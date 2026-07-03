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

-- ========== TAB 常量 ==========
local TAB_GENERAL     = 1
local TAB_BEST_BREEDS = 2
local tabButtons = {};local pageFrames = {}

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

-- ========== 宠物类型名获取 ==========

-- 获取宠物对战类型的本地化名称（人型/小动物/猛兽...）
local function GetPetTypeName(petType)
    if not petType or petType == 0 then return "?" end
    -- WoW 内置全局字符串 BATTLE_PET_NAME_1 ~ BATTLE_PET_NAME_10，已本地化
    return _G["BATTLE_PET_NAME_" .. petType] or ("?" .. tostring(petType))
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

-- ========== 最优品种列表 — Flipper 式 ScrollFrame 表格 ==========

-- 列布局常量（像素偏移 — 表格锚定撑满面板右侧）
local BB_COL = {
    ICON  = 5,                    -- 图标左边缘
    NAME  = 28,                   -- 宠物名称左边缘
    BREED = 280,                  -- 最优品种左边缘
    CAT   = 430,                  -- 宠物类型左边缘
}
local BB_NAME_W  = 248           -- NAME 列像素宽度
local BB_BREED_W = 145           -- BREED 列像素宽度（含 "P/P 攻击型" 长度）
local BB_CAT_W   = 130           -- CAT 列像素宽度（含 "人型/小动物" 长度）
local BB_ROW_HEIGHT = 22

-- ===========================================================================
-- 数据展平 — 将嵌套 BestBreeds[speciesID][breedID] 转为排序数组
-- 分类列显示宠物的战斗类型（人型/小动物/猛兽等），而非品种使用场景
-- ===========================================================================
local function FlattenBestBreeds()
    local flat = {}
    if not GeneDexDB or not GeneDexDB.BestBreeds then return flat end
    for speciesID, breeds in pairs(GeneDexDB.BestBreeds) do
        if type(speciesID) == "number" and type(breeds) == "table" then
            -- 解析物种名、图标、宠物类型（Rematch 优先）
            local speciesName, speciesIcon, petType
            if Rematch and Rematch.petInfo then
                local info = Rematch.petInfo:Fetch(speciesID)
                if info then
                    speciesName = info.speciesName
                    speciesIcon = info.speciesIcon
                    petType = info.petType  -- Rematch 可能包含
                end
            end
            -- 缺失的信息从 C_PetJournal 补齐（包括 petType：第11个返回值）
            if not speciesName or not petType then
                local _, jName, jIcon, _, _, _, _, _, _, _, jPetType = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                if not speciesName then speciesName = jName end
                if not speciesIcon then speciesIcon = jIcon end
                if not petType then petType = jPetType end
            end
            if not speciesName then
                speciesName = "ID:" .. tostring(speciesID)
            end
            local petTypeName = GetPetTypeName(petType)

            for breedID, binfo in pairs(breeds) do
                if type(breedID) == "number" and type(binfo) == "table" then
                    local breedCode = addonTable.GetBreedCode and addonTable.GetBreedCode(breedID) or tostring(breedID)
                    local breedDisplay = addonTable.GetBreedDisplayName and addonTable.GetBreedDisplayName(breedID, breedCode) or breedCode
                    flat[#flat + 1] = {
                        speciesID    = speciesID,
                        speciesName  = speciesName,
                        icon         = speciesIcon,
                        breedID      = breedID,
                        breedCode    = breedCode,
                        breedDisplay = breedDisplay,
                        petTypeName  = petTypeName,
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

-- ========== TAB 切换 ==========
local function SwitchTab(tabIndex)
    for i, btn in ipairs(tabButtons) do
        if i == tabIndex then
            btn.text:SetTextColor(1, 0.84, 0)  -- 金色高亮
        else
            btn.text:SetTextColor(0.5, 0.5, 0.5)  -- 灰色
        end
    end
    for i, page in ipairs(pageFrames) do
        if i == tabIndex then
            page:Show()
        else
            page:Hide()
        end
    end
end

-- ========== 面板创建 ==========
function addonTable.InitConfig()
    if panel then return end
    panel = CreateFrame("Frame", nil, UIParent);panel.name = "GenDexBD"

    -- ========================================================================
    -- Tab 标签栏
    -- ========================================================================
    local tabBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    tabBar:SetPoint("TOPLEFT", 0, -8)
    tabBar:SetPoint("TOPRIGHT", 0, -8)
    tabBar:SetHeight(26)
    tabBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 8,
    })
    tabBar:SetBackdropColor(0.08, 0.08, 0.12, 0.9)

    -- 分割线
    local divider = tabBar:CreateTexture(nil, "OVERLAY")
    divider:SetPoint("BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.35)

    local function CreateTabButton(text, tabIndex, anchorTo, anchorPoint, xOff)
        local btn = CreateFrame("Button", nil, tabBar)
        btn:SetSize(90, 22)
        btn:SetPoint("LEFT", anchorTo, anchorPoint or "RIGHT", xOff or -2, 0)
        btn:RegisterForClicks("LeftButtonUp")
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.text:SetPoint("CENTER")
        btn.text:SetText(text)
        btn:SetScript("OnClick", function() SwitchTab(tabIndex) end)
        return btn
    end

    tabButtons[TAB_GENERAL]     = CreateTabButton(GetLocaleString("TAB_GENERAL"),     TAB_GENERAL,     tabBar, "LEFT", 12)
    tabButtons[TAB_BEST_BREEDS] = CreateTabButton(GetLocaleString("TAB_BEST_BREEDS"), TAB_BEST_BREEDS, tabButtons[TAB_GENERAL])

    -- ========================================================================
    -- Page 1：常规设置（现有内容）
    -- ========================================================================
    local page1 = CreateFrame("Frame", nil, panel)
    page1:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    page1:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -8)
    page1:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)  -- 撑到底部
    pageFrames[TAB_GENERAL] = page1

    local title = page1:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -8);title:SetText(GetLocaleString("CONFIG_TITLE"))

    local prevCB = nil
    for i, opt in ipairs(OPTIONS) do
        if opt[3] == "check" then
            local cb = CreateFrame("CheckButton", nil, page1, "InterfaceOptionsCheckButtonTemplate")
            cb.Text:SetText(GetLocaleString(opt[2]))
            if i == 1 then cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
            else cb:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -2) end
            prevCB = cb
            cb:SetChecked(GeneDexDB and GeneDexDB.Options and GeneDexDB.Options[opt[1]] == true)
            cb:SetScript("OnClick", function(self) GeneDexDB.Options[opt[1]] = self:GetChecked() or false end)
        elseif opt[3] == "slider" then
            local lbl = page1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            lbl:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -8);lbl:SetText(GetLocaleString(opt[2]) .. ":")
            local valText = page1:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            valText:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
            local curVal = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AlertDuration or 5
            valText:SetText(curVal .. " " .. GetLocaleString("SECONDS"))
            local slider = CreateFrame("Slider", nil, page1, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4);slider:SetWidth(200)
            slider:SetMinMaxValues(1, 30);slider:SetValueStep(1)
            slider:SetValue(curVal)
            slider:SetScript("OnValueChanged", function(_, v)
                v = math.floor(v + 0.5)
                GeneDexDB.Options.AlertDuration = v
                valText:SetText(v .. " " .. GetLocaleString("SECONDS"))
            end)
            prevCB = slider
        end
    end

    -- 导出/导入按钮
    local exportBtn = CreateFrame("Button", nil, page1, "UIPanelButtonTemplate")
    exportBtn:SetPoint("TOPLEFT", prevCB, "BOTTOMLEFT", 0, -12);exportBtn:SetSize(120,24)
    exportBtn:SetText(GetLocaleString("EXPORT_BUTTON"))
    exportBtn:SetScript("OnClick", ShowExportDialog)

    local importBtn = CreateFrame("Button", nil, page1, "UIPanelButtonTemplate")
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0);importBtn:SetSize(120,24)
    importBtn:SetText(GetLocaleString("IMPORT_BUTTON"))
    importBtn:SetScript("OnClick", ShowImportDialog)

    -- 遇敌统计 — Flipper 式 ScrollFrame 表格
    local statsTitle = page1:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statsTitle:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -12)
    statsTitle:SetText(GetLocaleString("ENCOUNTER_STATS_TITLE"))

    local refreshBtn = CreateFrame("Button", nil, page1, "UIPanelButtonTemplate")
    refreshBtn:SetPoint("LEFT", statsTitle, "RIGHT", 8, 2);refreshBtn:SetSize(60, 20)
    refreshBtn:SetText("刷新")

    -- ==================================================================
    -- 表头 FontStrings — 固定于 ScrollFrame 上方，像素列偏移对齐数据列
    -- ==================================================================
    local HX, HY = 2, -28
    local hdrName = page1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrName:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", HX + ENC_COL.NAME, HY)
    hdrName:SetText("|cffffcc00" .. GetLocaleString("SPECIES_NAME_HEADER") .. "|r")

    local hdrBreed = page1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrBreed:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", HX + ENC_COL.BREED, HY)
    hdrBreed:SetText("|cffffcc00" .. GetLocaleString("BREED_HEADER") .. "|r")

    local hdrCount = page1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdrCount:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", HX + ENC_COL.COUNT, HY)
    hdrCount:SetText("|cffffcc00" .. GetLocaleString("COUNT_HEADER") .. "|r")

    -- ==================================================================
    -- 条纹裁剪容器 — 先创建 = 更低 z-order，不遮挡行文字
    -- ==================================================================
    local stripeClip = CreateFrame("Frame", nil, page1)
    stripeClip:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", -4, -48)
    stripeClip:SetPoint("BOTTOMRIGHT", page1, "BOTTOMRIGHT", -6, 6)
    stripeClip:SetClipsChildren(true)

    -- ==================================================================
    -- ScrollFrame — 后创建 = 更高 z-order，使用 Blizzard 模板
    -- ==================================================================
    local scroll = CreateFrame("ScrollFrame", "GenDexBDEncounterScroll", page1, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", statsTitle, "BOTTOMLEFT", -4, -48)
    scroll:SetPoint("BOTTOMRIGHT", page1, "BOTTOMRIGHT", -6, 6)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    content:SetPoint("TOPLEFT")
    content:SetPoint("RIGHT", scroll)

    -- 条纹容器对齐到 ScrollFrame（保持 z-order 不变）
    stripeClip:SetPoint("TOPLEFT", scroll, "TOPLEFT")
    stripeClip:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT")

    -- ==================================================================
    -- 对象池引用 — 挂载到 panel 上供方法使用（遇敌统计）
    -- ==================================================================
    panel.encounterScroll     = scroll
    panel.encounterContent    = content
    panel.encounterStripeClip = stripeClip
    panel.encounterRows       = {}    -- Button 行对象池
    panel.encounterStripes    = {}    -- 条纹帧对象池
    panel.encounterRowY       = {}    -- 行 Y 偏移记录（条纹重定位用）

    -- ==================================================================
    -- 遇敌统计 — 行对象池
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
    -- 遇敌统计 — 刷新数据行
    -- ==================================================================
    function panel:UpdateEncounterList()
        for _, r in pairs(self.encounterRows) do
            r:Hide()
        end
        self.encounterRowY = {}

        local flatData = FlattenEncounterStats()

        if #flatData == 0 then
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

                if entry.icon then
                    r.icon:SetTexture(entry.icon)
                    r.icon:Show()
                else
                    r.icon:Hide()
                end

                r.name:SetText(entry.speciesName)
                r.name:SetTextColor(1, 1, 1)
                r.breed:SetText(entry.breedCode)
                r.breed:SetTextColor(1, 1, 1)
                r.count:SetText(tostring(entry.count))
                r.count:SetTextColor(1, 1, 1)

                r.speciesID = entry.speciesID
                r.breedID   = entry.breedID

                r:Show()
                self.encounterRowY[i] = y
                y = y + ENC_ROW_HEIGHT
            end
            self.encounterContent:SetHeight(math.max(y, 1))
        end

        for i = #flatData + 1, #self.encounterRows do
            self.encounterRows[i]:Hide()
        end

        self:UpdateEncounterStripes()
    end

    -- ==================================================================
    -- 遇敌统计 — 交替条纹背景
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

    -- 遇敌统计刷新按钮回调
    refreshBtn:SetScript("OnClick", function()
        panel:UpdateEncounterList()
    end)

    -- ========================================================================
    -- Page 2：最优品种列表 — 表格撑满面板右侧和底部
    -- ========================================================================
    local page2 = CreateFrame("Frame", nil, panel)
    page2:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
    page2:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -8)
    page2:SetPoint("BOTTOM", panel, "BOTTOM", 0, 0)  -- 撑到底部
    pageFrames[TAB_BEST_BREEDS] = page2

    local bbTitle = page2:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    bbTitle:SetPoint("TOPLEFT", 16, -8)
    bbTitle:SetText(GetLocaleString("BEST_BREED_LIST_TITLE"))

    local bbRefreshBtn = CreateFrame("Button", nil, page2, "UIPanelButtonTemplate")
    bbRefreshBtn:SetPoint("LEFT", bbTitle, "RIGHT", 8, 2);bbRefreshBtn:SetSize(60, 20)
    bbRefreshBtn:SetText("刷新")

    -- 表头（列偏移与第一页表格一致的风格，但用更宽的 BB_COL）
    local bbHdrName = page2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bbHdrName:SetPoint("TOPLEFT", bbTitle, "BOTTOMLEFT", HX + BB_COL.NAME, HY)
    bbHdrName:SetText("|cffffcc00" .. GetLocaleString("SPECIES_NAME_HEADER") .. "|r")

    local bbHdrBreed = page2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bbHdrBreed:SetPoint("TOPLEFT", bbTitle, "BOTTOMLEFT", HX + BB_COL.BREED, HY)
    bbHdrBreed:SetText("|cffffcc00" .. GetLocaleString("BREED_HEADER") .. "|r")

    local bbHdrCat = page2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bbHdrCat:SetPoint("TOPLEFT", bbTitle, "BOTTOMLEFT", HX + BB_COL.CAT, HY)
    bbHdrCat:SetText("|cffffcc00" .. GetLocaleString("CATEGORY_HEADER") .. "|r")

    -- 条纹裁剪容器 — 撑满 ScrollFrame
    local bbStripeClip = CreateFrame("Frame", nil, page2)
    bbStripeClip:SetPoint("TOPLEFT", bbTitle, "BOTTOMLEFT", -4, -48)
    bbStripeClip:SetPoint("BOTTOMRIGHT", page2, "BOTTOMRIGHT", -6, 6)
    bbStripeClip:SetClipsChildren(true)

    -- ScrollFrame — 撑满右侧和底部
    local bbScroll = CreateFrame("ScrollFrame", "GenDexBDBestBreedScroll", page2, "UIPanelScrollFrameTemplate")
    bbScroll:SetPoint("TOPLEFT", bbTitle, "BOTTOMLEFT", -4, -48)
    bbScroll:SetPoint("BOTTOMRIGHT", page2, "BOTTOMRIGHT", -6, 6)

    local bbContent = CreateFrame("Frame", nil, bbScroll)
    bbContent:SetSize(1, 1)
    bbScroll:SetScrollChild(bbContent)
    bbContent:SetPoint("TOPLEFT")
    bbContent:SetPoint("RIGHT", bbScroll)

    bbStripeClip:SetPoint("TOPLEFT", bbScroll, "TOPLEFT")
    bbStripeClip:SetPoint("BOTTOMRIGHT", bbScroll, "BOTTOMRIGHT")

    -- 对象池引用
    panel.bbScroll     = bbScroll
    panel.bbContent    = bbContent
    panel.bbStripeClip = bbStripeClip
    panel.bbRows       = {}
    panel.bbStripes    = {}
    panel.bbRowY       = {}

    -- ==================================================================
    -- 最优品种 — 行对象池
    -- ==================================================================
    function panel:GetOrCreateBBRow(index)
        local r = self.bbRows[index]
        if r then return r end

        r = CreateFrame("Button", nil, self.bbContent)
        r:SetHeight(BB_ROW_HEIGHT)
        r:EnableMouse(true)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", BB_COL.ICON, 0)

        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", BB_COL.NAME, 0)
        r.name:SetWidth(BB_NAME_W)
        r.name:SetJustifyH("LEFT")

        r.breed = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.breed:SetPoint("LEFT", BB_COL.BREED, 0)
        r.breed:SetWidth(BB_BREED_W)
        r.breed:SetJustifyH("LEFT")

        r.category = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.category:SetPoint("LEFT", BB_COL.CAT, 0)
        r.category:SetWidth(BB_CAT_W)
        r.category:SetJustifyH("LEFT")

        self.bbRows[index] = r
        return r
    end

    -- ==================================================================
    -- 最优品种 — 刷新数据行
    -- ==================================================================
    function panel:UpdateBBList()
        for _, r in pairs(self.bbRows) do
            r:Hide()
        end
        self.bbRowY = {}

        local flatData = FlattenBestBreeds()

        if #flatData == 0 then
            local r = self:GetOrCreateBBRow(1)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, 0)
            r:SetPoint("RIGHT", 0, 0)
            if r.icon then r.icon:Hide() end
            r.name:SetText(GetLocaleString("BEST_BREED_NO_DATA"))
            r.name:SetTextColor(0.6, 0.6, 0.6)
            r.breed:SetText("")
            r.category:SetText("")
            r:Show()
            self.bbContent:SetHeight(BB_ROW_HEIGHT)
            self.bbRowY[1] = 0
        else
            local y = 0
            for i, entry in ipairs(flatData) do
                local r = self:GetOrCreateBBRow(i)

                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, -y)
                r:SetPoint("RIGHT", 0, 0)

                if entry.icon then
                    r.icon:SetTexture(entry.icon)
                    r.icon:Show()
                else
                    r.icon:Hide()
                end

                r.name:SetText(entry.speciesName)
                r.name:SetTextColor(1, 1, 1)
                r.breed:SetText(entry.breedDisplay)
                r.breed:SetTextColor(1, 0.84, 0)  -- 金色
                r.category:SetText(entry.petTypeName)
                r.category:SetTextColor(1, 1, 1)

                r.speciesID = entry.speciesID
                r.breedID   = entry.breedID

                r:Show()
                self.bbRowY[i] = y
                y = y + BB_ROW_HEIGHT
            end
            self.bbContent:SetHeight(math.max(y, 1))
        end

        for i = #flatData + 1, #self.bbRows do
            self.bbRows[i]:Hide()
        end

        self:UpdateBBStripes()
    end

    -- ==================================================================
    -- 最优品种 — 交替条纹背景
    -- ==================================================================
    function panel:UpdateBBStripes()
        if not self.bbStripes then self.bbStripes = {} end
        local bScroll = self.bbScroll

        local function repositionStripes(offset)
            for i, stripe in ipairs(self.bbStripes) do
                if self.bbRowY[i] then
                    stripe:ClearAllPoints()
                    local sy = self.bbRowY[i] + (offset or 0)
                    stripe:SetPoint("TOPLEFT", bScroll, "TOPLEFT", 0, -sy)
                    stripe:SetPoint("TOPRIGHT", bScroll, "TOPRIGHT", -16, -sy)
                    stripe:SetHeight(BB_ROW_HEIGHT)
                end
            end
        end

        local numRows = #(self.bbRowY or {})
        for i = 1, numRows do
            local stripe = self.bbStripes[i]
            if not stripe then
                stripe = CreateFrame("Frame", nil, self.bbStripeClip, "BackdropTemplate")
                stripe:SetBackdrop({
                    bgFile   = "Interface\\Buttons\\WHITE8X8",
                    tile     = true,
                    tileSize = 8,
                })
                self.bbStripes[i] = stripe
            end
            stripe:SetBackdropColor(
                i % 2 == 0 and 0.22 or 0.10,
                i % 2 == 0 and 0.22 or 0.10,
                i % 2 == 0 and 0.28 or 0.14
            )
            stripe:Show()
        end
        for i = numRows + 1, #self.bbStripes do
            self.bbStripes[i]:Hide()
        end

        repositionStripes(-(bScroll:GetVerticalScroll() or 0))

        if not self._bbStripesScrollHooked then
            self._bbStripesScrollHooked = true
            local scrollBar = _G["GenDexBDBestBreedScrollScrollBar"]
            if scrollBar then
                scrollBar:HookScript("OnValueChanged", function()
                    if panel:IsShown() then
                        repositionStripes(-(bScroll:GetVerticalScroll() or 0))
                    end
                end)
            end
        end
    end

    -- 最优品种刷新按钮回调
    bbRefreshBtn:SetScript("OnClick", function()
        panel:UpdateBBList()
    end)

    -- ========================================================================
    -- 初始数据加载 & 默认显示第一页
    -- ========================================================================
    panel:UpdateEncounterList()
    panel:UpdateBBList()
    SwitchTab(TAB_GENERAL)

    -- ========================================================================
    -- 注册到 Blizzard 设置面板
    -- ========================================================================
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    categoryID = category:GetID();Settings.RegisterAddOnCategory(category)
end

function addonTable.ToggleConfigPanel()
    if not categoryID then return end
    Settings.OpenToCategory(categoryID)
end
