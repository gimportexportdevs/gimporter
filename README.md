# gimporter
Garmin Connect App to import GPX and FIT files

* ConnectIQ App: https://apps.garmin.com/en-US/apps/de11adc4-fdbb-40b5-86ac-7f93b47ea5bb
* Android App: https://play.google.com/store/apps/details?id=org.surfsite.gexporter


## HOWTO
* start the Android app https://github.com/gimportexportdevs/gexporter on your mobile device (where your Garmin Connect app runs)
* build and start this Connect IQ app
* select a course to download
* start the course or download more
* check that the FIT file was imported (e.g. check the courses folder or start an activity with the course)

## iOS
* There is an experimental iOS app https://github.com/clawoo/gexporter-ios

## Development

### Toolchain

With [Nix](https://nixos.org/) (Linux), `nix develop` provides the complete
compile toolchain: the ConnectIQ SDK (pinned in `flake.nix`), a JDK, and
`SDK_HOME` already set. Without Nix, install the SDK via Garmin's
[SDK manager](https://developer.garmin.com/connect-iq/sdk/); `properties.mk`
picks up its `current-sdk.cfg` automatically on both Linux and macOS.
Machine-specific overrides (e.g. `DEVICE`, `PRIVATE_KEY`) go into a
gitignored `properties.local.mk`.

Either way you need two things the toolchain cannot ship:

* **Device definitions**: download them once with the SDK manager
  (requires a Garmin developer login).
* **Signing key**: `PRIVATE_KEY` defaults to `~/.id_rsa_garmin.der`;
  generate one with
  `openssl genrsa -out key.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in key.pem -out ~/.id_rsa_garmin.der -nocrypt`.

### Building

```
make build                 # app + widget for DEVICE (default: marqadventurer)
make build DEVICE=fenix7   # any device from the manifest
make -j buildall           # app + widget for every supported device
make run                   # build and launch in the simulator
make package               # store-ready .iq packages
```

`buildall` is parallel-safe: each target compiles in its own
`bin/work/<target>/` directory because monkeyc drops fixed-name scratch
files into its output directory and concurrent compiles sharing one
directory corrupt each other.
