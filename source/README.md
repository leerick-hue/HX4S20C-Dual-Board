# HX4S20C 双板完整交付（8EB7D133 + 6F5DD197）

本包包含两块已通过用户实板验收的固件、完整工程、配套媒体、制作工具与验证资料。验收日期为 2026-11-03，记录见 [用户验收记录](06_validation/USER_ACCEPTANCE_20261103.json)。

## 板一：相册与多方式控制

- 相册支持 1 / 2 / 5 / 10 / 30 秒五档停留等待时间，默认 1 秒；实际换图过程还包含加载、切换与淡入。
- KEY1 复位，KEY2（B2）下一张，KEY3（B1）循环切换相册、亮度、对比度、音量、音频条和音乐播放六种模式。
- 相册模式下，KEY4（C1）短按松开切换自动轮播，长按约 1.2 秒切换一档等待时间。复位后自动轮播关闭。
- 支持板载按键、手机红外及板二语音命令控制，配合照片显示与相册伴音。
- 使用板一配套照片/音频相册卡。

## 板二：视频播放与语音控制

- 配套源视频为 640×480、15fps、20 秒共 300 帧，采用 JPEG 解码与 RGB565 双帧缓存；HDMI 输出 1280×720@60Hz，画面居中于 x320/y120。
- 软件仿真稳态换帧间隔约 66.7ms，对应约 15fps。
- 支持 INMP441 麦克风采集、三类语音模板注册，以及带 CRC、回执和重试的板间命令传输。
- KEY2 注册“下一张”，KEY3 注册“暂停相册”，KEY4 注册“继续相册”。每次复位、重新下载或上电后注册三类模板：先安静 2 秒，松键约半秒后说出命令，说完安静至少 1 秒，三条录齐后开始识别。
- 视频素材为静音片段；配套镜像为 `03_media/board2_480p15/CARD_BBB_20s_640x480_15fps.img`。按裸扇区镜像整卡写入并校验，写入前备份卡内所需文件，确认目标为 TF 卡。两板同时运行时各配一张卡。

## 使用与校验

当前固件位于 [00_firmware_current](00_firmware_current/)，下载选择 BitWriter 的 **PROGRAM_SRAM、5MHz**。

接线见 [当前接线说明](05_docs/WIRING_CURRENT.md)，操作见两板各自的 DELIVERY/README.md。构建与测试入口见 [BUILD_AND_TEST.md](05_docs/BUILD_AND_TEST.md)，目录索引见 [CONTENTS.md](05_docs/CONTENTS.md)。

在包根目录运行：

```powershell
py -3 04_tools/verify_bundle.py --strict
py -3 04_tools/portable_runners.py --doctor
```

## 交付内容

`01_board1` 与 `02_board2` 提供完整板卡工程；`03_media` 提供媒体与示例；`04_tools` 提供校验和制作工具；`05_docs` 提供使用说明；`06_validation` 提供验证资料；`07_dependencies` 提供测试依赖；`08_licenses` 提供素材与组件许可；`09_package_audit` 提供来源、哈希和文本修订校验资料。

第三方组件与素材署名见 [许可说明](08_licenses/README.md)，目录组织参考见 [GITHUB_REFERENCE.md](05_docs/GITHUB_REFERENCE.md)。
