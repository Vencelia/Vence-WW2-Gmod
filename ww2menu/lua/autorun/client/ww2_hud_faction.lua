if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

-- Fallback por si el shared no define nombres/colores
local Names = WW2 and WW2.FactionNames or {
    [WW2 and WW2.FACCION and WW2.FACCION.REICH or "reich"] = "TERCER REICH",
    [WW2 and WW2.FACCION and WW2.FACCION.USSR or "ussr"]   = "UNION SOVIETICA",
}
local Colors = WW2 and WW2.FactionColors or {
    [WW2 and WW2.FACCION and WW2.FACCION.REICH or "reich"] = Color(180,30,30),
    [WW2 and WW2.FACCION and WW2.FACCION.USSR or "ussr"]   = Color(200,40,40),
}

surface.CreateFont("WW2_FactionHUD", {font="Montserrat", size=ScreenScale(20), weight=900})

hook.Add("HUDPaint", "WW2_FactionHUD_Draw", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local fac = ply:GetNWString("ww2_faction", "")
    if fac == "" then return end

    local name = (WW2 and WW2.FactionNames and WW2.FactionNames[fac]) or Names[fac] or string.upper(fac)
    local col  = (WW2 and WW2.FactionColors and WW2.FactionColors[fac]) or Colors[fac] or color_white

    local margin = math.max(1, math.floor(ScrW()*0.008))
    local x = margin
    local y = ScrH() - margin - draw.GetFontHeight("WW2_FactionHUD")

    draw.SimpleText(name, "WW2_FactionHUD", x+2, y+2, Color(0,0,0,200), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(name, "WW2_FactionHUD", x,   y,   col,             TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
end)
