using Soup;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/request-new.ui")]
    class RequestNew : Gtk.Box, MainApplicationPane {

        [GtkChild]
        private unowned Gtk.DropDown dropdown_protocol;
        [GtkChild]
        private unowned Gtk.Entry entry_hostname;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_request;
        [GtkChild]
        private unowned Gtk.Paned pane;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex_editor;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_text_view_request;
        [GtkChild]
        private unowned Gtk.Spinner spinner;

        private ApplicationWindow application_window;
        private HexEditor hex_editor;
        private RequestDetails request_details;
        private RequestTextEditor request_text_editor;

        public RequestNew (ApplicationWindow application_window) {
            this.application_window = application_window;
            dropdown_protocol.selected = 0;

            hex_editor = new HexEditor (application_window);
            hex_editor.show ();
            scrolled_window_hex_editor.set_child (hex_editor);

            request_text_editor = new RequestTextEditor (application_window);
            scrolled_window_text_view_request.set_child (request_text_editor);
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
            pane.set_end_child (request_details);

            reset_state ();
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

        public bool find_activated () {
            return request_details.find_activated ();
        }

        [GtkCallback]
        public void on_button_reset_clicked () {
            reset_state ();
        }

        [GtkCallback]
        public void on_send_clicked () {
            spinner.start ();
            label_error.label = "";
            var message = new Soup.Message ("POST", "http://" + application_window.core_address + "/requests/make");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("host");
            builder.add_string_value (entry_hostname.get_text ());
            builder.set_member_name ("ssl");
            builder.add_boolean_value (dropdown_protocol.selected == 0);
            builder.set_member_name ("request");
            if (scrolled_window_hex_editor.visible) {
                var buffer = (HexStaticBuffer) hex_editor.buffer;
                builder.add_string_value (Base64.encode (buffer.get_buffer ()));
            }
            else {
                builder.add_string_value (Base64.encode (request_text_editor.buffer.text.data));
            }
            
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request_body_from_bytes ("application/json", new Bytes (parameters.data ));
            
            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_and_read_async.end (res);
                    var str_resp = (string) response.get_data ();
                    if (message.status_code != 200) {
                        label_error.label = str_resp;
                        spinner.stop();
                        return;
                    }
    
                    var parser = new Json.Parser ();
                    parser.load_from_data (str_resp, -1);
                    
                    var rootObj = parser.get_root().get_object();    
                    var guid = rootObj.get_string_member("GUID");
                    request_details.set_request (guid);
                }
                catch (Error err) {
                    stdout.printf ("Error sending request: %s\n", err.message);
                    label_error.label = "Error sending request: " + err.message;
                }

                spinner.stop();
            });
        }

        public void populate_request (string guid) {
            var url = "http://" + application_window.core_address + "/requests/" + guid;

            var message = new Soup.Message ("GET", url);

            application_window.http_session.send_and_read_async.begin (message, GLib.Priority.HIGH, null, (obj, res) => {
                try {
                    var response = application_window.http_session.send_and_read_async.end (res);
                    var str_resp = (string) response.get_data () ;
                    if (message.status_code != 200) {
                        label_error.label = str_resp;
                        spinner.stop();
                        return;
                    }
    
                    var parser = new Json.Parser ();
                    parser.load_from_data (str_resp, -1);
                    
                    var rootObj = parser.get_root().get_object();    
                    var raw_request_data = Base64.decode (rootObj.get_string_member ("RequestData"));
                    var req_data_str = (string) raw_request_data;

                    if (req_data_str.validate (raw_request_data.length - 1, null)) {
                        scrolled_window_text_view_request.visible = true;
                        scrolled_window_hex_editor.visible = false;
                        request_text_editor.buffer.set_text (req_data_str.replace ("\r\n", "\n"));
                        label_request.mnemonic_widget = request_text_editor;
                    }
                    else {
                        scrolled_window_text_view_request.visible = false;
                        scrolled_window_hex_editor.visible = true;
                        var buf = new HexStaticBuffer.from_bytes (raw_request_data);
                        buf.set_read_only (false);
                        hex_editor.buffer = buf;
                        label_request.mnemonic_widget = hex_editor;
                    }

                    entry_hostname.set_text (rootObj.get_string_member ("Hostname"));
                    dropdown_protocol.selected = rootObj.get_string_member ("Protocol") == "https://" ? 0 : 1;

                    request_details.reset_state ();
                    
                } catch (Error err) {
                    stdout.printf ("Error retrieving/populating request: %s\n", err.message);
                    label_error.label = "Error retrieving request: " + err.message;
                }
            });
        }

        public void reset_state () {
            dropdown_protocol.selected = 0;
            entry_hostname.set_text ("livefirerange.pakikiproxy.com");
            spinner.stop ();
            stdout.printf("Reset state called\n");
            request_text_editor.buffer.set_text ("GET / HTTP/1.1\nHost: livefirerange.pakikiproxy.com\n\n");
            request_text_editor.on_text_changed (true);
            label_error.label = "";
            request_details.reset_state ();
            hex_editor.buffer = new HexStaticBuffer.from_bytes (new uint8[0]);
            scrolled_window_hex_editor.visible = false;
            scrolled_window_text_view_request.visible = true;
            label_request.mnemonic_widget = request_text_editor;
        }
    }
}
