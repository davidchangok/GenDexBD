-- GenDexBD Data_SkillTags.lua
-- 生成时间: 2026-07-20 00:34:21
-- 工具: tools/generate_skill_tags.py --builtin
-- 总计标注技能: 36
--
-- 标签含义:
--   NEEDS_SPEED   — 强依赖先手（打断/闪避/致盲/速度判定/装死/换宠）
--   SCALES_POWER  — 高额多段伤害/DoT/攻击力加成
--   SCALES_HEALTH — 百分比回血/吸血/换血/基于生命值伤害/护盾
--   FORCE_PP/SS/HH — 强制推荐特定属性
--
-- 扩充方式:
--   1. 直接编辑 RAW_TAGS 表添加新技能 ID
--   2. 创建 manual_tags.csv 运行 python tools/generate_skill_tags.py --builtin --manual manual_tags.csv

local addonName, addonTable = ...

-- ============================================================================
-- 1. 按标签分类的原始技能数据
-- ============================================================================

local RAW_TAGS = {
    -- 先手依赖：打断/闪避/致盲/飞天钻地/装死/换宠/天气抢先手
    NEEDS_SPEED = {
        116, 362, 118, 312, 492, 228, 298, 821, 231, 311, 
        158, 162, 254, 418, 488, 252, 713, 920, 247, 750, 
        
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

    -- 强制纯攻击 P/P
    FORCE_PP = {},

    -- 强制纯速度 S/S
    FORCE_SS = {},

    -- 强制纯生命 H/H
    FORCE_HH = {},

}

-- ============================================================================
-- 2. 初始化：按技能 ID 建立 O(1) 查询索引
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
