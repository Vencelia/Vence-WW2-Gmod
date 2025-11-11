AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local CAP_RADIUS = 1000            -- unidades
local CAP_SPEED  = 0.05            -- ✅ CAMBIADO: 0.12 → 0.03 (4x más lento)
local NEXT_INDEX = NEXT_INDEX or 0 -- índice global simple para nombres A/B/C

function ENT:Initialize()
    self:SetModel("models/props_lab/citizenradio.mdl")
    self:DrawShadow(true)
    self:SetNoDraw(false)

    self:SetSolid(SOLID_VPHYSICS)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    end

    -- Estado de captura
    self._control = 0.0 -- -1 (USSR) .. 0 neutral .. +1 (REICH)
    self:SetNWFloat("cap_control", self._control)
    self:SetNWBool("cap_contested", false)
    self:SetNWString("cap_owner", "") -- "", "reich", "ussr"
    self:SetNWInt("cap_radius", CAP_RADIUS)

    -- Nombre del punto: A, B, C...
    NEXT_INDEX = (NEXT_INDEX or 0) + 1
    local idx = math.min(NEXT_INDEX, 26)
    local label = string.char(64 + idx) -- 65->A
    self:SetNWString("cap_label", label)

    self._lastThink = CurTime()
end

-- Toggle congelado con E (útil para reposicionar rápido)
function ENT:Use(activator, caller)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(not phys:IsMotionEnabled())
        phys:Wake()
        if IsValid(activator) and activator:IsPlayer() then
            activator:ChatPrint("[WW2] "..(phys:IsMotionEnabled() and "Movimiento activado" or "Congelado"))
        end
    end
end

local function CountFactionsInSphere(pos, radius)
    local reich, ussr = 0, 0
    for _, ply in ipairs(ents.FindInSphere(pos, radius)) do
        if IsValid(ply) and ply:IsPlayer() and ply:Alive() then
            local fac = ply:GetNWString("ww2_faction", "")
            if fac == "reich" then
                reich = reich + 1
            elseif fac == "ussr" then
                ussr = ussr + 1
            end
        end
    end
    return reich, ussr
end

function ENT:Think()
    local now = CurTime()
    local dt = now - (self._lastThink or now)
    self._lastThink = now

    local radius = self:GetNWInt("cap_radius", 1000)
    local r, u = CountFactionsInSphere(self:GetPos(), radius)
    local advantage = r - u
    local contested = (r > 0 and u > 0 and r == u)

    -- progreso
    local ctrl = self._control or 0
    if advantage ~= 0 then
        ctrl = ctrl + (CAP_SPEED * advantage * dt)
        if ctrl > 1.0 then ctrl = 1.0 end
        if ctrl < -1.0 then ctrl = -1.0 end
    end
    self._control = ctrl

    -- ✅ NUEVA LÓGICA MEJORADA: El propietario solo cambia al cruzar el centro
    local owner = self:GetNWString("cap_owner", "")
    
    -- Captura completa
    if ctrl >= 0.999 then
        owner = "reich"
    elseif ctrl <= -0.999 then
        owner = "ussr"
    else
        -- ✅ FIX: Mantener dueño actual hasta que la barra cruce el centro (0)
        
        -- Si el punto es de Reich (owner = "reich")
        if owner == "reich" then
            -- Solo pierde el punto si la barra cruza a territorio negativo (USSR)
            if ctrl < 0 then
                owner = "" -- Pasa a neutral al cruzar el centro
            end
        
        -- Si el punto es de USSR (owner = "ussr")
        elseif owner == "ussr" then
            -- Solo pierde el punto si la barra cruza a territorio positivo (Reich)
            if ctrl > 0 then
                owner = "" -- Pasa a neutral al cruzar el centro
            end
        
        -- Si el punto es neutral (owner = "")
        else
            -- Se asigna al primero que llegue cerca del extremo
            if ctrl >= 0.8 then
                owner = "reich"
            elseif ctrl <= -0.8 then
                owner = "ussr"
            end
        end
    end

    self:SetNWFloat("cap_control", ctrl)
    self:SetNWBool("cap_contested", contested)
    self:SetNWString("cap_owner", owner)

    self:NextThink(CurTime() + 0.1)
    return true
end