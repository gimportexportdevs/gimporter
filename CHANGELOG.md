# Changelog

## [7.3.0](https://github.com/gimportexportdevs/gimporter/compare/v7.2.0...v7.3.0) (2026-07-06)


### Features

* translate UI into 21 major languages ([6c7c067](https://github.com/gimportexportdevs/gimporter/commit/6c7c0670133eb7ccf9238c87ac3a36420a1d6b12))

## [7.2.0](https://github.com/gimportexportdevs/gimporter/compare/v7.1.1...v7.2.0) (2026-07-06)


### Features

* add a glance view for the widget ([6e20c9d](https://github.com/gimportexportdevs/gimporter/commit/6e20c9d282945b3bfa92cf75e714f33ea5db33ea))
* distinct messages for storage-full, timeout and too-large errors ([e162504](https://github.com/gimportexportdevs/gimporter/commit/e16250409cc69d9960448deaee93e55b1faa9499)), closes [#32](https://github.com/gimportexportdevs/gimporter/issues/32)
* enable monkeyc type checking at level 2 ([ce80be0](https://github.com/gimportexportdevs/gimporter/commit/ce80be0c3b9516546056d8a04850dbcdf55a09fc)), closes [#30](https://github.com/gimportexportdevs/gimporter/issues/30)
* **nix:** headless simulator smoke test with screenshots (make simcheck) ([20d0610](https://github.com/gimportexportdevs/gimporter/commit/20d06107d7ae48b40c01ef89314ffc25b2deaf0b))
* nixify the ConnectIQ toolchain and make buildall parallel-safe ([0d1b48a](https://github.com/gimportexportdevs/gimporter/commit/0d1b48afef9ca3d95c92654fec070dbda64b8bf0))
* support Venu 4, vívoactive 6, and Forerunner 170 (2025 devices) ([aa9870c](https://github.com/gimportexportdevs/gimporter/commit/aa9870c5e4ab618e90e8c00a0adcf4b3f29f91f3))


### Bug Fixes

* course search could double-pop the view and skipped app tracks ([8716f8d](https://github.com/gimportexportdevs/gimporter/commit/8716f8de9da5181eafccb3016872d93189dc80bb)), closes [#25](https://github.com/gimportexportdevs/gimporter/issues/25)
* port handshake races and reentrancy during async windows ([a37b084](https://github.com/gimportexportdevs/gimporter/commit/a37b084cb835b92e4b7fbd498f9271acbdf674b2)), closes [#26](https://github.com/gimportexportdevs/gimporter/issues/26) [#27](https://github.com/gimportexportdevs/gimporter/issues/27)
* validate dir.json shape instead of crashing on malformed responses ([a4f64e3](https://github.com/gimportexportdevs/gimporter/commit/a4f64e32964eb0e7795a4c8b17e96da37df1308c)), closes [#28](https://github.com/gimportexportdevs/gimporter/issues/28)
* WiFi check never triggered - has does not test Dictionary keys ([8f92136](https://github.com/gimportexportdevs/gimporter/commit/8f92136388c02c6a4032f3a5716753f6a95cc492)), closes [#29](https://github.com/gimportexportdevs/gimporter/issues/29)

## [7.1.1](https://github.com/gimportexportdevs/gimporter/compare/v7.1.0...v7.1.1) (2026-03-24)


### Bug Fixes

* resolve connection errors on older devices (Fenix 5X Plus, Oregon 700) ([c089102](https://github.com/gimportexportdevs/gimporter/commit/c0891027cfa04c88e481a110e74847d48e1031ec))
