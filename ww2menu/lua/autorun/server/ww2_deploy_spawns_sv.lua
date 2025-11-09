-- ww2_deploy_spawns_sv.lua (FIX: POINT -> usa spawns de facción)
-- Requiere: LVS instalado y clases de spawn en el mapa: ww2_spawn_reich / ww2_spawn_ussr
if SERVER then
    util.AddNetworkString("WW2_DeployTo")
    




-- [[ TANQUISTA: helpers ]]
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

util.AddNetworkString("WW2_DeployAck")
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

    if destType == "base" then
        local baseEnt = FindBaseForFaction(side)
        if IsValid(baseEnt) then
            local pos = baseEnt:GetPos()
            local ang = Angle(0, baseEnt:EyeAngles().y, 0)
            local gpos, gang = GroundPosFrom(pos)
            return gpos, ang
        end

    elseif destType == "point" then
        if not CanDeployToPointServer(ply, label) then return nil end
        local cp = FindCapturePointByLabel(label)
        if IsValid(cp) then
            -- FIX: usar el spawn de FACCION MÁS CERCANO AL PUNTO DE CAPTURA
            local spawn = FindNearestFactionSpawn(side, cp:GetPos())
            if IsValid(spawn) then
                local spos = spawn:GetPos()
                local sang = Angle(0, spawn:EyeAngles().y, 0)
                local gpos, gang = GroundPosFrom(spos)
                return gpos, sang
            else
                -- fallback (si no hay spawns de facción en el mapa)
                local pos = cp:GetPos()
                local ang = Angle(0, cp:EyeAngles().y, 0)
                local gpos, gang = GroundPosFrom(pos)
                return gpos, ang
            end
        end
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
    local pos, ang = ResolveSpawnTransform(ply, destType, label)
    if not pos then return end

    timer.Simple(0.05, function()
        if not IsValid(ply) then return end

        -- Respawn con su clase/armas (tu sistema ya procesa WW2_ElegirClase antes)
        ply:Spawn()

        -- Colocar jugador
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
    local destType = string.lower(net.ReadString() or "")
    local label    = net.ReadString() or ""
    local transport = ""
    pcall(function() transport = net.ReadString() or "" end) -- 3er parámetro (opcional)

    if destType ~= "base" and destType ~= "point" then return end
    if (ply.GetNWString and ply:GetNWString("ww2_class","") and (ply:GetNWString("ww2_class","")=="reich_tanquista" or ply:GetNWString("ww2_class","")=="ussr_tanquista")) and destType=="point" then
        return
    end
    if destType == "point" and not CanDeployToPointServer(ply, label) then return end

    DoDeploy(ply, destType, label, transport)
end)
