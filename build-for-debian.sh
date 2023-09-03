#!/bin/bash

meson setup builddir
ninja -C builddir

# assumes the pakiki-core directory exists
mkdir -p .debpkg/usr/bin
mkdir -p .debpkg/usr/share/applications
mkdir -p .debpkg/usr/share/glib-2.0/schemas/
mkdir -p .debpkg/usr/share/pixmaps
cp builddir/com.forensant.pakiki .debpkg/usr/bin/pakiki
cp pakiki-core/pakikipythoninterpreter .debpkg/usr/bin/
cp pakiki-core/pakikicore .debpkg/usr/bin/
cp builddir/pakiki_crashpad_handler .debpkg/usr/bin/
cp data/pakiki.desktop .debpkg/usr/share/applications
cp src/com.forensant.pakiki.gschema.xml .debpkg/usr/share/glib-2.0/schemas/
cp src/resources/Logo.svg .debpkg/usr/share/pixmaps/pakiki.svg

chmod +x .debpkg/usr/bin/*

# post install
mkdir -p .debpkg/DEBIAN
echo -e "glib-compile-schemas /usr/share/glib-2.0/schemas/" > .debpkg/DEBIAN/postinst
chmod +x .debpkg/DEBIAN/postinst
