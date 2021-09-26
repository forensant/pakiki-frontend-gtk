namespace Proximity {

    [GtkTemplate (ui = "/com/forensant/proximity/prefs.ui")]
    public class ApplicationPreferences : Gtk.Dialog {

        private GLib.Settings settings;
        private ProxySettings proxy_settings;

        [GtkChild]
        private unowned Gtk.ComboBoxText combobox_request_doubleclick;

        [GtkChild]
        private unowned Gtk.Entry entry_proxy_address;

        [GtkChild]
        private unowned Gtk.Entry entry_upstream_proxy;

        [GtkChild]
        private unowned Gtk.Label label_error;

        private ApplicationWindow application_window;

        public ApplicationPreferences(ApplicationWindow window) {
            GLib.Object(transient_for: window, use_header_bar: 1);
            this.application_window = window;

            settings = new GLib.Settings("com.forensant.proximity");
            settings.bind("request-double-click", combobox_request_doubleclick, "active-id", GLib.SettingsBindFlags.DEFAULT);

            proxy_settings = new ProxySettings ();
            entry_proxy_address.text = proxy_settings.proxy_address;
            entry_upstream_proxy.text = proxy_settings.upstream_proxy_address;
        }

        [GtkCallback]
        public void on_button_certificate_save_clicked (Gtk.Button button) {
            proxy_settings.save_certificate (this);
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
            }
        }
    }
}