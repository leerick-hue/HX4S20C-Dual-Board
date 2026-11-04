# GitHub 同类项目交付结构参考

2026-11-03 实际查看以下仓库根目录与 README。仅参考文件组织与复现说明的覆盖范围，没有把其他项目代码改作本工程成果，也没有执行上传。

| 仓库与已查看目录 | 本包采用的交付做法 |
|---|---|
| [ultraembedded/FPGAmp](https://github.com/ultraembedded/FPGAmp)：gateware、firmware、scripts、docs、bitstreams、README、LICENSE、.gitmodules | 当前位流与完整工程分开，记录外部依赖及构建入口 |
| [nand2mario/nanospc](https://github.com/nand2mario/nanospc)：src、工程文件、scripts、verilator、doc、COPYING | 打包源码之外，还包括工程配置、媒体制作脚本、仿真和使用说明 |
| [ultraembedded/core_jpeg](https://github.com/ultraembedded/core_jpeg)：src_v、c_model、docs、README、LICENSE | 一并保留本项目使用的本地JPEG源码、独立C参考与许可证 |

可复核的目录数据入口：[FPGAmp](https://api.github.com/repos/ultraembedded/FPGAmp/contents)、[nanoSPC](https://api.github.com/repos/nand2mario/nanospc/contents)、[core_jpeg](https://api.github.com/repos/ultraembedded/core_jpeg/contents)。查看时文件名、Git blob/tree SHA 与链接摘要保存在 `09_package_audit/GITHUB_DIRECTORY_SNAPSHOTS.json`。

本包提供完整 SHA256 清单、源码与固件及测试报告的关联校验、隔离复现入口，以及完整构建与仿真资料。目录结构围绕本项目的使用、复现和文件查验进行组织。
