-- GenDexBD Data_SkillTags.lua
-- 手工精标Layer 1（FORCE_*仅在此生效）

local addonName, addonTable = ...

local RAW_TAGS = {
    NEEDS_SPEED = {
        362, 312, 821, 231, 311,
        162, 418, 713, 247, 750,
        2214,
        504, -- 空袭：率先攻击则额外伤害（先手机制）
        382, -- 尖网：反伤网罩需先手设网
    },
    SCALES_POWER = {
        406, 538, 421, 491, 593, 920, 349, 621, 117,
        160, -- 吞噬：吸血回复（兼有HP→SCALES_HEALTH）
        163, -- 奔踏：3轮多段攻击
        666, -- 狂乱之击：目标受伤害+50%增伤debuff
        250, -- 幼蛛群袭：网住双倍伤害（条件爆发）
        186, -- 鲁莽之击：高额飞行伤害(spam型自残攻击)
        517, -- 夜袭：致盲条件必定命中(高爆发)
        382, -- 尖网：反伤网罩（目标每次攻击受伤害）
        743, -- 蠕行真菌：每轮DoT
        706, -- 蜂拥：3轮多段攻击
        519, -- 天启：延迟秒杀+感染DoT
        448, -- 蠕行软泥：每轮额外DoT
        123, -- 治疗波：StandardDamage攻击力缩放治疗(非HP缩放)
        581, -- 群殴：3轮多段攻击+增伤debuff(同奔踏)
    },
    SCALES_HEALTH = {
        282, 136, 821, 160,
        -- 163奔踏debuff、283生存免死 不标HP: 不依赖宠物自身血量
    },
    FORCE_PP = { 919, 921 },
    FORCE_SS = {
        167, -- 坚果弹幕: 松鼠签名技,社区明确S/S最优
    },
    FORCE_HH = {},
}

addonTable.SkillTags = {}
for tag, skillList in pairs(RAW_TAGS) do
    for _, skillID in ipairs(skillList) do
        if not addonTable.SkillTags[skillID] then
            addonTable.SkillTags[skillID] = {}
        end
        addonTable.SkillTags[skillID][tag] = true
    end
end
addonTable.RAW_SKILL_TAGS = RAW_TAGS
