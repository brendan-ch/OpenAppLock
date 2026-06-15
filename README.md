# OpenAppLock

OpenAppLock is an open-source iOS Screen Time app. You define recurring
**rules** that block selected apps — by schedule window, daily time limit, or
number of opens — with an optional **Hard Mode** that makes an active block
impossible to lift, edit, or delete until its window ends. The interface is
intentionally plain, native iOS (List/Form/NavigationStack).

It is built on Apple's Screen Time APIs — FamilyControls, ManagedSettings, and
DeviceActivity — so blocking is enforced by the system, not by a VPN or DNS
shim.

## Requirements

- Xcode 26+ and an iOS 26 simulator (to build and run the tests).
- An Apple Developer account is only needed to run on a physical device; real
  app-blocking and usage tracking are observable on-device, not in the
  simulator.

## Getting started

```sh
git clone git@github.com:brendan-ch/OpenAppLock.git
cd OpenAppLock
open OpenAppLock.xcodeproj
```

Pick an **iOS Simulator** destination and build. No code signing is required
for simulator builds or tests. To run on a device, see the signing and
identifier steps in [CONTRIBUTING.md](CONTRIBUTING.md).

## Project layout

| Path | What |
|---|---|
| `OpenAppLock/` | App target (SwiftUI + SwiftData): models, pure logic, services, views |
| `Shared/` | Code compiled into the app and all three extensions |
| `OpenAppLockMonitor/` | DeviceActivityMonitor extension (limits, resets, session expiry) |
| `OpenAppLockShieldConfig/` | ShieldConfiguration extension (shield UI) |
| `OpenAppLockShieldAction/` | ShieldAction extension (Open button handling) |
| `Config/` | Build configuration (`.xcconfig`) — see CONTRIBUTING.md |
| `Docs/` | Feature spec and Swift guidelines |

Deeper architecture notes live in [AGENTS.md](AGENTS.md); feature behavior is
specified in [Docs/AGENT_RULES_FEATURE_SPEC.md](Docs/AGENT_RULES_FEATURE_SPEC.md).

## Contributing

Changes land on `main` only through reviewed pull requests. Branch with a
`feat/`, `fix/`, or `chore/` prefix and open a PR — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

## License

[MIT](LICENSE) © 2026 Brendan Chen
