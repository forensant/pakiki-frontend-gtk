namespace Proximity {

    public class HexEditor : Gtk.DrawingArea, Gtk.Scrollable {

        // Phase 2 - editing:
        //   1. [ ] Typing in input (and updating the buffer)
        //   2. [ ] Undo/redo
        //   3. [ ] Copy/paste
        //   4. [ ] Selection with keyboard shortcuts (including page up/page down)

        const int OFFSET_CHARACTERS = 8;
        const int PADDING_BETWEEN_SECTIONS = 32;
        const int TOP_BORDER = 6;
        const string HEX_CHARS = "0123456789ABCDEF";

        enum Area {
            NONE,
            HEX,
            ASCII
        }

        private double _fraction = 0.0;
        public double fraction {
            get { return _fraction; }
            set {
                _fraction = value;
                queue_draw ();
            }
        }

        private bool half_selection = false;
        private Area insertion_area = Area.NONE;
        private bool selecting = false;
        private double selection_start_x = -1;
        private double selection_start_y = -1;
        private int64 selection_start_charidx = 0;
        private int64 selection_end_charidx = 0;

        private Gtk.Adjustment _hadjustment;
        public Gtk.Adjustment hadjustment {
            get { return _hadjustment; }
            set { _hadjustment = value; }
        }

        private Gtk.ScrollablePolicy _hscroll_policy;
        public Gtk.ScrollablePolicy hscroll_policy {
            get { return _hscroll_policy; }
            set { _hscroll_policy = value; }
        }

        private Gtk.Adjustment _vadjustment;
        public Gtk.Adjustment vadjustment {
            get { return _vadjustment; }
            set {
                _vadjustment = value;
                set_vadjustment_properties ();
            }
        }

        private Gtk.ScrollablePolicy _vscroll_policy;
        public Gtk.ScrollablePolicy vscroll_policy {
            get { return _vscroll_policy; }
            set { _vscroll_policy = value; }
        }

        private HexBuffer _buffer;
        public HexBuffer buffer {
            get { return _buffer; }
            set {
                _buffer = value;
                buffer.length_changed.connect ( () => {
                    set_vadjustment_properties ();
                });
                set_vadjustment_properties ();
                vadjustment.set_value (0);
                selection_start_charidx = selection_end_charidx = -1;
                queue_draw ();
            }
        }

        public HexEditor () {
            var bytes = new uint8[0];
            buffer = new HexStaticBuffer.from_bytes (bytes);

            this.vscroll_policy = Gtk.ScrollablePolicy.MINIMUM;

            this.set_name ("hex-editor");
            this.get_style_context ().add_class ("hex");
            this.can_focus = true;
            this.add_events (Gdk.EventMask.BUTTON1_MOTION_MASK |
                Gdk.EventMask.BUTTON_PRESS_MASK |
                Gdk.EventMask.BUTTON_RELEASE_MASK |
                Gdk.EventMask.KEY_PRESS_MASK |
                Gdk.EventMask.POINTER_MOTION_MASK |
                Gdk.EventMask.SCROLL_MASK);

            this.size_allocate.connect ( (allocation) => {
                set_vadjustment_properties ();
            });

            this.scroll_event.connect ( (evt) => {
                int multiplier = 1;
                if (evt.direction == Gdk.ScrollDirection.UP) {
                    multiplier = -1;
                } else if (evt.direction != Gdk.ScrollDirection.DOWN) {
                    return false;
                }

                this.vadjustment.value = this.vadjustment.value + (this.vadjustment.step_increment * multiplier);
                return true;
            });

            this.button_press_event.connect ((evt) => {
                if (evt.button == 1) {
                    this.is_focus = true;

                    selecting = false;

                    selection_start_x = evt.x;
                    selection_start_y = evt.y;
                    return true;
                }

                return false;
            });

            this.button_release_event.connect ((evt) => {
                if (evt.button == 1) {
                    selection_start_x = -1;
                    selection_start_y = -1;

                    if (!selecting) {
                        selection_start_charidx = get_char_idx_from_x_y (evt.x, evt.y, out half_selection);
                        selection_end_charidx = selection_start_charidx;
                        insertion_area = get_area_at_position ((int)evt.x, (int)evt.y);
                        queue_draw ();
                    }
                    
                    return true;
                } else if (evt.button == 3) {
                    show_right_click_menu (evt);
                    return true;
                }

                return false;
            });

            this.motion_notify_event.connect ((evt) => {
                var cursor_name = "default";
                if (get_area_at_position ((int)evt.x, (int)evt.y) != Area.NONE) {
                    cursor_name = "text";
                }

                var cursor = new Gdk.Cursor.from_name (this.get_display (), cursor_name);
                this.get_window ().set_cursor (cursor);

                return set_selection (evt.x, evt.y);
            });

            this.key_press_event.connect (on_key_press);
        }

        public override bool draw (Cairo.Context cr) {
            cr.save ();
            
            var style = this.get_style_context ();
            style.render_background (cr, 0, 0, get_allocated_width (), get_allocated_height ());

            Pango.FontDescription font;
            style.get (this.get_state_flags (), "font", out font);

            var lines_to_display = lines_per_page () + 2;

            var text_to_set = new StringBuilder ();

            var first_line = (int64) vadjustment.value;
            var last_line = first_line + lines_to_display;

            if (last_line > line_count ()) {
                last_line = (int64) line_count ();
            }

            for (int64 i = first_line; i < last_line; i++) {
                var formatted_string = ("%0" + OFFSET_CHARACTERS.to_string() + "llu\n").printf(i * 16);
                text_to_set.append (formatted_string);
            }

            // http://developer.gnome.org/pangomm/unstable/classPango_1_1Layout.html
            var line_no_layout = create_pango_layout(text_to_set.str);
            line_no_layout.set_font_description(font);

            int x_offset;
            int text_height;

            //get the text dimensions (it updates the variables -- by reference)
            line_no_layout.get_pixel_size(out x_offset, out text_height);
            
            style.add_class ("hex-background");
            style.render_background (cr, 0, 0, x_offset + 12, get_allocated_height ());
            style.remove_class ("hex-background");

            style.add_class ("hex-border");
            style.render_background (cr, x_offset + 11, 0, 1, get_allocated_height ());
            style.remove_class ("hex-border");
            x_offset += PADDING_BETWEEN_SECTIONS + 6;

            style.render_layout (cr, 6, TOP_BORDER, line_no_layout);

            //var hex_line_width = draw_hex_lines (cr, first_line, last_line, x_offset);
            var hex_line_width = draw_lines (cr, first_line, last_line, x_offset, Area.HEX, (b, pos) => {
                var formatted_string = "%02x".printf (b);
                                
                if (pos % 16 == 15) {
                    // do nothing
                } else if (pos % 8 == 7) {
                    formatted_string += "   ";
                } else {
                    formatted_string += " ";
                }
                return formatted_string;
            });
            x_offset += hex_line_width + PADDING_BETWEEN_SECTIONS;

            style.add_class ("hex-border");
            style.render_background (cr, x_offset - 7, 0, 1, get_allocated_height ());
            style.remove_class ("hex-border");

            //var ascii_line_width = draw_ascii_lines (cr, first_line, last_line, x_offset);

            style.add_class ("hex-background");
            var ascii_width = get_char_width () * 17; // 1 extra for the space in the middle
            style.render_background (cr, x_offset - 6, 0, ascii_width + 12, get_allocated_height ());
            style.remove_class ("hex-background");

            var ascii_line_width = draw_lines (cr, first_line, last_line, x_offset, Area.ASCII, (b, pos) => {
                if (b < 32 || b > 126) {
                    b = '.';
                }

                var formatted_string = "%c".printf (b);
                
                if (pos % 8 == 7 && pos % 16 != 15) {
                    formatted_string += " ";
                }
                return formatted_string;
            });


            style.add_class ("hex-border");
            style.render_background (cr, x_offset + ascii_line_width + 6, 0, 1, get_allocated_height ());
            style.remove_class ("hex-border");

            cr.restore ();

            return false;
        }

        delegate string ByteToStringFunc (uint8 byte, int pos);
        private int draw_lines (Cairo.Context cr, int64 line_from, int64 line_to, int x_offset, Area area, ByteToStringFunc byte_to_string) {
            // there are 3 different buffers, one before selection, one during selection, one after selection
            // then all three are rendered on top of each other

            // 0 represents before the selection
            // 1 represents during the selection
            // 2 represents after the selection
            StringBuilder[] buffers = new StringBuilder[3];
            buffers[0] = new StringBuilder ();
            buffers[1] = new StringBuilder ();
            buffers[2] = new StringBuilder ();

            var insertion_offset = -1;

            var start_idx = selection_start_charidx;
            var end_idx = selection_end_charidx;
            if (start_idx > end_idx) {
                var tmp = start_idx;
                start_idx = end_idx;
                end_idx = tmp;
            }

            var from = line_from * 16;
            var bytes = buffer.data (from, line_to * 16);

            var style = this.get_style_context ();
            var start_of_selection = -1;
            int length = -1;

            for (var i = 0; i < bytes.length; i++) {
                var formatted_string = byte_to_string (bytes[i], i);

                var blank_string = "";
                for (var j = 0; j < formatted_string.length; j++) {
                    blank_string += " ";
                }

                if (i % 16 == 15) {
                    blank_string += "\n";
                    formatted_string += "\n";
                }

                // calculate the start/end of selections
                var end_selection = (((i + from) == end_idx) && selecting);

                if (i % 16 == 15 && start_of_selection != -1 && selecting) {
                    end_selection = true;
                }

                if (selecting && (i + from + 1) == buffer.length () && end_idx >= buffer.length () && start_of_selection != -1) {
                    end_selection = true;
                }

                if ((from + i) == start_idx) {
                    start_of_selection = i % 16;
                }
                if (start_of_selection == -1 && i % 16 == 0 && (from + i) >= start_idx && (from + i) <= end_idx) {
                    start_of_selection = i % 16;
                }
                
                // draw the background for selected text
                if (end_selection) {
                    int width, x;
                    if (area == Area.ASCII) {
                        x = get_char_ascii_x_offset (start_of_selection, x_offset, false);
                        width = get_char_ascii_x_offset ((i % 16) + 1, x_offset, true) - x;
                    } else {
                        x = get_char_hex_x_offset (start_of_selection, x_offset, false);
                        width = get_char_hex_x_offset ((i % 16) + 1, x_offset, true) - x;
                    }

                    var y = ((i / 16) * get_line_height ()) + TOP_BORDER;
                    var rect = Gdk.Rectangle() {
                        x = x,
                        y = y,
                        width = width,
                        height = (((i/16)+1) * get_line_height ())-y + TOP_BORDER
                    };

                    style.add_class ("hex-selected");
                    style.render_background (cr, rect.x, rect.y, rect.width, rect.height);
                    style.remove_class ("hex-selected");
                    
                    start_of_selection = -1;
                }

                // calculate the insertion character position
                if (i + from == start_idx) {
                    insertion_offset = length + 1;
                }

                var total_length = buffer.length ();
                if (i + from == total_length - 1 && start_idx >= total_length) {
                    insertion_offset = length + 1;
                }

                length += formatted_string.length;

                // create the text to draw
                if ((i + from) < start_idx) {
                    // before selection
                    buffers[0].append (formatted_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (blank_string);
                } else if ((i + from) >= start_idx && (i + from) <= end_idx && selecting) {
                    // during selection
                    buffers[0].append (blank_string);
                    buffers[1].append (formatted_string);
                    buffers[2].append (blank_string);
                } else {
                    // after selection
                    buffers[0].append (blank_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (formatted_string);
                }
            }

            if (insertion_area != area) {
                insertion_offset = -1;
            }

            return render_selection (cr, x_offset, buffers[0].str, buffers[1].str, buffers[2].str, insertion_offset);
        }

        /*private int draw_ascii_lines (Cairo.Context cr, int64 line_from, int64 line_to, int x_offset) {
            // TODO: This works basically the same as draw_hex_lines, so we can probably use function pointers to extract out the commonalities
            // TODO: Extract out
            var style = get_style_context ();
            style.add_class ("hex-background");
            var ascii_width = get_char_width () * 17; // 1 extra for the space in the middle
            style.render_background (cr, x_offset - 6, 0, ascii_width + 12, get_allocated_height ());
            style.remove_class ("hex-background");
            
            // this works the same way as the draw_hex_lines function
            StringBuilder[] buffers = new StringBuilder[3];
            buffers[0] = new StringBuilder ();
            buffers[1] = new StringBuilder ();
            buffers[2] = new StringBuilder ();

            var insertion_offset = -1;

            var start_idx = selection_start_charidx;
            var end_idx = selection_end_charidx;
            if (start_idx > end_idx) {
                var tmp = start_idx;
                start_idx = end_idx;
                end_idx = tmp;
            }

            var from = line_from * 16;
            var bytes = buffer.data (from, line_to * 16);

            var start_of_selection = -1;
            var length = 0;

            for (var i = 0; i < bytes.length; i++) {
                var hex_char = bytes[i];
                if (hex_char < 32 || hex_char > 126) {
                    hex_char = '.';
                }

                var formatted_string = "%c".printf (hex_char);

                var blank_string = " ";
                var end_selection = (((i + from) == end_idx) && selecting);

                if (selecting && (i + from + 1) == buffer.length () && end_idx >= buffer.length () && start_of_selection != -1) {
                    end_selection = true;
                }
                
                if (i % 16 == 15) {
                    formatted_string += "\n";
                    blank_string = " \n";
                    if (start_of_selection != -1 && selecting) {
                        end_selection = true;
                    }
                } else if (i % 8 == 7) {
                    formatted_string += " ";
                    blank_string = "  ";
                }

                if ((from + i) == start_idx) {
                    start_of_selection = i % 16;
                }
                if (start_of_selection == -1 && i % 16 == 0 && (from + i) >= start_idx && (from + i) <= end_idx) {
                    start_of_selection = i % 16;
                }
                
                // draw the background for selected text
                if (end_selection) {
                    var x = get_char_ascii_x_offset (start_of_selection, x_offset, false);
                    var y = ((i / 16) * get_line_height ()) + TOP_BORDER;
                    var rect = Gdk.Rectangle() {
                        x = x,
                        y = y,
                        width = get_char_ascii_x_offset ((i % 16) + 1, x_offset, true) - x,
                        height = (((i/16)+1) * get_line_height ())-y + TOP_BORDER
                    };

                    style.add_class ("hex-selected");
                    style.render_background (cr, rect.x, rect.y, rect.width, rect.height);
                    style.remove_class ("hex-selected");
                    
                    start_of_selection = -1;
                }

                if (i + from == start_idx) {
                    insertion_offset = length;
                }

                var total_length = buffer.length ();
                if (i + from == total_length - 1 && start_idx >= total_length) {
                    insertion_offset = length + 1;
                }

                length += formatted_string.length;
                
                if ((i + from) < start_idx) {
                    // before selection
                    buffers[0].append (formatted_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (blank_string);
                } else if ((i + from) >= start_idx && (i + from) <= end_idx && selecting) {
                    // during selection
                    buffers[0].append (blank_string);
                    buffers[1].append (formatted_string);
                    buffers[2].append (blank_string);
                } else {
                    // after selection
                    buffers[0].append (blank_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (formatted_string);
                }
            }

            if (insertion_area != Area.ASCII) {
                insertion_offset = -1;
            }

            return render_selection (cr, x_offset, buffers[0].str, buffers[1].str, buffers[2].str, insertion_offset);
        }*/

        /*private int draw_hex_lines (Cairo.Context cr, int64 line_from, int64 line_to, int x_offset) {
            // there are 3 different buffers, one before selection, one during selection, one after selection
            // then all three are rendered on top of each other

            // 0 represents before the selection
            // 1 represents during the selection
            // 2 represents after the selection
            StringBuilder[] buffers = new StringBuilder[3];
            buffers[0] = new StringBuilder ();
            buffers[1] = new StringBuilder ();
            buffers[2] = new StringBuilder ();

            var insertion_offset = -1;

            var start_idx = selection_start_charidx;
            var end_idx = selection_end_charidx;
            if (start_idx > end_idx) {
                var tmp = start_idx;
                start_idx = end_idx;
                end_idx = tmp;
            }

            var from = line_from * 16;
            var bytes = buffer.data (from, line_to * 16);

            var style = this.get_style_context ();
            var start_of_selection = -1;
            int length = -1;

            for (var i = 0; i < bytes.length; i++) {
                var formatted_string = "%02x".printf (bytes[i]);
                var blank_string = "   ";

                var end_selection = (((i + from) == end_idx || i + from == buffer.length () - 1) && selecting);

                if (selecting && (i + from + 1) == buffer.length () && end_idx >= buffer.length () && start_of_selection != -1) {
                    end_selection = true;
                }
                                
                if (i % 16 == 15) {
                    formatted_string += "\n";
                    blank_string = "  \n";
                    if (start_of_selection != -1 && selecting) {
                        end_selection = true;
                    }
                } else if (i % 8 == 7) {
                    formatted_string += "   ";
                    blank_string = "     ";
                } else {
                    formatted_string += " ";
                }

                if ((from + i) == start_idx) {
                    start_of_selection = i % 16;
                }
                if (start_of_selection == -1 && i % 16 == 0 && (from + i) >= start_idx && (from + i) <= end_idx) {
                    start_of_selection = i % 16;
                }
                
                // draw the background for selected text
                if (end_selection) {
                    var x = get_char_hex_x_offset (start_of_selection, x_offset, false);
                    var y = ((i / 16) * get_line_height ()) + TOP_BORDER;
                    var rect = Gdk.Rectangle() {
                        x = x,
                        y = y,
                        width = get_char_hex_x_offset ((i % 16) + 1, x_offset, true) - x,
                        height = (((i/16)+1) * get_line_height ())-y+ TOP_BORDER
                    };

                    style.add_class ("hex-selected");
                    style.render_background (cr, rect.x, rect.y, rect.width, rect.height);
                    style.remove_class ("hex-selected");
                    
                    start_of_selection = -1;
                }

                if (i + from == start_idx) {
                    insertion_offset = length + 1;
                    if (half_selection) {
                        insertion_offset++;
                    }
                }

                var total_length = buffer.length ();
                if (i + from == total_length - 1 && start_idx >= total_length) {
                    insertion_offset = length + 1;
                }

                length += formatted_string.length;
                
                if ((i + from) < start_idx) {
                    // before selection
                    buffers[0].append (formatted_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (blank_string);
                } else if ((i + from) >= start_idx && (i + from) <= end_idx && start_idx != end_idx) {
                    // during selection
                    buffers[0].append (blank_string);
                    buffers[1].append (formatted_string);
                    buffers[2].append (blank_string);
                } else {
                    // after selection
                    buffers[0].append (blank_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (formatted_string);
                }
            }

            if (insertion_area != Area.HEX) {
                insertion_offset = -1;
            }

            return render_selection (cr, x_offset, buffers[0].str, buffers[1].str, buffers[2].str, insertion_offset);
        }*/

        private Area get_area_at_position (int x, int y) {
            var char_width = get_char_width ();
            var start_of_hex_chars = (char_width * OFFSET_CHARACTERS) + PADDING_BETWEEN_SECTIONS + 6; // 6 for the initial spacing
            var end_of_hex_chars = start_of_hex_chars + (char_width * (3 + (16 * 2) + (7 * 2))); // 3 for the spaces, 16*2 for the hex chars, 7 for the spacing between hex chars
            var start_of_ascii = end_of_hex_chars + PADDING_BETWEEN_SECTIONS;
            var end_of_ascii = start_of_ascii + (char_width * 17);

            if (x > start_of_hex_chars && x < end_of_hex_chars) {
                return Area.HEX;
            } else if (x > start_of_ascii && x < end_of_ascii) {
                return Area.ASCII;
            } else {
                return Area.NONE;
            }
        }

        public bool get_border (out Gtk.Border b) {
            return false;
        }

        private int get_char_ascii_x_offset (int idx, int ascii_x_offset, bool end) {
            var addition = 0;
            if (idx > 7) {
                addition += 1; //the middle separator
            }
            if (end && idx == 8) {
                addition -= 1;
            }
            idx = idx + addition;

            return (idx * get_char_width ()) + ascii_x_offset;
        }

        private int get_char_hex_x_offset (int idx, int hex_x_offset, bool end) {
            var addition = 0;
            if (idx > 7) {
                addition += 2; //the middle separator
            }
            if (end && idx == 8) {
                addition -= 2;
            }
            idx = idx * 3;
            idx = idx + addition;
            if (end) {
                idx -= 1;
            }

            return (idx * get_char_width ()) + hex_x_offset;
        }

        private int get_char_idx_from_x_y (double x, double y, out bool half_selection) {
            var char_width = get_char_width ();
            var start_of_hex_chars = (char_width * OFFSET_CHARACTERS) + PADDING_BETWEEN_SECTIONS + 6; // 6 for the initial padding
            var end_of_hex_chars = start_of_hex_chars + (char_width * (3 + (16 * 2) + (7 * 2))); // 3 for the spaces, 16*2 for the hex chars, 7 for the spacing between hex chars
            var start_of_ascii_chars = end_of_hex_chars + PADDING_BETWEEN_SECTIONS;
            var end_of_ascii_chars = start_of_ascii_chars + (char_width * 17);

            y -= TOP_BORDER;
            half_selection = false;

            var chr_offset = -1.0;
            
            // hex chars
            if (x > start_of_hex_chars && x < end_of_hex_chars) {
                var halfway_point = ((end_of_hex_chars - start_of_hex_chars) / 2) + start_of_hex_chars;
                var raw_chr_offset = (x - start_of_hex_chars) / char_width;

                if (x < halfway_point) {
                    chr_offset = (raw_chr_offset + 1) / 3; // the +1 is due to the first character not having a space before it
                    half_selection = ((int)raw_chr_offset % 3) == 1;
                } else {
                    chr_offset = ((raw_chr_offset - (3 * 8) - 1) / 3) + 8;
                    half_selection = ((int)raw_chr_offset % 3) == 0;
                }

                chr_offset += (((int)y / get_line_height ()) + (int)this.vadjustment.value) * 16;
            }

            // ascii chars
            if (x > start_of_ascii_chars && x < end_of_ascii_chars) {
                var halfway_point = ((end_of_ascii_chars - start_of_ascii_chars) / 2) + start_of_ascii_chars;
                var raw_chr_offset = (x - start_of_ascii_chars) / char_width;

                chr_offset = raw_chr_offset;

                if (x > halfway_point) {
                    chr_offset--;
                }

                chr_offset += (((int)y / get_line_height ()) + (int)this.vadjustment.value) * 16;
            }

            if (chr_offset == -1) {
                return -1;
            }

            if (chr_offset < 0) {
                chr_offset = 0;
            } else if (chr_offset > this.buffer.length ()) {
                chr_offset = this.buffer.length ();
            }

            return (int)chr_offset;
        }

        private int get_char_width () {
            // given these are monospace, all characters should be the same width
            Pango.FontDescription font;
            get_style_context ().get (this.get_state_flags (), "font", out font);

            var l = create_pango_layout("A");
            l.set_font_description(font);

            int width, height;
            l.get_pixel_size(out width, out height);

            return width;
        }

        private int get_line_height () {
            Pango.FontDescription font;
            get_style_context ().get (this.get_state_flags (), "font", out font);

            var l = create_pango_layout("A0");
            l.set_font_description(font);

            int width, height;
            l.get_pixel_size(out width, out height);

            return height;
        }
        
        public override void get_preferred_width_for_height (int height, out int minimum, out int natural) {
            minimum = height;
            natural = height;
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.WIDTH_FOR_HEIGHT;
        }

        private string get_selected_text (Area area) {
            if (area == Area.NONE) {
                return "";
            }

            var start = selection_start_charidx;
            var end = selection_end_charidx;
            if (start > end) {
                var tmp = start;
                start = end;
                end = tmp;
            }

            var bytes = buffer.data (start, end + 1);

            var str = "";
            if (area == Area.ASCII) {
                for (var i = 0; i < bytes.length; i++) {
                    var hex_char = bytes[i];
                    if (hex_char < 32 || hex_char > 126) {
                        hex_char = '.';
                    }

                    var formatted_string = "%c".printf (hex_char);
                    str += formatted_string;
                }
            } else {
                for (var i = 0; i < bytes.length; i++) {
                    var formatted_string = "%02x".printf (bytes[i]);
                    str += formatted_string;
                }
            }

            return str;
        }

        private void handle_copy (Area area) {
            var selected_text = get_selected_text (area);
            var clipboard = Gtk.Clipboard.get_default (Gdk.Display.get_default ());
            clipboard.set_text (selected_text, selected_text.length);
        }

        private void handle_cut () {
            // TODO: Only if not read-only
            handle_copy (insertion_area);
            // TODO: delete the selected text
        }

        private void handle_paste () {
            // TODO: Only if not read-only
            var display = Gdk.Display.get_default ();
            var clipboard = Gtk.Clipboard.get_default (display);
            var text = clipboard.wait_for_text ();
            
            if (/^[A-F0-9\s]*$/i.match (text)) {
                try {
                    text = /\s/.replace (text, text.length, 0, "", 0);
                } catch {}

                for (int i = 0; i < text.length; i += 2) {
                    // TODO: 
                    /*var hex_char = text.substr (i, 2);
                    var byte_val = Convert.ToByte (hex_char, 16);
                    buffer.insert (buffer.get_iter_at_offset (selection_end_charidx), byte_val);*/
                }
                stdout.printf("Hex string: %s\n", text);
            }
            else if (text.is_ascii ()) {
                stdout.printf("Ascii string: %s\n", text);
            }
            else {
                stdout.printf("Non-Ascii String: %s, length: %d\n", text, text.data.length);
            
            }
            //clipboard.set_text (selected_text, selected_text.length);
        }

        public int lines_per_page () {
            return (int)((double)get_allocated_height () / (double)get_line_height ());
        }

        private uint64 line_count () {
            var lines = buffer.length () / 16;
            if (lines * 16 < buffer.length ()) {
                lines++;
            }
            return lines;
        }

        private bool on_key_press (Gdk.EventKey evt) {
            var found = true;

            if ((evt.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                if (evt.keyval == 'c' || evt.keyval == 'C') {
                    handle_copy (insertion_area);
                    return true;
                }
                
                if (evt.keyval == 'v' || evt.keyval == 'V') {
                    handle_paste ();
                    return true;
                }

                if (evt.keyval == 'x' || evt.keyval == 'X') {
                    handle_cut ();
                    return true;
                }
            }

            // handle the two arrow key cases
            if ((evt.state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                if (evt.keyval == Gdk.Key.Left) {
                    if (!selecting) {
                        selecting = true;
                        selection_start_charidx--;
                    }
                    selection_end_charidx--;
                } else if (evt.keyval == Gdk.Key.Right) {
                    if (!selecting) {
                        selecting = true;
                    }
                    else {
                        selection_end_charidx++;
                    }
                } else if (evt.keyval == Gdk.Key.Up) {
                    if (!selecting) {
                        selecting = true;
                    }
                    selection_end_charidx -= 16;
                } else if (evt.keyval == Gdk.Key.Down) {
                    if (!selecting) {
                        selecting = true;
                    }
                    selection_end_charidx += 16;
                } else if (evt.keyval == Gdk.Key.Home) {
                    if (!selecting) {
                        selecting = true;
                    }
                    selection_end_charidx = 0;
                    selection_start_charidx--;
                } else if (evt.keyval == Gdk.Key.End) {
                    if (!selecting) {
                        selecting = true;
                    }
                    selection_end_charidx = (int64)buffer.length () - 1;
                } else {
                    found = false;
                }
            }
            else {
                if (evt.keyval == Gdk.Key.Left) {
                    selection_start_charidx--;
                    selection_end_charidx--;

                    if (selecting) {
                        selecting = false;
                        var min = int64.min (selection_start_charidx, selection_end_charidx);
                        selection_end_charidx = selection_start_charidx = min;
                    }
                } else if (evt.keyval == Gdk.Key.Right) {
                    selection_start_charidx++;
                    selection_end_charidx++;
                    if (selecting) {
                        selecting = false;
                        var max = int64.max (selection_start_charidx, selection_end_charidx);
                        selection_end_charidx = selection_start_charidx = max;
                    }
                } else if (evt.keyval == Gdk.Key.Up) {
                    selection_start_charidx -= 16;
                    selection_end_charidx -= 16;
                    if (selecting) {
                        selecting = false;
                        var min = int64.min (selection_start_charidx, selection_end_charidx);
                        selection_end_charidx = selection_start_charidx = min;
                    }
                } else if (evt.keyval == Gdk.Key.Down) {
                    selection_start_charidx += 16;
                    selection_end_charidx += 16;
                    if (selecting) {
                        selecting = false;
                        var max = int64.max (selection_start_charidx, selection_end_charidx);
                        selection_end_charidx = selection_start_charidx = max;
                    }
                //} else if (evt.keyval == Gdk.Key.Page_Up) {
                //} else if (evt.keyval == Gdk.Key.Page_Down) {
                } else if (evt.keyval == Gdk.Key.Home) {
                    selection_start_charidx = selection_end_charidx = 0;
                    if (selecting) {
                        selecting = false;
                    }
                } else if (evt.keyval == Gdk.Key.End) {
                    var len = (int64)buffer.length ();
                    len--;
                    selection_start_charidx = selection_end_charidx = len;
                    if (selecting) {
                        selecting = false;
                    }
                } else {
                    found = false;
                }
            }

            if (selection_start_charidx < 0) {
                selection_start_charidx = 0;
            }
            if (selection_end_charidx >= buffer.length ()) {
                selection_end_charidx = (int64)buffer.length ();
            }

            if (found) {
                queue_draw ();
                return true;
            }

            /*if (insertion_area == Area.HEX) {
                if ((evt.keyval >= Gdk.Key.KP_0 && evt.keyval <= Gdk.Key.KP_9) || 
                    (evt.keyval >= 'A' && evt.keyval <= 'F') ||
                    (evt.keyval >= 'a' && evt.keyval <= 'f')) {
                    
                    if (half_selection) {
                        //...
                    }
                    var val = (int)(evt.keyval - Gdk.Key.KP_0);
                    insert_byte (val);
                    return true;
                }
            }*/

            if (insertion_area == Area.ASCII) {
                var selection_from = selection_start_charidx;
                var selection_to = selection_end_charidx;
                if (selection_from > selection_to) {
                    var tmp = selection_from;
                    selection_from = selection_to;
                    selection_to = tmp;
                }

                // regular ASCII characters
                if ((evt.keyval >= 32 && evt.keyval <= 126) || evt.keyval == Gdk.Key.KP_Enter || evt.keyval == Gdk.Key.Return) {
                    uint8[] bytes = {(uint8)evt.keyval};

                    if (evt.keyval == Gdk.Key.KP_Enter || evt.keyval == Gdk.Key.Return) {
                        if (buffer.pos_in_headers (selection_from)) {
                            bytes = new uint8[] {0x0d, 0x0a};
                        }
                        else {
                            bytes[0] = '\n';
                        }
                    }

                    if (selecting) {   
                        buffer.remove (selection_from, selection_to);
                        selecting = false;
                    }

                    buffer.insert (selection_from, bytes);
                    selection_end_charidx = selection_start_charidx = (selection_from + (int64)bytes.length);
                    return true;
                }

                if (evt.keyval == Gdk.Key.BackSpace) {
                    if (!selecting) {
                        selection_from--;
                        if (selection_from < 0) {
                            selection_from = 0;
                        }

                        selection_to--;
                        if (selection_to < 0) {
                            selection_to = 0;
                        }
                    }
                    buffer.remove (selection_from, selection_to);
                    selection_end_charidx = selection_start_charidx = selection_from;
                    selecting = false;
                }

                if (evt.keyval == Gdk.Key.Delete) {
                    buffer.remove (selection_from, selection_to);
                    selection_end_charidx = selection_start_charidx = selection_from;
                    selecting = false;
                }
            }

            return false;
        }

        private int render_selection (Cairo.Context cr, int x_offset, string before_selection, string selection, string after_selection, int selection_offset) {
            var style = get_style_context ();
            Pango.FontDescription font;
            style.get (this.get_state_flags (), "font", out font);

            // unselected text (before selection)
            var before_layout = create_pango_layout(before_selection);
            before_layout.set_font_description(font);

            int line_width, text_height;
            before_layout.get_pixel_size(out line_width, out text_height);
            style.render_layout (cr, x_offset, TOP_BORDER, before_layout);
            if (selection_offset != -1) {
                style.render_insertion_cursor (cr, x_offset, TOP_BORDER, before_layout, selection_offset, Pango.Direction.LTR);
            }

            // selected text
            style.add_class ("hex-selected");
            var selected_layout = create_pango_layout(selection);
            selected_layout.set_font_description(font);
            style.render_layout (cr, x_offset, TOP_BORDER, selected_layout);
            style.remove_class ("hex-selected");

            // unselected text (after selection)
            var after_layout = create_pango_layout(after_selection);
            after_layout.set_font_description(font);
            style.render_layout (cr, x_offset, TOP_BORDER, after_layout);

            return line_width;
        }

        private bool set_selection (double end_x, double end_y) {
            if (selection_start_x == -1 || selection_start_y == -1) {
                return false;
            }

            int start_chr = get_char_idx_from_x_y (selection_start_x, selection_start_y, null);
            int end_chr = get_char_idx_from_x_y (end_x, end_y, null);

            if (start_chr == -1 || end_chr == -1) {
                return false;
            }

            selecting = true;

            selection_start_charidx = start_chr;
            selection_end_charidx = end_chr;
            queue_draw ();

            return true;
        }

        private void set_vadjustment_properties () {
            if (vadjustment == null) {
                vadjustment = new Gtk.Adjustment (0, 0, 0, 0, 0, 0);
            }

            vadjustment.set_lower (0.0);
            vadjustment.set_page_size ((double)lines_per_page ());
            vadjustment.set_step_increment (10.0);
            vadjustment.set_page_increment ((double)lines_per_page ());
            vadjustment.set_upper ((double)line_count ());

            queue_draw ();
        }

        private void show_right_click_menu (Gdk.EventButton evt) {
            var menu = new Gtk.Menu ();
            
            var area = get_area_at_position ((int)evt.x, (int)evt.y);
            if (area == Area.NONE) {
                return;
            }

            var selected_text = get_selected_text (area);

            var copy_item = new Gtk.MenuItem.with_label ("Copy");
            copy_item.activate.connect ( () => {
                handle_copy (area);
            });
            copy_item.show ();
            menu.append (copy_item);

            var separator = new Gtk.SeparatorMenuItem ();
            separator.show ();
            menu.append (separator);

            var menu_item = new Gtk.MenuItem.with_label ("Send to Cyberchef");
            menu_item.activate.connect ( () => {
                var uri = "https://gchq.github.io/CyberChef/#input=" + Soup.URI.encode (Base64.encode (selected_text.data), "");

                try {
                    AppInfo.launch_default_for_uri (uri, null);
                } catch (Error err) {
                    stdout.printf ("Could not launch Cyberchef: %s\n", err.message);
                }
            });
            menu_item.show ();
            menu.append (menu_item);

            stdout.printf("Popping menu\n");
            menu.popup_at_pointer (evt);
        }
    }
}
