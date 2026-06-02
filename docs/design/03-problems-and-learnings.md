# 03 — Problems & Learnings

A running, honest record of problems hit during the project — starting in the
design/demo phase, before a single line of new application code was written.

The recurring lesson of this phase: **modernization friction often lives in the
build and the toolchain, not the source.** Simply getting the *unmodified* legacy
app to run surfaced four distinct issues. Each is logged as
symptom → investigation → root cause → fix → lesson.

---

## P-1 — Host ports 80 and 8080 already occupied

**Symptom:** `curl http://localhost:8080/jpetstore/` returned a Tomcat 404 before
we had started anything.

**Investigation:** `ss -ltnp` showed `docker-proxy` on `:8080`; `docker ps` showed
pre-existing containers from another project publishing `:80` and `:8080`.

**Root cause:** The dev sandbox is shared; other projects' containers hold the
conventional ports.

**Fix:** Ran the legacy demo on host port **8090**. Noted that the Phase 1 reverse
proxy will likewise need a non-default host port.

**Lesson:** Never assume default ports are free on a shared host. Check
`ss -ltnp` / `docker ps` first, and make ports configurable from day one. Do **not**
reclaim a port by killing another project's container.

---

## P-2 — Maven wrapper used JDK 8 despite a JDK 21 environment

**Symptom:**
```
RequireJavaVersion failed: Detected JDK .../temurin-8-jdk-amd64/jre is version
1.8.0 which is not in the allowed range [21,22),[25,26),[26,27),[27,28).
```

**Investigation:** `java -version` on `PATH` was 21; `JAVA_HOME` was empty;
`default-java` pointed at 21; there was no `~/.m2/toolchains.xml`. Yet the enforcer
plugin saw Temurin 8.

**Root cause:** The `mvnw` wrapper resolved a JDK 8 from the environment through a
path we did not fully pin down (Temurin 8 is installed because another project
needs it). The clean-looking environment hid the bleed-through.

**Fix:** Exported `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64` explicitly. The
enforcer then passed.

**Lesson:** A passing `java -version` does **not** mean your build uses that JDK.
Pin `JAVA_HOME` explicitly for every build invocation. On multi-JDK machines,
ambient JDK selection is a top source of "works on my machine" failures.

---

## P-3 — Compiler failed `release version 17 not supported` (host build)

**Symptom:** With `JAVA_HOME` set to 21 and the enforcer passing, the compile step
still failed:
```
Fatal error compiling: error: release version 17 not supported
```

**Investigation:** `release 17` is supported by any JDK ≥ 17, so a true JDK-21
compile should not produce this. The message is characteristic of a JDK-8 `javac`.
With no `toolchains.xml` and `default-java` → 21, the mechanism by which a JDK-8
compiler was still being invoked was not fully explained on the host.

**Root cause:** Unresolved on the host — a JDK-8 bleed-through in the build
environment, of the same family as P-2. Rather than rabbit-hole on a disposable
demo, we isolated the build.

**Fix:** Built inside Docker (`eclipse-temurin:21-jdk`), where only JDK 21 exists.
The compile succeeded immediately — confirming the failure was **environmental,
not a code problem**.

**Lesson:** When a host toolchain misbehaves in ways you cannot quickly explain,
**isolate the build in a container** rather than stacking host-level workarounds.
Isolation both fixes the immediate problem and proves where the fault was.

---

## P-4 — Upstream Dockerfile base image no longer exists

**Symptom:**
```
failed to resolve reference "docker.io/library/openjdk:25": ... not found
```

**Investigation:** The upstream `Dockerfile` starts `FROM openjdk:25`. The official
`openjdk` Docker Hub images are deprecated and that tag is not available.

**Root cause:** Base-image rot — a dependency that silently disappeared from the
registry after the Dockerfile was written.

**Fix:** Wrote a throwaway `Dockerfile.temurin` based on `eclipse-temurin:21-jdk`
to build and run the demo. (Kept out of the upstream submodule, which stays
read-only.)

**Lesson:** Pinned-but-unavailable base images are a real rot vector. Prefer
actively published bases (e.g. `eclipse-temurin`) and treat "the Dockerfile builds"
as something CI must keep verifying, not a one-time fact.

---

## P-5 — Process-hygiene mistake: an over-broad `pkill`

**Symptom:** While starting a Cloudflare tunnel, the launch command included
`pkill -f "cloudflared tunnel"`.

**Investigation:** `pgrep` showed **other** unrelated tunnels running on the host
(another service on `:8501`, and a named tunnel). The broad pattern would have
matched and killed those too.

**Root cause:** A too-broad process match used for convenience.

**Fix:** Stopped using broad `pkill`. Launched a fresh, separately-logged tunnel
without touching others. (The other tunnels survived, but the risk was real.)

**Lesson:** Never `pkill` by a broad pattern on a shared host. Track the specific
PID you started, or scope the match tightly. Convenience commands that match "all
X" are dangerous when X belongs to someone else.

---

## P-6 — Cloudflare quick-tunnel edge-registration lag

**Symptom:** Immediately after the tunnel printed its `*.trycloudflare.com` URL,
`curl` to it returned `000` (could not resolve host).

**Root cause:** Quick-tunnel hostnames take a few seconds to register at the edge /
in DNS after the URL is printed.

**Fix:** Retried for a few seconds; the tunnel then served `HTTP 200`.

**Lesson:** A printed tunnel URL is not instantly resolvable. Build a short
retry/poll into any "is it up yet?" verification instead of failing on the first
attempt.

---

## Meta-lesson for the lessons

Before any new code, the *build and ops* layer alone produced six logged problems —
JDK selection, an unexplained compiler failure, a dead base image, port contention,
a process-hygiene slip, and edge lag. For students modernizing their own legacy
app, the first portable habit is: **get the unmodified app building and running in
an isolated, reproducible environment before changing anything** — because that
step is where a surprising amount of the real difficulty hides.
