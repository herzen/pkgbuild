#!/bin/sh

aclocal -I m4 $ACLOCAL_FLAGS || exit 1
autoconf || exit 1
automake --add-missing || exit 1
./configure "${@}"
