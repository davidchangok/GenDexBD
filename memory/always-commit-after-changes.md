---
name: always-commit-after-changes
description: 每次代码修改后自动git commit+push备份
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f09fc2ec-4be0-47da-b4a8-c2c666d87418
  modified: 2026-07-19T18:03:01.493Z
---

每次对 GenDexBD 项目的代码修改完成后，自动执行 `git add -A && git commit -m "..." && git push`，确保修改实时备份到 GitHub。

**Why:** 用户偏好每次修改后立即备份，避免丢失进度。
**How to apply:** 代码修改完成后，用中文提交信息描述改动内容，然后 push 到 origin/main。
