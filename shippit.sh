#!/bin/bash
# Runs the tests, builds, and zips odin/out for itch.io. Uploads only with --push.
set -e
cd "$(dirname "$0")"

(cd odin && odin test . -define:ODIN_TEST_THREADS=1)
odin/build.sh
mkdir -p build
rm -f build/check-yer-butthole-html5.zip
(cd odin/out && zip -qr ../../build/check-yer-butthole-html5.zip .)
echo "built build/check-yer-butthole-html5.zip"

if [ "$1" = "--push" ]; then
    butler push odin/out thegrumpygamedev/check-yer-btthole:html
else
    echo "not pushed (use --push)"
fi
