# 工作台客户端维护

这是独立客户端源码，不是业务 App 源码。原业务项目位于已安装工作台 Projects 目录，先通过 API 确认项目再修改。

保留原工作台的全部操作，优先复用 NativeHost 中复制的原生编辑器。修改 native/ 下的生成源，不要直接修改 NativeHost 生成文件。不得修改官方 Codex 应用或私有数据库。

字号与窗口采用 Mac 原生尺寸。聊天主体 15px、侧栏 14px、次要文字 12px，不对整个客户端使用 CSS transform 或 iPad 缩放。手机画布可独立缩放。

真实额度取 account/rateLimits/read，remaining=100-usedPercent，缺失显示不可用。禁止把示例百分比当真实数据。

构建：npm run build:mac。验证：已启动服务后 npm test；界面使用电脑操作工具检查具体修改状态。保留用户的原项目，操作测试使用“工作台联调示例”。
