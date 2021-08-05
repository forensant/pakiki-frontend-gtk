namespace Proximity {
    
    public class InjectOperation {
        public enum Status {
            COMPLETED,
            UNDERWAY,
            ARCHIVED
        }

        public string guid                { get; private set; }
        public string title               { get; private set; }
        public string request             { get; private set; }
        public bool   archived            { get; private set; }
        public string error               { get; private set; }
        public int    percent_completed   { get; private set; }
        public string url                 { get; private set; }
        public string inject_description  { get; private set; }
        public int    requests_made_count { get; private set; }
        public int    total_request_count { get; private set; }

        public InjectOperation (Json.Object obj) {
            guid                = obj.get_string_member ("GUID");
            title               = obj.get_string_member ("Title");
            request             = obj.get_string_member ("Request");
            archived            = obj.get_boolean_member ("Archived");
            error               = obj.get_string_member ("Error");
            percent_completed   = (int)obj.get_int_member ("PercentCompleted");
            url                 = obj.get_string_member ("URL");
            inject_description  = obj.get_string_member ("InjectDescription");
            requests_made_count = (int)obj.get_int_member ("RequestsMadeCount");
            total_request_count = (int)obj.get_int_member ("TotalRequestCount");
        }

        public Status get_status () {
            if (archived) {
                return Status.ARCHIVED;
            }

            if (percent_completed >= 100) {
                return Status.COMPLETED;
            }

            return Status.UNDERWAY;
        }
    }
}
