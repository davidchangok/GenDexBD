---
name: no-sed-command
description: 禁止使用sed命令删除或修改文件
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 4c7850da-5d45-4890-bf03-68806b54d4e9
---

绝对禁止使用 `sed -i`、`sed` 配合管道、或任何变体的 `sed` 命令来删除或修改文件内容。`sed` 会破坏 Lua 文件结构、产生重复声明、漏删误删正常代码行，已经多次造成严重问题。

**Why:** 多次实操证明 sed 批量操作文件产生大量 bug（重复声明、无尽递归、变量未声明、残留垃圾行）
**How to apply:** 任何文件修改操作均使用 Edit 工具（精确替换）或 Write 工具（完整重写）。不使用 Bash 中的 sed 进行文件内容修改。
