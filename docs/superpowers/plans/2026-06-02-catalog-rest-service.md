# Catalog REST Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Spring Boot 3 service that exposes the JPetStore catalog as a clean REST API, reusing the legacy MyBatis persistence layer verbatim.

**Architecture:** A standalone Maven module at `services/catalog/`. The legacy `domain`, `mapper` (interfaces + XML), and `CatalogService` are *vendored* (copied byte-for-byte from the pinned `upstream/` submodule) and kept in their original `org.mybatis.jpetstore.*` packages, guarded by a provenance test. New code is confined to an `org.mybatis.jpetstore.catalog` package: DTOs (a deliberate projection that hides internal cost fields), REST controllers, and a JSON error model. Persistence runs against an embedded HSQLDB seeded from the vendored SQL.

**Tech Stack:** Java 21, Spring Boot 3.3.5, MyBatis (`mybatis-spring-boot-starter` 3.0.4), HSQLDB (in-memory), JUnit 5 + Spring MockMvc.

This is **Plan 1 of 3** for Phase 1 (the others: the Astro frontend, and the compose/nginx strangler deployment). It produces working, independently-testable software on its own.

**Spec:** `docs/design/01-architecture.md`, `docs/design/02-decisions.md`.

---

## File Structure

```
services/catalog/
  pom.xml                                              # NEW  Maven module
  src/main/java/org/mybatis/jpetstore/
    domain/    Category.java Product.java Item.java    # VENDORED
    mapper/    CategoryMapper.java ProductMapper.java ItemMapper.java   # VENDORED
    service/   CatalogService.java                     # VENDORED
    catalog/
      Application.java                                 # NEW  entry point
      api/
        CatalogController.java                         # NEW  REST endpoints
        HealthController.java                          # NEW  liveness
      dto/
        CategoryDto.java ProductDto.java               # NEW
        ItemDto.java ProductSummaryDto.java            # NEW
      error/
        NotFoundException.java                         # NEW
        ApiExceptionHandler.java                       # NEW  @RestControllerAdvice
  src/main/resources/
    mapper/    CategoryMapper.xml ProductMapper.xml ItemMapper.xml      # VENDORED
    database/  jpetstore-hsqldb-schema.sql jpetstore-hsqldb-dataload.sql # VENDORED
    application.yml                                     # NEW
  src/test/java/org/mybatis/jpetstore/catalog/
    ApplicationTests.java                              # context loads
    ProvenanceTest.java                                # vendored == upstream
    CatalogServiceIT.java                              # MyBatis against HSQLDB
    dto/DtoMappingTest.java                            # projection unit tests
    api/CatalogControllerTest.java                     # MockMvc
    api/HealthControllerTest.java                      # MockMvc
```

All commands below are run from `services/catalog/` unless noted. The repo root
(containing `upstream/`) is two levels up (`../../`).

---

## Task 1: Scaffold the Boot module (web only)

**Files:**
- Create: `services/catalog/pom.xml`
- Create: `services/catalog/src/main/java/org/mybatis/jpetstore/catalog/Application.java`
- Create: `services/catalog/src/main/resources/application.yml`
- Test: `services/catalog/src/test/java/org/mybatis/jpetstore/catalog/ApplicationTests.java`

- [ ] **Step 1: Write the failing test**

`src/test/java/org/mybatis/jpetstore/catalog/ApplicationTests.java`:

```java
package org.mybatis.jpetstore.catalog;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class ApplicationTests {

  @Test
  void contextLoads() {
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test` (from `services/catalog/`)
Expected: FAIL — no `pom.xml` / no `Application` class yet (build error).

- [ ] **Step 3: Write minimal implementation**

`pom.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.5</version>
    <relativePath/>
  </parent>

  <groupId>org.mybatis.jpetstore</groupId>
  <artifactId>catalog-service</artifactId>
  <version>0.1.0-SNAPSHOT</version>
  <packaging>jar</packaging>
  <name>JPetStore Catalog Service</name>

  <properties>
    <java.version>21</java.version>
    <mybatis-spring-boot.version>3.0.4</mybatis-spring-boot.version>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
```

`src/main/java/org/mybatis/jpetstore/catalog/Application.java`:

```java
package org.mybatis.jpetstore.catalog;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "org.mybatis.jpetstore")
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }
}
```

`src/main/resources/application.yml`:

```yaml
server:
  port: 8081
spring:
  application:
    name: catalog-service
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn -q test`
Expected: PASS — `ApplicationTests.contextLoads` green.

- [ ] **Step 5: Commit**

```bash
git add services/catalog/pom.xml services/catalog/src
git commit -m "feat(catalog): scaffold Spring Boot module"
```

---

## Task 2: Health endpoint

**Files:**
- Create: `services/catalog/src/main/java/org/mybatis/jpetstore/catalog/api/HealthController.java`
- Test: `services/catalog/src/test/java/org/mybatis/jpetstore/catalog/api/HealthControllerTest.java`

- [ ] **Step 1: Write the failing test**

`src/test/java/org/mybatis/jpetstore/catalog/api/HealthControllerTest.java`:

```java
package org.mybatis.jpetstore.catalog.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HealthController.class)
class HealthControllerTest {

  @Autowired
  MockMvc mvc;

  @Test
  void reportsUp() throws Exception {
    mvc.perform(get("/api/catalog/health"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.status").value("UP"));
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test -Dtest=HealthControllerTest`
Expected: FAIL — `HealthController` does not exist (compile error), or 404.

- [ ] **Step 3: Write minimal implementation**

`src/main/java/org/mybatis/jpetstore/catalog/api/HealthController.java`:

```java
package org.mybatis.jpetstore.catalog.api;

import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/catalog")
public class HealthController {

  @GetMapping("/health")
  public Map<String, String> health() {
    return Map.of("status", "UP");
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn -q test -Dtest=HealthControllerTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/catalog/src
git commit -m "feat(catalog): add health endpoint"
```

---

## Task 3: Vendor the persistence layer + provenance test

This task copies the legacy files verbatim and adds a test that fails if they ever
drift from the pinned upstream. It also adds the MyBatis + HSQLDB dependencies and
configuration so the vendored code can run.

**Files:**
- Create (copy): `domain/{Category,Product,Item}.java`, `mapper/{Category,Product,Item}Mapper.java`, `service/CatalogService.java`
- Create (copy): `resources/mapper/{Category,Product,Item}Mapper.xml`, `resources/database/jpetstore-hsqldb-schema.sql`, `resources/database/jpetstore-hsqldb-dataload.sql`
- Modify: `pom.xml` (add mybatis + hsqldb), `application.yml` (datasource, mybatis, sql init), `Application.java` (add `@MapperScan`)
- Test: `src/test/java/org/mybatis/jpetstore/catalog/ProvenanceTest.java`

- [ ] **Step 1: Copy the vendored files**

Run (from `services/catalog/`):

```bash
mkdir -p src/main/java/org/mybatis/jpetstore/domain \
         src/main/java/org/mybatis/jpetstore/mapper \
         src/main/java/org/mybatis/jpetstore/service \
         src/main/resources/mapper \
         src/main/resources/database

cp ../../upstream/src/main/java/org/mybatis/jpetstore/domain/Category.java \
   ../../upstream/src/main/java/org/mybatis/jpetstore/domain/Product.java \
   ../../upstream/src/main/java/org/mybatis/jpetstore/domain/Item.java \
   src/main/java/org/mybatis/jpetstore/domain/

cp ../../upstream/src/main/java/org/mybatis/jpetstore/mapper/CategoryMapper.java \
   ../../upstream/src/main/java/org/mybatis/jpetstore/mapper/ProductMapper.java \
   ../../upstream/src/main/java/org/mybatis/jpetstore/mapper/ItemMapper.java \
   src/main/java/org/mybatis/jpetstore/mapper/

cp ../../upstream/src/main/java/org/mybatis/jpetstore/service/CatalogService.java \
   src/main/java/org/mybatis/jpetstore/service/

cp ../../upstream/src/main/resources/org/mybatis/jpetstore/mapper/CategoryMapper.xml \
   ../../upstream/src/main/resources/org/mybatis/jpetstore/mapper/ProductMapper.xml \
   ../../upstream/src/main/resources/org/mybatis/jpetstore/mapper/ItemMapper.xml \
   src/main/resources/mapper/

cp ../../upstream/src/main/resources/database/jpetstore-hsqldb-schema.sql \
   ../../upstream/src/main/resources/database/jpetstore-hsqldb-dataload.sql \
   src/main/resources/database/
```

> Note: `CatalogService` references all three mappers; `ItemMapper` also declares
> `updateInventoryQuantity`/`getInventoryQuantity` (unused by catalog reads) — copy
> it verbatim regardless. Do NOT edit any copied file.

- [ ] **Step 2: Write the failing provenance test**

`src/test/java/org/mybatis/jpetstore/catalog/ProvenanceTest.java`:

```java
package org.mybatis.jpetstore.catalog;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import org.junit.jupiter.api.Test;

/**
 * Asserts the vendored legacy files are byte-identical to the pinned upstream
 * submodule. If this fails, a vendored copy has drifted from upstream@1478177.
 */
class ProvenanceTest {

  private static final Path VENDORED = Path.of("src/main");
  private static final Path UPSTREAM = Path.of("../../upstream/src/main");

  // vendored path (under src/main) -> upstream path (under upstream/src/main)
  private static final Map<String, String> FILES = Map.ofEntries(
      Map.entry("java/org/mybatis/jpetstore/domain/Category.java",
                "java/org/mybatis/jpetstore/domain/Category.java"),
      Map.entry("java/org/mybatis/jpetstore/domain/Product.java",
                "java/org/mybatis/jpetstore/domain/Product.java"),
      Map.entry("java/org/mybatis/jpetstore/domain/Item.java",
                "java/org/mybatis/jpetstore/domain/Item.java"),
      Map.entry("java/org/mybatis/jpetstore/mapper/CategoryMapper.java",
                "java/org/mybatis/jpetstore/mapper/CategoryMapper.java"),
      Map.entry("java/org/mybatis/jpetstore/mapper/ProductMapper.java",
                "java/org/mybatis/jpetstore/mapper/ProductMapper.java"),
      Map.entry("java/org/mybatis/jpetstore/mapper/ItemMapper.java",
                "java/org/mybatis/jpetstore/mapper/ItemMapper.java"),
      Map.entry("java/org/mybatis/jpetstore/service/CatalogService.java",
                "java/org/mybatis/jpetstore/service/CatalogService.java"),
      Map.entry("resources/mapper/CategoryMapper.xml",
                "resources/org/mybatis/jpetstore/mapper/CategoryMapper.xml"),
      Map.entry("resources/mapper/ProductMapper.xml",
                "resources/org/mybatis/jpetstore/mapper/ProductMapper.xml"),
      Map.entry("resources/mapper/ItemMapper.xml",
                "resources/org/mybatis/jpetstore/mapper/ItemMapper.xml"),
      Map.entry("resources/database/jpetstore-hsqldb-schema.sql",
                "resources/database/jpetstore-hsqldb-schema.sql"),
      Map.entry("resources/database/jpetstore-hsqldb-dataload.sql",
                "resources/database/jpetstore-hsqldb-dataload.sql"));

  @Test
  void vendoredFilesMatchUpstream() throws Exception {
    for (Map.Entry<String, String> e : FILES.entrySet()) {
      Path vendored = VENDORED.resolve(e.getKey());
      Path upstream = UPSTREAM.resolve(e.getValue());
      assertThat(Files.readString(vendored))
          .as("vendored %s must match upstream %s", e.getKey(), e.getValue())
          .isEqualTo(Files.readString(upstream));
    }
  }
}
```

- [ ] **Step 3: Run test to verify it passes immediately**

Run: `mvn -q test -Dtest=ProvenanceTest`
Expected: PASS (the files were just copied). If it FAILS, a copy was altered — re-copy.

> This test is unusual: it passes on creation. To prove it *works*, temporarily add
> a space to a vendored file, re-run (expect FAIL), then revert. (Optional sanity check.)

- [ ] **Step 4: Add MyBatis + HSQLDB deps and config so the vendored code runs**

In `pom.xml`, add inside `<dependencies>` (before the test starter):

```xml
    <dependency>
      <groupId>org.mybatis.spring.boot</groupId>
      <artifactId>mybatis-spring-boot-starter</artifactId>
      <version>${mybatis-spring-boot.version}</version>
    </dependency>
    <dependency>
      <groupId>org.hsqldb</groupId>
      <artifactId>hsqldb</artifactId>
      <scope>runtime</scope>
    </dependency>
```

Replace `application.yml` with:

```yaml
server:
  port: 8081
spring:
  application:
    name: catalog-service
  datasource:
    url: jdbc:hsqldb:mem:jpetstore
    driver-class-name: org.hsqldb.jdbc.JDBCDriver
    username: sa
    password: ""
  sql:
    init:
      mode: always
      schema-locations: classpath:database/jpetstore-hsqldb-schema.sql
      data-locations: classpath:database/jpetstore-hsqldb-dataload.sql
mybatis:
  type-aliases-package: org.mybatis.jpetstore.domain
  mapper-locations: classpath:mapper/*.xml
```

In `Application.java`, add the `@MapperScan` import and annotation:

```java
package org.mybatis.jpetstore.catalog;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "org.mybatis.jpetstore")
@MapperScan("org.mybatis.jpetstore.mapper")
public class Application {

  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }
}
```

- [ ] **Step 5: Run the full suite to verify the context still loads with persistence**

Run: `mvn -q test`
Expected: PASS — `ApplicationTests.contextLoads` now wires MyBatis + the datasource;
`ProvenanceTest` green; `HealthControllerTest` green.

- [ ] **Step 6: Commit**

```bash
git add services/catalog/pom.xml services/catalog/src
git commit -m "feat(catalog): vendor legacy persistence layer with provenance test"
```

---

## Task 4: Verify persistence end-to-end against HSQLDB

Prove the vendored mappers + service + seed SQL actually return the expected data.
This is an integration test (real HSQLDB, no mocks).

**Files:**
- Test: `services/catalog/src/test/java/org/mybatis/jpetstore/catalog/CatalogServiceIT.java`

- [ ] **Step 1: Write the failing test**

`src/test/java/org/mybatis/jpetstore/catalog/CatalogServiceIT.java`:

```java
package org.mybatis.jpetstore.catalog;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;

import org.junit.jupiter.api.Test;
import org.mybatis.jpetstore.domain.Item;
import org.mybatis.jpetstore.domain.Product;
import org.mybatis.jpetstore.service.CatalogService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
class CatalogServiceIT {

  @Autowired
  CatalogService catalogService;

  @Test
  void loadsCategories() {
    assertThat(catalogService.getCategoryList()).hasSize(5);
    assertThat(catalogService.getCategory("FISH").getName()).isEqualTo("Fish");
  }

  @Test
  void loadsProduct() {
    Product p = catalogService.getProduct("FI-SW-01");
    assertThat(p.getName()).isEqualTo("Angelfish");
    assertThat(p.getCategoryId()).isEqualTo("FISH");
  }

  @Test
  void listsProductsByCategory() {
    assertThat(catalogService.getProductListByCategory("FISH"))
        .extracting(Product::getProductId)
        .contains("FI-SW-01", "FI-SW-02", "FI-FW-01");
  }

  @Test
  void searchMatchesByKeyword() {
    assertThat(catalogService.searchProductList("%angelfish%"))
        .extracting(Product::getProductId)
        .contains("FI-SW-01");
  }

  @Test
  void listsItemsByProduct() {
    assertThat(catalogService.getItemListByProduct("FI-SW-01"))
        .extracting(Item::getItemId)
        .containsExactlyInAnyOrder("EST-1", "EST-2");
  }

  @Test
  void getsItemWithProductAndInventory() {
    Item item = catalogService.getItem("EST-1");
    assertThat(item.getProductId()).isEqualTo("FI-SW-01");
    assertThat(item.getListPrice()).isEqualByComparingTo(new BigDecimal("16.50"));
    assertThat(item.getProduct().getName()).isEqualTo("Angelfish");
    assertThat(item.getQuantity()).isEqualTo(10000); // QTY from INVENTORY join
  }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `mvn -q test -Dtest=CatalogServiceIT`
Expected: PASS. (If it fails on data load, confirm `spring.sql.init` ran the schema
before the dataload — Boot runs `schema-locations` then `data-locations`.)

- [ ] **Step 3: Commit**

```bash
git add services/catalog/src
git commit -m "test(catalog): verify vendored persistence against HSQLDB"
```

---

## Task 5: Category & Product DTOs + mapping

DTOs are records with a static `from(...)` factory. No mapping framework.

**Files:**
- Create: `catalog/dto/CategoryDto.java`, `catalog/dto/ProductDto.java`, `catalog/dto/ProductSummaryDto.java`
- Test: `services/catalog/src/test/java/org/mybatis/jpetstore/catalog/dto/DtoMappingTest.java`

- [ ] **Step 1: Write the failing test**

`src/test/java/org/mybatis/jpetstore/catalog/dto/DtoMappingTest.java`:

```java
package org.mybatis.jpetstore.catalog.dto;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.mybatis.jpetstore.domain.Category;
import org.mybatis.jpetstore.domain.Product;

class DtoMappingTest {

  @Test
  void categoryMaps() {
    Category c = new Category();
    c.setCategoryId("FISH");
    c.setName("Fish");
    c.setDescription("desc");

    CategoryDto dto = CategoryDto.from(c);

    assertThat(dto.id()).isEqualTo("FISH");
    assertThat(dto.name()).isEqualTo("Fish");
    assertThat(dto.description()).isEqualTo("desc");
  }

  @Test
  void productMaps() {
    Product p = new Product();
    p.setProductId("FI-SW-01");
    p.setCategoryId("FISH");
    p.setName("Angelfish");
    p.setDescription("desc");

    ProductDto dto = ProductDto.from(p);

    assertThat(dto.id()).isEqualTo("FI-SW-01");
    assertThat(dto.categoryId()).isEqualTo("FISH");
    assertThat(dto.name()).isEqualTo("Angelfish");
    assertThat(dto.description()).isEqualTo("desc");
  }

  @Test
  void productSummaryMaps() {
    Product p = new Product();
    p.setProductId("FI-SW-01");
    p.setName("Angelfish");

    ProductSummaryDto dto = ProductSummaryDto.from(p);

    assertThat(dto.id()).isEqualTo("FI-SW-01");
    assertThat(dto.name()).isEqualTo("Angelfish");
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test -Dtest=DtoMappingTest`
Expected: FAIL — DTO classes do not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

`src/main/java/org/mybatis/jpetstore/catalog/dto/CategoryDto.java`:

```java
package org.mybatis.jpetstore.catalog.dto;

import org.mybatis.jpetstore.domain.Category;

public record CategoryDto(String id, String name, String description) {

  public static CategoryDto from(Category c) {
    return new CategoryDto(c.getCategoryId(), c.getName(), c.getDescription());
  }
}
```

`src/main/java/org/mybatis/jpetstore/catalog/dto/ProductDto.java`:

```java
package org.mybatis.jpetstore.catalog.dto;

import org.mybatis.jpetstore.domain.Product;

public record ProductDto(String id, String categoryId, String name, String description) {

  public static ProductDto from(Product p) {
    return new ProductDto(p.getProductId(), p.getCategoryId(), p.getName(), p.getDescription());
  }
}
```

`src/main/java/org/mybatis/jpetstore/catalog/dto/ProductSummaryDto.java`:

```java
package org.mybatis.jpetstore.catalog.dto;

import org.mybatis.jpetstore.domain.Product;

public record ProductSummaryDto(String id, String name) {

  public static ProductSummaryDto from(Product p) {
    return new ProductSummaryDto(p.getProductId(), p.getName());
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn -q test -Dtest=DtoMappingTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/catalog/src
git commit -m "feat(catalog): add Category and Product DTOs"
```

---

## Task 6: ItemDto with projection (drop internal fields)

`ItemDto` must NOT expose `unitCost` or `supplierId`, and must collapse
`attribute1..5` (nulls removed) into a list plus a nested product summary.

**Files:**
- Create: `catalog/dto/ItemDto.java`
- Modify: `src/test/java/org/mybatis/jpetstore/catalog/dto/DtoMappingTest.java` (add cases)

- [ ] **Step 1: Add the failing tests**

Append these methods inside `DtoMappingTest` (and add imports
`org.mybatis.jpetstore.domain.Item` and `java.math.BigDecimal`):

```java
  @Test
  void itemMapsAndProjectsAwayInternalFields() {
    Product p = new Product();
    p.setProductId("FI-SW-01");
    p.setName("Angelfish");

    Item item = new Item();
    item.setItemId("EST-1");
    item.setProduct(p);
    item.setListPrice(new BigDecimal("16.50"));
    item.setUnitCost(new BigDecimal("10.00")); // internal — must not leak
    item.setSupplierId(1);                      // internal — must not leak
    item.setStatus("P");
    item.setQuantity(10000);
    item.setAttribute1("Large");

    ItemDto dto = ItemDto.from(item);

    assertThat(dto.id()).isEqualTo("EST-1");
    assertThat(dto.productId()).isEqualTo("FI-SW-01");
    assertThat(dto.listPrice()).isEqualByComparingTo(new BigDecimal("16.50"));
    assertThat(dto.quantity()).isEqualTo(10000);
    assertThat(dto.status()).isEqualTo("P");
    assertThat(dto.attributes()).containsExactly("Large");
    assertThat(dto.product().id()).isEqualTo("FI-SW-01");
    assertThat(dto.product().name()).isEqualTo("Angelfish");
  }

  @Test
  void itemDtoHasNoCostOrSupplierAccessors() {
    // The record's components are the entire public surface — assert by name.
    assertThat(ItemDto.class.getRecordComponents())
        .extracting(java.lang.reflect.RecordComponent::getName)
        .doesNotContain("unitCost", "supplierId");
  }
```

> `Item.productId` is populated by the mapper alias `I.PRODUCTID`; the nested
> `Item.product` is populated separately (`product.*` aliases). Both are available.

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test -Dtest=DtoMappingTest`
Expected: FAIL — `ItemDto` does not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

`src/main/java/org/mybatis/jpetstore/catalog/dto/ItemDto.java`:

```java
package org.mybatis.jpetstore.catalog.dto;

import java.math.BigDecimal;
import java.util.List;
import java.util.Objects;
import java.util.stream.Stream;

import org.mybatis.jpetstore.domain.Item;

public record ItemDto(String id, String productId, BigDecimal listPrice, int quantity,
                      String status, List<String> attributes, ProductSummaryDto product) {

  public static ItemDto from(Item i) {
    List<String> attributes = Stream
        .of(i.getAttribute1(), i.getAttribute2(), i.getAttribute3(),
            i.getAttribute4(), i.getAttribute5())
        .filter(Objects::nonNull)
        .toList();
    ProductSummaryDto product = i.getProduct() == null ? null : ProductSummaryDto.from(i.getProduct());
    return new ItemDto(i.getItemId(), i.getProductId(), i.getListPrice(), i.getQuantity(),
        i.getStatus(), attributes, product);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn -q test -Dtest=DtoMappingTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/catalog/src
git commit -m "feat(catalog): add ItemDto projecting away unitCost/supplierId"
```

---

## Task 7: Catalog controller — category endpoints

**Files:**
- Create: `catalog/api/CatalogController.java`
- Test: `services/catalog/src/test/java/org/mybatis/jpetstore/catalog/api/CatalogControllerTest.java`

> This test uses `@WebMvcTest` with a mocked `CatalogService` so it stays a fast
> web-layer test. (End-to-end data is already covered by `CatalogServiceIT`.)

- [ ] **Step 1: Write the failing test**

`src/test/java/org/mybatis/jpetstore/catalog/api/CatalogControllerTest.java`:

```java
package org.mybatis.jpetstore.catalog.api;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.mybatis.jpetstore.domain.Category;
import org.mybatis.jpetstore.domain.Product;
import org.mybatis.jpetstore.service.CatalogService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(CatalogController.class)
class CatalogControllerTest {

  @Autowired
  MockMvc mvc;

  @MockBean
  CatalogService catalogService;

  private Category category(String id, String name) {
    Category c = new Category();
    c.setCategoryId(id);
    c.setName(name);
    c.setDescription("desc");
    return c;
  }

  private Product product(String id, String categoryId, String name) {
    Product p = new Product();
    p.setProductId(id);
    p.setCategoryId(categoryId);
    p.setName(name);
    p.setDescription("desc");
    return p;
  }

  @Test
  void listsCategories() throws Exception {
    when(catalogService.getCategoryList()).thenReturn(List.of(category("FISH", "Fish")));

    mvc.perform(get("/api/catalog/categories"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$[0].id").value("FISH"))
        .andExpect(jsonPath("$[0].name").value("Fish"));
  }

  @Test
  void getsCategory() throws Exception {
    when(catalogService.getCategory("FISH")).thenReturn(category("FISH", "Fish"));

    mvc.perform(get("/api/catalog/categories/FISH"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.id").value("FISH"));
  }

  @Test
  void listsProductsInCategory() throws Exception {
    when(catalogService.getProductListByCategory("FISH"))
        .thenReturn(List.of(product("FI-SW-01", "FISH", "Angelfish")));

    mvc.perform(get("/api/catalog/categories/FISH/products"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$[0].id").value("FI-SW-01"))
        .andExpect(jsonPath("$[0].categoryId").value("FISH"));
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test -Dtest=CatalogControllerTest`
Expected: FAIL — `CatalogController` does not exist (compile error).

- [ ] **Step 3: Write minimal implementation**

`src/main/java/org/mybatis/jpetstore/catalog/api/CatalogController.java`:

```java
package org.mybatis.jpetstore.catalog.api;

import java.util.List;

import org.mybatis.jpetstore.catalog.dto.CategoryDto;
import org.mybatis.jpetstore.catalog.dto.ProductDto;
import org.mybatis.jpetstore.service.CatalogService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/catalog")
public class CatalogController {

  private final CatalogService catalogService;

  public CatalogController(CatalogService catalogService) {
    this.catalogService = catalogService;
  }

  @GetMapping("/categories")
  public List<CategoryDto> categories() {
    return catalogService.getCategoryList().stream().map(CategoryDto::from).toList();
  }

  @GetMapping("/categories/{id}")
  public CategoryDto category(@PathVariable String id) {
    return CategoryDto.from(catalogService.getCategory(id));
  }

  @GetMapping("/categories/{id}/products")
  public List<ProductDto> productsInCategory(@PathVariable String id) {
    return catalogService.getProductListByCategory(id).stream().map(ProductDto::from).toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn -q test -Dtest=CatalogControllerTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/catalog/src
git commit -m "feat(catalog): add category REST endpoints"
```

---

## Task 8: Catalog controller — product, item & search endpoints

**Files:**
- Modify: `catalog/api/CatalogController.java`
- Modify: `src/test/java/org/mybatis/jpetstore/catalog/api/CatalogControllerTest.java`

- [ ] **Step 1: Add the failing tests**

Add these imports to the test (`Item`, `BigDecimal`) and these methods inside
`CatalogControllerTest`:

```java
  private org.mybatis.jpetstore.domain.Item item(String id, String productId) {
    org.mybatis.jpetstore.domain.Item i = new org.mybatis.jpetstore.domain.Item();
    i.setItemId(id);
    i.setProduct(product(productId, "FISH", "Angelfish"));
    i.setListPrice(new java.math.BigDecimal("16.50"));
    i.setUnitCost(new java.math.BigDecimal("10.00"));
    i.setSupplierId(1);
    i.setStatus("P");
    i.setQuantity(10000);
    i.setAttribute1("Large");
    return i;
  }

  @Test
  void getsProduct() throws Exception {
    when(catalogService.getProduct("FI-SW-01")).thenReturn(product("FI-SW-01", "FISH", "Angelfish"));

    mvc.perform(get("/api/catalog/products/FI-SW-01"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.id").value("FI-SW-01"));
  }

  @Test
  void listsItemsForProduct() throws Exception {
    when(catalogService.getItemListByProduct("FI-SW-01")).thenReturn(List.of(item("EST-1", "FI-SW-01")));

    mvc.perform(get("/api/catalog/products/FI-SW-01/items"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$[0].id").value("EST-1"));
  }

  @Test
  void getsItemWithoutLeakingInternalFields() throws Exception {
    when(catalogService.getItem("EST-1")).thenReturn(item("EST-1", "FI-SW-01"));

    mvc.perform(get("/api/catalog/items/EST-1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.id").value("EST-1"))
        .andExpect(jsonPath("$.listPrice").value(16.50))
        .andExpect(jsonPath("$.product.name").value("Angelfish"))
        .andExpect(jsonPath("$.unitCost").doesNotExist())
        .andExpect(jsonPath("$.supplierId").doesNotExist());
  }

  @Test
  void searchesProducts() throws Exception {
    when(catalogService.searchProductList("%angelfish%"))
        .thenReturn(List.of(product("FI-SW-01", "FISH", "Angelfish")));

    mvc.perform(get("/api/catalog/products").param("q", "Angelfish"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$[0].id").value("FI-SW-01"));
  }
```

> The search test expects the controller to lowercase and wildcard-wrap the keyword
> to `%angelfish%` before calling the service — mirroring how the legacy
> `CatalogActionBean` lowercases input (the service itself also splits/wraps, but the
> controller normalizes the single-keyword path for a predictable contract).

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test -Dtest=CatalogControllerTest`
Expected: FAIL — new endpoints not implemented.

- [ ] **Step 3: Write minimal implementation**

Add imports to `CatalogController` (`ItemDto`, `RequestParam`) and these methods:

```java
  @GetMapping("/products/{id}")
  public ProductDto product(@PathVariable String id) {
    return ProductDto.from(catalogService.getProduct(id));
  }

  @GetMapping("/products/{id}/items")
  public List<ItemDto> itemsForProduct(@PathVariable String id) {
    return catalogService.getItemListByProduct(id).stream().map(ItemDto::from).toList();
  }

  @GetMapping("/items/{id}")
  public ItemDto item(@PathVariable String id) {
    return ItemDto.from(catalogService.getItem(id));
  }

  @GetMapping("/products")
  public List<ProductDto> search(@RequestParam("q") String q) {
    return catalogService.searchProductList("%" + q.toLowerCase() + "%").stream()
        .map(ProductDto::from).toList();
  }
```

Required new imports at the top of `CatalogController`:

```java
import org.mybatis.jpetstore.catalog.dto.ItemDto;
import org.springframework.web.bind.annotation.RequestParam;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mvn -q test -Dtest=CatalogControllerTest`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/catalog/src
git commit -m "feat(catalog): add product, item and search endpoints"
```

---

## Task 9: Error handling — 404 not-found and 400 blank-search

Replace null-returns and missing `q` with proper status codes and a JSON error body.

**Files:**
- Create: `catalog/error/NotFoundException.java`, `catalog/error/ApiExceptionHandler.java`
- Modify: `catalog/api/CatalogController.java` (throw `NotFoundException`; reject blank `q`)
- Modify: `src/test/java/org/mybatis/jpetstore/catalog/api/CatalogControllerTest.java` (add cases)

- [ ] **Step 1: Add the failing tests**

Add inside `CatalogControllerTest`:

```java
  @Test
  void missingCategoryReturns404() throws Exception {
    when(catalogService.getCategory("NOPE")).thenReturn(null);

    mvc.perform(get("/api/catalog/categories/NOPE"))
        .andExpect(status().isNotFound())
        .andExpect(jsonPath("$.status").value(404))
        .andExpect(jsonPath("$.path").value("/api/catalog/categories/NOPE"));
  }

  @Test
  void missingProductReturns404() throws Exception {
    when(catalogService.getProduct("NOPE")).thenReturn(null);

    mvc.perform(get("/api/catalog/products/NOPE"))
        .andExpect(status().isNotFound());
  }

  @Test
  void missingItemReturns404() throws Exception {
    when(catalogService.getItem("NOPE")).thenReturn(null);

    mvc.perform(get("/api/catalog/items/NOPE"))
        .andExpect(status().isNotFound());
  }

  @Test
  void blankSearchReturns400() throws Exception {
    mvc.perform(get("/api/catalog/products").param("q", "   "))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.status").value(400));
  }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mvn -q test -Dtest=CatalogControllerTest`
Expected: FAIL — currently a missing category throws NPE (500) and blank `q`
returns 200, not 404/400.

- [ ] **Step 3: Write the exception + handler**

`src/main/java/org/mybatis/jpetstore/catalog/error/NotFoundException.java`:

```java
package org.mybatis.jpetstore.catalog.error;

public class NotFoundException extends RuntimeException {

  public NotFoundException(String message) {
    super(message);
  }
}
```

`src/main/java/org/mybatis/jpetstore/catalog/error/ApiExceptionHandler.java`:

```java
package org.mybatis.jpetstore.catalog.error;

import java.util.Map;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {

  @ExceptionHandler(NotFoundException.class)
  public ResponseEntity<Map<String, Object>> notFound(NotFoundException ex, HttpServletRequest req) {
    return body(HttpStatus.NOT_FOUND, ex.getMessage(), req);
  }

  @ExceptionHandler(IllegalArgumentException.class)
  public ResponseEntity<Map<String, Object>> badRequest(IllegalArgumentException ex, HttpServletRequest req) {
    return body(HttpStatus.BAD_REQUEST, ex.getMessage(), req);
  }

  private ResponseEntity<Map<String, Object>> body(HttpStatus status, String message, HttpServletRequest req) {
    return ResponseEntity.status(status).body(Map.of(
        "status", status.value(),
        "error", status.getReasonPhrase(),
        "message", message == null ? "" : message,
        "path", req.getRequestURI()));
  }
}
```

- [ ] **Step 4: Make the controller throw**

In `CatalogController`, add the `NotFoundException` import:

```java
import org.mybatis.jpetstore.catalog.error.NotFoundException;
```

Replace the `category`, `product`, `item`, and `search` methods with:

```java
  @GetMapping("/categories/{id}")
  public CategoryDto category(@PathVariable String id) {
    Category c = catalogService.getCategory(id);
    if (c == null) {
      throw new NotFoundException("category not found: " + id);
    }
    return CategoryDto.from(c);
  }

  @GetMapping("/products/{id}")
  public ProductDto product(@PathVariable String id) {
    Product p = catalogService.getProduct(id);
    if (p == null) {
      throw new NotFoundException("product not found: " + id);
    }
    return ProductDto.from(p);
  }

  @GetMapping("/items/{id}")
  public ItemDto item(@PathVariable String id) {
    Item i = catalogService.getItem(id);
    if (i == null) {
      throw new NotFoundException("item not found: " + id);
    }
    return ItemDto.from(i);
  }

  @GetMapping("/products")
  public List<ProductDto> search(@RequestParam("q") String q) {
    if (q == null || q.isBlank()) {
      throw new IllegalArgumentException("search keyword must not be blank");
    }
    return catalogService.searchProductList("%" + q.toLowerCase() + "%").stream()
        .map(ProductDto::from).toList();
  }
```

Add the required domain imports to `CatalogController`:

```java
import org.mybatis.jpetstore.domain.Category;
import org.mybatis.jpetstore.domain.Item;
import org.mybatis.jpetstore.domain.Product;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mvn -q test -Dtest=CatalogControllerTest`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add services/catalog/src
git commit -m "feat(catalog): add 404/400 error handling with JSON body"
```

---

## Task 10: Full green build + manual smoke

**Files:** none (verification only)

- [ ] **Step 1: Run the entire suite**

Run: `mvn -q test`
Expected: PASS — `ApplicationTests`, `ProvenanceTest`, `CatalogServiceIT`,
`DtoMappingTest`, `HealthControllerTest`, `CatalogControllerTest` all green.

- [ ] **Step 2: Boot the app and smoke-test the live endpoints**

Run: `mvn -q spring-boot:run` (in one shell), then in another:

```bash
curl -s localhost:8081/api/catalog/health
curl -s localhost:8081/api/catalog/categories
curl -s localhost:8081/api/catalog/products/FI-SW-01
curl -s localhost:8081/api/catalog/items/EST-1     # must NOT contain unitCost/supplierId
curl -s "localhost:8081/api/catalog/products?q=angelfish"
curl -s -o /dev/null -w "%{http_code}\n" localhost:8081/api/catalog/categories/NOPE  # 404
```

Expected: JSON payloads as designed; `items/EST-1` shows `listPrice`, `quantity`,
`product`, no `unitCost`/`supplierId`; the bad id returns `404`. Stop with Ctrl-C.

- [ ] **Step 3: Commit (if any incidental fixes were needed)**

```bash
git add -A
git commit -m "chore(catalog): full green build for catalog service"
```

---

## Notes for the next plans

- **CORS:** not configured here. The Astro frontend (Plan 2) calls this API
  server-side (SSR) over the docker network, so CORS is unnecessary. If any
  client-side fetch is added, revisit.
- **DB lifecycle:** in-memory HSQLDB is recreated per process and reseeded by
  `spring.sql.init`. Fine for a read-only slice (ADR-005).
- **List-vs-detail quantity:** `getItemListByProduct` does not join `INVENTORY`, so
  `ItemDto.quantity` is `0` for list results and accurate only for `items/{id}` —
  this preserves legacy behavior intentionally.
