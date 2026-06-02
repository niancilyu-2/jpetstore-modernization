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

## ADR-007 — Reuse the legacy persistence layer by vendoring with a provenance check

**Decision:** Copy the catalog-relevant files (the `Category`/`Product`/`Item`
domain classes, the three mapper interfaces and their XML, and `CatalogService`)
verbatim into the Boot service, keeping their original packages. Add a
**provenance test** asserting each copy is byte-identical to its `upstream/`
counterpart at the pinned commit.

**Why:** The mappers and service are framework-agnostic (no Stripes imports), so
they are genuinely reusable. Vendoring is robust and realistic, and the provenance
test keeps "untouched reuse" honest — drift fails the build. It does not couple our
build to the submodule's directory layout.

**Alternatives rejected:**
- *Reference upstream sources in the build* (point Maven at `upstream/` source
  files). Purest "no copy" story, but brittle — couples our build to upstream's
  internal layout.
- *Rewrite the persistence layer fresh.* Cleanest long-term separation and a
  common real-world endpoint, but loses the "core survives untouched" lesson and is
  the most work for Phase 1.

---

## ADR-008 — Keep legacy at `/jpetstore/`; new catalog canonical at `/catalog/`

**Decision:** The reverse proxy sends `/api/catalog/*` and `/catalog/*` to the new
stack and everything else to the legacy WAR at its existing `/jpetstore/` context.
nginx is exposed on host port **8888** (sandbox `:80`/`:8080` are occupied).

**Why:** Rewriting legacy URLs in nginx adds complexity with no Phase-1 benefit.
Making the new catalog canonical at a distinct path keeps the cutover boundary
obvious and testable.

---

## Resolved — the remaining open decisions

| Was open | Resolved as |
| --- | --- |
| DTO field naming / match a legacy JSON shape? | No legacy JSON exists (JSP/HTML). Clean DTOs; drop `unitCost`/`supplierId` (ADR in `01-architecture.md`, DTO contract). |
| REST error-handling conventions | `@RestControllerAdvice`, JSON error body; 404 not-found, 400 blank-search. |
| Reverse-proxy host port | nginx on host **8888** (ADR-008). |
| How the Boot service consumes the mappers | Vendor with provenance check (ADR-007). |
