# Changelog

## [7.4.0](https://github.com/gimportexportdevs/gimporter/compare/v7.3.0...v7.4.0) (2026-10-21)


### Features

* ask gexporter for shared locations in the track list ([c7fd681](https://github.com/gimportexportdevs/gimporter/commit/c7fd6816c34fb115f43e52d7100493be47334c7e))
* download tracks pushed from the phone and remember fingerprints ([3919b28](https://github.com/gimportexportdevs/gimporter/commit/3919b28f7ad7a1db7122a436b0a82ddd26aeac02))
* let the phone list and delete gimporter's content ([cee46ac](https://github.com/gimportexportdevs/gimporter/commit/cee46ac430e2654282f5f69ca373761d4c063348))
* offer tracks pushed from the phone for starting instead of starting them ([b723484](https://github.com/gimportexportdevs/gimporter/commit/b723484a5ba212e86c023153c8d9089041d11439))
* receive locations pushed from the phone ([5790649](https://github.com/gimportexportdevs/gimporter/commit/579064921bf4dddd9ebe20637bd8995a4379d5f4))
* report the app's state to the phone ([5fbb6d8](https://github.com/gimportexportdevs/gimporter/commit/5fbb6d8835a1e9330e59a58acf82f34e4a0ad209))
* save shared locations and navigate to them ([764f224](https://github.com/gimportexportdevs/gimporter/commit/764f2246dff76b4260bb4170d757c59a5a9dc16f))
* scrolling track lists, nine new devices, and fixes found testing every device ([635ec8a](https://github.com/gimportexportdevs/gimporter/commit/635ec8a1d6ea0e5875f05e0c653dc9ba027ebd50))


### Bug Fixes

* do not store a track twice when it is sent again ([2785104](https://github.com/gimportexportdevs/gimporter/commit/278510482a678a5787263cf107ce8f8a02ace532))
* fit the start view to every screen and run on API 2.x devices again ([505d5a9](https://github.com/gimportexportdevs/gimporter/commit/505d5a97bb68bbf2d093f2e8a51316f6c446b23d))
* leave the app only once when tracks are pushed in quick succession ([da36f1d](https://github.com/gimportexportdevs/gimporter/commit/da36f1d9e2d7e8ee2a97fb3aa74bef87d7dc5301))
* return to the start view after backing out of the activity prompt ([d65b2a1](https://github.com/gimportexportdevs/gimporter/commit/d65b2a19cafbf208bd504c9221bb969a9b4092a6))
* send the port request through the outbox ([b84fc8a](https://github.com/gimportexportdevs/gimporter/commit/b84fc8ac5078ea1249f6fd5f336dfda2be07237d))

## [7.3.0](https://github.com/gimportexportdevs/gimporter/compare/v7.2.0...v7.3.0) (2026-09-21)


### Features

* support the fēnix 9 family (7 devices) ([2453097](https://github.com/gimportexportdevs/gimporter/commit/245309773c50952115d557e2be3c59ce9a22fb8c))
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
