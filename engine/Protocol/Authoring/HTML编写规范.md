# HTML Native Studio 编写规范

协议 `html-native/1`；工程规则 `native-rules/2`。规则只描述结构与映射，不含任何业务项目的固定名称、路由或资源路径。当前完整示例：`examples/NativeRules`。

## 工作方式与边界

有现成 UI 原图时，同时完整阅读 `UI原图复刻规则.md`（ui-replica/1），按资源先行、逐页测量、全屏背景、同视口对照的流程生产。该规则不改变本协议的技术与修改边界。

这是结构化 HTML 到 UIKit 的转换器。只接受能力清单内的 ui-* 标签、样式、声明式数据和动作；不接受任意网页、JavaScript、第三方框架或网络请求逻辑。系统不会凭截图猜按钮逻辑。发现不支持的内容时报告文件/节点，补齐协议能力后再实现。

新项目用 393 pt 基准宽度，模板高度 852。所有尺寸、字体、间距、圆角由原生统一宽度缩放工具适配，节点位置通过 NSLayoutConstraint 落地。可用高度取运行设备的实际高度，不另做按高度缩放；系统导航和安全区从可用内容高度扣除，根节点坐标相对于内容区；不要手动再加状态栏/导航栏高度。弹窗覆盖全屏。手机壳由工作台管理。

旧 402×874 项目仍能导入和编辑，不自动重排已有布局。导出前应按本规则迁移宽度、本地化、导航和权限声明；不能为通过检查而清空用户布局。

## 目录与登记

```
app.json                         项目身份、入口、状态、页面表、导航、语言和 iOS 配置
AGENTS.md / CODEX_TASK.md         给 Codex 的入口与任务说明
pages/<page-id>/page.html         每页一个根节点的 HTML 片段
pages/<page-id>/style.css         该页样式
components/<id>/view.html         共用结构（不用于自绘系统导航）
components/<id>/style.css
assets/catalog.json              所有图片与字体的清单
assets/shared/                   共用图片
assets/pages/<page-id>/           页面专属图片
assets/fonts/                    TTF / OTF 字体
localization/en.json              英文 key 表
localization/zh-Hans.json         简体中文 key 表
actions.json                     声明式行为
tokens/design.json               平面设计变量
.studio/authoring/               规范、能力清单、示例和校验入口
```

只加载 app.json 登记的页面、组件、动作文件。未登记的 assets 文件会报错；不要把资源藏在约定目录外。资源必须能够解码，目录与引用必须在项目内。新增/删除页面、资源时同步维护清单。

## app.json 工程规则

保留模板的 protocol、id、name、entry、viewport、stateVersion、state、pages、components、actions、tokens。id 稳定且项目独有。新增配置：

```json
{
  "viewport":{"width":393,"height":852},
  "localization":{"default":"en","files":{"en":"localization/en.json","zh-Hans":"localization/zh-Hans.json"}},
  "ios":{
    "classPrefix":"AB",
    "currencySymbol":"c.circle",
    "permissionKeys":{
      "NSCameraUsageDescription":"permission.camera",
      "NSPhotoLibraryUsageDescription":"permission.photos",
      "NSMicrophoneUsageDescription":"permission.microphone",
      "NSUserTrackingUsageDescription":"permission.tracking"
    }
  },
  "navigation":{"tint":"#235BDE","background":"#FFFFFF","tabs":[
    {"page":"home","titleKey":"nav.home","symbol":"house"},
    {"page":"settings","titleKey":"nav.settings","symbol":"gearshape"}
  ]},
  "links":{"privacy":"https://example.com/privacy","terms":"https://example.com/terms"}
}
```

classPrefix 用应用名缩写的 2–3 个英文字母（新建时按名称生成，可调整为正式缩写），导出的自定义 Swift 文件、类、结构统一前缀。示例链接是占位地址，正式交付前替换为真实地址。权限说明按真实用途填写；登记说明不等于自动申请权限或实现相机/麦克风功能。

每页字段：`id/name/role/html/css/navigation/onEnter/dismissOnBackdrop`。css、navigation 内可选字段、onEnter 可按需省略。role 使用 primary/detail/startup/dialog；弹窗必须是 dialog。顶部导航可写：

```json
{"titleKey":"nav.detail","backTitleKey":"action.back","buttons":[
 {"id":"privacy","titleKey":"action.privacy","symbol":"hand.raised","action":"show-privacy","side":"right"}
]}
```

`navigation.hidden:true` 隐藏该页顶部栏；非弹窗的可见导航必须有 titleKey。无底部导航时声明 `navigation.tabs:[]`。底部最多五项，同一路由不重复。原生使用 UINavigationController/UITabBarController，详情 push 自动隐藏 Tab Bar；HTML 端按同一声明预览栏位和文案。系统导航不进入可拖动的业务图层。

`onEnter:"action-id"` 在首次进入或声明式导航进入该页时执行，可开始一个 loading/delay 流程。它不是每次重绘都执行的钩子。不要写无条件循环跳转；动作有执行步数上限。返回已有页面保留状态，不重复执行 onEnter。

## 本地化与真实内容

两份 JSON 均为平面 `key:字符串`，key 集合与 `{参数名}` 集合必须完全一致。默认英文。不重复创建第三套语言文件。

```html
<ui-text id="title" text-key="screen.title" style="height:48"/>
<ui-text id="balance" text-key="balance.amount"
 text-args='{"amount":{"get":"state.balance"}}' style="height:32"/>
<ui-input id="name" bind="name" placeholder-key="input.name" style="height:44"/>
<ui-segment id="sort" bind="sort" option-keys='["sort.newest","sort.oldest"]' style="height:36"/>
```

语言表如 `"balance.amount":"Balance: {amount}"`，中文对应 `"余额：{amount}"`。变化数值放参数，不能写死扣费金额。`content='{"t":"screen.title"}'` 和动作表达式中的 `{"t":"key","args":{...}}` 也支持。

真正的用户内容可用 `{{item.title}}`、`{{state.userNote}}` 或 `content='{"get":"params.message"}'`。不得将固定按钮文案藏进 state 来绕过 key 检查。编译器无法判断一段数据是不是用户内容，作者要在清单注明来源。

富文本 spans 使用 UTF-16 start/end，end 不含结尾；支持 fontSize/fontWeight/color/italic/underline。所有语言的范围必须有效。语言长度不同需拆分独立 key 节点，不用固定范围跨不同翻译强套。

## 标签、图层和图片

HTML 只写片段，不写 doctype/html/head/body/script/link。每节点稳定 id，以英文字母开头；模板内不重复。不因为改文案或颜色改 id。

| 标签 | 原生对应 |
|---|---|
| ui-page/ui-column/ui-row/ui-stack/ui-grid | UIView 容器及声明式布局 |
| ui-scroll | UIScrollView |
| ui-text | UILabel |
| ui-image / ui-icon | UIImageView / SF Symbol UIImage |
| ui-button / ui-checkbox | UIButton / 系统勾选图标 |
| ui-input / ui-textarea | UITextField / UITextView |
| ui-switch / ui-slider / ui-stepper | UISwitch / UISlider / UIStepper |
| ui-segment | UISegmentedControl |
| ui-progress / ui-spinner | UIProgressView / UIActivityIndicatorView |
| ui-use | 显式共用模板 |

图片、组件背景、文字分层，不把整页做成 PNG。图标用 `<ui-icon id="search" symbol="magnifyingglass"/>`。装饰插画或照片用 ui-image。货币图标用 `ui-icon semantic="currency" symbol="c.circle"`，symbol 必须等于 ios.currencySymbol；所有出现位置引用同一个配置。

资源清单格式：

```json
[{"id":"shared.brand","path":"assets/shared/brand.png","kind":"image"},
 {"id":"font.body","path":"assets/fonts/body.ttf","kind":"font"}]
```

图片支持 PNG/JPEG/WebP，字体 TTF/OTF。asset 引用清单 id，font 引用字体 id。动态图片可用 `asset="{{item.image}}"`，所有可达数据值都要在清单登记。禁止绝对路径、远程图片 URL 和 Base64。导出时图片放 Assets.xcassets（WebP 转 PNG），字体保留本地字体文件。

## 布局与样式

CSS 只支持 `.class { 属性:值; }` 和节点 style，不支持选择器级联、伪类、媒体查询、浏览器全套 Flexbox。完整白名单见 capabilities.json。

- 数值：width/height/left/top/right/bottom/gap/padding/font-size/font-weight/line-height/letter-spacing/border-radius/border-width/opacity/rotation/scale/columns/row-height/flex-grow；可写 px，旋转可写 deg。
- width/height 的 fill 表示分配可用空间；auto 使用引擎默认值，不是浏览器自动文本测量。多行文本必须留够高度。
- display:flex/stack/grid；flex-direction:row/column；position:relative/absolute。
- align-items/align-self:start/center/end/stretch；stretch 配合明确 fill。
- overflow:hidden/visible，滚动使用 ui-scroll；object-fit:fit/fill/stretch。
- font-family:sans/serif/monospace/cursive；text-align:left/center/right。
- color/background/border-color:#RRGGBB 或 #RRGGBBAA；透明用 transparent。
- token 为平面 JSON，使用 `var(--accent)`。

不支持百分比/calc/rem/vw/vh/margin/filter/SVG/canvas/任意 CSS keyframes。复杂装饰使用独立图片，不能覆盖文字和点击节点。

渐变通过 `gradient='{"colors":["#235BDE","#A5D9F5"],"start":[0,0],"end":[0,1]}'`，可选 locations 与颜色数相同；阴影通过 `shadow='{"color":"#00000033","x":0,"y":4,"blur":12}'`。需要阴影和裁切时分两层。

动态样式示例：`styles='{"background":{"op":"if","args":[{"get":"state.selected"},"#CFEBDD","#FFFFFF"]}}'`。不要写 CSS :selected/:disabled，这些不在协议中。

## 状态、集合与控件

bind 相对于 state（`bind="accepted"`，不写 state.）。初始字段必须登记，输入为字符串，checkbox/switch 为布尔，slider/progress/stepper/segment 为数值。segment 为从 0 开始的索引。输入类型 text/password/number。

`when/disabled/selected/repeat/text-args/content/styles` 接受 JSON 表达式，外层单引号。选中状态不仅设置 selected，颜色等视觉差异同时通过 styles 描述。checkbox 的 isOn 由 bind 产生，不自动附加“同意”之类的文案。

重复节点使用 repeat + 稳定唯一 key，同类页面用 params/state 更换内容，不复制大量同布局页面。节点身份为 `页面/父节点/item[数据ID]`。

表达式读取 `{ "get":"state.count" }`；可读 state/params/item/event/storage/index。运算写 `{ "op":"add","args":[{"get":"state.count"},1] }`。支持 eq/not/and/or/add/sub/gt/gte/lt/concat/length/if/trim/split/join/contains/map/filter/find/sum。map/filter/find 的第二参数是 item/index 表达式；sum 只接受有限数值数组。不能执行 JavaScript。

## 点击、链接、加载与弹窗

所有按钮必须有 action；所有可编辑控件至少有 bind 或 action。不支持的事件属性直接报错，不能只画可点击的外观。

| 动作 | 字段和作用 |
|---|---|
| set / toggle | path,value / path |
| append / remove / update | path,value / path,key,value / path,key,id,value |
| if | when,then,else |
| push / replace / tab | page,params；入栈、替换、切换一级页 |
| back | 先关弹窗，否则返回上一页 |
| present / dismiss | page / 无；自定义 dialog 页面 |
| openURL | link；引用 app.links 中的 HTTPS 地址，iOS 用 SFSafariViewController |
| delay | duration,actions；0–60 秒内、严格大于 0 的声明式延时 |
| persist / restore | key,value / path,key,default；本地数据读写 |
| reset | 恢复初始 state，取消待执行延时，保留 storage |
| animate | duration,delay,curve,actions；0–10 秒，linear/ease/spring |

同一个 dialog 页面同时只显示一份：重复 `present` 已打开的弹窗不会叠加，也不会再次执行它的 `onEnter`。关闭后重新打开会再次执行 `onEnter`。不同 dialog 可以嵌套显示，`dismiss` / `back` 每次关闭最上面的一层。

加载占位符：

```html
<ui-spinner id="loading" when='{"get":"state.loading"}' style="width:24;height:24"/>
<ui-button id="next" action="open-detail" text-key="action.continue"
 disabled='{"get":"state.loading"}' style="height:44"/>
```

```json
{"open-detail":[
 {"type":"set","path":"loading","value":true},
 {"type":"delay","duration":1.2,"actions":[
  {"type":"set","path":"loading","value":false},
  {"type":"push","page":"detail"}
 ]}
]}
```

delay 不会阻塞 UI。工作台由服务计时，导出工程在原生运行端计时；重启后尚未完成的延时重新计时，不代表网络请求成功。模拟加载不能冒充真实登录、支付、上传或网络结果。需要真实业务能力时另接原生实现。

onEnter 可引用该类动作以展示页面进入加载。加载期间要禁用哪些操作必须明确声明；需要全页遮罩时用 dialog，不凭 loading 字段名称猜交互范围。

所有弹窗注册为 role:dialog，使用 ui-stack 与内部面板、自有颜色和本地化文案，提供关闭动作。dismissOnBackdrop:true 可关闭遮罩；不能用不透明全屏根背景挡住遮罩点击。弹窗和按钮一起转换，不生成 UIAlertController。

animate 同步位置、尺寸、旋转、颜色、透明度与进入/退出淡入淡出；iOS spring 与浏览器近似曲线需分别确认，不能保证每帧像素一致。

## iOS 编辑、保存、运行和导出

HTML 是结构与行为来源，iOS 覆盖用于调整外观。拖入 HTML 图层时保留原始动作、绑定和本地化来源，动态内容继续跟随。单层与连同子层复制分别选择。iOS 新增按钮或手改固定文案后，需要回到 HTML 补齐动作/key 再导出，转换检查会明确提示。不要通过删除校验绕过。

源码和 iOS 同改一个属性会报告冲突；不能清空 Workspace 或覆盖记录。共用视觉结构用 ui-use，跨页覆盖共享 sharedKey；原生导航由 navigation 集中管理。

隐私链接在真实模拟器中打开系统 Safari 容器。工作台提供“关闭网页”返回按钮；网页内的滚动、表单等操作在真实模拟器窗口进行，不映射为 HTML 项目的图层事件。

“运行 / 重启 iOS”保存布局、构建运行端、启动专用模拟器、安装启动 App 并恢复同步，进度和失败日志可见，不抹掉模拟器数据。日常 HTML 更新通过热同步完成，不需每次构建。

“导出 iOS 工程”导出完整页面表、所有弹窗、资源、动作、本地化及 iOS 外观覆盖，独立导出包位于 `HTMLNativeStudio/iOS/<App名>/`，再次导出使用 `<App名>-2` 等新目录保留历史包。存在受支持的外层 UIKit 空工程时，仅在用户明确导出时将生成代码与资源迁入外层 `StudioGenerated` 并接入 `ViewController.swift`；保留工程配置。后续导出更新上次生成内容，外层生成内容被手动修改时停止覆盖。工作区始终可继续编辑，日常同步不得写入外层，具体边界见 AGENTS.md。工程最低 iOS 15、纯 UIKit，离开工作台可独立运行；不复制当前一个页面作为整个工程。

## 工作台编辑与预览行为

这些是工作台的通用行为，不是要求业务项目增加特定页面或修改已有布局。

| 功能 | 约定 |
| --- | --- |
| 启动页编辑 | 手机下方同一个按钮进入与关闭。进入时暂停启动页 onEnter 和当前预览会话的延时动作，按钮显示“关闭启动页编辑”；关闭或切回运行时重新执行正常启动流程。保留布局修改，不删除项目动作，不修改 Xcode LaunchScreen。 |
| 选区关联 | 编辑状态下，HTML 点击或资源列表选择按相同图层 ID 选中当前 iOS 页面对应成员。没有对应项或被隐藏、锁定时不猜测匹配、不自动跳页。移动、缩放、删除操作不因此跨端转发；原有 HTML 源码同步机制不受此约定改变。 |
| 多选与资源缩放 | 每个选中资源保持独立选框。左侧 ＋ / − 缩放选中资源，不是缩放整台手机；资源和选框一起更新。 |
| 几何定位 | 自身与全部祖先的缩放、旋转、滚动及安全区坐标必须纳入定位；选框、命中、框选与拖动使用一致换算。不得用项目名、资源名或固定偏移掩盖误差。 |
| 页面转场 | iOS 默认 0.18 秒淡入淡出；首次显示及同页输入、滚动、同步不重复触发页面转场。遵循系统减少动态效果设置。 |
| 动画清理 | 完成、取消、替换及切页时清理临时画面和动画残留，不留半透明“薄膜”。保留项目明确声明的弹窗遮罩，不通过删除正常背景或全局强制不透明修复。 |
| 导出后调整 | 默认转场会随原生运行代码导出，可修改导出代码的 pageTransitionDuration 或转场实现。外层手工修改后再次导出仍执行修改检测，不能假设可无条件覆盖。 |

编辑启动页只改变预览会话，不改变正式启动流程。排查异常前先确认当前模式、实际加载版本和项目路由，再区分遮罩声明、动画临时快照与残留画面。以上是行为约定，是否已通过以本次验收证据为准。

## 检查与交付

遵守用户的测试安排。用户自行构建/测试时只做允许的静态检查，不启动模拟器。获得授权后可运行 validate.py：核对声明、资源和双语页面的初始布局，再按验收清单手动确认真实交互。

交付列出所有页面、弹窗、组件、资源、动作与条件状态，包括空态、加载、选中、禁用、错误和内容态。静态检查不覆盖任意动态数据、每种条件组合、SF Symbols 的系统版本可用性、网络服务或视觉完全一致。未完成或未验证的项目要明确记录，不能宣称“所有情况全部通过”。

## 结构化解析与转换核对（structured/1）

新模板附带 `.studio/authoring/schemas.json`，其中 app、catalog、actions 分别描述 app.json、assets/catalog.json 与动作文件的结构；业务规则仍以本规范和 capabilities.json 为准。

HTML 使用严格闭合的 ui-* 标签，可沿用 `<ui-image .../>`。图片、文字、原生控件、ui-path、ui-model 和 ui-use 不能再嵌套子图层；组合元素请用 ui-stack、ui-row 或 ui-column，防止原生渲染忽略内部内容。富文本用 spans，不嵌套 span。ui-use 实例支持 id/component/class/style，以及 name/group、when/repeat/key、action/disabled/selected/styles；这些实例属性会明确覆盖组件根节点的对应字段，styles 按属性合并。其余内容写在组件定义里；不支持的实例属性会报错，不再被静默忽略。

CSS 使用结构化解析，仍仅支持白名单属性、单一 .class 选择器和内联 style。不支持的选择器、属性和 !important 会报错；解析器升级不意味着支持任意网页。转义和注释由解析器处理，文案实体按 HTML 规则解码。

每次新版本导入或保存同步会核对初始页面的渲染数据到编辑数据是否完整；转换检查和导出检查进一步对比当前数据下的双语文案、资源引用、按钮动作、控件状态和原生导航。iOS 手工覆盖按覆盖后的预期值核对，不把正常编辑当作丢失。条件分支和依赖参数的页面仍需准备对应数据进行人工验收，不能把结构核对当作像素一致或全部交互通过。

工作台新建、接入和导入页面默认隐藏顶部导航栏（`navigation.hidden:true`），不自动添加 Home 标题或预留导航栏高度。仅在用户明确要求顶部原生导航时启用；状态栏和底部安全区保持系统管理。

## 当前 iOS 优先导出策略

导出以当前 iOS 合成页面为准：保留所有页面的 iOS 外观覆盖与新增图层，两端外观冲突不再阻止导出。源图层已不存在时不恢复旧图层，条件/重复层的覆盖仍保留。工作区差异记录不因导出而清空；导出包的 IOSExportResolution.json 记录策略与差异。源码新鲜度、资源、动作、本地化以及外层工程保护继续校验。只有用户明确导出才更新外层工程。此规则取代旧的“必须逐项解决 iOS 外观冲突才能导出”要求。

### 已有关联工程的重复导出

旧源码目录与外层 Xcode 工程不在同一路径时，可在源码的 HTMLNativeStudio/iOS/export-target.json 记录已确认的工程绝对路径（project 字段）。后续明确导出先验证该目标，再生成新包并迁移到关联工程；目标丢失时报告错误，不静默导出到另一位置。日常编辑不会更新外层工程，Xcode 工程配置保持不变。

重复导出只忽略 Xcode 对 .xcstrings 的 JSON 排版及 extractionState 提取标记变化；翻译内容、其他生成代码的手动修改仍阻止覆盖。验证导出时对照外层 StudioGenerated 的页面模型、iOS 覆盖和新增图层，不能仅凭新导出包存在判定迁移成功。
