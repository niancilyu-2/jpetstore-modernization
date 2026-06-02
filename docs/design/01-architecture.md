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

## Module layout & build

```
services/catalog/                 # Spring Boot 3, Maven, Java 21
  src/main/java/org/mybatis/jpetstore/
    domain/    Category, Product, Item        # VENDORED from upstream@1478177
    mapper/    Category/Item/ProductMapper    # VENDORED
    service/   CatalogService                 # VENDORED
    catalog/   CatalogController, dto/, error/, Application.java   # NEW
  src/main/resources/
    mapper/*.xml                              # VENDORED (MyBatis XML)
    database/*.sql                            # VENDORED seed for embedded HSQLDB
    application.yml
  src/test/java/...                           # provenance + mapper + web tests
frontend/catalog/                 # Astro (SSR)
docker/
  legacy.Dockerfile               # run the unmodified legacy app
  compose.yaml                    # legacy + catalog-api + catalog-web + nginx
  nginx/default.conf              # the strangler routing
```

Vendored files keep their `org.mybatis.jpetstore.*` packages so `CatalogService`
and the mappers wire up unchanged. A **provenance test** asserts each vendored
file is byte-identical to its `upstream/` counterpart; if the upstream pin moves
and a file drifts, the test fails loudly. Build uses Maven +
`mybatis-spring-boot-starter`, matching the upstream idiom. See ADR-007 in
[`02-decisions.md`](02-decisions.md).

## DTO contract

The legacy serves HTML (JSP), so **there is no existing JSON contract** — we
define it. DTOs are a deliberate projection that hides internal fields:

```jsonc
CategoryDto { "id", "name", "description" }
ProductDto  { "id", "categoryId", "name", "description" }
ItemDto     { "id", "productId", "listPrice", "quantity",   // quantity = inventory in stock
              "status", "attributes": [..], "product": { "id", "name" } }
              // DROPPED: unitCost, supplierId  <- internal/cost data, never exposed
```

`listPrice` (a `BigDecimal`) serializes as a JSON number. The dropped
`unitCost`/`supplierId` are a teaching artifact: a web-layer test asserts they
never appear in any response. This is the decoupling lesson — the wire contract is
chosen, not inherited from the persistence shape.

## REST API + error handling

| Method & path | Maps to (`CatalogService`) | Notes |
| --- | --- | --- |
| `GET /api/catalog/categories` | `getCategoryList()` | homepage payload |
| `GET /api/catalog/categories/{id}` | `getCategory()` | 404 if missing |
| `GET /api/catalog/categories/{id}/products` | `getProductListByCategory()` | |
| `GET /api/catalog/products/{id}` | `getProduct()` | 404 if missing |
| `GET /api/catalog/products/{id}/items` | `getItemListByProduct()` | |
| `GET /api/catalog/items/{id}` | `getItem()` | 404 if missing |
| `GET /api/catalog/products?q=…` | `searchProductList()` | blank `q` -> 400 (mirrors legacy "enter a keyword") |
| `GET /api/catalog/health` | — | liveness |

A single `@RestControllerAdvice` returns a small JSON error body
`{ status, error, message, path }`. A not-found maps to 404; a blank search maps
to 400.

## Testing strategy

1. **Provenance test** — vendored files are byte-identical to the upstream pin.
2. **Mapper tests** — MyBatis against embedded HSQLDB seeded from the vendored
   SQL (ported from upstream's catalog mapper tests).
3. **Web-layer tests (MockMvc)** — status codes, the 404/400 paths, and the
   projection assertion (`unitCost`/`supplierId` absent from every response).
4. **E2E cutover (Playwright, through nginx)** — the marquee check: browsing
   `/catalog/...` is served by the new stack, while a legacy path still hits the
   legacy WAR. "Cutover IS verification."

## Deployment & strangler routing

`docker/compose.yaml` runs four services; only nginx is exposed on the host, at
port **8888** (host `:80` and `:8080` are occupied in the dev sandbox — see the
problem log).

```nginx
location /api/catalog/  { proxy_pass http://catalog-api:8081; }   # new REST
location /catalog/      { proxy_pass http://catalog-web:4321; }   # new Astro UI
location /              { proxy_pass http://legacy:8080; }        # everything else, untouched
```

The legacy app keeps its existing `/jpetstore/` context; the new catalog is
canonical at `/catalog/`. We deliberately do **not** rewrite legacy URLs in nginx
— that adds complexity with no Phase-1 benefit. Each app keeps its own embedded
HSQLDB (read-only slice -> safe; see ADR-005).
