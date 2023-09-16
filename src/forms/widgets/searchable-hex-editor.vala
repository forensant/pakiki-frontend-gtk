
namespace Pakiki {
    class SearchableHexEditor : Gtk.Box {

        public HexEditor hex_editor;
        private Gtk.ScrolledWindow scrolled_window_hex_editor;
        private TextSearchBar search_bar;

        private bool _scroll = true;
        public bool scroll {
            get { return _scroll; }
            set { 
                _scroll = value;

                var vertical_policy = value ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER;
                var shadow_type = value ? Gtk.ShadowType.NONE : Gtk.ShadowType.IN;

                scrolled_window_hex_editor.vscrollbar_policy = vertical_policy;
                scrolled_window_hex_editor.shadow_type = shadow_type;
            }
        }

        public SearchableHexEditor (ApplicationWindow application_window) {
            this.orientation = Gtk.Orientation.VERTICAL;
            scrolled_window_hex_editor = new Gtk.ScrolledWindow (null, null);
            scrolled_window_hex_editor.show ();

            hex_editor = new HexEditor (application_window);
            hex_editor.expand = true;
            hex_editor.show ();
            scrolled_window_hex_editor.add (hex_editor);

            search_bar = new TextSearchBar ();
            search_bar.format_visible = true;

            search_bar.search_next.connect (on_next_pushed);

            search_bar.search_prev.connect (() => {
                var sr = hex_editor.buffer.prev_search_result ();
                hex_editor.set_char_selection (sr.start_offset, sr.end_offset);
                update_count ();
            });

            search_bar.stop.connect (() => {
                search_bar.search_mode_enabled = false;
                hex_editor.grab_focus ();
            });

            search_bar.text_changed.connect (() => {
                search_bar.spinner_visible = true;
                hex_editor.buffer.search (search_bar.text, search_bar.format);
            });

            hex_editor.buffer_assigned.connect (() => {
                hex_editor.buffer.search_results_available.connect (on_search_results_available);
            });

            search_bar.show ();

            this.pack_start (search_bar, false, false, 0);
            this.pack_start (scrolled_window_hex_editor, true, true, 0);
        }

        public bool find_activated () {
            if (!search_bar.text_has_focus () && !hex_editor.has_focus) {
                return false;
            }

            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;
            search_bar.show_close_button = true;

            if (search_bar.search_mode_enabled) {
                search_bar.find_activated ();
            } else {
                hex_editor.grab_focus ();
            }
    
            return true;
        }

        private void on_next_pushed () {
            var sr = hex_editor.buffer.next_search_result ();
            hex_editor.set_char_selection (sr.start_offset, sr.end_offset);
            update_count ();
        }

        private void on_search_results_available () {
            search_bar.spinner_visible = false;
            if (hex_editor.buffer.search_result_count () != 0) {
                on_next_pushed ();
            }
            else {
                update_count ();
            }
        }

        private void update_count () {
            var current_selection = hex_editor.buffer.search_result_selection ();
            var total = hex_editor.buffer.search_result_count ();
            
            if (search_bar.text == "") {
                search_bar.clear_search_count ();
            }
            else if (total == 0) {
                search_bar.set_no_results ();
            }
            else {
                search_bar.set_count (current_selection, total);
            }
        }
    }
}
