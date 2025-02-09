#!/bin/bash

# This script is used to build the crashpad handler for the current platform.

# modified from https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
PROJECT_ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../")

echo "Cloning depot_tools"
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git $PROJECT_ROOT/subprojects/depot_tools

PATH=$PROJECT_ROOT/subprojects/depot_tools:$PATH

echo "Initial checkout of crashpad"
mkdir -p $PROJECT_ROOT/subprojects/crashpad
cd $PROJECT_ROOT/subprojects/crashpad
fetch crashpad

echo "Generating build files"
cd $PROJECT_ROOT/subprojects/crashpad/crashpad
gn gen out/Default

echo "Building"
ninja -C out/Default

echo "Copying output"
mkdir -p $PROJECT_ROOT/builddir
cp $PROJECT_ROOT/subprojects/crashpad/crashpad/out/Default/crashpad_handler $PROJECT_ROOT/builddir/pakiki_crashpad_handler
