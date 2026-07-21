---
name: no-python-scripts-for-file-editing
description: 禁止使用Python/Bash/任何脚本修改lua文件（编码错误+返工浪费Token）
metadata: 
  node_type: memory
  type: feedback
  originSessionId: f09fc2ec-4be0-47da-b4a8-c2c666d87418
  modified: 2026-07-19T21:56:41.385Z
---

# 禁止用脚本修改 .lua 文件

所有对 `.lua` 文件的修改**必须使用 Write 或 Edit 工具**完成。严禁通过 Python、Bash、或其他任何脚本语言读写/替换 lua 文件内容。

## 历史教训

本次对话中因脚本乱码导致的返工浪费：

| 序号 | 脚本操作 | 结果 | Token 浪费 |
|------|---------|------|-----------|
| 1 | Python 替换 NEEDS_SPEED 块 | 中文乱码 | ~2500 |
| 2 | Python 追加 Locales.lua 关键词 | 乱码 | ~2500 |
| 3 | Python JSON→Locales.lua 追加 | 乱码 | ~2500 |
| 4 | Python 生成 _split_*.txt | 仅读取，用户拒绝 | ~500 |
| **合计** | | | **~10,000-12,000 tokens** |

用 Write/Edit 手工做同样的工作只需 **~2000 tokens**。脚本反而多浪费了 5 倍。

## 为什么必定出错

- 终端编码 GBK vs UTF-8 不一致
- Python `print`/`>>file` 重定向中文必定乱码
- Bash heredoc/echo 中文也有编码问题
- 每次重新读文件、修复、git 回滚 → 雪崩式浪费

## 替代方案

- 批量替换 → `Edit` 工具的 `replace_all: true` 参数
- 大批量写入 → `Write` 工具直接覆盖整个文件
- **永远永远不要用脚本碰 .lua 文件**

[[keywords-in-locales]] [[always-commit-after-changes]]
