-- GenDexBD Data_SkillTags.lua
-- 生成时间: 2026-07-20 持续迭代
-- 技能标签数据库（手动精标Layer 1）
-- FORCE_* 标签仅在此处生效，自动分类器不产生 FORCE_*

local addonName, addonTable = ...

local RAW_TAGS = {
    -- 先手依赖：打断/闪避/致盲/飞天钻地/装死/换宠/控制
    NEEDS_SPEED = {
        362, 118, 312, 492, 228, 298, 821, 231, 311,
        158, 162, 254, 418, 488, 252, 713, 920, 247, 750,
        2214, -- 尾击：迫使敌人换宠（控制技能）
    },

    -- 攻击加成：多段伤害/DoT/流血/高额爆发
    SCALES_POWER = {
        406, 538, 421, 491, 593, 920, 367, 349, 621, 117,
        160, -- 吞噬：造成伤害（兼有吸血→SCALES_HEALTH）
        163, -- 奔踏：3轮多段攻击（兼有增伤debuff→SCALES_HEALTH）
    },

    -- 血量加成：百分比回血/吸血/换血/基于HP伤害/护盾/增伤debuff
    SCALES_HEALTH = {
        163, -- 奔踏：增伤debuff（受到伤害提高）
        282, -- 自爆：基于总生命值%
        136, -- 吞噬(Devour)：百分比回血
        504, -- 血水：斩杀
        821, -- 茧击：伤害吸收
        160, -- 吞噬(Consume)：吸血回复
    },

    -- 强制纯攻击 P/P（社区共识确认：Black Claw体系等）
    FORCE_PP = {
        919, -- 黑爪：Black Claw体系核心 → 纯攻击爆发
        921, -- 狩猎小队：多段攻击+增伤debuff
    },

    -- 强制纯速度 S/S
    FORCE_SS = {},

    -- 强制纯生命 H/H
    FORCE_HH = {},
}

-- ============================================================================
-- 初始化：按技能ID建立 O(1) 查询索引
-- ============================================================================

addonTable.SkillTags = {}

local function InitializeTags()
    for tag, skillList in pairs(RAW_TAGS) do
        for _, skillID in ipairs(skillList) do
            if not addonTable.SkillTags[skillID] then
                addonTable.SkillTags[skillID] = {}
            end
            addonTable.SkillTags[skillID][tag] = true
        end
    end
end

InitializeTags()

addonTable.RAW_SKILL_TAGS = RAW_TAGS
