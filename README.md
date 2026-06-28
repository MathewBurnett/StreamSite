# StreamSite

A single Docker container that **both** ingests an RTMP stream and serves the
viewer website that plays it. nginx (with the [RTMP module]) handles the
incoming stream, repackages it as HLS, and serves the player page — all from
one image, one origin.

[RTMP module]: https://github.com/arut/nginx-rtmp-module

## What's inside

| File                          | Purpose                                                          |
| ----------------------------- | ---------------------------------------------------------------- |
| `Dockerfile`                  | Compiles nginx + the RTMP module on Alpine; adds our config + website. |
| `nginx.conf`                  | Merged config: website + HLS playback + RTMP ingest in one server.|
| `docker-entrypoint.sh`        | Renders `variables.conf` from environment variables at startup.   |
| `docker-compose.yml`          | Deploy compose — pulls the GHCR image, reads `.env`.              |
| `docker-compose.override.yml` | Local-dev overlay — builds from source instead of pulling.        |
| `.env.example`                | Template for the runtime configuration.                          |
| `.github/workflows/`          | GitHub Action that builds and pushes the image to GHCR.          |
| `www/`                        | The viewer website (`index.html`, assets, `stream.png` poster).   |

## Configuration (`.env`)

All runtime config lives in environment variables. Copy the template and edit:

```sh
cp .env.example .env
```

```ini
IMAGE=ghcr.io/mathewburnett/streamsite:latest  # image to run on the deploy host
HTTP_PORT=8080            # host port for website + HLS
RTMP_PORT=1935            # host port for RTMP ingest

STREAM_TITLE=Stream Site
STREAM_KEY=live           # the key you publish to <host>/<streamKey>
STREAM_PICTURE=stream.png

STREAM_HLS_HOST=          # empty = same origin as the page (recommended)
STREAM_HLS_PORT=8080
```

The entrypoint renders these into `<web root>/variables.conf` on every boot,
and the page reads that at load time.

### Customising the website / poster

The served web root is bind-mounted to a host folder (`./www` by default, set
via `WWW_DIR`). On first start the container **seeds** that folder with the
website from the image, so after `docker compose up` you'll have a populated
`./www`. Edit files there and they persist:

- **Change the stream poster:** replace `./www/stream.png` (or set
  `STREAM_PICTURE` to another filename you've dropped in `./www`).
- **Tweak the page:** edit `./www/index.html`, `./www/player.css`, etc.

Seeding never overwrites files you've changed (it only fills in missing ones).
To pull a newer image's website into an existing `./www`, delete the file(s) you
want refreshed (or the whole folder) and restart — the container re-seeds them.

> Files the container seeds are owned by `root`. To swap one afterwards you may
> need `sudo` (or edit as root). The friction-free way is to drop your own
> `./www/stream.png` **before the first start** — seeding then keeps your file,
> which stays owned by you.

### Hostname handling

`STREAM_HLS_HOST` is left **empty** by default. With no host, the player fetches
`/hls/<streamKey>.m3u8` relative to the page's own origin — so it automatically
uses whatever IP or hostname the viewer typed to reach the deploy host. There is
nothing to configure per host. Set `STREAM_HLS_HOST` only when HLS is served by
a *different* machine than the website.

## Deploy (GHCR + compose)

1. Push to `master` (or tag `v*`). The GitHub Action builds the image and
   pushes it to `ghcr.io/mathewburnett/streamsite`.
2. On the deployment host, copy just `docker-compose.yml` and a populated
   `.env`, then:

   ```sh
   docker compose pull
   docker compose up -d
   ```

> The package is private by default. Either make it public in the repo's
> Packages settings, or `docker login ghcr.io` on the host with a PAT that has
> `read:packages`.

## Local development

`docker-compose.override.yml` is merged in automatically and builds from source:

```sh
docker compose up --build
```

## Use it

- **Watch:** open <http://localhost/> (or any `http://localhost/<stream_key>`).
- **Publish:** there is no application segment in the path — point your encoder
  straight at the host with your chosen stream key:

  - **OBS / most encoders:** Server `rtmp://localhost:1935`, Stream Key `live`
    (or any key you like).
  - **ffmpeg:** the empty application needs a leading `//`, then the key:

    ```sh
    ffmpeg -re -i input.mp4 -c:v libx264 -c:a aac -f flv rtmp://localhost:1935//live
    ```

Whatever key `<key>` you publish is then watchable at `http://localhost/<key>`.
The page starts in a "waiting" state and goes live automatically once it sees
the HLS playlist advancing.

## Ports

| Port   | Protocol | Use                                                  |
| ------ | -------- | ---------------------------------------------------- |
| `1935` | RTMP     | Publish the stream here (no app segment).             |
| `80`   | HTTP     | Website + HLS playback (`/`, `/<key>`, `/hls/…`).      |
| `8080` | HTTP     | Same website + HLS, alternate port.                   |
