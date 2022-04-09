namespace Proximity {
    public class HexStaticBuffer : Object, HexBuffer {
        
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

        public uint8 byte_at (uint64 offset) {
            if (offset >= buffer.length) {
                return '0';
            }
            else {
                return buffer[offset];
            }
        }
        
        public uint8[] data (uint64 from, uint64 to) {
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

        public bool data_cached (uint64 from, uint64 to) {
            return true;
        }

        public uint8[] get_buffer () {
            return buffer;
        }

        public void insert (uint64 at, uint8[] data) {
            Array<uint8> new_buffer = new Array<uint8> (false);
            new_buffer.append_vals (buffer[0:at], (uint)at);
            new_buffer.append_vals (data, data.length);
            new_buffer.append_vals (buffer[at:buffer.length], (uint)(buffer.length - at));

            this.buffer = (owned) new_buffer.data;
            length_changed ();
        }

        public uint64 length () {
            return buffer.length;
        }

        public bool pos_in_headers (uint64 pos) {
            var str = (string)data;
            return str.index_of ("\x0a\x0d\x0a\x0d") > pos;
        }

        public void remove (uint64 from, uint64 to) {
            Array<uint8> new_buffer = new Array<uint8> (false);
            if (from != 0) {
                new_buffer.append_vals (buffer[0:from], (uint)from);
            }
            new_buffer.append_vals (buffer[to + 1:buffer.length], (uint)(buffer.length - to - 1));

            this.buffer = (owned) new_buffer.data;
            length_changed ();
        }

        public bool read_only () {
            return _read_only;
        }

        public void replace_byte (uint64 pos, uint8 byte) {
            if (pos >= buffer.length) {
                return;
            }
            buffer[pos] = byte;
            length_changed (); // not technically, but will force a refresh
        }

        public void set_read_only (bool ro) {
            _read_only = ro;
        }
    }
}
