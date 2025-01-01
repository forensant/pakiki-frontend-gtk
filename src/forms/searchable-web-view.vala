namespace Pakiki {
    class SearchableWebView : Gtk.Box {

        private WebKit.WebView webview;
        private TextSearchBar search_bar;

        public SearchableWebView (ApplicationWindow application_window, WebKit.WebView webview) {
            this.orientation = Gtk.Orientation.VERTICAL;

            this.vexpand = true;
            this.hexpand = true;
            

            this.webview = webview;
            webview.show ();

            search_bar = new TextSearchBar ();
            search_bar.format_visible = false;

            search_bar.search_next.connect (() => {
                webview.get_find_controller ().search_next ();
            });

            search_bar.search_prev.connect (() => {
                webview.get_find_controller ().search_previous ();
            });

            search_bar.stop.connect (() => {
                webview.get_find_controller ().search_finish ();
                search_bar.enabled = false;
                webview.grab_focus ();
            });

            search_bar.text_changed.connect (() => {
                var flags = WebKit.FindOptions.CASE_INSENSITIVE | WebKit.FindOptions.WRAP_AROUND;
                webview.get_find_controller ().search (search_bar.text, flags, 1000);
            });

            search_bar.show ();

            this.append (search_bar);
            this.append (webview);
        }

        public bool find_activated () {
            if (!search_bar.text_has_focus () && !webview.has_focus) {
                return false;
            }

            search_bar.enabled = !search_bar.enabled;
            search_bar.show_close_button = true;

            if (search_bar.enabled) {
                search_bar.find_activated ();
            } else {
                webview.grab_focus ();
            }
    
            return true;
        }

        public void load_uri (string uri) {
            webview.load_uri (uri);
        }
    }
}
