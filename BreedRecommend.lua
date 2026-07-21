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
local W_SUICIDE = 2.0  -- SUICIDE_HP 加成（HP%自爆:血量直接=攻击力,加权高于普通回血护盾）
local W_POWER_AMP = 1.5  -- POWER_AMP 加成（伤害放大器:+125%/+100%,Power²受益）
local W_FORCE = 3.0
local W_COMMUNITY = 2.0  -- 社区例外加权（软覆盖，远小于 FORCE=3.0）
                          -- 1.5 × 100 = 150分加成，翻转中等差距的排名
local SCALE = 100
local HP_VALUE = 0.67 -- 生命系数等价比（1生命 ≈ 0.67攻击/速度）
                       -- 来源：NGA 5.0实测数据 "能量0.1:速度0.1≈生命0.15"

local FAMILY_MOD = {
    -- 1型: 人型 — 攻击回血4% → 偏攻击
    [1]  = { h=1.0, p=1.15, s=1.0 },
    -- 2型: 龙类 — 敌方<50%伤害+50% → 偏攻击(斩杀)
    [2]  = { h=1.0, p=1.15, s=1.0 },
    -- 3型: 飞行 — >50%HP速度+50%(种族被动已给速度,不需额外加权)
    [3]  = { h=1.0, p=1.1, s=1.0 },
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
-- 社区例外加权表（speciesID → 社区偏好的单属性 "H"/"P"/"S"/"B" 或完整码 "H/P"等）
-- 软覆盖机制：加成 W_COMMUNITY 到偏好属性权重，乘以品种系数
-- 远小于 FORCE(3.0)，仅用于翻转差距较小的排名
-- 社区共识来源：WarcraftPets 论坛/评论区（详见 memory/community-breed-consensus.md）
-- ============================================================================
local COMMUNITY_BREED_BONUS = {
    -- === 蜘蛛家族 ===
    [412] = "S",     -- 蜘蛛: S/S社区首选,网→毒→幼蛛组合需先手设网
    [470] = "P",     -- 暮光蜘蛛: P/P仅3品种,无S/S可选
    [484] = "P/S",   -- 沙漠蜘蛛: P/S社区确认
    [407] = "P/S",   -- 林地小蜘蛛: P/S确认有品种
    [1726] = "S",    -- 潜地小蜘蛛: S/S,3NEED标签自然偏速
    [3007] = "P/B",  -- 粉腿小蜘蛛: P/B,生命虹吸+传染打击
    [428] = "S",     -- 熔火幼蛛: S/S社区主导,先手尖网控场+341速反制MPD
    [3202] = "S",    -- 元蛛追猎者: S/S,蜘蛛控场型,乱舞+致盲剧毒+尖网先手
    -- === 老鼠家族 ===
    [398] = "S",     -- 黑老鼠: S/S,乱舞+奔踏先手额外攻击次数
    [454] = "S",     -- 幽暗城老鼠: S/S,同黑老鼠家族
    [410] = "S",     -- 码头老鼠: S/S,同老鼠家族
    [1427] = "P",    -- 霜鬃鼠: P/P社区确认,SneakAttack+CallDarkness爆发流
    [4277] = "S",    -- 树液啮咬者: S/S,啮齿类Flurry系共用S/S共识
    -- === 兔子/松鼠家族 ===
    [391] = "S",     -- 高山短尾兔: S/S,乱舞+钻地+躲闪+激素刺激
    [448] = "S",     -- 野兔: S/S,同391+奔踏
    [443] = "S",     -- 草地短尾兔: S/S,同391/448家族
    [379] = "S",     -- 松鼠: S/S,坚果弹幕+奔踏+蜷伏,FORCE_SS已设双保险
    [452] = "S",     -- 红尾花栗鼠: S/S,FORCE_SS(167)生效同379
    [647] = "S",     -- 灰色松鼠: S/S,松鼠家族全S/S
    [3278] = "S",    -- 开心果: S/S,FORCE_SS坚果弹幕+狂野爪击风暴
    [137] = "S",     -- 棕兔: S/S,兔子家族全S/S,乱舞+钻地+躲闪
    [378] = "S",     -- 兔子: S/S,兔子家族S/S共识,同上技能池
    [487] = "S",     -- 高山花栗鼠: S/S,花栗鼠全S/S,坚果弹幕+奔踏+蜷伏
    [730] = "S",     -- 多莱兔仔: S/S,兔子家族S/S,同137/378
    [1729] = "S",    -- 绿尾野兔: S/S,野兔全S/S,速度碾压同族
    -- === 土拨鼠 ===
    [386] = "S",     -- 草原土拨鼠: S/S,无P/B品种可选,仅3品种S/S最优
    [549] = "P/B",   -- 黄腹土拨鼠: P/B,自加速技移除NEEDS_SPEED后P/B反超S/S
    -- === 甲虫家族 ===
    [415] = "H/P",   -- 火甲虫: H/P社区推荐,无P/P可选
    [429] = "P",     -- 熔火甲虫: P/P社区"especially P/P",不同于415有P/P选P/P
    [2843] = "B",    -- 虚痕甲虫: B/B,NEEDS_SPEED×1+SCALES×2均衡
    [430] = "S",     -- 金甲虫: S/S唯一品种
    -- === 蛇/蝎家族 ===
    [425] = "P/S",   -- 燃灰蝰蛇: P/S,无S/S可选,蛇类指南推荐S/S→P/S最接近
    [432] = "P/S",   -- 纹尾蝎: P/S社区Vek确认,P/S(481)>B/B(414)
    -- [418] 水蛇: 仅B/B品种, 单品种无需COMMUNITY_BONUS
    -- === 蟹 ===
    [388] = "H",     -- 海滨蟹: H/H,双治疗坦克翻身,NEEDS_SPEED不碾压H/H
    -- [423] 熔岩蟹: 社区无品种讨论,Shell Shield攻缩放工具宠,移除COMMUNITY
    [746] = "P",     -- 君王蟹: P/P,同海滨蟹族PvP速攻
    [401] = "H",     -- 海湾蟹: H/H,双治疗坦克型,甲壳护盾+治疗波续航
    [564] = "H",     -- 翡翠乌龟: H/H,龟类坦克型,甲壳护盾+治疗波
    [572] = "P",     -- 塔边小蟹: P/P,蟹类PvP速攻型,蟹钳+激流
    [1583] = "P",    -- 海藻凿孔蟹: P/P,螃蟹PvP型,同572
    -- === 青蛙/蟾蜍 ===
    [419] = "S/B",   -- 小青蛙: S/B,治疗波+净化雨吃攻击缩放,水栖治疗体系
    [420] = "H/P",   -- 蟾蜍: H/P唯一青蛙/蟾蜍有H/P品种,治疗波攻缩放
    [648] = "H/P",   -- 大蟾蜍: H/P,蟾蜍家族同420
    -- === 蜗牛 ===
    [493] = "H/P",   -- 闪光湖蜗牛: H/P,305攻=最高攻蜗牛,吸收吃Power+甲壳护盾吃HP
    [3482] = "H/P",  -- 圆石之壳: H/P,蜗牛家族H/P共识,吸收+甲壳护盾体系
    -- === 蛾/蝴蝶 ===
    [478] = "H/S",   -- 森林蛾: H/S,Cocoon Strike>速度技,需血量维持飞行被动
    [2384] = "S",    -- 海滨蝴蝶: S/S,飞行蝴蝶通用S/S
    [1325] = "P/S",  -- 焰光蛾: P/S,蛾类P/P或P/S共识,飞行被动给速度
    [1587] = "P/S",  -- 皇家飞蛾: P/S,同蛾类家族共识
    -- === 猫头鹰/鸟 ===
    -- [507] 羽冠猫头鹰: 无可靠社区共识, 飞行均衡P/P亦合理, 移除
    -- [423] 熔岩蟹: 无社区讨论, 移除
    -- [418] 水蛇: 仅B/B, 单品种无需
    -- [3384] 雷触蓝羽鸭: 仅S/B单品种, Rematch误报4品种
    -- [3038] 不朽死亡蟑螂: FORCE_SS强制S/S, COMMUNITY B/B不能覆盖, 需搜社区确认
    [548] = "P",     -- 蛮锤狮鹫: P/P社区"no-brainer",仅3种鸟有P/P,切削之风+群殴多段爆发
    [646] = "S",     -- 鸡: S/S(P/P也可),飞行×1.3速+325速,蛋幕+切削之风
    [1068] = "S",    -- 乌鸦: S/S,空袭+暗黑+夜袭,"very rare but best"
    [1572] = "S",    -- 夺目的红羽雀: S/S,飞行速度系S/S,啄击+飞羽+升空
    -- === 蝙蝠 ===
    [626] = "P",     -- 蝙蝠: P/P,鲁莽之击spam+鹰眼,无防御=最大化输出
    [1762] = "P",    -- 猪鼻蝙蝠: P/P,蝙蝠家族P/P共识,鲁莽之击+夜袭
    -- === 鹿/羊 ===
    [447] = "H/S",   -- 小鹿: H/S,B/B有75%惩罚,治疗吃Power需HS均衡
    [374] = "H/P",   -- 黑羔羊: H/P,高血高攻+Chew+Comeback+Stampede
    [1913] = "H/S",  -- 闪蹄小鹿: H/S,治疗辅助宠,宁静+引吭+自然守护
    -- === 亡灵 ===
    [627] = "H/P",   -- 被感染的松鼠: H/P,邪爆HP%+吞噬,亡灵偏攻
    [1740] = "P/S",  -- 幽灵蛆虫: P/S,吸血+疫病+幽魂之咬
    [455] = "P/S",   -- 生病的松鼠: P/S,刨花+激素刺激+奔踏/狂乱之击,亡灵松鼠
    [1238] = "B",    -- 幼年瓦格里: B/B(PvP鬼影先手),社区B/B+H/H都可,标记B/B为共识首选
    -- === 元素 ===
    [509] = "H/S",   -- 袖珍沼泽兽: H/S,痛殴先手晕+鞭笞额外攻击,元素均衡
    [445] = "H/S",   -- 小旋风: H/S社区Vek确认,289速Bash先手+Wild Winds反制水栖
    [519] = "H",     -- 邪焰: H/H,灼燃大地+献祭+焚烧DOT叠加需血量,无P/P可选
    -- === 龙类 ===
    [557] = "P",     -- 虚空精灵龙: P/P,wp=2.30×1.8碾压ws_needs,P/P>591>S/S=565
    [1167] = "P",    -- 翡翠始祖龙宝宝: P/P,翡翠存在+翡翠梦境=Power缩放治疗,P/P最大治疗量
    [1976] = "P",    -- 利爪雏龙: P/P,SCALES_POWER×3飞行,隼龙围攻+狂风+掠食之击
    [1974] = "S",    -- 雪羽雏龙: S/S,隼龙围攻+尖鸣+掠食之击,飞行速攻
    [1975] = "H/P",  -- 恐嘴雏龙: H/P,隼龙围攻+鲁莽之击+掠食之击,SCALES_POWER×2+HEALTH×1
    [3100] = "P",    -- 越时机械幼龙: P/P,火焰吐息+剃刀利爪+末日决战
    [4261] = "B",    -- 黑曜战争雏龙: B/B,烈焰吐息+剃刀利爪+末日决战SUICIDE_HP,龙类均衡
    -- === 人型/野兽 PvP ===
    [514] = "S",     -- 剥石者幼崽: S/S,"head and shoulders better",专注+脚踢+偏斜=先手控
    [1180] = "P",    -- 赞达拉袭胫者: P/P,黑爪+狩猎小队=纯爆发
    [1211] = "P",    -- 赞达拉撕踝者: P/P,Black Claw体系
    [1212] = "P",    -- 赞达拉裂足者: P/P,同上
    [1213] = "P",    -- 赞达拉啮趾者: P/P,社区:P/P>P/S>S/S
    [2537] = "P",    -- 赞达拉迅猛龙宝宝: P/P,同上
    [1387] = "P",    -- 钢铁星弹: P/P,旋紧发条+增压+自爆=最强爆发
    -- === 魔宠 ===
    [343] = "P/S",   -- 暗月豹幼崽: P/S社区确认,P/S>B/B,Devour需Power+Speed先手
    [552] = "H/P",   -- 暮光小恶魔: H/P,1960血魔法被动线686+生命虹吸续航
    [3390] = "P/S",  -- 睿智融合体: P/S,一闪+吸取能量+照亮,NEEDS_SPEED×2元素
    [3034] = "P/S",  -- 托加斯特潜伏者: P/S,鬼影缠身+幽魂之咬+幻象屏障,亡灵均衡
    [1201] = "P/B",  -- 格纳瑟斯的子嗣: P/B,囫囵吞食+潜水+麻痹震击,水栖均衡
    [1720] = "P/S",  -- 艾米苟萨: P/S,爪击+奥术风暴+能量涌动,龙类速攻
    [2469] = "H/S",  -- 荆丛幼芽: H/S,毒枝+日光术+纠缠根须/太阳光,人型治疗
    [267] = "B",     -- 魔化灯笼: B/B,照亮+闪光+灵魂结界,魔法控制
    [1716] = "P",    -- 守望者猫头鹰雏鸟: P/P,飞羽+召唤黑暗+夜袭,飞行爆发
    [2959] = "B",    -- 小灵通: B/B,亡者战队+复活盟友+幽冥之声,亡灵召唤
    [2919] = "P/S",  -- 戈姆刺根者: P/S,切削之风+穿刺+麻痹毒液,SCALES_POWER×3飞行
    [3110] = "P/S",  -- 吉兹莫: P/S,狂抓+潜行+魔力冲撞/虚无之界,野兽速攻
    -- === 机械 ===
    [85] = "H/S",    -- 步行炸弹: H/S,震击+猛击+自爆,NEEDS_SPEED×2+SCALES_POWER×2
    [2717] = "H/P",  -- 微型机器人XD: H/P,警报+震荡干涉+增压/离子炮,NEEDS_SPEED×2机械
    [2718] = "H",    -- 微型机器人8D: H/H,同2717但HH品种
    [2674] = "B",    -- H4ND-EE: B/B,重拳/砍劈+抓握/重建+万能打击/修复,均衡机械
    [2753] = "H",    -- 喷洒机器人0D型: H/H,水流喷射+毒雾喷洒/强化护甲
    [1567] = "P/S",  -- 哨兵之友: P/S,夜袭+月火术+虚无之界,NEEDS_SPEED×2飞行
    -- === 其他 ===
    [1344] = "H/P",  -- 暴怒小箭猪: H/P,灵魂尖刺+侧击+复仇,SCALES_HEALTH+NEEDS_SPEED+SCALES_POWER
    [1185] = "H/S",  -- 幽灵小箭猪: H/S,幽灵打击+灵魂尖刺/幻象屏障+幽魂脊刺,魔法家族
    [485] = "H/P",   -- 石犰狳: H/P,抓挠/痛击+甲壳护盾/咆哮+染疫之爪,SCALES_POWER×2均衡
    [3357] = "H/S",  -- 碧蓝晶刺猪: H/S,尖刺体肤+水晶牢笼+剧毒长牙,魔法坦克
    [2839] = "P/S",  -- 虚痕野兔: P/S,可爱至极/先发优势+虚空震颤,NEEDS_SPEED×2
    [438] = "H",     -- 王蛇: H/H唯一此技能池H/H蛇,高血量+野兽被动+毒牙递增
    [406] = "H",     -- 甲虫: H/H天启战术首选,需活到陨星落下(1806血)
    [1749] = "S",    -- Death Adder: S/S,341速致盲剧毒+Puncture Wound双倍
    -- [3049] 脉动蛆虫: H/H=745vsH/B=740仅差5分,移除COMMUNITY让算法自然决策
    -- [3038] 不朽死亡蟑螂: FORCE_SS(乱舞)已强推S/S,移除COMMUNITY避免与FORCE冲突
    [1073] = "H/B",  -- 塔吉: H/B,酸蚀之触+痛殴+奔踏,人型均衡
    [1181] = "H",    -- 老年巨蟒: H/H社区共识,Beast被动+Poison Fang+Huge Fang生存越长越好
    -- 臭鼬家族: WarcraftPets社区共识H/P(heal吃Power+debuff需血量担伤),S/S=289速不够快
    [633] = "H/P",  -- 山地臭鼬: H/P(有此品种),COMMUNITY覆盖FORCE_SS有效
    -- [397] [823] 无H/P品种, COMMUNITY无法生效, 依赖FORCE_SS自然决策
    -- === 待搜索验证 (已在记忆文件中标记，暂不加COMMUNITY_BONUS) ===
    -- [343] 暗月豹幼崽: P/S — 需搜社区确认
    -- [330] 暗月小猴: ? — 香蕉弹幕+掷桶+咆哮
    -- [383] 锦绣阔步者: ? — 需搜社区确认
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

local function Score(h, p, s, tc, pt, speciesID)
    local fm = FAMILY_MOD[pt] or {h=1.0, p=1.0, s=1.0}

    local wh = (W_BASE + W_HEALTH * (tc["SCALES_HEALTH"] or 0)
                       + W_SUICIDE * (tc["SUICIDE_HP"] or 0)) * fm.h
    local wp = (W_BASE + W_POWER  * (tc["SCALES_POWER"]  or 0)
                       + W_POWER_AMP * (tc["POWER_AMP"] or 0)) * fm.p
    local ws_base  = W_BASE * fm.s
    local ws_needs = W_SPEED * (tc["NEEDS_SPEED"] or 0) * fm.s

    -- 社区共识优先：如COMMUNITY_BREED_BONUS存在,FORCE标签自动让路
    local hasComm = speciesID and COMMUNITY_BREED_BONUS[speciesID]
    if not hasComm then
        if (tc["FORCE_PP"] or 0) > 0 then wp = wp + W_FORCE * p end
        if (tc["FORCE_SS"] or 0) > 0 then ws_needs = ws_needs + W_FORCE * s end
        if (tc["FORCE_HH"] or 0) > 0 then wh = wh + W_FORCE * h end
    end

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
        local score = Score(neutH, neutP, neutS, tc, nil, speciesID)
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
                local bscore, bdetail = Score(h, p, s, btc, petType, speciesID)
                if bscore > bestScore then
                    bestScore, bestDetail, bestBIdx = bscore, bdetail, idx
                end
            end
            -- 无配招时用空标签降级（不应发生，但健壮处理）
            if not bestDetail then
                bestScore, bestDetail = Score(h, p, s, bestTc, petType, speciesID)
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
                    targetCode = commStat == "H" and "H/H" or commStat == "P" and "P/P" or commStat == "S" and "S/S" or commStat == "B" and "B/B" or nil
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
addonTable.GetCommunityBreed = function(speciesID) return COMMUNITY_BREED_BONUS[speciesID] end
