
namespace Proximity {
    class SearchableRequestPreview : Gtk.Box {

        private RequestPreview request_preview;
        private TextSearchBar search_bar;

        private int upto;
        private int total_count;

        public SearchableRequestPreview (ApplicationWindow application_window) {
            this.orientation = Gtk.Orientation.VERTICAL;

            request_preview = new RequestPreview (application_window);
            request_preview.get_find_controller ().counted_matches.connect (matches_counted);
            request_preview.show ();

            search_bar = new TextSearchBar ();
            search_bar.format_visible = false;

            search_bar.search_next.connect (() => {
                request_preview.get_find_controller ().search_next ();
                upto++;

                if (upto >= total_count) {
                    upto = 0;
                    // for some reason this needs to be called twice
                    request_preview.get_find_controller ().search_next ();
                }

                update_count_totals ();
            });

            search_bar.search_prev.connect (() => {
                request_preview.get_find_controller ().search_previous ();

                upto--;

                if (upto <= -1) {
                    upto = total_count - 1;
                    request_preview.get_find_controller ().search_previous ();
                }

                update_count_totals ();
            });

            search_bar.stop.connect (() => {
                request_preview.get_find_controller ().search_finish ();
                search_bar.search_mode_enabled = false;
                request_preview.grab_focus ();
            });

            search_bar.text_changed.connect (() => {
                var controller = request_preview.get_find_controller ();
                controller.search (search_bar.text, WebKit.FindOptions.CASE_INSENSITIVE, 1000);
                controller.count_matches (search_bar.text, WebKit.FindOptions.CASE_INSENSITIVE, 1000);
            });

            search_bar.show ();

            this.pack_start (search_bar, false, false, 0);
            this.pack_start (request_preview, true, true, 0);
        }

        public bool find_activated () {
            if (!search_bar.text_has_focus () && !request_preview.has_focus) {
                return false;
            }

            search_bar.search_mode_enabled = !search_bar.search_mode_enabled;

            if (search_bar.search_mode_enabled) {
                search_bar.find_activated ();
            } else {
                request_preview.grab_focus ();
            }
    
            return true;
        }

        public void load_uri (string uri) {
            request_preview.load_uri (uri);
        }

        private void matches_counted (uint match_count) {
            upto = 0;
            total_count = (int)match_count;
            update_count_totals ();
        }

        public bool set_content (uchar[] bytes, string mimetype, string url) {
            return request_preview.set_content(bytes, mimetype, url);
        }

        private void update_count_totals () {
            if (search_bar.text == "") {
                search_bar.clear_search_count ();
            }
            else if (total_count == 0) {
                search_bar.set_no_results ();
            }
            else {
                search_bar.set_count (upto + 1, total_count);
            }
        }
    }
}
