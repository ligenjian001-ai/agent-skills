# Agent Skills — 多 Agent 协作技能生态系统

> 跨项目的 agent 技能库。AG (Antigravity) 担任编排者，通过 task-delegate 统一调度多个后端 agent，各技能互相协作，形成完整的自动化工作流。

## 核心理念

**AG = 编排者 (Copilot)**，不亲自做重活，而是：

1. 理解用户意图 → 拆解任务 → 分派给最合适的后端
2. 监控执行 → 验证结果 → 记录过程
3. 维持对话上下文不被污染，使任务链路可以无限延长

## ⚠️ 全局规则配置（使用前必读）

> [!IMPORTANT]
> 仅 clone 本仓库 **不足以让 skill 正常工作**。
> 你需要在 AG Settings 中注册 skill 目录，并在全局规则中添加关键配置。
> 详见 **[全局规则配置指南](GLOBAL_RULES_SETUP.md)**。

## 后端分派策略

| 后端 | 擅长领域 | 典型场景 |
|------|---------|---------|
| **CC (Claude Code)** | 编码 | 实现功能、修复 bug、重构代码 |
| **Codex (OpenAI)** | 推理 & 长链路思考 | 复杂分析、调试、架构决策、panel 辩论 |
| **Gemini (Google)** | 多模态 | 图片分析、浏览器自动化、OCR |
| **DeepSeek** | 性价比 | 快速生成、简单分析、批量处理 |

> AG 自身只写验证代码和编排脚本，**一旦涉及编码实现就委派**。这保证 AG 上下文不被实现细节污染，任务链路可以变得极长且复杂。

## 技能协作架构

```mermaid
graph TB
    subgraph "👤 用户"
        U[User]
    end

    subgraph "🧠 编排层"
        AG["Antigravity (AG)<br/>编排者"]
        ARC["ag-archive<br/>Journal + Subagent Tracking"]
        DR["daily-report<br/>自动日报"]
    end

    subgraph "⚡ 执行层"
        TD["task-delegate<br/>统一 dispatch"]
        PD["panel-discussion<br/>多角色辩论"]
        BI["bug-investigation<br/>双分析师诊断"]
        DA["deep-analysis<br/>多维度系统分析"]
        SD["system-design<br/>详细系统设计"]
    end

    subgraph "🔧 后端"
        CC[CC] & CDX[Codex] & GEM[Gemini] & DS[DeepSeek]
    end

    subgraph "🛠️ 功能扩展"
        BU["browser-use"] & JK["jenkins-ops"] & IR["infra-request"]
        II["infra-intake\nIssue 处理 + CC 设计对话"]
        ANP["agent-native-product\n产品 agent 化改造"]
        CMR["concept-model-review\n概念模型审计"]
        JS["jupyter-session\n持久 Jupyter 会话"]
    end

    subgraph "📦 基础设施"
        TMUX["tmux-protocol"]
        SC["skill-creator"]
        ALD["ag-lag-diagnosis"]
    end

    subgraph "💾 IPC"
        IPC1["~/.task-delegate/"]
        IPC2["~/.panel-discussions/"]
        IPC3["brain/{conv}/"]
        IPC4["~/.deep-analysis/"]
        IPC5["~/.system-design/"]
    end

    U --> AG
    AG -->|编排| TD
    AG -->|记录| ARC
    TD -->|launch| CC & CDX & GEM & DS
    PD -->|wrapper| TD
    BI -->|wrapper| TD
    DA -->|wrapper| TD
    SD -->|wrapper| TD
    DA -->|system_map| SD
    TD -->|写入| IPC1
    PD -->|编排数据| IPC2
    ARC -->|journal| IPC3
    DA -->|分析| IPC4
    SD -->|设计| IPC5
    DR -.->|读取| IPC1 & IPC2 & IPC3
    AG --> BU & JK & IR & ANP & CMR & II
    II -->|"CC Design Dialogue"| TD
    ANP -->|wrapper| TD
    CMR -->|wrapper| TD
    CMR -->|concept_map| ANP
    TD & PD & BI & DA & SD & JK & BU --> |终端| TMUX
```

### 数据流

| 存储 | 用途 | 写入者 | 消费者 |
|------|------|--------|--------|
| `~/.task-delegate/` | 所有 subagent 执行记录（Single Source of Truth） | task-delegate | daily-report, ag-archive, ag_retro.py |
| `~/.panel-discussions/` | Panel 编排数据（topic, summary, manifest） | panel-discussion | daily-report |
| `~/.bug-investigations/` | Bug 调查编排数据（context, verdict） | bug-investigation | daily-report |
| `~/.deep-analysis/` | 多维度分析数据（aspects, analyst/challenger 输出, system_map） | deep-analysis | system-design, daily-report |
| `~/.system-design/` | 设计数据（sketch, decide, spike, blueprint） | system-design | infra-request, daily-report |
| `~/.agent-native-transform/` | 产品 agent 化改造数据（assess, transform, audit） | agent-native-product | daily-report |
| `~/.concept-model-review/` | 概念模型审计数据（discover, evaluate, path_design） | concept-model-review | agent-native-product, daily-report |
| `brain/{conv_id}/` | 对话 journal + subagent tracking | ag-archive | daily-report |

**双向链接**：`execution_record.json` 的 `source_conversation` → `brain/{conv_id}/`，journal 的 `[subagent]` tag → `~/.task-delegate/{task_id}/`

## 技能清单

### 基础设施

| Skill | Description |
|-------|-------------|
| [tmux-protocol](tmux-protocol/) | 强制终端协议 — 所有 terminal 命令必须走 tmux，防止 agent hang |
| [skill-creator](skill-creator/) | 技能构建标准 — 六段式 SKILL.md + README.md 双层文档体系 |
| [ag-lag-diagnosis](ag-lag-diagnosis/) | AG IDE 性能诊断 — polling storms, 大 .pb 文件, renderer blocking |

### 编排执行

| Skill | Description |
|-------|-------------|
| [task-delegate](task-delegate/) | 统一任务委派 — prompt, launch, monitor, verify, extract (CC/Codex/Gemini/DeepSeek) |
| [agent-panel-discussion](agent-panel-discussion/) | 多角色辩论 — 怀疑/务实/乐观三方辩论，多轮反驳 + 信心评分 |
| [bug-investigation](bug-investigation/) | Bug 调查 — CC + Codex 双分析师独立诊断，AG 综合裁决 |
| [deep-analysis](deep-analysis/) | 多维度系统分析 — 问题驱动 aspect 发现 + Analyst/Challenger 双 agent 对抗 |
| [system-design](system-design/) | 详细系统设计 — 三视角 Sketch + 收敛 + Spike 验证 + Blueprint |

### 记录分析

| Skill | Description |
|-------|-------------|
| [ag-archive](ag-archive/) | 对话归档 — Journal 协议 + `[subagent]` tracking + conversation_summary |
| [daily-report](daily-report/) | 自动日报 — 扫描 3 个数据源，按项目分组，附 AI 改进建议 |

### 功能扩展

| Skill | Description |
|-------|-------------|
| [browser-use](browser-use/) | 浏览器自动化 — browser-use + Gemini Flash，比 AG 内置快 2-9x |
| [jenkins-ops](jenkins-ops/) | Jenkins CI/CD — 触发、监控、配置、排障 |
| [infra-request](infra-request/) | 基建需求 — GitHub Issues 提交 + 验证 + Tool Integration Plan |
| [infra-intake](infra-intake/) | 基建实现 — AG 确认问题 + CC Design Dialogue 多轮协作 + 独立验证 |
| [agent-native-product](agent-native-product/) | 产品 agent 化改造 — ASSESS(A2-A6) → TRANSFORM → AUDIT，含 Agent Trial + Friction Log |
| [concept-model-review](concept-model-review/) | 概念模型审计 — DISCOVER → EVALUATE → PATH DESIGN，评估产品竞争力 |
| [jupyter-session](jupyter-session/) | 持久 Jupyter 会话 — kernel 管理 + 代码执行 + 输出截断 + 图片保存，直连 REST API |

## 技能间协作关系

| 协作模式 | 说明 |
|---------|------|
| `panel-discussion` → `task-delegate` | panel_launch.sh 是 task_launch.sh 的 thin wrapper |
| `bug-investigation` → `task-delegate` | inv_launch.sh 是 task_launch.sh 的 thin wrapper |
| `deep-analysis` → `task-delegate` | Analyst/Challenger agent 通过 task-delegate dispatch |
| `system-design` → `task-delegate` | Architect/Realist/Explorer agent 通过 task-delegate dispatch |
| `deep-analysis` → `system-design` | system_map.md 作为 system-design 的输入（可选、可组合） |
| `system-design` → `infra-request` | Blueprint 的 infra_requests/ 可直接提交 GitHub Issues |
| `infra-intake` → `task-delegate` | CC Design Dialogue + Baseline/Verify 通过 task-delegate dispatch |
| `ag-archive` → `task-delegate` | journal `[subagent]` tag 通过 task_id 关联执行记录 |
| `daily-report` → `ag-archive` + `task-delegate` + `panel-discussion` | 扫描 IPC 目录生成日报 |
| `jupyter-session` → `tmux-protocol` | jupyter_api.py 通过 tmux 调用 |
| `all terminal skills` → `tmux-protocol` | 所有涉及终端的操作必须遵循 tmux 协议 |
| `all skills` → `skill-creator` | 文档标准：SKILL.md (agent) + README.md (human) |
| `agent-native-product` → `task-delegate` | Scout/Transformer/Auditor 通过 task-delegate dispatch |
| `deep-analysis` → `agent-native-product` | system_map.md 可作为 ASSESS 输入 |
| `concept-model-review` → `task-delegate` | Discoverer/Evaluator/PathDesigner 通过 task-delegate dispatch |
| `concept-model-review` → `agent-native-product` | concept_map + 打开路径 feeds A1 维度 |
