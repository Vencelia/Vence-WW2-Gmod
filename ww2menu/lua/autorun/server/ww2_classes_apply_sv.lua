if CLIENT then return end

util.AddNetworkString("WW2_ElegirClase")
util.AddNetworkString("WW2_DeployAck")

local MODEL = {
    reich = "models/half-dead/red orchestra 2/ger/rawrecruit.mdl",
    ussr  = "models/half-dead/red orchestra 2/sov/rawrecruit.mdl",
}

local LOADOUT = {
    REICH_TANQUISTA = { "tfa_codww2_mp40", "tfa_codww2_ger_frag", "tfa_codww2_p38", "weapon_lvsrepair", "tfa_codww2_shovel", "weapon_extinguisher" },
    REICH_ASALTO       = { "tfa_codww2_mp40", "tfa_codww2_shovel", "tfa_codww2_luger", "tfa_codww2_ger_frag", "tfa_codww2_satchel_charge" },
    REICH_FUSILERO     = { "tfa_codww2_kar98k", "tfa_codww2_luger", "tfa_codww2_trenchknife", "tfa_codww2_ger_frag", "tfa_codww2_satchel_charge" },
    REICH_SOPORTE      = { "tfa_codww2_stg44", "tfa_codww2_luger", "tfa_codww2_shovel", "tfa_codww2_m18_smoke", "tfa_codww2_ger_frag" },
    REICH_AMETRALLADOR = { "tfa_codww2_mg42", "tfa_codww2_luger", "tfa_codww2_ger_frag" },
    REICH_MEDICO       = { "tfa_codww2_gewehr43", "weapon_medkit", "tfa_codww2_p38" },
	
    USSR_TANQUISTA  = { "tfa_codww2_greasegun", "tfa_codww2_no2", "weapon_lvsrepair", "tfa_codww2_n74_mk1", "tfa_codww2_shovel", "weapon_extinguisher" },
    USSR_ASALTO   = { "tfa_codww2_ppsh41", "tfa_codww2_no2", "tfa_codww2_molotov", "ctfa_codww2_shovel", "tfa_codww2_satchel_charge" },
    USSR_FUSILERO = { "tfa_codww2_mosin", "tfa_codww2_no2", "tfa_codww2_molotov", "tfa_codww2_trenchknife", "tfa_codww2_satchel_charge" },
    USSR_SOPORTE  = { "tfa_codww2_avs36", "tfa_codww2_m18_smoke", "tfa_codww2_usa_frag", "tfa_codww2_shovel" },
    USSR_MEDICO   = { "tfa_codww2_svt40", "weapon_medkit", "tfa_codww2_trenchknife", "tfa_codww2_molotov" },
	USSR_AMETRALLADOR   = { "tfa_codww2_lewis", "tfa_codww2_molotov", "tfa_codww2_no2", "tfa_codww2_shovel" },
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

    if classId == "reich_tanquista" then ply:SetModel("models/half-dead/red orchestra 2/ger/tanker.mdl") elseif classId == "ussr_tanquista" then ply:SetModel("models/half-dead/red orchestra 2/sov/tanker.mdl") elseif MODEL[side] then ply:SetModel(MODEL[side]) end
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
