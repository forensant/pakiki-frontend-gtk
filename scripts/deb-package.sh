#!/bin/bash

./build-for-debian.sh

# if you update this, make sure you also update the manual build files
cat >.debpkg/DEBIAN/control <<EOL
Package: Pakiki
Version: `cat src/resources/version`
Architecture: `dpkg --print-architecture`
Essential: no
Maintainer: Forensant
Depends: libc6 (>= 2.2.1), libgtk-3-0, libpython3.11, libsoup-3.0-0, libjson-glib-1.0-0, libwebkit2gtk-4.1-0, libgtksourceview-3.0-1, libgee-0.8-2, libnotify4
Description: Native next generation intercepting proxy, designed for security testing of web applications.
EOL

dpkg-deb -Zxz --build .debpkg "Pakiki-Community-v`cat src/resources/version`-Linux-`uname -m`.deb"