-- ww2_victory_loader.lua
-- Carga el sistema de victoria

if SERVER then
    AddCSLuaFile("autorun/client/ww2_victory_cl.lua")
    include("autorun/server/ww2_victory_sv.lua")
    
    print("[WW2] Sistema de Victoria cargado (servidor)")
end

if CLIENT then
    include("autorun/client/ww2_victory_cl.lua")
    
    print("[WW2] Sistema de Victoria cargado (cliente)")
end