namespace Proximity {

    [GtkTemplate (ui = "/com/forensant/proximity/window.ui")]
    public class ApplicationWindow : Gtk.ApplicationWindow {

        [GtkChild]
        private unowned Gtk.Button button_back;
        [GtkChild]
        private unowned Gtk.Button button_intercept;
        [GtkChild]
        private unowned Gtk.Button button_new;
        [GtkChild]
        private unowned Gtk.Stack stack;
        [GtkChild]
        private unowned Gtk.MenuButton gears;
        [GtkChild]
        private unowned Gtk.CheckButton checkButtonExcludeResources;
        [GtkChild]
        private unowned Gtk.ToggleButton button_search;
        [GtkChild]
        private unowned Gtk.SearchBar searchbar;
        [GtkChild]
        private unowned Gtk.SearchEntry searchentry;

        private GLib.Settings settings;
        private InjectPane inject_pane;
        private RequestList request_list;
        private RequestNew new_request;
        private CoreProcess core_process;
        private bool controls_hidden;
        private int core_process_timer;

        public ApplicationWindow (Gtk.Application application) {
            GLib.Object (application: application);

            core_process = new CoreProcess (this);
            var process_launched = core_process.open (null);

            settings = new GLib.Settings ("com.forensant.proximity");
            
            button_search.bind_property ("active", searchbar, "search-mode-enabled",
                                  GLib.BindingFlags.BIDIRECTIONAL);

            button_search.bind_property ("active", searchbar, "visible",
                                  GLib.BindingFlags.BIDIRECTIONAL);

            searchbar.visible = false;

            //var gtk_settings = Gtk.Settings.get_default ();
            //gtk_settings.gtk_application_prefer_dark_theme = true;

            var builder = new Gtk.Builder.from_resource ("/com/forensant/proximity/app-menu.ui");
            var menu = (MenuModel) builder.get_object ("menu");
            gears.menu_model = menu;

            // works around a webkit bug
            //new WebKit.WebView();

            if (process_launched == true) {
                // sometimes it takes a while for the process to launch, so wait until we can establish comms with it
                Timeout.add_full (Priority.DEFAULT, 10, check_core_launched_first_launch);
            }
            else {
                render_controls (false);
            }
        }

        private bool check_core_launched_first_launch () {
            return check_core_process_launched (render_controls);
        }

        private bool check_core_launched_subsequent_launch () {
            return check_core_process_launched (reset_state);
        }

        delegate void OnProcessLaunched (bool successful);
        private bool check_core_process_launched (OnProcessLaunched on_process_launched) {
            var successful = true;
            try {
                Soup.Session session = new Soup.Session ();
                Soup.Request request = session.request ("http://localhost:10101/proxy/ca_certificate.pem");
                InputStream stream = request.send ();
            } catch (Error e) {
                successful = false;
            }

            core_process_timer += 1;
            if (core_process_timer > 50 || successful) {
                on_process_launched (successful);
                return Source.REMOVE;
            }
            return Source.CONTINUE;
        }

        private void render_controls (bool process_launched) {
            controls_hidden = !process_launched;

            request_list = new RequestList (this);
            request_list.show ();
            request_list.set_processed_launched (process_launched);
            stack.add_titled (request_list, "RequestList", "Requests");
            
            if (process_launched) {
                inject_pane = new InjectPane (this);
                inject_pane.show ();
                stack.add_titled (inject_pane, "Inject", "Inject");

                new_request = new RequestNew (this);
                stack.add_named (new_request, "NewRequest");
            }
        }

        public void hide_controls () {
            controls_hidden = true;
            button_new.visible = false;
            button_intercept.visible = false;
            button_back.visible = false;
            gears.visible = false;
            button_search.visible = false;
            stack.remove (inject_pane);
        }

        public void on_new_project () {
            core_process.new_project ();
        }

        public void on_open_project () {
            core_process.open_project ();
        }

        public void on_save_project () {
            core_process.save_project ();
        }

        public void send_to_inject (string guid) {
            stack.visible_child = inject_pane;
            inject_pane.on_new_inject_operation (guid);
        }

        public void send_to_new_request (string guid) {
            stack.visible_child = new_request;
            new_request.populate_request (guid);
        }

        [GtkCallback]
        public void on_back_clicked () {
            if (stack.visible_child == new_request) {
                stack.visible_child = request_list;
            }
        }

        [GtkCallback]
        public void on_intercept_clicked () {
            var messagedialog = new Gtk.MessageDialog (this,
                Gtk.DialogFlags.MODAL,
                Gtk.MessageType.WARNING,
                Gtk.ButtonsType.OK,
                "This has not been implemented yet.");

            messagedialog.response.connect ( () => {
                messagedialog.close ();
            });

            messagedialog.show ();
        }

        [GtkCallback]
        public void on_new_clicked () {
            if (stack.visible_child == request_list) {
                stack.visible_child = new_request;
            } else if (stack.visible_child == inject_pane) {
                inject_pane.on_new_inject_operation ();
            }
        }

        public void request_double_clicked (string guid) {
            if (settings.get_string ("request-double-click") == "new-request") {
                send_to_new_request (guid);
            } else {
                send_to_inject (guid);
            }
        }

        public void on_new_project_open () {
            // sometimes it takes a while for the process to launch, so wait until we can establish comms with it
            Timeout.add_full (Priority.DEFAULT, 10, check_core_launched_subsequent_launch);
        }

        private void reset_state (bool launch_successful) {
            if (launch_successful) {
                inject_pane.reset_state ();
                new_request.reset_state ();
                request_list.reset_state ();
            }
            else {
                var msgbox = new Gtk.MessageDialog (this, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.OK, "Error: Could not open the file.");
                msgbox.run ();
                core_process.open (null);
                Timeout.add_full (Priority.DEFAULT, 10, check_core_launched_subsequent_launch);
            }
        }

        [GtkCallback]
        public void search_text_changed () {
            request_list.on_search (searchentry.get_text (), checkButtonExcludeResources.get_active ());
            inject_pane.on_search  (searchentry.get_text (), checkButtonExcludeResources.get_active ());
        }

        [GtkCallback]
        public void visible_child_changed () {
            if (stack.in_destruction () || controls_hidden)
                return;

            button_intercept.visible = (stack.visible_child == request_list);
            button_new.visible = (stack.visible_child == request_list || (stack.visible_child == inject_pane && !inject_pane.new_shown ()));
            button_back.visible = (stack.visible_child == new_request);

            var can_search = (inject_pane.can_search () || stack.visible_child == request_list);
            button_search.sensitive = can_search;

            if (searchbar.visible && !can_search) {
                searchbar.visible = false;
            }
        }
    }
}
