-- GenDexBD ConfigPanel.lua - 设置面板 + 导入导出

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

-- 转义导出字段中的特殊字符（用 \| 代替 |, \n 代替换行）
local function EscapeField(s)
    if not s then return "" end
    s = s:gsub("\\","\\\\"):gsub("\n","\\n"):gsub("|","\\|")
    return s
end

-- 反转义
local function UnescapeField(s)
    if not s then return "" end
    -- 注意顺序：先还原 \| 再还原 \\（避免 double-unescape）
    s = s:gsub("\\|","|"):gsub("\\n","\n"):gsub("\\\\","\\")
    return s
end

-- 检查 breedID 是否有效（从 BreedData 表动态获取范围）
local function IsValidBreedID(bid)
    return bid and addonTable.BREEDS and addonTable.BREEDS[bid] ~= nil
end

-- ========== 导入导出弹窗 ==========
local function ShowExportDialog()
    -- 序列化 BestBreeds: speciesID=breedID|category|note（元数据完整保留）
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
                        -- 旧格式兼容：无元数据
                        lines[#lines+1] = strformat("%d=%d", sid, bid)
                    end
                end
            end
        end
    end
    local text = #lines>0 and table.concat(lines,"\n") or ""

    -- 创建导出弹窗
    local dlg = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    dlg:SetSize(420, 320);dlg:SetPoint("CENTER");dlg:SetFrameStrata("DIALOG")
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
    sf:SetScrollChild(eb);eb:SetWidth(390)
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
    -- 兼容 CRLF (\r\n) 和 LF (\n) 行尾
    for line in (text.."\n"):gmatch("([^\r\n]*)\r?\n") do
        if line ~= "" then
            -- 新格式: speciesID=breedID|category|note
            local sid, bid, cat, note = strmatch(line, "^(%d+)=(%d+)|([^|]*)|(.*)$")
            if sid and bid then
                sid, bid = tonumber(sid), tonumber(bid)
                cat = UnescapeField(cat)
                note = UnescapeField(note)
            else
                -- 旧格式兼容: speciesID=breedID
                sid, bid = strmatch(line, "^(%d+)=(%d+)$")
                if sid and bid then
                    sid, bid = tonumber(sid), tonumber(bid)
                    cat, note = "custom", ""
                end
            end
            if sid and bid and sid>0 and IsValidBreedID(bid) then
                if not GeneDexDB then GeneDexDB = {} end
                if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds)~="table" then GeneDexDB.BestBreeds={} end
                -- 同物种首次导入时清空已有数据（后续行直接写入，避免多行互相覆盖）
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

-- ========== 遇敌统计内嵌表格 ==========

local encounterRowPool = {}  -- FontString 对象池

local function BuildEncounterStats(panel, anchor)
    for _, fs in ipairs(encounterRowPool) do fs:SetText("") end
    local rowIndex = 0

    local function getRow()
        rowIndex = rowIndex + 1
        local fs = encounterRowPool[rowIndex]
        if not fs then
            fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetWidth(360)
            fs:SetJustifyH("LEFT")
            encounterRowPool[rowIndex] = fs
        end
        return fs
    end

    local header = getRow()
    header:SetFontObject("GameFontHighlight")
    header:SetText(string.format("%-30s %-10s %s", "宠物名称", "品种", "次数"))
    header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 2, -6)

    local prevRow = header
    if GeneDexDB and GeneDexDB.EncounterStats and next(GeneDexDB.EncounterStats) then
        for sid, breeds in pairs(GeneDexDB.EncounterStats) do
            local speciesName = tostring(sid)
            if Rematch and Rematch.petInfo then
                local info = Rematch.petInfo:Fetch(sid)
                if info and info.speciesName then speciesName = info.speciesName end
            end
            local nameRow = getRow()
            nameRow:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -2)
            nameRow:SetText("|cffffcc00" .. speciesName .. "|r")
            prevRow = nameRow
            for bid, count in pairs(breeds) do
                local code = addonTable.GetBreedCode and addonTable.GetBreedCode(bid) or tostring(bid)
                local breedRow = getRow()
                breedRow:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, 0)
                breedRow:SetText(string.format("    %-20s %-10s %d", code, "", count))
                prevRow = breedRow
            end
        end
    else
        local emptyRow = getRow()
        emptyRow:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -4)
        emptyRow:SetText(GetLocaleString("ENCOUNTER_NO_DATA"))
    end
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

    -- 遇敌统计（纯 FontString 追加，无额外 Frame，面板自带滚动）
    local statsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statsTitle:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -12)
    statsTitle:SetText(GetLocaleString("ENCOUNTER_STATS_TITLE"))

    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("LEFT", statsTitle, "RIGHT", 8, 2);refreshBtn:SetSize(60, 20)
    refreshBtn:SetText("刷新")
    refreshBtn:SetScript("OnClick", function()
        for _, fs in ipairs(encounterRowPool) do fs:Hide() end
        encounterRowPool = {}
        BuildEncounterStats(panel, statsTitle)
    end)

    BuildEncounterStats(panel, statsTitle)

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID();Settings.RegisterAddOnCategory(category)
end

function addonTable.ToggleConfigPanel()
    if not categoryID then return end
    Settings.OpenToCategory(categoryID)
end
