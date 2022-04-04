using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/payload-selection-widget.ui")]
    class PayloadSelectionWidget : Gtk.Grid {

        [GtkChild]
        private unowned Gtk.Entry entry_from;
        [GtkChild]
        private unowned Gtk.Entry entry_fuzzdb_search;
        [GtkChild]
        private unowned Gtk.Entry entry_to;
        [GtkChild]
        private unowned Gtk.Frame frame_iterate;
        [GtkChild]
        private unowned Gtk.Label label_iterate;
        [GtkChild]
        private unowned Gtk.ListStore liststore_custom_files;
        [GtkChild]
        private unowned Gtk.TreeStore treestore_fuzzdb;
        [GtkChild]
        private unowned Gtk.TreeView treeview_custom_files;
        [GtkChild]
        private unowned Gtk.TreeView treeview_fuzzdb;

        private ApplicationWindow application_window;
        private string path_to_set;
        private bool populating_fuzzdb;
        private Gtk.TreeModelFilter treeview_model_filter;

        public int iterate_from {
            get { return int.parse (entry_from.text); }
            set { entry_from.text = value.to_string (); }
        }

        public int iterate_to {
            get { return int.parse (entry_to.text); }
            set { entry_to.text = value.to_string (); }
        }

        public string[] custom_filenames {
            owned get { return get_custom_filenames_internal (); }
        }

        public string[] custom_file_payloads {
            owned get { return get_custom_file_payloads_internal (); }
        }

        public string[] fuzzdb_files {
            owned get { return get_fuzzdb_files_internal (); }
        }

        enum Column {
            CHECKED,
            TITLE,
            FILENAME,
            PAYLOADS
        }

        public PayloadSelectionWidget (ApplicationWindow application_window, bool show_iterator) {
            this.application_window = application_window;
            populating_fuzzdb = false;
            path_to_set = "";
            populate_payloads ();

            if (show_iterator == false) {
                frame_iterate.hide ();
                label_iterate.hide ();
            }

            treeview_model_filter = new Gtk.TreeModelFilter (treestore_fuzzdb, null);
            treeview_model_filter.set_visible_func (should_fuzzdb_row_be_visible);
            treeview_fuzzdb.model = treeview_model_filter;

            var fuzzdb_toggle_renderer = new Gtk.CellRendererToggle ();
            fuzzdb_toggle_renderer.set_activatable (true);
            fuzzdb_toggle_renderer.toggled.connect (on_fuzzdb_toggled);

            var filename_renderer = new Gtk.CellRendererText();
            filename_renderer.ellipsize = Pango.EllipsizeMode.START;
            filename_renderer.ellipsize_set = true;

            treeview_custom_files.insert_column_with_attributes (-1, "Filename", filename_renderer, "text", 0);

            int toggle_column = treeview_fuzzdb.insert_column_with_attributes (-1, "Checked",
                fuzzdb_toggle_renderer);

            treeview_fuzzdb.insert_column_with_attributes (-1, "Title",
                new Gtk.CellRendererText(), "text",
                Column.TITLE);

            treeview_fuzzdb.get_column (toggle_column).set_cell_data_func (fuzzdb_toggle_renderer, (cell_layout, cell, tree_model, iter) => {
                Value field_val;
                tree_model.get_value (iter, Column.CHECKED, out field_val);

                var checked_status = field_val.get_string ();

                cell.set_property ("inconsistent", checked_status == "Inconsistent");
                cell.set_property ("active", checked_status == "Checked");

            });
        }

        private void add_to_fuzzdb_tree (Json.Array filetree_children, Gtk.TreeIter? parent = null) {
            foreach (var element in filetree_children.get_elements ()) {
                Json.Object payload = element.get_object ();
                Gtk.TreeIter iter;

                var payloads = "";

                var sample_payloads = payload.get_array_member ("SamplePayloads");
                if (sample_payloads != null) {
                    foreach (var sample_payload in sample_payloads.get_elements ()) {
                        payloads += sample_payload.get_string () + "\n";
                    }

                    if(payloads != "") {
                        payloads = "<b>Sample Payloads:</b>\n" + payloads.replace ("&", "&amp;").replace ("<", "&gt;").replace (">", "&lt;");
                    }
                }

                treestore_fuzzdb.append (out iter, parent);

                treestore_fuzzdb.set (iter, 
                    Column.CHECKED, false,
                    Column.TITLE, payload.get_string_member ("Title"),
                    Column.FILENAME, payload.get_string_member ("ResourcePath"),
                    Column.PAYLOADS, payloads);

                add_to_fuzzdb_tree (payload.get_array_member ("SubEntries"), iter);
            }
        }

        private string[] get_custom_filenames_internal () {
            var custom_files = new Gee.ArrayList<string> ();
            liststore_custom_files.@foreach ((model, path, iter) => {
                Value path_value;
                model.get_value (iter, 0, out path_value);
                var file_path = path_value.get_string ();
                custom_files.add (file_path);

                return false;
            });

            return custom_files.to_array ();
        }

        private string[] get_custom_file_payloads_internal () {
            var custom_file_payloads = new Gee.ArrayList<string> ();

            liststore_custom_files.@foreach ((model, path, iter) => {
                Value path_value;
                model.get_value (iter, 0, out path_value);
                var file_path = path_value.get_string ();

                var file = File.new_for_path (file_path);

                if (!file.query_exists ()) {
                    stderr.printf ("File '%s' doesn't exist.\n", file_path);
                    return false;
                }

                try {
                    var dis = new DataInputStream (file.read ());
                    string line;
                    while ((line = dis.read_line (null)) != null) {
                        custom_file_payloads.add (line);
                    }
                } catch (Error e) {
                    error ("%s", e.message);
                }

                return false; // iterate until the end
            });

            return custom_file_payloads.to_array ();
        }

        private string[] get_fuzzdb_files_internal () {
            var fuzzdb_files = new Gee.ArrayList<string> ();

            treeview_fuzzdb.model.@foreach ((model, path, iter) => {
                Value is_checked;
                model.get_value (iter, Column.CHECKED, out is_checked);

                if (is_checked.get_string () == "Checked" && model.iter_n_children (iter) == 0) {
                    Value filename;
                    model.get_value (iter, Column.FILENAME, out filename);
                    fuzzdb_files.add (filename.get_string ());
                }

                return false; // iterate until the end
            });

            return fuzzdb_files.to_array ();
        }

        [GtkCallback]
        private void on_button_add_custom_file_clicked () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.OPEN,
                "_Open",
                "_Cancel");

            dialog.transient_for = application_window;
            dialog.local_only = false; //allow for uri
            dialog.set_modal (true);

            var res = dialog.run ();
            
            if (res == Gtk.ResponseType.ACCEPT) {
                var file = dialog.get_file();
                var filename = file.get_path ();

                Gtk.TreeIter iter;
                liststore_custom_files.insert_with_values (out iter, -1,
                    0, filename
                );
            }
            
            dialog.destroy ();
        }

        [GtkCallback]
        private void on_button_remove_custom_file_clicked () {
            var selection = treeview_custom_files.get_selection ();

            Gtk.TreeIter iter;
            Gtk.TreeModel model;
            if (selection.get_selected (out model, out iter)) {
                liststore_custom_files.remove (ref iter);
            }
        }

        [GtkCallback]
        private void on_entry_fuzzdb_search_search_changed () {
            treeview_model_filter.refilter ();

            if (entry_fuzzdb_search.text == "") {
                return;
            }

            treeview_model_filter.@foreach ((model, path, iter) => {
                if (!treeview_model_filter.iter_has_child (iter) && treeview_model_filter.visible (model, iter)) {
                    treeview_fuzzdb.expand_to_path (path);
                }

                return false;
            });
        }

        private void on_fuzzdb_toggled (string path) {
            Gtk.TreeIter iter;
            treeview_model_filter.get_iter(out iter, new Gtk.TreePath.from_string(path));

            Value is_checked;
            treeview_model_filter.get_value(iter, Column.CHECKED, out is_checked);

            var value_to_set = "Checked";
            if (is_checked.get_string () == "Checked") {
                value_to_set = "Unchecked";   
            }

            Gtk.TreeIter child_iter;
            treeview_model_filter.convert_iter_to_child_iter (out child_iter, iter);
            treestore_fuzzdb.set_value(child_iter, Column.CHECKED, value_to_set);

            set_fuzzdb_parent_status (iter);
            set_fuzzdb_child_status (iter, value_to_set);

            is_checked.unset();
        }

        private void populate_payloads () {
            var message = new Soup.Message ("GET", "http://" + application_window.core_address + "/inject_operations/payloads");

            application_window.http_session.queue_message (message, (sess, mess) => {
                if (mess.status_code != 200) {
                    return;
                }
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var root_obj = parser.get_root().get_object();

                    populating_fuzzdb = true;
                    add_to_fuzzdb_tree (root_obj.get_array_member ("SubEntries"));
                } catch (Error err) {
                    stdout.printf("Error occurred while retrieving payloads: %s\n", err.message);
                }

                populating_fuzzdb = false;
                treeview_model_filter.refilter ();

                if (path_to_set != "") {
                    set_fuzzdb_path (path_to_set);
                    path_to_set = "";
                }
            });
        }

        public void reset_state () {
            entry_fuzzdb_search.text = "";
            treeview_model_filter.refilter ();
            treestore_fuzzdb.@foreach ((model, path, iter) => {
                treestore_fuzzdb.set_value (iter, Column.CHECKED, "Unchecked");
                return false; // iterate until the end
            });
            
            treeview_fuzzdb.collapse_all ();
            treeview_fuzzdb.get_selection ().unselect_all ();
            liststore_custom_files.clear ();
            entry_from.text = "0";
            entry_to.text = "0";
            populate_payloads ();
        }

        private void set_fuzzdb_child_status (Gtk.TreeIter iter, string value_to_set) {
            var child_count = treeview_model_filter.iter_n_children (iter);
            for (int i = 0; i < child_count; i++) {
                Gtk.TreeIter child_iter;
                if (!treeview_model_filter.iter_nth_child (out child_iter, iter, i)) {
                    continue;
                }

                Gtk.TreeIter child_model_iter;
                treeview_model_filter.convert_iter_to_child_iter (out child_model_iter, child_iter);
                treestore_fuzzdb.set_value(child_model_iter, Column.CHECKED, value_to_set);
                set_fuzzdb_child_status (child_iter, value_to_set);
            }
        }

        private void set_fuzzdb_parent_status (Gtk.TreeIter current_child) {
            Gtk.TreeIter parent;
            bool has_parent = treeview_model_filter.iter_parent (out parent, current_child);

            if (!has_parent) {
                return;
            }

            var false_found = false;
            var true_found = false;
            var inconsistent_found = false;

            var child_count = treeview_model_filter.iter_n_children (parent);
            for (int i = 0; i < child_count; i++) {
                Gtk.TreeIter child_iter;
                if (!treeview_model_filter.iter_nth_child (out child_iter, parent, i)) {
                    continue;
                }

                Value is_checked;
                treeview_model_filter.get_value(child_iter, Column.CHECKED, out is_checked);

                var is_checked_str = is_checked.get_string ();
                if (is_checked_str == "Inconsistent") {
                    inconsistent_found = true;
                } else if (is_checked_str == "Checked") {
                    true_found = true;
                } else {
                    false_found = true;
                }
            }

            var checked_val = "Unchecked";

            if (inconsistent_found || true_found && false_found) {
                checked_val = "Inconsistent";
            } else if (true_found) {
                checked_val = "Checked";
            }

            Gtk.TreeIter parent_model_iter;
            treeview_model_filter.convert_iter_to_child_iter (out parent_model_iter, parent);
            treestore_fuzzdb.set_value (parent_model_iter, Column.CHECKED, checked_val);
            set_fuzzdb_parent_status (parent);
        }

        public void set_fuzzdb_path (string path) {
            Gtk.TreeIter iter;
            var assigned = treestore_fuzzdb.get_iter_first (out iter);

            if (populating_fuzzdb || !assigned) {
                path_to_set = path;
                return;
            }

            var path_components = path.split ("/");
            
            for (int i = 0; i < path_components.length; i++) {
                var part = path_components[i];

                while (true) {
                    Value title;
                    treestore_fuzzdb.get_value (iter, Column.TITLE, out title);
                    if (title.get_string () == part) {
                        treeview_fuzzdb.expand_to_path (new Gtk.TreePath.from_string (treestore_fuzzdb.get_string_from_iter (iter)));
                        treeview_fuzzdb.set_cursor (new Gtk.TreePath.from_string (treestore_fuzzdb.get_string_from_iter (iter)), null, false);

                        var prev_iter = iter;
                        if (!treestore_fuzzdb.iter_children (out iter, iter)) {
                            if (i == path_components.length - 1) {
                                treestore_fuzzdb.set_value(prev_iter, Column.CHECKED, "Checked");
                            }
                            return;
                        }
                        break;
                    }

                    if (!treestore_fuzzdb.iter_next (ref iter)) {
                        return;
                    }
                }
            }
        }

        private bool should_fuzzdb_row_be_visible (Gtk.TreeModel model, Gtk.TreeIter iter) {
            if (populating_fuzzdb) {
                return true;
            }

            Value val_title;
            Value val_path;
            
            model.get_value (iter, Column.TITLE, out val_title);
            model.get_value (iter, Column.FILENAME, out val_path);

            if (val_title.type () != GLib.Type.STRING || val_path.type () != GLib.Type.STRING) {
                return false;
            }

            var title = val_title.get_string ().down ();
            var path = val_path.get_string ().down ();

            var filter = entry_fuzzdb_search.text.down ();

            if (title.contains (filter) || path.contains (filter)) {
                return true;
            }

            for (var i = 0; i < model.iter_n_children (iter); i++) {
                Gtk.TreeIter child_iter;

                if (!model.iter_nth_child (out child_iter, iter, i)) {
                    continue;
                }

                if (should_fuzzdb_row_be_visible (model, child_iter)) {
                    return true;
                }
            }
            
            return false;
        }
    }
}
