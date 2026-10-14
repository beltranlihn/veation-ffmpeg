# [veation] Imagen base de BtbN con tres cambios (win/VEATION-CAMBIOS.md):
#   - FROM fijado por digest (versions.lock: ubuntu-base);
#   - herramientas descargadas fijadas por sha256: el autoconf 2.73 (.deb), CMake 3.31.9 de Kitware
#     (x265 4.1 no configura con CMake 4: usa cmake_policy(SET CMP0025 OLD)) y meson desde su tarball;
#   - sin rustup ni cargo-c (sin rav1e ni librsvg no hay Rust) y sin el «curl | bash» de nodesource.
# Las versiones de apt siguen sin fijar (FFMPEG-PROPIO.md, 2.5.6: SIN VERIFICAR el aislamiento de la
# parte Windows); BUILDINFO-win.txt deja constancia de lo que se instalo.
ARG UBUNTU_REF
FROM ${UBUNTU_REF}

ARG TARGETPLATFORM
ARG AUTOCONF_DEB_URL
ARG AUTOCONF_DEB_SHA256
ARG CMAKE_URL
ARG CMAKE_SHA256
ARG MESON_URL
ARG MESON_SHA256

ENV DEBIAN_FRONTEND=noninteractive
RUN \
    apt-get -y update && \
    apt-get -y dist-upgrade && \
    apt-get -y install --no-install-recommends \
        $([ "$TARGETPLATFORM" != "linux/amd64" ] || echo gcc-multilib g++-multilib) \
        build-essential yasm nasm \
        xxd pkgconf curl wget unzip zip git subversion mercurial rsync jq \
        autoconf automake libtool libtool-bin libltdl-dev autopoint gettext ninja-build \
        clang llvm lcov lld qemu-user \
        texinfo texi2html help2man flex bison groff libxml2-utils \
        gperf itstool ragel libc6-dev zlib1g-dev libssl-dev \
        gtk-doc-tools gobject-introspection gawk \
        ocaml ocaml-findlib ocamlbuild libnum-ocaml-dev indent p7zip-full zstd libarchive-tools \
        default-jdk-headless ant \
        python3-setuptools python3-pip python3-venv python3-jinja2 python3-jsonschema python3-apt python3-dev python-is-python3 && \
    apt-get -y autoremove && \
    apt-get -y clean autoclean && \
    rm -rf /var/lib/apt/lists/* && \
    git config --global user.email "builder@localhost" && \
    git config --global user.name "Builder" && \
    git config --global advice.detachedHead false

RUN wget -O autoconf.deb "$AUTOCONF_DEB_URL" && \
    echo "$AUTOCONF_DEB_SHA256  autoconf.deb" | sha256sum -c - && \
    dpkg -i autoconf.deb && \
    rm autoconf.deb

RUN wget -O /tmp/cmake.tar.gz "$CMAKE_URL" && \
    echo "$CMAKE_SHA256  /tmp/cmake.tar.gz" | sha256sum -c - && \
    mkdir -p /opt/cmake && tar -xf /tmp/cmake.tar.gz -C /opt/cmake --strip-components=1 && \
    rm /tmp/cmake.tar.gz && \
    /opt/cmake/bin/cmake --version

RUN wget -O /tmp/meson.tar.gz "$MESON_URL" && \
    echo "$MESON_SHA256  /tmp/meson.tar.gz" | sha256sum -c - && \
    mkdir -p /opt/meson && tar -xf /tmp/meson.tar.gz -C /opt/meson --strip-components=1 && \
    rm /tmp/meson.tar.gz && \
    printf '#!/bin/sh\nexec python3 /opt/meson/meson.py "$@"\n' > /usr/local/bin/meson && \
    chmod 755 /usr/local/bin/meson && \
    meson --version

ENV PATH="/opt/cmake/bin:${PATH}"

RUN --mount=src=.,dst=/input \
    for s in /input/*.sh; do cp $s /usr/bin/$(echo $s | sed -e 's|.*/||' -e 's/\.sh$//'); done

ENV HOST_CC="gcc" \
    HOST_CXX="g++" \
    HOST_CFLAGS="-O2 -pipe" \
    HOST_CXXFLAGS="-O2 -pipe"
