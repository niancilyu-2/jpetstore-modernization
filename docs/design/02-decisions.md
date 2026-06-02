# 02 — Decision Log

Decisions made during the design phase, ADR-style: the decision, why, and the
alternatives rejected. Recording *alternatives rejected* is deliberate — it
teaches judgment, not just answers.

---

## ADR-001 — Separate sandbox repo (not a fork of upstream)

**Decision:** Build a new repo (`jpetstore-modernization`). Consume the legacy app
as a **read-only git submodule pinned to commit `1478177`**.

**Why:** Mirrors the real-world constraint of strangling a system you do not own.
Keeps the legacy provably untouched. Simplest CI. No long-lived fork branch to
keep rebasing.

**Alternatives rejected:**
- *Fork + sibling Maven module.* Classic in-repo strangler-fig, but upstream's
  Renovate bot bumps dependencies almost daily — a fork branch would be in
  perpetual conflict. Real maintenance tax over a multi-week project.
- *Hybrid (fork + separate repo).* Most moving pieces: duplicated CI, two release
  cycles, more overhead than a sandbox warrants.

---

## ADR-002 — Phase 1 = full slice cutover (backend **and** frontend)

**Decision:** Phase 1 delivers the Boot REST service **and** the Astro frontend
**and** the reverse-proxy cutover — a user browsing the catalog is served by the
new stack.

**Why:** The user-visible cutover is the point. It forces the "cutover IS
verification" discipline and produces a real, demonstrable strangle.

**Alternatives rejected:**
- *Backend-only.* Faster to "done," but no cutover moment; verification would be
  curl/Postman only. Defers the riskiest integration work instead of facing it.
- *Full slice + persistence rewrite (MyBatis→JPA).* Dilutes the strangler-fig
  focus into a parallel persistence-migration project. Possible later; not Phase 1.

---

## ADR-003 — Frontend: Astro

**Decision:** Build the catalog frontend with Astro (SSR).

**Why:** The catalog pages are mostly content (categories/products/items). Astro's
SSR-by-default produces small payloads and maps cleanly onto what JSPs were already
doing — a "replace like with like, but modernized" story. Adds a new tool to the
toolkit without much risk on read-only pages.

**Alternatives rejected:**
- *React + Vite.* Safe and familiar, scales to the stateful slices later, but
  overkill for 5 read-only pages and the largest bundle of the options.
- *HTMX + plain HTML.* Most YAGNI and a nice "you don't always need a SPA" lesson,
  but scales least well to the stateful Cart/Order slices where SPA state pays off.

---

## ADR-004 — First slice: Catalog

**Decision:** Strangle the catalog slice first.

**Why:** Smallest, read-only, no session writes, already covered by upstream tests,
and the cleanest 1:1 mapping to REST. Lowest-risk way to stand up the whole
strangler scaffold (proxy, new service, new frontend, DB) before tackling stateful
slices.

---

## ADR-005 — Data: separate embedded HSQLDB per app for Phase 1

**Decision:** Each app keeps its own embedded HSQLDB (identical seed SQL) for
Phase 1; graduate to a shared Postgres when a stateful slice arrives.

**Why:** The catalog slice is read-only, so two in-memory DBs cannot diverge.
Defers the shared-DB integration work until a slice actually needs it — and makes
that graduation an explicit teaching moment rather than hidden plumbing.

---

## ADR-006 — Demo the legacy app via a current-JDK Docker image

**Decision:** Run the "before" app from a throwaway Docker image based on
`eclipse-temurin:21-jdk`, not from the host Maven build and not from the upstream
Dockerfile.

**Why:** The host build picked up the wrong JDK, and the upstream Dockerfile's base
image (`openjdk:25`) no longer exists. A temurin-based container isolates the build
from host toolchain quirks. Full root causes in
[`03-problems-and-learnings.md`](03-problems-and-learnings.md).

---

## Open decisions (still to be made)

- DTO field naming / whether any legacy JSON shape must be matched
- REST error-handling conventions
- Reverse-proxy host port (sandbox `:80`/`:8080` are occupied)
- How the Boot service consumes the legacy mappers from the submodule
