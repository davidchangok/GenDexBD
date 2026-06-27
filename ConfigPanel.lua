-- GenDexBD ConfigPanel.lua - 设置面板 + 导入导出

local addonName, addonTable = ...
local GetLocaleString = addonTable.GetLocaleString;local ipairs = ipairs;local pairs = pairs
local strmatch = string.match;local strformat = string.format;local time = time

local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP",  "check" },
    { "ShowInJournal",      "OPTION_SHOW_JOURNAL",  "check" },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE",  "check" },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE",   "check" },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE",     "check" },
    { "AlertDuration",      "OPTION_ALERT_DURATION","slider" },
}

local panel = nil;local categoryID = nil

-- ========== 导入导出弹窗 ==========
local function ShowExportDialog()
    -- 序列化 BestBreeds: 一行一个 speciesID=breedID
    local lines = {}
    if GeneDexDB and GeneDexDB.BestBreeds then
        for sid, breeds in pairs(GeneDexDB.BestBreeds) do
            if type(breeds)=="table" then
                for bid in pairs(breeds) do
                    lines[#lines+1] = strformat("%d=%d", sid, bid)
                end
            end
        end
    end
    local text = #lines>0 and table.concat(lines,"\n") or ""

    -- 创建导出弹窗
    local dlg = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    dlg:SetSize(380, 320);dlg:SetPoint("CENTER");dlg:SetFrameStrata("DIALOG")
    dlg:SetToplevel(true)
    dlg.TitleBg:SetHeight(26)
    local title = dlg:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",0,-12);title:SetText(GetLocaleString("EXPORT_TITLE"))

    -- 滚动编辑框
    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",12,-40);sf:SetPoint("BOTTOMRIGHT",-32,40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true);eb:SetFontObject("GameFontHighlight");eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed",function() dlg:Hide() end)
    sf:SetScrollChild(eb);eb:SetWidth(340)
    eb:SetText(text);eb:HighlightText()

    -- 提示文字
    local hint = dlg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT",16,16);hint:SetText(GetLocaleString("EXPORT_HINT"))

    -- 关闭按钮
    local closeBtn = CreateFrame("Button",nil,dlg,"UIPanelButtonTemplate")
    closeBtn:SetPoint("BOTTOMRIGHT",-16,16);closeBtn:SetText(CLOSE);closeBtn:SetSize(80,24)
    closeBtn:SetScript("OnClick",function() dlg:Hide() end)
end

local function DoImport(text)
    local count = 0
    for line in (text.."\n"):gmatch("(.-)\n") do
        local sid,bid = strmatch(line,"^(%d+)=(%d+)$")
        if sid and bid then
            sid,bid = tonumber(sid),tonumber(bid)
            if sid and bid and sid>0 and bid>=3 and bid<=14 then
                if not GeneDexDB then GeneDexDB = {} end
                if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds)~="table" then GeneDexDB.BestBreeds={} end
                -- 同物种只保留一个最优（与 SetBestBreed 一致）
                GeneDexDB.BestBreeds[sid]={}
                GeneDexDB.BestBreeds[sid][bid]={category="custom",note="",addedAt=time()}
                count = count + 1
            end
        end
    end
    return count
end

local function ShowImportDialog()
    local dlg = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    dlg:SetSize(380, 320);dlg:SetPoint("CENTER");dlg:SetFrameStrata("DIALOG")
    dlg:SetToplevel(true)
    dlg.TitleBg:SetHeight(26)
    local title = dlg:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",0,-12);title:SetText(GetLocaleString("IMPORT_TITLE"))

    -- 滚动编辑框
    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",12,-40);sf:SetPoint("BOTTOMRIGHT",-32,40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true);eb:SetFontObject("GameFontHighlight");eb:SetAutoFocus(true)
    eb:SetScript("OnEscapePressed",function() dlg:Hide() end)
    sf:SetScrollChild(eb);eb:SetWidth(340);eb:SetText("")

    -- 提示
    local hint = dlg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT",16,16);hint:SetText(GetLocaleString("IMPORT_HINT"))

    -- 导入按钮
    local importBtn = CreateFrame("Button",nil,dlg,"UIPanelButtonTemplate")
    importBtn:SetPoint("BOTTOMRIGHT",-100,16);importBtn:SetText(GetLocaleString("IMPORT_BUTTON"));importBtn:SetSize(80,24)
    importBtn:SetScript("OnClick",function()
        local n = DoImport(eb:GetText())
        print(strformat("|cff00ff00[GenDexBD]|r "..GetLocaleString("IMPORT_DONE"):format(n)))
        dlg:Hide()
    end)

    -- 取消按钮
    local cancelBtn = CreateFrame("Button",nil,dlg,"UIPanelButtonTemplate")
    cancelBtn:SetPoint("LEFT",importBtn,"RIGHT",8,0);cancelBtn:SetText(CANCEL);cancelBtn:SetSize(80,24)
    cancelBtn:SetScript("OnClick",function() dlg:Hide() end)
end

-- ========== 面板创建 ==========
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
            local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            lbl:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -8);lbl:SetText(GetLocaleString(opt[2]) .. ":")
            local valText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            valText:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            local curVal = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AlertDuration or 5
            valText:SetText(curVal .. " " .. GetLocaleString("SECONDS"))
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

    -- 导出/导入按钮
    local exportBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    exportBtn:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -12);exportBtn:SetSize(120,24)
    exportBtn:SetText(GetLocaleString("EXPORT_BUTTON"))
    exportBtn:SetScript("OnClick", ShowExportDialog)

    local importBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0);importBtn:SetSize(120,24)
    importBtn:SetText(GetLocaleString("IMPORT_BUTTON"))
    importBtn:SetScript("OnClick", ShowImportDialog)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID();Settings.RegisterAddOnCategory(category)
    print("|cff00ff00[GenDexBD]|r 配置已注册，categoryID=" .. tostring(categoryID))
end

function addonTable.ToggleConfigPanel()
    if not categoryID then print("|cffff0000[GenDexBD]|r 配置面板未注册，请输入 /reload");return end
    Settings.OpenToCategory(categoryID)
end
