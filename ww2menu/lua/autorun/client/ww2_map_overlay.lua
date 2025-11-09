if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

-- ================== CONFIG ==================
local CAM_HEIGHT = 450
local MAP_MARGIN = 64
local BG_ALPHA   = 220
local KEY_TOGGLE = KEY_M

-- Animación (0..1): 0 oculto, 1 visible
local ANIM_SPEED = 7.0     -- rapidez de lerp; subí/baixá para más/menos velocidad
local animFrac   = 0       -- estado actual
local targetFrac = 0       -- objetivo según tecla/chat

local colPanel   = Color(20,20,20,255)
local colBorder  = Color(255,255,255,25)
local colText    = Color(230,230,230,230)
local colTip     = Color(210,210,210,180)
local colReich   = Color(80,150,255)
local colUSSR    = Color(220,60,60)
local colNeutral = Color(200,200,200)

local cvarIconScale = CreateClientConVar("ww2_map_icon_scale", "1.8", true, false, "Escala iconos mapa (0.5..4.0)", 0.5, 4.0)

surface.CreateFont("WW2_MapOverlay_Title",{font="Montserrat", size=ScreenScale(12), weight=1000})
surface.CreateFont("WW2_MapOverlay_Sub",  {font="Montserrat", size=ScreenScale(7),  weight=600})
surface.CreateFont("WW2_MapIcon",         {font="Montserrat", size=ScreenScale(9),  weight=1000})
surface.CreateFont("WW2_MapBase",         {font="Montserrat", size=ScreenScale(8),  weight=1000})

-- ================== STATE ==================
local MAP_FRAME, MAP_PANEL, CLOSE_BTN

-- ================== HELPERS ==================
local function FindDeployCam()
    local cams = ents.FindByClass("ww2_deploy_cam")
    return cams[1]
end

local function ClampToPanel(px, py, panelW, panelH, margin)
    margin = margin or 6
    local cx, cy = panelW * 0.5, panelH * 0.5
    local dx, dy = px - cx, py - cy
    if dx == 0 and dy == 0 then dx = 0.001 end
    local sx = (panelW * 0.5 - margin) / math.max(1, math.abs(dx))
    local sy = (panelH * 0.5 - margin) / math.max(1, math.abs(dy))
    local s = math.min(sx, sy)
    if s > 1 then return px, py, false end
    local ex, ey = cx + dx * s, cy + dy * s
    return ex, ey, true
end

local function DrawCircle(x, y, r)
    local seg = math.max(20, math.floor(r*0.8))
    local poly = {}
    for i=0, seg-1 do
        local a = (i/seg) * math.pi*2
        poly[#poly+1] = {x = x + math.cos(a)*r, y = y + math.sin(a)*r}
    end
    surface.DrawPoly(poly)
end

local function DrawArrowToCenter(x, y, cx, cy, size)
    local ang = math.atan2(cy - y, cx - x)
    local s = size or 12
    local p1x, p1y = x + math.cos(ang) * s, y + math.sin(ang) * s
    local left  = ang + math.rad(130)
    local right = ang - math.rad(130)
    local p2x, p2y = x + math.cos(left)  * (s*0.7), y + math.sin(left)  * (s*0.7)
    local p3x, p3y = x + math.cos(right) * (s*0.7), y + math.sin(right) * (s*0.7)
    surface.DrawPoly({ {x=p1x,y=p1y}, {x=p2x,y=p2y}, {x=p3x,y=p3y} })
end

local function GetCapturePoints() return ents.FindByClass("ww2_cap_point") end

-- [[ WW2: GetCapturePoints robust override (cache + fallbacks) ]]
do
    local _cp_cache = {}
    local _cp_next  = 0

    local function collectByClasses()
        local t, seen = {}, {}
        local function add(list)
            for _, e in ipairs(list) do
                if IsValid(e) and not seen[e] then
                    seen[e] = true
                    t[#t+1] = e
                end
            end
        end
        -- Clases esperadas (agrega si tienes otras variantes)
        add(ents.FindByClass("ww2_cap_point"))
        add(ents.FindByClass("ww2_capture_point"))
        return t
    end

    local function collectByNWFallback()
        local t = {}
        for _, e in ipairs(ents.GetAll()) do
            if IsValid(e) and e.GetNWString then
                local lbl = e:GetNWString("cap_label", "")
                local own = e:GetNWString("cap_owner", "")
                if (lbl ~= "") or (own ~= "") then
                    t[#t+1] = e
                end
            end
        end
        return t
    end

    -- Si ya existe un local GetCapturePoints en este archivo, lo reasignamos.
    -- Si no existe, esta asignación crea/usa el global en este contexto y los
    -- llamados posteriores lo tomarán igual.
    GetCapturePoints = function()
        if _cp_next > RealTime() then
            return _cp_cache
        end
        _cp_next = RealTime() + 2.0

        local t = collectByClasses()
        if #t == 0 then
            t = collectByNWFallback()
        end
        _cp_cache = t
        return _cp_cache
    end
end
-- [[ /override ]]
local function GetBases() return ents.FindByClass("ww2_base_reich"), ents.FindByClass("ww2_base_ussr") end

local function GetPlayerFactionColor()
    local side = LocalPlayer():GetNWString("ww2_faction","")
    if side == "reich" then return colReich
    elseif side == "ussr" then return colUSSR
    else return Color(180,180,180) end
end

-- ================== DRAWERS ==================
local CPTrend = {}
local function DrawMarkers(w, h, sx, sy, view)
    local t = CurTime()
    local scale = math.Clamp(cvarIconScale:GetFloat(), 0.5, 4.0)
    local basesReich, basesUSSR = GetBases()

    local function drawBaseList(list, col, text)
        for _, b in ipairs(list) do
            if not IsValid(b) then continue end
            cam.Start3D(view.origin, view.angles, view.fov, sx, sy, w, h)
                local sp = b:GetPos():ToScreen()
            cam.End3D()
            local px, py = sp.x - sx, sp.y - sy
            px, py = ClampToPanel(px, py, w, h, 18)

            local baseSize = math.min(w, h) * 0.10 * scale
            local r = math.floor(baseSize * 0.5)

            surface.SetDrawColor(0,0,0,180); DrawCircle(px+2, py+2, r)
            surface.SetDrawColor(col); DrawCircle(px, py, r)
            surface.SetDrawColor(40,42,46,240); DrawCircle(px, py, r-4)

            draw.SimpleText(text, "WW2_MapBase", px+1, py+1, Color(0,0,0,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, "WW2_MapBase", px,   py,   Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    drawBaseList(basesReich, colReich, "REICH")
    drawBaseList(basesUSSR, colUSSR, "SOVIET")

    -- Puntos
    cam.Start3D(view.origin, view.angles, view.fov, sx, sy, w, h)
    for _, cp in ipairs(GetCapturePoints()) do
        if not IsValid(cp) then continue end
        local sp = cp:GetPos():ToScreen()
        local px, py = sp.x - sx, sp.y - sy
        px, py = ClampToPanel(px, py, w, h, 8)

        local label     = cp:GetNWString("cap_label","A")
        local owner     = cp:GetNWString("cap_owner","")
        local ctrl      = cp:GetNWFloat("cap_control",0)
        local contested = cp:GetNWBool("cap_contested", false)

        local idx  = cp:EntIndex()
        local last = CPTrend[idx] or ctrl
        local delta = ctrl - last
        CPTrend[idx] = ctrl

        local baseCol = colNeutral
        if owner == "reich" then baseCol = colReich
        elseif owner == "ussr" then baseCol = colUSSR end

        local wantBlink = false
        if contested and owner ~= "" then
            wantBlink = true
        else
            if owner == "reich" and delta < -0.0005 then wantBlink = true
            elseif owner == "ussr" and delta > 0.0005 then wantBlink = true
            elseif owner == "" and math.abs(delta) > 0.0005 then wantBlink = true end
        end

        local blinkFast = (math.floor(t*6) % 2) == 0
        local drawCol = wantBlink and (blinkFast and baseCol or colNeutral) or baseCol

        local base = math.min(w, h) * 0.05
        local sz = math.floor(base * scale)
        local bx, by = math.floor(px - sz/2), math.floor(py - sz/2)

        surface.SetDrawColor(Color(0,0,0,200)) surface.DrawRect(bx+2, by+2, sz, sz)
        surface.SetDrawColor(40,42,46,230)     surface.DrawRect(bx, by, sz, sz)
        surface.SetDrawColor(drawCol)          surface.DrawRect(bx+2, by+2, sz-4, sz-4)
        surface.SetDrawColor(colBorder)        surface.DrawOutlinedRect(bx, by, sz, sz, 2)

        draw.SimpleText(label, "WW2_MapIcon", bx + sz/2 + 1, by + sz/2 + 1, Color(0,0,0,180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(label, "WW2_MapIcon", bx + sz/2,     by + sz/2,     Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    cam.End3D()

    -- Jugador (2D)
    local lp = LocalPlayer()
    if IsValid(lp) then
        cam.Start3D(view.origin, view.angles, view.fov, sx, sy, w, h)
            local sp = lp:GetPos():ToScreen()
        cam.End3D()
        local px, py = sp.x - sx, sp.y - sy
        local clamped
        px, py, clamped = ClampToPanel(px, py, w, h, 10)

        local r = math.max(6, math.floor(math.min(w,h) * 0.012))
        local facCol = GetPlayerFactionColor()
        surface.SetDrawColor(0,0,0,200) DrawCircle(px+2, py+2, r)
        surface.SetDrawColor(facCol)     DrawCircle(px, py, r)
        surface.SetDrawColor(255,255,255) surface.DrawOutlinedRect(px-r, py-r, r*2, r*2, 1)
        if clamped then
            surface.SetDrawColor(facCol)
            DrawArrowToCenter(px, py, w*0.5, h*0.5, math.max(10, r*1.2))
        end
    end
end

-- ================== OVERLAY (CREACIÓN ÚNICA) ==================
local function EnsureOverlay()
    if IsValid(MAP_FRAME) then return end

    local scrW, scrH = ScrW(), ScrH()
    MAP_FRAME = vgui.Create("DFrame")
    MAP_FRAME:SetSize(scrW, scrH)
    MAP_FRAME:SetTitle("")
    MAP_FRAME:ShowCloseButton(false)
    MAP_FRAME:SetDraggable(false)
    MAP_FRAME:SetVisible(false)             -- se muestra sólo si animFrac > 0
    MAP_FRAME:SetKeyboardInputEnabled(false)
    -- sin MakePopup para no robar foco ni bloquear entrada del juego

    function MAP_FRAME:Paint(w, h)
        if animFrac <= 0 then return end
        local a = math.Clamp(animFrac, 0, 1)
        surface.SetDrawColor(0,0,0, math.floor(BG_ALPHA * a))
        surface.DrawRect(0,0,w,h)

        draw.SimpleText("MAPA", "WW2_MapOverlay_Title", w*0.5, MAP_MARGIN*0.6, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Mantén M para ver · Rueda: escala iconos", "WW2_MapOverlay_Sub", w*0.5, MAP_MARGIN*1.1, colTip, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- panel del mapa (se desliza desde abajo)
    local mapW, mapH = scrW - MAP_MARGIN*2, scrH - MAP_MARGIN*2
    MAP_PANEL = vgui.Create("DPanel", MAP_FRAME)
    MAP_PANEL:SetSize(mapW, mapH)
    MAP_PANEL:SetPos(MAP_MARGIN, scrH)  -- arranca abajo (fuera de pantalla)
    MAP_PANEL.Paint = function(self, w, h)
        if animFrac <= 0 then return end
        surface.SetDrawColor(colPanel) surface.DrawRect(0,0,w,h)

        local camEnt = FindDeployCam()
        if not IsValid(camEnt) then
            draw.SimpleText("Sin cámara ww2_deploy_cam.", "WW2_MapOverlay_Sub", w*0.5, h*0.5, Color(200,60,60), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        local sx, sy = self:LocalToScreen(0, 0)
        local yaw = camEnt:GetAngles().y
        local origin = camEnt:GetPos() + Vector(0,0,CAM_HEIGHT)
        local view = { origin=origin, angles=Angle(90, yaw, 0), x=sx, y=sy, w=w, h=h, fov=camEnt.GetCamFOV and camEnt:GetCamFOV() or 70, drawviewmodel=false, drawhud=false, znear=3 }

        render.RenderView(view)
        render.SetScissorRect(sx, sy, sx + w, sy + h, true)
        DrawMarkers(w, h, sx, sy, view)
        render.SetScissorRect(0, 0, 0, 0, false)

        surface.SetDrawColor(colBorder) surface.DrawOutlinedRect(0,0,w,h,2)
    end

    -- botón opcional de cierre (no es necesario en “mantener M”, pero lo dejo)
    CLOSE_BTN = vgui.Create("DButton", MAP_FRAME)
    CLOSE_BTN:SetSize(math.floor(scrW*0.16), math.floor(scrH*0.06))
    CLOSE_BTN:SetText("")
    CLOSE_BTN.Paint = function(self, bw, bh)
        surface.SetDrawColor(30,30,30,230) surface.DrawRect(0,0,bw,bh)
        surface.SetDrawColor(255,255,255,30) surface.DrawOutlinedRect(0,0,bw,bh,2)
        draw.SimpleText("Cerrar [M]", "WW2_MapOverlay_Sub", bw/2, bh/2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    CLOSE_BTN.DoClick = function() end  -- no hace nada; se cierra al soltar M

    -- scroll wheel para escala de iconos
    function MAP_PANEL:OnMouseWheeled(dlta)
        local v = math.Clamp(cvarIconScale:GetFloat() + dlta*0.1, 0.5, 4.0)
        RunConsoleCommand("ww2_map_icon_scale", tostring(v))
        return true
    end
end

-- ================== CONTROL: Mantener M + bloqueo de chat ==================
local CHAT_OPEN = false
local blockUntilMUp = false

hook.Add("StartChat","WW2_MapOverlay_ChatStart", function()
    CHAT_OPEN = true
    blockUntilMUp = true
end)

hook.Add("FinishChat","WW2_MapOverlay_ChatEnd", function()
    CHAT_OPEN = false
    -- bloquea hasta que se suelte M
end)

hook.Add("Think", "WW2_MapOverlay_HoldM", function()
    -- determinar target según chat y tecla
    local hold = input.IsKeyDown(KEY_TOGGLE)
    if CHAT_OPEN or blockUntilMUp then
        targetFrac = 0
        if blockUntilMUp and not hold then
            blockUntilMUp = false
        end
    else
        targetFrac = hold and 1 or 0
    end

    -- animación
    local ft = FrameTime()
    animFrac = Lerp(math.min(1, ft * ANIM_SPEED), animFrac, targetFrac)

    -- crear overlay si hace falta
    if animFrac > 0 or targetFrac > 0 then
        EnsureOverlay()
    end
    if not IsValid(MAP_FRAME) then return end

    -- visibilidad del frame
    local show = animFrac > 0.001
    MAP_FRAME:SetVisible(show)
    if not show then return end

    -- actualizar posiciones (deslizar el panel desde abajo)
    local scrW, scrH = ScrW(), ScrH()
    local mapW, mapH = scrW - MAP_MARGIN*2, scrH - MAP_MARGIN*2

    if IsValid(MAP_PANEL) then
        MAP_PANEL:SetSize(mapW, mapH)
        local y = math.floor(Lerp(animFrac, scrH, MAP_MARGIN))
        MAP_PANEL:SetPos(MAP_MARGIN, y)
    end

    if IsValid(CLOSE_BTN) then
        local bw, bh = math.floor(scrW*0.16), math.floor(scrH*0.06)
        CLOSE_BTN:SetSize(bw, bh)
        CLOSE_BTN:SetPos(scrW*0.5 - bw/2, math.floor(Lerp(animFrac, scrH + 30, scrH - MAP_MARGIN*0.85 - bh)))
    end
end)

-- Comando extra (debug): abre al máximo mientras lo mantengas pulsado
concommand.Add("ww2_map_hold_debug", function()
    targetFrac = 1
end)
