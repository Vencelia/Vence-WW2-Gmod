
-- ww2_base_capture_sv.lua (v2) — mismas reglas que ww2_cap_point init.lua
-- Captura de BASES principales con control continuo -1..1, dt, ventaja r-u y dueño que cambia al cruzar el centro.
if SERVER then
    util.AddNetworkString("WW2_BaseCap_Hint")

    local CAP_RADIUS_CVAR = CreateConVar("ww2_base_cap_radius", "1000", FCVAR_ARCHIVE, "Radio de captura de BASE", 256, 4096)
    local CAP_SPEED_CVAR  = CreateConVar("ww2_base_cap_speed",  "0.05",  FCVAR_ARCHIVE, "Velocidad de captura por jugador (BASE)", 0.005, 0.25)
    local TICK = 0.1

    local function BaseClasses()
        return { "ww2_base_reich", "ww2_base_ussr" }
    end

    local function EnsureBaseState(ent)
        ent._base_side = ent._base_side or (ent.base_side or (ent.GetNWString and ent:GetNWString("base_side","") or ""))
        if ent._base_side == "" then
            local cn = string.lower(ent:GetClass() or "")
            if cn:find("reich", 1, true) then ent._base_side = "reich" end
            if cn:find("ussr",  1, true) then ent._base_side = "ussr"  end
        end
        -- -1 (USSR) .. 0 .. +1 (REICH) — igual que tu punto A/B/C
        if ent._cap_control == nil then
            ent._cap_control = (ent._base_side == "reich") and 1.0 or -1.0
        end
        ent._cap_owner   = ent._cap_owner or ent._base_side
        ent._cap_contested = ent._cap_contested or false
        ent._lastThink = ent._lastThink or CurTime()

        ent:SetNW2String("base_side", ent._base_side)
        ent:SetNW2Float("cap_control", ent._cap_control)
        ent:SetNW2String("cap_owner",   ent._cap_owner)
        ent:SetNW2Bool("cap_contested", ent._cap_contested)
        ent:SetNW2String("cap_captured_by", ent._cap_captured_by or "")
        ent:SetNW2Int("cap_radius", CAP_RADIUS_CVAR:GetInt())
    end

    local function CountFactionsInSphere(pos, radius)
        local reich, ussr = 0, 0
        for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
            if IsValid(ent) and ent:IsPlayer() and ent:Alive() then
                local fac = ent:GetNWString("ww2_faction","")
                if fac == "reich" then
                    reich = reich + 1
                elseif fac == "ussr" then
                    ussr = ussr + 1
                end
            end
        end
        return reich, ussr
    end

    local function ThinkBase(ent)
        EnsureBaseState(ent)
        local now = CurTime()
        local dt  = now - (ent._lastThink or now)
        ent._lastThink = now

        local radius = CAP_RADIUS_CVAR:GetFloat()
        local speed  = CAP_SPEED_CVAR:GetFloat()
        local r, u = CountFactionsInSphere(ent:GetPos(), radius)
        local advantage = r - u

        -- Contested EXACTO como el cap point: mismos jugadores de ambos lados (igual número)
        local contested = (r > 0 and u > 0 and r == u)
        ent._cap_contested = contested
        ent:SetNW2Bool("cap_contested", contested)

        -- Progreso
        local ctrl = ent._cap_control or 0
        if advantage ~= 0 then
            ctrl = ctrl + (speed * advantage * dt)
            if ctrl > 1.0 then ctrl = 1.0 end
            if ctrl < -1.0 then ctrl = -1.0 end
        end
        ent._cap_control = ctrl

        -- Dueño con mismas reglas que el cap point
        local owner = ent._cap_owner or ""
        if ctrl >= 0.999 then
            owner = "reich"
        elseif ctrl <= -0.999 then
            owner = "ussr"
        else
            if owner == "reich" then
                if ctrl < 0 then owner = "" end
            elseif owner == "ussr" then
                if ctrl > 0 then owner = "" end
            else
                if ctrl >= 0.8 then
                    owner = "reich"
                elseif ctrl <= -0.8 then
                    owner = "ussr"
                end
            end
        end

        -- Capturada por lado contrario: mantenemos nombre original + leyenda
        if owner ~= ent._cap_owner then
            ent._cap_owner = owner
            ent:SetNW2String("cap_owner", owner)
            if owner ~= "" and owner ~= ent._base_side then
                ent._cap_captured_by = owner
                ent:SetNW2String("cap_captured_by", owner)
            elseif owner == ent._base_side then
                ent._cap_captured_by = ""
                ent:SetNW2String("cap_captured_by", "")
            end
        end

        ent:SetNW2Float("cap_control", ctrl)
        ent:SetNW2Int("cap_radius", math.floor(radius))
    end

    timer.Create("WW2_BaseCap_Think", TICK, 0, function()
        for _, cls in ipairs(BaseClasses()) do
            for _, ent in ipairs(ents.FindByClass(cls) or {}) do
                if IsValid(ent) then ThinkBase(ent) end
            end
        end
    end)
end
