using Soup;

namespace Pakiki {

    [GtkTemplate (ui = "/com/forensant/pakiki/payload-selection-widget.ui")]
    class PayloadSelectionWidget : Gtk.Box {

        [GtkChild]
        private unowned Gtk.SpinButton entry_from;
        [GtkChild]
        private unowned Gtk.SearchEntry entry_fuzzdb_search;
        [GtkChild]
        private unowned Gtk.SpinButton entry_to;
        [GtkChild]
        private unowned Gtk.Label label_payload_selection_count;
        [GtkChild]
        private unowned Gtk.ListView listview_custom_files;
        [GtkChild]
        private unowned Gtk.ListView listview_fuzzdb;
        [GtkChild]
        private unowned Gtk.Notebook notebook;

        private ApplicationWindow application_window;
        private GLib.ListStore liststore_fuzzdb_root;
        private string path_to_set;
        private bool populating_fuzzdb;
        private Gtk.SelectionModel selection_model_custom_files;
        private Gtk.SelectionModel selection_model_fuzzdb;
        private Gtk.StringList stringlist_custom_files;
        private Gtk.TreeListModel treelist_fuzzdb;
        private Gtk.Filter filter_fuzzdb;

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
            PAYLOADS,
            PAYLOAD_COUNT
        }

        public PayloadSelectionWidget (ApplicationWindow application_window, bool show_iterator) {
            this.application_window = application_window;
            populating_fuzzdb = false;
            path_to_set = "";
            populate_payloads ();

            stringlist_custom_files = new Gtk.StringList (null);
            selection_model_custom_files = new Gtk.MultiSelection (stringlist_custom_files);
            listview_custom_files.set_model (selection_model_custom_files);

            var customfile_column_factory = new Gtk.SignalListItemFactory ();
            customfile_column_factory.setup.connect (on_setup_label_column);
            customfile_column_factory.bind.connect (on_bind_column_custom_file);
            listview_custom_files.set_factory (customfile_column_factory);

            if (show_iterator == false) {
                notebook.remove_page (2);
            }

            filter_fuzzdb = new Gtk.CustomFilter((obj) => {
                var file = obj as FuzzDBFile;
                if (file == null) {
                    return false;
                }

                return file.search_matches (entry_fuzzdb_search.text);
            });

            liststore_fuzzdb_root = new GLib.ListStore (typeof (FuzzDBFile));
            treelist_fuzzdb = new Gtk.TreeListModel (liststore_fuzzdb_root, true, false, fuzzdb_create_model_func);
            var filter_model = new Gtk.FilterListModel (treelist_fuzzdb, filter_fuzzdb);
            selection_model_fuzzdb = new Gtk.NoSelection (filter_model);
            listview_fuzzdb.set_model (selection_model_fuzzdb);

            var fuzzdb_column_factory = new Gtk.SignalListItemFactory ();
            fuzzdb_column_factory.setup.connect (on_setup_tree);
            fuzzdb_column_factory.bind.connect (on_bind_column_fuzzdb);
            fuzzdb_column_factory.unbind.connect (on_unbind_column_fuzzdb);
            listview_fuzzdb.set_factory (fuzzdb_column_factory);
        }

        private void clear_custom_files () {
            while (stringlist_custom_files.get_n_items() != 0) {
                stringlist_custom_files.remove (0);
            }
        }

        public void clone_inject_operation (InjectOperation operation) {
            clear_custom_files ();
            for (int i = 0; i < operation.custom_filenames.length; i++) {
                stringlist_custom_files.append (operation.custom_filenames[i]);
            }

            reset_fuzzdb_tree ();

            foreach (var path in operation.fuzzdb) {
                set_fuzzdb_path (path.to_string ());
            }

            iterate_from = operation.iterate_from;
            iterate_to = operation.iterate_to;
        }

        private string[] get_custom_filenames_internal () {
            var custom_files = new Gee.ArrayList<string> ();
            for (int i = 0; i < stringlist_custom_files.get_n_items (); i++) {
                custom_files.add (stringlist_custom_files.get_string (i));
            }
            return custom_files.to_array ();
        }

        private string[] get_custom_file_payloads_internal () {
            var custom_file_payloads = new Gee.ArrayList<string> ();

            for (int i = 0; i < stringlist_custom_files.get_n_items (); i++) {
                var file_path = stringlist_custom_files.get_string (i);

                var file = File.new_for_path (file_path);

                if (!file.query_exists ()) {
                    stderr.printf ("File '%s' doesn't exist.\n", file_path);
                    continue;
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
            };

            return custom_file_payloads.to_array ();
        }

        private string[] get_fuzzdb_files_internal () {
            var fuzzdb_files = new Gee.ArrayList<string> ();

            for (var i = 0; i < liststore_fuzzdb_root.get_n_items (); i++) {
                var file = liststore_fuzzdb_root.get_item (i) as FuzzDBFile;
                if (file == null) {
                    continue;
                }

                fuzzdb_files.add_all (file.get_checked_files ());
            }

            return fuzzdb_files.to_array ();
        }

        private void on_bind_column_custom_file (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var path = (string) list_item.item ;
            var label = (Gtk.Label) list_item.child;

            try {
                var file = File.new_for_path (path);
                var file_info = file.query_info ("standard::*", GLib.FileQueryInfoFlags.NONE, null);
                label.label = file_info.get_display_name ();
            } catch (Error e) {
                label.label = path;
                stdout.printf("Could not get filename: %s\n", e.message);
            }

            label.tooltip_text = path;
        }

        private static ListModel? fuzzdb_create_model_func (Object item) {
            var file = (FuzzDBFile) item;
            if (file.children.size == 0) {
                return null;
            }
            var model = new ListStore (typeof (FuzzDBFile));
            for (var i = 0; i < file.children.size; i++) {
                model.append (file.children.@get (i));
            }
            return model;
        }

        private void on_bind_column_fuzzdb (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = list_item_obj as Gtk.ListItem;
            if (list_item == null) {
                stdout.printf("list_item is null\n");
                return;
            }

            var item_data = (FuzzDBFile) list_item.item ;

            var expander = list_item.child as Gtk.TreeExpander;
            if (expander != null) {
                var checkbox = expander.child as Gtk.CheckButton;
                if (checkbox != null) {
                    checkbox.label = item_data.title;
                    checkbox.active = item_data.checked;
                    checkbox.set_inconsistent (item_data.inconsistent);
                    checkbox.set_data ("file", item_data);
                    checkbox.tooltip_markup = item_data.payloads;

                    var id = item_data.notify.connect((pobj) => {
                        if (pobj.name != "checked" && pobj.name != "inconsistent") {
                            return;
                        }

                        checkbox.active = item_data.checked;
                        checkbox.set_inconsistent (item_data.inconsistent);
                    });
        
                    item_data.signal_id = id;
                }
            }

            var child_row = treelist_fuzzdb.get_row (list_item.position);
            expander.set_list_row (child_row);
        }

        [GtkCallback]
        private void on_button_add_custom_file_clicked () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.OPEN,
                "_Open",
                "_Cancel");

            dialog.transient_for = application_window;
            dialog.set_modal (true);

            dialog.response.connect ((response) => {
                if (response == Gtk.ResponseType.ACCEPT) {
                    var file = dialog.get_file();
                    var filename = file.get_path ();

                    stringlist_custom_files.append (filename);
                }
                dialog.destroy ();
                update_payload_count ();
            });

            dialog.show ();
        }

        [GtkCallback]
        private void on_button_remove_custom_file_clicked () {
            var selected_items = selection_model_custom_files.get_selection();

            for (var i = selected_items.get_size(); i > 0; i--) {
                var idx = selected_items.get_nth ((uint)i);
                stringlist_custom_files.remove (idx);
            }

            update_payload_count ();
        }

        private void on_fuzzdb_checkbox_toggled (Gtk.CheckButton checkbox, FuzzDBFile file) {
            file.toggle_active (checkbox.active);
            file.set_parent_inconsistent ();
            update_payload_count ();
        }

        [GtkCallback]
        private void on_entry_fuzzdb_search_search_changed () {
            filter_fuzzdb.changed (Gtk.FilterChange.DIFFERENT);
        }

        private void on_setup_label_column (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var label = new Gtk.Label ("");
            label.halign = Gtk.Align.START;
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            ((Gtk.ListItem) list_item_obj).child = label;
        }

        private void on_setup_tree (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var checkbox = new Gtk.CheckButton ();
            checkbox.halign = Gtk.Align.START;

            checkbox.toggled.connect (() => {
                var file = checkbox.get_data<FuzzDBFile> ("file");
                if (file == null) {
                    return;
                }
                on_fuzzdb_checkbox_toggled(checkbox, file);
            });
            
            var expander = new Gtk.TreeExpander ();
            expander.child = checkbox;
            ((Gtk.ListItem) list_item_obj).child = expander;
        }

        private void on_unbind_column_fuzzdb (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var fuzzdb_file = list_item.item as FuzzDBFile;
            if (fuzzdb_file != null && fuzzdb_file.signal_id != null) {
                fuzzdb_file.disconnect(fuzzdb_file.signal_id);
                fuzzdb_file.signal_id = null;
            }
        }

        private void populate_payloads () {
            if (application_window.core_address == "") {
                return;
            }
            var url = "http://" + application_window.core_address + "/inject_operations/payloads";

            var message = new Soup.Message ("GET", url);

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                if (message.status_code != 200) {
                    return;
                }

                liststore_fuzzdb_root.remove_all ();

                try {
                    var bytes = application_window.http_session.send_and_read_async.end (res);
                    var data = ((string) bytes.get_data ());

                    var parser = new Json.Parser ();
                    parser.load_from_data (data, -1);
                    var root_obj = parser.get_root().get_object();
                    populating_fuzzdb = true;
                    var children = root_obj.get_array_member ("SubEntries");
                    var fuzzdb_files = FuzzDBFile.children_from_json_array (children);
                    for (var i = 0; i < fuzzdb_files.size; i++) {
                        var f = fuzzdb_files[i];
                        f.set_parents ();
                        liststore_fuzzdb_root.append (f);
                    }
                } catch (Error err) {
                    stdout.printf("Error occurred while retrieving payloads: %s\n", err.message);
                }

                populating_fuzzdb = false;
                entry_fuzzdb_search.text = "";

                if (path_to_set != "") {
                    set_fuzzdb_path (path_to_set);
                    path_to_set = "";
                }
            });

        }

        private void reset_fuzzdb_tree () {
            for (var i = 0; i < liststore_fuzzdb_root.get_n_items(); i++) {
                var file = liststore_fuzzdb_root.get_item (i) as FuzzDBFile;
                if (file == null) {
                    continue;
                }
                file.uncheck ();
            }
        }

        public void reset_state () {
            entry_fuzzdb_search.text = "";
            reset_fuzzdb_tree ();
            selection_model_fuzzdb.unselect_all ();
            clear_custom_files ();
            entry_from.text = "0";
            entry_to.text = "0";
            populate_payloads ();
            update_payload_count ();
        }

        public void set_fuzzdb_path (string path) {
            for (var i = 0; i < liststore_fuzzdb_root.get_n_items (); i++) {
                var file = liststore_fuzzdb_root.get_item (i) as FuzzDBFile;
                if (file == null) {
                    continue;
                }
                file.set_checked_path (path);
            }

            update_payload_count ();
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

        private int get_fuzzdb_payload_count (FuzzDBFile file) {
            var payload_count = 0;

            for (var i = 0; i < file.children.size; i++) {
                payload_count += get_fuzzdb_payload_count (file.children.@get (i));
            }

            if (file.checked && file.children.size == 0) {
                payload_count += file.payload_count;
            }
            return payload_count;
        }

        [GtkCallback]
        private void update_payload_count() {
            var fuzzdb_payload_count = 0;

            for (var i = 0; i < liststore_fuzzdb_root.get_n_items (); i++) {
                var file = liststore_fuzzdb_root.get_item (i) as FuzzDBFile;
                if (file == null) {
                    continue;
                }
                fuzzdb_payload_count += get_fuzzdb_payload_count (file);
            }
            
            var payload_count = get_custom_file_payloads_internal ().length + (iterate_to - iterate_from).abs () + fuzzdb_payload_count;

            if (payload_count == 0) {
                label_payload_selection_count.label = "No payloads selected";
            } else if (payload_count == 1) {
                label_payload_selection_count.label = "1 payload selected";
            } else {
                label_payload_selection_count.label = payload_count.to_string () + " payloads selected";
            }
        }
    }
}
