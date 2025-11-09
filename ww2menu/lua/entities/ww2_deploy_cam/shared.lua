ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "WW2 Deploy Camera"
ENT.Category = "WW2"
ENT.Author = "WW2"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "CamFOV")
    if SERVER then
        self:SetCamFOV(70)
    end
end
