-- GenDexBD Locales.lua
-- 多语种字符串表，根据客户端语种自动选择中文或英文
-- 加载顺序：第1个（最先加载，所有后续模块依赖）

local addonName, addonTable = ...

-- 检测客户端语种
local locale = GetLocale()  -- "zhCN", "enUS", "zhTW", "deDE", ...

-- ============================================================================
-- 字符串表
-- ============================================================================

-- 品种内部名称（用于生成显示名如"P/P 攻击型"）
local breedNames = {
    [3]  = { zhCN = "平衡型",   enUS = "Balanced" },
    [4]  = { zhCN = "攻击型",   enUS = "Power" },
    [5]  = { zhCN = "速度型",   enUS = "Speed" },
    [6]  = { zhCN = "生命型",   enUS = "Health" },
    [7]  = { zhCN = "攻血型",   enUS = "H/P Power/Health" },
    [8]  = { zhCN = "攻速型",   enUS = "Power/Speed" },
    [9]  = { zhCN = "血速型",   enUS = "Health/Speed" },
    [10] = { zhCN = "攻平型",   enUS = "Power/Balanced" },
    [11] = { zhCN = "速平型",   enUS = "Speed/Balanced" },
    [12] = { zhCN = "血平型",   enUS = "Health/Balanced" },
    [13] = { zhCN = "攻生型",   enUS = "P/H Power/Health" },
    [14] = { zhCN = "血速型",   enUS = "Health/Speed" },
}

-- 通用字符串表：键名 → { zhCN = "...", enUS = "..." }
local strings = {
    -- 系统消息
    ADDON_LOADED          = { zhCN = "GenDexBD 已加载。输入 /gbbd 打开设置。", enUS = "GenDexBD loaded. Type /gbbd to configure." },
    MIGRATION_COMPLETE    = { zhCN = "最优品种数据已升级到 v2 格式。",         enUS = "Best breed data migrated to v2 format." },
    SLASH_HELP            = { zhCN = "GenDexBD 命令: /gbbd 打开设置面板",       enUS = "GenDexBD commands: /gbbd to open settings" },

    -- 品种显示
    BREED_UNKNOWN         = { zhCN = "未知品种",   enUS = "Unknown Breed" },
    BREED_FORMAT          = { zhCN = "品种: %s", enUS = "Breed: %s" },
    BREED_TARGET_FORMAT   = { zhCN = "品种: %s 🎯 %s", enUS = "Breed: %s 🎯 %s" },

    -- 备注显示
    NOTE_LABEL            = { zhCN = "备注: %s",   enUS = "Note: %s" },

    -- 最优属性分类
    CATEGORY_PVP          = { zhCN = "PvP 对战",   enUS = "PvP Battle" },
    CATEGORY_PVE          = { zhCN = "PvE 任务",   enUS = "PvE Quest" },
    CATEGORY_COLLECTION   = { zhCN = "收藏",       enUS = "Collection" },
    CATEGORY_CUSTOM       = { zhCN = "自定义",     enUS = "Custom" },

    -- 最优属性管理 UI
    BEST_BREED_SECTION    = { zhCN = "★ 最优属性管理",        enUS = "★ Best Breed Management" },
    SET_BEST_BREED        = { zhCN = "最优属性设置",          enUS = "Best Breed Setup" },
    SET_OTHER_BREED       = { zhCN = "设为其他属性",          enUS = "Set Other Breed" },
    REMOVE_BEST_BREED     = { zhCN = "取消最优属性",          enUS = "Remove Best Breed" },
    SHOW_IN_JOURNAL       = { zhCN = "在手册中显示该宠物",     enUS = "Show in Journal" },
    NO_BEST_BREED_SET     = { zhCN = "尚未设置最佳品种",      enUS = "No best breed set" },
    ONLY_BREED_IS_BEST    = { zhCN = "唯一属性即为最佳",      enUS = "Only breed is best" },
    ALL_OWNED             = { zhCN = "已全部拥有",            enUS = "All Owned" },
    UPDATE_BEST_BREED     = { zhCN = "更新分类/备注",         enUS = "Update Category/Note" },
    CATEGORY_LABEL        = { zhCN = "使用场景",              enUS = "Category" },
    NOTE_LABEL_UI         = { zhCN = "备注信息",              enUS = "Note" },
    NOTE_PLACEHOLDER      = { zhCN = "选填（如：PVE输出最高）", enUS = "Optional (e.g.: Best for PvE)" },


    -- 配置面板
    CONFIG_TITLE          = { zhCN = "GenDexBD 设置",         enUS = "GenDexBD Settings" },
    OPTION_SHOW_TOOLTIP   = { zhCN = "鼠标提示显示品种",        enUS = "Show breed in tooltip" },

    OPTION_ALERT_BATTLE   = { zhCN = "战斗目标提示",           enUS = "Alert in battle" },
    OPTION_ASSUME_RARE    = { zhCN = "默认按精良品质推算",       enUS = "Assume Rare quality" },
    OPTION_SHOW_NOTE      = { zhCN = "提示中显示最优备注",       enUS = "Show best breed note in tooltip" },
    OPTION_TRACK_ENCOUNTERS = { zhCN = "遇敌属性计数",           enUS = "Track Pet Encounters" },
    OPTION_ALERT_DURATION = { zhCN = "目标提示显示时间",            enUS = "Alert display duration" },
    OPTION_DEBUG_RECOMMEND = { zhCN = "诊断日志（智能推荐详情）",     enUS = "Debug log (Recommend details)" },
    SECONDS              = { zhCN = "秒",                      enUS = "sec" },
    EXPORT_BUTTON        = { zhCN = "导出配置",                 enUS = "Export Config" },
    IMPORT_BUTTON        = { zhCN = "导入配置",                 enUS = "Import Config" },
    EXPORT_TITLE         = { zhCN = "导出最优品种数据",           enUS = "Export Best Breed Data" },
    IMPORT_TITLE         = { zhCN = "导入最优品种数据",           enUS = "Import Best Breed Data" },
    EXPORT_HINT          = { zhCN = "Ctrl+C 复制全部文本",       enUS = "Ctrl+C to copy all text" },
    IMPORT_HINT          = { zhCN = "Ctrl+V 粘贴数据后点击导入",   enUS = "Ctrl+V to paste then click Import" },
    IMPORT_DONE          = { zhCN = "导入完成：%d 条记录",        enUS = "Import done: %d records" },
    ENCOUNTER_STATS_TITLE = { zhCN = "遇敌属性统计",              enUS = "Encounter Stats" },
    ENCOUNTER_NO_DATA    = { zhCN = "暂无遇敌记录",               enUS = "No encounter data yet" },
    SPECIES_NAME_HEADER  = { zhCN = "宠物名称",                  enUS = "Pet Name" },
    BREED_HEADER         = { zhCN = "品种",                      enUS = "Breed" },
    COUNT_HEADER         = { zhCN = "遇敌次数",                  enUS = "Count" },

    -- Tab 标签页
    TAB_GENERAL          = { zhCN = "常规设置",                  enUS = "General" },
    TAB_BEST_BREEDS      = { zhCN = "最优品种",                  enUS = "Best Breeds" },

    -- 最优品种列表
    BEST_BREED_LIST_TITLE = { zhCN = "已保存的最优品种",           enUS = "Saved Best Breeds" },
    BEST_BREED_NO_DATA    = { zhCN = "暂无保存记录",               enUS = "No saved breeds yet" },
    CATEGORY_HEADER       = { zhCN = "分类",                      enUS = "Category" },

    -- 智能推荐
    SMART_RECOMMEND        = { zhCN = "🤖 智能推荐",           enUS = "🤖 Smart Recommendation" },
    RECOMMEND_TITLE        = { zhCN = "品种推荐 (评分)",        enUS = "Breed Recommendations (Score)" },
    RECOMMEND_NO_DATA      = { zhCN = "技能标签数据不足",        enUS = "Insufficient ability tag data" },
    RECOMMEND_NO_BREEDS    = { zhCN = "无法获取可选品种",        enUS = "Cannot determine possible breeds" },
    RECOMMEND_SCORE_FMT    = { zhCN = "%s  — 评分: %d",      enUS = "%s  — Score: %d" },
    RECOMMEND_STATS_FMT    = { zhCN = "  H×%.1f  P×%.1f  S×%.1f", enUS = "  H×%.1f  P×%.1f  S×%.1f" },
    RECOMMEND_NO_TAGS      = { zhCN = "(无匹配标签，显示基础属性评分)", enUS = "(No matching tags; raw stat score)" },
    RECOMMEND_SET_BREED    = { zhCN = "设为此品种",             enUS = "Set as Best Breed" },

    -- 战斗提示
    ALERT_TARGET          = { zhCN = "最优属性目标",        enUS = "Best Breed Target" },
    ALERT_PVP             = { zhCN = "PvP 目标发现！",    enUS = "PvP Target Found!" },
    ALERT_PVE             = { zhCN = "PvE 目标发现！",    enUS = "PvE Target Found!" },
    ALERT_COLLECTION      = { zhCN = "收藏目标发现！",     enUS = "Collection Target Found!" },
    ALERT_CUSTOM          = { zhCN = "目标发现！",        enUS = "Target Found!" },

    -- 品质名（用于调试/日志）
    QUALITY_POOR          = { zhCN = "灰色",   enUS = "Poor" },
    QUALITY_COMMON        = { zhCN = "白色",   enUS = "Common" },
    QUALITY_UNCOMMON      = { zhCN = "绿色",   enUS = "Uncommon" },
    QUALITY_RARE          = { zhCN = "蓝色",   enUS = "Rare" },
    QUALITY_EPIC          = { zhCN = "紫色",   enUS = "Epic" },
    QUALITY_LEGENDARY     = { zhCN = "橙色",   enUS = "Legendary" },

    -- 下拉菜单默认项
    DROPDOWN_SELECT       = { zhCN = "请选择场景", enUS = "Select Category" },
}

-- ============================================================================
-- 字符串查找函数
-- ============================================================================

-- 判断是否使用中文
local function IsChineseLocale()
    return locale == "zhCN" or locale == "zhTW"
end

-- 从字符串表中获取当前语种的文本
local function GetLocalizedString(tbl, key)
    local entry = tbl[key]
    if not entry then
        return "[" .. tostring(key) .. "]"
    end
    if IsChineseLocale() then
        return entry.zhCN or entry.enUS or tostring(key)
    else
        return entry.enUS or tostring(key)
    end
end

-- 暴露字符串查找函数供其他模块使用
addonTable.L = {
    GetString = GetLocalizedString,
    IsChineseLocale = IsChineseLocale,
}

-- ============================================================================
-- 公开 API 函数
-- ============================================================================

--- 获取品种的完整本地化显示名（如 "P/P 攻击型"）
--- @param breedID number 品种ID (3-14)
--- @param breedCode string|nil 品种短代码（如 "P/P"），传入则避免重复查找
--- @return string 本地化显示名
function addonTable.GetBreedDisplayName(breedID, breedCode)
    -- 获取短代码
    if not breedCode then
        breedCode = addonTable.GetBreedCode and addonTable.GetBreedCode(breedID)
        if not breedCode then
            return GetLocalizedString(strings, "BREED_UNKNOWN")
        end
    end

    -- 获取品种类型名
    local names = breedNames[breedID]
    if not names then
        return breedCode .. " " .. GetLocalizedString(strings, "BREED_UNKNOWN")
    end

    local typeName = IsChineseLocale() and names.zhCN or names.enUS
    if not typeName then
        typeName = GetLocalizedString(strings, "BREED_UNKNOWN")
    end

    return breedCode .. " " .. typeName
end

--- 获取最优属性分类的本地化名称
--- @param category string 分类键："pvp", "pve", "collection", "custom"
--- @return string 本地化分类名
function addonTable.GetBestBreedCategoryName(category)
    local categoryMap = {
        pvp = "CATEGORY_PVP",
        pve = "CATEGORY_PVE",
        collection = "CATEGORY_COLLECTION",
        custom = "CATEGORY_CUSTOM",
    }
    local stringKey = categoryMap[category] or "CATEGORY_CUSTOM"
    return GetLocalizedString(strings, stringKey)
end

-- ============================================================================
-- 自动分类关键词（zhCN/enUS 分离，便于维护）
-- ============================================================================

addonTable.AUTO_TAG_KEYWORDS = {
    NEEDS_SPEED = {
        zhCN = {
            "优先","先手","率先","首先","抢先",
            "打断","反制",
            "闪避","躲闪","偏斜","闪现","消失","虚化",
            "升空","升上","起飞","1轮内不可攻击","1轮内无法攻击",
            "钻地","钻入","潜水","下潜",
            "假死","比.*快",
            "替换.*宠","虚空之门","传送","强制.*换","召回",
            "昏迷","晕眩","击倒","催眠",
            "反弹.*攻击","冲锋","突袭","伏击","背刺","跳击","猛扑",
            "速度.*提高","速度.*提升",
            "陷阱","蛛网","诱捕","定身","无法逃跑","无法.*切换",
            "冰冻.*目标","沙尘暴","祈雨","天气变为","变为.*天气",
            "泥石流","焦土","雷暴",
            "茧","先手.*屏障","幕","驱散.*敌方",
        },
        enUS = {
            "goes first","always first","first strike",
            "initiative","preemptive","starts first",
            "interrupt","disrupt",
            "dodge","evade","evasive","elusive",
            "deflect","blink","vanish","ethereal",
            "soar",
            "burrow","underground","dive","submerge",
            "feign death","faster than",
            "swap.*pet","switch.*pet","nether gate","portal","force.*swap","recall",
            "stun","knock.*down","sleep.*first",
            "reflect.*attack","charge.*first","pounce","ambush","backstab","leap","lunge",
            "trap","web","ensnare","immobiliz","blind.*target","freeze.*target",
            "sandstorm","rain dance","mudslide","cleansing rain",
            "call darkness","arcane storm","scorched","lightning storm",
            "cocoon","barrier.*first","shroud","purge.*enemy",
        },
    },
    SCALES_POWER = {
        zhCN = {
            "乱舞","蜂群","猛踏","连射","弹幕","齐射",
            "三连击","双重.*击","两次","三次","连击","链.*攻击","重复",
            "每一击","1.2次","1.3次","1.2把","1.3把",
            "每回合","每轮造成","每轮额外","持续.*伤害","每回合造成","额外.*每轮","轮后.*造成",
            "流血","割裂","出血",
            "中毒.*每轮","中毒.*持续","毒性","污染","麻痹",
            "点燃","焦灼","献祭","燃烧.*伤害",
            "冻伤","低温",
            "诅咒","鬼影",
            "斩杀","处决","低于.*双倍","如果.*中毒.*双倍",
            "毁灭","湮灭","抹除","能量涌动","爆发","愤怒","狂怒",
            "审判","大灾变",
            "嚎叫","增幅","激怒","狂暴","嗜血","咆哮",
            "造成的伤害提高","攻击.*提升",
        },
        enUS = {
            "flurry","swarm","frenzy","stampede","thrash",
            "volley","barrage","salvo",
            "triple.*hit","double.*hit","two.*times","three.*times",
            "combo.*attack","chain.*attack","repeat",
            "each hit","each strike",
            "every round","each round","per round","per turn","each turn",
            "damage over","additional.*damage.*each","after.*round.*damage","turns.*later",
            "bleed","rend","lacerate","hemorrhage","gouge",
            "poison","toxic","venom","contaminate","neurotoxin",
            "ignite","scorch","immolate","conflagrate","burn.*damage",
            "chill","frostbite","frost.*damage","hypotherm",
            "curse","haunt","doom",
            "execute","execution","below.*double",
            "devastat","annihilate","obliterate","surge of power","burst.*damage",
            "wrath","fury","judgment","cataclysm","apocalypse",
            "howl","amplify","enrage","berserk","bloodlust","roar",
            "damage increased","damage boost","power boost",
        },
    },
    SCALES_HEALTH = {
        zhCN = {
            "治疗","治愈","回复.*生命","疗伤","康复","再生","回春","绽放","开花",
            "重振","提神","滋养","安抚","绷带","急救",
            "复活","复苏","重生","转生","不死","还魂","第二条命",
            "重铸","重建","故障保护",
            "最大生命.*回复","吸取.*生命","吸血","虹吸",
            "吞食","吞噬","盛宴","进食",
            "牺牲","自爆","爆炸","殉道","引爆","内爆",
            "杀死.*施法者","杀死.*使用者","总生命值","剩余.*生命值",
            "护盾.*吸收","屏障","结界","神盾","壁垒","吸收.*伤害",
            "减免.*伤害","伤害降低","降低.*伤害","受到.*伤害.*降低","受到.*伤害.*减少",
            "伤害上限","防止.*伤害",
            "坚毅","承受","坚韧","韧性",
            "守护者","保护者","庇护所","祝福","净化",
        },
        enUS = {
            "heals ","healing ","mend","cure",
            "restore.*health","recover.*health","regenerate","rejuvenate",
            "bloom","blossom","renew.*health","invigorate","nourish","sooth",
            "bandage","first aid",
            "resurrect","revive","rebirth","reincarnate","undying","reanimate","second life",
            "rebuilt","reconstruct","failsafe",
            "of.*max.*health","drain.*health","leech","siphon","vampir",
            "consume","devour","feast","feed",
            "sacrifice","self.destruct","explode","martyr","detonate","implode",
            "split.*health","swap.*life","life.*exchange",
            "shield.*absorb","barrier.*damage","ward","aegis","bulwark","absorb.*damage",
            "reduce.*damage","damage.*reduce","damage.*cap","cannot.*exceed","prevent.*damage",
            "fortitude","endure.*damage","withstand","resilien",
            "guardian","protector","sanctuary","blessing","purify",
        },
    },
}

--- 便捷函数：获取指定键的本地化字符串
--- @param key string 字符串键
--- @return string
function addonTable.GetLocaleString(key)
    return GetLocalizedString(strings, key)
end
