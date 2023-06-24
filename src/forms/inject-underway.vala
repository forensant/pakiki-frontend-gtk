using Soup;

namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/inject-underway.ui")]
    class InjectUnderway : Gtk.Grid {

        [GtkChild]
        private unowned Gtk.Button button_action;
        [GtkChild]
        private unowned Gtk.Entry entry_title;
        [GtkChild]
        private unowned Gtk.Label label_error;
        [GtkChild]
        private unowned Gtk.Label label_error_title;
        [GtkChild]
        private unowned Gtk.Label label_injection_parameters;
        [GtkChild]
        private unowned Gtk.Label label_title;
        [GtkChild]
        private unowned Gtk.ProgressBar progress_bar;
        [GtkChild]
        private unowned Gtk.TextView text_view_request;

        private ApplicationWindow application_window;
        public InjectOperation operation { get; private set; }
        private InjectPane inject_pane;
        private RequestList request_list_full;
        private bool search_exclude_resources;
        private bool search_negative_filter;
        private string search_query;

        public InjectUnderway (ApplicationWindow application_window, InjectPane inject_pane) {
            this.application_window = application_window;
            this.inject_pane = inject_pane;
            search_query = "";
            search_negative_filter = false;
            string[] scan_ids = {"-"};
            request_list_full = new RequestList (application_window, false, scan_ids);
            this.attach (request_list_full, 0, 4, 2, 1);

            label_title.set_text_with_mnemonic ("_Title");
            label_title.mnemonic_widget = entry_title;
            
            this.show ();
        }

        public bool find_activated () {
            return request_list_full.find_activated ();
        }

        public void set_inject_operation (InjectOperation operation) {
            var different_operation = this.operation == null || operation.guid != this.operation.guid;
            
            this.operation = operation;
            
            if (different_operation || entry_title.has_focus == false) {
                entry_title.set_text (operation.title);
            }

            if (different_operation) {
                text_view_request.buffer.text = operation.request;
                label_injection_parameters.set_text (operation.inject_description);
                label_injection_parameters.set_tooltip_text (operation.inject_description);
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
                label_error.set_tooltip_text (operation.error);
            }

            if (different_operation) {
                string[] scan_ids = {operation.guid};
                request_list_full.set_scan_ids (scan_ids);
                request_list_full.on_search (search_query, search_negative_filter, search_exclude_resources);
            }

            if (operation.get_status () == InjectOperation.Status.ARCHIVED) {
                button_action.label = "_Unarchive";
                button_action.tooltip_text = "Move the scan to the completed section of the sidebar";
            } else if (operation.get_status () == InjectOperation.Status.UNDERWAY) {
                button_action.label = "_Cancel";
                button_action.tooltip_text = "Cancel the scan";
            } else {
                button_action.label = "_Archive";
                button_action.tooltip_text = "Move the scan to the archived section in the sidebar";
            }
        }

        [GtkCallback]
        public void on_action_clicked () {
            var uri = "";
            var archive = "";

            switch (operation.get_status ()) {
                case InjectOperation.Status.UNDERWAY:
                    uri = "/scripts/{guid}/cancel";
                    break;
                case InjectOperation.Status.COMPLETED:
                    uri = "/inject_operations/{guid}/archive";
                    archive = "true";
                    break;
                case InjectOperation.Status.ARCHIVED:
                    uri = "/inject_operations/{guid}/archive";
                    archive = "false";
                    break;
            }

            if (uri == "") {
                return;
            }

            var message = new Soup.Message ("PATCH", "http://" + application_window.core_address + uri.replace ("{guid}", operation.guid));

            var parameters = "";
            if (archive != "") {
                parameters += ("archive=" + archive);
            }

            message.set_request_body_from_bytes ("application/x-www-form-urlencoded", new Bytes (parameters.data));
            application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }

        [GtkCallback]
        public void on_button_clone_clicked () {
            inject_pane.clone_inject_operation (operation);
        }

        public void on_search (string query, bool negative_filter, bool exclude_resources) {
            this.search_query = query;
            this.search_negative_filter = negative_filter;
            this.search_exclude_resources = exclude_resources;
            request_list_full.on_search (search_query, negative_filter, search_exclude_resources);
        }

        [GtkCallback]
        public void on_title_changed () {
            if (entry_title.text == operation.title) {
                return;
            }
            
            var message = new Soup.Message ("PATCH", "http://" + application_window.core_address + "/inject_operations/" + operation.guid + "/title");

            var parameters = "title=" + GLib.Uri.escape_string (entry_title.text);
            message.set_request_body_from_bytes ("application/x-www-form-urlencoded", new Bytes (parameters.data));
            application_window.http_session.send_async.begin (message, GLib.Priority.DEFAULT, null);
        }
    }
}
