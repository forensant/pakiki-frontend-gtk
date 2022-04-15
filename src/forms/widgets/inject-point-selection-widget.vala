using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/inject-point-selection-widget.ui")]
    class InjectPointSelectionWidget : Gtk.Box {
        public signal void find_clicked ();

        [GtkChild]
        private unowned Gtk.Button button_find;
        [GtkChild]
        private unowned Gtk.ComboBox combobox_protocol;
        [GtkChild]
        private unowned Gtk.Entry entry_hostname;
        [GtkChild]
        private unowned Gtk.Entry entry_title;
        [GtkChild]
        private unowned Gtk.Label label_host;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_title;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_text_view_request;
        
        private ApplicationWindow application_window;
        private RequestTextEditor text_view_request;

        public string hostname {
            get {
                return entry_hostname.text;
            }
        }

        public bool find_visible {
            get {
                return button_find.visible;
            }
            set {
                button_find.visible = value;
            }
        }

        public bool ssl {
            get {
                return combobox_protocol.active == 0;
            }
        }

        public string title {
            get {
                return entry_title.text;
            }
        }

        public bool title_visible {
            get {
                return entry_title.visible;
            }
            set {
                entry_title.visible = value;
                label_title.visible = value;
                label_host.visible = value;
                if (value == true) {
                    entry_hostname.placeholder_text = "";
                } else {
                    entry_hostname.placeholder_text = "Hostname";
                }
            }
        }

        public InjectPointSelectionWidget (ApplicationWindow application_window) {
            this.application_window = application_window;
            var renderer_text = new Gtk.CellRendererText();
            combobox_protocol.pack_start (renderer_text, true);
            combobox_protocol.add_attribute (renderer_text, "text", 0);
            combobox_protocol.set_active (0);

            text_view_request = new RequestTextEditor (application_window);
            scrolled_window_text_view_request.add (text_view_request);
            text_view_request.key_release_event.connect (on_text_view_request_key_release_event);

            text_view_request.buffer.create_tag ("selection", "background", "yellow", "foreground", "black");

            button_find.clicked.connect ( () => this.find_clicked () );
        }

        private void add_request_part_to_json (Json.Builder builder, string text, bool inject) {
            builder.begin_object ();
            builder.set_member_name ("RequestPart");
            builder.add_string_value (Base64.encode (text.data));
            builder.set_member_name ("Inject");
            builder.add_boolean_value (inject);
            builder.end_object ();
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

        public void get_request_json (Json.Builder builder) {
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

        private bool on_text_view_request_key_release_event (Gdk.EventKey event) {
            correct_separators_and_tag ();
            return false;
        }

        public void populate_request (string guid) {
            var url = "http://" + application_window.core_address + "/requests/" + guid;

            var message = new Soup.Message ("GET", url);

            application_window.http_session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var root_obj = parser.get_root().get_object();

                    reset_state ();
                    entry_hostname.text = root_obj.get_string_member ("Hostname");
                    combobox_protocol.active = (root_obj.get_string_member ("Protocol") == "https://" ? 0 : 1);

                    var request_parts = root_obj.get_array_member ("SplitRequest");

                    if (request_parts.get_length () == 0) {
                        text_view_request.buffer.text = (string) Base64.decode (root_obj.get_string_member ("RequestData"));
                    } else {
                        text_view_request.buffer.text = "";
                        for (int i = 0; i < request_parts.get_length (); i++) {
                            var part = request_parts.get_element (i).get_object ();
                            var text = (string) Base64.decode (part.get_string_member ("RequestPart"));
                            if (part.get_boolean_member ("Inject")) {
                                text = "»" + text + "«";
                            }

                            text_view_request.buffer.text += text;
                        }

                        correct_separators_and_tag ();
                    }
                    
                } catch (Error err) {
                    stdout.printf("Error retrieving request details: %s\n", err.message);
                }

                if (entry_title.visible) {
                    entry_title.grab_focus ();
                }
            });
        }

        public void reset_state () {
            entry_title.text = "";
            entry_hostname.text = "";
            combobox_protocol.active = 0;
            text_view_request.buffer.text = "";
        }
    }
}
