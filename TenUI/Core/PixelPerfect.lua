local _, ns = ...

local Pixel = {}
ns.Pixel = Pixel

local physicalPixel = 768 / 1080
local edges = setmetatable({}, { __mode = "k" })

local function refreshResolution()
    local _, height = GetPhysicalScreenSize()
    if height and height > 0 then physicalPixel = 768 / height end
end

function Pixel.Size(frame, pixels)
    local scale = frame:GetEffectiveScale()
    if issecretvalue and issecretvalue(scale) or type(scale) ~= "number" or scale <= 0 then
        scale = UIParent:GetEffectiveScale()
    end
    return pixels * physicalPixel / scale
end

function Pixel.Snap(frame, value)
    local step = Pixel.Size(frame, 1)
    return math.floor(value / step + 0.5) * step
end

-- Align a centered extent against the parent's actual origin. Either extent
-- can occupy an odd number of physical pixels.
function Pixel.SnapOffset(frame, offset, fraction, extent, parentExtent)
    local px = Pixel.Size(frame, 1)
    local edge = offset + fraction * (parentExtent - extent)
    return offset + math.floor(edge / px + 0.5) * px - edge
end

function Pixel.ConfigureTexture(texture)
    texture:SetSnapToPixelGrid(false)
    texture:SetTexelSnappingBias(0)
end

local function applyEdge(texture, edge)
    local size = Pixel.Size(edge.frame, edge.pixels)
    if edge.horizontal then texture:SetHeight(size) else texture:SetWidth(size) end
end

function Pixel.Edge(texture, frame, horizontal, pixels)
    local edge = { frame = frame, horizontal = horizontal, pixels = pixels or 1 }
    Pixel.ConfigureTexture(texture)
    applyEdge(texture, edge)
    edges[texture] = edge
end

function Pixel.RefreshEdges()
    refreshResolution()
    for texture, edge in pairs(edges) do
        pcall(applyEdge, texture, edge)
    end
end

function Pixel.SetFont(region, font, size, flags)
    if flags == "GLOBAL" then flags = ns:GetGlobalStyle().outline or "OUTLINE" end
    if type(flags) ~= "string" then flags = "" end
    local slug = flags and flags:find("SLUG", 1, true) and flags
        or (flags and flags ~= "" and flags .. ", SLUG" or "SLUG")
    local ok, applied = pcall(region.SetFont, region, font, size, slug)
    if ok and applied ~= false then return applied end
    return region:SetFont(font, size, flags)
end

refreshResolution()
for _, event in ipairs({ "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    ns:RegisterEvent(event, Pixel.RefreshEdges)
end
