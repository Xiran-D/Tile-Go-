extends Control

# 独立菜单场景（menu.tscn）
# 单屏主菜单（所有对战选项都在一屏）：
#   标题「瓷砖围棋」
#   行1 棋盘：**静态平铺** —— 启用项全部并排铺进本行，每块在屏幕**只出现一次**。
#       ★★ 2026-10-16（用户口令「棋盘选项不需要滚动了，删掉」）：原先是**首尾相接的横向
#         循环行**（像一条传送带：右端滚出淡出、左端滚入淡入，选中项滑到"屏幕右侧焦点位"），
#         整族已退役（函数/成员/常量的完整名单见下方「棋盘行：静态平铺」那段墓碑）。
#       · 块尺寸与块间距读**全页统一真源** `_uni_box`（`_tile_uniform_box` / `_main_row_roster`）
#         —— 与下面三行**同一个尺寸**（用户口令「棋盘、大小、对战方式、开始按钮都统一成
#         现在棋盘行按钮的大小」）；
#       · 「当前选中的那一档」由**凹陷态**表示（与行2 同一套判据）。
#       2026-09-15：经典 19×19 网格盘下线（AI 位置先验对它有系统性劣势），
#       当前五项真棋盘（彭罗斯 / 立方体 / 筝形 / 雪花 / 爱因斯坦）+ 两项待开发占位。
#   行2 大小（普通盘 = 随机/标准/加强；爱因斯坦 = 帽子/海龟/幽灵）
#   行3 对战方式：本地 / 磐石 / 疾风 —— 三块**等大居中、并列互斥**（永远只有一块选中）。
#       ★ 2026-10-15b：「人机」改名「磐石」；且「磐石」「疾风」不再是"父档 + 标记"，
#         而是 `_sel_mode` 的两个**并列取值**（详见 `MODE_XGAI` 常量处的注）。
#   行4 开始（按当前选择直接进对局）
#   底栏 练习 / 棋谱 / 对弈 / 设置 —— 四个面板**共用同一份真源**，位置尺寸四页一致。
#   ⚰️ 2026-10-12（名字不许回收）：原「行3 = 选『人机』后简单/普通/困难三块与它等大、四块拼成
#      一个大菱形向右侧折叠」**整族删除**（用户口令「对战方式那里只留本地、人机两个选项，
#      人机默认最难，不需选择难度」）⇒ 本行回到"每块都是一个完整的对战方式"这个形状。
#   ⚰️ 2026-10-08：原「行4 = 选『线上』后邀请好友 / 随机匹配两块折叠长出」随"联机整体搬进
#      『对弈』页"删除 ⇒ 主菜单不再有「线上」档（`_sel_mode` 永不可能等于 `MODE_ONLINE`，
#      这正是 `_push_board_choice()` 里那条判据必须改读 `GameConfig.mode` 的原因）。
#   右上角**没有**常驻控件（2026-10-02：原齿轮已删）——
#       进设置 = 头部四入口的「设置」；设置页右上角则是一块**棋盘砖形状**的「返回」，
#       回主菜单（页面底部那颗原生「返回主菜单」仍在，两条路都通）。
# 交互：点击瓷砖 = 执行它对应的功能。
#       「当前选中的那一档」由瓷砖的**凹陷态**表示（2026-10-12 起"黑砖标记"整族删除，
#       理由与墓碑见下面 `TILE_RELIEF_BEVEL` 那一段注释）。

# ====== 常量 / 配色 ======
const TOP_MARGIN: float = 132.0       # 标题区高度
## 底部留白。原为底部提示文案（"选好棋盘与对手，点「开始」开局…"）预留，
## 提示已于 2026-09-15 移除，该空白暂时保留 —— 它是行带预算的分母之一，
## 调小会把纵向空间还给瓷砖（bandH 变大、菱形 R 变大），需同步重跑 `--labeltest`
const BOTTOM_MARGIN: float = 20.0
const BREATH_PERIOD: float = 2.0       # 呼吸描边一个完整脉动周期（秒）

# ====== 瓷砖的「立体感」：未选 = 凸起 / 已选 = 凹陷（2026-10-12）======
## ★★ 用户口令「立体感按钮，已选时有凹进去的感觉」+「已选按钮不要变黑，会看不清字」。
##
## 口径：**凹凸两态靠"内嵌斜面环"的受光方向反转**区分 ——
##   凸起（未选）：左上内侧**受光（亮）**、右下内侧**背光（暗）** ⇒ 边棱朝外翻出去；
##   凹陷（已选）：左上内侧**投影（暗）**、右下内侧**反光（亮）** ⇒ 边棱朝里陷进去，
##                 同时整块面**压暗**一档（"陷进阴影里"）。
## 这是经典浮雕按钮的语言：**不占额外空间、不换底色**，因此字色可以一直读常规墨色。
## 另叠一条「凸起态在砖下面画一截厚边」（`_tile_side_walls()`）把"整块砖浮在盘面上"做实。
##
const TILE_RELIEF_BEVEL: float = 0.20   # 内嵌斜面环宽度 = 砖半高 × 本值
## 斜面环宽度的**占比上限** —— 环比半高还宽就等于把整块面吃光（凹陷态退化成一块纯色）。
## ★ 它是"地板 `TILE_RELIEF_BEVEL_MIN` 不许在极小砖上反噬"的那道闸：设置页里有些按钮
##   比主菜单的小砖还小，地板比半高还大时没有它就会把面吃光（且 `⑩d` 的 `bevel < 半高` 会红）。
const TILE_RELIEF_BEVEL_MAX_FRAC: float = 0.45
const TILE_RELIEF_DEPTH: float = 0.12   # 凸起态厚边高度 = 砖半高 × 本值
const TILE_RELIEF_MIN: float = 3.0      # **厚边**的地板值（像素）：再小就看不出凸起
## 描边 / 呼吸发光的线宽 —— `_draw()` 里那两条 `draw_polyline` 的唯一真源。
## ★ 它们必须提到常量区来：**斜面环的可见性由它们决定**（见 `TILE_INK_REACH`）。
##   在此之前它们是写在调用处的字面量（3.0 / 2.5 / 7.0），判据读不到 ⇒ 只能由人肉记着。
const TILE_OUTLINE_W: float = 3.0
const TILE_GLOW_W_MIN: float = 2.5
const TILE_GLOW_W_MAX: float = 7.0
## 描边 + 发光**伸进砖内**的最大半径（`draw_polyline` 的线宽是**居中**的 ⇒ 一半朝内）。
## ★★★ 2026-10-12 真机截图像素取色实测：`立方体`（R≈29 ⇒ 半高≈21）的斜面环只有 3.94px
##   ⇒ **整圈被这两条墨迹盖掉**，那块砖在屏幕上一点凹凸都没有 —— 而 ⑩c/⑩d/⑩h **全绿**
##   （它们量的是 `poly` 与函数返回值，看不见"谁盖住了谁"）。
const TILE_INK_REACH: float = TILE_OUTLINE_W * 0.5 + TILE_GLOW_W_MAX * 0.5   # = 5.0
## 斜面环宽度的**地板**：必须比 `TILE_INK_REACH` 宽出至少 2px，否则环被墨迹吃掉 ⇒
## 立体感在"最小的那些砖"上退回不存在（`--menutest` ⑩n 直接断这一条）。
## ★ 它的上界由 `TILE_RELIEF_BEVEL_MAX_FRAC` 兜住（极小砖上地板会超过半高）。
const TILE_RELIEF_BEVEL_MIN: float = TILE_INK_REACH + 2.0                   # = 7.0
const TILE_FACE_DARKEN: float = 0.22    # 凹陷态面色的压暗幅度
## 斜面环/厚边从"面色"派生的两档明暗：亮边 = 面的提亮，暗边 = 面的压暗。
## ★ 都用 `Color.lightened/darkened` 从**当前面色**派生，不写死颜色 —— 换主题时自动跟着走。
const TILE_BEVEL_LIGHTEN: float = 0.30  # 受光边提亮幅度
const TILE_BEVEL_DARKEN: float = 0.42   # 背光边压暗幅度

# 页面编号
const PAGE_MAIN: int = 0
const PAGE_SETTINGS: int = 1
## 棋谱库页（2026-10-02 主菜单重设计）。★ 用**末尾追加**而不是插在中间 ——
##   `_page` 的值会进 `GameConfig` 之外的地方（判据、存档回放路径），插在中间会让
##   旧值含义漂移；追加则老值永远不变。
const PAGE_RECORDS: int = 2
## 联机大厅页（同上）。
const PAGE_LOBBY: int = 3

# 对战方式
## ⚠️ 这四个常量是 `_sel_mode` 的**取值域**，而 `_sel_mode` 是"此刻选中哪一块瓷砖"的**唯一真源**。
##   显示名（本地 / 磐石 / 疾风）**不在**这里 —— 走 `_mode_label()` 单一真源，别就地写字符串。
const MODE_VS_AI: int = GameConfig.VS_AI    # 菜单显示名「**磐石**」（2026-10-15b 前叫「人机」）
const MODE_LOCAL: int = GameConfig.LOCAL
const MODE_ONLINE: int = GameConfig.ONLINE
## 「疾风」档（2026-10-14 立项为「测试AI」，**2026-10-15 转正并定名"疾风"**）。
##
## ★★ 2026-10-15b **并列化**（用户口令「人机和疾风两个按钮逻辑有问题，改成并列的关系」）：
##   本常量从此是 `_sel_mode` 的一个**独立取值**，与 `MODE_LOCAL` / `MODE_VS_AI` 平级。
##   ⚰️ 改前它是"哨兵"：选中态 = `_sel_mode == VS_AI` **且** `_sel_xgai == true`，即
##      「疾风 = 人机 + 一个标记」的**父子关系**。症状是**看得见**的 —— 点「疾风」时
##      `_mode_tile_selected(MODE_VS_AI)` 也返回 true ⇒ **「人机」和「疾风」两块一起亮**，
##      玩家会以为"人机也被选中了"（那就是这条口令的由来）。`_sel_xgai` 已随本改动**退役**
##      （派生量 = `_sel_mode == MODE_XGAI`，别再加回来 —— 铁律 8：状态一处写一处读）。
##
## ★ 编号 100 = 菜单内部值，**仍永不写进 `GameConfig.mode`**（那里只收 LOCAL/VS_AI/ONLINE，
##   全工程 30+ 处 `game_mode == VS_AI`；且 Ludii 的编号 3 已墓碑不复用）。
##   ⇒ 折叠只发生在**下发边界**一处：`_sel_mode_for_config()`（疾风 ⇒ VS_AI）。
##   ★ 持久化仍走 `last_match.cfg` 的可选字段 `xg`（哨兵值不外泄进文件的 `mode` 字段）——
##     否则"选了它、下完棋返回菜单又变回磐石"，那就只是换了个名字的临时档。
const MODE_XGAI: int = 100
## 「流水」档（2026-10-22）：白方由**渗流引擎** `LiushuiAI`（`ai_engine_liushui.gd`）接管。
##
## ★ 与「疾风」**同构的并列取值**，不是 `VS_AI` 的子档 —— 理由全部照抄 `MODE_XGAI` 那一段：
##   · 编号 **101**（不与 100 撞，且不复用已墓碑的编号）；
##   · 同疾风一样**永不写进 `GameConfig.mode`**（那里只收 LOCAL/VS_AI/ONLINE，全工程 30+ 处
##     `game_mode == VS_AI`）⇒ 折叠点仍**只有** `_sel_mode_for_config()` 一处（流水 ⇒ VS_AI）；
##   · 下发标记走 `GameConfig.liushui_opponent`（bool，与 `xg_opponent` 平级）。
##     ★ 为什么是 bool 而不是把 `xg_opponent` 升级成档位号：`game.gd` 侧两个判定同形
##       （`xxx_play_mode = GameConfig.xxx_opponent and game_mode == VS_AI`），
##       升级成 int 会连带改 `xg_play_mode` 的三处读点与存档口径，收益为零。
##   · **持久化复用 `xg` 字段**（0=磐石 / 1=疾风 / 2=流水）：`last_match.cfg` 格式**一个字节不变**，
##     旧记录的 0/1 语义完全不动（铁律 §111：换口径要让新式在旧工况下退化成旧式）。
const MODE_LIUSHUI: int = 101
## 「野马」档（2026-10-23）：白方由**神经网络先验引擎** `YemaAI`（`ai_engine_yema.gd`）接管。
##
## ★ 与「疾风」「流水」**同构的并列取值**，不是 `VS_AI` 的子档 —— 理由全部照抄上面两段：
##   · 编号 **102**（不与 100/101 撞）；
##   · 同样**永不写进 `GameConfig.mode`**（那里只收 LOCAL/VS_AI/ONLINE）
##     ⇒ 折叠点仍**只有** `_sel_mode_for_config()` 一处（野马 ⇒ VS_AI）；
##   · 下发标记走 `GameConfig.yema_opponent`（bool，与另两个平级）；
##   · **持久化复用 `xg` 字段**（0=磐石 / 1=疾风 / 2=流水 / **3=野马**）：
##     `last_match.cfg` 格式一个字节不变，旧记录的 0/1/2 语义完全不动（铁律 §111）。
## ★ 「野马」与「流水」的区别只在**先验从哪来**：流水是渗流（离散调和测度），
##   野马是神经网络（17 维点级特征 + 手上这点权重）+ 磐石搜索读深。
const MODE_YEMA: int = 102

# 联机方式（线上模式下那一行；★ 第 5 步后剩「邀请好友」+ 2026-10-01 加回「联机大厅」两瓣）
const NET_INVITE: int = 0    # 邀请好友：Steam 建房拿房间号 / 输房间号加入
const NET_LOBBY: int = 1      # 联机大厅：浏览公开大厅、看昵称+胜率、点选加入（不再手输房间号）
## 左侧联机面板里「加入」按钮的**固定**宽度（面板总宽是算出来的，只有它写死）。
## ★ 为什么要拆成常量：`_fit_online_panel_children()` 用「内宽 − JOIN_BTN_W − 间隙」
##   反推输入框宽度；这个式子里的"按钮宽"是面板唯一**不随宽度变**的一维，拆出来才不会
##   出现"两个都在变的量互相减"（那种式子在收窄时会让输入框宽度反向增长）。
# ⚠️ 编号 1 原是「随机匹配（进撮合队列）」，2026-09-30 §24 第 5 步随自建联机删除。
#    ★ 编号**不复用**（与本工程 GameConfig 的棋盘编号同一惯例）：将来若加回第二档请用新编号，
#      免得旧日志 / 旧配置里的 1 被解释成别的东西。
#    ★★ 但 2026-10-01 加「联机大厅」时**只能复用 1** —— NET_RANDOM 这个符号已删，
#       留着的唯一"不解释错"的做法就是给新档一个不与旧日志撞含义的值；
#       本工程里 1 从未落进任何配置或存档（旧实现是 `_sel_netmode` 内存量、不持久化），
#       所以复用是安全的。这条注释就是这次复用的**依据**，不是免责声明。

# 棋盘类型
const BOARD_PENROSE: int = GameConfig.BOARD_PENROSE   # 彭罗斯密铺（非周期菱形密铺）
const BOARD_CUBE: int = GameConfig.BOARD_CUBE         # 立方体棋盘：3 块菱形拼正六边形、六边形排成蜂窝
const BOARD_KITE: int = GameConfig.BOARD_KITE         # 筝形棋盘：3 块筝形钝角相对拼等边三角形、三角形密铺
const BOARD_SNOWFLAKE: int = GameConfig.BOARD_SNOWFLAKE   # 雪花棋盘：Ammann-Beenker 密铺（45° 菱形 + 正方形桥）
const BOARD_HAT: int = GameConfig.BOARD_HAT             # 爱因斯坦棋盘（帽子家族：帽子/海龟/幽灵）——非周期单瓦片密铺，13 条有效边
# GameConfig.BOARD_GRID(1) = 经典 19×19 网格盘，2026-09-15 下线（AI 位置先验对它系统性不利），
# 编号不再复用 —— 详见 game_config.gd 的注释。

## 爱因斯坦（帽子家族）的三个种类。**菜单里「爱因斯坦」那一项的第二级不是尺寸行，而是这一行**：
## 三个种类都只做随机盘（约 200 格），所以原来那行 随机/标准/加强 对它没有意义。
## 值取自 GameConfig.HAT_*（= Tile(a,b) 的 a/b 取值），种类只换瓦片的两组边长，不动拓扑。
## ★ 2026-09-23：清单搬到了 `MenuModel`（两个菜单共用**同一份**数据层，见该文件头注释）。
## 这里保留同名常量**别名**，让本文件原有的几十处引用一行都不用改 ——
## 数据只有一份、名字不变，这比"全量改名"安全得多（改名要动几十处，漏一处就是静默错位）。
const BOARD_KINDS: Array = MenuModel.BOARD_KINDS
const HAT_KINDS: Array = MenuModel.HAT_KINDS

## 棋盘清单的**说明**保留在这里（清单本身在 `MenuModel.BOARD_KINDS`）：
## enabled=true 的项选中后向右折叠出二级菜单 —— **普通棋盘 = 大小三档（随机/标准/加强）；
## 「爱因斯坦」= 种类三档（帽子/海龟/幽灵）**；两种含义复用同一套折叠机制
## （同一 group 名、同样 3 个槽位），语义判据见 `MenuModel.slot_meaning()`。
## enabled=false 是**待开发占位**（灰红描边、点了弹「开发中」提示），只为把循环行撑满 ——
## 行里只有 2 项时循环滚动会出现左右相邻两块同名（"怎么有两个立方体"），占位块把周期拉长即可。
## ⚠️ 手机菜单不铺占位项（竖排列表没有循环周期问题）。

# 瓷砖标签排版：文字放在瓷砖「外侧」——主按钮置于上顶点之上，折叠子项置于远离折叠中心的一侧，
# 保证文字既不与瓷砖边缘线交叠，也不压住中心的黑子标记。
const LABEL_GAP: float = 4.0     # 文字与瓷砖边界的最小间距（像素）
## 锚点标签「朝折叠展开的反侧让位」时，让位后的文字近边与**折叠瓣近缘**之间要留的净空（像素）。
## ★ 为什么必须单列：折叠瓣的近缘**正好压在锚点中心**（O' = 锚点 + dir·(R,0)，瓣宽 2R）
##   ⇒ 标签只要还有一半探过锚点中心，就压在瓣的本体上。让位量因此必须由**文字宽度**定，
##   不能由"半宽的某个比例"定（比例不跟文字长度走，换字号/换文案就会静默压上）。
## ★ 2026-10-09：这里原有 `ANCHOR_AVOID_CLEAR`（锚点标签避让的净空），随"文字放进按钮内部"
##   整族删除 —— 没有文字挂在按钮外了，也就没有"让位后留多少净空"这回事。
##   ⚠️ 名字**不许回收**（同 `_gear_*` / `_back_*` 那一族的口径）。
## 文字画在按钮**内部**时，与按钮四边留出的内边距（像素）。太小会贴着描边，太大装不下长标签。
const BTN_TEXT_PAD: float = 8.0
## 按钮内文字的字号下限（像素）。窄视口下长标签会被压到这个字号为止，再小就不如不显示了。
const BTN_TEXT_FS_MIN: int = 12
## 菜单瓷砖之间的横向间隙 = 半径 × 该系数（行内多块并排时生效）。
## 纵向受行高硬约束（块的大小上不去），而横向有富余 → 这里是把"紧凑感"松开的主要手段。
## 演变：0.6（顶点仅隔 0.6R≈26px，贴成一团）→ 0.85 → 1.1（间隔约 1.1R，看着舒展）。
## 调大后整行更宽，注意 --labeltest 与折叠菜单的横向越界检查（--settest/labeltest 会兜）。
const TILE_GAP_RATIO: float = 1.1
## ====== 菜单按钮形状（2026-10-08 用户口令：抛弃菱形瓷砖 + 落子动效，改用规整圆角矩形）======
## ★★ 半高比 `menu_btn_h_ratio` **同时**是**纵向预算的分母**（`_tile_base_r()` 与 action 行各一处）：
##   它原先是**写死的字面量 0.73** —— 形状与预算各写一遍 ⇒ 只改形状不改预算，块会缩水而预算
##   照旧按 0.73R 留白（静默浪费）；反过来则静默重叠（本项目在这一处返工最多）。
##   收成一个真源、两边都读它之后，这个旋钮**才**是安全的（改完先看 `--labeltest` [行带] 净空）。
## ⚠️ 默认值 0.73 **不是**随手选的：它就是旧菱形的半高比，取它 ⇒ 新按钮与旧菱形**包围盒相同**
##   ⇒ 七百行布局判据照旧成立（见 `_make_btn_rect()` 的注）。
@export var menu_btn_h_ratio: float = 0.73    # 按钮半高 = R × 本值
## ★★ 2026-10-12 用户口令「改成左右两端半圆的矩形」= **胶囊形** ⇒ 默认值取 1.0。
##   语义：圆角半径 = `min(半高, 半宽)` × 本值。
##     · 1.0  → 圆角半径恰好 = 半高 ⇒ **左右两端各一个半圆**（胶囊，当前口径）；
##     · 0.34 → 圆角矩形（2026-10-08「规整圆角矩形」那一版的值）；
##     · 0.0  → 直角矩形。
##   ⚠️ 关键的一处放宽：上界从 `半宽/2` 改成 `半宽`。旧上界够不到胶囊 ——
##     `min(半高, 半宽/2)` 在 0.73 的半高比下恒等于半宽/2，再乘 0.34 只到半高的 0.34 倍，
##     **竖着永远拼不出半圆**（那正是旧口径画不出胶囊的原因，不是值调小了）。
##   ★ 保持本工程「数值一律运行期可调」的口径：改这一个数就让形状在"直角 → 圆角 → 胶囊"
##     之间连续变化，不必改代码。
## ★★ 2026-10-15：**作用面收窄了** —— 瓷砖（屏幕上的菜单块）改走 `_tile_poly()` 之后，
##   圆角取的是 `GameConfig.DIALOG_CORNER`（**绝对像素**，与新版全局按钮同一个常量，
##   用户口令「和新版全局按钮相同」）。⇒ 这个比值旋钮现在**只作用于判据自造的那几块假砖样本**
##   （`--menutest` ④/⑩c/⑩d/⑩h 的 `_make_btn_rect(…, R)`），**不再影响屏幕上的瓷砖**。
##   ⚠️ 想调**屏幕上**瓷砖的圆角请改 `GameConfig.DIALOG_CORNER`（那里同时管全局按钮，
##     这正是"形状相同"的兑现方式）；留这个旋钮是因为删 `@export` 会动编辑器旋钮面，
##     而那属于审美决策（铁律 11），留给用户拍 —— 见报告 §9.7。
@export var menu_btn_corner: float = 1.0       # 圆角半径 = min(半高, 半宽) × 本值（1.0 = 胶囊；★只作用于判据样本）
@export var menu_btn_corner_seg: int = 4       # 每个圆角的采样段数（≥1；点数 = 4×本值 + 2）
## 菜单瓷砖半径：由 行高 与 视口宽占比 两者取小（见 _tile_base_r）。
## 宽度项：视口宽 * ROW_WIDTH_RATIO / 7.7（本行 3 块并排 = 6R + 2*0.85R = 7.7R）。
## 原先半径被硬编码上限钉死（78）：块偏小、整行只占视口约 36%，这才是"横向紧凑"的主因。
## 高度项仍是最紧的约束（行带高约 167 → R≈52），故同时收紧了行带上下留白来释放高度。
const ROW_WIDTH_RATIO: float = 0.60
## 竖屏行带高度上限的余量系数（见 `_portrait_band_cap()`）：1.10 = 让宽度顶满之后
## 每边再留 ~10% 呼吸位。调到 1.0 时正好顶满（标签可能贴到上一行下顶点），别往下调。
const PORTRAIT_BAND_SLACK: float = 1.10
## 一行 3 块并排时的总宽系数：3 块本体(6R) + 2 个间隙(2*TILE_GAP_RATIO*R)。
## 由 TILE_GAP_RATIO 推导，改间距时不必再手改这里的数字。
const ROW_SPAN: float = 6.0 + 2.0 * TILE_GAP_RATIO
## 棋盘大小那三档的**折叠进度**（`_board_t` → `_board_target`）缓动时长（秒）。
const BOARD_FOLD_TIME: float = 0.35
## 行标题顶端留白（像素）。行标题从**行带内部顶端**起画，故这是相对行带顶的偏移。
const ROW_HEAD_TOP: float = 6.0
## 行标题文字底边与「本行瓷砖标签」顶边之间必须留出的净空（像素）。
## 这是**唯一**的碰撞判据：净空 < 0 就是行标题压到某块瓷砖的标签上，--labeltest 的 [行带] 会直接报出。
const ROW_HEAD_CLEAR: float = 6.0
## 行带底往上留出的呼吸位（像素）：块本体下沿与行带底之间至少留这么多，
## 免得下一行的行标题紧贴上一行的瓷砖下顶点。
const ROW_HEAD_PAD: float = 8.0
## 相邻两行之间的**显式行间距**（像素）—— 直接进 `_layout_setup()` 的行带高度预算：
##   `bandH = (bottom0 − top0 − ROW_ROW_GAP·(行数−1)) / 行数`
##
## ★★ 2026-10-16 语义升级（用户口令「间距稍微拉大一点」）：原先它只是「开始」行的
##   一道**下让保险**（防块下沿贴住下一行文字；一次实测 484.7 == 484.7 的产物），
##   行与行之间其实**没有任何显式间距** —— 行带首尾相接，视觉间距全靠 `_tile_base_r()`
##   的纵向余量**间接**给出。那个量拧不动（改它要动 `by_b` 公式）⇒ 行距根本拉不开。
##   现在把它提成**行距的唯一真源**，四行各扣一份 ⇒ 行距成为一个可以直接拧的旋钮，
##   而"块下沿别贴住下一行"这道保险自动包含在它里面（不必再额外 `× 0.5`）。
##
## ⚠️ 代价必须说清楚：视口总高是固定的，行距拉大 ⇒ 每行行带变矮 ⇒ 块略小。
##   实测（真窗口 1152×681）：`ROW_ROW_GAP` 0→14 时 `bandH` 106→100、`r_base` 38.5→34.5（−10%）；
##   同批把 `FOOT_BAND_H` 86→68（底部行带原先比块高一倍）补偿回一部分
##   ⇒ 净效果是"行距 +14px、块 −6px、底部多出一条呼吸位"，见那两个常量的注。
const ROW_ROW_GAP: float = 14.0
## 折叠大簇（选中块 + 三瓣子项）相对块中心的纵向伸出行程，单位 = R。
##
## 几何：上/下瓣中心在 O' ± (0, 半高比·R)，各瓣自身半高同为 半高比·R
## → 自块中心起算，向上可到 -2·半高比·R、向下可到 +2·半高比·R（1.46 = 2×0.73 即默认档）。
## ★ 1.46 **当前没有任何代码读它**（下面几处只是引用这条注释）⇒ 半高比改了它**不会**让行为出错，
##   但它会变成一个过期的记账数字 —— 真要用它时请改成 `2.0 * menu_btn_h_ratio`，别照抄 1.46。
##
## ⚠️ 这个值**只用于**判断折叠态会不会顶进相邻行，**不再**用来收块半径。
## 原因：行带高（真机 1152×720 时仅 130~173px）根本放不下「行标题 + 标签 + 1.46R」三段，
## 硬按它收半径会把块压到 R≈24（原先 52），块小到标签散不开、整行缩成一小团 ——
## 属于"为了消除一个只在展开态出现、且展开时行标题会淡出让位"的重叠，牺牲全部常态观感。
## 折叠态允许轻微越出行带（下方相邻行的行标题此刻已淡出，视觉上不冲突）。
## 瓷砖标签的字号。多处纵向预算公式要用，集中一处避免口径不一（原来到处硬编码 22）。
const TILE_LABEL_FS: int = 22
## 棋盘行的额外收缩系数。**已改回 1.0（不再收缩）**：
## 原为 0.82，理由是"棋盘行要向外折叠大小三档、需要更多横向余量"。
## 但实测（真机逻辑视口 1152×720，行带 167 → R=51.7）两边都不会越界：
##   棋盘行折叠最外缘 = 891，对战方式行折叠最外缘 = 891，而视口留白后上限是 1124 —— 尚有 233px 余量。
## 即 0.82 属于过度保守，代价是**两行半径不一致、左右边界对不齐**（棋盘行 348px / 对战方式行 424px，
## 用户明确反馈"棋盘和对战方式要对齐"）。取同一半径后两行完全对齐，行宽同时从 30% 提到 37%。
## 保留此常量（而非删掉乘数）是为了让"棋盘行是否要单独收缩"这件事有据可查、随时可调。
## 折叠大菱形（选中项 + 三瓣子项）向外伸出时，距视口边缘至少留出的余量。
## 选「人机」时难度三瓣向右侧伸出至 人机中心+3R，是最紧的情形；据此收缩半径避免出屏。
const ROW_EDGE_MARGIN: float = 28.0
## 折叠子项（棋盘大小三档 / 难度三档 / 联机方式两档）文字的额外「散开量」，单位 = 瓷砖半径的倍数。
##
## 为什么需要它：三块折叠瓣拼成大菱形后，标签统一朝同一侧平移，
## 于是「随机 / 标准 / 加强」三个标签挤成一个紧凑三角 —— 实测（1152×648 窗口）
## 相邻两标签水平只差 1 个 R（≈40px），而两字标签本身就有 44px 宽 → **水平方向是重叠的**，
## 垂直方向也只剩 3~4px 间隙，看起来就是糊成一片。
## 修法：让每个标签再沿「远离簇中心」的方向多走一小段（随机向上 / 标准朝外 / 加强向下 / 联机方式向左），
## 呈放射状散开。这样既增大了彼此间距，又保持了「文字在瓷砖外侧」的原有规则。
## 调大 → 散得更开；调到 0 → 退回旧排版。
## 取值权衡：0.40 能到约 65px（≈旧排版两倍），标签离本块瓷砖远了一圈但仍可辨对应，
## 用户要求「再大一点」后由 0.30 提到 0.40（联机方式也一并放宽，避免与上方大小菜单重叠）。
## 想再松/再紧直接改这个数即可，用 `--labeltest` 可以立刻看到量化结果。
const SUB_LABEL_SPREAD: float = 0.40


## 盘形在目标矩形内的内边距（占短边比例）。**唯一消费者是 `_shape_polys()`** ——
## 它按当前选择算一遍真实盘形，并等比缩放居中到 w×h。
##
## ★★ 2026-10-02：本常数原来叫 `PREVIEW_PAD_RATIO`，属于主菜单右下角的「棋盘预览卡」。
##   用户口令「既然已经有了背景棋盘效果，那就可以彻底删除棋盘预览了」⇒ 卡片（连同它的
##   让位几何、自检、内部类）整建制删除，**只剩首页背景密铺还在调这个比例** ⇒ 顺手改名。
##   为什么非得改名：「彻底删掉」的验收标准不是"屏幕上没了"，而是**源码里再也搜不到那个功能**
##   —— 留着一个叫 `PREVIEW_*` 的常数、或者一个叫 `_preview_shape_polys()` 的函数，
##   下一个人（或下一轮的我）会以为预览没删干净，于是去"修"一个不存在的东西。
##   ⚠️ 改名之前已全量 grep 过工具侧（`struct_guard.py` 的 MARKERS/CHECKS、`negctl_hovertest.py`
##   的 MUTATIONS 锚点）：**没有任何锚点落在这几个符号上** ⇒ 改名不会让阴性对照静默变 SKIP
##   （那是铁律 13⑰ 记过的坑：改名的代价只有一处 —— 锚点失配后那条判据**静默丢覆盖**）。
const SHAPE_PAD_RATIO: float = 0.06

var _bg_color := Color(0.07, 0.08, 0.11)
const MENU_TILE_COLOR := Color(0.40, 0.41, 0.45)  # 菜单瓷砖统一低调底色（与对局棋盘 board_tile_color 一致）
var _fat_color := MENU_TILE_COLOR
var _disabled_color := Color(0.55, 0.42, 0.42)  # 暂未开放瓷砖
var _accent := Color(0.96, 0.88, 0.62)          # 可点击瓷砖描边 / 高亮


# ====== 菜单项（独立瓷砖）======
# 每个元素：{ center, poly, label, cb, disabled, group, selected }
var _items: Array[Dictionary] = []
var _section_labels: Array[Dictionary] = []  # 设置屏各行的小标题（非点击）
var _row_label_y: Dictionary = {}            # { group: 行标题 y }，折叠展开后锚点标签落位用
## 最近一次 `_layout_setup()` 真正使用的行带高度与行带间距（竖屏收敛后 `_band_h` < 等分高度）。
## ★ 供 `_row_fit_test()` 报告与 `--portraittest` 断言读 —— **布局写、测试读**，
##   测试侧绝不自己再推一遍（本项目在"测试自己重算几何"上返工最多）。
var _band_h: float = 0.0
var _band_gap: float = 0.0
## 最近一次 `_layout_setup()` 真正采用的**全页统一瓷砖尺寸**（`_tile_uniform_box()` 的产物）。
## ★ 同 `_band_h` 一条纪律：**布局写、测试读**。四行内容 + 底部入口行都由它派生，
##   判据若自己再推一遍（`_row_radius` / `_row_fit` 那一支），量的就是另一种块宽 ——
##   这正是 2026-10-16 之前"判据读数与真机分辨率静默分叉"的老坑。
var _uni_box: Dictionary = {}
# ★ 2026-10-09：这里原有 `_board_sub_center/_board_sub_r/_diff_sub_center/_diff_sub_r`
#   四个「折叠簇中心」成员 —— 大小/难度两组都不再从锚点向外折叠，簇不存在了。
#   ⚠️ 名字不许回收（铁律 §18）：别拿这四个名字去装别的东西。
## ★★ 2026-10-04 v4：这里原有 `var _back_anim`（设置页右上角「返回」棋盘按钮的落子动画），
##   **整族已删**（`_back_anim` / `_back_tile_*` / `_draw_back_tile()` /
##   `_on_back_tile_pressed()` / `_back_tile_action()`）。用户口令「设置选项挪过来之后删掉
##   设置页的返回按钮」—— 设置现在是**主菜单的一个面板**，底栏那块「练习」就是回去的路
##   （原地可见、可点），再留一颗"返回"就是三份回去的路（底栏 / 这块砖 / ESC 退出）。
##   ⚠️ 名字**不许回收**：留着 `_back_*` 只会让下一个人去找一个不存在的东西。
##   ⚠️ 它当年不塞进 `_stone_anims` 的理由也一并作废：那本字典的键是 `_items` 下标，
##   而设置页 `_items` 为空（没有合法键）——**那条理由只在"设置是独立页"时成立**。
# ★ 2026-10-09：这里原有 `_diff_t` / `_diff_target` 两个「难度折叠进度」成员 ——
#   难度三档平铺进「对战方式」行、不再有长出/收回动画 ⇒ 进度没有生产者，整族删除。
#   ⚠️ 名字不许回收（铁律 §18）。
var _board_t: float = 0.0                     # 棋盘「大小」折叠进度：0 折叠(无) → 1 展开(随机/标准/加强 贴彭罗斯右侧)
var _board_target: float = 0.0               # 目标进度，由 _sel_board == BOARD_PENROSE 决定
var _board_pending: int = -1                  # 待切换的棋盘类型（彭罗斯↔立方体锚点不同）：先收回 → 收完换锚点 → 再展开
var _ip_edit: LineEdit = null                # 对弈页·好友联机档：房间号输入框
var _lobby_list_box: VBoxContainer = null    # 对弈页·公开大厅档：列表容器
var _lobby_status: Label = null              # 状态行（搜索中 / 空 / 条数 / Steam 不可用）
var _lobby_refresh_btn: Button = null        # 「刷新」
var _lobby_scroll: ScrollContainer = null    # 列表滚动区
# ★★ 2026-09-30 §24 第 5 步：这里原有**五个**成员，现全部删除，逐个记明去向 ——
#   · `_chan_relay_btn` / `_chan_steam_btn` / `_chan_hint` → 通道二选一的三件控件（随通道删除）；
#   · `_match_overlay`        → 「匹配中…」覆盖层（随机匹配删除）；
#   · `_host_room_created`    → 自动建房的状态位（建房动作已挪进对局场景，菜单侧不再建房）；
#   · `_no_auto_room`         → 上面那个的**自检夹具**（"只置一次、任何分支都不清"的闸，
#                               它守的 `--steamuitest` 判据 ⑱ 一并删除）。
#   ★ 那对状态位留下的教训值得留一句：**自检不许有真实副作用**（当时是"起 node 信令服务器"），
#     而夹具要选"任何分支都不会被清掉"的形态 —— 用会被 `else` 分支清掉的变量当夹具，
#     漏装一次就真把服务器起起来了（2026-09-30 实测，日志冒出 `[Matchmaking] 已自动启动…`）。
#     现在这个副作用源整个没了，所以夹具也不需要了。
var _code_hint: Label = null                   # 「你的房间号…」那行标签
var _join_hint: Label = null                   # 「输入…加入」那行标签
var _enter_btn: Button = null                  # 「Steam 建房并进入」
## 本局设置三个下拉（2026-10-21）。★ 它们**只显示**真源（`_sel_board` / `_sel_size` /
## `GameConfig.seat_choice`），本身不存状态 —— 见 `_refresh_duel_picks()`。
var _duel_board_opt: OptionButton = null
var _duel_size_opt: OptionButton = null
var _duel_seat_opt: OptionButton = null
var _join_btn: Button = null                  # 联机：「加入」按钮（★ 提为成员：要跟着面板宽度重排）

# ====== 对弈页（联机大厅）控件（2026-10-08 新建；**切页即销毁**）======
## ★★★ 用户口令「完善联机大厅，把主菜单的好友联机也搬到联机大厅里」：
##   联机的两个档（好友联机 / 公开大厅）从练习面板搬进底栏第三块「对弈」页，
##   页内用两个切换块承载 —— 练习面板的「线上」档与 netmode 两瓣**整族删除**。
## 档位 id 顺序（建切换块、派生按下态、判据都读它；顺序只有一处说了算）
const DUEL_TAB_ORDER: Array[int] = [NET_INVITE, NET_LOBBY]
## 对弈页几何常量（页内布局用；**没有**「从标签带反解槽位」那套公式了）
const DUEL_PAD: float = 40.0                  # 页左右内边距（与棋谱页同源观感）
const DUEL_TAB_W: float = 168.0               # 两个切换块的固定宽：它们是标签，不随窗口拉伸
const DUEL_JOIN_W: float = 92.0               # 「加入」按钮固定宽（余量全给输入框，长输入不顶出右沿）
## 判据里"可用宽"要扣掉的垂直滚动条余量（大厅列表超长时它会吃掉行宽）。
## ★ 为什么是个显式常量：写在判据里当字面量的话，将来换成自定义滚动条样式就**静默**失准。
const DUEL_SCROLLBAR_ALLOW: float = 16.0
## 公开大厅列表的**内容列宽**（不跟着页宽无限拉伸）。
## ★ 为什么要有上限（2026-10-08 目检）：页宽 1072 时，行内的「加入」被推到屏幕最右端，
##   与它左边的昵称隔着 900px —— "这一行的按钮"看不出属于哪一行。列表给个列宽（≈620）
##   就照顾了两头：长昵称仍有富余、按钮也挨着它那一行。
##   ★ 上限只对**列表**生效：好友联机那一档的控件本来就是窄的（建房按钮 300）。
const DUEL_LIST_W: float = 620.0
var _duel_root: Control = null                # 页根容器（原生控件树，切页销毁）
var _duel_me: Label = null                    # 页首：我的昵称 + 联机战绩
## 档位 id → 切换块 Button。★ 用字典而不是「两个成员 + 两处分支」：加档只改 `DUEL_TAB_ORDER`。
var _duel_tabs: Dictionary = {}               # ← 标签与按下态**全**由 `_refresh_duel_tabs()` 派生
var _duel_invite_box: Control = null          # 「好友联机」那一块（建房 + 输房间号加入）
var _duel_lobby_box: Control = null           # 「公开大厅」那一块（刷新 + 列表）
var _page: int = PAGE_MAIN                   # 当前菜单页
var _settings_root: Control = null            # 设置页原生控件根（非瓷砖），切换页面时销毁

# ====== 主菜单重设计（2026-10-02）======
## ★★ 背景棋盘**跟当前选择联动**：首页主视觉直接画所选棋盘的真实密铺。
##   为什么存"背景用的那两个值"而不是直接读 `_sel_board`：
##   绘制时要的是**已经切好档**的盘型（棋盘类型 + 大小档），而 `_sel_size` 的槽位 0
##   在爱因斯坦下是"种类"、在筝形下是"迷你"—— 直接读会在两种盘上取到错的几何。
##   ⇒ 切盘/切档时在这里**换算一次**（`_sync_menu_bg()`），绘制与判据都读它（唯一真源）。
var _menu_bg_board: int = BOARD_PENROSE
var _menu_bg_size: int = GameConfig.STANDARD
## 背景棋盘缓慢漂移的相位（主视觉用；0 = 不漂移）
var _bg_drift: float = 0.0
## 底部入口行（原"首页四入口行"）的块半径（绘制时读它，**不重算** ——
##   布局算一次、绘制读一次，两处各算一次就是"两处真相"，块与命中会差一点点）。
## ★ 2026-10-04：这一行从屏幕**顶部**搬到**底部**，名字沿用 `_nav_row_r`（仍是 nav 那一行），
##   但"哪一行"的概念由 `_footer_band()` 定义，不再有"头部两簇"。
var _nav_row_r: float = 0.0
## 本轮 nav 行的**相邻中心距**（绘制/判据都读它，不各自重算）。
## ★ 与 `_nav_row_r` 分开是因为两者由**不同约束**决定：R 由纵向预算与块宽决定，
##   pitch 由「标签不叠」与「可用宽度铺开」决定（见 `_nav_fit_solve` / `_nav_place`）。
var _nav_row_pitch: float = 0.0
## 底部行标签**实际用**的字号（区域不够宽时会从 24 逐档降到 21 / 18 …）。
## ★ 绘制与判据**都读它**（经 `_draw_fs_for()`）—— 各读各的就会出现"判据量的是 24、画的是 20"，
##   而那种错是**静默**的（判据照样绿，字照样叠）。
## ★★ 2026-10-04：`nav` 与 `quick` **共用这一个字号**（原来是 24 / 20 两档）。
##   理由：它俩现在是**同一行里的邻居**，"练习"比另外三块字号小一号会读成"次要项"，
##   而它恰恰是进对局的**唯一入口**（「开始对局」已删）⇒ 不是次要项。
##   ⚠️ 连带后果：原来那两个成员（`_nav_label_fs` / `_quick_label_fs`）里**只留这一个** ——
##   留着第二个就是"同一行两个字号真源"，改一边忘一边的表现是**静默的字号不一致**。
var _nav_label_fs: int = 24
## nav 实际摆成几行（1 = 一行；底部区域太矮/太窄时自动换行，见 `_layout_footer_row`）。
var _nav_rows: int = 1
## 本轮底部行带的上下沿（`--layoutdbg` / `--menutest` 的报告口径）。
## ★ 必须存**本轮**的值而不是重算 —— 重算要把整段行带算法再跑一遍，
##   那是"复制一份可能各自漂移的算法"。
var _nav_band_top: float = -1.0
var _nav_band_h: float = 0.0

# 外观设置控件（设置页重建时刷新；用于预设切换后同步取色器显示）
var _appr_preview_bg: ColorRect = null
var _appr_preview_board: Control = null   # 迷你棋盘（自绘，读 GameConfig 实时反映主题）

# 「鼠标指针」控件（外观组：自定义指针开关 + 指针大小滑条，2026-09-30 新增）
# 为什么这三个要存成员变量：headless 自检（`--settest`）要在**真实交互路径**上操作它们，
# 而设置页是运行时构建的 —— 没有稳定引用就只能靠遍历树找控件，那样一旦改排版就会漏判上游逻辑。
var _cursor_cb: CheckButton = null        # 开关：true = 用自定义三角刮刀，false = 系统箭头
## 图模式开关（2026-10-19）：「显示」组那颗 CheckButton。
## 语义 = 棋盘画成**完整网格**、棋子画成**圆形**（密铺的落子单元与邻接不变）。
## 真源是 `GameConfig.graph_mode`，这里只存控件引用（同步走 `_sync_graph_control()`）。
var _graph_cb: CheckButton = null
var _cursor_sl: HSlider = null            # 滑条：**值是 0..3 的档位下标**（不是像素！见 GameConfig.cursor_size_for_index）
var _cursor_val: Label = null             # 当前档文案（如「96 px」）
# ⚠️ 曾经有个 `_cursor_syncing` 递归守卫 —— 改用 `set_*_no_signal()` 之后它就没用了，
#    已删。留着的坏处是把"信号从源头掐掉"和"容许信号发出来再挡回去"两种口径并存，
#    以后有人删掉 no_signal 会以为还有守卫兜着（死变量比没有更危险）。

# 按选择算「真实盘形」用的**离树** game.gd 实例（见 `_shape_polys()`）。
# ★ 2026-10-02：它原先只服务主菜单右下角的「棋盘预览卡」；卡片删除后**唯一消费者
#   变成首页背景密铺**（`_bg_ensure()`）⇒ 整套逻辑保留（`_shape_gen_get()` / `_shape_polys()` /
#   本成员 / `_exit_tree()` 里的释放），只把 `_pv_*` / `_preview_*` 的名字改掉。
# 为什么不干脆在菜单里自己写一份几何：本项目铁律 —— 一个盘只有一份几何真源，
# 复制生成器必然各自漂移（新增/改盘时要改两处，迟早漏）。
var _shape_gen: Node = null      # 离树生成器实例（懒创建；不进场景树，故它的 _ready 不会跑）

# 主题色块按钮：方块尺寸与选中项（选中项描粗边，见 _make_preset_button）
# 一行 7 个：72×48 + 12 间距 + 行首 28 标签 = 604，内容列 616 刚好容纳且不溢出
const SWATCH_W: float = 72.0
const SWATCH_H: float = 48.0

## 顶部错误提示的字色。★ 抽成常量是**有意**的：`--steamuitest` 要读出「刚才那条提示到底显示了什么」，
## 而它靠这个颜色在子节点里认人。两处各写一份 `Color(1.0,0.45,0.45)` 的话，
## 哪天有人微调了提示色，自检就会**找不到提示 → 读回空串 → 判据静默变红**（而病因看着像 UI 坏了）。
const TOAST_RED: Color = Color(1.0, 0.45, 0.45)
var _preset_sel: String = ""              # 当前高亮的主题名（"" = 自定义配色，无高亮）
var _preset_btns: Array[Button] = []      # 全部色块按钮（切换后统一重绘描边）

# 页面旋转角：保留旋转绘制管线（_rotated），当前无切换动画，恒为 0
var _rot_t: float = 0.0
var _labelpos_done: bool = false               # --labelpos 只打印一次

## 人机（磐石 / 疾风）难度：**恒为最难**（2026-10-12 用户口令「人机默认最难，不需选择难度」）。
## ★★ 删掉的是**整条「难度可选择」的状态链**，不是"少一个选项"：
##   常量三档 → 建项三块 → `_select_diff()` → `_refresh_selection()` 的难度分支 →
##   `_sel_diff` 成员 → `last_match.cfg` 的 `diff` 回填。留任何一个都是"旋钮拧不动"的
##   死参数（铁律 §33：声明了但从不被读取 = 消融无效 + 回归全绿）。
## ★ 配置仍由 `_apply_ai_config()` **一处**写入引擎（难度 / 时间 / 线程 / 根候选宽度四项一起）
##   ⇒ "想拉开设难度"这条路没有被堵死：加回一档 = 加一个常量 + 加一处分支 + 加一块瓷砖。
## ⚰️ 墓碑（名字不许回收）：这里原有 `DIFF_EASY` / `DIFF_NORMAL` 两个常量。
##   它们当年的实测结论**留在 `_apply_ai_config()` 的注释里**，别丢。
const DIFF_HARD: int = GameConfig.AI_HARD

# 对战设置的选择状态（跨页保留）
var _sel_size: int = GameConfig.STANDARD     # 默认「标准」：彭罗斯→120 落子格、立方体→4 环/183 落子格
											# （随机档 = 每局现场生成约 200 格，见 game.gd random_target_tiles）
var _sel_mode: int = MODE_LOCAL   # 取值域 = MODE_LOCAL / MODE_VS_AI / MODE_XGAI / MODE_LIUSHUI / MODE_YEMA（五块瓷砖一一对应）
var _sel_netmode: int = NET_INVITE           # 联机方式：默认「邀请好友」
# ★ 2026-09-30 §24 第 5 步：这里原有 `var _sel_channel: int = GameConfig.CHAN_RELAY`
#   —— 联机**通道**（自建中继 / Steam P2P），与 `_sel_netmode`（"怎么找人"）正交。
#   通道二选一删除后它恒为 `CHAN_STEAM` ⇒ 成了"没有任何 UI 能改、也永远只有一种取值"的
#   死变量。按本工程口径（**死变量比没有更危险**：以后有人删掉 `_push_board_choice()` 里
#   那行赋值，却以为通道还有人在管）**删除**。
#   通道的唯一真源现在只剩 `GameConfig.net_channel` 一处（菜单写、`game.gd::_steam_arg()` 读）。
var _sel_board: int = BOARD_PENROSE         # 当前棋盘类型：默认选中「彭罗斯」（循环行的第 0 项）
## 爱因斯坦（帽子家族）的种类：只在 _sel_board == BOARD_HAT 时有意义（此时第二级那三瓣是种类，
## 不是大小档）。三档都走随机档，所以它和 _sel_size 互相独立，各记各的。
var _sel_hatkind: int = GameConfig.HAT_HAT
# ★ 2026-09-30 §24 第 5 步：这里原有 `var _net_starting: bool = false`（联机启动防重入）。
#   它原先由三条自建联机路径写（自动建房 / 凭码加入 / 快速匹配），第 5 步把这三条都删掉后
#   **没有任何写点** ⇒ 恒为 false 的死变量（只剩 `--steamuitest` 在读它，那是同义反复）。
#   ⇒ 变量与那几处读点一起删除。

var _breath_t: float = 0.0                   # 呼吸描边时间累计（秒）

@onready var _title: Label

## 自检/调试参数：把 `--` 前后的命令行参数**合并**后返回。
## 只看 `get_cmdline_args()` 时，`godot res://menu.tscn -- --xxtest` 会被静默忽略
## （不报错、也不进自检，表现为「自检卡死」）。合并后两种写法都能命中。
func _argv() -> PackedStringArray:
	var out := OS.get_cmdline_args()
	out.append_array(OS.get_cmdline_user_args())
	return out

## 一次性探针（2026-10-02）：量「headless 下能不能把视口改成真机那一档」。
## 背景：`--labeltest` 的标签×面板判据在 headless（视口 1152×1152）下**全绿**，
## 而同一份代码在实机 1152×648 目检是叠印的 —— 判据压根跑不到会撞的那一档，
## 等于没有牙齿（铁律 4）。而 `_row_fit_test` 的方法学注释写着 headless 下
## `size`「改不动」（Godot 报 non-equal opposite anchors）—— 但那说的是
## **改 Control 自己的 size**，根 Window 是另一回事，**没实测过不能当结论**。
##
## ★ 实测结果（2026-10-02，推翻了那条旧注释）：**改本节点自己的 `size` 是生效的**
##   （改完立刻回读 = 目标尺寸），改根 Window 反而会把本节点挤成 1152×144。
##   ⇒ 多视口扫描的老办法（"headless 改不动、只能解析算"）不必要：
##     直接 `size = 目标` → `_layout_setup()` → 回读布局产物 即可，
##     与 `_row_fit_test`「回读布局产物而非重算几何」的方法学完全一致。
## 本探针保留下来当**回归用的量具**：哪天有人又说"headless 改不动"，
## 跑一次就知道那是错的，别再照着错注释绕远路。
func _vp_probe() -> void:
	var keep: Vector2 = size
	print("[vpprobe] 初始 size=%s" % str(keep))
	# ★ 2026-10-08：这里原有「先切到线上 + 把 `_net_t` 顶到 1」两步 —— 它们服务的是
	#   netmode 两瓣的标签读数，随两瓣删除。本探针只量"改自己的 `size` 生不生效"，
	#   量 `mode` 行（本地 / 磐石 / 疾风）的标签位置同样成立。

	for vp in [Vector2(1152.0, 648.0), Vector2(1280.0, 800.0), Vector2(1024.0, 640.0)]:
		size = vp
		_layout_setup()
		var lf: float = -1.0
		for it in _items:
			if it["group"] == "mode" and (it["poly"] as PackedVector2Array).size() >= 3:
				lf = _label_now(it).x
				break
		print("[vpprobe] 目标=%s ⇒ 回读 size=%s  mode 行首块标签 x=%.0f" % [str(vp), str(size), lf])
		for it4 in _items:
			if it4["group"] == "mode" and (it4["poly"] as PackedVector2Array).size() >= 3:
				var l4: Vector2 = _label_now(it4)
				var tw4: float = UITheme.body_font().get_string_size(
						str(it4["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
				print("[vpprobe]   %s 瓣中心=%s 标签rect x=%.0f..%.0f" % [
						str(it4["label"]), str(it4["center"]),
						l4.x - tw4 * 0.5, l4.x + tw4 * 0.5])
			elif it4["group"] in ["mode", "action"] and (it4["poly"] as PackedVector2Array).size() >= 3:
				var bb4 := Rect2((it4["poly"] as PackedVector2Array)[0], Vector2.ZERO)
				for p4 in (it4["poly"] as PackedVector2Array):
					bb4 = bb4.expand(p4)
				print("[vpprobe]   [%s/%s] rect x=%.0f..%.0f y=%.0f..%.0f" % [
						str(it4["group"]), str(it4["label"]),
						bb4.position.x, bb4.end.x, bb4.position.y, bb4.end.y])
	size = keep
	_layout_setup()
	print("[vpprobe] 复原 size=%s" % str(size))
	get_tree().quit()

## 本次运行是不是**自动化运行**（自检 / 截图 / 预置选择）？命令行里出现 `--*test*`（所有自检
## flag，含将来新加的）、`--screenshot`、`--shotpage=`、`--select=` 都算。
##
## ⚠️ 这道闸管着两件事，缺一不可：
##   ① **不恢复**上一局选项 —— 自检与截图必须从**确定性的默认状态**出发；若读用户的
##      last_match.cfg，「用户上次选过爱因斯坦」就会让 labeltest 之类的断言随机变红，
##      而这种假红最难查（很像真 bug，但清掉配置就好了）。
##   ② **不落盘** —— 自检内部也会调到 `_push_board_choice()`（如 --einsteintest 的两段），
##      不挡住就会把测试用的临时选择写进用户的配置文件。
##
## 用**模式匹配**而不是逐个列举 flag：以后加一个新自检不必回来改这里
##（列举法迟早漏一处 —— 本工程「两处同口径」的老坑就是这类）。
## 注意 `--headless` **不算**自动化：冒烟里 `godot --headless res://menu.tscn --quit`
## 走的正是"正常运行"这条路径，于是冒烟顺带覆盖了「带恢复启动菜单」这一个分支。
##
## ★★ 2026-09-29 起判定**搬去 Autoload**（`GameConfig.is_automated_run()`），这里只转发：
##    原先 menu.gd 与 menu_mobile.gd **各有一份列举 flag 的副本，而且列的不是同一批**
##    （手机侧漏掉 `--portraittest` 这类新 flag ⇒ 那条路径上写盘会真写用户配置）。
##    两份副本的存在本身就是 bug 温床，所以收成一份、两侧转发。
##    本函数**保留**是因为它是被大量调用的门面（且 `--lastmatchtest` 第 4 条把它当阳性探针测）。
func _is_automated_run() -> bool:
	return GameConfig.is_automated_run()


## 自检（--cursortest）：自定义鼠标光标（三角刮刀）的**素材与热区**。
##
## 为什么必须有它：光标接错**全是静默失败** —— 游戏照常跑、exit=0、不报任何错，
## 只是「点得不准」（热区偏了）或「某种底色上指针看不见」。没有自检就只能靠人眼撞见。
##
## ⚠️ 边界（别把这条当成品验收）：`--headless` 下**根本没有光标渲染**，
##    所以这里能自动验的只有「素材 + 几何」这一半。观感/大小必须人眼看。
##
## 判据里带**阴性对照**（见 ⑤）：A 不存在的尺寸必须报缺；B 热区挪到**木柄中心**时「木色占比」
## 判据必须报警（实测木柄 96~100% / 刀尖 0%）；C 热区挪到**刀刃半路**时 ④ 的「尖端余量」判据
## 必须报警 —— 三条对照都成立，才说明判据真的在测东西，而不是恒真。
func _cursor_self_test() -> void:
	print("[cursortest] 自定义光标素材与热区（几何真源：工作区 瓷砖围棋_光标素材/draw_cursor.py）")
	var bad: Array[String] = []
	var cover_lo := 999.0
	var cover_hi := 0.0
	var worst_px := 0.0        # 热区偏离「比例位置」的像素偏差（判据见 ④）
	for s: int in GameConfig.CURSOR_SIZES:
		var path: String = GameConfig.cursor_texture_path(s)
		if not ResourceLoader.exists(path):
			bad.append("缺素材 %s" % path)
			print("[cursortest] %3dpx ✗ 找不到 %s" % [s, path])
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			bad.append("加载失败 %s" % path)
			print("[cursortest] %3dpx ✗ 加载失败 %s" % [s, path])
			continue
		var sz: Vector2 = tex.get_size()
		var cols := int(sz.x)
		var rows := int(sz.y)
		var img: Image = tex.get_image()
		if img == null:
			bad.append("%dpx 取不到像素（get_image() 返回 null）" % s)
			print("[cursortest] %3dpx ✗ 取不到像素" % s)
			continue
		var hs: Vector2i = GameConfig.cursor_hotspot_for(tex)
		var opaque := 0
		for y in rows:
			for x in cols:
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		var cover := 100.0 * float(opaque) / float(cols * rows)
		cover_lo = minf(cover_lo, cover)
		cover_hi = maxf(cover_hi, cover)
		# ① 素材实际尺寸必须与文件名一致（防「放错文件」——最蠢也最像的那种错）
		var size_ok: bool = cols == s and rows == s
		# ② 热区必须落在图内、且在**刀尖那一角**区（当前朝向左上；与系统箭头同向）。
		#    ★ 改朝向时这里要跟着改：真源是 `draw_cursor.py` 的 `TIP_TO`，
		#      对应 `GameConfig.CURSOR_HOTSPOT_RATIO` —— 三者必须一致，否则这条会红。
		var in_img: bool = hs.x >= 0 and hs.y >= 0 and hs.x < cols and hs.y < rows
		var ratio := float(hs.x) / float(cols)
		var in_zone: bool = ratio >= 0.01 and ratio <= 0.15
		# ③ ★牙齿★ 热区必须压在**刀尖（钢/灰）**上，而不是木柄上
		var wood: float = _cursor_wood_share(img, hs, 2)
		var wood_ok: bool = wood < 0.5
		# ④ ★牙齿★ 热区必须是全图在**刀刃指向**上最外的那个点（即真的在尖端，不在半路）
		var slack: float = _cursor_tip_slack(img, hs)
		worst_px = maxf(worst_px, absf(slack))
		var tip_ok: bool = absf(slack) <= GameConfig.CURSOR_TIP_SLACK_PX
		if not size_ok:
			bad.append("%dpx 素材实际尺寸 %dx%d" % [s, cols, rows])
		if not in_img:
			bad.append("%dpx 热区 %s 落在图外" % [s, hs])
		if not in_zone:
			bad.append("%dpx 热区比例 %.3f 不在刀尖角区 [0.01, 0.15]" % [s, ratio])
		if not wood_ok:
			bad.append("%dpx 热区落在木柄上（木色占比 %.0f%%）" % [s, wood * 100.0])
		if not tip_ok:
			bad.append("%dpx 热区不在尖端（沿指向余量 %.2fpx）" % [s, slack])
		print("[cursortest] %3dpx 热区 (%d,%d) 比例 %.3f｜尺寸 %dx%d｜覆盖 %.0f%%｜热区木色 %.0f%%｜尖端余量 %+.2fpx｜%s" % [
			s, hs.x, hs.y, ratio, cols, rows, cover, wood * 100.0, slack,
			"✓" if size_ok and in_img and in_zone and wood_ok and tip_ok else "✗"])
	# ④ 热区必须是全图在**刀刃指向**上最外的那个点。判据：先取木柄（暖色）像素的质心当"出发点"，
	#    方向 = 质心→热区；把全图不透明像素投影到该方向，最大投影与热区的投影之差就是"余量"。
	#    ★ 为什么换掉上一版：上一版是 |hs − 尺寸×比例| ≤ 0.5px，而 hs **本身就是**那个比例
	#      round 出来的 → **恒真、零牙齿**（比例写错也照样过）。这一版拿素材**自己的像素**当参照。
	#    ★ 阈值 1.0px 是量出来的：正确热区四档余量 −0.46…−0.08px，而最近的错法（旧 0.088 比例）
	#      +2.43px、画布正中 +29.7px、右下角 −4.4px → 1.0 落在空档中间，四种错法全抓得住。
	var tip_ok_all: bool = worst_px <= GameConfig.CURSOR_TIP_SLACK_PX
	print("[cursortest] ④ 尖端余量最坏 %.2fpx（≤%.1f）→ %s" % [
		worst_px, GameConfig.CURSOR_TIP_SLACK_PX, "✓" if tip_ok_all else "✗"])
	if cover_lo < 20.0 or cover_hi > 60.0:
		bad.append("图形覆盖率 %.0f%%~%.0f%% 越界（20~60）—— 是不是放错了文件？" % [cover_lo, cover_hi])
	print("[cursortest]    图形覆盖率区间 %.0f%%~%.0f%%（合理带 20~60）→ %s" % [
		cover_lo, cover_hi, "✓" if cover_lo >= 20.0 and cover_hi <= 60.0 else "✗"])

	# ⑤ 阴性对照：证明上面几条判据**真的在测东西**
	#    A. 不存在的尺寸必须被报为缺素材（否则「素材存在」那条是空转的）
	var bogus: String = GameConfig.cursor_texture_path(33)
	var bogus_absent: bool = not ResourceLoader.exists(bogus)
	print("[cursortest] ⑤A 不存在的尺寸 33 → %s（应报缺失）→ %s" % [
		bogus, "✓" if bogus_absent else "✗ 竟然存在，路径推导有问题"])
	if not bogus_absent:
		bad.append("负路径 %s 竟然存在" % bogus)
	#    B. 把热区强行挪到**木柄中心**（`CURSOR_WOOD_PROBE_RATIO`），③ 的木色判据必须报警。
	#       ★ 不能拿「画布正中」当探针：本版（用户稿，斜轴布局）的**正中落在灰刀面上**，
	#         那里木色占比也是 0% → 阴性对照会恒假红，等于没测。探针点必须真的是木柄。
	var t48: Texture2D = load(GameConfig.cursor_texture_path(48))
	if t48 == null:
		bad.append("48px 素材加载失败，⑤B 无法执行")
	else:
		var i48: Image = t48.get_image()
		var wp := Vector2i(int(round(48.0 * GameConfig.CURSOR_WOOD_PROBE_RATIO.x)),
				int(round(48.0 * GameConfig.CURSOR_WOOD_PROBE_RATIO.y)))
		var wood_mid: float = _cursor_wood_share(i48, wp, 2)
		var mid_ok: bool = wood_mid >= 0.5
		print("[cursortest] ⑤B 热区挪到木柄中心 (%d,%d) 时木色占比 %.0f%%（应 ≥50%%）→ %s" % [
			wp.x, wp.y, wood_mid * 100.0,
			"✓ 判据能区分刀尖与木柄" if mid_ok else "✗ 区分不出来，等于没测"])
		if not mid_ok:
			bad.append("木柄/刀尖判据区分不出来（木柄中心木色占比仅 %.0f%%）" % (wood_mid * 100.0))
		#    C. ④ 的阴性对照：取「木柄质心 → 热区」的中点（沿刀刃走了一半，必然不是尖端），
		#       余量必须超出容差。★ 不写死某个比例：那样一换素材/换朝向就失效。
		var wc: Vector2 = _cursor_wood_centroid(i48)
		var hs48 := Vector2(GameConfig.cursor_hotspot_for(t48))
		var half := Vector2i(int(round((wc.x + hs48.x) * 0.5)), int(round((wc.y + hs48.y) * 0.5)))
		var slack_bad: float = _cursor_tip_slack(i48, half)
		var c_ok: bool = absf(slack_bad) > GameConfig.CURSOR_TIP_SLACK_PX
		print("[cursortest] ⑤C 热区挪到刀刃半路 %s 时余量 %+.2fpx（应 >%.1f）→ %s" % [
			half, slack_bad, GameConfig.CURSOR_TIP_SLACK_PX,
			"✓ 判据能区分尖端与半路" if c_ok else "✗ 区分不出来，等于没测"])
		if not c_ok:
			bad.append("④ 尖端判据区分不出来（刀刃半路处余量仅 %+.2fpx）" % slack_bad)

	print("[cursortest] 汇总：%s" % ("全部通过 ✓" if bad.is_empty() else "失败 ✗ %s" % [bad]))
	get_tree().quit()


## 热区邻域里的「木色」像素占比。木柄是暖色（R 明显大于 B），钢刀面/近黑描边是中性色。
## 用来判「热区到底压在刀尖上还是压在木柄上」；该判据的阴性对照见 `_cursor_self_test` ⑤B。
func _cursor_wood_share(img: Image, c: Vector2i, rad: int) -> float:
	var wood := 0
	var n := 0
	var cols := img.get_width()
	var rows := img.get_height()
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			var col := img.get_pixel(clampi(c.x + dx, 0, cols - 1), clampi(c.y + dy, 0, rows - 1))
			if col.a <= 0.5:
				continue
			n += 1
			if col.r - col.b > 0.15 and col.r > col.g:
				wood += 1
	return 0.0 if n == 0 else float(wood) / float(n)


## 全部「木色」像素的质心（图像像素坐标）。判据 ④ 拿它当"从哪儿出发"的原点。
## 返回 `Vector2(-1, -1)` 表示一个木色像素都没有（那说明木柄没画出来 —— 本身就该报错）。
func _cursor_wood_centroid(img: Image) -> Vector2:
	var sx := 0.0
	var sy := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var col := img.get_pixel(x, y)
			if col.a <= 0.5:
				continue
			if col.r - col.b > 0.15 and col.r > col.g:
				sx += float(x) + 0.5
				sy += float(y) + 0.5
				n += 1
	return Vector2(-1.0, -1.0) if n == 0 else Vector2(sx / float(n), sy / float(n))


## ★牙齿判据④★：热区是不是**全图在"刀刃指向"上最外的那个点**（即真的在尖端）。
##
## 做法：① 取木柄（暖色）质心当原点；② 方向 = 原点 → 热区（= 刀刃指向）；
##       ③ 把全图不透明像素投影到该方向，最大投影与热区的投影之差 = **余量**。
## 余量 ≈ 0（可负一点，因为热区是亚像素的）→ 热区就在尖端；
## 余量明显为正 → 热区退回到刀身半路上了。
##
## ★ 为什么不是「|热区 − 尺寸×比例| ≤ 0.5」那种写法：热区**本身就是**那个比例 round 出来的，
##   两个量天然只差一个 round 误差 → 判据恒真、零牙齿（比例写错也照样过）。这一版拿素材
##   **自己的像素**当参照，所以它测的是"热区到底落在图上哪儿"，而不是"常量有没有自洽"。
func _cursor_tip_slack(img: Image, hs: Vector2i) -> float:
	var c: Vector2 = _cursor_wood_centroid(img)
	if c.x < 0.0:
		return 999.0                      # 找不到木柄 → 视为判不了，直接报大余量
	var dir := Vector2(hs) - c
	if dir.length() < 1e-6:
		return 999.0
	dir = dir.normalized()
	var best := -1e18
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a <= 0.5:
				continue
			best = maxf(best, (Vector2(float(x) + 0.5, float(y) + 0.5) - c).dot(dir))
	return best - (Vector2(hs) - c).dot(dir)


## 统一的「判据打印 + 形状守卫 + 汇总」，**两个自检共用这一份**
## （`--steamtest` 与 `--steamuitest`）。返回失败判据名列表。
##
## ★ 为什么要抽出来：第二个打印循环是典型的「一处写、多处读」分叉 —— 形状守卫只要有一份
##   被改弱（或忘了带），坏掉的判据条就会在那条路径上**把进程弄死**。结构守卫 S20 就是
##   靠"这条守卫行必须**恰好出现 1 次**"在首跑时把这个重复抓出来的（当时新建 `--steamuitest`
##   顺手复制了一份 ⇒ S20 立刻报「命中 2 次」）。这正说明"复制守卫"是不行的，必须共用。
##
## ★★ 形状守卫的必要性（**绝不要写 `bool(c[1])`**）：判据条第 2 位一旦被写歪成字符串，
##    `bool(String)` 会抛 `SCRIPT ERROR: Nonexistent 'bool' constructor.`，
##    而 SCRIPT ERROR 会**中止整个调用函数**（连后面的 `quit()` 一起带走）
##    ⇒ 自检挂死、回归干等到 300s 超时（EXIT=124）。实测 2026-09-30。
##    写歪了应该"显示成红 + 有名字"，不该把进程弄死。
func _print_checks(prefix: String, checks: Array) -> Array:
	print("%s ---- 判据 ----" % prefix)
	var failed: Array = []
	for c in checks:
		if not (c is Array) or (c as Array).size() < 2:
			print("%s !! 判据条形状非法，已跳过：%s" % [prefix, str(c)])
			continue
		var nm := str(c[0])
		var okc: bool = (c as Array)[1] is bool and (c as Array)[1]
		# ★ 判据名里**不许出现全角括号**（并列信息用 `｜`）：阴性对照仪靠 `split("（")[0]`
		#   切「哪条判据红了」，名字带全角括号会把尾巴连同 `✗` 一起切掉 ⇒ 判定退化成
		#   「无编号判据红，看结论」。踩过两轮，已做成静态守卫 **S26**。
		print("%s %s %s（%s）" % [prefix, nm, "✓" if okc else "✗",
				str(c[2]) if c.size() > 2 else ""])
		if not okc:
			failed.append(nm)
	return failed


## 自检：--musictest 音乐系统（music.gd）。
## ★ 与 `--steamtest` 同一分工：**判据体在被测组件里**（`Music.run_selftest()` 才拿得到
##   合成器、节拍器、和声映射的细节），这里只做「触发 + 统一打印 + 判据数守卫 + 退出」。
## ★★ 为什么这里必须有一条"判据数 > 0"：音乐是**听觉产物**，headless 听不到 ——
##   最容易写出的假自检就是"什么都没测、一条红都没有"（全绿的假象）。
##   判据数必须 > 0，否则结论一律算失败。
## ★ 打印与形状守卫一律走 `_print_checks()`（**唯一真源**）：它负责"判据名不许带全角括号"
##   与"形状非法不许把进程弄死"这两条既有纪律（见该函数的说明）。
func _music_self_test() -> void:
	print("[musictest] 开始（音乐系统：拨弦合成 / 固定节拍 / 和声随战况）")
	var t0 := Time.get_ticks_msec()
	var checks: Array = Music.run_selftest()
	var failed: Array = _print_checks("[musictest]", checks)
	print("[musictest] 判据 %d 条，失败 %d 条%s" % [checks.size(), failed.size(),
			"" if failed.is_empty() else "：" + ", ".join(failed)])
	var pass_all := failed.is_empty() and checks.size() > 0
	print("[musictest] 结论：", "通过 ✓" if pass_all else "失败 ✗")
	print("[musictest] 耗时 %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


## 自检：--steamtest Steam 联机封装（steam_net.gd）。
## ★ 判据体在 `SteamNet.run_selftest()` 里 —— 那边才拿得到 Steam 的反射细节；
##   这里只负责「触发 + 统一打印 + 退出」，与其它自检的分工一致。
## ★ 它是**协程**（被测体内部要 await 异步的 lobby 回调），所以在 _ready 里**不 await** 直接调，
##   让它自己跑完再 quit（`_ready` 保持同步，避免给整个菜单引入协程化的连带影响）。
## ⚠️ 「环境不可用」与「代码坏」在输出里**必须分开**：Steam 没开 / lobby 后端不通时要明说，
##    不能把环境问题吞成通过 —— 静默绿比红更危险。
func _steam_self_test() -> void:
	print("[steamtest] 开始（Steam 联机封装自检）")
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = await SteamNet.run_selftest()
	var checks: Array = res.get("checks", [])
	# ★ 打印 + 形状守卫 + 收集失败项都走 `_print_checks()`（**与 `--steamuitest` 共用一处**：
	#   复制第二份打印循环会让"形状守卫"分叉，结构守卫 S20 首跑就把那次重复抓出来了）。
	var failed: Array = _print_checks("[steamtest]", checks)
	var inf := SteamNet.info()
	print("[steamtest] 环境：state=%s | reason=%s | appid=%s | steamid=%s | 昵称=%s | GodotSteam=%s" % [
			inf["state"], inf["reason"], inf["app_id"], inf["steam_id"],
			inf["persona"], inf["godotsteam_version"]])
	print("[steamtest] 判据 %d 条，失败 %d 条%s" % [checks.size(), failed.size(),
			"" if failed.is_empty() else "：" + ", ".join(failed)])
	# ★ 判据数必须 > 0 —— 否则"什么都没测"会和"全通过"长得一模一样（手机菜单那次的教训）
	var pass_all := bool(res.get("pass", false)) and failed.is_empty() and checks.size() > 0
	print("[steamtest] 结论：", "通过 ✓" if pass_all else "失败 ✗")
	print("[steamtest] 耗时 %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


## 自检：--steamuitest 菜单侧 Steam 联机 UI。
## （§21 第 3 步建立，测的是"通道二选一"；§24 第 5 步删掉自建联机后按"只剩一条通道"重写。）
##
## 重写后**要钉死的三件事**（都是本工程踩过的坑）：
##  ① **降级不许静默**：插件缺失 / Steam 没开 / 没登录 ⇒ 必须在**点击时**给 toast 并
##     **留在菜单**，绝不带着半截状态进对局。第 5 步删掉"通道按钮 disabled"那层 UI 之后，
##     `_host_enter_game()` / `_steam_join_by_id()` 里那道 `ensure_init()` 就是**唯一**的拦截点。
##  ② **校验顺序固定**：格式 ⇒ 环境 ⇒ 落参数 ⇒ 请求转场。顺序错（先落参数再查环境）会留下
##     "参数写脏了却停在菜单"的静默态 —— 判据 ⑥ 把顺序钉死。
##  ③ **判据读真源**：·「有没有请求转场」读**点前点后的快照差**（`_join_snap()`，里面含
##     `Transition.is_busy()` —— 它真的在 `change_scene()` 开头被置真），而**不是**"点完之后
##     是不是转场中"：后者一旦前面漏过一次转场请求就恒真（同义反复）；
##     · 提示语读**真的挂在树上的那个 Label**（`_toast_text_since`），不读另存的副本。
##
## ★★ 为什么每条非法输入都要**同时**断言「提示对了」与「参数未改动」：
##   只断言提示语是不够的 ——「提示完照样往下走、把参数写了、把场景切了」在输出里
##   **完全看不出来**（`_steam_join_by_id()` 里那几个 `return` 漏一个就是这个症状）。
##   两条合起来才叫"被挡住了"。
##
## ★ 环境门控：需要「插件在场 / Steam 可登录」才够得到的判据（⑩）缺环境时**明说跳过、
##   不计红** —— 不许为了凑数写成恒真（把环境问题吞成通过，比红更危险）。
##
## ★★ 第 5 步顺手**删掉了 5 条**没有对象的判据（原 ①②③④⑤⑥⑱），别以为是漏了：
##   · 原 ①~⑥ 测的是"通道按钮点击 ⇒ 四条文案换语义 / 通道 × 联机方式的可见性矩阵 /
##     Steam 档拒绝随机匹配" —— 通道与联机方式都只剩一档，这些矩阵全部塌缩成常量；
##   · 原 ⑱「全程未触发自动建房」测的是"自检没把 node 信令服务器起起来" ——
##     自动建房这个**被测对象**已整个删除，留着它就是恒真式。
##   ⇒ 新版本改为 10 条：四条 Steam 文案 / 面板可见性 / 三条输入校验 / 环境拦截 /
##     `online` 复位 / 自动化守卫 / 真机落参数转场。
func _steam_ui_self_test() -> void:
	print("[steamuitest] 开始（菜单侧 Steam 联机 UI 自检）")
	var t0 := Time.get_ticks_msec()

	# 对弈页控件缺失就没法测了：**先挡一道**，别让后面那些 `.text` 直接抛 SCRIPT ERROR
	# （SCRIPT ERROR 会中止整个调用函数、连 `quit()` 一起带走 ⇒ 回归干等到 300s 超时）。
	# ★ 2026-10-08：入口从练习面板的浮层搬进「对弈」页 ⇒ 这里必须先**建页**再挡。
	#   建页本身不碰 Steam（见 `_build_duel_ui()` 的注释）⇒ 无 Steam 的机器照样跑完
	#   除 ⑩ 之外的全部判据。
	SteamNet.set_force_missing(false)
	_set_page(PAGE_LOBBY)
	if _duel_root == null or _ip_edit == null or _join_btn == null \
			or _enter_btn == null or _code_hint == null or _join_hint == null \
			or _duel_tabs.size() != DUEL_TAB_ORDER.size():
		print("[steamuitest] 对弈页控件缺失 ⇒ 无法继续（判据 0 条）")
		print("[steamuitest] 结论：失败 ✗")
		get_tree().quit()
		return
	var plugin: bool = SteamNet.is_plugin_present()
	print("[steamuitest] 环境：Steam 插件在场=%s | 需要插件的判据会明说「跳过」，其余照跑" % str(plugin))

	var checks: Array = []
	var skipped: Array = []

	# ── ⓪ 建页**那一刻**就必须自洽（2026-10-08，被目检抓出来的真 bug 的接棒判据）──────
	#   病灶：`_refresh_duel_tabs()` 曾被写在"两块内容还没建出来"的位置 ⇒ 空转 ⇒
	#   **首帧两块同时可见**（VBox 里叠着两套控件）。
	#   ★★ 为什么 ② / `--labeltest` ③ 抓不到：它们都**自己**显式调一次 `_refresh_duel_tabs()`
	#     再量 —— 量的是"函数对不对"，量不到"建页有没有调它"。
	#     ⇒ 与铁律 11 同族：**探针（函数）、判据（接线）、目检（观感）三件分工不能混**。
	#   做法：**不改档位**、直接重建页（走 `_set_page` 的真实路径），然后量三个量对不对上。
	var keep_net0: int = _sel_netmode
	_set_page(PAGE_LOBBY)
	var tabs0: Dictionary = _duel_tab_state()
	var inv0: bool = _duel_invite_box.visible == (keep_net0 != NET_LOBBY)
	var lob0: bool = _duel_lobby_box.visible == (keep_net0 == NET_LOBBY)
	var tab0: bool = bool(tabs0.get(keep_net0, false))
	var c0: bool = inv0 and lob0 and tab0
	checks.append(["⓪ 建页即自洽｜两块可见性与按下态都对上档位｜派生时机不能空转", c0,
			"档位=%s 联机块对上=%s 大厅块对上=%s 该档按下=%s" % [
				_netmode_label(keep_net0), str(inv0), str(lob0), str(tab0)]])

	# ── ① 四条文案全是 Steam 语义（进线上模式就该是这个，不再需要先点通道）────────
	var c1: bool = _enter_btn.text.contains("Steam") and _code_hint.text.contains("Steam") \
			and _join_hint.text.contains("Steam") and _ip_edit.placeholder_text.contains("房间号")
	checks.append(["① 线上模式面板四条文案均为 Steam 语义", c1,
			"进入按钮=「%s」码标签=「%s」加入标签=「%s」占位=「%s」" % [
				_enter_btn.text, _code_hint.text, _join_hint.text, _ip_edit.placeholder_text]])

	# ── ② 两档互斥：档位一翻，两块内容与两个切换块的按下态**一起**跟着变 ─────────────
	#   ★ 三半一起量（只量一半的话，把它写成恒真也能过）：
	#     ① 好友联机档 ⇒ 只有联机块可见；② 公开大厅档 ⇒ 只有大厅块可见；
	#     ③ 两个切换块的按下态与档位一致。
	_sel_netmode = NET_INVITE
	_refresh_duel_tabs()
	var v_inv: bool = _duel_invite_box.visible and not _duel_lobby_box.visible
	_sel_netmode = NET_LOBBY
	_refresh_duel_tabs()
	var v_lob: bool = _duel_lobby_box.visible and not _duel_invite_box.visible
	var tabs2: Dictionary = _duel_tab_state()
	var v_tab: bool = bool(tabs2.get(NET_LOBBY, false)) and not bool(tabs2.get(NET_INVITE, true))
	_sel_netmode = NET_INVITE
	_refresh_duel_tabs()
	var c2: bool = v_inv and v_lob and v_tab
	checks.append(["② 两档互斥｜档位⇒两块内容与按下态一起变", c2,
			"好友档(联机块可见=%s) 大厅档(大厅块可见=%s) 按下态=%s" % [
				str(v_inv), str(v_lob), str(tabs2)]])

	# ── ③ 空输入 ⇒ 提示「房间号」且不转场、不写参数 ───────────────────────────
	_ip_edit.text = ""
	var s3: Dictionary = _join_snap()
	var n3: int = get_child_count()
	_start_join()                       # 真实路径：点「加入」按钮的回调
	var msg3: String = _toast_text_since(n3)
	var d3: String = _join_snap_delta(s3)
	var c3: bool = msg3.contains("房间号") and d3 == "未改动"
	checks.append(["③ 空输入 ⇒ 提示房间号｜不请求转场也不写参数", c3,
			"提示=「%s」参数%s" % [msg3, d3]])

	# ── ④ 非数字房间号 ⇒ 拒 ──────────────────────────────────────────────────
	#   ★ 为什么要严：输错一位就会去一个**不存在的房间**干等，而 Steam 那边**不报错**
	#     —— 症状是"永远等不到人"，没有任何提示。
	_ip_edit.text = "abc"
	var s4: Dictionary = _join_snap()
	var n4: int = get_child_count()
	_start_join()
	var msg4: String = _toast_text_since(n4)
	var d4: String = _join_snap_delta(s4)
	var c4: bool = msg4.contains("纯数字") and d4 == "未改动"
	checks.append(["④ 非数字房间号 ⇒ 拒绝｜不请求转场也不写参数", c4,
			"提示=「%s」参数%s" % [msg4, d4]])

	# ── ⑤ 房间号 0 ⇒ 拒 ──────────────────────────────────────────────────────
	_ip_edit.text = "0"
	var s5: Dictionary = _join_snap()
	var n5: int = get_child_count()
	_start_join()
	var msg5: String = _toast_text_since(n5)
	var d5: String = _join_snap_delta(s5)
	var c5: bool = msg5.contains("大于 0") and d5 == "未改动"
	checks.append(["⑤ 房间号 0 ⇒ 拒绝｜不请求转场也不写参数", c5,
			"提示=「%s」参数%s" % [msg5, d5]])

	# ── ⑥ 格式合法但环境不可用 ⇒ 卡在**环境**那一道，参数一个都不许落 ─────────
	#   ★ 这条把「校验顺序」钉死了：格式 ⇒ 环境 ⇒ 落参数 ⇒ 请求转场。
	#     顺序错（先落参数再查环境）时快照里四个字段任一会变 ⇒ 报红。
	_ip_edit.text = "109775243422783190"
	SteamNet.set_force_missing(true)
	var s6: Dictionary = _join_snap()
	var n6: int = get_child_count()
	_start_join()
	var msg6: String = _toast_text_since(n6)
	var d6: String = _join_snap_delta(s6)
	SteamNet.set_force_missing(false)
	var c6: bool = msg6.contains("Steam 不可用") and d6 == "未改动"
	checks.append(["⑥ 格式合法但环境不可用 ⇒ 卡在环境校验｜不请求转场也不写参数", c6,
			"提示=「%s」参数%s" % [msg6, d6]])

	# ── ⑦ 建房路径同款一闸：环境不可用 ⇒ 给提示且不请求转场 ───────────────────
	#   ★ 第 5 步删掉"通道按钮 disabled"之后，这道闸是**唯一**的拦截点 —— 所以它必须单独有判据。
	SteamNet.set_force_missing(true)
	var s7: Dictionary = _join_snap()
	var n7: int = get_child_count()
	_host_enter_game()
	var msg7: String = _toast_text_since(n7)
	var d7: String = _join_snap_delta(s7)
	SteamNet.set_force_missing(false)
	var c7: bool = msg7.contains("Steam 不可用") and d7 == "未改动"
	checks.append(["⑦ 环境不可用时点「建房并进入」⇒ 给提示且不请求转场", c7,
			"提示=「%s」参数%s" % [msg7, d7]])

	# ── ⑧ `_push_board_choice()` 落通道 + **联机开关的真源**（所有开局路径的唯一必经点）──
	#   a 联机局（`GameConfig.mode == ONLINE`）⇒ **不许**把 `online` 复位；
	#   b 非联机局 ⇒ 强制复位（守「联机过一局、回菜单玩单机」时 `online` 粘住、
	#     导致 `game.gd::_ready` 仍走 `_start_network()` 的既有隐患）。
	#   ★★ 2026-10-08：a 这一半**换了真源** —— 原来是 `_sel_mode != MODE_ONLINE`，而练习面板
	#     删掉「线上」档后 `_sel_mode` 永不为 ONLINE ⇒ 那个条件**恒真** ⇒ 联机建房时刚设好的
	#     `online = true` 会被立刻抹掉（**静默变成单机局**）。现在读 `GameConfig.mode`
	#     （与 `game.gd` 的 `start_mode` 同一个真源，铁律 8：一处写一处读）。
	#   ★ b 必须**故意写一次** `online = true`：不先设真，就分不出"被复位了"和"本来就是假"。
	GameConfig.mode = MODE_ONLINE
	GameConfig.online = true
	GameConfig.net_channel = GameConfig.CHAN_STEAM
	_push_board_choice()
	var a8: bool = GameConfig.online and GameConfig.net_channel == GameConfig.CHAN_STEAM
	GameConfig.mode = MODE_LOCAL
	GameConfig.online = true
	GameConfig.net_channel = GameConfig.CHAN_STEAM
	_push_board_choice()
	var b8: bool = GameConfig.online == false and GameConfig.net_channel == GameConfig.CHAN_STEAM
	checks.append(["⑧ 落通道｜联机局⇒不复位 online；非联机⇒复位｜通道恒 Steam", a8 and b8,
			"联机局 online=%s 非联机复位=%s（online→%s 通道→%d）" % [
				str(a8), str(b8), str(GameConfig.online), GameConfig.net_channel]])
	GameConfig.mode = MODE_LOCAL

	# ── ⑨ 自动化运行守卫（本自检绝不碰用户的 `last_match.cfg`）────────────────
	#   ★ 这条同时是 `_is_automated_run()` 的**阳性探针**：匹配规则一旦写坏（例如漏掉 `--*test*`），
	#     这里立刻报红，而不是等到某天发现"跑一次自检把玩家的上一局选项冲了"。
	#     （⑧ 里两次 `_push_board_choice()` 就是被它护着的真实写点。）
	var c9: bool = _is_automated_run()
	checks.append(["⑨ 自动化运行守卫为真｜本自检不写用户的上一局配置", c9,
			"is_automated_run=%s" % str(c9)])

	# ── ⑩ 真机那一段：合法房间号 ⇒ 参数落位 + 请求转场。**必须放最后** ──────────
	#   ★ 它会真的调 `Transition.change_scene()`（异步：先淡出 0.3s 再换场景）。
	#     本自检是**同步**跑完的，紧接着 `quit()` ⇒ 转场那一步永远等不到，
	#     所以进程不会真的切进 game.tscn（这也是它必须排在最后的原因）。
	#   ★ 环境门控：拿不到 Steam 就**明说跳过**，不计红。
	if not plugin:
		skipped.append("⑩ 真机落参数并请求转场｜环境：Steam 插件不在场")
	elif not SteamNet.ensure_init():
		skipped.append("⑩ 真机落参数并请求转场｜环境：Steam 不可用（state=%s reason=%s）" % [
				SteamNet.state(), SteamNet.reason()])
	else:
		_ip_edit.text = "109775243422783190"
		var s10: Dictionary = _join_snap()
		_start_join()
		var d10: String = _join_snap_delta(s10)
		# ★ 这里**不能**再写 `点击前无转场 and 点击后转场中` —— 前面只要漏过一次转场请求，
		#   "点击后转场中" 就恒真 ⇒ 判据退化成同义反复。改成"四个字段必须**变成**期望值"
		#   （每个都是**这一次点击**该造成的变化）。
		var c10: bool = GameConfig.steam_lobby == 109775243422783190 \
				and not GameConfig.is_host and GameConfig.online \
				and GameConfig.net_channel == GameConfig.CHAN_STEAM \
				and Transition.is_busy()
		checks.append(["⑩ 合法房间号 ⇒ 参数落位并请求转场", c10, "参数%s" % d10])

	# ── ⑪ 公开大厅档的降级闸：Steam 不可用 ⇒ 档位不翻、列表不刷 ────────────────────
	#   ★ 与 ⑥⑦ 同一道闸（`_select_netmode()` / `_refresh_lobby_list()` 里的 `ensure_init()`）。
	#   ★ 量**这一次调用的增量**：先把档位摆回「好友联机」，再过闸点「公开大厅」，然后断言
	#     ① 档位没翻 ② 状态行一个字都没动（旧版量的 `_lobby_panel == null` 家族已随浮层删除）。
	_sel_netmode = NET_INVITE
	_refresh_duel_tabs()
	var st11: String = _lobby_status.text if _lobby_status != null else ""
	SteamNet.set_force_missing(true)
	_select_netmode(NET_LOBBY)          # ★ 真实入口：玩家点「公开大厅」切换块走的就是它
	var stay11: bool = _sel_netmode == NET_INVITE
	var st_keep11: bool = _lobby_status != null and _lobby_status.text == st11
	SteamNet.set_force_missing(false)
	var c11: bool = stay11 and st_keep11
	checks.append(["⑪ Steam 不可用时点「公开大厅」⇒ 档不翻、列表不刷｜降级闸", c11,
			"档位=%s（期望 好友联机） 状态行=%s" % [
				_netmode_label(_sel_netmode),
				"未改" if st_keep11 else "「%s」（期望「%s」）" % [
					str(_lobby_status.text if _lobby_status != null else "无"), st11]]])

	# ⑪b 阳性对照：闸之外那一半（`_refresh_lobby_list()`）**真的会动**状态行 ——
	#   没有这条，⑪ 就是"怎么都不动"也绿的恒真式。
	#   ★ 口径不能写成"刷完就有列表"：那要求本机 Steam 真能 init，无 Steam 的机器上恒红
	#     （又一次拿环境当代码）。允许两种结果：有 Steam ⇒「正在搜索对手…」；
	#     没 Steam ⇒「Steam 不可用：…」—— 两者都**不等于**刷之前的文案。
	var st11b: String = _lobby_status.text if _lobby_status != null else ""
	_refresh_lobby_list()
	var c11b: bool = _lobby_status != null and _lobby_status.text != st11b
	checks.append(["⑪b 阳性对照：闸之外那半段会动状态行｜证明 ⑪ 不是恒真", c11b,
			"状态行「%s」→「%s」" % [st11b, str(_lobby_status.text if _lobby_status != null else "无")]])

	# ⑪c **连点当前档不许把按下态弄丢**（2026-10-08 新增，钉一个真被写进去的坏法）。
	#   `toggle_mode` 的按钮**自己**会把 `button_pressed` 翻面 ⇒ 连点当前档时它会翻成"未按下"，
	#   而 `_select_netmode()` 对同档早退（防连点抖列表）⇒ 若不重派生，玩家看到的是
	#   "当前档看起来没被选中"（"点了没反应"同一家）。这里**故意**把按钮翻成 false 再调一次回调。
	_sel_netmode = NET_INVITE
	_refresh_duel_tabs()
	var b11c: Button = _duel_find_tab_button(NET_INVITE)
	if b11c != null:
		b11c.button_pressed = false          # 模拟 toggle 自翻
		_on_duel_tab_pressed(NET_INVITE)
	var tabs11: Dictionary = _duel_tab_state()
	var c11c: bool = bool(tabs11.get(NET_INVITE, false)) and not bool(tabs11.get(NET_LOBBY, true))
	checks.append(["⑪c 连点当前档 ⇒ 按下态被重新派生｜toggle 自翻不留假象", c11c,
			"按下态=%s（好友联机应 true / 公开大厅应 false）" % str(tabs11)])

	# ── ⑫ 两档切换块的**接线**：从控件树出发找到真按钮、真按一下（不是直呼内部字典）────
	#   ★★ 为什么必须"从控件出发"（rules.md §13⑫ 工具栏接线的同一条纪律）：直呼
	#     `_select_netmode()` 只证明"函数在"，证明不了"按钮真的连着它" —— 而"按钮连错 /
	#     没连"正是"点了没反应"那一族。旧版这里测的是折叠菜单那一瓣的菱形命中测试，
	#     随两瓣一起删除。
	_sel_netmode = NET_INVITE
	_refresh_duel_tabs()
	var btn12: Button = _duel_find_tab_button(NET_LOBBY)
	var found12: bool = btn12 != null
	if found12:
		btn12.emit_signal("pressed")        # ★ 真按：走信号 ⇒ 走真实回调链
	var c12a: bool = found12 and _sel_netmode == NET_LOBBY
	checks.append(["⑫a 从控件树找到「公开大厅」切换块并按它 ⇒ 档位跟着翻｜接线不是靠注释", c12a,
			"找到=%s 按下后档位=%s" % [str(found12), _netmode_label(_sel_netmode)]])
	var tabs12: Dictionary = _duel_tab_state()
	var c12b: bool = _sel_netmode == NET_LOBBY and bool(tabs12.get(NET_LOBBY, false)) \
			and _duel_lobby_box.visible and not _duel_invite_box.visible
	checks.append(["⑫b 按下 ⇒ 档位 + 按下态 + 两块内容一起变｜三个量同一真源", c12b,
			"档位=%s 按下态=%s 大厅块可见=%s 联机块可见=%s" % [
				_netmode_label(_sel_netmode), str(tabs12),
				str(_duel_lobby_box.visible), str(_duel_invite_box.visible)]])
	# ── ⑬ 对弈页页首必须写出「本局棋盘」，且跟着主菜单的选择变 ────────────────
	#   ★ 用户的真实问题（2026-10-21）：「邀请好友在哪里选择棋盘呢？」—— 本页是联机**唯一**
	#     入口，而盘的真源在**主菜单的棋盘行**。不写这一格，玩家要么以为联机页能选盘，
	#     要么以为"我在菜单选的盘就是这局用的盘"—— 而联机的盘实际由**房主**定
	#     （`game.gd::_send_init()` 把顶点/瓷砖/邻接/盘型标记/种子整套下发给加入方）。
	#   ★ 判据必须**真的换一张盘再读**：只断"文本非空"抓不住"写死了第一张盘名"这种坏法。
	var bak13_board: int = _sel_board
	var bak13_size: int = _sel_size
	var sum13a: String = _duel_board_summary()
	var other13: int = GameConfig.BOARD_SNOWFLAKE if bak13_board != GameConfig.BOARD_SNOWFLAKE \
			else GameConfig.BOARD_CUBE
	_select_board(other13)                 # 真实入口：玩家点棋盘瓷砖走的就是它
	_commit_board_pending()                # `_select_board` 只置"待切换"，落定要这一下
	_set_page(PAGE_LOBBY)                  # 重建页 ⇒ `_refresh_duel_header()` 重新派生
	var head13: String = ""
	if _duel_me != null and is_instance_valid(_duel_me):
		head13 = _duel_me.text
	var want13: String = MenuModel.board_label(other13)
	var old13: String = MenuModel.board_label(bak13_board)
	var c13: bool = sum13a != "" and head13.contains(want13) \
			and (old13 == want13 or not head13.contains(old13))
	checks.append(["⑬ 对弈页页首写出本局棋盘｜换盘后跟着变，不是写死的", c13,
			"换盘前摘要=「%s」→ 换盘后页首=「%s」（期望含「%s」）" % [sum13a, head13, want13]])
	# 还原：选择与页面都回到原样（后面的判据与退出都依赖「好友联机」档 + 原盘）
	_select_board(bak13_board)
	_commit_board_pending()
	_sel_size = bak13_size
	_set_page(PAGE_LOBBY)

	# ── ⑭ 本局设置三个下拉：全棋盘列表 / 座位可写 / 爱因斯坦禁用大小 ──────────────
	#   ★ 必须**从控件出发**（同 ⑫a 的纪律）：直接调 `_on_duel_board_pick()` 只证明"函数在"，
	#     证明不了下拉真的连着它 —— "下拉没接线"正是"选了没反应"那一族。
	#   ★ 三件事一起断：① 项数（"全部棋盘" = **启用**盘数，占位「敬请期待」不许进）
	#     ② 选了之后**真源**真的变（`_sel_board` / `GameConfig.seat_choice`）
	#     ③ 爱因斯坦盘下大小下拉必须禁用（它的大小由种类决定）。
	#   ★ 座位表与常量必须一一对上（"索引即常量"）：顺序错了 = 选「我执白」发出黑棋，
	#     而且**一条错都不报**（只是两个人坐反了）。
	var kinds14: Array = MenuModel.enabled_board_kinds()
	var cnt14_board: int = _duel_board_opt.item_count if _duel_board_opt != null and is_instance_valid(_duel_board_opt) else -1
	var cnt14_size: int = _duel_size_opt.item_count if _duel_size_opt != null and is_instance_valid(_duel_size_opt) else -1
	var cnt14_seat: int = _duel_seat_opt.item_count if _duel_seat_opt != null and is_instance_valid(_duel_seat_opt) else -1
	var ok14_n: bool = cnt14_board == kinds14.size() and cnt14_size == MenuModel.slots().size() \
			and cnt14_seat == 3
	var ok14_map: bool = SEAT_PICK_LABELS.size() == 3 and GameConfig.SEAT_BLACK == 0 \
			and GameConfig.SEAT_WHITE == 1 and GameConfig.SEAT_RANDOM == 2
	var bak14_board: int = _sel_board
	var bak14_size: int = _sel_size
	var bak14_seat: int = int(GameConfig.seat_choice)
	var i14_snow: int = -1
	var i14_hat: int = -1
	for i in kinds14.size():
		if int(kinds14[i]["id"]) == GameConfig.BOARD_SNOWFLAKE:
			i14_snow = i
		if int(kinds14[i]["id"]) == GameConfig.BOARD_HAT:
			i14_hat = i
	if i14_snow >= 0 and _duel_board_opt != null and is_instance_valid(_duel_board_opt):
		_duel_board_opt.select(i14_snow)
		_duel_board_opt.item_selected.emit(i14_snow)     # ★ 真选：走控件自己的信号
	var ok14_board: bool = _sel_board == GameConfig.BOARD_SNOWFLAKE
	if _duel_seat_opt != null and is_instance_valid(_duel_seat_opt):
		_duel_seat_opt.select(1)
		_duel_seat_opt.item_selected.emit(1)
	var ok14_seat: bool = int(GameConfig.seat_choice) == GameConfig.SEAT_WHITE
	if i14_hat >= 0 and _duel_board_opt != null and is_instance_valid(_duel_board_opt):
		_duel_board_opt.select(i14_hat)
		_duel_board_opt.item_selected.emit(i14_hat)
	var ok14_dis: bool = _duel_size_opt != null and is_instance_valid(_duel_size_opt) \
			and _duel_size_opt.disabled
	checks.append(["⑭ 本局设置下拉：全棋盘列表 + 座位可写 + 爱因斯坦禁用大小",
			ok14_n and ok14_map and ok14_board and ok14_seat and ok14_dis,
			"项数(棋盘%d/期望%d 大小%d/期望%d 座位%d/期望3) 座位映射=%s 选雪花后=%d 选白后seat=%d 帽子下大小禁用=%s" % [
				cnt14_board, kinds14.size(), cnt14_size, MenuModel.slots().size(), cnt14_seat,
				str(ok14_map), _sel_board, int(GameConfig.seat_choice), str(ok14_dis)]])
	# 还原：选择与页面（后面的判据与退出都依赖「好友联机」档 + 原盘 + 原座位）
	_select_board(bak14_board)
	_commit_board_pending()
	_sel_size = bak14_size
	GameConfig.seat_choice = bak14_seat
	_set_page(PAGE_LOBBY)
	# 复原：档位回「好友联机」、清掉 force_missing，别把状态留给后面的判据/退出
	_sel_netmode = NET_INVITE
	SteamNet.set_force_missing(false)
	_refresh_duel_tabs()
	_refresh_selection()

	var failed: Array = _print_checks("[steamuitest]", checks)
	for s in skipped:
		# ★ 跳过必须**显式打印原因**：静默跳过会伪装成绿（本工程铁律：环境问题不许被吞成通过）。
		print("[steamuitest] 跳过 %s" % str(s))
	print("[steamuitest] 判据 %d 条，失败 %d 条，跳过 %d 条%s" % [checks.size(), failed.size(),
			skipped.size(), "" if failed.is_empty() else "：" + ", ".join(failed)])
	# ★ 判据数必须 > 0 —— 否则"什么都没测"会和"全通过"长得一模一样（手机菜单那次的教训）。
	var pass_all: bool = failed.is_empty() and checks.size() > 0
	print("[steamuitest] 结论：", "通过 ✓" if pass_all else "失败 ✗")
	print("[steamuitest] 耗时 %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


## 探测仪器（**不是自检**）：--steamp2p。
## ★ 与 `--steamtest` 的分工：那边判「代码对不对」，这边量「平台能不能」——
##   「同一 Steam 账号 + 同一台机器的两个进程能不能自环 P2P」是个**平台事实**，
##   它决定 Step 2 的自检能做到哪一层（真双进程 e2e / 还是只能测到"发送调用成功"）。
##   ⇒ 因此它**不进** `GAME_TESTS`/`MENU_TESTS`、不参与通过失败判定（写成判据会变成
##     一条永远红的假信号："自环不通"多半是 Steam 的平台限制而不是本工程代码错）。
func _steam_p2p_probe() -> void:
	print("[steamp2p] 开始（同账号自环 P2P 可行性探测，非判据）")
	var r: Dictionary = await SteamNet.probe_p2p_self()
	for ln in (r.get("lines", []) as Array):
		print("[steamp2p] %s" % str(ln))
	print("[steamp2p] 结论：%s" % str(r.get("verdict", "")))
	get_tree().quit()


func _ready() -> void:
	# ⚰️ 2026-10-17 墓碑（名字不许回收）：这里原有**手机菜单路由**（`use_mobile_menu()`
	#   → `menu_mobile.tscn` 延迟切场景）。手机版已搁置 ⇒ 整套退役：
	#   `menu_mobile.gd` / `menu_mobile.tscn` / `GameConfig.use_mobile_menu()` /
	#   `mobile_menu_override` / `--mobileui` flag 全部删除。
	#   `menu_model.gd` **未删**（桌面菜单仍依赖它的 BOARD_KINDS / slots() / 标签函数）。
	#   重启手机版时必须**重写**（旧实现只在备份里：`_瘦身备份_2026-10-17/menu_mobile.gd`）。
	# 注意：背景在 _draw() 内绘制，不能做成铺满全屏的子节点，
	# 否则会覆盖（压在）本节点的 _draw() 内容（瓷砖）之上。

	# ★ 2026-09-30 §24 第 5 步：这里原有 `--mmtest`（headless 联机信令自检：验证 Godot 的
	#   HTTP 客户端能向自建信令服建房拿码、并凭码取回房主端点）。信令服与整条码流程都删了，
	#   这条自检没有可测对象 —— 删除。它对应的回归清单项 `mmtest` 也一并从 `regress.sh` 摘掉。

	# 外观配色（user://appearance.cfg 持久化；菜单与对局共用同一套）
	GameConfig.load_appearance()
	_apply_appearance()

	# 诊断：`--steamdiag` —— 「Steam 到底缺哪一层」，逐层体检后退出。
	# ★ 专给"另一台机器上报『Steam 不可用』"用：一条命令把猜测变成能截图核对的分层报告
	#   （缺 addons / 缺 dll / 引擎版本过低 / 库被拦，四种成因处置方式完全不同）。
	#   放在 `--apprt` 之后：此时外观已加载，但**还没建 UI、没碰用户配置**。
	if "--steamdiag" in _argv():
		print("[steamdiag] is_plugin_present=", SteamNet.is_plugin_present())
		print("[steamdiag] 报告：", SteamNet.diag_report())
		var okd: bool = SteamNet.ensure_init()
		print("[steamdiag] ensure_init=", okd, " state=", SteamNet.state(),
				" reason=", SteamNet.reason(), " 版本=", str(SteamNet.info().get("godotsteam_version", "")))
		SteamNet.shutdown_steam()
		get_tree().quit()
		return

	# 自检：--apprt「外观·对局往返」—— 必须放在 load/apply **之后**，测的才是"回到菜单这一刻"的状态
	if "--apprt" in _argv():
		_appearance_round_trip_test()
		return

	# 标题
	_title = Label.new()
	_title.text = "瓷砖围棋"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 60)
	_title.add_theme_color_override("font_color", _accent)
	# ★ 2026-10-13 重设计：主标题是全工程唯一的 L1「展示级」元素，给它**展示字体**
	#   （霞鹜文楷，楷体）。正文与控件保持黑体（主题默认）——中文 13–22px 用楷体笔画
	#   密度太高会糊，所以楷体只上大字，不当全局默认。
	#   走 override 而非改主题类型绑定，是有意让"哪些控件用展示字体"成为一处显式清单。
	UITheme.apply_display_font(_title, GameConfig.use_portrait_canvas())
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 26.0
	_title.offset_bottom = TOP_MARGIN
	add_child(_title)

	# **回到菜单时恢复上一局的选项**（2026-09-19 用户要求：下完棋返回菜单要保留上次的选项）。
	# 必须在 `_set_page(PAGE_MAIN)` **之前** —— 页面是按 `_sel_*` 构建的
	#（⚰️ 2026-10-16：这里原还有一句"`_set_page` 末尾的 `_snap_board_row()` 要按选中棋盘把
	#  循环行停到对应槽位" —— 随轮播整族删除；【先恢复状态、再建页】这条次序**没变**，
	#  它本来就是因为"页面按 `_sel_*` 构建"才成立的）。
	# 放到后面就会出现「先画默认、再改状态」的分叉（凹陷态停在彭罗斯但开局用雪花）。
	# 自动化运行不恢复（见 `_is_automated_run` 的说明）。
	if not _is_automated_run():
		_restore_last_match()

	_set_page(PAGE_MAIN)

	# 好友邀请落地（详见 `_bootstrap_steam_invites`）：延后一帧，别卡住菜单首次绘制。
	_bootstrap_steam_invites.call_deferred()

	# 联机启动失败提示（由 game.tscn 写入，显示后清空）
	if GameConfig.connection_error != "":
		_show_error_toast(GameConfig.connection_error)
		GameConfig.connection_error = ""


	# 调试/截图：--select=<瓷砖文字> 预置一个选择（如 彭罗斯 / 立方体 / 磐石 / 疾风），
	# 便于截取「二级行展开」等状态；须放在 -- 之后，常与 --screenshot 搭配使用。
	# 支持多个 `--select=`（按出现顺序依次执行），用于截取需要"二级选择"的状态。
	# ⚠️ 名字是**当前显示名**（`_mode_label()` 那一份）：2026-10-15b 起「人机」叫「磐石」，
	#   旧脚本里写 `--select=人机` 会走进 `_auto_select()` 的"未找到同名瓷砖"分支（只是 push_warning，
	#   不报红）⇒ 截出来的图看着正常但状态没预置上。改名前先 grep 一遍 `--select=`。
	for ua in _argv():
		if ua.begins_with("--select="):
			_auto_select(ua.substr(9))

	# 调试/截图：--shotpage=settings 先切到设置页再截图（设置页是原生控件，只能靠真机截图审外观）
	# `--shotpage=quit`：先弹出 ESC 退出确认面板再截 —— 与 game.gd 的 `--screenshot --pause`
	# 同一思路：这两个面板都是**原生控件**（PanelContainer/Button），headless 下截不到，
	# 而「字看不清 / 没居中」这类问题断言抓不到（能断言颜色与坐标，好不好看必须看图）。
	for ua in _argv():
		if ua == "--shotpage=settings":
			_set_page(PAGE_SETTINGS)
			break
		if ua == "--shotpage=quit":
			_show_quit_confirm()
			break
		if ua == "--shotpage=lobby":
			# 联机大厅面板（含"有对手"与"空列表"两态，见 _menu_shot_lobby 注释）
			_menu_shot_lobby()
			break

		if ua == "--shotpage=records":
			# 棋谱**面板**（2026-10-02 新增；2026-10-04 第四版从"独立页"改成主菜单的一个
			# 面板 —— 底栏四块在它上面照样在，所以这里必须跑布局，否则截不到底栏）
			_set_page(PAGE_RECORDS)
			_layout_setup()
			break
		if ua == "--shotpage=lobbypage":
			# 对弈面板（与上面的 `=lobby` 不同：那是叠在练习面板上的联机大厅面板）
			_set_page(PAGE_LOBBY)
			_layout_setup()
			break
	# 调试/截图：`--shotspin=<相位>` 把**背景旋转**定格在指定相位再截（0=不转、0.25=摆到最大角）。
	# ★ 为什么必须有这个夹具：背景旋转是个**随时间推进**的量，而 `--screenshot` 拍到的是
	#   "第几帧" —— 不钉相位就永远拍不到"摆到最大角"那一档，也就无法目检
	#   "转到底的时候盘形边界会不会扫进屏幕/渐隐圆盘会不会与盘形错开"。
	#   ★ 而这两件事**头less 拿不到像素** ⇒ 只能定格 + 看图。
	# ⚠️ 定格方式：写 `_bg_spin` 并置 `_bg_frozen`，让 `_process` 不再推进它
	#   （只写一次相位不够 —— 拍图前还会跑几百帧，相位早跑掉了）。
	# ★ 同时把 `_bg_drift` 归零：A/B 两帧之间**只允许差一个旋转角**，
	#   否则反解出来的角度里混着一次未知平移（见 `_bg_frozen` 的说明）。
	for ua3 in _argv():
		if ua3.begins_with("--shotspin="):
			var ph: float = float(ua3.split("=")[1])
			_bg_spin = clampf(ph, 0.0, 1.0)
			_bg_drift = 0.0
			_bg_frozen = true
			queue_redraw()
			break
	# 与上一条配套：`--shotpage=settings --shotdrop` 把设置页试摆盘定格成
	# 「第 3 格挂着悬浮预览 + 第 0 格棋子正落到半途」，用于**目检**菜单侧的悬浮/下落
	# （与 game.gd 的 `--screenshot --shotdrop` 同一思路：headless 断言只保证几何与透明度，
	#  「能不能看出它在浮动、会不会跟真棋子分不清」只能看图）。
	if "--shotdrop" in _argv():
		_menu_shot_drop()

	# 与上面两条同一族：`--shotpage=records --shotcheck=<n>` 把当前页前 n 个「勾选类」控件
	# 置为**已勾选**再截 —— 用于**目检**"勾压在方块上到底看不看得清"（设置页两个开关默认关、
	# 棋谱页 402 个勾选框默认不勾 ⇒ 此前这类状态的截图样本恒为 0）。理由与三条纪律见函数头。
	# ⚠️ 必须排在 `--shotpage=` 那一段**之后**：控件得先随页面建出来才有得勾。
	for ua4 in _argv():
		if ua4.begins_with("--shotcheck"):
			var n4: int = 1
			if ua4.contains("="):
				n4 = maxi(1, int(ua4.split("=")[1]))
			_menu_shot_check(n4)
			break

	# 自检：--portraittest 菜单竖屏布局（行带收敛 / 瓷砖顶满宽度 / 视口内 / 净空 + 阴性对照）。
	# ★ 必须配 `--winsize=720x1560` 用真窗口跑 —— headless 物理窗恒为 1152×1152 正方，
	#   拿不到竖屏（见函数头注释）。
	if "--portraittest" in _argv():
		_portrait_self_test()
	# 自检：--modeltest 共享数据层 MenuModel（两个菜单共用的槽位语义 / 有效选择 / 恢复校验）
	if "--modeltest" in _argv():
		_model_self_test()

	if "--screenshot" in _argv():
		_capture_and_quit()

	# ---- 自检：--gatediag 外观**脏标记门**的双向验证（2026-10-20 第 0 步）----
	# ★ 为什么要这条：门的作用是"拦住不该写的写"，而**拦住**这件事没有观测量 ——
	#   不写文件跟"本来就没写"在文件层面长得一模一样。所以必须主动制造一次写企图：
	#     ① 未置脏 ⇒ 必须被挡（blocked +1、文件字节不变）；
	#     ② 置脏后 ⇒ 必须放行（blocked 不变、文件内容确实变了）。
	#   两个方向缺一不可：只测 ① 的话，"门把功能一起挡死"也能满足它。
	# ★★ 本自检会**真的写一次用户文件** ⇒ 开头备份字节、结尾原样写回，跑完必须逐字节还原。
	#   所以在任何自动化批跑里都可以安全复跑（不会留下痕迹）。
	if "--gatediag" in _argv():
		var user_path: String = ProjectSettings.globalize_path(GameConfig.APPEARANCE_PATH)
		var before: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
		var b0: int = GameConfig._appearance_save_blocked
		GameConfig.save_appearance()                     # ① 未置脏
		var b1: int = GameConfig._appearance_save_blocked
		var mid: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
		GameConfig.mark_appearance_dirty()
		GameConfig.save_appearance()                     # ② 置脏后
		var b2: int = GameConfig._appearance_save_blocked
		var after: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
		# 还原用户文件（逐字节）。★★ 必须防"备份为空"：`before` 读失败时是空数组，
		#   `store_buffer(空)` 会把用户配置**清成 0 字节** —— 自检自己成了破坏者
		#   （2026-10-20 本轮真实踩到：跑到一半发现 appearance.cfg 变 0 字节）。
		var ok_restore: bool = false
		if before.is_empty():
			print("[gatediag] ✗ 备份为空（读不到用户配置？）⇒ **跳过还原**，绝不用空内容覆盖它")
		else:
			var f := FileAccess.open(user_path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(before)
				f.close()
			ok_restore = FileAccess.get_file_as_bytes(user_path) == before
		var ok_block: bool = b1 == b0 + 1 and mid == before
		var ok_pass: bool = b2 == b1 and after != before
		var ok: bool = ok_block and ok_pass and ok_restore and not before.is_empty()
		print("[gatediag] ① 未置脏 ⇒ 挡住 %s（blocked %d→%d，文件字节未变=%s）" % [
			"✓" if ok_block else "✗", b0, b1, str(mid == before)])
		print("[gatediag] ② 置脏后 ⇒ 放行 %s（blocked %d→%d，文件确实被写=%s）" % [
			"✓" if ok_pass else "✗", b1, b2, str(after != before)])
		print("[gatediag] ③ 用户文件逐字节还原 %s" % ["✓" if ok_restore else "✗"])
		print("[gatediag] 结论：", "通过 ✓" if ok else "失败 ✗")
		get_tree().quit()
		return
	# headless 外观自检：--apptest 构建设置页外观控件 → 应用预设 → 存盘 → 改内存 → 读回校验
	if "--apptest" in _argv():
		_run_appearance_self_test()
	# 自检：--labeltest 折叠子项（棋盘大小三档）标签间距。
	# 为什么需要它：标签位置是纯几何计算，headless 下又截不了图（截图要等
	# RenderingServer.frame_post_draw，dummy 渲染器永远不发射 → 挂到超时）。
	# 所以改成直接量「文字框之间的净间距」，既能验证散开效果，也能防以后排版改回去又挤在一起。
	if "--vpprobe" in _argv():
		_vp_probe()
		return
	if "--labeltest" in _argv():
		_label_spacing_test()
	# 自检：--settest 设置页分栏布局量化（左预览 / 右内容，防「横向拉太长、预览太小」回归）
	if "--settest" in _argv():
		_settings_layout_test()
	# 自检：--boardtest 棋盘类型切换的收回/展开动画
	if "--boardtest" in _argv():
		_board_fold_test()
	# ★ 2026-09-30 §24 第 5 步：这里原有 `--netmodetest`（联机方式状态机）。
	#   它整个是围绕「随机匹配选中即进队列 ⇒ 停下后必须复位」建的，随机匹配删除后无对象可测。
	# 自检：--esctest ESC 退出确认面板（模拟按键事件，不碰真实输入设备）
	if "--esctest" in _argv():
		_esc_test()
	# 自检：--einsteintest 爱因斯坦（帽子家族）那一槽位的二级行＝种类行（帽子/海龟/幽灵）
	if "--einsteintest" in _argv():
		_einstein_kind_test()
	# 自检：--lastmatchtest 「上一局选项」的落盘→读回→应用到菜单状态闭环（用独立路径，不碰用户配置）
	if "--lastmatchtest" in _argv():
		_last_match_test()
	# 自检：--recordtest 联机战绩（user://record.cfg）落盘→读回→胜率计算闭环（独立路径，不碰用户战绩）
	if "--recordtest" in _argv():
		_record_test()
	# 自检：--menutest 主菜单重设计（首页四入口 / 可展开快速设置 / 背景棋盘联动 / 页面系统）
	#   ★ flag 名**不要**与既有菜单自检撞（boardtest/labeltest/settest/apptest/esctest/
	#     einsteintest/lastmatchtest/cursortest/steamtest/steamuitest/recordtest
	#     已占用）—— 同前缀会让 regress.sh 的「自检压根没跑」哨兵失效。
	#   ★ 2026-10-02：「棋盘预览卡」整建制删除 ⇒ `previewtest` 也从"已占用"这份名单里退出了，
	#     但**别回收这个名字**：旧回归日志与旧记忆件里都还写着它，回收会让"旧日志说跑过、
	#     新清单里查不到"变成一件需要考古的事 —— 而消掉这种考古成本正是本轮在做的事。
	if "--menutest" in _argv():
		_menu_layout_self_test()
	# 自检：--rectest 棋谱库面板（列表 / 搜索 / 排序 / 勾选 / 删除 / 导出 SGF / 导出导入 JSON /
	#   进复盘的交接）。★ 全在自检盘上跑（`records_selftest`），不碰玩家的棋谱库。
	if "--rectest" in _argv():
		_records_ui_self_test()
	# 自检：--musictest 音乐系统（music.gd：拨弦合成 / 固定节拍 / 和声随战况）。
	#   ★ 判据体在 `Music.run_selftest()` 里 —— 合成器与调度的细节只有音乐引擎自己知道；
	#     这里只负责「触发 + 统一打印 + 退出」，与 `--steamtest` 的分工一致。
	#   ★ 它**不带游戏场景**（铁律 2 的菜单侧口径）："战况读数"那一半在菜单场景下走
	#     **降级路径**（判据 ⑧），另有一条**静态**契约判据（⑦）守 game.gd 的字段名
	#     —— 那个文件正被另一个会话改着，一个字节都不能碰。
	#   ★ 可选参数：`--musicdump=<绝对路径>`（落一份验收 wav，供人耳 +
	#     工作区 Python 做独立频谱验证）、`--musiccontract=<路径>`（把 ⑦ 指向别的文件，
	#     供阴性对照在不碰 game.gd 的前提下证明这条判据有牙齿）。
	if "--musictest" in _argv():
		_music_self_test()
	# 自检：--cursortest 自定义鼠标光标（三角刮刀）的素材与热区。
	# ⚠️ headless 下**没有光标渲染**，所以这里只验「素材 + 几何」这一半；
	#    「看起来对不对 / 大小合不合适」必须人眼看（详见 `_cursor_self_test` 的说明）。
	if "--cursortest" in _argv():
		_cursor_self_test()
	# 自检：--steamtest Steam 联机封装（steam_net.gd）：可用性探测 / 优雅降级 / 常量口径 /
	#   lobby 端到端。★ 不依赖游戏场景 ⇒ 放菜单侧（守「菜单侧自检不带 res://game.tscn」）。
	#   ⚠️ 需要真实 Steam 客户端在运行；环境不可用时输出会明说，不会静默变绿。
	if "--steamtest" in _argv():
		_steam_self_test()

	# 自检：--steamuitest 菜单侧「联机通道」二选一 + Steam 大厅 UI（§21 第 3 步）。
	# ★ 不带 `res://game.tscn`（菜单侧自检的铁律）；全程**不联网、不改场景** ——
	#   "有没有请求转场 / 有没有写参数"靠 `_join_snap()` 的**点前点后快照比对**来守
	#   （不是"点完之后是不是转场中"：那写法一旦前面漏过一次就恒真，见该函数的说明）。
	# ★ 环境无关：Steam 插件缺失那一层用 `SteamNet.set_force_missing()` **强制复现**，
	#   所以没装 Steam 的机器上它也照样有牙齿；只有最后一条真环境判据会**明说跳过**。
	if "--steamuitest" in _argv():
		# ★ 刻意**不** await：判据 ⑫a/⑫b 全部同步可判（命中测试 + 直呼回调 + 读标记）。
		#   曾经写成 `await` 是因为想走 `_input()` 的合成点击，而它内部带 await；
		#   那条路已放弃（"await 链一断，整函数连 quit() 一起消失"，实测判据一条都打不出来）。
		#   合成点击那层改由 ⑫a 的 `_tile_at_point()` 守住 —— 它就是 `_input()` 判定用的
		#   那个函数，验它等于验"点得中"，且不引入 await。
		_steam_ui_self_test()

	# 探测仪器：--steamp2p 量「同一账号同机能不能自环 P2P」—— 决定 Step 2 的验证能做到哪一层。
	# ★ **不是自检**：不进 GAME_TESTS/MENU_TESTS，不判通过/失败（见函数头的说明）。
	if "--steamp2p" in _argv():
		_steam_p2p_probe()

# ====== 页面 / 瓷砖布局 ======
## 清空「上一页留下的全部菜单侧状态」——**唯一入口**（`_set_page()` 第一件事）。
##
## ★★ 为什么必须收成一处（2026-10-02 实测的坑）：这些成员是**一起**被重建的，而
##   "手写一列 `clear()`"本身是个**清空点也是写点**的地方 —— 成员变多时，新加的那个
##   会被**静默漏掉**（清了五样，看起来该清的都清了）。当轮实测漏的正是 `_board_slots`：
##   它每一项带的是 `_items` 的**下标**，而下一页的 `_items` 长度可能远小于上一页
##   ⇒ `_draw()` 里 `_items[int(s["i"])]` 每帧一条 **Out of bounds**
##   （实测切到棋谱库页后 46 条/张截图），而 `_page` 是对的、`_items` 里那条记录也在。
##   ⚠️ 为什么它特别容易漏：`_board_slots` 只在**棋盘行的布局**里被重填，而非主菜单页
##     压根不跑那段 ⇒ 它一直留着上一页的下标（没人"忘记赋值"，是**没人赋值**）。
##   ⇒ 加成员时只改这一个函数。
##   ★ 守卫 S52a 钉"调用点唯一"、S52b 钉"`_items` 真的被清"。
##   ⚰️ 2026-10-16：那串下标链（`_board_slots`）随棋盘行改静态平铺整族删除，
##      对应的一半运行时判据（原 `--menutest` ⑥c「切页后槽位下标仍在范围内」）一并退役 ——
##      理由与本函数的立场**不冲突**：这里守的仍是"新成员只改这一处"，
##      只是当前清单恰好少了一样。回潮由 FORBID **S54c** 禁止。
func _forget_menu_items() -> void:
	_items.clear()
	_section_labels.clear()
	# ⚰️ 2026-10-12：这里原有 `_stones` / `_stone_anims` / `_stone_outs` 三行 `clear()`
	#   —— 随黑砖族整族删除。⚠️ 本条注释留着是给下一个加成员的人看的：
	#   本函数是"上一页留下的菜单侧状态"的**唯一清空入口**（见上面的说明），
	#   新加成员**只改这一处**。
	# ★ 2026-10-04 v4：这里原有 `_back_anim = 0.0`（设置页「返回」按钮的落子动画）——
	#   那一族已整族删除，清空点随之少一样。
	# ⚰️ 2026-10-16：这里原有 `_board_slots.clear()`（循环行的槽位下标链）—— 同上，整族退役。

func _set_page(page: int) -> void:
	_page = page
	# 页面重建是硬切，没有动画可依附 → 待切换的棋盘类型立即落定，避免凹陷态与实际开局不一致
	if _board_pending >= 0:
		_sel_board = _board_pending
		_board_pending = -1
	_forget_menu_items()          # 上一页的条目/下标/棋子一起清（见该函数的说明）
	_clear_settings_ui()          # 切换页面时销毁上一页的原生设置控件（若有）
	_clear_records_ui()           # 棋谱面板的原生控件树同理（两个面板不会同时在，但两处都要清）
	_clear_duel_ui()             # 对弈页（联机大厅）的原生控件树同理（三个面板不会同时在，但三处都要清）
	var descriptors: Array[Dictionary] = []
	match page:
		PAGE_MAIN:
			_title.text = "瓷砖围棋"
			# 棋盘类型（横排循环行，顺序与条目全部来自 BOARD_KINDS）
			for kind in BOARD_KINDS:
				var kid: int = int(kind["id"])
				var k_en: bool = bool(kind["enabled"])
				var k_lbl: String = str(kind["label"])
				var k_cb: Callable = (func() -> void: _select_board(kid)) if k_en \
					else (func() -> void: _show_error_toast("「%s」还在开发中，敬请期待" % k_lbl))
				descriptors.append({"label": k_lbl, "group": "board", "sel": k_en and _sel_board == kid,
					"cb": k_cb, "disabled": not k_en})
			# 二级行（紧贴选中块外侧折叠展开，仿「人机+三难度」结构；循环行里每一项都有 → 恒开）。
			# ★★ 这一行有**两种含义**，由「有效选中的棋盘」决定 ——
			#   · 普通棋盘 = 棋盘大小三档（全局槽位 RANDOM/STANDARD/ENHANCED）。槽位 0 的显示名
			#     随棋盘类型变：只剩筝形盘没有随机档 → 它下面槽位 0 是「迷你」固定盘（R=2，72 格），
			#     其余棋盘都显示「随机」（雪花 2026-09-16、爱因斯坦 2026-09-19 起都有真随机档；
			#     「迷你」固定档仍可用 --snowmini 等 flag 钉层数/R 取到）。
			#   · 爱因斯坦 = **种类三档（帽子/海龟/幽灵）** —— 它只适合做随机盘（约 200 格），
			#     大小三档对它没有意义，正好把这一行让给「种类」（用户口径：三个种类都是随机约 200 格）。
			# 两者复用同一套折叠机制（同一个 group 名 "boardsize" + 同样 3 个槽位），所以布局 /
			# 折叠动画 / 标签放射散布 / --labeltest 全都不用改；差别只有 label 与 size_id 的含义
			# （回调已统一成 `_activate_size_slot` —— 它是「点的第几个槽位」，含义在点击时现判）。
			# 每一项都带 size_id，选中匹配与布局收集都按 size_id 走（标签会随棋盘变，不能按字面匹配）。
			# ★★ 二级行的三个槽位：标签 / 选中态 / 回调**全部走同一个「槽位」口径**
			#    （`_size_slot_label()` / `_size_slot_selected()` / `_activate_size_slot()`），
			#    这里不再按棋盘分叉各写一套。
			#    ⚠️ 为什么必须这样（2026-09-19 用户报的两个 bug，**同一个根因**）：
			#    这一行是「同一组物理瓷砖、两种含义」，而页面**只在 _set_page 重建**；
			#    用户点棋盘类型只走 `_refresh_selection()`，原实现在那里**只改写 `label`、不动 `cb`** →
			#      · 先在彭罗斯下建行（cb = _select_size）、再切到爱因斯坦：字变成了「帽子/海龟/幽灵」，
			#        回调还是 `_select_size` → **点种类毫无反应**（`_sel_hatkind` 永不变，凹陷态停在帽子）；
			#      · 反向（爱因斯坦 → 彭罗斯）更直白：非种类分支只改写槽位 0 的标签，
			#        槽位 1/2 留着「海龟/幽灵」→ **其他棋盘的标准/加强被"改名"**。
			#    根因一句话：**行的语义随棋盘变了，回调却没跟着变**。
			#    现在回调是「激活第 slot 个槽位」，含义在**点击那一刻**由 `_is_hat_eff()` 现判 ——
			#    与标签用同一个判据 → 两者结构上不可能再打架。
			#    （两种含义都恰好 3 个槽位：槽位号 0/1/2 同时是 RANDOM/STANDARD/ENHANCED 与三个种类 id；
			#     `--einsteintest` 里钉了「HAT_KINDS 恰好 3 项」，将来加种类必须同时改这里。）
			for slot in [GameConfig.RANDOM, GameConfig.STANDARD, GameConfig.ENHANCED]:
				descriptors.append({"label": _size_slot_label(slot), "size_id": slot,
					"group": "boardsize", "sel": _size_slot_selected(slot),
					"cb": Callable(self, "_activate_size_slot").bind(slot), "disabled": false})
			# ★ 2026-10-09：这里原有「难度三档建项（group = "diff"，靠 `_diff_t` 折叠展开）」——
			#   按用户口令「人机难度不要折叠菜单，直接和本地按钮并列平铺」整段**下移**到
			#   「对战方式」行里（见下面 本地/人机 之后那三行），group 一并改成 "mode"。
			# 对战方式（顺序固定为 本地/人机/简单/普通/困难，与 `_items` 插入顺序一致 ——
			# 通用排布分支就是按这个顺序从左到右摆的）。
			# ★★★ 2026-10-08：**「线上」这一档整族删除**（用户口令「把主菜单的好友联机也搬到
			#   联机大厅里」）—— 联机现在只有「对弈」页一个入口，练习面板只管本地/磐石/疾风。
			#   这不是"少一个选项"，而是把**双入口收成单入口**：
			#     · 原来选「线上」会展开 netmode 两瓣 + 在左侧浮层里画建房/大厅面板，
			#       且它的「开始」是**禁用**的（联机开局必须走那些面板）；
			#     · 现在这些全部搬进「对弈」页（两档切换块 + 建房/加入 + 大厅列表），
			#       练习面板的「开始」**永远可用**（只服务本地 / 人机）。
			#   ⚠️ 连带三处（改这里必须一起动，否则是静默坏法）：
			#     ① `_push_board_choice()` 里那句"非联机就复位 `GameConfig.online`" ——
			#        判据从 `_sel_mode != MODE_ONLINE`（删掉线上后**恒真**）改成
			#        `GameConfig.mode != MODE_ONLINE`：不改的话，联机建房时刚设好的
			#        `online = true` 会被立刻抹掉 ⇒ **静默变成单机局**；
			#     ② `_net_t` / `_net_target` / netmode 两瓣的折叠动画、标签避让、几何判据
			#        **整族删除**（`--labeltest` 的 [联机方式] 段与 `--steamuitest` ⑫a/⑫b 同步改写）；
			#     ③ 结构守卫 S63（"抬升必须加在放射散开之后"）随两瓣一起退役，
			#        改由墓碑守卫禁止 `_net_*` 族回潮（见 struct_guard.py）。
			# ★ 2026-10-09：身份字段 `mode_id` + `sel` **同出一源**（`_mode_tile_selected()`）
			#   —— 原先 `sel` 就地写表达式、`_refresh_selection()` 另按 label 认一遍，两处口径
			#   分裂，结局就是"点难度后一个实心块都不剩"（`--menutest` ⑭ 逮到的那条）。
			#   见 `_mode_tile_selected()` 的注。
			# ★★ 2026-10-12：难度三档（简单/普通/困难）**整族删除**（用户口令「对战方式那里
			#   只留本地、人机两个选项，人机默认最难，不需选择难度」）。连带删除的：
			#     · `diff_id` 身份字段（本行的每一块都是"整个对局方式"，不再有"哪一档"）；
			#     · `_select_diff()`（它存在的唯一理由是"点难度要连带切到人机"）；
			#     · `_refresh_selection()` 的 `"mode"` 臂里那条 `diff_id >= 0` 分支。
			#   ⚠️ 本行现在恰好 3 块，**等大、居中**（用户口令「保持和其它行一样大，只居中」）——
			#     半径走 `_row_fit(cnt, tileR)` 而它是"先保半径"的 ⇒ 块数与棋盘行一致时
			#     半径逐像素相同（`--labeltest` 的 [对齐] 一直断这条）。
			# ★★ 2026-10-15b：三块的 `label` 一律走 `_mode_label()` 单一真源，别就地写字符串 ——
			#   本轮「人机」改名「磐石」，就地写就意味着"改名必须记得改这里 + 日志那处 + 手机那处"，
			#   而漏改的症状是**静默**的：`_auto_select()` / `--select=` / ⑭ 的样本都按 label 认瓷砖，
			#   名字对不上时它们只会"找不到那块瓷砖"（见 `_auto_select()` 的 push_warning）。
			descriptors.append({"label": _mode_label(MODE_LOCAL), "group": "mode", "mode_id": MODE_LOCAL,
				"sel": _mode_tile_selected(MODE_LOCAL),
				"cb": func() -> void: _select_mode(MODE_LOCAL), "disabled": false})
			# ★ 2026-10-15b：本块显示名 **「磐石」**（原名「人机」，用户口令「人机这个名字和疾风
			#   也不搭，你再改个名字」）。取名口径：与「疾风」一动一静（风 / 石），同为 2 字
			#   ⇒ 本行三块等大居中（走 `_row_fit()`）的几何口径**一行都不用动**；
			#   且名副其实 —— 生产引擎 30~80ms/手、17 个特征，风格稳而扎实，与骨架的"快而激进"相对。
			#   ⚠️ 它仍**不是难度档**：20 局对骨架 14:6 但目差仅 +9.1（t=0.84 不显著）⇒ 两者同档，
			#     两个名字都只描述**风格**，不描述强弱（叫难度会误导）。
			descriptors.append({"label": _mode_label(MODE_VS_AI), "group": "mode", "mode_id": MODE_VS_AI,
				"sel": _mode_tile_selected(MODE_VS_AI),
				"cb": func() -> void: _select_mode(MODE_VS_AI), "disabled": false})
			# ★ 2026-10-14：「测试AI」立项 —— 白方由图围棋骨架（第三套实现，1 手贪心）接管，
			#   给用户亲测骨架棋力。`mode_id` 仍是身份字段、`sel` 仍走 `_mode_tile_selected()`
			#   同一源；`GameConfig.mode` 只会落 VS_AI（骨架标记走 `GameConfig.xg_opponent`）。
			# ★★ 2026-10-15 转正（用户口令「把测试AI也划为正式吧」）⇒ 定名 **「疾风」**：
			#   · 与「本地」「磐石」同为 **2 字** —— 本行三块等大居中（走 `_row_fit()`），
			#     4 字的"测试AI"会把块宽和字重排；换成 2 字则几何口径一行都不用动；
			#   · 名副其实：骨架引擎实测 **0.75ms/手**（生产 30~80ms），风格快而激进（吃子优先）；
			#   · **不叫"简单/困难"** —— 20 局对生产 14:6 但目差仅 +9.1（t=0.84 不显著）
			#     ⇒ 两者**同档**，名字只描述**风格**（快），不描述强弱（叫难度会误导）。
			descriptors.append({"label": _mode_label(MODE_XGAI), "group": "mode", "mode_id": MODE_XGAI,
				"sel": _mode_tile_selected(MODE_XGAI),
				"cb": func() -> void: _select_mode(MODE_XGAI), "disabled": false})
			# ★ 2026-10-22 第四块「流水」（渗流引擎 `LiushuiAI`）。身份仍是 `mode_id`，
			#   `sel` 仍走 `_mode_tile_selected()` 同一源（结构上不可能两块同时亮）。
			#   ⚠️ 本行块数 3 ⇒ **4**：`_row_fit(cnt, tileR)` 是"先保半径"的，块数一旦与棋盘行
			#     不一致，半径就不再逐像素相同 —— `--labeltest` 的 [对齐] 段与 `--menutest` ⑭
			#     必须重跑（⑭ 的样本数是**现数**，不拍常数；[对齐] 若报红属预期，见该段注）。
			#   取名口径与前三块一致（2 字、描述**风格**不描述强弱）：「流水」= 势场漫延、
			#     渗流连通，与「磐石」的稳、「疾风」的快相对。
			descriptors.append({"label": _mode_label(MODE_LIUSHUI), "group": "mode", "mode_id": MODE_LIUSHUI,
				"sel": _mode_tile_selected(MODE_LIUSHUI),
				"cb": func() -> void: _select_mode(MODE_LIUSHUI), "disabled": false})
			# ★ 2026-10-23 第五块「野马」（神经网络先验引擎 `YemaAI`）。同样是 `mode_id` 身份，
			#   `sel` 走 `_mode_tile_selected()` 同一源。名字 2 字，与其余四块等大（`_row_fit()`）。
			descriptors.append({"label": _mode_label(MODE_YEMA), "group": "mode", "mode_id": MODE_YEMA,
				"sel": _mode_tile_selected(MODE_YEMA),
				"cb": func() -> void: _select_mode(MODE_YEMA), "disabled": false})
			# ⚰️ 2026-10-13 墓碑（名字不许回收）：这里原有第三块「Ludii」
			#   （`mode_id = MODE_LUDII`，`sel` 走 `_mode_tile_selected()` 同一条口径 ——
			#   身份由 `mode_id` 认，从不按 label 认，那是 2026-10-12「点难度后实心块全灭」的教训）。
			#   用户口令「彻底砍掉 Ludii」⇒ 整族删除，本行那时回到 **2 块**（本地 / 人机）；
			#   2026-10-15b 起为 **3 块**（本地 / 磐石 / 疾风，全部并列互斥）。
			#   ⚠️ 块数变了 ⇒ `--labeltest` 的 [对齐] 段与 `--menutest` ⑭ 的样本都要跟着改；
			#     好消息是这两处现在都是**现数**（读 `_items` / 读实际块数），不再拍常数。
			# ⚰️ 2026-10-12 墓碑（本行内，名字不许回收）：这里原有「简单 / 普通 / 困难」三块
			#   难度瓷砖（2026-10-09 从独立 group `"diff"` 平铺进来的那一族）。
			# 开始（本地 / 磐石 / 疾风都可用；**联机不走这里** —— 它有自己的页与自己的开局入口：
			# 「对弈」页的「Steam 建房并进入」/「加入」，两处都直接写 `GameConfig` 再转场）
			descriptors.append({"label": "开始", "group": "action", "sel": false, "cb": _start_from_setup, "disabled": false})

			# ====== 底部一行四入口：四个面板共用**同一份**（2026-10-04 第四版）======
			# ★★ 用户口令「主菜单底栏四按钮**固定在主菜单不动**，上面的空间用来切换面板，
			#   当前面板作为练习面板，把棋谱和联机也放到主菜单面板中，设置选项挪过来之后
			#   删掉设置页的返回按钮」⇒ 就是下面这一句 append_array 的由来：
			#   这四块从"只在首页注册"变成**四个面板都 append 同一份真源**
			#   （`_footer_entry_descriptors()`）—— 底栏"固定不动"因此**结构性成立**。
			#   ⚠️ 各页各写一份的话，"固定"只由**四份文本巧合一致**保证：改一页忘三页
			#   就变成"这个面板的底栏长得不一样"，而每个面板**内部自洽** ⇒ 所有几何判据
			#   照样绿（`--menutest` ⑥d 现在专门量这一条：四页的底栏必须**逐块同位置**）。
			# ★ 全部走 `_items` 这条**数据驱动的真源**（`center`/`poly` 由 `_layout_*` 填，
			#   绘制与 `_tile_at_point` 命中都从它派生）⇒ 命中测试与视觉**不可能分家**。
			#   ★★ 不用 Control 节点做入口：现有那套原生控件只服务设置面板（有主题/存档同步），
			#   入口要跟瓷砖同背景，混用两套控件会让"点击命中"与"看到的位置"分家 ——
			#   而那种错**点得到但点错项**，症状是静默的。
			descriptors.append_array(_footer_entry_descriptors())
		PAGE_SETTINGS:
			# ★ 设置**面板**（不再是"独立页"）：设置选项由 `_build_settings_ui()` 落在
			#   底栏行带**之上**（`offset_bottom` 读 `_footer_band()`）⇒ 底栏露在外面、
			#   仍然可点（按「练习」即回练习面板）。用户口令「设置选项挪过来之后删掉设置页的
			#   返回按钮」—— 返回按钮整族已删；这里**不要**再补一颗返回（补了就是三份回去的路）。
			_title.text = "设置"
			descriptors.append_array(_footer_entry_descriptors())
		PAGE_RECORDS:
			# ★ 棋谱面板初版：只进占位（空态文案 + 底栏）。
			#   列表与"点谱进复盘"等 `--browsetest` 交互层做完再填 —— 与阶段② 的次序一致，
			#   免得出现"面板能点开、点进去动不了"的半截状态。
			# ★ 2026-10-04：面板标题跟着入口名一起改（「棋谱库」→「棋谱」）—— 入口与落地面板
			#   叫两个名字时，用户会以为点进去的是别的地方。改名要**成对**改。
			# ⚠️ 面板名与底栏那块砖**必须同名**，而这条由 ⑥d 逐块比标签来守（不是靠注释）。
			_title.text = "棋谱"
			descriptors.append_array(_footer_entry_descriptors())
		PAGE_LOBBY:
			# ★ 同上：入口「对弈」↔ 本面板标题必须同名。
			#   ⚠️ 但**别**把 `netmode` 组那一瓣也叫「对弈」—— 那是"邀请好友 / 联机大厅"里的
			#   二级选项，语义是"去哪找对手"（见注册处注释）。
			_title.text = "对弈"
			# ★ 2026-10-08：本页不再是占位 —— 页内容在 `_set_page()` 末尾由 `_build_duel_ui()` 建
			#   （与棋谱 / 设置面板同一处，见下面那三行 `if page == …` 的说明）。
			descriptors.append_array(_footer_entry_descriptors())

	for d in descriptors:
		_items.append({
			"center": Vector2.ZERO,
			"poly": PackedVector2Array(),
			"label": d["label"],
			"cb": d["cb"],
			"disabled": d["disabled"],
			"group": d["group"],
			"size_id": int(d.get("size_id", -99)),   # 仅 boardsize 组使用：按 id 匹配（标签随棋盘变）
			# ★ 2026-10-09：`mode` 组（对战方式行）的身份字段 —— 与 `size_id` 同一个思路。
			#   `_mode_tile_selected()` 是唯一读者。
			# ⚰️ 2026-10-12：`diff_id` 一并删除（难度不再可选）。身份字段仍有**两个**
			#   （`size_id` / `mode_id` 各服务一组）—— 别把 `size_id` 也顺手合并掉：
			#   两者语义不同（前者是"槽位号"，后者是"哪一种对局方式"）。
			"mode_id": int(d.get("mode_id", -1)),
			# ★★ 2026-10-16：`nav` 组（底栏四块）的身份字段 —— 与 `size_id` / `mode_id` 同一个思路。
			#   读者是 `_mode_tile_selected()` 的同族 `_nav_tile_selected()`。
			#   ⚠️⚠️ 本 `_items.append({...})` 是一张**投影白名单**：描述符里有的键**不会自动过来**。
			#     本轮实测踩到（修 bug 时**当场**被新判据逮住）：描述符侧写好了 `page_id`，
			#     投影里没登记 ⇒ `it.get("page_id", -1)` 恒 -1 ⇒ `_nav_tile_selected(-1)` 恒假
			#     ⇒ 症状与"运行期压根没有 nav 臂"**一模一样**（底栏 0 块亮），
			#     而建项处的 `sel` 仍然是对的 ⇒ 只看建项结果的判据照样全绿。
			#   ⇒ 通式：**加身份字段要改两处**（描述符 + 本投影）。少改一处是**静默**的，
			#     唯一能咬住它的是走"运行期重新派生"那条路的判据（`--menutest` ⑤b2）。
			"page_id": int(d.get("page_id", -1)),
			"selected": d.get("sel", false),
		})

	# ★ 2026-10-09：这里原有「难度折叠目标 `_diff_target = 1.0 if _sel_mode == MODE_VS_AI`」
	#   那一行 —— 随 `_diff_t` 一族整族删除（难度不再折叠，恒在屏上）。
	# ★ 2026-10-08：这里原有「联机折叠目标 `_net_target`」那一行 —— 随 netmode 两瓣整族删除
	#   （练习面板不再有联机入口，"从「线上」左侧长出两瓣"这件事不存在了）。
	# 棋盘大小折叠目标：循环行里每一项（含占位）在_contents上都有三档大小可选 → 恒为展开。
	# 例外只有「切换动画期间」—— _process 会先置 0 收回，等整行滑到位再置 1 展开。
	_board_target = 1.0

	# ⚰️ 2026-10-12：这里原有「选中项直接铺黑子（无需生长动画）」那一段 ——
	#   随黑砖族整族删除。"已选"现在完全由 `_items[i]["selected"]` 表达，
	#   绘制侧按它画凹陷态，**不需要任何额外的记账集合**（少一个集合 = 少一处会不同步的状态）。

	# ⚰️ 2026-10-16：这里原有 `if page == PAGE_MAIN: _snap_board_row()` —— 它把循环行
	#   "对准焦点位"再排布（排布要读 `_board_row_pos`）。棋盘行改静态平铺后焦点位不存在，
	#   该函数随整族删除 ⇒ 这一支没有内容，整条 `if` 一并摘掉（留一个空 `if ... : pass`
	#   比不写更坏：读的人会以为"这里还有一步"。）
	if page == PAGE_SETTINGS:
		_build_settings_ui()   # 原生控件树，落在底部行带**之上**（见该函数里的让位算式）
	if page == PAGE_RECORDS:
		_build_records_ui()    # 棋谱库面板（同一套纪律：整棵树在底栏行带之上、切页销毁）
	if page == PAGE_LOBBY:
		# ★ 2026-10-08：对弈页（联机大厅）——与棋谱面板同一处建树（整棵树在底栏之上、切页销毁）
		_build_duel_ui()
	# ★★★ 2026-10-04 v4：**四个面板都必须跑布局** —— 底栏那四块注册在**每一个**面板上
	#   （`_footer_entry_descriptors()`），而 `center`/`poly` 是布局填的 ⇒ 不跑布局的那个
	#   面板，底栏既不画也点不到 ⇒ **面板变成死胡同**（只能 ESC 退游戏）。
	#   ★ 这条错是**静默**的：没有任何报错，`_items` 里那四条记录也在，
	#   而判据若只看 `_items`（不看 `poly`）会全绿 —— 本轮实测就踩到了：
	#   设置面板原来走"只建原生控件、不跑布局"那一支，⑥b/⑥d 立刻报「第1面板四块未布局」。
	#   ⚠️ 为什么写成"无条件一次"而不是在三支里各写一次：三处各写一遍就是三份布局时机，
	#   将来加第五个面板必漏一处（而漏掉的表现与上面那条一模一样，还是静默的）。
	_layout_setup()            # 末尾会算一次背景密铺（`_bg_ensure()`）与联机面板重排
	if page == PAGE_MAIN:
		_sync_menu_bg()        # 背景棋盘跟当前选择联动（唯一真源，绘制与判据都读它）
	# ★ 原生控件（标签/勾选框/输入框）的主题墨色：**建页之后统一刷一次**（唯一调用点）。
	#   放在 `_layout_setup()` 之后、`queue_redraw()` 之前：刷墨色会改 `LineEdit` 的盒底色
	#   （进而改最小尺寸）⇒ 必须在布局算完之后做，否则这一帧量到的是旧尺寸。
	_refresh_page_ink()
	queue_redraw()

## 自检（--modeltest）：**共享数据层 `MenuModel`** 的判据（2026-09-23 加手机菜单时新增）。
##
## ★ 为什么这一层的自检比菜单自检更重要：两个菜单（桌面密铺 / 手机竖排）都从这里取
##   「槽位语义 / 有效选择 / 恢复校验」，这一层错了就是**两个菜单一起错**，
##   而且错法都是静默的（标签与凹陷态各指一件事、预览与开局画不同的盘）。
##   所以每条都配**阴性对照**：把判据"往反方向拨一下"，必须变红 —— 恒真的判据等于没有判据。
##
## headless 下可直接跑（全是纯函数，不碰节点、不碰视口）→ 这条有真正的 runner。
func _model_self_test() -> void:
	var ok := true
	print("[modeltest] ===== 共享数据层 MenuModel =====")

	# ① 槽位数必须与「种类数」一致 —— 两种含义共用同一组槽位是这套机制的前提。
	#    这条跨层钉一次（--einsteintest 钉的是菜单侧那一份），加种类时两边都会响。
	var n_slots: int = MenuModel.slots().size()
	var ok1: bool = n_slots == 3 and MenuModel.HAT_KINDS.size() == 3
	if not ok1:
		ok = false
	print("[modeltest] ① 槽位数=%d 种类数=%d（都须为 3）→ %s" % [
		n_slots, MenuModel.HAT_KINDS.size(), "通过 ✓" if ok1 else "失败 ✗"])

	# ② 标签与语义同源：`slot_meaning` 说这行是种类时，标签必须来自 HAT_KINDS；
	#    说是大小时必须来自 size_label。两种语义在同一 slot 上**必须给不同结果**（阴性对照）。
	var hat_used := false
	var size_used := false
	var mismatch: Array[String] = []
	for slot in MenuModel.slots():
		for hat in [false, true]:
			var lbl: String = MenuModel.slot_label(slot, hat, GameConfig.BOARD_PENROSE)
			var want: String = MenuModel.hat_kind_label(slot) if hat \
				else MenuModel.size_label(slot, GameConfig.BOARD_PENROSE)
			if lbl != want:
				mismatch.append("slot%d hat=%s got=%s want=%s" % [slot, str(hat), lbl, want])
			if hat: hat_used = true
			else: size_used = true
	# 阴性对照：同一 slot、两套语义，结果必须不同（否则"同源"这件事根本无从测起）
	var distinct := true
	for slot in MenuModel.slots():
		if MenuModel.slot_label(slot, true, GameConfig.BOARD_PENROSE) \
			== MenuModel.slot_label(slot, false, GameConfig.BOARD_PENROSE):
			distinct = false
	var ok2: bool = mismatch.is_empty() and hat_used and size_used and distinct
	if not ok2:
		ok = false
	print("[modeltest] ② 标签随语义切换：%.0f 处不符%s，两套语义结果不同=%s → %s" % [
		mismatch.size(), ("（" + "; ".join(mismatch) + "）") if not mismatch.is_empty() else "",
		str(distinct), "通过 ✓" if ok2 else "失败 ✗"])

	# ③ 选中态与标签**同源**：用两组**不同值**的状态，检验两种语义指向不同的槽位。
	#    （若用相同的 sel_size/sel_hatkind，两种语义恰好重合，判据会假绿 —— 这里刻意分开取。）
	var sel_size: int = GameConfig.RANDOM          # 0
	var sel_hat: int = GameConfig.HAT_SPECTRE      # 2
	var size_sel := -1
	var hat_sel := -1
	for slot in MenuModel.slots():
		if MenuModel.slot_selected(slot, false, sel_size, sel_hat):
			size_sel = slot
		if MenuModel.slot_selected(slot, true, sel_size, sel_hat):
			hat_sel = slot
	var ok3: bool = size_sel == sel_size and hat_sel == sel_hat and size_sel != hat_sel
	if not ok3:
		ok = false
	print("[modeltest] ③ 选中态随语义切换：大小语义选中=%d（应 %d）种类语义选中=%d（应 %d）→ %s" % [
		size_sel, sel_size, hat_sel, sel_hat, "通过 ✓" if ok3 else "失败 ✗"])

	# ④ 点击落点随语义切换（回调那一条腿）
	var a_size: Dictionary = MenuModel.slot_activation(1, false)
	var a_hat: Dictionary = MenuModel.slot_activation(1, true)
	var ok4: bool = int(a_size.get("size", -1)) == 1 and not a_size.has("hat_kind") \
		and int(a_hat.get("hat_kind", -1)) == 1 and not a_hat.has("size")
	if not ok4:
		ok = false
	print("[modeltest] ④ 点击落点：大小语义→%s 种类语义→%s → %s" % [
		str(a_size), str(a_hat), "通过 ✓" if ok4 else "失败 ✗"])

	# ⑤ 「爱因斯坦一律随机档」这条规则必须在**唯一落点**成立，且非帽子盘不许被改。
	#    阴性对照就是"非帽子盘必须保留 sel_size"—— 少了那一半，判据可以用"永远返回 RANDOM"通过。
	var ch_hat: Dictionary = MenuModel.effective_choice(
		GameConfig.BOARD_HAT, GameConfig.ENHANCED, GameConfig.HAT_TURTLE)
	var ch_pen: Dictionary = MenuModel.effective_choice(
		GameConfig.BOARD_PENROSE, GameConfig.ENHANCED, GameConfig.HAT_TURTLE)
	var ch_neg: Dictionary = MenuModel.effective_choice(-1, GameConfig.STANDARD, GameConfig.HAT_HAT)
	var ok5: bool = int(ch_hat["size"]) == GameConfig.RANDOM \
		and int(ch_hat["hat_kind"]) == GameConfig.HAT_TURTLE \
		and int(ch_pen["size"]) == GameConfig.ENHANCED \
		and int(ch_neg["board"]) == GameConfig.BOARD_PENROSE
	if not ok5:
		ok = false
	print("[modeltest] ⑤ 有效选择：帽子盘 size=%d（应 %d）｜彭罗斯 size=%d（应 %d）｜board=-1 回落=%d → %s" % [
		int(ch_hat["size"]), GameConfig.RANDOM, int(ch_pen["size"]), GameConfig.ENHANCED,
		int(ch_neg["board"]), "通过 ✓" if ok5 else "失败 ✗"])

	# ⑥ 恢复上一局的校验：合法采纳、占位/下线 id 整份作废、越界夹取、「线上」不恢复
	var r_ok: Dictionary = MenuModel.restore_state(
		{"board": GameConfig.BOARD_HAT, "size": 99, "hat_kind": -5, "diff": 7, "mode": GameConfig.VS_AI})
	var r_bad: Dictionary = MenuModel.restore_state({"board": -1, "size": 1})
	var r_online: Dictionary = MenuModel.restore_state(
		{"board": GameConfig.BOARD_PENROSE, "mode": GameConfig.ONLINE})
	# ★ 2026-10-15 `xg`（疾风档）的夹取：超界给 5 必须夹到 1，**缺省**必须给 0。
	#   ⚠️ **两半都要断**：只断"夹到 1"的话，把 `restore_state()` 里那行写成常量 1 也照样绿。
	var r_xg_hi: Dictionary = MenuModel.restore_state({"board": GameConfig.BOARD_PENROSE, "xg": 5})
	var r_xg_lo: Dictionary = MenuModel.restore_state({"board": GameConfig.BOARD_PENROSE})
	var ok6: bool = not r_ok.is_empty() and int(r_ok["size"]) == GameConfig.ENHANCED \
		and int(r_ok["hat_kind"]) == GameConfig.HAT_HAT and int(r_ok["diff"]) == 2 \
		and int(r_ok["mode"]) == GameConfig.VS_AI \
		and int(r_xg_hi.get("xg", -1)) == 1 and int(r_xg_lo.get("xg", -1)) == 0 \
		and r_bad.is_empty() and int(r_online["mode"]) == GameConfig.LOCAL
	if not ok6:
		ok = false
	print("[modeltest] ⑥ 恢复校验：越界夹取 size=%d hat=%d diff=%d xg=%d（缺省→%d）｜占位 id 作废=%s｜线上→%s（应本地）→ %s" % [
		int(r_ok.get("size", -9)), int(r_ok.get("hat_kind", -9)), int(r_ok.get("diff", -9)),
		int(r_xg_hi.get("xg", -9)), int(r_xg_lo.get("xg", -9)),
		str(r_bad.is_empty()), MenuModel.mode_label(int(r_online.get("mode", -9))),
		"通过 ✓" if ok6 else "失败 ✗"])

	# ⑦ 手机菜单「大小」行的当前值：帽子盘必须说"由棋盘决定"（与 ⑤ 同源），
	#    非帽子盘必须显示真实档位名。阴性对照同上：两半都要。
	var sv_hat: String = MenuModel.size_row_value(GameConfig.BOARD_HAT, GameConfig.ENHANCED)
	var sv_kite: String = MenuModel.size_row_value(GameConfig.BOARD_KITE, GameConfig.RANDOM)
	var sv_pen: String = MenuModel.size_row_value(GameConfig.BOARD_PENROSE, GameConfig.RANDOM)
	var ok7: bool = sv_hat == "由棋盘决定" and sv_kite == "迷你" and sv_pen == "随机"
	if not ok7:
		ok = false
	print("[modeltest] ⑦ 大小行文案：帽子=%s｜筝形随机档=%s｜彭罗斯随机档=%s → %s" % [
		sv_hat, sv_kite, sv_pen, "通过 ✓" if ok7 else "失败 ✗"])

	print("[modeltest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

# 选大小 / 选难度：仅更新选择状态并重绘（不重建页面）
func _select_size(id: int) -> void:
	_sel_size = id
	_refresh_selection()

## 选爱因斯坦的种类（帽子/海龟/幽灵）。与 _select_size 同一套做法：只改状态 + 重绘，
## 不重建页面（三瓣瓷砖原位换凹陷态即可）。
## ★ 这里**不再顺手把 `_sel_size` 改成随机**（曾经这么干过）：那会把用户在其他棋盘上选的大小档
##   冲掉 —— 选了「海龟」再切回彭罗斯，大小就莫名变成随机档。
##   「爱因斯坦一律按随机档开局」这件事由 `_push_board_choice()` 一处兜住
##   （它判 `board_type == BOARD_HAT` 时强制 RANDOM），两个状态各记各的、互不污染。
func _select_hatkind(id: int) -> void:
	_sel_hatkind = id
	_refresh_selection()

## 种类 id → 显示名。★ 已委托 `MenuModel.hat_kind_label()`（两个菜单共用一份，查不到退回「帽子」）
func _hat_kind_label(id: int) -> String:
	return MenuModel.hat_kind_label(id)

## ★ 二级行第 slot 个槽位在当前「有效选中棋盘」下的显示名。**唯一真源在 `MenuModel.slot_label()`**
##   （`menu_mobile.gd` 的选项块调的是同一个函数）—— 这一层就是 2026-09-19 那个
##   「其他棋盘的标准/加强被改名」bug 的结构性防线：两个菜单不可能各写一套槽位语义。
func _size_slot_label(slot: int) -> String:
	return MenuModel.slot_label(slot, _is_hat_eff(), _eff_board())

## ★ 二级行第 slot 个槽位的选中态。与 `_size_slot_label` **共用同一个 `_is_hat_eff()` 判据**，
##   保证「凹陷态」与「标签」永远指同一件事。
func _size_slot_selected(slot: int) -> bool:
	return MenuModel.slot_selected(slot, _is_hat_eff(), _sel_size, _sel_hatkind)

## ★ 二级行的**唯一回调**：点第 slot 个槽位。落到哪个状态字段由 `MenuModel.slot_activation()`
##   在**点击这一刻**判定 —— 这是「行语义随棋盘变、回调却没跟着变」那个 bug 的结构性修复。
func _activate_size_slot(slot: int) -> void:
	var a: Dictionary = MenuModel.slot_activation(slot, _is_hat_eff())
	if a.has("hat_kind"):
		_select_hatkind(int(a["hat_kind"]))
	else:
		_select_size(int(a["size"]))

## 自检用：按**真实点击路径**激活二级行第 slot 个槽位 —— 定位到该项、过一遍
## `_tile_at_point` 命中判定、再调它的 `cb`（与 `_input` 里 `(it["cb"] as Callable).call()`
## 是同一条链）。返回 false = 这条链上有一步没过（通常是折叠没收完 → 被 `_board_t` 门槛挡下）。
func _click_boardsize_slot(slot: int) -> bool:
	for i in _items.size():
		var it: Dictionary = _items[i]
		if str(it["group"]) != "boardsize" or int(it.get("size_id", -99)) != slot:
			continue
		if _tile_at_point(it["center"]) != i:
			return false
		(it["cb"] as Callable).call()
		return true
	return false
## 「有效选中」的棋盘是不是爱因斯坦。二级行的含义要靠它判定，口径必须与凹陷态一致
##（切换动画期间用待切换的那个，否则整行已经切成「种类」、标签却还写着「随机/标准/加强」）。
func _is_hat_eff() -> bool:
	return _eff_board() == BOARD_HAT

## ★「大小」那一行的**行标题真源**（2026-10-09：该行从"棋盘行右侧的折叠二级菜单"
##   改成独立一行 ⇒ 必须有个标题，否则 帽子/海龟/幽灵 三个字看不出是什么）。
##   ⚠️ 为什么必须是函数而不是建项时写死的字符串：这一行的含义**随棋盘变**
##   （普通盘 = 大小三档；爱因斯坦 = 种类三档，见 `_size_slot_label()` 那一大段说明），
##   而布局 `_layout_setup()` 会在切棋盘时重跑 —— 写死就会"行已经切成种类、标题还写大小"。
##   ⇒ 与标签走**同一个判据** `_is_hat_eff()`，两者结构上不可能分家（铁律 7）。
func _size_row_title() -> String:
	return "种类" if _is_hat_eff() else "大小"

## 把菜单里的棋盘选择推给 GameConfig。**开局前统一走这里**（原先 6 处各写一遍
## `board_size / board_type`，加一类棋盘就要改 6 个地方，漏一处就出怪局）。
## ★ 爱因斯坦不暴露尺寸档：无论 _sel_size 停在哪个槽位，一律按随机档开局，并把种类一起推过去
##   （种类换的是瓦片边长，直接决定盘面 → 和种子一样属于「盘面参数」，必须一起下发/落盘）。
func _push_board_choice() -> void:
	var ch := _eff_board_choice(false)
	# 写 GameConfig 的三个字段走 MenuModel（**唯一**写这里的地方，手机菜单同一入口）
	MenuModel.apply_choice_to_config(ch)
	# ★ 联机开关与通道也在这里落 —— 本函数是**所有开局路径的唯一必经点**，所以两边必须同源：
	#   ★★ 同时修掉一个**既有隐患**：此前 `GameConfig.online` 一旦被联机路径置真，
	#   全工程**没有任何复位点**（`online = false` 只出现在联机失败回滚里，已 grep 确认）
	#   ⇒ 「联机完回菜单、再开单机」时 `game.gd::_ready` 仍会走 `_start_network()`
	#   （HUD 显示等待对端）。现在由下面这一行兜住。
	# ★ 2026-09-30 §24 第 5 步：这里原有 `GameConfig.net_channel = _sel_channel`（线上）与
	#   `= GameConfig.CHAN_RELAY`（非线上复位）两个分支 —— 那是"通道二选一"时代的写法。
	#   自建联机删除后通道**恒为 Steam**，两支合并成一行无条件赋值。
	#   ★★ 2026-09-30 §24 追修（P0）：**这两行单独不够** —— 非线上分支只复位了 `online`，
	#   而 `net_channel` 改成"无条件 = Steam"后就**恒真**了。首版据此让引擎只认通道 ⇒
	#   单机/人机局与全部游戏侧自检被改写成 ONLINE + Steam（详见 `game.gd::_steam_arg()` 注释）。
	#   修法选在**引擎侧**补 `mode == ONLINE` 这一半（铁律 8：菜单写、引擎读，各一处）：
	#   菜单侧覆盖不到"自检 / 直接启动 game.tscn"那条路径，而那条恰恰是被咬得最狠的。
	#   保留这一行的意义：`net_channel` 仍是"本局走哪条通道"的**唯一真源**
	#   （`game.gd::_steam_arg()` 只读它）—— 将来若要再加第二条通道，只需改这一行的右边。
	# ★★★ 2026-10-08：判据从 `_sel_mode != MODE_ONLINE` 改成 **`GameConfig.mode != MODE_ONLINE`**。
	#   为什么必须改（"把联机搬进「对弈」页、练习面板删掉「线上」档"的**连带**，不改就静默炸联机）：
	#     · 练习面板的「对战方式」只剩 本地/人机 ⇒ `_sel_mode` **永不可能**等于 ONLINE
	#       ⇒ 原来那个条件**恒真**；
	#     · 而两个联机入口（`_host_enter_game()` / `_steam_join_by_id()`）都是
	#       **先写 `GameConfig.mode = MODE_ONLINE`、再调本函数** ⇒ 恒真条件会把刚设好的
	#       `GameConfig.online = true` **立刻抹成 false**：房主/加入方都静默变成单机局
	#       （`game.gd::_ready` 只认 `online` 决定要不要 `_start_network()`），
	#       症状是"点建房进对局，却是一盘单机" —— 不报错、不报红，只有玩才看得出。
	#   ★ 为什么 `GameConfig.mode` 才是**真源**、而不是"换个等价的菜单量"：
	#     · 引擎侧的对战方式本来就是 `game.gd` 里 `var start_mode: int = GameConfig.mode`
	#       （铁律 8：一处写、一处读）—— 菜单侧再判一个派生量就是第二份真相；
	#     · 三个开局入口写法已统一为"先落 `GameConfig.mode`、再落选项"：
	#       `_start_from_setup()` 落 `_sel_mode`，两个联机入口落 `MODE_ONLINE`。
	#   ★ 判据：`--steamuitest` ⑧ 两半（线上 ⇒ **不许**复位 / 非线上 ⇒ 强制复位）。
	if GameConfig.mode != MODE_ONLINE:
		GameConfig.online = false
	GameConfig.net_channel = GameConfig.CHAN_STEAM
	# 顺手把「这一局用的选项」落盘，供**下次回到菜单**时恢复（见 `_restore_last_match`）。
	# 放这里是因为它是**所有开局路径的唯一必经点**（本地/人机 `_start_from_setup`、联机建房
	# `_host_enter_game`、凭码加入 `_start_join`、快速匹配 `_start_match`）—— 一处兜住，
	# 以后加新的开局入口也不会漏记。自动化运行不落盘（否则自检的临时选择会污染用户配置）。
	if not _is_automated_run():
		# ⚠️ `diff` 传**恒定的困难档**：桌面菜单没有难度状态（见 `DIFF_HARD` 的注），
		#   但 `last_match.cfg` 的字段格式不变（手机菜单仍在读写它，`--mtest` 钉着）。
		#    ★ 2026-10-15：疾风档转正 ⇒ 选中态一并落盘（`xg`，见 `save_last_match` 的注）。
		#    ★★ 2026-10-15b 并列化：文件格式**一个字节都没变**（仍是 `mode` + `xg` 两个字段），
		#      只是两者的来源改了 —— `mode` 走 `_sel_mode_for_config()`（疾风折叠成 VS_AI），
		#      `xg` 由 `_sel_mode` 派生。**哨兵值 100 仍然不外泄进文件**（旧版本 Godot 读它
		#      会落进 `game.gd::_ready` 的夹取里变成一个非法 mode）。
		GameConfig.save_last_match(_sel_board, _sel_size, _sel_hatkind, DIFF_HARD,
			_sel_mode_for_config(), _sel_kind_code())

## 预览与开局**共用的**「有效选择」三元组：`{board, size, hat_kind}`。
## ★ 这是「爱因斯坦一律走随机档」这条规则的**唯一落点**：`_push_board_choice()` 与右下角的
##   预览卡都从这里取，两处结构上不可能分叉 —— 分头各写一遍就会出现
##   「预览画的是标准盘、点开始却是随机盘」这种鬼状态（本项目在完全同型的地方踩过）。
## `use_pending=true` 时取「待切换」的那个棋盘（`_eff_board()`），让预览在切换动画一开始就跟手。
func _eff_board_choice(use_pending: bool = true) -> Dictionary:
	return MenuModel.effective_choice(_eff_board() if use_pending else _sel_board,
		_sel_size, _sel_hatkind)

## 把一份「上一局选项」记录应用到菜单的选择状态。返回是否采纳。
##
## 拆成独立函数（而不是写进 `_restore_last_match`）是为了**可自检**：自检运行时
## `_is_automated_run()` 恒为真，`_restore_last_match()` 会直接返回，只能从这一层测。
##
## 校验口径：
##   · 棋盘 id 必须是**当前启用**项 —— 版本迭代里会有盘下线（经典 19×19 于 2026-09-15 下线，
##     编号不复用），旧配置里的 id 可能指向一个已经不存在的盘；此时**整份作废**回默认，
##     绝不能让菜单去画一个不存在的选项（会画不出、也点不着）。
##   · 大小档 / 帽子种类：越界值一律夹回合法区间（文件被手改过也不至于崩）。
##     ⚰️ 2026-10-12：这句原先还含「难度」。难度整族删除后菜单里没有这个状态，
##     记录里的 `diff` **夹取照做、桌面菜单不采纳**（手机菜单还有难度行且被 `--mtest` 钉着）。
##   · 对战方式：只采纳 本地 / 磐石（+ 疾风，走 `xg` 那一栏）。**「线上」一律不采纳**（见下）。
func _apply_last_match(d: Dictionary) -> bool:
	# 校验/夹取口径全部在 MenuModel.restore_state()（纯函数 → 手机菜单共用同一套，且能 headless 验）
	var s: Dictionary = MenuModel.restore_state(d)
	if s.is_empty():
		return false
	_sel_board = int(s["board"])
	_sel_size = int(s["size"])
	_sel_hatkind = int(s["hat_kind"])
	# ⚰️ 2026-10-12：这里原有 `_sel_diff = int(s["diff"])` —— 难度不再可选 ⇒ 菜单里没有这个
	#   状态，文件里的 `diff` 字段**显式不采纳**（`save_last_match` 照写、`MenuModel` 照夹取，
	#   因为手机菜单还有难度行且被 `--mtest` 钉着）。
	#   ⚠️ 别把这一行"顺手加回来"：那会让「磐石恒最难」变成"上一局是什么就是什么"。
	#
	# ★ 2026-10-15 转正：疾风档**跟着持久化**。原先写死 false —— 那时它是临时测试入口，
	#   "想测再点一次"是合理的；但正式档位若记不住选择，玩家每次回来都要重选一次。
	#   `xg` 是新增的**可选**字段（旧记录缺它 ⇒ 0 = 未选疾风），与 `mode` 那道必需检查分开。
	#
	# ★★ 2026-10-15b 并列化：两个字段**合成一个赋值** —— 因为菜单里它们本来就是同一个状态
	#    （`_sel_mode`），分成两行写必然长出"两边不同步"的窗口。
	#   · `xg == 1` ⇒ 直接落 `MODE_XGAI`，**不看 `mode`**：记录里 `mode` 那一栏按约定只会是
	#     0/1（哨兵不外泄），所以 xg=1 时它就是 VS_AI，读它没有额外信息；
	#   · 手改成 `mode=本地, xg=1` 这种自相矛盾的 cfg ⇒ 采纳 xg（疾风本来就是 AI 档，
	#     与"恢复线上会把菜单带进联机状态"那类危险不同 —— 它不会在打开菜单时产生任何副作用）。
	#   · 旧记录（缺 `xg`）⇒ 0 ⇒ 走 `mode`，与改前**逐字节同行为**（铁律 §111：换口径时
	#     新式必须在旧工况下退化成旧式）。
	# ★ 2026-10-22：`xg` 字段升级成**档位号**（0=磐石 / 1=疾风 / 2=流水）。
	#   旧记录只有 0/1 ⇒ 逐字节退化成旧行为（§111）；新增的 2 只由 `_sel_kind_code()` 产生。
	# ★ 2026-10-23：再加 **3=野马**（同样只由 `_sel_kind_code()` 产生，旧记录 0/1/2 语义不动）。
	#   ⚠️ 四个 `if` 的顺序有意义：数值分支必须排在 `else`（`mode`）之前。
	#   写成 `== 3 else ...` 那种链式会让漏掉的号落进 `mode` ⇒ 静默恢复成磐石。
	var kind := int(s.get("xg", 0))
	if kind == 3:
		_sel_mode = MODE_YEMA
	elif kind == 2:
		_sel_mode = MODE_LIUSHUI
	elif kind == 1:
		_sel_mode = MODE_XGAI
	else:
		_sel_mode = int(s["mode"])
	return true

## 回到菜单时恢复上一局的选项（2026-09-19 用户要求：下完棋返回菜单要保留上次的选项）。
##
## 存的字段见 `GameConfig.save_last_match()`；首次运行（没有记录）或记录已失效时静默跳过，
## 一切照默认值来。
func _restore_last_match() -> void:
	var d: Dictionary = GameConfig.load_last_match()
	if not _apply_last_match(d):
		return
	# ★ 显示名走 `_mode_label`（唯一口径）：**别**在这里就地写
	#   `"人机" if … else "本地"` —— 对战方式一旦多一块，它就会被**印成"本地"**，
	#   而实际进的根本不是本地局（日志骗人，且 `--menutest` 抓不到 —— 它不读这行）。
	#   ⚰️ 2026-10-13：这条纪律正是加「Ludii」时暴露出来的（同日 Ludii 退役，纪律照旧）。
	#   ★★ 2026-10-15b **第三次兑现，而且换了个形态**：并列化之后 `_sel_mode` 可能是哨兵 100，
	#     而 `MenuModel.mode_label()` 不认识它 ⇒ 会**静默印成 "?"**（一行骗人的日志，
	#     且 `lastmatch_e2e.sh` 正是 grep 这行来断端到端的 ⇒ 它也会跟着错到看不懂）。
	#     ⇒ 这就是 `_mode_label()` 存在的理由：两档委托共用真源，哨兵那一档在菜单侧就地给。
	print("[菜单] 已恢复上一局选项：棋盘=%s 大小档=%d 帽子种类=%d 对战方式=%s（磐石恒最难）" % [
		_board_label(_sel_board), _sel_size, _sel_hatkind, _mode_label(_sel_mode)])

## 选棋盘类型。序列旋钮还是在**更新选择状态**，真正的位置变化分三步交给 _process 串起来：
##   ① 收回当前的大小折叠菜单（_board_target=0，与「对战方式」同一套缓动）；
##   ② 收回完成 → 换锚点，并把循环行的目标槽位设为「离当前位置最近的那个 ≡ 新选中项」；
##   ③ 整行滑到位后才重新展开大小菜单 —— 顺序反了的话，折叠簇会跟着整行一起飞出去再回来。
func _select_board(id: int) -> void:
	if id == _sel_board and _board_pending < 0:
		return
	if id == _sel_board:
		_board_pending = -1                          # 收回途中又点回原项 → 取消切换，原地重新展开
	else:
		_board_pending = id
	_board_target = 0.0
	_refresh_selection()   # 凹陷态立即跟到新块（选中标记取 _eff_board），不等收回动画

## 把待切换的棋盘类型立即落定（开始对局时用；页面重建走 _set_page 里的同款内联处理）
func _commit_board_pending() -> void:
	if _board_pending < 0:
		return
	_sel_board = _board_pending
	_board_pending = -1
	_layout_setup()
	_board_target = 1.0

## 「有效选中」的棋盘：切换动画期间（_board_pending >= 0）返回待切换的那个，否则就是 _sel_board。
## 只有**选中标记（凹陷态）**用它；折叠锚点/布局必须用 _sel_board，否则二级菜单会在收回途中瞬移。
func _eff_board() -> int:
	return _board_pending if _board_pending >= 0 else _sel_board

## 棋盘类型 → 瓷砖文字。★ 委托 `MenuModel.board_label()`（手机菜单同一份）
func _board_label(id: int) -> String:
	return MenuModel.board_label(id)

## 循环行只铺**启用**的棋盘。★ 委托 `MenuModel.enabled_board_kinds()`
func _board_enabled_kinds() -> Array:
	return MenuModel.enabled_board_kinds()



# 选方式：必须重建本页——线上模式要增出「联机方式」行(netmode 瓷砖)，
# 其余模式要把该行移除。★ 2026-10-09：原先这里还写着「难度块展开/收回由 _diff_target
# 驱动 _process 缓动」—— 折叠机制整族删除，难度三档恒在「对战方式」行里。
##
## ★★ 2026-10-15b 并列化：本函数从"带分支的父子逻辑"退化成**最朴素的一句赋值**。
##   ⚰️ 改前长这样（用户口令「人机和疾风两个按钮逻辑有问题」）：
##     `if id == MODE_XGAI: _sel_mode = MODE_VS_AI; _sel_xgai = true`
##     ⇒ 点「疾风」会把「磐石」一起点亮（两块一起进选中态 = 屏幕上看得见的坏）。
##   现在「疾风」就是 `_sel_mode` 的一个取值，三块互为**并列互斥**项，语义上不可能同时亮。
##   ⚠️ 那句"`id == _sel_mode: return`"的**早退**不是省事，是**有语义**的：它挡掉"重复点同一块"
##     时的整页重建 + 折叠动画重启（点自己时重建会让整行滑回起点、闪一下）。别顺手删。
func _select_mode(id: int) -> void:
	if id == _sel_mode:
		return
	_sel_mode = id
	# ★ 2026-09-30 §24 第 5 步：这里原有 `_reset_netmode_to_invite()`（离开联机时把联机方式
	#   复位为「邀请好友」）。它存在的唯一理由是「随机匹配」那颗瓷砖**选中即进队列** ——
	#   停在 NET_RANDOM 又没在匹配中时，再点它会被 `if id == _sel_netmode: return` 静默拦掉，
	#   用户连重试的入口都没有。随机匹配删除后这个状态不存在了，
	#   `_reset_netmode_to_invite()` 与守它整条状态机的 `--netmodetest` 一起删除。
	_set_page(PAGE_MAIN)

## 对战方式常量 → 标签（**单一真源**，与 `_netmode_label()` 同一口径）。
##
## ★ 2026-10-15b 新增：原先三块瓷砖的 label 就地写死在描述符里（"本地"/"人机"/"疾风"），
##   而「磐石」这个名字**同时**要在 `MenuModel.mode_label()`（手机菜单 + 日志 + 棋谱）出现
##   ⇒ 改名必须记得改两处。就地写的代价在本轮立刻兑现：`_auto_select()` / `--select=` /
##   `--menutest` ⑭ 的样本都**按 label 字面**认瓷砖，写歪一处只会"找不到那块瓷砖"（静默）。
##   `MODE_XGAI` 的名字只能在这里给 —— 它是菜单内部哨兵，`MenuModel`（手机/棋谱共用）
##   不该知道它的存在，所以本函数**委托**给 `MenuModel.mode_label()` 拿另两档的名字。
func _mode_label(id: int) -> String:
	if id == MODE_XGAI:
		return "疾风"
	if id == MODE_LIUSHUI:
		return "流水"
	if id == MODE_YEMA:
		return "野马"

	return MenuModel.mode_label(id)

## 联机方式常量 → 标签（**单一真源**）。描述符的 `label` 与 `_refresh_selection()` 的
## 选中态判定都从这里取 —— 免得"加了一瓣、忘了改 `_refresh_selection` 里的硬编码"
## ⇒ 那一瓣永远选不中（黑子标记不出现 = 点了没反应，而且**静默**）。
func _netmode_label(id: int) -> String:
	match id:
		NET_LOBBY: return "公开大厅"
		_: return "好友联机"

## 选联机档（页内两个切换块的**唯一写点**）。
## ★★★ 2026-10-08：本函数从"翻开练习面板上的浮层"改成"翻对弈页里的档" ——
##   练习面板的「线上」档与 netmode 两瓣已整族删除，联机只有「对弈」页一个入口。
## ★ 顺序仍然是「先过闸、再翻档」（2026-10-02 订正过的那条）：闸不过时档位**不动**，
##   玩家看到"没反应 + 明确提示"，而不是"选中了却空着"（判据 ⑪）。
## ★ 翻档之后：① 不在对弈页就切过去（底栏「对弈」与这里**同一个落点**）；
##   ② 走一遍 `_refresh_duel_tabs()` 派生（标签 / 按下态 / 两块可见性三个量一起）；
##   ③ 选公开大厅 ⇒ 顺手刷列表。
## ★ 同档连点早退（防连点抖列表）：它的**视觉后果**由 `_on_duel_tab_pressed()` 末尾那句
##   "无条件重派生"兜住（toggle 按钮会自己翻面，见那里的注释）。
func _select_netmode(id: int) -> void:
	if id == _sel_netmode:
		return
	if id == NET_LOBBY and not SteamNet.ensure_init():
		_show_error_toast("Steam 不可用：%s" % SteamNet.reason())
		return
	_sel_netmode = id
	if _page != PAGE_LOBBY:
		_set_page(PAGE_LOBBY)      # 不在本页时切过去（切页里会建树并派生一次）
	_refresh_duel_tabs()
	# ★ 页首那行「未连接 Steam」要跟着刷新：进页时 Steam 可能还没起来（建页不碰 Steam），
	#   而这里已经过了 `ensure_init()` 那道闸 ⇒ 此刻的昵称才是真的
	#   （不刷的话会一直挂着"未连接 Steam"，而玩家明明已经能建房了 —— 量具说谎）。
	_refresh_duel_header()
	if id == NET_LOBBY:
		_refresh_lobby_list()

# ====== 对弈页（联机大厅）：两档真源 + 页首（2026-10-08）======
##
## ★★★ 用户口令「完善联机大厅，把主菜单的好友联机也搬到联机大厅里」⇒ 本页是**唯一**的联机入口。
##   与旧实现（「塞进 netmode 标签带与 mode 行之间那条缝里的浮层」）的三点结构差异，改之前先读：
##     ① **不再是浮层**：本页是普通原生控件树（与设置页 / 棋谱页同一套纪律），位置由容器布局给出。
##        ⇒ `_online_panel_pos()` / `_online_panel_w()` / `_lobby_panel_h()` / `_reflow_*()` /
##          `_fit_*()` 以及 `ONLINE_PANEL_W` / `ONLINE_PANEL_H` / `PANEL_GAP` **整族删除**：
##          它们服务的「缝」随两瓣标签一起消失，留着就是一套指向不存在几何的真源。
##     ② 可见性**仍然只有一个写点**（`_refresh_duel_tabs()`）—— 铁律 8 不变，只是从
##        「两个浮层二选一」变成「页内两块二选一 + 两个切换块的按下态」。三个量必须一起派生，
##        否则就是「按下的是 A、显示的是 B」（铁律 7）。
##     ③ 档位常量（`NET_INVITE` / `NET_LOBBY`）与标签真源（`_netmode_label()`）不变 ——
##        换的只是「谁把这个档画出来」。
##
## ★ 判据：`--steamuitest` ⑪/⑪b/⑪c（降级闸 / 阳性对照 / 真实入口不翻档）
##   ＋ ⑫a/⑫b（**从控件出发**找到真切换块、真按一下 ⇒ 档位与按下态跟着变）
##   ＋ `--labeltest` 的对弈页布局四档视口扫描（页内控件不越界 / 不压底栏）。
func _refresh_duel_tabs() -> void:
	var lobby: bool = _sel_netmode == NET_LOBBY
	for id in _duel_tabs.keys():
		var b: Button = _duel_tabs[id]
		if b == null or not is_instance_valid(b):
			continue
		# ★ 标签也在这里重派生（而不是只在建的时候写一次）：`_netmode_label()` 是标签的唯一真源，
		#   将来改档名只改那一处；只在建时写死就会留下「切换块还挂着旧名字」（静默）。
		b.text = _netmode_label(int(id))
		b.button_pressed = int(id) == _sel_netmode
		# ★ 选中态还必须**看得见**：主题给的 toggle 按下态在这里几乎分不出来（目检实测两档一样灰），
		#   而"看不出当前在哪一档"正是玩家会当成"点了没反应"的那一家（铁律 7 的观感那一半）。
		#   样式同样**在这里派生**（与标签、按下态同一个真源 `_sel_netmode`），不在建控件时写死 ——
		#   建控件时套一次的话，切档之后"选中的块"就永远停在第一次建页时那一档上（静默）。
		# ★★ 2026-10-15 改口径：从"只覆盖字色"改成**整套样式按两态分别套**
		#   （选中 = 实心 accent + 贴合字色；未选 = 主题色描边 + 表面浮起）。
		#   为什么必须整套：旧版只改字色 ⇒ 两块的**盒子**都还是引擎默认灰底，
		#   于是"选中的那一块"读起来只是"字换了颜色"，而用户报的原话正是
		#   「设置按钮等大多数按钮也没有用上主题色」——判定它的判据不能只看字。
		#   ⚠️ 旧注里那条"按下那一刻字色会闪回默认白"的坑没消失，它已经**上收进了真源**
		#   （`GameConfig.style_theme_button*()` 现在连 `font_hover_pressed_color` 一起覆盖）。
		if int(id) == _sel_netmode:
			_style_page_button_selected(b)
		else:
			_style_page_button(b)
	if _duel_invite_box != null and is_instance_valid(_duel_invite_box):
		_duel_invite_box.visible = not lobby
	if _duel_lobby_box != null and is_instance_valid(_duel_lobby_box):
		_duel_lobby_box.visible = lobby

## 页首那一行：我是谁 + 我的联机战绩（真源：`SteamNet.my_persona()` / `GameConfig.record_str()`）。
##
## ★ 为什么值得占一行：房主把自己的战绩写进 lobby data 供陌生人浏览时显示
##   （`SteamNet.LOBBY_RECORD_KEY`）—— 自己反而看不到就成了单向镜；
##   而「进大厅前先确认自己登录了」也是这条最便宜的自检。
## ★ 拿不到昵称时**明说**「未连接 Steam」而不是留空：留空会被读成「我的昵称是空的」，
##   而实际是「Steam 没起来」（同族的「量具说谎」比不显示更坏）。
func _refresh_duel_header() -> void:
	if _duel_me == null or not is_instance_valid(_duel_me):
		return
	var nm: String = SteamNet.my_persona()
	# ★ 2026-10-21 补「本局棋盘」（用户问「邀请好友在哪里选择棋盘呢？」）：
	#   本页是联机**唯一入口**，而盘的真源在**主菜单的棋盘行**（`_sel_board` / `_sel_size` /
	#   `_sel_hatkind` → `_eff_board_choice()`）。不写这一格，房主进局前不知道自己将开哪张盘，
	#   加入方更会以为"我在菜单选的盘算数" —— 实际联机的盘由房主定
	#   （`game.gd::_send_init()` 把整张盘：顶点/瓷砖/邻接/盘型标记/种子 整套下发，
	#     `_apply_snapshot()` 直接套用）。⇒ 一格文字消掉一整类"是不是选错了"的疑惑。
	_duel_me.text = "我：%s ｜ 联机战绩 %s ｜ 本局棋盘：%s（联机以房主所选为准）" % [
			nm if nm != "" else "未连接 Steam", GameConfig.record_str(), _duel_board_summary()]


## 本局将用哪张盘的可读摘要（盘名·大小；爱因斯坦是 盘名·种类）。
## ★ **只读**：真源仍是 `_eff_board_choice()`（主菜单那三个 `_sel_*`），这里不另存状态，
##   也不自己判"爱因斯坦没有大小档"那条规则 —— 大小一律走 `MenuModel.size_row_value()`。
func _duel_board_summary() -> String:
	var ch: Dictionary = _eff_board_choice(false)
	var bid: int = int(ch.get("board", GameConfig.BOARD_PENROSE))
	var sz: int = int(ch.get("size", GameConfig.STANDARD))
	var nm: String = MenuModel.board_label(bid)
	if MenuModel.is_hat_board(bid):
		nm += "·" + MenuModel.hat_kind_label(int(ch.get("hat_kind", GameConfig.HAT_HAT)))
	return "%s·%s" % [nm, MenuModel.size_row_value(bid, sz)]

# ====== 对弈页的本局设置：棋盘 / 大小 / 座位（2026-10-21）======
## 座位下拉的显示名。★★ **顺序就是** `GameConfig.SEAT_BLACK/WHITE/RANDOM` 的数值（0/1/2）：
##   "索引即常量"在这里是契约 —— 顺序一改，选「我执白」就会真的发黑，而且**不报错**。
##   由 `--steamuitest` ⑭ 双向钉住（既查这张表的内容，也查它写进 GameConfig 的值）。
const SEAT_PICK_LABELS: Array[String] = ["我执黑", "我执白", "随机"]

## 一行「标签 + 下拉」。三个选择器共用这一处建法（否则是三份几乎一样的 8 行）。
## ★ `_style_page_button()` 会把它登记进 `_page_btns`（主题切换时 `_restyle_page_buttons()`
##   会一起重套盒子）—— OptionButton 是 Button 的子类，走同一套主题没错。
func _duel_make_pick_row(parent: VBoxContainer, label_text: String, items: Array,
		cb: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(row)
	var lb := _ui_label(label_text, 16)
	lb.custom_minimum_size = Vector2(56.0, 0.0)
	row.add_child(lb)
	var opt := OptionButton.new()
	opt.name = "DuelPick" + label_text
	opt.custom_minimum_size = Vector2(240.0, 36.0)
	opt.focus_mode = Control.FOCUS_NONE
	for it in items:
		opt.add_item(str(it))
	_style_page_button(opt)
	opt.item_selected.connect(cb)
	row.add_child(opt)
	return opt

## 棋盘下拉的项 = **当前启用的全部棋盘**。
## ★ 真源 `MenuModel.enabled_board_kinds()`：占位的「敬请期待」**不进**列表 ——
##   放进去玩家点了也开不了局（而且 `enabled=false` 那本来就是"没实现"的占位）。
func _duel_board_pick_labels() -> Array:
	var out: Array = []
	for k in MenuModel.enabled_board_kinds():
		out.append(str(k["label"]))
	return out

## 大小下拉的项 = 三档（随机 / 标准 / 加强）。
## ★ 爱因斯坦盘**禁用**这个下拉（它的大小由种类决定，见 `MenuModel.effective_choice()`），
##   而不是把项换成"由棋盘决定"—— 换项会让 `select()` 的索引语义跟着变，
##   三档索引与 `MenuModel.slots()` 的对应关系就断了（本工程最忌讳的"索引换个含义"）。
func _duel_size_pick_labels() -> Array:
	var out: Array = []
	var bid: int = int(_eff_board_choice(false).get("board", GameConfig.BOARD_PENROSE))
	for slot in MenuModel.slots():
		out.append(MenuModel.size_label(int(slot), bid))
	return out

## 三个下拉的选中项 / 可用状态 —— **唯一派生点**（建页、每次改选、切档都走它）。
## ★ 全部从真源现读，不缓存：`_sel_board` / `_sel_size` / `GameConfig.seat_choice`
##   才是状态，下拉只是它们的显示器（铁律 7 的"派生"那一半）。
func _refresh_duel_picks() -> void:
	var ch: Dictionary = _eff_board_choice(false)
	var bid: int = int(ch.get("board", GameConfig.BOARD_PENROSE))
	var sz: int = int(ch.get("size", GameConfig.STANDARD))
	var hat: bool = MenuModel.is_hat_board(bid)
	if _duel_board_opt != null and is_instance_valid(_duel_board_opt):
		var kinds: Array = MenuModel.enabled_board_kinds()
		for i in kinds.size():
			if int(kinds[i]["id"]) == bid:
				_duel_board_opt.select(i)
				break
	if _duel_size_opt != null and is_instance_valid(_duel_size_opt):
		_duel_size_opt.disabled = hat
		_duel_size_opt.tooltip_text = "爱因斯坦盘的大小由种类决定（帽子 / 海龟 / 幽灵 各一套）" if hat else ""
		var slots: Array = MenuModel.slots()
		for i in slots.size():
			if int(slots[i]) == sz:
				_duel_size_opt.select(i)
				break
	if _duel_seat_opt != null and is_instance_valid(_duel_seat_opt):
		_duel_seat_opt.select(clampi(int(GameConfig.seat_choice), 0, SEAT_PICK_LABELS.size() - 1))

## 下拉 → 真源。棋盘 / 大小走主菜单那两条**唯一入口**，座位写 `GameConfig.seat_choice`。
## ⚠️ `_select_board()` 只置"待切换"（`_board_pending`），落定必须 `_commit_board_pending()`
##    —— 少这一句就是"下拉显示雪花、`_sel_board` 还是彭罗斯"，而且没有任何报错。
func _on_duel_board_pick(idx: int) -> void:
	var kinds: Array = MenuModel.enabled_board_kinds()
	if idx < 0 or idx >= kinds.size():
		return
	_select_board(int(kinds[idx]["id"]))
	_commit_board_pending()
	_refresh_duel_picks()
	_refresh_duel_header()

func _on_duel_size_pick(idx: int) -> void:
	var slots: Array = MenuModel.slots()
	if idx < 0 or idx >= slots.size():
		return
	_select_size(int(slots[idx]))
	_refresh_duel_picks()
	_refresh_duel_header()

## 座位下拉（**房主视角**）：加入方选它没有意义 —— 它的颜色由房主经 `init` 消息下发
## （`game.gd::_send_init()` 的 `net_color`）。这一栏存在是为了让房主建房前能换边。
func _on_duel_seat_pick(idx: int) -> void:
	GameConfig.seat_choice = clampi(idx, GameConfig.SEAT_BLACK, GameConfig.SEAT_RANDOM)
	_refresh_duel_picks()
	_refresh_duel_header()

## 页内容的可用下沿（**唯一真源**：底栏行带上沿 − 净空）。
## ★ 与设置页 / 棋谱页同一口径（读 `_footer_band()`），别再写 `size.y - 常数`：
##   底栏高度是布局意图常量，内容必须**让位给它**，而「让多少」只能有一处说了算。
func _duel_panel_bottom() -> float:
	return _footer_band().position.y - FOOT_GAP

## 建对弈页控件树（`_set_page(PAGE_LOBBY)` 调；每次先销毁上一棵）。
## ★ 本函数**绝不碰 Steam**：页面能画出来与「Steam 可用」是两件事 ——
##   把环境判断塞进建页里，自检与无 Steam 的机器就都看不到页面
##   （旧实现把闸放在 `_open_lobby_panel()` 而不是 `_build_lobby_panel()`，同一条纪律；
##    现在由 `_select_netmode()` 与 `_refresh_lobby_list()` 两道闸守）。
func _build_duel_ui() -> void:
	_clear_duel_ui()
	var duel_bottom: float = _duel_panel_bottom()
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_top = TOP_MARGIN + 12.0
	root.offset_bottom = -(size.y - duel_bottom)
	root.offset_left = DUEL_PAD
	root.offset_right = -DUEL_PAD
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_duel_root = root

	# ── 页首：我 ──
	_duel_me = _ui_label("", 18)
	# ★ 这一行现在带「本局棋盘」⇒ 可能变长。Label 会按文本撑开**最小宽度**，不夹住就把整页
	#   顶出右沿（大厅列表那几处踩过同一条）。夹住 + 省略号：宁可截断，也不许挤坏布局。
	_duel_me.clip_text = true
	_duel_me.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(_duel_me)

	# ── 两档切换块 ──
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)
	_duel_tabs.clear()
	for id in DUEL_TAB_ORDER:
		var b := Button.new()
		b.text = _netmode_label(id)
		b.toggle_mode = true                  # 按下态由 `_refresh_duel_tabs()` 派生（铁律 7）
		b.custom_minimum_size = Vector2(DUEL_TAB_W, 40.0)
		b.pressed.connect(_on_duel_tab_pressed.bind(id))
		tabs.add_child(b)
		_duel_tabs[id] = b
	# ★★ 这里**曾经**有一句 `_refresh_duel_tabs()`（"建完切换块就派生"）—— 那是**空转**：
	#   此刻两块内容还没建出来（两个成员都是 null）⇒ 一个 `visible` 都没设过
	#   ⇒ 首帧**两块同时可见**。派生的唯一正确时点在函数末尾（两块都建好之后），见那里。
	#   ⚠️ 别在这里补回来：它看着"更早生效"，实际什么都没做。

	# ── 好友联机（档 NET_INVITE）──
	# ★ 文案是**常量**（第 5 步删掉自建中继后只剩 Steam 一种语义）⇒ 就地写死，
	#   不再抽「刷新文案」的函数：一套只有一种取值的刷新函数等于给常量做断言
	#   （本工程在 `MenuModel.netmode_label` 上正是因为这个把它删掉的）。
	_duel_invite_box = VBoxContainer.new()
	_duel_invite_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_duel_invite_box.add_theme_constant_override("separation", 10)
	root.add_child(_duel_invite_box)
	# ── 本局设置：棋盘 / 大小 / 座位（2026-10-21 用户口令「联机页面加入棋盘选择下拉列表，
	#    把当前全部棋盘都放进去，还要能选择座位（黑白棋）」）────────────────────────
	# ★★ 这三个下拉**不另存状态**：棋盘写 `_sel_board`、大小写 `_sel_size`（都走主菜单那两条
	#   唯一入口 `_select_board()` / `_select_size()`），座位写 `GameConfig.seat_choice`。
	#   为什么必须同源：主菜单那排瓷砖也是同一份状态 —— 各存一份就会出现
	#   「下拉说雪花、瓷砖高亮彭罗斯、开局用的是第三个」（本工程在完全同型的地方踩过好几次）。
	# ★ 用的都是**真入口**：`_select_board()` 只置"待切换"，落定还要 `_commit_board_pending()`
	#   —— 少这一句的话下拉看着变了、实际 `_sel_board` 没动（静默）。
	var picks := VBoxContainer.new()
	picks.name = "DuelPicks"
	picks.add_theme_constant_override("separation", 8)
	picks.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_duel_invite_box.add_child(picks)
	_duel_board_opt = _duel_make_pick_row(picks, "棋盘", _duel_board_pick_labels(),
			_on_duel_board_pick)
	_duel_size_opt = _duel_make_pick_row(picks, "大小", _duel_size_pick_labels(),
			_on_duel_size_pick)
	_duel_seat_opt = _duel_make_pick_row(picks, "座位", SEAT_PICK_LABELS,
			_on_duel_seat_pick)
	# ★ 需求「一定要双方都准备好了再进入对局」在 UI 上必须**提前说清**：
	#   真正的闸在对局侧（`game.gd::_can_local_play()` 的 `_net_phase != "playing"` +
	#   双方各点「准备」→ 房主广播 start），这里只负责让玩家知道有这么一道闸，
	#   免得有人以为"点了建房就能落子"。
	var prep := _ui_label("双方进入对局后各点一次「准备」，两人都准备好才开始落子", 16)
	prep.add_theme_color_override("font_color", GameConfig.ink_color())
	_duel_invite_box.add_child(prep)
	_code_hint = _ui_label("Steam 房间号：建房后显示在对局界面（右上角），把它发给好友", 16)
	# ★★ 别用写死的浅灰（0.82,0.84,0.88）：那是**旧浮层**的配色 —— 旧面板自带深色底
	#   （`_lobby_bg` α=1.0），所以浅字读得出来；本页没有自绘底色、背景是主题色，
	#   浅色系主题下浅灰字几乎看不见（目检实测就是一条淡痕）。
	#   ⇒ 一律走 `_ui_label()` 的主题自适应墨色（与棋谱页/设置页同一条纪律：
	#     配色不许写死，判据要读运行时亮度）。这行**显式**写出来而不是省掉，
	#     是为了把"这里曾经写死过颜色"留在纸面上。
	#   ⚠️ 2026-10-08 踩过：这段代码被"删旧族 + 重插"带回过旧版本一次
	#     （重插会把重插**之前**的手工修补一起丢掉）⇒ 重插后必须逐条对照改动清单。
	_code_hint.add_theme_color_override("font_color", GameConfig.ink_color())
	_duel_invite_box.add_child(_code_hint)
	_enter_btn = Button.new()
	_enter_btn.text = "Steam 建房并进入"
	_enter_btn.custom_minimum_size = Vector2(300.0, 40.0)
	_enter_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style_page_button(_enter_btn)          # 主题色（未选态）；本页按钮都浮在页面底上
	_enter_btn.pressed.connect(_host_enter_game)
	_duel_invite_box.add_child(_enter_btn)
	_join_hint = _ui_label("输入好友的 Steam 房间号", 16)
	_duel_invite_box.add_child(_join_hint)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	# ★ 别让输入行吃满整页宽：它是"一格输入 + 一个按钮"，拉成近千像素的长条既难看、
	#   也让「加入」跑到视线最右端（离它要操作的东西最远）。SHRINK_BEGIN = 只占内容宽。
	join_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_duel_invite_box.add_child(join_row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "房间号（数字）"
	_ip_edit.custom_minimum_size = Vector2(220.0, 34.0)
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.focus_mode = Control.FOCUS_ALL
	join_row.add_child(_ip_edit)
	_join_btn = Button.new()
	_join_btn.text = "加入"
	_join_btn.custom_minimum_size = Vector2(DUEL_JOIN_W, 34.0)
	_style_page_button(_join_btn)
	_join_btn.pressed.connect(_start_join)
	join_row.add_child(_join_btn)

	# ── 公开大厅（档 NET_LOBBY）──
	_duel_lobby_box = VBoxContainer.new()
	_duel_lobby_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_duel_lobby_box.add_theme_constant_override("separation", 10)
	root.add_child(_duel_lobby_box)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	# ★ 工具条与列表**同时**收进内容列宽（`DUEL_LIST_W`）：只收列表、让工具条铺满整页的话，
	#   「刷新」与它的状态行会飘在左边、列表却在中间，看着像两块不相干的东西。
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.custom_minimum_size = Vector2(DUEL_LIST_W, 0.0)
	_duel_lobby_box.add_child(bar)
	_lobby_refresh_btn = Button.new()
	_lobby_refresh_btn.text = "刷新"
	_lobby_refresh_btn.custom_minimum_size = Vector2(92.0, 34.0)
	_style_page_button(_lobby_refresh_btn)
	_lobby_refresh_btn.pressed.connect(_refresh_lobby_list)
	bar.add_child(_lobby_refresh_btn)
	_lobby_status = _ui_label("点「刷新」搜索正在等待的对手", 16)
	_lobby_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ★ clip 不能省：Label 会被长文案**撑大最小宽** ⇒ 把整页顶出右沿（与列表行同一族）。
	_lobby_status.clip_text = true
	bar.add_child(_lobby_status)
	_lobby_scroll = ScrollContainer.new()
	_lobby_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ★ 横向**不铺满**：收进 `DUEL_LIST_W` 的内容列宽（见该常量的注释：铺满会让「加入」
	#   飘到屏幕最右端，与它那一行的昵称隔开近千像素）。
	_lobby_scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_lobby_scroll.custom_minimum_size = Vector2(DUEL_LIST_W, 0.0)
	_lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lobby_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_duel_lobby_box.add_child(_lobby_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	_lobby_scroll.add_child(box)
	_lobby_list_box = box

	# ★★ 派生的**时机**是契约的一部分（2026-10-08，被目检抓出来的真 bug）：
	#   必须在**两块内容都建好之后**才落第一次 —— 曾经把它写在"建完切换块、还没建两块"的
	#   位置 ⇒ 那时 `_duel_invite_box` / `_duel_lobby_box` 都还是 null，两个 `visible`
	#   一个都没设过 ⇒ **首帧两块内容同时可见**（VBox 里叠着两套控件，截图一眼可见）。
	#   ⚠️ 这条坑**判据抓不到**：`--steamuitest` ②/`--labeltest` ③ 都自己显式调
	#   `_refresh_duel_tabs()` 再量（量的是函数，不是"建页有没有调它"）
	#   ⇒ 又一条"探针/判据/目检三件分工"（铁律 11）。现已补 ⓪ 号判据专守"建页即自洽"。
	_refresh_duel_tabs()
	_refresh_duel_header()
	_refresh_duel_picks()


## 销毁对弈页控件树 + **清干净所有引用**（切页 / 重建时调用）。
## ★ 清引用只有 `_forget_duel_refs()` 一处（铁律 8：清空点也是写点）——
##   本页成员已有 14 个，手写清空必然漏掉新增的那几个（旧实现踩过：留下指向已 `queue_free()`
##   节点的悬空引用，访问即报错，或更坏：报错被吞）。
func _clear_duel_ui() -> void:
	if _duel_root != null and is_instance_valid(_duel_root):
		_duel_root.queue_free()
	_forget_duel_refs()

func _forget_duel_refs() -> void:
	_duel_root = null
	_duel_me = null
	_duel_tabs.clear()
	_duel_invite_box = null
	_duel_lobby_box = null
	_code_hint = null
	_enter_btn = null
	_join_hint = null
	_ip_edit = null
	_join_btn = null
	_lobby_refresh_btn = null
	_lobby_status = null
	_lobby_scroll = null
	_lobby_list_box = null
	_duel_board_opt = null
	_duel_size_opt = null
	_duel_seat_opt = null

## 切换块的回调：**点击时现判含义**（铁律 7）—— 「这一块指哪一档」由它绑定的 id 现判，
## 档位切换本身交给 `_select_netmode()`（那里有环境闸 + 翻档 + 派生三件，一处写）。
## ★★ 末尾**无条件**重派生一次，这条看着多余、其实是在堵一个静默坏法：
##   `toggle_mode` 的按钮**自己**会把 `button_pressed` 翻面 ⇒ 连点当前档时它会翻成「未按下」，
##   而 `_select_netmode()` 对同档早退（防连点抖面板）⇒ 不重派生就留下
##   「当前档的块看起来没被选中」的假象（「点了没反应」同一家）。
func _on_duel_tab_pressed(id: int) -> void:
	_select_netmode(id)
	_refresh_duel_tabs()

## 两个切换块此刻的按下态（id → bool）。**给判据用的唯一读法** ——
## 判据不自己去 `_duel_tabs` 里翻字典（那是内部结构），也不另算一遍派生逻辑。
func _duel_tab_state() -> Dictionary:
	var out: Dictionary = {}
	for id in _duel_tabs.keys():
		var b: Button = _duel_tabs[id]
		out[int(id)] = (b != null and is_instance_valid(b) and b.button_pressed)
	return out

## 从**控件树**里找出第 id 档的切换块（判据用）。
## ★★ 为什么必须从控件出发：读 `_duel_tabs` 是"自己人给自己人打分"—— 按钮没接上、
##   甚至没建出来，照样能读到按下态。而"按钮连错 / 没连"正是"点了没反应"那一族
##   （与棋谱面板 ⑫ 的工具栏接线同一条纪律，见 rules.md §13⑫）。
func _duel_find_tab_button(id: int) -> Button:
	return _duel_find_button(_duel_root, _netmode_label(id)) as Button

func _duel_find_button(node: Node, text: String) -> Button:
	if node == null or not is_instance_valid(node):
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for c in node.get_children():
		var hit := _duel_find_button(c, text)
		if hit != null:
			return hit
	return null

func _refresh_lobby_list() -> void:
	_clear_lobby_list()
	if _lobby_status:
		_lobby_status.text = "正在搜索对手…"
	if not SteamNet.steam_lobby_list_received.is_connected(_on_lobby_list_received):
		SteamNet.steam_lobby_list_received.connect(_on_lobby_list_received)
	SteamNet.request_lobby_list()

func _clear_lobby_list() -> void:
	if _lobby_list_box == null:
		return
	for c in _lobby_list_box.get_children():
		_lobby_list_box.remove_child(c)
		c.queue_free()

func _on_lobby_list_received(ids: Array) -> void:
	_clear_lobby_list()
	if ids.is_empty():
		if _lobby_status:
			_lobby_status.text = "没有在等待的对手（点「刷新」重试）"
		return
	if _lobby_status:
		_lobby_status.text = "找到 %d 位玩家" % ids.size()
	for e in ids:
		var lid := int(e)
		if lid == 0:
			continue
		_lobby_list_box.add_child(_make_lobby_row(lid))

## 大厅列表里的一行 = **两行**（昵称+加入 / 胜率），不是原来的一行三列。
## ★★ 为什么必须改结构（2026-10-02）：大厅面板搬进共用槽位后宽度只有 240（内宽 224），
##   而原来一行三列是 150+150+72+2×8 = **388 零余量**。要么砍字号砍到读不清，要么砍列宽
##   砍到昵称只剩两三个字 —— 都等于把"能看见谁在等"这件事做坏。
##   两行版读起来更清楚（昵称独占一行，不必与胜率抢宽），且**长昵称只影响自己那一行**。
## ★ 昵称与胜率都用 EXPAND_FILL + clip + 省略号：余量全给它们，「加入」宽度固定
##   （`LOBBY_JOIN_W`）⇒ 任何长度的昵称都**不可能**把按钮顶出面板右沿。
##   这与 `_fit_online_panel_children()` 里「输入框吃余量、按钮固定」是同一条纪律。
const LOBBY_JOIN_W: float = 64.0
const LOBBY_ROW_MIN_W: float = 60.0
func _make_lobby_row(lid: int) -> Control:
	var nm := String(SteamNet.lobby_get_data(lid, SteamNet.LOBBY_NAME_KEY))
	if nm == "":
		nm = "玩家"   # 兜底：没写昵称的房（旧构建房主）
	var rec := String(SteamNet.lobby_get_data(lid, SteamNet.LOBBY_RECORD_KEY))
	if rec == "":
		rec = "—"
	var row := _lobby_row_shell()
	var name_lbl := _lobby_row_name(nm)
	var rec_lbl := _lobby_row_record(rec)
	var join := Button.new()
	join.text = "加入"
	join.custom_minimum_size = Vector2(LOBBY_JOIN_W, 30)
	join.size = Vector2(LOBBY_JOIN_W, 30)
	_style_page_button(join)
	join.pressed.connect(_join_lobby.bind(lid))
	_lobby_row_line1(row).add_child(name_lbl)
	_lobby_row_line1(row).add_child(join)
	row.add_child(rec_lbl)
	return row

## 与 `_make_lobby_row()` 同构，但昵称/胜率**由参数给**（截图夹具专用，不读 Steam）。
## ★ 刻意复制而不是给 `_make_lobby_row()` 加可选参数：那函数是生产路径，
##   给它挂"只在截图时为真"的分支 = 往真源里塞一条测试专用岔路（铁律：判据/夹具不碰真源）。
##   ⚠️ 但**排版部分共用** `_lobby_row_shell/_lobby_row_name/_lobby_row_record` ——
##   排版是生产关注点（长昵称顶出「加入」是用户看得见的 bug），不该各写一份：
##   两份排版各改一处 ⇒ 有一半概率"截图看着好、实机坏"（截图恰好是唯一目检件）。
func _make_lobby_row_shot(nm: String, rec: String) -> Control:
	var row := _lobby_row_shell()
	_lobby_row_line1(row).add_child(_lobby_row_name(nm if nm != "" else "玩家"))
	_lobby_row_line1(row).add_child(Button.new())
	var jb := _lobby_row_line1(row).get_child(1) as Button
	jb.text = "加入"
	jb.custom_minimum_size = Vector2(LOBBY_JOIN_W, 30)
	jb.size = Vector2(LOBBY_JOIN_W, 30)
	# ★ 截图夹具与生产行**同样套主题色样式**：夹具的用途就是"截图 = 实机观感"，
	#   少套一次样式会让截图里的「加入」是一块引擎默认灰按钮 —— 而这张截图正是唯一目检件，
	#   于是"实机已主题化"这件事在目检里反而看不出来（夹具与生产的外观分叉 = 目检说谎）。
	_style_page_button(jb)
	row.add_child(_lobby_row_record(rec))
	return row

## 行的外壳：VBox（两行之间 4px）。
func _lobby_row_shell() -> VBoxContainer:
	var row := VBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 58)
	row.add_theme_constant_override("separation", 4)
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 6)
	row.add_child(line1)
	return row

## 第一行容器（昵称 + 「加入」）。取 child(0) 而不是再存一个成员 ——
## 行是每次刷新重建的短命对象，存成员反而多一处"忘了清"的引用。
func _lobby_row_line1(row: Node) -> HBoxContainer:
	return row.get_child(0) as HBoxContainer

func _lobby_row_name(nm: String) -> Label:
	var name_lbl := Label.new()
	name_lbl.text = nm
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.custom_minimum_size = Vector2(LOBBY_ROW_MIN_W, 0)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 16)
	return name_lbl

func _lobby_row_record(rec: String) -> Label:
	var rec_lbl := Label.new()
	rec_lbl.text = "胜率 %s" % (rec if rec != "" else "—")
	rec_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec_lbl.custom_minimum_size = Vector2(LOBBY_ROW_MIN_W, 0)
	rec_lbl.clip_text = true
	rec_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# ★ 2026-10-13 重设计：13 → 16（L5 辅助层）。13px 的中文在这个尺寸下笔画粘连、
	#   几乎不可读，而这是"胜率"这种需要被看到的辅助信息。16 与同层的 16（L4 上沿的
	#   紧凑按钮字）同档，L3/L4/L5 阶梯自此在设置区也统一了。
	rec_lbl.add_theme_font_size_override("font_size", 16)
	rec_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	return rec_lbl

func _join_lobby(lid: int) -> void:
	# ★ 复用"输房间号加入"的唯一必经点（铁律 8：一处写一处读）。
	# 房间号的三个来源都走这里（2026-10-21 起）：
	#   ① 公开大厅列表点「加入」（`_make_lobby_row` 的按钮）
	#   ② 好友接受邀请 / Steam 好友列表「加入游戏」（`_on_steam_join_requested`）
	#   ③ 被邀请启动时命令行 `+connect_lobby`（`_bootstrap_steam_invites`）
	# ⇒ **不新开路径**：三条来源只是"房间号从哪来"不同，校验顺序与环境闸必须完全一样
	#   （结构守卫 S89 盯着这一行只出现一次，就是为了防止有人再抄一份"快捷加入"）。
	_steam_join_by_id(str(lid))

## 截图专用（`--screenshot --shotpage=lobby`）：把联机大厅面板摆成"有对手"的样子再截。
## ★ 为什么需要它：面板全是**原生控件**（ColorRect/Label/Button/HBox），而
##   `_make_lobby_row()` 的昵称与胜率**只能从 Steam lobby data 读**（`SteamNet.lobby_get_data`）
##   ⇒ 本机没有第二个账号、也没有别人建房 ⇒ 真实列表恒为空，"排版好不好看"永远截不到。
##   与 `--shotdrop` 同一思路：**夹具造数据、目检看图**，不为了让截图能跑而改生产路径。
## ★ 假数据必须**长度各异**且含"无战绩"那一档（`record == ""` ⇒ 显示 "胜率 —"），
##   否则截出来的图只证明"等宽字符串能排下"，证明不了长昵称/无战绩两档会不会撑破行宽。
## 截图专用（`--screenshot --shotpage=lobby`）：把「公开大厅」档摆成"有对手"的样子再截。
## ★ 为什么需要它：列表全是**原生控件**（Label/Button/HBox），而 `_make_lobby_row()` 的昵称与
##   胜率**只能从 Steam lobby data 读**（`SteamNet.lobby_get_data`）⇒ 本机没有第二个账号、
##   也没有别人建房 ⇒ 真实列表恒为空，"排版好不好看"永远截不到。
##   与 `--shotdrop` 同一思路：**夹具造数据、目检看图**，不为了让截图能跑而改生产路径。
## ★ 假数据必须**长度各异**且含"无战绩"那一档（`record == ""` ⇒ 显示 "胜率 —"），
##   否则截出来的图只证明"等宽字符串能排下"，证明不了长昵称/无战绩两档会不会撑破行宽。
## ★ 2026-10-08：本夹具跟着页走 —— 直接落到「对弈」页的大厅档（**不碰 Steam**：
##   旧版走 `_select_netmode()` 会被环境闸挡下、截出空图）。
func _menu_shot_lobby() -> void:
	await get_tree().process_frame
	_sel_netmode = NET_LOBBY
	_set_page(PAGE_LOBBY)
	_layout_setup()
	if _lobby_status:
		_lobby_status.text = "找到 4 位玩家"
	_clear_lobby_list()
	var fake := [
		["玩家甲", "80%（8胜2负）"],
		["一个名字很长的陌生对手", "50%（1胜1负）"],
		["玩家丙", ""],           # 无战绩 ⇒ 该行显示 "胜率 —"
		["Steam游客_12345678", "0%（0胜3负）"],
	]
	for e in fake:
		_lobby_list_box.add_child(_make_lobby_row_shot(String(e[0]), String(e[1])))
	print("[shotlobby] 夹具填入 %d 行（长昵称 + 无战绩两档都含）｜页=%d 档=%s 页内宽=%.0f" % [
		fake.size(), _page, _netmode_label(_sel_netmode), _duel_root.size.x])

## 「对战方式」行某一档此刻该不该高亮 —— **建项处的 `sel` 与运行期的
## `_refresh_selection()` 共用的唯一口径**。
##
## `mode_id` = 这一块代表哪种对局方式（★ 身份字段，**不许**按 label 字面认 —— 见下）。
##
## ★★ 为什么必须只有这一份（2026-10-09，`--menutest` ⑭ 逮到的真 bug）：
##   难度三档从独立 group `"diff"` 平铺进 `"mode"` 之后，`_refresh_selection()` 那一臂
##   仍按 **label 字面**认「本地 / 人机」，难度档的 label 是「简单/普通/困难」
##   ⇒ 点难度走 `_select_diff() → _refresh_selection()` 时**三档全被判不高亮**。
##   屏幕上的样子：点了「困难」**一个实心块都不剩**，而 AI 确实按困难在下 —— 静默。
##   ⚠️ 建项处的 `sel` 一直是**对的**（它按 `_sel_diff` 算）⇒ 坏的只有"运行期重新派生"
##   这一路，于是**所有只看建项结果的判据一条也抓不到**（⑭ 就是为它补的）。
##   ⚠️ 与 `boardsize` 组当年同一个坑（那一族早已改成按 `size_id` 匹配）—— 同一个
##   "用内容当身份"的坏法，第二次出现。**这里不再重复第三遍**。
##
## ★ 2026-10-12：难度删除后本判据退化成"**对局方式相等**"这一条 —— 但**身份字段必须保留**：
##   把 `mode_id` 省掉、改回按 label 认，就正好复现上面那条 bug 的写法（第三次）。
##   `--menutest` ⑭ 的阴性对照（把 `==` 改成 `>=`）现在量的是"身份字段还在不在被用"。
##
## ★★ 2026-10-15b 并列化后，本判据**彻底退化成相等** —— 这正是目标形态：
##   ⚰️ 改前：`if mode_id == MODE_XGAI: return _sel_mode == MODE_VS_AI and _sel_xgai`
##     ⇒ 点「疾风」时「磐石」也返回 true（`_sel_mode` 被写成 VS_AI）—— **两块一起亮**。
##     用户的这句话就是冲它来的：「人机和疾风两个按钮逻辑有问题，改成并列的关系」。
##   ★ 现在三块是并列项 ⇒ `_sel_mode` 是什么，就只有那**一块**亮，结构上不可能出现两块。
##   ★ ⑭ 的阴性对照因此补了一把**直接复现旧写法**的刀（"父子判定"刀）：把 MODE_XGAI 那一支
##     改回"依赖 `_sel_mode == MODE_VS_AI`"，⑭ 必须当场红 —— 那才是这条口令的回归牙齿。
func _mode_tile_selected(mode_id: int) -> bool:
	return _sel_mode == mode_id

## 底栏某一档此刻该不该高亮 —— **建项处的 `sel` 与运行期的
## `_refresh_selection()` 共用的唯一口径**（与 `_size_slot_selected` / `_mode_tile_selected`
## 同一条纪律：谁都不许另写一份）。
##
## ★★ 为什么必须补这一份（2026-10-16 用户报的真 bug）：
##   用户口令「主菜单**切换棋盘刷新后「练习」的已选状态会取消**」。
##   底栏四块建项时 `sel = _page == 目标页`（见 `_footer_entry_descriptors()`），而
##   `_refresh_selection()` 的 `match` **没有 `"nav"` 臂** ⇒ `now_sel` 恒 `false`
##   ⇒ **点一下棋盘**（`_select_board()` 末尾就调 `_refresh_selection()`）就把「练习」的
##   凹陷态抹掉 —— 屏幕上的样子是"我看不出自己在哪个面板了"，而不会有任何报错。
##   ⚠️⚠️ 坏的只有"运行期重新派生"这一路：**建项处的值一直是对的** ⇒ 所有只看建项结果的
##     判据（含 `--menutest` ⑤b，它走 `_set_page()` = **重建**条目）一条也抓不到。
##     这与 2026-10-09 `"diff"` 那一臂是**同一个坑，第三次**（见 `_mode_tile_selected` 的注）
##     —— 所以这次连判据一起补：`--menutest` ⑤b2（走 `_select_board()` 这条真实路径）。
##
## ★ `page_id` 是**身份字段**（与 `size_id` / `mode_id` 同款，**不许按 label 字面认**）：
##   底栏四个 label 是给人读的，将来改名（「棋谱」→「棋谱库」）不该影响选中态，
##   更不该"按名字匹配到别的块"—— 那正是本工程复现过三次的坏法（用内容当身份）。
func _nav_tile_selected(page_id: int) -> bool:
	return _page == page_id

# 根据当前选择状态刷新各瓷砖的 selected 标记并重绘。
# ★★ 2026-10-12：`selected` 现在是**唯一**的"已选"真源 —— 绘制侧按它决定"凸起 / 凹陷"
#   （旧版还要把它同步进 `_stones` 去铺黑砖，那个第二份记账随黑砖族整族删除）。
func _refresh_selection() -> void:
	for i in _items.size():
		var it: Dictionary = _items[i]
		var now_sel := false
		match it["group"]:
			"board":
				# 用「有效选中」而非 _sel_board：切换动画期间凹陷态立即跟到新块，
				# 折叠锚点仍用 _sel_board（旧块），才能绕旧锚点收回。
				now_sel = (it["label"] == _board_label(_eff_board()))
			"boardsize":
				# 标签与选中态都按 size_id（= 槽位号）走**同一份口径**（标签随棋盘类型变，不能按字面匹配）。
				# ★ 三个槽位**一律**改写标签（原实现只改写槽位 0）—— 否则从爱因斯坦切回普通棋盘时，
				#   槽位 1/2 会留着「海龟/幽灵」，就是用户说的「其他棋盘的标准/加强被改名了」。
				#   回调不在这里：它是 `_activate_size_slot`（点击时现判含义），所以本处不必动它 ——
				#   这也正是「语义与回调」不再可能分叉的原因。
				var sid: int = int(it.get("size_id", -99))
				it["label"] = _size_slot_label(sid)
				now_sel = _size_slot_selected(sid)
			"mode":
				# ★★ 2026-10-09 修（`--menutest` ⑭ 逮到）：本臂**走身份字段**，不按 label 字面匹配。
				#   原实现只认「人机 / 本地」两个 label，而难度三档平铺进本组之后 label 是
				#   「简单/普通/困难」⇒ 点难度时三档全被判不高亮（AI 却真按该档在下）。
				#   ⚠️ 建项处 `sel` 一直是对的 ⇒ 这条坏法**只在"运行期重新派生"这一路**上，
				#   只看建项结果的判据一条也抓不到。现在两处同调 `_mode_tile_selected()`。
				now_sel = _mode_tile_selected(int(it.get("mode_id", -1)))
			# ⚰️ 这里原有 `"diff":` 一臂（难度三档的选中态）。难度档已并入 `mode` 组 ⇒ 那一臂
			#   **永不命中**（恒假的闸 = 没闸，铁律 4）⇒ 并入上面那一臂。
			#   ⚠️ 别再"另起一臂按 label 认"：那正是上面那条 bug 的复现方法。
			"nav":
				now_sel = _nav_tile_selected(int(it.get("page_id", -1)))
				# ★★ 2026-10-16 补（用户报的 bug：「主菜单切换棋盘刷新后『练习』的已选状态会取消」）：
				#   本臂原先**根本不存在** ⇒ 底栏四块的 `now_sel` 恒 false ⇒ `selected` 被无条件
				#   写成 false。这里走身份字段 `page_id`，与建项处同调 `_nav_tile_selected()`。
				#   ⚠️ `"action"`（开始）**故意不进本臂**：它建项时就是 `sel: false`
				#     （「开始」是动作不是状态）⇒ 恒 false 才是对的，别"顺手"给它也派生一个。
				#   ⚠️ 判据侧同步补了 `--menutest` ⑤b2（走 `_select_board()` 这条**真实路径**）；
				#     ⑤b 抓不到它 —— 那条走 `_set_page()` ⇒ 读的是**建项处**的值，而建项处一直是对的。

		it["selected"] = now_sel
		# ⚰️ 2026-10-12：这里原有「把选中项同步进 `_stones`（铺黑子）/ 取消选择则移除，
		#   并触发落子或提子动画」那一整段 —— 随黑砖族整族删除。
		#   ⇒ `selected` 现在是**唯一**的选中态真源，没有再需要跟它同步的第二份记账。
	_sync_menu_bg()        # ★ 同理：首页主视觉的背景盘型也跟选择走（2026-10-02 重设计）。
	#   ★ 挂在这个"选择变了"的统一收口上，而不是散在 `_select_board` / `_activate_size_slot`
	#   各自调一遍 —— 后者是"两处真相"的温床：将来新增一条改选择的路径就会漏掉背景同步，
	#   而症状是"背景还是上一张盘"，**静默**且不像 bug。
	queue_redraw()

# ====== 设置**面板**（原生控件，非瓷砖）======
# 设置界面用普通 UI 控件（滑块 / 复选 / 按钮），居中、随窗口自适应；
# 不再使用菱形瓷砖按钮。所有控件挂在 _settings_root 下，切换面板时整体销毁。
func _build_settings_ui() -> void:
	_clear_settings_ui()
	var vw := get_viewport_rect().size.x
	# ★★ 2026-10-04 v4：设置从"独立页"变成**主菜单的一个面板** ⇒ 这棵控件树必须
	#   **整棵落在底栏行带之上**（下沿 = `_footer_band().position.y - FOOT_GAP`）。
	#   为什么这条是硬要求：底栏四块是"换面板"的唯一入口，被控件树盖住就是**出不去**
	#   （而它盖住的是自绘瓷砖，`_input` 仍能命中 ⇒ 症状是"砖看不见但点得到"，更怪）。
	#   ⚠️ 下沿必须读 `_footer_band()` 真源，不能写常数：行带高度是布局意图常量，
	#   写常数就会"行带改了、控件还压在它上面"，而那种错**只有看图才看得见**
	#   （`--settest` 的「不压底栏」量它）。
	var panel_bottom: float = _footer_band().position.y - FOOT_GAP
	# 左右分栏：左＝放大的主题预览，右＝设置内容。
	# 两栏宽度都随屏幕自适应并设上限——此前单列上限 1150 在宽屏下拉得过长，很不美观。
	var outer := HBoxContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 标题区高 TOP_MARGIN(132)：内容必须从其下方开始（原先 96 会压在「设置」标题上）
	outer.offset_top = TOP_MARGIN + 12.0
	# `offset_bottom` 是**相对父节点下沿**的距离 ⇒ 取负的"面板下沿到底栏带上沿的差"
	outer.offset_bottom = -(size.y - panel_bottom)
	outer.offset_left = 32.0
	outer.offset_right = -32.0
	outer.add_theme_constant_override("separation", 24)
	outer.mouse_filter = Control.MOUSE_FILTER_STOP   # 拦截点击，避免穿透到菜单瓷砖逻辑
	add_child(outer)
	_settings_root = outer

	# —— 左栏：外观预览（正方形，五角星按栏宽放大；上下用弹性空白把它垂直居中）——
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	var left_w := clampf(vw * 0.30, 280.0, 460.0)
	# 窗口很矮时按可用高度收敛，避免预览把说明文字挤出可视区
	# ★ v4：可用高度改按**面板**高度算（原来是"屏幕高 − 上下外边距"）—— 面板比整屏矮
	#   一整条底栏带，照旧算式会让预览按整屏高度放大、把右栏设置行挤出面板。
	var avail_h := maxf(panel_bottom - (TOP_MARGIN + 12.0) - 48.0, 180.0)
	# ★★ 2026-10-04 v4 修正（**扁视口下预览被压成非正方形**）：预览边长与左栏宽必须取
	#   **同一个量**。原先左栏宽写 `left_w`（= 屏宽的 30%）、预览高写 `minf(left_w, avail_h)`
	#   —— 只有"avail_h ≥ left_w"时这两个才相等，于是正方形是**假设**出来的而不是构造出来的。
	#   实测：`--winsize=1152x648`（**设计基准分辨率**）下 avail_h=338 < left_w=346
	#   ⇒ 预览 346×338 ⇒ `--settest`「预览近似正方形」**✗**。
	#   ⚠️ 为什么一直没发现：headless 视口恒 1152×1152（`--canvassize=` **也**改不动它，
	#     实测三次都是 1152）⇒ 这条判据在回归里**只跑过一档**，而它会出问题的那一档
	#     （扁屏）压根没跑过（铁律 4）。⇒ 修完另配一条**真窗口扁屏**回归，见 regress.sh。
	var preview_sz: float = minf(left_w, avail_h)
	left.custom_minimum_size = Vector2(preview_sz, 0.0)
	outer.add_child(left)
	_build_appearance_preview(left, preview_sz)

	# —— 右栏：设置内容（内容较多，用滚动容器包裹，小屏也能完整操作）——
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_STOP   # 拦截点击，避免穿透到菜单瓷砖逻辑
	outer.add_child(sc)
	# ScrollContainer 禁用横向滚动时会把子控件拉满整行宽（SHRINK_CENTER 失效）→ 文字全挤在左侧。
	# 套一层 CenterContainer，让内容列真正水平居中。
	var center := CenterContainer.new()
	sc.add_child(center)
	var root := VBoxContainer.new()
	# 内容列宽随屏幕自适应：窄屏至少 520，上限 720（再宽行内控件就被拉得过长）
	root.custom_minimum_size = Vector2(clampf(vw * 0.38, 520.0, 720.0), 0.0)
	root.add_theme_constant_override("separation", 14)
	center.add_child(root)

	# —— 声音（音乐 + 音效）——
	# ★ 2026-10-05：分组标签由「音效」改成「声音」—— 原来"背景音乐"滑条挂在"音效"
	#   分组底下，名不副实；新版音乐也不再是"背景音乐"（是固定节拍的拨弦生成）。
	root.add_child(_ui_group_label("声音"))
	# 音乐音量（新版音乐引擎：固定节拍 + 拨弦合成，和声随战况）
	var bgm_row := HBoxContainer.new()
	var bgm_sl := HSlider.new()
	bgm_sl.min_value = 0.0; bgm_sl.max_value = 100.0; bgm_sl.step = 1.0
	bgm_sl.value = int(Music.bgm_volume * 100.0)
	bgm_sl.custom_minimum_size = Vector2(260.0, 28.0)
	# 不 EXPAND_FILL：撑满整列会把滑条拉得过长（此前 1150 宽的列里尤其难看）
	var bgm_val := _ui_label("%d%%" % int(bgm_sl.value), 18)
	bgm_sl.value_changed.connect(func(v: float) -> void:
		Music.set_bgm_volume(v / 100.0)
		bgm_val.text = "%d%%" % int(v))
	bgm_row.add_child(_ui_label("音乐")); bgm_row.add_child(bgm_sl); bgm_row.add_child(bgm_val)
	root.add_child(bgm_row)
	# 音效音量
	var sfx_row := HBoxContainer.new()
	var sfx_sl := HSlider.new()
	sfx_sl.min_value = 0.0; sfx_sl.max_value = 100.0; sfx_sl.step = 1.0
	sfx_sl.value = int(Music.sfx_volume * 100.0)
	sfx_sl.custom_minimum_size = Vector2(260.0, 28.0)
	var sfx_val := _ui_label("%d%%" % int(sfx_sl.value), 18)
	sfx_sl.value_changed.connect(func(v: float) -> void:
		Music.set_sfx_volume(v / 100.0)
		sfx_val.text = "%d%%" % int(v))
	sfx_row.add_child(_ui_label("音效音量")); sfx_row.add_child(sfx_sl); sfx_row.add_child(sfx_val)
	root.add_child(sfx_row)
	# 静音
	var mute_row := HBoxContainer.new()
	var mute_cb := CheckButton.new()
	mute_cb.button_pressed = Music.muted
	mute_cb.toggled.connect(func(p: bool) -> void: Music.set_muted(p))
	mute_row.add_child(_ui_label("静音")); mute_row.add_child(mute_cb)
	root.add_child(mute_row)
	# 自动播放 BGM
	var auto_row := HBoxContainer.new()
	var auto_cb := CheckButton.new()
	auto_cb.button_pressed = Music.autoplay_bgm
	auto_cb.toggled.connect(func(p: bool) -> void:
		Music.autoplay_bgm = p
		if p: Music.play_bgm() else: Music.stop_bgm())
	auto_row.add_child(_ui_label("自动播放音乐")); auto_row.add_child(auto_cb)
	root.add_child(auto_row)
	root.add_child(_build_display_group())

	# —— 外观（背景色 / 瓷砖色，实时预览并持久化）——
	_build_appearance_group(root)


	# ★ 2026-09-30 §24 第 5 步：这里原有设置页的「联机」组 —— 一个信令服务器地址输入框
	#   + 保存按钮 + 一行说明（"两人必须用同一地址才能联机"）。它设置的是**自建信令服**的地址
	#   （`Matchmaking.server_url`，也会被 `save_server_url()` 落盘），随自建联机一起删除。
	#   Steam 侧的 P2P 由 Steam 自己做 NAT 穿透，**没有任何服务器地址需要玩家填** ——
	#   留着一个填了不生效的输入框，比没有更坏（"量具说谎"）。

	# —— 返回 ——
	var back := Button.new()
	back.text = "返回主菜单"
	back.custom_minimum_size = Vector2(240.0, 44.0)
	_style_page_button(back)
	back.pressed.connect(func() -> void: _set_page(PAGE_MAIN))
	root.add_child(back)

# ====== 显示设置（全屏 / 无边框全屏 / 窗口）======
## 三个模式按钮做互斥选择：点哪个就应用到窗口、存盘，并刷新按钮选中态。
## 即时生效（不需要重启），因为窗口模式是引擎级状态，改了立刻看得到。
func _build_display_group() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.add_child(_ui_group_label("显示"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_ui_label("屏幕模式"))
	var btns: Array[Button] = []
	var modes: Array[int] = [GameConfig.MODE_WINDOW, GameConfig.MODE_FULLSCREEN, GameConfig.MODE_BORDERLESS]
	for m in modes:
		var b := Button.new()
		b.text = GameConfig.window_mode_name(m)
		b.custom_minimum_size = Vector2(120.0, 34.0)
		b.toggle_mode = true
		b.pressed.connect(_on_display_mode_pressed.bind(m, btns))
		row.add_child(b)
		btns.append(b)
	box.add_child(row)
	_refresh_display_buttons(btns)
	var hint := _ui_label("全屏为独占模式；无边框全屏切出桌面更流畅，多屏/老显卡下更稳", 14)
	box.add_child(hint)

	# —— 图模式（2026-10-19 用户需求：「设置里加一个图模式开关，打开后棋盘以经典棋盘
	#    （点线）方式展示」）——
	# 归「显示」组而不是「外观」组：它是「进对局后画面怎么呈现」，与配色预设互不相干
	# （「恢复默认主题」不会把它一起抹掉）。
	var g_row := HBoxContainer.new()
	g_row.add_theme_constant_override("separation", 10)
	_graph_cb = CheckButton.new()
	# ★ 与 `_cursor_cb` 同一套写法：`toggled(bool)` + 回调开头的幂等守卫。
	#   （`_sync_graph_control()` 用**普通赋值**写 `button_pressed` —— 只有它会刷新
	#     CheckButton 的视觉，见 `_sync_cursor_controls()` 的实测记录 —— 而普通赋值**会**
	#     回调到这里 ⇒ 没有守卫的话「打开设置页」就等于写了一次盘。）
	_graph_cb.toggled.connect(_on_graph_mode_toggled)
	g_row.add_child(_ui_label("图模式")); g_row.add_child(_graph_cb)
	box.add_child(g_row)
	box.add_child(_ui_label("开：网格棋盘 + 圆形棋子（经典观感）；关：显示瓷砖面", 14))
	_sync_graph_control()
	return box

## 应用模式 + 存盘 + 刷新按钮选中态
func _on_display_mode_pressed(m: int, btns: Array[Button]) -> void:
	GameConfig.window_mode = m
	GameConfig.apply_window_mode()
	GameConfig.mark_appearance_dirty()      # 用户操作 ⇒ 置脏（第 0 步脏标记门，否则这次改动存不下来）
	GameConfig.save_appearance()
	_refresh_display_buttons(btns)
	_tip("屏幕模式：%s" % GameConfig.window_mode_name())

## 按钮选中态与 GameConfig.window_mode 对齐（用 toggle 高亮当前模式）
## ★★ 选中/未选**两套样式都在这里套**（同一处派生）：建控件时套一次、刷新时只改 `button_pressed`
##   的话，切模式之后"被按下的那个按钮"仍挂着**未选**的盒子 —— 按下态只有引擎默认主题给的
##   一点点明度差，"当前是哪个模式"就退化成看不出来（本页是"三个里选一个"，看不出等于没选）。
## 「图模式」开关：翻一下 → 立即落盘（进对局时 `game.gd::_draw()` 读
## `GameConfig.graph_mode` 决定铺不铺瓷砖面）。
## ★ 幂等守卫不可删，理由与 `_on_cursor_toggled()` 完全相同：`_sync_graph_control()`
##   用普通赋值写 `button_pressed`（普通赋值才会刷新视觉），那一下会回调到这里 ⇒
##   值没变就必须直接返回，否则「打开设置页」就写了一次盘
##   （`--settest` 的「打开设置页不写盘」守的正是这件事）。
func _on_graph_mode_toggled(on: bool) -> void:
	if on == GameConfig.graph_mode:
		return
	GameConfig.graph_mode = on
	GameConfig.mark_appearance_dirty()      # 用户操作 ⇒ 置脏（第 0 步）
	GameConfig.save_appearance()
	# ★ 自己再同步一次（与 `_on_cursor_toggled()` 一致）：
	#   真机上点开关时引擎已经把 `button_pressed` 翻好了，但 `--settest` 是用
	#   `toggled.emit()` 模拟的 —— 那条路上没人翻它 ⇒ 少了这句，判据量到的是"没接上"。
	_sync_graph_control()
	_tip("图模式：%s" % ("开（网格 + 圆棋子）" if on else "关（瓷砖面）"))

## 开关状态 ← `GameConfig.graph_mode`（唯一真源）。
## ★ 用普通赋值（不是 `set_pressed_no_signal()`）：后者不刷新 CheckButton 的视觉，
##   状态对了但画成灰的（`_sync_cursor_controls()` 那条注释里有实测记录）。
func _sync_graph_control() -> void:
	if is_instance_valid(_graph_cb):
		_graph_cb.button_pressed = GameConfig.graph_mode

func _refresh_display_buttons(btns: Array[Button]) -> void:
	var modes: Array[int] = [GameConfig.MODE_WINDOW, GameConfig.MODE_FULLSCREEN, GameConfig.MODE_BORDERLESS]
	for i in btns.size():
		if i < modes.size() and is_instance_valid(btns[i]):
			var on: bool = modes[i] == GameConfig.window_mode
			btns[i].button_pressed = on
			if on:
				_style_page_button_selected(btns[i])
			else:
				_style_page_button(btns[i])


# ====== 外观设置（背景色 / 瓷砖色）======
# 配色统一存于 GameConfig（user://appearance.cfg），菜单与对局场景共用。
# 设置页改动即时生效（菜单背景/瓷砖、文字对比度），关闭取色面板时才写盘。
## 把 GameConfig 的配色同步到菜单绘制变量，并刷新预览
func _apply_appearance() -> void:
	_bg_color = GameConfig.bg_color
	_fat_color = GameConfig.board_color   # 菜单瓷砖=主题棋盘色（与对局棋盘一致，宣纸=木黄…）
	_accent = GameConfig.accent_color()
	# ⚰️ 2026-10-12：这里原有 `_stone_accent = GameConfig.accent_color()` ——
	#   它的唯一读者是已删除的黑砖族 ⇒ 赋值一并删除（只写不读的成员）。
	if is_instance_valid(_title):
		_title.add_theme_color_override("font_color", _accent)
	_sync_appearance_controls()
	_sync_graph_control()      # 图模式开关也与外观同源（`GameConfig.graph_mode`）
	# ★★ 2026-10-19 修用户报「设置页选主题后整体主题立即应用，但设置页内的按钮没变」：
	#   必须先重套按钮的 **StyleBox**，再刷字色 —— 二者管的是两层，缺一层就是
	#   "字换色了、框还是上一个主题的"。位置放在 `_refresh_settings_ink()` **之前**：
	#   套盒子会连带覆盖 `font_color` 一族（`style_theme_button()` 里做了），
	#   字色后刷才不会被打回去。
	_restyle_page_buttons()
	_refresh_settings_ink()
	_refresh_records_ink()      # 棋谱面板同理（两个面板只会存在一个，但两处都得刷）
	queue_redraw()

## 页面按钮的**表面**（按钮要"从它所在的面上浮出来"，这个面就是入参）。
## ★ 直通 `GameConfig.page_surface()` —— 与 `_draw()` 画背景用的是同一个乘积。
##   ⚠️ 别再在这里写 `_bg_color * _bg_brightness`：那正是"同一件事两处各算一遍"的老路（铁律 §18），
##   而默认明度 1.0 时两份恒等 ⇒ 分叉要等用户在设置页拉过明度才现形。
func _page_surface() -> Color:
	return GameConfig.page_surface()

## 页面按钮套**未选**态样式。**唯一入口**：各调用点不许自己拼 `GameConfig.style_theme_button(...)`，
## 否则"传哪张面"就又变成每个调用点各写一份（见上面 `_page_surface()` 的注）。
## ★★ 2026-10-19：本函数同时**登记**按钮（见 `_restyle_page_buttons()` 的注）。
##   `register = false` 只给"重套"那条路用 —— 它套的本来就是已登记的表，没必要再走一遍去重。
func _style_page_button(btn: Button, register: bool = true) -> void:
	GameConfig.style_theme_button(btn, _page_surface())
	if register:
		_register_page_btn(btn)

## 页面按钮套**选中**态样式（实心 accent）。与未选态分成两个入口，是因为"哪个是选中"
## 只能由各控件自己的真源（`_sel_netmode` / `GameConfig.window_mode`）现判 —— 本函数不猜状态，
## **调用点负责在状态变化时把两态重新套一遍**（铁律 7：一组控件两含义 ⇒ 三者同一判据派生）。
func _style_page_button_selected(btn: Button, register: bool = true) -> void:
	GameConfig.style_theme_button_selected(btn, _page_surface())
	if register:
		_register_page_btn(btn)

# ★★ 页面按钮登记表（2026-10-19）。
#   用途 = 换主题后**把按钮的盒子重新套一遍**。见 `_restyle_page_buttons()`。
#   为什么是登记表而不是"遍历控件树时按 host 颜色反推"：host 记的是**当时那张面的颜色**，
#   换主题后它已经是旧值 —— 拿它去和新 `page_surface()` 比必然不等，判不出身份（试过，不成立）。
#   而 `_style_page_button*()` 本来就是页面样式的**唯一入口** ⇒ 在入口登记，口径天然同源。
#   ⚠️ 用 `WeakRef`：切页时整棵子树会被 free，"谁还活着"由 `_restyle_page_buttons()` 顺手清理。
var _page_btns: Array[WeakRef] = []

func _register_page_btn(btn: Button) -> void:
	for w in _page_btns:
		if w.get_ref() == btn:
			return
	_page_btns.append(weakref(btn))

## 换主题后把**登记过的页面按钮**按各自当前的态重新套一遍样式，并顺手清掉已释放的。
##
## ★★ 为什么必须有这一条（2026-10-19，用户报的 bug）：
##   现象 —— 「设置页面选择主题后整个主题随即应用，但设置页内的按钮没有变」。
##   根因 —— 按钮的底色/边框**住在 StyleBox 里**，而 StyleBox 是建页时由
##   `style_theme_button()` 一次性套上的；`_apply_appearance()` 那条刷新链里
##   `_refresh_settings_ink()` 只覆盖 `font_color` 一类（字色），**没人重套 StyleBox**
##   ⇒ 按钮留着上一套主题的盒子。字色却跟着变了，于是症状更像"说不清的错位"：
##   字换色了、框没换。
## ★ 凭什么知道该套**哪一态**：读 `BTN_META_STATE`（`style_theme_button*()` 自己记的，
##   真源在 GameConfig）—— 不从 `toggle_mode` / `button_pressed` 反推：两档切换块的
##   "选中"是业务状态，与引擎的 toggle 语义并不一一对应（`_refresh_duel_tabs()` 那里有账）。
## ★ 主题色块（`_make_preset_button` 的 flat 自绘块）不在表里 ⇒ 不会被刷上按钮底，
##   它们画的是**各主题自己的颜色**，与当前主题无关（切主题时只需要 `_refresh_preset_swatches()`
##   刷描边高亮）。
func _restyle_page_buttons() -> void:
	var alive: Array[WeakRef] = []
	for w in _page_btns:
		var b: Button = w.get_ref() as Button
		if not is_instance_valid(b):
			continue
		alive.append(w)
		# 引擎可能已经把这个按钮 free 掉但对象还挂在树上？`is_instance_valid` 已挡住那一路。
		# 未套过样式的按钮（没 meta）不碰 —— 与 `_register_page_btn` 的口径保持一致。
		if not b.has_meta(GameConfig.BTN_META_HOST):
			continue
		var st: String = String(b.get_meta(GameConfig.BTN_META_STATE))
		if st == GameConfig.BTN_STATE_SELECTED:
			_style_page_button_selected(b, false)
		else:
			_style_page_button(b, false)
	_page_btns = alive

## 外观自检（--apptest）：设置页控件构建 → 应用预设 → 存盘 → 改内存 → 读回校验
func _run_appearance_self_test() -> void:
	# ★ 自检一律走**独立路径**（与 `--lastmatchtest` 同一套纪律）：写用户的 `appearance.cfg`
	#   会把"自检用的默认主题"留给用户 —— 2026-09-27 用户报「配色变回默认」，实测就是本函数
	#   结尾那次 `save_appearance()` 干的：跑一次回归（《回归脚本》必跑 apptest），主题就被冲成
	#   宣纸·浅。先记下用户文件的原始字节，结尾再核对它**一个字节都没变**。
	# ★ 路径的**唯一真源**在 GameConfig：这个独立路径同时是 `--settest` 的"改道闸"目标
	#   （`save_appearance()` 在自动化运行里会改道到这里），两边必须是**同一个文件**才不会各说各话。
	var TEST_PATH: String = GameConfig.APPEARANCE_SELFTEST_PATH
	var user_path: String = ProjectSettings.globalize_path(GameConfig.APPEARANCE_PATH)
	var user_before: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
	_set_page(PAGE_SETTINGS)
	var built: bool = is_instance_valid(_appr_preview_bg)
	var ok_preset: bool = GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
	var saved_bg: Color = GameConfig.bg_color
	var saved_board: Color = GameConfig.board_color
	GameConfig.save_appearance(TEST_PATH)
	GameConfig.bg_color = Color(0.11, 0.22, 0.33)           # 改内存
	GameConfig.board_color = Color(0.44, 0.22, 0.11)        # 改内存
	GameConfig.load_appearance(TEST_PATH)                    # 应被盘上配置覆盖回来
	var ok_persist: bool = GameConfig.bg_color.is_equal_approx(saved_bg) \
			and GameConfig.board_color.is_equal_approx(saved_board)
	var ok_ink: bool = GameConfig.ink_color().get_luminance() < 0.3   # 浅背景 → 深字
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)                          # 复原为默认主题（自检盘）
	GameConfig.bg_brightness = 1.0
	GameConfig.save_appearance(TEST_PATH)
	# 所有预设必须可应用、配色分量合法（0..1），否则主题按钮点了会脏色或异常
	var ok_all_presets: bool = true
	for pn in GameConfig.preset_names():
		if not GameConfig.apply_preset(pn):
			ok_all_presets = false
		if GameConfig.bg_color.r < 0.0 or GameConfig.bg_color.g < 0.0 or GameConfig.bg_color.b < 0.0 \
				or GameConfig.board_color.r < 0.0 or GameConfig.board_color.g < 0.0 or GameConfig.board_color.b < 0.0:
			ok_all_presets = false
	# 每个主题必须有自己的标题色：两两互不相同，且对背景有足够对比度（WCAG ≥3.0）
	# 同时校验：棋盘色中明度（黑白棋子都看得清）、棋盘 vs 背景对比度 ≥1.35
	#（浅色系背景很亮，棋盘若也跟着浅会糊成一片 —— 实测踩过 1.19~1.31 的版本）
	var ok_accents: bool = true
	var ok_contrast: bool = true          # 棋盘 vs 背景
	var ok_stones: bool = true            # ★ 棋子 vs 棋盘 + 两枚棋子互辨（2026-10-08 新增）
	var stone_min: float = 99.0           # 上面两项的**最差读数**（用来定位是哪个主题踩线）
	var stone_min_name: String = ""
	var seen_accent: Array[Color] = []
	for pn in GameConfig.preset_names():
		GameConfig.apply_preset(pn)
		var ac: Color = GameConfig.accent_color()
		if ac.a <= 0.0:
			ok_accents = false
		for prev in seen_accent:
			if prev.is_equal_approx(ac):
				ok_accents = false       # 标题色重复
		seen_accent.append(ac)
		# ① 标题 vs 背景 ≥3.0（WCAG 正文可读线）
		if GameConfig.contrast_of(GameConfig.bg_color, ac) < 3.0:
			ok_accents = false           # 标题在背景上读不清
		# ② 棋盘 vs 背景 ≥1.35（棋盘边界不能糊进背景）
		if GameConfig.contrast_of(GameConfig.bg_color, GameConfig.board_color) < 1.35:
			ok_contrast = false
		# ③ 棋子 vs 棋盘 ≥1.35 · 两枚棋子色差 ≥0.60 —— **按该主题自己的棋子色算**
		#   ★★ 这一条取代了旧判据「棋盘明度 ∈ (0.18, 0.82)」。旧判据是**为黑白子估的近似**，
		#      实测放过了「竹青·浅」：白子对棋盘只有 **1.342**（<1.35），肉眼几乎糊住，而它判绿。
		#      新判据直接量"该主题的棋子 vs 该主题的棋盘"，顺带天然支持霓虹的荧光子。
		#   ⚠️ **不许退回"只卡棋盘明度"** —— 那等于把这条已经咬到过真问题的牙齿拔掉。
		var p1: Color = GameConfig.stone_color_black
		var p2: Color = GameConfig.stone_color_white
		var c1: float = GameConfig.contrast_of(p1, GameConfig.board_color)
		var c2: float = GameConfig.contrast_of(p2, GameConfig.board_color)
		var ds: float = GameConfig.rgb_distance(p1, p2)
		if c1 < 1.35 or c2 < 1.35 or ds < 0.60:
			ok_stones = false
		var m: float = minf(minf(c1, c2), ds)
		if m < stone_min:
			stone_min = m
			stone_min_name = pn
	# 单档校验（2026-10-08 取消深浅两档）：主题表里**不许**再出现 `tier` 字段或「·浅/·深」后缀 ——
	# 残留会让设置页与手机选项层重新长出**空的分节标题**，而那是个**静默**的视觉回归。
	var ok_single: bool = true
	var groups: Array = GameConfig.preset_name_groups()
	if groups.size() != 1 or (groups[0] as Array).size() != GameConfig.preset_names().size():
		ok_single = false                # 分组数不为 1（或分组里漏了名字）
	for t in GameConfig.themes():
		if t.display_name.contains("·"):
			ok_single = false
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)                          # 遍历会改到最后一个预设，再复原
	GameConfig.bg_brightness = 1.0
	GameConfig.save_appearance(TEST_PATH)
	# 主题按钮必须是「纯色块」：不带任何文字、宽度方正、数量与预设数一致、
	# 每个方块能取到自己的四色（取不到就会画成黑块）、tooltip 保留主题名、
	# 且选中高亮唯一（当前配色匹配某预设时只有它被高亮，自定义配色时一个都不亮）。
	# headless 截不了图，所以色块"长什么样"只能这样量化。
	_refresh_preset_swatches()
	var ok_swatch: bool = (_preset_btns.size() == GameConfig.preset_names().size()) \
			and _preset_btns.size() > 0
	var sel_count: int = 0
	var names_seen: Array[String] = []
	for b in _preset_btns:
		if not is_instance_valid(b):
			ok_swatch = false
			continue
		if b.text != "":
			ok_swatch = false                      # 必须无文字
		if b.custom_minimum_size.x < 40.0 or b.custom_minimum_size.y < 30.0:
			ok_swatch = false                      # 太小会看不清色块
		if b.tooltip_text == "":
			ok_swatch = false                      # 名字没了文字就得靠 tooltip，不能一起丢
		if names_seen.has(b.tooltip_text):
			ok_swatch = false                      # 名字不能重复
		names_seen.append(b.tooltip_text)
		if GameConfig.preset_colors(b.tooltip_text).is_empty():
			ok_swatch = false                      # 取不到配色 → 会画成黑块
		if b.tooltip_text == _preset_sel:
			sel_count += 1
	# 复原成默认后应恰好高亮 1 个（默认主题自身）
	if sel_count != 1:
		ok_swatch = false
	# 自定义配色（改掉背景色）后应一个都不高亮
	GameConfig.bg_color = GameConfig.bg_color.darkened(0.2)
	_refresh_preset_swatches()
	if _preset_sel != "":
		ok_swatch = false
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
	GameConfig.bg_brightness = 1.0
	GameConfig.save_appearance(TEST_PATH)
	# **自检不许碰用户的 appearance.cfg**：用户文件必须**逐字节**未变。
	#    配一条阳性对照：自检**确实写了盘**（自检盘非空）—— 否则"没污染"可能只是"压根没写"，
	#    那样这条判据就是恒真的（没有牙齿）。
	var test_written: bool = FileAccess.get_file_as_bytes(
			ProjectSettings.globalize_path(TEST_PATH)).size() > 0
	var user_after: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
	var ok_nopollute: bool = (user_before == user_after) and test_written

	# ── 主题色按钮调色板 + 上一步提示圆点（2026-10-08 第三轮）────────────────────
	# 这两条是**新能力**的验收（`GameConfig.button_palette()` / `last_move_dot_color()`），
	# 逐主题全量跑，不是拿默认主题抽查一个。
	# ★★ 各配一条**阴性对照**，而且对照必须**自己也被判不达标**才算有牙齿：
	#   · 按钮：旧实现的固定深灰（`DIALOG_BTN_BG`）铺在面板底上，本工程从来没量过
	#     "按钮 vs 它所在的面板底" —— 实测 1.254 < 1.35，即**旧按钮本来就踩线**；
	#   · 圆点：旧实现的硬编码反色在霓虹/赛博上必须**被判不达标**（那正是用户看到的病）。
	#   若哪天有人把阈值调到"旧实现也能过"，这两条对照会当场红 —— 阈值就不许再偷改。
	var ok_btn_pal: bool = true
	var ok_dot: bool = true
	# ★★ 四项**必须逐项单列**：它们的**阈值不同**（面 1.35 / 字 4.5），
	#   混成一个"最小值"会把"面差 1.42（达标）"印在"字差 4.4（不达标）"的主题前面 ——
	#   第一版正是这么印成 `最差 1.421（宣纸）`，而真正的失败项根本不是它（rules §14）。
	#   口径：每项各自维护「最差读数 + 它的主人」，末尾四项并排打印。
	var btn_thr: Array = [
		GameConfig.BTN_SURFACE_MIN_CONTRAST, GameConfig.BTN_TEXT_MIN_CONTRAST,
		GameConfig.BTN_SURFACE_MIN_CONTRAST, GameConfig.BTN_TEXT_MIN_CONTRAST,
	]
	var btn_worst: Array = [999.0, 999.0, 999.0, 999.0]
	var btn_who: Array = ["", "", "", ""]
	var dot_min: float = 999.0
	var dot_min_name: String = ""
	for pn3 in GameConfig.preset_names():
		GameConfig.apply_preset(pn3)
		# ★ 判据的"表面"必须与消费方**同一个真源**（`page_surface()` = 背景色 × 明度档）：
		#   旧版这里写的是裸 `bg_color`，于是"按钮被接到明度档**之前**的底色上"这类错
		#   （`bg_brightness≠1` 的机器上按钮与背景同色）在判据里恒不可见。
		var host: Color = GameConfig.page_surface()
		var pal: Dictionary = GameConfig.button_palette(host)
		# 口径与消费方一致：面 = 按钮 vs 它所在的底；字 = 字 vs 它自己所在的那个面
		var vals: Array = [
			GameConfig.contrast_of(pal["fill"], host),
			GameConfig.contrast_of(pal["ink"], pal["fill"]),
			GameConfig.contrast_of(pal["fill_sel"], host),
			GameConfig.contrast_of(pal["ink_sel"], pal["fill_sel"]),
		]
		for bi in range(4):
			if vals[bi] < btn_worst[bi]:
				btn_worst[bi] = vals[bi]
				btn_who[bi] = pn3
			if vals[bi] < btn_thr[bi]:
				ok_btn_pal = false             # 面浮不出来 或 字读不清，逐项判
		# 提示圆点：两枚棋子**各自的绘制色**各算一次（主题可能换过棋子色）。
		# ⚠️ 这里**不能**写 `Stone.BLACK` —— `enum Stone` 定义在 `game.gd` 内部，
		#   菜单侧看不见它（那是场景脚本的成员枚举，不是全局 `class_name`）⇒ 直接用颜色配对。
		var stone_pairs: Array = [
			[GameConfig.stone_color_black, "黑"],
			[GameConfig.stone_color_white, "白"],
		]
		for sp in stone_pairs:
			var sc: Color = sp[0]
			var cd: float = GameConfig.contrast_of(GameConfig.last_move_dot_color(sc), sc)
			if cd < dot_min:
				dot_min = cd
				dot_min_name = "%s·%s" % [pn3, sp[1]]
			if cd < GameConfig.DOT_MIN_CONTRAST:
				ok_dot = false
	# ── 浮层面板（ESC 暂停 / ESC 退出确认 / 遮罩弹窗）主题化后的整条推导链 ────────
	# 2026-10-15 新增。面板底色从"固定深蓝灰"改成"由主题棋盘色推离棋盘底"（见 game_config.gd
	# 里 `overlay_surface()` 的推导链）。**底色一换，它上面的每一项都要重新量**：
	# 这正是 2026-09-22 那次事故的病根（底色换了、字色没跟，正文对比度掉到 1.06）。
	# ★ 五项**逐项单列**（阈值不同：2.5 / 4.5 / 4.5 / 4.5 / 1.35），理由同上面按钮那四项。
	var ok_panel: bool = true
	var pan_thr: Array = [
		GameConfig.PANEL_SCRIM_MIN, GameConfig.DIALOG_TEXT_MIN_CONTRAST,
		GameConfig.DIALOG_TEXT_MIN_CONTRAST, GameConfig.DIALOG_TEXT_MIN_CONTRAST,
		GameConfig.BTN_SURFACE_MIN_CONTRAST,
	]
	var pan_worst: Array = [999.0, 999.0, 999.0, 999.0, 999.0]
	var pan_who: Array = ["", "", "", "", ""]
	# 面板明度上限：口径是"**面板恒落在深色区间**"（`PANEL_LUM_MAX`）。
	# ★ 为什么单列成一条判据而不是靠"文字达标"间接保证：第一版就是"够分离就原样用棋盘色"，
	#   藏青那套的棋盘色是浅蓝白 ⇒ 吐出一块 L=0.509 的**浅色面板**，深色主题弹出白面板。
	#   那一次是"文字对比度"这条判据先红的，红点却指向文字 —— 根因在**面板明度**上。
	#   把根因单列，红了就能一眼看出是"面板不该是浅色"，而不是去查拟合函数。
	var ok_panel_dark: bool = true
	var pan_lum_max: float = 0.0
	var pan_lum_who: String = ""
	for pn5 in GameConfig.preset_names():
		GameConfig.apply_preset(pn5)
		var surf: Color = GameConfig.overlay_surface()
		var pal5: Dictionary = GameConfig.button_palette(surf)
		var vals5: Array = [
			GameConfig.contrast_of(surf, GameConfig.panel_backdrop()),
			GameConfig.contrast_of(GameConfig.dialog_title_color(), surf),
			GameConfig.contrast_of(GameConfig.dialog_text_color(), surf),
			GameConfig.contrast_of(GameConfig.dialog_button_font_color(), pal5["fill"]),
			GameConfig.contrast_of(pal5["fill"], surf),
		]
		for pi in range(5):
			if vals5[pi] < pan_worst[pi]:
				pan_worst[pi] = vals5[pi]
				pan_who[pi] = pn5
			if vals5[pi] < pan_thr[pi]:
				ok_panel = false
		var lum5: float = surf.get_luminance()
		if lum5 > pan_lum_max:
			pan_lum_max = lum5
			pan_lum_who = pn5
		if lum5 > GameConfig.PANEL_LUM_MAX + 0.01:
			ok_panel_dark = false
	# ★ 阴性对照：**不推导**、直接拿页面底色当面板底（最容易写出来的那种实现）——
	#   它必须被判不达标。为什么它一定不达标是**可证明**的：面板后面恒压着一层 45% 黑遮罩，
	#   而"页面底色"正是**遮罩前**的那张脸 ⇒ 拿它当面板底 = 面板与背景只差那 45% 的变暗，
	#   14 个主题上都到不了 2.5。若哪天这条对照"成立"了，说明判据在自证。
	var neg_panel_passes: bool = true
	for pn6 in GameConfig.preset_names():
		GameConfig.apply_preset(pn6)
		var naive: Color = GameConfig.bg_color * GameConfig.bg_brightness
		if GameConfig.contrast_of(naive, GameConfig.panel_backdrop()) < GameConfig.PANEL_SCRIM_MIN:
			neg_panel_passes = false
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
	GameConfig.bg_brightness = 1.0
	# 阴性对照① 旧按钮配色（固定深灰）vs 它真正所在的弹窗面板底
	var neg_btn_passes: bool = GameConfig.contrast_of(
			GameConfig.DIALOG_BTN_BG, GameConfig.DIALOG_BG) >= GameConfig.BTN_SURFACE_MIN_CONTRAST
	# 阴性对照② 旧圆点配色（硬编码反色）是否"每套主题都达标"
	var neg_dot_passes: bool = true
	for pn4 in GameConfig.preset_names():
		GameConfig.apply_preset(pn4)
		if GameConfig.contrast_of(Color(1, 1, 1), GameConfig.stone_color_black) \
				< GameConfig.DOT_MIN_CONTRAST:
			neg_dot_passes = false
		if GameConfig.contrast_of(Color(0, 0, 0), GameConfig.stone_color_white) \
				< GameConfig.DOT_MIN_CONTRAST:
			neg_dot_passes = false
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
	GameConfig.bg_brightness = 1.0
	var ok_neg_theme: bool = (not neg_btn_passes) and (not neg_dot_passes) and (not neg_panel_passes)
	GameConfig.save_appearance(TEST_PATH)

	# ── 换主题后页面按钮的**盒子**必须跟着换（2026-10-19，用户报的 bug）───────────
	# 现象：设置页选主题 ⇒ 整个界面立刻换色，**但设置页内的按钮没变**（字色变了、框没换）。
	# 根因：按钮的底色/边框住在 StyleBox 里，建页时套一次；`_apply_appearance()` 只刷字色
	#       ⇒ 没人重套盒子。修法 = 登记表 + `_restyle_page_buttons()`。
	# ★ 判据必须跑在**会出问题的那一档**：这里真的切一个**不同的**主题，量同一颗按钮的
	#   底色**前后不同**，且等于按新面算出来的期望值（只量"变了"不够 —— 变成错的也满足）。
	# ★ 按钮从**登记表**里挑（`_page_btns` 就是"页面按钮"这个集合的真源）。挑不到 ⇒ 红：
	#   那说明登记这条路断了，等于这条判据压根没跑（"没跑"不许长成"通过"）。
	var ok_restyle: bool = false
	var restyle_msg: String = ""
	var probe_btn: Button = null
	for w in _page_btns:
		var cb: Button = w.get_ref() as Button
		if is_instance_valid(cb) and not cb.flat and cb.is_inside_tree():
			probe_btn = cb
			break
	if probe_btn == null:
		restyle_msg = "登记表里没有活着的页面按钮 ⇒ 这条判据没跑（按不合格处理）"
	else:
		GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
		GameConfig.bg_brightness = 1.0
		_apply_appearance()
		var fill_a: Color = GameConfig.probe_button_theme(probe_btn)["fill"]
		var other: String = ""
		for pn_r in GameConfig.preset_names():
			if pn_r != GameConfig.DEFAULT_PRESET:
				other = pn_r
				break
		var ok_apply_r: bool = other != "" and GameConfig.apply_preset(other)
		_apply_appearance()
		var pr_r: Dictionary = GameConfig.probe_button_theme(probe_btn)
		var fill_b: Color = pr_r["fill"]
		ok_restyle = ok_apply_r and not fill_b.is_equal_approx(fill_a) \
				and fill_b.is_equal_approx(pr_r["fill_expect"])
		restyle_msg = "「%s」→「%s」按钮「%s」底色 %s → %s（期望 %s）" % [
			GameConfig.DEFAULT_PRESET, other,
			probe_btn.text if probe_btn.text != "" else String(probe_btn.name),
			str(fill_a), str(fill_b), str(pr_r["fill_expect"])]
	# 复原成默认主题（后面还会写一次自检盘，口径保持一致）
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
	GameConfig.bg_brightness = 1.0
	_apply_appearance()
	GameConfig.save_appearance(TEST_PATH)

	var ok_all: bool = built and ok_preset and ok_persist and ok_ink and ok_all_presets \
			and ok_accents and ok_contrast and ok_stones and ok_single and ok_swatch and ok_nopollute \
			and ok_btn_pal and ok_dot and ok_neg_theme and ok_panel and ok_panel_dark and ok_restyle
	# 清理：user:// 下不留垃圾；内存配色读回用户的（本进程随后退出，只为口径干净）
	DirAccess.open("user://").remove(GameConfig.APPEARANCE_SELFTEST_PATH.get_file())
	GameConfig.load_appearance()
	print("[apptest] 预览=%s 预设=%s 持久化=%s 文字自适应=%s 全部主题可用=%s 标题色独立=%s 棋盘对背景=%s 单档=%s 色块按钮=%s 不碰用户配置=%s（自检盘已写=%s） → %s" % [
		built, ok_preset, ok_persist, ok_ink, ok_all_presets, ok_accents, ok_contrast, ok_single, ok_swatch,
		str(ok_nopollute), str(test_written),
		"通过 ✓" if ok_all else "失败 ✗"])
	# 换主题后按钮盒子（2026-10-19 修的那条 bug 的唯一复发防线）：单列一行，印出前后读数。
	print("[apptest] 换主题后页面按钮盒子跟着换：%s｜%s" % [
		"通过 ✓" if ok_restyle else "失败 ✗", restyle_msg])
	# 棋子可辨单列一行：它是**最容易在新增主题时踩线**的一项（霓虹类要自定义棋子色），
	# 且出事时最想知道的是"哪个主题、哪一项、差多少" —— 所以把最差读数与它的主人印出来。
	print("[apptest] 棋子可辨（棋子vs棋盘≥1.35 且 两子色差≥0.60）：%s｜最差 %.3f（%s）" % [
		"通过 ✓" if ok_stones else "失败 ✗", stone_min,
		stone_min_name if stone_min_name != "" else "—"])
	# 新增两项也各单列一行（同"棋子可辨"的理由：新增主题时最容易踩线，出事时要能一眼看出是哪套）
	print("[apptest] 主题色按钮逐项（阈值：面≥1.35 字≥4.5 选面≥1.35 选字≥4.5）：%s｜面 %.3f（%s）｜字 %.3f（%s）｜选面 %.3f（%s）｜选字 %.3f（%s）｜阴性对照=%s" % [
		"通过 ✓" if ok_btn_pal else "失败 ✗",
		btn_worst[0], btn_who[0] if btn_who[0] != "" else "—",
		btn_worst[1], btn_who[1] if btn_who[1] != "" else "—",
		btn_worst[2], btn_who[2] if btn_who[2] != "" else "—",
		btn_worst[3], btn_who[3] if btn_who[3] != "" else "—",
		"旧固定深灰按钮必须被判不达标 → %s" % ("成立 ✓" if not neg_btn_passes else "★不成立（判据没牙齿）")])
	print("[apptest] 上一步提示圆点（圆点vs所在棋子≥3.0）：%s｜最差 %.3f（%s）｜阴性对照=%s" % [
		"通过 ✓" if ok_dot else "失败 ✗", dot_min,
		dot_min_name if dot_min_name != "" else "—",
		"旧硬编码反色必须被判不达标 → %s" % ("成立 ✓" if not neg_dot_passes else "★不成立（判据没牙齿）")])
	# 浮层面板（2026-10-15）：面板底 = 主题棋盘色推离"遮罩后的棋盘底"。
	# ★ 五项逐项印最差读数 + 它的主人（新增主题时最容易踩线的就是这里）。
	print("[apptest] 浮层面板主题化（阈值：面板vs背景≥2.0 标题≥4.5 正文≥4.5 按钮字≥4.5 按钮面vs面板≥1.35）：%s｜面板 %.3f（%s）｜标题 %.3f（%s）｜正文 %.3f（%s）｜按钮字 %.3f（%s）｜按钮面 %.3f（%s）" % [
		"通过 ✓" if ok_panel else "失败 ✗",
		pan_worst[0], pan_who[0] if pan_who[0] != "" else "—",
		pan_worst[1], pan_who[1] if pan_who[1] != "" else "—",
		pan_worst[2], pan_who[2] if pan_who[2] != "" else "—",
		pan_worst[3], pan_who[3] if pan_who[3] != "" else "—",
		pan_worst[4], pan_who[4] if pan_who[4] != "" else "—"])
	print("[apptest] 浮层面板明度（须 ≤%.2f，即面板恒落在深色区间）：%s｜最亮 %.3f（%s）｜阴性对照 直接拿页面底色当面板底必须被判不达标 → %s" % [
		GameConfig.PANEL_LUM_MAX,
		"通过 ✓" if ok_panel_dark else "失败 ✗", pan_lum_max,
		pan_lum_who if pan_lum_who != "" else "—",
		"成立 ✓" if not neg_panel_passes else "★不成立（判据没牙齿）"])
	get_tree().quit()

static var _apprt_stage: int = 0
static var _apprt_keep: Dictionary = {}

## 自检（--apprt）：外观「对局往返」—— 选中的主题**过了对局一趟**后不能被回写成默认。
##
## ① 切到一个**非默认**主题并落盘 → 进对局（game.gd 的 `_apply_appearance()` 会 `load_appearance()`）；
## ② 回到菜单：预设名 / GameConfig 配色 / 菜单自己的绘制变量，三项必须都还是它。
##
## ★ 为什么必须真的进一次对局：只在菜单里"存 → 读"验不到"对局那一读"（`--apptest` 已经在验前者），
##   而用户报的正是"过了对局一趟就变默认"。
## ★ 两个阶段靠 **static 变量**接力：场景切换不会重置脚本的静态成员（Autoload 之外的进程内状态），
##   比"往 user:// 里塞个阶段文件"干净，也不会污染用户目录。
## ★ 收尾**必须还原用户原来的主题并落盘**。
## ★★ 它**故意**不走独立路径（测的就是"真配置过一趟对局"）→ **不要把它加进 `regress.sh`**：
##    回归是每次改码都跑的，而这条一旦中途崩掉，用户的主题就会留在测试值上。
##    只作为**手工排查工具**留着（用户报「配色变回默认」时先跑它，一眼分辨是"没落盘"还是"被谁冲了"）。
func _appearance_round_trip_test() -> void:
	# ★ 从真源挑"非默认主题"，**不许硬编码主题名**：本行原来是 `"黛蓝·深"` —— 主题表改单档
	#   （2026-10-08）后该名已不存在 ⇒ `apply_preset()` 返回 false、`appearance_preset` 不会变，
	#   于是 ② 的 `c_preset` 假红，看起来像"配色被对局冲掉了"（其实根本没切过去）。
	#   同一处毛病在 `menu_mobile.gd` 判据⑩ 也犯过一次 ⇒ 凡"要用某个主题名"都从 `preset_names()` 取。
	var want: String = GameConfig.DEFAULT_PRESET
	for nm in GameConfig.preset_names():
		if String(nm) != GameConfig.DEFAULT_PRESET:
			want = String(nm)
			break
	var want_bg: Color = GameConfig.preset_colors(want).get("bg", Color.BLACK)
	if _apprt_stage == 0:
		_apprt_keep = {
			"bg": GameConfig.bg_color, "board": GameConfig.board_color,
			"line": GameConfig.line_color, "accent": GameConfig.accent_override,
			"preset": GameConfig.appearance_preset, "bright": GameConfig.bg_brightness,
		}
		var ok_apply: bool = GameConfig.apply_preset(want)
		GameConfig.save_appearance()
		_apprt_stage = 1
		print("[apprt] ① 切到非默认主题「%s」（apply=%s）并落盘 → 进对局" % [want, str(ok_apply)])
		Transition.change_scene("res://game.tscn")
		return
	var c_preset: bool = GameConfig.appearance_preset == want
	var c_cfg: bool = GameConfig.bg_color.is_equal_approx(want_bg)
	var c_draw: bool = _bg_color.is_equal_approx(want_bg)
	var ok: bool = c_preset and c_cfg and c_draw
	print("[apprt] ② 对局后回菜单：预设%s=%s 配置色%s=%s 菜单绘制色%s=%s → %s" % [
		str(c_preset), GameConfig.appearance_preset,
		str(c_cfg), str(GameConfig.bg_color),
		str(c_draw), str(_bg_color),
		"通过 ✓" if ok else "失败 ✗"])
	# 还原用户原主题（自检到此为止，不能把用户配置留在测试值上）
	GameConfig.bg_color = _apprt_keep["bg"]
	GameConfig.board_color = _apprt_keep["board"]
	GameConfig.line_color = _apprt_keep["line"]
	GameConfig.accent_override = _apprt_keep["accent"]
	GameConfig.appearance_preset = _apprt_keep["preset"]
	GameConfig.bg_brightness = float(_apprt_keep["bright"])
	GameConfig.save_appearance()
	print("[apprt] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 自检（--settest）：设置页分栏布局量化。
## 为什么需要：设置页是原生控件，headless 截不了图（dummy 渲染器不发 frame_post_draw），
## 而「横向拉太长 / 预览太小」这类问题只有量化尺寸才说得清。等两帧让容器完成布局后读实际 size。
func _settings_layout_test() -> void:
	# ★★ 「自检不许写用户的 user:// 配置」这条纪律的**判据**（2026-09-29 新增）。
	#    闸在 `GameConfig.save_appearance()` 里（自动化运行 → 改道写自检盘），这里量它有没有生效。
	#    两条缺一不可：
	#      ① 自检盘上**必须留下**那次写 —— 否则"用户文件没变"可能只是"压根没写"，判据变成恒真；
	#      ② 用户文件**逐字节未变** —— 且要在**伤害最大的那一刻**量（点完无边框全屏、还没还原时），
	#         不能只量收尾：收尾那次是"写回原值"，它会把内容盖回去，从而**掩盖掉中途的破坏**。
	var user_path: String = ProjectSettings.globalize_path(GameConfig.APPEARANCE_PATH)
	var user_before: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
	# 清掉上一轮留下的自检盘，防"旧文件冒充新写"（与本工程"跑前 rm 旧图"同一纪律）
	DirAccess.open("user://").remove("appearance_selftest.cfg")
	_set_page(PAGE_SETTINGS)
	await get_tree().process_frame
	await get_tree().process_frame
	var ok := true
	# ★★ 「**只是打开设置页**」不许产生任何写入（2026-09-30 新增）。
	#    真凶：构建控件时 `_sync_cursor_controls()` 若用**普通赋值**给 CheckButton / HSlider
	#    设初值，Godot 会**发信号**（`toggled` / `value_changed`）⇒ 构建那一下等于
	#    "替玩家点了一次"：弹提示 + 白写一次盘。正确写法是 `set_pressed_no_signal()` /
	#    `set_value_no_signal()`（见该函数注释）。
	#    ⚠️ 这个副作用**只在值真的变化时才发生**（true→true 不发信号）⇒ 天然难发现：
	#    实测第一次就是靠"截图顶部多了一条提示气泡"才看见的。
	#    判据挂在自检盘上（自动化运行的写都会改道到那里）—— 上面刚删过，此刻它**不该存在**。
	var opened_wrote: bool = FileAccess.file_exists(GameConfig.APPEARANCE_SELFTEST_PATH)
	if opened_wrote:
		ok = false
	print("[settest]   打开设置页不写盘 %s（自检盘存在=%s）" % [
		"✓" if not opened_wrote else "✗", str(opened_wrote)])
	var vw := get_viewport_rect().size.x
	var pv := _appr_preview_bg                     # 左栏预览色块
	var left_w: float = pv.size.x                  # 左栏宽（ColorRect 水平 FILL 满左栏）
	var pv_h: float = pv.size.y
	var a := minf((left_w - 12.0) / 3.804, (pv_h - 12.0) / 3.618)   # 与 PreviewBoard 同一公式
	var star_h := 3.618 * a
	var cen: Control = _find_first(_settings_root, "CenterContainer")
	var col_w: float = cen.get_child(0).size.x if cen != null and cen.get_child_count() > 0 else -1.0
	var sl: Control = _find_first(_settings_root, "HSlider")
	var sl_w: float = sl.size.x if sl != null else -1.0
	var total: float = left_w + 24.0 + col_w + 64.0   # 两栏 + 间距 + 左右外边距
	# 主题色块所在容器的占宽 / 换行行数 / 有没有方块探出内容列。
	# ★★ 2026-10-08 主题改单档，这一格换了容器（`HBoxContainer` → `HFlowContainer`，12 个方块自动换行）：
	#   · 旧注释写「7 个方块 + 行首『浅/深』标签仍在内容列内」—— 那两层现在都不存在了，别照着它改代码；
	#   · 更要紧的是**这条判据的牙齿变了**：`HBoxContainer` 会被内容横向撑开，所以「容器宽 ≤ 列宽」
	#     当年真能抓到溢出；而 `HFlowContainer` 的宽度**由列宽决定**（只会往下换行）⇒ 只看容器宽
	#     就退化成**恒真式**（实测 `色块行=520` 恰好 == `内容列=520`，一眼即是恒真）。
	#     改量**每个方块自己的全局右边界 vs 内容列右边界**（有牙齿：方块最小宽超了列就探出来），
	#     并把**行数**打出来 —— 12 个方块在窄视口下换行变多会让面板变高，那由「不压底栏」兜底。
	var sw_row_w: float = -1.0
	var sw_rows: int = 0
	var sw_out: int = 0
	var col_right: float = -1.0
	if cen != null and cen.get_child_count() > 0 and cen.get_child(0) is Control:
		col_right = (cen.get_child(0) as Control).get_global_rect().end.x
	if not _preset_btns.is_empty():
		var first: Button = _preset_btns[0]
		var row_node: Node = first.get_parent()
		if row_node is Control:
			sw_row_w = (row_node as Control).size.x
		var ys: Array[float] = []
		for b in _preset_btns:
			if not is_instance_valid(b):
				continue
			var yy: float = b.get_global_rect().position.y
			var is_new: bool = true
			for e in ys:
				if absf(e - yy) <= 1.0:
					is_new = false
					break
			if is_new:
				ys.append(yy)
			if col_right > 0.0 and b.get_global_rect().end.x > col_right + 1.0:
				sw_out += 1
		sw_rows = ys.size()
	var checks := {
		"预览够大": star_h >= 200.0,
		"预览近似正方形": absf(pv_h - left_w) <= 2.0,
		"不压标题": _settings_root.position.y >= TOP_MARGIN,
		# ★★ 2026-10-04 v4（设置从"独立页"变成主菜单的一个**面板**）：这棵原生控件树必须
		#   **整棵落在底栏行带之上**。为什么这条必须有牙齿：底栏四块是换面板的**唯一入口**，
		#   被控件树盖住就是"出不去"—— 而 `--menutest` 那几条（①/⑤e/⑥b/⑥d）**全都只看砖
		#   自己**（标签对不对、自己在不在行带里、四个面板一不一致），控件树盖上去它们一律照绿。
		#   ⚠️ 这里读的是**派生结果**（控件树的实际下沿）与**真源**（`_footer_band()`）的关系，
		#   不是"把 `offset_bottom` 的算式抄一遍"—— 抄一遍就是把判据写成恒真式。
		"不压底栏": _settings_root.get_rect().end.y <= _footer_band().position.y + 0.5,
		"左栏不过宽": left_w <= 460.5,
		"内容列不过宽": col_w <= 720.5,
		"滑条未被拉长": sl_w <= 321.0,
		"不横向溢出": total <= vw + 1.0,
		"色块行不溢出": sw_row_w > 0.0 and sw_out == 0 \
				and (col_w < 0.0 or sw_row_w <= col_w + 1.0),
	}
	print("[settest] 控件树 y=%.0f..%.0f · 底栏带上沿=%.0f · 视口高=%.0f" % [
		_settings_root.get_rect().position.y, _settings_root.get_rect().end.y,
		_footer_band().position.y, size.y])
	print("[settest] 视口宽=%.0f 左栏预览=%.0f×%.0f 星高≈%.0f 内容列=%.0f 滑条=%.0f 总占宽=%.0f 色块行=%.0f 换行=%d 行 探出=%d 个" % [
		vw, left_w, pv_h, star_h, col_w, sl_w, total, sw_row_w, sw_rows, sw_out])
	if not _preset_btns.is_empty():
		var b0: Button = _preset_btns[0]
		print("[settest]   色块实测 %.0f×%.0f（min %.0f×%.0f）" % [
			b0.size.x, b0.size.y, b0.custom_minimum_size.x, b0.custom_minimum_size.y])
	for k in checks:
		var good: bool = checks[k]
		if not good:
			ok = false
		print("[settest]   %s %s" % [k, "✓" if good else "✗"])
	# 预览试摆：点第一格落黑 → 点第二格落白 → 再点第一格提回（黑白交替）
	var pb := _appr_preview_board as PreviewBoard
	if pb == null:
		ok = false
		print("[settest]   预览可落子 ✗ 控件缺失")
	else:
		pb._rebuild_polys()
		_click_preview_cell(pb, 0)
		var m0: int = pb._marks[0]
		_click_preview_cell(pb, 1)
		var m1: int = pb._marks[1]
		_click_preview_cell(pb, 0)
		var m0b: int = pb._marks[0]
		var ok_play: bool = (m0 == 1) and (m1 == 2) and (m0b == 0)
		if not ok_play:
			ok = false
		print("[settest]   预览可落子 %s（首格=%d 次格=%d 再点提回=%d）" % [
			"✓" if ok_play else "✗", m0, m1, m0b])
		# 吃子：五格环 0-1-2-3-4-0。黑0 → 白1 → 黑2 ⇒ 白1 两邻皆黑、无气被提
		pb._marks.fill(0)
		pb._fade.clear()
		pb._turn = 1
		_click_preview_cell(pb, 0)
		_click_preview_cell(pb, 1)
		_click_preview_cell(pb, 2)
		var ok_eat: bool = (pb._marks[0] == 1) and (pb._marks[2] == 1) and (pb._marks[1] == 0) \
				and pb._fade.has(1) and (not bool(pb._fade[1]["in"]))   # 被提格走的是渐隐动画
		if not ok_eat:
			ok = false
		print("[settest]   预览可吃子 %s（白1=%d 提子动画=%s）" % [
			"✓" if ok_eat else "✗", pb._marks[1], pb._fade.has(1)])
		# ★★ 提子动画必须**排在落子动画之后**（2026-09-29 用户口令）。
		#   两条一起判 —— ① 起手 delay ≥ 落子动画时长 ② **真的推进半个落子时长之后**，
		#   被提那一格的剩余时长必须**一点没少**（= 它一动没动）。
		#   ⚠️ 只有 ① 是不够的：`_process` 若改成 delay 与 t **并排**递减，起手那一帧
		#      两种写法完全一样，只有推进之后才分得出来。
		var seq_delay: float = float(pb._fade[1].get("delay", 0.0))
		pb._process(PreviewBoard.ANIM_TIME * 0.5)
		var seq_hold: bool = pb._fade.has(1) \
				and is_equal_approx(float(pb._fade[1]["t"]), PreviewBoard.ANIM_TIME)
		var ok_seq: bool = seq_delay >= PreviewBoard.ANIM_TIME and seq_hold
		if not ok_seq:
			ok = false
		print("[settest]   提子排在落子之后 %s（delay %.2fs ≥ %.2fs；落子半途时提子剩余仍未变 %s）" % [
			"✓" if ok_seq else "✗", seq_delay, PreviewBoard.ANIM_TIME, str(seq_hold)])
		# 自杀手：白1/白3 各有外气（0、4 空），黑下 2 → 自己无气且没吃子 → 这手不成立
		pb._marks.fill(0)
		pb._fade.clear()
		pb._marks[1] = 2
		pb._marks[3] = 2
		pb._turn = 1
		pb._place(2)
		var ok_sui: bool = (pb._marks[2] == 0) and (pb._turn == 1)
		if not ok_sui:
			ok = false
		print("[settest]   自杀手不成立 %s（第2格=%d 轮次仍黑=%s）" % [
			"✓" if ok_sui else "✗", pb._marks[2], pb._turn == 1])
		# 动画推进：喂 0.5s（> ANIM_TIME 0.3）后所有落子/提子动画都应结束
		# （不推进的话颜色会卡在渐显起点，落子看起来没反应）
		pb._process(0.5)
		var ok_anim: bool = pb._fade.is_empty()
		if not ok_anim:
			ok = false
		print("[settest]   动画会推进 %s（残留 %d 个）" % ["✓" if ok_anim else "✗", pb._fade.size()])
		# 提子**向上平移淡出**（2026-09-29 用户口令；菜单盘与对局盘 `_capture_fade_state()` 同源）。
		#  ★ 四件事一起判，每一条都对应一种"看起来改了、其实没平移"的死法：
		#   ① 起手：位移 = 0 且 alpha = 1（还在原格、不透明 —— 否则棋子会"跳一下"）
		#   ② 终点：位移 == 落子的**起点**位移（两个动画共用**同一个**高度旋钮 `_drop_h()`，
		#      口径上"提子的终点就是落子的起点"，不许多开一个旋钮）
		#   ③ 半途：**已经向上走完 ≥40% 行程** —— 防"只淡出不平移"，也防把位移全挤进末尾
		#      （末尾 alpha ≈ 0.2，那里再动等于没动）
		#   ④ 终点 alpha = 0（散尽、不留残影）
		var fz0: Dictionary = pb._fade_state(0.0)
		var fz1: Dictionary = pb._fade_state(1.0)
		var fzm: Dictionary = pb._fade_state(0.5)
		var rise_tot: float = -Vector2(fz1["off"]).y
		var ok_capfade: bool = Vector2(fz0["off"]) == Vector2.ZERO \
				and is_equal_approx(float(fz0["alpha"]), 1.0) \
				and is_equal_approx(float(fz1["alpha"]), 0.0) \
				and rise_tot > 0.0 \
				and Vector2(fzm["off"]).x == 0.0 and Vector2(fzm["off"]).y < 0.0 \
				and -Vector2(fzm["off"]).y >= rise_tot * 0.4 \
				and Vector2(fz1["off"]) == Vector2(pb._drop_state(0.0)["off"])
		if not ok_capfade:
			ok = false
		print("[settest]   提子向上平移淡出 %s（行程 %.1f，半途 %.1f 需 ≥%.1f）" % [
			"✓" if ok_capfade else "✗", rise_tot, -Vector2(fzm["off"]).y, rise_tot * 0.4])
		# ★★ 提子**波前顺序 + 总时长封顶**（2026-09-29 用户口令；口径与对局盘逐字同源）。
		#   五格环 0-1-2-3-4-0 上造一个**两层**局面：黑3 已占，白1、白2 连成一块（白2 的另一个
		#   邻居 3 被黑占掉），白块的最后一口气是 0 ⇒ 黑下 0 提掉 {1,2}。
		#   **层号可手算**：0 与 1 相邻 ⇒ 1 是第 0 层；0 与 2 不相邻（2 的邻居是 1、3）⇒ 2 是第 1 层。
		#   期望值就写死成 {1:0, 2:1}，并先把"0 与 1 相邻 / 0 与 2 不相邻"断言出来，期望值才不是魔数。
		pb._marks.fill(0)
		pb._fade.clear()
		pb._marks[3] = 1
		pb._marks[1] = 2
		pb._marks[2] = 2
		pb._turn = 1
		pb._place(0)
		var adj_ok: bool = pb._neighbors(1).has(0) and (not pb._neighbors(2).has(0))
		var wv_bad := 0
		if pb._fade.has(1) and pb._fade.has(2):
			if int(pb._fade[1].get("wave", -1)) != 0:
				wv_bad += 1
			if int(pb._fade[2].get("wave", -1)) != 1:
				wv_bad += 1
		else:
			wv_bad = 2
		# delay 必须**随层号真的递增**（顺序落到时间上，而不只是记了个数）
		var ord_ok: bool = pb._fade.has(1) and pb._fade.has(2) \
				and float(pb._fade[1]["delay"]) < float(pb._fade[2]["delay"]) \
				and is_equal_approx(float(pb._fade[1]["delay"]), PreviewBoard.ANIM_TIME)
		# 封顶：最深层结束 == ANIM_TIME(等落子) + CAPTURE_TOTAL_TIME，且**与层数无关**；地板也要兜住
		var cap: float = PreviewBoard.ANIM_TIME + pb._capture_total_time()
		var cap_ok: bool = is_equal_approx(pb._capture_end_time(1, 1), cap)
		var len_free := true
		for wm in [1, 2, 5]:
			if not is_equal_approx(pb._capture_end_time(wm, wm), cap):
				len_free = false
		var mono := true
		for wm in [3]:
			for w in wm:
				if not (pb._capture_wave_start(w, wm) < pb._capture_wave_start(w + 1, wm)):
					mono = false
		# 两端锚点：第 0 层起手偏移**恒为 0**（贴着落点的那层立刻开始，只等落子动画）；
		# 最深层吃满剩余跨度（= 总时长 - 单颗时长）⇒ "摊开"确实落在 [0, 剩余] 区间里，不溢出。
		#（★ 菜单侧封顶是 const、运行期不可改，所以这里只钉这两端；"旋钮拉到单颗时长就变齐提"
		#  那一条只有对局盘能测（`--captest` 里真的把旋钮拨过去）—— 两侧各测能测的那一半。）
		var ends_ok: bool = is_equal_approx(pb._capture_wave_start(0, 3), 0.0) \
				and is_equal_approx(pb._capture_wave_start(3, 3),
					pb._capture_total_time() - PreviewBoard.ANIM_TIME)
		var wave_ok: bool = adj_ok and wv_bad == 0 and ord_ok and cap_ok and len_free and mono and ends_ok
		if not wave_ok:
			ok = false
		print("[settest]   提子波前顺序+总时长封顶 %s（0 邻1=%s/0 不邻2=%s｜层号 %d/%d 期望 0/1（错 %d）｜delay 随层递增 %s｜最深结束 %.2fs == 封顶 %.2fs（与层数无关 %s）｜起手偏移随层递增 %s｜两端锚点 %s）" % [
			"✓" if wave_ok else "✗", str(adj_ok), str(not pb._neighbors(2).has(0)),
			int(pb._fade[1].get("wave", -1)) if pb._fade.has(1) else -1,
			int(pb._fade[2].get("wave", -1)) if pb._fade.has(2) else -1, wv_bad,
			"✓" if ord_ok else "✗", pb._capture_end_time(1, 1), cap,
			"✓" if len_free else "✗", "✓" if mono else "✗", "✓" if ends_ok else "✗"])
		# 悬浮预览 + 落子下落（2026-09-29 用户口令「落子就是那块预览向下落下」，菜单盘同步）：
		# ① 准入门槛与「能不能下」同源：空点亮 / 已占不亮 / 自杀点不亮
		# ② 预览起手状态必须**逐位等于**下落第一帧（需求的核心不变量，两处代码各写一份、由本断言钉住）
		pb._marks.fill(0)
		pb._fade.clear()
		pb._turn = 1
		pb._hover = 0
		var vis_free: bool = pb._hover_visible()
		pb._marks[0] = 1
		var vis_occ: bool = pb._hover_visible()
		pb._marks[0] = 0
		pb._marks[1] = 2
		pb._marks[3] = 2                       # 白1/白3 夹住 2 → 自杀手
		pb._hover = 2
		var vis_sui: bool = pb._hover_visible()
		pb._marks.fill(0)
		pb._hover = -1
		var gate_ok: bool = vis_free and (not vis_occ) and (not vis_sui)
		if not gate_ok:
			ok = false
		print("[settest]   预览准入门槛 %s（空点=%s 已占=%s 自杀点=%s）" % [
			"✓" if gate_ok else "✗", "✓" if vis_free else "✗",
			"✓" if vis_occ else "✗", "✓" if vis_sui else "✗"])
		var hs: Dictionary = pb._hover_state()
		var ds: Dictionary = pb._drop_state(0.0)
		var dl: Dictionary = pb._drop_state(1.0)
		var dmid: Dictionary = pb._drop_state(0.5)
		var same: bool = Vector2(hs["off"]) == Vector2(ds["off"]) \
			and is_equal_approx(float(hs["alpha"]), float(ds["alpha"]))
		var land: bool = Vector2(dl["off"]) == Vector2.ZERO \
			and is_equal_approx(float(dl["alpha"]), 1.0)
		var midy: float = Vector2(dmid["off"]).y
		var mid_pos: bool = midy < 0.0 and absf(midy) < pb._drop_h()
		# ★★ 透明度爬升只在 `HOVER_ALPHA < 1` 时成立：2026-09-29 用户口令「预览棋子改成不透明」
		#   把顶面定成 1.0，`lerpf(1.0, 1.0, t) ≡ 1.0` 是**自然退化**，不是"爬升坏了"。
		#   两个分支都有牙齿：<1 时钉"起手=常量、半途严格居中、落定=1"；=1 时钉"确实没有爬升"
		#   （菜单侧这两个是 const、运行期不可拧，"旋钮真被读到"由阴性对照仪改实现来证）。
		var ramp_txt := ""
		var ramp_ok := true
		if PreviewBoard.HOVER_ALPHA < 0.999:
			ramp_ok = is_equal_approx(float(ds["alpha"]), PreviewBoard.HOVER_ALPHA) \
				and float(dmid["alpha"]) > float(ds["alpha"]) \
				and float(dmid["alpha"]) < 1.0
			ramp_txt = "常量 %.2f：起手 %.2f → 半途 %.2f → 落定 1.00（爬升 %s）" % [
				PreviewBoard.HOVER_ALPHA, float(ds["alpha"]), float(dmid["alpha"]), "✓" if ramp_ok else "✗"]
		else:
			ramp_ok = is_equal_approx(float(ds["alpha"]), 1.0) \
				and is_equal_approx(float(dmid["alpha"]), 1.0)
			ramp_txt = "常量 1.00（不透明）：起手/半途/落定 α 全 = %.2f（无爬升 %s）" % [
				float(dmid["alpha"]), "✓" if ramp_ok else "✗"]
		var drop_ok: bool = same and land and mid_pos and ramp_ok
		if not drop_ok:
			ok = false
		print("[settest]   预览=下落起手 %s（起手相同=%s 落定=%s 半途 y=%.1f α=%.2f｜%s｜抬高 %.1fpx）" % [
			"✓" if drop_ok else "✗", "✓" if same else "✗", "✓" if land else "✗", midy,
			float(dmid["alpha"]), ramp_txt, pb._drop_h()])
		# 预览**侧壁**（厚度感；已取代原来的「对齐虚线」）：面数 == 格子边数、每个面的四点
		# 恰好是「抬高后的边 a→b」+「落点的边 b→a」；对照：`_hover` 指向已占格时一个面都不该有
		# （走真 `_hover_visible()`）；再加一条**厚度真的看得见**（侧壁必须可辨识地暗于顶面，
		# 否则"厚度"只是名义上的 —— 黑白两方都判）。
		pb._marks.fill(0)
		pb._fade.clear()
		pb._turn = 1
		pb._hover = 0
		var gwalls: Array = pb._hover_side_walls()
		var gp: PackedVector2Array = pb._polys[0]
		var gh: float = pb._drop_h()
		var gbad := 0
		for i in gwalls.size():
			var q: Array = gwalls[i]
			var ea: Vector2 = gp[i]
			var eb: Vector2 = gp[(i + 1) % gp.size()]
			var gexp := [ea + Vector2(0.0, -gh), eb + Vector2(0.0, -gh), eb, ea]
			for k in 4:
				if (q[k] as Vector2).distance_to(gexp[k]) > 0.01:
					gbad += 1
		pb._marks[0] = 1
		var gwalls_blocked: int = pb._hover_side_walls().size()
		pb._marks[0] = 0
		# ★★ 读**实现本身**（`_hover_side_color()`），不是另抄公式 `hbase.darkened(SIDE_DARKEN)`：
		#   自检另抄一份 = 没测那份公式。实测（阴性对照 N8）：抄公式那版把实现改成 `darkened(0.0)`
		#   之后**照旧全绿** —— "厚度感消失"这种 bug 就永远抓不住。
		var thick_bad := 0
		var thick_txt: Array = []
		for col in [1, 2]:
			var hbase: Color = PreviewBoard.PIECE_BLACK if col == 1 else PreviewBoard.PIECE_WHITE
			pb._turn = col
			var wcol: Color = pb._hover_side_color()
			var wl: float = wcol.get_luminance()
			var bl: float = hbase.get_luminance()
			thick_txt.append("%s %.3f<%.3f" % ["✓" if wl <= bl * 0.95 else "✗", wl, bl])
			if not (wl <= bl * 0.95):
				thick_bad += 1
		pb._turn = 1
		# 侧壁**不透明**（`SIDE_ALPHA`）＋ 顶面**不透明**（`HOVER_ALPHA`）。
		# ★★ 这条判据的口径**翻过两次**（0.5 → 1.0），与对局盘 `--hovertest` ⑧ 同步：
		#   第一轮「预览动画侧边改成半透明」；第二轮用户看到实物后「要改成完全不透明才好」。
		#   每次翻面都按纪律补牙齿 —— 只断言"α 等于常量"是**同义反复**（常量写死也绿）。
		#   ★ 判据只读**实现本身**（`_hover_side_color()`），不另抄 `darkened(SIDE_DARKEN)`；
		#     菜单侧这两个是 const ⇒ 运行时**没法**拧旋钮（那是对局盘 ⑧ 才有的手段），
		#     "常量真被读到"只能由**阴性对照仪改实现**来证（N9 / N8 / N14 一族）。
		#     ⇒ 改这里的同时**必须**复核 negctl 里那几条还咬得住（本轮已复核）。
		var walpha: float = pb._hover_side_color().a
		var top_alpha: float = float(pb._hover_state()["alpha"])
		var side_ok: bool = is_equal_approx(walpha, PreviewBoard.SIDE_ALPHA) and walpha >= 0.999
		var top_ok: bool = top_alpha >= 0.999 and is_equal_approx(top_alpha, PreviewBoard.HOVER_ALPHA)
		var wall_ok: bool = gwalls.size() == gp.size() and gbad == 0 \
				and gwalls_blocked == 0 and thick_bad == 0 and side_ok and top_ok
		if not wall_ok:
			ok = false
		print("[settest]   预览侧壁 %s（边 %d → 面 %d，几何错 %d 处｜已占格给 %d 面｜厚度可辨 %s｜侧壁 α=%.2f 不透明 %s｜顶面 α=%.2f 不透明 %s）" % [
			"✓" if wall_ok else "✗", gp.size(), gwalls.size(), gbad, gwalls_blocked,
			" ｜ ".join(thick_txt), walpha, "✓" if side_ok else "✗",
			top_alpha, "✓" if top_ok else "✗"])
	# —— 鼠标指针：开关 + 大小滑条（2026-09-30 新增）——
	# ⚠️ headless 下**没有窗口、光标根本不会被渲染**（`apply_custom_mouse_cursor()` 在 headless
	#    分支直接 return），所以这里验的是「控件 ↔ GameConfig ↔ 素材 ↔ 落盘」这条链路；
	#    "指针长得对不对 / 大小合不合适"只能人眼看（与 `--cursortest` 同一条边界，见那里的说明）。
	var saved_cur_on: bool = GameConfig.cursor_enabled
	var saved_cur_size: int = GameConfig.cursor_size
	DirAccess.open("user://").remove("appearance_selftest.cfg")   # 防旧文件冒充"这次写了"
	# ★★ **读回**时的量化（`load_appearance()` 里那道 `cursor_size_index()`）：
	#    写一个人为的坏值进去再读回来 —— 落在哪一档不重要，**必须落在有素材的四档之一**。
	#    ⚠️ 这条必须自己站着：上面的「怪尺寸被量化」验的是 `cursor_size_index()` 这个**函数**，
	#       验不了「`load_appearance()` 到底有没有调用它」——没这条，那道防护就是没人看的油漆。
	#    （自检盘里只放 cursor 段 ⇒ 其余各项都 fallback 到当前值，等于只读不改，无副作用。）
	var badcf := ConfigFile.new()
	badcf.set_value("cursor", "enabled", false)
	badcf.set_value("cursor", "size", 55)
	badcf.save(GameConfig.APPEARANCE_SELFTEST_PATH)
	GameConfig.load_appearance(GameConfig.APPEARANCE_SELFTEST_PATH)
	var ok_loadq: bool = GameConfig.CURSOR_SIZES.has(GameConfig.cursor_size) \
			and ResourceLoader.exists(GameConfig.cursor_texture_path())
	if not ok_loadq:
		ok = false
	print("[settest]   读回坏值→量化到现存档 %s（盘上 55 → 内存 %d px）" % [
		"✓" if ok_loadq else "✗", GameConfig.cursor_size])
	GameConfig.cursor_enabled = saved_cur_on
	GameConfig.cursor_size = saved_cur_size
	DirAccess.open("user://").remove("appearance_selftest.cfg")   # 再清一次：下面的落盘判据要认新文件
	var cur_ready: bool = is_instance_valid(_cursor_cb) and is_instance_valid(_cursor_sl) \
			and is_instance_valid(_cursor_val)
	var ok_cur: bool = cur_ready
	var cur_detail := "控件齐=%s" % str(cur_ready)
	if cur_ready:
		ok_cur = _cursor_cb.button_pressed == GameConfig.cursor_enabled \
				and is_equal_approx(_cursor_sl.value, float(GameConfig.cursor_size_index())) \
				and _cursor_val.text == ("%d px" % GameConfig.cursor_size) \
				and _cursor_sl.editable == GameConfig.cursor_enabled
		cur_detail += " 开关=%s 档=%d/%d 文案=%s 可拖=%s" % [
			str(_cursor_cb.button_pressed), int(_cursor_sl.value),
			GameConfig.CURSOR_SIZES.size() - 1, _cursor_val.text, str(_cursor_sl.editable)]
	if not ok_cur:
		ok = false
	print("[settest]   鼠标指针控件 %s（%s）" % ["✓" if ok_cur else "✗", cur_detail])
	# ★★ 四档素材必须**全在**。缺一档就会出现"拖到那一档指针消失"——而且不报错：
	#    `apply_custom_mouse_cursor()` 找不到资源只会 push_warning 然后沿用系统光标。
	#    （`--cursortest` ⑤A 守的是同一件事的另一面：给个不存在的值必须报缺失。）
	var missing: Array[String] = []
	for s in GameConfig.CURSOR_SIZES:
		var cpath: String = GameConfig.cursor_texture_path(int(s))
		if not ResourceLoader.exists(cpath):
			missing.append(cpath)
	var ok_cur_assets: bool = missing.is_empty()
	if not ok_cur_assets:
		ok = false
	print("[settest]   四档素材齐全 %s（缺 %d：%s）" % [
		"✓" if ok_cur_assets else "✗", missing.size(), "、".join(missing)])
	# ★★ 滑条**只能产出有素材的档**：这条是 `cursor_size_for_index()` 那条防护的牙齿。
	#    给一个没素材的怪值（55），反查必须把它拽回四档之一，而且那一档的素材必须存在 ——
	#    少了这一步，设置页一旦改成"value 直接当像素"，55 就会静默变成系统箭头。
	GameConfig.cursor_size = 55
	var quant_idx: int = GameConfig.cursor_size_index()
	var ok_quant: bool = quant_idx >= 0 and quant_idx < GameConfig.CURSOR_SIZES.size() \
			and ResourceLoader.exists(GameConfig.cursor_texture_path(
					GameConfig.cursor_size_for_index(quant_idx)))
	if not ok_quant:
		ok = false
	print("[settest]   怪尺寸被量化到现存档 %s（55 → 档 %d = %d px，素材存在=%s）" % [
		"✓" if ok_quant else "✗", quant_idx, GameConfig.cursor_size_for_index(quant_idx),
		str(ok_quant)])
	GameConfig.cursor_size = saved_cur_size
	# —— 真实交互路径（`emit_signal` 模拟玩家点了控件）——
	# ★ gate 只看"控件在不在"（`cur_ready`），**不看上面那条初值判据 `ok_cur`**：
	#   初值一红就把交互整段跳过的话，后面这几条永远轮不到举证，于是让别的判据顶替它红 ——
	#   结论虽然照样是红的，但**红的理由是错的**（本工程 W1 那次「红得有理却报错」的同族坑）。
	if cur_ready:
		# ① 拨开关：GameConfig 跟着翻，且**滑条可用性必须跟着翻**（联动）
		var want_on: bool = not saved_cur_on
		_cursor_cb.toggled.emit(want_on)
		var ok_toggle: bool = GameConfig.cursor_enabled == want_on \
				and _cursor_sl.editable == want_on \
				and _cursor_cb.button_pressed == want_on
		if not ok_toggle:
			ok = false
		print("[settest]   拨开关→联动 %s（cur=%s 滑条可拖=%s 按钮态=%s）" % [
			"✓" if ok_toggle else "✗", str(GameConfig.cursor_enabled),
			str(_cursor_sl.editable), str(_cursor_cb.button_pressed)])
		# ② 拖滑条：换一档 → 尺寸改 + 文案跟随 + 落盘（写到**自检盘**，见下面那条）
		var target_idx: int = (GameConfig.cursor_size_index(saved_cur_size) + 1) \
				% GameConfig.CURSOR_SIZES.size()
		_cursor_sl.value_changed.emit(float(target_idx))
		var want_px: int = GameConfig.cursor_size_for_index(target_idx)
		var ok_size: bool = GameConfig.cursor_size == want_px \
				and _cursor_val.text == ("%d px" % want_px)
		if not ok_size:
			ok = false
		print("[settest]   拖滑条→改尺寸 %s（档 %d → %d px，文案=%s）" % [
			"✓" if ok_size else "✗", target_idx, GameConfig.cursor_size, _cursor_val.text])
		# ★ 阳性对照：上面的操作必须**真的落到盘上**（否则"能用"只是内存里的假象）。
		#   ⚠️ 要在**还原之前**读 —— 还原那次 `save_appearance()` 会把内容盖回原值，
		#     只量收尾的话这条会变成恒真的空判据（2026-09-29 的同族坑）。
		var ccf := ConfigFile.new()
		var loaded_ok: bool = ccf.load(GameConfig.APPEARANCE_SELFTEST_PATH) == OK
		var disk_size: int = int(ccf.get_value("cursor", "size", -1))
		var disk_on: bool = bool(ccf.get_value("cursor", "enabled", true))
		var cur_wrote: bool = loaded_ok and disk_size == GameConfig.cursor_size \
				and disk_on == GameConfig.cursor_enabled
		if not cur_wrote:
			ok = false
		print("[settest]   指针设置已落盘 %s（自检盘读=%s size=%d enabled=%s，期望 size=%d enabled=%s）" % [
			"✓" if cur_wrote else "✗", str(loaded_ok), disk_size, str(disk_on),
			GameConfig.cursor_size, GameConfig.cursor_enabled])
		GameConfig.cursor_enabled = saved_cur_on
		GameConfig.cursor_size = saved_cur_size
		GameConfig.save_appearance()
		_sync_cursor_controls()
	# —— 图模式开关（2026-10-19）——
	# ★ 与「自定义指针」同一套：开关 → GameConfig → 落盘（**自检盘**）→ 还原。
	#   为什么这条必须有：它整条链断了（没接线 / 没写盘 / 写到用户配置上）在设置页上
	#   只表现为"点了没反应"，而效果要到**进对局**才看得见 ⇒ 是所有旋钮里最难靠人眼发现的。
	#   ⚠️ 落盘那条**必须在还原之前**读：`save_appearance()` 在收尾会把值盖回去
	#   （与 cursor 段同一条坑，见那里的注释）。
	var saved_graph: bool = GameConfig.graph_mode
	var graph_ready: bool = is_instance_valid(_graph_cb)
	var ok_graph: bool = graph_ready and _graph_cb.button_pressed == saved_graph
	var graph_txt: String = "控件在=%s 初值=%s" % [str(graph_ready), str(saved_graph)]
	if graph_ready:
		var want_graph: bool = not saved_graph
		_graph_cb.toggled.emit(want_graph)
		var gcf := ConfigFile.new()
		var g_disk_ok: bool = gcf.load(GameConfig.APPEARANCE_SELFTEST_PATH) == OK
		var g_disk: bool = bool(gcf.get_value("appearance", "graph_mode", not want_graph))
		ok_graph = ok_graph and GameConfig.graph_mode == want_graph \
				and _graph_cb.button_pressed == want_graph \
				and g_disk_ok and g_disk == want_graph
		graph_txt += " 拨到=%s 内存=%s 自检盘=%s" % [
			str(want_graph), str(GameConfig.graph_mode), str(g_disk)]
		GameConfig.graph_mode = saved_graph
		GameConfig.save_appearance()
		_sync_graph_control()
	if not ok_graph:
		ok = false
	print("[settest]   图模式开关 %s（%s）" % ["✓" if ok_graph else "✗", graph_txt])
	# 屏幕模式：三个按钮必须存在、与当前模式对齐，且点击能改 GameConfig 并回存盘
	var mb := _find_display_buttons()
	var saved_mode: int = GameConfig.window_mode
	# 这两只在下面「点无边框全屏」那一块里赋值；**先声明**是为了即使按钮数不对（早退）也有定义
	var wrote_selftest: bool = false
	var user_mid: PackedByteArray = user_before
	var ok_disp: bool = mb.size() == 3
	var detail := "按钮数=%d" % mb.size()
	if ok_disp:
		var hit := 0
		for i in mb.size():
			if mb[i].button_pressed:
				hit += 1
		ok_disp = hit == 1 and mb[saved_mode].button_pressed
		detail += " 高亮数=%d 当前=%s" % [hit, GameConfig.window_mode_name()]
	if not ok_disp:
		ok = false
	print("[settest]   屏幕模式按钮 %s（%s）" % ["✓" if ok_disp else "✗", detail])
	# 点击「无边框全屏」→ GameConfig 改值 + 按钮高亮跟随（headless 下窗口调用为 no-op，不崩即算过）
	if mb.size() == 3:
		mb[GameConfig.MODE_BORDERLESS].emit_signal("pressed")
		var ok_click: bool = GameConfig.window_mode == GameConfig.MODE_BORDERLESS \
			and mb[GameConfig.MODE_BORDERLESS].button_pressed
		if not ok_click:
			ok = false
		print("[settest]   切无边框全屏 %s（window_mode=%d 高亮跟随=%s）" % [
			"✓" if ok_click else "✗", GameConfig.window_mode, str(mb[GameConfig.MODE_BORDERLESS].button_pressed)])
		# ★ 阳性对照：这一下**必须**在自检盘上留下 `window_mode=MODE_BORDERLESS` ——
		#   它同时证明两件事：① 真实交互路径确实走到了写盘（闸没把功能一起挡死）；
		#   ② 那次写**改道**了（原来它是直接写用户真配置的，见 `save_appearance()` 的注释）。
		var scf := ConfigFile.new()
		wrote_selftest = scf.load(GameConfig.APPEARANCE_SELFTEST_PATH) == OK \
				and int(scf.get_value("display", "window_mode", -1)) == GameConfig.MODE_BORDERLESS
		user_mid = FileAccess.get_file_as_bytes(user_path)
		GameConfig.window_mode = saved_mode
		GameConfig.save_appearance()          # 还原（改道写自检盘；用户文件由下面那条判据守着）
		_refresh_display_buttons(mb)
	var user_after: PackedByteArray = FileAccess.get_file_as_bytes(user_path)
	var ok_nopollute: bool = wrote_selftest and user_before == user_mid \
			and user_before == user_after
	if not ok_nopollute:
		ok = false
	DirAccess.open("user://").remove("appearance_selftest.cfg")   # 清理：user:// 下不留垃圾
	print("[settest]   不碰用户外观配置 %s（自检盘已写 window_mode=2=%s｜用户文件 %dB 逐字节未变=%s 中途=%s）" % [
		"✓" if ok_nopollute else "✗", str(wrote_selftest), user_before.size(),
		str(user_before == user_after), str(user_before == user_mid)])
	print("[settest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 自检辅助：取设置页里「屏幕模式」那三个按钮（按文字匹配，避免依赖节点层级）
func _find_display_buttons() -> Array[Button]:
	var out: Array[Button] = []
	var want: Array[String] = [
		GameConfig.window_mode_name(GameConfig.MODE_WINDOW),
		GameConfig.window_mode_name(GameConfig.MODE_FULLSCREEN),
		GameConfig.window_mode_name(GameConfig.MODE_BORDERLESS),
	]
	for t in want:
		var b := _find_bottom_button(_settings_root, t)
		if b != null:
			out.append(b)
	return out

## 深度优先找按钮文字等于 text 的 Button
func _find_bottom_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node as Button
	for c in node.get_children():
		var r := _find_bottom_button(c, text)
		if r != null:
			return r
	return null

## 自检辅助：模拟点击预览第 i 格（取其多边形质心，必然落在格内）
## 截图专用（`--screenshot --shotpage=settings --shotdrop`）：把设置页试摆盘定格成
## 「第 3 格挂着半透明悬浮预览 + 第 0 格棋子正落到半途」。
## 做法与对局盘 `--shotdrop` 一致：把 fade 剩余时长设成半途 + 停掉 `_process`（冻结推进）。
## ★ 必须先等两帧：`PreviewBoard` 的多边形是按控件尺寸算的，`_set_page` 那一瞬间 size 还是 0。
func _menu_shot_drop() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var pb := _appr_preview_board as PreviewBoard
	if pb == null:
		print("[shotdrop] 设置页试摆盘不存在，跳过")
		return
	pb._marks.fill(0)
	pb._fade.clear()
	pb._turn = 1
	pb._rebuild_polys()
	pb._marks[0] = 1
	pb._fade[0] = {"t": PreviewBoard.ANIM_TIME * 0.5, "dur": PreviewBoard.ANIM_TIME,
		"in": true, "col": 1}
	pb._hover = 2
	pb.set_process(false)         # 冻结动画推进（同对局盘 `_anim_freeze`）
	pb.queue_redraw()
	print("[shotdrop] 菜单试摆盘：第0格冻在 %.2fs/%.2fs，第2格挂悬浮预览，抬高 %.1fpx（臂长 %.1f）"
		% [pb._fade[0]["t"], PreviewBoard.ANIM_TIME, pb._drop_h(), pb._arm])

## 目检夹具：把**当前页**前 `n` 个「勾选类」控件置为已勾选（供 `--shotcheck` 调）。
##
## ★★ 为什么必须有它（2026-10-15 补，来自一个**真实缺口**，不是"顺手加个开关"）：
##   `--menutest` ⑯ 里那两条量"勾色"的判据（勾/本体、勾/方块）读的是**导出图标重上色**的
##   像素；而截图夹具里**一个已勾选样本都没有** —— 设置页两个开关默认关、棋谱页 402 个
##   勾选框默认不勾 ⇒ 「勾压在深棕方块上到底看不看得清」这件事，**判据有数、肉眼一次都没见过**
##   （此前只用离线拼的图标对照图代偿，而离线重上色与真机 `_draw` 出来的并不是同一张图）。
##   ⇒ 补这个夹具，把"已勾选"变成**可复现的一帧**。
##
## ⚠️ 三条纪律（都是这一类夹具最容易踩的）：
##   ① 必须排在 `--shotpage=` 那一段**之后**调 —— 控件得先随页面建出来才有得勾；
##   ② 改状态必须走 `set_pressed_no_signal()` **而不是** `button_pressed = true`：
##      后者会**发 `toggled` 信号**，把业务回调（静音 / 自动播放）带出来 —— 那是
##      **夹具替被测物做事**，截出来的不再是产品自己的样子，还可能顺手改掉用户设置；
##   ③ 只改**内存里的视图态**、不写 `user://`：进程退出即消失（同 `--shotitems` 只读不写）。
##   ★ 也刻意**不重上色**：勾与本体那对色本就由 `_ink_apply_control()` 上过（那才是被测对象），
##     夹具在这里再描一遍就等于"夹具帮忙修好了"。
func _menu_shot_check(n: int) -> void:
	var ctls: Array[Control] = []
	GameConfig.collect_controls(self, ctls)
	var hit: int = 0
	var names: Array[String] = []
	for c in ctls:
		if not (c is CheckBox or c is CheckButton):
			continue
		if hit >= n:
			break
		(c as BaseButton).set_pressed_no_signal(true)
		hit += 1
		names.append("%s「%s」" % [c.get_class(), _ctrl_text_hint(c)])
	# ★ 必须把**勾了谁**打出来：否则截图里"哪一处的变化是这次勾选造成的"无从归因 ——
	#   实测踩到过一次：只印总数「已勾选 2 个」时，diff 出两簇改动却说不清第二簇是哪个控件，
	#   差点误判成"夹具越权改了别处"。夹具的输出要和它的作用**一一对应**（铁律 12 同族）。
	print("[shotcheck] 已勾选 %d 个勾选类控件（请求 %d；当前页=%d）：%s" % [
		hit, n, _page, "、".join(names)])

func _click_preview_cell(pb: Control, i: int) -> void:
	if pb == null or i >= pb._polys.size():
		return
	var poly: PackedVector2Array = pb._polys[i]
	var s := Vector2.ZERO
	for p in poly:
		s += p
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = s / float(maxi(poly.size(), 1))
	pb._gui_input(ev)

## 自检（--boardtest）：棋盘类型切换的折叠/换盘时序。
## 现在守三件事（都仍有牙齿）：
##   ① 切换时**先收回**（`_board_target → 0`）、`_sel_board` 暂不落定、`_board_pending` 记住目标；
##   ② 凹陷态（`_items[i]["selected"]`）**立刻**跟到新块 —— 不等收回动画；
##   ③ 推进帧之后：切换落定（`_sel_board == other` 且 `_board_pending < 0`）**并且重新展开**
##      （`_board_t > 0.99`）—— 少了"重新展开"这半，"卡在收回态"（屏幕上少一行选项）
##      是静默的：`_sel_board` 已经对了，别处一条判据都不会红。
func _board_fold_test() -> void:
	_set_page(PAGE_MAIN)
	_layout_setup()
	for i in 60:                       # 先让初始状态稳定（默认棋盘的展开/收回走到头）
		_process(1.0 / 60.0)
	var start: int = _sel_board
	var other: int = BOARD_CUBE if start != BOARD_CUBE else BOARD_PENROSE
	# ① 点击另一棋盘：应立刻进入收回（target=0），锚点暂不变，但选中态已跟随
	_select_board(other)
	var ok_hold: bool = (_board_target < 0.001) and (_sel_board == start) and (_board_pending == other)
	var ok_stone: bool = _selected_board_label() == _board_label(other)
	# ② 推进帧：收完 → 换锚点 → 重新展开。
	#    ⚠️ 帧数要给足（180 ≈ 3s）：最坏情形是 收回0.3s + 展开0.3s，再算上缓动的尾段，
	#       给一倍余量以免把"慢"误报成"坏"（这条余量是滑行时代留下的，现在更宽裕，不必收）。
	for i in 180:
		_process(1.0 / 60.0)
	var ok_done: bool = (_sel_board == other) and (_board_pending < 0) and (_board_t > 0.99)
	# ③ 再切回去：同一条时序链必须**双向**成立（只验一个方向时"回程卡住"测不到）
	_select_board(start)
	var ok_hold2: bool = (_board_target < 0.001) and (_sel_board == other)
	for i in 180:
		_process(1.0 / 60.0)
	var home_x: float = _find_center("board", _board_label(start)).x
	var ok_back: bool = (_sel_board == start) and (_board_pending < 0) and (_board_t > 0.99)
	var ok: bool = ok_hold and ok_stone and ok_done and ok_hold2 and ok_back
	print("[boardtest] %s→%s→%s：先收回=%s 凹陷态跟随=%s 到位后再展开=%s 回程同序=%s 末态t=%.2f 落位x=%.0f %s" % [
		_board_label(start), _board_label(other), _board_label(start), ok_hold, ok_stone,
		ok_done, ok_back, _board_t, home_x,
		"通过 ✓" if ok else "失败 ✗"])
	get_tree().quit()

## 当前被选中的棋盘类型文字（自检用：验证凹陷态是否立即跟到新块）
func _selected_board_label() -> String:
	for it in _items:
		if it["group"] == "board" and bool(it["selected"]):
			return it["label"]
	return ""

## 二级行（group "boardsize"）三瓣当前的标签，按槽位顺序（自检用）。
## 注意这一行有**两种含义**（普通棋盘=大小三档 / 爱因斯坦=种类三档），所以自检不能按字面断言，
## 只能「先读标签、再按棋盘类型判期望」。
func _boardsize_labels() -> Array[String]:
	var out: Array[String] = []
	for it in _items:
		if it["group"] == "boardsize":
			out.append(String(it["label"]))
	return out

## 二级行里带凹陷态那一瓣的标签（没有则空串）——自检验证「选中态跟着走」用
func _selected_boardsize_label() -> String:
	for it in _items:
		if it["group"] == "boardsize" and bool(it["selected"]):
			return String(it["label"])
	return ""

## 深度优先找第一个指定类型的控件（自检用）
func _find_first(node: Node, cls: StringName) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find_first(c, cls)
		if r != null:
			return r
	return null

## 构建「外观」分组：主题选择 + 恢复默认（配色细项已删繁就简，一切以主题为准）
func _build_appearance_group(root: VBoxContainer) -> void:
	root.add_child(_ui_group_label("外观"))
	# 预览在左栏（_build_settings_ui 里构建），此处只放主题选择

	# 主题（预设配色方案）：★ 2026-10-08 起**单档**（不再分浅/深两版），12 个主题一行排布、
	# 自动换行；行首标签改为「分组标签」（单档时为空串 ⇒ **不画**，不占宽度）。
	# 按钮是纯色块、不带文字（名字走 tooltip），所以方块可以做得方正紧凑。
	_preset_btns.clear()
	var groups: Array = GameConfig.preset_name_groups()
	var group_marks: Array[String] = MenuModel.GROUP_LABELS   # 名字真源在 MenuModel（手机菜单读同一份）
	for gi in groups.size():
		var names: Array = groups[gi]
		if names.is_empty():
			continue
		# ★ 用 **HFlowContainer**（自动换行）而不是 HBoxContainer：单档后是 12 个主题，
		#   一行硬排需要 12×72px + 间距 ≈ 1000px，而左栏可用宽度放不下 ——
		#   HBox 不会换行，只会把色块压扁或溢出到别的控件上（且**不报错**）。
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 12)
		row.add_theme_constant_override("v_separation", 10)
		var mk: String = group_marks[gi] if gi < group_marks.size() else ""
		if mk != "":                       # 单档时标签是空串 ⇒ 跳过（否则行首白占一格）
			var tag := _ui_label(mk, 16)
			tag.custom_minimum_size = Vector2(28.0, 0.0)
			row.add_child(tag)
		for pname in names:
			var sb := _make_preset_button(String(pname))
			_preset_btns.append(sb)
			row.add_child(sb)
		root.add_child(row)
	_refresh_preset_swatches()   # 初始高亮：按当前配色决定（自定义配色则全部无高亮）

	# 恢复默认主题
	var reset := Button.new()
	reset.text = "恢复默认主题"
	reset.custom_minimum_size = Vector2(200.0, 38.0)
	_style_page_button(reset)
	reset.pressed.connect(func() -> void:
		GameConfig.mark_appearance_dirty()      # 用户操作 ⇒ 置脏（第 0 步）
		GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
		GameConfig.bg_brightness = 1.0
		GameConfig.save_appearance()
		_apply_appearance()
		_refresh_preset_swatches())   # 不弹提示：此前的浮层提示会压到标题上
	root.add_child(reset)

	# —— 鼠标指针（2026-09-30 用户要求：设置里加「光标开关」+「光标大小调节」）——
	# 放在外观组末尾：它和配色同属"屏幕上看得见的观感项"，但它自成一个语义块，
	# 所以直接排在「恢复默认主题」**之后** —— 挨着放会让人以为按钮也把指针一并恢复掉。
	root.add_child(_ui_label("鼠标指针", 18))
	var c_row := HBoxContainer.new()
	_cursor_cb = CheckButton.new()
	# ★ 用 `toggled`（**带 bool 参数**）而不是 `pressed`：后者要靠"控件自己已经翻转过
	#   button_pressed"才能读到新值 —— 那是隐式状态依赖（本工程踩过一整类，
	#   见 2026-09-29 `--whitepreview` 靠 `place_stone()` 副作用抵消那次）。
	_cursor_cb.toggled.connect(_on_cursor_toggled)
	c_row.add_child(_ui_label("自定义指针")); c_row.add_child(_cursor_cb)
	root.add_child(c_row)

	var sz_row := HBoxContainer.new()
	_cursor_sl = HSlider.new()
	_cursor_sl.min_value = 0.0
	_cursor_sl.max_value = float(GameConfig.CURSOR_SIZES.size() - 1)
	_cursor_sl.step = 1.0
	_cursor_sl.custom_minimum_size = Vector2(200.0, 28.0)
	_cursor_sl.value_changed.connect(_on_cursor_size_changed)
	_cursor_val = _ui_label(_cursor_size_text(), 18)
	sz_row.add_child(_ui_label("指针大小")); sz_row.add_child(_cursor_sl); sz_row.add_child(_cursor_val)
	root.add_child(sz_row)
	# ⚠️ 说明文字是 **Label**（不解析 Markdown）—— 写 `**强调**` 会原样把星号画出来（截图实测踩过）；
	#    另外这一行会挤在内容列宽度里，太长会被右侧裁掉（竖屏 520px 列宽下尤其明显）。
	root.add_child(_ui_label("关闭时用系统箭头。Windows 上不随系统缩放变大，高分屏建议选大档", 14))
	# ★ 三样东西（开关状态 / 滑条档位 / 数值文案）的初值，加上「关掉就不能拖」这条联动，
	#   全部由 `_sync_cursor_controls()` **同一套判据**派生 —— 分开写三处迟早漏一处，
	#   症状是"关了还能拖、拖了却没反应"（不报错的静默失效）。
	_sync_cursor_controls()

## 「自定义指针」开关（typed signal：`toggled(on: bool)`）：立即生效 + 落盘，
## 并让「指针大小」跟着可用/不可用。
##
## ★★ 开头的**幂等守卫**是必须的，不要删：`_sync_cursor_controls()` 用普通赋值写
##    `button_pressed`（为了视觉能正常刷新，见那里的注释），而普通赋值**会发 `toggled` 信号**
##    ⇒ 构建设置页那一下会回调到这里。若值没变就直接返回，那一次"同步"就自然被忽略掉
##    —— 不弹提示、不白写盘。（这就是 `--settest`「打开设置页不写盘」守的那件事。）
func _on_cursor_toggled(on: bool) -> void:
	if on == GameConfig.cursor_enabled:
		return          # 同步产生的信号（或重复点同一个状态）：无变化，不该有副作用
	GameConfig.cursor_enabled = on
	GameConfig.apply_custom_mouse_cursor()      # 立即生效（关= Input.set_custom_mouse_cursor(null) 恢复系统箭头）
	GameConfig.mark_appearance_dirty()      # 用户操作 ⇒ 置脏（第 0 步）
	GameConfig.save_appearance()
	_sync_cursor_controls()
	_tip("自定义指针：%s" % ("开" if GameConfig.cursor_enabled else "关（系统箭头）"))

## 「指针大小」滑条。★ 收到的 v 是**档位下标**（0..3），不是像素。
## 幂等守卫同 `_on_cursor_toggled()`：同步赋值会发 `value_changed`，值没变就别动。
func _on_cursor_size_changed(v: float) -> void:
	var px: int = GameConfig.cursor_size_for_index(int(v))
	if px == GameConfig.cursor_size:
		return
	GameConfig.cursor_size = px
	GameConfig.apply_custom_mouse_cursor()
	GameConfig.mark_appearance_dirty()      # 用户操作 ⇒ 置脏（第 0 步）
	GameConfig.save_appearance()
	_sync_cursor_controls()

## 开关状态 / 滑条档位 / 数值文案 / 滑条可用性 —— **唯一**同步入口。
##
## ★★ 这里用**普通赋值**（不是 `set_pressed_no_signal()` / `set_value_no_signal()`），
##    理由实测过（2026-09-30，两张真机截图对像素）：
##      · `set_pressed_no_signal(true)` 之后，**逻辑**上 `button_pressed == true`（探针实测），
##        但画面上 CheckButton 仍停在默认的"关"外观 —— 它不刷新视觉。
##        症状：设置页里「自定义指针」明明该是开的，却画成灰的关（静态截图才看得出来）。
##      · 同一张图里用普通赋值的「自动播放音乐」显示正常 ⇒ 差异就在这个 API 上。
##    所以改回普通赋值，并把"同步不该有副作用"这件事交给两个回调开头的**幂等守卫**
##    （值没变就 return）。两条一起才成立：缺守卫 ⇒ 构建即写盘 + 弹提示；
##    缺普通赋值 ⇒ 状态对但画错。
func _sync_cursor_controls() -> void:
	var idx: int = GameConfig.cursor_size_index()
	if is_instance_valid(_cursor_cb):
		_cursor_cb.button_pressed = GameConfig.cursor_enabled
	if is_instance_valid(_cursor_sl):
		_cursor_sl.value = float(idx)
		_cursor_sl.editable = GameConfig.cursor_enabled
	if is_instance_valid(_cursor_val):
		_cursor_val.text = _cursor_size_text()

## 数值文案由 GameConfig 现算，不在回调里手写 `%d px` —— 手写就会出现"数字与配置不同源"。
func _cursor_size_text() -> String:
	return "%d px" % GameConfig.cursor_size

## 同步色块按钮的选中高亮：只有当前配色与某预设完全匹配时才高亮它
##（matches_preset() 会比对四色，若用户改过任何一项即视为自定义 → 全部不高亮）
func _refresh_preset_swatches() -> void:
	_preset_sel = GameConfig.matches_preset()
	for b in _preset_btns:
		if is_instance_valid(b):
			b.queue_redraw()

## 预设按钮 = 纯色块（不带文字）。
## 方块内：左半＝背景色、右半＝棋盘色（二者直接相邻，明度差一眼可见），
## 底部一条细带＝该主题的专属标题色 → 一个方块同时交代 bg/board/accent 三色。
## 悬停或选中时描一圈浅边并加粗，让"当前主题"在 12 个方块中一眼可辨。
## ★ 别在此写死主题个数（旧文写"14 个"，主题表改版后即不实）：真源是 `GameConfig.preset_names().size()`。
## 名字不显示在方块上（用户要求去掉文字），改用 tooltip 承载。
func _make_preset_button(pname: String) -> Button:
	var pb := Button.new()
	var cols: Dictionary = GameConfig.preset_colors(pname)
	pb.text = ""                                        # 不带文字
	pb.flat = true                                      # 去掉默认按钮底/边框，只留自绘色块
	pb.custom_minimum_size = Vector2(SWATCH_W, SWATCH_H)
	pb.tooltip_text = pname

	pb.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, pb.size)
		var bg: Color = cols.get("bg", Color.BLACK)
		var board: Color = cols.get("board", Color.BLACK)
		var line: Color = cols.get("line", Color.WHITE)
		var accent: Color = cols.get("accent", Color.WHITE)
		var band_h: float = maxf(3.0, r.size.y * 0.11)   # 标题色细带（收窄，免得抢了主色）
		var body_h: float = r.size.y - band_h
		# 左半背景色、右半棋盘色：两块直接相邻，主题的"背景 vs 棋盘"明度差一眼可见
		var half: float = r.size.x * 0.5
		pb.draw_rect(Rect2(0.0, 0.0, half, body_h), bg, true)
		pb.draw_rect(Rect2(half, 0.0, half, body_h), board, true)
		# 中缝：该主题的轮廓色，暗示棋盘的线条观感
		pb.draw_line(Vector2(half, 0.0), Vector2(half, body_h), line, 1.0)
		# 底边标题色细带：只铺中间 60%，两端留白 —— 铺满会在相邻方块间连成彩色条，看着很吵
		var bw: float = r.size.x * 0.60
		pb.draw_rect(Rect2((r.size.x - bw) * 0.5, body_h + (band_h - 3.0) * 0.5, bw, 3.0), accent, true)
		# 描边：选中加粗＋亮白；悬停次之；平时也保留清晰边界（浅色行同色系相邻时不糊）
		var yl: float = bg.get_luminance()
		var strong: Color = Color(1, 1, 1, 0.95) if yl < 0.45 else Color(0, 0, 0, 0.90)
		var dim: Color = Color(1, 1, 1, 0.55) if yl < 0.45 else Color(0, 0, 0, 0.55)
		var w: float = 1.0
		var edge: Color = dim
		if _preset_sel == pname:
			w = 3.0
			edge = strong
		elif pb.is_hovered():
			w = 2.0
			edge = strong
		pb.draw_rect(r.grow(-w * 0.5), edge, false, w))

	# 悬停进出要重绘（描边随 hover 变化）
	pb.mouse_entered.connect(func() -> void: pb.queue_redraw())
	pb.mouse_exited.connect(func() -> void: pb.queue_redraw())
	# 不弹「已应用配色」提示：该浮层位于标题区，会与标题文字重叠
	pb.pressed.connect(func() -> void:
		if GameConfig.apply_preset(pname):
			GameConfig.mark_appearance_dirty()      # 用户操作 ⇒ 置脏（第 0 步）
			GameConfig.save_appearance()
			_apply_appearance()
			_refresh_preset_swatches())
	return pb

## 外观预览：背景色块内嵌迷你棋盘（用主题棋盘色填充、轮廓色描边，切主题即时刷新）
## 挂在设置页左栏，垂直撑满可用高度 —— 星形大小由栏宽决定，比原先 84px 高的小条大得多。
func _build_appearance_preview(parent: Node, box_h: float) -> void:
	var top_sp := Control.new()          # 弹性空白：让预览+说明整体垂直居中
	top_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(top_sp)
	var box := ColorRect.new()
	# ★★ 2026-10-04 v4 修正：宽高**都**取 `box_h` —— 原先写 `Vector2(0.0, box_h)`（宽 0 =
	#   水平撑满左栏），靠"左栏宽恰好 == box_h"这个**假设**凑正方形。扁视口下 box_h 由
	#   **面板高度**推出（比左栏窄）⇒ 假设不成立 ⇒ 实测 346×338，判据「预览近似正方形」✗。
	#   ⇒ 改成**按构造**正方形 + 水平居中（不再随左栏拉伸）。
	box.custom_minimum_size = Vector2(box_h, box_h)   # 正方形（**构造**保证，不靠外部宽度）
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var board := PreviewBoard.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.clip_contents = true   # 图形超出预览框的部分裁掉
	board.mouse_filter = Control.MOUSE_FILTER_STOP   # 可点击试摆（黑白交替）
	box.add_child(board)
	parent.add_child(box)
	_appr_preview_bg = box
	_appr_preview_board = board
	_update_appearance_preview()
	var cap := _ui_label("主题预览 · 点格子试摆", 14)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(cap)
	var bot_sp := Control.new()
	bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(bot_sp)

# ===== 按选择算「真实盘形」（首页背景密铺的唯一几何来源）=====
## ★★ 2026-10-02 沿革：这套东西原本是给主菜单右下角「棋盘预览卡」用的。
##   用户口令「既然已经有了背景棋盘效果，那就可以彻底删除棋盘预览了」⇒ 卡片删除，
##   而**这套几何换算整套留下** —— 首页背景密铺（`_bg_ensure()`）现在就是靠它拿盘形的。
##   连带改名：`_preview_gen` → `_shape_gen_get`、`_preview_shape_polys` → `_shape_polys`、
##   `_pv_gen` → `_shape_gen`。为什么非改不可：见 `SHAPE_PAD_RATIO` 的注释
##   （留着 `preview` 的名字 == 让下一个人以为预览没删干净）。
##   ❌ 随卡片一起删掉的是：`_preview_is_random()`（它的全部调用者都在卡片的"随机档画问号"
##   分支与自检里）、`_preview_ensure()`、`_preview_update()`、`_preview_card_rect()`、
##   `_menu_ink_rects()`、`class BoardPreview`、`--previewtest`。
##   ⚠️ 背景密铺**不需要**「是不是随机盘」这个判断：它按 `_menu_bg_size = RANDOM` 直接要
##   "该盘能生成的最大那档几何"（见 `_sync_menu_bg()`）—— 那是张真的盘，照画即可。
##
## 离树实例化的 game.gd：只借它的生成器算几何，**不进场景树**（所以它的 `_ready()` 不会跑，
## 不会去生成棋盘、连信号、碰 UI）。
## 安全性已核对：`generate_board()` 及其调到的全部生成器（彭罗斯/立方体/筝形/雪花/爱因斯坦）
## 全程只读写自己的成员数组，不碰场景树、不读视口、不 await。
func _shape_gen_get() -> Node:
	if _shape_gen == null or not is_instance_valid(_shape_gen):
		var sc: GDScript = load("res://game.gd") as GDScript
		_shape_gen = sc.new()
	return _shape_gen

## 按选择算一遍**真实盘形**，并等比缩放居中到 w×h 的局部坐标；返回每片瓷砖的多边形。
## ⚠️ `game.gd` 的 `tiles` 存的是**顶点索引**（`Array[int]`），真实坐标在 `vertices` 里 ——
##   直接拿 `tiles` 当坐标用会静默画出一堆垃圾（本函数第一版就是这么写错的）。
## ★ 唯一的调用者是首页背景密铺（`_bg_ensure()`），而它把结果**缓存**下来逐帧复用 ——
##   实测 `generate_board()` 3~12ms，每帧跑必卡（见 `_bg_polys` 的注释）。
## 历史：上一版还服务「棋盘预览卡」，那时这里有一条「随机档不调这个、改画问号占位」的分支
##   —— 随卡片一起删了（背景要的就是真几何，不问随机与否，见 `_shape_gen_get()` 的说明）。
func _shape_polys(ch: Dictionary, w: float, h: float) -> Array:
	var g := _shape_gen_get()
	var save: Array = [GameConfig.board_type, GameConfig.board_size, GameConfig.hat_kind]
	GameConfig.board_type = int(ch["board"])
	GameConfig.board_size = int(ch["size"])
	GameConfig.hat_kind = int(ch["hat_kind"])
	g.call("_apply_board_size", int(ch["size"]))
	g.call("generate_board")
	var verts: Array = g.get("vertices")
	var tiles: Array = g.get("tiles")
	GameConfig.board_type = save[0]
	GameConfig.board_size = save[1]
	GameConfig.hat_kind = save[2]
	# ① 盘面外接盒（所有瓷砖顶点）
	var bb := Rect2()
	var first := true
	for t in tiles:
		for idx in (t as Array):
			var v: Vector2 = verts[int(idx)]
			if first:
				bb = Rect2(v, Vector2.ZERO)
				first = false
			else:
				bb = bb.expand(v)
	var out: Array = []
	if first or bb.size.x <= 0.0 or bb.size.y <= 0.0:
		return out
	# ② 等比缩放 + 居中（等比，不能各轴独立缩放 —— 那会把盘压扁、菱形变歪）
	var pad: float = maxf(minf(w, h) * SHAPE_PAD_RATIO, 4.0)
	var k: float = minf((w - pad * 2.0) / bb.size.x, (h - pad * 2.0) / bb.size.y)
	var c0: Vector2 = bb.position + bb.size * 0.5
	var dst := Vector2(w, h) * 0.5
	for t in tiles:
		var poly := PackedVector2Array()
		for idx in (t as Array):
			poly.append(dst + ((verts[int(idx)] as Vector2) - c0) * k)
		out.append(poly)
	return out

## 某一块**实际绘制**用的标签字号（**唯一真源**）。
## ★ `_draw()` / `_pass_ink_rect()` / `_nav_label_overlap_count()` / 各条标签判据全部读它 ——
##   各写一份就会出现「判据量 24、画 20」那种**静默**错配（判据绿、字照叠）。
func _draw_fs_for(it: Dictionary) -> int:
	var g: String = str(it["group"])
	# ★★ 2026-10-04 v4：底栏四块（练习 / 棋谱 / 对弈 / 设置）**全部归 `nav`** ——
	#   它们现在是同一行里的邻居（v3 起从"顶部左簇 / 右簇"两簇搬到底部一行）。
	#   字号由 `_layout_footer_row()` 按区域宽度逐档下调，四块一起读 `_nav_label_fs`。
	#   ⚠️ v3 还给 `quick` 单独留过一支（「练习」当时是开关）；四块同类后已删 ——
	#   留着第二支就是"同一行两个字号真源"，而那种错是**静默的**（判据量 24、画 20）。
	if g == "nav":
		return _label_fs_fit(_nav_label_fs, str(it["label"]), it["poly"])
	return _label_fs_fit(_label_font_size_for(g), str(it["label"]), it["poly"])

## ★★ 文字放进按钮里面之后，字号必须**自适应到按钮的容量** ——
##   否则窄视口下（真机 1152×648 时 R≈38，按钮宽仅 76px）「爱因斯坦」这种长标签
##   会直接溢出到按钮外面（旧口径里文字本来就在外面，多长都装得下 ⇒ 从来没有这个约束）。
## ★ 它是 `_draw_fs_for()` 的**一部分** ⇒ 绘制与每一条判据读到同一个值
##   （两处各算一次就是"判据量 24、画 20"那类静默错配）。
## ★ 一次按比例求解（不是逐档循环递减）：循环在每帧每个标签上跑，白烧 CPU。
func _label_fs_fit(fs0: int, text: String, poly: PackedVector2Array) -> int:
	if poly.size() < 3:
		return fs0
	var f: Font = UITheme.body_font()
	var tw0: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0).x
	var th0: float = f.get_ascent(fs0) + f.get_descent(fs0)
	if tw0 <= 0.01 or th0 <= 0.01:
		return fs0
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	var avail_w: float = bb.size.x - 2.0 * BTN_TEXT_PAD
	var avail_h: float = bb.size.y - 2.0 * BTN_TEXT_PAD * 0.6
	if avail_w <= 4.0 or avail_h <= 4.0:
		return BTN_TEXT_FS_MIN
	var s: float = minf(avail_w / tw0, avail_h / th0)
	return maxi(int(floor(float(fs0) * minf(s, 1.0))), BTN_TEXT_FS_MIN)

## 某一笔**标签自己**的墨迹矩形（不含块本体）。**唯一真源**：`_pass_ink_rect()` 与
## `--labeltest` 的「标签互不重叠」都读它。
##
## ★★ 2026-10-04 v4 抽出来的理由（这是本轮一个**真 bug**）：`--labeltest` 的
##   `_label_no_overlap_one()` 原先**自己另算了一套标签位置** ——
##   它把标签放在"块包围盒正上方 `-6.0 - 字高`"，而绘制端放的是
##   `_label_pos_for()` 的结果（折叠子项在块的**外侧**、还要加放射散开与锚点避让）。
##   ⇒ 那条判据量的是**一个屏幕上不存在的位置**：它此前能全绿纯属巧合（幽灵位置恰好不叠），
##   而本轮底栏改版后它开始报 11 对重叠 —— 全是幽灵之间的重叠，画面上一个字都没叠。
##   教训与 `_draw_fs_for()` 那次同源：**判据与绘制必须读同一份几何**，否则
##   "判据绿/红"与"用户看到什么"之间没有任何关系（而它看起来像在守标签）。
func _label_ink_rect(it: Dictionary, draw_center: Vector2, draw_poly: PackedVector2Array,
		label_fs: int, is_home: bool) -> Rect2:
	var lp: Vector2 = _ink_label_pos(it, draw_center, draw_poly, label_fs, is_home)
	var th: float = _font_h(label_fs)
	var tw: float = UITheme.body_font().get_string_size(str(it["label"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x
	return Rect2(lp - Vector2(tw, th) * 0.5, Vector2(tw, th))

## 一块瓷砖的墨迹矩形（块 ∪ 标签）。**唯一真源**：`--menutest` 的 ⑤c/⑤e/⑧/⑬ 都读它
## （块本体 + 标签一起算 —— 只量"块"会漏掉向外散开的标签，实测比块顶还高十几个像素）。
## ★ 2026-10-02：`_menu_ink_rects()`（批量版，专供「棋盘预览卡让位」）已随卡片删除 ——
##   它是本函数唯一的批量调用者，删掉后调用者只剩"单块 + 循环行槽位"这几处，口径不变。
## ★ 2026-10-04 v3：原先的头两个调用方（`_content_ink_top()` 与 `_header_band()` 的排版）
##   已随入口行翻到底部而消失；现在它只服务判据，**别再**把布局算法挂到它上面
##   （布局读真源 `_footer_band()`，判据量派生结果 —— 两层分工，见 ⑤e 的说明）。
## ★ 2026-10-04 v4：标签那一半走 `_label_ink_rect()`（同一个真源，见那里的说明）。
func _pass_ink_rect(it: Dictionary, draw_center: Vector2, draw_poly: PackedVector2Array,
		label_fs: int, is_home: bool) -> Rect2:
	var r := Rect2(draw_poly[0], Vector2.ZERO)
	for p in draw_poly:
		r = r.expand(p)
	var lr: Rect2 = _label_ink_rect(it, draw_center, draw_poly, label_fs, is_home)
	r = r.expand(lr.position)
	r = r.expand(lr.end)
	return r

## 绘制端某一笔的标签中心。**绘制与几何判据（`_pass_ink_rect`）共用这一个** ——
## 判据要是另写一套标签位置，就会和「实际画在哪」分叉（曾经表现为「卡片压标签」：
## 预览卡按自己算的位置躲，实际字画在另一个地方 ⇒ 判据绿、字照叠）。
## ★ 2026-10-09：文字改画在**按钮内部**（见 `_label_pos_for()` 的注）⇒ 位置就是按钮中心，
##   "锚点避让 / 放射散开 / is_home 参与与否"那一整套随之外挂几何一起作废。
func _ink_label_pos(it: Dictionary, draw_center: Vector2, _poly: PackedVector2Array,
		label_fs: int, _is_home: bool) -> Vector2:
	return _label_pos_for(it, draw_center, label_fs)

## 退出时释放离树生成器实例（`_shape_gen_get()` 懒创建的那个）。
## Node 不是 RefCounted，不 free 就会漏 —— 实测不释放时 Godot 退出会报
## 「RID of type "CanvasItem" was leaked」。
## ★ 2026-10-02：本函数随「棋盘预览卡」差点被一并删除 —— 那是错的。它释放的是 `_shape_gen`，
##   而**首页背景密铺还在用它**（`_bg_ensure()` → `_shape_polys()`）。
##   判别口径：看**成员**的服务对象（谁调 `_shape_polys()`），而不是看它当初为谁而写。
func _exit_tree() -> void:
	if _shape_gen != null and is_instance_valid(_shape_gen):
		_shape_gen.free()
	_shape_gen = null

## 收集一棵子树里的所有 `LineEdit`。★ 与 `collect_buttons_deep()` **类型不同、契约不同**
##   （那个收 `Button` 家族；这里只收输入框）⇒ 不是重复实现，但两边的遍历写法要一致
##   （都是"自己是 + 递归子节点"）。
func _collect_line_edits(node: Node, out: Array[LineEdit]) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is LineEdit:
		out.append(node as LineEdit)
	for c in node.get_children():
		_collect_line_edits(c, out)


## 输入框的主题审计（与 `_themed_button_audit()` 同族，逐条射程不同）：
##   ① 走过 `style_theme_line_edit()`（元数据在）、② 表面 ∈ 允许集合、
##   ③ 字/盒 ≥ `BTN_TEXT_MIN_CONTRAST`、④ 占位符/盒 ≥ `INPUT_PLACEHOLDER_MIN_CONTRAST`、
##   ④b 占位符**明显淡于正文**、⑤ 盒底/字/占位符三支色逐位等于真源给的、⑥ 圆角是我们的签名。
## ★ ④/④b 必须单列：占位符与正文是两支**不同的**颜色，而"正文达标"完全可能与"占位符看不清"
##   或"占位符与正文一样浓"同时成立 —— 只量正文就会漏掉它（第一版就是这么漏的）。
func _themed_input_audit(root: Node, allowed_hosts: Array, tag: String) -> Dictionary:
	var out: Dictionary = {
		"tag": tag, "total": 0, "bad": [],
		"worst_text": 999.0, "worst_text_who": "",
		"worst_ph": 999.0, "worst_ph_who": "",
	}
	if root == null or not is_instance_valid(root):
		out["bad"].append("%s：根节点不存在" % tag)
		return out
	var les: Array[LineEdit] = []
	_collect_line_edits(root, les)
	for n in les:
		var le: LineEdit = n
		out["total"] = int(out["total"]) + 1
		var pr: Dictionary = GameConfig.probe_line_edit_theme(le)
		var label: String = "「%s」" % (le.text if le.text != "" else le.placeholder_text)
		if not bool(pr["styled"]):
			out["bad"].append("%s输入框%s 没走过样式入口（盒子仍是引擎默认深灰）" % [tag, label])
			continue
		var host: Color = pr["host"]
		var hit: bool = false
		for h in allowed_hosts:
			if (host as Color).is_equal_approx(h):
				hit = true
				break
		if not hit:
			out["bad"].append("%s输入框%s 表面不对：%s（允许 %s）" % [tag, label, str(host), str(allowed_hosts)])
		if not is_equal_approx(float(pr["corner"]), GameConfig.DIALOG_CORNER):
			out["bad"].append("%s输入框%s 圆角 %.1f ≠ %.1f" % [
				tag, label, float(pr["corner"]), GameConfig.DIALOG_CORNER])
		if not (pr["fill"] as Color).is_equal_approx(pr["fill_expect"]):
			out["bad"].append("%s输入框%s 盒底 %s ≠ 真源给的 %s" % [
				tag, label, str(pr["fill"]), str(pr["fill_expect"])])
		var ct: float = GameConfig.contrast_of(pr["ink"], pr["fill"])
		if ct < float(out["worst_text"]):
			out["worst_text"] = ct
			out["worst_text_who"] = tag + label
		if ct < GameConfig.BTN_TEXT_MIN_CONTRAST:
			out["bad"].append("%s输入框%s 字/盒 %.2f < %.2f" % [
				tag, label, ct, GameConfig.BTN_TEXT_MIN_CONTRAST])
		# ④ 占位符：色值由 `probe` 读回（判据不自己再 `get_theme_color` 一次 —— 两处各读一次
		#   就有可能读到不同的东西）。量的是**渲染出来的那个量**：占位符色现在是不透明的独立一支，
		#   见 `input_box_placeholder_ink()` 的注（"半透明让断言变假"）。
		var cph: float = GameConfig.contrast_of(pr["ph"], pr["fill"])
		if cph < float(out["worst_ph"]):
			out["worst_ph"] = cph
			out["worst_ph_who"] = tag + label
		if cph < GameConfig.INPUT_PLACEHOLDER_MIN_CONTRAST:
			out["bad"].append("%s输入框%s 占位符/盒 %.2f < %.2f" % [
				tag, label, cph, GameConfig.INPUT_PLACEHOLDER_MIN_CONTRAST])
		# ④b 占位符还必须**明显淡于正文**（否则"提示"与"已输入的内容"长得一样 = 提示失效）。
		#   ★ 这一条是有来历的：改写之前占位符 = `Color(ink, 0.55)`（靠 alpha 变淡），而对比度算的
		#   是 `get_luminance()`、**不看 alpha** ⇒ ③④ 两条印出**同一个读数**（实测 3.57 / 3.57）
		#   ＝ ④ 根本没有独立牙齿，"占位符与正文一样浓"这种坏法永远抓不到。
		#   现在占位符是不透明的独立一支色，"淡"才第一次成为可断言的量（这条判据就是它的牙）。
		if cph >= ct:
			out["bad"].append("%s输入框%s 占位符不比正文淡：占位符 %.2f ≥ 正文 %.2f" % [
				tag, label, cph, ct])
		# ⑤ 盒底/字/占位符三支色都必须逐位等于真源给的（"套上了"与"套对了"是两件事）
		if not (pr["ink"] as Color).is_equal_approx(pr["ink_expect"]):
			out["bad"].append("%s输入框%s 字色 %s ≠ 真源给的 %s" % [
				tag, label, str(pr["ink"]), str(pr["ink_expect"])])
		if not (pr["ph"] as Color).is_equal_approx(pr["ph_expect"]):
			out["bad"].append("%s输入框%s 占位符色 %s ≠ 真源给的 %s" % [
				tag, label, str(pr["ph"]), str(pr["ph_expect"])])
	return out


## 控件属于哪一族"**本体靠引擎默认主题**的图标/样式盒"的原生控件（不属于返回 ""）。
## ★ 返回值必须与 `ThemeDB` 的类型名一致：`GameConfig.native_body_roles()` 拿它当 `Theme` 的查询键。
func _native_body_family(ctrl: Control) -> String:
	if ctrl is CheckBox:
		return "CheckBox"
	if ctrl is CheckButton:
		return "CheckButton"
	if ctrl is HSlider:
		return "HSlider"
	if ctrl is VSlider:
		return "VSlider"
	if ctrl is VScrollBar:
		return "VScrollBar"
	if ctrl is HScrollBar:
		return "HScrollBar"
	return ""


## 本体主题审计（与 `_themed_button_audit()` / `_themed_input_audit()` 同族，射程不同）：
##   ① 走过 `style_theme_native_body()`（元数据在）、② 表面 ∈ 允许集合、
##   ③ 每个引擎图标都**换过**（不是引擎默认那张）、④ 图标色档**逐档**等于真源给的、
##   ⑤ 主档对所在表面 ≥ `BTN_SURFACE_MIN_CONTRAST`（按下/禁用态各另有更低的一档）、
##      副档（勾/手柄）压在**本体**上 ⇒ 按"字压填充"那一档要求（`BTN_TEXT_MIN_CONTRAST`，禁用态另算），
##      且对同类里**所有会当它背景的样式盒底色**也 ≥ `BTN_SURFACE_MIN_CONTRAST`
##      （滑杆手柄骑在轨道与进度条之间 ⇒ 两边都得看得见）、
##   ⑥ 样式盒底色逐位等于真源给的、⑦ 非按下态底色对表面 ≥ 同值（按下态另有一档 `BTN_PRESS_*`）。
## ★★ 为什么量的是**像素与色值本身**、而不是"我调过哪个函数"：样式函数写错（取错色、把档位
##   映射反了）时前者照样红、后者照样绿。这是本工程"判据要读真源 + 量眼睛看到的量"的同一口径。
func _themed_native_body_audit(root: Node, allowed_hosts: Array, tag: String) -> Dictionary:
	var out: Dictionary = {
		"tag": tag, "total": 0, "bad": [], "fam": {},
		"worst_main": 999.0, "worst_main_who": "",
		"worst_dis": 999.0, "worst_dis_who": "",
		"worst_alt": 999.0, "worst_alt_who": "",
		"worst_alt2": 999.0, "worst_alt2_who": "",
		"worst_sb": 999.0, "worst_sb_who": "",
		"icons": 0, "icons_done": 0, "alt2_pairs": 0,
	}
	if root == null or not is_instance_valid(root):
		out["bad"].append("%s：根节点不存在" % tag)
		return out
	var ctls: Array[Control] = []
	GameConfig.collect_controls(root, ctls)
	for c in ctls:
		var fam: String = _native_body_family(c)
		if fam == "":
			continue
		out["total"] = int(out["total"]) + 1
		var fcnt: Dictionary = out["fam"]
		fcnt[fam] = int(fcnt.get(fam, 0)) + 1
		var pr: Dictionary = GameConfig.probe_native_body(c)
		var who: String = "%s%s#%d" % [tag, fam, int(out["total"])]
		if not bool(pr["styled"]):
			out["bad"].append("%s 没走过样式入口（方块/胶囊/轨道/滑块还是引擎默认灰）" % who)
			continue
		var host: Color = pr["host"]
		var hit: bool = false
		for h in allowed_hosts:
			if (host as Color).is_equal_approx(h):
				hit = true
				break
		if not hit:
			out["bad"].append("%s 表面不对：%s（允许 %s）" % [who, str(host), str(allowed_hosts)])
		var roles: Dictionary = pr["roles"]
		for k in roles.keys():
			var key: String = String(k)
			var exp: Array = roles[key]
			if key.begins_with(GameConfig.NATIVE_IC_PREFIX):
				out["icons"] = int(out["icons"]) + 1
				var act: Array = pr["ic"][key]
				if act.is_empty():
					out["bad"].append("%s 图标 %s 没换（还是引擎默认那张）" % [who, key])
					continue
				out["icons_done"] = int(out["icons_done"]) + 1
				for i in mini(act.size(), exp.size()):
					var have: Color = (act[i] as Dictionary)["color"]
					var want: Color = exp[i]
					if absf(have.r - want.r) > 0.01 or absf(have.g - want.g) > 0.01 \
							or absf(have.b - want.b) > 0.01:
						out["bad"].append("%s 图标 %s 第%d档 %s ≠ 真源给的 %s" % [
							who, key, i, str(have), str(want)])
				# 主档：本体得从它所在的表面上看得出来。**三档各一条闸**（静止 1.35 / 按下 1.15 /
				# 禁用 1.10）—— 拿 1.35 去要求禁用态，等于要求"禁用的控件比正常还显眼"，方向反了。
				var dis: bool = key.contains("disabled")
				var cm: float = GameConfig.contrast_of(exp[0], host)
				if dis:
					if cm < float(out["worst_dis"]):
						out["worst_dis"] = cm
						out["worst_dis_who"] = who + "/" + key
					if cm < GameConfig.BTN_DISABLED_MIN_CONTRAST:
						out["bad"].append("%s 图标 %s 禁用档/表面 %.2f < %.2f" % [
							who, key, cm, GameConfig.BTN_DISABLED_MIN_CONTRAST])
					# 相对判据：禁用态必须**比同名的正常态更贴向表面**（"灰下去"而不是"换个颜色"）。
					#   配对名由图标名派生（`checked_disabled` → `checked`）—— 名字来自引擎，不是我们编的。
					var partner: String = key.replace("_disabled", "")
					if roles.has(partner):
						var c_en: float = GameConfig.contrast_of((roles[partner] as Array)[0], host)
						if cm > c_en:
							out["bad"].append("%s 图标 %s 禁用档比正常档更显眼（%.2f > %.2f）" % [
								who, key, cm, c_en])
				else:
					if cm < float(out["worst_main"]):
						out["worst_main"] = cm
						out["worst_main_who"] = who + "/" + key
					if cm < GameConfig.BTN_SURFACE_MIN_CONTRAST:
						out["bad"].append("%s 图标 %s 主档/表面 %.2f < %.2f" % [
							who, key, cm, GameConfig.BTN_SURFACE_MIN_CONTRAST])
				# ① 勾（开关的手柄）压在**本体**上 ⇒ 按"字压填充"那一档要求它
				#    （禁用态单独一档：禁用控件上的勾只要看得出有勾）。
				#    ★ 只在图标**真的有两档**时才有意义（单色图标：方块本来就只有一支色）。
				if exp.size() > 1 and act.size() > 1:
					var bar_alt: float = GameConfig.BTN_DISABLED_TEXT_MIN_CONTRAST if dis \
						else GameConfig.BTN_TEXT_MIN_CONTRAST
					var ca: float = GameConfig.contrast_of(exp[1], exp[0])
					if ca < float(out["worst_alt"]):
						out["worst_alt"] = ca
						out["worst_alt_who"] = who + "/" + key
					if ca < bar_alt:
						out["bad"].append("%s 图标 %s 副档/本体 %.2f < %.2f" % [who, key, ca, bar_alt])
				# ② 手柄骑在同类里**所有会当它背景的样式盒底色**上（滑杆：轨道 + 进度条）
				#    ⇒ 逐个要求 ≥ `BTN_SURFACE_MIN_CONTRAST`。
				#    ★★ 这一条**不能**并进①：① 的前提是"图标有两档"，而手柄是**单色**图标
				#      （实测 1 档）—— 挂在①里面它就永远不跑，读数印成 `999.00()`，
				#      而那正是"有效分母 = 0"的自白（铁律 §106）。⇒ 拆出来独立跑，并把
				#      **跑过几对**计入⑯的样本下限（分母为 0 必须红，而不是印个 999 看着像"没事"）。
				for kb in roles.keys():
					var keyb: String = String(kb)
					if not keyb.begins_with(GameConfig.NATIVE_SB_PREFIX):
						continue
					var bg2: Color = (roles[keyb] as Array)[0]
					if bg2.a <= 0.0 or bg2.is_equal_approx(exp[0]):
						continue
					out["alt2_pairs"] = int(out["alt2_pairs"]) + 1
					var cb2: float = GameConfig.contrast_of(exp[1], bg2)
					if cb2 < float(out["worst_alt2"]):
						out["worst_alt2"] = cb2
						out["worst_alt2_who"] = who + "/" + key + " vs " + keyb
					if cb2 < GameConfig.BTN_SURFACE_MIN_CONTRAST:
						out["bad"].append("%s 图标 %s 副档/样式盒 %s %.2f < %.2f" % [
							who, key, keyb, cb2, GameConfig.BTN_SURFACE_MIN_CONTRAST])
			else:
				var actb: Color = pr["sb"][key]
				var wantb: Color = exp[0]
				if absf(actb.r - wantb.r) > 0.01 or absf(actb.g - wantb.g) > 0.01 \
						or absf(actb.b - wantb.b) > 0.01:
					out["bad"].append("%s 样式盒 %s 底色 %s ≠ 真源给的 %s" % [
						who, key, str(actb), str(wantb)])
				if wantb.a <= 0.0:
					continue     # 透明底（焦点环）：靠描边说话，不参与"面/底"对比
				var cs: float = GameConfig.contrast_of(wantb, host)
				var bar: float = GameConfig.BTN_SURFACE_MIN_CONTRAST
				if key.contains("disabled"):
					bar = GameConfig.BTN_DISABLED_MIN_CONTRAST
				elif key.ends_with("pressed"):
					bar = GameConfig.BTN_PRESS_MIN_CONTRAST
				if cs < float(out["worst_sb"]):
					out["worst_sb"] = cs
					out["worst_sb_who"] = who + "/" + key
				if cs < bar:
					out["bad"].append("%s 样式盒 %s 底/表面 %.2f < %.2f" % [who, key, cs, bar])
	return out


## 给一条"这是哪个控件"的人读线索（一页里几十个 Label，错误信息里光有类名没法定位）。
func _ctrl_text_hint(c: Control) -> String:
	var t: String = ""
	if c is Label:
		t = (c as Label).text
	elif c is Button:
		t = (c as Button).text
	elif c is LineEdit:
		t = (c as LineEdit).placeholder_text
	if t == "":
		t = String(c.name)
	return t.substr(0, 14)


## 字体接线审计（⑰ 用）：把页面里**真在生效的字体**读出来，与字体真源比对。
##   ① 每个带文字的控件（Label / Button / LineEdit）的 `get_theme_font("font")` 必须是
##      `UITheme.body_font()` 或 `UITheme.display_font()`（展示级那几个是**刻意**用楷 Medium 的）；
##   ② 一支都不能是引擎兜底字体 —— "字体没生效"在画面上**只有这一种形态**。
## ★★ 为什么读**控件**而不是读主题常量：`ui_theme.build()` 里绑错类型/绑错项名时，常量断言照样绿。
##   2026-10-15 那件事正是这样：三份字体有两份因为缺 `.import` 而 `exists=false`，**静默**退回引擎
##   兜底字体，两天没人发现 —— 因为当时工程里**没有任何判据读控件上的字体**（`fonts_report()`
##   写好了却零调用点）。这一条就是那个"嘴"。
func _themed_font_audit(root: Node, tag: String) -> Dictionary:
	var out: Dictionary = {
		"tag": tag, "total": 0, "body": 0, "display": 0, "fallback": 0, "offsrc": 0, "bad": [],
	}
	if root == null or not is_instance_valid(root):
		out["bad"].append("%s：根节点不存在" % tag)
		return out
	var ctls: Array[Control] = []
	GameConfig.collect_controls(root, ctls)
	var fb: Font = UITheme.body_font()
	var fd: Font = UITheme.display_font()
	for c in ctls:
		if not (c is Label or c is Button or c is LineEdit):
			continue
		out["total"] = int(out["total"]) + 1
		var f: Font = c.get_theme_font("font")
		if f == null:
			out["bad"].append("%s「%s」%s 读不到字体（null）" % [tag, _ctrl_text_hint(c), c.get_class()])
			continue
		if f == fb:
			out["body"] = int(out["body"]) + 1
		elif f == fd:
			out["display"] = int(out["display"]) + 1
		else:
			out["fallback"] = int(out["fallback"]) + 1
			out["bad"].append("%s「%s」%s 用的是%s —— 主题字体没生效" % [
				tag, _ctrl_text_hint(c), c.get_class(),
				"引擎兜底字体" if f == ThemeDB.fallback_font else "别的字体"])
		# ★★ 独立的第二桶「字体**来源**不是我们的三个文件」（2026-10-15 补）。
		#   为什么上面那个 `f == fb / fd` 的比对**单独不够**：字体缺失时主题压根没绑字体，
		#   而 `UITheme.body_font()` 也退化到引擎兜底 ⇒ **两边同时退化、恒等** ⇒ 这一桶会是 0，
		#   判据看不见"整场 UI 静默降级"（这正是 2026-10-15 那次事故的形态）。
		#   ⇒ 另问一件事：`UITheme.is_theme_font(f)`（查 `resource_path` 是不是我们的字体文件）。
		#   ⚠️ 刻意**不**用 `f == ThemeDB.fallback_font` 当这一桶的判据 —— 试过，假红：
		#     `apply_ui_theme()` 末尾把 `ThemeDB.fallback_font` 换成了我们自己的正文字体
		#     （次要保险）⇒ 字体正常时每个控件都"等于兜底"。详见 `ui_theme.gd::is_theme_font()`。
		if not UITheme.is_theme_font(f):
			out["offsrc"] = int(out["offsrc"]) + 1
			out["bad"].append("%s「%s」%s 的字体不来自我们的字体文件（resource_path=%s）" % [
				tag, _ctrl_text_hint(c), c.get_class(), f.resource_path])
	return out


## `Button` 的**表单型子类**的名字（勾选框 / 下拉 / 取色器 / 菜单钮）；普通按钮返回 ""。
## ★ 单独成函数是为了让"排除表只有一处"—— 判据与将来的样式层都读它（铁律 §18）。
## ⚠️ 名单里**没有** `LinkButton`：它继承的是 `BaseButton` 而**不是** `Button`
##   （写进来会有 `Parse Error: Expression is of type "Button" so it can't be of type "LinkButton"`
##   ⇒ `menu.gd` 整个加载失败 ⇒ 所有自检零输出、进程被 SIGTERM，看着像"挂死"）。
##   反过来说：`collect_buttons_deep()` 按 `is Button` 收，本来也收不到它。
func _form_button_class(b: Button) -> String:
	if b is CheckBox:
		return "CheckBox"
	if b is CheckButton:
		return "CheckButton"
	if b is OptionButton:
		return "OptionButton"
	if b is ColorPickerButton:
		return "ColorPickerButton"
	if b is MenuButton:
		return "MenuButton"
	return ""


## 页面原生按钮的**接线审计**（2026-10-15 T3 的验收工具）：读**控件上真实生效**的值，断四件事
##   ① `themed`：这个按钮真的走过样式入口（元数据 `BTN_META_HOST` 存在）；
##   ② `host ∈ allowed_hosts`：套样式时用的**表面**必须是给定的那几个真源之一 ——
##      "传错表面"（例如漏乘背景明度档）在控件颜色上**看不出来**，只有这一条能咬住；
##   ③ 面：`fill` 对 `host` 的对比度 ≥ `BTN_SURFACE_MIN_CONTRAST`（按钮要从所在的面上浮出来）；
##   ④ 字：`ink` 对 `fill` 的对比度 ≥ `BTN_TEXT_MIN_CONTRAST`（字要在按钮底上读得清）。
## 外加 `corner == GameConfig.DIALOG_CORNER`：圆角是我们那支 stylebox 的**签名** ——
##   引擎默认主题的按钮圆角是 3，于是"只套了字色、盒子还留在引擎默认主题上"这种半吊子接线
##   会被当场认出来（只看颜色的话两者可能碰巧接近 ⇒ 漏判）。
## ★ 跳过两类，且**两类都报数**（否则"全被跳过"与"全都合格"会印成同一行，铁律 §98~100）：
##   ① `flat == true` —— 外观预设色块，它**自己就是配色样本**，自绘、不该套按钮底色；
##   ② **表单型的 `Button` 子类**（勾选框 / 下拉 / 取色器 / 菜单钮）—— 它们不是"按钮"语义，
##      字色走的是页面墨色（`_apply_ink_recursive()`），勾选框本体与滑条属下一步。
##      ⚠️ 用"逐类判 `is`"而不是"只收 `get_class() == "Button"`"：后者是**静默**排除，
##        将来真给某一类接上主题也没人看得出来它被排除在外。
func _themed_button_audit(root: Node, allowed_hosts: Array, tag: String) -> Dictionary:
	var out: Dictionary = {
		"tag": tag, "total": 0, "themed": 0, "flat_skipped": 0,
		"form_skipped": {}, "bad": [],
		"worst_surf": 999.0, "worst_surf_who": "",
		"worst_text": 999.0, "worst_text_who": "",
	}
	if root == null or not is_instance_valid(root):
		out["bad"].append("%s：根节点不存在（页面没建出来？）" % tag)
		return out
	var all: Array[Button] = []
	# ★ 遍历复用 `GameConfig.collect_buttons_deep()`（**不是**在这里再写一份递归）：
	#   两份遍历迟早对不上，"按钮集合"对不上却都自称"全部按钮"（铁律 §70）。
	GameConfig.collect_buttons_deep(root, all)
	for n in all:
		var b: Button = n
		if b.flat:
			out["flat_skipped"] = int(out["flat_skipped"]) + 1
			continue
		var form: String = _form_button_class(b)
		if form != "":
			var sk: Dictionary = out["form_skipped"]
			sk[form] = int(sk.get(form, 0)) + 1
			continue
		out["total"] = int(out["total"]) + 1
		var pr: Dictionary = GameConfig.probe_button_theme(b)
		var label: String = ("「%s」" % b.text) if b.text != "" else ("(无名 %s)" % String(b.name))
		if String(pr["state"]) == "":
			out["bad"].append("%s%s 没走过样式入口（元数据缺失 ⇒ 还是引擎默认主题）" % [tag, label])
			continue
		out["themed"] = int(out["themed"]) + 1
		var host: Color = pr["host"]
		var hit: bool = false
		for h in allowed_hosts:
			if host.is_equal_approx(h):
				hit = true
				break
		if not hit:
			out["bad"].append("%s%s 表面不对：%s（允许 %s）——是不是漏乘了背景明度档？" % [
				tag, label, str(host), str(allowed_hosts)])
		if not is_equal_approx(float(pr["corner"]), GameConfig.DIALOG_CORNER):
			out["bad"].append("%s%s 圆角 %.1f ≠ 我们的 %.1f（盒子不是这支 stylebox 建的）" % [
				tag, label, float(pr["corner"]), GameConfig.DIALOG_CORNER])
		# ★ 盒子底色必须**逐位**等于按那个表面算出来的填充色：这一条咬的是"半路又改了一次颜色"
		#   （例如在套样式之后又手写一个 `add_theme_stylebox_override("normal", …)`）——
		#   那种改法会留下"对比度碰巧还够"的假绿，只有逐位比对看得见。
		if not (pr["fill"] as Color).is_equal_approx(pr["fill_expect"]):
			out["bad"].append("%s%s 底色 %s ≠ 真源给的 %s" % [
				tag, label, str(pr["fill"]), str(pr["fill_expect"])])
		# ③ 面：按钮 vs 它所在的那个面  ④ 字：字 vs 按钮底
		var cs: float = GameConfig.contrast_of(pr["fill"], host)
		if cs < float(out["worst_surf"]):
			out["worst_surf"] = cs
			out["worst_surf_who"] = tag + label
		if cs < GameConfig.BTN_SURFACE_MIN_CONTRAST:
			out["bad"].append("%s%s 面/底 %.2f < %.2f" % [
				tag, label, cs, GameConfig.BTN_SURFACE_MIN_CONTRAST])
		var ct: float = GameConfig.contrast_of(pr["ink"], pr["fill"])
		if ct < float(out["worst_text"]):
			out["worst_text"] = ct
			out["worst_text_who"] = tag + label
		if ct < GameConfig.BTN_TEXT_MIN_CONTRAST:
			out["bad"].append("%s%s 字/底 %.2f < %.2f" % [
				tag, label, ct, GameConfig.BTN_TEXT_MIN_CONTRAST])
	return out


## 自检：--menutest 主菜单重设计（2026-10-02）。
## ★★★ 本条自检的核心纪律：**走真实交互路径** —— 判据点条目一律
##   「查 `_items` 拿 center → `_tile_at_point(p)` 命中 → 调该条目的 `cb`」，
##   **不直呼 `_select_*` / 不先 `_set_page()` 再手工改状态**。
##   理由（menu.md 截图牙齿第 1 条，2026-09-19 踩过整整一轮）：直呼状态函数测的是
##   **状态机**，而真 bug 恰在**接线**上（"点了没反应" / "改了标签没改回调"）
##   ⇒ 那种写法**修 bug 前就是绿的，等于没测这个 bug**。
##   ⇒ 判据：修 bug 前如果这条是绿的，那它没在测这个 bug。
func _menu_layout_self_test() -> void:
	print("[menutest] ===== 主菜单重设计自检（视口 %s）=====" % str(size))
	var checks: Array = []
	# ---- 把「默认页」在**本函数第一件事**抓下来（2026-10-04，阴性对照 K5 逼出来的缺口）----
	# ★★ 为什么必须抢在这里：本函数为了让后面的命中测试有个确定的起点，紧接着就
	#   `_set_page(PAGE_MAIN)`。**在那之后再读 `_page`，读到的是自检自己刚设的值** ⇒ 恒真式。
	#   铁律 13「判据自己注入被测量 ⇒ 接线盲区」：取值点一旦落在被测动作**之后**，
	#   这条判据就只在自己证明自己 —— 而且**不会报任何错**，看起来最像"一直在守着"。
	# ★ 用户看得见的那一半（底栏哪一块亮着）**也要在同一时刻抓**：底栏 `sel` 由 `_page` 派生，
	#   而 `_page` 稍后会被本自检自己改掉 ⇒ 晚一步抓就只剩 ["练习"]（假绿的第二种形态）。
	# ★ 真源链（两处写点，**后者才可观测**）：`var _page: int = PAGE_MAIN`（声明初值）
	#   → `_ready()` 里那句无条件的 `_set_page(PAGE_MAIN)`。程序顺序上后者在后
	#   ⇒ 首帧绘制看到的默认页由它决定；**单独改声明初值不会有任何可见差别**
	#   （K5 首版就是砍在声明初值上 ⇒ 砍不动任何东西，见 negctl_v4 那段注）。
	#   守卫 S66 钉的是"取值点在测试自己切页之前"这个**结构**（顺序错了判据就退化成恒真式）。
	var page_on_entry: int = _page
	var lit_on_entry: Array[String] = []
	for d_e in _footer_entry_descriptors():
		if bool(d_e["sel"]):
			lit_on_entry.append(str(d_e["label"]))
	_sel_board = BOARD_PENROSE
	_sel_size = GameConfig.STANDARD
	_sel_mode = MODE_LOCAL
	# ★★ headless 自检在 `_ready` 里同步跑完就 quit ⇒ `_process` **一次都不会跑**
	#   ⇒ 所有靠 `_process` 缓动的折叠进度（现在只剩 `_board_t`）
	#   全停在初始值。而 `_tile_at_point` 会按"进度 < 0.99 就不响应点击"挡掉这些组
	#   ⇒ 判据会一路报"无候选"，看起来像布局没做出来，**实际是动画没走完**。
	#   既有自检早就踩过同一个坑（`--steamuitest` 里那句「折叠动画必须收完，
	#   否则命中测试按 `_net_t<0.99` 直接跳过」）。这里一次性全部置到位。
	_board_t = 1.0
	_set_page(PAGE_MAIN)          # 自检起点：默认页的取值点必须在**这句之前**（守卫 S66）
	# `_set_page` 会把几个 `_target` 重新按选择算一遍；进度也要跟上，否则又回到 0
	_board_t = 1.0

	# ---- ① 底部一行四入口都在、都可点、且互不重叠 ----
	#   四入口 = 练习 / 棋谱 / 对弈 / 设置（**四个面板都注册同一份**，见
	#   `_footer_entry_descriptors()`）。
	#   ★★ 2026-10-04 v3 改口径：原来是「开始对局 / 棋谱库 / 联机大厅 / 设置」四块 `nav`，
	#      当时**删了一块、改了三块名**，「练习」在**另一个 group**（`quick`，因为它是开关
	#      不是跳页）⇒ 判据不能"只筛 nav"。v4 起四块**全归 `nav`**（都是面板入口），
	#      `_footer_row_items()` 就是"全部 nav"，判据与布局仍读同一个真源。
	#   ★ 为什么用「互不重叠」当判据：菱形/卡片入口挤在一起时**视觉上能看见重叠**，
	#   但命中测试是"第一个命中的 `_items` 顺序"⇒ 点 A 触发 B 的回调，**静默**。
	#   ★ 顺序也一起钉：底部那一行是**用户读得出来的一句话**，顺序变了观感就变了
	#     （而且没有任何几何判据看得见"顺序"）。
	var row_items: Array[Dictionary] = _footer_row_items()
	var row_labels: Array[String] = []
	for it_r in row_items:
		row_labels.append(str(it_r["label"]))
	var want1: Array[String] = ["练习", "棋谱", "对弈", "设置"]
	var c1a: bool = row_labels == want1
	checks.append(["①a 底部一行四入口齐备且次序固定", c1a,
		"实际 %s 期望 %s" % [str(row_labels), str(want1)]])
	# 逐个点：命中测试必须落在**自己那条**上（重叠就会被前面的抢走）
	var hit_mismatch: Array[String] = []
	for it_r2 in row_items:
		var nm: String = str(it_r2["label"])
		var g_r: String = str(it_r2["group"])
		var idx: int = -1
		for i in _items.size():
			if str(_items[i]["label"]) == nm and str(_items[i]["group"]) == g_r:
				idx = i
				break
		if idx < 0:
			hit_mismatch.append(nm + "(缺)")
			continue
		var got: int = _tile_at_point(_items[idx]["center"])
		if got != idx:
			hit_mismatch.append("%s→%s" % [nm, str(_items[got]["label"]) if got >= 0 else "无"])
	var c1b: bool = hit_mismatch.is_empty()
	# ⚠️ 判据名里**不许出现全角括号**（守卫 S26）：阴性对照仪靠 `split("（")[0]` 切
	#   "哪一条红了"，名字里带括号会把 `✗` 一起切掉 ⇒ 报红理由退化成"（无编号判据红）"。
	#   并列项一律用 `｜`。明细（第 3 个字段）里可以照常写括号。
	checks.append(["①b 入口互不重叠｜点谁中谁", c1b, str(hit_mismatch)])

	# ---- ② 「练习」是**面板入口**（v4 起不再是展开/收起开关）----
	# ★★ 口径变化的原因：用户口令「主菜单底栏四按钮固定在主菜单不动，上面的空间用来切换
	#   面板，当前面板作为练习面板」⇒「练习」从"同一页里收起/展开设置区的开关"变成
	#   **一块面板**。旧判据 ②b 量的是 `_quick_t` 两向都走 —— 那套折叠机制已整族删除
	#   （`_toggle_quick_panel()` / `_setup_alpha()`），判据留着就会变成"量一个已经不存在
	#   的量"：恒真式，而且是**最坏的那种**（它长得像在守"练习还能用"）。
	#   ⇒ 改口径：量它**真的切到练习面板**，且**练习面板上设置区真的在位可点**。
	#   ⚠️ "可点"这一半不能省：底栏四块都在 `nav` 组、四个面板都在，
	#   而设置区那几行**只在 PAGE_MAIN 上被建出来** —— 有人改错分派时，"底栏还在"与
	#   "练习面板是空的"都能看出来，但 ①a/①b/⑥b 全绿（它们只问底栏那四块）。
	var practice_idx: int = -1
	for i in _items.size():
		if str(_items[i]["group"]) == "nav" and str(_items[i]["label"]) == "练习":
			practice_idx = i
			break
	var c2a: bool = practice_idx >= 0
	checks.append(["②a 底栏有「练习」面板入口", c2a, "idx=%d" % practice_idx])
	if c2a:
		# ★ 先把回调**取出来**再切页：`_set_page()` 会重建 `_items`，`practice_idx`
		#   在切换之后就指向别的东西了（或越界）—— 拿 Callable 本身不受影响。
		var practice_cb: Callable = _items[practice_idx]["cb"]
		_set_page(PAGE_SETTINGS)          # 先离开练习面板
		practice_cb.call()                # 走**真实回调**（接错时"面板换不了"是静默的）
		var came_back: bool = _page == PAGE_MAIN
		var setup_bad: Array[String] = []
		var want_rows: int = 0
		for i2 in _items.size():
			var g2: String = str(_items[i2]["group"])
			if g2 == "nav":
				# 底栏四块由 ⑥b 逐页量（它们不属于"设置区"），这里排除
				continue
			# ★★ 2026-10-16：棋盘行**不再排除** —— 原先排除它的理由是"它的重影坐标在
			#   `_board_slots` 里，由 ③/⑤ 单独量"。棋盘行改静态平铺后每块只出现一次，
			#   `_items[i2]["center"]` 就是屏上那个点 ⇒ 排除它就等于"棋盘 5 块不验可点"，
			#   而 ③ 只抽验**一块**（挑第一个未选中的）⇒ 剩下 4 块的可点性无人看。
			# ⚠️ 但棋盘行的**禁用占位**（「敬请期待①②」）必须**跳过**：它按设计不参与布局
			#   （见 `_layout_setup()` 收集段），既没有 poly 也不在屏上 ——
			#   拿它去验"可点"只会报两条 `未布局` 的**假红**。
			#   只对 `board` 组豁免：别的组的禁用项（如线上模式下的「开始」）**是要布局的**。
			if g2 == "board" and bool(_items[i2].get("disabled", false)):
				continue
			want_rows += 1
			if (_items[i2]["poly"] as PackedVector2Array).size() < 3:
				setup_bad.append("%s·未布局" % str(_items[i2]["label"]))
				continue
			var hit2: int = _tile_at_point(_items[i2]["center"])
			if hit2 != i2:
				setup_bad.append("%s→%s" % [str(_items[i2]["label"]),
					("无" if hit2 < 0 else str(_items[hit2]["label"]))])
		# ★ 样本非平凡（铁律 13⑨）：`want_rows` 必须是个真实的数 —— 若哪天分派被改坏、
		#   练习面板上一块内容都不建，`setup_bad` 会是空的 ⇒ 这条会**假绿**。
		# ★ 门槛的来历（**每次删行都要跟着改，别让它悄悄变成假绿**）：
		#   · 2026-10-08：删掉「线上 + 两瓣联机方式」⇒ 从 10 降到 8；
		#   · 2026-10-12：删掉「简单/普通/困难」三块难度 ⇒ 非 board/nav 的块变成
		#     **本地 / 人机 + 三大小 + 开始 = 6 块**（实测）。
		#   · 2026-10-13：对战方式加第三块「Ludii」⇒ 6 → 7 块；**同日「彻底砍掉 Ludii」**
		#     ⇒ 7 → **6 块**（回归 2026-10-12 那个 2 块形状）。两次都让本条**当场变红** ——
		#     这正是"精确计数"守的那一半：加行/删行**不许静默**，红了就得把这段一起改。
		#   · 2026-10-14：对战方式加第三块「测试AI」（骨架对手入口，用户口令）⇒ 6 → **7 块**。
		#     当场变红（本条按设计咬住），数字随结构一起更新。
		#   · 2026-10-15b：「人机」改名「磐石」且与「疾风」并列化 ⇒ **块数不变，仍是 7**
		#     （改的是一块瓷砖的 label 与选中口径，不是增删）⇒ 本条**不动**。
		#     这正是"精确计数"守的另一半：改名字不该惊动它。
		#   · 2026-10-16：棋盘行**收进本条**（原先由"槽位"那一族量，槽位已删）⇒ 7 + 棋盘 5 = **12 块**。
		#     变红→按设计更新数字。⚠️ 这一次**不是**"加了一行"，而是"分母补全"：
		#     旧口径下棋盘 5 块里只有 ③ 抽验的那 1 块被验过可点。
		#   · 2026-10-22：对战方式加第四块「流水」（渗流引擎入口）⇒ 12 → **13 块**。
		#     当场变红（本条按设计咬住），数字随结构一起更新。首次加行时跑出了 13 —— 与预期一致。
		#   · 2026-10-23：对战方式加第五块「野马」（神经网络先验引擎入口）⇒ 13 → **14 块**。
		#     当场变红（实测参数 `设置区 14 块`，与 13 的差恰好是那一块），数字随结构一起更新。
		#     ⚠️ 同日又一次验证了"精确计数"的价值：若当初放宽成 `>= 6`，这块新瓷砖
		#       布局失败也**不会**报红。
		#   ⚠️ 这一条**改成了精确计数**（`>= 6` 换成实际值），与上面"留一点余量"的口径相反
		#     —— 理由：块数降到 6 之后"余量"就没有意义了（余量就是"允许少一块"，而少一块
		#     正是本条要抓的那种坏法）。本条守的仍是「**别一块都不建 / 别只建一半**」。
			#     ⇒ 将来再加行：**先看这里红不红**，红了就把数字与这一段一起更新（别放宽）。
		var c2b: bool = came_back and setup_bad.is_empty() and want_rows == 14
		checks.append(["②b 练习面板｜回调切得回来且设置区在位可点", c2b,
			"回到主菜单=%s · 设置区 %d 块 · 异常 %s" % [str(came_back), want_rows,
				str(setup_bad.slice(0, 3))]])

	# ---- ②c 默认/初始那一页就是练习（取值点在函数入口，见 `page_on_entry` 那段注）----
	# ★★ 为什么单列这一条（用户口令第三句「当前面板作为练习面板」的**另一半**）：
	#   ②a/②b 走的是"先离开练习面板、再点『练习』回来" ⇒ 它们验的是**回调对不对**，
	#   对"还没点任何东西时显示哪一页"**完全不敏感**（那由 `_ready` 里那句 `_set_page` 决定）。
	#   实测（阴性对照 K5）：把默认页改成棋谱，**全套 `--menutest` 仍然全绿** ⇒ 这一半当时
	#   没有任何判据。K5 一次报了**两件事**：① 判据缺失（就是这条要补的）；
	#   ② 那把刀的锚点本身选错了（砍在声明初值上 ⇒ 被 `_ready` 那句覆盖 ⇒ 砍不动任何东西）。
	# ★ 两半一起量（铁律 7「一组控件两种含义」）：`_page` 是状态真源（`_draw()` 按它决定
	#   画哪个面板），"哪一块亮着"是**用户唯一看得见**的那一面 —— 只量前者会漏掉
	#   "面板切对了但点亮的是别人"；只量后者会漏掉"点亮对了但画的其实是别的面板"。两种都静默。
	var want_lit: Array[String] = ["练习"]
	var c2c: bool = page_on_entry == PAGE_MAIN and lit_on_entry == want_lit
	checks.append(["②c 默认面板即练习｜点亮的就是练习", c2c,
		"入口页=%d 期望=%d · 点亮=%s 期望=%s" % [page_on_entry, PAGE_MAIN,
			str(lit_on_entry), str(want_lit)]])

	# ---- ③ 展开后棋盘行可点，且**点了真的换棋盘**（接线，非状态机）----
	# ★★ 2026-10-16：点的是 `_items[tgt_item]["center"]`（**屏上那一块的中心**）。
	#   ⚰️ 原先进来时先要求"走**槽位重影坐标**"：棋盘行是**循环行**，同一块砖在屏幕上
	#      有多个重影（`_board_slots`），而 `_items[t]["center"]` 只是"离焦点最近的那次出现"
	#      的**记账锚点**，点它会打到别的块（实测命中 #0）⇒ 症状是"点了没反应"、且**静默**。
	#      用户口令「棋盘选项不需要滚动了，删掉」之后棋盘行是**静态平铺**：每块在屏上
	#      **只出现一次**，`_items[t]["center"]` **就是**绘制/命中用的那个点
	#      ⇒ "锚点 vs 重影"这个差别整个消失，判据必须回到最直接的那条路。
	#   ⚠️ 别把这一改当成"判据放宽"：上面那句 `var base: Vector2 = _items[tgt_item]["center"]`
	#      当年是**故意**写成"锚点 + (槽心 − 锚点)"的（等价于直接用槽心）。现在直接用锚点，
	#      量的仍然是"用户看到并点下去的那一块"——不变的是那条纪律，不是那个中间变量。
	var board_before: int = _sel_board
	# ★★ 量的是 **`_eff_board()`**（用户当前看到的棋盘）而不是 `_sel_board`：
	#   `_select_board()` 走的是**待切换机制** —— 设 `_board_pending`、收回动画，
	#   `_sel_board` 要等 `_commit_board_pending()`（点"开始"或切页）才落定。
	#   这是有意设计（凹陷态立即跟到新块、折叠锚点仍用旧块，见该函数注释）。
	#   ⇒ 判据若读 `_sel_board`，量的是"内部状态"而不是"用户看到的"——
	#   而且会恒红（点了不换），读起来像"接线坏了"，实际是量错了对象。
	var eff_before: int = _eff_board()
	var c3: bool = false
	var c3msg: String = "无可切目标"
	# 找一块**当前没选中**的棋盘（点已选中的块不会改变 `_sel_board` ⇒ 样本平凡）
	# ★★ 字段名是 **`selected`** 不是 `sel` —— `descriptors` 里用 `sel` 写，
	#   进 `_items` 时被映射成 `selected`（见 `for d in descriptors:` 那段）。
	#   读错字段名的症状极隐蔽：**所有项都被当成"未选中"** ⇒ 挑中列表里的第一个
	#   （恰好就是当前选中的那块）⇒ 点它不变 ⇒ 判据永远红，且看不出哪里错。
	var tgt_item: int = -1
	for i in _items.size():
		if str(_items[i]["group"]) == "board" and not bool(_items[i].get("disabled", false)) \
				and not bool(_items[i].get("selected", false)):
			tgt_item = i
			break
	if tgt_item < 0:
		c3msg = "没有未选中的棋盘（样本平凡）"
	else:
		# ★ 静态平铺：这一块在屏上**只出现一次**，它的 `center` 就是命中点
		#   （与 `_draw()` 的画点、`_tile_at_point()` 的判点**同源**）。
		var tgt_pt: Vector2 = _items[tgt_item]["center"]
		var got2: int = _tile_at_point(tgt_pt)
		if got2 >= 0 and not bool(_items[got2].get("disabled", false)):
			(_items[got2]["cb"] as Callable).call()
			c3 = _eff_board() != eff_before
			c3msg = "点 #%d（%s）前=%d 后=%d（_sel=%d pending=%d）" % [
				got2, str(_items[got2]["label"]), eff_before, _eff_board(),
				_sel_board, _board_pending]
		else:
			c3msg = "命中 #%d 不可点" % got2
	checks.append(["③ 展开后换棋盘走真实命中+回调", c3, c3msg])

	# ---- ④ 背景棋盘随选择联动（换棋盘后背景盘形要重画）----
	#   判据读**背景真源**（`_menu_bg_board`），不读"有没有重画"
	#   ——后者在"总是 queue_redraw"时恒真。
	# ★ 比的是 `_eff_board()`：与 ③ 同一个口径（"用户看到的那个"）。
	var bg_after: int = int(_menu_bg_board)
	var eff_after: int = _eff_board()
	var c4: bool = bg_after == eff_after and bg_after != eff_before
	checks.append(["④ 背景棋盘随选择联动", c4,
		"背景=%d 用户看到=%d（切换前 %d）" % [bg_after, eff_after, eff_before]])

	# ---- ④b ★★ 背景旋转：摆幅由**实测盘形**解出、且摆到头覆盖损失在闸内 ----
	#   ★ 为什么这条非有不可：旋转幅度是"氛围"参数，**没有像素判据**（headless 不渲染）
	#     ⇒ 把摆幅写成 60° 之类的常数，屏幕上会看到盘形边界扫进屏幕 / 渐隐圆盘与盘形
	#     错开，而所有既有判据**照样全绿**（它们只看背景画的是哪张盘）。
	#   ★ 量法：`_bg_spin_amp_for()` 是纯几何 ⇒ headless 直接可测。三半都要：
	#       ① 幅度**非零**（否则"加了旋转"是假的，而"转 0°"什么错都不会报）；
	#       ② 幅度对应的覆盖损失 ≤ `BG_SPIN_LOSS`（这才是"边界不会露"的数学保证）；
	#       ③ 幅度**真的随盘形变**（正圆顶到上限 22°、3:1 扁盘被几何闸压到 ≈12°）
	#          —— 少了这半，"写死一个常数"照样全绿。
	#   ⚠️ ①②必须一起：只测①，写死 90° 也绿；只测②，写死 0° 也绿。
	#   ⚠️ 样本必须给**不同长宽比**：首版拿四档视口去量，而 `_bg_rect` 与视口无关
	#     ⇒ 四个样本是同一个数（"看起来量了四档、其实只量了一档"）。
	var spin_bad: Array[String] = []
	var spin_msg: Array[String] = []
	var plates: Array[Vector2] = []
	if _bg_rect.size.x > 0.0 and _bg_rect.size.y > 0.0:
		plates.append(_bg_rect.size)                       # 真源：当前实际在用的盘形
	plates.append(Vector2(900.0, 900.0))                   # 正圆（几何闸发散 ⇒ 该被上限夹住）
	plates.append(Vector2(1200.0, 1000.0))                 # 1.2:1
	plates.append(Vector2(1400.0, 700.0))                  # 2:1
	plates.append(Vector2(1500.0, 500.0))                  # 3:1（几何闸必须咬住）
	var amps_deg: Array[float] = []
	for bsz in plates:
		var aa: float = _bg_spin_amp_for(bsz)
		amps_deg.append(rad_to_deg(aa))
		var big: float = maxf(bsz.x, bsz.y) * 0.5
		var rat: float = minf(bsz.x, bsz.y) * 0.5 / maxf(big, 1.0)
		# 长轴方向上转 θ 后的投影半径 / 未转时的半径 ⇒ 实际覆盖损失
		var proj: float = big * sqrt(maxf(1.0 - (1.0 - rat * rat) * sin(aa) * sin(aa), 0.0))
		var real_loss: float = 1.0 - proj / maxf(big, 1.0)
		spin_msg.append("%.0f:1 幅%.1f° 损%.3f" % [1.0 / maxf(rat, 0.001), rad_to_deg(aa), real_loss])
		if rad_to_deg(aa) <= 0.5:
			spin_bad.append("盘%.0f×%.0f 摆幅≈0（旋转没接上）" % [bsz.x, bsz.y])
		if real_loss > BG_SPIN_LOSS + 0.0005:
			spin_bad.append("盘%.0f×%.0f 损失 %.4f > 闸 %.3f" % [bsz.x, bsz.y, real_loss, BG_SPIN_LOSS])
		if rad_to_deg(aa) > BG_SPIN_MAX_DEG + 0.0001:
			spin_bad.append("盘%.0f×%.0f 摆幅 %.1f° 超上限 %.0f°" % [
				bsz.x, bsz.y, rad_to_deg(aa), BG_SPIN_MAX_DEG])
	# ③ 幅度必须随盘形变（正圆那档被上限夹、3:1 那档被几何闸压）——
	#    这两档相等就说明"幅度与盘形无关"，即写死了。
	if not (amps_deg[1] > amps_deg[4] + 1.0):
		spin_bad.append("正圆 %.1f° 未高于 3:1 的 %.1f°（幅度与盘形脱钩？）" % [
			amps_deg[1], amps_deg[4]])
	# ④ 绘制侧用的那份摆幅必须就是解算器的输出（否则"判据量 A、画 B"）
	if absf(_bg_spin_amp - _bg_spin_amp_for(_bg_rect.size)) > 0.0001:
		spin_bad.append("在用的摆幅 %.3f ≠ 解算值 %.3f" % [
			_bg_spin_amp, _bg_spin_amp_for(_bg_rect.size)])
	var c4b: bool = spin_bad.is_empty()
	checks.append(["④b 背景旋转摆幅由盘形解出且在覆盖闸内", c4b,
		"异常 %d 处 %s ｜ %s" % [spin_bad.size(), str(spin_bad.slice(0, 2)),
			str(spin_msg.slice(0, 3))]])

	# ---- ④c ★ 背景点变换**真的是绕盘心旋转**（不是平移/缩放/没接上）----
	#   ★ 为什么单列：`_draw()` 里那一行 `_bg_xform(p, cc, th, org)` 是"旋转有没有作用到
	#     几何上"的唯一接口。headless 看不见像素 ⇒ 只能测这个**纯函数**本身。
	#   三条一次问清：θ=0 时只有平移；θ≠0 时每点到盘心的距离不变（旋转的充要特征）；
	#   且确实转过了那个角 —— 只测"距离不变"的话，**恒等变换也满足**（平凡样本）。
	#   ⚠️ 算夹角要拿"旋转后的**向量**"（`q1 - org - cc`），不是"旋转后的点" ——
	#     拿点去比会得到 120° 这种离谱值（那正是测量写错、而不是变换写错）。
	var pc := Vector2(100.0, 40.0)
	var cc4 := Vector2(700.0, 400.0)
	var org4 := Vector2(-173.0, -97.0)
	var q0: Vector2 = _bg_xform(pc, cc4, 0.0, org4)
	var q1: Vector2 = _bg_xform(pc, cc4, deg_to_rad(20.0), org4)
	var d0: float = (pc - cc4).length()
	var d1: float = (q1 - org4 - cc4).length()
	var ang: float = absf((pc - cc4).angle_to(q1 - org4 - cc4))
	var c4c: bool = q0.is_equal_approx(pc + org4) \
		and absf(d1 - d0) < 0.001 \
		and absf(ang - deg_to_rad(20.0)) < 0.0005
	checks.append(["④c 背景点变换确为绕盘心旋转", c4c,
		"θ=0差=%.4f 半径差=%.4f 转角=%.2f°（应 20°）" % [
			(q0 - (pc + org4)).length(), d1 - d0, rad_to_deg(ang)]])

	# ---- ⑤ 展开区不越右沿（菱形/卡片几何不许出界）----
	#   ★★ 2026-10-16：棋盘行**改按 `_items` 量**，白名单里补回 `"board"`。
	#     ⚰️ 改前的口径（2026-10-02 修的那一版）：棋盘行是**循环行**，
	#        `_items[i]["poly"]` 存的是「离焦点最近的**那一次出现**」（**记账值**），而可见窗口
	#        只有 `k0−N+1 .. k0` 共 N 格 ⇒ 那个值**允许落在窗口之外**。实测（1152 视口、
	#        `pos=0`、`focus_x=810`、`pitch=160`、`R=51.6`）：`_items["筝形"].poly` 落在 k=2
	#        ⇒ x=1130、右沿 1181 > 1152 当场报红，**而屏幕上那一块根本不在那儿**（真右沿 861.6）
	#        ⇒ 那是一次**假红**，于是白名单把 `"board"` 排除、改由"按槽位平移 poly"来量。
	#     用户口令「棋盘选项不需要滚动了，删掉」之后棋盘行是**静态平铺**：每块只出现一次，
	#     `_items[i]["poly"]` **就是**屏上真几何 ⇒ 记账值这个概念不存在了，
	#     "按槽位平移"那一整段也随之消失。
	#   ⚠️⚠️ 必须把 `"board"` **补回白名单**，不能只是删掉槽位那段：只删的话棋盘行
	#      **一条都不进本判据** ⇒ "5 块平铺出屏"没有任何判据看得见（**静默丢覆盖**，
	#      而判据照样打印 ✓）。这正是当年把 board 排除出去时留下的对偶陷阱。
	var vw: float = size.x
	var over: Array[String] = []
	for it in _items:
		# ⚠️ 2026-10-09：白名单里的 `"diff"` 已去（难度三档并入 `mode` 组）—— 留一个
		#   永不命中的组名，读的人会以为那一行还独立存在。
		#   ★ 守卫 S54 的标记钉着本行**原文**（逐字含 `["board", …]`），已同步改
		#     （命中≠1 即报红，不会静默）。
		if str(it["group"]) not in ["board", "nav", "boardsize", "mode"]:
			continue
		var poly: PackedVector2Array = it["poly"]
		for pp in poly:
			if pp.x > vw + 1.0 or pp.x < -1.0:
				over.append("%s[%s]@%.0f" % [str(it["label"]), str(it["group"]), pp.x])
				break
	var c5: bool = over.is_empty()
	checks.append(["⑤ 展开区不越左右沿｜视口宽 %.0f" % vw, c5, str(over)])

	# ---- ⑤a ★ 入口行标签不叠 ----
	#   ★ 判据量的是"**摆完之后标签不叠**"（复用 `--labeltest` 的那套矩形比对），
	#     而不是"有没有切成 2×2"—— 后者只验了开关，前者才验了求解**真的解决了问题**。
	# ★ 只量"重叠对数"，**不另算行列数** —— 行列数只是实现细节（`_nav_rows` 已是真源），
	#   判据自己再数一遍等于给同一件事第二个定义，将来改一边忘了另一边就静默。
	# ⚠️ 2026-10-04 v3：历史背景（"四入口所在列要让开 boardsize 三瓣散开标签、于是改 2×2"）
	#   已经不存在了 —— 底部行带是**整行通带**（1096px 宽），宽度不再是瓶颈，
	#   实测 `per_row` 恒 = 4。但这条判据**必须留着**：它咬的是"求解器给出的摆法会不会叠"，
	#   而"瓶颈从宽度换成高度"恰好是"换了个参数、同一个失效模式"——换个视口一样能叠。
	_layout_footer_row()
	var nov: int = _nav_label_overlap_count()
	var c5a: bool = nov == 0
	checks.append(["⑤a 底部入口行标签不叠", c5a,
		"重叠 %d 对·行数 %d·字号 %d" % [nov, _nav_rows, _nav_label_fs]])

	# ---- ⑤c ★★ 块与块不许相交（不只是标签！）----
	#   为什么单列：⑤a 只量**标签**矩形，而 2026-10-02 的截图暴露的是**块本身**压住
	#   棋盘行的「彭罗斯」选中块（标签各自不叠、块却叠在一起）。
	#   ⇒ 「标签不叠」与「块不叠」是**两件不同的事**，前者绿不代表后者绿。
	#   ⚠ headless 视口恒 1152×1152（**正方**），而真实基座是 1152×**648**（扁）——
	#   扁视口下横向更挤 ⇒ 这个问题在 headless 单档下**量不出来**（铁律 4）。
	#   ⇒ 这里显式把视口设成扁档再量，测完复原。
	var size_bak2: Vector2 = size
	var hit_pairs: Array[String] = []
	for vp2 in [Vector2(1152.0, 648.0), Vector2(1024.0, 640.0), Vector2(1280.0, 800.0)]:
		size = vp2
		_layout_setup()
		for it_a in _items:
			if str(it_a["group"]) != "nav" or (it_a["poly"] as PackedVector2Array).size() < 3:
				continue
			var ba := Rect2((it_a["poly"] as PackedVector2Array)[0], Vector2.ZERO)
			for pa in (it_a["poly"] as PackedVector2Array):
				ba = ba.expand(pa)
			for it_b in _items:
				if str(it_b["group"]) == "nav" \
						or (it_b["poly"] as PackedVector2Array).size() < 3:
					continue
				var bb2 := Rect2((it_b["poly"] as PackedVector2Array)[0], Vector2.ZERO)
				for pb2 in (it_b["poly"] as PackedVector2Array):
					bb2 = bb2.expand(pb2)
				var ov3: Rect2 = ba.intersection(bb2)
				if ov3.size.x > 0.0 and ov3.size.y > 0.0 and ov3.size.x * ov3.size.y > 8.0:
					hit_pairs.append("%s %s↔%s/%s(%.0f×%.0f)" % [str(vp2),
						str(it_a["label"]), str(it_b["group"]), str(it_b["label"]),
						ov3.size.x, ov3.size.y])
	size = size_bak2
	_layout_setup()
	var c5c: bool = hit_pairs.is_empty()
	checks.append(["⑤c 四入口块不压其它行｜扁视口三档", c5c,
		"相交 %d 处：%s" % [hit_pairs.size(), str(hit_pairs.slice(0, 3))]])

	# ---- ⑤e ★★★ 底部行带的**两条结构不变量**（v3 架构的地基）----
	#   ① 入口行（nav/quick）的墨迹 ⊆ 底部行带；
	#   ② 底部行带 ∩ **内容行**墨迹 = ∅。
	#   两条合起来 ⇒「入口行压住内容」**结构性不可能**（不是"试出来刚好"）。
	#   ★★ 为什么 ⑤c 一个人不够：⑤c 量的是**结果**（此刻这两堆块有没有相交），
	#     而簇被 `_nav_place` **贴行带上沿**摆 ⇒ 行带"长上来"也未必立刻相交
	#     ⇒ ⑤c 会全绿而地基已经坏了（实测 MT5 的第一版正是这样）。
	#     ⇒ "量派生结果"与"守结构"必须两层都有（铁律 4 的射程那条）。
	#   ★★★ 2026-10-04 v3：这条判据在**同一个失效模式下换了个方向**，所以留着而不是重写：
	#     · v2 的 ② 近乎恒真（`_header_band()` 自己就是读内容墨迹算的 ⇒ 谁也没法违背它）；
	#       它咬的是"有人把下沿换成常数/别的量"（对照刀 MT5 与守卫 S50）。
	#     · v3 的 ② **真的有牙齿**了：底部行带由 `FOOT_BAND_H` 定死，而内容行的 `bottom0`
	#       必须去**读**它（`_layout_setup()` 的第一行）—— 有人把 `bottom0` 改回
	#       `size.y - BOTTOM_MARGIN - 6` 就会让内容墨迹**真的**切进底带 ⇒ ② 立刻红。
	#       ⇒ 同一个不变量，v3 的射程比 v2 宽（v2 靠"结构性"，v3 靠"参数一致"）。
	#     · "块真的没压上去"仍由 ① 与 ⑤c 各自**独立**地咬 —— 三处分工写清楚，别互相顶班。
	var size_bak5: Vector2 = size
	var band_bad: Array[String] = []
	for vp5 in [Vector2(1152.0, 648.0), Vector2(1024.0, 640.0), Vector2(1280.0, 800.0), size_bak5]:
		size = vp5
		_layout_setup()
		var fb5: Rect2 = _footer_band()
		for it5 in _items:
			var g5: String = str(it5["group"])
			var pl5: PackedVector2Array = it5["poly"]
			if pl5.size() < 3:
				continue
			var ir5: Rect2 = _pass_ink_rect(it5, it5["center"], pl5, _draw_fs_for(it5), true)
			if g5 == "nav":
				# ① 簇墨迹必须整个落在行带里（±0.5 容差：标签上沿与带顶是同一个算式推的）
				if ir5.position.y < fb5.position.y - 0.5 or ir5.end.y > fb5.end.y + 0.5 \
						or ir5.position.x < fb5.position.x - 0.5 \
						or ir5.end.x > fb5.end.x + 0.5:
					band_bad.append("%s 簇出带「%s」带=%s 墨=%s" % [str(vp5),
						str(it5["label"]), str(fb5), str(ir5)])
				continue
			# ② 内容行墨迹不许被行带切到
			var ov6: Rect2 = fb5.intersection(ir5)
			if ov6.size.x > 0.0 and ov6.size.y > 0.0:
				band_bad.append("%s 带切内容「%s」%.0f×%.0f" % [str(vp5),
					str(it5["label"]), ov6.size.x, ov6.size.y])
	size = size_bak5
	_layout_setup()
	var c5e: bool = band_bad.is_empty()
	checks.append(["⑤e 底部入口行在带内且带不切内容｜架构地基", c5e,
		"违反 %d 处 %s" % [band_bad.size(), str(band_bad.slice(0, 3))]])

	# ---- ⑤b ★ 底栏既是"按钮"又是"面板指示器"（一组控件两种含义，铁律 7）----
	#   为什么这条必须重写（旧 ⑤b 量的是"收起不可点 / 展开可点"）：用户口令「底栏四按钮
	#   **固定**在主菜单不动，上面的空间用来**切换面板**」⇒ 折叠机制整族删除，
	#   `_quick_t` 已经没有任何生产者。旧判据留着就是**量一个不存在的量**（恒真式，
	#   而且是最坏的那种：它长得像还在守"练习能不能用"）。
	#   ⇒ 改口径：这四块砖的 `sel`（凹陷态）与 `cb`（换面板）**必须从同一个 `_page` 派生**。
	#   `sel` 若写成常量 false、或写死某一项，症状是"看不出自己在哪个面板"—— 而屏幕上
	#   一切正常、①a/①b/对错全绿（它们只问标签与命中），只有用户觉得迷路。
	#   ★★ 期望值**不另写一份 page↔标签 映射表**（那才是"判据自己注入被测量"）：
	#   独立于实现的期望是 —— **亮着的那一块，点它不该换面板**（它就是这个面板的入口）。
	#   两向都量（在练习 / 棋谱 / 设置三个面板各问一次），否则"恒 sel=true"也能过。
	var sel_bad: Array[String] = []
	var sel_samples: int = 0
	for pgs in [PAGE_MAIN, PAGE_RECORDS, PAGE_SETTINGS]:
		_set_page(pgs)
		sel_samples += 1
		var on: Array[int] = _nav_lit_indices()    # 量法唯一真源（见该函数）
		if on.size() != 1:
			sel_bad.append("第%d面板亮 %d 块（应恰好 1）" % [pgs, on.size()])
			continue
		var lit: int = on[0]
		var lit_cb: Callable = _items[lit]["cb"]
		lit_cb.call()
		if _page != pgs:
			sel_bad.append("第%d面板亮的「%s」点下去却跳到第%d面板" % [
				pgs, str(_items[lit]["label"]), _page])
		_set_page(pgs)
	_set_page(PAGE_MAIN)
	var c5b: bool = sel_bad.is_empty() and sel_samples == 3
	checks.append(["⑤b 底栏恰好一块亮着｜且指出当前面板", c5b,
		"样本 %d 个面板 · 异常 %s" % [sel_samples, str(sel_bad)]])

	# ---- ⑤b2 ★★ 换棋盘**刷新之后**底栏仍恰好一块亮着（2026-10-16 用户报的真 bug）----
	#   病灶：`_refresh_selection()` 的 `match` 原先**没有 `"nav"` 臂** ⇒ 底栏四块的
	#     `selected` 被无条件写成 false ⇒ **点一下棋盘**（`_select_board()` 末尾就调它）
	#     凹陷态就从「练习」上消失 —— 用户原话：「主菜单切换棋盘刷新后"练习"的已选状态会取消」。
	#   ★★ 为什么 ⑤b 抓不到它（这条判据存在的**唯一理由**）：⑤b 走 `_set_page()`，
	#     而 `_set_page()` 是**重建**条目 ⇒ 它读到的是**建项处**的 `sel`，而建项处一直是对的。
	#     坏的只有"**运行期重新派生**"这一路 —— 与 2026-10-09 `diff` 那一臂同一个坑（第三次）。
	#   ★ 走**真实交互路径**：点一块别的棋盘（`_select_board()` → `_refresh_selection()`），
	#     不直呼 `_refresh_selection()` —— 直呼的话"`_select_board()` 哪天不再调它"这条断开
	#     就没人看得见（铁律：判据必须经过真实入口）。前面那次直呼只作"派生臂在不在"的单验。
	#   ★ 期望值**不另写一份映射表**（同 ⑤b 的口径）：独立于实现的期望是 ——
	#     换完棋盘，亮着的仍然**恰好一块**，且它**就是「练习」**（面板压根没换过）。
	#   ★ 本判据要**真的改一次选择** ⇒ 跑完必须原样还回去（后面的判据都跑在原来的棋盘上）；
	#     快照点放在**真正改选择之前**（那时 `_set_page()` 已经落定过 `_board_pending`）。
	var ref_bad: Array[String] = []
	var ref_samples: int = 0
	var alt_b: int = -1
	for kb in BOARD_KINDS:
		if bool(kb["enabled"]) and int(kb["id"]) != _eff_board():
			alt_b = int(kb["id"])
			break
	if alt_b < 0:
		# 有效分母 = 0 必须报红（铁律 §106）：找不到"另一块启用的棋盘"就**不是通过**
		ref_bad.append("找不到「当前选中之外」的启用棋盘 ⇒ 本判据没有样本")
	else:
		_set_page(PAGE_MAIN)                 # 保证在练习面板上（亮块应当是「练习」）
		_refresh_selection()                 # ① 直呼一次：单验"派生臂在不在"
		ref_samples += 1
		var n1: int = _nav_lit_indices().size()
		if n1 != 1:
			ref_bad.append("刷新后底栏亮 %d 块（应恰好 1）" % n1)
		var sb_save: int = _sel_board
		var bp_save: int = _board_pending
		var bt_save: float = _board_target
		_select_board(alt_b)                 # ② 真实路径：点另一块棋盘
		ref_samples += 1
		var lit2: Array[int] = _nav_lit_indices()
		var lbl2: String = str(_items[lit2[0]]["label"]) if lit2.size() == 1 else ""
		if lit2.size() != 1 or lbl2 != "练习":
			ref_bad.append("换到「%s」后底栏亮 %d 块（亮的是「%s」，应恰好 1 块且是「练习」）" % [
				_board_label(alt_b), lit2.size(), lbl2])
		_sel_board = sb_save                  # 还原选择（连同折叠目标）——不漏状态给后面
		_board_pending = bp_save
		_board_target = bt_save
		_refresh_selection()
	var c5b2: bool = ref_bad.is_empty() and ref_samples == 2
	checks.append(["⑤b2 换棋盘刷新后底栏仍恰好一块亮着", c5b2,
		"样本 %d 次刷新 · 异常 %s" % [ref_samples, str(ref_bad)]])

	# ---- ⑥ 页面系统：四个页面都能进，且每页的入口**真的摆好了、点得到** ----
	#   ★ ⑥a 量的是"**页面常量与分派都在**"——若只加了常量没加分派，页面进不去，
	#     而首页判据照样全绿（同"新增的分支没被走到"）。
	#   ★★ ⑥b 量的是**新页那一类静默缺陷**，本轮实测踩到过一个，**没有任何报错**：
	#     新页（棋谱库 / 联机大厅）只切页、没跑 `_layout_setup()` ⇒「返回」块 `poly` 为空
	#     ⇒ **既不画也点不到** ⇒ 页面形同死胡同。
	#     这个错**不会**被"页面进不进得去"发现：`_page` 对、`_items` 里那条记录也在。
	#     ⚰️ 原先 ⑥b/⑥c 还合守另一半「`_set_page()` 清了 `_items` 却没清那串下标链」
	#        （病灶：`_board_slots` 存的是 `_items` 的下标 ⇒ 切页后 `_draw()` 每帧越界）。
	#        那串链随「棋盘选项不滚动」整族删除 ⇒ ⑥c 退役（见它的墓碑），
	#        这一半改由 struct_guard 的 FORBID **S54c** 禁止回潮。
	#   ★★★ ⑥b 还必须走**闸口**（`_tile_hit_for_click`）而不是直呼 `_tile_at_point`：
	#     `_input` 里原有的 `if _page != PAGE_MAIN: return` 会把这两页的瓷砖点击一并挡掉
	#     ⇒ 那块**看得见、点不动**。直呼 `_tile_at_point` 的判据对此**全绿**（盲区）。
	#     铁律：判据必须跑真实交互路径；闸口在哪，判据就必须经过哪。
	var pages_all: Array[int] = [PAGE_MAIN, PAGE_SETTINGS, PAGE_RECORDS, PAGE_LOBBY]
	var pages_ok: Array[String] = []
	var not_laid: Array[String] = []
	var not_hit: Array[String] = []
	for pi in pages_all:
		_set_page(pi)
		if _page != pi:
			continue          # 分派断了：由 ⑥a 报
		pages_ok.append(str(pi))
		# ⚰️ 2026-10-16 墓碑（编号不复用）：「⑥c 切页后槽位下标仍在范围内」整条退役。
		#   原文 = 「`_board_slots` 里每个 `i` 必须落在本页 `_items` 的下标范围内」
		#   （病灶：棋盘行那串**下标链**只在棋盘行的布局里被重填，切页时没人赋值 ⇒
		#     `_draw()` 里 `_items[int(s["i"])]` 每帧刷 `Out of bounds`，46 条/张截图）。
		#   `_board_slots` 随「棋盘选项不滚动」整族删除 ⇒ **下标链本身不存在**，
		#   没有对象可量。⚠️ 不要改成"对空集合恒真"的判据 —— 那是没测（铁律 4）。
		#   ⚠️ 回潮由 struct_guard 的 FORBID **S54c** 禁止（比留一条空判据硬）。
		# ① 本页自己的入口（`nav`）必须 `poly` 非空、且**点得到自己**
		for i in _items.size():
			var g6: String = str(_items[i]["group"])
			if g6 != "nav":
				continue
			# 内容行（board/boardsize/mode/action）的判据在 ①~⑤，
			# 这里只管新页那类"整行都没布局"的错 —— 各组的分工写清楚，免得重复报。
			var pl6: PackedVector2Array = _items[i]["poly"]
			if pl6.size() < 3:
				not_laid.append("第%d页「%s」" % [pi, str(_items[i]["label"])])
				continue
			var hit6: int = _tile_hit_for_click(_items[i]["center"])
			if hit6 != i:
				not_hit.append("第%d页「%s」→%s" % [pi, str(_items[i]["label"]),
					("无" if hit6 < 0 else str(_items[hit6]["label"]))])
	var c6a: bool = pages_ok.size() == pages_all.size()
	checks.append(["⑥a 页面分派可达｜%d/%d 页" % [pages_ok.size(), pages_all.size()], c6a,
		"可达 %s" % str(pages_ok)])
	var c6b: bool = not_laid.is_empty() and not_hit.is_empty()
	checks.append(["⑥b 每页入口都摆好且点得到", c6b,
		"未布局 %d 处 %s · 点错 %d 处 %s" % [not_laid.size(), str(not_laid.slice(0, 2)),
			not_hit.size(), str(not_hit.slice(0, 2))]])
	# ⑥d ★★ 底栏"固定不动"：四个面板上这四块必须**逐块同位置、同标签、同顺序**。
	#   ★★ 这条是本轮用户口令「底栏四按钮**固定**在主菜单不动，上面的空间用来切换面板」
	#      的**直接判据**。为什么必须单列：四个面板各自都在 `_set_page()` 里建自己那份
	#      `_items` —— 若谁把底栏写成"每页各写四行"，那么"改一页忘三页"只表现为
	#      "这个面板的底栏长得不一样"，而**每个面板内部都是自洽的**：①a（标签与顺序对）、
	#      ①b（点得到自己）、⑤e（在自己那条带里）全都照样绿。
	#   ⇒ 判据必须**跨面板比**：同一块砖在四个面板上的中心与包围盒都要一致（0.5px 容差）。
	#   ⚠️ 样本数入判据（铁律 13⑨）：`foot_samples` 必须 = 面板数 × 4 ——
	#      否则"比了个空集"（比如底栏一块都没建）也会是绿的。
	var foot_ref: Dictionary = {}          # 标签 → {c: 中心, bb: 包围盒}
	var foot_bad: Array[String] = []
	var foot_samples: int = 0
	for pf in pages_all:
		_set_page(pf)
		var fit: Array[Dictionary] = _footer_row_items()
		if fit.size() != 4:
			foot_bad.append("第%d面板底栏 %d 块（应 4）" % [pf, fit.size()])
			continue
		for itf in fit:
			var lbl: String = str(itf["label"])
			var plf: PackedVector2Array = itf["poly"]
			if plf.size() < 3:
				foot_bad.append("第%d面板「%s」未布局" % [pf, lbl])
				continue
			var bbf := Rect2(plf[0], Vector2.ZERO)
			for ppf in plf:
				bbf = bbf.expand(ppf)
			foot_samples += 1
			if not foot_ref.has(lbl):
				foot_ref[lbl] = {"c": Vector2(itf["center"]), "bb": bbf}
				continue
			var ref: Dictionary = foot_ref[lbl]
			var rbb: Rect2 = ref["bb"]
			if (Vector2(ref["c"]) - Vector2(itf["center"])).length() > 0.5 \
					or absf(rbb.position.x - bbf.position.x) > 0.5 \
					or absf(rbb.position.y - bbf.position.y) > 0.5 \
					or absf(rbb.size.x - bbf.size.x) > 0.5 \
					or absf(rbb.size.y - bbf.size.y) > 0.5:
				foot_bad.append("「%s」在第%d面板位置变了（心 %s vs %s）" % [
					lbl, pf, str(itf["center"]), str(ref["c"])])
	var c6d: bool = foot_bad.is_empty() and foot_samples == pages_all.size() * 4
	checks.append(["⑥d 底栏四块在四个面板上同位置同标签", c6d,
		"样本 %d 块 · 异常 %s" % [foot_samples, str(foot_bad.slice(0, 3))]])

	# ---- ⑥e ★ 点底栏真的切到对应面板（接线，非几何）----
	#   ★ 与 ⑥d 的分工：⑥d 量"四个面板的底栏长得一样"，这里量"点了之后面板真的换了"。
	#     两者是**两件事** —— `cb` 没接上时 ⑥d 照样绿（位置对、标签对，就是按了没反应）。
	#   ★ 为什么直呼 `cb` 而不合成真事件喂 `_input`：见 `_tile_hit_for_click()` 的说明
	#     （`_input` 里 `await` 之后才调 `cb`，自检跟过去会把 `quit()` 一起挂掉）。
	#   ★★ 期望值**不另写一份 page↔标签 映射表**（那才是"判据自己注入被测量"）：
	#     独立于实现的期望是两句话 —— ① **亮着的那块点下去不该换面板**（它就是这个
	#     面板的入口）；② **点别的块必须真的离开**（否则"接了个空回调"也能过）。
	var sw_bad: Array[String] = []
	var sw_seen: int = 0
	for ps in pages_all:
		_set_page(ps)
		var lit_i: int = -1
		for i_s2 in _items.size():
			if str(_items[i_s2]["group"]) == "nav" and bool(_items[i_s2]["selected"]):
				lit_i = i_s2
				break
		if lit_i < 0:
			sw_bad.append("第%d面板没有亮着的底栏块" % ps)
			continue
		sw_seen += 1
		var lit_cb: Callable = _items[lit_i]["cb"]
		lit_cb.call()
		if _page != ps:
			sw_bad.append("第%d面板点自己那块却跳到 %d" % [ps, _page])
		_set_page(ps)
		var moved: bool = false
		for i_s3 in _items.size():
			if str(_items[i_s3]["group"]) != "nav" or i_s3 == lit_i:
				continue
			var cb_s: Callable = _items[i_s3]["cb"]
			cb_s.call()
			if _page != ps:
				moved = true
				break
		if not moved:
			sw_bad.append("第%d面板点别的底栏块没有任何反应" % ps)
	_set_page(PAGE_MAIN)
	var c6e: bool = sw_bad.is_empty() and sw_seen == pages_all.size()
	checks.append(["⑥e 点底栏真的切面板｜点自己不动·点别的必动", c6e,
		"样本 %d 面板 · 异常 %s" % [sw_seen, str(sw_bad)]])

	# ---- ⑧ 子页空态提示：该有的页要有，且不许压住头部行带 / 入口块 ----
	#   ★ 为什么这条要存在：占位页的"空"是**看不见的** —— 它不报错、不越界、前面几条全绿，
	#     只是用户看到一片空白，分不清"功能还没做"与"这里坏了"。
	#   ★ 与 ⑥b 的分工：⑥b 量"入口块摆好了且点得到"，这条量"提示文字自己有没有越界"。
	#     ⚠️ 位置若在判据里另算一遍（比如自己写 `size.y * 0.5`），就是"判据自己注入被测量"
	#     —— 把那行挪走判据照样绿。这里一律读 `_empty_hint()` 那份真源。
	#   ★ 必须**多档视口**量：头部行带的下沿是内容墨迹推出来的，而新页没有内容墨迹
	#     ⇒ 两档（正方/扁）下都可能不同（这正是本轮"返回块飘到屏幕中部"的病灶）。
	#   ★ 样本数也入判据：`hint_seen.size() == 4`（2 档 × 2 页）—— 若哪天 `_empty_hint()`
	#     恒返回 `{}`，"提示都不压东西"就成了**平凡样本**（铁律 13⑨），必须会红。
	var hint_bad: Array[String] = []
	var hint_seen: Array[String] = []
	var size_bak8: Vector2 = size
	var rec_idx_bak8: Array = _rec_idx
	for vp8 in [size_bak8, Vector2(1152.0, 648.0)]:
		size = vp8
		for pi8 in pages_all:
			_set_page(pi8)
			# ★ 2026-10-09：`_set_page(PAGE_RECORDS)` 会 `_rec_load()` 读**共享自检盘**，
			#   那里面可能躺着别的自检留下的样本（实测 1272 条）⇒ "空库提示"被误判成"有谱不提示"。
			#   本条要验的是**空态提示的落位**（不出屏 / 不压底带 / 不压入口块），与库里到底有没有谱
			#   无关 ⇒ 量之前先把索引置空，量完再还原（"有谱则不提示"那半由 `--rectest` ②b 守）。
			_rec_idx = []
			var want8: bool = pi8 == PAGE_RECORDS
			# ★★ 2026-10-08：`PAGE_LOBBY` 从"该有空态提示"名单里**移出** —— 它不再是占位页：
			#   页内容由 `_build_duel_ui()` 建（`_duel_root`），见 `_duel_page_test()`。
			#   ⇒ 口径改成两条：① 该有提示的页（棋谱）必须有；② 不该有的页一个都不许有；
			#     ③ 对弈页另加**阳性断言**：页根真的建出来了 —— 否则"没内容也没提示"
			#        这种两空状态会静默通过（旧口径正是这么放它过去的）。
			if pi8 == PAGE_LOBBY and _duel_root == null:
				hint_bad.append("%s 对弈页没有页根（既无内容也无提示）" % str(vp8))
			var h8: Dictionary = _empty_hint()
			if h8.is_empty():
				if want8:
					hint_bad.append("%s 第%d页缺空态提示" % [str(vp8), pi8])
				continue
			if not want8:
				# 口径漂了：不该有的页也有了 ⇒ 也报出来（否则"多出来的"没人管）
				hint_bad.append("%s 第%d页多出空态提示" % [str(vp8), pi8])
				continue
			hint_seen.append("%s:%d" % [str(vp8), pi8])
			var hr: Rect2 = h8["rect"]
			if hr.position.x < 0.0 or hr.position.y < 0.0 \
					or hr.end.x > vp8.x or hr.end.y > vp8.y:
				hint_bad.append("%s 第%d页提示出屏 %s" % [str(vp8), pi8, str(hr)])
			var ovb: Rect2 = hr.intersection(_footer_band())
			if ovb.size.x > 0.0 and ovb.size.y > 0.0:
				hint_bad.append("%s 第%d页提示压底带 %.0f×%.0f" % [str(vp8), pi8,
					ovb.size.x, ovb.size.y])
			for i8 in _items.size():
				var g8: String = str(_items[i8]["group"])
				if g8 != "nav":
					continue
				var pl8: PackedVector2Array = _items[i8]["poly"]
				if pl8.size() < 3:
					continue
				# 与 ⑥b 同口径：块的**墨迹**（块 + 标签），不是光秃秃的多边形
				var bi8: Rect2 = _pass_ink_rect(_items[i8], _items[i8]["center"], pl8,
					_draw_fs_for(_items[i8]), true)
				var ovh: Rect2 = hr.intersection(bi8)
				if ovh.size.x > 0.0 and ovh.size.y > 0.0:
					hint_bad.append("%s 第%d页提示压「%s」%.0f×%.0f" % [str(vp8), pi8,
						str(_items[i8]["label"]), ovh.size.x, ovh.size.y])
	size = size_bak8          # ⚠️ 扫多档后必须复原（与 ⑤c 同纪律）
	_rec_idx = rec_idx_bak8   # 复原被置空的索引（见循环顶部那段注）
	_set_page(PAGE_MAIN)
	# ⚠️ 样本数 = 2（**该有提示的页只剩棋谱** × 2 档视口）：恒空的样本集会让这条判据**恒真**
	#   （铁律 13⑨）。对弈页从名单移出后这里必须同步 —— 否则它会因为少了两个样本而恒红。
	var c8: bool = hint_bad.is_empty() and hint_seen.size() == 2
	checks.append(["⑧ 子页空态提示在位且不压底带/入口块", c8,
		"样本 %d 处 · 异常 %d 处 %s" % [hint_seen.size(), hint_bad.size(),
			str(hint_bad.slice(0, 3))]])

	# ---- ⑨（**已删**）----
	#   这里原有「设置页右上角「返回」棋盘按钮：门槛 + 命中形状 + 接线」一整条判据。
	#   ★★ 2026-10-04 v4 随那块按钮**整族删除**（用户口令「设置选项挪过来之后删掉设置页的
	#   返回按钮」）—— 判据的对象没了。
	#   ⚠️ 为什么"留一条恒真的 ⑨"是错的：那会让下一个人以为这个角落还有东西要守；
	#   而那块的**职责（回去）现在归底栏「练习」**，由 ⑥d（四页同位置）+
	#   ⑥e（点它真的换面板）+ ⑤b（凹陷态指出当前面板）三条一起守。
	#   编号**不回收**：留个空号比"用 ⑨ 装别的东西"好 —— 后者会让历史日志与
	#   阴性对照表里的"⑨"指两件事。

	# ---- ⑩ 瓷砖的「凹凸立体感」几何：凸起 / 凹陷只是同一套几何的两个朝向 ----
	#   ★★ 2026-10-12 用户口令「立体感按钮，已选时有凹进去的感觉」+「已选按钮不要变黑，
	#     会看不清字」⇒ 本族**整族替换**了原先的「落子 / 提子黑砖动画」：
	#       · ⑩a / ⑩b / ⑩e / ⑩f **整族删除**（黑砖没了，那两条曲线与它的画序依据一起没了）；
	#       · ⑩c / ⑩d **保留编号、换被测物**（侧壁 → 厚边；抬高量 → 厚边的尺度）；
	#       · ⑩h / ⑩k 是本轮新增的两条（形状 / 字色）。
	#   ⚠️ 编号**不回收**（铁律 §18）：空号留墓碑 —— 否则历史日志与阴性对照表里的
	#      「⑩a」会指两件事。
	#
	# ---- ⑩a（**已删**）----
	#   原文 = 「落子起手=抬起+预览透明度｜落定=归位+满实心」，量 `_stone_drop_state()`
	#   （`1-tt²` 加速下落 + 透明度线性涨到实心，与对局盘 `_place_drop_state()` 同源）。
	#   ★ 它当年钉出的两条方法论**留在这里别丢**：
	#     ① 两条判据的**红项清单必须互不重叠** —— 一把刀只允许打红一条；
	#     ② **判据的对照量不许取自另一条判据的被测物**（⑩b 的那个高度必须读真源
	#        `_stone_drop_h()`；读 ⑩a 的产物 `ds0["off"]` 会让一把刀打红两条，
	#        读起来像"一处改动坏了两个地方"，从此再也分不出是哪条曲线坏了）。
	#
	# ---- ⑩b（**已删**）----
	#   原文 = 「提子升空=落子起手高度｜半途≥40%｜1/4 处非落子曲线」，量 `_stone_fade_state()`。
	#   ★ 一条**勘误**（与 `_stone_fade_state` 墓碑里那条同源，**别丢**）：`1-(1-t)²` 与
	#     `1-t²` 的自变量换元后**逐点相同**（t=0.25 都是 0.4375、t=0.5 都是 0.75）——
	#     旧注释里那句「不是时间反演」把**理由写反了**（结论是对的）。
	#     ⇒ 教训：注释里的推导也要验算（它不像代码会被判据咬，写错就永远错着）。
	#   ★ 一条方法论：**只量"半途 ≥40%"抓不到"两条曲线写反"** —— 它们在 t=0.5 恰好相等
	#     ⇒ 必须另取一个**非对称采样点**（那里取 0.25）。这是"平凡样本"那族坑的标准解法。
	#
	# ---- ⑩e（**已删**）----
	#   原文 = 「离位黑砖最后画｜依据=会压到别人的砖」，量的是"抬起 30px 的砖压住了谁"。
	#   黑砖不再离位 ⇒ 那条画序（攒起来 → 收尾画）连同"依据还在不在"一起消失。
	#   ★ 它死守过的一条纪律仍在生效、只是换了位置：**判据只断能断的那一半** ——
	#     "绘制时到底调了谁"在 headless 下看不见（不渲染），那一半永远只能交给结构守卫
	#     （见 struct_guard.py 的 S95「黑砖族符号不许回潮」）。
	#   ★ 还有一条**反直觉的写法**值得留：它的断言方向是「**压到了**才需要这条规则」，
	#     不是「不许压」—— 后者是一条**永远红**的判据，下一站就是被人删掉或放宽，
	#     于是真正的依据再也无人看着。

	# ---- ⑩c 厚边（凸起态的"厚度"）：几何与**这一笔的 poly** 逐点对齐，off=0 时自动退化 ----
	#   ★ 被测物从 `_stone_side_walls()` 换成 `_tile_side_walls()`（同一个实现改了名），
	#     用途只剩一个静态的：凸起态从砖下沿往下长出来的那截厚度（`off` 由
	#     `_tile_relief_depth()` 给出）。
	#   ★★ 三条缺一不可：
	#     ① **逐点对齐**：厚边的顶边 = 砖边 + off、底边 = 砖边**原样** —— 保证"厚度是从
	#        这一笔自己的轮廓长出来的"，而不是另造一条（另造 ⇒ 换形状时与面错位，静默）；
	#     ② **off=0 自动退化**（面积用鞋带公式量，不靠"看起来没有"）：它是"不需要额外判
	#        '没厚度就不画'"这个设计的全部依据；
	#     ③ **边色从面色派生、且 alpha 逐字跟着面走** —— 换主题 / 循环行两端淡入淡出时
	#        边必须一起淡，否则剩下一圈"没有面的边"（**看得见**的错）。
	#   ⚠️ 样本是**假砖**（R=50 的胶囊）：这几条量的是几何与配色本身；用真砖会把
	#     "几何对不对"和"布局对不对"两件事缠在一起（真砖的尺度由上界守，见 ⑩d）。
	var c_bad: Array[String] = []
	var pp2: PackedVector2Array = _make_btn_rect(Vector2.ZERO, 50.0)
	var off_probe := Vector2(0.0, -17.0)
	var walls: Array = _tile_side_walls(pp2, off_probe)
	if walls.size() != pp2.size():
		c_bad.append("厚边面数 %d ≠ 边数 %d" % [walls.size(), pp2.size()])
	else:
		for k in walls.size():
			var q: Array = walls[k]
			var a0: Vector2 = pp2[k]
			var b0: Vector2 = pp2[(k + 1) % pp2.size()]
			if (Vector2(q[0]) - (a0 + off_probe)).length() > 0.001 \
					or (Vector2(q[1]) - (b0 + off_probe)).length() > 0.001:
				c_bad.append("第%d面顶边没跟着 off 抬高" % k)
			if (Vector2(q[2]) - b0).length() > 0.001 \
					or (Vector2(q[3]) - a0).length() > 0.001:
				c_bad.append("第%d面底边没落在砖边上（厚边会歪）" % k)
	# off=0 ⇒ 每个四边形的两条竖边重合 ⇒ 面积 0
	var deg: float = 0.0
	for q2 in _tile_side_walls(pp2, Vector2.ZERO):
		var quad := PackedVector2Array()
		for pv in (q2 as Array):
			quad.push_back(pv)
		deg = maxf(deg, _poly_area(quad))
	if deg > 0.001:
		c_bad.append("off=0 时厚边面积 %.4f（应 0 ⇒ 自动消失）" % deg)
	# 边色：alpha 必须逐字跟着面色走（探针 alpha=0.4）
	var face_probe := Color(0.5, 0.5, 0.5, 0.4)
	var lits: Array[float] = [0.0, 0.5, 1.0]
	for lit_probe in lits:
		var ec_a: Color = _tile_edge_color(face_probe, lit_probe)
		if absf(ec_a.a - face_probe.a) > 0.0001:
			c_bad.append("lit=%.1f 的边 alpha=%.3f 没跟着面色 %.3f 走" % [
				lit_probe, ec_a.a, face_probe.a])
	var lum_d: float = _tile_edge_color(face_probe, 0.0).get_luminance()
	var lum_m: float = _tile_edge_color(face_probe, 0.5).get_luminance()
	var lum_l: float = _tile_edge_color(face_probe, 1.0).get_luminance()
	if lum_d >= face_probe.get_luminance():
		c_bad.append("背光边没被压暗（厚度看不出来）")
	if lum_l <= face_probe.get_luminance():
		c_bad.append("受光边没被提亮（立体感看不出来）")
	# ★ 单调性用**严格**形式（铁律 §35：「非递减」在恒等序列上恒真）
	if not (lum_d < lum_m and lum_m < lum_l):
		c_bad.append("边色明度随 lit 不是严格增（%.4f / %.4f / %.4f）" % [lum_d, lum_m, lum_l])
	var c10c: bool = c_bad.is_empty()
	checks.append(["⑩c 厚边与砖边逐点对齐｜off=0 自动退化｜边色严格随面色派生", c10c,
		"异常 %d 处 %s" % [c_bad.size(), str(c_bad.slice(0, 3))]])

	# ---- ⑩d 厚边的**尺度**：非平凡、且**不跨到下方最近一笔** ----
	#   ★ 被测物从「真砖起手抬高量」换成「真砖的厚边高度」。三条不变量：
	#     ① **下界** `depth ≥ TILE_RELIEF_MIN` —— 真砖小到被地板夹住时，厚度会退化成
	#        一条看不见的线（"立体感"成了空话），而 ⑩c 量的是**假砖**（R=50）照样绿
	#        ⇒ 必须有这一条量**真砖**；
	#     ② **上界 = 实测净空**：厚边只向下伸 ⇒ 它必须小于「本块下沿 → 下方最近的
	#        一笔（别的砖 **或别的标签**）顶沿」的最小值。
	#        ⚠️⚠️ 这个上界**必须实测**，不许写成 `ROW_ROW_GAP − 常数`：行与行之间的距离
	#        不只有一个来源（nav 行走 `NAV_ROW_GAP`，其余行由 `_tile_base_r()` 的纵向
	#        预算给出），拿某一个常量当上界就是**猜**。首版正是猜的（`ROW_ROW_GAP − 4`
	#        = 6.0），实测把 7.38 判红，而它离真实净空还差得远 ⇒ **假红**。
	#        ★ 这条给**观感旋钮装了牙齿**：`TILE_RELIEF_DEPTH` 调大是"看得见"的改动，
	#        没有它就能把画面搞坏而**所有几何判据都还是绿的**（它们量的都是 `poly`，
	#        而厚边画在 `poly` 之外）。
	#        ★ 净空用**包围盒**量：bbox 净空 ≤ 真实形状净空 ⇒ 断言更严，不会假绿。
	#        ★★ 它是**物理**约束（"不许跨到下一行"），**不是审美约束** —— 厚边多厚才算好看
	#        由 A/B 目检判断（铁律 11：探针只量病灶、守卫守画序、A/B 目检守观感；
	#        把审美写成硬判据的下一站就是一条"被人放宽掉"的红）。实测最小净空 62.47px。
	#     ③ **斜面宽在 (0, 半高) 里** —— 环比半高还宽就等于把整块面吃光（凹陷态会变成
	#        一块纯色，凹凸两态分不出来）。
	#   ★ 射程说清楚：只量**严格在下方**且**水平真的重叠**的净空 ——
	#     同行相邻块不在射程内（那一对由 ⑤c「块与块不叠」与 ⑩g 守）。
	#   ⚠️ 候选块**排除 `board` 组**：它的 `poly` 是循环行的"离焦点最近那一次"的**记账值**，
	#     可以落在可见窗口之外（⑩g 那条注里记过这笔账）⇒ 拿它量净空会报出一个屏幕上
	#     不存在的坐标。棋盘行的静态重叠由 ⑩g 按 `_board_slots` 展开来守。
	#   ⚠️ 样本必须来自**真砖**（`_items`）：假砖的尺度是判据自己给的 ⇒ 量不到"真砖够不够大"。
	var d_bad: Array[String] = []
	var depths: Array[float] = []
	var bevels: Array[float] = []
	var gap_best: float = 99999.0
	var gap_who: String = ""
	var n_gap: int = 0
	_set_page(PAGE_MAIN)
	# (1) 先把"这一页真的会画出来的每一笔"摊成包围盒清单：瓷砖本体 + **标签墨迹框**
	#     ★ 为什么连标签一起收：标签摆在砖轮廓**上方**（`LABEL_GAP`）⇒ 厚边往**下**伸时
	#       最先撞到的往往是**下一行的标签**，而不是下一行的砖。只收砖会漏掉这一半。
	#     ⚠️ 用 `_ink_label_pos()` 拼标签框（与 ⑩g／`_pass_ink_rect` 同一套算法）。
	var boxes_d: Array = []              # [Rect2, "砖group[label]" / "标签[label]"]
	for itb in _items:
		var pb2: PackedVector2Array = itb["poly"]
		if pb2.size() < 3:
			continue
		var rb2 := Rect2(pb2[0], Vector2.ZERO)
		for pq in pb2:
			rb2 = rb2.expand(pq)
		boxes_d.append([rb2, "砖%s[%s]" % [str(itb["group"]), str(itb["label"])]])
		var fs_g: int = _draw_fs_for(itb)
		var lp_g: Vector2 = _ink_label_pos(itb, itb["center"], pb2, fs_g, true)
		var th_g: float = _font_h(fs_g)
		var tw_g: float = UITheme.body_font().get_string_size(str(itb["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs_g).x
		boxes_d.append([Rect2(lp_g - Vector2(tw_g, th_g) * 0.5, Vector2(tw_g, th_g)),
			"标签[%s]" % str(itb["label"])])
	# (2) 逐块真砖量三条
	for itd in _items:
		var pd: PackedVector2Array = itd["poly"]
		if pd.size() < 3:
			continue
		var gd: String = str(itd["group"])
		if gd == "board":
			continue
		var half_d: float = _tile_half_h(pd)
		var dep_d: float = _tile_relief_depth(pd)
		var bev_d: float = _tile_relief_bevel(pd)
		depths.append(dep_d)
		bevels.append(bev_d)
		if dep_d < TILE_RELIEF_MIN - 0.001:
			d_bad.append("%s[%s] 厚边高度 %.2f < 地板 %.2f" % [
				gd, str(itd["label"]), dep_d, TILE_RELIEF_MIN])
		if bev_d <= 0.0 or bev_d >= half_d:
			d_bad.append("%s[%s] 斜面宽 %.2f 不在 (0, 半高 %.2f) 里" % [
				gd, str(itd["label"]), bev_d, half_d])
		# 下方净空：从本块的**下沿**量到下方最近一笔的**顶沿**
		var own := Rect2(pd[0], Vector2.ZERO)
		for pq2 in pd:
			own = own.expand(pq2)
		var gap_d: float = 99999.0
		var who_d: String = ""
		for bd in boxes_d:
			var rb3: Rect2 = bd[0]
			if rb3.position.y < own.end.y - 0.5:
				continue                 # 不在下方（自己那一份也天然落在这里）
			if rb3.end.x <= own.position.x + 0.5 or rb3.position.x >= own.end.x - 0.5:
				continue                 # 水平不重叠 ⇒ 是旁边那一列，不构成"下压"
			var g_d: float = rb3.position.y - own.end.y
			if g_d < gap_d:
				gap_d = g_d
				who_d = str(bd[1])
		if gap_d < 99999.0:
			n_gap += 1
			if gap_d < gap_best:
				gap_best = gap_d
				gap_who = "%s[%s] → %s" % [gd, str(itd["label"]), who_d]
		if dep_d >= gap_d:
			d_bad.append("%s[%s] 厚边 %.2f ≥ 到下方 %s 的净空 %.2f（跨行压过去了）" % [
				gd, str(itd["label"]), dep_d, who_d, gap_d])
	# ⚠️ 样本必须 ≥2 块：空样本集会让上面那个循环**一次都不进** ⇒ 判据恒真（铁律 13⑨）
	if depths.size() < 2:
		d_bad.append("真砖样本不足（%d）—— 平凡样本" % depths.size())
	# ⚠️ 上界必须**至少量到一处**：一处都没有 = 上界压根没被检验（"没量到"不许印成满分证据）
	if n_gap < 1:
		d_bad.append("上界一处也没量到（没有任何一块真砖的下方有东西）—— 平凡样本")
	# ★★ 2026-10-12 补（阴性对照 MT21 实测逮到）：不变量①那条是 `≥` ⇒ **恒等于地板**
	#   那种退化它能过 —— 而"恒等于地板"正是"立体感退化成一条看不见的线"的**定义**
	#   （`_tile_relief_depth()` 改成 `return TILE_RELIEF_MIN` ⇒ 这条判据全绿）。
	#   ★ 铁律 §35：「非递减」在**恒等序列**上恒真 ⇒ 判据要写**严格**形式。
	#   ⇒ 再钉一条：至少一块真砖的厚边是**算出来的**（> 地板），不是被地板夹住的。
	#   ⚠️ 与上面那条"上界至少量到一处"是**同一个毛病**的第二次出现
	#     （"没量到 / 全被夹住"都能伪装成满分）—— 同一个形状，本文件已记两次账。
	if not depths.is_empty() and depths.max() <= TILE_RELIEF_MIN + 0.001:
		d_bad.append("所有真砖的厚边都恒等于地板 %.2f —— 尺度被夹没了（非平凡性丢失）"
			% TILE_RELIEF_MIN)
	var dep_lo: float = depths.min() if not depths.is_empty() else 0.0
	var dep_hi: float = depths.max() if not depths.is_empty() else 0.0
	var bev_lo: float = bevels.min() if not bevels.is_empty() else 0.0
	var bev_hi: float = bevels.max() if not bevels.is_empty() else 0.0
	var c10d: bool = d_bad.is_empty()
	checks.append(["⑩d 真砖厚边非平凡且小于到下方的实测净空｜斜面宽在 (0, 半高)", c10d,
		"样本 %d 块（量到上界 %d 块）· 异常 %d 处 %s（厚边 %.2f~%.2f / 斜面 %.2f~%.2f / 最小净空 %.2f ← %s）" % [
			depths.size(), n_gap, d_bad.size(), str(d_bad.slice(0, 2)),
			dep_lo, dep_hi, bev_lo, bev_hi, gap_best, gap_who]])

	# ---- ⑩h 形状：左右两端半圆（胶囊）｜点数确定 ⇒ 内外轮廓逐点一一对应 ----
	#   ★★ 用户口令「改成左右两端半圆的矩形」。
	#   ★★ 四条一起量，缺一条就漏一类：
	#     ① **形状成员性**：每个顶点要么落在上/下直边上、要么落在四角圆弧上（半径 = `cr`）
	#        —— 这是"它到底是什么形状"的直接断言，不是"看起来像"；
	#     ② **点数 = 4×seg + 2**：这是"内轮廓能按下标与外墙配对"的**地基**。旧写法
	#        （只去掉一个尾点、留着两条零长度直边）在胶囊下会多出退化边 ⇒
	#        `draw_polyline` 多画一段、`_tile_side_walls()` 多一个零面积四边形，
	#        更要命的是内外点数不等 ⇒ 斜面环那段**整段不画**（`if inner.size() == ...`）；
	#     ③ **`menu_btn_corner = 1.0` 就是胶囊**：这一条钉的是批次 1 修掉的那个上界错误
	#        —— 旧式 `max_cr = minf(hh, hw * 0.5)` 在 `h_ratio = 0.73` 下恒等于 `hw/2`，
	#        再乘什么系数都够不到 `hh` ⇒ **竖着永远拼不出半圆**。
	#        ★ 判据用「到中轴水平线段的最短距离 == 半高」来断，实测咬得住它
	#          （旧式下左端弧点给出 0.625R ≠ 0.73R）。
	#     ④ **内轮廓**：点数相同 + 逐点到**对应边**的距离 ≈ t（斜接的等价条件）+
	#        严格在里 + `t=0` 时逐点恒等。
	#        ⚠️ 符号：判据取的是**外**法线 ⇒ 内移点的读数是 **−t**（首版写成 `+t` 判红过，
	#        见下面那一段注：那是**判据写反**，不是代码坏）。
	#   ⚠️ 形状断言按 `menu_btn_corner` **现算期望**（不硬编码"必须是胶囊"）：旋钮改小时
	#     本条**跟着换靶子**（期望变成"圆角半径与旋钮一致"）⇒ 旋钮不是死的、判据也不恒真。
	var h_bad: Array[String] = []
	var seg_h: int = maxi(1, menu_btn_corner_seg)
	var R_h: float = 50.0
	var hw_h: float = R_h
	var hh_h: float = R_h * menu_btn_h_ratio
	var cr_h: float = clampf(minf(hh_h, hw_h) * menu_btn_corner, 0.0, minf(hh_h, hw_h))
	var sx_h: float = hw_h - cr_h
	var sy_h: float = hh_h - cr_h
	var poly_h: PackedVector2Array = _make_btn_rect(Vector2.ZERO, R_h)
	if poly_h.size() != 4 * seg_h + 2:
		h_bad.append("点数 %d ≠ 4×seg+2 = %d（去重没做干净 / 退化边留下了）" % [
			poly_h.size(), 4 * seg_h + 2])
	var bb_h := Rect2(poly_h[0], Vector2.ZERO)
	for p_h in poly_h:
		bb_h = bb_h.expand(p_h)
	if absf(bb_h.size.x - 2.0 * hw_h) > 0.01 or absf(bb_h.size.y - 2.0 * hh_h) > 0.01:
		h_bad.append("包围盒 %s ≠ %.1f×%.1f（换形状也不许越纵向预算）" % [
			str(bb_h.size), 2.0 * hw_h, 2.0 * hh_h])
	# 形状成员性：上/下直边 或 四角圆弧
	var arc_c: Array[Vector2] = [Vector2(sx_h, -sy_h), Vector2(sx_h, sy_h),
		Vector2(-sx_h, sy_h), Vector2(-sx_h, -sy_h)]
	var n_on_h: int = 0
	for p_h2 in poly_h:
		var ok_edge: bool = absf(absf(p_h2.y) - hh_h) < 0.02 and absf(p_h2.x) <= sx_h + 0.02
		var ok_arc: bool = false
		for cc_h in arc_c:
			if absf((p_h2 - cc_h).length() - cr_h) < 0.05:
				ok_arc = true
				break
		if ok_edge or ok_arc:
			n_on_h += 1
		elif h_bad.size() < 4:
			h_bad.append("顶点 %s 既不在直边上、也不在角弧上（cr=%.2f）" % [str(p_h2), cr_h])
	if n_on_h != poly_h.size():
		h_bad.append("形状成员性 %d/%d —— 有顶点落在轮廓之外" % [n_on_h, poly_h.size()])
	# `menu_btn_corner = 1.0` ⇒ 胶囊（左右两端各一个半圆）—— 临时置 1.0 造样本后还原
	var corner_bak_h: float = menu_btn_corner
	menu_btn_corner = 1.0
	var cap_h: PackedVector2Array = _make_btn_rect(Vector2.ZERO, R_h)
	menu_btn_corner = corner_bak_h
	var cap_cx: float = hw_h - hh_h      # 两端半圆圆心所在的 |x|
	var n_cap: int = 0
	for p_h3 in cap_h:
		var t_h: float = clampf(p_h3.x, -cap_cx, cap_cx)
		if absf((p_h3 - Vector2(t_h, 0.0)).length() - hh_h) < 0.05:
			n_cap += 1
	if n_cap != cap_h.size():
		h_bad.append("menu_btn_corner=1.0 下有 %d/%d 个顶点不满足「胶囊方程」（两端半圆没长出来）"
			% [cap_h.size() - n_cap, cap_h.size()])
	# 内轮廓（`_draw()` 画斜面环时读的同一个函数）
	var iv_t: float = 6.0
	var inner_h: PackedVector2Array = _inset_convex(poly_h, iv_t)
	if inner_h.size() != poly_h.size():
		h_bad.append("内轮廓点数 %d ≠ 外墙 %d（斜面环按下标配对会错位）" % [
			inner_h.size(), poly_h.size()])
	else:
		# 有符号外法线：与 `_inset_convex()` 同一套鞋带符号判定（y 向下 ⇒ 顺时针为正）
		var acc_h := 0.0
		for k_h in poly_h.size():
			var ak: Vector2 = poly_h[k_h]
			var bk: Vector2 = poly_h[(k_h + 1) % poly_h.size()]
			acc_h += ak.x * bk.y - bk.x * ak.y
		var sgn_h: float = 1.0 if acc_h > 0.0 else -1.0
		var worst_d: float = 0.0
		for k_h2 in poly_h.size():
			var pk: Vector2 = poly_h[k_h2]
			var pk2: Vector2 = poly_h[(k_h2 + 1) % poly_h.size()]
			# ★★ 这里取的是**外**法线（与 `_inset_convex()` 同一套符号约定）⇒ 内移 t 的顶点
			#   在这个方向上给出的是 **−t**，断言必须写 `+ iv_t`。
			#   ⚠️ 首版写成 `- iv_t`（= 期望内轮廓落在**外面**），于是代码改对之后这条反而报红
			#   （实测"最大偏差 12.000" = |−6 − 6|，正好 2t）—— **是判据写反，不是代码坏**。
			#   ⇒ 铁律 §71 的老账：判据读数与同屏数据自相矛盾时，先假设判据写反。
			var nk: Vector2 = Vector2(pk2.y - pk.y, -(pk2.x - pk.x)).normalized() * sgn_h
			worst_d = maxf(worst_d, absf((inner_h[k_h2] - pk).dot(nk) + iv_t))
			worst_d = maxf(worst_d,
				absf((inner_h[(k_h2 + 1) % poly_h.size()] - pk).dot(nk) + iv_t))
		if worst_d > 0.05:
			h_bad.append("环宽不处处等于 t=%.1f（最大偏差 %.3f）" % [iv_t, worst_d])
		if _poly_area(inner_h) >= _poly_area(poly_h):
			h_bad.append("内轮廓面积 %.1f 不小于外墙 %.1f（不是向内取的）" % [
				_poly_area(inner_h), _poly_area(poly_h)])
	var zero_h: PackedVector2Array = _inset_convex(poly_h, 0.0)
	var same_h: bool = zero_h.size() == poly_h.size()
	if same_h:
		for k_h3 in poly_h.size():
			if zero_h[k_h3].distance_to(poly_h[k_h3]) > 0.001:
				same_h = false
				break
	if not same_h:
		h_bad.append("t=0 时内轮廓没退回外墙（环会留下一条缝）")
	var c10h: bool = h_bad.is_empty()
	checks.append(["⑩h 胶囊：两端半圆｜点数=4×seg+2｜内轮廓逐点对应且环宽为 t", c10h,
		"顶点 %d · 异常 %d 处 %s" % [poly_h.size(), h_bad.size(), str(h_bad.slice(0, 3))]])

	# ---- ⑩k 字色必须对「它真正画在上面的那个底色」达标（**含选中态**）----
	#   ★★ 为什么必须有这条（2026-10-12 用户报「已选按钮不要变黑，会看不清字」）：
	#     旧口径是"选中就读 `pal["ink_sel"]`"，而那一对（`fill_sel` / `ink_sel`）是
	#     **对着实心 accent 底**算出来的；主菜单瓷砖的底其实是主题棋盘色 `_fat_color`
	#     ⇒ 浅主题下 `fill_sel` 被推近黑、`ink_sel` 跟着变近黑 ⇒ **黑字压黑砖**
	#     （截图像素实测：选中块 (31,31,36)、字 (0,0,0)，对比度约 1.3 —— 门槛要 4.5）。
	#   ⚠️⚠️ **必须含选中态样本**：旧口径恰在选中态塌掉；只量未选态的话，这条判据
	#     **修 bug 前就是绿的**（铁律 4：那种判据等于没测这个 bug）。
	#   ★ 判据读 `_tile_label_color()` / `_tile_label_bg()` 这一对**真源**（`_draw()` 读同一对），
	#     不自己重实现一份底色逻辑（铁律 §70）。
	#   ★ 逐主题扫（`preset_names()` 取真源，禁硬编码主题名，铁律 §78）：这是**配色**问题，
	#     不是"某一个主题的常量写错" ⇒ 单主题样本会漏掉另一半（浅色主题）。
	#   ★ 两种底色各维护「最差读数 + 它的主人」并**分别打印**：混成一个最小值会把
	#     "未选态 5.0（达标）"印在"选中态 1.2（不达标）"前面（rules §14 的老账）。
	#   ★★ 内含一条**阴性对照**（兜底分支）：正常主题下兜底那一步根本不会被触发，
	#     把 `ink` 换成"与底色完全相同"（对比度 1.0）之后它**必须**被触发 ——
	#     没有这一半，"兜底被删掉"在本判据里看不出来（那就是"写了判据却永远不红"）。
	var k_bad: Array[String] = []
	var k_samples: Array[Dictionary] = [
		{"selected": false, "disabled": false, "tag": "未选可用"},
		{"selected": true, "disabled": false, "tag": "已选可用"},
	]
	var k_worst: Array[float] = [999.0, 999.0]
	var k_who: Array[String] = ["", ""]
	var k_seen: int = 0
	var k_apply: int = 0
	var k_fb: int = 0          # `pal["ink"]` 自身不够、真走了兜底的主题数（**仅报告**）
	for pn_k in GameConfig.preset_names():
		if not GameConfig.apply_preset(pn_k):
			continue
		_apply_appearance()
		k_apply += 1
		var pal_k: Dictionary = GameConfig.button_palette(_bg_color)
		for si_k in k_samples.size():
			var s_k: Dictionary = k_samples[si_k]
			var bg_k: Color = _tile_label_bg(s_k)
			var ink_k: Color = _tile_label_color(s_k, pal_k)
			var cr_k: float = GameConfig.contrast_of(ink_k, bg_k)
			k_seen += 1
			if cr_k < k_worst[si_k]:
				k_worst[si_k] = cr_k
				k_who[si_k] = pn_k
			if cr_k < GameConfig.BTN_TEXT_MIN_CONTRAST:
				k_bad.append("%s[%s] 字/底对比 %.2f < %.2f（底=%s 字=%s）" % [
					pn_k, str(s_k["tag"]), cr_k, GameConfig.BTN_TEXT_MIN_CONTRAST,
					str(bg_k), str(ink_k)])
			# 接线：**不需要兜底时**，字色必须就是 `pal["ink"]`（没去读 `ink_sel`、
			#   也没读别的键）。★ 只在"不需要兜底"的那一半断，否则会把正常兜底判成红。
			var ink_pal_k: Color = Color(pal_k["ink"])
			if GameConfig.contrast_of(ink_pal_k, bg_k) >= GameConfig.BTN_TEXT_MIN_CONTRAST:
				if not ink_k.is_equal_approx(ink_pal_k):
					k_bad.append("%s[%s] 字色不是 pal[ink]（是不是又去读 ink_sel 了？）" % [
						pn_k, str(s_k["tag"])])
			else:
				k_fb += 1
	# 兜底分支的阴性对照：ink 与底色相同时必须仍然达标，且**不等于**底色
	var n_fallback: int = 0
	for si_k2 in k_samples.size():
		var s_k2: Dictionary = k_samples[si_k2]
		var bg_k2: Color = _tile_label_bg(s_k2)
		var pal_bad: Dictionary = GameConfig.button_palette(_bg_color).duplicate()
		pal_bad["ink"] = bg_k2
		var ink_bad: Color = _tile_label_color(s_k2, pal_bad)
		n_fallback += 1
		if ink_bad.is_equal_approx(bg_k2):
			k_bad.append("兜底没生效：ink 与底色相同时原样返回（对比度 %.2f）" % [
				GameConfig.contrast_of(ink_bad, bg_k2)])
		elif GameConfig.contrast_of(ink_bad, bg_k2) < GameConfig.BTN_TEXT_MIN_CONTRAST:
			k_bad.append("兜底生效了但没达标：%.2f < %.2f" % [
				GameConfig.contrast_of(ink_bad, bg_k2), GameConfig.BTN_TEXT_MIN_CONTRAST])
	# 复原（自检不许把主题留在最后一个预设上）
	GameConfig.apply_preset(GameConfig.DEFAULT_PRESET)
	_apply_appearance()
	# ⚠️ 样本数必须达标：空集会让上面两个循环**一次都不进** ⇒ 判据恒真（铁律 13⑨）
	var c10k: bool = k_bad.is_empty() and k_seen >= 2 and k_apply >= 2 and n_fallback == 2
	# ⚠️ `k_fb` 是**要印出来的**：它数的是"`pal["ink"]` 自身对瓷砖底不够、真走了兜底"的
	#   样本数 —— 兜底是**保险**不是常态，常态下它应当是 0；哪天上到两位数，说明
	#   `pal["ink"]`（对着 `pal["fill"]` 拟合的那一档）与瓷砖真实底色的差距变大了，
	#   该去看 `button_palette()` 而不是来放宽阈值。（首版算了却没印 = 只写不读的死变量。）
	checks.append(["⑩k 字色对真实底色达标｜含选中态｜逐主题 × 未选/已选", c10k,
		"主题 %d 个 · 样本 %d 处 · 兜底对照 %d · 走了兜底 %d 处 · 异常 %d 处｜最差 未选 %.3f(%s) 已选 %.3f(%s) %s" % [
			k_apply, k_seen, n_fallback, k_fb, k_bad.size(),
			k_worst[0], k_who[0], k_worst[1], k_who[1], str(k_bad.slice(0, 2))]])

	# ---- ⑩g 静止布局下**砖本体不压标签**（换按钮形状时最容易撞的一条）----
	#   ★★ 为什么必须有这条：它量的是"标签 × 砖本体"这对关系 —— 而 ⑤a 量"标签与标签不叠"、
	#      ⑤c 量"块与块不叠"，**没有一条量"块压标签"**。这正是**改按钮形状**（菱形 →
	#      圆角矩形 → 2026-10-12 的胶囊）时唯一会撞的那件事：形状一变，砖的轮廓就在标签
	#      附近多长出/少掉一块，而其余几百条几何判据**一条也看不见**。
	#      实测账：2026-10-08 菱形→圆角矩形时报出 2 处（为此加了 `_anchor_avoid_offset()`
	#      那一整套补偿）；本轮胶囊改动的回归里它就是主要看门人。
	#   ★ 依据：标签是按 `LABEL_GAP` / `SUB_LABEL_SPREAD` / `_anchor_avoid_offset()` 摆在砖
	#      轮廓**之外**的 ⇒ 静止布局下"某块砖的本体压住另一块的标签"应当**一处也没有**。
	#   ⚰️ 2026-10-12：本条原先还有另一个理由（"证明「标签一律最后画」在静止画面上是逐像素
	#      等价的"）—— 那套"攒起来 / 延后画"的机制随黑砖族删除、标签已改成就地落笔
	#      ⇒ 那个理由作废了，但**"砖本体不压标签"这条事实本身仍然要守**（上面的理由更硬：
	#      它与机制无关，只与"形状 × 标签摆位"有关）。
	# ⚠️⚠️ 必须按**这一帧真的会画的每一笔**量 —— 而棋盘行改**静态平铺**之后，
	#   "`_items` 的 poly 是记账值、屏幕上看的是槽位几何"这个差别**不存在了**：
	#   每块只出现一次，`_items[i]["poly"]` 就是绘制几何。
	#   ⚰️ 改前这里要"棋盘行按 `_board_slots` 展开、其余组按 `_items`"两段各走一遍
	#      （理由：循环行的 `poly` 是「离焦点最近的那一次出现」，可以落在可见窗口之外，
	#       实测 ⑤ 在 2026-10-02 报过 `筝形@1181` 那个屏幕上不存在的坐标）——
	#      槽位整族删除后那一段一条也进不来，留着就是量空集合。
	#   ⚠️ 这里**不要**反过来把棋盘行排除掉："砖本体不压标签"对棋盘行同样成立，
	#      排除 = 静默丢掉 5 块的覆盖（判据照样 ✓）。
	var pass_g: Array[Dictionary] = []
	for i_g in _items.size():
		var it_g: Dictionary = _items[i_g]
		var pl_g: PackedVector2Array = it_g["poly"]
		if pl_g.size() < 3:
			continue
		pass_g.append({"it": it_g, "i": i_g, "poly": pl_g, "c": it_g["center"], "home": true})
	var base_cover_bad: Array[String] = []
	var n_base_cover: int = 0
	for a_g in pass_g:
		var pa2: PackedVector2Array = a_g["poly"]
		for b_g in pass_g:
			# 同一笔自己压自己的标签不算（标签就贴在它自己砖上顶点上方，`LABEL_GAP` 撑开）。
			# ⚠️ 身份用**下标**判（`i`），不要用 `a["it"] == b["it"]` —— 那是"拿 Dictionary 内容
			#   当身份"，内容相同的两个条目会互相顶替（本轮 ⑩e 已记过同一笔账）。
			#   `distance < 0.5` 那一半负责区分"同一块砖的不同重影"（它们是同一 `i`、位置不同）。
			if int(a_g["i"]) == int(b_g["i"]) \
					and (a_g["c"] as Vector2).distance_to(b_g["c"]) < 0.5:
				continue
			var itb2: Dictionary = b_g["it"]
			var fs_b: int = _draw_fs_for(itb2)
			var lp_b: Vector2 = _ink_label_pos(itb2, b_g["c"], b_g["poly"], fs_b, bool(b_g["home"]))
			var th_b: float = _font_h(fs_b)
			var tw_b: float = UITheme.body_font().get_string_size(str(itb2["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs_b).x
			var lbl_b := Rect2(lp_b - Vector2(tw_b, th_b) * 0.5, Vector2(tw_b, th_b))
			var area_b: float = _raised_hits_rect(pa2, lbl_b)
			if area_b > 1.0:
				n_base_cover += 1
				if base_cover_bad.size() < 4:
					# ★ 红项**必须带坐标**：只知道"谁压住了谁"没法决定往哪让 —— 而本条正是
					#   「换按钮形状」那类改动的落点（2026-10-08 菱形→圆角矩形实测报出两处）。
					var pbb := Rect2(pa2[0], Vector2.ZERO)
					for ppc in pa2:
						pbb = pbb.expand(ppc)
					base_cover_bad.append("%s[%s]块%s 压住标签「%s」%s /%.0fpx²" % [
						str((a_g["it"] as Dictionary)["group"]), str((a_g["it"] as Dictionary)["label"]),
						str(pbb), str(itb2["label"]), str(lbl_b), area_b])
	_set_page(PAGE_MAIN)
	var c10g: bool = n_base_cover == 0
	checks.append(["⑩g 静止布局下砖本体不压标签｜换形状的落点", c10g,
		"%d 笔探针 · 重叠 %d 处 %s" % [pass_g.size(), n_base_cover, str(base_cover_bad)]])

	# ---- ⑩m 受光方向：凸起 = **左上**受光（亮）｜凹陷 = 整圈反过来 ----
	#   ★★★ 为什么非有这条不可（2026-10-12 真机截图像素取色逮到）：本族的方向契约写在注释里
	#     （「凸起：左上内侧受光（亮）」），而代码把 `(dv.x + dv.y)` **取正**那一半当受光
	#     ⇒ 屏幕上「未选看着像凹、已选看着像凸」，与契约、与用户口令**正好相反**。
	#     ⚠️ ⑩c/⑩d/⑩h/⑩k **一条都看不见**：它们量的都是**对称量**（单调 / 对齐 / 派生 /
	#     对比度），方向一翻照旧成立。⇒ 必须有一条**只问方向**的判据
	#     （铁律 §17/§23 的同族现象：方向写反 ⇒ 判据与同屏数据自相矛盾，而判据自己是绿的）。
	#   ★★ 独立性（铁律 §70）：不另抄一份方向公式，调生产端那一个 `_tile_bevel_lit()`；
	#     期望值也不写「左上 = 1」这种常数，而是用**几何**定出「哪条边在左上」
	#     （`mid − center` 的 `x + y` 最小者），再问「这条边的受光权重是不是高的那个」。
	#   ★ 样本 = 假砖（R=50，与 ⑩c 同一个 `_make_btn_rect`）：本条量的是「光从哪来」，与
	#     布局无关；真砖的**尺度**由 ⑩d 守、真砖的**可见性**由 ⑩n 守。
	var m_bad: Array[String] = []
	var ctr_m := Vector2(200.0, 150.0)
	var poly_m: PackedVector2Array = _make_btn_rect(ctr_m, 50.0)
	var inner_m: PackedVector2Array = _inset_convex(poly_m, _tile_relief_bevel(poly_m))
	var mids_m: Array[Vector2] = []
	var tl_m: int = -1
	var br_m: int = -1
	var tl_s: float = 1.0e18
	var br_s: float = -1.0e18
	if poly_m.size() >= 3 and poly_m.size() == inner_m.size():
		for k in poly_m.size():
			var k2: int = (k + 1) % poly_m.size()
			var mid_k: Vector2 = (poly_m[k] + poly_m[k2] + inner_m[k2] + inner_m[k]) * 0.25
			mids_m.append(mid_k)
			var s_k: float = (mid_k - ctr_m).x + (mid_k - ctr_m).y
			if s_k < tl_s:
				tl_s = s_k
				tl_m = k
			if s_k > br_s:
				br_s = s_k
				br_m = k
	var lit_r_tl: float = 0.0
	var lit_r_br: float = 0.0
	var lit_s_tl: float = 0.0
	var lit_s_br: float = 0.0
	if tl_m < 0 or br_m < 0 or tl_m == br_m:
		m_bad.append("探针砖上找不出「左上 / 右下」两条边（内轮廓点数 %d / %d）" % [
			poly_m.size(), inner_m.size()])
	else:
		var mid_tl: Vector2 = mids_m[tl_m]
		var mid_br: Vector2 = mids_m[br_m]
		# 先断「选出来的那条边几何上真的在左上 / 右下」—— 否则下面两条可以靠选点作弊通过
		if not (mid_tl.x < ctr_m.x and mid_tl.y < ctr_m.y):
			m_bad.append("选出的「左上」边其实不在左上 %s（中心 %s）" % [str(mid_tl), str(ctr_m)])
		if not (mid_br.x > ctr_m.x and mid_br.y > ctr_m.y):
			m_bad.append("选出的「右下」边其实不在右下 %s" % str(mid_br))
		lit_r_tl = _tile_bevel_lit(mid_tl, ctr_m, false)
		lit_r_br = _tile_bevel_lit(mid_br, ctr_m, false)
		lit_s_tl = _tile_bevel_lit(mid_tl, ctr_m, true)
		lit_s_br = _tile_bevel_lit(mid_br, ctr_m, true)
		# ★ 严格形式 + **差距够大**：铁律 §35「非递减在恒等序列上恒真」⇒ 连「差 ≥ 0.5」一起断
		if not (lit_r_tl >= lit_r_br + 0.5):
			m_bad.append("凸起态左上受光 %.3f 没比右下 %.3f 高（光该从左上打来）" % [
				lit_r_tl, lit_r_br])
		if not (lit_s_tl <= lit_s_br - 0.5):
			m_bad.append("凹陷态没把受光方向反过来（左上 %.3f / 右下 %.3f）" % [lit_s_tl, lit_s_br])
		# 两态必须**严格互为补**（这才是「整圈反过来」；只断"小于/大于"会漏掉"两态一样平"）
		var rev_err: float = absf((lit_r_tl - lit_r_br) + (lit_s_tl - lit_s_br))
		if rev_err > 0.001:
			m_bad.append("凹凸两态不是整圈反过来（差值之和 %.4f 应 0）" % rev_err)
		# 边色必须跟着方向走，而且**差要非平凡**（「亮 / 暗」得真的看得出来）
		var face_m := Color(0.42, 0.45, 0.48, 1.0)
		var lm_face: float = face_m.get_luminance()
		var c_r_tl: Color = _tile_edge_color(face_m, lit_r_tl)
		var c_r_br: Color = _tile_edge_color(face_m, lit_r_br)
		var c_s_tl: Color = _tile_edge_color(face_m, lit_s_tl)
		var c_s_br: Color = _tile_edge_color(face_m, lit_s_br)
		var l_r_tl: float = c_r_tl.get_luminance()
		var l_r_br: float = c_r_br.get_luminance()
		var l_s_tl: float = c_s_tl.get_luminance()
		var l_s_br: float = c_s_br.get_luminance()
		if not (l_r_tl > lm_face and lm_face > l_r_br):
			m_bad.append("凸起态的左上边没亮过面色 / 右下边没暗过面色（%.4f / %.4f / %.4f）" % [
				l_r_tl, lm_face, l_r_br])
		if not (l_s_tl < lm_face and lm_face < l_s_br):
			m_bad.append("凹陷态的明暗没反过来（%.4f / %.4f / %.4f）" % [l_s_tl, lm_face, l_s_br])
		if not (l_r_tl - l_r_br > 0.05):
			m_bad.append("凹凸的明暗差只有 %.4f —— 太淡，屏幕上读不出立体感" % (l_r_tl - l_r_br))
	var c10m: bool = m_bad.is_empty()
	checks.append(["⑩m 受光方向：凸起=左上亮｜凹陷=整圈反过来｜明暗差非平凡", c10m,
		"异常 %d 处 %s（lit 凸起 左上%.3f/右下%.3f · 凹陷 左上%.3f/右下%.3f）" % [
			m_bad.size(), str(m_bad.slice(0, 3)), lit_r_tl, lit_r_br, lit_s_tl, lit_s_br]])

	# ---- ⑩n 斜面环必须**宽过描边+呼吸发光伸进砖内的那段**（「算对了」≠「看得见」）----
	#   ★★★ 为什么（2026-10-12 真机截图像素取色逮到）：`draw_polyline` 的线宽是**居中**的
	#     ⇒ 3px 描边 + 最多 7px 呼吸发光会往砖内渗 5px（`TILE_INK_REACH`）；而**真机窗口
	#     1152×648** 下 `棋盘 / 大小 / 对战方式` 三行的小砖只有 R≈29（半高≈21）⇒ 按比例
	#     只有 3.94px 的斜面环 ⇒ **整圈被墨迹盖掉**：那块砖在屏幕上一点凹凸都没有。
	#     实测 x 剖面：描边 (77,255,209) 8px 之后**直接**是面色 (14,29,34)，中间没有环。
	#     ⚠️ ⑩d 看不见它：只断「斜面宽 < 半高」的**上界**（缺"被盖掉"这一侧的下界）。
	#   ★★★ 为什么**必须按尺寸扫描**而不是量 `_items` 的现成砖：自检画布比真机窗口大
	#     （`--labeltest` 同步读数「棋盘R=56.8 对战方式R=56.8」，真机实测 R≈29）
	#     ⇒ `_items` 里每一块都是"大砖"，**小砖那一档只在真机上存在**
	#     ⇒ 只量 `_items` 的话，本条会报出一堆漂亮读数而**恰恰漏掉它要守的那一档**
	#     （"样本里没有那一档"与"全通过"在日志里长得一模一样 —— 铁律 4 的同族现象；
	#      本条上一版就是这么写的，实测读数「最小档 nav[练习] 半高43.0」，小砖一块没进样本）。
	#     扫描 = 自造 R 递进的胶囊（与 ⑩c 同一个 `_make_btn_rect`），显式覆盖真机那一档。
	#   ★ 口径：`bevel − TILE_INK_REACH ≥ 1`（净环至少 1px 才可能被看见）；对"上限夹子已经
	#     咬到"的小尺寸（半高 < `hh_need`）不要求 —— 那是物理上装不下，不是缺陷。
	#     两向同时关：`0 < bevel < 半高`（地板反噬会把整块面吃掉）。
	#   ★★ 非平凡性（铁律 4）：单列 `n_small`（R ≤ 34 = 真机小砖档）并断 ≥1，把盲区本身钉住。
	var n_bad: Array[String] = []
	var thin_bad: Array[String] = []
	# 净环只在"上限夹子还没咬到"的砖上要求（咬到 = 物理上装不下，不是缺陷）
	var hh_need: float = (TILE_INK_REACH + 1.0) / TILE_RELIEF_BEVEL_MAX_FRAC
	var n_probe: int = 0
	var n_small: int = 0
	var thin_worst: float = 1.0e18
	var thin_who: String = ""
	# R 档位：从"小到装不下"一直到"比自检画布里的真砖还大"，**必须含真机小砖档 R≈29**
	var r_sweep: Array[float] = [8.0, 12.0, 16.0, 19.0, 22.0, 26.0, 29.0, 34.0, 40.0, 48.0,
		56.8, 64.0, 72.0, 84.0]
	for r_n in r_sweep:
		var pn0: PackedVector2Array = _make_btn_rect(Vector2(300.0, 200.0), r_n)
		var hh_n0: float = _tile_half_h(pn0)
		var bv_n0: float = _tile_relief_bevel(pn0)
		if bv_n0 <= 0.0 or bv_n0 >= hh_n0:
			n_bad.append("R=%.1f 的斜面宽 %.2f 不在 (0, 半高 %.2f) 里" % [r_n, bv_n0, hh_n0])
		if hh_n0 < hh_need:
			continue
		n_probe += 1
		if r_n <= 34.0:                     # 真机小砖那一档（1152×648 像素实测 R≈29）
			n_small += 1
			if bv_n0 - TILE_INK_REACH < thin_worst:
				thin_worst = bv_n0 - TILE_INK_REACH
				thin_who = "R=%.1f 半高%.1f 环%.2f" % [r_n, hh_n0, bv_n0]
		if bv_n0 - TILE_INK_REACH < 1.0:
			thin_bad.append("R=%.1f 环 %.2f 只比墨迹内渗 %.2f 宽 %.2f ⇒ 会被描边+发光盖掉" % [
				r_n, bv_n0, TILE_INK_REACH, bv_n0 - TILE_INK_REACH])
	# 真砖辅断：自检画布下它们都偏大，但"环被夹没 / 被面吃掉"这类退化在这一档也看得见
	var n_real: int = 0
	_set_page(PAGE_MAIN)
	for itn in _items:
		var pn: PackedVector2Array = itn["poly"]
		if pn.size() < 3:
			continue
		var hh_n: float = _tile_half_h(pn)
		var bv_n: float = _tile_relief_bevel(pn)
		if bv_n <= 0.0 or bv_n >= hh_n:
			n_bad.append("%s[%s] 斜面宽 %.2f 不在 (0, 半高 %.2f) 里" % [
				str(itn["group"]), str(itn["label"]), bv_n, hh_n])
		if hh_n >= hh_need:
			n_real += 1
			if bv_n - TILE_INK_REACH < 1.0:
				thin_bad.append("真砖 %s[%s] 环 %.2f 净空只有 %.2f" % [
					str(itn["group"]), str(itn["label"]), bv_n, bv_n - TILE_INK_REACH])
	if n_probe < 6:
		thin_bad.append("扫描有效档位不足（%d 档）—— 平凡样本" % n_probe)
	if n_small < 1:
		thin_bad.append("小砖那一档（R ≤ 34）一档都没扫到 —— 上一版正是瞎在这一档")
	if n_real < 2:
		thin_bad.append("真砖辅断样本不足（%d 块）" % n_real)
	var thin_disp: float = -1.0
	if n_small > 0:
		thin_disp = thin_worst
	var c10n: bool = n_bad.is_empty() and thin_bad.is_empty()
	checks.append(["⑩n 斜面环宽须宽过描边+发光的墨迹内渗｜扫描含真机小砖档 R≤34", c10n,
		"扫描 %d 档（小砖 %d / 真砖 %d）· 越界 %d · 太窄 %d %s（小砖最窄净环 %.2f ← %s / 墨迹内渗 %.2f）" % [
			n_probe, n_small, n_real, n_bad.size(), thin_bad.size(), str(thin_bad.slice(0, 2)),
			thin_disp, thin_who, TILE_INK_REACH]])

	# ---- ⑩f（**已删**）----
	#   原文 = 「统一动效的初始态干净｜无残留动画」，量的是 `_stone_anims` / `_stone_outs`
	#   两本动画字典是否为空（防"一进页面动画就在半空中"）。
	#   黑砖族删除后这两本字典不存在 ⇒ 判据的对象没了。
	#   ★ 它当年被迫写成这种"只做能做的一半"的形态，理由值得留（**别丢**）：
	#     "绘制时到底调了谁"在 headless 下看不见（不渲染）⇒ 那一半**永远**只能由结构守卫
	#     承担（MARKERS 钉调用点 + FORBID 钉旧写法）。本族原有的三条 MARKERS
	#     （`menu_stone_drop_call` / `menu_stone_fade_call` / `menu_stone_inplace`）随黑砖族
	#     删除，**替代它的是 S95**（「黑砖族符号不许回潮」）—— 因为被测对象不存在时，
	#     "它还在不在"没有意义，只有"它别回来"有意义（同 S55/S58a 的处置口径）。

	# ---- ⑬ ★★ 对弈页内容不许压住底栏（v4 删浮层后的**接棒判据**）----
	#   ★★ 为什么还要留这一条：联机入口从"练习面板上的浮层"搬成"独立的对弈页"之后，
	#      "谁压底栏"的风险没消失，只是**换了个角色**：页内容是原生 Control（不在 `_items` 里）
	#      ⇒ ①~⑫ 没有一条看得见它。
	#   ★ 与 `--labeltest` 的 `_duel_page_test()` 分工不同，两条都要（铁律 4：判据射程不同）：
	#      · 这里**多视口**量"页根下沿 ≤ 底栏上沿"这条硬边界；
	#      · 那边逐档量页根**等于真源**、控件不越右沿、两档互斥、列表行排得下。
	var size_bak13: Vector2 = size
	var page_bak13: int = _page
	var du_bad: Array[String] = []
	var du_seen: int = 0
	for vp13 in [Vector2(1152.0, 648.0), Vector2(1024.0, 640.0), Vector2(1280.0, 800.0),
			Vector2(1920.0, 1080.0)]:
		size = vp13
		_set_page(PAGE_LOBBY)          # 换视口必须重建（页根尺寸由 `size` 反解）
		_layout_setup()
		var fb13: Rect2 = _footer_band()
		if _duel_root == null:
			du_bad.append("%s 页根未建" % str(vp13))
			continue
		du_seen += 1
		var rb13: float = _duel_root.position.y + _duel_root.size.y
		if rb13 > fb13.position.y + 0.5:
			du_bad.append("%s 页根下沿 %.1f 压到底栏上沿 %.1f（超 %.1f）" % [
				str(vp13), rb13, fb13.position.y, rb13 - fb13.position.y])
		if rb13 > vp13.y:
			du_bad.append("%s 页根出屏底 %.1f > %.1f" % [str(vp13), rb13, vp13.y])
	size = size_bak13
	_set_page(page_bak13)
	_layout_setup()
	# ⚠️ 样本数必须是 4（视口）：恒空的样本集会让这条判据**恒真**（铁律 13⑨）。
	var c13: bool = du_bad.is_empty() and du_seen == 4
	checks.append(["⑬ 对弈页内容不压底部行带｜四档视口", c13,
		"样本 %d 处 · 异常 %d 处 %s" % [du_seen, du_bad.size(), str(du_bad.slice(0, 3))]])

	# ---- ⑭ 对战方式行：点一块 ⇒ **恰好那一块**高亮（走真实回调）----
	#   ★★ 为什么必须留这条（2026-10-09 读代码发现、随后实测证实；2026-10-12 又踩过一次同族）：
	#     原先难度三档从独立 group `"diff"` **平铺**进 `"mode"` 之后，`_refresh_selection()`
	#     的 `"mode"` 分支仍按「本地 / 人机」两个 **label** 字面认 ⇒ 点难度走
	#     `_select_diff() → _refresh_selection()` 时**三档全被判不高亮**。
	#     屏幕上的样子：点了一个档位**一个实心块都不剩**，而 AI 确实按那一档在下 —— 静默，
	#     且所有几何判据都看不见（它们量位置，**没有一条量「选中态」**）。
	#   ★ 2026-10-12（难度整族删除）之后这条**没有失效，只是换了靶子**：现在断的是
	#     「点「本地」/「磐石」/「疾风」各恰好亮一块、且亮的正是**点的那一块**」。
	#     ⚠️ 它守的是**结构性**坏法，不是难度特有的 —— `_mode_tile_selected()` 若被改回按
	#     label 认身份、或有人把 `==` 写成 `>=`，本条当场红。这就是它的长期价值。
	#   ★★ 2026-10-15b：**靶子第三次换，这次就是用户报的那个 bug** ——
	#     「疾风 = 人机 + 标记」的父子写法会让点「疾风」时**亮两块**。为此本条现在有**两颗牙**：
	#       ① 「恰好一块」——父子写法下点疾风 ⇒ 亮【磐石, 疾风】⇒ 红；
	#       ② 「`_sel_mode` == 这块瓷砖声明的 `mode_id`」——父子写法下点疾风 ⇒ 落 VS_AI(1)
	#          而不是 XGAI(100) ⇒ 红（这一颗专治"只有 `_select_mode` 被改回父子"的情形：
	#          那时 ① 也红，但报的是"亮了两块"，② 报的是"身份写成了父档"，指向更准）。
	#     ⚠️ 反过来说：**只把 `_mode_tile_selected` 改回父子**（`_select_mode` 不动）时，
	#      `_sel_mode` 仍是 100 ⇒ ② 绿、① 红（点疾风时磐石那块也判为选中）⇒ 仍被逮住。
	#      两颗牙的射程确实不同，**都要留**。
	#   ★ 判据**走真实回调**（`it["cb"]`），不许自己重算 `sel`：铁律 4 的
	#     「判据自己先调一次被测函数 ⇒ 抓不到该调它的地方没调」。
	#   ★ 高亮**断恰好一块 + 断它的名字**：只断"有没有亮"的话，「全不亮」与「全亮」
	#     都能溜过去（铁律 §68：别把"没量到"印成满分证据）。
	var mode_bak14: int = _sel_mode
	# ★★ 2026-10-15b：样本改成**从真源现取**（`_items` 里 group == "mode" 的全部瓷砖），
	#   不再硬编码清单。⚰️ 改前写死 `["本地", "人机"]` —— 本行加/改一块（本轮「人机」→「磐石」
	#   且并列化）就必须记得改那一行；漏改时症状有两档，**坏的那一档是静默的**：
	#   清单比实际少一块 ⇒ 少掉的那块**永远不被点一次**（射程静默变短，判据照样绿）。
	#   每块带 `label` + `mode_id` 两样：`label` 用来点它（与用户点的是同一块瓷砖）、
	#   `mode_id` 用来断"点它之后 `_sel_mode` 该等于什么" —— **不另立一张映射表**（§78）。
	var tiles14: Array = []
	for it16 in _items:
		if str(it16["group"]) == "mode":
			tiles14.append({"label": str(it16["label"]), "id": int(it16.get("mode_id", -1))})
	# 读「对战方式」行此刻高亮着哪些标签（只按 group 筛，不带任何位置/顺序假设）
	var read_lit := func() -> Array:
		var l_mode: Array[String] = []
		for it14 in _items:
			if str(it14["group"]) != "mode" or not bool(it14["selected"]):
				continue
			l_mode.append(str(it14["label"]))
		return l_mode
	# 点「对战方式」行某块瓷砖的**真实回调**（与用户点的是同一个 Callable）
	var click_mode_tile := func(lbl: String) -> bool:
		for it15 in _items:
			if str(it15["group"]) == "mode" and str(it15["label"]) == lbl:
				(it15["cb"] as Callable).call()
				return true
		return false
	var e14: Array[String] = []
	var covered14: Array[String] = []
	if tiles14.size() < 2:
		# 取不到样本 ⇒ 早退并**报红**（铁律 13⑨：对空集合的判据恒真 = 没测）
		e14.append("「对战方式」行只取到 %d 块瓷砖 —— 样本不足，本条不作数" % tiles14.size())
	for i14 in tiles14.size():
		var want_lbl14: String = str(tiles14[i14]["label"])
		var want_id14: int = int(tiles14[i14]["id"])
		# ★ 每次先把 `_sel_mode` 设成**另一块**（不是设成它自己）—— 设成它自己就成了恒真式：
		#   "点了没反应"与"点对了"在屏幕上完全一样。
		_sel_mode = int(tiles14[(i14 + 1) % tiles14.size()]["id"])
		_set_page(PAGE_MAIN)
		if not click_mode_tile.call(want_lbl14):
			e14.append("找不到「%s」瓷砖，标签被改名了？（_items 里明明列出了它）" % want_lbl14)
			continue
		covered14.append(want_lbl14)
		var lit14: Array = read_lit.call()
		# ★★ 这一条就是本轮口令的**回归牙齿**：「并列」= 点一块只亮一块。
		#   ⚰️ 并列化之前点「疾风」会亮【疾风, 磐石（旧称人机）】两块 ⇒ 这里当场红。
		if lit14.size() != 1 or str(lit14[0]) != want_lbl14:
			e14.append("点「%s」⇒ 高亮 %s（应恰好一块、且是「%s」）" % [
				want_lbl14, str(lit14), want_lbl14])
		# ★ 第二条：`_sel_mode` 必须落成**这块瓷砖自己声明的身份**（不是"父档"）。
		#   ⚰️ 并列化之前点「疾风」会落 `MODE_VS_AI`(1) 而不是 `MODE_XGAI`(100) ⇒ 这里当场红。
		if _sel_mode != want_id14:
			e14.append("点「%s」⇒ _sel_mode=%d（应 %d）—— 标签与状态不同源" % [
				want_lbl14, _sel_mode, want_id14])
	# ★★ 并列契约本身：这两块必须**都在**、且是**两个不同的名字**（不是塌成同一块）。
	#   ⚠️ **射程说清楚**（本轮用刀量出来的，别说成比实际更多）：本段两边**同源**
	#      （`_mode_label()` 与建瓷砖时用的是同一条链）⇒ 它**只能**抓"两个档取了同一个名字"
	#      这种塌缩，**抓不到"改名字却漏改了一处"**。那件事由 `--labeltest` 的 ⓪ 段负责
	#      —— 那边用的是**独立字面量**（模拟脚本/人按名字找瓷砖），才是跨实现的对拍。
	#      两段分工不同，都要留（§11 探针/判据分工）。
	var lbl_pan14: String = _mode_label(MODE_VS_AI)
	var lbl_xg14: String = _mode_label(MODE_XGAI)
	var has_lbl14 := func(s: String) -> bool:
		for t16 in tiles14:
			if str(t16["label"]) == s:
				return true
		return false
	if lbl_pan14 == lbl_xg14 or not has_lbl14.call(lbl_pan14) or not has_lbl14.call(lbl_xg14):
		e14.append("「%s」与「%s」未同时存在、或取了同一个名字 —— 并列契约被破坏" % [
			lbl_pan14, lbl_xg14])
	_sel_mode = mode_bak14
	_set_page(PAGE_MAIN)
	# ⚠️ 有效分母（铁律 §106）：本行至少 3 块（本地 / 磐石 / 疾风），且**每一块**都真被点过一次。
	#   少到 0 会让判据恒真（铁律 13⑨）；少一块则那一块永远不被点 —— 射程静默变短。
	var c14: bool = e14.is_empty() and tiles14.size() >= 3 \
		and covered14.size() == tiles14.size()
	checks.append(["⑭ 对战方式行：点一块恰好亮那一块｜走真实回调", c14,
		"覆盖 %s · 异常 %d 处 %s" % [str(covered14), e14.size(), str(e14.slice(0, 3))]])

	# ---- ⑮ 页面原生按钮的**主题接线**（2026-10-15）----
	#   ★★ 用户口令：「esc界面还没有用上主题色、**设置按钮等大多数按钮也没有用上主题色**」。
	#     这一类错的形态是**静默**的：按钮还在、还能点、文字也对，只是颜色还是引擎默认主题的灰
	#     —— 没有任何几何判据看得见它（①~⑭ 全都量瓷砖与布局，量不到上面这层原生控件的配色）。
	#   ★ 与 `--esctest` 的分工（铁律 §11 探针/判据/目检三分工）：那条量的是 **ESC 面板自己**
	#     （底色/标题/正文的对比度），本条量的是**四个页面 + ESC 面板里的按钮接线**
	#     —— 判据射程不同，两条都要。
	#   ★★ 走**真实控件树**（从页面根递归），不读任何成员表：读成员表是"自己人给自己人打分"
	#     （按钮没建出来/没接上照样能读到）。新加按钮只要落在页面根之下就**自动进入本判据**
	#     —— 这才是"加按钮忘了接样式"会被逮住的原因。
	#   ★★★ 明度档必须扫**两档**（1.0 与 0.6）：按钮的样式是在**建页那一刻**用当时的
	#     `page_surface()` 算好的，而"传错表面"（传裸 `bg_color` 而漏乘明度档）在明度 = 1.0 时
	#     **与正确实现逐位相同** ⇒ 只扫默认档的话这条判据对它恒真。0.6 是那个错的照妖镜。
	var audit_bad: Array[String] = []
	var audit_total: int = 0
	var audit_themed: int = 0
	var audit_flats: int = 0
	var audit_forms: Dictionary = {}
	var au_worst_surf: float = 999.0
	var au_worst_surf_who: String = ""
	var au_worst_text: float = 999.0
	var au_worst_text_who: String = ""
	# 输入框那一族（阈值与"面/底"不同，各自单列 —— 铁律 §14）
	var in_total: int = 0
	var in_worst_text: float = 999.0
	var in_worst_text_who: String = ""
	var in_worst_ph: float = 999.0
	var in_worst_ph_who: String = ""
	# ★★ 四处控件树的审计结果先**收进数组**，循环之后再统一记账。
	#   为什么不用一个累加用的 lambda：**GDScript 的 lambda 按值捕获局部变量**
	#   （`rules.md` §91~95 记过账）⇒ `audit_total += …` 改的是 lambda 自己的副本，
	#   外面那个变量**一个字节都不会动**，而且不报错 —— 症状是判据永远看到 0 个按钮。
	var audits15: Array = []
	var inaudits15: Array = []
	var br_bak15: float = GameConfig.bg_brightness
	var page_roots: Array = [
		[PAGE_SETTINGS, "设置页"], [PAGE_RECORDS, "棋谱页"], [PAGE_LOBBY, "对弈页"],
	]
	for br15 in [1.0, 0.6]:
		GameConfig.bg_brightness = br15
		for pr15 in page_roots:
			var pg15: int = int(pr15[0])
			var tag15: String = "%s(明度%.1f)" % [str(pr15[1]), br15]
			# ★ 必须**重建页面**再审计：样式是建页时套上的，复用上一轮的控件树就量不到
			#   "这一档明度下建出来的是什么"（而这正是本判据要量的东西）。
			_set_page(pg15)
			if _page != pg15:
				audit_bad.append("%s：页面进不去（分派断了，见 ⑥a）" % tag15)
				continue
			var rt15: Control = null
			if pg15 == PAGE_SETTINGS:
				rt15 = _settings_root
			elif pg15 == PAGE_RECORDS:
				rt15 = _records_root
			else:
				rt15 = _duel_root
			# ① 页面按钮：表面必须是 `page_surface()`（与 `_draw()` 画的底色同一个真源）
			audits15.append(_themed_button_audit(rt15, [GameConfig.page_surface()], tag15))
			# ①b 同页的**输入框**（棋谱页搜索框 / 对弈页房间号）——与按钮同族但阈值不同。
			#   收进**另一个数组**：两族的返回键不同（按钮有"面/底"，输入框另有一项"占位符/盒"），
			#   混在一个循环里迟早按错键（那读取到的是 null，而 null 参与比较不报错）。
			inaudits15.append(_themed_input_audit(rt15, [GameConfig.page_surface()], tag15))
		# ② ESC 退出确认面板里的按钮：表面必须是 `overlay_surface()`（面板的推导底色）
		#   ⚠️ 它必须放在**同一个明度档循环里**：面板底色是"推到刚好分离"的结果，而目标随
		#     `page_surface()` 变 ⇒ 换档之后面板与按钮**都要重算**（这条一致性只能在这里断）。
		_set_page(PAGE_MAIN)
		_show_quit_confirm()
		audits15.append(_themed_button_audit(_quit_layer, [GameConfig.overlay_surface()],
			"ESC面板(明度%.1f)" % br15))
		_clear_quit_confirm()
	GameConfig.bg_brightness = br_bak15
	_set_page(PAGE_MAIN)
	# 统一记账（循环之后，见上面"不要用 lambda 累加"的注）
	for a15 in audits15:
		audit_total += int(a15["total"])
		audit_themed += int(a15["themed"])
		audit_flats += int(a15["flat_skipped"])
		var fs15: Dictionary = a15["form_skipped"]
		for k15 in fs15.keys():
			audit_forms[k15] = int(audit_forms.get(k15, 0)) + int(fs15[k15])
		audit_bad.append_array(a15["bad"])
		if float(a15["worst_surf"]) < au_worst_surf:
			au_worst_surf = float(a15["worst_surf"])
			au_worst_surf_who = str(a15["worst_surf_who"])
		if float(a15["worst_text"]) < au_worst_text:
			au_worst_text = float(a15["worst_text"])
			au_worst_text_who = str(a15["worst_text_who"])
	for ia15 in inaudits15:
		in_total += int(ia15["total"])
		audit_bad.append_array(ia15["bad"])
		if float(ia15["worst_text"]) < in_worst_text:
			in_worst_text = float(ia15["worst_text"])
			in_worst_text_who = str(ia15["worst_text_who"])
		if float(ia15["worst_ph"]) < in_worst_ph:
			in_worst_ph = float(ia15["worst_ph"])
			in_worst_ph_who = str(ia15["worst_ph_who"])
	# ★ 阴性对照：**没走过样式入口**的按钮必须被判出来（"审计真的能识别未接线"这件事本身要有牙）。
	#   拿一个全新的裸 `Button` 去审 —— 它带着引擎默认主题的 normal stylebox（非 null！），
	#   所以任何"只看 stylebox 存不存在"的写法在这一步会**假绿**；本判据读的是元数据，能咬住。
	var neg_bare: Button = Button.new()
	var neg_a: Dictionary = _themed_button_audit(neg_bare, [GameConfig.page_surface()], "阴性对照")
	neg_bare.free()
	var neg_caught: bool = int(neg_a["themed"]) == 0 and not (neg_a["bad"] as Array).is_empty()
	# ⚠️ 样本数入判据：`total` 必须 ≥ 8（设置3 + 屏幕模式3 + 棋谱5 + 对弈5 …），
	#   否则"一个按钮都没收到"与"全都合格"会印成同一行（铁律 13⑨）。
	#   ★ 表单型子类（勾选框/下拉/取色器）**必须有样本**：不然"排除表把真按钮也排掉了"
	#     这件事本身没有判据看着（`audit_total` 照样够数）。
	#   ★ 输入框同样要有样本（棋谱页搜索框 + 对弈页房间号 × 两档明度 = 4）：
	#     收到 0 个 = 遍历坏了 / 页面没建出来，那与"全都合格"印出来一模一样。
	var c15: bool = audit_bad.is_empty() and neg_caught and audit_total >= 8 \
			and audit_themed == audit_total and audit_flats >= 1 \
			and in_total >= 2 \
			and int(audit_forms.get("CheckBox", 0)) + int(audit_forms.get("CheckButton", 0)) >= 1
	checks.append(["⑮ 页面按钮与输入框的主题接线｜两档背景明度 ×4 处控件树，读控件真实生效值", c15,
		"按钮 %d 个·已主题化 %d·自绘色块跳过 %d·表单控件跳过 %s·输入框 %d 个｜按钮最差 面/底 %.2f(%s) 字/底 %.2f(%s)｜输入框最差 字/盒 %.2f(%s) 占位符/盒 %.2f(%s)｜对照逮住=%s｜异常 %d 处 %s" % [
			audit_total, audit_themed, audit_flats, str(audit_forms), in_total,
			au_worst_surf, au_worst_surf_who, au_worst_text, au_worst_text_who,
			in_worst_text, in_worst_text_who, in_worst_ph, in_worst_ph_who,
			str(neg_caught), audit_bad.size(), str(audit_bad.slice(0, 3))]])

	# ---- ⑯ 原生控件**本体**的主题接线（勾选框 / 开关 / 滑杆 / 滚动条）（2026-10-15）----
	#   ★★ 与 ⑮ 的分工（铁律 §11）：⑮ 量的是"**我们套上去的**样式"（按钮的面/字、输入框的
	#     盒/字/占位符），而它**故意把表单子类排除掉**了（`_form_button_class()` 的排除表）。
	#     本条补的正是被排掉的那一半：勾选框的**方块与勾**、开关的**胶囊与手柄**、滑杆的
	#     **轨道与手柄**、滚动条的**槽与滑块** —— 这些本体全部来自**引擎默认主题的图标与样式盒**，
	#     不在我们的任何样式入口里。没有本条，这一整类"配色没统一"**没有任何判据看着**
	#     （症状就是那 402 个灰方块 + 两根灰滑杆 + 一条灰滚动条）。
	#   ★★ 判据量的是**交给渲染器的像素**：读回每个图标的 `Image` 色档与样式盒底色，
	#     再与真源函数算出的期望**逐档逐位**比。样式函数取错色/把档位映射反了 —— 这里当场红。
	#   ★ 两档明度照旧（理由同 ⑮：`page_surface()` 的错法在明度 1.0 下与正确实现逐位相同）。
	var nb_bad: Array[String] = []
	var nb_total: int = 0
	var nb_icons: int = 0
	var nb_icons_done: int = 0
	var nb_alt2: int = 0
	var nb_fam: Dictionary = {}
	var nb_worst_main: float = 999.0
	var nb_worst_main_who: String = ""
	var nb_worst_dis: float = 999.0
	var nb_worst_dis_who: String = ""
	var nb_worst_alt: float = 999.0
	var nb_worst_alt_who: String = ""
	var nb_worst_alt2: float = 999.0
	var nb_worst_alt2_who: String = ""
	var nb_worst_sb: float = 999.0
	var nb_worst_sb_who: String = ""
	var audits16: Array = []
	var br_bak16: float = GameConfig.bg_brightness
	for br16 in [1.0, 0.6]:
		GameConfig.bg_brightness = br16
		for pr16 in page_roots:
			var pg16: int = int(pr16[0])
			var tag16: String = "%s(明度%.1f)" % [str(pr16[1]), br16]
			# 与 ⑮ 同样**重建页面**再审计：本体样式是在建页那一刻套上的
			_set_page(pg16)
			var rt16: Control = null
			if pg16 == PAGE_SETTINGS:
				rt16 = _settings_root
			elif pg16 == PAGE_RECORDS:
				rt16 = _records_root
			else:
				rt16 = _duel_root
			audits16.append(_themed_native_body_audit(rt16, [GameConfig.page_surface()], tag16))
	GameConfig.bg_brightness = br_bak16
	_set_page(PAGE_MAIN)
	for a16 in audits16:
		nb_total += int(a16["total"])
		nb_icons += int(a16["icons"])
		nb_icons_done += int(a16["icons_done"])
		nb_alt2 += int(a16["alt2_pairs"])
		for k16 in (a16["fam"] as Dictionary).keys():
			nb_fam[k16] = int(nb_fam.get(k16, 0)) + int(a16["fam"][k16])
		nb_bad.append_array(a16["bad"])
		if float(a16["worst_main"]) < nb_worst_main:
			nb_worst_main = float(a16["worst_main"])
			nb_worst_main_who = str(a16["worst_main_who"])
		if float(a16["worst_dis"]) < nb_worst_dis:
			nb_worst_dis = float(a16["worst_dis"])
			nb_worst_dis_who = str(a16["worst_dis_who"])
		if float(a16["worst_alt"]) < nb_worst_alt:
			nb_worst_alt = float(a16["worst_alt"])
			nb_worst_alt_who = str(a16["worst_alt_who"])
		if float(a16["worst_alt2"]) < nb_worst_alt2:
			nb_worst_alt2 = float(a16["worst_alt2"])
			nb_worst_alt2_who = str(a16["worst_alt2_who"])
		if float(a16["worst_sb"]) < nb_worst_sb:
			nb_worst_sb = float(a16["worst_sb"])
			nb_worst_sb_who = str(a16["worst_sb_who"])
	# ★ 阴性对照（第一层）：一个**全新的裸 CheckBox** —— 图标就是引擎默认那张 ⇒ ① 就必须红。
	#   少了它，"没走过样式入口"这条分支永远没被走过（写错了也看不出来）。
	var neg_cb: CheckBox = CheckBox.new()
	var neg_n: Dictionary = _themed_native_body_audit(neg_cb, [GameConfig.page_surface()], "阴性对照")
	neg_cb.free()
	var neg_nb_caught: bool = int(neg_n["total"]) == 1 \
		and int(neg_n["icons_done"]) == 0 and not (neg_n["bad"] as Array).is_empty()
	# ★ 阴性对照（第二层，更有牙）：把**引擎默认的那张图标**用同一条"逐档等于真源"的判据算一遍，
	#   必须**不相等**（它就是灰的）。没有这一层，④ 那段颜色比对里哪怕写成恒真也照样绿。
	var demo_cls: String = ""
	for kf in nb_fam.keys():
		if int(nb_fam[kf]) > 0:
			demo_cls = String(kf)
			break
	var neg_color_caught: bool = false
	if demo_cls != "":
		var d_roles: Dictionary = GameConfig.native_body_roles(demo_cls, GameConfig.page_surface())
		var d_th: Theme = ThemeDB.get_default_theme()
		for kd in d_roles.keys():
			var keyd: String = String(kd)
			if not keyd.begins_with(GameConfig.NATIVE_IC_PREFIX):
				continue
			var icd: StringName = StringName(keyd.substr(GameConfig.NATIVE_IC_PREFIX.length()))
			var t_def: Array = GameConfig.icon_tones(d_th.get_icon(icd, demo_cls))
			if t_def.is_empty():
				continue
			var want_d: Color = (d_roles[keyd] as Array)[0]
			var have_d: Color = (t_def[0] as Dictionary)["color"]
			if absf(have_d.r - want_d.r) > 0.01 or absf(have_d.g - want_d.g) > 0.01 \
					or absf(have_d.b - want_d.b) > 0.01:
				neg_color_caught = true
				break
	# ⚠️ 样本数入判据（铁律 13⑨/§106）：控件 ≥ 10、勾选框 ≥ 8、滑杆 ≥ 2、滚动条 ≥ 1（**内部子节点
	#   也要收得到**——它正是"遍历口径比生产宽"的那条判据）、**手柄/样式盒对比跑了 ≥ 1 对**
	#   （分母为 0 必须红，而不是印个 999.00 看着像"没事"）、**引擎图标一张不落全换过**。
	#   少了这些，"一个控件都没收到"与"全都合格"会印成同一行。
	var c16: bool = nb_bad.is_empty() and neg_nb_caught and neg_color_caught \
			and nb_total >= 10 and int(nb_fam.get("CheckBox", 0)) >= 8 \
			and int(nb_fam.get("HSlider", 0)) >= 2 \
			and int(nb_fam.get("VScrollBar", 0)) + int(nb_fam.get("HScrollBar", 0)) >= 1 \
			and nb_alt2 >= 1 \
			and nb_icons > 0 and nb_icons_done == nb_icons
	checks.append(["⑯ 原生控件本体的主题接线：勾选框/开关/滑杆/滚动条｜两档明度 ×3 页，读回图标像素与样式盒底色", c16,
		"控件 %d 个·按族 %s·引擎图标 %d 张·已重上色 %d·手柄/样式盒对 %d｜主档/面最差 %.2f(%s) 禁用档/面最差 %.2f(%s)｜勾(副档)/本体最差 %.2f(%s) 手柄/样式盒最差 %.2f(%s)｜样式盒/面最差 %.2f(%s)｜对照(裸控件)逮住=%s (引擎灰图标)逮住=%s｜异常 %d 处 %s" % [
			nb_total, str(nb_fam), nb_icons, nb_icons_done, nb_alt2,
			nb_worst_main, nb_worst_main_who, nb_worst_dis, nb_worst_dis_who,
			nb_worst_alt, nb_worst_alt_who, nb_worst_alt2, nb_worst_alt2_who,
			nb_worst_sb, nb_worst_sb_who, str(neg_nb_caught), str(neg_color_caught),
			nb_bad.size(), str(nb_bad.slice(0, 4))]])

	# ---- ⑰ 字体接线（2026-10-15）----
	#   ★★ 用户口令是「统一配色与**字体**应用」，而 ①~⑯ 量到的全是颜色与几何 —— 字体一条都没有。
	#     这一类的坏法是**静默**的：字体文件缺 `.import` ⇒ `ResourceLoader.exists()=false` ⇒
	#     `load_fonts()` 按既定策略静默退回引擎兜底字体 ⇒ 界面照常显示、判据照常全绿，
	#     只有"字长得不一样"这件事没人管（2026-10-15 实测：三份里有两份没生效，两天无人知）。
	#   ★ 判据读的是**控件真实生效的字体**（`get_theme_font("font")`），不是主题常量：
	#     `ui_theme.build()` 里绑错类型 / 绑错项名时，读常量的写法照样绿。
	#   ★ 两半都要：①**三份字体到位**（缺了就红 —— 补救动作明确：在编辑器里打开一次工程补 `.import`，
	#     或者把字体文件放回去）；②**每个带字控件都真的在用主题字体**（一个都不许是兜底字体）。
	var ft_bad: Array[String] = []
	var ft_total: int = 0
	var ft_body: int = 0
	var ft_display: int = 0
	var audits17: Array = []
	var ft_pages: Array = [[PAGE_MAIN, "首页", null], [PAGE_SETTINGS, "设置页", "settings"]]
	for fp17 in ft_pages:
		var pg17: int = int(fp17[0])
		_set_page(pg17)
		var rt17: Control = _settings_root if int(fp17[0]) == PAGE_SETTINGS else self
		audits17.append(_themed_font_audit(rt17, str(fp17[1])))
	# ★★ ESC 退出确认面板必须**显式**纳入射程：它的根是 `CanvasLayer`，而 `Control` 的主题继承链
	#   **只走 Control 与 Window** —— 夹一层 CanvasLayer 就断（`GameConfig.apply_ui_theme()` 里
	#   挂项目主题正是为了兜住这件事）。这条是本判据第一次跑就逮到的真问题，所以它必须常驻：
	#   ⑮ 那份残留是"碰巧"（`queue_free` 延迟到帧末），这里改成**主动弹一次**。
	_set_page(PAGE_MAIN)
	_show_quit_confirm()
	audits17.append(_themed_font_audit(_quit_layer, "ESC退出确认面板"))
	_clear_quit_confirm()
	var ft_offsrc: int = 0
	for a17 in audits17:
		ft_total += int(a17["total"])
		ft_body += int(a17["body"])
		ft_display += int(a17["display"])
		ft_offsrc += int(a17["offsrc"])
		ft_bad.append_array(a17["bad"])
	# ★ 阴性对照：一个**全新的裸 Label** —— 它没进过任何页面，字体必然是引擎兜底字体 ⇒ 必须被逮住。
	#   少了它，"字体比对"那段写反/写恒真都看不出来。
	var neg_lbl: Label = Label.new()
	var neg_f: Dictionary = _themed_font_audit(neg_lbl, "阴性对照")
	neg_lbl.free()
	var neg_ft_caught: bool = int(neg_f["fallback"]) == 1 and not (neg_f["bad"] as Array).is_empty()
	var ft_ready: bool = UITheme.fonts_ready()
	var ft_report: String = UITheme.fonts_report()
	var c17: bool = ft_bad.is_empty() and ft_ready and neg_ft_caught and ft_offsrc == 0 \
			and ft_total >= 20 and ft_body >= 10 and ft_display >= 1
	checks.append(["⑰ 字体接线：三份字体到位 + 每个带字控件都在用主题字体｜读控件真实生效字体", c17,
		"字体到位 %s（就绪=%s）｜带字控件 %d 个（正文体 %d·展示体 %d·非我方字体 %d）｜对照(裸 Label 必为兜底字体)逮住=%s｜异常 %d 处 %s" % [
			ft_report, str(ft_ready), ft_total, ft_body, ft_display, ft_offsrc,
			str(neg_ft_caught), ft_bad.size(), str(ft_bad.slice(0, 4))]])

	# ---- ⑦ 退出复原：判据跑完必须回到干净状态（切页/切盘都复原）----
	#   ⚰️ 2026-10-16：这里原有"再量一次槽位下标"那一半（⑥c 是逐页量的，这里量
	#      "本轮所有切页折腾完"之后回到首页的那一份）—— `_board_slots` 整族删除后
	#      下标链不存在，那一半随之退役（理由同 ⑥c 的墓碑）。
	#   ⇒ 本条只剩"回首页 + 条目已重建"这两件事。它仍有牙齿：切页折腾之后
	#      `_items` 若没重建（或建出来是空的），后面所有页面相关的判据都会量空集合。
	_set_page(PAGE_MAIN)
	_sel_board = BOARD_PENROSE
	var c7: bool = _page == PAGE_MAIN and not _items.is_empty()
	checks.append(["⑦ 复原：回首页·条目已重建", c7,
		"page=%d items=%d" % [_page, _items.size()]])

	_print_checks("[menutest]", checks)
	var failed: Array = _print_checks("", [])
	var bad: int = 0
	for c in checks:
		if not ((c as Array)[1] is bool and (c as Array)[1]):
			bad += 1
	print("[menutest] 判据 %d 条，失败 %d 条" % [checks.size(), bad])
	print("[menutest] 结论：%s" % ("通过 ✓" if bad == 0 else "失败 ✗ 主菜单布局不对"))
	get_tree().quit()

## 设置页主题预览的迷你棋盘：五块菱形（顶角 72°）绕中心每 72° 一块，拼成五角星
## ——正是彭罗斯「五菱日星」图案。填充=主题棋盘色、描边=主题轮廓色，
## _draw 时直接读 GameConfig，切主题后 queue_redraw 即刷新（背景由外层 bg 色块提供）。
class PreviewBoard extends Control:
	const PIECE_BLACK := Color(0.06, 0.06, 0.08)   # 与 game.gd piece_color_black 默认一致
	const PIECE_WHITE := Color(0.90, 0.90, 0.95)   # 与 game.gd piece_color_white 默认一致
	const CELLS: int = 5
	const ANIM_TIME: float = 0.3     # 与对局盘「悬浮预览 / 落子」那一套的时长口径一致
	## 悬浮预览 + 落子下落 —— ★ 与对局盘**同一套口径**（game.gd：`hover_preview_alpha` /
	## `drop_height_ratio` / `_place_drop_state()`），两个盘的观感才是同一门语言。
	## 关键：悬浮抬高量与下落起点高度是**同一个数**（`_drop_h()`），于是「预览那一格」与
	## 「落下来的那一格」起手逐位相同 —— 由 `--settest` 断言钉死（改一边就红）。
	## ★★ 2026-09-29 用户口令「预览动画侧边改成半透明，预览棋子改成不透明」：
	##   顶面不透明度默认 **1.0**（不透明），厚度感改由 `SIDE_ALPHA` 独立承担。
	const HOVER_ALPHA: float = 1.0   # 悬浮预览顶面的不透明度（= 对局盘 hover_preview_alpha）
	const DROP_RATIO: float = 0.6     # 抬高/下落高度 = 菱形内切半径 × 本值（= 对局盘 drop_height_ratio）
	## 预览块的**侧壁**（厚度感；已取代原来的「对齐虚线」const HOVER_GUIDE_ALPHA）。
	## ★★ 2026-09-29 用户口令「落子预览虚线不好看，改成整个侧边，体现出厚度感」——
	##   口径与对局盘 `hover_side_darken` / `hover_side_alpha` / `hover_foot_line` 同源，
	##   两边观感才是同一门语言。
	## 侧壁色 = **顶面色** darkened(本值)，再按 `SIDE_ALPHA` 半透明。
	const SIDE_DARKEN: float = 0.35      # 侧壁压暗幅度（= 对局盘 hover_side_darken）
	## 侧壁不透明度（= 对局盘 `hover_side_alpha`）。★ 口径变过两次，两次都保留常量：
	##   · 更早被钉成"不透明"，理由是"相邻边侧壁在窄角会重叠、半透明叠两次出深斑"；
	##     实测对凸格子不成立（两侧面只共一条竖棱、面积重叠 0）⇒ 放开成常量。
	##   · 2026-09-29 第一轮「预览动画侧边改成半透明」⇒ 0.5。
	##   · 2026-09-29 第二轮「棋子…要改成**完全不透明**才好」⇒ 回到 **1.0**：
	##     半透明的代价是**真的看得见背后的盘面**（侧壁那圈是混合色）。
	## 取 0 = 侧壁全透明（只剩顶面）；取 1 = 不透明侧壁（当前默认）。
	const SIDE_ALPHA: float = 1.0
	const FOOT_LINE: float = 1.0         # 落点轮廓线宽倍数（= 对局盘 hover_foot_line）
	## 一手提多子时**整段提子过程的总时长上限**（秒）。★ 口径与对局盘 `capture_total_time` 同源：
	##   分层只摊开**起手时刻**，而摊开的总跨度恒为 `本值 - ANIM_TIME`（按层号/最大层号归一化）
	##   ⇒ 串再长，整段也只用这么久。取 `ANIM_TIME` 时跨度为 0 = 所有子同时升空（旧观感）。
	const CAPTURE_TOTAL_TIME: float = 0.75
	## 星形菱形「内切半径 / 臂长」。菱形对角线 2a / 2b（b = a·tan36°）→ r = ab/√(a²+b²)
	## = a·tan36°/√(1+tan²36°) = 0.5878a。对局盘那侧用的是 `_min_tile_r`（同为内切半径），
	## 换成同一量纲两边的高度口径才可比。
	const ARM_R_RATIO: float = 0.5878
	## 图模式圆棋子**占"相邻落子点间距"的比例**（子径 = 间距 × 本值）。
	## ★ 见 `_round_r` 的注释：对局盘间距不匀、按最小值取就够；星形五间距全相等，
	##   取 1.0 会相切成圆团 ⇒ 收一档，落在围棋子径/格距的惯常比例（0.85~0.95）里。
	const ROUND_FILL: float = 0.86
	## 预览盘**外扩比例**（pad = 臂长 a × 本值）。
	## ★ 2026-10-20 用户口令「棋盘大小有点超出窗口了，边界改成现在的一半大就行」之后，
	##   对局盘的 `board_panel_pad` 26 → 13（pad / 棋盘宽 ≈ 0.022）；本条跟着减半对齐，
	##   否则预览的盘边会比真实对局**宽一倍**，设置页看到的是个"不一样的盘"
	##   （用户随即报「设置页预览棋盘忘了改」）。
	## ★ 顺带修掉一个裁切：以前 pad = 0.16a ≈ 12px 而四周只留 `m = 6` ⇒ 盘的上下左右
	##   各被 Control 裁掉约 6px；现在 pad = 0.08a ≈ 6px 且 `_rebuild_polys()` 的分母
	##   把 2×pad 算进去了 ⇒ **盘恒在 Control 内**，与对局盘"pad 计入缩放边距"同一条思路。
	const PANEL_PAD_RATIO: float = 0.08
	var _marks: Array[int] = []      # 每格：0=空 1=黑 2=白
	var _turn: int = 1               # 下一手颜色（1 黑 / 2 白）
	var _fade: Dictionary = {}       # 动画：id -> {"t":剩余, "dur":总长, "in":是否落子渐显, "col":1/2}
	var _polys: Array[PackedVector2Array] = []   # 每格多边形（命中测试用，_rebuild_polys 重算）
	var _line_w: float = 1.6
	var _arm: float = 0.0            # 星形臂长 a（_rebuild_polys 里算；下落高度由它换算）
	## 每格**中心**（= 落子点）。图模式的三样东西都靠它：网格顶点、圆棋子圆心、领地/悬浮定位。
	var _centers: Array[Vector2] = []
	## 图模式**圆棋子半径** = 相邻落子点间距的一半 × `ROUND_FILL`。
	## ★ 量纲与对局盘「直径 = 全盘最近落子点间距」**同一个口径**：星形里五个菱形首尾共边，
	##   两中心分居共享边两侧 ⇒ 中心距 = 2×内切半径 = `2a·sin36°`，所以"间距的一半"就是
	##   `a * ARM_R_RATIO`（实测坐标核对：菱形 k 与 k+1 的共享边端点逐位相同）。
	## ★★ 但要再乘 `ROUND_FILL` 缩小一档，理由**不是**照抄对局盘就能对：
	##   对局盘的落子点间距**不匀**（实测 54.6~88.4px），按最小值取直径时只有最密那几对相切、
	##   其余方向留缝，网格照样看得见；而星形的 5 个间距**完全相等**（正五边形环），
	##   照搬 1.0 会让五颗子**两两相切成一个圆团**、网格线被彻底盖住
	##   —— 实测第一版就是 1.0，三颗子叠成一坨，认不出是棋盘。
	##   取 0.86 落在围棋"子径 ≈ 格距 0.85~0.95"的惯常比例里，缝隙刚好露出网格。
	var _round_r: float = 0.0
	var _hover: int = -1             # 鼠标悬浮的格子（-1 = 不在任何格上）

	## 五块菱形（顶角 72°）绕中心每 72° 一块 → 五角星。几何单独抽出来：
	## 绘制与点击命中测试共用同一份多边形，自检（--settest）也能直接调用。
	func _rebuild_polys() -> void:
		# 尖朝上的五角星外接范围：纵向 = 上尖 2a + 下两尖 1.618a = 3.618a；横向 = ±1.902a = 3.804a。
		# 据此定 a 并把星形垂直居中（按直径 2a 定尺寸会上下裁切）。
		# ★ 分母里的 `2.0 * PANEL_PAD_RATIO`：盘的左右/上下各要外扩 pad = a*本值，
		#   而盘是以**星形包围盒**为基准算的 ⇒ a 必须按"星形 + 两侧盘边"来定，
		#   否则盘会被 Control 裁掉一条边（见 PANEL_PAD_RATIO 的注释）。
		var m := 6.0
		var a := minf((size.x - 2.0 * m) / (3.804 + 2.0 * PANEL_PAD_RATIO),
			(size.y - 2.0 * m) / (3.618 + 2.0 * PANEL_PAD_RATIO))
		var b := a * tan(PI / 5.0)                          # 半短对角线 = a·tan36°（顶角 72°）
		var top := (size.y - 3.618 * a) * 0.5               # 星形整体垂直居中（左栏很高，贴顶会留大片空）
		var c := Vector2(size.x * 0.5, top + 2.0 * a)       # 中心距上尖 2a
		_line_w = maxf(1.6, a * 0.028)                      # 轮廓线随星形放大，大图下才不显细
		_arm = a                                            # 下落/悬浮高度按臂长换算（见 ARM_R_RATIO）
		_round_r = a * ARM_R_RATIO * ROUND_FILL          # 图模式圆棋子半径（见成员注释）
		_polys.clear()
		_centers.clear()
		for k in CELLS:
			var dir := Vector2(cos(-PI / 2.0 + k * TAU / 5.0), sin(-PI / 2.0 + k * TAU / 5.0))
			var perp := dir.orthogonal()
			# 中心 = 顶点平均 = c + a*dir（四个顶点两两对称，平均恰好落在臂中点）
			_centers.append(c + a * dir)
			_polys.append(PackedVector2Array([
				c,
				c + a * dir + b * perp,
				c + 2.0 * a * dir,
				c + a * dir - b * perp,
			]))

	func _draw() -> void:
		_rebuild_polys()
		if _marks.size() != CELLS:
			_marks.resize(CELLS)
		var base := GameConfig.board_color
		# ⓪ 棋盘「盘」：与对局盘**同一套画法**（`board_panel.gd::BoardPanel`）。
		#   为什么要同步：设置页预览的存在意义就是"**所见即对局所得**" ——
		#   对局盘加了托盘而预览还是光板，用户在设置页看到的就不是他真正会得到的东西
		#   （2026-10-20 用户口令「别忘了同步设置页预览效果」）。
		#   ★ 参数**不共用**：星形只有几百像素宽，直接套对局盘的 26px pad 会把格子吃掉一半
		#     ⇒ pad / 厚度都按臂长 `_arm` 换比例（两边 pad/盘宽 都 ≈ 0.04，观感一致）。
		#   ★ 盘面色照抄底板色（`base` = 主题棋盘色）⇒ 盘与格子连成一片，与对局盘同构。
		var star_pts := PackedVector2Array()
		for k in CELLS:
			for p in _polys[k]:
				star_pts.push_back(p)
		var pv_edge: Color = GameConfig.line_color
		pv_edge.a = minf(pv_edge.a + 0.25, 1.0)
		BoardPanel.draw(self, BoardPanel.shape(star_pts, maxf(_arm * PANEL_PAD_RATIO, 4.0)),
			base, maxf(_arm * 0.05, 2.0), pv_edge, _line_w * 1.4)
		if GameConfig.graph_mode:
			# ①' **图模式：网格** = 五个落子点连成环。星形五块菱形绕中心**首尾共边**
			#     （菱形 k 与 k+1 的共享边端点逐位相同，a=1/b=tan36° 代入即得）
			#     ⇒ 邻接就是一个五元环、每点度数 2，与对局盘"落子点两两连线"是同一条规则
			#     在 5 格上的退化形态。
			#     ★ 图模式**没有底板这一步**：棋子是圆不是整块面，抬离时露出来的就是 ⓪ 铺好的盘，
			#       不存在"漏出一块空档"的问题（那条坑是面模式整块染色专属的）。
			var gl: Color = GameConfig.line_color
			for k in CELLS:
				draw_line(_centers[k], _centers[(k + 1) % CELLS], gl, maxf(_line_w * 1.2, 1.6))
		else:
			# ① 底板：**每一格先按棋盘色铺一遍**（与对局盘同构 —— 那边瓷砖底色也是先全画，
			#    棋子再叠上去）。⚠️ 这一步不能省（**面模式**）：棋子落下时是被**抬离**格子的
			#    （偏移 + 半透明），若每格只画一次，它腾出来的那块位置就什么也没画
			#    → 直接从背后面板漏出一块空档，看着就是「落下过程中棋盘缺了一块 / 消失了」
			#    （2026-09-29 用户报的正是这个）。
			for k in CELLS:
				_draw_cell(_polys[k], base, Vector2.ZERO)
		# ② 棋子 / 提子升空 / 落子下落：叠在底板之上（空格只靠底板，跳过）。
		#    ★★ 同样**分两遍**，判据是「**离不离位**」：离位的棋子（下落的那一手、
		#    向上升空散尽的提子）必须**压在所有棋子之上** —— 按格子序号一遍画完时，
		#    落点序号小于某块旧棋子就会被它盖住（= 落子被已有棋子遮挡，2026-09-29 用户报的
		#    同一个毛病）；提子自 2026-09-29 起会**向上升出本格**，必然压到上方邻格，同理。
		#    列在原格的棋子与邻格不重叠（格子互不重叠），所以挪到最后画逐像素等价 ——
		#    唯一有重叠的只有"停在空中"那一段。
		# ②a 落定在原格的棋子（位置不动，按序号画即可）
		for k in CELLS:
			if _fade.has(k) or _marks[k] == 0:
				continue
			var fill := PIECE_BLACK if _marks[k] == 1 else PIECE_WHITE
			_paint_stone(k, fill, Vector2.ZERO)
		# ②b **离位**的棋子：正在下落的那一格 + 正在升空淡出的提子那一格，最后画。
		#    ★★ 2026-09-29 用户口令「**落子时保留侧边厚度**」：它与悬浮预览**共用**
		#    `_block_side_walls()` / `_side_color_for()` —— 于是"预览（有厚度的板）→
		#    落下（一路有厚度，落到地面时侧面高度自然归零）"是连续的，而不是
		#    "预览一块板、落下来一张纸"。侧壁色从**顶面色**派生 ⇒ 提子淡出时墙裙跟着淡，
		#    不会剩下一圈没有顶面的空壳。
		for k in CELLS:
			if not _fade.has(k):
				continue
			var f2: Dictionary = _fade[k]
			var p2 := 1.0 - clampf(f2["t"] / f2["dur"], 0.0, 1.0)
			# 落子走下落曲线（起手状态 = `_hover_state()`，逐位相同的不变量由 --settest 断言）；
			# 提子走 `_fade_state()`（与对局盘 `_capture_fade_state()` 同源）。
			var st: Dictionary = _drop_state(p2) if bool(f2["in"]) else _fade_state(p2)
			var fill2: Color = PIECE_BLACK if f2["col"] == 1 else PIECE_WHITE
			fill2.a *= st["alpha"]
			var o2: Vector2 = st["off"]
			# 侧壁是**面模式专属**：圆棋子没有"板"的厚度（对局盘图模式的落子也是纯圆 + 位移）。
			if o2 != Vector2.ZERO and not GameConfig.graph_mode:
				var w2: Color = _side_color_for(fill2)
				for q in _block_side_walls(k, o2):
					draw_colored_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), w2)
			_paint_stone(k, fill2, o2)
		# ③ 悬浮预览（压在网格线上，模拟「浮在盘面上方的一块有厚度的板」）：
		#    **侧壁 → 落点轮廓 → 顶面**。已取代原来的「鬼影 + 对齐虚线」——
		#    2026-09-29 用户口令「落子预览虚线不好看，改成整个侧边，体现出厚度感」。
		#    星形里格子紧邻、预览块一抬高就压到邻格上方，而**侧壁的底边就是落点轮廓**，
		#    "它到底会落到哪一格"由厚度本身回答（比虚线更硬），不再需要额外画线。
		#    ⚠️ 顺序不能反：侧壁先画、**轮廓在顶面之前**、顶面最后压上去。
		#    ★★ 轮廓不能画在顶面**之后**（2026-09-29 第二轮用户报「**白子**预览时仍能看到
		#       其后的棋盘边界」）：预览块是**抬离**的，"落点那一圈"的**上边**正好落进抬起来的
		#       顶面内部 ⇒ 白棋子面上多一道横线。实测取样（对局盘同款几何，work/preview_leak.py）：
		#         白鬼影：轮廓压在白顶面上 (171,171,180) vs 顶面 (230,230,242) ⇒ 差 **59**（可见）
		#         黑鬼影：同一条       ( 11, 11, 15) vs 顶面 ( 15, 15, 20) ⇒ 差 **4**（看不见）
		#       —— 差 15 倍，正是"白子尤为明显"的原因。改成"轮廓先画"，顶面把它盖住即可，
		#          "会落到哪一格"的外沿信息一字不少。见结构守卫 **S14**（对局盘是 S13）。
		if _hover_visible():
			var hs: Dictionary = _hover_state()
			var hbase: Color = PIECE_BLACK if _turn == 1 else PIECE_WHITE
			# ③a/③b 侧壁 + 落点轮廓：**面模式专属** —— 它们表达的是"一块有厚度的板悬在上面"。
			#   图模式抬起头来的是一颗**圆棋子**（与对局盘 `_draw_graph_hover()` 同貌），
			#   既没有板、也没有"落点轮廓"可言：圆落在哪个落子点上，由圆心自己回答。
			if not GameConfig.graph_mode:
				# ③a 侧壁：棋子色暗面（厚度感来源）。必须先画：顶面压上去，
				#     只露出"墙裙"那一圈 —— 正是一块板看过去的样子。
				var hwall: Color = _hover_side_color()
				for q in _hover_side_walls():
					draw_colored_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), hwall)
				# ③b 落点轮廓：侧壁底边那一圈加一道硬边，"会落到哪一格"不用眼力猜。
				#     **画在顶面之前** ⇒ 落进顶面内部的那段被不透明顶面盖住（见上面的实测）。
				if FOOT_LINE > 0.0:
					var foot: Color = hwall.darkened(0.25)
					var fp: PackedVector2Array = _polys[_hover]
					for k in fp.size():
						draw_line(fp[k], fp[(k + 1) % fp.size()], foot,
							maxf(1.0, _line_w * FOOT_LINE))
			# ③c 顶面：棋子色（`HOVER_ALPHA`，默认不透明），与下落起手逐位相同 —— **必须最后画**。
			var hc: Color = hbase
			hc.a = hs["alpha"]
			_paint_stone(_hover, hc, hs["off"])

	## **任意一格**的侧壁几何：把「格子的每条边」竖直拉到 `off` 之前的那个位置。
	## 返回 `[[抬高后的边的起点, 抬高后的边的终点, 落点边的终点, 落点边的起点], ...]`（与顶点同序）。
	## ★★ 抽成"带下标 / off 参数"的通用函数是 2026-09-29 用户口令「**落子时保留侧边厚度**」
	##   带来的：厚度此前只有悬浮预览有，真正落下来的那一手与升空散尽的提子都只是平铺的一块面
	##   —— 观感上是"预览是有厚度的板，落下来却变成一张纸"。现在三处共用本函数。
	## ★ `off` 归零 ⇒ 侧面高度为 0、面积 0，自动消失（不需要额外判"落地了就不画"）。
	func _block_side_walls(i: int, off: Vector2) -> Array:
		var out: Array = []
		if i < 0 or i >= _polys.size():
			return out
		var pts: PackedVector2Array = _polys[i]
		var n := pts.size()
		for k in n:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % n]
			out.append([a + off, b + off, b, a])
		return out

	## 预览块的侧壁几何（= 该格的侧壁、抬高量取预览位移）。
	## ★ `_draw()` 与 `--settest` 共用本函数 —— 自检断言的就是这套几何（改这里必红）。
	## ★ 口径与对局盘 `_hover_side_walls()` 同源，两边观感是同一门语言。
	func _hover_side_walls() -> Array:
		if not _hover_visible():
			return []
		return _block_side_walls(_hover, _hover_state()["off"])

	## **一块格子的侧壁色**：从它自己的**顶面色**派生 —— 压暗 + 按 `SIDE_ALPHA` 半透明，
	## 且透明度**跟着顶面的透明度走**（`top.a` 是乘数）。
	## ★ 为什么"跟着顶面走"这条关系必须成立：提子升空时顶面一路淡出，若侧壁恒不透明，
	##   最后一帧会剩下一圈**没有顶面的墙裙**（看着像块空壳）；顶面淡、侧壁一起淡才干净。
	## ★★ 顶面色是**唯一入口**：`_hover_side_color()` 与 `_draw()` ②b（下落 / 提子）都走这里。
	func _side_color_for(top: Color) -> Color:
		var w: Color = top.darkened(SIDE_DARKEN)
		w.a = clampf(SIDE_ALPHA * top.a, 0.0, 1.0)
		return w

	## 悬浮预览的侧壁颜色 —— `_draw()` 与 `--settest`「厚度可辨 / 半透明」**共用本函数**。
	## ★★ 为什么必须抽出来：这条判据原先在自检里**自己另算了一遍** `hbase.darkened(SIDE_DARKEN)`，
	##   于是把实现改成 `darkened(0.0)`（厚度感消失）时，判据手里的"参考答案"还是常量 0.35
	##   ⇒ **照旧全绿**（2026-09-29 阴性对照 N8 实测：唯一一条没牙齿的）。判据必须读**实现本身**
	##   —— 这正是 §"单一真源"那条纪律：自检另抄一份公式 = 没测那条公式。
	## ★ 顶面色要先按预览透明度常量打折再交给 `_side_color_for()` —— 于是
	##   「顶面调淡 ⇒ 侧壁跟着淡」这条关系在预览上也成立，而不是写死一个 alpha 常量。
	func _hover_side_color() -> Color:
		var base: Color = PIECE_BLACK if _turn == 1 else PIECE_WHITE
		base.a = _hover_state()["alpha"]
		return _side_color_for(base)

	## 画一颗棋子的**形象** —— 两套画法在这里**唯一分叉**。
	##   · 面模式：整块菱形染色 + 轮廓（`_draw_cell`）；
	##   · 图模式：**圆**，圆心 `_centers[k]`、半径 `_round_r`，走 `BoardPanel.round_stone()` ——
	##     与对局盘**同一个实现**，描边宽度/同色压暗/alpha 跟随这些细节不会再各漂一份。
	## ★ `off` 对两边都是"整颗抬离"，语义一致（下落 / 提子升空 / 悬浮）。
	## ★ 调用点只有三处，与对局盘的两遍画序一一对应（落定 / 离位 / 悬浮）。
	func _paint_stone(k: int, fill: Color, off: Vector2) -> void:
		if k < 0 or k >= _centers.size():
			return
		if GameConfig.graph_mode:
			BoardPanel.round_stone(self, _centers[k] + off, fill, _round_r)
		else:
			_draw_cell(_polys[k], fill, off)

	## 画一格（多边形填充 + 轮廓）。`off` = 抬高位移（悬浮/下落用），零位移时直接原地画。
	func _draw_cell(pts: PackedVector2Array, fill: Color, off: Vector2) -> void:
		var moved := pts
		if off != Vector2.ZERO:
			moved = PackedVector2Array()
			for p in pts:
				moved.push_back(p + off)
		draw_colored_polygon(moved, fill)
		var closed := PackedVector2Array(moved)
		closed.append(moved[0])
		draw_polyline(closed, GameConfig.line_color, _line_w, true)

	## 悬浮预览的抬高量 = 落子下落的起点高度（**同一个数**，别各写一份）。
	func _drop_h() -> float:
		return maxf(4.0, _arm * ARM_R_RATIO * DROP_RATIO)

	## 落子下落的瞬时状态：`k` = **已过**比例 0→1（0 = 刚点下、还在空中；1 = 已落定）。
	## 公式与对局盘 `_place_drop_state()` 逐字同源（`1-tt²` 加速下落、透明度**线性**涨到实心）。
	func _drop_state(k: float) -> Dictionary:
		var tt := clampf(k, 0.0, 1.0)
		return {
			"off": Vector2(0.0, -_drop_h() * (1.0 - tt * tt)),
			"alpha": lerpf(HOVER_ALPHA, 1.0, tt),
		}

	## 提子消散的瞬时状态：`k` = **已过**比例 0→1（0 = 刚被提、棋子还在原格；1 = 已升空散尽）。
	## 公式与对局盘 `_capture_fade_state()` 逐字同源 —— 2026-09-29 用户口令
	## 「把提子也改成向上平移淡出」：与落子成**镜像**（落子从上方落下 + 由淡转实，
	## 提子**向上升走** + 由实转无），高度复用**同一个** `_drop_h()`（提子终点 == 落子起点）。
	## ★ 缓动取先快后慢 `1-(1-t)²`，**不是**下落曲线的时间反演：反演会把位移全挤进最后 30%，
	##   而那时 alpha 已经 ≈0.2 ⇒ 肉眼只剩"原地淡出"，等于没平移（`--settest` 钉死
	##   「半途至少走完 40% 行程」）。
	func _fade_state(k: float) -> Dictionary:
		var tt := clampf(k, 0.0, 1.0)
		var back := 1.0 - tt
		return {
			"off": Vector2(0.0, -_drop_h() * (1.0 - back * back)),
			"alpha": 1.0 - tt,
		}

	## 悬浮预览的位移与不透明度。★ 必须**逐位等于** `_drop_state(0.0)` —— 这是
	## 「落子就是这块预览往下落」的全部内容，由 `--settest` 交叉断言。
	## 故意**不**写成 `_drop_state(0.0)` 的转发：那样「两边一致」就成了废话（同一个函数），
	## 谁改了下落曲线都不会被发现。两条表达式各写一份、由自检钉在一起，才叫不变量。
	func _hover_state() -> Dictionary:
		return {"off": Vector2(0.0, -_drop_h()), "alpha": HOVER_ALPHA}

	## 此刻是否该显示悬浮预览（`_draw()` 与 `--settest` 共用 ⇒ 自检测的是真门槛）。
	func _hover_visible() -> bool:
		return _hover >= 0 and _hover < CELLS and _can_place(_hover)

	## 试摆：点空格落子（黑先、黑白交替），点已有子则提回（轮次退回该色）；
	## 鼠标移动则更新悬浮预览格（与对局盘同一套交互语言）。
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _polys.size() != CELLS:
				_rebuild_polys()      # 尚未绘制过（headless 下可能没走 _draw）也能命中
			var h := -1
			for i in _polys.size():
				if Geometry2D.is_point_in_polygon(mm.position, _polys[i]):
					h = i
					break
			if h != _hover:           # 变了才重绘：每帧都重绘白烧 GPU
				_hover = h
				queue_redraw()
			return
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if _polys.size() != CELLS:
			_rebuild_polys()          # 尚未绘制过（headless 下可能没走 _draw）也能命中
		if _marks.size() != CELLS:
			_marks.resize(CELLS)
		for i in _polys.size():
			if Geometry2D.is_point_in_polygon(mb.position, _polys[i]):
				if _marks[i] == 0:
					_place(i)          # 落子（含提掉对方无气块、自杀手判定）
				else:
					_lift(i)           # 手动提回（试摆撤销）
				queue_redraw()
				accept_event()
				return

	## 鼠标移出预览盘 → 收掉悬浮鬼影（没有 motion 事件来纠正它了）
	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
			_hover = -1
			queue_redraw()

	## 邻接：五菱星里相邻两块共享一条从中心出发的辐条 → 5 个格子首尾相接成一个环。
	func _neighbors(i: int) -> Array[int]:
		return [(i + 1) % CELLS, (i + CELLS - 1) % CELLS]

	## 同色连通块的气 = 相邻空点的个数（去重）
	func _group_libs(start: int, color: int) -> int:
		if _marks[start] != color:
			return 0
		var seen := {}
		var stack: Array[int] = [start]
		var libs := {}
		while not stack.is_empty():
			var i: int = stack.pop_back()
			if seen.has(i):
				continue
			seen[i] = true
			for j in _neighbors(i):
				if _marks[j] == 0:
					libs[j] = true
				elif _marks[j] == color and not seen.has(j):
					stack.append(j)
		return libs.size()

	## 这一手是否成立（空点 + 落子后本方串有气，或能提掉对方无气块）。
	## ★ `_place()` 与悬浮预览**共用同一个判据** —— 否则会出现「预览亮着、点下去没反应」
	## （与对局盘 `_place_block_reason()` / `can_place_at()` 同一条纪律）。只读、无副作用。
	func _can_place(i: int) -> bool:
		if i < 0 or i >= CELLS or _marks.size() != CELLS or _marks[i] != 0:
			return false
		var me := _turn
		var opp := 3 - me
		var save: int = _marks[i]
		_marks[i] = me
		var ok := false
		for j in _neighbors(i):
			if _marks[j] == opp and _group_libs(j, opp) == 0:
				ok = true        # 能提到子 → 提掉的点就是我的气
				break
		if not ok:
			ok = _group_libs(i, me) > 0
		_marks[i] = save
		return ok

	## 落子：先判成立（判据与悬浮预览同源），再提掉对方无气的块。
	## ★ 两遍：**先收集**被提的格子（`_collect_group`，只清 marks），再**统一记录动画**
	##   （`_record_captures`，按波前层摊开起手时刻）—— 因为"从哪颗开始提"要先知道**全量**
	##   被提集合才能算层号（同对局盘 `_capture_depths()` 的口径）。
	func _place(i: int) -> void:
		if not _can_place(i):
			return               # 自杀手：预览里不提示，直接不成立
		var me := _turn
		var opp := 3 - me
		_marks[i] = me
		var taken: Array[int] = []
		for j in _neighbors(i):
			if _marks[j] == opp and _group_libs(j, opp) == 0:
				_collect_group(j, opp, taken)
		_record_captures(i, taken, opp)
		_fade[i] = {"t": ANIM_TIME, "dur": ANIM_TIME, "in": true, "col": me}
		_turn = opp

	## 收集一整块被提的格子（连同色连通块），并立刻清空 marks。**不写动画**（见 `_place()`）。
	func _collect_group(start: int, color: int, out: Array[int]) -> void:
		var stack: Array[int] = [start]
		var seen := {}
		while not stack.is_empty():
			var i: int = stack.pop_back()
			if seen.has(i) or _marks[i] != color:
				continue
			seen[i] = true
			_marks[i] = 0
			out.append(i)
			for j in _neighbors(i):
				if _marks[j] == color:
					stack.append(j)

	## 把被提的格子记成"向上平移淡出"的动画：起手 = 落子动画时长 + **本颗所在波前层**的偏移。
	## ★★ 2026-09-29 用户口令「一次提走多个棋子时，从对方所下棋子旁边的子开始被提走，接着它旁边的子
	##   被提走，依次提完；整个提子过程限制在一定时间内」——口径与对局盘
	##   `place_stone()` 的提子记录**逐字同源**（`_capture_depths()` / `_capture_wave_start()`）。
	func _record_captures(placed: int, ids: Array[int], color: int) -> void:
		if ids.is_empty():
			return
		var depths: Dictionary = _capture_depths(placed, ids)
		var wave_max: int = _capture_wave_max(depths)
		for i in ids:
			var wave: int = int(depths.get(i, 0))
			_fade[i] = {"t": ANIM_TIME, "dur": ANIM_TIME, "in": false, "col": color,
				"delay": ANIM_TIME + _capture_wave_start(wave, wave_max),
				"wave": wave, "wave_max": wave_max}

	## 整段提子过程的**总时长**（含地板：小于单颗时长连一颗都放不完）。
	## ★ 与对局盘 `_capture_total_time()` 同口径；`_capture_wave_start()` 与自检都只能问它。
	func _capture_total_time() -> float:
		return maxf(ANIM_TIME, CAPTURE_TOTAL_TIME)

	## 第 `wave` 层（`wave_max` = 最深层层号）的**起手偏移**（秒，不含"等落子动画"那一段）。
	## ★★ 归一化 `wave / wave_max` = "总时长封顶"的全部关键：第 0 层偏移 0、最深层偏移
	##   `总时长 - 单颗时长` ⇒ 最深层刚好在总时长处散尽，且**与层数无关**。
	##   写成 `spread * wave` 时长就随串长线性爆炸（阴性对照守这一条）。与对局盘逐字同源。
	func _capture_wave_start(wave: int, wave_max: int) -> float:
		if wave_max <= 0:
			return 0.0
		return maxf(0.0, _capture_total_time() - ANIM_TIME) * float(wave) / float(wave_max)

	## 被提的每颗格子离**刚落那一手**有几层（BFS，只在被提集合里搜）。
	## ★ 口径与对局盘 `_capture_depths()` 同源：第 0 层 = 与落点相邻的被提格。
	## ⚠️ 不能靠 `_marks` 判连通 —— `_collect_group()` 已经把子清空了（同那族"复算 board
	##   导致分支不可达"的坑），只能靠 `_neighbors()` + "在不在被提集合里"。
	func _capture_depths(placed: int, ids: Array[int]) -> Dictionary:
		var depth: Dictionary = {}
		if ids.is_empty():
			return depth
		var want: Dictionary = {}
		for i in ids:
			want[i] = true
		var frontier: Array[int] = []
		for i in ids:
			if _neighbors(i).has(placed):
				depth[i] = 0
				frontier.append(i)
		if frontier.is_empty():      # 兜底：宁可"同时提"，也绝不丢下一颗不提（漏动画是静默的）
			for i in ids:
				depth[i] = 0
			return depth
		var d := 0
		while not frontier.is_empty() and depth.size() < ids.size():
			d += 1
			var next: Array[int] = []
			for f in frontier:
				for nb in _neighbors(f):
					if want.has(nb) and not depth.has(nb):
						depth[nb] = d
						next.append(nb)
			frontier = next
		for i in ids:
			if not depth.has(i):
				depth[i] = d
		return depth

	## 本手提子的最深层层号（只提一层时为 0）。
	func _capture_wave_max(depths: Dictionary) -> int:
		var mx := 0
		for v in depths.values():
			mx = maxi(mx, int(v))
		return mx

	## 某颗被提格子**整段动画结束的时刻**（相对"落子动画起手"的时间轴，秒）—— 自检据此断言封顶。
	func _capture_end_time(wave: int, wave_max: int) -> float:
		return ANIM_TIME + _capture_wave_start(wave, wave_max) + ANIM_TIME

	## 手动提回（点已落子的格子）：同样走向上平移淡出，轮次退回被提的那一色。
	## ⚠️ 这里**不加 delay**：它没有"伴随的落子动画"要等（delay 的语义是"等落子动画走完"，
	##    对局盘侧没有这条路径，菜单侧这个交互是独一份）⇒ 点下去立刻开始升空。
	func _lift(i: int) -> void:
		var c: int = _marks[i]
		_marks[i] = 0
		_fade[i] = {"t": ANIM_TIME, "dur": ANIM_TIME, "in": false, "col": c}
		_turn = c

	## 显式开帧处理：内部类也要，否则 _process 不跑 → 落子颜色卡在渐显起点（等于看不见落子）
	func _ready() -> void:
		set_process(true)

	## 逐帧推进落子/提子动画（有动画才重绘，空闲时不额外开销）
	func _process(delta: float) -> void:
		if _fade.is_empty():
			return
		for k in _fade.keys():
			var f: Dictionary = _fade[k]
			# ★ 提子动画**排在落子动画之后**：`delay` 没走完就只推 delay、不动 `t` ——
			#   于是 `t` 一直是满的 ⇒ `_fade_state()` 算出来必然是"原格 + 不透明"
			#   （被提的子先原样停着），delay 归零才开始升空淡出。两段天然串行。
			# ★★ 时间必须**结转**（与对局盘 `_process` 同口径）：一帧的 delta 比剩余 delay 长时，
			#    多出来的那段要落到 `t` 上。写成"直接 continue"会把多余时间整段吞掉 ——
			#    平时一帧 1/60s 看不出来，一次推一大段就会变成"提子永远不动"（对局盘实测踩过）。
			var dt := delta
			var dl := float(f.get("delay", 0.0))
			if dl > 0.0:
				var used: float = minf(dl, dt)
				dl -= used
				dt -= used
				f["delay"] = dl
			f["t"] = f["t"] - dt
			if f["t"] <= 0.0:
				_fade.erase(k)
		queue_redraw()

## 预设切换后刷新预览（避免显示旧值）
func _sync_appearance_controls() -> void:
	_update_appearance_preview()

func _update_appearance_preview() -> void:
	if is_instance_valid(_appr_preview_bg):
		_appr_preview_bg.color = GameConfig.bg_color * GameConfig.bg_brightness
	if is_instance_valid(_appr_preview_board):
		_appr_preview_board.queue_redraw()   # 迷你棋盘自绘时直接读 GameConfig

## 设置页文字颜色随背景明度反转（浅背景→深字，深背景→浅字）
func _refresh_settings_ink() -> void:
	if not is_instance_valid(_settings_root):
		return
	var ink := GameConfig.ink_color()
	var accent := GameConfig.accent_color()
	_apply_ink_recursive(_settings_root, ink, accent)

## 棋谱面板同理。★ 为什么单独一条而不是把两棵树塞进一个循环：
##   两个面板**永远只有一个存在**（切页时另一个已销毁），写成一个循环反而要多处理
##   "其中一个为 null"的情形；但**必须两条都有** —— 只给设置做、漏了棋谱的话，
##   症状是"在棋谱面板里换主题，字还是旧颜色"（而设置面板正常 ⇒ 看着像棋谱面板的 bug）。
func _refresh_records_ink() -> void:
	if not is_instance_valid(_records_root):
		return
	var ink := GameConfig.ink_color()
	var accent := GameConfig.accent_color()
	_apply_ink_recursive(_records_root, ink, accent)


# ====== 自检（--rectest）：棋谱库面板 ======
# ★ 全在**自检盘**（`GameRecord.records_dir()` 在自动化运行下就是 `user://records_selftest`）
#   —— 面板里的每个动作都会落盘，判据绝不能碰玩家的棋谱库。
# ★★ 判据纪律（本轮逐条踩过）：
#   ① **样本非平凡**：先造 3 份"手数/结果/日期都不同"的谱，排序与筛选才有的量；
#      否则在"库里只有 1 条"上跑排序判据，那条判据**恒真**（铁律 27）。
#   ② **严格 vs 非严格**：全表非增/非降（老实说：这条不是恒真 —— 不排序时输入顺序是
#      索引顺序，自然会violate）；而"三条样本的相对次序"要**严格**（铁律 25）。
#   ③ **阴性对照就在同一函数里**：乱串搜索必须 0 条、坏 JSON 必须不增库、
#      不存在的 id 不许污染交接。阳性 + 阴性同屏，免得"只测了会通过的那一半"。
func _records_ui_self_test() -> void:
	var ok: bool = true
	var bad_shape: Array[String] = []
	print("[rectest] === 棋谱库面板自检（自检盘 %s）===" % GameRecord.records_dir())

	# ---- 先清掉**本次自检自己**留下的残留样本 ----
	# ★★ 为什么必须有这一步（2026-10-08 实测）：前三轮自检**中途失败**（脚本错 / 被掐），
	#   样本就永久留在自检盘里 ⇒ 下一轮"搜索 种子1234 命中 9 条（应 3）""筛到 1 条却勾了 3 条"，
	#   **判据在骂的不是代码，是上一轮的尸体**。这类"判据被自己的历史污染"极难查
	#   （本工程已有先例：`judge_replay_hud_layout()` 量到越来越多的按钮）。
	#   ⇒ 判据要**对自己的产物做幂等清理**，认领范围要窄：只删"指纹以 `rectest` 开头"的。
	#   ⚠️ 首版只认**当前**指纹字符串 ⇒ 早先失败那几轮用的是旧指纹（`rectest-fp`），
	#     清理**一条都没认出来**。⇒ 认领口径必须是**前缀**（指纹会改，"这批是我的"不变）。
	#   ⚠️⚠️ 第二版按索引里的 `generator_fingerprint` 去认 —— **索引里压根没有这个字段**：
	#     `GameRecord._index_entry()` 的键是**写死的固定列表**（id/created_at/mode/…/plies），
	#     指纹只存在**完整谱文件**里。⇒ `purged` 恒 0，而且它**不报错**（`get()` 取不到给默认值）。
	#     ★ 这就是"按索引字段认领"的陷阱：索引是**摘要**，任何后来加进谱头的字段都不在里面。
	#     ⇒ 改成两步：① 按 id 里的种子串（`_s1234x`，`make_id()` 把它编进了 id）筛**候选**
	#       （索引里有 id，筛得很便宜）；② 读那份**文件**确认指纹，再删。
	#       两步合起来 = "认得出自己的、且只认自己的"（自检盘是所有自检共用的）。
	# ---- 样本清单（**先声明**：下面的清理段要按它筛候选）----
	#   ⚠️ 声明顺序是**语义**：清理段读 spec ⇐ 所以 spec 必须在清理段之前。
	#     反了 ⇒ `spec` 使用前未定义 ⇒ 整场景编译失败（不是运行期报错）。
	# ★★ 日期与手数**故意反向**（手数最少的日期最新）：
	#   这样"按时间↓"与"按手数↓"给出的**相对次序恰好相反** ⇒ 两条判据互为对照 ——
	#   若排序压根没生效（或两档串了），必有一条红。
	#   ⚠️ 首版把两者**同向**排列，结果两个档位给出同一个次序 ⇒ **两条判据分不开**，
	#     它们只是在比同一个东西（实测：两行都打 true 而"排序"根本没被区分开）。
	var spec: Array = [
		{"days": "03", "plies": 5,  "reason": GameRecord.REASON_SCORE,       "winner": GameRecord.STONE_BLACK, "seed": 12345},
		{"days": "02", "plies": 12, "reason": GameRecord.REASON_RESIGN,      "winner": GameRecord.STONE_WHITE, "seed": 12346},
		{"days": "01", "plies": 30, "reason": GameRecord.REASON_INTERRUPTED, "winner": 0,                       "seed": 12347},
	]
	# ★ 机器对局的样本**刻意不进 `spec`**（2026-10-22）：`spec.size()` 被 ④ 当分母用
	#   （搜「种子1234」要**恰好命中 3 条**），多塞一份进去会当场把那条判据改坏。
	#   种子也**故意避开 1234x 前缀**：`_rec_row_text` 里是"种子%d"，子串匹配下 `种子22349`
	#   不含 `种子1234` ⇒ 但 `种子12345`/`种子12346`… 会与 `种子1234` 互撞，所以新种子选 22349。
	var machine_seed: int = 22349

	var purge_seeds: Array[int] = []
	for s0 in spec:
		purge_seeds.append(int(s0["seed"]))
	purge_seeds.append(machine_seed)
	var purge_cand: Array[String] = []
	for e in GameRecord.list_index():
		if not (e is Dictionary):
			continue
		var pid: String = str((e as Dictionary).get("id", ""))
		for sd in purge_seeds:
			if pid.ends_with("_s%d" % sd):
				purge_cand.append(pid)
				break
	var purged: int = 0
	for pid in purge_cand:
		var prec: Dictionary = GameRecord.load_by_id(pid)
		if str(prec.get("generator_fingerprint", "")).begins_with("rectest"):
			GameRecord.delete_by_id(pid)
			purged += 1
	if purged > 0:
		print("[rectest] （清掉上一轮残留的样本 %d 条 / 候选 %d 条）" % [purged, purge_cand.size()])

	# ---- 造样本：3 份手数/结果/日期都不同的谱 ----
	var made: Array[String] = []
	for s in spec:
		var rec: Dictionary = GameRecord.new_record(GameConfig.LOCAL,
			GameConfig.BOARD_PENROSE, GameConfig.STANDARD, int(s["seed"]), 7,
			REC_SELF_FP, {})
		for k in int(s["plies"]):
			GameRecord.append_move(rec, k, 1 if k % 2 == 0 else 2, 0, -1)
		GameRecord.finish(rec, str(s["reason"]), int(s["winner"]), 1, 2)
		rec["created_at"] = "2026-%s-01 10:00:00" % str(s["days"])
		var p: String = GameRecord.save(rec)
		if p != "":
			made.append(str(rec["id"]))
	# 元判据：样本真的造出来了（不然下面所有"排序/筛选"判据都在空集合上跑）
	if made.size() != spec.size():
		bad_shape.append("样本只造出 %d/%d 份" % [made.size(), spec.size()])

	# ---- 样本②：一份**机器对局**（`kind = KIND_MACHINE`），专给「分类」判据用 ----
	# ★ 双方名用**真引擎名**（磐石/疾风）：这样"列表里认得出是哪两个 AI 打"这件事本身
	#   也能被同一条判据量到（否则分类对了、但列表还显示"本地"，用户照样分不清）。
	var made_m: Array[String] = []
	var rec_m: Dictionary = GameRecord.new_record(GameConfig.LOCAL,
		GameConfig.BOARD_PENROSE, GameConfig.STANDARD, machine_seed, 0,
		REC_SELF_FP, {"black": "磐石", "white": "疾风"}, GameRecord.KIND_MACHINE)
	for k in 4:
		GameRecord.append_move(rec_m, k, 1 if k % 2 == 0 else 2, 0, -1)
	GameRecord.finish(rec_m, GameRecord.REASON_SCORE, GameRecord.STONE_BLACK, 3, 1)
	rec_m["created_at"] = "2026-04-01 10:00:00"
	var p_m: String = GameRecord.save(rec_m)
	if p_m != "":
		made_m.append(str(rec_m["id"]))
	if made_m.size() != 1:
		bad_shape.append("机器对局样本没造出来（分类判据会在空集合上跑）")

	# ---- 进面板（真实路径：`_set_page` 建树，和用户点底栏那块砖同一条）----
	_set_page(PAGE_RECORDS)
	var built: bool = _records_root != null and is_instance_valid(_records_root)
	var n_all: int = _rec_idx.size()

	# ---- ① 面板几何：不压标题、不压底栏（与设置面板同款口径）----
	var top_ok: bool = built and _records_root.position.y >= TOP_MARGIN
	var bot_ok: bool = built and _records_root.get_rect().end.y \
		<= _footer_band().position.y + 0.5
	var c1: bool = built and top_ok and bot_ok
	print("[rectest] ① 面板就位：建树=%s 上沿 %.0f(≥%.0f)=%s 下沿 %.0f(≤%.0f)=%s → %s"
		% [str(built), _records_root.position.y if built else -1.0, TOP_MARGIN, str(top_ok),
			_records_root.get_rect().end.y if built else -1.0,
			_footer_band().position.y, str(bot_ok), "✓" if c1 else "✗"])
	if not c1:
		ok = false

	# ---- ② 列表条数 == min(过滤后条数, 渲染上限)，且样本在列表里 ----
	#   ★ 上限那条**必须一起断**：只断"行数 == 过滤后条数"的话，一旦库里超过上限
	#     它永远红；只断"行数 > 0"又等于没断。
	var flt_n: int = _rec_filtered().size()
	var want_rows: int = mini(flt_n, REC_ROW_CAP) + (1 if flt_n > REC_ROW_CAP else 0)
	var rows_n: int = 0
	if _rec_rows_box != null and is_instance_valid(_rec_rows_box):
		rows_n = _rec_rows_box.get_child_count()
	var c2: bool = built and rows_n == want_rows and _rec_idx.size() >= spec.size()
	print("[rectest] ② 列表：行 %d（过滤 %d 条·上限 %d，含截断提示 %s）·库共 %d 条 → %s"
		% [rows_n, flt_n, REC_ROW_CAP, str(flt_n > REC_ROW_CAP), _rec_idx.size(),
			"✓" if c2 else "✗"])
	if not c2:
		ok = false

	# ---- ②b 有谱则不显示「还没有棋谱」空态（2026-10-09 用户报的 bug）----
	#   ★★ 为什么这条**必需**：`_empty_hint()` 是 `_draw()` 每帧读的**绘制层**真源，
	#     与列表容器里那套「空态 Label」是**两套东西**。原先它无条件返回"还没有棋谱…"，
	#     于是棋谱库**明明有谱**，绘制层还把它画在列表**上方**（两层空态叠加，且都看不见报错）。
	#   ★ 判据读真源：此刻样本已造、已进面板（`_rec_idx` 非空）⇒ `_empty_hint()` 必须返回 `{}`。
	#   ★ 这条和 `--menutest` ⑧（空库时"该有提示"）**互为反方向**：⑧ 守"没谱要提示"、
	#     这条守"有谱别提示"，少一条就有一半裸奔（"有谱还提示"只有这条抓得到）。
	var hint_with_recs: Dictionary = _empty_hint()
	var c2b: bool = built and _rec_idx.size() >= spec.size() and hint_with_recs.is_empty()
	print("[rectest] ②b 有谱不空态：库 %d 条(应≥%d)·`_empty_hint()` 返回%s → %s"
		% [_rec_idx.size(), spec.size(), str(hint_with_recs), "✓" if c2b else "✗"])
	if not c2b:
		ok = false

	# ---- ③ 排序三档 ----
	#   ⚠️ 断言的是**性质**（非增/非降）+ **样本三者的严格相对次序**，
	#      不是自己重写一遍比较器去比 —— 那是"另写一份口径不同的副本"（铁律 31）。
	#   ★ 这一段**只读 `_rec_filtered()`**（纯数据），不重建行：重建一次要造几百个控件，
	#     三条判据各来一次就是白等几秒（首版就是这么把自检拖到跑不完的）。
	var sort_msgs: Array[String] = []
	var c3: bool = true
	# 样本次序读法：`_rec_rel_order` 返回"按 id 顺序各自在列表里的下标"。
	# ★ 两个档位的期望**互为反向**（样本日期与手数故意反向排）：
	#   时间↓ ⇒ 最新在前 ⇒ id0(01-03) 在前、id2(01-01) 在后 ⇒ 下标递增
	#   手数↓ ⇒ 手数最多在前 ⇒ id2(30) 在前、id0(5) 在后 ⇒ 下标递减
	#   ⚠️ 判据用 `strictly increasing / decreasing` 而不是"等于某个具体数字"：
	#     具体数字会随别的自检往库里塞条目而变（实测：同一份代码两次跑，下标从 [0,1,2] 变成
	#     [1063,1060,1057]）—— 那是**判据绑到了库的规模上**，不是判据本身。
	# ③a 时间 ↓：全表 `created_at` 非增 + 样本下标**严格递增**
	_rec_sort = REC_SORT_TIME
	var lst: Array = _rec_filtered()
	var time_mono: bool = true
	for i in range(1, lst.size()):
		if str((lst[i - 1] as Dictionary).get("created_at", "")) \
				< str((lst[i] as Dictionary).get("created_at", "")):
			time_mono = false
	var time_pos: Array = _rec_rel_order(lst, made)
	var time_strict: bool = _rec_strictly(time_pos, true)
	var c3a: bool = time_mono and time_strict
	sort_msgs.append("时间↓ 非增=%s 样本下标=%s(应严格递增)" % [str(time_mono), str(time_pos)])
	# ③b 手数 ↓：全表 `plies` 非增 + 样本下标**严格递减**（与时间档反向 = 互为对照）
	_rec_sort = REC_SORT_PLIES
	lst = _rec_filtered()
	var plies_mono: bool = true
	for i in range(1, lst.size()):
		if int((lst[i - 1] as Dictionary).get("plies", 0)) \
				< int((lst[i] as Dictionary).get("plies", 0)):
			plies_mono = false
	var plies_pos: Array = _rec_rel_order(lst, made)
	var plies_strict: bool = _rec_strictly(plies_pos, false)
	var c3b: bool = plies_mono and plies_strict
	sort_msgs.append("手数↓ 非增=%s 样本下标=%s(应严格递减)" % [str(plies_mono), str(plies_pos)])
	# ③c 结果：全表序键非降
	_rec_sort = REC_SORT_RESULT
	lst = _rec_filtered()
	var res_mono: bool = true
	for i in range(1, lst.size()):
		if _rec_result_key(lst[i - 1] as Dictionary) > _rec_result_key(lst[i] as Dictionary):
			res_mono = false
	var c3c: bool = res_mono
	sort_msgs.append("结果 非降=%s" % str(res_mono))
	c3 = c3a and c3b and c3c
	print("[rectest] ③ 排序三档：%s → %s" % ["｜".join(sort_msgs), "✓" if c3 else "✗"])
	if not c3:
		ok = false
	# 排序按钮文案跟着档位走（回到时间档并刷一次按钮 + 列表）
	_rec_sort = REC_SORT_TIME
	_rec_rebuild_rows()

	# ---- ④ 搜索：阳性（命中 3 条且条条都含）+ 阴性（乱串 0 条）+ 复原 ----
	#   ⚠️ 直接给 `LineEdit.text` 赋值**不会**发 `text_changed`（那是用户编辑才发的）
	#      ⇒ 赋值后必须自己调一次重建，否则判据量到的是"没筛过的列表"（假绿）。
	#   ⚠️ "条数对"与"条条都含词"必须**分开成两个布尔**：首版写成一个变量
	#      （先 `hit.size() == 3` 再逐条查），计数一不对后面那句就永远不执行 ⇒
	#      报出来的信息是"条条含词=false"，把病因指到了错的地方。
	_rec_search.text = "种子1234"
	_rec_rebuild_rows()
	var hit: Array = _rec_filtered()
	var hit_each: bool = not hit.is_empty()
	for e in hit:
		if not _rec_row_text(e as Dictionary).contains("种子1234"):
			hit_each = false
	var hit_n_ok: bool = hit.size() == spec.size()
	_rec_search.text = "绝不可能匹配的串ZZZ"
	_rec_rebuild_rows()
	var miss_n: int = _rec_filtered().size()
	var miss_hint: String = ""
	if _rec_rows_box.get_child_count() > 0:
		# ★★ 守卫必须是「**第一个孩子是不是 Label**」，不是「有没有孩子」（2026-10-08 实测）：
		#   空态那一行是 `_ui_label(...)`（Label）；而有结果时第一个孩子是**行容器 HBox**。
		#   阴性对照 **RC10**（让搜索恒不筛 ⇒ 列表永远非空且是行容器）正是从这里把自检**打断**的：
		#   `(HBox as Label)` → null → `.text` 抛 null 实例错 ⇒ `_records_ui_self_test()`
		#   **中途返回**、末尾的 `quit()` 没走到 ⇒ 菜单场景一直活着 ⇒ 仪器只能报「超时 300s 挂死」。
		#   ★ 教训一：**挂死不是判决**。刀打出来的必须落在"红/绿"上，"挂死"= 这条对照**没跑**，
		#     而它在结果表里和"咬住"长得完全不一样 —— 所以仪器必须有"第四类"（本工程早已有）。
		#   ★ 教训二（更普适）：`get_child_count() > 0` 只保证"有东西"，**不保证"是那个东西"**。
		#     凡 `get_child(i) as T` 都必须**判类型**（`if x is T`），不能拿"非空"代替"类型对"。
		var first_child: Node = _rec_rows_box.get_child(0)
		if first_child is Label:
			miss_hint = (first_child as Label).text
	_rec_search.text = ""
	_rec_rebuild_rows()
	var back_n: int = _rec_filtered().size()
	var c4: bool = hit_n_ok and hit_each and miss_n == 0 and back_n == n_all \
		and miss_hint.contains("没有匹配")          # 空态必须说清"是被搜索筛没的"
	print("[rectest] ④ 搜索：命中 %d(应%d)=%s 条条含词=%s｜乱串 %d(应0)｜清空后 %d(应%d)｜空态提示=%s → %s"
		% [hit.size(), spec.size(), str(hit_n_ok), str(hit_each), miss_n, back_n, n_all,
			miss_hint, "✓" if c4 else "✗"])
	if not c4:
		ok = false

	# ---- ⑤ 全选 / 取消全选 ----
	_rec_select_all(true)
	var n_on: int = _rec_checked_ids().size()
	_rec_select_all(false)
	var n_off: int = _rec_checked_ids().size()
	var c5: bool = n_on == _rec_filtered().size() and n_on >= spec.size() and n_off == 0
	print("[rectest] ⑤ 全选：全选 %d(应%d)｜取消后 %d(应0) → %s"
		% [n_on, _rec_filtered().size(), n_off, "✓" if c5 else "✗"])
	if not c5:
		ok = false

	# ---- ⑥ 搜索状态下勾选只算**列出来的**（防"删掉屏幕上看不见的谱"）----
	#   这是本面板最危险的一处：先全选，再搜到只剩 1 条 ⇒ 勾选数必须也只剩 1。
	_rec_select_all(true)
	_rec_search.text = "种子12345"
	_rec_rebuild_rows()
	var narrow_on: int = _rec_checked_ids().size()
	var c6: bool = narrow_on == 1 and _rec_filtered().size() == 1
	print("[rectest] ⑥ 搜索态勾选：全选后筛到 1 条 → 勾选数 %d（应 1，不是 3）→ %s"
		% [narrow_on, "✓" if c6 else "✗"])
	if not c6:
		ok = false
	_rec_search.text = ""
	_rec_rebuild_rows()
	_rec_select_all(false)

	# ---- ⑥b 分类：全部 / 我的对局 / 机器对局 ----
	# ★ 用户口令（2026-10-22）：「再给棋谱加一个分类的功能，把历史对局和其他的分开」。
	# ★★ 参照物纪律（§70/§110）：期望条数从**条目自己的 `kind` 字段**直数，
	#   **不调** `_rec_kind_of()` —— 那个函数正是被测物（映射 + 过滤）。用它算期望
	#   = 自己问自己：过滤那一半被悍掉时两边一起退化，判据恒绿。
	# ★★ §135（就是本判据首版踩出来的假红）：期望**只数"索引里有 kind 的条目"**是错的 ——
	#   自检盘里 1924 条老谱没有该字段，首版因此报「我的 1927(应3)」，而代码是对的。
	#   老数据的默认口径（缺 kind ⇒ 保守归入「我的」）是**规范的一部分**，不是"不合格"。
	#   ⇒ 期望改成**分区式**（我的 = 全部 - 机器）：既解释了分母里每一条，又不用把
	#     "逐条按 kind 分拣"再抄一遍（省掉一次 §70 违规）；`kind_absent` 只当信息量印出来。
	# ★★ 为什么必须断"样本落在哪一档"而不只断"三个数相等"（§110 的同一根）：
	#   三个档的条数全从 `_rec_idx` 派生 ⇒ 若 `kind` 投影整体丢失，`machine_ids` 变空、
	#   `got_machine` 也是 0 ⇒ **0 == 0 恒绿**，而用户看到的是"机器对局全都变成了我的对局"。
	#   只有"这份机器样本必须在机器档里"这条把两边钉在不同对象上。
	#   （本工程踩过同型一次：`generator_fingerprint` 不在索引投影里，`purged` 恒 0 且不报错。）
	var all_ids: Array[String] = []
	var human_ids: Array[String] = []
	var machine_ids: Array[String] = []
	var kind_absent: int = 0
	for e0 in _rec_idx:
		if not (e0 is Dictionary):
			continue
		var d0: Dictionary = e0
		var id0: String = str(d0.get("id", ""))
		all_ids.append(id0)
		match int(d0.get("kind", -1)):
			GameRecord.KIND_HUMAN:
				human_ids.append(id0)
			GameRecord.KIND_MACHINE:
				machine_ids.append(id0)
			_:
				# 2026-10-22 之前落盘的条目（自检盘里有上千条）没有 kind ⇒ 按保守方向归「我的」。
				# 这里只**记数**不报红：它们不是本轮改动的产物（§71 别把老账记到新改动头上）。
				kind_absent += 1
	var mid: String = str(made_m[0]) if not made_m.is_empty() else ""
	# 磁盘对拍（§13）：机器样本**文件里**的 kind 真的是 MACHINE（不只是索引投影对）
	var disk_kind_ok: bool = false
	if mid != "":
		var dr: Dictionary = GameRecord.load_by_id(mid)
		disk_kind_ok = int(dr.get("kind", -1)) == GameRecord.KIND_MACHINE
	# 样本分档：机器样本进机器档，三份人机样本进我的档（两边都要占住）
	var sample_split: bool = mid != "" and machine_ids.has(mid)
	for h0 in made:
		if not human_ids.has(str(h0)):
			sample_split = false
	# 交互面：**真按按钮**绕一圈（不是直改 `_rec_kind`），逐档量条数并核对按钮字
	var btn_present: bool = _rec_kind_btn != null and is_instance_valid(_rec_kind_btn)
	_rec_kind = REC_KIND_ALL
	if btn_present:
		(_rec_kind_btn as Button).text = REC_KIND_LABELS[_rec_kind]
	_rec_rebuild_rows()
	var got_all: int = _rec_filtered().size()
	var got_human: int = -1
	var got_machine: int = -1
	var label_ok: bool = btn_present
	var cycled_back: bool = false
	if btn_present:
		for _i in REC_KIND_COUNT:
			(_rec_kind_btn as Button).pressed.emit()
			if (_rec_kind_btn as Button).text != REC_KIND_LABELS[_rec_kind]:
				label_ok = false
			if _rec_kind == REC_KIND_HUMAN:
				got_human = _rec_filtered().size()
			elif _rec_kind == REC_KIND_MACHINE:
				got_machine = _rec_filtered().size()
		cycled_back = _rec_kind == REC_KIND_ALL
	# 阴性 + 阳性成对（§110）：同一条搜索串
	#   阴性 = 在「我的对局」档下**搜不到**机器样本；
	#   阳性 = 在「机器对局」与「全部」档下**各命中 1 条**。
	#   ★ 没有阳性那两半，"搜索功能本身坏了"也会让阴性通过 —— 那是恒真式。
	_rec_kind = REC_KIND_HUMAN
	if btn_present:
		(_rec_kind_btn as Button).text = REC_KIND_LABELS[_rec_kind]
	_rec_search.text = "种子%d" % machine_seed
	_rec_rebuild_rows()
	var neg_human: int = _rec_filtered().size()
	_rec_kind = REC_KIND_MACHINE
	if btn_present:
		(_rec_kind_btn as Button).text = REC_KIND_LABELS[_rec_kind]
	_rec_rebuild_rows()
	var pos_machine: int = _rec_filtered().size()
	_rec_kind = REC_KIND_ALL
	if btn_present:
		(_rec_kind_btn as Button).text = REC_KIND_LABELS[_rec_kind]
	_rec_rebuild_rows()
	var pos_all: int = _rec_filtered().size()
	_rec_search.text = ""
	_rec_rebuild_rows()
	_rec_select_all(false)
	# 行文本（"哪两个 AI 打"）：那一行必须同时写出两个引擎名
	var row_txt: String = ""
	for e0 in _rec_idx:
		if e0 is Dictionary and str((e0 as Dictionary).get("id", "")) == mid:
			row_txt = _rec_row_text(e0)
			break
	var name_ok: bool = mid != "" and row_txt.contains("磐石") and row_txt.contains("疾风")
	# ★ 期望的「我的」条数走**分区式**（`全部 - 机器`），不是"逐个按 kind 分拣一遍"：
	#   ① `_rec_kind_of()` 的口径就是"是机器就进机器档，否则进我的档"（老谱无 kind ⇒ 我的），
	#      写成逐条分拣等于把那句映射再抄一遍（§70 判据不许重实现被测逻辑）；
	#   ② 分区式只依赖一个量（机器条数），而那个量有独立的牙齿（`machine_ids.has(mid)`，
	#      投影丢了就是空集 ⇒ 红），所以"恒等式"那一半不承担识别能力，不会被同化。
	var want_human: int = all_ids.size() - machine_ids.size()
	var c6b: bool = btn_present and label_ok and cycled_back and disk_kind_ok and sample_split \
		and name_ok and got_all == all_ids.size() \
		and got_human == want_human and got_machine == machine_ids.size() \
		and got_machine >= 1 and got_human >= spec.size() \
		and neg_human == 0 and pos_machine == 1 and pos_all == 1
	print("[rectest] ⑥b 分类三档：全部 %d(应%d)｜我的 %d(应%d)｜机器 %d(应%d)｜索引无kind老条目 %d｜盘上kind=%s 样本分档=%s｜按钮巡回=%s/%s｜行文本含双方名=%s｜搜机器样本 我的档 %d(应0)·机器档 %d(应1)·全部档 %d(应1) → %s"
		% [got_all, all_ids.size(), got_human, want_human,
			got_machine, machine_ids.size(), kind_absent,
			str(disk_kind_ok), str(sample_split), str(cycled_back), str(label_ok),
			str(name_ok), neg_human, pos_machine, pos_all, "✓" if c6b else "✗"])
	if not c6b:
		ok = false

	# ---- ⑦ 进复盘的交接：取走 + 清空；不存在的 id 不许污染 ----
	var pend_id: String = made[0] if not made.is_empty() else ""
	var c7a: bool = pend_id != "" and _rec_request_open(pend_id)
	var got_id: String = GameConfig.take_pending_replay()
	var got_again: String = GameConfig.take_pending_replay()
	var c7b: bool = got_id == pend_id and got_again == ""
	var c7c: bool = not _rec_request_open("绝不存在_id") and GameConfig.take_pending_replay() == ""
	var c7: bool = c7a and c7b and c7c
	print("[rectest] ⑦ 交接：写入=%s 取走=%s(应%s) 再取=%s(应空) 坏id被拒=%s → %s"
		% [str(c7a), got_id, pend_id, "\"%s\"" % got_again if got_again != "" else "空",
			str(c7c), "✓" if c7 else "✗"])
	if not c7:
		ok = false

	# ---- ⑧ 导出 SGF：真的落盘 + 内容像 SGF（在自检盘里写，不碰用户目录）----
	var ex_dir: String = GameRecord.records_dir() + "/export_rectest"
	DirAccess.make_dir_recursive_absolute(ex_dir)
	var sgf_path: String = _rec_export_write(ex_dir + "/a.sgf", made, true)
	var sgf_txt: String = FileAccess.get_file_as_string(sgf_path) if sgf_path != "" else ""
	var c8: bool = sgf_path != "" and sgf_txt.begins_with("(;") and sgf_txt.contains("SZ[") \
		and sgf_txt.ends_with(")") and sgf_txt.contains(";B[") and sgf_txt.contains(";W[")
	print("[rectest] ⑧ 导出 SGF：%d 份 → %d 字节·(; 开头=%s·SZ=%s·含黑白着法=%s → %s"
		% [made.size(), sgf_txt.length(), str(sgf_txt.begins_with("(;")),
			str(sgf_txt.contains("SZ[")),
			str(sgf_txt.contains(";B[") and sgf_txt.contains(";W[")), "✓" if c8 else "✗"])
	if not c8:
		ok = false

	# ---- ⑨ 导出 JSON → 再导入回来：**往返对拍**（最有价值的一条）----
	#   比的是"读回来那份与源谱**逐字段**一致（除了 id）"—— 只数条数的话，
	#   导出漏了字段、导入默认了字段都照样绿。
	#   ★★ 新 id 的口径 = **导入前拍的快照差集**，不是"库里所有不在 `made` 里的 id"。
	#      首版用了后者 ⇒ 上一轮残留样本也被算成"本次导入的" ⇒ 配对错位，
	#      而且错位之后取到空字典、`["moves"]` 直接**抛脚本错**（整条自检当场终止，
	#      后面 ⑩⑪ 一条都没跑）。⇒ 两条纪律：① 差集对着**紧邻的快照**算；
	#      ② 读记录一律先判空再取键（`load_by_id` 对不存在的 id 返回空字典）。
	var json_path: String = _rec_export_write(ex_dir + "/a.json", made, false)
	var snap_before: Dictionary = {}
	for e in _rec_idx:
		snap_before[str((e as Dictionary).get("id", ""))] = true
	var n_before_imp: int = _rec_idx.size()
	var imported_n: int = _rec_import_text(FileAccess.get_file_as_string(json_path))
	var n_after_imp: int = _rec_idx.size()
	var new_ids: Array[String] = []
	for e in _rec_idx:
		var sid: String = str((e as Dictionary).get("id", ""))
		if not snap_before.has(sid):
			new_ids.append(sid)
	var pair_ok: bool = new_ids.size() == made.size()
	var first_bad: String = "" if pair_ok else "新 id 数 %d ≠ 样本 %d" % [new_ids.size(), made.size()]
	for i in made.size():
		if not pair_ok:
			break
		var src_rec: Dictionary = GameRecord.load_by_id(made[i])
		var dst_rec: Dictionary = GameRecord.load_by_id(new_ids[i])
		if src_rec.is_empty() or dst_rec.is_empty():
			pair_ok = false
			first_bad = "第 %d 对读不回来（空记录）" % i
			break
		# ★ 先判空再取键：直接写 `src_rec["moves"]` 在空字典上是**脚本错**（不是判据红）
		var src_mv: Array = src_rec.get("moves", [])
		var dst_mv: Array = dst_rec.get("moves", [])
		for k in ["board_type", "board_size", "board_seed", "komi", "mode",
				"generator_fingerprint", "created_at", "format_version"]:
			if str(src_rec.get(k, "")) != str(dst_rec.get(k, "")):
				pair_ok = false
				first_bad = "%s: %s ≠ %s" % [k, str(src_rec.get(k)), str(dst_rec.get(k))]
		if src_mv.size() != dst_mv.size():
			pair_ok = false
			first_bad = "手数 %d ≠ %d" % [src_mv.size(), dst_mv.size()]
		if str(GameRecord.result_of(src_rec)) != str(GameRecord.result_of(dst_rec)):
			pair_ok = false
			first_bad = "终局条目不同"
		if not pair_ok:
			break
	var c9: bool = imported_n == made.size() and n_after_imp == n_before_imp + made.size() \
		and pair_ok
	print("[rectest] ⑨ 导出→导入往返：导入 %d 条·库存 %d→%d（应 +%d）·逐字段一致=%s%s → %s"
		% [imported_n, n_before_imp, n_after_imp, made.size(), str(pair_ok),
			"" if pair_ok else "（%s）" % first_bad, "✓" if c9 else "✗"])
	if not c9:
		ok = false
	# ★★ 导入必须**换新 id**（沿用原 id 会静默覆盖本地同名那条："导入"的语义是加进来）
	var id_clash: bool = false
	for nid in new_ids:
		if made.has(nid):
			id_clash = true
	var c9b: bool = not id_clash and new_ids.size() == made.size()
	print("[rectest] ⑨b 导入换新 id：新 %d 条与源 id 相撞=%s → %s"
		% [new_ids.size(), str(id_clash), "✓" if c9b else "✗"])
	if not c9b:
		ok = false

	# ---- ⑩ 坏输入的阴性对照：坏 JSON / 空串 / 缺格式版本 ⇒ 不增库、不崩 ----
	var n_before_bad: int = _rec_idx.size()
	var bad_n: int = _rec_import_text("{这不是 json")
	bad_n += _rec_import_text("")
	bad_n += _rec_import_text("[[1,2,3]]")
	bad_n += _rec_import_text("{\"format_version\": 999}")
	var n_after_bad: int = _rec_idx.size()
	var c10: bool = bad_n == 0 and n_after_bad == n_before_bad
	print("[rectest] ⑩ 坏输入：4 份坏数据导入 %d 条(应0)·库存 %d→%d(应不变) → %s"
		% [bad_n, n_before_bad, n_after_bad, "✓" if c10 else "✗"])
	if not c10:
		ok = false

	# ---- ⑪ 删除：索引真少一条 + **文件真的没了**（量真源，不拿 API 返回值当"删掉了"）----
	# ★★ 输入**故意混一个不存在的 id**：这是本条唯一的牙齿来源。
	#   `GameRecord.delete_by_id()` 对不存在的 id **也返回 true**（它只保证"库里没有这条"），
	#   所以"删了 N 个 id 就报告 N 条"这种写法在只删真实 id 时**与正确实现完全一致**
	#   ⇒ 判据分不开（阴性对照 RC14 会当场"没牙齿"）。混一个假的进来说明：
	#   返回值必须是**索引的净变化**，不是"我调了几次 API"。
	var del_id: String = new_ids[0] if not new_ids.is_empty() else ""
	var n_before_del: int = _rec_idx.size()
	var gone_n: int = _rec_do_delete([del_id, "绝不存在_id"])
	var file_gone: bool = GameRecord.load_by_id(del_id).is_empty()
	var c11: bool = del_id != "" and gone_n == 1 and _rec_idx.size() == n_before_del - 1 \
		and file_gone
	print("[rectest] ⑪ 删除：喂 [真 id, 不存在的 id] → 索引 -%d(应1)·文件读不回来=%s → %s"
		% [gone_n, str(file_gone), "✓" if c11 else "✗"])
	if not c11:
		ok = false

	# ---- ⑫ 工具栏**接线**：按文本找到真按钮，且**真按一下**（不是直接调函数）----
	# ★★ 为什么必须有这条（铁律 13「接线盲区」，`rules.md` §13）：
	#   ①~⑪ 全是**直接调函数**（`_rec_export_write` / `_rec_import_text` / `_rec_do_delete` /
	#   `_rec_request_open`）⇒ 若 `_build_records_ui()` 漏加某个按钮，**用户根本点不到那个功能**，
	#   而 13 条判据**照样全绿**。这是本工程最怕的形态：判据覆盖了**函数**，
	#   没覆盖"用户能不能**到达**那个函数"。⇒ 必须有一条从**控件**出发的判据。
	# ★ 两层，缺一不可：① 存在性 + `pressed` **有连接**（"有个控件"与"那个控件接了活"是两件事，
	#   漏 `.connect(...)` 的按钮点下去什么都不会发生）；② **真按** —— 只有真按才算走了真实交互路径。
	# ⚠️ **不按**「删除所选」：它 `popup_centered()` 一个 `ConfirmationDialog`，而 headless 下
	#   弹 Window 会**静止不动**（本工程已实测过 `FileDialog` 那一族 ⇒ 判据挂死）。
	#   "点了会弹确认框"由 `_rec_ask_delete()` 的源码 + S 系列守卫守，不靠 headless 按。
	var btns: Dictionary = {}
	_rec_buttons_by_text(_records_root, btns)
	# ★ 期望写**前缀**而不是全文：全选框的文字是**运行期**的（`全选（%d 条）`，见
	#   `_rec_rebuild_rows()`），绑全文 = 判据跟着库里条数一起漂。
	#   ⚠️ 首版就是写死的 `"全选"` ⇒ 报「缺按钮=["全选"]」，而控件**好端端在那儿** ——
	#   **是判据的期望值错了，不是面板错了**。这类"红在判据自己"的账本工程记得很多
	#   （`rules.md` §71 同族）：**看到红先问"我的期望值是不是绑了一个会变的东西"**。
	var want_pfx: Array[String] = ["导出 SGF", "导出 JSON", "导入 JSON", "删除所选",
		REC_SORT_LABELS[_rec_sort], REC_KIND_LABELS[_rec_kind], "复盘", "全选"]
	var miss_txt: Array[String] = []
	var nowire_txt: Array[String] = []
	for wt in want_pfx:
		var hit_btn: Button = null
		for k in btns.keys():
			if str(k).begins_with(wt):
				hit_btn = btns[k] as Button
				break
		if hit_btn == null:
			miss_txt.append(wt)
			continue
		# `pressed` 或 `toggled` **任一个有连接** = 那个控件真的接了活。
		# ⚠️ 只查 `pressed` 会把好端端接好的**全选框**报成"未接线"（实测：
		#   `在位数 7/7·未接线 ["全选"]`）：全选框接的是 `toggled`，而
		#   `toggled` 声明在 `BaseButton` 上（`Button`/`CheckBox` 都继承）。
		#   ⇒ "有个控件"与"它会干活"是两件事，但**判"会干活"要看它接的是哪个信号**。
		var wired: bool = not hit_btn.pressed.get_connections().is_empty() \
			or not hit_btn.toggled.get_connections().is_empty()
		if not wired:
			nowire_txt.append(wt)
	# 真按「导入 JSON」：headless 分支只改状态文字、**不弹窗** ⇒ 安全，且副作用可观测
	var st_before: String = _rec_status.text if _rec_status != null and is_instance_valid(_rec_status) else ""
	var import_live: bool = false
	if btns.has("导入 JSON"):
		(btns["导入 JSON"] as Button).pressed.emit()
		if _rec_status != null and is_instance_valid(_rec_status):
			import_live = _rec_status.text != st_before
	# 真按「排序」：档位必须真的往前走（这证明"按钮 → 回调 → 状态"整条链是通的）
	var sort_before: int = _rec_sort
	var order_a: Array = _rec_filtered()
	var sort_live: bool = false
	if btns.has(REC_SORT_LABELS[_rec_sort]):
		(btns[REC_SORT_LABELS[_rec_sort]] as Button).pressed.emit()
		sort_live = _rec_sort != sort_before
	# 还原档位（不然会把后面的判据与"用户上次的档"改掉）
	while _rec_sort != sort_before:
		_rec_cycle_sort()
	# 真按「分类」：档位必须真的往前走（与「排序」同款）。★ 与 ⑥b 分工：
	#   ⑥b 量的是"三档筛出来的**内容**对不对"（计数 + 样本归属 + 阴性/阳性）；
	#   这里量的是"这块**按钮**接上了没有"（存在性那条只看信号有没有连接，连接了但回调
	#   什么都没干照样绿）。两条各管一半，合成才等于"用户点得到且点得对"。
	var kind_before: int = _rec_kind
	var kind_live: bool = false
	if btns.has(REC_KIND_LABELS[_rec_kind]):
		(btns[REC_KIND_LABELS[_rec_kind]] as Button).pressed.emit()
		kind_live = _rec_kind != kind_before and _rec_kind == (kind_before + 1) % REC_KIND_COUNT
	while _rec_kind != kind_before:
		_rec_cycle_kind()
	# 真按「全选」：`button_pressed` 的 **setter 会发 `toggled`**（Godot 正为此留了
	#   `set_pressed_no_signal()`）⇒ 这条真的走了一遍"用户点全选"的路，
	#   比只查"信号有没有连接"更有牙齿（连接了但回调里什么都没干，也照样会被这条抓住）。
	var all_live: bool = false
	if _rec_all_box != null and is_instance_valid(_rec_all_box):
		_rec_all_box.button_pressed = true
		all_live = _rec_checked_ids().size() == _rec_filtered().size() \
			and _rec_filtered().size() > 0
		_rec_all_box.button_pressed = false
	# ★ 元判据（铁律 12/13）：这套"按文本找控件"的仪器本身要有牙齿 ——
	#   一个**确定不存在**的文本必须**找不着**。否则 `btns` 若恒非空/恒命中，上面那条永远绿。
	var phantom_hit: bool = btns.has("绝不可能存在的按钮ZZZ")
	if phantom_hit:
		bad_shape.append("工具栏存在性检查没牙齿（不存在的按钮也被认成在）")
	var c12: bool = miss_txt.is_empty() and nowire_txt.is_empty() and import_live \
		and sort_live and kind_live and all_live \
		and order_a.size() == _rec_filtered().size() and not phantom_hit
	print("[rectest] ⑫ 工具栏接线：在位数 %d/%d·未接线 %d·真按「导入 JSON」状态变=%s·真按「排序」换档=%s·真按「分类」换档=%s·真按「全选」勾满=%s·阴性(不存在的按钮找不着)=%s → %s"
		% [want_pfx.size() - miss_txt.size(), want_pfx.size(), nowire_txt.size(),
			str(import_live), str(sort_live), str(kind_live), str(all_live),
			str(not phantom_hit), "✓" if c12 else "✗"])
	if not c12:
		ok = false
		print("[rectest]   ✗ 细节：缺按钮=%s｜未接线=%s"
			% [str(miss_txt), str(nowire_txt)])

	# ---- 清理：把本次造的 + 导入的一起删掉（判据不许往自检盘里堆垃圾）----
	for id in made:
		GameRecord.delete_by_id(id)
	# ★ 机器对局样本也必须收：它在 `made` 之外（刻意不混进 ④ 的分母）⇒ 漏了这一行，
	#   自检盘里就会一直躺着一条 `kind=MACHINE` 的样本，下一轮 ⑥b 的"机器档 ≥1"
	#   会**靠上一轮的尸体**通过（本函数开头那段清理只认种子前缀，认得出但那是补救不是本分）。
	for id in made_m:
		GameRecord.delete_by_id(id)
	for id in new_ids:
		GameRecord.delete_by_id(id)
	DirAccess.remove_absolute(ex_dir + "/a.sgf")
	DirAccess.remove_absolute(ex_dir + "/a.json")
	# ★ 连**目录**一起收：只删两个文件会留下一个空的 `export_rectest/`
	#   （实测自检盘里就躺着它）。空目录本身无害（不是 `.json`，索引看不见），
	#   但"自检不该在盘上留任何东西"这条纪律下，留着它就是留了。
	#   ⚠️ 必须在两个文件删完之后调 —— 非空目录 `remove_absolute` 会失败。
	DirAccess.remove_absolute(ex_dir)
	_set_page(PAGE_MAIN)

	# ---- 元判据（铁律 12 ②）----
	if not bad_shape.is_empty():
		for b in bad_shape:
			print("[rectest] ✗ 细节·%s" % b)
		ok = false
	print("[rectest] 结论：%s" % ("通过 ✓" if ok else "失败 ✗ 棋谱库面板不对"))
	get_tree().quit()


## 在**列表**里找 `ids` 各自的下标（找不到记 -1）。给排序判据量"样本三者的相对次序"用。
func _rec_rel_order(list: Array, ids: Array) -> Array:
	var pos: Array = []
	for id in ids:
		var at: int = -1
		for i in list.size():
			if str((list[i] as Dictionary).get("id", "")) == str(id):
				at = i
				break
		pos.append(at)
	return pos


## 递归收集一棵子树里的所有按钮，建 **文本 → Button** 表（同名只留第一个）。
## ★ 给 ⑫ 用：判据必须能**从控件出发**找到真按钮（`rules.md` §13「接线盲区」）。
## ★ 用 `n is Button` 而不是 `n.get_class() == "Button"`：`CheckBox`/`OptionButton` 都是
##   `Button` 的子类，"按类判"能把全选框一起收进来（本判据正需要它）。
## ⚠️ **与 `_collect_buttons()`（按 `name` 索引，给 `--esctest` 用）不是同一个契约，故意并存**：
##   那个按 `name` 建表，而本面板的按钮都是 `Button.new()` 出来的**没有名字**
##   （自动名 `@Button@N`，会随建树顺序漂移，压根不能当键）⇒ 必须按**文本**认。
##   ★ 命名事故记录：本函数**首版就叫 `_collect_buttons`** ⇒ 与上面那个（`--esctest` 用的）**重名** ⇒
##   `Parse Error: Function "_collect_buttons" has the same name as a previously declared function`
##   ⇒ `menu.gd` **整个加载失败**（`--rectest` 零输出 + 被 SIGTERM，看起来像"挂死"）。
##   ⇒ `rules.md` §47「成员名/函数名先查占用」又被踩了一次：**加函数前先 grep 名字**。
func _rec_buttons_by_text(root: Node, out: Dictionary) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is Button:
		var b: Button = root as Button
		if not out.has(b.text):
			out[b.text] = b
	for c in root.get_children():
		_rec_buttons_by_text(c, out)


## 下标序列是否**严格**递增 / 递减（且无 -1）。给排序判据用。
## ★ 用"严格"而不是"非减"（铁律 25）：非减在"三份样本挤在同一个下标"这种退化情形下
##   也能成立，而那种情形恰恰说明"有一个样本没被列出来"。
func _rec_strictly(pos: Array, up: bool) -> bool:
	if pos.size() < 2:
		return false
	for i in pos.size():
		if int(pos[i]) < 0:
			return false
	for i in range(1, pos.size()):
		if up and int(pos[i - 1]) >= int(pos[i]):
			return false
		if not up and int(pos[i - 1]) <= int(pos[i]):
			return false
	return true


## 把当前主题的墨色刷进一棵页面控件树。**唯一入口**：`_refresh_settings_ink()` /
## `_refresh_records_ink()` / `_refresh_page_ink()` 都调它。
##
## ★★ 2026-10-15 扩到"**带文字的原生表单控件**"：原先只处理 `Label`，于是
##    `CheckBox` / `CheckButton` / `LineEdit` 一律停在**引擎默认主题**的字色上
##    —— 那是接近白的浅灰，压在浅色主题（宣纸/天青…）的页面上对比度只有 **1.06**
##    （等于没字），而它们在深色主题下看着完全正常 ⇒ 又是一个"只在一半主题上坏掉"的静默缺陷。
##    最早被逮到的是棋谱页那个「全选」勾选框与大厅的房间号输入框。
##   ★ `LineEdit` 走 `style_theme_line_edit()`（连**盒底**一起换）：只改字色的话，
##     按"对页面底可读"算出来的近黑字会压在引擎默认的深灰盒上 ⇒ 字与盒一起糊
##     （原因与实测见该函数的注）。盒色与字色是一对，必须同一个真源一起给。
##   ⚠️⚠️ `Button` **故意不在**这里的名单里：按钮的字色必须取自 `button_palette()`
##    （那是对着**按钮自己的填充色**拟合出来的），而本函数给的是"对**页面底**可读"的墨色。
##    两者是不同的真源 —— 把 Button 加进来会把按钮字色刷成"对着页面底算的颜色"，
##    压在按钮底上可能不达标（浅色主题下按钮底是浅褐、页面墨色是近黑 ⇒ 碰巧还行，
##    深色主题下按钮底是荧光色、页面墨色是近白 ⇒ 就可能翻车）。这一条由 `--menutest` ⑮ 守。
func _apply_ink_recursive(node: Node, ink: Color, accent: Color) -> void:
	_ink_apply_control(node, ink, accent)
	for child in node.get_children():
		_apply_ink_recursive(child, ink, accent)

## 给**单个**控件套当前主题的墨色。从 `_apply_ink_recursive()` 里提出来，是因为
## **运行期新建**的控件（棋谱页每次筛选/排序都会重建一整批行）也要就地套一次 ——
## 那种"建完才刷"的写法在增量建控件的地方必然漏（本轮实测：棋谱页的「全选」是灰字）。
## ★ 返回 true 表示这个控件被本函数管（含"故意不管"的 Button 之外的类型）。
func _ink_apply_control(node: Node, ink: Color, accent: Color) -> bool:
	if node is Label:
		var lbl := node as Label
		lbl.add_theme_color_override("font_color", accent if bool(lbl.get_meta("group", false)) else ink)
		return true
	if node is CheckBox or node is CheckButton:
		# 勾选类控件分**两层**：文字（下面这几支字色）+ **方块/胶囊本体**（方块与勾、胶囊与手柄
		# 都是引擎图标记的 —— 2026-10-15 起走 `style_theme_native_body()` 重新上色）。
		for k in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color"]:
			(node as Button).add_theme_color_override(k, ink)
		GameConfig.style_theme_native_body(node as Control, _page_surface())
		return true
	if node is Slider or node is ScrollBar:
		# 滑杆 / 滚动条：本体**全部**在引擎的样式盒与图标里（轨道、手柄、槽、滑块）⇒ 整支重上色。
		# ★ 这两族没有"文字"这一层，所以只有这一个入口（与勾选框不同）—— 一句话说得清的分工。
		GameConfig.style_theme_native_body(node as Control, _page_surface())
		return true
	if node is ScrollContainer:
		# ★★ 为什么必须在这里单独取（2026-10-15 踩到）：`ScrollContainer` 的两条滚动条是**内部
		#   子节点**（引擎 `add_child(..., INTERNAL_MODE_FRONT)`），而 `Node.get_children()`
		#   **默认不收内部子节点** ⇒ 本工程所有"从页面根递归"的遍历（含本函数所在的
		#   `_apply_ink_recursive()` 自己）**根本看不见它们**：棋谱页/大厅右侧那条滚动条因此
		#   一直是引擎灰 —— 而它既不在按钮族、也不在输入框族，**没有任何判据看着它**。
		#   （本轮实测：`--menutest` ⑯ 起初一个 VScrollBar 都收不到，正是这个口径暴露的。）
		#   引擎给了取值 API，所以在这里显式取出来套样式 —— 不去改递归口径，免得顺带把手伸进
		#   别的内部节点（那些不是我们的界面）。
		var sc := node as ScrollContainer
		for bar in [sc.get_v_scroll_bar(), sc.get_h_scroll_bar()]:
			if bar != null:
				GameConfig.style_theme_native_body(bar, _page_surface())
		return true
	if node is OptionButton or node is MenuButton:
		# ★★ 2026-10-21（座位/棋盘/大小三个下拉）踩到上面那条坑的**第二张脸**：
		#   `PopupMenu` 里也有一个内部 `ScrollContainer`（引擎 4.4+ 为 `max_height` 加的那套），
		#   它的两条滚动条同样是内部子节点 —— 上面 `ScrollContainer` 那一支靠
		#   `get_v_scroll_bar()` 取值 API 绕过去了，而弹窗**没有**这种 API。
		#   实测：对弈页加 3 个 `OptionButton` 之后，`--menutest` ⑯ 立刻报
		#   「异常 12 处」= 3 个弹窗 × 2 条滚动条 × 2 档明度（此前一直是 0 处全绿）。
		#   ⇒ 专门钻一次内部子节点，但**范围只到弹窗里面**（不动全局递归口径）。
		var pmn: PopupMenu = (node as Button).get_popup()
		if pmn != null:
			_style_popup_internals(pmn, _page_surface())
		# 字色不在这里管：`OptionButton` 属于「表单控件」，⑮ 的按钮族口径里明确跳过了它
		# （见上面那段 Button 故意不进来的理由）。
		return false
	if node is LineEdit:
		# ★ 整支重套（盒底 + 字 + 光标），不是只改字色 —— 理由见 `style_theme_line_edit()` 的注。
		GameConfig.style_theme_line_edit(node as LineEdit, _page_surface())
		return true
	return false

## 把 `PopupMenu` **内部**的滚动条也套上主题（`_ink_apply_control()` 的 OptionButton 分支调它）。
## ★ 为什么要单独钻一次内部子节点：`PopupMenu` 自带的 `ScrollContainer` 及其两条滚动条都是
##   `INTERNAL_MODE_*` 子节点，`Node.get_children()` **默认不收** ⇒ 本工程"从页面根递归"的
##   遍历（`_apply_ink_recursive()`）根本走不到它们；而 `ScrollContainer` 那一支能靠
##   `get_v_scroll_bar()` 这个取值 API 绕过去，弹窗**没有**对应 API。
##   实测（2026-10-21）：对弈页加了 3 个下拉之后 `--menutest` ⑯ 立刻报「异常 12 处」
##   = 3 个弹窗 × 2 条滚动条 × 2 档明度（加下拉之前是 0 处全绿 ⇒ 是本轮引入的真回归）。
## ★ 范围刻意收得极小：**只在弹窗内部**用 `get_children(true)`。全局递归口径一个字不动 ——
##   放开它会把别的内部节点（不是我们的界面）一起伸手进去，那是注释里明确拒绝过的做法。
## ★ 幂等：`style_theme_native_body()` 的源一律取 `ThemeDB` 默认主题（见它的注）。
func _style_popup_internals(pm: PopupMenu, host_bg: Color) -> void:
	if pm == null or not is_instance_valid(pm):
		return
	var stack: Array[Node] = [pm]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children(true):
			if ch is ScrollBar:
				GameConfig.style_theme_native_body(ch as Control, host_bg)
			stack.append(ch)

## 页面建好之后**统一刷一次主题墨色**（原生控件里"不跟着主题走"的那一半）。
## ★★ 为什么必须在**建页时**也刷（2026-10-15 实测踩到）：`_apply_appearance()` 那条路只在
##   "改主题/启动"时跑，而页面控件是**建页那一刻**才造出来的 ⇒ 只靠它的话，首次进页面时
##   勾选框/输入框仍是引擎默认色（实测：`--shotpage=records` 的「全选」在宣纸下是灰字、
##   搜索框还是引擎默认深灰）。两条路都要：**建页给初值，改主题给刷新**。
## ★ 只有一个调用点（`_set_page()` 末尾）—— 铁律 8：一处写，别让每个 `_build_*` 各写一行。
func _refresh_page_ink() -> void:
	if _page == PAGE_SETTINGS:
		_refresh_settings_ink()
	elif _page == PAGE_RECORDS:
		_refresh_records_ink()
	elif _page == PAGE_LOBBY and _duel_root != null and is_instance_valid(_duel_root):
		# 对弈页没有独立的 `_refresh_duel_ink`，这里直接刷（它只有几个标签 + 一个输入框）
		_apply_ink_recursive(_duel_root, GameConfig.ink_color(), GameConfig.accent_color())

# 浅色标签（颜色随背景明度自适应）
func _ui_label(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", GameConfig.ink_color())
	return l

# 分组标题（强调色，颜色随背景明度自适应；文字居中）
func _ui_group_label(text: String) -> Label:
	var l := _ui_label(text, 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_meta("group", true)
	l.add_theme_color_override("font_color", GameConfig.accent_color())
	return l

# 轻量临时提示（秒后自动消失），用于设置页操作反馈
func _tip(msg: String) -> void:
	var t := Label.new()
	t.text = msg
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", _accent)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	# 标题是 60px 大字、垂直居中于 26~132（实际文字约占 43~115）→ 提示贴最顶才不会压到标题
	t.position.y = 8.0
	add_child(t)
	var tw := Timer.new()
	tw.wait_time = 2.5
	tw.one_shot = true
	tw.timeout.connect(func() -> void:
		t.queue_free(); tw.queue_free())
	add_child(tw)
	tw.start()

# 销毁设置页原生控件
func _clear_settings_ui() -> void:
	if _settings_root != null and is_instance_valid(_settings_root):
		_settings_root.queue_free()
		_settings_root = null

# ====== 棋谱库面板（原生控件，非瓷砖）======
# ★★ 与设置面板**同一套纪律**（照 `_build_settings_ui()` 抄的，逐条理由见那边）：
#   ① 整棵控件树落在**底栏行带之上**（下沿读 `_footer_band()` 真源，不写常数）——
#      底栏四块是"换面板"的唯一入口，被盖住就是**出不去**，而被盖住的又是自绘瓷砖
#      （`_input` 仍能命中）⇒ 症状是"砖看不见但点得到"，更怪。
#   ② 切页时整棵销毁（`_clear_records_ui()`，与 `_clear_settings_ui()` 并列调用）。
#   ③ 用 `Control.MOUSE_FILTER_STOP` 拦住点击，别穿透到菜单瓷砖逻辑。
# ★ 为什么**不**用瓷砖做列表：瓷砖那套（`_items` + `_layout_*` + `_tile_at_point`）是为
#   "固定几块 + 循环行 + 折叠动画"设计的；棋谱条数是**运行期数据**（可能 0 条、可能几百条），
#   塞进去就得给布局加滚动、给命中加裁剪 —— 把两件事混成一件。而"点条目进复盘"是普通按钮，
#   用原生控件反而更稳（也与设置面板一致）。
# ★ 数据源一律走 `GameRecord` 的既有 API（`list_index` / `load_by_id` / `delete_by_id` /
#   `to_json` / `from_json` / `save` / `to_sgf`）：**不自己拼路径、不自己写盘**，
#   那两道闸（格式版本 + 自动化运行改道自检盘）都在那条路上；另写一份就是又一条
#   "两处都记得"的路（本工程老坑）。
var _records_root: Control = null
var _rec_rows_box: VBoxContainer = null      # 每行挂这里（重建列表 = 清掉它再填）
var _rec_search: LineEdit = null
var _rec_all_box: CheckBox = null            # 全选（只作用于**当前列出的**那些）
var _rec_status: Label = null
var _rec_sort_btn: Button = null
var _rec_idx: Array = []                     # `GameRecord.list_index()` 的快照
var _rec_sel: Dictionary = {}                # id → bool（勾选态）
var _rec_sort: int = 0
## 全选 ↔ 逐行 的互写重入闸（给 `CheckBox.button_pressed` 赋值会**同步**发 `toggled`，
## 与复盘滑条的 `_rp_ui_lock` 同族；不设闸就是"全选一次、再逐行点一下，全选框态乱跳"）。
var _rec_ui_lock: bool = false
const REC_SORT_TIME: int = 0
const REC_SORT_PLIES: int = 1
const REC_SORT_RESULT: int = 2
const REC_SORT_COUNT: int = 3
const REC_SORT_LABELS: Array[String] = ["时间 ↓", "手数 ↓", "结果"]
## ★★ 棋谱**分类**（2026-10-22 加，用户口令「把历史对局和其他的分开」）。
## 三档 = 全部 / 我的对局 / 机器对局。真源是**记录自己的 `kind`**（`GameRecord.KIND_*`），
##   不是从 `mode` 推 —— `mode` 只有 LOCAL/VS_AI/ONLINE，**表达不了"两个 AI 互下"**。
## ★ 控件选型：用**一个会循环的 `Button`**（与上面排序按钮同构），不用 `OptionButton`/
##   `TabBar` —— 后者是**新原生控件**，会连带 `--menutest` ⑯ 的原生控件清点（§126：
##   加 3 个 OptionButton ⇒ ⑯ 异常 0→12）。同构复用 = 接线只在这一处，漏不了。
const REC_KIND_ALL: int = 0
const REC_KIND_HUMAN: int = 1
const REC_KIND_MACHINE: int = 2
const REC_KIND_COUNT: int = 3
const REC_KIND_LABELS: Array[String] = ["全部对局", "我的对局", "机器对局"]
var _rec_kind: int = REC_KIND_ALL
var _rec_kind_btn: Button = null
## 一次最多铺多少行。★★ 这不是"优化"，是**必要的**：
##   一行 = 复选框 + 标签 + 两个按钮 = 4 个控件，而每次筛选/排序都要整批重建。
##   实测（2026-10-08 首跑 `--rectest`）：自检盘里积了 1065 条 ⇒ 一轮自检要建/销毁
##   四万多个控件，**整个自检跑不完**（哨兵是"零输出 + 被杀"）。
##   而这在真机上同样会发生：玩家连下几百局之后，进棋谱面板就是**卡死几秒**。
##   ⇒ 上限 + 一行"只显示前 N 条，用搜索缩小范围"的提示（**别悄悄截断**：
##     列表少了东西而不说，用户会以为棋谱丢了 —— 那比卡顿严重得多）。
const REC_ROW_CAP: int = 200
## 自检样本的认领指纹（`--rectest` 造的谱都带它）。
## ★ 为什么要一个**专属指纹**而不是"按 id 前缀认"：清理必须**认得出自己的产物、且只认自己的**
##   —— 按时间/前缀去猜会误删别的自检留下的东西（自检盘是所有自检共用的）。
const REC_SELF_FP: String = "rectest-selftest-fp"


func _clear_records_ui() -> void:
	if _records_root != null and is_instance_valid(_records_root):
		_records_root.queue_free()
	_records_root = null
	_rec_rows_box = null
	_rec_search = null
	_rec_all_box = null
	_rec_status = null
	_rec_sort_btn = null
	_rec_kind_btn = null
	_rec_ui_lock = false


func _build_records_ui() -> void:
	_clear_records_ui()
	var vw := get_viewport_rect().size.x
	# 下沿 = 底栏行带上沿 − 净空（与设置面板同一口径，读真源而非写常数）
	# ★ 变量名**故意与设置面板不同**（`rec_panel_bottom` vs 那边的 `panel_bottom`）：
	#   两边若同名，结构守卫 S60 那个"下沿先读真源"的标记就会命中 2 次 ⇒ 守卫报红。
	#   而**放宽那个标记到"允许 2 次"是错的**：那会让它对设置面板的咬合力一起变松。
	#   ⇒ 各自独立命名，S84 单独守棋谱面板这一份。
	var rec_panel_bottom: float = _footer_band().position.y - FOOT_GAP
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_top = TOP_MARGIN + 12.0
	root.offset_bottom = -(size.y - rec_panel_bottom)
	root.offset_left = 40.0
	root.offset_right = -40.0
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	_records_root = root

	# —— 工具条：搜索 / 排序 / 全选 / 状态 ——
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)
	_rec_search = LineEdit.new()
	_rec_search.placeholder_text = "搜索（双方 / 盘型 / 模式 / 结果 / 手数 / 日期）"
	_rec_search.custom_minimum_size = Vector2(clampf(vw * 0.30, 240.0, 420.0), 34.0)
	# ★ 边打边筛：`text_changed` 而不是"回车才筛"——列表是原地重建的，没有回车那一步的负担，
	#   而"输完了还得按一下"在小列表上纯属多余动作。
	_rec_search.text_changed.connect(func(_t: String) -> void: _rec_rebuild_rows())
	bar.add_child(_rec_search)
	_rec_sort_btn = Button.new()
	_rec_sort_btn.text = REC_SORT_LABELS[_rec_sort]
	_style_page_button(_rec_sort_btn)
	_rec_sort_btn.pressed.connect(func() -> void: _rec_cycle_sort())
	bar.add_child(_rec_sort_btn)
	# 分类（全部 / 我的对局 / 机器对局）：同样是"点一下循环下一档"，与排序按钮同构
	_rec_kind_btn = Button.new()
	_rec_kind_btn.text = REC_KIND_LABELS[_rec_kind]
	_style_page_button(_rec_kind_btn)
	_rec_kind_btn.pressed.connect(func() -> void: _rec_cycle_kind())
	bar.add_child(_rec_kind_btn)
	_rec_all_box = CheckBox.new()
	_rec_all_box.text = "全选"
	_rec_all_box.toggled.connect(func(on: bool) -> void: _rec_select_all(on))
	bar.add_child(_rec_all_box)
	_rec_status = _ui_label("", 18)
	_rec_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_rec_status)

	# —— 列表（可滚动；条数是运行期数据，不滚会直接把底栏挤出去）——
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(sc)
	_rec_rows_box = VBoxContainer.new()
	_rec_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_rows_box.add_theme_constant_override("separation", 6)
	sc.add_child(_rec_rows_box)

	# —— 动作条：导出 SGF / 导出 JSON / 导入 JSON / 删除所选 ——
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 12)
	root.add_child(act)
	act.add_child(_rec_make_action("导出 SGF", func() -> void: _rec_ask_export(true)))
	act.add_child(_rec_make_action("导出 JSON", func() -> void: _rec_ask_export(false)))
	act.add_child(_rec_make_action("导入 JSON", func() -> void: _rec_ask_import()))
	act.add_child(_rec_make_action("删除所选", func() -> void: _rec_ask_delete()))
	_rec_load()


func _rec_make_action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_style_page_button(b)          # 棋谱页四个动作按钮：走工厂 ⇒ 接线只在这一处，漏不了
	b.pressed.connect(cb)
	return b


# ---------------- 数据：读 / 筛 / 排 ----------------

## 重新读索引并重建行。★ 写盘动作（删除 / 导入）之后**必须**走它，
##   而不是就地改 `_rec_idx` —— 两份状态迟早不一致（铁律 8）。
func _rec_load() -> void:
	var raw: Array = GameRecord.list_index()
	var kept: Array = []
	for e in raw:
		if e is Dictionary:
			kept.append(e)
	_rec_idx = kept
	_rec_rebuild_rows()


## 当前要显示的条目（分类 + 筛选 + 排序）。**纯函数**
## （只读 `_rec_idx` / `_rec_search` / `_rec_sort` / `_rec_kind`）⇒ 判据可以直接对它的输出断言。
func _rec_filtered() -> Array:
	var q: String = ""
	if _rec_search != null and is_instance_valid(_rec_search):
		q = _rec_search.text.strip_edges().to_lower()
	var out: Array = []
	for e in _rec_idx:
		var d: Dictionary = e
		# ★ 分类先过（便宜），再走全行文本匹配（贵）
		if _rec_kind != REC_KIND_ALL and _rec_kind_of(d) != _rec_kind:
			continue
		if q != "" and not _rec_row_text(d).to_lower().contains(q):
			continue
		out.append(d)
	out.sort_custom(Callable(self, "_rec_cmp"))
	return out


## 条目属于哪一类（UI 侧的口径）。★ 真源是**记录自己的 `kind` 字段**，不是模式、也不是双方名：
##   按双方名认引擎名会在改名后**静默**把机器对局漏回"我的对局"（§113）。
##   索引里没有 `kind`（2026-10-22 之前的谱）⇒ 算「我的对局」，这是**保守方向**：
##   宁可把老谱留在默认类里，也不要把玩家的对局藏进"机器对局"里（`--recmig` 可把老谱补齐）。
func _rec_kind_of(e: Dictionary) -> int:
	if int(e.get("kind", GameRecord.KIND_HUMAN)) == GameRecord.KIND_MACHINE:
		return REC_KIND_MACHINE
	return REC_KIND_HUMAN


## 排序比较器。★ 每种口径都必须以**全序兜底**结尾（这里按 id 降序）：
##   只按"时间"比的话，同一秒内造的两条谱**谁前谁后**取决于 Godot 内部排序实现
##   ⇒ "序列严格递减"那条判据会随实现飘（铁律 25 要的是**严格**形式，就得先有全序）。
func _rec_cmp(a: Dictionary, b: Dictionary) -> bool:
	match _rec_sort:
		REC_SORT_PLIES:
			var pa: int = int(a.get("plies", 0))
			var pb: int = int(b.get("plies", 0))
			if pa != pb:
				return pa > pb
		REC_SORT_RESULT:
			var ka: String = _rec_result_key(a)
			var kb: String = _rec_result_key(b)
			if ka != kb:
				return ka < kb
		_:
			var ta: String = str(a.get("created_at", ""))
			var tb: String = str(b.get("created_at", ""))
			if ta != tb:
				return ta > tb
	return str(a.get("id", "")) > str(b.get("id", ""))


## 排序序键（纯函数，也给判据用）：结果名 + 原因，取不到排到最后。
func _rec_result_key(e: Dictionary) -> String:
	var w: String = str(e.get("winner", ""))
	if w == "":
		return "zzz_未终局"
	return "%s_%s" % [w, str(e.get("reason", ""))]


## 行文本 = **搜索的靶子也是它**（所见即所搜：靶子与显示同一个真源，
## 否则会出现"屏幕上明明有这几个字，搜不到"）。
func _rec_row_text(e: Dictionary) -> String:
	var plies: int = int(e.get("plies", 0))
	var res: String = _rec_result_text(e)
	var tm: String = str(e.get("created_at", ""))
	if tm.length() > 16:
		tm = tm.substr(0, 16)
	return "%s · %s · %d手 · %s · 种子%d · %s" % [
		MenuModel.board_label(int(e.get("board_type", -1))), _rec_title(e),
		plies, res, int(e.get("board_seed", 0)), tm]


## 「这一局是谁跟谁下的」——棋谱列表的第二列。
## ★ 用户口令（2026-10-22）：「棋谱怎么没有命名，我怎么知道是哪两个AI打？」——
##   原来这一列显示的是 `mode` 名（`MenuModel.mode_label`），而**机器对局的 mode 也是 LOCAL**
##   ⇒ 三对 AI 的谱在列表里长得一模一样（全是"本地"）。
## ★ 数据来源是索引里的 `players` 投影（由 `GameRecord._index_entry()` 写；索引是列表页唯一读源）。
## ★ 取不到双方名时**退回模式名**（不是显示空/占位）：2026-10-22 之前的老索引没有 `players`，
##   退回 `mode` 名至少还是"这条谱是什么玩法"，比一片空白有用（跑一次 `--recmig` 可补齐）。
func _rec_title(e: Dictionary) -> String:
	var pv: Variant = e.get("players")
	if typeof(pv) == TYPE_DICTIONARY:
		var b: String = str((pv as Dictionary).get("black", ""))
		var w: String = str((pv as Dictionary).get("white", ""))
		if b != "" and w != "":
			return "%s vs %s" % [b, w]
	return _rec_mode_name(int(e.get("mode", -1)))


func _rec_mode_name(mode: int) -> String:
	# ★ 显示名统一走 `MenuModel.mode_label` 这一个口（"联机"是棋谱的叫法，与菜单"线上"不同）
	if mode == GameConfig.ONLINE:
		return "联机"

	return MenuModel.mode_label(mode)


func _rec_result_text(e: Dictionary) -> String:
	var w: String = str(e.get("winner", ""))
	if w == "":
		return "未终局"
	var wn: String = {"BLACK": "黑胜", "WHITE": "白胜", "DRAW": "和"}.get(w, w)
	var rs: String = str(e.get("reason", ""))
	var rn: String = {"SCORE": "终局", "RESIGN": "认输", "INTERRUPTED": "中断"}.get(rs, rs)
	return "%s(%s)" % [wn, rn]


# ---------------- 列表重建 / 勾选 ----------------

func _rec_rebuild_rows() -> void:
	if _rec_rows_box == null or not is_instance_valid(_rec_rows_box):
		return
	for c in _rec_rows_box.get_children():
		# ★ 先 `remove_child` 再 `queue_free`：只 `queue_free` 的话它要到**帧末**才真的离开
		#   容器 ⇒ 同一帧内数行数的判据会数到"上一批 + 这一批"（而屏幕上只有这一批）。
		_rec_rows_box.remove_child(c)
		c.queue_free()
	var list: Array = _rec_filtered()
	if list.is_empty():
		# ★ 空态也要**说出为什么空**：库是真空的、还是被搜索筛没了 —— 两者长得一样，
		#   而用户按"搜错了"去改搜索框的前提是**知道**是搜索筛的。
		var why: String = "（棋谱库是空的：对局结束后会自动入库）"
		if not _rec_idx.is_empty():
			var q_now: String = _rec_search.text.strip_edges() \
				if _rec_search != null and is_instance_valid(_rec_search) else ""
			# ★ 分类筛选也可能把列表筛空（比如库里还没有机器对局）—— 那时不许印成
			#   "没有匹配「」的"（空引号 = 用户会以为自己搜错了，而去改一个本来就没填的框）。
			if q_now == "" and _rec_kind != REC_KIND_ALL:
				why = "（%d 条棋谱里没有「%s」）" % [_rec_idx.size(), REC_KIND_LABELS[_rec_kind]]
			else:
				why = "（%d 条棋谱里没有匹配「%s」的）" % [_rec_idx.size(), q_now]
		_rec_rows_box.add_child(_ui_label(why, 20))
	else:
		# ★ 上限（见 `REC_ROW_CAP` 的说明）：截断了就**明说**，别让用户以为棋谱丢了。
		var shown: int = mini(list.size(), REC_ROW_CAP)
		for i in shown:
			_rec_rows_box.add_child(_rec_row(list[i] as Dictionary))
		if list.size() > shown:
			_rec_rows_box.add_child(_ui_label(
				"（只显示前 %d 条，共 %d 条 —— 用搜索缩小范围）" % [shown, list.size()], 18))
	# 全选框跟着列表走（在闸内写，免得它的 `toggled` 反过来把逐行勾选改掉）
	_rec_ui_lock = true
	if _rec_all_box != null and is_instance_valid(_rec_all_box):
		var all_on: bool = not list.is_empty()
		for e in list:
			if not bool(_rec_sel.get(str((e as Dictionary).get("id", "")), false)):
				all_on = false
				break
		_rec_all_box.button_pressed = all_on
		_rec_all_box.text = "全选（%d 条）" % list.size()
	_rec_ui_lock = false


func _rec_row(e: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var id: String = str(e.get("id", ""))
	var cb := CheckBox.new()
	cb.button_pressed = bool(_rec_sel.get(id, false))
	# ★ 行是**运行期重建**的（每次搜索/排序/勾选都整批换掉）⇒ 墨色必须**就地套**：
	#   只靠建页那一次整树刷，新造出来的勾选框会退回引擎默认的浅灰字
	#   （本轮目检实测：宣纸下「全选」与行内勾选框都是灰的）。标签与按钮各自在工厂里套，
	#   勾选框没有工厂，所以在这里补——**同一支 `_ink_apply_control()`**，不另写一份键表。
	_ink_apply_control(cb, GameConfig.ink_color(), GameConfig.accent_color())
	cb.toggled.connect(func(on: bool) -> void: _rec_toggle(id, on))
	row.add_child(cb)
	var lbl := _ui_label(_rec_row_text(e), 20)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(_rec_make_action("复盘", func() -> void: _rec_open(id)))
	row.add_child(_rec_make_action("删除", func() -> void: _rec_do_delete([id])))
	return row


func _rec_toggle(id: String, on: bool) -> void:
	_rec_sel[id] = on
	if _rec_ui_lock:
		return
	# 逐行改动之后重算全选框（不重建行 —— 重建会把用户正在点的那个控件销毁掉）
	_rec_ui_lock = true
	if _rec_all_box != null and is_instance_valid(_rec_all_box):
		var list: Array = _rec_filtered()
		var all_on: bool = not list.is_empty()
		for e in list:
			if not bool(_rec_sel.get(str((e as Dictionary).get("id", "")), false)):
				all_on = false
				break
		_rec_all_box.button_pressed = all_on
	_rec_ui_lock = false


func _rec_select_all(on: bool) -> void:
	if _rec_ui_lock:
		return
	_rec_ui_lock = true
	for e in _rec_filtered():
		_rec_sel[str((e as Dictionary).get("id", ""))] = on
	if _rec_rows_box != null and is_instance_valid(_rec_rows_box):
		for c in _rec_rows_box.get_children():
			# 行结构：CheckBox 是第 0 个孩子（`_rec_row()` 的构造顺序就是真源）
			if c.get_child_count() > 0 and c.get_child(0) is CheckBox:
				(c.get_child(0) as CheckBox).button_pressed = on
	_rec_ui_lock = false


## 当前列出的 id（导出"没勾就导全部"用）。
func _rec_visible_ids() -> Array:
	var out: Array = []
	for e in _rec_filtered():
		out.append(str((e as Dictionary).get("id", "")))
	return out


## 勾选且**当前列出的** id。
## ★ 为什么必须限定"当前列出"：被搜索筛掉的行如果还算数，用户在搜索状态下点
##   「删除所选」，删掉的就是**屏幕上看不见的那些** —— 这是本面板最危险的一处，
##   所以删除的输入只从这条函数取（唯一真源）。
func _rec_checked_ids() -> Array:
	var out: Array = []
	for e in _rec_filtered():
		var id: String = str((e as Dictionary).get("id", ""))
		if bool(_rec_sel.get(id, false)):
			out.append(id)
	return out


# ---------------- 动作：复盘 / 删除 / 导出 / 导入 ----------------

## **写交接**（唯一入口）：把"要看哪条谱"记进 Autoload。
## ★ 与 `_rec_open()` 分开是为了**能被判据直接调**：`_rec_open()` 会真的换场景，
##   自检里一调整条跑道就没了。⇒ 判据量这一半（交接的写入），另一半（换场景）交给
##   结构守卫守"`_rec_open()` = 本函数 + `change_scene`"（接线不是靠注释保证的）。
func _rec_request_open(id: String) -> bool:
	if id == "" or GameRecord.load_by_id(id).is_empty():
		_rec_status_set("这条棋谱读不出来（文件可能已被删除）")
		return false
	GameConfig.request_replay(id)
	return true


func _rec_open(id: String) -> void:
	if not _rec_request_open(id):
		return
	_rec_status_set("正在打开棋谱…")
	Transition.change_scene("res://game.tscn")


func _rec_ask_delete() -> void:
	var ids: Array = _rec_checked_ids()
	if ids.is_empty():
		_rec_status_set("先勾选要删的棋谱（或用「全选」）")
		return
	# ★ 二次确认：删除是**不可逆**的（`GameRecord.delete_by_id()` 直接删文件，没有回收站）。
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "要删除选中的 %d 条棋谱吗？\n此项不可撤销。" % ids.size()
	dlg.title = "删除棋谱"
	dlg.confirmed.connect(func() -> void:
		_rec_do_delete(ids)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered()


## 真删。返回**索引实际减少的条数**（不是"调了几次 API"——`delete_by_id()` 对不存在的
##   id 也返回 true，用返回值当"删掉了"会虚报）。
func _rec_do_delete(ids: Array) -> int:
	var n_before: int = _rec_idx.size()
	for id in ids:
		_rec_sel.erase(str(id))
		GameRecord.delete_by_id(str(id))
	_rec_load()
	var gone: int = n_before - _rec_idx.size()
	_rec_status_set("已删除 %d 条" % gone)
	return gone


func _rec_ask_export(is_sgf: bool) -> void:
	var ids: Array = _rec_checked_ids()
	if ids.is_empty():
		ids = _rec_visible_ids()      # 没勾就导"当前列出的全部"
	if ids.is_empty():
		_rec_status_set("没有可导出的棋谱")
		return
	var ext: String = ".sgf" if is_sgf else ".json"
	var stamp: String = Time.get_datetime_string_from_system() \
		.replace("-", "").replace(":", "").replace("T", "-").replace(" ", "_")
	var def_path: String = "%s/export_%s%s" % [GameRecord.records_dir(), stamp, ext]
	# ★ headless 下不弹文件对话框（`FileDialog` 是 Window，headless 里弹不出来，
	#   而"弹不出来"会表现为静止不动 ⇒ 判据挂死）。落盘路径仍走同一个写点。
	if DisplayServer.get_name() == "headless":
		_rec_status_set("已导出 %d 条到 %s" % [ids.size(), _rec_export_write(def_path, ids, is_sgf)])
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.current_path = ProjectSettings.globalize_path(def_path)
	dlg.add_filter("*.%s" % ext.substr(1), "棋谱")
	dlg.file_selected.connect(func(p: String) -> void:
		_rec_status_set("已导出 %d 条到 %s" % [ids.size(), _rec_export_write(p, ids, is_sgf)])
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(760, 520))


## **唯一写盘点**（导出）：测与真用走同一条。
func _rec_export_write(path: String, ids: Array, is_sgf: bool) -> String:
	var text: String = _rec_export_text(ids, is_sgf)
	if text == "":
		return ""
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return path


## 导出文本（**纯函数**，判据直接断言它）。多条时按顺序拼接：
##   · SGF：多个 `(…;)` 树并列（SGF 允许一份文件里放多棵树，标准工具都能读）
##   · JSON：一个数组（自家 `from_json` 认不出来 —— 那字段是单份的，故数组走 `_rec_import_one`）
func _rec_export_text(ids: Array, is_sgf: bool) -> String:
	if is_sgf:
		var blocks: Array[String] = []
		for id in ids:
			var s: String = GameRecord.to_sgf(GameRecord.load_by_id(str(id)))
			if s != "":
				blocks.append(s)
		return "\n".join(blocks)
	var arr: Array = []
	for id in ids:
		var rec: Dictionary = GameRecord.load_by_id(str(id))
		if not rec.is_empty():
			arr.append(rec)
	return JSON.stringify(arr, "\t")


func _rec_ask_import() -> void:
	if DisplayServer.get_name() == "headless":
		_rec_status_set("headless 下不弹文件对话框（判据走 _rec_import_text）")
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.json", "棋谱 JSON")
	dlg.file_selected.connect(func(p: String) -> void:
		var n: int = _rec_import_text(FileAccess.get_file_as_string(p))
		_rec_status_set("导入 %d 条" % n)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(760, 520))


## 导入（**纯逻辑 + 唯一写点**：写盘一律走 `GameRecord.save()`）。
## 接受：单份谱字典 / 谱数组（自家导出格式）；其它一律不认（返回 0，不抛错）。
func _rec_import_text(text: String) -> int:
	var parsed: Variant = JSON.parse_string(text)
	var n: int = 0
	if typeof(parsed) == TYPE_ARRAY:
		for e in (parsed as Array):
			if typeof(e) == TYPE_DICTIONARY and _rec_import_one(e as Dictionary):
				n += 1
	elif typeof(parsed) == TYPE_DICTIONARY:
		if _rec_import_one(parsed as Dictionary):
			n += 1
	_rec_load()
	_rec_status_set("导入 %d 条" % n)
	return n


func _rec_import_one(d: Dictionary) -> bool:
	# ★ 走 `from_json`→`save` 这条既有真源：既有的两道闸（格式版本 + 落盘目录改道）
	#   都在那条路上；自己拼一份就是又一条"两处都记得"的路。
	var norm: Dictionary = GameRecord.from_json(GameRecord.to_json(d))
	if norm.is_empty():
		return false
	# ★★ 必须**重新发 id**：导入的谱多半带着原 id（尤其是从别处导回来的），
	#   沿用就会**静默覆盖**本地同名的那条 —— 而"导入"的语义是"加进来"，不是"替换"。
	#   （`save()` 见到空 id 会 `make_id()` 一个新号。）
	norm.erase("id")
	return GameRecord.save(norm) != ""


func _rec_cycle_sort() -> void:
	_rec_sort = (_rec_sort + 1) % REC_SORT_COUNT
	if _rec_sort_btn != null and is_instance_valid(_rec_sort_btn):
		_rec_sort_btn.text = REC_SORT_LABELS[_rec_sort]
	_rec_rebuild_rows()


## 分类循环：全部 → 我的对局 → 机器对局 → 全部。与 `_rec_cycle_sort()` 逐字同构。
func _rec_cycle_kind() -> void:
	_rec_kind = (_rec_kind + 1) % REC_KIND_COUNT
	if _rec_kind_btn != null and is_instance_valid(_rec_kind_btn):
		_rec_kind_btn.text = REC_KIND_LABELS[_rec_kind]
	_rec_rebuild_rows()


func _rec_status_set(msg: String) -> void:
	if _rec_status != null and is_instance_valid(_rec_status):
		_rec_status.text = msg
	print("[records] %s" % msg)


# 菜单瓷砖基准半径：由 行高 与 视口宽占比 两者取小。
#  · 高度：**按「行标题占完之后剩下的可用高度」精算**，见 _row_above_need()。
#    这是"行标题压到瓷砖标签"这个反复出问题的点的唯一正解 —— 别再回到"拍一个
#    ROW_HEAD_PAD 数字"的老路：那等于让人眼去心算「标题字高 + 净空 + 标签字高 +
#    间隙 + 半高」这一串，任何一项变动（改字号档位、改行数）都会让它失准，
#    而失准的表现就是静默重叠。
#  · 宽度：视口宽 * ROW_WIDTH_RATIO / ROW_SPAN（本行 3 块并排的总宽 = ROW_SPAN*R）
# shrink：个别行的额外收缩系数（当前棋盘行为 1.0 = 不收缩，与对战方式行等大）。
func _tile_base_r(band_h: float, shrink: float = 1.0) -> float:
	# 行标题段整体让出去之后，块区域高度 = bandH - need，块中心居中于该区域。
	# 故块心**上方**可用的高度只有块区域的一半：(bandH - need)/2。
	# 这半高要放下「块自己的标签 + 间隙 + 半高」；而 `_row_above_need()` 里
	# 已经含了「标签 + 间隙」那一项，故此处**只需再减半高**，不要再减一遍标签高。
	var need: float = _row_above_need(band_h)
	var avail: float = (band_h - need) * 0.5
	# ★ 半高比**必须读真源**（原先这里写死 0.73，与形状那边的 0.73 是两份 ⇒ 改一边就分叉）
	var by_h: float = maxf(0.0, avail) / menu_btn_h_ratio
	var by_w: float = size.x * ROW_WIDTH_RATIO / ROW_SPAN
	# ★★ 2026-10-09：把「块本体下沿别贴行带底」（`ROW_HEAD_PAD`）**收编进来**。
	#   原先这一道闸散在各 `_layout_*_row` 里、`_portrait_band_cap()` 看不见它 ⇒ 竖屏收敛
	#   按 `by_w` 解出 bandH，布局却再被 below_clr 压一小截，`--portraittest` ③ 的
	#   「顶满宽度」就永远差一口气（4 行后实测 49.58 vs 上限 52.68，而它还报"通过"）。
	#   below_clr 与 by_h 只差常数 `ROW_HEAD_PAD/半高比`，是 band_h 的纯函数 ⇒ 收进来
	#   既不改横向排布、又让"收敛到哪一档"只有一个真源。
	var below_clr: float = band_h - ROW_HEAD_PAD - (need * 0.5 + band_h * 0.5)
	var by_b: float = maxf(0.0, below_clr) / menu_btn_h_ratio
	return minf(minf(by_h, by_b), by_w) * shrink


## 竖屏行带高度的上限：把行带高度收敛到「行内瓷砖刚好被**宽度**顶满」的那一档。
## 之后再高的行带只会把空隙变大，瓷砖一点也不会变大（`_tile_base_r` 取 min，宽度已是瓶颈）。
##
## ★ 为什么用**搜索**而不是解析求导：`_tile_base_r` 里的 `need` 含 `_font_h(字号)`（字体实高），
##   而字号又由 `_row_head_font_size(bandH)` 按行带高度分档。自己再推一遍公式等于把
##   「行标题让位」这件事写两处 —— 字体/字号档位一改就分叉（而分叉的表现是静默重叠，
##   本项目在这一处返工最多）。直接问它自己最稳。
## ★ 但**不能直接二分**：`_row_head_font_size()` 在 145/190 有跳变，字号一跳
##   `need` 就跳、`R` 会**掉一格** → `_tile_base_r` 不是单调函数，二分的"不变量"不成立。
##   （⚠️ 这两个跳变点原为 `130/145/165/190`，2026-10-15 五档收三档时同步改；
##    第③步保险的实测数值 `155×1.1=170` 是按**旧**跳变点 165 举的例子 ——
##    新跳变点是 145/190，170 已不再落在任何跳变点附近，但保险本身照样要留：**档位一改就可能用上**。）
##   所以改成三步：①先探到一个「R 确实顶满」的高度 ②往下二分收敛 ③乘余量后**再校验一次**，
##   不满足就一格格往上抬。第③步是给跳变留的保险（本机实测 155×1.1=170 恰好没跨过 165 的
##   跳变点，所以这次保险没用上 —— 但档位一改就可能用上，别删）。
## ★ 踩过的两个错（都写在这里，别再走一遍）：
##   ① 二分下界写过 `b * 0.5`。真边界（≈155）在区间 `[390, 780]` 之外 → 二分只能收敛到
##      区间下界 390，"看着收敛了"其实一步没动（实测 hi=390 恒等于 lo）。下界必须是低锚点。
##   ② 一度以为"cap 处 R 掉到 52.7 = 顶不满" —— 那是把 `by_w` 手算错了
##      （`ROW_SPAN = 6 + 2*TILE_GAP_RATIO = 8.2`，不是 7.8）。52.68 恰好**就是** by_w。
##      → 手算常数去核对机器输出，等于用一个错的东西去判另一个东西，只会绕远路。
func _portrait_band_cap() -> float:
	var by_w: float = size.x * ROW_WIDTH_RATIO / ROW_SPAN
	# ① 先找一个 R 已经顶到宽度的高度（从半高往上走，最多几步）
	var b: float = size.y * 0.5
	while b < size.y and _tile_base_r(b) < by_w - 0.01:
		b *= 1.15
	b = minf(b, maxf(size.y, 41.0))
	# ② 二分收敛到下降沿边界
	# ⚠️ 下界必须是「明显不够高」的值（R(下界)=0），**不能**取 `b * 0.5`：
	#    第一版写成 [b/2, b]，而真边界（≈168）在区间之外 → 二分只能收敛到区间下界 390，
	#    看着"收敛了"其实一步没动（实测 hi=390 = lo）。判据写得再漂亮，区间错了也是白跑。
	var lo: float = 40.0                   # R(40) = maxf(0, ...) = 0 < by_w，是安全的低锚点
	var hi: float = b
	for _i in 40:                          # 40 次 → 亚像素，纯算术可忽略
		var mid: float = (lo + hi) * 0.5
		if _tile_base_r(mid) >= by_w - 0.01:
			hi = mid                        # 高度还够 → 还能更矮
		else:
			lo = mid
	# ③ 余量之后必须**仍然顶满**（否则瓷砖白小一圈，正是第一版的毛病）
	var cap: float = hi * PORTRAIT_BAND_SLACK
	while cap < size.y and _tile_base_r(cap) < by_w - 0.01:
		cap += 2.0
	if "--layoutdbg" in _argv():
		print("[bandcap] by_w=%.2f hi=%.1f cap=%.1f R(cap)=%.2f（顶满=%s）" % [
			by_w, hi, cap, _tile_base_r(cap),
			str(_tile_base_r(cap) >= by_w - 0.01)])
	return minf(cap, size.y)

## 行带顶到「块中心」之间必须容纳的总高度（不含块自身的半高 = 半高比·R）。
## 自上而下依次是：行标题上留白 → 行标题文字 → 净空。
##
## ★★ 2026-10-09：末尾那两项「瓷砖标签文字 + 标签与瓷砖的间隙」**整段删除** ——
##   文字改画在按钮**内部**（用户口令）⇒ 行带上方不再需要给"挂在按钮外的字"留位置。
##   这一段约 35px/行（fs=22 的实高 31 + LABEL_GAP 4），删掉后 `_tile_base_r()` 的 `avail`
##   变大 ⇒ **按钮半径随之变大**（这就是"完善布局"腾出来的空间，不是凭空调参）。
##
## ⚠️ 为什么行标题要算进这一串（这是本项目最绕、返工最多的一处）：
## 瓷砖标签画在菱形上顶点之上，行标题画在行带顶端，两者在**同一条纵向通道**里一前一后；
## 而方块的中心又固定在行带中心 → 任何一方变高都会挤到另一方。
## 早期版本给行标题只预留 8px（ROW_HEAD_PAD），但 fs=24 的标题实高就有 34px，
## 少算的 26px 恰好被当时 `_draw_label` 的基线 bug（文字整体上浮 26px）掩盖掉了 ——
## 也就是说，真机上"看起来没问题"是靠另一个 bug 顶出来的。
## 修掉基线 bug 后重叠立刻显形，本函数就是把这份欠账补回来。
func _row_above_need(band_h: float) -> float:
	return ROW_HEAD_TOP + _font_h(_row_head_font_size(band_h)) + ROW_HEAD_CLEAR

## 某行「瓷砖中心」的 y。
##
## 为什么不是简单取行带中心（bandTop + bandH/2）：
## 行标题占据行带顶部那一段，而块自己的标签又画在块上方 —— 两者叠在同一个方向。
## 若块中心仍固定在行带中心，行标题一高就直接压到标签上（这正是历史 bug）。
## 所以把块中心**下移半个「行标题段」**，使行标题段真正从块的可用区域里让出去：
##   行带 = [行标题段 HEAD][块区域]，块区域以自身中心对称
##   → 中心 = bandTop + HEAD + (bandH - HEAD)/2 = bandTop + (bandH + HEAD)/2
##
## 「开始」行没有行标题，HEAD = 0，中心即行带中心（与原行为一致）。
func _row_center_y(band_top: float, band_h: float, has_head: bool) -> float:
	if not has_head:
		return band_top + band_h * 0.5
	return band_top + (_row_above_need(band_h)) * 0.5 + band_h * 0.5

## 某字号的文字行高（ascent + descent）。绘制与自检统一用它，避免各处口径不一。
func _font_h(font_size: int) -> float:
	var f: Font = UITheme.body_font()
	return f.get_ascent(font_size) + f.get_descent(font_size)

# ═══════════════════════════════════════════════════════════════════════════
# 瓷砖「外形尺寸」真源（2026-10-15 新增）
# ═══════════════════════════════════════════════════════════════════════════
#
# ## 用户口令
# 「棋盘行『爱因斯坦』小一号怎么解：**再改按钮形状，和新版全局按钮相同，使它贴近文字的形状**」
# —— 即：**不再把长标签的字号压小**，改为让**形状跟着文字走**。
#
# ## 症状（改前实测）
# 「爱因斯坦」4 字在 fs=22 时文本宽 ≈88px，而棋盘行块的内腔只有 `2R − 2·BTN_TEXT_PAD`
# ≈ 49.7px ⇒ `_label_fs_fit()` 把字号一路压到 **12**，同行的「彭罗斯」却是 22。
# 根因不是字号选错，是**块的形状按「半径 × 半高比」定死、和文字没有任何关系**。
#
# ## 口径（= 新版全局按钮那一支）
#   · 半宽 = max(旧设计半宽 `r_base`, (本行**最宽标签**文字宽 + 2 × `BTN_PAD_PAGE.x`) / 2)
#   · 半高 = `r_base × menu_btn_h_ratio`   ← **纵向一个像素都不动**
#   · 圆角 = `DIALOG_CORNER`（**绝对像素**，与全局按钮同一个常量 ⇒ 形状真的"相同"，不是胶囊）
# ⇒ 于是「同层等重」由**形状**保证，`_label_fs_fit()` 退化成"整行真的放不下时才用"的兜底。
#
# ## ★★ 为什么半宽取 `max(r_base, 文字所需)` 而不是"纯贴身"
# 纯贴身（半宽只由文字定）会把**短标签的块一起缩水**，而 `r_base` 是**跟着视口**走的
# （`_tile_base_r` 的高度/宽度预算）⇒ 大窗口下整页菜单会退化成一排"固定像素的小按钮"、
# 不再随分辨率缩放。更硬的一条在竖屏：720 宽下 4 字标签需要 ≈244px，行宽上限只有 432px，
# 纯贴身会退化成"缩字号"，直接跌破移动版 `TEXT_MIN_PT = 17pt` 底线（`judge_mobile_layout()`）。
# 取 max 的语义正好就是用户那句话 —— **形状保证"文字一定装得下"，但不把已经合适的东西改小**：
# 「爱因斯坦」从 12 回到 22，而其余各行（标签都只有 2 字）**一个像素都不动**（可回归验证）。
#
# ## ★ 为什么是「本行统一半宽」而不是「每块各自贴身」
# 棋盘行是**循环轮播**（`_board_row_pos` / `_board_pitch` / `_board_focus_x_for` 全建立在
# **等距**模型上）。混宽会让：
#   ① 相邻块间距随槽位不等 ⇒ 轮播滑动时"一跳一跳"；
#   ② `_board_focus_x_for()` 的解析居中失效（推导里两端的半宽会相消，前提是它们**相等**）；
#   ③ `_board_row_solve()` 的联合求解（半径 × 焦点）没有定义。
# 而**除棋盘行外，其余每行的标签本来就等长**（大小/对战方式/入口四块全是 2 字，「开始」1 块）
# ⇒ 「本行统一 = 本行最宽标签」在那些行与"每块各自贴身"**完全等价**，
#   只有棋盘行（2/4 字混排）会有差别，而那一行恰恰**必须**等宽。
#
# ## ★ 降级顺序（用户拍板：「先缩间距，再整体缩字号」）
#   `_tile_box()` 里就是这两步，且**行内统一**缩 —— 所有块同时变小，
#   绝不出现"同一行里某个标签比其他小一号"（那正是本次要消灭的现象）。

## 某块在**旧设计半宽** `r_base` 下的半高（= `r_base × menu_btn_h_ratio`）。
## ★ 形状改口径后纵向仍走这一支 ⇒ `_tile_base_r()` 的纵向预算 / 行间净空 / [对齐] 判据
##   全部不用动（这正是把改动面压住的关键）。
func _tile_hh_for(r_base: float) -> float:
	return maxf(r_base, 0.0) * menu_btn_h_ratio

## 一段文本在 `fs` 下、按**新版全局按钮**的内边距所需的最小半宽。
func _tile_hw_for(text: String, fs: int) -> float:
	var f: Font = UITheme.body_font()
	var tw: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return (tw + 2.0 * GameConfig.BTN_PAD_PAGE.x) * 0.5

## 一行 `labels` 在 `fs` 下的**统一半宽** = `max(旧设计半宽, 本行最宽标签所需)`。
## 纯几何（只依赖入参）⇒ 布局与判据共用同一份（铁律 31）。
func _tile_hw_row(r_base: float, labels: Array, fs: int) -> float:
	var hw: float = maxf(r_base, 0.0)
	for s in labels:
		hw = maxf(hw, _tile_hw_for(str(s), fs))
	return hw


# ═══════════════════════════════════════════════════════════════════════════
# 全页瓷砖「统一外形尺寸」真源（2026-10-16）
# ═══════════════════════════════════════════════════════════════════════════
#
# 用户口令：「棋盘选项不需要滚动了，删掉，然后棋盘、大小、对战方式、开始按钮
#            都统一成现在棋盘行按钮的大小；底下一行高度也与上面统一，间距稍微拉大一点」
#
# ## 改前实测（真窗口 1152×681，`--layoutdbg` 的 [navdbg] 块包围盒）—— 同一页并存**三档**大小
#   · 棋盘行        120×56   （半宽被 4 字「爱因斯坦」撑到 60；r = 38.5）
#   · 大小／对战方式 77×56   （2 字标签 ⇒ 半宽 = r = 38.5）
#   · 开始          132×96   （`by_h_act` 那条"无行标题、可放大一档"的专用分支，r = 65.8）
#   · 底部 nav     ~103×86   （自己一套 `_nav_fit_solve`，R 由 `FOOT_BAND_H` 反解 ⇒ 58.9）
# ⇒ 用户看到的"没对齐"就是这三档。
#
# ## 本真源把 **四行内容 + 底部入口行** 收成一份 `{r, hw, hh, fs, gap}`
#   · `r`   = `_tile_base_r(band_h)` —— 四行共用**同一个** `bandH` ⇒ 天然等高
#   · `hw`  = `max(r, 全页最宽标签所需半宽)`（只增不减，沿用 `_tile_hw_row` 的口径）
#   · `hh`  = `_tile_hh_for(r)`
#   · `gap` = 全页**统一间距**（各行块间距一致，观感才整齐）
#
# ## ★★ 为什么半宽取「**全页**最宽」而不是「本行最宽」（= `_tile_box` 的口径）
#   用户要的是**按钮一样大**。「本行最宽」在改前推出的是：棋盘行 60、其余行 38
#   ⇒ 屏幕上仍是两种宽窄 —— 那正是用户报的现象本身。
#   取全页最宽恰好落在棋盘行那一档（「爱因斯坦」是全页最长标签）
#   ⇒ 其余行"长高"到棋盘行尺寸，与用户原话「统一成**现在棋盘行按钮**的大小」逐字相符。
#   ⚠️ 连带：`hw` 的下限仍是 `r`（只增不减），所以本口径**不会**把任何一块改小 ——
#     改的只有"其余行变大"。
#
# ## ★★ 横向可用宽度改用 `size.x − 2·ROW_EDGE_MARGIN`（**与 `_nav_zone_rect()` 同口径**）
#   不再用 `ROW_WIDTH_RATIO`(0.60)。理由不是"想放宽"，而是**棋盘行改平铺之后口径必须换**：
#   原先棋盘行是轮播（只显示一个周期、块宽由 pitch 摊开、另有 `_board_row_solve` 的
#   横向收缩），而现在是 **5 块真平铺**。竖屏 720 下 `720×0.60/10 = 43.2` 会把统一半宽
#   压到「爱因斯坦」（4 字）装不下、一路跌破 `BTN_TEXT_FS_MIN`；
#   换成 `720−56 = 664` 后 5 块正好放得下，且**一个字号都不缩**。
#   ⚠️ 这同时让横屏的块间距变松（正是用户要的「间距稍微拉大一点」），不是副作用。
#
# ## 溢出的处理仍然**不外推**：真放不下时 `gap` 触底（`0.05·r`，与各 `_layout_*_row` 同口径），
#   再由 `_tile_box()` 那套"先缩间距、再整行缩字号"兜底。本轮实测三档常用横屏 + 竖屏
#   **都不触发**（读数见 `--layoutdbg` 的 `[uni]` 行）。
## 全页统一尺寸的**行花名册**（块数 + 标签）—— **与当前页无关**。
##
## 返回 `{cnts: Array, labels: Array}`：
##   · `cnts[gi]` = 第 gi 行**会上屏**的块数（棋盘行的禁用占位不算，与 `_layout_setup()`
##     收集段同一条判据）；
##   · `labels`   = 全部会上屏的标签 —— `_tile_uniform_box()` 用它求"全页最宽"。
##
## ★★ 为什么必须独立成一个**页无关**的真源（2026-10-16 `--menutest` ⑥d 实测报红）：
##   `_uni_box` 原先按**当前页**的 `_items` 现数行块数，而 `_items` 是**按页重建**的：
##   「练习」页有 棋盘5 / 大小3 / 对战方式3 / 开始1 + 底栏4，其余三页**只有底栏那 4 块**。
##   ⇒ `gap` 的上限在练习页被"5 块那一行"压到 63.3、在别的页放宽到 92.7
##   ⇒ **同一条底栏切一次页就整行跳一格**（实测「练习」块心 x 227.2 ↔ 183.0，差 44.2px）。
##   底栏的契约是"四个面板**固定不动**"（`_footer_entry_descriptors()` 那段），
##   所以它的尺寸只能由一份**不随页变**的花名册推出来。
##
## ⚠️ 花名册必须与 `_set_page(PAGE_MAIN)` 真正建出来的项**逐行一致** —— 两处各记一份就会
##   静默分叉：症状不是报错，而是"底栏尺寸悄悄变了"。这份一致性由 `_row_align_test()` 的
##   `[花名册]` 段**逐行对数**守（练习页上拿它与真实 `_items` 的分组计数比，不等即报红）。
func _main_row_roster() -> Dictionary:
	var cnts: Array = []
	var labels: Array = []
	# ① 棋盘行：顺序与条目全部来自 `BOARD_KINDS`（与 `_set_page` 同一真源），只数**启用**项
	var n_board := 0
	for kind in BOARD_KINDS:
		if not bool(kind["enabled"]):
			continue              # 禁用占位不上屏（「敬请期待①②」）
		n_board += 1
		labels.append(str(kind["label"]))
	cnts.append(n_board)
	# ② 大小行：三个槽位，标签随选中棋盘变（两种含义都恰好 3 槽，见 `_set_page`）
	for slot in [GameConfig.RANDOM, GameConfig.STANDARD, GameConfig.ENHANCED]:
		labels.append(_size_slot_label(slot))
	cnts.append(3)
	# ③ 对战方式行：本地 / 磐石 / 疾风 / 流水（顺序与 `_set_page` 的 append 顺序一致）
	#   ⚠️ 加档必须同步这里 —— `--labeltest` 的 [花名册] 段按「块数序列」对拍，
	#      本行少写一块就当场红（2026-10-22 加「流水」时正是这样被逮住的）。
	for m in [MODE_LOCAL, MODE_VS_AI, MODE_XGAI, MODE_LIUSHUI]:
		labels.append(_mode_label(m))
	cnts.append(4)
	# ④ 开始行（无行标题，单块）
	labels.append("开始")
	cnts.append(1)
	# ⑤ 底栏入口行：四个面板共用同一份真源 ⇒ 这里正是"页无关"的落点
	var f_n := 0
	for d_n in _footer_entry_descriptors():
		f_n += 1
		labels.append(str(d_n["label"]))
	cnts.append(f_n)
	return {"cnts": cnts, "labels": labels}

func _tile_uniform_box(band_h: float, row_cnts: Array, labels_all: Array) -> Dictionary:
	var r_base: float = _tile_base_r(band_h)
	var fs: int = _label_font_size_for("board")
	var hw: float = _tile_hw_row(r_base, labels_all, fs)
	var hh: float = _tile_hh_for(r_base)
	# 可用横向宽度：与底部入口行同一支口径（左右各留 ROW_EDGE_MARGIN）
	var avail: float = maxf(1.0, size.x - 2.0 * ROW_EDGE_MARGIN)
	# 名义间距：块越宽缝越宽（与 TILE_GAP_RATIO 同源，不再另立系数）
	var gap: float = hw * TILE_GAP_RATIO
	for c in row_cnts:
		var cnt: int = int(c)
		if cnt < 2:
			continue
		var fit_c: float = (avail - 2.0 * hw * float(cnt)) / float(cnt - 1)
		gap = minf(gap, fit_c)
	gap = maxf(gap, hw * 0.05)
	return {"r": r_base, "hw": hw, "hh": hh, "fs": fs, "gap": gap}

## 行标题字号：行带越矮字号越小，为「标题 + 标签 + 菱形」腾出纵向空间。
## 为什么需要：真机逻辑视口是 1152×720，4 行时 bandH 只有 125px，
## 而「行标题(≈36) + 间隙 + 标签(≈31) + 菱形全高」的固定占用会超出行带（实测超 7px），
## 表现为「棋盘/对战方式」小标题压到瓷砖标签上。把标题字号随行高收缩即可化解，
## 且矮行本来也不需要大字号标题，观感更协调。
##
## ★★ 2026-10-15：**五档收成三档**（用户拍板）。原五档 `26/24/22/20/18`，
##   跳变点 `190/165/145/130`。收档不是审美偏好，是**实测**出来的。
##
##   横屏 4 行时 `bandH = (视口高 − 256) / 4`（`256 = TOP_MARGIN 132 + ROW_HEAD_TOP 6
##   + BOTTOM_MARGIN 20 + FOOT_BAND_H 86 + FOOT_GAP 12`，减出来正好 256）。
##   ⚠️ 这个式子**必须按 `_layout_setup()` 的实际口径**推 —— 我第一版拿"屏高减上下边距再除以行数"
##     去算（漏了**底部行带**那 106px），表里整列全错，差点据此得出"24 档取不到"的错误结论。
##     ⇒ 校验方式：`--labeltest` 的 `[行带] bandH(实际)` 必须与式子对得上（实测 vh=681 → 106 ✓）。
##
##   | 视口高 vh | bandH | 原档 | 收档后 |
##   |---|---|---|---|
##   | 648（**设计基准**）/ 681（本机默认窗）/ 720（真机） | 98 / 106 / 116 | 18 | 18 |
##   | 776–836 | 130–145 | 20 | **18** ← 变 |
##   | 836–916 | 145–165 | 22 | 22 |
##   | 916–1016 | 165–190 | 24 | **22** ← 变 |
##   | ≥1016 | ≥190 | 26 | 26 |
##   | 竖屏（`_portrait_band_cap()` 收敛后） | cap | 26 | 26 |
##
##   ⇒ 两条事实：
##     ① 设计基准（648）、本机默认窗（681）、真机（720）**三者本来就都落在 18 档**
##        （bandH 98/106/116 全都 < 130）—— 也就是说这一档位阶梯对"横屏正常视口"
##        根本不起作用，它只在窗口被拉高到 776 以上时才生效；
##     ② `20`/`18` 与 `24`/`22` 各自只差 **2px** —— 相邻两档差 2px 等于没分档。
##   ⇒ 收成**等距阶梯 `26 / 22 / 18`**（步长 4），跳变点 `190 / 145`：
##       · vh 776–836：20 → **18**（矮行标题小 2px，方向是**更安全**的那边 ——
##         字号只影响净空，变小不会压到标签）；
##       · vh 916–1016：24 → **22**（同理小 2px）；
##       · 其余所有区间**逐档不变**（含三档常用视口与全部竖屏）。
##   ⚠️ 阈值只在本函数里出现，**没有任何判据硬编码档位**（已核：`grep '130\.0|145\.0|165\.0|190\.0' menu.gd`
##      只命中本函数）—— 所以收档不会让谁静默变红，但也**没有判据替你守它**：
##      要改这三个数，请连同上面那张实测表一起改。
func _row_head_font_size(band_h: float) -> int:
	if band_h >= 190.0:
		return 26
	elif band_h >= 145.0:
		return 22
	return 18

# 主菜单布局：按 group 分多行（棋盘 / 大小 / 对战方式 / 开始），行首有小标题。
# 难度三档**平铺**在「对战方式」行内（与 本地/人机 并列；不折叠、也不另起一行）。
#
# ⚠️ 行数**恒为 4**（棋盘 / 大小 / 对战方式 / 开始）。「有哪些行」由 `_row_count_test()`
# 钉死；行数直接进 `_tile_base_r` 的纵向预算，行数一变整套净空全变，而同行/跨行的
# 间距断言都是按 4 行算的（它们会红，但报的是症状、不是“行数变了”这个根因）。
# ★ 沿革（**这两个数都曾经是对的 —— 引用前先看这里，别再照抄旧数**）：
#   · 4 → 3：「开始匹配」动作瓷砖随「线上+随机匹配」一起移除（选「随机匹配」曾自动进队列）。
#   · 3 → 4（2026-10-09）：按用户口令把「大小」三档**单列一行**（原先贴着选中棋盘折叠展开）。
#   ⚠️ 行数越少 = 行带越高 = 块越大，所以行数是**观感与预算的共同输入**，不是排版细节。
func _layout_setup() -> void:
	# ★★ 2026-10-02 重设计：`nav`（三入口）与 `quick`（「练习」开关）**不参与高度等分**。
	#
	#   病灶（实测）：把它们 append 进 `groups` 后，3 组变 5 组 ⇒ `bandH` 从 185 掉到 115
	#   ⇒ 块半径随之变小 ⇒ 循环行相邻块的**水平间距不够放标签** ⇒ 棋盘行五个标签糊成一片
	#   （放大截图实测；`--labeltest` 十几条子测试当时全绿 —— 它们量行带/行间/对齐，
	 #   **没有一条量"标签之间"**，已补 `_label_no_overlap_test`）。
	#
	#   修法：前 3 组（board/mode/action）**照旧等分**整个可用高度，
	#   nav/quick **不进 `groups`**，由 `_layout_footer_row()` 自取**底部行带**
	#   （屏幕最下方那条左右通带，见 `_footer_band()` / `_nav_zone_rect()`）。
	#   ★ 为什么不反过来"只给新增行分固定高度"：那会让新增行在矮视口下挤成一条缝，
	#   而入口行是首页最该被读到的东西，**宁可它不动也不动原有的三行**。
	#   ★★ 2026-10-04 v3：这段"修法"**没变**，变的只是行带在屏幕的哪一头
	#   （v2 顶部 → v3 底部）。⇒ 与 v0 那个病灶仍然只隔一步之遥：**谁把它们并进
	#   `groups` 谁就会再糊一次**。守卫 S50 + `--labeltest` 的 `_label_no_overlap_test`
	#   就是为这一步留的。
	# ★ 2026-10-09：**四行**（棋盘 / 大小 / 对战方式 / 开始）。
	#   · 「大小」三档（普通盘 = 随机·标准·加强；爱因斯坦下 = 帽子·海龟·幽灵）原先是**贴着
	#     选中棋盘向右折叠展开**的二级菜单，按用户口令「把大小这三个选项单列一行」独立成行；
	#   · 难度三档按同一句口令**取消折叠**、平铺进「对战方式」行（与 本地/人机 并列），
	#     且它们建项时直接归 `mode` 组 ⇒ 本行与其它普通行**没有任何区别**，专用排布函数
	#     `_layout_mode_row()` 整族删除（同一件事写两处 = 改一处漏一处）。
	var groups: Array[String] = ["board", "boardsize", "mode"]
	groups.append("action")
	# 行带起点：标题区(TOP_MARGIN)之下。
	# ⚠️ 这里**不再**给首行行标题预留固定像素（原先写死 +26，与 fs=24 的实高 34 不符，
	#    于是首行标题要么压到某个瓷砖标签上、要么被顶出标题区，反复出问题）。
	#    改为：行标题占位由 `_row_above_need()` 精算，瓷砖行中心再由 `_row_center_y()` 下移补偿，
	#    这样换字号档位/换行数都自动成立，不需要人来心算。
	var top0 := TOP_MARGIN + ROW_HEAD_TOP
	# ★★★ 2026-10-04 v3：`bottom0` 由**底部行带上沿**给出（不再直接贴屏底）——
	#   入口行从顶部翻到底部后，屏底那 86px 归底部行带，内容三行必须在它之上收口。
	#   ★ 这就是 S50 那条守卫守的**唯一真源**：底部行带的位置只有 `_footer_band()` 一处定义，
	#     内容行读它、谁都不许再写一个"大概多高"的常数。
	#   ⚠️ 实测代价：1152×648 下 `bottom0` 622→530 ⇒ bandH 161→131 ⇒ 内容块 R 57.1→38.2。
	#     这是"底部要放一行"的必然代价，口径与算账见 `FOOT_BAND_H` 的注释。
	var bottom0 := _footer_band().position.y - FOOT_GAP
	# 行带高度：各行等分（观感整齐），行与行之间再各扣掉一份**显式行距**。
	# ★★ 2026-10-16：`ROW_ROW_GAP` 由「「开始」行的下让保险」升级为**行距真源**
	#   （用户口令「间距稍微拉大一点」）。原先行带首尾相接、间距全靠 `_tile_base_r()`
	#   的纵向余量间接给出 ⇒ 那个量拧不动，行距根本拉不开。见该常量的注。
	# 每行内部的纵向预算由 `_row_above_need()` + 两个半菱形共同约束，见 `_tile_base_r`。
	var bandH := (bottom0 - top0 - ROW_ROW_GAP * float(groups.size() - 1)) \
		/ float(groups.size())
	# ★ 竖屏：**不能**等分整个高度（2026-09-23）。等分在横屏成立是因为高度本来就紧
	#   （⚠️ 这句原先举的例子是"1152×720 时 bandH≈185" —— 那是 **3 行时代**的数，
	#    2026-10-09「大小」独立成行后行数变 4，`bandH = (720−256)/4 = 116`。
	#    结论（"横屏高度紧、竖屏高度富余"）不变，但**别再引用那个 185**）；
	#   竖屏高度富余 → bandH≈465，但瓷砖半径被**宽度**卡死在 `size.x*0.60/7.8`≈55
	#   → 每行分到 465px 只放 55px 的块，行间空出几百像素（截图里"内容挤在上半屏、
	#   下方一片空"就是这个，不是绘制错）。
	#   改法：先把行带高度收敛到「瓷砖刚好被宽度顶满」的那一档（`_portrait_band_cap()`），
	#   剩下的高度按「份」均匀分掉 —— 顶部 1 份 + 行间 (n-1) 份 + 底部 1 份，
	#   于是内容在竖屏上自然铺开而不是堆在顶上。
	var bandGap := ROW_ROW_GAP
	if GameConfig.use_portrait_canvas():
		var cap := _portrait_band_cap()
		if cap < bandH:
			# ★ 2026-10-16：竖屏的"剩余高度"要把**行距**也先扣掉（横屏已经在 bandH 里扣过）
			var leftover: float = (bottom0 - top0) - cap * float(groups.size()) \
				- ROW_ROW_GAP * float(groups.size() - 1)
			var u: float = leftover / float(groups.size() + 1)
			top0 += u
			bandGap = ROW_ROW_GAP + u
			bandH = cap
	# ⚠️ 这两个**必须存成员变量**：`_row_fit_test()` 原来按「等分整个高度」自己重算一遍 bandH，
	# 只用于报告口径；加了竖屏收敛之后两者不再相等 —— 报告里那条 `bandH(该场景)=` 会显示一个
	# 屏幕上并不存在的高度，进而把人带到错误的结论上（该函数的历史注释里已为此返工过一轮）。
	# 改为「布局写、测试读」：`_band_h` 就是这一轮真正用的行带高。
	_band_h = bandH
	_band_gap = bandGap
	# ★★ 2026-10-16：**全页统一瓷砖尺寸**（唯一真源）—— 四行内容 + 底部入口行全部读它。
	#   ⚠️ 行花名册**不按 `_items` 现数**（那会随页变）—— 见 `_main_row_roster()` 那段
	#   "为什么"，以及它守的 `--menutest` ⑥d（底栏四页同位置）。
	var roster: Dictionary = _main_row_roster()
	var uni_cnts: Array = roster["cnts"]
	var uni_labels: Array = roster["labels"]
	var ubox: Dictionary = _tile_uniform_box(bandH, uni_cnts, uni_labels)
	_uni_box = ubox
	if "--layoutdbg" in _argv():
		print("[layoutdbg] size=%s groups=%d top0=%.0f bottom0=%.0f bandH=%.0f gap=%.0f base_r=%.1f" % [
			str(size), groups.size(), top0, bottom0, bandH, bandGap, _tile_base_r(bandH)])
		print("[layoutdbg]   [uni] r=%.1f hw=%.1f hh=%.1f fs=%d gap=%.1f 行块数=%s avail=%.0f" % [
			float(ubox["r"]), float(ubox["hw"]), float(ubox["hh"]), int(ubox["fs"]),
			float(ubox["gap"]), str(uni_cnts), size.x - 2.0 * ROW_EDGE_MARGIN])
		for gg in groups.size():
			print("[layoutdbg]   组%d=%s 行带 y=%.0f..%.0f 标题y=%.0f" % [
				gg, groups[gg], top0 + (bandH + bandGap) * float(gg),
				top0 + (bandH + bandGap) * float(gg) + bandH,
				top0 + (bandH + bandGap) * float(gg) + 6.0])
	# ⚠️ `_layout_setup()` 可被重复调用（改窗口尺寸、切页、自检里主动重跑），
	# 而 `_section_labels` 原先只在 `_set_page()` 里清空 → 重复调用会**累积重复项**，
	# 于是绘制端读到的是旧一次布局的 y（字号也可能对不上），表现为"标题位置与自检读数不符"。
	# 布局函数必须自己保证幂等：先清空再填充。
	_row_label_y.clear()
	_section_labels.clear()
	for gi in groups.size():
		var g: String = groups[gi]
		var bandTop := top0 + (bandH + bandGap) * float(gi)
		var row_items: Array[Dictionary] = []
		for it in _items:
			if it["group"] != g:
				continue
			# ★★ 2026-10-16：棋盘行的**禁用占位**（「敬请期待①②」）仍不布局 —— 这一条不变；
			#   变的是"启用项不再轮播"：原先只有"离焦点最近的 N 块"上屏（`_board_slots` 槽位），
			#   现在**全部**启用项平铺进本行。
			#   ⚠️ 只对 `board` 组生效：别的组的禁用项（如线上模式下的「开始」）仍要布局、置灰绘制。
			if g == "board" and bool(it["disabled"]):
				continue
			row_items.append(it)
		var cnt := row_items.size()
		if cnt == 0:
			continue
		var label_txt: String = {"board": "棋盘", "boardsize": _size_row_title(),
			"mode": "对战方式", "action": ""}.get(g, "")
		# 行标题落位：贴行带顶（留 6px 呼吸位）画。半径公式里
		# `ROW_HEAD_PAD` 就是"给行标题预留的纵向空间"，两者必须自洽：
		# 标题占的高度不能超过 ROW_HEAD_PAD，否则必然压到瓷砖标签。
		# `--labeltest` 的 [行带] 断言会直接量出净空，改这里务必重跑。
		var hfs: int = _row_head_font_size(bandH)
		var hh: float = _font_h(hfs)
		var row_label_y: float = bandTop + ROW_HEAD_TOP + hh * 0.5   # _draw_label 以文字中心落位
		_row_label_y[g] = row_label_y
		if label_txt != "":
			# 行标题一律记录，「让位」改为绘制期按折叠进度淡出 —— 原先只在布局期判断，
			# 折叠动画开始后标题会残留在原地，与展开出的折叠瓣/锚点标签重叠。
			# 字号随行高自适应，矮行用小字号，避免标题压到瓷砖标签（见 _row_head_font_size）。
			_section_labels.append({"text": label_txt, "y": row_label_y, "group": g, "fs": hfs})
		# ★★ 2026-10-16：**本行不再有任何专用分支** —— 原先顺序是
		#   ① `if g == "board": _layout_board_row(...)`（循环轮播，整族已删）；
		#   ② 再按 `action` / 其它分两档半径（「开始」走 `by_h_act` 放大一档）。
		#   用户口令「棋盘、大小、对战方式、开始按钮都统一成现在棋盘行按钮的大小」
		#   ⇒ 四行共用 `ubox` **一份**尺寸，块大小与块间距都不再随行变化。
		#
		# ⚠️ 块心仍按 `_row_center_y()` 走（有行标题的行整体下移半个标题段，「开始」行没有
		#   行标题 ⇒ 仍居中于行带）—— 变的只是**块的大小**，不是它落在哪；纵向预算
		#   （`_row_above_need` / `by_b`）一个字都没改，所以 [行带] 净空判据照旧成立。
		var has_head: bool = label_txt != ""
		var cy := _row_center_y(bandTop, bandH, has_head)
		# 变量名避开上面行标题那一个 `hh`（那是 `_font_h()` 的字高），别覆盖它
		var tile_hw := float(ubox["hw"])
		var tile_hh := float(ubox["hh"])
		var gap := float(ubox["gap"])
		var totalW := float(cnt) * 2.0 * tile_hw + float(cnt - 1) * gap
		var startX := size.x / 2.0 - totalW / 2.0 + tile_hw
		for k in cnt:
			var cx := startX + float(k) * (2.0 * tile_hw + gap)
			var c := Vector2(cx, cy)
			row_items[k]["center"] = c
			row_items[k]["poly"] = _tile_poly(c, tile_hw, tile_hh)
	# ★★★ 2026-10-04 v3：nav / quick 在**底部行带**里排成一行（`_footer_band()`）。
	#   它们仍不进前 3 组的等分（v0 那样做过：bandH 185→115、循环行标签全糊，实测 50 对重叠）。
	#   与内容行的关系仍是**结构性不相交**，但方向反了：
	#     · v2（顶部）：行带下沿追着内容墨迹走 ⇒ 不重叠；
	#     · v3（底部）：行带位置由屏底定死，**内容行的 `bottom0` 读行带上沿** ⇒ 不重叠。
	#   ⚠ 顺序：仍必须排在三个内容行**之后**。v2 是为了读内容墨迹；v3 不是为了读墨迹
	#     （`_footer_band()` 与内容无关），而是因为**这里是"本轮布局的收尾"** ——
	#     摆位要写在内容行算完之后，将来若谁把它提前，`_nav_band_top/_nav_band_h`
	#     就会先被填成一份、再被后面的逻辑覆盖（`--layoutdbg` 会打印出对不上的读数）。
	_layout_footer_row()
	# ★ 2026-10-02：「棋盘预览卡」删除 ⇒ 这里原先那句 `_preview_update()`（连同它
	#   "必须排在 nav 之后"的顺序约束）整条消失。留一句说明是给**下一个改这段的人**看的：
	#   上面 `_layout_footer_row()` 必须排在三个内容行**之后**那条约束与卡片无关，别跟着放宽。
	# ★ 背景密铺的生成盒跟着视口走 ⇒ 改窗口大小必须重算（缓存键含视口尺寸）。
	#   放在这里而不是 `_draw()`：绘制不该有副作用（`_draw` 可能被引擎在任何时刻调用）。
	_bg_ensure()

	if "--layoutdbg" in _argv() and _page == PAGE_MAIN:
		_dbg_geometry_dump()

## 布局几何 dump（`--layoutdbg` 时随每次布局打印一次）。
## ★ 为什么要有它：本页所有的"重叠"问题都在**多档视口**下才现形，而 headless 视口恒
##   1152×1152（正方），实机基座是 1152×648（扁）。凭手算常数去判"哪里撞哪里"，
##   等于用一个错的东西去判另一个东西（本文件在 `_portrait_band_cap` 的注释里已记过这笔账）。
##   ⇒ 一律打印**实测**的墨迹包围盒（块 + 标签），谁跟谁相交一眼可见。
func _dbg_geometry_dump() -> void:
	var f: Font = UITheme.body_font()
	print("[navdbg] ==== size=%s ====" % str(size))
	# ★ 2026-10-09：本 dump 的组清单**只写一份** —— 下面"块包围盒"与"标签墨迹"两段
	#   原先各写了一份**逐字相同**的白名单，改一处漏一处就会让两段的样本集悄悄不一致
	#   （dump 是给人读的，两段口径不同源时最难发现）。
	#   ⚠️ `"diff"` / `"netmode"` 两个组名已去（难度三档并入 `mode`、netmode 两瓣整族
	#   删除）—— 留一个永不命中的组名在清单里，读 dump 的人会以为那一行还在。
	var dump_groups: Array[String] = ["board", "boardsize", "mode", "action", "nav"]
	var by_g: Dictionary = {}
	for it in _items:
		var poly: PackedVector2Array = it["poly"]
		if poly.size() < 3:
			continue
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			bb = bb.expand(p)
		if str(it["group"]) not in dump_groups:
			continue
		var g: String = str(it["group"])
		if not by_g.has(g):
			by_g[g] = bb
		else:
			by_g[g] = (by_g[g] as Rect2).merge(bb)
	var lfs: int = TILE_LABEL_FS
	var keys: Array = by_g.keys()
	keys.sort()
	for g2 in keys:
		var r2: Rect2 = by_g[g2]
		print("[navdbg]   %-10s 块 x=%.0f..%.0f y=%.0f..%.0f" % [g2, r2.position.x, r2.end.x,
			r2.position.y, r2.end.y])
	# 标签墨迹（用绘制同款算法；各组的散开中心与半径按已有成员取）
	for it2 in _items:
		if (it2["poly"] as PackedVector2Array).size() < 3:
			continue
		var g3: String = str(it2["group"])
		if g3 not in dump_groups:
			continue
		var lp: Vector2 = _label_pos_for(it2, it2["center"], lfs)
		var tw: float = f.get_string_size(str(it2["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		print("[navdbg]   lbl %-8s %-8s cx=%.0f cy=%.0f 宽=%.0f 右沿=%.0f" % [g3,
			str(it2["label"]), lp.x, lp.y, tw, lp.x + tw * 0.5])
	var nbr: Rect2 = _nav_zone_rect()
	print("[navdbg]   底部入口带 x=%.0f..%.0f y=%.0f..%.0f R=%.1f rows=%d fs=%d per_row_pitch=%.1f"
		% [nbr.position.x, nbr.end.x, nbr.position.y, nbr.end.y, _nav_row_r, _nav_rows,
		_nav_label_fs, _nav_row_pitch])
	# ★★ 2026-10-16：棋盘行改**静态平铺** ⇒ 原先那行
	#   「盘行 pos=… k0=… focus_x=… pitch=… R=… 槽=… 右沿=…」整条退役：
	#   相位 / 焦点 / pitch / 槽数随轮播一族删除，继续打就是**四个恒为 0 的幽灵读数**
	#   （dump 里出现"pos=0.000 focus_x=0.0 槽=0"，读起来像"布局少做了一步"—— 比不打印更坏）。
	#   改成打印**真几何**：块数 + 左右端 + 块宽 / 间距（与 `--shotitems` 同一口径，
	#   量的是 `_items` 里那份真正用于绘制的 poly）。
	var bb_l := 1e9
	var bb_r := -1e9
	var n_bp := 0
	for it_bp in _items:
		if str(it_bp["group"]) != "board":
			continue
		var pl_bp: PackedVector2Array = it_bp["poly"]
		if pl_bp.size() < 3:
			continue
		n_bp += 1
		for p_bp in pl_bp:
			bb_l = minf(bb_l, p_bp.x)
			bb_r = maxf(bb_r, p_bp.x)
	print("[navdbg]   盘行 静态平铺 %d 块 x=%.0f..%.0f 块宽=%.0f 间距=%.0f（视口宽 %.0f）" % [
		n_bp, bb_l, bb_r, 2.0 * float(_uni_box.get("hw", 0.0)),
		float(_uni_box.get("gap", 0.0)), size.x])
	# 2026-10-04 v4：这里原有"右上棋盘按钮（返回）"的坐标打印 —— 齿轮先删，那块按钮随后
	# 也**整族删除**（设置成了主菜单的一个面板，回去走底栏「练习」）⇒ 这一行没有对象了。
	# ⚠️ 别再打印一个不存在的控件：dump 里出现幽灵坐标，读起来像"布局少做了一步"。
	# ★ 2026-10-08：这里原有"联机面板 x=…"的坐标打印 —— 浮层整族删除，没有对象了。
	#   ⚠️ 别再打印不存在的控件：dump 里出现幽灵坐标，读起来像"布局少做了一步"。

## ====== 底部一行入口（nav 三入口 + quick「练习」开关，2026-10-04 v3）======
##
## 位置：屏幕**下沿**那一条左右通带，四块排成**一行**（练习 / 棋谱 / 对弈 / 设置）。
##
## ★★★ 三代口径都写在这里，别再走一遍：
##   v0 把 nav/quick append 进 `groups` 参与高度等分 ⇒ 3 组变 5 组 ⇒ bandH 185→115
##      ⇒ 循环行相邻块间距不够放标签 ⇒ 五个标签糊成一片（实测 50 对重叠）。
##   v1 放进"右侧空白列"（左界写 `size.x*0.54`，撞上大小簇就让到 `need_sb`）——
##      扁视口下大小簇横向**更宽**（R 更大），让开后剩不下四块的位置，于是"就不让了"
##      ⇒ 1280×800 下入口块与大小簇相交 46×31 / 106×31 px（`--menutest` ⑤c 当场报红）。
##   v2 **头部**两簇：行带下沿由内容墨迹实测推（`_content_ink_top()` 已随本版删除），
##      内容行排在它之下 ⇒ 两者**结构性不相交**。代价是入口块比棋盘行块小
##      （实测 R 43.6 vs 57）—— 那是「绝不重叠」的价钱。
##   v3（本版）用户口令「把现在棋盘顶部的五个按钮挪到底部一行；删除开始对局按钮，把快速设置
##      改名叫练习，棋谱库改名叫棋谱，联机大厅改名叫对弈」⇒ 整条行带从**上沿翻到下沿**。
##      v2 的"不重叠"是靠**让位**拿到的（行带下沿追着内容墨迹走）；v3 反过来了：行带位置由
##      屏底**定死**（`FOOT_BAND_H`），**内容行必须让出**这段高度（`_layout_setup()` 的
##      `bottom0` 直接读 `_footer_band().position.y`）。
##      ★ 同一个"结构性不相交"，两版的方向相反，但**真源仍然只有一个**（谁自变量谁因变量
##        换了个方向而已）—— 这正是守卫 S50 守的那件事，所以 S50 跟着改口径而不是删掉。
##      ⚠️ 代价必须说清楚（实测）：内容行带 161 → **131**，内容块 R 从 **57.1 掉到 38.2**
##        （−33%）。这是"底部要放一行"的**必然代价**，不是没调好：
##        屏高 648、`BOTTOM_MARGIN` 20 ⇒ 可用 628；内容墨迹最低只到 582 ⇒ 底部只剩 **46px**，
##        而一行"标签在砖上 + 砖本体 2·半高比·R"最少要 85px ⇒ 缺口约 40px **只能从内容里出**。
##        ❌ 已被否掉的"不缩内容"方案：把底部行压到 `NAV_MIN_R`(22) 附近 ⇒ 底部行只剩 ~73px，
##           上沿 555 仍然**切进**「开始」砖（砖底 582）⇒ 直接重叠。
##        ✅ 反过来把内容割得更多、底部行做得更大也是一种设计（R≈40 时两边等大），
##           本版选的是"底部行 ≈ 内容块"（R 38.2 vs 38.2）—— 观感上是一整行同级入口。
## ★★ 2026-10-16：**86 → 68**（用户口令「底下一行高度也与上面统一」）。
##   原 86 是"底栏自己一套尺寸"的产物：`_nav_fit_solve()` 按 `zone.size.y / (2·menu_btn_h_ratio)`
##   反解 R ⇒ R = 58.9、块全高 86，恰好把整条行带塞满 —— 而**内容行块只有 56 高**
##   （R = 38.5）。用户看到的正是"底部那行比上面大一倍"。
##   现在底栏块改读**与内容行同一份**统一尺寸（`_tile_uniform_box()`）⇒
##   行带只需「块全高 + 上下各 `FOOT_ROW_PAD` 呼吸位」= 2·28 + 12 = 68。
##
## ⚠️⚠️ 这个值现在**只是 `_footer_band_h()` 的迭代初值**，不再是最终行带高 —— 原因见那个函数：
##   67/68 只是**设计基准视口**（视口高 648~720）下"块全高 + 12"的取值，而块高与行带高
##   互为因果（行带高 → bandH → r_base → 块高 → 行带高），写死它在大视口下会崩：
##   实测 headless 1152×1152（bandH 218 ⇒ 块高 123）四块底栏砖被挤成 4 行、溢出 368px。
##   ⚠️ 别把这个常量当成"行带高"去读 —— 要读就调 `_footer_band_h()`。
const FOOT_BAND_H: float = 68.0        # 底部行带高的**迭代初值**（真值由 `_footer_band_h()` 解出）
## 底部行带的呼吸位：底栏块全高之外、上下各留这么多（`_footer_band_h()` 用它把块高换算成行带高）。
const FOOT_ROW_PAD: float = 6.0
## 主菜单内容行数（棋盘 / 大小 / 对战方式 / 开始）—— **唯一真源**。
## `_content_band_h()` 的纵向预算、`_row_count_test()` 的期望值都读它；
## ⚠️ 它必须恒等于 `_layout_setup()` 里 `groups` 的条数（那边由 `groups.size()` 现取，
##    `_row_count_test()` 就是在钉这两者一致 —— 行数一变，两边的纵向预算会**静默分叉**）。
const MAIN_ROW_COUNT: int = 4
const FOOT_GAP: float = 12.0           # 底部行带与「内容墨迹 / 空态提示」之间的净空
## 相邻入口块中心距 / R（= 本体 2R + 0.2R 缝，与棋盘行 `TILE_GAP_RATIO` 同源）
const NAV_PITCH_RATIO: float = 2.2
## ★ 2026-10-09：这里原有 `NAV_LABEL_GAP`（入口块标签与块上顶点之间的净空）——
##   随"文字放进按钮内部"删除（标签不再挂在块上方 ⇒ 没有这段间距）。
##   新常量 `NAV_ROW_GAP` = 底栏**多行**时行与行之间的呼吸位（原先靠"标签行高"顶开，
##   那段没了以后必须显式留，否则多行会贴在一起）。
const NAV_ROW_GAP: float = 8.0
## 入口块半径下限：低于它就宁可**降字号**，也不要画出一堆看不清的碎块
## 空态提示字号（棋谱 / 对弈页的那一行说明文字）
const EMPTY_HINT_FS: int = 22
## 本轮 nav 每行摆几块（1 行时 = 块数；矮/窄时自动变小 ⇒ 换行）
var _nav_per_row: int = 4
## ★★ 2026-10-04 v4：这里原有 `const BACK_TILE_TOP_PAD = 18.0`（设置页右上角那块「返回」
##   棋盘按钮的标签墨迹上沿）。用户口令「设置选项挪过来之后删掉设置页的返回按钮」⇒
##   那块按钮整族删除，常量随之消失。**别回收名字**：留着只会让下一个人去找一个不存在的东西。

## 内容行带高（给定底部行带高 `foot` 时）。**纯函数**，供 `_footer_band_h()` 迭代用。
## ⚠️ 与 `_layout_setup()` 的算式**逐项相同**（除竖屏收敛那一步，见那里的注）——
##   两处一旦分叉，`_footer_band_h()` 就会按一个"屏幕上并不存在的 bandH"去解块高。
func _content_band_h(foot: float) -> float:
	var top0: float = TOP_MARGIN + ROW_HEAD_TOP
	var bottom0: float = size.y - BOTTOM_MARGIN - foot - FOOT_GAP
	return (bottom0 - top0 - ROW_ROW_GAP * float(MAIN_ROW_COUNT - 1)) / float(MAIN_ROW_COUNT)

## 底部行带高 = **统一块全高 + 上下各 `FOOT_ROW_PAD`**（2026-10-16 用户口令「底下一行高度
## 也与上面统一」）。
##
## ★★ 为什么必须**迭代**而不是写死一个数：底栏块高与内容行带高**互为因果** ——
##   行带高 → `bandH` → `_tile_base_r()` → 块半高 → 行带高。
##   写死一个常数（本版初版取 68.0）只在**设计基准视口**（视口高 648~720）下碰巧吻合，
##   实测 headless 1152×1152 下内容块高 123 而行带仍 68 ⇒ 四块底栏砖被挤成 **4 行**、
##   溢出到「开始」行上面（`--labeltest` `[行间] nav底=1356 → action顶=930 间隙=−427 ✗`，
##   6 条判据当场报红）。1920×1080 同样崩（内容块高 150 vs 行带 68）—— **不是 headless 专有**。
##
## ★ 迭代是**收缩**的：`foot` 变大 → `bottom0` 变小 → `bandH` 变小 → `r_base` 变小
##   → `hh` 变小 → `foot` 变小。实测 2 次就到 0.25px 以内，6 次是余量。
##   并且它是**纯函数**（只依赖 `size` 与常量）⇒ 幂等，不会引入"上一帧残留"那种状态
##   （那正是 `--portraittest` ⑥ 阴性对照要防的东西）。
##   ⚠️ 手法与 `_portrait_band_cap()` 同源：手推公式会与真源分叉，**直接问它自己**最稳。
func _footer_band_h() -> float:
	var foot: float = FOOT_BAND_H
	for _it in 6:
		var hh: float = _tile_hh_for(_tile_base_r(_content_band_h(foot)))
		var next: float = 2.0 * hh + 2.0 * FOOT_ROW_PAD
		var done: bool = absf(next - foot) <= 0.25
		foot = next
		if done:
			break
	# 下限：至少容得下一行块 + 呼吸位（块小时别把行带压成一条缝）；
	# 上限：不超过屏高的 40%（极端扁视口兜底，否则内容行会被挤没）。
	return clampf(foot, 2.0 * FOOT_ROW_PAD + 16.0, size.y * 0.4)

## 底部行带（左右通带，`x` 从 0 到屏宽）。**上沿 = 屏底 − `BOTTOM_MARGIN` − 行带高**。
##
## ★★ 为什么高度不是像 v2 那样"由内容墨迹推"：
##   底部行带是**自变量**（内容让位给它），内容墨迹是**因变量** —— 反过来写的话
##   `_layout_setup()` 要先知道内容在哪才能定行带，而内容又在等行带让出空间，
##   就成了一个**顺序环**（v2 没这个问题：那时头部行带是最后排的，谁也不等它）。
##   ⚠️ 2026-10-16：行带高的**取值**现在是 `_footer_band_h()` 的迭代解（块全高 + 呼吸位），
##     但它仍然是"自变量" —— 循环被那个纯函数的迭代打破了，`_layout_setup()` 的次序没变。
## ★★ 为什么底部基准用 `BOTTOM_MARGIN` 而不是另写一个常数：屏底留白全局只有这一个真源。
func _footer_band() -> Rect2:
	var foot: float = _footer_band_h()
	var bottom: float = size.y - BOTTOM_MARGIN
	return Rect2(0.0, bottom - foot, size.x, foot)


## 底部入口行的可用区域：**整条行带**内缩左右边距。
## ★★ v3 不再有"左簇 / 右簇"—— `quick` 与 `nav` 挤进**同一行**，所以只有一个区域。
##   ⚠️ 本版把原来两个函数（`_nav_band_rect` 右簇 / `_quick_band_rect` 左簇）**合并成一个**：
##     它们原先的分界读的是标题墨迹（标题左边一块、右边四块），而底部行不经过标题
##     ⇒ 分界不存在了。留着"左簇区域"只会让下一个改这里的人以为还能分两簇摆。
## ★★ 区域变宽的直接后果：v2 里右簇只有 400px 宽 ⇒ R 被**宽度**卡在 46.5（不是高度）；
##   v3 有 1096px 宽 ⇒ 宽度不再是瓶颈，R 改由**行带高度**决定（实测 38.2）。
## ⚠️ 这就是"挪个位置"的**连带后果**：同一段求解代码，瓶颈从宽度换成高度 ⇒
##   改这里必须重跑 `--menutest` ⑤a/⑤c/⑤e/⑧ 与 `--labeltest`。
func _nav_zone_rect() -> Rect2:
	var fb: Rect2 = _footer_band()
	var left: float = ROW_EDGE_MARGIN
	var right: float = size.x - ROW_EDGE_MARGIN
	# 2px 余量：几何"恰好等于"时浮点比较会让末块压线（末块右沿 = 区域右沿）
	return Rect2(left, fb.position.y, maxf(40.0, right - left - 2.0), fb.size.y)

## 「n 块怎么摆」的纯几何求解，返回 {ok, r, per_row, pitch}。
##
## ★★ 为什么把**行数也交给求解**而不是写死：窄而高的区域里 2×2 能比 1×4 放出更大的块，
##   而"哪种更大"取决于区域宽高比 ⇒ 写死行数只在一个比例下最优（铁律 4）。
## ★★ 为什么用**穷举候选**而不是解析式：横向同时受「标签不叠」与「块宽」两个约束，
##   哪个占优取决于字号；让求解器自己试，比人在注释里推一遍稳（本项目在
##   `_portrait_band_cap` 上已经因为"手推一遍"吃过账）。
## 参数：`tws` = 每块的标签宽度（同一字号下算），`zone` = 可用矩形，`fs` = 字号（决定标签行高）。
func _nav_fit_solve(tws: Array[float], zone: Rect2, fs: int) -> Dictionary:
	var n: int = tws.size()
	var none := {"ok": false, "r": 0.0, "per_row": maxi(n, 1), "pitch": 0.0}
	if n <= 0 or zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return none
	# 相邻两块不叠所需的最小中心距：两块各占一半字宽
	# ★ 2026-10-09：文字进按钮 ⇒ 这里的"字宽"仍是**标签宽度**（块内文字也要装得下），
	#   但它不再需要额外的标签行高（`_nav_place()` 那边同理，见那里的注）。
	var min_pitch: float = 0.0
	for i in range(n - 1):
		min_pitch = maxf(min_pitch, (tws[i] + tws[i + 1]) * 0.5)
	var best_r: float = -1.0
	var best_k: int = n
	for k in range(n, 0, -1):
		var rows: int = int(ceil(float(n) / float(k)))
		# 横向：2R + pitch·(k−1) ≤ W，而 pitch = max(min_pitch, NAV_PITCH_RATIO·R)
		#   ⇒ R ≤ min( (W − min_pitch·(k−1))/2 , W/(2 + NAV_PITCH_RATIO·(k−1)) )
		#     前者 = 「标签占优」分支，后者 = 「块宽占优」分支。取两者之小一定安全：
		#     若 NAV_PITCH_RATIO·R ≥ min_pitch 则 pitch 走后者 ⇒ 总宽 ≤ W；
		#     否则 pitch = min_pitch ⇒ 总宽 ≤ 2·a + min_pitch·(k−1) = W。两分支都成立。
		var by_w_a: float = (zone.size.x - min_pitch * float(k - 1)) * 0.5
		var by_w_b: float = zone.size.x / (2.0 + NAV_PITCH_RATIO * float(k - 1))
		# 纵向：rows 行，每行占「块全高 2·半高比·R + 标签行高 + 净空」
		# ★ 2026-10-09：文字改画在按钮**内部** ⇒ 这里不再减「标签行高 + 间隙」
		#   （底栏四块的字原先挂在块上方，行高要替它留一段；现在那一段归按钮自己了）
		#   ⇒ 同样的行带能放下更大的块（与内容行 `_row_above_need()` 那一笔同源）。
		var by_h: float = (zone.size.y / float(rows)) / (2.0 * menu_btn_h_ratio)
		var r: float = minf(minf(by_w_a, by_w_b), by_h)
		if r > best_r:
			best_r = r
			best_k = k
	if best_r <= 0.0:
		return none
	return {"ok": true, "r": best_r, "per_row": best_k,
		"pitch": maxf(min_pitch, NAV_PITCH_RATIO * best_r)}

## 一簇块的标签宽度（按给定字号）。求解与摆放都读它，避免两处各算一次。
func _nav_label_widths(items: Array[Dictionary], fs: int) -> Array[float]:
	var f: Font = UITheme.body_font()
	var out: Array[float] = []
	for it in items:
		out.append(f.get_string_size(str(it["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return out

## 把一簇块按求解结果摆进 `zone`：每行各自按 `align` 靠边/居中，整簇**贴行带上沿**。
## ★ 抽成一个函数（v2 时是"左右两簇的摆法必须逐字相同"；v3 只剩一簇，但它仍是
##   "求解→摆位"的唯一实现，别在别处再写一次 `_make_btn_rect` 的循环）。
##
## `align`（`"left"` / `"center"` / `"right"`）由**簇的块数**决定，不是由上下位置决定：
##   · 多块（换行后要对称）→ `"center"`；
##   · **单块** → 贴右侧（`"right"`）。
## ★★ 为什么单块要贴右边（2026-10-02 截图目检，v3 仍成立）：棋谱 / 对弈页只有一块「返回」，
##   若按区域居中，它落在屏幕左右中间的**中点** —— 那个位置不指向任何东西，
##   看起来像"随机摆的一块"（截图里正是这个观感）。贴右侧则与设置页**右上角**那块「返回」
##   同侧（都是"靠右"），一眼能看出"这是本页的返回"。
##   ⚠️ v2 时它还写着"与首页**左上角**的「快速设置」形成左右呼应" —— v3 入口整行翻到底部，
##   那句不再成立（首页左上是空的），但**结论不变**（贴右），换成本条理由。
##
## ★★★ 为什么整簇**贴行带上沿**而不是"在区域里纵向居中"：这样标签墨迹顶 == 行带上沿，
##   是一个**可判的量**（⑤e 的 ① 直接量它）。
##   （当年还有第二个读者 `_back_tile_center()`，2026-10-04 v4 随返回按钮整族删除。）
##   v2 的历史理由是"新页没有内容墨迹 ⇒ 区域高得多 ⇒ 居中会把同一套组件摆到屏幕中部
##   （实测首页 y≈89、棋谱库页 y≈178）"；v3 的行带是**常数高度**，不存在这个问题了，
##   但"贴顶 == 可判的量"这条理由独立成立 ⇒ 保持贴顶。
func _nav_place(items: Array[Dictionary], zone: Rect2, fs: int,
		r: float, per_row: int, pitch: float, align: String = "center",
		hw_in: float = -1.0) -> void:
	var n: int = items.size()
	if n <= 0 or r <= 0.0 or per_row <= 0:
		return
	# ★ 2026-10-09：文字改画在按钮**内部** ⇒ 不再给"挂在块上方的字"留 `label_h + NAV_LABEL_GAP`
	#   ⇒ vstep 只剩块自身全高（+ 行间呼吸），y0 也只需让出块的上半高。
	# ★ 2026-10-15：横向半宽走 `_tile_hw_row()`（与内容行**同一支**口径）。
	# ★★ 2026-10-16：半宽改为**由调用方传入**（`_uni_box["hw"]`）。底栏块与四行内容块现在
	#   必须是**同一个尺寸**（用户口令「底下一行高度也与上面统一」），而 `_tile_hw_row()`
	#   只会给出"**本行**最宽"（底栏四个标签恒 2 字 ⇒ 结果 = r = 34.4）⇒ 站在这里自己算，
	#   必然比内容行（120 宽）窄一圈 —— 那正是本次要消灭的现象。
	#   `hw_in <= 0` 退回自算：兜底路径（`_uni_box` 未建立时），见 `_layout_footer_row()`。
	var labels_n: Array = []
	for it_n in items:
		labels_n.append(str(it_n["label"]))
	var hw_n: float = hw_in if hw_in > 0.0 else _tile_hw_row(r, labels_n, fs)
	var hh_n: float = _tile_hh_for(r)
	var vstep: float = 2.0 * hh_n + NAV_ROW_GAP
	# ★★ 2026-10-16：整簇**垂直居中**于行带（原先是**贴行带上沿**）。
	#   贴顶是 v2 时代留下的"可判的量"（⑤e 的 ① 直接量标签墨迹顶 == 行带上沿）；但那时
	#   底栏块恰好把行带塞满（86 == 块全高）⇒ 贴顶与居中是同一个位置，两种写法分不出来。
	#   现在块只有 ~50 高、行带 68 ⇒ 贴顶会在下边留 18px、上边 0，看起来像"底部一整行没对齐"。
	#   居中后判据量的是"上下留白相等"，同样是**可判的量**（`--menutest` ⑤e 已同步）。
	var rows_t: int = maxi(1, int(ceil(float(n) / float(per_row))))
	var cluster_h: float = 2.0 * hh_n * float(rows_t) + NAV_ROW_GAP * float(rows_t - 1)
	var y0: float = zone.position.y + (zone.size.y - cluster_h) * 0.5 + hh_n
	for idx in n:
		var row: int = idx / per_row
		var per: int = mini(per_row, n - row * per_row)     # 末行可能不满
		var row_w: float = 2.0 * hw_n + pitch * float(per - 1)
		var row_x0: float = zone.position.x + hw_n
		if align == "center":
			row_x0 = zone.position.x + (zone.size.x - row_w) * 0.5 + hw_n
		elif align == "right":
			row_x0 = zone.position.x + zone.size.x - row_w + hw_n
		var col: int = idx - row * per_row
		var c := Vector2(row_x0 + float(col) * pitch, y0 + float(row) * vstep)
		items[idx]["center"] = c
		items[idx]["poly"] = _tile_poly(c, hw_n, hh_n)

## 子页（棋谱 / 对弈）的**空态提示** —— 文字/字号/落位的唯一真源（绘制与判据都读它）。
##
## ★★ 为什么值得为两行字写一条真源：占位页**什么都不画**时，用户看到的是一片空白 ——
##   分不清"功能还没做"与"这里坏了"。一行居中说明就把"这是有意留的位"说清楚了。
## ★★ 更实际的理由：不写判据的话，将来有人改布局把这行挪到行带/返回块上，
##   **没有任何东西会红**（`--menutest` ①~⑦ 都不看它）。⇒ 位置必须是可读的量，
##   判据才能量"它有没有压住底部行带 / 入口块"。
## ★ 返回 `{}` = 这一页没有空态提示（主菜单 / 设置页）。**判据也要认这个口径**
##   （否则"哪一页该有"就成了第二处真相）。
func _empty_hint() -> Dictionary:
	var txt: String = ""
	match _page:
		PAGE_RECORDS:
			# ★ 只在**真的没有棋谱**时才提示空态（2026-10-09 用户报的 bug）：
			#   原先无条件返回这句，导致棋谱库里**明明有谱**也照样把"还没有棋谱"压在列表上。
			#   判据读真源：`_rec_idx`（`_rec_load()` 的索引快照，进页时已加载）非空 ⇒ 不空态。
			#   ★ 注意这是"有谱则不提示"，与"没谱才提示"是同一件事的两面：
			#     只要库里真的一条都没有，`_rec_idx` 就为空，这句照常显示 —— 不会误伤真空态。
			if _rec_idx.is_empty():
				txt = "还没有棋谱 · 对局结束后会自动存档"
	if txt == "":
		return {}
	var fs: int = EMPTY_HINT_FS
	var h: float = _font_h(fs)
	# ★ 2026-10-04 v3：纵向让位方向也翻转了 —— 原来是"躲开**上**方的头部行带"
	#   （上界 = 头带下沿 + 净空），现在是"躲开**下**方的底部行带"
	#   （下界 = 底带上沿 − 净空）。
	# ★★ 上界仍读真源（`_footer_band()`，不是 `size.y - 常数`），于是
	#   "底部行带改了、提示还压着它"这种错**结构性不可能**出现 —— 判据 ⑧ 独立咬这一条。
	# ⚠️ 上界这侧改用 `TOP_MARGIN + ROW_HEAD_TOP`（而非 v2 的"头带下沿"）：子页**没有内容行**
	#   （`_items` 里只有一块「返回」）⇒ 页身的上沿就是标题区之下那一线，没有更聪明的真源可读。
	var top: float = TOP_MARGIN + ROW_HEAD_TOP
	var bottom: float = _footer_band().position.y - FOOT_GAP
	var cy: float = (top + bottom) * 0.5
	var cx: float = size.x * 0.5
	var tw: float = UITheme.body_font().get_string_size(
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return {"text": txt, "fs": fs, "center": Vector2(cx, cy),
		"rect": Rect2(cx - tw * 0.5, cy - h * 0.5, tw, h)}

## 底栏那**四块入口**的注册表（**唯一真源**：四个面板都 `append_array` 它）。
##
## ★★ 为什么必须是一份、而不是每页各 append 四行：用户口令是「主菜单底栏四按钮**固定**在
##   主菜单不动，上面的空间用来切换面板」。四页各写一份时，"固定"只由**四份文本巧合一致**
##   保证 —— 改一页忘三页就变成"这个面板的底栏长得不一样"，而它在任何几何判据里都是**绿**的
##   （每个面板内部自洽、块数对、点得到自己）。⇒ 抽成唯一真源后"固定"由**构造**保证。
##
## ★ `sel = _nav_tile_selected(目标页)`：这四块同时是**面板指示器**（当前面板的凹陷态停在它上面）——
##   与"按一下换个面板"是同一件事的两面 ⇒ 两处都必须由**同一个 `_page`** 派生，
##   各写一个判据就会出现"凹陷态停 A、点开的是 B"（铁律 7：一组控件两种含义，回调与标签同源）。
##   ★★ 2026-10-16：原来这里写的是**内联**的 `sel: _page == PAGE_MAIN`（四行各写一遍），
##     而运行期那一份（`_refresh_selection()`）**压根没有 `"nav"` 臂** ⇒ 点一下棋盘就把
##     「练习」的凹陷态抹掉（用户报的 bug）。⇒ 抽成 `_nav_tile_selected(page_id)`：
##     **建项值与运行期值出自同一个谓词**，结构上不可能再分叉。
##   ★ `page_id` = **身份字段**（**不许按 label 字面认** —— 与 `size_id` / `mode_id` 同款；
##     "用内容当身份"这个坏法在本工程已复现三次，本条是它的第三个消费方）。
##
## ★ 顺序 = 「练习 / 棋谱 / 对弈 / 设置」：用户读得出来的句子（从最靠近开局排到最远离对局）。
##   屏幕上的顺序 = `_items` 顺序 = 这里的 append 顺序（见 `_footer_row_items()`）。
func _footer_entry_descriptors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# 「练习」= 本面板上面那几行设置区（棋盘 / 大小 / 种类 / 难度 / 对战方式 / 开始）。
	# ★ 2026-10-04 第四版起它**不再是一个开关**（`_toggle_quick_panel()` 已随折叠机制删除）：
	#   折叠机制的前提是"同一页里收起/展开同一块内容"，而现在是**换面板** ——
	#   两者在屏幕上的区别是"设置区淡出后同一页还剩什么"，语义不同，不能共用一条状态。
	out.append({"label": "练习", "group": "nav", "page_id": PAGE_MAIN,
		"sel": _nav_tile_selected(PAGE_MAIN),
		"cb": func() -> void: _set_page(PAGE_MAIN), "disabled": false})
	# ★ 2026-10-04：棋谱库→棋谱、联机大厅→对弈（`--menutest` ① 钉着这四个词）。
	# ⚠️ `netmode` 组的「联机大厅」瓣**不改** —— 那是"对战方式=线上"下的**二级选项**
	#   （邀请好友 / 联机大厅），说的是"去哪找对手"，与底栏这个面板入口不是一件事。
	#   改错会出现"两个「对弈」而其中一个其实是联机方式"的静默混淆。
	out.append({"label": "棋谱", "group": "nav", "page_id": PAGE_RECORDS,
		"sel": _nav_tile_selected(PAGE_RECORDS),
		"cb": func() -> void: _set_page(PAGE_RECORDS), "disabled": false})
	out.append({"label": "对弈", "group": "nav", "page_id": PAGE_LOBBY,
		"sel": _nav_tile_selected(PAGE_LOBBY),
		"cb": func() -> void: _set_page(PAGE_LOBBY), "disabled": false})
	# 「设置」：设置选项已挪进本面板（`_build_settings_ui()` 落在底栏之上）
	# ⇒ 设置页原来那颗「返回」按钮**没有存在意义**（原地按「练习」就回去了），已整族删除。
	out.append({"label": "设置", "group": "nav", "page_id": PAGE_SETTINGS,
		"sel": _nav_tile_selected(PAGE_SETTINGS),
		"cb": func() -> void: _set_page(PAGE_SETTINGS), "disabled": false})
	return out

## 底栏此刻**亮着**的那几块的 `_items` 下标（**唯一量法**：`--menutest` ⑤b 与 ⑤b2 共用）。
## ★ 抽出来的理由与 ⑤b 那条"期望值不另写一份映射表"同源：**"怎么算亮着"只能有一个定义** ——
##   两条判据各写一遍 `for ... if group == "nav" and selected` 的话，将来量法一变
##   （比如"还要看 alpha 不为 0"）就只会改一处，另一处静默留在旧口径上。
func _nav_lit_indices() -> Array[int]:
	var out: Array[int] = []
	for i in _items.size():
		if str(_items[i]["group"]) == "nav" and bool(_items[i]["selected"]):
			out.append(i)
	return out

## 底部那一行**有哪些块、按什么顺序**（**唯一真源**：布局与判据都读它）。
##
## ★★ 为什么抽出来而不是在 `_layout_footer_row()` 里就地收集：判据 ① 要问"底部这行是不是
##   这四块、顺序对不对"，若它自己再筛一遍（按 group 数、或按另一份 label 列表比），
##   就出现**第二个定义** —— 将来往这行加一块砖，布局会画出来而判据不知道（判据照样绿），
##   或者反过来把新砖从判据里漏掉。`--labeltest` 的摆位判据也读它。
##
## ★ 顺序 = 「练习 / 棋谱 / 对弈 / 设置」：**用户读得出来的句子**，从"最靠近开局"排到
##   "最远离对局"。⚠️ 不能按 group 名或 label 字典序排 —— 按名字/组名排都会把「练习」甩到
##   末尾。顺序的真源是 `_footer_entry_descriptors()` 的 append 顺序（这里只按 `_items` 顺序取）。
##
## ★★ 2026-10-04 第四版：「练习」原来归 `quick` 组（它是**开关**，与另外三块的"选中态 /
##   回调后会发生什么"都不一样 ⇒ 当时必须分开）。现在四块都是**面板入口** ⇒ 全部归 `nav`，
##   这一族"两类控件"的分叉整个消失（连带 `_draw_fs_for` / `_label_font_size_for` 里
##   给 `quick` 留的那两支也一并删掉 —— 留着就是"同一行两个字号真源"）。
func _footer_row_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in _items:
		if it["group"] == "nav":
			out.append(it)
	return out

## 底部入口行的**唯一入口**：裁字号 → 求解 → 摆位。`_layout_setup()` 末尾调一次。
##
## ★★ v3 与 v2 的两处结构差异（改这里之前先读）：
##   ① **一簇、不是两簇**：v2 把 `quick` 与 `nav` 分成左右两簇，各自求解再取 `min(R)`；
##      v3 它们是**同一行里的邻居** ⇒ 只有**一次**求解、**一个**字号、**一次**摆位。
##      ⚠️ 别为"两类控件"保留两套参数：同一个字号 / 同一个 R 就是它们的契约
##      （分两套的表现是"一行里字号不一"，而那**没有任何判据看得见**）。
##   ② 摆哪几块由 `_footer_row_items()` 决定（顺序的真源在那里）。
func _layout_footer_row() -> void:
	var row_items: Array[Dictionary] = _footer_row_items()
	if row_items.is_empty():
		_nav_band_top = -1.0
		_nav_band_h = 0.0
		return
	var zone: Rect2 = _nav_zone_rect()
	# ★★ 2026-10-16：底栏块**不再自己解一套尺寸**（用户口令「底下一行高度也与上面统一」）。
	#   改前：`_nav_fit_solve()` 按行带高反解 R = `zone.size.y / (2·menu_btn_h_ratio)` = 58.9
	#   ⇒ 块全高 86 **恰好把整条行带塞满**，而内容行块只有 56 高 —— 用户看到的
	#   "底部那行比上面大一倍"就是它。现在改读 `_uni_box`（与四行内容**同一份**统一尺寸）。
	#   ⚠️ 行数求解**保留**：块尺寸既然不可再议，"放不下"就只剩**换行**一条出路
	#   （窄视口下四块仍可能折成两行），`_nav_place()` 的多行能力照旧要用。
	#   ⚠️ `_nav_fit_solve()` 退成**兜底**（只在 `_uni_box` 未建立时用）—— 它仍是对的，
	#     别当死代码删：本函数也可能在 `_items` 为空/未布局时被调到。
	var fs_use: int = int(_uni_box.get("fs", _label_font_size_for("nav")))
	var r_use: float = float(_uni_box.get("r", 0.0))
	var hw_use: float = float(_uni_box.get("hw", 0.0))
	if r_use <= 0.0 or hw_use <= 0.0:
		var fit0: Dictionary = _nav_fit_solve(_nav_label_widths(row_items, fs_use), zone, fs_use)
		r_use = maxf(float(fit0["r"]), _tile_base_r(zone.size.y) * 0.5)
		hw_use = maxf(r_use, 0.0)
	if r_use <= 0.0:
		return
	var hh_use: float = _tile_hh_for(r_use)
	var gap_use: float = float(_uni_box.get("gap", hw_use * TILE_GAP_RATIO))
	var n: int = row_items.size()
	# 行数：块尺寸不可调 ⇒ 唯一出路是换行。取"能塞进 zone 的最大每行块数"（从多到少试）。
	var per_row: int = 1
	for k in range(n, 0, -1):
		var k_use: int = mini(k, n)
		var rows_k: int = int(ceil(float(n) / float(k_use)))
		var row_w_k: float = 2.0 * hw_use * float(k_use) + gap_use * float(maxi(k_use - 1, 0))
		var rows_h_k: float = 2.0 * hh_use * float(rows_k) + NAV_ROW_GAP * float(rows_k - 1)
		per_row = k_use
		if row_w_k <= zone.size.x + 0.01 and rows_h_k <= zone.size.y + 0.01:
			break
	per_row = maxi(per_row, 1)
	# 间距：先要**统一间距**；连它都放不下就把间距压到剩余全部
	# （下限 `0.05·块宽`，与内容行 `_tile_uniform_box()` 同一口径）。
	var per_use: int = mini(per_row, n)
	var pitch_use: float = 2.0 * hw_use + gap_use
	if per_use >= 2:
		var gap_fit: float = (zone.size.x - 2.0 * hw_use * float(per_use)) / float(per_use - 1)
		pitch_use = 2.0 * hw_use + maxf(hw_use * 0.05, minf(gap_use, gap_fit))
	_nav_row_r = r_use
	_nav_label_fs = fs_use
	_nav_per_row = per_use
	_nav_rows = maxi(1, int(ceil(float(n) / float(per_use))))
	_nav_row_pitch = pitch_use
	_nav_band_top = zone.position.y
	_nav_band_h = zone.size.y
	# ★ 单块贴边、多块居中 —— 判据由**块数**派生（`align` 的口径见 `_nav_place()`）。
	#   ⚠️ 这里若写成 `"right"` 常量，首页那四块会挤到屏幕最右侧（与"底部一行是一整簇"的观感不符）；
	#   写成 `"center"`，棋谱 / 对弈页那块孤零零的「返回」又回到"飘在中间"。
	#   两处都是**看得见**的错。
	_nav_place(row_items, zone, fs_use, r_use, per_use, pitch_use,
		"center" if n > 1 else "right", hw_use)

## 底部入口行（`_footer_row_items()`）的标签矩形两两重叠的对数（判据 ⑤a 用）。
## ★ 复用 `_draw_fs_for()` 与 `_pass_ink_rect()` —— 各算一次就会出现
##   "判据量 24、画 20"那种**静默**错配（判据绿、字照叠）。
## ★★★ 2026-10-04 v3 修了一个**判据盲区**：本函数原先只数 `group == "nav"` 的块，
##   而 v3 起「练习」在 `quick` 组、与「棋谱」是**紧挨着的邻居** —— 照旧写法，
##   这两块标签叠在一起时 ⑤a **照样全绿**（只数了 nav 内部的三对）。
##   病灶与铁律 13 同族：**判据的范围 ≠ 被测量物的范围**。
##   ⇒ 改成读 `_footer_row_items()`（布局用的同一份名单）——范围的真源只有一处，
##     将来往这行加第五块砖时，判据自动把它算进来。
func _nav_label_overlap_count() -> int:
	var f: Font = UITheme.body_font()
	var boxes: Array = []
	for it in _footer_row_items():
		if (it["poly"] as PackedVector2Array).size() < 3:
			continue
		var fs: int = _draw_fs_for(it)
		var tw: float = f.get_string_size(str(it["label"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var th: float = _font_h(fs)
		var lp: Vector2 = _ink_label_pos(it, it["center"], it["poly"], fs, true)
		boxes.append(Rect2(lp - Vector2(tw, th) * 0.5, Vector2(tw, th)))
	var bad: int = 0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var ov: Rect2 = (boxes[i] as Rect2).intersection(boxes[j] as Rect2)
			if ov.size.x > 0.0 and ov.size.y > 0.0 and ov.size.x * ov.size.y > 8.0:
				bad += 1
	return bad

# ★ 2026-10-09：这里原有 `_layout_mode_row()`（对战方式行的专用排布 + 难度三瓣折叠）——
#   难度三档取消折叠、平铺进本行（与 本地/人机 并列）之后，本行就是一条普通行，
#   由 `_layout_setup()` 的通用分支统一排布（居中 + 横向按块数收上限）。
#   ⚠️ 名字不许回收：不要再建一个 `_layout_mode_row` 去做别的事。



# ====== 棋盘行：**静态平铺**（2026-10-16 用户口令「棋盘选项不需要滚动了，删掉」）======
#   · 启用项**全部**平铺进本行（禁用占位「敬请期待①②」不建项、不占位）；
#   · 每块在屏幕上**只出现一次** —— 槽位 / 重影 / 相位 / 焦点位那一整套概念不存在；
#   · 块尺寸与块间距读**全页统一真源** `_uni_box`（见 `_tile_uniform_box` / `_main_row_roster`），
#     本行**没有**专属的横向收缩（原先那条「半径 × 焦点联合求解」随轮播一起退役）；
#   · 排布就在 `_layout_setup()` 的通用分支里 —— 与大小 / 对战方式 / 开始三行**同一段代码**。
#
# ★ 2026-10-09：这里原有 `_has_diff_row()`（判“有没有难度三瓣要折叠”）—— 折叠机制整族删除，
#   难度三档恒在「对战方式」行里平铺，`_has_diff_row()` 恒真 ⇒ 对空集合的判据 = 没测。
#   ⚠️ 名字不许回收。


## 一块「规整圆角矩形」按钮 —— **按钮形状的唯一真源**（2026-10-08 用户口令：
## 「抛弃现在的落子按钮，改用主题色相关的普通按钮」+ 形状拍板「规整圆角矩形」）。
##
## ★★ 包围盒与旧的宽菱形**逐像素相同**（半宽 R、半高 `menu_btn_h_ratio·R` = 0.73R）：
##   ① 行内总宽 = cnt·2R + 间隙 ⇒ 半宽不变，**横向排布不变**；
##   ② 纵向预算按半高收半径，而 `_tile_base_r()` 与 action 行都读**同一个** `menu_btn_h_ratio`；
##   ③ 标签位置走 `_tile_label_pos()` 的**包围盒半宽/半高**（bbox 相同 ⇒ 标签一个像素都不动）。
##   ⇒ 这是刻意选的**最小改动面**：只换形状、不动几何，于是几百行布局判据**照旧成立**，
##     一轮回归就能把"形状换了"和"布局坏了"这两件事分开（改观感的同时改布局 = 分不清是谁坏的）。
## ⚠️ 若哪天要把按钮改扁（调 `menu_btn_h_ratio`），② 会跟着变 —— 那就**必须**重跑
##   `--labeltest` 的 [行带] 净空与 `--menutest` 的行间间隙（真源收在一处正是为了这件事）。
##
## ★ 点序必须**沿轮廓连续、顺时针**：`Geometry2D.is_point_in_polygon` 不在乎绕向，
##   但 `draw_polyline`（描边/呼吸光晕）要闭合、`_stone_side_walls()` 逐**相邻点对**生成墙裙
##   ⇒ 点序跳一下就会画出一条穿过按钮的假边。
## ★ 轮廓只有**一族**（半宽 R、半高 `menu_btn_h_ratio·R`）。**"向内收几像素"不在这里做**：
##   那个需求（凹陷态的内嵌斜面环）由 `_inset_convex(poly, t)` 按**边法线内移**完成 ——
##   理由是"按法线内移与朝向无关"，而重造一条同心的内轮廓要求知道 center 与 R，
##   且 `draw_poly` 可能是**旋转过**的（`_rot_t`）⇒ 内外轮廓错位，只在旋转态可见（静默）。
##   ⚰️ 2026-10-12：这里原有第三个参数 `inset`（把 hw/hh 各减 inset 重造内轮廓）。
##     唯一设想过的调用点是"斜面环的内线"，而实际实现走了 `_inset_convex()` ⇒
##     **没有任何调用者** ⇒ 它是个**死参数**（铁律 §33：拧不动的旋钮；留着还会引诱下一个人
##     用它，而那条路是错的）。连 `hw`/`hh` 上的 `- inset` 一起删，行为不变（`inset` 恒为 0）。
## ★★ 2026-10-15：签名从「只吃一个 R」扩成**显式半宽/半高/圆角**（瓷砖的形状改口径后，
##   半宽由文字定、半高仍由 R 定，两者不再成比值）。两个新参数都**带"走旧口径"的默认值**，
##   于是所有只传 R 的老调用点（判据自造样本那一族）**行为逐像素不变**。
##   · `hh_in < 0` ⇒ `hw × menu_btn_h_ratio`（旧口径）
##   · `cr_in < 0` ⇒ `min(hw,hh) × menu_btn_corner`（比值口径，1.0 = 胶囊）
##   ⚠️ 瓷砖走的是 `_tile_poly()`（**绝对像素**圆角 `DIALOG_CORNER`）—— 比值口径与绝对口径
##     是两回事，别互相传（一处混用就会出现"圆角随块大小乱变"或"大块圆角被压成 0"）。
func _make_btn_rect(center: Vector2, hw_in: float, hh_in: float = -1.0,
		cr_in: float = -1.0) -> PackedVector2Array:
	var hw: float = maxf(hw_in, 0.5)
	var hh: float = maxf(hh_in if hh_in >= 0.0 else hw_in * menu_btn_h_ratio, 0.5)
	var max_cr: float = minf(hh, hw)
	var cr: float = clampf(cr_in if cr_in >= 0.0 else max_cr * menu_btn_corner,
		0.0, max_cr)
	var sx: float = hw - cr
	var sy: float = hh - cr
	var seg: int = maxi(1, menu_btn_corner_seg)
	var pts := PackedVector2Array()
	pts.append(center + Vector2(-sx, -hh))      # 上边左端
	pts.append(center + Vector2(sx, -hh))       # 上边右端（= 右上圆弧起点）
	# 四个角顺时针：右上(−90°→0°) → 右下(0°→90°) → 左下(90°→180°) → 左上(180°→270°)
	var corners := [Vector2(sx, -sy), Vector2(sx, sy), Vector2(-sx, sy), Vector2(-sx, -sy)]
	var a0s := [-PI * 0.5, 0.0, PI * 0.5, PI]
	# 每个角之后的**那条直边的另一端**（左上角之后回到起点，故只有 3 条）
	var edge_ends := [Vector2(hw, sy), Vector2(-sx, hh), Vector2(-hw, -sy)]
	for q in 4:
		var cc: Vector2 = corners[q]
		var a0: float = a0s[q]
		for k in range(1, seg + 1):
			var a: float = a0 + PI * 0.5 * float(k) / float(seg)
			pts.append(center + cc + Vector2(cos(a), sin(a)) * cr)
		if q < 3:
			pts.append(center + edge_ends[q])
	# ★★ 去掉**重合点**。旧口径（圆角矩形，`sy > 0`）只有"左上圆弧终点 == 起点"这一处重合；
	#   胶囊形下 `sy == 0`，每条直边的端点与相邻圆弧的端点落到同一处（`sx + cr` 与 `hw` 只差
	#   浮点舍入，`distance_to` 一定不是 0）⇒ 不去掉会多出零长度边：
	#     ① `draw_polyline`（描边 / 呼吸光晕）多一段退化线段；
	#     ② `_tile_side_walls()` 多一个**零面积四边形**。
	#   ⇒ 顺带得到一个更强的不变量：**点数确定 = `4×seg + 2`** —— 于是"外墙"与
	#     `_inset_convex()` 给出的内轮廓**点数必然相同、逐点一一对应**，
	#     斜面环按下标配对就靠这一条（`--menutest` ⑩h 直接断它）。
	var out := PackedVector2Array()
	for p in pts:
		if out.size() > 0 and out[out.size() - 1].distance_to(p) < 0.001:
			continue
		out.append(p)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.001:
		out.remove_at(out.size() - 1)
	return out


## 瓷砖（菜单块）的轮廓：**形状 = 新版全局按钮** —— 圆角是 `DIALOG_CORNER` 的**绝对像素**
## （不是胶囊，也不是"半高 × 比值"）。`hw/hh` 由 `_tile_box()` 给出，这里只管"长成什么样"。
##
## ★ 为什么圆角必须走**绝对像素**：`DIALOG_CORNER` 同时是"是不是我们那支 StyleBoxFlat"
##   的签名（`game_config.gd` 里 `set_corner_radius_all(DIALOG_CORNER)`）。瓷砖若用比值口径
##   （旧 `menu_btn_corner = 1.0` = 胶囊），两块砖的圆角会随块的大小各算各的 —— 那正是
##   "形状和新版全局按钮相同"这句话要消掉的东西。
func _tile_poly(center: Vector2, hw: float, hh: float) -> PackedVector2Array:
	return _make_btn_rect(center, hw, hh, maxf(GameConfig.DIALOG_CORNER, 0.0))

# ★ 2026-10-02：这里原有 `_gear_center()` / `_gear_radius()`（右上角齿轮中心 / 半径，
## 中心写死 `size.x − 34, 30`、半径 15，命中还要 `*1.35`）。
## 用户口令「主菜单设置小齿轮删掉，只留设置按钮；设置页面右上角的齿轮也换成棋盘按钮」
## ⇒ 齿轮**整建制删除**，两个函数一并删掉（`_draw_gear()` 同时删）。
## 顶上那块「返回」的几何一度由 `_back_tile_*()` 给出（由行带推导、命中走砖的真实多边形）；
## ★ 2026-10-04 v4 起那一族**也删了** —— 设置成了主菜单的一个面板，回去走底栏「练习」。
## ⚠️ 名字**不许回收**：留着 `_gear_*` 只会让下一个人去找一个不存在的东西。

# 把点绕屏幕「底边中点」旋转（页面旋转绘制管线，当前恒为 0）
# 以底边中点为轴，页面像转盘一样逆时针扫过，视觉上更稳且不至于把内容甩出屏幕上方
func _rotated(p: Vector2, angle: float) -> Vector2:
	var c := Vector2(size.x * 0.5, size.y)
	return (p - c).rotated(angle) + c

## ★★ 2026-10-04 v4：这里原有 `func _tile_click_page_ok(page) -> bool`（"这一页的瓷砖点击
##   要不要处理"的闸：设置页挡、其余放行）。用户口令「把…设置选项挪过来…，删掉设置页的
##   返回按钮」之后，设置**不再是独立页**而是主菜单的一个面板 —— 底栏四块必须**在每个面板
##   上都可点**（那是换面板的唯一入口）⇒ 这道闸**一个面板都不该挡**，于是没有存在意义了。
##   ⚠️ 删而不是"改成恒 return true"：恒真的闸 = 没有闸，而留着它会让下一个人以为
##   "某些面板的瓷砖点击是被挡住的"，从而把真正的病因（原生控件盖住底栏）查错地方。
##   ★ 那它当年守的东西现在归谁守：设置面板的原生控件树被要求**整棵落在底栏带之上**
##   （`_build_settings_ui()` 读 `_footer_band()`），由 `--settest` 的「不压底栏」量。

## 「一次瓷砖点击最终命中哪一项」= 命中测试（未命中返回 -1）。
##
## ★★ 抽出来的唯一理由：`_input()` 里 `await create_timer(STONE_ANIM_TIME+0.05)` **之后**
##   才调 `cb`，而自检若合成真事件喂 `_input` 就必须跟到那一步 —— 那条 `await` 链一断，
##   整个自检函数（连同末尾的 `quit()`）**一起消失** ⇒ 挂到超时，日志里一条判据都没有
##   （本文件在 `--steamuitest` 上已记过这笔账）。⇒ 判据走"命中"这一段，
##   "命中之后落子/调 `cb`"那一段由 ①b / ②b 各自覆盖。
func _tile_hit_for_click(p: Vector2) -> int:
	return _tile_at_point(p)

# ====== 输入：点瓷砖 = 执行它对应的功能 ======
func _input(event: InputEvent) -> void:
	# ⚰️ 2026-10-12：这里原有 `if _input_locked: return`（锁住"落子动画那 0.35s"里的重复点击）。
	#   动画与它那条 `await` 链删除后本函数是**同步**的（点完即走完）⇒ 没有窗口要锁。
	#   连带删掉的还有函数末尾那句 `await create_timer(...)` —— 见那里的墓碑。
	# ESC：弹出退出游戏确认面板（主菜单此前没有退出程序的入口，只能 Alt+F4）
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_quit_confirm()
		get_viewport().set_input_as_handled()
		return
	# 退出面板开着：忽略一切点击。⚠️ 本函数是 Node._input，**先于** GUI 输入分发，
	# 遮罩的 mouse_filter=STOP 挡不住这里 —— 必须显式拦截（否则隔着面板还能点瓷砖）
	if _quit_layer != null:
		return
	# ★ 2026-10-08：这里原有「左侧浮层面板可见时，点它的输入框区域不触发瓷砖点击」那一段 ——
	#   浮层整族删除。对弈页是**另一个页面**（`_page == PAGE_LOBBY` 时页内瓷砖只有底栏四块），
	#   而底栏在页内容**下方**、与输入框不相交 ⇒ 这个让位不再需要。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# ★ 2026-10-04 v4：这里原有"设置页右上角「返回」棋盘按钮"的分支 —— 那一族已整族删除。
		# ★★ 也不再按"哪一页"挡瓷砖点击了：底栏四块**每个面板上都要可点**（它是换面板的
		#   唯一入口），而设置面板的原生控件树被要求**整棵落在底栏带之上**（`_build_settings_ui()`
		#   读 `_footer_band()`），所以"看得见的控件"与"自绘瓷砖"不会抢同一块地方。
		#   ⚠️ 这条纪律的判据在 `--settest` 的「不压底栏」（量的正是那两棵树的关系），
		#   不在本文件的路由里 —— 路由这层现在**无闸可言**，写个恒真的闸只会误导下一个人。
		var id := _tile_hit_for_click(event.position)
		if id == -1:
			return
		var it: Dictionary = _items[id]
		if it["disabled"]:
			queue_redraw()
			return
		# ⚰️ 2026-10-12：这里原有「先铺一颗黑子 → `await 0.35s` 让落子动画播完 → 再执行功能」
		#   那条链 —— 随黑砖族整族删除。没有动画可等之后，那条 `await` 只剩纯粹的三分之一秒延迟
		#   （用户点「开始」要等 0.35s 才转场），连同它需要的 `_input_locked` 一起删。
		#   ⚠️ 本函数因此**不再是协程**。这反而是好事：见 `_tile_hit_for_click()` 的注 ——
		#   那条 `await` 链一断，喂合成事件的自检会**连着末尾的 `quit()` 一起消失**（挂到超时）。
		(it["cb"] as Callable).call()

# ====== ESC 退出游戏确认 ======
## 主菜单/设置页按 ESC 弹出。主菜单此前**没有**退出程序的入口（只能 Alt+F4）。
## 用 CanvasLayer 而不是画进 _draw：遮罩要吃掉瓷砖点击（STOP），且独立于自绘层不互相干扰。
var _quit_layer: CanvasLayer = null
var _quit_panel: Control = null
var _quit_dim: ColorRect = null

func _toggle_quit_confirm() -> void:
	if _quit_layer != null:
		_clear_quit_confirm()
	else:
		_show_quit_confirm()

## ⚠️ CanvasLayer 子控件拿不到视口矩形当父区域，anchors 不可靠 → 遮罩/面板手动定位；
## 居中交给 _refit_quit_menu，随窗口缩放实时跟随。
func _show_quit_confirm() -> void:
	_clear_quit_confirm()
	_quit_layer = GameConfig.new_themed_layer()
	_quit_layer.name = "QuitConfirm"
	_quit_layer.layer = 50
	add_child(_quit_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_dim = dim
	_quit_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	_quit_panel = panel
	# 底色/圆角/描边/内边距走 GameConfig（与 game.gd 的 ESC 暂停面板**同一套**：
	# 面板底色必须不透明才谈得上"文字对比度达标"，详见 game_config.gd 里那段坑注释）
	GameConfig.style_dialog_panel(panel)
	_quit_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.name = "DialogTitle"
	title.text = "退出游戏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	# ★ L2「页面标题」：同样用展示字体（楷体），字号仍是 26 —— 只换字形、不动尺寸，
	#   这样 `--esctest` 的面板对比度判据与既有坐标断言都不受影响。
	UITheme.apply_page_title_font(title, GameConfig.use_portrait_canvas())
	# ★ 不能再用 accent_color()：那是"对棋盘背景"推导的，浅色主题下是深棕，压在深色面板上
	#   实测对比度只有 2.88。dialog_title_color() = 同一强调色提亮到对面板底色达标。
	title.add_theme_color_override("font_color", GameConfig.dialog_title_color())
	vb.add_child(title)
	var hint := Label.new()
	hint.name = "DialogHint"
	hint.text = "确定要退出吗？再按 ESC 可取消"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	# 同理不能用 ink_color()：浅色主题下它是近黑 (0.10,0.10,0.12)，对面板底对比度实测 1.06（等于没字）
	hint.add_theme_color_override("font_color", GameConfig.dialog_text_color())
	vb.add_child(hint)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var yes := Button.new()
	yes.name = "QuitYes"
	yes.text = "退出游戏"
	yes.focus_mode = Control.FOCUS_NONE
	yes.custom_minimum_size = Vector2(150, 46)
	yes.add_theme_font_size_override("font_size", 16)
	GameConfig.style_dialog_button(yes)
	yes.pressed.connect(func() -> void: get_tree().quit())
	hb.add_child(yes)
	var no := Button.new()
	no.name = "QuitNo"
	no.text = "取消"
	no.focus_mode = Control.FOCUS_NONE
	no.custom_minimum_size = Vector2(150, 46)
	no.add_theme_font_size_override("font_size", 16)
	GameConfig.style_dialog_button(no)
	no.pressed.connect(_clear_quit_confirm)
	hb.add_child(no)
	# 始终居中：先摆一次，布局完成后精确居中，窗口缩放实时跟随
	if not get_viewport().size_changed.is_connected(_refit_quit_menu):
		get_viewport().size_changed.connect(_refit_quit_menu)
	_refit_quit_menu()
	await get_tree().process_frame
	_refit_quit_menu()

## 面板/遮罩按当前视口重排：遮罩铺满、面板正中
func _refit_quit_menu() -> void:
	if _quit_layer == null:
		return
	var vs := get_viewport_rect().size
	if _quit_dim != null and is_instance_valid(_quit_dim):
		_quit_dim.position = Vector2.ZERO
		_quit_dim.size = vs
	# size==0 = 首帧布局未完成，跳过（等一帧后的精定位接手）
	if _quit_panel != null and is_instance_valid(_quit_panel) and _quit_panel.size.x > 0.0:
		_quit_panel.position = (vs - _quit_panel.size) * 0.5

func _clear_quit_confirm() -> void:
	if get_viewport().size_changed.is_connected(_refit_quit_menu):
		get_viewport().size_changed.disconnect(_refit_quit_menu)
	if _quit_layer != null and is_instance_valid(_quit_layer):
		_quit_layer.queue_free()
	_quit_layer = null
	_quit_panel = null
	_quit_dim = null


## 自检（--esctest）：ESC 退出确认面板。模拟按键事件走真实 `_input` 路径（不发真实键）。
func _esc_test() -> void:
	var ok := true
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	# ① 按 ESC → 面板出现
	_input(ev)
	if _quit_layer == null:
		ok = false
	# ② 面板里有「退出游戏」「取消」两个按钮
	var btns := {}
	_collect_buttons(_quit_layer, btns)
	if not (btns.has("QuitYes") and btns.has("QuitNo")):
		ok = false
	# ③ 面板开着时鼠标点击被忽略（遮罩挡不住 _input，靠那道显式守卫）
	#    ★★ 2026-10-12 重写探针（旧写法量 `_stones.size()` 有没有变，那个集合已随黑砖族删除）：
	#      现在**把目标瓷砖的 `cb` 换成一个置位探针** —— 这是"点击有没有真的被派发下去"的
	#      **直接**观测，而不是靠某个副作用有没有发生。同时把点击**打在真砖的中心**上：
	#      旧写法让 `event.position` 留在 (0,0)（那里根本没有砖 ⇒ 判据恒真、没有牙齿）。
	var me := InputEventMouseButton.new()
	me.button_index = MOUSE_BUTTON_LEFT
	me.pressed = true
	var probe_i: int = -1
	for i_e in _items.size():
		if str(_items[i_e]["group"]) == "nav" and (_items[i_e]["poly"] as PackedVector2Array).size() >= 3:
			probe_i = i_e
			break
	var fired := [false]
	if probe_i >= 0:
		me.position = _items[probe_i]["center"]
		var probe_cb: Callable = _items[probe_i]["cb"]
		_items[probe_i]["cb"] = func() -> void: fired[0] = true
		_input(me)
		_items[probe_i]["cb"] = probe_cb
	else:
		ok = false
	ok = ok and not fired[0]
	# ④ 再按 ESC → 面板关闭
	_input(ev)
	if _quit_layer != null:
		ok = false
	# ⑤ 「取消」回调也能关闭（「退出游戏」不按 —— 会真的退出程序）
	_input(ev)
	(btns["QuitNo"] as Button).pressed.emit()
	if _quit_layer != null:
		ok = false
	# ⑥ 居中：布局完成后面板中心应与视口中心重合（缩放窗口后由 size_changed 跟随，同口径）
	_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	if _quit_panel != null and is_instance_valid(_quit_panel):
		var pc: Vector2 = _quit_panel.position + _quit_panel.size * 0.5
		if (pc - get_viewport_rect().size * 0.5).length() > 1.0:
			ok = false
	else:
		ok = false
	# ⑦ 面板文字对比度（对**面板自己的底色**算，不是对菜单背景）：标题/正文/按钮三项都要达标，
	#    且阴性对照必须报警（=判据确实抓得住"字看不清"这个 bug）。
	#    ⚠️ 必须在面板**还开着**的时候量 —— `_clear_quit_confirm()` 之后控件就没了。
	var jr: Array = GameConfig.judge_dialog_contrast(_quit_layer)
	var ok_c: bool = bool(jr[0])
	if not ok_c:
		ok = false
	_clear_quit_confirm()
	print("[esctest] 开/按钮/点击拦截/ESC关/取消关/居中 = %s → %s" % [str(ok), "通过 ✓" if ok else "失败 ✗"])
	print("[esctest] ⑦ 面板文字对比度：%s → %s" % [String(jr[1]), "通过 ✓" if ok_c else "失败 ✗"])
	get_tree().quit()

## 递归收集子树里的 Button（按 name 索引）
func _collect_buttons(node: Node, out: Dictionary) -> void:
	for c in node.get_children():
		if c is Button:
			out[String(c.name)] = c
		_collect_buttons(c, out)

## 鼠标点落在哪块瓷砖上（返回 _items 下标；-1 = 没点中）。
## 棋盘行是循环行：同一块可能同时出现多次 → 必须逐**槽位**判，不能再用 it["poly"] ——
## 那只代表「离焦点最近的那次出现」，点在别处的重影上会答错。
## 低于该透明度的重影不响应点击：看得见却点不到会怪，所以取一个较宽松的阈值。
func _tile_at_point(p: Vector2) -> int:
	for i in _items.size():
		var it: Dictionary = _items[i]
	# ★ 2026-10-09：这里原有两道「折叠未展开就不响应点击」的闸（diff 读 `_diff_t`、
	#   boardsize 读 `_board_t`）—— 两组都不再折叠，恒在屏上 ⇒ 闸恒真 = 没闸，整族删除。
	#   ⚠️ 留着会让人以为「收起态」还存在，而它已经没有任何生产者（本文件记过这笔账）。
		# ★★ 2026-10-04 第四版：这里原有的两道「设置区收起则不可点」的闸**已删** ——
		#   `_quick_t` / `SETUP_GROUPS` 随折叠机制一起消失（「练习」现在是**面板**，不是开关）。
		#   为什么删掉而不是留成恒真：留一个永远为真的闸，下一个人会以为"收起态"还存在，
		#   而它已经没有任何生产者 ⇒ 恒真判据 = 没测（这类死状态在本文件记过账）。
		#   设置区那几组现在**只在自己的面板上存在**（`_set_page()` 只在 PAGE_MAIN 建它们），
		#   所以"别的面板上点得到练习区的砖"结构性不可能 —— 不需要闸。
		# ★★ 2026-10-16：这里原有 `if it["group"] == "board": continue` + 紧随的
		#   「重影之间取透明度最高的那次重现」（`BOARD_HIT_ALPHA` 阈值 + `_board_slots` 循环）。
		#   棋盘行改**静态平铺** ⇒ 每块只有一次出现、alpha 恒 1 ⇒ 那一支与上面这一支
		#   **逐字段等价** ⇒ 整族删除（连同 `BOARD_HIT_ALPHA` 常量）。
		if Geometry2D.is_point_in_polygon(p, it["poly"]):
			return i
	return -1

# 逐帧驱动：棋盘行滑动缓动 + 呼吸描边相位
func _process(delta: float) -> void:
	# ⚰️ 2026-10-12：这里原有本函数**开头**的两段"黑砖动画推进"（`_stone_anims` / `_stone_outs`
	#   逐帧递减、到点擦除）—— 随黑砖族整族删除。
	#   ⚠️ 那两段当年的纪律值得留住（**别丢**）："动画计时的推进只允许在 `_process` 里"，因为
	#     散到绘制侧会变成"帧率越高动得越快"（本文件在背景旋转相位上记过同一笔账，守卫 S53）。
	#     现在本函数仍是全部的"逐帧推进点"（棋盘滑动 + 呼吸相位），那条纪律没有被放宽。
	# ★ 2026-10-09：这里原有「难度折叠进度 `_diff_t` 向 `_diff_target` 缓动」那一段 ——
	#   难度三档平铺进「对战方式」行之后不再有出现/消失动画 ⇒ 折叠进度没有生产者，
	#   整段删除（`_board_t` 那一段**保留**：它还驱动「切换棋盘 → 整行滑动」的时序）。
	# ★ 2026-10-08：这里原有「联机折叠进度向 `_net_target` 缓动」那一段 —— 随 netmode 两瓣
	#   整族删除（练习面板不再有联机入口，"从「线上」左侧长出"这件事不存在了）。
	#   剩下两种折叠（难度 / 棋盘大小）照旧。
	# 棋盘大小折叠进度向目标缓动（时长 = `BOARD_FOLD_TIME`）
	if absf(_board_t - _board_target) > 0.001:
		var step := delta / BOARD_FOLD_TIME
		if _board_t < _board_target:
			_board_t = minf(_board_t + step, _board_target)
		else:
			_board_t = maxf(_board_t - step, _board_target)
	# 主视觉背景棋盘缓慢漂移 + 缓慢旋转（相位只做时间累积，绘制侧自己取样）。
	if _page == PAGE_MAIN:
		# `_bg_frozen` 只给截图夹具用（见 `--shotspin=`）：钉住相位才能拍到最大摆角那一档。
		# ★ 漂移与旋转**一起**受它管：两帧之间只允许差一个旋转角（见 `_bg_frozen` 的说明）。
		if not _bg_frozen:
			_bg_drift = fmod(_bg_drift + delta * 0.06, 1.0)
			# 缓慢旋转：与漂移同款"只累积相位、绘制侧取样"（摆幅在 `_bg_ensure()` 里解出）。
			# ⚠️ 相位必须**只在这里**推进：散到绘制侧就变成"帧率越高转得越快"，
			#   而且 `_draw` 里改状态会让同一帧画两次得到不同的图（守卫 S53 钉着这一行）。
			_bg_spin = fmod(_bg_spin + delta * BG_SPIN_RATE, 1.0)
		queue_redraw()
	# 收回完成后才换锚点：循环行里各棋盘的折叠簇锚点不同，必须先收回，
	# 否则二级菜单会瞬移（旧实现把 _board_t 直接置 0，就是这个观感）。
	if _board_pending >= 0 and _board_t <= 0.001:
		_sel_board = _board_pending
		_board_pending = -1
		# ★★ 2026-10-16：原先这里还要 `_board_row_target = _board_target_pos(...)`（换卷绕槽位）
		#   再由下面那段"整行横移"驱动重排。棋盘行改**静态平铺** ⇒ 没有滑行、没有槽位
		#   ⇒ 换盘即时重排一次即可（少滑一段，但换盘本身仍然走
		#   「先收回 `_board_target=0` → `_board_t` 缓到 0 → 换 `_sel_board` → 再展开」这条既有链）。
		_layout_setup()
	elif _board_target < 0.5 and _board_pending < 0 and absf(_board_t - _board_target) < 0.001:
		# 收回完成 → 才把大小三档展开（顺序仍是「先收回、再展开」；`_board_t` 是这条链的时序闸）
		_board_target = 1.0
	# 呼吸描边持续脉动 → 每帧重绘（菜单场景开销可忽略）
	_breath_t += delta
	queue_redraw()

# ====== 绘制 ======
func _draw() -> void:
	# 背景（始终绘制：主菜单瓷砖与设置页原生控件都需底色）
	# ★ 底色走 `_page_surface()`（= `GameConfig.page_surface()`）这个**唯一真源**：
	#   页面按钮的调色板入参读的是同一个函数 ⇒"按钮浮在它自己那张面上"这件事
	#   由结构保证，不靠两处各写一遍乘法（见该函数的注）。
	var bg: Color = _page_surface()
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# 首页主视觉：当前所选棋盘的**真实密铺**（低不透明度衬底 + 极慢漂移）
	if _page == PAGE_MAIN and not _items.is_empty():
		_draw_menu_bg_tiling()
	# ★ 2026-10-04 v4：这里原有 `_draw_back_tile()`（设置页右上角的「返回」棋盘按钮）。
	#   它随 v4 整族删除 —— 设置成了主菜单的一个面板，回去走底栏「练习」。
	#   ⚠️ 那一角**本来就是空的**（齿轮 2026-10-02 已删），现在连"只在设置页出现的那块"也没了。
	if _items.is_empty():
		return

	# 页面旋转 + 淡出/淡入（当前 _rot_t 恒为 0，即不旋转）
	var rot_alpha := clampf(cos(_rot_t), 0.0, 1.0)

	# ★ 2026-10-09：这里原有两组「折叠簇缓动缩放」的中间量（`hc`/`cluster`/`clusterA` 用于
	#   难度三瓣、`bc`/`board_cluster`/`boardA` 用于大小三瓣）—— 两组都改成平铺/单列一行，
	#   没有簇可以"绕锚点缩放"了 ⇒ 整族删除。所有非循环行现在走同一条绘制路径。
	#   ⚠️ 名字不许回收（铁律 §18）：`cluster*` 这组名字别再拿来装别的东西。

	# 设置屏行标题（随切换动画旋转）。
	if "--labelpos" in _argv() and not _labelpos_done:
		_labelpos_done = true
		print("[labelpos] size=%s rot_t=%.3f" % [str(size), _rot_t])
		for sl2 in _section_labels:
			print("[labelpos]   分组=%s text=%s y=%.1f fs=%d" % [
				sl2["group"], sl2["text"], sl2["y"], int(sl2.get("fs", 18))])
	for sl in _section_labels:
		# ★ 2026-10-09：这里原有 `var fade := 1.0` + 「对战方式」行标题按难度折叠进度
		#   （`fade = 1 - clamp(_diff_t*2,0,1)`）淡出让位的那一段 —— 折叠机制整族删除后
		#   没有任何行标题需要让位 ⇒ 恒真的 `fade` 与恒假的 `if fade <= 0.01` 一起删
		#   （留着就是"看起来还有人在让位"的死状态，本文件记过这笔账）。
		# ⚰️ 2026-10-12：这一行**当年**的理由是「快速设置」收起后设置区整体淡出 ——
		#   否则屏幕上只剩「棋盘 / 对战方式」两个孤零零的小标题挂着（比不淡出更怪）。
		#   折叠机制整族删除后，随它一起留下的 `head_setup_a` 恒为 1.0、紧跟的
		#   `if head_setup_a <= 0.01: continue` 是**永不执行的分支** ⇒ 整段删除。
		#   ⚠️ 上一批（2026-10-09）删的是它**上面两行**那条同形状的 `fade`（墓碑见上），
		#   同一个残渣**漏了这两处** ⇒ 见到"恒真局部 + 恒假 if"要把函数扫完再收工。
		var pos: Vector2 = _rotated(Vector2(size.x / 2.0, sl["y"]), _rot_t)
		var col := GameConfig.ink_color()   # 随背景明度反转，浅背景下仍可读
		col.a *= rot_alpha
		# 字号由 _row_head_font_size 按行高给出（矮行用小字号，为「标签 + 菱形」腾纵向空间）
		_draw_label(sl["text"], pos, col, int(sl.get("fs", 18)))

	# 子页空态提示（棋谱库 / 联机大厅）：占位页什么都不画会看起来像"坏了"。
	# ★ 走 `_empty_hint()` 这条唯一真源 —— 位置/文字/字号都不能在这里另算一遍，
	#   否则判据量的是 A、画的是 B（本项目"判据量 24、画 20"那类静默错配）。
	# ★ 它是独立的一笔：不归任何「设置区淡出闸」管（那个闸已随折叠机制整族删除）。
	var hint: Dictionary = _empty_hint()
	if not hint.is_empty():
		var hcol := GameConfig.ink_color()
		hcol.a *= rot_alpha * 0.72      # 提示文字比正文淡一档：是说明，不是选项
		_draw_label_centered(str(hint["text"]), _rotated(hint["center"], _rot_t),
			hcol, int(hint["fs"]))

	# ⚰️ 2026-10-13 墓碑：这里原有 `var tex_ok := ...`（把纹理开关与懒加载在本帧算一次、
	#   循环里复用）。它先因釉面填充改走 `_fill_tile_poly()` 而变成死变量，
	#   随后釉面纹理整族删除 —— 两件事都不需要在这里留任何东西。

	# 组装本帧要画的「画笔」，一次一笔：
	#   · 普通行（大小 / 对战方式 / 开始）：每块一笔，绕屏幕中心旋转后直接入列；
	#   · 棋盘循环行：每个可见**槽位**一笔 —— 一块可能有多次重现，且各自有不同的透明度。
	#     ★ 2026-10-09：原先 diff / boardsize 两组还要"按折叠进度绕簇心缩放"——
	#       两组都改成平铺 / 单列一行之后没有簇了，那一支整段删除（见上面那处墓碑）。
	var draw_passes: Array[Dictionary] = []
	for i in _items.size():
		var it0: Dictionary = _items[i]
		# 防御性：未完成布局（poly 为空）的瓷砖直接跳过（首次帧 / 旋转切换中）
		if it0["poly"].size() < 3:
			continue
		# ★★ 2026-10-16：这里原有 `if it0["group"] == "board": continue` + 紧随的
		#   `for s in _board_slots:` 一整段「按槽位逐笔入列」（同一块多次重现、各自不同 alpha）。
		#   棋盘行改**静态平铺**之后，每块只有**一次**出现 ⇒ 那段里的 `off` 恒 0、
		#   `extra` 恒 1、`home` 恒 true，与下面这一支**逐字段等价** ⇒ 整族删除。
		#   ⚠️ 留一个"恒等的第二支"是最难发现的死代码：它在日志里与"没有这个分支"
		#     长得一模一样（本文件在 `_setup_alpha` 上记过同一笔账）。
		# ★ 2026-10-09：这里原有 `if it0["group"] == "diff"` / `elif ... == "boardsize"`
		#   两支（按折叠进度绕簇心缩放 + 淡出），只剩 `else` 这一支 —— 折叠机制整族删除。
		#   ⚠️ `pfold` 因此恒为 1.0，但它**不能删**：`draw_passes` 的每一项都带这个键，
		#   下游按 `float(p["fold"])` 给这一笔乘不透明度，缺键会取到 0（整块变透明）。
		var pc := Vector2.ZERO
		var ppoly := PackedVector2Array()
		var pfold := 1.0   # 本组折叠透明度（恒 1.0：折叠机制已整族删除，键仍要留）
		for pp in it0["poly"]:
			ppoly.append(_rotated(pp, _rot_t))
		pc = _rotated(it0["center"], _rot_t)
		draw_passes.append({"i": i, "center": pc, "poly": ppoly, "extra": 1.0, "fold": pfold, "home": true})

	# ⚰️ 2026-10-12：这里原有 `deferred_stones` / `label_passes` 两段"延后画"的暂存 ——
	#   随黑砖族整族删除。它们当年的唯一理由是**抬起的黑砖会压到别的砖/别的标签**
	#   （⑩e 用 22 块真砖探针实测 17 处相交、最重 3703px²）⇒ 逼出"离位块最后画 + 全部标签
	#   再最后画"这条一律的规则。没有黑砖之后这两段是**逐像素等价的空操作** ——
	#   而"恒真的变换"与"没有这个变换"在日志里长得一模一样（铁律 4）⇒ 删掉，
	#   免得下一个人以为"还有东西会盖住标签"，从而不敢把标签就地画。
	#   ⚠️ 名字不许回收（铁律 §18）：`deferred_stones` / `label_passes` 两个名字别再装别的东西。

	# ★ 本帧的按钮调色板（可用字 / 禁用字）—— 字色只从这一处派生。
	# ⚠️ 2026-10-12：这里**不再**读 `ink_sel`。理由见 `_tile_label_color()` 的注：
	#   那一对（`fill_sel`/`ink_sel`）是**对着实心 accent 底**算出来的，而瓷砖底是
	#   `_fat_color`（主题棋盘色）⇒ 浅主题下会把字推成近黑、压在深色砖上。
	var _btn_pal: Dictionary = GameConfig.button_palette(_bg_color)
	for d in draw_passes:
		var i: int = int(d["i"])
		var it: Dictionary = _items[i]
		var draw_center: Vector2 = d["center"]
		var draw_poly: PackedVector2Array = d["poly"]
		var extra_a: float = float(d["extra"])   # 循环行的淡入淡出（普通行恒 1）
		var fold_a: float = float(d["fold"])     # 所属二级菜单的折叠进度
		# ★★ 2026-10-02 / 2026-10-12：`fade` 是**唯一**的相乘点 —— 下面每一笔（厚边 / 面 /
		#   斜面环 / 描边 / 呼吸光晕 / 标签）都从它派生，一处相乘即可覆盖全部；反过来
		#   在各处各乘一次，将来加一笔新的就会漏。**这条纪律不随折叠机制退役。**
		#   ⚰️ 2026-10-12：这里原有 `setup_a`（「快速设置」收起时设置区整体淡出）+ 一条
		#   `if setup_a <= 0.01: continue`。折叠机制整族删除后它恒为 1.0、那条 `if` 是
		#   **永不执行的分支**（`_setup_alpha()` 已无消费者）⇒ 整段删除。删的是空操作，
		#   行为不变；留这段注只为说清"这里当年真有一闸"。
		# ★ 本笔的**总淡出系数**（循环行端点 / 折叠收起 / 页面旋转，三档合一）。
		#   旧写法是"底色乘一遍、黑砖再单独乘一遍"（黑砖有自己独立的落子缓动）；
		#   黑砖删除后只剩这一个来源 ⇒ 新加的笔**结构性不可能漏乘**。
		var fade: float = extra_a * fold_a * rot_alpha
		var disabled: bool = it["disabled"]
		var selected: bool = it["selected"]
		# ===== 立体感：未选 = 凸起 / 已选 = 凹陷（2026-10-12）=====
		# 面色：凹陷态压暗一档（"陷进阴影里"）；凸起态就是砖本色。
		# ★ 底色走 `_tile_face_color()` 这条唯一真源 —— `_tile_label_bg()` 与 ⑩k 的字色对账
		#   都从它派生 ⇒ 底与字**不可能各取一次**（那正是"黑字压黑砖"的根因）。
		var sunken: bool = selected and not disabled
		var face: Color = _tile_face_color(it)
		if sunken:
			face = face.darkened(TILE_FACE_DARKEN)
		face.a = fade

		# ① 凸起态：先在砖**下面**画一截厚边（凹陷态是"贴平在盘面上"的 ⇒ 不画）。
		#    ★ 画序：厚边 < 面（反过来就成了"厚边盖住自己的面"，与对局盘 S3 同一条语义）。
		#    ★ 厚边只**向下**伸出 `_tile_relief_depth()` 像素、而该值远小于行间净空
		#      （`ROW_ROW_GAP`），所以它不会跨到下一行去 —— `--menutest` ⑩d 直接断这个上界。
		if not sunken and not disabled:
			var wall_col: Color = _tile_edge_color(face, 0.0)
			for q in _tile_side_walls(draw_poly, Vector2(0.0, _tile_relief_depth(draw_poly))):
				draw_colored_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), wall_col)
		# ② 面：纯色平涂（釉面纹理 2026-10-13 整族删除，理由见 `_fill_tile_poly()` 处墓碑）
		_fill_tile_poly(draw_poly, face)
		# ③ 内嵌斜面环：**受光方向按凹凸反转** —— 这是"凸起 / 凹陷"的主要视觉线索。
		#    凸起：左上内侧**受光（亮）**、右下内侧**背光（暗）** ⇒ 边棱朝外翻出去；
		#    凹陷：整圈反过来 ⇒ 边棱朝里陷进去。
		#    ⚠️⚠️ 2026-10-12 修：上面这句契约**当时是对的、代码是反的**（写成右下受光）
		#      ⇒ 屏幕上"未选看着像凹、已选看着像凸"。方向公式已提成 `_tile_bevel_lit()`
		#      并改对；这条由 `--menutest` ⑩m 守（⑩c/⑩d/⑩h 是**对称量**，看不见方向）。
		#    ★ 环宽是从砖边**向内**取的 `bevel` 像素 ⇒ 凹凸两态的外轮廓**逐像素相同**，
		#      于是几百行布局判据与命中测试一个都不用改。
		#    ★★ 环宽还必须**比描边+发光伸进砖内的那段更宽**（`TILE_INK_REACH`）——
		#      实测最小那三行砖（半高≈21）原先只有 3.94px ⇒ 整圈环被墨迹盖掉、凹凸全无。
		#      由 `--menutest` ⑩n 守。
		#    ⚰️ 2026-10-12：这一段取代了原先的「黑砖标记」（整块染黑 + 落子/提子动画）——
		#      见本文件常量区那段墓碑（黑字压黑砖 ⇒ 用户报「已选按钮看不清字」）。
		var bevel: float = _tile_relief_bevel(draw_poly)
		var inner: PackedVector2Array = _inset_convex(draw_poly, bevel)
		if inner.size() == draw_poly.size():
			var bn: int = draw_poly.size()
			for k in bn:
				var k2: int = (k + 1) % bn
				var mid: Vector2 = (draw_poly[k] + draw_poly[k2] + inner[k2] + inner[k]) * 0.25
				# ★★ 受光权重走 `_tile_bevel_lit()` 这条**唯一真源**（⑩m 读同一个函数）。
				#    ⚠️ 2026-10-12 修：这里原来把方向公式**内联**在本处，而且是**反的**
				#    （藏在循环体里 ⇒ 判据想核对方向也无从下手，只能抄一份公式 = 铁律 §70）。
				var lit: float = _tile_bevel_lit(mid, draw_center, sunken)
				draw_colored_polygon(
					PackedVector2Array([draw_poly[k], draw_poly[k2], inner[k2], inner[k]]),
					_tile_edge_color(face, lit))

		# ④ 描边（可点击瓷砖金色描边；禁用灰红，且静态不呼吸）
		var line_col := _disabled_color if disabled else _accent
		line_col.a *= fade
		var closed := PackedVector2Array(draw_poly)
		closed.append(draw_poly[0])
		draw_polyline(closed, line_col, TILE_OUTLINE_W, true)
		# 可点击瓷砖：金色呼吸描边（脉动发光，让“可点按钮”更显眼）
		if not disabled:
			var pulse := 0.5 + 0.5 * sin(_breath_t * TAU / BREATH_PERIOD)   # 0..1 平滑脉动
			var glow := _accent
			glow.a = lerpf(0.30, 0.95, pulse) * fade   # 透明度呼吸
			draw_polyline(closed, glow, lerpf(TILE_GLOW_W_MIN, TILE_GLOW_W_MAX, pulse), true)  # 线宽呼吸
		# ⑤ 标签（★ 2026-10-09 用户口令「把文字放到按钮里面」）
		# ★★ 字色走 `_tile_label_color()` 这条**唯一真源** —— `--menutest` ⑩k 读**同一个函数**，
		#    对着 `_tile_label_bg()`（"字真正画在上面的那个底色"）量对比度。
		#    ⚰️ 2026-10-12 修：原实现在这里读 `_btn_pal["ink_sel"]`，而那一对（`fill_sel`/`ink_sel`）
		#      是**对着实心 accent 底**算出来的 —— 与瓷砖真实的底（`_fat_color`）不是一回事
		#      ⇒ 浅主题下 `ink_sel` 被推成近黑，压在深色砖上就是**黑字压黑砖**
		#      （用户报「已选按钮不要变黑，会看不清字」；截图像素实测选中块 (31,31,36)、字 (0,0,0)，
		#      对比度约 1.3）。**底与字各自取一次**就是根因，所以现在两者同出一源。
		var label_col: Color = _tile_label_color(it, _btn_pal)
		# ★ 2026-10-02：字号走 `_draw_fs_for()`（**唯一真源**）——
		#   绘制与 `--labeltest` / `--menutest` 的「标签互不重叠」判据读**同一个函数**。
		#   之前是一句 `26 if action else 22` 写死在绘制侧、判据侧完全不知道字号
		#   ⇒ 两处各猜一次，判据就算得不准（而它还算绿）。
		#   `nav`（三入口）与 `quick`（「练习」开关）**共用 24 一档**（v3 起两者同排一行，
		#   见 `_label_font_size_for` 的注）；
		#   它们都可能因底部行带太矮被逐档下调（见 `_layout_footer_row`）⇒ 必须读**实际值**。
		var label_fs := _draw_fs_for(it)
		label_col.a *= extra_a * fold_a * rot_alpha
		# —— 标签位置 ——
		# ★★ 2026-10-09 用户口令「把文字放到按钮里面」：
		#   旧口径是"挂在按钮**外面**"（③ 其余按钮放在上顶点之上 / ① 折叠子项放在展开侧外侧 /
		#   ② 折叠锚点还要做"避开二级菜单"的位移），那一整套是为**菱形**设计的：菱形四个角是空的，
		#   标签挂在外侧不会撞；换成实心的圆角矩形后，外挂的文字必然被相邻按钮压住
		#   （实测 `--menutest` ⑩g 报 2 处，为此加了 `_anchor_avoid_offset()` 那一整套补偿）。
		#   ⇒ 文字改画在**按钮内部**，位置就是这块按钮的中心 ⇒ ① ② ③ 三支 + 避让 + 放射散开
		#     整套几何**结构性不需要**（没有文字在按钮外，也就没有"谁压谁的字"这回事）。
		var lpos := _label_pos_for(it, draw_center, label_fs)
		# ★ 就地落笔（Ⰶ 2026-10-12：原先要"攒到最后画"，理由见上面 `deferred_stones` 的墓碑）。
		_draw_label_centered(str(it["label"]), lpos, label_col, label_fs)

	# ⚰️ 2026-10-12：这里原有「收尾（三件事，次序不能动）」那一整段 ——
	#   ① 画离位的黑砖（侧壁 → 顶面）② 描边/呼吸光晕**不**跟着延后 ③ 全部标签最后落笔。
	#   **整段删除**（随黑砖族）。那三条次序不变量的服务对象（"抬起来的砖会压到谁"）已经不存在
	#   ⇒ 留着任何一条都只会变成恒真式，而"恒真的顺序判据"和"没有这条判据"在日志里一模一样
	#   （铁律 4）。⚠️ 连同 struct_guard 的 S57a/S57b/S57c 一起退役（见守卫那几条的说明）。
	#   ★ 值得留住的一条教训（**别丢**）：那一段的存在证明过 —— "两段式的几何，守卫必须
	#     同时钉住**生产端与消费端**"。只钉消费端时，把生产端改成"就地画"会让收尾循环空转，
	#     守卫照样全绿（2026-10-02 阴性对照 NS2 实测报"没牙齿"）。

## ====== 瓷砖的「凹凸立体感」几何与配色（2026-10-12）======
##
## ★★ 用户口令「立体感按钮，已选时有凹进去的感觉」+「已选按钮不要变黑，会看不清字」。
##   本族**取代**原有的「黑砖」族（`_stone_*` 六条函数，见常量区那段墓碑）。
##
## 五条不变量（`--menutest` ⑩c/⑩d/⑩h/⑩k/⑩m/⑩n 各钉一条）：
##   ① **与砖边逐点对齐**：厚边 / 斜面环的几何都由"这一笔的 poly"现算，不另存一份副本；
##   ② **不改变包围盒**：斜面是**向内**取的、厚边只向下伸 `_tile_relief_depth()` ＋ 该值
##      远小于行间净空（⑩d 直接断这个上界）⇒ 凹凸两态的外轮廓逐像素相同
##      ⇒ 几百行布局判据与命中测试一个都不用改；
##   ③ **边色从面色派生**：换主题时厚边 / 斜面自动跟着走，不会留下"上一版主题的边"；
##   ④ **受光方向**：凸起 = **左上**受光（亮）/ 凹陷 = 整圈反过来（⑩m）——
##      ⚠️ 这是**唯一一条"方向型"不变量**，而 ①②③ 全是**对称量**（单调/对齐/派生），
##      方向写反时它们**照样全绿**（2026-10-12 实测：代码写成右下受光，①②③ 全绿）。
##   ⑤ **看得见**：斜面环宽必须 > 描边+发光伸进砖内的半径（⑩n）——
##      "几何算对了"与"屏幕上真的看得见"是两件事（实测小砖上环被墨迹整圈盖掉）。
##
## ⚠️ 尺寸一律**从 poly 现算**（不写 `R * 0.73`）：菜单的循环行会把同一块砖投影到多个槽位，
##   几何只有 poly/center 是真的（`_items[i]["poly"]` 是"离焦点最近的那一次"的记账值）。
##   这条纪律原先写在已删的 `_stone_inr()` 上 —— 那是黑砖族里**唯一值得继承**的东西，故留下。
##
## ⚠️ 已知限制（**量到了、但不当红判**，留账）：暗色主题上面色本身接近黑（霓虹 = (14,29,34)），
##   厚边 = 面色压暗 0.42 ⇒ (8,17,20)，与背景 (9,11,19) 的亮度差只有 ~1/255
##   ⇒ **暗色主题下"厚边"这一档基本看不见**（斜面环不受影响，它是从面往两个方向拉开的）。
##   要改它得动"边色从面色**乘性**派生"这条契约（近黑面色乘 0.58 无处可去），
##   而那会让 12 个主题的观感一起变 —— 属**审美决策**，不由自检单方面拍（铁律 11）。

## 一块瓷砖的**包围盒半高**（= `r_base × menu_btn_h_ratio`）—— 厚度 / 斜面宽度都以它为尺度。
## ★ 2026-10-15：形状改口径后**半宽不再等于半高比的分母**，但半高本身一点没变
##   （`_tile_hh_for()` 仍走 `menu_btn_h_ratio`）⇒ 这里按包围盒现量，读数与改口径前**逐像素相同**。
func _tile_half_h(pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return 0.0
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	return bb.size.y * 0.5

## 凸起态的**厚边高度**（像素）= 半高 × `TILE_RELIEF_DEPTH`，地板 `TILE_RELIEF_MIN`。
## ★ 地板与对局盘 `_drop_height()` 同一条理由：地板太大就把旋钮吃掉（再调小完全没反应）。
## ★★ 上界：它必须**明显小于** `ROW_ROW_GAP`（行间净空），否则厚边会跨到下一行去。
##   这条由 `--menutest` ⑩d 直接断（`depth < ROW_ROW_GAP - 4`）—— 观感旋钮也要有牙齿。
func _tile_relief_depth(pts: PackedVector2Array) -> float:
	return maxf(TILE_RELIEF_MIN, _tile_half_h(pts) * TILE_RELIEF_DEPTH)

## 内嵌**斜面环宽度**（像素）= 半高 × `TILE_RELIEF_BEVEL`，两档一起夹：
##   · 下界 `TILE_RELIEF_BEVEL_MIN` —— 不是"再小看不出来"，而是"再小就被描边+发光盖掉"
##     （`TILE_INK_REACH`，真机截图像素取色实测得来）；
##   · 上界 `半高 × TILE_RELIEF_BEVEL_MAX_FRAC` —— 极小砖上地板会超过半高 ⇒ 会把整块面吃光。
## ★ 为什么要**上界**而不是"只抬地板"：这条函数是所有砖共用的（主菜单 + 设置页），
##   而设置页里的控件比主菜单小砖还小 ⇒ 只抬地板必然在那边捅出一个 `bevel ≥ 半高`。
func _tile_relief_bevel(pts: PackedVector2Array) -> float:
	var hh: float = _tile_half_h(pts)
	return clampf(maxf(TILE_RELIEF_BEVEL_MIN, hh * TILE_RELIEF_BEVEL),
		0.0, hh * TILE_RELIEF_BEVEL_MAX_FRAC)

## 一条斜面环边的**受光权重**（0 = 背光 / 1 = 受光）—— 唯一真源
## （`_draw()` 与 `--menutest` ⑩m 读**同一个函数**）。
##
## ★★ 方向契约（用户口令「立体感按钮，已选时有凹进去的感觉」）：
##   光从**左上**打来 ⇒ **凸起**（未选）的**左上内侧受光（亮）**、右下内侧背光（暗）；
##   **凹陷**（已选）整圈反过来。
##
## ⚠️⚠️ 2026-10-12 实测修（真机截图像素取色的结论，不是推的）：原实现把 `(dv.x + dv.y)`
##   **取正**那一半当受光（= 右下受光）⇒ 屏幕上"未选看着像凹、已选看着像凸"，
##   与上面这段契约、与用户口令**正好相反**。修法 = `lit = 1.0 − t`。
##   ★ 本文件当时的注释（"凸起：左上内侧受光（亮）"）**是对的，代码是反的** ——
##     而 ⑩c/⑩d/⑩h 全都看不见：它们量的是"边色随 `lit` **单调**"（对称量），
##     方向一翻，单调性照旧成立 ⇒ 这类缺陷**只有"量方向"的判据**能守（新增 ⑩m）。
## ★ 除法先护零：判据会拿假砖（R=50）跑同一个函数，理论上中心点也可能被喂进来。
func _tile_bevel_lit(mid: Vector2, center: Vector2, sunken: bool) -> float:
	var dv: Vector2 = mid - center
	var t: float = clampf((dv.x + dv.y) / maxf(dv.length(), 0.001) * 0.7071 * 0.5 + 0.5, 0.0, 1.0)
	var lit: float = 1.0 - t          # ★ 左上（t→0）受光 ⇒ 亮
	return 1.0 - lit if sunken else lit   # ★ 这一句就是"凹"的全部：受光方向反转

## **一条立体边的颜色** —— 从它所属的**面色**派生，`lit` ∈ [0,1]：0 = 背光、1 = 受光。
## ★★ 唯一入口：凸起态的厚边、凹凸两态的斜面环**全走这里** ⇒ 换主题时边跟着面一起走。
## ★ 透明度**跟着面色走**（`face.a` 是乘数）：循环行两端会淡入淡出，边必须一起淡，
##   否则会剩下一圈"没有面的边"（与 `--menutest` ⑩c 那条断言同源）。
func _tile_edge_color(face: Color, lit: float) -> Color:
	var t: float = clampf(lit, 0.0, 1.0)
	var c: Color = face.darkened(TILE_BEVEL_DARKEN).lerp(
		face.lightened(TILE_BEVEL_LIGHTEN), t)
	c.a = face.a      # ★ 显式钉住"边跟着面一起淡"（`darkened/lightened/lerp` 都保留 alpha）
	return c

## 把一条**凸**多边形的每条边向内平移 `t` 像素，返回**点数相同**的内轮廓。
## ★★ 符号约定（**这一条最容易写反**，实测反过一次）：`bis` 由**外**法线相加而来
##   ⇒ 内移必须写成 `p − bis·(t / (bis·n))`，写成 `+` 会变成**外扩**。
##   2026-10-12 的防线 = `--menutest` ⑩h（它有一条"内轮廓面积必须**小于**外墙"）。
## ★★ 用法：内嵌斜面环 —— `inner[k]` 与 `poly[k]` **一一对应**，直接按下标配对成四边形即可。
## ★ 为什么不写成"用 `_make_btn_rect(center, R − t, t)` 重造一条内轮廓"：
##   ① 重造要求知道 center 与 R，而绘制侧只有 poly；
##   ② 更要命的是**朝向** —— `draw_poly` 可能是**旋转过**的（`_rot_t`），重造出来的是没旋转的
##      ⇒ 内外轮廓错位，而且只在旋转态可见（静默）。按边法线内移则**与朝向无关**。
## ★ 斜接（miter）长度按 `1/cos(半夹角)` 放大 —— 这正是"两条边各内移 `t`"的等价条件，
##   于是**环宽处处恰好 t**（不是"顶点沿角平分线走 t"那种会让宽度随角度变的写法）。
##   圆弧段相邻边夹角很小（`seg=4` 时 22.5° ⇒ 放大 1.02）；直边与圆弧交界处是 90°（⇒ 1.41），
##   凸形状上不会长出尖刺。
func _inset_convex(pts: PackedVector2Array, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = pts.size()
	if n < 3:
		return out
	var acc := 0.0
	for k in n:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		acc += a.x * b.y - b.x * a.y
	# Godot 的 y **向下**增长 ⇒ 屏幕上顺时针的多边形（`_make_btn_rect()` 正是）
	# 给出 `acc > 0`，此时 `Vector2(e.y, −e.x)` 才是**外**法线；逆时针则整体取反。
	var sgn: float = 1.0 if acc > 0.0 else -1.0
	for k in n:
		var p: Vector2 = pts[k]
		var e0: Vector2 = (p - pts[(k - 1 + n) % n]).normalized()
		var e1: Vector2 = (pts[(k + 1) % n] - p).normalized()
		var n0 := Vector2(e0.y, -e0.x) * sgn
		var n1 := Vector2(e1.y, -e1.x) * sgn
		var bis: Vector2 = n0 + n1
		if bis.length() < 0.0001:
			out.append(p - n0 * t)          # 退化边（零长度）：退化成单边法线
			continue
		bis = bis.normalized()
		# ★★★ 符号**必须是减**：`bis` 是**外**法线的角平分线，要"往内 t"就得沿它反着走。
		#   推导：两条偏移线的方程各是 `(x − p)·n = −t`，代入 `x = p + s·bis` 得
		#   `s = −t / (bis·n)`。
		#   ⚠️⚠️ 2026-10-12 实测踩到（`--menutest` ⑩h **首跑**就报红，这条判据是为它写的）：
		#     写成 `+` 会把轮廓**向外**撑 6px ⇒ 整圈"内嵌斜面环"跑到砖**外面**去
		#     （实测内轮廓面积 7855 > 外墙 6049，正是外扩 6px 的量）。
		#     ★ 它**没有任何别的判据看得见** —— 布局判据量的都是 `poly`，而这一圈画在
		#       `poly` 之外；连"凹凸两态外轮廓逐像素相同"这条设计前提也一起被破坏了。
		# `maxf(…, 0.15)` 是斜接的保险：半夹角接近 90° 时 `bis.dot(n0)` 趋 0，
		# 不夹住的话斜接长度会飙到无穷（尖刺）。0.15 对应夹角上限约 162°。
		out.append(p - bis * (t / maxf(bis.dot(n0), 0.15)))
	return out

## 多边形与**矩形**的相交面积（自检用）。
## ★ 为什么要它而不是 `Rect2.intersects()`：那是**包围盒对包围盒**的粗判 —— 对"瘦菱形 vs 细长
##   标签框"这种组合会虚报（见 ⑩e 里的实测：粗判 8 处、精确判交 0 处）。判"字有没有被盖住"
##   必须按真实形状算，否则要么假红、要么（反过来放宽后）真漏。
func _raised_hits_rect(poly: PackedVector2Array, r: Rect2) -> float:
	var box := PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	])
	var area := 0.0
	for ip in Geometry2D.intersect_polygons(poly, box):
		area += _poly_area(ip)
	return area

## 多边形面积（鞋带公式，恒取正值）。
## ★ 为什么不找引擎函数：Godot 4 的 `Geometry2D` **没有** `area()` —— 实测写 `Geometry2D.area()`
##   会让 `--menutest` 报 `Static function "area()" not found`，而那个 SCRIPT ERROR 会**中止整个
##   自检函数**（连末尾的 `quit()` 一起带走）⇒ 表现是**挂到超时、日志里一条判据都没有**
##   （铁律 12 那条"失效方式不是变红而是中止调用函数"的又一例）。自己算四五个点的面积很便宜。
## 自检用：判「侧壁在 off=0 时是否退化」与「抬起的砖到底压没压住别的砖」。
func _poly_area(pts: PackedVector2Array) -> float:
	var acc := 0.0
	var n: int = pts.size()
	if n < 3:
		return 0.0
	for k in n:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		acc += a.x * b.y - b.x * a.y
	return absf(acc) * 0.5

## ⚰️ 2026-10-12 墓碑（名字不许回收）：这里原有 `_stone_drop_h()` / `_stone_drop_state()`
##   ——「落子下落」的抬高量与瞬时状态（`1-tt²` 加速下落 + 透明度线性涨到实心，与对局盘
##   `_place_drop_state()` 逐字同源）。随黑砖族整族删除。
##   ★ 它当年被 `--menutest` ⑩a / ⑩d 钉着；那两条判据同步退役（编号不回收，留空号）。
##   ★★ 值得留住的一条**勘误**（**别丢** —— 它是对局盘 `game.gd::_capture_fade_state()`
##     注释里那句错的推导，当年抄公式时验算出来的）：
##     那里的注释写着「提子缓动取 `1-(1-t)²`，**不是**落子 `1-t²` 的时间反演：反演会把位移
##     挤进最后 30%……」。**这句在数学上不成立** —— 把落子曲线的自变量换成 `1-t` 得
##     `1-(1-t)² = 2t-t²`，与提子曲线**逐点相同**（实测 t=0.25 两者都是 0.4375、t=0.5 都是 0.75）。
##     也就是说提子曲线**恰恰就是**落子曲线的时间反演，两者是同一个东西。
##     ⇒ 结论（"半途 40% 看得出来"）是对的，**理由写反了**。
##     ★ 教训（与铁律 13「判据必须读真源」同族）：**注释里的推导也是要验算的** ——
##       它不像代码会被判据咬，写错就永远错着，下一个人还会照它推理。


## **任意一块砖**的厚边几何：把「砖的每条边」竖直拉到 `off` 之后的那个位置。
## 返回 `[[拉过去的边的起点, 拉过去的边的终点, 落点边的终点, 落点边的起点], ...]`（与顶点同序）。
## ★ 与对局盘 `_block_side_walls()` 同源，只差一处：那边收**瓷砖下标**（自己去取 `tiles[i]`），
##   这里收**这一笔的 poly**（理由见上面那段"尺寸一律从 poly 现算"）。
## ★ `off` 归零 ⇒ 侧面高度为 0、面积 0，自动消失（不需要额外判"没厚度就不画"）。
##   ⚰️ 2026-10-12 改名：原名 `_stone_side_walls()`。它当年的 `off` 是**动画位移**（随时间变），
##   现在只有一个静态用途 —— 凸起态的厚度，`off` 由 `_tile_relief_depth()` 给出。
##   ⚠️ 名字不许回收（铁律 §18）。
func _tile_side_walls(pts: PackedVector2Array, off: Vector2) -> Array:
	var out: Array = []
	var n: int = pts.size()
	for k in n:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		out.append([a + off, b + off, b, a])
	return out


## 一块瓷砖的**面色**（"这块砖本身是什么颜色"，不含任何状态）。
## ★ 唯一真源：`_draw()` 取它画面，`_tile_label_bg()` 与 `--menutest` ⑩k 的底色对账也读它。
func _tile_face_color(it: Dictionary) -> Color:
	if bool(it["disabled"]):
		return _disabled_color
	return _fat_color

## 一块瓷砖的**标签真正画在上面的那个底色**。
## ★★ 它存在的唯一理由（2026-10-12 用户报「已选按钮不要变黑，会看不清字」）：
##   字色必须对着**这个**取。旧口径是"选中就读 `button_palette()["ink_sel"]`"，而
##   `fill_sel`/`ink_sel` 那一对是**对着实心 accent 底**算出来的；主菜单瓷砖的底其实是
##   `_fat_color`（主题棋盘色）⇒ 浅主题下 `fill_sel` 被推近黑、`ink_sel` 跟着变成近黑
##   ⇒ **黑字压黑砖**（截图像素实测：选中块 (31,31,36)、字 (0,0,0)，对比度约 1.3）。
##   ⇒ 底与字必须**从同一个真源派生**，这一条就是那个真源。
func _tile_label_bg(it: Dictionary) -> Color:
	var c: Color = _tile_face_color(it)
	if bool(it["selected"]) and not bool(it["disabled"]):
		c = c.darkened(TILE_FACE_DARKEN)
	return c

## 一块瓷砖的**标签字色** —— `_draw()` 与 `--menutest` ⑩k 读**同一个函数**（唯一真源）。
## ★ 只按「禁用 / 可用」分两档：选中态只是把面压暗一档，底色仍在同一族明度里，同一个墨色够用
##   —— 而"够不够用"由 ⑩k 对**两态都**量，不是猜的。
## ★★ 兜底那一步不是装饰：`pal["ink"]` 只保证**对着 `pal["fill"]`** 达标，而瓷砖底是
##   `_fat_color`（两者只差"从背景推离 `BTN_SURFACE_MIN_CONTRAST` 倍"那个偏移）⇒ 一般也达标，
##   但**不保证**。⇒ 这里对着**真实底色**复检一次，不达标就退到白 / 黑里更优的一侧
##   （只动明暗、不动色相；正常主题下这一步不会被触发 —— 它是保险，不是常态）。
func _tile_label_color(it: Dictionary, pal: Dictionary) -> Color:
	if bool(it["disabled"]):
		return Color(pal["disabled_ink"])
	var ink: Color = Color(pal["ink"])
	var bg: Color = _tile_label_bg(it)
	if GameConfig.contrast_of(ink, bg) < GameConfig.BTN_TEXT_MIN_CONTRAST:
		var w := Color(1, 1, 1)
		var b := Color(0, 0, 0)
		ink = b if GameConfig.contrast_of(b, bg) > GameConfig.contrast_of(w, bg) else w
	return ink

## 铺一块瓷砖的**面**：纯色平涂（`draw_colored_polygon`）。
## ★ 保留成唯一真源的理由：「首页每一块砖」的面与它的几何派生走同一份口径 ——
##   两处各内联一份填充代码，将来改瓷砖面只会改到一处，而它们画的都是"同一块砖"，
##   观感分家是**看得见**的错（本项目"判据量 A、画 B"那族坑的近亲）。
func _fill_tile_poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, col)

## ★★ 2026-10-04 v4：这里原有**设置页右上角那块「返回」棋盘按钮的整族实现**
##   （`_back_tile_r/fs/center/poly/visible/hit`、`_back_stone_state()`、`_draw_back_tile()`、
##   `_back_tile_action()`、`_on_back_tile_pressed()`）。
##   用户口令「主菜单底栏四按钮固定在主菜单不动，上面的空间用来切换面板…设置选项挪过来之后
##   **删掉设置页的返回按钮**」⇒ 整族删除。理由：那四块常驻在**每一个**面板上
##   （`_footer_entry_descriptors()`），设置面板里按一下「练习」就回去了 ——
##   再留一颗"返回"就是三份回去的路（底栏 / 这块砖 / ESC 退出确认）。
##   ⚠️ 名字**不许回收**：留着 `_back_*` 只会让下一个人去找一个不存在的东西。
##   ⚠️ 它当年"不进 `_items`"的理由也随之消失（那时设置页的 `_items` 是空的、
##   瓷砖点击还被 `_tile_click_page_ok()` 挡着 —— 那个闸也在本轮删掉了）。

# 在 _items 中按 group+label 查找某瓷砖中心（用于按标签定位某一块瓷砖）
func _find_center(group: String, label: String) -> Vector2:
	for it in _items:
		if it["group"] == group and it["label"] == label:
			return it["center"]
	return Vector2.ZERO

## 调试辅助：按标签点选一个瓷砖（触发其回调 → 重建页面并开始折叠动画）。
## 自检（--labeltest）：棋盘大小三档 + 难度三档标签的净间距。
## 两两文字框的净间距 = max(水平净空, 垂直净空)；> 0 表示两框不相交。
## 同时算出「不加放射散开」的旧排版作对照，直接看出改善幅度。
func _label_spacing_test() -> void:
	const FS := 22
	var f: Font = UITheme.body_font()
	var th: float = f.get_ascent(FS) + f.get_descent(FS)
	print("[labeltest] 窗口=%s 散开系数=%.2f 字号=%d 文字高≈%.1f" % [
		str(size), SUB_LABEL_SPREAD, FS, th])
	var ok := true
	# ---- ⓪ 夹具的"预置选择"本身必须先断（2026-10-15b 新立）----
	#   ★★ 为什么这一段必须**排在最前**、而且是一条独立判据：
	#     下面所有几何判据都建立在这两句 `_auto_select()` **真的选中了那块瓷砖**之上。
	#     改名（本轮「人机」→「磐石」）之后，夹具里那句会静默不生效（旧实现只 `push_warning`）
	#     ⇒ **后面全都跑在一个不是想量的布局上，而且全绿**。
	#   ★ 这是**跨实现**的对拍（铁律 §13/§110 的正用法）：这里的字面量 `"磐石"` 是**独立参照物**
	#     —— 它模拟"截图脚本/人**按名字**去找那块瓷砖"，而瓷砖标签是从 `_mode_label()`/
	#     `MenuModel.mode_label()` 那条链生出来的。两边不同源 ⇒ 改名漏改一处就会分叉。
	#     ⚰️ 反例（本轮踩到后删掉的写法）：拿 `_mode_label(MODE_VS_AI)` 去比瓷砖自己的 label ——
	#     两边**同源**，改名时一起变 ⇒ **恒真**，砍了刀也不红（§110 的老坑换了个壳）。
	#   ★ 阴性对照**内建**（双向验证，不用外挂脚本）：一个必定不存在的名字必须**找不到**
	#     —— 否则"找到了"这件事可能是 `_auto_select()` 恒真。名字故意写成一句自我说明，
	#     好让那行 `push_warning` 在日志里一眼看出是**有意**的对照、不是故障。
	_set_page(PAGE_MAIN)
	var fix_hit: bool = _auto_select("彭罗斯") and _auto_select("磐石")
	var fix_miss: bool = not _auto_select("（阴性对照·这个名字必定不存在）")
	var c0: bool = fix_hit and fix_miss
	ok = c0 and ok
	print("[labeltest] ⓪ 夹具预置：彭罗斯+磐石命中·不存在名必落空 %s（命中=%s 落空=%s%s）" % [
		"✓" if c0 else "✗", str(fix_hit), str(fix_miss),
		"" if c0 else " · 瓷砖改名了？夹具的名字与 `_mode_label()` 那条链对不上"])
	_board_t = 1.0
	_layout_setup()
	ok = _spread_test_group("boardsize", Vector2.RIGHT) and ok
	# ★ 2026-10-09：这里原有 `_spread_test_group("diff", …)` —— 难度三档并入 `mode` 组，
	#   `diff` 组已不存在 ⇒ 对空集合的判据恒真 = 没测（铁律 4）。它要量的东西改由
	#   `_spread_test_group("mode", …)` 覆盖（对战方式行现在 5 块，间距最容易挤）。
	ok = _spread_test_group("mode", Vector2.ZERO) and ok
	# ★★ 2026-10-09：这里原有「场景1b 锚点标签避让」三条（`_anchor_avoid_test(...)`）
	#   —— 随"文字放进按钮内部"整族删除（标签不再挂在按钮外 ⇒ 没有东西可避让；
	#   判据若留着就是在量一个绘制端根本不用的位置，详见该函数处的删除说明）。
	# 场景1c：爱因斯坦（4 个字，棋盘行里最长的标签）+ 它的**种类行**（帽子/海龟/幽灵）。
	# 为什么单列一遍：① 棋盘行标签从 2~3 字变成 4 字，横向余量要重新量；
	# ② 这一项的二级行不是尺寸行而是种类行（见 _set_page）—— 同 group 换含义后，
	#    标签散布的几何是否仍然成立，必须拿它的实际标签量一次。
	_select_board(BOARD_HAT)
	_set_page(PAGE_MAIN)              # 落定待切换项 + 按新棋盘重建二级行（种种类行）
	_board_t = 1.0
	_layout_setup()
	ok = _spread_test_group("boardsize", Vector2.RIGHT) and ok
	# 场景2：彭罗斯 + 线上。★ 2026-09-30 §24 第 5 步：这一场景原有**三条**断言，
	#   `_spread_test_group("netmode", Vector2(-1,0))` / `_cross_group_gap("boardsize","netmode")` /
	#   `_anchor_avoid_test("mode","线上", …)`，逐条记明处置（**一删 / 一换组 / 一保留**）：
	#     · 联机方式那一行当时只剩 1 项（「随机匹配」已删）⇒ `_spread_test_group` 的
	#       pairwise 双重循环一次都不跑 ⇒ 返回恒真 —— **对空集合的判据 = 没测**（本工程老坑，
	#       与"标记没人看 = 假绿"同族）。**删除**，改成下面那条元判据。
	#     · `_cross_group_gap("boardsize", "mode")` **保留**：boardsize（棋盘行最右：随机/标准/加强）
	#       ↔ mode（对战方式行最左）—— 对角的这两组仍可能斜向相撞。
	# ★★ 2026-10-08：`_anchor_avoid_test("mode","线上", …)` 与"组内项数恒为 2"那条元判据
	#   随 netmode 两瓣整族删除（被测对象消失 ⇒ 判据同步摘，铁律 4 的同族纪律：
	#   **对空集合的判据 = 没测**；留着它只会恒真）。

	_set_page(PAGE_MAIN)
	_auto_select("彭罗斯")
	_board_t = 1.0
	_layout_setup()
	ok = _cross_group_gap("boardsize", "mode") and ok
	# ★★ 2026-10-08：这里原有三条**联机方式两瓣**的几何断言，随两瓣整族删除：
	#   `_spread_test_group("netmode", …)`（组内净间距）/ `_cross_group_gap("boardsize","netmode")`
	#   （跨行净距）/ `_label_vs_panel_test()`（两瓣标签 × 左侧浮层面板）。被测对象都没了。
	#   ⇒ 换成「对弈」页的布局判据：页内原生控件不越界 / 不压底栏 / 两档互斥 / 列表行排得下。
	#   这不是"同类判据换个名字"，而是**病灶搬了家**（浮层 → 页内容），判据必须跟着搬。
	ok = _duel_page_test() and ok

	# 场景3：行标题「棋盘」「对战方式」与各行瓷砖标签的纵向净空（多视口扫描）。
	# 为什么要专门测：瓷砖半径一旦放大，块的标签会向上顶进行标题所在的行（实测过直接叠在一起），
	# 而只比「折叠子项之间」的间距抓不到这类回归。
	# ⚠️ 循环行改动后的新前提：「棋盘」行标题**不再淡出**（选中项停在靠右的焦点位，离居中标题很远），
	#    所以这条断言现在对每一行都长期有效，不再是"展开态跳过"。
	ok = _section_label_test() and ok
	print("[labeltest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## ★★ 2026-10-09：这里原有 `_anchor_avoid_test()`（`--labeltest` [避让]）与它专用的
##   `_rect_btn_gap()`，**整族删除**。
##   ⚠️ 为什么必须删而不是"让它继续绿"：文字改画在**按钮内部**之后，绘制端已经不调
##   `_anchor_avoid_offset()` 了，而这条判据**自己还在调它** ⇒ 它量的是一个**屏幕上不存在
##   的标签位置**（把标签从按钮中心又挪走 52px）。这正是本工程记过账的那类假判据：
##   "判据绿/红"与"用户看到什么"之间没有任何关系（实际表现：文字进按钮当天它立刻报
##   3 处 ✗，而画面上一个字也没压到瓣上）。
##   ★ 它当年守的病归谁守：折叠展开改**浮层抽屉**（用户拍板）之后，抽屉不参与行布局，
##   压不到行内任何东西 ⇒ 由抽屉自己的判据守（抽屉在屏内、不压底栏、点外面能关）。
##   ⚠️ 名字**不许回收**：留个空位，免得下一个人去找一个不存在的"避让"。

## 自检（--portraittest）：菜单在**竖屏**下的布局判据。
##
## ★ 为什么这一侧必须用**真窗口**跑（不能 headless）：
##   headless 的物理窗恒为 1152×1152 正方，无论怎么设 `--resolution` 都改不动
##   （实测 `--resolution 720x1560` 被忽略），于是逻辑视口永远正方 —— **拿不到竖屏**。
##   ⚠️ 2026-10-02 更正：`_row_fit_test` 注释曾写"`size` 也改不动"，**实测是错的** ——
##   改**本节点自己的** `size` 在 headless 下**生效**（`_label_vs_panel_test()` 就靠它扫四档横屏视口，
##   量具 `--vpprobe`）。真正不行的是改**根 Window**（会把本节点挤成 1152×144）。
##   ⇒ 但**竖屏这一侧仍用真窗口**：它要验的是「画布基座是否真的切成 720×1560」，
##   那是 Autoload `apply_design_canvas()` 的事，只改本节点 `size` 绕过了基座、不算数。
##   所以：`menu.gd -- --portraittest` 必须配 `--winsize=720x1560`（regress.sh 里已如此）。
##   与之相对，game 侧的 HUD 分支只依赖谓词、与长宽比无关 → 那一半留在 headless。
##
## 判据（每条都要能把「删掉竖屏收敛」这件事抓出来）：
##   ① 真的在竖屏下跑（否则直接失败并给提示，避免"在横屏里测竖屏"这种假绿）
##   ② 行带高度**已经被收敛**（`_band_h` < 等分高度），且行带之间有间距
##   ③ 瓷砖半径**顶满宽度**（收敛不能以缩小瓷砖为代价 —— 那就是把问题换个方向）
##   ④ 所有瓷砖多边形都在视口内
##   ⑤ 行标题与瓷砖标签的净空（复用 `_section_label_test()` 的**同一套**判据，不另写一份）
##   ⑥ 阴性对照：谓词切回横屏后 `_layout_setup()` 必须回到等分（②必须变红）
func _portrait_self_test() -> void:
	var ok := true
	print("[portraittest] ===== 菜单竖屏布局自检 =====")
	var vs: Vector2 = get_viewport_rect().size
	# ① 真竖屏？
	var ok1: bool = vs.y > vs.x and GameConfig.use_portrait_canvas() \
		and get_window().content_scale_size == GameConfig.BASE_SIZE_PORTRAIT
	if not ok1:
		ok = false
	print("[portraittest] ① 真竖屏：视口=(%.0f,%.0f) 谓词=%s 基座=%s → %s" % [
		vs.x, vs.y, str(GameConfig.use_portrait_canvas()), str(get_window().content_scale_size),
		"通过 ✓" if ok1 else "失败 ✗（必须配 --winsize=720x1560 跑，headless 办不到）"])
	# ② / ③ / ④：跑一次真实布局，读它的产物
	_layout_setup()
	# ★★ 2026-10-16：「等分高度」改成**读真源** —— 原先这里自己拼了一遍算式
	#   `(vs.y − BOTTOM_MARGIN − 6 − (TOP_MARGIN + ROW_HEAD_TOP)) / 4`，它**漏了两项**：
	#   底部入口行带的高度、以及行与行之间那份显式行距 `ROW_ROW_GAP`。
	#   2026-10-16 把 ROW_ROW_GAP 从 10 拉到 14（用户口令「间距稍微拉大一点」）之后，
	#   那个手拼的"等分"与实际布局差了 34px ⇒ ⑥ 的阴性对照开始报红。
	#   ⚠️ 这正是本文件反复记过的那类坑："判据自己再推一遍几何" ⇒ 与屏幕画的对不上。
	#   ⇒ 改走 `_content_band_h(_footer_band_h())`（`_layout_setup()` 横屏那一支的同一份算式）。
	var equal_h: float = _content_band_h(_footer_band_h())
	var ok2: bool = _band_h < equal_h - 1.0 and _band_gap > 0.0
	if not ok2:
		ok = false
	print("[portraittest] ② 行带收敛：实际 %.0f vs 等分 %.0f，间距 %.0f → %s" % [
		_band_h, equal_h, _band_gap, "通过 ✓" if ok2 else "失败 ✗（竖屏没收敛=内容堆在上半屏）"])
	var by_w: float = vs.x * ROW_WIDTH_RATIO / ROW_SPAN
	# ③ 瓷砖**半径预算顶满宽度**（收敛不能以缩小瓷砖为代价 —— 那就是把问题换个方向）。
	#   ★★ 2026-10-16 改口径：原先量的是"内容行**多边形**的横向半宽 ≥ by_w"。
	#     棋盘行改静态平铺 + 五行统一尺寸之后，多边形的横向半宽是
	#     `max(r_base, 最宽标签所需半宽)` —— 竖屏 720 下「爱因斯坦」把半宽顶到 60，
	#     而 `by_w` 只有 52.7 ⇒ 判据被**标签宽度**喂饱：`r_base` 就算被缩一半它照样绿
	#     （它量的根本不是被收敛影响的那一半）。这是"判据看着在守 A、其实只守了 B"。
	#   ⇒ 改量 `r_base`：真源是 `_tile_base_r(_band_h)`，与 `_portrait_band_cap()` 用的是
	#     **同一支**（那里的收敛目标就是"让 `_tile_base_r(cap)` 顶到 `by_w`"）。
	#     顶不到 = 收敛没生效或把瓷砖缩小了 ⇒ 报红。
	var r_base_meas: float = _tile_base_r(_band_h)
	var ok3: bool = r_base_meas >= by_w - 0.5
	if not ok3:
		ok = false
	print("[portraittest] ③ 半径预算顶满宽度：r_base=%.2f（bandH=%.0f）宽度上限 %.2f → %s" % [
		r_base_meas, _band_h, by_w, "通过 ✓" if ok3 else "失败 ✗（收敛把瓷砖缩小了）"])
	# ④ 所有**真正会画出来**的瓷砖都在视口内（= 全部 `_items` 的 poly）。
	#   ⚰️ 改前棋盘行要先按 `_board_slots` 用「槽位中心 − 项心」平移出可见几何再量
	#      （理由：循环行的 poly 是记账值，可以落在窗口之外，量它会假越界 720.94/740.97）。
	#      静态平铺之后 poly 就是绘制几何 ⇒ 两段合成一段，棋盘行也一并进分母
	#      （**不是**把棋盘行排除掉：那等于静默丢掉 5 块的越界覆盖）。
	var outside: Array[String] = []
	for it in _items:
		var poly: PackedVector2Array = it.get("poly", PackedVector2Array())
		for p in poly:
			if p.x < -0.5 or p.y < -0.5 or p.x > vs.x + 0.5 or p.y > vs.y + 0.5:
				outside.append("%s/%s%s" % [str(it["group"]), it["label"], str(p)])
				break
	var ok4: bool = outside.is_empty()
	if not ok4:
		ok = false
	print("[portraittest] ④ 瓷砖均在视口内：%s → %s" % [
		"是" if ok4 else "; ".join(outside), "通过 ✓" if ok4 else "失败 ✗"])
	# ⑤ 净空：直接复用行标题 vs 瓷砖标签那条既有判据
	var ok5: bool = _section_label_test()
	if not ok5:
		ok = false
	print("[portraittest] ⑤ 行标题净空（复用 --labeltest [行带] 判据）→ %s" % [
		"通过 ✓" if ok5 else "失败 ✗"])
	# ⑥ 阴性对照：谓词切回横屏 → 必须回到等分高度（②那条判据要变红）
	var keep: int = GameConfig.portrait_override
	GameConfig.portrait_override = 0
	_layout_setup()
	var ok6: bool = not (_band_h < equal_h - 1.0 and _band_gap > 0.0)
	if not ok6:
		ok = false
	print("[portraittest] ⑥ 阴性对照（强制横屏→应回到不分档的等分 %.0f，实测 %.0f）→ %s" % [
		equal_h, _band_h, "通过 ✓" if ok6 else "失败 ✗（判据恒真，等于没有判据）"])
	GameConfig.portrait_override = keep
	_layout_setup()
	print("[portraittest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 行带纵向空间校验：行标题文字 vs 瓷砖标签文字，必须留出净空。
##
## ⚠️ 方法学（血泪教训，别再走弯路）：
## **不要在这个函数里重算几何**。前几版都是"用公式再算一遍应该在哪"，结果反复与实际不符：
##   · 自己拼常数而没引用 `BOTTOM_MARGIN`（曾按 46 算，实际值是当时的 56）→ bandH 算错；
##     现在该常量已由 56 改为 20（底部提示文案删除后回收给棋盘），常量值还会继续变，
##     所以这里只强调「必须引用常量」而不是记住某个数字；
##   · 漏掉 `_draw_label` 是**以文字中心**落位（不是左上角）→ 凭空少算半个字高，
##     把真机 36px 的净空算成 −29px "重叠"，白白返工好几轮；
##   · ~~想在 headless 里把 `size` 改成真机视口尺寸再跑布局 —— Godot 直接拒绝~~
##     **⚠️ 这条旧结论已被 2026-10-02 实测推翻，别再照着绕远路**：改**本节点自己的** `size`
##     在 headless 下**是生效的**（立刻回读得到目标值）；真正不行的是改**根 Window** 的 `size`
##     —— 那会把本节点挤成 1152×144。量具见 `--vpprobe`，反例见 `_label_vs_panel_test()`：
##     它正是靠"改自己的 size → `_layout_setup()` → 回读布局产物"扫四档视口的。
##
## 所以改为**回读布局产物**：直接在当前真实 size 下跑 `_layout_setup()`，
## 读 `_row_label_y` 与瓷砖实际 center/poly，比净空。算出来的位置就是画出来的位置。
## 视口差异通过 `vh` 参数显式传入只用于计算 bandH/字号档位，几何一律以布局实测为准。
func _row_fit_test(vw: float, vh: float, n_groups: int) -> bool:
	# 用真机逻辑视口推算该场景下的 bandH 与字号（仅用于报告口径）。
	# ⚠️ 起点口径必须与 `_layout_setup()` 逐字一致：那里是 `TOP_MARGIN + ROW_HEAD_TOP`，
	# **不是** `TOP_MARGIN + 26`。口径不一致会让自检报出一个屏幕上并不存在的 bandH，
	# 进而得出与真机相反的结论（踩过）。
	var top0: float = TOP_MARGIN + ROW_HEAD_TOP
	var bottom0: float = vh - BOTTOM_MARGIN - 6.0
	var band_h: float = (bottom0 - top0) / float(n_groups)
	# 必须在当前真实视口下重跑布局，保证读到的 center/poly 与绘制一致
	_layout_setup()
	# ★ band_h 只当「该场景若是等分」的参照；**真正用的**是布局刚记下的 `_band_h`（竖屏会收敛）。
	#   两者不一致时以 `_band_h` 为准，否则报告会显示一个屏幕上不存在的高度（踩过）。
	var f: Font = UITheme.body_font()
	var lbl_h: float = _font_h(TILE_LABEL_FS)
	var ok: bool = true
	print("[labeltest] [行带] 视口%.0f×%.0f 组数=%d bandH(实际)=%.0f（等分参考=%.0f）标题字号=%d 上方需%.0f 实测size=%s" % [
		vw, vh, n_groups, _band_h, band_h, _row_head_font_size(_band_h),
		_row_above_need(_band_h), str(size)])
	# 行标题实际落位：_draw_label 以文字**中心**落位，实参为 (size.x/2, sl["y"])。
	# 但真正绘制时用的是 _section_labels 里登记的 fs（可能与本场景推算的字号不同），
	# 故按实际登记的 fs 取字高。
	var fs_by_group := {}
	for sl in _section_labels:
		fs_by_group[sl["group"]] = int(sl.get("fs", 18))
	# ⚠️ 行数恒为 4（棋盘 / 大小 / 对战方式 / 开始；「开始匹配」按钮早已移除，没有 "net" 组）。
	#   ★ 2026-10-09：`boardsize` 独立成行 ⇒ 3 行变 4 行（`_row_count_test` 钉着它）。
	for g in ["board", "mode"]:
		if not _row_label_y.has(g) or not fs_by_group.has(g):
			continue
		var it_ref := {}
		for it in _items:
			if it["group"] == g and it["poly"].size() >= 3:
				it_ref = it
				break
		if it_ref.is_empty():
			continue
		var hfs: int = fs_by_group[g]
		var hh: float = _font_h(hfs)
		var head_cy: float = _row_label_y[g]
		var head_bottom: float = head_cy + hh * 0.5
		var lbl_cy: float = _tile_label_pos(it_ref["center"], it_ref["poly"],
			it_ref["label"], TILE_LABEL_FS, Vector2.ZERO).y
		var lbl_top: float = lbl_cy - lbl_h * 0.5
		var clear: float = lbl_top - head_bottom
		# 判据：净空 ≥ ROW_HEAD_CLEAR（不只是一句"不重叠"）。
		# 用"≥预留值"而不是"≥0"当红线，是为了让布局公式里的 ROW_HEAD_CLEAR 真的被守住 ——
		# 否则公式扣了 6px、实际只留 1px 也算"通过"，红线就形同虚设。
		var row_ok: bool = clear >= ROW_HEAD_CLEAR - 0.5
		if not row_ok:
			ok = false
		print("[labeltest] [行带]   %s 标题中心=%.0f 标题底=%.0f 标签顶=%.0f 净空=%.0f（需≥%.0f）%s" % [
			g, head_cy, head_bottom, lbl_top, clear, ROW_HEAD_CLEAR,
			"✓" if row_ok else "✗ 行标题压到瓷砖标签"])
	return _row_row_gap_test() and ok

## 相邻两行之间必须留出视觉间隙：上一行的**瓷砖下沿**（取该行所有块下沿的**最低者** ——
## 谁伸出去了就把谁算进去，是保守取法）与下一行的**行标题顶**（无标题的行则取其标签顶）
## 之间 ≥ ROW_ROW_GAP。
## ⚠️ 旧注释写的是「下底最高者，因为折叠瓣会向下伸」—— **两处都不对了**：
##   ① 折叠机制整族删除后没有瓣会伸出（理由消失）；
##   ② 代码取的是 `maxf(bot_y, bb.end.y)`，而 y 轴向下增 ⇒ 取到的是**最低**的那个下沿。
##   取法保留（保守），只是别再按旧注释去理解它。
##
## 为什么需要这条：`_row_fit_test` 只查「同一行内 行标题 vs 瓷砖标签」，
## 而实测出现过「开始」标签顶 484.7 恰好等于「本地」块底 484.7 —— 跨行零间隙，
## 屏幕上两块糊在一起，但同行的检查完全测不到。行带是等分的，这种"边界相切"
## 在改行数/改字号时非常容易撞上，必须单独钉一条。
func _row_row_gap_test() -> bool:
	var ok := true
	var f: Font = UITheme.body_font()
	var lbl_h: float = _font_h(TILE_LABEL_FS)
	# 收集各行实际占据的纵向区间：{组名: [上界, 下界]}
	var spans := {}
	# ★ 2026-10-09：`boardsize` 现在是**独立一行**（原先挂在棋盘行右侧折叠展开），
	#   两处行清单必须补上它 —— 不补的话这一行根本不进判据，行间贴住了也测不到。
	var rows := ["board", "boardsize", "mode", "action", "nav"]
	for g in rows:
		var it_ref := {}
		for it in _items:
			if it["group"] == g and it["poly"].size() >= 3:
				it_ref = it
				break
		if it_ref.is_empty():
			continue
		var top_y: float = 1e9
		var bot_y: float = -1e9
		# 横向区间（2026-10-02：行间判据要判"两行横向是否相交"，见下面 gap 那段）
		var min_x: float = 1e9
		var max_x: float = -1e9
		for it in _items:
			if it["group"] != g or it["poly"].size() < 3:
				continue
			# 标签（块上方）
			var lc: Vector2 = _tile_label_pos(it["center"], it["poly"], it["label"],
				TILE_LABEL_FS, Vector2.ZERO)
			top_y = minf(top_y, lc.y - lbl_h * 0.5)
			# 块本体下沿
			var bb := Rect2(it["poly"][0], Vector2.ZERO)
			for p in it["poly"]:
				bb = bb.expand(p)
			bot_y = maxf(bot_y, bb.end.y)
			min_x = minf(min_x, bb.position.x)
			max_x = maxf(max_x, bb.end.x)
		spans[g] = [top_y, bot_y, Rect2(min_x, 0.0, max_x - min_x, 1.0)]
	# 按布局顺序逐对比较（action 总在最后）
	var order: Array[String] = []
	for g in rows:
		if spans.has(g):
			order.append(g)
	# ★★ 必须按 **y 排序**再算相邻，而不是按 `rows` 数组顺序 —— 2026-10-02 起
	#   `nav`/`quick` 摆放在**右侧空白列**（y 在三行之上），而 `rows` 的书写顺序仍是
	#   board/mode/action/nav/quick ⇒ 按数组顺序算会得到 `action底 → nav顶` 这种
	#   **负间隙**（实测 -849），报红却与实际布局无关。⇒ 顺序必须由**几何**给出。
	order.sort_custom(func(a: String, b: String) -> bool:
		return float(spans[a][0]) < float(spans[b][0]))
	for i in range(order.size() - 1):
		var a: String = order[i]
		var b: String = order[i + 1]
		# ★★ 只在**两行横向区间真的相交**时才判行间间隙。
		#   2026-10-02 起 `nav`/`quick` 摆**右侧空白列**，而 board/mode/action 居中 ——
		#   两者横向不相交（`--labeltest` 的「标签互不重叠」五档 0 对已证），
		#   纵向贴在一起**无害**。首版不判横向就报 `nav底=279 → board顶=261 间隙=-18`，
		#   那条红与实际视觉重叠无关 —— **判据量错了对象**。
		var xa: Rect2 = spans[a][2]
		var xb: Rect2 = spans[b][2]
		var x_overlap: bool = (xa.position.x < xb.end.x) and (xb.position.x < xa.end.x)
		var gap: float = (float(spans[b][0]) - float(spans[a][1])) if x_overlap else 999.0
		# ★ 2026-10-09：这里原有 `or expanded`（board/mode 展开态不计行间间隙）—— 折叠机制
		#   整族删除后没有任何行会「伸出」行带 ⇒ 恒假的豁免 = 一条永远不咬人的判据
		#   （铁律 4：留恒真的闸 = 没闸）。行间间隙现在无条件生效。
		#   ⚠️ 本条注释原先**逐字写了两遍**（只差 "or " 两个字）—— 同一条结论写两处，
		#     改一处漏一处时留下的那份就会被当成“还没改过”的依据。已删重复的那份。
		var row_ok: bool = gap >= ROW_ROW_GAP - 0.5
		if not row_ok:
			ok = false
		print("[labeltest] [行间] %s底=%.0f → %s顶=%.0f 间隙=%.0f（需≥%.0f）%s" % [
			a, float(spans[a][1]), b, float(spans[b][0]), gap, ROW_ROW_GAP,
			"✓" if row_ok else "✗ 两行内容贴在一起"])
	return ok

## 每行都必须把该行的瓷砖真正摆好（poly 非空）。
## 为什么需要这条：`_layout_*_row` 都是「按名字找瓷砖」，一旦名字与建项处的 label 不一致，
## 函数会静默 `return`，瓷砖 poly 恒为空 → 绘制循环跳过 → 屏幕上该行**是空的**，
## 但程序不报任何错、其它自检也测不到（它们只比标签间距）。实测踩过：
## 布局函数写的是旧名 ["创建房间","加入房间","快速匹配"]，而瓷砖实际叫「开始匹配」，
## 于是整行长期空白，直到截图才发现。
func _row_tiles_test() -> bool:
	var ok := true
	# ★ 2026-10-09：`boardsize` 已是**独立一行**（原先挂在棋盘行右侧折叠展开），清单必须含它。
	#   ⚠️ 漏了它的后果**因判据而异**：本函数这一份漏了 ⇒ 该行的瓷砖**一个都不进检查**，
	#   布局函数名字写错、整行空着也照样绿 —— 那正是本函数存在的理由（见上面 docstring）。
	#   （`_row_row_gap_test` 里另有一份**同名但用途不同**的清单，那一份漏了 ⇒ 行间贴住也测不到。
	#     两份必须分别维护：合并成一份 = 一处改动同时影响两个判据，判据之间就失去独立性。）
	var rows := ["board", "boardsize", "mode", "action", "nav"]
	# 逐行检查：该行只要有 item，就必须全部完成布局（poly >= 3）
	for g in rows:
		var total := 0
		var laid := 0
		var bad_disabled := 0
		for it in _items:
			if it["group"] != g:
				continue
			if g == "board" and bool(it["disabled"]):
				# 仅棋盘行：禁用占位（「敬请期待」）不布局是**预期状态**（循环行只铺启用项，
				# 紧凑间距下窗口放不下占位块）；反而必须断言它没被摆位，防止占位块混进画面。
				# 其他行的禁用项（如线上模式下的「开始」按钮）仍会被布局、置灰绘制，必须正常计数。
				if it["poly"].size() >= 3:
					bad_disabled += 1
				continue
			total += 1
			if it["poly"].size() >= 3:
				laid += 1
		if total == 0:
			continue
		var row_ok: bool = laid == total and bad_disabled == 0
		if not row_ok:
			ok = false
		var why_pos := "✗ 有瓷砖未布局（名字对不上？该行会空白）"
		if bad_disabled > 0:
			why_pos = "✗ %d 个禁用占位被摆位（占位块不该出现在画面）" % bad_disabled
		print("[labeltest] [摆位] 行 %s：%d/%d 块已布局 %s" % [
			g, laid, total, "✓" if row_ok else why_pos])
	return ok

## 主菜单**行数必须是 4**（棋盘 / 大小 / 对战方式 / 开始），且不存在 "net" 行。
##
## 为什么钉这条：行数直接进 `_tile_base_r` 的纵向预算，行数一变整套净空全变 ——
## 若有人加/删一行却没同步 `_layout_setup` 的预算，屏幕上会立刻出现“行标题压住瓷砖
## 标签”，而同行/跨行的间距断言都是**按 4 行算的**，只会报症状、抓不到根因。
## ★ 沿革：4 → 3（移除「开始匹配」动作瓷砖）→ 4（2026-10-09「大小」单列一行）。
##   ⚠️ 这两个数**都曾经是对的**；本 docstring 曾长期写着“必须是 3”，引用它会得出反的结论。
##
## ★★ 下面 `row_groups` 里的 `"net"` **不是残留，是「禁用组探测器」（负向哨兵）**：
##   `row_groups`（待检查的组名）与 `expect`（期望出现的组名）是**两份不同的清单**，
##   断言是 `present == expect`；只要 `row_groups` 里多出任何一个在 `expect` 里没有的
##   组名，且它真的出现在 `_items` 里，`present` 就会比 `expect` 长 ⇒ 立刻红。
##   ⇒ 哪天又有人把「联机」做成主菜单的一行，这条哨兵立刻报红。
##   ⚠️ 千万别"顺手"删掉 `"net"`（哨兵消失、这条判据对“多出一行”就瞎了），
##     更别把两份清单合并成一份（那就成了恒真式，铁律 4）。
func _row_count_test() -> bool:
	var row_groups := ["board", "boardsize", "mode", "net", "action"]
	var present: Array[String] = []
	for g in row_groups:
		for it in _items:
			if it["group"] == g:
				present.append(g)
				break
	var expect: Array[String] = ["board", "boardsize", "mode", "action"]
	var ok: bool = present == expect
	print("[labeltest] [行数] 实际=%s 期望=%s %s" % [
		str(present), str(expect),
		"✓ 恒定 4 行" if ok else "✗ 行数变了，_layout_setup 的 bandH/半径预算需同步重算"])
	return ok

## 行标题（棋盘 / 对战方式）与瓷砖标签的纵向冲突检查。
## 只在「不展开折叠」的默认态测：展开时行标题会按进度淡出让位，属于预期行为。
## 不做像素框比较（headless 视口恒为 1152×1152，与真机 1152×720 不同源，会误报），
## 改用 _row_fit_test 的纯几何判据：按真机逻辑视口算 bandH 与 R，比纵向空间总和。
##
## ⚠️ 组数恒为 **4**（棋盘 / 大小 / 对战方式 / 开始）—— 就是下面三条 `_row_fit_test(…, 4)`
## 末位那个参数。见 `_layout_setup` 顶部的沿革与 `_row_count_test` 钉的那一份。
## 但仍保留多视口扫描 —— 行数固定不代表安全，bandH 随视口高度走，矮窗口照样能挤爆。
func _section_label_test() -> bool:
	var ok := true
	ok = _row_fit_test(1152.0, 720.0, 4) and ok    # 真机默认逻辑视口
	ok = _row_fit_test(1280.0, 800.0, 4) and ok    # 宽一点
	ok = _row_fit_test(1024.0, 640.0, 4) and ok    # 矮窗口：bandH 最小，最容易挤爆
	# ★★ 2026-10-16：这里原有 4 条 `_board_row_fit_test(vw, vh)` —— 那是**解析算**的轮播模型
	#   （焦点下限 `BOARD_FOCUS_MIN_RATIO`、簇右缘、最左块留白 ≥2R、整组居中）。棋盘行改
	#   **静态平铺**之后那一整套概念不存在，函数已删 ⇒ 换成 `_board_static_test(vp)`：
	#   它改 `size` → `_layout_setup()` → 量**真几何**（上屏数 / 等距 / 居中 / 不出屏）。
	#   ⚠️ 四条视口一个不少 —— "判据要跑在会出问题的那一档"（铁律 4）不因改口径而放宽。
	ok = _board_static_test(Vector2(1152.0, 720.0)) and ok
	ok = _board_static_test(Vector2(1280.0, 800.0)) and ok
	ok = _board_static_test(Vector2(1024.0, 640.0)) and ok
	ok = _board_static_test(Vector2(1920.0, 1080.0)) and ok   # 大屏：块变大 ⇒ 5 块平铺最考验横向预算
	ok = _row_align_test() and ok
	ok = _roster_vs_items_test() and ok
	ok = _row_tiles_test() and ok
	ok = _row_count_test() and ok
	ok = _board_static_test() and ok          # 当前（headless 1152×1152）这一档
	# ★ 2026-10-02：同组标签互不重叠。`labeltest` 已有十几条子测试（行带/行间/对齐/
	#   避让/循环行…），**唯独没有"同组两块挨太近"这一条** ⇒ 2026-10-02 加了 nav/quick
	#   两行带、纵向空间被压小后，棋盘循环行的标签叠成一团（放大截图实测），
	#   而 `labeltest` **全绿**。几何断言抓不到"看着糊"，得逐对量矩形。
	ok = _label_no_overlap_test() and ok
	return ok

## 同组内任意两个标签的矩形不得相交（>8px² 才算真叠，边缘擦碰不算）。
## ★ 为什么循环行要按**槽位**算而不是按 `_items` 算：同一块棋盘有多个重影，
##   用户看到的是那些重影上的标签（`_board_slots` 每项带 `i`/`center`/`alpha`）。
##   只按 `_items` 的原始 center 算 ⇒ 量的是"未投影的锚点"，与实际显示无关。
##   —— 与「自检走真实交互路径」同源：判据必须量**用户看到的那份几何**。
func _label_no_overlap_test() -> bool:
	var ok := true
	# ★★ 必须**多档扫描**（铁律 4：判据要跑在会出问题的视口那一档）。
	#   首版只量当前这一档 ⇒ 全绿，而实拍（1152×648 基座）里标签糊成一片：
	#   headless 视口恒 1152×1152（**正方**），而 1152×648 那个扁视口才挤得下问题。
	#   ⚠ 每档跑完**必须复原** `size`（扫多档后不复原会污染后续自检）。
	var vp_list := [Vector2(1152.0, 648.0), Vector2(1152.0, 720.0), Vector2(1024.0, 640.0),
		Vector2(1280.0, 800.0), Vector2(1920.0, 1080.0)]
	var size_save: Vector2 = size
	for vp in vp_list:
		ok = _label_no_overlap_one(vp) and ok
	size = size_save
	_layout_setup()      # 复原布局产物，别留上一档的坐标
	queue_redraw()
	return ok

## 某一档视口下的「同组标签互不重叠」检查（真跑布局，扫完由调用方复原 size）。
##
## ★★★ 2026-10-04 v4：**每一条标签矩形改走 `_label_ink_rect()`**（= 绘制那条链：
##   `_draw_fs_for()` 定字号 → `_label_pos_for()` 定位置 → 锚点避让）。原先这里是
##   **自己另算了一套**：字号读 `_label_font_size_for()`（漏掉 `_nav_label_fs` 的逐档下调）、
##   位置写成"块包围盒正上方 `-6.0 - 字高`"（而绘制端折叠子项是摆在块的**外侧**、
##   还要加放射散开与锚点避让）。
##   ⇒ 它量的是**屏幕上不存在的位置**：此前能全绿纯属巧合，本轮底栏改版后开始报 11 对
##   重叠 —— 逐条查下来**全是幽灵之间的重叠**，画面上一个字都没叠（`--labeltest` 的
##   间距判据与 `[标签×面板]` 判据读的是真几何，两档一起看就能分辨）。
##   ⚠️ 为什么这比"调参把重叠压下去"更该做：判据与绘制不同源时，
##   **判据的红绿与"用户看到什么"之间没有任何关系** —— 它既会假红（本轮）也会假绿
##   （`_draw_fs_for` 那次的"判据量 24、画 20"）。同源之后它才有牙齿。
##   ★ 几何口径与 `_draw()` 的 `draw_passes` 对齐：静止态下 `_rot_t == 0`、
##   折叠进度 1.0 ⇒ `draw_center = it["center"]`、`draw_poly = it["poly"]`。
##   ★★ 2026-10-16：棋盘行**不再有槽位**（静态平铺）—— 原先"棋盘行按 `_board_slots`
##   展开、其余组按 `_items`"这两段的差别整个消失，统一按 `_items` 走一次。
func _label_no_overlap_one(vp: Vector2) -> bool:
	size = vp
	_layout_setup()      # ★ 换档后**必须重跑布局**：布局产物是按 size 算的，
	#                     不重跑的话量的是上一档的坐标（读起来像"判据没测"）
	queue_redraw()
	var ok := true
	var boxes: Array = []      # {name:String, r:Rect2}
	# ★★ 2026-10-16：全部组**统一按 `_items`**（每块一次出现）。
	#   原先棋盘行要先按 `_board_slots` 展开槽位（同一块多次重现、各自 home 判据），
	#   棋盘行改静态平铺后 `_board_slots` 恒空 ⇒ 那一段一条也进不来 ⇒ 本判据的
	#   **样本集从 16 掉到 11**（棋盘行 5 块整个漏掉）却**照样打印 ✓**。
	#   ⇒ 下面末尾新增"样本数 == 上屏块数"那一条就是为它补的牙（范围缩了必须报红）。
	for it_n in _items:
		if (it_n["poly"] as PackedVector2Array).size() < 3:
			continue
		boxes.append({"name": "%s/%s" % [str(it_n["group"]), str(it_n["label"])],
			"r": _label_ink_rect(it_n, Vector2(it_n["center"]),
				it_n["poly"], _draw_fs_for(it_n), true)})
	var bad: int = 0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var ov: Rect2 = (boxes[i]["r"] as Rect2).intersection(boxes[j]["r"] as Rect2)
			if ov.size.x > 0.0 and ov.size.y > 0.0 and ov.size.x * ov.size.y > 8.0:
				bad += 1
				if bad <= 6:
					# ★ 打印**两个矩形本身**（不只叠了多少）：判据报红时"谁叠谁、往哪躲"
					#   是唯一下一步，只给一个面积等于把定位工作又推回给人。
					print("[labeltest] [标签互不重叠] %s 「%s」×「%s」✗（叠 %.0f×%.0f px）%s ∩ %s" % [
							str(vp), str((boxes[i] as Dictionary)["name"]),
							str((boxes[j] as Dictionary)["name"]), ov.size.x, ov.size.y,
							str(boxes[i]["r"]), str(boxes[j]["r"])])
	# ★★ 样本数守卫（2026-10-16 补）：判据的**范围**必须等于"屏幕上真的有几个块"。
	#   来历：棋盘行改静态、`_board_slots` 变空的那一版，本判据的样本集**静默**从 16 掉到
	#   11（棋盘行 5 块整个漏掉）却照样打印 ✓ —— 范围缩了而判据不会红（铁律 13 那一类）。
	#   ⇒ 直接拿 `_items` 里**已布局**的块数当分母，缺一个就报红并把两个数都打出来。
	var on_screen := 0
	for it_c in _items:
		if (it_c["poly"] as PackedVector2Array).size() >= 3:
			on_screen += 1
	var cnt_ok: bool = boxes.size() == on_screen
	if not cnt_ok:
		ok = false
	var why_o := "✗"
	if not cnt_ok:
		why_o = "✗ 样本集 %d ≠ 上屏 %d 块（判据范围缩了）" % [boxes.size(), on_screen]
	elif bad == 0:
		why_o = "✓"
	print("[labeltest] [标签互不重叠] %s %d 个标签矩形（上屏 %d 块）重叠 %d 对 → %s" % [
			str(vp), boxes.size(), on_screen, bad, why_o])
	return ok and bad == 0 and cnt_ok

## 各 group 的标签字号（**唯一真源**）。绘制与判据都读它。
## ★ 之前绘制侧是一句 `26 if action else 22`，判据侧压根不知道字号 ⇒ 两处各猜一次，
##   判据就算得不准（而它还算绿）。抽出函数后两边必须同源。
func _label_font_size_for(g: String) -> int:
	match g:
		"action": return 26
		# ★ 底栏四块（练习 / 棋谱 / 对弈 / 设置）都走这一档。
		#   ⚠️ 实际生效值走 `_draw_fs_for()` → `_nav_label_fs`（`_layout_footer_row()`
		#   会按区域宽度逐档下调）—— 这一支只提供**初始值**（它的第一个参数）。
		#   ★ 2026-10-04 v4：原来还有一个 `quick` 支（「练习」当初归在 `quick` 组，
		#   因为它是开关）。四块都归 `nav` 之后它没有消费者了 ⇒ 删掉。
		"nav": return 24
		_: return 22

## **全页所有行的瓷砖必须一样大**（2026-10-16 用户口令：「棋盘、大小、对战方式、开始按钮
## 都统一成现在棋盘行按钮的大小；底下一行高度也与上面统一」）。
##
## ★ 口径：**读布局产物**（`_uni_box` + 各行实际 `poly` 的包围盒），**不自己重算**。
##   重算就是"判据量 A、屏幕画 B"（铁律 31）—— 本文件在这一类上返工最多。
##   ⚠️ 分母含**底部入口行**（`nav`）：用户那句"底下一行"说的就是它。
##   ⚠️ 每行取**单块**尺寸而不是整组并集：多块并排时并集宽 = `n·2hw + (n−1)·gap`，
##     那是**行宽**不是**块宽**，拿它去比 `_uni_box["hw"]` 会得出"棋盘行 864 宽"这种荒唐结论。
func _row_align_test() -> bool:
	if _uni_box.is_empty():
		print("[labeltest] [等大] 布局产物 `_uni_box` 为空（未跑布局？）")
		return false
	var w_want: float = float(_uni_box["hw"]) * 2.0
	var h_want: float = float(_uni_box["hh"]) * 2.0
	var rows := ["board", "boardsize", "mode", "action", "nav"]
	var ok := true
	var bad: Array[String] = []
	var txt := ""
	for g in rows:
		var sz: Dictionary = _group_tile_size(g)
		var v: Vector2 = sz["size"]
		if int(sz["n"]) <= 0:
			ok = false
			bad.append("%s 未布局" % g)
			txt += "%s=— " % g
			continue
		if not bool(sz["uniform"]):
			ok = false
			bad.append("%s 组内不一致" % g)
		if absf(v.x - w_want) > 0.5 or absf(v.y - h_want) > 0.5:
			ok = false
			bad.append("%s=%.0f×%.0f" % [g, v.x, v.y])
		txt += "%s=%.0f×%.0f " % [g, v.x, v.y]
	print("[labeltest] [等大] 统一尺寸 %.0f×%.0f ｜ 实测 %s%s" % [
		w_want, h_want, txt,
		"✓ 五行同一尺寸（含底栏）" if ok else "✗ 不一致：%s" % ", ".join(bad)])
	return ok

## **行花名册 × 练习页真实建项** 逐行对数（2026-10-16 新增）。
##
## ★★ 为什么非有不可：`_uni_box` 的行花名册（`_main_row_roster()`）与 `_set_page(PAGE_MAIN)`
##   建的 `_items` 是**两份必须一致的清单** —— 花名册决定块宽 / 间距，`_items` 决定屏幕上
##   真的有哪几块。两处各记一份，改一处漏一处时**什么错都不会报**：
##   往花名册里多记一行 ⇒ `gap` 被压小（各行整体变窄）；漏记一行 ⇒ 底栏变宽。
##   症状全是"尺寸悄悄变样"，没有任何异常、也没有任何判据会红。
##   ⇒ 必须拿它们**互相对数**：练习页上按组现数 `_items`，与花名册**逐项**比（含组顺序）。
##
## ⚠️ 比的是**会上屏的块数**：棋盘行的禁用占位（「敬请期待①②」）不参与布局，
##   两侧都不该数它（花名册那边由 `_main_row_roster()` 现筛，这边按 `disabled` 现筛）。
##
## ⚠️ 只许在 `PAGE_MAIN` 上比：别的页 `_items` 本来就只有底栏那四块 —— 那是**设计如此**
##   （正是它逼着 `_uni_box` 不能用按页现数的花名册，见 `_main_row_roster()`）。
##   所以"不在练习页"不是可以静默跳过的情形，而是**前置条件不满足** ⇒ 报红。
func _roster_vs_items_test() -> bool:
	if _page != PAGE_MAIN:
		print("[labeltest] [花名册] ✗ 判据必须跑在练习页（当前 page=%d）—— 样本集为空，别静默跳过" % _page)
		return false
	var cnts: Array = _main_row_roster()["cnts"]
	var groups := ["board", "boardsize", "mode", "action", "nav"]
	var live: Array = []
	for g in groups:
		var n := 0
		for it in _items:
			if str(it["group"]) != g:
				continue
			if g == "board" and bool(it["disabled"]):
				continue
			n += 1
		live.append(n)
	var ok: bool = live == cnts
	print("[labeltest] [花名册] 统一尺寸的行块数：花名册=%s ｜ 练习页实测=%s %s" % [
		str(cnts), str(live),
		"✓ 逐行一致（组序：棋盘/大小/对战方式/开始/底栏）" if ok else
		"✗ 两处清单已分叉 —— 改 `_set_page(PAGE_MAIN)` 必须同步改 `_main_row_roster()`"])
	return ok

## 某组瓷砖的**单块**外形尺寸，附带「组内是否一致」与已布局块数。判据用（纯读，不改状态）。
func _group_tile_size(g: String) -> Dictionary:
	var sz := Vector2.ZERO
	var n := 0
	var uniform := true
	for it in _items:
		if str(it["group"]) != g:
			continue
		var poly: PackedVector2Array = it["poly"]
		if poly.size() < 3:
			continue
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			bb = bb.expand(p)
		if n == 0:
			sz = bb.size
		elif absf(bb.size.x - sz.x) > 0.5 or absf(bb.size.y - sz.y) > 0.5:
			uniform = false
		n += 1
	return {"size": sz, "n": n, "uniform": uniform}

## **棋盘行（静态平铺）**专项校验 —— 2026-10-16 取代原 `[循环行]` 段。
##
## 现在守五件事，**全部读真几何**（`_items` 的 `center` / `poly`），不引用任何解析模型：
##   ① **启用项全部上屏**（块数 == `_board_enabled_kinds().size()`，且每块 `poly` 非空）；
##   ② **每块只出现一次**（同 label 不重复）—— 这条正是"删掉滚动"的核心断言：
##      轮播时代同一块会在屏幕上出现多次（槽位 `k ≡ 序号 mod N`），那正是用户要去掉的；
##   ③ 相邻块**等距**（中心距 == `gap + 2·hw`，与统一尺寸真源 `_uni_box` 对账）；
##   ④ 整行**水平居中**（左右留白相等）；
##   ⑤ 两端**不出屏**（左顶点 ≥ 0、右顶点 ≤ 视口宽）。
##
## `vp` 给 `Vector2.ZERO` ⇒ 用当前视口；否则临时改 `size` 跑一遍布局再复原
## （与 `_label_no_overlap_one()` 同一手法 —— 多档扫描是铁律 4 的要求）。
func _board_static_test(vp: Vector2 = Vector2.ZERO) -> bool:
	var size_save: Vector2 = size
	if vp != Vector2.ZERO:
		size = vp
		_layout_setup()
	var ok := true
	var items_b: Array[Dictionary] = []
	for it in _items:
		if str(it["group"]) == "board" and not bool(it["disabled"]):
			items_b.append(it)
	var nk: int = _board_enabled_kinds().size()
	var laid := 0
	var labels: Array[String] = []
	var min_l := 1e9
	var max_r := -1e9
	for it2 in items_b:
		var poly: PackedVector2Array = it2["poly"]
		if poly.size() < 3:
			continue
		laid += 1
		labels.append(str(it2["label"]))
		var bb := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			bb = bb.expand(p)
		min_l = minf(min_l, bb.position.x)
		max_r = maxf(max_r, bb.end.x)
	# ① 全部上屏（注意同时要求 `items_b.size() == nk`：万一有启用盘**根本没建项**，
	#    只数 poly 是数不出来的 —— 那是"少了一块"的另一种形态）
	var all_laid: bool = laid == nk and items_b.size() == nk
	# ② 每块只出现一次
	var seen := {}
	var dup := ""
	for lb in labels:
		if seen.has(lb):
			dup = lb
		seen[lb] = true
	var once_ok: bool = dup == ""
	# ③ 等距 + ④ 居中 + ⑤ 不出屏（③④ 只对"≥2 块且都布局"才有意义）
	var pitch_ok := true
	var center_ok := true
	var pitch_txt := "—"
	if laid >= 2:
		var expect: float = float(_uni_box.get("gap", 0.0)) \
			+ 2.0 * float(_uni_box.get("hw", 0.0))
		for k2 in range(1, laid):
			var step: float = Vector2(items_b[k2]["center"]).x \
				- Vector2(items_b[k2 - 1]["center"]).x
			if absf(step - expect) > 0.5:
				pitch_ok = false
		pitch_txt = "%.1f（期望 %.1f）" % [
			Vector2(items_b[1]["center"]).x - Vector2(items_b[0]["center"]).x, expect]
		center_ok = absf(min_l - (size.x - max_r)) <= 0.5
	var inside_ok: bool = min_l >= -0.5 and max_r <= size.x + 0.5
	var why := "✓"
	if not all_laid:
		why = "✗ 只有 %d/%d 块上屏（棋盘行会有空洞）" % [laid, nk]
	elif not once_ok:
		why = "✗ 同屏出现重复块「%s」（滚动没删干净）" % dup
	elif not pitch_ok:
		why = "✗ 相邻块不等距（%s）" % pitch_txt
	elif not center_ok:
		why = "✗ 整行没居中"
	elif not inside_ok:
		why = "✗ 有块出屏（x %.0f..%.0f / 视口宽 %.0f）" % [min_l, max_r, size.x]
	if not (all_laid and once_ok and pitch_ok and center_ok and inside_ok):
		ok = false
	print("[labeltest] [棋盘行] 视口%.0f×%.0f 上屏=%d/%d 相邻块距=%s x=%.0f..%.0f %s" % [
		size.x, size.y, laid, nk, pitch_txt, min_l, max_r, why])
	# 复原：`vp` 为 ZERO 时 `size_save == size`，这一句是空操作（但必须无条件写，
	# 否则将来有人加分支时会漏掉复原 —— `_label_no_overlap_test` 在这一处有先例）
	size = size_save
	if vp != Vector2.ZERO:
		_layout_setup()
		queue_redraw()
	return ok

## 当前排版下某瓷砖标签的绘制中心（展开完成态，fold_progress=1，供自检口径统一）。
func _label_now(it: Dictionary) -> Vector2:
	var oc: Vector2 = it["center"]       # netmode 两瓣已删（原用大菱形中心）
	return _label_pos_for(it, it["center"], 22)

## 量化某折叠子项组（boardsize / diff / netmode）的标签净间距：
## new = 当前放射散开排版，old = 不加散开（仅统一平移 old_dir 方向）。
## 组内的 pairwise 净间距 = max(水平净空, 垂直净空)；≥ 8px 视为不挤压。
## ★★ 标签 × 联机面板控件 碰撞判据（2026-10-01 新增，为目检发现的缺陷而补）。
## 缺陷回顾：加「联机大厅」第二瓣后，它的标签（纯向左排布）与**左侧联机面板**的说明文字
##   「Steam 房间号（建房后在对局界面显示）」**叠印成一串**（`--shotpage=netmode` 目检实测，
##   视口 y≈463..485 文字连成一片）。单瓣时代不撞（上瓣 y≈399，面板那行 y≈462）。
## 为什么必须机器判据：`--labeltest` 其余三条量的是"标签 vs 标签""块 vs 块"，
##   而联机面板是**原生 Control 子树**、**不参与瓷砖几何** ⇒ 叠上去时全部几何断言照样全绿。
##   这是"只有看图能发现 ⇒ 就得给它一条判据"的典型（与 `--shotpage=settings` 同族）。
##
## ★★★ **必须多视口扫，否则判据没有牙齿**（2026-10-02 实测，这是本条最重要的一处）：
##   headless 视口恒为 **1152×1152（正方）**，而叠印发生在**实机 1152×648（扁窗）** ——
##   正方视口下折叠簇的行中心高、标签带靠内，**算出来是不撞的**。实测同一份代码：
##     1152×648  ⇒ 标签带最左 x=278、面板 x=329.9（勉强让开）
##     1280×800  ⇒ 标签带最左 x=172、面板 x=224.3
##     1024×640  ⇒ 标签带最左 x=224、面板 x=275.8
##   单视口（1152×1152）跑出来全绿，而用户真机那一档是叠的 ⇒ **判据跑不到病灶 = 没测**。
##   而"headless 改不动视口"这条**旧注释是错的**（`_row_fit_test` 方法学里写着）——
##   实测（`_vp_probe()` 量具）：**直接改本节点自己的 `size` 是生效的**且立刻回读得到；
##   改根 Window 反而会把本节点挤成 1152×144（那才是真的不行）。方法学因此改成
##   "改自己的 size → `_layout_setup()` → **回读布局产物**"，与 `_row_fit_test` 同源。
##   ⇒ 本函数扫多档视口，每档重跑布局再量 —— 几何一律以布局实测为准，不重算公式。
##
## 口径：取面板里**有文字的**子控件（Label/LineEdit/Button）与两瓣标签求矩形**相交**，
##   交叠面积 > 8px² 才算真叠（边缘 1~2px 的擦碰看图也读不出来）。
## ★★ **必须把面板自身的位置加上**（`ctrl.position` 是**面板内局部坐标**，而标签位置是
##   **全屏坐标**）—— 漏了这一句，交集恒为空、判据变成**恒真式**（打不动）。
##   这是本条判据首跑就踩的：注掉修复后它**照样全绿**，正是铁律 4 的当场验证。
## 面板可见性门控：不可见/未建时**明说跳过、不计红**（自动化运行不建它）。
## ★ 扫完必须**复原** `size` 并重跑布局，否则后面的判据（场景3 等）会拿着被改小的视口跑。
## 多档视口清单（**共用**：对弈页布局判据 `_duel_page_test` 逐档扫它）。
## ★ 只在 headless 那一档验的做法在本工程栽过不止一次：headless 视口恒 1152×1152 **正方**，
##   而布局缺陷多半在扁/宽视口才现形（铁律 4：判据要跑在会出问题的那一档）。
const LABEL_PANEL_VIEWPORTS: Array[Vector2] = [
	Vector2(1152.0, 648.0),   # 真机横屏基座
	Vector2(1280.0, 800.0),
	Vector2(1024.0, 640.0),   # 矮窗口：页内容最挤
	Vector2(1920.0, 1080.0),  # 大屏：页最宽，行排版也要过
]


## 大厅列表行的**排版夹具**（判据与截图共用）：三种长度 + 无战绩那一档。
## ★ 为什么必须是这几个样本：它们各自压一个边界 —— 长昵称（换行/省略号）、
##   普通昵称、无战绩（`record == ""` ⇒ 显示「胜率 —」）。只喂等长样本等于没测。
const LOBBY_ROW_FAKE: Array = [
	["一个名字很长的陌生对手", "50%（1胜1负）"],
	["玩家丙", ""],
	["Steam游客_12345678", "0%（0胜3负）"],
]

func _duel_page_test() -> bool:
	var keep_page: int = _page
	var keep_net: int = _sel_netmode
	var keep: Vector2 = size
	var ok := true
	var seen: int = 0
	for vp in LABEL_PANEL_VIEWPORTS:
		size = vp
		# ★ 换视口必须**重建**：页根尺寸由 `size` 反解（`offset_bottom` 读底栏真源），
		#   只改 `size` 不重建的话量的还是旧尺寸的容器（"改了视口却量到旧几何"）。
		_set_page(PAGE_LOBBY)
		_layout_setup()
		var fb: Rect2 = _footer_band()
		for tier in DUEL_TAB_ORDER:
			_sel_netmode = tier
			_refresh_duel_tabs()
			seen += 1
			ok = _duel_page_one(vp, fb, tier) and ok
	# ★ 复原三件（视口 / 页 / 档位）：扫描改了 `size`，不复原会让**后面所有判据**跑在被改过的
	#   视口上（静默污染，本工程在旧槽位判据里就是这么写的）。
	size = keep
	_sel_netmode = keep_net
	_set_page(keep_page)
	if keep_page == PAGE_LOBBY:
		_refresh_duel_tabs()
	# ⚠️ 样本数必须 = 视口数 × 档数：恒空的样本集会让这条判据**恒真**（铁律 13⑨）。
	var want_seen: int = LABEL_PANEL_VIEWPORTS.size() * DUEL_TAB_ORDER.size()
	var all_ok: bool = ok and seen == want_seen
	print("[labeltest] [对弈页] %d 档视口 × %d 档 = %d 次校验（期望 %d）%s" % [
		LABEL_PANEL_VIEWPORTS.size(), DUEL_TAB_ORDER.size(), seen, want_seen,
		"✓ 全部合格" if all_ok else "✗ 至少一处不合格"])
	return all_ok

## 单视口单档位：四件事（由 `_duel_page_test` 逐档调用）。
func _duel_page_one(vp: Vector2, fb: Rect2, tier: int) -> bool:
	var ok := true
	if _duel_root == null or not is_instance_valid(_duel_root):
		print("[labeltest] [对弈页] %s 档=%s 页根未建 ✗" % [str(vp), _netmode_label(tier)])
		return false
	# ── ① 页内容**让开底栏**（纵向）：下沿必须**等于真源**，且不越过底栏上沿 ──────────
	#   量"等于真源"而不是"小于某阈值"：后者在把页根改小一截时照样绿（而那正是"内容缩了"的坏法）。
	var root_bottom: float = _duel_root.position.y + _duel_root.size.y
	var want_bottom: float = _duel_panel_bottom()
	if absf(root_bottom - want_bottom) > 0.5:
		ok = false
		print("[labeltest] [对弈页] %s 页根下沿 %.1f ≠ 真源 %.1f ✗（页内容没让开底栏）" % [
			str(vp), root_bottom, want_bottom])
	if root_bottom > fb.position.y + 0.5:
		ok = false
		print("[labeltest] [对弈页] %s 页根下沿 %.1f 压到底栏上沿 %.1f ✗" % [
			str(vp), root_bottom, fb.position.y])
	# ── ② 页内控件（**递归**，含滚动区里的列表行）不越页右沿 ─────────────────────────
	#   ★ 必须递归：列表行在 ScrollContainer → VBox → HBox 三层之下，只看直接子控件的话
	#     恰好漏掉"「加入」被顶出右沿"这一族（旧判据 ④ 记过同一笔账）。
	var over := _panel_max_child_right(_duel_root, 0.0, "")
	var over_r: float = float(over["right"])
	if over_r > _duel_root.size.x + 0.5:
		ok = false
		print("[labeltest] [对弈页] %s 控件右沿 %.1f > 页内宽 %.1f ✗（%s）" % [
			str(vp), over_r, _duel_root.size.x, str(over["who"])])
	# ── ③ 互斥：本档的块可见（另一档不可见），且两个切换块的按下态与本档一致 ─────────
	var want_lobby: bool = tier == NET_LOBBY
	var vis_ok: bool = _duel_lobby_box.visible == want_lobby \
			and _duel_invite_box.visible == (not want_lobby)
	var tabs: Dictionary = _duel_tab_state()
	var tab_ok: bool = bool(tabs.get(tier, false))
	for other in DUEL_TAB_ORDER:
		if other != tier and bool(tabs.get(other, true)):
			tab_ok = false
	if not (vis_ok and tab_ok):
		ok = false
		print("[labeltest] [对弈页] %s 档=%s 互斥 ✗ 联机块可见=%s 大厅块可见=%s 按下态=%s" % [
			str(vp), _netmode_label(tier), str(_duel_invite_box.visible),
			str(_duel_lobby_box.visible), str(tabs)])
	# ── ④ 大厅列表行排版（只在公开大厅档有意义）：最长昵称 + 无战绩两档都排得下 ──────
	if want_lobby:
		var scr := _lobby_list_box.get_parent() as ScrollContainer
		if scr == null:
			ok = false
			print("[labeltest] [对弈页] %s 列表容器没有滚动父节点 ✗" % str(vp))
		else:
			_clear_lobby_list()
			for e in LOBBY_ROW_FAKE:
				_lobby_list_box.add_child(_make_lobby_row_shot(String(e[0]), String(e[1])))
			# ★★ 判据必须量**这一帧就正确**的那个量：本页是容器布局（VBox/HBox/ScrollContainer），
			#   而 Godot 的容器排序是**延迟**的 ⇒ 同一帧里 `scr.size` 还是 0。
			#   （旧实现能拿 `scr.size` 当判据，是因为旧代码**手工** `_fit_lobby_panel_children()`
			#    把尺寸设好了 —— 那套手工排版已随浮层删除，判据的口径也得跟着换。）
			#   ⇒ 基准取**页内宽**（`_duel_root.size` 由 anchors/offsets 立即算出，① 已证），
			#     再夹上列表自己的内容列宽上限（`DUEL_LIST_W`）并扣掉垂直滚动条余量。
			var avail_w: float = maxf(40.0,
				minf(DUEL_LIST_W, _duel_root.size.x) - DUEL_SCROLLBAR_ALLOW)
			var wide := 0.0
			for c in _lobby_list_box.get_children():
				var row := c as Control
				if row == null:
					continue
				var need: float = row.get_combined_minimum_size().x
				wide = maxf(wide, need)
				if need > avail_w + 0.5:
					ok = false
					print("[labeltest] [对弈页] %s 行最小宽 %.0f > 可用宽 %.0f ✗（「加入」会被顶出右沿）" % [
						str(vp), need, avail_w])
			print("[labeltest] [对弈页] %s 档=公开大厅：%d 行夹具 最宽行 %.0f ≤ 可用宽 %.0f（页内宽 %.0f − 滚动条 %.0f）%s" % [
				str(vp), LOBBY_ROW_FAKE.size(), wide, avail_w, _duel_root.size.x,
				DUEL_SCROLLBAR_ALLOW, "✓" if wide <= avail_w + 0.5 else "✗"])
			_clear_lobby_list()
	return ok

func _panel_max_child_right(node: Node, best: float, best_name: String,
		off: float = 0.0) -> Dictionary:
	for c in node.get_children():
		var ctrl := c as Control
		if ctrl == null or not ctrl.visible:
			continue
		var r: float = off + ctrl.position.x + ctrl.size.x
		var nm := str(ctrl.get_class())
		# Label / Button 带上文字：读日志时能认出是哪一行被顶出去了
		if ctrl is Label:
			nm = "%s「%s」" % [nm, str((ctrl as Label).text)]
		elif ctrl is Button:
			nm = "%s「%s」" % [nm, str((ctrl as Button).text)]
		if r > best:
			best = r
			best_name = nm
		var sub := _panel_max_child_right(ctrl, best, best_name, off + ctrl.position.x)
		if float(sub["right"]) > best:
			best = float(sub["right"])
			best_name = str(sub["who"])
	return {"right": best, "who": best_name}

func _spread_test_group(group: String, old_dir: Vector2) -> bool:
	var f: Font = UITheme.body_font()
	const FS := 22
	var th: float = f.get_ascent(FS) + f.get_descent(FS)
	var names: Array[String] = []
	var widths: Array[float] = []
	var now: Array[Vector2] = []
	var old: Array[Vector2] = []
	for it in _items:
		if it["group"] != group:
			continue
		names.append(it["label"])
		widths.append(f.get_string_size(it["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
		now.append(_label_now(it))
		old.append(_tile_label_pos(it["center"], it["poly"], it["label"], FS, old_dir))
	var ok := true
	for i in names.size():
		for j in range(i + 1, names.size()):
			var d: Vector2 = now[j] - now[i]
			var gap_new: float = maxf(absf(d.x) - (widths[i] + widths[j]) * 0.5, absf(d.y) - th)
			var d0: Vector2 = old[j] - old[i]
			var gap_old: float = maxf(absf(d0.x) - (widths[i] + widths[j]) * 0.5, absf(d0.y) - th)
			var good: bool = gap_new >= 8.0
			if not good:
				ok = false
			print("[labeltest] [%s] %s↔%s 净间距 %.1f px（旧排版 %.1f px）%s" % [
				group, names[i], names[j], gap_new, gap_old, "✓" if good else "✗ 仍太挤"])
	return ok

## 跨组净间距：验证两组标签之间不重叠（用户关注点：联机方式文字在左侧、不与上方大小菜单撞）。
## 任意两标签文字框净间距 = max(水平净空, 垂直净空)；≥ 8px 视为不相交。
func _cross_group_gap(g1: String, g2: String) -> bool:
	var f: Font = UITheme.body_font()
	const FS := 22
	var th: float = f.get_ascent(FS) + f.get_descent(FS)
	var a: Array[Dictionary] = []
	var b: Array[Dictionary] = []
	for it in _items:
		if it["group"] == g1:
			a.append(it)
		elif it["group"] == g2:
			b.append(it)
	var ok := true
	for ia in a:
		for ib in b:
			var pa: Vector2 = _label_now(ia)
			var pb: Vector2 = _label_now(ib)
			var wa: float = f.get_string_size(ia["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
			var wb: float = f.get_string_size(ib["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x
			var d: Vector2 = pb - pa
			var gap: float = maxf(absf(d.x) - (wa + wb) * 0.5, absf(d.y) - th)
			var good: bool = gap >= 8.0
			if not good:
				ok = false
			print("[labeltest] [跨组] %s↔%s 净间距 %.1f px %s" % [
				ia["label"], ib["label"], gap, "✓" if good else "✗ 重叠"])
	return ok

## 供 --select=<标签> / 目检夹具按标签预置菜单状态。
##
## ★ 2026-10-15b：返回值从 `void` 改成 `bool`（**命中与否**）—— 原先"没找到"只 `push_warning`，
##   而 `push_warning` 在 `--headless` 日志里与正常输出混在一起，**没人看**。改名（本轮「人机」→
##   「磐石」）之后，夹具里那句 `_auto_select("人机")` 会静默不生效 ⇒ 量到的布局不是想量的那个、
##   截出来的图也不是要审的那个状态，**而日志一片干净**。⇒ 把"命中与否"变成可断言的返回值，
##   由调用方（`_label_spacing_test`）当场断掉。CLI 那一侧仍只警告 —— `--select=` 是调试口，
##   写错名字不该让整轮截图失败（但会打一行 warning 供人读）。
func _auto_select(label: String) -> bool:
	var hit := Callable()
	for it in _items:
		if it["label"] == label:
			hit = it["cb"]
			break
	if hit.is_valid():
		hit.call()
		return true
	push_warning("--select=%s：未找到同名瓷砖" % label)
	return false

## 以 center 为「文字视觉中心」绘制一行文字（水平居中）。
##
## ⚠️ 曾经写的是 `draw_string(f, center - Vector2(sz.x/2, sz.y/2), ...)` —— 错的：
## draw_string 的 origin 是**基线**，不是文本框左上角。按 sz/2 偏移会让文字整体上浮
## 约 0.5*(ascent-descent) ≈ 3px，且 y 方向少算半个字高，
## 于是"行标题名义上在 164，实际画在 138"（真机截图实测差 25.4px）。
## 后果不只是观感：**自检按名义位置算净空会得出与真机相反的结论**
## （实测真机净空 +23.6px，自检却报 −12px 重叠），白查好几轮。
## 正确做法是按 ascent/descent 补偿基线（与 _draw_label_centered 同口径）。
func _draw_label(text: String, center: Vector2, color: Color, font_size: int) -> void:
	var f: Font = UITheme.body_font()
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# 基线 = 视觉中心 + (ascent - descent)/2，这样 ascent 与 descent 对称分布于中心两侧
	var baseline := center.y + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2(center.x - tw * 0.5, baseline),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## ★★ 2026-10-09：这里原有 `_poly_half_w()` 与 `_anchor_avoid_offset()`（锚点标签避让位移），
##   **整族删除**。为什么删而不是"留着备用"：
##   ① 它们的**唯一消费者**是"标签挂在按钮外面"那套几何 —— 文字改画在**按钮内部**之后
##      （用户口令），标签就落在自己那块按钮的中心，按钮之间又不重叠 ⇒ **没有任何文字在按钮外**
##      ⇒ "谁压谁的字"这个问题结构性不存在，避让量也就没有东西可避。
##   ② 留着就是**恒真的闸**：`--labeltest` 的 [避让] 断言当时还在自己调它，于是判据量的是
##      一个**绘制端根本不用的位置**（绿/红与用户看到什么无关）—— 本工程这条纪律已记过账。
##   ⚠️ 名字**不许回收**（`_gear_*` / `_back_*` 那一族的口径）：留个空位比"用旧名装别的东西"好。
##   ⚠️ 它当年守的那个病（"折叠瓣压住锚点标签"）现在的归处：折叠展开改**浮层抽屉**之后，
##      抽屉不参与行布局 ⇒ 压不到任何东西；这一点由抽屉自己的判据守。

## 以 center 为「文字视觉中心」绘制瓷砖标签。
## draw_string 的 origin 是字体基线（不是文本框左上角），这里按 ascent/descent 精确补偿，
## 否则文字会整体上浮约 0.85 个行高、压在瓷砖边缘线上。
func _draw_label_centered(text: String, center: Vector2, color: Color, font_size: int) -> void:
	var f: Font = UITheme.body_font()
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (f.get_ascent(font_size) - f.get_descent(font_size)) * 0.5
	draw_string(f, Vector2(center.x - sz.x * 0.5, baseline),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## ★★ 标签绘制中心 —— **唯一真源**（绘制与每条判据都必须读它，不许各处各摆一次）。
##
## 2026-10-09 用户口令「把文字放到按钮里面」：位置 = 这块按钮的中心（`draw_center`）。
##
## 旧口径**整条作废**：文字挂在按钮**外面**（其余按钮放在上顶点之上、折叠子项挂在展开侧外侧），
## 还要按 `SUB_LABEL_SPREAD` 放射散开、按 `_anchor_avoid_offset()` 避开二级菜单。
## 那一套是给**菱形**设计的 —— 菱形四个角是空的，外挂的文字从尖角旁边蹭得过去；
## 换成实心的圆角矩形后，任何外挂文字都会被相邻按钮压住（`--menutest` ⑩g 实测报 2 处，
## 为它加的"锚点避让"那一整套正是这份代价）。
##
## ⇒ 文字进到按钮内部之后，"谁压谁的字"这个问题**结构性消失**：
##   标签在自己的按钮里，而按钮之间互不重叠（⑤c 守）⇒ 按钮外根本没有文字可压。
## ⚠️ 因此那几个"外挂几何"的量（`LABEL_GAP` / 放射散开 / 锚点避让）**必须删**而不是留着 ——
##   留着就是"恒真的闸"，下一个人会以为外面还有东西要守（本工程这条纪律已记过账）。
##
## ⚠️ 未使用的形参以 `_` 开头（GDScript 约定：不报未使用），**签名留到清理那一轮再收窄** ——
##   现在收窄要一次改 13 处调用点，而这一轮的重点是把"文字进按钮"的几何先跑通、先量到。
func _label_pos_for(_it: Dictionary, draw_center: Vector2, _font_size: int) -> Vector2:
	return draw_center

## 同上（旧名 `_tile_label_pos`，判据侧仍在用）—— 真源与说明见 `_label_pos_for()`。
func _tile_label_pos(draw_center: Vector2, _poly: PackedVector2Array,
		_text: String, _font_size: int, _dir: Vector2) -> Vector2:
	return draw_center


# ====== 跳转 / 动作 ======
# ★ 2026-10-02：这里原有 `_toggle_settings()`（齿轮的"翻面"回调：主菜单↔设置页）。
#   齿轮删除后它**没有任何调用者**了 —— 留着的症状是"看起来页面对切还有个统一入口"，
#   实则两条路早已分开：
#     · 进设置 = 头部四入口的 `nav`「设置」（`_set_page(PAGE_SETTINGS)`）；
#     · 回练习面板 = 底栏那颗「练习」（`_set_page(PAGE_MAIN)`）。
#       ★ 2026-10-04 v4：设置页右上角那块棋盘按钮与页内那颗原生「返回主菜单」都已删除
#         —— 底栏四块常驻在四个面板上（`_footer_entry_descriptors()`），回去的路就在眼前。
#   ⇒ 整函数删除。**名字不许回收**：它表达的是"同一块控件翻面"，而现在根本没有那块控件。

# ★★ 2026-09-30 §24 第 5 步：这里原有 `_auto_create_room()`（联机邀请好友时**自动建房**，
#   起本地信令服务器 + 开一个房间 + 把 6 位邀请码写到左侧面板），以及它的闸
#   `_ensure_invite_room()`、两个状态位 `_host_room_created` / `_no_auto_room`
#   （后者是自检夹具：自检不许真的起 node 服务器）。**整组删除**，理由：
#     · 它们全部服务于**自建信令服**（`Matchmaking.create_room` + `matchmaking_server.js`）；
#     · Steam 侧的房间号是 `createLobby()` 的**异步回调**给的，而且建房发生在**对局场景**
#       （`SteamTransport.start()` → `lobby_ready` → `game.gd::_on_steam_lobby_ready()`），
#       菜单这一侧**没有 lobby 可建** ⇒ 自动建房在 Steam 下本来就被 `if not is_steam` 跳过。
#   ⇒ 顺带消失的还有两个副作用面：菜单不再可能拉起 node.exe、
#     自检也不再需要"禁止自动建房"的夹具（那个夹具连同它守的 `--steamuitest` 判据 ⑱ 已删）。

## 「进入对局」按钮：Steam 建房并进入（第 5 步后只剩这一条通道）。
## ★ 这里**不做任何网络动作**就进对局 —— 建房发生在对局场景的 `SteamTransport.start()`，
##   房间号随后由 `lobby_ready` 回调回填到**对局 HUD**（菜单侧看不到它）。
##   对局侧唯一真源：`game.gd::_on_steam_lobby_ready()`。
func _host_enter_game() -> void:
	# ★ Steam 建房前必须确认真的能用：插件缺失 / Steam 没开 / 没登录，都在这一道闸挡住，
	#   失败给 toast 并**留在菜单** —— 绝不"进对局之后才发现"（那时玩家已离开菜单，提示看不到）。
	#   第 5 步删掉通道按钮后，这道闸是**唯一**的降级拦截点（原先是"按钮 disabled + 这里的闸"两层）。
	if not SteamNet.ensure_init():
		_show_error_toast("Steam 不可用：%s" % SteamNet.reason())
		return
	GameConfig.online = true
	GameConfig.is_host = true
	GameConfig.mode = MODE_ONLINE
	# 房主侧房间号恒为 0（由 `createLobby` 的异步回调给出）；顺手清掉上一局残留，
	# 免得 UI 上还挂着那串**已经失效**的旧号（"量具说谎"比空着更坏）。
	GameConfig.steam_lobby = 0
	_push_board_choice()     # ★ 通道在这一处落进 `GameConfig.net_channel`（所有开局路径的唯一必经点）
	Transition.change_scene("res://game.tscn")

## 联机：输入房间号加入（Steam 大厅 id，执白）。
## ★★ 2026-09-30 §24 第 5 步：这里原是铁律 7 的样板 —— 同一个输入框承载"中继邀请码 / 对方 IP"
##   与"Steam 房间号"两种语义，所以回调必须**点击时现判**（`if _sel_channel == CHAN_STEAM`）。
##   自建联机删除后只剩一种语义 ⇒ 分派消失；但那半边纪律没有失效：
##   校验顺序仍必须是 **格式 ⇒ 环境 ⇒ 落参数 ⇒ 请求转场**（顺序错就会留下"参数写脏了但
##   没进对局"的静默状态），这一点由 `--steamuitest` 守着。
func _start_join() -> void:
	var txt := _ip_edit.text.strip_edges()
	if txt == "":
		_show_error_toast("请输入房间号")
		return
	_steam_join_by_id(txt)

## Steam 加入：输入的是**房间号**（`lobby_id`，纯数字，形如 `109775243422783190`）。
## ★ 校验必须严：输错一位就会去一个**不存在的房间**干等，而 Steam 那边**不会报错**
##   —— 症状是"永远等不到人"，没有任何提示。宁可在这里挡住并把格式说清楚。
## ★ 也不吞掉"看起来像邀请码"的输入（6 位字母数字是中继的格式）：直接报格式错，
##   不做任何"猜测通道"的自动回退（自动回退 = 静默改写玩家意图）。
func _steam_join_by_id(txt: String) -> void:
	var s := txt.strip_edges()
	if not s.is_valid_int():
		_show_error_toast("Steam 房间号应是纯数字（例：109775243422783190）")
		return
	var lid := int(s)
	if lid <= 0:
		_show_error_toast("Steam 房间号必须大于 0")
		return
	if not SteamNet.ensure_init():
		_show_error_toast("Steam 不可用：%s" % SteamNet.reason())
		return
	GameConfig.online = true
	GameConfig.is_host = false
	GameConfig.steam_lobby = lid
	GameConfig.mode = MODE_ONLINE
	_push_board_choice()
	Transition.change_scene("res://game.tscn")

# ====== 好友邀请落地（2026-10-21）======
## 用户口令「在游戏里直接点击就能召唤 steam 邀请好友窗口邀请好友对弈」的**入站一半**。
## 发出去那一半在对局 HUD（`game.gd::_on_invite_pressed` → `SteamNet.open_invite_dialog`）。
##
## 好友点「接受」之后，Steam 有两条路把房间号送到我们手里：
##   ① 程序没开 ⇒ Steam 用 `+connect_lobby <id>` 拉起本程序
##      ⇒ `SteamNet.ensure_init()` 里解析 → 发 `steam_join_requested`，同时留在 `_pending_join`
##   ② 程序开着（停在菜单）⇒ Steam 触发 `join_requested` → `SteamNet` 转发同一个信号
## ⇒ **两条路都汇到 `_on_steam_join_requested()`**，只写一处（否则总有一条会漏 = 静默不联动）。
##
## ★★ 为什么必须**主动 ensure_init()**：`SteamNet` 是刻意惰性的（当年不给 200+ headless 自检
##   引入 Steam 依赖）。但"能被好友邀请"要求 Steam 一直在跑、`run_callbacks` 一直在泵，
##   否则 `join_requested` 永远不会触发。⇒ 这里在**真运行**时提前拉起来。
##   · 自动化/headless 一律跳过（`_is_automated_run()` + `DisplayServer`）—— 自检不该依赖 Steam。
##   · 回退口 `--nosteam`（用户偏好：新系统必须有一条一键关掉的路）：
##     跑 `瓷砖围棋.exe -- --nosteam` 则完全不初始化，代价是收不到好友邀请。
func _bootstrap_steam_invites() -> void:
	if _is_automated_run() or DisplayServer.get_name() == "headless":
		return
	if "--nosteam" in _argv():
		print("[menu] --nosteam：跳过 Steam 初始化（本次收不到好友邀请）")
		return
	if not SteamNet.steam_join_requested.is_connected(_on_steam_join_requested):
		SteamNet.steam_join_requested.connect(_on_steam_join_requested)
	if not SteamNet.ensure_init():
		# ★ 明说而不是静默：Steam 没起来时"邀请好友"这一整条路都不通，
		#   玩家需要知道原因（第二台机器上就是这个症状）。
		print("[menu] Steam 未就绪（好友邀请不可用）：", SteamNet.reason())
		return
	var lid: int = SteamNet.take_pending_join()
	if lid != 0:
		print("[menu] 检测到「被邀请启动」：lobby=", lid, " ⇒ 直接进局")
		_join_lobby(lid)


## 运行时好友接受邀请 / 从 Steam 好友列表点「加入游戏」⇒ 直接进局。
## ★ 已经在对局里时**不抢**：进局要切场景，会把当前对局丢掉。只在菜单侧处理。
## ★ `lobby_id <= 0` 一律忽略（`join_requested` 在异常情况下可能给出 0）。
func _on_steam_join_requested(lobby_id: int, friend_id: int) -> void:
	if lobby_id <= 0:
		return
	if GameConfig.online:
		print("[menu] 已在对局中，忽略好友加入请求 lobby=", lobby_id, " friend=", friend_id)
		return
	# 与「启动参数」那条路互斥：消费掉 pending，免得同一个邀请进两次局。
	SteamNet.take_pending_join()
	print("[menu] 好友邀请进局：lobby=", lobby_id, " friend=", friend_id)
	_join_lobby(lobby_id)


# ★★ 2026-09-30 §24 第 5 步：**从这里到本段末尾、共约 240 行**全部删除，组成是：
#     `_join_by_code()`            ← 凭 6 位邀请码向自建信令服取房主端点（ENet 直连）
#     `_start_match()`             ← 快速匹配：进自建信令服的撮合队列
#     `_show_matchmaking_overlay()`  ← 「匹配中…」覆盖层（含取消按钮）
#     `_hide_matchmaking_overlay()`
#     `_reset_netmode_to_invite()` ← 匹配失败/取消后把联机方式复位（见 `_select_mode` 的说明）
#     `_cancel_matchmaking()`      ← 覆盖层「取消」
#     `_netmode_state_test()`      ← `--netmodetest` 自检（整个状态机就是为随机匹配建的）
#   共同点：**全部以自建信令服为前提**（`Matchmaking.*` 出现的每一处都在这里或 `_auto_create_room`）。
#   ★ 注意 `_join_by_code()` 删除的**连带**：`_looks_like_code()`（判"输的是邀请码还是 IP"）
#     也随之无人引用，一并删除 —— 否则会留下一个"看着有用、其实没有任何入口"的函数
#     （GDScript 不会报未使用函数，静默残留）。

## 自检（--einsteintest）：爱因斯坦（帽子家族）那一槽位的**种类行**语义。
##
## 为什么必须单独钉一遍：它是全菜单**唯一一处「同一个 group 承载两种含义」**的地方 ——
## 普通棋盘的二级行是「大小三档（随机/标准/加强）」，爱因斯坦的是「种类三档（帽子/海龟/幽灵）」，
## 两者共用 group="boardsize"、共用同样 3 个槽位、身份也都靠 size_id 匹配。
## 于是有三件事一旦漏掉，症状都很难查：
##   ① 标签不同步换 → 整行已经是「帽子/海龟/幽灵」，字却还写着「随机/标准/加强」；
##   ② 选中态用错数据源（_sel_size vs _sel_hatkind）→ 选中态停在错误的那一瓣；
##   ③ 开局没把种类推给 GameConfig → **菜单看着选了海龟，进游戏却是帽子随机盘**。
## 三件都是纯状态，headless 下可以精确断言，不用截图。
func _einstein_kind_test() -> bool:
	var ok := true
	_set_page(PAGE_MAIN)

	# 0) 这一槽位已改名为「爱因斯坦」（旧名「帽子」不再出现在棋盘行里）
	var lbl: String = _board_label(BOARD_HAT)
	var c0: bool = lbl == "爱因斯坦"
	ok = c0 and ok
	print("[einsteintest] 0) 棋盘槽位名=%s（期望 爱因斯坦）%s" % [lbl, "✓" if c0 else "✗"])

	# 1) 选爱因斯坦 → 二级行必须是种类三档，且顺序与 HAT_KINDS 一致
	_select_board(BOARD_HAT)
	_set_page(PAGE_MAIN)
	var want: Array[String] = []
	for k in HAT_KINDS:
		want.append(String(k["label"]))
	var labs: Array[String] = _boardsize_labels()
	var c1: bool = labs == want
	ok = c1 and ok
	print("[einsteintest] 1) 爱因斯坦的二级行=%s（期望 %s）%s"
		% [str(labs), str(want), "✓" if c1 else "✗ 尺寸行没换成种类行"])

	# 2) 逐瓣点选：凹陷态 / 菜单状态 / 推给 GameConfig 的三件套必须一起对
	for i in HAT_KINDS.size():
		var kid: int = int(HAT_KINDS[i]["id"])
		var klbl: String = String(HAT_KINDS[i]["label"])
		_select_hatkind(kid)
		_push_board_choice()
		var stone_ok: bool = _selected_boardsize_label() == klbl
		var state_ok: bool = _sel_hatkind == kid
		# ★ 尺寸必须被强制成「随机」：爱因斯坦只做随机盘，否则它会继承用户上次在别的棋盘上选的档
		var cfg_ok: bool = GameConfig.board_type == BOARD_HAT and GameConfig.hat_kind == kid \
			and GameConfig.board_size == GameConfig.RANDOM
		var ci: bool = stone_ok and state_ok and cfg_ok
		ok = ci and ok
		print("[einsteintest] 2) 点「%s」→ 凹陷态=%s(%s) 菜单状态(%s) | GameConfig 种类=%d 尺寸=随机(%s) %s"
			% [klbl, _selected_boardsize_label(), "✓" if stone_ok else "✗",
				"✓" if state_ok else "✗", GameConfig.hat_kind,
				"✓" if GameConfig.board_size == GameConfig.RANDOM else "✗",
				"✓" if ci else "✗"])

	# 2b) ★★ 真实点击路径（**不重建页面**）—— 用户实际踩到的就是这条，之前漏测。
	#     `_set_page` 只在启动/切页时跑一次；用户点棋盘类型只走 `_refresh_selection()`，
	#     所以「先在普通棋盘下把行建出来 → 再切到爱因斯坦 → 再点三瓣」必须单独验。
	#     修好前实测：标签确实换成了帽子/海龟/幽灵，但回调还是 `_select_size`
	#     → 点三瓣毫无反应（`_sel_hatkind` 永不变、凹陷态停在帽子）；
	#     反向切回普通棋盘时槽位 1/2 还留着「海龟/幽灵」。
	#     ⚠️ 自检同步跑在 `_ready` 里，`_process` 还没跑过 → 手工把折叠进度置成「已展开」的
	#     稳态（= 用户看到的状态），否则 `_tile_at_point` 会被 `_board_t` 门槛挡下。
	_sel_board = BOARD_PENROSE
	_board_pending = -1
	_sel_hatkind = GameConfig.HAT_HAT
	_sel_size = GameConfig.STANDARD
	_set_page(PAGE_MAIN)                 # 行按「普通棋盘」建：回调是本文件里的大小三档
	_select_board(BOARD_HAT)             # 只切棋盘（走 _refresh_selection，**不重建页面**）
	_commit_board_pending()              # 切换落定（等价于收回 + 滑行 + 展开跑完）
	_board_t = 1.0
	_board_target = 1.0
	_layout_setup()
	var want_h: Array[String] = []
	for k in HAT_KINDS:
		want_h.append(String(k["label"]))
	var lanes_h: Array[String] = _boardsize_labels()
	var c2b: bool = lanes_h == want_h
	var click_log: Array[String] = []
	for i in HAT_KINDS.size():
		var kid2: int = int(HAT_KINDS[i]["id"])
		var klbl2: String = String(HAT_KINDS[i]["label"])
		if not _click_boardsize_slot(kid2):
			c2b = false
			click_log.append("%s:点不到" % klbl2)
			continue
		var step_ok: bool = _sel_hatkind == kid2 and _selected_boardsize_label() == klbl2
		if not step_ok:
			c2b = false
		click_log.append("%s→凹陷态%s" % [klbl2, _selected_boardsize_label()])
	# 反向：切回普通棋盘（同样**不重建页面**）→ 三档标签不许残留「海龟/幽灵」，
	# 且点中间那槽要真的选到「标准」（同一条真实点击链）。
	_select_board(BOARD_PENROSE)
	_commit_board_pending()
	_board_t = 1.0
	_board_target = 1.0
	_layout_setup()
	var want_s: Array[String] = ["随机", "标准", "加强"]
	var lanes_s: Array[String] = _boardsize_labels()
	var back_ok: bool = lanes_s == want_s
	if back_ok:
		back_ok = _click_boardsize_slot(GameConfig.STANDARD) and _sel_size == GameConfig.STANDARD and _selected_boardsize_label() == "标准"
	c2b = c2b and back_ok
	ok = c2b and ok
	print("[einsteintest] 2b) 真实点击路径（不重建页面）：爱因斯坦二级行=%s 逐瓣点击=%s | 切回彭罗斯二级行=%s 点「标准」后凹陷态=%s %s"
		% [str(lanes_h), str(click_log), str(lanes_s), _selected_boardsize_label(),
			"✓" if c2b else "✗ 行语义与回调不同步"])
	# 3) 切回普通棋盘：二级行要换回大小三档，且选中源换回 _sel_size（不是 _sel_hatkind）
	_sel_size = GameConfig.ENHANCED           # 故意停在「加强」，看它能不能被正确回显
	_select_board(BOARD_PENROSE)
	_set_page(PAGE_MAIN)
	var want2: Array[String] = ["随机", "标准", "加强"]
	var labs2: Array[String] = _boardsize_labels()
	var sel2: String = _selected_boardsize_label()
	_push_board_choice()
	var c3: bool = labs2 == want2 and sel2 == "加强" \
		and GameConfig.board_size == GameConfig.ENHANCED and GameConfig.board_type == BOARD_PENROSE
	ok = c3 and ok
	print("[einsteintest] 3) 切回彭罗斯：二级行=%s 凹陷态=%s | 推给 GameConfig 的尺寸=%d（应仍是加强）%s"
		% [str(labs2), sel2, GameConfig.board_size, "✓" if c3 else "✗"])

	# 4) 阴性对照：把 _sel_hatkind 设成表里没有的 id（模拟「表与状态不同步」）
	#    → 标签必须**回退成「帽子」而不是空串**（空串会让瓷砖标签整块消失，且不容易被发现），
	#      且**没有任何一瓣被标成选中**（证明选中态是按 id 精确匹配，不是"反正有 3 瓣就黑一块"）。
	#    另外 game.gd 侧对未知种类也必须安全降级成帽子几何（`_hat_kind_lengths()` 的 `_` 分支）。
	_sel_hatkind = 99
	_select_board(BOARD_HAT)
	_set_page(PAGE_MAIN)
	var labs_bad: Array[String] = _boardsize_labels()
	var all_named: bool = labs_bad.size() == HAT_KINDS.size()
	for s in labs_bad:
		if s == "":
			all_named = false
	var no_stone: bool = _selected_boardsize_label() == ""
	var fallback_ok: bool = _hat_kind_label(99) == "帽子"
	var ctl: bool = all_named and no_stone and fallback_ok
	ok = ctl and ok
	print("[einsteintest] 4) 阴性对照（种类 id=99 不在表里）：标签=%s 无空串(%s) 无一瓣选中(%s) 名字回退=%s(%s) %s"
		% [str(labs_bad), "✓" if all_named else "✗", "✓" if no_stone else "✗",
			_hat_kind_label(99), "✓" if fallback_ok else "✗", "✓" if ctl else "✗"])

	_sel_hatkind = GameConfig.HAT_HAT       # 复原，别把自检里的坏状态留给后续
	print("[einsteintest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()
	return ok

## 自检 --lastmatchtest：「上一局选项」的 **落盘 → 读回 → 应用到菜单状态** 闭环。
##
## 为什么要它 —— 这条链上有四处**静默**失败点，全都不会抛错、只会悄悄错：
##   ① ConfigFile 的 section/key 名写错 → 读回全丢（症状：回菜单永远回默认，日志一片干净）；
##   ② 过期记录（某盘下线后换编号、旧 id 还留在文件里）被照单全收 → 菜单去画一个
##      "不存在的选项"，选中态画不出也点不着；
##   ③ 越界脏数据（文件被手改）直接塞进选择状态 → 大小档/种类/难度落在线外；
##   ④ 落盘没有守卫 → 自检/截图用的临时选择被写进用户配置（污染真实状态）。
##
## 文件往返走**独立路径**（`user://lastmatch_selftest.cfg`），绝不碰用户的 last_match.cfg；跑完删掉。
func _last_match_test() -> bool:
	var ok := true
	const TEST_PATH := "user://lastmatch_selftest.cfg"

	# 1) 文件往返：**六个**字段逐一比对（section / key 名任一写错都会在这里现形）
	#    ★ 2026-10-15 加第 6 个 `xg`：**必须给非零值** —— 给 0 的话"写进去了"与"压根没写"
	#      读回来一样都是 0 ⇒ 判据瞎（§106「有效分母」在字段级的样子）。
	#    ★ 2026-10-15b 并列化：**字段格式一个字节都没变**（本段就是这条的守卫）——
	#      `mode=VS_AI` + `xg=1` 仍是"上一局选了疾风"的唯一写法，哨兵 100 不许进文件。
	var want := {
		"board": BOARD_SNOWFLAKE, "size": GameConfig.ENHANCED,
		"hat_kind": GameConfig.HAT_SPECTRE, "diff": DIFF_HARD, "mode": MODE_VS_AI, "xg": 1,
	}
	# ★ 六个参数全部显式 `int(...)`：`want` 是 Dictionary ⇒ 读出来是 Variant，
	#   不包的话静态检查会把它当 `String` 而报
	#   「Invalid argument for save_last_match(): argument 6 should be int but is String」
	#   （2026-10-14 实测：`--lastmatchtest` 直接 Parse Error ⇒ exit=124 卡到超时）。
	GameConfig.save_last_match(int(want["board"]), int(want["size"]), int(want["hat_kind"]),
		int(want["diff"]), int(want["mode"]), int(want["xg"]), TEST_PATH)
	var back: Dictionary = GameConfig.load_last_match(TEST_PATH)
	var same: bool = back.size() == want.size()
	for k in want:
		if int(back.get(k, -999)) != int(want[k]):
			same = false
	ok = same and ok
	print("[lastmatchtest] 1) 文件往返：写=%s｜读=%s %s" % [str(want), str(back), "✓" if same else "✗ 键名/类型不一致"])

	# 2) 应用：一份合法记录要**一字不差**落到菜单的**四项**选择状态上
	#    ⚰️ 2026-10-12：原先是**五项**（多一个难度档）。难度整族删除后菜单里没有这个状态，
	#      记录里的 `diff` 字段**显式不采纳**（见 `_apply_last_match()` 的墓碑）。
	#      ⚠️ 下面**故意不**断"难度被采纳" —— 那正是要被禁掉的写法
	#      （它会把「磐石恒最难」变成"上一局是什么就是什么"）。
	_sel_board = BOARD_PENROSE
	_sel_size = GameConfig.STANDARD
	_sel_hatkind = GameConfig.HAT_HAT
	_sel_mode = MODE_LOCAL
	# ★ 2026-10-15：疾风档（`xg`）转正 ⇒ 它也要**一字不差落到状态上**。
	# ★★ 2026-10-15b 并列化：它**不再是第 5 项独立状态** —— 合并进 `_sel_mode` 那一项
	#   （`_sel_xgai` 已退役）。所以本段的期望值从`VS_AI 且 xgai`变成 **`_sel_mode == MODE_XGAI`**。
	#   ⚠️ 哨兵方向仍然要**相反**（这里期望 MODE_XGAI ⇒ 先设 MODE_LOCAL）——
	#     不设的话上一段残留的值会让断言**恒真**（"看着断住了、其实没测"）。
	#   ⚠️ 这同时是**旧记录兼容**的守卫（铁律 §111）：记录里 `mode=VS_AI` + `xg=1` 是
	#     并列化**前后完全一样**的写法 ⇒ 恢复出来的东西必须仍是"疾风档"。
	var applied: bool = _apply_last_match(back)
	var hit: bool = applied and _sel_board == BOARD_SNOWFLAKE \
		and _sel_size == GameConfig.ENHANCED and _sel_hatkind == GameConfig.HAT_SPECTRE \
		and _sel_mode == MODE_XGAI
	ok = hit and ok
	#    ⚠️ 判据行的 ✗ **必须出现在第一个全角括号之前**：阴性对照仪判"哪条红了"靠的是
	#      `line.split("（")[0].endswith("✗")`（S26 同族的运行时口径）——
	#      把 ✗ 写在括号**后面**的判据，刀砍下去也不会被认成红。本行原版就是那个写法，
	#      2026-10-15b 顺手改成 `名字 ✗（明细）`。
	print("[lastmatchtest] 2) 应用：四项状态一字不差落上 %s（采纳=%s 棋盘=%s 大小档=%d 种类=%d 对战方式=%d=%s · 难度不采纳）" % [
		"✓" if hit else "✗", str(applied), _board_label(_sel_board), _sel_size, _sel_hatkind,
		_sel_mode, _mode_label(_sel_mode)])

	# 3) 阴性对照（每条都必须被挡住）。每条都先把四项状态设成**与坏记录全都不同**的哨兵值，
	#    这样"只应用了一半"也会被抓到（只比其中一个字段是抓不住的 —— 那种断言等于没写）。
	#    a) 棋盘 id 已不存在（-1 是「敬请期待」占位 id）→ 整份作废，四项状态一个都不许动
	_sel_board = BOARD_PENROSE
	_sel_size = GameConfig.RANDOM
	_sel_hatkind = GameConfig.HAT_HAT
	# ★ 2026-10-15b：哨兵改成 `MODE_XGAI` —— 并列化之后它就是"第四档"这个**最难被误改的值**
	#   （坏记录里写的是 MODE_VS_AI，若"作废"那道闸漏了，`_sel_mode` 会被写成 VS_AI ⇒ 当场红）。
	#   ⚰️ 改前这里靠 `_sel_xgai = true` 来钉同一件事，那个成员已退役。
	_sel_mode = MODE_XGAI
	var rejected: bool = not _apply_last_match({"board": -1, "size": GameConfig.ENHANCED,
		"hat_kind": GameConfig.HAT_TURTLE, "diff": DIFF_HARD, "mode": MODE_VS_AI})
	var untouched: bool = _sel_board == BOARD_PENROSE and _sel_size == GameConfig.RANDOM \
		and _sel_hatkind == GameConfig.HAT_HAT and _sel_mode == MODE_XGAI
	var c3a: bool = rejected and untouched
	ok = c3a and ok
	print("[lastmatchtest] 3a) 棋盘 id 已下线：拒绝=%s 四项状态全未动=%s %s" % [
		str(rejected), "✓" if untouched else ("✗ 状态被改动"), "✓" if c3a else "✗"])
	#    b) 越界脏数据 → 夹回合法区间（大小档→加强、种类→幽灵、对战方式→本地），不是照抄
	#       ⚠️ 脏记录里仍带 `"diff": 99`：夹取那一半在 `MenuModel.restore_state()` 里照旧要做
	#          （手机菜单还有难度行、被 `--mtest` 钉着），而**桌面菜单不采纳它**。
	#          本条顺带断"一个越界的 `diff` 不会把整份记录丢掉"。
	#    ★ 2026-10-15b：这份脏记录**故意不带 `xg`** ⇒ 顺带钉住"旧格式/缺字段的纪录
	#      **不会被误认成疾风档**"（铁律 §111：新式必须能在旧工况下退化成旧式）。
	#      期望 `MODE_VS_AI`（记录里 `mode=1`、无 `xg` ⇒ 磐石，**不是**疾风）。
	var clamped: bool = _apply_last_match({"board": BOARD_KITE, "size": 99,
		"hat_kind": 99, "diff": 99, "mode": 1})
	var c3b: bool = clamped and _sel_board == BOARD_KITE and _sel_size == GameConfig.ENHANCED \
		and _sel_hatkind == GameConfig.HAT_SPECTRE and _sel_mode == MODE_VS_AI
	ok = c3b and ok
	print("[lastmatchtest] 3b) 越界脏数据被夹回 %s（大小=%d 种类=%d 对战方式=%d · 缺 xg ⇒ 磐石非疾风）" % [
		"✓" if c3b else "✗", _sel_size, _sel_hatkind, _sel_mode])
	#    c) 对战方式=线上 → 必须退回「本地」（恢复线上会在菜单一打开就建房/进排队队列）
	#    ⚠️ 记录里那个 `diff` 字段**仍要写**（文件格式没变、手机菜单还在读写它），
	#      只是桌面菜单不采纳它 ⇒ 用当前唯一在用的那一档。
	var c3c: bool = _apply_last_match({"board": BOARD_KITE, "size": GameConfig.STANDARD,
		"hat_kind": GameConfig.HAT_HAT, "diff": DIFF_HARD, "mode": GameConfig.ONLINE}) \
		and _sel_mode == MODE_LOCAL
	ok = c3c and ok
	print("[lastmatchtest] 3c) 上一局是「线上」→ 必须退回本地 %s（恢复成对战方式=%d 期望=%d）" % [
		"✓" if c3c else "✗ 会把菜单带进联机状态", _sel_mode, MODE_LOCAL])
	#    d) 空记录（首次运行）→ 不采纳
	var c3d: bool = not _apply_last_match({})
	ok = c3d and ok
	print("[lastmatchtest] 3d) 空记录（首次运行）：不采纳=%s %s" % [str(c3d), "✓" if c3d else "✗"])
	#    e) ★ 2026-10-15b 新增：`xg=1` 时**只看 `xg`、不看 `mode`** ——
	#       `mode=LOCAL` + `xg=1` 是自相矛盾的 cfg（正常写法下 `xg=1` 必然配 `mode=VS_AI`，
	#       哨兵外泄才会出现别的组合），手改文件才写得出。口径与"恢复线上"那类**危险**不同：
	#       疾风本来就是 AI 档，恢复它不会在打开菜单时产生任何副作用（不会建房/不会进队列），
	#       所以采纳 `xg` 是安全的；反过来若采纳 `mode`，症状是"上局明明是疾风，回来变本地"
	#       —— 静默且要玩一局才发现。
	#       ⚠️ 哨兵先设成 **`MODE_VS_AI`**（不是 MODE_LOCAL）—— 这样"两边都没被写"也会被抓到。
	_sel_mode = MODE_VS_AI
	var c3e: bool = _apply_last_match({"board": BOARD_KITE, "size": GameConfig.STANDARD,
		"hat_kind": GameConfig.HAT_HAT, "diff": DIFF_HARD, "mode": GameConfig.LOCAL, "xg": 1}) \
		and _sel_mode == MODE_XGAI
	ok = c3e and ok
	print("[lastmatchtest] 3e) xg=1 压过 mode=本地 %s（对战方式=%d 期望=%d 疾风 · 手改文件才有的组合）" % [
		"✓" if c3e else "✗ 口径与 `_apply_last_match()` 的注不符", _sel_mode, MODE_XGAI])

	# 4) 守卫：本次就是自动化运行 → 恢复与落盘都必须被跳过（自检绝不读写用户配置）。
	#    这条同时是 `_is_automated_run()` 的**阳性探针**：把匹配规则写坏（例如漏掉 `--*test*`）
	#    这里立刻报红，而不是等到某天发现自检结果依赖用户的上一局。
	var guard: bool = _is_automated_run()
	ok = guard and ok
	print("[lastmatchtest] 4) 自动化运行守卫：本次带 --lastmatchtest → 必须为真（不恢复/不落盘）%s"
		% ["✓" if guard else "✗ 守卫失效，自检会污染用户配置"])

	# 4b) **写点兜底闸**（2026-09-29）：自动化运行下，对**真路径**发起写必须被拦下（不落盘）。
	#     `GameConfig.save_last_match()` 里那道闸是兜底用的 —— 现有两个调用点各自都套了
	#     `if not _is_automated_run():`，但"两处都记得"不是不变量（本工程的老坑），所以闸放在写点。
	#     ★ 为什么这里**故意发起一次真路径的写**：要测的不变量是「这个动作**没有效果**」，
	#       而"没有效果"只能靠**真做一次再看**来观测 —— 如果改成断言 `_is_automated_run()`，
	#       那把 `save_last_match()` 里的闸整段删掉它**照样绿**（同义反复，等于没测）。
	#     ★ 安全性：闸生效时**一个字节都不会写**；为防"闸坏掉的那一次"留下脏数据，先把用户文件的
	#       原始字节取下来，比完之后**按字节还原**（即使在坏构建上跑，用户配置也会被复原，
	#       而下面那条判据会报红把这件事说出来 —— 不静默）。
	var user_lm: String = ProjectSettings.globalize_path(GameConfig.LAST_MATCH_PATH)
	var lm_before: PackedByteArray = FileAccess.get_file_as_bytes(user_lm)
	# ★ 显式传 `xg=0`：`xg` 插在 `path` 之前（有默认值），**传了路径的调用点必须补这一位**，
	#   否则路径字符串落到 `xg: int` 上 ⇒ Parse Error（本轮实测就是这么栽的第二次）。
	GameConfig.save_last_match(BOARD_KITE, GameConfig.STANDARD, GameConfig.HAT_HAT,
		DIFF_HARD, MODE_LOCAL, 0, GameConfig.LAST_MATCH_PATH)
	#     ★★ 判据变量 `lm_intact` 只在**还原之前**判一次：**判据不许被自己的善后动作抹平**。
	#       首版就踩了 —— 还原之后又比了一次、把结果写回同一个变量 ⇒ 判据恒真，
	#       阴性对照（M33 拆掉闸）当场是**绿的**（"看起来有判据、其实它永远不会红"）。
	#       所以还原的结果另存 `lm_restored`，只用于汇报，不进判据。
	var lm_intact: bool = FileAccess.get_file_as_bytes(user_lm) == lm_before
	var lm_restored: bool = lm_intact
	if not lm_intact:
		if lm_before.is_empty():
			DirAccess.remove_absolute(user_lm)          # 原本没有这个文件 → 删掉，别留一个空壳
		else:
			var lf := FileAccess.open(user_lm, FileAccess.WRITE)
			if lf != null:
				lf.store_buffer(lm_before)
				lf.close()
		lm_restored = FileAccess.get_file_as_bytes(user_lm) == lm_before
	ok = lm_intact and ok
	print("[lastmatchtest] 4b) 写点兜底闸：对真路径发写被拦下（用户文件 %dB 逐字节未变）%s" % [
		lm_before.size(), "✓" if lm_intact else
			("✗ 用户配置被自检写了（已按字节还原=%s）" % str(lm_restored))])

	# 5) 开局下发计划（纯函数 `_start_config_plan()`）—— 三个档位逐一断。
	#    ★★ 为什么单列这一段（2026-10-15b 新立）：并列化给"下发"这条链新增了一个**静默**坏法 ——
	#      `_start_from_setup()` 里若把 `if _sel_mode == MODE_VS_AI` 留着不改成**折叠后**的值，
	#      疾风档就会落到 `else: GameConfig.ai_time_ms = 0`；而骨架自己不看时间预算 ⇒
	#      疾风照下、**看不出来**，只有"疾风局里 AI 执黑的兜底起手"那一支才咬人。
	#      把它抽成纯函数（铁律 §67：判据的标的必须是纯函数）之后，这里能把三个档位一次断掉，
	#      不必真开机（`_start_from_setup()` 末端会转场，没法在自检里调）。
	#    期望表（**每列都断**，不只断 `mode` 那一列 —— 只断一列的话 `xg`/`ai_cfg` 写歪照样绿）：
	#      档位          mode   xg      liushui  kind  ai_cfg
	#      本地(0)       0      false   false    0     false
	#      磐石(1)       1      false   false    0     true
	#      疾风(100)     **1**  true    false    1     true   ← 哨兵折叠成 1；出现 100 = 哨兵外泄进引擎
	#      流水(101)     **1**  false   true     2     true   ← 2026-10-22 新增档
	#    ★★ 表里真正守着的东西是**互斥**：疾风必须 `xg=true/liushui=false`、流水必须反过来。
	#      两者的 `mode` 都是 1（折叠后同值）⇒ 只断 `mode` 的话"两个标记同时为 true"
	#      这唯一的坏法**完全看不见**（它在 `game.gd` 里被 `not xg_play_mode` 兜成疾风，
	#      即"选了流水却下了疾风"—— 棋能下、界面正常、只有引擎不对）。
	#    ★ `kind` 列守的是存档编码：0/1/2 写错 ⇒ 重启后档位漂移（静默，见 `_sel_kind_code()`）。
	var plan_cases: Array = [
		{"id": MODE_LOCAL, "mode": MODE_LOCAL, "xg": false, "liushui": false, "yema": false, "kind": 0, "ai_cfg": false},
		{"id": MODE_VS_AI, "mode": MODE_VS_AI, "xg": false, "liushui": false, "yema": false, "kind": 0, "ai_cfg": true},
		{"id": MODE_XGAI, "mode": MODE_VS_AI, "xg": true, "liushui": false, "yema": false, "kind": 1, "ai_cfg": true},
		{"id": MODE_LIUSHUI, "mode": MODE_VS_AI, "xg": false, "liushui": true, "yema": false, "kind": 2, "ai_cfg": true},
		{"id": MODE_YEMA, "mode": MODE_VS_AI, "xg": false, "liushui": false, "yema": true, "kind": 3, "ai_cfg": true},
	]
	var plan_bad: Array[String] = []
	var plan_seen: int = 0
	for pc in plan_cases:
		_sel_mode = int(pc["id"])
		var pl: Dictionary = _start_config_plan()
		plan_seen += 1
		if int(pl["mode"]) != int(pc["mode"]) or bool(pl["xg"]) != bool(pc["xg"]) \
				or bool(pl["liushui"]) != bool(pc["liushui"]) \
				or bool(pl["yema"]) != bool(pc["yema"]) \
				or int(pl["kind"]) != int(pc["kind"]) \
				or bool(pl["ai_cfg"]) != bool(pc["ai_cfg"]):
			plan_bad.append("%s ⇒ mode=%s xg=%s liushui=%s yema=%s kind=%s ai_cfg=%s（应 %s/%s/%s/%s/%s/%s）" % [
				_mode_label(int(pc["id"])), str(pl["mode"]), str(pl["xg"]), str(pl["liushui"]),
				str(pl["yema"]), str(pl["kind"]), str(pl["ai_cfg"]),
				str(pc["mode"]), str(pc["xg"]), str(pc["liushui"]), str(pc["yema"]),
				str(pc["kind"]), str(pc["ai_cfg"])])
	# ⚠️ 有效分母：五档必须**都跑到**（少一档 = 少断一档；一个都没有则判据恒真 —— 铁律 13⑨）
	var c5: bool = plan_bad.is_empty() and plan_seen == plan_cases.size()
	ok = c5 and ok
	print("[lastmatchtest] 5) 开局下发计划｜纯函数·五档各断 mode/xg/liushui/yema/kind/ai_cfg %s（覆盖 %d 档 · 异常 %d 处 %s）" % [
		"✓" if c5 else "✗", plan_seen, plan_bad.size(), str(plan_bad.slice(0, 3))])

	# 6) 清理测试文件：user:// 下不留垃圾
	var left: bool = FileAccess.file_exists(TEST_PATH)
	if left:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var cleaned: bool = not FileAccess.file_exists(TEST_PATH)
	ok = cleaned and ok
	print("[lastmatchtest] 6) 清理测试文件：%s → 已删=%s %s" % [
		TEST_PATH, str(cleaned), "✓" if cleaned else "✗"])

	# 状态复原（别把自检里的状态留给后续代码）
	_sel_board = BOARD_PENROSE
	_sel_size = GameConfig.STANDARD
	_sel_hatkind = GameConfig.HAT_HAT
	_sel_mode = MODE_LOCAL
	print("[lastmatchtest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()
	return ok

## 自检 --recordtest：联机战绩（user://record.cfg）的 落盘→读回→胜率计算 闭环。
##
## 为什么要它 —— 这条链上有三处**静默**失败点，全都不会抛错、只会悄悄错：
##   ① ConfigFile 的 section/key 名写错 → 读回全丢（战绩归零、大厅里胜率显示错）；
##   ② 胜率边界算错（0 局 / 全胜 / 全负）→ 显示 "0%" 或除零崩；
##   ③ 落盘没有守卫 → 自检/截图把临时战绩写进用户真配置（污染真实战绩）。
##
## 文件往返走**独立路径**（`user://record_selftest.cfg`），绝不碰用户的 record.cfg；跑完删掉。
func _record_test() -> bool:
	var ok := true
	const TEST_PATH := "user://record_selftest.cfg"

	# 0) 快照当前战绩内存态，测完还原（别让自检污染本次进程的战绩）
	var wins0: int = GameConfig.record_wins
	var losses0: int = GameConfig.record_losses

	# 1) 文件往返：wins/losses 逐一比对（section/key 名任一写错都会在这里现形）
	GameConfig.record_wins = 12
	GameConfig.record_losses = 4
	GameConfig.save_record(TEST_PATH)
	GameConfig.record_wins = 0
	GameConfig.record_losses = 0
	GameConfig.load_record(TEST_PATH)
	var rw: bool = GameConfig.record_wins == 12 and GameConfig.record_losses == 4
	ok = rw and ok
	print("[recordtest] 1) 文件往返：写 12/4 → 读 %d/%d %s" % [
		GameConfig.record_wins, GameConfig.record_losses, "✓" if rw else "✗ 键名/类型不一致"])

	# 2) 胜率边界（四条）：0 局 = -1（区分"没打过"与"全输"）、全胜 = 1、全负 = 0、3胜1负 = 0.75
	GameConfig.record_wins = 0
	GameConfig.record_losses = 0
	var e0: bool = GameConfig.win_rate() < 0.0
	GameConfig.record_wins = 5
	GameConfig.record_losses = 0
	var e1: bool = is_equal_approx(GameConfig.win_rate(), 1.0)
	GameConfig.record_wins = 0
	GameConfig.record_losses = 5
	var e2: bool = is_equal_approx(GameConfig.win_rate(), 0.0)
	GameConfig.record_wins = 3
	GameConfig.record_losses = 1
	var e3: bool = is_equal_approx(GameConfig.win_rate(), 0.75)
	var e_ok: bool = e0 and e1 and e2 and e3
	ok = e_ok and ok
	print("[recordtest] 2) 胜率边界：0局=%s 全胜=%s 全负=%s 3胜1负=%s %s" % [
		str(e0), str(e1), str(e2), str(e3), "✓" if e_ok else "✗"])

	# 3) record_str 格式（大厅 UI 与 lobby data 要显示）：无战绩 "—"，有战绩 "75%（3胜1负）"
	GameConfig.record_wins = 0
	GameConfig.record_losses = 0
	var r0: String = GameConfig.record_str()
	GameConfig.record_wins = 3
	GameConfig.record_losses = 1
	var r1: String = GameConfig.record_str()
	var s_ok: bool = r0 == "—" and r1 == "75%（3胜1负）"
	ok = s_ok and ok
	print("[recordtest] 3) record_str：无战绩=\"%s\" 3胜1负=\"%s\" %s" % [
		r0, r1, "✓" if s_ok else "✗"])

	# 4) 写点兜底闸：自动化运行下，对**真路径**发写必须被改道到自检盘（不落用户文件）。
	#    与 --lastmatchtest 4b 同一套：真做一次再看"用户文件没动"。首版只断言 is_automated_run()
	#    是同义反复 —— 把 save_record 里的闸整段删掉它照样绿。所以必须**故意发一次真路径的写**。
	var user_rec: String = ProjectSettings.globalize_path(GameConfig.RECORD_PATH)
	var rec_before: PackedByteArray = FileAccess.get_file_as_bytes(user_rec)
	GameConfig.record_wins = 999
	GameConfig.record_losses = 1
	GameConfig.save_record(GameConfig.RECORD_PATH)
	var rec_intact: bool = FileAccess.get_file_as_bytes(user_rec) == rec_before
	var rec_restored: bool = rec_intact
	if not rec_intact:
		if rec_before.is_empty():
			DirAccess.remove_absolute(user_rec)
		else:
			var rf := FileAccess.open(user_rec, FileAccess.WRITE)
			if rf != null:
				rf.store_buffer(rec_before)
				rf.close()
		rec_restored = FileAccess.get_file_as_bytes(user_rec) == rec_before
	ok = rec_intact and ok
	print("[recordtest] 4) 写点兜底闸：对真路径发写被改道（用户文件 %dB 逐字节未变）%s" % [
		rec_before.size(), "✓" if rec_intact else
			("✗ 用户战绩被自检写了（已按字节还原=%s）" % str(rec_restored))])

	# 5) 清理测试文件：user:// 下不留垃圾
	var left: bool = FileAccess.file_exists(TEST_PATH)
	if left:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	var cleaned: bool = not FileAccess.file_exists(TEST_PATH)
	ok = cleaned and ok
	print("[recordtest] 5) 清理测试文件：%s → 已删=%s %s" % [
		TEST_PATH, str(cleaned), "✓" if cleaned else "✗"])

	# 状态复原
	GameConfig.record_wins = wins0
	GameConfig.record_losses = losses0
	print("[recordtest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()
	return ok

# ★ 2026-09-30 §24 第 5 步：`_looks_like_code()`（判"输的是 6 位邀请码还是对方 IP"）
#   随 `_join_by_code()` 一起删除 —— 它是自建中继的输入格式约定，Steam 侧只认纯数字房间号
#   （`_steam_join_by_id()` 里那道 `is_valid_int()` + `> 0`）。

## 顶部红色错误提示（联机失败等），数秒后自动移除
func _show_error_toast(msg: String) -> void:
	var toast := Label.new()
	toast.text = msg
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", TOAST_RED)
	toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toast.offset_top = 18.0
	# ★ 2026-10-21：高度按文本长度**自适应**（短提示仍然是原来的 64）。
	#   起因 = 「Steam 不可用」现在带**逐层诊断**（100~200 字，见 `SteamNet.missing_diag()`），
	#   固定 64 高会把后半截挤到下面控件的区域里 —— 那条提示正是"第二台机器缺什么"的
	#   唯一线索，读不全等于没有（同"量具说谎"那一族：信息在，但读不到）。
	var extra: float = clampf(ceilf(float(msg.length()) / 40.0) - 1.0, 0.0, 5.0) * 26.0
	toast.offset_bottom = 64.0 + extra
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func() -> void:
		if is_instance_valid(toast):
			toast.queue_free())

## 探针：读出「`n0` 之后新增的那条错误提示」的文字（没有则空串）。
## ★ 读的是**真的挂在树上的那个 Label**，不是另存一份副本 —— 副本一旦和显示脱钩
##   （改了显示、忘了副本），判据就成了谎话（本工程「量具说谎」那一类，见过不止一次）。
## ★ `n0` 用「点击前的子节点数」而不是"清空所有提示"：`queue_free()` 是**延迟**的，
##   同帧内被 free 的旧提示仍在子节点列表里，清不干净；而新提示一定**追加**在末尾。
func _toast_text_since(n0: int) -> String:
	var last := ""
	for i in range(n0, get_child_count()):
		var c := get_child(i)
		if c is Label and (c as Label).has_theme_color_override("font_color") \
				and (c as Label).get_theme_color("font_color").is_equal_approx(TOAST_RED):
			last = (c as Label).text
	return last

## 自检探针：把「加入 / 建房」这一路会写的字段 + 「有没有请求转场」抓成一份快照。
## ★ 只盯着 `steam_lobby` 是**不够**的 —— `is_host` / `online` / `net_channel` 里
##   任何一个被提前写坏，都会让这一局走上错的通道（而单看房间号完全看不出来）。
## ★ `busy` 进来是**为了让判据可归因**：写成「点完之后 `Transition.is_busy()` 为假」的话，
##   只要**前面**某一步漏过一次转场请求，后面每一条都会跟着红 —— 阴性对照仪于是只会告诉你
##   "一大片都红了"，**说不出是哪条判据抓住了哪件事**。改成「点之前 == 点之后」之后，
##   每条判据只对自己那一次点击负责（差值非空 ⇒ 那一次点击真的动了东西）。
func _join_snap() -> Dictionary:
	return {
		"lobby": GameConfig.steam_lobby, "host": GameConfig.is_host,
		"online": GameConfig.online, "chan": GameConfig.net_channel,
		"busy": Transition.is_busy(),
	}

## 比对 `_join_snap()` 的快照：返回「未改动」或「被改成：…」。给自检的明细串用。
func _join_snap_delta(b: Dictionary) -> String:
	var now: Dictionary = _join_snap()
	var parts: Array = []
	for k in ["lobby", "host", "online", "chan", "busy"]:
		if b[k] != now[k]:
			parts.append("%s %s→%s" % [k, str(b[k]), str(now[k])])
	return "未改动" if parts.is_empty() else "被改成：" + ", ".join(parts)

# ====== 主菜单重设计：辅助函数（2026-10-02）======

## 把「当前选择」换算成背景该画的盘型 + 档位，并落定。
## ★ 为什么需要单独换算而不是直接读 `_sel_board` / `_sel_size`：
##   `_sel_size` 的槽位 0 在**爱因斯坦**下是「种类」、在**筝形**下是「迷你固定盘」——
##   直接读会在这两种盘上取到错的几何（背景画出来的与实际开局不是一张盘）。
##   而这层换算**只能有一处**，否则绘制与判据各算一次，早晚分家（同"两处真相"）。
func _sync_menu_bg() -> void:
	# ★ 用 `_eff_board()`（**用户看到的**那块）而不是 `_sel_board` ——
	#   `_select_board()` 走待切换机制：点一下就设 `_board_pending` 并收回动画，
	#   `_sel_board` 要到"开始/切页"才落定。若背景跟 `_sel_board`，
	#   症状是"点了新棋盘、背景还是旧盘"—— 而那**恰恰是用户最想看到它变**的一刻。
	_menu_bg_board = _eff_board()
	# 槽位 0 的语义随棋盘变（大小 vs 种类）；爱因斯坦下"随机档"不存在，
	# 背景统一按"该盘能生成的最大那档"画 —— 背景是氛围，不需要与实际局完全同尺寸。
	if _is_hat_eff():
		_menu_bg_size = GameConfig.RANDOM
	else:
		_menu_bg_size = _sel_size
	# ★★ 换盘型/换档 ⇒ 背景密铺必须**作废重算**。
	#   这里是"背景真源被改写"的唯一入口 ⇒ 作废动作也必须挂在这里，
	#   散到各调用处就是"将来加一条改选择的路径就会漏掉"（症状：背景还是上一张盘）。
	_bg_ensure()

## ====== 首页主视觉：所选棋盘的**真实密铺**（2026-10-02 重设计）======
## 背景密铺生成盒 / 视口（>1 留出漂移余量，免得漂出边）
const BG_TILE_SCALE: float = 1.30
## 背景密铺的基准不透明度（衬底，不能盖过前景的字）
const BG_ALPHA: float = 0.17
## 描边相对填充的强度倍数（密铺的"线"比"面"更该被看见一点）
const BG_LINE_MUL: float = 1.7
## 漂移幅度 / 视口短边（每帧推进量在 `_process` 里，约 0.06 周期/秒）
const BG_DRIFT_PX: float = 0.016
## ====== 背景缓慢旋转（2026-10-02 加）======
## 旋转相位推进速度（周期/秒）。→ 摆一个来回约 33 秒。
## ★ 与漂移**故意不同频**（0.06 vs 0.03）：两个正弦同频会看出"整体在一起晃"，
##   不同频才像"背景自己是活的"（周期比 2:1，最小公倍数 33s，长时间不重复）。
const BG_SPIN_RATE: float = 0.03
## 摆角的**上限**（度）：盘形越接近圆，几何上允许转得越多，但"背景大幅转向"观感上过头
## ⇒ 几何解出的幅度再被这个上限夹一道。见 `_bg_spin_amp_for()`。
const BG_SPIN_MAX_DEG: float = 22.0
## 允许的最大**覆盖损失**：旋转之后密铺在任一方向上的跨度最多缩这么多。
## ★★ 为什么不直接写死角度（铁律 4）：能转多少完全由**盘形的长宽比**决定 ——
##   彭罗斯实测 666×741（≈0.90，几乎圆 ⇒ 转很多也不掉覆盖），筝形可能到 0.5。
##   由 `R·√(1−(1−(r/R)²)sin²θ) ≥ R·(1−loss)` 反解：
##     `sin²θ ≤ (2·loss − loss²)/(1 − (r/R)²)`
##   ⇒ 角度**从实测盘形解出来**，写死一个数只对当前盘型成立。
##   ⚠️ 比值 →1（正圆）时右式发散 ⇒ 必须与 `BG_SPIN_MAX_DEG` 一起取小。
const BG_SPIN_LOSS: float = 0.02
## ★★ 2026-10-02 用户明确决定：**这三个旋钮不上设置页**（"要不要做成运行期可调" → "不需要"）。
##   ⇒ 它们就留在 `menu.gd` 当常量，**不要再往设置页加**（本项目"数值一律 `@export` 可实时调"
##     那条约定是给**玩法/棋理**数值的；背景旋转是**氛围层观感微调**，玩家没有选择它的理由）。
## ⚠️ 但改这三个值之前要知道一件事：**它们是 ④b 判据的真源** ——
##   ④b ② 断言"实测覆盖损失 ≤ `BG_SPIN_LOSS`"、④b 上限断言"≤ `BG_SPIN_MAX_DEG`"，
##   都是**拿常量比自己** ⇒ 把 `BG_SPIN_LOSS` 放到 0.5，那条断言**会跟着一起放松**（⑤「判据
##   自己注入被测量」那一族）。⇒ 改这三个值之后，能判的只剩：几何是否**仍然**由实测盘形解出
##   （④b ③：换盘形幅度必须跟着变）+ **定格截图目检**（摆幅看起来过不过头）。

## 缓存：`_bg_polys`（视口本地坐标，已按缩放盒居中）+ `_bg_key`（缓存键）+ `_bg_box`。
## ★ 必须是"缓存 + 一次生成"：`generate_board()` 实测 3~12ms，每帧跑必卡。
var _bg_polys: Array = []
var _bg_key: Array = []
var _bg_box: Vector2 = Vector2.ZERO
## 每块的**渐隐系数**（与 `_bg_polys` 一一对应）。★ 它只依赖"块心在密铺局部坐标里的位置"，
## 与旋转、漂移**都无关** ⇒ 一次算好、逐帧复用（旋转之后更没理由每帧重算：
## 每块要加总顶点 + 两次除法，183 块 × 每帧 ≈ 白烧 3 万个浮点运算）。
var _bg_fade_k: Array = []
## 旋转相位（0..1）与**解出来的**摆幅（弧度）。相位由 `_process` 推进、绘制侧取样。
var _bg_spin: float = 0.0
var _bg_spin_amp: float = 0.0
## 只给截图夹具（`--shotspin=`）用：把背景动效**整体定格**（漂移与旋转一起停在夹具给的相位）。
## ★ 为什么必须连漂移一起定格：A/B 目检要回答的是"旋转有没有把盘形甩出渐隐范围" ——
##   若两帧之间漂移相位还各自乱跑，差分里就混着一次**未知平移**
##   ⇒ 拿截图去反解旋转角会得到一个"看着像对的"错数（铁律 4 的坐标系/口径混用）。
var _bg_frozen: bool = false
## 密铺**实际占的**外接矩形（局部坐标）。外缘渐隐按它归一化 ——
## ★ 不能用 `_bg_box`：生成器给的是**有界的盘形**（一个内切于生成盒的菱形/多边形），
##   盘形自己够不到盒子的四角 ⇒ 按盒子归一化会在盘形边界处留一圈**看得见的硬边**
##   （实测首版截图：屏幕中间悬着一块巨大的"贴纸"）。
var _bg_rect: Rect2 = Rect2()

## 背景密铺几何：盘型 / 档位 / 帽子种类 / 视口尺寸任一变了才重算（否则立刻返回）。
## ★ 走 `MenuModel.effective_choice()` 而不是直接读 `_sel_size`：
##   槽位 0 的语义在爱因斯坦下是"种类"、在筝形下是"迷你"，直接读会取到错的几何
##   （与 `_shape_polys()` 同源，见 `_sync_menu_bg` 的注释）。
func _bg_ensure() -> void:
	if _page != PAGE_MAIN:
		return
	var box := Vector2(maxf(size.x, 64.0) * BG_TILE_SCALE, maxf(size.y, 64.0) * BG_TILE_SCALE)
	var ch: Dictionary = MenuModel.effective_choice(_menu_bg_board, _menu_bg_size, _sel_hatkind)
	var key: Array = [int(ch["board"]), int(ch["size"]), int(ch["hat_kind"]),
		roundi(box.x), roundi(box.y)]
	if key == _bg_key:
		return
	_bg_key = key
	_bg_box = box
	_bg_polys = _shape_polys(ch, box.x, box.y)
	# 记录密铺实际占的矩形（外缘渐隐按它归一化，见 `_bg_rect` 的注释）
	_bg_rect = Rect2()
	var first := true
	for poly2 in _bg_polys:
		for p2 in (poly2 as PackedVector2Array):
			if first:
				_bg_rect = Rect2(p2, Vector2.ZERO)
				first = false
			else:
				_bg_rect = _bg_rect.expand(p2)
	# ★★ 外缘渐隐系数与旋转摆幅都在**这里**一次算好 —— 两者都只依赖盘形几何。
	#   计算的**唯一真源**是这两个循环：绘制侧只读结果，判据也只读结果
	#   （"判据自己再算一遍"就会出现"量的是 A、画的是 B"那种静默错配）。
	_bg_fade_k = _bg_fade_k_for(_bg_polys, _bg_rect)
	_bg_spin_amp = _bg_spin_amp_for(_bg_rect.size)
	# 诊断（`--layoutdbg`）：背景密铺的生成盒 / 实占盒 / 块数 / 缓动相位 / 摆幅。
	# ★ 为什么值得常驻：背景是"氛围"层，它的边缘、透明度、旋转幅度**都没有像素判据**
	#   （headless 不渲染），只能靠这几个量对着截图判断 —— 与 `_dbg_geometry_dump` 同一个理由。
	if "--layoutdbg" in _argv():
		print("[bgdbg] size=%s box=%.0f×%.0f rect=P(%.1f,%.1f) S(%.0f,%.0f) 块=%d 摆幅=%.1f°" % [
			str(size), box.x, box.y, _bg_rect.position.x, _bg_rect.position.y,
			_bg_rect.size.x, _bg_rect.size.y, _bg_polys.size(), rad_to_deg(_bg_spin_amp)])

## 背景缓慢旋转的**摆幅上限**解算（弧度）。
##
## 几何：盘形在局部坐标里是一个"椭圆状"的块（半轴 `R = max/2`、`r = min/2`）。
##   绕中心转 θ 后，它在**长轴方向**上的跨度缩到 `R·√(cos²θ + (r/R)²·sin²θ)`
##   = `R·√(1 − (1−(r/R)²)·sin²θ)` ⇒ 要让损失 ≤ `loss`：
##     `(1−(r/R)²)·sin²θ ≤ 2·loss − loss²`
##
## ★★ 为什么"允许的损失"当输入、角度当输出：盘形长宽比**随盘型变**（彭罗斯 0.90、筝形可能 0.5），
##   写死角度在圆盘上太保守、在扁盘上则会让背景露出边界（铁律 4）。
## ★ 正圆（比值→1）时右式发散（几何上确实可以转任意角），所以必须与 `BG_SPIN_MAX_DEG` 取小。
## ★ 这一层是纯几何，headless 可测 ⇒ 判据 ④b 直接量它（不必靠像素）。
func _bg_spin_amp_for(bsz: Vector2) -> float:
	var r: float = minf(bsz.x, bsz.y) * 0.5
	var big: float = maxf(bsz.x, bsz.y) * 0.5
	if r <= 0.0 or big <= 0.0:
		return 0.0
	var denom: float = 1.0 - (r / big) * (r / big)
	var loss: float = clampf(BG_SPIN_LOSS, 0.0, 0.5)
	var num: float = 2.0 * loss - loss * loss
	# 比值→1（正圆）时 denom→0：几何上任意角都不掉覆盖 ⇒ 交给上限夹
	var s2: float = 1.0 if denom <= 0.0001 else clampf(num / denom, 0.0, 1.0)
	var deg: float = rad_to_deg(asin(sqrt(s2)))
	return deg_to_rad(minf(deg, BG_SPIN_MAX_DEG))

## 逐块的渐隐系数（按块心在**密铺局部坐标**里到中心的归一化椭圆距离）。
## 返回与 `polys` 等长的 `Array[float]`，值域 [0,1]（0 = 全透明、不画）。
##
## ★★ 为什么按**椭圆**归一化（首版踩过）：把密铺的外接矩形当椭圆的两个半轴，于是
##   "盘形边界的正上/正下/正左/正右"正好落在 `k=0` 的等值线上 ⇒ 任何视口都**看不见生硬的边界**。
##   按**对角线**归一化时中边只降到 0.4，实测截图上"屏幕中间悬着一块巨大的贴纸"，
##   那条边界**一眼可见**（`_bg_rect` 的存在理由）。
## ★★ 关键性质：这个量**旋转不变**（用的是局部坐标、且绕中心旋转不改变这个距离关系）
##   ⇒ 加了旋转之后它仍然只需要算一次。反过来，若把它写在绘制循环里"跟着转后的点算"，
##   就等于把渐隐钉在屏幕坐标上 —— 盘形一转，渐隐圆盘与盘形边界**错开**，
##   边界立刻显形（这正是"旋转"这件事最容易踩的坑）。
func _bg_fade_k_for(polys: Array, brect: Rect2) -> Array:
	var out: Array = []
	var cc: Vector2 = brect.position + brect.size * 0.5
	var rx: float = maxf(brect.size.x * 0.5, 1.0)
	var ry: float = maxf(brect.size.y * 0.5, 1.0)
	for poly in polys:
		var src: PackedVector2Array = poly
		var acc := Vector2.ZERO
		for p in src:
			acc += p
		var n: int = maxi(src.size(), 1)
		var dx: float = (acc.x / float(n) - cc.x) / rx
		var dy: float = (acc.y / float(n) - cc.y) / ry
		var de: float = dx * dx + dy * dy
		out.append(clampf(1.0 - de * de * 0.85 - de * 0.15, 0.0, 1.0))
	return out

## 背景密铺点变换：`局部 → 绕盘心转 θ → 平移到屏幕`。绘制侧**唯一**的点变换，
## 判据也读它（否则"旋转到底有没有作用到几何上"就成了盲区）。
func _bg_xform(p: Vector2, center: Vector2, theta: float, org: Vector2) -> Vector2:
	return (p - center).rotated(theta) + center + org

## 画背景密铺（在 `_draw()` 的最开头、底色之后调用）。
##
## ★★ 为什么用"真几何"而不是贴图：本工程的视觉语言就是菱形瓷砖，而每个棋盘的密铺
##   都是生成器现算的 ⇒ 直接用真几何，换盘型时背景自然跟着换（用户口径「跟当前选择联动」）。
## ★ 为什么"低不透明度 + 外缘渐隐"两层保险：生成器给的是**有界的盘形**（不是无限密铺），
##   直接画会看到一条生硬的"棋盘轮廓边"；而且背景是衬底，必须让位于前景的字。
##   ⇒ 按"离视口中心的归一化距离"逐块调透明度，外缘自然淡出。
func _draw_menu_bg_tiling() -> void:
	if _bg_polys.is_empty():
		return
	# 漂移：两个轴取不同频率的正弦，看不出周期（纯观感，无玩法含义）
	var amp: float = minf(size.x, size.y) * BG_DRIFT_PX
	var off := Vector2(sin(_bg_drift * TAU) * amp, sin(_bg_drift * TAU * 0.63) * amp * 0.6)
	var org: Vector2 = (size - _bg_box) * 0.5 + off
	# ★★ 缓慢旋转（2026-10-02 加）：绕**盘心**摆（不是绕屏幕中心）——
	#   漂移量很小但两者叠加，绕盘心摆才能保证"盘形自己的边界"不扫进屏幕里：
	#   渐隐椭圆的中心就是盘心，绕盘心旋转时**渐隐边界与盘形边界始终保持重合**
	#   ⇒ 不可能因为旋转而露出硬边（与"按盒子归一化会留一圈硬边"是同一件事的两面）。
	#   摆幅由 `_bg_spin_amp_for()` 从实测盘形解出（摆到头覆盖损失 ≤ `BG_SPIN_LOSS`）。
	var th: float = sin(_bg_spin * TAU) * _bg_spin_amp
	var cc0: Vector2 = _bg_rect.position + _bg_rect.size * 0.5
	var fill_base: Color = GameConfig.board_color
	var line_base: Color = GameConfig.line_color
	for bi in _bg_polys.size():
		var poly: PackedVector2Array = _bg_polys[bi]
		if poly.size() < 3:
			continue
		# ★ 渐隐系数是**缓存**里的（旋转不变 ⇒ 只算一次），不在这里现算
		var k: float = float(_bg_fade_k[bi]) if bi < _bg_fade_k.size() else 0.0
		if k <= 0.02:
			continue
		var pp := PackedVector2Array()
		for p in poly:
			pp.append(_bg_xform(p, cc0, th, org))
		var col := fill_base
		col.a = BG_ALPHA * k
		draw_colored_polygon(pp, col)
		var lc := line_base
		lc.a = clampf(BG_ALPHA * BG_LINE_MUL * k, 0.0, 1.0)
		var closed := PackedVector2Array(pp)
		closed.append(pp[0])
		draw_polyline(closed, lc, 1.0, true)


## 「疾风」档 → `GameConfig` 层身份的**唯一折叠点**（铁律 8：一处写、一处读）。
##
## 为什么需要它：并列化之后「疾风」是 `_sel_mode` 的独立取值（哨兵 `MODE_XGAI = 100`），
## 而 `GameConfig.mode` 只收 LOCAL/VS_AI/ONLINE —— `game.gd` 有 30+ 处 `game_mode == VS_AI`，
## 给 mode 加第四档就得改遍那些地方（且 `game.gd::_ready` 有一道"非法 mode 夹回 VS_AI"的闸，
## 加档等于把那道闸作废）。⇒ **折叠一次**：「疾风」在引擎侧就是"人机 + 骨架标记"，
## 与改前的下发结果**逐字节相同**（铁律 §111）。两个读点：`_start_from_setup()` 与落盘。
func _sel_mode_for_config() -> int:
	return MODE_VS_AI if (_sel_mode == MODE_XGAI or _sel_mode == MODE_LIUSHUI
		or _sel_mode == MODE_YEMA) else _sel_mode


## `_sel_mode` → `last_match.cfg` 的 `xg` 字段编码（0=磐石 / 1=疾风 / 2=流水 / 3=野马）。
## ★ 单一真源：存档那行与读档那条各写一遍 `if elif` 必然漂移，而漂移的症状是**静默的**
##   —— 存进去 1、读回来当磐石，只有"重启后档位变了"才看得见（§113）。
## ⚠️ 字段名仍叫 `xg`（历史名）：改名要动文件格式、破坏旧记录兼容，收益为零。
func _sel_kind_code() -> int:
	if _sel_mode == MODE_YEMA:
		return 3
	if _sel_mode == MODE_LIUSHUI:
		return 2
	if _sel_mode == MODE_XGAI:
		return 1
	return 0

## 开局下发决策（**纯函数** —— 铁律 §67：配对/判据的标的必须是纯函数，否则只能靠真开机验证）。
##
## 返回 `{mode, xg, ai_cfg}` 三样，就是 `_start_from_setup()` 写进 `GameConfig` 的全部内容。
##
## ★★ 为什么值得单独抽出来：这三样里 `ai_cfg` 那一项**判错的后果是静默的** ——
##   并列化之后若把 `if _sel_mode == MODE_VS_AI` 留着不改成折叠值，疾风档就会落到
##   `else: GameConfig.ai_time_ms = 0`；而骨架自己不看时间预算 ⇒ **疾风照下、看不出来**，
##   只有"疾风局里 AI 执黑的兜底起手"那一支才咬人。抽成纯函数之后 `--lastmatchtest` 的
##   5) 段能把三个档位一次性断掉（含阴性对照），不必真开机。
func _start_config_plan() -> Dictionary:
	var cfg_mode: int = _sel_mode_for_config()
	return {
		"mode": cfg_mode,          # 写进 `GameConfig.mode` 的值（永远是三个合法值之一）
		"xg": _sel_mode == MODE_XGAI,   # 写进 `GameConfig.xg_opponent`
		"liushui": _sel_mode == MODE_LIUSHUI,   # 写进 `GameConfig.liushui_opponent`
		"yema": _sel_mode == MODE_YEMA,   # 写进 `GameConfig.yema_opponent`
		"ai_cfg": cfg_mode == MODE_VS_AI,   # 要不要 `_apply_ai_config()`（疾风/流水/野马**也要**）
		"kind": _sel_kind_code(),   # 写进 `last_match.cfg` 的 `xg` 字段
	}

# 由主菜单开始：按当前选择写入 GameConfig
func _start_from_setup() -> void:
	_commit_board_pending()          # 收回动画途中点「开始」：先把待切换的棋盘落定，别用旧锚点开局
	# ★ 2026-10-15b：三件下落全部由上面那个纯函数给出（同一个东西，两边不可能分叉）
	var plan: Dictionary = _start_config_plan()
	GameConfig.mode = int(plan["mode"])
	# 「疾风」标记随局下发（菜单→game 的唯一通道）。联机入口不经过这里；
	# game 侧还有 `game_mode == VS_AI` 闸 ⇒ 联机局不可能误开骨架。
	GameConfig.xg_opponent = bool(plan["xg"])
	# ★ 2026-10-22：流水档标记。与 `xg_opponent` **逐字同构** —— 每次开局无条件覆盖写，
	#   因此不存在"上一局选了流水、这局选磐石却残留 true"的窗口；
	#   联机/本地入口不写它也不出事（`game.gd` 的判定带 `and game_mode == VS_AI`）。
	GameConfig.liushui_opponent = bool(plan["liushui"])
	# ★ 2026-10-23：野马档标记。同上，每次开局无条件覆盖写（不存在残留 true 的窗口）。
	GameConfig.yema_opponent = bool(plan["yema"])
	_push_board_choice()
	if bool(plan["ai_cfg"]):
		_apply_ai_config()               # 磐石 / 疾风同走"恒最难"（见 `DIFF_HARD` 的注）
	else:
		GameConfig.ai_time_ms = 0
	Transition.change_scene("res://game.tscn")

## 难度档 → 引擎配置。
##
## 时间预算的定法（2026-09-13 重调，有实测依据）：
## 此前根候选上限是「全宽 96」，`--aibud` 实测**不同预算选出的着法一致率只有 13~38%** ——
## 每个候选只分到 0.4~3 次真实访问，胜率是纯噪声，多给的时间只是在掷骰子。
## 把根候选限到 14 个（`auto_root_width`）后一致率升到 88~100%。
##
## 二轮扫描（宽度 × 预算四档，标准盘 8 个局面）把「给多少时间」钉死了：
##   rw=14 → 150/300/420/900ms 四档两两一致率 88~100%，其中 8 个局面有 7 个**四档全同手**
##            （唯一的例外是 420ms 自己跑偏，150/300/900 三家一致）→ **150ms 就已经收敛**；
##   rw=28 → 一致率掉到 50~75%，开始被噪声主导；
##   rw=48 → 13~50%，退化成掷骰子（就是「96 候选」那个病的复现）。
## 所以两条结论：① 预算 150ms 足够，多给不再改变决策；② **不要再加宽根候选**（会反向劣化）。
##
## 困难的定位因此不是「想得更久」（实测想更久着法不变），而是留出余量 + 让对手看得见思考过程；
## 真要拉开档位差，得从**先验（棋感函数）**下手 —— 搜索在这个预算区间里几乎不改变结论。
##
## ★★ 2026-10-12：本函数原先收一个 `level` 参数、按三档 `match`（简单 / 困难 / 默认=普通）。
##   用户口令「人机默认最难，不需选择难度」之后**只剩困难这一档** ⇒ 参数与 `match` 一并删除
##   （留一个恒真的 `match` 就是"旋钮拧不动"的死参数，铁律 §33）。
##
## ⚰️ 两档已删的配置**原文留在这里**，别丢 —— 哪天要把难度选择加回来，这三条直接可用：
##   · 简单（`AI_EASY`）：`150ms / 1 线程 / 根全宽 9999`。刻意保留"单线程 + 根全宽"：
##     候选全宽 ⇒ 每个候选样本极少 ⇒ 退化成纯先验 + 噪声，是「弱但不像卡住」的低难度档；
##   · 普通（`AI_NORMAL`）：`200ms / 0 线程 / 根宽 0`（= 默认分支）；
##   · 困难（`AI_HARD`）：`500ms / 0 线程 / 根宽 0`（当前唯一在用的那一档）。
func _apply_ai_config() -> void:
	GameConfig.ai_level = DIFF_HARD
	GameConfig.ai_time_ms = 500
	GameConfig.ai_threads = 0
	GameConfig.ai_root_width = 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not _items.is_empty():
		_layout_setup()
		# ⚰️ 2026-10-12：这里原有「清空 `_stones`/两本动画字典 → 再把当前选中项重新铺回黑子」
		#   那一段（因为"黑子"是绘制侧读的独立记账集合，布局重建会把它清掉，必须补回来）。
		#   黑砖族删除后"已选"只由 `_items[i]["selected"]` 表达，而 `_layout_setup()` **不动它**
		#   ⇒ 这段补偿逻辑结构性不需要了（这正是"少一个集合 = 少一处会不同步的状态"的收益）。

		queue_redraw()

func _capture_and_quit() -> void:
	# ★ 等动画收尾再截（原来固定等 0.5s）：切棋盘要走「收回 → 整行滑行 → 再展开」三步，
	#   最长约 1.6s，0.5s 截到的是**动画中途**（瓷砖半透明、折叠簇还叠在一起）。
	#   实测 2026-09-19：`--select=爱因斯坦` 截出来的三瓣是灰的、还压在棋盘块上，
	#   被当成「改不了选项」的旁证，白查一轮 —— 截图本身也得等状态稳定。
	#   判据 = 已经处于「展开稳态」：切换落定 + 目标=1 + 进度=1 + 滑行完成。
	#   ⚠️ 千万别只写 `_board_t == _board_target`：收回阶段两者都是 0，会被误判成「已收敛」
	#   （实测第一次就写成那样，截出来的还是收回态、三瓣一个都看不到），必须钉住 **≥0.999**。
	#   最多等 5 秒，绝不无限等。
	var waited := 0.0
	while waited < 5.0:
		if _board_pending < 0 and _board_target >= 0.999 and _board_t >= 0.999:
			break
		await get_tree().create_timer(0.05).timeout
		waited += 0.05
	await get_tree().create_timer(0.15).timeout      # 呼吸描边相位不敏感，只留一点余量
	# ★ 等开场淡入（0.5s 的黑→透明）彻底结束再截，否则整张图被均匀压暗（实测 8%），
	#   审外观/量对比度都会失真。最多等 1.5s，绝不无限等。
	var fw := 0.0
	while Transition.cover_alpha() > 0.01 and fw < 1.5:
		await get_tree().create_timer(0.05).timeout
		fw += 0.05
	await RenderingServer.frame_post_draw
	# 打印真实视口：截图审外观时常要拿它对照瓷砖半径（1058 高 vs 1800 高，块大小差很多）
	print("[shot] 视口=%s 窗口=%s 位置=%s 可用区=%s 模式=%d" % [
		str(get_viewport_rect().size), str(DisplayServer.window_get_size()),
		str(DisplayServer.window_get_position()), str(GameConfig.screen_usable_rect()),
		DisplayServer.window_get_mode()])
	# 「窗口有没有居中」只看数字容易看漏（偏 24px 肉眼就是"看着别扭"）→ 直接出判据。
	# ★ 基准是**可用区**（去掉任务栏），不是整屏 —— 见 GameConfig.screen_usable_rect()
	print("[shot] 窗口居中 = %s（偏差=%s；基准=可用区）" % [
		GameConfig.window_center_verdict(), str(GameConfig.window_center_delta())])
	# 画布基座：审"竖屏/横屏"截图时必须知道这张图是哪个基座下截的，
	# 否则「UI 怎么变大了」会被当成渲染 bug（其实是单位从 1152 换成了 720）。
	print("[shot] %s" % GameConfig.canvas_verdict())
	if "--shotitems" in _argv():
		# 截图排查用：列出每块瓷砖的布局结果（poly=0 表示该块没被摆位、不会画出来）
		for i in _items.size():
			var it: Dictionary = _items[i]
			print("[shot]   #%d %s/%s poly=%d center=%s disabled=%s" % [
				i, it["group"], it["label"], it["poly"].size(), str(it["center"]),
				str(it["disabled"])])
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var p := "user://debug_menu.png"
		var ok: int = img.save_png(p)
		print("菜单截图保存 ok=", ok, " path=", ProjectSettings.globalize_path(p))
	else:
		print("菜单截图失败：image 为空")
	get_tree().quit()
