# Screen Time Access Required Overlay — Design Spec

Status: **planned** · Branch: `feat/screen-time-permission-revoked-overlay`

## Goal

Today, if a user completes onboarding (granting Screen Time / FamilyControls
access) and later revokes that access from the system Settings app, the app
does nothing to reflect it: `RootView` gates only on `hasCompletedOnboarding`
(an `@AppStorage` bool that never reverts), so `MainView` keeps rendering as
if everything still works. In reality, without authorization, rules can no
longer be enforced — `RuleEnforcer`/`RuleScheduler` silently no-op against
FamilyControls/DeviceActivity APIs they no longer have permission to call.

Add a full-screen block that appears whenever the app is onboarded but Screen
Time access is not currently approved, explaining why the app can't function
and linking directly to the system Settings page to re-enable it.

## Where the gate lives

`RootView` (`OpenAppLock/Views/RootView.swift`) already:
- Gates on `hasCompletedOnboarding` to choose between `OnboardingView` and
  `MainView`.
- Refreshes `ScreenTimeAuthorization.status` on every `scenePhase == .active`
  transition (comment: "so permission changes made in the system Settings
  app ... are reflected everywhere").
- Gets a synchronously-current status at cold launch too, since
  `ScreenTimeAuthorization.init` reads `provider.currentStatus` immediately.

So detection is already fully wired — the only gap is that nothing reads
`authorization.status` once onboarding is complete. Extend `RootView`'s
branch to three destinations instead of two.

**Why not gate inside `MainView` instead:** `MainView` already spins up a
SwiftData `@Query`, the `RuleEnforcer` environment, and a 30s enforcement
loop the moment its body runs. None of that should activate when Screen Time
access is missing, and `RootView` already owns "is the app usable" gating —
extending it is the smaller, more correct change.

## New pure decision logic

Following this project's `Logic/` pattern (pure, heavily unit-tested state
derivation — see `RuleStatus`, `RulePolicy`):

```swift
// OpenAppLock/Logic/RootDestination.swift
enum RootDestination: Equatable {
    case onboarding
    case screenTimeAccessRequired
    case main

    static func resolve(
        hasCompletedOnboarding: Bool,
        authorizationStatus: ScreenTimeAuthorizationStatus
    ) -> RootDestination {
        guard hasCompletedOnboarding else { return .onboarding }
        return authorizationStatus == .approved ? .main : .screenTimeAccessRequired
    }
}
```

`RootView.body` becomes a `switch RootDestination.resolve(hasCompletedOnboarding:authorizationStatus:)`.
Both `.notDetermined` and `.denied` map to `.screenTimeAccessRequired` — from
the user's perspective both mean "the app can't work right now," and the only
fix in either case is the same Settings visit.

## New view: `ScreenTimeAccessRequiredView`

`OpenAppLock/Views/ScreenTimeAccessRequiredView.swift` — full-screen block,
visually consistent with `OnboardingView`'s permission step
(`OnboardingView.swift:64-93`):

- An icon (reuse the `"hourglass"` SF Symbol from onboarding's permission
  step, or a lock-style symbol — implementer's call, staying consistent with
  onboarding's visual language).
- Title + short explanation that Screen Time access was turned off and the
  app can't block anything without it.
- A single primary button, "Open Settings", using
  `UIApplication.openSettingsURLString` via `openURL` — the same mechanism
  `OnboardingView`'s `openSettingsButton` already uses.
- Accessibility identifier on the view container and the button — use a
  distinct identifier (e.g. `screenTimeAccessRequiredView`,
  `screenTimeAccessRequiredOpenSettingsButton`) rather than reusing
  onboarding's `openSettingsButton`, so UI tests can address this screen
  unambiguously even though the two screens never appear simultaneously.
- No in-app re-request/"Allow Screen Time" button: access was already
  granted once and revoked, so `requestAuthorization()` is not guaranteed to
  re-surface the system prompt. Settings is the only reliable path back.
- No manual "Check Again" button: `RootView`'s existing scenePhase-driven
  refresh already re-evaluates on every foreground, which covers the only
  realistic path back (Settings always backgrounds the app first).

New copy keys in `Shared/Copy/CopyKey.swift` / `Shared/Copy.xcstrings`
(exact key names at implementer's discretion, following existing
`onboarding*` naming conventions), e.g.:
- Title: "Screen Time Access Needed"
- Description: "OpenAppLock can't block anything without Screen Time access. Turn it back on in Settings to keep your rules working."
- Button: "Open Settings" (may reuse existing `onboardingOpenSettingsButton` copy value, new accessibility identifier as above)

## Diagnostic logging

Log the transition once, matching the existing lifecycle logging style in
`MainView`/`RootView` (e.g. `Diag.log(.lifecycle, "screen time authorization not approved — showing access-required overlay")`), so on-device log exports capture when the block screen was shown without needing extra state tracking.

## Testing

1. **Unit tests** (Swift Testing, `OpenAppLockTests/RootDestinationTests.swift`):
   parameterized over all 6 `(hasCompletedOnboarding, authorizationStatus)`
   combinations, asserting the resolved `RootDestination`.
2. **UI test**: `LaunchConfiguration` currently has no way to simulate
   "onboarding completed, but authorization not approved" —
   `OpenAppLockApp.swift:80-84` forces `.approved` mock status whenever
   `onboardingCompleted != false`. Add a new launch flag (e.g.
   `-screen-time-access-revoked`) that seeds
   `MockAuthorizationProvider(status: .denied)` even with onboarding
   completed. Add a UI test asserting `ScreenTimeAccessRequiredView`'s
   elements appear and `MainView` elements (e.g. `newRuleButton`) do not.
3. **Manual on-device/simulator validation**: launch with onboarding
   completed, toggle Screen Time access off in Settings, foreground the app,
   confirm the overlay appears; confirm "Open Settings" opens the correct
   Settings page.

## Explicitly out of scope

- Changing `RuleEnforcer`/`RuleScheduler` to skip work when unauthorized —
  they already silently no-op without a visible error; that's a separate,
  pre-existing gap this feature doesn't touch.
- An in-app "Allow Screen Time" retry button.
- Persisting or logging permission-loss history beyond the single
  `Diag.log` line at the transition.
