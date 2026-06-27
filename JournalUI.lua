-- GenDexBD JournalUI.lua
-- 宠物手册集成：列表品种标记、详情品种显示、最优属性管理界面
-- 加载顺序：第6个（依赖 Core/DB、BreedMath、Locales、BreedData）
--
-- 注入位置：
--   列表页每行 → 品种短代码 FontString（如 "P/P"，目标品种前加 ★）
--   详情页 → 品种全称行 + 最优属性管理区（分类下拉/备注输入/切换按钮）

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
local tinsert = table.insert
local tconcat = table.concat
local strlower = string.lower
local strfind = string.find

-- ============================================================================
-- API 字段自动探测
-- ============================================================================

--- 已探测到的 C_PetJournal.GetPetInfoBySpeciesID 返回字段名（缓存）
local petInfoFields = nil  -- { healthKey, powerKey, speedKey }

--- 运行时自动探测 GetPetInfoBySpeciesID 返回表中三围基准属性的字段名
--- 用任意一个已知物种ID（如 39=机械小鸡）取一次数据，然后根据字段名模式匹配
--- @return healthKey, powerKey, speedKey 实际字段名
local function DetectPetInfoFields()
    if petInfoFields then
        return petInfoFields[1], petInfoFields[2], petInfoFields[3]
    end

    -- 尝试用物种ID=39（机械小鸡，几乎所有版本都有）取一次返回值来探测字段
    local sample = C_PetJournal.GetPetInfoBySpeciesID(39)
    if not sample then
        -- 退而求其次，取任意已知物种
        sample = C_PetJournal.GetPetInfoBySpeciesID(1)
    end
    if not sample then
        return nil, nil, nil
    end

    local allKeys = {}
    for k in pairs(sample) do
        allKeys[#allKeys + 1] = k
    end

    -- 字段匹配规则：字段名转换为小写后，包含特定关键词则判定为该属性类型
    local healthPatterns = { "health", "hp" }
    local powerPatterns = { "power", "attack", "atk" }
    local speedPatterns = { "speed", "spd" }

    local function findKey(patterns)
        for _, key in ipairs(allKeys) do
            local lowerKey = strlower(key)
            for _, pat in ipairs(patterns) do
                if strfind(lowerKey, pat, 1, true) then
                    return key
                end
            end
        end
        return nil
    end

    local healthKey = findKey(healthPatterns)
    local powerKey = findKey(powerPatterns)
    local speedKey = findKey(speedPatterns)

    petInfoFields = { healthKey, powerKey, speedKey }
    return healthKey, powerKey, speedKey
end

--- 从 GetPetInfoBySpeciesID 返回表中提取三围基准属性
--- @param petInfo table API 返回的物种信息表
--- @return number|nil baseHealth, number|nil basePower, number|nil baseSpeed
local function ExtractBaseStats(petInfo)
    if not petInfo then
        return nil, nil, nil
    end
    local hKey, pKey, sKey = DetectPetInfoFields()
    if not hKey or not pKey or not sKey then
        return nil, nil, nil
    end
    return petInfo[hKey], petInfo[pKey], petInfo[sKey]
end

-- ============================================================================
-- 宠物列表按钮自动发现
-- ============================================================================

--- 运行时动态获取宠物手册滚动列表中的所有可见按钮
--- 不依赖硬编码的按钮命名规则，而是通过遍历 scrollFrame 子元素自动发现
--- @return table Frame 对象数组
local function FindJournalListButtons()
    local buttons = {}

    -- 方法1：通过 HybridScrollFrame 标准 API 获取
    if PetJournalListScrollFrame and PetJournalListScrollFrame.buttons then
        for _, btn in ipairs(PetJournalListScrollFrame.buttons) do
            if btn and btn:IsVisible() then
                buttons[#buttons + 1] = btn
            end
        end
        if #buttons > 0 then
            return buttons
        end
    end

    -- 方法2：如果 ScrollFrame 存在，遍历其子元素
    -- 12.0 中 PetJournalListScrollFrame 可能为 nil（命名已变化），需要空值保护
    if PetJournalListScrollFrame then
        local children = { PetJournalListScrollFrame:GetChildren() }
        for _, child in ipairs(children) do
            local childName = child:GetName()
            if childName and strfind(childName, "PetJournalListScrollFrameButton") then
                if child:IsVisible() then
                    buttons[#buttons + 1] = child
                end
            end
        end
    end

    -- 方法3：如果以上都失败，回退到遍历全局命名表（兼容旧版）
    if #buttons == 0 then
        for i = 1, 40 do
            local btn = _G["PetJournalListScrollFrameButton" .. i]
            if btn and btn:IsVisible() then
                buttons[#buttons + 1] = btn
            end
        end
    end

    return buttons
end

-- 缓存键: speciesID .. "_" .. petID → breedID
-- 在宠物列表刷新和详情切换时使用，避免重复计算
local breedCache = {}

--- 获取缓存的品种（缓存未命中则计算并缓存）
--- @param speciesID  number
--- @param petID      number
--- @param level      number
--- @param quality    number
--- @param health     number 当前生命
--- @param power      number 当前攻击
--- @param speed      number 当前速度
--- @param baseHealth number 物种基础生命
--- @param basePower  number 物种基础攻击
--- @param baseSpeed  number 物种基础速度
--- @return number|nil breedID
local function GetCachedBreed(speciesID, petID, level, quality,
                               health, power, speed,
                               baseHealth, basePower, baseSpeed)
    local key = tostring(speciesID) .. "_" .. tostring(petID)

    -- 缓存命中
    local cached = breedCache[key]
    if cached ~= nil then
        -- 注意：nil 也是有效缓存值（表示之前已计算过但无法确定品种）
        return cached
    end

    -- 缓存未命中，计算
    if not health or not power or not speed or
       not baseHealth or not basePower or not baseSpeed then
        breedCache[key] = nil  -- 缓存"无法计算"
        return nil
    end

    -- 按配置决定品质
    local calcQuality = quality or 4
    if GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.AssumeRareQuality then
        if not quality or calcQuality < 4 then
            calcQuality = 4
        end
    end

    local breedID = CalculateBreedFromStats(
        health, power, speed,
        baseHealth, basePower, baseSpeed,
        level, calcQuality
    )

    breedCache[key] = breedID  -- 缓存结果（可能为 nil）
    return breedID
end

--- 清空指定物种的缓存（最优品种变更时调用）
local function InvalidateBreedCache(speciesID)
    local prefix = tostring(speciesID) .. "_"
    for key in pairs(breedCache) do
        if key:find(prefix, 1, true) == 1 then
            breedCache[key] = nil
        end
    end
end

-- ============================================================================
-- 公开 API：最优品种管理
-- ============================================================================

--- 设置最优品种（含分类和备注）
--- @param speciesID number 物种ID
--- @param breedID   number 品种ID
--- @param category  string|nil 分类键（默认 "custom"）
--- @param note      string|nil 备注文本（默认 ""）
function addonTable.SetBestBreed(speciesID, breedID, category, note)
    if not speciesID or not breedID or type(speciesID) ~= "number" or type(breedID) ~= "number" then
        return
    end

    local db = GeneDexDB
    if not db then
        return
    end
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

    -- 使缓存失效
    InvalidateBreedCache(speciesID)
end

--- 移除最优品种标记
--- @param speciesID number 物种ID
--- @param breedID   number 品种ID
function addonTable.RemoveBestBreed(speciesID, breedID)
    if not speciesID or not breedID then
        return
    end

    local db = GeneDexDB
    if not db then
        return
    end
    local bestBreeds = db.BestBreeds
    if not bestBreeds or type(bestBreeds) ~= "table" then
        return
    end

    local speciesData = bestBreeds[speciesID]
    if not speciesData or type(speciesData) ~= "table" then
        return
    end

    speciesData[breedID] = nil

    -- 如果该物种没有已标记品种了，清理键
    if not next(speciesData) then
        bestBreeds[speciesID] = nil
    end

    -- 使缓存失效
    InvalidateBreedCache(speciesID)
end

--- 查询是否是最优品种
--- @param speciesID number 物种ID
--- @param breedID   number 品种ID
--- @return boolean
function addonTable.IsBestBreed(speciesID, breedID)
    if not speciesID or not breedID then
        return false
    end
    local db = GeneDexDB
    if not db then
        return false
    end
    local bestBreeds = db.BestBreeds
    if not bestBreeds or type(bestBreeds) ~= "table" then
        return false
    end
    local speciesData = bestBreeds[speciesID]
    if not speciesData or type(speciesData) ~= "table" then
        return false
    end
    return speciesData[breedID] ~= nil
end

--- 获取最优品种元数据
--- @param speciesID number 物种ID
--- @param breedID   number 品种ID
--- @return table|nil { category, note, addedAt }
function addonTable.GetBestBreedInfo(speciesID, breedID)
    if not speciesID or not breedID then
        return nil
    end
    local db = GeneDexDB
    if not db then
        return nil
    end
    local bestBreeds = db.BestBreeds
    if not bestBreeds or type(bestBreeds) ~= "table" then
        return nil
    end
    local speciesData = bestBreeds[speciesID]
    if not speciesData or type(speciesData) ~= "table" then
        return nil
    end
    local breedData = speciesData[breedID]
    if not breedData or type(breedData) ~= "table" then
        return nil
    end
    return breedData
end

--- 获取某物种所有最优品种及其元数据
--- @param speciesID number 物种ID
--- @return table { [breedID] = { category, note, addedAt }, ... }
function addonTable.GetAllBestBreeds(speciesID)
    if not speciesID then
        return {}
    end
    local db = GeneDexDB
    if not db then
        return {}
    end
    local bestBreeds = db.BestBreeds
    if not bestBreeds or type(bestBreeds) ~= "table" then
        return {}
    end
    local speciesData = bestBreeds[speciesID]
    if not speciesData or type(speciesData) ~= "table" then
        return {}
    end
    return speciesData
end

-- ============================================================================
-- 列表页：品种短代码标注
-- ============================================================================

--- 更新单个列表按钮的品种标注
--- @param button table 列表按钮 Frame
--- @param breedID number|nil 品种ID
--- @param speciesID number 物种ID
local function UpdateListButtonBreed(button, breedID, speciesID)
    if not button then
        return
    end

    -- 查找或创建品种标注 FontString
    local breedText = button.GeneDexBreedText

    if not breedText then
        -- 首次创建：在按钮右上角创建小型 FontString
        breedText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        breedText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -4, -2)
        breedText:SetJustifyH("RIGHT")
        breedText:SetDrawLayer("OVERLAY")
        button.GeneDexBreedText = breedText
    end

    -- 检查配置开关
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        breedText:Hide()
        return
    end

    if not breedID then
        breedText:Hide()
        return
    end

    local breedCode = GetBreedCode(breedID)
    if not breedCode then
        breedText:Hide()
        return
    end

    -- 检查是否是最优品种
    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    -- 构建文本
    if isBest then
        breedText:SetText("★ " .. breedCode)
        breedText:SetTextColor(1.0, 0.84, 0.0)  -- 金色
    else
        breedText:SetText(breedCode)
        breedText:SetTextColor(0.8, 0.8, 0.8)   -- 浅灰色
    end

    breedText:Show()
end

-- 前置声明：定义在文件后部
local InjectIntoJournal

--- 刷新整个宠物列表的品种标注
function addonTable.RefreshJournalList()
    -- 首次调用时尝试注入 Journal UI
    if InjectIntoJournal then InjectIntoJournal() end

    -- 如果暴雪原生 PetJournal 不可见（被 Rematch 等插件接管），跳过列表刷新
    if not PetJournal or not PetJournal:IsShown() then
        return
    end

    -- 检查开关
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        -- 隐藏所有已有的标注（自动发现按钮）
        local allButtons = FindJournalListButtons()
        for _, button in ipairs(allButtons) do
            if button.GeneDexBreedText then
                button.GeneDexBreedText:Hide()
            end
        end
        return
    end

    -- 获取宠物总数
    local numPets = C_PetJournal.GetNumPets()
    if not numPets or numPets <= 0 then
        return
    end

    -- 尝试获取滚动偏移（支持多种 API）
    local scrollOffset = 0
    if PetJournalListScrollFrame then
        if PetJournalListScrollFrame.offset then
            scrollOffset = PetJournalListScrollFrame.offset
        elseif PetJournalListScrollFrame.scrollOffset then
            scrollOffset = PetJournalListScrollFrame.scrollOffset
        end
    end

    -- 自动发现所有可见的列表按钮
    local buttons = FindJournalListButtons()

    for i, button in ipairs(buttons) do
        local petIndex = i + scrollOffset
        if petIndex > numPets then
            -- 超出范围，隐藏
            if button.GeneDexBreedText then
                button.GeneDexBreedText:Hide()
            end
        else
            local petID = C_PetJournal.GetPetInfoByIndex(petIndex)
            if petID then
                local _, speciesID, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
                    C_PetJournal.GetPetInfoByPetID(petID)

                if speciesID and level then
                    -- 用自动探测获取物种基准属性
                    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                    local baseHealth, basePower, baseSpeed = ExtractBaseStats(petInfo)

                    -- 获取缓存/推算品种
                    local breedID = GetCachedBreed(
                        speciesID, petID, level, quality,
                        health, power, speed,
                        baseHealth, basePower, baseSpeed
                    )

                    UpdateListButtonBreed(button, breedID, speciesID)
                else
                    -- 数据不全，隐藏
                    if button.GeneDexBreedText then
                        button.GeneDexBreedText:Hide()
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 详情页：品种信息 + 最优属性管理
-- ============================================================================

-- 详情页 UI 控件引用（单例）
local detailBreedText = nil    -- "品种: P/P 攻击型" 文本行
local bestBreedFrame = nil     -- 最优属性管理区容器
local categoryDropdown = nil   -- 分类下拉菜单
local noteEditBox = nil        -- 备注输入框
local actionButton = nil       -- 设为/取消 按钮
local markedInfoLine = nil     -- 已标记信息行

-- 当前详情页上下文
local currentSpeciesID = nil
local currentBreedID = nil
local currentPetID = nil

-- 下拉菜单的分类选项
local CATEGORY_OPTIONS = {
    { key = "pvp",        order = 1 },
    { key = "pve",        order = 2 },
    { key = "collection", order = 3 },
    { key = "custom",     order = 4 },
}

--- 构建已标记品种信息文本
--- @param speciesID number
--- @return string|nil
local function BuildMarkedInfoText(speciesID)
    local bestBreeds = addonTable.GetAllBestBreeds(speciesID)
    if not bestBreeds or not next(bestBreeds) then
        return nil
    end

    local parts = {}
    for breedID, data in pairs(bestBreeds) do
        if type(data) == "table" then
            local breedCode = GetBreedCode(breedID) or "?"
            local categoryName = GetBestBreedCategoryName(data.category or "custom")
            parts[#parts + 1] = breedCode .. "(" .. categoryName .. ")"
        end
    end

    if #parts == 0 then
        return nil
    end

    local fmt = GetLocaleString("ALREADY_MARKED")
    return fmt:format(tconcat(parts, ", "))
end

--- 刷新详情页最优属性管理区 UI 状态
local function RefreshBestBreedUI()
    if not bestBreedFrame then
        return
    end

    local speciesID = currentSpeciesID
    local breedID = currentBreedID

    if not speciesID or not breedID then
        bestBreedFrame:Hide()
        return
    end

    -- 检查配置开关
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInJournal then
        bestBreedFrame:Hide()
        return
    end

    bestBreedFrame:Show()

    local isBest = addonTable.IsBestBreed(speciesID, breedID)
    local bestInfo = addonTable.GetBestBreedInfo(speciesID, breedID)

    -- 更新按钮文字
    if actionButton then
        if isBest and bestInfo then
            actionButton:SetText(GetLocaleString("REMOVE_BEST_BREED"))
        else
            actionButton:SetText(GetLocaleString("SET_BEST_BREED"))
        end
    end

    -- 更新下拉菜单显示
    if categoryDropdown then
        if isBest and bestInfo then
            local categoryName = GetBestBreedCategoryName(bestInfo.category or "custom")
            UIDropDownMenu_SetText(categoryDropdown, categoryName)
        else
            UIDropDownMenu_SetText(categoryDropdown, GetLocaleString("CATEGORY_CUSTOM"))
        end
    end

    -- 更新备注输入框
    if noteEditBox then
        if isBest and bestInfo then
            noteEditBox:SetText(bestInfo.note or "")
        else
            noteEditBox:SetText("")
        end
    end

    -- 更新已标记信息行
    if markedInfoLine then
        local infoText = BuildMarkedInfoText(speciesID)
        if infoText then
            markedInfoLine:SetText(infoText)
            markedInfoLine:Show()
        else
            markedInfoLine:Hide()
        end
    end
end

--- 设置当前详情页显示的宠物
local function SetCurrentPet(speciesID, breedID, petID)
    currentSpeciesID = speciesID
    currentBreedID = breedID
    currentPetID = petID
    RefreshBestBreedUI()
end

--- 详情页"设为/取消"按钮点击处理
local function OnActionButtonClick()
    local speciesID = currentSpeciesID
    local breedID = currentBreedID

    if not speciesID or not breedID then
        return
    end

    if addonTable.IsBestBreed(speciesID, breedID) then
        -- 已标记 → 取消
        addonTable.RemoveBestBreed(speciesID, breedID)
    else
        -- 未标记 → 设为最优
        -- 读取当前分类选择
        local category = "custom"
        if categoryDropdown and categoryDropdown.selectedKey then
            category = categoryDropdown.selectedKey
        end
        -- 读取备注
        local note = ""
        if noteEditBox then
            note = noteEditBox:GetText() or ""
        end

        addonTable.SetBestBreed(speciesID, breedID, category, note)
    end

    -- 刷新整个界面
    RefreshBestBreedUI()
    addonTable.RefreshJournalList()
    -- 刷新详情品种行（因最优状态变化需要更新文本颜色）
    RefreshDetailBreedLine()
end

--- 刷新详情品种文本行（如 "品种: P/P 攻击型"）
local function RefreshDetailBreedLine()
    if not detailBreedText then
        return
    end

    local speciesID = currentSpeciesID
    local breedID = currentBreedID

    if not speciesID or not breedID then
        detailBreedText:Hide()
        return
    end

    local breedCode = GetBreedCode(breedID) or "?"
    local breedName = GetBreedDisplayName(breedID, breedCode)
    local isBest = addonTable.IsBestBreed(speciesID, breedID)

    local fmt = GetLocaleString("BREED_FORMAT")
    local text = fmt:format(breedCode, breedName)

    if isBest then
        local bestInfo = addonTable.GetBestBreedInfo(speciesID, breedID)
        if bestInfo then
            local categoryName = GetBestBreedCategoryName(bestInfo.category or "custom")
            local targetFmt = GetLocaleString("BREED_TARGET_FORMAT")
            text = targetFmt:format(breedCode, breedName, categoryName)
        end
        detailBreedText:SetTextColor(1.0, 0.84, 0.0)  -- 金色
    else
        detailBreedText:SetTextColor(1.0, 1.0, 1.0)   -- 白色
    end

    detailBreedText:SetText(text)
    detailBreedText:Show()
end

--- 下拉菜单初始化回调
--- @param self table 下拉按钮
--- @param level number 菜单层级
local function CategoryDropDown_Initialize(self, level)
    -- 为每个分类选项创建菜单项
    for _, opt in ipairs(CATEGORY_OPTIONS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = GetBestBreedCategoryName(opt.key)
        info.value = opt.key
        info.func = function(button)
            -- 保存选择
            self.selectedKey = button.value
            -- 更新按钮显示文本
            UIDropDownMenu_SetText(self, button:GetText())

            -- 关闭菜单
            CloseDropDownMenus()

            -- 如果当前已标记，可自动更新（可选行为，这里只更新内部状态）
        end
        info.checked = (self.selectedKey == opt.key)
        UIDropDownMenu_AddButton(info, level)
    end
end

--- 创建次优属性管理区 UI
--- @param parentFrame table 父容器（PetJournal 相关 frame）
local function CreateBestBreedUI(parentFrame)
    if bestBreedFrame then
        return  -- 已创建
    end

    -- 容器 Frame
    bestBreedFrame = CreateFrame("Frame", nil, parentFrame)
    bestBreedFrame:SetSize(280, 150)
    bestBreedFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 10, -180)
    bestBreedFrame:Hide()

    -- "★ 最优属性管理" 标题
    local sectionTitle = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sectionTitle:SetPoint("TOPLEFT", bestBreedFrame, "TOPLEFT", 0, 0)
    sectionTitle:SetText(GetLocaleString("BEST_BREED_SECTION"))
    sectionTitle:SetTextColor(1.0, 0.84, 0.0)

    -- 分类标签
    local categoryLabel = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    categoryLabel:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -10)
    categoryLabel:SetText(GetLocaleString("CATEGORY_LABEL") .. ":")
    categoryLabel:SetTextColor(1.0, 1.0, 1.0)

    -- 分类下拉菜单
    categoryDropdown = CreateFrame("Frame", "GeneDexBDCategoryDropdown", bestBreedFrame, "UIDropDownMenuTemplate")
    categoryDropdown:SetPoint("LEFT", categoryLabel, "RIGHT", 8, 0)
    categoryDropdown.selectedKey = "custom"
    UIDropDownMenu_Initialize(categoryDropdown, CategoryDropDown_Initialize)
    UIDropDownMenu_SetWidth(categoryDropdown, 120)
    UIDropDownMenu_SetText(categoryDropdown, GetLocaleString("CATEGORY_CUSTOM"))

    -- 备注标签
    local noteLabel = bestBreedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    noteLabel:SetPoint("TOPLEFT", categoryLabel, "BOTTOMLEFT", 0, -10)
    noteLabel:SetText(GetLocaleString("NOTE_LABEL_UI") .. ":")
    noteLabel:SetTextColor(1.0, 1.0, 1.0)

    -- 备注输入框
    noteEditBox = CreateFrame("EditBox", nil, bestBreedFrame, "InputBoxTemplate")
    noteEditBox:SetPoint("LEFT", noteLabel, "RIGHT", 8, 0)
    noteEditBox:SetPoint("RIGHT", bestBreedFrame, "RIGHT", -4, 0)
    noteEditBox:SetHeight(24)
    noteEditBox:SetAutoFocus(false)
    noteEditBox:SetMaxLetters(64)
    noteEditBox:SetTextInsets(4, 4, 2, 2)
    -- 占位符通过 hint 方式（WoW 标准 EditBox 无 placeholder）
    -- 使用 OnEscapePressed 清空
    noteEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- 操作按钮
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

--- 创建详情品种文本（如 "品种: P/P 攻击型"）
--- @param parentFrame table 父容器
local function CreateDetailBreedLine(parentFrame)
    if detailBreedText then
        return
    end

    -- 动态查找宠物卡片（12.0 命名可能已变化）
    local petCard = FindPetCard()
    if not petCard then
        return
    end

    detailBreedText = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailBreedText:SetPoint("BOTTOMLEFT", petCard, "TOPLEFT", 10, 2)
    detailBreedText:SetPoint("RIGHT", petCard, "RIGHT", -10, 0)
    detailBreedText:SetJustifyH("LEFT")
    detailBreedText:Hide()
end

--- 当选中宠物变化时更新详情页
local function UpdateDetailView()
    -- 仅在暴雪原生 PetJournal 可见时更新
    if not PetJournal or not PetJournal:IsShown() then
        return
    end

    local speciesID = C_PetJournal.GetSelectedSpeciesID()
    local petID = C_PetJournal.GetSelectedPetID()

    if not speciesID or not petID then
        SetCurrentPet(nil, nil, nil)
        if detailBreedText then
            detailBreedText:Hide()
        end
        if bestBreedFrame then
            bestBreedFrame:Hide()
        end
        return
    end

    -- 获取当前宠物数据
    local _, _, _, _, _, _, _, _, _, _, level, quality, health, power, speed =
        C_PetJournal.GetPetInfoByPetID(petID)

    if not level then
        SetCurrentPet(nil, nil, nil)
        return
    end

    -- 获取物种基准属性（自动探测 API 字段名）
    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    local baseHealth, basePower, baseSpeed = ExtractBaseStats(petInfo)

    -- 推算品种
    local breedID = GetCachedBreed(
        speciesID, petID, level, quality,
        health, power, speed,
        baseHealth, basePower, baseSpeed
    )

    SetCurrentPet(speciesID, breedID, petID)
    RefreshDetailBreedLine()
end

-- ============================================================================
-- 焦点帧：运行时自动发现并注入到 PetJournal
-- ============================================================================

-- 是否已完成注入（只需注入一次）
local journalInjected = false
-- 监听宠物选择变化的 OnUpdate 帧
local journalWatcherFrame = nil

--- 运行时查找宠物手册的父容器 Frame
--- 12.0 中 CollectionsJournal 是主容器，PetJournal 是暴雪宠物面板（子 Frame）
--- @return table|nil 找到的父 Frame
local function FindJournalParent()
    -- 候选名称列表（12.0 真名优先）
    local candidates = {
        "CollectionsJournal",    -- 12.0 (Midnight) 收藏界面主容器
        "PetJournalParent",      -- 旧版经典名称
        "PetJournal",            -- 暴雪宠物面板
        "PetJournalFrame",       -- 变体
    }

    for _, name in ipairs(candidates) do
        local frame = _G[name]
        if frame then
            print("|cff00ff00[GenDexBD]|r 找到宠物手册容器: " .. name)
            return frame
        end
    end

    -- 以上都没有：尝试从已知子元素向上遍历
    if PetJournal then
        local parent = PetJournal:GetParent()
        for _ = 1, 5 do
            if not parent then break end
            local children = { parent:GetChildren() }
            if #children >= 3 then
                return parent
            end
            parent = parent:GetParent()
        end
    end

    return nil
end

--- 运行时查找详情页的宠物卡片 Frame
--- 12.0 中 PetJournal 是暴雪宠物面板（CollectionsJournal 的子 Frame）
--- PetCard 是 PetJournal 内部显示宠物模型的区域
--- @return table|nil
local function FindPetCard()
    -- 已知名称列表（12.0 优先）
    local cardNames = {
        "PetJournalPetCard",           -- 经典名称
        "PetJournalPetCardFrame",      -- 变体
        "CollectionsJournalPetCard",   -- 12.0 可能的命名
    }
    for _, name in ipairs(cardNames) do
        local frame = _G[name]
        if frame then
            return frame
        end
    end

    -- 在 PetJournal 内搜索包含 "Card" 的子 Frame
    if PetJournal then
        local children = { PetJournal:GetChildren() }
        for _, child in ipairs(children) do
            local childName = child:GetName() or ""
            if strfind(childName, "Card") then
                return child
            end
        end
    end

    return nil
end

--- 执行首次注入：在 PetJournal 界面中创建品种显示和管理 UI
--- 仅在暴雪原生宠物面板（PetJournal）可见时注入
--- 如果 Rematch 等插件已接管（PetJournal 被隐藏），则跳过
local function InjectIntoJournal()
    if journalInjected then
        return
    end

    -- 确定父容器：12.0 中是 CollectionsJournal（不是 PetJournalParent）
    -- PetJournal 是暴雪宠物面板（CollectionsJournal 的子 Frame）
    local parentFrame = FindJournalParent()
    if not parentFrame then
        return
    end

    -- 检查 PetJournal 是否存在且可见
    -- 如果 Rematch 等插件已接管宠物面板，PetJournal 会被隐藏
    -- 此时应跳过注入，避免与插件冲突
    if PetJournal and not PetJournal:IsShown() then
        -- Rematch 等插件已激活，推迟到 PetJournal 可见时再注入
        return
    end

    journalInjected = true

    print("|cff00ff00[GenDexBD]|r 宠物手册框架: " .. (parentFrame:GetName() or "<未命名>") .. "，品种UI注入中...")

    -- 将详情行和最优管理区挂在 PetJournal 上（而不是 CollectionsJournal）
    -- 这样当 Rematch 接管时 PetJournal 隐藏，我们的 UI 也随之隐藏
    local journalFrame = PetJournal or parentFrame

    CreateDetailBreedLine(journalFrame)
    CreateBestBreedUI(journalFrame)
    print("|cff00ff00[GenDexBD]|r 品种UI已注入到: " .. (journalFrame:GetName() or "<未命名>"))

    -- 创建选择变化监听帧
    if not journalWatcherFrame then
        journalWatcherFrame = CreateFrame("Frame")
        journalWatcherFrame.tick = 0
        journalWatcherFrame:SetScript("OnUpdate", function(self, elapsed)
            self.tick = self.tick + elapsed
            if self.tick < 0.3 then return end
            self.tick = 0

            -- 仅在 PetJournal 可见时工作
            if PetJournal and PetJournal:IsShown() then
                local speciesID = C_PetJournal.GetSelectedSpeciesID()
                if speciesID ~= currentSpeciesID then
                    UpdateDetailView()
                end
            end
        end)
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化 Journal UI（由 Core.lua 在 PLAYER_LOGIN 时调用）
--- 不在此处直接注入，而是等 PET_JOURNAL_LIST_UPDATE 首次触发时自动注入
--- 因为 PetJournal 的 Frame 只有在用户首次打开宠物手册时才会被创建
function addonTable.InitJournalUI()
    -- 不需要做任何事
    -- RefreshJournalList() 会在 PET_JOURNAL_LIST_UPDATE 时调用
    -- 首次调用时自动触发 InjectIntoJournal()
end
