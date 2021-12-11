namespace Proximity {
    class CoreProcess : Object {
        public signal void core_started (string location);
        public signal void listener_error (string warning);

        private ApplicationWindow application_window;
        private Pid child_pid;
        private string path;
        private bool temporary_file;

        public CoreProcess (ApplicationWindow parent) {
            this.application_window = parent;
            child_pid = 0;
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
            return file.get_path ();            
        }

        public bool open (string? project_path) {
            if (child_pid != 0) {
                Posix.kill (child_pid, Posix.Signal.TERM);
                child_pid = 0;
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
                    string[] spawn_args = {core_exe_path + "proximitycore", "-project", path, "-parentpid", pid.to_string ()};
                    string[] spawn_env = Environ.get ();
                    Pid child_pid;

                    int standard_input;
                    int standard_output;
                    int standard_error;

                    if (core_exe_path == "") {
                        core_exe_path = "/";
                    }

                    Process.spawn_async_with_pipes (core_exe_path,
                        spawn_args,
                        spawn_env,
                        SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                        null,
                        out child_pid,
                        out standard_input,
                        out standard_output,
                        out standard_error);

                    // stdout:
                    IOChannel output = new IOChannel.unix_new (standard_output);
                    output.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
                        return process_line (channel, condition, "stdout");
                    });

                    // stderr:
                    IOChannel error = new IOChannel.unix_new (standard_error);
                    error.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
                        return process_line (channel, condition, "stderr");
                    });

                    this.child_pid = child_pid;
                    ChildWatch.add (child_pid, (pid, status) => {
                        // Triggered when the child indicated by child_pid exits
                        stdout.printf("Proximity core closed with status %d\n", status);
                        this.child_pid = 0;
                        Process.close_pid (pid);
                    });

                    return true;
                } catch (Error err) {
                }
            }

            stderr.printf ("Could not launch the executable process from any of the following directories:\n");
            for (int i = 0; i < paths.length; i++) {
                stderr.printf ("  %s\n", paths[i]);
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
                    //application_window.on_new_project_open ();

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

        private bool process_line (IOChannel channel, IOCondition condition, string stream_name) {
            if (condition == IOCondition.HUP) {
                print ("%s: The fd has been closed.\n", stream_name);
                return false;
            }
        
            try {
                string line;
                channel.read_line (out line, null, null);
                print ("[Proximity Core] %s: %s", stream_name, line);
                
                if (line.contains ("Web frontend is available at:")) {
                    var scheme_idx = line.index_of ("://");
                    var host_idx = line.index_of ("/", scheme_idx + 4);
                    var host = line.substring (scheme_idx + 3, host_idx - scheme_idx - 3);
                    this.core_started (host);
                }

                if (line.contains ("Warning: The proxy could not be started")) {
                    var warning_location = line.index_of ("Warning:");
                    var warning_message = line.substring (warning_location);
                    this.listener_error (warning_message);
                }

            } catch (IOChannelError e) {
                print ("%s: IOChannelError: %s\n", stream_name, e.message);
                return false;
            } catch (ConvertError e) {
                print ("%s: ConvertError: %s\n", stream_name, e.message);
                return false;
            }
        
            return true;
        }

        public void save_project () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.SAVE,
                "_Save",
                "_Cancel");

            set_common_file_dialog_properties (dialog);
            var response_id = dialog.run ();

            if (response_id == Gtk.ResponseType.ACCEPT) {
                var selected_file = dialog.get_file();
                var filename = selected_file.get_path ();
                if (child_pid != 0) {
                    Posix.kill (child_pid, Posix.Signal.TERM);
                    child_pid = 0;
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
