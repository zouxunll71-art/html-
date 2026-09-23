请在当前 HTML Native Studio 项目中实现我接下来给出的 App 需求。

先读 AGENTS.md、.studio/authoring/HTML编写规范.md、iOS工程规则映射.md、capabilities.json 和 app.json。以 examples/NativeRules 为当前工程规则参考；不要照搬它的业务页面。

如果我提供 UI 原图，完整读取 `.studio/authoring/UI原图复刻规则.md`（ui-replica/4），先输出 UI_AUDIT.md，再为所有页面/状态建立坐标模板及校准模式，接入一致的独立资源，按模板布局，抽离 QA，逐页交付并排、叠加、像素差分及交互证据和 design-qa.md。禁止普通页跳过模板，完整读取《生成素材规则.md》：图片素材只生成，不复用原始图片或抠图；允许细纹理、斑点和发丝差异，整体视觉须验收，替代字体不能冒称一致。纯 HTML 请求不修改/构建原生工程；工作台项目将方法落实到声明式 ui-* 协议，不另做不能同步的应用。缺失能力、资源或未验证项明确记录。

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

指定原图内资源单独生成时，遵循 UI原图复刻规则.md 的“带 UI 原图指定资源单独生成”：把实际 UI 图片传入图像工具，明确目标区域，逐资源输出并核对；仅文字提示和单张候选不能代替真实页面回填验收；随机细节按生成素材规则处理。

## 像素级复刻升级（ui-replica/4）

按 UI原图复刻规则.md 的执行门槛：锁定参考原图及哈希，读取生成文件真实像素并区分 pt/CSS px/DPR；资源和字体先独立验收；同一参数源驱动模板与页面；连续截图稳定后做分区域及整页差分；按几何、裁切、轮廓、文字、颜色顺序校准，回归即回退。纯 HTML 任务只验证 HTML；已授权双端任务分别对照同一原图，外层工程仍受显式导出边界保护。自动校准能力以 自动参数校准.md 的实现范围为准，未支持能力明确标记，不将规范当功能上线或验收证据。交付补充 qa/reference-manifest.json、qa/capture-environment.json、实际尺寸及校准记录。

自动参数校准工具已随规范提供于 `.studio/authoring/calibration/`。有可运行 HTML、锁定原图和测量参数时先读 `自动参数校准.md` 并执行截图校准；此工具的严格像素判定仍要求零差异，生成素材的整体视觉按《生成素材规则.md》另外验收，使用 --apply 后必须验证持久化源码。ui-* 原文件须先通过 export-preview.py 使用真实渲染器生成隔离预览；尚不支持校准 iOS，不得用候选结果代替最终输出。

兼容尚未重新安装规范的项目：若项目内缺少校准脚本，读取 `.studio/authoring/system.json` 的 systemRoot，在该目录的 Protocol/Calibration 使用已安装工具和 README.md；不覆盖旧项目定制规范，不因此改动业务源码。
