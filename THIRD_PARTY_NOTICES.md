# 第三方代码与许可

本文件说明 Lumen 的参考来源、构建依赖及 Release 中的原生播放器组件。项目自身采用 GPL-3.0-or-later；第三方代码保持各自原许可，不因本项目的许可而被重新授权。

## Simple Live

- 项目：[xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live)
- 归属：xiaoyaocz / Simple Live 贡献者；上游许可文档包含 2023–2025 的作者署名。
- 许可：GNU GPL v3 或后续版本。
- 使用方式：Lumen 的功能与平台协议实现参考该项目，以 ArkTS 重写及适配 HarmonyOS；不声称是上游的官方 HarmonyOS 版本。
- 本仓库保留 [GPL 许可文本](LICENSE)，并以兼容的 GPL-3.0-or-later 发布项目源代码。

## @ohos/ijkplayer 2.0.11

- 来源：[CPF-ApplicationTPC/ohos_ijkplayer](https://gitcode.com/CPF-ApplicationTPC/ohos_ijkplayer)
- ohpm 包：`@ohos/ijkplayer@2.0.11`，具体包完整性校验见 `entry/oh-package-lock.json5`。
- 对应上游版本源码：[`fe669dc75fbcfad5c6adc854fc4d6a2869c394c8`](https://gitcode.com/CPF-ApplicationTPC/ohos_ijkplayer/tree/fe669dc75fbcfad5c6adc854fc4d6a2869c394c8)。其库模块版本为 2.0.11，与 HAR 的 13 个 ArkTS 接口源文件逐个一致。
- 许可：LGPL v2.1 或后续版本。包中标注 Copyright (C) 2024 Huawei Device Co., Ltd.；保留 [许可副本](LICENSES/ijkplayer-LGPL-2.1.txt)。
- 基础项目：[bilibili/ijkplayer](https://github.com/bilibili/ijkplayer)，对应作者和版权声明保留在上游源码中。
- Lumen 不修改发布 HAR 内的播放器库；应用通过 XComponent / N-API 调用其动态库。

## 原生库涉及的组件

下列来源按该版播放器上游的构建说明整理。Release 另附第三方源码包，包含相关源码、原始版权 / 许可文件及构建资料；具体固定修订号与 SHA-256 见 [源码说明](docs/NATIVE_SOURCES.md)。

| 组件 | 上游版本 / 来源 | 许可说明 |
| --- | --- | --- |
| FFmpeg | [ohos_ffmpeg / ohos-n8.0](https://gitcode.com/CPF-ApplicationTPC/ohos_ffmpeg/tree/ohos-n8.0) | FFmpeg 项目主要为 LGPL-2.1-or-later；启用某些模块会改变许可要求。本包没有 `--enable-gpl` 或 `--enable-nonfree` 构建选项。以源码中的各文件声明、COPYING 文本及实际构建配置为准。 |
| SoundTouch | [bilibili/soundtouch / ijk-r0.1.2-dev](https://github.com/bilibili/soundtouch/tree/ijk-r0.1.2-dev) | LGPL-2.1-or-later，原声明随源码包保留。 |
| libyuv | [bilibili/libyuv / ijk-r0.2.1-dev](https://github.com/bilibili/libyuv/tree/ijk-r0.2.1-dev) | BSD 类许可及各文件声明，LICENSE / PATENTS 随源码保留。 |
| OpenSSL | [OpenSSL 3.4.3](https://github.com/openssl/openssl/releases/tag/openssl-3.4.3) | Apache-2.0，许可文件随官方源码归档保留。 |
| LLVM / libc++ | HarmonyOS SDK / [OpenHarmony LLVM 项目](https://gitcode.com/openharmony/third_party_llvm-project) | Apache-2.0 with LLVM exceptions 等上游许可；编译器 / 系统开发环境由使用者自行取得，未随本仓库提供 SDK。 |

### 修改播放器与重新构建

1. 取得 Release 所附源码包，以及自己有权使用的 HarmonyOS / OpenHarmony SDK。
2. 按源码包中的播放器 README / doc 和第三方构建脚本编译目标架构的动态库。
3. 将修改后的库整理为本地 HAR，并调整工程依赖；重新编译 Lumen。
4. 使用自己的开发者签名安装。项目不会提供私钥，也不限制使用者以自己的配置修改、重新构建客户端及播放器。

此处固定了源码获取来源，但不承诺与上游二进制进行逐字节可复现构建。对外再分发时仍需自行保留版权声明、许可和相应源码，检查自己启用的编解码器与构建选项；不要把“包标注 LGPL”当作所有依赖或所有配置都许可相同的依据。

## 开发辅助工具

`tools/verify/package-lock.json` 固定了 Node 开发依赖；这些依赖不打包进 HarmonyOS 应用：

- [esbuild](https://github.com/evanw/esbuild)：MIT。
- [ws](https://github.com/websockets/ws)：MIT。

包管理器会提供相应的原始 LICENSE。GitHub 上不提交 node_modules。

## 系统框架、图标与界面截图

HarmonyOS / OpenHarmony、ArkUI、UIDesignKit 和系统符号由各自权利人提供，使用其 SDK 时适用对应条款。Lumen 的分层应用图标与 ArkTS 界面资源保留在仓库中。

截图展示客户端界面，其中的游戏图标、平台名称、封面和其他第三方内容属于对应权利人，只用作项目界面演示，不代表商业授权、平台合作或官方身份；软件许可证不重新授权这些内容。

## 不包含的内容

公开仓库及 Release 不包含个人签名证书 / 私钥、设备绑定的 Profile、账号 Cookie / 令牌、用户数据库、私有开发历史、抓包 / 调试日志或 SDK 安装包。未签名 HAP 仍需要使用者自行签名才能在符合条件的设备上安装。
