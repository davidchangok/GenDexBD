---
name: no-scripts-for-encoding
description: 禁止用脚本管道处理中文数据 — 管道编码不可靠，必须用Grep/Read/Edit等专用工具
metadata:
  type: feedback
  originSessionId: 2026-07-22-custom-breed-verification
  modified: 2026-07-21T18:15:33.507Z
---

# 禁止脚本管道处理中文数据

**不仅仅禁止 Python 改 lua 文件，也禁止用 Python/shell 脚本管道处理含中文的数据。**

## 为什么

- WoW SavedVariables/源码文件是 UTF-8 编码
- Python 可以正确读取 UTF-8，但通过 Bash/PowerShell 管道输出时中文会变 `?`
- 终端→shell→Python 的编码链路不可靠，数据一旦乱码就无法恢复
- 之前 252 条候选列表中所有中文宠物名全部丢失就是这个原因

## 正确做法

| 操作 | 用这个 | 不要用 |
|------|--------|--------|
| 读文件 | `Read` / `Grep` | `python3 -c "open()..."` |
| 搜索内容 | `Grep` | `grep` through `Bash` |
| 写文件 | `Write` / `Edit` | `python3` 脚本写文件 |
| 数据统计 | 实在需要用脚本时先用 `Read` 确认编码 | 直接管道输出 |

## 例外

如果脚本**不涉及中文输出**（如纯数字统计），可以在确认编码安全后使用。
但要优先考虑是否能用 `Grep -c` 等专用工具替代。

**Why:** 2026-07-22 会话中 252 条候选验证因脚本管道中文乱码而失败，浪费大量时间。
**How to apply:** 任何涉及含中文的 Lua 文件操作，第一步用 `Read` 确认内容可读，再用 `Grep` 搜索，最后用 `Edit` 修改。不通过 shell 管道传递中文。

[[no-python-scripts-for-file-editing]] [[no-sed-command]] [[always-use-skills]]
