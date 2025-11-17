-- lua/weapons/gmod_tool/stools/ww2_point_connector.lua
-- Herramienta "Conector de puntos" para enlazar bases y puntos de captura manualmente.

TOOL.Category   = "Venceww2"
TOOL.Name       = "Conector de puntos"
TOOL.Command    = nil
TOOL.ConfigName = ""

local BASE_CLASSES = {
    ["ww2_base_reich"] = true,
    ["ww2_base_ussr"]  = true
}

local CAP_CLASSES = {
    ["ww2_cap_point"]     = true,
    ["ww2_capture_point"] = true
}

local function IsBase(ent)
    return IsValid(ent) and BASE_CLASSES[ent:GetClass()] or false
end

local function IsCapPoint(ent)
    return IsValid(ent) and CAP_CLASSES[ent:GetClass()] or false
end

if CLIENT then
    language.Add("tool.ww2_point_connector.name", "Conector de puntos")
    language.Add("tool.ww2_point_connector.desc", "Enlaza manualmente bases y puntos de captura para crear brazos de ataque.")
    language.Add("tool.ww2_point_connector.0",    "Click izquierdo: seleccionar BASE defensora, luego puntos y BASE atacante. Click derecho: cancelar brazo actual.")

    -- Halos y líneas de debug solo cuando esta herramienta está activa
    hook.Add("PreDrawHalos", "WW2_PointConnector_Halos", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" then return end
        if wep:GetMode() ~= "ww2_point_connector" then return end

        local base = ply:GetNWEntity("ww2_conn_defbase")
        if IsValid(base) then
            halo.Add({base}, Color(0, 255, 0), 3, 3, 1, true, true)
        end
    end)

    hook.Add("PostDrawTranslucentRenderables", "WW2_PointConnector_DrawArms", function(depth, sky)
        if sky then return end

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" then return end
        if wep:GetMode() ~= "ww2_point_connector" then return end

        local function drawArmLines(list)
            for _, cp in ipairs(list) do
                if IsValid(cp) then
                    local baseId = cp:GetNWInt("arm_base_id", 0)
                    if baseId > 0 then
                        local base = Entity(baseId)
                        if IsValid(base) then
                            render.DrawLine(
                                base:GetPos() + Vector(0, 0, 40),
                                cp:GetPos()   + Vector(0, 0, 40),
                                Color(0, 100, 255),
                                true
                            )
                        end
                    end

                    local atkId = cp:GetNWInt("arm_attack_base_id", 0)
                    if atkId > 0 then
                        local atk = Entity(atkId)
                        if IsValid(atk) then
                            render.DrawLine(
                                cp:GetPos()  + Vector(0, 0, 45),
                                atk:GetPos() + Vector(0, 0, 45),
                                Color(0, 150, 255),
                                true
                            )
                        end
                    end
                end
            end
        end

        local allCaps = {}
        for cls, _ in pairs(CAP_CLASSES) do
            for _, cp in ipairs(ents.FindByClass(cls)) do
                if IsValid(cp) then
                    table.insert(allCaps, cp)
                end
            end
        end
        drawArmLines(allCaps)
    end)

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", {
            Text        = "Conector de puntos",
            Description = "Selecciona una BASE defensora (URSS/Reich), luego los puntos de captura en orden (A, B, C, ...), y finalmente una BASE atacante."
        })
    end
end

-- =========================
--  LÓGICA SERVIDOR
-- =========================

-- Devuelve el próximo índice de brazo para una base (1,2,3...)
local function GetNextArmIndexForBase(baseEnt)
    if not IsValid(baseEnt) then return 1 end
    local baseId = baseEnt:EntIndex()
    local maxIdx = 0

    for cls, _ in pairs(CAP_CLASSES) do
        for _, cp in ipairs(ents.FindByClass(cls)) do
            if IsValid(cp) and cp:GetNWInt("arm_base_id", 0) == baseId then
                local idx = cp:GetNWInt("arm_index", 0)
                if idx > maxIdx then
                    maxIdx = idx
                end
            end
        end
    end

    return maxIdx + 1
end

local function OrderToLetter(order)
    local a = string.byte("A")
    local z = string.byte("Z")
    local b = a + (order - 1)
    if b < a then b = a end
    if b > z then b = z end
    return string.char(b)
end

function TOOL:ClearBuildState()
    self.DefBase          = nil
    self.CurrentArmIndex  = nil
    self.NextOrder        = nil
    self.CurrentArmPoints = {}

    if SERVER then
        local ply = self:GetOwner()
        if IsValid(ply) then
            ply:SetNWEntity("ww2_conn_defbase", nil)
        end
    end
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    local ent = trace.Entity

    if not IsValid(ent) then
        ply:ChatPrint("[WW2] No has apuntado a una entidad válida.")
        return false
    end

    -- 1) Seleccionar BASE defensora si aún no hay
    if not self.DefBase then
        if not IsBase(ent) then
            ply:ChatPrint("[WW2] Primero selecciona una BASE defensora (URSS o Reich) con click izquierdo.")
            return false
        end

        self.DefBase          = ent
        self.CurrentArmIndex  = nil
        self.NextOrder        = 1
        self.CurrentArmPoints = {}

        ply:SetNWEntity("ww2_conn_defbase", ent)

        ply:ChatPrint(string.format("[WW2] BASE defensora seleccionada: %s (id %d).", ent:GetClass(), ent:EntIndex()))
        ply:ChatPrint("[WW2] Ahora selecciona puntos de captura en orden (A,B,C,...) y finalmente una BASE atacante.")
        return true
    end

    -- 2) Si ya hay BASE defensora, podemos:
    --   a) Añadir un punto de captura al brazo actual
    --   b) Finalizar el brazo seleccionando una BASE atacante

    if IsCapPoint(ent) then
        -- Añadir punto de captura al brazo en construcción
        if not self.CurrentArmIndex then
            self.CurrentArmIndex = GetNextArmIndexForBase(self.DefBase)
        end

        local order  = self.NextOrder or (#self.CurrentArmPoints + 1)
        local letter = OrderToLetter(order)
        local baseId = self.DefBase:EntIndex()

        ent:SetNWInt("arm_base_id", baseId)
        ent:SetNWInt("arm_index",   self.CurrentArmIndex)
        ent:SetNWInt("arm_order",   order)
        ent:SetNWString("arm_letter", letter)

        local curLabel = ent:GetNWString("cap_label", "")
        if curLabel == nil or curLabel == "" then
            ent:SetNWString("cap_label", letter .. tostring(self.CurrentArmIndex))
        end

        table.insert(self.CurrentArmPoints, ent)
        self.NextOrder = order + 1

        ply:ChatPrint(string.format(
            "[WW2] Punto de captura añadido al brazo %d: %s (orden %d -> %s%d).",
            self.CurrentArmIndex, ent:GetClass(), order, letter, self.CurrentArmIndex
        ))

        -- Recalcular frente si el sistema de brazos lo soporta
        if WW2 and WW2.Arms and WW2.Arms.RebuildFrontState then
            WW2.Arms.RebuildFrontState()
        end

        return true
    end

    if IsBase(ent) then
        -- Seleccionar BASE atacante para cerrar el brazo actual
        if ent == self.DefBase then
            ply:ChatPrint("[WW2] Esta base ya es la defensora. Selecciona otra BASE para marcarla como atacante.")
            return false
        end

        if not self.CurrentArmIndex or not self.CurrentArmPoints or #self.CurrentArmPoints == 0 then
            ply:ChatPrint("[WW2] Primero selecciona al menos un punto de captura entre la BASE defensora y la atacante.")
            return false
        end

        local atkId = ent:EntIndex()
        for _, cp in ipairs(self.CurrentArmPoints) do
            if IsValid(cp) then
                cp:SetNWInt("arm_attack_base_id", atkId)
            end
        end

        ply:ChatPrint(string.format(
            "[WW2] Brazo de ataque creado: BASE defensora %s[%d] -> %d puntos -> BASE atacante %s[%d].",
            self.DefBase:GetClass(), self.DefBase:EntIndex(),
            #self.CurrentArmPoints,
            ent:GetClass(), atkId
        ))

        -- Podemos seguir usando la misma BASE defensora para un nuevo brazo (A2,B2,...)
        self.CurrentArmIndex  = nil
        self.NextOrder        = 1
        self.CurrentArmPoints = {}

        -- Recalcular frente si el sistema lo usa
        if WW2 and WW2.Arms and WW2.Arms.RebuildFrontState then
            WW2.Arms.RebuildFrontState()
        end

        return true
    end

    ply:ChatPrint("[WW2] Solo puedes enlazar BASES y puntos de captura con esta herramienta.")
    return false
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    self:ClearBuildState()

    if IsValid(ply) then
        ply:ChatPrint("[WW2] Brazo actual cancelado y selección limpia.")
    end

    return true
end

function TOOL:Reload(trace)
    -- Podemos usar Reload igual que RightClick o dejarlo para futuras funciones
    return self:RightClick(trace)
end
