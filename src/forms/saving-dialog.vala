namespace Pakiki {
    
    class SavingDialog : Gtk.Window {

        public SavingDialog () {
            modal = true;
            title = "Saving";

            var label = new Gtk.Label ("Saving project, this could take a few minutes for large projects.\nPlease do not reset or shut down your PC until this is complete.");
            var spinner = new Gtk.Spinner ();
            spinner.spinning = true;

            spinner.margin_start = 12;
            spinner.margin_end = 18;
            spinner.margin_top = 18;
            spinner.margin_bottom = 18;
            label.margin_start = 18;
            label.margin_top = 18;
            label.margin_bottom = 18;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box.append (label);
            box.append (spinner);
            
            set_child (box);
        }
    }
}
