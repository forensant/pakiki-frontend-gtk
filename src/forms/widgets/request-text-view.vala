namespace Proximity {

    [GtkTemplate (ui = "/com/forensant/proximity/request-text-view.ui")]
    class RequestTextView : Gtk.Box {
        private SearchableSourceView searchable_source_view;
        private HexEditor hex_editor;

        // Anything above this, and we won't try to syntax highlight as it causes performance issues - 10KB?
        private long MAX_HIGHLIGHT_LINE_LENGTH = (1024*10); 

        [GtkChild]
        private unowned Gtk.ScrolledWindow scrolled_window_hex_view;

        // for the requests/responses where we can render them
        private Gtk.SourceLanguageManager language_manager;
        private Gtk.SourceBuffer source_buffer;

        private ApplicationWindow application_window;
        private bool setting_selection;

        private bool _editable;
        public bool editable {
            get { return _editable; }
            set { 
                _editable = value;
                searchable_source_view.source_view.editable = value;
                // hex_editor.editable = value;
            }
        }

        private bool _scroll = true;
        public bool scroll {
            get { return _scroll; }
            set { 
                _scroll = value;

                searchable_source_view.scroll = value;
                var vertical_policy = value ? Gtk.PolicyType.AUTOMATIC : Gtk.PolicyType.NEVER;
                var shadow_type = value ? Gtk.ShadowType.NONE : Gtk.ShadowType.IN;

                scrolled_window_hex_view.vscrollbar_policy = vertical_policy;
                scrolled_window_hex_view.shadow_type = shadow_type;
            }
        }
        
        public RequestTextView (ApplicationWindow application_window) {
            this.application_window = application_window;
            searchable_source_view = new SearchableSourceView ();
            searchable_source_view.show ();
            this.add (searchable_source_view);
            
            setting_selection = false;
            language_manager = Gtk.SourceLanguageManager.get_default ();
            var lang = language_manager.get_language ("xml");

            source_buffer = new Gtk.SourceBuffer.with_language (lang);
            searchable_source_view.source_view.buffer = source_buffer;
            
            searchable_source_view.source_view.populate_popup.connect ( (menu) => {
                on_request_response_popup (menu, source_buffer);
            });

            hex_editor = new HexEditor ();
            hex_editor.show ();
            scrolled_window_hex_view.add (hex_editor);
        }

        public bool find_activated () {
            if (searchable_source_view.visible) {
                return searchable_source_view.find_activated ();
            }

            return false;
        }

        private long longest_line_length (string req) {
            var lines = req.split("\n");
            long longest_line_length = 0;
            foreach (string l in lines) {
                if (l.length > longest_line_length) {
                    longest_line_length = l.length;
                }
            }
            return longest_line_length;
        }

        private void on_request_response_popup (Gtk.Menu menu, Gtk.TextBuffer buffer) {
            Gtk.TextIter selection_start, selection_end;
            var text_selected = buffer.get_selection_bounds (out selection_start, out selection_end);

            if (!text_selected) {
                return;
            }

            var separator = new Gtk.SeparatorMenuItem ();
            separator.show ();
            menu.append (separator);

            var menu_item = new Gtk.MenuItem.with_label ("Send to Cyberchef");
            menu_item.activate.connect ( () => {
                var selected_text = buffer.get_slice (selection_start, selection_end, true);
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

        public void reset_state () {
            source_buffer.text = "";
            hex_editor.buffer = new HexStaticBuffer ();
            show_hex (false);
        }

        public void set_large_request (string guid, int64 content_length) {
            show_hex (true);
            if (hex_editor.buffer is HexRemoteBuffer) {
                var buf = hex_editor.buffer as HexRemoteBuffer;
                if (buf.guid == guid) {
                    buf.content_length = content_length;
                    return;
                }
            }

            hex_editor.buffer = new HexRemoteBuffer (application_window, guid, content_length);
        }

        private void set_hex_text (uchar[] request, uchar[] response) {
            show_hex (true);

            var full_hex_text = new Gee.ArrayList<uchar> ();
            for (var i = 0; i < request.length; i++) {
                full_hex_text.add (request[i]);
            }
            if (request.length == 0 || response.length == 0) {
                full_hex_text.add ('\n');
                full_hex_text.add ('\n');
            }
            for (var i = 0; i < response.length; i++) {
                full_hex_text.add (response[i]);
            }

            hex_editor.buffer = new HexStaticBuffer.from_bytes (full_hex_text.to_array ());
        }

        public void set_request(uchar[] request) {
            set_request_response (request, new uchar[1] { 0 });
        }

        public void set_request_response (uchar[] request, uchar[] response) {
            var str_request = (string)request;
            var str_response = (string)response;

            if (str_response.validate (response.length - 1, null) && str_request.validate (request.length - 1, null)) {
                set_text (str_request, str_response);
            } else {
                set_hex_text (request, response);
            }
        }

        private void set_sourceview_language (string response) {
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

            source_buffer.language = language_manager.get_language (language);
        }

        private void set_text (string request, string response) {
            show_hex (false);
            if (should_syntax_highlight (request, response)) {
                set_sourceview_language (request);
            }
            else {
                source_buffer.language = language_manager.get_language ("text");
            }
            var newlines = _scroll ? "\n\n" : "";
            source_buffer.text = request.make_valid () + newlines + response.make_valid ();
        }

        private bool should_syntax_highlight(string request, string response) {
            return longest_line_length(request) <= MAX_HIGHLIGHT_LINE_LENGTH &&
             longest_line_length(response) <= MAX_HIGHLIGHT_LINE_LENGTH;
        }

        private void show_hex (bool show) {
            scrolled_window_hex_view.visible = show;
            searchable_source_view.visible = !show;
        }
    }
}