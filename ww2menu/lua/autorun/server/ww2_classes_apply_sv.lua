if CLIENT then return end

util.AddNetworkString("WW2_ElegirClase")
util.AddNetworkString("WW2_DeployAck")

local MODEL = {
    reich = "models/player/dod_german.mdl",
    ussr  = "models/ro1soviet_rifleman4pm.mdl",
}

local LOADOUT = {
    REICH_TANQUISTA = { "cw_kk_ins2_doi_mp40", "cw_kk_ins2_doi_nade_m24", "cw_kk_ins2_doi_p38", "weapon_lvsrepair", "cw_kk_ins2_doi_mel_shovel_de", "weapon_extinguisher" },
    REICH_ASALTO       = { "cw_kk_ins2_doi_mp40", "cw_kk_ins2_doi_mel_shovel_de", "cw_kk_ins2_doi_luger", "cw_kk_ins2_doi_nade_m24" },
    REICH_FUSILERO     = { "cw_kk_ins2_doi_k98k", "dcw_kk_ins2_doi_luger", "dcw_kk_ins2_doi_mel_k98k" },
    REICH_SOPORTE      = { "cw_kk_ins2_doi_stg44", "cw_kk_ins2_doi_luger", "cw_kk_ins2_doi_mel_shovel_de", "cw_kk_ins2_doi_nade_n39", "cw_kk_ins2_doi_nade_m24" },
    REICH_AMETRALLADOR = { "cw_kk_ins2_doi_mg34", "cw_kk_ins2_doi_p38", "cw_kk_ins2_doi_nade_n39" },
    REICH_MEDICO       = { "cw_kk_ins2_doi_g43", "weapon_medkit", "cw_kk_ins2_doi_p38" },
	
    USSR_TANQUISTA  = { "cw_kk_ins2_doi_east_ppd40_drum", "cw_kk_ins2_doi_east_tt33", "weapon_lvsrepair", "cw_kk_ins2_doi_nade_east_rpg40", "cw_kk_ins2_doi_mel_shovel_us", "weapon_extinguisher" },
    USSR_ASALTO   = { "cw_kk_ins2_doi_east_ppd40_drum", "cw_kk_ins2_doi_east_m1895dbl", "cw_kk_ins2_doi_nade_east_rg42", "cw_kk_ins2_doi_mel_shovel_us" },
    USSR_FUSILERO = { "cw_kk_ins2_doi_east_mel_svt40bayonet", "cw_kk_ins2_doi_nade_east_rpg40", "cw_kk_ins2_doi_east_m1895dbl", "cw_kk_ins2_doi_nade_tnt_soviet" },
    USSR_SOPORTE  = { "cw_kk_ins2_doi_east_pps43", "cw_kk_ins2_doi_nade_east_f1", "cw_kk_ins2_doi_east_nade_rdg1", "cw_kk_ins2_doi_mel_shovel_us" },
    USSR_MEDICO   = { "cw_kk_ins2_doi_east_svt40", "weapon_medkit", "cw_kk_ins2_doi_east_mel_svt40bayonet", "cw_kk_ins2_doi_east_tt33" },
	USSR_AMETRALLADOR   = { "cw_kk_ins2_doi_east_dp27", "cw_kk_ins2_doi_east_nade_rdg1", "cw_kk_ins2_doi_east_tt33", "cw_kk_ins2_doi_mel_shovel_us" },
}

local function strip_weapons(ply)
    for _, wep in ipairs(ply:GetWeapons()) do
        ply:StripWeapon(wep:GetClass())
    end
    ply:StripAmmo()
end

local function give_weapons(ply, t)
    if not t then return end
    for _, w in ipairs(t) do
        if isstring(w) and w ~= "" then
            ply:Give(w)
        end
    end
end

local function apply_class(ply, classId, side)
    if not IsValid(ply) then return end
    side = side or ply:GetNWString("ww2_faction","")
    classId = classId or ply:GetNWString("ww2_class","")
    if side == "" or classId == "" then return end

    if classId == "reich_tanquista" then ply:SetModel("models/tank_crew5.mdl") elseif classId == "ussr_tanquista" then ply:SetModel("models/ro_ost_41-45_soviet_tank_crew3pm.mdl") elseif MODEL[side] then ply:SetModel(MODEL[side]) end
    local weps = LOADOUT[string.upper(classId)]
    if weps then strip_weapons(ply) give_weapons(ply, weps) end
end

net.Receive("WW2_ElegirClase", function(_, ply)
    if not IsValid(ply) then return end
    local classId = net.ReadString() or ""
    if classId == "" then return end
    ply:SetNWString("ww2_class", classId)
    apply_class(ply, classId)
end)

hook.Add("PlayerSpawn", "WW2_ReapplyClassLoadout", function(ply)
    timer.Simple(0, function()
        if IsValid(ply) then apply_class(ply) end
    end)
end)
