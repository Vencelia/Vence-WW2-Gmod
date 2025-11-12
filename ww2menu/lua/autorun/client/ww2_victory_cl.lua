-- ww2_victory_cl.lua
-- Pantalla de victoria con música y efectos

if SERVER then return end

-- Estado de victoria
local VICTORY_ACTIVE = false
local WINNING_FACTION = ""
local VICTORY_START_TIME = 0
local FADE_DURATION = 3 -- Duración del fade a negro en segundos

-- Música
local currentMusic = nil

-- Fuentes
surface.CreateFont("WW2_Victory_Title", {
    font = "Trebuchet24",
    size = ScreenScale(40),
    weight = 1200,
    extended = true
})
surface.CreateFont("WW2_Victory_Sub", {
    font = "Trebuchet24",
    size = ScreenScale(18),
    weight = 900,
    extended = true
})
-- Colores por facción
local COLORS = {
    reich = Color(80, 150, 255), -- Azul
    ussr = Color(220, 60, 60)    -- Rojo
}

-- Textos de victoria
local VICTORY_TEXT = {
    reich = "VICTORIA PARA EL TERCER REICH",
    ussr  = "VICTORIA PARA LA UNIÓN SOVIÉTICA"
}

-- Música por resultado (ganador/perdedor)
local MUSIC_PATHS = {
    victory = "music/hl2_song23_suitsong3.mp3",  -- Triage At Dawn
    defeat = "music/hl2_song31.mp3"               -- Hunter Down
}

-- Función para iniciar victoria
local function StartVictory(faction)
    VICTORY_ACTIVE = true
    WINNING_FACTION = faction
    VICTORY_START_TIME = CurTime()
    
    -- Determinar si el jugador ganó o perdió
    local playerFaction = LocalPlayer():GetNWString("ww2_faction", "")
    local isWinner = (playerFaction == faction)
    
    -- Reproducir música apropiada
    if isWinner then
        -- Música de victoria (Triage At Dawn)
        surface.PlaySound(MUSIC_PATHS.victory)
    else
        -- Música de derrota (Hunter Down)
        surface.PlaySound(MUSIC_PATHS.defeat)
    end
    
    print("[WW2] Victoria iniciada:", faction, "| Jugador:", playerFaction, "| Ganador:", isWinner)
end

-- Función para limpiar victoria
local function ClearVictory()
    VICTORY_ACTIVE = false
    WINNING_FACTION = ""
    VICTORY_START_TIME = 0
    
    -- Detener música
    if currentMusic then
        currentMusic:Stop()
        currentMusic = nil
    end
    
    print("[WW2] Victoria limpiada (cliente)")
end

-- Recibir mensaje de victoria del servidor
net.Receive("WW2_Victory", function()
    local faction = net.ReadString()
    StartVictory(faction)
end)

-- Recibir señal de limpieza
net.Receive("WW2_VictoryClear", function()
    ClearVictory()
end)

-- Dibujar pantalla de victoria
hook.Add("HUDPaint", "WW2_VictoryScreen", function()
    if not VICTORY_ACTIVE then return end
    
    local scrW, scrH = ScrW(), ScrH()
    local timeSinceStart = CurTime() - VICTORY_START_TIME
    
    -- Determinar si el jugador ganó
    local playerFaction = LocalPlayer():GetNWString("ww2_faction", "")
    local isWinner = (playerFaction == WINNING_FACTION)
    
    -- Color según facción ganadora
    local victoryColor = COLORS[WINNING_FACTION] or Color(255, 255, 255)
    local victoryText = VICTORY_TEXT[WINNING_FACTION] or "VICTORIA"
    
    -- ✅ FADE A NEGRO (solo para perdedores)
    if not isWinner then
        -- Calcular alpha del fade (0 a 255 en FADE_DURATION segundos)
        local fadeProgress = math.Clamp(timeSinceStart / FADE_DURATION, 0, 1)
        local fadeAlpha = math.floor(255 * fadeProgress)
        
        -- Dibujar overlay negro con fade
        surface.SetDrawColor(0, 0, 0, fadeAlpha)
        surface.DrawRect(0, 0, scrW, scrH)
    end
    
    -- ✅ TEXTO DE VICTORIA (siempre visible, encima del fade)
    -- Animación de aparición (fade in del texto)
    local textFadeIn = math.Clamp(timeSinceStart * 2, 0, 1)
    local textAlpha = math.floor(255 * textFadeIn)
    
    -- Sombra del texto
    draw.SimpleText(
        victoryText,
        "WW2_Victory_Title",
        scrW * 0.5 + 4,
        scrH * 0.35 + 4,
        Color(0, 0, 0, textAlpha * 0.8),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
    
    -- Texto principal
    draw.SimpleText(
        victoryText,
        "WW2_Victory_Title",
        scrW * 0.5,
        scrH * 0.35,
        Color(victoryColor.r, victoryColor.g, victoryColor.b, textAlpha),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
    
    -- ✅ SUBTÍTULO (resultado para el jugador)
    -- Info extra
    draw.SimpleText("Todas las bases y puntos controlados", "WW2_Victory_Sub", ScrW()*0.5, ScrH()*0.52, Color(235,235,235, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    local subtitleText = isWinner and "VICTORIA" or "DERROTA"
    local subtitleColor = isWinner and Color(80,150,255, textAlpha) or Color(255, 60, 60, textAlpha)
    
    -- Sombra del subtítulo
    draw.SimpleText(
        subtitleText,
        "WW2_Victory_Sub",
        scrW * 0.5 + 2,
        scrH * 0.45 + 2,
        Color(0, 0, 0, textAlpha * 0.8),
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
    
    -- Subtítulo
    draw.SimpleText(
        subtitleText,
        "WW2_Victory_Sub",
        scrW * 0.5,
        scrH * 0.45,
        subtitleColor,
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
    
    -- ✅ INSTRUCCIÓN (después de 5 segundos)
    if timeSinceStart > 5 then
        local instructionAlpha = math.floor(255 * math.Clamp((timeSinceStart - 5) * 0.5, 0, 1))
        
        draw.SimpleText(
            "El admin cambiará el mapa pronto...",
            "WW2_Victory_Sub",
            scrW * 0.5,
            scrH * 0.85,
            Color(220, 220, 220, instructionAlpha),
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER
        )
    end
end)

-- Bloquear HUD normal durante victoria
-- HUDShouldDraw override removed to keep HUD visible

-- Limpiar al desconectar
hook.Add("ShutDown", "WW2_VictoryClientCleanup", function()
    ClearVictory()
end)

-- Comando de testing (cliente)
concommand.Add("ww2_test_victory_client", function(ply, cmd, args)
    local faction = args[1] or "reich"
    if faction ~= "reich" and faction ~= "ussr" then
        faction = "reich"
    end
    
    print("[WW2] Testing victoria (cliente):", faction)
    StartVictory(faction)
end)

concommand.Add("ww2_clear_victory_client", function()
    ClearVictory()
end)