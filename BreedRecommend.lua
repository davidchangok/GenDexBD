-- GenDexBD BreedRecommend.lua
-- 智能品种推荐引擎：技能标签 + 动态权重 + 运行时自动分类
-- 加载顺序：第5个（依赖 BreedData + Data_SkillTags，被 JournalUI 调用）
--
-- 双层技能分类：
--   Layer 1: Data_SkillTags.lua 静态标签库（精标 + FORCE_* 覆盖）
--   Layer 2: 运行时 API 读描述 → 公式过滤 → 关键词匹配 → 缓存
--   FORCE_* 标签仅通过 Layer 1 生效
--
--   SCALES_POWER 仅标记超线性技能（多段/DoT/斩杀/增幅），
--   普通单段攻击不在此列（攻击属性自然缩放，无需品种引导）。
--
-- 评分：品种系数直接计算（API 不再暴露基准属性）

local addonName, addonTable = ...

local BREEDS = addonTable.BREEDS
local SkillTags = addonTable.SkillTags
local ipairs, pairs, type = ipairs, pairs, type
local tsort, mfloor = table.sort, math.floor
local sfind, slower = string.find, string.lower

-- ============================================================================
-- 常量
-- ============================================================================

local SPEED_THRESHOLDS = {0.8, 1.0, 1.2, 1.4}
local SPEED_BONUS = { [0.8]=1.0, [1.0]=1.1, [1.2]=1.25, [1.4]=1.4 }

local W_BASE  = 1.0
local W_SPEED = 0.7   -- NEEDS_SPEED 标签加成（降为0.7防碾压SCALES_HEALTH）
local W_POWER = 0.5   -- SCALES_POWER 加成（超线性技能）
local W_HEALTH = 0.9   -- SCALES_HEALTH 加成（PvE坦克生存技;因HP_VALUE=0.67折扣,需高于W_SPEED）
local W_FORCE = 3.0
local W_COMMUNITY = 1.5  -- 社区例外加权（软覆盖，远小于 FORCE=3.0）
                          -- 1.5 × 100 = 150分加成，翻转中等差距的排名
local SCALE = 100
local HP_VALUE = 0.67 -- 生命系数等价比（1生命 ≈ 0.67攻击/速度）
                       -- 来源：NGA 5.0实测数据 "能量0.1:速度0.1≈生命0.15"

local FAMILY_MOD = {
    -- 1型: 人型 — 攻击回血4% → 偏攻击
    [1]  = { h=1.0, p=1.15, s=1.0 },
    -- 2型: 龙类 — 敌方<50%伤害+50% → 偏攻击(斩杀)
    [2]  = { h=1.0, p=1.15, s=1.0 },
    -- 3型: 飞行 — >50%HP速度+50% → 偏速度
    [3]  = { h=1.0, p=1.0, s=1.3 },
    -- 4型: 亡灵 — 死亡复活一回合 → 偏攻击
    [4]  = { h=1.0, p=1.3, s=1.0 },
    -- 5型: 小动物 — CC减免 → 均衡偏坦
    [5]  = { h=1.1, p=1.0, s=1.0 },
    -- 6型: 魔法 — 单次伤害≤35%HP → 慢速高血
    [6]  = { h=1.3, p=1.0, s=0.8 },
    -- 7型: 元素 — 无视天气负面 → 均衡(策略型)
    [7]  = { h=1.0, p=1.0, s=1.0 },
    -- 8型: 野兽 — <50%HP伤害+25% → 战术操作,非品种引导
    [8]  = { h=1.0, p=1.0, s=1.0 },
    -- 9型: 水栖 — DoT减免 → 均衡偏攻(治疗波/净化雨攻击缩放)
    [9]  = { h=1.0, p=1.1, s=1.0 },
    -- 10型:机械 — 复活20%HP一次 → 偏攻击
    [10] = { h=1.0, p=1.2, s=1.0 },
}

-- ============================================================================
-- 社区例外加权表（speciesID → 社区偏好的单属性 "H"/"P"/"S"）
-- 软覆盖机制：加成 W_COMMUNITY 到偏好属性权重，乘以品种系数
-- 远小于 FORCE(3.0)，仅用于翻转差距较小的排名
-- 社区共识来源：WarcraftPets 论坛/评论区（详见 memory/community-breed-consensus.md）
-- ============================================================================
local COMMUNITY_BREED_BONUS = {
    [438] = "H",  -- 王蛇: H/H社区首选,高血量+野兽被动+毒牙递增
    [406] = "H",  -- 甲虫: H/H天启战术首选,需活到陨星落下(1806血)
    [374] = "H/P",-- 黑羔羊: H/P社区首选,高血高攻+Chew+Comeback+Stampede
    [478] = "H/S",-- 森林蛾: H/S社区首选,Cocoon Strike>速度技,需血量维持飞行被动
    [1749] = "S", -- Death Adder: S/S社区共识,341速致盲剧毒+Puncture Wound双倍
    [548] = "P", -- 蛮锤狮鹫: P/P社区"no-brainer",仅3种鸟有P/P,切削之风+群殴多段爆发
    [500] = "H", -- 迷你地狱火: H/H社区共识,自爆HP%+魔法锁血+强化护甲
}

-- ============================================================================
-- Layer 2: 自动分类关键词（精炼版）
-- ============================================================================
-- 关键词从 Locales.lua 的 addonTable.AUTO_TAG_KEYWORDS 读取
-- 按客户端语种自动选择 zhCN 或 enUS
local AUTO_TAGS = (function()
    local kw = addonTable.AUTO_TAG_KEYWORDS
    local key = (GetLocale() == "zhCN" or GetLocale() == "zhTW") and "zhCN" or "enUS"
    return {
        NEEDS_SPEED   = kw.NEEDS_SPEED[key],
        SCALES_POWER  = kw.SCALES_POWER[key],
        SCALES_HEALTH = kw.SCALES_HEALTH[key],
    }
end)()

local autoTagCache = {}
local speciesBuildCache = {}

-- ============================================================================
-- 否定词过滤：防止过匹配（如"阻止回复生命"误匹配SCALES_HEALTH）
-- ============================================================================
-- 每个标签可定义否定模式列表，句子匹配否定模式时跳过该标签的正向匹配
local NEGATE_PATTERNS = {
    SCALES_HEALTH = {
        -- 中文：否定回复/治疗 → 这是debuff不是治疗技能
        "阻止.*回复", "无法.*回复", "不能.*回复", "禁止.*回复",
        "不会.*回复", "不再.*回复", "防止.*回复",
        "阻止.*治疗", "无法.*治疗", "不能.*治疗", "禁止.*治疗",
        "阻止.*治愈", "无法.*治愈",
        -- 中文：伤害降低→对方debuff非自身防御
        "使.*目标.*伤.*降低", "降低.*目标.*伤",
        -- 英文：否定heal/restore → debuff, not a healing ability
        "prevent.*heal", "prevent.*restore", "prevent.*recover",
        "cannot.*heal", "unable.*heal", "stop.*heal",
        "block.*heal", "block.*restore",
        -- 英文：enemy debuff → not self-defense
        "enemy.*deal.*less", "reduce.*enemy.*damage", "target.*deal.*less",
    },
    SCALES_POWER = {
        -- 中文："受到攻击时.*提升速度" → 被攻击触发，非自身增幅
        "受到.*攻击.*速度",
        "受到.*攻击.*闪避",
        -- 英文："when attacked.*speed" → reactive, not self-amplify
        "when.*attacked.*speed",
        "when.*struck.*speed",
    },
}

-- ============================================================================
-- 内部函数
-- ============================================================================

local function AutoClassify(abilityID)
    if autoTagCache[abilityID] ~= nil then return autoTagCache[abilityID] end
    if not C_PetBattles or not C_PetBattles.GetAbilityInfoByID then
        autoTagCache[abilityID] = false; return nil
    end
    local ok, _, name, _, _, desc = pcall(C_PetBattles.GetAbilityInfoByID, abilityID)
    if not ok or not desc then autoTagCache[abilityID] = false; return nil end

    -- 技能名 + 描述合并匹配（名中的关键词也参与：钻地/猛击等）
    local text = slower(name .. " " .. desc)

    -- 过滤 [...] 公式标记（替换为空格，保留上下文连续性）
    local cleaned, depth = "", 0
    for i = 1, #text do
        local c = text:sub(i, i)
        if c == "[" then depth = depth + 1
        elseif c == "]" and depth > 0 then depth = depth - 1
        elseif depth == 0 then cleaned = cleaned .. c
        end
    end
    cleaned = cleaned:gsub("%s+", " ")

    -- 按中文句号。换行分割（UTF-8 safe：gsub 按字节序列匹配，而不是 [^。] 数组）
    -- Lua 5.1 的 [^。] 对多字节字符无效，因为它是逐字节匹配的
    cleaned = cleaned:gsub("。", "\n")
    local tags = {}
    for tag, patterns in pairs(AUTO_TAGS) do
        for _, pat in ipairs(patterns) do
            for sentence in cleaned:gmatch("[^\n]+") do
                -- 先检查否定模式：句子含否定词则跳过此句的该标签匹配
                local negated = false
                local negList = NEGATE_PATTERNS[tag]
                if negList then
                    for _, negPat in ipairs(negList) do
                        if sfind(sentence, negPat) then
                            negated = true; break
                        end
                    end
                end
                if not negated and sfind(sentence, pat) then
                    tags[tag] = true; break
                end
            end
            if tags[tag] then break end
        end
    end
    if next(tags) then autoTagCache[abilityID] = tags; return tags end
    autoTagCache[abilityID] = false
    return nil
end

-- ============================================================================
-- 配招枚举：按槽位分组 + 枚举合法配招（解决幽灵配招问题）
-- ============================================================================
-- API返回顺序: at[1]=slot1主, at[2]=slot2主, at[3]=slot3主
--               at[4]=slot1副, at[5]=slot2副, at[6]=slot3副

-- 槽位分组
local function GroupAbilitiesBySlot(flatList)
    local slots = {}
    local count = #flatList
    for i = 1, 3 do
        local opts = {}
        if flatList[i] and flatList[i] > 0 then opts[#opts+1] = flatList[i] end
        if count >= i+3 and flatList[i+3] and flatList[i+3] > 0
           and flatList[i+3] ~= flatList[i] then
            opts[#opts+1] = flatList[i+3]
        end
        slots[i] = opts
    end
    return slots
end

-- 枚举所有合法配招（递归回溯，最多 2³=8 种）
local function EnumerateBuilds(slots)
    local builds = {}
    local function backtrack(slotIdx, chosen)
        if slotIdx > 3 then
            builds[#builds+1] = { abilities = {chosen[1], chosen[2], chosen[3]} }
            return
        end
        for _, aid in ipairs(slots[slotIdx]) do
            chosen[slotIdx] = aid
            backtrack(slotIdx + 1, chosen)
        end
    end
    backtrack(1, {})
    return builds
end

-- 计算单个配招的标签（复用 SkillTags + AutoClassify）
local function ComputeBuildTags(build)
    local tc = {}
    for _, aid in ipairs(build.abilities) do
        local tags = SkillTags[aid] or AutoClassify(aid)
        if tags then
            for tag in pairs(tags) do
                tc[tag] = (tc[tag] or 0) + 1
            end
        end
    end
    return tc
end

-- 获取技能名（调试用）
local function GetAbilityName(aid)
    local _, _, aname = pcall(C_PetBattles.GetAbilityInfoByID, aid)
    return aname or "?"
end

-- ============================================================================
-- 评分函数（前置: CollectTags 引用 Score 选最佳配招）
-- ============================================================================

local function SpeedBonus(s_coef)
    local b = 1.0
    for _, t in ipairs(SPEED_THRESHOLDS) do
        if s_coef >= t then b = SPEED_BONUS[t] end
    end
    if s_coef < SPEED_THRESHOLDS[1] then b = 0.5 end
    return b
end

local function GetPetType(speciesID)
    local vals = {C_PetJournal.GetPetInfoBySpeciesID(speciesID)}
    if #vals >= 3 then
        local v = vals[3]
        if type(v) == "number" and v >= 1 and v <= 10 and v == mfloor(v) then return v end
    end
    return nil
end

local function Score(h, p, s, tc, pt)
    -- 家族被动修正基础权重(不是只修正NEEDS_SPEED)
    --   飞行: >50%HP时速度+50% → ws偏高
    --   亡灵: 死亡复活一回合 → wp偏高
    --   魔法: 单次伤害≤35%HP → wh偏高, ws偏低
    --   野兽: <50%HP时增伤 → wh偏高(存活力)
    --   机械: 死亡复活一次 → wp偏高
    local fm = FAMILY_MOD[pt] or {h=1.0, p=1.0, s=1.0}

    local wh = (W_BASE + W_HEALTH * (tc["SCALES_HEALTH"] or 0)) * fm.h
    local wp = (W_BASE + W_POWER  * (tc["SCALES_POWER"]  or 0)) * fm.p
    local ws_base  = W_BASE * fm.s
    local ws_needs = W_SPEED * (tc["NEEDS_SPEED"] or 0) * fm.s

    if (tc["FORCE_PP"] or 0) > 0 then wp = wp + W_FORCE * p end
    if (tc["FORCE_SS"] or 0) > 0 then ws_needs = ws_needs + W_FORCE * s end
    if (tc["FORCE_HH"] or 0) > 0 then wh = wh + W_FORCE * h end

    local sb = 1.0
    if (tc["NEEDS_SPEED"] or 0) > 0 then sb = SpeedBonus(s) end

    local ws = ws_base
    if (tc["NEEDS_SPEED"] or 0) == 0 then ws = ws * 0.85 end  -- 弱化惩罚:坦克无需速度

    -- 生命等价比修正：1生命 ≈ 0.67攻击/速度（NGA 5.0实测 "0.1攻:0.1速≈0.15命"）
    -- 品种生命系数(0.2-1.8)需要打折后再参与评分
    local raw = wp * p + ws * s + ws_needs * sb + wh * h * HP_VALUE
    return raw * SCALE, {wh=wh,wp=wp,ws=ws,sb=sb,ws_base=ws_base,ws_needs=ws_needs}
end

local function CollectTags(speciesID)
    -- 缓存命中：直接返回最佳配招标签
    local cached = speciesBuildCache[speciesID]
    if cached then return cached.bestTagCounts end

    local results = { C_PetJournal.GetPetAbilityList(speciesID) }
    local at = results[1]
    if not at or type(at) ~= "table" then return {} end

    local slots = GroupAbilitiesBySlot(at)
    local builds = EnumerateBuilds(slots)

    -- 单配招宠物（1 build）：快速路径
    if #builds == 1 then
        local tc = ComputeBuildTags(builds[1])
        speciesBuildCache[speciesID] = {bestBuild=1, bestTagCounts=tc, allBuilds=builds, slots=slots}
        return tc
    end

    -- 多配招宠物（2-8 builds）：用B/B(3)中性分评估每个配招，选最优
    local bestBuildIdx, bestScore = 1, -1
    local neutH, neutP, neutS = 1.0, 1.0, 1.0  -- B/B 品种系数
    for idx, build in ipairs(builds) do
        local tc = ComputeBuildTags(build)
        local score = Score(neutH, neutP, neutS, tc, nil)  -- nil=无家族修正(用默认1.0)
        if score > bestScore then bestBuildIdx, bestScore = idx, score end
    end
    local bestTc = ComputeBuildTags(builds[bestBuildIdx])
    speciesBuildCache[speciesID] = {bestBuild=bestBuildIdx, bestTagCounts=bestTc,
                                     allBuilds=builds, slots=slots, bestScore=bestScore}
    return bestTc
end

-- ============================================================================
-- 公开 API + 诊断
-- ============================================================================

--- 诊断：打印物种所有技能详情（无条件输出，独立于评分流程）
--- @param speciesID number
--- @param petType number|nil 已知类型可传入，nil则自动查
function addonTable.DumpSpeciesAbilities(speciesID, petType)
    if not speciesID then return end
    if not petType then petType = GetPetType(speciesID) end
    local vals = {C_PetJournal.GetPetInfoBySpeciesID(speciesID)}
    local name = type(vals[1])=="string" and vals[1] or "?"

    -- 触发 CollectTags 以填充 speciesBuildCache
    local bestTc = CollectTags(speciesID)
    local cached = speciesBuildCache[speciesID]
    local slots = cached and cached.slots or {}
    local builds = cached and cached.allBuilds or {}

    -- 最佳配招标签摘要
    local parts = {}
    if bestTc and next(bestTc) then
        for tag, count in pairs(bestTc) do parts[#parts+1] = tag .. "×" .. count end
        table.sort(parts)
    end
    local suffix = (#builds > 1) and string.format(" (best of %d builds)", #builds) or ""
    print(string.format("[GenDexDBG] skills: pet=%s sid=%d  tags={%s}%s",
        name, speciesID, #parts>0 and table.concat(parts, ", ") or "", suffix))
    print("|cffffd700=== [GenDexDBG] speciesID=" .. tostring(speciesID) .. " (" .. name .. ") petType=" .. tostring(petType) .. " ===|r")

    -- 槽位分组输出（多配招宠物标槽位号）
    if #slots > 0 then
        for i = 1, 3 do
            if slots[i] and #slots[i] > 0 then
                local names = {}
                for _, aid in ipairs(slots[i]) do
                    names[#names+1] = string.format("[%d]%s", aid, GetAbilityName(aid))
                end
                print(string.format("  -- Slot %d: %s", i, table.concat(names, " | ")))
            end
        end
    end

    -- 再输出所有技能详情（按原格式，flat list）
    local at = ({ C_PetJournal.GetPetAbilityList(speciesID) })[1]
    if at and type(at) == "table" then
        for _, aid in pairs(at) do
            if type(aid) == "number" and aid > 0 then
                local _, _, aname, _, _, desc = pcall(C_PetBattles.GetAbilityInfoByID, aid)
                local stTags, acTags = SkillTags[aid], autoTagCache[aid]
                if acTags == false then acTags = nil end
                print(string.format("  aid=%d |%s|  desc=%s", aid, aname or "?", desc or "???"))
                if stTags then local tl={};for t in pairs(stTags)do tl[#tl+1]=t end; print("    -> Static: "..table.concat(tl,", ")) end
                if acTags then local tl={};for t in pairs(acTags)do tl[#tl+1]=t end; print("    -> Auto:   "..table.concat(tl,", ")) end
                if not stTags and not acTags then print("    -> NO TAGS MATCHED") end
            end
        end
    end
end

function addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, topN)
    if not speciesID then return {} end; if not petType then petType = GetPetType(speciesID) end

    -- 触发 CollectTags 以填充 speciesBuildCache（内部 GroupAbilitiesBySlot + EnumerateBuilds）
    local bestTc = CollectTags(speciesID)
    local cached = speciesBuildCache[speciesID]
    local builds = cached and cached.allBuilds or {}
    local bestBuildIdx = cached and cached.bestBuild or 1

    local doDebug = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
    if doDebug then
        addonTable.DumpSpeciesAbilities(speciesID, petType)
        -- 多配招时输出槽位 + 配招枚举 + 标签摘要
        if #builds > 1 then
            print("  Builds (" .. #builds .. " total):")
            for idx, build in ipairs(builds) do
                local names = {}
                for _, aid in ipairs(build.abilities) do
                    names[#names+1] = GetAbilityName(aid)
                end
                local btc = ComputeBuildTags(build)
                local btparts = {}
                if btc and next(btc) then
                    for tag, count in pairs(btc) do btparts[#btparts+1] = tag .. "×" .. count end
                    table.sort(btparts)
                end
                local marker = (idx == bestBuildIdx) and " ← best" or ""
                print(string.format("  B%d %s  tags={%s}%s",
                    idx, table.concat(names, "+"), table.concat(btparts, ", "), marker))
            end
            print("--- Per-breed best-build scores ---")
        end
        print("--- Final scores ---")
        print(string.format("  %-6s %8s %8s %8s %8s %8s %8s %8s", "Breed","Score","wH","wP","wS-Base","wS-Need","S-Bns","Raw"))
    end

    local breeds = {}
    if possibleBreedIDs and type(possibleBreedIDs)=="table" and #possibleBreedIDs>0 then
        for _,bid in ipairs(possibleBreedIDs)do if BREEDS[bid]then breeds[#breeds+1]=bid end end
    end
    if #breeds==0 then for bid=3,14 do if BREEDS[bid]then breeds[#breeds+1]=bid end end end

    local rs = {}
    for _,bid in ipairs(breeds)do
        local br = BREEDS[bid]
        if br then
            local h,p,s = br[1],br[2],br[3]
            local code = addonTable.GetBreedCode and addonTable.GetBreedCode(bid) or "?"

            -- 多配招枚举：每个品种取所有配招的最高分（对该品种最有利的配招）
            local bestScore, bestDetail, bestBIdx = -9999, nil, bestBuildIdx
            for idx, build in ipairs(builds) do
                local btc = ComputeBuildTags(build)
                local bscore, bdetail = Score(h, p, s, btc, petType)
                if bscore > bestScore then
                    bestScore, bestDetail, bestBIdx = bscore, bdetail, idx
                end
            end
            -- 无配招时用空标签降级（不应发生，但健壮处理）
            if not bestDetail then
                bestScore, bestDetail = Score(h, p, s, bestTc, petType)
            end

            local score = bestScore
            local detail = bestDetail

            -- 歧义品种扣1分: Breed 10(P/B)与8(P/S)系数完全相同,BreedData声明8优先
            if addonTable.BREED_AMBIGUITY and addonTable.BREED_AMBIGUITY[bid] then score = score - 1 end
            -- 社区例外加权：直接加分到社区共识偏好的品种
            -- commStat: 单字母"H"/"P"/"S"→纯品种H/H/P/P/S/S; 完整码"H/P"→直接匹配
            -- 软覆盖: W_COMMUNITY=1.5 × 100 = 150分，翻转较大差距的排名
            local commStat = COMMUNITY_BREED_BONUS[speciesID]
            local commBonus = 0
            if commStat then
                local targetCode
                if #commStat == 1 then
                    targetCode = commStat == "H" and "H/H" or commStat == "P" and "P/P" or commStat == "S" and "S/S" or nil
                else
                    targetCode = commStat  -- 完整品种码如 "H/P"
                end
                if targetCode and code == targetCode then
                    commBonus = W_COMMUNITY * SCALE
                    score = score + commBonus
                end
            end
            if doDebug then
                print(string.format("  %-6s %8d %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f",
                    code,mfloor(score+0.5),detail.wh,detail.wp,
                    detail.ws_base or 0,detail.ws_needs or 0,detail.sb,
                    detail.wp*p + detail.ws*s + (detail.ws_needs or 0)*detail.sb + detail.wh*h*HP_VALUE))
                if commBonus > 0 then
                    print(string.format("    ↑ +%d Community bonus (commStat=%s)", commBonus, commStat))
                end
            end
            -- tagCounts 反映该品种最优配招的实际标签
            local breedBtc = (bestBIdx > 0 and builds[bestBIdx]) and ComputeBuildTags(builds[bestBIdx]) or bestTc
            rs[#rs+1]={breedID=bid,score=mfloor(score+0.5),breedCode=code,
                       stats={h_coef=h,p_coef=p,s_coef=s},details=detail,tagCounts=breedBtc}
        end
    end

    tsort(rs, function(a,b)return a.score>b.score end)
    topN=topN or 3
    if #rs>topN then local t={};for i=1,topN do t[i]=rs[i]end;return t end
    return rs
end

function addonTable.RecommendBestBreed(speciesID,petType,possibleBreedIDs)
    local rs = addonTable.CalculateBreedScores(speciesID,petType,possibleBreedIDs,1)
    if #rs>0 then return rs[1].breedID,rs[1].breedCode,rs[1].score end
    return nil,nil,nil
end

-- 暴露技能标签收集供 JournalUI label 摘要
addonTable.CollectSkillTags = CollectTags
addonTable.GetSkillTags = function() return SkillTags end
