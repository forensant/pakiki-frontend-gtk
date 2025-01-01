namespace Pakiki {   
    class RequestTextEditor : GtkSource.View {
        public signal void long_running_task (bool running);

        private ApplicationWindow application_window;
        private GtkSource.Buffer source_buffer = new GtkSource.Buffer (null);
        private SyntaxHighlighter syntax_highlighter = new SyntaxHighlighter ();
        public string direction = "request";
        private string guid = "";
        private string protocol = "";
        private string url = "";

        public RequestTextEditor (ApplicationWindow application_window) {
            this.application_window = application_window;
            this.buffer = source_buffer;
            monospace = true;
            left_margin = right_margin = top_margin = bottom_margin = 6;
            wrap_mode = Gtk.WrapMode.CHAR;
            visible = true;
            syntax_highlighter.set_tags (buffer);
            this.extra_menu = get_request_popup_menu ();
            this.buffer.changed.connect (() => {
                on_text_changed (false);
            });

            this.install_action ("request-editor.send-to-cyberchef", null, on_send_to_cyberchef);
            this.install_action ("request-editor.insert-oob-domain", null, insert_oob_domain);
            this.install_action ("request-editor.url_encode", null, (widget) => {
                var editor = (RequestTextEditor)widget;
                var buffer = editor.buffer;

                Gtk.TextIter start, end;
            
                var selection = buffer.get_selection_bounds (out start, out end);
                if (selection && start != end) {
                    var selected_text = buffer.get_slice (start, end, true);
                    var encoded_text = GLib.Uri.escape_string (selected_text, "&+");
                    editor.replace_selected_text (encoded_text);
                }
            });

            this.install_action ("request-editor.url_decode", null, (widget) => {
                var editor = (RequestTextEditor)widget;
                var buffer = editor.buffer;

                Gtk.TextIter start, end;

                var selection = buffer.get_selection_bounds (out start, out end);
                if (selection && start != end) {
                    var selected_text = buffer.get_slice (start, end, true);
                    var decoded_text = GLib.Uri.unescape_string (selected_text);
                    editor.replace_selected_text (decoded_text);
                }
            });
        }

        private GLib.MenuModel get_request_popup_menu () {
            this.action_set_enabled ("request-editor.insert-oob-domain", this.editable);
            this.action_set_enabled ("request-editor.url_encode", this.editable);
            this.action_set_enabled ("request-editor.url_decode", this.editable);

            var cs_menu = new GLib.Menu ();
            cs_menu.append ("Insert out-of-band domain", "request-editor.insert-oob-domain");
            cs_menu.append ("Send to CyberChef", "request-editor.send-to-cyberchef");
            cs_menu.append ("URL Encode", "request-editor.url_encode");
            cs_menu.append ("URL Decode", "request-editor.url_decode");

            var root_menu = new GLib.Menu ();
            root_menu.append_section (null, cs_menu);
            if (guid != "" && protocol != "" && url != "") {
                root_menu.append_section (null, RequestDetails.populate_send_to_menu (application_window, guid, protocol, url));
            }
            return root_menu;
        }

        private static void insert_oob_domain (Gtk.Widget widget, string action_name, Variant? parameter) {
            var editor = (RequestTextEditor)widget;
            var buffer = editor.buffer;
            var application_window = editor.application_window;

            editor.long_running_task (true);
            
            var url = "http://" + application_window.core_address + "/out_of_band/url";

            var message = new Soup.Message ("GET", url);

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                if (message.status_code == 200) {
                    try {
                        var bytes = application_window.http_session.send_and_read_async.end (res);
                        var domain = (string) bytes.get_data ();
                        buffer.begin_user_action ();
                        buffer.delete_selection (true, true);
                        buffer.insert_at_cursor (domain, domain.length);
                        buffer.end_user_action ();
                    }
                    catch (Error err) {
                        stdout.printf ("Could not insert out-of-band domain: %s\n", err.message);
                    }
                }
                editor.long_running_task (false);
            });
        }

        private string prev_text = "";
        public void on_text_changed (bool force_refresh = false) {
            if ((prev_text == buffer.text || buffer.text.chomp () == "") && !force_refresh) {
                return;
            }

            if (buffer.text.chomp () == "") {
                return;
            }

            prev_text = buffer.text;

            if(application_window.core_address == "") {
                return;
            }

            var url = "http://" + application_window.core_address + "/requests/highlight";
            var message = new Soup.Message ("POST", url);
            var encoded_text = Base64.encode (buffer.text.data);
            message.set_request_body_from_bytes ("text/text", new Bytes (encoded_text.data));

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                if (message.status_code == 200) {
                    try {
                        var bytes = application_window.http_session.send_and_read_async.end (res);
                        
                        if (bytes.get_data () == null) {
                            return;
                        }
                        
                        var html = (string) Base64.decode ((string) bytes.get_data());
                        if (html == "" || prev_text != buffer.text) {
                            return;
                        }

                        syntax_highlighter.set_highlightjs_tags (buffer, html, null, false);
                    } catch (Error err) {
                        stdout.printf ("Could not syntax highlight text: %s\n", err.message);
                    }
                }
            });
        }

        private static void on_send_to_cyberchef (Gtk.Widget widget, string action_name, Variant? parameter) {
            var editor = (RequestTextEditor)widget;
            var buffer = editor.buffer;
            var application_window = editor.application_window;

            Gtk.TextIter selection_start, selection_end;
            var text_selected = buffer.get_selection_bounds (out selection_start, out selection_end);

            var text_to_encode = "";
            if (text_selected) {
                text_to_encode = buffer.get_slice (selection_start, selection_end, true);
            } else {
                text_to_encode = buffer.text;
            }

            var uri = "http://" + application_window.core_address + "/cyberchef/#input=" + GLib.Uri.escape_string (Base64.encode (text_to_encode.data));

            try {
                AppInfo.launch_default_for_uri (uri, null);
            } catch (Error err) {
                stdout.printf ("Could not launch CyberChef: %s\n", err.message);
            }
        }

        public void set_request_details (string guid, string protocol, string url) {
            this.guid = guid;
            this.protocol = protocol;
            this.url = url;

            this.extra_menu = get_request_popup_menu ();
        }

        private void replace_selected_text (string new_text) {            
            buffer.delete_selection (true, true);
            buffer.insert_at_cursor (new_text, new_text.length);

            Gtk.TextIter selection_start, selection_end;
            buffer.get_selection_bounds (out selection_start, out selection_end);
            selection_start.backward_chars (new_text.length);
            buffer.select_range (selection_start, selection_end);
        }
    }
}