# GenDexBD · 基因宝典

**智能品种推荐引擎** — 为 WoW 宠物对战 2000+ 物种提供基于技能分析的品种建议。

[![Version](https://img.shields.io/badge/version-1.0.2-blue)](#)
[![Interface](https://img.shields.io/badge/interface-120007-green)](#)

---

## 功能

| 功能 | 说明 |
|------|------|
| **智能品种推荐** | 右击宠物显示算法评分全排名，支持一键设为最佳品种 |
| **社区共识标注** | 96 条 WarcraftPets 社区验证的品种共识，0 冲突 |
| **多语言支持** | zhCN + enUS 完整本地化（界面 + 关键词双层） |
| **标签系统** | 三层标签：静态精标 + 自动关键词匹配 + 否定词过滤 |
| **全物种报告** | `/gbbd report` 批量评估所有物种，生成结构化报告 |
| **进度弹窗** | 设置面板内置报告按钮，进度条 + 实时统计 |
| **战斗星标** | 野外战斗金色 ★ 标记最优品种目标 |

## 命令

| 命令 | 效果 |
|------|------|
| `/gbbd` | 打开设置面板 |
| `/gbbd report` | 批量生成全物种品种评估报告 |

## 报告流程

1. 游戏中 `/gbbd report`
2. 退出游戏
3. `python tools/extract_report.py`
4. 查看 `GenDexBD_Report.txt`：共识 → FORCE → 技能+排名 → 单品种 → 智能审查

## 算法参数

| 参数 | 值 | 说明 |
|------|-----|------|
| W_BASE | 1.0 | 基础权重 |
| W_SPEED | 0.7 | NEEDS_SPEED |
| W_POWER | 0.5 | SCALES_POWER |
| W_HEALTH | 0.9 | SCALES_HEALTH |
| W_SUICIDE | 2.0 | 自爆/HP% |
| W_POWER_AMP | 1.5 | 伤害放大器 |
| W_FORCE | 3.0 | 强制标签 |
| W_COMMUNITY | 2.0 | 社区共识 |

## 数据质量

| 指标 | 值 |
|------|-----|
| 总物种 | 2027 |
| 多品种 | 757 |
| COMMUNITY 共识 | 96 条 |
| 共识匹配率 | 100% |
| 无标签技能 | 0 |

## 依赖

- [Rematch](https://www.curseforge.com/wow/addons/rematch)
- 可选: [BattlePetBreedID](https://www.curseforge.com/wow/addons/battle_pet_breedid)
- 可选: [PetTracker](https://www.curseforge.com/wow/addons/pettracker)

## 文件

```
GenDexBD/
├── Locales.lua          # 多语种字符串 + 分类关键词
├── BreedData.lua        # 12品种系数定义
├── Data_SkillTags.lua   # 静态标签库
├── BreedRecommend.lua   # 核心评分引擎 + 96条共识
├── Core.lua             # 主控制
├── JournalUI.lua        # 右击菜单
├── Report.lua           # 全物种报告
├── ConfigPanel.lua      # 设置面板
├── tools/extract_report.py  # 报告解析脚本
└── tests/               # 单元测试
```

## 社区共识来源

WarcraftPets + wow-petguide.com 双源验证，50+ 轮搜索覆盖全家族。
详见 `memory/community-breed-consensus.md`。

## License

MIT
