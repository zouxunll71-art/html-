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
- 接入空文件夹 / iOS 工程时，在所选项目内创建 `HTMLNativeStudio/`，包含模板、AGENTS.md、编写规范与校验工具。

每台电脑的工作目录各自解析。“同步”是与这台电脑上的 Codex 同步，不是跨电脑复制别人的账号和项目。历史项目的源文件若不在本机，仍需先取得源码并添加正确路径。

可选环境变量：`CODEX_BINARY` 指定 Codex 可执行文件，`DEVELOPER_DIR` 指定 Xcode Developer 目录，`STUDIO_ROOT` 指定已配置的引擎目录，`STUDIO_APP_DEST` 指定构建的应用输出路径。

升级安装前请退出工作台及其后台服务。安装器保留本机配置、项目和账号数据；不会自动结束正在执行的任务。服务只监听本机，使用 18775 和 18777 端口；占用时需要先关闭冲突版本。

## 开发与校验

```sh
npm ci --ignore-scripts
npm run test:unit
python3 scripts/check_distribution.py
```

`npm test` 还包括已运行的本机服务接口测试。`npm run build:mac` 构建客户端，需要先完成安装、具有已生成令牌的本机引擎。

`engine/` 包含原工作台源代码、模板和规范，`native/` 为客户端宿主与构建脚本，`web/` 为对话界面。Codex App Server 为实验接口，官方更新可能需要适配。本项目不是 OpenAI 官方客户端。

GitHub 私有仓库只有受邀用户可以下载；公开仓库可供所有人下载。第三方组件说明见 [THIRD_PARTY_NOTICES.md](engine/THIRD_PARTY_NOTICES.md)。本项目暂未授予额外的开源许可证，转载或再分发请联系仓库所有者。
