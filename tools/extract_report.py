#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 GenDexBD.lua 中提取 SpeciesReport 并生成可读文本报告。
用法: python extract_report.py [GenDexBD.lua路径] [输出文件路径]
"""

import re
import sys
import os


def count_braces(text, start, end):
    """从 start 到 end 之间的大括号深度变化"""
    depth = 0
    for i in range(start, min(end, len(text))):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
    return depth


def find_balanced_block(text, start_marker):
    """定位一个 { ... } 平衡块"""
    idx = text.find(start_marker)
    if idx == -1:
        return None
    eq_pos = text.index("=", idx)
    brace_pos = text.index("{", eq_pos)
    depth = 0
    pos = brace_pos
    while pos < len(text):
        c = text[pos]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[brace_pos + 1 : pos]  # 不含外层花括号
        pos += 1
    return None


def find_species_report(text):
    """定位 SpeciesReport 的完整文本"""
    idx = text.find('["SpeciesReport"]')
    if idx == -1:
        print("错误: 未找到 SpeciesReport")
        sys.exit(1)
    eq_pos = text.index("=", idx)
    brace_pos = text.index("{", eq_pos)
    depth = 0
    pos = brace_pos
    while pos < len(text):
        c = text[pos]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return idx, pos + 1  # 返回起止位置
        pos += 1
    print("错误: SpeciesReport 未闭合")
    sys.exit(1)


def extract_records(r_section):
    """从 ["r"] 的值中提取每条记录文本"""
    brace_pos = r_section.index("{")
    records = []
    depth = 0  # 深度0=记录间(r数组层级), 1=记录内, 2+=嵌套
    record_start = None
    pos = brace_pos + 1
    while pos < len(r_section):
        c = r_section[pos]
        if c == "{":
            if depth == 0:
                record_start = pos
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and record_start is not None:
                records.append(r_section[record_start : pos + 1])
                record_start = None
        pos += 1
    return records


def simple_match(pattern, text, group=1, default=None):
    m = re.search(pattern, text)
    if m:
        return m.group(group)
    return default


def main():
    if len(sys.argv) < 2:
        saved_dir = os.path.expandvars(
            r"E:\Game\World of Warcraft\_retail_\WTF\Account\171939075#1\SavedVariables"
        )
        src = os.path.join(saved_dir, "GenDexBD.lua")
    else:
        src = sys.argv[1]

    out = sys.argv[2] if len(sys.argv) > 2 else "GenDexBD_Report.txt"

    if not os.path.exists(src):
        print(f"错误: 文件不存在 {src}")
        sys.exit(1)

    with open(src, "r", encoding="utf-8") as f:
        text = f.read()

    print(f"读取 {src} ({len(text)} 字符)")

    # ==== 解析 sm (摘要) ====
    sm_start, sm_end = find_species_report(text)
    raw = text[sm_start:sm_end]
    print(f"SpeciesReport 块: {len(raw)} 字符")

    sm = {}
    for key in ["total", "singleBreed", "multiBreed", "skipped", "errors",
                "withCommunity", "communityMatch", "communityConflict",
                "zeroTags", "forceTags"]:
        m = re.search(r'\["' + key + r'"\]\s*=\s*(\d+)', raw)
        if m:
            sm[key] = int(m.group(1))

    # ==== 提取 r 段 ====
    r_marker = '["r"]'
    r_idx = raw.find(r_marker)
    if r_idx == -1:
        print("错误: 未找到 r 段")
        sys.exit(1)
    r_eq = raw.index("=", r_idx)
    r_brace = raw.index("{", r_eq)
    # 定位 r 数组的闭合括号
    depth = 0
    r_end = r_brace
    while r_end < len(raw):
        c = raw[r_end]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        r_end += 1
    r_section = raw[r_brace : r_end + 1]

    records = extract_records(r_section)
    print(f"提取到 {len(records)} 条记录")

    # ==== 解析每条记录 ====
    parsed = []
    for rec_text in records:
        r = {}
        r["id"] = int(simple_match(r'\["id"\]\s*=\s*(\d+)', rec_text) or 0)
        r["name"] = simple_match(r'\["n"\]\s*=\s*"([^"]*)"', rec_text) or "?"
        r["type"] = simple_match(r'\["tn"\]\s*=\s*"([^"]*)"', rec_text) or "?"
        r["single"] = simple_match(r'\["sb"\]\s*=\s*(true)', rec_text) == "true"
        r["numBreeds"] = int(simple_match(r'\["nb"\]\s*=\s*(\d+)', rec_text) or 0)
        r["petType"] = int(simple_match(r'\["t"\]\s*=\s*(\d+)', rec_text) or 0)
        r["zeroTags"] = simple_match(r'\["zt"\]\s*=\s*(true)', rec_text) == "true"
        r["forceTags"] = simple_match(r'\["ft"\]\s*=\s*(true)', rec_text) == "true"
        r["hasCommunity"] = simple_match(r'\["hc"\]\s*=\s*(true)', rec_text) == "true"
        r["conflict"] = simple_match(r'\["cf"\]\s*=\s*(true)', rec_text) == "true"
        r["commMatch"] = simple_match(r'\["cm"\]\s*=\s*(true)', rec_text) == "true"
        r["commBreed"] = simple_match(r'\["cb"\]\s*=\s*"([^"]*)"', rec_text) or ""

        # 提取品种排名: bd 块（用括号计数方式提取）
        bd_match = re.search(r'\["bd"\]\s*=\s*\{', rec_text)
        if bd_match:
            # 从 bd = { 开始计数
            bd_start = bd_match.end() - 1  # 指向 {
            depth = 0
            bd_end = bd_start
            for i in range(bd_start, len(rec_text)):
                c = rec_text[i]
                if c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        bd_end = i + 1
                        break
            bd_text = rec_text[bd_start:bd_end]

            # 从 bd_text 中分割每个品种条目
            breeds = []
            breed_entries = re.findall(
                r'\{(?:[^{}]*|\{[^{}]*\})*\}', bd_text, re.DOTALL
            )
            for bentry in breed_entries:
                bc = simple_match(r'\["bc"\]\s*=\s*"([^"]*)"', bentry) or ""
                bid = int(simple_match(r'\["bid"\]\s*=\s*(\d+)', bentry) or 0)
                sc = int(simple_match(r'\["sc"\]\s*=\s*(\d+)', bentry) or 0)
                tg = simple_match(r'\["tg"\]\s*=\s*"([^"]*)"', bentry) or ""
                h = simple_match(r'\["h"\]\s*=\s*([\d.]+)', bentry)
                p = simple_match(r'\["p"\]\s*=\s*([\d.]+)', bentry)
                s = simple_match(r'\["s"\]\s*=\s*([\d.]+)', bentry)
                if h and p and s:
                    # 单品种: 用系数生成标签
                    tg = f"h={h} p={p} s={s}"
                breeds.append({
                    "code": bc,
                    "bid": bid,
                    "score": sc if sc else 0,
                    "tags": tg,
                })
            r["breeds"] = breeds
        else:
            r["breeds"] = []

        parsed.append(r)

    print(f"解析完成: {len(parsed)} 条")

    # ==== 生成报告 ====
    lines = []
    lines.append("=" * 70)
    lines.append("  GenDexBD 物种品种评估报告")
    lines.append("=" * 70)
    lines.append("")

    lines.append("--- 汇总统计 ---")
    total = sm.get("total", len(parsed))
    lines.append(f"  总物种:        {total}")
    lines.append(f"  单品种:        {sm.get('singleBreed','?')}  ({sm.get('singleBreed',0)/max(total,1)*100:.0f}%)")
    lines.append(f"  多品种:        {sm.get('multiBreed','?')}  ({sm.get('multiBreed',0)/max(total,1)*100:.0f}%)")
    lines.append(f"  跳过(不可对战): {sm.get('skipped','?')}")
    lines.append(f"  FORCE标签:      {sm.get('forceTags','?')}")
    lines.append(f"  社区共识:       {sm.get('withCommunity','?')}")
    lines.append(f"  共识匹配/冲突:   {sm.get('communityMatch','?')}/{sm.get('communityConflict','?')}")
    lines.append(f"  零标签:         {sm.get('zeroTags','?')}")
    lines.append(f"  异常:           {sm.get('errors','?')}")
    lines.append("")

    multi = [r for r in parsed if not r["single"]]
    single = [r for r in parsed if r["single"]]
    force_recs = [r for r in parsed if r["forceTags"]]
    community_recs = [r for r in parsed if r["hasCommunity"]]
    conflict_recs = [r for r in parsed if r["conflict"]]
    zero_tag_recs = [r for r in parsed if r["zeroTags"]]

    # --- 社区共识 ---
    lines.append("=" * 70)
    lines.append(f"  一、社区共识物种 ({len(community_recs)} 只)")
    lines.append("=" * 70)
    lines.append(f"{'ID':<6} {'名称':<16} {'社区':<6} {'算法Top1':<8} {'分数':<6} {'匹配':<4} {'品种数':<6}")
    lines.append("-" * 60)
    for r in community_recs:
        top1 = r["breeds"][0] if r["breeds"] else {}
        lines.append(
            f"{r['id']:<6} {r['name']:<16} {r.get('commBreed','?'):<6} "
            f"{top1.get('code','?'):<8} {top1.get('score','?'):<6} "
            f"{'OK' if r['commMatch'] else '!!':<4} {r['numBreeds']:<6}"
        )
    lines.append("")

    if conflict_recs:
        lines.append("=" * 70)
        lines.append(f"  ⚠️  冲突 ({len(conflict_recs)} 只)")
        lines.append("=" * 70)
        for r in conflict_recs:
            top1 = r["breeds"][0] if len(r["breeds"]) > 0 else {}
            top2 = r["breeds"][1] if len(r["breeds"]) > 1 else {}
            lines.append(
                f"  {r['id']} {r['name']}: 社区={r.get('commBreed','?')} "
                f"算法={top1.get('code','?')}/{top1.get('score','?')} "
                f"亚军={top2.get('code','?')}/{top2.get('score','?')}"
            )
        lines.append("")
    else:
        lines.append("✅ 共识冲突: 0")
        lines.append("")

    # --- FORCE 标签 ---
    lines.append("=" * 70)
    lines.append(f"  二、FORCE 标签物种 ({len(force_recs)} 只)")
    lines.append("=" * 70)
    lines.append(f"{'ID':<6} {'名称':<18} {'Top1':<6} {'分数':<6} {'Top2':<6} {'分数':<6} {'差距':<6} {'标签'}")
    lines.append("-" * 90)
    for r in force_recs:
        top1 = r["breeds"][0] if len(r["breeds"]) > 0 else {}
        top2 = r["breeds"][1] if len(r["breeds"]) > 1 else {}
        gap = top1.get("score", 0) - top2.get("score", 0) if top1 and top2 else 0
        tags = top1.get("tags", "")[:40] if top1 else ""
        lines.append(
            f"{r['id']:<6} {r['name']:<18} {top1.get('code','?'):<6} "
            f"{top1.get('score','?'):<6} {top2.get('code','?'):<6} "
            f"{top2.get('score','?'):<6} {gap:<6} {tags}"
        )
    lines.append("")

    # --- 多品种完整排名 ---
    lines.append("=" * 70)
    lines.append(f"  三、多品种完整排名 ({len(multi)} 只)")
    lines.append("=" * 70)

    for r in multi:
        breeds = r.get("breeds", [])
        if not breeds:
            continue
        flags = ""
        if r["forceTags"]: flags += "[FORCE]"
        if r["hasCommunity"]: flags += "[COMM]"
        if r["conflict"]: flags += "[冲突]"
        if r["zeroTags"]: flags += "[零]"

        top12_gap = ""
        if len(breeds) >= 2:
            g = breeds[0]["score"] - breeds[1]["score"]
            if g < 20:
                top12_gap = f" ⚡Top1-2差={g}"
            elif g < 50:
                top12_gap = f" (差={g})"

        lines.append(f"\n  {r['id']} {r['name']} ({r['type']})  {r['numBreeds']}种  {flags}{top12_gap}")
        lines.append(f"  {'品种':<8} {'分数':<8} {'标签'}")
        lines.append(f"  {'-'*6}   {'-'*6}   {'-'*30}")
        for b in breeds[:6]:  # 最多6个品种
            lines.append(f"  {b['code']:<8} {b['score']:<8} {b.get('tags','')[:50]}")
    lines.append("")

    # --- 单品种 ---
    lines.append("=" * 70)
    lines.append(f"  四、单品种物种 ({len(single)} 只)")
    lines.append("=" * 70)
    for r in single[:30]:
        b = r["breeds"][0] if r["breeds"] else {}
        lines.append(f"  {r['id']:<6} {r['name']:<18} {r.get('type','?'):<6} {b.get('code','?'):<6}")
    if len(single) > 30:
        lines.append(f"  ... 共 {len(single)} 只（省略 {len(single)-30} 只）")
    lines.append("")

    lines.append("=" * 70)
    lines.append(f"  报告结束  |  {len(parsed)}物种  |  单:{len(single)}  |  多:{len(multi)}")
    lines.append(f"  FORCE:{len(force_recs)}  |  共识:{len(community_recs)}  |  冲突:{len(conflict_recs)}")
    lines.append("=" * 70)

    result = "\n".join(lines)
    with open(out, "w", encoding="utf-8") as f:
        f.write(result)

    print(f"报告已生成: {out} ({len(result)} 字符)")
    print(f"\n快速摘要: {len(parsed)}物种 | 单:{len(single)} | 多:{len(multi)} | FORCE:{len(force_recs)} | 共识:{len(community_recs)}")


if __name__ == "__main__":
    main()
