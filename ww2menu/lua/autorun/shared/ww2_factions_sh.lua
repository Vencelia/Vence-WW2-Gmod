-- WW2 Facciones y Clases (Compartido)

WW2 = WW2 or {}
WW2.FACCION = WW2.FACCION or {}
WW2.CLASE   = WW2.CLASE   or {}

-- Facciones
WW2.FACCION.REICH = "reich"
WW2.FACCION.USSR  = "ussr"

WW2.FactionNames = {
    [WW2.FACCION.REICH] = "Tercer Reich",
    [WW2.FACCION.USSR]  = "Unión Soviética",
}

WW2.FactionColors = {
    [WW2.FACCION.REICH] = Color(70, 120, 255), -- Azul notable
    [WW2.FACCION.USSR]  = Color(220, 50, 50),  -- Rojo notable
}

-- Clases (IDs)
-- Reich
WW2.CLASE.REICH_ASALTO       = "reich_asalto"       -- ya existente
WW2.CLASE.REICH_FUSILERO     = "reich_fusilero"
WW2.CLASE.REICH_SOPORTE      = "reich_soporte"
WW2.CLASE.REICH_AMETRALLADOR = "reich_ametrallador"
WW2.CLASE.REICH_MEDICO       = "reich_medico"
WW2.CLASE.REICH_INGENIERO    = "reich_ingeniero"
WW2.CLASE.REICH_TANQUISTA    = "reich_tanquista"
-- USSR
WW2.CLASE.USSR_ASALTO        = "ussr_asalto"        -- ya existente
WW2.CLASE.USSR_FUSILERO      = "ussr_fusilero"
WW2.CLASE.USSR_SOPORTE       = "ussr_soporte"
WW2.CLASE.USSR_AMETRALLADOR  = "ussr_ametrallador"
WW2.CLASE.USSR_MEDICO        = "ussr_medico"
WW2.CLASE.USSR_INGENIERO     = "ussr_ingeniero"
WW2.CLASE.USSR_TANQUISTA     = "ussr_tanquista"
WW2.ClassNames = {
    [WW2.CLASE.REICH_ASALTO]       = "ASALTO",
    [WW2.CLASE.REICH_FUSILERO]     = "FUSILERO",
    [WW2.CLASE.REICH_SOPORTE]      = "SOPORTE",
    [WW2.CLASE.REICH_AMETRALLADOR] = "AMETRALLADOR LIGERO",
    [WW2.CLASE.REICH_MEDICO]       = "MÉDICO",
    [WW2.CLASE.REICH_INGENIERO]    = "INGENIERO",
	[WW2.CLASE.REICH_TANQUISTA]    = "TANQUISTA",

    [WW2.CLASE.USSR_ASALTO]        = "ASALTO",
    [WW2.CLASE.USSR_FUSILERO]      = "FUSILERO",
    [WW2.CLASE.USSR_SOPORTE]       = "SOPORTE",
    [WW2.CLASE.USSR_AMETRALLADOR]  = "AMETRALLADOR LIGERO",
    [WW2.CLASE.USSR_MEDICO]        = "MÉDICO",
    [WW2.CLASE.USSR_INGENIERO]     = "INGENIERO",
	[WW2.CLASE.USSR_TANQUISTA]     = "TANQUISTA",
	
}

-- Redstrings
if SERVER then
    util.AddNetworkString("WW2_ElegirBando")     -- C->S: string faccion
    util.AddNetworkString("WW2_ElegirClase")     -- C->S: string clase
    util.AddNetworkString("WW2_SyncFaction")     -- S->C: string faccion
    util.AddNetworkString("WW2_SyncClass")       -- S->C: string clase
    util.AddNetworkString("WW2_RequestRespawn")  -- C->S: pedir respawn
end

-- Helpers jugador
local PLAYER = FindMetaTable("Player")
function PLAYER:WW2_GetFaction() return self:GetNWString("ww2_faction", "") end
function PLAYER:WW2_GetClass()   return self:GetNWString("ww2_class",   "") end
function PLAYER:WW2_HasFaction() return self:WW2_GetFaction() ~= "" end
function PLAYER:WW2_HasClass()   return self:WW2_GetClass()   ~= "" end
