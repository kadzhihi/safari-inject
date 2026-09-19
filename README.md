# IOSControl Safari HTTP

`IOSControlSafariHTTP` is a standard Dopamine rootless ElleKit tweak for iOS 16. It exposes a localhost-only bridge from IOSControl Lua 5.4 to the active, real MobileSafari page:

```text
IOSControl Lua -> http://127.0.0.1:17891 -> MobileSafari tweak -> active Safari page -> JavaScript result
```

It does not create a separate browser and does not use `javascript:` URLs, Web Inspector, usbmuxd, lockdownd, or RootHide.

## Supported environment

- iOS 16 on a standard Dopamine rootless jailbreak
- ElleKit (`/var/jb` rootless prefix)
- MobileSafari bundle `com.apple.mobilesafari`
- IOSControl Lua 5.4

The package architecture is `iphoneos-arm64`; the injected dylib is deliberately FAT with both `arm64` and `arm64e` slices.

## Build

Requirements: Theos with an iPhoneOS SDK capable of the configured `TARGET`, plus standard Debian packaging tools.

```sh
make clean package FINALPACKAGE=1
```

Check the finished package before installing:

```sh
dpkg-deb -f packages/*.deb Architecture
dpkg-deb -x packages/*.deb /tmp/ioscontrol-safari-package
lipo -archs /tmp/ioscontrol-safari-package/var/jb/usr/lib/TweakInject/IOSControlSafariHTTP.dylib
```

Expected architecture output is `iphoneos-arm64` for the package and both `arm64 arm64e` for the dylib. GitHub Actions performs the same checks and uploads only the final `.deb`.

## Install and test

1. Install the generated `.deb` with Sileo.
2. Force-close MobileSafari, then open it again. This is required for the new dylib to load.
3. Run [ioscontrol_safari_test.lua](ioscontrol_safari_test.lua) from IOSControl.

The constructor writes `ioscontrol_safari_loaded.txt` to MobileSafari’s dynamically resolved Caches directory and logs `[CTOR] loaded`. The test’s `/ping` check is the practical injection/bridge proof; use the constructor log and its printed marker path for marker troubleshooting.

Normal successful output ends with:

```text
[PASS] 01 injection-bridge
...
[PASS] 18 final-summary
===== SUMMARY =====
passed=18
failed=0
first_failed_stage=none
```

## Endpoints

- `GET /ping` — bridge/process information.
- `GET /status` — active-page discovery diagnostics, URL, and title.
- `POST /eval` — raw UTF-8 JavaScript source.
- `GET /scan` — `input`, `textarea`, `select`, and contenteditable elements.
- `POST /fill` — JSON `{"selector":"...","value":"..."}`. Inputs and textareas use their native prototype setter; select and contenteditable are also supported. Bubbling `input` and `change` events follow the update.

All UIKit/WebKit/Safari interaction is dispatched to the main queue. Socket I/O runs on a serial background queue and has bounded HTTP and JavaScript timeouts.

## Troubleshooting

- **Injection:** Force-close/reopen Safari. Look for `[CTOR] loaded` and `[HTTP] listen OK` in MobileSafari logs. The marker log reports its actual container-Caches location.
- **Ping:** If `/ping` cannot connect, the tweak was not injected or the listener could not bind. Inspect `[HTTP] socket`, `bind`, and `listen` diagnostics.
- **Page discovery:** `/status` returns `stage: "find-page"` with the number of visible objects/windows inspected. This Safari hierarchy path is **NOT RUNTIME VERIFIED** until tested on the target phone.
- **JavaScript:** `/eval` returns `stage: "javascript"` for syntax/runtime errors or a timeout.
- **DOM fill:** `/fill` returns `ELEMENT_NOT_FOUND`, `INVALID_SELECTOR`, or `UNSUPPORTED_ELEMENT` without focusing the target element.

## Security

The server binds only `127.0.0.1:17891`; it never listens on Wi-Fi, cellular, or all interfaces. Local processes able to reach that port can request JavaScript execution in Safari, so do not expose or proxy it.

## Runtime status

The source and GitHub workflow are statically reviewed. Actual tweak injection, Safari page discovery, and JavaScript execution are **NOT RUNTIME VERIFIED** until the supplied test is run on the stated iPhone.
