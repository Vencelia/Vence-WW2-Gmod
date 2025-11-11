AddCSLuaFile("entities/ww2_deploy_cam/shared.lua")
AddCSLuaFile("entities/ww2_deploy_cam/cl_init.lua")

-- ============================================
-- ✅ FIX: Cámara con ángulo correcto para vista cenital
-- ============================================

-- Crear una cámara donde mira el admin con vista cenital perfecta (pitch 90°)
concommand.Add("ww2_cam_create", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then 
        ply:ChatPrint("[WW2] Solo admins pueden crear cámaras.")
        return 
    end
    
    local tr = ply:GetEyeTrace()
    if not tr.Hit then 
        ply:ChatPrint("[WW2] Apunta al suelo para colocar la cámara.")
        return 
    end

    local ent = ents.Create("ww2_deploy_cam")
    if not IsValid(ent) then 
        ply:ChatPrint("[WW2] Error: No se pudo crear la entidad ww2_deploy_cam.")
        return 
    end
    
    -- Posición: donde apuntas + altura
    ent:SetPos(tr.HitPos + Vector(0, 0, 5))
    
    -- ✅ ÁNGULO CORRECTO: Pitch 90° (mirando directo hacia abajo)
    -- El yaw define la orientación del "norte" del mapa
    local yaw = ply:EyeAngles().y
    ent:SetAngles(Angle(90, yaw, 0))  -- CAMBIADO de Angle(180, yaw, 0)
    
    ent:Spawn()
    ent:Activate()

    ply:ChatPrint("[WW2] ✅ Cámara creada con vista cenital (pitch 90°).")
    ply:ChatPrint("[WW2] • Gírala con physgun para cambiar el YAW (norte del mapa).")
    ply:ChatPrint("[WW2] • Muévela a la altura/posición deseada.")
    ply:ChatPrint("[WW2] • Usa E para congelar/descongelar.")
end)

-- Eliminar todas las cámaras
concommand.Add("ww2_cam_delete", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then 
        ply:ChatPrint("[WW2] Solo admins pueden eliminar cámaras.")
        return 
    end
    
    local count = 0
    for _, e in ipairs(ents.FindByClass("ww2_deploy_cam")) do
        if IsValid(e) then
            e:Remove()
            count = count + 1
        end
    end
    
    ply:ChatPrint(string.format("[WW2] ✅ Cámaras eliminadas: %d", count))
end)

-- ============================================
-- COMANDOS ADICIONALES DE UTILIDAD
-- ============================================

-- Listar todas las cámaras con su posición y ángulo
concommand.Add("ww2_cam_list", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local cams = ents.FindByClass("ww2_deploy_cam")
    if #cams == 0 then
        ply:ChatPrint("[WW2] No hay cámaras en el mapa.")
        return
    end
    
    ply:ChatPrint(string.format("[WW2] ===== Cámaras (%d) =====", #cams))
    for i, cam in ipairs(cams) do
        local pos = cam:GetPos()
        local ang = cam:GetAngles()
        local fov = cam.GetCamFOV and cam:GetCamFOV() or 70
        
        ply:ChatPrint(string.format(
            "[%d] Pos: %.0f,%.0f,%.0f | Ang: P=%.0f Y=%.0f R=%.0f | FOV: %.0f",
            i, pos.x, pos.y, pos.z, ang.p, ang.y, ang.r, fov
        ))
    end
end)

-- Teletransportarse a la cámara más cercana
concommand.Add("ww2_cam_goto", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local cams = ents.FindByClass("ww2_deploy_cam")
    if #cams == 0 then
        ply:ChatPrint("[WW2] No hay cámaras en el mapa.")
        return
    end
    
    -- Buscar la más cercana
    local closest, closestDist
    for _, cam in ipairs(cams) do
        local dist = ply:GetPos():DistToSqr(cam:GetPos())
        if not closest or dist < closestDist then
            closest = cam
            closestDist = dist
        end
    end
    
    if IsValid(closest) then
        ply:SetPos(closest:GetPos() + Vector(0, 0, 64))
        ply:SetEyeAngles(Angle(0, closest:GetAngles().y, 0))
        ply:ChatPrint("[WW2] ✅ Teletransportado a la cámara.")
    end
end)

-- Ajustar el FOV de la cámara más cercana
concommand.Add("ww2_cam_fov", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local fov = tonumber(args[1])
    if not fov or fov < 30 or fov > 300 then
        ply:ChatPrint("[WW2] Uso: ww2_cam_fov <30-120>")
        ply:ChatPrint("[WW2] Ejemplo: ww2_cam_fov 70")
        return
    end
    
    local cams = ents.FindByClass("ww2_deploy_cam")
    if #cams == 0 then
        ply:ChatPrint("[WW2] No hay cámaras en el mapa.")
        return
    end
    
    -- Buscar la más cercana
    local closest, closestDist
    for _, cam in ipairs(cams) do
        local dist = ply:GetPos():DistToSqr(cam:GetPos())
        if not closest or dist < closestDist then
            closest = cam
            closestDist = dist
        end
    end
    
    if IsValid(closest) and closest.SetCamFOV then
        closest:SetCamFOV(fov)
        ply:ChatPrint(string.format("[WW2] ✅ FOV cambiado a %.0f°", fov))
    end
end)

-- Corregir el ángulo de todas las cámaras existentes (pitch a 90°)
concommand.Add("ww2_cam_fix_angles", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local cams = ents.FindByClass("ww2_deploy_cam")
    if #cams == 0 then
        ply:ChatPrint("[WW2] No hay cámaras en el mapa.")
        return
    end
    
    local fixed = 0
    for _, cam in ipairs(cams) do
        local ang = cam:GetAngles()
        if math.abs(ang.p - 90) > 1 then -- Solo corregir si no está en 90°
            local newAng = Angle(90, ang.y, 0)
            cam:SetAngles(newAng)
            fixed = fixed + 1
        end
    end
    
    ply:ChatPrint(string.format("[WW2] ✅ Cámaras corregidas: %d/%d", fixed, #cams))
    if fixed > 0 then
        ply:ChatPrint("[WW2] Todas las cámaras ahora tienen pitch 90° (vista cenital perfecta).")
    end
end)

-- ============================================
-- VALIDACIÓN AL CARGAR EL MAPA
-- ============================================

-- Advertir si hay cámaras con ángulo incorrecto
hook.Add("InitPostEntity", "WW2_CamValidation", function()
    timer.Simple(2, function()
        local cams = ents.FindByClass("ww2_deploy_cam")
        local badCams = 0
        
        for _, cam in ipairs(cams) do
            local ang = cam:GetAngles()
            if math.abs(ang.p - 90) > 1 then
                badCams = badCams + 1
            end
        end
        
        if badCams > 0 then
            print(string.format("[WW2] ⚠️ ADVERTENCIA: %d cámara(s) con ángulo incorrecto detectadas.", badCams))
            print("[WW2] Usa 'ww2_cam_fix_angles' en consola para corregirlas automáticamente.")
            
            -- Notificar a todos los admins conectados
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and ply:IsAdmin() then
                    ply:ChatPrint(string.format("[WW2] ⚠️ %d cámara(s) con ángulo incorrecto.", badCams))
                    ply:ChatPrint("[WW2] Usa: ww2_cam_fix_angles")
                end
            end
        end
    end)
end)

-- ============================================
-- DEBUG: Mostrar info de cámara en HUD (servidor)
-- ============================================

concommand.Add("ww2_cam_debug", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    if ply:GetNWBool("WW2_CamDebug", false) then
        ply:SetNWBool("WW2_CamDebug", false)
        ply:ChatPrint("[WW2] Debug de cámara desactivado.")
    else
        ply:SetNWBool("WW2_CamDebug", true)
        ply:ChatPrint("[WW2] Debug de cámara activado. Usa nuevamente para desactivar.")
    end
end)

-- ============================================
-- CLIENTE: Visualización de debug
-- ============================================

if CLIENT then
    hook.Add("HUDPaint", "WW2_CamDebugDraw", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:GetNWBool("WW2_CamDebug", false) then return end
        
        local cams = ents.FindByClass("ww2_deploy_cam")
        if #cams == 0 then return end
        
        surface.CreateFont("WW2_CamDebug", {font="Courier New", size=14, weight=700})
        
        local y = 100
        for i, cam in ipairs(cams) do
            if not IsValid(cam) then continue end
            
            local pos = cam:GetPos()
            local ang = cam:GetAngles()
            local fov = cam.GetCamFOV and cam:GetCamFOV() or 70
            local dist = ply:GetPos():Distance(pos)
            
            -- Color: verde si pitch=90, rojo si no
            local col = (math.abs(ang.p - 90) < 1) and Color(0,255,0) or Color(255,100,100)
            
            draw.SimpleText(
                string.format("[Cam %d] Dist: %.0fm | P: %.1f° Y: %.1f° | FOV: %.0f", 
                    i, dist/39.37, ang.p, ang.y, fov
                ),
                "WW2_CamDebug",
                10, y,
                col
            )
            
            -- Dibujar línea en 3D hacia la cámara
            local pos2D = pos:ToScreen()
            if pos2D.visible then
                surface.SetDrawColor(col)
                surface.DrawLine(ScrW()/2, ScrH()/2, pos2D.x, pos2D.y)
            end
            
            y = y + 18
        end
    end)
end