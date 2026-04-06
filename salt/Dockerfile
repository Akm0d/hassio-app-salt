ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

ARG SALTGUI_REF=release

# Copy root filesystem
COPY rootfs /

# Setup base
RUN apk add --no-cache \
    lighttpd \
    py3-cherrypy \
    py3-pip \
    py3-ws4py \
    shadow \
    salt-lts-api \
    salt-lts-master \
    wget \
 && wget -O /tmp/saltgui.tar.gz "https://github.com/erwindon/SaltGUI/archive/${SALTGUI_REF}.tar.gz" \
 && mkdir -p /opt /var/cache/lighttpd /run/lighttpd \
 && tar -xzf /tmp/saltgui.tar.gz -C /tmp \
 && mv "/tmp/SaltGUI-${SALTGUI_REF}/saltgui" /opt/saltgui \
 && python3 -m pip install --no-cache-dir backports.tarfile \
 && rm -rf "/tmp/SaltGUI-${SALTGUI_REF}" /tmp/saltgui.tar.gz

# Build arguments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Tyler Levy Conde <yonstib@gmail.com>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Tyler Levy Conde" \
    org.opencontainers.image.authors="Tyler Levy Conde <yonstib@gmail.com>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/Akm0d/hassio-app-salt" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
