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


-- ============================================================================
-- ICONOS 2D SOBRE PUNTOS DE CAPTURA Y BASES (EN LA PANTALLA DEL JUGADOR)
-- ============================================================================
-- Muestra un círculo de color según facción (Reich / URSS / Neutral) + letra/nombre
-- a cierta altura sobre cada punto de captura o base.
-- Se dibuja SIEMPRE que existan las entidades en el mapa.
-- ============================================================================

surface.CreateFont("WW2_Cap_Marker", {
    font = "Montserrat",
    size = ScreenScale(7),
    weight = 800
})

local WW2_MARKER_HEIGHT = 1200 -- aprox. 30 metros arriba
local WW2_MARKER_RADIUS_POINT = 14
local WW2_MARKER_RADIUS_BASE  = 18

local function WW2_DrawFilledCircle(x, y, r, col)
    draw.NoTexture()
    surface.SetDrawColor(col.r, col.g, col.b, col.a or 255)
    local seg = math.max(20, math.floor(r * 0.8))
    local poly = {}
    for i = 0, seg - 1 do
        local a = (i / seg) * math.pi * 2
        poly[#poly+1] = { x = x + math.cos(a) * r, y = y + math.sin(a) * r }
    end
    surface.DrawPoly(poly)
end

local function WW2_GetOwnerColor(owner)
    if owner == "reich" then return colReich end
    if owner == "ussr"  then return colUSSR end
    return colNeutral
end

local function WW2_DrawWorldMarkerForEnt(ent, label, isBase)
    if not IsValid(ent) then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local basePos = ent:GetPos() + Vector(0,0, WW2_MARKER_HEIGHT)
    local scr = basePos:ToScreen()
    local x, y = scr.x, scr.y

    -- Clamp simple a la pantalla para evitar perderse por completo
    local sw, sh = ScrW(), ScrH()
    x = math.Clamp(x, 0, sw)
    y = math.Clamp(y, 0, sh)

    -- Resolver dueño: primero cap_owner (NW2 / NW1), para bases caer a base_side
    local owner = ""
    if ent.GetNW2String then
        owner = ent:GetNW2String("cap_owner","")
    end
    if (owner == nil or owner == "" or owner == "neutral") and ent.GetNWString then
        owner = ent:GetNWString("cap_owner","")
    end

    if isBase and (owner == nil or owner == "" or owner == "neutral") then
        local side = ""
        if ent.GetNW2String then
            side = ent:GetNW2String("base_side","")
        end
        if (side == nil or side == "" or side == "neutral") and ent.GetNWString then
            side = ent:GetNWString("base_side","")
        end
        owner = side
    end

    local col = WW2_GetOwnerColor(owner)

    local r = isBase and WW2_MARKER_RADIUS_BASE or WW2_MARKER_RADIUS_POINT

    -- Sombra
    WW2_DrawFilledCircle(x+2, y+2, r+2, Color(0,0,0,200))
    -- Círculo de facción
    WW2_DrawFilledCircle(x, y, r, col)

    -- Texto centrado (letra o nombre)
    local txt = label or ""
    if txt ~= "" then
        draw.SimpleText(txt, "WW2_Cap_Marker", x+1, y+1,
            Color(0,0,0,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(txt, "WW2_Cap_Marker", x,   y,
            Color(255,255,255,255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

hook.Add("HUDPaint", "WW2_CaptureAndBase_WorldMarkers", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local mySide = lp:GetNWString("ww2_faction","")

    -- =========================
    --  AGRUPAR PUNTOS POR BRAZO
    -- =========================
    local capsByArm = {}
    local freeCaps  = {}

    local function GetCapOwner(cp)
        local o = ""
        if cp.GetNW2String then
            o = cp:GetNW2String("cap_owner","")
        end
        if (o == nil or o == "" or o == "neutral") and cp.GetNWString then
            o = cp:GetNWString("cap_owner","")
        end
        return o or ""
    end

    local function EnsureArm(ai, abid)
        local key = tostring(ai) .. ":" .. tostring(abid)
        local arm = capsByArm[key]
        if not arm then
            local baseEnt = Entity(abid)
            local baseSide = ""
            if IsValid(baseEnt) then
                if baseEnt.GetNW2String then
                    baseSide = baseEnt:GetNW2String("base_side","")
                end
                if (baseSide == nil or baseSide == "" or baseSide == "neutral") and baseEnt.GetNWString then
                    baseSide = baseEnt:GetNWString("base_side","")
                end
            end
            arm = { key = key, baseId = abid, baseSide = baseSide, caps = {}, maxOrder = 0 }
            capsByArm[key] = arm
        end
        return arm
    end

    local function AddCap(cp)
        local ai = cp:GetNWInt("arm_index", 0)
        local ab = cp:GetNWInt("arm_base_id", 0)
        if ai > 0 and ab > 0 then
            local arm = EnsureArm(ai, ab)
            local order = cp:GetNWInt("arm_order", 0)
            if order > arm.maxOrder then
                arm.maxOrder = order
            end
            table.insert(arm.caps, cp)
        else
            table.insert(freeCaps, cp)
        end
    end

    for _, cp in ipairs(ents.FindByClass("ww2_cap_point")) do
        if IsValid(cp) then AddCap(cp) end
    end
    for _, cp in ipairs(ents.FindByClass("ww2_capture_point")) do
        if IsValid(cp) then AddCap(cp) end
    end

    local showCap = {}  -- ent -> true
    local ownBaseVisible = { reich = false, ussr = false }
    local enemyBaseUnlocked = { reich = false, ussr = false }

    local function ProcessArm(arm)
        local caps = arm.caps
        if #caps == 0 then return end

        table.sort(caps, function(a, b)
            return a:GetNWInt("arm_order", 0) < b:GetNWInt("arm_order", 0)
        end)

        local n = #caps

        local function ownerAt(i)
            return GetCapOwner(caps[i])
        end

        local side = mySide
        if side ~= "reich" and side ~= "ussr" then
            -- espectador u otra facción: ve todo
            for _, cp in ipairs(caps) do
                showCap[cp] = true
            end
            return
        end

        local baseSide = arm.baseSide
        if baseSide ~= "reich" and baseSide ~= "ussr" then
            -- si no se conoce base_side, mostrar todo este brazo
            for _, cp in ipairs(caps) do
                showCap[cp] = true
            end
            return
        end

        if side == baseSide then
            -- Progreso desde la base del brazo (lado que lo inicia)
            local k = 0
            for i = 1, n do
                if ownerAt(i) == side then
                    k = k + 1
                else
                    break
                end
            end

            if k == 0 then
                -- BASE - A1 : veo base propia + primer punto neutral
                ownBaseVisible[side] = true
                showCap[caps[1]] = true
            elseif k < n then
                -- A1-B1, B1-C1, ... : veo último capturado y el siguiente
                showCap[caps[k]]   = true
                showCap[caps[k+1]] = true
            else
                -- Todos capturados por este lado: veo último cap + base ENEMIGA
                showCap[caps[n]] = true
                enemyBaseUnlocked[side] = true
            end
        else
            -- Progreso desde el lado contrario (base enemiga)
            local k = 0
            for rev = 1, n do
                local idx = n + 1 - rev
                if ownerAt(idx) == side then
                    k = k + 1
                else
                    break
                end
            end

            if k == 0 then
                -- BASE ENEMIGA - último punto: veo mi base + último punto neutral
                ownBaseVisible[side] = true
                showCap[caps[n]] = true
            elseif k < n then
                -- C1-B1, B1-A1, ... desde el otro lado
                local lastIdx  = n + 1 - k      -- último capturado por este lado
                local frontIdx = n - k          -- siguiente a capturar
                showCap[caps[lastIdx]]  = true
                showCap[caps[frontIdx]] = true
            else
                -- Todos capturados por este lado: veo último cap + base enemiga
                local lastIdx = n + 1 - k -- = 1
                showCap[caps[lastIdx]] = true
                enemyBaseUnlocked[side] = true
            end
        end
    end

    for _, arm in pairs(capsByArm) do
        ProcessArm(arm)
    end

    -- Puntos sin brazo: se muestran siempre
    for _, cp in ipairs(freeCaps) do
        showCap[cp] = true
    end

    -- 1) Dibujar puntos de captura que tocan a este jugador
    for cp, _ in pairs(showCap) do
        if IsValid(cp) then
            local lbl = cp:GetNWString("cap_label","")
            WW2_DrawWorldMarkerForEnt(cp, lbl, false)
        end
    end

    -- 2) BASES (Reich / URSS) con visibilidad según avance del brazo
    for _, b in ipairs(ents.FindByClass("ww2_base_reich")) do
        if IsValid(b) then
            local side = "reich"
            if b.GetNW2String then
                local s2 = b:GetNW2String("base_side","")
                if s2 ~= nil and s2 ~= "" then side = s2 end
            end
            if b.GetNWString and (side == nil or side == "" or side == "neutral") then
                local s1 = b:GetNWString("base_side","")
                if s1 ~= nil and s1 ~= "" then side = s1 end
            end

            local showBase = false
            if mySide == "reich" then
                -- BASE propia solo visible mientras no hayas avanzado en TODOS los brazos (k == 0)
                showBase = ownBaseVisible["reich"]
            elseif mySide == "ussr" then
                -- Soviet solo ve la base Reich cuando en algún brazo llegó al último punto
                showBase = enemyBaseUnlocked["ussr"]
            else
                showBase = true
            end

            if showBase then
                WW2_DrawWorldMarkerForEnt(b, "BASE", true)
            end
        end
    end

    for _, b in ipairs(ents.FindByClass("ww2_base_ussr")) do
        if IsValid(b) then
            local side = "ussr"
            if b.GetNW2String then
                local s2 = b:GetNW2String("base_side","")
                if s2 ~= nil and s2 ~= "" then side = s2 end
            end
            if b.GetNWString and (side == nil or side == "" or side == "neutral") then
                local s1 = b:GetNWString("base_side","")
                if s1 ~= nil and s1 ~= "" then side = s1 end
            end

            local showBase = false
            if mySide == "ussr" then
                showBase = ownBaseVisible["ussr"]
            elseif mySide == "reich" then
                showBase = enemyBaseUnlocked["reich"]
            else
                showBase = true
            end

            if showBase then
                WW2_DrawWorldMarkerForEnt(b, "BASE", true)
            end
        end
    end
end)



