using Soup;

namespace Pakiki {
    class RequestsPane : Gtk.Paned, MainApplicationPane {

        public signal void request_double_clicked (string guid);
        public signal void request_selected (string guid);
        
        private ApplicationWindow application_window;
        private RequestList request_list;
        private bool requests_loaded;

        private SitemapWidget sitemap_widget;
        private Gtk.ScrolledWindow scrolled_window_site_map;

        public bool process_actions {
            get { return request_list.process_actions; }
            set { request_list.process_actions = value; }
        }

        public RequestsPane (ApplicationWindow application_window, bool initial_launch) {
            requests_loaded = false;
            this.application_window = application_window;
            request_list = new RequestList (application_window, initial_launch);
            request_list.requests_loaded.connect (on_requests_loaded);
            request_list.request_selected.connect ( (guid) => { this.request_selected (guid); } );
            request_list.request_double_clicked.connect ( (guid) => { this.request_double_clicked (guid); } );
            request_list.show ();

            sitemap_widget = new SitemapWidget (application_window);
            sitemap_widget.border_width = 0;

            sitemap_widget.url_filter_set.connect ((url) => {
                request_list.set_url_filter (url);
            });

            position = 0;
            wide_handle = false;

            scrolled_window_site_map = new Gtk.ScrolledWindow (null, null);
            scrolled_window_site_map.expand = true;
            scrolled_window_site_map.shadow_type = Gtk.ShadowType.NONE;
            scrolled_window_site_map.add (sitemap_widget);

            this.add1 (scrolled_window_site_map);
            this.add2 (request_list);
        }

        public bool can_filter_protocols () {
            return true;
        }

        public bool can_search () {
            return requests_loaded;
        }

        public bool find_activated () {
            return request_list.find_activated ();
        }

        public string new_tooltip_text () {
            return "New Request";
        }

        public string new_name () {
            return "_New Request";
        }

        public bool new_visible () {
            return true;
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

        public void on_search (string text, bool negative_filter, bool exclude_resources, string protocol) {
            request_list.on_search (text, negative_filter, exclude_resources, protocol);
        }

        public void process_launch_successful (bool success) {
            if (success) {
                scrolled_window_site_map.show_all ();
            }
            else {
                scrolled_window_site_map.hide ();
            }

            request_list.set_processed_launched (success);
        }

        public void reset_state () {
            sitemap_widget.reset_state ();
            request_list.reset_state ();
        }
    }
}
