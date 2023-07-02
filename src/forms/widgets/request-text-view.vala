namespace Pakiki {

    class RequestTextView : Gtk.Box {
        private Gtk.Box box_search_container;
        private Gtk.Paned pane_text;
        private Gtk.TextView text_view_request;
        private Gtk.TextView text_view_response;
        private SearchableHexEditor searchable_hex_editor;
        private Gtk.ScrolledWindow scroll_view_request;
        private Gtk.ScrolledWindow scroll_view_response;
        private TextSearchBar search_bar;

        private Gtk.TextView text_view_placeholder;

        private int search_total_count;
        private int search_upto;

        private ApplicationWindow application_window;
        private bool setting_selection;

        private bool _editable;
        public bool editable {
            get { return _editable; }
            set { 
                _editable = value;
                text_view_request.editable = value;
                text_view_response.editable = value;
                // hex_editor.editable = value;
            }
        }

        public bool is_hex_visible {
            get { return searchable_hex_editor.visible; }
        }

        public RequestTextView (ApplicationWindow application_window) {
            box_search_container = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            search_bar = new TextSearchBar ();
            search_bar.format_visible = false;
            search_bar.search_next.connect (this.search_next);
            search_bar.search_prev.connect (this.search_prev);
            search_bar.stop.connect (this.search_stop);
            search_bar.text_changed.connect (this.search_text_changed);
            box_search_container.pack_start (search_bar, false, false);

            this.application_window = application_window;
            text_view_request = new Gtk.TextView (); 
            text_view_request.wrap_mode = Gtk.WrapMode.CHAR;
            text_view_request.monospace = true;
            text_view_request.wrap_mode = Gtk.WrapMode.CHAR;
            text_view_request.margin = 8;
            text_view_request.visible = true;
            SyntaxHighlighter.set_tags(text_view_request.buffer);

            text_view_response = new Gtk.TextView ();
            text_view_response.wrap_mode = Gtk.WrapMode.CHAR;
            text_view_response.monospace = true;
            text_view_response.wrap_mode = Gtk.WrapMode.CHAR;
            text_view_response.margin = 8;
            text_view_response.visible = true;
            SyntaxHighlighter.set_tags(text_view_response.buffer);

            scroll_view_request = new Gtk.ScrolledWindow (null, null);
            scroll_view_request.expand = true;
            scroll_view_request.visible = true;
            scroll_view_request.child = text_view_request;

            scroll_view_response = new Gtk.ScrolledWindow (null, null);
            scroll_view_response.expand = true;
            scroll_view_response.visible = true;
            scroll_view_response.child = text_view_response;

            pane_text = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            pane_text.expand = true;

            pane_text.pack1 (scroll_view_request, true, true);
            pane_text.pack2 (scroll_view_response, true, true);
            pane_text.position = 350;
            pane_text.visible = true;
            
            box_search_container.pack_start (pane_text, true, true);
            box_search_container.hide ();

            text_view_placeholder = new Gtk.TextView ();
            text_view_placeholder.expand = true;
            text_view_placeholder.editable = false;

            this.pack_start (box_search_container, true, true, 0);
            this.pack_start (text_view_placeholder, true, true, 0);
            
            setting_selection = false;
            
            text_view_request.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, text_view_request.buffer);
            });

            text_view_response.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, text_view_response.buffer);
            });

            searchable_hex_editor = new SearchableHexEditor ();
            searchable_hex_editor.show ();
            this.pack_start (searchable_hex_editor, true, true, 0);
        }

        public bool find_activated () {
            if (text_view_request.is_focus || text_view_response.is_focus) {
                
                search_bar.search_mode_enabled = !search_bar.search_mode_enabled;

                if (search_bar.search_mode_enabled) {
                    search_bar.find_activated ();
                } else {
                    text_view_response.grab_focus ();
                }

                return true;
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
            text_view_request.buffer.text = "";
            text_view_response.buffer.text = "";
            searchable_hex_editor.hex_editor.buffer = new HexStaticBuffer ();
            searchable_hex_editor.visible = false;
            box_search_container.visible = false;
            text_view_placeholder.visible = true;
        }

        private int delete_search_mark () {
            int found_in = 0;
            var prev_mark = text_view_request.buffer.get_mark ("search");
            if (prev_mark != null) {
                text_view_request.buffer.delete_mark (prev_mark);
            }

            prev_mark = text_view_response.buffer.get_mark ("search");
            if (prev_mark != null) {
                text_view_response.buffer.delete_mark (prev_mark);
                found_in = 1;
            }

            return found_in;
        }

        private void search_next () {
            search_upto++;

            if (search_upto >= search_total_count) {
                search_upto = 0;
                delete_search_mark ();
            }

            search (true);
        }

        private void search_prev () {
            search_upto--;

            if (search_upto <= -1) {
                search_upto = search_total_count - 1;
                delete_search_mark ();
            }

            search (false);
        }

        private int count_search_results (Gtk.TextView text_view) {
            Gtk.TextIter iter_start, iter_end;
            text_view.buffer.get_start_iter (out iter_start);
            text_view.buffer.get_end_iter (out iter_end);

            var found = true;
            int count = 0;
            while (found) {
                found = iter_start.forward_search  (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
                if (found) {
                    iter_start = iter_end;
                    count++;
                }
            }

            return count;
        }

        private void search_text_changed () {
            delete_search_mark ();

            if (search_bar.text == "") {
                search_bar.clear_search_count ();
            }
            else {
                search_upto = -1;
                search_total_count = count_search_results (text_view_request) + count_search_results (text_view_response);
                
                if (search_total_count == 0) {
                    search_bar.set_no_results ();
                }
            }

            search_next ();
        }

        private void search_stop () {
            search_bar.search_mode_enabled = false;

            int found_in = delete_search_mark ();

            if (found_in == 0) {
                text_view_request.grab_focus ();
            }
            else {
                text_view_response.grab_focus ();
            }
        }

        void search(bool forward) {
            var text_view = text_view_request;
            if (text_view_response.buffer.get_mark ("search") != null) {
                text_view = text_view_response;
            }

            if (!forward && search_upto == search_total_count - 1) {
                text_view = text_view_response;
            }

            var prev_mark = text_view.buffer.get_mark ("search");

            Gtk.TextIter iter_start;
            Gtk.TextIter iter_end;

            if (prev_mark == null) {
                if (forward) {
                    text_view.buffer.get_start_iter (out iter_start);
                }
                else {
                    text_view.buffer.get_end_iter (out iter_start);
                }
            }
            else {
                text_view.buffer.get_iter_at_mark (out iter_start, prev_mark);
                text_view.buffer.delete_mark (prev_mark);
            }
            iter_end = iter_start;

            var found = false;
            if (forward) {
                found = iter_start.forward_search  (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
            } else {
                iter_start.backward_char ();
                found = iter_start.backward_search (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
            }
            
            if (search_bar.text == "") {
                return;
            }
            
            if (!found) {
                // search on the other text view
                if (text_view == text_view_request) {
                    text_view = text_view_response;
                }
                else {
                    text_view = text_view_request;
                }

                if (forward) {
                    text_view.buffer.get_start_iter (out iter_start);
                }
                else {
                    text_view.buffer.get_end_iter (out iter_start);
                }
                iter_end = iter_start;

                if (forward) {
                    found = iter_start.forward_search  (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
                } else {
                    iter_start.backward_char ();
                    found = iter_start.backward_search (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
                }

                if (found && text_view == text_view_response && !forward) {
                    search_upto = search_total_count - 2;
                }
            }
            
            if (found) {
                text_view.buffer.select_range (iter_start, iter_end);
                var mark = text_view.buffer.create_mark ("search", iter_end, true);
                text_view.scroll_mark_onscreen (mark);
                search_bar.set_count (search_upto + 1, search_total_count); // as it's 0-indexed
            }
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

        private Cancellable cancellable = new Cancellable();
        private void set_text (string request, string response) {
            show_hex (false);
            cancellable.cancel ();
            var highlighter = new SyntaxHighlighter ();
            cancellable.reset ();
            highlighter.set_highlightjs_tags (text_view_request.buffer, request, cancellable);
            highlighter.set_highlightjs_tags (text_view_response.buffer, response, cancellable);
        }

        private void show_hex (bool show) {
            searchable_hex_editor.visible = show;
            box_search_container.visible = !show;
            scroll_view_request.visible = !show;
            scroll_view_response.visible = !show;
            text_view_request.visible = !show;
            text_view_response.visible = !show;
            text_view_placeholder.visible = false;
        }
    }
}
