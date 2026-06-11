-- Debug-Flag. Wenn true, werden auch info-Logs geschrieben.
-- Im Release sollte das auf false stehen, um die Logdatei klein zu halten.
local DEBUG = true

-- Sichtbarkeitsstatus des BIC-Fensters. Startet mit "versteckt" (false),
local IS_VISIBLE = false

-- Merker, ob die Tastatur aktuell für die DCS-Simulation gesperrt ist,
-- damit der Pilot Text in die Eingabefelder tippen kann. Wird in
-- keyboard_input() umgeschaltet.
local KEYBOARDLOCK = false

-- Standard-LuaFileSystem-Bibliothek (Verzeichnisse prüfen, iterieren)
local cLfs = require("lfs")

-- DCS-Input-Bibliothek (wird für lockKeyboardInput benötigt, um
-- Tastaturanschläge an Textfelder umzuleiten, ohne DCS-Aktionen
-- auszulösen).
local cInput = require("Input")

--[[
    LogLevel-Tabelle.
    Strings statt Zahlen, damit die Logdatei menschenlesbar bleibt.
    Statt `dbg_log(LogFile, 1, "...")` schreibt man `dbg_log(LogFile, LogLevel.info, "...")`.
]]
local LogLevel = {
    info = "info",
    warn = "warn",
    crit = "crit",
}

--[[
    check_paths(PATHS)
    ----------------------------------------------------------------
    Prüft, ob alle übergebenen Verzeichnisse existieren.

    Parameter:
        PATHS  – Array (numerisch indizierte Tabelle) mit
                 absoluten oder relativen Verzeichnispfaden.

    Verhalten:
        - Nutzt cLfs.attributes(path, "mode") – das gibt `nil` zurück,
          wenn der Pfad nicht existiert, sonst einen String wie
          "directory" oder "file".
        - Bei einem fehlenden Pfad: Fehlermeldung auf die DCS-Konsole
          UND `os.exit(1)` – das Script bricht sofort ab, weil ohne
          die erwarteten Verzeichnisse kein Sinnvoller Betrieb möglich
          ist (z.B. Log-Verzeichnis fehlt).
        - Bewusst KEIN dbg_log, weil zu diesem Zeitpunkt das Logfile
          selbst noch nicht existieren muss.
]]
local function check_paths(PATHS)
	-- ipairs, nicht pairs: wir erwarten eine geordnete Liste.
	for _, DIR in ipairs(PATHS) do
		local exists = cLfs.attributes(DIR, "mode")
		if not exists then
			print(LogLevel.crit..": "..DIR..": does not exsist")
			os.exit(1)
		end
	end
end

--[[
    check_files(F)
    ----------------------------------------------------------------
    Prüft, ob alle benötigten Dateien lesbar sind.

    Parameter:
        F – Dictionary (key/value), wobei:
            KEY   = logischer Name der Datei (z.B. "Log", "Ui", "Class")
            FILE  = vollständiger Pfad zur Datei

    Verhalten:
        - Öffnet jede Datei im Lesemodus ("r") und schließt sie sofort
          wieder. Das ist die einfachste Existenz-/Lesbarkeitsprüfung,
          die Lua bietet.
        - Sonderfall KEY == "Log": Die Logdatei darf fehlen, weil sie
          durch log_rotate() bzw. dbg_log() ohnehin beim ersten
          Schreibvorgang angelegt wird. Alle anderen Dateien sind
          Pflicht (UI-Definition, Class-Modul etc.).
        - Bei Fehler: Konsolenausgabe + os.exit(1).
]]
local function check_files(F)
	-- pairs, nicht ipairs: F ist ein Dictionary, kein Array.
	for KEY, FILE in pairs(F) do
		local f = io.open(FILE, "r")
		if not f then
			print(LogLevel.crit..": "..FILE..": not found")
			if KEY ~= "Log" then
				os.exit(1)
			end
		else
			f:close()
		end
	end
end

--[[
    log_rotate(LogFile)
    ----------------------------------------------------------------
    Rotiert die Logdatei: Die bestehende Datei wird zu .old umbenannt,
    eine neue leere Datei wird angelegt.

    Parameter:
        LogFile – Pfad zur Logdatei (z.B. "C:/.../Logs/bic.log").

    Vorgehen (Schritt für Schritt):
        1. Prüfen, ob die Logdatei existiert (Lesemodus öffnen).
        2. Wenn ja: aktuelle .old löschen (falls vorhanden),
           dann LogFile → LogFile.old umbenennen.
        3. Neue leere Datei anlegen (Schreibmodus "w"), flush+close,
           damit der Handle freigegeben ist, bevor dbg_log() sie
           anschließend im Append-Modus öffnet.

    Warum Rotation?
        - DCS-Sessions können lang sein; eine wachsende Logdatei
          kostet Performance und wird unübersichtlich.
        - Eine Generation (.old) reicht – bei Bedarf kann man später
          auf N-Generationen erweitern.
]]
local function log_rotate(LogFile)
	local f = io.open(LogFile, "r")
	if f then
		f:close()
		-- Vorherige .old entfernen, sonst schlägt os.rename fehl.
		os.remove(LogFile..".old")
		os.rename(LogFile, LogFile..".old")
	end
	local n = io.open(LogFile, "w")
	if n then
		n:flush()
		n:close()
	end
end

--[[
    dbg_log(LogFile, LEVEL, MESSAGE)
    ----------------------------------------------------------------
    Schreibt eine formatierte Logzeile in die Logdatei.

    Parameter:
        LogFile – Pfad zur Logdatei (String).
        LEVEL   – LogLevel ("info" | "warn" | "crit").
        MESSAGE – Beliebiger Inhalt (wird via tostring gewandelt).

    Rückgabe:
        true  – Logzeile wurde geschrieben.
        false – Logfile fehlt oder ist kein String (nur Konsolenhinweis).

    Format der Logzeile:
        >> :<Datum/Uhrzeit> ::<LEVEL> :::<MESSAGE>

    Besonderheiten:
        - Datei wird im Modus "a+" (append+read) geöffnet, damit
          mehrere Aufrufe die Datei nicht überschreiben.
        - 'info' wird NUR geschrieben, wenn das Modul-Flag DEBUG true
          ist. 'warn' und 'crit' werden immer geloggt.
        - Bei LEVEL == "crit" wird eine zweite Zeile "Script wird
          beendet." angehängt, dann os.exit(1). Das ist die zentrale
          Stelle, an der das Script kontrolliert abbricht.
        - An jeder möglichen Rückkehr wird der Filehandle explizit
          geschlossen. Lua hat keinen deterministischen GC für
          Filehandles – in DCS kann ein offener Handle zu
          Schreibkonflikten führen.
]]
local function dbg_log(LogFile, LEVEL, MESSAGE)
	if not LogFile then
		print("LogFile wurde nicht angegeben. Logfile kann nicht geschrieben werden.")
		return false
	end
	if (type(LogFile) ~= "string") then
		print("LogFile ist kein String: "..tostring(LogFile).." Logfile kann nicht geschrieben werden.")
		return false
	end

	local LOG = io.open(LogFile, "a+")
	if not LOG then
		print("LogFile kann nicht geöffnet werden: " .. LogFile)
		return false
	end

	-- 'info' wird nur bei DEBUG geloggt
	if LEVEL ~= LogLevel.info or DEBUG == true then
		LOG:write(("\n>> :%s ::%s :::%s"):format(
		os.date(),
			tostring(LEVEL),
			tostring(MESSAGE)
		))
	end

	if LEVEL == LogLevel.crit then
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

--[[
    chk_require(LogFile, OK, LEVEL, MODULE)
    ----------------------------------------------------------------
    Wrapper, der das Ergebnis eines `require()`-Aufrufs loggt.

    Parameter:
        LogFile – Logfile-Pfad (String).
        OK      – true, wenn require erfolgreich; sonst false.
        LEVEL   – LogLevel ("info" | "warn" | "crit").
        MODULE  – Logischer Name des Moduls (nur für die Logzeile).

    Verhalten:
        - Bei OK == false: Fehlermeldung mit dem übergebenen LEVEL
          loggen, false zurückgeben.
        - Bei OK == true: info-Zeile "... wurde geladen." loggen.
        - Die doppelte LogFile-Validierung am Anfang ist absichtlich
          identisch zu dbg_log – defensive Programmierung: Falls LogFile
          nil oder kein String ist, würden wir beim Schreiben sonst
          seltsame Fehler in DCS bekommen.
]]
local function chk_require(LogFile, OK, LEVEL, MODULE)
	if not LogFile then
		print("LogFile wurde nicht angegeben. Logfile kann nicht geschrieben werden.")
		return false
	end
	if (type(LogFile) ~= "string") then
		print("LogFile ist kein String: "..tostring(LogFile).." Logfile kann nicht geschrieben werden.")
		return false
	end

	if OK == false then
		dbg_log(LogFile, LEVEL, MODULE.." konnte nicht geladen werden.")
		return false
	end
	dbg_log(LogFile, LogLevel.info, MODULE.." wurde geladen.")
end

--[[
    Funktionen für Callbacks und Fensterverwaltung
    =====================================================================
    Der folgende Block baut die DCS-UI auf. Wichtige Konzepte:

    1. `oBicWindow` ist eine Closure-Variable. Sie wird mit nil
       initialisiert und erst beim ersten onActivatePlane für die
       F-4E per `spawnDialogFromFile()` erzeugt. Solange sie nil ist,
       reagieren Hotkey- und andere Callbacks defensiv (siehe
       onActivatePlane).

    2. `create_callbacks(...)` ist eine Fabrik-Funktion: Sie liefert
       eine `cb`-Tabelle zurück, die der Hook bei DCS registriert.
       Dadurch sind LogFile, LogLevel, cDialogLoader, cSkin, Ui, cBICclass im
       Closure gefangen – der Hook muss diese nicht kennen.

    3. CHILDS: Dictionary mit logischen Namen → Element-Name im
       .dlg-File. Wir iterieren darüber statt Strings hart zu
       kodieren, weil wir mehrere Elemente gleich behandeln
       (sichtbar/unsichtbar schalten).

    4. Skin-Trick: oBicWindow wird NIE mit setVisible(false) ver-
       steckt, weil DCS dann den Hotkey-Callback deaktiviert (Lektion
       aus dem Scratchpad). Stattdessen setzen wir einen 
       unsichtbaren Skin (`windowSkinChatMin`) und blenden die
       Kindelemente aus. Die Hotkey-Registrierung bleibt aktiv.
]]

--[[
    create_callbacks(LogFile, cDialogLoader, cSkin, Ui, cBICclass)
    ----------------------------------------------------------------
    Fabrik für die DCS-User-Callbacks. Wird vom Hook einmal beim
    Laden aufgerufen und liefert eine Tabelle mit Callback-Funktionen
    zurück, die DCS bei Bedarf aufruft.

    Parameter:
        LogFile        – Logfile-Pfad (wird an alle Subfunktionen
                         durchgereicht, damit diese unabhängig vom
                         Hook-Kontext loggen können).
        cDialogLoader  – Modul, das .dlg-Dateien in Dialog-Objekte
                         verwandelt (via spawnDialogFromFile).
        cSkin          – Modul mit Skin-Definitionen
                         (windowSkin, windowSkinChatMin).
        Ui             – Pfad zur .dlg-Datei (vom Hook aufgelöst).
        cBICclass      – Datenmodul (im aktuellen Stand ungenutzt,
                         ist aber für die spätere Übergabe der
                         TAS/Distanz/Count-Werte an die UI vorgesehen).

    Rückgabe:
        cb – Tabelle mit der Funktion `onActivatePlane(unitType)`,
             die der Hook bei DCS.setUserCallbacks() registriert.
]]
local function create_callbacks(LogFile, cDialogLoader, cSkin, Ui, cBICclass)
    -- Rückgabe-Tabelle: Wird am Ende mit cb.onActivatePlane befüllt und
    -- an den Hook zurückgegeben, der sie bei DCS.setUserCallbacks() einträgt.
    local cb = {}

    -- Closure-Variable für das BIC-Dialogfenster.
    -- nil bedeutet: das Fenster wurde noch nicht erzeugt.
    -- Wird in init_window() befüllt und in onActivatePlane() auf nil gesetzt,
    -- wenn ein anderes Flugzeug als die F-4E aktiviert wird.
    local oBicWindow

    -- Mapping: logischer Name → Element-Name im .dlg-File.
    -- Alle UI-Kindelemente, die beim Sichtbarkeits-Umschalten betroffen sind,
    -- stehen hier zentral. Neue Felder müssen nur hier eingetragen werden,
    -- switch_window_children() iteriert automatisch darüber.
	local CHILDS = {
    	labelTAS = "labelTAS",
		inputTAS = "inputTAS",
		labelDist = "labelDist",
		inputDist = "inputDist",
        unitButton = "unitButton",
		labelBombs = "labelBombs",
		inputBombs = "inputBombs",
		labelResult = "labelResult",
		outputResult = "outputResult",
		calcButton = "calcButton",
		closeButton = "closeButton",
	}

    local ERROR_CHILDS = {
        errorTAS = "errorTAS",
        errorDist = "errorDist",
        errorBombs = "errorBombs",
    }

    --[[
        switch_window_children()
        ----------------------------------------------------------------
        Setzt die Sichtbarkeit aller Kindelemente gemäß IS_VISIBLE.
        Wird nach jedem Wechsel des Fensterzustands (switch_window)
        aufgerufen, damit Labels, Eingabe- und Ausgabefelder sowie
        Buttons synchron mit dem Fenster-Skin ein- oder ausgeblendet
        werden.

        Warum separat von switch_window?
        - switch_window ändert den Skin und IS_VISIBLE.
        - switch_window_children liest IS_VISIBLE dann nur noch ab.
        - Diese Trennung erlaubt es, die Kinder auch aus init_window()
          heraus in den Ausgangszustand (versteckt) zu versetzen, ohne
          den Skin anzufassen.
    ]]
	local function switch_window_children()

		dbg_log(LogFile, LogLevel.info, "switch_window_children")
        -- Alle Kindelemente auf den aktuellen Sichtbarkeitsstatus setzen.
        -- key wird nicht genutzt, name ist der .dlg-Element-Name.
		for key, name in pairs(CHILDS) do
    		oBicWindow:findByName(name):setVisible(IS_VISIBLE)
		end

	end

    --[[
        switch_window()
        ----------------------------------------------------------------
        Schaltet das BIC-Fenster zwischen sichtbar und versteckt um.
        Wird als Hotkey-Callback (LShift+LCtrl+B) und als Change-
        Callback des Close-Buttons registriert.

        Skin-Trick (statt setVisible):
        - setVisible(false) würde den Hotkey-Callback deaktivieren.
          DCS deregistriert Callbacks von unsichtbaren Fenstern.
        - Deshalb bleibt das Fenster technisch immer sichtbar.
          Stattdessen wird zwischen zwei Skins gewechselt:
            • windowSkinChatMin → nahezu unsichtbarer Skin (≈ versteckt)
            • windowSkin        → normaler, sichtbarer Skin
        - Kindelemente werden ebenfalls ein-/ausgeblendet (switch_window_children),
          damit der Nutzer keine Phantomfelder sieht.
        - setHasCursor steuert, ob das Fenster Mausklicks entgegennimmt.
          Im versteckten Zustand false, damit Klicks nicht versehentlich
          abgefangen werden.
    ]]
    local function switch_window()

        if IS_VISIBLE then
            -- Fenster verstecken: unsichtbarer Skin, kein Cursor, Kinder ausblenden.
            oBicWindow:setSkin(cSkin.windowSkinChatMin())
			oBicWindow:setHasCursor(false)
			IS_VISIBLE = false
			switch_window_children()
			dbg_log(LogFile, LogLevel.info, "switch_window: not visible")
        else
            -- Fenster zeigen: normaler Skin, Cursor aktivieren, Kinder einblenden.
            oBicWindow:setSkin(cSkin.windowSkin())
			oBicWindow:setHasCursor(true)
            IS_VISIBLE = true
			switch_window_children()
			dbg_log(LogFile, LogLevel.info, "switch_window: is visible")
        end

    end

    --[[
        on_calculate()
        ----------------------------------------------------------------
        Liest die drei Eingabefelder aus und loggt die Werte.
        Wird als Change-Callback des Berechnen-Buttons registriert.

        Aktueller Stand: Nur Auslesen und Loggen – die eigentliche
        Berechnung (TAS → Intervall) ist noch nicht implementiert.
        cBICclass ist als späterer Empfänger der Werte vorgesehen.

        Eingabefelder:
            inputTAS   – True Airspeed in Knoten
            inputDist  – Abwurfabstand in Nautischen Meilen
            inputBombs – Anzahl der Bomben
    ]]
    local function set_error(name, state)
        oBicWindow:findByName(name):setVisible(state)
    end

	local function on_calculate()
        local okTAS = cBICclass:setKnots(oBicWindow:findByName(CHILDS.inputTAS):getText())
        set_error(ERROR_CHILDS.errorTAS, not okTAS)
        local okDist = cBICclass:setDistance(oBicWindow:findByName(CHILDS.inputDist):getText())
        set_error(ERROR_CHILDS.errorDist, not okDist)
        local okBombs = cBICclass:setBombCount(oBicWindow:findByName(CHILDS.inputBombs):getText())
        set_error(ERROR_CHILDS.errorBombs, not okBombs)

        if not okTAS or not okDist or not okBombs then
            return
        end

        cBICclass:calculate()
	end

    --[[
        keyboard_input()
        ----------------------------------------------------------------
        Toggelt den Tastatursperr-Zustand für Text-Eingabefelder.
        Wird als Focus-Callback aller drei Eingabefelder (TAS, Dist,
        BombCount) registriert. DCS ruft ihn auf, wenn ein Textfeld den
        Fokus erhält ODER verliert – es gibt keinen separaten
        "blur"-Callback.

        Warum Tastatursperre nötig?
        - DCS leitet Tastenanschläge standardmäßig an die Simulation
          weiter (Throttle, Fahrwerk, etc.). Ohne Sperre landet jeder
          Buchstabe sowohl im Textfeld als auch als Steuerbefehl im
          Cockpit.
        - DCS.lockKeyboardInput(keyboardEvents) sperrt eine Liste von
          Tasten für die Simulation; Eingaben landen dann NUR im Textfeld.

        Chat-Hotkeys werden bewusst NICHT gesperrt:
        - Würden Chat-Tasten gesperrt, kann der Chat-Dialog nicht mehr
          geöffnet werden. In Kombination mit dem Scratchpad entsteht
          ein Deadlock: Chat kann nicht geschlossen werden, und fast alle
          Tastatureingaben funktionieren nicht mehr.
        - removeCommandEvents() entfernt daher Chat-Tasten aus der
          Sperrliste. Dieser Ansatz ist aus mul_chat.lua übernommen.

        KEYBOARDLOCK-Flag:
        - Verhindert, dass bei schnellem Fokus-Wechsel zwischen Feldern
          DCS.lockKeyboardInput mehrfach hintereinander aufgerufen wird,
          was die internen Zähler von DCS durcheinander bringen kann.
    ]]
	local function keyboard_input()
        if KEYBOARDLOCK then
            -- Tastatur war gesperrt → Sperre aufheben.
            -- Der Parameter `true` bei unlockKeyboardInput signalisiert DCS,
            -- alle gesperrten Tasten freizugeben.
			---@diagnostic disable-next-line: undefined-global
            DCS.unlockKeyboardInput(true)
            KEYBOARDLOCK = false
			dbg_log(LogFile, LogLevel.info, "Textfeld Fokus nicht aktiv")

		else

            -- Alle Tasten der angeschlossenen Tastatur holen.
	        local keyboardEvents = cInput.getDeviceKeys(cInput.getKeyboardDeviceName())
            -- DCS-Aktionsumgebung: Enthält alle bekannten UI-Aktionen inkl.
            -- der Chat-Befehle, die wir aus der Sperrliste entfernen müssen.
	        local inputActions = cInput.getEnvTable().Actions

            -- Chat-Hotkeys aus der Sperrliste entfernen.
            -- Verhindert den Chat-Deadlock (siehe Funktions-Doku oben).
            -- Kopiert aus mul_chat.lua.
	        local removeCommandEvents = function(commandEvents)
    	        for i, commandEvent in ipairs(commandEvents) do
                    -- Rückwärts iterieren, damit table.remove den Index
                    -- der noch nicht geprüften Einträge nicht verschiebt.
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
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(inputActions.iCommandChat))
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(inputActions.iCommandAllChat))
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(inputActions.iCommandFriendlyChat))
        	removeCommandEvents(cInput.getUiLayerCommandKeyboardKeys(inputActions.iCommandChatShowHide))

            -- Verbleibende Tasten für die Simulation sperren, damit sie
            -- ausschließlich in die Textfelder fließen.
			---@diagnostic disable-next-line: undefined-global
        	DCS.lockKeyboardInput(keyboardEvents)
        	KEYBOARDLOCK = true

			dbg_log(LogFile, LogLevel.info, "Textfeld Fokus aktiv")

        end
    end

    local function switch_unit()
        local oUnitButton = oBicWindow:findByName(CHILDS.unitButton)
        if oUnitButton:getText() == "nm" then
            oUnitButton:setText("ft")
        else
            oUnitButton:setText("nm")
        end
    end
    --[[
        init_window()
        ----------------------------------------------------------------
        Erstellt das BIC-Dialogfenster und registriert alle Callbacks.
        Wird genau einmal aus onActivatePlane() heraus aufgerufen,
        wenn das erste Mal eine F-4E aktiviert wird und oBicWindow
        noch nil ist.

        Reihenfolge:
        1. Dialog aus der .dlg-Datei laden (spawnDialogFromFile).
        2. Fenster auf visible=true setzen – DCS-Pflicht, damit
           Hotkey-Callbacks registriert werden können.
        3. Hotkey-Callback für den Toggle-Shortcut eintragen.
        4. Skin auf windowSkinChatMin setzen → Fenster startet unsichtbar.
        5. Callbacks für Close-Button, Berechnen-Button und die drei
           Eingabefelder registrieren.
        6. switch_window_children() aufrufen → alle Kinder auf
           IS_VISIBLE=false setzen (Startzustand: alles versteckt).
    ]]
    local function init_window()

        -- Dialog-Objekt aus der .dlg-Datei erzeugen. Ab jetzt ist
        -- oBicWindow nicht mehr nil und alle find-/set-Methoden verfügbar.
    	oBicWindow = cDialogLoader.spawnDialogFromFile(Ui)
    	dbg_log(LogFile, LogLevel.info, "oBicWindow: "..tostring(oBicWindow))

        -- Muss true sein, bevor Hotkeys registriert werden können.
        -- DCS ignoriert addHotKeyCallback auf unsichtbaren Fenstern.
		oBicWindow:setVisible(true)
    	dbg_log(LogFile, LogLevel.info, "oBicWindow:setVisible(true)")

        -- Tastenkombination LShift+LCtrl+B schaltet das Fenster um.
        -- Der Callback (switch_window) ist im Closure gefangen und
        -- hat dadurch Zugriff auf oBicWindow, IS_VISIBLE und cSkin.
		oBicWindow:addHotKeyCallback("left shift+left ctrl+b", switch_window)
    	dbg_log(LogFile, LogLevel.info, "oBicWindow:addChangeCallback: "..tostring(oBicWindow.addHotKeyCallback))
		dbg_log(LogFile, LogLevel.info, "oBicWindow: Callback :addHotKeyCallback für switch_window registriert")

        -- Fenster sofort mit dem Mini-Skin starten → optisch unsichtbar,
        -- aber technisch sichtbar (Hotkey bleibt registriert).
		oBicWindow:setSkin(cSkin.windowSkinChatMin())
    	dbg_log(LogFile, LogLevel.info, "oBicWindow: setSkin windowSkinChatMin()")

        -- Close-Button: Klick ruft switch_window auf → versteckt das Fenster.
        -- addChangeCallback wird bei Button-Zustandsänderung (Pressed) gefeuert.
		local oCloseButton = oBicWindow:findByName(CHILDS.closeButton)
		oCloseButton:addChangeCallback(switch_window)
		dbg_log(LogFile, LogLevel.info, "oCloseButton:addChangeCallback: "..tostring(oCloseButton.addChangeCallback))
		dbg_log(LogFile, LogLevel.info, "oCloseButton: Callback :addChangeCallback für switch_window registriert")

        -- Berechnen-Button: Klick liest Eingabefelder aus und startet
        -- die (noch zu implementierende) Intervall-Berechnung.
		local oCalculateButton = oBicWindow:findByName("calcButton")
		oCalculateButton:addChangeCallback(on_calculate)
		dbg_log(LogFile, LogLevel.info, "oCalculateButton:addChangeCallback: "..tostring(oCalculateButton.addChangeCallback))
		dbg_log(LogFile, LogLevel.info, "oCalculateButton: Callback :addChangeCallback für on_calculate registriert")

        -- Alle drei Eingabefelder bekommen denselben Focus-Callback.
        -- DCS ruft ihn beim Fokus-Erhalt UND beim Fokus-Verlust auf.
        -- keyboard_input() erkennt anhand von KEYBOARDLOCK, welcher Fall vorliegt.
		local oInputTAS = oBicWindow:findByName(CHILDS.inputTAS)
		oInputTAS:addFocusCallback(keyboard_input)
		dbg_log(LogFile, LogLevel.info, "oInputTAS:addFocusCallback: "..tostring(oInputTAS.addFocusCallback))
		dbg_log(LogFile, LogLevel.info, "oInputTAS: Callback :addFocusCallback für keyboard_input registriert")

		local oInputDIS = oBicWindow:findByName(CHILDS.inputDist)
		oInputDIS:addFocusCallback(keyboard_input)
		dbg_log(LogFile, LogLevel.info, "oInputDIS:addFocusCallback: "..tostring(oInputDIS.addFocusCallback))
		dbg_log(LogFile, LogLevel.info, "oInputDIS: Callback :addFocusCallback für keyboard_input registriert")

        local oUnitButton = oBicWindow:findByName(CHILDS.unitButton)
        oUnitButton:addChangeCallback(switch_unit)
        dbg_log(LogFile, LogLevel.info, "oUnitButton:addChangeCallback: "..tostring(oUnitButton.addChangeCallback))
        dbg_log(LogFile, LogLevel.info, "oUnitButton: Callback :addChangeCallback für switch_unit registriert")

		local oInputBCOUNT = oBicWindow:findByName(CHILDS.inputBombs)
		oInputBCOUNT:addFocusCallback(keyboard_input)
		dbg_log(LogFile, LogLevel.info, "oInputBCOUNT:addFocusCallback: "..tostring(oInputBCOUNT.addFocusCallback))
		dbg_log(LogFile, LogLevel.info, "oInputBCOUNT: Callback :addFocusCallback für keyboard_input registriert")

        -- Alle Kinder initial auf IS_VISIBLE=false setzen → Startzustand versteckt.
		switch_window_children()

end

    --[[
        cb.onActivatePlane(unitType)
        ----------------------------------------------------------------
        DCS-Callback: Wird aufgerufen, wenn der Spieler ein Flugzeug
        aktiviert (Slot wechselt oder Mission startet).

        Parameter:
            unitType – DCS-interner Typ-String des aktivierten Flugzeugs
                       (z.B. "F-4E-45MC", "F-16C_50", ...).

        Logik:
        - F-4E aktiv UND Fenster existiert noch nicht → init_window().
          Das stellt sicher, dass das Fenster genau einmal erzeugt wird,
          auch wenn onActivatePlane mehrfach für die F-4E gefeuert wird.
        - Anderes Flugzeug aktiv UND Fenster existiert → aufräumen:
          setVisible(false), destroy(), oBicWindow = nil.
          Das gibt den DCS-Speicher für das Dialog-Objekt frei und
          setzt die Closure-Variable zurück, damit beim nächsten
          F-4E-Slot wieder init_window() ausgeführt wird.
        - Anderes Flugzeug aktiv UND kein Fenster → nichts tun
          (elseif greift nur wenn oBicWindow ~= nil).
    ]]
    function cb.onActivatePlane(unitType)

		dbg_log(LogFile, LogLevel.info, "[CB] onActivatePlane unitType=" .. tostring(unitType))
		if unitType == "F-4E-45MC" then
            -- F-4E aktiviert: Fenster nur beim ersten Mal erzeugen.
        	if not oBicWindow then
            	init_window()
			end
		elseif oBicWindow then
            -- Anderes Flugzeug aktiviert: Fenster zerstören und Closure zurücksetzen.
			oBicWindow:setVisible(false)
			oBicWindow:destroy()
			oBicWindow = nil
		end

    end

    -- Tabelle mit dem registrierten Callback zurückgeben.
    -- Der Hook übergibt diese Tabelle an DCS.setUserCallbacks().
    return cb
end

return {
	LogLevel = LogLevel,
	check_paths = check_paths,
	check_files = check_files,
	log_rotate = log_rotate,
	dbg_log = dbg_log,
	chk_require = chk_require,
	create_callbacks = create_callbacks,
}