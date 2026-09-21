本项目由 HTML Native Studio 的 html-native/1 模板创建，iOS 工程规则修订为 native-rules/2。

开始前读取 `.studio/authoring/HTML编写规范.md`、`.studio/authoring/iOS工程规则映射.md`、`.studio/authoring/capabilities.json` 、`.studio/authoring/schemas.json` 和 `app.json`。参考当前示例 `.studio/authoring/examples/NativeRules`；旧示例用于旧协议对照，不能作为新工程入口。

新项目以 393 pt 宽度为基准，模板高度 852；位置、字号、间距按宽度统一缩放。手机外壳、安全区和系统导航由工作台管理。不要在 HTML 画业务导航栏、状态栏、灵动岛或 Home 指示条。

有 UI 原图的任务必须先完整读取 `.studio/authoring/UI原图复刻规则.md`（ui-replica/1）。先清点页面、状态、独立资源及缺失项，再逐页测量复刻；复杂主页才用轮廓/锚点模板，普通页直接测量。背景使用通用全屏背景层覆盖安全区；内容仍遵守系统安全区。已有正式资源复用，缺失资源用 ImageGen，不从 UI 截图裁切。每页必须有实际截图与原图对照，不能以可运行或大致相似代替验收，不声称未经验证的像素一致。

所有页面与弹窗显式登记；图片/字体完整登记 assets/catalog.json；稳定图层 ID 不随内容变化。UI 文案使用 text-key、placeholder-key、option-keys 或 t 表达式；en 和 zh-Hans 必须具有相同的 key 和参数。真实用户内容可从数据绑定读取，不能借此藏静态 UI 文案。SF 图标用 ui-icon；金币图标统一使用 ios.currencySymbol 的 UIImage，不能用文字符号。

每个按钮登记 action，每个可编辑控件登记 bind 或 action。页面进入动作登记 onEnter，定时步骤使用 delay；加载使用 ui-spinner + when，禁用和选中状态显式绑定。隐私、协议链接登记 links，通过 openURL 打开 iOS 系统 SFSafariViewController。

HTML 是行为与资源来源，iOS 覆盖用于独立调整外观。不能改系统安装目录、Workspace、运行状态或 overrides；不能用整页 PNG、WebView 或虚假的成功反馈充当原生实现。遇到协议未支持的能力，明确报告并补充协议后再使用，不静默删减。

遵守用户的构建/测试安排：用户说明自己测试时，不启动模拟器、不执行构建或运行测试。交付时明确区分语法/声明静态检查、实际构建和两端交互测试；未做的不能标为通过。用户允许后可运行 `python3 .studio/authoring/validate.py`，再按验收清单测试。
