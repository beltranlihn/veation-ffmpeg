#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_depends() {
    echo libiconv
    echo zlib
    echo libxml2
    echo xz
    echo amf
    echo dav1d
    echo ffnvcodec
    echo libmp3lame
    echo libopus
    echo libvpx
    echo onevpl
    echo snappy
    echo svtav1
    echo x264
    echo x265
    echo zimg
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerfinal() {
    return 0
}

ffbuild_dockerdl() {
    return 0
}

ffbuild_dockerlayer() {
    return 0
}

ffbuild_dockerstage() {
    return 0
}

ffbuild_dockerbuild() {
    return 0
}

ffbuild_ldexeflags() {
    return 0
}
