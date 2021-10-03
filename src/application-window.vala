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

        private bool controls_hidden;
        private CoreProcess core_process;
        private int core_process_timer;
        private InjectPane inject_pane;
        private Intercept intercept;
        private RequestNew new_request;
        private RequestsPane requests_pane;
        private GLib.Settings settings;

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

        public void change_pane (string name) {
            stack.set_visible_child_name (name);
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
                request.send ();
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

        public void hide_controls () {
            controls_hidden = true;
            button_new.visible = false;
            button_intercept.visible = false;
            button_back.visible = false;
            gears.visible = false;
            button_search.visible = false;
            stack.remove (inject_pane);
        }

        [GtkCallback]
        public void on_back_clicked () {
            selected_pane ().on_back_clicked ();
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

        public void on_new_project_open () {
            // sometimes it takes a while for the process to launch, so wait until we can establish comms with it
            Timeout.add_full (Priority.DEFAULT, 10, check_core_launched_subsequent_launch);
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
            button_back.visible = pane.back_visible ();

            var can_search = pane.can_search ();
            button_search.sensitive = can_search;

            if (searchbar.visible && !can_search) {
                searchbar.visible = false;
            }

            // special case
            button_intercept.visible = (stack.visible_child == requests_pane);
        }

        public void on_save_project () {
            core_process.save_project ();
        }

        private void render_controls (bool process_launched) {
            controls_hidden = !process_launched;

            requests_pane = new RequestsPane (this, process_launched);
            requests_pane.show ();
            stack.add_titled (requests_pane, "RequestList", "Requests");
            
            if (process_launched) {
                inject_pane = new InjectPane (this);
                inject_pane.show ();
                stack.add_titled (inject_pane, "Inject", "Inject");

                new_request = new RequestNew (this);
                stack.add_named (new_request, "NewRequest");

                intercept = new Intercept (this);
                stack.add_named (intercept, "Intercept");
            }

            stack.@foreach ((w) => {
                var pane = (MainApplicationPane) w;
                pane.pane_changed.connect(on_pane_changed);
            });
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
            selected_pane ().on_search (searchentry.get_text (), checkButtonExcludeResources.get_active ());
        }

        private MainApplicationPane selected_pane () {
            return (MainApplicationPane) stack.visible_child;
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
        public void visible_child_changed () {
            on_pane_changed ();
        }
    }
}
