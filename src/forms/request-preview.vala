namespace Pakiki {
    using WebKit;
    
    class RequestPreview : WebKit.WebView {
        private bool _has_content = false;
        public bool has_content {
            get { return _has_content; }
        }

        private ApplicationWindow application_window;

        public RequestPreview(ApplicationWindow application_window) {
            this.application_window = application_window;
            
            this.decide_policy.connect (on_link_clicked);
        }

        private bool on_link_clicked (PolicyDecision policy_decision, PolicyDecisionType type) {
            if (type != WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
                return false;
            }

            var decision = (NavigationPolicyDecision)policy_decision;
            var navigation_type = decision.get_navigation_action ().get_navigation_type ();

            if (navigation_type == WebKit.NavigationType.OTHER) {
                return false;
            }

            // ignore form submissions, link clicks, etc.
            decision.ignore ();
            return true;
        }

        public bool set_content (Bytes bytes, string mimetype, string url) {
            if ( mimetype.index_of ("application/") == 0) {
                this.load_uri ("about:blank");
                _has_content = false;
                return false;
            }

            var web_context = this.get_context ();
            web_context.clear_cache ();

            var proxy_settings = new WebKit.NetworkProxySettings ("http://" + application_window.preview_proxy_address + "/", null);
            
            var data_manager = get_website_data_manager ();
            data_manager.set_tls_errors_policy (WebKit.TLSErrorsPolicy.IGNORE);
            data_manager.set_network_proxy_settings (WebKit.NetworkProxyMode.CUSTOM, proxy_settings);

            if (bytes.length == 0) {
                this.load_uri ("about:blank");
                _has_content = false;
                return false;
            }

            this.load_bytes (bytes, mimetype, null, url);

            _has_content = true;
            return true;
        }
    }
}
