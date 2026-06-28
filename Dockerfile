# Single-container solution: ingest RTMP, repackage to HLS, and serve the
# website — all from one nginx process.
#
# This mirrors the build approach of JasonRivers/Docker-nginx-rtmp (compile
# nginx with arut/nginx-rtmp-module on Alpine) but is self-contained: our own
# config, website, and entrypoint, not built on top of that image.

# ---- Stage 1: build nginx with the RTMP module ----
FROM alpine:latest AS builder

ARG NGINX_VERSION=1.26.2
ARG NGINX_RTMP_VERSION=1.2.2

RUN apk add --no-cache \
        build-base \
        ca-certificates \
        curl \
        git \
        linux-headers \
        openssl-dev \
        pcre-dev \
        pcre2-dev \
        zlib-dev

WORKDIR /tmp
RUN curl -fsSL -O "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    git clone --depth 1 -b "v${NGINX_RTMP_VERSION}" \
        https://github.com/arut/nginx-rtmp-module.git && \
    tar xzf "nginx-${NGINX_VERSION}.tar.gz"

RUN cd "nginx-${NGINX_VERSION}" && \
    ./configure \
        --prefix=/opt/nginx \
        --with-http_ssl_module \
        --add-module=../nginx-rtmp-module && \
    make -j"$(nproc)" && \
    make install

# ---- Stage 2: runtime image ----
FROM alpine:latest

RUN apk add --no-cache ca-certificates openssl pcre pcre2 zlib

# nginx binary + its conf/html/logs tree, and the RTMP stats stylesheet.
COPY --from=builder /opt/nginx /opt/nginx
COPY --from=builder /tmp/nginx-rtmp-module/stat.xsl /opt/nginx/conf/stat.xsl

# Our merged config: website + HLS + RTMP in one server.
COPY nginx.conf /opt/nginx/conf/nginx.conf

# Pristine website lives in html-default. At startup the entrypoint seeds the
# served root (/opt/nginx/html) from it without clobbering changed files — so
# the web root can be bind-mounted to a host ./www folder for live edits (e.g.
# swapping the stream poster) while still working when nothing is mounted.
# The served root is emptied here so the seed always provides our files (not
# nginx's default welcome page). variables.conf is generated at startup too.
COPY www/ /opt/nginx/html-default/
RUN rm -rf /opt/nginx/html/*

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# 1935 = RTMP ingest, 80/8080 = website + HLS playback
EXPOSE 1935 80 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
