sources += files(
    'application.vala',
    'application-window.vala',
    'main.vala',

    'forms/application-preferences.vala',
    'forms/inject-new.vala',
    'forms/inject-list-row.vala',
    'forms/inject-pane.vala',
    'forms/inject-underway.vala',
    'forms/intercept.vala',
    'forms/main-application-pane.vala',
    'forms/placeholder-inject.vala',
    'forms/placeholder-requests.vala',
    'forms/request-details.vala',
    'forms/request-list.vala',
    'forms/request-new.vala',
    'forms/requests-pane.vala',

    'models/core-process.vala',
    'models/inject-operation.vala',
    'models/proxy-settings.vala'
)

schemas_dir = get_option('prefix') / get_option('datadir') / 'glib-2.0' / 'schemas'
settings_schemas = [ 'com.forensant.proximity.gschema.xml' ]

import( 'gnome' ).compile_schemas(
    build_by_default: true,
    depend_files: settings_schemas
)

install_data(settings_schemas, install_dir: schemas_dir)

meson.add_install_script('glib-compile-schemas', schemas_dir)