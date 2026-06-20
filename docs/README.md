# 项目开发文档索引

本目录存放 `stock_chart_flutter` 的开发标准文件。后续需求、技术方案、设计约束、执行步骤和开发日志都应在这里维护，避免关键信息散落在对话或临时记录中。

## 文件说明

- `requirements.md`：项目目标、功能需求、非功能需求和验收标准。
- `technical-spec.md`：代码结构、技术约束、数据模型、交互实现和质量要求。
- `design-spec.md`：图表视觉、交互体验、响应式和可访问性规范。
- `execution-steps.md`：开发、验证、发布和文档维护的标准步骤。
- `development-log/`：按日期记录每日完成事项、验证结果和待办专项。

## 使用方式

1. 开发前从 `APP.md` 进入，按任务类型读取对应文档。
2. 涉及功能行为时同步检查 `requirements.md`。
3. 涉及实现结构、公共 API、性能或测试时同步检查 `technical-spec.md`。
4. 涉及界面、颜色、图表状态或交互体验时同步检查 `design-spec.md`。
5. 任务完成后按 `execution-steps.md` 做验证，并更新 `development-log/` 中当天日志。

## 文档维护原则

- 标准文件要描述稳定规则，临时结论放入开发日志。
- 代码行为改变时，同步更新需求、技术或设计文档。
- 发布前确保 README、CHANGELOG、pubspec 和本目录文档没有互相矛盾。
