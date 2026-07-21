#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 GenDexBD.lua 中提取 SpeciesReport 并生成可读文本报告。
用法: python extract_report.py <GenDexBD.lua路径> [输出文件路径]
"""

import re
import sys
import os


def find_species_report(text):
    """在 SavedVariables 文本中定位 SpeciesReport 块的起止位置"""
    # 找 ["SpeciesReport"] = {
    start_marker = '["SpeciesReport"]'
    idx = text.find(start_marker)
    if idx == -1:
        print("错误: 未找到 SpeciesReport")
        sys.exit(1)

    # 找到 = { 后的第一个 {
    eq_pos = text.index("=", idx)
    brace_pos = text.index("{", eq_pos)
    depth = 0
    pos = brace_pos
    while pos < len(text):
        if text[pos] == "{":
            depth += 1
        elif text[pos] == "}":
            depth -= 1
            if depth == 0:
                return text[idx : pos + 1]
        pos += 1

    print("错误: SpeciesReport 块未正确闭合")
    sys.exit(1)


def indent(level):
    return "    " * level


def format_tags(tag_str):
    if not tag_str:
        return ""
    # × → x
    return tag_str.replace("\xc3\x97".encode().decode("utf-8", "replace"), "x")


def main():
    if len(sys.argv) < 2:
        # 默认路径
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

    # 提取 SpeciesReport 文本块
    raw = find_species_report(text)
    print(f"SpeciesReport 块: {len(raw)} 字符")

    # ==========================================================
    # 直接解析顶层结构: sm(摘要) + r(结果列表)
    # ==========================================================

    # --- 解析 sm ---
    sm = {}
    sm_patterns = {
        "total": r'\["total"\]\s*=\s*(\d+)',
        "singleBreed": r'\["singleBreed"\]\s*=\s*(\d+)',
        "multiBreed": r'\["multiBreed"\]\s*=\s*(\d+)',
        "skipped": r'\["skipped"\]\s*=\s*(\d+)',
        "errors": r'\["errors"\]\s*=\s*(\d+)',
        "withCommunity": r'\["withCommunity"\]\s*=\s*(\d+)',
        "communityMatch": r'\["communityMatch"\]\s*=\s*(\d+)',
        "communityConflict": r'\["communityConflict"\]\s*=\s*(\d+)',
        "zeroTags": r'\["zeroTags"\]\s*=\s*(\d+)',
        "forceTags": r'\["forceTags"\]\s*=\s*(\d+)',
    }
    for key, pat in sm_patterns.items():
        m = re.search(pat, raw)
        if m:
            sm[key] = int(m.group(1))

    # --- 解析 r 中的每条记录 ---
    # 每条记录 = {["bd"]={...},["sb"]=bool,["tn"]="家族",["id"]=数字,["t"]=数字,["nb"]=数字,["n"]="名称", ...}
    # 简化策略: 用正则提取每条记录的简版信息
    records = []

    # 找每条记录的 id 和 n (名称)
    id_pattern = re.compile(r'\["id"\]\s*=\s*(\d+)')
    name_pattern = re.compile(r'\["n"\]\s*=\s*"([^"]*)"')
    tn_pattern = re.compile(r'\["tn"\]\s*=\s*"([^"]*)"')
    sb_pattern = re.compile(r'\["sb"\]\s*=\s*(true|false)')
    nb_pattern = re.compile(r'\["nb"\]\s*=\s*(\d+)')
    t_pattern = re.compile(r'\["t"\]\s*=\s*(\d+)')
    zt_pattern = re.compile(r'\["zt"\]\s*=\s*true')
    ft_pattern = re.compile(r'\["ft"\]\s*=\s*true')
    hc_pattern = re.compile(r'\["hc"\]\s*=\s*true')
    cm_pattern = re.compile(r'\["cm"\]\s*=\s*(true|false)')
    cf_pattern = re.compile(r'\["cf"\]\s*=\s*true')
    cb_pattern = re.compile(r'\["cb"\]\s*=\s*"([^"]*)"')

    # 品种排名: ["bc"]="S/S",["bid"]=5,["sc"]=889,["tg"]=...
    breed_pattern = re.compile(
        r'\{"?\["bc"\]"?\s*=\s*"([^"]+)"\s*,\s*"?\["bid"\]"?\s*=\s*(\d+)\s*,\s*"?\["sc"\]"?\s*=\s*(\d+)(?:,[^}]*?\["tg"\]"?\s*=\s*"([^"]*)")?[^}]*\}'
    )

    # 按 { ... } 分割记录（粗提取，一条记录=一个物种）
    # 每段以 ["bd"]= 或 ["sb"]= 开头，用 ["id"] 定位
    # 简单办法：以 ["id"] 为锚点提取两侧内容

    segments = re.split(r'(?=\{"?\["id"\]"?\s*=\s*\d+)', raw)
    # 第一段是 sm 部分，跳过
    for seg in segments[1:]:
        m_id = id_pattern.search(seg)
        m_name = name_pattern.search(seg)
        if not m_id or not m_name:
            continue

        rec = {
            "id": int(m_id.group(1)),
            "name": m_name.group(1),
        }

        m_tn = tn_pattern.search(seg)
        if m_tn:
            rec["type"] = m_tn.group(1)

        m_sb = sb_pattern.search(seg)
        rec["single"] = m_sb and m_sb.group(1) == "true"

        m_nb = nb_pattern.search(seg)
        rec["numBreeds"] = int(m_nb.group(1)) if m_nb else 0

        m_t = t_pattern.search(seg)
        rec["petType"] = int(m_t.group(1)) if m_t else 0

        rec["zeroTags"] = zt_pattern.search(seg) is not None
        rec["forceTags"] = ft_pattern.search(seg) is not None
        rec["hasCommunity"] = hc_pattern.search(seg) is not None
        rec["conflict"] = cf_pattern.search(seg) is not None

        m_cm = cm_pattern.search(seg)
        rec["commMatch"] = m_cm and m_cm.group(1) == "true"

        m_cb = cb_pattern.search(seg)
        if m_cb:
            rec["commBreed"] = m_cb.group(1)

        # 提取 Top 3 品种排名
        breeds = breed_pattern.findall(seg)
        if breeds:
            rec["topBreeds"] = [
                {"code": b[0], "bid": int(b[1]), "score": int(b[2]), "tags": b[3] if len(b) > 3 else ""}
                for b in breeds[:5]
            ]

        records.append(rec)

    # ==========================================================
    # 生成报告
    # ==========================================================
    lines = []
    lines.append("=" * 70)
    lines.append("  GenDexBD 物种品种评估报告")
    lines.append("=" * 70)
    lines.append("")

    # 摘要
    lines.append("--- 汇总统计 ---")
    if sm:
        lines.append(f"  总物种:        {sm.get('total', '?')}")
        lines.append(f"  单品种:        {sm.get('singleBreed', '?')}  ({sm.get('singleBreed',0)/sm.get('total',1)*100:.0f}%)")
        lines.append(f"  多品种:        {sm.get('multiBreed', '?')}  ({sm.get('multiBreed',0)/sm.get('total',1)*100:.0f}%)")
        lines.append(f"  跳过(不可对战): {sm.get('skipped', '?')}")
        lines.append(f"  FORCE标签:      {sm.get('forceTags', '?')}")
        lines.append(f"  社区共识总数:    {sm.get('withCommunity', '?')}")
        lines.append(f"  共识匹配:       {sm.get('communityMatch', '?')}")
        lines.append(f"  共识冲突:       {sm.get('communityConflict', '?')}")
        lines.append(f"  零标签:         {sm.get('zeroTags', '?')}")
        lines.append(f"  异常:           {sm.get('errors', '?')}")
    lines.append("")

    # 多品种详细列表
    multi = [r for r in records if not r["single"]]
    single = [r for r in records if r["single"]]
    force_recs = [r for r in records if r["forceTags"]]
    conflict_recs = [r for r in records if r["conflict"]]
    community_recs = [r for r in records if r["hasCommunity"]]
    zero_tag_recs = [r for r in records if r["zeroTags"]]

    # --- Part 1: 社区共识 ---
    lines.append("=" * 70)
    lines.append(f"  一、社区共识物种 ({len(community_recs)} 只)")
    lines.append("=" * 70)
    lines.append(
        f"{'ID':<6} {'宠物名':<16} {'社区':<6} {'算法Top1':<8} {'分数':<6} {'匹配':<4} {'品种数':<6}"
    )
    lines.append("-" * 60)
    for r in community_recs:
        top1 = r.get("topBreeds", [{}])[0] if r.get("topBreeds") else {}
        lines.append(
            f"{r['id']:<6} {r['name']:<16} {r.get('commBreed','?'):<6} "
            f"{top1.get('code','?'):<8} {top1.get('score','?'):<6} "
            f"{'OK' if r['commMatch'] else '!!':<4} {r['numBreeds']:<6}"
        )
    lines.append("")

    # --- Part 2: 冲突 ---
    if conflict_recs:
        lines.append("=" * 70)
        lines.append(f"  ⚠️  共识冲突 ({len(conflict_recs)} 只)")
        lines.append("=" * 70)
        for r in conflict_recs:
            top1 = r.get("topBreeds", [{}])[0] if r.get("topBreeds") else {}
            top2 = r.get("topBreeds", [{}])[1] if len(r.get("topBreeds", [])) > 1 else {}
            lines.append(
                f"  {r['id']} {r['name']}: 社区={r.get('commBreed','?')} "
                f"算法={top1.get('code','?')}/{top1.get('score','?')} "
                f"亚军={top2.get('code','?')}/{top2.get('score','?')}"
            )
        lines.append("")
    else:
        lines.append("✅ 共识冲突: 0 — 算法与社区完全一致")
        lines.append("")

    # --- Part 3: FORCE标签 ---
    lines.append("=" * 70)
    lines.append(f"  二、FORCE 标签物种 ({len(force_recs)} 只)")
    lines.append("=" * 70)
    lines.append(
        f"{'ID':<6} {'宠物名':<18} {'Top1':<6} {'分数':<6} {'标签'}"
    )
    lines.append("-" * 80)
    for r in force_recs:
        top1 = r.get("topBreeds", [{}])[0] if r.get("topBreeds") else {}
        tags = top1.get("tags", "")[:50] if top1 else ""
        lines.append(
            f"{r['id']:<6} {r['name']:<18} {top1.get('code','?'):<6} "
            f"{top1.get('score','?'):<6} {tags}"
        )
    lines.append("")

    # --- Part 4: 多品种完整排名 ---
    lines.append("=" * 70)
    lines.append(f"  三、多品种完整排名 ({len(multi)} 只)")
    lines.append("=" * 70)

    for r in multi:
        breeds = r.get("topBreeds", [])
        if not breeds:
            continue
        flags = ""
        if r["forceTags"]:
            flags += "[FORCE]"
        if r["hasCommunity"]:
            flags += "[COMM]"
        if r["conflict"]:
            flags += "[冲突]"
        if r["zeroTags"]:
            flags += "[零标签]"

        lines.append(f"\n  {r['id']} {r['name']} ({r['type']})  可选:{r['numBreeds']}种  {flags}")
        lines.append(f"  {'品种':<8} {'分数':<8} {'标签'}")
        lines.append(f"  {'-'*6}   {'-'*6}   {'-'*30}")
        for b in breeds:
            lines.append(f"  {b['code']:<8} {b['score']:<8} {b.get('tags','')[:60]}")
    lines.append("")

    # --- Part 5: 单品种列表 ---
    lines.append("=" * 70)
    lines.append(f"  四、单品种物种 ({len(single)} 只)")
    lines.append("=" * 70)
    for r in single[:50]:  # 只列前50只
        b = r.get("topBreeds", [{}])[0] if r.get("topBreeds") else {}
        lines.append(f"  {r['id']:<6} {r['name']:<18} {r.get('type','?'):<6} {b.get('code','?'):<6}")
    if len(single) > 50:
        lines.append(f"  ... 共 {len(single)} 只单品种（省略 {len(single)-50} 只）")
    lines.append("")

    lines.append("=" * 70)
    lines.append(f"  报告结束")
    lines.append(f"  物种: {len(records)} | 单品种: {len(single)} | 多品种: {len(multi)}")
    lines.append(f"  FORCE: {len(force_recs)} | 共识: {len(community_recs)} | 冲突: {len(conflict_recs)}")
    lines.append("=" * 70)

    result = "\n".join(lines)
    with open(out, "w", encoding="utf-8") as f:
        f.write(result)

    print(f"报告已生成: {out} ({len(result)} 字符)")

    # 摘要
    print(f"\n--- 快速摘要 ---")
    print(f"  总物种: {len(records)}")
    print(f"  单品种: {len(single)}")
    print(f"  多品种: {len(multi)}")
    print(f"  FORCE标签: {len(force_recs)}")
    print(f"  社区共识: {len(community_recs)}")
    print(f"  冲突: {len(conflict_recs)}")


if __name__ == "__main__":
    main()
