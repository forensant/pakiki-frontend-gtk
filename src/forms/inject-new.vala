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
        private unowned Gtk.Label label_error;
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

            text_view_request.buffer.create_tag ("selection", "background", "yellow");

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

        private void correct_separators_and_tag () {
            Gtk.TextIter start_pos, end_pos;
            text_view_request.buffer.get_bounds (out start_pos, out end_pos);
            text_view_request.buffer.remove_all_tags (start_pos, end_pos);

            var in_inject_point = false;
            Gtk.TextIter selection_start = start_pos;

            while (!start_pos.equal (end_pos)) {
                if (start_pos.get_char () == '»') {
                    if (in_inject_point) {
                        in_inject_point = false;
                        text_view_request.buffer.apply_tag_by_name ("selection", selection_start, start_pos);

                        // correct the character
                        var pos_after_current = start_pos;
                        if (!pos_after_current.forward_char ()) {
                            break;
                        }

                        var start_mark = text_view_request.buffer.create_mark (null, start_pos, true);
                        text_view_request.buffer.@delete (ref start_pos, ref pos_after_current);
                        text_view_request.buffer.get_iter_at_mark (out start_pos, start_mark);
                        text_view_request.buffer.delete_mark (start_mark);
                        text_view_request.buffer.insert (ref start_pos, "«", -1);
                    } else {
                        in_inject_point = true;
                        selection_start = start_pos;
                        
                        if (!selection_start.forward_char ()) {
                            break;
                        }
                    }
                } else if (start_pos.get_char () == '«') {
                    if (in_inject_point) {
                        in_inject_point = false;
                        text_view_request.buffer.apply_tag_by_name ("selection", selection_start, start_pos);
                    } else {
                        in_inject_point = true;

                        // correct the character
                        var pos_after_current = start_pos;
                        if (!pos_after_current.forward_char ()) {
                            break;
                        }

                        var start_mark = text_view_request.buffer.create_mark (null, start_pos, true);
                        text_view_request.buffer.@delete (ref start_pos, ref pos_after_current);
                        text_view_request.buffer.get_iter_at_mark (out start_pos, start_mark);
                        text_view_request.buffer.delete_mark (start_mark);
                        text_view_request.buffer.insert (ref start_pos, "»", -1);

                        selection_start = start_pos;

                        if (!selection_start.forward_char ()) {
                            break;
                        }
                    }
                }

                if (!start_pos.forward_char ()) {
                    break;
                }
            }

            if (in_inject_point) {
                text_view_request.buffer.apply_tag_by_name ("selection", selection_start, start_pos);
            }
        }

        private void add_request_part_to_json (Json.Builder builder, string text, bool inject) {
            builder.begin_object ();
            builder.set_member_name ("RequestPart");
            builder.add_string_value (Base64.encode (text.data));
            builder.set_member_name ("Inject");
            builder.add_boolean_value (inject);
            builder.end_object ();
        }

        private void get_request_json (Json.Builder builder) {
            builder.begin_array ();

            Gtk.TextIter start_pos, end_pos;
            text_view_request.buffer.get_bounds (out start_pos, out end_pos);
            var i = 0;
            string text = "";

            while (!start_pos.equal (end_pos)) {
                var chr = start_pos.get_char ();
                if (chr == '»' || chr == '«') {
                    add_request_part_to_json (builder, text, i % 2 == 1);
                    text = "";
                    i += 1;
                } else {
                    text += chr.to_string ();
                }

                if (!start_pos.forward_char ()) {
                    break;
                }
            }

            if (text != "") {
                add_request_part_to_json (builder, text, i % 2 == 1);
            }

            builder.end_array ();
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

        [GtkCallback]
        private bool on_text_view_request_key_release_event (Gdk.EventKey event) {
            correct_separators_and_tag ();
            return false;
        }

        [GtkCallback]
        private void on_button_add_separator_clicked () {
            label_error.label = "";

            Gtk.TextIter start_pos, end_pos;
            var text_selected = text_view_request.buffer.get_selection_bounds (out start_pos, out end_pos);
            var text = text_view_request.buffer.text;

            var last_start_iterator = start_pos;
            var last_end_iterator = start_pos;
            last_start_iterator.backward_find_char ( (c) => {
                return c == '»';
            }, null);
            last_end_iterator.backward_find_char ( (c) => {
                return c == '«';
            }, null);

            var last_character_opened = (last_start_iterator.get_offset () > last_end_iterator.get_offset ());

            if (start_pos.equal (end_pos)) {
                // start == end, so insert a single character
                var chrToInsert = "»";    
                if (last_character_opened) {
                    chrToInsert = "«";
                }

                text_view_request.buffer.insert_at_cursor (chrToInsert, -1);
                text_view_request.has_focus = true;
            } else if (text_selected) {
                // it's a range

                if (last_character_opened) {
                    label_error.label = "Cannot add separator as there's a previously unclosed separator.";
                    return;
                }

                var selected_text = text_view_request.buffer.get_text (start_pos, end_pos, false);
                if (selected_text.contains ("»") || selected_text.contains ("«")) {
                    label_error.label = "Cannot add separator as part of a range is within the selected text.";
                    return;
                }

                var start_mark = text_view_request.buffer.create_mark (null, start_pos, true);
                text_view_request.buffer.insert (ref end_pos, "«", -1);
                text_view_request.buffer.get_iter_at_mark (out start_pos, start_mark);
                text_view_request.buffer.insert (ref start_pos, "»", -1);
                text_view_request.buffer.get_selection_bounds (out start_pos, out end_pos);
                end_pos.backward_char ();
                text_view_request.buffer.select_range (start_pos, end_pos);
                text_view_request.buffer.delete_mark (start_mark);
            }

            correct_separators_and_tag ();
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
            get_request_json (builder);
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
