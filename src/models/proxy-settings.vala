namespace Pakiki {
    public class ProxySettings {

        private ApplicationWindow application_window;
        private string certificate;
        public int connections_per_host;
        public string proxy_address;
        public string upstream_proxy_address;
        public bool successful;
        public bool unauthenticated;
        
        public ProxySettings (ApplicationWindow application_window) {
            this.application_window = application_window;
            successful = true;
            unauthenticated = false;
            download_settings ();
            download_certificate ();
        }

        void download_certificate () {
            var url = "http://" + application_window.core_address + "/proxy/ca_certificate.pem";
            try {
                // Request a file:
                var message = new Soup.Message ("GET", url);
                InputStream stream = application_window.http_session.send (message);
                
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
                // Request a file:
                var message = new Soup.Message ("GET", url);
                InputStream stream = application_window.http_session.send (message);
                
                // Print the content:
                DataInputStream data_stream = new DataInputStream (stream);
        
                string? line;
                var proxy_settings = "";
                while ((line = data_stream.read_line ()) != null) {
                    proxy_settings += line;
                }

                if (proxy_settings == "Invalid API Key") {
                    unauthenticated = true;
                    return;
                }

                var parser = new Json.Parser ();
                parser.load_from_data (proxy_settings);
                var root_object = parser.get_root ().get_object ();

                proxy_address = root_object.get_string_member ("Http11ProxyAddr");
                upstream_proxy_address = root_object.get_string_member ("Http11UpstreamProxyAddr");
                connections_per_host = (int)root_object.get_int_member ("MaxConnectionsPerHost");

            } catch (Error e) {
                proxy_address = "UNKNOWN";
                successful = false;

                stderr.printf ("Error connecting to %s to get the proxy port: %s\n", url, e.message);
            }
        }

        public string local_proxy_address () {
            var parts = proxy_address.split (":", 2);
            if (parts.length == 1) {
                return "127.0.0.1:" + parts[0];
            } else if (parts[0] == "") {
                return "127.0.0.1:" + parts[1];
            } else {
                return proxy_address;
            }
        }

        public string save () {
            var message = new Soup.Message ("PUT", "http://" + application_window.core_address + "/proxy/settings");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("Http11ProxyAddr");
            builder.add_string_value (proxy_address);
            builder.set_member_name ("Http11UpstreamProxyAddr");
            builder.add_string_value (upstream_proxy_address);
            builder.set_member_name ("MaxConnectionsPerHost");
            builder.add_int_value (connections_per_host);
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request_body_from_bytes ("application/json", new Bytes(parameters.data));
            try {
                var response_body = application_window.http_session.send_and_read (message);
                if (message.status_code != 200) {
                    if (response_body != null) {
                        return (string)response_body.get_data ();
                    } else {
                        return "Error: " + message.status_code.to_string ();
                    }
                }
            } catch (Error e) {
                return "Error: Could not save settings: " + e.message;
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