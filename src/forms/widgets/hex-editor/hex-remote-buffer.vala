namespace Proximity {
    // TODO: Obviously this isn't actually the remote buffer
    public class HexRemoteBuffer : Object, HexBuffer {
        
        private uint8[] buffer;

        public HexRemoteBuffer.from_file (string filename) {
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
        
        public uint8[] data (int from, int to) {
            if (to < buffer.length) {
                to = buffer.length;
            }
            if (from < 0) {
                from = 0;
            }

            return buffer[from:to];
        }

        public bool data_cached (int from, int to) {
            return true;
        }

        public int64 length () {
            return buffer.length;
        }
    }
}
