# Reynard Browser · 简体中文维护分支

**面向中文用户的 Reynard 浏览器开源汉化维护项目。** 基于 [minh-ton/reynard-browser](https://github.com/minh-ton/reynard-browser)，使用 Gecko 内核，支持 iOS 13 及更高版本（实际可用性取决于机型、系统及安装方式）。

[English](README.md) · [原作者仓库](https://github.com/minh-ton/reynard-browser) · [构建记录](https://github.com/xytxg/reynard-browser/actions) · [上游同步日志](docs/UPSTREAM_SYNC.md)

> [!NOTE]
> 本项目是社区维护的 Fork，**不是原作者、Mozilla、Apple 或 OpenAI 的官方发行版**。Reynard 仍处于实验阶段。本文不承诺已通过全部兼容性测试，也不宣称进行了正式安全审计。

## 项目目标

- **简体中文界面**：完善浏览器主界面、阅读模式、隐私设置、跟踪防护、远程调试等文案。
- **跟进上游**：同步 Gecko 内核、iOS 适配、标签页、下载及扩展功能的上游修复，保留原有代码署名与历史。
- **减少回归**：引入字符串资源和格式占位符检查，避免出现“译文存在但为空”的情况。
- **可追溯构建**：使用 GitHub Actions 构建并保存测试产物；只有真正构建完成才会发布可下载的预览版本。

目前同步后的资源包含 **471 条主界面字符串、41 条设置字符串**，已检查简体中文译文的存在性与非空状态。这是资源文件覆盖率，不代表每个页面都已完成真机测试。

## 当前开发状态

- 本次同步的上游版本：[`6e84bfca`](https://github.com/minh-ton/reynard-browser/commit/6e84bfca9c16b2204dc64c93d2089b5410039897)。
- 上游配置版本：`0.18.0`；Fork 预览构建使用单独的构建标签，不冒充原作者官方版本。
- 源码、翻译与构建改动均可在公开提交中核查，详见 [同步日志](docs/UPSTREAM_SYNC.md)。
- 构建与安装兼容性需要以 [Actions](https://github.com/xytxg/reynard-browser/actions) 的真实记录为准。

## 下载安装

**不要把原作者的 IPA 当作此汉化分支的 IPA。**

| 设备 / 安装方案 | 文件 | 注意事项 |
| --- | --- | --- |
| AltStore / SideStore | `Reynard.ipa` | 需要兼容的签名/侧载方式，安装时保留 App Extensions |
| TrollStore 兼容系统 | `Reynard-TrollStore.tipa` | 需要系统版本、设备和 TrollStore 兼容 |
| 已越狱设备 | `Reynard-Jailbroken.ipa` | 需要对应的越狱与签名环境；此分支的当前 CI 不构建该变体 |

**本仓库产物：** [Fork Releases](https://github.com/xytxg/reynard-browser/releases) / [GitHub Actions](https://github.com/xytxg/reynard-browser/actions)。如果没有成功构建的资产文件，请不要使用未经验证的旧 IPA。原版程序请前往 [上游 Releases](https://github.com/minh-ton/reynard-browser/releases)。

Reynard 的浏览器扩展、JIT、权限和内核接口存在特殊安装要求，**未签名 IPA 不能直接像 App Store App 一样安装**。安装失败时请先阅读 [构建与安装说明](docs/BUILD.md)。

## 自行编译（需要 macOS）

```bash
git clone --recursive https://github.com/xytxg/reynard-browser.git
cd reynard-browser
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
./tools/development/build-gecko.sh
./tools/development/build-idevice.sh
./tools/release/build-app.sh --no-signing
./tools/release/create-ipa.sh
```

具体 Xcode、Rust、Python、ldid 依赖及 GitHub Actions 操作方式参见 [docs/BUILD.md](docs/BUILD.md)。Gecko 完整编译对时间、磁盘及工具链要求较高，不保证所有 Xcode 版本都可一次成功。

## 维护、反馈与安全

欢迎贡献译文、检查占位符、提供真机复现步骤，以及报告普通 Bug。请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。仓库 Issues 功能如未启用，可通过 Pull Request 反馈非敏感问题；安全问题请勿公开发布完整利用细节。

## 特别鸣谢与开源协议

原始项目：**[Minh Ton / Reynard Browser](https://github.com/minh-ton/reynard-browser)**。浏览器主体、Gecko 集成、原始功能和上游历史属于原作者及对应贡献者。此仓库主要贡献是中文本地化、上游同步与独立维护。

遵循仓库原有的 [GPL-3.0](LICENSE) 与 Gecko 衍生补丁相应的 [Mozilla 许可说明](LICENSE.firefox)。保留原作者署名；不会将 Fork 冒充原创浏览器。
