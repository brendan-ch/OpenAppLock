# OpenAppLock

OpenAppLock is a free, open source app blocker for iOS using Apple's Family Controls API. At this time, it has been created primarily with Claude Code.

Join the [TestFlight](https://testflight.apple.com/join/5ymbrmns) beta! The App Store link will come...soon.

## Features

- Create app blocking rules
	- **Schedule**: block apps on a schedule
	- **Time limit**: block apps after using them for a set period of time
	- **Open limit**: block apps after opening them a number of times
- Define custom app lists to use with any of these rules
- Hard mode
	- If this is on, the rule cannot be disabled while it is active
- Uninstall protection
	- Prevent app uninstallation to work around hard mode, if hard mode is on

## Building

You need Xcode 26+ and an iOS 26 simulator to build and run the tests. To see the app blocking in action, you'll need a real device.

You'll need to follow some steps to use your own development team/certificate/provisioning profile after cloning.

1. Clone the repository. Do *not* open it in Xcode yet.
2. Create a folder titled `SharedXcodeSettings` *next to the cloned repository*. Then, create a file `DeveloperSettings.xcconfig` in that folder. The structure should look like this:

```
directory/
  SharedXcodeSettings/
    DeveloperSettings.xcconfig
  OpenAppLock/    # the cloned repository
    OpenAppLock.xcodeproj
```

3. In that folder, create a file `DeveloperSettings.xcconfig` and include the following line:

```
DEVELOPMENT_TEAM = <the team ID of your Apple Developer account>
```

4. Open the project in Xcode

This setup was stolen from [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire/blob/main/README.md#building); go check them out!

By default, the app will attempt to read this file, falling back to an empty development team if the file doesn't exist. This will work for simulator testing, but not for real device testing.

Note that Xcode may also try to automatically write a development team to the `xcodeproj` file if it can't detect one. If it does this, you may need to undo that change through Git and follow the approach listed above. Note that **PRs containing hardcoded development team IDs will not be accepted**.

There's probably a better way to handle this. Please reach out using my email below, or post on the [Discussions](https://github.com/brendan-ch/OpenAppLock/discussions) section, if you have suggestions.

## Contributing

If you're encountering a bug, please open an [issue](https://github.com/brendan-ch/OpenAppLock/issues) and I will look into it! For feature ideas, please raise them in the [Discussions](https://github.com/brendan-ch/OpenAppLock/discussions) section first. Because I'm still heavily developing the app, I may not accommodate all feature requests.

My email is `me [at] bchen.dev` if you have any questions!

