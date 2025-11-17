AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local CAP_RADIUS = 1000            -- unidades
local CAP_SPEED  = 0.05            -- velocidad de captura
local NEXT_INDEX = NEXT_INDEX or 0 -- (ya no se usa para el label, pero lo dejo por compat)

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

    -- ⚠️ IMPORTANTE PARA SAVE:
    -- NO reseteamos cap_control / cap_owner / cap_label aquí.
    -- Solo aseguramos un radio por defecto si no hay nada.
    if self:GetNWInt("cap_radius", 0) <= 0 then
        self:SetNWInt("cap_radius", CAP_RADIUS)
    end

    self._lastThink = CurTime()

    -- Sistema de brazos de ataque
    if SERVER and WW2 and WW2.Arms and WW2.Arms.AssignArmToCapPoint then
        WW2.Arms.AssignArmToCapPoint(self)
    end
end

-- Toggle congelado con E (útil para reposicionar rápido)
function ENT:Use(activator, caller)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(not phys:IsMotionEnabled())
        phys:Wake()
        if IsValid(activator) and activator:IsPlayer() then
            activator:ChatPrint("[WW2] " .. (phys:IsMotionEnabled() and "Movimiento activado" or "Congelado"))
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
    local dt  = now - (self._lastThink or now)
    self._lastThink = now

    -- 🔁 COMPAT SAVE:
    -- Si venimos de un SAVE, _control será nil. Lo sincronizamos UNA vez con lo que traiga el NW.
    if self._control == nil then
        self._control = self:GetNWFloat("cap_control", 0)
    end

    -- Si este punto no tiene nombre (cap_label) todavía, intentamos asignarle su brazo/identificador.
    if not self._ww2ArmLabelChecked then
        self._ww2ArmLabelChecked = true
        local lbl = self:GetNWString("cap_label", "")
        if (lbl == nil or lbl == "") and WW2 and WW2.Arms and WW2.Arms.AssignArmToCapPoint then
            WW2.Arms.AssignArmToCapPoint(self)
        end
    end

    local radius = self:GetNWInt("cap_radius", CAP_RADIUS)
    local r, u   = CountFactionsInSphere(self:GetPos(), radius)

    -- Filtro por brazo: solo el punto frontal del brazo cuenta y respeta cooldown de avance
    if WW2 and WW2.Arms and WW2.Arms.FilterCountsForCap then
        r, u = WW2.Arms.FilterCountsForCap(self, r, u)
    end

    local advantage = r - u
    local contested = (r > 0 and u > 0 and r == u)

    -- Progreso de captura
    local ctrl = self._control or 0
    if advantage ~= 0 then
        ctrl = ctrl + (CAP_SPEED * advantage * dt)
        if ctrl > 1.0 then ctrl = 1.0 end
        if ctrl < -1.0 then ctrl = -1.0 end
    end
    self._control = ctrl

    -- ✅ LÓGICA MEJORADA: el owner solo cambia al cruzar el centro
    local prevOwner = self:GetNWString("cap_owner", "")
    local owner     = prevOwner

    -- Captura completa
    if ctrl >= 0.999 then
        owner = "reich"
    elseif ctrl <= -0.999 then
        owner = "ussr"
    else
        -- Si el punto es de Reich
        if owner == "reich" then
            -- Pierde el punto solo si la barra cruza a negativo (lado soviético)
            if ctrl < 0 then
                owner = ""
            end

        -- Si el punto es de USSR
        elseif owner == "ussr" then
            -- Pierde el punto solo si la barra cruza a positivo (lado reich)
            if ctrl > 0 then
                owner = ""
            end

        -- Si el punto es neutral
        else
            -- En estado neutral no forzamos dueño aquí.
            -- El owner pasará a reich/ussr solo cuando ctrl llegue a ±0.999
            -- en el bloque de "Captura completa" de arriba.
        end
    end

    self:SetNWFloat("cap_control", ctrl)
    self:SetNWBool("cap_contested", contested)
    self:SetNWString("cap_owner", owner)

    -- 🔁 Notificar cambio de dueño al sistema de brazos (frente + cooldown)
    if owner ~= prevOwner then
        if WW2 and WW2.Arms and WW2.Arms.RebuildFrontState then
            WW2.Arms.RebuildFrontState()
        end
        if (owner == "reich" or owner == "ussr") and WW2 and WW2.Arms and WW2.Arms.NotifyAdvance then
            WW2.Arms.NotifyAdvance(self, owner)
        end
    end

    self:NextThink(CurTime() + 0.1)
    return true
end
