local two_pi = 2 * math.pi
local eps = 1e-12

local function normalize(angle)
    -- normalize into [-pi, pi)
    local a = (angle + math.pi) % two_pi - math.pi
    -- canonicalize -pi -> +pi so we use (-pi, pi]
    if math.abs(a + math.pi) < eps then
        return math.pi
    end
    return a
end

local function angleDiff(a, b)
    -- signed shortest difference a - b in (-pi, pi]
    local d = (a - b) % two_pi
    if d > math.pi then d = d - two_pi end
    -- map small numerical -pi to +pi for consistency
    if math.abs(d + math.pi) < eps then
        return math.pi
    end
    return d
end

local function anglesAlmostEqual(a, b, tol)
    tol = tol or 1e-12
    return math.abs(angleDiff(a, b)) < tol
end

local function subtract(a, b)
    local s = normalize(a)
    local e = normalize(b)

    -- compute diff in [0, 2pi)
    local diff = (e - s) % two_pi

    -- if > pi, go the negative way (diff - 2pi)
    if diff > math.pi then
        diff = diff - two_pi
    elseif math.abs(diff - math.pi) < eps then
        -- tie (exact half-turn): choose the positive rotation (+pi)
        diff = math.pi
    end
    return diff
end

local function lerpAngle(startAngle, endAngle, t)
    local s = normalize(startAngle)
    local e = normalize(endAngle)

    -- compute diff in [0, 2pi)
    local diff = (e - s) % two_pi

    -- if > pi, go the negative way (diff - 2pi)
    if diff > math.pi then
        diff = diff - two_pi
    elseif math.abs(diff - math.pi) < eps then
        -- tie (exact half-turn): choose the positive rotation (+pi)
        diff = math.pi
    end

    local result = s + diff * t
    return normalize(result)
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
        --print("✔ PASS:", test.name)
        passed = passed + 1
    else
        error("failed radian test: " .. test.name)
        return
    end
end

return {
    normalize = normalize,
    lerpAngle = lerpAngle,
    subtract = subtract,
    anglesAlmostEqual = anglesAlmostEqual,
}
