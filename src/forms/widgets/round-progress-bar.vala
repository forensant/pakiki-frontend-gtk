namespace Proximity {

    public class RoundProgressBar : Gtk.DrawingArea {

        private double _fraction = 0.0;
        public double fraction {
            get { return _fraction; }
            set {
                _fraction = value;
                queue_draw ();
            }
        }

        public RoundProgressBar () {
        }

        public override bool draw (Cairo.Context cr) {
            cr.save ();
            var x = get_allocated_width () / 2;
            var y = get_allocated_height () / 2;
            var radius = double.min (get_allocated_width () / 2,
                                     get_allocated_height () / 2) - 5;

            cr.set_line_cap (Cairo.LineCap.BUTT);

            var style_context = this.get_style_context ();
            var colour = style_context.get_color (Gtk.StateFlags.NORMAL);

            cr.set_line_width (2);

            // draw the lighter background circle
            cr.arc (x, y, radius, 0, 2 * Math.PI);
            cr.set_source_rgba (colour.red, colour.green, colour.blue, 0.2);
            cr.stroke ();


            // draw the progress circle
            cr.arc (x, y, radius, 0, 2.0 * fraction * Math.PI);
            cr.set_source_rgba (colour.red, colour.green, colour.blue, 0.8);
            cr.stroke ();

            if (fraction == 1.0) {
                // draw the tick
                var width = get_allocated_width ();
                var height = get_allocated_height ();

                //cr.set_source_rgba (colour.red, colour.green, colour.blue, colour.alpha);

                cr.set_line_width (1.5);
                cr.move_to (width * 0.33, y);
                cr.line_to (width * 0.45, height * 0.6);
                cr.line_to (width * 0.65, height * 0.35);
                cr.stroke ();
            }

            cr.restore ();

            return false;
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.WIDTH_FOR_HEIGHT;
        }
    
        public override void get_preferred_width_for_height (int height, out int minimum, out int natural) {
            minimum = height;
            natural = height;
        }
    }
}