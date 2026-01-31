# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

gimporter is a Garmin ConnectIQ application written in MonkeyC that downloads GPX/FIT files from a companion Android app (gexporter) and imports them as courses on Garmin devices. Part of a larger gimporter/gexporter ecosystem.

## Build Commands

```bash
make build           # Build for default device (set DEVICE in properties.mk)
make buildall        # Build for all supported devices
make run             # Build and run in simulator
make test            # Run tests in simulator
make deploy          # Deploy to connected device
make package         # Create distribution .iq files (app + widget)
make clean           # Remove build artifacts
```

Build for a specific device: `make build DEVICE=fenix7`

## Development Setup

Edit `properties.mk` to configure:
- `DEVICE`: Target device (default: marqadventurer)
- `SDK_HOME`: ConnectIQ SDK path (auto-detected from `~/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`)
- `PRIVATE_KEY`: Path to signing key (.der file)
- `DEPLOY`: Device mount point for deployment

## Architecture

### Source Files

- **gimporterApp.mc**: Main application containing:
  - `gimporterApp`: App class handling HTTP communication, course downloads, and PersistedContent imports
  - `gimporterView`/`gimporterDelegate`: Main view and input handling
  - `PortRequestListener`: Handles Android companion app communication
  - `SimilarCourseChooser`/`SimilarCourseChooserDelegate`: Menu for selecting from similar course matches

- **TrackChooser.mc**: Paginated track list UI (15 items per page with "MORE" option)

### Communication Flow

1. App checks Bluetooth connection (WiFi must be off)
2. Requests port from Android companion app via `Comm.transmit(["GET_PORT"], ...)`
3. Fetches track list from `http://127.0.0.1:[port]/dir.json`
4. Downloads selected track as GPX or FIT (device-dependent, set via `Rez.Strings.GPXorFIT`)
5. Imports via `PersistedContent` API, searches for matching course in courses/tracks/routes
6. If exact match found, launches course; if similar matches found, presents selection menu

### Build Configuration

The build uses split jungle include files:
- `monkey-base.jungleinc`: Per-device resource paths (launcher icons, FIT/GPX support)
- `monkey-app.jungleinc`: App manifest reference
- `monkey-widget.jungleinc`: Widget manifest reference

Resources are organized by:
- `resources-fit/` vs `resources-nofit/`: Device FIT file support capability
- `resources-launcher-NxN/`: Device-specific icon sizes
- `resources-round-NxN/`, `resources-rectangle-NxN/`, `resources-semiround-NxN/`: Screen shape layouts

## Key Implementation Details

- Course name normalization strips `_course.fit`, `.fit`, `.gpx` suffixes for matching
- Port request has 1-second timeout before falling back to default port 22222
- Track pagination: 15 items per page, uses Symbol identifiers `:ITEM_0` through `:ITEM_15`
- App exists in two variants: watch-app and widget (widget manifest auto-generated from app manifest)