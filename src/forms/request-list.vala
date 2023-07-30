using Soup;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/request-list.ui")]
    class RequestList : Gtk.Paned {

        public signal void requests_loaded (bool present);
        public signal void request_double_clicked (string guid);
        public signal void request_selected (string guid);

        [GtkChild]
        private unowned Gtk.Box box;
        [GtkChild]
        private unowned Gtk.Label label_no_requests;
        [GtkChild]
        private unowned Gtk.ListStore liststore;
        [GtkChild]
        private unowned Gtk.Overlay overlay;
        [GtkChild]
        private unowned Gtk.TreeView request_list;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_requests;

        private ApplicationWindow application_window;
        private Gtk.Box box_request_details;
        private bool exclude_resources;
        private Gee.Set<string> guid_set;
        private Gtk.Label label_overlay;
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
        
        enum Column {
            GUID,
            PROTOCOL,
            TIME,
            URL,
            RESPONSE_CONTENT_LENGTH,
            RESPONSE_CONTENT_TYPE,
            DURATION,
            VERB,
            STATUS,
            PAYLOADS,
            ERROR,
            NOTES
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

            this.placeholder_requests = new PlaceholderRequests (application_window);
            placeholder_requests.hide ();
            this.box.add (placeholder_requests);

            label_overlay = new Gtk.Label ("");
            label_overlay.name = "lbl_overlay";
            label_overlay.label = "Loading requests...";
            overlay.add_overlay (label_overlay);

            var url_renderer = new Gtk.CellRendererText();
            url_renderer.ellipsize = Pango.EllipsizeMode.END;
            url_renderer.ellipsize_set = true;

            var time_cell_renderer = new Gtk.CellRendererText();
            time_cell_renderer.ellipsize = Pango.EllipsizeMode.MIDDLE;
            time_cell_renderer.ellipsize_set = true;

            var response_length_renderer = new Gtk.CellRendererText ();
            var content_type_renderer    = new Gtk.CellRendererText ();
            var duration_renderer        = new Gtk.CellRendererText ();
            var status_renderer          = new Gtk.CellRendererText ();

            var payload_renderer = new Gtk.CellRendererText();
            payload_renderer.ellipsize = Pango.EllipsizeMode.END;
            payload_renderer.ellipsize_set = true;

            var error_renderer = new Gtk.CellRendererText();
            error_renderer.ellipsize = Pango.EllipsizeMode.END;
            error_renderer.ellipsize_set = true;

            var notes_renderer = new Gtk.CellRendererText();
            notes_renderer.ellipsize = Pango.EllipsizeMode.END;
            notes_renderer.ellipsize_set = true;
            notes_renderer.editable = true;
            notes_renderer.edited.connect(on_notes_updated);

            /*columns*/
            request_list.insert_column_with_attributes (get_col_pos ("GUID"),
                                                    "GUID",
                                                    new Gtk.CellRendererText(),
                                                    "text", Column.GUID);

            request_list.insert_column_with_attributes (get_col_pos ("Protocol"),
                                                    "Protocol",
                                                    new Gtk.CellRendererText(),
                                                    "text", Column.PROTOCOL);

            request_list.insert_column_with_attributes (get_col_pos ("Time"),
                                                    "Time",
                                                    time_cell_renderer,
                                                    "text", Column.TIME);

            request_list.insert_column_with_attributes (get_col_pos ("URL"),
                                                    "URL",
                                                    url_renderer,
                                                    "text", Column.URL);

            request_list.insert_column_with_attributes (get_col_pos ("Size"),
                                                    "Size",
                                                    response_length_renderer,
                                                    "text", Column.RESPONSE_CONTENT_LENGTH);

            request_list.insert_column_with_attributes (get_col_pos ("Content Type"),
                                                    "Content Type",
                                                    content_type_renderer,
                                                    "text", Column.RESPONSE_CONTENT_TYPE);

            request_list.insert_column_with_attributes (get_col_pos ("Duration"),
                                                    "Duration",
                                                    duration_renderer,
                                                    "text", Column.DURATION);

            request_list.insert_column_with_attributes (get_col_pos ("Verb"),
                                                    "Verb",
                                                    new Gtk.CellRendererText (),
                                                    "text", Column.VERB);

            request_list.insert_column_with_attributes (get_col_pos ("Status"),
                                                    "Status",
                                                    status_renderer,
                                                    "text", Column.STATUS);

            request_list.insert_column_with_attributes (get_col_pos ("Payloads"),
                                                    "Payloads",
                                                    payload_renderer,
                                                    "text", Column.PAYLOADS);

            request_list.insert_column_with_attributes (get_col_pos ("Error"),
                                                    "Error",
                                                    error_renderer,
                                                    "text", Column.ERROR);

            request_list.insert_column_with_attributes (get_col_pos ("Notes"),
                                                    "Notes",
                                                    notes_renderer,
                                                    "text", Column.NOTES);

                                                    
            var guid_column = request_list.get_column ( get_col_pos ("GUID"));
            guid_column.visible = false;

            var url_column = request_list.get_column (get_col_pos ("URL"));
            url_column.expand = true;
            url_column.min_width = 200;

            var time_column = request_list.get_column (get_col_pos ("Time"));
            time_column.set_cell_data_func(time_cell_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.TIME, out val);
                ((Gtk.CellRendererText)cell).text = response_time(new DateTime.from_unix_local(val.get_int()));
                val.unset();
            });
            time_column.min_width = 100;

            var response_size_column = request_list.get_column (get_col_pos ("Size"));
            response_size_column.set_cell_data_func(response_length_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.RESPONSE_CONTENT_LENGTH, out val);
                ((Gtk.CellRendererText)cell).text = response_size_to_string(val.get_int64 ());
                val.unset();
            });

            var response_type_column = request_list.get_column (get_col_pos ("Content Type"));
            response_type_column.set_cell_data_func(content_type_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.RESPONSE_CONTENT_TYPE, out val);
                var components = val.get_string ().split (";", 2);
                if (components.length >= 1) {
                    ((Gtk.CellRendererText)cell).text = components[0];
                }
                val.unset();
            });

            var duration_column = request_list.get_column (get_col_pos ("Duration"));
            duration_column.set_cell_data_func(duration_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.DURATION, out val);
                ((Gtk.CellRendererText)cell).text = response_duration(val.get_int ());
                val.unset();
            });

            var status_column = request_list.get_column (get_col_pos ("Status"));
            status_column.set_cell_data_func(status_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.STATUS, out val);

                if (val.get_int() == 0) {
                    ((Gtk.CellRendererText)cell).text = "";
                } else {
                    ((Gtk.CellRendererText)cell).text = val.get_int ().to_string ();
                }
                
                val.unset();
            });

            var payload_column = request_list.get_column (get_col_pos ("Payloads"));
            payload_column.set_cell_data_func(payload_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.PAYLOADS, out val);
                ((Gtk.CellRendererText)cell).text = payloads_to_string(val.get_string ());
                val.unset();
            });

            // if it's a scan, then it'll have payloads to show
            if (scan_ids.length == 0) {
                payload_column.visible = false;
            }

            for (int i = 0; i < request_list.get_n_columns(); i++) {
                request_list.get_column(i).resizable = true;
                request_list.get_column(i).reorderable = true;
            }

            request_list.get_column (get_col_pos ("Time")).sort_column_id         = Column.TIME;
            request_list.get_column (get_col_pos ("Protocol")).sort_column_id     = Column.PROTOCOL;
            request_list.get_column (get_col_pos ("URL")).sort_column_id          = Column.URL;
            request_list.get_column (get_col_pos ("Size")).sort_column_id         = Column.RESPONSE_CONTENT_LENGTH;
            request_list.get_column (get_col_pos ("Content Type")).sort_column_id = Column.RESPONSE_CONTENT_TYPE;
            request_list.get_column (get_col_pos ("Duration")).sort_column_id     = Column.DURATION;
            request_list.get_column (get_col_pos ("Verb")).sort_column_id         = Column.VERB;
            request_list.get_column (get_col_pos ("Status")).sort_column_id       = Column.STATUS;
            request_list.get_column (get_col_pos ("Payloads")).sort_column_id     = Column.PAYLOADS;
            request_list.get_column (get_col_pos ("Error")).sort_column_id        = Column.ERROR;
            request_list.get_column (get_col_pos ("Notes")).sort_column_id        = Column.NOTES;

            var visible_columns = this.visible_columns ();
            foreach (var col in request_list.get_columns ()) {
                if (col.title == "GUID") {
                    continue;
                }

                if (col.title == "Payloads" && scan_ids.length == 0) {
                    continue;
                }

                var visible = (!visible_columns.has_key (col.title)) || visible_columns[col.title];
                col.visible = visible;
            }

            box_request_details = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            request_details = new RequestDetails (application_window);
            request_details.hide ();
            box_request_details.add (request_details);

            request_compare = new RequestCompare (application_window);
            request_compare.hide ();
            box_request_details.add (request_compare);

            request_list.columns_changed.connect (save_column_settings);

            this.add2 (box_request_details);
            
            scrolled_window_requests.hide ();

            if (scan_ids.length != 0 && !initial_launch) {
                get_requests ();
            }

            var selection = request_list.get_selection();
            selection.mode = Gtk.SelectionMode.MULTIPLE;
            selection.changed.connect(this.on_selection_changed);
        }

        private void add_request_to_table (Json.Object request) {
            var url = request.get_string_member("URL");

            if (url_filter != "" && !url.contains(url_filter)) {
                return;
            }

            var guid = request.get_string_member ("GUID");

            Gtk.TreeIter iter;
            liststore.insert_with_values (out iter, -1,
                Column.GUID,                    guid,
                Column.PROTOCOL,                request.get_string_member ("Protocol"),
                Column.TIME,                    request.get_int_member ("Time"),
                Column.URL,                     request.get_string_member ("URL"),
                Column.RESPONSE_CONTENT_LENGTH, request.get_int_member ("ResponseContentLength"),
                Column.RESPONSE_CONTENT_TYPE, request.get_string_member ("ResponseContentType"),
                Column.DURATION,                request.get_int_member ("ResponseTime"),
                Column.VERB,                    request.get_string_member ("Verb"),
                Column.STATUS,                  request.get_int_member ("ResponseStatusCode"),
                Column.PAYLOADS,                request.get_string_member ("Payloads"),
                Column.ERROR,                   request.get_string_member ("Error"),
                Column.NOTES,                   request.get_string_member ("Notes")
            );

            guid_set.add (guid);

            if (label_no_requests.visible || placeholder_requests.visible) {
                show_controls (1);
            }
        }

        private void display_header_right_click_menu (Gdk.EventButton event) {
            var menu = new Gtk.Menu ();

            request_list.get_columns ().foreach ((col) => {
                if (col.title == "GUID") {
                    return;
                }

                if (col.title == "Payloads" && scan_ids.length == 0) {
                    return;
                }
                
                var menu_item = new Gtk.CheckMenuItem.with_label (col.title);
                menu_item.active = col.visible;
                menu_item.show ();
                menu_item.toggled.connect (() => {
                    col.visible = menu_item.active;
                    request_list.columns_autosize ();
                    save_column_settings ();
                });

                menu.append (menu_item);
            });
            
            menu.popup_at_pointer (event);
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
            liststore.clear ();
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

        private string[] get_selected_fields (Column col) {
            var selection = request_list.get_selection ();
            Gtk.TreeModel model;
            string[] vals = {};

            var selected_rows = selection.get_selected_rows (out model);
            foreach (var path in selected_rows) {
                Gtk.TreeIter iter;

                if (!model.get_iter (out iter, path)) {
                    continue;
                }

                GLib.Value val;
                model.get_value (iter, (int) col, out val);

                vals += val.get_string ();
            }

            return vals;
        }

        private string[] get_selected_guids () {
            return get_selected_fields (Column.GUID);
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
                    liststore.@foreach ((model, path, iter) => {
                        Value guid;
                        model.get_value (iter, Column.GUID, out guid);

                        if (request_guid == guid.get_string ()) {
                            liststore.remove (ref iter);
                            guid_set.remove (request_guid);
                            return true;
                        }

                        return false; // continue iterating
                    });
                }

                return;
            }

            if (!guid_set.contains (request_guid)) {
                add_request_to_table (request);
            } else {
                // if it already exists in the table, update it
                liststore.@foreach ((model, path, iter) => {
                    Value guid;
                    model.get_value (iter, Column.GUID, out guid);

                    if (request_guid == guid.get_string ()) {
                        liststore.set_value (iter, Column.TIME,          request.get_int_member("Time"));
                        liststore.set_value (iter, Column.URL,           request.get_string_member("URL"));
                        liststore.set_value (iter, Column.RESPONSE_CONTENT_LENGTH, request.get_int_member("ResponseContentLength"));
                        liststore.set_value (iter, Column.RESPONSE_CONTENT_TYPE, request.get_string_member("ResponseContentType"));
                        liststore.set_value (iter, Column.DURATION,      request.get_int_member("ResponseTime"));
                        liststore.set_value (iter, Column.VERB,          request.get_string_member("Verb"));
                        liststore.set_value (iter, Column.STATUS,        request.get_int_member("ResponseStatusCode"));
                        liststore.set_value (iter, Column.PAYLOADS,      request.get_string_member("Payloads"));
                        liststore.set_value (iter, Column.ERROR,         request.get_string_member("Error"));
                        liststore.set_value (iter, Column.NOTES,         request.get_string_member("Notes"));

                        return true;
                    }

                    return false; // continue iterating
                });
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

        private void on_notes_updated (string path, string newtext) {
            Gtk.TreeIter iter;
            liststore.get_iter (out iter, new Gtk.TreePath.from_string(path));

            Value guid;
            liststore.get_value (iter, Column.GUID, out guid);

            var message = new Soup.Message ("PATCH", "http://" + application_window.core_address + "/requests/" + guid.get_string () + "/notes");

            var parameters = "notes=" + GLib.Uri.escape_string (newtext, null);
            message.set_request_body_from_bytes ("application/x-www-form-urlencoded", new Bytes(parameters.data));
            
            application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);

            liststore.set_value (iter, Column.NOTES, newtext);
            guid.unset ();
        }

        [GtkCallback]
        public bool on_request_list_button_press_event (Gdk.EventButton event) {         
            if (event.type == Gdk.EventType.@2BUTTON_PRESS) {
                var guids = get_selected_guids ();
                if (guids.length != 1) {
                    return false;
                }
                var guid = guids[0];

                var protocols = get_selected_fields (Column.PROTOCOL);
                if (protocols.length != 1) {
                    return false;
                }

                var is_http = protocols[0].contains("HTTP");
                
                this.request_double_clicked (guid);
                
                if (process_actions) {
                    application_window.request_double_clicked (guid, is_http);
                }
            }

            return false; // allow other event handlers to be processed as well
        }
         
        [GtkCallback]
        public bool on_request_list_button_release_event (Gdk.EventButton event) {
            if (event.type != Gdk.EventType.BUTTON_RELEASE || event.button != 3) {
                return false;
            }

            // if the event was on top of the header....
            var first_column = request_list.get_column (1);
            var is_header = false;
            if (first_column != null) {
                int x, y, w, h;
                first_column.cell_get_size (null, out x, out y, out w, out h);
                if (event.y < h) {
                    is_header = true;
                }
            }

            if (is_header) {
                display_header_right_click_menu (event);
                return false;
            }
            
            if (process_actions) {
                // right click
                var menu = new Gtk.Menu ();

                var protocols = get_selected_fields (Column.PROTOCOL);
                if (protocols.length != 1) {
                    return false;
                }

                var is_http = protocols[0].contains("HTTP");
                
                var guids = get_selected_guids ();
                if (guids.length != 1 || guids[0] == "") {
                    return false;
                }
                var guid = guids[0];
            
                var new_window = new Gtk.MenuItem.with_label ("New Window");
                new_window.activate.connect ( () => {
                    var win = new RequestWindow (application_window, guid);
                    win.show ();
                });
                new_window.show ();
                menu.append (new_window);
                
                var item_new_request = new Gtk.MenuItem.with_label ("New Request");
                item_new_request.sensitive = is_http;
                item_new_request.activate.connect ( () => {
                    application_window.send_to_new_request (guid);
                });
                item_new_request.show ();
                menu.append (item_new_request);
    
                var item_inject = new Gtk.MenuItem.with_label ("Inject");
                item_inject.sensitive = is_http;
                item_inject.activate.connect ( () => {
                    application_window.send_to_inject (guid);
                });
                item_inject.show ();
                menu.append (item_inject);

                var copy_url = new Gtk.MenuItem.with_label ("Copy URL");
                copy_url.activate.connect ( () => {
                    var urls = get_selected_fields (Column.URL);
                    if (urls.length != 1 || urls[0] == "") {
                        return;
                    }

                    var url = urls[0];
                    Gdk.Display display = Gdk.Display.get_default ();
                    Gtk.Clipboard clipboard = Gtk.Clipboard.get_for_display (display, Gdk.SELECTION_CLIPBOARD);
                    clipboard.set_text (url, url.length);
                });
                copy_url.show ();
                menu.append (copy_url);

                var open_browser_inject = new Gtk.MenuItem.with_label ("Open in Browser");
                open_browser_inject.sensitive = is_http;
                open_browser_inject.activate.connect ( () => {
                    var urls = get_selected_fields (Column.URL);
                    if (urls.length != 1 || urls[0] == "") {
                        return;
                    }

                    var url = urls[0];
                    try {
                        AppInfo.launch_default_for_uri (url, null);
                    } catch (Error err) {
                        stdout.printf ("Could not launch browser: %s\n", err.message);
                    }
                });
                open_browser_inject.show ();
                menu.append (open_browser_inject);

                menu.popup_at_pointer (event);
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

        private void on_selection_changed (Gtk.TreeSelection selection) {
            if(updating) {
                return;
            }

            var guids = get_selected_guids ();
            
            if (guids.length == 0) {
                return;
            }
            
            if (guids.length == 1 && guids[0] != "") {
                var guid = guids[0];

                var pos = this.position;
                request_details.set_request (guid);
                this.position = pos;
                
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

        private string payloads_to_string (string str) {
            if (str == "") {
                return "";
            }

            var parser = new Json.Parser ();
            
            try {
                parser.load_from_data (str, -1);
                var payload_str = "";

                var payload_parts = parser.get_root ().get_object ();
                payload_parts.foreach_member ((obj, name, val) => {
                    var str_val = val.get_string ();
                    if (str_val != null) {
                        if (payload_str != "") {
                            payload_str += ", ";
                        }

                        payload_str += name + ": " + str_val;
                    }
                });

                return payload_str;
            }
            catch(Error e) {
                stdout.printf ("Could not parse JSON payload data, error: %s\nData: %s\n", e.message, str);
                return "";
            }
        }

        private string response_duration (int64 duration) {
            if (duration == 0) {
                return "";
            }

            if (duration > 5000) {
                return ((float)(duration/1000.0)).to_string ("%.2f s");
            }
            
            return duration.to_string () + " ms";
        }

        private string response_size_to_string (int64 response_size) {
            if (response_size == 0) {
                return "";
            }

            var bytes = (float)response_size;
            if (bytes < 1024) {
                return bytes.to_string() + " B";
            }

            bytes = bytes / (float)1024.0;
            if (bytes < 1024) {
                return bytes.to_string("%.2f KB");
            }

            bytes = bytes / (float)1024.0;
            if (bytes < 1024) {
                return bytes.to_string("%.2f MB");
            }

            bytes = bytes / (float)1024.0;
            if (bytes < 1024) {
                return bytes.to_string("%.2f GB");
            }

            return "";
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
            if (request_list.get_columns ().length () != COLUMN_COUNT) {
                return;
            }
            var settings = "";
            request_list.get_columns ().foreach ((col) => {
                if (settings != "") {
                    settings += ";";
                }
                settings += col.title + ":" + (col.visible ? "1" : "0");
            });

            application_window.settings.set_string (scan_ids.length == 0 ? "grid-columns" : "scan-grid-columns", settings);
        }

        private void scroll_to_bottom () {
            request_list.vadjustment.value = request_list.vadjustment.upper;
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
