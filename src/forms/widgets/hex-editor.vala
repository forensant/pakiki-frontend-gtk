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

        private bool selecting = false;
        private double selection_start_x = -1;
        private double selection_start_y = -1;
        private int selection_start_charidx = -1;
        private int selection_end_charidx = -1;

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
                set_vadjustment_properties ();
                queue_draw ();
            }
        }

        public HexEditor () {
            var bytes = new uint8[0];
            buffer = new HexStaticBuffer.from_bytes (bytes);

            this.vscroll_policy = Gtk.ScrollablePolicy.MINIMUM;

            this.set_name ("hex-editor");
            this.get_style_context ().add_class ("hex");
            this.add_events (Gdk.EventMask.BUTTON1_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.SCROLL_MASK);

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

                    if (selecting) {
                        selecting = false;
                    } else {
                        selection_start_charidx = -1;
                        selection_end_charidx = -1;
                        queue_draw ();
                    }
                    
                    return true;
                } else if (evt.button == 3) {
                    show_right_click_menu (evt);
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
        }

        public override bool draw (Cairo.Context cr) {
            cr.save ();
            
            var style = this.get_style_context ();
            style.render_background (cr, 0, 0, get_allocated_width (), get_allocated_height ());

            Pango.FontDescription font;
            style.get (this.get_state_flags (), "font", out font);

            var lines_to_display = lines_per_page () + 2;

            var text_to_set = new StringBuilder ();

            var first_line = (int) vadjustment.value;
            var last_line = first_line + lines_to_display;

            if (last_line > line_count ()) {
                last_line = (int) line_count ();
            }

            for (int i = first_line; i < last_line; i++) {
                var formatted_string = ("%0" + OFFSET_CHARACTERS.to_string() + "d\n").printf(i * 16);
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

            var hex_line_width = draw_hex_lines (cr, first_line, last_line, x_offset);
            x_offset += hex_line_width + PADDING_BETWEEN_SECTIONS;

            style.add_class ("hex-border");
            style.render_background (cr, x_offset - 7, 0, 1, get_allocated_height ());
            style.remove_class ("hex-border");

            var ascii_line_width = draw_ascii_lines (cr, first_line, last_line, x_offset);

            style.add_class ("hex-border");
            style.render_background (cr, x_offset + ascii_line_width + 6, 0, 1, get_allocated_height ());
            style.remove_class ("hex-border");

            cr.restore ();

            return false;
        }

        private int draw_ascii_lines (Cairo.Context cr, int line_from, int line_to, int x_offset) {
            // TODO: This works basically the same as draw_hex_lines, so we can probably use function pointers to extract out the commonalities
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

            for (var i = 0; i < bytes.length; i++) {
                var hex_char = bytes[i];
                if (hex_char < 32 || hex_char > 126) {
                    hex_char = '.';
                }

                var formatted_string = "%c".printf (hex_char);

                var blank_string = " ";
                var end_selection = ((i + from) == end_idx);
                
                if (i % 16 == 15) {
                    formatted_string += "\n";
                    blank_string = " \n";
                    if (start_of_selection != -1) {
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
                
                if ((i + from) < start_idx) {
                    // before selection
                    buffers[0].append (formatted_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (blank_string);
                } else if ((i + from) >= start_idx && (i + from) <= end_idx) {
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

            return render_selection (cr, x_offset, buffers[0].str, buffers[1].str, buffers[2].str);
        }

        private int draw_hex_lines (Cairo.Context cr, int line_from, int line_to, int x_offset) {
            // there are 3 different buffers, one before selection, one during selection, one after selection
            // then all three are rendered on top of each other

            // 0 represents before the selection
            // 1 represents during the selection
            // 2 represents after the selection
            StringBuilder[] buffers = new StringBuilder[3];
            buffers[0] = new StringBuilder ();
            buffers[1] = new StringBuilder ();
            buffers[2] = new StringBuilder ();

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

            for (var i = 0; i < bytes.length; i++) {
                var formatted_string = "%02x".printf (bytes[i]);
                var blank_string = "   ";

                var end_selection = ((i + from) == end_idx);
                
                if (i % 16 == 15) {
                    formatted_string += "\n";
                    blank_string = "  \n";
                    if (start_of_selection != -1) {
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
                
                if ((i + from) < start_idx) {
                    // before selection
                    buffers[0].append (formatted_string);
                    buffers[1].append (blank_string);
                    buffers[2].append (blank_string);
                } else if ((i + from) >= start_idx && (i + from) <= end_idx) {
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

            return render_selection (cr, x_offset, buffers[0].str, buffers[1].str, buffers[2].str);
        }

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

        private int get_char_idx_from_x_y (double x, double y) {
            // for now let's just do the main selection area
            var char_width = get_char_width ();
            var start_of_hex_chars = (char_width * OFFSET_CHARACTERS) + PADDING_BETWEEN_SECTIONS + 6; // 6 for the initial padding
            var end_of_hex_chars = start_of_hex_chars + (char_width * (3 + (16 * 2) + (7 * 2))); // 3 for the spaces, 16*2 for the hex chars, 7 for the spacing between hex chars
            var start_of_ascii_chars = end_of_hex_chars + PADDING_BETWEEN_SECTIONS;
            var end_of_ascii_chars = start_of_ascii_chars + (char_width * 17);

            y -= TOP_BORDER;

            // hex chars
            if (x > start_of_hex_chars && x < end_of_hex_chars) {
                var halfway_point = ((end_of_hex_chars - start_of_hex_chars) / 2) + start_of_hex_chars;
                var raw_chr_offset = (x - start_of_hex_chars) / char_width;

                var chr_offset = -1.0;

                if (x < halfway_point) {
                    chr_offset = (raw_chr_offset + 1) / 3; // the +1 is due to the first character not having a space before it
                } else {
                    chr_offset = ((raw_chr_offset - (3 * 8) - 2) / 3) + 8;
                }

                chr_offset += (((int)y / get_line_height ()) + (int)this.vadjustment.value) * 16;

                return (int)chr_offset;
            }

            // ascii chars
            if (x > start_of_ascii_chars && x < end_of_ascii_chars) {
                var halfway_point = ((end_of_ascii_chars - start_of_ascii_chars) / 2) + start_of_ascii_chars;
                var raw_chr_offset = (x - start_of_ascii_chars) / char_width;

                var chr_offset = raw_chr_offset;

                if (x > halfway_point) {
                    chr_offset--;
                }

                chr_offset += (((int)y / get_line_height ()) + (int)this.vadjustment.value) * 16;

                return (int)chr_offset;
            }

            // neither
            return -1;
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

        public int lines_per_page () {
            return (int)((double)get_allocated_height () / (double)get_line_height ());
        }

        private int64 line_count () {
            var lines = buffer.length () / 16;
            if (lines * 16 < buffer.length ()) {
                lines++;
            }
            return lines;
        }

        private int render_selection (Cairo.Context cr, int x_offset, string before_selection, string selection, string after_selection) {
            var style = get_style_context ();
            Pango.FontDescription font;
            style.get (this.get_state_flags (), "font", out font);

            // unselected text (before selection)
            var before_layout = create_pango_layout(before_selection);
            before_layout.set_font_description(font);

            int line_width, text_height;
            before_layout.get_pixel_size(out line_width, out text_height);
            style.render_layout (cr, x_offset, TOP_BORDER, before_layout);

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

            int start_chr = get_char_idx_from_x_y (selection_start_x, selection_start_y);
            int end_chr = get_char_idx_from_x_y (end_x, end_y);

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
                var clipboard = Gtk.Clipboard.get_default (Gdk.Display.get_default ());
                clipboard.set_text (selected_text, selected_text.length);
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

            menu.popup_at_pointer (evt);
        }
    }
}
