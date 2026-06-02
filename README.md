# JPetStore Modernization

A teaching sandbox that incrementally modernizes the legacy
[MyBatis JPetStore-6](https://github.com/mybatis/jpetstore-6) web application
using the **strangler-fig** pattern — replacing it one vertical slice at a time
while the original keeps serving traffic.

The goal is not just a finished migration; it is a **documented, didactic record**
of the decisions, the architecture, and the problems hit along the way — so it can
be used as lesson material for students modernizing their own legacy applications.

## What we are modernizing

The legacy app is a classic 3-tier Java web app:

- **Stripes 1.6.0** (a web framework whose last release was ~2015) — the chokepoint
- **JSP** views
- **MyBatis** + **Spring** + embedded **HSQLDB**, packaged as a WAR on Tomcat 9

Stripes blocks the upstream project's own Jakarta EE migration (see the
`<!-- Keep spring-web at 5.3.39 until jakarta upgrade occurs -->` note in its
`pom.xml`). Removing it is the real, motivated work.

## Target architecture (Phase 1)

A reverse proxy routes the **catalog** slice to a new Spring Boot 3 service + an
Astro frontend, while everything else still goes to the untouched legacy WAR.

See [`docs/design/01-architecture.md`](docs/design/01-architecture.md) for the
full topology.

## Repository layout

```
docs/design/        # design docs, decision log, and problem/learning records
upstream/           # the legacy app, as a pinned git submodule (READ-ONLY reference)
```

> The legacy app is consumed as a **git submodule pinned to a specific commit**.
> We never modify it — this mirrors the real-world constraint of strangling a
> system you do not own.

## Status

Design complete for Phase 1 (catalog slice); implementation planning next. See
[`docs/design/`](docs/design/) for the architecture, the decision log, and the
problem/learning record.

## Documentation index

| Doc | What it covers |
| --- | --- |
| [`00-overview.md`](docs/design/00-overview.md) | Why this project exists and what "done" means |
| [`01-architecture.md`](docs/design/01-architecture.md) | System topology, the catalog slice, data strategy |
| [`02-decisions.md`](docs/design/02-decisions.md) | Decision log (ADR-style) with alternatives rejected |
| [`03-problems-and-learnings.md`](docs/design/03-problems-and-learnings.md) | Real problems hit in the design/demo phase, with root causes |
| [`04-running-the-legacy-app.md`](docs/design/04-running-the-legacy-app.md) | How to run the "before" app locally |
