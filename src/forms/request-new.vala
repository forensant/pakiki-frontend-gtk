using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-new.ui")]
    class RequestNew : Gtk.Paned {

        [GtkChild]
        private unowned Gtk.ComboBox combobox_protocol;
        [GtkChild]
        private unowned Gtk.Entry entry_hostname;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_host;
        [GtkChild]
        private unowned Gtk.Label label_request;
        [GtkChild]
        private unowned Gtk.Spinner spinner;
        [GtkChild]
        private unowned Gtk.TextView text_view_request;

        private RequestDetails request_details;

        public RequestNew (ApplicationWindow application_window) {
            var renderer_text = new Gtk.CellRendererText();
            combobox_protocol.pack_start (renderer_text, true);
            combobox_protocol.add_attribute (renderer_text, "text", 0);
            combobox_protocol.set_active (0);

            label_host.set_text_with_mnemonic ("_Host");
            label_host.mnemonic_widget = combobox_protocol;

            label_request.set_text_with_mnemonic ("_Request");
            label_request.mnemonic_widget = text_view_request;

            request_details = new RequestDetails (application_window);
            this.add2 (request_details);
        }

        public void populate_request (string guid) {
            var url = "http://localhost:10101/project/request?guid=" + guid;

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
                    text_view_request.buffer.set_text (requestData);
                    request_details.reset_state ();
                    
                } catch (Error err) {
                    stdout.printf ("Error retrieving/populating request: %s\n", err.message);
                }
            });
        }

        [GtkCallback]
        public void on_send_clicked () {
            spinner.start ();
            label_error.visible = false;
            var session = new Soup.Session ();
            var message = new Soup.Message ("POST", "http://127.0.0.1:10101/proxy/make_request");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("host");
            builder.add_string_value (entry_hostname.get_text ());
            builder.set_member_name ("ssl");
            builder.add_boolean_value (combobox_protocol.get_active() == 0);
            builder.set_member_name ("request");
            builder.add_string_value (Base64.encode (text_view_request.buffer.text.data));
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

        public void reset_state () {
            combobox_protocol.set_active (0);
            entry_hostname.set_text ("");
            spinner.stop ();
            spinner.hide ();
            text_view_request.buffer.set_text ("");
            label_error.visible = false;
            request_details.reset_state ();
        }
    }
}
