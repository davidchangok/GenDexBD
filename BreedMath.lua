-- GenDexBD BreedMath.lua
-- 品种推算引擎：纯函数模块，无副作用、无 UI 依赖、可独立测试
-- 加载顺序：第3个（依赖 BreedData.lua 的数据表）
--
-- 核心公式：
--   最终属性 = 物种基础属性 × 品种系数 × 品质修正 × 等级缩放
--   反推：观测品种系数 = 实际属性 / (物种基础属性 × 品质修正 × 等级缩放)
--   等级缩放：LevelFactor = 1 + (level - 1) × LEVEL_SCALE_FACTOR

local addonName, addonTable = ...

-- ============================================================================
-- 文件作用域 local 化（WoW Lua 性能优化）
-- ============================================================================

local BREEDS = addonTable.BREEDS
local QUALITY_MULTIPLIER = addonTable.QUALITY_MULTIPLIER
local BREED_AMBIGUITY = addonTable.BREED_AMBIGUITY

local ipairs = ipairs
local pairs = pairs
local type = type
local math_abs = math.abs

-- ============================================================================
-- 常量
-- ============================================================================

local MAX_TOLERANCE = 0.15      -- 精确推算最大容差（欧氏距离的平方）
local RATIO_TOLERANCE = 0.30     -- 比例估算最大容差（欧氏距离的平方）
local DEFAULT_QUALITY = 4        -- 默认品质：精良(Rare)
local LEVEL_SCALE_FACTOR = 0.2   -- 等级缩放因子：1 + (level-1) * 0.2
local DEFAULT_LEVEL = 1          -- 最低有效等级

-- 预计算：将 BREEDS 表转为扁平数组以加速匹配循环（避免 pairs 遍历的哈希开销）
-- 格式: { { breedID, h, p, s }, ... }
local breedList = {}
for breedID = 3, 14 do
    local breed = BREEDS[breedID]
    if breed then
        breedList[#breedList + 1] = { breedID, breed[1], breed[2], breed[3] }
    end
end

-- ============================================================================
-- 内部辅助函数
-- ============================================================================

--- 输入验证：检查数值是否为正数
--- @param ... number 要检查的数值
--- @return boolean 是否全部有效
local function IsValidPositive(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or v <= 0 or v ~= v then  -- 最后一项检查 NaN
            return false
        end
    end
    return true
end

--- 计算观测品种系数与理论品种系数之间的欧氏距离的平方
--- @param obsH number 观测生命系数
--- @param obsP number 观测攻击系数
--- @param obsS number 观测速度系数
--- @param breedH number 理论生命系数
--- @param breedP number 理论攻击系数
--- @param breedS number 理论速度系数
--- @return number 欧氏距离的平方
local function DistanceSquared(obsH, obsP, obsS, breedH, breedP, breedS)
    local dH = obsH - breedH
    local dP = obsP - breedP
    local dS = obsS - breedS
    return dH * dH + dP * dP + dS * dS
end

--- 在品种列表中查找最小距离的品种
--- @param obsH number 观测生命系数
--- @param obsP number 观测攻击系数
--- @param obsS number 观测速度系数
--- @param tolerance number 容差阈值
--- @return number|nil breedID 最匹配的品种ID，超出容差则返回 nil
local function FindBestMatch(obsH, obsP, obsS, tolerance)
    local bestBreedID = nil
    local bestDist = math.huge

    for _, breed in ipairs(breedList) do
        local breedID, h, p, s = breed[1], breed[2], breed[3], breed[4]
        local dist = DistanceSquared(obsH, obsP, obsS, h, p, s)

        if dist < bestDist then
            bestDist = dist
            bestBreedID = breedID
        elseif dist == bestDist then
            -- 系数完全相同时的歧义处理
            -- 检查歧义表，优先使用非歧义品种
            local preferred = BREED_AMBIGUITY[bestBreedID]
            local otherPreferred = BREED_AMBIGUITY[breedID]
            if otherPreferred then
                -- 当前 breedID 是歧义品种，使用 preferred 替换
                bestBreedID = otherPreferred
            elseif preferred then
                -- 当前最佳是歧义品种，用 preferred（非歧义值）替换
                bestBreedID = preferred
            end
            -- 如果都没有歧义声明，保持第一个匹配的
        end
    end

    -- 容差检查
    if bestDist > tolerance then
        return nil
    end

    return bestBreedID
end

--- 计算等级缩放因子
--- @param level number 宠物等级
--- @return number
local function GetLevelFactor(level)
    local lv = level
    if type(lv) ~= "number" or lv < 1 then
        lv = DEFAULT_LEVEL
    end
    return 1 + (lv - 1) * LEVEL_SCALE_FACTOR
end

--- 获取品质修正系数，找不到则返回默认值
--- @param quality number 品质ID
--- @return number
local function GetQualityMultiplier(quality)
    return QUALITY_MULTIPLIER[quality] or QUALITY_MULTIPLIER[DEFAULT_QUALITY]
end

-- ============================================================================
-- 公开 API
-- ============================================================================

--- 精确推算品种（需要物种基准属性数据）
--- 用于宠物手册等已知物种信息的场景
--- @param health    number 当前生命值
--- @param power     number 当前攻击值
--- @param speed     number 当前速度值
--- @param baseHealth number 物种基础生命值
--- @param basePower  number 物种基础攻击值
--- @param baseSpeed  number 物种基础速度值
--- @param level     number 宠物等级
--- @param quality   number 宠物品质ID (1-6)
--- @return number|nil breedID 品种ID，无法确定返回 nil
--- @return string|nil 附加信息（"exact" 表示精确匹配，nil 表示失败）
function addonTable.CalculateBreedFromStats(health, power, speed,
                                             baseHealth, basePower, baseSpeed,
                                             level, quality)
    -- 输入验证
    if not IsValidPositive(health, power, speed,
                           baseHealth, basePower, baseSpeed) then
        return nil
    end

    -- 计算等级缩放和品质修正
    local levelFactor = GetLevelFactor(level)
    local qualityMult = GetQualityMultiplier(quality)

    -- 反推观测品种系数
    local denominator = qualityMult * levelFactor
    local obsH = health / (baseHealth * denominator)
    local obsP = power  / (basePower  * denominator)
    local obsS = speed  / (baseSpeed  * denominator)

    -- 匹配品种
    local breedID = FindBestMatch(obsH, obsP, obsS, MAX_TOLERANCE)
    return breedID
end

--- 比例估算品种（仅需要当前属性，无需基准数据）
--- 用于战斗中等无法获取物种基准属性的场景
--- @param health number 当前生命值
--- @param power  number 当前攻击值
--- @param speed  number 当前速度值
--- @return number|nil breedID 品种ID，无法确定返回 nil
function addonTable.GuessBreedByRatio(health, power, speed)
    -- 输入验证
    if not IsValidPositive(health, power, speed) then
        return nil
    end

    -- 三围比例归一化：将原始属性映射到与品种系数相同的尺度
    local total = health + power + speed
    if total <= 0 then
        return nil
    end

    local scale = 3.0 / total
    local obsH = health * scale
    local obsP = power  * scale
    local obsS = speed  * scale

    local breedID = FindBestMatch(obsH, obsP, obsS, RATIO_TOLERANCE)
    return breedID
end

--- 获取品种短代码（如 "P/P", "H/S"）
--- @param breedID number 品种ID
--- @return string|nil 短代码，无效ID返回 nil
function addonTable.GetBreedCode(breedID)
    local breed = BREEDS[breedID]
    if not breed then
        return nil
    end

    local primary = breed[4]   -- 主代码
    local secondary = breed[5] -- 副代码

    if not primary or not secondary then
        return nil
    end

    return primary .. "/" .. secondary
end
