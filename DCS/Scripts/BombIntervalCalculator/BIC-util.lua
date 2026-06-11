local VERSION = "Bomb Interval Calculator v1.0.0 (2026-06-11)"
-- Wenn true, werden auch LogLevel[1] (info)-Einträge in die Logdatei
-- geschrieben. Im Release auf false setzen, damit die Datei klein bleibt.
-- Nur warn und crit werden dann noch geloggt.
local DEBUG = false

-- Gibt an ob das BIC-Fenster gerade sichtbar ist (true) oder versteckt
-- (false). Startet mit false, weil das Fenster beim Laden unsichtbar ist.
-- Wird in switch_window() umgeschaltet und in switch_window_children()
-- gelesen, um die Kindelemente entsprechend ein- oder auszublenden.
local IS_VISIBLE = false

-- Gibt an ob die Tastatur aktuell für DCS gesperrt ist (true), damit
-- Eingaben nur in die Textfelder fließen und nicht gleichzeitig als
-- Cockpit-Steuerbefehle gewertet werden. Wird in keyboard_input()
-- umgeschaltet. Beim Destroy des Fensters explizit auf false gesetzt,
-- damit ein neues Fenster mit sauberem Zustand startet.
local KEYBOARDLOCK = false

-- LuaFileSystem: Standard-Bibliothek für Dateisystem-Operationen.
-- Wird in check_paths() genutzt, um zu prüfen ob Verzeichnisse existieren.
local cLfs = require("lfs")

-- DCS Input-Bibliothek: Ermöglicht Zugriff auf Tastatur-Events und das
-- Sperren/Entsperren der Tastatureingabe für die Simulation.
-- Wird in keyboard_input() genutzt.
local cInput = require("Input")

-- Log-Level als Array. Zugriff über Index:
--   LogLevel[1] = "info"  -- Nur bei DEBUG = true geloggt
--   LogLevel[2] = "warn"  -- Immer geloggt
--   LogLevel[3] = "crit"  -- Immer geloggt, beendet das Script
-- Strings statt Zahlen damit die Logdatei menschenlesbar bleibt.
local LogLevel = {
    "info",
    "warn",
    "crit",
}

-- check_paths(PATHS)
-- Prüft ob alle Verzeichnisse in der übergebenen Liste existieren.
-- Wird beim Start aufgerufen bevor das Logfile angelegt wird, daher
-- wird bei Fehler direkt auf die Konsole geschrieben statt zu loggen.
--
-- Parameter:
--   PATHS  - Array mit absoluten Verzeichnispfaden (z.B. Logs-Ordner,
--            Scripts-Ordner). Wird mit ipairs iteriert, Reihenfolge
--            ist also garantiert.
--
-- Verhalten bei fehlendem Verzeichnis:
--   Gibt eine Fehlermeldung auf die Konsole aus und beendet das
--   Script mit os.exit(1). Kein Logfile vorhanden = kein dbg_log.
local function check_paths(PATHS)

	for _, DIR in ipairs(PATHS) do
		local exists = cLfs.attributes(DIR, "mode")
		if not exists then
			print(LogLevel[3]..": "..DIR..": does not exsist")
			os.exit(1)
		end
	end

end

-- check_files(F)
-- Prüft ob alle benötigten Dateien lesbar sind. Öffnet jede Datei
-- kurz im Lesemodus und schließt sie sofort wieder – das ist die
-- einfachste Existenz- und Lesbarkeitsprüfung die Lua bietet.
--
-- Parameter:
--   F  - Dictionary (key = logischer Name, value = Dateipfad).
--        Bekannte Keys: "Log", "Ui", "Class".
--
-- Sonderfall "Log":
--   Die Logdatei darf fehlen, weil sie durch log_rotate() beim Start
--   neu angelegt wird. Alle anderen Dateien sind Pflicht – fehlt z.B.
--   die .dlg-Datei, kann das Fenster nicht erzeugt werden.
--
-- Verhalten bei fehlender Pflichtdatei:
--   Konsolenausgabe + os.exit(1).
local function check_files(F)

	for KEY, FILE in pairs(F) do
		local f = io.open(FILE, "r")
		if not f then
			print(LogLevel[3]..": "..FILE..": not found")
			if KEY ~= "Log" then
				os.exit(1)
			end
		else
			f:close()
		end
	end

end

-- log_rotate(LogFile)
-- Rotiert die Logdatei: Die vorhandene Datei wird zu .old umbenannt,
-- dann wird eine neue leere Datei angelegt. Wird einmal beim Start
-- aufgerufen damit die Datei nicht über mehrere Sessions wächst.
--
-- Parameter:
--   LogFile  - Absoluter Pfad zur Logdatei (z.B. ".../Logs/bic.log").
--
-- Ablauf:
--   1. Prüfen ob die Logdatei existiert (Lesemodus öffnen).
--   2. Wenn ja: vorhandene .old löschen (os.rename schlägt sonst fehl),
--      dann LogFile nach LogFile.old umbenennen.
--   3. Neue leere Datei anlegen, flush und close damit der Handle
--      freigegeben ist bevor dbg_log() die Datei im Append-Modus öffnet.
local function log_rotate(LogFile)

	local f = io.open(LogFile, "r")
	if f then
		f:close()
		os.remove(LogFile..".old")
		os.rename(LogFile, LogFile..".old")
	end
	local n = io.open(LogFile, "w")
	if n then
		n:flush()
		n:close()
	end

end

-- dbg_log(LogFile, LEVEL, MESSAGE)
-- Schreibt eine formatierte Zeile in die Logdatei. Öffnet die Datei
-- im Append-Modus ("a+") damit mehrere Aufrufe sich nicht gegenseitig
-- überschreiben. Schließt den Handle nach jedem Aufruf explizit, weil
-- Lua keinen deterministischen GC für Filehandles hat und in DCS ein
-- offener Handle zu Schreibkonflikten führen kann.
--
-- Parameter:
--   LogFile  - Absoluter Pfad zur Logdatei (String). Wird auf nil und
--              falschen Typ geprüft bevor die Datei geöffnet wird.
--   LEVEL    - Log-Level: LogLevel[1] (info), LogLevel[2] (warn) oder
--              LogLevel[3] (crit). Bestimmt ob und wie geloggt wird.
--   MESSAGE  - Beliebiger Inhalt, wird via tostring() in einen String
--              gewandelt bevor er geschrieben wird.
--
-- Rückgabe:
--   true   - Zeile wurde geschrieben.
--   false  - LogFile fehlerhaft oder Datei nicht öffenbar (nur Konsole).
--
-- Log-Format jeder Zeile:
--   >> :<Datum+Uhrzeit> ::<LEVEL> :::<MESSAGE>
--
-- Besonderheiten:
--   - info-Zeilen werden nur geschrieben wenn DEBUG = true ist.
--   - Bei LEVEL == LogLevel[3] (crit) wird eine zweite Zeile
--     "Script wird beendet." angehängt, dann os.exit(1).
--     Das ist die zentrale Abbruchstelle des Scripts.
local function dbg_log(LogFile, LEVEL, MESSAGE)

	if not LogFile then
		print("LogFile wurde nicht angegeben. \
            Logfile kann nicht geschrieben werden.")
		return false
	end
	if (type(LogFile) ~= "string") then
		print("LogFile ist kein String: "..tostring(LogFile
            ).." Logfile kann nicht geschrieben werden."
        )
		return false
	end

	local LOG = io.open(LogFile, "a+")
	if not LOG then
		print("LogFile kann nicht geöffnet werden: " .. LogFile)
		return false
	end

	-- info wird nur bei DEBUG = true geschrieben.
	-- warn und crit werden immer geschrieben.
	if LEVEL ~= LogLevel[1] or DEBUG == true then
		LOG:write(("\n>> :%s ::%s :::%s"):format(
		os.date(),
			tostring(LEVEL),
			tostring(MESSAGE)
		))
	end

	-- Bei crit: zweite Zeile "Script wird beendet." schreiben,
	-- dann Datei schließen und Script beenden.
	if LEVEL == LogLevel[3] then
		LOG:write(("\n>> :%s ::%s :::%s"):format(
		os.date(),
			tostring(LEVEL),
			"Script wird beendet.")
		)
		LOG:flush()
		LOG:close()
		os.exit(1)
	end

    LOG:flush()
	LOG:close()

	return true
end

-- chk_require(LogFile, OK, LEVEL, MODULE)
-- Wertet das Ergebnis eines require()-Aufrufs aus und loggt es.
-- Schreibt bei Erfolg eine info-Zeile, bei Fehler eine Zeile mit dem
-- übergebenen LEVEL (typischerweise crit, damit das Script abbricht).
--
-- Parameter:
--   LogFile  - Absoluter Pfad zur Logdatei (String).
--   OK       - true wenn require() erfolgreich war, sonst false.
--   LEVEL    - Log-Level der Fehlermeldung wenn OK == false.
--   MODULE   - Anzeigename des Moduls für die Logzeile (z.B. "cUtil").
--
-- Rückgabe:
--   false  - wenn OK == false oder LogFile ungültig.
--   nil    - bei Erfolg (kein explizites return true nötig).
local function chk_require(LogFile, OK, LEVEL, MODULE)
	if not LogFile then
		print("LogFile wurde nicht angegeben. \
            Logfile kann nicht geschrieben werden.")
		return false
	end
	if (type(LogFile) ~= "string") then
		print("LogFile ist kein String: "..tostring(LogFile
            ).." Logfile kann nicht geschrieben werden."
        )
		return false
	end

	if OK == false then
		dbg_log(LogFile, LEVEL, MODULE.." konnte nicht geladen werden.")
		return false
	end
	dbg_log(LogFile, LogLevel[1], MODULE.." wurde geladen.")
end

-- create_callbacks(LogFile, cDialogLoader, cSkin, Ui, cBICclass)
-- Fabrik-Funktion: Baut alle DCS-Callbacks und gibt sie als Tabelle
-- zurück. Der Hook übergibt diese Tabelle an DCS.setUserCallbacks().
-- Alle inneren Funktionen teilen sich denselben Closure und haben so
-- Zugriff auf LogFile, oBicWindow, IS_VISIBLE, CHILDS usw., ohne
-- dass diese Werte global sichtbar sein müssen.
--
-- Parameter:
--   LogFile       - Absoluter Pfad zur Logdatei.
--   cDialogLoader - DCS-Modul zum Laden von .dlg-Dateien
--                   (spawnDialogFromFile).
--   cSkin         - DCS-Modul mit Skin-Definitionen
--                   (windowSkin, windowSkinChatMin).
--   Ui            - Absoluter Pfad zur BIC-ui.dlg-Datei.
--   cBICclass     - Instanz der BIC-Datenklasse mit Settern/Gettern
--                   für TAS, Distanz, Einheit, Bombenanzahl und der
--                   calculate()-Methode.
--
-- Rückgabe:
--   cb  - Tabelle mit cb.onActivatePlane(unitType), die DCS bei
--         Slot-Wechsel aufruft.
local function create_callbacks(LogFile, cDialogLoader, cSkin, Ui, cBICclass)

    -- Rückgabe-Tabelle für DCS.setUserCallbacks().
    local cb = {}

    -- Das Dialog-Objekt des BIC-Fensters. Startet als nil und wird in
    -- init_window() gefüllt. Solange nil, werden keine UI-Operationen
    -- ausgeführt. Wird in onActivatePlane() auf nil gesetzt wenn ein
    -- anderes Flugzeug als die F-4E aktiviert wird.
    local oBicWindow

    -- Mapping von logischen Namen auf die Element-Namen in BIC-ui.dlg.
    -- switch_window_children() iteriert über diese Tabelle um alle
    -- Kindelemente gleichzeitig ein- oder auszublenden. Neue Felder
    -- nur hier eintragen, der Rest passiert automatisch.
	local CHILDS = {
    	labelTAS     = "labelTAS",
		inputTAS     = "inputTAS",
		hintTAS      = "hintTAS",      -- Hinweis "200 - 1000 kts" unter TAS-Feld
		labelDist    = "labelDist",
		inputDist    = "inputDist",
        unitButton   = "unitButton",   -- Button zum Umschalten zwischen nm und ft
		hintDistNm   = "hintDistNm",   -- Hinweis "0.1 - 2.0 nm" (nur bei Einheit nm)
		hintDistFt   = "hintDistFt",   -- Hinweis "650 - 12500 ft" (nur bei Einheit ft)
		labelBombs   = "labelBombs",
		inputBombs   = "inputBombs",
		hintBombs    = "hintBombs",    -- Hinweis "2 - 21" unter Bomben-Feld
		labelResult  = "labelResult",
		outputResult = "outputResult", -- Ausgabefeld: Ergebnis, "Invalid input" oder
		                               -- "Invalid interval"
		calcButton   = "calcButton",
		closeButton  = "closeButton",
	}

    -- switch_window_children()
    -- Setzt die Sichtbarkeit aller Kindelemente aus CHILDS auf den
    -- aktuellen Wert von IS_VISIBLE. Wird nach jedem Wechsel des
    -- Fensterzustands aufgerufen (switch_window), damit Labels,
    -- Eingabefelder, Ausgabefeld und Buttons synchron mit dem
    -- Fenster-Skin ein- oder ausgeblendet werden.
    --
    -- Sonderfall Dist-Hints:
    --   hintDistNm und hintDistFt sind gegenseitig exklusiv – immer
    --   ist nur einer der beiden sichtbar, abhängig von der aktiven
    --   Einheit am unitButton. Da der CHILDS-Loop beide auf IS_VISIBLE
    --   setzen würde, korrigiert ein nachgelagerter Block beim
    --   Einblenden den jeweils falschen Hint wieder auf false.
	local function switch_window_children()

		dbg_log(LogFile, LogLevel[1], "switch_window_children")

		-- Alle Kindelemente auf den aktuellen Sichtbarkeitsstatus setzen.
		for _, name in pairs(CHILDS) do
    		oBicWindow:findByName(name):setVisible(IS_VISIBLE)
		end

        -- Beim Einblenden: aktive Einheit vom Button lesen und nur den
        -- passenden Dist-Hint sichtbar lassen. Der andere bleibt false.
        if IS_VISIBLE then
            local currentUnit = oBicWindow:findByName(
                CHILDS.unitButton):getText()

            if currentUnit == "nm" then
                oBicWindow:findByName(CHILDS.hintDistNm):setVisible(true)
                oBicWindow:findByName(CHILDS.hintDistFt):setVisible(false)
                dbg_log(LogFile, LogLevel[1], "switch_window_children: \
                    currentUnit is nm")
            else
                oBicWindow:findByName(CHILDS.hintDistNm):setVisible(false)
                oBicWindow:findByName(CHILDS.hintDistFt):setVisible(true)
                dbg_log(LogFile, LogLevel[1], "switch_window_children: \
                currentUnit is ft")
            end
        end

	end

    -- switch_window()
    -- Schaltet das BIC-Fenster zwischen sichtbar und versteckt um.
    -- Registriert als Hotkey-Callback (LShift+LCtrl+B) und als
    -- Change-Callback des Close-Buttons.
    --
    -- Skin-Trick (warum kein setVisible?):
    --   DCS deregistriert Hotkey-Callbacks wenn ein Fenster mit
    --   setVisible(false) versteckt wird. Das Fenster bleibt daher
    --   technisch immer sichtbar. Stattdessen wird zwischen zwei
    --   Skins gewechselt:
    --     windowSkinChatMin  ->  transparenter Skin (optisch unsichtbar)
    --     windowSkin         ->  normaler sichtbarer Skin
    --   setHasCursor(false) verhindert im versteckten Zustand dass
    --   Mausklicks versehentlich vom Fenster abgefangen werden.
    local function switch_window()

        if IS_VISIBLE then
            -- Fenster verstecken: transparenter Skin, Cursor aus,
            -- IS_VISIBLE auf false, dann Kinder ausblenden.
            oBicWindow:setSkin(cSkin.windowSkinChatMin())
			oBicWindow:setHasCursor(false)
			IS_VISIBLE = false
			switch_window_children()
			dbg_log(LogFile, LogLevel[1], "switch_window: not visible")
        else
            -- Fenster einblenden: normaler Skin, Cursor ein,
            -- IS_VISIBLE auf true, dann Kinder einblenden.
            oBicWindow:setSkin(cSkin.windowSkin())
			oBicWindow:setHasCursor(true)
            IS_VISIBLE = true
			switch_window_children()
			dbg_log(LogFile, LogLevel[1], "switch_window: is visible")
        end

    end

    -- on_calculate()
    -- Liest die drei Eingabefelder aus, übergibt die Werte an die
    -- BIC-Klasse und zeigt das Ergebnis im Ausgabefeld an.
    -- Registriert als Change-Callback des Calculate-Buttons.
    --
    -- Ablauf:
    --   1. TAS, Distanz und Bombenanzahl aus den Eingabefeldern lesen.
    --      tonumber() wandelt den Text in eine Zahl um. Gibt es keine
    --      gültige Zahl (leeres Feld, Text), liefert tonumber() nil
    --      und die Setter der BIC-Klasse geben false zurück.
    --   2. Schlägt mindestens ein Setter fehl, wird "Invalid input" in
    --      das Ausgabefeld geschrieben und die Funktion beendet.
    --   3. Sind alle Werte gültig, wird calculate() aufgerufen.
    --      Liegt das Ergebnis außerhalb der F-4E Hardware-Grenzen
    --      (0.05s – 10.00s), gibt calculate() false zurück und das
    --      Ausgabefeld zeigt "Invalid interval".
    --   4. Bei gültigem Ergebnis wird es mit zwei Dezimalstellen
    --      formatiert in das Ausgabefeld geschrieben.
	local function on_calculate()

        -- True Airspeed einlesen und setzen. okTAS ist true wenn der
        -- Wert im gültigen Bereich liegt (200 - 1000 kts).
        local okTAS = cBICclass:setKnots(
            tonumber(oBicWindow:findByName(CHILDS.inputTAS):getText())
        )
        dbg_log(LogFile, LogLevel[1], "TAS: "..tostring(cBICclass:getKnots()))

        -- Distanz einlesen und setzen. Die aktive Einheit wird direkt
        -- vom unitButton-Text gelesen und mit übergeben.
        -- okDist ist true wenn der Wert im Bereich der aktiven Einheit
        -- liegt (nm: 0.1-2.0, ft: 650-12500).
        local okDist = cBICclass:setDistance(
            tonumber(oBicWindow:findByName(CHILDS.inputDist):getText()),
            oBicWindow:findByName(CHILDS.unitButton):getText()
        )
        dbg_log(LogFile, LogLevel[1], "Distance: "..tostring(
            cBICclass:getDistance()
        )..tostring(cBICclass:getUnit()))

        -- Bombenanzahl einlesen und setzen. okBombs ist true wenn der
        -- Wert im gültigen Bereich liegt (2 - 21).
        local okBombs = cBICclass:setBombCount(
            tonumber(oBicWindow:findByName(CHILDS.inputBombs):getText())
        )
        dbg_log(LogFile, LogLevel[1], "Bombs: "..tostring(
            cBICclass:getBombCount()
        ))

        -- Mindestens ein Eingabewert ist ungültig: Fehlermeldung
        -- ausgeben und abbrechen. Kein calculate()-Aufruf.
        if not okTAS or not okDist or not okBombs then
            dbg_log(
                LogFile, LogLevel[1], "Invalid input: TAS="..tostring(okTAS
                )..", Dist="..tostring(okDist
                )..tostring(cBICclass:getUnit()
                )..", Bombs="..tostring(okBombs)
            )
            oBicWindow:findByName(CHILDS.outputResult):setText("Invalid input")
            return
        end

        -- Alle Eingaben gültig: Intervall berechnen.
        -- RESULT ist false wenn das Ergebnis außerhalb 0.05s – 10.00s liegt.
        local RESULT = cBICclass:calculate()

        if RESULT == false then
            dbg_log(LogFile, LogLevel[1], "Invalid interval")
                oBicWindow:findByName(CHILDS.outputResult
                ):setText("Invalid interval"
            )
            return
        end

        -- Gültiges Ergebnis: mit zwei Dezimalstellen formatiert ausgeben.
        oBicWindow:findByName(CHILDS.outputResult
            ):setText(string.format("%.2f", RESULT)
        )
        dbg_log(LogFile, LogLevel[1], "Calculated interval: \
            "..tostring(RESULT).." seconds")
	end

    -- keyboard_input()
    -- Toggelt die Tastatursperre für Texteingaben. Registriert als
    -- Focus-Callback an allen drei Eingabefeldern (TAS, Dist, Bombs).
    -- DCS ruft diesen Callback sowohl beim Fokus-Erhalt als auch beim
    -- Fokus-Verlust eines Feldes auf – es gibt keinen separaten Blur-
    -- Callback. Das KEYBOARDLOCK-Flag unterscheidet die beiden Fälle.
    --
    -- Warum Tastatursperre?
    --   DCS leitet Tastatureingaben standardmäßig an die Simulation
    --   weiter. Ohne Sperre landet jeder Tastendruck gleichzeitig im
    --   Textfeld und als Cockpit-Steuerbefehl (z.B. Fahrwerk, Throttle).
    --   DCS.lockKeyboardInput() sperrt eine Liste von Tasten für die
    --   Simulation; sie landen dann nur noch im Textfeld.
    --
    -- Chat-Hotkeys werden bewusst NICHT gesperrt:
    --   Würden Chat-Tasten gesperrt, lässt sich der Chat nicht mehr
    --   öffnen. In Kombination mit dem Scratchpad-Ansatz entsteht ein
    --   Deadlock: Chat kann nicht geschlossen werden und fast alle
    --   Tastatureingaben funktionieren nicht mehr.
    --   removeCommandEvents() entfernt daher die vier Chat-Aktionen
    --   aus der Sperrliste bevor lockKeyboardInput() aufgerufen wird.
    --   Dieser Ansatz ist aus mul_chat.lua übernommen.
	local function keyboard_input()

        if KEYBOARDLOCK then
            -- Tastatur war gesperrt -> Sperre aufheben.
            -- Der Parameter true bei unlockKeyboardInput signalisiert
            -- DCS, alle gesperrten Tasten freizugeben.
			---@diagnostic disable-next-line: undefined-global
            DCS.unlockKeyboardInput(true)
            KEYBOARDLOCK = false
			dbg_log(LogFile, LogLevel[1], "Textfeld Fokus nicht aktiv")

		else

            -- Alle Tasten der angeschlossenen Tastatur holen.
	        local keyboardEvents = cInput.getDeviceKeys(
                cInput.getKeyboardDeviceName()
            )
            -- DCS-Aktionsumgebung: Enthält alle UI-Aktionen inkl.
            -- der Chat-Befehle die aus der Sperrliste entfernt werden.
	        local inputActions = cInput.getEnvTable().Actions

            -- Hilfsfunktion: Entfernt eine Liste von Command-Events
            -- aus keyboardEvents. Iteriert rückwärts über keyboardEvents
            -- damit table.remove() die noch nicht geprüften Indizes
            -- nicht verschiebt.
	        local removeCommandEvents = function(commandEvents)
    	        for i, commandEvent in ipairs(commandEvents) do
        	        for j = #keyboardEvents, 1, -1 do
            	        if keyboardEvents[j] == commandEvent then
                	        table.remove(keyboardEvents, j)
                    	    break
                    	end
                	end
            	end
		   	end

            -- Vier Chat-Aktionen aus der Sperrliste herausnehmen:
            -- Chat öffnen, Allchat, Teamchat, Chat ein-/ausblenden.
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(
                inputActions.iCommandChat)
            )
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(
                inputActions.iCommandAllChat)
            )
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(
                inputActions.iCommandFriendlyChat)
            )
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(
                inputActions.iCommandChatShowHide)
            )

            -- Verbleibende Tasten für die Simulation sperren.
			---@diagnostic disable-next-line: undefined-global
        	DCS.lockKeyboardInput(keyboardEvents)
        	KEYBOARDLOCK = true

			dbg_log(LogFile, LogLevel[1], "Textfeld Fokus aktiv")

        end
    end

    -- switch_unit()
    -- Schaltet die Distanz-Einheit zwischen nm und ft um.
    -- Registriert als Change-Callback des unitButtons.
    -- Liest den aktuellen Button-Text, setzt ihn auf die jeweils
    -- andere Einheit und blendet den passenden Dist-Hint ein.
    local function switch_unit()

        local oUnitButton = oBicWindow:findByName(CHILDS.unitButton)
        if oUnitButton:getText() == "nm" then
            -- Von nm auf ft wechseln.
            oUnitButton:setText("ft")
            oBicWindow:findByName(CHILDS.hintDistNm):setVisible(false)
            oBicWindow:findByName(CHILDS.hintDistFt):setVisible(true)
        else
            -- Von ft auf nm wechseln.
            oUnitButton:setText("nm")
            oBicWindow:findByName(CHILDS.hintDistNm):setVisible(true)
            oBicWindow:findByName(CHILDS.hintDistFt):setVisible(false)
        end

    end

    -- init_window()
    -- Erstellt das BIC-Dialogfenster und registriert alle Callbacks.
    -- Wird genau einmal aus onActivatePlane() aufgerufen, wenn eine
    -- F-4E aktiviert wird und oBicWindow noch nil ist.
    --
    -- Reihenfolge:
    --   1. Dialog aus der .dlg-Datei laden (spawnDialogFromFile).
    --   2. setVisible(true) – DCS-Pflicht bevor Hotkeys registriert
    --      werden können. Unsichtbare Fenster akzeptieren keine Callbacks.
    --   3. Hotkey LShift+LCtrl+B für switch_window registrieren.
    --   4. Skin auf windowSkinChatMin setzen -> Fenster startet optisch
    --      unsichtbar, bleibt aber technisch sichtbar (Hotkey aktiv).
    --   5. Callbacks für Close-Button, Calculate-Button, Unit-Button
    --      und die drei Eingabefelder registrieren.
    --   6. switch_window_children() aufrufen -> alle Kinder auf
    --      IS_VISIBLE (= false) setzen. Startzustand: alles versteckt.
    local function init_window()

        -- Dialog-Objekt erzeugen. Ab hier ist oBicWindow nicht mehr nil.
    	oBicWindow = cDialogLoader.spawnDialogFromFile(Ui)
    	dbg_log(LogFile, LogLevel[1], "oBicWindow: "..tostring(oBicWindow))

        -- Muss true sein bevor Hotkeys registriert werden können.
		oBicWindow:setVisible(true)
    	dbg_log(LogFile, LogLevel[1], "oBicWindow:setVisible(true)")

        -- Fenster-Titel setzen
        oBicWindow:setText(tostring(VERSION))

		oBicWindow:addHotKeyCallback("left shift+left ctrl+b", switch_window)
    	dbg_log(LogFile, LogLevel[1],
            "oBicWindow:addChangeCallback: "..tostring(
            oBicWindow.addHotKeyCallback)
        )
		dbg_log(LogFile, LogLevel[1], "oBicWindow: Callback \
            :addHotKeyCallback für switch_window registriert")

        -- Skin-Trick: Fenster sofort optisch verstecken.
		oBicWindow:setSkin(cSkin.windowSkinChatMin())
    	dbg_log(LogFile, LogLevel[1], "oBicWindow: setSkin windowSkinChatMin()")

        -- Close-Button: Klick ruft switch_window auf.
		local oCloseButton = oBicWindow:findByName(CHILDS.closeButton)
		oCloseButton:addChangeCallback(switch_window)
		dbg_log(LogFile, LogLevel[1], "oCloseButton:addChangeCallback: \
            "..tostring(oCloseButton.addChangeCallback))
		dbg_log(LogFile, LogLevel[1], "oCloseButton: Callback \
            :addChangeCallback für switch_window registriert")

        -- Calculate-Button: Klick ruft on_calculate auf.
		local oCalculateButton = oBicWindow:findByName("calcButton")
		oCalculateButton:addChangeCallback(on_calculate)
		dbg_log(LogFile, LogLevel[1], "oCalculateButton:addChangeCallback: \
            "..tostring(oCalculateButton.addChangeCallback))
		dbg_log(LogFile, LogLevel[1], "oCalculateButton: Callback \
        :addChangeCallback für on_calculate registriert")

        -- TAS-Eingabefeld: Fokus-Callback für Tastatursperre.
		local oInputTAS = oBicWindow:findByName(CHILDS.inputTAS)
		oInputTAS:addFocusCallback(keyboard_input)
		dbg_log(LogFile, LogLevel[1], "oInputTAS:addFocusCallback: \
            "..tostring(oInputTAS.addFocusCallback))
		dbg_log(LogFile, LogLevel[1], "oInputTAS: Callback \
            :addFocusCallback für keyboard_input registriert")

        -- Distanz-Eingabefeld: Fokus-Callback für Tastatursperre.
		local oInputDIS = oBicWindow:findByName(CHILDS.inputDist)
		oInputDIS:addFocusCallback(keyboard_input)
		dbg_log(LogFile, LogLevel[1], "oInputDIS:addFocusCallback: \
            "..tostring(oInputDIS.addFocusCallback))
		dbg_log(LogFile, LogLevel[1], "oInputDIS: Callback \
            :addFocusCallback für keyboard_input registriert")

        -- Unit-Button: Change-Callback für Einheiten-Umschaltung.
        local oUnitButton = oBicWindow:findByName(CHILDS.unitButton)
        oUnitButton:addChangeCallback(switch_unit)
        dbg_log(LogFile, LogLevel[1], "oUnitButton:addChangeCallback: \
            "..tostring(oUnitButton.addChangeCallback))
        dbg_log(LogFile, LogLevel[1], "oUnitButton: Callback \
            :addChangeCallback für switch_unit registriert")

        -- Bomben-Eingabefeld: Fokus-Callback für Tastatursperre.
		local oInputBCOUNT = oBicWindow:findByName(CHILDS.inputBombs)
		oInputBCOUNT:addFocusCallback(keyboard_input)
		dbg_log(LogFile, LogLevel[1], "oInputBCOUNT:addFocusCallback: \
            "..tostring(oInputBCOUNT.addFocusCallback))
		dbg_log(LogFile, LogLevel[1], "oInputBCOUNT: Callback \
            :addFocusCallback für keyboard_input registriert")

end

    -- cb.onActivatePlane(unitType)
    -- DCS-Callback: Wird von DCS aufgerufen wenn der Spieler einen
    -- Slot betritt oder die Mission startet.
    --
    -- Parameter:
    --   unitType  - DCS-interner Typ-String des aktivierten Flugzeugs
    --               (z.B. "F-4E-45MC", "F-16C_50").
    --
    -- Logik:
    --   F-4E aktiv + kein Fenster -> init_window() aufrufen.
    --     Stellt sicher dass das Fenster nur einmal erzeugt wird,
    --     auch wenn onActivatePlane mehrfach für die F-4E kommt.
    --   Anderes Flugzeug + Fenster vorhanden -> aufräumen:
    --     setVisible(false), destroy(), oBicWindow = nil,
    --     KEYBOARDLOCK = false. Gibt DCS-Speicher frei und setzt die
    --     Closure zurück damit beim nächsten F-4E-Slot init_window()
    --     wieder ausgeführt wird.
    --   Anderes Flugzeug + kein Fenster -> nichts tun.
    function cb.onActivatePlane(unitType)

		dbg_log(LogFile, LogLevel[1],
            "[CB] onActivatePlane unitType="..tostring(unitType))
		if unitType == "F-4E-45MC" then
        	if not oBicWindow then
            	init_window()
			end
		elseif oBicWindow then
			oBicWindow:setVisible(false)
			oBicWindow:destroy()
			oBicWindow = nil
            -- Tastatursperre zurücksetzen damit das nächste Fenster
            -- mit sauberem Zustand startet.
            KEYBOARDLOCK = false
		end

    end

    return cb
end

-- Öffentliche API dieses Moduls. Wird vom Hook via require() geladen.
-- Nur diese Funktionen/Werte sind von außen sichtbar.
return {
	LogLevel         = LogLevel,          -- Log-Level-Array (info/warn/crit)
	check_paths      = check_paths,       -- Verzeichnisse prüfen
	check_files      = check_files,       -- Dateien prüfen
	log_rotate       = log_rotate,        -- Logdatei rotieren
	dbg_log          = dbg_log,           -- In Logdatei schreiben
	chk_require      = chk_require,       -- require()-Ergebnis loggen
	create_callbacks = create_callbacks,  -- DCS-Callbacks erzeugen
}
