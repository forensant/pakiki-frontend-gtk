using Soup;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/inject-point-selection-widget.ui")]
    class InjectPointSelectionWidget : Gtk.Box {
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

        // for the find dialog
        private Gtk.CheckButton checkbutton_exclude_resources;
        private Gtk.CheckButton checkbutton_negative_filter;
        private RequestsPane requests_pane;
        private Gtk.SearchEntry search_entry;

        public string hostname {
            get {
                return entry_hostname.text;
            }
        }

        public bool host_error_visible {
            get {
                return entry_hostname.secondary_icon_name != "";
            }
            set {
                entry_hostname.secondary_icon_name = (value ? "dialog-warning-symbolic" : "");
                entry_hostname.secondary_icon_tooltip_text = (value ? "Hostname must be entered" : "");
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
        }

        private void add_request_part_to_json (Json.Builder builder, string text, bool inject) {
            builder.begin_object ();
            builder.set_member_name ("RequestPart");
            builder.add_string_value (Base64.encode (text.data));
            builder.set_member_name ("Inject");
            builder.add_boolean_value (inject);
            builder.end_object ();
        }

        private void clear_between_selection (Gtk.TextIter start_pos, Gtk.TextIter end_pos) {
            unichar[] chrs_to_replace = {'»', '«'};
            var start_mark = text_view_request.buffer.create_mark (null, start_pos, true);
            var end_mark = text_view_request.buffer.create_mark (null, end_pos, true);

            for (var i = 0; i < chrs_to_replace.length; i++) {
                var chr = chrs_to_replace[i];
                while (true) {
                    Gtk.TextIter start_iter, end_iter;
                    text_view_request.buffer.get_iter_at_mark (out start_iter, start_mark);
                    text_view_request.buffer.get_iter_at_mark (out end_iter, end_mark);

                    var found = false;
                    if (start_iter.get_char () == chr) {
                        found = true;
                    }
                    else {
                        found = start_iter.forward_find_char ( (c) => {
                            return c == chr;
                        }, end_iter);
                    }

                    if (!found) {
                        break;
                    }

                    var end_chr_iter = start_iter;
                    end_chr_iter.forward_char ();
                    text_view_request.buffer.delete_interactive (ref start_iter, ref end_chr_iter, true);
                }
            }

            text_view_request.buffer.delete_mark (start_mark);
            text_view_request.buffer.delete_mark (end_mark);
        }

        public void clone_inject_operation (InjectOperation operation) {
            entry_title.text = operation.title;
            entry_hostname.text = operation.host;
            combobox_protocol.active = (operation.ssl ? 0 : 1);
            host_error_visible = false;
            text_view_request.buffer.text = operation.request;
            correct_separators_and_tag ();
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

        private bool is_iter_in_selection (Gtk.TextIter iter) {
            var last_start_iterator = iter;
            var last_end_iterator = iter;
            last_start_iterator.backward_find_char ( (c) => {
                return c == '»';
            }, null);
            last_end_iterator.backward_find_char ( (c) => {
                return c == '«';
            }, null);

            return (last_start_iterator.get_offset () > last_end_iterator.get_offset ());
        }

        [GtkCallback]
        private void on_button_add_separator_clicked () {
            label_error.label = "";

            Gtk.TextIter start_pos, end_pos;
            var text_selected = text_view_request.buffer.get_selection_bounds (out start_pos, out end_pos);
            var in_selection = is_iter_in_selection (start_pos);

            if (start_pos.equal (end_pos)) {
                // start == end, so insert a single character
                var chrToInsert = "»";    
                if (in_selection) {
                    chrToInsert = "«";
                }

                text_view_request.buffer.insert_at_cursor (chrToInsert, -1);
                text_view_request.has_focus = true;
            } else if (text_selected) {
                // it's a range

                if (in_selection) {
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
        private void on_button_clear_separator_clicked () {
            Gtk.TextIter start_pos, end_pos;
            var text_selected = text_view_request.buffer.get_selection_bounds (out start_pos, out end_pos);

            var in_selection = is_iter_in_selection (start_pos);

            if (!text_selected) {
                if (in_selection) {
                    // just clear the current selection that we're in
                    var last_start_iterator = start_pos;
                    last_start_iterator.backward_find_char ( (c) => {
                        return c == '»';
                    }, null);

                    var start_mark = text_view_request.buffer.create_mark (null, last_start_iterator, true);

                    var end_char_pos = end_pos;
                    end_char_pos.forward_find_char ( c => {
                        return c == '«';
                    }, null);

                    if (!end_char_pos.is_end ()) {
                        var mark_end_pos = end_char_pos;
                        mark_end_pos.forward_char ();
                        text_view_request.buffer.delete_interactive (ref end_char_pos, ref mark_end_pos, true);

                    }

                    Gtk.TextIter start_char_pos;
                    text_view_request.buffer.get_iter_at_mark (out start_char_pos, start_mark);
                    var mark_start_pos = start_char_pos;
                    mark_start_pos.forward_char ();
                    text_view_request.buffer.delete_interactive (ref mark_start_pos, ref start_char_pos, true);
                    text_view_request.buffer.delete_mark (start_mark);
                }
                else {
                    // if nothing is selected, clear all separators
                    Gtk.TextIter buffer_text_start, buffer_text_end;
                    text_view_request.buffer.get_start_iter (out buffer_text_start);
                    text_view_request.buffer.get_end_iter (out buffer_text_end);

                    clear_between_selection (buffer_text_start, buffer_text_end);
                } 
            }
            else {
                // if we have a selection covering multiple, then clear all selected
                Gtk.TextIter multiple_start_iter = start_pos;
                Gtk.TextIter multiple_end_iter = end_pos;
                if (in_selection) {
                    multiple_start_iter.backward_find_char ( (c) => {
                        return c == '»';
                    }, null);
                }
                if (is_iter_in_selection (end_pos)) {
                    var found = false;

                    if (multiple_end_iter.get_char () == '«') {
                        found = true;
                    }
                    else {
                        found = multiple_end_iter.forward_find_char ( (c) => {
                            return c == '«';
                        }, null);
                    }

                    if (found) {
                        multiple_end_iter.forward_char ();
                    }
                }

                clear_between_selection (multiple_start_iter, multiple_end_iter);
            }

            correct_separators_and_tag ();
            text_view_request.has_focus = true;
        }

        [GtkCallback]
        private void on_button_find_clicked() {
            var dialog = new Gtk.Dialog.with_buttons ("Find Request", application_window, Gtk.DialogFlags.MODAL);
            dialog.add_button ("Cancel", Gtk.ResponseType.CANCEL);
            dialog.add_button ("OK", Gtk.ResponseType.OK);
            var selected_guid = "";

            var searchbar = new Gtk.SearchBar ();
            searchbar.show_close_button = false;
            var box_search = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            if (search_entry == null) {
                search_entry = new Gtk.SearchEntry ();
            }
            search_entry.placeholder_text = "Filter Requests";
            box_search.pack_start (search_entry, false, false, 0);

            if (checkbutton_negative_filter == null) {
                checkbutton_negative_filter = new Gtk.CheckButton.with_mnemonic ("_Negative Filter");
            }
            checkbutton_negative_filter.active = false;
            box_search.pack_start (checkbutton_negative_filter, false, false, 0);

            if (checkbutton_exclude_resources == null) {
                checkbutton_exclude_resources = new Gtk.CheckButton.with_mnemonic ("_Exclude Resources (Images, Stylesheets, etc)");
            }
            checkbutton_exclude_resources.active = true;
            box_search.pack_start (checkbutton_exclude_resources, false, false, 0);

            box_search.hexpand = true;
            searchbar.visible = true;
            searchbar.search_mode_enabled = true;
            searchbar.add (box_search);
            searchbar.connect_entry (search_entry);
            dialog.get_content_area ().pack_start (searchbar, false, false, 0);
            searchbar.show_all ();

            if (requests_pane == null) {
                requests_pane = new RequestsPane (application_window, false);
            }
            requests_pane.process_launch_successful (true);
            requests_pane.reset_state ();
            requests_pane.request_selected.connect ( (guid) => { selected_guid = guid; });
            requests_pane.process_actions = false;
            requests_pane.request_double_clicked.connect ( (guid) => {
                selected_guid = guid;
                dialog.response (Gtk.ResponseType.OK);
            });
            requests_pane.show ();
            dialog.get_content_area ().pack_start (requests_pane, true, true, 0);
            dialog.set_default_response (Gtk.ResponseType.OK);
            dialog.set_default_size (application_window.default_width - 100, application_window.default_height - 150);

            search_entry.search_changed.connect (() => {
                set_find_filter ();
            });

            checkbutton_exclude_resources.toggled.connect (() => {
                set_find_filter ();
            });

            checkbutton_negative_filter.toggled.connect (() => {
                set_find_filter ();
            });

            set_find_filter ();

            var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
            separator.hexpand = true;
            dialog.get_content_area ().pack_start (separator, false, false, 0);

            dialog.get_action_area ().margin_top = 12;
            dialog.get_action_area ().margin_bottom = 12;
            dialog.get_action_area ().margin_end = 18;

            dialog.response.connect ( (response_id) => {
                if (response_id == Gtk.ResponseType.OK) {
                    this.populate_request (selected_guid);
                }
                dialog.destroy ();

                checkbutton_negative_filter.destroy ();
                checkbutton_exclude_resources.destroy ();
                search_entry.destroy ();
                requests_pane.destroy ();
                requests_pane = null;
                checkbutton_negative_filter = null;
                checkbutton_exclude_resources = null;
            });

            dialog.show ();
            dialog.run ();
        }

        private bool on_text_view_request_key_release_event (Gdk.EventKey event) {
            correct_separators_and_tag ();
            return false;
        }

        public void populate_request (string guid) {
            var url = "http://" + application_window.core_address + "/requests/" + guid;

            var message = new Soup.Message ("GET", url);

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    var resp = application_window.http_session.send_and_read_async.end (res);
                    var resp_body = (string) resp.get_data ();

                    var parser = new Json.Parser ();
                    parser.load_from_data (resp_body, -1);

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
            entry_hostname.secondary_icon_name = "";
        }

        private void set_find_filter () {
            requests_pane.on_search (search_entry.get_text (),
                checkbutton_negative_filter.get_active (),
                checkbutton_exclude_resources.get_active (),
                "HTTP");
        }
    }
}
