-- GenDexBD JournalUI.lua
-- 宠物手册集成：品种标注 + 右键最优管理
-- 全量诊断日志覆盖每个决策点

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

local function LOG(fmt, ...)
    print("|cff00ccff[GenDexBD]|r " .. fmt:format(...))
end

local function ERR(fmt, ...)
    print("|cffff0000[GenDexBD]|r " .. fmt:format(...))
end

-- ============================================================================
-- 最优品种管理 API
-- ============================================================================

function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID then return end
    if not GeneDexDB then ERR("SetBestBreed: GeneDexDB nil"); return end
    if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds) ~= "table" then GeneDexDB.BestBreeds = {} end
    if not GeneDexDB.BestBreeds[speciesID] then GeneDexDB.BestBreeds[speciesID] = {} end
    GeneDexDB.BestBreeds[speciesID][breedID] = { category = category or "custom", note = note or "", addedAt = time() }
    LOG("SetBestBreed species=%d breed=%d cat=%s", speciesID, breedID, category or "custom")
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
    if not sample then
        ERR("无法获取 C_PetJournal.GetPetInfoBySpeciesID 返回值")
        return nil, nil, nil
    end
    local allKeys = {}
    for k in pairs(sample) do allKeys[#allKeys + 1] = k end
    LOG("宠物信息字段: %s", table.concat(allKeys, ", "))
    local function fk(patterns)
        for _, key in ipairs(allKeys) do
            local lk = strlower(key)
            for _, pat in ipairs(patterns) do if strfind(lk, pat, 1, true) then return key end end
        end
    end
    local hk = fk({"health", "hp"})
    local pk = fk({"power", "attack", "atk"})
    local sk = fk({"speed", "spd"})
    if not hk or not pk or not sk then
        ERR("无法匹配基准属性字段: H=%s P=%s S=%s", tostring(hk), tostring(pk), tostring(sk))
    else
        LOG("基准属性字段: H=%s P=%s S=%s", hk, pk, sk)
    end
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
    if not health or not power or not speed then
        -- 正常情况：背包里的宠物可能没有属性数据
        return nil
    end
    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if not petInfo then return nil end

    local bh, bp, bs = ExtractBaseStats(petInfo)
    if not bh or not bp or not bs then return nil end

    local calcQuality = quality or 4
    if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then
        if not quality or calcQuality < 4 then calcQuality = 4 end
    end

    return CalculateBreedFromStats(health, power, speed, bh, bp, bs, level, calcQuality)
end

-- ============================================================================
-- 列表按钮品种标注
-- ============================================================================
local function FindPetListButtons()
    local btns = {}
    local method = ""

    -- 方法1：旧式 HybridScrollFrame
    if PetJournalListScrollFrame then
        method = "HybridScrollFrame.buttons"
        if PetJournalListScrollFrame.buttons then
            for _, b in ipairs(PetJournalListScrollFrame.buttons) do
                if b and b:IsVisible() and b.petID then btns[#btns + 1] = b end
            end
        end
        if #btns > 0 then return btns end
    end

    -- 方法2：遍历 PetJournal / CollectionsJournal 的全部子 Frame（12.0 ScrollBox）
    local searchRoots = {}
    if PetJournal then searchRoots[#searchRoots + 1] = { name = "PetJournal", frame = PetJournal } end
    if CollectionsJournal then searchRoots[#searchRoots + 1] = { name = "CollectionsJournal", frame = CollectionsJournal } end

    for _, root in ipairs(searchRoots) do
        method = root.name .. " 深度遍历"
        local function scan(parent, depth)
            if depth > 6 then return end
            local children = { parent:GetChildren() }
            for _, child in ipairs(children) do
                if child:IsVisible() and child.petID then
                    btns[#btns + 1] = child
                end
                scan(child, depth + 1)
            end
        end
        scan(root.frame, 0)
        if #btns > 0 then
            LOG("找到 %d 个按钮 (方法=%s)", #btns, method)
            return btns
        end
    end

    -- 方法3：全局命名表
    method = "全局命名表"
    for i = 1, 50 do
        local b = _G["PetJournalListScrollFrameButton" .. i]
        if not b then break end
        if b:IsVisible() and b.petID then btns[#btns + 1] = b end
    end

    return btns
end

--- 为单个按钮添加品种标注
local function LabelButton(button)
    if not button or not button.petID then
        ERR("LabelButton: 无效按钮")
        return
    end

    -- 创建标注 FontString（仅首次）
    if not button._genedexLabel then
        local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", button, "RIGHT", -6, 0)
        fs:SetJustifyH("RIGHT")
        button._genedexLabel = fs
    end

    local label = button._genedexLabel

    -- 配置开关检查
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        label:Hide()
        return
    end

    -- 获取宠物数据
    local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
        C_PetJournal.GetPetInfoByPetID(button.petID)
    if not speciesID then
        label:Hide()
        return
    end

    -- 推算品种
    local breedID = CalcBreed(speciesID, level, quality, health, power, speed)
    if not breedID then
        label:Hide()
        return
    end

    local code = GetBreedCode(breedID)
    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    label:SetText(isBest and ("★" .. code) or code)
    label:SetTextColor(isBest and 1 or 0.6, isBest and 0.84 or 0.6, 0.6)
    label:Show()
end

--- 刷新全部列表按钮
local function RefreshAllButtons()
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        return
    end

    local btns = FindPetListButtons()
    local count = 0
    for _, b in ipairs(btns) do
        local ok, err = pcall(LabelButton, b)
        if ok then count = count + 1 end
        if not ok then ERR("LabelButton 失败: %s", tostring(err)) end
    end
    if count > 0 then
        LOG("已标注 %d 个按钮", count)
    end
end

-- ============================================================================
-- 右键菜单
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
-- PET_JOURNAL_LIST_UPDATE 回调
-- ============================================================================

local updateCount = 0

local function OnJournalUpdate()
    updateCount = updateCount + 1

    -- PetJournal 在 Blizzard_Collections 加载前为 nil，直接跳过
    if not PetJournal then
        LOG("#%d PetJournal=nil 跳过", updateCount)
        return
    end

    local hasCJ = CollectionsJournal ~= nil
    LOG("#%d PJ=%s CJ=%s PJ.show=%s",
        updateCount,
        PetJournal and "T" or "nil",
        hasCJ and "T" or "nil",
        PetJournal:IsShown() and "yes" or "no")

    -- 首次 PetJournal 存在时打印所有子 Frame 结构
    if not PetJournal._genedex_dumped then
        PetJournal._genedex_dumped = true
        LOG("=== PetJournal 子 Frame 结构 ===")
        local function dump(parent, indent)
            if indent > 3 then return end
            local children = { parent:GetChildren() }
            for _, child in ipairs(children) do
                local cn = child:GetName() or "<unnamed>"
                local cv = child:IsVisible() and "可见" or "隐藏"
                local extra = ""
                if child.petID then extra = " [petID=" .. tostring(child.petID) .. "]" end
                if child.buttonType then extra = extra .. " [buttonType]" end
                LOG("  " .. string.rep("  ", indent) .. "%s (%s)%s", cn, cv, extra)
                dump(child, indent + 1)
            end
        end
        dump(PetJournal, 0)
        LOG("=== 结构结束 ===")
    end

    RefreshAllButtons()

    local btns = FindPetListButtons()
    for _, b in ipairs(btns) do
        if b and b.petID then HookRightClick(b) end
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

function addonTable.InitJournalUI()
    LOG("JournalUI 初始化开始")

    -- PET_JOURNAL_LIST_UPDATE 事件
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    ef:SetScript("OnEvent", function(_, event)
        if event == "PET_JOURNAL_LIST_UPDATE" then
            OnJournalUpdate()
        end
    end)
    LOG("已注册 PET_JOURNAL_LIST_UPDATE")

    -- Blizzard_Collections 加载时
    local wf = CreateFrame("Frame")
    wf:RegisterEvent("ADDON_LOADED")
    wf:SetScript("OnEvent", function(_, _, a)
        if a == "Blizzard_Collections" then
            LOG("Blizzard_Collections 已加载，触发刷新")
            OnJournalUpdate()
            wf:UnregisterEvent("ADDON_LOADED")
        end
    end)

    LOG("JournalUI 初始化完成")
end
