namespace Proximity {
    public class ProxySettings {

        private ApplicationWindow application_window;
        private string certificate;
        public string proxy_address;
        public string upstream_proxy_address;
        public bool successful;
        
        public ProxySettings (ApplicationWindow application_window) {
            this.application_window = application_window;
            successful = true;
            download_settings ();
            download_certificate ();
        }

        void download_certificate () {
            var url = "http://" + application_window.core_address + "/proxy/ca_certificate.pem";
            try {
                // Create a session:
                Soup.Session session = new Soup.Session ();
        
                // Request a file:
                Soup.Request request = session.request (url);
                InputStream stream = request.send ();
        
                // Print the content:
                DataInputStream data_stream = new DataInputStream (stream);
        
                string? line;
                this.certificate = "";
                while ((line = data_stream.read_line ()) != null) {
                    certificate += line;
                    certificate += "\n";
                }
            } catch (Error e) {
                stderr.printf ("Error connecting to %s to download the certificate: %s\n", url, e.message);
                successful = false;
            }
            
        }

        void download_settings () {
            var url = "http://" + application_window.core_address + "/proxy/settings";
            try {
                // Create a session:
                Soup.Session session = new Soup.Session ();
        
                // Request a file:
                Soup.Request request = session.request (url);
                InputStream stream = request.send ();
        
                // Print the content:
                DataInputStream data_stream = new DataInputStream (stream);
        
                string? line;
                var proxy_settings = "";
                while ((line = data_stream.read_line ()) != null) {
                    proxy_settings += line;
                }

                var parser = new Json.Parser ();
                parser.load_from_data (proxy_settings);
                var root_object = parser.get_root ().get_object ();

                proxy_address = root_object.get_string_member ("Http11ProxyAddr");
                upstream_proxy_address = root_object.get_string_member ("Http11UpstreamProxyAddr");

            } catch (Error e) {
                proxy_address = "UNKNOWN";
                successful = false;

                stderr.printf ("Error connecting to %s to get the proxy port: %s\n", url, e.message);
            }
        }

        public string save () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://" + application_window.core_address + "/proxy/settings");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("Http11ProxyAddr");
            builder.add_string_value (proxy_address);
            builder.set_member_name ("Http11UpstreamProxyAddress");
            builder.add_string_value (upstream_proxy_address);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request("application/json", Soup.MemoryUse.COPY, parameters.data);
            session.send_message(message);

            if (message.status_code == 500) {
                return (string)message.response_body.data;
            }
            return "";
        }

        public void save_certificate (Gtk.Window parent) {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                parent,
                Gtk.FileChooserAction.SAVE,
                "_Save",
                "_Cancel");

            dialog.set_current_name ("certificate.pem");
            dialog.transient_for = parent;
            dialog.local_only = false; //allow for uri
            dialog.set_modal (true);
            dialog.set_do_overwrite_confirmation (true);

            var response_id = dialog.run ();

            if (response_id == Gtk.ResponseType.ACCEPT) {
                var file = dialog.get_file();
                    
                try {
                    file.replace_contents (certificate.data, null, false,
                                           GLib.FileCreateFlags.NONE, null, null);
                }
                catch (GLib.Error err) {
                    error ("%s\n", err.message);
                }
            }

            dialog.destroy ();
            
        }

    }
}