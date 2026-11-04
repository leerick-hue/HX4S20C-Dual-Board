# 8EB7D133 + 6F5DD197 接线依据

当前双板采用下表引脚约束。具体排针、麦克风、红外接收头和矩阵键盘说明见 [详细接线表](WIRING_INHERITED.md)。

| 当前工程约束 | SHA256 |
|---|---|
| `01_board1/src/user_source/constraints_source/pin.adc` | `7b44b3437592da07bd3068a0f186eaeaba766d3929503774187a7b7c0ec53e6d` |
| `02_board2/src/pin.adc` | `5594d89153d1f0b63f220a05a554edc0425a5886995eb5101c5d83b5f2e02e0d` |

板间仍为命令TX、ACK回路及共地，115200/8N1；板二电脑诊断音频串口为1Mbps，两者不同。

板一相册周期操作使用**实物 KEY4/C1**（代码逻辑 key2），实物 KEY2/B2 是下一张；板二 KEY2/3/4 是三类语音模板注册键。按板卡分别识别，不按逻辑信号名推断实物键号。
