namespace Proximity {
    public class Application : Gtk.Application {
        private ApplicationWindow window;

        private List<Gdk.Pixbuf> icons;

        public Application () {
            application_id = "com.forensant.proximity";
            GLib.Environment.set_prgname("Proximity");

            icons = new List<Gdk.Pixbuf> ();
            try {
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo256.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo128.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo64.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo48.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo32.png"));
                icons.append (new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo16.png"));
            } catch (Error err) {
                stdout.printf ("Could not create icon pack");
            }
        }

        private void about () {
            Gtk.AboutDialog dialog = new Gtk.AboutDialog ();
            dialog.set_destroy_with_parent (true);
            dialog.set_transient_for (window);
            dialog.set_modal (true);

            dialog.program_name = "Proximity Community Edition";
            dialog.comments = "Intercepting proxy";
            dialog.copyright = "Copyright © %d Forensant Ltd".printf (new DateTime.now ().get_year ());
            dialog.version = "0.3";

            dialog.license_type = Gtk.License.MIT_X11;

            dialog.website = "https://proximityhq.com/";
            dialog.website_label = "proximityhq.com";

            try {
                var logo = new Gdk.Pixbuf.from_resource ("/com/forensant/proximity/Logo-banner.png");
                dialog.logo = logo;
            } catch (Error err) {
                stdout.printf ("Could not create logo for the about page");
            }

            dialog.response.connect ((response_id) => {
                if (response_id == Gtk.ResponseType.CANCEL || response_id == Gtk.ResponseType.DELETE_EVENT) {
                    dialog.hide_on_delete ();
                }
            });

            // Show the dialog:
            dialog.present ();
        }

        public override void activate () {
            if (window == null) {
                window = new ApplicationWindow (this);
            }
            window.set_icon_list (icons);
            window.present ();

            var action = new SimpleAction("new", null);
            action.activate.connect (window.on_new_project);
            add_action (action);

            action = new SimpleAction("open", null);
            action.activate.connect (window.on_open_project);
            add_action (action);

            action = new SimpleAction("save_as", null);
            action.activate.connect (window.on_save_project);
            add_action (action);
        }

        private void preferences () {
            var prefs = new ApplicationPreferences (window);
            prefs.present ();
        }

        public override void startup () {
            base.startup ();

            var action = new SimpleAction ("preferences", null);
            action.activate.connect (preferences);
            add_action (action);

            action = new SimpleAction("about", null);
            action.activate.connect (about);
            add_action (action);
        }
    }
}
