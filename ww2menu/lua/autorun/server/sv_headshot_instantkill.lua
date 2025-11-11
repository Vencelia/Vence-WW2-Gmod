-- sv_headshot_instantkill.lua
-- Headshot: muerte instantánea
-- Casco (Reich/USSR): 99% desvío (una vez por vida) + bodygroup "headwear" + casco físico que sale disparado
-- Diferencia visual por facción:
--   - USSR: headwear 1→0 (quitar), casco soviético
--   - Reich: headwear 0→1 (quitar), casco alemán
-- Sonidos:
--   - Si el casco te salva: SOLO metal
--   - Si NO te salva y mueres: body break, pero SOLO en PlayerDeath (muerte real)

if SERVER then
    local METAL_HIT_SND  = "physics/metal/metal_solid_impact_bullet2.wav"
    local BODY_BREAK_SND = "physics/body/body_medium_break2.wav"
    local HELMET_CHANCE  = 0.99
    
    -- ✅ Modelos de casco por facción
    local HELMET_MODEL_USSR  = "models/half-dead/red orchestra 2/sov/w_helmet.mdl"
    local HELMET_MODEL_REICH = "models/half-dead/red orchestra 2/ger/w_helmet.mdl"
    
    local NW_HELMET_USED = "WW2_HelmetConsumed"

    -- Debug helper
    CreateConVar("ww2_helmet_debug", "0", FCVAR_ARCHIVE, "Debug del casco (logs en server)")
    local function DPrint(...)
        if GetConVar("ww2_helmet_debug"):GetBool() then
            print("[WW2 Helmet]", ...)
        end
    end

    -- Limpieza de hooks por si existían previos
    hook.Remove("ScalePlayerDamage", "WW2_HeadshotInstantKill")
    hook.Remove("EntityTakeDamage", "WW2_BlockAfterHelmet_ETD")
    hook.Remove("EntityTakeDamage", "WW2_HeadshotFallback")
    hook.Remove("PlayerShouldTakeDamage", "WW2_BlockAfterHelmet_PSTD")
    hook.Remove("PlayerSpawn", "WW2_ResetHelmetUse")
    hook.Remove("PlayerDeath", "WW2_BodyBreakOnHeadshotDeath")

    -- Ventana mini de invulnerabilidad para blindar contra otros hooks
    local function ArmInvulnFrame(ply, dur) ply.__WW2_HelmetInvulnUntil = CurTime() + (dur or 0.12) end
    local function InInvulnFrame(ply) return IsValid(ply) and ply.__WW2_HelmetInvulnUntil and CurTime() <= ply.__WW2_HelmetInvulnUntil end

    -- Reset por vida
    hook.Add("PlayerSpawn", "WW2_ResetHelmetUse", function(ply)
        if not IsValid(ply) then return end
        ply:SetNWBool(NW_HELMET_USED, false)
        ply.__WW2_HelmetInvulnUntil = nil
        ply.__WW2_PlayBodyBreakOnDeath = nil

        -- NO resetear bodygroup aquí, eso lo maneja ww2_factions_sv.lua
    end)

    -- ✅ Obtener facción del jugador
    local function GetPlayerFaction(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return nil end
        
        -- Intentar WW2_GetFaction primero
        if isfunction(ply.WW2_GetFaction) then 
            local fac = ply:WW2_GetFaction()
            if fac and fac ~= "" then return fac end
        end
        
        -- Fallback a NetworkVar
        local fac = ply:GetNWString("ww2_faction", "")
        if fac == "reich" or fac == "ussr" then return fac end
        
        return nil
    end

    -- ✅ Verificar si el jugador tiene casco activo según su facción
    local function HasHelmetActive(ply)
        local fac = GetPlayerFaction(ply)
        if not fac then return false end
        
        -- Buscar bodygroup "headwear"
        local idx = ply:FindBodygroupByName("headwear")
        if not idx or idx < 0 then
            idx = ply:FindBodygroupByName("Headwear")
        end
        if not idx or idx < 0 then
            idx = ply:FindBodygroupByName("HEADWEAR")
        end
        
        if not idx or idx < 0 then 
            DPrint("No se encontró bodygroup 'headwear' en", ply:Nick())
            return false 
        end
        
        local currentValue = ply:GetBodygroup(idx)
        
        -- USSR: headwear=1 significa CON casco
        -- Reich: headwear=0 significa CON casco
        if fac == "ussr" then
            return currentValue == 1
        elseif fac == "reich" then
            return currentValue == 0
        end
        
        return false
    end

    -- ✅ Quitar casco visualmente según facción
    local function RemoveHelmetVisual(ply)
        local fac = GetPlayerFaction(ply)
        if not fac then return end
        
        local idx = ply:FindBodygroupByName("headwear")
        if not idx or idx < 0 then
            idx = ply:FindBodygroupByName("Headwear")
        end
        if not idx or idx < 0 then
            idx = ply:FindBodygroupByName("HEADWEAR")
        end
        
        if not idx or idx < 0 then return end
        
        if fac == "ussr" then
            -- USSR: 1→0 (quitar casco)
            ply:SetBodygroup(idx, 0)
            DPrint("Casco USSR removido para", ply:Nick(), "(headwear 1→0)")
        elseif fac == "reich" then
            -- Reich: 0→1 (quitar casco)
            ply:SetBodygroup(idx, 1)
            DPrint("Casco Reich removido para", ply:Nick(), "(headwear 0→1)")
        end
    end

    -- Calcula dirección de impacto SIN usar dmginfo luego (evitamos CTakeDamageInfo nulo en timer)
    local function CalcImpactDir(ply, dmginfo)
        local headPos
        local boneId = ply:LookupBone("ValveBiped.Bip01_Head1")
        if boneId then headPos = select(1, ply:GetBonePosition(boneId)) end
        if not headPos or headPos == vector_origin then headPos = ply:EyePos() end

        -- 1) Desde posición del impacto si existe
        if dmginfo and dmginfo.GetDamagePosition then
            local ok, hitpos = pcall(dmginfo.GetDamagePosition, dmginfo)
            if ok and hitpos and hitpos ~= vector_origin then
                local dir = (headPos - hitpos)
                if not dir:IsZero() then return dir:GetNormalized() end
            end
        end

        -- 2) Desde el atacante hacia la cabeza
        if dmginfo and dmginfo.GetAttacker then
            local ok2, atk = pcall(dmginfo.GetAttacker, dmginfo)
            if ok2 and IsValid(atk) then
                if atk.GetShootPos then
                    local dir = (headPos - atk:GetShootPos())
                    if not dir:IsZero() then return dir:GetNormalized() end
                elseif atk.EyePos then
                    local dir = (headPos - atk:EyePos())
                    if not dir:IsZero() then return dir:GetNormalized() end
                end
            end
        end

        -- 3) Fallback: opuesto a la vista del jugador
        return (-ply:GetAimVector()):GetNormalized()
    end

    -- ✅ Spawnea y lanza un casco físico desde la cabeza (modelo según facción)
    local function SpawnFlyingHelmet(ply, launchDir)
        local fac = GetPlayerFaction(ply)
        if not fac then return end
        
        -- Modelo según facción
        local helmetModel = (fac == "reich") and HELMET_MODEL_REICH or HELMET_MODEL_USSR
        util.PrecacheModel(helmetModel)

        -- Esperar al próximo tick para tener huesos/pos estable
        timer.Simple(0, function()
            if not IsValid(ply) then return end

            -- Posición y ángulo (hueso cabeza si existe)
            local headPos, headAng
            local boneId = ply:LookupBone("ValveBiped.Bip01_Head1")
            if boneId then headPos, headAng = ply:GetBonePosition(boneId) end
            if not headPos or headPos == vector_origin then
                headPos = ply:EyePos()
                headAng = ply:EyeAngles()
            end

            local dir = (isvector(launchDir) and not launchDir:IsZero()) and launchDir or (-ply:GetAimVector()):GetNormalized()

            -- Intento 1: prop_physics (si el modelo tiene malla de físicas)
            local ent = ents.Create("prop_physics")
            if not IsValid(ent) then
                DPrint("No se pudo crear prop_physics")
                return
            end

            ent:SetModel(helmetModel)
            ent:SetPos(headPos + dir * 2 + Vector(0,0,4))
            ent:SetAngles(headAng or AngleRand())
            ent:Spawn()
            ent:Activate()

            -- Seguridad de colisiones
            ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            ent:SetOwner(ply)

            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                phys:Wake()
                phys:EnableGravity(true)
                phys:EnableDrag(true)
                local force = 350 + math.random(0,150)
                phys:ApplyForceCenter(dir * force * phys:GetMass())
                phys:AddAngleVelocity(VectorRand() * 200)
                -- Autoremove
                timer.Simple(8, function() if IsValid(ent) then ent:Remove() end end)
                DPrint("Spawn OK prop_physics casco", fac)
                return
            end

            -- Si no hay física, fallback a prop_dynamic
            DPrint("Sin física en modelo; usando prop_dynamic fallback")
            ent:Remove()

            local dyn = ents.Create("prop_dynamic")
            if not IsValid(dyn) then
                DPrint("No se pudo crear prop_dynamic")
                return
            end

            dyn:SetModel(helmetModel)
            dyn:SetPos(headPos + dir * 2 + Vector(0,0,4))
            dyn:SetAngles(headAng or AngleRand())
            dyn:Spawn()
            dyn:SetMoveType(MOVETYPE_FLYGRAVITY)
            dyn:SetSolid(SOLID_NONE)
            dyn:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
            dyn:SetOwner(ply)

            local speed = 350 + math.random(0,150)
            dyn:SetVelocity(dir * speed)
            dyn:SetLocalAngularVelocity(Angle(math.random(-200,200), math.random(-200,200), math.random(-200,200)))

            timer.Simple(8, function() if IsValid(dyn) then dyn:Remove() end end)
            DPrint("Spawn OK prop_dynamic casco (fallback)", fac)
        end)
    end

    -- Decide: desviado (metal + casco sale) o letal (sonará al morir)
    hook.Add("ScalePlayerDamage", "WW2_HeadshotInstantKill", function(ply, hitgroup, dmginfo)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply:Alive() then return end
        
        -- ✅ DEBUG: Ver qué hitgroup está llegando
        DPrint(string.format("Daño recibido: %s | Hitgroup: %d | Daño: %.1f", 
            ply:Nick(), hitgroup, dmginfo:GetDamage()))
        
        if hitgroup ~= HITGROUP_HEAD then return end

        DPrint("¡HEADSHOT DETECTADO en", ply:Nick(), "!")

        -- ✅ Verificar si tiene casco según facción Y no lo ha usado
        if HasHelmetActive(ply) and not ply:GetNWBool(NW_HELMET_USED, false) and math.random() < HELMET_CHANCE then
            ply:SetNWBool(NW_HELMET_USED, true)
            ArmInvulnFrame(ply, 0.12)

            DPrint("CASCO SALVÓ A", ply:Nick())

            -- Anular daño
            dmginfo:SetDamage(0)
            dmginfo:ScaleDamage(0)
            if dmginfo.SetDamageForce then dmginfo:SetDamageForce(Vector(0,0,0)) end

            -- ✅ Feedback + QUITAR bodygroup + casco físico
            ply:EmitSound(METAL_HIT_SND, 75, 100, 1, CHAN_AUTO)
            RemoveHelmetVisual(ply)

            local dir = CalcImpactDir(ply, dmginfo)
            SpawnFlyingHelmet(ply, dir)

            ply.__WW2_PlayBodyBreakOnDeath = nil
            return
        end

        -- Letal
        DPrint("HEADSHOT LETAL en", ply:Nick())
        dmginfo:SetDamage(ply:Health() + 1000)
        ply.__WW2_PlayBodyBreakOnDeath = true
    end)
    
    -- ✅ FALLBACK: Hook adicional para detectar headshots si ScalePlayerDamage falla
    hook.Add("EntityTakeDamage", "WW2_HeadshotFallback", function(ply, dmginfo)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply:Alive() then return end
        if InInvulnFrame(ply) then return end -- Ya procesado
        
        -- Detectar headshot por posición del daño
        local hitPos = dmginfo:GetDamagePosition()
        if hitPos and hitPos ~= Vector(0,0,0) then
            local headBone = ply:LookupBone("ValveBiped.Bip01_Head1")
            if headBone then
                local headPos = ply:GetBonePosition(headBone)
                local dist = hitPos:Distance(headPos)
                
                -- Si el impacto está cerca de la cabeza (radio 15 unidades)
                if dist < 15 then
                    DPrint("HEADSHOT DETECTADO POR POSICIÓN en", ply:Nick(), "- Distancia:", dist)
                    
                    -- Verificar si tiene casco
                    if HasHelmetActive(ply) and not ply:GetNWBool(NW_HELMET_USED, false) and math.random() < HELMET_CHANCE then
                        ply:SetNWBool(NW_HELMET_USED, true)
                        ArmInvulnFrame(ply, 0.12)
                        
                        DPrint("CASCO SALVÓ A", ply:Nick(), "(fallback)")
                        
                        -- Anular daño
                        dmginfo:SetDamage(0)
                        dmginfo:ScaleDamage(0)
                        if dmginfo.SetDamageForce then dmginfo:SetDamageForce(Vector(0,0,0)) end
                        
                        -- Efectos
                        ply:EmitSound(METAL_HIT_SND, 75, 100, 1, CHAN_AUTO)
                        RemoveHelmetVisual(ply)
                        
                        local dir = CalcImpactDir(ply, dmginfo)
                        SpawnFlyingHelmet(ply, dir)
                        
                        ply.__WW2_PlayBodyBreakOnDeath = nil
                        return true -- Bloquear daño
                    else
                        -- Headshot letal
                        DPrint("HEADSHOT LETAL en", ply:Nick(), "(fallback)")
                        dmginfo:SetDamage(ply:Health() + 1000)
                        ply.__WW2_PlayBodyBreakOnDeath = true
                    end
                end
            end
        end
    end)

    -- Blindajes redundantes
    hook.Add("EntityTakeDamage", "WW2_BlockAfterHelmet_ETD", function(ent, dmginfo)
        if not IsValid(ent) or not ent:IsPlayer() then return end
        if InInvulnFrame(ent) then
            dmginfo:SetDamage(0)
            dmginfo:ScaleDamage(0)
            if dmginfo.SetDamageForce then dmginfo:SetDamageForce(Vector(0,0,0)) end
        end
    end)

    hook.Add("PlayerShouldTakeDamage", "WW2_BlockAfterHelmet_PSTD", function(ply, attacker)
        if InInvulnFrame(ply) then return false end
    end)

    -- Sonido de "romper cuerpo" solo si realmente murió
    hook.Add("PlayerDeath", "WW2_BodyBreakOnHeadshotDeath", function(victim, inflictor, attacker)
        if not IsValid(victim) then return end
        if victim.__WW2_PlayBodyBreakOnDeath then
            victim:EmitSound(BODY_BREAK_SND, 75, 100, 1, CHAN_AUTO)
        end
        victim.__WW2_PlayBodyBreakOnDeath = nil
    end)
    
    -- ✅ COMANDO DE TESTING
    concommand.Add("ww2_test_headshot", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        
        ply:ChatPrint("=== TEST HEADSHOT SYSTEM ===")
        ply:ChatPrint("Facción: " .. (GetPlayerFaction(ply) or "NINGUNA"))
        ply:ChatPrint("Tiene casco activo: " .. tostring(HasHelmetActive(ply)))
        ply:ChatPrint("Casco usado: " .. tostring(ply:GetNWBool(NW_HELMET_USED, false)))
        
        -- Mostrar bodygroups
        local idx = ply:FindBodygroupByName("headwear") or ply:FindBodygroupByName("Headwear") or ply:FindBodygroupByName("HEADWEAR")
        if idx and idx >= 0 then
            ply:ChatPrint("Headwear bodygroup índice: " .. idx)
            ply:ChatPrint("Headwear valor actual: " .. ply:GetBodygroup(idx))
            ply:ChatPrint("Headwear opciones totales: " .. ply:GetBodygroupCount(idx))
        else
            ply:ChatPrint("⚠️ NO se encontró bodygroup 'headwear'")
        end
        
        ply:ChatPrint("Usa 'ww2_helmet_debug 1' para ver logs detallados")
    end)
    
    concommand.Add("ww2_force_headshot", function(ply, cmd, args)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        
        -- Simular un headshot
        local dmg = DamageInfo()
        dmg:SetDamage(50)
        dmg:SetAttacker(ply)
        dmg:SetInflictor(ply)
        dmg:SetDamageType(DMG_BULLET)
        
        -- Posición de la cabeza
        local headBone = ply:LookupBone("ValveBiped.Bip01_Head1")
        if headBone then
            local headPos = ply:GetBonePosition(headBone)
            dmg:SetDamagePosition(headPos)
        end
        
        ply:TakeDamageInfo(dmg)
        ply:ChatPrint("[WW2] Headshot simulado - revisa consola del servidor")
    end)
end