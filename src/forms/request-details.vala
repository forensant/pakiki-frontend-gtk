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
        private Gtk.SourceLanguageManager language_manager;
        private Gtk.SourceBuffer source_buffer;
        private Gtk.SourceBuffer source_buffer_orig;
        private Gtk.SourceView text_view_request_response;
        private Gtk.SourceView text_view_original_request_response;

        public RequestDetails (ApplicationWindow application_window) {
            this.application_window = application_window;
            guid = "";
            language_manager = Gtk.SourceLanguageManager.get_default ();

            var lang = language_manager.get_language ("xml");

            source_buffer = new Gtk.SourceBuffer.with_language (lang);
            text_view_request_response = new Gtk.SourceView.with_buffer (source_buffer);
            source_buffer_orig = new Gtk.SourceBuffer.with_language (lang);
            text_view_original_request_response = new Gtk.SourceView.with_buffer (source_buffer_orig);

            setup_sourceview (text_view_request_response, scroll_window_text);
            setup_sourceview (text_view_original_request_response, scroll_window_original_text);

            text_view_request_response.show ();
            text_view_original_request_response.show ();

            // Ensure that when we reactivate webkit, that it's sandboxed: https://gitlab.gnome.org/GNOME/Initiatives/-/wikis/Sandbox-all-the-WebKit!
            //_preview.load_uri("https://www.google.com/");

            set_send_to_popup ();
            scroll_window_original_text.hide ();

            text_view_request_response.populate_popup.connect (on_request_response_popup_modified);
            text_view_original_request_response.populate_popup.connect (on_request_response_popup_orig);
        }

        private void on_request_response_popup_modified (Gtk.Menu menu) {
            on_request_response_popup (menu, text_view_request_response);
        }

        private void on_request_response_popup_orig (Gtk.Menu menu) {
            on_request_response_popup (menu, text_view_original_request_response);
        }

        public void on_request_response_popup (Gtk.Menu menu, Gtk.SourceView control) {
            Gtk.TextIter selection_start, selection_end;
            var text_selected = control.buffer.get_selection_bounds (out selection_start, out selection_end);

            if (!text_selected) {
                return;
            }

            var separator = new Gtk.SeparatorMenuItem ();
            separator.show ();
            menu.append (separator);

            var menu_item = new Gtk.MenuItem.with_label ("Send to Cyberchef");
            menu_item.activate.connect ( () => {
                var selected_text = control.buffer.get_slice (selection_start, selection_end, true);
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

        private void setup_sourceview (Gtk.SourceView source_view, Gtk.ScrolledWindow parent) {
            source_view.expand = true;
            source_view.monospace = true;
            source_view.margin_start = 6;
            source_view.margin_end = 6;
            source_view.margin_top = 6;
            source_view.margin_bottom = 6;
            source_view.set_wrap_mode(Gtk.WrapMode.CHAR);
            parent.add (source_view);
        }

        public void set_request (string guid) {
            this.guid = guid;
            reset_state ();
            button_send_to.set_visible (true);

            if (guid == "" || guid == "-") {
                return;
            }

            var session = new Soup.Session ();
            var message = new Soup.Message ("GET", "http://127.0.0.1:10101/project/requestresponse?guid=" + guid);

            session.queue_message (message, (sess, mess) => {
                var parser = new Json.Parser ();
                var jsonData = (string)mess.response_body.flatten().data;
                try {
                    if (!parser.load_from_data (jsonData, -1)) {
                        return;
                    }

                    var rootObj = parser.get_root().get_object();
                    
                    var original_request = (string)Base64.decode (rootObj.get_string_member ("Request"));
                    var original_response = (string)Base64.decode (rootObj.get_string_member ("Response"));

                    var modified_request = (string)Base64.decode (rootObj.get_string_member ("ModifiedRequest"));
                    var modified_response = (string)Base64.decode (rootObj.get_string_member ("ModifiedResponse"));

                    if (modified_request != "" || modified_response != "") {
                        scroll_window_original_text.show ();

                        if (modified_request == "") {
                            modified_request = original_request;
                        }

                        if (modified_response == "") {
                            modified_response = original_response;
                        }

                        var buffer = this.text_view_request_response.buffer;
                        buffer.text = "";
                        set_sourceview_language (source_buffer, modified_response.make_valid ());
                        buffer.text = modified_request.make_valid () + "\n\n" + modified_response.make_valid ();

                        buffer = this.text_view_original_request_response.buffer;
                        buffer.text = "";
                        set_sourceview_language (source_buffer_orig, original_response.make_valid ());
                        buffer.text = original_request.make_valid () + "\n\n" + original_response.make_valid ();
                    } else {
                        scroll_window_original_text.hide ();
                        var buffer = this.text_view_request_response.buffer;
                        buffer.text = ""; 
                        set_sourceview_language (source_buffer, original_response.make_valid ());
                        buffer.text = original_request.make_valid () + "\n\n" + original_response.make_valid ();
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

        private void set_sourceview_language (Gtk.SourceBuffer buffer, string response) {
            var language = "html";

            try {
                var re = new Regex ("\\s*Content-Type: [/A-Za-z0-9]*\\s*");
                GLib.MatchInfo match_info;
                var match_found = re.match (response, 0, out match_info);
                
                
                if (match_found && match_info.get_match_count () >= 1) {
                    var content_type = match_info.fetch (0);
                    if (content_type != null) {
                        if (content_type.contains ("javascript")) {
                            language = "javascript";
                        } else if (content_type.contains ("css") || content_type.contains ("stylesheet")) {
                            language = "css";
                        }
                    }
                }
            } catch (Error e) {
                stderr.printf ("Could not get the language of the response: %s\n", e.message);
            }

            buffer.language = language_manager.get_language (language);
        }

        public void reset_state () {
            text_view_request_response.buffer.set_text ("");
            text_view_original_request_response.buffer.set_text ("");
            scroll_window_original_text.hide ();
            this.page = 0;
        }
    }
}
