using Soup;

namespace Proximity {
    class RequestsPane : Gtk.Paned, MainApplicationPane {
        
        private ApplicationWindow application_window;
        private bool launch_successful;
        private RequestList request_list;
        private bool requests_loaded;

        private SitemapWidget sitemap_widget;

        public RequestsPane (ApplicationWindow application_window, bool launch_successful) {
            requests_loaded = false;
            this.application_window = application_window;
            this.launch_successful = launch_successful;
            request_list = new RequestList (application_window, launch_successful);
            request_list.requests_loaded.connect (on_requests_loaded);
            request_list.show ();
            request_list.set_processed_launched (launch_successful);

            sitemap_widget = new SitemapWidget (application_window);
            sitemap_widget.border_width = 0;

            sitemap_widget.url_filter_set.connect ((url) => {
                request_list.set_url_filter (url);
            });

            position = 0;
            wide_handle = false;

            if (launch_successful) {
                var scrolled_window_site_map = new Gtk.ScrolledWindow (null, null);
                scrolled_window_site_map.expand = true;
                scrolled_window_site_map.shadow_type = Gtk.ShadowType.NONE;
                scrolled_window_site_map.add (sitemap_widget);
                scrolled_window_site_map.show_all ();

                this.add1 (scrolled_window_site_map);
                this.add2 (request_list);
                
                sitemap_widget.populate_sitemap ();
            } else {
                this.add1 (request_list);
            }
        }

        public bool can_search () {
            return requests_loaded;
        }

        public string new_tooltip_text () {
            return "New Request";
        }

        public void on_new_clicked () {
            application_window.change_pane ("NewRequest");
        }

        private void on_requests_loaded (bool requests_present) {
            if (requests_present && requests_loaded == false) {
                position = 250;
                request_list.requests_loaded.disconnect (on_requests_loaded);
                requests_loaded = true;

                pane_changed ();
            }
        }

        public bool new_visible () {
            return launch_successful;
        }

        public void on_search (string text, bool exclude_resources) {
            request_list.on_search (text, exclude_resources);
        }

        public void reset_state () {
            sitemap_widget.reset_state ();
            request_list.reset_state ();
        }
    }
}
