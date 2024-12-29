using Notify;

namespace Pakiki {

    [GtkTemplate (ui = "/com/forensant/pakiki/window.ui")]
    public class ApplicationWindow : Gtk.ApplicationWindow {
        public const string UPDATE_HOST = "https://pakikiproxy.com";

        public signal void settings_changed ();

        [GtkChild]
        private unowned Gtk.Button button_back;
        [GtkChild]
        private unowned Gtk.Button button_intercept;
        [GtkChild]
        private unowned Gtk.Button button_new;
        [GtkChild]
        private unowned Gtk.ToggleButton button_filter;
        [GtkChild]
        private unowned Gtk.CheckButton check_button_exclude_resources;
        [GtkChild]
        private unowned Gtk.CheckButton check_button_negative_filter;
        [GtkChild]
        private unowned Gtk.ComboBoxText combobox_search_protocols;
        [GtkChild]
        private unowned Gtk.MenuButton gears;
        [GtkChild]
        private unowned Gtk.Image image_filter_icon;
        [GtkChild]
        private unowned Gtk.InfoBar info_bar_bind_error;
        [GtkChild]
        private unowned Gtk.Label label_intercept;
        [GtkChild]
        private unowned Gtk.Label label_proxy_bind_error;
        [GtkChild]
        private unowned Gtk.Overlay overlay;
        [GtkChild]
        private unowned Gtk.Popover popover_filter;
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
        public GLib.Settings settings;

        private bool authentication_displayed;
        private bool controls_hidden;
        private CoreProcess core_process;
        private InjectPane inject_pane;
        private Intercept intercept;
        private Gtk.Label label_overlay;
        private RequestNew new_request;
        private Application pakiki_application;
        private RequestsPane requests_pane;
        private SavingDialog saving_dialog;
        private bool timeout_started;

        private Notify.Notification notification;

        public ApplicationWindow (Application application, string core_address, string preview_proxy_address, string api_key) {
            GLib.Object (application: application);
            this.api_key = api_key;
            if (api_key == "") {
                generate_api_key ();
            }

            this.pakiki_application = application;
            this.set_title ("Pākiki Proxy");
            core_process = new CoreProcess (this, this.api_key);
            this.authentication_displayed = false;
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

            settings = new GLib.Settings ("com.forensant.pakiki");
            init_crash_reporting ();

            var app = get_application ();

            var find_action = new SimpleAction("find-shortcut", null);
            find_action.activate.connect (() => {
                var pane = selected_pane ();
                if (pane != null && pane.find_activated ()) {
                    // do nothing - as find has been activated
                }
                else if (pane == null || pane.can_search ()) {
                    button_filter.active = !button_filter.active;
                }
            });
            app.add_action (find_action);
            app.set_accels_for_action ("app.find-shortcut", new string[] {"<Ctrl>F"});
            
            });
            add_accel_group (accel_group);

            var builder = new Gtk.Builder.from_resource ("/com/forensant/pakiki/app-menu.ui");
            var menu_model = (GLib.Menu) builder.get_object ("menu");
            GlobalActions.get_instance(this);
            
            if (!is_sandboxed ()) {
                var section = new GLib.Menu() ;
                section.append ( "Open _Browser", "app.open-browser");
                
                menu_model.append_section(null, section);
            }
            
            gears.menu_model = menu_model;

            Notify.init ("com.forensant.pakiki");

            set_filter_icon ();

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

            this.close_request.connect (() => {
                if (core_process != null) {
                    saving_dialog = new SavingDialog();
                    saving_dialog.set_transient_for(this);
                    this.hide ();
                    saving_dialog.show ();

                    var quitting = core_process.quit (this.on_quit_successful);

                    return quitting;
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
            return get_coloured_svg("resource:///com/forensant/pakiki/Logo-banner.svg");
        }

        private void create_http_session () {
            http_session = new Soup.Session ();
            http_session.proxy_resolver = null;
            
            http_session.request_queued.connect ((msg) => {
                msg.got_headers.connect (() => {
                    var host = msg.uri.get_host ();
                    if (host == null) {
                        host = "";
                    }
                    if (msg.status_code == 401 && !host.contains ("pakikiproxy.com")) {
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
                stderr.printf("Error displaying notification: %s\n", e.message);
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

        private InputStream get_coloured_svg (string uri) {
            var file = File.new_for_uri (uri);

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

        public void init_crash_reporting () {
            Crashpad.setup (
                "/tmp",
                "Pākiki Proxy - Community",
                pakiki_application.get_version (),
                "https://sentry.pakikiproxy.com/api/7/minidump/?sentry_key=b46351d9d014caa8c9f6de4a9dfcf634",
                "");

            bool report = settings.get_boolean ("crash-reports");
            Crashpad.set_automatic_reporting ("/tmp", report);
            set_core_crash_reporting ();
        }

        public bool is_sandboxed () {
            File file = File.new_for_path ("/.flatpak-info");
            return file.query_exists ();
        }

        private bool monitor_core_connection () {
            Soup.Session session = new Soup.Session ();
            session.proxy_resolver = null;
            var message = new Soup.Message ("GET", "http://" + core_address + "/ping");
            
            session.send_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    session.send_async.end (res);

                    if (message.status_code == 200) {
                        if (label_overlay.visible == true || proxy_settings.successful == false) {
                            label_overlay.hide ();
                            on_core_started (core_address);
                        }
                    }
                    else {
                        throw new IOError.CONNECTION_REFUSED ("Server did not respond with 200 status code");
                    }
                } catch (Error e) {
                    stdout.printf ("Error monitoring core connection: %s\n", e.message);
                    
                    // if the proxy settings haven't been successfully loaded, there will be another message already displayed to the user
                    if (label_overlay.visible == false && proxy_settings.successful) {
                        label_overlay.label = "Connection to Pākiki Core lost. Retrying...\n\nOnce the connection is re-established, the data will be reloaded.";
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
            set_core_crash_reporting ();
            this.proxy_settings = new ProxySettings (this);

            var action = new SimpleAction ("preferences", null);
            action.activate.connect (on_show_preferences);
            application.add_action (action);

            if (!timeout_started) {
                timeout_started = true;
                Timeout.add_full (Priority.DEFAULT, 5000, monitor_core_connection);
            }

            if (!proxy_settings.unauthenticated) { // the dialog will be shown and will then refresh once it's been authenticated
                render_controls (proxy_settings.successful);
            }
        }

        [GtkCallback]
        public void on_button_filter_toggled () {
            combobox_search_protocols.visible = selected_pane ().can_filter_protocols ();
            if (!button_filter.active) { // state we're changing from
                popover_filter.popdown ();
            } else {
                popover_filter.popup ();
                searchentry.grab_focus ();
            }
        }

        [GtkCallback]
        public void on_popover_filter_closed () {
            button_filter.active = false;
        }

        [GtkCallback]
        public void on_searchentry_stop_search () {
            button_filter.active = false;
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

        public void on_open_browser () {
            var browser_path = this.browser_path ();

            if (browser_path == "") {
                var msgbox = new Gtk.MessageDialog (this,
                    Gtk.DialogFlags.MODAL,
                    Gtk.MessageType.WARNING,
                    Gtk.ButtonsType.CLOSE,
                    "Chromium could not be found.\nOn Kali can be installed with `sudo apt install chromium`");
                msgbox.run ();
                msgbox.destroy ();
                return;
            }

            var configdir = writeBrowserConfig ();
            stdout.printf("Config dir: %s\n", configdir);

            string[] spawn_args = {
                browser_path,
                "--temp-profile",
                "--no-first-run",
                "--ignore-certificate-errors",
                "--test-type",
                "--install-autogenerated-theme=216,239,217",
                "--no-events",
                "--profile-dir=" + configdir,
                "--proxy-server=" + this.proxy_settings.local_proxy_address (),
                "--proxy-bypass-list=<-loopback>;"+core_address,
                "--disable-default-apps",
                "--disable-breakpad",
                "--disable-crash-reporter",
                "--disk-cache-size=0",
                "--no-default-browser-check",
                "--no-pings",
                "--no-service-autorun",
                "--media-cache-size=0",
                "--use-mock-keychain",
                "--no-default-browser-check",
                "--disable-features=Translate",
                "--password-store=basic",
                "--disable-background-networking",
                "--disable-sync",
                "--metrics-recording-only",
                "--disable-features=MediaRouter",
                "--disable-features=OptimizationGuideModelDownloading,OptimizationHintsFetching,OptimizationTargetPrediction,OptimizationHints",
                "http://" + core_address + "/browser_home/",
            };

            string[] spawn_env = Environ.get ();
            Pid child_pid;

            try {
                Process.spawn_async (null,
                    spawn_args,
                    spawn_env,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    null,
                    out child_pid);
            } catch (Error e) {
                stdout.printf ("Error launching browser: %s\n", e.message);
                return;
            }

            ChildWatch.add (child_pid, (pid, status) => {
                // Triggered when the child indicated by child_pid exits
                Process.close_pid (pid);
            });
        }

        public string browser_path () {
            File file = File.new_for_path ("/usr/bin/chromium");
            if (file.query_exists ()) {
                return "/usr/bin/chromium";
            }

            file = File.new_for_path ("/usr/bin/chromium-browser");
            if (file.query_exists ()) {
                return "/usr/bin/chromium-browser";
            }

            return "";
        }

        public void launch_documentation (string path = "/") {
            var url = "https://docs.pakikiproxy.com";
            if (core_address != "") {
                url = "http://" + core_address + "/docs";
            }

            url += path;

            var doc_window = new Gtk.Window (Gtk.WindowType.TOPLEVEL);
            doc_window.set_default_size (1280, 768);
            doc_window.set_title ("Pākiki Proxy Help");
            
            var web_view = new WebKit.WebView ();
            var data_manager = web_view.get_website_data_manager ();
            data_manager.set_network_proxy_settings (WebKit.NetworkProxyMode.NO_PROXY, null);

            web_view.load_uri (url);
            doc_window.add (web_view);

            doc_window.show_all ();
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
            button_new.label = pane.new_name ();
            button_new.tooltip_text = pane.new_tooltip_text ();
            button_back.visible = pane.back_visible ();

            var can_search = pane.can_search ();
            button_filter.sensitive = can_search;
            combobox_search_protocols.visible = selected_pane ().can_filter_protocols ();

            if (popover_filter.visible && !can_search) {
                button_filter.active = false;
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

        private void on_show_preferences () {
            var prefs = new ApplicationPreferences (this);
            prefs.settings_changed.connect (() => {
                settings_changed (); 
            });
            prefs.present ();
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
                button_filter.visible = true;
                inject_pane.visible = true;
            } 
            else {
                button_new.visible = false;
                button_intercept.visible = false;
                button_back.visible = false;
                button_filter.visible = false;
                inject_pane.visible = false;
            }
        }

        public void request_double_clicked (string guid, bool is_http) {
            var behaviour = settings.get_string ("request-double-click");

            if (!is_http || behaviour == "new-window") {
                var win = new RequestWindow (this, guid);
                win.show ();
                return;
            }

            switch (behaviour) {
            case "new-request":
                send_to_new_request (guid);
                break;
            case "inject":
                send_to_inject (guid);
                break;
            default:
                stdout.printf("Unknown double-click behaviour setting: %s\n", behaviour);
                break;
            }
        }

        private void reset_state (bool launch_successful) {
            if (launch_successful) {
                foreach (var pane in child_panes) {
                    pane.reset_state ();
                }
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
                check_button_negative_filter.get_active (),
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

        private void set_core_crash_reporting () {
            if (core_address == "") {
                return;
            }

            var enabled = settings.get_boolean ("crash-reports") ? "true" : "false";
            var url = "http://" + core_address + "/crash_reporting?enabled=" + enabled;
            var message = new Soup.Message ("GET", url);
            this.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }

        private void set_filter_icon () {
            var image_src = this.get_coloured_svg ("resource:///com/forensant/pakiki/funnel-outline-symbolic.svg");
            try {
                image_filter_icon.pixbuf = new Gdk.Pixbuf.from_stream (image_src);
            } catch (Error e) {
                stdout.printf ("Error setting filter icon: %s\n", e.message);
            }
        }

        public void set_intercepted_request_count(int count) {
            if (count > 0) {
                label_intercept.label = "<b>_Intercept (" + count.to_string () + ")</b>";
            }
            else {
                label_intercept.label = "_Intercept";
            }
        }

        private void set_window_icon (Gtk.Window window) {
            var icons = new List<Gdk.Pixbuf> ();
            try {
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/pakiki/Logo256.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/pakiki/Logo128.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/pakiki/Logo64.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/pakiki/Logo48.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/pakiki/Logo32.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/pakiki/Logo16.png"));
            } catch (Error err) {
                stdout.printf ("Could not create icon pack");
                return;
            }

            window.set_icon_list (icons);
        }

        private string writeBrowserConfig() {
            // generate a temporary path
            try {
                CoreProcess.create_temp_dir ();
                var basedir = GLib.DirUtils.make_tmp ("pakiki-XXXXXX");

                var dir = basedir + "/chromedata/Default/";
                GLib.DirUtils.create_with_parents (dir, 448); // 448 == 0700 in octal
                
                var file = File.new_for_uri ("resource:///com/forensant/pakiki/chrome-preferences.json");
                var contents = "";

                var dis = new DataInputStream (file.read ());
                string line;
                while ((line = dis.read_line (null)) != null) {
                    contents += line + "\n";
                }
                
                var filepath = dir + "Preferences";
            
                var f = File.new_for_path (filepath);
                {
                    // write the string into the file
                    
                    var file_stream = f.create (FileCreateFlags.NONE);
                    var data_stream = new DataOutputStream (file_stream);
                    data_stream.put_string (contents);
                }

                return basedir + "/chromedata/";
            } catch (Error e) {
                stdout.printf ("Error writing browser config: %s\n", e.message);
            }

            return "";
        }

        private void do_update_check () {
            var url = UPDATE_HOST + "/api/application/updates?edition=Community&version=" + pakiki_application.get_version ();
            var message = new Soup.Message ("GET", url);
            
            http_session.send_and_read_async.begin (message, GLib.Priority.DEFAULT, null, (obj, res) => {
                try {
                    var bytes = http_session.send_and_read_async.end (res);

                    var parser = new Json.Parser ();
                    parser.load_from_data ((string)bytes.get_data ());
                    if (parser.get_root () == null) {
                        return;
                    }
                    var root_object = parser.get_root ().get_object ();
                    var should_update = root_object.get_boolean_member ("ShouldUpdate");
                    
                    if (should_update) {
                        if (!this.info_bar_bind_error.revealed) {
                            this.info_bar_bind_error.revealed = true;
                            label_proxy_bind_error.label = "An update is available, visit <a href=\"https://pakikiproxy.com/\">https://pakikiproxy.com/</a> to download it.";
                        }
                    }
                } catch (Error err) {
                    stdout.printf("Error checking for updates: %s\n", err.message);
                }
            });
        }
    }
}
