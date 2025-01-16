namespace Pakiki {
    
    [GtkTemplate (ui = "/com/forensant/pakiki/find-window.ui")]
    class FindWindow : Gtk.Window {
        public signal void request_set (string selected_guid);
        
        [GtkChild]
        private unowned Gtk.CheckButton checkbutton_exclude_resources;
        [GtkChild]
        private unowned Gtk.CheckButton checkbutton_negative_filter;
        [GtkChild]
        private unowned Gtk.Viewport viewport_requests;
        [GtkChild]
        private unowned Gtk.SearchEntry search_entry;

        private ApplicationWindow application_window;
        private RequestsPane requests_pane;
        private string selected_guid;

        public FindWindow (ApplicationWindow application_window) {
            this.application_window = application_window;

            requests_pane = new RequestsPane (application_window, false);
            requests_pane.process_launch_successful (true);
            requests_pane.reset_state ();
            requests_pane.request_selected.connect ( (guid) => { selected_guid = guid; });
            requests_pane.process_actions = false;
            requests_pane.request_double_clicked.connect ( (guid) => {
                selected_guid = guid;
                on_button_ok_clicked ();
            });
            viewport_requests.set_child (requests_pane);
        }

        [GtkCallback]
        private void on_button_cancel_clicked () {
            this.close ();
        }

        [GtkCallback]
        private void on_button_ok_clicked () {
            request_set (selected_guid);
            this.close ();
        }

        [GtkCallback]
        private void set_find_filter () {
            requests_pane.on_search (search_entry.get_text (),
                checkbutton_negative_filter.get_active (),
                checkbutton_exclude_resources.get_active (),
                "HTTP");
        }
    }
}