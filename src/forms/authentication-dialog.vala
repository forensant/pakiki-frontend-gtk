namespace Pakiki {
    
    class AuthenticationDialog : Gtk.Window {
        public signal void response (Gtk.ResponseType response_id);

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

            var api_key_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            entry_api_key.width_request = 300;

            api_key_box.append (label);
            api_key_box.append (entry_api_key);

            var container_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            container_box.margin_start = 18;
            container_box.margin_end = 18;
            container_box.margin_top = 18;
            container_box.margin_bottom = 18;

            var button_ok = new Gtk.Button.with_mnemonic ("_OK");
            button_ok.clicked.connect (() => {
                response (Gtk.ResponseType.OK);
            });

            var button_cancel = new Gtk.Button.with_mnemonic ("_Cancel");
            button_cancel.clicked.connect (() => {
                response (Gtk.ResponseType.CANCEL);
            });

            var spacer = new Gtk.Label ("");
            spacer.hexpand = true;

            var button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            button_box.append (spacer);
            button_box.append (button_cancel);
            button_box.append (button_ok);
            
            container_box.append (api_key_box);
            container_box.append (button_box);

            this.set_child (container_box);
        }

    }
}
