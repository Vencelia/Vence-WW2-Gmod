if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

-- ================== CONFIG ==================
local CAM_HEIGHT = 450
local MAP_MARGIN = 64
local BG_ALPHA   = 220
local KEY_TOGGLE = KEY_M

-- Animación (0..1): 0 oculto, 1 visible
local ANIM_SPEED = 7.0
local animFrac   = 0
local targetFrac = 0

local colPanel   = Color(20,20,20,255)
local colBorder  = Color(255,255,255,25)
local colText    = Color(230,230,230,230)
local colTip     = Color(210,210,210,180)
local colReich   = Color(80,150,255)
local colUSSR    = Color(220,60,60)
local colNeutral = Color(200,200,200)

local cvarIconScale = CreateClientConVar("ww2_map_icon_scale", "1.8", true, false, "Escala iconos mapa (0.5..4.0)", 0.5, 4.0)

-- Ajustes finos iguales al menú de deploy
local cvarMapProjScale = CreateClientConVar("ww2_map_proj_scale", "1.00", true, false, "Escala radial de proyección en overlay (0.5..3.0)", 0.5, 3.0)
local cvarMapOffsetX   = CreateClientConVar("ww2_map_offset_x", "0", true, false, "Offset X (px) overlay", -2048, 2048)
local cvarMapOffsetY   = CreateClientConVar("ww2_map_offset_y", "0", true, false, "Offset Y (px) overlay", -2048, 2048)

-- Calibración fina (ajustar si hay offset residual)
local OFFSET_X = 0
local OFFSET_Y = 0

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

-- ============================================
-- ✅ FIX: PROYECCIÓN 3D→2D CORRECTA
-- ============================================
local function WorldToScreenCustom(worldPos, viewData)
    local ang   = viewData.angles
    local origin= viewData.origin
    local fov   = viewData.fov or 70
    local w     = viewData.w
    local h     = viewData.h

    local delta = worldPos - origin
    local fwd   = ang:Forward()
    local right = ang:Right()
    local up    = ang:Up()

    local x = delta:Dot(right)
    local y = delta:Dot(fwd)
    local z = delta:Dot(up)

    -- Nunca devolvemos nil: si queda "detrás" de la cámara, clipeamos cerca
    if y <= 0.1 then y = 0.1 end

    if y <= 0.1 then return nil, nil, false end

    local tanHalfV = math.tan(math.rad(fov) * 0.5)
    local scale = (h * 0.5)
    local projScale = (cvarMapProjScale and cvarMapProjScale:GetFloat()) or 1.0
    projScale = math.max(0.5, math.min(3.0, projScale))
    scale = scale * projScale

    local sx = (x / (y * tanHalfV)) * scale + (w * 0.5)
    local sy = (-z / (y * tanHalfV)) * scale + (h * 0.5)

    local offx = (cvarMapOffsetX and cvarMapOffsetX:GetInt()) or 0
    local offy = (cvarMapOffsetY and cvarMapOffsetY:GetInt()) or 0
    sx = sx + offx
    sy = sy + offy

    return sx, sy, true

end
-- ============================================

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
    draw.NoTexture()
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

-- ================== LVs / Facción Helpers ==================
local function GetLocalSide()
    local lp = LocalPlayer()
    if not IsValid(lp) then return "" end
    return lp:GetNWString("ww2_faction","")
end

local function IsLVSAliveClient(veh)
    if not IsValid(veh) then return false end
    if veh.GetIsDestroyed and veh:GetIsDestroyed() then return false end
    if veh.GetDisabled     and veh:GetDisabled()     then return false end
    local hp, maxhp
    if veh.GetHP then local okH, v = pcall(function() return veh:GetHP() end); if okH then hp = tonumber(v) end end
    if veh.GetMaxHP then local okM, v = pcall(function() return veh:GetMaxHP() end); if okM then maxhp = tonumber(v) end end
    if hp ~= nil and maxhp ~= nil and maxhp > 0 and hp <= 0 then return false end
    if veh.GetNW2Bool and (veh:GetNW2Bool("LVS_Destroyed", false) or veh:GetNW2Bool("LVS_Disabled", false)) then return false end
    if veh.GetNWBool  and (veh:GetNWBool("LVS_Destroyed", false) or veh:GetNWBool("LVS_Disabled", false))  then return false end
    local hp1 = veh.GetNWInt and veh:GetNWInt("LVS_HP", -1) or -1
    if hp1 == 0 then return false end
    return true
end

-- Mapear camión por bando
local function GetTruckClassForSide(side)
    if side == "reich" then return "lvs_wheeldrive_fiat_621" end
    if side == "ussr"  then return "lvs_wheeldrive_gaz_aaa" end
    return nil
end


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

    -- ✅ FIX: Crear viewData para proyección correcta
    local viewData = {
        origin = view.origin,
        angles = view.angles,
        fov = view.fov,
        w = w,
        h = h
    }

    -- ✅ FIX: Proyección correcta para bases
    local function drawBaseList(list, col, text)
        for _, b in ipairs(list) do
            if not IsValid(b) then continue end
            
            -- ✅ PROYECCIÓN CORRECTA (sin cam.Start3D)
            local px, py, visible = WorldToScreenCustom(b:GetPos(), viewData)
            if not px then continue end
            
            px, py = ClampToPanel(px, py, w, h, 18)

            local baseSize = math.min(w, h) * 0.10 * scale
            local r = math.floor(baseSize * 0.5)

        -- Color por propietario actual
        local owner = (b.GetNW2String and b:GetNW2String("cap_owner","")) or (b.GetNWString and b:GetNWString("cap_owner","")) or ""
        local drawCol = col
        if owner == "reich" then drawCol = colReich elseif owner == "ussr" then drawCol = colUSSR end


            surface.SetDrawColor(0,0,0,180); DrawCircle(px+2, py+2, r)
            surface.SetDrawColor(drawCol); DrawCircle(px, py, r)
            surface.SetDrawColor(40,42,46,240); DrawCircle(px, py, r-4)

            draw.SimpleText(text, "WW2_MapBase", px+1, py+1, Color(0,0,0,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, "WW2_MapBase", px,   py,   Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    drawBaseList(basesReich, colReich, "REICH")
    drawBaseList(basesUSSR, colUSSR, "SOVIET")

    -- ✅ FIX: Proyección correcta para puntos de captura
    for _, cp in ipairs(GetCapturePoints()) do
        if not IsValid(cp) then continue end
        
        -- ✅ PROYECCIÓN CORRECTA
        local px, py, visible = WorldToScreenCustom(cp:GetPos(), viewData)
        if not px then continue end
        
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

    

-- ================== CAMIONES DE MI FACCION ==================
do
    local side = GetLocalSide()
    local class = GetTruckClassForSide(side)
    if class then
        local list = ents.FindByClass(class) or {}
        local scale = math.Clamp(cvarIconScale:GetFloat(), 0.5, 4.0)
        local col = (side == "reich") and colReich or (side == "ussr" and colUSSR or colNeutral)
        local base = math.min(w, h) * 0.05
        local sz = math.floor(base * 0.8 * scale) -- ligeramente más pequeño que un punto de captura
        for _, ent in ipairs(list) do
            if IsValid(ent) and IsLVSAliveClient(ent) then
                local px, py = WorldToScreenCustom(ent:GetPos(), {
                    origin=view.origin, angles=view.angles, fov=view.fov, w=w, h=h
                })
                if px and py then
                    px, py = ClampToPanel(px, py, w, h, 10)
                    local bx, by = math.floor(px - sz/2), math.floor(py - sz/2)
                    surface.SetDrawColor(0,0,0,200)  surface.DrawRect(bx+2, by+2, sz, sz)
                    surface.SetDrawColor(40,42,46,230) surface.DrawRect(bx, by, sz, sz)
                    surface.SetDrawColor(col)          surface.DrawRect(bx+2, by+2, sz-4, sz-4)
                    surface.SetDrawColor(colBorder)    surface.DrawOutlinedRect(bx, by, sz, sz, 2)
                    draw.SimpleText("TRUCK", "WW2_MapIcon", bx + sz/2, by + sz/2, Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
    end
end

-- ================== ALIADOS EN EL MAPA (solo mi facción) ==================
do
    local lp = LocalPlayer()
    local mySide = GetLocalSide()
    local allyCol = (mySide == "reich") and colReich or (mySide == "ussr" and colUSSR or colNeutral)
    local scale = math.Clamp(cvarIconScale:GetFloat(), 0.5, 4.0)
    local baseR = math.max(4, math.floor(math.min(w,h) * 0.008)) -- aliados
    local selfR = math.max(6, math.floor(math.min(w,h) * 0.012)) -- jugador local (más grande)

    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p ~= lp then
            if p:GetNWString("ww2_faction","") == mySide then
                local px, py = WorldToScreenCustom(p:GetPos(), viewData)
                if px and py then
                    local clamped
                    px, py, clamped = ClampToPanel(px, py, w, h, 10)
                    surface.SetDrawColor(0,0,0,200) DrawCircle(px+2, py+2, baseR)
                    surface.SetDrawColor(allyCol)     DrawCircle(px, py, baseR)
                    if clamped then
                        surface.SetDrawColor(allyCol)
                        DrawArrowToCenter(px, py, w*0.5, h*0.5, math.max(10, baseR*1.2))
                    end
                end
            end
        end
    end

    -- Ajustar el tamaño del jugador local (más grande que aliados)
    -- (La sección del jugador local existente abajo ya lo dibuja. Aumentamos r dinámicamente)
end

-- ✅ FIX: Proyección correcta para el jugador
    local lp = LocalPlayer()
    if IsValid(lp) then
        local px, py, visible = WorldToScreenCustom(lp:GetPos(), viewData)
        if px then
            local clamped
            px, py, clamped = ClampToPanel(px, py, w, h, 10)

            local r = math.max(8, math.floor(math.min(w,h) * 0.015)) -- más grande que aliados
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
    MAP_FRAME:SetVisible(false)
    MAP_FRAME:SetKeyboardInputEnabled(false)

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
    MAP_PANEL:SetPos(MAP_MARGIN, scrH)
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
        local view = { origin=origin, angles=Angle(90, yaw, 0), x=sx, y=sy, w=w, h=h, fov=camEnt.GetCamFOV and camEnt:GetCamFOV() or 200, drawviewmodel=false, drawhud=false, znear=3 }

        render.RenderView(view)
        render.SetScissorRect(sx, sy, sx + w, sy + h, true)
        DrawMarkers(w, h, sx, sy, view)
        render.SetScissorRect(0, 0, 0, 0, false)

        surface.SetDrawColor(colBorder) surface.DrawOutlinedRect(0,0,w,h,2)
    end

    CLOSE_BTN = vgui.Create("DButton", MAP_FRAME)
    CLOSE_BTN:SetSize(math.floor(scrW*0.16), math.floor(scrH*0.06))
    CLOSE_BTN:SetText("")
    CLOSE_BTN.Paint = function(self, bw, bh)
        surface.SetDrawColor(30,30,30,230) surface.DrawRect(0,0,bw,bh)
        surface.SetDrawColor(255,255,255,30) surface.DrawOutlinedRect(0,0,bw,bh,2)
        draw.SimpleText("Cerrar [M]", "WW2_MapOverlay_Sub", bw/2, bh/2, colText, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    CLOSE_BTN.DoClick = function() end

    -- scroll wheel para escala de iconos
    function MAP_PANEL:OnMouseWheeled(dlta)
        if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
            local v = math.Clamp(cvarMapProjScale:GetFloat() + dlta*0.05, 0.5, 3.0)
            RunConsoleCommand("ww2_map_proj_scale", string.format("%.2f", v))
            return true
        elseif input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then
            if input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT) then
                local oy = cvarMapOffsetY:GetInt()
                RunConsoleCommand("ww2_map_offset_y", tostring(oy + (dlta>0 and -2 or 2)))
            else
                local ox = cvarMapOffsetX:GetInt()
                RunConsoleCommand("ww2_map_offset_x", tostring(ox + (dlta>0 and -2 or 2)))
            end
            return true
        else
            local v = math.Clamp(cvarIconScale:GetFloat() + dlta*0.1, 0.5, 4.0)
            RunConsoleCommand("ww2_map_icon_scale", tostring(v))
            return true
        end
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
end)

hook.Add("Think", "WW2_MapOverlay_HoldM", function()
    local hold = input.IsKeyDown(KEY_TOGGLE)
    if CHAT_OPEN or blockUntilMUp then
        targetFrac = 0
        if blockUntilMUp and not hold then
            blockUntilMUp = false
        end
    else
        targetFrac = hold and 1 or 0
    end

    local ft = FrameTime()
    animFrac = Lerp(math.min(1, ft * ANIM_SPEED), animFrac, targetFrac)

    if animFrac > 0 or targetFrac > 0 then
        EnsureOverlay()
    end
    if not IsValid(MAP_FRAME) then return end

    local show = animFrac > 0.001
    MAP_FRAME:SetVisible(show)
    if not show then return end

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