AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/hunter/blocks/cube05x05x05.mdl")
    self:DrawShadow(false)
    self:SetNoDraw(false)

    self:SetSolid(SOLID_VPHYSICS)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false) -- aparece congelada
        phys:Wake()
    end
end

-- Usar E para congelar/descongelar rápidamente
function ENT:Use(activator, caller)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(not phys:IsMotionEnabled())
        phys:Wake()
    end
end
