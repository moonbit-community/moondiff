# Backend internals

The module root intentionally has no package. The `main` executable imports
`internal/server` directly, and implementation packages are layered from
infrastructure to transport:

- `crypto` is the lowest-level security primitive package.
- `protocol` owns shared errors and protocol/JSON adaptation.
- `config` and `httpio` provide configuration and bounded I/O primitives.
- `storage` owns application state and SQLite persistence.
- `auth`, `github`, and `device` implement session and upstream workflows.
- `home`, `merge`, and `viewed` are feature packages.
- `rpc` dispatches protocol requests without owning feature logic.
- `server` owns HTTP routing and process lifecycle.

Dependencies should only point from later bullets to earlier bullets. Feature
packages must not import one another; shared behavior belongs in a lower layer.

See [the backend design](../INTERNAL.md) for runtime behavior and security
invariants.
