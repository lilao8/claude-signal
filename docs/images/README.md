# Screenshots / 截图

- `demo.gif` — the notch light cycling working → permission → done → error → off.
- `states.png` — each state on the notch outline and the menu-bar dot.

How they were made: real captures on an M5 Pro MacBook Pro, driving the light by writing
session files to `~/.claude-signal/sessions/`. `demo.gif` is a `screencapture -v` region
recording converted to GIF with AVFoundation + ImageIO (the menu-bar dot is cropped out of
it because macOS puts its screen-recording indicator in that slot while recording);
`states.png` is stitched from still captures. A plain dark strip was placed under the
menu bar during capture so no unrelated window content shows. Screen captures don't
include the physical camera notch, so its silhouette is drawn in black at the position
NSScreen reports.

制作方式：在 M5 Pro MacBook Pro 上实拍，通过写入 `~/.claude-signal/sessions/` 下的会话文件驱动灯的状态。
`demo.gif` 是 `screencapture -v` 区域录屏，用 AVFoundation + ImageIO 转成 GIF（录屏时 macOS 会把录屏指示器
放在菜单栏圆点的位置，所以 GIF 里裁掉了圆点）；`states.png` 由静态截图拼成。拍摄时在菜单栏下方垫了一条纯色
深色窗口，避免带进其他窗口的内容。截图不包含物理摄像头刘海，因此按 NSScreen 报告的位置用黑色画出了刘海轮廓。
