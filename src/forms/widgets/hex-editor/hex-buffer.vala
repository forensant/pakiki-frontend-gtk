namespace Pakiki {
    public class HexBuffer : Object {
        public signal void length_changed ();

        // this block needs to be implemented within child classes
        public virtual uint8[] all_data () { return new uint8[0]; }
        public virtual uint8[] data (uint64 from, uint64 to) { return new uint8[0]; }
        public virtual bool data_cached (uint64 from, uint64 to) { return true; }
        public virtual uint64 length () { return 0; }
        public virtual bool read_only () { return true; }

        public virtual uint8 byte_at (uint64 offset) { return '0';}
        public virtual void insert (uint64 at, uint8[] data) {}
        public virtual bool pos_in_headers (uint64 pos) { return false; }
        public virtual void remove (uint64 from, uint64 to) {}
        public virtual void replace_byte (uint64 pos, uint8 byte) {}

        /*
          Search logic
         */
        public struct SearchResult {
            int64 start_offset;
            int64 end_offset;
        }

        public signal void search_results_available ();
        // This should be implemented in child classes, and should populate search_results and reset the counter to -1, and call search_results_available
        public virtual void search (string query, string format) {}

        protected SearchResult[] search_results;
        protected int search_result_upto;

        protected uint8[] hex_to_bytes (string hex) {
            uint8[] bytes = {};
            for (int i = 0; i < hex.length; i+=2) {
                int b;
                var parsed = int.try_parse (hex.slice(i, i + 2), out b, null, 16);
                if (parsed) {
                    bytes += (uint8)b;
                }
                else {
                    bytes += '?';
                }
            }
            bytes += '\0';
            return bytes;
        }

        public SearchResult next_search_result () {
            if (search_results.length == 0) {
                SearchResult sr = { 0, 0 };
                return sr;
            }

            search_result_upto++;

            if (search_result_upto >= search_results.length) {
                search_result_upto = 0;
            }

            return search_results[search_result_upto];
        }

        public SearchResult prev_search_result () {
            if (search_results.length == 0) {
                SearchResult sr = { 0, 0 };
                return sr;
            }

            search_result_upto--;

            if (search_result_upto <= -1) {
                search_result_upto = search_results.length - 1;
            }

            return search_results[search_result_upto];
        }

        public int search_result_count () {
            return search_results.length;
        }

        public int search_result_selection () {
            return search_result_upto + 1; // as it's 0-indexed
        }

        protected string valid_hex (string hexstr) {
            var hex = hexstr;
            if (hex.index_of ("0x") == 0) {
                hex = hex.slice (2, hex.length);
            }

            try {
                Regex regex = new Regex ("[^0-9A-Fa-f]");
                hex = regex.replace (hex, hex.length, 0, "");
                if (hex.length % 2 != 0) {
                    hex = hex.slice (0, hex.length - 1);
                }
                return hex;
            }
            catch (RegexError e) {
                stdout.printf ("Could not parse the regex: %s\n", e.message);
            }

            return "";
        }
    }
}
