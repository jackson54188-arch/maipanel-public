# MaiPanel 外框 + 串流示例

maimai 手台 App 的公开示例：照着机台的真实几何画出圆盘外框，并把电脑推来的
JPEG 串流解码显示在顶部条和圆盘里。

- 画的是真机布局：34 区圆盘、8 个外键、读卡器卡片、三角键、顶部广告牌，
  尺寸比例和完整版一致。
- 作为 TCP 服务端监听 `24870`（1P）/ `24880`（2P），连上后自动请求视频流，
  收到 `0x10` 帧就交给后台队列解码。
- 触摸、外键、灯光、读卡器文字、电脑端桥接、安卓版和游戏 Mod 都不在这个
  仓库里，完整版不开源。

## 目录

- `app/` — 示例 App（SwiftUI，XcodeGen 工程）
- `tools/` — 演示推流脚本和 12 帧合成画面
- `.github/workflows/build-ipa.yml` — 未签名 IPA 构建

## 构建

公开仓库的 macOS runner 免费、不限分钟数。打开 **Actions → Build unsigned
IPA → Run workflow**，跑完在该次运行页面下载 IPA：

- 在仓库里配了 `CORE_PAT` 秘密：检出私有完整版并构建，产物名
  **MaiPanel-unsigned**。
- 没有配置（包括别人 fork 的仓库）：构建本仓库的示例，产物名
  **MaiPanel-shell-unsigned**。

推送到 `main` / `master` 也会触发构建；产物保留 1 天。构建全程不签名，
不需要 Apple 账号或证书，侧载用 Sideloadly / AltStore，7 天过期后重新装。

### 私有完整版是怎么拉进来的

工作流用 `CORE_PAT` 检出私有仓库 `jackson54188-arch/MaiPanel_WoW`，把它放在
`core/` 里构建。PAT 的要求：

- Fine-grained token，**Only select repositories** 只勾私有仓库；
- **Repository permissions → Contents: Read-only**，别的权限都不给；
- 只存在仓库的 Actions secret `CORE_PAT` 里，不要写进任何文件或日志。

没有这个秘密时检出步骤会软失败（`continue-on-error`），工作流自动退回构建
本仓库的示例版，不会因为缺 PAT 而失败。工作流不使用 `pull_request_target`，
fork 的 PR 拿不到秘密。

## 在平板上看串流

1. 用上面构建的示例 IPA 侧载到 iPad（未签名）。
2. 电脑和 iPad 在同一 Wi-Fi，或者已经有 USB 端口转发到平板的 24870。
3. 运行：

   ```bat
   python tools\demo_sender.py 192.168.1.23 --slot 1
   ```

   地址换成平板的局域网 IP；`--slot 2` 对应 24880。脚本连上后会先报告
   自己是 1P/2P、请求画面，然后按 12 fps 循环发送 `tools/frames` 里的
   合成帧。
4. App 左上角显示「PC 已连接」，圆盘出现画面；断开后回到「NO SIGNAL」。

`tools/frames` 是用 `tools/make_frames.py` 生成的（需要 Pillow），画面是
540×960，顶部 23.4% 是名字条，圆盘中心和完整版用同一套比例，方便检查裁剪。

## 协议（示例用到的部分）

小端：

```
"MPNL" | version:u8 | type:u8 | length:u16 | payload
```

- `0x07` control：`[1, 1]` 开始镜像画面，`[1, 0]` 停止；`[2, slot]` 报告
  自己在 1P（1）还是 2P（2）。
- `0x10` video：一帧 JPEG，长度小于 65000 字节。
- `0x02` ping / `0x03` pong：保活。App 连上后每秒发一次 ping，收到就回 pong。

App 是 TCP 服务端，电脑主动连进来；连上后 App 先发 `[2, slot]` 和
`[1, 1]`。真实桥接程序还会发触摸、外键、灯光等帧，示例版直接忽略。

## 许可

MIT，见 [LICENSE](LICENSE)。
