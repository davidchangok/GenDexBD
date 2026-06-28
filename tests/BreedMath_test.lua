-- GenDexBD BreedMath 单元测试
-- 纯函数测试：无需 WoW 运行环境，可在标准 Lua 5.1+ 解释器中运行
-- 用法: lua tests/BreedMath_test.lua (需要同目录下的 BreedData + BreedMath 代码内联)
--
-- 在 WoW 内运行: /run GenDexBD_RunTests()
-- 测试函数由 GenDexBD Core 在 PLAYER_LOGIN 后挂载到 _G

local _G = _G or {}
local addonName = "GenDexBD"

-- 模拟 addonTable（测试环境使用 addonTable 约定）
local addonTable = {}

-- ============================================================================
-- 内联 BreedData（模拟 BreedData.lua 的纯数据部分）
-- ============================================================================
addonTable.QUALITY_MULTIPLIER = {
    [1] = 1.0, [2] = 1.1, [3] = 1.2, [4] = 1.3, [5] = 1.4, [6] = 1.5,
}

addonTable.BREEDS = {
    [3]  = { 1.0, 1.0, 1.0, "B", "B" },
    [4]  = { 0.4, 1.8, 0.8, "P", "P" },
    [5]  = { 0.4, 0.8, 1.8, "S", "S" },
    [6]  = { 1.8, 0.4, 0.8, "H", "H" },
    [7]  = { 1.4, 1.4, 0.2, "H", "P" },
    [8]  = { 0.8, 1.4, 0.8, "P", "S" },
    [9]  = { 1.4, 0.2, 1.4, "H", "S" },
    [10] = { 0.8, 1.4, 0.8, "P", "B" },
    [11] = { 0.8, 0.4, 1.6, "S", "B" },
    [12] = { 1.2, 0.8, 1.0, "H", "B" },
    [13] = { 1.2, 1.2, 0.6, "P", "H" },
    [14] = { 1.2, 0.6, 1.2, "H", "S" },
}

addonTable.BREED_AMBIGUITY = {
    [10] = 8,
}

-- ============================================================================
-- 内联 BreedMath（从 BreedMath.lua 提取核心逻辑，去掉 addonTable 依赖）
-- ============================================================================
local BREEDS = addonTable.BREEDS
local QUALITY_MULTIPLIER = addonTable.QUALITY_MULTIPLIER
local BREED_AMBIGUITY = addonTable.BREED_AMBIGUITY

local MAX_TOLERANCE = 0.15
local RATIO_TOLERANCE = 0.30
local DEFAULT_QUALITY = 4
local LEVEL_SCALE_FACTOR = 0.2
local DEFAULT_LEVEL = 1

-- 预计算 breedList
local breedList = {}
for breedID = 3, 14 do
    local breed = BREEDS[breedID]
    if breed then
        breedList[#breedList + 1] = { breedID, breed[1], breed[2], breed[3] }
    end
end

local function IsValidPositive(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or v <= 0 or v ~= v then  -- 最后一项检查 NaN (v ~= v 仅在 NaN 时为 true)
            return false
        end
    end
    return true
end

local function DistanceSquared(obsH, obsP, obsS, breedH, breedP, breedS)
    local dH = obsH - breedH
    local dP = obsP - breedP
    local dS = obsS - breedS
    return dH * dH + dP * dP + dS * dS
end

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
            -- 双向检查歧义处理（修复后：不依赖迭代顺序）
            local preferred = BREED_AMBIGUITY[bestBreedID]
            local otherPreferred = BREED_AMBIGUITY[breedID]
            if otherPreferred then
                bestBreedID = otherPreferred
            elseif preferred then
                bestBreedID = preferred
            end
        end
    end

    if bestDist > tolerance then
        return nil
    end
    return bestBreedID
end

local function GetLevelFactor(level)
    local lv = level
    if type(lv) ~= "number" or lv < 1 then
        lv = DEFAULT_LEVEL
    end
    return 1 + (lv - 1) * LEVEL_SCALE_FACTOR
end

local function GetQualityMultiplier(quality)
    return QUALITY_MULTIPLIER[quality] or QUALITY_MULTIPLIER[DEFAULT_QUALITY]
end

-- BreedMath 公开 API
local function CalculateBreedFromStats(health, power, speed,
                                        baseHealth, basePower, baseSpeed,
                                        level, quality)
    if not IsValidPositive(health, power, speed, baseHealth, basePower, baseSpeed) then
        return nil
    end
    local levelFactor = GetLevelFactor(level)
    local qualityMult = GetQualityMultiplier(quality)
    local denominator = qualityMult * levelFactor
    local obsH = health / (baseHealth * denominator)
    local obsP = power  / (basePower  * denominator)
    local obsS = speed  / (baseSpeed  * denominator)
    local breedID = FindBestMatch(obsH, obsP, obsS, MAX_TOLERANCE)
    return breedID
end

local function GuessBreedByRatio(health, power, speed)
    if not IsValidPositive(health, power, speed) then
        return nil
    end
    local total = health + power + speed
    if total <= 0 then return nil end
    local scale = 3.0 / total
    local obsH = health * scale
    local obsP = power  * scale
    local obsS = speed  * scale
    local breedID = FindBestMatch(obsH, obsP, obsS, RATIO_TOLERANCE)
    return breedID
end

local function GetBreedCode(breedID)
    local breed = BREEDS[breedID]
    if not breed then return nil end
    local primary, secondary = breed[4], breed[5]
    if not primary or not secondary then return nil end
    return primary .. "/" .. secondary
end

-- ============================================================================
-- 测试框架
-- ============================================================================
local passed, failed = 0, 0

local function assert_equal(actual, expected, test_name)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        local a = tostring(actual or "nil")
        local e = tostring(expected or "nil")
        print(string.format("  ❌ 失败: %s — 期望=%s  实际=%s", test_name, e, a))
    end
end

local function assert_not_nil(value, test_name)
    if value ~= nil then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("  ❌ 失败: %s — 期望非 nil，实际 nil", test_name))
    end
end

local function assert_nil(value, test_name)
    if value == nil then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("  ❌ 失败: %s — 期望 nil，实际=%s", test_name, tostring(value)))
    end
end

local function run_section(name)
    print(string.format("── %s ──", name))
end

-- ============================================================================
-- 测试用例
-- ============================================================================
print("═" .. string.rep("═", 30))
print("GenDexBD BreedMath 单元测试")
print("═" .. string.rep("═", 30))

-- ---------- GetBreedCode ----------
run_section("GetBreedCode 品种代码获取")

assert_equal(GetBreedCode(3),  "B/B", "Breed 3 → B/B")
assert_equal(GetBreedCode(4),  "P/P", "Breed 4 → P/P")
assert_equal(GetBreedCode(5),  "S/S", "Breed 5 → S/S")
assert_equal(GetBreedCode(6),  "H/H", "Breed 6 → H/H")
assert_equal(GetBreedCode(7),  "H/P", "Breed 7 → H/P")
assert_equal(GetBreedCode(8),  "P/S", "Breed 8 → P/S")
assert_equal(GetBreedCode(9),  "H/S", "Breed 9 → H/S")
assert_equal(GetBreedCode(10), "P/B", "Breed 10 → P/B")
assert_equal(GetBreedCode(11), "S/B", "Breed 11 → S/B")
assert_equal(GetBreedCode(12), "H/B", "Breed 12 → H/B")
assert_equal(GetBreedCode(13), "P/H", "Breed 13 → P/H")
assert_equal(GetBreedCode(14), "H/S", "Breed 14 → H/S")
assert_nil(GetBreedCode(1),  "不存在的 Breed 1 → nil")
assert_nil(GetBreedCode(99), "不存在的 Breed 99 → nil")

-- ---------- IsValidPositive 边界 ----------
run_section("IsValidPositive 输入验证")

assert_equal(IsValidPositive(100, 80, 60), true, "正常正数 → true")
assert_equal(IsValidPositive(0, 80, 60), false, "含 0 → false")
assert_equal(IsValidPositive(-1, 80, 60), false, "含负数 → false")
assert_equal(IsValidPositive(100), true, "单参数 → true")

-- ---------- CalculateBreedFromStats 精确推算 ----------
run_section("CalculateBreedFromStats 精确推算")

-- 已知品种测试: 机械小鸡 (speciesID=39), 25级, 蓝色品质
-- 基础属性约: 1546/276/276 (life/power/speed 在 level 1)
-- 精确推算需要基准属性数据，这里测试函数结构即可

-- breed 4 (P/P): 系数 0.4/1.8/0.8
-- 如果 base: health=100, power=100, speed=100, level=25, quality=4
-- 期望: obs coefficients ≈ 0.4/1.8/0.8
-- levelFactor = 1+24*0.2=5.8, qualityMult=1.3, denominator=7.54
-- health = 100*0.4*7.54=301.6, power=100*1.8*7.54=1357.2, speed=100*0.8*7.54=603.2
local b4 = CalculateBreedFromStats(302, 1357, 603, 100, 100, 100, 25, 4)
assert_equal(b4, 4, "精确推算: 属性对应 P/P (breed 4)")

-- breed 8 (P/S): 系数 0.8/1.4/0.8 (与 breed 10 相同)
-- health=100*0.8*7.54=603, power=100*1.4*7.54=1056, speed=100*0.8*7.54=603
local b8 = CalculateBreedFromStats(603, 1056, 603, 100, 100, 100, 25, 4)
assert_equal(b8, 8, "精确推算: 歧义品种 P/S vs P/B → 应返回 8 (BREED_AMBIGUITY)")

-- breed 9 (H/S 旧版): 系数 1.4/0.2/1.4
-- health=100*1.4*7.54=1056, power=100*0.2*7.54=151, speed=100*1.4*7.54=1056
local b9 = CalculateBreedFromStats(1056, 151, 1056, 100, 100, 100, 25, 4)
assert_equal(b9, 9, "精确推算: 属性对应 Breed 9 (旧版 H/S)")

-- breed 14 (H/S 新版): 系数 1.2/0.6/1.2 — 应能区分 Breed 9
-- health=100*1.2*7.54=905, power=100*0.6*7.54=452, speed=100*1.2*7.54=905
local b14 = CalculateBreedFromStats(905, 452, 905, 100, 100, 100, 25, 4)
assert_equal(b14, 14, "精确推算: 属性对应 Breed 14 (新版 H/S) — 应与 Breed 9 区分")

-- 超出容差应返回 nil
local bnil = CalculateBreedFromStats(9999, 9999, 9999, 100, 100, 100, 25, 4)
assert_nil(bnil, "精确推算: 极端异常属性 → nil")

-- 无效输入应返回 nil
local binv1 = CalculateBreedFromStats(0, 100, 100, 100, 100, 100, 25, 4)
assert_nil(binv1, "精确推算: health=0 → nil")
local binv2 = CalculateBreedFromStats(100, -10, 100, 100, 100, 100, 25, 4)
assert_nil(binv2, "精确推算: power 负数 → nil")

-- NaN 检测 (0/0 在 Lua 中产生 NaN)
local binv3 = CalculateBreedFromStats(0/0, 100, 100, 100, 100, 100, 25, 4)
assert_nil(binv3, "精确推算: NaN 输入 → nil")

-- ---------- GuessBreedByRatio 比例估算 ----------
run_section("GuessBreedByRatio 比例估算")

-- breed 3 (B/B): 系数比例 1:1:1
-- 归一化后 obs: 1.0, 1.0, 1.0
local g3 = GuessBreedByRatio(100, 100, 100)
assert_equal(g3, 3, "比例估算: 均等三围 → B/B (breed 3)")

-- breed 5 (S/S): 系数 0.4/0.8/1.8, 比例归一化大致为 1:2:4.5 or 0.44/0.89/2.0
-- speed 占比最高
local g5 = GuessBreedByRatio(44, 89, 200)
assert_equal(g5, 5, "比例估算: 高速三围 → S/S (breed 5)")

-- breed 6 (H/H): 系数 1.8/0.4/0.8, health 占比最高
local g6 = GuessBreedByRatio(180, 40, 80)
assert_equal(g6, 6, "比例估算: 高血量三围 → H/H (breed 6)")

-- 无效输入
local gnil1 = GuessBreedByRatio(0, 0, 0)
assert_nil(gnil1, "比例估算: 全零 → nil")
local gnil2 = GuessBreedByRatio(-1, 50, 50)
assert_nil(gnil2, "比例估算: 负数 → nil")

-- ---------- 品级缩放一致性 ----------
run_section("品级缩放一致性")

-- 不同等级的同品种宠物应推算相同 breedID (品质一致)
local r1 = CalculateBreedFromStats(302, 1357, 603, 100, 100, 100, 25, 4)
local r2 = CalculateBreedFromStats(164, 738, 328, 100, 100, 100, 15, 4)
assert_equal(r1, r2, "品级一致: 25级和15级 P/P → breed 一致")

-- 不同品质的同品种宠物（默认品质=4 推算）
local r3 = CalculateBreedFromStats(278, 1248, 555, 100, 100, 100, 25, 3)
assert_equal(r3, 4, "品质回退: 绿色品质用品质4推算 → 仍推算正确")

-- ---------- 歧义处理健壮性 ----------
run_section("歧义处理健壮性")

-- Breed 8 和 Breed 10 系数完全相同: {0.8, 1.4, 0.8}
-- 无论 breedList 构建顺序如何，歧义处理都应返回 8
local amb_result = CalculateBreedFromStats(603, 1056, 603, 100, 100, 100, 25, 4)
assert_equal(amb_result, 8, "歧义处理: P/S vs P/B → 始终返回 8 (BREED_AMBIGUITY[10]=8)")

-- ============================================================================
-- 结果汇总
-- ============================================================================
print("")
print("═" .. string.rep("═", 30))
local total = passed + failed
print(string.format("测试结果: %d/%d 通过", passed, total))
if failed > 0 then
    print(string.format("❌ %d 个测试失败", failed))
else
    print("✅ 全部通过!")
end
print("═" .. string.rep("═", 30))

-- 返回退出码（方便 CI 集成）
if failed > 0 then
    os.exit(1)
end
