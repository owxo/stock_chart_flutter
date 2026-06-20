# 技术实现标准

## 代码结构

- `lib/stock_chart_flutter.dart`：公共导出入口，只导出稳定 API。
- `lib/src/models/`：图表数据模型，例如 `CandleData` 和 `LinePoint`。
- `lib/src/stock_candlestick_chart.dart`：K 线图组件和绘制逻辑。
- `lib/src/stock_line_chart.dart`：折线图组件和绘制逻辑。
- `lib/src/stock_chart_theme.dart`：图表主题配置。
- `lib/src/tencent_quote_data_source.dart`：腾讯行情接口请求、JSON/JSONP 解析和数据模型转换。
- `lib/src/tencent_stock_chart_page.dart`：腾讯行情风格示例页面、状态编排和数据加载调度。
- `lib/src/tencent_stock_chart_painters.dart`：腾讯行情示例页内的自定义绘制器。
- `lib/src/tencent_stock_chart_right_panel.dart`：腾讯行情示例页右侧盘口和成交面板。
- `example/`：包使用示例和人工验证入口。

## 实现约束

- 图表主体使用 Flutter 原生 Widget、Gesture、Listener、MouseRegion 和 CustomPainter 实现。
- 对外组件保持无侵入接入方式，优先通过构造参数配置数据、尺寸、主题和回调。
- 绘制逻辑需要处理空数据、可视范围、价格区间极小值和滚动边界。
- 网络相关逻辑只能放在示例或明确的数据适配层，不应污染通用图表组件；请求必须有超时控制，解析逻辑应可单元测试。
- 腾讯行情示例页默认不配置股票代码；只有 `symbol` 非空时才触发远程请求，空状态和失败状态不得填充模拟行情。
- 新增公共类型时，需要从 `lib/stock_chart_flutter.dart` 导出，并补充 README 示例或说明。
- 大型示例页面按职责拆分为状态编排、数据源、绘制器和局部 UI 文件；拆分优先使用 `part` 保持私有实现不进入公共 API。

## 数据模型标准

- K 线数据使用 `CandleData`，必须包含时间、开盘、最高、最低、收盘和成交量。
- 折线数据使用 `LinePoint`，必须包含时间和值。
- 所有输入数据默认由调用方保证排序；如新增内部排序，需要明确记录行为和性能影响。

## 交互标准

- 缩放应围绕手势或鼠标焦点位置展开，避免视图跳动。
- 平移后滚动位置必须 clamp 到有效范围。
- 选中回调应在选中项变化时触发，清空选中状态时返回 `null`。
- 长按结束、鼠标离开等场景需要清理十字光标或焦点状态。

## 质量要求

- 常规变更后运行 `flutter analyze` 和 `flutter test`。
- 发布前运行 `flutter pub publish --dry-run`。
- 涉及示例应用平台能力时，优先运行对应平台的示例或构建命令。
- 无法运行验证时，在开发日志和最终说明中写明原因。
