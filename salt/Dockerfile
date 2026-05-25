ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1
# hadolint ignore=DL3006
FROM ghcr.io/astral-sh/uv:latest AS uv-bin

# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Copy root filesystem
COPY rootfs /
COPY --from=uv-bin /uv /uvx /usr/local/bin/

RUN rm -rf \
    /etc/s6-overlay/s6-rc.d/api \
    /etc/s6-overlay/s6-rc.d/example1 \
    /etc/s6-overlay/s6-rc.d/example2 \
    /etc/s6-overlay/s6-rc.d/init-example \
    /etc/s6-overlay/s6-rc.d/master \
    /etc/s6-overlay/s6-rc.d/proxy \
    /etc/s6-overlay/s6-rc.d/user2 \
    /etc/s6-overlay/s6-rc.d/user/contents.d/api \
    /etc/s6-overlay/s6-rc.d/user/contents.d/master \
    /etc/s6-overlay/s6-rc.d/user/contents.d/proxy \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/base-addon-banner \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/base-addon-log-level \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/base/contents.d/base-addon-banner \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/base/contents.d/base-addon-log-level \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/fix-attrs/dependencies.d/base-addon-banner \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/legacy-cont-init/dependencies.d/base-addon-log-level \
    /package/admin/s6-overlay-*/etc/s6-rc/sources/top/contents.d/user2 \
    /usr/bin/salt-api.sh \
    /usr/bin/salt-ingress-auth.py \
    /usr/bin/salt-init.sh \
    /usr/bin/salt-proxy.py \
    /usr/bin/salt-proxy.sh \
    /usr/bin/salt-rest-api.py \
    /usr/bin/salt_ingress_auth_lib.py

# Setup base
RUN apk add --no-cache --upgrade \
    musl \
    musl-utils \
    libcrypto3 \
    libssl3 \
    openssl-dev \
 && apk add --no-cache \
    bash \
    build-base \
    ca-certificates \
    cargo \
    clang \
    compiler-rt \
    curl \
    git \
    libffi-dev \
    python3 \
    rust \
    salt-master \
    salt-minion \
    zeromq-dev \
 && mkdir -p /opt/materium

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
