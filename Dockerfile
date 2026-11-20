# =============================================================================
# Build environment for MAME 0.223 (Game & Watch subset) for TrimUI Brick
#
#   - Native linux/arm64 build host (Apple-Silicon Macs run arm64 containers
#     at full speed; no cross toolchain needed)
#   - Base: ubuntu:20.04 pinned by its arm64 manifest digest (pins.env) —
#     glibc 2.31, binary-compatible with the device runtime
#   - apt pinned to a snapshot.ubuntu.com timestamp from pins.env — the
#     toolchain (gcc/lld libs) is frozen forever
#   - SDL2 2.0.20 from the pinned release tarball (sha256-verified here):
#     a build-time dependency only — the pak runs the device's own SDL2
#     from /usr/trimui/lib (mali fbdev video driver)
# =============================================================================
ARG DOCKER_BASE_IMAGE
FROM ${DOCKER_BASE_IMAGE}

ARG APT_USE_SNAPSHOT=1
ARG APT_SNAPSHOT_DATE=""
ARG SDL2_VERSION
ARG SDL2_URL
ARG SDL2_SHA256

ENV DEBIAN_FRONTEND=noninteractive

# Freeze apt to the snapshot server (replaces the live sources entirely).
RUN if [ "${APT_USE_SNAPSHOT}" = "1" ] && [ -n "${APT_SNAPSHOT_DATE}" ]; then \
        echo "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT_DATE} focal main universe" > /etc/apt/sources.list && \
        echo "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT_DATE} focal-updates main universe" >> /etc/apt/sources.list && \
        echo "deb https://snapshot.ubuntu.com/ubuntu/${APT_SNAPSHOT_DATE} focal-security main universe" >> /etc/apt/sources.list; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ make python3 git lld \
    ca-certificates wget tar xz-utils \
    pkg-config linux-libc-dev libasound2-dev libx11-dev \
    libsdl2-ttf-dev libfontconfig1-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- SDL2 2.0.20 (fbcon + dummy video, ALSA via dlopen) ----
# fbcon needs linux/fb.h (linux-libc-dev). ALSA is dlopen'd at runtime, so the
# built libSDL2 only depends on glibc at runtime.
RUN mkdir -p /opt/sdl2-src && cd /opt/sdl2-src \
    && wget -qO SDL2.tar.gz "${SDL2_URL}" \
    && echo "${SDL2_SHA256}  SDL2.tar.gz" | sha256sum -c - \
    && tar xzf SDL2.tar.gz \
    && cd "SDL2-${SDL2_VERSION}" \
    && ./configure --prefix=/opt/sdl2 \
        --enable-video-fbcon \
        --enable-video-dummy \
        --disable-video-x11 \
        --disable-video-wayland \
        --disable-video-kmsdrm \
        --disable-video-opengl \
        --disable-video-opengles \
        --disable-video-vulkan \
        --enable-alsa \
        --disable-pulseaudio \
        --disable-esd \
        --disable-arts \
        --disable-jack \
        --disable-sndio \
    && make -j8 && make install \
    && rm -rf /opt/sdl2-src

ENV SDL_INSTALL_ROOT=/opt/sdl2
ENV PATH=/opt/sdl2/bin:${PATH}
