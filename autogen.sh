#!/bin/sh

aclocal-1.10 -I m4 $ACLOCAL_FLAGS || exit 1
automake-1.10 --add-missing || exit 1
autoconf || exit 1
./configure "${@}"
