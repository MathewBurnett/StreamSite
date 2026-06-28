#!/bin/sh
# Render the website's runtime config from environment variables, then start
# nginx in the foreground.
#
# Config now lives in the environment (an .env file on the deploy host) rather
# than a checked-in variables.conf. This script writes that file fresh on every
# boot from whatever the container's environment provides.
set -e

WEBROOT=/opt/nginx/html
CONF="${WEBROOT}/variables.conf"

# nginx-rtmp writes HLS fragments here; make sure the directory exists.
mkdir -p /tmp/hls

# Seed the served web root from the pristine baked copy. -n (no-clobber) means
# files already present win, so when ${WEBROOT} is bind-mounted to a host ./www
# folder, anything you've changed there (e.g. stream.png) is preserved while
# missing files are filled in. On a fresh/empty mount you get the full site.
mkdir -p "${WEBROOT}"
cp -rn /opt/nginx/html-default/* "${WEBROOT}/"

: "${STREAM_TITLE:=Stream Site}"
: "${STREAM_KEY:=live}"
: "${STREAM_PICTURE:=stream.png}"
# Empty host => the player uses the same origin the page was loaded from, so it
# automatically targets whatever IP / hostname the viewer used to reach this
# host. Set it only when HLS is served from a different machine.
: "${STREAM_HLS_HOST:=}"
: "${STREAM_HLS_PORT:=8080}"

cat > "$CONF" <<EOF
title     = "${STREAM_TITLE}"
hlsHost   = "${STREAM_HLS_HOST}"
hlsPort   = "${STREAM_HLS_PORT}"
streamKey = "${STREAM_KEY}"
picture   = "${STREAM_PICTURE}"
EOF

echo "Rendered ${CONF} from environment:"
cat "$CONF"

exec /opt/nginx/sbin/nginx -g "daemon off;"
