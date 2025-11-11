-- lvs_no_wrecks_sv.lua
-- Bloquea y limpia cualquier “wreck/prop” que LVS intente dejar al destruir vehículos.

local function removeSoon(ent)
    if not IsValid(ent) then return end
    timer.Simple(0, function()
        if IsValid(ent) then ent:Remove() end
    end)
end

-- 1) Si LVS expone helpers para generar restos, los anulamos.
hook.Add("InitPostEntity", "LVS_NoWrecks_DisableSpawners", function()
    if not LVS then return end

    local candidates = {
        "SpawnWreck",
        "SpawnDestroyedVehicle",
        "SpawnDebris",
        "SpawnGib",
        "SpawnBurningWreck",
    }

    for _, fname in ipairs(candidates) do
        if isfunction(LVS[fname]) then
            LVS[fname] = function() return end
        end
    end

    -- Si existiera un convar servidor para restos, intenta desactivarlo.
    -- No falla si no existe.
    if ConVarExists("lvs_wrecks") then
        RunConsoleCommand("lvs_wrecks", "0")
    end
end)

-- 2) Cualquier entidad de “wreck/gib/destroyed” que se alcance a crear, la borramos al nacer.
hook.Add("OnEntityCreated", "LVS_NoWrecks_AutoCleanup", function(ent)
    if not IsValid(ent) then return end
    local cls = ent:GetClass()
    if not cls then return end

    -- Heurística: clases típicas de restos en LVS.
    -- (Cubre variantes como lvs_*_wreck, *_destroyed, *_gib, etc.)
    local lower = string.lower(cls)
    if string.find(lower, "lvs", 1, true) and
       (string.find(lower, "wreck", 1, true)
        or string.find(lower, "destroyed", 1, true)
        or string.find(lower, "gib", 1, true)
        or string.find(lower, "debris", 1, true)
        or string.find(lower, "burn", 1, true)) then
        removeSoon(ent)
        return
    end

    -- Algunos restos pueden ser prop_physics con flags NW marcando que son “wreck”.
    timer.Simple(0, function()
        if not IsValid(ent) then return end
        if ent:GetNW2Bool("LVS.IsWreck", false)
        or ent:GetNWBool("LVS.IsWreck", false)
        or ent:GetNW2Bool("lvs_iswreck", false)
        or ent:GetNWBool("lvs_iswreck", false) then
            ent:Remove()
        end
    end)
end)

-- 3) Fallback: si existe un hook de destrucción en LVS, remueve todo lo que intente dejar.
-- (No rompe si el hook no existe.)
hook.Add("LVS.OnVehicleDestroyed", "LVS_NoWrecks_BlockOnDestroyed", function(vehicle, attacker)
    if not IsValid(vehicle) then return end
    -- Si algún sistema crea restos “tarde”, borra las entidades cercanas que marquen el flag.
    timer.Simple(0, function()
        local radius = 256
        for _, ent in ipairs(ents.FindInSphere(vehicle:GetPos(), radius)) do
            if IsValid(ent) then
                local c = string.lower(ent:GetClass() or "")
                if (string.find(c, "lvs", 1, true) and
                    (c:find("wreck", 1, true) or c:find("gib", 1, true) or c:find("destroyed", 1, true) or c:find("debris", 1, true)))
                or ent:GetNW2Bool("LVS.IsWreck", false)
                or ent:GetNWBool("LVS.IsWreck", false) then
                    ent:Remove()
                end
            end
        end
    end)
end)
