using Soup;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/request-list.ui")]
    class RequestList : Gtk.Box {

        public signal void requests_loaded (bool present);
        public signal void request_double_clicked (string guid);
        public signal void request_selected (string guid);

        [GtkChild]
        private unowned Gtk.Box box;
        [GtkChild]
        private unowned Gtk.Label label_no_requests;
        [GtkChild]
        private unowned Gtk.Overlay overlay;
        [GtkChild]
        private unowned Gtk.Paned pane;
        [GtkChild]
        private unowned Gtk.ColumnView request_list;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_requests;

        private ApplicationWindow application_window;
        private Gtk.Box box_request_details;
        private bool exclude_resources;
        private Gee.Set<string> guid_set;
        private Gtk.Label label_overlay;
        private GLib.ListStore liststore;
        private Gtk.SelectionModel liststore_selection_model;
        private PlaceholderRequests placeholder_requests;
        private RequestCompare request_compare;
        private RequestDetails request_details;
        private string[] scan_ids;
        private bool search_negative_filter;
        private string search_protocol;
        private string search_query;
        private bool updating;
        private bool resetting;
        private string url_filter;
        private WebsocketConnection websocket;

        private bool _process_actions;
        public bool process_actions {
            get { return _process_actions; }
            set { 
                _process_actions = value;
                request_details.show_send_to = value;
            }
        }
        
        private int COLUMN_COUNT = 12;

        public RequestList (ApplicationWindow application_window, bool initial_launch, string[] scan_ids = {}) {
            this.application_window = application_window;
            this.scan_ids = scan_ids;
            this.exclude_resources = true;
            this.updating = false;
            this.search_negative_filter = false;
            this.search_protocol = "";
            this.search_query = "";
            this.url_filter = "";
            this._process_actions = true;
            guid_set = new Gee.TreeSet<string> ();
            request_list.has_tooltip = true;

            liststore = new GLib.ListStore (typeof (Request));
            var model = new Gtk.SortListModel (liststore, request_list.sorter);
            liststore_selection_model = new Gtk.MultiSelection (model);
            liststore_selection_model.selection_changed.connect (on_selection_changed);
            request_list.set_model (liststore_selection_model);

            this.placeholder_requests = new PlaceholderRequests (application_window);
            placeholder_requests.hide ();
            this.box.append (placeholder_requests);

            label_overlay = new Gtk.Label ("");
            label_overlay.name = "lbl_overlay";
            label_overlay.label = "Loading requests...";
            overlay.add_overlay (label_overlay);

            box_request_details = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            
            request_details = new RequestDetails (application_window);
            request_details.hide ();
            box_request_details.append (request_details);

            request_compare = new RequestCompare (application_window);
            request_compare.hide ();
            box_request_details.append (request_compare);

            box_request_details.hide ();
            pane.set_end_child (box_request_details);

            init_columns ();
                     
            var visible_columns = this.visible_columns ();
            var cols = request_list.get_columns ();
            var col_count = cols.get_n_items ();
            for (int i = 0; i < col_count; i++) {
                var col = cols.get_item (i) as Gtk.ColumnViewColumn;
                if (col == null) {
                    stdout.printf ("Could not cast column to ColumnViewColumn\n");
                    continue;
                }

                var visible = (!visible_columns.has_key (col.title)) || visible_columns[col.title];
                col.visible = visible;
            }

            if (scan_ids.length != 0 && !initial_launch) {
                get_requests ();
            }

            var request_list_double_click_gesture = new Gtk.GestureClick ();
            request_list_double_click_gesture.button = 1;
            request_list_double_click_gesture.pressed.connect ( (n_press, x, y) => {
                if (n_press >= 2) {
                    on_request_list_doubleclick_event ( );
                }
            });
            request_list.add_controller (request_list_double_click_gesture);

            var request_list_right_click_gesture = new Gtk.GestureClick ();
            request_list_right_click_gesture.button = 3;
            request_list_right_click_gesture.released.connect ( (n_press, x, y) => {
                on_request_list_right_click_event (x, y);
            });
            request_list.add_controller (request_list_right_click_gesture);
            set_header_right_click_menus ();
        }

        private void add_request_to_table (Json.Object request) {
            var url = request.get_string_member("URL");

            if (url_filter != "" && !url.contains(url_filter)) {
                return;
            }

            var guid = request.get_string_member ("GUID");
            guid_set.add (guid);

            // TODO: Maybe use splice for these?
            var r = new Request (request, application_window);
            liststore.append(r);

            if (label_no_requests.visible || placeholder_requests.visible) {
                show_controls (1);
            }
        }

        public bool find_activated () {
            return request_details.find_activated ();
        }

        private int get_col_pos (string title) {
            var settings = application_window.settings.get_string (scan_ids.length == 0 ? "grid-columns" : "scan-grid-columns");
            var columns = settings.split (";");
            
            for (int i = 0; i < columns.length; i++) {
                if (columns[i].index_of (title, 0) == 0) {
                    return i;
                }
            }

            return -1;
        }

        private void get_requests () {
            if (application_window.core_address == "") {
                return;
            }

            label_no_requests.visible = false;
            this.updating = true;
            guid_set.clear ();
            request_details.reset_state ();
            liststore.remove_all ();
            this.updating = false;

            bool fetched_data = false;
            var url = "http://" + application_window.core_address + "/requests?exclude_resources=" + (exclude_resources ? "true" : "false");

            if (search_query != null && search_query != "") {
                url += "&filter=" + GLib.Uri.escape_string (search_query);
            }

            if (search_negative_filter) {
                url += "&negative_filter=true";
            }

            var scan_id = string.joinv (":", scan_ids);
            if (scan_id != "") {
                url += "&scanid=" + scan_id;
            }

            if (url_filter != "") {
                url += "&url_filter=" + GLib.Uri.escape_string ("://" + url_filter);
            }

            if (search_protocol != "" && search_protocol != "all") {
                url += "&protocol=" + search_protocol;
            }

            var message = new Soup.Message ("GET", url);
            var response_received = false;
            var is_resetting = resetting;
            
            Timeout.add_full (GLib.Priority.HIGH, 50, () => {
                if (!response_received && !is_resetting) {
                    label_overlay.visible = true;
                    overlay.show ();
                }

                return GLib.Source.REMOVE;
            });
            
            application_window.http_session.send_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_async.end (res);
                    
                    this.updating = true;
                    fetched_data = true;
                    var parser = new Json.Parser ();

                    if (message.status_code != 200) {
                        stderr.printf("Could not connect to %s\n", url);
                        return;
                    }

                    parser.load_from_stream_async.begin (response, null, (obj2, res2) => {
                        try {
                            parser.load_from_stream_async.end (res2);

                            var rootArray = parser.get_root ().get_array ();

                            show_controls (rootArray.get_length ());
        
                            foreach (var reqElement in rootArray.get_elements ()) {
                                var request = reqElement.get_object ();
                                add_request_to_table (request);
                            }
        
                            var should_scroll = true;
                            Timeout.add_full (GLib.Priority.HIGH, 1000, () => {
                                should_scroll = false;
                                label_overlay.visible = false;
                                return GLib.Source.REMOVE;
                            });
        
                            GLib.Idle.add_full (GLib.Priority.DEFAULT_IDLE, () => {
                                if (should_scroll) {
                                    scroll_to_bottom ();
                                    label_overlay.visible = false;
                                }
                                return GLib.Source.REMOVE;
                            });
        
                            this.requests_loaded (rootArray.get_length () > 0);        
                        } catch (Error err) {
                            stdout.printf ("Could not populate request list: %s\n", err.message);
                            label_overlay.visible = false;
                        }
                    });
                } catch (Error err) {
                    stdout.printf ("Could not populate request list: %s\n", err.message);
                    label_overlay.visible = false;
                }

                this.updating = false;
                response_received = true;
            });

            if (websocket != null && websocket.state == Soup.WebsocketState.OPEN) {
                websocket.close (Soup.WebsocketCloseCode.NO_STATUS, null);
            }

            var notification_filters = new Gee.HashMap<string, string> ();

            if (scan_ids.length == 0) {
                notification_filters["ScanID"] = "";
            } else if (scan_ids.length == 1) {
                notification_filters["ScanID"] = scan_ids[0];
            }
           
            if (search_protocol != "" && search_protocol != "all") {
                notification_filters["Protocol"] = search_protocol;
            }

            url = CoreProcess.websocket_url (application_window, "HTTP Request", notification_filters);
            string filter = "";
            if (exclude_resources) {
                filter += "exclude_resources:true";
            }
            if (search_negative_filter) {
                filter += " negative_filter:true";
            }

            if (search_query != null && search_query != "") {
                filter += GLib.Uri.escape_string (" " + search_query);
            }

            if (filter != "") {
                url += "&filter=" + filter;
            }

            url += "&api_key=" + application_window.api_key;

            var wsmessage = new Soup.Message ("GET", url);
            application_window.http_session.websocket_connect_async.begin (wsmessage, "localhost", null, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    websocket = application_window.http_session.websocket_connect_async.end (res);
                    websocket.max_incoming_payload_size = 0;
                    websocket.message.connect (on_websocket_message);
                } catch (Error err) {
                    stdout.printf ("Error connecting to websocket %s, error message: %s\n", url, err.message);
                }
            });
        }

        private Request[] get_selected_requests () {
            var selected_rows = liststore_selection_model.get_selection ();
            var selected_row_count = selected_rows.get_size ();

            Request[] requests = {};

            for (int i = 0; i < selected_row_count; i++) {
                var selection = selected_rows.get_nth (i);
                var req = (Request?)liststore.get_item (selection);
                if (req == null) {
                    continue;
                }

                requests += req;
            }


            return requests;
        }

        private string[] get_selected_guids () {
            var guids = new string[]{};
            var selected_requests = get_selected_requests ();
            for (int i = 0; i < selected_requests.length; i++) {
                guids += selected_requests[i].guid;
            }
            return guids;
        }

        private static bool guids_equal (GLib.Object a, GLib.Object b) {
            var req_a = a as Request;
            var req_b = b as Request;

            if (req_a == null || req_b == null) {
                return false;
            }

            return req_a.guid == req_b.guid;
        }

        private void init_columns () {
            var protocol_column_factory = new Gtk.SignalListItemFactory ();
            protocol_column_factory.setup.connect (on_setup_label_column);
            protocol_column_factory.bind.connect (on_bind_column_protocol);

            var time_column_factory = new Gtk.SignalListItemFactory ();
            time_column_factory.setup.connect (on_setup_label_column_truncate_middle);
            time_column_factory.bind.connect (on_bind_column_time);

            var url_column_factory = new Gtk.SignalListItemFactory ();
            url_column_factory.setup.connect (on_setup_label_column_truncate_end);
            url_column_factory.bind.connect (on_bind_column_url);

            var size_column_factory = new Gtk.SignalListItemFactory ();
            size_column_factory.setup.connect (on_setup_label_column);
            size_column_factory.bind.connect (on_bind_column_size);

            var content_type_column_factory = new Gtk.SignalListItemFactory ();
            content_type_column_factory.setup.connect (on_setup_label_column);
            content_type_column_factory.bind.connect (on_bind_column_content_type);

            var duration_column_factory = new Gtk.SignalListItemFactory ();
            duration_column_factory.setup.connect (on_setup_label_column);
            duration_column_factory.bind.connect (on_bind_column_duration);

            var verb_column_factory = new Gtk.SignalListItemFactory ();
            verb_column_factory.setup.connect (on_setup_label_column);
            verb_column_factory.bind.connect (on_bind_column_verb);

            var status_column_factory = new Gtk.SignalListItemFactory ();
            status_column_factory.setup.connect (on_setup_label_column);
            status_column_factory.bind.connect (on_bind_column_status);

            var payload_column_factory = new Gtk.SignalListItemFactory ();
            payload_column_factory.setup.connect (on_setup_label_column_truncate_end);
            payload_column_factory.bind.connect (on_bind_column_payload);

            var error_column_factory = new Gtk.SignalListItemFactory ();
            error_column_factory.setup.connect (on_setup_label_column_truncate_end);
            error_column_factory.bind.connect (on_bind_column_error);

            var notes_column_factory = new Gtk.SignalListItemFactory ();
            notes_column_factory.setup.connect (on_setup_editable_column);
            notes_column_factory.bind.connect (on_bind_column_notes);

            var protocol_column = new Gtk.ColumnViewColumn ("Protocol", protocol_column_factory);
            protocol_column.resizable = true;
            protocol_column.sorter = new Gtk.CustomSorter (on_sort_protocol);

            var time_column = new Gtk.ColumnViewColumn ("Time", time_column_factory);
            time_column.resizable = true;
            time_column.fixed_width = 100;
            time_column.sorter = new Gtk.CustomSorter (on_sort_time);

            var url_column = new Gtk.ColumnViewColumn ("URL", url_column_factory);
            url_column.resizable = true;
            url_column.expand = true;
            url_column.fixed_width = 200;
            url_column.sorter = new Gtk.CustomSorter (on_sort_url);

            var size_column = new Gtk.ColumnViewColumn ("Size", size_column_factory);
            size_column.resizable = true;
            size_column.sorter = new Gtk.CustomSorter (on_sort_size);

            var content_type_column = new Gtk.ColumnViewColumn ("Content Type", content_type_column_factory);
            content_type_column.resizable = true;
            content_type_column.sorter = new Gtk.CustomSorter (on_sort_content_type);

            var duration_column = new Gtk.ColumnViewColumn ("Duration", duration_column_factory);
            duration_column.resizable = true;
            duration_column.sorter = new Gtk.CustomSorter (on_sort_duration);

            var verb_column = new Gtk.ColumnViewColumn ("Verb", verb_column_factory);
            verb_column.resizable = true;
            verb_column.sorter = new Gtk.CustomSorter (on_sort_verb);

            var status_column = new Gtk.ColumnViewColumn ("Status", status_column_factory);
            status_column.resizable = true;
            status_column.sorter = new Gtk.CustomSorter (on_sort_status);

            var payload_column = new Gtk.ColumnViewColumn ("Payloads", payload_column_factory);
            payload_column.resizable = true;
            payload_column.sorter = new Gtk.CustomSorter (on_sort_payload);
            payload_column.visible = scan_ids.length != 0;

            var error_column = new Gtk.ColumnViewColumn ("Error", error_column_factory);
            error_column.resizable = true;
            error_column.sorter = new Gtk.CustomSorter (on_sort_error);

            var notes_column = new Gtk.ColumnViewColumn ("Notes", notes_column_factory);
            notes_column.resizable = true;
            notes_column.sorter = new Gtk.CustomSorter (on_sort_notes);

            request_list.append_column (protocol_column);
            request_list.append_column (time_column);
            request_list.append_column (url_column);
            request_list.append_column (size_column);
            request_list.append_column (content_type_column);
            request_list.append_column (duration_column);
            request_list.append_column (verb_column);
            request_list.append_column (status_column);
            request_list.append_column (payload_column);
            request_list.append_column (error_column);
            request_list.append_column (notes_column);
        }

        private void on_bind_column_content_type (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.content_type ();
            label.tooltip_text = item_data.content_type ();
        }

        private void on_bind_column_duration (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.response_duration ();
            label.tooltip_text = item_data.response_duration ();
        }

        private void on_bind_column_error (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.error;
            label.tooltip_text = item_data.error;
        }

        private void on_bind_column_notes (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.EditableLabel) list_item.child;
            label.text = item_data.notes;
            label.tooltip_text = item_data.notes;
            label.bind_property ("text", item_data, "notes", GLib.BindingFlags.DEFAULT, null, null);
        }

        private void on_bind_column_payload (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            var payloads = item_data.payloads_to_string ();
            label.label = payloads;
            label.tooltip_text = payloads;
        }

        private void on_bind_column_protocol (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.protocol;
            label.tooltip_text = item_data.protocol;
        }

        private void on_bind_column_size (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.response_size ();
            label.tooltip_text = item_data.response_size ();
        }

        private void on_bind_column_status (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            var text = item_data.status.to_string ();
            label.label = text;
            label.tooltip_text = text;
        }

        private void on_bind_column_time (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            var text = response_time(new DateTime.from_unix_local (item_data.time));
            label.label = text;
            label.tooltip_text = text;
        }

        private void on_bind_column_url (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.url;
            label.tooltip_text = item_data.url;
        }

        private void on_bind_column_verb (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var list_item = (Gtk.ListItem) list_item_obj;
            var item_data = (Request) list_item.item ;
            var label = (Gtk.Label) list_item.child;
            label.label = item_data.verb;
            label.tooltip_text = item_data.verb;
        }

        private void on_websocket_message (int type, Bytes message) {
            var parser = new Json.Parser ();
            var json_data = (string)message.get_data();
            
            if (json_data == "") {
                return;
            }
            
            try {
                parser.load_from_data (json_data, -1);
            }
            catch(Error e) {
                stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, json_data);
                return;
            }

            var request = parser.get_root ().get_object ();

            if (scan_ids.length > 1) {
                var scan_id = request.get_string_member ("ScanID");
                var scan_id_found = false;
    
                for (int i = 0; i < scan_ids.length; i++) {
                    if (scan_ids[i] == scan_id) {
                        scan_id_found = true;
                        break;
                    }
                }
                
                if (!scan_id_found) {
                    return;
                }
            }

            var should_scroll_to_bottom = ((request_list.vadjustment.value + request_list.vadjustment.page_size + 150.0) > request_list.vadjustment.upper);

            var request_guid = request.get_string_member ("GUID");
            var action = "";
            if (request.has_member ("Action")) {
                action = request.get_string_member ("Action");
            }

            if (action == "filtered") {
                if (guid_set.contains (request_guid)) {
                    for (uint i = 0; i < liststore.get_n_items (); i++) {
                        var req = liststore.get_item (i) as Request;
                        if (request != null && req.guid == request_guid) {
                            liststore.remove (i);
                            guid_set.remove (request_guid);
                            break;
                        }
                    }
                }

                return;
            }

            if (!guid_set.contains (request_guid)) {
                add_request_to_table (request);
            } else {
                var r = new Request (request, application_window);
                uint position = 0;
                var found = liststore.find_with_equal_func (r, guids_equal, out position);

                if (!found) {
                    return;
                }

                var request_as_array = new GLib.Object[]{r};
                liststore.splice (position, 1, request_as_array);
            }

            // the currently highlighted request has been updated
            if (request_details.guid == request_guid) {
                if (request.get_string_member ("Protocol") == "Websocket") {
                    request_details.set_request (request_guid, true);
                } else {
                    int64 content_length = request.get_int_member ("ResponseSize") + request.get_int_member ("RequestSize");
                    request_details.request_updated (content_length);
                }
            }

            // automatically scroll to the bottom if needed
            if(should_scroll_to_bottom) {
                scroll_to_bottom ();
            }
        }

        public void on_request_list_doubleclick_event () {
            var requests = get_selected_requests ();
            if (requests.length != 1) {
                return;
            }
            var request = requests[0];
            
            var is_http = request.protocol.contains("HTTP");
            
            this.request_double_clicked (request.guid);
            
            if (process_actions) {
                application_window.request_double_clicked (request.guid, is_http);
            }
        }
         
        public bool on_request_list_right_click_event (double x, double y) {
            if (process_actions) {
                // right click

                var reqs = get_selected_requests ();

                var guid = "";
                var protocol = "";
                var url = "";

                if (reqs.length >= 1) {
                    guid = reqs[0].guid;
                    protocol = reqs[0].protocol;
                    url = reqs[0].url;
                }

                if (guid == "") {
                    return false;
                }

                var menu = RequestDetails.populate_send_to_menu (application_window, guid, protocol, url);
                
                var popup = new Gtk.PopoverMenu.from_model (menu);
                popup.set_parent (this);
                var rect = Gdk.Rectangle () { x = (int)x, y = (int)y };
                popup.set_pointing_to (rect);
                popup.has_arrow = false;
                popup.popup ();
            }

            return false; // allow other event handlers to also be run
        }

        public void on_search (string query, bool negative_filter, bool exclude_resources, string protocol = "") {
            this.search_query = query;
            this.search_negative_filter = negative_filter;
            this.exclude_resources = exclude_resources;
            this.search_protocol = protocol;
            get_requests ();
        }

        private void on_selection_changed (uint position, uint n_items) {
            if (updating) {
                return;
            }

            var guids = get_selected_guids ();
            
            if (guids.length == 0) {
                return;
            }
            
            if (guids.length == 1 && guids[0] != "") {
                var guid = guids[0];

                var pos = pane.position;
                request_details.set_request (guid);
                pane.position = pos;
                
                request_selected (guid);
                request_details.show ();
                request_compare.hide ();
            }
            else {
                request_compare.compare_requests (guids[0], guids[1]);
                request_details.guid = "";

                request_compare.show ();
                request_details.hide ();
            }
        }


        private void on_setup_editable_column (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var label = new Gtk.EditableLabel ("");
            label.halign = Gtk.Align.START;
            ((Gtk.ListItem) list_item_obj).child = label;
        }

        private void on_setup_label_column (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var label = new Gtk.Label ("");
            label.halign = Gtk.Align.START;
            ((Gtk.ListItem) list_item_obj).child = label;
        }

        private void on_setup_label_column_truncate_middle (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var label = new Gtk.Label ("");
            label.halign = Gtk.Align.START;
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            ((Gtk.ListItem) list_item_obj).child = label;
        }

        private void on_setup_label_column_truncate_end (Gtk.SignalListItemFactory factory, GLib.Object list_item_obj) {
            var label = new Gtk.Label ("");
            label.halign = Gtk.Align.START;
            label.ellipsize = Pango.EllipsizeMode.END;
            ((Gtk.ListItem) list_item_obj).child = label;
        }

        private static int on_sort_content_type (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.response_content_type == req_b.response_content_type) {
                return 0;
            }

            if (req_a.response_content_type > req_b.response_content_type) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_duration (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.duration == req_b.duration) {
                return 0;
            }

            if (req_a.duration > req_b.duration) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_error (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.error == req_b.error) {
                return 0;
            }

            if (req_a.error > req_b.error) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_notes (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.notes == req_b.notes) {
                return 0;
            }

            if (req_a.notes > req_b.notes) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_payload (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.payloads_to_string () == req_b.payloads_to_string ()) {
                return 0;
            }

            if (req_a.payloads_to_string () > req_b.payloads_to_string ()) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_protocol (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.protocol == req_b.protocol) {
                return 0;
            }

            if (req_a.protocol > req_b.protocol) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_size (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.response_content_length == req_b.response_content_length) {
                return 0;
            }

            if (req_a.response_content_length > req_b.response_content_length) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_status (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.status == req_b.status) {
                return 0;
            }

            if (req_a.status > req_b.status) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_time (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.time == req_b.time) {
                return 0;
            }

            if (req_a.time > req_b.time) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_url (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.url == req_b.url) {
                return 0;
            }

            if (req_a.url > req_b.url) {
                return 1;
            }
            
            return -1;
        }

        private static int on_sort_verb (Request? req_a, Request? req_b) {
            if (req_a == null || req_b == null || req_a.verb == req_b.verb) {
                return 0;
            }

            if (req_a.verb > req_b.verb) {
                return 1;
            }
            
            return -1;
        }

        public static string response_time (DateTime time) {
            var now = new DateTime.now ();
            var isToday = (time.get_day_of_year () == now.get_day_of_year () && time.get_year () ==  now.get_year ());

            if (isToday) {
                return time.format ("%X");
            }
            else {
                return time.format ("%x %X");
            }
        }

        public void reset_state () {
            label_overlay.visible = false;
            resetting = true;
            get_requests ();
            request_details.reset_state ();
            resetting = false;
            request_compare.hide ();
            request_details.hide ();
        }

        private void save_column_settings () {
            var cols = request_list.get_columns ();
            var col_count = cols.get_n_items ();

            var settings = "";
            for (int i = 0; i < col_count; i++) {
                var col = cols.get_item (i) as Gtk.ColumnViewColumn;
                if (col == null) {
                    stdout.printf ("Could not cast column to ColumnViewColumn\n");
                    continue;
                }

                if (settings != "") {
                    settings += ";";
                }

                settings += col.title + ":" + (col.visible ? "1" : "0");
            }

            application_window.settings.set_string (scan_ids.length == 0 ? "grid-columns" : "scan-grid-columns", settings);            
        }

        private void scroll_to_bottom () {
            request_list.vadjustment.value = request_list.vadjustment.upper;
        }

        private void set_header_right_click_menus () {
            var menu = new GLib.Menu ();

            var cols = request_list.get_columns ();
            var col_count = cols.get_n_items ();

            var action_group = new GLib.SimpleActionGroup ();

            // build the menu
            for (int i = 0; i < col_count; i++) {
                var col = cols.get_item (i) as Gtk.ColumnViewColumn;
                if (col == null) {
                    stdout.printf ("Could not cast column to ColumnViewColumn\n");
                    continue;
                }

                if (col.title == "Payloads" && scan_ids.length == 0) {
                    continue;
                }

                var action_name = col.title.replace(" ", "");
                var action = new GLib.SimpleAction.stateful (action_name, null, new Variant.boolean (col.visible));
                action.activate.connect ((parameter) => {
                    col.visible = !col.visible;
                    save_column_settings ();
                    action_group.change_action_state (action_name, new Variant.boolean (col.visible));
                });

                action_group.add_action (action);

                var name = col.title;
                menu.append (name, "columntoggle." + action_name);
            }

            this.insert_action_group ("columntoggle", action_group);

            // go back through each column and set it
            for (int i = 0; i < col_count; i++) {
                var col = cols.get_item (i) as Gtk.ColumnViewColumn;
                if (col == null) {
                    stdout.printf ("Could not cast column to ColumnViewColumn\n");
                    continue;
                }

                col.header_menu = menu;
            }
        }

        public void set_scan_ids (string[] guids, bool refresh_list = true) {
            this.scan_ids = guids;
            if (refresh_list) {
                this.get_requests ();
            }
        }

        public void set_url_filter (string url) {
            if (this.url_filter != url) {
                this.url_filter = url;
                this.get_requests ();
            }
        }

        public void set_processed_launched (bool successful) {
            if (!successful) {
                placeholder_requests.set_error (application_window.core_address);
                placeholder_requests.show ();
                overlay.hide ();
            } else {
                placeholder_requests.update_proxy_address ();
                overlay.hide ();
            }
        }

        private void show_controls (uint request_count) {
            if (request_count == 0 && scan_ids.length == 0) {
                if (search_query != "" || url_filter != "" || (search_protocol != "" && search_protocol != "all")) {
                    label_no_requests.visible = true;
                } else {
                    placeholder_requests.show ();
                }
                scrolled_window_requests.hide ();
                box_request_details.hide ();
                request_details.hide ();
                request_compare.hide ();
            } else {
                label_no_requests.visible = false;
                placeholder_requests.hide ();
                overlay.show ();
                scrolled_window_requests.show ();
                box_request_details.show ();
                request_details.show ();
                request_compare.hide ();
                this.requests_loaded (true);
            }
        }

        private Gee.HashMap<string, bool> visible_columns () {
            var settings = application_window.settings.get_string (scan_ids.length == 0 ? "grid-columns" : "scan-grid-columns");
            var visible_columns = new Gee.HashMap<string, bool> ();

            if (settings == "") {
                return visible_columns;
            }

            var columns = settings.split (";");
            foreach (var column in columns) {
                var parts = column.split (":");
                visible_columns[parts[0]] = parts[1] == "1";
            }

            visible_columns["GUID"] = false;
            if (scan_ids.length == 0) {
                visible_columns["Payloads"] = false;
            }

            return visible_columns;
        }
    }
}
