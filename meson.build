project('com.forensant.pakiki', 'vala', 'c',
  version: run_command('cat', 'src/resources/version', check : true).stdout().strip(),
  license: 'MIT')

dependencies = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gtk+-3.0'),
    dependency('gee-0.8'),
    dependency('json-glib-1.0'),
    dependency('libsoup-3.0'),
    meson.get_compiler('vala').find_library('posix'),
    dependency('gtksourceview-3.0'),
    dependency('webkit2gtk-4.1'),
    dependency('libnotify')
]

sources = []

sources += import( 'gnome' ).compile_resources(
    'project-resources',
    'src/resources/pakikiapp.gresource.xml',
    source_dir: 'src/resources',
)

subdir('data')
subdir('src')

executable('com.forensant.pakiki', sources, dependencies: dependencies, install: true)