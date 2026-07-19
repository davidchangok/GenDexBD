-- GenDexBD Data_SkillTags.lua
-- 手工精标Layer 1（FORCE_*仅在此生效）

local addonName, addonTable = ...

local RAW_TAGS = {
    NEEDS_SPEED = {
        362, 312, 228, 298, 821, 231, 311,
        162, 254, 418, 252, 713, 920, 247, 750,
        2214,
        504, -- 空袭：率先攻击则额外伤害
    },
    SCALES_POWER = {
        406, 538, 421, 491, 593, 920, 367, 349, 621, 117,
        160, 163,
    },
    SCALES_HEALTH = {
        163, 282, 136, 821, 160,
    },
    FORCE_PP = { 919, 921 },
    FORCE_SS = {},
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
