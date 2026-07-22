# AbstractFramework working agreement

Read `CONTRIBUTING.md` before changing first-party Lua. Its secret-value,
shared-widget, evidence, and validation rules are mandatory.

AbstractFramework is the shared layer for BFInfinite. Put reusable widgets and
the one canonical secret-value helper here; do not create BFInfinite-local
forks or per-file replacements.

Before handing off a change, run:

```sh
./scripts/lint.sh [changed Lua files...]
```
