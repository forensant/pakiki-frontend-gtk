// The two server-side syntax highlighters are/have been Chroma and hljs. This file contains
// logic which strips the HTML outputted by them, and converts that into tags which can be
// applied to a Gtk.TextBuffer.

using GXml;

namespace Pakiki {
    class SyntaxHighlighter {

        private bool is_dark_mode () {
            var schemaSource = SettingsSchemaSource.get_default();
            var schema = schemaSource.lookup("org.gnome.desktop.interface", true);
        
            if (schema == null) { 
                return false;
            }

            var settings = new Settings("org.gnome.desktop.interface");
            string? value = settings.get_string("color-scheme");
    
            if (value.contains ("dark")) {
                return true;
            }

            return false;
        }

        public void set_tags (Gtk.TextBuffer buffer) {
            var is_currently_dark = is_dark_mode ();            
            
            if (is_currently_dark) {
                buffer.create_tag("hljs-comment", "foreground", "#5c6370", "style", Pango.Style.ITALIC);
                buffer.create_tag("hljs-quote", "foreground", "#5c6370", "style", Pango.Style.ITALIC);

                buffer.create_tag("hljs-doctag", "foreground", "#c678dd");
                buffer.create_tag("hljs-keyword", "foreground", "#c678dd");
                buffer.create_tag("hljs-formula", "foreground", "#c678dd");

                buffer.create_tag("hljs-selection", "foreground", "#e06c75");
                buffer.create_tag("hljs-name", "foreground", "#e06c75");
                buffer.create_tag("hljs-selector-tag", "foreground", "#e06c75");
                buffer.create_tag("hljs-deletion", "foreground", "#e06c75");
                buffer.create_tag("hljs-subst", "foreground", "#e06c75");

                buffer.create_tag("hljs-literal", "foreground", "#56b6c2");

                buffer.create_tag("hljs-string", "foreground", "#98c379");
                buffer.create_tag("hljs-regexp", "foreground", "#98c379");
                buffer.create_tag("hljs-addition", "foreground", "#98c379");
                buffer.create_tag("hljs-attribute", "foreground", "#98c379");
                
                buffer.create_tag("hljs-attr", "foreground", "#d19a66");
                buffer.create_tag("hljs-variable", "foreground", "#d19a66");
                buffer.create_tag("hljs-template-variable", "foreground", "#d19a66");
                buffer.create_tag("hljs-type", "foreground", "#d19a66");
                buffer.create_tag("hljs-selector-class", "foreground", "#d19a66");
                buffer.create_tag("hljs-selector-attr", "foreground", "#d19a66");
                buffer.create_tag("hljs-selector-pseudo", "foreground", "#d19a66");
                buffer.create_tag("hljs-number", "foreground", "#d19a66");

                buffer.create_tag("hljs-symbol", "foreground", "#4078f2");
                buffer.create_tag("hljs-bullet", "foreground", "#4078f2");
                buffer.create_tag("hljs-link", "foreground", "#4078f2", "underline", true);
                buffer.create_tag("hljs-meta", "foreground", "#4078f2");
                buffer.create_tag("hljs-selector-id", "foreground", "#4078f2");
                buffer.create_tag("hljs-title", "foreground", "#4078f2");

                buffer.create_tag("hljs-built_in", "foreground", "#c18401");

                buffer.create_tag("hljs-emphasis", "style", Pango.Style.ITALIC);
                buffer.create_tag("hljs-strong", "weight", 700);

                // Chroma colours
                buffer.create_tag("chroma-k", "foreground", "#c678dd");
                buffer.create_tag("chroma-n-blank", "foreground", "#eeeeee");
                buffer.create_tag("chroma-n", "foreground", "#e06c75");
                buffer.create_tag("chroma-l", "foreground", "#98c379");
                buffer.create_tag("chroma-s", "foreground", "#98c379");
                buffer.create_tag("chroma-d", "foreground", "#98c379");
                buffer.create_tag("chroma-m", "foreground", "#d19a66");
                buffer.create_tag("chroma-i", "foreground", "#d19a66");
                buffer.create_tag("chroma-o", "foreground", "#61aeee");
                buffer.create_tag("chroma-c", "foreground", "#eeeeee");
                buffer.create_tag("chroma-g", "foreground", "#f92672");
                buffer.create_tag("chroma-p", "foreground", "#eeeeee");

            } else {
                buffer.create_tag("hljs-comment", "foreground", "#a0a1a7", "style", Pango.Style.ITALIC);
                buffer.create_tag("hljs-quote", "foreground", "#a0a1a7", "style", Pango.Style.ITALIC);

                buffer.create_tag("hljs-doctag", "foreground", "#a626a4");
                buffer.create_tag("hljs-keyword", "foreground", "#a626a4");
                buffer.create_tag("hljs-formula", "foreground", "#a626a4");

                buffer.create_tag("hljs-selection", "foreground", "#e45649");
                buffer.create_tag("hljs-name", "foreground", "#e45649");
                buffer.create_tag("hljs-selector-tag", "foreground", "#e45649");
                buffer.create_tag("hljs-deletion", "foreground", "#e45649");
                buffer.create_tag("hljs-subst", "foreground", "#e45649");

                buffer.create_tag("hljs-literal", "foreground", "#0184bb");

                buffer.create_tag("hljs-string", "foreground", "#50a14f");
                buffer.create_tag("hljs-regexp", "foreground", "#50a14f");
                buffer.create_tag("hljs-addition", "foreground", "#50a14f");
                buffer.create_tag("hljs-attribute", "foreground", "#50a14f");
                
                buffer.create_tag("hljs-attr", "foreground", "#986801");
                buffer.create_tag("hljs-variable", "foreground", "#986801");
                buffer.create_tag("hljs-template-variable", "foreground", "#986801");
                buffer.create_tag("hljs-type", "foreground", "#986801");
                buffer.create_tag("hljs-selector-class", "foreground", "#986801");
                buffer.create_tag("hljs-selector-attr", "foreground", "#986801");
                buffer.create_tag("hljs-selector-pseudo", "foreground", "#986801");
                buffer.create_tag("hljs-number", "foreground", "#986801");

                buffer.create_tag("hljs-symbol", "foreground", "#61aeee");
                buffer.create_tag("hljs-bullet", "foreground", "#61aeee");
                buffer.create_tag("hljs-link", "foreground", "#61aeee", "underline", true);
                buffer.create_tag("hljs-meta", "foreground", "#61aeee");
                buffer.create_tag("hljs-selector-id", "foreground", "#61aeee");
                buffer.create_tag("hljs-title", "foreground", "#61aeee");

                buffer.create_tag("hljs-built_in", "foreground", "#e6c07b");

                buffer.create_tag("hljs-emphasis", "style", Pango.Style.ITALIC);
                buffer.create_tag("hljs-strong", "weight", 700);

                // Chroma colours
                buffer.create_tag("chroma-k", "foreground", "#a626a4");
                buffer.create_tag("chroma-n-blank", "foreground", "#111111");
                buffer.create_tag("chroma-n", "foreground", "#e45649");
                buffer.create_tag("chroma-l", "foreground", "#50a14f");
                buffer.create_tag("chroma-s", "foreground", "#50a14f");
                buffer.create_tag("chroma-d", "foreground", "#50a14f");
                buffer.create_tag("chroma-m", "foreground", "#986801");
                buffer.create_tag("chroma-i", "foreground", "#986801");
                buffer.create_tag("chroma-o", "foreground", "#4078f2");
                buffer.create_tag("chroma-c", "foreground", "#111111");
                buffer.create_tag("chroma-g", "foreground", "#f92672");
                buffer.create_tag("chroma-p", "foreground", "#111111");
            }
        }

        class TagOffset {
            public int start;
            public int end;
            public string tag;
        }

        private Gee.ArrayList<TagOffset> get_tags (GXml.DomNode? node, ref string current_highlight_string, ref int current_highlight_length) {
            var tags = new Gee.ArrayList<TagOffset>();

            if (node == null) {
                return tags;
            }

            if (node.node_type == GXml.DomNode.NodeType.TEXT_NODE) {
                current_highlight_string += node.node_value;
                current_highlight_length += node.node_value.char_count ();
                if (node.child_nodes.size != 0) {
                    stdout.printf("WARNING: TEXT NODE HAS CHILDREN\n");
                }
                return tags;
            } else if (node.node_type == GXml.DomNode.NodeType.ELEMENT_NODE) {
                var element = (GXml.DomElement)node;
                if (element.tag_name == "span") {
                    var tag_offset = new TagOffset();
                    tag_offset.start = current_highlight_length;
                    var child_tags = new Gee.ArrayList<TagOffset> ();
                    var only_text_children = true;
                    foreach (var child in node.child_nodes) {
                        if (child.node_type != GXml.DomNode.NodeType.TEXT_NODE) {
                            only_text_children = false;
                        }
                        child_tags.add_all (get_tags (child, ref current_highlight_string, ref current_highlight_length));
                    }

                    tag_offset.end = current_highlight_length;
                    var cls = element.get_attribute ("class");
                    if (!only_text_children) {
                        tags.add_all (child_tags);
                        return tags;
                    }
                    if (cls == "chroma-n" || cls == "chroma-nn") {
                        cls = "chroma-n-blank";
                    }
                    else if (cls.index_of ("chroma-", 0) == 0 && cls.length > 8) {
                        cls = cls.substring (0, 8);
                    }
                    tag_offset.tag = cls;
                    tags.add (tag_offset);
                    tags.add_all (child_tags);
                } else if (element.tag_name == "html" || element.tag_name == "pre") {
                    foreach (var child in node.child_nodes) {
                        tags.add_all (get_tags (child, ref current_highlight_string, ref current_highlight_length));
                    }
                } else {
                    stdout.printf("UNKNOWN TAG TYPE: %s\n", element.tag_name);
                }
            } else {
                stdout.printf("UNKNOWN NODE TYPE: %d\n", (int)node.node_type);
            }

            return tags;
        }

        public void set_highlightjs_tags (Gtk.TextBuffer buffer, string input_text, Cancellable? cancellable, bool set_string = true) {
            var current_highlight_string = "";
            var current_highlight_length = 0;
            var document = new HtmlDocument ();
            
            document.read_from_string_async.begin ("<html>" + input_text.make_valid () + "</html>", cancellable, (source, result) => {
                try {
                    document.read_from_string_async.end (result);

                    var tags = get_tags (document.first_child, ref current_highlight_string, ref current_highlight_length);
                    
                    if (set_string) {
                        buffer.text = current_highlight_string;
                    } else {
                        if (buffer.text != current_highlight_string) {
                            return;
                        }
                    }

                    var table_tags = buffer.tag_table;
                    remove_existing_tags (buffer);

                    tags.@foreach ((tag) => {
                        if (table_tags.lookup (tag.tag) == null) {
                            return true;
                        }

                        Gtk.TextIter start_iter;
                        Gtk.TextIter end_iter;
                    
                        buffer.get_iter_at_offset (out start_iter, tag.start);
                        buffer.get_iter_at_offset (out end_iter, tag.end);
                        buffer.apply_tag_by_name (tag.tag, start_iter, end_iter);
                        return true;
                    });
                } catch (GLib.Error e) {
                    stdout.printf ("Could not parse HTML: %s\n", e.message);
                    if (!set_string) {
                        return;
                    }
                    try {
                        var regex = new Regex ("<[^>]*>");
                        input_text = regex.replace (input_text, input_text.length, 0, "");
                    }
                    catch (GLib.Error e2) {
                        stdout.printf("Could not remove HTML tags: %s\n", e2.message);
                    }
                    
                    buffer.text = input_text;
                    return;
                }
            });
        }

        public static void remove_existing_tags (Gtk.TextBuffer buffer) {
            var tag_names = new Gee.ArrayList<string> ();
            buffer.tag_table.foreach ((texttag) => {
                var name = texttag.name;
                if (!tag_names.contains (name) && name.contains ("hljs")) {
                    tag_names.add (name);
                }
            });

            Gtk.TextIter start_iter;
            Gtk.TextIter end_iter;
            buffer.get_start_iter (out start_iter);
            buffer.get_end_iter (out end_iter);

            foreach (var name in tag_names) {
                buffer.remove_tag_by_name (name, start_iter, end_iter);
            }
        }
    }
}