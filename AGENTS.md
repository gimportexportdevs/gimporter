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
  - `gimporterApp`: App class and state machine (see Communication Flow), HTTP communication, course downloads, PersistedContent imports, messages to and from gexporter
  - `OutboxListener`: messages to the phone go through an outbox that sends one at a time (with a confirmation timeout), so a slow `Comm.transmit` cannot stall or reorder them
  - `gimporterView`/`gimporterDelegate`: Main view (drawn in code) and input handling
  - `SimilarCourseChooser`/`SimilarCourseChooserDelegate`: classic Menu for selecting from similar course matches

- **TrackChooser.mc**: Track list and similar-course list. `pushTrackChooser`/`pushSimilarCourseChooser` use a scrolling `Menu2` where the device has it and fall back to the classic paginated `Menu` (15 items per page with "MORE") on old devices

- **gimporterTest.mc**: Unit tests (`(:test)`), run by `make test`

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

Besides this pull flow, gexporter (20.2+) pushes: a tapped track (`"type": "track"`) or a shared place (`"type": "location"`) arrives as a phone message. gimporter downloads the track (or saves the place as a waypoint), shows its name with "Press Start", and Start hands it to the native course view or navigation via `exitTo`. Until Start, further pushes replace it. A content fingerprint keeps a track that is sent twice from being stored twice. The phone can also ask for and delete gimporter's content on the watch.

The app is a state machine (`mState`: IDLE, WAITING_FOR_PHONE, REQUESTING_PORT, LOADING_LIST, DOWNLOADING, CHOOSING_SIMILAR, READY_TO_START, LEAVING). `setState()` is the only place that changes it, and it reports the state to the phone ("importing", "imported", "started"; "ready" when idle), which drives gexporter's status line. Callbacks of an earlier download check the state and are ignored when it moved on.

### Old devices

- Oregon 7xx (API 2.2) has neither `Communications.transmit` nor `Application.Storage`: everything that uses them is behind `has` checks and the app falls back to the pull flow.
- On some devices (`approachs60/62/7042mm/7047mm`, `d2air`, `d2airx10`, `edge_1000`, `edge_520`, `fr735xt`, `oregon7xx`, `rino7xx`) the content API (`getAppCourses` etc.) crashes even behind a `has` check. Their builds exclude it with the `(:content)`/`(:nocontent)` annotations (`excludeAnnotations` in `monkey-base.jungleinc` and `monkey.jungle`); a new device of that kind goes on this list.
- Before API 3.1 there is no `fitTextToArea`; `wrapStatus` wraps the start screen text itself.

### Build Configuration

Builds run with monkeyc type checking (`-l 2`); keep new code warning-free.

monkeyc drops fixed-name scratch files (`internal-mir/`, `external-mir/`, `gen/`) into its `--output` directory, so concurrent compiles sharing one directory corrupt each other. The Makefile therefore builds every target in its own `bin/work/<target>/` directory and moves artifacts into place — do not "simplify" this away, it is what makes parallel `buildall` safe.

`make buildall` self-parallelizes: it recurses into a sub-make with `-j` bounded to the CPU count (`NPROC`, detected via `nproc`/`sysctl`), so a bare `make buildall` builds ~120 devices × 2 variants without forking 240 compiles at once. Override the job count with `make buildall JOBS=N`. Do not pass a bare `make -j buildall` — the explicit `-j$(JOBS)` on the recursion keeps it bounded regardless, but the bare flag is now unnecessary.

The build uses split jungle include files:
- `monkey-base.jungleinc`: Per-device resource paths (launcher icons, FIT/GPX support)
- `monkey-app.jungleinc`: App manifest reference
- `monkey-widget.jungleinc`: Widget manifest reference

There are no per-screen layouts: `gimporterView` draws the start view in code, relative to the screen size (round screens keep the text off the bezel, long titles wrap with `fitTextToArea` or get a smaller font, the Instinct subscreen shows the version). A new device therefore only needs a launcher icon size and FIT/GPX.

Resources are organized by:
- `resources-fit/` vs `resources-nofit/`: Device FIT file support capability
- `resources-launcher-NxN/`: Device-specific icon sizes
- `resources/strings/strings.xml`: English (default) UI strings; the language-neutral fallback for every locale
- `resources-<lang>/strings/strings.xml`: Per-language translations (deu, fre, spa, ita, dut, por, pol, ces, rus, swe, fin, dan, nob, tur, gre, hun, ukr, zhs, zht, jpn, kor)

### Localization

UI strings are translated via `resources-<lang>/strings/` directories. The SDK's `default.jungle` already maps each `base.lang.<code> = resources-<code>`, so **no jungle edits are needed** — just add the folder. But every translated language MUST also be listed in `manifest-app.xml`'s `<iq:languages>` block, or monkeyc silently ignores the folder ("String resources will be ignored. Add the '<lang>' language…"). The widget manifest is `sed`-generated from the app manifest, so it inherits the languages automatically.

Translation files only override the user-facing strings; brand/technical/symbol tokens (`AppName`, `AppVersion`, `GPXorFIT`, `MORE`) are intentionally left out and fall back to the default `resources`/device resources at runtime. `PressStart` mirrors the base `scope="glance"` attribute.

Expected build warning: monkeyc emits `String id '<X>' undefined for language 'hun'` for those un-translated tokens. This hits only ONE language — whichever is first in the SDK `base.lang.*` declaration order among the included set (`hun` today; remove it and `nob` inherits the warning). It is **cosmetic**: the simulator confirms that with the device set to Hungarian, `AppName`/`AppVersion` render correctly and `Ui.loadResource(Rez.Strings.GPXorFIT)` returns `"FIT"` — the runtime resolver falls back to the default/device resources exactly as for every other locale. Treat these like the glance "annotation will be ignored" no-ops, not regressions.

## Key Implementation Details

- Course name normalization strips `_course.fit`, `.fit`, `.gpx` suffixes for matching
- Port request has 1-second timeout (counted from when the outbox actually sends it) before falling back to default port 22222
- Classic menu pagination: 15 items per page, uses Symbol identifiers `:ITEM_0` through `:ITEM_15`

## Testing

- `make test DEVICE=<device>` runs the unit tests in the simulator. Test builds do not report "ready" to the phone, so they do not trigger the simulator's "no data connection" dialog.
- CI (`.github/workflows/build.yml`) runs the unit tests on one device per special case — `oregon7xx` (API 2.2, no transmit/Storage), `approachs62` (`(:nocontent)`), `d2charlie` (no `fitTextToArea`), `instinct2` (subscreen), `fenix6` (reference), `fenix847mm` (current AMOLED), `edge1050` (rectangular Edge) — and builds the store packages with `make package` (the `.iq` files are the CI artifact). Extend that list when a new kind of special case appears, rather than running `buildall` in CI.
- The CI image (`matco/connectiq-tester`) lags behind the SDK's device list; `.github/scripts/prune-unknown-devices.sh` drops devices it does not know yet before building.
- The whole phone-to-watch flow can run against the simulator with a gexporter debug build in simulator mode, see `gexporter/CLAUDE.md`. Test changes to the transfer on a real watch before release.

## Compatibility with gexporter

All combinations of old and new versions must work:
- New gimporter, old gexporter: the pull flow (track list) works as before.
- Old gimporter, new gexporter: gexporter notices that gimporter does not answer the new messages and tells the user to pick the track from the list; it lists places only for a gimporter that asks for them (`"locations" => "1"` in the list request).

## Releasing

1. release-please opens a "chore(master): release x.y.z" PR from the conventional commits; merging it tags the release and bumps the version.
2. Build the store packages: `make package` (or take the `.iq` files from the CI artifact).
3. Upload both in the Connect IQ developer dashboard (https://apps.garmin.com/developer/dashboard): the app (`gimporter-app.iq`) and the widget (`gimporter-widget.iq`), each via "Neue Version hochladen".
4. "What's new" in the store: only what users of the last published version notice, in user language; keep the history of earlier versions below the new entry. Descriptions, screenshots and the device icons are edited via "Details bearbeiten".

## Where users report problems

Look there now and then and before a release; answer in the reporter's language, and show the text to the maintainer before posting (it is public):
- GitHub issues: https://github.com/gimportexportdevs/gimporter/issues (and https://github.com/gimportexportdevs/gexporter/issues — many watch problems are reported there)
- Garmin forum support thread: https://forums.garmin.com/developer/connect-iq/f/showcase/5150/gimporter-gexporter---import-fit-gpx-courses-from-your-android-phone
- Connect IQ store reviews: app https://apps.garmin.com/apps/de11adc4-fdbb-40b5-86ac-7f93b47ea5bb, widget https://apps.garmin.com/apps/fac50ef3-77b2-466c-9f4f-4dcb2feb49a3
- App exists in two variants: watch-app and widget (widget manifest auto-generated from app manifest)