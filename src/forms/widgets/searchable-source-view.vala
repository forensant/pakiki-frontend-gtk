namespace Proximity {
    [GtkTemplate (ui = "/com/forensant/proximity/searchable-source-view.ui")]
    public class SearchableSourceView : Gtk.Box {
        
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_source_view;

        [GtkChild]
        public unowned Gtk.SourceView source_view;

        private TextSearchBar search_bar;

        private bool _scroll = true;
        public bool scroll {
            get { return _scroll; }
            set { 
                _scroll = value;

                var vertical_policy = value ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER;
                var shadow_type = value ? Gtk.ShadowType.NONE : Gtk.ShadowType.IN;

                scrolled_window_source_view.vscrollbar_policy = vertical_policy;
                scrolled_window_source_view.shadow_type = shadow_type;
            }
        }

        public SearchableSourceView () {
            search_bar = new TextSearchBar ();
            this.pack_start (search_bar, false, false, 0);

            search_bar.format_visible = false;
            search_bar.search_next.connect (this.search_next);
            search_bar.search_prev.connect (this.search_prev);
            search_bar.stop.connect (this.search_stop);
            search_bar.text_changed.connect (this.search_text_changed);
        }

        public bool find_activated () {
            if (!search_bar.text_has_focus () && !source_view.has_focus) {
                return false;
            }

            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;

            if (search_bar.search_mode_enabled) {
                search_bar.find_activated ();
            } else {
                source_view.grab_focus ();
            }

            return true;
        }

        private void search_next () {
            search (true);
        }

        private void search_prev () {
            search (false);
        }

        private void search_text_changed () {
            var prev_mark = source_view.buffer.get_mark ("search");
            if (prev_mark != null) {
                source_view.buffer.delete_mark (prev_mark);
            }

            search_next ();
        }

        private void search_stop () {
            search_bar.search_mode_enabled = false;

            var prev_mark = source_view.buffer.get_mark ("search");
            if (prev_mark != null) {
                source_view.buffer.delete_mark (prev_mark);
            }
            
            source_view.grab_focus ();
        }

        void search(bool forward) {
            var prev_mark = source_view.buffer.get_mark ("search");

            Gtk.TextIter iter_start;
            Gtk.TextIter iter_end;

            if (prev_mark == null) {
                if (forward) {
                    source_view.buffer.get_start_iter (out iter_start);
                }
                else {
                    source_view.buffer.get_end_iter (out iter_start);
                }
            }
            else {
                source_view.buffer.get_iter_at_mark (out iter_start, prev_mark);
                source_view.buffer.delete_mark (prev_mark);
            }
            iter_end = iter_start;

            var found = false;
            if (forward) {
                found = iter_start.forward_search  (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
            } else {
                iter_start.backward_char ();
                found = iter_start.backward_search (search_bar.text, Gtk.TextSearchFlags.CASE_INSENSITIVE, out iter_start, out iter_end, null);
            }
            
            if (!found || search_bar.text == "") {
                return;
            }
            else {
                source_view.buffer.select_range (iter_start, iter_end);
                var mark = source_view.buffer.create_mark ("search", iter_end, true);
                source_view.scroll_mark_onscreen (mark);
            }
        }
    }
}
