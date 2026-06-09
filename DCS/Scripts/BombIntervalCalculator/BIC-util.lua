local DEBUG = true
local IS_VISIBLE = false
local cLfs = require("lfs")

local LL = {
    info = "info",
    warn = "warn",
    crit = "crit",
}

local function check_paths(PATHS)
	for _, DIR in ipairs(PATHS) do
		local exists = cLfs.attributes(DIR, "mode")
		if not exists then
			print(LL.crit..": "..DIR..": does not exsist")
			os.exit(1)
		end
	end
end

local function check_files(F)
	for KEY, FILE in pairs(F) do
		local f = io.open(FILE, "r")
		if not f then
			print(LL.crit..": "..FILE..": not found")
			if KEY ~= "Log" then
				os.exit(1)
			end
		else
			f:close()
		end
	end
end

local function log_rotate(LF)
	local f = io.open(LF, "r")
	if f then
		f:close()
		os.remove(LF .. ".old")
		os.rename(LF, LF .. ".old")
	end
	local n = io.open(LF, "w")
	if n then
		n:flush()
		n:close()
	end
end

local function dbg_log(LF, LEVEL, MESSAGE)
	if not LF then
		print("LogFile wurde nicht angegeben. Logfile kann nicht geschrieben werden.")
		return false
	end
	if (type(LF) ~= "string") then
		print("LogFile ist kein String: "..tostring(LF).." Logfile kann nicht geschrieben werden.")
		return false
	end

	local LOG = io.open(LF, "a+")
	if not LOG then
		print("LogFile kann nicht geöffnet werden: " .. LF)
		return false
	end

	-- 'info' wird nur bei DEBUG geloggt
	if LEVEL ~= LL.info or DEBUG == true then
		LOG:write(("\n>> :%s ::%s :::%s"):format(
		os.date(),
			tostring(LEVEL),
			tostring(MESSAGE)
		))
	end

	LOG:flush()
	LOG:close()

	if LEVEL == LL.crit then
		LOG:write(("\n>> :%s ::%s :::%s"):format(
		os.date(),
			tostring(LEVEL),
			"Script wird beendet."
		))
		os.exit(1)
	end

	return true
end

local function chk_require(LF, OK, LEVEL, MODULE)
	if not LF then
		print("LogFile wurde nicht angegeben. Logfile kann nicht geschrieben werden.")
		return false
	end
	if (type(LF) ~= "string") then
		print("LogFile ist kein String: "..tostring(LF).." Logfile kann nicht geschrieben werden.")
		return false
	end

	if OK == false then
		dbg_log(LF, LEVEL, MODULE.." konnte nicht geladen werden.")
		return false
	end
	dbg_log(LF, LL.info, MODULE.." wurde geladen.")
end

--[[ Funktionen für Callbacks und Fensterverwaltung ]]

local function create_callbacks(LF, cDialogLoader, cSkin, Ui)
    local cb = {}
    local oBicWindow

	local CHILDREN = {
    	"labelTAS", "inputTAS", "labelDist", "inputDist", "labelBombs", "inputBombs",
    	"labelResult", "outputResult", "calcButton", "closeButton",
	}

	local function switch_window_children()

		for _, name in ipairs(CHILDREN) do
			dbg_log(LF, LL.info, name)
    		oBicWindow:findByName(name):setVisible(IS_VISIBLE)
		end

	end

    local function switch_window()

        if IS_VISIBLE then
            oBicWindow:setSkin(cSkin.windowSkinChatMin())
			IS_VISIBLE = false
			switch_window_children()
			dbg_log(LF, LL.info, "Window Switch: non visible")
        else
            oBicWindow:setSkin(cSkin.windowSkin())
            IS_VISIBLE = true
			switch_window_children()
			dbg_log(LF, LL.info, "Window Switch: visible")
        end

    end

    local function init_window()

    	oBicWindow = cDialogLoader.spawnDialogFromFile(Ui)
    	dbg_log(LF, LL.info, "oBicWindow: " .. tostring(oBicWindow))

		oBicWindow:setVisible(true)
    	dbg_log(LF, LL.info, "setVisible done")

    	-- addHotKeyCallback registriert eine Funktion die DCS aufruft,
		-- sobald die angegebene Tastenkombination gedrückt wird.
		-- Erster Parameter  : die Tastenkombination als String
		-- Zweiter Parameter : die Funktion die aufgerufen werden soll
		--
		-- WICHTIG: switch_window ohne Klammern!
		-- Mit Klammern (switch_window()) würde die Funktion SOFORT ausgeführt
		-- und das Ergebnis (nil) als Callback übergeben – der Hotkey würde
		-- nie funktionieren.
		-- Ohne Klammern (switch_window) wird die Funktion selbst übergeben
		-- und erst beim Tastendruck ausgeführt.
		oBicWindow:addHotKeyCallback("left shift+left ctrl+b", switch_window)
    	dbg_log(LF, LL.info, "switch_window done")

		oBicWindow:setSkin(cSkin.windowSkinChatMin())
    	dbg_log(LF, LL.info, "setSkin done")

		local oCloseButton = oBicWindow:findByName("closeButton")
		dbg_log(LF, LL.info, "addChangeCallback: "..tostring(oCloseButton.addChangeCallback))
		oCloseButton:addChangeCallback(switch_window)

		switch_window()
    	dbg_log(LF, LL.info, "switch_window_children done")

end

    function cb.onSimulationStart()

        if not oBicWindow then
            init_window()
        end

    end

    return cb
end

return {
	LogLevel = LL,
	check_paths = check_paths,
	check_files = check_files,
	log_rotate = log_rotate,
	dbg_log = dbg_log,
	chk_require = chk_require,
	create_callbacks = create_callbacks,
}