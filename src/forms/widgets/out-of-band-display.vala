namespace Pakiki {   
    class OutOfBandDisplay : Gtk.Grid {
        private ApplicationWindow application_window;
        private SyntaxHighlighter syntax_highlighter = new SyntaxHighlighter ();

        public OutOfBandDisplay(ApplicationWindow application_window) {
            this.application_window = application_window;
            margin = 18;

            row_spacing = 6;
            column_spacing = 12;
        }

        public void render_interaction (Json.Object request_contents, Json.Array data_packets) {
            reset_state ();

            var request_data = request_contents.get_string_member ("Request");
            var response_data = request_contents.get_string_member ("Response");

            Json.Object? request_packet = null;
            Json.Object? response_packet = null;

            for (int i = 0; i < data_packets.get_length (); i++) {
                var packet = data_packets.get_element (i).get_object ();

                if (packet == null) {
                    continue;
                }

                if (!packet.has_member ("Direction")) {
                    continue;
                }

                if (packet.get_string_member ("Direction") == "Request") {
                    request_packet = packet;
                } else {
                    response_packet = packet;
                }
            }

            if (request_packet == null || response_packet == null) {
                return;
            }

            var row = 0;

            var parser = new Json.Parser ();
            try {
                if (!parser.load_from_data (request_packet.get_string_member ("DisplayData"), -1)) {
                    return;
                }

                var root = parser.get_root ();
                if (root == null && root.get_object () == null) {
                    return;
                }

                var request_root = root.get_object ();
                request_root.foreach_member ( (object, name, value) => {
                    var str_val = value.get_string ();
                    if (str_val == null || str_val == "") {
                        return;
                    }

                    var label_name = new Gtk.Label (name + ":");
                    var label_value = new Gtk.Label (str_val);
                    label_value.selectable = true;

                    label_name.valign = Gtk.Align.START;
                    label_name.halign = Gtk.Align.END;
                    label_value.valign = Gtk.Align.START;
                    label_value.halign = Gtk.Align.START;

                    this.attach (label_name, 0, row, 1, 1);
                    this.attach (label_value, 1, row, 1, 1);

                    label_name.show ();
                    label_value.show ();

                    row++;
                });
            } catch {
            }

            var request_label = new Gtk.Label ("Request:");
            request_label.valign = Gtk.Align.START;
            request_label.halign = Gtk.Align.END;
            this.attach (request_label, 0, row, 1, 1);
            var request_packet_data = Base64.decode(request_packet.get_string_member ("Data"));
            var request_text_view = new Gtk.TextView ();
            request_text_view.monospace = true;
            if (request_data == null) {
                request_text_view.buffer.text = (string)request_packet_data;
            } else {
                request_data = (string)Base64.decode(request_data);
                syntax_highlighter.set_tags (request_text_view.buffer);
                syntax_highlighter.set_highlightjs_tags (request_text_view.buffer, request_data, null); 
            }
            
            request_text_view.editable = false;
            request_text_view.margin = 8;
            var request_scroll_view = new Gtk.ScrolledWindow (null, null);
            request_scroll_view.add (request_text_view);
            request_scroll_view.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            request_scroll_view.vscrollbar_policy = Gtk.PolicyType.NEVER;
            request_scroll_view.shadow_type = Gtk.ShadowType.IN;
            request_scroll_view.expand = true;
            request_scroll_view.show ();

            this.attach (request_scroll_view, 1, row, 1, 1);

            request_label.show ();
            request_text_view.show ();

            row++;

            var response_label = new Gtk.Label ("Response:");
            response_label.valign = Gtk.Align.START;
            response_label.halign = Gtk.Align.END;
            this.attach (response_label, 0, row, 1, 1);
            var response_packet_data = Base64.decode(response_packet.get_string_member ("Data"));
            var response_text_view = new Gtk.TextView ();
            response_text_view.monospace = true;
            response_text_view.buffer.text = (string)response_data;
            response_text_view.editable = false;
            response_text_view.margin = 8;
            if (response_data == null) {
                response_text_view.buffer.text = (string)response_packet_data;
            } else {
                syntax_highlighter.set_tags (response_text_view.buffer);
                response_data = (string)Base64.decode(response_data);
                syntax_highlighter.set_highlightjs_tags (response_text_view.buffer, response_data, null); 
            }
            var response_scroll_view = new Gtk.ScrolledWindow (null, null);
            response_scroll_view.add (response_text_view);
            response_scroll_view.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            response_scroll_view.vscrollbar_policy = Gtk.PolicyType.NEVER;
            response_scroll_view.shadow_type = Gtk.ShadowType.IN;
            response_scroll_view.expand = true;
            response_scroll_view.show ();
            this.attach (response_scroll_view, 1, row, 1, 1);

            response_label.show ();
            response_text_view.show ();

            this.expand = true;

            this.show ();
            
        }

        public void reset_state () {
            var children = get_children ();
            foreach (var child in children) {
                child.destroy ();
            }
        }
    }
}
