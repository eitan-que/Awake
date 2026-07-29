# Awake

Keep a Mac from sleeping, from the menu bar or the command line.

macOS can be told to ignore every sleep trigger, including closing the lid, by
setting `disablesleep` through `pmset`. That needs root, it is easy to forget
you left it on, and the setting is invisible once it is set. Awake makes it one
click or one word, and puts a mug in the menu bar so you can always see the
answer.

Run `awake` with no arguments and it tells you where things stand:

```
  Awake  keep this Mac from sleeping

  Status   OFF this Mac sleeps normally

  awake on       disable sleep, even with the lid closed
  awake off      restore normal sleep
  awake status   print just the status line
  awake help     show this
```

The menu bar shows an outline mug when sleep is normal and a filled mug while
the Mac is being held awake.

## Install

Requires macOS 13 or newer. Both routes install the same thing, but **building
from source is the one to use**: it skips Gatekeeper entirely, and it lets you
sign with your own certificate, which is what keeps macOS from listing Awake as
an unidentified developer. The disk image is there for machines without a
toolchain.

### From source, signed with your own certificate

Needs the Xcode command line tools.

```sh
git clone https://github.com/eitan-que/Awake.git
cd Awake
sudo make install CODESIGN_ID="Apple Development: you@example.com (XXXXXXXXXX)"
```

Get that identity once, free, with an ordinary Apple ID: in Xcode, **Settings >
Accounts**, add your Apple ID, then **Manage Certificates > + > Apple
Development**. `security find-identity -v -p codesigning` then prints the name to
paste above. [Signing](#signing) explains what it buys and how to fix the one
thing that commonly goes wrong.

Leaving `CODESIGN_ID` out also works -- the build is then signed ad-hoc, and
Awake runs exactly the same. Only its presentation in System Settings suffers.

Either way, that builds the app, installs it to `/Applications`, links `awake`
into `/usr/local/bin`, registers the privileged helper, and starts the menu bar
app at login for every user.

To remove everything, including the helper, and restore normal sleep:

```sh
sudo make uninstall
```

### From the disk image

[Releases](https://github.com/eitan-que/Awake/releases) carries a `.dmg`
holding the app on its own. Open it, drag Awake to Applications, and launch it
from there; it asks for your password once and installs the same things
`sudo make install` does -- the helper, the `awake` command and the login agent.

It has to be dragged out first. Everything Awake installs names
`/Applications/Awake.app`, so opening it from inside the disk image would point
a root daemon at a bundle about to be unmounted; the app says so and stops
rather than doing it.

The build is signed ad-hoc rather than with a Developer ID, so macOS will refuse
to open it on the first try. To let it through, open **System Settings > Privacy
& Security**, scroll to the message naming Awake, click **Open Anyway**, and
confirm with your admin password. Since macOS 15 this is the only way in --
Control-clicking the app no longer skips the check.

For the same reason, **System Settings > General > Login Items & Extensions**
will show Awake as two separate rows reading *Item from unidentified developer*,
without an icon. Nothing is wrong; a signature with no Team ID cannot be
attributed to the app. Building from source with your own certificate is what
turns those two rows into one named "Awake" -- see [Signing](#signing).

### Signing

Awake installs two launchd jobs -- the menu bar agent and the privileged daemon
-- and both plists carry `AssociatedBundleIdentifiers`, the key that folds them
into a single "Awake" row in Login Items & Extensions. macOS honours that key
only when the signed program has a Team ID, and an **ad-hoc signature has none**,
so an unsigned build gets two anonymous rows instead, each reading *Item from
unidentified developer*, neither with an icon.

Any real certificate supplies a Team ID, including the free kind described
above. Signed that way, Login Items shows one "Awake" entry with the app icon
and two items, one of them system-wide -- that one is the daemon.

A paid Developer ID buys one further thing, and only one: letting *other* people
open a build you hand them without going through Gatekeeper by hand. It makes no
difference to the machine you built on.

If `find-identity` reports the certificate but not as a *valid* identity
(`CSSMERR_TP_NOT_TRUSTED`), the chain cannot be built: macOS ships an
intermediate that expired in February 2023, and current certificates are issued
by the G3 one. Install it from
[Apple's certificate authority page](https://www.apple.com/certificateauthority/)
(`AppleWWDRCAG3.cer`) and check again.

## How it works

**One executable, three modes.** The menu bar app, the `awake` command and the
privileged daemon are the same binary invoked differently:

| Invocation | Runs as | Mode |
| --- | --- | --- |
| `Awake.app` (or `--menubar`) | you | Menu bar item |
| `awake …` | you | Command line |
| `--helper` | root | The only thing that calls `pmset` |
| `--install-daemon` | root | One-shot helper registration |

With no arguments it picks by context: a terminal gets the status overview, a
Finder launch gets the menu bar app.

Nothing is copied at install time. The LaunchDaemon runs the app's own binary in
place, and `/usr/local/bin/awake` is a symlink to it, so there is exactly one
executable on disk and no way for two copies to drift apart.

Nothing but the helper is privileged. The app and the CLI *ask* for a change by
posting a [`notify(3)`](https://developer.apple.com/documentation/darwin/notify_post)
event; the helper performs it.

### Staying in sync

The helper is the single writer of the current state, and it publishes into
notify's own 64-bit state slot on `com.awake.changed`. Two rules make everything
agree:

- **It waits before publishing.** `pmset -g` can still report the old value for
  a moment after a write. Announcing as soon as `pmset` returns is what made the
  menu bar trail the CLI: observers woke, sampled a setting mid-flight, and
  showed a stale answer. The helper confirms the change is observable first.
- **Nobody else re-reads.** Observers take the published value rather than
  running their own `pmset`, so there is one answer, not three that can race.

Changes made by something *other* than Awake -- a direct `sudo pmset` call --
are caught by a 60 second drift check in the helper, which republishes and
announces if reality has moved. That is the only path with a delay, and it is
the only path where Awake is not the one making the change.

### Why the password is asked once

The helper is a LaunchDaemon. `sudo make install` registers it while it already
has root, so a source install never prompts separately, and the daemon survives
reboots. A prebuilt `Awake.app` dragged into `/Applications` instead asks for
authorization the first time it launches, registers the same daemon, and never
asks again.

### Cost

Idle, Awake costs nothing: every component is blocked waiting for an event.
Toggles are pushed, not polled, and reading the published state is a memory
lookup rather than a process spawn. The two `pmset` calls that remain are the
helper's drift check and the menu bar's backstop, both on 60 second timers with
15 seconds of tolerance so the OS can coalesce those wakeups with others. Each
costs roughly 0.3 ms of CPU.

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
swift build              # the executable
make bundle              # assemble build/Awake.app without installing
make clean
```

`make install` compiles as the invoking user and only the installation itself
runs as root, so `sudo make install` does not leave root-owned artifacts in
`.build/`.

The app icon is generated, not committed: `Tools/MakeIcon` renders it from the
same `mug.fill` symbol the menu bar uses, so the two cannot drift apart.

Builds are signed ad-hoc, which is enough to run locally. Distributing a build
that opens without a Gatekeeper warning needs a Developer ID signature.

### Layout

```
Sources/Awake/
  main.swift                  mode dispatch
  Channel.swift               notify channels and token wrapper
  SleepState.swift            published state and the pmset read
  CommandLineInterface.swift  the awake command
  MenuBarController.swift     menu bar item
  Helper.swift                privileged daemon
  HelperInstaller.swift       one-time registration
Tools/MakeIcon                icon generator (build time only)
Resources                     Info.plist, LaunchAgent plist
```

## License

MIT. See [LICENSE](LICENSE).
