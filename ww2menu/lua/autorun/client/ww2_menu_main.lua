if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

-- ========= FUENTES (una sola vez) =========
if not _G.__WW2_FONTS_DEFINED then
    surface.CreateFont("WW2_Titulo",    {font="Trajan Pro", size=ScreenScale(14), weight=800})
    surface.CreateFont("WW2_Sub",       {font="Montserrat", size=ScreenScale(10), weight=700})
    surface.CreateFont("WW2_Opcion",    {font="Montserrat", size=ScreenScale(9),  weight=600})
    surface.CreateFont("WW2_Pie",       {font="Montserrat", size=ScreenScale(7),  weight=500})
    surface.CreateFont("WW2_ClassTitle",{font="Montserrat", size=ScreenScale(12), weight=1000})
    surface.CreateFont("WW2_ClassItem", {font="Montserrat", size=ScreenScale(9),  weight=800})
    surface.CreateFont("WW2_DeathBtn",  {font="Montserrat", size=ScreenScale(9),  weight=800})
    _G.__WW2_FONTS_DEFINED = true
end

-- ========= Config =========
local TITULO_PRINCIPAL = "1942 - En las afueras de Moscú"
local TEXTO_REICH      = "Tercer Reich"
local TEXTO_USSR       = "Unión Soviética"
local TEXTO_CIVIL      = "Civil"

-- ========= Colores =========
local colOscuro     = Color(10, 10, 12, 245)
local colBorde      = Color(255, 255, 255, 10)
local colTitulo     = Color(240, 240, 240)
local colReich      = Color(140, 0, 0, 200)
local colUSSR       = Color(180, 20, 20, 200)
local colLinea      = Color(255, 255, 255, 30)

-- ========= Blur =========
local blur = Material("pp/blurscreen")
local function PintarBlur(panel, capas)
    local x, y = panel:LocalToScreen(0, 0)
    local scrW, scrH = ScrW(), ScrH()
    surface.SetDrawColor(255,255,255)
    surface.SetMaterial(blur)
    for i=1,(capas or 4) do
        blur:SetFloat("$blur", i*1.5)
        blur:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(-x, -y, scrW, scrH)
    end
end

-- ========= Net helper =========
local function ElegirFaccion(faccion)
    if not faccion or faccion == "" then return end
    net.Start("WW2_ElegirBando")
        net.WriteString(faccion)
    net.SendToServer()
end

-- ========= MENÚ PRINCIPAL =========
function WW2_AbrirMenu()
    local scrW, scrH = ScrW(), ScrH()
    local margen     = math.max(16, math.floor(scrW * 0.01))
    local altoHeader = math.max(64, math.floor(scrH * 0.12))
    local altoPie    = math.max(52, math.floor(scrH * 0.10))
    local anchoCol   = math.floor((scrW - margen*3) * 0.5)
    local altoCol    = math.floor(scrH - altoHeader - altoPie - margen*2)

    local frame = vgui.Create("DFrame")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:SetTitle("")
    frame:SetSize(scrW, scrH)
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(self, w, h)
        PintarBlur(self, 5)
        surface.SetDrawColor(colOscuro)  surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(colBorde)   surface.DrawOutlinedRect(margen/2, margen/2, w - margen, h - margen, 2)
        surface.SetDrawColor(colLinea)
        surface.DrawRect(margen, altoHeader, w - margen*2, 1)
        surface.DrawRect(margen, h - altoPie, w - margen*2, 1)
    end
    g_WW2_Menu = frame

    local header = vgui.Create("DPanel", frame)
    header:SetPos(margen, margen)
    header:SetSize(scrW - margen*2, altoHeader - margen)
    header.Paint = function(self, w, h)
        draw.SimpleText(TITULO_PRINCIPAL, "WW2_Titulo", w*0.5, h*0.55, colTitulo, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Selecciona tu bando", "WW2_Pie", w*0.5, h*0.85, Color(220,220,220,160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- REICH
    local panelReich = vgui.Create("DButton", frame)
    panelReich:SetText("")
    panelReich:SetPos(margen, altoHeader + margen)
    panelReich:SetSize(anchoCol, altoCol)
    panelReich.Paint = function(self, w, h)
        surface.SetDrawColor(colReich) surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(colBorde) surface.DrawOutlinedRect(0,0,w,h,2)
        draw.SimpleText(TEXTO_REICH, "WW2_Sub", w/2, h*0.08, Color(255,240,240), TEXT_ALIGN_CENTER)
    end
    panelReich.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        ElegirFaccion(WW2.FACCION.REICH)
        if IsValid(frame) then frame:Remove() end
        WW2_AbrirMenuClases_Reich()
    end

    -- USSR
    local panelUSSR = vgui.Create("DButton", frame)
    panelUSSR:SetText("")
    panelUSSR:SetPos(margen*2 + anchoCol, altoHeader + margen)
    panelUSSR:SetSize(anchoCol, altoCol)
    panelUSSR.Paint = function(self, w, h)
        surface.SetDrawColor(colUSSR) surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(colBorde) surface.DrawOutlinedRect(0,0,w,h,2)
        draw.SimpleText(TEXTO_USSR, "WW2_Sub", w/2, h*0.08, Color(255,240,240), TEXT_ALIGN_CENTER)
    end
    panelUSSR.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        ElegirFaccion(WW2.FACCION.USSR)
        if IsValid(frame) then frame:Remove() end
        WW2_AbrirMenuClases_USSR()
    end
end

-- Auto abrir si no hay menú
hook.Add("InitPostEntity", "WW2_MostrarMenu_Init", function()
    timer.Simple(1.0, function()
        if not IsValid(g_WW2_Menu) then
            WW2_AbrirMenu()
        end
    end)
end)

concommand.Add("ww2menu_open", function()
    if IsValid(g_WW2_Menu) then g_WW2_Menu:Remove() end
    WW2_AbrirMenu()
end)
