WW2_SelectedClassFromMenu = WW2_SelectedClassFromMenu or nil
if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

-- === LVS: aliveness check (client) ===
function IsLVSAliveClient(veh)
    if not IsValid(veh) then return false end
    if veh.GetIsDestroyed and veh:GetIsDestroyed() then return false end
    if veh.GetDisabled     and veh:GetDisabled()     then return false end
    -- HP APIs
    local hp, maxhp
    if veh.GetHP then
        local okH, v = pcall(function() return veh:GetHP() end)
        if okH then hp = tonumber(v) end
    end
    if veh.GetMaxHP then
        local okM, v = pcall(function() return veh:GetMaxHP() end)
        if okM then maxhp = tonumber(v) end
    end
    if hp ~= nil and maxhp ~= nil and maxhp > 0 and hp <= 0 then return false end
    -- NW flags
    if veh.GetNW2Bool and (veh:GetNW2Bool("LVS_Destroyed", false) or veh:GetNW2Bool("lvs_destroyed", false) or veh:GetNW2Bool("LVS_Disabled", false)) then
        return false
    end
    if veh.GetNWBool and (veh:GetNWBool("LVS_Destroyed", false) or veh:GetNWBool("lvs_destroyed", false) or veh:GetNWBool("LVS_Disabled", false)) then
        return false
    end
    -- NW HP exact 0 means dead
    local hp2 = veh.GetNW2Int and veh:GetNW2Int("LVS_HP", -1) or -1
    if hp2 == 0 then return false end
    local hp1 = veh.GetNWInt and veh:GetNWInt("LVS_HP", -1) or -1
    if hp1 == 0 then return false end
    return true
end




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
local cvarDeployProjScale = CreateClientConVar("ww2_deploy_proj_scale", "1.00", true, false, "Escala radial de proyección en mapa de deploy (0.5..3.0)", 0.5, 3.0)

-- Calibración fina (ajustar si hay offset residual)
local OFFSET_X = 0
local OFFSET_Y = 0

local CPTrend = {}
local LastMarkers = {}
local LastVehicles = {}

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
    -- Escala radial para alejar/acercar los iconos desde el centro del panel (configurable)
    local scale = 1.0
    if cvarDeployProjScale then scale = math.Clamp(cvarDeployProjScale:GetFloat(), 0.5, 3.0) end
    local cx, cy = w * 0.5, h * 0.5
    screenX = cx + (screenX - cx) * scale
    screenY = cy + (screenY - cy) * scale
    
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
-- ==============================
--  LVS ICONS (solo camiones vivos)
-- ==============================
local _lvsCache = { nextScan = 0, reich = {}, ussr = {} }

function GetLocalSide()
    local lp = LocalPlayer()
    if not IsValid(lp) then return nil end
    -- Primero por string
    local s = (lp:GetNWString("ww2_faction","") or ""):lower()
    if s:find("reich") then return "reich" end
    if s:find("ussr") or s:find("sov") then return "ussr" end
    -- Fallback por Team/NWInt si existiera
    local t = lp:Team()
    if TEAM_REICH and t == TEAM_REICH then return "reich" end
    if TEAM_USSR  and t == TEAM_USSR  then return "ussr"  end
    local f = lp:GetNWInt("WW2_Faction",0)
    if (TEAM_REICH and f == TEAM_REICH) or f == 1 then return "reich" end
    if (TEAM_USSR  and f == TEAM_USSR)  or f == 2 then return "ussr"  end
    return nil
end

-- Detección conservadora: solo consideramos destruido si APIs/flags lo dicen.
local function IsVehicleDestroyed(veh)
    if not IsValid(veh) then return true end
    if veh.GetIsDestroyed and veh:GetIsDestroyed() then return true end
    if veh.GetDisabled     and veh:GetDisabled()     then return true end

    local hp, maxhp
    if veh.GetHP then
        local okH, v = pcall(function() return veh:GetHP() end)
        if okH then hp = tonumber(v) end
    end
    if veh.GetMaxHP then
        local okM, v = pcall(function() return veh:GetMaxHP() end)
        if okM then maxhp = tonumber(v) end
    end
    if hp ~= nil and maxhp ~= nil and maxhp > 0 then
        if hp <= 0 then return true else return false end
    end

    if veh.GetNW2Bool then
        if veh:GetNW2Bool("LVS_Destroyed", false) or veh:GetNW2Bool("lvs_destroyed", false) or veh:GetNW2Bool("LVS_Disabled", false) then
            return true
        end
    end
    if veh.GetNWBool then
        if veh:GetNWBool("LVS_Destroyed", false) or veh:GetNWBool("lvs_destroyed", false) or veh:GetNWBool("LVS_Disabled", false) then
            return true
        end
    end

    local hp2 = veh.GetNW2Int and veh:GetNW2Int("LVS_HP", -1) or -1
    if hp2 == 0 then return true end
    local hp1 = veh.GetNWInt and veh:GetNWInt("LVS_HP", -1) or -1
    if hp1 == 0 then return true end

    return false
end


local function DrawPlusIcon(px, py, size, fillCol)
    local half = math.floor(size * 0.5)
    local x = math.floor(px - half)
    local y = math.floor(py - half)
    surface.SetDrawColor(0,0,0,150) surface.DrawRect(x, y, size, size)
    surface.SetDrawColor(255,255,255,255) surface.DrawOutlinedRect(x, y, size, size, 1)
    fillCol = fillCol or Color(255,255,255)
    local pad = math.max(3, math.floor(size * 0.2))
    surface.SetDrawColor(fillCol.r, fillCol.g, fillCol.b, 200)
    surface.DrawLine(px, y + pad, px, y + size - pad)
    surface.DrawLine(x + pad, py, x + size - pad, py)
end


-- Invalida cache al destruir/quitar un LVS para que desaparezca rápido del mapa
hook.Add("EntityRemoved","WW2_LVSCacheInvalidate_Map", function(ent)
    if not IsValid(ent) then return end
    local c = ent:GetClass()
    if c == "lvs_wheeldrive_fiat_621" or c == "lvs_wheeldrive_gaz_aaa" then
        if _lvsCache then _lvsCache.nextScan = 0 end
    end
end)
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


local function DrawArrowToCenter(x, y, cx, cy, size, col)
    -- Dibuja una flecha (triángulo) que apunta desde (x,y) hacia el centro (cx,cy)
    -- size controla el largo, col el color opcional
    local ang = math.atan2(cy - y, cx - x) -- radianes
    local len = size or 14                 -- largo total
    local base = len * 0.8                 -- qué tan atrás va la base respecto a la punta
    local half = (len * 0.5) * 0.6         -- medio ancho de la base

    -- Punto punta (un poco hacia la dirección)
    local tipx = x + math.cos(ang) * len
    local tipy = y + math.sin(ang) * len

    -- Centro de la base (detrás de la punta)
    local bx = tipx - math.cos(ang) * base
    local by = tipy - math.sin(ang) * base

    -- Vector perpendicular (para ancho de la base)
    local px = -math.sin(ang)
    local py =  math.cos(ang)

    local p2x = bx + px * half
    local p2y = by + py * half
    local p3x = bx - px * half
    local p3y = by - py * half

    surface.SetDrawColor(col or Color(255,255,255,255))
    surface.DrawPoly({
        {x = tipx, y = tipy},
        {x = p2x,  y = p2y },
        {x = p3x,  y = p3y },
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
            
            -- Precompute flags for click: entIndex + blocked for my faction if base is captured by enemy
            local entIndex = b:EntIndex()
            local owner = (b.GetNW2String and b:GetNW2String("cap_owner","")) or (b.GetNWString and b:GetNWString("cap_owner","")) or ""
            local base_side = (b.GetNW2String and b:GetNW2String("base_side","")) or (b.GetNWString and b:GetNWString("base_side","")) or ""
            local mySide = LocalPlayer():GetNWString("ww2_faction","")
            local blocked = (mySide == base_side) and (owner ~= "" and owner ~= base_side)
        

            -- Color por propietario actual (mantener texto original)
            local owner = (b.GetNW2String and b:GetNW2String("cap_owner","")) or (b.GetNWString and b:GetNWString("cap_owner","")) or ""
            local drawCol = col
            if owner == "reich" then drawCol = colReich elseif owner == "ussr" then drawCol = colUSSR end


            surface.SetDrawColor(0,0,0,180); DrawCircle(px+2, py+2, r)
            surface.SetDrawColor(drawCol); DrawCircle(px, py, r)
            surface.SetDrawColor(40,42,46,240); DrawCircle(px, py, r-4)

            draw.SimpleText(text, "WW2_MapBase", px+1, py+1, Color(0,0,0,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(text, "WW2_MapBase", px,   py,   Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            table.insert(LastMarkers, {kind="base", side=side, x=px, y=py, r=r, entIndex=b:EntIndex()})
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
function DrawLVSIcons(panelW, panelH, scale, view)

    LastVehicles = {}
    if not WorldToScreenCustom then return end

    
    -- ⛔ Ocultar camiones si eres TANQUISTA
    if IsTanquistaClass(WW2_SelectedClassFromMenu) then return end
local side = GetLocalSide and GetLocalSide() or nil
    if side ~= "reich" and side ~= "ussr" then return end

    -- Facción -> clase exacta
    local class = (side == "reich") and "lvs_wheeldrive_fiat_621" or "lvs_wheeldrive_gaz_aaa"

    -- Recolectar solo vehículos válidos y no destruidos
    local vehicles = {}
    for _, ent in ipairs(ents.FindByClass(class) or {}) do
        if IsValid(ent) and IsLVSAliveClient(ent) then
            if IsLVSAliveClient(ent) then vehicles[#vehicles+1] = ent end
        end
    end
    if #vehicles == 0 then return end

    -- Numeración estable por EntIndex()
    table.sort(vehicles, function(a,b) return a:EntIndex() < b:EntIndex() end)

    local fill = (side == "reich") and Color(80,150,255) or Color(220,60,60)
    local sz   = math.Clamp(math.floor(math.min(panelW, panelH) * 0.05 * (scale or 1)), 14, 40)

    local viewData = { origin = view.origin, angles = view.angles, fov = view.fov, w = panelW, h = panelH }

    for i = 1, #vehicles do
        local ent = vehicles[i]
        local px, py = WorldToScreenCustom(ent:GetPos(), viewData)
        if px and py then
            px, py = ClampToPanel(px, py, panelW, panelH, 10)

            -- Cuadrado sólido centrado
            local bx, by = math.floor(px - sz/2), math.floor(py - sz/2)
            surface.SetDrawColor(fill)        surface.DrawRect(bx, by, sz, sz)
            surface.SetDrawColor(0,0,0,180)   surface.DrawOutlinedRect(bx, by, sz, sz, 1)

            -- Número blanco centrado (1..N)
            draw.SimpleText(tostring(i), "WW2_MapIcon", bx + sz/2, by + sz/2, Color(255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            table.insert(LastVehicles, { x = bx, y = by, w = sz, h = sz, entIndex = ent:EntIndex() })
        end
    end
end
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
            local view = {origin=origin, angles=Angle(90, yaw, 0), x=sx, y=sy, w=w, h=h, fov=camEnt.GetCamFOV and camEnt:GetCamFOV() or 200, drawviewmodel=false, drawhud=false, znear=3}

            render.RenderView(view)
            
            -- ✅ FIX: Usar nueva función de proyección
            local pts = CollectMarkerScreenPos(view, sx, sy, w, h)

            render.SetScissorRect(sx, sy, sx + w, sy + h, true)
            local scale = math.Clamp(cvarIconScale:GetFloat(), 0.5, 4.0)
            DrawMarkers(pts, w, h, scale, sx, sy, view)
            -- LVS vivos
            DrawLVSIcons(w, h, scale, view)
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
        -- Prioridad: click en camiones LVS dibujados
        for _, v in ipairs(LastVehicles or {}) do
            if PointInRect(px, py, v) then
                -- ⛔ TANQUISTA NO PUEDE USAR CAMIONES (ni enviar net)
                if IsTanquistaClass(WW2_SelectedClassFromMenu) then surface.PlaySound("buttons/button10.wav"); return end

                -- Si el jugador eligió clase en el menú, reenviarla al server
                                -- Validar entidad y que esté viva
                local ent = Entity(v.entIndex)
                if not IsValid(ent) or not IsLVSAliveClient(ent) then surface.PlaySound("buttons/button10.wav"); return end

                if WW2_SelectedClassFromMenu then
                    net.Start("WW2_ElegirClase")
                        net.WriteString(tostring(WW2_SelectedClassFromMenu))
                    net.SendToServer()
                end
                -- Enviar deploy tipo 'vehicle' con EntIndex como label
                net.Start("WW2_DeployTo")
                    net.WriteString("vehicle")
                    net.WriteString(tostring(v.entIndex))
                    net.WriteString("")
                net.SendToServer()
                surface.PlaySound("buttons/button14.wav")
                return
            end
        end
        for _, mk in ipairs(LastMarkers) do
            if mk.kind == "base" and PointInCircle(px, py, mk) then
-- TANQUISTA: solo puede desplegar en SU base principal NO capturada.
if IsTanquistaClass and IsTanquistaClass(WW2_SelectedClassFromMenu) then
    if mk.entIndex then
        local ent = Entity(mk.entIndex)
        if IsValid(ent) then
            local mySide    = LocalPlayer():GetNWString("ww2_faction","")
            local base_side = (ent.GetNW2String and ent:GetNW2String("base_side","")) or (ent.GetNWString and ent:GetNWString("base_side","")) or ""
            local owner     = (ent.GetNW2String and ent:GetNW2String("cap_owner","")) or (ent.GetNWString and ent:GetNWString("cap_owner","")) or ""
            -- Solo permitir si la base es de mi facción y el dueño actual es la facción original
            if not (mySide == base_side and owner == base_side) then
                surface.PlaySound("buttons/button10.wav")
                return
            end
        end
    end
end

                -- Lógica de apertura con el MISMO menú existente (sin crear uno nuevo)
                do
                    local ent = (mk.entIndex and Entity(mk.entIndex)) or nil
                    if IsValid(ent) then
                        local mySide    = LocalPlayer():GetNWString("ww2_faction","")
                        local base_side = (ent.GetNW2String and ent:GetNW2String("base_side","")) or (ent.GetNWString and ent:GetNWString("base_side","")) or ""
                        local owner     = (ent.GetNW2String and ent:GetNW2String("cap_owner","")) or (ent.GetNWString and ent:GetNWString("cap_owner","")) or ""
                        -- 1) Mi base capturada por enemigo: bloquear (ya hay early return arriba, pero doble seguro)
                        if mySide == base_side and owner ~= "" and owner ~= base_side then
                            surface.PlaySound("buttons/button10.wav")
                            return
                        end
                        -- 2) Base enemiga capturada por mi facción: abrir diálogo sin CAMION
                        if mySide ~= base_side and owner == mySide then
    if IsTanquistaClass and IsTanquistaClass(WW2_SelectedClassFromMenu) then surface.PlaySound("buttons/button10.wav"); return end
    WW2_OpenTransportDialog("base", tostring(mk.entIndex or ""), false)
    return
end
                        -- 3) Caso normal: mi base propia libre o enemiga sin capturar → comportamiento normal
                        if mySide == mk.side then
                            WW2_OpenTransportDialog("base", tostring(mk.entIndex or ""), true)
                            return
                        end
                    end
                end
    
                -- HARD BLOCK: si mi propia base fue capturada por el enemigo, NO abrir menú ni enviar nets
                do
                    if mk.blocked then surface.PlaySound("buttons/button10.wav"); return end
                    local ent = (mk.entIndex and Entity(mk.entIndex)) or nil
                    if IsValid(ent) then
                        local mySide   = LocalPlayer():GetNWString("ww2_faction","")
                        local base_side = (ent.GetNW2String and ent:GetNW2String("base_side","")) or (ent.GetNWString and ent:GetNWString("base_side","")) or ""
                        local owner     = (ent.GetNW2String and ent:GetNW2String("cap_owner","")) or (ent.GetNWString and ent:GetNWString("cap_owner","")) or ""
                        if mySide == base_side and owner ~= "" and owner ~= base_side then
                            surface.PlaySound("buttons/button10.wav")
                            return
                        end
                    end
                end
    
-- Si es base enemiga capturada por mi facción -> ofrecer PIE/AUTO y mandar net directo con entIndex
do
    local side = LocalPlayer():GetNWString("ww2_faction","")
    if mk.entIndex then
        local ent = Entity(mk.entIndex)
        if IsValid(ent) then
            local base_side = (ent.GetNW2String and ent:GetNW2String("base_side","")) or (ent.GetNWString and ent:GetNWString("base_side","")) or ""
            local owner     = (ent.GetNW2String and ent:GetNW2String("cap_owner","")) or (ent.GetNWString and ent:GetNWString("cap_owner","")) or ""
            if base_side ~= side and owner == side then
                local m = DermaMenu()
                m:AddOption("PIE", function()
                    net.Start("WW2_DeployTo")
                        net.WriteString("base")
                        net.WriteString(tostring(mk.entIndex))
                        net.WriteString("pie")
                    net.SendToServer()
                end)
                m:AddOption("AUTO", function()
                    net.Start("WW2_DeployTo")
                        net.WriteString("base")
                        net.WriteString(tostring(mk.entIndex))
                        net.WriteString("auto")
                    net.SendToServer()
                end)
                m:Open()
                return
            end
        end
    end
end

                -- Bloqueo: si mi propia base fue capturada por el enemigo, no abrir diálogo
                do
                    if mk.entIndex then
                        local ent = Entity(mk.entIndex)
                        if IsValid(ent) then
                            local base_side = (ent.GetNW2String and ent:GetNW2String("base_side","")) or (ent.GetNWString and ent:GetNWString("base_side","")) or ""
                            local owner     = (ent.GetNW2String and ent:GetNW2String("cap_owner","")) or (ent.GetNWString and ent:GetNWString("cap_owner","")) or ""
                            if side == base_side and owner ~= "" and owner ~= base_side then
                                surface.PlaySound("buttons/button10.wav")
                                return
                            end
                        end
                    end
                end

                local side = LocalPlayer():GetNWString("ww2_faction","")
                if side == mk.side then
                    WW2_OpenTransportDialog("base", tostring(mk.entIndex or ""), true)
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
            WW2_DEPLOY_FRAME:Close()
        end
    end)
end