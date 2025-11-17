-- lua/autorun/server/ww2_arms_sv.lua
-- Sistema de "brazos" de ataque para ww2_cap_point / ww2_capture_point
-- + lógica de frente de captura y cooldown por brazo/bando

if not SERVER then return end

WW2 = WW2 or {}
WW2.Arms = WW2.Arms or {}
local Arms = WW2.Arms

local CAP_CLASSES  = { "ww2_cap_point", "ww2_capture_point" }
local BASE_CLASSES = { "ww2_base_reich", "ww2_base_ussr" }

local function IsCapPoint(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    for _, cls in ipairs(CAP_CLASSES) do
        if c == cls then return true end
    end
    return false
end

local function IsBase(ent)
    if not IsValid(ent) then return false end
    local c = ent:GetClass()
    for _, cls in ipairs(BASE_CLASSES) do
        if c == cls then return true end
    end
    return false
end

local function GetAllBases()
    local out = {}
    for _, cls in ipairs(BASE_CLASSES) do
        for _, e in ipairs(ents.FindByClass(cls)) do
            if IsValid(e) then out[#out+1] = e end
        end
    end
    return out
end

local function GetAllCapPoints()
    local out = {}
    for _, cls in ipairs(CAP_CLASSES) do
        for _, e in ipairs(ents.FindByClass(cls)) do
            if IsValid(e) then out[#out+1] = e end
        end
    end
    return out
end

-- Devuelve letra siguiente: "" -> "A", "A"->"B", ..., "Z"->"Z"
local function NextLetter(str)
    if not str or str == "" then return "A" end
    local byte = string.byte(str)
    if not byte then return "A" end
    if byte >= string.byte("Z") then return "Z" end
    byte = byte + 1
    return string.char(byte)
end

-- Calcula próximo índice de brazo para una base concreta
local function NextArmIndexForBase(baseEnt)
    if not IsValid(baseEnt) then return 1 end
    local baseId = baseEnt:EntIndex()
    local maxIdx = 0

    for _, cp in ipairs(GetAllCapPoints()) do
        if IsValid(cp) and cp:GetNWInt("arm_base_id", 0) == baseId then
            local idx = cp:GetNWInt("arm_index", 0)
            if idx > maxIdx then
                maxIdx = idx
            end
        end
    end

    return maxIdx + 1
end

-- Encuentra entidad "padre" más cercana: base o cap point ya existente
local function FindNearestParentForCap(cp)
    if not IsValid(cp) then return nil, nil end

    local pos = cp:GetPos()
    local nearest, nearestDist2, nearestKind = nil, math.huge, nil

    -- Buscar bases
    for _, b in ipairs(GetAllBases()) do
        local d2 = b:GetPos():DistToSqr(pos)
        if d2 < nearestDist2 then
            nearest, nearestDist2, nearestKind = b, d2, "base"
        end
    end

    -- Buscar otros cap points
    for _, other in ipairs(GetAllCapPoints()) do
        if other ~= cp then
            local d2 = other:GetPos():DistToSqr(pos)
            if d2 < nearestDist2 then
                nearest, nearestDist2, nearestKind = other, d2, "cap"
            end
        end
    end

    return nearest, nearestKind
end

-- =======================
--  ASIGNAR BRAZO AL CAP
-- =======================
function Arms.AssignArmToCapPoint(cp)
    if not IsValid(cp) or not IsCapPoint(cp) then return end

    -- Pequeño delay para asegurarnos de que bases y otros puntos existen
    timer.Simple(0, function()
        if not IsValid(cp) then return end

        local parent, kind = FindNearestParentForCap(cp)
        local armIndex, armOrder, armLetter, armBaseId

        if not IsValid(parent) then
            -- No hay nada: brazo 0 sin nombre
            cp:SetNWInt("arm_index", 0)
            cp:SetNWInt("arm_order", 0)
            cp:SetNWInt("arm_base_id", 0)
            cp:SetNWString("arm_letter", "")
            return
        end

        if kind == "base" then
            -- Nuevo brazo: A1, A2, A3...
            armBaseId = parent:EntIndex()
            armIndex  = NextArmIndexForBase(parent)
            armOrder  = 1
            armLetter = "A"
        else
            -- Continuación de brazo: B1, C1... o B2, C2...
            local parentArmIdx   = parent:GetNWInt("arm_index", 0)
            local parentArmOrder = parent:GetNWInt("arm_order", 0)
            local parentLetter   = parent:GetNWString("arm_letter", "")

            -- Si por algún motivo el parent no tiene brazo, tratamos como si fuera base
            if parentArmIdx <= 0 then
                local baseParent, kind2 = FindNearestParentForCap(parent)
                if kind2 == "base" and IsValid(baseParent) then
                    armBaseId = baseParent:EntIndex()
                    armIndex  = NextArmIndexForBase(baseParent)
                else
                    armBaseId = 0
                    armIndex  = 0
                end
                armOrder  = 1
                armLetter = "A"
            else
                armBaseId = parent:GetNWInt("arm_base_id", 0)
                armIndex  = parentArmIdx
                armOrder  = parentArmOrder + 1
                armLetter = NextLetter(parentLetter)
            end
        end

        cp:SetNWInt("arm_base_id", armBaseId or 0)
        cp:SetNWInt("arm_index", armIndex or 0)
        cp:SetNWInt("arm_order", armOrder or 0)
        cp:SetNWString("arm_letter", armLetter or "")

        -- Nombre A1, B1, C2...
        if (armIndex or 0) > 0 and (armLetter or "") ~= "" then
            cp:SetNWString("cap_label", tostring(armLetter) .. tostring(armIndex))
        end

        if Arms.RebuildFrontState then
            Arms.RebuildFrontState()
        end
    end)
end

-- Rebuild global opcional
function Arms.RebuildAllArms()
    for _, cp in ipairs(GetAllCapPoints()) do
        cp:SetNWInt("arm_base_id", 0)
        cp:SetNWInt("arm_index", 0)
        cp:SetNWInt("arm_order", 0)
        cp:SetNWString("arm_letter", "")
    end

    local points = GetAllCapPoints()
    table.sort(points, function(a,b)
        return a:EntIndex() < b:EntIndex()
    end)

    for _, cp in ipairs(points) do
        Arms.AssignArmToCapPoint(cp)
    end
end

-- ==========================
--  FRENTE POR BRAZO / BANDO
-- ==========================

local function GetCapOwner(cp)
    local o = ""
    if cp.GetNW2String then
        o = cp:GetNW2String("cap_owner","")
    end
    if (o == nil or o == "") and cp.GetNWString then
        o = cp:GetNWString("cap_owner","")
    end
    return o or ""
end

local function UpdateFrontForArm(armIndex, armBaseId)
    local list = {}
    for _, cp in ipairs(GetAllCapPoints()) do
        if cp:GetNWInt("arm_index", 0) == armIndex and cp:GetNWInt("arm_base_id", 0) == armBaseId then
            list[#list+1] = cp
        end
    end
    if #list == 0 then return end

    table.sort(list, function(a,b)
        return a:GetNWInt("arm_order", 0) < b:GetNWInt("arm_order", 0)
    end)

    local baseEnt = Entity(armBaseId)
    local baseSide = ""
    if IsValid(baseEnt) then
        if baseEnt.GetNW2String then
            baseSide = baseEnt:GetNW2String("base_side","")
        end
        if (not baseSide or baseSide == "") and baseEnt.GetNWString then
            baseSide = baseEnt:GetNWString("base_side","")
        end
    end

    local function computeFrontIndex(side)
        if side ~= "reich" and side ~= "ussr" then return nil end
        if not baseSide or baseSide == "" then return nil end
        local n = #list

        -- Lado que inicia el brazo (baseSide)
        if side == baseSide then
            local ownedPrefix = 0
            for k = 1, n do
                local o = GetCapOwner(list[k])
                if o == side then
                    ownedPrefix = k
                else
                    break
                end
            end
            local front = ownedPrefix + 1
            if front > n then
                return nil, "enemy_base"
            else
                return front, "cap"
            end
        else
            -- Lado contrario: cuenta desde el final
            local ownedPrefix = 0
            for rev = 1, n do
                local k = n + 1 - rev
                local o = GetCapOwner(list[k])
                if o == side then
                    ownedPrefix = rev
                else
                    break
                end
            end
            local front_rev = ownedPrefix + 1
            if front_rev > n then
                return nil, "enemy_base"
            else
                local idx = n + 1 - front_rev
                return idx, "cap"
            end
        end
    end

    local frontReich = select(1, computeFrontIndex("reich"))
    local frontUSSR  = select(1, computeFrontIndex("ussr"))

    for i, cp in ipairs(list) do
        cp:SetNWBool("cap_front_reich", frontReich == i)
        cp:SetNWBool("cap_front_ussr",  frontUSSR  == i)
    end
end

function Arms.RebuildFrontState()
    -- reset flags
    for _, cp in ipairs(GetAllCapPoints()) do
        cp:SetNWBool("cap_front_reich", false)
        cp:SetNWBool("cap_front_ussr",  false)
    end

    local seen = {}
    for _, cp in ipairs(GetAllCapPoints()) do
        local ai = cp:GetNWInt("arm_index", 0)
        local ab = cp:GetNWInt("arm_base_id", 0)
        if ai > 0 and ab > 0 then
            local key = tostring(ai) .. ":" .. tostring(ab)
            if not seen[key] then
                seen[key] = true
                UpdateFrontForArm(ai, ab)
            end
        end
    end
end

-- ==========================
--  COOLDOWN POR AVANCE
-- ==========================

Arms.LastAdvance = Arms.LastAdvance or {}
local ADVANCE_COOLDOWN = 10 -- segundos

function Arms.NotifyAdvance(cp, side)
    if not IsValid(cp) then return end
    if side ~= "reich" and side ~= "ussr" then return end

    local armIndex = cp:GetNWInt("arm_index", 0)
    local armBase  = cp:GetNWInt("arm_base_id", 0)
    if armIndex <= 0 or armBase <= 0 then return end

    local key = tostring(armIndex) .. ":" .. tostring(armBase) .. ":" .. side
    Arms.LastAdvance[key] = CurTime()
end

-- Filtro para que solo el punto frontal cuente para captura y respete cooldown
function Arms.FilterCountsForCap(cp, reichCount, ussrCount)
    if not IsValid(cp) then return reichCount, ussrCount end

    local idx   = cp:GetNWInt("arm_index", 0)
    local base  = cp:GetNWInt("arm_base_id", 0)
    if idx <= 0 or base <= 0 then
        return reichCount, ussrCount
    end

    local frontReich = cp:GetNWBool("cap_front_reich", false)
    local frontUSSR  = cp:GetNWBool("cap_front_ussr",  false)

    local now = CurTime()

    if frontReich then
        local key = tostring(idx) .. ":" .. tostring(base) .. ":reich"
        local t   = Arms.LastAdvance[key] or 0
        if t ~= 0 and now < t + ADVANCE_COOLDOWN then
            frontReich = false
        end
    end

    if frontUSSR then
        local key = tostring(idx) .. ":" .. tostring(base) .. ":ussr"
        local t   = Arms.LastAdvance[key] or 0
        if t ~= 0 and now < t + ADVANCE_COOLDOWN then
            frontUSSR = false
        end
    end

    -- Si no eres frente para ese bando, no cuenta gente de ese bando
    if not frontReich then reichCount = 0 end
    if not frontUSSR  then ussrCount  = 0 end

    return reichCount, ussrCount
end

print("[WW2] Sistema de brazos de ataque + frente/cooldown cargado (ww2_arms_sv.lua)")
