using Soup;
using WebKit;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/request-details.ui")]
    class RequestDetails : Gtk.Notebook {

        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_original_text;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll_window_text;
        [GtkChild]
        private WebKit.WebView webkit_preview;
        [GtkChild]
        private unowned Gtk.MenuButton button_send_to;

        private ApplicationWindow application_window;
        private string guid;

        private RequestTextView orig_request_text_view;
        private RequestTextView request_text_view;
        
        private bool _show_send_to;
        public bool show_send_to {
            get { return _show_send_to; }
            set {
                _show_send_to = value; 
                button_send_to.visible = value;
            }
        }

        private bool ended;

        public RequestDetails (ApplicationWindow application_window) {
            this.application_window = application_window;
            ended = false;
            guid = "";

            request_text_view = new RequestTextView ();
            orig_request_text_view = new RequestTextView ();

            request_text_view.editable = false;
            orig_request_text_view.editable = false;

            scroll_window_text.add (request_text_view);
            scroll_window_original_text.add (orig_request_text_view);

            request_text_view.show ();
            orig_request_text_view.show ();

            set_send_to_popup ();
            scroll_window_original_text.hide ();
            webkit_preview.hide ();

            webkit_preview.decide_policy.connect (on_link_clicked);
        }

        ~RequestDetails () {
            ended = true;
        }

        private bool on_link_clicked (PolicyDecision policy_decision, PolicyDecisionType type) {
            if (type != WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
                return false;
            }

            var decision = (NavigationPolicyDecision)policy_decision;

            if (decision.get_navigation_action ().get_navigation_type () == WebKit.NavigationType.LINK_CLICKED) {
                decision.ignore ();
                return true;
            }

            return false;
        }

        public void set_request (string guid) {
            this.guid = guid;
            reset_state ();
            if (_show_send_to) {
                button_send_to.set_visible (true);
            }

            if (guid == "" || guid == "-") {
                return;
            }

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", "http://" + application_window.core_address + "/project/requestresponse?guid=" + guid);

            session.queue_message (message, (sess, mess) => {
                if (ended) {
                    return;
                }

                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    if (!parser.load_from_data (jsonData, -1)) {
                        return;
                    }

                    var root_obj = parser.get_root().get_object();
                    
                    var original_request = Base64.decode (root_obj.get_string_member ("Request"));
                    var original_response = Base64.decode (root_obj.get_string_member ("Response"));

                    var modified_request = Base64.decode (root_obj.get_string_member ("ModifiedRequest"));
                    var modified_response = Base64.decode (root_obj.get_string_member ("ModifiedResponse"));

                    var url = root_obj.get_string_member ("URL");
                    var mimetype = root_obj.get_string_member ("MimeType");
                    
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
                        set_webview (modified_response, mimetype, url);
                        
                    } else {
                        scroll_window_original_text.hide ();

                        request_text_view.set_request_response (original_request, original_response);
                        set_webview (original_response, mimetype, url);
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

        private void set_webview (uchar[] bytes, string mimetype, string url) {
            if ( mimetype.index_of ("application/") == 0) {
                webkit_preview.hide ();
                return;
            }

            var proxy_settings = new WebKit.NetworkProxySettings ("http://" + application_window.preview_proxy_address + "/", null);
            var web_context = webkit_preview.get_context ();
            web_context.clear_cache ();
            web_context.set_tls_errors_policy (WebKit.TLSErrorsPolicy.IGNORE);
            web_context.set_network_proxy_settings (WebKit.NetworkProxyMode.CUSTOM, proxy_settings);

            var bytes_str = (string)bytes;
            var end_of_headers = bytes_str.index_of ("\r\n\r\n");

            if (end_of_headers == -1) {
                webkit_preview.hide ();
                return;
            }

            GLib.Bytes body = new GLib.Bytes (bytes[end_of_headers + 4:bytes.length]);

            if (body.length == 0) {
                webkit_preview.hide ();
                return;
            }

            webkit_preview.show ();
            webkit_preview.load_bytes (body, mimetype, null, url);
        }

        public void reset_state () {
            request_text_view.reset_state ();
            orig_request_text_view.reset_state ();
            scroll_window_original_text.hide ();
            this.page = 0;
        }
    }
}
