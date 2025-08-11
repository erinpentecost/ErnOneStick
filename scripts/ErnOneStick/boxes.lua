local util = require("openmw.util")

local function inBox(position, box)
    local normalized = box.transform:inverse():apply(position)
    return math.abs(normalized.x) <= 1
        and math.abs(normalized.y) <= 1
        and math.abs(normalized.z) <= 1
end

local function fudge(s, e, bonus)
    return s + ((bonus * (e - s)):normalize())
end
