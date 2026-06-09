--[[
================================================================================
  BIC-hook.lua — Einstiegspunkt des "Bomb Interval Calculator" für DCS

  Aufgabe dieser Datei:
    1. Relevante Verzeichnisse (User-Home, DCS-User, Script-Ordner, Log-Ordner)
       als Lua-Variablen anlegen.
    2. Den Lua-Paketpfad (package.path) erweitern, damit "require" lokale
       Dateien aus dem Script-Ordner finden kann (BIC-util, BIC-class, ...).
    3. Das eigene Util-Modul "BIC-util" laden. Wenn das schon scheitert,
       ist das ein kritischer Fehler (Pfadproblem) → Script beenden.
    4. Eine DIR-Liste (DIRS) für die Pfadprüfung definieren.
    5. Prüfen, ob alle Verzeichnisse existieren (cUtil.check_paths).
    6. Eine Datei-Tabelle (F) mit Pfaden zu Logdatei, Klassen-Datei und
       UI-Definition (.dlg) aufbauen.
    7. Prüfen, ob alle benötigten Dateien vorhanden sind (cUtil.check_files).
    8. Eine vorhandene Logdatei rotieren (log_rotate), damit das Log
       nicht endlos wächst.
    9. Externe DCS-Module nachladen:
       - DialogLoader → für die UI-Definition (.dlg-Datei)
       - Skin         → für den "Skin-Trick" zum Ein-/Ausblenden
       - BIC-Class    → eigene Datenklasse (sonst "crit", Script-Abbruch)
       Fehler werden in das Log geschrieben. Log-Level werden aus
       cUtil.LogLevel gelesen (in BIC-util definiert und exportiert).
    10. Die Callbacks (onSimulationStart u.a.) über cUtil.create_callbacks
        erzeugen lassen. Diese Funktion kapselt die UI-Logik und das
        Hotkey-Handling.
    11. Die Callbacks bei DCS registrieren (DCS.setUserCallbacks).
    12. Eine letzte Logzeile schreiben, damit im Log sichtbar ist, dass
        die Registrierung geklappt hat.
================================================================================
]]


--[[ ---------- 1. PFADE / VERZEICHNISSE ---------- ]]

-- USERHOME: Windows-Pfad zum Benutzerverzeichnis (C:\Users\<Name>).
-- os.getenv liest eine Umgebungsvariable. In DCS unter Windows ist
-- "USERPROFILE" der zuverlässigere Weg als "HOME".
local USERHOME     = os.getenv("USERPROFILE")

-- DCSUSERHOME: Unterordner "Saved Games\DCS" innerhalb des Benutzerprofils.
-- DCS speichert dort Mods, Logs, Skripte, Traces etc. Der Doppel-Backslash
-- ist in Lua-Strings das Escape-Zeichen für einen einzelnen Backslash,
-- da Windows-Pfade "\" als Trennzeichen nutzen.
local DCSUSERHOME  = USERHOME .. "\\Saved Games\\DCS"

-- SCRIPTHOME: Zielverzeichnis, in dem die BIC-Dateien liegen sollen.
local SCRIPTHOME   = DCSUSERHOME .. "\\Scripts\\BombIntervalCalculator"

-- LOGHOME: Standard-Logverzeichnis von DCS, wird für die eigene Logdatei
-- "bic.log" wiederverwendet, damit man Logs an einem gewohnten Ort findet.
local LOGHOME      = DCSUSERHOME .. "\\Logs"


--[[ ---------- 2. PAKETPFAD ERWEITERN ---------- ]]

-- package.path enthält die durchsuchten Muster für require().
-- "\?.lua" sorgt dafür, dass z.B. require("BIC-util") die Datei
-- "BIC-util.lua" im SCRIPTHOME finden kann. Das Semikolon ist der
-- Listentrenner in package.path.
package.path = package.path .. ";" .. SCRIPTHOME .. "\\?.lua;"


--[[ ---------- 3. MODUL-VORAB DEKLARATIONEN ---------- ]]

-- OK               : Boolean-Rückgabewert von pcall (true = erfolgreich geladen)
-- cUtil            : das eigene Util-Modul mit Logging/Pfadprüfung/Callback-Bau
-- cDialogLoader    : DCS-Modul zum Erzeugen eines UI-Fensters aus .dlg
-- cSkin            : DCS-Modul mit Skin-Definitionen (z.B. windowSkinChatMin)
-- cBICclass        : eigene Datenklasse für die Berechnungswerte
local OK, cUtil, cDialogLoader, cSkin, cBICclass


--[[ ---------- 4. UTIL-MODUL LADEN (KRITISCH) ---------- ]]

-- pcall fängt Fehler ab, die require() wirft (z.B. "module not found").
-- Wenn das eigene Util-Modul nicht lädt, können wir weder loggen noch
-- Pfade prüfen → also direkt mit print() und os.exit(1) abbrechen.
OK, cUtil = pcall(require, "BIC-util")
if not OK then
    print("Benötigte Projekt-Datei BIC-util kann nicht geladen werden. Pfadproblem?")
    os.exit(1)
end


--[[ ---------- 5. Verzeichnis-LISTE ---------- ]]

-- DIRS: Liste der zu prüfenden Verzeichnisse. Wird an check_paths
-- übergeben. Die Reihenfolge ist bewusst hierarchisch: erst das
-- Benutzerverzeichnis, dann DCS-spezifische Pfade, dann der eigene
-- Script-Ordner.
local DIRS = {
	USERHOME, DCSUSERHOME, SCRIPTHOME, LOGHOME,
}

-- Existenzprüfung aller Verzeichnisse. Fehlt etwas, beendet sich
-- das Script innerhalb von check_paths per os.exit(1).
cUtil.check_paths(DIRS)


--[[ ---------- 6. DATEI-TABELLE AUFBAUEN ---------- ]]

-- F: Tabelle mit Datei-Pfaden. Das Präfix "F" steht für "Files"
-- (gemäß Namenskonvention). Die Keys ("Log", "Class", "Ui") dienen
-- nur der Lesbarkeit – sie sind im Grunde Labels.
local F = {
	Log		= LOGHOME .. "\\bic.log",        -- Logdatei für Debug-Output
	Class	= SCRIPTHOME .. "\\BIC-class.lua",  -- Datenklasse
	Ui		= SCRIPTHOME .. "\\BIC-ui.dlg",     -- UI-Definition für DialogLoader
}

-- Existenzprüfung aller benötigten Dateien. Fehlt eine Datei
-- (außer der Logdatei, die darf fehlen), beendet sich das Script.
cUtil.check_files(F)


--[[ ---------- 7. LOG-DATEI ROTIEREN ---------- ]]

-- cUtil.log_rotate rotiert eine vorhandene Logdatei:
--   alte Datei -> "bic.log.old"
--   neue, leere "bic.log" wird angelegt.
-- So bleibt das Log überschaubar und alte Einträge bleiben
-- für Fehleranalysen erhalten.
cUtil.log_rotate(F.Log)


--[[ ---------- 8. EXTERNE / EIGENE MODULE LADEN ---------- ]]

-- DialogLoader: DCS-eigenes Modul. Wird benötigt, um aus der .dlg-Datei
-- ein lauffähiges Dialog-Objekt zu erzeugen (spawnDialogFromFile).
-- Fehler hier sind "warn" – das Script kann theoretisch weiterlaufen,
-- allerdings wird das UI dann nicht funktionieren.
OK, cDialogLoader = pcall(require, "DialogLoader")
cUtil.chk_require(F.Log, OK, cUtil.LogLevel.warn, "DialogLoader")

-- Skin: DCS-Modul mit vordefinierten Skins. Wir brauchen es für den
-- Skin-Trick (sichtbar ↔ unsichtbar). Auch "warn" bei Fehler.
OK, cSkin = pcall(require, "Skin")
cUtil.chk_require(F.Log, OK, cUtil.LogLevel.warn, "cSkin")

-- BIC-Class: eigene Datenklasse. Hier ist ein Fehler kritisch, weil
-- die Berechnungslogik ohne sie nicht funktioniert. chk_require mit
-- LL.crit sorgt dafür, dass das Script bei Fehlschlag beendet wird.
OK, cBICclass = pcall(require, "BIC-Class")
cUtil.chk_require(F.Log, OK, cUtil.LogLevel.crit, "cBICclass")


--[[ ---------- 9. CALLBACKS ERZEUGEN ---------- ]]

-- create_callbacks kapselt die gesamte UI-/Hotkey-Logik und liefert
-- eine Tabelle mit den Funktionen, die DCS kennt
-- (z.B. cb.onSimulationStart). Übergeben werden:
--   F.Log         : Pfad zur Logdatei (für dbg_log-Aufrufe)
--   cDialogLoader : Modul zum Erzeugen des UI-Fensters
--   cSkin         : Modul mit Skin-Definitionen
--   F.Ui          : Pfad zur .dlg-Datei mit der UI-Definition
-- Der Einfachheit halber wird die zurückgegebene Tabelle direkt
-- "callbacks" genannt.
local callbacks = cUtil.create_callbacks(F.Log, cDialogLoader, cSkin, F.Ui)


--[[ ---------- 10. CALLBACKS BEI DCS REGISTRIEREN ---------- ]]

-- DCS.setUserCallbacks erwartet eine Tabelle mit Funktionen wie
-- onSimulationFrame, onSimulationStart, onSimulationStop, ...
-- Ab diesem Zeitpunkt reagiert DCS auf die im Modul registrierten
-- Callbacks – z.B. wird onSimulationStart aufgerufen, sobald der
-- Pilot einen Slot einnimmt, und baut dann das UI-Fenster auf.
---@diagnostic disable-next-line: undefined-global
DCS.setUserCallbacks(callbacks)


--[[ ---------- 11. ABSCHLUSS-LOG ---------- ]]

-- Bestätigung in die Logdatei schreiben. Damit ist im Log klar
-- erkennbar, dass die Initialisierung komplett durchgelaufen ist
-- und DCS die Callbacks kennt.
cUtil.dbg_log(F.Log, cUtil.LogLevel.info, "Callbacks registriert.")
