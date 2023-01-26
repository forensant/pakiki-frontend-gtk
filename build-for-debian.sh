#!/bin/bash

meson setup builddir
ninja -C builddir

# assumes the proximity-core directory exists
mkdir -p .debpkg/usr/bin
mkdir -p .debpkg/usr/share/applications
mkdir -p .debpkg/usr/share/glib-2.0/schemas/
mkdir -p .debpkg/usr/share/pixmaps
cp builddir/com.forensant.proximity .debpkg/usr/bin/proximity
cp proximity-core/proximitypythoninterpreter .debpkg/usr/bin/
cp proximity-core/proximitycore .debpkg/usr/bin/
cp data/proximity.desktop .debpkg/usr/share/applications
cp src/com.forensant.proximity.gschema.xml .debpkg/usr/share/glib-2.0/schemas/
cp src/resources/Logo.svg .debpkg/usr/share/pixmaps/proximity.svg

chmod +x .debpkg/usr/bin/*

# post install
mkdir -p .debpkg/DEBIAN
echo -e "glib-compile-schemas /usr/share/glib-2.0/schemas/" > .debpkg/DEBIAN/postinst
chmod +x .debpkg/DEBIAN/postinst
