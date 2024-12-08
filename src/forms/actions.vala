namespace Pakiki {
    public class GlobalActions : GLib.Object {

        private static GlobalActions? instance;
        private ApplicationWindow application_window;
        private List<GLib.SimpleAction> actions;

        private GlobalActions (ApplicationWindow window) {
            this.application_window = window;


            var open_browser_action = new GLib.SimpleAction ("open-browser", null);
            open_browser_action.activate.connect (on_open_browser);
            application_window.application.add_action (open_browser_action);
        }

        public static GlobalActions get_instance (ApplicationWindow window) {
            if (instance == null) {
                instance = new GlobalActions (window);
            }
            return instance;
        }


        private void on_open_browser (GLib.Variant? parameter) {
            application_window.on_open_browser ();
        }
    }
}