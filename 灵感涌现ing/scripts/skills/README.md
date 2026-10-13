# 技能系统架构与填写指南

已实现技能数据、效果执行、八个触发点、习得界面和存档状态。核心依据为 [游戏策划案](../../灵感涌现中%20策划案.html)，技能规则按 2026-10-13 程序答复：每人三个技能，技能 1／2／3 在 0／20／50 好感度解锁（好感度上限 50，原来的技能 4 与 100 门槛已删除）；存在自动生效与支付灵感习得两类。绵羊梦游者的白日梦、梦境讲述、梦想家已填写文案、触发器与费用，接入睡着、局内永久成长和一次任务翻倍。其余正式人物技能仍为空白占位，系统不自行为角色编写具体技能。

## 数据与代码分工

| 文件 | 职责 |
| --- | --- |
| `data/characters.json` | 三个技能位，引用 `skill_id`，保存解锁好感门槛 |
| `data/skills.json` | 技能唯一 ID、名字、介绍、吐槽、习得类型、费用和触发器 |
| `skill_definition.gd` | 只读资料 Resource、字段校验 |
| `skill_table.gd` | 加载与校验技能定义 |
| `skill_context.gd` | 阶段状态与结算方案的独立快照 |
| `skill_result.gd` | 效果返回的数值修正、临时效果和特殊结果 `outcomes` |
| `effect_registry.gd` | 效果代码注册与参数校验 |
| `effects/numeric_modifier.gd` | 通用固定值和百分比加成 |
| `effects/temporary_modifier.gd` | 持续当月或当年的临时加成 |
| `effects/sheep_skill.gd` | 睡着判断、永久成长及当前作品下一次任务翻倍标记 |
| `skill_runner.gd` | 资格、条件、频次、事件去重、效果合并和来源记录 |
| `game_model.gd` | 基础流程、各阶段调用及真实状态提交 |
| `member_sheet.gd` | 三个技能位和付费习得按钮 |

三个独立文本字段是 `name`（名字）、`description`（技能介绍）、`quip`（吐槽）。效果代码不解析文案。人物页显示这三段文字，长内容可滚动查看或悬停查看完整介绍；报告显示触发技能的名字和吐槽，完整来源记录在 `skill_events` 中。修改效果参数时需要同步修改介绍中的数值。

技能定义是共享资料，不保存角色进度。Godot 资源可能被缓存和共享，因此已习得 ID、触发次数、事件记录与临时效果均保存在本局状态里。[Godot 4.7 Resource 官方手册](https://docs.godotengine.org/en/4.7/classes/class_resource.html)

## 三个技能位与两种习得方式

人物表中的技能位按顺序为：

```json
"skills": [
  {"skill_id": "a_skill_1", "unlock_affinity": 0},
  {"skill_id": "a_skill_2", "unlock_affinity": 20},
  {"skill_id": "a_skill_3", "unlock_affinity": 50}
]
```

| `acquisition` | 生效方式 | `inspiration_cost` |
| --- | --- | --- |
| `auto` | 达到好感门槛自动生效，无须点击学习 | 必须为 0 |
| `inspiration` | 先达到门槛，再支付灵感一次性习得 | 必须为正整数，由每个技能独立配置 |

技能 1 的 0 好感门槛也可以搭配任一类型。正式占位定义默认 `auto`、费用 0、三个文本为空、触发器为空；未填写名字的技能不能购买或触发。

付费习得允许在立项准备和每月准备时进行，不消耗月份。报告或结局中不能购买，未解锁、灵感不足、重复习得、错误人物或技能位均不会扣费。学习状态按人物 ID 下的 `learned_skills` 保存；旧版单个 `learned` 标志、固定 6 灵感收费和固定专长倍率已删除。

每个阶段开始重新判断当前好感门槛。邀约使自动技能解锁时，只参与后续阶段，不重算此前阶段。付费技能仍须由玩家在准备阶段习得；改变技能配置类型或人物阵容后，应开始新游戏。

## 四个流程阶段及八个触发点

“结算前”指基础结算方案已生成但尚未写入状态，技能修正该方案；“结算后”指基础结果已写入，技能产生额外增量。后置百分比作用于后置方案自身，通常应使用 `add` 发放额外收益。Bug 暂为白板数值，不影响职责基础收益；技能修正最终贡献，不改写人物基础能力。

| 触发点 | 时机 | 支持的修正 |
| --- | --- | --- |
| `PROJECT_BEFORE` | 玩家确认年度立项后，应用基础立项方案前 | 偏好好感增量、初始作品属性、额外灵感 |
| `PROJECT_AFTER` | 立项方案完成后，进入月度准备前 | 好感、作品增量、灵感、临时修正 |
| `ACTION_BEFORE` | 本月单人行动确认后，应用任务或邀约方案前 | 任务产出、新增或修复 Bug、邀约好感增量 |
| `ACTION_AFTER` | 单人行动完成后，全员职责结算前 | 额外作品收益、好感、灵感、临时修正 |
| `DUTY_BEFORE` | 全员职责贡献方案生成后，统一应用前 | 指定成员或全队的职责贡献、修复量、新增 Bug；额外作品、好感、灵感 |
| `DUTY_AFTER` | 全员贡献及 Bug 变化完成后，试玩或评奖前 | 额外作品收益、Bug 修正、好感、灵感 |
| `AWARD_BEFORE` | 第 12 月职责结算完成后，最终评分与获奖判断前 | 游戏性／创新性／表现力分项，以及额外总分 bonus |
| `AWARD_AFTER` | 奖项确定后，年度奖励提交前 | 灵感奖励、好感增量；不能回改分数、Bug 或奖项 |

```text
立项确认：PROJECT_BEFORE → 立项提交 → PROJECT_AFTER
月度行动：ACTION_BEFORE → 单人行动提交 → ACTION_AFTER
月度职责：DUTY_BEFORE → 全员贡献统一提交 → DUTY_AFTER
年度评奖：AWARD_BEFORE → 分数与奖项确定 → AWARD_AFTER → 奖励提交
```

选择任务、调整岗位、打开或关闭界面都不触发结算。邀约使用 `action_kind = invite`，独立任务使用 `action_kind = task`。人物技能的所属者 `owner_id` 与行动者 `actor_id` 分开，任务专属技能应显式填写任务条件。

职责事件每月只处理一次全队，执行器汇总全员技能后修正按人物 ID 区分的贡献，避免全队加成在四人循环里重复四次。第 4、8 月试玩不触发年度评奖技能。年度评分按技能修正后的分项和 bonus 计算，再判断奖项；分项和总分限制在 0～100，Bug 不影响分数或获奖条件。

八个触发点已接入旧原型的实际立项、回合和年末流程。默认新界面已接入年度立项、单人任务／邀约及全员职责对应的六个触发点；开始按钮的跳转本身不派发技能。默认新界面尚未接入年末评奖、完整三年结局及玩家自动存档，不能把已有模型入口当作这些流程的界面交付。

## 填写技能

以下仅为填写示例，未加入正式数据：

```json
{
  "id": "a_skill_2",
  "name": "任务专注",
  "description": "自己执行任务时，该任务的游戏性收益增加 20%。",
  "quip": "先把这一件事做好。",
  "acquisition": "inspiration",
  "inspiration_cost": 3,
  "triggers": [
    {
      "hook": "ACTION_BEFORE",
      "conditions": {"action_kind": "task", "actor_is_owner": true},
      "target": "work",
      "frequency": "event",
      "effect_id": "numeric_modifier",
      "params": {"field": "g", "operation": "percent", "amount": 0.2},
      "priority": 0
    }
  ]
}
```

| 字段 | 支持内容 |
| --- | --- |
| `conditions` | `owner_role`（岗位 0～3）、`actor_is_owner`、`owner_slept`（本人是否在刚结束的阶段睡着）、`action_kind`、`action_id`（0～5）、`genre`、`topic`、`genre_id`、`topic_id`、`year`、`month`、`award_best`（用于评奖后判断） |
| `target` | `owner`、`actor`、`team`（成员目标）；`work`（作品）；`shared`（共享资源）；`score`（评分） |
| `frequency` | `event`、`month`、`year`、`run`；每个触发器在指定周期最多一次 |
| `operation` | `add` 固定值；`percent` 比例，0.2 表示 +20% |
| `field` | 作品／职责：`g` 游戏性、`i` 创新性、`v` 美术、`m` 音乐、`b` Bug；职责另有 `repair` 修复量；成员：`affinity`；共享：`inspiration`；评分：`g`、`i`、`p`、`bonus` |
| `priority` | 整数，执行器按优先级、人物 ID、技能 ID、触发器序号稳定排列 |

新界面的年度作品选择在确认时触发 `PROJECT_BEFORE`／`PROJECT_AFTER`。后续行动和职责也使用同一年度档案：`genre`／`topic` 是显示名，建议新增条件使用稳定的 `genre_id`／`topic_id`（如 `narrative`／`fantasy`），可避免改文案影响技能。上下文另提供 `project` 档案副本、`project_id` 和完整 `title`；作品数据与读取入口见工程 README 的“年度作品资料”。旧原型仍沿用原选项及显示名条件。

字段、目标与触发点的允许组合由 `effects/numeric_modifier.gd` 校验，错误配置不会静默生效。成员目标的产出字段仅用于 `DUTY_BEFORE`；其他成员目标只修改好感。

固定值先相加，百分比也先相加，结果为 `(基础方案值 + 固定加成合计) × max(0, 1 + 百分比加成合计)`。奖励与好感统一四舍五入为整数，好感保持 0～50，Bug 不低于 0。减少作品 Bug 可以使用 `target = work`、`field = b`、`operation = add` 与负数；增加职责修复量则用成员目标和正的 `repair`。

### 人物能力的两种加成

人物能力分两层，技能给出数值加成时按层归属：**直接加值**加到白值（`ClubGame.base_ability()`），**百分比增幅**与好感增幅一起在 `ClubGame.ability_bonus()` 相加，最后由 `ClubGame.ability()` 用「白值 × (1 + 增幅合计)」乘一次。每点好感提供 1% 增幅，好感上限 50 时最高 +50%。

梦境讲述已接入人物能力层：`ability_add` 结果写入成员本局 `ability_growth`，`base_ability(member_id, state)` 加到白值，随后统一应用一次好感增幅。人物页读取状态后刷新两列；数据表及共享角色定义不被改变。成长同局跨年保留，新游戏归零。不要把同一个加成重复写入两个层次。

当月或当年临时加成使用 `effect_id = temporary_modifier`，params 额外填写 `apply_hook`（`ACTION_BEFORE` 或 `DUTY_BEFORE`）及 `duration`（`month` 或 `year`）。例如 ACTION_AFTER 建立当月 DUTY_BEFORE 的全队修正。临时效果只参与随后对应阶段，不回改产生它的阶段；过期时清理并随存档保存。当前不支持评奖时建立临时修正，也不支持跨年延续当年修正。

特殊效果可在 `effects/` 新增 GDScript，再注册到 `effect_registry.gd`；实现 `can_trigger(context, conditions)`、`evaluate(context, target, params)` 并返回 `SkillResult`。绵羊效果 `sheep_skill` 支持 `sleep`（概率）、`growth`（本人及队友脑洞加值）、`dreamer`（当前作品任务标记）三种 `mode`，参数和触发阶段单独校验。特殊结果经执行器提交，不允许效果直接改写共享资料或真实状态。

睡着在前置数值修正合并后绝对清除本人贡献／任务输出，任务后置作品及灵感奖励也取消。成长和标记在对应后置阶段只因本人睡着而触发。任务睡着仍扣一步、保留年度次数；标记不叠加，可由任意社员下一次成功任务使用，睡着和邀约均不消耗。翻倍作用于任务前后阶段的作品及灵感增量，不放大好感或能力成长，也不影响月末共享灵感。标记保存 `project_id` 和 `year`，跨年或作品身份改变后清除。

## 预览、提交与运行状态

每个技能取得相同阶段起点的独立状态和方案快照，不能操作真实状态、界面或存档。效果返回修正，由执行器统一合并，效果之间不递归派发事件。

立项和回合函数先复制输入状态，预览在副本中模拟事件及次数，正式提交使用相同函数并采用返回的新状态。技能不会在界面重绘时执行。事件 ID 包含本局 ID、年份、月份与阶段；立项阶段月份使用 0。事件、频次和临时效果保存在 `skill_runtime`，学习状态保存在各人物的 `learned_skills`。重复提交、重新打开报告及读档不会额外获得技能效果。

同一技能的多个触发器当前分别计数，不共用额度。绵羊的随机种子由本局 ID、年月、阶段和本人 ID 的哈希生成，预览与提交不重新抽取；同一引擎版本中保存恢复也保留相同结果。当前存档版本为 4，成长与作品标记是可选字段，原有版本 4 状态按零成长、无标记兼容；版本 1～3 不读取，旧文件本身不删除。正式导出时需包含 `data/*.json`。

## 验证

双击“运行测试.cmd”依次运行技能、技能界面、人物表及原有规则检查。测试样本只存在内存或 `qa/` 中，不修改正式人物和技能表。覆盖三个门槛、两种习得方式、重复购买、灵感不足、阶段资格、任务与邀约区分、全队汇总、加成叠加、临时效果期限、年度限次、预览一致、读档恢复及评奖前后顺序。图形检查还验证三段文案、按钮扣费、状态刷新与不同分辨率下的布局。

`test_sheep_skills.gd` 同时进入启动器，验证三个已确认规则、概率边界、仅取消自己、成长与好感增幅、下一次成功任务翻倍及后置奖励、不能叠加、跨年和新局隔离、老状态兼容、非法成长／标记拒绝、保存后随机重现、真实任务／月末结果提示。图形运行时截图到 `qa/sheep_task_sleep.png` 与 `qa/sheep_monthly_sleep.png`。

灵感是社团全局资源，状态根字段 `inspiration` 保存共享余额；技能的 `shared/inspiration` 效果、习得消费及每月收益都通过游戏模型的同一资源入口结算，不修改人物或作品属性。定义见 `ClubGame.INSPIRATION`。
