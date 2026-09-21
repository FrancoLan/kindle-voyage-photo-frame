#!/bin/sh

set -eu
cd "$(dirname "$0")"

/usr/bin/clang \
    --target=armv7-linux-gnueabi \
    -march=armv7-a \
    -marm \
    -c kindle-evgrab-cat.S \
    -o kindle-evgrab-cat.o

/usr/bin/python3 build-arm-elf.py kindle-evgrab-cat.o ../kindle-evgrab-cat
/usr/bin/clang \
    --target=armv7-linux-gnueabi \
    -march=armv7-a \
    -marm \
    -c kindle-xcontrols.S \
    -o kindle-xcontrols.o

/usr/bin/python3 build-arm-elf.py kindle-xcontrols.o ../kindle-xcontrols
/usr/bin/file ../kindle-evgrab-cat
/usr/bin/file ../kindle-xcontrols
