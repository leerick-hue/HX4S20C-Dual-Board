# 板一相册实现与验证

当前固件 **8EB7D133** 提供五档相册等待时间、本地按键操作、红外控制与板间语音命令接收，并已通过用户实板验收。

## 周期与手势控制

- 等待时间为 1 / 2 / 5 / 10 / 30 秒，默认 1 秒；自动轮播默认关闭。
- 实物 KEY4/C1（逻辑 `key2`）短按松开切换轮播，长按约 1.2 秒切换一档。KEY2/B2 为下一张，KEY3/B1 为模式键。
- 周期计算使用 64 位无符号常量；40MHz 下计数宽度为 31 位，100MHz 参数下为 32 位，覆盖 30 秒档位。
- 按键手势按相册模式进行管理；达到长按阈值后执行切档，短按执行开关切换。
- 周期调整、轮播开关与远程 SET 统一管理计时起点，远程 SET 具有明确优先级；手动 NEXT 通过请求队列参与加载调度。

## 数据通路与验证

相册集成采用实际 BMP 解析、1280×720 等比像素参考、RGB565 FIFO/DMA、帧交换、淡入与共享 PCM 通路，并覆盖周期键、UART、UI 与 NEC 控制。

周期单元验证通过 48,076 条检查，覆盖五档计数、加载边沿、消抖、长按阈值、模式切换、暂停恢复及同时事件。集成结果按各任务的源码与测试输入哈希关联。

## 构建结果

构建参数为 seed11、carry-min5。Slow/Fast 分析覆盖 10 个时钟，STA 覆盖率 99.96%，setup +0.582ns、hold +0.004ns。资源为 LUT 9867、寄存器 7801、LE 10999、BRAM 39、DSP 6、PLL 3。

位流 SHA256：`8eb7d133a6c5b3f1bacbfa363553d99f14f219d491439fc8a9bf655582d147d9`。

验收见 [当前状态](ACCEPTANCE_UPDATE.md)，构建与测试数据索引见 `DELIVERY.json`。包内源码注释修订具有独立哈希及代码内容一致性校验。

## 复现入口

```powershell
py -3 sim/run_period_unit.py
py -3 sim/run_period_integration.py
py -3 tools/build_video.py --name album_period_seed11 --seed 11 --carry-min 5
py -3 publish_period.py
```

跨目录运行使用包根目录 `04_tools/portable_runners.py`，详见 `../05_docs/BUILD_AND_TEST.md`。
