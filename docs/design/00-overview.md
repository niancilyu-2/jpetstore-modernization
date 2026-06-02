# 00 — Overview

## Why this project exists

Two goals, in priority order:

1. **A real modernization exercise.** Take a genuinely legacy Java web app and
   modernize it without breaking it, using the strangler-fig pattern.
2. **A teaching artifact.** Capture the decisions, the architecture review, and —
   crucially — the *problems and dead ends* in enough detail that students can
   learn from the journey, not just the destination.

The second goal is why this repo over-documents. Most "example migrations" show a
clean before/after. The valuable, rarely-shared material is the friction: the
toolchain rot, the wrong assumptions, the recoveries. Those live in
[`03-problems-and-learnings.md`](03-problems-and-learnings.md) and will keep
growing as the project proceeds.

## The legacy app

[`mybatis/jpetstore-6`](https://github.com/mybatis/jpetstore-6), pinned at commit
`1478177`. It is **actively maintained** (current Spring 6, MyBatis 3.5, JUnit 5,
Docker, CI) — so the legacy is *not* the dependencies. The legacy is concentrated
in exactly two interlocked places:

- **Stripes 1.6.0** — an end-of-life web framework (ActionBean pattern, no REST
  nature, no annotation routing).
- **JSP** views coupled to Stripes.

Direct evidence that Stripes is the real blocker, from the upstream `pom.xml`:

```xml
<!-- Keep spring-web at 5.3.39 until jakarta upgrade occurs -->
```

…and the integration-test suite is commented out in the upstream build for the
same reason. The maintainers cannot move to Jakarta EE without removing Stripes.
That makes Stripes removal a **single, well-bounded blocker whose removal unlocks
a cascade** of upgrades — an ideal modernization shape.

## What "done" means for Phase 1

A user-visible **cutover of the catalog slice**:

- A new **Spring Boot 3** service exposes the catalog as REST, reusing the
  existing MyBatis mappers and services.
- A small **Astro** app replaces the 5 catalog JSPs.
- A **reverse proxy** sends `/catalog/*` and `/api/catalog/*` to the new stack;
  everything else still hits the untouched legacy WAR.

The defining assertion (borrowed from a prior project's hard-won lesson —
*"cutover IS verification"*): if a user browses the catalog in a real browser,
they MUST be served by the new stack, not the legacy JSP. A CI check of that is
Phase 1's safety net.

## Honest scope note

This codebase is a **technique** sandbox, not a **legacy-archaeology** sandbox.
The source is clean (plain POJOs, explicit SQL in mapper XML, constructor-injected
services). Students will *not* relive schema drift or implicit ORM magic here —
that texture lives in messier legacy systems. What this app *does* still teach,
unexpectedly well, is that **modernization friction often lives in the build and
the toolchain, not the source** — see the problem log.
