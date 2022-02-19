namespace Proximity {   
    class RequestTextEditor : Gtk.SourceView {
        public signal void long_running_task (bool running);

        private ApplicationWindow application_window;

        public RequestTextEditor (ApplicationWindow application_window) {
            this.application_window = application_window;
            monospace = true;
            left_margin = right_margin = top_margin = bottom_margin = 6;
            wrap_mode = Gtk.WrapMode.CHAR;
            visible = true;
            this.populate_popup.connect (on_populate_popup);
        }

        private void insert_oob_domain () {
            long_running_task (true);

            var url = "http://" + application_window.core_address + "/proxy/out_of_band/url";

            var message = new Soup.Message ("GET", url);

            application_window.http_session.queue_message (message, (sess, mess) => {
                if (message.status_code == 200) {
                    var domain = (string) message.response_body.flatten ().data;
                    buffer.insert_at_cursor (domain, domain.length);
                }

                long_running_task (false);
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

            if (!text_selected) {
                return;
            }

            var selected_text = buffer.get_slice (selection_start, selection_end, true);

            var menu_item_cyberchef = new Gtk.MenuItem.with_label ("Send to Cyberchef");
            menu_item_cyberchef.activate.connect ( () => {
                var uri = "https://gchq.github.io/CyberChef/#input=" + Soup.URI.encode (Base64.encode (selected_text.data), "");

                try {
                    AppInfo.launch_default_for_uri (uri, null);
                } catch (Error err) {
                    stdout.printf ("Could not launch Cyberchef: %s\n", err.message);
                }
            });
            menu_item_cyberchef.show ();
            menu.append (menu_item_cyberchef);

            var menu_item_encode = new Gtk.MenuItem.with_label ("URL Encode");
            menu_item_encode.activate.connect ( () => {
                var encoded_text = Soup.URI.encode (selected_text, null);
                this.replace_selected_text (encoded_text);
            });
            menu_item_encode.show ();
            menu.append (menu_item_encode);

            var menu_item_decode = new Gtk.MenuItem.with_label ("URL Decode");
            menu_item_decode.activate.connect ( () => {
                var decoded_text = Soup.URI.decode (selected_text);
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