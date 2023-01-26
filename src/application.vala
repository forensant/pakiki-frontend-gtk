namespace Proximity {
    public class Application : Gtk.Application {
        private string? api_key;
        private string? core_address;
        private string? preview_proxy_address;
        private ApplicationWindow window;

        public Application () {
            application_id = "com.forensant.proximity";
            flags |= GLib.ApplicationFlags.HANDLES_COMMAND_LINE;
            GLib.Environment.set_prgname("Proximity");

            set_temp_environment_var ();
        }

        private void about () {
            Gtk.AboutDialog dialog = new Gtk.AboutDialog ();
            dialog.set_destroy_with_parent (true);
            dialog.set_transient_for (window);
            dialog.set_modal (true);

            dialog.program_name = "Proximity Community Edition";
            dialog.comments = "Intercepting proxy";
            dialog.copyright = "Copyright © %d Forensant Ltd".printf (new DateTime.now ().get_year ());
            dialog.version = get_version ();

            dialog.license_type = Gtk.License.MIT_X11;

            dialog.website = "https://proximityhq.com/";
            dialog.website_label = "proximityhq.com";

            try {
                var logo = new Gdk.Pixbuf.from_stream_at_scale (window.banner_logo_svg (), 350, 64, true, null);
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
                window = new ApplicationWindow (this, core_address, preview_proxy_address, api_key);
            }
            window.present ();

            Gtk.CssProvider css_provider = new Gtk.CssProvider ();
            css_provider.load_from_resource ("/com/forensant/proximity/style.css");
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
    
            var action = new SimpleAction("new", null);
            action.activate.connect (window.on_new_project);
            add_action (action);

            action = new SimpleAction("open", null);
            action.activate.connect (window.on_open_project);
            add_action (action);

            action = new SimpleAction("save_as", null);
            action.activate.connect (window.on_save_project);
            add_action (action);

            action = new SimpleAction("open_browser", null);
            action.activate.connect (window.on_open_browser);
            add_action (action);
        }

        private int _command_line (ApplicationCommandLine command_line) {
            bool version = false;
    
            OptionEntry[] options = new OptionEntry[4];
            options[0] = { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null };
            options[1] = { "core", 0, 0, OptionArg.STRING, ref core_address, "Address for a running Proximity Core instance to connect to", "HOST:PORT" };
            options[2] = { "preview-proxy", 0, 0, OptionArg.STRING, ref preview_proxy_address, "Address for a running Proximity Core's preview proxy instance to connect to", "HOST:PORT" };
            options[3] = { "api-key", 0, 0, OptionArg.STRING, ref api_key, "The API Key when connecting to an external Proximity Core instance", null };
    
            // We have to make an extra copy of the array, since .parse assumes
            // that it can remove strings from the array without freeing them.
            string[] args = command_line.get_arguments ();
            string*[] _args = new string[args.length];
            for (int i = 0; i < args.length; i++) {
                _args[i] = args[i];
            }
    
            try {
                var opt_context = new OptionContext ();
                opt_context.set_help_enabled (true);
                opt_context.add_main_entries (options, null);
                unowned string[] tmp = _args;
                opt_context.parse (ref tmp);
            } catch (OptionError e) {
                command_line.print ("error: %s\n", e.message);
                command_line.print ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
                return 0;
            }
    
            if (version) {
                command_line.print ("Proximity Community Edition " + get_version () + "\n");
                return 0;
            }

            if (core_address != null && preview_proxy_address == null) {
                command_line.print ("If a core address is specified, a preview proxy should also be specified\n");
                return 0;
            }

            if (core_address != null && api_key == null) {
                command_line.print ("If a core address is specified, an API Key should also be specified\n");
                return 0;
            }

            if (core_address == null) {
                core_address = "";
                preview_proxy_address = "";
                api_key = "";
            }
            
            activate ();
    
            return 0;
        }
    
        public override int command_line (ApplicationCommandLine command_line) {
            // keep the application running until we are done with this commandline
            this.hold ();
            int res = _command_line (command_line);
            this.release ();
            return res;
        }

        public string get_version () {
            var file = File.new_for_uri ("resource:///com/forensant/proximity/version");

            var contents = "";

            try {
                var dis = new DataInputStream (file.read ());
                string line;
                while ((line = dis.read_line (null)) != null) {
                    contents += line;
                }
            } catch (Error e) {
                stdout.printf ("Error getting logo: %s\n", e.message);
            }

            return contents;
        }

        private void preferences () {
            var prefs = new ApplicationPreferences (window);
            prefs.settings_changed.connect (() => {
                window.settings_changed (); 
            });
            prefs.present ();
        }

        private void set_temp_environment_var () {
            var env_vars = GLib.Environ.@get ();

            var cache_home = GLib.Environ.get_variable (env_vars, "XDG_CACHE_HOME");
            if (cache_home == null) {
                return;
            }

            GLib.Environment.set_variable ("TMPDIR", cache_home + "/tmp", false);
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
