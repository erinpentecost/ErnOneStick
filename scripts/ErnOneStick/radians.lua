local util = require('openmw.util')

local phi = 2 * math.pi
local eps = 1e-12

local function subtract(a, b)
    local s = util.normalizeAngle(a)
    local e = util.normalizeAngle(b)

    -- compute diff in [0, 2pi)
    local diff = (e - s) % phi

    -- if > pi, go the negative way (diff - 2pi)
    if diff > math.pi then
        diff = diff - phi
    elseif math.abs(diff - math.pi) < eps then
        -- tie (exact half-turn): choose the positive rotation (+pi)
        diff = math.pi
    end
    return diff
end

local function anglesAlmostEqual(a, b, tol)
    tol = tol or 1e-12
    return math.abs(subtract(a, b)) < tol
end

local function lerpAngle(startAngle, endAngle, t)
    local s = util.normalizeAngle(startAngle)
    local e = util.normalizeAngle(endAngle)

    -- compute diff in [0, 2pi)
    local diff = (e - s) % phi

    -- if > pi, go the negative way (diff - 2pi)
    if diff > math.pi then
        diff = diff - phi
    elseif math.abs(diff - math.pi) < eps then
        -- tie (exact half-turn): choose the positive rotation (+pi)
        diff = math.pi
    end

    local result = s + diff * t
    return util.normalizeAngle(result)
end

-- Tests (corrected expectations and modular comparisons)
local tests = {
    { name = "No change (t=0)",                  start = 0,               finish = math.pi / 2,      t = 0,   expected = 0 },
    { name = "Exact end (t=1)",                  start = 0,               finish = math.pi / 2,      t = 1,   expected = math.pi / 2 },
    { name = "Midway short path",                start = 0,               finish = math.pi / 2,      t = 0.5, expected = math.pi / 4 },
    { name = "Wrap around (cross -pi to pi)",    start = 3 * math.pi / 4, finish = -3 * math.pi / 4, t = 0.5, expected = math.pi },     -- canonical +pi
    { name = "Half-turn tie case",               start = 0,               finish = math.pi,          t = 0.5, expected = math.pi / 2 }, -- tie -> positive direction
    { name = "Negative to positive across wrap", start = -math.pi + 0.1,  finish = math.pi - 0.1,    t = 0.5, expected = math.pi }      -- canonical +pi (equivalent to -pi)
}

local passed = 0
for _, test in ipairs(tests) do
    local got = lerpAngle(test.start, test.finish, test.t)
    if anglesAlmostEqual(got, test.expected) then
        passed = passed + 1
    else
        error("failed radian test: " .. test.name)
        return
    end
end

return {
    lerpAngle = lerpAngle,
    subtract = subtract,
    anglesAlmostEqual = anglesAlmostEqual,
}
