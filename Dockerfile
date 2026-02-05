# Simple wrapper over userdocs/qbittorrent-nox-static

# Base image
ARG ALPINE_BASE_VERSION=3.23.3
ARG ALPINE_BASE_HASH=25109184c71bdad752c8312a8623239686a9a2071e8825f20acb8f2198c3f659

# Image METADATA
ARG IMAGE_BUILD_DATE=1970-01-01T00:00:00+00:00
ARG IMAGE_VCS_REF=00000000

# Versions
# These versions should be kept in sync with the ones in .github/workflows/ci.yaml.
ARG QBITTORRENT_NOX_VERSION=5.1.4
ARG QBITTORRENT_NOX_SUB_VERSION=0
ARG LIB_TORRENT_VERSION=2.0.11

# Non-root user and group IDs
ARG UID=65532
ARG GID=65532

# Proxy settings
ARG http_proxy=""
ARG https_proxy=""

# === Download Stage ===

FROM alpine:${ALPINE_BASE_VERSION}@sha256:${ALPINE_BASE_HASH} AS downloader

ARG http_proxy
ARG https_proxy

RUN set -e && \
    apk -U upgrade && apk add --no-cache \
    ca-certificates=20251003-r0 \
    wget=1.25.0-r2

ARG TARGETARCH=amd64

ARG QBITTORRENT_NOX_VERSION
ARG LIB_TORRENT_VERSION

WORKDIR /opt/qBittorrent

RUN set -e \
    && \
    case ${TARGETARCH} in \
    "amd64")  QBITTORRENT_NOX_FILENAME="x86_64-qbittorrent-nox" \
    ;; \
    "arm64")  QBITTORRENT_NOX_FILENAME="aarch64-qbittorrent-nox" \
    ;; \
    *)        echo "Unsupported architecture: ${TARGETARCH}"; exit 1; \
    esac \
    && \
    TAG_NAME="release-${QBITTORRENT_NOX_VERSION}_v${LIB_TORRENT_VERSION}" \
    && \
    wget -O ./qbittorrent "https://github.com/userdocs/qbittorrent-nox-static/releases/download/${TAG_NAME}/${QBITTORRENT_NOX_FILENAME}"

# === Package Stage ===

FROM scratch

ARG IMAGE_BUILD_DATE
ARG IMAGE_VCS_REF

ARG QBITTORRENT_NOX_VERSION
ARG QBITTORRENT_NOX_SUB_VERSION

ARG UID
ARG GID

# OCI labels for image metadata
LABEL description="qBittorrent Distroless Image" \
    org.opencontainers.image.created=${IMAGE_BUILD_DATE} \
    org.opencontainers.image.authors="Hantong Chen <public-service@7rs.net>" \
    org.opencontainers.image.url="https://github.com/han-rs/container-ci-qbittorrent" \
    org.opencontainers.image.documentation="https://github.com/han-rs/container-ci-qbittorrent/blob/main/README.md" \
    org.opencontainers.image.source="https://github.com/han-rs/container-ci-qbittorrent" \
    org.opencontainers.image.version=${QBITTORRENT_NOX_VERSION}-b${QBITTORRENT_NOX_SUB_VERSION}+image.${IMAGE_VCS_REF} \
    org.opencontainers.image.vendor="Hantong Chen" \
    org.opencontainers.image.licenses="GPL-3.0-or-later" \
    org.opencontainers.image.title="qBittorrent Distroless Image" \
    org.opencontainers.image.description="qBittorrent Distroless Image"

COPY --from=downloader /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=downloader --chown="${UID}:${GID}" --chmod=775 /opt/qBittorrent /opt/qBittorrent
COPY --chown="${UID}:${GID}" --chmod=775 ./assets/qBittorrent.conf /opt/qBittorrent/config/qBittorrent.conf
COPY --chown="${UID}:${GID}" --chmod=775 ./assets/search /opt/qBittorrent/data/nova3/engines

ENV QBT_WEBUI_PORT=6880 \
    QBT_TORRENTING_PORT=6881

WORKDIR /opt/qBittorrent

# Run as non-root user.
USER "${UID}:${GID}"

# Start in foreground mode
ENTRYPOINT ["./qbittorrent"]

# Default arguments for qbittorrent-nox
CMD ["./qbittorrent", "--confirm-legal-notice", "--profile=/opt"]
