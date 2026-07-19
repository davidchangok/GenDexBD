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
local SPEED_BONUS = { [0.8]=1.0, [1.0]=1.2, [1.2]=1.5, [1.4]=2.0 }

local W_BASE  = 1.0
local W_SPEED = 0.8   -- NEEDS_SPEED 标签加成
local W_POWER = 0.6   -- SCALES_POWER 加成（超线性技能）
local W_HEALTH = 1.0  -- SCALES_HEALTH 加成（血量技能稀缺价值更高）
local W_FORCE = 3.0
local SCALE = 100
local HP_VALUE = 0.67 -- 生命系数等价比（1生命 ≈ 0.67攻击/速度）
                       -- 来源：NGA 5.0实测数据 "能量0.1:速度0.1≈生命0.15"

local FAMILY_MOD = {
    [3]  = { h=1.0, p=1.0, s=1.3 }, [4] = { h=1.0, p=1.3, s=1.0 },
    [6]  = { h=1.3, p=1.0, s=0.8 }, [8] = { h=1.2, p=1.0, s=1.0 },
    [10] = { h=1.0, p=1.2, s=1.0 },
}

-- ============================================================================
-- Layer 2: 自动分类关键词（精炼版）
-- ============================================================================
-- SCALES_POWER 仅含超线性技能；普通攻击不在此列

local AUTO_TAGS = {
    NEEDS_SPEED = {
        "优先", "先手", "率先", "首先", "初击", "抢先", "快攻",
        "goes first", "always first", "first strike",
        "initiative", "preemptive", "starts first",
        "interrupt", "打断", "反制", "disrupt",
        "dodge", "闪避", "躲闪", "evade", "evasive", "elusive",
        "deflect", "偏斜", "blink", "闪现", "vanish", "消失",
        "ethereal", "虚化", "invulnerable", "无敌",
        "untargetable", "不可选中", "stealth", "潜", "invisible", "隐形",
        "升空", "升上", "起飞", "soar", "翱翔",
        "1轮内不可攻击", "1轮内无法攻击",
        "burrow", "钻地", "钻入", "掘地", "underground",
        "dive", "潜水", "下潜", "submerge",
        "feign death", "假死", "装死", "诈死",
        "survival", "生存", "cheat death", "免死",
        "faster than", "比.*快", "速度比",
        "each.*speed", "每.*点速度",
        "based on.*speed", "基于.*速度",
        "slower.*more", "越慢.*越",
        -- 速度增益（加速自己=需要速度品种放大收益）
        "speed.*increas", "速度.*提高", "速度.*提升",
        "专注", "concentrat", -- 专注类技能：提高速度+暴击+命中
        "swap.*pet", "替换.*宠", "switch.*pet",
        "nether gate", "虚空之门", "portal", "传送",
        "force.*swap", "强制.*换", "recall", "召回",
        "stun", "昏迷", "晕眩",
        "clobber", "猛击", "bash", "重击", "冲撞", "headbutt",
        "concuss", "脑震荡", "knock.*down", "击倒", "trip", "绊倒",
        "sleep.*first", "催眠", "confus.*first",
        "counterstrike", "反击", "riposte", "招架",
        "reflect.*attack", "反弹.*攻击",
        "retaliate", "报复", "deflect.*attack",
        "charge.*first", "冲锋", "pounce", "突袭",
        "ambush", "伏击", "sneak.*attack", "偷袭",
        "backstab", "背刺", "leap", "跳击", "lunge", "猛扑",
        "dash", "疾跑", "sprint", "飞奔",
        "trap", "陷阱", "web", "蛛网", "ensnare", "诱捕",
        "immobiliz", "定身", "blind.*target", "致盲",
        "freeze.*target", "冰冻.*目标", "polymorph", "变形",
        "lightning storm", "雷暴", "sandstorm", "沙尘暴",
        "rain dance", "祈雨", "sunlight", "阳光",
        -- 天气（变天需先手才能抢在对手行动前生效）
        "moonlight", "月光", "moonfire", "月火",
        "天气变为", "变为.*天气", "weather.*change",
        "mudslide", "泥石流", "cleansing rain",
        "call darkness", "arcane storm", "scorched", "焦土",
        "cocoon", "茧", "barrier.*first", "先手.*屏障", "shroud", "幕",
        "team.*speed", "队伍.*速度", "ally.*speed",
        "purge.*enemy", "驱散.*敌方",
    },
    SCALES_POWER = {
        -- 多段（≥2 hits，非单段普攻）
        "flurry", "乱舞", "swarm", "蜂群", "frenzy", "狂暴",
        "stampede", "猛踏", "thrash",
        "volley", "连射", "barrage", "弹幕", "salvo", "齐射",
        "triple.*hit", "三连击", "double.*hit", "双重.*击",
        "two.*times", "两次", "three.*times", "三次",
        "combo.*attack", "连击", "chain.*attack", "链.*攻击",
        "每一击", "each hit", "each strike",
        "1.2次", "1.3次", "1.2把", "1.3把", -- 多段攻击的数量范围描述
        -- DoT/每轮
        "every round", "每轮", "each round", "每回合",
        "per round", "per turn", "each turn",
        "damage over", "持续.*伤害", "每回合造成",
        "additional.*damage.*each", "额外.*每轮",
        -- 延迟伤害（轮后触发）
        "轮后.*造成", "after.*round.*damage", "turns.*later",
        -- 流血
        "bleed", "流血", "rend", "割裂", "lacerate",
        "hemorrhage", "出血", "gouge",
        -- 中毒
        "poison", "中毒", "毒性", "toxic", "venom",
        "infect", "感染", "contaminate", "污染",
        "neurotoxin", "麻痹",
        -- 燃烧Dot
        "ignite", "点燃", "scorch", "焦灼", "immolate", "献祭",
        "conflagrate", "burn.*damage", "燃烧.*伤害",
        -- 冰霜Dot
        "chill", "冻伤", "frostbite", "frost.*damage",
        "hypotherm", "低温",
        -- 诅咒
        "curse", "诅咒", "haunt", "鬼影", "doom",
        -- 斩杀/条件增伤
        "execute", "斩杀", "execution", "处决",
        "低于.*双倍", "below.*double",
        "如果.*中毒.*双倍",
        -- 高额爆发
        "devastat", "毁灭", "annihilate", "湮灭", "obliterate", "抹除",
        "surge of power", "能量涌动", "burst.*damage", "爆发",
        "wrath", "愤怒", "fury", "狂怒",
        "judgment", "审判", "cataclysm", "大灾变",
        "apocalypse", "天启",
        -- 攻击加成/增幅（无.*，防止"伤害...速度提高"跨词误匹配）
        "howl", "嚎叫", "amplify", "增幅",
        "enrage", "激怒", "berserk", "狂暴",
        "bloodlust", "嗜血", "roar", "咆哮",
        "伤害提高", "伤害提升", "damage increased", "damage boost",
        "攻击.*提升", "power boost",
    },
    SCALES_HEALTH = {
        -- 治疗
        "heals ", "治疗", "healing ", "治愈", "回复.*生命",
        "mend", "cure", "疗伤", "restore.*health", "恢复.*生命",
        "recover.*health", "康复", "regenerate", "再生",
        "rejuvenate", "回春", "bloom", "绽放", "blossom", "开花",
        "renew.*health", "重振", "invigorate", "提神",
        "nourish", "滋养", "sooth", "安抚",
        "bandage", "绷带", "first aid", "急救",
        -- 复活/重生/机械不死
        "resurrect", "复活", "revive", "复苏",
        "rebirth", "重生", "reincarnate", "转生",
        "undying", "不死", "reanimate", "还魂",
        "second life", "第二条命",
        "rebuilt", "重铸", "reconstruct", "重建",
        "failsafe", "故障保护",
        -- 百分比回血
        "max health.*heal", "最大生命.*回复",
        "of.*max.*health", "最大生命值.*的",
        -- 吸血
        "drain.*health", "吸取.*生命", "leech", "吸血",
        "siphon", "虹吸", "vampir",
        -- 吞噬
        "consume", "吞食", "devour", "吞噬",
        "feast", "盛宴", "feed", "进食",
        -- 牺牲/自爆/自毁
        "sacrifice", "牺牲", "self.destruct", "自爆",
        "explode", "爆炸", "martyr", "殉道",
        "detonate", "引爆", "implode", "内爆",
        "杀死.*施法者", "杀死.*使用者", "立即杀死",
        "总生命值", "剩余.*生命值",
        -- 换血/平分（均分生命=生命交换，反SCALES_HEALTH：HP越低越强）
        "split.*health", "swap.*life", "life.*exchange",
        -- 护盾/屏障
        "shield.*absorb", "护盾.*吸收",
        "barrier.*damage", "屏障", "ward", "结界",
        "aegis", "神盾", "bulwark", "壁垒",
        "absorb.*damage", "吸收.*伤害",
        -- 减伤
        "reduce.*damage", "减免.*伤害", "damage.*reduce",
        "伤害降低", "降低.*伤害",
        "受到.*伤害.*降低", "受到.*伤害.*减少",
        "damage.*cap", "伤害上限", "cannot.*exceed",
        "prevent.*damage", "防止.*伤害",
        -- 坦克/耐久
        "fortitude", "坚毅", "endure.*damage", "承受",
        "withstand", "坚韧", "resilien", "韧性",
        -- 守护
        "guardian", "守护者", "protector", "保护者",
        "sanctuary", "庇护所", "blessing", "祝福", "purify", "净化",
    },
}

local autoTagCache = {}

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
                if sfind(sentence, pat) then
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

local function CollectTags(speciesID)
    local tc = {}
    local results = { C_PetJournal.GetPetAbilityList(speciesID) }
    local at = results[1]
    if not at or type(at) ~= "table" then return tc end
    for _, aid in pairs(at) do
        if type(aid) == "number" and aid > 0 then
            local tags = SkillTags[aid] or AutoClassify(aid)
            if tags then for tag in pairs(tags) do
                tc[tag] = (tc[tag] or 0) + 1
            end end
        end
    end
    return tc
end

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
    local wh = W_BASE + W_HEALTH * (tc["SCALES_HEALTH"] or 0)
    local wp = W_BASE + W_POWER  * (tc["SCALES_POWER"]  or 0)
    local ws_base  = W_BASE
    local ws_needs = W_SPEED * (tc["NEEDS_SPEED"] or 0)

    if (tc["FORCE_PP"] or 0) > 0 then wp = wp + W_FORCE end
    if (tc["FORCE_SS"] or 0) > 0 then ws_needs = ws_needs + W_FORCE end
    if (tc["FORCE_HH"] or 0) > 0 then wh = wh + W_FORCE end

    local fm = FAMILY_MOD[pt]
    if fm then wh = wh * fm.h; wp = wp * fm.p; ws_needs = ws_needs * fm.s end

    local sb = 1.0
    if (tc["NEEDS_SPEED"] or 0) > 0 then sb = SpeedBonus(s) end

    local ws = ws_base
    if (tc["NEEDS_SPEED"] or 0) == 0 then ws = ws * 0.7 end

    -- 生命等价比修正：1生命 ≈ 0.67攻击/速度（NGA 5.0实测 "0.1攻:0.1速≈0.15命"）
    -- 品种生命系数(0.2-1.8)需要打折后再参与评分
    local raw = wp * p + ws * s + ws_needs * sb + wh * h * HP_VALUE
    return raw * SCALE, {wh=wh,wp=wp,ws=ws,sb=sb,ws_base=ws_base,ws_needs=ws_needs}
end

-- ============================================================================
-- 公开 API + 诊断
-- ============================================================================

function addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, topN)
    if not speciesID then return {} end; if not petType then petType = GetPetType(speciesID) end
    local tc = CollectTags(speciesID)

    local doDebug = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
    if doDebug then
        local vals = {C_PetJournal.GetPetInfoBySpeciesID(speciesID)}
        local name = type(vals[1])=="string" and vals[1] or "?"
        print("|cffffd700=== [GenDexDBG] speciesID=" .. tostring(speciesID) .. " (" .. name .. ") petType=" .. tostring(petType) .. " ===|r")
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
            local score,detail = Score(h,p,s,tc,petType)
            local code = addonTable.GetBreedCode and addonTable.GetBreedCode(bid) or "?"
            if doDebug then
                print(string.format("  %-6s %8d %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f",
                    code,mfloor(score+0.5),detail.wh,detail.wp,
                    detail.ws_base or 0,detail.ws_needs or 0,detail.sb,
                    detail.wp*p + detail.ws*s + (detail.ws_needs or 0)*detail.sb + detail.wh*h*HP_VALUE))
            end
            rs[#rs+1]={breedID=bid,score=mfloor(score+0.5),breedCode=code,
                       stats={h_coef=h,p_coef=p,s_coef=s},details=detail,tagCounts=tc}
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
