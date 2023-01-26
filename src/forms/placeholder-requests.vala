namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/placeholder-requests.ui")]
    class PlaceholderRequests : Gtk.Box {

        [GtkChild]
        private unowned Gtk.Box box_chromium_not_found;
        [GtkChild]
        private unowned Gtk.Button button_certificate_save;
        [GtkChild]
        private unowned Gtk.Button button_launch_browser;
        [GtkChild]
        private unowned Gtk.Expander expander_manual_instructions;
        [GtkChild]
        private unowned Gtk.Frame frame_error;
        [GtkChild]
        private unowned Gtk.Label label_certificate;
        [GtkChild]
        private unowned Gtk.Label label_chromium_not_found;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_title_certificate;
        [GtkChild]
        private unowned Gtk.Label label_title_proxy;
        [GtkChild]
        private unowned Gtk.Label label_setup_proxy;

        private ApplicationWindow application_window;
        private GLib.Settings settings;
        
        public PlaceholderRequests (ApplicationWindow application_window) {
            this.application_window = application_window;

            settings = new GLib.Settings ("com.forensant.proximity");
            
            expander_manual_instructions.expanded = settings.get_boolean ("manual-instructions-expanded");

            if (is_sandboxed ()) {
                expander_manual_instructions.expanded = true;
                label_chromium_not_found.visible = false;
                button_launch_browser.visible = false;
                box_chromium_not_found.visible = false;
            } else {
                set_browser_available ();

                if (!application_window.can_open_browser ()) {
                    Timeout.add_full (Priority.DEFAULT, 1000, () => {
                        if (application_window.can_open_browser ()) {
                            set_browser_available ();
                            return false;
                        }
    
                        return true;
                    });
                }
            }            
        }

        private bool is_sandboxed () {
            File file = File.new_for_path ("/.flatpak-info");
            return file.query_exists ();
        }

        [GtkCallback]
        public void on_button_certificate_save_clicked (Gtk.Button button) {
            application_window.proxy_settings.save_certificate (application_window);
        }

        [GtkCallback]
        public void on_button_launch_browser_clicked (Gtk.Button button) {
            application_window.on_open_browser ();
        }

        [GtkCallback]
        public void on_expander_manual_instructions_activate (Gtk.Expander expander) {
            settings.set_boolean ("manual-instructions-expanded", !expander.expanded);
        }

        public void update_proxy_address () {
            if (application_window.proxy_settings.successful) {
                label_setup_proxy.label = label_setup_proxy.label.replace ("PROXYADDRESS", "http://" + application_window.proxy_settings.local_proxy_address ());
            }
            else {
                set_error (application_window.core_address);
            }
        }

        private void set_browser_available () {
            label_chromium_not_found.visible = !application_window.can_open_browser ();
            box_chromium_not_found.visible = !application_window.can_open_browser ();
            button_launch_browser.sensitive = application_window.can_open_browser ();
        }

        public void set_error (string core_address) {
            if (core_address == "") {
                label_error.set_text ("An error has occurred when launching the core. Ensure that 'proximitycore' is in the directory next to Proximity.");
            } else {
                label_error.set_markup ("An error has occurred when connecting to Proximity Core at <a href=\"http://" + core_address + "\">http://" + core_address + "</a>. Ensure that Proximity Core is running and that the address is correct.");
            }
            
            frame_error.visible = true;
            expander_manual_instructions.visible = false;
            label_chromium_not_found.visible = false;
            button_launch_browser.visible = false;
            box_chromium_not_found.visible = false;

            button_certificate_save.visible = false;
            label_certificate.visible = false;
            label_title_certificate.visible = false;
            label_title_proxy.visible = false;
            label_setup_proxy.visible = false;
        }
    }
}
