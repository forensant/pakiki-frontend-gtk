using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/inject-new.ui")]
    class InjectNew : Gtk.Box {

        [GtkChild]
        private unowned Gtk.ComboBox combobox_protocol;
        [GtkChild]
        private unowned Gtk.Entry entry_hostname;
        [GtkChild]
        private unowned Gtk.Entry entry_from;
        [GtkChild]
        private unowned Gtk.Entry entry_title;
        [GtkChild]
        private unowned Gtk.Entry entry_to;
        [GtkChild]
        private unowned Gtk.Label label_from;
        [GtkChild]
        private unowned Gtk.Label label_fuzzdb;
        [GtkChild]
        private unowned Gtk.Label label_host;
        [GtkChild]
        private unowned Gtk.Label label_known_files;
        [GtkChild]
        private unowned Gtk.Label label_request;
        [GtkChild]
        private unowned Gtk.Label label_title;
        [GtkChild]
        private unowned Gtk.Label label_to;
        [GtkChild]
        private unowned Gtk.ListStore liststore_fuzzdb;
        [GtkChild]
        private unowned Gtk.ListStore liststore_known_files;
        [GtkChild]
        private unowned Gtk.TextView text_view_request;
        [GtkChild]
        private unowned Gtk.TreeView treeview_fuzzdb;
        [GtkChild]
        private unowned Gtk.TreeView treeview_known_files;

        private InjectPane inject_pane;
        
        enum Column {
            CHECKED,
            TITLE,
            FILENAME
        }

        public InjectNew (InjectPane inject_pane) {
            this.inject_pane = inject_pane;
            var renderer_text = new Gtk.CellRendererText();
            combobox_protocol.pack_start (renderer_text, true);
            combobox_protocol.add_attribute (renderer_text, "text", 0);
            combobox_protocol.set_active (0);

            // set the mnemonics
            label_title.set_text_with_mnemonic ("_Title");
            label_title.mnemonic_widget = entry_title;
            label_host.set_text_with_mnemonic ("_Host");
            label_host.mnemonic_widget = combobox_protocol;
            label_request.set_text_with_mnemonic ("_Request");
            label_request.mnemonic_widget = entry_hostname;
            label_fuzzdb.set_text_with_mnemonic ("_FuzzDB");
            label_fuzzdb.mnemonic_widget = treeview_fuzzdb;
            label_known_files.set_text_with_mnemonic ("_Known Files");
            label_known_files.mnemonic_widget = treeview_known_files;
            label_from.set_text_with_mnemonic ("F_rom");
            label_from.mnemonic_widget = entry_from;
            label_to.set_text_with_mnemonic ("T_o");
            label_to.mnemonic_widget = entry_to;

            populate_payloads ();

            var fuzzdb_toggle_renderer = new Gtk.CellRendererToggle ();
            fuzzdb_toggle_renderer.set_activatable (true);
            fuzzdb_toggle_renderer.toggled.connect (on_fuzzdb_toggled);

            var known_files_toggle_renderer = new Gtk.CellRendererToggle ();
            known_files_toggle_renderer.set_activatable (true);
            known_files_toggle_renderer.toggled.connect (on_known_files_toggled);

            treeview_fuzzdb.insert_column_with_attributes (-1, "Checked",
                fuzzdb_toggle_renderer, "active", 0);

            treeview_fuzzdb.insert_column_with_attributes (-1, "Title",
                new Gtk.CellRendererText(), "text",
                Column.TITLE);

            treeview_known_files.insert_column_with_attributes (-1, "Checked",
                known_files_toggle_renderer, "active",
                Column.CHECKED);

            treeview_known_files.insert_column_with_attributes (-1, "TILE",
                new Gtk.CellRendererText(), "text",
                Column.TITLE);

        }

        private void get_selected_filenames (Json.Builder builder, Gtk.ListStore liststore) {
            builder.begin_array ();

            liststore.@foreach ((model, path, iter) => {
                Value is_checked;
                model.get_value (iter, Column.CHECKED, out is_checked);

                if (is_checked.get_boolean ()) {
                    Value filename;
                    model.get_value (iter, Column.FILENAME, out filename);
                    builder.add_string_value (filename.get_string ());
                }

                return false; // iterate until the end
            });

            builder.end_array ();
        }

        private void on_fuzzdb_toggled (string path) {
            Gtk.TreeIter iter;
            liststore_fuzzdb.get_iter(out iter, new Gtk.TreePath.from_string(path));

            Value is_checked;
            liststore_fuzzdb.get_value(iter, Column.CHECKED, out is_checked);
            liststore_fuzzdb.set_value(iter, Column.CHECKED, !is_checked.get_boolean ());
            is_checked.unset();
        }

        private void on_known_files_toggled (string path) {
            Gtk.TreeIter iter;
            liststore_known_files.get_iter(out iter, new Gtk.TreePath.from_string(path));

            Value is_checked;
            liststore_known_files.get_value(iter, Column.CHECKED, out is_checked);
            liststore_known_files.set_value(iter, Column.CHECKED, !is_checked.get_boolean ());
            is_checked.unset();
        }

        [GtkCallback]
        private void on_run_clicked () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://127.0.0.1:10101/inject_operations/run");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("host");
            builder.add_string_value (entry_hostname.get_text ());
            builder.set_member_name ("ssl");
            builder.add_boolean_value (combobox_protocol.get_active() == 0);
            builder.set_member_name ("request");
            builder.add_string_value ( Base64.encode (text_view_request.buffer.text.data));
            builder.set_member_name ("Title");
            builder.add_string_value (entry_title.get_text ());
            builder.set_member_name ("iterateFrom");
            builder.add_int_value (int.parse (entry_from.get_text ()));
            builder.set_member_name ("iterateTo");
            builder.add_int_value (int.parse (entry_to.get_text ()));
            builder.set_member_name ("fuzzDB");
            get_selected_filenames (builder, liststore_fuzzdb);
            builder.set_member_name ("knownFiles");
            get_selected_filenames (builder, liststore_known_files);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            stdout.printf("JSON: %s\n", parameters);

            message.set_request("application/json", Soup.MemoryUse.COPY, parameters.data);
            
            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    parser.load_from_data (jsonData, -1);

                    var rootObj = parser.get_root().get_object();
                    
                    var guid = rootObj.get_string_member("GUID");

                    inject_pane.select_when_received (guid);
                }
                catch(Error e) {
                    stdout.printf("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                }

            });
        } 

        private void populate_payloads () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://127.0.0.1:10101/inject_operations/payloads");

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);
                    var rootObj = parser.get_root().get_object();
                    populate_payload_liststore (liststore_fuzzdb, rootObj.get_array_member ("Attack"));
                    populate_payload_liststore (liststore_known_files, rootObj.get_array_member ("KnownFiles"));
                } catch (Error err) {
                    stdout.printf("Error occurred while retrieving payloads: %s\n", err.message);
                }
            });
        }

        private void populate_payload_liststore (Gtk.ListStore liststore, Json.Array array) {
            foreach (var element in array.get_elements ()) {
                Json.Object payload = element.get_object ();
                Gtk.TreeIter iter;

                liststore.insert_with_values (out iter, -1, 
                    Column.CHECKED, false,
                    Column.TITLE, payload.get_string_member ("Title"),
                    Column.FILENAME, payload.get_string_member ("Filename"));
            }
        }

        public void populate_request (string guid) {
            var url = "http://localhost:10101/project/request?guid=" + guid;

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var rootObj = parser.get_root().get_object();

                    entry_hostname.set_text (rootObj.get_string_member ("Hostname"));
                    combobox_protocol.set_active (rootObj.get_string_member ("Protocol") == "https://" ? 0 : 1);
                    text_view_request.buffer.set_text ( (string) Base64.decode (rootObj.get_string_member ("RequestData")));
                } catch (Error err) {
                    stdout.printf("Error retrieving request details: %s\n", err.message);
                }

                entry_title.grab_focus ();
            });
        }

    }
}
