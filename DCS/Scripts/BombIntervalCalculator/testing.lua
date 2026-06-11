--[[
testing.lua

Spielplatz zum Testen der BIC-Klasse.
Lädt die Klassendefinition aus BIC-class.lua, erzeugt eine Instanz
und prüft alle Getter/Setter auf erfolgreiche und fehlgeschlagene Fälle.
--]]

-- Klassendefinition aus eigener Datei laden.
-- require sucht die Datei im package.path und führt sie aus.
-- Der Rückgabewert von require ist das, was die Datei am Ende zurückgibt
-- (also der Wert hinter dem optionalen return am Ende der Datei).
local cBicClass = require("BIC-class")

-- Eine Instanz der Klasse erzeugen.
-- Da BIC-class.lua aktuell die Felder direkt am Klassen-Table definiert,
-- machen wir eine flache Kopie. So hat jede Instanz eigene Werte,
-- teilt sich aber die Funktionsdefinitionen (die mit self arbeiten).
local function newInstance()
    local obj = {}
    for k, v in pairs(cBicClass) do
        obj[k] = v
    end
    return obj
end

local OBJECT1 = newInstance()
local OBJECT2 = newInstance()

-- Tests laufen auf OBJECT
local function runTests(obj)
    -- Test setVisible / getVisible
    assert(obj:setVisible(true) ~= false, "FAIL setVisible(true)")
    assert(obj:getVisible() == true, "FAIL getVisible() nach true")
    assert(obj:setVisible(false) ~= false, "FAIL setVisible(false)")
    assert(obj:getVisible() == false, "FAIL getVisible() nach false")
    assert(obj:setVisible("ja") == false, "FAIL setVisible(string) sollte scheitern")
    assert(obj:getVisible() == false, "FAIL getVisible() nach ungültigem Setzen")

    -- Test setKnots / getKnots
    assert(obj:setKnots(450) ~= false, "FAIL setKnots(450)")
    assert(obj:getKnots() == 450, "FAIL getKnots() nach 450")
    assert(obj:setKnots(200) ~= false, "FAIL setKnots(200) Grenze unten")
    assert(obj:setKnots(1000) ~= false, "FAIL setKnots(1000) Grenze oben")
    assert(obj:setKnots(199) == false, "FAIL setKnots(199) sollte scheitern")
    assert(obj:setKnots(1001) == false, "FAIL setKnots(1001) sollte scheitern")
    assert(obj:setKnots("schnell") == false, "FAIL setKnots(string) sollte scheitern")
    assert(obj:getKnots() == 1000, "FAIL getKnots() sollte letzten gültigen Wert halten")

    -- Test setDistance / getDistance
    assert(obj:setDistance(5) ~= false, "FAIL setDistance(5)")
    assert(obj:getDistance() == 5, "FAIL getDistance() nach 5")
    assert(obj:setDistance(0) ~= false, "FAIL setDistance(0)")
    assert(obj:setDistance(-3) ~= false, "FAIL setDistance(-3) (kein Min definiert)")
    assert(obj:setDistance("weit") == false, "FAIL setDistance(string) sollte scheitern")

    -- Test setUnit / getUnit
    assert(obj:setUnit("ft") ~= false, "FAIL setUnit('ft')")
    assert(obj:getUnit() == "ft", "FAIL getUnit() nach ft")
    assert(obj:setUnit("nm") ~= false, "FAIL setUnit('nm')")
    assert(obj:setUnit("km") == false, "FAIL setUnit('km') sollte scheitern")
    assert(obj:setUnit(123) == false, "FAIL setUnit(number) sollte scheitern")
    assert(obj:getUnit() == "nm", "FAIL getUnit() nach ungültigem Versuch")

    -- Test setBombCount / getBombCount
    assert(obj:setBombCount(2) ~= false, "FAIL setBombCount(2) Grenze unten")
    assert(obj:setBombCount(21) ~= false, "FAIL setBombCount(21) Grenze oben")
    assert(obj:getBombCount() == 21, "FAIL getBombCount() nach 21")
    assert(obj:setBombCount(1) == false, "FAIL setBombCount(1) sollte scheitern")
    assert(obj:setBombCount(22) == false, "FAIL setBombCount(22) sollte scheitern")
    assert(obj:setBombCount("drei") == false, "FAIL setBombCount(string) sollte scheitern")
    assert(obj:getBombCount() == 21, "FAIL getBombCount() sollte letzten gültigen Wert halten")

    print("Alle Tests bestanden.")
end

runTests(OBJECT1)
runTests(OBJECT2)

OBJECT1:setVisible(true)
print(tostring(OBJECT1:getVisible()))
