-- ww2_victory_sv.lua
-- Sistema de victoria cuando una facción controla TODOS los puntos de captura

if SERVER then
    util.AddNetworkString("WW2_Victory")
    util.AddNetworkString("WW2_VictoryClear")
    
    local VICTORY_ACTIVE = false
    local WINNING_FACTION = ""
    
    -- Función para verificar victoria
    local function CheckVictoryCondition()
        -- Si ya hay victoria activa, no verificar
        if VICTORY_ACTIVE then return end
        
        -- Obtener todos los puntos de captura
        local points = {}
        for _, cp in ipairs(ents.FindByClass("ww2_cap_point")) do
            if IsValid(cp) then
                table.insert(points, cp)
            end
        end
        
        -- Si no hay puntos, no hay victoria
        if #points == 0 then return end
        
        -- Contar propietarios
        local owners = {}
        for _, cp in ipairs(points) do
            local owner = cp:GetNWString("cap_owner", "")
            if owner ~= "" then
                owners[owner] = (owners[owner] or 0) + 1
            end
        end
        
        -- Verificar si una facción controla TODOS los puntos
        local totalPoints = #points
        
        if owners["reich"] and owners["reich"] == totalPoints then
            -- ¡TERCER REICH GANA!
            TriggerVictory("reich")
        elseif owners["ussr"] and owners["ussr"] == totalPoints then
            -- ¡USSR GANA!
            TriggerVictory("ussr")
        end
    end
    
    -- Activar victoria
    function TriggerVictory(faction)
        VICTORY_ACTIVE = true
        WINNING_FACTION = faction
        
        print("[WW2] ¡VICTORIA PARA:", string.upper(faction), "!")
        
        -- Quitar armas a todos los jugadores
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                ply:StripWeapons()
            end
        end
        
        -- Enviar mensaje de victoria a todos los clientes
        net.Start("WW2_Victory")
            net.WriteString(faction)
        net.Broadcast()
    end
    
    -- Limpiar victoria (por comando de admin o cambio de mapa)
    function ClearVictory()
        if not VICTORY_ACTIVE then return end
        
        VICTORY_ACTIVE = false
        WINNING_FACTION = ""
        
        print("[WW2] Victoria limpiada")
        
        -- Enviar señal de limpieza a clientes
        net.Start("WW2_VictoryClear")
        net.Broadcast()
    end
    
    -- Timer que verifica victoria cada 2 segundos
    timer.Create("WW2_VictoryCheck", 2, 0, function()
        CheckVictoryCondition()
    end)
    
    -- Comando de admin para limpiar victoria
    concommand.Add("ww2_victory_clear", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[WW2] Solo admins pueden usar este comando.")
            return
        end
        
        ClearVictory()
        
        if IsValid(ply) then
            ply:ChatPrint("[WW2] Victoria limpiada.")
        else
            print("[WW2] Victoria limpiada (consola).")
        end
    end)
    
    -- Limpiar victoria al cambiar de mapa
    hook.Add("ShutDown", "WW2_VictoryCleanup", function()
        ClearVictory()
    end)
    
    -- Prevenir que los jugadores recojan armas durante victoria
    hook.Add("PlayerCanPickupWeapon", "WW2_VictoryNoWeapons", function(ply, wep)
        if VICTORY_ACTIVE then
            return false
        end
    end)
    
    -- Prevenir spawn de armas durante victoria
    hook.Add("PlayerSpawn", "WW2_VictoryNoSpawnWeapons", function(ply)
        if VICTORY_ACTIVE then
            timer.Simple(0.1, function()
                if IsValid(ply) then
                    ply:StripWeapons()
                end
            end)
        end
    end)
    
    -- Comando de testing para forzar victoria (solo admin)
    concommand.Add("ww2_force_victory", function(ply, cmd, args)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[WW2] Solo admins pueden usar este comando.")
            return
        end
        
        local faction = args[1]
        if faction ~= "reich" and faction ~= "ussr" then
            if IsValid(ply) then
                ply:ChatPrint("[WW2] Uso: ww2_force_victory <reich/ussr>")
            else
                print("[WW2] Uso: ww2_force_victory <reich/ussr>")
            end
            return
        end
        
        TriggerVictory(faction)
        
        if IsValid(ply) then
            ply:ChatPrint("[WW2] Victoria forzada para: " .. faction)
        else
            print("[WW2] Victoria forzada para: " .. faction)
        end
    end)

        -- Auto limpiar la victoria en 10s
        timer.Simple(10, function()
            if VICTORY_ACTIVE then
                ClearVictory()
            end
        end)

end
-- Bloquear recogida de armas mientras hay victoria activa
hook.Add("PlayerCanPickupWeapon", "WW2_Victory_BlockPickup", function(ply, wep)
    if VICTORY_ACTIVE then return false end
end)
