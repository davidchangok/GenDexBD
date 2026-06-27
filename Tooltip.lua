-- GenDexBD Tooltip.lua
-- 鼠标提示品种装饰：在宠物 Tooltip 中追加品种信息行
-- 加载顺序：第5个（依赖 Core 的 DB、BreedMath、Locales、BreedData）
-- 使用 12.0 现代 API: TooltipDataProcessor.AddTooltipPostCall()

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化
-- ============================================================================

local CalculateBreedFromStats = addonTable.CalculateBreedFromStats
local GetBreedCode = addonTable.GetBreedCode
local GetBreedDisplayName = addonTable.GetBreedDisplayName
local GetBestBreedCategoryName = addonTable.GetBestBreedCategoryName
local GetLocaleString = addonTable.GetLocaleString

local TooltipDataProcessor_AddTooltipPostCall = TooltipDataProcessor.AddTooltipPostCall

-- ============================================================================
-- 内部辅助函数
-- ============================================================================

--- 获取最优品种信息（内联以避免循环依赖 JournalUI）
--- @param speciesID number 物种ID
--- @param breedID number 品种ID
--- @return table|nil 最优品种元数据 { category, note, addedAt }
local function GetBestBreedInfo(speciesID, breedID)
    if not speciesID or not breedID then
        return nil
    end
    local bestBreeds = GeneDexDB.BestBreeds
    if not bestBreeds then
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

--- 构建品种 Tooltip 文本行
--- @param breedID number
--- @param isTarget boolean 是否是最优品种
--- @param bestInfo table|nil 最优品种元数据
--- @return string 品种行文本
local function BuildBreedLine(breedID, isTarget, bestInfo)
    local breedCode = GetBreedCode(breedID) or "?"
    local breedName = GetBreedDisplayName(breedID, breedCode)

    if not isTarget or not bestInfo then
        -- 普通品种：品种: P/P 攻击型
        local fmt = GetLocaleString("BREED_FORMAT")
        return fmt:format(breedCode, breedName)
    else
        -- 目标品种：品种: P/P 攻击型 🎯 PvP 对战
        local categoryName = GetBestBreedCategoryName(bestInfo.category or "custom")
        local fmt = GetLocaleString("BREED_TARGET_FORMAT")
        return fmt:format(breedCode, breedName, categoryName)
    end
end

--- 构建备注行
--- @param note string 备注文本
--- @return string|nil
local function BuildNoteLine(note)
    if not note or note == "" then
        return nil
    end
    local fmt = GetLocaleString("NOTE_LABEL")
    return fmt:format(note)
end

-- ============================================================================
-- Tooltip 处理回调
-- ============================================================================

--- BattlePet 类型 Tooltip 回调（宠物手册内悬停、野外宠物悬停）
--- @param tooltip table Tooltip 对象
--- @param data table Tooltip 数据
local function OnBattlePetTooltip(tooltip, data)
    -- 检查用户配置开关
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInTooltip then
        return
    end

    -- 提取 Tooltip 数据字段
    local speciesID = data.speciesID
    local level = data.level
    local quality = data.quality
    local health = data.maxHealth
    local power = data.power
    local speed = data.speed

    if not speciesID or not level then
        return  -- 数据不完整，无法推算
    end

    -- 获取物种基准属性
    local petInfo = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if not petInfo then
        return
    end

    -- 尝试多种可能的字段名（WoW API 返回字段名可能因版本而异）
    local baseHealth = petInfo.baseHealth or petInfo.health or petInfo.baseHp or petInfo.baseHP
    local basePower = petInfo.basePower or petInfo.power or petInfo.baseAtk or petInfo.baseAttack
    local baseSpeed = petInfo.baseSpeed or petInfo.speed or petInfo.baseSpd or petInfo.baseSpeed2

    if not baseHealth or not basePower or not baseSpeed then
        return
    end

    -- 如果启用了"按精良品质推算"，且当前品质低于4，则用品质4推算
    local calcQuality = quality or 4
    if GeneDexDB.Options.AssumeRareQuality and calcQuality < 4 then
        calcQuality = 4
    end

    -- 推算品种
    local breedID = CalculateBreedFromStats(
        health, power, speed,
        baseHealth, basePower, baseSpeed,
        level, calcQuality
    )

    if not breedID then
        return  -- 无法确定品种，不显示
    end

    -- 检查是否是最优品种
    local bestInfo = GetBestBreedInfo(speciesID, breedID)
    local isTarget = bestInfo ~= nil

    -- 添加品种行
    local breedLine = BuildBreedLine(breedID, isTarget, bestInfo)
    local r, g, b = 1.0, 1.0, 1.0  -- 默认白色
    if isTarget then
        r, g, b = 1.0, 0.84, 0.0   -- 目标品种金色
    end
    tooltip:AddLine(breedLine, r, g, b)

    -- 添加备注行（仅目标品种 + 有备注 + 开关启用）
    if isTarget and GeneDexDB.Options.ShowBestBreedNote then
        local noteLine = BuildNoteLine(bestInfo.note)
        if noteLine then
            tooltip:AddLine(noteLine, r, g, b)
        end
    end
end

--- Item 类型 Tooltip 回调（背包宠物笼物品）
--- @param tooltip table Tooltip 对象
--- @param data table Tooltip 数据
local function OnItemTooltip(tooltip, data)
    -- 检查用户配置开关
    if not GeneDexDB or not GeneDexDB.Options or not GeneDexDB.Options.ShowInTooltip then
        return
    end

    -- 尝试获取物品对应的宠物物种
    local itemID = data.id
    if not itemID then
        return
    end

    -- 通过物品ID获取宠物信息
    local speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
    if not speciesID then
        return  -- 不是宠物笼物品
    end

    -- 检查该物种是否有已标记的最优品种
    local bestBreeds = GeneDexDB.BestBreeds
    if not bestBreeds then
        return
    end
    local speciesData = bestBreeds[speciesID]
    if not speciesData or type(speciesData) ~= "table" then
        return
    end

    -- 收集该物种所有已标记的品种
    local lines = {}
    for breedID, breedData in pairs(speciesData) do
        if type(breedData) == "table" then
            local breedCode = GetBreedCode(breedID) or "?"
            local breedName = GetBreedDisplayName(breedID, breedCode)
            local categoryName = GetBestBreedCategoryName(breedData.category or "custom")
            lines[#lines + 1] = breedName .. " (" .. categoryName .. ")"
        end
    end

    if #lines == 0 then
        return
    end

    -- 添加 "最优品种: P/P(PvE), H/S(PvP)" 行
    local header = GetLocaleString("BEST_BREED_SECTION") .. ": "
    local infoText = table.concat(lines, ", ")
    tooltip:AddLine(header .. infoText, 1.0, 0.84, 0.0)
end

-- ============================================================================
-- 初始化
-- ============================================================================

--- 注册 Tooltip 回调（由 Core.lua 在 PLAYER_LOGIN 时调用）
function addonTable.InitTooltip()
    -- 注册 BattlePet 类型 Tooltip 回调
    TooltipDataProcessor_AddTooltipPostCall(
        Enum.TooltipDataType.BattlePet,
        OnBattlePetTooltip
    )

    -- 注册 Item 类型 Tooltip 回调（宠物笼物品）
    TooltipDataProcessor_AddTooltipPostCall(
        Enum.TooltipDataType.Item,
        OnItemTooltip
    )
end
