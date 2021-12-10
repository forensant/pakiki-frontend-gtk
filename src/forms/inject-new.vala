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
        private unowned Gtk.Entry entry_title;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Spinner spinner;
        [GtkChild]
        private unowned Gtk.TextView text_view_request;

        private ApplicationWindow application_window;
        private InjectPane inject_pane;
        private PayloadSelectionWidget payload_selection_widget;

        public InjectNew (ApplicationWindow application_window, InjectPane inject_pane) {
            this.application_window = application_window;
            this.inject_pane = inject_pane;
            var renderer_text = new Gtk.CellRendererText();
            combobox_protocol.pack_start (renderer_text, true);
            combobox_protocol.add_attribute (renderer_text, "text", 0);
            combobox_protocol.set_active (0);

            payload_selection_widget = new PayloadSelectionWidget (application_window, true);
            payload_selection_widget.margin_top = 12;
            this.pack_start (payload_selection_widget, true, true, 0);
            this.reorder_child (payload_selection_widget, 4);
            payload_selection_widget.show ();

            text_view_request.buffer.create_tag ("selection", "background", "yellow");
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

        private void get_custom_files (Json.Builder builder) {
            builder.set_member_name ("customPayloads");
            builder.begin_array ();

            foreach (string payload in payload_selection_widget.custom_file_payloads) {
                builder.add_string_value (payload);
            }
            
            builder.end_array ();

            builder.set_member_name ("customFilenames");
            builder.begin_array ();

            foreach (string filename in payload_selection_widget.custom_filenames) {
                builder.add_string_value (filename);
            }
            
            builder.end_array ();
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

        private void get_selected_filenames (Json.Builder builder) {
            builder.begin_array ();

            foreach (string filename in payload_selection_widget.fuzzdb_files) {
                builder.add_string_value (filename);
            }

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
        private void on_run_clicked () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://" + application_window.core_address + "/inject_operations/run");

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
            builder.add_int_value (payload_selection_widget.iterate_from);
            builder.set_member_name ("iterateTo");
            builder.add_int_value (payload_selection_widget.iterate_to);
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

        public void populate_request (string guid) {
            var url = "http://" + application_window.core_address + "/project/request?guid=" + guid;

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

            payload_selection_widget.reset_state ();
        }
    }
}
