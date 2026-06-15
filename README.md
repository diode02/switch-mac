# SwitchMac

A macOS menu bar app to share a Magic Keyboard between multiple Macs — no physical button press needed.

## Tested on

| Hardware | Details |
|---|---|
| MacBook Air (Apple Silicon) | M-series chip |
| MacBook Pro (Apple Silicon) | M-series chip |
| Magic Keyboard with Touch ID | Lightning connector |

## How it works

SwitchMac runs on each Mac independently. Moving the keyboard is a two-step process:

1. **Release** on the Mac that currently has it — fully unpairs/forgets the keyboard so it's free.
2. **Connect** on the Mac you want to use it on — reconnects instantly.

No networking, no server, no coordination between Macs. Each action is local-only.

---

## Prerequisites

The Magic Keyboard pairs with **one Mac at a time**. SwitchMac automates the unpair/re-pair cycle so you don't have to dig into System Settings each time.

Make sure `blueutil` is installed on each Mac before first use (see below).

### `blueutil` (required)

SwitchMac uses `blueutil` to manage Bluetooth connections. Install it once on each Mac:

```bash
brew install blueutil
```

---

## Build & Install

```bash
cd /path/to/switch-mac
./build.sh
```

This produces `SwitchMac.app` in the same folder.

- Drag it to `/Applications` on each Mac.
- Add it to **Login Items** (System Settings → General → Login Items) so it starts automatically.

---

## Setup

1. Launch SwitchMac — a **⌨** icon appears in the menu bar.
2. Click it → **Configure keyboard first…**
3. Select your Magic Keyboard from the list, or type its MAC address manually.
4. Repeat on each Mac.

---

## Switching the keyboard

**To move the keyboard from Mac A → Mac B:**

**On Mac A** (the one that currently has the keyboard):
> Click **⌨** → **1️⃣ Release keyboard from this Mac**

The keyboard is unpaired from Mac A and is now free.

**On Mac B** (the one you want it on):
> Click **⌨** → **2️⃣ Connect keyboard to this Mac**

Mac B reconnects to the keyboard instantly.

**To go back:** repeat the two steps in reverse.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Release" does nothing | Make sure `blueutil` is installed (`brew install blueutil`). |
| "Connect" fails | The keyboard must still be paired with that Mac. If you released it too many times, re-pair manually via System Settings → Bluetooth. |
| App won't open (Gatekeeper) | Right-click → Open, or run `xattr -dr com.apple.quarantine SwitchMac.app`. |
| No keyboards listed | The keyboard must be paired first via System Settings → Bluetooth, then re-open "Configure keyboard". |

---

## Architecture

```
SwitchMac/
├── Sources/SwitchMac/
│   ├── main.swift              # Entry point (NSApplication)
│   ├── AppDelegate.swift       # Menu bar UI + actions
│   └── BluetoothManager.swift  # blueutil + IOBluetooth wrapper
├── Info.plist                  # App metadata & permissions
├── Package.swift               # Swift Package Manager
└── build.sh                    # Build → .app bundle
```

---

## Permissions

macOS will ask for:
- **Bluetooth** — to query paired/connected state via IOBluetooth.
