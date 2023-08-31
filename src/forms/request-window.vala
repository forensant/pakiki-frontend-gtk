namespace Pakiki {   
    class RequestWindow : Gtk.Window {
        public RequestWindow (ApplicationWindow application_window, string request_guid) {
            this.title = "Request Details — Pākiki Proxy";
            this.window_position = Gtk.WindowPosition.CENTER;
            this.set_default_size (810, 500);
            this.hide_titlebar_when_maximized = true;

            var req_details = new RequestDetails (application_window);
            req_details.set_request (request_guid);
            req_details.margin = 0;
            req_details.show ();
            this.add (req_details);
        }
    }
}