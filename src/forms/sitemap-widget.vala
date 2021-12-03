using Soup;

namespace Proximity {
    class SitemapWidget : Gtk.TreeView {
        public signal void loaded ();
        public signal void url_filter_set (string url);

        public string url_path {
            owned get { return get_url_path_internal (); }
            set { set_url_path_internal (value); }
        }

        public bool has_loaded;
        private Gtk.TreeStore tree_store_site_map;
        private WebsocketConnection websocket;

        public SitemapWidget () {
            has_loaded = false;
            this.get_selection ().set_mode (Gtk.SelectionMode.SINGLE);
            tree_store_site_map = new Gtk.TreeStore (1, typeof (string));
            Gtk.TreeIter iter;
            tree_store_site_map.append (out iter, null);
            tree_store_site_map.set (iter, 0, "All");

            this.model = tree_store_site_map;
            this.get_selection ().changed.connect ( on_sitemap_row_changed );
            Gtk.CellRendererText cell = new Gtk.CellRendererText ();
            this.insert_column_with_attributes (-1, "Sitemap", cell, "text", 0);
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
        }

        private string get_path_string (Gtk.TreeIter iter) {
            Value path_value;
            tree_store_site_map.get_value (iter, 0, out path_value);
            var value = path_value.get_string ();

            Gtk.TreeIter parent;
            if (tree_store_site_map.iter_parent (out parent, iter)) {
                return get_path_string (parent) + "/" + value;
            }

            return value;
        }

        private string get_url_path_internal () {
            Gtk.TreeModel model;
            Gtk.TreeIter path_iter;

            if (this.get_selection ().get_selected (out model, out path_iter)) {
                string url = get_path_string (path_iter);
                if (url == "All") {
                    url = "";
                }
                return url;
            }

            return "";
        }

        private void set_url_path_internal (string url_path) {
            var split_paths = url_path.split("/");
            Gee.List<string> paths = new Gee.ArrayList<string> ();
            paths.add_all_array (split_paths);

            if (paths.size == 0) {
                return;
            }

            var child_count = tree_store_site_map.iter_n_children (null);
            for (int i = 0; i < child_count; i++) {
                Gtk.TreeIter iter;
                if (tree_store_site_map.iter_nth_child (out iter, null, i)) {
                    Value path_value;
                    tree_store_site_map.get_value (iter, 0, out path_value);

                    if (path_value.get_string () == split_paths[0]) {
                        paths.remove_at (0);

                        if (paths.size == 0) {
                            this.expand_to_path (tree_store_site_map.get_path (iter));
                            this.get_selection ().select_iter (iter);
                            return;
                        } else {
                            set_url_path_position (paths, iter);
                        }
                    }
                }
            }
        }

        private void set_url_path_position (Gee.List<string> path_components, Gtk.TreeIter iter) {
            if (path_components.size == 0) {
                return;
            }

            string path = path_components.@get (0);

            var child_count = tree_store_site_map.iter_n_children (iter);
            for (int i = 0; i < child_count; i++) {
                Gtk.TreeIter child_iter;
                if (tree_store_site_map.iter_nth_child (out child_iter, iter, i)) {
                    Value path_value;
                    tree_store_site_map.get_value (child_iter, 0, out path_value);

                    if (path_value.get_string () == path) {
                        path_components.remove_at (0);


                        if (path_components.size == 0) {
                            this.expand_to_path (tree_store_site_map.get_path (iter));
                            this.get_selection ().select_iter (child_iter);
                            return;
                        }
                        
                        set_url_path_position (path_components, child_iter);
                        return;
                    }
                }
            }
        }

        private void on_sitemap_row_changed () {
            url_filter_set (url_path);
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
                stdout.printf ("Could not parse JSON data for sitemap, error: %s\nData: %s\n", e.message, json_data);
                return;
            }

            var path = parser.get_root ().get_object ();
                
            if(path.get_string_member("ObjectType") != "Site Map Path") {
                return;
            }

            add_path_to_sitemap (path.get_string_member ("Path"));
        }

        public void populate_sitemap () {
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

                    has_loaded = true;
                    loaded ();
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

        public void reset_state () {
            tree_store_site_map.clear ();
            populate_sitemap ();
        }
    }
}
