local function noop() end
local ns = { RegisterModule = noop, RegisterEvent = noop, RegisterMessage = noop }
IsPlayerSpell = function() return false end
GetPhysicalScreenSize = function() return 1920, 1080 end
assert(loadfile("TenUI/Modules/CastBar.lua"))("TenUI", ns)
assert(loadfile("TenUI/Core/PixelPerfect.lua"))("TenUI", ns)

local function near(a, b)
    assert(math.abs(a - b) < 0.000001, ("expected %f, got %f"):format(b, a))
end

local cadence = {}
local function checkMarks(start, duration, guid, expected)
    local ticks = ns.CastBar:GetChannelTickFractions(356995, duration, start, guid, cadence)
    assert(#ticks == #expected)
    for i, mark in ipairs(expected) do near(ticks[i], mark) end
end
checkMarks(10, 3, "first", { 2/3, 1/3 })
checkMarks(12.4, 3.6, "second", { 5/6, 5/9, 5/18 })
checkMarks(12.4, 3.6, "second", { 5/6, 5/9, 5/18 })
checkMarks(20, 3, "third", { 2/3, 1/3 })

for _, scale in ipairs({ 0.7, 1, 1.25 }) do
    local frame = { GetEffectiveScale = function() return scale end }
    local px = ns.Pixel.Size(frame, 1)
    for _, fraction in ipairs({ 0, 0.5, 1 }) do
        for _, width in ipairs({ 99, 100 }) do
            local extent = width * px
            local parent = 641 * px
            local offset = ns.Pixel.SnapOffset(frame, -2.25, fraction, extent, parent)
            local edge = (offset + fraction * (parent - extent)) / px
            near(edge, math.floor(edge + 0.5))
            near(ns.Pixel.SnapOffset(frame, offset, fraction, extent, parent), offset)
        end
    end
end
print("PASS channel recasts, duplicate updates, pixel alignment and repeated rescaling")
