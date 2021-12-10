namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/placeholder-requests.ui")]
    class PlaceholderRequests : Gtk.Box {

        [GtkChild]
        private unowned Gtk.Button button_certificate_save;
        [GtkChild]
        private unowned Gtk.Frame frame_error;
        [GtkChild]
        private unowned Gtk.Label label_certificate;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_title_certificate;
        [GtkChild]
        private unowned Gtk.Label label_title_proxy;
        [GtkChild]
        private unowned Gtk.Label label_setup_proxy;

        private ApplicationWindow application_window;
        private ProxySettings proxy_settings;
        
        public PlaceholderRequests (ApplicationWindow application_window) {
            this.application_window = application_window;

            update_proxy_address ();
        }

        [GtkCallback]
        public void on_button_certificate_save_clicked (Gtk.Button button) {
            proxy_settings.save_certificate (application_window);
        }

        void update_proxy_address () {
            proxy_settings = new ProxySettings (application_window);
            if (proxy_settings.successful) {
                label_setup_proxy.label = label_setup_proxy.label.replace ("PROXYADDRESS", "http://localhost" + proxy_settings.proxy_address);
            }
            else {
                set_error (application_window.core_address);
            }
        }

        public void set_error (string core_address) {
            application_window.hide_controls ();
            if (core_address == "") {
                label_error.set_text ("An error has occurred when launching the core. Ensure that 'proximitycore' is in the directory next to Proximity.");
            } else {
                label_error.set_markup ("An error has occurred when connecting to Proximity Core at <a href=\"http://" + core_address + "\">http://" + core_address + "</a>. Ensure that Proximity Core is running and that the address is correct.");
            }
            
            frame_error.visible = true;

            button_certificate_save.visible = false;
            label_certificate.visible = false;
            label_title_certificate.visible = false;
            label_title_proxy.visible = false;
            label_setup_proxy.visible = false;
        }
    }
}
