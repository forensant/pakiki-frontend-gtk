namespace Proximity {
    public interface HexBuffer : Object {
        public signal void length_changed ();

        public abstract uint8[] data (int from, int to);
        public abstract bool data_cached (int from, int to);
        public abstract int64 length ();
    }
}
