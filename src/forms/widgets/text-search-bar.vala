namespace Proximity {
    [GtkTemplate (ui = "/com/forensant/proximity/text-search-bar.ui")]
    public class TextSearchBar : Gtk.SearchBar {
        
        public signal void search_next ();
        public signal void search_prev ();
        public signal void stop ();
        public signal void text_changed ();

        [GtkChild]
        private Gtk.ComboBox combobox_format;

        [GtkChild]
        private Gtk.SearchEntry search_entry_text;

        public bool format_visible {
            get { return combobox_format.visible; }
            set { combobox_format.visible = value; }
        }

        public string text {
            get { return search_entry_text.text; }
            set { search_entry_text.text = value; }
        }

        public void find_activated () {
            search_entry_text.grab_focus ();
        }

        [GtkCallback]
        private void on_search_entry_text_next_match () {
            search_next ();
        }

        [GtkCallback]
        private void on_search_entry_text_previous_match () {
            search_prev ();
        }

        [GtkCallback]
        private void on_search_entry_text_search_changed () {
            text_changed ();
        }

        [GtkCallback]
        private void on_search_entry_text_stop_search () {
            stop ();
        }

        public bool text_has_focus () {
            return search_entry_text.has_focus;
        }
    }
}
