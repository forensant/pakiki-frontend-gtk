using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/inject-new.ui")]
    class InjectNew : Gtk.Box {

        [GtkChild]
        private unowned Gtk.Button button_run;
        [GtkChild]
        private unowned Gtk.ComboBox combobox_protocol;
        [GtkChild]
        private unowned Gtk.Entry entry_hostname;
        [GtkChild]
        private unowned Gtk.Entry entry_from;
        [GtkChild]
        private unowned Gtk.Entry entry_fuzzdb_search;
        [GtkChild]
        private unowned Gtk.Entry entry_title;
        [GtkChild]
        private unowned Gtk.Entry entry_to;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.ListStore liststore_custom_files;
        [GtkChild]
        private unowned Gtk.Spinner spinner;
        [GtkChild]
        private unowned Gtk.TextView text_view_request;
        [GtkChild]
        private unowned Gtk.TreeStore treestore_fuzzdb;
        [GtkChild]
        private unowned Gtk.TreeView treeview_custom_files;
        [GtkChild]
        private unowned Gtk.TreeView treeview_fuzzdb;

        private ApplicationWindow application_window;
        private InjectPane inject_pane;
        private Gtk.TreeModelFilter treeview_model_filter;
        private bool populating_fuzzdb;
        
        enum Column {
            CHECKED,
            TITLE,
            FILENAME,
            PAYLOADS
        }

        public InjectNew (ApplicationWindow application_window, InjectPane inject_pane) {
            this.application_window = application_window;
            this.inject_pane = inject_pane;
            var renderer_text = new Gtk.CellRendererText();
            combobox_protocol.pack_start (renderer_text, true);
            combobox_protocol.add_attribute (renderer_text, "text", 0);
            combobox_protocol.set_active (0);

            populating_fuzzdb = false;
            populate_payloads ();

            text_view_request.buffer.create_tag ("selection", "background", "yellow");

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

        private void get_custom_files (Json.Builder builder) {
            builder.set_member_name ("customPayloads");
            builder.begin_array ();

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
                        builder.add_string_value (line);
                    }
                } catch (Error e) {
                    error ("%s", e.message);
                }

                return false; // iterate until the end
            });

            builder.end_array ();

            builder.set_member_name ("customFilenames");
            builder.begin_array ();

            liststore_custom_files.@foreach ((model, path, iter) => {
                Value path_value;
                model.get_value (iter, 0, out path_value);
                var file_path = path_value.get_string ();
                builder.add_string_value (file_path);

                return false; // likewise iterate until the end
            });

            builder.end_array ();
        }

        private void get_selected_filenames (Json.Builder builder) {
            builder.begin_array ();

            treestore_fuzzdb.@foreach ((model, path, iter) => {
                Value is_checked;
                model.get_value (iter, Column.CHECKED, out is_checked);

                if (is_checked.get_string () == "Checked" && model.iter_n_children (iter) == 0) {
                    Value filename;
                    model.get_value (iter, Column.FILENAME, out filename);
                    builder.add_string_value (filename.get_string ());
                }

                return false; // iterate until the end
            });

            builder.end_array ();
        }

        [GtkCallback]
        private void on_button_add_separator_clicked () {
            label_error.label = "";

            Gtk.TextIter start_pos, end_pos;
            var text_selected = text_view_request.buffer.get_selection_bounds (out start_pos, out end_pos);

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
        }

        private void on_fuzzdb_toggled (string path) {
            Gtk.TreeIter iter;
            treestore_fuzzdb.get_iter(out iter, new Gtk.TreePath.from_string(path));

            Value is_checked;
            treestore_fuzzdb.get_value(iter, Column.CHECKED, out is_checked);

            var value_to_set = "Checked";
            if (is_checked.get_string () == "Checked") {
                value_to_set = "Unchecked";   
            }
            treestore_fuzzdb.set_value(iter, Column.CHECKED, value_to_set);

            set_fuzzdb_parent_status (iter);
            set_fuzzdb_child_status (iter, value_to_set);

            is_checked.unset();
        }

        [GtkCallback]
        private void on_run_clicked () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://127.0.0.1:10101/inject_operations/run");

            button_run.sensitive = false;
            spinner.active = true;

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
            get_selected_filenames (builder);
            get_custom_files (builder);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request("application/json", Soup.MemoryUse.COPY, parameters.data);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    parser.load_from_data (jsonData, -1);

                    var rootObj = parser.get_root().get_object();
                    
                    var guid = rootObj.get_string_member("GUID");
                    reset_state ();

                    inject_pane.select_when_received (guid);
                }
                catch(Error e) {
                    stdout.printf("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                }

                button_run.sensitive = true;
                spinner.active = false;
            });
        }

        [GtkCallback]
        private bool on_text_view_request_key_release_event (Gdk.EventKey event) {
            correct_separators_and_tag ();
            return false;
        }

        private void populate_payloads () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://127.0.0.1:10101/inject_operations/payloads");

            session.queue_message (message, (sess, mess) => {
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
            });
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

                    reset_state ();
                    entry_hostname.text = rootObj.get_string_member ("Hostname");
                    combobox_protocol.active = (rootObj.get_string_member ("Protocol") == "https://" ? 0 : 1);
                    text_view_request.buffer.text = (string) Base64.decode (rootObj.get_string_member ("RequestData"));
                } catch (Error err) {
                    stdout.printf("Error retrieving request details: %s\n", err.message);
                }

                entry_title.grab_focus ();
            });
        }

        public void reset_state () {
            entry_title.text = "";
            entry_hostname.text = "";
            combobox_protocol.active = 0;
            text_view_request.buffer.text = "";

            // Reset the rest of the state
            treestore_fuzzdb.@foreach ((model, path, iter) => {
                treestore_fuzzdb.set_value (iter, Column.CHECKED, "Unchecked");
                return false; // iterate until the end
            });
            
            treeview_fuzzdb.collapse_all ();
            treeview_fuzzdb.get_selection ().unselect_all ();
            liststore_custom_files.clear ();
            entry_from.text = "0";
            entry_to.text = "0";
        }

        private void set_fuzzdb_child_status (Gtk.TreeIter iter, string value_to_set) {
            var child_count = treestore_fuzzdb.iter_n_children (iter);
            for (int i = 0; i < child_count; i++) {
                Gtk.TreeIter child_iter;
                if (!treestore_fuzzdb.iter_nth_child (out child_iter, iter, i)) {
                    continue;
                }

                treestore_fuzzdb.set_value(child_iter, Column.CHECKED, value_to_set);
                set_fuzzdb_child_status (child_iter, value_to_set);
            }
        }

        private void set_fuzzdb_parent_status (Gtk.TreeIter current_child) {
            Gtk.TreeIter parent;
            bool has_parent = treestore_fuzzdb.iter_parent (out parent, current_child);

            if (!has_parent) {
                return;
            }

            var false_found = false;
            var true_found = false;
            var inconsistent_found = false;

            var child_count = treestore_fuzzdb.iter_n_children (parent);
            for (int i = 0; i < child_count; i++) {
                Gtk.TreeIter child_iter;
                if (!treestore_fuzzdb.iter_nth_child (out child_iter, parent, i)) {
                    continue;
                }

                Value is_checked;
                treestore_fuzzdb.get_value(child_iter, Column.CHECKED, out is_checked);

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

            treestore_fuzzdb.set_value (parent, Column.CHECKED, checked_val);
            set_fuzzdb_parent_status (parent);
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
