# iOS 工程规则映射

来源：用户提供的 IOS_All.md。这里只应用通用工程规则；页面和业务特定规则不自动套到每个 App。此映射说明实现范围，不表示本轮已经完成构建或真机验收。

| 原规则 | 本系统处理 |
|---|---|
| 1 | 与用户中文沟通；生成的原生源码标识、注释及内部错误为英文。 |
| 2、12、22 | 固定 UI 文案引用 key；en/zh-Hans 同 key 和参数，默认英文；导出一份 Localizable.xcstrings，另有双语 InfoPlist.strings。编辑器项目名称等元数据可中文。 |
| 3、4、5、7、8 | 游客身份、Keychain、登录时序和账户删除是业务规则，不自动生成。可声明 loading/delay；不伪造真实身份或网络结果。 |
| 6 | app.links + openURL，iOS 用 SFSafariViewController；示例提供 HTTPS 占位链接，正式使用时替换。 |
| 9、10 | 原生页面节点由 NSLayoutConstraint 布局，StudioWidthScale 统一按 393 基准宽度缩放。导航安全区由系统计算。 |
| 11 | role:dialog 自定义布局、颜色、key 和按钮，通过 present/dismiss 同步；原生运行端不使用 UIAlertController。工作台自己的工具提示不属于导出 App 页面。 |
| 13 | 复用共享动作引擎、资源与现有 UIKit 运行端；不另写按项目名区分的转换器。 |
| 14 | ios.classPrefix 控制导出自定义 Swift 类与文件的 2–3 字母统一前缀。配置/语言/资源文件沿用系统格式。 |
| 15 | 导出工程最低 iOS 15、UIKit 原生视图。页面不包 WebView；动作仍由本地声明解释器执行。工作台开发环境最低版本与导出最低版本分开配置。 |
| 16、17、18 | 启动页、登录页内容及按钮位置是业务页面规则，不强制。页面可声明 onEnter 来表达自己的进入流程。 |
| 19 | 本轮不构建、运行或执行功能测试。系统“运行 / 重启 iOS”按钮供用户主动触发构建与运行。 |
| 20 | 全部声明图片导出到 Assets.xcassets，使用 UIImage(named:) 加载；原生图标为 SF Symbol UIImage。 |
| 21 | 点击内容空白区隐藏键盘；不会吞掉输入控件点击。 |
| 23、27、30 | 顶部 UINavigationController，底部 UITabBarController；导航固定，push 自动 hidesBottomBarWhenPushed，导航项的文字和事件同步。 |
| 24 | 配置四项权限说明 key，导出 Info.plist 与双语 InfoPlist.strings；不会主动申请四项权限。 |
| 25、26 | 金币商店 UICollectionView、购买业务加载和支付能力不自动生成；ui-spinner、disabled、dialog 可表达已声明的加载与交互屏蔽。 |
| 28、29 | 业务数值由共享 state / 参数驱动，可用 key 参数呈现、自定义 dialog 确认；具体扣费和账户账本不自动生成。 |
| 31 | 语言表禁止指定的中英文用词；任意用户输入/外部数据不在静态文案扫描保证范围。 |
| 32、33 | 图标使用 ui-icon + SF Symbols；semantic=currency 强制等于 ios.currencySymbol，使用 UIImage，禁止把该语义声明为文本节点。作者不能把图标伪装成普通照片绕过语义规范。 |
| 34 | 原文未列出。 |
| 35、36 | 登录/会员/商店的页面内容、布局和强制加载规则不自动套用。 |

完整原生 API、网络、支付、Keychain、设备权限流程等尚未加入声明协议的能力必须单独实现后再使用。规则文档中的业务描述不能被当成已实现功能。
