namespace Pakiki {
    class CoreProcess : Object {
        public signal void copying_file (bool start);
        public signal void core_started (string location);
        public signal void listener_error (string warning);
        public signal void opening_file (bool start);
        
        private string api_key;
        private ApplicationWindow application_window;
        private Pid child_pid;
        private string path;
        private FileStream process_stdin;
        private SavingDialog saving_dialog = null;
        private bool temporary_file;

        public delegate void QuitSuccessful();

        public CoreProcess (ApplicationWindow parent, string api_key) {
            this.application_window = parent;
            child_pid = 0;
            this.api_key = api_key;
        }

        private void copy_and_open_file (string from, string to) {
            File file1 = File.new_for_path (from);
            File file2 = File.new_for_path (to);

            try {
                file1.copy (file2, FileCopyFlags.OVERWRITE, null, null);

                if (temporary_file) {
                    file1.@delete (null);
                }
            } catch (Error e) {
                print ("Error: %s\n", e.message);
            }

            open (to);
        }

        public static void create_temp_dir () {
            var tmp_dir = GLib.Environment.get_tmp_dir ();
            if (!FileUtils.test (tmp_dir, FileTest.IS_DIR)) {
                DirUtils.create_with_parents (tmp_dir, 0755);
            }
        }

        private string? get_temporary_file_path () {
            FileIOStream iostream;
            File file;
            try {
                create_temp_dir ();
                file = File.new_tmp ("pakiki-XXXXXX.pkk", out iostream);
            } catch (Error err) {
                stdout.printf ("Error getting temporary path, using /tmp/pakiki_temp instead (%s)\n", err.message);
                return "/tmp/pakiki_temp";
            }
            return file.get_path ();
        }

        public bool open (string? project_path) {
            if (child_pid != 0) {
                stdout.printf("Child process already open, this shouldn't happen - closing it.\n");
                Posix.kill (child_pid, Posix.Signal.TERM);
                ChildWatch.add (child_pid, (pid, status) => {
                    if (temporary_file) {
                        var f = File.new_for_path (path);
                        try {
                            f.@delete (null);
                        } catch (Error e) {
                            stdout.printf("Colud not delete file: %s\n", e.message);
                        }
                    }

                    open (project_path);
    
                    child_pid = 0;
                });
                return true;
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
                    string[] spawn_args = {
                        core_exe_path + "pakikicore",
                        "-project", path, 
                        "-parentpid", pid.to_string (),
                        "-api-key", api_key
                    };

                    string[] spawn_env = Environ.get ();
                    Pid child_pid;

                    int standard_input;
                    int standard_output;
                    int standard_error;

                    if (core_exe_path == "") {
                        core_exe_path = "/";
                    }

                    var launch_success = Process.spawn_async_with_pipes (core_exe_path,
                        spawn_args,
                        spawn_env,
                        SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                        null,
                        out child_pid,
                        out standard_input,
                        out standard_output,
                        out standard_error);

                    if (!launch_success) {
                        continue;
                    }

                    process_stdin = FileStream.fdopen (standard_input, "w");

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
                        stdout.printf("Pākiki core closed with status %d\n", status);
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

        string to_open;

        private void on_open_project_quit_successful() {
            child_pid = 0;
            saving_dialog.close ();
            open (to_open);
        }

        void handle_open_project_response (Gtk.FileChooserNative open_dialog, int response_id, bool new_file) {
            switch (response_id) {
                case Gtk.ResponseType.ACCEPT: // open the file
                    var file = open_dialog.get_file();
                    var filename = file.get_path ();

                    if (this.path == filename) {
                        return;
                    }
                    
                    this.opening_file (true);

                    if (new_file && file.query_exists ()) {
                        try {
                            file.@delete ();
                        } catch (Error e) {
                            stdout.printf("Colud not delete file: %s\n", e.message);
                        }
                    }

                    if (child_pid != 0) {
                        saving_dialog = new SavingDialog ();
                        saving_dialog.show_all ();
                        to_open = filename;
                        quit (this.on_open_project_quit_successful);
                    }
                    
                    break;
    
                case Gtk.ResponseType.CANCEL:
                    break;
            }
            open_dialog.destroy ();
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

        public void new_project () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.SAVE,
                "_Save",
                "_Cancel");

            set_common_file_dialog_properties (dialog);
            dialog.set_current_name("project.pkk");
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
                print ("[Pākiki Core] %s: %s", stream_name, line);
                
                if (line.contains ("Web frontend is available at:")) {
                    var scheme_idx = line.index_of ("://");
                    var host_idx = line.index_of ("/", scheme_idx + 4);
                    var host = line.substring (scheme_idx + 3, host_idx - scheme_idx - 3);
                    this.core_started (host);
                    this.opening_file (false);
                }

                if (line.contains ("Preview proxy is available at:")) {
                    var scheme_idx = line.index_of ("://");
                    var host_idx = line.index_of ("/", scheme_idx + 4);
                    var host = line.substring (scheme_idx + 3, host_idx - scheme_idx - 3);
                    application_window.preview_proxy_address = host;
                }

                if (line.contains ("Warning: The proxy could not be started")) {
                    var warning_location = line.index_of ("Warning:");
                    var warning_message = line.substring (warning_location);
                    this.listener_error (warning_message);
                }

                if (line.contains ("A previous project was not closed properly")) {
                    var dlg = new Gtk.MessageDialog (null,
                        Gtk.DialogFlags.MODAL,
                        Gtk.MessageType.WARNING,
                        Gtk.ButtonsType.YES_NO,
                        line.replace ("(y/n)", ""));

                    var res = dlg.run ();
                    var chr = "n";
                    switch (res)
                    {
                    case Gtk.ResponseType.YES:
                        chr = "y";
                        break;
                    default:
                        // do_nothing_since_dialog_was_cancelled ();
                        break;
                    }
                    chr += "\n";
                    process_stdin.write (chr.data);
                    process_stdin.flush ();

                    dlg.destroy ();
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

        public void quit (QuitSuccessful? quit_successful) {
            if (child_pid != 0) {
                Posix.kill (child_pid, Posix.Signal.TERM);

                ChildWatch.add (child_pid, (pid, status) => {
                    if (temporary_file) {
                        var f = File.new_for_path (path);
                        try {
                            f.@delete (null);
                        } catch (Error e) {
                            stdout.printf("Colud not delete file: %s\n", e.message);
                        }
                    }

                    if (quit_successful != null) {
                        quit_successful ();
                    }
                });

                child_pid = 0;
            } else {
                if (quit_successful != null) {
                    quit_successful ();
                }
            }
        }

        public void save_project () {
            var dialog = new Gtk.FileChooserNative ("Pick a file",
                application_window,
                Gtk.FileChooserAction.SAVE,
                "_Save",
                "_Cancel");

            set_common_file_dialog_properties (dialog);
            dialog.set_current_name("project.pkk");
            var response_id = dialog.run ();

            if (response_id == Gtk.ResponseType.ACCEPT) {
                var selected_file = dialog.get_file();
                var filename = selected_file.get_path ();
                copying_file (true);
                if (child_pid != 0) {
                    Posix.kill (child_pid, Posix.Signal.TERM);
                    ChildWatch.add (child_pid, (pid, status) => {
                        copy_and_open_file (this.path, filename);
                        copying_file (false);
                    });
                    child_pid = 0;
                }
                else {
                    copy_and_open_file (this.path, filename);
                    copying_file (false);
                }
            }

            dialog.destroy ();
        }

        private void set_common_file_dialog_properties (Gtk.FileChooserNative dialog) {
            dialog.transient_for = application_window;
            dialog.local_only = false; //allow for uri
            dialog.set_modal (true);
            dialog.set_do_overwrite_confirmation (true);

            var filter = new Gtk.FileFilter ();
            filter.add_pattern ("*");
            filter.set_filter_name ("All files");
            dialog.add_filter (filter);

            filter = new Gtk.FileFilter ();
            filter.add_pattern ("*.pkk");
            filter.set_filter_name ("Pākiki Project");
            dialog.add_filter (filter);
            dialog.set_filter (filter);
        }

        public static string websocket_url(ApplicationWindow application_window, string object_type, Gee.HashMap<string, string> filters = new Gee.HashMap<string, string> ()) {
            var url = "http://" + application_window.core_address + "/notifications";

            filters["ObjectType"] = object_type;
            
            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            foreach (var entry in filters.entries) {
                builder.set_member_name (entry.key);
                builder.add_string_value (entry.value);
            }
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);

            string json_str = generator.to_data (null);

            
            url += "?objectfieldfilter=" + GLib.Uri.escape_string (json_str, null);

            url += "&api_key=" + application_window.api_key;
            
            return url;
        }
    }
}
