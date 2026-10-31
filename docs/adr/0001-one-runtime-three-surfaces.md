# One runtime output serves desktop, CLI, and web

**Status**: accepted (2026-10-31)

The web profile and its built frontend already ship inside the desktop runtime tree, so the desktop shell, the terminal `dsh`, and the manual web surface all reference the same `dsh-desktop-runtime` output. A thin `dsh` package wraps that output without Electron; the desktop package adds only the Electron shell. We accepted a larger CLI/web closure and a coupled update cadence instead of building a second, web-only runtime and payload pipeline.

## Considered Options

- **Separate slim web runtime**: smaller server closure, but a second offline build/lockfile pipeline and a second runtime to keep version-aligned.
- **Official npm release for CLI/web**: fast to package, but abandons the hermetic source build and reintroduces the legacy `pkgs/dsh` approach.

## Consequences

- Updating DSH updates every surface at once; there is no independent web version.
- The CLI/web closure includes desktop-only dependencies (Python, Office assets) even when only the web surface runs.
- `packages.dsh` must never copy or fix up the byte-hashed runtime tree; it only references it.
