using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-details.ui")]
    class RequestDetails : Gtk.Notebook {

        [GtkChild]
        private unowned Gtk.TextView requestResponseText;
        //[GtkChild]
        //private WebKit.WebView webkit_preview;
        [GtkChild]
        private unowned Gtk.MenuButton button_send_to;

        private ApplicationWindow application_window;
        private string guid;

        public RequestDetails (ApplicationWindow application_window) {
            this.application_window = application_window;
            guid = "";
            // Ensure that when we reactivate webkit, that it's sandboxed: https://gitlab.gnome.org/GNOME/Initiatives/-/wikis/Sandbox-all-the-WebKit!
            //_preview.load_uri("https://www.google.com/");

            // create the send-to menu
            var menu = new Gtk.Menu ();
            
            var item_new_request = new Gtk.MenuItem.with_label ("New Request");
            item_new_request.activate.connect ( () => {
                if (guid != "") {
                    application_window.send_to_new_request (guid);
                }
            });
            item_new_request.show ();
            menu.append (item_new_request);

            var item_inject = new Gtk.MenuItem.with_label ("Inject");
            item_inject.activate.connect ( () => {
                if (guid != "") {
                    application_window.send_to_inject (guid);
                }
            });
            item_inject.show ();
            menu.append (item_inject);

            button_send_to.set_popup (menu);
        }

        [GtkCallback]
        public void on_request_response_popup (Gtk.Menu menu) {
            Gtk.TextIter selection_start, selection_end;
            var text_selected = requestResponseText.buffer.get_selection_bounds (out selection_start, out selection_end);

            if (!text_selected) {
                return;
            }

            var separator = new Gtk.SeparatorMenuItem ();
            separator.show ();
            menu.append (separator);

            var menu_item = new Gtk.MenuItem.with_label ("Send to Cyberchef");
            menu_item.activate.connect ( () => {
                var selected_text = requestResponseText.buffer.get_slice (selection_start, selection_end, true);
                var uri = "https://gchq.github.io/CyberChef/#input=" + Soup.URI.encode (Base64.encode (selected_text.data), "");

                try {
                    AppInfo.launch_default_for_uri (uri, null);
                } catch (Error err) {
                    stdout.printf ("Could not launch Cyberchef: %s\n", err.message);
                }
            });
            menu_item.show ();
            menu.append (menu_item);
        }

        public void set_request (string guid) {
            this.guid = guid;
            button_send_to.set_visible (true);

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", "http://127.0.0.1:10101/project/requestresponse?guid=" + guid);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    parser.load_from_data (jsonData, -1);

                    var rootObj = parser.get_root().get_object();
                    
                    var request = (string)Base64.decode(rootObj.get_string_member("Request"));
                    var response = (string)Base64.decode(rootObj.get_string_member("Response"));

                    var buffer = this.requestResponseText.buffer;
                    buffer.text = request.make_valid() + "\n\n" + response.make_valid();
                }
                catch(Error e) {
                    stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                }
                
            });
        }

        public void reset_state () {
            requestResponseText.buffer.set_text ("");
        }
    }
}
