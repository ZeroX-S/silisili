# 1.57 首页滑动卡顿：优化与回归边界

## 问题与修改

基线 `f419885`。本次修改保留工作区已有的 5.0 SDK / 二维码兼容改动。

- 首页原先在卡片创建、按压、滑动结束、恢复前台时准备隐藏视频。
  `prepareVideo -> resolve -> loadSourceWithAudio` 会启动实际硬解码，
  更换目标又在 GUI 线程进入 `codec_stop / join / glFinish`。
- 首页现在只在静止 350ms 后预取中心卡片的播放地址；拖动、页面非前台、
  列表加载、已有播放时不发起预取。点击仍走正常播放入口，使用相同缓存。
- `PlaybackSession::prepareVideo` 只委托元数据预取，不改变播放器、当前解析器
  或播放状态；删除隐藏解码状态、首帧接管分支及旧测试页的隐式预播放。
- 元数据请求最多同时 2 个；缓存最多 16 条、5 分钟有效，清理过期数据。
  新的显式解析清除上一轮等待预取的标记，维持最新请求序号保护。
- 解码器工作线程在完成回调、队列设置和 `codec_start` 后才发布
  `m_startedCodec`。停止线程只读取该原子指针，不再读取正在初始化的
  `m_codec`；创建过程检查取消，发布后再次检查取消。
- 推荐首页、直播列表、搜索结果先完成错误/数据/页号状态更新，再通知加载结束，
  避免同步 QML 回调在中间状态触发分页。搜索失败后等待用户主动重试。

## 不能混淆的边界

- 网络 API 仍是异步；网络超时不是 GUI 同步等待的耗时上限。
- 本轮没有把整个播放器改为异步销毁。真实播放的切源、退出仍可能等待
  OMX/GPU/工作线程回收；不能将本次改动宣称为所有播放路径零卡顿。
- 保留解码器停止后再 join、join 后销毁、GPU 缓冲释放顺序，未采用 detach、
  超时后直接释放资源等可能造成悬空指针的方式。
- 官方 [droidmedia 实现](https://github.com/sailfishos/droidmedia/blob/master/droidmediacodec.cpp)
  的 stop 本身包含编解码器停止及内部线程等待；源码中的停止调用并非异步完成通知。
- 构建和源码检查不等于真实设备流畅度通过；原来的 `sf50test1` 日志只能证明
  隐藏视频反复启动，不能给出本次用户报告的卡顿时长。

## 无设备回归

在仓库根执行：

```sh
node native/tests/home-scroll-smoke.js
bash vm-deploy/scripts/verify-silisili-native-source.sh
git diff --check
```

Node 测试执行 HomePage 的实际 JavaScript 策略函数，检查静止/拖动/后台/
播放中/加载中/空视口和重复分页通知。附加源码契约防止隐藏解码、无界预取、
错误通知顺序回归，并枚举原子发布/取消握手的六种顺序。
这些测试不加载 Silica，不模拟真实 OMX，不是 FPS 或触摸响应测试。

## SDK 构建注意事项

本轮主线验证使用 `MeeGo Build` 的 `SailfishOS-5.1.0.11-aarch64`，测试
release 为 `1.57.scrolltest1`，不替换已有的 5.0 专用测试 RPM。
使用独立的 `/home/builder/silisili-scroll-test-*` 构建目录和
`outputs/scroll-test` 输出目录；第一次必须 `REUSE_OBJECTS=0`。

现有工作区 `work/vm-build-native-rpm.sh` 要求输出目录中预先存在 ARMv7
音频兼容 shim。自定义输出目录时，先在 VM 内从当前源码编译它，不能依赖
默认输出目录的旧文件：

```sh
arm-linux-gnueabihf-gcc -march=armv7-a -mfloat-abi=softfp \
  -fPIC -fvisibility=hidden -nostdlib -nodefaultlibs -shared \
  -Wl,--hash-style=both -Wl,-soname,libminimedia-audiosource-shim.so \
  "$PROJECT_ROOT/packaging/apps/silisili-native/minimediaservice-audiosource-shim.c" \
  -o "$OUTPUT_DIR/libminimedia-audiosource-shim.so"
```

`PROJECT_ROOT` 与 `OUTPUT_DIR` 应设置为 VM 内已经确认的源目录和输出目录。
若只有该文件缺失导致打包失败，完整编译/链接已成功，并且源码、头文件、SDK、
编译参数与 release 均未变化，可以补编 shim 后以相同路径
`REUSE_OBJECTS=1` 重跑包装脚本。不要跨 SDK 或 release 复用目标文件。

## 真机回归要求（尚待执行）

本轮无设备检查和 SDK 构建已通过。产物为
`outputs/scroll-test/silisili-native-devel-1.1.0-1.57.scrolltest1.aarch64.rpm`，
12,566,492 字节，SHA-256：
`5c50101ebf50442897da2827e09cae1031785bf8c7a2aa7f6bb716d2d31fa4e1`。
应用 ABI 上限实测 GLIBC 2.34 / GLIBCXX 3.4.30，不能用于 5.0 设备验证。
同目录 `build.log` 和 `validation.md` 保存构建与核验记录。

1. 冷启动首页，连续快速/慢速滑动各 60 秒、往返刷新、切后台再恢复。
   在未点击播放时，硬解码 generation 不得增长，不得出现隐藏媒体 load。
2. 网络正常、断开、切换、超时/业务错误后主动刷新；错误期间不得自动循环请求。
3. 单列/双列；推荐/热门/搜索/直播分页；检查追加页号和条目去重。
4. 点击已缓存和未缓存视频，记录真实点击至首帧耗时，不能提前解码后再启动计时。
5. 初始化中快速退出/换视频；验证无旧帧、无后台残留音频、进程不重启。
6. 点播/直播、各可选画质、历史续播、快进、倍速、全屏、应用内小窗、Cover、
   系统 PiP 及关闭回收。保留当前 PID/日志区间，至少使用操作标记与状态变化
   两项证据；不使用视觉模型，不将截图完整性当作视觉通过。
