-- ww2_deploy_spawns_sv.lua (CON spawn en vehículos LVS)
-- Requiere: LVS instalado y clases de spawn en el mapa: ww2_spawn_reich / ww2_spawn_ussr
if SERVER then
    util.AddNetworkString("WW2_DeployTo")
    util.AddNetworkString("WW2_DeployAck")

-- === LVS aliveness (server) ===
local function IsLVSVehicleAlive(veh)
    if not IsValid(veh) then return false end
    if veh.GetIsDestroyed and veh:GetIsDestroyed() then return false end
    if veh.GetDisabled     and veh:GetDisabled()     then return false end
    local hp, maxhp
    if veh.GetHP then
        local okH, v = pcall(function() return veh:GetHP() end)
        if okH then hp = tonumber(v) end
    end
    if veh.GetMaxHP then
        local okM, v = pcall(function() return veh:GetMaxHP() end)
        if okM then maxhp = tonumber(v) end
    end
    if hp ~= nil and maxhp ~= nil and maxhp > 0 and hp <= 0 then return false end
    if veh.GetNW2Bool and (veh:GetNW2Bool("LVS_Destroyed", false) or veh:GetNW2Bool("lvs_destroyed", false) or veh:GetNW2Bool("LVS_Disabled", false)) then return false end
    if veh.GetNWBool  and (veh.GetNWBool("LVS_Destroyed", false)  or veh:GetNWBool("lvs_destroyed", false)  or veh:GetNWBool("LVS_Disabled", false)) then return false end
    local hp2 = veh.GetNW2Int and veh:GetNW2Int("LVS_HP", -1) or -1
    if hp2 == 0 then return false end
    local hp1 = veh.GetNWInt and veh:GetNWInt("LVS_HP", -1) or -1
    if hp1 == 0 then return false end
    return true
end

end

-- [[ TANQUISTA: helpers ]] - ✅ FIX: Mover FUERA del bloque if SERVER
local function IsTanquistaClassId(cls)
    return cls == "reich_tanquista" or cls == "ussr_tanquista"
end

local function IsTanquistaPly(ply)
    local cls = ply:GetNWString("ww2_class","")
    return IsTanquistaClassId(cls)
end

local function SpawnLVSClassAtPos(ply, className, pos, ang)
    if not isstring(className) or className == "" then return end
    local veh = ents.Create(className)
    if not IsValid(veh) then return end
    veh:SetPos((pos or ply:GetPos()) + Vector(0,0,40))
    veh:SetAngles(ang or Angle(0,0,0))
    veh:Spawn()
    veh:Activate()
    timer.Simple(0.05, function()
        if not (IsValid(ply) and IsValid(veh)) then return end
        if veh.ForceEnterDriverSeat then
            veh:ForceEnterDriverSeat(ply)
        else
            if ForceEnterDriverSeat then
                ForceEnterDriverSeat(ply, veh)
            end
        end
    end)
    return veh
end
-- [[ /TANQUISTA: helpers ]]

-- ✅ NUEVA FUNCIÓN: Verificar si vehículo está destruido (SERVIDOR)
local function IsVehicleDestroyed(veh)
    if not IsValid(veh) then return true end
    
    -- ✅ Método 1: NetworkVar de LVS "LVS_IsDestroyed"
    local destroyed = veh:GetNWBool("LVS_IsDestroyed", false)
    if destroyed then 
        print("[WW2 Debug] Vehículo destruido (NWBool LVS_IsDestroyed)")
        return true 
    end
    
    -- ✅ Método 2: HP mediante NetworkVar
    local hp = veh:GetNWInt("LVS_HP", -1)
    if hp == 0 then 
        print("[WW2 Debug] Vehículo destruido (NWInt LVS_HP = 0)")
        return true 
    end
    
    -- ✅ Método 3: GetHP() método directo
    if veh.GetHP then
        local directHP = veh:GetHP()
        if directHP <= 0 then
            print("[WW2 Debug] Vehículo destruido (GetHP = " .. directHP .. ")")
            return true
        end
    end
    
    -- ✅ Método 4: En llamas
    if veh:IsOnFire() then 
        print("[WW2 Debug] Vehículo destruido (en llamas)")
        return true 
    end
    
    -- ✅ Método 5: GetDestroyed() si existe
    if veh.GetDestroyed and veh:GetDestroyed() then
        print("[WW2 Debug] Vehículo destruido (GetDestroyed)")
        return true
    end
    
    -- ✅ Método 6: Verificar color (vehículos destruidos se ponen oscuros)
    local col = veh:GetColor()
    if col.r < 50 and col.g < 50 and col.b < 50 then
        print("[WW2 Debug] Vehículo destruido (color oscuro)")
        return true
    end
    
    return false
end

-- === Utils de facción ===
local function GetPlayerFaction(ply)
    local side = (ply.GetNWString and ply:GetNWString("ww2_faction","")) or ""
    if side == "reich" or side == "ussr" then return side end
    if _G.WW2 and _G.WW2.FACCION then
        if side == _G.WW2.FACCION.REICH then return "reich" end
        if side == _G.WW2.FACCION.USSR then return "ussr" end
    end
    return side
end

local function GetBases()
    return ents.FindByClass("ww2_base_reich"), ents.FindByClass("ww2_base_ussr")
end

local function FindBaseForFaction(side)
    local reich, ussr = GetBases()
    if side == "reich" then return reich[1] end
    if side == "ussr" then return ussr[1] end
end

local function GetFactionSpawnClass(side)
    if side == "reich" then return "ww2_spawn_reich" end
    if side == "ussr" then return "ww2_spawn_ussr" end
    return nil
end

local function FindNearestFactionSpawn(side, originPos)
    local cls = GetFactionSpawnClass(side)
    if not cls then return NULL end
    local spawns = ents.FindByClass(cls)
    local best, bestDist = NULL, math.huge
    for _, e in ipairs(spawns) do
        if IsValid(e) then
            local d = e:GetPos():DistToSqr(originPos)
            if d < bestDist then
                best, bestDist = e, d
            end
        end
    end
    return best
end

-- === Puntos de captura ===
local function FindCapturePointByLabel(lbl)
    if not lbl or lbl == "" then return NULL end
    for _, cp in ipairs(ents.FindByClass("ww2_cap_point")) do
        if IsValid(cp) and cp:GetNWString("cap_label","") == lbl then
            return cp
        end
    end
    for _, cp in ipairs(ents.FindByClass("ww2_capture_point")) do
        if IsValid(cp) and cp:GetNWString("cap_label","") == lbl then
            return cp
        end
    end
    return NULL
end

local function CanDeployToPointServer(ply, lbl)
    local cp = FindCapturePointByLabel(lbl)
    if not IsValid(cp) then return false end
    local owner     = cp:GetNWString("cap_owner","")
    local contested = cp:GetNWBool("cap_contested", false)
    local side      = GetPlayerFaction(ply)
    if side == "" then return false end
    if owner == side then return true end
    if contested and owner ~= "" and owner == side then return true end
    return false
end

-- === Geometría / terreno ===
local function GroundPosFrom(pos)
    local tr = util.TraceHull({
        start = pos + Vector(0,0,64),
        endpos = pos - Vector(0,0,1024),
        mins = Vector(-16,-16,0),
        maxs = Vector(16,16,72),
        mask = MASK_SOLID_BRUSHONLY
    })
    if tr.Hit then
        return tr.HitPos + Vector(0,0,8), tr.HitNormal:Angle()
    end
    return pos, Angle(0,0,0)
end

-- === Resolución del transform de spawn ===
local function ResolveSpawnTransform(ply, destType, label)
    local side = GetPlayerFaction(ply)

    -- =========================
    --  BASES (REICH / USSR)
    -- =========================
    if destType == "base" then
        local baseEnt

        -- 1) Override desde NET (base enemiga capturada que has clicado)
        if ply.WW2_BaseOverride then
            local ent = Entity(ply.WW2_BaseOverride)
            if IsValid(ent) and ent.GetClass and string.find(string.lower(ent:GetClass() or ""), "ww2_base_", 1, true) then
                baseEnt = ent
            end
            -- consumir override para que no se quede pegado
            ply.WW2_BaseOverride = nil
        end

        -- 2) Si el label trae EntIndex de base válida (click directo/tanquista), usarla
        if (not IsValid(baseEnt)) and label and label ~= "" then
            local idx = tonumber(label)
            if idx then
                local ent = Entity(idx)
                if IsValid(ent) and ent.GetClass and string.find(string.lower(ent:GetClass() or ""), "ww2_base_", 1, true) then
                    baseEnt = ent
                end
            end
        end

        -- 3) Fallback: base principal de la facción
        if not IsValid(baseEnt) then
            baseEnt = FindBaseForFaction(side)
        end

        if IsValid(baseEnt) then
            -- ENLACE BASE → ENTIDAD DE DESPLIEGUE (ww2_spawn_reich / ww2_spawn_ussr)
            local origin = baseEnt:GetPos()
            local spawn  = FindNearestFactionSpawn(side, origin)

            if IsValid(spawn) then
                local spos = spawn:GetPos()
                local sang = Angle(0, spawn:EyeAngles().y, 0)
                local gpos, gang = GroundPosFrom(spos)
                return gpos, sang
            else
                -- Si no hay entidades ww2_spawn_* en el mapa, fallback = base
                local pos = baseEnt:GetPos() + Vector(0,0,8)
                local ang = baseEnt:GetAngles()
                local gpos, gang = GroundPosFrom(pos)
                return gpos, ang
            end
        end

    -- =========================
    --  PUNTOS DE CAPTURA
    -- =========================
    elseif destType == "point" then
        if not CanDeployToPointServer(ply, label) then return nil end
        local cp = FindCapturePointByLabel(label)
        if IsValid(cp) then
            local spawn = FindNearestFactionSpawn(side, cp:GetPos())
            if IsValid(spawn) then
                local spos = spawn:GetPos()
                local sang = Angle(0, spawn:EyeAngles().y, 0)
                local gpos, gang = GroundPosFrom(spos)
                return gpos, sang
            else
                -- fallback (si no hay spawns de facción en el mapa)
                local pos = cp:GetPos()
                local ang = cp:GetAngles()
                local gpos, gang = GroundPosFrom(pos)
                return gpos, ang
            end
        end

    -- =========================
    --  VEHÍCULOS LVS
    -- =========================
    elseif destType == "vehicle" then
        local vehIdx = tonumber(label)
        if not vehIdx then return nil end

        local veh = Entity(vehIdx)
        if not IsValid(veh) then return nil end

        -- Usar función centralizada para verificar destrucción
        if IsVehicleDestroyed(veh) then
            print("[WW2] Spawn rechazado: vehículo destruido")
            return nil
        end

        local vehClass = veh:GetClass()
        local allowedVehicles = {
            reich = {
                ["lvs_wheeldrive_fiat_621"] = true
            },
            ussr = {
                ["lvs_wheeldrive_gaz_aaa"] = true
            }
        }

        if not allowedVehicles[side] or not allowedVehicles[side][vehClass] then
            print("[WW2] Vehículo rechazado:", vehClass, "para facción:", side)
            return nil
        end

        return veh:GetPos(), veh:GetAngles(), veh
    end

    return nil
end
-- === Vehículos LVS ===
local VEH_BY_FACTION = {
    ussr = {
        auto   = "lvs_wheeldrive_gaz67",
        camion = "lvs_wheeldrive_gaz_aaa",
    },
    reich = {
        auto   = "lvs_wheeldrive_dodkuebelwagen",
        camion = "lvs_wheeldrive_fiat_621",
    }
}

local function ForceEnterDriverSeat(ply, veh)
    if not IsValid(veh) or not IsValid(ply) then return end
    local seat = veh.GetDriverSeat and veh:GetDriverSeat() or nil
    if IsValid(seat) then
        ply:EnterVehicle(seat)
        return
    end
    local best, bestDist = nil, math.huge
    for _, ent in ipairs(ents.FindInSphere(veh:GetPos(), 256)) do
        if IsValid(ent) and ent:GetClass() == "prop_vehicle_prisoner_pod" then
            local d = ent:GetPos():DistToSqr(veh:GetPos())
            if d < bestDist then
                best, bestDist = ent, d
            end
        end
    end
    if IsValid(best) then
        ply:EnterVehicle(best)
    end
end

-- ✅ NUEVA FUNCIÓN: Meter jugador en asiento de pasajero (2-6)
local function ForceEnterPassengerSeat(ply, veh)
    if not IsValid(veh) or not IsValid(ply) then return false end
    
    -- Buscar asientos de pasajero (normalmente índices 1-5, asientos 2-6)
    local seats = {}
    for _, ent in ipairs(ents.FindInSphere(veh:GetPos(), 512)) do
        if IsValid(ent) and ent:GetClass() == "prop_vehicle_prisoner_pod" then
            -- Excluir el asiento del conductor
            local isDriverSeat = false
            if veh.GetDriverSeat then
                if ent == veh:GetDriverSeat() then
                    isDriverSeat = true
                end
            end
            
            if not isDriverSeat then
                table.insert(seats, ent)
            end
        end
    end
    
    -- Buscar el primer asiento libre
    for _, seat in ipairs(seats) do
        if IsValid(seat) and not IsValid(seat:GetDriver()) then
            ply:EnterVehicle(seat)
            return true
        end
    end
    
    -- Si no hay asientos libres
    return false
end

local function SpawnLVSFor(ply, transport, pos, ang)
    local tstr = string.lower(tostring(transport or ""))
    local vclass = nil
    if string.StartWith(tstr, "lvs_") then
        vclass = tstr
    else
        local side = (GetPlayerFaction and GetPlayerFaction(ply)) or (GetFaction and GetFaction(ply)) or (ply.GetNWString and ply:GetNWString("ww2_faction","")) or ""
        local defs = VEH_BY_FACTION[side or ""] or {}
        vclass = defs[transport or ""]
    end

    if not vclass or vclass == "" then return nil end

    local veh = ents.Create(vclass)
    if not IsValid(veh) then return nil end

    local spawnPos = (pos or (IsValid(ply) and ply:GetPos()) or Vector()) + Vector(0,0,40)
    veh:SetPos(spawnPos)
    veh:SetAngles(ang or Angle(0,0,0))
    veh:Spawn()
    veh:Activate()

    timer.Simple(0.05, function()
        if IsValid(ply) and IsValid(veh) then
            if veh.ForceEnterDriverSeat then
                veh:ForceEnterDriverSeat(ply)
            elseif ForceEnterDriverSeat then
                ForceEnterDriverSeat(ply, veh)
            end
        end
    end)

    return veh
end

-- === Despliegue principal ===
local function DoDeploy(ply, destType, label, transport)
    local pos, ang, targetVeh = ResolveSpawnTransform(ply, destType, label)
    if not pos then return end

    -- ✅ NUEVO: Si es spawn en vehículo, verificar asientos ANTES de spawnear
    if destType == "vehicle" and IsValid(targetVeh) then
        -- Verificar si hay asientos libres PRIMERO
        local hasFreeSeat = false
        for _, ent in ipairs(ents.FindInSphere(targetVeh:GetPos(), 512)) do
            if IsValid(ent) and ent:GetClass() == "prop_vehicle_prisoner_pod" then
                local isDriverSeat = false
                if targetVeh.GetDriverSeat and ent == targetVeh:GetDriverSeat() then
                    isDriverSeat = true
                end
                
                if not isDriverSeat and not IsValid(ent:GetDriver()) then
                    hasFreeSeat = true
                    break
                end
            end
        end
        
        -- ✅ FIX: Si no hay asientos libres, NO SPAWNEAR
        if not hasFreeSeat then
            if IsValid(ply) then
                ply:ChatPrint("[WW2] No hay asientos libres en el vehículo.")
            end
            return -- NO hacer nada, el jugador sigue en el menú
        end
    end

    timer.Simple(0.05, function()
        if not IsValid(ply) then return end

        -- Respawn con su clase/armas
        ply:Spawn()

        -- ✅ NUEVO: Si es spawn en vehículo
        if destType == "vehicle" and IsValid(targetVeh) then
            -- Colocar cerca del vehículo
            ply:SetPos(pos + Vector(0, 0, 50))
            ply:SetEyeAngles(Angle(0, ang.y, 0))
            
            -- Meter en asiento de pasajero
            timer.Simple(0.1, function()
                if IsValid(ply) and IsValid(targetVeh) then
                    local success = ForceEnterPassengerSeat(ply, targetVeh)
                    if not success then
                        -- Esto no debería pasar porque ya verificamos antes
                        ply:ChatPrint("[WW2] Error al entrar al vehículo.")
                    end
                end
            end)
            
            net.Start("WW2_DeployAck") net.Send(ply)
            return
        end

        -- Flujo normal (base/punto)
        ply:SetPos(pos)
        ply:SetEyeAngles(Angle(0, ang.y, 0))

        transport = string.lower(tostring(transport or "pie"))
        if string.StartWith(transport, "lvs_") then
            -- dejar transport tal cual (className LVS)
        elseif transport ~= "auto" and transport ~= "camion" then
            transport = "pie"
        end
        
        -- CAMION sólo en base
        if destType ~= "base" and transport == "camion" then
            transport = "auto"
        end

        if transport ~= "pie" then
            local veh = SpawnLVSFor(ply, transport, pos, ang)
            if not IsValid(veh) then
                ply:ChatPrint("[WW2] No se pudo crear el vehículo, desplegado a pie.")
            end
        end

        net.Start("WW2_DeployAck") net.Send(ply)
    end)
end


-- === NET ===
net.Receive("WW2_DeployTo", function(len, ply)
    if not IsValid(ply) then return end

    local destType  = string.lower(net.ReadString() or "")
    local label     = net.ReadString() or ""
    local transport = ""
    pcall(function() transport = net.ReadString() or "" end)

    -- Reset override by default on each request
    ply.WW2_BaseOverride = nil

    -- === BASE: ownership rules + EntIndex en label ===
    if destType == "base" then
        local num = tonumber(label or "")
        local baseEnt = (num and Entity(num)) or nil
        if IsValid(baseEnt) and string.find(string.lower(baseEnt:GetClass() or ""), "ww2_base_", 1, true) then
            local base_side = (baseEnt.GetNW2String and baseEnt:GetNW2String("base_side","")) or (baseEnt.GetNWString and baseEnt:GetNWString("base_side","")) or ""
            local owner     = (baseEnt.GetNW2String and baseEnt:GetNW2String("cap_owner","")) or (baseEnt.GetNWString and baseEnt:GetNWString("cap_owner","")) or ""
            local mySide    = (ply.GetNWString and ply:GetNWString("ww2_faction","")) or ""

            -- Mi base capturada por enemigo -> bloquear
            if base_side == mySide and owner ~= "" and owner ~= base_side then
                return
            end
            -- Base enemiga capturada por mi bando -> permitir solo PIE/AUTO
            if base_side ~= mySide then
                if owner ~= mySide then return end -- aún no capturada
                local t = string.lower(transport or "")
                if t == "camion" or t == "truck" then return end
                -- Señalar base específica para el resolver
                ply.WW2_BaseOverride = baseEnt:EntIndex()
            end
        end
    end

    -- Validaciones básicas
    if destType ~= "base" and destType ~= "point" and destType ~= "vehicle" then return end

    -- Tanquista: restricciones
    if IsTanquistaPly and IsTanquistaPly(ply) then
        if destType == "vehicle" then return end
        if destType == "point"   then return end
    end

    -- Puntos de captura: reglas servidor
    if destType == "point" and (not CanDeployToPointServer or not CanDeployToPointServer(ply, label)) then return end

    -- Vehículos: validar existencia / destrucción
    if destType == "vehicle" then
        local vehIdx = tonumber(label)
        if not vehIdx then return end
        local veh = Entity(vehIdx)
        if not IsValid(veh) then
            if IsValid(ply) then ply:ChatPrint("[WW2] El vehículo ya no existe.") end
            return
        end
        if IsVehicleDestroyed and IsVehicleDestroyed(veh) then
            if IsValid(ply) then ply:ChatPrint("[WW2] El vehículo está destruido.") end
            return
        end
    end

    DoDeploy(ply, destType, label, transport)

    -- Clear override after deploy to avoid sticky spawns
    ply.WW2_BaseOverride = nil
end)

-- ============================================
-- COMANDOS DE TESTING
-- ============================================

-- Comando para destruir el vehículo que estás mirando (testing)
concommand.Add("ww2_destroy_vehicle", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then
        if IsValid(ply) then
            ply:ChatPrint("[WW2] Solo admins pueden usar este comando.")
        end
        return
    end
    
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    
    if not IsValid(ent) then
        ply:ChatPrint("[WW2] No estás mirando ninguna entidad.")
        return
    end
    
    -- Verificar si es un vehículo LVS
    local class = ent:GetClass()
    if not string.StartWith(class, "lvs_") then
        ply:ChatPrint("[WW2] Eso no es un vehículo LVS.")
        return
    end
    
    ply:ChatPrint("[WW2] Destruyendo vehículo: " .. class .. " (EntIndex: " .. ent:EntIndex() .. ")")
    
    -- ✅ Método 1: Setear HP a 0
    if ent.SetHP then
        ent:SetHP(0)
        ply:ChatPrint("  → HP seteado a 0")
    end
    
    -- ✅ Método 2: Setear NetworkVar HP
    ent:SetNWInt("LVS_HP", 0)
    ply:ChatPrint("  → NetworkVar LVS_HP = 0")
    
    -- ✅ Método 3: Setear NetworkVar Destroyed
    ent:SetNWBool("LVS_IsDestroyed", true)
    ply:ChatPrint("  → NetworkVar LVS_IsDestroyed = true")
    
    -- ✅ Método 4: Prender fuego
    ent:Ignite(999)
    ply:ChatPrint("  → Vehículo en llamas")
    
    -- ✅ Método 5: Oscurecer color
    ent:SetColor(Color(30, 30, 30, 255))
    ply:ChatPrint("  → Color oscurecido")
    
    -- ✅ Método 6: CRÍTICO - Setear Health() de Source a 0
    ent:SetHealth(0)
    ply:ChatPrint("  → Health() seteado a 0")
    
    -- ✅ Método 7: Llamar función de destrucción de LVS si existe
    if ent.LVSExplode then
        ent:LVSExplode()
        ply:ChatPrint("  → LVSExplode() llamado")
    end
    
    -- ✅ Forzar sincronización de NetworkVars
    timer.Simple(0.1, function()
        if IsValid(ent) then
            ent:SetNWBool("LVS_IsDestroyed", true)
            ent:SetNWInt("LVS_HP", 0)
        end
    end)
    
    ply:ChatPrint("[WW2] ✅ Vehículo destruido completamente")
    ply:ChatPrint("[WW2] IMPORTANTE: Cierra y abre el menú de despliegue para ver el cambio")
end)

-- Comando para ver estado de vehículo
concommand.Add("ww2_vehicle_info", function(ply, cmd, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    
    if not IsValid(ent) then
        ply:ChatPrint("[WW2] No estás mirando ninguna entidad.")
        return
    end
    
    local class = ent:GetClass()
    if not string.StartWith(class, "lvs_") then
        ply:ChatPrint("[WW2] Eso no es un vehículo LVS.")
        return
    end
    
    ply:ChatPrint("=== INFO VEHÍCULO ===")
    ply:ChatPrint("Clase: " .. class)
    ply:ChatPrint("EntIndex: " .. ent:EntIndex())
    ply:ChatPrint("")
    ply:ChatPrint("--- Métodos de Detección ---")
    
    -- Health() de Source
    local health = ent:Health()
    ply:ChatPrint("Health(): " .. health .. (health <= 0 and " ❌ DESTRUIDO" or " ✅"))
    
    -- HP directo
    if ent.GetHP and ent.GetMaxHP then
        local hp = ent:GetHP()
        local maxHP = ent:GetMaxHP()
        ply:ChatPrint("GetHP(): " .. hp .. " / " .. maxHP .. (hp <= 0 and " ❌ DESTRUIDO" or " ✅"))
    else
        ply:ChatPrint("GetHP(): N/A")
    end
    
    -- NetworkVar HP
    local nwhp = ent:GetNWInt("LVS_HP", -1)
    ply:ChatPrint("NWInt LVS_HP: " .. nwhp .. (nwhp == 0 and " ❌ DESTRUIDO" or nwhp == -1 and " (no usado)" or " ✅"))
    
    -- NetworkVar Destroyed
    local nwdest = ent:GetNWBool("LVS_IsDestroyed", false)
    ply:ChatPrint("NWBool LVS_IsDestroyed: " .. tostring(nwdest) .. (nwdest and " ❌ DESTRUIDO" or " ✅"))
    
    -- En llamas
    local onfire = ent:IsOnFire()
    ply:ChatPrint("IsOnFire(): " .. tostring(onfire) .. (onfire and " ❌ DESTRUIDO" or " ✅"))
    
    -- Color
    local col = ent:GetColor()
    local isDark = (col.r < 50 and col.g < 50 and col.b < 50)
    ply:ChatPrint("Color: R=" .. col.r .. " G=" .. col.g .. " B=" .. col.b .. (isDark and " ❌ DESTRUIDO" or " ✅"))
    
    -- GetDestroyed
    if ent.GetDestroyed then
        local dest = ent:GetDestroyed()
        ply:ChatPrint("GetDestroyed(): " .. tostring(dest) .. (dest and " ❌ DESTRUIDO" or " ✅"))
    else
        ply:ChatPrint("GetDestroyed(): N/A")
    end
    
    ply:ChatPrint("")
    ply:ChatPrint("--- Resultado Final ---")
    local isDestroyed = IsVehicleDestroyed(ent)
    ply:ChatPrint("¿Está destruido?: " .. (isDestroyed and "❌ SÍ" or "✅ NO"))
    
    if isDestroyed then
        ply:ChatPrint("El icono NO debería aparecer en el mapa")
    else
        ply:ChatPrint("El icono SÍ debería aparecer en el mapa")
    end
end)

-- Safety: clear any lingering base override on spawn
hook.Add("PlayerSpawn", "WW2_ClearBaseOverrideOnSpawn", function(ply)
    ply.WW2_BaseOverride = nil
end)
