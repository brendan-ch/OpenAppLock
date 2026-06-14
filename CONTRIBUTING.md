# Contributing to OpenAppLock

Thanks for your interest in OpenAppLock. This guide covers local setup, the
code-signing convention, and the branch/PR workflow.

## Prerequisites

- Xcode 26 or newer (the project targets **iOS 26**).
- An iOS 26 **simulator** runtime. Building and running the test suites needs
  nothing else — no Apple Developer account and no code signing.

## Code-signing setup (one time)

Signing identity is developer-specific, so the project keeps it **outside** the
repository instead of committing a Team ID. The checked-in
[`Config/Shared.xcconfig`](Config/Shared.xcconfig) optionally includes a file
that lives one directory **above** your clone:

```
Developer/
├── OpenAppLock/                          <- your clone
└── SharedXcodeSettings/
    └── DeveloperSettings.xcconfig        <- your settings, never committed
```

Because the include is optional (`#include?`), the project opens and builds for
the simulator even when that file is absent. You only need it to produce a
**signed** build or to run on a **device**:

```sh
# from the repo root
mkdir -p ../SharedXcodeSettings
cp Config/DeveloperSettings.sample.xcconfig \
   ../SharedXcodeSettings/DeveloperSettings.xcconfig
# then edit it and set DEVELOPMENT_TEAM to your 10-character Apple Team ID
```

Find your Team ID at <https://developer.apple.com/account> → *Membership
details*.

### Running on your own device

The app and its three Screen Time extensions are registered under the
maintainer's identifiers — the `dev.bchen.OpenAppLock` bundle-ID prefix and the
`group.dev.bchen.OpenAppLock` App Group — which belong to the maintainer's
team. To run on a device under your own account you must also change those to
your own:

- `PRODUCT_BUNDLE_IDENTIFIER` for each target (app + `.Monitor`,
  `.ShieldConfig`, `.ShieldAction`),
- the App Group string in `Shared/AppGroup.swift` and in the four
  `*.entitlements` files,
- and request the **Family Controls** capability for your bundle IDs.

This is only needed for on-device runs; simulator builds and tests are
unaffected.

## Building & testing

Open `OpenAppLock.xcodeproj` in Xcode, pick an **iOS Simulator** destination
(a device destination makes test runs hang), and build/test as usual.

For headless/CI runs, [`Config/CI.xcconfig`](Config/CI.xcconfig) disables code
signing entirely:

```sh
xcodebuild test \
  -project OpenAppLock.xcodeproj \
  -scheme OpenAppLock \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -xcconfig Config/CI.xcconfig
```

Follow red-green TDD: for any behavior change, update
[`docs/RULES_FEATURE_SPEC.md`](docs/RULES_FEATURE_SPEC.md) first, write the
failing test, then implement. See [`AGENTS.md`](AGENTS.md) and
`docs/SWIFT_GUIDELINES.md` for the project's coding and testing standards.

## Branch & PR workflow

`main` advances only through reviewed pull requests — please don't push feature
or fix work to it directly.

1. Branch from `main` using a conventional prefix: `feat/…`, `fix/…`, or
   `chore/…`.
2. Make your change with tests; keep commits in
   [Conventional Commits](https://www.conventionalcommits.org/) form
   (`feat:`, `fix:`, `refactor:`, …).
3. Push the branch and open a PR for review.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
