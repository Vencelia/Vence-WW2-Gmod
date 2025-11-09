if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

-- Fonts (safe to redefine)
surface.CreateFont("WW2_DeathBig",  {font="Montserrat", size=ScreenScale(16), weight=1000})
surface.CreateFont("WW2_DeathBtn",  {font="Montserrat", size=ScreenScale(9),  weight=800})

local DeathUI = {
    active = false,
    diedAt = 0,
    frame  = nil,
    btnDeploy = nil,
    btnChange = nil
}

local function DeathUI_Remove()
    if IsValid(DeathUI.btnDeploy) then DeathUI.btnDeploy:Remove() end
    if IsValid(DeathUI.btnChange) then DeathUI.btnChange:Remove() end
    if IsValid(DeathUI.frame) then DeathUI.frame:Remove() end
    DeathUI.btnDeploy, DeathUI.btnChange, DeathUI.frame = nil, nil, nil
end

local function DeathUI_Start()
    DeathUI.active = true
    DeathUI.diedAt = CurTime()
    DeathUI_Remove()
    gui.EnableScreenClicker(true)

    local f = vgui.Create("DPanel")
    f:SetSize(ScrW(), ScrH())
    f:SetPos(0, 0)
    f:SetKeyboardInputEnabled(true)
    f:SetMouseInputEnabled(true)
    f:SetZPos(32767)
    f:SetVisible(true)
    f.Paint = function() end
    DeathUI.frame = f
end

local function DeathUI_Stop()
    DeathUI.active = false
    gui.EnableScreenClicker(false)
    DeathUI_Remove()
end

local function DeathUI_CreateButtons()
    if not DeathUI.active or not IsValid(DeathUI.frame) then return end
    if IsValid(DeathUI.btnDeploy) then return end
    if CurTime() - DeathUI.diedAt < 2.0 then return end

    local scrW, scrH = ScrW(), ScrH()
    local btnW, btnH = math.floor(scrW*0.18), math.floor(scrH*0.07)
    local gap = math.max(16, math.floor(scrW*0.01))
    local totalW = btnW*2 + gap
    local baseX = (scrW - totalW) * 0.5
    local baseY = math.floor(scrH * 0.60)

    local function styleBtn(btn, text)
        btn:SetText("")
        btn.Paint = function(self, w, h)
            surface.SetDrawColor(30,30,30,230) surface.DrawRect(0,0,w,h)
            surface.SetDrawColor(255,255,255,30) surface.DrawOutlinedRect(0,0,w,h,2)
            local clr = self:IsHovered() and Color(255,255,255) or Color(220,220,220)
            draw.SimpleText(text, "WW2_DeathBtn", w*0.5, h*0.5, clr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- DESPLEGAR
    local b1 = vgui.Create("DButton", DeathUI.frame)
    b1:SetSize(btnW, btnH)
    b1:SetPos(baseX, baseY)
    styleBtn(b1, "DESPLEGAR")
    b1.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        local cls = LocalPlayer():GetNWString("ww2_class","")
        if cls ~= "" and WW2_AbrirMenuDespliegue then
            DeathUI_Stop()
            WW2_AbrirMenuDespliegue(cls)
        else
            -- si no tiene clase aún, lo mandamos al menú de facción
            DeathUI_Stop()
            if WW2_AbrirMenu then WW2_AbrirMenu() end
        end
    end
    DeathUI.btnDeploy = b1

    -- CAMBIAR FACCION
    local b2 = vgui.Create("DButton", DeathUI.frame)
    b2:SetSize(btnW, btnH)
    b2:SetPos(baseX + btnW + gap, baseY)
    styleBtn(b2, "CAMBIAR DE FACCION")
    b2.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        DeathUI_Stop()
        if WW2_AbrirMenu then WW2_AbrirMenu() end
    end
    DeathUI.btnChange = b2
end

-- Detectar vivo/muerto
local wasAlive = true
hook.Add("Think", "WW2_DeathUI_AliveDetector_New", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local alive = ply:Alive()
    if wasAlive and not alive then
        DeathUI_Start()
    elseif (not wasAlive) and alive then
        DeathUI_Stop()
    end
    wasAlive = alive
end)

-- Dibujo de la pantalla negra + texto rojo
hook.Add("HUDPaint", "WW2_DeathUI_Draw_New", function()
    if not DeathUI.active then return end
    local scrW, scrH = ScrW(), ScrH()
    surface.SetDrawColor(0,0,0,255) surface.DrawRect(0,0,scrW,scrH)

    local msg = "ESTAS MUERTO"
    draw.SimpleText(msg, "WW2_DeathBig", scrW*0.5 + 2, scrH*0.42 + 2, Color(0,0,0,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(msg, "WW2_DeathBig", scrW*0.5,     scrH*0.42,     Color(220,30,30),   TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    DeathUI_CreateButtons()
end)
