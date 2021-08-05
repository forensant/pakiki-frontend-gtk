namespace Proximity {
    class CoreProcess {
        ApplicationWindow application_window;
        GLib.Subprocess process;
        string path;
        bool temporary_file;

        public CoreProcess (ApplicationWindow parent) {
            this.application_window = parent;
        }

        private string? get_temporary_file_path () {
            FileIOStream iostream;
            File file;
            try {
                file = File.new_tmp ("proximity-XXXXXX.px", out iostream);
            } catch (Error err) {
                stdout.printf ("Error getting temporary path, using /tmp/proximity_temp instead (%s)\n", err.message);
                return "/tmp/proximity_temp";
            }
            var path = file.get_path ();
            stdout.printf ("Storing the files in: %s\n", path);
            return path;            
        }

        public bool open (string? project_path) {
            if (process != null) {
                process.force_exit ();
            }

            if (project_path == null ) {
                path = get_temporary_file_path ();
                temporary_file = true;
            } else {
                path = project_path;
                temporary_file = false;
            }

            var pid = (int) Posix.getpid ();

            // the core can change locations, depending on the environment, so attempt to find it
            // in a number of locations, starting with the "safest" first (to stop people from dropping malicious executables elsewhere)
            char[] exe_path_chr = new char[102400];
            var path_size = Posix.readlink ("/proc/self/exe", exe_path_chr);

            string exe_path = "";

            if (path_size != 102400 && path_size > 0) {
                exe_path = (string)exe_path_chr;

                var last_slash = exe_path.last_index_of_char ('/');
                if (last_slash == -1) {
                    exe_path = "";
                } else {
                    exe_path = exe_path.slice (0, last_slash + 1);
                }
            }
        
            string[] paths = {
                exe_path,
                "", // system path
                GLib.Environment.get_current_dir() + "/"
            };
            
            foreach (string core_exe_path in paths) {
                try {
                    process = new GLib.Subprocess (GLib.SubprocessFlags.NONE,
                        core_exe_path + "proximitycore",
                        "-project",
                        path,
                        "-parentpid",
                        pid.to_string ());

                    return true;
                } catch (Error err) {
                    stdout.printf("Error launching process: %s\n", err.message);
                }
            }

            return false;
        }

        public void open_project () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.OPEN,
                "_Open",
                "_Cancel");

            set_common_file_dialog_properties (dialog);
            var res = dialog.run ();
            handle_open_project_response (dialog, res, false);
        }

        void handle_open_project_response (Gtk.FileChooserNative open_dialog, int response_id, bool new_file) {
            switch (response_id) {
                case Gtk.ResponseType.ACCEPT: // open the file
                    var file = open_dialog.get_file();
                    var filename = file.get_path ();
                    open (filename);
                    application_window.on_new_project_open ();

                    break;
    
                case Gtk.ResponseType.CANCEL:
                    break;
            }
            open_dialog.destroy ();
        }

        public void new_project () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.SAVE,
                "_Save",
                "_Cancel");

            set_common_file_dialog_properties (dialog);
            var res = dialog.run ();
            handle_open_project_response (dialog, res, true);
        }

        public void save_project () {
            stdout.printf("Saving project");
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.SAVE,
                "_Save",
                "_Cancel");

            set_common_file_dialog_properties (dialog);
            var response_id = dialog.run ();

            stdout.printf("Got data!");

            if (response_id == Gtk.ResponseType.ACCEPT) {
                var selected_file = dialog.get_file();
                var filename = selected_file.get_path ();
                if (process != null) {
                    process.force_exit ();
                }

                File file1 = File.new_for_path (this.path);
                File file2 = File.new_for_path (filename);

                try {
                    file1.copy (file2, FileCopyFlags.OVERWRITE, null, null);
                } catch (Error e) {
                    print ("Error: %s\n", e.message);
                }

                open (filename);
            }

            dialog.destroy ();
        }

        private void set_common_file_dialog_properties (Gtk.FileChooserNative dialog) {
            dialog.transient_for = application_window;
            dialog.local_only = false; //allow for uri
            dialog.set_modal (true);
            dialog.set_do_overwrite_confirmation (true);
        }
    }
}
