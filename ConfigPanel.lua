-- GenDexBD ConfigPanel.lua - 设置面板 + 导入导出 + 遇敌统计

local addonName, addonTable = ...
local GetLocaleString = addonTable.GetLocaleString;local ipairs = ipairs;local pairs = pairs
local strmatch = string.match;local strformat = string.format;local time = time

local OPTIONS = {
    { "ShowInTooltip",      "OPTION_SHOW_TOOLTIP",      "check" },
    { "AlertInBattle",      "OPTION_ALERT_BATTLE",      "check" },
    { "AssumeRareQuality",  "OPTION_ASSUME_RARE",       "check" },
    { "ShowBestBreedNote",  "OPTION_SHOW_NOTE",         "check" },
    { "TrackEncounters",    "OPTION_TRACK_ENCOUNTERS",  "check" },
    { "AlertDuration",      "OPTION_ALERT_DURATION",    "slider" },
}

local panel = nil;local categoryID = nil

-- ========== 导入导出工具函数 ==========

local function EscapeField(s)
    if not s then return "" end
    s = s:gsub("\\","\\\\"):gsub("\n","\\n"):gsub("|","\\|")
    return s
end

local function UnescapeField(s)
    if not s then return "" end
    s = s:gsub("\\|","|"):gsub("\\n","\n"):gsub("\\\\","\\")
    return s
end

local function IsValidBreedID(bid)
    return bid and addonTable.BREEDS and addonTable.BREEDS[bid] ~= nil
end

-- ========== 导入导出弹窗 ==========
local function ShowExportDialog()
    local lines = {}
    if GeneDexDB and GeneDexDB.BestBreeds then
        for sid, breeds in pairs(GeneDexDB.BestBreeds) do
            if type(breeds)=="table" then
                for bid, binfo in pairs(breeds) do
                    if type(binfo)=="table" then
                        local cat = EscapeField(binfo.category or "custom")
                        local note = EscapeField(binfo.note or "")
                        lines[#lines+1] = strformat("%d=%d|%s|%s", sid, bid, cat, note)
                    else
                        lines[#lines+1] = strformat("%d=%d", sid, bid)
                    end
                end
            end
        end
    end
    local text = #lines>0 and table.concat(lines,"\n") or ""

    local dlg = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    dlg:SetSize(420, 320);dlg:SetPoint("CENTER");dlg:SetFrameStrata("DIALOG")
    dlg:SetToplevel(true)
    dlg.TitleBg:SetHeight(26)
    local title = dlg:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",0,-12);title:SetText(GetLocaleString("EXPORT_TITLE"))

    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",12,-40);sf:SetPoint("BOTTOMRIGHT",-32,40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true);eb:SetFontObject("GameFontHighlight");eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed",function() dlg:Hide() end)
    sf:SetScrollChild(eb);eb:SetWidth(390)
    eb:SetText(text);eb:HighlightText()

    local hint = dlg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT",16,16);hint:SetText(GetLocaleString("EXPORT_HINT"))

    local closeBtn = CreateFrame("Button",nil,dlg,"UIPanelButtonTemplate")
    closeBtn:SetPoint("BOTTOMRIGHT",-16,16);closeBtn:SetText(CLOSE);closeBtn:SetSize(80,24)
    closeBtn:SetScript("OnClick",function() dlg:Hide() end)
end

local function DoImport(text)
    local count = 0
    for line in (text.."\n"):gmatch("([^\r\n]*)\r?\n") do
        if line ~= "" then
            local sid, bid, cat, note = strmatch(line, "^(%d+)=(%d+)|([^|]*)|(.*)$")
            if sid and bid then
                sid, bid = tonumber(sid), tonumber(bid)
                cat = UnescapeField(cat)
                note = UnescapeField(note)
            else
                sid, bid = strmatch(line, "^(%d+)=(%d+)$")
                if sid and bid then
                    sid, bid = tonumber(sid), tonumber(bid)
                    cat, note = "custom", ""
                end
            end
            if sid and bid and sid>0 and IsValidBreedID(bid) then
                if not GeneDexDB then GeneDexDB = {} end
                if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds)~="table" then GeneDexDB.BestBreeds={} end
                if count == 0 or not GeneDexDB.BestBreeds[sid] then
                    GeneDexDB.BestBreeds[sid] = {}
                end
                GeneDexDB.BestBreeds[sid][bid]={category=cat or "custom",note=note or "",addedAt=time()}
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

    local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",12,-40);sf:SetPoint("BOTTOMRIGHT",-32,40)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true);eb:SetFontObject("GameFontHighlight");eb:SetAutoFocus(true)
    eb:SetScript("OnEscapePressed",function() dlg:Hide() end)
    sf:SetScrollChild(eb);eb:SetWidth(340);eb:SetText("")

    local hint = dlg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT",16,16);hint:SetText(GetLocaleString("IMPORT_HINT"))

    local importBtn = CreateFrame("Button",nil,dlg,"UIPanelButtonTemplate")
    importBtn:SetPoint("BOTTOMRIGHT",-100,16);importBtn:SetText(GetLocaleString("IMPORT_BUTTON"));importBtn:SetSize(80,24)
    importBtn:SetScript("OnClick",function()
        local n = DoImport(eb:GetText())
        print(strformat("|cff00ff00[GenDexBD]|r "..GetLocaleString("IMPORT_DONE"):format(n)))
        dlg:Hide()
    end)

    local cancelBtn = CreateFrame("Button",nil,dlg,"UIPanelButtonTemplate")
    cancelBtn:SetPoint("LEFT",importBtn,"RIGHT",8,0);cancelBtn:SetText(CANCEL);cancelBtn:SetSize(80,24)
    cancelBtn:SetScript("OnClick",function() dlg:Hide() end)
end

-- ========== 遇敌统计内嵌表格 ==========

local encounterRowPool = {}

local function BuildEncounterStats(contentFrame)
    for _, fs in ipairs(encounterRowPool) do fs:SetText("") end
    local rowIndex = 0

    local function getRow()
        rowIndex = rowIndex + 1
        local fs = encounterRowPool[rowIndex]
        if not fs then
            fs = contentFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetWidth(310)
            fs:SetJustifyH("LEFT")
            encounterRowPool[rowIndex] = fs
        end
        fs:SetHeight(15)
        return fs
    end

    -- 表头
    local header = getRow()
    header:SetFontObject("GameFontHighlight")
    header:SetText("|cffffcc00宠物名称          品种      次数|r")
    header:SetPoint("TOPLEFT", 4, 0)

    local prevRow = header
    local yOff = -16

    if GeneDexDB and GeneDexDB.EncounterStats and next(GeneDexDB.EncounterStats) then
        for sid, breeds in pairs(GeneDexDB.EncounterStats) do
            local speciesName = tostring(sid)
            if Rematch and Rematch.petInfo then
                local info = Rematch.petInfo:Fetch(sid)
                if info and info.speciesName then speciesName = info.speciesName end
            end
            local nameRow = getRow()
            nameRow:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, yOff)
            nameRow:SetText("|cffffcc00" .. speciesName .. "|r")
            prevRow = nameRow; yOff = 0

            for bid, count in pairs(breeds) do
                local code = addonTable.GetBreedCode and addonTable.GetBreedCode(bid) or tostring(bid)
                local breedRow = getRow()
                breedRow:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, yOff)
                breedRow:SetText(string.format("    %-20s %-10s %d", code, "", count))
                prevRow = breedRow; yOff = 0
            end
            yOff = -2
        end
    else
        local emptyRow = getRow()
        emptyRow:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -4)
        emptyRow:SetText(GetLocaleString("ENCOUNTER_NO_DATA"))
    end

    contentFrame:SetHeight(math.max(60, rowIndex * 16 + 4))
    for i = rowIndex + 1, #encounterRowPool do
        encounterRowPool[i]:SetText("")
    end
    return rowIndex
end

-- ========== 面板创建 ==========
function addonTable.InitConfig()
    if panel then return end
    panel = CreateFrame("Frame", nil, UIParent)
    panel.name = "GenDexBD"
    -- 加大面板高度容纳 group
    panel:SetSize(500, 520)

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

    -- 遇敌统计独立 Group 框
    local group = CreateFrame("Frame", nil, panel, "InterfaceOptionsGroupTemplate")
    group:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -16)
    group:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 8)
    group.heading:SetText(GetLocaleString("ENCOUNTER_STATS_TITLE"))

    -- 刷新按钮（group 右上角）
    local refreshBtn = CreateFrame("Button", nil, group, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("TOPRIGHT", group, "TOPRIGHT", -12, -12);refreshBtn:SetSize(60,20)
    refreshBtn:SetText("刷新")
    refreshBtn:SetScript("OnClick", function()
        for _, fs in ipairs(encounterRowPool) do fs:Hide() end
        encounterRowPool = {}
        local totalRows = BuildEncounterStats(panel.encounterContent)
        panel.encounterContent:SetHeight(math.max(60, totalRows * 16 + 4))
    end)

    -- 纵向滚动表格（group 内部，带 UIPanelScrollFrameTemplate 自带纵向滚动条）
    local scrollFrame = CreateFrame("ScrollFrame", nil, group, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -34)
    scrollFrame:SetPoint("BOTTOMRIGHT", -34, 14)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(320, 60)
    scrollFrame:SetScrollChild(content)
    panel.encounterContent = content

    local totalRows = BuildEncounterStats(panel.encounterContent)
    content:SetHeight(math.max(60, totalRows * 16 + 4))

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID();Settings.RegisterAddOnCategory(category)
end

function addonTable.ToggleConfigPanel()
    if not categoryID then return end
    Settings.OpenToCategory(categoryID)
end
