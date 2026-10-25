# button-keys

手柄按键 → Mac 键盘按键。绑定表预先覆盖全部 **17 个物理按键**，未绑定的写 `nil`，后续加需求只改一张表。

开源仓库：<https://github.com/wujiang1999/vibe-coding-with-a-gamepad>（英文 README 与设计说明在 `README.md` / `docs/DESIGN.md`）。

## 当前绑定

| 手柄 | 键盘 | 状态 |
|---|---|---|
| Y | Esc ⎋ | ✅ 已绑定 |
| B | Delete ⌫ | ✅ 已绑定 |
| X | 左 Option ⌥ | ✅ 已绑定 |
| A | Enter ↩ | ✅ 已绑定 |
| LT（Left Trigger，模拟量过 0.5 算按下） | 鼠标左键（按住可拖动） | ✅ 已绑定 |
| RT（Right Trigger，模拟量过 0.5 算按下） | 鼠标右键 | ✅ 已绑定 |
| LB / RB | — | 未绑定 |
| **左摇杆** | **指针移动**（两轴，死区 + 加速曲线） | ✅ 已启用 |
| **右摇杆** | **滚动**（上下 + 左右两轴） | ✅ 已启用 |
| 十字键 上下左右 | — | 未绑定 |
| 左/右摇杆按下 | — | 未绑定 |
| Menu / Options / Home | — | 未绑定 |

摇杆位移派生的 `Left/Right Thumbstick Up/Down/Left/Right` **故意不在表里**：阈值低到 0.13，容易误触发。

## 构建与运行

```bash
./build.sh            # 生成 ./button-keys
./button-keys         # 常驻，Ctrl+C 退出（退出前会释放按键）
./button-keys --verbose   # 未绑定的按键也打印，调表时用
./button-keys --selftest  # 走同一条发送路径敲一次 Option+Enter，验证权限
```

首次运行需要「辅助功能」权限：系统设置 → 隐私与安全性 → 辅助功能，勾选运行它的终端。
若改由 launchd 自启，要给 `button-keys` 二进制单独授权，然后重启该 launchd 任务。

**二进制一旦重新编译，授权即失效**（签名/cdhash 变了）。所以正常使用期间不要再 `./build.sh`：
改绑定只改同目录 `bindings.json`，然后 `kill -HUP $(pgrep -f 'work/gamepad/button-keys/button-keys')` 热重载。

## 常驻（launchd，已配置）

- 任务：`art.wujiang.gamepad-button-keys`，plist 在 `~/Library/LaunchAgents/art.wujiang.gamepad-button-keys.plist`
- 日志：`~/Library/Logs/gamepad-button-keys.log`（退出/重启都追加写，不覆盖）
- `RunAtLoad` + `KeepAlive`：登录自启，进程被杀或被崩溃后 5 秒内自动拉起

```bash
launchctl print gui/$(id -u)/art.wujiang.gamepad-button-keys   # 看状态与 pid
launchctl kickstart -k gui/$(id -u)/art.wujiang.gamepad-button-keys  # 重启
launchctl bootout gui/$(id -u)/art.wujiang.gamepad-button-keys       # 停止并移除（plist 留着，下次登录仍会启动，除非删 plist）
tail -f ~/Library/Logs/gamepad-button-keys.log                 # 观察按键
```

注意：**重新 `./build.sh` 后二进制签名变化，辅助功能授权可能失效**；若日志重新出现「缺少「辅助功能」权限」，
到面板里把 `button-keys` 删掉重新添加，或每次开发时改为在终端里跑（终端已授权即可）。

## 摇杆当鼠标

左摇杆推杆方向 → 指针位移方向；推得越满越快，松手立即停（不是匀速漂移）。右摇杆同理，但输出的是滚动事件，
上下推 = 垂直滚动，左右推 = 水平滚动。指针坐标用所有显示器的并集裁剪，不会移出屏幕。

手感参数在同目录 `pointer.json`（启动时缺失会自动生成），改完 `kill -HUP $(pgrep -f 'button-keys/button-keys')` 生效，**不需要重编译**：

| 参数 | 当前值 | 作用 |
|---|---|---|
| `deadzone` / `scrollDeadzone` | 0.15 / 0.18 | 死区，抵消摇杆漂移 |
| `exponent` / `scrollExponent` | 1.7 / 1.5 | 加速曲线，越大越"慢起步" |
| `maxSpeed` / `maxScroll` | 1600 pt/s / 1400 px/s | 推满时的峰值速度 |
| `maxStep` | 0.05 s | 单帧步长上限，卡顿后不会瞬移 |

要点：

- 指针移动发的是 `mouseMoved`；按住 LT 时改发 `leftMouseDragged`，所以"按住 LT + 推左摇杆"就是拖动。
- 滚动用 `scrollWheelEvent2Source(units: .pixel)`，单位是像素，触控板级别的手感。
- 手感全部走 `pointer.json` + SIGHUP，不重编译就不会触发授权失效。

## 加一个绑定

1. 在 `bindings` 里把 `nil` 改成键名，例如 `"Button B": "escape"`。
2. 键名不在 `keyCodes` 里就加一行，值是要用的物理键码（`CGKeyCode`，与键盘布局无关）。
3. 修饰键（option/shift/command/control/capslock/fn）会自动登记 flag，按住期间后续按键都带该修饰。
4. 值写成 `mouse:left` / `mouse:right` / `mouse:middle` 时，该键发鼠标按键而不是键盘键。

想让一个键发组合键（如 Cmd+C），当前最小版只支持"一个手柄键 = 一个键盘键"；
组合键需要给同一元素配多个动作，属于下一步的配置化版本。

## 行为与限制

- 按下发 keyDown、松开发 keyUp；按住不放不会自动连发。
- 按住 X 期间 Option 持续按下，此时再按 A 得到的是 Option+Enter，这是修饰键的正常语义。
- 启动时会先给已绑定的键各发一次 keyUp，清掉上次异常退出可能残留的修饰键状态。
- 手柄断开、Ctrl+C、SIGTERM 都会先释放所有按住的键，避免修饰键卡死。
- 系统「安全输入」字段（密码框）会拦截合成事件；这是设计如此。
- Enter 用的是主键盘 Return（0x24）；小键盘 Enter 是 `keypadenter`（0x4C）。

## 实测记录（2026-10-25）

- `--selftest` 在目标窗口观测到 `KEYDOWN code=36 mods=option`：Option 按下后，Enter 事件确实携带 Option 修饰，
  说明两个绑定与修饰键状态机都工作正常（Return keyCode 36 = 0x24）。
- 设备侧：`BEITONG A1N3 XINPUT GAMEPAD`（Xbox 档案，34 元素）；B/X/Y 的 0/1 边沿事件此前已实测。
- 00:27–00:34 launchd 实例日志里观测到真实按键链路：`Button A → enter 按下/松开`、`Button X → option 按下/松开`。
- 00:41 该实例重启后日志重新出现「缺少「辅助功能」权限」——对应 00:30 的重编译。处置见上文：面板里重新勾选 `button-keys`，再 `launchctl kickstart -k`。
- 08:19 指针实测（100ms 采样光标坐标）：向右推住 0.74s 位移 +906px（1219 pt/s），向上推住 0.52s 位移 -689px（1317 pt/s），
  另一轴恒定为 0，到屏幕边缘正确夹住；当时峰值设定 1400 pt/s。
- 08:21 / 08:26 鼠标键实测：LT 记录 4 次左键按下/松开，RT 记录 5 次右键按下/松开（右键菜单可见）。
- 滚动实测：右摇杆上下/左右均触发 `scrollWheelEvent`，目标窗口滚动正常。
- 手感复查后峰值调整为 `maxSpeed 1600` / `maxScroll 1400`，曲线参数未变。
- 已知坑：新起的进程调用 `GCController.controllers()` 可能拿不到已连接的手柄（探针实测为空），
  只有长期运行的守护进程能持续收到事件；因此功能都做在服务的 tick 循环里，不另起进程。
