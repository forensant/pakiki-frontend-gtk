namespace Proximity {
    public interface HexBuffer : Object {
        public signal void length_changed ();

        public abstract uint8[] data (uint64 from, uint64 to);
        public abstract bool data_cached (uint64 from, uint64 to);
        public abstract uint64 length ();
    }
}
