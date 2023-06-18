namespace Proximity {

    [GtkTemplate (ui = "/com/forensant/proximity/prefs.ui")]
    public class ApplicationPreferences : Gtk.Dialog {
        public signal void settings_changed ();

        private GLib.Settings settings;
        private ProxySettings proxy_settings;

        [GtkChild]
        private unowned Gtk.ComboBoxText combobox_colour_scheme;

        [GtkChild]
        private unowned Gtk.ComboBoxText combobox_request_doubleclick;

        [GtkChild]
        private unowned Gtk.Entry entry_connections_per_host;

        [GtkChild]
        private unowned Gtk.Entry entry_proxy_address;

        [GtkChild]
        private unowned Gtk.Entry entry_upstream_proxy;

        [GtkChild]
        private unowned Gtk.Label label_error;

        private ApplicationWindow application_window;
        private Gtk.ListStore liststore_colour_schemes;

        public ApplicationPreferences(ApplicationWindow window) {
            GLib.Object(transient_for: window, use_header_bar: 1);
            this.application_window = window;

            liststore_colour_schemes = new Gtk.ListStore(2, typeof(string), typeof(string));

            var style_manager = Gtk.SourceStyleSchemeManager.get_default();
            foreach(string id in style_manager.get_scheme_ids ()) {
                var scheme = style_manager.get_scheme (id);
                Gtk.TreeIter iter;
                liststore_colour_schemes.append (out iter);
                liststore_colour_schemes.set(iter, 0, scheme.name, 1, scheme.id, -1);
            }

            combobox_colour_scheme.model = liststore_colour_schemes;
            combobox_colour_scheme.id_column = 1;

            settings = new GLib.Settings("com.forensant.proximity");
            settings.bind("request-double-click", combobox_request_doubleclick, "active-id", GLib.SettingsBindFlags.DEFAULT);
            combobox_colour_scheme.active_id = (string) settings.get_value ("colour-scheme");

            combobox_colour_scheme.changed.connect (() => {
                // we use this rather than bind, to guarantee that the setting has been set before the other controls
                // try to use it (after we fire settings_changed)
                Gtk.TreeIter iter;
                Value val;

                combobox_colour_scheme.get_active_iter(out iter);
                liststore_colour_schemes.get_value(iter, 1, out val);

                settings.set_value("colour-scheme", (string)val);

                settings_changed (); 
            });
            
            combobox_request_doubleclick.changed.connect (() => { settings_changed (); });

            proxy_settings = new ProxySettings (window);
            entry_proxy_address.text = proxy_settings.proxy_address;
            entry_upstream_proxy.text = proxy_settings.upstream_proxy_address;
            entry_connections_per_host.text = proxy_settings.connections_per_host.to_string ();
        }

        [GtkCallback]
        public void on_button_certificate_save_clicked (Gtk.Button button) {
            proxy_settings.save_certificate (this);
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
    }
}