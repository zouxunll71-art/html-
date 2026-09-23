# HTML 像素参数校准工具

这是可运行的、受边界约束的坐标下降校准器，不是任意 UI 图自动转 HTML 的生成器。给定原图、可在浏览器运行的本地 HTML、明确的数值参数和允许范围后，它实际截图、搜索参数、比较并回退。只有解码后的 RGBA 像素全部一致，才报告视觉通过。资源/字体不同、超出参数范围、未声明参数或局部最优均可能无法消除差异，结果如实保留。

## 安装和运行

需要 Node.js 22+。在本工具目录执行 `npm ci --ignore-scripts`，然后 `npm run setup` 安装 Playwright Chromium。已有 Chrome 时可在配置写 `"channel": "chrome"` 使用它，并在报告锁定实际版本。不同浏览器的结果不能混用。

新项目安装规范后位于 `.studio/authoring/calibration/`，命令：

```sh
node .studio/authoring/calibration/cli.mjs qa/calibration.json
node .studio/authoring/calibration/cli.mjs qa/calibration.json --apply
node .studio/authoring/calibration/cli.mjs qa/calibration.json --verify
```

默认仅输出候选，不改源码。`--apply` 只在达到零差异后写入配置指向的专用校准 CSS，并重新加载不带注入样式的真实 HTML 验证；不复现或交互失败则回滚。未达到零差异时源文件保持原样。`--verify` 不搜索、不注入参数，只校验已保存的页面。退出码：0 为视觉零差异（仍须查看交互是否验证），1 为未匹配，2 为配置/运行失败。

HTML 必须事先引用专用样式表，例如 `<link rel="stylesheet" href="qa/layout.css">`。该文件初始为空或由本工具生成，不能指向包含其他业务样式的 CSS；代码中的页面样式仍在原文件保留。校准不修改 HTML 结构、文案、资源和业务逻辑，不接入工作台正在运行的项目/模拟器端口。

## 配置示例

以下坐标与参数只展示格式，必须从自己的原图模板测量获得，不能照抄。参考图使用原始 PNG；先取得文件 SHA-256 再填入 referenceSHA256。root 相对于配置文件，其余文件路径相对于 root。outputParent 必须事先存在。区域使用截图像素，数值参数使用 CSS px。

```json
{
  "root": "..",
  "entry": "index.html",
  "hash": "#home",
  "reference": "qa/reference/home.png",
  "referenceSHA256": "填写原始PNG的64位SHA256",
  "stylesheet": "qa/layout.css",
  "outputParent": "qa",
  "viewport": {"width": 402, "height": 874},
  "deviceScaleFactor": 3,
  "readySelector": "#home",
  "maxEvaluations": 200,
  "maxPasses": 3,
  "parameters": [
    {"id": "hero.x", "selector": "#hero", "property": "left", "initial": 20, "min": 12, "max": 28, "step": 0.333333},
    {"id": "title.fontSize", "selector": "#title", "property": "font-size", "initial": 24, "min": 22, "max": 26, "step": 0.333333}
  ],
  "regions": [
    {"id": "header", "x": 0, "y": 0, "width": 1206, "height": 600},
    {"id": "body", "x": 0, "y": 600, "width": 1206, "height": 2022}
  ],
  "interactions": [
    {"type": "click", "selector": "#save", "expect": {"selector": "#status", "text": "Saved"}},
    {"type": "fill", "selector": "#name", "value": "Clay", "expect": {"value": "Clay"}}
  ]
}
```

支持属性：left/top/width/height/font-size/line-height/letter-spacing/border-radius、四边 padding、margin-left/margin-top。仅支持稳定的简单 `#id` 选择器，每个参数匹配一个元素，单位 px；不支持自由 CSS、opacity、隐藏元素、背景替换或任意脚本优化。变换、颜色、阴影、图标和资源错误应按报告另行修复，不能伪称当前搜索器能自动修好。

参数顺序由坐标模板决定，建议整体位置 → 容器 → 图片 → 文字；步长可用 1/DPR。当前使用倍率 8、4、2、1 的有界坐标下降，会遇到局部最优，不保证任意问题收敛。每次接受必须降低整页通道误差，且所有声明区域误差均不增加；还会保留精确差异像素数。不能通过删区域、放宽阈值或改原图掩盖问题。

## 确定性、输出和边界

使用独立临时浏览器上下文和本地只读静态服务器；外部网络、变更请求被阻止。图片必须完整加载，字体等待就绪。固定软件渲染与 sRGB 环境；每次测量在有限次数内等待连续两帧一致，始终不一致就停止；JS 动画/随机内容必须由页面自身提供确定的校准状态，工具不会隐藏它们以骗过验收。CSS 动画以截图禁用模式处理，视频暂停至开头，状态时刻需与原图一致。

输出在新的 `qa/calibration-*/` 目录，包含 report.json、before/after、每轮试验图、原始像素差分、半透明叠加、并排图、candidate.css、calibrated-parameters.json 和应用时的 CSS 备份。原图哈希前后复核，尺寸不同立即拒绝，不缩放原图。报告区分 candidate-only 与 persisted-source，passed/visual-only/unmatched/failed；没有交互断言时不能标为完整通过。校准参数 JSON 是供回写模板的映射，不自动改未知格式的模板；回写后应重新执行 --verify。

参考图路径不向被测页面提供，禁止其作为隐藏图片加载；用户仍需审计其他截图副本、CSS 内嵌背景和资源来源，工具不能证明图片的设计来源或保证检测所有伪装。不可把“零差异”扩展为其他设备、状态或原生 iOS 的通过结论。

## 工作台结构化 HTML

本工具直接处理浏览器可运行的 HTML/CSS/JS。ui-* 源文件不能直接在浏览器测量。已提供 `export-preview.py` 适配器：调用系统真实编译器和 HTML 渲染器，把声明、资源和页面状态生成独立预览，事件仅保存在当前浏览器内存，不激活工作台项目、不连接模拟器、不修改业务目录。

```sh
python3 .studio/authoring/calibration/export-preview.py --engine <系统引擎目录> --source <HTML源码目录> --page <页面ID> --output <新的隔离验证目录> --width <原图像素宽> --height <原图像素高> --symbols <原生图标缓存目录>
```

页面由 ui-* 真实声明和独立资源渲染，未使用原图当页面背景。输出 provenance.json 记录模型/渲染器哈希和映射。以模型逻辑宽度统一等比缩放到指定画布，逻辑高度按比例计算；移除手机硬件外壳和 OS 状态栏，但保留原生页面导航。详情页需显式传 `--base-page <父页面ID>`，否则直接以指定页作为栈起点；截图证据必须注明这一状态差异。参考图不包含导航而模型包含时仍如实报告差异，不偷偷隐藏导航。测试状态默认使用模型初始数据，不冒称正在运行的用户会话；未支持 onEnter/delay、弹窗和模型绘制 fixture，相关任务需补专门适配，不能宣称已验证。

有系统符号的页面必须提供真实图标 PNG 和 manifest.json（条目 name/color/file），不自行画近似图标代替。每个图层生成稳定 DOM ID，可通过 `[data-node]` 对照回声明；目前结果只在隔离预览生成候选 CSS，不自动改业务 ui-*。把参数映射回合法声明后必须重新导出独立预览、重新截图验证。未实现 iOS 参数搜索或实时工作台按钮；HTML 结果不能代替原生 iOS 验收。

## 验证

`npm test` 使用真实浏览器和隔离样例；如使用 Chrome，设置 `CALIBRATION_BROWSER_CHANNEL=chrome npm test`。测试原图由固定样例生成，仅用于验证算法，不是业务项目的验收原图。原始设计图必须由用户提供或明确认可。
