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

local type = type
local pairs = pairs

-- ============================================================================
-- API 返回字段自动探测（C_PetJournal.GetPetInfoBySpeciesID）
-- ============================================================================
-- 该 API 返回多个独立值（非 table 格式），位置随版本变化。
-- 策略：取所有 5-100 范围的数字（排除 petType=1-10 等），最后 3 个中最大的为 health。

-- 已探测到的基准属性位置缓存
local petInfoFields = nil  -- { healthIndex, powerIndex, speedIndex }

--- 运行时自动探测：在返回值数组中定位三围基准属性（5-100 范围数字）
--- @return healthIdx, powerIdx, speedIdx 或均为 nil
local function DetectPetInfoFields()
    if petInfoFields then
        return petInfoFields[1], petInfoFields[2], petInfoFields[3]
    end

    local values = {C_PetJournal.GetPetInfoBySpeciesID(39)}  -- 机械松鼠
    if #values == 0 then
        values = {C_PetJournal.GetPetInfoBySpeciesID(1)}
    end
    if #values == 0 then
        return nil, nil, nil
    end

    -- 收集 5-100 的值
    local nums = {}
    for i, v in ipairs(values) do
        if type(v) == "number" and v >= 5 and v <= 100 and v == math.floor(v) then
            nums[#nums + 1] = {i = i, v = v}
        end
    end

    if #nums < 3 then
        return nil, nil, nil
    end

    -- 取最后 3 个符合范围的值，其中最大的为 health
    local a, b, c = nums[#nums - 2], nums[#nums - 1], nums[#nums]
    local v1, v2, v3 = a.v, b.v, c.v

    if v1 >= v2 and v1 >= v3 then
        petInfoFields = {a.i, b.i, c.i}
    elseif v2 >= v1 and v2 >= v3 then
        petInfoFields = {b.i, a.i, c.i}
    else
        petInfoFields = {c.i, a.i, b.i}
    end

    return petInfoFields[1], petInfoFields[2], petInfoFields[3]
end

--- 从 API 返回值数组中提取三围基准属性
--- @param values table 数值数组
--- @return number|nil baseHealth, number|nil basePower, number|nil baseSpeed
local function ExtractBaseStats(values)
    if not values or type(values) ~= "table" or #values == 0 then
        return nil, nil, nil
    end
    local hIdx, pIdx, sIdx = DetectPetInfoFields()
    if not hIdx or not pIdx or not sIdx then
        return nil, nil, nil
    end
    return values[hIdx], values[pIdx], values[sIdx]
end

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
        return fmt:format(breedName)
    else
        -- 目标品种：品种: P/P 攻击型 🎯 PvP 对战
        local categoryName = GetBestBreedCategoryName(bestInfo.category or "custom")
        local fmt = GetLocaleString("BREED_TARGET_FORMAT")
        return fmt:format(breedName, categoryName)
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

    -- 获取物种基准属性（自动探测，不硬编码）
    -- C_PetJournal.GetPetInfoBySpeciesID 返回多个独立值，需打包为数组
    local allValues = {C_PetJournal.GetPetInfoBySpeciesID(speciesID)}
    if #allValues == 0 then
        return
    end

    local baseHealth, basePower, baseSpeed = ExtractBaseStats(allValues)
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
    -- 运行时检测 TooltipDataProcessor API 是否存在（10.0+）
    if not TooltipDataProcessor
        or not TooltipDataProcessor.AddTooltipPostCall
        or type(TooltipDataProcessor.AddTooltipPostCall) ~= "function"
    then
        -- 旧版客户端，静默跳过（Interface 版本号会阻止加载，此检查为额外防护）
        return
    end

    -- 检测 TooltipDataType 枚举是否存在
    if not Enum or not Enum.TooltipDataType then
        return
    end

    -- 注册 BattlePet 类型 Tooltip 回调
    if Enum.TooltipDataType.BattlePet then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.BattlePet,
            OnBattlePetTooltip
        )
    end

    -- 注册 Item 类型 Tooltip 回调（宠物笼物品）
    if Enum.TooltipDataType.Item then
        TooltipDataProcessor.AddTooltipPostCall(
            Enum.TooltipDataType.Item,
            OnItemTooltip
        )
    end
end
