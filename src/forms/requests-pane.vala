using Soup;

namespace Proximity {
    class RequestsPane : Gtk.Paned, MainApplicationPane {
        
        private Gtk.TreeStore tree_store_site_map;
        private RequestList request_list;
        private bool requests_loaded;
        private Gtk.TreeView tree_view_site_map;
        private WebsocketConnection websocket;

        public RequestsPane (ApplicationWindow application_window, bool launch_successful) {
            requests_loaded = false;
            request_list = new RequestList (application_window);
            request_list.requests_loaded.connect (on_requests_loaded);
            request_list.show ();
            request_list.set_processed_launched (launch_successful);

            tree_store_site_map = new Gtk.TreeStore (1, typeof (string));
            Gtk.TreeIter iter;
            tree_store_site_map.append (out iter, null);
            tree_store_site_map.set (iter, 0, "All");

            tree_view_site_map = new Gtk.TreeView.with_model (tree_store_site_map);
            tree_view_site_map.border_width = 0;
            tree_view_site_map.get_selection ().changed.connect ( on_sitemap_row_changed );
            Gtk.CellRendererText cell = new Gtk.CellRendererText ();
            tree_view_site_map.insert_column_with_attributes (-1, "Sitemap", cell, "text", 0);

            position = 0;
            wide_handle = false;

            if (launch_successful) {
                var scrolled_window_site_map = new Gtk.ScrolledWindow (null, null);
                scrolled_window_site_map.expand = true;
                scrolled_window_site_map.shadow_type = Gtk.ShadowType.NONE;
                scrolled_window_site_map.add (tree_view_site_map);
                scrolled_window_site_map.show_all ();

                this.add1 (scrolled_window_site_map);
                this.add2 (request_list);
                
                get_sitemap ();
            } else {
                this.add1 (request_list);
            }
        }

        private void add_path_to_sitemap (string path, Gtk.TreeIter? parent = null) {
            var path_components = path.split("/");

            path = path_components[0];

            bool found = false;
            Gtk.TreeIter? current_iter = null;
            Gtk.TreeIter? insert_before = null;

            var child_count = tree_store_site_map.iter_n_children (parent);
            for (int i = 0; i < child_count; i++) {
                if (tree_store_site_map.iter_nth_child (out current_iter, parent, i)) {
                    Value path_value;
                    tree_store_site_map.get_value (current_iter, 0, out path_value);

                    if (path_value.get_string () == path) {
                        found = true;
                        break;
                    }

                    if (insert_before == null && path_value.get_string () > path) {
                        insert_before = current_iter;
                        break;
                    }
                }
            }

            // insert
            if (!found) {
                if (insert_before != null) {
                    tree_store_site_map.insert_before (out current_iter, parent, insert_before);
                } else {
                    tree_store_site_map.append (out current_iter, parent);
                }
                
                tree_store_site_map.set (current_iter, 0, path);
            }
            
            // now add any children to the sitemap
            string new_path = "";
            for (int i = 1; i < path_components.length; i++) {
                if (new_path != "") {
                    new_path += "/";
                }
                new_path += path_components[i];
            }

            if (new_path != "") {
                add_path_to_sitemap (new_path, current_iter);
            }
            
            if (wide_handle == false) {
                on_requests_loaded (true);
            }
        }

        private void get_sitemap () {
            var url = "http://localhost:10101/project/sitemap";

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var rootArray = parser.get_root().get_array();

                    foreach (var element in rootArray.get_elements ()) {
                        var path = element.get_string ();
                        add_path_to_sitemap (path);
                    }
                } catch (Error err) {
                    stdout.printf ("Could not retrieve site map: %s\n", err.message);
                }
            });

            if(websocket != null) {
                websocket.close(Soup.WebsocketCloseCode.NO_STATUS, null);
            }

            url = "http://127.0.0.1:10101/project/notifications";
            
            var wsmessage = new Soup.Message("GET", url);
            session.websocket_connect_async.begin(wsmessage, "localhost", null, null, (obj, res) => {
                try {
                    websocket = session.websocket_connect_async.end(res);
                }
                catch (Error err) {
                    stdout.printf ("Error ending websocket connection: %s\n", err.message);
                }
                websocket.message.connect(on_websocket_message);
            });
        }

        private string get_path_string (Gtk.TreeIter iter) {
            Value path_value;
            tree_store_site_map.get_value (iter, 0, out path_value);
            var value = path_value.get_string ();

            Gtk.TreeIter parent;
            if (tree_store_site_map.iter_parent (out parent, iter)) {
                return get_path_string (parent) + "/" + value;
            }

            return "://" + value;
        }

        private void on_requests_loaded (bool requests_present) {
            if (requests_present && requests_loaded == false) {
                position = 300;
                request_list.requests_loaded.disconnect (on_requests_loaded);
                requests_loaded = true;
            }
        }

        private void on_sitemap_row_changed () {
            Gtk.TreeModel model;
            Gtk.TreeIter path_iter;

            if (tree_view_site_map.get_selection ().get_selected (out model, out path_iter)) {
                string url = get_path_string (path_iter);
                if (url == "://All") {
                    url = "";
                }
    
                request_list.set_url_filter (url);
            }
        }

        private void on_websocket_message (int type, Bytes message) {
            var parser = new Json.Parser ();
            var json_data = (string) message.get_data ();
            
            if(json_data == "") {
                return;
            }
            
            try {
                parser.load_from_data (json_data, -1);
            }
            catch(Error e) {
                stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, json_data);
                return;
            }

            var path = parser.get_root ().get_object ();
                
            if(path.get_string_member("ObjectType") != "Site Map Path") {
                return;
            }

            add_path_to_sitemap (path.get_string_member ("Path"));
        }

        public bool new_visible () {
            return true;
        }

        public string pane_name () {
            return "Requests";
        }

        public void on_search (string text, bool exclude_resources) {
            request_list.on_search (text, exclude_resources);
        }

        public void reset_state () {
            // TODO: 
        }
    }
}
