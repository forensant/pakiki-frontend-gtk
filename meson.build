project('com.forensant.pakiki', 'vala', 'c',
  version: run_command('cat', 'src/resources/version', check : true).stdout().strip(),
  license: 'MIT')

vapi_dir = meson.current_source_dir() / 'vapi'
add_project_arguments(['--vapidir', vapi_dir], language: 'vala')
add_global_arguments('-DGDK_DISABLE_DEPRECATED -DGTK_DISABLE_DEPRECATED', language: 'c')

dependencies = [
    dependency('glib-2.0'),
    dependency('gobject-2.0'),
    dependency('gtk+-3.0'),
    dependency('gee-0.8'),
    dependency('crashpad_wrapper', default_options: ['default_library=static']),
    meson.get_compiler('vala').find_library('crashpad', dirs: vapi_dir),
    dependency('gxml-0.18', fallback : [ 'gxml', 'libgxml_dep' ], default_options: ['default_library=static']),
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