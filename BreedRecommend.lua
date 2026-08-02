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
-- 双场景：PvE / PvP 独立权重 + 独立社区共识

local addonName, addonTable = ...

local BREEDS = addonTable.BREEDS
local SkillTags = addonTable.SkillTags
local ipairs, pairs, type = ipairs, pairs, type
local tsort, mfloor = table.sort, math.floor
local sfind, slower = string.find, string.lower

-- ============================================================================
-- 常量 — 场景独立权重表
-- PvE: 速度价值低(NPC速度已知)/生存高/慢速=坦度加分
-- PvP: 速度价值高(镜像对局)/爆发meta/慢速=先手劣势
-- ============================================================================

local SPEED_THRESHOLDS = {0.8, 1.0, 1.2, 1.4}
local SPEED_BONUS = { [0.8]=1.0, [1.0]=1.1, [1.2]=1.25, [1.4]=1.4 }

local SCENARIO_WEIGHTS = {
    PVE = {
        W_BASE = 1.0, W_SPEED = 0.7, W_POWER = 0.5, W_HEALTH = 0.9,
        W_SUICIDE = 2.0, W_POWER_AMP = 1.5, W_FORCE = 3.0,
        W_COMMUNITY = 3.0, W_SLOW = 1.5, HP_VALUE = 0.67,
        NON_NEEDS_SPEED_PENALTY = 0.85,
    },
    PVP = {
        W_BASE = 1.0, W_SPEED = 1.2, W_POWER = 0.4, W_HEALTH = 0.6,
        W_SUICIDE = 1.5, W_POWER_AMP = 1.5, W_FORCE = 3.0,
        W_COMMUNITY = 3.0, W_SLOW = 0.3, HP_VALUE = 0.5,
        NON_NEEDS_SPEED_PENALTY = 1.0,
    },
}
local SCALE = 100

-- 家族被动修正 — PvE
local FAMILY_MOD_PVE = {
    [1]  = { h=1.0, p=1.15, s=1.0 },
    [2]  = { h=1.0, p=1.15, s=1.0 },
    [3]  = { h=1.0, p=1.1, s=1.0 },
    [4]  = { h=1.0, p=1.3, s=1.0 },
    [5]  = { h=1.1, p=1.0, s=1.0 },
    [6]  = { h=1.3, p=1.0, s=0.8 },
    [7]  = { h=1.0, p=1.0, s=1.0 },
    [8]  = { h=1.0, p=1.0, s=1.0 },
    [9]  = { h=1.0, p=1.1, s=1.0 },
    [10] = { h=1.0, p=1.2, s=1.0 },
}

-- 家族被动修正 — PvP
local FAMILY_MOD_PVP = {
    [1]  = { h=1.0, p=1.1,  s=1.05 },
    [2]  = { h=1.0, p=1.1,  s=1.05 },
    [3]  = { h=1.0, p=1.0,  s=1.15 },
    [4]  = { h=1.0, p=1.25, s=1.05 },
    [5]  = { h=1.05,p=1.0,  s=1.05 },
    [6]  = { h=1.2, p=1.0,  s=0.9  },
    [7]  = { h=1.0, p=1.0,  s=1.0  },
    [8]  = { h=1.0, p=1.0,  s=1.0  },
    [9]  = { h=1.0, p=1.05, s=1.05 },
    [10] = { h=1.0, p=1.15, s=1.05 },
}

-- ============================================================================
-- 社区共识加权表（双场景感知格式）
-- 格式: [speciesID] = {pve="X"|nil, pvp="X"|nil, note="来源说明"}
--   nil = 此场景无社区共识，算法独立决策
--   旧格式 string 仍兼容（视为通用共识）
-- ============================================================================
local COMMUNITY_BREED_BONUS = {
    -- ====== 两场景通用共识（家族/社区/技能分析） ======
    -- 蜘蛛家族
    [412] = {pve="S", pvp="S", note="蜘蛛家族共识,网→毒→幼蛛先手"},
    [470] = {pve="P", pvp="P", note="暮光蜘蛛:仅3品种无S/S可选"},
    [484] = {pve="P/S", pvp="P/S", note="沙漠蜘蛛社区确认"},
    [407] = {pve="P/S", pvp="P/S", note="林地小蜘蛛社区确认"},
    [1726] = {pve="S", pvp="S", note="潜地小蜘蛛,3NEED标签自然偏速"},
    [3007] = {pve="P/B", pvp="P/B", note="粉腿小蜘蛛,生命虹吸+传染打击"},
    [428] = {pve="S", pvp="S", note="熔火幼蛛社区主导,先手尖网控场"},
    [3202] = {pve="S", pvp="S", note="元蛛追猎者,蜘蛛控场型"},
    [637] = {pve="S", pvp="S", note="敏捷洞穴蛛,蜘蛛控场全S/S"},
    -- 老鼠家族
    [398] = {pve="S", pvp="S", note="老鼠家族共识,乱舞+奔踏先手"},
    [454] = {pve="S", pvp="S", note="幽暗城老鼠,同老鼠家族"},
    [410] = {pve="S", pvp="S", note="码头老鼠,同老鼠家族"},
    [1427] = {pve="P", pvp="P", note="霜鬃鼠社区确认,爆发流"},
    [4277] = {pve="S", pvp="S", note="树液啮咬者,啮齿类Flurry系S/S"},
    [392] = {pve="S", pvp="S", note="赤脊山老鼠,Flurry系全S/S"},
    [553] = {pve="S", pvp="S", note="偷渡老鼠,同Flurry系"},
    [709] = {pve="S", pvp="S", note="南洋箭鼠,同啮齿Flurry系"},
    -- 兔子/松鼠家族
    [391] = {pve="S", pvp="S", note="兔子家族共识,乱舞+钻地+躲闪"},
    [448] = {pve="S", pvp="S", note="野兔,同兔子家族+奔踏"},
    [443] = {pve="S", pvp="S", note="草地短尾兔,同兔子家族"},
    [441] = {pve="S", pvp="S", note="高山野兔社区明确,357速Dodge+Burrow"},
    [641] = {pve="S", pvp="S", note="极地野兔社区确认,兔子家族"},
    [379] = {pve="S", pvp="S", note="松鼠家族共识,坚果弹幕+奔踏+蜷伏"},
    [452] = {pve="S", pvp="S", note="红尾花栗鼠,松鼠家族S/S"},
    [647] = {pve="S", pvp="S", note="灰色松鼠,松鼠家族全S/S"},
    [3278] = {pve="S", pvp="S", note="开心果,FORCE_SS坚果弹幕"},
    [137] = {pve="S", pvp="S", note="棕兔,兔子家族全S/S"},
    [378] = {pve="S", pvp="S", note="兔子,家族S/S共识"},
    [487] = {pve="S", pvp="S", note="高山花栗鼠,松鼠家族全S/S"},
    [730] = {pve="S", pvp="S", note="多莱兔仔,兔子家族S/S"},
    [1729] = {pve="S", pvp="S", note="绿尾野兔,野兔全S/S"},
    [1778] = {pve="S", pvp="S", note="烟灰野兔,野兔全S/S"},
    [3191] = {pve="S", pvp="S", note="胆小的元兔,兔子家族Dodge+Burrow"},
    -- 土拨鼠
    [386] = {pve="S", pvp="S", note="草原土拨鼠,仅3品种S/S最优"},
    [549] = {pve="P/B", pvp="P/B", note="黄腹土拨鼠,自加速技P/B反超"},
    -- 甲虫家族
    [415] = {pve="H/P", pvp="H/P", note="火甲虫社区推荐,无P/P可选"},
    [429] = {pve="P", pvp="P", note="熔火甲虫社区especially P/P"},
    [2843] = {pve="B", pvp="B", note="虚痕甲虫均衡B/B"},
    [430] = {pve="S", pvp="S", note="金甲虫(经典)唯一S/S品种"},
    [2387] = {pve="P", pvp="S/B", note="金甲虫(BFA)WarcraftPets obvious P/P坦克流(Lordy S/B PvP先手)"},
    -- 蛇/蝎家族
    [425] = {pve="P/S", pvp="P/S", note="燃灰蝰蛇,无S/S选P/S"},
    [432] = {pve="P/S", pvp="P/S", note="纹尾蝎社区Vek确认"},
    -- 蟹
    [388] = {pve="H", pvp="H", note="海滨蟹,双治疗坦克"},
    [746] = {pve="P", pvp="P", note="君王蟹,蟹类PvP速攻"},
    [401] = {pve="H", pvp="H", note="海湾蟹,双治疗坦克"},
    [564] = {pve="H", pvp="H", note="翡翠乌龟,龟类坦克"},
    [572] = {pve="P", pvp="P", note="塔边小蟹,蟹类速攻"},
    [1583] = {pve="P", pvp="P", note="海藻凿孔蟹,螃蟹速攻"},
    [463] = {pve="H", pvp="H", note="灵魂蟹,坦克型"},
    [723] = {pve="H", pvp="H", note="棘刺水龟,龟类坦克H/H"},
    -- 青蛙/蟾蜍
    [419] = {pve="S/B", pvp="S/B", note="小青蛙,治疗波+净化雨"},
    [420] = {pve="H/P", pvp="H/P", note="蟾蜍,唯一H/P品种"},
    [648] = {pve="H/P", pvp="H/P", note="大蟾蜍,同420"},
    -- 蜗牛
    [493] = {pve="H/P", pvp="H/P", note="闪光湖蜗牛,最高攻蜗牛"},
    [3482] = {pve="H/P", pvp="H/P", note="圆石之壳,蜗牛H/P共识"},
    [743] = {pve="H/B", pvp="H/B", note="拉帕纳海螺社区共识,无H/H品种"},
    -- 蛾/蝴蝶（家族共识: P/P或P/S, 飞行被动给速度→功率优先）
    [478] = {pve="P/S", pvp="P/S", note="森林蛾,蛾家族共识P/P或P/S(飞行被动给速)"},
    [2384] = {pve="P", pvp="P",   note="海滨蝴蝶,Xu-Fu推荐P/P(基础速度太低S/S浪费)"},
    [1325] = {pve="P/S", pvp="P/S", note="焰光蛾,蛾类P/P或P/S共识"},
    [1587] = {pve="P/S", pvp="P/S", note="皇家飞蛾,同蛾类家族"},
    -- 鸟/猫头鹰
    [548] = {pve="P", pvp="P", note="蛮锤狮鹫社区no-brainer P/P"},
    [646] = {pve="S", pvp="S", note="鸡,S/S(P/P也可)"},
    [1068] = {pve="S", pvp="S", note="乌鸦,空袭+暗黑+夜袭very rare best"},
    [1572] = {pve="S", pvp="S", note="夺目红羽雀,飞行速度S/S"},
    -- 蝙蝠
    [626] = {pve="P", pvp="P", note="蝙蝠家族P/P共识,鲁莽之击spam"},
    [1762] = {pve="P", pvp="P", note="猪鼻蝙蝠,蝙蝠家族P/P"},
    -- 鹿/羊
    [447] = {pve="H/S", pvp="H/S", note="小鹿,治疗吃Power需HS均衡"},
    [374] = {pve="H/P", pvp="H/P", note="黑羔羊,高血高攻"},
    [1913] = {pve="H/S", pvp="P", note="闪蹄小鹿,PvE治疗辅助H/S,PvP Xu-Fu推荐P/P"},
    -- 亡灵
    [627] = {pve="H/P", pvp="H/P", note="被感染松鼠,邪爆HP%+吞噬"},
    [1740] = {pve="P/S", pvp="P/S", note="幽灵蛆虫,吸血+疫病+幽魂"},
    [455] = {pve="P/S", pvp="P/S", note="生病松鼠,亡灵松鼠速攻"},
    [1238] = {pve="B", pvp="B", note="幼年瓦格里,社区B/B+H/H都可"},
    -- 元素
    [509] = {pve="H/S", pvp="H/S", note="袖珍沼泽兽,痛殴先手+鞭笞"},
    [1328] = {pve="H/S", pvp="H/S", note="红宝石小水滴社区确认"},
    [445] = {pve="H/S", pvp="H/S", note="小旋风社区Vek确认289速Bash"},
    [519] = {pve="H", pvp="H", note="邪焰H/H DOT叠加需血量"},
    -- 龙类
    [557] = {pve="P", pvp="P", note="虚空精灵龙,P/P碾压ws_needs"},
    [1167] = {pve="P", pvp="P", note="翡翠始祖龙宝宝,Power缩放治疗"},
    [1976] = {pve="P", pvp="P", note="利爪雏龙,SCALES_POWERx3"},
    [1974] = {pve="S", pvp="S", note="雪羽雏龙,隼龙围攻+飞羽"},
    [1975] = {pve="H/P", pvp="H/P", note="恐嘴雏龙,SCALES_POWERx2+HEALTH"},
    [3100] = {pve="P", pvp="P", note="越时机械幼龙,末日决战SUICIDE"},
    [4261] = {pve="B", pvp="B", note="黑曜战争雏龙,龙类均衡SUICIDE"},
    -- 人型/野兽 PvP通用
    [514] = {pve="S", pvp="S", note="剥石者幼崽head and shoulders better"},
    [1180] = {pve="P", pvp="P", note="赞达拉袭胫者,黑爪+狩猎小队"},
    [1211] = {pve="P", pvp="P", note="赞达拉撕踝者,Black Claw体系"},
    [1212] = {pve="P", pvp="P", note="赞达拉裂足者,同上"},
    [1213] = {pve="P", pvp="P", note="赞达拉啮趾者,社区P/P>P/S>S/S"},
    [2537] = {pve="P", pvp="P", note="赞达拉迅猛龙宝宝,同上"},
    [1387] = {pve="P", pvp="P", note="钢铁星弹,最强爆发combo"},
    -- 魔宠
    [343] = {pve="P/S", pvp="P/S", note="暗月豹幼崽社区确认P/S>B/B"},
    [552] = {pve="H/P", pvp="H/P", note="暮光小恶魔,高血魔被动"},
    [3390] = {pve="P/S", pvp="P/S", note="睿智融合体,NEEDS_SPEEDx2"},
    [3034] = {pve="P/S", pvp="P/S", note="托加斯特潜伏者,亡灵均衡"},
    [1201] = {pve="P/B", pvp="P/B", note="格纳瑟斯子嗣,水栖均衡"},
    [1720] = {pve="P/S", pvp="P/S", note="艾米苟萨,龙类速攻"},
    [2469] = {pve="H/S", pvp="H/S", note="荆丛幼芽,人型治疗"},
    [267] = {pve="B", pvp="B", note="魔化灯笼,魔法控制B/B"},
    [1716] = {pve="P", pvp="P", note="守望者猫头鹰雏鸟,飞行爆发"},
    [2959] = {pve="B", pvp="B", note="小灵通,亡灵召唤B/B"},
    [2919] = {pve="P/S", pvp="P/S", note="戈姆刺根者,SCALES_POWERx3"},
    [3110] = {pve="P/S", pvp="P/S", note="吉兹莫,野兽速攻"},
    -- 机械
    [85] = {pve="H/S", pvp="H/S", note="步行炸弹,NEEDS_SPEEDx2+SCALES_POWERx2"},
    [2717] = {pve="H/P", pvp="H/P", note="微型机器人XD,NEEDS_SPEEDx2"},
    [2718] = {pve="H", pvp="H", note="微型机器人8D,同XD但HH"},
    [2674] = {pve="B", pvp="B", note="H4ND-EE,均衡机械B/B"},
    [2753] = {pve="H", pvp="H", note="喷洒机器人0D,水流+毒雾"},
    [1567] = {pve="P/S", pvp="P/S", note="哨兵之友,NEEDS_SPEEDx2飞行"},
    -- 其他通用
    [733] = {pve="S", pvp="S", note="草地欢跳者,PetBreedSurvey54%S/S"},
    [1344] = {pve="H/P", pvp="H/P", note="暴怒小箭猪,SCALESx3均衡"},
    [1185] = {pve="H/S", pvp="H/S", note="幽灵小箭猪,魔法家族"},
    [485] = {pve="H/P", pvp="H/P", note="石犰狳,SCALES_POWERx2均衡"},
    [3357] = {pve="H/S", pvp="H/S", note="碧蓝晶刺猪,魔法坦克"},
    [2839] = {pve="P/S", pvp="P/S", note="虚痕野兔,NEEDS_SPEEDx2"},
    [438] = {pve="H", pvp="H", note="王蛇,高血量+野兽被动+毒牙递增"},
    [406] = {pve="H", pvp="H", note="甲虫,天启战术需活到陨星"},
    [1749] = {pve="S", pvp="S", note="DeathAdder,341速致盲毒+PunctureWound"},
    [1073] = {pve="H/B", pvp="H/B", note="塔吉,酸蚀+痛殴+奔踏"},
    [1181] = {pve="H", pvp="H", note="老年巨蟒社区共识H/H"},
    [633] = {pve="H/P", pvp="H/P", note="山地臭鼬,社区共识H/P"},
    -- 蟑螂家族
    [55] = {pve="S", pvp="S", note="蟑螂家族共识S/S"},
    [424] = {pve="S", pvp="S", note="蟑螂家族共识S/S"},
    [541] = {pve="S", pvp="S", note="蟑螂家族共识,乱舞+生存本能先手"},
    [555] = {pve="S", pvp="S", note="蟑螂家族共识S/S"},
    [638] = {pve="S", pvp="S", note="蟑螂家族共识S/S"},
    [744] = {pve="S", pvp="S", note="蟑螂家族共识S/S"},
    -- PvE 侧重
    [2383] = {pve="P/S", pvp=nil, note="巨型蛀虫PvE攻速均衡,无S/S品种"},
    [4659] = {pve="P", pvp="P", note="卡亚蟹PvE爆发,汹涌优先+嚣狂自残高攻速杀"},
    -- ====== PvP 专属共识（Xu-Fu Best of each Family） ======
    [513] = {pve=nil, pvp="S", note="[Xu-Fu PvP]幼年其拉守护者速控, PvE算法推P/P"},
    [515] = {pve=nil, pvp="S", note="[Xu-Fu PvP]孢子芽速攻"},
    [1470] = {pve=nil, pvp="P", note="[Xu-Fu PvP]斧喙雏鸟飞行爆发"},
    [538] = {pve=nil, pvp="H", note="[Xu-Fu PvP]天灾雏龙亡灵坦克"},
    [456] = {pve=nil, pvp="P/S", note="[Xu-Fu PvP]疫喉雏鸟亡灵均衡"},
    [494] = {pve=nil, pvp="H/P", note="[Xu-Fu PvP]其拉甲虫野兽坦克"},
    [1166] = {pve=nil, pvp="P/S", note="[Xu-Fu PvP]昆莱小雪人人型均衡"},
    [2372] = {pve=nil, pvp="S", note="[Xu-Fu PvP]影背爬蟹速攻"},
    [2646] = {pve=nil, pvp="P/B", note="[Xu-Fu PvP]沙爪阳壳蟹水栖爆发"},
    [2866] = {pve=nil, pvp="S", note="[Xu-Fu PvP]虚空荧光飞行速攻"},
    [140] = {pve=nil, pvp="P", note="[Xu-Fu PvP]黄蛾唯一P/P蛾"},
    [2902] = {pve=nil, pvp="S", note="[Xu-Fu PvP]暗色惊惧之翼飞行毒雾"},
    [2380] = {pve=nil, pvp="P", note="[Xu-Fu PvP]寄生野猪蝇飞行爆发"},
    [1965] = {pve=nil, pvp="H/P", note="[Xu-Fu PvP]疫息亡灵DOT坦克"},
    [1600] = {pve=nil, pvp="S", note="[Xu-Fu PvP]骨蛇亡灵速攻"},
    [1968] = {pve=nil, pvp="S", note="[Xu-Fu PvP]邪恶灵魂亡灵速控"},
    [1432] = {pve=nil, pvp="S", note="[Xu-Fu PvP]夜影幼苗元素速攻"},
    [1429] = {pve=nil, pvp="P", note="[Xu-Fu PvP]暮秋幼苗元素爆发"},
    [2808] = {pve=nil, pvp="H/P", note="[Xu-Fu PvP]小弗兹元素坦克"},
    [1563] = {pve=nil, pvp="S", note="[Xu-Fu PvP]青铜幼龙唯一S/S龙类幼崽"},
    [1385] = {pve=nil, pvp="S", note="[Xu-Fu PvP]白化奇美拉幼崽龙类速攻"},
    [142] = {pve=nil, pvp="S", note="[Xu-Fu PvP]金色龙鹰宝宝龙类速攻"},
    [1229] = {pve=nil, pvp="S", note="[Xu-Fu PvP]恶魔小鬼人型速攻"},
    [1953] = {pve=nil, pvp="S", note="[Xu-Fu PvP]雪怪矮人人型速控"},
    [1495] = {pve=nil, pvp="S", note="[Xu-Fu PvP]石食者人型速控"},
    [1964] = {pve=nil, pvp="S", note="[Xu-Fu PvP]血沸魔法速攻"},
    [389] = {pve=nil, pvp="S", note="[Xu-Fu PvP]小小收割者机械速攻"},
    [2001] = {pve=nil, pvp="H/P", note="[Xu-Fu PvP]呆博勒机械坦克"},
    [1565] = {pve=nil, pvp="S", note="[Xu-Fu PvP]机械蝎子机械速攻"},
    [254] = {pve=nil, pvp="S", note="[Xu-Fu PvP]蓝发条火箭机器人机械速攻"},
    [2864] = {pve=nil, pvp="H/B", note="[Xu-Fu PvP]虚痕蝗虫小动物生存"},
    [724] = {pve=nil, pvp="S", note="[Xu-Fu PvP]高山幼狐野兽速攻"},
    [1330] = {pve=nil, pvp="S", note="[Xu-Fu PvP]致死小蝰蛇蛇族先手combo"},
    [2660] = {pve=nil, pvp="H/P", note="[Xu-Fu PvP]泥蛞蝓小动物坦克"},
    [2133] = {pve=nil, pvp="S", note="[Xu-Fu PvP]侏儒玛苏尔小动物速攻"},
    -- === 待搜索验证 ===
    -- [330] 暗月小猴 / [383] 锦绣阔步者
}

-- ============================================================================
-- Layer 2: 自动分类关键词（精炼版）
-- ============================================================================
local AUTO_TAGS = (function()
    local kw = addonTable.AUTO_TAG_KEYWORDS
    local key = (GetLocale() == "zhCN" or GetLocale() == "zhTW") and "zhCN" or "enUS"
    return {
        NEEDS_SPEED   = kw.NEEDS_SPEED[key],
        SCALES_POWER  = kw.SCALES_POWER[key],
        SCALES_HEALTH = kw.SCALES_HEALTH[key],
        SCALES_SLOW   = kw.SCALES_SLOW[key],
    }
end)()

local autoTagCache = {}
local speciesBuildCache = {}

-- ============================================================================
-- 否定词过滤
-- ============================================================================
local NEGATE_PATTERNS = {
    SCALES_HEALTH = {
        "阻止.*回复", "无法.*回复", "不能.*回复", "禁止.*回复",
        "不会.*回复", "不再.*回复", "防止.*回复",
        "阻止.*治疗", "无法.*治疗", "不能.*治疗", "禁止.*治疗",
        "阻止.*治愈", "无法.*治愈",
        "使.*目标.*伤.*降低", "降低.*目标.*伤",
        "prevent.*heal", "prevent.*restore", "prevent.*recover",
        "cannot.*heal", "unable.*heal", "stop.*heal",
        "block.*heal", "block.*restore",
        "enemy.*deal.*less", "reduce.*enemy.*damage", "target.*deal.*less",
    },
    SCALES_POWER = {
        "受到.*攻击.*速度", "受到.*攻击.*闪避",
        "when.*attacked.*speed", "when.*struck.*speed",
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

    local text = slower(name .. " " .. desc)

    local cleaned, depth = "", 0
    for i = 1, #text do
        local c = text:sub(i, i)
        if c == "[" then depth = depth + 1
        elseif c == "]" and depth > 0 then depth = depth - 1
        elseif depth == 0 then cleaned = cleaned .. c
        end
    end
    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:gsub("。", "\n")
    local tags = {}
    for tag, patterns in pairs(AUTO_TAGS) do
        for _, pat in ipairs(patterns) do
            for sentence in cleaned:gmatch("[^\n]+") do
                local negated = false
                local negList = NEGATE_PATTERNS[tag]
                if negList then
                    for _, negPat in ipairs(negList) do
                        if sfind(sentence, negPat) then negated = true; break end
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
-- 配招枚举
-- ============================================================================

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

local function GetAbilityName(aid)
    local _, _, aname = pcall(C_PetBattles.GetAbilityInfoByID, aid)
    return aname or "?"
end

-- ============================================================================
-- 评分函数
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

local function Score(h, p, s, tc, pt, speciesID, breedHas, scenario)
    scenario = scenario or "PVE"
    local w = SCENARIO_WEIGHTS[scenario]
    local fmTbl = (scenario == "PVP") and FAMILY_MOD_PVP or FAMILY_MOD_PVE
    local fm = fmTbl[pt] or {h=1.0, p=1.0, s=1.0}

    local wh = (w.W_BASE + w.W_HEALTH * (tc["SCALES_HEALTH"] or 0)
                       + w.W_SUICIDE * (tc["SUICIDE_HP"] or 0)) * fm.h
    local wp = (w.W_BASE + w.W_POWER  * (tc["SCALES_POWER"]  or 0)
                       + w.W_POWER_AMP * (tc["POWER_AMP"] or 0)) * fm.p
    local ws_base  = w.W_BASE * fm.s
    local ws_needs = w.W_SPEED * (tc["NEEDS_SPEED"] or 0) * fm.s

    local commData = speciesID and COMMUNITY_BREED_BONUS[speciesID]
    local hasComm = false
    if commData then
        if type(commData) == "table" then
            hasComm = (scenario == "PVP" and commData.pvp) or (scenario == "PVE" and commData.pve)
        else
            hasComm = true
        end
    end
    if not hasComm then
        if (tc["FORCE_PP"] or 0) > 0 and (not breedHas or breedHas[4]) then wp = wp + w.W_FORCE * p end
        if (tc["FORCE_SS"] or 0) > 0 and (not breedHas or breedHas[5]) then ws_needs = ws_needs + w.W_FORCE * s end
        if (tc["FORCE_HH"] or 0) > 0 and (not breedHas or breedHas[6]) then wh = wh + w.W_FORCE * h end
    end

    local sb = 1.0
    if (tc["NEEDS_SPEED"] or 0) > 0 then sb = SpeedBonus(s) end

    local ws = ws_base
    if (tc["NEEDS_SPEED"] or 0) == 0 then ws = ws * w.NON_NEEDS_SPEED_PENALTY end

    local slow_bonus = w.W_SLOW * (tc["SCALES_SLOW"] or 0) * (2.0 - s)

    local raw = wp * p + ws * s + ws_needs * sb + wh * h * w.HP_VALUE + slow_bonus
    return raw * SCALE, {wh=wh,wp=wp,ws=ws,sb=sb,ws_base=ws_base,ws_needs=ws_needs,slow_bonus=slow_bonus}
end

local function CollectTags(speciesID)
    local cached = speciesBuildCache[speciesID]
    if cached then return cached.bestTagCounts end

    local results = { C_PetJournal.GetPetAbilityList(speciesID) }
    local at = results[1]
    if not at or type(at) ~= "table" then return {} end

    local slots = GroupAbilitiesBySlot(at)
    local builds = EnumerateBuilds(slots)
    if #builds == 0 then return {} end

    if #builds == 1 then
        local tc = ComputeBuildTags(builds[1])
        speciesBuildCache[speciesID] = {bestBuild=1, bestTagCounts=tc, allBuilds=builds, slots=slots}
        return tc
    end

    local bestBuildIdx, bestScore = 1, -1
    local neutH, neutP, neutS = 1.0, 1.0, 1.0
    for idx, build in ipairs(builds) do
        local tc = ComputeBuildTags(build)
        local score = Score(neutH, neutP, neutS, tc, nil, speciesID, nil, "PVE")
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

function addonTable.DumpSpeciesAbilities(speciesID, petType)
    if not speciesID then return end
    if not petType then petType = GetPetType(speciesID) end
    local vals = {C_PetJournal.GetPetInfoBySpeciesID(speciesID)}
    local name = type(vals[1])=="string" and vals[1] or "?"

    local bestTc = CollectTags(speciesID)
    local cached = speciesBuildCache[speciesID]
    local slots = cached and cached.slots or {}
    local builds = cached and cached.allBuilds or {}

    local parts = {}
    if bestTc and next(bestTc) then
        for tag, count in pairs(bestTc) do parts[#parts+1] = tag .. "\195\151" .. count end
        table.sort(parts)
    end
    local suffix = (#builds > 1) and string.format(" (best of %d builds)", #builds) or ""
    print(string.format("[GenDexDBG] skills: pet=%s sid=%d  tags={%s}%s",
        name, speciesID, #parts>0 and table.concat(parts, ", ") or "", suffix))
    print("|cffffd700=== [GenDexDBG] speciesID=" .. tostring(speciesID) .. " (" .. name .. ") petType=" .. tostring(petType) .. " ===|r")

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

function addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, topN, scenario)
    scenario = scenario or "PVE"
    if not speciesID then return {} end; if not petType then petType = GetPetType(speciesID) end

    local bestTc = CollectTags(speciesID)
    local cached = speciesBuildCache[speciesID]
    local builds = cached and cached.allBuilds or {}
    local bestBuildIdx = cached and cached.bestBuild or 1

    local doDebug = GeneDexDB and GeneDexDB.Options and GeneDexDB.Options.DebugRecommend
    if doDebug then
        addonTable.DumpSpeciesAbilities(speciesID, petType)
        if #builds > 1 then
            print("  Builds (" .. #builds .. " total):")
            for idx, build in ipairs(builds) do
                local names = {}
                for _, aid in ipairs(build.abilities) do names[#names+1] = GetAbilityName(aid) end
                local btc = ComputeBuildTags(build)
                local btparts = {}
                if btc and next(btc) then
                    for tag, count in pairs(btc) do btparts[#btparts+1] = tag .. "\195\151" .. count end
                    table.sort(btparts)
                end
                local marker = (idx == bestBuildIdx) and " \226\134\144 best" or ""
                print(string.format("  B%d %s  tags={%s}%s",
                    idx, table.concat(names, "+"), table.concat(btparts, ", "), marker))
            end
            print("--- Per-breed best-build scores ---")
        end
        print("--- Final scores [" .. scenario .. "] ---")
        print(string.format("  %-6s %8s %8s %8s %8s %8s %8s %8s", "Breed","Score","wH","wP","wS-Base","wS-Need","S-Bns","Raw"))
    end

    local breeds = {}
    if possibleBreedIDs and type(possibleBreedIDs)=="table" and #possibleBreedIDs>0 then
        for _,bid in ipairs(possibleBreedIDs)do if BREEDS[bid]then breeds[#breeds+1]=bid end end
    end
    if #breeds==0 then for bid=3,14 do if BREEDS[bid]then breeds[#breeds+1]=bid end end end

    local breedHas = {}
    for _, bid in ipairs(breeds) do breedHas[bid] = true end

    local rs = {}
    for _,bid in ipairs(breeds)do
        local br = BREEDS[bid]
        if br then
            local h,p,s = br[1],br[2],br[3]
            local code = addonTable.GetBreedCode and addonTable.GetBreedCode(bid) or "?"

            local bestScore, bestDetail, bestBIdx = -9999, nil, bestBuildIdx
            for idx, build in ipairs(builds) do
                local btc = ComputeBuildTags(build)
                local bscore, bdetail = Score(h, p, s, btc, petType, speciesID, breedHas, scenario)
                if bscore > bestScore then
                    bestScore, bestDetail, bestBIdx = bscore, bdetail, idx
                end
            end
            if not bestDetail then
                bestScore, bestDetail = Score(h, p, s, bestTc, petType, speciesID, breedHas, scenario)
            end

            local score = bestScore
            local detail = bestDetail

            if addonTable.BREED_AMBIGUITY and addonTable.BREED_AMBIGUITY[bid] then score = score - 1 end

            local commRaw = COMMUNITY_BREED_BONUS[speciesID]
            local commStat = nil
            if commRaw then
                if type(commRaw) == "table" then
                    commStat = (scenario == "PVP") and commRaw.pvp or commRaw.pve
                else
                    commStat = commRaw
                end
            end
            local commBonus = 0
            if commStat then
                local targetCode
                if #commStat == 1 then
                    targetCode = commStat == "H" and "H/H" or commStat == "P" and "P/P" or commStat == "S" and "S/S" or commStat == "B" and "B/B" or nil
                else
                    targetCode = commStat
                end
                if targetCode and code == targetCode then
                    local wComm = SCENARIO_WEIGHTS[scenario].W_COMMUNITY
                    commBonus = wComm * SCALE
                    score = score + commBonus
                end
            end
            if doDebug then
                local w = SCENARIO_WEIGHTS[scenario]
                print(string.format("  %-6s %8d %8.2f %8.2f %8.2f %8.2f %8.2f %8.2f",
                    code,mfloor(score+0.5),detail.wh,detail.wp,
                    detail.ws_base or 0,detail.ws_needs or 0,detail.sb,
                    detail.wp*p + detail.ws*s + (detail.ws_needs or 0)*detail.sb + detail.wh*h*w.HP_VALUE))
                if commBonus > 0 then
                    print(string.format("    \226\134\145 +%d Community (scenario=%s)", commBonus, scenario))
                end
            end
            local breedBtc = (bestBIdx > 0 and builds[bestBIdx]) and ComputeBuildTags(builds[bestBIdx]) or bestTc
            rs[#rs+1]={breedID=bid,score=mfloor(score+0.5),breedCode=code,
                       stats={h_coef=h,p_coef=p,s_coef=s},details=detail,tagCounts=breedBtc,
                       hasCommunity=commStat~=nil}
        end
    end

    tsort(rs, function(a,b)return a.score>b.score end)
    topN=topN or 3
    if #rs>topN then local t={};for i=1,topN do t[i]=rs[i]end;return t end
    return rs
end

function addonTable.RecommendBestBreed(speciesID,petType,possibleBreedIDs)
    local rs = addonTable.CalculateBreedScores(speciesID,petType,possibleBreedIDs,1,"PVE")
    if #rs>0 then return rs[1].breedID,rs[1].breedCode,rs[1].score end
    return nil,nil,nil
end

function addonTable.CalculateDualScores(speciesID, petType, possibleBreedIDs, topN)
    return {
        pve = addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, topN, "PVE"),
        pvp = addonTable.CalculateBreedScores(speciesID, petType, possibleBreedIDs, topN, "PVP"),
    }
end

addonTable.CollectSkillTags = CollectTags
addonTable.GetSkillTags = function() return SkillTags end

addonTable.GetCommunityBreed = function(speciesID, scenario)
    local raw = COMMUNITY_BREED_BONUS[speciesID]
    if not raw then return nil end
    if type(raw) == "table" then
        if scenario == "PVP" then return raw.pvp end
        if scenario == "PVE" then return raw.pve end
        return raw.pve or raw.pvp
    end
    return raw
end

addonTable.GetCommunityBreedNote = function(speciesID)
    local raw = COMMUNITY_BREED_BONUS[speciesID]
    if type(raw) == "table" then return raw.note end
    return nil
end

addonTable.IsCommunityConsensus = function(speciesID, scenario)
    return addonTable.GetCommunityBreed(speciesID, scenario) ~= nil
end
