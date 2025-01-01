namespace Pakiki {
    
    public class InterceptedRequest : GLib.Object {
        public string action { get; set; }
        public string request_guid { get; set; }
        public string data_guid { get; set; }
        public string protocol { get; set; }
        public string direction { get; set; }
        public string url { get; set; }
        public string body { get; set; }
        public string original_request_body { get; set; }

        public InterceptedRequest (Json.Object obj) {
            var request = obj.get_object_member ("Request");
            var action = obj.get_string_member ("RecordAction");

            Object (
                protocol: request.has_member ("Protocol") ? request.get_string_member ("Protocol") : "",
                direction: obj.has_member ("Direction") ? (obj.get_string_member ("Direction") == "browser_to_server" ? "Request" : "Response") : "",
                url: request.has_member ("URL") ? request.get_string_member ("URL") : "",
                body: obj.has_member ("Body") ? obj.get_string_member ("Body") : "",
                original_request_body: obj.has_member ("RequestBody") ? obj.get_string_member ("RequestBody") : "",
                action: action,
                request_guid: request.get_string_member ("GUID"),
                data_guid: obj.get_string_member ("GUID")
            );
        }
    }
}
