namespace Proximity {
    public class HexRemoteBuffer : Object, HexBuffer {
        
        public string guid { get; private set; }

        private ApplicationWindow application_window;
        private uint8[] buffer;
        private uint64 buffer_start;
        private uint64 buffer_end;

        private uint64 _content_length;
        public uint64 content_length {
            get { return _content_length; }
            set {
                _content_length = value;
                length_changed ();
            }
        }

        public HexRemoteBuffer (ApplicationWindow application_window, string guid, uint64 content_length) {
            this.application_window = application_window;
            this.guid = guid;
            this.content_length = content_length;
            buffer_start = 0;
            buffer_end = 0;
        }
        
        public uint8[] data (uint64 from, uint64 to) {
            var blank_data = new uint8[0];
            if (from > to) {
                return blank_data;
            }

            // this function makes the assumption that generally we'll only be receiving requests for smallish amounts of data
            // and that the server will generally provide mid-large amounts of data to cache
            if (!data_cached (from, to)) {
                var url = "http://" + application_window.core_address + "/project/requests/" + guid+ "/data?from=" + from.to_string ();

                var message = new Soup.Message ("GET", url);
                application_window.http_session.send_message (message);

                var response = (string)message.response_body.flatten ().data;
                var parser = new Json.Parser ();
                try {
                    if (message.status_code != 200) {
                        stderr.printf("Could not connect to %s, response: %s\n", url, response);
                        return blank_data;
                    }
                    else {
                        parser.load_from_data (response, -1);
                        var root_obj = parser.get_root ().get_object ();

                        buffer = Base64.decode (root_obj.get_string_member ("Data"));
                        buffer_start = root_obj.get_int_member ("From");
                        buffer_end = root_obj.get_int_member ("To");
                    }
                } catch (Error err) {
                    stdout.printf ("Could not populate the request data cache: %s\n", err.message);
                    return blank_data;
                }
            }

            from -= buffer_start;
            to -= buffer_start;

            if (to > buffer.length) {
                to = buffer.length;
            }
            if (from < 0) {
                from = 0;
            }

            var b = buffer[from:to];
            return b;
        }

        public bool data_cached (uint64 from, uint64 to) {
            return (from >= buffer_start && to <= buffer_end);
        }

        public uint64 length () {
            return _content_length;
        }

        public bool read_only () {
            return true;
        }
    }
}
