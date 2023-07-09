namespace Pakiki {   
    class RequestTextEditor : Gtk.TextView {
        public signal void long_running_task (bool running);

        private ApplicationWindow application_window;
        private SyntaxHighlighter syntax_highlighter = new SyntaxHighlighter ();

        public string direction = "request";

        public RequestTextEditor (ApplicationWindow application_window) {
            this.application_window = application_window;
            monospace = true;
            left_margin = right_margin = top_margin = bottom_margin = 6;
            wrap_mode = Gtk.WrapMode.CHAR;
            visible = true;
            syntax_highlighter.set_tags (buffer);
            this.populate_popup.connect (on_populate_popup);
            this.buffer.changed.connect (() => {
                on_text_changed (false);
            });
        }

        private void insert_oob_domain () {
            long_running_task (true);

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
                long_running_task (false);
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

        private void on_populate_popup (Gtk.Menu menu) {
            var separator = new Gtk.SeparatorMenuItem ();
            separator.show ();
            menu.append (separator);

            var menu_item_oob = new Gtk.MenuItem.with_label ("Insert out-of-band domain");
            menu_item_oob.activate.connect ( () => {
                insert_oob_domain ();
            });
            menu_item_oob.show ();
            menu.append (menu_item_oob);
            
            Gtk.TextIter selection_start, selection_end;
            var text_selected = buffer.get_selection_bounds (out selection_start, out selection_end);

            var title = "Send selection to CyberChef";
            var selected_text = "";
            if (text_selected) {
                selected_text = buffer.get_slice (selection_start, selection_end, true);
            } else {
                title = "Send " + direction + " to CyberChef";
                selected_text = buffer.text;
            }
            
            var menu_item_cyberchef = new Gtk.MenuItem.with_label (title);
            menu_item_cyberchef.activate.connect ( () => {
                var uri = "http://" + application_window.core_address + "/cyberchef/#input=" + GLib.Uri.escape_string (Base64.encode (selected_text.data));

                try {
                    AppInfo.launch_default_for_uri (uri, null);
                } catch (Error err) {
                    stdout.printf ("Could not launch CyberChef: %s\n", err.message);
                }
            });
            menu_item_cyberchef.show ();
            menu.append (menu_item_cyberchef);

            var menu_item_encode = new Gtk.MenuItem.with_label ("URL Encode");
            menu_item_encode.activate.connect ( () => {
                var encoded_text = GLib.Uri.escape_string (selected_text, "&+");
                this.replace_selected_text (encoded_text);
            });
            menu_item_encode.show ();
            menu.append (menu_item_encode);

            var menu_item_decode = new Gtk.MenuItem.with_label ("URL Decode");
            menu_item_decode.activate.connect ( () => {
                var decoded_text = GLib.Uri.unescape_string (selected_text);
                this.replace_selected_text (decoded_text);
            });
            menu_item_decode.show ();
            menu.append (menu_item_decode);
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