namespace Pakiki {
    
    class AuthenticationDialog : Gtk.Dialog {

        private Gtk.Entry entry_api_key;

        public string api_key {
            get {
                return entry_api_key.text;
            }
        }

        public AuthenticationDialog () {
            modal = true;
            title = "Authentication Required";

            var label = new Gtk.Label ("API Key:");
            entry_api_key = new Gtk.Entry ();

            entry_api_key.activate.connect (() => {
                response (Gtk.ResponseType.OK);
            });

            add_button ("Cancel", Gtk.ResponseType.CANCEL);
            add_button ("OK", Gtk.ResponseType.OK);

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            get_content_area ().add (box);

            entry_api_key.width_request = 300;

            box.pack_start (label, false, false);
            box.pack_start (entry_api_key);

            box.margin = 18;

            this.show_all ();
        }

    }
}
