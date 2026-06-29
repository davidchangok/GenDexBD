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

-- ========== 遇敌统计 — Flipper 式 ScrollFrame 表格 ==========

-- 列布局常量（像素偏移，比例字体安全）
local ENC_COL = {
    ICON  = 5,                    -- 图标左边缘
    NAME  = 28,                   -- 宠物名称左边缘
    BREED = 240,                  -- 品种代码左边缘
    COUNT = 310,                  -- 遇敌次数左边缘
}
local ENC_NAME_W  = 208           -- NAME 列像素宽度
local ENC_BREED_W = 65            -- BREED 列像素宽度
local ENC_COUNT_W = 50            -- COUNT 列像素宽度
local ENC_ROW_HEIGHT = 22
local ENC_SCROLL_HEIGHT = 220     -- ScrollFrame 固定高度

-- ===========================================================================
-- 数据展平 — 将嵌套 EncounterStats[speciesID][breedID]=count 转为排序数组
-- ===========================================================================
local function FlattenEncounterStats()
    local flat = {}
    if not GeneDexDB or not GeneDexDB.EncounterStats then return flat end
    for speciesID, breeds in pairs(GeneDexDB.EncounterStats) do
        if type(speciesID) == "number" and type(breeds) == "table" then
            -- 解析物种名和图标（Rematch 优先）
            local speciesName, speciesIcon
            if Rematch and Rematch.petInfo then
                local info = Rematch.petInfo:Fetch(speciesID)
                if info then
                    speciesName = info.speciesName
                    speciesIcon = info.speciesIcon
                end
            end
            if not speciesName then
                speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            end
            if not speciesName then
                speciesName = "ID:" .. tostring(speciesID)
            end
            for breedID, count in pairs(breeds) do
                if type(breedID) == "number" and type(count) == "number" then
                    local breedCode = addonTable.GetBreedCode and addonTable.GetBreedCode(breedID) or tostring(breedID)
                    flat[#flat + 1] = {
                        speciesID   = speciesID,
                        speciesName = speciesName,
                        icon        = speciesIcon,
                        breedID     = breedID,
                        breedCode   = breedCode,
                        count       = count,
                    }
                end
            end
        end
    end
    -- 按物种名排序，同物种按品种代码排序
    table.sort(flat, function(a, b)
        local na = (a.speciesName or ""):lower()
        local nb = (b.speciesName or ""):lower()
        if na ~= nb then return na < nb end
        return (a.breedCode or "") < (b.breedCode or "")
    end)
    return flat
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

    -- 遇敌统计 — Flipper 式 ScrollFrame 表格
    local statsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statsTitle:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -12)
    statsTitle:SetText(GetLocaleString("ENCOUNTER_STATS_TITLE"))

    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("LEFT", statsTitle, "RIGHT", 8, 2);refreshBtn:SetSize(60, 20)
    refreshBtn:SetText("刷新")

    -- ==================================================================
    -- 表头 FontStrings — 固定于 ScrollFrame 上方，像素列偏移对齐数据列
    -- ==================================================================
    local HX, HY = 2, -28
    local hdrName = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrName:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", HX + ENC_COL.NAME, HY)
    hdrName:SetText("|cffffcc00" .. GetLocaleString("SPECIES_NAME_HEADER") .. "|r")

    local hdrBreed = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrBreed:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", HX + ENC_COL.BREED, HY)
    hdrBreed:SetText("|cffffcc00" .. GetLocaleString("BREED_HEADER") .. "|r")

    local hdrCount = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrCount:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", HX + ENC_COL.COUNT, HY)
    hdrCount:SetText("|cffffcc00" .. GetLocaleString("COUNT_HEADER") .. "|r")

    -- ==================================================================
    -- 条纹裁剪容器 — 先创建 = 更低 z-order，不遮挡行文字
    -- ==================================================================
    local stripeClip = CreateFrame("Frame", nil, panel)
    stripeClip:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", -4, -48)
    stripeClip:SetHeight(ENC_SCROLL_HEIGHT)
    stripeClip:SetWidth(380)
    stripeClip:SetClipsChildren(true)

    -- ==================================================================
    -- ScrollFrame — 后创建 = 更高 z-order，使用 Blizzard 模板
    -- ==================================================================
    local scroll = CreateFrame("ScrollFrame", "GenDexBDEncounterScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", -4, -48)
    scroll:SetHeight(ENC_SCROLL_HEIGHT)
    scroll:SetWidth(380)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    content:SetPoint("TOPLEFT")
    content:SetPoint("RIGHT", scroll)

    -- 条纹容器对齐到 ScrollFrame（保持 z-order 不变）
    stripeClip:SetPoint("TOPLEFT", scroll, "TOPLEFT")
    stripeClip:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")

    -- ==================================================================
    -- 对象池引用 — 挂载到 panel 上供方法使用
    -- ==================================================================
    panel.encounterScroll     = scroll
    panel.encounterContent    = content
    panel.encounterStripeClip = stripeClip
    panel.encounterRows       = {}    -- Button 行对象池
    panel.encounterStripes    = {}    -- 条纹帧对象池
    panel.encounterRowY       = {}    -- 行 Y 偏移记录（条纹重定位用）

    -- ==================================================================
    -- 行对象池 — 延迟创建 Button 行，首次创建后跨刷新复用
    -- ==================================================================
    function panel:GetOrCreateEncounterRow(index)
        local r = self.encounterRows[index]
        if r then return r end

        r = CreateFrame("Button", nil, self.encounterContent)
        r:SetHeight(ENC_ROW_HEIGHT)
        r:EnableMouse(true)

        -- 物种图标（18x18）
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", ENC_COL.ICON, 0)

        -- 宠物名称
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", ENC_COL.NAME, 0)
        r.name:SetWidth(ENC_NAME_W)
        r.name:SetJustifyH("LEFT")

        -- 品种代码
        r.breed = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.breed:SetPoint("LEFT", ENC_COL.BREED, 0)
        r.breed:SetWidth(ENC_BREED_W)
        r.breed:SetJustifyH("LEFT")

        -- 遇敌次数（右对齐数值列）
        r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.count:SetPoint("LEFT", ENC_COL.COUNT, 0)
        r.count:SetWidth(ENC_COUNT_W)
        r.count:SetJustifyH("RIGHT")

        self.encounterRows[index] = r
        return r
    end

    -- ==================================================================
    -- 刷新数据行 — 展平→排序→填充 Button 行 + 更新条纹
    -- ==================================================================
    function panel:UpdateEncounterList()
        -- 隐藏所有已有行
        for _, r in pairs(self.encounterRows) do
            r:Hide()
        end
        self.encounterRowY = {}

        local flatData = FlattenEncounterStats()

        if #flatData == 0 then
            -- 空数据：显示单行提示
            local r = self:GetOrCreateEncounterRow(1)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, 0)
            r:SetPoint("RIGHT", 0, 0)
            if r.icon then r.icon:Hide() end
            r.name:SetText(GetLocaleString("ENCOUNTER_NO_DATA"))
            r.name:SetTextColor(0.6, 0.6, 0.6)
            r.breed:SetText("")
            r.count:SetText("")
            r:Show()
            self.encounterContent:SetHeight(ENC_ROW_HEIGHT)
            self.encounterRowY[1] = 0
        else
            local y = 0
            for i, entry in ipairs(flatData) do
                local r = self:GetOrCreateEncounterRow(i)

                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, -y)
                r:SetPoint("RIGHT", 0, 0)

                -- 图标
                if entry.icon then
                    r.icon:SetTexture(entry.icon)
                    r.icon:Show()
                else
                    r.icon:Hide()
                end

                -- 列文本
                r.name:SetText(entry.speciesName)
                r.name:SetTextColor(1, 1, 1)
                r.breed:SetText(entry.breedCode)
                r.breed:SetTextColor(1, 1, 1)
                r.count:SetText(tostring(entry.count))
                r.count:SetTextColor(1, 1, 1)

                -- 存储数据用于后续交互（如 tooltip）
                r.speciesID = entry.speciesID
                r.breedID   = entry.breedID

                r:Show()
                self.encounterRowY[i] = y
                y = y + ENC_ROW_HEIGHT
            end
            self.encounterContent:SetHeight(math.max(y, 1))
        end

        -- 隐藏超出数据量的行
        for i = #flatData + 1, #self.encounterRows do
            self.encounterRows[i]:Hide()
        end

        -- 更新交替条纹背景
        self:UpdateEncounterStripes()
    end

    -- ==================================================================
    -- 交替条纹背景 — 遵循 Flipper 模式：Clip + 滚动钩子纯几何重定位
    -- ==================================================================
    function panel:UpdateEncounterStripes()
        if not self.encounterStripes then self.encounterStripes = {} end
        local encScroll = self.encounterScroll

        local function repositionStripes(offset)
            for i, stripe in ipairs(self.encounterStripes) do
                if self.encounterRowY[i] then
                    stripe:ClearAllPoints()
                    local sy = self.encounterRowY[i] + (offset or 0)
                    stripe:SetPoint("TOPLEFT", encScroll, "TOPLEFT", 0, -sy)
                    stripe:SetPoint("TOPRIGHT", encScroll, "TOPRIGHT", -16, -sy)
                    stripe:SetHeight(ENC_ROW_HEIGHT)
                end
            end
        end

        local numRows = #(self.encounterRowY or {})
        for i = 1, numRows do
            local stripe = self.encounterStripes[i]
            if not stripe then
                stripe = CreateFrame("Frame", nil, self.encounterStripeClip, "BackdropTemplate")
                stripe:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8X8",
                    tile     = true,
                    tileSize = 8,
                })
                self.encounterStripes[i] = stripe
            end
            -- 交替行底色
            stripe:SetBackdropColor(
                i % 2 == 0 and 0.22 or 0.10,
                i % 2 == 0 and 0.22 or 0.10,
                i % 2 == 0 and 0.28 or 0.14
            )
            stripe:Show()
        end
        for i = numRows + 1, #self.encounterStripes do
            self.encounterStripes[i]:Hide()
        end

        repositionStripes(-(encScroll:GetVerticalScroll() or 0))

        -- 首次注册滚动钩子（仅一次）
        if not self._encStripesScrollHooked then
            self._encStripesScrollHooked = true
            local scrollBar = _G["GenDexBDEncounterScrollScrollBar"]
            if scrollBar then
                scrollBar:HookScript("OnValueChanged", function()
                    if panel:IsShown() then
                        repositionStripes(-(encScroll:GetVerticalScroll() or 0))
                    end
                end)
            end
        end
    end

    -- 刷新按钮回调
    refreshBtn:SetScript("OnClick", function()
        panel:UpdateEncounterList()
    end)

    -- 初始加载数据
    panel:UpdateEncounterList()

    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID();Settings.RegisterAddOnCategory(category)
end

function addonTable.ToggleConfigPanel()
    if not categoryID then return end
    Settings.OpenToCategory(categoryID)
end
