local BicClass = {
    knots           = 0,        --integer min 200 max 1000
    distance        = 0,        --integer min 0.1nm, max 2.0nm  - min 650ft, max 12500ft
    disUnit         = "nm",     --string ft or nm
    bombCount       = 0,        --integer min 2
    interval        = 0,        --integer min 0.05s, max 10.00s

    setKnots        = function(self, a)

        if (type(a) ~= "number") or (a < 200) or (a > 1000) then
            return false
        end
        self.knots = a
        return true
    end,

    getKnots        = function(self)
        return self.knots
    end,

    setDistance     = function(self, a, unit)
        if type(a) ~= "number" then
            return false
        end
        if unit == "nm" then
            if a < 0.1 or a > 2.0 then
                return false
            end
        elseif unit == "ft" then
            if a < 650 or a > 12500 then
                return false
            end
        end
        self.distance = a
        self.disUnit  = unit
        return true
    end,

    getDistance     = function(self)
        return self.distance
    end,

    setUnit         = function(self, a)
        if (type(a) ~= "string") or (a ~= "ft" and a ~= "nm") then
            return false
        end
        self.disUnit = a
        return true
    end,

    getUnit         = function(self)
        return self.disUnit
    end,

    setBombCount    = function(self, a)
        if (type(a) ~= "number") or (a < 2) or (a > 21) then
            return false
        end
        self.bombCount = a
        return true
    end,

    getBombCount    = function(self)
        return self.bombCount
    end,

    getInterval     = function(self)
        return self.interval
    end,

    calculate = function(self)
        local interval = 0
        if self.disUnit == "nm" then
            interval = (self.distance / self.knots) * 3600
        elseif self.disUnit == "ft" then
            interval = (self.distance / (self.knots * 6076.12)) * 3600
        end
        self.interval = math.floor((interval / (self.bombCount - 1)) * 100 + 0.5) / 100

        if (self.interval < 0.05) or (self.interval > 10.00) then
            return false
        end

        return self.interval
    end,
}

return BicClass