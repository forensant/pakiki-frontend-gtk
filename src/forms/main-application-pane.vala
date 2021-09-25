namespace Proximity {
    interface MainApplicationPane : Object {
        
        public virtual bool back_visible () {
            return false;
        }

        public virtual bool new_visible () {
            return false;
        }

        public virtual bool search_sensitive () {
            return true;
        }

        public abstract void   on_search (string text, bool exclude_resources);
        public abstract string pane_name ();
        public abstract void   reset_state ();
    }
}
