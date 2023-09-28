using Soup;
using Gtk;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/intercept.ui")]
    class Intercept : Gtk.Paned, MainApplicationPane {

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
        private unowned Gtk.ToggleButton checkbox_intercept_to_server;
        [GtkChild]
        private unowned Gtk.ToggleButton checkbox_intercept_to_browser;
        [GtkChild]
        private unowned Gtk.TreeView list_requests;
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
        private Gtk.ListStore liststore_requests;
        private bool updating;
        private RequestTextEditor text_view_requestresponse;
        private RequestTextEditor text_view_request;
        private WebsocketConnection websocket;

        enum Column {
            REQUEST_GUID,
            DATA_PACKET_GUID,
            PROTOCOL,
            DIRECTION,
            URL,
            BODY,
            ORIGINAL_REQUEST_BODY
        }
        
        public Intercept (ApplicationWindow application_window) {
            this.application_window = application_window;
            liststore_requests = new Gtk.ListStore (7, typeof(string), typeof(string), typeof (string), typeof (string), typeof (string), typeof (string), typeof (string));
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
            list_requests.insert_column_with_attributes (-1, "Original Request Body", new CellRendererText (), "text", Column.ORIGINAL_REQUEST_BODY);

            var url_column = list_requests.get_column(Column.URL);
            url_column.expand = true;
            url_column.min_width = 200;

            var guid_column = list_requests.get_column(Column.REQUEST_GUID);
            guid_column.visible = false;

            var id_column = list_requests.get_column(Column.DATA_PACKET_GUID);
            id_column.visible = false;

            var body_column = list_requests.get_column(Column.BODY);
            body_column.visible = false;

            var original_body_column = list_requests.get_column(Column.ORIGINAL_REQUEST_BODY);
            original_body_column.visible = false;

            text_view_request = new RequestTextEditor (application_window);
            text_view_request.editable = false;
            text_view_request.show ();
            scrolled_window_text_request.add (text_view_request);

            text_view_requestresponse = new RequestTextEditor (application_window);
            text_view_requestresponse.show ();
            scrolled_window_text_requestresponse.add (text_view_requestresponse);

            hex_editor_request = new HexEditor (application_window);
            hex_editor_request.show ();
            scrolled_window_hex_request.add (hex_editor_request);

            hex_editor_requestresponse = new HexEditor (application_window);
            hex_editor_requestresponse.show ();
            scrolled_window_hex_requestresponse.add (hex_editor_requestresponse);

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
                var original_request_body = request_data.get_string_member ("RequestBody");

                if (direction == "browser_to_server") {
                    direction = "Request";
                } else {
                    direction = "Response";
                }

                Gtk.TreeIter iter;
                liststore_requests.insert_with_values (out iter, -1,
                    Column.REQUEST_GUID, request_guid,
                    Column.DATA_PACKET_GUID, data_packet_guid,
                    Column.PROTOCOL, protocol,
                    Column.DIRECTION, direction,
                    Column.URL, url,
                    Column.BODY, body,
                    Column.ORIGINAL_REQUEST_BODY, original_request_body
                );

                if (list_selection.get_selected_rows (null).length () == 0) {
                    list_selection.select_iter (iter);
                }
            }

            application_window.set_intercepted_request_count (liststore_requests.iter_n_children (null));
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
                    liststore_requests.clear ();
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

            label_edit_request.label = "";

            selection.selected_foreach ((model, path, iter) => {
                if (selection_count == 1) {
                    string request_guid;
                    string url;
                    string body;
                    string direction;
                    string protocol;
                    string original_request_body;

                    model.get (iter, Column.REQUEST_GUID, out request_guid);
                    model.get (iter, Column.URL, out url);
                    model.get (iter, Column.BODY, out body);
                    model.get (iter, Column.DIRECTION, out direction);
                    model.get (iter, Column.PROTOCOL, out protocol);
                    model.get (iter, Column.ORIGINAL_REQUEST_BODY, out original_request_body);

                    var body_bytes = Base64.decode (body);
                    var original_request_body_bytes = Base64.decode (original_request_body);

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
                        text_view_requestresponse.buffer.text = ((string) body_bytes).replace("\r\n", "\n");
                        text_view_requestresponse.direction = direction.down ();
                        text_view_requestresponse.editable = true;
                        text_view_requestresponse.on_text_changed (true);
                        text_view_requestresponse.set_request_details (request_guid, protocol, url);
                    }

                    var is_request = (direction == "Request");
                    button_forward.sensitive = true;
                    button_drop.sensitive = is_request;
                    button_intercept_response.sensitive = is_request && (protocol != "Websocket");

                    box_original_request.visible = !is_request && (original_request_body != "");
                    label_edit_request.label = box_original_request.visible ? "Request and Response" : "Request";

                    if (!is_request && (original_request_body != "")) {
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
                            text_view_request.buffer.text = ((string) original_request_body_bytes).replace("\r\n", "\n");
                            text_view_request.direction = direction.down ();
                            text_view_request.set_request_details (request_guid, protocol, url);
                        }
                    }
                } else {
                    box_original_request.visible = false;
                    scrolled_window_hex_requestresponse.hide ();
                    scrolled_window_text_requestresponse.show ();
                    text_view_request.buffer.text = "(Multiple requests/responses selected)";
                    text_view_request.set_request_details ("", "", "");
                    text_view_requestresponse.editable = false;
                    text_view_requestresponse.set_request_details ("", "", "");
                    button_forward.sensitive = true;
                    button_drop.sensitive = false;
                    button_intercept_response.sensitive = false;
                }
            });

            if (selection_count == 0) {
                scrolled_window_hex_requestresponse.hide ();
                scrolled_window_text_requestresponse.show ();
                text_view_requestresponse.buffer.text = "";
                text_view_requestresponse.editable = false;
                text_view_requestresponse.set_request_details ("", "", "");
                box_original_request.hide ();
            }
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
                        var bytes = ((HexStaticBuffer)hex_editor_requestresponse.buffer).get_buffer ();
                        body = Base64.encode (bytes);
                    }
                    else {
                        body = Base64.encode (text_view_requestresponse.buffer.text.data);
                    }
                }

                if (direction == "Request") {
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

            message.set_request_body_from_bytes ("application/json", new Bytes(parameters.data));
            application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }

        public void reset_state () {
            liststore_requests.clear ();
            clear_gui ();
            get_intercept_settings ();
            get_requests ();
        }
    }
}
