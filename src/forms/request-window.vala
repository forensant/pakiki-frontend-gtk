namespace Pakiki {   
    class RequestWindow : Gtk.Window {
        public RequestWindow (ApplicationWindow application_window, string request_guid) {
            this.title = "Request Details — Pākiki Proxy";
            this.set_default_size (810, 500);

            var req_details = new RequestDetails (application_window);
            req_details.set_request (request_guid);
            req_details.show ();
            this.set_child (req_details);
        }
    }
}
