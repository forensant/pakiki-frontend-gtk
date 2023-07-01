using GXml;

namespace Pakiki {
    class SyntaxHighlighter {
        public static void set_tags (Gtk.TextBuffer buffer) {
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

            buffer.create_tag("hljs-symbol", "foreground", "#4078f2");
            buffer.create_tag("hljs-bullet", "foreground", "#4078f2");
            buffer.create_tag("hljs-link", "foreground", "#4078f2", "underline", true);
            buffer.create_tag("hljs-meta", "foreground", "#4078f2");
            buffer.create_tag("hljs-selector-id", "foreground", "#4078f2");
            buffer.create_tag("hljs-title", "foreground", "#4078f2");

            buffer.create_tag("hljs-built_in", "foreground", "#c18401");

            buffer.create_tag("hljs-emphasis", "style", Pango.Style.ITALIC);
            buffer.create_tag("hljs-strong", "weight", 700);
        }

        class TagOffset {
            public int start;
            public int end;
            public string tag;
        }

        private string current_highlight_string = "";
        private Gee.ArrayList<TagOffset> get_tags (GXml.DomNode? node) {
            var tags = new Gee.ArrayList<TagOffset>();

            if (node == null) {
                return tags;
            }

            if (node.node_type == GXml.DomNode.NodeType.TEXT_NODE) {
                current_highlight_string += node.node_value;
                if (node.child_nodes.size != 0) {
                    stdout.printf("WARNING: TEXT NODE HAS CHILDREN\n");
                }
                return tags;
            } else if (node.node_type == GXml.DomNode.NodeType.ELEMENT_NODE) {
                var element = (GXml.DomElement)node;
                if (element.tag_name == "span") {
                    var tag_offset = new TagOffset();
                    tag_offset.start = current_highlight_string.char_count ();
                    var child_tags = new Gee.ArrayList<TagOffset> ();
                    foreach (var child in node.child_nodes) {
                        child_tags.add_all (get_tags (child));
                    }
                    
                    tag_offset.end = current_highlight_string.char_count ();
                    tag_offset.tag = element.get_attribute ("class");
                    tags.add (tag_offset);
                    tags.add_all (child_tags);
                } else if (element.tag_name == "html") {
                    foreach (var child in node.child_nodes) {
                        tags.add_all (get_tags (child));
                    }
                } else {
                    stdout.printf("UNKNOWN TAG TYPE: %s\n", element.tag_name);
                }
            } else {
                stdout.printf("UNKNOWN NODE TYPE: %d\n", (int)node.node_type);
            }

            return tags;
        }

        public void set_highlightjs_tags (Gtk.TextBuffer buffer, string input_text) {
            current_highlight_string = "";
            var document = new HtmlDocument ();
            try {
                document.read_from_string ("<html>" + input_text + "</html>");
            } catch (GLib.Error e) {
                stdout.printf("Could not parse HTML for syntax highlighting: %s\n", e.message);
                buffer.text = input_text;
                return;
            }
            
            var tags = get_tags (document.first_child);
            buffer.text = current_highlight_string;

            var table_tags = buffer.tag_table;

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
        }
    }
}