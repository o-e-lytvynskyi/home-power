# HomePower

A menu bar app for a Marstek Venus E home battery. It shows the charge, what
the battery is doing and the time left, read from the station's Local API on
the home network. No cloud account, no Home Assistant.

The station itself is described in the [field reference](../README.md).

## What it shows

The menu bar shows the percentage next to a battery glyph filled to the
charge:

| Glyph | Meaning |
|---|---|
| filled outline | discharging or idle; fill = charge |
| bolt over the fill | charging |
| red fill | 20 % or less |
| dashed, empty outline | no live reading: searching, no reply, or blocked by macOS |

The menu opens with either click. Its header has:
- the charge and the energy left (`2.21 of 5.12 kWh`);
- the state with battery power, and the time to the cutoff or to full;
- the BACKUP socket load, the grid port (drawing / feeding), battery
  temperature, mode, Wi-Fi signal, model and firmware.

Problem states show what to do instead: turn on Local API, allow Local
Network, check the address. The last good reading stays visible.

Battery power: firmware 148 and 150 don't report `bat_power`, so the app
works it out from the energy balance: grid port + BACKUP − PV. This was
checked on 2026-10-14 with the station unplugged: the result matched the fall
in `bat_capacity`. Whether a plugged-in station passes BACKUP straight
through from the grid (bypass) has not been checked yet. In that case the
balance would read as discharging while the battery is idle. Grid on/off
detection is not built yet; see `GridState` in `StationReading.swift`.

## Notifications

While the battery discharges, a notification arrives each time the charge
passes another 10 %: 90, 80 … 10. Each one says the average draw over the
last hour and how long the station lasts at that rate, down to the cutoff:

> **Home battery 90%**
> Average draw over the last hour: 157 W. About 25 h 30 min left at this rate.

The level depends on the charge:

| Charge | Title | Sound | Picture |
|---|---|---|---|
| 50 % and up | Home battery 90% | none | green battery |
| below 50 % | Home battery down to 40% | yes | orange battery with "!" |
| 20 % and below | Home battery low: 20% | yes | red battery with "!" |

How the steps behave:
- the last step is remembered across launches;
- a drop over several steps (the Mac slept) notifies once, at the current charge;
- charging 5 % above the last step re-arms the steps below it;
- a drop while the battery is idle moves the mark silently;
- each notification replaces the previous one in Notification Centre.

The average comes from the History model, so gaps count too. With less than
15 min of readings in the hour, the current draw stands in. While the screen
is locked, notifications wait for the unlock.

Notifications are on by default. They can be turned off in Settings. If
macOS has them denied, the menu offers **Turn On Notifications…**.

**Focus mutes them.** An active Focus delays every notification, these
included; look for `interruptionSuppression: delay delivery` in the
`usernoted` log. Add HomePower to the Focus's allowed apps. Time-sensitive
delivery would get through Focus, but it needs an entitlement that an ad-hoc
signed app can't have.

## History

**History…** (⌘Y in the menu) opens a window with the last 6 h, 24 h, 7 d
or 30 d:
- **totals:** energy charged and discharged in the period, how much of each
  is approximated, and the share of time filled in;
- **Charge:** state of charge over time;
- **Battery power:** charging below zero (blue), discharging above (orange);
- **by-day table:** charged, discharged and approximated share per day, so
  every value is readable without hovering.

Hovering either chart puts a crosshair on both and shows that moment's
values above them. Approximated stretches are dashed, with a fainter fill.

Every good poll is appended to
`~/Library/Application Support/HomePower/history.csv`
(`epoch,soc,wh,batteryW,backupW,gridW`, ~100 KB a day). It is kept for
30 days. A failed poll writes nothing. Torn or out-of-order lines are dropped
on load.

**Gaps.** Readings more than 2.5 min apart mean the app was not running, the
Mac slept or the station didn't answer. Such a gap is approximated:
- up to 15 min, charge and power are drawn straight across;
- longer, charge is drawn straight across, and power is held at the average
  that explains the change in stored energy (`bat_capacity`, else charge ×
  capacity). The energy totals stay right, but anything the battery did
  inside the gap nets out: charging and discharging during it show as their
  difference.

Nothing is drawn before the first reading or after the last one. Between
two readings power is linear, so a change that happened between polls is
spread across those 30 s.

## Data source

Marstek Open API Rev 3.1: JSON-RPC over UDP, port 30000. Local API must be
turned on in the Marstek app (Settings → Local API). It is off by default,
and firmware resets can turn it off again.

Each poll, every 30 s, sends `ES.GetStatus`, `Bat.GetStatus` and
`ES.GetMode`. `Wifi.GetStatus` and `Marstek.GetDevice` are added every 10th
poll. Timing rules come from the firmware:
- after a reply the station ignores requests for ~2 s, from any client, so
  calls are spaced 2 s from the last reply;
- over Wi-Fi requests get lost, so each call is resent at 0.5, 2.5 and 5 s
  with the same id.

The socket uses an ephemeral port: the Venus E 3.0 on firmware 148 answers
it, so port 30000 stays free for other clients. Note that every client shares
the station's quiet window. Another poller (Home Assistant, a script) slows
both down.

With no address set, the app finds the station by a directed broadcast on
each physical interface. Wi-Fi delivers broadcasts unreliably, so the
broadcast is resent for up to 8 s. The address and the station's Bluetooth
MAC are then saved. If the station stops answering, the app broadcasts every
5 min and follows the same MAC to its new address.

## Settings

- **Station address:** an IP, optionally `:port`. Empty means find it
  automatically. **Find** broadcasts now. The field applies on Return.
- **Station stops discharging at:** the cutoff used for the time-left
  estimate. The API can set the DoD but not read it back. DoD 88 % in the
  Marstek app means 12 %.
- **Launch at login:** uses `SMAppService`.

## Permissions

macOS asks for **Local Network** access on the first poll. Until it is
allowed, the menu says so and offers the settings pane.

The app is ad-hoc signed, so macOS treats every reinstall as a new app.
After `./install.sh`, Local Network access is asked for again.

## Build and install

```sh
./install.sh          # build, install to /Applications, launch
./install.sh --dev    # keep .build/ for fast rebuilds
./uninstall.sh        # stop, remove, forget settings (--clean drops .build/)
```

The build uses SwiftPM against the macOS 26 SDK. Nothing is left in the tree
after `install.sh`.

## Debug flags

| Flag | What it does |
|---|---|
| `--selftest` | built-in checks: parsing, firmware quirks, estimates, every state |
| `--selftest file.json` | parses `{"ES.GetStatus": {…result…}, …}` and prints the menu text |
| `--probe [host=ip[:port]] [cutoff=N]` | one live poll: every method with its time, then the menu text |
| `--discover [seconds=N]` | every station that answers a broadcast |
| `--history [range=6h\|24h\|7d\|30d] [demo] [file=…]` | what the History window shows, as text: totals, every filled gap and how, the day table |
| `--render [dir]` | menu header (light/dark), menu bar face for every demo state, and the History window (24 h, 7 d, with and without a crosshair), as PNGs. The period picker and the day table are AppKit controls that `ImageRenderer` can't draw — check those on `--demo history` |
| `--demo [state=…] [menu\|about\|history]` | synthetic reading and a week of history with gaps, no network; opens Settings, the menu, About or History |
| `--notify [soc=40] [draw=157] [cutoff=12]` | posts the notification the app would post at that charge and prints it. Run via LaunchServices so the app's permission applies: `open -n -W --stdout /tmp/out.txt /Applications/HomePower.app --args --notify soc=40` |
| `--login-item [on\|off]` | reads or changes the login item |

Demo states: `discharging`, `charging`, `idle`, `low`, `offline`,
`blocked`, `searching`.

`--probe` and `--discover` run under the terminal's Local Network
permission, not the app's.

Logs: `/usr/bin/log show --predicate 'subsystem == "dev.local.home-power"'`.
The app logs at `.notice` when the station goes silent, answers again, or is
found at a new address.
