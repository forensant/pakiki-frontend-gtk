using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-list.ui")]
    class RequestList : Gtk.Paned {

        public signal void requests_loaded (bool present);

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

        private ApplicationWindow application_window;
        private bool exclude_resources;
        private PlaceholderRequests placeholder_requests;
        private RequestDetails request_details;
        private string[] scan_ids;
        private string search_query;
        private bool updating;
        private string url_filter;
        private WebsocketConnection websocket;
        
        enum Column {
            GUID,
            TIME,
            URL,
            RESPONSE_SIZE,
            DURATION,
            VERB,
            STATUS,
            ERROR,
            NOTES
        }
        
        public RequestList (ApplicationWindow application_window, string[] scan_ids = {}) {
            this.application_window = application_window;
            this.scan_ids = scan_ids;
            this.exclude_resources = true;
            this.updating = false;
            this.placeholder_requests = new PlaceholderRequests (application_window);
            this.search_query = "";
            this.url_filter = "";

            this.box.add (placeholder_requests);

            var urlRenderer = new Gtk.CellRendererText();
            urlRenderer.ellipsize = Pango.EllipsizeMode.END;
            urlRenderer.ellipsize_set = true;

            var timeCellRenderer     = new Gtk.CellRendererText();
            var responseSizeRenderer = new Gtk.CellRendererText();
            var durationRenderer     = new Gtk.CellRendererText();

            var errorRenderer = new Gtk.CellRendererText();
            errorRenderer.ellipsize = Pango.EllipsizeMode.END;
            errorRenderer.ellipsize_set = true;

            var notesRenderer = new Gtk.CellRendererText();
            notesRenderer.ellipsize = Pango.EllipsizeMode.END;
            notesRenderer.ellipsize_set = true;
            notesRenderer.editable = true;
            notesRenderer.edited.connect(on_notes_updated);

            /*columns*/
            request_list.insert_column_with_attributes (-1, "GUID",
                                                    new Gtk.CellRendererText(), "text",
                                                    Column.GUID);

            request_list.insert_column_with_attributes (-1, "Time",
                                                    timeCellRenderer,
                                                    "text", Column.TIME);

            request_list.insert_column_with_attributes (-1, "URL",
                                                    urlRenderer,
                                                    "text", Column.URL);

            request_list.insert_column_with_attributes (-1, "Size",
                                                    responseSizeRenderer,
                                                    "text", Column.RESPONSE_SIZE);

            request_list.insert_column_with_attributes (-1, "Duration",
                                                    durationRenderer,
                                                    "text", Column.DURATION);

            request_list.insert_column_with_attributes (-1, "Verb",
                                                    new Gtk.CellRendererText (),
                                                    "text", Column.VERB);

            request_list.insert_column_with_attributes (-1, "Status",
                                                    new Gtk.CellRendererText (),
                                                    "text", Column.STATUS);

            request_list.insert_column_with_attributes (-1, "Error",
                                                    errorRenderer,
                                                    "text", Column.ERROR);

            request_list.insert_column_with_attributes (-1, "Notes",
                                                    notesRenderer,
                                                    "text", Column.NOTES);

            
            var guidColumn = request_list.get_column(Column.GUID);
            guidColumn.visible = false;

            var urlColumn = request_list.get_column(Column.URL);
            urlColumn.set_expand(true);

            var timeColumn = request_list.get_column(Column.TIME);
            timeColumn.set_cell_data_func(timeCellRenderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.TIME, out val);
                ((Gtk.CellRendererText)cell).text = response_time(new DateTime.from_unix_local(val.get_int()));
                val.unset();
            });

            var responseSizeColumn = request_list.get_column(Column.RESPONSE_SIZE);
            responseSizeColumn.set_cell_data_func(responseSizeRenderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.RESPONSE_SIZE, out val);
                ((Gtk.CellRendererText)cell).text = response_size_to_string(val.get_int());
                val.unset();
            });

            var durationColumn = request_list.get_column(Column.DURATION);
            durationColumn.set_cell_data_func(durationRenderer, (cell_layout, cell, tree_model, iter) => {
                Value val;
                tree_model.get_value(iter, Column.DURATION, out val);
                ((Gtk.CellRendererText)cell).text = response_duration(val.get_int());
                val.unset();
            });

            request_list.get_column(Column.TIME).sort_column_id          = Column.TIME;
            request_list.get_column(Column.URL).sort_column_id           = Column.URL;
            request_list.get_column(Column.RESPONSE_SIZE).sort_column_id = Column.RESPONSE_SIZE;
            request_list.get_column(Column.DURATION).sort_column_id      = Column.DURATION;
            request_list.get_column(Column.VERB).sort_column_id          = Column.VERB;
            request_list.get_column(Column.STATUS).sort_column_id        = Column.STATUS;
            request_list.get_column(Column.ERROR).sort_column_id         = Column.ERROR;
            request_list.get_column(Column.NOTES).sort_column_id         = Column.NOTES;

            request_details = new RequestDetails (application_window);
            request_details.hide ();
            this.add2 (request_details);
            get_requests();

            scrolled_window_requests.hide ();

            var selection = request_list.get_selection();
            selection.changed.connect(this.on_changed);
        }

        private void add_request_to_table (Json.Object request) {
            var url = request.get_string_member("URL");

            if (url_filter != "" && !url.contains(url_filter)) {
                return;
            }

            Gtk.TreeIter iter;
            liststore.insert_with_values (out iter, -1,
                Column.GUID,          request.get_string_member ("GUID"),
                Column.TIME,          request.get_int_member ("Time"),
                Column.URL,           request.get_string_member ("URL"),
                Column.RESPONSE_SIZE, request.get_int_member ("ResponseSize"),
                Column.DURATION,      request.get_int_member ("ResponseTime"),
                Column.VERB,          request.get_string_member ("Verb"),
                Column.STATUS,        request.get_int_member ("ResponseStatusCode"),
                Column.ERROR,         request.get_string_member ("Error"),
                Column.NOTES,         request.get_string_member ("Notes")
            );

            if (label_no_requests.visible || placeholder_requests.visible) {
                show_controls (1);
            }
        }

        private void show_controls (uint request_count) {
            if (request_count == 0 && scan_ids.length == 0) {
                if (search_query != "" || url_filter != "") {
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
            }
        }

        private void get_requests () {
            label_no_requests.visible = false;
            var url = "http://localhost:10101/project/requests?exclude_resources=" + (exclude_resources ? "true" : "false");

            if (search_query != null && search_query != "") {
                url += "&filter=" + Soup.URI.encode(search_query, null);
            }

            var scan_id = string.joinv (";", scan_ids);
            if (scan_id != "") {
                url += "&scanid=" + scan_id;
            }

            if (url_filter != "") {
                url += "&url_filter=" + Soup.URI.encode("://" + url_filter, null);
            }

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
                liststore.clear ();
                this.updating = true;
                var parser = new Json.Parser ();
                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var rootArray = parser.get_root ().get_array ();

                    show_controls (rootArray.get_length ());

                    foreach (var reqElement in rootArray.get_elements ()) {
                        var request = reqElement.get_object ();
                        add_request_to_table (request);
                    }

                    this.requests_loaded (rootArray.get_length () > 0);

                } catch (Error err) {
                    stdout.printf ("Could not populate request list: %s\n", err.message);
                }

                this.updating = false;
            });

            if (websocket != null && websocket.state == Soup.WebsocketState.OPEN) {
                websocket.close (Soup.WebsocketCloseCode.NO_STATUS, null);
            }

            url = "http://127.0.0.1:10101/project/notifications";
            string filter = "";
            if (exclude_resources) {
                filter += "exclude_resources:true";
            }

            if (search_query != null && search_query != "") {
                filter += Soup.URI.encode (" " + search_query, null);
            }

            if (filter != "") {
                url += "?filter=" + filter;
            }

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

        private string get_selected_guid () {
            var selection = request_list.get_selection ();
            Gtk.TreeModel model;
            Gtk.TreeIter iter;
            string guid;
    
            if (selection.get_selected (out model, out iter)) {
                model.get (iter, Column.GUID, out guid);
                return guid;
            }
            return "";
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
                
            if (request.get_string_member ("ObjectType") != "HTTP Request") {
                return;
            }

            var scan_id = request.get_string_member ("ScanID");
            var scan_id_found = false;

            for (int i = 0; i < scan_ids.length; i++) {
                if (scan_ids[i] == scan_id) {
                    scan_id_found = true;
                    break;
                }
            }

            if (scan_id_found == false && scan_ids.length != 0) {
                return;
            }

            var scroll_to_bottom = ((request_list.vadjustment.value + request_list.vadjustment.page_size + 200.0) > request_list.vadjustment.upper);

            var found = false;
            var request_guid = request.get_string_member ("GUID");

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
                    liststore.set_value (iter, Column.ERROR,         request.get_string_member("Error"));
                    liststore.set_value (iter, Column.NOTES,         request.get_string_member("Notes"));

                    found = true;
                    return true;
                }

                return false; // continue iterating
            });

            if(found == false) {
                add_request_to_table (request);
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
                request_details.set_request (guid);
            }
        }

        private void on_notes_updated (string path, string newtext) {
            Gtk.TreeIter iter;
            liststore.get_iter (out iter, new Gtk.TreePath.from_string(path));

            Value guid;
            liststore.get_value (iter, Column.GUID, out guid);

            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://127.0.0.1:10101/project/update_request");

            var parameters = "guid=" + guid.get_string () + "&notes=" + Soup.URI.encode (newtext, null);
            message.set_request ("application/x-www-form-urlencoded", Soup.MemoryUse.COPY, parameters.data);
            
            session.send_async.begin (message);

            liststore.set_value (iter, Column.NOTES, newtext);
            guid.unset ();
        }

        public void on_search (string query, bool exclude_resources) {
            this.search_query = query;
            this.exclude_resources = exclude_resources;
            get_requests ();
        }

        [GtkCallback]
        public bool on_request_list_button_press (Gdk.EventButton event) {         
            if (event.type == Gdk.EventType.@2BUTTON_PRESS) {
                var guid = get_selected_guid ();
                application_window.request_double_clicked (guid);
            } else if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) {
                // right click

                var menu = new Gtk.Menu ();
            
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

                menu.popup_at_pointer (event);
            }

            return false; // allow other event handlers to also be run
        }

        private string response_duration (int64 duration) {
            if (duration > 5000) {
                return ((float)(duration/1000.0)).to_string ("%.2f s");
            }
            
            return duration.to_string () + " ms";
        }

        private string response_size_to_string (int64 responseSize) {
            var bytes = (float)responseSize;
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

        private string response_time (DateTime time) {
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
                placeholder_requests.set_error ();
            }
        }
    }
}
