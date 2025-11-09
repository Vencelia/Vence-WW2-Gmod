if SERVER then return end
-- HUD de barra de captura para el punto en el que estés dentro del radio

surface.CreateFont("WW2_Cap_Title", {font="Montserrat", size=ScreenScale(10), weight=900})
surface.CreateFont("WW2_Cap_Sub",   {font="Montserrat", size=ScreenScale(7),  weight=800})

local colBG      = Color(15,15,18,230)
local colBorder  = Color(255,255,255,25)
local colNeutral = Color(210,210,210)
local colReich   = Color(80,150,255) -- Azul
local colUSSR    = Color(220,60,60)  -- Rojo
local colContest = Color(255,200,60)

local function GetNearestPointInRange(ply)
    local best, bestD
    for _, e in ipairs(ents.FindByClass("ww2_cap_point")) do
        if IsValid(e) then
            local rad = e:GetNWInt("cap_radius", 1000)
            local d = ply:GetPos():DistToSqr(e:GetPos())
            if d <= rad*rad then
                if not best or d < bestD then
                    best, bestD = e, d
                end
            end
        end
    end
    return best
end

hook.Add("HUDPaint", "WW2_CapturePoint_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local cp = GetNearestPointInRange(ply)
    if not IsValid(cp) then return end

    local label   = cp:GetNWString("cap_label","A")
    local owner   = cp:GetNWString("cap_owner","")
    local ctrl    = cp:GetNWFloat("cap_control",0)   -- -1..1
    local dispt   = cp:GetNWBool("cap_contested",false)

    local scrW, scrH = ScrW(), ScrH()
    local w, h = math.floor(scrW*0.45), math.floor(scrH*0.06)
    local x, y = (scrW - w)/2, math.floor(scrH*0.04)

    -- fondo
    surface.SetDrawColor(colBG) surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(colBorder) surface.DrawOutlinedRect(x, y, w, h, 2)

    -- barra de progreso (azul si ctrl>0, rojo si ctrl<0)
    local barPad = 8
    local barW = w - barPad*2
    local barH = math.floor(h*0.35)
    local barX = x + barPad
    local barY = y + h - barPad - barH

    -- fondo barra
    surface.SetDrawColor(50,50,56,200) surface.DrawRect(barX, barY, barW, barH)

    if ctrl > 0 then
        local fw = math.floor(barW * math.Clamp(ctrl, 0, 1))
        surface.SetDrawColor(colReich) surface.DrawRect(barX, barY, fw, barH)
    elseif ctrl < 0 then
        local fw = math.floor(barW * math.Clamp(-ctrl, 0, 1))
        surface.SetDrawColor(colUSSR) surface.DrawRect(barX, barY, fw, barH)
    end

    -- título y estado
    local title, tcol
    if owner == "reich" then
        title, tcol = (label.." Tercer Reich"), colReich
    elseif owner == "ussr" then
        title, tcol = (label.." Union Sovietica"), colUSSR
    else
        title, tcol = (label.." NEUTRAL"), colNeutral
    end

    draw.SimpleText(title, "WW2_Cap_Title", x + w/2, y + h*0.28, Color(0,0,0,180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(title, "WW2_Cap_Title", x + w/2, y + h*0.25, tcol,             TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    if dispt then
        local txt = "DISPUTA"
        draw.SimpleText(txt, "WW2_Cap_Sub", x + w/2, barY - 8, colContest, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end
end)
