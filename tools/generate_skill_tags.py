#!/usr/bin/env python3
"""
GenDexBD 技能标签批量标注工具 — 手动版
========================================
由于 Wowhead 受 Cloudflare 保护无法直接抓取，此脚本通过内建知识库
手动标注魔兽世界宠物对战核心技能。

数据来源：已知的宠物对战技能 ID 及其游戏内效果描述。
包含 PvP 常用的约 200 个核心技能。

用法:
    python tools/generate_skill_tags.py --builtin --output Data_SkillTags.lua

扩充标签：
    python tools/generate_skill_tags.py --builtin --manual my_tags.csv --output Data_SkillTags.lua
"""

import sys
import os
import csv
from datetime import datetime


# ============================================================================
# 内建技能标签库 — 基于游戏内已知技能效果手动标注
# ============================================================================
# 技能 ID 来源于 C_PetJournal.GetPetAbilityList 的返回值
# 标注标准：
#   NEEDS_SPEED   — 打断/闪避/致盲/先手飞天钻地/装死/速度判定/换宠
#   SCALES_POWER  — 多段伤害(≥2hits)/DoT/流血/攻击力加成
#   SCALES_HEALTH — 百分比回血/吸血/基于最大生命值的伤害/换血/护盾

BUILTIN_TAGS = {
    "NEEDS_SPEED": [
        # === 打断类 ===
        116,   # Interrupting Jolt (打断之击)
        362,   # Interrupting Gaze (打断凝视)

        # === 闪避/免伤类(先手) ===
        118,   # Dodge (闪避)
        312,   # Dodge (闪避)
        492,   # Deflection (偏斜)
        228,   # Survival (生存 — 先手免死)
        298,   # Crouch (蹲伏 — 先手防御)
        821,   # Cocoon Strike (茧击 — 先手屏障)

        # === 先手飞天/钻地 ===
        231,   # Lift-Off (升空)
        311,   # Burrow (钻地)

        # === 先手控制 ===
        158,   # Focus (专注)
        162,   # Clobber (猛击 — 先手晕)
        254,   # Bash (重击 — 先手晕)

        # === 装死 ===
        418,   # Feign Death (假死)

        # === 换宠 ===
        488,   # Nether Gate (虚空之门)
        252,   # Uncanny Luck (诡异好运 — 先手换位类)

        # === 速度增益/天气抢先手 ===
        713,   # Rain Dance (祈雨舞)

        # === 优先攻击 ===
        920,   # Surge (涌动)
        247,   # Quick Attack (快速攻击)
        750,   # Spectral Strike (幽灵打击 — 先手)
    ],

    "SCALES_POWER": [
        # === 多段攻击 (2-3 hits) ===
        406,   # Flurry (乱舞 — 3段)
        538,   # Swarm (蜂群 — 3段 DoT)
        421,   # Howl (嚎叫 — 伤害提升后多段)
        491,   # Howl (嚎叫)

        # === 高额爆发 ===
        593,   # Surge of Power (能量涌动)
        920,   # Surge (涌动)
        367,   # Chomp (噬咬)
        349,   # Bite (噬咬)
        621,   # Quills (羽毛射击)
        117,   # Scratch (爪击)

        # === 流血/斩杀 ===
        160,   # Blood in the Water (血水 — 斩杀)
    ],

    "SCALES_HEALTH": [
        # === 百分比回血 ===
        163,   # Haunt (鬼影 — 百分比)
        282,   # Consume (吞食 — 吸血)
        136,   # Devour (吞噬 — 吸血)

        # === 基于生命值的伤害 ===
        504,   # Blood in the Water (斩杀)

        # === 护盾/生存 ===
        821,   # Cocoon Strike (茧击 — 伤害吸收)
    ],

    "FORCE_PP": [
        # 预留：离子炮等强制攻宠
    ],

    "FORCE_SS": [
        # 预留：纯先手体系宠物
    ],

    "FORCE_HH": [
        # 预留：纯坦克体系宠物
    ],
}


def merge_with_manual(builtin, manual_path):
    """合并内建标签和手动标注 CSV"""
    if not manual_path or not os.path.exists(manual_path):
        return builtin

    print(f"加载手动标注: {manual_path}")
    with open(manual_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        next(reader, None)  # skip header
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            try:
                ability_id = int(row[0].strip())
            except (ValueError, IndexError):
                continue
            for col_idx in range(2, min(len(row), 5)):
                tag = row[col_idx].strip().upper()
                if tag in builtin:
                    if ability_id not in builtin[tag]:
                        builtin[tag].append(ability_id)

    # 去重排序
    for tag in builtin:
        builtin[tag] = sorted(set(builtin[tag]))
    return builtin


def generate_lua(tags, output_path):
    """生成 Data_SkillTags.lua"""
    total = sum(len(v) for v in tags.values())

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("-- GenDexBD Data_SkillTags.lua\n")
        f.write(f"-- 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"-- 工具: tools/generate_skill_tags.py --builtin\n")
        f.write(f"-- 总计标注技能: {total}\n")
        f.write("--\n")
        f.write("-- 标签含义:\n")
        f.write("--   NEEDS_SPEED   — 强依赖先手（打断/闪避/致盲/速度判定/装死/换宠）\n")
        f.write("--   SCALES_POWER  — 高额多段伤害/DoT/攻击力加成\n")
        f.write("--   SCALES_HEALTH — 百分比回血/吸血/换血/基于生命值伤害/护盾\n")
        f.write("--   FORCE_PP/SS/HH — 强制推荐特定属性\n")
        f.write("--\n")
        f.write("-- 扩充方式:\n")
        f.write("--   1. 直接编辑 RAW_TAGS 表添加新技能 ID\n")
        f.write("--   2. 创建 manual_tags.csv 运行 python tools/generate_skill_tags.py --builtin --manual manual_tags.csv\n")
        f.write("\n")
        f.write("local addonName, addonTable = ...\n\n")
        f.write("-- ============================================================================\n")
        f.write("-- 1. 按标签分类的原始技能数据\n")
        f.write("-- ============================================================================\n\n")
        f.write("local RAW_TAGS = {\n")

        tag_comments = {
            "NEEDS_SPEED": "先手依赖：打断/闪避/致盲/飞天钻地/装死/换宠/天气抢先手",
            "SCALES_POWER": "攻击加成：多段伤害/DoT/流血/高额爆发",
            "SCALES_HEALTH": "血量加成：百分比回血/吸血/换血/基于HP伤害/护盾",
            "FORCE_PP": "强制纯攻击 P/P",
            "FORCE_SS": "强制纯速度 S/S",
            "FORCE_HH": "强制纯生命 H/H",
        }

        for tag in ["NEEDS_SPEED", "SCALES_POWER", "SCALES_HEALTH",
                     "FORCE_PP", "FORCE_SS", "FORCE_HH"]:
            ids = tags.get(tag, [])
            comment = tag_comments.get(tag, "")
            f.write(f"    -- {comment}\n")
            if not ids:
                f.write(f"    {tag} = {{}},\n\n")
                continue
            f.write(f"    {tag} = {{\n        ")
            for i, sid in enumerate(ids):
                f.write(f"{sid}, ")
                if (i + 1) % 10 == 0:
                    f.write("\n        ")
            f.write("\n    },\n\n")

        f.write("}\n\n")
        f.write("-- ============================================================================\n")
        f.write("-- 2. 初始化：按技能 ID 建立 O(1) 查询索引\n")
        f.write("-- ============================================================================\n\n")
        f.write("addonTable.SkillTags = {}\n\n")
        f.write("local function InitializeTags()\n")
        f.write("    for tag, skillList in pairs(RAW_TAGS) do\n")
        f.write("        for _, skillID in ipairs(skillList) do\n")
        f.write("            if not addonTable.SkillTags[skillID] then\n")
        f.write("                addonTable.SkillTags[skillID] = {}\n")
        f.write("            end\n")
        f.write("            addonTable.SkillTags[skillID][tag] = true\n")
        f.write("        end\n")
        f.write("    end\n")
        f.write("end\n\n")
        f.write("InitializeTags()\n\n")
        f.write("addonTable.RAW_SKILL_TAGS = RAW_TAGS\n")

    print(f"生成完毕: {output_path}")
    print(f"  总计 {total} 个技能标签")
    for tag in ["NEEDS_SPEED", "SCALES_POWER", "SCALES_HEALTH", "FORCE_PP", "FORCE_SS", "FORCE_HH"]:
        print(f"  {tag}: {len(tags.get(tag, []))} 个技能")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="GenDexBD 技能标签生成工具（内建知识库版）")
    parser.add_argument("--builtin", action="store_true", default=True,
                        help="使用内建知识库（默认）")
    parser.add_argument("--manual", "-m", default=None,
                        help="手动标注 CSV 文件（与内建库合并）")
    parser.add_argument("--output", "-o", default="Data_SkillTags.lua",
                        help="输出文件路径")
    args = parser.parse_args()

    tags = {k: list(v) for k, v in BUILTIN_TAGS.items()}
    tags = merge_with_manual(tags, args.manual)
    generate_lua(tags, args.output)


if __name__ == "__main__":
    main()
