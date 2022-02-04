namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-text-view.ui")]
    class RequestTextView : Gtk.Box {
        [GtkChild]
        private unowned Gtk.SourceView source_view;
        [GtkChild]
        private Gtk.TextView text_view_hex_count;
        [GtkChild]
        private Gtk.TextView text_view_hex;
        [GtkChild]
        private Gtk.TextView text_view_ascii;

        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_source_view;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex_count;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_ascii;

        // for the requests/responses where we can render them
        private Gtk.SourceLanguageManager language_manager;
        private Gtk.SourceBuffer source_buffer;

        private bool setting_selection;

        private bool _editable;
        public bool editable {
            get { return _editable; }
            set { 
                _editable = value;
                source_view.editable = value; 
                text_view_hex.editable = value;
                text_view_ascii.editable = value;
            }
        }

        private bool _scroll = true;
        public bool scroll {
            get { return _scroll; }
            set { 
                _scroll = value;
                var vertical_policy = value ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER;
                scrolled_window_source_view.vscrollbar_policy = vertical_policy;
                scrolled_window_hex_count.vscrollbar_policy = vertical_policy;
                scrolled_window_hex.vscrollbar_policy = vertical_policy;
                scrolled_window_ascii.vscrollbar_policy = vertical_policy;

                scrolled_window_source_view.shadow_type = value ? Gtk.ShadowType.NONE : Gtk.ShadowType.IN;
            }
        }
        
        public RequestTextView () {
            setting_selection = false;
            language_manager = Gtk.SourceLanguageManager.get_default ();
            var lang = language_manager.get_language ("xml");

            source_buffer = new Gtk.SourceBuffer.with_language (lang);
            source_view.buffer = source_buffer;
            
            source_view.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, source_buffer, false);
            });

            text_view_hex.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, text_view_hex.buffer, true);
            });

            text_view_ascii.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, text_view_ascii.buffer, true);
            });
        }

        private void on_request_response_popup (Gtk.Menu menu, Gtk.TextBuffer buffer, bool strip_newlines) {
            Gtk.TextIter selection_start, selection_end;
            var text_selected = buffer.get_selection_bounds (out selection_start, out selection_end);

            if (!text_selected) {
                return;
            }

            var separator = new Gtk.SeparatorMenuItem ();
            separator.show ();
            menu.append (separator);

            var menu_item = new Gtk.MenuItem.with_label ("Send to Cyberchef");
            menu_item.activate.connect ( () => {
                var selected_text = buffer.get_slice (selection_start, selection_end, true);
                if (strip_newlines) {
                    selected_text = selected_text.replace ("\n", "");
                }
                var uri = "https://gchq.github.io/CyberChef/#input=" + Soup.URI.encode (Base64.encode (selected_text.data), "");

                try {
                    AppInfo.launch_default_for_uri (uri, null);
                } catch (Error err) {
                    stdout.printf ("Could not launch Cyberchef: %s\n", err.message);
                }
            });
            menu_item.show ();
            menu.append (menu_item);
        }

        public void reset_state () {
            source_buffer.text = "";
            text_view_hex_count.buffer.text = "";
            text_view_hex.buffer.text = "";
            text_view_ascii.buffer.text = "";
            show_hex (false);
        }

        private void set_hex_ascii (Gee.ArrayList<uchar> hex_text) {
            var text_to_set = new StringBuilder ();

            for (var i = 0; i < hex_text.size; i++) {
                var hex_char = hex_text[i];
                if (hex_char < 32 || hex_char > 126) {
                    hex_char = '.';
                }

                var formatted_string = "%c".printf (hex_char);
                if (i % 16 == 15) {
                    formatted_string += "\n";
                } else if (i % 8 == 7) {
                    formatted_string += " ";
                }

                text_to_set.append (formatted_string);
            }

            text_view_ascii.buffer.text = text_to_set.str;
        }

        private void set_hex_side_count (int count) {
            text_view_hex_count.buffer.text = "";
            var lines = count / 16;
            if (lines * 16 < count) {
                lines++;
            }

            var text_to_set = new StringBuilder ();

            for (int i = 0; i < lines; i++) {
                var formatted_string = "%08d\n".printf(i * 16);
                text_to_set.append (formatted_string);
            }

            text_view_hex_count.buffer.insert_at_cursor(text_to_set.str, (int)text_to_set.len);
        }

        private void set_hex_main (Gee.ArrayList<uchar> hex_text) {
            var text_to_set = new StringBuilder ();

            for (var i = 0; i < hex_text.size; i++) {
                var formatted_string = "%02x".printf(hex_text[i]);
                if (i % 16 == 15) {
                    formatted_string += "\n";
                } else if (i % 8 == 7) {
                    formatted_string += "   ";
                } else {
                    formatted_string += " ";
                }

                text_to_set.append (formatted_string);
            }

            text_view_hex.buffer.text = text_to_set.str;
        }

        private void set_hex_text (uchar[] request, uchar[] response) {
            show_hex (true);

            var full_hex_text = new Gee.ArrayList<uchar> ();
            for (var i = 0; i < request.length; i++) {
                full_hex_text.add (request[i]);
            }
            if (request.length == 0 || response.length == 0) {
                full_hex_text.add ('\n');
                full_hex_text.add ('\n');
            }
            for (var i = 0; i < response.length; i++) {
                full_hex_text.add (response[i]);
            }

            set_hex_side_count (full_hex_text.size);
            set_hex_main (full_hex_text);
            set_hex_ascii (full_hex_text);
        }

        public void set_request(uchar[] request) {
            set_request_response (request, new uchar[1] { 0 });
        }

        public void set_request_response (uchar[] request, uchar[] response) {
            var str_request = (string)request;
            var str_response = (string)response;

            if (str_response.make_valid () != str_response || str_request.make_valid () != str_request) {
                set_hex_text (request, response);
            } else {
                set_text (str_request, str_response);
            }
        }

        private void set_sourceview_language (string response) {
            var language = "html";

            try {
                var re = new Regex ("\\s*Content-Type: [/A-Za-z0-9]*\\s*");
                GLib.MatchInfo match_info;
                var match_found = re.match (response, 0, out match_info);
                
                
                if (match_found && match_info.get_match_count () >= 1) {
                    var content_type = match_info.fetch (0);
                    if (content_type != null) {
                        if (content_type.contains ("javascript")) {
                            language = "javascript";
                        } else if (content_type.contains ("css") || content_type.contains ("stylesheet")) {
                            language = "css";
                        }
                    }
                }
            } catch (Error e) {
                stderr.printf ("Could not get the language of the response: %s\n", e.message);
            }

            source_buffer.language = language_manager.get_language (language);
        }

        private void set_text (string request, string response) {
            show_hex (false);
            set_sourceview_language (request);
            var newlines = _scroll ? "\n\n" : "";
            source_buffer.text = request.make_valid () + newlines + response.make_valid ();
        }

        private void show_hex (bool show) {
            scrolled_window_hex_count.visible = show;
            scrolled_window_hex.visible = show;
            scrolled_window_ascii.visible = show;
            scrolled_window_source_view.visible = !show;
        }

    }
}