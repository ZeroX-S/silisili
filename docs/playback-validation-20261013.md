# 2026-10-13 播放与锁屏控制回归

本轮在 `native-pip-overlay` / `f419885` 的未提交修改上继续，保留此前
5.0 SDK、二维码兼容及首页滑动优化。下文先记录发布前的测试轮次，最终
1.58 发布包的身份和复测结果见文末。

## 本轮修复

- 所有视频启播在当前文件、起点和首帧纹理确认后才放行音频，加载时按暂停
  保留用户意图；硬解首个目标帧不等待被暂停的音频时钟。
- 暂停时定位仍处理 seek、投喂并呈现目标帧，随后继续保持暂停。待显示帧携带
  定位序号，旧序号帧不能进入新的定位。
- 真机抓到适配层在 flush 返回后仍交付旧回调：从 90 秒回到 14 秒时，旧
  90 秒输出被标记成新定位并冻结画面。现在先校验首帧目标时间及正常投喂的
  1.5 秒领先窗口，再标记目标已解码；迟到旧时间线帧不会阻断新目标解码。
- 新增标准 MPRIS 服务 `org.mpris.MediaPlayer2.silisili`，与 PlaybackSession
  共用播放/暂停、停止、定位、倍速、音量及媒体信息。锁屏显示标题和控制按钮；
  有封面时发布 artUrl。直播声明不可定位，速率范围固定 1；没有伪造上一/下一条
  队列能力。停止或退出后释放服务。
- 更新 CMake、qmake、手工 VM 编译入口及源文件验证，防止新组件漏打包。
- VM 增量编译在复制前比较源码内容，源文件和直接包含的头文件发生变化时
  保留旧对象到 `.previous` 并重编译；头文件变化同时重建 MOC，避免主机/VM
  时钟差导致陈旧对象被当作新对象。

## 包与设备

- 设备：Pixel 3a XL / bonito / Sailfish OS 5.2.0.16 / aarch64。
- boot ID：`70375c04-f814-4707-8df6-711ee7a3deab`。
- 连接：Mac → MeeGo Build → USB RNDIS → SSH `192.168.2.15:22`。
- SDK：`SailfishOS-5.1.0.11-aarch64`。
- NEVRA：`silisili-native-devel-1.1.0-1.57.scrolltest1.aarch64`，开发包同号重构建。
- 最终 RPM SHA-256：
  `410d8cd93e626d6979644af50c512de3728d0048f3e961655fb53037c2d75b5b`。
- 安装前校验 SHA/NEVRA、RPM 预检；安装后及退出回归后 `rpm -V` 通过。
- 稳定包未安装，本轮未改变稳定包身份。原播放同步测试包另存为
  `baseline-silisili-native-devel-1.1.0-1.57.scrolltest1.aarch64.rpm`，SHA 为
  `d827c8db4ee99cf70d7e1809ab356709e96fcec25487fdcf1d3a3422be0c9217`。
- RPM、脚本、完整构建/安装/运行日志和新截图统一保存在工程外
  `outputs/playback-validation-20261013/`。
- 完成后以普通入口重新启动首页（PID 9920），确认环境没有测试开关，
  空闲 Cover 只显示 Logo 与水印、操作禁用，MPRIS 服务不存在，包校验通过。

## 已通过的真机检查

| 场景 | 证据 |
| --- | --- |
| 普通硬解启播 | 当前源首帧发布在音频放行之前，后续帧持续增长 |
| 强制软解启播 | 相同启播屏障通过，帧序号持续增长；重绘计数不当作解码 FPS |
| 历史续播 | 从 14 秒目标启播，首帧后放行音频 |
| 加载中暂停 | pendingIntent=true，首帧就绪时 audioReleased=false，之后可正常继续 |
| 暂停前后定位 | 90 秒目标帧 PTS=89.9 秒；返回 14 秒目标帧 PTS=13.9 秒；音频仍暂停 |
| 倍速 | MPRIS 设置 1.25 倍、恢复 1 倍，状态回读一致 |
| 完整画质矩阵 | 360P/480P/720P/1080P/1080P60 请求值与解析值一致，六次加载均先首帧后音频 |
| 1080P60 横屏长播 | 同 PID 连续 60 秒，12 次五秒采样均前进；66 个约一秒视频呈现窗口最低 55 FPS，低于 45 的窗口为 0 |
| 前后台 | 同 PID 两次完整往返，Cover 视频帧前进，恢复后有画面 |
| 系统小窗 | Cover 按钮切换、真实视频输出、物理拖动及位置日志 |
| 小窗存在时退出应用 | 退出前 PiP visible=true，退出后窗口/播放均 false，23/23 硬解缓冲引用平衡，MPRIS 服务释放 |
| 应用内小窗 | 物理拖动改变位置；点击关闭后 active=false、playing=false、mediaKind=none，MPRIS 服务释放 |
| 锁屏 | 实际截图出现 SiliSili 标题和播放/暂停按钮；物理点击触发 MPRIS toggle，播放状态正确切换 |
| 直播 | 房间 6963590 硬解首帧后放行音频、持续出帧；暂停/恢复、不可定位、速率范围为 1、单次媒体加载 |
| 首页分页异常 | 仅应用内注入第二页请求失效，64 次继续 loadMore 未卡住，显式刷新在同进程恢复；未断开系统 Wi-Fi |

截图是本轮手机实际截取，另有输入处理日志和状态变化佐证。画面帧时间检查
独立于音频位置检查；早期 `mpris-verified.log` 曾出现“音频位置正确、目标
视频仍为旧帧”的情况，该迭代不能算定位通过，最终以 `mpris-final.log` 为准。
帧率结论只针对本次 60 FPS 视频、手机及测试区间，不保证任意视频/网络下的 FPS。
本轮不构成 5.0 真机、UHD 硬解或所有账号接口的全面验证。

## 构建故障记录

旧 SDK 和部分构建目录的访问时间异常到了 2121 年。32 位 SDK 的 stat 因
2038 时间范围溢出而失败，表现为 su Critical error、Permission denied 和
Value too large；随后 Scratchbox 缓存目录还导致交叉编译器映射失败。
任务脚本 `repair-sdk-atime.sh` 仅修正指定 SDK、工具链、目标、Scratchbox
和本任务构建目录的访问时间，保留源码修改时间，未修改 PAM 或系统安全策略。
最终成功构建使用正常 sdk-chroot，日志为 `build-final-seek.log`。

## 本地检查

```sh
node native/tests/home-scroll-smoke.js
node native/tests/playback-start-gate-smoke.js
bash vm-deploy/scripts/verify-silisili-native-source.sh
git diff --check
```

源码契约及抽象条件组合只作为静态检查，不能替代上述真机证据。

## 1.58 发布包复测

用户要求发布后，将 Release 更新到 `1.58`，补正 MPRIS DesktopEntry 为
`cn.silisili.native`、声明 QtDBus 运行时依赖，并纳入可独立使用的 VM 构建脚本。
发布 RPM 为 `silisili-native-devel-1.1.0-1.58.aarch64.rpm`，SHA-256 为
`b3b7d9010ce64524fc1167fed4271c60553520ad4ab866d59b716eee20025325`。

该精确 RPM 已在同一 5.2 设备安装，重跑完整画质矩阵、普通硬解启播、暂停
前后定位、倍速、锁屏状态及物理点击，并完成横屏 1080P60 连续 60 秒复测。
66 个约一秒窗口最低 51.7413 FPS，低于 45 的窗口为 0。查询 DesktopEntry
与安装的 desktop 文件匹配，RPM 校验干净。

首次在矩阵之后运行锁屏测试时播放会话已变为空闲，媒体服务不存在，该次
中断不计通过；重新冷启动后上述锁屏/定位复测通过。发布包证据保存在
`outputs/release-1.58/`，原候选包及较早测试日志继续保留。
