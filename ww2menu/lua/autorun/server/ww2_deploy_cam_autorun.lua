AddCSLuaFile("entities/ww2_deploy_cam/shared.lua")
AddCSLuaFile("entities/ww2_deploy_cam/cl_init.lua")

-- Crear una cámara donde mira el admin (yaw acorde a la mirada, pitch 0)
concommand.Add("ww2_cam_create", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local tr = ply:GetEyeTrace()
    if not tr.Hit then return end

    local ent = ents.Create("ww2_deploy_cam")
    if not IsValid(ent) then return end
    ent:SetPos(tr.HitPos + Vector(0,0,5))
    local yaw = ply:EyeAngles().y
    ent:SetAngles(Angle(180, yaw, 0)) -- el yaw del prop define la dirección del "mapa"
    ent:Spawn()
    ent:Activate()

    ply:ChatPrint("[WW2] Cámara creada. Gírala con physgun (yaw) y muévela donde quieras. Usa E para congelar/soltar.")
end)

concommand.Add("ww2_cam_delete", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local count = 0
    for _, e in ipairs(ents.FindByClass("ww2_deploy_cam")) do
        e:Remove()
        count = count + 1
    end
    ply:ChatPrint("[WW2] Cámaras eliminadas: "..count)
end)
