# HTML Native Studio

连接本人 Codex 账号的 macOS HTML / UIKit 双预览工作台。支持项目接入、对话同步、图片标注、模型与速度选择、原生布局编辑和 iOS 工程导出。

## 下载与安装

1. 从本仓库的 **Code → Download ZIP** 下载，解压到任意文件夹。
2. 安装完整 **Xcode 26 或更新版本**，打开一次完成初始化，在 Xcode 设置中安装 iOS 26 或更新的 Simulator 运行时。
3. 安装 **Node.js 22 或更新版本**，安装 Codex 桌面应用并登录你自己的账号。
4. 在解压目录运行 `python3 scripts/install.py --check` 检查环境，再运行 `python3 scripts/install.py`。也可双击 `Install.command`。
5. 安装完成后，双击桌面的 **HTML Native Studio** 图标启动。安装器会自动创建指向 `~/Applications/HTML Native Studio.app` 的快捷方式，使用应用自身图标。首次编译需要几分钟，依电脑性能而定。

桌面只放快捷方式，源码与运行文件保存在用户资源库中；删除桌面快捷方式不会删除应用或项目。若桌面已有其他同名文件，安装器会保留它并为新快捷方式加编号。桌面访问受限时，可直接从 `~/Applications/HTML Native Studio.app` 启动。

目前仅支持 macOS；没有提供 Windows/Linux 安装包。此版本在本机编译并临时签名，尚未使用 Apple Developer ID 公证，不承诺下载后免依赖双击即用。

## 路径与个人数据

安装器会根据当前用户和本机环境自动生成配置，不使用开发者电脑的用户名、源码路径或模拟器编号：

- 引擎、模板与客户端源码：`~/Library/Application Support/HTMLNativeStudio/`
- 对话关联与图片附件：`~/Library/Application Support/HTMLNativeStudio-CodexClient/`
- Codex：使用当前用户自己的安装、登录、项目、技能与记忆。不会分享开发者的账号、额度、对话或业务项目。
- 接入空文件夹 / iOS 工程时，在所选项目内创建 `HTMLNativeStudio/HTML/`，包含模板、AGENTS.md、编写规范与校验工具；同级 `HTMLNativeStudio/iOS/` 存放导出的原生工程。

每台电脑的工作目录各自解析。“同步”是与这台电脑上的 Codex 同步，不是跨电脑复制别人的账号和项目。历史项目的源文件若不在本机，仍需先取得源码并添加正确路径。

可选环境变量：`CODEX_BINARY` 指定 Codex 可执行文件，`DEVELOPER_DIR` 指定 Xcode Developer 目录，`STUDIO_ROOT` 指定已配置的引擎目录，`STUDIO_APP_DEST` 指定构建的应用输出路径。

请通过桌面的 HTML Native Studio 图标启动新版；不要运行 engine/scripts/launch.py 或旧分享版的启动脚本。新版客户端只在后台启动预览引擎，不自动打开旧版编辑器窗口。

升级安装前请退出工作台及其后台服务。安装器保留本机配置、项目和账号数据；不会自动结束正在执行的任务。服务只监听本机，使用 18775 和 18777 端口；占用时需要先关闭冲突版本。

## 给 Codex 使用的后台同步窗口

工作台启动后提供本机镜像地址 `http://127.0.0.1:18777/mirror`。这是供 Codex 检查界面和辅助操作的入口，使用者继续使用桌面工作台，无需打开或管理额外窗口。

- Codex 使用浏览器工具在**后台隐藏标签页**打开镜像，不弹出窗口、不切换用户正在使用的应用。应用本身不会自动创建 Codex 的浏览器标签页；由具备浏览器工具的 Codex 按需连接。
- 镜像显示桌面工作台的当前画面。桌面端的变化会更新到镜像；镜像中的点击、滚动和文字写入会作用于同一个桌面工作台，并非独立副本。操作前先检查当前项目和未发送草稿。
- 输入文字时，先点击镜像中的目标输入框，再使用镜像页的文字写入入口。不要把查看权限理解为可以发送消息、修改项目或执行其他任务；操作仍须符合使用者当前请求。
- 复杂拖拽、系统文件选择器以及未支持的原生控件，仍使用桌面操作工具。不得声称镜像已支持所有桌面操作。
- 当前约每 1.2 秒请求刷新，不是高帧率视频。只有连接镜像时才采集画面，断开后约 5 秒停止采集；无人连接时不持续截图。镜像功能本身不调用 AI 模型。
- 镜像只在本机提供，使用当前电脑的工作台与账号。不要将端口对外公开。桌面工作台关闭时可能显示最后画面，以同步状态为准；重启后页面会尝试重连，若提示认证失效则重新打开镜像地址。

维护本工作台的 Codex 先阅读根目录 [AGENTS.md](AGENTS.md)。新接入项目里的 `HTMLNativeStudio/HTML/AGENTS.md` 也包含这一入口说明；已有项目不会被自动覆写规范。

## 开发与校验

```sh
npm ci --ignore-scripts
npm run test:unit
python3 scripts/check_distribution.py
```

`npm test` 还包括已运行的本机服务接口测试。`npm run build:mac` 构建客户端，需要先完成安装、具有已生成令牌的本机引擎。

`engine/` 包含原工作台源代码、模板和规范，`native/` 为客户端宿主与构建脚本，`web/` 为对话界面。Codex App Server 为实验接口，官方更新可能需要适配。本项目不是 OpenAI 官方客户端。

GitHub 私有仓库只有受邀用户可以下载；公开仓库可供所有人下载。第三方组件说明见 [THIRD_PARTY_NOTICES.md](engine/THIRD_PARTY_NOTICES.md)。本项目暂未授予额外的开源许可证，转载或再分发请联系仓库所有者。

## 新项目目录（v1.0.15 起）

```text
项目目录/
└── HTMLNativeStudio/
    ├── HTML/          # app.json、页面、资源、项目规范
    └── iOS/           # 导出的 Xcode 工程，每次导出独立目录
```

只应用于以后新建、接入和导出。现有项目的源码与关联路径不迁移。旧格式项目导出时，在其 HTMLNativeStudio 目录内生成 HTML 源码副本和 iOS 工程；原源码仍是编辑入口，HTML 副本首次创建后不自动覆盖。再次导出 iOS 会使用带编号的新目录，不覆盖先前工程。新建工程的原生目录在首次导出前为空。
