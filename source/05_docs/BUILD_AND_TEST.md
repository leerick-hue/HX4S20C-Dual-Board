# 构建、测试与跨目录复现

当前交付固件为板一 **8EB7D133**、板二 **6F5DD197**，两板均已通过用户实板验收。固件位于 `00_firmware_current`，完整工程和验证数据位于 `01_board1`、`02_board2`。

## 工具与依赖

使用 Windows、Python 3、TD **6.2.168116**（EG4S20BG256 器件库）、ModelSim **10.3c**。主机工具使用 Pillow、pyserial；媒体编码使用 FFmpeg；JPEG 独立参考检查使用脚本指定的 GCC/C++ 编译器。

```powershell
py -3 -m pip install Pillow pyserial
```

包内收录实际使用的 RTL、加密 IP、IP 配置与测试 C 模型。厂商仿真模型的安装路径和哈希见 `07_dependencies/REQUIRED_VENDOR_MODELS.json`。

## 隔离复现入口

`04_tools/portable_runners.py` 将板卡工程复制到新工作目录，并解析包内依赖及工具路径。依赖包含对端通信 RTL、conditioner.mem、相册夹具、测试卡前缀与 JPEG C 模型。

```powershell
$env:HX_TD_ROOT = 'E:/TD/TD'
$env:HX_MODELSIM_BIN = 'E:/Modelsim/modelsim_ase/win32aloem'
py -3 04_tools/portable_runners.py --doctor
py -3 04_tools/portable_runners.py --job board1-unit --workdir E:/HX_TEST_B1
py -3 04_tools/portable_runners.py --job board2-link --workdir E:/HX_TEST_B2_LINK
```

每项任务使用一个包目录之外的新工作目录，建议使用短路径。`--doctor` 校验两块固件、252 个构建输入、包内依赖及已安装厂商模型；注释修订通过原始哈希、当前哈希与代码内容摘要关联。

| job | 用途与验证范围 |
|---|---|
| board1-unit | 周期与手势边界，加速计时，48,076 条检查 |
| board1-album | 相册、PCM、周期和 UART 集成，功能模型与加速定时 |
| board1-ui / board1-infrared | 按键 UI 与 NEC 控制链路 |
| board2-link | UART 回执、重试与对端协议 |
| board2-jpeg | JPEG RTL 与独立 C 模型样本比较，最大通道容差 8/255、平均 1.2 |
| board2-video | 完整视频链路，仿真扇区服务与 SDRAM 功能模型 |
| board2-rate | 换帧时序采集，稳态数据由 audit_rate.py 汇总 |
| board2-coexist | 视频、语音采样与命令共存，识别事件由仿真注入 |
| board1-build / board2-build | 完整综合、布局和布线 |

```powershell
py -3 04_tools/portable_runners.py --job board1-build --workdir E:/HX_BUILD_B1
py -3 04_tools/portable_runners.py --job board2-build --workdir E:/HX_BUILD_B2
```

板一使用 seed11、carry-min5；板二使用 seed45、area_prior、min_ripple_len12。当前构建入口为两板各自的构建脚本与 build.tcl，生成产物按对应流程完成校验和验收。

## 媒体与运行参数

板二源视频为 640×480、15fps，HDMI 为 1280×720@60Hz，原生窗口左320、上120；软件仿真稳态换帧间隔约 66.7ms。300 张 JPEG、原视频、编码脚本、预览与卡镜像均已收录。

新素材使用新目录生成。`build_media.py` 所需工具可配置为包内 `04_tools/media_tools`、本机 FFmpeg 及 `07_dependencies/old320_prefix.img`。该前缀用于媒体制作和测试；板二运行使用完整配套镜像 `03_media/board2_480p15/CARD_BBB_20s_640x480_15fps.img`。

板一使用照片/音频相册卡，`03_media/board1_examples` 提供示例素材及制作工具。两板同时运行时各使用一张卡。

当前用户实板验收依据见 `06_validation/USER_ACCEPTANCE_20261103.json`。所有文件由包根目录 `MANIFEST.json` 和 `SHA256SUMS.txt` 校验。
