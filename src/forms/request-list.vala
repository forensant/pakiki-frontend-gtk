using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-list.ui")]
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
        private unowned Gtk.TreeView request_list;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_requests;
        [GtkChild]
        private unowned Gtk.Spinner spinner;

        private ApplicationWindow application_window;
        private bool exclude_resources;
        private Gee.Set<string> guid_set;
        private PlaceholderRequests placeholder_requests;
        private RequestDetails request_details;
        private string[] scan_ids;
        private string search_protocol;
        private string search_query;
        private bool updating;
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
            RESPONSE_SIZE,
            DURATION,
            VERB,
            STATUS,
            PAYLOADS,
            ERROR,
            NOTES
        }
        
        public RequestList (ApplicationWindow application_window, string[] scan_ids = {}) {
            this.application_window = application_window;
            this.scan_ids = scan_ids;
            this.exclude_resources = true;
            this.updating = false;
            this.placeholder_requests = new PlaceholderRequests (application_window);
            this.search_protocol = "";
            this.search_query = "";
            this.url_filter = "";
            this._process_actions = true;
            guid_set = new Gee.TreeSet<string> ();

            this.box.add (placeholder_requests);

            var url_renderer = new Gtk.CellRendererText();
            url_renderer.ellipsize = Pango.EllipsizeMode.END;
            url_renderer.ellipsize_set = true;

            var time_cell_renderer = new Gtk.CellRendererText();
            time_cell_renderer.ellipsize = Pango.EllipsizeMode.MIDDLE;
            time_cell_renderer.ellipsize_set = true;

            var response_size_renderer = new Gtk.CellRendererText();
            var duration_renderer      = new Gtk.CellRendererText();
            var status_renderer        = new Gtk.CellRendererText();

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
            request_list.insert_column_with_attributes (-1, "GUID",
                                                    new Gtk.CellRendererText(),
                                                    "text", Column.GUID);

            request_list.insert_column_with_attributes (-1, "Protocol",
                                                    new Gtk.CellRendererText(),
                                                    "text", Column.PROTOCOL);

            request_list.insert_column_with_attributes (-1, "Time",
                                                    time_cell_renderer,
                                                    "text", Column.TIME);

            request_list.insert_column_with_attributes (-1, "URL",
                                                    url_renderer,
                                                    "text", Column.URL);

            request_list.insert_column_with_attributes (-1, "Size",
                                                    response_size_renderer,
                                                    "text", Column.RESPONSE_SIZE);

            request_list.insert_column_with_attributes (-1, "Duration",
                                                    duration_renderer,
                                                    "text", Column.DURATION);

            request_list.insert_column_with_attributes (-1, "Verb",
                                                    new Gtk.CellRendererText (),
                                                    "text", Column.VERB);

            request_list.insert_column_with_attributes (-1, "Status",
                                                    status_renderer,
                                                    "text", Column.STATUS);

            request_list.insert_column_with_attributes (-1, "Payloads",
                                                    payload_renderer,
                                                    "text", Column.PAYLOADS);

            request_list.insert_column_with_attributes (-1, "Error",
                                                    error_renderer,
                                                    "text", Column.ERROR);

            request_list.insert_column_with_attributes (-1, "Notes",
                                                    notes_renderer,
                                                    "text", Column.NOTES);

            
            var guid_column = request_list.get_column(Column.GUID);
            guid_column.visible = false;

            var protocol_column = request_list.get_column(Column.PROTOCOL);
            protocol_column.visible = false;

            var url_column = request_list.get_column(Column.URL);
            url_column.expand = true;
            url_column.min_width = 200;

            var time_column = request_list.get_column(Column.TIME);
            time_column.set_cell_data_func(time_cell_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.TIME, out val);
                ((Gtk.CellRendererText)cell).text = response_time(new DateTime.from_unix_local(val.get_int()));
                val.unset();
            });
            time_column.min_width = 100;

            var response_size_column = request_list.get_column(Column.RESPONSE_SIZE);
            response_size_column.set_cell_data_func(response_size_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.RESPONSE_SIZE, out val);
                ((Gtk.CellRendererText)cell).text = response_size_to_string(val.get_int ());
                val.unset();
            });

            var duration_column = request_list.get_column(Column.DURATION);
            duration_column.set_cell_data_func(duration_renderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.DURATION, out val);
                ((Gtk.CellRendererText)cell).text = response_duration(val.get_int ());
                val.unset();
            });

            var status_column = request_list.get_column(Column.STATUS);
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

            var payload_column = request_list.get_column(Column.PAYLOADS);
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

            request_list.get_column(Column.TIME).sort_column_id          = Column.TIME;
            request_list.get_column(Column.URL).sort_column_id           = Column.URL;
            request_list.get_column(Column.RESPONSE_SIZE).sort_column_id = Column.RESPONSE_SIZE;
            request_list.get_column(Column.DURATION).sort_column_id      = Column.DURATION;
            request_list.get_column(Column.VERB).sort_column_id          = Column.VERB;
            request_list.get_column(Column.STATUS).sort_column_id        = Column.STATUS;
            request_list.get_column(Column.PAYLOADS).sort_column_id      = Column.PAYLOADS;
            request_list.get_column(Column.ERROR).sort_column_id         = Column.ERROR;
            request_list.get_column(Column.NOTES).sort_column_id         = Column.NOTES;

            request_details = new RequestDetails (application_window);
            request_details.hide ();
            this.add2 (request_details);
            
            scrolled_window_requests.hide ();

            if (scan_ids.length != 0) {
                get_requests ();
            }

            var selection = request_list.get_selection();
            selection.changed.connect(this.on_changed);
        }

        private void add_request_to_table (Json.Object request) {
            var url = request.get_string_member("URL");

            if (url_filter != "" && !url.contains(url_filter)) {
                return;
            }

            var guid = request.get_string_member ("GUID");

            Gtk.TreeIter iter;
            liststore.insert_with_values (out iter, -1,
                Column.GUID,          guid,
                Column.PROTOCOL,      request.get_string_member ("Protocol"),
                Column.TIME,          request.get_int_member ("Time"),
                Column.URL,           request.get_string_member ("URL"),
                Column.RESPONSE_SIZE, request.get_int_member ("ResponseSize"),
                Column.DURATION,      request.get_int_member ("ResponseTime"),
                Column.VERB,          request.get_string_member ("Verb"),
                Column.STATUS,        request.get_int_member ("ResponseStatusCode"),
                Column.PAYLOADS,      request.get_string_member ("Payloads"),
                Column.ERROR,         request.get_string_member ("Error"),
                Column.NOTES,         request.get_string_member ("Notes")
            );

            guid_set.add (guid);

            if (label_no_requests.visible || placeholder_requests.visible) {
                show_controls (1);
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
                request_details.hide ();
            } else {
                label_no_requests.visible = false;
                placeholder_requests.hide ();
                scrolled_window_requests.show ();
                request_details.show ();
                this.requests_loaded (true);
            }
        }

        private void get_requests () {
            label_no_requests.visible = false;
            this.updating = true;
            guid_set.clear ();
            request_details.reset_state ();
            liststore.clear ();
            this.updating = false;

            bool fetched_data = false;
            Timeout.add (200, () => {
                if (!fetched_data) {
                    spinner.active = true;
                }
                return GLib.Source.REMOVE;
            });

            var url = "http://" + application_window.core_address + "/project/requests?exclude_resources=" + (exclude_resources ? "true" : "false");

            if (search_query != null && search_query != "") {
                url += "&filter=" + Soup.URI.encode(search_query, null);
            }

            var scan_id = string.joinv (":", scan_ids);
            if (scan_id != "") {
                url += "&scanid=" + scan_id;
            }

            if (url_filter != "") {
                url += "&url_filter=" + Soup.URI.encode("://" + url_filter, null);
            }

            if (search_protocol != "" && search_protocol != "all") {
                url += "&protocol=" + search_protocol;
            }

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
                this.updating = true;
                fetched_data = true;
                liststore.clear ();
                spinner.active = false;
                var parser = new Json.Parser ();
                try {
                    if (message.status_code != 200) {
                        stderr.printf("Could not connect to %s\n", url);
                        return;
                    }

                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var rootArray = parser.get_root ().get_array ();

                    show_controls (rootArray.get_length ());

                    foreach (var reqElement in rootArray.get_elements ()) {
                        var request = reqElement.get_object ();
                        add_request_to_table (request);
                    }

                    // scroll to the bottom
                    request_list.vadjustment.value = request_list.vadjustment.upper;

                    this.requests_loaded (rootArray.get_length () > 0);

                } catch (Error err) {
                    stdout.printf ("Could not populate request list: %s\n", err.message);
                }

                this.updating = false;
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

            url = CoreProcess.websocket_url (application_window.core_address, "HTTP Request", notification_filters);
            string filter = "";
            if (exclude_resources) {
                filter += "exclude_resources:true";
            }

            if (search_query != null && search_query != "") {
                filter += Soup.URI.encode (" " + search_query, null);
            }

            if (filter != "") {
                url += "&filter=" + filter;
            }

            var wsmessage = new Soup.Message ("GET", url);
            session.websocket_connect_async.begin (wsmessage, "localhost", null, null, (obj, res) => {
                try {
                    websocket = session.websocket_connect_async.end (res);
                    websocket.message.connect (on_websocket_message);
                } catch (Error err) {
                    stdout.printf ("Error connecting to websocket %s, error message: %s\n", url, err.message);
                }
            });
        }

        private string get_selected_field (Column col) {
            var selection = request_list.get_selection ();
            Gtk.TreeModel model;
            Gtk.TreeIter iter;
            string val;
    
            if (selection.get_selected (out model, out iter)) {
                model.get (iter, col, out val);
                return val;
            }
            return "";
        }

        private string get_selected_guid () {
            return get_selected_field (Column.GUID);
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

            var scroll_to_bottom = ((request_list.vadjustment.value + request_list.vadjustment.page_size + 200.0) > request_list.vadjustment.upper);

            var request_guid = request.get_string_member ("GUID");

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
                        liststore.set_value (iter, Column.RESPONSE_SIZE, request.get_int_member("ResponseSize"));
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

            // if the websocket packets have been updated, let the request details form know to update the list
            if (request_details.guid == request_guid && request.get_string_member ("Protocol") == "Websocket") {
                request_details.set_request (request_guid, true);
            }

            // automatically scroll to the bottom if needed
            if(scroll_to_bottom) {
                request_list.vadjustment.value = request_list.vadjustment.upper;
            }
        }

        private void on_changed (Gtk.TreeSelection selection) {
            if(updating) {
                return;
            }

            var guid = get_selected_guid ();
            if (guid != "") {
                var pos = this.position;
                request_details.set_request (guid);
                this.position = pos;
                
                request_selected (guid);
            }
        }

        private void on_notes_updated (string path, string newtext) {
            Gtk.TreeIter iter;
            liststore.get_iter (out iter, new Gtk.TreePath.from_string(path));

            Value guid;
            liststore.get_value (iter, Column.GUID, out guid);

            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://" + application_window.core_address + "/project/request");

            var parameters = "guid=" + guid.get_string () + "&notes=" + Soup.URI.encode (newtext, null);
            message.set_request ("application/x-www-form-urlencoded", Soup.MemoryUse.COPY, parameters.data);
            
            session.send_async.begin (message);

            liststore.set_value (iter, Column.NOTES, newtext);
            guid.unset ();
        }

        public void on_search (string query, bool exclude_resources, string protocol = "") {
            this.search_query = query;
            this.exclude_resources = exclude_resources;
            this.search_protocol = protocol;
            get_requests ();
        }

        [GtkCallback]
        public bool on_request_list_button_press_event (Gdk.EventButton event) {         
            if (event.type == Gdk.EventType.@2BUTTON_PRESS) {
                var guid = get_selected_guid ();
                if (guid == "") {
                    return false;
                }

                var protocol = get_selected_field (Column.PROTOCOL);
                if (protocol != "HTTP/1.1") {
                    return false;
                }

                this.request_double_clicked (guid);
                
                if (process_actions) {
                    application_window.request_double_clicked (guid);
                }
            }

            return false; // allow other event handlers to be processed as well
         }
         
        [GtkCallback]
        public bool on_request_list_button_release_event (Gdk.EventButton event) {
            if (event.type == Gdk.EventType.BUTTON_RELEASE && event.button == 3 && process_actions) {
                // right click
                var menu = new Gtk.Menu ();

                var protocol = get_selected_field (Column.PROTOCOL);
                if (protocol != "HTTP/1.1") {
                    return false;
                }
            
                var item_new_request = new Gtk.MenuItem.with_label ("New Request");
                item_new_request.activate.connect ( () => {
                    var guid = get_selected_guid ();
                    if (guid != "") {
                        application_window.send_to_new_request (guid);
                    }
                });
                item_new_request.show ();
                menu.append (item_new_request);
    
                var item_inject = new Gtk.MenuItem.with_label ("Inject");
                item_inject.activate.connect ( () => {
                    var guid = get_selected_guid ();
                    if (guid != "") {
                        application_window.send_to_inject (guid);
                    }
                });
                item_inject.show ();
                menu.append (item_inject);

                var open_browser_inject = new Gtk.MenuItem.with_label ("Open in Browser");
                open_browser_inject.activate.connect ( () => {
                    var guid = get_selected_guid ();
                    var url = get_selected_field (Column.URL);
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

                menu.popup_at_pointer (event);
            }

            return false; // allow other event handlers to also be run
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
            get_requests ();
            request_details.reset_state ();
        }

        public void set_scan_ids (string[] guids) {
            this.scan_ids = guids;
            this.get_requests ();
        }

        public void set_url_filter (string url) {
            this.url_filter = url;
            this.get_requests ();
        }

        public void set_processed_launched (bool successful) {
            if (!successful) {
                placeholder_requests.set_error (application_window.core_address);
            } else {
                placeholder_requests.update_proxy_address ();
                get_requests();
            }
        }
    }
}
