using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-new.ui")]
    class RequestNew : Gtk.Paned, MainApplicationPane {

        [GtkChild]
        private unowned Gtk.ComboBox combobox_protocol;
        [GtkChild]
        private unowned Gtk.Entry entry_hostname;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_request;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_text_view_request;
        [GtkChild]
        private unowned Gtk.Spinner spinner;

        private ApplicationWindow application_window;
        private RequestDetails request_details;
        private RequestTextEditor request_text_editor;

        public RequestNew (ApplicationWindow application_window) {
            this.application_window = application_window;
            var renderer_text = new Gtk.CellRendererText();
            combobox_protocol.pack_start (renderer_text, true);
            combobox_protocol.add_attribute (renderer_text, "text", 0);
            combobox_protocol.set_active (0);

            request_text_editor = new RequestTextEditor (application_window);
            scrolled_window_text_view_request.add (request_text_editor);
            request_text_editor.long_running_task.connect ( (running) => {
                if (running) {
                    spinner.start ();
                } else {
                    spinner.stop ();
                }
            });

            label_request.set_text_with_mnemonic ("_Request");
            label_request.mnemonic_widget = request_text_editor;

            request_details = new RequestDetails (application_window);
            this.add2 (request_details);
        }

        public bool back_visible () {
            return true;
        }

        public bool can_search () {
            return false;
        }

        public void on_back_clicked () {
            application_window.change_pane ("RequestList");
        }

        [GtkCallback]
        public void on_send_clicked () {
            spinner.start ();
            label_error.visible = false;
            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://" + application_window.core_address + "/proxy/make_request");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("host");
            builder.add_string_value (entry_hostname.get_text ());
            builder.set_member_name ("ssl");
            builder.add_boolean_value (combobox_protocol.get_active() == 0);
            builder.set_member_name ("request");
            builder.add_string_value (Base64.encode (request_text_editor.buffer.text.data));
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request("application/json", Soup.MemoryUse.COPY, parameters.data);
            
            session.queue_message (message, (sess, mess) => {
                if (mess.status_code != 200) {
                    label_error.visible = true;
                    label_error.label = (string)mess.response_body.flatten().data;
                    spinner.stop();
                    return;
                }

                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    parser.load_from_data (jsonData, -1);

                    var rootObj = parser.get_root().get_object();
                    
                    var guid = rootObj.get_string_member("GUID");
                    request_details.set_request (guid);

                }
                catch(Error e) {
                    stdout.printf("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                }

                spinner.stop ();
            });
        }

        public void populate_request (string guid) {
            var url = "http://" + application_window.core_address + "/project/request?guid=" + guid;

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();

                try {
                    parser.load_from_data ((string) message.response_body.flatten ().data, -1);

                    var rootObj = parser.get_root().get_object();

                    var requestData = (string) Base64.decode (rootObj.get_string_member ("RequestData"));

                    entry_hostname.set_text (rootObj.get_string_member ("Hostname"));
                    combobox_protocol.set_active (rootObj.get_string_member ("Protocol") == "https://" ? 0 : 1);
                    request_text_editor.buffer.set_text (requestData);
                    request_details.reset_state ();
                    
                } catch (Error err) {
                    stdout.printf ("Error retrieving/populating request: %s\n", err.message);
                }
            });
        }

        public void reset_state () {
            combobox_protocol.set_active (0);
            entry_hostname.set_text ("");
            spinner.stop ();
            spinner.hide ();
            request_text_editor.buffer.set_text ("");
            label_error.visible = false;
            request_details.reset_state ();
        }
    }
}
