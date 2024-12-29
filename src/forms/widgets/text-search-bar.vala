namespace Pakiki {
    [GtkTemplate (ui = "/com/forensant/pakiki/text-search-bar.ui")]
    public class TextSearchBar : Gtk.Box {
        
        public signal void search_next ();
        public signal void search_prev ();
        public signal void stop ();
        public signal void text_changed ();

        [GtkChild]
        private unowned Gtk.DropDown dropdown_format;
        [GtkChild]
        private unowned Gtk.Label label_count;
        [GtkChild]
        public unowned Gtk.SearchBar search_bar;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry_text;
        [GtkChild]
        private unowned Gtk.Spinner spinner;

        public bool enabled {
            get { return search_bar.search_mode_enabled; }
            set { search_bar.search_mode_enabled = value; }
        }

        public string format {
            get { return dropdown_format.selected == 0 ? "ASCII" : "Hex"; }
        }

        public bool format_visible {
            get { return dropdown_format.visible; }
            set { dropdown_format.visible = value; }
        }

        public bool show_close_button {
            get { return search_bar.show_close_button; }
            set { search_bar.show_close_button = value; }
        }

        public bool spinner_visible {
            get { return spinner.visible; }
            set { spinner.visible = value; }
        }

        public string text {
            get { return search_entry_text.text; }
            set { search_entry_text.text = value; }
        }

        public void TextSearchBar () {
            search_bar.show_close_button = true;
        }

        public void clear_search_count () {
            label_count.label = "";
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

        public void set_count (int upto, int total) {
            label_count.label = upto.to_string () + " of " + total.to_string ();
        }

        public void set_no_results () {
            label_count.label = "No results found";
        }

        public bool text_has_focus () {
            return search_entry_text.has_focus;
        }
    }
}
