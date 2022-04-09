using Soup;
using Gtk;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/intercept.ui")]
    class Intercept : Gtk.Paned, MainApplicationPane {

        [GtkChild]
        private unowned Gtk.Button button_drop;
        [GtkChild]
        private unowned Gtk.Button button_intercept_response;
        [GtkChild]
        private unowned Gtk.Button button_forward;
        [GtkChild]
        private unowned Gtk.ToggleButton checkbox_intercept_to_server;
        [GtkChild]
        private unowned Gtk.ToggleButton checkbox_intercept_to_browser;
        [GtkChild]
        private unowned Gtk.TreeView list_requests;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex_request;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_text_request;

        private ApplicationWindow application_window;
        private HexEditor hex_editor;
        private Gtk.ListStore liststore_requests;
        private bool updating;
        private RequestTextEditor text_view_request;
        private WebsocketConnection websocket;

        enum Column {
            REQUEST_GUID,
            DATA_PACKET_GUID,
            PROTOCOL,
            DIRECTION,
            URL,
            BODY
        }
        
        public Intercept (ApplicationWindow application_window) {
            this.application_window = application_window;
            liststore_requests = new Gtk.ListStore (6, typeof(string), typeof(string), typeof (string), typeof (string), typeof (string), typeof (string));
            list_requests.set_model (liststore_requests);

            var url_renderer = new Gtk.CellRendererText();
            url_renderer.ellipsize = Pango.EllipsizeMode.MIDDLE;
            url_renderer.ellipsize_set = true;

            list_requests.insert_column_with_attributes (-1, "GUID", new CellRendererText (), "text", Column.REQUEST_GUID);
            list_requests.insert_column_with_attributes (-1, "Data Packet GUID", new CellRendererText (), "text", Column.DATA_PACKET_GUID);
            list_requests.insert_column_with_attributes (-1, "Protocol", new CellRendererText (), "text", Column.PROTOCOL);
            list_requests.insert_column_with_attributes (-1, "Direction", new CellRendererText (), "text", Column.DIRECTION);
            list_requests.insert_column_with_attributes (-1, "URL", url_renderer, "text", Column.URL);
            list_requests.insert_column_with_attributes (-1, "Body", new CellRendererText (), "text", Column.BODY);

            var url_column = list_requests.get_column(Column.URL);
            url_column.expand = true;
            url_column.min_width = 200;

            var guidColumn = list_requests.get_column(Column.REQUEST_GUID);
            guidColumn.visible = false;

            var idColumn = list_requests.get_column(Column.DATA_PACKET_GUID);
            idColumn.visible = false;

            var bodyColumn = list_requests.get_column(Column.BODY);
            bodyColumn.visible = false;

            text_view_request = new RequestTextEditor (application_window);
            text_view_request.show ();
            scrolled_window_text_request.add (text_view_request);

            hex_editor = new HexEditor ();
            hex_editor.show ();
            scrolled_window_hex_request.add (hex_editor);

            get_intercept_settings ();
            get_requests ();

            var selection = list_requests.get_selection();
            selection.changed.connect(this.on_selection_changed);
            selection.mode = Gtk.SelectionMode.MULTIPLE;
        }

        private void add_request_to_table (Json.Object request_data) {
            var action = request_data.get_string_member ("RecordAction");
            var request = request_data.get_object_member ("Request");
            var list_selection = list_requests.get_selection ();

            if (action == "delete") {
                var request_guid_to_remove = request.get_string_member ("GUID");
                var data_guid_to_remove = request_data.get_string_member ("GUID");
                var select_next = false;
                
                liststore_requests.@foreach ((model, path, iter) => {
                    Value request_guid;
                    Value data_packet_guid;
                    model.get_value (iter, Column.REQUEST_GUID, out request_guid);
                    model.get_value (iter, Column.DATA_PACKET_GUID, out data_packet_guid);

                    bool remove_data_guid = (data_packet_guid.get_string () != "" && data_packet_guid.get_string () == data_guid_to_remove);
                    bool remove_request_guid = (data_packet_guid.get_string () == "" && request_guid.get_string () == request_guid_to_remove);

                    if (remove_data_guid || remove_request_guid) {
                        if (list_selection.iter_is_selected (iter)) {
                            select_next = true;
                        }
                        liststore_requests.remove (ref iter);
                        return true;
                    }

                    return false;
                });

                if (select_next) {
                    liststore_requests.@foreach ((model, path, iter) => {
                        list_selection.select_iter (iter);
                        return true;
                    });
                }
            } else {
                // add to the table
                var request_guid = request.get_string_member ("GUID");
                var data_packet_guid = request_data.get_string_member ("GUID");
                var protocol = request.get_string_member ("Protocol");
                var direction = request_data.get_string_member ("Direction");
                var url = request.get_string_member ("URL");
                var body = request_data.get_string_member ("Body");

                if (direction == "browser_to_server") {
                    direction = "Browser to server";
                } else {
                    direction = "Server to browser";
                }

                Gtk.TreeIter iter;
                liststore_requests.insert_with_values (out iter, -1,
                    Column.REQUEST_GUID, request_guid,
                    Column.DATA_PACKET_GUID, data_packet_guid,
                    Column.PROTOCOL, protocol,
                    Column.DIRECTION, direction,
                    Column.URL, url,
                    Column.BODY, body
                );

                if (list_selection.get_selected_rows (null).length () == 0) {
                    list_selection.select_iter (iter);
                }
            }
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
            scrolled_window_text_request.show ();
        }

        private void get_intercept_settings () {
            var url = "http://" + application_window.core_address + "/proxy/intercept_settings";

            var message = new Soup.Message ("GET", url);

            application_window.http_session.queue_message (message, (sess, mess) => {
                if (mess.status_code != 200) {
                    return;
                }
                this.updating = true;
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

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
            var url = "http://" + application_window.core_address + "/proxy/intercepted_requests";

            var session = application_window.http_session;
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
                if (mess.status_code != 200) {
                    return;
                }
                liststore_requests.clear ();
                this.updating = true;
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

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
            session.websocket_connect_async.begin (wsmessage, "localhost", null, null, (obj, res) => {
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
            return body_str.make_valid () != body_str;
        }

        public void on_back_clicked () {
            application_window.change_pane ("RequestList");
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

        private void on_selection_changed () {
            var selection = list_requests.get_selection ();            
            var selection_count = selection.get_selected_rows (null).length ();

            selection.selected_foreach ((model, path, iter) => {
                if (selection_count == 1) {
                    string body;
                    string direction;
                    string protocol;
                    model.get (iter, Column.BODY, out body);
                    model.get (iter, Column.DIRECTION, out direction);
                    model.get (iter, Column.PROTOCOL, out protocol);

                    var body_bytes = Base64.decode (body);

                    if (is_binary (body_bytes)) {
                        scrolled_window_hex_request.show ();
                        scrolled_window_text_request.hide ();
                        text_view_request.buffer.text = "";
                        var buffer = new HexStaticBuffer.from_bytes (body_bytes);
                        buffer.set_read_only (false);
                        hex_editor.buffer = buffer;
                    } else {
                        scrolled_window_hex_request.hide ();
                        scrolled_window_text_request.show ();
                        text_view_request.buffer.text = (string) body_bytes;
                    }

                    var is_request = (direction == "Browser to server");
                    button_forward.sensitive = true;
                    button_drop.sensitive = is_request;
                    button_intercept_response.sensitive = is_request && (protocol != "Websocket");
                } else {
                    text_view_request.buffer.text = "(Multiple requests/responses selected)";
                    button_forward.sensitive = true;
                    button_drop.sensitive = false;
                    button_intercept_response.sensitive = false;
                }
            });
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

            message.set_request("application/json", Soup.MemoryUse.COPY, parameters.data);
            
            application_window.http_session.queue_message (message, null);
        }

        private void send_request_response (string action) {
            var list_selection = list_requests.get_selection ();

            var selection_count = list_selection.get_selected_rows (null).length ();

            list_selection.selected_foreach ((model, path, iter) => {
                string request_guid;
                string data_packet_guid;
                string body;
                string direction;
                model.get (iter, Column.REQUEST_GUID, out request_guid);
                model.get (iter, Column.DATA_PACKET_GUID, out data_packet_guid);
                model.get (iter, Column.DIRECTION, out direction);
                model.get (iter, Column.BODY, out body);

                if (selection_count == 1) {
                    if (scrolled_window_hex_request.visible) {
                        var bytes = ((HexStaticBuffer)hex_editor.buffer).get_buffer ();
                        body = Base64.encode (bytes);
                    }
                    else {
                        body = Base64.encode (text_view_request.buffer.text.data);
                    }
                }

                if (direction == "Browser to server") {
                    direction = "browser_to_server";
                } else {
                    direction = "server_to_browser";
                }

                send_individual_request_response (request_guid, data_packet_guid, action, direction, body);
            });

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

            message.set_request("application/json", Soup.MemoryUse.COPY, parameters.data);
            
            application_window.http_session.queue_message (message, null);
        }

        public void reset_state () {
            liststore_requests.clear ();
            clear_gui ();
            get_intercept_settings ();
            get_requests ();
        }
    }
}
