-- GenDexBD JournalUI.lua
-- 宠物手册集成：详情品种显示、最优属性管理界面
-- 加载顺序：第6个（依赖 Core/DB、BreedMath、Locales、BreedData）
--
-- 注入策略：Hook PetJournal:Show，PetJournal 可见时注入 UI
-- Rematch 接管时会 Hide PetJournal，我们的 UI 随之消失，不冲突

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName
local GetBestBreedCategoryName = addonTable.GetBestBreedCategoryName
local GetLocaleString = addonTable.GetLocaleString

local time = time
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local tostring = tostring
local strlower = string.lower
local strfind = string.find
local tconcat = table.concat

-- ============================================================================
-- API 字段自动探测（C_PetJournal.GetPetInfoBySpeciesID）
-- ============================================================================

local petInfoFields = nil

local function DetectPetInfoFields()
    if petInfoFields then
        return petInfoFields[1], petInfoFields[2], petInfoFields[3]
    end
    local sample = C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1)
    if not sample then return nil, nil, nil end

    local allKeys = {}
    for k in pairs(sample) do allKeys[#allKeys + 1] = k end

    local function findKey(patterns)
        for _, key in ipairs(allKeys) do
            local lk = strlower(key)
            for _, pat in ipairs(patterns) do
                if strfind(lk, pat, 1, true) then return key end
            end
        end
        return nil
    end

    local hk = findKey({"health", "hp"})
    local pk = findKey({"power", "attack", "atk"})
    local sk = findKey({"speed", "spd"})
    petInfoFields = { hk, pk, sk }
    return hk, pk, sk
end

local function ExtractBaseStats(petInfo)
    if not petInfo then return nil, nil, nil end
    local hk, pk, sk = DetectPetInfoFields()
    if not hk or not pk or not sk then return nil, nil, nil end
    return petInfo[hk], petInfo[pk], petInfo[sk]
end

-- ============================================================================
-- 品种缓存
-- ============================================================================

local breedCache = {}

local function GetCachedBreed(speciesID, petID, level, quality,
                               health, power, speed,
                               baseHealth, basePower, baseSpeed)
    local key = tostring(speciesID) .. "_" .. tostring(petID)
    if breedCache[key] ~= nil then return breedCache[key] end

    if not health or not power or not speed or
       not baseHealth or not basePower or not baseSpeed then
        breedCache[key] = nil
        return nil
    end

    local calcQuality = quality or 4
    if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then
        if not quality or calcQuality < 4 then calcQuality = 4 end
    end

    local breedID = CalculateBreedFromStats(
        health, power, speed,
        baseHealth, basePower, baseSpeed,
        level, calcQuality
    )
    breedCache[key] = breedID
    return breedID
end

local function InvalidateBreedCache(speciesID)
    local prefix = tostring(speciesID) .. "_"
    for key in pairs(breedCache) do
        if strfind(key, prefix, 1, true) == 1 then
            breedCache[key] = nil
        end
    end
end

-- ============================================================================
-- 公开 API：最优品种管理
-- ============================================================================

function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID then return end
    local db = GeneDexDB
    if not db then return end
    if not db.BestBreeds or type(db.BestBreeds) ~= "table" then
        db.BestBreeds = {}
    end
    if not db.BestBreeds[speciesID] then
        db.BestBreeds[speciesID] = {}
    end
    db.BestBreeds[speciesID][breedID] = {
        category = category or "custom",
        note = note or "",
        addedAt = time(),
    }
    InvalidateBreedCache(speciesID)
end

function addonTable.RemoveBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return end
    local db = GeneDexDB
    if not db then return end
    local bestBreeds = db.BestBreeds
    if not bestBreeds or type(bestBreeds) ~= "table" then return end
    local sd = bestBreeds[speciesID]
    if not sd or type(sd) ~= "table" then return end
    sd[breedID] = nil
    if not next(sd) then bestBreeds[speciesID] = nil end
    InvalidateBreedCache(speciesID)
end

function addonTable.IsBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return false end
    local bb = GeneDexDB and GeneDexDB.BestBreeds
    if not bb or type(bb) ~= "table" then return false end
    local sd = bb[speciesID]
    if not sd or type(sd) ~= "table" then return false end
    return sd[breedID] ~= nil
end

function addonTable.GetBestBreedInfo(speciesID, breedID)
    if not speciesID or not breedID then return nil end
    local bb = GeneDexDB and GeneDexDB.BestBreeds
    if not bb or type(bb) ~= "table" then return nil end
    local sd = bb[speciesID]
    if not sd or type(sd) ~= "table" then return nil end
    local bd = sd[breedID]
    return (bd and type(bd) == "table") and bd or nil
end

function addonTable.GetAllBestBreeds(speciesID)
    if not speciesID then return {} end
    local bb = GeneDexDB and GeneDexDB.BestBreeds
    if not bb or type(bb) ~= "table" then return {} end
    local sd = bb[speciesID]
    return (sd and type(sd) == "table") and sd or {}
end

-- ============================================================================
-- PetJournal UI 注入
-- ============================================================================

-- 已注入标记
local journalInjected = false
-- 选择监听帧
local journalWatcherFrame = nil

-- 子控件引用
local detailBreedText = nil   -- "品种: P/P 攻击型" 文本行
local bestBreedFrame = nil    -- 最优属性管理区容器
local categoryDropdown = nil  -- 分类下拉
local noteEditBox = nil       -- 备注输入框
local actionButton = nil      -- 设为/取消按钮
local markedInfoLine = nil    -- 已标记信息行

-- 当前上下文
local currentSpeciesID = nil
local currentBreedID = nil

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 查找 PetCard（用于锚定品种行）
local function FindPetCard()
    if PetJournal then
        for _, child in ipairs({ PetJournal:GetChildren() }) do
            local cn = child:GetName() or ""
            if strfind(cn, "Card") then return child end
        end
    end
    -- 回退：全局查找
    for _, name in ipairs({"PetJournalPetCard", "PetJournalPetCardFrame"}) do
        if _G[name] then return _G[name] end
    end
    return nil
end

--- 构建已标记信息文本
local function BuildMarkedInfoText(speciesID)
    local allBreeds = addonTable.GetAllBestBreeds(speciesID)
    if not next(allBreeds) then return nil end

    local parts = {}
    for breedID, data in pairs(allBreeds) do
        if type(data) == "table" then
            local code = GetBreedCode(breedID) or "?"
            local cat = GetBestBreedCategoryName(data.category or "custom")
            parts[#parts + 1] = code .. "(" .. cat .. ")"
        end
    end
    if #parts == 0 then return nil end

    local fmt = GetLocaleString("ALREADY_MARKED")
    return fmt:format(tconcat(parts, ", "))
end

-- ============================================================================
-- 详情品种行
-- ============================================================================

local function RefreshDetailBreedLine()
    if not detailBreedText then return end

    local sid, bid = currentSpeciesID, currentBreedID
    if not sid or not bid then
        detailBreedText:Hide()
        return
    end

    local breedCode = GetBreedCode(bid) or "?"
    local breedName = GetBreedDisplayName(bid, breedCode)
    local isBest = addonTable.IsBestBreed(sid, bid)

    local text
    if isBest then
        local bi = addonTable.GetBestBreedInfo(sid, bid)
        local catName = bi and GetBestBreedCategoryName(bi.category or "custom") or ""
        local tf = GetLocaleString("BREED_TARGET_FORMAT")
        text = tf:format(breedCode, breedName, catName)
        detailBreedText:SetTextColor(1, 0.84, 0)
    else
        local f = GetLocaleString("BREED_FORMAT")
        text = f:format(breedCode, breedName)
        detailBreedText:SetTextColor(1, 1, 1)
    end

    detailBreedText:SetText(text)
    detailBreedText:Show()
end

local function EnsureDetailBreedLine()
    if detailBreedText then return end

    local parentFrame = PetJournal
    if not parentFrame then return end

    local petCard = FindPetCard()

    detailBreedText = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if petCard then
        detailBreedText:SetPoint("BOTTOMLEFT", petCard, "TOPLEFT", 10, 4)
        detailBreedText:SetPoint("RIGHT", petCard, "RIGHT", -10, 0)
    else
        -- 找不到 PetCard，挂在一个保守位置
        detailBreedText:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 20, -80)
    end
    detailBreedText:SetJustifyH("LEFT")
    detailBreedText:Hide()
end

-- ============================================================================
-- 最优属性管理区
-- ============================================================================

local CATEGORY_KEYS = { "pvp", "pve", "collection", "custom" }

local function CategoryDropDown_Initialize(self, level)
    for _, key in ipairs(CATEGORY_KEYS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = GetBestBreedCategoryName(key)
        info.value = key
        info.func = function(btn)
            self.selectedKey = btn.value
            UIDropDownMenu_SetText(self, btn:GetText())
            CloseDropDownMenus()
        end
        info.checked = (self.selectedKey == key)
        UIDropDownMenu_AddButton(info, level)
    end
end

local function OnActionButtonClick()
    local sid, bid = currentSpeciesID, currentBreedID
    if not sid or not bid then return end

    if addonTable.IsBestBreed(sid, bid) then
        addonTable.RemoveBestBreed(sid, bid)
    else
        local cat = "custom"
        if categoryDropdown and categoryDropdown.selectedKey then
            cat = categoryDropdown.selectedKey
        end
        local note = ""
        if noteEditBox then
            note = noteEditBox:GetText() or ""
        end
        addonTable.SetBestBreed(sid, bid, cat, note)
    end

    RefreshBestBreedUI()
    RefreshDetailBreedLine()
end

local function RefreshBestBreedUI()
    if not bestBreedFrame then return end

    local sid, bid = currentSpeciesID, currentBreedID
    if not sid or not bid then
        bestBreedFrame:Hide()
        return
    end

    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        bestBreedFrame:Hide()
        return
    end

    bestBreedFrame:Show()

    local isBest = addonTable.IsBestBreed(sid, bid)
    local bi = addonTable.GetBestBreedInfo(sid, bid)

    if actionButton then
        if isBest and bi then
            actionButton:SetText(GetLocaleString("REMOVE_BEST_BREED"))
        else
            actionButton:SetText(GetLocaleString("SET_BEST_BREED"))
        end
    end

    if categoryDropdown then
        local selKey = (isBest and bi and bi.category) or "custom"
        categoryDropdown.selectedKey = selKey
        UIDropDownMenu_SetText(categoryDropdown, GetBestBreedCategoryName(selKey))
    end

    if noteEditBox then
        noteEditBox:SetText((isBest and bi and bi.note) or "")
    end

    if markedInfoLine then
        local txt = BuildMarkedInfoText(sid)
        if txt then
            markedInfoLine:SetText(txt)
            markedInfoLine:Show()
        else
            markedInfoLine:Hide()
        end
    end
end

local function EnsureBestBreedUI()
    if bestBreedFrame then return end

    local parentFrame = PetJournal
    if not parentFrame then return end

    bestBreedFrame = CreateFrame("Frame", nil, parentFrame)
    bestBreedFrame:SetSize(280, 150)
    bestBreedFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 20, -110)
    bestBreedFrame:Hide()

    -- 标题
    local title = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", bestBreedFrame, "TOPLEFT", 0, 0)
    title:SetText(GetLocaleString("BEST_BREED_SECTION"))
    title:SetTextColor(1, 0.84, 0)

    -- 分类标签 + 下拉
    local catLabel = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    catLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    catLabel:SetText(GetLocaleString("CATEGORY_LABEL") .. ":")

    categoryDropdown = CreateFrame("Frame", "GeneDexBDCatDrop", bestBreedFrame, "UIDropDownMenuTemplate")
    categoryDropdown:SetPoint("LEFT", catLabel, "RIGHT", 8, 0)
    categoryDropdown.selectedKey = "custom"
    UIDropDownMenu_Initialize(categoryDropdown, CategoryDropDown_Initialize)
    UIDropDownMenu_SetWidth(categoryDropdown, 120)
    UIDropDownMenu_SetText(categoryDropdown, GetBestBreedCategoryName("custom"))

    -- 备注标签 + 输入框
    local noteLabel = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    noteLabel:SetPoint("TOPLEFT", catLabel, "BOTTOMLEFT", 0, -8)
    noteLabel:SetText(GetLocaleString("NOTE_LABEL_UI") .. ":")

    noteEditBox = CreateFrame("EditBox", nil, bestBreedFrame, "InputBoxTemplate")
    noteEditBox:SetPoint("LEFT", noteLabel, "RIGHT", 8, 0)
    noteEditBox:SetPoint("RIGHT", bestBreedFrame, "RIGHT", -4, 0)
    noteEditBox:SetHeight(24)
    noteEditBox:SetAutoFocus(false)
    noteEditBox:SetMaxLetters(64)
    noteEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- 按钮
    actionButton = CreateFrame("Button", nil, bestBreedFrame, "UIPanelButtonTemplate")
    actionButton:SetPoint("TOPLEFT", noteEditBox, "BOTTOMLEFT", 0, -8)
    actionButton:SetSize(160, 24)
    actionButton:SetText(GetLocaleString("SET_BEST_BREED"))
    actionButton:SetScript("OnClick", OnActionButtonClick)

    -- 已标记信息行
    markedInfoLine = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    markedInfoLine:SetPoint("TOPLEFT", actionButton, "BOTTOMLEFT", 0, -6)
    markedInfoLine:SetPoint("RIGHT", bestBreedFrame, "RIGHT", 0, 0)
    markedInfoLine:SetJustifyH("LEFT")
    markedInfoLine:SetTextColor(0.6, 0.6, 0.6)
    markedInfoLine:Hide()
end

-- ============================================================================
-- 更新详情视图
-- ============================================================================

local function UpdateDetailView()
    if not PetJournal or not PetJournal:IsShown() then return end

    local sid = C_PetJournal.GetSelectedSpeciesID()
    local pid = C_PetJournal.GetSelectedPetID()

    if not sid or not pid then
        currentSpeciesID = nil
        currentBreedID = nil
        if detailBreedText then detailBreedText:Hide() end
        if bestBreedFrame then bestBreedFrame:Hide() end
        return
    end

    local _, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
        C_PetJournal.GetPetInfoByPetID(pid)

    if not level then
        currentSpeciesID, currentBreedID = nil, nil
        return
    end

    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(sid)
    local bh, bp, bs = ExtractBaseStats(petInfo)

    local breedID = GetCachedBreed(sid, pid, level, quality,
                                    health, power, speed, bh, bp, bs)

    currentSpeciesID = sid
    currentBreedID = breedID

    RefreshDetailBreedLine()
    RefreshBestBreedUI()
end

-- ============================================================================
-- 注入入口：Hook PetJournal:Show
-- ============================================================================

--- 执行首次注入
local function InjectIntoJournal()
    if journalInjected then return end
    if not PetJournal or not PetJournal:IsShown() then return end

    journalInjected = true
    print("|cff00ff00[GenDexBD]|r PetJournal 已打开，注入品种UI...")

    EnsureDetailBreedLine()
    EnsureBestBreedUI()
    UpdateDetailView()

    -- 创建选择变化监听
    if not journalWatcherFrame then
        journalWatcherFrame = CreateFrame("Frame")
        journalWatcherFrame.tick = 0
        journalWatcherFrame:SetScript("OnUpdate", function(self, elapsed)
            self.tick = self.tick + elapsed
            if self.tick < 0.5 then return end
            self.tick = 0
            if PetJournal and PetJournal:IsShown() then
                local sid = C_PetJournal.GetSelectedSpeciesID()
                if sid ~= currentSpeciesID then
                    UpdateDetailView()
                end
            end
        end)
    end
end

--- 安全 Hook PetJournal:Show。
--- PetJournal 是 Blizzard_Collections 的子 Frame，该模块按需加载。
--- 参考 Rematch 的做法：检查 C_AddOns.IsAddOnLoaded 然后监听 ADDON_LOADED。
local function TryHookPetJournal()
    if not PetJournal then
        return false
    end
    hooksecurefunc(PetJournal, "Show", InjectIntoJournal)
    hooksecurefunc(PetJournal, "Show", UpdateDetailView)
    print("|cff00ff00[GenDexBD]|r 已 Hook PetJournal:Show")
    return true
end

-- ============================================================================
-- 初始化（参考 Rematch journal.lua 第15-26行）
-- ============================================================================

function addonTable.InitJournalUI()
    -- 检查 Blizzard_Collections 是否已加载
    if C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
        TryHookPetJournal()
        if PetJournal and PetJournal:IsShown() then
            InjectIntoJournal()
        end
    else
        -- 注册 ADDON_LOADED 等待 Blizzard_Collections 加载
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(_, _, addon)
            if addon == "Blizzard_Collections" then
                TryHookPetJournal()
                waiter:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
end
