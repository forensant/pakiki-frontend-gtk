namespace Pakiki {

    class RequestTextView : Gtk.Box {
        private SearchableSourceView searchable_source_view;
        private Gtk.TextView text_view;
        private SearchableHexEditor searchable_hex_editor;

        private ApplicationWindow application_window;
        private bool setting_selection;

        private bool _editable;
        public bool editable {
            get { return _editable; }
            set { 
                _editable = value;
                searchable_source_view.source_view.editable = value;
                text_view.editable = value;
                // hex_editor.editable = value;
            }
        }

        private bool _scroll = true;
        public bool scroll {
            get { return _scroll; }
            set { 
                _scroll = value;

                searchable_source_view.scroll = value;
                searchable_hex_editor.scroll = value;
            }
        }

        public bool is_hex_visible {
            get { return searchable_hex_editor.visible; }
        }

        public RequestTextView (ApplicationWindow application_window) {
            this.application_window = application_window;
            text_view = new Gtk.TextView ();
            text_view.monospace = true;
            text_view.wrap_mode = Gtk.WrapMode.CHAR;
            text_view.margin = 8;
            text_view.show ();
            text_view.expand = true;
            SyntaxHighlighter.set_tags(text_view.buffer);

            searchable_source_view = new SearchableSourceView (text_view);
            searchable_source_view.expand = true;
            searchable_source_view.show_all ();
            this.pack_start (searchable_source_view, true, true, 0);
            
            setting_selection = false;
            
            text_view.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, text_view.buffer);
            });

            searchable_hex_editor = new SearchableHexEditor ();
            searchable_hex_editor.show ();
            this.pack_start (searchable_hex_editor, true, true, 0);
        }

        public bool find_activated () {
            if (searchable_source_view.visible) {
                return searchable_source_view.find_activated ();
            }
            else if (searchable_hex_editor.visible) {
                return searchable_hex_editor.find_activated ();
            }

            return false;
        }

        private void on_request_response_popup (Gtk.Menu menu, Gtk.TextBuffer buffer) {
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
                var uri = "https://gchq.github.io/CyberChef/#input=" + GLib.Uri.escape_string (Base64.encode (selected_text.data));

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
            text_view.buffer.text = "";
            searchable_hex_editor.hex_editor.buffer = new HexStaticBuffer ();
            show_hex (false);
        }

        public void set_large_request (string guid, int64 content_length) {
            show_hex (true);
            if (searchable_hex_editor.hex_editor.buffer is HexRemoteBuffer) {
                var buf = searchable_hex_editor.hex_editor.buffer as HexRemoteBuffer;
                if (buf.guid == guid) {
                    buf.content_length = content_length;
                    return;
                }
            }

            searchable_hex_editor.hex_editor.buffer = new HexRemoteBuffer (application_window, guid, content_length);
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

            searchable_hex_editor.hex_editor.buffer = new HexStaticBuffer.from_bytes (full_hex_text.to_array ());
        }

        public void set_request(uchar[] request) {
            set_request_response (request, new uchar[1] { 0 });
        }

        public void set_request_response (uchar[] request, uchar[] response) {
            var str_request = (string)request;
            var str_response = (string)response;

            if (str_response.validate (response.length - 1, null) && str_request.validate (request.length - 1, null)) {
                set_text (str_request, str_response);
            } else {
                set_hex_text (request, response);
            }
        }

        private void set_text (string request, string response) {
            show_hex (false);
            var highlighter = new SyntaxHighlighter ();
            highlighter.set_highlightjs_tags (text_view.buffer, request + "\r\n\r\n\r\n\r\n" + response);
        }

        private void show_hex (bool show) {
            searchable_hex_editor.visible = show;
            searchable_source_view.visible = !show;
        }
    }
}