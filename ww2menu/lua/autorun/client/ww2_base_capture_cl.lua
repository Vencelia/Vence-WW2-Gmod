
-- ww2_base_capture_cl.lua (v2) — HUD igual en discurso al cap point
if SERVER then return end

local colReich  = Color(80,150,255)
local colUSSR   = Color(220,60,60)
local colBorder = Color(0,0,0,220)
local colBarBG  = Color(30,30,35,230)

local function GetLocalSide()
    local lp = LocalPlayer()
    if not IsValid(lp) then return "" end
    return lp:GetNWString("ww2_faction","")
end

local function LocalPlayerNearBase()
    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    local best, bestd2 = nil, 1e20
    for _, cls in ipairs({"ww2_base_reich","ww2_base_ussr"}) do
        for _, ent in ipairs(ents.FindByClass(cls) or {}) do
            if IsValid(ent) then
                local rad = ent:GetNW2Int("cap_radius", 1000)
                local d2 = lp:GetPos():DistToSqr(ent:GetPos())
                if d2 <= (rad*rad) and d2 < bestd2 then
                    best, bestd2 = ent, d2
                end
            end
        end
    end
    return best
end

local function TitleForBase(ent)
    local base_side = ent:GetNW2String("base_side","")
    local captured  = ent:GetNW2String("cap_captured_by","")
    local baseTitle = (base_side == "reich") and "BASE TERCER REICH" or "BASE SOVIETICA"
    if captured ~= "" and captured ~= base_side then
        if captured == "reich" then
            return baseTitle .. " CAPTURADA POR EL REICH", colReich
        else
            return baseTitle .. " CAPTURADA POR LA URSS", colUSSR
        end
    end
    return baseTitle, (base_side == "reich") and colReich or colUSSR
end

hook.Add("HUDPaint", "WW2_BaseCaptureHUD", function()
    local base = LocalPlayerNearBase()
    if not IsValid(base) then return end

    local control  = base:GetNW2Float("cap_control", 0)
    local contested = base:GetNW2Bool("cap_contested", false)
    local title, titleCol = TitleForBase(base)

    local w, h = ScrW(), ScrH()
    local barW, barH = math.floor(w*0.34), math.floor(h*0.028)
    local x, y = math.floor((w - barW)/2), math.floor(h*0.08)

    surface.SetDrawColor(colBarBG)  surface.DrawRect(x, y, barW, barH)
    surface.SetDrawColor(colBorder) surface.DrawOutlinedRect(x, y, barW, barH, 2)

    local frac = (control + 1) / 2
    local fillW = math.floor(barW * frac)
    surface.SetDrawColor(titleCol) surface.DrawRect(x, y, fillW, barH)

    draw.SimpleText(title, "Trebuchet24", w/2, y - 18, titleCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    if contested then
        draw.SimpleText("CONTESTADA", "Trebuchet18", w/2, y + barH + 4, Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end)
