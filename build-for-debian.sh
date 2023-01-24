#!/bin/bash

meson setup builddir
ninja -C builddir

# assumes proximity-core exists
mkdir -p .debpkg/usr/bin
mkdir -p .debpkg/usr/share/applications
cp builddir/com.forensant.proximity .debpkg/usr/bin/proximity
cp proximity-core/proximitypythoninterpreter .debpkg/usr/bin/
cp proximity-core/proximitycore .debpkg/usr/bin/
cp data/proximity.desktop .debpkg/usr/share/applications

chmod +x .debpkg/usr/bin/*
