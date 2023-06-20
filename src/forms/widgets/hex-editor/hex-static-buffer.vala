namespace Pakiki {
    public class HexStaticBuffer : HexBuffer {
        
        private uint8[] buffer;
        private bool _read_only;

        public HexStaticBuffer () {
            buffer = new uint8[0];
        }

        public HexStaticBuffer.from_bytes (uint8[] buffer) {
            this.buffer = buffer;
            _read_only = true;
        }

        public HexStaticBuffer.from_file (string filename) {
            try {
                
                var file = File.new_for_path (filename);
                
                if (!file.query_exists ()) {
                    stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
                    return;
                }

                file.load_contents (null, out buffer, null);
                length_changed ();
            } catch (Error e) {
                print ("Error: %s\n", e.message);
            }
        }

        public override uint8 byte_at (uint64 offset) {
            if (offset >= buffer.length) {
                return '0';
            }
            else {
                return buffer[offset];
            }
        }
        
        public override uint8[] data (uint64 from, uint64 to) {
            if (to > buffer.length) {
                to = buffer.length;
            }
            if (from < 0) {
                from = 0;
            }
            if (from > buffer.length) {
                from = buffer.length;
            }

            return buffer[from:to];
        }

        public override bool data_cached (uint64 from, uint64 to) {
            return true;
        }

        public uint8[] get_buffer () {
            return buffer;
        }

        public override void insert (uint64 at, uint8[] data) {
            Array<uint8> new_buffer = new Array<uint8> (false);
            new_buffer.append_vals (buffer[0:at], (uint)at);
            new_buffer.append_vals (data, data.length);
            new_buffer.append_vals (buffer[at:buffer.length], (uint)(buffer.length - at));

            this.buffer = (owned) new_buffer.data;
            length_changed ();
        }

        public override uint64 length () {
            return buffer.length;
        }

        public override bool pos_in_headers (uint64 pos) {
            var str = (string)data;
            return str.index_of ("\x0a\x0d\x0a\x0d") > pos;
        }

        public override void remove (uint64 from, uint64 to) {
            Array<uint8> new_buffer = new Array<uint8> (false);
            if (from != 0) {
                new_buffer.append_vals (buffer[0:from], (uint)from);
            }
            new_buffer.append_vals (buffer[to + 1:buffer.length], (uint)(buffer.length - to - 1));

            this.buffer = (owned) new_buffer.data;
            length_changed ();
        }

        public override bool read_only () {
            return _read_only;
        }

        public override void replace_byte (uint64 pos, uint8 byte) {
            if (pos >= buffer.length) {
                return;
            }
            buffer[pos] = byte;
            length_changed (); // not technically, but will force a refresh
        }

        public override void search (string query, string format) {
            search_result_upto = -1;
            string strbuf = (string)buffer;
            HexBuffer.SearchResult[] results = {};

            if (query == "") {
                search_results = results;
                this.search_results_available ();
                return;
            }
            
            var q = query;

            if (format == "Hex") {
                var hex = valid_hex (query);
                if (hex.length == 0) {
                    return;
                }

                q = (string) hex_to_bytes (hex);
            }

            int idx = 0;
            while (idx != -1) {
                idx = strbuf.index_of (q, idx);
                if (idx != -1) {
                    HexBuffer.SearchResult sr = { idx, idx + q.length - 1};
                    results += sr;
                    idx++;
                }
            }

            search_results = results;
            this.search_results_available ();
        }

        public void set_read_only (bool ro) {
            _read_only = ro;
        }
    }
}
