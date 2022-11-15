using Notify;

namespace Proximity {

    [GtkTemplate (ui = "/com/forensant/proximity/window.ui")]
    public class ApplicationWindow : Gtk.ApplicationWindow {
        public const string UPDATE_HOST = "https://proximityhq.com";

        public signal void settings_changed ();

        [GtkChild]
        private unowned Gtk.Button button_back;
        [GtkChild]
        private unowned Gtk.Button button_intercept;
        [GtkChild]
        private unowned Gtk.Button button_new;
        [GtkChild]
        private unowned Gtk.ToggleButton button_search;
        [GtkChild]
        private unowned Gtk.CheckButton check_button_exclude_resources;
        [GtkChild]
        private unowned Gtk.ComboBoxText combobox_search_protocols;
        [GtkChild]
        private unowned Gtk.MenuButton gears;
        [GtkChild]
        private unowned Gtk.InfoBar info_bar_bind_error;
        [GtkChild]
        private unowned Gtk.Label label_proxy_bind_error;
        [GtkChild]
        private unowned Gtk.Overlay overlay;
        [GtkChild]
        private unowned Gtk.SearchBar searchbar;
        [GtkChild]
        private unowned Gtk.SearchEntry searchentry;
        [GtkChild]
        private unowned Gtk.Stack stack;

        private string _core_address;
        public string core_address {
            get { return _core_address; }
        }

        public string api_key;
        public Soup.Session http_session;
        public string preview_proxy_address;
        public ProxySettings proxy_settings;

        private bool authentication_displayed;
        private bool controls_hidden;
        private CoreProcess core_process;
        private InjectPane inject_pane;
        private Intercept intercept;
        private Gtk.Label label_overlay;
        private RequestNew new_request;
        private Application proximity_application;
        private RequestsPane requests_pane;
        private SavingDialog saving_dialog;
        private GLib.Settings settings;
        private bool timeout_started;

        private Notify.Notification notification;

        public ApplicationWindow (Application application, string core_address, string preview_proxy_address, string api_key) {
            GLib.Object (application: application);
            this.api_key = api_key;
            if (api_key == "") {
                generate_api_key ();
            }

            core_process = new CoreProcess (this, this.api_key);
            this.authentication_displayed = false;
            this.proximity_application = application;
            this._core_address = core_address;
            this.preview_proxy_address = preview_proxy_address;
            timeout_started = false;

            set_window_icon (this);
            create_http_session ();

            var process_launched = true;
            if (core_address == "") {
                process_launched = core_process.open (null);
            }

            stack.notify.connect ( (s, property) => {
                if (property.name == "visible-child") {
                    on_pane_changed ();
                }
            });

            label_overlay = new Gtk.Label ("");
            label_overlay.name = "lbl_overlay";
            overlay.add_overlay (label_overlay);
            
            settings = new GLib.Settings ("com.forensant.proximity");
            
            button_search.bind_property ("active", searchbar, "search-mode-enabled",
                                  GLib.BindingFlags.BIDIRECTIONAL);

            button_search.bind_property ("active", searchbar, "visible",
                                  GLib.BindingFlags.BIDIRECTIONAL);

            button_search.clicked.connect (() => {
                searchentry.grab_focus ();
            });

            searchbar.visible = false;

            var accel_group = new Gtk.AccelGroup ();
            accel_group.connect ('f', Gdk.ModifierType.CONTROL_MASK, 0, (group, accel, keyval, modifier) => {
                var pane = selected_pane ();
                if (pane != null && pane.find_activated ()) {
                    // do nothing - as find has been activated
                }
                else if (pane == null || pane.can_search ()) {
                    searchbar.visible = !searchbar.visible;
                    if (searchbar.visible) {
                        searchentry.grab_focus ();
                    }
                }

                return true;
            });
            add_accel_group (accel_group);

            var builder = new Gtk.Builder.from_resource ("/com/forensant/proximity/app-menu.ui");
            var menu = (MenuModel) builder.get_object ("menu");
            gears.menu_model = menu;

            Notify.init ("com.forensant.proximity");

            WebKit.WebContext.get_default ().set_sandbox_enabled (true);
            // works around a webkit bug
            new WebKit.WebView();

            requests_pane = new RequestsPane (this, true);
            requests_pane.pane_changed.connect(on_pane_changed);
            stack.add_titled (requests_pane, "RequestList", "Requests");
            requests_pane.show ();

            inject_pane = new InjectPane (this);
            inject_pane.pane_changed.connect(on_pane_changed);
            stack.add_titled (inject_pane, "Inject", "Inject");

            new_request = new RequestNew (this);
            new_request.pane_changed.connect(on_pane_changed);
            stack.add_named (new_request, "NewRequest");    

            intercept = new Intercept (this);
            intercept.pane_changed.connect(on_pane_changed);
            stack.add_named (intercept, "Intercept");

            if (core_address != "") {
                on_core_started (core_address);
            }

            core_process.core_started.connect (on_core_started);

            core_process.listener_error.connect ((message) => {
                this.info_bar_bind_error.revealed = true;
                label_proxy_bind_error.label = message.strip () + "  —  Requests are not being intercepted.";
            });

            core_process.copying_file.connect ((started) => {
                if (started) {
                    label_overlay.label = "Saving and copying project file. This may take a few minutes for large projects...";
                }
                label_overlay.visible = started;
            });

            core_process.opening_file.connect ((started) => {
                if (started) {
                    label_overlay.label = "Opening project file. This may take a few minutes for large projects...";
                }
                label_overlay.visible = started;
            });

            if (!process_launched) {
                stdout.printf("Core didn't start\n");
                render_controls (false);
            }

            stdout.printf("Proximity started\n");

            this.delete_event.connect ((e) => {
                if (core_process != null) {
                    saving_dialog = new SavingDialog();
                    this.hide ();
                    saving_dialog.show_all ();

                    core_process.quit (this.on_quit_successful);

                    return true;
                }
                
                return false;
            });
        }

        private void authenticate_user () {
            if (authentication_displayed) {
                return;
            }

            authentication_displayed = true;
            var auth_dlg = new AuthenticationDialog ();
            set_window_icon (auth_dlg);
            var response = auth_dlg.run ();
            auth_dlg.close ();

            if (response != Gtk.ResponseType.OK) {
                // if we can't authenticate, then there's not much more we can do
                application.quit ();
                return;
            }
            else if (response == Gtk.ResponseType.OK) {
                authentication_displayed = false;
                api_key = auth_dlg.api_key;
                label_overlay.hide ();
                on_core_started (core_address);
            }
        }

        public InputStream banner_logo_svg () {
            var file = File.new_for_uri ("resource:///com/forensant/proximity/Logo-banner.svg");

            var contents = "";

            try {
                var dis = new DataInputStream (file.read ());
                string line;
                while ((line = dis.read_line (null)) != null) {
                    contents += line + "\n";
                }
            } catch (Error e) {
                stdout.printf ("Error getting logo: %s\n", e.message);
            }

            var style_context = this.get_style_context ();
            var text_color = style_context.get_color (Gtk.StateFlags.NORMAL);

            contents = contents.replace ("#000000", text_color.to_string ());
            return new GLib.MemoryInputStream.from_data (contents.data);
        }

        private void create_http_session () {
            http_session = new Soup.Session ();

            http_session.request_queued.connect ((msg) => {
                msg.got_headers.connect (() => {
                    if (msg.status_code == 401) {
                        authenticate_user ();
                    }
                });

                var HEADER_FIELD = "X-API-Key";
                if (api_key != "" && msg.request_headers != null && msg.request_headers.get_one (HEADER_FIELD) == null) {
                    msg.request_headers.append (HEADER_FIELD, api_key);
                }
            });
        }

        public void change_pane (string name) {
            stack.set_visible_child_name (name);
        }

        public void display_notification (string title, string message, MainApplicationPane pane, string guid) {
            if (has_toplevel_focus && selected_pane () == pane) {
                return;
            }

            notification = new Notify.Notification(title, message, "dialog-information");

            notification.add_action ("default", "Show", (notification, action) => {
                this.grab_focus ();
                stack.visible_child = (Gtk.Widget)pane;
                pane.set_selected_guid (guid);
            });

            try {
                notification.show ();
            } catch (Error e) {
                stdout.printf("Error displaying notification: %s\n", e.message);
            }
        }

        private void generate_api_key () {
            FileStream stream = FileStream.open ("/dev/urandom", "r");
            uint8[] key_bytes = new uint8[32];
            bool generate_insecure = false;

            if (stream == null) {
                generate_insecure = true;
            }

            if (!generate_insecure) {
                size_t read = stream.read (key_bytes, 1);
                if (read != 32) {
                    generate_insecure = true;
                }
            }

            if (generate_insecure) {
                stderr.printf ("WARNING: Generating insecure API key using non-cryptographic number generator\n");
                for (var i = 0; i < key_bytes.length; i++) {
                    key_bytes[i] = (uint8) Random.int_range(0,255);
                }
            }
            
            api_key = "";

            for (var i = 0; i < key_bytes.length; i++) {
                api_key += key_bytes[i].to_string ("%02X");
            }
        }

        private bool monitor_core_connection () {
            Soup.Session session = new Soup.Session ();
            var message = new Soup.Message ("GET", "http://" + core_address + "/ping");

            session.queue_message (message, (sess, mess) => {
                if (mess.status_code == 200) {
                    if (label_overlay.visible == true || proxy_settings.successful == false) {
                        label_overlay.hide ();
                        on_core_started (core_address);
                    }
                }
                else {
                    // if the proxy settings haven't been successfully loaded, there will be another message already displayed to the user
                    if (label_overlay.visible == false && proxy_settings.successful) {
                        label_overlay.label = "Connection to Proximity Core lost. Retrying...\n\nOnce the connection is re-established, the data will be reloaded.";
                        label_overlay.show ();
                    }
                }
            });

            return Source.CONTINUE;
        }

        [GtkCallback]
        public void on_back_clicked () {
            selected_pane ().on_back_clicked ();
        }

        private void on_core_started (string address) {
            this._core_address = address;
            this.proxy_settings = new ProxySettings (this);

            if (!timeout_started) {
                timeout_started = true;
                Timeout.add_full (Priority.DEFAULT, 5000, monitor_core_connection);
            }

            if (!proxy_settings.unauthenticated) { // the dialog will be shown and will then refresh once it's been authenticated
                render_controls (proxy_settings.successful);
            }
        }

        [GtkCallback]
        public void on_button_search_toggled () {
            combobox_search_protocols.visible = selected_pane ().can_filter_protocols ();
        }

        [GtkCallback]
        public void on_searchentry_stop_search () {
            searchbar.search_mode_enabled = false;
        }

        [GtkCallback]
        public void on_info_bar_bind_error_close () {
            info_bar_bind_error.revealed = false;
        }

        [GtkCallback]
        public void on_info_bar_bind_error_response (int response) {
            // at this point there are no other actions other than closing on the info bar
            on_info_bar_bind_error_close ();
        }

        [GtkCallback]
        public void on_intercept_clicked () {
            stack.visible_child = intercept;
        }

        [GtkCallback]
        public void on_new_clicked () {
            selected_pane ().on_new_clicked ();
        }

        public void on_new_project () {
            core_process.new_project ();
        }

        public void on_open_project () {
            core_process.open_project ();
        }

        public void on_pane_changed () {
            if (stack.in_destruction () || controls_hidden || inject_pane == null) {
                return;
            }

            var pane = selected_pane ();
            button_new.visible  = pane.new_visible ();
            button_new.tooltip_text = pane.new_tooltip_text ();
            button_back.visible = pane.back_visible ();

            var can_search = pane.can_search ();
            button_search.sensitive = can_search;
            combobox_search_protocols.visible = selected_pane ().can_filter_protocols ();

            if (searchbar.visible && !can_search) {
                searchbar.visible = false;
            }

            // special case
            button_intercept.visible = (stack.visible_child == requests_pane);
        }

        private void on_quit_successful () {
            core_process = null;
            saving_dialog.close ();
            this.close ();
        }

        public void on_save_project () {
            core_process.save_project ();
        }

        private void render_controls (bool process_launched) {
            controls_hidden = !process_launched;

            stack.set_visible_child_name ("RequestList");
            reset_state (true);
            requests_pane.process_launch_successful (process_launched);

            if (process_launched) {
                do_update_check ();

                button_new.visible = true;
                button_intercept.visible = true;
                button_back.visible = false;
                gears.visible = true;
                button_search.visible = true;
                inject_pane.visible = true;
            } 
            else {
                button_new.visible = false;
                button_intercept.visible = false;
                button_back.visible = false;
                button_search.visible = false;
                inject_pane.visible = false;
            }
        }

        public void request_double_clicked (string guid) {
            if (settings.get_string ("request-double-click") == "new-request") {
                send_to_new_request (guid);
            } else {
                send_to_inject (guid);
            }
        }

        private void reset_state (bool launch_successful) {
            if (launch_successful) {
                stack.@foreach ( (widget) => {
                    var pane = (MainApplicationPane) widget;
                    pane.reset_state ();
                });

                new_request.reset_state ();
                intercept.reset_state ();
            }
            else {
                var msgbox = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "Error: Could not open the file.");
                msgbox.run ();
                core_process.open (null);
            }
        }

        [GtkCallback]
        public void search_text_changed () {
            selected_pane ().on_search (searchentry.get_text (),
                check_button_exclude_resources.get_active (),
                combobox_search_protocols.get_active_id ()
            );
        }

        private MainApplicationPane selected_pane () {
            return (MainApplicationPane) stack.visible_child;
        }

        public string selected_pane_name () {
            return stack.visible_child_name;
        }

        public void send_to_inject (string guid) {
            stack.visible_child = inject_pane;
            inject_pane.on_new_inject_operation (guid);
        }

        public void send_to_new_request (string guid) {
            stack.visible_child = new_request;
            new_request.populate_request (guid);
        }

        private void set_window_icon (Gtk.Window window) {
            var icons = new List<Gdk.Pixbuf> ();
            try {
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo256.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo128.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo64.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo48.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo32.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo16.png"));
            } catch (Error err) {
                stdout.printf ("Could not create icon pack");
                return;
            }

            window.set_icon_list (icons);
        }

        private void do_update_check () {
            var url = UPDATE_HOST + "/api/application/updates?edition=Community&version=" + Application.VERSION;

            Soup.Session session = new Soup.Session ();
            var message = new Soup.Message ("GET", url);
            
            session.queue_message (message, (sess, mess) => {
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data ((string)mess.response_body.data);
                    if (parser.get_root () == null) {
                        return;
                    }
                    var root_object = parser.get_root ().get_object ();
                    var should_update = root_object.get_boolean_member ("ShouldUpdate");
                    
                    if (should_update) {
                        if (!this.info_bar_bind_error.revealed) {
                            this.info_bar_bind_error.revealed = true;
                            label_proxy_bind_error.label = "An update is available, visit <a href=\"https://proximityhq.com/\">https://proximityhq.com/</a> to download it.";
                        }
                    }
                }
                catch (GLib.Error err) {
                    stdout.printf("Error checking for updates: %s\n", err.message);
                }
            });
        }
    }
}
