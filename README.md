# HX4S20C 双板项目

基于 HX4S20C 的双板相册、视频播放与语音控制系统，包含配套固件、完整工程、媒体资源、工具和使用说明。

## 功能

- 板一：照片相册、1 / 2 / 5 / 10 / 30 秒五档轮播等待时间、相册伴音、按键与红外控制。
- 板二：640×480 视频播放、1280×720@60Hz HDMI 输出、麦克风采集与三类语音模板注册。
- 板间通信：支持下一张、暂停相册、继续相册命令，具备 CRC、回执、重试与重复命令管理。
- 当前固件：板一 **8EB7D133**，板二 **6F5DD197**。
- 两板已于 **2026-11-03** 通过用户实板验收。

## 源码入口

完整交付目录已放入 [source](source/)，可直接浏览或克隆。

| 内容 | 入口 |
|---|---|
| 板一 HDL 源码 | [01_board1/src](source/01_board1/src/) |
| 板一周期控制 | [sd_card_bmp.v](source/01_board1/src/user_source/hdl_source/SD/sd_card_bmp.v) |
| 板二 HDL 源码 | [02_board2/src](source/02_board2/src/) |
| 板二语音与通信 | [02_board2/src/voice](source/02_board2/src/voice/) |
| 板一仿真 | [01_board1/sim](source/01_board1/sim/) |
| 板二仿真 | [02_board2/sim](source/02_board2/sim/) |
| 使用与接线说明 | [05_docs](source/05_docs/) |
| 构建与测试说明 | [BUILD_AND_TEST.md](source/05_docs/BUILD_AND_TEST.md) |
| 工具与依赖 | [04_tools](source/04_tools/) · [07_dependencies](source/07_dependencies/) |
| 组件许可与素材署名 | [08_licenses](source/08_licenses/) |

```powershell
git clone https://github.com/leerick-hue/HX4S20C-Dual-Board.git
cd HX4S20C-Dual-Board/source
py -3 04_tools/verify_bundle.py --strict
```

## 下载与使用

在 [Releases](https://github.com/leerick-hue/HX4S20C-Dual-Board/releases/tag/v1.0.0) 中下载完整 RAR 交付包及对应 `.sha256` 文件。

按 [交付说明](source/README.md) 开始使用。固件下载采用 **PROGRAM_SRAM、5MHz**，两板同时运行时各使用一张配套 TF 卡。

组件许可与素材署名按 `source/08_licenses` 及对应组件原有声明执行。
