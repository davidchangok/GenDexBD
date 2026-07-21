---
name: detailed-change-log
description: 每次 GitHub 推送后必须在本地记忆文件中详细记录做了什么
metadata:
  type: feedback
  originSessionId: 2026-07-22-state-recovery
  modified: 2026-07-21T17:36:00.979Z
---

# 变更日志规则

每次 `git commit + push` 后，必须在本地的项目记忆文件中对做了什么进行**详细记录**，并且此记忆文件同样需要上传到 GitHub。

## 记录内容要求

每次变更记录必须包含：

1. **修改了哪些文件** — 文件路径 + 行数变化概览
2. **为什么修改** — 触发原因（用户要求/代码审查/社区共识更新/bug修复等）
3. **具体改了什么** — 关键变更点的文字描述（不是复制整个 diff）
4. **影响分析** — 对算法评分/用户体验/数据质量的影响
5. **相关记忆更新** — 是否同步更新了其他记忆文件

## 记录位置

- 在 `memory/` 目录下创建 `change-log-YYYY-MM.md` 按月归档
- 同时更新 `memory/MEMORY.md` 索引
- 变更日志文件随项目一起 git push

## 格式示例

```markdown
---
name: change-log-2026-07
description: 2026年7月变更日志
metadata:
  type: project
---

# 2026-07 变更日志

## 2026-07-22

### commit: <hash> — <subject>
- **文件**: BreedRecommend.lua (+12/-3), Locales.lua (+5/-1)
- **原因**: 用户要求同步 Report.lua COMMUNITY 缺失条目
- **改动**: ...
- **影响**: ...
- **记忆同步**: 更新 community-breed-consensus.md
```

**Why:** 用户曾因忘记存档而丢失工作进度。详细记录每次变更可避免重复劳动，也便于回溯问题。
**How to apply:** 每次 commit 后立即写变更日志，不要拖延。如果变动小（单行修复），可以合并到当天日志中。

[[always-commit-after-changes]] [[project-state]]
