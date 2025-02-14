namespace Pakiki {
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
            set_draw_func (draw);
        }

        private void draw (Gtk.DrawingArea drawing_area, Cairo.Context cr, int width, int height) {
            var rectangle = Gdk.Rectangle () {
                x = 0,
                y = 0,
                width = width,
                height = height
            };
            var selected = ((this.get_state_flags () & Gtk.StateFlags.SELECTED) == Gtk.StateFlags.SELECTED);
            render (cr, rectangle, this.get_style_context (), selected);
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.WIDTH_FOR_HEIGHT;
        }

        public override void measure (Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum = for_size;
            natural = for_size;
            minimum_baseline = -1;
            natural_baseline = -1;
        }

        public bool render (Cairo.Context cr, Gdk.Rectangle area, Gtk.StyleContext style_context, bool selected) {
            if (fraction < 0.0) {
                return false;
            }

            cr.save ();
            var x = (area.width / 2) + area.x;
            var y = (area.height / 2) + area.y;
            var radius = double.min (area.width / 2,
                                     area.height / 2) - 5;

            cr.set_line_cap (Cairo.LineCap.BUTT);

            //var state = selected ? Gtk.StateFlags.SELECTED : Gtk.StateFlags.NORMAL;
            var colour = style_context.get_color ();

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
                var diameter = radius * 2;
                cr.set_line_width (1.5);
                
                // these are all relative to the centre of the circle
                cr.move_to (x - (diameter * 0.25), y); // first point (start of the tick)
                cr.line_to (x - (diameter * 0.05), y + (diameter * 0.2)); // the centre point
                cr.line_to (x + (diameter * 0.25), y - (diameter * 0.25)); // last bit of the tick

                cr.stroke ();
            }

            cr.restore ();

            return false;
        }
    }
}