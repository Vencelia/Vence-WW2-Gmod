-- ww2_lvs_autocleanup.lua
-- Elimina vehículos LVS destruidos tras un retraso configurable (por defecto 60s)

if not SERVER then return end

local CV_ENABLE = CreateConVar("ww2_lvs_cleanup_enable", "1", FCVAR_ARCHIVE,
    "Habilita limpieza automática de vehículos LVS destruidos (1=ON, 0=OFF)")

local CV_DELAY  = CreateConVar("ww2_lvs_cleanup_delay",  "60", FCVAR_ARCHIVE,
    "Segundos antes de remover un LVS destruido (mín. 5s)")

local CV_DEBUG  = CreateConVar("ww2_lvs_cleanup_debug",  "0", FCVAR_ARCHIVE,
    "Mensajes de depuración en consola (0=OFF,1=ON)")

local function dbg(...)
    if CV_DEBUG:GetBool() then
        print("[LVS-Autocleanup]", ...)
    end
end

-- Detección de si una entidad es vehículo LVS
local function IsLVSVehicle(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass()
    if cls and cls:StartWith("lvs_") then return true end
    if ent.LVS == true then return true end
    return false
end

-- Detección robusta de destrucción (LVS)
local function IsLVSDestroyed(ent)
    if not IsValid(ent) then return true end

    if ent.GetIsDestroyed and ent:GetIsDestroyed() then return true end
    if ent.GetDisabled     and ent:GetDisabled()     then return true end

    local hp, maxhp
    if ent.GetHP then
        local okH, v = pcall(function() return ent:GetHP() end)
        if okH then hp = tonumber(v) end
    end
    if ent.GetMaxHP then
        local okM, v = pcall(function() return ent:GetMaxHP() end)
        if okM then maxhp = tonumber(v) end
    end
    if hp ~= nil and maxhp ~= nil and maxhp > 0 and hp <= 0 then
        return true
    end

    -- Flags de red comúnmente usadas por LVS
    if ent.GetNW2Bool and (ent:GetNW2Bool("LVS_Destroyed", false)
        or ent:GetNW2Bool("lvs_destroyed", false)
        or ent:GetNW2Bool("LVS_Disabled",  false)) then
        return true
    end

    if ent.GetNWBool and (ent:GetNWBool("LVS_Destroyed", false)
        or ent:GetNWBool("lvs_destroyed", false)
        or ent:GetNWBool("LVS_Disabled",  false)) then
        return true
    end

    local hp2 = ent.GetNW2Int and ent:GetNW2Int("LVS_HP", -1) or -1
    if hp2 == 0 then return true end

    local hp1 = ent.GetNWInt and ent:GetNWInt("LVS_HP", -1) or -1
    if hp1 == 0 then return true end

    return false
end

-- Expulsa cualquier pasajero residual antes de remover
local function EjectPassengers(ent)
    if not IsValid(ent) then return end
    if ent.GetPassenger then
        for i = 1, 16 do
            local seat = ent:GetPassenger(i)
            if IsValid(seat) then
                local drv = seat.GetDriver and seat:GetDriver() or nil
                if IsValid(drv) then
                    drv:ExitVehicle()
                end
            end
        end
    end
end

-- Conjuntos de seguimiento
local WATCH    = {}  -- entidades LVS vigiliadas
local SCHEDULE = {}  -- ent -> tiempo de eliminación (CurTime()+delay)

local function Track(ent)
    if not IsLVSVehicle(ent) then return end
    WATCH[ent] = true
    SCHEDULE[ent] = nil
    dbg("watch", ent, ent:GetClass())
end

-- Vigilar entidades nuevas
hook.Add("OnEntityCreated", "WW2_LVS_AutoCleanup_Watch", function(ent)
    -- Se difiere un tick para asegurar que GetClass/Getters existan
    timer.Simple(0, function()
        if IsValid(ent) then Track(ent) end
    end)
end)

-- Sembrar las existentes al cargar el mapa
hook.Add("InitPostEntity", "WW2_LVS_AutoCleanup_Seed", function()
    for _, ent in ipairs(ents.GetAll()) do
        Track(ent)
    end
end)

-- Limpieza de tablas al remover entidad
hook.Add("EntityRemoved", "WW2_LVS_AutoCleanup_Unwatch", function(ent)
    WATCH[ent]    = nil
    SCHEDULE[ent] = nil
end)

-- Bucle con baja frecuencia (0.5s) para programar/remover
timer.Create("WW2_LVS_AutoCleanup_Tick", 0.5, 0, function()
    if not CV_ENABLE:GetBool() then return end

    local delay = math.max(5, CV_DELAY:GetFloat() or 60)
    local now   = CurTime()

    -- Evaluar estado de destrucción y programar/cancelar
    for ent, _ in pairs(WATCH) do
        if not IsValid(ent) then
            WATCH[ent]    = nil
            SCHEDULE[ent] = nil
        else
            local dead = IsLVSDestroyed(ent)
            local exp  = SCHEDULE[ent]
            if dead and not exp then
                SCHEDULE[ent] = now + delay
                dbg("destroyed -> cleanup in", delay, "sec", ent)
            elseif (not dead) and exp then
                -- “Reparado”/revivido: cancelar
                SCHEDULE[ent] = nil
                dbg("revived, cancel cleanup", ent)
            end
        end
    end

    -- Ejecutar eliminaciones vencidas
    for ent, t_exp in pairs(SCHEDULE) do
        if not IsValid(ent) then
            SCHEDULE[ent] = nil
            WATCH[ent]    = nil
        elseif now >= t_exp then
            dbg("removing destroyed vehicle", ent)
            EjectPassengers(ent)
            SafeRemoveEntity(ent)
            SCHEDULE[ent] = nil
            WATCH[ent]    = nil
        end
    end
end)
