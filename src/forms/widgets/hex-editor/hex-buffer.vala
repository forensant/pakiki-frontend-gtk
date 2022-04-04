namespace Proximity {
    public interface HexBuffer : Object {
        public signal void length_changed ();

        public abstract uint8[] data (uint64 from, uint64 to);
        public abstract bool data_cached (uint64 from, uint64 to);
        public abstract uint64 length ();

        public virtual void insert (uint64 at, uint8[] data) {}
        public virtual bool pos_in_headers (uint64 pos) { return false; }
        public virtual void remove (uint64 from, uint64 to) {}
    }
}
