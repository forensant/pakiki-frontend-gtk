namespace Pakiki {
    public class GlobalActions : GLib.Object {

        private static GlobalActions? instance;
        private ApplicationWindow application_window;
        private List<GLib.SimpleAction> actions;

        private GlobalActions (ApplicationWindow window) {
            this.application_window = window;
            var app = window.application;

            actions = new List<GLib.SimpleAction> ();

            var new_window_action = new GLib.SimpleAction ("new-window", VariantType.STRING);
            new_window_action.activate.connect (on_new_window);
            actions.append (new_window_action);
            app.add_action (new_window_action);

            var new_request_action = new GLib.SimpleAction ("new-request", VariantType.STRING);
            new_request_action.activate.connect (on_new_request);
            actions.append (new_request_action);
            app.add_action (new_request_action);

            var inject_action = new GLib.SimpleAction ("inject", VariantType.STRING);
            inject_action.activate.connect (on_inject_request);
            actions.append (inject_action);
            app.add_action (inject_action);

            var copy_url_action = new GLib.SimpleAction ("copy-url", VariantType.STRING);
            copy_url_action.activate.connect (on_copy_url);
            actions.append (copy_url_action);
            app.add_action (copy_url_action);

            var open_in_browser_action = new GLib.SimpleAction ("open-in-browser", VariantType.STRING);
            open_in_browser_action.activate.connect (on_open_in_browser);
            actions.append (open_in_browser_action);
            app.add_action (open_in_browser_action);

            var open_browser_action = new GLib.SimpleAction ("open-browser", null);
            open_browser_action.activate.connect (on_open_browser);
            app.add_action (open_browser_action);
        }

        public static GlobalActions get_instance (ApplicationWindow window) {
            if (instance == null) {
                instance = new GlobalActions (window);
            }
            return instance;
        }

        public void set_enabled (string name, bool enabled) {
            foreach (var action in actions) {
                if (action.name == name) {
                    action.set_enabled (enabled);
                    break;
                }
            }
        }

        private void on_new_window (GLib.Variant? parameter) {
            var win = new RequestWindow (application_window, parameter.get_string ());
            win.show ();
        }

        private void on_new_request (GLib.Variant? parameter) {
            application_window.send_to_new_request (parameter.get_string ());
        }

        private void on_inject_request (GLib.Variant? parameter) {
            application_window.send_to_inject (parameter.get_string ());
        }

        private void on_copy_url (GLib.Variant? parameter) {
            var clipboard = application_window.get_clipboard ();
            clipboard.set_text (parameter.get_string ());
        }

        private void on_open_in_browser (GLib.Variant? parameter) {
            try {
                AppInfo.launch_default_for_uri (parameter.get_string (), null);
            } catch (Error err) {
                stdout.printf ("Could not launch browser: %s\n", err.message);
            }
        }

        private void on_open_browser (GLib.Variant? parameter) {
            application_window.on_open_browser ();
        }
    }
}