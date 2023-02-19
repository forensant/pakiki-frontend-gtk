#!/bin/bash

./build-for-debian.sh

# if you update this, make sure you also update the manual build files
cat >.debpkg/DEBIAN/control <<EOL
Package: Proximity
Version: `cat src/resources/version`
Architecture: `dpkg --print-architecture`
Essential: no
Maintainer: Forensant
Depends: libc6 (>= 2.2.1), libgtk-3-0, libpython3.10, libsoup2.4-1, libjson-glib-1.0-0, libwebkit2gtk-4.0-37, libgtksourceview-3.0-1, libgee-0.8-2, libnotify4
Description: Native next generation intercepting proxy, designed for security testing of web applications.
EOL

dpkg-deb -Zxz --build .debpkg "Proximity-Community-v`cat src/resources/version`-Linux-`uname -m`.deb"