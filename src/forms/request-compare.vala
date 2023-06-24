namespace Pakiki {
    class RequestCompare : Gtk.Notebook {
        private ApplicationWindow application_window;

        private Gtk.Label label_error;
        private Gtk.Paned paned_preview;
        private Gtk.Paned paned_text;
        private RequestDiff request_diff_1;
        private RequestDiff request_diff_2;
        private RequestPreview request_preview_1;
        private RequestPreview request_preview_2;
        private Gtk.ScrolledWindow scrolled_window_request_differences;
        private Gtk.ScrolledWindow scrolled_window_request_preview;

        public RequestCompare(ApplicationWindow application_window) {
            this.application_window = application_window;
            
            request_diff_1 = new RequestDiff ();
            request_diff_2 = new RequestDiff ();

            request_diff_1.show ();
            request_diff_2.show ();

            scrolled_window_request_differences = new Gtk.ScrolledWindow (null, null);
            scrolled_window_request_differences.show ();

            var separator_diff = new Gtk.Separator (Gtk.Orientation.VERTICAL);
            separator_diff.show ();

            var box_diff = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box_diff.pack_start (request_diff_1, true, true, 0);
            box_diff.pack_start (separator_diff, false, false, 0);
            box_diff.pack_start (request_diff_2, true, true, 0);
            box_diff.expand = true;
            box_diff.show ();

            scrolled_window_request_differences.add (box_diff);

            this.append_page (scrolled_window_request_differences, new Gtk.Label ("Text"));

            request_preview_1 = new RequestPreview (application_window);
            request_preview_2 = new RequestPreview (application_window);

            request_preview_1.show ();
            request_preview_2.show ();

            scrolled_window_request_preview = new Gtk.ScrolledWindow (null, null);

            var separator_prev = new Gtk.Separator (Gtk.Orientation.VERTICAL);
            separator_prev.show ();

            var box_prev = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box_prev.pack_start (request_preview_1, true, true, 0);
            box_prev.pack_start (separator_prev, false, false, 0);
            box_prev.pack_start (request_preview_2, true, true, 0);
            box_prev.expand = true;
            box_prev.show ();
            
            scrolled_window_request_preview.add (box_prev);
            scrolled_window_request_preview.show ();

            this.append_page (scrolled_window_request_preview, new Gtk.Label ("Preview"));
            
            label_error = new Gtk.Label ("");
            label_error.expand = true;
            this.append_page (label_error, new Gtk.Label ("Text"));
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
                            label_error.label = "Error loading differences 1: " + err.message;
                            label_error.show ();
                            return;
                        }
                    });
                } catch (Error err) {
                    scrolled_window_request_differences.hide ();
                    scrolled_window_request_preview.hide ();
                    label_error.label = "Error loading differences 2: " + err.message;
                    label_error.show ();
                    return;
                }                
            });
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
                            response_to_use += '\0';

                            if (request_preview_id == 1) {
                                request_preview_1.set_content (response_to_use, mimetype, url);
                            } else {
                                request_preview_2.set_content (response_to_use, mimetype, url);
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
