# NotchDeck Modules

NotchDeck has a source-integrated, community-extensible module architecture.

> **Important:** the current model is **source-integrated through reviewed pull
> requests**. NotchDeck does **not** load arbitrary unsigned `.bundle` /
> `.dylib` files or downloaded executable code at runtime. Community modules are
> compiled into the app and reviewed like any other contribution.

## Directory layout

```
NotchDeck/Modules/
  Core/       # the protocol, descriptor, capabilities, registry, context
  BuiltIn/    # (existing shipped widgets live under Modules/… today)
  Community/  # accepted community modules
  Examples/   # example/template modules (never enabled by default)
```

## The building blocks

| Type                      | Purpose                                             |
| ------------------------- | --------------------------------------------------- |
| `NotchDeckModule`         | Protocol a module implements.                       |
| `ModuleDescriptor`        | Stable metadata (id, name, version, author, category, icon, default-enabled, surfaces, **capabilities**, settings). |
| `ModuleCapability`        | Declared sensitive access (camera, downloads, agent events, …). |
| `ModuleSurface`           | Where it presents (Home card, expanded tab, compact activity, settings, background). |
| `AnyNotchDeckModule`      | Type erasure for the registry.                      |
| `ModuleContext`           | Capability-gated access handed to the module.       |
| `CommunityModuleRegistry` | One authoritative registry (rejects duplicate ids). |

## Guides

- **[CREATING_A_MODULE.md](CREATING_A_MODULE.md)** — write and register a module.
- **[MODULE_REVIEW_GUIDELINES.md](MODULE_REVIEW_GUIDELINES.md)** — what reviewers
  check before a module is merged.

## Example

See `NotchDeck/Modules/Examples/UptimeExampleModule.swift` — a minimal module
with metadata, a Home card, optional settings, **no sensitive capability**, and
tests in `NotchDeckTests/ModuleArchitectureTests.swift`.

## Roadmap

Signed and/or sandboxed **external** extensions are a future goal, not a current
feature. See [../../SECURITY.md](../../SECURITY.md).
