local BicClass = {
    isVisible       = false,    --boolean
    knots           = 0,        --integer min 200 max 1000
    distance        = 0,        --integer
    disUnit         = "nm",     --string ft or nm
    bombCount       = 0,        --integer min 2

    setVisible      = function(self, a)
        if (type(a) ~= "boolean") then
            return false
        end
        self.isVisible = a
    end,
    getVisible      = function(self)
        return self.isVisible
    end,
    setKnots        = function(self, a)
        if not (type(a) == "number") or (a < 200) or (a > 1000) then
            return false
        end
        self.knots = a
    end,
    getKnots        = function(self)
        return self.knots
    end,
    setDistance     = function(self, a)
        if not (type(a) == "number") then
            return false
        end
        self.distance = a
    end,
    getDistance     = function(self)
        return self.distance
    end,
    setUnit         = function(self, a)
        if (type(a) ~= "string") or (a ~= "ft" and a ~= "nm") then
            return false
        end
        self.disUnit = a
    end,
    getUnit         = function(self)
        return self.disUnit
    end,
    setBombCount    = function(self, a)
        if type(a) ~= "number" or a < 2 or a > 21 then
            return false
        end
        self.bombCount = a
    end,
    getBombCount    = function(self)
        return self.bombCount
    end,
}

return BicClass