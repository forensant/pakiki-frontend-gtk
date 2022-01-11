using Notify;

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
        private unowned Gtk.ToggleButton button_search;
        [GtkChild]
        private unowned Gtk.CheckButton check_button_exclude_resources;
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

        public string core_address;
        public string preview_proxy_address;

        private Application proximity_application;
        private bool controls_hidden;
        private CoreProcess core_process;
        //private int core_process_timer;
        private InjectPane inject_pane;
        private Intercept intercept;
        private Gtk.Label label_connection_lost;
        private RequestNew new_request;
        private RequestsPane requests_pane;
        private GLib.Settings settings;

        private Notify.Notification notification;

        public ApplicationWindow (Application application, string core_address, string preview_proxy_address) {
            GLib.Object (application: application);
            core_process = new CoreProcess (this);
            this.proximity_application = application;
            this.core_address = core_address;
            this.preview_proxy_address = preview_proxy_address;

            var process_launched = true;
            if (core_address == "") {
                process_launched = core_process.open (null);
            }

            stack.notify.connect ( (s, property) => {
                if (property.name == "visible-child") {
                    on_pane_changed ();
                }
            });

            label_connection_lost = new Gtk.Label ("Connection to Proximity Core lost. Retrying...\n\nOnce the connection is re-established, the data will be reloaded.");
            label_connection_lost.name = "lbl_connection_lost";
            overlay.add_overlay (label_connection_lost);
            
            settings = new GLib.Settings ("com.forensant.proximity");
            
            button_search.bind_property ("active", searchbar, "search-mode-enabled",
                                  GLib.BindingFlags.BIDIRECTIONAL);

            button_search.bind_property ("active", searchbar, "visible",
                                  GLib.BindingFlags.BIDIRECTIONAL);

            searchbar.visible = false;

            var builder = new Gtk.Builder.from_resource ("/com/forensant/proximity/app-menu.ui");
            var menu = (MenuModel) builder.get_object ("menu");
            gears.menu_model = menu;

            Notify.init ("Proximity");

            WebKit.WebContext.get_default ().set_sandbox_enabled (true);

            // works around a webkit bug
            new WebKit.WebView();

            if (core_address != "") {
                on_core_started (core_address);
            }

            core_process.core_started.connect (on_core_started);

            core_process.listener_error.connect ((message) => {
                this.info_bar_bind_error.revealed = true;
                label_proxy_bind_error.label = message.strip () + "  —  Requests are not being intercepted.";
            });

            if (process_launched == true) {
                Timeout.add_full (Priority.DEFAULT, 5000, monitor_core_connection);
            }
            else {
                stdout.printf("Core didn't start\n");
                render_controls (false);
            }
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

        public void hide_controls () {
            controls_hidden = true;
            button_new.visible = false;
            button_intercept.visible = false;
            button_back.visible = false;
            gears.visible = false;
            button_search.visible = false;
            if (inject_pane != null) {
                stack.remove (inject_pane);
                inject_pane = null;
            }
        }

        private bool monitor_core_connection () {
            Soup.Session session = new Soup.Session ();
            var message = new Soup.Message ("GET", "http://" + core_address + "/proxy/ping");

            session.queue_message (message, (sess, mess) => {
                if (mess.status_code == 200) {
                    if (label_connection_lost.visible == true) {
                        label_connection_lost.hide ();
                        reset_state (true);
                    }
                }
                else {
                    if (label_connection_lost.visible == false) {
                        label_connection_lost.show ();
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
            this.core_address = address;
            stdout.printf("Core started on address: %s, Resetting state\n", address);
            render_controls (true);
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

            stack.transition_type = Gtk.StackTransitionType.NONE;

            var request_pane_child = stack.get_child_by_name ("RequestList");
            if (request_pane_child != null) {
                stack.remove (request_pane_child);
            }

            var inject_pane_child = stack.get_child_by_name ("Inject");
            if (inject_pane_child != null) {
                stack.remove (inject_pane_child);
            }

            requests_pane = new RequestsPane (this, process_launched);
            requests_pane.pane_changed.connect(on_pane_changed);
            requests_pane.show ();
            stack.add_titled (requests_pane, "RequestList", "Requests");
            
            if (process_launched) {
                inject_pane = new InjectPane (this);
                inject_pane.show ();
                inject_pane.pane_changed.connect(on_pane_changed);
                stack.add_titled (inject_pane, "Inject", "Inject");

                if (stack.get_child_by_name ("NewRequest") == null) {
                    new_request = new RequestNew (this);
                    new_request.pane_changed.connect(on_pane_changed);
                    stack.add_named (new_request, "NewRequest");    
                } else {
                    new_request.reset_state ();
                }
                
                if (stack.get_child_by_name ("Intercept") == null) {
                    intercept = new Intercept (this);
                    intercept.pane_changed.connect(on_pane_changed);
                    stack.add_named (intercept, "Intercept");
                } else {
                    intercept.reset_state ();
                }

                button_new.visible = true;
                button_intercept.visible = true;
                button_back.visible = false;
                gears.visible = true;
                button_search.visible = true;
                stack.set_visible_child_name ("RequestList");
            }

            stack.transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT;
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
            }
        }

        [GtkCallback]
        public void search_text_changed () {
            selected_pane ().on_search (searchentry.get_text (), check_button_exclude_resources.get_active ());
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
    }
}
