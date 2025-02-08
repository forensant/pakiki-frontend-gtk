namespace Pakiki {
    class RequestDiff : GtkSource.View {
        public RequestDiff () {
            this.editable = false;
            this.monospace = true;
            this.wrap_mode = Gtk.WrapMode.CHAR;
            
            this.buffer.create_tag ("diff-added", "background", "light green", "foreground", "black");
            this.buffer.create_tag ("diff-removed", "background", "pink", "foreground", "pink");
        }

        public void set_diff (Json.Array arr, int request) {
            this.buffer.text = "";
            Gtk.TextIter iter;
            this.buffer.get_start_iter (out iter);

            arr.foreach_element ((array, idx, element) => {
                var obj = element.get_object ();
                var text = obj.get_string_member ("Text");
                var request_no = obj.get_int_member ("Request");

                if (request_no == 0) {
                    this.buffer.insert (ref iter, text, -1);
                } else if (request_no == request) {
                    this.buffer.insert_with_tags_by_name (ref iter, text, -1, "diff-added");
                } else {
                    this.buffer.insert_with_tags_by_name (ref iter, text, -1, "diff-removed");
                }
            });
        }

    }
}
