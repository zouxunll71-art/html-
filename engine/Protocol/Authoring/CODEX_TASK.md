请在当前 HTML Native Studio 项目中实现我接下来给出的 App 需求。

先读 AGENTS.md、.studio/authoring/HTML编写规范.md、iOS工程规则映射.md、capabilities.json 和 app.json。以 examples/NativeRules 为当前工程规则参考；不要照搬它的业务页面。

如果我提供 UI 原图，必须完整读取 `.studio/authoring/UI原图复刻规则.md` 并执行：先清点与准备独立资源，复杂主页用轮廓/锚点校准，普通页直接测量；背景全屏覆盖安全区，控件仍在内容区；逐页做同尺寸、同状态截图对照，修复明显差异后再进入下一页。不要重新设计、裁切 UI 截图做素材、重复生成可复用资源、擅自增加业务功能，或在未对照验收时宣称像素一致。文档中的网页方法须映射为本系统声明式 ui-* 协议，不另做无法同步的 HTML/JavaScript 应用。

- 新工程使用 393 pt 基准宽度，模板为 393×852；工作台提供手机壳、安全区和原生导航。
- 显式登记全部页面、弹窗、路由、动作、资源和共用组件，禁止项目名/文件名特判。
- UI 文案全部用英文、简体中文成对 key；不硬编码按钮、导航、提示、输入占位符和权限说明。实际用户内容用绑定。
- 顶部导航在 page.navigation 声明，底部在 navigation.tabs 声明；不画导航图片或自制 HTML tabbar。图标用 SF Symbols。
- 点击、输入、勾选、禁用、选中、加载、延时、页面进入和链接跳转均通过已支持的动作/状态声明实现。隐私、协议 HTTPS 链接由 iOS SFSafariViewController 打开。
- ui-spinner 是原生加载占位符，后续可替换；使用 when 控制出现，disabled 屏蔽不能重复触发的按钮。
- 图片按 assets/shared、assets/pages/<page-id>、assets/fonts 分类并登记 catalog；文字、背景、按钮分别成层，不用整页截图兜底。
- 保留用户的 iOS 外观修改。缺少协议能力时说明，不擅自塞入 JavaScript、WebView 或假的交互。
- 新工程补齐 ios.classPrefix、四项 permissionKeys 和本地化文件。导出包含所有页面、弹窗、资源和动作；独立包写入 HTMLNativeStudio/iOS/<App名>，重复导出保留编号历史包；接入外层工程遵守 AGENTS.md 的显式导出边界。

默认按 AGENTS.md 自行执行授权工作区内的必要校验、构建与浏览器镜像验证，无需逐次确认；用户明确限制构建或运行时遵循该限制。外层 iOS 工程不在默认构建和修改范围内，不能自行导出或迁移。交付页面/资源/动作清单、已做检查和待验证项；使用内置 validate.py 和验收清单，区分源码检查、构建、实际交互与视觉比对。

我的具体需求：
（在这里补充 App 名称、页面、UI 参考、资源和交互需求）
