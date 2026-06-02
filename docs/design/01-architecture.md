# 01 — Architecture

## System topology (Phase 1)

```
                                 ┌─────────────────────────────┐
                                 │  reverse proxy (strangler)  │
                                 └──────────────┬──────────────┘
                                                │
            ┌─────────────────────┬─────────────┴──────────────┬───────────────────────┐
            │                     │                            │                       │
   /catalog/*  (new UI)   /api/catalog/* (REST)    /api/catalog/health      everything else
            │                     │                            │                       │
            ▼                     ▼                            ▼                       ▼
   ┌────────────────┐   ┌─────────────────────────────────────────┐         ┌──────────────────┐
   │  Astro (SSR)   │──▶│  Spring Boot 3 service                   │         │  legacy WAR      │
   │                │   │  + MyBatis (mappers ported as-is)        │         │  (Stripes + JSP, │
   └────────────────┘   └───────────────┬─────────────────────────┘         │   Tomcat 9,      │
                                        │                                   │   UNTOUCHED)     │
                              ┌─────────▼─────────┐                         └─────────┬────────┘
                              │ embedded HSQLDB   │                         ┌─────────▼─────────┐
                              │ (Boot's JVM)      │                         │ embedded HSQLDB   │
                              └───────────────────┘                         │ (legacy's JVM)    │
                                                                            └───────────────────┘
```

## Components

| Component | Role | Source |
| --- | --- | --- |
| Reverse proxy (nginx) | Routes catalog traffic to the new stack, all else to legacy | Our config |
| Astro app | SSR frontend replacing the 5 catalog JSPs | New (this repo) |
| Spring Boot 3 service | REST API for the catalog, reusing legacy mappers/services | New (this repo) |
| Legacy WAR | Everything not yet strangled | `upstream/` submodule, unmodified |

## The catalog slice

The first slice is **catalog** — read-only, no session writes, already covered by
upstream tests, and a clean 1:1 to REST.

| Stripes today | REST tomorrow |
| --- | --- |
| `viewCategory(categoryId)` | `GET /api/catalog/categories/{id}` |
| `viewProduct(productId)` | `GET /api/catalog/products/{id}` |
| `viewItem(itemId)` | `GET /api/catalog/items/{id}` |
| `searchProducts(keyword)` | `GET /api/catalog/products?q={keyword}` |
| `viewMain()` | `GET /api/catalog/categories` |

The reusable core (survives the refactor untouched):

```
upstream/.../mapper/    7 MyBatis mappers   ← framework-agnostic
upstream/.../service/   CatalogService      ← framework-agnostic
```

Only the Stripes `web/actions/` layer (request binding, navigation, JSP forwarding)
is thrown away. That separation is exactly what makes the slice strangler-friendly.

## Data strategy

Phase 1 gives **each app its own embedded HSQLDB**, loaded from identical SQL.
This is safe *only because the catalog slice is read-only* — no writes means no
divergence between the two databases.

When a stateful slice (Cart, Order) arrives in a later phase, both apps must share
one database (a real Postgres). That graduation is itself a teaching moment: the
integration contract between old and new was always there; the separate in-memory
DBs merely let us defer it for a read-only slice.

## Boundaries we will hold

- **DTOs at the API edge.** The REST service returns explicit DTOs, not domain
  objects — so the wire contract is decoupled from persistence. (A lesson carried
  in from a prior project where leaking domain shapes over the wire broke a
  frontend cutover.)
- **Upstream is read-only.** It is a pinned submodule; the new stack consumes it,
  never edits it.

## Open design questions (not yet settled)

These are the design sections still to be worked through and recorded:

- Exact DTO shapes and JSON field names (must the Astro app match any legacy shape?)
- Error handling / status-code conventions for the REST layer
- Testing strategy: how the existing upstream tests pin behavior, plus the
  Playwright/e2e cutover assertion
- Reverse-proxy host port (host `:80` and `:8080` are already occupied in the
  dev sandbox — see the problem log)
- How the Boot service consumes mappers from the submodule (depend on the built
  artifact vs. import sources)
