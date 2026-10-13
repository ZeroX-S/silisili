# 播放启动音画同步（2026-09-06）

## 原因与修改

普通零秒启播原来不启用 `m_initialPositionGatePending`，只有历史续播等
非零位置启动才等待目标首帧。独立 DASH 音轨因而可以先开始，而页面仍等待
视频纹理；音频与硬解视频走不同的准备链路。

- 所有启用视频的加载都等待：当前文件已加载、起点已确认、当前源首帧纹理
  已就绪。纯音频路径不增加视频依赖。
- 零秒起播不增加 seek，也不先放音频再重新定位视频。
- 等待期间的内部暂停不覆盖用户暂停意图；加载和播放状态不能提前绕过屏障。
- 硬解展示线程对每轮启动/定位的首个目标帧不等待音频时钟。否则暂停的音频
  时钟与首帧会互等；首帧之后仍按正常音频主时钟控制速度及丢弃迟到帧。
- 测试页可通过 `SILISILI_NATIVE_TEST_SOFTWARE_VIDEO=1` 强制走软解；必须同时
  设置非空 `SILISILI_NATIVE_TEST_PAGE`，正常启动不受影响。

这里的“首帧”是当前源纹理发布，不等同于屏幕已经完成一次物理扫描显示。
网络解析、下载和设备负载仍会影响启动耗时，不能承诺所有视频均小于 2 秒。

## 自动检查

```sh
node native/tests/playback-start-gate-smoke.js
node native/tests/home-scroll-smoke.js
bash vm-deploy/scripts/verify-silisili-native-source.sh
sh -n vm-deploy/scripts/probe-silisili-native-play-start.sh
git diff --check
```

Node 启播检查包含源码契约和 48 个抽象条件组合，并不执行真实 C++ 解码器。
真机脚本 `probe-silisili-native-play-start.sh` 需以 root 执行，只停止本应用，
通过正常 invoker 启动，支持 `zero`、`history`、`software`、`matrix`、
`fullscreen` 模式及画质编号参数。它会实际播放测试视频并产生观看历史，
唤醒/解锁屏幕，不改变桌面、网络或系统服务。无 Wayland 连接时拒绝测试。
完整画质矩阵必须出现 complete 标记，且每次加载均有先首帧后音频的证据。

## 本轮设备验证

- 设备：bonito / Sailfish 5.2.0.16 / aarch64。
- boot ID：`296709f1-c626-403a-93b9-935562a5d835`。
- SDK：SailfishOS-5.1.0.11-aarch64；这是 5.1/5.2 测试包，不是 5.0 包。
- NEVRA：`silisili-native-devel-1.1.0-1.57.scrolltest1.aarch64`。
- 本轮同版本号开发重构建 SHA-256：
  `d827c8db4ee99cf70d7e1809ab356709e96fcec25487fdcf1d3a3422be0c9217`。
- 安装前校验 SHA/NEVRA、RPM 预检；安装后 `rpm -V` 通过，未改变稳定包身份。
- 构建/安装/测试日志在工程外 `outputs/play-start-test/`；旧包仍在
  `outputs/scroll-test/`，SHA 为
  `5c50101ebf50442897da2827e09cae1031785bf8c7a2aa7f6bb716d2d31fa4e1`。

| 场景 | 实测证据 | 结果 |
| --- | --- | --- |
| 1080P 硬解零秒启动，PID 55895 | 首帧后放行音频，约 0.941 秒；后续帧序号 61/121 | 通过 |
| 强制软解零秒启动，PID 49803 | 首帧后放行音频，约 0.999 秒；后续帧序号持续增长 | 通过 |
| 14 秒历史续播，PID 50242 | 确认目标 14 秒、首帧后放行音频，约 1.604 秒；持续出帧 | 通过 |
| 连续画质切换，PID 50671 | 360P/480P/720P/1080P/1080P60 均有 step ready，六次加载均先首帧后音频 | 整轮中断，未通过完整矩阵 |

耗时从播放器提交加载算起，不包含点击到 URL 解析的时间；帧序号增长不是
目测结果，软解重绘计数也不能当作独立解码 FPS。

矩阵结尾出现 QSGRenderThread SIGABRT。同一时刻系统日志出现停止 Lipstick，
随后 `lipstick.service` 为 inactive、正常退出码 0，`/run/display/wayland-0`
消失；下一次启动报 Failed to create display。没有可用 core（系统未接受
rich-core 隐私提示，未擅自启用）。不能据此确定是本次播放器回归，也不能
忽略该退出并宣称全部通过。没有擅自重启桌面服务。

用户随后确认另有业务同时调试此手机。本轮停止真机操作，未重启桌面、
终止其他业务或尝试抢占显示资源；矩阵中断保留为环境冲突下的未完成测试。

待桌面恢复后：重新执行完整画质矩阵、独立 1080P60 长播、暂停/继续、定位、
横屏及前后台、小窗/Cover 和直播回归。5.0 外部设备仍需另外验证。

2026-10-13 已继续完成该批真机回归，并修复暂停定位及迟到旧帧问题、加入
锁屏媒体控制。最终包与结果见 [本轮回归记录](playback-validation-20261013.md)。
