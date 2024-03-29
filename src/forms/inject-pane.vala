using Soup;

namespace Pakiki {
    [GtkTemplate (ui = "/com/forensant/pakiki/inject-pane.ui")]
    class InjectPane : Gtk.Paned, MainApplicationPane {

        [GtkChild]
        private unowned Gtk.Grid grid;
        [GtkChild]
        private unowned Gtk.ScrolledWindow injectListScrollWindow;

        private ApplicationWindow application_window;
        private InjectNew inject_new_form;
        private InjectListRow inject_list_placeholder_row;
        private InjectUnderway inject_underway_form;
        private Gtk.ListBox list_box_injection_scans;
        private PlaceholderInject placeholder_form;
        private string select_guid_when_received;
        private WebsocketConnection websocket;

        public InjectPane (ApplicationWindow application_window) {
            this.application_window = application_window;
            list_box_injection_scans = new Gtk.ListBox ();
            list_box_injection_scans.show ();
            injectListScrollWindow.add (list_box_injection_scans);

            inject_list_placeholder_row = new InjectListRow.placeholder ();
            list_box_injection_scans.insert (inject_list_placeholder_row, 0);

            inject_underway_form = new InjectUnderway (application_window, this);
            grid.attach (inject_underway_form, 0, 1);
            inject_underway_form.hide ();

            inject_new_form = new InjectNew (application_window, this);
            grid.attach (inject_new_form, 0, 0);
            inject_new_form.hide ();

            placeholder_form = new PlaceholderInject ();
            grid.attach (placeholder_form, 0, 2);
            placeholder_form.show ();
            
            list_box_injection_scans.row_selected.connect (on_row_selected);

            get_inject_operations ();
        }

        public bool can_search () {
            return inject_underway_form.visible;
        }

        public void clone_inject_operation (InjectOperation operation) {
            inject_underway_form.hide ();
            placeholder_form.hide ();
            inject_new_form.show ();
            list_box_injection_scans.unselect_all ();
            inject_new_form.clone_inject_operation (operation);
            pane_changed ();
        }

        public bool find_activated () {
            return inject_underway_form.visible && inject_underway_form.find_activated ();
        }

        private void get_inject_operations () {
            if (application_window.core_address == "") {
                return;
            }
            var url = "http://" + application_window.core_address + "/inject_operations";
            
            var session = application_window.http_session;
            var message = new Soup.Message ("GET", url);

            session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                if (message.status_code != 200) {
                    return;
                }

                var row = list_box_injection_scans.get_row_at_index (0);
                while (row != null) {
                    list_box_injection_scans.remove (row);
                    row = list_box_injection_scans.get_row_at_index (0);
                }

                list_box_injection_scans.insert (inject_list_placeholder_row, -1);
                list_box_injection_scans.insert (new InjectListRow.label(InjectOperation.Status.COMPLETED, "Completed"), -1);
                list_box_injection_scans.insert (new InjectListRow.label(InjectOperation.Status.UNDERWAY,  "Underway"),  -1);
                list_box_injection_scans.insert (new InjectListRow.label(InjectOperation.Status.ARCHIVED,  "Archived"),  -1);
                
                try {
                    var bytes = session.send_and_read_async.end (res);
                    var parser = new Json.Parser ();
                    parser.load_from_data ((string) bytes.get_data (), -1);

                    var rootArray = parser.get_root().get_array();

                    foreach (var reqElement in rootArray.get_elements ()) {
                        var scan = reqElement.get_object ();
                        parse_inject_object (scan);
                    }
                } catch (Error err) {
                    stdout.printf ("Could not retrieve inject scans: %s\n", err.message);
                }

                show_appropriate_labels ();
            });

            if (websocket != null && websocket.state == Soup.WebsocketState.OPEN) {
                websocket.close(Soup.WebsocketCloseCode.NO_STATUS, null);
            }

            url = CoreProcess.websocket_url (application_window, "Inject Operation");
            
            var wsmessage = new Soup.Message("GET", url);
            session.websocket_connect_async.begin(wsmessage, "localhost", null, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    websocket = session.websocket_connect_async.end(res);
                    websocket.max_incoming_payload_size = 0;
                    websocket.message.connect(on_websocket_message);
                    websocket.error.connect ((err) => {
                        stdout.printf("Websocket error: %s\n", err.message);
                    });
                }
                catch (Error err) {
                    stdout.printf ("Error, ending websocket connection: %s\n", err.message);
                }
            });
        }

        private void insert_into_position (InjectListRow row_to_insert) {
            var i = 0;
            var inserted = false;
            list_box_injection_scans.@foreach ( (widget) => {
                if (inserted) {
                    return;
                }

                var row = (InjectListRow)widget;

                if (row.row_type == InjectListRow.Type.LABEL && row.status == row_to_insert.status) {
                    list_box_injection_scans.insert (row_to_insert, i + 1);
                    inserted = true;
                    row_to_insert.show_all ();
                }

                i++;
            });
        }

        public string new_tooltip_text () {
            return "New Injection Scan";
        }

        public bool new_visible () {
            return !inject_new_form.visible;
        }

        private void on_new_clicked () {
            on_new_inject_operation ();
        }

        public void on_new_inject_operation (string? guid = null) {
            inject_underway_form.hide ();
            placeholder_form.hide ();
            inject_new_form.show ();
            if (guid != null) {
                inject_new_form.populate_request (guid);
            }
            list_box_injection_scans.unselect_all ();
            pane_changed ();
        }

        private void on_row_selected (Gtk.ListBoxRow? widget) {
            if (widget == null) {
                return;
            }

            var row = (InjectListRow)widget;
            inject_new_form.hide ();
            placeholder_form.hide ();
            inject_underway_form.show ();
            inject_underway_form.set_inject_operation (row.inject_operation);
            pane_changed ();
        }

        public void on_search (string query, bool negative_filter, bool exclude_resources, string protocol) {
            inject_underway_form.on_search (query, negative_filter, exclude_resources);
        }

        private void on_websocket_message (int type, Bytes message) {
            var parser = new Json.Parser ();
            var json_data = (string) message.get_data ();
            
            if(json_data == "") {
                return;
            }
            
            try {
                parser.load_from_data (json_data, -1);
            }
            catch(Error e) {
                stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, json_data);
                return;
            }

            var operation = parser.get_root ().get_object ();
            parse_inject_object (operation);
            show_appropriate_labels ();
        }

        private void parse_inject_object (Json.Object obj) {            
            var guid = obj.get_string_member("GUID");
            var inject_operation = new InjectOperation (obj);

            // go through the existing rows and see if it already exists
            // if it does, update the status, progress and/or title
            var exists      = false;
            var to_reinsert = false;

            var currently_selected = (inject_underway_form.operation != null && inject_underway_form.operation.guid == guid);

            list_box_injection_scans.@foreach ( (widget) => {
                var row = (InjectListRow)widget;

                if (row.inject_operation != null && row.inject_operation.guid == guid) {
                    exists = true;

                    if (row.inject_operation.get_status () == InjectOperation.Status.UNDERWAY && inject_operation.get_status () == InjectOperation.Status.COMPLETED) {
                        var message = "Pākiki has finished an inject scan.";

                        if (row.inject_operation.title != "") {
                            message = "Pākiki has finished the following scan: " + row.inject_operation.title;
                        }

                        application_window.display_notification ("Inject scan completed",
                                message,
                                this,
                                row.inject_operation.guid);
                    }

                    if (row.inject_operation.get_status () == inject_operation.get_status ()) {
                        row.update_inject_operation (inject_operation);
                    }
                    else {
                        to_reinsert = true;
                        list_box_injection_scans.remove (row);
                    }
                }
            });

            // ensure the ongoing scan is updated if it's currently selected
            if (exists && currently_selected) {
                inject_underway_form.set_inject_operation (inject_operation);
            }

            // insert the row into the list, if it's not already in there
            if (exists == false || to_reinsert) {
                var row = new InjectListRow.inject_scan (inject_operation);
                insert_into_position (row);

                if (currently_selected) {
                    list_box_injection_scans.select_row (row);
                }

                if (select_guid_when_received != null && select_guid_when_received == guid) {
                    list_box_injection_scans.select_row (row);
                    select_guid_when_received = null;
                }
            }
        }

        public void reset_state () {
            get_inject_operations ();
            inject_underway_form.hide ();
            inject_new_form.hide ();
            inject_new_form.reset_state ();
            pane_changed ();
        }

        public void select_when_received (string guid) {
            var found = false;

            list_box_injection_scans.@foreach ( (widget) => {
                var row = (InjectListRow)widget;

                if (row.row_type == InjectListRow.Type.INJECT_SCAN && row.inject_operation.guid == guid) {
                    found = true;
                    select_guid_when_received = null;
                    
                    list_box_injection_scans.select_row (row);
                }
            });

            select_guid_when_received = guid;
        }

        public void set_selected_guid (string guid) {
            select_when_received (guid);
        }

        private void show_appropriate_labels() {
            var completed_present = false, underway_present = false, archived_present = false;

            list_box_injection_scans.@foreach ( (widget) => {
                var row = (InjectListRow)widget;

                if (row.row_type == InjectListRow.Type.INJECT_SCAN ) {
                    if (row.status == InjectOperation.Status.COMPLETED) { completed_present = true; }
                    if (row.status == InjectOperation.Status.UNDERWAY)  { underway_present  = true; }
                    if (row.status == InjectOperation.Status.ARCHIVED)  { archived_present  = true; }
                }
            });

            list_box_injection_scans.@foreach ( (widget) => {
                var row = (InjectListRow)widget;

                if (row.row_type == InjectListRow.Type.LABEL) {
                    var show = false;

                    if (row.status == InjectOperation.Status.COMPLETED && completed_present) {
                        show = true;
                        row.first = true;
                    }

                    if (row.status == InjectOperation.Status.UNDERWAY  && underway_present)  {
                        show = true;
                        row.first = (completed_present == false);
                    }

                    if (row.status == InjectOperation.Status.ARCHIVED  && archived_present)  {
                        show = true;
                        row.first = (completed_present == false && underway_present == false);
                    }
                    
                    if (show) {
                        row.show_all ();
                    } else {
                        row.hide ();
                    }
                }
            });

            if (completed_present == false && underway_present == false && archived_present == false) {
                inject_list_placeholder_row.show_all ();
            } else {
                inject_list_placeholder_row.hide ();
            }
        }
    }
}
