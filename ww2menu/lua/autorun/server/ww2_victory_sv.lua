
-- ww2_victory_sv.lua (FINAL+RESET) — victoria por TODOS los puntos + bases; autoclear a 10s; reset de mapa
-- - Tras 10s: ejecuta ww2_victory_clear
-- - En ww2_victory_clear: todos los CAP POINTS quedan NEUTRALES; todas las BASES vuelven a su facción original
if SERVER then
    util.AddNetworkString("WW2_Victory")
    util.AddNetworkString("WW2_VictoryClear")

    local VICTORY_ACTIVE = false
    local WINNER = ""

    -- ================= Helpers =================
    local function GetOwner(ent)
        if not IsValid(ent) then return "" end
        if ent.GetNWString then
            local v = ent:GetNWString("cap_owner","")
            if v ~= "" then return v end
        end
        if ent.GetNW2String then
            local v2 = ent:GetNW2String("cap_owner","")
            if v2 ~= "" then return v2 end
        end
        return ""
    end

    local function SetOwner(ent, owner)
        if not IsValid(ent) then return end
        if ent.SetNWString then ent:SetNWString("cap_owner", owner or "") end
        if ent.SetNW2String then ent:SetNW2String("cap_owner", owner or "") end
    end

    local function GetCtrl(ent)
        if not IsValid(ent) then return 0 end
        if ent.GetNWFloat then
            local v = ent:GetNWFloat("cap_control", 0)
            if v ~= 0 then return v end
        end
        if ent.GetNW2Float then
            local v2 = ent:GetNW2Float("cap_control", 0)
            return v2
        end
        return 0
    end

    local function SetCtrl(ent, val)
        if not IsValid(ent) then return end
        if ent.SetNWFloat then ent:SetNWFloat("cap_control", val or 0) end
        if ent.SetNW2Float then ent:SetNW2Float("cap_control", val or 0) end
    end

    local function AllCapPoints()
        local t = {}
        for _, e in ipairs(ents.FindByClass("ww2_cap_point") or {}) do
            if IsValid(e) then t[#t+1] = e end
        end
        return t
    end
    local function AllBases()
        local t = {}
        for _, e in ipairs(ents.FindByClass("ww2_base_reich") or {}) do if IsValid(e) then t[#t+1] = e end end
        for _, e in ipairs(ents.FindByClass("ww2_base_ussr")  or {}) do if IsValid(e) then t[#t+1] = e end end
        return t
    end

    local function ControlsAll(list, fac)
        if #list == 0 then return false end
        for i = 1, #list do
            if GetOwner(list[i]) ~= fac then return false end
        end
        return true
    end

    -- ================ Victoria ================
    local function BroadcastVictory(fac)
        if VICTORY_ACTIVE then return end
        VICTORY_ACTIVE = true
        WINNER = fac

        -- Quitar armas
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then ply:StripWeapons() end
        end

        net.Start("WW2_Victory")
            net.WriteString(fac) -- "reich" | "ussr"
        net.Broadcast()

        -- Autoclear en 10s
        timer.Simple(30, function()
            if VICTORY_ACTIVE then
                RunConsoleCommand("ww2_victory_clear")
            end
        end)
    end

    -- Reset total de puntos/bases tras victoria o al ejecutar el comando
    local function ResetAllPointsAndBases()
        -- Puntos: neutral
        for _, cp in ipairs(AllCapPoints()) do
            -- neutral: owner "", control 0
            SetOwner(cp, "")
            SetCtrl(cp, 0)
        end
        -- Bases: volver a su facción original
        for _, b in ipairs(AllBases()) do
            -- Detectar base_side (NW o campo lua)
            local side = ""
            if b.GetNW2String then side = b:GetNW2String("base_side","") end
            if side == "" and b.GetNWString then side = b:GetNWString("base_side","") end
            if side == "" and b.base_side then side = b.base_side end
            -- Fallback por classname
            if side == "" and b.GetClass then
                local cn = string.lower(b:GetClass() or "")
                if string.find(cn, "reich", 1, true) then side = "reich"
                elseif string.find(cn, "ussr", 1, true) then side = "ussr" end
            end

            -- Owner y control por defecto
            if side == "reich" then
                SetOwner(b, "reich")
                SetCtrl(b,  1.0)
            elseif side == "ussr" then
                SetOwner(b, "ussr")
                SetCtrl(b, -1.0)
            else
                -- si no pudimos determinar, lo dejamos neutral
                SetOwner(b, "")
                SetCtrl(b, 0)
            end

            -- Limpiar flags auxiliares
            if b.SetNW2String then b:SetNW2String("cap_captured_by","") end
            if b.SetNWString  then b:SetNWString("cap_captured_by","")  end
            if b.SetNW2Bool   then b:SetNW2Bool("cap_contested", false) end
            if b.SetNWBool    then b:SetNWBool("cap_contested", false)  end
        end
    end

    local function ClearVictory()
        if not VICTORY_ACTIVE then return end
        VICTORY_ACTIVE = false
        WINNER = ""

        -- Limpiar escena en clientes
        net.Start("WW2_VictoryClear")
        net.Broadcast()

        -- Resetear mapa a estado inicial
        ResetAllPointsAndBases()
    end

    -- Chequeo 1/s
    local function CheckVictory()
        if VICTORY_ACTIVE then return end

        local pts = AllCapPoints()
        local bas = AllBases()
        if #pts == 0 or #bas == 0 then return end -- evita victorias por vacío

        for _, fac in ipairs({"reich","ussr"}) do
            if ControlsAll(pts, fac) and ControlsAll(bas, fac) then
                BroadcastVictory(fac)
                return
            end
        end
    end

    timer.Create("WW2_VictoryCheck", 1, 0, CheckVictory)

    -- Comando expuesto
    concommand.Add("ww2_victory_clear", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then
            ply:ChatPrint("[WW2] Solo admins.")
            return
        end
        ClearVictory()
    end)
end
