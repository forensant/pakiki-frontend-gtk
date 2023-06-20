namespace Pakiki {
    class InjectListRow : Gtk.ListBoxRow {

        public enum Type {
            INJECT_SCAN,
            LABEL,
            PLACEHOLDER
        }

        public Type row_type                    { get; set; }
        public InjectOperation.Status status    { get; set; }
        public InjectOperation inject_operation { get; set; }

        public bool first {
            set {
                if (value) {
                    this.margin_top = 0;
                } else {
                    this.margin_top = 3; 
                }
            }
        }

        private Gtk.Label label_title;
        private RoundProgressBar progress_bar;

        public InjectListRow.label (InjectOperation.Status status, string title) {
            this.row_type = Type.LABEL;
            this.status   = status;

            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
            hbox.set_spacing (5);
            this.add (hbox);

            var label_title = new Gtk.Label (null);
            label_title.set_markup ("<b>" + title + "</b>");
            hbox.pack_start (label_title, false, false, 0);
            label_title.margin_top  = 6;
            label_title.margin_start = 6;
            label_title.xalign = 0.0f;

            label_title.show ();

            this.margin_top = 3;
            this.margin_bottom = 3;

            this.set_selectable (false);
            this.sensitive = false;
        }

        public InjectListRow.placeholder () {
            this.row_type = Type.PLACEHOLDER;
            this.status   = UNDERWAY;

            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
            hbox.set_spacing (5);
            this.add (hbox);

            label_title = new Gtk.Label (null);
            label_title.set_markup ("<i>Scans will be shown here once they have started.</i>");
            hbox.pack_start (label_title, true, true, 0);
            label_title.margin_top    = 20;
            label_title.margin_start  = 10;
            label_title.margin_end    = 10;
            label_title.margin_bottom = 20;
            label_title.wrap = true;
            this.sensitive = false;

            label_title.show ();

            this.set_selectable (false);
        }

        public InjectListRow.inject_scan (InjectOperation inject_operation) {
            this.row_type         = Type.INJECT_SCAN;
            this.status           = inject_operation.get_status ();
            this.inject_operation = inject_operation;

            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            this.add (hbox);

            progress_bar = new RoundProgressBar ();
            if (inject_operation.get_status () == InjectOperation.Status.COMPLETED || inject_operation.get_status () == InjectOperation.Status.ARCHIVED) {
                progress_bar.fraction = 1.0f;
            } else {
                progress_bar.fraction = ((double)inject_operation.percent_completed * 0.01);
            }
            
            progress_bar.margin_start = 6;
            hbox.pack_start (progress_bar, false, false, 0);

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            hbox.pack_start (vbox, true, true, 0);

            label_title = new Gtk.Label (inject_operation.title);
            label_title.margin_start = 6;
            label_title.xalign = 0.0f;
            
            vbox.pack_start (label_title, false, false, 0);

            var label_subtitle = new Gtk.Label (inject_operation.url + " - " + inject_operation.inject_description);
            label_subtitle.name = "lbl_inject_subtitle";
            label_subtitle.margin_start = 6;
            label_subtitle.margin_bottom = 3;
            label_subtitle.xalign = 0.0f;
            
            vbox.pack_start (label_subtitle, false, false, 0);

            this.margin_top = 3;
            this.margin_bottom = 3;

            this.set_selectable (true);
            this.show_all();
        }

        public void update_inject_operation (InjectOperation operation) {
            this.inject_operation = operation;
            label_title.set_text (operation.title);
            if (inject_operation.get_status () == InjectOperation.Status.UNDERWAY) {
                progress_bar.fraction = ((double)inject_operation.percent_completed * 0.01);
            }
        }
    }
}
