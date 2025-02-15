namespace Pakiki {
    class RequestCompare : Gtk.Box {
        private ApplicationWindow application_window;

        private Gtk.Label label_error;
        private Gtk.Notebook notebook;
        private RequestDiff request_diff_1;
        private RequestDiff request_diff_2;
        private RequestPreview request_preview_1;
        private RequestPreview request_preview_2;
        private Gtk.ScrolledWindow scrolled_window_request_differences;
        private Gtk.ScrolledWindow scrolled_window_request_preview;

        public RequestCompare(ApplicationWindow application_window) {
            this.application_window = application_window;

            notebook = new Gtk.Notebook ();
            this.append (notebook);
            
            request_diff_1 = new RequestDiff ();
            request_diff_2 = new RequestDiff ();

            request_diff_1.hexpand = true;
            request_diff_2.hexpand = true;

            request_diff_1.show ();
            request_diff_2.show ();

            scrolled_window_request_differences = new Gtk.ScrolledWindow ();
            scrolled_window_request_differences.show ();

            var separator_diff = new Gtk.Separator (Gtk.Orientation.VERTICAL);
            separator_diff.show ();

            var box_diff = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box_diff.append (request_diff_1);
            box_diff.append (separator_diff);
            box_diff.append (request_diff_2);
            box_diff.set_hexpand (true);
            box_diff.show ();

            scrolled_window_request_differences.set_child (box_diff);

            notebook.append_page (scrolled_window_request_differences, new Gtk.Label ("Text"));

            request_preview_1 = new RequestPreview (application_window);
            request_preview_2 = new RequestPreview (application_window);

            scrolled_window_request_preview = new Gtk.ScrolledWindow ();

            var separator_prev = new Gtk.Separator (Gtk.Orientation.VERTICAL);
            separator_prev.show ();

            var box_prev = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box_prev.append (request_preview_1);
            box_prev.append (separator_prev);
            box_prev.append (request_preview_2);
            box_prev.set_vexpand (true);
            box_prev.show ();
            
            scrolled_window_request_preview.set_child (box_prev);
            scrolled_window_request_preview.show ();

            notebook.append_page (scrolled_window_request_preview, new Gtk.Label ("Preview"));
            
            label_error = new Gtk.Label ("");
            label_error.set_hexpand (true);
            notebook.append_page (label_error, new Gtk.Label ("Text"));
        }

        public void compare_requests (string base_guid, string compare_guid) {
            var url = "http://" + application_window.core_address + "/requests/" + base_guid + "/compare/" + compare_guid;
            var message = new Soup.Message ("GET", url);

            application_window.http_session.send_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_async.end (res);

                    if (message.status_code != 200) {
                        var buffer = new uint8[10240];
                        size_t bytes_read;

                        var error_message = "The status code was: " + message.status_code.to_string ();
                    
                        if (response.read_all (buffer, out bytes_read, null)) {
                            error_message = (string) buffer;
                        }
                        throw new IOError.CONNECTION_REFUSED ("Could not compare requests: " + error_message);
                    }

                    var parser = new Json.Parser ();
                    parser.load_from_stream_async.begin (response, null, (obj2, res2) => {
                        try {
                            parser.load_from_stream_async.end (res2);

                            var root_array = parser.get_root ().get_array ();

                            request_diff_1.set_diff (root_array, 1);
                            request_diff_2.set_diff (root_array, 2);
        
                            load_web_preview (base_guid, 1);
                            load_web_preview (compare_guid, 2);
        
                            label_error.hide ();
                            scrolled_window_request_differences.show ();
                            scrolled_window_request_preview.show ();
                        } catch (Error err) {
                            scrolled_window_request_differences.hide ();
                            scrolled_window_request_preview.hide ();
                            label_error.label = "Error loading differences: " + err.message;
                            label_error.show ();
                            return;
                        }
                    });
                } catch (Error err) {
                    scrolled_window_request_differences.hide ();
                    scrolled_window_request_preview.hide ();
                    label_error.label = err.message;
                    label_error.show ();
                    return;
                }                
            });
        }

        private Bytes parse_body (uchar[] full_response) {
            int offset = -1;
            for (int i = 0; i < full_response.length - 4; i++) {
                if (full_response[i] == '\r' && full_response[i + 1] == '\n' && full_response[i + 2] == '\r' && full_response[i + 3] == '\n') {
                    offset = i + 4;
                    break;
                }
            }

            if (offset == -1) {
                return new Bytes(null);
            }

            return new Bytes (full_response[offset:full_response.length]);
        }

        private void load_web_preview (string guid, int request_preview_id) {
            var message = new Soup.Message ("GET", "http://" + application_window.core_address + "/requests/" + guid + "/contents");

            application_window.http_session.send_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_async.end (res);

                    if (message.status_code != 200) {
                        throw new IOError.CONNECTION_REFUSED ("Could not load request contents");
                    }

                    var parser = new Json.Parser ();
                    parser.load_from_stream_async.begin (response, null, (obj2, res2) => {
                        try {
                            parser.load_from_stream_async.end (res2);

                            var root_obj = parser.get_root ().get_object ();

                            var original_response = Base64.decode (root_obj.get_string_member ("Response"));
                            var modified_response = Base64.decode (root_obj.get_string_member ("ModifiedResponse"));

                            var url = root_obj.get_string_member ("URL");
                            var mimetype = root_obj.get_string_member ("MimeType");

                            var response_to_use = original_response;
                            if (modified_response.length != 0) {
                                response_to_use = modified_response;
                            }
                
                            var response_bytes = parse_body(response_to_use);
                
                            if (request_preview_id == 1) {
                                request_preview_1.set_content (response_bytes, mimetype, url);
                            } else {
                                request_preview_2.set_content (response_bytes, mimetype, url);
                            }

                            scrolled_window_request_preview.visible = (request_preview_1.has_content || request_preview_2.has_content);
                        } catch (Error err) {
                            stdout.printf ("Could not parse JSON data, error: %s\n", err.message);
                        }
                    });
                } catch (Error err) {
                    stdout.printf ("Could not load request contents: %s\n", err.message);
                }
            });
        }
    }
}
