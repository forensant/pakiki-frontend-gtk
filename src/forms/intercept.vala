using Soup;
using Gtk;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/intercept.ui")]
    class Intercept : Gtk.Box, MainApplicationPane {

        [GtkChild]
        private unowned Gtk.Box box_original_request;
        [GtkChild]
        private unowned Gtk.Button button_drop;
        [GtkChild]
        private unowned Gtk.Button button_intercept_response;
        [GtkChild]
        private unowned Gtk.Button button_forward;
        [GtkChild]
        private unowned Gtk.Label label_edit_request;
        [GtkChild]
        private unowned Gtk.CheckButton checkbox_intercept_to_server;
        [GtkChild]
        private unowned Gtk.CheckButton checkbox_intercept_to_browser;
        [GtkChild]
        private unowned Gtk.ColumnView list_requests;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex_request;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_text_request;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex_requestresponse;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_text_requestresponse;

        private ApplicationWindow application_window;
        private HexEditor hex_editor_requestresponse;
        private HexEditor hex_editor_request;
        private GLib.ListStore liststore_requests;
        private Gtk.SelectionModel liststore_selection_model;
        private bool updating;
        private RequestTextEditor text_view_requestresponse;
        private RequestTextEditor text_view_request;
        private WebsocketConnection websocket;

        public Intercept (ApplicationWindow application_window) {
            this.application_window = application_window;
            liststore_requests = new GLib.ListStore (typeof (InterceptedRequest));
            liststore_selection_model = new Gtk.MultiSelection (liststore_requests);
            list_requests.set_model (liststore_selection_model);

            var protocol_column_factory = new Gtk.SignalListItemFactory ();
            protocol_column_factory.setup.connect (on_setup_label_column);
            protocol_column_factory.bind.connect (on_bind_column_protocol);

            var direction_column_factory = new Gtk.SignalListItemFactory ();
            direction_column_factory.setup.connect (on_setup_label_column);
            direction_column_factory.bind.connect (on_bind_column_direction);

            var url_column_factory = new Gtk.SignalListItemFactory ();
            url_column_factory.setup.connect (on_setup_label_column);
            url_column_factory.bind.connect (on_bind_column_url);

            var protocol_column = new Gtk.ColumnViewColumn ("Protocol", protocol_column_factory);
            var direction_column = new Gtk.ColumnViewColumn ("Direction", direction_column_factory);
            var url_column = new Gtk.ColumnViewColumn ("URL", url_column_factory);
            url_column.expand = true;

            list_requests.append_column (protocol_column);
            list_requests.append_column (direction_column);
            list_requests.append_column (url_column);

            text_view_request = new RequestTextEditor (application_window);
            text_view_request.editable = false;
            text_view_request.show ();
            scrolled_window_text_request.set_child (text_view_request);

            text_view_requestresponse = new RequestTextEditor (application_window);
            text_view_requestresponse.editable = false;
            text_view_requestresponse.show ();
            scrolled_window_text_requestresponse.set_child (text_view_requestresponse);

            hex_editor_request = new HexEditor (application_window);
            hex_editor_request.show ();
            scrolled_window_hex_request.set_child (hex_editor_request);

            hex_editor_requestresponse = new HexEditor (application_window);
            hex_editor_requestresponse.show ();
            scrolled_window_hex_requestresponse.set_child (hex_editor_requestresponse);

            get_intercept_settings ();
            get_requests ();

            liststore_selection_model.selection_changed.connect (on_selection_changed);
        }

        private static bool guids_equal (GLib.Object a, GLib.Object b) {
            var req_a = a as InterceptedRequest;
            var req_b = b as InterceptedRequest;

            if (req_a == null || req_b == null) {
                return false;
            }

            bool remove_data_guid = (req_a.data_guid != "" && req_a.data_guid == req_b.data_guid);
            bool remove_request_guid = (req_a.data_guid == "" && req_a.request_guid == req_b.request_guid);
            
            return remove_data_guid || remove_request_guid;
        }

        private void add_request_to_table (Json.Object request_data) {
            var intercepted_request = new InterceptedRequest (request_data);

            var selected_rows = liststore_selection_model.get_selection ();

            if (intercepted_request.action == "delete") {
                uint position = 0;
                var found = liststore_requests.find_with_equal_func (intercepted_request, guids_equal, out position);

                if (!found) {
                    return;
                }

                var selected = selected_rows.contains (position);
                var select_next = (selected_rows.get_size () == 1 && selected_rows.get_nth (0) == position);

                if (selected) {
                    liststore_selection_model.unselect_item (position);
                }

                liststore_requests.remove (position);
                
                if (select_next && liststore_requests.get_n_items () > 0) {
                    liststore_selection_model.select_item (liststore_requests.get_n_items () - 1, true);
                }

            } else {
                // otherwise add it
                liststore_requests.append (intercepted_request);
                if (selected_rows.get_size () == 0) {
                    liststore_selection_model.select_item (liststore_requests.get_n_items () - 1, true);
                }
            }

            application_window.set_intercepted_request_count ((int)liststore_requests.get_n_items ());
        }

        public bool back_visible () {
            return true;
        }

        public bool can_search () {
            return false;
        }

        private void clear_gui () {
            text_view_request.buffer.text = "";
            button_drop.sensitive = false;
            button_forward.sensitive = false;
            button_intercept_response.sensitive = false;
            scrolled_window_hex_request.hide ();
            scrolled_window_text_request.hide ();
            scrolled_window_hex_requestresponse.hide ();
            scrolled_window_text_requestresponse.show ();
            box_original_request.hide ();
        }

        private void get_intercept_settings () {
            if (application_window.core_address == "") {
                return;
            }
            var url = "http://" + application_window.core_address + "/proxy/intercept_settings";
            
            var message = new Soup.Message ("GET", url);

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_and_read_async.end (res);
                    if (message.status_code != 200) {
                        return;
                    }
                    this.updating = true;
                    var parser = new Json.Parser ();
                    parser.load_from_data ((string) response.get_data ());

                    var settings = parser.get_root ().get_object ();
                    checkbox_intercept_to_browser.active = settings.get_boolean_member ("ServerToBrowser");
                    checkbox_intercept_to_server.active = settings.get_boolean_member ("BrowserToServer");
                } catch (Error err) {
                    stdout.printf ("Could not populate request list: %s\n", err.message);
                }

                this.updating = false;
            });
        }

        private void get_requests () {
            if (application_window.core_address == "") {
                return;
            }

            var url = "http://" + application_window.core_address + "/proxy/intercepted_requests";

            var session = application_window.http_session;
            var message = new Soup.Message ("GET", url);

            session.send_and_read_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    var response = session.send_and_read_async.end (res);
                    if (message.status_code != 200) {
                        return;
                    }
                    liststore_requests.remove_all ();
                    this.updating = true;
                    var parser = new Json.Parser ();
                    parser.load_from_data ((string) response.get_data (), -1);

                    var rootArray = parser.get_root ().get_array ();

                    foreach (var reqElement in rootArray.get_elements ()) {
                        var request = reqElement.get_object ();
                        add_request_to_table (request);
                    }
                } catch (Error err) {
                    stdout.printf ("Could not populate request list: %s\n", err.message);
                }

                this.updating = false;
            });

            if (websocket != null && websocket.state == Soup.WebsocketState.OPEN) {
                websocket.close (Soup.WebsocketCloseCode.NO_STATUS, null);
            }

            url = CoreProcess.websocket_url (application_window, "Intercepted Request");

            var wsmessage = new Soup.Message ("GET", url);
            session.websocket_connect_async.begin (wsmessage, "localhost", null, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    websocket = session.websocket_connect_async.end (res);
                    websocket.max_incoming_payload_size = 0;
                    websocket.message.connect (on_websocket_message);
                } catch (Error err) {
                    stdout.printf ("Error ending websocket: %s\n", err.message);
                }
            });
        }

        private bool is_binary (uchar[] body) {
            var body_str = (string)body;
            return !body_str.validate (body.length - 1, null) || body.length > (1024*1024);
        }

        public void on_back_clicked () {
            application_window.change_pane ("RequestList");
        }

        private void on_bind_column_direction (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (InterceptedRequest) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.direction;
        }

        private void on_bind_column_protocol (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (InterceptedRequest) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.protocol;
        }

        private void on_bind_column_url (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (InterceptedRequest) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.url;
        }

        [GtkCallback]
        public void on_button_drop_activate () {
            send_request_response ("drop");
        }

        [GtkCallback]
        public void on_button_forward_activate () {
            send_request_response ("forward");
        }

        [GtkCallback]
        public void on_button_intercept_response_activate () {
            send_request_response ("forward_and_intercept_response");
        }

        [GtkCallback]
        public void on_checkbox_intercept_to_browser_toggled () {
            if (!updating) {
                set_intercept ();
                clear_gui ();
            }
        }

        [GtkCallback]
        public void on_checkbox_intercept_to_server_toggled () {
            if (!updating) {
                set_intercept ();
                clear_gui ();
            }
        }

        private void on_new_clicked () {
            application_window.change_pane ("NewRequest");
        }

        private void on_selection_changed (uint position, uint n_items) {
            var selected_rows = liststore_selection_model.get_selection ();
            var selected_row_count = selected_rows.get_size ();

            if (selected_row_count == 0) {
                scrolled_window_hex_requestresponse.hide ();
                scrolled_window_text_requestresponse.show ();
                scrolled_window_hex_request.hide ();
                scrolled_window_text_request.hide ();
                text_view_requestresponse.buffer.text = "";
                text_view_requestresponse.editable = false;
                text_view_requestresponse.set_request_details ("", "", "");
                box_original_request.hide ();
                label_edit_request.label = "";
                return;
            }

            if (selected_row_count > 1) {
                box_original_request.visible = false;
                scrolled_window_hex_request.hide ();
                scrolled_window_text_request.hide ();
                scrolled_window_hex_requestresponse.hide ();
                scrolled_window_text_requestresponse.show ();
                text_view_request.set_request_details ("", "", "");
                text_view_requestresponse.buffer.text = "(Multiple requests/responses selected)";
                text_view_requestresponse.editable = false;
                text_view_requestresponse.set_request_details ("", "", "");
                button_forward.sensitive = true;
                button_drop.sensitive = false;
                button_intercept_response.sensitive = false;
                label_edit_request.label = "";
                return;
            }

            var selection = selected_rows.get_nth (0);
            var intercepted_request = (InterceptedRequest?)liststore_requests.get_item (selection);
            if (intercepted_request == null) {
                return;
            }
            var body_bytes = Base64.decode (intercepted_request.body);
            var original_request_body_bytes = Base64.decode (intercepted_request.original_request_body);

            if (is_binary (body_bytes)) {
                scrolled_window_hex_requestresponse.show ();
                scrolled_window_text_requestresponse.hide ();
                text_view_requestresponse.buffer.text = "";
                var buffer = new HexStaticBuffer.from_bytes (body_bytes);
                buffer.set_read_only (false);
                hex_editor_requestresponse.buffer = buffer;
            } else {
                scrolled_window_hex_requestresponse.hide ();
                scrolled_window_text_requestresponse.show ();
                if (body_bytes.length == 0) {
                    text_view_requestresponse.buffer.text = "";
                } else {
                    text_view_requestresponse.buffer.text = ((string) body_bytes).replace("\r\n", "\n");
                }
                text_view_requestresponse.direction = intercepted_request.direction.down ();
                text_view_requestresponse.editable = true;
                text_view_requestresponse.on_text_changed (true);
                text_view_requestresponse.set_request_details (
                    intercepted_request.request_guid, 
                    intercepted_request.protocol,
                    intercepted_request.url);
                    
                var is_request = (intercepted_request.direction == "Request");
                button_forward.sensitive = true;
                button_drop.sensitive = is_request;
                button_intercept_response.sensitive = is_request && (intercepted_request.protocol != "Websocket");

                box_original_request.visible = !is_request && (intercepted_request.original_request_body != "");
                label_edit_request.label = box_original_request.visible ? "Request and Response" : "Request";

                if (!is_request && (intercepted_request.original_request_body != "")) {
                    if (is_binary (original_request_body_bytes)) {
                        scrolled_window_hex_request.show ();
                        scrolled_window_text_request.hide ();
                        text_view_request.buffer.text = "";
                        var buffer = new HexStaticBuffer.from_bytes (original_request_body_bytes);
                        buffer.set_read_only (true);
                        hex_editor_request.buffer = buffer;
                    } else {
                        scrolled_window_hex_request.hide ();
                        scrolled_window_text_request.show ();
                        if (body_bytes.length == 0) {
                            text_view_request.buffer.text = "";
                        } else {
                            text_view_request.buffer.text = ((string) original_request_body_bytes).replace("\r\n", "\n");
                        }
                        text_view_request.direction = intercepted_request.direction.down ();
                        text_view_request.set_request_details (intercepted_request.request_guid, intercepted_request.protocol, intercepted_request.url);
                    }
                }
            }
        }

        private void on_setup_label_column (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var label = new Gtk.Label ("");
            label.halign = Gtk.Align.START;
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            ((Gtk.ListItem) list_item_obj).child = label;
        }

        private void on_websocket_message (int type, Bytes message) {
            var parser = new Json.Parser ();
            var jsonData = (string)message.get_data();

            if (jsonData == "") {
                return;
            }

            try {
                parser.load_from_data (jsonData, -1);
            }
            catch(Error e) {
                stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                return;
            }

            var request = parser.get_root ().get_object ();
            add_request_to_table (request);
        }

        private void send_individual_request_response (string request_guid, string data_packet_guid, string action, string direction, string body) {
            var message = new Soup.Message ("PUT", "http://" + application_window.core_address + "/proxy/set_intercepted_response");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("RequestGUID");
            builder.add_string_value (request_guid);
            builder.set_member_name ("DataPacketGUID");
            builder.add_string_value (data_packet_guid);
            builder.set_member_name ("Body");
            builder.add_string_value (body);
            builder.set_member_name ("Direction");
            builder.add_string_value (direction);
            builder.set_member_name ("RequestAction");
            builder.add_string_value (action);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request_body_from_bytes ("application/json", new Bytes(parameters.data));
            
            application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }

        private void send_request_response (string action) {
            var selection_count = liststore_selection_model.get_n_items ();

            var iter = BitsetIter ();
            uint position = 0;
            var found = iter.init_first (liststore_selection_model.get_selection (), out position);

            while (found) {
                var intercepted_request = (InterceptedRequest)liststore_requests.get_item (position);
                string body = "";
                string direction = "";

                if (selection_count == 1) {
                    if (scrolled_window_hex_requestresponse.visible) {
                        var bytes = ((HexStaticBuffer)hex_editor_requestresponse.buffer).get_buffer ();
                        body = Base64.encode (bytes);
                    }
                    else {
                        body = Base64.encode (text_view_requestresponse.buffer.text.data);
                    }
                }

                if (intercepted_request.direction == "Request") {
                    direction = "browser_to_server";
                } else {
                    direction = "server_to_browser";
                }

                send_individual_request_response (intercepted_request.request_guid, intercepted_request.data_guid, action, direction, body);

                found = iter.next (out position);
            }
            
            clear_gui ();
        }

        private void set_intercept () {
            var message = new Soup.Message ("PUT", "http://" + application_window.core_address + "/proxy/intercept_settings");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("BrowserToServer");
            builder.add_boolean_value (checkbox_intercept_to_server.active);
            builder.set_member_name ("ServerToBrowser");
            builder.add_boolean_value (checkbox_intercept_to_browser.active);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request_body_from_bytes ("application/json", new Bytes(parameters.data));
            application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }

        public void reset_state () {
            liststore_requests.remove_all ();
            clear_gui ();
            get_intercept_settings ();
            get_requests ();
        }
    }
}
