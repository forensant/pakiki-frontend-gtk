#!/bin/bash

# This script is used to build the crashpad handler for the current platform.

export PATH=$PATH:/usr/lib/sdk/llvm16/bin
echo $PATH

mkdir -p builddir

echo "Checking out submodules"
git submodule update --init --recursive
cd subprojects
mkdir crashpad
cd crashpad

echo "Fetching crashpad"
../depot_tools/fetch crashpad
cd crashpad

echo "Generating build files"
../../depot_tools/gn gen out/Default

echo "File listing:"
find .

echo "Modifying the build files"
if ! grep -q "include <stdint.h>" "third_party/mini_chromium/mini_chromium/base/logging.h"; then
    echo "Updating logging.h"
    sed -i '10 a #include <stdint.h>' third_party/mini_chromium/mini_chromium/base/logging.h
fi

if ! grep -q "include <stdint.h>" "third_party/mini_chromium/mini_chromium/base/strings/utf_string_conversion_utils.h"; then
    echo "Updating utf_string_conversion_utils.h"
    sed -i '10 a #include <stdint.h>' third_party/mini_chromium/mini_chromium/base/strings/utf_string_conversion_utils.h
fi

if ! grep -q "include <stdint.h>" "third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h"; then
    echo "Updating icu_utf.h"
    sed -i '10 a #include <stdint.h>' third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h
fi

if ! grep -q "typedef unsigned char uint8_t" "third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h"; then
    echo "Updating icu_utf.h 2"
    sed -i '10 a typedef unsigned char uint8_t;' third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h
fi

echo "Starting build"
../../depot_tools/ninja -C out/Default
cd ../../..

echo "Copying output"
cp subprojects/crashpad/crashpad/out/Default/crashpad_handler ./builddir/pakiki_crashpad_handler