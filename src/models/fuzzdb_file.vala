namespace Pakiki {
    
    public class FuzzDBFile : GLib.Object {
        public bool checked { get; set; }
        public Gee.ArrayList<FuzzDBFile> children { get; set; }
        public string filename { get; set; }
        public bool inconsistent { get; private set; }
        public int payload_count { get; set; }
        public string payloads { get; set; }
        public string title { get; set; }

        public FuzzDBFile? parent { get; set; }

        // this mixes the display vs model, but I couldn't find another way to do it
        public ulong? signal_id { get; set; }
        
        public FuzzDBFile (Json.Object obj) {
            string str_payloads = "";
            var sample_payloads = obj.get_array_member ("SamplePayloads");
            if (sample_payloads != null) {
                foreach (var sample_payload in sample_payloads.get_elements ()) {
                    str_payloads += sample_payload.get_string () + "\n";
                }

                if(str_payloads != "") {
                    str_payloads = "<b>Sample Payloads:</b>\n" + str_payloads.replace ("&", "&amp;").replace ("<", "&gt;").replace (">", "&lt;");
                }
            }

            Object (
                checked: false,
                children: children_from_json_array (obj.get_array_member ("SubEntries")),
                filename: obj.get_string_member ("ResourcePath"),
                payload_count: (int) obj.get_int_member ("PayloadCount"),
                payloads: str_payloads,
                title: obj.get_string_member ("Title")
            );
        }

        public static Gee.ArrayList<FuzzDBFile> children_from_json_array (Json.Array array) {
            Gee.ArrayList<FuzzDBFile> children = new Gee.ArrayList<FuzzDBFile> ();
            foreach (var element in array.get_elements ()) {
                Json.Object payload = element.get_object ();
                children.add (new FuzzDBFile (payload));
            }
            return children;
        }

        public Gee.ArrayList<string> get_checked_files () {
            var checked_files = new Gee.ArrayList<string> ();
            if (checked && children.size == 0) {
                checked_files.add (this.filename);
            }

            foreach (var child in children) {
                checked_files.add_all (child.get_checked_files ());
            }

            return checked_files;
        }

        public bool search_matches (string search) {
            if (title.down ().contains (search.down ())) {
                return true;
            }

            foreach (var child in children) {
                if (child.search_matches (search)) {
                    return true;
                }
            }

            return false;
        }

        public void set_checked_path (string path) {
            if (path == filename) {
                checked = true;
                return;
            }

            foreach (var child in children) {
                child.set_checked_path (path);
            }
        }

        public void set_indeterminate () {
            stdout.printf ("set_indeterminate: %s\n", title);
            if (children.size == 0) {
                return;
            }

            foreach (var child in children) {
                child.set_indeterminate ();
            }

            var all_false = true;
            var all_true = true;
            foreach (var child in children) {
                if (child.inconsistent) {
                    inconsistent = true;
                    return;
                }
                if (child.checked) {
                    all_false = false;
                } else {
                    all_true = false;
                }
            }

            if (all_false || all_true) {
                inconsistent = false;
                checked = all_true;
            } else {
                inconsistent = true;
            }
        }

        public void set_parents () {
            foreach (var child in children) {
                child.parent = this;
                child.set_parents ();
            }
        }

        public void set_parent_inconsistent () {
            stdout.printf("set_parent_inconsistent: %s\n", title);
            var root = parent;
            if (root == null) {
                stdout.printf("root is null\n");
                return;
            }

            while (true) {
                var new_parent = root.parent;
                if (new_parent == null) {
                    break;
                }
                root = new_parent;
            }
            
            root.set_indeterminate ();
        }

        public void toggle_active (bool active) {
            checked = active;
            foreach (var child in children) {
                child.toggle_active (active);
            }
        }

        public void uncheck () {
            checked = false;
            foreach (var child in children) {
                child.uncheck ();
            }
        }
    }
}
