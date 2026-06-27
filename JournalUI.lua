-- GenDexBD JournalUI.lua
-- 加载顺序：第6个（依赖 Core/DB、BreedMath、Locales、BreedData）
-- 列表页：PET_JOURNAL_LIST_UPDATE 事件扫描按钮追加品种代码
-- 右键菜单：最优属性管理

local addonName, addonTable = ...

local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName

local time = time
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local strlower = string.lower
local strfind = string.find

-- ============================================================================
-- 最优品种管理 API
-- ============================================================================

function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID then return end
    if not GeneDexDB then return end
    if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds) ~= "table" then GeneDexDB.BestBreeds = {} end
    if not GeneDexDB.BestBreeds[speciesID] then GeneDexDB.BestBreeds[speciesID] = {} end
    GeneDexDB.BestBreeds[speciesID][breedID] = { category = category or "custom", note = note or "", addedAt = time() }
end

function addonTable.RemoveBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return end
    local bb = GeneDexDB and GeneDexDB.BestBreeds
    if not bb or type(bb) ~= "table" then return end
    local sd = bb[speciesID]
    if not sd or type(sd) ~= "table" then return end
    sd[breedID] = nil
    if not next(sd) then bb[speciesID] = nil end
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
-- API 自动探测
-- ============================================================================

local petInfoFields = nil

local function DetectPetInfoFields()
    if petInfoFields then return petInfoFields[1], petInfoFields[2], petInfoFields[3] end
    local sample = C_PetJournal.GetPetInfoBySpeciesID(39) or C_PetJournal.GetPetInfoBySpeciesID(1)
    if not sample then return nil, nil, nil end
    local allKeys = {}
    for k in pairs(sample) do allKeys[#allKeys + 1] = k end
    local function fk(patterns)
        for _, key in ipairs(allKeys) do
            local lk = strlower(key)
            for _, pat in ipairs(patterns) do if strfind(lk, pat, 1, true) then return key end end
        end
    end
    local hk = fk({"health", "hp"})
    local pk = fk({"power", "attack", "atk"})
    local sk = fk({"speed", "spd"})
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
-- 品种计算
-- ============================================================================

local function CalcBreed(speciesID, level, quality, health, power, speed)
    if not health or not power or not speed then return nil end
    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    local bh, bp, bs = ExtractBaseStats(petInfo)
    if not bh or not bp or not bs then return nil end
    local calcQuality = quality or 4
    if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then
        if not quality or calcQuality < 4 then calcQuality = 4 end
    end
    return CalculateBreedFromStats(health, power, speed, bh, bp, bs, level, calcQuality)
end

-- ============================================================================
-- 列表按钮品种标注 — PET_JOURNAL_LIST_UPDATE 扫描模式
-- ============================================================================

--- 从 ScrollFrame 或 ScrollBox 中获取所有可见的宠物条目按钮
local function FindPetListButtons()
    local btns = {}

    -- 方法1：旧式 HybridScrollFrame (PetJournalListScrollFrame)
    if PetJournalListScrollFrame then
        if PetJournalListScrollFrame.buttons then
            for _, b in ipairs(PetJournalListScrollFrame.buttons) do
                if b and b:IsVisible() and b.petID then btns[#btns + 1] = b end
            end
        end
        if #btns > 0 then return btns end
    end

    -- 方法2：12.0 新式 ScrollBox — 遍历 ScrollFrame 的子 Frame
    local scrollFrame = PetJournalListScrollFrame or PetJournal
    if scrollFrame then
        -- 深度遍历子 Frame 找有 petID 属性的可见按钮
        local function scan(parent, depth)
            if depth > 4 then return end
            local children = { parent:GetChildren() }
            for _, child in ipairs(children) do
                if child:IsVisible() and child.petID then
                    btns[#btns + 1] = child
                end
                scan(child, depth + 1)
            end
        end
        scan(scrollFrame, 0)
        if #btns > 0 then return btns end
    end

    -- 方法3：全局命名表逐个查（传统兼容，最先匹配到就返回）
    for i = 1, 50 do
        local b = _G["PetJournalListScrollFrameButton" .. i]
        if not b then break end
        if b:IsVisible() and b.petID then btns[#btns + 1] = b end
    end

    return btns
end

--- 为单个列表按钮追加品种标注
local function LabelButton(button)
    if not button or not button.petID then return end
    if not button._genedexLabel then
        -- 创建一个 FontString 挂在按钮上
        local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        fs:SetJustifyH("RIGHT")
        button._genedexLabel = fs
    end

    local label = button._genedexLabel
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        label:Hide()
        return
    end

    local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
        C_PetJournal.GetPetInfoByPetID(button.petID)
    if not speciesID then label:Hide(); return end

    local breedID = CalcBreed(speciesID, level, quality, health, power, speed)
    if not breedID then label:Hide(); return end

    local code = GetBreedCode(breedID)
    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    label:SetText(isBest and ("★" .. code) or code)
    label:SetTextColor(isBest and 1 or 0.6, isBest and 0.84 or 0.6, 0.6)
    label:Show()
end

--- 刷新所有列表按钮的品种标注
local function RefreshAllButtons()
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        return
    end
    local btns = FindPetListButtons()
    for _, b in ipairs(btns) do
        pcall(LabelButton, b)  -- 单个按钮失败不阻塞其他
    end
end

-- ============================================================================
-- 右键菜单：最优属性管理
-- ============================================================================

local CATEGORY_LIST = { "pvp", "pve", "collection", "custom" }
local menuFrame = nil

local function EnsureMenu()
    if menuFrame then return end
    menuFrame = CreateFrame("Frame", "GeneDexBDMenu", UIParent, "UIDropDownMenuTemplate")
end

local function ShowBestBreedMenu(button, petID, speciesID, breedID)
    if not speciesID or not breedID then return end
    EnsureMenu()

    local isBest = addonTable.IsBestBreed(speciesID, breedID)
    local code = GetBreedCode(breedID) or "?"
    local name = GetBreedDisplayName(breedID, code)

    UIDropDownMenu_Initialize(menuFrame, function(_, level)
        local info = UIDropDownMenu_CreateInfo()

        if level == 1 then
            info.text = name
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, 1)

            if isBest then
                local bi = addonTable.GetBestBreedInfo(speciesID, breedID)
                if bi then
                    info.isTitle = true
                    info.text = "已标记: " .. (bi.category or "custom")
                    UIDropDownMenu_AddButton(info, 1)
                    if bi.note and bi.note ~= "" then
                        info.text = "备注: " .. bi.note
                        UIDropDownMenu_AddButton(info, 1)
                    end
                end
                info.isTitle = false
                info.text = "取消最优品种"
                info.notCheckable = true
                info.func = function()
                    addonTable.RemoveBestBreed(speciesID, breedID)
                    RefreshAllButtons()
                end
                UIDropDownMenu_AddButton(info, 1)
            else
                info.isTitle = false
                info.text = "设为最优品种"
                info.notCheckable = true
                info.hasArrow = true
                info.menuList = "GENEDEX_CATS"
                UIDropDownMenu_AddButton(info, 1)
            end
        elseif level == 2 then
            for _, cat in ipairs(CATEGORY_LIST) do
                local catName = addonTable.GetBestBreedCategoryName and addonTable.GetBestBreedCategoryName(cat) or cat
                info.text = catName
                info.notCheckable = true
                info.func = function()
                    addonTable.SetBestBreed(speciesID, breedID, cat, "")
                    RefreshAllButtons()
                end
                UIDropDownMenu_AddButton(info, 2)
            end
        end
    end)

    ToggleDropDownMenu(1, nil, menuFrame, button, 0, 0)
end

-- ============================================================================
-- 按钮右键 Hook
-- ============================================================================

local function HookRightClick(button)
    if button._genedexRightHooked then return end
    button._genedexRightHooked = true

    local petID = button.petID
    button:HookScript("OnClick", function(self, btnName)
        if btnName ~= "RightButton" then return end
        local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
            C_PetJournal.GetPetInfoByPetID(petID)
        if not speciesID then return end
        local breedID = CalcBreed(speciesID, level, quality, health, power, speed)
        if not breedID then return end
        ShowBestBreedMenu(self, petID, speciesID, breedID)
    end)
end

-- ============================================================================
-- PET_JOURNAL_LIST_UPDATE 事件处理
-- ============================================================================

local eventFrame = nil

local function OnJournalUpdate()
    RefreshAllButtons()
    -- 给新出现的按钮加右键 hook
    local btns = FindPetListButtons()
    for _, b in ipairs(btns) do
        if b and b.petID then HookRightClick(b) end
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function addonTable.InitJournalUI()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PET_JOURNAL_LIST_UPDATE" then
            OnJournalUpdate()
        end
    end)

    -- 也注册 Blizzard_Collections 加载时的刷新
    local waiter = CreateFrame("Frame")
    waiter:RegisterEvent("ADDON_LOADED")
    waiter:SetScript("OnEvent", function(_, _, addon)
        if addon == "Blizzard_Collections" then
            OnJournalUpdate()
            waiter:UnregisterEvent("ADDON_LOADED")
        end
    end)

    print("|cff00ff00[GenDexBD]|r JournalUI 已初始化（PET_JOURNAL_LIST_UPDATE 模式）")
end
