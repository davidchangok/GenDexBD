-- GenDexBD JournalUI.lua
-- 宠物手册集成：轻量嵌入暴雪已有 UI 元素
-- 参考 BattlePetBreedID 的做法，不创建独立 Frame
-- 加载顺序：第6个

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName

local time = time
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local tostring = tostring
local strlower = string.lower
local strfind = string.find

-- ============================================================================
-- 公开 API：最优品种管理（被 Tooltip / 战斗模块调用）
-- ============================================================================

function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID then return end
    if not GeneDexDB then return end
    if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds) ~= "table" then
        GeneDexDB.BestBreeds = {}
    end
    if not GeneDexDB.BestBreeds[speciesID] then
        GeneDexDB.BestBreeds[speciesID] = {}
    end
    GeneDexDB.BestBreeds[speciesID][breedID] = {
        category = category or "custom",
        note = note or "",
        addedAt = time(),
    }
end

function addonTable.RemoveBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return end
    local bestBreeds = GeneDexDB and GeneDexDB.BestBreeds
    if not bestBreeds or type(bestBreeds) ~= "table" then return end
    local sd = bestBreeds[speciesID]
    if not sd or type(sd) ~= "table" then return end
    sd[breedID] = nil
    if not next(sd) then bestBreeds[speciesID] = nil end
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
-- API 字段自动探测
-- ============================================================================

local petInfoFields = nil

local function DetectPetInfoFields()
    if petInfoFields then return petInfoFields[1], petInfoFields[2], petInfoFields[3] end
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
-- 品种推算（内联缓存版本）
-- ============================================================================

local breedCache = {}

local function GetBreed(petID, speciesID, level, quality, health, power, speed)
    local key = "p" .. tostring(petID)
    if breedCache[key] ~= nil then return breedCache[key] end

    if not health or not power or not speed then
        breedCache[key] = nil
        return nil
    end

    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    local bh, bp, bs = ExtractBaseStats(petInfo)
    if not bh or not bp or not bs then
        breedCache[key] = nil
        return nil
    end

    local calcQuality = quality or 4
    if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then
        if not quality or calcQuality < 4 then calcQuality = 4 end
    end

    local breedID = CalculateBreedFromStats(health, power, speed, bh, bp, bs, level, calcQuality)
    breedCache[key] = breedID
    return breedID
end

-- ============================================================================
-- 宠物册列表按钮品种标注（对齐 BattlePetBreedID 的 PetJournal_InitPetButton hook）
-- ============================================================================

--- Hook PetJournal_InitPetButton：在暴雪初始化每个列表按钮后，
--- 在按钮的物种名字后面追加品种短代码 + 最优标记 ★
local function OnPetButtonInit(button)
    if not button then return end
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end

    local petID = button.petID
    if not petID then return end

    local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
        C_PetJournal.GetPetInfoByPetID(petID)
    if not speciesID then return end

    local breedID = GetBreed(petID, speciesID, level, quality, health, power, speed)
    if not breedID then
        -- 未能确定品种，不做任何修改
        return
    end

    -- 品种短代码
    local breedCode = GetBreedCode(breedID)
    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    local suffix = " " .. breedCode
    if isBest then suffix = " ★" .. breedCode end

    -- 追加到按钮的物种名文本后面（BattlePetBreedID 同样修改 name/subname）
    -- 暴雪的按钮结构：button.name 是物种名的 FontString
    if button.name then
        local original = button.name:GetText() or ""
        -- 避免重复追加
        if not original:find(breedCode, 1, true) then
            button.name:SetText(original .. suffix)
        end
        if isBest then
            button.name:SetTextColor(1, 0.84, 0)  -- 最优品种金色
        end
    end
end

-- ============================================================================
-- 右键菜单：最优属性管理
-- ============================================================================

local menuFrame = nil

local function CreateBestBreedMenu()
    if menuFrame then return end
    menuFrame = CreateFrame("Frame", "GeneDexBDMenu", UIParent, "UIDropDownMenuTemplate")
end

local CATEGORY_KEYS = { pvp = true, pve = true, collection = true, custom = true }

local function ShowBestBreedMenu(button, petID, speciesID, breedID)
    if not speciesID or not breedID then return end

    CreateBestBreedMenu()

    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    UIDropDownMenu_Initialize(menuFrame, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- 品种信息（不可点击）
        local breedCode = GetBreedCode(breedID) or "?"
        local breedName = GetBreedDisplayName(breedID, breedCode)
        info.text = "品种: " .. breedName
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)

        if isBest then
            -- 已标记：显示分类 + 备注，提供取消选项
            local bi = addonTable.GetBestBreedInfo(speciesID, breedID)
            if bi then
                local catName = addonTable.GetBestBreedCategoryName and addonTable.GetBestBreedCategoryName(bi.category) or bi.category
                info.text = "已标记: " .. catName
                info.isTitle = true
                info.notCheckable = true
                UIDropDownMenu_AddButton(info, level)

                if bi.note and bi.note ~= "" then
                    info.text = "备注: " .. bi.note
                    info.isTitle = true
                    info.notCheckable = true
                    UIDropDownMenu_AddButton(info, level)
                end
            end

            -- 取消
            info.isTitle = false
            info.text = "取消最优品种"
            info.notCheckable = true
            info.func = function()
                addonTable.RemoveBestBreed(speciesID, breedID)
                breedCache = {}  -- 清缓存强制刷新
            end
            UIDropDownMenu_AddButton(info, level)
        else
            -- 未标记：提供按分类标记的子菜单
            info.isTitle = false
            info.text = "设为最优品种"
            info.notCheckable = true
            info.hasArrow = true
            info.menuList = { "pvp", "pve", "collection", "custom" }
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- 二级菜单：选择分类
    UIDropDownMenu_Initialize(menuFrame, function(self, level)
        if level == 2 then
            for _, cat in ipairs({"pvp", "pve", "collection", "custom"}) do
                local info = UIDropDownMenu_CreateInfo()
                local catName = addonTable.GetBestBreedCategoryName and addonTable.GetBestBreedCategoryName(cat) or cat
                info.text = catName
                info.notCheckable = true
                info.func = function()
                    addonTable.SetBestBreed(speciesID, breedID, cat, "")
                    breedCache = {}
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)

    ToggleDropDownMenu(1, nil, menuFrame, button, 0, 0)
end

--- Hook 列表按钮右键点击
local function OnPetButtonRightClick(button, petID, speciesID, breedID)
    ShowBestBreedMenu(button, petID, speciesID, breedID)
end

-- ============================================================================
-- 为每个列表按钮添加右键菜单 hook
-- 在 PetJournal_InitPetButton 后立即执行
-- ============================================================================

local function HookPetButtonRightClick(button)
    if not button or button._genedex_RightClickHooked then return end
    button._genedex_RightClickHooked = true

    -- 原有点击行为保持不变
    local petID = button.petID
    button:HookScript("OnClick", function(self, buttonName)
        if buttonName == "RightButton" then
            local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
                C_PetJournal.GetPetInfoByPetID(petID)
            if speciesID then
                local breedID = GetBreed(petID, speciesID, level, quality, health, power, speed)
                if breedID then
                    OnPetButtonRightClick(self, petID, speciesID, breedID)
                end
            end
        end
    end)
end

-- ============================================================================
-- 组合 Hook：在 PetJournal_InitPetButton 后一次性完成所有注入
-- ============================================================================

local function FullInitPetButton(button)
    if not button or not button.petID then return end

    -- 1. 追加品种文本到按钮
    OnPetButtonInit(button)

    -- 2. 添加右键菜单
    HookPetButtonRightClick(button)
end

-- ============================================================================
-- 初始化
-- ============================================================================

local hooksInstalled = false

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    hooksecurefunc("PetJournal_InitPetButton", FullInitPetButton)
    print("|cff00ff00[GenDexBD]|r 已 Hook PetJournal_InitPetButton")
end

function addonTable.InitJournalUI()
    -- 参考 BattlePetBreedID：监听 Blizzard_Collections 加载
    if C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
        InstallHooks()
    else
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("ADDON_LOADED")
        waiter:SetScript("OnEvent", function(_, _, addon)
            if addon == "Blizzard_Collections" then
                InstallHooks()
                waiter:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end
end
