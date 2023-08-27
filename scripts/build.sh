#!/bin/bash

# To be run from the project's root directory

./build-for-debian.sh
flatpak-builder --repo=repo --force-clean build-dir com.forensant.pakiki.yml
flatpak build-bundle repo Pakiki-Proxy-Community-v$(date +"%Y.%m.01")-Linux-$(uname --m).flatpak com.forensant.pakiki

# upload debug files
if command -v sentry-cli
then
    sentry-cli --url https://sentryio.pakikiproxy.com debug-files upload -o forensant -p gtk-frontend builddir/com.forensant.pakiki
fi
