---
name: data-api-builder-relations
description: Define and manage entity relationships in Data API Builder dab-config.json. Use when asked to add, create, or configure relationships between entities, connect tables, or set up navigation properties in DAB.
license: MIT
---

# Data API Builder Relationships

This skill covers how to define entity relationships in Data API Builder (DAB) configuration files. Relationships enable navigation between related entities via REST and GraphQL endpoints.

---

## Golden Rule: Always Create Reciprocal Relationships

**When you create a relationship in one direction, you MUST always create the inverse relationship on the other entity.** This is non-negotiable.

For example, if `Product` has a many-to-one relationship to `Category`, then `Category` MUST also have a one-to-many relationship back to `Product`. Both sides must always exist.

### Why?

- Enables bidirectional navigation in both REST and GraphQL
- Users expect to traverse from either side (e.g., "get a category's products" AND "get a product's category")
- Incomplete relationships create confusing, asymmetric APIs

### Reciprocal Pair Pattern

Every foreign key produces **two** relationship entries:

```json
{
  "entities": {
    "Category": {
      "source": "dbo.Categories",
      "relationships": {
        "products": {
          "cardinality": "many",
          "target.entity": "Product",
          "source.fields": ["CategoryId"],
          "target.fields": ["CategoryId"]
        }
      }
    },
    "Product": {
      "source": "dbo.Products",
      "relationships": {
        "category": {
          "cardinality": "one",
          "target.entity": "Category",
          "source.fields": ["CategoryId"],
          "target.fields": ["CategoryId"]
        }
      }
    }
  }
}
```

---

## Relationship Types

| Type | Cardinality | Example | Description |
|------|-------------|---------|-------------|
| One-to-one | `"one"` on both sides | User ↔ Profile | Each row maps to exactly one row |
| One-to-many | `"many"` on parent, `"one"` on child | Category → Products | Parent has many children |
| Many-to-one | `"one"` on child, `"many"` on parent | Product → Category | Child points to one parent |
| Many-to-many | `"many"` on both sides + `linking.object` | Students ↔ Courses | Join table connects both |

---

## Relationship Properties

| Property | Required | Description |
|----------|----------|-------------|
| `cardinality` | Yes | `"one"` or `"many"` |
| `target.entity` | Yes | Name of the related entity |
| `source.fields` | No* | Column(s) on the source entity |
| `target.fields` | No* | Column(s) on the target entity |
| `linking.object` | Many-to-many only | Join table (e.g., `"dbo.Enrollments"`) |
| `linking.source.fields` | Many-to-many only | Join table column(s) for source |
| `linking.target.fields` | Many-to-many only | Join table column(s) for target |

\* DAB can infer fields from foreign keys, but explicit is always better.

---

## Examples

### One-to-Many / Many-to-One (with reciprocal)

```json
"Category": {
  "source": "dbo.Categories",
  "relationships": {
    "products": {
      "cardinality": "many",
      "target.entity": "Product",
      "source.fields": ["CategoryId"],
      "target.fields": ["CategoryId"]
    }
  }
},
"Product": {
  "source": "dbo.Products",
  "relationships": {
    "category": {
      "cardinality": "one",
      "target.entity": "Category",
      "source.fields": ["CategoryId"],
      "target.fields": ["CategoryId"]
    }
  }
}
```

### Many-to-Many (with reciprocal)

```json
"Student": {
  "source": "dbo.Students",
  "relationships": {
    "courses": {
      "cardinality": "many",
      "target.entity": "Course",
      "linking.object": "dbo.Enrollments",
      "linking.source.fields": ["StudentId"],
      "linking.target.fields": ["CourseId"]
    }
  }
},
"Course": {
  "source": "dbo.Courses",
  "relationships": {
    "students": {
      "cardinality": "many",
      "target.entity": "Student",
      "linking.object": "dbo.Enrollments",
      "linking.source.fields": ["CourseId"],
      "linking.target.fields": ["StudentId"]
    }
  }
}
```

### One-to-One (with reciprocal)

```json
"User": {
  "source": "dbo.Users",
  "relationships": {
    "profile": {
      "cardinality": "one",
      "target.entity": "Profile",
      "source.fields": ["UserId"],
      "target.fields": ["UserId"]
    }
  }
},
"Profile": {
  "source": "dbo.Profiles",
  "relationships": {
    "user": {
      "cardinality": "one",
      "target.entity": "User",
      "source.fields": ["UserId"],
      "target.fields": ["UserId"]
    }
  }
}
```

### Self-Referencing (with reciprocal)

```json
"Employee": {
  "source": "dbo.Employees",
  "relationships": {
    "manager": {
      "cardinality": "one",
      "target.entity": "Employee",
      "source.fields": ["ManagerId"],
      "target.fields": ["EmployeeId"]
    },
    "directReports": {
      "cardinality": "many",
      "target.entity": "Employee",
      "source.fields": ["EmployeeId"],
      "target.fields": ["ManagerId"]
    }
  }
}
```

---

## CLI Commands

```bash
# Add one-to-many: Category → Products
dab update Category \
  --relationship "products" \
  --cardinality many \
  --target.entity Product \
  --relationship.fields "CategoryId:CategoryId"

# Add reciprocal many-to-one: Product → Category
dab update Product \
  --relationship "category" \
  --cardinality one \
  --target.entity Category \
  --relationship.fields "CategoryId:CategoryId"
```

---

## Naming Conventions

| Direction | Convention | Example |
|-----------|-----------|---------|
| To-one (child → parent) | Singular, lowercase | `"category"`, `"warehouse"`, `"manager"` |
| To-many (parent → children) | Plural, lowercase | `"products"`, `"inventory"`, `"directReports"` |

---

## Constraints

- **Relationships cannot span configuration files.** Both entities must be in the same `dab-config.json` (or the same child config file).
- **Always specify `source.fields` and `target.fields` explicitly.** DAB can infer them from foreign keys, but explicit definitions are more reliable and self-documenting.
- **Many-to-many requires a `linking.object`.** The join table must exist in the database.

---

## Checklist

When adding relationships to a DAB config:

1. Identify the foreign key and which entity owns it
2. Add the relationship on the owning (child) entity with `cardinality: "one"`
3. Add the reciprocal relationship on the referenced (parent) entity with `cardinality: "many"`
4. Use singular names for to-one, plural names for to-many
5. Validate: `dab validate --config dab-config.json`
