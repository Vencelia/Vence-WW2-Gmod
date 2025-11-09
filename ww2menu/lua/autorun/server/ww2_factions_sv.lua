-- WW2 Facciones y Clases (Servidor) – Enforcer de modelo + envío correcto de clientes
if CLIENT then return end

AddCSLuaFile("autorun/shared/ww2_factions_sh.lua")
AddCSLuaFile("autorun/client/ww2_menu_main.lua")
AddCSLuaFile("autorun/client/ww2_menu_classes.lua")
AddCSLuaFile("autorun/client/ww2_menu_deploy.lua")
AddCSLuaFile("autorun/client/ww2_hud_faction.lua")

include("autorun/shared/ww2_factions_sh.lua")

local function ValidFaction(f)
    return f == WW2.FACCION.REICH or f == WW2.FACCION.USSR
end

local validClasses = {
    [WW2.CLASE.REICH_TANQUISTA] = true,
    [WW2.CLASE.USSR_TANQUISTA] = true,
    -- Reich
    [WW2.CLASE.REICH_ASALTO]       = true,
    [WW2.CLASE.REICH_FUSILERO]     = true,
    [WW2.CLASE.REICH_SOPORTE]      = true,
    [WW2.CLASE.REICH_AMETRALLADOR] = true,
    [WW2.CLASE.REICH_MEDICO]       = true,
    [WW2.CLASE.REICH_INGENIERO]    = true,
    -- USSR
    [WW2.CLASE.USSR_ASALTO]        = true,
    [WW2.CLASE.USSR_FUSILERO]      = true,
    [WW2.CLASE.USSR_SOPORTE]       = true,
    [WW2.CLASE.USSR_AMETRALLADOR]  = true,
    [WW2.CLASE.USSR_MEDICO]        = true,
    [WW2.CLASE.USSR_INGENIERO]     = true,
}
local function ValidClass(c) return validClasses[c] == true end

-- ========= Persistencia + NW =========
local function SetPlayerFaction(ply, fac)
    if not IsValid(ply) or not ValidFaction(fac) then return end
    ply:SetPData("ww2_faction", fac)
    ply:SetNWString("ww2_faction", fac)
    -- notificar cliente por si alguien lo usa
    if util.NetworkStringToID("WW2_SyncFaction") ~= 0 then
        net.Start("WW2_SyncFaction") net.WriteString(fac) net.Send(ply)
    end
end

local function SetPlayerClass(ply, cls)
    if not IsValid(ply) then return end
    if cls ~= "" and not ValidClass(cls) then return end
    ply:SetPData("ww2_class", cls or "")
    ply:SetNWString("ww2_class", cls or "")
    if util.NetworkStringToID("WW2_SyncClass") ~= 0 then
        net.Start("WW2_SyncClass") net.WriteString(cls or "") net.Send(ply)
    end
end

hook.Add("PlayerInitialSpawn", "WW2_LoadFactionClassOnJoin", function(ply)
    local fac = ply:GetPData("ww2_faction", "")
    local cls = ply:GetPData("ww2_class", "")
    -- sanity
    if not ValidFaction(fac) then fac = "" end
    if cls ~= "" and not ValidClass(cls) then cls = "" end

    if fac ~= "" then SetPlayerFaction(ply, fac) end
    if cls ~= "" then SetPlayerClass(ply, cls) end
end)

-- ========= Forzado de modelo robusto =========
local FALLBACK_MODEL = "models/player/kleiner.mdl"

local function ResolveDesiredModel(ply)
    local fac = ply:GetNWString("ww2_faction", "")
    local cls = ply:GetNWString("ww2_class", "")

    if cls == WW2.CLASE.REICH_TANQUISTA then return "models/half-dead/red orchestra 2/ger/tanker.mdl" end
    if cls == WW2.CLASE.USSR_TANQUISTA then return "models/half-dead/red orchestra 2/sov/tanker.mdl" end
    if fac == WW2.FACCION.REICH and cls ~= "" then
        return "models/half-dead/red orchestra 2/ger/rawrecruit.mdl"
    elseif fac == WW2.FACCION.USSR and cls ~= "" then
        return "models/half-dead/red orchestra 2/sov/rawrecruit.mdl"
    end
    return nil
end

local function ForceModel(ply, mdl)
    if not IsValid(ply) then return end
    if not mdl or mdl == "" then mdl = FALLBACK_MODEL end

    if not util.IsValidModel(mdl) then
        local desired = mdl
        mdl = FALLBACK_MODEL
        print(("[WW2] Modelo inválido o no montado: %s -> usando fallback %s para %s")
            :format(tostring(desired), FALLBACK_MODEL, ply:Nick()))
    end

    util.PrecacheModel(mdl)
    ply:SetModel(mdl)
    ply:SetNWString("ww2_forced_model", mdl)
end

local Enforcer = {}

local function GiveLoadout(ply, fac, cls)
    ply:StripWeapons()
    if fac == WW2.FACCION.REICH then
        if     cls == WW2.CLASE.REICH_ASALTO       then
                ply:Give("cw_kk_ins2_doi_mp40") ; ply:Give("cw_kk_ins2_doi_mel_shovel_de") ; ply:Give("cw_kk_ins2_doi_luger") ; ply:Give("cw_kk_ins2_doi_nade_m24")

        elseif cls == WW2.CLASE.REICH_FUSILERO     then
                ply:Give("cw_kk_ins2_doi_k98k") ; ply:Give("dcw_kk_ins2_doi_luger") ; ply:Give("dcw_kk_ins2_doi_mel_k98k")

        elseif cls == WW2.CLASE.REICH_SOPORTE      then
                ply:Give("cw_kk_ins2_doi_stg44") ; ply:Give("cw_kk_ins2_doi_luger") ; ply:Give("cw_kk_ins2_doi_mel_shovel_de") ; ply:Give("cw_kk_ins2_doi_nade_n39") ; ply:Give("cw_kk_ins2_doi_nade_m24")

        elseif cls == WW2.CLASE.REICH_AMETRALLADOR then
                ply:Give("cw_kk_ins2_doi_mg34") ; ply:Give("cw_kk_ins2_doi_p38") ; ply:Give("cw_kk_ins2_doi_nade_n39")

        elseif cls == WW2.CLASE.REICH_MEDICO       then
                ply:Give("cw_kk_ins2_doi_g43") ; ply:Give("weapon_medkit") ; ply:Give("cw_kk_ins2_doi_p38")

        elseif cls == WW2.CLASE.REICH_INGENIERO    then
            ply:Give("doi_ws_atow_mp34"); ply:Give("doi_atow_c96"); ply:Give("weapon_xdebarricade"); ply:Give("doi_atow_etoolus"); ply:Give("weapon_lvsrepair"); ply:Give("weapon_lvsmines")
        end
    elseif fac == WW2.FACCION.USSR then
        if     cls == WW2.CLASE.USSR_ASALTO        then
                ply:Give("cw_kk_ins2_doi_east_ppd40_drum") ; ply:Give("cw_kk_ins2_doi_east_m1895dbl") ; ply:Give("cw_kk_ins2_doi_nade_east_rg42") ; ply:Give("cw_kk_ins2_doi_mel_shovel_us")

        elseif cls == WW2.CLASE.USSR_FUSILERO      then
                ply:Give("cw_kk_ins2_doi_east_mel_svt40bayonet") ; ply:Give("cw_kk_ins2_doi_east_nade_rpg40") ; ply:Give("cw_kk_ins2_doi_east_m1895dbl") ; ply:Give("cw_kk_ins2_doi_east_nade_tnt_soviet")

        elseif cls == WW2.CLASE.USSR_SOPORTE       then
                ply:Give("cw_kk_ins2_doi_east_pps43") ; ply:Give("cw_kk_ins2_doi_nade_east_f1") ; ply:Give("cw_kk_ins2_doi_east_nade_rdg1") ; ply:Give("cw_kk_ins2_doi_mel_shovel_us")

        elseif cls == WW2.CLASE.USSR_AMETRALLADOR  then
                ply:Give("cw_kk_ins2_doi_east_dp27") ; ply:Give("cw_kk_ins2_doi_east_nade_rdg1") ; ply:Give("cw_kk_ins2_doi_east_tt33") ; ply:Give("cw_kk_ins2_doi_mel_shovel_us")

        elseif cls == WW2.CLASE.USSR_MEDICO        then
                ply:Give("cw_kk_ins2_doi_east_svt40") ; ply:Give("weapon_medkit") ; ply:Give("cw_kk_ins2_doi_east_mel_svt40bayonet") ; ply:Give("cw_kk_ins2_doi_east_tt33")

        elseif cls == WW2.CLASE.USSR_INGENIERO     then
            ply:Give("doi_atow_ithaca37"); ply:Give("doi_atow_sw29"); ply:Give("weapon_xdebarricade"); ply:Give("doi_atow_etoolus"); ply:Give("weapon_lvsrepair"); ply:Give("weapon_lvsmines")
        elseif cls == WW2.CLASE.USSR_TANQUISTA then
                ply:Give("cw_kk_ins2_doi_east_ppd40_drum") ; ply:Give("cw_kk_ins2_doi_east_tt33") ; ply:Give("weapon_lvsrepair") ; ply:Give("cw_kk_ins2_doi_nade_east_rpg40") ; ply:Give("cw_kk_ins2_doi_mel_shovel_us") ; ply:Give("weapon_extinguisher")

        end
    end
end

hook.Add("PlayerSpawn", "WW2_ApplyFactionClassOnSpawn", function(ply)
    local fac = ply:GetNWString("ww2_faction", "")
    local cls = ply:GetNWString("ww2_class", "")
    if fac == "" or cls == "" then Enforcer[ply] = nil return end

    local mdl = ResolveDesiredModel(ply)
    if mdl then
        ForceModel(ply, mdl)
        Enforcer[ply] = { expire = CurTime() + 2.0, mdl = mdl }
        GiveLoadout(ply, fac, cls)
    else
        Enforcer[ply] = nil
    end
end)

timer.Create("WW2_ModelEnforcer_Tick", 0.10, 0, function()
    for ply, data in pairs(Enforcer) do
        if not IsValid(ply) then
            Enforcer[ply] = nil
        else
            if CurTime() > (data.expire or 0) then
                Enforcer[ply] = nil
            else
                local desired = data.mdl
                if desired and ply:GetModel() ~= desired then
                    ForceModel(ply, desired)
                end
            end
        end
    end
end)

-- ========= Elección de facción/clase =========
util.AddNetworkString("WW2_ElegirBando")
util.AddNetworkString("WW2_ElegirClase")
util.AddNetworkString("WW2_RequestRespawn")
util.AddNetworkString("WW2_SyncFaction")
util.AddNetworkString("WW2_SyncClass")

net.Receive("WW2_ElegirBando", function(_, ply)
    local fac = net.ReadString()
    if not ValidFaction(fac) then return end
    SetPlayerFaction(ply, fac)

    -- resetear clase al cambiar de facción
    if ply:GetPData("ww2_class", "") ~= "" then SetPlayerClass(ply, "") end
end)

net.Receive("WW2_ElegirClase", function(_, ply)
    local cls = net.ReadString()
    if not ValidClass(cls) then return end

    local fac = ply:GetNWString("ww2_faction","")
    -- Coherencia clase ↔ facción
    if string.StartWith(cls, "reich_") and fac ~= WW2.FACCION.REICH then return end
    if string.StartWith(cls, "ussr_")  and fac ~= WW2.FACCION.USSR  then return end

    SetPlayerClass(ply, cls)

    -- Respawn con loadout
    timer.Simple(0.05, function() if IsValid(ply) then ply:Spawn() end end)
end)

net.Receive("WW2_RequestRespawn", function(_, ply)
    if not IsValid(ply) then return end
    timer.Simple(0.05, function() if IsValid(ply) then ply:Spawn() end end)
end)

hook.Add("PlayerDisconnected", "WW2_EnforcerCleanup", function(ply)
    Enforcer[ply] = nil
end)
