# 执行步骤标准

## 开发前

1. 阅读 `APP.md` 和 `docs/README.md`。
2. 阅读 `docs/development-log/` 中最新日期日志，确认未完成事项。
3. 按任务类型阅读需求、技术或设计标准文件。
4. 检查当前工作区状态，避免覆盖他人或用户已有修改。
5. 明确本次任务的验收方式和需要更新的文档。

## 开发中

1. 保持改动范围聚焦，优先沿用现有组件、模型和目录结构。
2. 公共 API 变更要同步考虑 README、CHANGELOG 和导出入口。
3. UI 和交互变更要同步检查 `docs/design-spec.md`。
4. 技术结构或数据约定变更要同步检查 `docs/technical-spec.md`。
5. 发现新的待办或风险时，先记录到当天开发日志。

## 验证

常规验证命令：

```bash
flutter pub get
flutter analyze
flutter test
```

发布前额外验证：

```bash
flutter pub publish --dry-run
```

示例应用验证可按需要运行：

```bash
cd example
flutter run
```

## 开发后

1. 更新当天开发日志，记录完成事项、变更文件、验证结果和待办专项。
2. 如行为发生变化，同步更新 `docs/requirements.md`、`docs/technical-spec.md` 或 `docs/design-spec.md`。
3. 如用户可见能力变化，同步更新 README 或 CHANGELOG。
4. 最终说明中列出主要变更和验证情况。

## 日志更新步骤

1. 获取当天日期，文件名使用 `docs/development-log/YYYY-MM-DD.md`。
2. 如果文件不存在，按 `docs/development-log/TEMPLATE.md` 创建。
3. 在“已完成”中写入实际完成内容。
4. 在“变更文件”中列出本次修改的文件路径。
5. 在“验证”中写入已运行命令及结果；未运行则说明原因。
6. 在“待办专项”中保留下一步需要推进的具体事项。
