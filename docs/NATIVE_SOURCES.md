# 原生播放器源码与构建资料

当前发布包使用 ohpm 的 `@ohos/ijkplayer@2.0.11`，ARM64 动态库未经 Lumen 修改。为方便取得相应源码和保留许可，本次 Release 除应用源码外，另提供：

[`Lumen-1.0.1-native-sources.tar.gz`](https://github.com/xxz-0308/lumen-harmony/releases/download/v1.0.1/Lumen-1.0.1-native-sources.tar.gz)

该归档的 SHA-256：

```text
1169d72c868dba765f3ff665fa51391ff0de152967e2d700b70cbfe1d51171e4
```

机器可读的版本、来源与分组件归档校验值见 [native-sources.json](native-sources.json)。所有源码归档保留各自版权、许可与构建文档，不包含 Git 历史或开发者的 SDK / 签名资料。

## 固定的来源

| 组件 | 版本 / 上游分支 | 源码修订 |
| --- | --- | --- |
| OpenHarmony ijkplayer | 库模块 2.0.11 | `fe669dc75fbcfad5c6adc854fc4d6a2869c394c8` |
| OpenHarmony FFmpeg | `ohos-n8.0` | `69c05840d1d5412007e50beb94c8508015e51d4f` |
| SoundTouch | `ijk-r0.1.2-dev` | `6bf39cd3bf6b0c156267d12446b0d6bdcfcd53c2` |
| libyuv | `ijk-r0.2.1-dev` | `a0c7dd3e4b095649881f39152655437b8cde1589` |
| 原生构建工具与 FFmpeg 8 配方 | `tpc_c_cplusplus` | `c64d7253e6c8b05f5022721cf30e51b4738e02c9` |
| OpenSSL | 官方 `openssl-3.4.3.tar.gz` | 官方 3.4.3 发行源码；归档 SHA-256 见 JSON 清单 |

播放器源码版本是从上游历史中按模块版本 2.0.11 定位的，其 13 个 ArkTS 接口文件与发布 HAR 一致。其余组件版本依据该版播放器的构建说明和分发的原生库配置整理；这不是二进制逐字节可复现的保证。

## 使用源码包

1. 解开外层归档，阅读 `README.txt` 和 `SOURCE_MANIFEST.json`。
2. 解开各个组件 tar，保留各自 LICENSE / COPYING / NOTICE 等文件。
3. 自行取得有权使用的 HarmonyOS / OpenHarmony Native SDK，配置本机的编译器、sysroot 和输出前缀。
4. 按 `ijkplayer/README.md`、其 `doc/` 文件以及 `build-tools/lycium`、`build-tools/thirdparty/ohos_ffmpeg-ff8.0` 中的构建说明生成依赖库，再编译播放器。
5. OpenSSL 使用所附 **3.4.3 官方源码及其 INSTALL 文档**；不要将旧的 OpenSSL 1.1 配方当作该版本配方。需要针对自己的 Native SDK 配置交叉编译参数。
6. 按播放器文档准备 FFmpeg / OpenSSL / SoundTouch / libyuv 的产物目录，构建自己的 HAR。Lumen 可改为依赖该本地 HAR，然后使用自己的签名重新打包安装。

源码包是供修改、检查许可和重新构建使用的资料，不是无需 SDK、直接运行即可得到同一二进制的安装器。SDK、签名证书、Profile 和私钥均需使用者自行取得；项目不提供或限制访问个人签名密钥。

默认构建 Lumen 无需手动编译这些原生组件：`ohpm install` 会按 lockfile 安装上游 HAR。只有需要修改 / 重建播放器，或检查其源码与许可时才需要这个额外归档。
