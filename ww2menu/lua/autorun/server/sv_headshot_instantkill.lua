-- sv_headshot_instantkill.lua
-- Headshot: muerte instantánea
-- Casco (Reich/USSR): 40% desvío (una vez por vida) + bodygroup "helmet" + casco físico que sale disparado
-- Diferencia visual por facción:
--   - USSR: casco normal
--   - Reich: casco gris oscuro (85,85,85,255)
-- Sonidos:
--   - Si el casco te salva: SOLO metal
--   - Si NO te salva y mueres: body break, pero SOLO en PlayerDeath (muerte real)

if SERVER then
    local METAL_HIT_SND  = "physics/metal/metal_solid_impact_bullet2.wav"
    local BODY_BREAK_SND = "physics/body/body_medium_break2.wav"
    local HELMET_CHANCE  = 0.99
    local HELMET_MODEL   = "models/half-dead/red orchestra 2/sov/w_helmet.mdl"
    local NW_HELMET_USED = "WW2_HelmetConsumed"

    local COLOR_REICH = Color(85,85,85,255)

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

        -- Reset bodygroup "helmet"
        local idx = ply:FindBodygroupByName("helmet")
        if idx and idx >= 0 then ply:SetBodygroup(idx, 0) end
    end)

    -- ¿Facciones con casco? y etiqueta
    local function GetHelmetFactionTag(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return nil end
        local fac
        if isfunction(ply.WW2_GetFaction) then fac = ply:WW2_GetFaction() end
        if fac == nil or fac == "" then fac = ply:GetNWString("WW2_Faction", "") end

        if isnumber(fac) then
            if (FACTION_REICH and fac == FACTION_REICH) then return "reich" end
            if (FACTION_USSR  and fac == FACTION_USSR)  then return "ussr" end
            return nil
        end

        local s = tostring(fac):Trim():lower()
        local reich = { "reich","tercer reich","tercer_reich","axis reich","axis_reich" }
        for _,k in ipairs(reich) do if s==k then return "reich" end end
        local ussr  = { "ussr","unión soviética","union sovietica","soviet","soviet union","sovietica" }
        for _,k in ipairs(ussr)  do if s==k then return "ussr" end end
        return nil
    end

    local function HasHelmetFaction(ply)
        return GetHelmetFactionTag(ply) ~= nil
    end

    local function TryApplyHelmetBodygroup(ply)
        local idx = ply:FindBodygroupByName("helmet")
        if idx and idx >= 0 then ply:SetBodygroup(idx, 1) end
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

    -- Spawnea y lanza un casco físico desde la cabeza, con color opcional
    local function SpawnFlyingHelmet(ply, launchDir, optColor)
        util.PrecacheModel(HELMET_MODEL)

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

            ent:SetModel(HELMET_MODEL)
            ent:SetPos(headPos + dir * 2 + Vector(0,0,4))
            ent:SetAngles(headAng or AngleRand())
            ent:Spawn()
            ent:Activate()
            if optColor then
                ent:SetRenderMode(RENDERMODE_NORMAL)
                ent:SetColor(optColor)
            end

            -- Seguridad de colisiones
            ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS) -- no choca con players, casi nada
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
                DPrint("Spawn OK prop_physics casco")
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

            dyn:SetModel(HELMET_MODEL)
            dyn:SetPos(headPos + dir * 2 + Vector(0,0,4))
            dyn:SetAngles(headAng or AngleRand())
            dyn:Spawn()
            if optColor then
                dyn:SetRenderMode(RENDERMODE_NORMAL)
                dyn:SetColor(optColor)
            end
            dyn:SetMoveType(MOVETYPE_FLYGRAVITY)
            dyn:SetSolid(SOLID_NONE)
            dyn:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
            dyn:SetOwner(ply)

            local speed = 350 + math.random(0,150)
            dyn:SetVelocity(dir * speed)
            dyn:SetLocalAngularVelocity(Angle(math.random(-200,200), math.random(-200,200), math.random(-200,200)))

            timer.Simple(8, function() if IsValid(dyn) then dyn:Remove() end end)
            DPrint("Spawn OK prop_dynamic casco (fallback)")
        end)
    end

    -- Decide: desviado (metal + casco sale) o letal (sonará al morir)
    hook.Add("ScalePlayerDamage", "WW2_HeadshotInstantKill", function(ply, hitgroup, dmginfo)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if not ply:Alive() then return end
        if hitgroup ~= HITGROUP_HEAD then return end

        if HasHelmetFaction(ply) and not ply:GetNWBool(NW_HELMET_USED, false) and math.random() < HELMET_CHANCE then
            ply:SetNWBool(NW_HELMET_USED, true)
            ArmInvulnFrame(ply, 0.12)

            -- Anular daño
            dmginfo:SetDamage(0)
            dmginfo:ScaleDamage(0)
            if dmginfo.SetDamageForce then dmginfo:SetDamageForce(Vector(0,0,0)) end

            -- Feedback + bodygroup + casco físico (con color por facción)
            ply:EmitSound(METAL_HIT_SND, 75, 100, 1, CHAN_AUTO)
            TryApplyHelmetBodygroup(ply)

            local dir = CalcImpactDir(ply, dmginfo)
            local tag = GetHelmetFactionTag(ply)
            local col = (tag == "reich") and COLOR_REICH or nil -- USSR = nil (color default)
            SpawnFlyingHelmet(ply, dir, col)

            ply.__WW2_PlayBodyBreakOnDeath = nil
            return
        end

        -- Letal
        dmginfo:SetDamage(ply:Health() + 1000)
        ply.__WW2_PlayBodyBreakOnDeath = true
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

    -- Sonido de “romper cuerpo” solo si realmente murió
    hook.Add("PlayerDeath", "WW2_BodyBreakOnHeadshotDeath", function(victim, inflictor, attacker)
        if not IsValid(victim) then return end
        if victim.__WW2_PlayBodyBreakOnDeath then
            victim:EmitSound(BODY_BREAK_SND, 75, 100, 1, CHAN_AUTO)
        end
        victim.__WW2_PlayBodyBreakOnDeath = nil
    end)
end
