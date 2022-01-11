icon_sizes = ['16','32', '48', '64', '128', '256']

foreach i : icon_sizes
    install_data(
        join_paths('images', 'icons', i, meson.project_name() + '.png'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i, 'apps')
    )
endforeach

install_data(
    meson.project_name() + '.desktop',
    install_dir: join_paths(get_option('datadir'), 'applications')
)
