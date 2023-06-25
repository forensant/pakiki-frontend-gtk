sources += files(
    'application.vala',
    'application-window.vala',
    'main.vala',

    'forms/application-preferences.vala',
    'forms/authentication-dialog.vala',
    'forms/inject-new.vala',
    'forms/inject-list-row.vala',
    'forms/inject-pane.vala',
    'forms/inject-underway.vala',
    'forms/intercept.vala',
    'forms/main-application-pane.vala',
    'forms/payload-selection-widget.vala',
    'forms/placeholder-inject.vala',
    'forms/placeholder-requests.vala',
    'forms/request-compare.vala',
    'forms/request-details.vala',
    'forms/request-list.vala',
    'forms/request-new.vala',
    'forms/request-preview.vala',
    'forms/request-window.vala',
    'forms/requests-pane.vala',
    'forms/saving-dialog.vala',
    'forms/searchable-web-view.vala',
    'forms/sitemap-widget.vala',
    'forms/widgets/inject-point-selection-widget.vala',
    'forms/widgets/hex-editor.vala',
    'forms/widgets/hex-editor/hex-buffer.vala',
    'forms/widgets/hex-editor/hex-remote-buffer.vala',
    'forms/widgets/hex-editor/hex-static-buffer.vala',
    'forms/widgets/out-of-band-display.vala',
    'forms/widgets/request-diff.vala',
    'forms/widgets/request-text-editor.vala',
    'forms/widgets/request-text-view.vala',
    'forms/widgets/round-progress-bar.vala',
    'forms/widgets/searchable-hex-editor.vala',
    'forms/widgets/searchable-source-view.vala',
    'forms/widgets/text-search-bar.vala',

    'models/core-process.vala',
    'models/inject-operation.vala',
    'models/proxy-settings.vala'
)

schemas_dir = get_option('prefix') / get_option('datadir') / 'glib-2.0' / 'schemas'
settings_schemas = [ 'com.forensant.pakiki.gschema.xml' ]

import( 'gnome' ).compile_schemas(
    build_by_default: true,
    depend_files: settings_schemas
)

install_data(settings_schemas, install_dir: schemas_dir)

meson.add_install_script('glib-compile-schemas', schemas_dir)