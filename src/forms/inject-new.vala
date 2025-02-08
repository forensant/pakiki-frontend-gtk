using Soup;

namespace Pakiki {
    
    class InjectNew : Gtk.Box {

        private ApplicationWindow application_window;
        private Gtk.Button button_run;
        private InjectPane inject_pane;
        private InjectPointSelectionWidget inject_point_selection_widget;
        private Gtk.Label label_error;
        private PayloadSelectionWidget payload_selection_widget;
        private Gtk.Spinner spinner;

        public InjectNew (ApplicationWindow application_window, InjectPane inject_pane) {
            this.application_window = application_window;
            this.inject_pane = inject_pane;

            this.orientation = Gtk.Orientation.VERTICAL;

            this.margin_start = 18;
            this.margin_end = 18;
            this.margin_top = 18;
            this.margin_bottom = 18;

            inject_point_selection_widget = new InjectPointSelectionWidget (application_window);
            this.append (inject_point_selection_widget);

            payload_selection_widget = new PayloadSelectionWidget (application_window, true);
            payload_selection_widget.margin_top = 12;
            this.append (payload_selection_widget);
            payload_selection_widget.show ();

            button_run = new Gtk.Button ();
            button_run.label = "_Run";
            button_run.use_underline = true;
            button_run.clicked.connect (on_run_clicked);
            button_run.show ();

            label_error = new Gtk.Label ("");
            label_error.halign = Gtk.Align.START;
            label_error.hexpand = true;

            spinner = new Gtk.Spinner ();
            spinner.margin_end = 12;
            spinner.show ();
            
            var box_bottom = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box_bottom.margin_top = 12;
            box_bottom.append (label_error);
            box_bottom.append (spinner);
            box_bottom.append (button_run);
            
            box_bottom.show ();

            this.append (box_bottom);
        }

        public void clone_inject_operation (InjectOperation operation) {
            inject_point_selection_widget.clone_inject_operation (operation);
            payload_selection_widget.clone_inject_operation (operation);
        }

        private void get_custom_files (Json.Builder builder) {
            builder.set_member_name ("customPayloads");
            builder.begin_array ();

            foreach (string payload in payload_selection_widget.custom_file_payloads) {
                builder.add_string_value (payload);
            }
            
            builder.end_array ();

            builder.set_member_name ("customFilenames");
            builder.begin_array ();

            foreach (string filename in payload_selection_widget.custom_filenames) {
                builder.add_string_value (filename);
            }
            
            builder.end_array ();
        }

        private void get_selected_filenames (Json.Builder builder) {
            builder.begin_array ();

            foreach (string filename in payload_selection_widget.fuzzdb_files) {
                builder.add_string_value (filename);
            }

            builder.end_array ();
        }

        public void on_run_clicked () {
            if (inject_point_selection_widget.hostname == "") {
                inject_point_selection_widget.host_error_visible = true;
                return;
            }
            else {
                inject_point_selection_widget.host_error_visible = false;
            }
            
            var message = new Soup.Message ("POST", "http://" + application_window.core_address + "/inject_operations/run");

            button_run.sensitive = false;
            spinner.spinning = true;

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("host");
            builder.add_string_value (inject_point_selection_widget.hostname);
            builder.set_member_name ("ssl");
            builder.add_boolean_value (inject_point_selection_widget.ssl);
            builder.set_member_name ("request");
            inject_point_selection_widget.get_request_json (builder);
            builder.set_member_name ("Title");
            builder.add_string_value (inject_point_selection_widget.title);
            builder.set_member_name ("iterateFrom");
            builder.add_int_value (payload_selection_widget.iterate_from);
            builder.set_member_name ("iterateTo");
            builder.add_int_value (payload_selection_widget.iterate_to);
            builder.set_member_name ("fuzzDB");
            get_selected_filenames (builder);
            get_custom_files (builder);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request_body_from_bytes ("application/json", new Bytes (parameters.data));

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_and_read_async.end (res);
                    var response_data = (string) response.get_data ();
                    
                    if (message.status_code != 200) {
                        label_error.label = "Error: " + response_data;
                        label_error.visible = true;
                        button_run.sensitive = true;
                        spinner.spinning = false;
                        return;
                    } else {
                        label_error.visible = false;
                    }
    
                    var parser = new Json.Parser ();
                    
                    parser.load_from_data (response_data, -1);
                    var rootObj = parser.get_root().get_object();
                    
                    var guid = rootObj.get_string_member("GUID");
                    reset_state ();

                    inject_pane.select_when_received (guid);
                }
                catch(Error e) {
                    stdout.printf("Could not parse JSON data, error: %s\n", e.message);
                }

                button_run.sensitive = true;
                spinner.spinning = false;
            });

        }

        public void populate_request (string guid) {
            inject_point_selection_widget.populate_request (guid);
        }

        public void reset_state () {
            spinner.spinning = false;
            button_run.sensitive = true;
            inject_point_selection_widget.reset_state ();
            payload_selection_widget.reset_state ();
        }
    }
}
