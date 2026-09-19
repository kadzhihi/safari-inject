# IOSControl Safari HTTP Bridge v0.2.0

This build changes the runtime architecture specifically to avoid doing heavy work during MobileSafari's tweak constructor.

## Runtime architecture

1. `IOSControlSafariBootstrap.dylib` is the only dylib automatically injected into MobileSafari.
2. Its constructor does no UIKit/WebKit work. It waits 1.5 seconds on Safari's main queue.
3. It writes a runtime state to the pasteboard, then manually `dlopen()`s `IOSControlSafariPayload.dylib` with `RTLD_NOW`.
4. Any real dyld error is exposed as `IOSCONTROL_SAFARI_PAYLOAD_DLOPEN_FAIL|error=...`.
5. The bootstrap resolves `ICHTPayloadStart` with `dlsym()` and starts the payload explicitly.
6. The payload starts the localhost HTTP listener and reports exact socket/bind/listen status back through the same runtime channel.
7. Only after `/ping` succeeds should `/status`, `/eval`, `/scan`, and `/fill` be tested.

This removes constructor-time filesystem markers and constructor-time WebKit/server startup from the automatic injection path.

## Build

The GitHub workflow builds both `arm64` and `arm64e` for standard Dopamine rootless and packages both dylibs.

## Install / test

Install the generated `.deb`, fully terminate MobileSafari, then run `ioscontrol_safari_test.lua` in IOSControl.

The important runtime values are self-explanatory:

- `IOSCONTROL_SAFARI_BOOTSTRAP_LOADED...`
- `IOSCONTROL_SAFARI_PAYLOAD_DLOPEN_FAIL|error=...`
- `IOSCONTROL_SAFARI_PAYLOAD_DLSYM_FAIL|error=...`
- `IOSCONTROL_SAFARI_HTTP_SOCKET_FAIL|...`
- `IOSCONTROL_SAFARI_HTTP_BIND_FAIL|...`
- `IOSCONTROL_SAFARI_HTTP_LISTEN_FAIL|...`
- `IOSCONTROL_SAFARI_HTTP_LISTENING|127.0.0.1:17891`

If `HTTP_LISTENING` appears, the same test continues automatically into real Safari page discovery and JavaScript evaluation.
