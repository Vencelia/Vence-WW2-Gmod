if SERVER then return end
include("autorun/shared/ww2_factions_sh.lua")

surface.CreateFont("WW2_ClassTitle",{font="Montserrat", size=ScreenScale(12), weight=1000})
surface.CreateFont("WW2_ClassItem", {font="Montserrat", size=ScreenScale(8),  weight=800})
surface.CreateFont("WW2_Opcion",    {font="Montserrat", size=ScreenScale(7),  weight=600})
surface.CreateFont("WW2_DeathBtn",  {font="Montserrat", size=ScreenScale(9),  weight=800})

local function DrawClassCard(btn, title, modelTxt, weaponsTxt)
    btn:SetText("")
    btn.Paint = function(self, w, h)
        surface.SetDrawColor(45,45,50,240) surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(255,255,255,30) surface.DrawOutlinedRect(0,0,w,h,2)
        draw.SimpleText(title, "WW2_ClassItem", 16, 16, Color(230,230,230))
        draw.SimpleText("Model:", "WW2_Opcion", 16, 56, Color(200,200,200))
        draw.SimpleText(modelTxt, "WW2_Opcion", 90, 56, Color(230,230,230))
        draw.SimpleText("Armas:", "WW2_Opcion", 16, 84, Color(200,200,200))
        draw.SimpleText(weaponsTxt, "WW2_Opcion", 90, 84, Color(230,230,230))
    end
end

local function BuildClassesFrame(titleText, classDefs)
    local scrW, scrH = ScrW(), ScrH()
    local frame = vgui.Create("DFrame")
    frame:SetSize(scrW, scrH)
    frame:SetTitle("")
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(self,w,h)
        surface.SetDrawColor(10,10,12,240) surface.DrawRect(0,0,w,h)
        draw.SimpleText(titleText or "CLASES", "WW2_ClassTitle", w*0.5, 60, Color(230,230,230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local panel = vgui.Create("DPanel", frame)
    panel:SetSize(scrW*0.7, scrH*0.6)
    panel:Center()
    panel.Paint = function(self,w,h) surface.SetDrawColor(25,25,25,230) surface.DrawRect(0,0,w,h) end

    local cols = 2
    local rows = math.ceil(#classDefs / cols)
    local cellW = (panel:GetWide() - 60) / cols
    local cellH = (panel:GetTall() - 60) / math.max(1, rows)
    local i = 0

    for _, def in ipairs(classDefs) do
        i = i + 1
        local col = (i-1) % cols
        local row = math.floor((i-1) / cols)
        local btn = vgui.Create("DButton", panel)
        btn:SetSize(cellW, cellH)
        btn:SetPos(20 + col * (cellW + 20), 20 + row * (cellH + 20))
        DrawClassCard(btn, def.title, def.model, def.weaponsTxt or "")
        btn.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            if IsValid(frame) then frame:Remove() end
            if WW2_AbrirMenuDespliegue then
                WW2_AbrirMenuDespliegue(def.classId)
            else
                chat.AddText(Color(255,80,80), "[WW2] Falta el menú de despliegue (WW2_AbrirMenuDespliegue).")
            end
        end
    end

    local btnBack = vgui.Create("DButton", frame)
    btnBack:SetSize(180, 54)
    btnBack:SetPos(40, scrH - 90)
    btnBack:SetText("")
    btnBack.Paint = function(self, w, h)
        surface.SetDrawColor(30,30,30,240) surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(255,255,255,30) surface.DrawOutlinedRect(0,0,w,h,2)
        draw.SimpleText("← Volver", "WW2_DeathBtn", w/2, h/2, Color(230,230,230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnBack.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        if IsValid(frame) then frame:Remove() end
        -- No existe menú principal; simplemente cerramos.
    end
end

function WW2_AbrirMenuClases_Reich()
    BuildClassesFrame("CLASES TERCER REICH", {
        { title="ASALTO",       classId=WW2.CLASE.REICH_ASALTO,       model="Infanteria Alemana",
          weaponsTxt="MP40, Pala de trinchera (DE), Luger P08, Granada M24" },

        { title="FUSILERO",     classId=WW2.CLASE.REICH_FUSILERO,     model="Infanteria Alemana",
          weaponsTxt="Kar98k, Luger P08, Bayoneta K98k" },

        { title="SOPORTE",      classId=WW2.CLASE.REICH_SOPORTE,      model="Infanteria Alemana",
          weaponsTxt="StG 44, Luger P08, Pala de trinchera (DE), Granada N39, Granada M24" },

        { title="AMETRALLADOR", classId=WW2.CLASE.REICH_AMETRALLADOR, model="Infanteria Alemana",
          weaponsTxt="MG34, P38, Granada N39" },

        { title="MÉDICO",       classId=WW2.CLASE.REICH_MEDICO,       model="Infanteria Alemana",
          weaponsTxt="G43, Botiquín, P38" },

        { title="TANQUISTA",    classId=WW2.CLASE.REICH_TANQUISTA,    model="Tripulante de Tanque",
          weaponsTxt="MP40, Granada M24, P38, Herramienta de reparación, Pala de trinchera (DE), Extintor" }
    })
end

function WW2_AbrirMenuClases_USSR()
    BuildClassesFrame("CLASES UNIÓN SOVIÉTICA", {
        { title="ASALTO",       classId=WW2.CLASE.USSR_ASALTO,        model="models/ro1soviet_rifleman4pm.mdl",
          weaponsTxt="PPD-40 (tambor), Nagant M1895, Granada RG-42, Pala de trinchera" },

        { title="FUSILERO",     classId=WW2.CLASE.USSR_FUSILERO,      model="models/ro1soviet_rifleman4pm.mdl",
          weaponsTxt="Bayoneta SVT-40, Granada RPG-40, Nagant M1895, TNT soviético" },

        { title="SOPORTE",      classId=WW2.CLASE.USSR_SOPORTE,       model="models/ro1soviet_rifleman4pm.mdl",
          weaponsTxt="PPS-43, Granada F1, Granada RDG-1, Pala de trinchera" },

        { title="AMETRALLADOR", classId=WW2.CLASE.USSR_AMETRALLADOR,  model="models/ro1soviet_rifleman4pm.mdl",
          weaponsTxt="DP-27, TT-33, Granada RDG-1, Pala de trinchera" },

        { title="MÉDICO",       classId=WW2.CLASE.USSR_MEDICO,        model="models/ro1soviet_rifleman4pm.mdl",
          weaponsTxt="SVT-40, Botiquín, Bayoneta SVT-40, TT-33" },

        { title="TANQUISTA",    classId=WW2.CLASE.USSR_TANQUISTA,     model="models/ro_ost_41-45_soviet_tank_crew3pm.mdl",
          weaponsTxt="PPD-40 (tambor), TT-33, Herramienta de reparación, RPG-40, Pala de trinchera, Extintor" }
    })
end
