using Soup;

namespace Proximity {
    
    [GtkTemplate (ui = "/com/forensant/proximity/inject-underway.ui")]
    class InjectUnderway : Gtk.Grid {

        [GtkChild]
        private Gtk.Button button_action;
        [GtkChild]
        private Gtk.Entry entry_title;
        [GtkChild]
        private Gtk.Label label_error;
        [GtkChild]
        private Gtk.Label label_error_title;
        [GtkChild]
        private Gtk.Label label_injection_parameters;
        [GtkChild]
        private Gtk.Label label_title;
        [GtkChild]
        private Gtk.ProgressBar progress_bar;
        [GtkChild]
        private Gtk.TextView text_view_request;

        public InjectOperation operation { get; private set; }
        private RequestList request_list_full;
        private bool search_exclude_resources;
        private string search_query;

        public InjectUnderway (ApplicationWindow application_window) {
            string[] scan_ids = {"-"};
            request_list_full = new RequestList (application_window, scan_ids);
            this.attach (request_list_full, 0, 4, 2, 1);

            label_title.set_text_with_mnemonic ("_Title");
            label_title.mnemonic_widget = entry_title;
            
            this.show_all ();
        }

        public void set_inject_operation (InjectOperation operation) {
            var different_operation = this.operation == null || operation.guid != this.operation.guid;
            
            this.operation = operation;
            text_view_request.buffer.text = operation.request;
            label_injection_parameters.set_text (operation.inject_description);

            if (different_operation || entry_title.has_focus == false) {
                entry_title.set_text (operation.title);
            }

            if (operation.percent_completed >= 100) {
                progress_bar.hide ();
            } else {
                progress_bar.show ();
                progress_bar.set_fraction ((double)operation.percent_completed * 0.01);
                progress_bar.set_show_text (true);
                progress_bar.set_text (operation.requests_made_count.to_string () + " of " + operation.total_request_count.to_string ());
            }

            if (operation.error == "") {
                label_error_title.hide ();
                label_error.hide ();
            } else {
                label_error_title.show ();
                label_error.show ();

                label_error.set_text (operation.error);
            }

            if (different_operation) {
                string[] scan_ids = {operation.guid};
                request_list_full.set_scan_ids (scan_ids);
                request_list_full.on_search (search_query, search_exclude_resources);
            }

            if (operation.get_status () == InjectOperation.Status.ARCHIVED) {
                button_action.label = "_Unarchive";
            } else if (operation.get_status () == InjectOperation.Status.UNDERWAY) {
                button_action.label = "_Cancel";
            } else {
                button_action.label = "_Archive";
            }
        }

        [GtkCallback]
        public void on_action_clicked () {
            var uri = "";
            var archive = "";

            switch (operation.get_status ()) {
                case InjectOperation.Status.UNDERWAY:
                    uri = "/scripts/cancel";
                    break;
                case InjectOperation.Status.COMPLETED:
                    uri = "/inject_operation/archive";
                    archive = "true";
                    break;
                case InjectOperation.Status.ARCHIVED:
                    uri = "/inject_operation/archive";
                    archive = "false";
                    break;
            }

            if (uri == "") {
                return;
            }

            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://127.0.0.1:10101" + uri);

            var parameters = "guid=" + operation.guid;
            if (archive != "") {
                parameters += ("&archive=" + archive);
            }
            message.set_request ("application/x-www-form-urlencoded", Soup.MemoryUse.COPY, parameters.data);
            session.send_async.begin (message);
        }

        public void on_search (string query, bool exclude_resources) {
            this.search_query = query;
            this.search_exclude_resources = exclude_resources;
            request_list_full.on_search (search_query, search_exclude_resources);
        }

        [GtkCallback]
        public void on_title_changed () {
            var session = new Soup.Session ();
            var message = new Soup.Message ("PUT", "http://127.0.0.1:10101/inject_operation");

            Json.Builder builder = new Json.Builder ();
            builder.begin_object ();
            builder.set_member_name ("GUID");
            builder.add_string_value (operation.guid);
            builder.set_member_name ("Title");
            builder.add_string_value (entry_title.get_text ());
            builder.end_object ();

            Json.Generator generator = new Json.Generator ();
            Json.Node root = builder.get_root ();
            generator.set_root (root);
            string parameters = generator.to_data (null);

            message.set_request ("application/json", Soup.MemoryUse.COPY, parameters.data);
            session.send_async.begin (message);
        }
    }
}
