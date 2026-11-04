# 板二视频与语音实现及验证

当前固件 **6F5DD197** 提供 640×480 JPEG 视频播放、INMP441 麦克风采集、三类语音模板注册与可靠板间命令传输，已通过用户实板验收。

## 视频数据通路

播放器、video_source 与 video_path 组成视频通路。RGB565 帧缓存每银行为 153600 个 32 位字，双银行共 1228800 字节；像素按 JPEG 坐标写入，每组 BL4 包含四个相邻字。HDMI 采用 1280×720@60Hz 时序，640×480 画面居中显示。

配套素材为 20 秒静音视频，共 300 帧，时间戳按 `3200*i` 推进。300 个 JPEG 均通过 profile 与软件解码检查，卡镜像 payload 与源 JPEG 逐字节一致。媒体数据预算平均约 620KB/s、峰值约 753KB/s。

## 软件验证结果

- 样本 0、149、230、299 在 40MHz RTL 下各连续解码两次，覆盖输入间隔、输出停顿及 307200 个像素的唯一坐标。
- 独立 C 参考比较采用最大通道差 8/255、平均差 1.2 的容差；完整显示链路采用 RTL 解码像素作精确参考。
- 功能回归覆盖 16 个完整 720p 帧、14745600 像素，以及四次银行切换、地址覆盖、字内容、BL4 组织、前台银行保护、窗口、暂停恢复与循环。
- 连续速率回归完成六次换帧及 22 个完整 720p 帧、20275200 像素。仿真包含每扇区 0–50μs 启动延迟和 360ns 字节间隔，解码到可提交约 20.30–22.83ms。
- 稳态 swap2..6 的四个间隔均约 66.6666ms，对应 15.000015fps，稳态统计的 drop/underrun/late 均为零。定义及数据见相应 `qualified_rate.json`。

完整视频仿真使用实际 JPEG、FIFO、加密 SDRAM 控制器与物理引脚 BL4 功能模型。整机共存仿真覆盖 1048 个 I2S/PCM/诊断 UART 样本、三个训练键、四次 115200 UART/ACK 命令、ACK 重试与去重，以及视频帧提交和 HDMI AXIS 输出；识别事件采用仿真注入。

## 构建结果

构建采用完整综合、布局与布线流程，参数为 seed45、area_prior、min_ripple_len12。Slow/Fast 分析覆盖 8 个时钟，STA 覆盖率 99.99%，setup +0.200ns、hold +0.021ns。

资源为 LUT 15901、寄存器 11041、LE 17831、BRAM 56、DSP 28、PLL 2。构建 stage 为 `b1f3e879a7`。

位流 SHA256：`6f5dd1975f1776dd7ae1815c7a236df9faad3b7c26cb7a1d59a1fd1205f32a42`。

构建与发布脚本校验工具结果、源码指纹、setup/hold、时钟、覆盖率、报告、位流与媒体输入。验收见 [当前状态](ACCEPTANCE_UPDATE.md)，构建与仿真数据索引见 `DELIVERY.json`。

## 复现入口

```powershell
py -3 media/check_rtl_samples.py
py -3 sim/run_480p_video.py
py -3 sim/run_480p_video.py --rate
# 汇总本次速率运行的稳态区间数据：
py -3 sim/audit_rate.py <本次rate480日志目录>
py -3 sim/run_coexist.py
py -3 build.py
py -3 publish_480p.py
```

跨目录运行使用包根目录 `04_tools/portable_runners.py`，详见 `../05_docs/BUILD_AND_TEST.md`。新媒体集合在新目录中通过 `build_media.py` 生成。
