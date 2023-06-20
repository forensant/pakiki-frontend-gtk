namespace Pakiki {
    
    class SavingDialog : Gtk.Dialog {

        public SavingDialog () {
            modal = true;
            title = "Saving";

            var spinner = new Gtk.Spinner ();
            spinner.active = true;

            spinner.margin_start = 12;

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            box.pack_start (new Gtk.Label ("Saving project, this could take a few minutes for large projects.\nPlease do not reset or shut down your PC until this is complete."), false, false, 0);
            box.pack_start (spinner, false, false, 0);
            
            get_content_area ().add (box);

            box.margin = 18;

            this.show_all ();
        }
    }
}
