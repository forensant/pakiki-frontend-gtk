namespace Proximity {
    class InjectListRow : Gtk.ListBoxRow {

        public enum Type {
            INJECT_SCAN,
            LABEL,
            PLACEHOLDER
        }

        public Type row_type                    { get; set; }
        public InjectOperation.Status status    { get; set; }
        public InjectOperation inject_operation { get; set; }

        private Gtk.Label label_title;
        private Gtk.ProgressBar progress_bar;

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

            this.set_selectable (false);
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

            label_title.show ();

            this.set_selectable (false);
        }

        public InjectListRow.inject_scan (InjectOperation inject_operation) {
            this.row_type         = Type.INJECT_SCAN;
            this.status           = inject_operation.get_status ();
            this.inject_operation = inject_operation;

            var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
            hbox.set_spacing (5);
            this.add (hbox);

            Gtk.Image image;

            if (inject_operation.get_status () == InjectOperation.Status.COMPLETED) {
                image = new Gtk.Image.from_icon_name ("gtk-apply", Gtk.IconSize.DND);
            } else if (inject_operation.get_status () == InjectOperation.Status.UNDERWAY) {
                image = new Gtk.Image.from_icon_name ("media-playback-start", Gtk.IconSize.DND);
            } else {
                image = new Gtk.Image.from_icon_name ("document-open", Gtk.IconSize.DND);
            }
            image.pixel_size = 32;
            image.margin_start = 6;
            hbox.pack_start (image, false, false, 0);

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
            vbox.set_spacing (2);
            hbox.pack_start (vbox, true, true, 0);

            label_title = new Gtk.Label (inject_operation.title);
            label_title.margin_start = 6;
            label_title.xalign = 0.0f;
            
            vbox.pack_start (label_title, false, false, 0);

            var label_subtitle = new Gtk.Label (inject_operation.url + " - " + inject_operation.inject_description);
            label_subtitle.margin_start = 6;
            label_subtitle.xalign = 0.0f;
            vbox.pack_start (label_subtitle, false, false, 0);

            if (inject_operation.get_status () == InjectOperation.Status.UNDERWAY) {
                progress_bar = new Gtk.ProgressBar ();
                progress_bar.set_fraction ((double)inject_operation.percent_completed * 0.01);
                progress_bar.margin_start = 6;
                progress_bar.margin_end = 12;
                progress_bar.margin_bottom = 6;
                vbox.pack_start (progress_bar, true, true, 0);
            }

            this.set_selectable (true);
            this.show_all();
        }

        public void update_inject_operation (InjectOperation operation) {
            this.inject_operation = operation;
            label_title.set_text (operation.title);
            if (inject_operation.get_status () == InjectOperation.Status.UNDERWAY) {
                progress_bar.set_fraction ((double)inject_operation.percent_completed * 0.01);
            }
        }
    }
}
