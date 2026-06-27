-- GenDexBD JournalUI.lua
-- 双模式品种标注：暴雪原生面板 + Rematch 面板

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

local function LOG(fmt, ...) print("|cff00ccff[GenDexBD]|r " .. fmt:format(...)) end
local function ERR(fmt, ...) print("|cffff0000[GenDexBD]|r " .. fmt:format(...)) end

-- ============================================================================
-- 最优品种管理 API
-- ============================================================================

function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID then return end
    if not GeneDexDB then ERR("GeneDexDB nil"); return end
    if not GeneDexDB.BestBreeds or type(GeneDexDB.BestBreeds) ~= "table" then GeneDexDB.BestBreeds = {} end
    if not GeneDexDB.BestBreeds[speciesID] then GeneDexDB.BestBreeds[speciesID] = {} end
    GeneDexDB.BestBreeds[speciesID][breedID] = { category = category or "custom", note = note or "", addedAt = time() }
    LOG("SetBestBreed species=%d breed=%d cat=%s", speciesID, breedID, category or "custom")
    RefreshAllButtons()
end

function addonTable.RemoveBestBreed(speciesID, breedID)
    if not speciesID or not breedID then return end
    local bb = GeneDexDB and GeneDexDB.BestBreeds
    if not bb or type(bb) ~= "table" then return end
    local sd = bb[speciesID]
    if not sd or type(sd) ~= "table" then return end
    sd[breedID] = nil
    if not next(sd) then bb[speciesID] = nil end
    RefreshAllButtons()
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
-- API 字段探测
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
-- 品种推算
-- ============================================================================

local function CalcBreed(speciesID, level, quality, health, power, speed)
    if not health or not power or not speed then return nil end
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
-- 按钮发现：双来源
-- ============================================================================

--- 判断按钮是否为 Rematch 按钮（有 Breed FontString 子元素的特征）
local function IsRematchButton(button)
    return button.Breed ~= nil
end

--- 深度遍历 Frame 找有 petID 的可见子元素
local function DeepScan(root, maxDepth)
    local btns = {}
    local function scan(parent, depth)
        if depth > maxDepth then return end
        local children = { parent:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsVisible() and child.petID then
                btns[#btns + 1] = child
            end
            scan(child, depth + 1)
        end
    end
    scan(root, 0)
    return btns
end

--- 获取所有可见的宠物列表按钮（暴雪原生 + Rematch）
local function FindPetListButtons()
    -- 源1：Rematch 面板
    if RematchFrame and RematchFrame:IsShown() then
        local btns = DeepScan(RematchFrame, 4)
        if #btns > 0 then
            return btns, "Rematch"
        end
    end

    -- 源2：暴雪原生 PetJournal
    if PetJournal and PetJournal:IsShown() then
        local btns = DeepScan(PetJournal, 4)
        if #btns > 0 then
            return btns, "PetJournal"
        end
    end

    -- 源3：全局命名表（旧版兼容）
    local btns = {}
    for i = 1, 50 do
        local b = _G["PetJournalListScrollFrameButton" .. i]
        if not b then break end
        if b:IsVisible() and b.petID then btns[#btns + 1] = b end
    end
    if #btns > 0 then return btns, "全局命名表" end

    return {}, "none"
end

-- ============================================================================
-- 按钮品种标注（通用，适配双来源）
-- ============================================================================

--- 为单个按钮添加/更新品种标注
local function LabelButton(button)
    if not button or not button.petID then return end
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        return
    end

    local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
        C_PetJournal.GetPetInfoByPetID(button.petID)
    if not speciesID then return end

    local breedID = CalcBreed(speciesID, level, quality, health, power, speed)
    if not breedID then return end

    local code = GetBreedCode(breedID)
    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    if IsRematchButton(button) then
        -- Rematch 按钮：改写已有的 Breed FontString
        if button.Breed then
            button.Breed:SetText(isBest and ("★" .. code) or code)
            button.Breed:SetTextColor(isBest and 1 or 0.6, isBest and 0.84 or 0.6, 0.6)
            button.Breed:Show()
        end
        -- 同时改写 SpeciesName（如果可见）追加品种信息
        if button.SpeciesName and button.SpeciesName:IsShown() then
            local cur = button.SpeciesName:GetText() or ""
            -- 去重
            if not cur:find(code, 1, true) then
                button.SpeciesName:SetText(cur .. "  [" .. code .. "]")
            end
        end
    else
        -- 暴雪原生按钮：创建独立的 FontString
        if not button._genedexLabel then
            local fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("RIGHT", button, "RIGHT", -6, 0)
            fs:SetJustifyH("RIGHT")
            button._genedexLabel = fs
        end
        local label = button._genedexLabel
        label:SetText(isBest and ("★" .. code) or code)
        label:SetTextColor(isBest and 1 or 0.6, isBest and 0.84 or 0.6, 0.6)
        label:Show()
    end
end

--- 刷新所有列表按钮的品种标注
function RefreshAllButtons()
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then return end

    local btns, source = FindPetListButtons()
    local count = 0
    for _, b in ipairs(btns) do
        local ok, err = pcall(LabelButton, b)
        if ok then count = count + 1
        elseif err then ERR("LabelButton: %s", tostring(err)) end
    end
    if count > 0 then LOG("已标注 %d 个按钮 (来源=%s)", count, source) end
end

-- ============================================================================
-- 右键菜单
-- ============================================================================

local menuFrame = nil

local function EnsureMenu()
    if menuFrame then return end
    menuFrame = CreateFrame("Frame", "GeneDexBDMenu", UIParent, "UIDropDownMenuTemplate")
end

local function ShowBestBreedMenu(button, speciesID, breedID)
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
            for _, cat in ipairs({"pvp", "pve", "collection", "custom"}) do
                local catName = addonTable.GetBestBreedCategoryName and addonTable.GetBestBreedCategoryName(cat) or cat
                info.text = catName
                info.notCheckable = true
                info.func = function()
                    addonTable.SetBestBreed(speciesID, breedID, cat, "")
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
        ShowBestBreedMenu(self, speciesID, breedID)
    end)
end

-- ============================================================================
-- 事件回调
-- ============================================================================

local updateCount = 0

local function OnListUpdate()
    updateCount = updateCount + 1
    local btns, source = FindPetListButtons()
    LOG("#%d 找到 %d 个按钮 (来源=%s)", updateCount, #btns, source)

    if #btns > 0 then
        for _, b in ipairs(btns) do
            pcall(LabelButton, b)
            HookRightClick(b)
        end
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

local inited = false

function addonTable.InitJournalUI()
    if inited then return end
    inited = true
    LOG("初始化 (双模式: 原生面板+Rematch)")

    -- 触发1：PET_JOURNAL_LIST_UPDATE（两者都会触发）
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PET_JOURNAL_LIST_UPDATE")
    ef:SetScript("OnEvent", function(_, e)
        if e == "PET_JOURNAL_LIST_UPDATE" then OnListUpdate() end
    end)

    -- 触发2：Blizzard_Collections 加载
    local bcf = CreateFrame("Frame")
    bcf:RegisterEvent("ADDON_LOADED")
    bcf:SetScript("OnEvent", function(_, _, a)
        if a == "Blizzard_Collections" then
            LOG("Blizzard_Collections 已加载")
            OnListUpdate()
            bcf:UnregisterEvent("ADDON_LOADED")
        end
    end)

    -- 触发3：RematchFrame Show（Rematch 打开/切换到日志模式时）
    local rmf = CreateFrame("Frame")
    rmf:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t < 0.5 then return end
        self._t = 0

        if RematchFrame and RematchFrame:IsShown() then
            if not self._wasShown then
                self._wasShown = true
                LOG("RematchFrame 已显示，触发刷新")
                OnListUpdate()
            end
        else
            self._wasShown = false
        end
    end)

    -- 触发4：如果 Rematch 正在显示中（插件加载时已经在用 Rematch）
    if RematchFrame and RematchFrame:IsShown() then
        C_Timer.After(0.5, function() OnListUpdate() end)
    end
end
