# APP.md

## 项目协作入口

本文件是本项目后续开发协作的入口说明。开始任何开发、修复、重构、发布或文档任务前，先阅读本文件，再按任务类型阅读 `docs` 下的对应标准文件。

## 标准文件路径

- 项目文档索引：`docs/README.md`
- 开发需求标准：`docs/requirements.md`
- 技术实现标准：`docs/technical-spec.md`
- 设计规范标准：`docs/design-spec.md`
- 执行步骤标准：`docs/execution-steps.md`
- 开发日志目录：`docs/development-log/`
- 开发日志模板：`docs/development-log/TEMPLATE.md`

## 每次工作的固定流程

1. 读取 `APP.md` 和 `docs/README.md`，确认当前任务需要遵循的标准文件。
2. 读取 `docs/development-log/` 中最新日期日志，了解已完成事项、遗留问题和待办专项。
3. 开发前确认需求、技术约束、设计约束和验证步骤是否明确；不明确时先补充或记录到对应文档。
4. 开发中优先遵循项目现有结构：公共导出在 `lib/stock_chart_flutter.dart`，核心实现放在 `lib/src/`，示例放在 `example/`。
5. 完成后更新当天开发日志；如果当天日志不存在，则按 `docs/development-log/TEMPLATE.md` 新建 `YYYY-MM-DD.md`。
6. 当天日志必须记录已完成开发事项、变更文件、验证结果、待办专项和下一步建议。

## 日志记录规则

- 日期使用本地工作区日期，文件名格式为 `YYYY-MM-DD.md`。
- 已完成事项写清楚实际完成的开发或文档工作，不记录模糊描述。
- 待办专项只记录仍需推进的具体事项，并标明优先级或触发条件。
- 如果没有运行验证命令，需要在日志中说明原因。
- 每次任务结束前都要检查当天日志是否已更新。

## 当前项目定位

`stock_chart_flutter` 是一个 Flutter 股票图表组件包，核心能力包括 K 线图、分时折线图、缩放、平移、十字光标、移动均线和腾讯行情风格示例页面。项目开发应优先保证金融图表的稳定性、可读性、跨平台交互一致性和发布包 API 的兼容性。
