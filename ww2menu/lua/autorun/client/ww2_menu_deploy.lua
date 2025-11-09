WW2_SelectedClassFromMenu = WW2_SelectedClassFromMenu or nil
if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")


-- Validación cliente: solo permite desplegar al dueño o defensor en disputa
local function WW2_FindCapPointByLabel(lbl)
    for _, cp in ipairs(ents.FindByClass("ww2_cap_point")) do
        if IsValid(cp) and cp:GetNWString("cap_label","") == lbl then return cp end
    end
end
function WW2_CanDeployToPoint(lbl)
    local cp = WW2_FindCapPointByLabel(lbl)
    if not IsValid(cp) then return false end
    local owner     = cp:GetNWString("cap_owner","")
    local contested = cp:GetNWBool("cap_contested", false)
    local side      = LocalPlayer():GetNWString("ww2_faction","")
    if side == "" then return false end
    if owner == side then return true end
    if contested and owner ~= "" and owner == side then return true end
    return false
end
surface.CreateFont("WW2_ClassTitle",{font="Montserrat", size=ScreenScale(12), weight=1000})
surface.CreateFont("WW2_Pie",       {font="Montserrat", size=ScreenScale(7),  weight=500})
surface.CreateFont("WW2_DeathBtn",  {font="Montserrat", size=ScreenScale(9),  weight=800})
surface.CreateFont("WW2_Opcion",    {font="Montserrat", size=ScreenScale(9),  weight=600})
surface.CreateFont("WW2_MapIcon",   {font="Montserrat", size=ScreenScale(9),  weight=1000})
surface.CreateFont("WW2_MapBase",   {font="Montserrat", size=ScreenScale(8),  weight=1000})

local CAM_HEIGHT = 450
local colReich   = Color(80,150,255)
local colUSSR    = Color(220,60,60)
local colNeutral = Color(200,200,200)
local colBorder  = Color(15,15,18,220)
local colShadow  = Color(0,0,0,200)

local cvarIconScale = CreateClientConVar("ww2_map_icon_scale", "1.8", true, false, "Escala iconos mapa (0.5..4.0)", 0.5, 4.0)

-- Calibración fina (ajustar si hay offset residual)
local OFFSET_X = 0
local OFFSET_Y = 0

local CPTrend = {}
local LastMarkers = {}

local function FindDeployCam()
    local cams = ents.FindByClass("ww2_deploy_cam")
    return cams[1]
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

local function GetBases()
    return ents.FindByClass("ww2_base_reich"), ents.FindByClass("ww2_base_ussr")
end

-- ============================================
-- ✅ FIX: PROYECCIÓN 3D→2D CORRECTA
-- ============================================
local function WorldToScreenCustom(worldPos, viewData)
    local ang = viewData.angles
    local origin = viewData.origin
    local fov = viewData.fov
    local w = viewData.w
    local h = viewData.h
    
    -- Vector relativo a la cámara
    local delta = worldPos - origin
    
    -- Rotación inversa (matriz de vista)
    local forward = ang:Forward()
    local right = ang:Right()
    local up = ang:Up()
    
    local x = delta:Dot(right)
    local y = delta:Dot(forward)
    local z = delta:Dot(up)
    
    -- Proyección perspectiva
    if y <= 0.1 then 
        return nil, nil, false -- Detrás de la cámara
    end
    
    local fovRad = math.rad(fov)
    local aspect = w / h
    local tanHalfFov = math.tan(fovRad / 2)
    
    local screenX = (x / (y * tanHalfFov * aspect)) * (w / 2) + (w / 2) + OFFSET_X
    local screenY = (-z / (y * tanHalfFov)) * (h / 2) + (h / 2) + OFFSET_Y
    
    return screenX, screenY, true
end

local function CollectMarkerScreenPos(view, sx, sy, w, h)
    local points = {}
    local viewData = {
        origin = view.origin,
        angles = view.angles,
        fov = view.fov,
        w = w,
        h = h
    }
    
    for _, cp in ipairs(GetCapturePoints()) do
        if IsValid(cp) then
            local worldPos = cp:GetPos()
            local screenX, screenY, visible = WorldToScreenCustom(worldPos, viewData)
            
            if screenX and screenY then
                points[#points+1] = {
                    cp = cp, 
                    x = screenX, 
                    y = screenY, 
                    vis = visible
                }
            end
        end
    end
    
    return points
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
    local left = ang + math.rad(130)
    local right = ang - math.rad(130)
    local p2x, p2y = x + math.cos(left) * (s*0.7), y + math.sin(left) * (s*0.7)
    local p3x, p3y = x + math.cos(right) * (s*0.7), y + math.sin(right) * (s*0.7)
    surface.DrawPoly({
        {x = p1x, y = p1y},
        {x = p2x, y = p2y},
        {x = p3x, y = p3y},
    })
end

local function DrawMarkers(points, panelW, panelH, scale, sx, sy, view)
    LastMarkers = {}
    local t = CurTime()
    local cx, cy = panelW * 0.5, panelH * 0.5

    -- ✅ FIX: Proyección correcta para bases
    local viewData = {
        origin = view.origin,
        angles = view.angles,
        fov = view.fov,
        w = panelW,
        h = panelH
    }

    -- Bases first (circles)
    local basesReich, basesUSSR = GetBases()
    local function drawBaseList(list, col, text, side)
        for _, b in ipairs(list) do
            if not IsValid(b) then continue end
            
            -- ✅ PROYECCIÓN CORRECTA (sin cam.Start3D)
            local px, py, visible = WorldToScreenCustom(b:GetPos(), viewData)
            if not px then continue end
            
            px, py = ClampToPanel(px, py, panelW, panelH, 18)
            local baseSize = math.min(panelW, panelH) * 0.10 * scale
            local r = math.floor(baseSize * 0.5)

            surface.SetDrawColor(0,0,0,180); DrawCircle(px+2, py+2, r)
            surface.SetDrawColor(col); DrawCircle(px, py, r)
            surface.SetDrawColor(40,42,46,240); DrawCircle(px, py, r-4)

            draw.SimpleText(text, "WW2_MapBase", px+1, py+1, Color(0,0,0,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, "WW2_MapBase", px,   py,   Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            table.insert(LastMarkers, {kind="base", side=side, x=px, y=py, r=r})
        end
    end
    drawBaseList(basesReich, colReich, "REICH", "reich")
    drawBaseList(basesUSSR, colUSSR, "SOVIET", "ussr")

    -- Capture points (squares)
    for _, item in ipairs(points) do
        local cp = item.cp
        if not IsValid(cp) then continue end

        local px, py = item.x, item.y
        local clamped = false
        px, py, clamped = ClampToPanel(px, py, panelW, panelH, 8)

        local label     = cp:GetNWString("cap_label","A")
        local owner     = cp:GetNWString("cap_owner","")
        local ctrl      = cp:GetNWFloat("cap_control",0)
        local contested = cp:GetNWBool("cap_contested", false)

        local idx = cp:EntIndex()
        local last = CPTrend[idx] or ctrl
        local delta = ctrl - last
        CPTrend[idx] = ctrl

        local baseCol = colNeutral
        if owner == "reich" then baseCol = colReich
        elseif owner == "ussr" then baseCol = colUSSR end

        local wantBlink = false
        local blinkColA, blinkColB = baseCol, colNeutral

        if contested and owner ~= "" then
            wantBlink = true
        else
            if owner == "reich" then
                if delta < -0.0005 then
                    wantBlink = true
                    if ctrl > 0 then blinkColA, blinkColB = colReich, colNeutral
                    else blinkColA, blinkColB = colUSSR, colNeutral end
                end
            elseif owner == "ussr" then
                if delta > 0.0005 then
                    wantBlink = true
                    if ctrl < 0 then blinkColA, blinkColB = colUSSR, colNeutral
                    else blinkColA, blinkColB = colReich, colNeutral end
                end
            else
                if delta > 0.0005 then wantBlink = true; blinkColA, blinkColB = colReich, colNeutral
                elseif delta < -0.0005 then wantBlink = true; blinkColA, blinkColB = colUSSR, colNeutral end
            end
        end

        local blinkFast = (math.floor(t*6) % 2) == 0
        local drawCol = wantBlink and (blinkFast and blinkColA or blinkColB) or baseCol

        local base = math.min(panelW, panelH) * 0.05
        local sz = math.floor(base * math.Clamp(scale or 1.8, 0.5, 4.0))
        local bx, by = math.floor(px - sz/2), math.floor(py - sz/2)

        surface.SetDrawColor(colShadow) surface.DrawRect(bx+2, by+2, sz, sz)
        surface.SetDrawColor(40,42,46,230) surface.DrawRect(bx, by, sz, sz)
        surface.SetDrawColor(drawCol) surface.DrawRect(bx+2, by+2, sz-4, sz-4)
        surface.SetDrawColor(colBorder) surface.DrawOutlinedRect(bx, by, sz, sz, 2)

        draw.SimpleText(label, "WW2_MapIcon", bx + sz/2 + 1, by + sz/2 + 1, Color(0,0,0,180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(label, "WW2_MapIcon", bx + sz/2,     by + sz/2,     Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if clamped then
            surface.SetDrawColor(drawCol)
            DrawArrowToCenter(bx + sz/2, by + sz/2, cx, cy, math.max(10, sz*0.25))
        end

        table.insert(LastMarkers, {kind="point", label=label, x=bx, y=by, w=sz, h=sz})
    end
end

local function PointInRect(x, y, r) return x >= r.x and y >= r.y and x <= r.x + r.w and y <= r.y + r.h end
local function PointInCircle(x, y, c) local dx, dy = x - c.x, y - c.y return (dx*dx + dy*dy) <= (c.r * c.r) end

function WW2_AbrirMenuDespliegue(selectedClassId)
    
-- [[ TANQUISTA: helpers ]] 
local function IsTanquistaClass(cls)
    return cls == WW2.CLASE.REICH_TANQUISTA or cls == WW2.CLASE.USSR_TANQUISTA
end

local function GetFactionSide()
    return LocalPlayer():GetNWString("ww2_faction","")
end

local function WW2_OpenTankCategoryMenu(onChooseCat)
    local scrW, scrH = ScrW(), ScrH()
    local f = vgui.Create("DFrame")
    f:SetSize(scrW * 0.32, scrH * 0.24)
    f:Center()
    f:SetTitle("DESPLIEGUE TANQUISTA")
    f:MakePopup()

    local btnLight = vgui.Create("DButton", f)
    btnLight:SetText("TANQUES LIGEROS")
    btnLight:SetSize(f:GetWide()-40, 48)
    btnLight:SetPos(20, 50)
    btnLight.DoClick = function()
        if IsValid(f) then f:Close() end
        if onChooseCat then onChooseCat("light") end
    end

    local btnMedium = vgui.Create("DButton", f)
    btnMedium:SetText("TANQUES MEDIANOS")
    btnMedium:SetSize(f:GetWide()-40, 48)
    btnMedium:SetPos(20, 110)
    btnMedium.DoClick = function()
        if IsValid(f) then f:Close() end
        if onChooseCat then onChooseCat("medium") end
    end
end

local TANKS_BY_SIDE = {
    reich = {
        light  = { "lvs_pz1_mow", "lvs_pz2_mow", "lvs_pz38t_mow" },
        medium = { "lvs_pz3_mow", "lvs_pz4c_mow" },
    },
    ussr = {
        light  = { "lvs_bt7_tb", "lvs_t26_33", "lvs_t60" },
        medium = { "lvs_t34_40", "lvs_t28_38" },
    }
}

local function WW2_OpenTankListMenu(category, onChooseClass)
    local side = GetFactionSide()
    local list = (TANKS_BY_SIDE[side] and TANKS_BY_SIDE[side][category]) or {}
    if not list or #list == 0 then
        chat.AddText(Color(255,80,80), "[WW2] No hay tanques disponibles para tu facción/categoría.")
        return
    end
    local scrW, scrH = ScrW(), ScrH()
    local f = vgui.Create("DFrame")
    f:SetSize(scrW * 0.36, 80 + 56 * #list)
    f:Center()
    f:SetTitle(string.upper(side) .. " - " .. string.upper(category))
    f:MakePopup()

    local y = 40
    for _, cls in ipairs(list) do
        local b = vgui.Create("DButton", f)
        b:SetText(cls)
        b:SetSize(f:GetWide()-40, 48)
        b:SetPos(20, y)
        y = y + 56
        b.DoClick = function()
            if IsValid(f) then f:Close() end
            if onChooseClass then onChooseClass(cls) end
        end
    end
end
-- [[ /TANQUISTA: helpers ]]

-- [[ Opciones de transporte: PIE / AUTO / CAMION ]]
local function WW2_SendDeployWithTransport(destType, label, transport)
    transport = transport or "pie"
    if WW2_SelectedClassFromMenu then
        net.Start("WW2_ElegirClase")
            net.WriteString(tostring(WW2_SelectedClassFromMenu))
        net.SendToServer()
    end
    net.Start("WW2_DeployTo")
        net.WriteString(destType or "")
        net.WriteString(label or "")
        net.WriteString(transport or "pie")
    net.SendToServer()
end

local function WW2_OpenTransportDialog(destType, label, allowTruck)
    if IsValid(WW2_TRANSPORT_DIALOG) then WW2_TRANSPORT_DIALOG:Remove() end

    -- Flujo especial TANQUISTA: solo base y abre categorías/lista de tanques
    if IsTanquistaClass(selectedClassId) then
        if destType ~= "base" then return end
        WW2_OpenTankCategoryMenu(function(cat)
            WW2_OpenTankListMenu(cat, function(lvsClass)
                WW2_SendDeployWithTransport("base", "", lvsClass)
            end)
        end)
        return
    end

    -- Flujo normal (PIE/AUTO/CAMION)
    local scrW, scrH = ScrW(), ScrH()
    local f = vgui.Create("DFrame"); WW2_TRANSPORT_DIALOG = f
    f:SetSize(scrW * 0.32, scrH * 0.28)
    f:Center()
    f:SetTitle("")
    f:ShowCloseButton(true)
    f:MakePopup()
    f.Paint = function(self, w, h)
        surface.SetDrawColor(18,18,22,245) surface.DrawRect(0,0,w,h)
        draw.SimpleText("Despliegue en", "WW2_ClassTitle", w*0.5, h*0.18, Color(230,230,230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local function MakeOptButton(caption, yFrac, key)
        local btn = vgui.Create("DButton", f)
        btn:SetSize(f:GetWide() * 0.8, 38)
        btn:SetPos(f:GetWide()*0.1, f:GetTall()*yFrac)
        btn:SetText("")
        btn.Paint = function(self,w,h)
            surface.SetDrawColor(35,35,35,230) surface.DrawRect(0,0,w,h)
            surface.SetDrawColor(255,255,255,35) surface.DrawOutlinedRect(0,0,w,h,2)
            local clr = self:IsHovered() and Color(255,255,255) or Color(220,220,220)
            draw.SimpleText(caption, "WW2_DeathBtn", w/2, h/2, clr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btn.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            if IsValid(f) then f:Remove() end
            WW2_SendDeployWithTransport(destType, label, key)
        end
        return btn
    end

    MakeOptButton("PIE",   0.40, "pie")
    MakeOptButton("AUTO",  0.60, "auto")
    if allowTruck then
        MakeOptButton("CAMION", 0.80, "camion")
    end
end
-- [[ /Opciones de transporte ]]

WW2_SelectedClassFromMenu = selectedClassId
local scrW, scrH = ScrW(), ScrH()
    local frame = vgui.Create("DFrame"); WW2_DEPLOY_FRAME = frame
    frame:SetSize(scrW, scrH)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame.Paint = function(self, w, h)
        surface.SetDrawColor(10,10,12,245) surface.DrawRect(0,0,w,h)
        draw.SimpleText("DESPLIEGUE", "WW2_ClassTitle", w*0.5, h*0.14, Color(230,230,230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Selecciona tu punto de entrada (click en mapa)", "WW2_Pie", w*0.5, h*0.20, Color(210,210,210,180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local mapW, mapH = math.floor(scrW*0.60), math.floor(scrH*0.45)
    local mapX, mapY = math.floor((scrW - mapW)/2), math.floor(scrH*0.24)

    local mapPanel = vgui.Create("DPanel", frame)
    mapPanel:SetPos(mapX, mapY)
    mapPanel:SetSize(mapW, mapH)
    mapPanel.Paint = function(self, w, h)
        surface.SetDrawColor(20,20,20,255) surface.DrawRect(0,0,w,h)
        local camEnt = FindDeployCam()
        if not IsValid(camEnt) then
            draw.SimpleText("Sin cámara de despliegue.", "WW2_Opcion", w*0.5, h*0.5, Color(230,80,80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("Usa: ww2_cam_create (admin) para crear una.", "WW2_Pie", w*0.5, h*0.5 + 24, Color(220,220,220,180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            local sx, sy = self:LocalToScreen(0, 0)
            local yaw = camEnt:GetAngles().y
            local origin = camEnt:GetPos() + Vector(0,0,CAM_HEIGHT)
            local view = {origin=origin, angles=Angle(90, yaw, 0), x=sx, y=sy, w=w, h=h, fov=camEnt.GetCamFOV and camEnt:GetCamFOV() or 70, drawviewmodel=false, drawhud=false, znear=3}

            render.RenderView(view)
            
            -- ✅ FIX: Usar nueva función de proyección
            local pts = CollectMarkerScreenPos(view, sx, sy, w, h)

            render.SetScissorRect(sx, sy, sx + w, sy + h, true)
            local scale = math.Clamp(cvarIconScale:GetFloat(), 0.5, 4.0)
            DrawMarkers(pts, w, h, scale, sx, sy, view)
            render.SetScissorRect(0, 0, 0, 0, false)

            surface.SetDrawColor(255,255,255,25) surface.DrawOutlinedRect(0,0,w,h,2)
            draw.SimpleText("Click: Bases (círculos) / Puntos (cuadrados)", "WW2_Pie", 8, 8, Color(230,230,230,200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    mapPanel.OnMousePressed = function(self, mcode)
        if mcode ~= MOUSE_LEFT then return end
        local mx, my = gui.MousePos()
        local sx, sy = self:LocalToScreen(0,0)
        if mx < sx or my < sy or mx > sx + self:GetWide() or my > sy + self:GetTall() then return end
        local px, py = mx - sx, my - sy
        for _, mk in ipairs(LastMarkers) do
            if mk.kind == "base" and PointInCircle(px, py, mk) then
                local side = LocalPlayer():GetNWString("ww2_faction","")
                if side == mk.side then
                    WW2_OpenTransportDialog("base", "", true)
                end
                return
            end
        end
        for _, mk in ipairs(LastMarkers) do
            if mk.kind == "point" and PointInRect(px, py, mk) then
                if not WW2_CanDeployToPoint(mk.label or "") then surface.PlaySound("buttons/button10.wav"); return end
                if IsTanquistaClass(selectedClassId) then return end 
                WW2_OpenTransportDialog("point", mk.label or "", false)
                return
            end
        end
    end

    local function MakeButton(txt, xFrac, yFrac, onClick)
        local btn = vgui.Create("DButton", frame)
        btn:SetSize(scrW*0.22, scrH*0.06)
        btn:SetPos(scrW*xFrac - btn:GetWide()/2, scrH*yFrac)
        btn:SetText("")
        btn.Paint = function(self,w,h)
            surface.SetDrawColor(30,30,30,230) surface.DrawRect(0,0,w,h)
            surface.SetDrawColor(255,255,255,30) surface.DrawOutlinedRect(0,0,w,h,2)
            local clr = self:IsHovered() and Color(255,255,255) or Color(220,220,220)
            draw.SimpleText(txt, "WW2_DeathBtn", w/2, h/2, clr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        btn.DoClick = function() surface.PlaySound("buttons/button14.wav"); onClick() end
        return btn
    end

    MakeButton("Cancelar", 0.5, 0.84, function()
        if IsValid(frame) then frame:Remove() end
        local fac = LocalPlayer():GetNWString("ww2_faction", "")
        if fac == WW2.FACCION.REICH then
            WW2_AbrirMenuClases_Reich()
        elseif fac == WW2.FACCION.USSR then
            WW2_AbrirMenuClases_USSR()
        else
            WW2_AbrirMenu()
        end
    end)
end


-- Cerrar el menú al confirmar despliegue
if CLIENT then
    net.Receive("WW2_DeployAck", function()
        if IsValid(WW2_DEPLOY_FRAME) then
            WW2_DEPLOY_FRAME:Remove()
            WW2_DEPLOY_FRAME = nil
        end
    end)
end