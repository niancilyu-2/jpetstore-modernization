# 04 — Running the Legacy App (the "before")

How to run the **unmodified** legacy app locally, so you can see the baseline the
modernization is measured against. This is the procedure that surfaced the build
problems in [`03-problems-and-learnings.md`](03-problems-and-learnings.md).

## Why Docker (and not the host build)

The host Maven build hit JDK-selection problems (P-2, P-3). Building inside a
container with a known JDK avoids them entirely. The upstream Dockerfile cannot be
used as-is because its base image (`openjdk:25`) no longer exists (P-4), so we use
a small temurin-based Dockerfile.

## Dockerfile used for the demo

The Dockerfile lives in this repo at [`docker/legacy.Dockerfile`](../../docker/legacy.Dockerfile).
It is kept here (not in the `upstream/` submodule, which stays read-only) and uses
the `upstream/` checkout as its build context.

## Steps

```bash
# run from the repo root; build context is the pinned upstream/ submodule
docker build -f docker/legacy.Dockerfile -t jpetstore-legacy upstream/

# host :8080 may be taken on a shared machine — map to :8090 (see P-1)
docker run -d --name jpetstore-legacy-demo -p 8090:8080 jpetstore-legacy

# the app comes up at:
#   http://localhost:8090/jpetstore/
```

> On first container start, the cargo plugin downloads Tomcat 9 inside the
> container, so the app takes a short while to answer `HTTP 200`. Poll rather than
> assume it is instantly up.

## Exposing it without a localhost URL (this sandbox)

This GCP sandbox does not serve `localhost` to a browser, so a tunnel is used:

```bash
cloudflared tunnel --url http://localhost:8090
# then open  https://<generated>.trycloudflare.com/jpetstore/
```

Quick-tunnel URLs are **ephemeral** (they die with the process/session) and take a
few seconds to become resolvable after the URL prints (P-6). They are for a quick
look, not a stable share link.

## Demo credentials

Upstream demo login: `j2ee` / `j2ee`.

## What to look at

Walk **Category → Product → Item** (e.g. Fish → Angelfish → an item). That is the
catalog slice being strangled first. Note the `*.action?...` URLs — that is the
Stripes ActionBean routing the new REST + Astro stack will replace.
