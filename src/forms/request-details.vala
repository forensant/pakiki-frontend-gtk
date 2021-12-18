using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-details.ui")]
    class RequestDetails : Gtk.Notebook {

        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_original_text;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_text;
        //[GtkChild]
        //private WebKit.WebView webkit_preview;
        [GtkChild]
        private unowned Gtk.MenuButton button_send_to;

        private ApplicationWindow application_window;
        private string guid;

        private RequestTextView request_text_view;
        private RequestTextView orig_request_text_view;

        public RequestDetails (ApplicationWindow application_window) {
            this.application_window = application_window;
            guid = "";

            request_text_view = new RequestTextView ();
            orig_request_text_view = new RequestTextView ();

            request_text_view.editable = false;
            orig_request_text_view.editable = false;

            scroll_window_text.add (request_text_view);
            scroll_window_original_text.add (orig_request_text_view);

            request_text_view.show ();
            orig_request_text_view.show ();

            // Ensure that when we reactivate webkit, that it's sandboxed: https://gitlab.gnome.org/GNOME/Initiatives/-/wikis/Sandbox-all-the-WebKit!
            //_preview.load_uri("https://www.google.com/");

            set_send_to_popup ();
            scroll_window_original_text.hide ();
        }

        public void set_request (string guid) {
            this.guid = guid;
            reset_state ();
            button_send_to.set_visible (true);

            if (guid == "" || guid == "-") {
                return;
            }

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", "http://" + application_window.core_address + "/project/requestresponse?guid=" + guid);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    if (!parser.load_from_data (jsonData, -1)) {
                        return;
                    }

                    var rootObj = parser.get_root().get_object();
                    
                    var original_request = Base64.decode (rootObj.get_string_member ("Request"));
                    var original_response = Base64.decode (rootObj.get_string_member ("Response"));

                    var modified_request = Base64.decode (rootObj.get_string_member ("ModifiedRequest"));
                    var modified_response = Base64.decode (rootObj.get_string_member ("ModifiedResponse"));

                    if (modified_request.length != 0 || modified_response.length != 0) {
                        scroll_window_original_text.show ();

                        if (modified_request.length == 0) {
                            modified_request = original_request;
                        }

                        if (modified_response.length == 0) {
                            modified_response = original_response;
                        }

                        request_text_view.set_request_response (modified_request, modified_response);
                        orig_request_text_view.set_request_response (original_request, original_response);
                    } else {
                        scroll_window_original_text.hide ();

                        request_text_view.set_request_response (original_request, original_response);
                    }
                }
                catch(Error e) {
                    stdout.printf ("Could not parse JSON data, error: %s\nData: %s\n", e.message, jsonData);
                }
                
            });
        }

        private void set_send_to_popup () {
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

        public void reset_state () {
            request_text_view.reset_state ();
            orig_request_text_view.reset_state ();
            scroll_window_original_text.hide ();
            this.page = 0;
        }
    }
}
