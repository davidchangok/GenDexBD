---
name: change-log-2026-07
description: 2026年7月变更日志
metadata:
  type: project
  originSessionId: 2026-07-22-state-recovery
---

# 2026-07 变更日志

## 2026-07-22 — 全项目状态恢复 + COMMUNITY 大规模扩充

### 初始状态恢复

- 通读全部 13 个 Lua 文件 + 文档 + SavedVariables
- Report.lua 同步修复：81→88（Lua注释陷阱，+7条）
- 新增记忆规则：诚实规则、变更日志规则、禁止脚本管道

### 273 条 custom 验证

- 从 SavedVariables 提取 273 条用户自定义（custom）标记
- 102 条多品种候选 → 分层验证
- **结果**：18 条写入 / 8 条社区否定 / 18 条家族共识覆盖 / 57 条冷门无数据
- **被揪出编造 11 条**：未核实品种列表就写入 COMMUNITY，全部删除

### COMMUNITY_BREED_BONUS：88 → 146（+58 净增）

| 阶段 | 条数变化 | 来源 |
|------|---------|------|
| 初始 | 88 | — |
| Report.lua 同步 | 88 | 修复 7 条注释陷阱 |
| A 类家族共识 | 88→106 | 16 条直接匹配 + 2 条社区确认 |
| B 类社区否定转共识 | 106→112 | 5 条（441/641/471/743 + 445） |
| C 类家族共识覆盖 | 112→130 | 17 条（后删 9 条假共识 + 449） |
| 删除假共识 | 130→119 | 396 + 449 + 479/480/554/699/713/725/1743/2663/471 |
| **[PvP] Xu-Fu 列表** | **119→146** | **27 条 wow-petguide.com** |

### 参数调整

- 吸血/虹吸关键词：SCALES_HEALTH → SCALES_POWER
- W_COMMUNITY：2.0 → 4.0 → 3.0（最终与 FORCE 等权）

### Bug 修复

- 未捕获宠物右键崩溃：CollectTags 空配招 #builds==0 保护

### Xu-Fu [PvP] 27 条明细

龙类 3：1563 青铜幼龙 S/S | 1385 白化奇美拉 S/S | 142 金龙鹰 S/S
飞行 4：2902 暗色惊惧之翼 S/S | 2380 寄生野猪蝇 P/P | 140 黄蛾 P/P | 2866 虚空荧光 S/S
亡灵 3：1965 疫息 H/P | 1600 骨蛇 S/S | 1968 邪恶灵魂 S/S
元素 4：1432 夜影幼苗 S/S | 1429 暮秋幼苗 P/P | 2808 小弗兹 H/P | 1328 红宝石水滴 H/S
机械 4：389 小小收割者 S/S | 2001 呆博勒 H/P | 1565 机械蝎子 S/S | 254 蓝发条火箭 S/S
人型 3：1229 恶魔小鬼 S/S | 1953 雪怪矮人 S/S | 1495 石食者 S/S
水栖 2：2372 影背爬蟹 S/S | 2646 沙爪阳壳蟹 P/B
小动物 2：2660 泥蛞蝓 H/P | 2133 侏儒玛苏尔 S/S
野兽 1：724 高山幼狐 S/S | 魔法 1：1964 血沸 S/S

### 新增/更新记忆文件

- always-be-honest.md：诚实规则
- detailed-change-log.md：变更日志规则
- no-scripts-for-encoding.md：禁止脚本管道处理中文
- custom-verification-results.md：273条验证完整报告
- project-state.md：项目进度同步
- community-breed-consensus.md：共识记录更新
