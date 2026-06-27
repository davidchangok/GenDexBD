-- GenDexBD ConfigPanel.lua

local addonName, addonTable = ...
local GetLocaleString = addonTable.GetLocaleString;local ipairs = ipairs

local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP",  "check" },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL",  "check" },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE",  "check" },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE",   "check" },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE",     "check" },
    { "AlertDuration",      "OPTION_ALERT_DURATION","slider" },
}

local panel = nil;local categoryID = nil

function addonTable.InitConfig()
    if panel then return end
    panel = CreateFrame("Frame", nil, UIParent);panel.name = "GenDexBD"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16);title:SetText(GetLocaleString("CONFIG_TITLE"))

    local prevCB = nil
    for i, opt in ipairs(OPTIONS) do
        if opt[3] == "check" then
            local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
            cb.Text:SetText(GetLocaleString(opt[2]))
            if i == 1 then cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
            else cb:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -2) end
            prevCB = cb
            cb:SetChecked(GeneDexDB and GeneDexDB.Options and GeneDexDB.Options[opt[1]] == true)
            cb:SetScript("OnClick", function(self) GeneDexDB.Options[opt[1]] = self:GetChecked() or false end)
        elseif opt[3] == "slider" then
            -- 持续时间标签
            local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            lbl:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -8);lbl:SetText(GetLocaleString(opt[2]) .. ":")
            -- 当前值文本
            local valText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            valText:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            local curVal = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AlertDuration or 5
            valText:SetText(curVal .. " " .. GetLocaleString("SECONDS"))
            -- 滑块
            local slider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4);slider:SetWidth(200)
            slider:SetMinMaxValues(1, 30);slider:SetValueStep(1)
            slider:SetValue(curVal)
            slider:SetScript("OnValueChanged", function(self, v)
                v = math.floor(v + 0.5)
                GeneDexDB.Options.AlertDuration = v
                valText:SetText(v .. " " .. GetLocaleString("SECONDS"))
            end)
            prevCB = slider
        end
    end

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID();Settings.RegisterAddOnCategory(category)
    print("|cff00ff00[GenDexBD]|r 配置已注册，categoryID=" .. tostring(categoryID))
end

function addonTable.ToggleConfigPanel()
    if not categoryID then print("|cffff0000[GenDexBD]|r 配置面板未注册，请输入 /reload");return end
    Settings.OpenToCategory(categoryID)
end
