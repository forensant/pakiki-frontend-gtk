using Soup;
using WebKit;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-details.ui")]
    class RequestDetails : Gtk.Notebook {

        [GtkChild]
        private unowned Gtk.MenuButton button_send_to;
        [GtkChild]
        private unowned Gtk.ListStore liststore_websocket_packets;
        [GtkChild]
        private unowned Gtk.Paned pane_websocket;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_original_text;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_text;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_out_of_band_interaction;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_websocket_request;
        [GtkChild]
        private unowned Gtk.TreeView treeview_websocket_packets;
        [GtkChild]
        private unowned Gtk.Viewport viewport_out_of_band_interaction;

        private ApplicationWindow application_window;
        public string guid;
        private Gee.HashMap<string, string> modified_websocket_data;
        private OutOfBandDisplay out_of_band_display;
        private RequestPreview request_preview;
        private SearchableWebView searchable_web_view;
        private string url;

        private RequestTextView text_view_orig_request;
        private RequestTextView text_view_request;
        private RequestTextView text_view_websocket_request;

        enum WebsocketColumn {
            GUID,
            TIME,
            DIRECTION,
            OPCODE,
            MODIFIED,
            DATA
        }
        
        private bool _show_send_to;
        public bool show_send_to {
            get { return _show_send_to; }
            set {
                _show_send_to = value; 
                button_send_to.visible = value;
            }
        }

        private bool ended;

        public RequestDetails (ApplicationWindow application_window) {
            this.application_window = application_window;
            modified_websocket_data = new Gee.HashMap<string, string> ();
            ended = false;
            guid = "";
            show_send_to = true;

            text_view_request = new RequestTextView (application_window);
            text_view_orig_request = new RequestTextView (application_window);
            text_view_websocket_request = new RequestTextView (application_window);

            text_view_request.editable = false;
            text_view_orig_request.editable = false;
            text_view_websocket_request.editable = false;

            scroll_window_text.add (text_view_request);
            scroll_window_original_text.add (text_view_orig_request);
            scroll_window_websocket_request.add (text_view_websocket_request);

            text_view_request.show ();
            text_view_orig_request.show ();
            text_view_websocket_request.show ();

            set_send_to_popup ();
            scroll_window_original_text.hide ();

            request_preview = new RequestPreview (application_window);
            searchable_web_view = new SearchableWebView (application_window, request_preview);
            this.append_page (searchable_web_view, new Gtk.Label.with_mnemonic ("_Preview"));
            searchable_web_view.hide ();

            out_of_band_display = new OutOfBandDisplay (application_window);
            scroll_window_out_of_band_interaction.add (out_of_band_display);

            var time_cell_renderer = new Gtk.CellRendererText();

            treeview_websocket_packets.insert_column_with_attributes (-1, "GUID",
                                                    new Gtk.CellRendererText(),
                                                    "text", WebsocketColumn.GUID);

            treeview_websocket_packets.insert_column_with_attributes (-1, "Time",
                                                    time_cell_renderer,
                                                    "text", WebsocketColumn.TIME);

            treeview_websocket_packets.insert_column_with_attributes (-1, "Direction",
                                                    new Gtk.CellRendererText(),
                                                    "text", WebsocketColumn.DIRECTION);

            treeview_websocket_packets.insert_column_with_attributes (-1, "Opcode",
                                                    new Gtk.CellRendererText(),
                                                    "text", WebsocketColumn.OPCODE);

            treeview_websocket_packets.insert_column_with_attributes (-1, "Modified",
                                                    new Gtk.CellRendererText(),
                                                    "text", WebsocketColumn.MODIFIED);

            treeview_websocket_packets.insert_column_with_attributes (-1, "Data",
                                                    new Gtk.CellRendererText(),
                                                    "text", WebsocketColumn.DATA);

            treeview_websocket_packets.get_column(WebsocketColumn.GUID).visible = false;
            treeview_websocket_packets.get_column(WebsocketColumn.DATA).visible = false;

            var time_column = treeview_websocket_packets.get_column(WebsocketColumn.TIME);
            time_column.set_cell_data_func(time_cell_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, WebsocketColumn.TIME, out val);
                ((Gtk.CellRendererText)cell).text = RequestList.response_time(new DateTime.from_unix_local(val.get_int()));
                val.unset();
            });

            var selection = treeview_websocket_packets.get_selection ();
            selection.changed.connect(this.on_websocket_packet_selected);
        }

        ~RequestDetails () {
            ended = true;
        }

        public bool find_activated () {
            if (get_nth_page (page) == scroll_window_original_text) {
                return text_view_orig_request.find_activated ();
            }
            else if (get_nth_page (page) == scroll_window_text) {
                return text_view_request.find_activated ();
            } else if (get_nth_page (page) == searchable_web_view) {
                return searchable_web_view.find_activated ();
            }
            
            return false;
        }

        private void on_websocket_packet_selected () {
            var selection = treeview_websocket_packets.get_selection ();
            Gtk.TreeModel model;
            Gtk.TreeIter iter;

            string guid;
            string data;
    
            if (selection.get_selected (out model, out iter)) {
                model.get (iter, WebsocketColumn.GUID, out guid);
                model.get (iter, WebsocketColumn.DATA, out data);

                uchar[] decoded_data = new uchar[0];

                if (modified_websocket_data.has_key (guid)) {
                    decoded_data = (uchar[])"Original:\n".data;
                }

                var orig_data = Base64.decode (data.to_string ());
                for (int i = 0; i < orig_data.length; i++) {
                    decoded_data += orig_data[i];
                }

                if (modified_websocket_data.has_key (guid)) {
                    var title = (uchar[])"\n\nModified:\n".data;
                    for (int i = 0; i < title.length; i++) {
                        decoded_data += title[i];
                    }

                    var modified_data = Base64.decode (modified_websocket_data[guid]);
                    for (int i = 0; i < modified_data.length; i++) {
                        decoded_data += modified_data[i];
                    }
                }

                decoded_data += '\0';

                uchar[] response_data = {'\0'};
                text_view_websocket_request.set_request_response (decoded_data, response_data);
            }
        }

        private void populate_http_data (Json.Object root_obj) {
            var original_request = Base64.decode (root_obj.get_string_member ("Request"));
            var original_response = Base64.decode (root_obj.get_string_member ("Response"));

            original_request += '\0';
            original_response += '\0';

            var modified_request = Base64.decode (root_obj.get_string_member ("ModifiedRequest"));
            var modified_response = Base64.decode (root_obj.get_string_member ("ModifiedResponse"));

            url = root_obj.get_string_member ("URL");
            var mimetype = root_obj.get_string_member ("MimeType");

            var large_response = root_obj.get_boolean_member ("LargeResponse");
            var modified = root_obj.get_boolean_member ("Modified");
            var combined_content_length = root_obj.get_int_member ("CombinedContentLength");
            
            if (modified) {
                scroll_window_original_text.show ();

                if (modified_request.length == 0) {
                    modified_request = original_request;
                } else {
                    modified_request += '\0';
                }

                if (modified_response.length == 0) {
                    modified_response = original_response;
                } else {
                    modified_response += '\0';
                }

                if (large_response) {
                    text_view_request.set_large_request (guid, combined_content_length);
                    text_view_orig_request.set_request_response ("Request or response too large to display".data, "".data);
                    searchable_web_view.hide ();
                }
                else {
                    text_view_request.set_request_response (modified_request, modified_response);
                    text_view_orig_request.set_request_response (original_request, original_response);
                    var data_load_success = request_preview.set_content (modified_response, mimetype, url);
                    searchable_web_view.visible = data_load_success;
                }
                
            } else {
                scroll_window_original_text.hide ();

                if (large_response) {
                    text_view_request.set_large_request (guid, combined_content_length);
                    searchable_web_view.hide ();
                }
                else {
                    text_view_request.set_request_response (original_request, original_response);
                    var data_load_success = request_preview.set_content (original_response, mimetype, url);
                    searchable_web_view.visible = data_load_success;
                }
            }
        }

        private void populate_websocket_data (Json.Object root_obj, bool request_updated) {
            if (!request_updated) {
                liststore_websocket_packets.clear ();
                text_view_websocket_request.reset_state ();
            }

            var packets = root_obj.get_array_member ("DataPackets");

            for (int i = 0; i < packets.get_length (); i++) {
                var packet_obj = packets.get_object_element (i);
                var packet_guid = packet_obj.get_string_member ("GUID");
                var packet_time = packet_obj.get_int_member ("Time");
                var packet_direction = packet_obj.get_string_member ("Direction");
                var packet_display_data = packet_obj.get_string_member ("DisplayData");
                var packet_modified = packet_obj.get_boolean_member ("Modified");
                var packet_data = packet_obj.get_string_member ("Data");

                if (packet_direction == "Request") {
                    packet_direction = "Client > Server";
                } else {
                    packet_direction = "Server > Client";
                }

                var packet_opcode = "";
                var parser = new Json.Parser ();
                try {
                    if (!parser.load_from_data (packet_display_data, -1)) {
                        return;
                    }

                    var root = parser.get_root ();
                    if (root != null && root.get_object () != null && root.get_object ().has_member ("opcode")) {
                       packet_opcode = root.get_object ().get_string_member ("opcode");
                    }
                } catch {
                }

                var found = false;
                liststore_websocket_packets.@foreach ((model, path, iter) => {
                    Value guid;
                    model.get_value (iter, WebsocketColumn.GUID, out guid);

                    if (guid.get_string () == packet_guid) {
                        found = true;

                        if (packet_modified) {
                            liststore_websocket_packets.set_value (
                                iter,
                                WebsocketColumn.MODIFIED,
                                "Yes"
                            );

                            modified_websocket_data[packet_guid] = packet_data;
                        }
                        
                        return true;
                    }

                    return false;
                });

                if (found) {
                    continue;
                }

                Gtk.TreeIter iter;
                liststore_websocket_packets.insert_with_values (out iter, -1,
                                                WebsocketColumn.GUID, packet_guid,
                                                WebsocketColumn.TIME, packet_time,
                                                WebsocketColumn.DIRECTION, packet_direction,
                                                WebsocketColumn.OPCODE, packet_opcode,
                                                WebsocketColumn.MODIFIED, packet_modified ? "Yes" : "",
                                                WebsocketColumn.DATA, packet_data);
            }
        }

        public void set_request (string guid, bool request_updated = false) {
            this.guid = guid;
            if (_show_send_to) {
                button_send_to.set_visible (true);
            }

            if (guid == "" || guid == "-") {
                return;
            }

            var message = new Soup.Message ("GET", "http://" + application_window.core_address + "/requests/" + guid + "/contents");

            application_window.http_session.queue_message (message, (sess, mess) => {
                if (ended || mess.status_code != 200) {
                    return;
                }

                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    if (!parser.load_from_data (jsonData, -1)) {
                        return;
                    }

                    var root_obj = parser.get_root().get_object();

                    var protocol = root_obj.get_string_member ("Protocol");

                    set_controls_visible (protocol == "HTTP/1.1", protocol == "Websocket", protocol == "Out of Band");

                    if (protocol == "Websocket") {
                        populate_websocket_data (root_obj, request_updated);
                    }
                    else if (protocol == "Out of Band") {
                        var packets = root_obj.get_array_member ("DataPackets");
                        out_of_band_display.render_interaction (packets);
                    } else {
                        populate_http_data (root_obj);
                    }
                }
                catch(Error e) {
                    stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                }
                
            });
        }

        private void set_controls_visible (bool http, bool websocket, bool out_of_band) {
            var text_visibility_changed = (!scroll_window_text.visible && http);

            scroll_window_text.visible = http;
            scroll_window_original_text.visible = http;
            searchable_web_view.visible = http;
            pane_websocket.visible = websocket;
            viewport_out_of_band_interaction.visible = out_of_band;

            // reset the displayed page to stop jumping around
            if(text_visibility_changed) {
                this.page = 0;
            }

            if (!http) {
                button_send_to.set_visible (false);
            } else if (_show_send_to) {
                button_send_to.set_visible (true);
            }
        }

        private void set_send_to_popup () {
            var menu = new Gtk.Menu ();
                        
            var item_new_request = new Gtk.MenuItem.with_label ("New Request");
            item_new_request.activate.connect ( () => {
                if (guid != "") {
                    application_window.send_to_new_request (guid);
                }
            });
            item_new_request.show ();
            menu.append (item_new_request);

            var item_inject = new Gtk.MenuItem.with_label ("Inject");
            item_inject.activate.connect ( () => {
                if (guid != "") {
                    application_window.send_to_inject (guid);
                }
            });
            item_inject.show ();
            menu.append (item_inject);

            var open_browser_inject = new Gtk.MenuItem.with_label ("Open in Browser");
            open_browser_inject.activate.connect ( () => {
                if (guid != "" && url != "") {
                    try {
                        AppInfo.launch_default_for_uri (url, null);
                    } catch (Error err) {
                        stdout.printf ("Could not launch browser: %s\n", err.message);
                    }
                }
            });
            open_browser_inject.show ();
            menu.append (open_browser_inject);

            button_send_to.set_popup (menu);
        }

        public void update_content_length (int64 combined_content_length) {
            text_view_request.set_large_request (guid, combined_content_length);
        }

        public void reset_state () {
            modified_websocket_data.clear ();
            text_view_request.reset_state ();
            text_view_orig_request.reset_state ();
            text_view_websocket_request.reset_state ();
            searchable_web_view.load_uri ("about:blank");
            liststore_websocket_packets.clear ();
            scroll_window_original_text.hide ();
            searchable_web_view.hide ();
            pane_websocket.hide ();
            viewport_out_of_band_interaction.hide ();
            this.page = 0;
        }
    }
}
