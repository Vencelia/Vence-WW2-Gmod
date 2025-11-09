AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local function NearestCapLabel(pos)
    local best, bestDist, bestLabel
    for _, cp in ipairs(ents.FindByClass("ww2_cap_point")) do
        if IsValid(cp) then
            local d = pos:DistToSqr(cp:GetPos())
            if not best or d < bestDist then
                best, bestDist = cp, d
                bestLabel = cp:GetNWString("cap_label","")
            end
        end
    end
    return bestLabel or ""
end

function ENT:Initialize()
    self:SetModel("models/hunter/blocks/cube05x05x05.mdl")
    self:DrawShadow(true)
    self:SetNoDraw(false)
    self:SetSolid(SOLID_VPHYSICS)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) phys:Wake() end
    local label = NearestCapLabel(self:GetPos())
    self:SetNWString("link_label", label)
    self:SetNWString("spawn_side", "reich")
end
