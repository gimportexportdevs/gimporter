# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

gimporter is a Garmin ConnectIQ application written in MonkeyC that downloads GPX/FIT files from a companion Android app (gexporter) and imports them as courses on Garmin devices.

## Build Commands

```bash
# Build for default device (configured in properties.mk)
make build

# Build for all supported devices
make buildall

# Run in simulator
make run

# Run tests in simulator
make test

# Deploy to connected device
make deploy

# Create distribution packages (.iq files)
make package

# Clean build artifacts
make clean
```

## Development Setup

1. **Configure SDK Path**: Edit `properties.mk` to set your ConnectIQ SDK path
   - Default uses: `$(HOME)/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg`
   - Override by setting `SDK_HOME` in properties.mk

2. **Set Default Device**: Edit `DEVICE` in `properties.mk` (default: marqadventurer)

3. **Configure Private Key**: Set `PRIVATE_KEY` path in properties.mk for signing builds

## Architecture

### Core Components

- **gimporterApp.mc**: Main application class
  - Handles Bluetooth/WiFi connectivity checks
  - Manages HTTP communication with gexporter server
  - Downloads and imports courses using PersistedContent API
  - Receives port configuration from Android app via phone messages

- **TrackChooser.mc**: Track selection UI
  - Displays paginated list of available tracks
  - Handles menu navigation for track selection

### Communication Flow

1. App connects to Android companion via Bluetooth
2. Receives server port from Android app (default: 22222)
3. Fetches track list from `http://127.0.0.1:[port]/dir.json`
4. Downloads selected track as GPX/FIT file
5. Imports file using Garmin's PersistedContent API
6. Launches course or makes it available in device's courses

### Resource Organization

- `resources/`: Base resources and strings
- `resources-fit/`: Resources for devices supporting FIT files
- `resources-nofit/`: Resources for devices without FIT support
- `resources-launcher-*`: Device-specific launcher icons
- `resources-rectangle-*/resources-round-*/resources-semiround-*`: Layout resources by screen shape

## Testing

```bash
# Run tests for default device
make test

# Tests create device-specific test PRG files in bin/
# Example: bin/gimporter-marqadventurer-test.prg
```

## Key Configuration Files

- **manifest-app.xml**: Application manifest with supported devices
- **monkey.jungle**: Build configuration and resource paths
- **properties.mk**: Developer-specific settings (SDK path, device, keys)

## Device Support

The app supports a wide range of Garmin devices including:
- Edge series (520, 530, 820, 830, 1030, 1040, etc.)
- Fenix series (5, 5s, 5x, 6, 6s, 6x and their variants)
- Forerunner series (245, 645, 735XT, 935, 945)
- MARQ series
- Oregon/Montana/GPSMAP outdoor devices

## Important Implementation Details

- Uses PersistedContent API for course management (checks multiple content types: courses, tracks, routes)
- Requires Bluetooth connection to Android device
- WiFi must be disabled for proper operation
- Course name matching handles various suffixes like "_course.fit"
- Supports both GPX and FIT file formats (device-dependent)