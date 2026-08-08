# Reynard Browser 简体中文说明

Reynard 是面向 iOS 13 及更高版本的 Gecko 浏览器。本分支保留原有 Gecko、JIT、应用扩展、
标签页和侧载架构，并加入简体中文（`zh-Hans`）、下载安全修复、私密会话保护和源码构建
未签名 IPA 的 GitHub Actions 流程。

已成功的 `main`、手动和 `v*` 标签构建会由 `github-actions[bot]` 自动发布到本仓库的
[Releases](https://github.com/xytxg/reynard-browser-zh/releases) 页面，并附带 IPA 与 SHA-256
校验文件。普通分支和 Pull Request 不具备发布权限。

## 上游同步状态

当前维护代码已同步原作者仓库截至 `f2dd5f6` 的 0.9.0 更新，并使用
`FIREFOX_153_0_RELEASE`。除鼠标/触控板指针支持、崩溃恢复、JIT 后台音频保活、站点缩放、
HTTPS-Only 与增强型跟踪保护外，本轮还加入实体键盘初步支持、网页内容延伸到底部工具栏
下方、链接“在后台打开”、更高质量的 Apple Touch Icon/Manifest 图标与 Gecko Release/LTO
优化配置。中文分支继续保留下载安全、私密会话保护、旧系统兼容与未签名 IPA 自动发布能力。

同步后额外移除了 favicon 对 Safari 私有框架的依赖，限制图标 URL 只能使用 HTTP/HTTPS，
并在 UIKit 解码前校验图片尺寸，降低畸形图片造成内存峰值的风险。Gecko 构建脚本会在成功、
失败或中断时恢复用户原有的 `.mozconfig`，不会把临时 Release 配置遗留在源码目录。

## 简体中文

当 iOS 的首选语言为“简体中文”时，Reynard 会自动使用中文；英文资源仍然保留。
主应用、OpenIn 扩展、Reynard Helper 扩展和附加组件界面都包含中文资源。可以运行
`tools/tests/run-static-tests.sh` 检查缺失翻译、重复键和格式化占位符。

## 未签名 IPA 是什么

GitHub Actions 产物没有 Apple 开发证书、分发证书或 Provisioning Profile，不能直接安装。
安装前必须使用兼容方式重新签名，例如 AltStore、SideStore、个人开发证书，或在兼容系统上
使用 TrollStore。重新签名和安装时必须保留以下扩展：

- `PlugIns/OpenIn.appex`
- `PlugIns/Reynard Helper.appex`

扩展丢失会导致打开文件、Gecko 进程或其他浏览器能力失效。LiveContainer 受其进程和应用扩展
模型限制，不属于受支持方案；使用分发证书重签也存在 entitlement 和扩展兼容限制。

## 在 GitHub Actions 从源码构建

1. 打开本仓库的 **Actions** 页面。
2. 选择 **Build unsigned IPA from source**。
3. 点击 **Run workflow**。
4. 工作流成功后，可在 **Releases** 下载 bot 自动发布的 IPA，也可在该次运行的
   **Artifacts** 下载 `Reynard-source-unsigned-<运行编号>`。

工作流会按顺序执行：

1. 校验中文资源并运行不依赖 Gecko 的纯 Swift 下载安全测试。
2. 根据 `engine/release.txt` 下载指定 Firefox 源码并应用 `patches/`。
3. 从源码构建 idevice 静态库和 iOS Gecko。
4. 使用真实 `Reynard` Scheme 构建 `Reynard.app`，并设置
   `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO` 和
   `AD_HOC_CODE_SIGNING_ALLOWED=NO`。
5. 检查主程序、`Info.plist`、两个应用扩展、GeckoView、XUL 和 Frameworks 后，生成标准
   `Payload/Reynard.app` IPA。

IPA 文件名格式为 `Reynard-<版本>-<提交短 SHA>-unsigned.ipa`。推送到 `main` 或手动运行时，
成功产物通常创建 `build-<运行编号>` 预发行版；推送 `v*` 标签时创建同名正式 Release。
维护者明确标记 `[formal release]` 的主分支提交也会在真实 IPA 校验通过后发布中文版正式版。
发行说明会明确标记未签名限制。Pull Request 默认只运行快速检查；需要按需验证完整包时，可在
PR 标题中加入 `[build ipa]`，但 PR 构建不会创建发行版，以防未合并代码取得发布权限。
旧的上游 AltStore 元数据刷新工作流只允许手动运行，不会再被每个中文构建发行版触发，也不会
干扰 IPA 的自动发布状态。

## 本地源码构建

需要 macOS、Xcode、Python 3、Rust/Cargo、`cbindgen 0.29.1`、支持
`wasm32-wasi` 的 LLVM/Clang 与 LLD（Apple Clang 不包含该目标时可使用 Homebrew LLVM/LLD）、
与 Gecko 版本匹配的 WASI sysroot 和 compiler-rt，以及足够的磁盘空间。GitHub Actions
会从对应的 Mozilla 工具链任务取得并缓存 WASI sysroot 与 compiler-rt。
克隆仓库后运行：

```bash
git clone --recursive https://github.com/xytxg/reynard-browser-zh.git
cd reynard-browser-zh
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
./tools/development/build-idevice.sh
./tools/development/build-gecko.sh
./tools/release/build-unsigned-app.sh
version="$(awk -F ' = ' '/^CURRENT_VERSION = / { print $2; exit }' browser/Configuration/Reynard.xcconfig)"
sha="$(git rev-parse --short=7 HEAD)"
./tools/release/create-unsigned-ipa.sh dist/Reynard.app "dist/Reynard-${version}-${sha}-unsigned.ipa"
```

正常的开发签名构建仍可直接在 Xcode 中打开 `browser/Reynard.xcodeproj`，选择 `Reynard`
Scheme。源码构建脚本不会读取或上传 Apple ID、证书、Provisioning Profile 或密码。

## JIT 与安装方式

Gecko 的正常性能依赖当前安装环境允许 JIT。TrollStore 和部分越狱环境可提供更稳定的 JIT；
AltStore、SideStore 或个人证书安装是否能启用 JIT，取决于 iOS 版本、配对服务和当前权限。
“已经安装”不等于“JIT 已启用”，请以应用内 JIT 状态为准。

## 下载与隐私改进

- 按日期清理只删除命中日期范围的已完成下载，不会清空全部记录或删除进行中的任务。
- 服务器文件名会移除路径分隔符、控制字符和双向文本控制符，限制 UTF-8 长度，并验证最终
  路径仍在 Downloads 目录中。
- 下载失败会显示网络、空间不足、权限或文件保存错误；普通 URLSession 下载可以重试。
- 下载确认会显示文件名、来源域名、大小和 MIME 类型；未知大小会明确显示。
- 下载进度界面合并为约 350 毫秒一次刷新，完成和失败仍立即更新。
- favicon 请求会合并同一站点的并发任务、拒绝非 Web URL，并限制压缩图片解码后的最大尺寸。
- 私密标签页、选择状态、导航历史和缩略图不写入会话数据库；升级后会清理旧版遗留的私密
  标签数据。
- “设置 → 主页 → 恢复上次浏览”关闭后会移除已保存的普通标签和导航状态。

## 当前限制

- Gecko 捕获下载接口目前不提供可靠的 Resume Data，因此没有伪造暂停状态；普通下载失败可
  重试，但 Gecko 捕获下载需要网页重新发起。
- 当前普通下载仍使用前台 `URLSession`。在没有验证任务重关联、目标路径恢复和 Gecko 捕获
  兼容性前，不会声称支持系统终止后的后台续传。
- GitHub 托管 macOS Runner 首次构建 Gecko 会很慢，并可能因磁盘、六小时任务上限、上游下载
  或缓存大小失败。工作流会保留实际日志，不会生成空 IPA。若持续超过托管 Runner 限制，建议
  使用至少 100 GB 可用空间的 self-hosted macOS Runner。
- Gecko 对部分网站权限或 iOS 能力没有可用接口时，Reynard 不会提供无效开关。

## 常见构建失败

- Firefox 标签下载失败：检查 `engine/release.txt` 和上游网络状态。
- 补丁冲突：查看 `dist/logs/apply-patches.log`；CI 会直接失败，不会等待交互输入。
- Gecko 构建超时或磁盘不足：查看 `disk-*.log`，清理 DerivedData/对象缓存或改用 self-hosted Runner。
- Xcode 构建找不到 XUL/GeckoView：确认 `build-gecko.sh` 已成功完成且对象目录没有混用不同 Xcode。
- IPA 校验失败：检查 `Reynard.app/PlugIns`、`Frameworks` 和签名元数据；脚本不会上传不完整或
  带签名的包。
