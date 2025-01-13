namespace Pakiki {
    
    public class Request : GLib.Object {
        public string guid { get; set; }
        public string protocol { get; set; }
        public int64 time { get; set; }
        public string url { get; set; }
        public int64 response_content_length { get; set; }
        public string response_content_type { get; set; }
        public int64 duration { get; set; }
        public string verb { get; set; }
        public int64 status { get; set; }
        public string payloads { get; set; }
        public string error { get; set; }

        private bool _notes_timer_running = false;
        private string _last_note_update = "";
        private string _notes = "";
        public string notes { 
            get {
                return _notes;
            } 
            set {
                _notes = value;
                start_note_update_timer ();
            }
        }

        private ApplicationWindow _application_window;

        public Request (Json.Object obj, ApplicationWindow application_window) {
            Object (
                guid: obj.get_string_member ("GUID"),
                protocol: obj.get_string_member ("Protocol"),
                time: obj.get_int_member ("Time"),
                url: obj.get_string_member ("URL"),
                response_content_length: obj.get_int_member ("ResponseContentLength"),
                response_content_type: obj.get_string_member ("ResponseContentType"),
                duration: obj.get_int_member ("ResponseTime"),
                verb: obj.get_string_member ("Verb"),
                status: obj.get_int_member ("ResponseStatusCode"),
                payloads: obj.get_string_member ("Payloads"),
                error: obj.get_string_member ("Error")
            );

            _notes = obj.get_string_member ("Notes");
            _application_window = application_window;
        }

        public string content_type () {
            if (response_content_type == "") {
                return "";
            }

            var components = response_content_type.split (";", 2);
            if (components.length >= 1) {
                return components[0];
            }

            return response_content_type;
        }

        public string payloads_to_string () {
            if (payloads == "") {
                return "";
            }

            var parser = new Json.Parser ();
            
            try {
                parser.load_from_data (payloads, -1);
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
                stdout.printf ("Could not parse JSON payload data, error: %s\nData: %s\n", e.message, payloads);
                return "";
            }
        }

        public string response_duration () {
            if (duration == 0) {
                return "";
            }

            if (duration > 5000) {
                return ((float)(duration/1000.0)).to_string ("%.2f s");
            }
            
            return duration.to_string () + " ms";
        }

        public string response_size () {
            if (response_content_length == 0) {
                return "";
            }

            var bytes = (float)response_content_length;
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

        private void send_note_update () {
            var message = new Soup.Message ("PATCH", "http://" + _application_window.core_address + "/requests/" + guid + "/notes");

            var parameters = "notes=" + GLib.Uri.escape_string (_notes, null);
            message.set_request_body_from_bytes ("application/x-www-form-urlencoded", new Bytes(parameters.data));
            
            _application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }

        private void start_note_update_timer () {
            if (_notes_timer_running) {
                return;
            }

            _notes_timer_running = true;
            GLib.Timeout.add_seconds (2, () => {
                if (_last_note_update != _notes) {
                    // if there's an update, send it, and continue the timer
                    send_note_update ();
                    _last_note_update = _notes;
                    return true;
                }

                _notes_timer_running = false;
                return false;
            });
        }

    }
}