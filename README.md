# Bomb Interval Calculator (BIC)

A Lua mod for **Digital Combat Simulator (DCS)**, specifically for the
**F-4E Phantom II**. Calculates the release interval for unguided bombs
(e.g. Mk-82) based on true airspeed, target distance, and bomb count —
as part of pre-flight mission planning, without an external calculator.

---

## Purpose

When flying a carpet bombing run in DCS with the F-4E, the
**INTRVL knob** in the cockpit must be set to a release interval in
seconds. The correct value depends on three factors:

| Factor         | Unit         | Source in cockpit             |
|----------------|--------------|-------------------------------|
| True Airspeed  | Knots (kts)  | TAS indicator                 |
| Target distance| nm or ft     | Mission planning / maps       |
| Number of bombs| Count        | Aircraft loadout              |

In real operations these values were always calculated on the ground
before takeoff — reliable TAS and distance figures are not available
in the air, and historically pilots never computed this in flight.
BIC brings that pre-flight calculation into DCS via a small window
toggled by hotkey, so no external calculator is needed.

---

## Formula

The underlying calculation is the simple distance-time equation
distributed across `(n − 1)` intervals:

```
Δt = (d / v) × 3600 / (n − 1)
```

- `d` = target distance in **nautical miles** (nm)  
  (ft input is converted internally: `d_nm = d_ft / 6076.12`)
- `v` = true airspeed in **knots**
- `n` = number of bombs (minimum 2, otherwise division by zero)
- `Δt` = release interval in **seconds**

### Valid output range

`0.05 s` to `10.00 s` — these are the hardware limits of the F-4E's
INTRVL knob. The knob runs from 0.05 s to 1.00 s; a switch multiplies
the value by 10 (max. 10.00 s). Values outside this range are detected
by BIC and reported in the output field.

---

## The UI

The window (300 × 240 px) contains three input fields, one output field,
and two buttons:

```
┌─ Bomb Interval Calculator ───────────────────┐
│  True Airspeed (kts): [     ]                |
|                       200 - 750 kts          │
│  Distance:            [     ] [nm]           |
|                       0.1 - 2.0 nm           │
│  Number of Bombs:     [     ]                |
|                       2 - 24                 │
│                                              │
│  Interval (sec):      [          ]           │
│                                              │
│  [ Calculate ]        [ Close ]              │
└──────────────────────────────────────────────┘
```

- **Calculate** reads the inputs, validates them, and writes the result
  to the output field.
- **Close** hides the window (skin trick, see below).
- The unit button toggles between **nm** and **ft**; the range hint
  below the distance field updates accordingly.
- Visibility is toggled by hotkey: `Left Shift + Left Ctrl + B`

### Output field messages

| Message            | Meaning                                             |
|--------------------|-----------------------------------------------------|
| `0.05 – 10.00`     | Valid interval in seconds (2 decimal places)        |
| `Invalid input`    | At least one field is empty or out of range         |
| `Invalid interval` | Inputs are valid but result is outside 0.05 – 10.00s|

---

## The Skin Trick

DCS deactivates hotkey callbacks as soon as a dialog window is hidden
with `setVisible(false)`. The solution is borrowed from the
[ScratchPad project](https://github.com/rkusa/dcs-scratchpad):

1. On startup the window is created (`spawnDialogFromFile`)
2. `setSkin(cSkin.windowSkinChatMin())` switches to a
   **transparent chat-minimized skin**
3. All child elements are individually hidden via `findByName()` +
   `setVisible(false)`
4. The hotkey toggles between `windowSkin()` (visible) and
   `windowSkinChatMin()` (invisible)

This keeps the window object technically "alive" so hotkeys continue to
work throughout long missions.

---

## Project Structure

```
DCS/
└── Scripts/
    ├── Hooks/
    │   └── BIC-hook.lua                # Entry point, registers callbacks with DCS
    └── BombIntervalCalculator/
        ├── BIC-util.lua                # Logging, path checks, callback factory, window management
        ├── BIC-class.lua               # Data object with setters/getters and calculate()
        ├── BIC-ui.dlg                  # DCS dialog definition for the UI window
        └── testing.lua                 # Manual tests for the BIC class
```

### File roles

| File           | Purpose                                                                           |
|----------------|-----------------------------------------------------------------------------------|
| `BIC-hook.lua` | Loaded by DCS. Loads modules, checks paths/files, registers callbacks.            |
| `BIC-util.lua` | Logging, path checks, log rotation, callback factory including hotkey/skin trick. |
| `BIC-class.lua`| Data class with validating setters for TAS, distance, unit, and bomb count.       |
| `BIC-ui.dlg`   | Static description of the window, input fields, and buttons.                      |
| `testing.lua`  | Standalone test script (outside DCS) for class setters/getters.                   |

---

## Naming Conventions

The project follows a small but consistent scheme:

| Style             | Meaning                                                      |
|-------------------|--------------------------------------------------------------|
| `UPPERCASE`       | Simple types / values (strings, numbers, booleans)           |
| `cModule`         | Modules loaded via `require` (e.g. `cUtil`, `cDialogLoader`) |
| `oObject`         | Instances / objects (e.g. `oBicWindow`)                      |
| `LF`              | Short for LogFile path (argument to functions)               |
| `LL`              | LogLevel table (`info`, `warn`, `crit`)                      |
| `F`               | Files table with paths (`F.Log`, `F.Ui`, `F.Class`)          |

---

## Logging

- Default path: `%USERPROFILE%\Saved Games\DCS\Logs\bic.log`
- Three levels: `info` (only when `DEBUG = true`), `warn`, `crit`
- On startup an existing `bic.log` is rotated to `bic.log.old` to
  prevent the file from growing indefinitely
- `crit` entries terminate the script immediately

Format of each log line:
```
>> :<date+time> ::<LEVEL> :::<MESSAGE>
```

---

## Installation

1. Copy the `DCS/Scripts/` folder from this repository into your
   DCS user directory:
   ```
   %USERPROFILE%\Saved Games\DCS\Scripts\
   ```
2. Make sure the path
   `%USERPROFILE%\Saved Games\DCS\Scripts\BombIntervalCalculator\`
   exists and contains the four files (`BIC-util.lua`, `BIC-class.lua`,
   `BIC-ui.dlg`, `testing.lua`).
3. Start DCS, load a mission with an F-4E, and take a slot.
4. The BIC window is created automatically when entering the slot and is
   ready to use.
5. Hotkey **Left Shift + Left Ctrl + B** toggles the window on/off.

---

## Testing Outside DCS

The data class can be tested independently of the game, provided
Lua 5.1 is installed:

```bash
lua DCS/Scripts/BombIntervalCalculator/testing.lua
```

The script creates two instances of the class, calls all setters/getters
with valid and invalid values, and prints `All tests passed.` at the end
if all `assert` calls succeed.

---

## References & Inspiration

- [DCS ScratchPad Hook](https://raw.githubusercontent.com/rkusa/dcs-scratchpad/refs/heads/main/Scripts/Hooks/scratchpad-hook.lua) — template for the skin trick
- [DCS ScratchPad UI](https://raw.githubusercontent.com/rkusa/dcs-scratchpad/refs/heads/main/Scripts/Scratchpad/ScratchpadWindow.dlg) — template for the `.dlg` definition
- DCS Wiki on `DialogLoader`, `Skin`, `DCS.setUserCallbacks`

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.

You are free to use, copy, modify, and distribute this software, provided that
any derivative work is also released under the same GPL-3.0 license and its
source code is made available.

See the [LICENSE](LICENSE) file for the full license text, or visit
https://www.gnu.org/licenses/gpl-3.0.html
