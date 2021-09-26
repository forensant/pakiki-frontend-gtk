project('proximity', 'vala', 'c',
  version: '0.1',
  license: 'MIT')

dependencies = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gtk+-3.0'),
    dependency('gee-0.8'),
    dependency('json-glib-1.0'),
    dependency('libsoup-2.4'),
    meson.get_compiler('vala').find_library('posix'),
    dependency('gtksourceview-3.0'),
#   dependency('webkit2gtk-4.0')
]

sources = []

sources += import( 'gnome' ).compile_resources(
    'project-resources',
    'src/resources/proximityapp.gresource.xml',
    source_dir: 'src/resources',
)

subdir('src')

executable('proximity', sources, dependencies: dependencies, install: true)