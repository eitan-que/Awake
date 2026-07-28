# Awake

Keep a Mac from sleeping, from the menu bar or the command line.

macOS can be told to ignore every sleep trigger, including closing the lid, by
setting `disablesleep` through `pmset`. That needs root, it is easy to forget
you left it on, and the setting is invisible once it is set. Awake makes it one
click or one word, and puts a mug in the menu bar so you can always see the
answer.

```
awake on      # do not sleep, even with the lid closed
awake off     # back to normal
awake         # report the current setting
```

The menu bar shows an outline mug when sleep is normal and a filled mug while
the Mac is being held awake.

## Install

Requires macOS 13 or newer and the Xcode command line tools.

```sh
git clone https://github.com/eitan-que/Awake.git
cd Awake
sudo make install
```

That builds the app, installs it to `/Applications`, links `awake` into
`/usr/local/bin`, registers the privileged helper, and starts the menu bar app
at login for every user.

To remove everything, including the helper, and restore normal sleep:

```sh
sudo make uninstall
```

## How it works

Three executables and a small shared library:

| Component | Runs as | Job |
| --- | --- | --- |
| `Awake` | you | Menu bar item, and one-time helper installation |
| `awake` | you | CLI front end |
| `awake-helper` | root | The only thing that calls `pmset` |
| `AwakeCore` | — | Shared channels, paths and state reading |

Nothing but the helper is privileged. The app and the CLI ask for a change by
posting a [`notify(3)`](https://developer.apple.com/documentation/darwin/notify_post)
event; the helper performs it and posts back that the state moved.

### Why the password is asked once

The helper is a LaunchDaemon. `sudo make install` puts it in place while it
already has root, so a source install never prompts separately, and the daemon
survives reboots. A prebuilt `Awake.app` dragged into `/Applications` instead
asks for authorization the first time it launches, installs the same daemon, and
never asks again.

### Cost

Idle, Awake costs nothing: every component is blocked waiting for an event.
Toggles are pushed, not polled. The menu bar keeps one backstop timer at 60
seconds with 15 seconds of tolerance, to catch changes made by something other
than Awake and to let the OS coalesce that wakeup with others. Each check is a
single `pmset -g`, roughly 0.3 ms of CPU.

### Security

The notify channels are global to the machine and unauthenticated: any process
running on it can post `com.awake.on`. What that grants is exactly one thing --
toggling `disablesleep` -- because the events carry no payload and the helper
runs `pmset` with hardcoded arguments. That is the same capability as a
passwordless sudoers rule scoped to those two commands, which is the usual way
people solve this. It is not broader, but it is worth knowing it is not narrower
either.

`sudo make uninstall` removes the daemon completely.

## Development

```sh
swift build              # all four executables
make bundle              # assemble build/Awake.app without installing
make clean
```

The app icon is generated, not committed: `Tools/MakeIcon` renders it from the
same `mug.fill` symbol the menu bar uses, so the two cannot drift apart.

Builds are signed ad-hoc, which is enough to run locally. Distributing a build
that opens without a Gatekeeper warning needs a Developer ID signature.

### Layout

```
Sources/AwakeCore     shared channels, paths, state reading
Sources/AwakeApp      menu bar app and helper installer
Sources/AwakeCLI      the awake command
Sources/AwakeHelper   privileged daemon
Tools/MakeIcon        icon generator (build time only)
Resources             Info.plist, LaunchAgent plist
```

Target names avoid case-only differences on purpose. macOS filesystems are
case-insensitive by default, so `Awake` and `awake` cannot coexist in one
directory -- which is also why the CLI ships in `Contents/Helpers` rather than
beside the app binary in `Contents/MacOS`.

## License

MIT. See [LICENSE](LICENSE).
