
namespace Proximity {
    class SearchableWebView : Gtk.Box {

        private WebKit.WebView webview;
        private TextSearchBar search_bar;

        public SearchableWebView (ApplicationWindow application_window, WebKit.WebView webview) {
            this.orientation = Gtk.Orientation.VERTICAL;

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
                search_bar.search_mode_enabled = false;
                webview.grab_focus ();
            });

            search_bar.text_changed.connect (() => {
                var flags = WebKit.FindOptions.CASE_INSENSITIVE | WebKit.FindOptions.WRAP_AROUND;
                webview.get_find_controller ().search (search_bar.text, flags, 1000);
            });

            search_bar.show ();

            this.pack_start (search_bar, false, false, 0);
            this.pack_start (webview, true, true, 0);
        }

        public bool find_activated () {
            if (!search_bar.text_has_focus () && !webview.has_focus) {
                return false;
            }

            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;

            if (search_bar.search_mode_enabled) {
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
