#!/bin/bash

# This script is used to build the crashpad handler for the current platform.

git submodule update --init --recursive
cd subprojects
mkdir crashpad
cd crashpad
../depot_tools/fetch crashpad
cd crashpad
../depot_tools/gn gen out/Default

if ! grep -q "include <stdint.h>" "third_party/mini_chromium/mini_chromium/base/logging.h"; then
    sed -i '10 a #include <stdint.h>' third_party/mini_chromium/mini_chromium/base/logging.h
fi

if ! grep -q "include <stdint.h>" "third_party/mini_chromium/mini_chromium/base/strings/utf_string_conversion_utils.h"; then
    sed -i '10 a #include <stdint.h>' third_party/mini_chromium/mini_chromium/base/strings/utf_string_conversion_utils.h
fi

if ! grep -q "include <stdint.h>" "third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h"; then
    sed -i '10 a #include <stdint.h>' third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h
    sed -i '10 a typedef unsigned char uint8_t;' third_party/mini_chromium/mini_chromium/base/third_party/icu/icu_utf.h
fi

ninja -C out/Default
cd ../../..
cp subprojects/crashpad/crashpad/out/Default/crashpad_handler ./builddir/pakiki_crashpad_handler