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
        private unowned Gtk.TextView text_view_request;
      
        private ApplicationWindow application_window;
        private Gtk.ListStore liststore_requests;
        private bool updating;
        private WebsocketConnection websocket;

        enum Column {
            GUID,
            DIRECTION,
            URL,
            BODY
        }
        
        public Intercept (ApplicationWindow application_window) {
            this.application_window = application_window;
            liststore_requests = new Gtk.ListStore (4, typeof (string), typeof (string), typeof (string), typeof (string));
            list_requests.set_model (liststore_requests);

            list_requests.insert_column_with_attributes (-1, "GUID", new CellRendererText (), "text", Column.GUID);
            list_requests.insert_column_with_attributes (-1, "Direction", new CellRendererText (), "text", Column.DIRECTION);
            list_requests.insert_column_with_attributes (-1, "URL", new CellRendererText (), "text", Column.URL);
            list_requests.insert_column_with_attributes (-1, "Body", new CellRendererText (), "text", Column.BODY);

            var guidColumn = list_requests.get_column(Column.GUID);
            guidColumn.visible = false;

            var bodyColumn = list_requests.get_column(Column.BODY);
            bodyColumn.visible = false;

            get_intercept_settings ();
            get_requests ();

            var selection = list_requests.get_selection();
            selection.changed.connect(this.on_selection_changed);
            selection.mode = Gtk.SelectionMode.MULTIPLE;
        }

        private void add_request_to_table (Json.Object requestData) {
            var action = requestData.get_string_member ("RecordAction");
            var request = requestData.get_object_member ("Request");
            var list_selection = list_requests.get_selection ();

            if (action == "delete") {
                var guidToRemove = request.get_string_member ("GUID");
                var select_next = false;
                
                liststore_requests.@foreach ((model, path, iter) => {
                    Value rowGuid;
                    model.get_value (iter, Column.GUID, out rowGuid);

                    if (rowGuid == guidToRemove) {
                        liststore_requests.remove (ref iter);
                        if (list_selection.iter_is_selected (iter)) {
                            select_next = true;
                        }
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
                var direction = requestData.get_string_member ("Direction");

                if (direction == "browser_to_server") {
                    direction = "Browser to server";
                } else {
                    direction = "Server to browser";
                }

                Gtk.TreeIter iter;
                liststore_requests.insert_with_values (out iter, -1,
                    Column.GUID, request.get_string_member ("GUID"),
                    Column.DIRECTION, direction,
                    Column.URL, request.get_string_member ("URL"),
                    Column.BODY, requestData.get_string_member ("Body")
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
        }

        private void get_intercept_settings () {
            var url = "http://localhost:10101/proxy/intercept_settings";

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
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
            var url = "http://localhost:10101/proxy/intercepted_requests";

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
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

            if (websocket != null) {
                websocket.close (Soup.WebsocketCloseCode.NO_STATUS, null);
            }

            url = "http://127.0.0.1:10101/project/notifications";

            var wsmessage = new Soup.Message ("GET", url);
            session.websocket_connect_async.begin (wsmessage, "localhost", null, null, (obj, res) => {
                try {
                    websocket = session.websocket_connect_async.end (res);
                } catch (Error err) {
                    stdout.printf ("Error ending websocket: %s\n", err.message);
                }
                websocket.message.connect (on_websocket_message);
            });
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
                    model.get (iter, Column.BODY, out body);
                    model.get (iter, Column.DIRECTION, out direction);
                    text_view_request.buffer.text = (string) Base64.decode (body);

                    var is_request = (direction == "Browser to server");
                    button_forward.sensitive = true;
                    button_drop.sensitive = is_request;
                    button_intercept_response.sensitive = is_request;
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
                
            if (request.get_string_member ("ObjectType") != "Intercepted Request") {
                return;
            }

            add_request_to_table (request);
        }

        private void send_individual_request_response (string guid, string action, string direction, string body) {
            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://127.0.0.1:10101/proxy/set_intercepted_response");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("GUID");
            builder.add_string_value (guid);
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
            
            session.queue_message (message, null);
        }

        private void send_request_response (string action) {
            var list_selection = list_requests.get_selection ();

            var selection_count = list_selection.get_selected_rows (null).length ();

            list_selection.selected_foreach ((model, path, iter) => {
                string guid;
                string body;
                string direction;
                model.get (iter, Column.GUID, out guid);
                model.get (iter, Column.DIRECTION, out direction);
                model.get (iter, Column.BODY, out body);

                if (selection_count == 1) {
                    body = Base64.encode (text_view_request.buffer.text.data);
                }

                if (direction == "Browser to server") {
                    direction = "browser_to_server";
                } else {
                    direction = "server_to_browser";
                }

                send_individual_request_response (guid, action, direction, body);
            });

            list_selection.unselect_all ();
            clear_gui ();
        }

        private void set_intercept () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://127.0.0.1:10101/proxy/intercept_settings");

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
            
            session.queue_message (message, null);
        }

        public void reset_state () {
            liststore_requests.clear ();
            clear_gui ();
            get_intercept_settings ();
        }
    }
}
