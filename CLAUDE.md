# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

gimporter is a Garmin ConnectIQ application written in MonkeyC that downloads GPX/FIT files from a companion Android app (gexporter) and imports them as courses on Garmin devices. Part of a larger gimporter/gexporter ecosystem.

## Build Commands

On Linux the Nix flake provides the full toolchain (ConnectIQ SDK + JDK, with
`SDK_HOME` set), so prefix any `make` command with `nix develop -c`, or enter
the shell once with `nix develop`:

```bash
nix develop -c make build        # Build app + widget for default device (set DEVICE in properties.mk)
nix develop -c make buildall     # Build app + widget for all supported devices (self-parallelizes to CPU count; override with JOBS=N)
nix develop -c make run          # Build and run in simulator
nix develop -c make test         # Run tests in simulator
nix develop -c make deploy       # Deploy to connected device
nix develop -c make package      # Create distribution .iq files (app + widget)
make clean                       # Remove build artifacts (no toolchain needed)
```

Build for a specific device: `nix develop -c make build DEVICE=fenix7`

Without Nix, drop the `nix develop -c` prefix and rely on a locally installed
SDK (see Development Setup below).

## Development Setup

On Linux, `nix develop` provides the full compile toolchain: the ConnectIQ SDK (pinned in `flake.nix` as a fixed-output derivation, exposed through a writable shadow under `~/.cache/gimporter/` because monkeyc writes `default.jungle` next to its jar), a JDK, and `SDK_HOME` set. The first `nix develop` downloads the SDK (~200 MB) and populates the shadow, so it is slow; subsequent runs are cached. Device definitions are NOT in the flake — download them once with Garmin's SDK manager (requires developer login); monkeyc finds them in `~/.Garmin/ConnectIQ/Devices`.

Without Nix, `properties.mk` auto-detects the SDK from the SDK manager's `current-sdk.cfg` (Linux: `~/.Garmin/ConnectIQ/`, macOS: `~/Library/Application Support/Garmin/ConnectIQ/`).

Configuration (all overridable via environment or a gitignored `properties.local.mk`):
- `DEVICE`: Target device (default: marqadventurer)
- `SDK_HOME`: ConnectIQ SDK path
- `PRIVATE_KEY`: Path to signing key (.der file, default `~/.id_rsa_garmin.der`)
- `DEPLOY`: Device mount point for deployment

## Architecture

### Source Files

- **gimporterApp.mc**: Main application containing:
  - `gimporterApp`: App class handling HTTP communication, course downloads, and PersistedContent imports
  - `gimporterView`/`gimporterDelegate`: Main view and input handling
  - `PortRequestListener`: Handles Android companion app communication
  - `SimilarCourseChooser`/`SimilarCourseChooserDelegate`: Menu for selecting from similar course matches

- **TrackChooser.mc**: Paginated track list UI (15 items per page with "MORE" option)

- **GlanceView.mc**: Glance shown in the widget carousel on glance-capable
  devices (app name + FIT/GPX mode + version). The glance execution scope
  only loads `(:glance)`-annotated code: `gimporterApp` itself carries the
  annotation (the system instantiates it in glance scope), strings touched
  on that path (`AppName`, `AppVersion`, `PressStart`, `GPXorFIT`) are
  marked `scope="glance"`, and foreground-only methods use
  `(:typecheck(disableGlanceCheck))`. On the 36 legacy devices without
  glance support the compiler prints "annotation will be ignored" warnings
  during `buildall` — these are expected no-ops, not regressions.

### Communication Flow

1. App checks Bluetooth connection (WiFi must be off)
2. Requests port from Android companion app via `Comm.transmit(["GET_PORT"], ...)`
3. Fetches track list from `http://127.0.0.1:[port]/dir.json`
4. Downloads selected track as GPX or FIT (device-dependent, set via `Rez.Strings.GPXorFIT`)
5. Imports via `PersistedContent` API, searches for matching course in courses/tracks/routes
6. If exact match found, launches course; if similar matches found, presents selection menu

### Build Configuration

Builds run with monkeyc type checking (`-l 2`); keep new code warning-free.

monkeyc drops fixed-name scratch files (`internal-mir/`, `external-mir/`, `gen/`) into its `--output` directory, so concurrent compiles sharing one directory corrupt each other. The Makefile therefore builds every target in its own `bin/work/<target>/` directory and moves artifacts into place — do not "simplify" this away, it is what makes parallel `buildall` safe.

`make buildall` self-parallelizes: it recurses into a sub-make with `-j` bounded to the CPU count (`NPROC`, detected via `nproc`/`sysctl`), so a bare `make buildall` builds ~120 devices × 2 variants without forking 240 compiles at once. Override the job count with `make buildall JOBS=N`. Do not pass a bare `make -j buildall` — the explicit `-j$(JOBS)` on the recursion keeps it bounded regardless, but the bare flag is now unnecessary.

The build uses split jungle include files:
- `monkey-base.jungleinc`: Per-device resource paths (launcher icons, FIT/GPX support)
- `monkey-app.jungleinc`: App manifest reference
- `monkey-widget.jungleinc`: Widget manifest reference

Resources are organized by:
- `resources-fit/` vs `resources-nofit/`: Device FIT file support capability
- `resources-launcher-NxN/`: Device-specific icon sizes
- `resources-round-NxN/`, `resources-rectangle-NxN/`, `resources-semiround-NxN/`: Screen shape layouts
- `resources/strings/strings.xml`: English (default) UI strings; the language-neutral fallback for every locale
- `resources-<lang>/strings/strings.xml`: Per-language translations (deu, fre, spa, ita, dut, por, pol, ces, rus, swe, fin, dan, nob, tur, gre, hun, ukr, zhs, zht, jpn, kor)

### Localization

UI strings are translated via `resources-<lang>/strings/` directories. The SDK's `default.jungle` already maps each `base.lang.<code> = resources-<code>`, so **no jungle edits are needed** — just add the folder. But every translated language MUST also be listed in `manifest-app.xml`'s `<iq:languages>` block, or monkeyc silently ignores the folder ("String resources will be ignored. Add the '<lang>' language…"). The widget manifest is `sed`-generated from the app manifest, so it inherits the languages automatically.

Translation files only override the user-facing strings; brand/technical/symbol tokens (`AppName`, `AppVersion`, `GPXorFIT`, `MORE`) are intentionally left out and fall back to the default `resources`/device resources at runtime. `PressStart` mirrors the base `scope="glance"` attribute.

Expected build warning: monkeyc emits `String id '<X>' undefined for language 'hun'` for those un-translated tokens. This hits only ONE language — whichever is first in the SDK `base.lang.*` declaration order among the included set (`hun` today; remove it and `nob` inherits the warning). It is **cosmetic**: the simulator confirms that with the device set to Hungarian, `AppName`/`AppVersion` render correctly and `Ui.loadResource(Rez.Strings.GPXorFIT)` returns `"FIT"` — the runtime resolver falls back to the default/device resources exactly as for every other locale. Treat these like the glance "annotation will be ignored" no-ops, not regressions.

## Key Implementation Details

- Course name normalization strips `_course.fit`, `.fit`, `.gpx` suffixes for matching
- Port request has 1-second timeout before falling back to default port 22222
- Track pagination: 15 items per page, uses Symbol identifiers `:ITEM_0` through `:ITEM_15`
- App exists in two variants: watch-app and widget (widget manifest auto-generated from app manifest)