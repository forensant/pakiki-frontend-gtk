namespace Pakiki {

    public class DoubleClickMapping : GLib.Object {
        public string action { get; set; }
        public string name { get; set; }

        public DoubleClickMapping (string action, string name) {
            this.action = action;
            this.name = name;
        }
    }

    [GtkTemplate (ui = "/com/forensant/pakiki/prefs.ui")]
    public class ApplicationPreferences : Gtk.Window {
        public signal void settings_changed ();

        private GLib.Settings settings;
        private ProxySettings proxy_settings;

        [GtkChild]
        private unowned Gtk.CheckButton checkbutton_crash_reports;
        [GtkChild]
        private unowned Gtk.DropDown dropdown_colour_scheme;
        [GtkChild]
        private unowned Gtk.DropDown dropdown_request_doubleclick;
        [GtkChild]
        private unowned Gtk.Entry entry_connections_per_host;
        [GtkChild]
        private unowned Gtk.Entry entry_proxy_address;
        [GtkChild]
        private unowned Gtk.Entry entry_upstream_proxy;
        [GtkChild]
        private unowned Gtk.Label label_error;

        private ApplicationWindow application_window;
        private GLib.ListStore liststore_colour_schemes;
        private GLib.ListStore liststore_request_doubleclick;

        public ApplicationPreferences(ApplicationWindow window) {
            this.application_window = window;
            settings = new GLib.Settings("com.forensant.pakiki");

            liststore_colour_schemes = new GLib.ListStore(typeof(GtkSource.StyleScheme));
            var style_manager = GtkSource.StyleSchemeManager.get_default();
            foreach(string id in style_manager.get_scheme_ids ()) {
                var scheme = style_manager.get_scheme (id);
                liststore_colour_schemes.append (scheme);
            }

            dropdown_colour_scheme.expression = new Gtk.CClosureExpression (typeof (string), null, null, (Callback) get_colour_scheme_name, null, null);
            dropdown_colour_scheme.set_model (liststore_colour_schemes);
            set_colour_scheme ((string) settings.get_value ("colour-scheme"));
            dropdown_colour_scheme.notify.connect ((paramSpec) => {
                if (paramSpec.name == "selected") {
                    settings.set_value("colour-scheme", get_selected_colour_scheme ());
                    settings_changed ();
                }
            });

            liststore_request_doubleclick = new GLib.ListStore (typeof (DoubleClickMapping));
            liststore_request_doubleclick.append (new DoubleClickMapping ("new-request", "New Request"));
            liststore_request_doubleclick.append (new DoubleClickMapping ("inject", "Inject"));
            liststore_request_doubleclick.append (new DoubleClickMapping ("new-window", "Open in New Window"));

            dropdown_request_doubleclick.expression = new Gtk.CClosureExpression (typeof (string), null, null, (Callback) get_doubleclick_name, null, null);
            dropdown_request_doubleclick.set_model (liststore_request_doubleclick);
            set_request_doubleclick (settings.get_string ("request-double-click"));
            dropdown_request_doubleclick.notify.connect ((paramSpec) => {
                if (paramSpec.name == "selected") {
                    var mapping = liststore_request_doubleclick.get_item (dropdown_request_doubleclick.selected) as DoubleClickMapping;
                    if (mapping == null) {
                        return;
                    }

                    settings.set_string ("request-double-click", mapping.action);
                    settings_changed ();
                }
            });

            checkbutton_crash_reports.active = settings.get_boolean ("crash-reports");
            
            proxy_settings = new ProxySettings (window);
            entry_proxy_address.text = proxy_settings.proxy_address;
            entry_upstream_proxy.text = proxy_settings.upstream_proxy_address;
            entry_connections_per_host.text = proxy_settings.connections_per_host.to_string ();
        }

        static string get_colour_scheme_name (GtkSource.StyleScheme scheme) {
            return scheme.name;
        }

        static string get_doubleclick_name (DoubleClickMapping mapping) {
            return mapping.name;
        }

        private string get_selected_colour_scheme () {
            var idx = dropdown_colour_scheme.selected;
            var scheme = liststore_colour_schemes.get_item (idx) as GtkSource.StyleScheme;
            if (scheme == null) {
                return "";
            }
            return scheme.id;
        }

        [GtkCallback]
        public void on_button_certificate_save_clicked (Gtk.Button button) {
            proxy_settings.save_certificate (this);
        }

        [GtkCallback]
        public void on_button_crash_clicked () {
            var i = new int[0];
            var x = i[1];
            stdout.printf ("%d", x);
        }

        [GtkCallback]
        public void on_button_force_crash_core_clicked () {
            var url = "http://" + application_window.core_address + "/crash_reporting/test";
            try {
                var message = new Soup.Message ("GET", url);
                this.application_window.http_session.send (message);
            } catch (Error e) {
                stderr.printf ("Could not enable or disable crash reporting within the core: %s\n", e.message);
            }
        }

        [GtkCallback]
        public void on_checkbutton_crash_reports_toggled () {
            settings.set_boolean ("crash-reports", checkbutton_crash_reports.active);
            application_window.init_crash_reporting ();
        }

        [GtkCallback]
        public void on_entry_connections_per_host_changed () {
            proxy_settings.connections_per_host = int.parse (entry_connections_per_host.text);
            save_settings ();
        }

        [GtkCallback]
        public void on_proxy_address_changed () {
            proxy_settings.proxy_address = entry_proxy_address.text;
            save_settings ();
        }

        [GtkCallback]
        public void on_upstream_proxy_changed () {
            proxy_settings.upstream_proxy_address = entry_upstream_proxy.text;
            save_settings ();
        }

        private void save_settings () {
            var response = proxy_settings.save ();
            if (response != "") {
                label_error.label = response;
                label_error.show ();
            } else {
                label_error.hide ();
                settings_changed ();
            }
        }

        private void set_colour_scheme (string id) {
            for (var i = 0; i < liststore_colour_schemes.get_n_items (); i++) {
                var item = liststore_colour_schemes.get_item (i) as GtkSource.StyleScheme;
                if (item == null) {
                    continue;
                }

                if (item.id == id) {
                    dropdown_colour_scheme.selected = i;
                    break;
                }
            }
        }

        private void set_request_doubleclick (string setting) {
            for (var i = 0; i < liststore_request_doubleclick.get_n_items (); i++) {
                var item = liststore_request_doubleclick.get_item (i) as DoubleClickMapping;
                if (item == null) {
                    continue;
                }

                if (item.action == setting) {
                    dropdown_request_doubleclick.selected = i;
                    break;
                }
            }
        }
    }
}