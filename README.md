# 💣 Bomb Interval Calculator (BIC)

Ein Lua-Mod für den **Digital Combat Simulator (DCS)**, speziell für die
**F-4E Phantom II**. Berechnet das Abwurfintervall für ungelenkte Bomben
(z. B. Mk-82) anhand von True Airspeed, Streckenlänge und Bombenanzahl –
direkt im Cockpit, ohne externen Rechner.

---

## 🎯 Zweck

Wer in DCS mit der F-4E einen Bombenteppich legen will, muss am
**INTRVL-Regler** im Cockpit ein Intervall in Sekunden einstellen. Welcher
Wert der richtige ist, hängt von drei Faktoren ab:

| Faktor          | Einheit      | Quelle im Cockpit           |
|-----------------|--------------|------------------------------|
| True Airspeed   | Knoten (kts) | TAS-Anzeige                  |
| Streckenlänge   | nm oder ft   | Missionsplanung / Karten     |
| Bombenanzahl    | Stück        | Beladung des Flugzeugs       |

Diese Werte tippt man normalerweise vor dem Start in einen externen
Taschenrechner (oder eine App) und überträgt das Ergebnis dann ins
Cockpit. Der BIC erledigt das **während des Flugs** über ein kleines
DCS-Fenster, das per Hotkey ein- und ausgeblendet wird.

---

## 🧮 Die Formel

Die zugrundeliegende Berechnung ist die simpel Weg-Zeit-Gleichung,
verteilt auf `(n − 1)` Intervalle:

```
Δt = (d / v) × 3600 / (n − 1)
```

- `d` = Streckenlänge in **Seemeilen** (nm)  
  (Eingabe in ft wird intern umgerechnet: `d_nm = d_ft / 6076`)
- `v` = True Airspeed in **Knoten**
- `n` = Anzahl der Bomben (mindestens 2, sonst Division durch 0)
- `Δt` = Abwurfintervall in **Sekunden**

### Gültiger Ausgabebereich

`0,05 s` bis `10,00 s` – das sind die Hardware-Grenzen des
INTRVL-Reglers der F-4E. Der Regler läuft von 0,05 s bis 1,00 s; ein
Schalter multipliziert den Wert mit 10 (max. 10,00 s). Werte außerhalb
dieses Bereichs werden vom BIC erkannt und entsprechend markiert.

---

## 🖥️ Das UI

Das Fenster (300 × 220 px) enthält drei Eingabefelder, ein Ausgabefeld
und zwei Buttons:

```
┌─ Bomb Interval Calculator ─────────────┐
│  True Airspeed (kts): [         ]      │
│  Distance (nm or ft): [         ]      │
│  Number of Bombs:     [         ]      │
│                                        │
│  Interval (sec):       [         ]     │
│                                        │
│  [ Calculate ]            [ Close ]    │
└────────────────────────────────────────┘
```

- **Calculate** liest die Eingaben, validiert sie und schreibt das
  Ergebnis in das Ausgabefeld.
- **Close** versteckt das Fenster (Skin-Trick, siehe unten).
- Sichtbarkeit wird per **Hotkey getoggelt**: `Left Shift + Left Ctrl + B`

---

## 🪟 Der Skin-Trick

DCS deaktiviert Hotkey-Callbacks, sobald man ein Dialog-Fenster mit
`setVisible(false)` versteckt. Die Lösung stammt aus dem
[ScratchPad-Projekt](https://github.com/rkusa/dcs-scratchpad):

1. Beim Start wird das Fenster erzeugt (`spawnDialogFromFile`)
2. Per `setSkin(cSkin.windowSkinChatMin())` wird der Skin auf eine
   **transparente Chat-Minimized-Variante** gesetzt
3. Alle Kind-Elemente werden über `findByName()` einzeln auf
   `setVisible(false)` gesetzt
4. Der Hotkey schaltet zwischen `windowSkin()` (sichtbar) und
   `windowSkinChatMin()` (unsichtbar) hin und her

So bleibt das Fenster-Objekt technisch "lebendig" und der Hotkey
funktioniert weiterhin – auch über lange Missionen hinweg.

---

## 📁 Projektstruktur

```
DCS/
└── Scripts/
    ├── Hooks/
    │   └── BIC-hook.lua                # Einstiegspunkt, registriert Callbacks bei DCS
    └── BombIntervalCalculator/
        ├── BIC-util.lua                # Logging, Pfadprüfung, Callback-Bau, Fensterverwaltung
        ├── BIC-class.lua               # Datenobjekt mit Setter/Getter für Berechnungswerte
        ├── BIC-ui.dlg                  # DCS Dialog-Definition für das UI-Fenster
        └── testing.lua                 # Manuelle Tests der BIC-Klasse
```

### Rollen der Dateien

| Datei          | Aufgabe                                                                     |
|----------------|------------------------------------------------------------------------------|
| `BIC-hook.lua` | Wird von DCS geladen. Lädt Module, prüft Pfade/Dateien, registriert Callbacks. |
| `BIC-util.lua` | Logging, Pfadprüfung, Log-Rotation, Aufbau der Callbacks inkl. Hotkey/Skin-Trick. |
| `BIC-class.lua`| Datenklasse mit validierenden Settern für TAS, Distanz, Einheit, Bombenanzahl. |
| `BIC-ui.dlg`   | Statische Beschreibung des Fensters, der Eingabefelder und Buttons.         |
| `testing.lua`  | Standalone-Testskript (außerhalb DCS) für die Setter/Getter der Klasse.      |

---

## 🔧 Namenskonventionen

Das Projekt folgt einem kleinen, aber konsequenten Schema:

| Schreibweise     | Bedeutung                                         |
|------------------|----------------------------------------------------|
| `GROSSBUCHSTABEN` | Einfache Typen / Werte (Strings, Numbers, Booleans) |
| `cModul`         | Geladene Module via `require` (z. B. `cUtil`, `cDialogLoader`) |
| `oObjekt`        | Instanzen / Objekte (z. B. `oBicWindow`)           |
| `LF`             | Kurzform für LogFile-Pfad (Argument an Funktionen) |
| `LL`             | LogLevel-Tabelle (`info`, `warn`, `crit`)          |
| `F`              | Files-Tabelle mit Pfaden (`F.Log`, `F.Ui`, `F.Class`) |

---

## 🪵 Logging

- Standardpfad: `%USERPROFILE%\Saved Games\DCS\Logs\bic.log`
- Drei Level: `info` (nur bei `DEBUG = true`), `warn`, `crit`
- Beim Start wird eine vorhandene `bic.log` zu `bic.log.old` rotiert,
  damit die Datei nicht endlos wächst
- `crit`-Meldungen beenden das Script sofort

Format jeder Zeile:
```
>> :<Datum+Uhrzeit> ::<LEVEL> :::<MESSAGE>
```

---

## 🚀 Installation

1. Den Ordner `DCS/Scripts/` aus diesem Repository in dein
   DCS-Benutzerverzeichnis kopieren:
   ```
   %USERPROFILE%\Saved Games\DCS\Scripts\
   ```
2. Sicherstellen, dass der Pfad
   `%USERPROFILE%\Saved Games\DCS\Scripts\BombIntervalCalculator\`
   existiert und die vier Dateien (`BIC-util.lua`, `BIC-class.lua`,
   `BIC-ui.dlg`, `testing.lua`) enthält.
3. DCS starten, eine Mission mit F-4E laden, einen Slot besetzen.
4. Das BIC-Fenster wird beim Slot-Betreten automatisch erzeugt und ist
   bereit.
5. Hotkey **Left Shift + Left Ctrl + B** schaltet das Fenster ein/aus.

---

## 🧪 Testen außerhalb von DCS

Die Datenklasse kann unabhängig vom Spiel getestet werden, sofern
Lua 5.1 installiert ist:

```bash
lua DCS/Scripts/BombIntervalCalculator/testing.lua
```

Das Skript erzeugt zwei Instanzen der Klasse, ruft alle Setter/Getter
mit gültigen und ungültigen Werten auf und gibt am Ende
`Alle Tests bestanden.` aus, falls alle `assert`-Aufrufe durchgehen.

---

## 📚 Verweise & Inspiration

- [DCS ScratchPad Hook](https://raw.githubusercontent.com/rkusa/dcs-scratchpad/refs/heads/main/Scripts/Hooks/scratchpad-hook.lua) – Vorlage für den Skin-Trick
- [DCS ScratchPad UI](https://raw.githubusercontent.com/rkusa/dcs-scratchpad/refs/heads/main/Scripts/Scratchpad/ScratchpadWindow.dlg) – Vorlage für die `.dlg`-Definition
- DCS-Wiki zu `DialogLoader`, `Skin`, `DCS.setUserCallbacks`

---

## ⚖️ Lizenz

Lizenz steht noch aus. Bis dahin: **All rights reserved** durch den
Autor. Vorschläge gerne als Issue.