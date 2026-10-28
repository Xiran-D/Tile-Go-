extends Node2D

# ====== 彭罗斯棋盘参数（全部 @export：改默认值后重开一局生效）======
# ⚠️ 2026-10-13：运行时调参面板（TAB）已整块删除 ⇒ **没有**"运行期实时调参"这条路了。
# 几何: Robinson 三角形替换法（P3 标准彭罗斯镶嵌）
@export_group("生成")
## 替换迭代次数，2~6。越大棋盘越密、菱形越多
@export_range(2, 6, 1) var iterations: int = 4
## 是否用圆形裁剪去掉边缘不完整的菱形
@export var use_circle_clip: bool = true
## 裁剪半径（种子单位，0=中心 1=种子外缘）。标准棋盘 0.82 → 120 落子格 / 141 顶点
@export_range(0.4, 0.95, 0.01) var clip_radius: float = 0.82

@export_group("随机棋盘")
## 「随机」档的目标落子格数。两种棋盘的取法不同，但都命中这个数：
##   彭罗斯 → 在密铺里开一扇圆形窗口，二分搜索半径直到格数最接近目标；
##   立方体 → 从中心六边形随机生长，长到 目标/3 个六边形为止（每六边形 3 块菱形）。
@export_range(80, 400, 1) var random_target_tiles: int = 200
## 目标格数的随机浮动 ±N（每局在 [target-N, target+N] 里取一个值，让每局大小也略有不同）
@export_range(0, 60, 1) var random_tile_jitter: int = 12
## 随机盘取景窗口的**圆心偏移量**（单位 = 半径的倍数）。0 = 窗口恒在正中心；
## 越大，取到的密铺片段离「密铺原点」越远（对雪花随机档来说就是第三个随机源，见
## _generate_snowflake_random）。2026-09-16 按「偏移量放大一点」的要求把默认从 0.24 提到 0.6、
## 上限从 0.45 提到 1.2。
@export_range(0.0, 1.2, 0.01) var random_window_offset: float = 0.6
## 立方体随机生长的「紧密度」：每次从前沿里随机抽 N 个候选、取离中心最近的那个。
## 1 = 纯随机生长（形状毛糙、容易拖出长条，实测填充率最低只有 0.44）；
## 3 = 明显圆润（默认）；越大越接近规整的六边形补丁，也就越不像「随机」。
@export_range(1, 6, 1) var random_grow_compact: int = 3
## 彭罗斯随机盘：是否随机旋转「生成种子」的朝向（连续随机角）。
## 旋转整张密铺的朝向，让每局窗口截到的菱形网格指向不同方向，而不是永远同一套网格线（固定盘不受影响）。
@export var penrose_random_seed_rot: bool = true
## 彭罗斯随机盘：是否随机镜像（翻转）种子，与旋转叠加再翻出一种手性，进一步拉开每局差异（固定盘不受影响）。
@export var penrose_random_seed_mirror: bool = true
## 立方体随机盘：每个六边形是否在两种朝向间随机（三菱形内辐条指向偶顶点 / 奇顶点，
## 等效旋转 60°；正六边形转 120° 不变形故只有这两种。固定盘不受影响）。
@export var cube_hex_random_rot: bool = true

@export_group("筝形棋盘")
## 筝形盘的**正六边形环数** R（边界是严格正六边形，六条边各 R 条单位边）。
##   落子格数 = 6R² 个筝形：R=2 → 72 格（迷你）；R=3 → 162 格（标准）；R=4 → 288 格（加强）。
##   （R=6 是 648 格，对 AI 与操作都过大，故上限取 6、实际只用 2/3/4。）
@export_range(1, 6, 1) var _kite_r: int = 3

# ⚰️ 2026-10-17 墓碑（名字不许回收）：这里原有 `@export_group("雪花棋盘")` 与
#   `@export_range(1, 8, 1) var _snow_r: int = 4`。`_snow_r` **从来没有读者**
#   （真源是 `_snow_r_actual`，由 `_apply_board_size()` 按尺寸档直钉）⇒ 组与变量一并删除
#   （铁律 §33 死参数：旋钮拧不动）。下面这段 Ammann-Beenker 密铺说明**保留**——
#   它讲的是 `generate_snowflake()` 的几何原理，与那个死变量无关。
## 雪花盘**层数 n**（圆窗半径 R ≈ 0.61·n + 0.1 随层数走）。密铺 = **Ammann-Beenker**：
## de Bruijn 四格网（octagrid，4 族平行线、法向 45° 等分）的对偶 —— 瓷砖恰为两种：
## **45°/135° 胖菱形** 与 **正方形**。等相位网格关于原点**严格 8 重旋转对称**，
## 中央胞 = 正八边形 → 其对偶顶点上 **8 块 45° 菱形锐角共点（8×45°=360°）＝一朵完整雪花**，
## 相邻雪花之间由正方形搭桥（AB 密铺的招牌构型）。
## 层数阶梯（圆窗裁剪实测）：n=3 → 72（迷你）；n=5 → 200（标准）；n=6 → 296（加强）。

@export_group("帽子棋盘")
## **池的替换层数**（H7/H8 系统的膨胀次数）。取盘是「池 + BFS 收 N 片」，池必须比目标
## 大出一圈 —— BFS 球贴着池边界会被削平。实测：level 3 池（377 片）取 310 片时填充率
## 掉到 0.51（< 0.55 门槛），所以默认 4（池 2584 片）。level 5 约 1.8 万片，太慢，别开。
@export_range(2, 4, 1) var _hat_pool_level: int = 4
## 「标准」档落子格数
@export_range(40, 400, 1) var hat_std_tiles: int = 150
## 「加强」档落子格数
@export_range(40, 600, 1) var hat_big_tiles: int = 310
## 「随机」档目标格数 —— **爱因斯坦专用**，不与其它盘共用的 random_target_tiles 混用。
## 2026-09-20 用户口径：三种类随机盘格数提到 240~300 → 默认 270，±random_tile_jitter(12)
## = 258~282，正好落在窗口内。
@export_range(40, 600, 1) var hat_rand_tiles: int = 270

@export_group("配色")
@export var fat_color: Color = Color(0.78, 0.82, 0.88)
@export var thin_color: Color = Color(0.96, 0.91, 0.66)  # 瘦菱形底色（浅黄）
@export var background_color: Color = Color(0.5, 0.55, 0.62)
@export var line_color: Color = Color(1, 1, 1, 0.30)
## 占格棋子色：把瓷砖本身作为棋子，落子后该瓷砖染成对应玩家色（@export 可调）
@export var piece_color_black: Color = Color(0.06, 0.06, 0.08)
@export var piece_color_white: Color = Color(0.90, 0.90, 0.95)
## 棋盘底色：所有瓷砖统一用这一低调中性色，结构靠边线区分（@export 可调）。
## 取中性灰，使浅/深两套主题的边线（亮线/暗线）都能在其上清晰可见。
@export var board_tile_color: Color = Color(0.40, 0.41, 0.45)

@export_group("外观")
## 棋子半径 = 全盘最小内切圆半径 × 该系数（1.0 恰好贴满最窄的瘦菱形）
@export_range(0.6, 1.15, 0.01) var stone_scale: float = 0.86
## 立方体棋盘专用棋子系数：60°/120° 菱形的最大内切圆更瘦，取 0.78 让棋子稳稳嵌在面内
@export_range(0.5, 1.15, 0.01) var cube_stone_scale: float = 0.78
## 立方体棋盘三面明暗（同一立方体的三个面：亮 / 中 / 暗，形成等距立方体错觉）
@export var cube_face_mid: Color = Color(0.74, 0.79, 0.87)
@export var line_width: float = 2.2
## 图模式下**网格线**的加粗倍数（面模式线宽 × 它）。
## 面模式里线是"砖缝"（压在棋子边上即可），图模式里线是**棋盘本身**（落子点两两连线）⇒ 略粗一点更立得住。
@export_range(1.0, 3.0, 0.05) var graph_grid_width_scale: float = 1.2
## 图模式圆棋子的**直径系数**：直径 = 全盘**最近落子点间距** × 它（1.0 ⇒ 最密的那一对正好相切）。
## ★ 与面模式的 `stone_scale` 是**两个量纲**：那个是"相对本格内切半径"（每格大小不同），
##   这个是"相对最近落子点间距"（全盘一个数）。混用会让同一个旋钮在两套画法里各自跑偏。
## ★ 图模式要的是**等大圆子** ⇒ 全盘只认这一个基准，不按格、不按盘型分档（立方体盘也一样）。
## ★ 上限给到 1.60：Penrose 的落子点间距不匀（标准盘实测 54.6~88.4px，差 1.6 倍），
##   按"最近间距"取 1.0 时疏处空隙很大（实测最大 34px）；实测 1.35 左右观感最接近经典棋子。
@export_range(0.30, 1.60, 0.01) var graph_stone_scale: float = 1.0
## 终局**领地归属标记**的半径系数：圆点半径 = 该画法下的棋子半径 × 它（下限 2px 保证可见）。
## ★ 2026-10-20 用户口令「终局领地描边改为落子点中心圆形标记，瓷砖模式也这么改」：
##   原来是沿**瓷砖轮廓**描一圈边 —— 在一张"棋盘 = 落子点 + 连线"的盘上，那就是两套线并存。
##   现在两套画法都画**落子点中心的小圆 + 同色邻点连线**（对标腾讯围棋的标点法）。
## ★ 默认 **0.45**（第一版给 0.30 = 与"最后一手提示点"同值，用户实测反馈**太小**）。
##   量级感：标准盘棋子半径 ≈ 27px ⇒ 点半径 ≈ 12px、直径 ≈ 24px vs 格距 54.6px ≈ 0.45 格。
##   再大就会在密处（thin-thin 相邻，间距 54.6）与相邻点相压，所以上限给到 0.80。
@export_range(0.10, 0.80, 0.01) var territory_dot_scale: float = 0.45
## 终局领地**标点**的两种颜色 —— 黑方领地 = 深色点、白方领地 = 白色点
## （2026-10-20 用户口令「学习一下腾讯围棋标点的配色」）。
##
## ★ 腾讯那套的核心不是"给每方配一个好看的色"，而是**归属方的本色**：黑方的空点是深色、
##   白方的空点是白色。之所以在木色盘上也认得出来，靠两件事：
##     ① **点比棋子小得多**（本工程实测 直径 24px vs 棋子 54.6px，1:2.3）；
##     ② **白点自带深色描边**（`_draw_round_stone()` 的 `darkened(0.45)`）。
## ★ 黑方**不用纯黑**：本工程棋子本身就是近黑（`piece_color_black`，还随主题走），
##   标点若也是纯黑就与棋子同色，只剩"大小"一个区分维度。取中深灰 ≈
##   「半透明黑叠在木色盘上」的观感 —— 既保留"黑方 = 深色"的语义，又与实心棋子拉开一档。
## ★ 两者都是 `@export`：换到霓虹 / 赛博这类深底主题时，白点与底色的关系会整个翻面，得就地调。
@export var territory_black_color: Color = Color(0.30, 0.30, 0.33, 0.95)
@export var territory_white_color: Color = Color(0.97, 0.97, 0.97, 0.95)

# ====== 棋盘「盘」（2026-10-20 用户口令「给棋盘一个"盘"的效果（图与面共用），记得采用主题色」）======
## 开 = 棋盘底下垫一块**实体托盘**（凸包外扩 + 下方厚度 + 外轮廓），关 = 退回"直接铺在背景上"。
## ★ 两套画法**共用** `_draw_board_panel()`，同一块盘、同一套配色。
## ★ 颜色取**主题棋盘色**（`board_tile_color` = `GameConfig.board_color`，随主题走）——
##   面模式的瓷砖本来就是它 ⇒ 盘与瓷砖连成一片，观感是"一整块木盘上刻着格子"，
##   而不是"一堆色块飘在背景上"。图模式没有瓷砖面，盘就成了那块承托网格的实体。
@export var board_panel_enabled: bool = true
## 盘比棋盘区域向外扩多少 px（沿顶点凸包均匀外扩，圆角转折）。
## ★ 2026-10-20 用户口令「棋盘大小有点超出窗口了，边界改成现在的一半大就行」⇒ 26 → **13**。
##   加盘之前，棋盘按 `GameConfig.board_margin()`（横 40）缩放；盘再往外扩 26 ⇒
##   物理窗口下盘的上下沿只剩 ~11px（实测 `_shot_盘_面模式.png`：上/下余量各 11 物理像素），
##   看起来就是"盘要出窗口了"。减半 + 让 `_adapt_to_screen()` 把 pad 计入边距（见那里），
##   盘边距窗口恒为 `board_margin()`，与 pad 取值无关 —— 这是结构性的，不靠碰巧。
@export_range(0.0, 80.0, 1.0) var board_panel_pad: float = 13.0
## 盘的下方厚度 px（0 = 纯平板，没有立体感）。
@export_range(0.0, 30.0, 0.5) var board_panel_thickness: float = 7.0
## 盘面色 = **主题棋盘色 × 它**（默认白 = 原样跟随主题；想更暗/更偏色都在这里拧，不动主题）。
@export var board_panel_tint: Color = Color(1, 1, 1, 1)


const PHI: float = (1.0 + sqrt(5.0)) / 2.0

enum Stone { EMPTY, BLACK, WHITE }

# ====== 棋盘数据 ======
# 落子单元 = 菱形瓷砖（棋子落在瓷砖内部）；邻接 = 共享一条边
var vertices: Array[Vector2] = []       # 几何顶点（仅用于渲染瓷砖与边线）
var adjacency: Array = []               # 瓷砖邻接：每个元素是 Array[int]（邻居 tile_id）
var _edge_neighbor: Dictionary = {}     # 共享边缓存：边顶点对(打包int key) -> 邻接瓷砖id（-1=外边界/无邻居）
var board: Dictionary = {}              # { tile_id: Stone }
## 当前行棋方（`Stone.BLACK` / `Stone.WHITE`）。
## ★★ 必须显式写 `: int` —— `var current_player = Stone.BLACK`（漏注解）在 Godot 4 里是
##   **无类型（Variant）**变量，于是**任何**从它做 `:=` 推断的地方都会报
##   `Cannot infer the type of "…" variable because the value doesn't have a set type`。
##   2026-10-04 实测：`--aiterms` 里 `var opp := 3 - current_player` 就这么挂的，
##   而且**整个 game.gd 解析失败 ⇒ 游戏直接打不开**（不是"某个功能坏了"）。
##   ⚠️ `=` 与 `:=` 的区别是本项目最容易静默复发的坑之一：**漏注解不报错，只在下游 `:=` 处炸**。
var current_player: int = Stone.BLACK
var ko_point: int = -1                  # 打劫禁点 = tile_id

# ====== 对局流程（停一手 / 终局）======
var passes := 0                 # 连续停手次数：双方连续停 2 次 → 终局
var game_over := false          # 终局后锁定落子/停手
var black_prisoners := 0        # 黑方提掉的白子数（黑方战果）
var white_prisoners := 0        # 白方提掉的黑子数（白方战果）
## 白方贴目（单位：瓷砖数）。默认 0 = 不贴目；若觉得黑棋先手总占便宜可调大
@export_range(0, 12, 1) var komi: int = 0

# ====== 对局模式（由菜单场景经 GameConfig 单例传入）======
enum { LOCAL, VS_AI, ONLINE }            # LOCAL=本地双人; VS_AI=人机对战; ONLINE=联机对战;
var game_mode: int = LOCAL       # 进入本场景即已开始对局（菜单已选定模式）

## 自检用：对局手数上限（0 = 下到终局）。
## 大盘一局 700 手，随机填充的官子会把结果方差顶到 ±700 目，
## 任何 3% 的机制差异都读不出来。截断在 N 手后用**确定性**面积分判胜负，噪声立刻降一个量级。
var _match_max_moves := 0

## 静默落子日志。自检（--aiablate / --aiself 等）一局几百手，
## 「落子瓷砖 N 成功，提掉 M 子」会把 [aiablate] 汇总行彻底淹没（实测 1440 行里只有 4 行有用）。
## 只影响 print，不影响任何逻辑。
## `_quiet_place`：自检期的**静音开关**。一局几百手 + 穷举对照（`--hovertest` 每个空点试一手，
## 几百次拒绝）会把汇总行彻底淹没 —— 所以落子的成功/拒绝三类日志全归它管，
## 正常对局里它恒为 false，用户看到的提示一个字不少。
var _quiet_place := false
## ★★ 2026-10-27 解耦：`_quiet_place` 原来**同时**管着「静音 print」和「关掉位置超级劫」
##   （`place_stone()` 的 superko 关口写的是 `if not _quiet_place and ...`），而它自己的
##   注释声明是「只影响 print，不影响任何逻辑」—— 声明与实现不符。
##   后果：**所有自弈仪器**（`--aispec` / `--capftest` / `--aiablate` / `--aiself` / `--aibud`）
##   都在**没有位置超级劫**的规则下跑。实锤形态：`--aispec` 120 格盘跑出 `224:1`、`1:227`，
##   而 120 格盘总分要过 200 必须提子 ≥100 ⇒ 只有「反复投子、反复被提」才可能，
##   那正是位置超级劫禁止的循环。
##   ⇒ 拆成独立开关。默认 false = **保留所有既有自弈的自检行为逐字不变**；
##     需要真实规则口径的实验显式打开（`--aispec` 的 `sk` token）。
##   （为什么不用「默认 true」：`_quiet_place` 还被「探测性落子」类自检用（如 `--hovertest`
##     对每个空点试一手），那些路径会把 `_superko_hist` 污染，硬开会在那里误判。）
var _superko_enforce := false

# 瓷砖数据
var tiles: Array = []              # 每个元素是 Array[int]（4 个顶点 idx，环序）
var tile_colors: Array[Color] = []
var tile_centers: Array[Vector2] = []   # 瓷砖中心（落子/棋子绘制点）
var tile_r: Array[float] = []           # 瓷砖内切圆半径（像素）
var _min_tile_r := 0.0                  # 全盘最小内切半径 → 统一棋子基准

# 立方体棋盘（三菱形六边形蜂窝）状态
var _is_cube: bool = false              # 当前棋盘是否为「立方体」棋盘（三面明暗 + 星位）
var _cube_hex_r: int = 4                # 六边形补丁半径（环数）：R 环 → 3R²+3R+1 个六边形 → ×3 块菱形（默认标准=4）
var _cube_star_tiles: Array[int] = []   # 星位（中心 + 六个角六边形各取一块菱形），仅立方体盘非空

# 筝形棋盘（3 块筝形钝角相对拼等边三角形 → 三角格密铺）状态
var _is_kite: bool = false              # 当前棋盘是否为「筝形」棋盘
## 筝形盘的**正六边形环数**：见 @export 的 _kite_r。随机档生成后回填为实际环数。
## 默认与 @export 的 `_kite_r` 保持一致（3 = 标准档 162 格），否则菜单尺寸档改动前
## 首帧会用错的环数（曾写死 2，导致「标准盘」少一圈）。
var _kite_r_actual: int = 3

# 雪花棋盘（Ammann-Beenker 密铺：45° 胖菱形 + 正方形，8 菱形锐角共点成雪花）状态
var _is_snow: bool = false              # 当前棋盘是否为「雪花」棋盘
## 雪花盘的**层数 n**：见 @export 的 _snow_r。由 `_apply_board_size()` 按尺寸档设定
##（迷你 3 / 标准 5 / 加强 6），与 `_kite_r_actual` 同一套「_actual」纪律。
## ⚠️ 随机档不读它（半径由目标格数现算，见 _generate_snowflake_random）。
var _snow_r_actual: int = 4
## 上一次生成时被跳过的「奇异交点」（三线共点）数：固定档恒 0，随机档理论上也是 0，自检盯着
var _snow_last_singular: int = 0

# 爱因斯坦棋盘（帽子家族：帽子 / 海龟 / 幽灵）状态
var _is_hat: bool = false               # 当前棋盘是否为「爱因斯坦（帽子家族）」棋盘
var _hat_kind_used: int = 0             # 本次生成用的种类（GameConfig.HAT_*）——只进日志/自检
## 本次目标落子格数：标准 hat_std_tiles / 加强 hat_big_tiles / 随机 random_target_tiles±jitter
var _hat_target: int = 150
var _hat_pool_size: int = 0             # 本次池的片数（日志 / 启动横幅 / 自检用）
## 选区算法开关：0 = BFS 圆底 + 剔叶片修补（默认，保证最小邻接度 ≥2）；1 = **裸 BFS**。
## ★ 只给自检 ⑤ 的**阴性对照**用 —— 切回 1 必须能重现「度数 1 的尖头」，否则说明探针是瞎的。
var _hat_pick_mode: int = 0
## 剔叶诊断（每次生成时重置）：「轮数」= 实际跑了几轮修补（上限 8）；「禁片数」= 累计剔掉几片；
## 「撤回」= 1 表示某轮补不回 n_target、不得已把叶片放了回去（此时最小度可能仍为 1）。
var _hat_trim_passes: int = 0
var _hat_trim_banned: int = 0
var _hat_trim_aborted: int = 0
## 「选区平滑」换片次数（每次生成时重置）：等量换片把凹口填平 / 凸角削圆的次数。
var _hat_round_swaps: int = 0
## 选区平滑开关：0 = 开（默认）；1 = **关** —— 只给自检做阴性对照
##（关掉后同种子填充率必须不变好，否则说明平滑器没在干活）。
var _hat_round_mode: int = 0
var _hat_seed_tile: int = -1            # 本次种子片（池索引；固定档恒为「离池形心最近」那片）
var _hat_rot_deg: float = 0.0           # 本次整盘朝向（只有随机档会转，固定档恒 0）

# 随机棋盘（「随机」档）状态
## 随机棋盘的种子：整张盘面由它唯一决定。单机每局重掷；联机由房主下发（保证双方同一张盘）。
## 用 RandomNumberGenerator 而非全局 randi()，是为了让「盘面生成」与「对局中的随机流」互不干扰，
## 也让同一颗种子必定复现同一张盘（自检 --randtest 与 --boardseed=N 都依赖这一点）。
var _rand_seed: int = 0
var _rand_target: int = 0               # 本次实际抽到的目标格数（HUD / 日志展示用）

# ====== 落子 / 提子动画 ======
const STONE_ANIM_TIME: float = 0.3   # 落子落下、提子消散的时长（秒）
var _place_anims: Dictionary = {}    # { tile_id: 剩余时长 } 落子下落动画
## { tile_id: {"time_left","delay","color","wave","wave_max"} } 提子消散动画。
## `delay` = 等落子动画走完 + 本颗所在**波前层**的起手偏移（见 `_capture_wave_start()`）；
## `wave` / `wave_max` = 层号与最深层层号（留档给自检断言顺序，不靠反推 delay）。
var _capture_anims: Dictionary = {}
var _last_move: int = -1             # 上一步落子的瓷砖索引（含 AI/玩家），-1 表示无

# ====== 悔棋（2026-10-02 用户口令「AI 对战可以自由悔棋一手，联机则需要发送请求双方同意」）======
## 落子历史栈：每一项 = **撤销这一手所需的最小信息集**。
## 为什么不能靠盘面反推：`ko_point` / `passes` / `_last_move` 三个状态在落子时会被**覆写**，
##   而盘面本身推不出它们 ⇒ 必须显式存档，否则回滚后这三样会残留成"这一手之后"的值
##   （症状：悔完棋劫点还是劫点 → 玩家被禁止在明显合法的点落子，且**没有任何提示**）。
## 每项字段：
##   `tile`          这一手落在哪
##   `color`         谁落的（回滚后行棋权交回给他）
##   `captured`      被提掉的白子/黑子（回滚时**要放回盘面**，颜色 = color 的对方）
##   `ko_before` / `passes_before` / `last_move_before`  三个被覆写状态的本手之前值
##   `pass_move`     true = 这一项其实是「停一手」而非落子（停一手也消耗一次机会）
## ★ 探测性落子（`_quiet_place`，自检里试手用）**不入栈** —— 否则自检跑几百手会攒出
##   一条假历史，真悔棋时回滚到一个谁也没下过的局面（理由同 `_last_move` 不记它）。
var _hist: Array[Dictionary] = []

# ====== 棋谱（2026-10-02，棋谱阶段① ：数据层 + 记账）======
## 当前这一局的棋谱（`GameRecord` 的字典形态，见 `record.gd`）。逐手追加，终局时落盘。
## ★★ 它与 `_hist` 是**两条各自独立的记账链**，故意不合并成一条：
##   · `_hist`  = 悔棋用的**最小信息集**（要能无损回滚：含 ko_before / passes_before / …）
##   · `_record` = 棋谱用的**复现信息集**（要能重放：含本手**之后**的劫点、提子数…）
##   两者的字段口径**故意不同**（`ko_before` vs `ko`）⇒ `--grecotest` 才能拿它们**逐字段对拍**：
##   如果只有一条链，"谱记对了"与"悔棋回滚对了"会互相掩盖（同一份数据自证）。
var _record: Dictionary = {}
## 棋谱的生成器指纹（拼盘型 + 所有影响几何的参数）。写进每份谱头：
##   "几何由种子决定"**只对同一个游戏版本成立** —— 将来改了生成器（哪怕只调一个 ε），
##   旧棋谱会重放出**不同甚至崩掉**的盘 ⇒ 复盘器将来要按它拒绝加载（阶段②）。
var _record_gen_fp: String = ""
## ★★ 复盘器（棋谱阶段②）。**状态全部收在 `replay.gd` 里**，这里只留两个"让路闸"：
##   ① `_replay` 非空 = 复盘中 ⇒ 阻断 AI 走子 / 联机收包 / 悔棋 / 终局记账
##   ② 复盘构造盘面时由 `replay.gd` 自行开关 `_quiet_place`（探测性落子不入 `_hist`）
## 为什么不让复盘直接改这些成员：漏判一个的症状是"复盘完开新局看到旧手数"这类**静默**鬼 bug。
var _replay: GameReplay = null
## 复盘里的落子**不播离位动画**（否则拖手数滑条时满屏砖块乱飞）。
## ★ 这条闸只关"视觉动画"，**不关**盘面重建 —— 重建必须走 `place_stone()` 真实路径。
@export var replay_anim_enabled: bool = true
## 连续播放速率（手/秒）。用户口径「数值一律 @export，运行期可实时调」。
@export_range(0.5, 60.0, 0.5) var replay_plays_per_sec: float = 10.0
## 联机悔棋次数上限（每局）。用户口径「AI 无限、联机限 3 次/局」。
const UNDO_LIMIT_ONLINE: int = 3
## 已用悔棋次数（按颜色分开记：联机双方各 3 次，不是合起来 3 次）
var _undo_used: Dictionary = {}
## 联机：悔棋请求的当前状态。`pending` = 有请求在飞；`null` = 无请求。
##   请求期间**锁住发起方的悔棋按钮**（连点会发第二个请求，对方面板会打架）。
var _undo_pending_from: int = -1     # 谁发起的请求（-1 = 无）
## 请求在飞时冻结落子：悔棋要撤的是「上一手」，对方在这期间落子会让回滚语义错乱
var _undo_freeze: bool = false
# 悬浮预览（2026-09-29 用户口令「鼠标悬浮出现半透明瓷砖，落子就是它向下落下」）：
# 鼠标停在**可落子的空瓷砖**上时画一块半透明瓷砖；落子动画的起手状态与它同貌（同一透明度、
# 同一块瓷砖），视觉上就是「预览那块砖落下来变成棋子」。
var _hover_tile: int = -1            # 当前悬浮的瓷砖索引（-1 = 不在任何瓷砖上）
var _anim_freeze: bool = false       # 仅供截图自检（--shotdrop）：冻结动画推进以便截到半途
@export_group("悬浮预览与落子下落")
## ★ 只有两个**高度/透明度**旋钮，且**悬浮高度与下落高度是同一个值**（`_drop_height()`）——
##   这样「预览那块砖」与「落下来的砖」起手状态逐位相同，调整时也不会一边高一边低。
## ★★ 2026-09-29 用户口令「预览动画侧边改成半透明，预览棋子改成不透明」：
##   本旋钮的**默认值由 0.45 改成 1.0**（顶面不透明）—— 厚度感现在由**侧壁**独立承担
##   （见 `hover_side_alpha`），不再需要靠顶面半透明"透出底下那块砖"来表达"这是预览"。
##   旋钮仍留着：调小它就退回"半透明预览"的旧观感（`--hovertest` ⑦ 会在旋钮 <1 时
##   额外断言透明度真的在爬升，所以这个旋钮不会变成死参数）。
@export_range(0.0, 1.0, 0.01) var hover_preview_alpha: float = 1.0  ## 悬浮预览瓷砖顶面的不透明度
@export_range(0.0, 3.0, 0.05) var drop_height_ratio: float = 0.6     ## 悬浮/下落高度 = 最小砖内切半径 × 本值
## 预览块的**侧壁**压暗幅度 —— 厚度感就来自这里（见 `_hover_side_walls()`）。
## ★★ 2026-09-29 用户口令「虚线不好看，改成整个侧边，体现出厚度感」：逐顶点对齐虚线**整条删掉**，
##   改成把预览块从落点一路"竖"上来，那圈侧面即侧壁 ⇒ 它本来就是一块有厚度的板材，
##   同时**侧壁底边 == 落点轮廓**，虚线原来唯一的职责（"会落到哪一格"）由它顺带承担，还更硬更准。
## 侧壁色 = 当前方棋子色 `.darkened(本值)`（暗面），取 0 = 与顶面同色（厚度就看不出来了）。
@export_range(0.0, 1.0, 0.05) var hover_side_darken: float = 0.35
## **侧壁的不透明度**（顶面用 `hover_preview_alpha`，侧壁单独一个旋钮）。
## ★★ 口径变过两次，两次都是用户口令，**两次都保留了旋钮**（只改默认值，绝不删参数）：
##   · 更早：侧壁被**刻意钉成不透明**（`w.a = 1.0`），理由写的是"相邻边的侧壁在窄角处会
##     重叠、半透明叠两次出深斑"。实测（`--hovertest` ⑨ 的邻接口径）**凸多边形上不成立**：
##     沿同一方向平移时每两条边的侧面四边只**共一条竖棱**（面积重叠为 0）；只有凹砖
##     （帽子/爱因斯坦族）在凹顶点附近叠出一道略深的竖痕，可接受 ⇒ 这个理由被推翻、放开成旋钮。
##   · 2026-09-29（第一轮）「预览动画侧边改成半透明」⇒ 默认 0.5。
##   · 2026-09-29（第二轮）用户看到实物后改成「棋子…要改成**完全不透明**才好」⇒ 默认回到 **1.0**。
##     半透明的代价是**真的能看见背后的盘面**（侧壁那圈是 50% 混合，实测白鬼影的墙裙下沿
##     是"盘色 + 侧壁色"各一半）——用户口径是"棋子不要透，后面的棋盘边界不许露出来"。
## 取 0 = 侧壁全透明（只剩顶面，厚度感消失）；取 1 = 不透明侧壁（当前默认）。
## ⚠️ 判据已随口径一起翻面（`--hovertest` ⑧ / `--settest`）：钉的是"不透明"（≥0.999）**且**
##    保留**敏感性对照**（拧 0 → 必须 0.00；拧 1 → 必须 1.00）—— 只钉默认值就是同义反复。
@export_range(0.0, 1.0, 0.05) var hover_side_alpha: float = 1.0
## **落点轮廓线**宽度倍数（侧壁底边那一圈硬边）：让"落在哪一格"有个硬判据，不靠眼力。
## ★ 它取代了原来那条"线宽 × 1.4 + alpha 0.8"的对齐虚线口径（同色系可见性那套调参**已作废**）；
##   取 0 = 不画轮廓（只剩侧壁自身的边界）。
@export_range(0.0, 2.0, 0.05) var hover_foot_line: float = 1.0

@export_group("提子动画")
## 一手提多子时，**整段提子过程的总时长上限**（秒）：从第一颗开始升空，到最后一颗散尽。
## ★★ 2026-09-29 用户口令「一次提走多个棋子时，从对方所下棋子旁边的子开始被提走，接着它旁边的子
##   被提走，依次提子直到全部提完；整个提子过程限制在一定时间内」——两件事分别落在两处：
##   ① **谁是第一颗** = 按"离刚落那一手的距离"分层（`_capture_depths()`：BFS 一层 = 一波），
##      第 0 层就是贴着刚落那手的子；一层接一层往外推；
##   ② **总时长封顶** = 分层只摊开**起手时刻**，而摊开的总跨度恒为 `本值 - STONE_ANIM_TIME`
##      （`_capture_wave_start()`：按层号/最大层号**归一化**）⇒ **串再长，整段提子也只用这么久**。
##      ★ 归一化那一步是全部关键：少了它，20 层长龙会拖成 20 倍时长（阴性对照 M24 守这一条）。
## ★ 取 `STONE_ANIM_TIME`(=0.3) 时跨度为 0 ⇒ 所有被提的子**同时**升空 = 本需求之前的旧观感。
##   于是这一个旋钮就够：拉到 0.3 是"齐提"、拉大是"一层层提"，不用再开一个开关。
## ⚠️ 有**地板** = `STONE_ANIM_TIME`（小于它连一颗都放不完），由 `_capture_total_time()` 兜住。
@export_range(0.3, 3.0, 0.05) var capture_total_time: float = 0.75

# AI 相关
const PLAYER_COLOR = Stone.BLACK
const AI_COLOR = Stone.WHITE
var is_ai_thinking: bool = false
# AI 思考代次：每次重置/重建棋局 +1。AI 是异步搜索的，思考期间若棋局已重置，
# 协程醒来发现代数不符就丢弃结果，避免把旧局的着法落到新局上
var _ai_gen: int = 0
var ai_engine: AIEngine = null
## 「流水」档的引擎实例（2026-10-22）。与 `ai_engine` **互斥**：同一局只会有一个是非 null。
## ★ 为什么不是把 `ai_engine` 改成无类型：那会让全工程 20+ 处 `ai_engine.xxx` 失去类型检查，
##   而其中一半是自检路径的探针（写错字段名从"当场 Parse Error"退化成"运行时静默 Invalid"）。
var ai_liushui: LiushuiAI = null
## 「野马」档的引擎实例（2026-10-23）：神经网络先验 + 磐石搜索（`ai_engine_yema.gd`）。
## ★ 它内部**自己持有一个 `AIEngine`**（做读深搜索），与外层 `ai_engine` 是两个独立实例。
##   刻意不共享：外层 `ai_engine` 被 20+ 处自检路径当"磐石本体"读写（改预算、读 playouts、
##   `--jevdump` 导先验），若野马复用它，野马档下那些探针读到的就会是"被注入过外部先验的"
##   磐石 ⇒ 磐石的自检基线悄悄失效。多一个实例只多几千字节缓冲。
var ai_yema: YemaAI = null

## AI 每手思考时长（毫秒）。这不是难度档位，是性能/延迟旋钮；
## 引擎无等级之分，始终全力搜索，给的时间越长越强。@export 可调
@export var ai_time_ms: int = 200


# ====== AI 主动认输（极度劣势时不再陪着收完官子）======
## 总开关。判据见 `_ai_resign_eval()`：连「剩余空点全归自己」这个乐观上限都追不平才认输
@export var ai_resign_enabled: bool = true
## 安全余量 = 棋盘格数 × 该比例。留出提子 / 劫争可能带来的翻转空间，宁可少认也不误认
@export_range(0.0, 0.5, 0.01) var ai_resign_margin_ratio: float = 0.12
## 至少已落「格数 × 该比例」手才允许认输：开局盘面空旷时形势估计不可靠，避免早早乱认
@export_range(0.0, 1.0, 0.05) var ai_resign_min_stones_ratio: float = 0.30


var click_area: Area2D

# ---------- 初始化 ----------
## 自检/调试参数：把 `OS.get_cmdline_args()`（`--` 之前的）与
## `OS.get_cmdline_user_args()`（`--` 之后的）**合并**后返回。
##
## 为什么要合并（踩过两次的坑）：同一个 `--aibud=...` 放在 `--` 前还是后，会落进两个不同的列表。
## 只看 `get_cmdline_args()` 时，`godot res://game.tscn -- --aibud=...` 这种写法会被**静默忽略** ——
## 场景照常启动、不报任何错、也不进自检，表现为「自检莫名卡死」，实测为此空烧了 25 分钟。
## 合并之后两种写法都能命中，这个坑就不存在了。
func _argv() -> PackedStringArray:
	var out := OS.get_cmdline_args()
	out.append_array(OS.get_cmdline_user_args())
	return out

## 前缀命中（`--名` 或 `--名=参数…` 都算命中）。
## 为什么要有它：`"--aiprof" in _argv()` 是**精确相等**匹配 ⇒ 一旦给这个自检加了
## 参数写法（`--aiprof=m90`），派发点就**静默不命中**：游戏照常启动、不打印、
## 不退出（实际表现是"卡死"，2026-10-27 为它空等 180 秒）。
## 凡是带参数的仪器，派发一律走本函数（§96 同族：exit=0 / 无输出 ≠ 跑到了）。
func _argv_has_prefix(p: String) -> bool:
	for a in _argv():
		if a == p or a.begins_with(p + "="):
			return true
	return false

func _ready():
	# ★ 2026-10-18 规则内核拆分：_rk 必须在**一切**自检/对局路径之前就绪
	#   （--rulestest/--xgtest 等自检与 reset_game 都跑在本 _ready 里）。
	_rk = RulesKernel.new()
	_rk.host = self
	randomize()   # 未播种时 randi() 每次运行序列相同（影响随机兜底着法/AI 加砖）
	# 模式、棋盘大小、AI 时长由菜单场景写入 GameConfig 单例；直接打开本场景时兜底
	# 联机自检测试：命令行带 --onlinetest 时强制以房主身份进入联机自环
	# ★ 2026-09-30 §24 第 5 步：`--nettest-host/-client`（ENet 双进程）、`--matchtest-host/-client`
	#   与 `--relaytest-*`（邀请）、`--mqtest-*`（快速匹配）四条入口**已全部删除** ——
	#   它们背后是自建信令服（`matchmaking_server.js`）与 ENet/RPC 两条路，随自建联机一起下线。
	#   ★ `--onlinetest` **保留**：它不进网络，只单进程直呼 `_apply_action` 验权威路径，
	#     不受通道影响（判据 `_self_test_online()`，见文件后半）。
	var _args := _argv()
	if "--onlinetest" in _args:
		GameConfig.online = true
		GameConfig.is_host = true
		GameConfig.mode = GameConfig.ONLINE
	elif "--cubetest" in _args:
		GameConfig.board_type = GameConfig.BOARD_CUBE
		if "--cuberand" in _args:
			GameConfig.board_size = GameConfig.RANDOM
		elif "--cubebig" in _args:
			GameConfig.board_size = GameConfig.ENHANCED
		else:
			GameConfig.board_size = GameConfig.STANDARD
	elif "--kitetest" in _args:
		GameConfig.board_type = GameConfig.BOARD_KITE
		if "--kitebig" in _args:
			GameConfig.board_size = GameConfig.ENHANCED
		elif "--kitemini" in _args:
			GameConfig.board_size = GameConfig.RANDOM   # 筝形下 RANDOM 槽位 = 迷你固定盘
		else:
			GameConfig.board_size = GameConfig.STANDARD
	elif "--snowtest" in _args:
		GameConfig.board_type = GameConfig.BOARD_SNOWFLAKE
		if "--snowbig" in _args:
			GameConfig.board_size = GameConfig.ENHANCED
		elif "--snowmini" in _args:
			# 雪花 2026-09-16 起 RANDOM 槽位是**随机档**，不再是迷你固定盘；
			# 迷你（n=3 / 72 格）改在下面 _apply_board_size() 之后直钉 _snow_r_actual
			GameConfig.board_size = GameConfig.STANDARD
		else:
			GameConfig.board_size = GameConfig.STANDARD
	elif "--hattest" in _args:
		GameConfig.board_type = GameConfig.BOARD_HAT
		if "--hatbig" in _args:
			GameConfig.board_size = GameConfig.ENHANCED
		else:
			GameConfig.board_size = GameConfig.STANDARD
	# 调试/截图用：--board=penrose|cube|kite|snow|hat|turtle|spectre 覆盖棋盘类型
	#（须放在 -- 之后，常与 --screenshot 搭配）。turtle/spectre 是「爱因斯坦」大类的后两种种类，
	# 等价于 --board=hat --hatkind=turtle|spectre，只是打字更短。
	for ua in _argv():
		if ua.begins_with("--board="):
			match ua.substr(8):
				"cube": GameConfig.board_type = GameConfig.BOARD_CUBE
				"kite": GameConfig.board_type = GameConfig.BOARD_KITE
				"snow": GameConfig.board_type = GameConfig.BOARD_SNOWFLAKE
				"hat": GameConfig.board_type = GameConfig.BOARD_HAT
				"turtle":
					GameConfig.board_type = GameConfig.BOARD_HAT
					GameConfig.hat_kind = GameConfig.HAT_TURTLE
				"spectre":
					GameConfig.board_type = GameConfig.BOARD_HAT
					GameConfig.hat_kind = GameConfig.HAT_SPECTRE
				_: GameConfig.board_type = GameConfig.BOARD_PENROSE
	# 调试：--hatkind=hat|turtle|spectre 选爱因斯坦大类的种类（只对 --board=hat 系列有意义）
	for ua in _argv():
		if ua.begins_with("--hatkind="):
			match ua.substr(10):
				"turtle": GameConfig.hat_kind = GameConfig.HAT_TURTLE
				"spectre": GameConfig.hat_kind = GameConfig.HAT_SPECTRE
				_: GameConfig.hat_kind = GameConfig.HAT_HAT
	# 调试：--boardseed=N 固定随机棋盘的种子（同种子必得同一张盘，用于复现与自检）
	#       --sizerand / --sizebig 直接切到「随机」/「加强」档（截图与单盘核对用）；
	#       筝形盘无随机档，--sizerand 在筝形下即「迷你」固定盘（见 _apply_board_size）
	for ua in _argv():
		if ua.begins_with("--boardseed="):
			_rand_seed = int(ua.substr(12))
		elif ua == "--sizerand":
			GameConfig.board_size = GameConfig.RANDOM
		elif ua == "--sizebig":
			GameConfig.board_size = GameConfig.ENHANCED
	# ★ Steam 路径（`--steamhost` / `--steamjoin=<id>` / 自检 `--steamnet`）必须在**下面两处之前**
	#   把状态摆好，否则根本进不了联机分支：
	#     ① 第 400 行 `game_mode = GameConfig.mode` —— 必须是 ONLINE；
	#     ② 第 420 行 `if GameConfig.online and not _start_network()` —— 必须为真，
	#        而且它是在**调用前**求值的（写进 `_start_network()` 里就晚了，那一frame 进不去）。
	#   第 3 步的菜单「联机方式」接上后走的是同一条分支，这三行由菜单侧的选择填充。
	if _use_steam():
		GameConfig.mode = ONLINE
		GameConfig.online = true
		GameConfig.is_host = str(_steam_arg()["role"]) == "host"
	# ⚰️ 2026-10-13 墓碑（名字不许回收）：这里原有 `--ludii` 调试 flag
	#   （强制以 LUDII 模式开局，用来 headless 验证「从菜单点 Ludii」那条路 ——
	#    因为菜单点按钮这条路 headless 下点不到）。Ludii 整族删除后它没有语义，删。
	# 自检：--liushuitest 要走**真实的接入路径**才能验到东西 —— `ai_liushui` 是 `_ready`
	#   后面按 `liushui_play_mode` 建的，所以标记必须在**下面那一行之前**设好。
	#   ⚠️ 放在菜单之后不动：菜单开局会无条件覆盖写这两个字段（`_start_from_setup()`），
	#      自检没有菜单，只能自己摆。`--liushuitest` 只在本分支生效。
	if "--liushuitest" in _args:
		GameConfig.mode = VS_AI
		GameConfig.liushui_opponent = true
	# 自检：--yematest 野马档（神经网络先验 + 磐石搜索）在**真实盘**上接得上（2026-10-23）
	#   ★ 与上面 `--liushuitest` **逐字同构**：`ai_yema` 是 `_ready` 后面按 `yema_play_mode`
	#     建的，所以标记必须在这一行之前摆好。自检没有菜单，只能自己摆。
	#   ⚠️ 三个标记互斥由菜单的 `_sel_mode` 单值保证；若同时给多个 flag，
	#     `yema_play_mode` 的派生式里（`not xg_play_mode and not liushui_play_mode`）
	#     会让老档优先 ⇒ 本条**会看到 `ai_yema == null` 并报红**，这是对的（不许静默）。
	if "--yematest" in _args:
		GameConfig.mode = VS_AI
		GameConfig.yema_opponent = true
	var start_mode: int = GameConfig.mode
	if start_mode != LOCAL and start_mode != VS_AI and start_mode != ONLINE:
		start_mode = LOCAL
	game_mode = start_mode
	# ★ 疾风档（2026-10-14 立项为「测试AI」，**2026-10-15 转正定名"疾风"**）：
	#   主菜单「对战方式·疾风」= VS_AI + 骨架标记；白方不走 ai_engine
	#   （`_start_ai_turn()` 的 `xg_play_mode` 分支）。普通档恒 false。
	xg_play_mode = GameConfig.xg_opponent and game_mode == VS_AI
	# ★ 流水档（2026-10-22）：与疾风同构 —— 菜单写 `VS_AI` + `liushui_opponent`，
	#   白方不走生产引擎而走渗流引擎。三档互斥由菜单保证（`_sel_mode` 单值），
	#   这里再加一道 `and not xg_play_mode` 防御：万一两个标记同时为真，
	#   **疾风优先**（它是先有的档，行为不许被新档改变）。
	liushui_play_mode = GameConfig.liushui_opponent and game_mode == VS_AI and not xg_play_mode
	# ★ 野马档（2026-10-23）：与上两档**逐字同构**。优先级刻意排在最后
	#   （`not xg_play_mode and not liushui_play_mode`）—— 万一三个标记同时为真，
	#   老档优先。理由与流水那条一样：新档不许改变老档的行为，哪怕在"不可能发生"的状态下。
	yema_play_mode = GameConfig.yema_opponent and game_mode == VS_AI \
		and not xg_play_mode and not liushui_play_mode
	if GameConfig.ai_time_ms > 0:
		ai_time_ms = GameConfig.ai_time_ms
	_apply_board_size(GameConfig.board_size)   # 根据菜单选择的尺寸设定迭代次数/裁剪半径
	# 「迷你」固定档（n=3 / 72 格）现在没有尺寸槽位可用（RANDOM = 随机档），只能直钉层数
	if "--snowmini" in _args:
		_snow_r_actual = 3
	_apply_appearance()                        # 应用设置页选的配色（背景 / 瓷砖 / 边线 / 立方体三面）

	# 自检（--apprt，外观·对局往返）：菜单侧在等这一趟 —— 进对局后**立刻**返回菜单。
	# 它验的是「过了对局一趟，主题会不会被回写成默认」（2026-09-27 用户报）。
	# ★ 必须放在 `_apply_appearance()` **之后**：对局自己那一读 `load_appearance()` 才是被测对象。
	if "--apprt" in _args:
		_apprt_back_to_menu()
		return

	# 联机：启动网络（房主建服 / 加入连服）；失败则回到菜单
	if GameConfig.online and not _start_network():
		return

	# ★★ 棋谱复盘交接 · **第一段**（必须在 `generate_board()` **之前**）：
	#   先把谱头声明的那张盘（盘型/尺寸/种子）切换好，再建盘。
	#   ⚠️ 顺序是**语义**不是风格：指纹里编 `board_type`/`board_size`，而盘一旦生成完就改不动了
	#   （改了要重跑 `generate_board()` + `_adapt_to_screen()` + `ai_engine.setup(adjacency)`）。
	#   ★ 放在这里还有个附带好处：**不额外调一次 `reset_game()`**。
	#     `reset_game()` 会 `_record_close_if_unfinished()` ⇒ **真的落盘一条 INTERRUPTED 谱**
	#     ⇒ 每进一次复盘就在库里塞一条垃圾。晚一步切盘就得多 reset 一次。
	var pend_id: String = GameConfig.take_pending_replay()
	var pend_rec: Dictionary = {}
	if pend_id != "":
		pend_rec = GameRecord.load_by_id(pend_id)
	replay_apply_board_spec(pend_rec)
	# 按菜单选择的棋盘类型生成对应棋盘（随机档在生成前先抽种子，保证「每局一张新盘」）
	if _is_random_board() and _rand_seed == 0:
		_rand_seed = _fresh_seed()
	generate_board()   # ★ 谱头切盘**之后**才建盘（顺序由 S85/S86 守）
	_adapt_to_screen()              # 自适应缩放居中
	if "--cubetest" in _args:
		_cube_self_check()
	_setup_click_detection()
	# 棋钟内核（2026-10-16）：**必须在 `reset_game()` 之前** —— reset 要把它一起归零。
	_build_clock()
	reset_game()
	# ⚰️ 2026-10-13：这里原有 `_build_tuning_ui()`（TAB 运行时调参面板），面板整块删除。
	_build_ai_hud()
	_build_game_hud()
	# 复盘 HUD（棋谱阶段② 交互层）：**只建一次**，复盘进出只翻 `visible`。
	# ⚠️ 必须在这里（`_ready` 里）建：`--browsetest` 等自检直接调 `replay_enter()`，
	#    那时若控件还没建，交互层判据就量不到任何控件 —— 而"量不到"极容易被写成恒真式。
	_build_replay_hud()
	ai_engine = AIEngine.new()
	ai_engine.setup(adjacency, AI_COLOR)
	ai_engine.time_budget_ms = ai_time_ms
	if ai_engine:
		ai_engine.time_budget_ms = ai_time_ms
		ai_engine.threads = GameConfig.ai_threads
		ai_engine.root_width = GameConfig.ai_root_width
		# ★★ 贴目必须传给引擎（2026-10-02）：否则 AI 的终局评估按 0 目算，
		#   而游戏侧 `_compute_scores()` 把 komi 算进白方总分 ⇒ **两边不同源**，
		#   白方贴目时 AI 不知道自己有便宜，会在该收官时乱冲、该止损时不认。
		_sync_komi_to_engine()
	# ★ 2026-10-22 流水档：额外建一个**渗流引擎** `LiushuiAI`（`ai_engine_liushui.gd`）。
	#
	#   ⚠️ 为什么 `ai_engine` **照样建、不设 null**：全工程 20+ 处 `if ai_engine:`、`_sync_komi_to_engine()`、
	#      `--aibud`/`--jevdump` 等自检路径都隐含"磐石引擎永远非空"。让它在流水档里空着，
	#      等于给这条前提开一个洞，而洞只在**实战才走到的那条**上暴露 ⇒ 典型静默缺陷。
	#      代价只是几千字节缓冲，换来的是"新档结构上不可能弄坏旧档"。
	#   ⚠️ 与 `xg_play_mode` 的关系：疾风档**不建**它（`liushui_play_mode` 已含 `not xg_play_mode`），
	#      所以三档实例分布是 —— 磐石：只有 ai_engine；疾风：只有 ai_engine（但白方走骨架）；
	#      流水：ai_engine + ai_liushui（白方走后者）。
	if liushui_play_mode:
		ai_liushui = LiushuiAI.new()
		ai_liushui.setup(adjacency, AI_COLOR)
		ai_liushui.time_budget_ms = ai_time_ms
		ai_liushui.root_width = GameConfig.ai_root_width
		_sync_komi_to_engine()
	# ★ 2026-10-23 野马档：再建一个**神经网络先验引擎** `YemaAI`（`ai_engine_yema.gd`）。
	#
	#   ⚠️ 同上，`ai_engine` 照样建、不设 null。四档实例分布：
	#     磐石：只有 ai_engine（白方走它）｜疾风：只有 ai_engine（白方走骨架）
	#     流水：ai_engine + ai_liushui（白方走后者）｜野马：ai_engine + ai_yema（白方走后者）
	#   野马内部还有一个自己的 `AIEngine`，所以野马档实际有 3 个引擎实例 —— 全都很轻
	#   （AIEngine 的主要开销是 ballot 缓冲，几万字节），换来的是"新档结构上不可能弄坏旧档"。
	#
	#   ⚠️ 权重加载失败时**不静默降级**：`YemaAI.allow_fallback_to_panshi` 默认 false，
	#     `choose_move` 会 push_error 并返回 -1（停一手）。宁可看见野马不下棋、
	#     也不要人以为在下野马其实在下磐石 —— 后者没有任何可观测迹象。
	if yema_play_mode:
		ai_yema = YemaAI.new()
		ai_yema.setup(adjacency, AI_COLOR)
		ai_yema.time_budget_ms = ai_time_ms
		ai_yema.root_width = GameConfig.ai_root_width
		_sync_komi_to_engine()
	# ⚰️ 2026-10-13 修一个**我自己刚犯的** bug（删 Ludii 留下的孤儿语句）：
	#   这里原有 `if game_mode == LUDII and not _start_ludii_bridge(secs):` 以及缩进一层的
	#   `return`。删桥时我把 `if` 那一行删掉了、**把 `return` 留下了** ⇒ 它变成了上面
	#   `if ai_engine:` 的语句体 ⇒ `_ready()` **无条件提前返回** ⇒ 本行以后的东西
	#   （启动横幅 + **全部游戏侧自检分派**）全成了**死代码**。
	#   症状隐蔽到极点：语法完全合法、`--quit` 下 `exit=0`、零 Parse Error、零 SCRIPT ERROR
	#   —— 三条常规闸门全绿。只有 `--passtest` 这类真自检会**一个字都不打印然后挂死**
	#   才露出来（实测 `exit=124`）。★ 这条正好证明铁律「exit=0 ≠ 通过」还要再加一层：
	#   **"跑到了"也要单独验**。防线已补进 `regress.sh` 冒烟：断言启动横幅必须出现在
	#   `smoke_game.log` 里（`_ready()` 只要提前返回，横幅就没了 ⇒ 当场红）。
	var mode_name := "本地双人" if game_mode == LOCAL \
		else ("联机对战" if game_mode == ONLINE else "人机对战")
	var board_name := "彭罗斯"
	if GameConfig.board_type == GameConfig.BOARD_CUBE:
		board_name = "立方体(蜂窝六边形)"
	elif GameConfig.board_type == GameConfig.BOARD_KITE:
		board_name = "筝形(三角格)"
	elif GameConfig.board_type == GameConfig.BOARD_SNOWFLAKE:
		board_name = "雪花(A-B密铺)"
	elif GameConfig.board_type == GameConfig.BOARD_HAT:
		board_name = "爱因斯坦·" + _hat_kind_name(GameConfig.hat_kind) + "(帽子家族)"
	var size_txt := "随机（%d 格 / 种子 %d）" % [tiles.size(), _rand_seed] if _is_random_board() \
		else _board_size_name(GameConfig.board_size)
	if not _is_random_board():     # 随机档一律用上面那行「随机（N 格 / 种子 S）」，不再叠环数/层数
		if GameConfig.board_type == GameConfig.BOARD_CUBE:
			size_txt = "%s（%d 环 / %d 格）" % [_board_size_name(GameConfig.board_size), _cube_hex_r, tiles.size()]
		elif GameConfig.board_type == GameConfig.BOARD_KITE:
			size_txt = "%s（%d 环 / %d 格）" % [_board_size_name(GameConfig.board_size), _kite_r_actual, tiles.size()]
		elif GameConfig.board_type == GameConfig.BOARD_SNOWFLAKE:
			size_txt = "%s（%d 层 / %d 格）" % [_board_size_name(GameConfig.board_size), _snow_r_actual, tiles.size()]
		elif GameConfig.board_type == GameConfig.BOARD_HAT:
			size_txt = "%s（%d 格 / 池 %d 片）" % [_board_size_name(GameConfig.board_size), tiles.size(), _hat_pool_size]
	# 启动横幅：思考预算一档（Ludii 退役后只剩 `ai_time_ms` 一个真源）
	print(board_name, "围棋已启动。模式：", mode_name, " | 棋盘：", size_txt,
			" | AI 思考预算：", ai_time_ms, " ms")
	_update_hud()  # 显示对局内 HUD
	# ★★ 棋谱复盘交接 · **第二段**（菜单「棋谱」面板点某条谱 → 本场景）。
	#   ★ 交接是**两段式**：第一段在建盘之前（切盘，见上文），这一段是"真正进复盘"。
	#   ★ 这一段的位置**必须在 `_update_hud()` 之后**。
	#   为什么：`_update_hud()` 末段在非联机态下**无条件**把 `_hud_layer.visible` 置真，
	#   而进复盘要 `_show_replay_hud(true)` 把对局 HUD 隐掉。顺序反了（先隐后显）的后果是
	#   **两块 HUD 同时挂在屏上** —— 复盘工具条压在对局按钮上，且不报任何错，只有看图才发现。
	#   ★ 取走 + 清空是同一次调用（`take_pending_replay()`）：清了就不会"回菜单再进对局又进复盘"。
	#   ↑ 那次调用**已经在建盘之前做掉**（第一段，见上文），这里直接用缓存的 `pend_rec`。
	#   ⚠️ 别在这里再调一次 `take_pending_replay()`：它已经清了，第二次只会拿到空串，
	#      于是"点了谱却什么都没发生"（而且连失败提示都走不到 —— 静默失效）。
	# ★ `pend_id != ""` 而 `pend_rec` 为空 = 谱文件被删了 ⇒ 也要走下面那句失败提示。
	if pend_id != "" and not replay_enter(pend_rec):
		# 加载失败（谱文件被删了 / 生成器指纹与当前版本不符）：**留在对局模式，但必须说出来**。
		# 那条 `push_warning` 在正式版看不见，玩家只会觉得"点了没反应"。
		# ★ 写进 `_hud_override`（覆盖层）而不是直接写 label：`_start_ai_turn()` 会无条件
		#   `_update_hud()` 重写 `_hud_turn_label`，直接写会被**下一帧刷掉**（人机 + AI 执黑
		#   + 从菜单点坏谱三事同时发生时现形）。覆盖层在 `_update_hud()` 里**优先于**轮换文案。
		_hud_override = "这条棋谱加载失败（已删除或与当前版本不符）"
	# 若人机模式且 AI 执先手（理论兜底），触发 AI 起手
	# ★ `and _replay == null`：正在复盘时**不许** AI 落子 —— 复盘盘面是"重放的过去"，
	#   AI 一落就把游标与盘面对上不上了（而这条只有人机 + AI 执黑 + 从菜单进复盘三件事
	#   同时发生时才会现形，属于"罕见组合"，不做判据根本量不到）。

	if game_mode == VS_AI and current_player == AI_COLOR and _replay == null:
		_start_ai_turn()
	# 调试：命令行带 --screenshot 时截图保存后退出
	if "--screenshot" in _argv():
		# `--screenshot --pause`：先把 ESC 暂停面板打开再截。
		# 暂停面板是**原生控件**（PanelContainer/Button），headless 下截不到，而"字看不清 / 没居中"
		# 这类问题**断言抓不到**，必须真机看图 —— 与 menu.gd 的 `--shotpage=<页>` 同一思路。
		if "--pause" in _argv():
			_show_pause_menu()
		# `--screenshot --shotcap`：构造「黑提白一子」的真实提子局面再截（验证落子/提子两段动画的画序）。
		if "--shotcap" in _argv():
			_setup_shot_capture()
		# `--screenshot --shotdrop`：把落子动画**冻在半途**再截（验证悬浮预览 + 下落中间帧）。
		if "--shotdrop" in _argv():
			_setup_shot_drop()
		# `--screenshot --shotwave`：一手提掉**一条长龙**，冻在"波前"途中再截 ——
		# 这是"从贴着刚落那手的子开始、一层层往外提"这件事**唯一的目检手段**
		# （单张静态图能同时看到近端已散尽、中段半透明、远端还没动，那一帧就是顺序本身）。
		if "--shotwave" in _argv():
			_setup_shot_wave()
		# `--screenshot --shotemote`：**两条侧抽屉 + 两边各一个气泡**，一次截全（2026-10-21）。
		#   ★ 自绘图形（脸 / 心 / 星）**只有肉眼能判**：有没有画歪、52px 格子里线宽糊不糊、
		#     深色抽屉底上"淡底的脸"会不会和底板混成一片 —— 这些都不产生任何断言失败，
		#     所以必须有这一档目检（同 §11：探针 / 守卫 / 目检三分工）。
		#   ★ 2026-10-21 第二轮靠这一张图逮到两个**判据全绿**的真 bug：
		#     ① 身份槽与回合提示按 `page_surface()` 挑字色、却画在深色抽屉底上（对比度 1.2）；
		#     ② 表情格的墨色按"面"推、而按钮底是调色板的浅底（白线压浅金，1.79）。
		#     两者都已改成"参照物 = 真正画在上面的那块面"，见 `_drawer_surface()`。
		if "--shotemote" in _argv():
			_setup_shot_emote()
		_capture_and_quit()
	# 自检：--passtest 本地双人模式连点两次「停一手」，校验不会触发 AI
	if "--passtest" in _argv():
		_self_test_local_pass()
	# 自检：--onlinetest 联机权威路径（单进程自环，验证动作回放/校验无异常）
	# ★ 这里**只留这一条**：原先下面还有一条 `--nettest-*` → `_self_test_network()`（ENet 双进程），
	#   第 5 步随自建联机一起删掉了。
	if "--onlinetest" in _argv():
		_self_test_online()
	# 自检：--readygate 联机「**双方都准备好了才进入对局**」的端到端闸（2026-10-21）
	#   走真实点击入口 `_on_area_input()`，正 / 负对照成对，看棋盘真的变了没有。
	if "--readygate" in _argv():
		_ready_gate_self_test()
	# 自检：--emotetest 快捷表情 + 联机身份条（2026-10-21）
	#   ★ 纯本地、不需要 Steam：判据量的是「消息入口 → 气泡状态 → 真实绘制计数 → 几何」。
	#   头像"真的从 Steam 取到图"那一条在 `--steamtest`（那里才有真 Steam）。
	if "--emotetest" in _argv():
		_emote_self_test()
	# 自检：--drawertest 侧抽屉几何 + 严防重叠（2026-10-21 第二轮）
	#   ★ 纯本地、不需要 Steam；量的是**真实矩形**（棋盘顶点盒 / 面板全局矩形 / 把手全局矩形）。
	#   阴性对照（让位系数压 0 后判据必须报红）内建在 ④ —— 没有它这条判据永远绿。
	if "--drawertest" in _argv():
		_drawer_self_test()
	# 自检：--aibench AI 性能基线（不同棋盘规模/时间预算下实际模拟次数）
	if "--aibench" in _argv():
		_ai_bench()
	# 自检：--aiprof AI 搜索剖析（树深度 / 各阶段耗时 / 热路径调用次数）
	# ⚠️ 必须用 `begins_with` 而不是 `in _argv()`：后者是**精确相等**匹配 ⇒
	#   带参数写法 `--aiprof=m90` 会静默不命中，游戏照常启动、什么都不打印、
	#   也不退出（2026-10-27 实测踩到，等了 180 秒超时才看出来）。
	if _argv_has_prefix("--aiprof"):
		_ai_prof()
	# 自检：--ailife 死活（判定层真源对照 / 做活与点杀要点 / 阴性对照 / 自战统计）
	if "--ailife" in _argv():
		_ai_life_test()
	# 自检：--aiterms 根先验特征分解（一次遍历 vs 权重基分解 跨实现对拍 + 仿射恒等式）
	if "--aiterms" in _argv():
		_ai_terms_test()
	# 自检：--aieye 把「AI 填自己的眼 / 不会做活」量出来（自战逐手记账 + 阴性对照）
	# 必须用 begins_with：带参数的写法（--aieye=pen）不是 `_argv()` 里的精确成员，用 `in` 会整条漏掉
	for a in _argv():
		if a.begins_with("--aieye"):
			_ai_eye_fill_probe()
			break
	# 自检：--areatest 过滤层口径专项（`_group_alive` 旧判据 vs `_group_status` 求解器是否打架）
	# 确定性、无搜索、秒级 → 放在回归里当断言，见 `_ai_own_area_judge_test()` 的说明
	if "--areatest" in _argv():
		_ai_own_area_judge_test()
	# 自检：--aipristest 叶子评估「提子项」接线（`count_prisoners`，2026-10-27）
	# 为什么要它：提子项是**唯一一处**「引擎口径与规则内核真源不一致」的已知差，
	#   而它的坏法全是静默的 —— 开关打不开 / 计数器没清 / 符号反了 / `_undo` 没回滚，
	#   四种都只会让 A/B 对打「看起来没差别」，于是被读成「提子项没用」。
	#   ⇒ 必须有一条不靠对打、只靠计数器的确定性判据先钉住接线。
	if "--aipristest" in _argv():
		_ai_prisoner_term_test()
	# 自检：--clocktest 棋钟（走时 / 读秒 / 加秒 / 超时 + 手频→BPM + 时间压力→音乐）
	# ★ 判据体在 `game_clock.gd::run_selftest()`（纯逻辑，只有内核自己拿得到细节）；
	#   这里补两条**只有对局侧能验**的契约（黑白索引对齐、快照真的挂上场景）。
	if "--clocktest" in _argv():
		_clock_self_test()
	# 自检：--analyzetest 全局局势分析层（死活分区 / 胜率 / 只读 / 音乐接线）
	# 用 begins_with：将来带参数写法（--analyzetest:pen）不会漏判（否则整条自检空跑）。
	for a in _argv():
		if a.begins_with("--analyzetest"):
			_analyze_self_test()
			break
	# 自检：--anlzprobe 局势层机制探针（确定性，先验层面；秒级）
	for a in _argv():
		if a.begins_with("--anlzprobe"):
			_anlz_probe()
			break
	# 自检：--anlzdose 救活权重剂量-响应扫描（确定性，秒级）
	# ★ 平级循环，**不要嵌进上面那个** —— 嵌套过一次（2026-10-07），
	#   症状是「零输出 + exit 0」：日志连 [anlzdose] 首行都没有 ⇒ 函数从未被进入。
	#   排查手法（技能 Part 4.1）：缺首行 = 标志没匹配上，不是函数内部卡住。
	for a in _argv():
		if a.begins_with("--anlzdose"):
			_anlz_dose()
			break
	# 自检：--anlzreal 真实局面采样（确定性，先验层；替代造夹具）
	for a in _argv():
		if a.begins_with("--anlzreal"):
			_anlz_real()
			break
	# 自检：--anlzwhy 要点早退原因分布（诊断：实战里机制为何不触发）
	for a in _argv():
		if a.begins_with("--anlzwhy"):
			_anlz_why()
			break
	# 自检：--anlzrate 三个局势机制在**真实盘**上的触发率（决定去留）
	for a in _argv():
		if a.begins_with("--anlzrate"):
			_anlz_rate()
			break
	# 自检：--anlzdir `w_sealed_territory` 的**方向判据**（配对：同局面同种子，只改一个权重）
	for a in _argv():
		if a.begins_with("--anlzdir"):
			_anlz_dir()
			break
	# 自检：--anlzmis 局势层**机械缺陷 + 工作点**诊断（只读探针；分档扫描）
	# ★ 平级循环，不要嵌进上面任何一个（2026-10-07 嵌错过一次 ⇒ 零输出 + exit 0）
	for a in _argv():
		if a.begins_with("--anlzmis"):
			_anlz_mis()
			break
	# 自检：--scidtest ★ 局面版本号 `_sc_id` 的缓存失效纪律（两条缓存各一条判据）
	# ★ 平级循环，不要嵌进上面任何一个（2026-10-07 嵌错过一次 ⇒ 零输出 + exit 0）
	for a in _argv():
		if a.begins_with("--scidtest"):
			_scid_test()
			break
	# 自检：--sealhard ★ 空区硬过滤（③ 从软权重升级成"打分前剔除" + 扩面）
	# ★ 同样平级。本自检**必须走真源 `_prepare_root()`** 去读计数 —— 判据自己手算的话，
	#   "开关接了但没被读"这种死参数会安静地全绿（铁律 22 那次就是这么漏的）。
	for a in _argv():
		if a.begins_with("--sealhard"):
			_sealhard_test()
			break
	# 自检：--ladtest 征子（ladder）判定专项：正确性 + A/B 开销
	if "--ladtest" in _argv():
		_ladder_test()
	# 自检：--hovertest 悬浮预览 + 落子下落（准入门槛与点击同源 / 棋理判据与 place_stone 穷举对照）
	if "--hovertest" in _argv():
		_hover_test()
	# 自检：--komi 白方贴目在引擎终局评估里生效（2026-10-02）
	if "--komitest" in _argv():
		_ai_komi_probe()
	# 自检：--rulestest 棋理判据**跨引擎**一致（2026-10-02）
	if "--rulestest" in _argv():
		_rules_cross_test()
	# 自检：--xgtest 图围棋骨架（第三套独立实现）与生产逐手对拍（2026-10-14）
	if "--xgtest" in _argv():
		_gograph_cross_test()
	# 自检：--liushuitest 流水（渗流引擎）在**真实盘**上接得上、走得出合法手（2026-10-22）
	if "--liushuitest" in _argv():
		_liushui_smoke_test()
	# 自检：--yematest 野马（神经网络先验 + 磐石搜索）接得上、关态逐位等价磐石（2026-10-23）
	if "--yematest" in _argv():
		_yema_smoke_test()
	# 仪器：--nnprobe=权重.json,golden.json —— **引擎侧前向与训练侧逐位对拍**（2026-10-26）
	# ★ 不是自检：路径由调用者给，**不碰线上 `ai/yema_weights.json`**。
	#   存在的理由：`--yematest` 只认线上那一份，而换结构（gnn）之后必须能在
	#   "不改线上权重"的前提下先验新权重，否则只能拿线上做实验。
	# ★ 两把刀缺一不可：特征对拍（喂进去的一样）+ 前向对拍（算出来的一样）。
	# ★ 三把刀缺一不可：特征对拍（喂进去的一样）+ 前向对拍（算出来的一样）+ 耗时。
	# ★ 这里刻意写成 `a == "--nnprobe" or a.begins_with(...)` 两种形式：
	#   `_audit_selftests.RE_FLAG` 只认**整条带引号的 flag 字面量**（`"--x"`），
	#   只写 `begins_with("--nnprobe=")` 的话这个入口对**孤儿闸隐形**
	#   （§113：凡按名字认东西的都会静默失效）。裸写 = 打印用法并以 2 退出。
	for a in _argv():
		if a == "--nnprobe" or a.begins_with("--nnprobe="):
			_nn_probe(a.substr(10))
			break
	# 仪器：--xgfight 骨架二版 vs 一版配对换色自弈出胜率/目差（2026-10-14；调参用，无判定）
	if "--xgfight" in _argv():
		_xg_fight_probe()
	# 仪器：--xgtune 骨架 **A/B 旋钮**配对换色自弈 + 配对 t 值（2026-10-20；调参用，无判定）
	#   带参写法 `--xgtune=n6:b=weak2=1.0` 不是精确成员 ⇒ 用 begins_with（同 --xgduel）
	for a in _argv():
		if a == "--xgtune" or a.begins_with("--xgtune="):
			_xg_tune_probe()
			break
	# 仪器：--xgduel 生产引擎（完整搜索）vs 骨架二版（1~2 手贪心）配对换色（2026-10-14）
	# 带参数写法 `--xgduel=r3:ms200:m260` 不是精确成员 ⇒ 用 begins_with（同 --aitune）
	for a in _argv():
		if a.begins_with("--xgduel"):
			_xg_duel_probe()
	# 仪器：--yemaduel 野马**开网络** vs **关网络**（=同参数磐石）配对换色自弈（2026-10-23）
	# ★ 这不是自检（要跑几分钟、结论是统计量不是真假）⇒ 用具名仪器入口 + 孤儿登记表。
	#   存在的理由只有一个：`--yematest` 证明得了"网络接上了"，证明不了"棋变强了"。
	for a in _argv():
		if a.begins_with("--yemaduel"):
			_yema_duel_probe()
	# 仪器：--aiscale **棋力-预算曲线**（同一引擎、只差 max_playouts，2026-10-24）
	# ★ 这是"要不要投自训练"的前置测量：先看算力还换不换得到棋力。
	for a in _argv():
		if a.begins_with("--aiscale"):
			_ai_scale_probe()
	# 仪器：--aispec **任意引擎参数** A vs B 配对换色自弈（2026-10-27，可复现、可配对读）
	# ★ 与 `--aiscale` 的分工：aiscale 只扫 `max_playouts`，本仪器扫任意属性
	#   （`eval_mix_lambda` / `max_playout_moves` / `prior_visits` / `root_width` / `c_puct`…）。
	#   存在的理由：每试一个旋钮就改一次源码、再靠人记着拨回去，必然漏（§120）。
	for a in _argv():
		if a.begins_with("--aispec"):
			_ai_spec_probe()
	# 仪器：--selfplay **自对弈数据工厂**（AlphaZero 式，标签 = 完整访问分布 + 终局胜负，2026-10-24）
	# ★ 与 --aigraph 的分工：aigraph 蒸教师（argmax 单点），selfplay 学自己的搜索（分布）。
	for a in _argv():
		if a.begins_with("--selfplay"):
			_selfplay_probe()
			break
	# 仪器：--liuh2h 三款 AI（磐石/疾风/流水）两两对战 + 选出 6 局写进**用户棋谱库**（2026-10-22）
	# ★★ 名字**不许**含 "test"：`is_automated_run()` 会把它判成自检 ⇒ 棋谱落进
	#   `user://records_selftest`，用户在菜单「棋谱」里永远看不到这 6 局（静默失败）。
	for a in _argv():
		if a.begins_with("--liuh2h"):
			_liuh2h_probe()
			break
	# 仪器：--liudiag 流水诊断/调参（把"被提"归因 + 旋钮 A/B，2026-10-22）
	# ★ 名字也不含 test（理由同 `--liuh2h`）—— 但本仪器**自己**把 `_record_muted` 置真，
	#   所以它既不写用户库也不写自检盘（调参要跑很多臂，一局一谱会把库灌满）。
	for a in _argv():
		if a.begins_with("--liudiag"):
			_liudiag_probe()
			break
	# 仪器：--liudrill 流水**战术训练场**（捕获 / 自救 / 不送吃，低方差，2026-10-22）
	# ★ 与 `--liudiag` 的分工：diag 量"一整局下来丢了多少"，噪声大；
	#   drill 量"单个局面该不该下对"，每个局面一张伯努利票 ⇒ 几十个局面就能看差。
	for a in _argv():
		if a.begins_with("--liudrill"):
			_liudrill_probe()
			break
	# 维护：--recmig 给老棋谱补齐 `kind` 分类字段 + 补 `players` 索引投影（2026-10-22，一次性）
	# ⚠️ 名字不含 test ⇒ 它**写的是用户棋谱库**。这是刻意（要迁移的就是真库），
	#   也意味着它是"写用户数据"的命令，只该人工跑一次。
	if "--recmig" in _argv():
		_record_migrate_kind()
	# 自检：--undotest 悔棋（栈完整性 / 回滚无损 / 三模式语义 / 联机额度与冻结）
	if "--undotest" in _argv():
		_undo_test()
	# 自检：--replaytest 回放一致性（棋谱阶段① 的地基：种子决定论在**有落子**时也成立）
	if "--replaytest" in _argv():
		_replay_consistency_test()
	# 自检：--grecotest 棋谱（记账 /逐手对拍 / 落盘两道闸 / 读回重放 / 悔棋截谱 / 中断标记）
	if "--grecotest" in _argv():
		_record_test()
	# 自检：--browsetest 复盘器（阶段② 功能层：跳转 / 播放速率 / 点盘跳转 / 退出复原）
	#   ★ flag 名不能叫 --replaytest（棋谱地基已占用）/ --recordtest（联机战绩已占用），
	#     同前缀会让"自检压根没跑"的哨兵失效。
	if "--browsetest" in _argv():
		_replay_browse_test()
	# 自检：--aiterr 终局评估质量（截断处 vs 下满后的真值）
	if "--aiterr" in _argv():
		_ai_territory_probe()
	# 自检：--ailam 给 λ 混合定理论最优值（测 rollout 噪声 σ 与静态评估偏差 b）
	if "--ailam" in _argv():
		_ai_lambda_probe()
	# 自检：--aiablate[=轮数] 消融实验（多局换色，定位哪一项机制在拖累棋力）
	# 注意用 begins_with：`--aiablate=3` 不是列表里的精确成员，用 `in` 会漏掉带参数的写法
	for a in _argv():
		if a.begins_with("--aiablate"):
			_ai_ablate()
			break
	# 自检：--aiself / --aiself=cross  AI 自战对比（详见 _ai_self_play）
	for a in _argv():
		if a.begins_with("--aiself"):
			_ai_self_play()
			break
	# 数据：--aidata 给第二档「浅层模型」落盘训练数据（特征 + 教师标签 + 对局结果）
	for a in _argv():
		if a.begins_with("--aidata"):
			_ai_data_dump()
			break
	# 数据：--aigraph 导出「图结构 + 局面 + 教师标签」，给**图无关**神经网络训练（2026-10-23）
	#   ★ 与 `--aidata` 的分工：那份是「候选级 21 维标量」，锁死在 17 项线性特征的天花板上；
	#     这份给 state + edge list，训练端自己算点级特征 ⇒ 权重与点数/度数无关，能跨盘型。
	for a in _argv():
		if a.begins_with("--aigraph"):
			_aigraph_probe()
			break
	# 自检：--capftest rollout 长度成本-一致率前沿（2026-10-05，解功效不足的死局）
	for a in _argv():
		if a.begins_with("--capftest"):
			_cap_factor_test()
			break
	# 自检：--dcwtest 动态分中心混合权重专项（死参数接线修复，2026-10-05）
	for a in _argv():
		if a.begins_with("--dcwtest"):
			_dc_weight_test()
			break
	# 自检：--vtest 价值头专项（引擎/落盘两套特征实现对拍 + 混入口径，2026-09-28）
	for a in _argv():
		if a.begins_with("--vtest"):
			_value_head_test()
			break
	# 自检：--aitune 参数对打仪（两组引擎参数互打，胜率喂给外部调参 runner 当裁判）
	# begins_with 同 --aiself：带参数写法 --aitune=... 不是精确成员，用 in 会整条漏掉
	for a in _argv():
		if a.begins_with("--aitune"):
			_ai_tune_match()
			break
	# 自检：--aitest 验证异步 AI 链路（后台线程搜索 → 协程 → 落子）
	if "--aitest" in _argv():
		_ai_async_test()
	# ⚰️ 2026-10-13 墓碑（名字不许回收）：这里原有两条 Ludii 自检 ——
	#   `--ludii`（`_ludii_diag()`：等一次 hello，打印模式/桥/classpath/拓扑）
	#   与 `--ludiitest`（`_ludii_test()`：协议 / 拓扑对拍 / 合法集对拍 / 换先对战 / 拒绝路径）。
	#   用户口令「彻底砍掉 Ludii」⇒ 连同 `ludii_bridge.gd` 与 `regress.sh` 里那一条 runner 一并删。
	#   ★ `--ludiibridge=<cp>`（只配 classpath、不触发自检）也随桥一起消失，不再需要"精确匹配"那条纪律。
	if "--gridtest" in _argv():
		_grid_self_test()
	# 自检：--randtest 随机棋盘（格数/连通/复现/多样性）
	if "--randtest" in _argv():
		_rand_self_test()
	# 自检：--pentest 五格网（pentagrid）生成器的数学健全性（胖瘦比/无缝无叠/复现/格数）
	if "--pentest" in _argv():
		_pentagrid_self_test()
	# 自检：--kitetest 筝形盘几何（邻边相等/角度谱/钝角共点/无缝无叠/面积和=三角形面积/星位/随机档）
	# 注意：board_type 的设定必须在上面 `--cubetest` 那条 elif 链里完成，
	# 不能在这里现设 —— `--board=` 的解析在那之后，会把它覆盖回去（实测踩过）。
	if "--kitetest" in _argv():
		_kite_self_test()
	# 自检：--snowtest 雪花盘几何（45°菱形/正方形桥/盘心 8 锐角共点/无缝无叠/连通/星位/三档）
	if "--snowtest" in _argv():
		_snow_self_test()
	# 自检：--hattest 帽子盘（瓦片模板 + 8 块筝形分解 / 池阶梯 / 边到边 / 三档格数 / 随机档）
	if "--hattest" in _argv():
		_hat_self_test()
	# 自检：--captest 提子计数与终局计分健全性回归
	if "--captest" in _argv():
		_capture_self_test()
	# 自检：--aibud[=big|enh|std|rwN|b...] 时间预算 → 决策一致率（回答「多给思考时间到底有没有用」）
	# 同样必须用 begins_with：带参数的写法（--aibud=rw12）不是列表里的精确成员，
	# 用 `in` 判断会漏掉，然后场景就一直空跑不退出（表现为「自检卡死」）
	for a in _argv():
		if a.begins_with("--aibud"):
			_ai_budget_test()
			break
	# 自检：--dumpadj=<pen|cube|kite|snow|hat>[:<std|enh|rand>] 导出真实邻接表
	# （工作区 `死活真源/` 的通用图死活求解器要用它验 `ld_cap_points = 6`，
	#  详见 `_dump_adjacency` 注释。同样必须 begins_with：带参数写法不是精确成员）
	for a in _argv():
		if a.begins_with("--dumpadj"):
			_dump_adjacency(a.substr(9))          # 9 = "--dumpadj".length()
			break
	# 自检：--jevdump=<pen|cube|kite|snow|hat>[:<std|enh|rand>][:<已落手数,逗号分隔>][:<pw>][:<根宽>]
	# 导出「真实局面 + 引擎自己的根先验」，供工作区 Jev 可行性探针（jev_probe.py）对照。
	# 同样必须 begins_with：带参数写法不是参数列表里的精确成员，用 `in` 判断会整条漏掉，
	# 然后场景空跑到超时（表现为「自检卡死」，与 --dumpadj / --aibud 同一个坑）。
	for a in _argv():
		if a.begins_with("--jevdump"):
			_jevdump(a.substr(9))                  # 9 = "--jevdump".length()
			break
	# 自检：--resigntest AI 主动认输判据（绝望局面必认 / 均势必不认 / 手数不足必不认）
	if "--resigntest" in _argv():
		_resign_self_test()
	# 自检：--counttest 「对方停一手 → 是否数子」提示的触发条件与两个按钮行为
	if "--counttest" in _argv():
		_count_self_test()
	# 自检：--esctest ESC 暂停面板（模拟按键事件，不碰真实输入设备、不联网）
	if "--esctest" in _argv():
		_esc_test()
	# 自检：--hatdead 定位器 —— 用户 2026-09-21 报「帽子盘右侧边缘空格点不动」
	if "--hatdead" in _argv():
		_hat_dead_self_test()
	# 自检：--portraittest 竖屏形态（画布基座 / 棋盘边距 / 拾取框覆盖 / HUD 触摸目标 + 两条阴性对照）
	if "--portraittest" in _argv():
		_portrait_self_test()

## 自检（--portraittest）：**竖屏形态**的判据（2026-09-23 用户口令「我希望它是竖屏的」）。
##
## ★ 为什么必须有这个自检，而不是"看图就行"：
##   竖屏分支（画布基座、棋盘边距、HUD 布局）全都在**运行期按谓词分叉**，
##   而本机是横屏桌面 —— 不带 `--portrait` 的话这几条分支**永远跑不到**，
##   等于"改了没人验"。新分支必须有 runner，这条是本工程的铁律。
## ★ 哪些能在 headless 跑：HUD 分支只依赖 `GameConfig.use_portrait_canvas()`（谓词），
##   与视口长宽比无关 → headless 也能验（本函数）。
##   菜单侧的「行带高度收敛」依赖真实竖屏视口，headless 的物理窗恒为 1152×1152 正方，
##   拿不到竖屏 → 那一条放在 menu.gd 的 `--portraittest`，用真窗口跑（`--winsize=720x1560`）。
func _portrait_self_test() -> void:
	var ok := true
	print("[portraittest] ===== 竖屏形态自检 =====")

	# ① 尺寸参数解析（纯函数）。正例 + **反例**都要有 —— 只测正例的解析器写成"永远返回 ZERO"也能过。
	var ap: Callable = GameConfig.parse_size_arg
	var cases: Array = [
		["720x1560", Vector2i(720, 1560)], ["720X1560", Vector2i(720, 1560)],
		[" 720 x 1560 ", Vector2i(720, 1560)], ["1152x648", Vector2i(1152, 648)],
		["abc", Vector2i.ZERO], ["720", Vector2i.ZERO], ["720x", Vector2i.ZERO],
		["0x0", Vector2i.ZERO], ["100x100", Vector2i.ZERO], ["720x-5", Vector2i.ZERO],
		["x1560", Vector2i.ZERO], ["720x1560x9", Vector2i.ZERO],
	]
	var bad_cases: Array[String] = []
	for c in cases:
		var got: Vector2i = ap.call(String(c[0]))
		if got != Vector2i(c[1]):
			bad_cases.append("%s→%s(期望%s)" % [String(c[0]), str(got), str(c[1])])
	var ok1: bool = bad_cases.is_empty()
	if not ok1:
		ok = false
	print("[portraittest] ① parse_size_arg %d 例：%s → %s" % [
		cases.size(), "全部符合 ✓" if ok1 else "; ".join(bad_cases),
		"通过 ✓" if ok1 else "失败 ✗"])

	# ② 画布基座谓词。★ 判据读的是**真的套在窗口上的值**（content_scale_size），不是常量。
	var w: Window = get_window()
	var base: Vector2i = GameConfig.design_base_size()
	var ok2: bool = GameConfig.use_portrait_canvas() \
		and base == GameConfig.BASE_SIZE_PORTRAIT \
		and w.content_scale_size == base \
		and w.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND
	if not ok2:
		ok = false
	print("[portraittest] ② 竖屏画布：谓词=%s 基座=%s 实际content_scale=%s aspect=%d → %s" % [
		str(GameConfig.use_portrait_canvas()), str(base), str(w.content_scale_size),
		w.content_scale_aspect, "通过 ✓" if ok2 else "失败 ✗（须用 --portrait 跑）"])

	# ③ 棋盘边距：竖屏必须用**收紧档**（14 而非 40），且量出来的四边最小余量就是它。
	#    只看常量等于没测；这里量的是 `_adapt_to_screen()` 真正摆出来的棋盘包围盒。
	GameConfig.board_type = GameConfig.BOARD_PENROSE
	generate_board()
	_adapt_to_screen()
	_update_hud()
	await get_tree().process_frame
	await get_tree().process_frame
	var vs := get_viewport_rect().size
	var bb := _board_bbox()
	var m_l: float = bb.position.x
	var m_t: float = bb.position.y
	var m_r: float = vs.x - bb.end.x
	var m_b: float = vs.y - bb.end.y
	var min_m: float = minf(minf(m_l, m_r), minf(m_t, m_b))
	var want_m: float = GameConfig.board_margin_portrait
	var ok3: bool = absf(min_m - want_m) <= 1.0 and min_m >= want_m - 1.0
	if not ok3:
		ok = false
	print("[portraittest] ③ 棋盘边距：上%.1f 下%.1f 左%.1f 右%.1f → 最小余量 %.1f（期望 %.0f）→ %s" % [
		m_t, m_b, m_l, m_r, min_m, want_m, "通过 ✓" if ok3 else "失败 ✗"])

	# ④ 可点区域必须盖住棋盘包围盒（`--hatdead` 的不变量，在竖屏形态下再钉一次）。
	#    竖屏下边距收紧到 14 → 棋盘更靠边，正是最容易掉出拾取框的一档。
	var ok4 := true
	if click_area == null:
		ok4 = false
	else:
		for ch in click_area.get_children():
			if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
				var sh := (ch as CollisionShape2D).shape as RectangleShape2D
				var box := Rect2(click_area.position - sh.size * 0.5, sh.size)
				if not box.encloses(bb.grow(1.0)):
					ok4 = false
					print("[portraittest]    拾取框 %s 未包住棋盘 %s" % [str(box), str(bb)])
	if not ok4:
		ok = false
	print("[portraittest] ④ 拾取框盖住棋盘 %s → %s" % [
		str(bb), "通过 ✓" if ok4 else "失败 ✗"])

	# ⑤ HUD 竖屏档：按钮必须够高（触摸目标）且完整在屏内。
	#    ★ 期望值传**字面常量**（HUD_TOUCH_MIN_PORTRAIT），不传 `hud_button_min_height()`
	#      —— 后者的值由谓词派生，用它当期望值的话阴性对照会把自己关掉（见函数注释）。
	var jr: Array = judge_hud_layout(GameConfig.HUD_TOUCH_MIN_PORTRAIT)
	var ok5: bool = bool(jr[0])
	if not ok5:
		ok = false
	print("[portraittest] ⑤ HUD %s → %s" % [String(jr[1]), "通过 ✓" if ok5 else "失败 ✗"])

	# ⑥ **阴性对照**：把谓词切回横屏，同一条判据必须报警。
	#    ★ 没有这一步的话，「按钮高 ≥ 76」可能只是"恰好本来就高"，判据其实没在测竖屏分支。
	#    判据要能变红，才算真的在测东西。
	#    ★ 必须等一下帧：`custom_minimum_size = 0` 只是把最小尺寸标脏，容器要下一帧才重排。
	#      不等的话报警会来自"按钮宽度还是竖屏那次的拉伸值 → 出屏"这个**副作用**，
	#      而不是"高度不够"这个正主 —— 阴性对照对了但理由错了，下次就查不出来真问题。
	var keep_override: int = GameConfig.portrait_override
	GameConfig.portrait_override = 0
	_refit_hud()
	await get_tree().process_frame
	await get_tree().process_frame
	var jr2: Array = judge_hud_layout(GameConfig.HUD_TOUCH_MIN_PORTRAIT)
	var ok6: bool = not bool(jr2[0])
	if not ok6:
		ok = false
	print("[portraittest] ⑥ 阴性对照（强制横屏，判据必须报警）：%s → %s" % [
		String(jr2[1]), "通过 ✓" if ok6 else "失败 ✗（判据恒真，等于没有判据）"])
	# ⑤b **横屏档的正判据**：按钮必须**不出屏**（期望值传 0 把"高度"那一半关掉，只留出屏）。
	#   ★★ 2026-10-15 补：原先横屏档的"出屏"**只出现在 ⑥ 的报警文本里**，而 ⑥ 断言的是
	#     `not 判据通过` ⇒ 它报出「返回菜单 出屏」之后照样印「通过 ✓」！也就是说
	#     "横屏 HUD 有没有被挤出屏幕"这件事**当时没有任何判据在守**（红点被当成噪声读过去）。
	#     这不是假想：本轮给 HUD 按钮套主题样式时，内边距把这一行从 305px 撑到 345px，末位
	#     按钮真的出屏了 —— 而 ⑥ 依旧全绿。
	#   ★ 为什么期望值传 0.0 而不是 HUD_TOUCH_MIN_PORTRAIT：高度那一半已经由 ⑤（竖屏）/⑥
	#     （阴性对照）覆盖，这里只留"出屏"这一半，两条判据射程不重叠（铁律 §11 同族分工）。
	#   ★ 与 ⑥ 配对（同一状态下一个必须红、一个必须绿）：只有"必须红"那一半的话，
	#     判据恒真（永远报红）也能过 ⑥；只有"必须绿"那一半的话，"永远不报警"也能过。
	var jr5b: Array = judge_hud_layout(0.0)
	var ok5b: bool = bool(jr5b[0])
	if not ok5b:
		ok = false
	print("[portraittest] ⑤b 横屏档 HUD 按钮不得出屏：%s → %s" % [
		String(jr5b[1]), "通过 ✓" if ok5b else "失败 ✗"])
	# ⑤c **横屏档的离边留白**（2026-10-16 用户口令「对局中按钮接近屏幕边缘，修一下」）。
	#   ★ 为什么 ⑤b 抓不到它：⑤b 只问"出没出屏"，而病灶是**紧贴屏幕边**
	#     （改前横屏实测右沿只剩 **5px**：宽度预算 320 被当成"距右"用，行宽 315 ⇒ 320−315=5）。
	#     5px 与 200px 在"出屏"这条判据眼里**一模一样** —— 本条补的就是这个射程缺口。
	#   ★ 期望值取**编译期字面量** `HUD_EDGE_MARGIN_LANDSCAPE`（**不取那个变量**）：
	#     ⑤d 的阴性对照要改的正是那个变量 ⇒ 期望值若也读它，判据就把自己关掉了
	#     （与 ⑤ 传 `HUD_TOUCH_MIN_PORTRAIT` 是同一条纪律）。
	var jr5c: Array = judge_hud_layout(0.0, GameConfig.HUD_EDGE_MARGIN_LANDSCAPE)
	var ok5c: bool = bool(jr5c[0])
	if not ok5c:
		ok = false
	print("[portraittest] ⑤c 横屏档 HUD 离屏幕边 ≥ %.0f：%s → %s" % [
		GameConfig.HUD_EDGE_MARGIN_LANDSCAPE, String(jr5c[1]),
		"通过 ✓" if ok5c else "失败 ✗"])
	# ⑤d **阴性对照**：把留白归 0（复现"贴着屏幕边"）⇒ 同一条判据必须报警。
	#   ★ 改的是**被测物**（`hud_landscape_margin` ⇒ 布局真的贴边），**不改期望值** ——
	#     这正是与 ⑤c 配对的意义：只有"必须绿"那一半的话，判据恒真也能过 ⑤d；
	#     只有"必须红"那一半的话，判据永远不报警也能过 ⑤c。两半缺一不可。
	#   ★ 不需要 await 下一帧：横屏分支只改盒子的 `position`（尺寸仍是自然宽高）⇒
	#     子节点的局部矩形不变、全局矩形**立即**跟着移动（与 ⑥ 那种"改了 size 要等重排"不同）。
	var gap_bak: float = GameConfig.hud_landscape_margin
	GameConfig.hud_landscape_margin = 0.0
	_refit_hud()
	var jr5d: Array = judge_hud_layout(0.0, GameConfig.HUD_EDGE_MARGIN_LANDSCAPE)
	var ok5d: bool = not bool(jr5d[0])
	if not ok5d:
		ok = false
	print("[portraittest] ⑤d 阴性对照（留白归 0，判据必须报警）：%s → %s" % [
		String(jr5d[1]), "通过 ✓" if ok5d else "失败 ✗（判据恒真，等于没有判据）"])
	GameConfig.hud_landscape_margin = gap_bak     # 还原**被测物**
	_refit_hud()
	# 棋盘边距的第二条阴性对照：横屏档必须是 40（同一个量法）
	_adapt_to_screen()
	var min_m2: float = minf(minf(_board_bbox().position.x, vs.x - _board_bbox().end.x),
		minf(_board_bbox().position.y, vs.y - _board_bbox().end.y))
	var ok7: bool = absf(min_m2 - GameConfig.board_margin_landscape) <= 1.0
	if not ok7:
		ok = false
	print("[portraittest] ⑦ 阴性对照（边距回到横屏 %.0f，实测 %.1f）→ %s" % [
		GameConfig.board_margin_landscape, min_m2, "通过 ✓" if ok7 else "失败 ✗"])
	# ⑧ **HUD 文字的主题接线**（2026-10-16 用户口令「对局中的『轮到你』文字颜色没有配合主题」）。
	#   ★ 为什么正判据 + 阴性对照一起写（与 ⑤/⑥ 同一套路）：正判据只证明"此刻通过"，
	#     阴性对照才证明**它真的在测这条线**（把 override 清掉必须立刻红）。
	#   ★ 阴性对照改的是**被测物**（清掉 override = 复现"没接线"），**不改期望值** ——
	#     判据内部的参照物（`page_surface()` / 阈值真源）全程不动（铁律：判据不许把自己关掉）。
	#   ★ 还原用 `add_theme_color_override` 写回原值 + `_refit_hud()`：HUD 外观的唯一入口是
	#     `_refit_hud()`，还原也走它，保证"跑完与跑之前逐位相同"。
	var jt: Array = judge_hud_text_theme()
	var ok8: bool = bool(jt[0])
	if not ok8:
		ok = false
	print("[portraittest] ⑧ HUD 回合提示字色 %s → %s" % [String(jt[1]), "通过 ✓" if ok8 else "失败 ✗"])
	var ink_bak: Color = _hud_turn_label.get_theme_color("font_color")
	var had_bak: bool = _hud_turn_label.has_theme_color_override("font_color")
	_hud_turn_label.remove_theme_color_override("font_color")
	var jt2: Array = judge_hud_text_theme()
	var ok8b: bool = not bool(jt2[0])
	if not ok8b:
		ok = false
	print("[portraittest] ⑧b 阴性对照（清掉字色 override，判据必须报警）：%s → %s" % [
		String(jt2[1]), "通过 ✓" if ok8b else "失败 ✗（判据恒真，等于没有判据）"])
	if had_bak:
		_hud_turn_label.add_theme_color_override("font_color", ink_bak)
	_refit_hud()
	# 还原：别把测试状态漏给后面（同一进程里可能还有别的自检）
	GameConfig.portrait_override = keep_override
	_refit_hud()
	_adapt_to_screen()

	print("[portraittest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 棋盘当前包围盒（顶点已是像素坐标）—— 供竖屏自检量边距用
func _board_bbox() -> Rect2:
	if vertices.is_empty():
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in vertices:
		mn.x = minf(mn.x, v.x)
		mn.y = minf(mn.y, v.y)
		mx.x = maxf(mx.x, v.x)
		mx.y = maxf(mx.y, v.y)
	return Rect2(mn, mx - mn)

## 自检（--hatdead）：「右侧边缘空格点不动」的定位器（临时诊断）。
##
## 两条候选成因必须**分开量**，否则只能猜：
##   ① **GUI 吃掉点击**：落子走 Area2D 物理拾取（`_on_area_input`），它排在 GUI 事件**之后**。
##      只要有 `mouse_filter = STOP` 的 Control 盖在格子上，物理拾取根本收不到事件，
##      而且**一声不响** —— 连 "该瓷砖内已有棋子" 都不会打（导出后用户也看不到 print，
##      所以「到底是不是自杀判错」在界面上无法区分）。右边特别可疑：常驻 HUD
##      （停一手 / 重新开始 / 认输 / 返回菜单）就钉在右下角，而 `_adapt_to_screen` 只留 40px 边距。
##   ② **真的无气**：点被对方子围住 → `place_stone` 判自杀。
##      关键看这些点的**邻接度**：度 1 = 几何缺陷（尖头，必须为 0）；度 2 = 正常棋理下的死点。
func _hat_dead_self_test() -> void:
	var ok := true
	game_mode = VS_AI
	GameConfig.board_type = GameConfig.BOARD_HAT
	generate_hat()
	_adapt_to_screen()          # ★ 必须补这一步：它才把顶点换算成像素坐标并重建 tile_centers
	_update_hud()
	await get_tree().process_frame
	await get_tree().process_frame

	# ---------- ① 棋盘 / 控件几何（顶点此时已是像素坐标：屏幕坐标 == 世界坐标）
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for v in vertices:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
	print("[hatdead] 视口 %s | 棋盘盒 x∈[%.0f,%.0f] y∈[%.0f,%.0f] | 格 %d"
		% [str(get_viewport_rect().size), min_x, max_x, min_y, max_y, tiles.size()])
	# 环境快照：判定「用户配置是否落在会越界的那一档」靠它（窗口比例 ≠ 16:9 才会越界）。
	print("[hatdead] 环境：Window.size=%s DisplayServer.window=%s 终变换=%s ｜屏幕=%s 缩放=%.2f ｜窗口模式=%d"
		% [str(get_window().size), str(DisplayServer.window_get_size()),
			str(get_viewport().get_final_transform()), str(DisplayServer.screen_get_size()),
			DisplayServer.screen_get_scale(), DisplayServer.window_get_mode()])

	var stops: Array = []
	_collect_stop_controls(self, stops)
	for e in stops:
		var c: Control = e
		print("[hatdead] STOP 控件 %s rect=%s" % [str(c.get_path()), str(c.get_global_rect())])
	var blocked: Array[int] = []
	for i in tiles.size():
		for c in stops:
			if (c as Control).get_global_rect().has_point(tile_centers[i]):
				blocked.append(i)
				break
	print("[hatdead] ① 中心被 STOP 控件盖住的格子 = %d / %d" % [blocked.size(), tiles.size()])
	if blocked.size() > 0:
		var s1: Array = []
		for i in mini(10, blocked.size()):
			var t: int = blocked[i]
			s1.append("t%d%s" % [t, str(tile_centers[t].round())])
		print("[hatdead]    样例：", ", ".join(s1))

	# ---------- ①b 「多边形遮挡」逐点采样。①只验**中心**，抓不到「格子中心空着、多边形
	#    一角却伸到按钮底下」这一类；而用户报的恰恰是**边缘**点不动。做法：在格子多边形内
	#    按 3px 网格采样，看采样点是否落在某个 STOP 控件矩形里 —— 是则事件被 GUI 吃掉，
	#    物理拾取收不到，且**一声不响**（连「已有子 / 自杀」都不打，导出后无从分辨）。
	var cov: Array = []
	var holes := 0
	for i in tiles.size():
		var q: Dictionary = _hat_cover_frac(i, stops, true)
		holes += int(q["holes"])
		if board[i] != Stone.EMPTY or int(q["blk"]) == 0:
			continue
		cov.append({"t": i, "blk": q["blk"], "tot": q["tot"], "frac": q["frac"],
			"c": tile_centers[i], "bp": q["bp"], "r": q["r"], "deg": adjacency[i].size()})
	print("[hatdead] ①b 空点中「多边形被 STOP 控件压住」的格子 = %d（须 0）" % cov.size())
	for e in cov:
		var cc: Vector2 = e["c"]
		var rr: Rect2 = e["r"]
		print("[hatdead]     t%d 中心%s 度%d 被压%.0f%%（%d/%d 点）压区 x∈[%.0f,%.0f] y∈[%.0f,%.0f] 被压样点%s"
			% [e["t"], str(cc.round()), e["deg"], float(e["frac"]) * 100.0, e["blk"], e["tot"],
				rr.position.x, rr.end.x, rr.position.y, rr.end.y, str((e["bp"] as Vector2).round())])
	# ⚠️ 上一版这里是「`_tile_at_point` 没返回本格」→ 实测报了 385 个，**全是假报**：
	#    它返回的是第一个包含该点的片，采样点正好落在共享边上时返回邻居属于正常歧义。
	#    真正该查的漏洞是它返回 **-1**（点在多边形内却说"没命中"）→ 点击静默无效。
	print("[hatdead] ①b 多边形内却被 _tile_at_point 判为「未命中」(-1) 的采样点 = %d（须 0）" % holes)
	if holes > 0:
		ok = false

	# ---------- ⑧ 「点看得见的地方能不能落子」：`tile_centers` 是棋子 / 空格提示的**绘制位置**，
	#    用户就是照着它点的。若它落在自己多边形**外面**（帽子瓦片是非凸的，顶点形心完全可能
	#    掉进凹口或掉到盘外），那么点"看得见的那个格子"就会：返回 -1（**什么都不发生，静默**）
	#    或者落到**邻居**身上（更像"点了没反应 / 放错地方"）。这正是用户描述的症状形态。
	var c_gap := 0
	var c_nb := 0
	var s8: Array = []
	for i in tiles.size():
		var hit2: int = _tile_at_point(tile_centers[i])
		if hit2 == i:
			continue
		if hit2 == -1:
			c_gap += 1
		else:
			c_nb += 1
		if s8.size() < 14:
			s8.append("t%d%s→%s" % [i, str(tile_centers[i].round()),
				("空隙(-1)" if hit2 == -1 else "t%d" % hit2)])
	print("[hatdead] ⑧ tile_centers 不在自己多边形内的格子 = %d / %d ｜ 其中落空隙(-1) %d、落邻居 %d"
		% [c_gap + c_nb, tiles.size(), c_gap, c_nb])
	if s8.size() > 0:
		print("[hatdead]    样例：", ", ".join(s8))
	if c_gap + c_nb > 0:
		ok = false

	# ---------- ⑨ 「可点区域」有多大：落子靠 `click_area`，它是一个 **2000×2000、原点居中**的
	#    矩形 → 覆盖范围恒为 x,y ∈ [-1000,1000]，**不随棋盘或窗口变化**。窗口一变宽，棋盘被
	#    重新居中放大，右边缘就跑到这个方框外面 → 那部分瓷砖的物理拾取根本收不到事件，
	#    **静默无效**。这正是「右侧边缘空格点不动」的结构性来源
	#    （棋盘盒右/下边界最大能到 视口.x-40 / 视口.y-40，只要 >1000 就越界）。
	var ov: Dictionary = _hat_overflow()
	print("[hatdead] ⑨ click_area 可点矩形 = %s ｜ 视口 %s ｜ 棋盘盒右/下 = (%.0f, %.0f)"
		% [str(ov["rect"]), str(get_viewport_rect().size), max_x, max_y])
	print("[hatdead] ⑨ 有部分落在可点矩形外的格子 = %d / %d（须 0）｜ 最重 t%s 越界 %.0fpx"
		% [int(ov["n"]), tiles.size(), str(ov["t"]), float(ov["worst"])])
	if int(ov["n"]) > 0:
		ok = false
		# 越界格上做 A/B：① **直接调处理函数**（绕过物理拾取）→ 应落子成功；
		# ② **真实合成点击** → 应落子失败。两条合起来才证明「是拾取范围被框住了」，
		# 而不是棋理/几何有问题 —— 这是给用户"点不动"定性最关键的一次对照。
		var ot := int(ov["t"])
		var oc: Vector2 = tile_centers[ot]
		var evd2 := InputEventMouseButton.new()
		evd2.button_index = MOUSE_BUTTON_LEFT
		evd2.button_mask = MOUSE_BUTTON_MASK_LEFT
		evd2.pressed = true
		evd2.position = oc
		evd2.global_position = oc
		var sd2: Dictionary = board.duplicate()
		var mode3: int = game_mode
		var go3: bool = game_over
		var at3: bool = is_ai_thinking
		game_mode = LOCAL
		game_over = false
		is_ai_thinking = false
		current_player = PLAYER_COLOR
		_on_area_input(get_viewport(), evd2, -1)
		var dir_ok: bool = board[ot] != sd2[ot]
		board.clear()
		for k in sd2.keys():
			board[k] = sd2[k]
		current_player = PLAYER_COLOR
		var r9: Dictionary = await _hat_click_probe(ot, oc)
		game_mode = mode3
		game_over = go3
		is_ai_thinking = at3
		print("[hatdead] ⑨ 越界格 t%d 中心%s：直接调处理函数 → %s ｜ 真实合成点击 → %s"
			% [ot, str(oc.round()), "落子 ✓" if dir_ok else "没落子 ✗",
				"落子 ✓" if r9["ok"] else "没落子 ✗（与「拾取范围被框住」一致）"])

	# ---------- ② 中盘空点可落性（复用引擎自己的着手体检，与对局同口径）
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260921
	var col: int = Stone.BLACK
	var placed := 0
	var tries := 0
	_quiet_place = true
	while placed < 95 and tries < 20000:
		tries += 1
		var v: int = rng.randi_range(0, tiles.size() - 1)
		if board[v] != Stone.EMPTY:
			continue
		current_player = col
		if place_stone(v, false):
			placed += 1
			col = Stone.WHITE if col == Stone.BLACK else Stone.BLACK
	_quiet_place = false
	current_player = col
	print("[hatdead] ② 造中盘：落 %d 子（试 %d 次）" % [placed, tries])
	var deg_hist: Dictionary = {}
	for i in tiles.size():
		var d: int = adjacency[i].size()
		deg_hist[d] = int(deg_hist.get(d, 0)) + 1
	print("[hatdead] ② 邻接度直方图 ", str(deg_hist))
	# ★ 独立审计（有牙齿的那一条）：`adjacency` 是从**池邻接**映射来的，这里按「共享边」纯几何
	#   反查一遍 —— 两套口径**互相独立**。若几何邻居数 > 邻接度数，就是「邻接表丢了边」→
	#   落子时气被少算 → **假自杀**（正是用户怀疑的那种错法）。
	#   ⚠️ 不能用 `_edge_neighbor` 反推：它每条边**只登记一次**（后到的片直接 continue），
	#      拿它数度数必然偏小（实测把 142/150 个格子判成不一致，全是这个假报）。
	#      正确做法是拿边的两个端点，在**所有**片里找「同时含这两点且不是自己」的那一片。
	var geo_bad := 0
	for i in tiles.size():
		var s: Dictionary = {}
		var tvs: Array = tiles[i]
		for k in tvs.size():
			var a: int = tvs[k]
			var b: int = tvs[(k + 1) % tvs.size()]
			for j in tiles.size():
				if j == i:
					continue
				var ntvs: Array = tiles[j]
				if ntvs.has(a) and ntvs.has(b):
					s[j] = true
					break
		if s.size() != adjacency[i].size():
			geo_bad += 1
			print("[hatdead]    ✗ 度数不一致 t%d：邻接 %d vs 几何 %d 坐标%s 邻居%s"
				% [i, adjacency[i].size(), s.size(), str(tile_centers[i].round()), str(s.keys())])
	print("[hatdead] ③ 邻接表 vs 纯几何邻居数不一致的格子 = %d / %d（须 0）"
		% [geo_bad, tiles.size()])
	if geo_bad > 0:
		ok = false
	# 低度格子（度 ≤3）逐个点名：它们才是「边界上容易被围死」的候选。
	# 判据：度 2 的格子只需要对方两手就能做死；度 ≤1 是几何缺陷。
	var vsz: Vector2 = get_viewport_rect().size
	for i in tiles.size():
		if adjacency[i].size() > 3:
			continue
		var p: Vector2 = tile_centers[i]
		var relx: float = p.x / maxf(vsz.x, 1.0)
		var rely: float = p.y / maxf(vsz.y, 1.0)
		var side := "中"
		if relx > 0.72:
			side = "右"
		elif relx < 0.28:
			side = "左"
		print("[hatdead]    低度格 t%d 度%d 位置 %s (%.0f,%.0f) 相对(%.2f,%.2f) 坐标%s"
			% [i, adjacency[i].size(), side, p.x, p.y, relx, rely, str(p.round())])
	var dead: Array[int] = []
	var dead_deg: Dictionary = {}
	for i in tiles.size():
		if board[i] != Stone.EMPTY:
			continue
		var g: Dictionary = _ai_move_gate(i, current_player)
		if g["suicide"]:
			dead.append(i)
			var d2: int = adjacency[i].size()
			dead_deg[d2] = int(dead_deg.get(d2, 0)) + 1
	print("[hatdead] ② 空点里「无气（自杀）」的 = %d / %d，按邻接度分 %s"
		% [dead.size(), tiles.size(), str(dead_deg)])
	# 位置分解：用户报的是「右侧边缘」。若无气点集中在右侧，就是边界低度格被围死；
	# 若左右对称分布，则更可能是 HUD 挡点击（HUD 只在右下）。
	var side_n: Dictionary = {"左": 0, "中": 0, "右": 0}
	for i in dead:
		var rx: float = tile_centers[i].x / maxf(vsz.x, 1.0)
		side_n["右" if rx > 0.72 else ("左" if rx < 0.28 else "中")] += 1
	print("[hatdead] ② 无气点的左右分布 = %s" % str(side_n))
	var s2: Array = []
	for i in mini(10, dead.size()):
		var t2: int = dead[i]
		var own := 0
		var en := 0
		for nb in adjacency[t2]:
			if board[nb] == current_player:
				own += 1
			elif board[nb] != Stone.EMPTY:
				en += 1
		s2.append("t%d(度%d 己%d 敌%d)" % [t2, adjacency[t2].size(), own, en])
	print("[hatdead]    样例：", ", ".join(s2))
	if int(dead_deg.get(1, 0)) > 0:
		ok = false                       # 度 1 的格子 = 几何缺陷（尖头），必须为 0

	# ---------- ④ 「有气必可落」：只要还剩一个空邻居，就**绝不能**判自杀 —— 专抓假自杀。
	#    这是对用户那句「是不是自杀判错了」的正面回答。
	var over_rej := 0
	for i in tiles.size():
		if board[i] != Stone.EMPTY:
			continue
		var has_empty := false
		for nb in adjacency[i]:
			if board[nb] == Stone.EMPTY:
				has_empty = true
				break
		if has_empty and bool(_ai_move_gate(i, current_player)["suicide"]):
			over_rej += 1
			print("[hatdead]    ✗ 假自杀 t%d 度%d 坐标%s"
				% [i, adjacency[i].size(), str(tile_centers[i].round())])
	print("[hatdead] ④ 有空邻居却被判自杀的格子 = %d（须 0 = 无假自杀）" % over_rej)
	if over_rej > 0:
		ok = false

	# ---------- ⑤ 「该判死的判得对不对」：人为把每个低度格（度 ≤3）的邻居全填成对方色，
	#    然后**两条独立路径**比对：引擎的着手体检 vs 本函数里手写的「落子→提子→数气」最小复刻。
	#    两者不一致 ⟹ 自杀判据本身有错。
	var kill_n := 0
	var kill_bad := 0
	var kill_eg := ""
	for i in tiles.size():
		if adjacency[i].size() > 3:
			continue
		if board[i] != Stone.EMPTY:
			continue      # ★ 已被占的低度格要跳过：`_ai_move_gate` 会正确报 illegal，
						  #   若这里盲目覆盖求值就会造出「引擎说 illegal、独立复刻说死」的**假分歧**
						  #   （第一版就是这么错的：20 个里报 2 个分歧，全是已被占的点）
		var save: Dictionary = board.duplicate()
		var opp_ct: int = Stone.WHITE if current_player == Stone.BLACK else Stone.BLACK
		for nb in adjacency[i]:
			board[nb] = opp_ct
		var eng: Dictionary = _ai_move_gate(i, current_player)
		var ind: Dictionary = _hat_indep_place_check(i, current_player)
		board.clear()
		for k in save.keys():
			board[k] = save[k]
		kill_n += 1
		var eng_dead: bool = bool(eng["suicide"])
		var ind_dead: bool = int(ind["libs"]) == 0 and int(ind["cap"]) == 0
		if eng_dead != ind_dead:
			kill_bad += 1
			var nbs: Array = []
			for nb in adjacency[i]:
				nbs.append("%d=%d" % [nb, board[nb]])
			print("[hatdead]    ✗ 判据分歧 t%d 度%d 邻居[%s] 引擎%s 独立%s"
				% [i, adjacency[i].size(), ", ".join(nbs), str(eng), str(ind)])
		if kill_eg == "" and ind_dead:
			kill_eg = "t%d 度%d 填满 %d 个邻居后被做死（引擎判自杀=%s）" % [
				i, adjacency[i].size(), adjacency[i].size(), str(eng_dead)]
	print("[hatdead] ⑤ 低度格做死实验：%d 个，判据分歧 %d 个（须 0）｜样例：%s"
		% [kill_n, kill_bad, kill_eg])
	if kill_bad > 0:
		ok = false

	# ---------- ⑥ 端到端**真点击**：合成鼠标左键走「_input → GUI → 物理拾取」的真实管线，
	#    看棋盘是否真的落子。①②④⑤ 全是离线算的，只有这条能复现用户的症状。
	#    每个候选格取两点做**对照**：A 安全点（多边形内、离所有 STOP 控件最远）、
	#    B 被压点（多边形内、确实落在 STOP 矩形里）。预期 A 落得上、B 落不上。
	#    ★ 阳性对照：先点一个中心空点；它都落不上就说明拾取管线整体没生效 → 本项作废，
	#      否则会把「全都没落上」当成「没遮挡」的假绿（正是"修 bug 前就是绿的"那种探针）。
	var mode_save: int = game_mode
	game_mode = LOCAL          # 免 AI 抢手 / 免联机分支，只看拾取本身
	game_over = false
	is_ai_thinking = false
	current_player = PLAYER_COLOR
	_update_hud()
	await get_tree().process_frame
	print("[hatdead] ⑥ 物理拾取开关 physics_object_picking=%s（false 则合成点击永不可能生效）"
		% str(get_viewport().physics_object_picking))
	var vc2 := Vector2(get_viewport_rect().size) * 0.5
	var mid_t := -1
	var mid_d := INF
	for i in tiles.size():
		if board[i] != Stone.EMPTY:
			continue
		var dm: float = tile_centers[i].distance_to(vc2)
		if dm < mid_d:
			mid_d = dm
			mid_t = i
	# ★ 阳性对照必须**分两层**量（上一轮把两层混成一条，才误判成「拾取管线坏了」）：
	#   ⑥a **直接调** `_on_area_input`（绕过物理拾取）→ 验处理函数 + `place_stone`；
	#   ⑥b **合成事件** `push_input` → 验引擎能把事件派发到 Area2D 的 `input_event`。
	#   判据（base_ok）只取 ⑥a —— 它反映的是**游戏逻辑**；⑥b 只是"我的探针能不能合成点击"。
	var seen := [0]
	var cb := func(_vp, ev2, _si):
		seen[0] = int(seen[0]) + 1
		if ev2 is InputEventMouseButton:
			print("[hatdead]      input_event 内容：pos=%s global=%s pressed=%s button=%d ｜ 按该 pos 查拾取器 → t%s"
				% [str((ev2 as InputEventMouseButton).position),
					str((ev2 as InputEventMouseButton).global_position),
					str((ev2 as InputEventMouseButton).pressed),
					(ev2 as InputEventMouseButton).button_index,
					str(_tile_at_point((ev2 as InputEventMouseButton).position))])
		else:
			print("[hatdead]      input_event 内容：非鼠标键 %s" % str(ev2))
	var p_in := Vector2(-1, -1)
	var direct_ok := false
	var direct_ids: Array = []
	if mid_t >= 0:
		p_in = _hat_safe_point(mid_t, stops)
	if p_in.x >= 0.0:
		var evd := InputEventMouseButton.new()
		evd.button_index = MOUSE_BUTTON_LEFT
		evd.button_mask = MOUSE_BUTTON_MASK_LEFT
		evd.pressed = true
		evd.position = p_in
		evd.global_position = p_in
		var sd: Dictionary = board.duplicate()
		_on_area_input(get_viewport(), evd, -1)
		for k in board.keys():
			if int(sd.get(k, Stone.EMPTY)) == Stone.EMPTY and board[k] != Stone.EMPTY:
				direct_ids.append(k)
		direct_ok = direct_ids.size() > 0
		board.clear()
		for k in sd.keys():
			board[k] = sd[k]
		current_player = PLAYER_COLOR
	print("[hatdead] ⑥a 直接调 _on_area_input（绕过拾取）：空点 t%d 多边形内点%s → %s%s"
		% [mid_t, str(p_in.round()), "落子 ✓" if direct_ok else "没落子 ✗",
			("；落在 t%s（拾取器判 t%s）" % [str(direct_ids), str(_tile_at_point(p_in))])
				if direct_ok else ""])
	click_area.input_event.connect(cb)
	var r0: Dictionary = await _hat_click_probe(mid_t, p_in)
	click_area.input_event.disconnect(cb)
	print("[hatdead] ⑥b 合成事件 push_input → input_event 触发 %d 次、落子 %s（拾取器判 t%s）"
		% [seen[0], "✓" if r0["ok"] else "✗", str(r0["picked"])])
	var base_ok: bool = direct_ok
	var n_ab := 0
	var n_a_ok := 0
	var n_b_ok := 0
	for e in cov:
		var ab: Dictionary = await _hat_click_ab(int(e["t"]), stops)
		n_ab += 1
		if bool(ab["a_ok"]):
			n_a_ok += 1
		if bool(ab["b_ok"]):
			n_b_ok += 1
		print("[hatdead]     t%d 被压%.0f%% ｜ A安全点%s 拾取t%s → %s ｜ B被压点%s 拾取t%s → %s"
			% [e["t"], float(e["frac"]) * 100.0,
				str((ab["pa"] as Vector2).round()), str(ab["pa_pick"]),
				"落✓" if ab["a_ok"] else "落✗",
				str((ab["pb"] as Vector2).round()), str(ab["pb_pick"]),
				"落✓" if ab["b_ok"] else "落✗"])
	print("[hatdead] ⑥ 对照 %d 格：安全点落子 %d、被压点落子 %d" % [n_ab, n_a_ok, n_b_ok])
	if not base_ok:
		print("[hatdead]    ✗ ⑥a 失败 → 处理函数 / place_stone 这条路上有问题")
		ok = false
	elif not bool(r0["ok"]):
		print("[hatdead]    ⚠ ⑥a 通过但 ⑥b 派发不通 → 合成点击不可用（探针限制，非游戏问题）；⑥/⑦ 的 A|B 对照不作结论")
	elif n_ab > 0 and n_a_ok == n_ab and n_b_ok < n_ab:
		print("[hatdead]    ✗ 已复现：被 HUD 压住的格子点不动、安全处可落 —— 与用户症状一致")
		ok = false
	elif n_ab > 0 and n_b_ok == n_ab:
		print("[hatdead]    → STOP 控件**没有**吃掉点击（物理拾取与 GUI 互不阻塞）")
	game_mode = mode_save

	# ---------- ⑦ 窗口尺寸扫描：`_build_game_hud` 把 HUD 钉在 (vs.x-320, vs.y-110)，
	#    而 `_adapt_to_screen` 只留 40px 边距 —— 两者的相对位置**随窗口尺寸/宽高比变化**。
	#    本机 1152×720 下 ①b 是 0，所以「右侧点不动」若与 HUD 有关，只可能出现在别的尺寸下。
	var sizes: Array = [Vector2i(1152, 720), Vector2i(1280, 720), Vector2i(1366, 768),
		Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1152, 1152), Vector2i(2560, 1080)]
	var winsz: Vector2i = get_window().size
	for s in sizes:
		get_window().size = s
		await get_tree().process_frame
		await get_tree().process_frame
		_adapt_to_screen()
		_update_hud()
		await get_tree().process_frame
		var stops2: Array = []
		_collect_stop_controls(self, stops2)
		var hit := 0
		var worst := 0.0
		var worst_t := -1
		for i in tiles.size():
			if board[i] != Stone.EMPTY:
				continue
			var fr2: float = float(_hat_cover_frac(i, stops2, false)["frac"])
			if fr2 > 0.0:
				hit += 1
				if fr2 > worst:
					worst = fr2
					worst_t = i
		var ov2: Dictionary = _hat_overflow()
		print("[hatdead] ⑦ 窗口%s 视口%s ｜HUD %s｜ 被压空点 %d（最重 t%d %.0f%%）｜可点框 %s 越界格 %d（最重 t%s %.0fpx）"
			% [str(s), str(get_viewport_rect().size), _hat_rects_str(stops2),
				hit, worst_t, worst * 100.0, str(ov2["rect"]), int(ov2["n"]),
				str(ov2["t"]), float(ov2["worst"])])
		if hit > 0:
			ok = false
			# 被压格子**就地**做 A/B 真点击：这是「GUI 会不会吃掉点击」的直接证据，
			# 比"矩形相交"更硬 —— 相交不等于事件真的被吞掉。
			var mode2: int = game_mode
			game_mode = LOCAL
			game_over = false
			is_ai_thinking = false
			current_player = PLAYER_COLOR
			var ab2: Dictionary = await _hat_click_ab(worst_t, stops2)
			game_mode = mode2
			print("[hatdead] ⑦   A安全点%s 拾取t%s → %s ｜ B被压点%s 拾取t%s → %s"
				% [str((ab2["pa"] as Vector2).round()), str(ab2["pa_pick"]),
					"落✓" if ab2["a_ok"] else "落✗",
					str((ab2["pb"] as Vector2).round()), str(ab2["pb_pick"]),
					"落✓" if ab2["b_ok"] else "落✗"])
	get_window().size = winsz
	await get_tree().process_frame
	await get_tree().process_frame
	_adapt_to_screen()
	_update_hud()

	print("[hatdead] 结论：%s" % ("通过 ✓" if ok else "失败 ✗"))
	get_tree().quit()

## 独立复刻「落子 → 提掉死串 → 数自己新块的气」，**只读 adjacency / board**，
## 不调用 get_group / get_liberties —— 用来跟引擎的着手体检对拍（⑤ 的两条独立路径）。
func _hat_indep_place_check(p: int, color: int) -> Dictionary:
	var opp: int = Stone.WHITE if color == Stone.BLACK else Stone.BLACK
	var save: Dictionary = board.duplicate()
	board[p] = color
	var seen: Dictionary = {}
	var captured: Array[int] = []
	for nb in adjacency[p]:
		if board[nb] != opp or seen.has(nb):
			continue
		var grp: Array[int] = [nb]
		seen[nb] = true
		var qi := 0
		while qi < grp.size():
			var cur: int = grp[qi]
			qi += 1
			for x in adjacency[cur]:
				if board[x] == opp and not seen.has(x):
					seen[x] = true
					grp.append(x)
		var lp: Dictionary = {}
		for m in grp:
			for x in adjacency[m]:
				if board[x] == Stone.EMPTY:
					lp[x] = true
		if lp.is_empty():
			captured.append_array(grp)
	for v in captured:
		board[v] = Stone.EMPTY
	var mine: Array[int] = [p]
	var seen2: Dictionary = {p: true}
	var qi2 := 0
	while qi2 < mine.size():
		var cur2: int = mine[qi2]
		qi2 += 1
		for x in adjacency[cur2]:
			if board[x] == color and not seen2.has(x):
				seen2[x] = true
				mine.append(x)
	var lp2: Dictionary = {}
	for m in mine:
		for x in adjacency[m]:
			if board[x] == Stone.EMPTY:
				lp2[x] = true
	board.clear()
	for k in save.keys():
		board[k] = save[k]
	return {"libs": lp2.size(), "cap": captured.size()}

## 递归收集**可见**且 `mouse_filter = STOP` 的 Control。
## CanvasLayer 自身没有 rect，只递归它的子节点（控件坐标即屏幕坐标）。
func _collect_stop_controls(node: Node, out: Array) -> void:
	for ch in node.get_children():
		if ch is CanvasLayer:
			if (ch as CanvasLayer).visible:
				_collect_stop_controls(ch, out)
			continue
		if ch is Control:
			var c := ch as Control
			if not c.visible:
				continue
			if c.mouse_filter == Control.MOUSE_FILTER_STOP:
				out.append(c)
			_collect_stop_controls(c, out)
			continue
		_collect_stop_controls(ch, out)

## 在格子多边形内找一个「离所有 STOP 控件最远」的采样点，用作 ⑥ 的 **A 安全点**。
## 返回 Vector2(-1, -1) 表示该格多边形被完全压住（找不到安全点）。
func _hat_safe_point(tile_id: int, stops: Array) -> Vector2:
	var poly := PackedVector2Array()
	for idx in tiles[tile_id]:
		poly.append(vertices[idx])
	var bb := Rect2(poly[0], Vector2.ZERO)
	for vv in poly:
		bb = bb.expand(vv)
	var best := Vector2(-1, -1)
	var best_d := -1.0
	var sx := bb.position.x
	while sx <= bb.end.x:
		var sy := bb.position.y
		while sy <= bb.end.y:
			var p := Vector2(sx, sy)
			sy += 3.0
			if Geometry2D.is_point_in_polygon(p, poly):
				var d := INF
				for c in stops:
					var r: Rect2 = (c as Control).get_global_rect()
					var q := Vector2(clampf(p.x, r.position.x, r.end.x),
						clampf(p.y, r.position.y, r.end.y))
					d = minf(d, p.distance_to(q))
				if d > best_d:
					best_d = d
					best = p
		sx += 3.0
	return best

## 在格子多边形内按 3px 网格采样，统计被 STOP 控件矩形压住的采样点。
## 返回 {"tot","blk","frac","bp","r","holes"}。`with_pick_check` 为真时额外统计
## 「点在多边形内、`_tile_at_point` 却返回 -1」的**拾取漏洞**点数（这才是该为 0 的那一项）。
func _hat_cover_frac(tile_id: int, stops: Array, with_pick_check := true) -> Dictionary:
	var poly := PackedVector2Array()
	for idx in tiles[tile_id]:
		poly.append(vertices[idx])
	var bb := Rect2(poly[0], Vector2.ZERO)
	for vv in poly:
		bb = bb.expand(vv)
	var tot := 0
	var blk := 0
	var holes := 0
	var bp := Vector2.ZERO
	var r := Rect2()
	var bx0 := INF
	var bx1 := -INF
	var by0 := INF
	var by1 := -INF
	var sx := bb.position.x
	while sx <= bb.end.x:
		var sy := bb.position.y
		while sy <= bb.end.y:
			var p := Vector2(sx, sy)
			sy += 3.0
			if not Geometry2D.is_point_in_polygon(p, poly):
				continue
			tot += 1
			if with_pick_check and _tile_at_point(p) == -1:
				holes += 1
			for c in stops:
				if (c as Control).get_global_rect().has_point(p):
					if blk == 0:
						bp = p
					blk += 1
					bx0 = minf(bx0, p.x)
					bx1 = maxf(bx1, p.x)
					by0 = minf(by0, p.y)
					by1 = maxf(by1, p.y)
					break
		sx += 3.0
	if blk > 0:
		r = Rect2(bx0, by0, bx1 - bx0, by1 - by0)
	var fr := 0.0
	if tot > 0:
		fr = float(blk) / float(tot)
	return {"tot": tot, "blk": blk, "frac": fr, "bp": bp, "r": r, "holes": holes}

## 统计有多少格子的多边形**有一部分落在 `click_area` 可点矩形之外** —— 那部分区域物理拾取
## 收不到事件，点了**静默无效**（既不落子、也不报"已有子/自杀"）。
## 返回 {"n": 越界格数, "worst": 最大越界像素, "t": 最重格 id, "rect": 可点矩形}。
func _hat_overflow() -> Dictionary:
	var ar := Rect2()
	if click_area != null:
		for ch in click_area.get_children():
			if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
				var sz: Vector2 = ((ch as CollisionShape2D).shape as RectangleShape2D).size
				ar = Rect2(click_area.global_position - sz * 0.5, sz)
	var n := 0
	var worst := 0.0
	var wt := -1
	for i in tiles.size():
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for idx in tiles[i]:
			var v: Vector2 = vertices[idx]
			mn.x = minf(mn.x, v.x)
			mn.y = minf(mn.y, v.y)
			mx.x = maxf(mx.x, v.x)
			mx.y = maxf(mx.y, v.y)
		if not ar.encloses(Rect2(mn, mx - mn)):
			n += 1
			var od: float = maxf(maxf(ar.position.x - mn.x, mx.x - ar.end.x),
				maxf(ar.position.y - mn.y, mx.y - ar.end.y))
			if od > worst:
				worst = od
				wt = i
	return {"n": n, "worst": worst, "t": wt, "rect": ar}

## 把 STOP 控件矩形拼成一行（只记位置/尺寸，不记节点路径，免得日志太长）。
func _hat_rects_str(stops: Array) -> String:
	var out: Array = []
	for c in stops:
		var r: Rect2 = (c as Control).get_global_rect()
		out.append("(%.0f,%.0f,%.0f,%.0f)" % [r.position.x, r.position.y, r.size.x, r.size.y])
	return " ".join(out)

## 合成一次**真实**左键按下，走 viewport 的「GUI → 物理拾取」真实管线。
## 返回 {"ok": 是否真的落了子, "ids": 新子所在格, "picked": 拾取器认为点到了哪一格}。
## 无论成败都还原棋盘（避免污染后面的候选）。
## ⚠️ 必须等**物理帧**：Godot 4 的物体拾取不在 `push_input` 里当场派发，而是把鼠标事件排进
##    队列，在 `_process_picking()`（物理帧）里才做 `intersect_point` 并回调 `input_event`。
##    只等 `process_frame` 会**永远**拿到「没落子」的假结论。
## ⚠️ 判「是否落子」不能只看 `tile_id`：拾取器可能把点判给**邻居**，那时 tile_id 没变、
##    邻居变了 —— 只看 tile_id 会得到"没落子"的假红（上一轮就是这么错的两层）。
func _hat_click_probe(tile_id: int, p: Vector2) -> Dictionary:
	var save: Dictionary = board.duplicate()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.pressed = true
	# ⚠️ 坐标系：`push_input` 收的是**窗口像素坐标**，而 `_tile_at_point`/`vertices` 用的是
	#    **视口逻辑坐标**；引擎在物理拾取时会把事件位置按 `get_final_transform()` 的**逆**变换
	#    压到逻辑空间（实测：我给 (491,338)，处理函数收到 (327,225)，正好 ×0.666 = 1/1.5）。
	#    所以先乘上 `get_final_transform()` 抵消掉，探针才落在与棋盘同一套坐标里。
	var xf: Transform2D = get_viewport().get_final_transform()
	var pw: Vector2 = xf * p
	ev.position = pw
	ev.global_position = pw
	var picked: int = _tile_at_point(p)
	get_viewport().push_input(ev)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ids: Array = []
	for k in board.keys():
		if int(save.get(k, Stone.EMPTY)) == Stone.EMPTY and board[k] != Stone.EMPTY:
			ids.append(k)
	board.clear()
	for k in save.keys():
		board[k] = save[k]
	current_player = PLAYER_COLOR
	return {"ok": ids.size() > 0, "ids": ids, "picked": picked, "tile": tile_id}

## 对指定格子做 A（安全点）/ B（被压点）**真实点击对照**。
## 返回 {"pa","pa_pick","a_ok","pb","pb_pick","b_ok"}；无被压区时 b_* 恒为 false。
func _hat_click_ab(tile_id: int, stops: Array) -> Dictionary:
	var pa: Vector2 = _hat_safe_point(tile_id, stops)
	var q: Dictionary = _hat_cover_frac(tile_id, stops, false)
	var pa_pick := -1
	var a_ok := false
	if pa.x >= 0.0:
		pa_pick = _tile_at_point(pa)
		var r: Dictionary = await _hat_click_probe(tile_id, pa)
		a_ok = bool(r["ok"])
	var pb: Vector2 = q["bp"]
	var pb_pick := -1
	var b_ok := false
	if int(q["blk"]) > 0:
		pb_pick = _tile_at_point(pb)
		var r2: Dictionary = await _hat_click_probe(tile_id, pb)
		b_ok = bool(r2["ok"])
	return {"pa": pa, "pa_pick": pa_pick, "a_ok": a_ok,
		"pb": pb, "pb_pick": pb_pick, "b_ok": b_ok}

## 自检（--esctest）：ESC 暂停面板。模拟按键事件走真实 `_input` 路径（不发真实键）。
func _esc_test() -> void:
	var ok := true
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	# ① 按 ESC → 面板出现（替代旧行为「直接切回主菜单」）
	_input(ev)
	if _pause_layer == null:
		ok = false
	# ② 面板里有「继续对局 / 返回主菜单 / 退出游戏」三个按钮
	var btns := {}
	_collect_buttons(_pause_layer, btns)
	if not (btns.has("PauseContinue") and btns.has("PauseBack") and btns.has("PauseQuit")):
		ok = false
	# ③ 面板开着时鼠标点击不落子（物理拾取与遮罩是两条管线，靠显式守卫拦截）
	var me := InputEventMouseButton.new()
	me.button_index = MOUSE_BUTTON_LEFT
	me.pressed = true
	var stones_before := 0
	for v in board.size():
		if board[v] != Stone.EMPTY:
			stones_before += 1
	_on_area_input(null, me, 0)
	var stones_after := 0
	for v in board.size():
		if board[v] != Stone.EMPTY:
			stones_after += 1
	if stones_before != stones_after:
		ok = false
	# ④ 再按 ESC → 面板关闭
	_input(ev)
	if _pause_layer != null:
		ok = false
	# ⑤ 「继续对局」回调关闭面板（PauseQuit 不按 —— 会真的退出程序）
	_input(ev)
	(btns["PauseContinue"] as Button).pressed.emit()
	if _pause_layer != null:
		ok = false
	# ⑥ 居中：布局完成后面板中心应与视口中心重合（缩放窗口后由 size_changed 跟随，同口径）
	_input(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	if _pause_panel != null and is_instance_valid(_pause_panel):
		var pc: Vector2 = _pause_panel.position + _pause_panel.size * 0.5
		if (pc - get_viewport_rect().size * 0.5).length() > 1.0:
			ok = false
	else:
		ok = false
	# ⑦ 面板文字对比度（对**面板自己的底色**算，不是对棋盘背景）：标题/正文/按钮三项都要达标，
	#    且阴性对照必须报警（=判据确实抓得住"字看不清"这个 bug）。
	#    ⚠️ 必须在面板**还开着**的时候量 —— `_clear_pause_menu()` 之后控件就没了。
	var jr: Array = GameConfig.judge_dialog_contrast(_pause_layer)
	var ok_c: bool = bool(jr[0])
	if not ok_c:
		ok = false
	# ⑧ 字体接线：**整场**（含 `CanvasLayer` 浮层）的带字控件都必须用主题字体。
	#   ★★ 为什么必须在这里量：本场景的 UI 几乎全在 `CanvasLayer` 里（HUD / 暂停 / 认输 / 结果 /
	#     复盘工具条…），而 `Control` 的主题继承链**只走 Control 与 Window** —— 中间夹一层
	#     CanvasLayer 就断（它两者都不是）⇒ 浮层里的字退回**引擎默认字体**：界面照常显示、
	#     判据全绿，只有"这里的字跟别处不一样"没人管。这条判据就是那件事的嘴
	#     （菜单侧的同款判据在 `--menutest` ⑰）。
	#   ⚠️ 同样必须在面板**还开着**的时候量（面板里的控件也要进样本）。
	var f_bad: Array[String] = []
	var f_ok_n: int = 0
	var f_bad_n: int = 0
	var ctls8: Array[Control] = []
	GameConfig.collect_controls(self, ctls8)
	var f_deg_n: int = 0
	for c8 in ctls8:
		if not (c8 is Label or c8 is Button or c8 is LineEdit):
			continue
		var f8: Font = c8.get_theme_font("font")
		if not UITheme.is_theme_font(f8):
			f_deg_n += 1
		if f8 == UITheme.body_font() or f8 == UITheme.display_font():
			f_ok_n += 1
		else:
			f_bad_n += 1
			if f_bad.size() < 3:
				f_bad.append("%s「%s」" % [c8.get_class(), String(c8.name).substr(0, 12)])
	#   ★★ 2026-10-15 补牙（**下刀实测逮到本条当时是恒真式**）：
	#     把 `UITokens.FONT_BODY` 指向一个不存在的路径（= 复现"字体三份有两份没生效"那次事故）
	#     之后，本条**照样报「19/19 主题字体·异常 0 → 通过 ✓」**。根因不是漏比，而是
	#     **两边同时退化**：字体缺失 ⇒ `UITheme.build()` 里 `if _body != null` 不成立 ⇒ 主题
	#     **压根没写** `default_font` ⇒ `get_theme_font("font")` 掉回引擎默认；而
	#     `UITheme.body_font()` 也退化到 `ThemeDB.fallback_font` —— **同一个对象** ⇒ 恒等 ⇒ 恒绿。
	#     这与铁律 13 同型：**判据与被测物共享同一个"退化出口"时，"两边相等"不构成证据**
	#     （同型先例见 §106：判据要跑在能触发目标分支的局面；以及铁律 68：把没量到印成满分）。
	#   ★★ 第一版补牙**写错了**，值得留着当教训（§108：红了先疑判据）：我写成
	#     `f8 == ThemeDB.fallback_font ⇒ 算退化`。它假红 —— 因为 `apply_ui_theme()` 末尾那句
	#     `ThemeDB.fallback_font = UITheme.body_font()`（次要保险）把这个参照物**换成了我们自己**，
	#     于是字体一切正常时**每个**控件都"等于兜底"（实测撤刀后 19/19 全报退化）。
	#     ⇒ 真凶是判据挑错了参照物，**不是**代码有问题；没有去改代码迁就它，而是换口径。
	#   ⇒ 正解 = 问"它到底从**哪个文件**来的"：`UITheme.is_theme_font()` 查 `resource_path`
	#     是否等于三个 token 路径之一（我们的字体有文件；引擎内建兜底字体是空串）。
	#     这条口径**绕开 fallback 那个出口**，双向实测：刀下 19/19 报退化（红）、撤刀后 0（绿）。
	#   两条断言，各查一件事：① 三份字体必须真的到位（`UITheme.fonts_ready()`，查资源存在性）；
	#   ② 控件的实际生效字体必须来自我们的字体文件（查"没掉进退化出口"）。
	var f_ready: bool = UITheme.fonts_ready()
	var ok_f: bool = f_bad_n == 0 and f_ok_n >= 8 and f_ready and f_deg_n == 0
	if not ok_f:
		ok = false
	_clear_pause_menu()
	print("[esctest] 开/按钮/落子拦截/ESC关/继续关/居中 = %s → %s" % [str(ok), "通过 ✓" if ok else "失败 ✗"])
	print("[esctest] ⑦ 面板文字对比度：%s → %s" % [String(jr[1]), "通过 ✓" if ok_c else "失败 ✗"])
	print("[esctest] ⑧ 字体接线：带字控件 %d 个·主题字体 %d·异常 %d·字体到位=%s·引擎兜底 %d %s → %s" % [
		f_ok_n + f_bad_n, f_ok_n, f_bad_n, str(f_ready), f_deg_n, str(f_bad),
		"通过 ✓" if ok_f else "失败 ✗"])
	get_tree().quit()

## 递归收集子树里的 Button（按 name 索引）
func _collect_buttons(node: Node, out: Dictionary) -> void:
	for c in node.get_children():
		if c is Button:
			out[String(c.name)] = c
		_collect_buttons(c, out)

## 自检辅助：把引擎内部棋盘倒进对局 `board`。
## 不能直接 `board = ai_engine.export_board()` —— `export_board()` 只含**非空**点，
## 而对局侧的不变量是「每个瓷砖 id 都有值」。直接替换后同一帧的 `_draw()/_update_hud()`
## 会按 id 取值并撞上缺失键（日志里表现为 `Out of bounds get index '103' on base Dictionary`）。
func _load_board_from_engine() -> void:
	var exp: Dictionary = ai_engine.export_board()
	for i in tiles.size():
		board[i] = int(exp.get(i, Stone.EMPTY))
	ko_point = -1
	_last_move = -1

## 测试辅助：按比例摆盘 —— 前 black_ratio×n 格放黑、接着 white_ratio×n 格放白，其余留空。
## 直接写 `board` 而不走 `place_stone`：不触发提子/轮次/动画逻辑，局面完全可控可复现。
func _lay_ratio_board(black_ratio: float, white_ratio: float) -> void:
	for vid in board.keys():
		board[vid] = Stone.EMPTY
	black_prisoners = 0
	white_prisoners = 0
	ko_point = -1
	_last_move = -1
	passes = 0
	game_over = false
	var n: int = tiles.size()
	var nb: int = clampi(int(float(n) * black_ratio), 0, n)
	var nw: int = clampi(int(float(n) * white_ratio), 0, n - nb)
	for i in nb:
		board[i] = Stone.BLACK
	for i in range(nb, nb + nw):
		board[i] = Stone.WHITE

## 自检（--resigntest）：AI 主动认输的判据。
##
## 四个用例刻意选成**与领地归属无关**的局面，所以结论不依赖 flood fill 的具体划分、
## 是确定性的、可反复回归的：
##   ① 黑 60% / 白 10% / 空 30% → 白方（AI）无论如何都追不上 → 必认
##   ② 黑 10% / 白 35%       → AI 反而领先 → 绝不认
##   ③ 同①，但把「最少手数」门槛提到 110% → 下限保护生效，必不认
##   ④ 同①，但关掉总开关 `ai_resign_enabled` → 必不认
func _resign_self_test() -> void:
	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	generate_penrose()
	_adapt_to_screen()
	game_mode = VS_AI
	reset_game(true)
	var n: int = tiles.size()
	var ok := true

	# ① 绝望局面 → 必认
	_lay_ratio_board(0.60, 0.10)
	var ev: Dictionary = _ai_resign_eval()
	var c1: bool = bool(ev["should_resign"])
	print("[resigntest] ① 绝望局面 → 落后 %d 点, 空点 %d, 余量 %d, 已落 %d 手（门槛 %d）→ 认输=%s（期望 true）" % [
		ev["deficit"], ev["empties"], ev["margin"], ev["played"], ev["min_played"], c1])
	if not c1:
		ok = false

	# ② AI 领先 → 绝不认
	_lay_ratio_board(0.10, 0.35)
	var ev2: Dictionary = _ai_resign_eval()
	var c2: bool = bool(ev2["should_resign"])
	print("[resigntest] ② AI 领先 %d 点 → 认输=%s（期望 false）" % [-int(ev2["deficit"]), c2])
	if c2:
		ok = false

	# ③ 手数下限保护：门槛提到 110%，即使局面绝望也不许认
	_lay_ratio_board(0.60, 0.10)
	var saved_min: float = ai_resign_min_stones_ratio
	ai_resign_min_stones_ratio = 1.10
	var ev3: Dictionary = _ai_resign_eval()
	var c3: bool = bool(ev3["should_resign"])
	print("[resigntest] ③ 门槛提到 110%%（已落 %d < 门槛 %d）→ 认输=%s（期望 false）" % [
		ev3["played"], ev3["min_played"], c3])
	if c3:
		ok = false
	ai_resign_min_stones_ratio = saved_min

	# ④ 总开关关闭 → 一律不认
	var saved_on: bool = ai_resign_enabled
	ai_resign_enabled = false
	var c4: bool = bool(_ai_resign_eval()["should_resign"])
	print("[resigntest] ④ 关掉 ai_resign_enabled → 认输=%s（期望 false）" % c4)
	if c4:
		ok = false
	ai_resign_enabled = saved_on

	# ⑤ 端到端：绝望局面下走一次 AI 回合，必须直接以认输终局（而不是落子）
	_lay_ratio_board(0.60, 0.10)
	current_player = AI_COLOR
	var resigned: bool = _ai_try_resign()
	print("[resigntest] ⑤ 走一次 AI 回合 → 认输终局=%s game_over=%s（期望 true/true）" % [
		resigned, game_over])
	if not resigned or not game_over:
		ok = false

	print("[resigntest] 结果：", "通过 ✓" if ok else "失败 ✗")
	print("[resigntest] 棋盘格数=%d（用例比例基于此计算）" % n)
	get_tree().quit()

## 自检（--counttest）：「对方停一手 → 是否数子」提示。
## 覆盖：① 三种模式各自的触发条件  ② 停一手后确实弹出且未终局
##       ③ 「继续下棋」只关提示、盘面不变  ④ 再停一手构成连续停手 → 直接终局
##       ⑤ 「数子终局」立即结算
func _count_self_test() -> void:
	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	generate_penrose()
	_adapt_to_screen()
	var ok := true

	# ① 触发条件：只有「对方停手」才弹，自己点的停一手不弹给自己
	game_mode = VS_AI
	var m1: bool = _should_prompt_count(AI_COLOR) and not _should_prompt_count(PLAYER_COLOR)
	print("[counttest] ① 人机：AI停手→弹=%s, 玩家停手→弹=%s（期望 true/false）" % [
		_should_prompt_count(AI_COLOR), _should_prompt_count(PLAYER_COLOR)])
	if not m1:
		ok = false
	game_mode = LOCAL
	var m2: bool = _should_prompt_count(Stone.BLACK) and _should_prompt_count(Stone.WHITE)
	print("[counttest] ① 本地双人：任一方停手都弹=%s（期望 true）" % m2)
	if not m2:
		ok = false
	game_mode = ONLINE
	_net_color = Stone.BLACK
	var m3: bool = _should_prompt_count(Stone.WHITE) and not _should_prompt_count(Stone.BLACK)
	print("[counttest] ① 联机（本机执黑）：对方(白)停手→弹=%s, 自己(黑)停手→弹=%s（期望 true/false）" % [
		_should_prompt_count(Stone.WHITE), _should_prompt_count(Stone.BLACK)])
	if not m3:
		ok = false

	# ② 本地双人实际停一手 → 弹出提示、passes=1、未终局
	game_mode = LOCAL
	reset_game(true)
	_on_pass_pressed()
	var c2: bool = _count_layer != null and passes == 1 and not game_over
	print("[counttest] ② 停一手后 → 提示弹出=%s passes=%d game_over=%s（期望 true/1/false）" % [
		_count_layer != null, passes, game_over])
	if not c2:
		ok = false

	# ②b 面板居中：等一帧让容器算出真实尺寸，比较面板中心与视口中心
	# （原先按硬编码的 -215/-95 偏移定位，内容行数一变就偏；headless 截不了图，只能量）
	await get_tree().process_frame
	var c2b: bool = _popup_centered(_count_layer, "②b 数子提示面板")
	if not c2b:
		ok = false

	# ③ 「继续下棋」→ 提示关闭，仍未终局，轮次保持
	var turn_before: int = current_player
	_on_count_declined()
	var c3: bool = _count_layer == null and not game_over and current_player == turn_before
	print("[counttest] ③ 点「继续下棋」→ 提示关闭=%s game_over=%s 轮次不变=%s（期望 true/false/true）" % [
		_count_layer == null, game_over, current_player == turn_before])
	if not c3:
		ok = false

	# ④ 再停一手 → 连续两次停手，按规则直接终局，且不重复弹提示
	_on_pass_pressed()
	var c4: bool = game_over and _count_layer == null and passes >= 2
	print("[counttest] ④ 连续第二次停手 → game_over=%s passes=%d 提示残留=%s（期望 true/2/false）" % [
		game_over, passes, _count_layer != null])
	if not c4:
		ok = false

	# ⑤ 「数子终局」→ 立即结算
	reset_game(true)
	_on_pass_pressed()
	_on_count_confirmed()
	var c5: bool = game_over and _count_layer == null
	print("[counttest] ⑤ 点「数子终局」→ game_over=%s 提示关闭=%s（期望 true/true）" % [
		game_over, _count_layer == null])
	if not c5:
		ok = false

	# ⑤b 结算面板居中（同一套 _center_popup）
	await get_tree().process_frame
	var c5b: bool = _popup_centered(_result_layer, "⑤b 结算面板")
	if not c5b:
		ok = false

	# ⑥ 无视提示直接落子 = 用行动选「继续」→ 提示应收掉、停手计数清零、对局继续
	reset_game(true)
	_on_pass_pressed()
	var prompt_open: bool = _count_layer != null
	var vid: int = _random_legal_move()
	var placed: bool = vid >= 0 and place_stone(vid, false)
	var c6: bool = prompt_open and placed and _count_layer == null and passes == 0 and not game_over
	print("[counttest] ⑥ 提示弹出=%s → 直接落子%s → 提示关闭=%s passes=%d game_over=%s（期望 true/true/true/0/false）" % [
		prompt_open, "成功" if placed else "失败", _count_layer == null, passes, game_over])
	if not c6:
		ok = false

	print("[counttest] 结果：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 自检辅助：弹窗是否真正居中（取层内第一个 Control，比较它与视口中心的偏差）
func _popup_centered(layer: CanvasLayer, tag: String) -> bool:
	if layer == null or not is_instance_valid(layer) or layer.get_child_count() == 0:
		print("[counttest] %s：✗ 面板不存在" % tag)
		return false
	var panel := layer.get_child(0) as Control
	if panel == null:
		print("[counttest] %s：✗ 首个子节点不是 Control" % tag)
		return false
	var r := panel.get_global_rect()
	var vs := get_viewport_rect().size
	var off := (r.get_center() - vs * 0.5).abs()
	var good: bool = off.x <= 2.0 and off.y <= 2.0
	print("[counttest] %s：尺寸=%s 中心偏差=(%.1f, %.1f) → %s" % [
		tag, str(r.size), off.x, off.y, "✓" if good else "✗ 未居中"])
	return good

## `--aibud` 的盘型 token 收集（去重）。调用方用空数组起步 = 只跑彭罗斯。
func _aibud_add_board(bts: Array[int], bt: int) -> void:
	if not bts.has(bt):
		bts.append(bt)

## 盘型 token → GameConfig 常量；不认识返回 -1。aibud / aieye / aitune / aidata
## 四个仪器的盘型解析共用（逗号连写时逐个过这里）。
func _bt_token_id(tok: String) -> int:
	match tok:
		"pen":
			return GameConfig.BOARD_PENROSE
		"cube":
			return GameConfig.BOARD_CUBE
		"kite":
			return GameConfig.BOARD_KITE
		"snow":
			return GameConfig.BOARD_SNOWFLAKE
		"hat":
			return GameConfig.BOARD_HAT
	return -1

## 逗号连写盘型（如 "pen,snow,hat"）：**全部**是合法盘型才接管（加进 bts 并返回
## true）；否则不动 bts、返回 false，让调用方落到各自的前缀分支（如 aibud 的
## b150,300,600 预算列表）。
## ★ 必须在每个解析器 `_` 分支的**最前面**调用：否则 "pen,…" 被 p 前缀吞、
##   "snow,…" 被 s 前缀吞（--aidata 实测：三盘连写被静默吃成单盘彭罗斯，
##   照常出结果、exit 0 —— 「少跑了两个盘」和「三盘都过了」长得一模一样）。
func _aibud_try_board_list(tok: String, bts: Array[int]) -> bool:
	if not ("," in tok):
		return false
	var ids: Array[int] = []
	for pt in tok.split(",", false):
		var bid := _bt_token_id(pt)
		if bid < 0:
			return false
		ids.append(bid)
	for bid in ids:
		_aibud_add_board(bts, bid)
	return true

## 盘型显示名。**game.gd 里原本只在 `_ready()` 用局部变量拼过一次**（board_name），
## 没有可复用的函数 —— 自检要按盘型分组打印，就补这一个。
func _bt_name(bt: int) -> String:
	match bt:
		GameConfig.BOARD_CUBE: return "立方体"
		GameConfig.BOARD_KITE: return "筝形"
		GameConfig.BOARD_SNOWFLAKE: return "雪花"
		GameConfig.BOARD_HAT: return "爱因斯坦"
		_: return "彭罗斯"

## 按 GameConfig.board_type 生成对应盘。原来是写死的 generate_penrose()，
## 于是 `--aibud` 无论怎么调都在彭罗斯上跑。
## 顺序要求：调用前必须已经设好 board_type **并**跑过 `_apply_board_size()`。
func _generate_selected_board() -> void:
	match GameConfig.board_type:
		GameConfig.BOARD_CUBE: generate_cube()
		GameConfig.BOARD_KITE: generate_kite()
		GameConfig.BOARD_SNOWFLAKE: generate_snowflake()
		GameConfig.BOARD_HAT: generate_hat()
		_: generate_penrose()

## 相邻度直方图（"3度:60 4度:88 5度:35" 这种）。
## 为什么要它：AI 的眼位/死活模型是从**方形盘**推出来的（`ld_cap_points = 6` 背后是
## 「一块眼位大于六目必活」这条围棋定理），而筝形邻接只有 2~4 度、雪花还夹着正方形桥。
## 度分布是「这张盘的局部结构与方形盘差多远」的第一个客观坐标 —— 先记下来备查。
func _degree_hist_txt() -> String:
	var h: Dictionary = {}
	for i in tiles.size():
		var d: int = get_neighbors(i).size()
		h[d] = int(h.get(d, 0)) + 1
	var ks: Array = h.keys()
	ks.sort()
	var parts := PackedStringArray()
	for k in ks:
		parts.append("%d度:%d" % [int(k), int(h[k])])
	return " ".join(parts)

## 「着手体检」：只看这一手本身有没有硬伤，与比分、与棋力无关。
##
## 为什么需要它：这个引擎的单局比分方差极大（±150 目），「AI 在某张盘上是不是在下坏棋」
## 拿比分当尺子根本分辨不出来（技能 `godot-ai-tuning-verify` Part 2 的水位线）。
## 而下面这几类坏棋是**客观事实**，数一数就有结论：
##   illegal    落在非空点 / 越界          —— 硬伤，恒应为 0
##   pass       停一手（mv < 0）           —— 合法，但比例高说明它认为无处可下
##   suicide    落子后己方新块 0 气        —— 自杀，硬伤
##   self_atari 落子后己方新块 1 气且未提子 —— 送吃
##   lib_drop   未提子却让己方相邻组并集的气变少 —— 自紧气（总数，见下）
##
## ⚠️ `lib_drop` 只报总数是**不合格的判据**：它把性质相反的三类混在一起数。
## 2026-09-19 实测（三盘各 32 手）总数都在 8~12，但拆开看**正手占绝大多数** ——
## 若拿这个总数当「AI 在下坏棋」的证据去降自紧气，连通、做眼这些正手会被一起削掉。
## 所以加 `kind` 字段，拆成互斥三类（自上而下短路）：
##   kind="connect"   mv 同时贴到 **≥2 个不同的己方组** → 并块连通。气必然少 1
##                    （mv 自己变成子不再是气），所以**每个连通手都命中 lib_drop**
##                    —— 这是总数失真的主因。
##   kind="own_area"  mv 所在整片空区的边界上**没有对方子** → 己方领地里落子。
##                    引擎 `_own_territory_only()` 会滤掉「边界全己方**且边界各块已活**」
##                    的，剩下的都是「边界有未活组」→ 做眼/补活，也是正手。
##   kind="tighten"   其余：贴己方、气变少、既不连通也不在己方空区 → **唯一可疑的一类**。
##
## ⚠️ 本函数会**临时改 board 再原样还原** —— 只在自检里调用，不参与对局主路径。
func _ai_move_gate(mv: int, color: int) -> Dictionary:
	var out := {"illegal": false, "pass": false, "suicide": false,
		"self_atari": false, "lib_drop": false, "kind": "",
		"own_nb": 0, "cap_n": 0}
	if mv < 0:
		out["pass"] = true
		return out
	if mv >= tiles.size() or board[mv] != Stone.EMPTY:
		out["illegal"] = true
		return out
	var enemy: int = Stone.BLACK if color == Stone.WHITE else Stone.WHITE
	# 连通性与空区性质**必须在试落之前**取：落子后相邻己方组会被并成一块（组数 2→1）、
	# 空区也少一个点，两处口径都会变。塞到底下 branch 里去算就永远是错的，而且不报错。
	var own_groups: int = _gate_adj_own_groups(mv, color)
	var region_enemy: bool = _gate_empty_region_has_enemy(mv, enemy)
	# 前提诊断：这一手贴不贴己方子（不贴则 libs_before 恒空，「自紧气」永远算不出来）
	var own_nb := 0
	for n in get_neighbors(mv):
		if board[n] == color:
			own_nb += 1
	out["own_nb"] = own_nb
	# 落子前：己方相邻各组的并集气位（**含 mv** —— 它此刻还是空点，落子后就不算气了，
	# 这正是「自紧气」唯一的来源；把 mv 排掉这一项就永远算不出来）
	var libs_before: Dictionary = {}
	for n in get_neighbors(mv):
		if board[n] != color:
			continue
		for vid in get_group(n):
			for nn in get_neighbors(vid):
				if board[nn] == Stone.EMPTY:
					libs_before[nn] = true
	# 试落：占点 → 提掉被吃死的对方组 → 量己方新块的气
	board[mv] = color
	var captured: Array[int] = []
	for n in get_neighbors(mv):
		if board[n] != enemy:
			continue
		var eg: Array[int] = get_group(n)
		if eg.is_empty() or get_liberties(eg) > 0:
			continue
		for vid in eg:
			if not captured.has(vid):
				captured.append(vid)
	out["cap_n"] = captured.size()
	for vid in captured:
		board[vid] = Stone.EMPTY
	var libs_after: int = get_liberties(get_group(mv))
	if captured.is_empty():          # 提了子就不算「送吃」：那是好手（或劫材）
		if libs_after == 0:
			out["suicide"] = true
		elif libs_after == 1:
			out["self_atari"] = true
		elif libs_after < libs_before.size():
			out["lib_drop"] = true
			if own_groups >= 2:
				out["kind"] = "connect"
			elif not region_enemy:
				out["kind"] = "own_area"
			else:
				out["kind"] = "tighten"
	# 还原：board 是这轮实验的真值，必须原样还回去
	board[mv] = Stone.EMPTY
	for vid in captured:
		board[vid] = enemy
	return out

## mv 邻接的**不同**己方组数（用「组内最小格子号」当代表 id，不依赖任何组 id 约定）。
## 必须在**落子前**调用：落子会把相邻己方组并成一块，之后永远返回 1。
func _gate_adj_own_groups(mv: int, color: int) -> int:
	var ids: Dictionary = {}
	for n in get_neighbors(mv):
		if board[n] != color:
			continue
		var g: Array[int] = get_group(n)
		if g.is_empty():
			continue
		var rep: int = g[0]
		for vid in g:
			if vid < rep:
				rep = vid
		ids[rep] = true
	return ids.size()

## mv 所在整片空区的边界上有没有对方子（泛洪空区 + 只看边界，不看空区内部）。
## 与引擎 `_own_territory_only()` 的**第一层**同口径；引擎那层还多判「边界己方组是否都已活」，
## 那要用引擎内部的死活求解器，game.gd 侧拿不到 —— 所以这里算的是它的**超集**：
## 本函数说 false（边界有对方子）时引擎一定不会滤掉这一手；说 true 时不保证是纯己方领地。
## 同样必须在**落子前**调用（落子后 mv 不再是空点，泛洪起点就没了）。
func _gate_empty_region_has_enemy(mv: int, enemy: int) -> bool:
	var seen: Dictionary = {mv: true}
	var st: Array[int] = [mv]
	var qi := 0
	while qi < st.size():
		var cur: int = st[qi]
		qi += 1
		for n in get_neighbors(cur):
			if board[n] == Stone.EMPTY:
				if not seen.has(n):
					seen[n] = true
					st.append(n)
			elif board[n] == enemy:
				return true
	return false
## `--dumpadj` 的盘型 token → 常量。与 `--aibud` 同一套名字，不另发明一套。
func _board_type_from_token(tok: String) -> int:
	match tok:
		"cube": return GameConfig.BOARD_CUBE
		"kite": return GameConfig.BOARD_KITE
		"snow": return GameConfig.BOARD_SNOWFLAKE
		"hat": return GameConfig.BOARD_HAT
		_: return GameConfig.BOARD_PENROSE

## 把**真实邻接表**打到 stdout，供工作区的死活真源（`死活真源/` 里的通用图求解器）读。
##
## 为什么必须从引擎里 dump、而不是在 Python 里重造一遍生成器：`ld_cap_points = 6` 是
## 「眼位空间 > 6 目必活」这条**方形盘**定理的简化；判它在别的盘上成不成立，测的必须是
## **引擎实际用的那张图**。Python 里照着重写一份雪花/筝形，两边一旦不等价，测出来的就
## 不是引擎的行为 —— 而且这种不等价是**静默**的，不会有任何报错。
##
## 输出每行一个 token（python 直接 split 即可）：
##   [dumpadj] board <名字>
##   [dumpadj] n <格数>
##   [dumpadj] edge <i> <j>
##   [dumpadj] edges <边数>
##   [dumpadj] done
## ⚠️ 无向边只打 i < j 一次，别打两遍（求解器按无向图建邻接，打两遍会把度数翻倍）。
func _dump_adjacency(arg: String) -> void:
	var s := arg
	if s.begins_with("="):
		s = s.substr(1)
	var parts := s.split(":", false)
	var bt: int = _board_type_from_token(parts[0] if parts.size() > 0 else "pen")
	var sz: int = GameConfig.STANDARD
	if parts.size() > 1:
		match parts[1]:
			"rand": sz = GameConfig.RANDOM
			"enh", "big": sz = GameConfig.ENHANCED
			_: sz = GameConfig.STANDARD
	GameConfig.board_type = bt
	GameConfig.board_size = sz
	_apply_board_size(sz)
	if sz == GameConfig.RANDOM:
		_rand_seed = 20260919          # 固定种子：导出的这张图要能被别人复现
	_generate_selected_board()
	reset_game()
	print("[dumpadj] board %s" % _bt_name(bt))
	print("[dumpadj] n %d" % tiles.size())
	var ec := 0
	for i in tiles.size():
		for j in adjacency[i]:
			if int(j) > i:
				print("[dumpadj] edge %d %d" % [i, int(j)])
				ec += 1
	print("[dumpadj] edges %d" % ec)
	print("[dumpadj] done")
	get_tree().quit()
## 自检（--jevdump）：导出真实局面 + 引擎自己的根先验。
##
## 为什么要它：工作区探针要判断「Jev 给的候选点概率分布」与「引擎的先验排序」
## 是否相关。两边必须看**同一个局面**、先验必须是**搜索真正用过的那一份** ——
## 所以这里走 `prepare_root_for_dump()`（与 `choose_move` 同一调用顺序），
## 而不是在 Python 里重造一遍 scramble（不等价是**静默**的，同 `_dump_adjacency`）。
##
## 为什么根宽默认 48 而不是引擎的 `auto_root_width = 14`：14 是**搜索**的最佳口径
## （见 `_effective_root_width` 的实测注释），但探针要算秩相关，14 个点太少、
## 单个平局就能翻转结论。先验本身与 K 无关（`_root_score` 逐点独立），
## K 只影响 softmax 归一化的集合 —— 所以这里放大 K 不影响先验口径。
##
## 参数：`--jevdump=<board>:<size>:<plies_csv>:<pw>:<rw>`
##   例：--jevdump=hat:std:9,27,45:256:48
## 输出每行一个 token（python 直接 split）：
##   [jevdump] board <名字> / btok <token> / size <名字> / n <格数> / ai <颜色>
##   [jevdump] rootw <根宽> / pw <模拟上限>
##   [jevdump] edge <i> <j>            全局一次，只打 i < j（打两遍会把度数翻倍）
##   [jevdump] edges <边数>
##   [jevdump] pos <序号> <已落手数> / turn <轮到谁> / empties <空点>
##   [jevdump] cell <i> <0空|1黑|2白>  ×n
##   [jevdump] cand <v> <先验概率>     按先验降序；已是 softmax 归一化的分布
##   [jevdump] cands <候选数>
##   [jevdump] chosen <v>              与上面同一状态真跑一次搜索的结果
##   [jevdump] posend / [jevdump] done
func _jevdump(arg: String) -> void:
	var s := arg
	if s.begins_with("="):
		s = s.substr(1)
	var parts := s.split(":", false)
	var tok: String = parts[0] if parts.size() > 0 else "pen"
	var bt: int = _board_type_from_token(tok)
	var sz: int = GameConfig.STANDARD
	if parts.size() > 1:
		match parts[1]:
			"rand": sz = GameConfig.RANDOM
			"enh", "big": sz = GameConfig.ENHANCED
			_: sz = GameConfig.STANDARD
	var plies: Array[int] = []
	if parts.size() > 2:
		for p in parts[2].split(",", false):
			plies.append(maxi(int(p), 1))
	if plies.is_empty():
		plies.append(9)                       # 不给就一个中盘局面，够探针用
	var pw: int = 256
	if parts.size() > 3:
		pw = maxi(int(parts[3]), 1)
	var rw: int = 48
	if parts.size() > 4:
		rw = clampi(int(parts[4]), 1, 255)    # 255 = Choice 选项上限，别超
	GameConfig.board_type = bt
	GameConfig.board_size = sz
	_apply_board_size(sz)
	if sz == GameConfig.RANDOM:
		_rand_seed = 20260913                 # 固定种子：导出的局面要能被复现
	_generate_selected_board()
	reset_game()
	ai_engine.setup(adjacency, AI_COLOR, 20260913)
	ai_engine.threads = 1                  # 同 aibud：单线程 + 定 pw + 定种子才可复现
	ai_engine.max_playouts = pw
	ai_engine.root_width = rw
	print("[jevdump] board %s" % _bt_name(bt))
	print("[jevdump] btok %s" % tok)
	print("[jevdump] size %s" % _board_size_name(sz))
	print("[jevdump] n %d" % tiles.size())
	print("[jevdump] ai %d" % AI_COLOR)
	print("[jevdump] rootw %d" % ai_engine.root_width)
	print("[jevdump] pw %d" % ai_engine.max_playouts)
	var ec := 0
	for i in tiles.size():
		for j in adjacency[i]:
			if int(j) > i:
				print("[jevdump] edge %d %d" % [i, int(j)])
				ec += 1
	print("[jevdump] edges %d" % ec)
	for ci in plies.size():
		# 局面：与 aibud 同一套种子约定 —— scramble 走同一条 rng 流，种子必须在它**之前**给
		ai_engine.reset_state()
		ai_engine.rng.seed = 20260913 + ci * 7919
		ai_engine.scramble(plies[ci])
		_load_board_from_engine()
		var empties := 0
		for i in tiles.size():
			if board[i] == Stone.EMPTY:
				empties += 1
		print("[jevdump] pos %d %d" % [ci + 1, plies[ci]])
		print("[jevdump] turn %d" % ai_engine._turn)
		print("[jevdump] empties %d" % empties)
		for i in tiles.size():
			print("[jevdump] cell %d %d" % [i, int(board[i])])
		# 根先验（不搜索，走与 choose_move 同一调用顺序）
		ai_engine.reset_state()
		ai_engine.rng.seed = 20260913 + ci * 7919
		var ri: Dictionary = ai_engine.prepare_root_for_dump(board, -1)
		var cands: Array = ri["cands"]
		var priors: Array = ri["priors"]
		var order: Array[int] = []
		for i in cands.size():
			order.append(i)
		order.sort_custom(func(a, b): return float(priors[a]) > float(priors[b]))
		for i in order:
			print("[jevdump] cand %d %.8f" % [int(cands[i]), float(priors[i])])
		print("[jevdump] cands %d" % cands.size())
		# 实际选择：与上面同一状态（reset + 同种子），探针据此算 top-1 命中
		ai_engine.reset_state()
		ai_engine.rng.seed = 20260913 + ci * 7919
		print("[jevdump] chosen %d" % int(ai_engine.choose_move(board, -1)))
		print("[jevdump] posend")
	print("[jevdump] done")
	get_tree().quit()

## 自检（--aibud）：时间预算 → 决策一致率（两两对照矩阵）。
##
## 为什么不用自战比分来回答「多给时间是否更强」：这个引擎的单局比分方差极大
## （实测同配置对打，单局能差 166 目；换色多局后仍能出现「同配置 A 4:0 B」），
## 想靠比分分辨 20% 的棋力差异需要几十局，代价高且结论不稳。
##
## 换一个确定性指标：**同一个局面上，不同预算选出的着手是否相同**。
## 矩阵里第 i 行第 j 列 = 预算 i 与预算 j 选同一手的局面比例。
## 一致率高 → 缩短到该预算几乎不改变决策，省下的是纯等待；
## 一致率低 → 时间确实在改变选择，要缩短就得接受棋风/棋力变化。
func _ai_budget_test() -> void:
	var budgets: Array[int] = [300, 560, 700, 2400]
	var sizes: Array[int] = [GameConfig.STANDARD]
	# 盘型列表。**原来这里是写死的彭罗斯**（下面直接 generate_penrose()）—— 于是这个仪器
	# 从来没在雪花/筝形上跑过，那两种盘上的 AI 行为一直是没有数据的地方。
	# 空数组起步 = 只跑彭罗斯；显式给盘型 token 时再填（避免「默认 + 指定」跑成两轮）。
	var bts: Array[int] = []
	var stage_cnt := 8
	var rw := 0
	var pw := 0
	# 参数：`--aibud[=<tok>:<tok>...]`，tok 可以是
	#   pen / cube / kite / snow / hat → 跑哪些**盘型**（可叠多个）
	#   std / big / enh  → 跑哪些棋盘档位（enh = 只跑加强盘，格数 360）
	#   rwN              → 把根候选显式剪到 N（0 / 不给 = 走引擎自己的自适应宽度）
	#   pwN              → 模拟次数上限（**强烈建议给**：不给则按墙钟停手，不可复现）
	#   b150,300,600     → 覆盖测试预算列表（毫秒，逗号分隔，至少两个）
	#   sN               → 覆盖局面数（默认 8；加强盘上 scramble 很贵，扫描时调小）
	# 例：--aibud=snow:kite:std:b150,300,600   （两种盘各跑标准档）
	# 例：--aibud=enh:rw20:s5:b150,300,600
	#
	# 注意必须用 `begins_with` 而不是 `in`：带参数写法不是参数列表里的精确成员，
	# 用 `in` 判断会整条分支漏掉，然后场景空跑到超时（表现为「自检卡死」）。
	# ⚠️ 盘型 token 必须写成 match 的**精确分支**：`snow` 否则会被下面的 `s` 前缀分支
	#    抢走（int("now") = 0 → 夹到 2），静默把「局面数」改成 2，一字不报。
	for a in _argv():
		if not a.begins_with("--aibud"):
			continue
		var suffix := a.substr(7)          # 7 = "--aibud".length()
		if suffix.begins_with("="):
			suffix = suffix.substr(1)
		for tok in suffix.split(":", false):
			match tok:
				"pen": _aibud_add_board(bts, GameConfig.BOARD_PENROSE)
				"cube": _aibud_add_board(bts, GameConfig.BOARD_CUBE)
				"kite": _aibud_add_board(bts, GameConfig.BOARD_KITE)
				"snow": _aibud_add_board(bts, GameConfig.BOARD_SNOWFLAKE)
				"hat": _aibud_add_board(bts, GameConfig.BOARD_HAT)
				"big": sizes = [GameConfig.STANDARD, GameConfig.ENHANCED]
				"enh": sizes = [GameConfig.ENHANCED]
				"std": sizes = [GameConfig.STANDARD]
				"rand": sizes = [GameConfig.RANDOM]
				_:
					if _aibud_try_board_list(tok, bts):
						continue
					if tok.begins_with("pw"):
						pw = maxi(int(tok.substr(2)), 1)
					elif tok.begins_with("wt"):
						# 真·自紧气先验惩罚（wt-6 / wt0）。A/B「降自紧气」的开关：
						# wt0 = 旧行为（基线），负号直接写在 token 里
						ai_engine.w_tighten = float(tok.substr(2))
					elif tok.begins_with("rw"):
						rw = maxi(int(tok.substr(2)), 0)
					elif tok.begins_with("b"):
						var bs: Array[int] = []
						for p in tok.substr(1).split(",", false):
							bs.append(int(p))
						if bs.size() >= 2:
							budgets = bs
					elif tok.begins_with("s"):
						stage_cnt = clampi(int(tok.substr(1)), 2, 64)
	if rw > 0:
		ai_engine.root_width = rw
		print("[aibud] 根候选已剪到 %d" % rw)
	# ⚠️ 可复现性开关（2026-09-19）：不给 pw 时，停止条件是**墙钟**，
	# 同一份代码连跑两次「自紧气」能差一倍（筝形 12 vs 6）—— 在那样一把尺子上
	# 调任何先验都分不清「改有效」和「这次恰好不同」。给了 pw 之后模拟次数成为唯一
	# 停止条件，配合上面的「固定种子 + 单线程」，整轮才可复现。
	if pw > 0:
		ai_engine.max_playouts = pw
		print("[aibud] 模拟次数上限=%d（时间预算退化为兜底）→ 本轮可复现" % pw)
	print("[aibud] 真·自紧气先验 w_tighten=%.1f（0=关闭；wt token 可调）" % ai_engine.w_tighten)
	if bts.is_empty():
		bts.append(GameConfig.BOARD_PENROSE)     # 没显式给盘型 → 保持旧行为（只跑彭罗斯）
	var bt_names := PackedStringArray()
	for b in bts:
		bt_names.append(_bt_name(b))
	print("[aibud] 盘型=%s 档位=%s 局面数=%d 预算=%s" % [
		" / ".join(bt_names), str(sizes), stage_cnt, str(budgets)])
	# 拍平成 (盘型 × 尺寸) 的笛卡尔积再单层循环 —— 这样下面几十行循环体**一个 tab 都不用动**
	#（把 for bt 套在 for sz 外面就得整体重排缩进，那是这类补丁最容易写坏的地方）。
	var cases: Array = []
	for b in bts:
		for s in sizes:
			cases.append([b, s])
	for cs in cases:
		var bt: int = int(cs[0])
		var sz: int = int(cs[1])
		GameConfig.board_type = bt      # 必须先设：_apply_board_size() 要读它
		GameConfig.board_size = sz
		_apply_board_size(sz)
		# 随机盘必须固定种子：否则每一档预算都在不同的盘上跑，比的是盘面而不是预算
		if sz == GameConfig.RANDOM:
			_rand_seed = 20260913
		_generate_selected_board()
		reset_game()
		# ⚠️ 种子必须显式给（2026-09-20）：setup(seed=0) 会用时间戳做种去洗 _perm
		#（全局展开排列 + rollout 兜底扫描顺序都依赖它）→ 两次运行展开顺序不同，
		# 依然不可复现。这是「种子设在 scramble 前」修完之后剩下的最后一个复现性洞。
		ai_engine.setup(adjacency, AI_COLOR, 20260913)
		ai_engine.threads = 1        # 见下方「关键控制变量」：单线程才有前缀性质，对照才干净
		print("[aibud] ===== 盘型=%s 档位=%s 格数=%d | 相邻度 %s =====" % [
			_bt_name(bt), _board_size_name(sz), tiles.size(), _degree_hist_txt()])
		var picks: Array = []          # picks[case][budget_index] = 瓷砖号
		var all_po: Array = []         # 同上结构：每次调用的**实际**模拟次数（判 pw 有没有真绑住）
		var gate := {"illegal": 0, "pass": 0, "suicide": 0, "self_atari": 0, "lib_drop": 0,
			"connect": 0, "own_area": 0, "tighten": 0, "touch_own": 0, "had_cap": 0}
		var gate_n := 0
		for ci in stage_cnt:
			# 用 rollout 铺到不同阶段的中盘局面（棋形比纯随机真实），再让引擎在同样局面上比较
			ai_engine.reset_state()
			# ⚠️ 种子必须在 scramble **之前**设：scramble 走的是同一条 rng 流，
			# 而原来只在下面的预算循环里设种子 → 铺出来的局面本身就每次不同
			# （实测同一参数两次跑，局面1 空点数 152 vs 154），后面比的全是噪声。
			ai_engine.rng.seed = 20260913 + ci * 7919
			ai_engine.scramble((ci + 1) * (tiles.size() / 16))
			_load_board_from_engine()
			var row: Array[int] = []
			var po: Array[int] = []          # 本轮每个预算调用的实际模拟次数
			for bi in budgets.size():
				# 每次都从零起树，排除树复用带来的差异。
				# ★ 2026-09-21：这里一度改成 setup()，理由是只调 reset_state() 时同一局面、
				# 同一 8000ms 预算（都跑满 pw64）连调三次会给出 `28 | 102 | 102`。
				# 真因其实在引擎内部 —— `_group_status()` 把 `_ld_n = 0` 写在 `libs == 0`
				# 那条早退之后，于是 `_eye_vital_bonus()` 拿**上一次**的眼位模型去判当前
				# 候选点、白送要点奖励。修好后 reset_state() 已足够（它现在也作废眼位模型）。
				ai_engine.reset_state()
				# 关键控制变量：同一局面下固定随机种子 + 单线程。
				# 否则「换了预算」和「换了随机流」两件事混在一起，测到的差别全是 RNG 噪声
				# （随机种子取时间戳时，同一份代码连跑两次都会给出完全不同的手）。
				# 单线程还保证了「小预算的搜索过程是大预算的前缀」，比较才有意义。
				ai_engine.rng.seed = 20260913 + ci * 7919
				ai_engine.time_budget_ms = budgets[bi]
				var mv: int = int(ai_engine.choose_move(board, -1))
				row.append(mv)
				po.append(ai_engine.last_playouts)
				# 顺手体检：这一手本身有没有硬伤（免费 —— 手已经算出来了）
				var g: Dictionary = _ai_move_gate(mv, AI_COLOR)
				gate_n += 1
				for gk in ["illegal", "pass", "suicide", "self_atari", "lib_drop"]:
					if g[gk]:
						gate[gk] = int(gate[gk]) + 1
				var kd := String(g["kind"])
				if kd != "":
					gate[kd] = int(gate[kd]) + 1
				if int(g["own_nb"]) > 0:
					gate["touch_own"] = int(gate["touch_own"]) + 1
				if int(g["cap_n"]) > 0:
					gate["had_cap"] = int(gate["had_cap"]) + 1
			picks.append(row)
			all_po.append(po)
			var parts := PackedStringArray()
			for k in budgets.size():
				# ⚠️ 带上实际模拟次数：`pw` 是**上限不是保证**。它没在预算内跑满时，时间就
				# 重新成为停止条件，而「首次调用冷缓存慢 / 二次热缓存快」会让**同配置的两次
				# 调用**跑出不同迭代数 → 矩阵里两个相同预算的一致率掉到 83%~92%（实测
				# 彭罗斯局面1 28 vs 102）。这一列就是「pw 到底绑没绑住」的现场判据。
				var bind := "⚠" if (pw > 0 and int(po[k]) < pw) else ""
				parts.append("%dms→%d(p%d%s)" % [budgets[k], row[k], int(po[k]), bind])
			var empties := 0
			for i in tiles.size():
				if board[i] == Stone.EMPTY:
					empties += 1
			print("[aibud] 棋盘=%s 局面%d（已落 %d 手，空点 %d）| %s" % [
				_board_size_name(sz), ci + 1, (ci + 1) * (tiles.size() / 16),
				empties, "  ".join(parts)])
		# 客观坏棋统计（比分为尺子时测不出来的那一类：非法/自杀/送吃/自紧气都是 0/1 事实）
		print("[aibud] 着手体检（%d 手）：非法=%d 停一手=%d 自杀=%d 自送吃=%d 自紧气=%d" % [
			gate_n, gate["illegal"], gate["pass"], gate["suicide"], gate["self_atari"], gate["lib_drop"]])
		print("[aibud] ↳ 自紧气拆分：连通(正手)=%d 己方空区做眼(正手)=%d 真·自紧气(可疑)=%d" % [
			gate["connect"], gate["own_area"], gate["tighten"]])
		# 前提诊断：三项判据在「提了子」时会整体跳过 —— 必须先看这两列再读上面那行
		print("[aibud] ↳ 前提：贴己方子=%d/%d 提了子=%d/%d（提子手不进上面三项判据）" % [
			gate["touch_own"], gate_n, gate["had_cap"], gate_n])
		print("[aibud] ===== 盘型=%s 档位=%s 决策一致率矩阵（同局面选同一手的比例）=====" % [
			_bt_name(bt), _board_size_name(sz)])
		var head := "[aibud]              "
		for b in budgets:
			head += "%7dms" % b
		print(head)
		for i in budgets.size():
			var line := "[aibud] %7dms  " % budgets[i]
			for j in budgets.size():
				var same := 0
				for row: Array in picks:
					if row[i] == row[j]:
						same += 1
				line += "%7d%%" % int(round(100.0 * float(same) / float(stage_cnt)))
			print(line)
		# ★ 同预算复现性判据（2026-09-21）：把**两个值相同的预算**放进矩阵，它们的一致率
		# 必须是 100% —— 它测的是「同一局面、同一种子、同一预算下连调两次是否选同一手」。
		# 曾经这里是 83%/92%，根因是两处**跨调用残留状态**：
		#   ① `_ld_n`（眼位模型有效性标记）让 `_eye_vital_bonus()` 拿上一次的 `_ld_pts` /
		#      `_ldm_nbr` 去判当前候选点，白送 w_eye_make / w_kill_point；
		#   ② `_scan_cnt`（rollout 全盘扫描相位）让 `_playout_move()` 在 `_scan_all` 与
		#      `_scan_local` 之间随「之前搜过多少次」漂移 → 消耗的随机数个数不同 → 整棵树分叉。
		# 这条判据就是为它们立的：**只报数不报错的话，任何先验 A/B 都会把「残留污染」读成
		# 「改动有效」**。注意矩阵对角线恒为 100%（自己跟自己比），只有同值的**不同两列**
		# 才携带复现性信息。
		var tie_unstable := 0
		var tie_total := 0
		for ti in budgets.size():
			for tj in range(ti + 1, budgets.size()):
				if budgets[ti] != budgets[tj]:
					continue
				tie_total += 1
				var same_ij := 0
				for row: Array in picks:
					if row[ti] == row[tj]:
						same_ij += 1
				if same_ij < stage_cnt:
					tie_unstable += 1
		if tie_total > 0:
			print("[aibud] ↳ 同预算复现性：%d/%d 对同值预算未达 100%% → %s" % [
				tie_unstable, tie_total,
				"可复现 ✓（无跨调用残留）" if tie_unstable == 0
					else "不可复现 ✗（存在跨调用残留状态 → 先修引擎，再调先验）"])
		# ★ pw 绑定体检（2026-09-21 补）：`pw` 只是**上限**，不是保证跑满 —— 没跑满时时间就
		# 重新成为停止条件，冷缓存的首次调用会被截断在更少的迭代上、选出另一手。未跑满数 >0
		# 就该把预算调大重跑（技能 Part 8：「先验可以后调，尺子必须先能复现」）。
		if pw > 0:
			var unbind := 0
			var tot_call := 0
			var min_po := 1 << 30
			for prow: Array in all_po:
				for k in budgets.size():
					tot_call += 1
					var pv := int(prow[k])
					min_po = mini(min_po, pv)
					if pv < pw:
						unbind += 1
			print("[aibud] ↳ pw 绑定：未跑满 %d/%d 次调用（最低 p%d / 上限 pw%d）→ %s" % [
				unbind, tot_call, min_po, pw,
				"已绑住 ✓（时间不再是停止条件 → 尺子可复现）"
					if unbind == 0 else "未绑住 ✗（时间仍会截断 → 先调大预算，再调先验）"])
		ai_engine.time_budget_ms = 200           # 复位到普通档默认值（见 menu.gd _apply_difficulty_level）
	get_tree().quit()

## 自检（--capftest）：rollout 长度（`playout_cap_factor`）的成本-一致率前沿。
##
## 【为什么需要它 —— 它解开了一个「功效不足」的死局】
## 2026-10-05 实测：`--aitune pw150 ms8000` 单局（双方合计）344 秒、单方 200 手 = 172 秒
## ⇒ **每手 860ms**，而 `pw150` 只该给 150 次模拟。差出来的 5.7 倍在乘积的另一半：
##   每手生成步数 ≈ pw × rollout长度，`capi = min(int(n × playout_cap_factor), _eff_cap)`
##   彭罗斯标准盘 n=120、默认 factor=1.0 ⇒ **每次模拟都补满全盘** ⇒ 150 × 120 = 18000 步。
## ⇒ 上一轮把单局成本归因于 `max_moves=220` 是**错的**（它只是乘数之一，实测手数 200 确实贴近 220）。
## 而「降 rollout 长度会不会改棋」此前只能靠跨局胜率回答 —— 按铁律 31 的功效分析，
## 7.2 小时的预算只够检出 ≥24.5pp 的差异，而预期效应是 1pp 级 ⇒ **永远问不出来**。
## 本自检把同一问题从「整局」下推到「单着」：局面数 × 单手成本 × 配置数，
## 实测尺度 200 局面 × 1 手 × 860ms × 2 配置 ≈ 6 分钟 ⇒ **便宜 70 倍**，绕开了功效不足。
##
## 【判据纪律 —— 三条都不能是恒真式】
##   ① **复现性地板**：`cap=1.0` 跑**两次**（同种子）必须选同一手。它给出「纯残留噪声」的地板，
##      下面的一致率必须显著高于它，否则「一致率高」只是「地板本身就高」。
##      ⚠️ 这不是「阴性对照」而是**校准尺** —— 它测的是地板，不是效果。
##   ② **阳性对照（必须有牙齿）**：`cap=0.05` 这种极端降配**必须**明显改变选点。
##      如果连它都 100% 一致，说明「一致率」这个指标压根没在测 cap（接线盲区，铁律 13）。
##   ③ **阴性对照（必须有牙齿）**：`cap=1.0` 但**换随机种子**跑两次 ⇒ 一致率应**明显低于**
##      ①的 100%。若它也 100%，**先别急着说「引擎对 RNG 不敏感」** —— 实测（pw20）它确实 100%，
##      但真因是**搜索在该 pw 下没有决策权**：`prior_visits=12` 让每个候选开局就带 12 visits，
##      20 次模拟摊到 ~14 个候选上每个只多 ~1.4 次 ⇒ visits 差异被先验淹没 ⇒ 选点由先验决定，
##      自然与 RNG 无关。两种诊断的处置完全相反（前者⇒引擎 bug，后者⇒pw 给太小），
##      所以④a 先把「决策权」量化出来再读③。
##   ④a **决策权体检**：印出各 cap 下 root 子节点的 visits 极差与先验占比。
##       极差小 ⇒ 搜索没说话，③ 的 100% 是**必然**而非异常。
##   ④b **成本必须真降**：耗时随 cap 单调下降（**严格**递减，铁律 35 ——
##       判「严格」而非「非递减」，后者在恒等序列上是恒真判据）。
##       ★ 实测耗时对 cap **不是线性**（pw20 下 c1.0=58ms / c0.1=11ms，拟合 a≈6ms 固定 + b≈52·cap）
##       ⇒ 降 cap 的收益有上限，`_prepare_root` 全盘评分 + 树构建那份**与 cap 无关的开销省不掉**。
##
## 参数：`--capftest[=<tok>...]`
##   pen/cube/kite/snow/hat → 盘型（可叠）｜ sN 局面数（默认 6）
##   pwN 模拟次数上限（默认 40；**必须给**，否则墙钟截断 ⇒ 不可复现）
##   c0.5,0.3,0.1 → 要测的 cap 列表（默认 1.0,0.5,0.3,0.1）
func _cap_factor_test() -> void:
	var bts: Array[int] = []
	# 通用引擎参数覆盖（`k=名=值`，2026-10-27）：在 `setup()` 之后应用。
	# 为什么需要它：`--capftest` 原本只能扫 cap，而「换叶子价值口径」的改动
	# （`infl_dead_zone` / 各类权重）全落在别的属性上 ⇒ 没有通用入口就只能每试一个
	# 改一次源码默认值，再靠人记着拨回（§120 那类事故的源头）。
	var cap_ov := {}
	var stage_cnt := 6
	var pw := 40
	var depth_step := 40     # 每局面铺多少手（中盘才有统计翻盘空间）
	# ★ rw：根宽覆盖（0 = 不给）。**cap 矩阵必须跑在有分辨力的区域** ——
	#   默认 rw14 下③ 阴性对照显示「连换种子都 100% 一致」⇒ 那片区域仪器是瞎的，
	#   一致率 100% 只说明「测不出」，**不**说明「降 cap 不改棋」（见补丁 8 注释）。
	var rw := 0
	var caps: Array[float] = [1.0, 0.5, 0.3, 0.1]
	for a in _argv():
		if not a.begins_with("--capftest"):
			continue
		# ⚠️ 2026-10-05 修 off-by-one：原写 `a.substr(9)` 并注释「9 = "--capftest".length()」
		#   —— **实际是 10**（`--`2 + `capftest`8）。切掉的是 `t` ⇒ substr(10) 得到
		#   "t=snow,hat,kite:..." ⇒ begins_with("=") 为假、不剥 = ⇒ 整串成一个 token
		#   ⇒ 盘型列表**静默失效**、退回默认单盘彭罗斯，照常打印且 exit 0。
		#   （与 `--aidata` 当年那次同款：「少跑了两个盘」和「一个盘都过了」一模一样。）
		# ⇒ 不用 substr(N)：长度必须由**字符串自己**决定，否则注释也会跟着一起错。
		var suffix := a.trim_prefix("--capftest")
		suffix = suffix.trim_prefix("=")
		for tok in suffix.split(":", false):
			match tok:
				"pen": _aibud_add_board(bts, GameConfig.BOARD_PENROSE)
				"cube": _aibud_add_board(bts, GameConfig.BOARD_CUBE)
				"kite": _aibud_add_board(bts, GameConfig.BOARD_KITE)
				"snow": _aibud_add_board(bts, GameConfig.BOARD_SNOWFLAKE)
				"hat": _aibud_add_board(bts, GameConfig.BOARD_HAT)
				_:
					if _aibud_try_board_list(tok, bts):
						continue
					if tok.begins_with("s"):
						stage_cnt = maxi(int(tok.substr(1)), 2)
					elif tok.begins_with("pw"):
						pw = maxi(int(tok.substr(2)), 1)
					elif tok.begins_with("d"):
						depth_step = maxi(int(tok.substr(1)), 4)
					elif tok.begins_with("rw"):
						rw = maxi(int(tok.substr(2)), 0)
					elif tok.begins_with("k="):
						# ★ 复用 `--aispec` 的三道硬闸（键必须真实存在 / 类型必须相同 /
						#   拒绝空覆盖）：`set()` 对不存在的键**静默无效** ⇒ 打错一个字母
						#   就变成"跑的还是旧口径"，而报告照样印出一张整齐的矩阵。
						var kerrs: Array[String] = []
						var kov := _ai_spec_parse(ai_engine, tok.substr(2), "k", kerrs)
						if kerrs.size() > 0:
							for msg in kerrs:
								print("[capftest] ✗ %s" % msg)
							print("[capftest] ⇒ 覆盖没生效的数据一律不许读（那会变成「跑的是旧口径」却看不出）")
							get_tree().quit(1)
							return
						for kk in kov.keys():
							cap_ov[kk] = kov[kk]
					elif tok.begins_with("c"):
						var cs: Array[float] = []
						for p in tok.substr(1).split(",", false):
							cs.append(maxf(float(p), 0.01))
						if cs.size() >= 2:
							caps = cs
	if bts.is_empty():
		bts = [GameConfig.BOARD_PENROSE]
	# pw 必须给足：max_playouts 是唯一停止条件（时间预算退化为 8000ms 兜底，永不到）
	ai_engine.max_playouts = pw
	ai_engine.time_budget_ms = 8000
	ai_engine.threads = 1          # 单线程：小 cap 的搜索是大 cap 的前缀，比较才有意义
	print("[capftest] 盘型=%s 局面数=%d pw=%d 铺局步长=%d手/局面 cap=%s 根宽=%s 单线程" % [
		str(bts.size()), stage_cnt, pw, depth_step, str(caps),
		str(rw if rw > 0 else ai_engine.auto_root_width)])
	print("[capftest] 每手生成步数 ≈ pw × min(n×cap, _eff_cap) —— 这就是单局成本的乘积结构")

	var fails := 0
	for bt in bts:
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.STANDARD
		_apply_board_size(GameConfig.STANDARD)
		_generate_selected_board()
		reset_game()
		ai_engine.setup(adjacency, AI_COLOR, 20261005)
		ai_engine.threads = 1
		ai_engine.max_playouts = pw
		# 覆盖必须放在**所有基础赋值之后**，否则会被后面的赋值压掉（本次实测踩过一次）
		for kk in cap_ov.keys():
			ai_engine.set(kk, cap_ov[kk])
		if not cap_ov.is_empty():
			print("[capftest] 引擎参数覆盖：%s" % _ai_spec_desc(cap_ov))
		var rw_saved := ai_engine.auto_root_width
		if rw > 0:
			ai_engine.auto_root_width = rw
			print("[capftest] 根宽覆盖 %d → %d（★ 需在有分辨力的区域量cap 效应；默认 14 下阴性对照显示这片区域仪器是瞎的）" % [rw_saved, rw])
		print("[capftest] ===== 盘型=%s 格数=%d | 相邻度 %s =====" % [
			_bt_name(bt), tiles.size(), _degree_hist_txt()])
		# 每个局面：各 cap 各跑一次 → picks[局面][cap索引] / cost[局面][cap索引] = 毫秒
		var picks: Array = []
		var costs: Array = []
		var sigma: Array = []      # [局面][cap] → 叶子分 σ
		var pos: Array = []          # 记 cap 下限对应的实际 rollout 长度（成本模型的自证）
		var cap_steps: Array = []
		# rollout 长度上界 = min(int(n×cap), _eff_cap)：**每盘一次**（只随格数变，与局面无关）
		for cf in caps:
			cap_steps.append(mini(int(float(tiles.size()) * cf), mini(tiles.size(), 160)))
		for ci in stage_cnt:
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			# ★ 深度用 dN（默认 40 手/局面）：原先的 (ci+1)*(n/16) 最多只铺到 26 手，
			#   那正是 `_root_score` 先验压倒一切的阶段 ⇒ 任何扰动都翻不动选点，
			#   读出来会误判成「指标没牙齿」。中盘才有统计翻盘空间。
			ai_engine.scramble(depth_step * (ci + 1))
			_load_board_from_engine()
			var row: Array[int] = []
			var crow: Array[int] = []
			var srow: Array[float] = []   # 每个 cap 的叶子分 σ（仪器量，不参与决策）
			for ci2 in caps.size():
				ai_engine.reset_state()      # 作废眼位模型，避免跨调用残留
				ai_engine.rng.seed = 20261005 + ci * 7919    # 同种子：cap 是唯一变量
				ai_engine.playout_cap_factor = float(caps[ci2])
				var t0 := Time.get_ticks_msec()
				var mv: int = int(ai_engine.choose_move(board, -1))
				var el := Time.get_ticks_msec() - t0
				row.append(mv)
				crow.append(el)
				srow.append(ai_engine._dc_std)
			picks.append(row)
			costs.append(crow)
			var stones := 0
			for i in tiles.size():
				if board[i] != Stone.EMPTY:
					stones += 1
			pos.append(stones)
			sigma.append(srow)
			var parts := PackedStringArray()
			for k in caps.size():
				parts.append("c%.2f→%d(%dms,σ%.1f)" % [float(caps[k]), row[k], crow[k], srow[k]])
			print("[capftest] 局面%d（已落%d子）| %s" % [ci + 1, pos[ci], "  ".join(parts)])
			# ---- ④a 决策权体检：搜索统计到底有没有话语权 ----
			# `_pick_merged` 对 `v_real ≈ 0` 的候选**恒按先验打分** ⇒ 那种局面上
			# 「换种子也 100% 一致」是**构造上的必然**，不是引擎对 RNG 不敏感。
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			ai_engine.playout_cap_factor = 1.0
			var av: Dictionary = ai_engine.probe_root_visits(board, -1, AI_COLOR, pw)
			print("[capftest]   ↳ ④a 决策权：候选%d 真实访问 top2 占 %d%%（先验 %d/候选）零访问占 %d%%" % [
				int(av["cands"]), int(round(100.0 * float(av["top2"]))),
				int(round(ai_engine.prior_visits)), int(round(100.0 * float(av["zero_frac"])))])
			# 定量对比：换种子能把 top1 的 q 推动多少（2×标准误）vs 需要推动多少（先验差距）。
			# 推不动 ⇒「换种子也 100% 一致」是**构造上的必然**，不是引擎对 RNG 不敏感。
			var pg := float(av["prior_gap"])
			var se := float(av["se1"])
			print("[capftest]   ↳ ④a 证据 vs 先验：top1真实访问 %d 次 | q标准误 %.4f（2se=%.4f）先验差距 %.4f | 修正系数上限 %.2f → %s" % [
				int(av["v_top1"]), se, 2.0 * se, pg, float(av["fix_cap"]),
				"先验差距 >> RNG 噪声 ⇒ 选点被先验锁定（正常）"
					if pg > 2.0 * se
				else "噪声足以撼动先验 ⇒ 若仍 100% 一致才是真异常"])

		# ---- ① 复现性地板：cap=1.0 跑两次（同种子）必须 100% 一致 ----
		var floor_ok := 0
		var floor_n := 0
		# ---- ③ 阴性对照：cap=1.0 换种子 ⇒ 应明显低于地板 ----
		var neg_same := 0
		for ci in stage_cnt:
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			# ★ 深度用 dN（默认 40 手/局面）：原先的 (ci+1)*(n/16) 最多只铺到 26 手，
			#   那正是 `_root_score` 先验压倒一切的阶段 ⇒ 任何扰动都翻不动选点，
			#   读出来会误判成「指标没牙齿」。中盘才有统计翻盘空间。
			ai_engine.scramble(depth_step * (ci + 1))
			_load_board_from_engine()
			var r1: Array = picks[ci]
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			ai_engine.playout_cap_factor = 1.0
			var m1: int = int(ai_engine.choose_move(board, -1))
			ai_engine.reset_state()
			ai_engine.rng.seed = 999331 + ci * 7919     # 只换种子 ⇒ 阴性对照
			ai_engine.playout_cap_factor = 1.0
			var m2: int = int(ai_engine.choose_move(board, -1))
			floor_n += 1
			if r1[0] == m1:
				floor_ok += 1
			if m1 == m2:
				neg_same += 1
		print("[capftest] ① 复现性地板：同种子两次 %d/%d = %d%%" % [
			floor_ok, floor_n, int(round(100.0 * floor_ok / floor_n))])
		print("[capftest] ③ 阴性对照（只换种子）：%d/%d = %d%% → %s" % [
			neg_same, floor_n, int(round(100.0 * neg_same / floor_n)),
			"有牙齿 ✓（引擎对 RNG 敏感，一致率家族是有效指标）"
				if neg_same < floor_n else "无牙齿 ✗ —— 先看④a：若 top2 访问占比接近 100%，则这是构造上的必然（非冠军候选零访问 ⇒ `_pick_merged` 恒按先验打分），应加深局面或加预算；只有④a 显示访问分散却仍 100%，才是引擎真对 RNG 不敏感"])
		if neg_same >= floor_n:
			fails += 1

		# ---- 一致率矩阵 + 耗时矩阵 ----
		print("[capftest] 一致率矩阵（行=cap，列=cap，同局面选同一手的比例）")
		var head := "[capftest]            "
		for cf in caps:
			head += "c%6.2f" % float(cf)
		print(head)
		for i in caps.size():
			var line := "[capftest] c%6.2f " % float(caps[i])
			for j in caps.size():
				var same := 0
				for row: Array in picks:
					if row[i] == row[j]:
						same += 1
				line += "%7d%%" % int(round(100.0 * float(same) / stage_cnt))
			print(line)
		print("[capftest] 平均单手耗时矩阵（ms）")
		print(head)
		var avg_cost: Array[float] = []
		for i in caps.size():
			var line2 := "[capftest] c%6.2f " % float(caps[i])
			var sum := 0.0
			for crow: Array in costs:
				sum += float(crow[i])
			var avg := sum / float(stage_cnt)
			avg_cost.append(avg)
			line2 += "%7.0f" % avg
			print(line2)
		# ---- ④ 成本必须真降：耗时随 cap 严格递减 ----
		var mono := true
		for i in caps.size() - 1:
			if avg_cost[i] <= avg_cost[i + 1]:
				mono = false
		print("[capftest] ④ 成本单调性（cap 越小越快，须严格递减）：%s" % [
			"✓" if mono else "✗"])
		if not mono:
			fails += 1
		# ---- ② 阳性对照（2026-10-05 二版）：扰动换成 auto_root_width ----
		# 原设计拿「换 cap」当扰动，实测 c1.00 vs c0.10 仍 100% —— 但那是**扰动太弱**，
		# 不是指标没牙齿：cap 影响的是 top1/top2 的胜率估计 q，其修正量被
		# `prior_pick_weight(0.6) × V/(V+evidence_k(10))` 压住，q 的波动只有 ±4.4%。
		# ⇒ 换一把**量级足够**的尺子：`auto_root_width` 在 --aibud 既有实测里已校准过
		# （`ai_engine.gd:3172`：rw14→88~100% / rw48→50~75% / rw96→13~50%）。
		# 若连根宽放大 4 倍都打不下一致率，那才是指标真的没牙齿。
		var rw0 := ai_engine.auto_root_width   # 若给了 rw 则已是覆盖后的值
		var pos_same := 0
		for ci in stage_cnt:
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			ai_engine.scramble(depth_step * (ci + 1))
			_load_board_from_engine()
			ai_engine.auto_root_width = rw0
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			ai_engine.playout_cap_factor = 1.0
			var a1: int = int(ai_engine.choose_move(board, -1))
			ai_engine.auto_root_width = rw0 * 4      # 14 → 56：--aibud 实测会打下一致率
			ai_engine.reset_state()
			ai_engine.rng.seed = 20261005 + ci * 7919
			var a2: int = int(ai_engine.choose_move(board, -1))
			ai_engine.auto_root_width = rw0
			if a1 == a2:
				pos_same += 1
		var pos_rate2 := int(round(100.0 * float(pos_same) / stage_cnt))
		print("[capftest] ② 阳性对照（根宽 %d vs %d，同种子一致 %d%%）：%s" % [
			rw0, rw0 * 4, pos_rate2,
			"有牙齿 ✓（放大根宽确实改了选点 ⇒ 一致率确实在测选点）"
				if pos_rate2 < 100
			else "无牙齿 ✗（连根宽放大 4 倍都不改选点 ⇒ 一致率是废指标）"])
		if pos_rate2 >= 100:
			fails += 1
		# ---- 成本-一致率前沿：便宜多少、一致率掉多少 ----
		print("[capftest] 前沿（相对 c%.2f）：" % float(caps[0]))
		for i in caps.size():
			var same2 := 0
			for row: Array in picks:
				if row[0] == row[i]:
					same2 += 1
			print("[capftest]   c%6.2f  耗时 %5.2f×  与满配一致 %3d%%  rollout长度≤%d" % [
				float(caps[i]), avg_cost[i] / maxf(avg_cost[0], 0.001),
				int(round(100.0 * float(same2) / stage_cnt)), int(cap_steps[i])])
	print("[capftest] 结论：%s（失败 %d 项）" % [
		"通过 ✓" if fails == 0 else "失败 ✗", fails])
	ai_engine.playout_cap_factor = 1.0        # 复位，别把测试配置漏给后续自检
	ai_engine.auto_root_width = 14        # 复位（即便 rw 覆盖过也别留下）
	ai_engine.max_playouts = 100000
	ai_engine.time_budget_ms = 200
	get_tree().quit(1 if fails > 0 else 0)


## 自检（--captest）：提子计数正确性。
##
## 回归的 bug：`remove_dead_stones` 原先「先收集全部该色子、再逐个判气、最后统一提子」，
## 于是同一串会被它的每一颗子各扫一遍并 append 进 removed_ids → 长度 = 串内子数²。
## 实战表现：一手提掉 k 子打出的却是 k² 子（11 子大龙 → 「提掉 121 子」），
## 提子数被放大数倍后，终局「总分 = 盘上子 + 领空 + 提子」会算出远超棋盘总点数的荒谬值
## （自战对照里曾出现 988 : 38 这种不可能比分，直接把棋力对比数据污染掉）。
func _capture_self_test() -> void:
	_test_build_square_grid(TEST_GRID_N)   # 仅邻接的 19×19 方形夹具（见其注释）
	game_mode = LOCAL
	reset_game(true)
	var n: int = TEST_GRID_N               # 19（正方形网格边长）
	# 白 3 子横排在第 0 行前三格：id 0,1,2。四口气为 (0,3)=3、(1,0..2)=19,20,21
	# 注意：place_stone() 末尾会把 current_player 翻给对手，所以每手前都要显式置色
	for c in 3:
		current_player = Stone.WHITE
		place_stone(c, false)
	var w_alive := 0
	for i in tiles.size():
		if board[i] == Stone.WHITE:
			w_alive += 1
	# 黑围下边 19,20,21，最后一手 3 提子。
	# ★ 最后一手必须带 `animate=true`：只有它才会写 `_capture_anims` —— 提子**渐隐**的判据
	#   全靠这个字典；前面几手用 false 是为了不让动画干扰提子计数。
	for v in [n, n + 1, n + 2]:
		current_player = Stone.BLACK
		place_stone(v, false)
	current_player = Stone.BLACK
	place_stone(3, true)
	var emptied := 0
	for c in 3:
		if board[c] == Stone.EMPTY:
			emptied += 1
	var sc: Dictionary = _compute_scores()
	var tot: int = int(sc.get("total_black", 0)) + int(sc.get("total_white", 0))
	var ceiling: int = tiles.size() + 7    # 本局共落 7 子 → 总分上限 = 格数 + 手数
	var ok: bool = emptied == 3 and black_prisoners == 3 and tot <= ceiling
	print("[captest] 白子=%d 被提空=%d/3 | 黑提子计数=%d（期望 3）| 总分=%d ≤ 上限 %d → %s" % [
		w_alive, emptied, black_prisoners, tot, ceiling, "通过 ✓" if ok else "失败 ✗"])

	# ---- ⑧ 提子**波前顺序** + ⑨ **整段时长封顶**（2026-09-29 用户口令）----
	# 口令原文：「一次提走多个棋子时，从对方所下棋子旁边的子开始被提走，接着它旁边的子被提走，
	#          依次提子直到全部提完；整个提子过程限制在一定时间内」。⇒ 两件独立的事，两条判据：
	#   ⑧ **顺序**：第 0 层 == 贴着刚落那一手的被提子，第 1 层 == 挨着第 0 层……
	#   ⑨ **封顶**：最深层的**结束时刻**恒等于 `_capture_delay() + _capture_total_time()`，
	#      且**与层数无关** —— 这一条才是"限制在一定时间内"的真牙齿
	#      （去掉归一化后，长龙会线性变久 ⇒ 红）。
	# ★ 本夹具（19×19 方阵）的三个白子 0-1-2 是一条横串，四口气已被黑占掉三口、只留 3 ⇒
	#   黑下 3 恰好提掉整串。分层可以**手算**：3 的邻居含 2 ⇒ 2 是第 0 层；1 挨着 2 ⇒ 第 1 层；
	#   0 挨着 1 ⇒ 第 2 层。所以这里**写死期望值**（不是抄实现的公式，是这块盘的几何事实）。
	#   下面先把"2 确实挨着落点 3"断言出来，期望值才算有依据、不是魔数。
	var t_place := 3
	var adjacent_ok: bool = adjacency[2].has(t_place)
	var wave_expect := {2: 0, 1: 1, 0: 2}
	var wave_bad := 0
	var delay_order_bad := 0
	if _capture_anims.size() == 3:
		for c in wave_expect.keys():
			if int(_capture_anims[c].get("wave", -1)) != wave_expect[c]:
				wave_bad += 1
		# delay 必须**随层号严格递增**（同层相等）—— 顺序真的落到时间上了，而不只是记了个数
		if not (float(_capture_anims[2]["delay"]) < float(_capture_anims[1]["delay"])
				and float(_capture_anims[1]["delay"]) < float(_capture_anims[0]["delay"])):
			delay_order_bad += 1
		# 第 0 层的起手偏移必须是 0（= 立刻开始，只等落子动画）
		if not is_equal_approx(float(_capture_anims[2]["delay"]), _capture_delay()):
			delay_order_bad += 1
	else:
		wave_bad = 3
		delay_order_bad = 2
	# ⑨ 封顶：① 本局最深层的结束时刻 == 封顶值；② **层数写了多少都不变**（归一化的意义）；
	#    ③ 起手偏移随层号**严格递增**（否则"一层层"就没了）
	var cap: float = _capture_delay() + _capture_total_time()
	var this_end: float = 0.0
	for c in 3:
		this_end = maxf(this_end, _capture_end_time(int(_capture_anims[c].get("wave", 0)),
			int(_capture_anims[c].get("wave_max", 0))))
	var end_free_of_len := true
	for wm in [1, 2, 5, 20]:
		if not is_equal_approx(_capture_end_time(wm, wm), cap):
			end_free_of_len = false
	var wave_mono := true
	for wm in [1, 3, 20]:
		for w in wm:
			if not (_capture_wave_start(w, wm) < _capture_wave_start(w + 1, wm)):
				wave_mono = false
	# 地板：把总时长调到比单颗还短 → 必须兜到 `STONE_ANIM_TIME`，仍要封得住
	var save_total: float = capture_total_time
	capture_total_time = 0.0
	var floor_ok: bool = is_equal_approx(_capture_total_time(), STONE_ANIM_TIME)
	# 旋钮真的生效：拉到 STONE_ANIM_TIME → 跨度为 0（全部同时升空 = 旧观感）
	capture_total_time = STONE_ANIM_TIME
	var spread_ok: bool = is_equal_approx(_capture_wave_start(1, 1), 0.0)
	capture_total_time = save_total
	var wave_ok: bool = adjacent_ok and wave_bad == 0 and delay_order_bad == 0 \
			and is_equal_approx(this_end, cap) and end_free_of_len and wave_mono \
			and floor_ok and spread_ok
	if not wave_ok:
		ok = false
	print("[captest] 提子波前顺序+总时长封顶 %s（落点 t%d 贴着第0层 %s｜层号 %d/%d/%d 期望 0/1/2（错 %d）｜delay 随层递增 %s 且第0层只等落子 %.2fs｜最深结束 %.2fs == 封顶 %.2fs（与层数无关 %s）｜起手偏移随层递增 %s｜地板 %s｜旋钮拉到 %.2f = 齐提 %s）" % [
		"通过 ✓" if wave_ok else "失败 ✗", t_place, "✓" if adjacent_ok else "✗",
		int(_capture_anims[2].get("wave", -1)), int(_capture_anims[1].get("wave", -1)),
		int(_capture_anims[0].get("wave", -1)), wave_bad,
		"✓" if delay_order_bad == 0 else "✗", _capture_delay(),
		this_end, cap, "✓" if end_free_of_len else "✗", "✓" if wave_mono else "✗",
		"✓" if floor_ok else "✗", STONE_ANIM_TIME, "✓" if spread_ok else "✗"])

	# ---- 提子动画：起手原格不动 → **排在落子之后** → 向上平移淡出 → 散尽 ----
	#      （★ 问的是 `_stone_paint()` —— `_draw()` 画的就是它，不是副本）
	# 这一条守的是一类**不报错的失效**：门槛写错 ⇒ 分支永远不可达 ⇒ 提子"瞬间消失"，
	# 与"渐隐回瓷砖本色"在 headless 下**没有任何可观测差别**（渲染结果量不到）。
	# 断言七件事：① 起手（delay 还没走完）：三格都要画、在**离位层 1**、位移 = 0、alpha = 1
	#   （= 被提的子先**原样停在原格**）② **串行**：起手 delay ≥ 落子动画时长
	#   ③ **推进半个落子时长后仍然一动没动**（这条才真正测串行，见下）
	#   ④ 颜色 = 被提方棋子色 ⑤ 半途 alpha 真的降下来（不是常量）
	#   ⑥ 半途**已向上走完 ≥40% 行程**（防"只淡出不平移"，也防位移全挤在末尾 ——
	#      末尾 alpha ≈0，那种曲线等于没平移）⑦ 动画结束后不再画（不留残影）。
	var rise_total: float = -Vector2(_capture_fade_state(1.0)["off"]).y
	var f_start := 0                      # 起手：要画、离位层、位移 0、alpha 1
	var f_seq := 0                        # 串行口径：delay ≥ 落子动画时长
	var f_col := true                     # 颜色 = 被提方棋子色
	for c in 3:
		var p0: Dictionary = _stone_paint(c)
		var c0: Color = p0["col"]
		if p0["draw"] and int(p0["layer"]) == 1 and Vector2(p0["off"]) == Vector2.ZERO:
			f_start += 1
		if float(_capture_anims[c].get("delay", 0.0)) >= STONE_ANIM_TIME:
			f_seq += 1
		if not (is_equal_approx(c0.a, 1.0) and _same_rgb(c0, piece_color_white)):
			f_col = false
	# ★★ 真的推进「半个落子时长」：delay 只该走掉一半 ⇒ 被提的子必须**一动都没动**。
	#    这一条才是"两段串行"的真牙齿 —— `_process` 若改成 delay 与 time_left **并排**递减，
	#    起手那一帧看起来一模一样（同一帧内谁都还没推过），只有**推进之后**才分得出来。
	_process(STONE_ANIM_TIME * 0.5)
	var f_hold := 0
	for c in 3:
		var ph: Dictionary = _stone_paint(c)
		if ph["draw"] and int(ph["layer"]) == 1 and Vector2(ph["off"]) == Vector2.ZERO \
				and is_equal_approx(float(ph["col"].a), 1.0):
			f_hold += 1
	var f_mid := 0                        # 半途：alpha 真的在降
	var f_rise := 0                       # 半途：真的已经向上走了大半行程
	for c in 3:
		_capture_anims[c]["delay"] = 0.0                          # 让 delay 走完，才轮到渐隐
		_capture_anims[c]["time_left"] = STONE_ANIM_TIME * 0.5    # 拨到半途
		var pm: Dictionary = _stone_paint(c)
		var cm: Color = pm["col"]
		var off_m: Vector2 = pm["off"]
		if pm["draw"] and float(cm.a) > 0.2 and float(cm.a) < 0.8:
			f_mid += 1
			if off_m.x == 0.0 and off_m.y < 0.0 and -off_m.y >= rise_total * 0.4:
				f_rise += 1
	_capture_anims.clear()                                        # 拨到"动画已结束"
	var f_end := 0
	for c in 3:
		if not _stone_paint(c)["draw"]:
			f_end += 1
	# 终点必须**恰好**落在落子的起点上：两个动画共用**同一个**高度旋钮（`_drop_height()`）
	var f_end_pos: bool = Vector2(_capture_fade_state(1.0)["off"]) \
			== Vector2(_place_drop_state(0.0)["off"]) \
			and is_equal_approx(float(_capture_fade_state(1.0)["alpha"]), 0.0)
	var fade_ok: bool = f_start == 3 and f_seq == 3 and f_hold == 3 and f_mid == 3 \
			and f_rise == 3 and f_col and f_end == 3 and f_end_pos
	print("[captest] 提子动画 %s（起手原格不动 %d/3：离位层+位移0+alpha1｜排在落子之后 %d/3（delay %.2fs ≥ %.2fs）｜落子半途时仍一动没动 %d/3｜半途 alpha 降下来 %d/3 且已上升≥40%%行程 %d/3｜颜色=被提方 %s｜结束后不再画 %d/3｜终点==落子起点 %s）" % [
		"通过 ✓" if fade_ok else "失败 ✗", f_start, f_seq, _capture_delay(), STONE_ANIM_TIME,
		f_hold, f_mid, f_rise, "✓" if f_col else "✗", f_end, "✓" if f_end_pos else "✗"])
	if not fade_ok:
		ok = false
	# ★ 结论行必须留在**最后**：两个判据块都会写 `ok`，而波前那块的 `_capture_anims` 读取
	#   必须发生在 fade 块把它清空**之前**（fade 块末尾 `_capture_anims.clear()`），
	#   所以块序是"波前在前、结论在后"—— 别被块序带偏，结论只此一处。
	print("[captest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()


## 自检辅助：两个颜色**只比 RGB**（alpha 由调用方单独判 —— 渐隐动的正是 alpha）。
func _same_rgb(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)

## 自检（--gridtest）：给 AI 自检打底的**方形邻接夹具**是否真的方正规整 ——
## ① 格数 = n×n ② 邻接度符合方阵（角 2 / 边 3 / 内部 4）③ 邻接对称（A 的邻居必有 A）。
##
## ⚠️ 这不是棋盘自检了（经典 19×19 已下线）：三个依赖方形坐标手工验算的 AI 自检
##（--captest / --ladtest / --ailife）全都跑在 `_test_build_square_grid` 上，
## 夹具本身一旦歪了，这三个测试会以「AI 退步」的假象报错，极难定位 —— 所以单独钉一条。
func _grid_self_test() -> void:
	_test_build_square_grid(TEST_GRID_N)
	var n: int = TEST_GRID_N
	var deg: Dictionary = {}
	var sym_ok := true
	for a: Array in adjacency:
		deg[a.size()] = int(deg.get(a.size(), 0)) + 1
	for i in adjacency.size():
		for nb: int in adjacency[i]:
			if not (adjacency[nb] as Array).has(i):
				sym_ok = false
	var ok_cnt: bool = tiles.size() == n * n
	var ok_deg: bool = int(deg.get(2, 0)) == 4 \
		and int(deg.get(3, 0)) == (n - 2) * 4 \
		and int(deg.get(4, 0)) == (n - 2) * (n - 2)
	var ok: bool = ok_cnt and ok_deg and sym_ok
	print("[gridtest] 方形夹具 %d×%d | 格数=%d（期望 %d）| 邻接度分布=%s | 对称=%s → %s" % [
		n, n, tiles.size(), n * n, deg, sym_ok,
		"通过 ✓" if ok else "失败 ✗"])
	get_tree().quit()

## 自检（--aitest）：人机模式下黑先走一子，AI 必须经后台线程异步思考后正常落子，
## 且主线程在思考期间仍在跑（process_frame 正常推进）
func _ai_async_test() -> void:
	game_mode = VS_AI
	ai_time_ms = 500
	if ai_engine:
		ai_engine.time_budget_ms = ai_time_ms
		ai_engine.threads = GameConfig.ai_threads
		ai_engine.root_width = GameConfig.ai_root_width
	reset_game(true)
	var vid: int = _random_legal_move()
	if vid >= 0:
		place_stone(vid, false)
	print("[aitest] 黑已落子 ", vid, "，轮到白=", current_player == Stone.WHITE)
	_start_ai_turn()
	var waited: int = 0
	var frames: int = 0
	while is_ai_thinking and waited < 300:
		await get_tree().process_frame
		frames += 1
		waited += 1
		var ok_front: bool = not is_ai_thinking
		if ok_front:
			break
	var white_stones: int = 0
	for i in tiles.size():
		if board[i] == Stone.WHITE:
			white_stones += 1
	var ok_prod: bool = white_stones >= 1 and not game_over
	# ── ⑤ 骨架（疾风档）异步选点：**不阻塞主线程**（2026-10-20 用户反馈的量化） ──────
	# ★ 反馈原话：「跟骨架下棋的时候落子会卡一下再播放落子动画」。二版每手约 90ms，
	#   原先在 `_start_ai_turn()` 里**同步**跑 ⇒ 主线程 5~6 帧不重绘。改成后台线程后，
	#   这条盯两件事：① 真不阻塞 ② 返回的仍是合法着法（不能"不卡了但乱下"）。
	# ★ 阴性对照同批：**同步版必须同一帧内返回**（`df_s == 0`）—— 否则"帧数"这个量
	#   根本没在量阻塞，① 就成了恒真判据。
	#   ⚠️ 两边都传 `current_player`：`can_place_at()` 判自杀/劫用的就是这个行棋方，
	#     传别的颜色会让"合法"这个断言变成跨口径比对（§13）。
	var t0a: int = Time.get_ticks_usec()
	var f0a: int = Engine.get_process_frames()
	var mv_a: int = await _xg_choose_move_async(current_player)
	var df_a: int = Engine.get_process_frames() - f0a
	var ms_a: float = float(Time.get_ticks_usec() - t0a) / 1000.0
	var t0s: int = Time.get_ticks_usec()
	var f0s: int = Engine.get_process_frames()
	var mv_s: int = _xg_choose_move(current_player)
	var df_s: int = Engine.get_process_frames() - f0s
	var ms_s: float = float(Time.get_ticks_usec() - t0s) / 1000.0
	var legal_a: bool = mv_a == -1 or can_place_at(mv_a)
	var legal_s: bool = mv_s == -1 or can_place_at(mv_s)
	var ok_xg: bool = legal_a and legal_s and (df_a >= 1 or ms_a < 16.0) and df_s == 0
	print("[aitest] ⑤ 骨架异步选点：异步 帧=%d 用时=%.1fms 着法=t%d 合法=%s｜同步 帧=%d 用时=%.1fms 合法=%s（同步须 0 帧）→ %s" % [
		df_a, ms_a, mv_a, str(legal_a), df_s, ms_s, str(legal_s),
		"通过 ✓" if ok_xg else "失败 ✗"])
	var ok: bool = ok_prod and ok_xg
	print("[aitest] AI 异步落子=%d | 思考期间主线程帧数=%d | playouts=%d 用时=%dms → %s" % [
		white_stones, frames,
		ai_engine.last_playouts if ai_engine else 0,
		ai_engine.last_ms if ai_engine else 0,
		"通过 ✓" if ok else "失败 ✗"])
	get_tree().quit()

## `--aiterms` 走到中盘那 26 手用的 **playout 帽**（见 `_ai_terms_test()` 的"预算必须钉死"）。
## ★ 这个值一变，样本局面就变 ⇒ ④ 的存活特征数会跟着变。
##   改完必须**连跑 3 次确认复现**（同一命令、④ 的数字必须逐字相同）。
const AI_TERMS_WALK_PW: int = 300

## 根先验特征分解自检（--aiterms，2026-10-04）：第二档策略头落盘链路的牙齿。
##
## 【背景】`_root_score()` 已从「每候选 19 次权重基分解」改成「一次遍历出 17 项量」。
##   快 19 倍，但引入了一类**新风险**：仿射性一旦被破坏（哪个分支门改成读权重、
##   哪个 `_rt[]` 槽位写错），落盘数据会**静默**错位 —— 训练器照样收敛、
##   恒等式 `orig == base + Σ w·f` 甚至还成立（因为 base 会跟着漂）。
##   所以这里必须有能红的判据，且必须是**跨实现**的（铁律：两套实现必须对拍）。
##
## 四条判据：
##   ① 跨实现对拍：一次遍历的 17 项量 == 旧「置 1/置 0」反解法的结果（逐位）。
##      旧法是**独立算法**（改权重→重算整条链），新法是「一次记量→点积」，
##      两者对不上就说明仿射性破了或槽位写错了。
##   ② 仿射恒等式：`orig == base + Σ w_i·f_i`（用**当前**权重）。
##   ③ 阴性对照：故意把某个 `w_*` 改掉，`orig` 必须跟着变。
##      不变 ⇒ 恒等式判据是瞎的（它对权重不敏感，恒过），这本身就是最危险的失败。
##   ④ 样本非平凡：量出来的 17 项里必须有若干项**非零**。
##      全零也满足 ①②③ —— 那正是旧数据 `w_local` 恒零的形状（判据必须能报红它）。
func _ai_terms_test() -> void:
	_rand_seed = 20261004
	generate_penrose()
	reset_game()
	# ★★ 本自检**全程静音**（`_quiet_place = true`）：它要在**临时摆出的盘面**上连走
	#   几十手，再把盘面整个换回来（阶段二 `reset_game()`、阶段三与 ③ 段 `board = save_board`）
	#   —— 这些手工回滚**都不在** `place_stone()` 的存档里。非静音时留下两类脏条目：
	#     ① `_hist` 多出几十条探测手（悔棋会退到不存在的局面）；
	#     ② （2026-10-14 起）`_superko_hist` 多出几十个**从没下过**的局面指纹 ⇒ 真下到
	#        那些局面会被误判「同形再现」。
	#   静音只关掉"入栈 / 记历史 / 落子日志"，**不动盘面、不动特征统计** ⇒ 本条的四项判据
	#   （①②跨实现对拍、③阴性对照、④非零特征）逐条不受影响。
	_quiet_place = true
	var E := AIEngine.new()
	E.threads = 1
	E.value_blend = 0.0                     # 特征语义要纯净（同落盘仪器口径）
	E.setup(adjacency, Stone.BLACK, 777)
	# ★★ 预算必须**钉死** —— 否则下面那 26 手棋**不可复现**，判据就站在流沙上。
	#   病灶：`_search()` 主循环有**两个**停止条件，其中一个是
	#   `Time.get_ticks_msec() >= deadline`（每 12 次迭代查一次，`deadline = t0 + time_budget_ms`）
	#   ⇒ 迭代次数取决于**墙钟** ⇒ 局面每次略有不同。
	#   2026-10-04 实测（同一条命令连跑 3 次）：④ 的存活特征数在 **4/17 ↔ 5/17** 之间摆动
	#   （`w_tighten` 时有时无），而 ①②③ 稳定 ⇒ 表面上"结论通过"，其实样本在漂
	#   ——这正是铁律 4「判据得在会出问题的那一档上跑」要防的东西。
	#   口径同 `--jevdump`：「**单线程 + 定 pw + 定种子**才可复现」；这里再补一条
	#   "**时间不参与**"：把 `time_budget_ms` 抬到远大于 pw 实际耗时的值
	#   ⇒ 只剩 playout 帽（与"显然手早停"，后者只取决于树状态、是确定性的）会触发。
	E.max_playouts = AI_TERMS_WALK_PW
	E.time_budget_ms = 1000000000           # 实际等于"关掉时间闸"

	# 走到中盘：开局空区太多，`w_local` 之类压根不触发，样本非平凡判据会假红
	for i in 26:
		var mv := E.choose_move(board, ko_point, Stone.BLACK if i % 2 == 0 else Stone.WHITE)
		if mv < 0:
			break
		place_stone(mv, false)
	ai_engine.reset_state()

	var turn_c: int = current_player
	var last: int = _last_move
	var n_stone := 0
	for v in tiles.size():
		if board[v] != Stone.EMPTY:
			n_stone += 1
	print("[aiterms] 盘 %d 格 | 行棋方 %d | 对手上一手 %d | 非空 %d" % [
		tiles.size(), turn_c, last, n_stone])

	# ---- ①② 跨实现对拍 + 仿射恒等式：**开局 / 中盘 / 残局三个阶段各测一遍** ----
	# ★ 为什么要三阶段（铁律 4「判据得在会出问题的那一档上跑」）：
	#   仿射性可能被**只在某些局面出现的分支**破坏 —— 中盘测过不代表残局也过
	#   （提子 / 眼位穷举 / 征子推演在残局才大量触发）。只测中盘 = 覆盖不全。
	#   三阶段的结果**累加**后再判结论，任一阶段不符即整体红。
	var m := AIDATA_W.size()
	var n := 0
	var bad_pair := 0
	var bad_ident := 0
	var worst_pair := 0.0
	var worst_ident := 0.0
	var nz := {}
	for w in AIDATA_W:
		nz[w] = 0
	# 阶段一：当前盘面就是中盘（上面已走到 26 手）
	var st := _aiterms_probe_phase(E, turn_c, last, "中盘")
	n += int(st["n"])
	bad_pair += int(st["bad_pair"])
	bad_ident += int(st["bad_ident"])
	worst_pair = maxf(worst_pair, float(st["worst_pair"]))
	worst_ident = maxf(worst_ident, float(st["worst_ident"]))
	for k in nz.keys():
		nz[k] = int(nz[k]) + int(st["nz"][k])
	# 阶段二：**开局**（新盘、0 手）—— 空区最多，`_own_territory_only` 等早退路径在这里
	var save_board: Dictionary = board.duplicate()
	var save_ko: int = ko_point
	var save_last: int = _last_move
	var save_cp: int = current_player
	reset_game()
	ai_engine.reset_state()
	var st0 := _aiterms_probe_phase(E, 1, -1, "开局")
	n += int(st0["n"])
	bad_pair += int(st0["bad_pair"])
	bad_ident += int(st0["bad_ident"])
	worst_pair = maxf(worst_pair, float(st0["worst_pair"]))
	worst_ident = maxf(worst_ident, float(st0["worst_ident"]))
	for k in nz.keys():
		nz[k] = int(nz[k]) + int(st0["nz"][k])
	# 阶段三：**残局**（从存档继续走到剩 8 格以内）—— 提子/眼位/征子分支在这里才密集
	board = save_board
	ko_point = save_ko
	_last_move = save_last
	current_player = save_cp
	ai_engine.reset_state()
	var guard := 0
	while _empty_count() > 8 and guard < 400:
		guard += 1
		var tcv: int = current_player
		var mv2 := E.choose_move(board, ko_point, tcv)
		if mv2 < 0:
			break
		place_stone(mv2, false)
	ai_engine.reset_state()
	var st2 := _aiterms_probe_phase(E, current_player, _last_move, "残局")
	n += int(st2["n"])
	bad_pair += int(st2["bad_pair"])
	bad_ident += int(st2["bad_ident"])
	worst_pair = maxf(worst_pair, float(st2["worst_pair"]))
	worst_ident = maxf(worst_ident, float(st2["worst_ident"]))
	for k in nz.keys():
		nz[k] = int(nz[k]) + int(st2["nz"][k])

	var live: Array[String] = []
	var dead: Array[String] = []
	for w in AIDATA_W:
		if int(nz[w]) > 0:
			live.append(w)
		else:
			dead.append(w)
	print("[aiterms] 三阶段累计候选 %d | ①对拍不符 %d 处（最大差 %.6f）| ②恒等式不符 %d 处（最大差 %.6f）" % [
		n, bad_pair, worst_pair, bad_ident, worst_ident])
	print("[aiterms] ④ 非零特征 %d/%d %s" % [live.size(), m, live])
	print("[aiterms]   恒零 %d 个 %s" % [dead.size(), dead])

	# 阴性对照必须在**中盘**做（残局特征稀疏，更容易撞上首版那个假红）
	board = save_board
	ko_point = save_ko
	_last_move = save_last
	current_player = save_cp
	ai_engine.reset_state()
	# ---- ③ 阴性对照：改权重后 orig 必须变 ----
	# ★★ 必须挑一对**互相匹配**的「格子 + 权重」，且那个特征在该格子上**非零**。
	#   ⚠️ 2026-10-04 实测的假红（首版写法）：先把 `wsel` 按**全盘存活**挑出来
	#   （挑到 `w_self_atari`），却在**第一个空格** `v0` 上量 Δ —— 而那个格子上该特征
	#   恰好是 0.0 ⇒ Δ 恒为 0.0000 ⇒ 判"失败"（其实产线是好的，白查一轮）。
	#   病灶与铁律 13⑨ 同族：**"样本非平凡"没做进判据里** —— "我挑的权重"与"我量的格子"
	#   不是同一个样本。⇒ 修法是让两件事出自**同一次探针**（下面这个双层循环）。
	#   `v0 < 0`（全盘没有非零特征）本身是失败：那说明特征全死了，由 ④ 那一半兜底。
	var v0 := -1
	var wsel := ""
	for v in tiles.size():
		if board[v] != Stone.EMPTY or v == ko_point:
			continue
		var ft0: PackedFloat32Array = E.probe_root_terms_last(
			board, v, turn_c, last)["terms"]
		for i in m:
			if ft0[i] != 0.0:
				v0 = v
				wsel = str(AIDATA_W[i])
				break
		if v0 >= 0:
			break
	var o1 := 0.0
	var o2 := 0.0
	var feat_val := 0.0
	if v0 >= 0:
		var p1: Dictionary = E.probe_root_terms_last(board, v0, turn_c, last)
		o1 = float(p1["orig"])
		var ix: int = AIDATA_W.find(wsel)
		feat_val = float((p1["terms"] as PackedFloat32Array)[ix]) if ix >= 0 else 0.0
		var old_w: float = float(E.get(wsel))
		E.set(wsel, old_w + 7.0)
		o2 = float(E.probe_root_terms_last(board, v0, turn_c, last)["orig"])
		E.set(wsel, old_w)                    # 复原
	print("[aiterms] ③ 阴性对照 v%d × %s（该格特征值 %.3f）+= 7 ⇒ orig %.4f -> %.4f（Δ %.4f）" % [
		v0, wsel, feat_val, o1, o2, o2 - o1])

	# ---- 结论 ----
	# ★ `n` 必须够大：三阶段都跑过才有覆盖面（只测一个局面 = 覆盖不全）
	var ok := bad_pair == 0 and bad_ident == 0 and absf(o2 - o1) > 1.0e-6 \
			and live.size() >= 3 and n >= 60
	_quiet_place = false       # 与开头那处成对（自检全程静音，退出前还原）
	print("[aiterms] 结论：%s" % ("通过" if ok else "失败"))
	get_tree().quit(0 if ok else 1)


## 一个阶段（一个盘面）的 ①② 对拍。返回该阶段的统计，供三阶段累加。
##   ⚠️ 抽成函数是为了让「多个阶段走**同一条**代码」—— 复制三份循环的话，
##   将来改一处忘另两处 = 两个阶段的覆盖悄悄没了，而结论照样打印"通过"。
func _aiterms_probe_phase(E: AIEngine, turn_c: int, last: int, tag: String) -> Dictionary:
	var n := 0
	var bad_pair := 0
	var bad_ident := 0
	var worst_pair := 0.0
	var worst_ident := 0.0
	var nz := {}
	var m := AIDATA_W.size()
	for w in AIDATA_W:
		nz[w] = 0
	var save: Array[float] = []
	for i in m:
		save.append(float(E.get(AIDATA_W[i])))
	for v in tiles.size():
		if board[v] != Stone.EMPTY or v == ko_point:
			continue
		n += 1
		var fast: Dictionary = E.probe_root_terms_last(board, v, turn_c, last)
		var f_new: PackedFloat32Array = fast["terms"]
		var base: float = float(fast["base"])
		var orig: float = float(fast["orig"])
		# 旧法：逐特征置 1、其余 0，反解 —— **独立算法**，跨实现对拍的另一端
		var f_old := _terms_by_basis(E, v, turn_c, last)
		for i in m:
			var d: float = absf(f_new[i] - f_old[i])
			if d > worst_pair:
				worst_pair = d
			if d > 1.0e-4:
				bad_pair += 1
		# emp_nb（第 18 项）单独比：它是几何量，与权重无关
		var emp := 0
		for nb in adjacency[v]:
			if board[nb] == Stone.EMPTY:
				emp += 1
		if absf(f_new[m] - float(mini(emp, 4))) > 1.0e-4:
			bad_pair += 1
		var acc := base
		for i in m:
			if f_new[i] != 0.0:
				nz[AIDATA_W[i]] = int(nz[AIDATA_W[i]]) + 1
			acc += save[i] * f_new[i]
		var di: float = absf(acc - orig)
		if di > worst_ident:
			worst_ident = di
		if di > 1.0e-3:
			bad_ident += 1
	for i in m:
		E.set(AIDATA_W[i], save[i])         # 复原：自检不许污染现场
	if bad_pair > 0 or bad_ident > 0:
		print("[aiterms]   [%s] ①不符 %d / ②不符 %d（最大差 %.6f / %.6f）"
			% [tag, bad_pair, bad_ident, worst_pair, worst_ident])
	return {"n": n, "bad_pair": bad_pair, "bad_ident": bad_ident,
		"worst_pair": worst_pair, "worst_ident": worst_ident, "nz": nz}


func _empty_count() -> int:
	var c := 0
	for v in tiles.size():
		if board[v] == Stone.EMPTY:
			c += 1
	return c


## 旧法（权重基分解）：逐项置 1、其余 0，用 `probe_root_score` 的差值反解原始量。
## **只当对拍基准用**，不进落盘热路径 —— 它每候选要调 19 次 `_root_score()`
## （挂着 8000 节点的眼位穷举与 600 节点的征子推演），慢约 19 倍。
func _terms_by_basis(E: AIEngine, v: int, turn_c: int, last: int) -> PackedFloat32Array:
	var m := AIDATA_W.size()
	var save: Array[float] = []
	for i in m:
		save.append(float(E.get(AIDATA_W[i])))
	for i in m:
		E.set(AIDATA_W[i], 0.0)
	var base: float = E.probe_root_score_last(board, v, turn_c, last)
	var out := PackedFloat32Array()
	out.resize(m)
	for i in m:
		E.set(AIDATA_W[i], 1.0)
		out[i] = E.probe_root_score_last(board, v, turn_c, last) - base
		E.set(AIDATA_W[i], 0.0)
	for i in m:
		E.set(AIDATA_W[i], save[i])
	return out


## AI 性能基线自检（--aibench）：量化「每档时间预算能跑多少次 playout」，作为调参/提速依据。
##
## 纯 rollout 那一行会**同进程交替**跑收紧版送吃守卫与旧守卫各 4 轮，取各自的最优值。
## 两者棋力完全等价（收紧版只是省掉不可能命中的 BFS），所以这个比值是干净的真实提速比。
## 为什么要交替 + 取最优：同机多次跑同一份代码，实测「次数」能差近 2 倍
## （后台杀毒、其他进程抢 CPU 都会压低计数），
## 先跑 A 再跑 B 会把环境噪声误读成机制差异 —— 交替并取每方最优值才能反映代码本身的差距。
func _ai_bench() -> void:
	var budgets: Array[int] = [100, 800, 3000]
	var sizes: Array[int] = [GameConfig.RANDOM, GameConfig.STANDARD, GameConfig.ENHANCED]
	_rand_seed = 424242            # 基准测量必须用固定的一张盘，否则「提速」里混进盘面差异
	for sz in sizes:
		GameConfig.board_size = sz
		_apply_board_size(sz)
		generate_penrose()
		reset_game()
		ai_engine.reset_state()
		ai_engine.setup(adjacency, AI_COLOR)
		var best_old := 0
		var best_new := 0
		# 先热身一轮：第一次 benchmark 会带上 JIT / 缺页 / 缓存冷启动的开销，
		# 若把它算进对照，测到的就不是守卫改动的效果而是「谁先跑」。
		ai_engine.reset_state()
		ai_engine.benchmark(300)
		# 测量窗口用 600ms 而非 200ms。200ms 窗口下同一份代码跨进程能差出 47%
		# （旧守卫实测 114 → 168 次/200ms），噪声完全盖住被测的百分之几的差异。
		# 注意：即便这样，这个「提速百分比」仍然只适合看趋势；
		# 真正可比的是上面那组「固定预算 → playouts 数」，那个指标稳定得多。
		for rep in 3:
			ai_engine.reset_state()
			ai_engine.narrow_self_atari_guard = false
			best_old = maxi(best_old, ai_engine.benchmark(600))
			ai_engine.reset_state()
			ai_engine.narrow_self_atari_guard = true
			best_new = maxi(best_new, ai_engine.benchmark(600))
		var gain := 0.0
		if best_old > 0:
			gain = (float(best_new) / float(best_old) - 1.0) * 100.0
		print("[aibench] 棋盘=%s 格数=%d | 纯 rollout 旧守卫 %d / 新版 %d 次每 600ms 最优（提速 %.0f%%）" % [
			_board_size_name(sz), tiles.size(), best_old, best_new, gain])
		for b in budgets:
			ai_engine.time_budget_ms = b
			ai_engine.reset_state()
			var t0 := Time.get_ticks_msec()
			var mv := ai_engine.choose_move(board, ko_point)
			print("[aibench]   预算=%dms → playouts=%d 实际用时=%dms 落子=%d" % [
				b, ai_engine.last_playouts, Time.get_ticks_msec() - t0, mv])
	get_tree().quit()

## 死活考题（19×19 方形夹具）：一方围出「直三」、对手在框外封死，使其气只剩内部 3 点。
## 点在正中间就把空区截成两只单点真眼（做活）/ 破掉对方的眼（点杀）；点两端必错。
## 这是围棋最基本的死活题，也是"AI 会不会做活、会不会杀棋"最直接的考题。
## 自检（--ladtest）：征子（ladder）判定的正确性 + 开销。
## 正确性用两个手工验算过的局面（坐标跑在方形邻接夹具上，见 _test_build_square_grid）：
##   ① 无效叫吃：白打吃黑 3 子，但黑一长就冲到 3 气 → 必须判 false（不该去打）
##   ② 真征子  ：黑唯一长气点的两侧已被白封死，长过去仍只有 1 气 → 必须判 true
## 开销用固定预算下的 playouts 数 A/B（同进程开关对照，避开跨进程噪声）。
func _ladder_test() -> void:
	_test_build_square_grid(TEST_GRID_N)
	reset_game(true)
	ai_engine.setup(adjacency, Stone.WHITE)
	var N := TEST_GRID_N
	# ① 黑 3 子 (5,5)(6,5)(7,5)；白封上方 + 左下，黑剩 (8,5)(7,6) 两气 → 白下 (8,5) 打吃。
	# 黑长 (7,6) → 2 气；白追 (7,7)；黑长 (8,6) → 3 气，逃掉。
	# ★ 2026-09-20 补黑接应子 (9,7)：续打分支化之后读者会发现这条廊道沿 x+ 一路
	#   征到右边界（x=18）其实征得死 —— ① 要断言「真的逃得掉」，必须给黑一块
	#   逃到那里就能连上的援军，否则所有分支都死、断言前提就变了（见 ⑤）。
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(9, 7)]:
		board[p.y * N + p.x] = Stone.BLACK
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		board[p.y * N + p.x] = Stone.WHITE
	var ra: Dictionary = ai_engine.probe_ladder(board, 5 * N + 8)
	# ② 同形状，但白额外占住 (8,4)(8,6)：黑长到 (8,5) 后只剩 (9,5) 一气 → 征死。
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		board[p.y * N + p.x] = Stone.BLACK
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5),
			  Vector2i(7, 6), Vector2i(6, 6), Vector2i(8, 4), Vector2i(8, 6)]:
		board[p.y * N + p.x] = Stone.WHITE
	var rb: Dictionary = ai_engine.probe_ladder(board, 6 * N + 5)
	print("[ladtest] ① 无效叫吃（黑长气后冲到 3 气）→ 判定征死=%s → %s" % [
		str(ra["ladder"]), "通过 ✓" if ra["ladder"] == false else "未通过 ✗"])
	print("[ladtest] ② 真征子（长气点两侧已封死）→ 判定征死=%s → %s" % [
		str(rb["ladder"]), "通过 ✓" if rb["ladder"] == true else "未通过 ✗"])
	# ④ 先验改动对照（**确定性**）：分支化（2026-09-20）后换用无接应几何 ——
	#   黑 3 子两气 {(8,5),(7,6)}：白 (8,5) 打吃后黑逃 (7,6) 只剩 2 气，
	#   沿 x+ 一路征到右边界 → 征得死（good）；白 (7,6) 打吃后黑逃 (8,5) 直接 3 气 →
	#   征不死（bad）。旧位置②的两个点分支化后**都**征得死（(8,5) 沿底边一线），
	#   前提不成立只好换。
	# 关征子时两点都只拿 w_threat_each，开征子后征死点额外拿 w_ladder_good·sqrt(gsz)、
	# 无效点拿 w_ladder_bad·sqrt(gsz)，于是「两点分数之差」的开关增量应精确 = (good-bad)·sqrt(gsz)。
	# 不去比 choose_move 的选着：那个会因时间预算/多线程而飘（实测同局面两次结论不同），
	# 不能当回归断言。也不假设「两点只差征子一项」——实测它们还有其它先验差，
	# 所以校验的是**增量**：开关征子前后差值的变化量必须精确等于 (w_good - w_bad)·sqrt(gsz)。
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		board[p.y * N + p.x] = Stone.BLACK
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		board[p.y * N + p.x] = Stone.WHITE
	var good: int = 5 * N + 8
	var bad: int = 6 * N + 7
	var gsz := 3.0                     # 被打吃的是黑 3 子串
	var expect := (ai_engine.w_ladder_good - ai_engine.w_ladder_bad) * sqrt(gsz)
	var gap: Array[float] = []
	for on in [false, true]:
		ai_engine.ladder_enabled = on
		var sa: float = ai_engine.probe_root_score(board, good, Stone.WHITE)
		var sb: float = ai_engine.probe_root_score(board, bad, Stone.WHITE)
		gap.append(sa - sb)
	var delta := gap[1] - gap[0]
	var ok_lad: bool = absf(delta - expect) < 0.01
	print("[ladtest] ④ 先验对照（征死点=%d 无效叫吃点=%d）：关征子差值=%.2f 开征子差值=%.2f → 增量=%.2f（期望 %.2f）→ %s" % [
		good, bad, gap[0], gap[1], delta, expect, "通过 ✓" if ok_lad else "未通过 ✗"])
	# ③ 开销 A/B（彭罗斯标准盘，随机铺 12 手）
	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	generate_penrose()
	reset_game(true)
	ai_engine.setup(adjacency, AI_COLOR)
	ai_engine.scramble(12)
	_load_board_from_engine()
	ai_engine.time_budget_ms = 600
	ai_engine.ladder_enabled = false
	ai_engine.reset_state()
	var t0 := Time.get_ticks_msec()
	var mv_off := ai_engine.choose_move(board, -1, AI_COLOR)
	var ms_off := Time.get_ticks_msec() - t0
	var po_off := ai_engine.last_playouts
	ai_engine.ladder_enabled = true
	ai_engine.reset_state()
	t0 = Time.get_ticks_msec()
	var mv_on := ai_engine.choose_move(board, -1, AI_COLOR)
	var ms_on := Time.get_ticks_msec() - t0
	var po_on := ai_engine.last_playouts
	var drop := 0.0
	if po_off > 0:
		drop = (1.0 - float(po_on) / float(po_off)) * 100.0
	print("[ladtest] ③ 开销（600ms）：关=playouts %d（%dms，落子 %d）| 开=playouts %d（%dms，落子 %d）→ 模拟量下降 %.1f%% %s" % [
		po_off, ms_off, mv_off, po_on, ms_on, mv_on, drop,
		"可接受 ✓" if drop < 25.0 else "过重 ✗（调小 ladder_max_plies / 提高 ladder_min_size）"])

	# ---- 2026-09-20 分支化 + 逃征子 ---
	# ★ ③ 的开销段把引擎切到了彭罗斯盘（n=120），⑤⑥⑦ 跑在 19×19 夹具上 ——
	#   不重装就 121 号索引越界（首跑的 Out of bounds 就是它）。
	_test_build_square_grid(TEST_GRID_N)
	reset_game(true)
	ai_engine.setup(adjacency, Stone.WHITE)
	# ⑤ 分支化正例：① 的几何但**不放接应子** → 征子沿 x+ 一路打到右边界（x=18），
	#   征得死。贪心读者（旧）走 (8,6) 那条废线判 false；分支读者两条线都试 → true。
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		board[p.y * N + p.x] = Stone.BLACK
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		board[p.y * N + p.x] = Stone.WHITE
	var re5: Dictionary = ai_engine.probe_ladder(board, 5 * N + 8)
	print("[ladtest] ⑤ 分支化（无接应 → 沿右边界征死）→ 判定征死=%s → %s" % [
		str(re5["ladder"]), "通过 ✓" if re5["ladder"] == true else "未通过 ✗"])

	# ⑥ 逃征子惩罚增量：⑤ 的局面 + 白 (8,5) 已落 → 黑 3 子只剩 (7,6) 一气。
	#    黑逃 (7,6) 之后攻方按同一套推演仍征得死 → ladder_escape_check
	#    开/关的 probe_root_score 差值必须精确 = w_ladder_run·sqrt(3) − w_save_each·3。
	#    ★ 2026-09-28 起改拨布尔开关：w_ladder_run 不再当分析开关用（权重基分解
	#      要求打分对 w_* 纯线性，见 ai_engine.gd:192 注释）。
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		board[p.y * N + p.x] = Stone.BLACK
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5), Vector2i(5, 6),
			  Vector2i(6, 6), Vector2i(8, 5)]:
		board[p.y * N + p.x] = Stone.WHITE
	var esc_pt: int = 6 * N + 7
	var saved_wt := sqrt(3.0)
	# 差值由两部分组成（都在设计内）：惩罚项 w_ladder_run·√3 + 逃跑奖励被摘掉
	# −w_save_each·3（开关 ON 时 saved 里不再有这 3 子）。
	var run_expect: float = ai_engine.w_ladder_run * saved_wt - ai_engine.w_save_each * 3.0
	var run_delta: Array[float] = []
	for chk in [false, true]:
		ai_engine.ladder_escape_check = chk
		run_delta.append(ai_engine.probe_root_score(board, esc_pt, Stone.BLACK))
	var d6: float = run_delta[1] - run_delta[0]
	var ok6: bool = absf(d6 - run_expect) < 0.01
	print("[ladtest] ⑥ 逃征子惩罚（逃=%d，征死推演=true）：开-关差值=%.2f（期望 %.2f = 惩罚%.2f + 摘奖励%.2f）→ %s" % [
		esc_pt, d6, run_expect, ai_engine.w_ladder_run * saved_wt,
		-ai_engine.w_save_each * 3.0, "通过 ✓" if ok6 else "未通过 ✗"])
	ai_engine.ladder_escape_check = true
	# ⑥b 解耦阴性对照：布尔开关 ON 时，w_ladder_run 0↔默认 只应改惩罚项本身
	#    （分类路径不动、saved 不动）→ 差值必须精确 = w_ladder_run·sqrt(3)。
	#    若旧病复发（权重又被当门槛），这 3 子会被摘出 saved，差值混入 −w_save_each·3。
	var dec_expect: float = ai_engine.w_ladder_run * saved_wt
	var dec_delta: Array[float] = []
	var run_wt_keep := ai_engine.w_ladder_run
	for w in [0.0, run_wt_keep]:
		ai_engine.w_ladder_run = w
		dec_delta.append(ai_engine.probe_root_score(board, esc_pt, Stone.BLACK))
	ai_engine.w_ladder_run = run_wt_keep
	var d6b: float = dec_delta[1] - dec_delta[0]
	print("[ladtest] ⑥b 解耦对照（纯惩罚项）：差值=%.2f（期望 %.2f）→ %s" % [
		d6b, dec_expect, "通过 ✓" if absf(d6b - dec_expect) < 0.01 else "未通过 ✗"])

	# ⑦ 逃得掉的逃不受惩罚：① 的几何 + 接应子 (9,7) + 白 (8,5) 已落 → 黑逃 (7,6)
	#    能连上援军 → 逃跑有效 → ladder_escape_check 开/关差值必须 = 0。
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5), Vector2i(9, 7)]:
		board[p.y * N + p.x] = Stone.BLACK
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5), Vector2i(5, 6),
			  Vector2i(6, 6), Vector2i(8, 5)]:
		board[p.y * N + p.x] = Stone.WHITE
	var run_delta7: Array[float] = []
	for chk in [false, true]:
		ai_engine.ladder_escape_check = chk
		run_delta7.append(ai_engine.probe_root_score(board, esc_pt, Stone.BLACK))
	var d7: float = run_delta7[1] - run_delta7[0]
	print("[ladtest] ⑦ 逃跑有效（接应子连通）：差值=%.2f（期望 0.00）→ %s" % [
		d7, "通过 ✓" if absf(d7) < 0.01 else "未通过 ✗"])
	ai_engine.ladder_escape_check = true

	get_tree().quit()


## 死活状态名（0=死 / 1=未定形 / 2=活），口径与 `AIEngine._group_status()` 一致
func _ld_st_name(st: int) -> String:
	match st:
		0:
			return "死"
		1:
			return "未定"
		2:
			return "活"
	return "?"


## 形内相对偏移 → 19×19 方形夹具上的全局点号
func _ld_id_of(p: Vector2i, base: Vector2i) -> int:
	return (base.y + p.y) * TEST_GRID_N + (base.x + p.x)


## 真源「小眼形」表 —— **与工作区 `死活真源/eye_ld_solver2.py` 逐条对应**（改表前必须先改真源脚本）。
##   st   = 三态：0 = 死（**防守方先手也死**）、1 = 未定形、2 = 活
##   kill = 真源「攻方先手要点」集合（相对偏移）；空集 = 已是活形，攻方怎么下都杀不掉
## 真源是穷举出来的（局部图模型 + 极小极大 + 循环判活 + 提整串算合法手），不是棋理口诀；
## 口诀只用来交叉复核：
##   直二 / 方四                      → 死
##   直三 / 弯三 / 丁四 / 梅花五 / 刀把五 / 阶梯七 → 未定形（先手占要点者胜）
##   直四 / 曲四 / 直五 / 直六 / 葡萄六 / 直七 / 方八 → 活
func _ld_shape_table() -> Array:
	return [
		{"n": "直二", "pts": [Vector2i(0, 0), Vector2i(1, 0)], "st": 0,
			"kill": [Vector2i(0, 0), Vector2i(1, 0)]},
		{"n": "直三", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "st": 1,
			"kill": [Vector2i(1, 0)]},
		{"n": "弯三", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "st": 1,
			"kill": [Vector2i(0, 0)]},
		{"n": "直四", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)], "st": 2,
			"kill": []},
		{"n": "曲四", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 2)], "st": 2,
			"kill": []},
		{"n": "方四", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "st": 0,
			"kill": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]},
		{"n": "丁四", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)], "st": 1,
			"kill": [Vector2i(1, 0)]},
		{"n": "直五", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(4, 0)], "st": 2, "kill": []},
		{"n": "梅花五", "pts": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
			Vector2i(1, 2)], "st": 1, "kill": [Vector2i(1, 1)]},
		{"n": "刀把五", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1),
			Vector2i(2, 1)], "st": 1, "kill": [Vector2i(1, 0)]},
		{"n": "葡萄六", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1),
			Vector2i(1, 1), Vector2i(2, 1)], "st": 2, "kill": []},
		{"n": "直六", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(4, 0), Vector2i(5, 0)], "st": 2, "kill": []},
		# ---- 7/8 目（2026-09-20 cap=7 定标新增；结论与杀点由真源逐位验证）----
		# 阶梯七 = cap=6 时代的已知假活例：未定形，攻方杀点只有腰点 (1,1)。
		{"n": "阶梯七", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
			Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)], "st": 1,
			"kill": [Vector2i(1, 1)]},
		{"n": "直七", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)], "st": 2, "kill": []},
		# 方八是 8 目 —— cap=7 下走「区域超上限 → 判活」捷径，不进穷举（回归捷径路径）。
		{"n": "方八", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)], "st": 2,
			"kill": []},
	]


## 摆一个「眼位空间」死活夹具：ring_color 围住 pts（防守方），wall_color 在 Chebyshev-2 外圈封死。
## 与真源求解器**同款构造**：ring = Chebyshev-1 膨胀 − eye，wall = Chebyshev-2 膨胀 − ring − eye。
## base = 本形在 19×19 夹具上的左上锚点（形最宽 6 → base.x ∈ [2,11] 才装得下）。
## 返回 ring 上一个点（探针入口）。
func _lay_eye_shape(pts: Array, base: Vector2i, ring_color: int, wall_color: int) -> int:
	var n: int = TEST_GRID_N
	var eye: Array[Vector2i] = []
	for p: Vector2i in pts:
		eye.append(Vector2i(base.x + p.x, base.y + p.y))
	var ring: Array[Vector2i] = []
	var wall: Array[Vector2i] = []
	for r: int in [1, 2]:
		var dst: Array[Vector2i] = ring if r == 1 else wall
		for p: Vector2i in eye:
			for dx in range(-r, r + 1):
				for dy in range(-r, r + 1):
					var q := Vector2i(p.x + dx, p.y + dy)
					if eye.has(q) or ring.has(q) or dst.has(q):
						continue
					dst.append(q)
	for q: Vector2i in ring:
		board[q.y * n + q.x] = ring_color
	for q: Vector2i in wall:
		board[q.y * n + q.x] = wall_color
	return ring[0].y * n + ring[0].x


## `_lay_eye_shape()` 的**关键补充**：摆完封闭眼形后，再挖掉 k 个「贴着内环」的外墙子，
## 让内环那块棋**多出 k 口气**（= 既有眼位空间、又有外气）。
##
## 为什么必须补这个：原夹具把棋块封死、气**恰好只有眼位空间那几个** → `_group_alive()` 的
## 「≥2 只单点眼 **或** 气 ≥6」两个条件都不成立 → 一律判「未活」→ 过滤层必然走豁免分支。
## 于是「既有眼位空间、又有外气」这个**实战常态**从来没被测过 ——
## 而实战里棋块气数一旦到 6，`_group_alive()` 就说它「活」，整片眼位空间随即被过滤层封住。
func _lay_eye_shape_with_libs(pts: Array, base: Vector2i, ring_color: int, wall_color: int,
		outside_libs: int) -> int:
	var rep := _lay_eye_shape(pts, base, ring_color, wall_color)
	if outside_libs <= 0:
		return rep
	var n: int = TEST_GRID_N
	var eye: Array[Vector2i] = []
	for p: Vector2i in pts:
		eye.append(Vector2i(base.x + p.x, base.y + p.y))
	var ring: Array[Vector2i] = []
	for p: Vector2i in eye:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var q := Vector2i(p.x + dx, p.y + dy)
				if not eye.has(q) and not ring.has(q):
					ring.append(q)
	# 外墙里「正交贴着内环」的那些 → 挖掉它们才真能让内环那块棋长气
	var cand: Array[Vector2i] = []
	for p: Vector2i in ring:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if eye.has(q) or ring.has(q) or cand.has(q):
				continue
			if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n:
				continue
			cand.append(q)
	# 排序后固定取前 k 个：夹具必须**逐位可复现**，否则断言会飘
	cand.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * n + a.x < b.y * n + b.x)
	var k: int = 0
	while k < outside_libs and k < cand.size():
		board[cand[k].y * n + cand[k].x] = Stone.EMPTY
		k += 1
	return rep


## 自检（--areatest）**过滤层口径专项**（确定性，无搜索 / 无随机器 / 无线程，可当回归断言）。
##
## 被测对象只有一句话：**过滤层凭什么封掉一片己方空区**。
##   · 过滤层用的是**旧**判据 `_group_alive()` = 「≥2 只单点眼 **或** 气 ≥6」；
##   · 真死活求解器是 `_group_status()` = 「封闭眼位空间穷举 / 非封闭按 ld_max_libs 比气」。
## 两个口径本该同向，实测**两个方向都会打架**，而且两处都是静默的：
##   方向 A（封住了未定形的眼位 → AI 下不出做活要点 = 用户说的「不会做活」）：
##     棋块气 ≥ 6 但只有一个可被杀的眼位空间 → 旧判据说「活」→ 整片空间被封；
##     而 `_group_status()` 说「未定形(1)」→ 要点本该是 AI 的做活手。
##   方向 B（没封住已经活定的眼形 → AI 往自己活形里填 = 用户说的「填自己的眼」）：
##     直四 / 曲四 / 直五 / 葡萄六 / 直六 / 直七 这些真源判**活(2)** 的形状，
##     单点眼数 = 0、气 < 6 → 旧判据说「未活」→ 整片空间开闸，AI 可以往里填。
##
## 判据（不是「谁对」，而是**两个判据不许自相矛盾** —— 宽严不齐正是本工程反复踩的坑）：
##   · 方向 A：`_group_status()` 说未定形(1) 时，过滤层不得封（要点必须在候选集里）；
##   · 方向 B：`_group_status()` 说活(2) 时，过滤层宜封（活形的内部不该是可选项）。
## 自检（--analyzetest）**全局局势分析层**（确定性；只读、不用搜索）。
##
## 被测对象：`AIEngine.analyze_board()` —— 逐块死活分区 + 净胜率 + 行动指令。
## 它要解决的用户问题：**AI 落后时宁可去对方地盘落子也不回头救自己快死的块**。
## 病根在旧口径：`_area_score()` 里死子与活子一样都算面积 ⇒ 救死子是净亏。
##
## 七段判据（详见补丁脚本头部）：① 死形认死 ② 活形认活 ③ 阳性对照（关求解器必须失手）
## ④ 阴性对照（活形不许同时判死） ⑤ 只读纪律 ⑥ 严格单调 ⑦ 音乐接线。
func _analyze_self_test() -> void:
	var base := Vector2i(4, 4)
	# 真源 12 形（死活真源/说明.md）：st 列 = 防守方先手，kill 列 = 攻方先手。
	# 取其中「攻方先手能杀」的死形做①，「两方都活」的活形做②。
	var dead_shapes: Array = []
	var live_shapes: Array = []
	# ★ 直接用真源表自带的 `st` 字段当判据真源（铁律 18：公式只有一个真源）——
	#   我第一版想按形名硬编码「哪些是死形/活形」，那是把真源表抄了第二份，
	#   真源表一改就漂。`st` = 防守方先手能活否：0 死 / 1 未定形 / 2 活。
	for cs: Dictionary in _ld_shape_table():
		if int(cs.get("st", -1)) == 0:
			dead_shapes.append(cs)
		elif int(cs.get("st", -1)) == 2:
			live_shapes.append(cs)
	print("[analyzetest] ===== 全局局势分析层 =====")
	print("[analyzetest] 判据① 死形（真源判攻方能杀）须认成 DEAD | 判据② 活形（真源判两方都活）须认成 LIVE")
	print("[analyzetest] 判据③ 阳性对照：ld_cap_points 调 0（死形求解短路）后 ① 必须失手 ⇒ 证明 ① 测的是真死活")
	print("[analyzetest] 判据④ 阴性对照：活形不许同时被判 DEAD（防「一律判死」的反向恒真）")
	print("[analyzetest] 判据⑤ 只读：analyze_board 前后棋盘逐位一致且 _ld_n 已复位")
	print("[analyzetest] 判据⑥ 严格单调（判在**黑块子数之和**这个纯计数上；points/win_rate 有界或含评估项，只作读数）")
	print("[analyzetest] 判据⑧ 分区互斥+完备：tag 全合法且子数对得上（防漏网之块）")
	print("[analyzetest] 判据⑦ 音乐：局势字段**生产端真的发出去**（反射读真场景 + 逐项与成员对账）"
			+ " + 完整性闸有阴性对照 + 四轴只随自己的信号动")

	var fail_dead: Array = []
	var fail_live: Array = []
	var fail_pos: Array = []
	var fail_neg: Array = []
	var fail_ro: Array = []
	var fail_mono: Array = []
	var fail_music: Array = []
	var n_dead: int = 0
	var n_live: int = 0
	var skipped_leaky: Array = []   # 漏气而豁免的形（附原因）
	var leaky_names: Array = []     # 只存形名，供阳性对照用同一豁免口径

	# ---------- ① 死形须认成 DEAD / ② 活形须认成 LIVE ----------
	for group: Array in [[dead_shapes, "dead"], [live_shapes, "live"]]:
		var shapes: Array = group[0]
		var mode := String(group[1])
		for cs: Dictionary in shapes:
			var nm := String(cs.get("n", "?"))
			reset_game(true)
			_test_build_square_grid(TEST_GRID_N)
			ai_engine.setup(adjacency, Stone.WHITE)
			ai_engine.ld_enabled = true
			# 白 = 内环围壁（有眼位空间的那块，= 被测对象），黑 = 外墙。
			# ★ outside_libs 必须 **0（封闭）**：`_group_status()` 在「有外气」时
			#   直接 `return 2 if libs > ld_max_libs else 1` —— 永不判 DEAD。
			#   给外气就等于要求「死形判 DEAD」达成一个**不可能**的目标（铁律 4：
			#   判据红先怀疑「我测错了」，别急着改被测代码）。
			_lay_eye_shape_with_libs(cs["pts"], base, Stone.WHITE, Stone.BLACK, 0)
			var a := ai_engine.analyze_board(board, ko_point)
			var tag := _dominant_tag(a, Stone.WHITE)
			if mode == "dead":
				# ★ 只对**气密**（libs <= ld_max_libs）的死形要求 DEAD。
				#   漏气的形（如方四在 5×5 网格上 libs=24）会走`未封闭 ⇒气宽判活` 分支，
				#   那是引擎的既定设计而非 bug（`ai_engine.gd:990`）⇒ 判它= 测一个坏夹具。
				#   依据：`死活真源/说明.md` 移植四坑①「夹具必须气密，角上会漏气」。
				# ★ 用**主体块**的 libs（与 `_dominant_tag` 同一处选，避免自相矛盾）
				var bl := int(_dominant_block(a, Stone.WHITE).get("libs", 0))
				if bl > int(ai_engine.ld_max_libs):
					skipped_leaky.append("%s(libs=%d)" % [nm, bl])
					leaky_names.append(nm)
					continue
				n_dead += 1
				if tag != "DEAD":
					fail_dead.append("%s→%s" % [nm, tag])
			else:
				n_live += 1
				if tag != "LIVE":
					fail_live.append("%s→%s" % [nm, tag])
	print("[analyzetest] ① 死形 %d 个：认成 DEAD %d/%d%s%s"
			% [n_dead, n_dead - fail_dead.size(), n_dead,
			   "" if fail_dead.is_empty() else " ✗ %s" % str(fail_dead),
			   "" if skipped_leaky.is_empty()
			   else " ｜豁免(漏气，非判据目标): %s" % str(skipped_leaky)])
	print("[analyzetest] ② 活形 %d 个：认成 LIVE %d/%d%s"
			% [n_live, n_live - fail_live.size(), n_live,
			   "" if fail_live.is_empty() else " ✗ %s" % str(fail_live)])

	# ---------- ③ 阳性对照：关掉死活求解器，① 必须开始失手 ----------
	#不这么做的话，① 可能只是在数「块有几块」—— 关掉求解器后它若仍全对，说明它压根没在测死活。
	var pos_still_ok := 0
	for cs: Dictionary in dead_shapes:
		var nm_p := String(cs.get("n", "?"))
		# 同一个豁免口径：阳性对照只跑**气密**的死形，否则它在比一个不成立的期望。
		if leaky_names.has(nm_p):
			continue
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.WHITE)
		# ★ 扰动量换成 `ld_cap_points = 0`（而不是 `ld_enabled = false`）。
		#   为什么：`ld_enabled` 只管**眼位要点/做活**（`_eye_vital_bonus` 等），
		#   **不关**死形求解 —— `ai_engine.gd` 里 `m > ld_cap_points → return 2` 与
		#   `_ldm_search` 的死形判定都在 `ld_enabled` 之外 ⇒ 关它对 ① 死形**无影响**
		#   ⇒ 实测「关掉后仍 2/2 全对」。**扰动根本作用不到被测路径**（同 10-05 那次
		#   「阳性对照扰动太弱」是一类病：扰动与被测路径不相交）。
		#   `ld_cap_points=0` 让 `m > ld_cap_points` 恒真 ⇒ 所有封闭眼形一律判活(2)
		#   ⇒ ① 必须开始失手 ⇒ 这才是有牙齿的阳性对照。
		ai_engine.ld_cap_points = 0
		_lay_eye_shape_with_libs(cs["pts"], base, Stone.WHITE, Stone.BLACK, 0)
		var a := ai_engine.analyze_board(board, ko_point)
		if _dominant_tag(a, Stone.WHITE) == "DEAD":
			pos_still_ok += 1
		ai_engine.ld_cap_points = 7# 复位（默认值，见 ai_engine.gd:257）
	var pos_total := dead_shapes.size() - skipped_leaky.size()
	# ★ 样本不足 ⇒ **不适用**（不红）。理由见补丁头：真源 st=0 只有直二/方四，
	#   方四漏气被豁免 ⇒ 只剩 1 个气密死形，且直二仅 2 点、关掉求解器也照样判死
	#   ⇒「仍全对」在这 1 个样本上必然发生，测不出任何东西。
	#   报成「恒真」会把「样本不足」误报成「判据失效」（铁律 37）。
	if pos_total >= 2 and pos_still_ok == pos_total:
		fail_pos.append("ld_cap_points=0 后 ① 仍全对（%d/%d）⇒ ① 可能是恒真" % [pos_still_ok, pos_total])
	if pos_total <= 1:
		#★ 阳性对照**样本不足**而非「无牙齿」：真源里 st=0 的死形只有直二(2点)与
		#   方四(4点)，而方四在 5×5 夹具上漏气被豁免⇒ 只剩 1 个气密死形，
		#   而直二仅 2 点、`_ld_region` 太小，关掉求解器也能判死 ⇒ 测不出差异。
		#   **不伪装成「无牙齿」**（那会把「样本不足」误报成「判据失效」，铁律 37）。
		print("[analyzetest] ③ 阳性对照：**样本不足，不适用**（气密死形仅 %d 个，"
				% pos_total)
		print("     且直二仅 2 点 ⇒ 关掉死活求解器也能判死 ⇒ 本盘型下无法构造有效阳性对照")
	else:
		print("[analyzetest] ③ 阳性对照：把 ld_cap_points 调0（死形求解短路）后 ① 仍判对的 %d/%d ⇒ %s"
				% [pos_still_ok, pos_total,
				   "★有牙齿（① 真在测死活）✓" if pos_still_ok < pos_total else "★无牙齿"])

	# ---------- ④ 阴性对照：活形不许同时被判 DEAD ----------
	# 这是 ① 的反向对照：若某形既进 fail_dead 又进 fail_live，说明分类器在乱输出。
	for nm: String in fail_live:
		if nm.ends_with("→DEAD"):
			fail_neg.append(nm)
	if fail_dead.size() > 0 and fail_live.size() > 0:
		var both: Array = []
		for x: String in fail_dead:
			for y: String in fail_live:
				if String(x).split("→")[0] == String(y).split("→")[0]:
					both.append(x)
		fail_neg.append_array(both)
	print("[analyzetest] ④ 阴性对照：无「同形既判活又判死」⇒ %s"
			% ("✓" if fail_neg.is_empty() else "✗ %s" % str(fail_neg)))

	# ---------- ⑤ 只读纪律 ----------
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	ai_engine.ld_enabled = true
	var snap_before := board.duplicate()
	var ld_before := ai_engine._ld_n
	ai_engine.analyze_board(board, ko_point)
	ai_engine.analyze_board(board, ko_point)          # 连调两次：第二次若读到上次的模型就会不一致
	var same := board.size() == snap_before.size()
	if same:
		for i in board.size():
			if int(board[i]) != int(snap_before[i]):
				same = false
				break
	if not same:
		fail_ro.append("analyze_board 改了棋盘")
	if int(ai_engine._ld_n) != 0:
		fail_ro.append("_ld_n 未复位（%d ≠ 0）⇒ 会污染随后搜索" % int(ai_engine._ld_n))
	print("[analyzetest] ⑤ 只读：棋盘逐位一致=%s | _ld_n %d→%d（须 0）%s"
			% ["是" if same else "否★", ld_before, int(ai_engine._ld_n),
			   "" if fail_ro.is_empty() else " ✗ %s" % str(fail_ro)])

	# ---------- ⑥ 严格单调（严格增，不是非递减）----------
	#铁律 35：非递减在恒等序列上是恒真判据 ⇒ 必须用严格形式。
	var wb_list: Array = []
	var bp_list: Array = []      # 无界量：只作**观察**（评估哲学，可能为负）
	var bs_list: Array = []      # ★ 判据真正的量：黑块子数之和（纯计数）
	# ★ 单调可证的构造：先在 (2,2) 与 (2,3) 摆一个**已成形的黑块**（直二 = 死形，
	#   但它子数确定），然后每次往**同一条边上**加子 ⇒ 该块子数单调 +1
	#   ⇒ black_points 必然严格增。
	#   ⚠️ 旧构造用 `_first_empty()`（索引最小空点）⇒ 落点随机挨着白墙，
	#     后几手变成「往白活形里填」或自己被提 ⇒ 实测 [0,15,16,16,11] 非单调。
	#     **非单调的构造配严格单调判据 = 永远红**（判据与构造必须自洽）。
	# 只加到 3：加到 4 时会自填己方眼位 ⇒ 目数**下降**。
	# ★ 那是真实棋理现象（AI 不该往自己活形里填），属areatest 的口径，
	#   不是「胜率公式对不对」⇒ 本判据不覆盖它（覆盖它= 量错东西，铁律 13）。
	for extra in [0, 1, 2]:
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.BLACK)
		ai_engine.ld_enabled = true
		# ★★★ 夹具构造**直接写 board[]**，不走 `place_stone()`。
		#   `place_stone()` 会推进 `current_player`（落子→提子→换手），
		#   连下三次 = 黑1 白1 黑1 ⇒ 黑只有 2 子，实测「黑块子数之和 [1,1,1]」。
		#   同类夹具（`_lay_eye_shape` / `_lay_eye_shape_with_libs`）也是直接写 board
		#   ⇒ 同一类构造用同一手法（铁律 18）。
		# 布局：y=2 行从 x=2 起连成一线，加子向右延伸 ⇒ 主体块恒为「一条直线」。
		for gi in 3:
			board[2 * TEST_GRID_N + 2 + gi] = Stone.BLACK
		for gi in extra:
			board[2 * TEST_GRID_N + 5 + gi] = Stone.BLACK
		var a6 := ai_engine.analyze_board(board, ko_point)
		wb_list.append(float(a6["win_black"]))
		bp_list.append(float(a6["black_points"]))
		# ★ 判据用的量：黑块 stones 之和（纯计数，无评估项、无对方干扰）
		var bs := 0.0
		for t: Dictionary in (a6["blocks_black"] as Array):
			bs += float(t.get("stones", 0))
		bs_list.append(bs)
	var mono_ok := true
	# ★★ 严格单调判在**无界**量 `black_points` 上，不能判 win_rate（铁律 14）。
	#   `win_rate ∈ [0,1]` 有界 ⇒ 「严格递增」在边界处不可满足（实测第二手就顶到 1.0），
	#   在它上面判单调 = 判一条永远红的废判据。win_rate 只作**读数**打印。
	for i in range(bs_list.size() - 1):
		if not (bs_list[i + 1] > bs_list[i]):
			mono_ok = false
			fail_mono.append("加 %d→%d 子：黑块子数之和 %.0f→%.0f 非严格增"
					% [i, i + 1, bs_list[i], bs_list[i + 1]])
	# komi 单调：贴目给白 ⇒ komi↑ ⇒ win_white↑
	var ww_list: Array = []
	var wp_list: Array = []      # ★ 无界量
	for k in [0.0, 4.0, 8.0, 16.0]:
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.BLACK)
		ai_engine.komi = k
		ww_list.append(float(ai_engine.analyze_board(board, ko_point)["win_white"]))
		wp_list.append(float(ai_engine.analyze_board(board, ko_point)["white_points"]))
	for i in range(wp_list.size() - 1):
		if not (wp_list[i + 1] > wp_list[i]):
			mono_ok = false
			fail_mono.append("komi %.1f→%.1f：white_points %.1f→%.1f 非严格增"
					% [[0.0, 4.0, 8.0, 16.0][i], [0.0, 4.0, 8.0, 16.0][i + 1],
					   wp_list[i], wp_list[i + 1]])
	ai_engine.komi = 0.0
	print("[analyzetest] ⑥ 严格单调（判在**黑块子数之和**上；points/win_rate 只作读数）")
	print("[analyzetest]   同一黑块上再加 0/1/2 子 ⇒ **黑块子数之和 %s（判据量）**" % str(bs_list))
	print("[analyzetest]   观察（不作闸门）：black_points %s" % str(bp_list))
	print("[analyzetest]     ↑ 它含活/死扣分与 area（双方面积差）⇒ 可为负，那是 score_true_live 的设计后果")
	print("[analyzetest]   komi 0/4/8/16 ⇒ white_points %s（贴目只加白侧 ⇒ 严格增）" % str(wp_list))
	print("[analyzetest]   读数（有界，不作闸门）：win_black %s ｜ win_white %s"
			% [str(wb_list), str(ww_list)])
	print("[analyzetest]   ⇒ %s" % ("✓" if mono_ok else "✗"))

	# ---------- ⑧ ★ 分区互斥 + 完备（防「漏网之块」）----------
	# 用户报的病正是「有块该救没救」⇒ **漏掉任何一块都会让局势判断失效**。
	# 这条可证伪：把任一块的 tag 改成非法值必红；删掉任一块则 stones 总数对不上必红。
	var LEGAL := ["LIVE", "UNSETTLED", "DEAD", "SEALED_TERRITORY"]
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	ai_engine.ld_enabled = true
	_lay_eye_shape_with_libs(_ld_shape_table()[0]["pts"], base, Stone.WHITE, Stone.BLACK, 0)
	var a8 := ai_engine.analyze_board(board, ko_point)
	var tag_bad: Array = []
	var sum_w := 0
	for t: Dictionary in (a8["blocks_white"] as Array):
		if not (LEGAL as Array).has(String(t.get("tag", "?"))):
			tag_bad.append(String(t.get("tag", "?")))
		sum_w += int(t.get("stones", 0))
	# ★ 精确核账：不只比总数，还要**指出哪个坐标没被任何块覆盖** ——
	#   「5≠10」看不出是引擎漏块、还是这块本来就不该计入（口径问题）。
	#   用 seen 覆盖法：把每块代表点标记，再逐格核。
	var cover := {}
	for t: Dictionary in (a8["blocks_white"] as Array):
		# 代表点所在块的子集 = 沿邻接走得到的同色连通域
		var rep := int(t.get("rep", -1))
		if rep < 0 or rep >= board.size():
			continue
		var stack: Array[int] = [rep]
		cover[rep] = true
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			for nb: int in adjacency[cur]:
				if int(board[nb]) == int(Stone.WHITE) and not cover.has(nb):
					cover[nb] = true
					stack.append(nb)
	var real_w := 0
	var uncovered: Array = []
	for i in board.size():
		if int(board[i]) == int(Stone.WHITE):
			real_w += 1
			if not cover.has(i):
				uncovered.append(i)
	if not tag_bad.is_empty():
		fail_mono.append("非法 tag：%s" % str(tag_bad))
	if sum_w != real_w:
		# ★ 差值 + 两边明细：若真是引擎漏块，差值能直接指出漏了几个
		#   （原来只报「5≠10」，看不出是漏块还是数错口径）。
		var detail: Array = []
		for t: Dictionary in (a8["blocks_white"] as Array):
			detail.append("%s(st=%d,li=%d)" % [String(t.get("tag", "?")),
					int(t.get("stones", 0)), int(t.get("libs", 0))])
		fail_mono.append("白块子数 %d ≠ 盘面白子 %d（差 %d）；未覆盖坐标 %s；块明细 %s"
				% [sum_w, real_w, real_w - sum_w, str(uncovered), str(detail)])
	print("[analyzetest] ⑧ 互斥+完备：tag 全合法=%s ｜ 白块子数 %d = 盘面 %d ⇒ %s"
			% ["是" if tag_bad.is_empty() else "否★", sum_w, real_w,
			   "✓" if sum_w == real_w and tag_bad.is_empty() else "✗"])

	# ---------- ⑨ ★ 块清单完备：**同尺寸的两块棋不许合并** ----------
	# 起因（2026-10-08 重读源码发现）：`analyze_board()` 的逐块去重键取的是 `_group()`
	# 的**返回值** —— 那是**成员计数**，不是块身份：
	#     `var g := _group(v) ... if seen.has(g): continue`
	# ⇒ 凡尺寸相同的两块棋被当成同一块，**第二块起整体丢弃**。
	# 实测（`--anlzmis`，19×19 / 120 手档）：独立枚举 16 块·360 子 vs 清单 13 块·313 子
	# ⇒ **丢 3 块、丢 47 子**。
	# ⑧ 号判据本来就在查「子数对得上」，但它只用了**一个**白块夹具 ⇒ 形不成尺寸碰撞
	# ⇒ **修 bug 前就是绿的**（铁律 4：绿 ≠ 有牙齿，是夹具没覆盖到）。
	# 本判据专造碰撞：白 4 块（尺寸 3/3/1/1）、黑 2 块（尺寸 2/2）。
	# 期望值一律**从夹具推导**（铁律 39：不许手写数字）。
	var fail_blk: Array = []
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	ai_engine.ld_enabled = true
	var pat9: Array = [
		[1, 1, Stone.WHITE], [1, 2, Stone.WHITE], [1, 3, Stone.WHITE],
		[8, 8, Stone.WHITE], [8, 9, Stone.WHITE], [8, 10, Stone.WHITE],
		[15, 15, Stone.WHITE], [3, 15, Stone.WHITE],
		[5, 5, Stone.BLACK], [5, 6, Stone.BLACK],
		[12, 12, Stone.BLACK], [12, 13, Stone.BLACK],
	]
	var exp_w9 := 0
	var exp_b9 := 0
	for pp: Array in pat9:
		board[int(pp[0]) * TEST_GRID_N + int(pp[1])] = pp[2]
		if int(pp[2]) == int(Stone.WHITE):
			exp_w9 += 1
		else:
			exp_b9 += 1
	var a9 := ai_engine.analyze_board(board, ko_point)
	var w9 := 0
	var b9 := 0
	for t: Dictionary in (a9["blocks_white"] as Array):
		w9 += int(t.get("stones", 0))
	for t: Dictionary in (a9["blocks_black"] as Array):
		b9 += int(t.get("stones", 0))
	var nw9 := (a9["blocks_white"] as Array).size()
	var nb9 := (a9["blocks_black"] as Array).size()
	if w9 != exp_w9:
		fail_blk.append("⑨ 同尺寸碰撞夹具：白块子数 %d ≠ 盘面 %d（丢 %d 子）" % [w9, exp_w9, exp_w9 - w9])
	if b9 != exp_b9:
		fail_blk.append("⑨ 同尺寸碰撞夹具：黑块子数 %d ≠ 盘面 %d（丢 %d 子）" % [b9, exp_b9, exp_b9 - b9])
	if nw9 != 4:
		fail_blk.append("⑨ 同尺寸碰撞夹具：白块数 %d ≠ 4（同尺寸块被合并）" % nw9)
	if nb9 != 2:
		fail_blk.append("⑨ 同尺寸碰撞夹具：黑块数 %d ≠ 2（同尺寸块被合并）" % nb9)
	print("[analyzetest] ⑨ 同尺寸碰撞夹具：白 %d 块/%d 子（期望 4/%d）｜ 黑 %d 块/%d 子（期望 2/%d）⇒ %s"
			% [nw9, w9, exp_w9, nb9, b9, exp_b9, "✓" if fail_blk.is_empty() else "✗"])

	# ---------- ⑩ ★「对方活块就在旁边」必须按**整块**判，不能只看代表点 ----------
	# `_has_live_block_near()` 原文是 `_is_adj(rep, v)` —— `rep` 是该块里**点号最小**的子。
	# 一块棋有几十个子时，v 挨着块尾却离代表点很远 ⇒ 查不到 ⇒ ③ 号机制漏触发。
	# 夹具专造这个错位：黑 4 子 L 形，代表点 (5,5)=100；取样点 v=(7,7)=140 与块尾 (6,7)
	# **相邻**、与代表点**不相邻**。
	# ★ 必须配**阴性对照**（远离该块的 (9,9) 仍须 false）—— 否则「一律返回 true」也能全绿
	#   （铁律 4：对照本身也要有牙齿）。
	var fail_near: Array = []
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	ai_engine.ld_enabled = true
	ai_engine.ai_color = Stone.WHITE          # 「对方」= 黑
	var blk10: Array = [5 * 19 + 5, 5 * 19 + 6, 5 * 19 + 7, 6 * 19 + 7]
	for q: int in blk10:
		board[q] = Stone.BLACK
	var a10 := ai_engine.analyze_board(board, ko_point)
	var v_hit := 7 * 19 + 7                     # 与 (6,7) 相邻、与代表点 (5,5) 不相邻
	var v_far := 9 * 19 + 9                     # 远离该块（阴性对照）
	var near_hit: bool = ai_engine._has_live_block_near(a10, v_hit, Stone.BLACK)
	var near_far: bool = ai_engine._has_live_block_near(a10, v_far, Stone.BLACK)
	ai_engine.ai_color = Stone.WHITE
	if not near_hit:
		fail_near.append("⑩ 活块邻接：v=%d 与块内子相邻却查不到（代表点 %d 与 v 不相邻）"
				% [v_hit, blk10[0]])
	if near_far:
		fail_near.append("⑩ 活块邻接**阴性对照**失手：远离该块的 v=%d 也返回 true ⇒ 判据恒真" % v_far)
	print("[analyzetest] ⑩ 活块邻接（整块口径）：挨着块尾=%s（期望 true）｜ 远离块=%s（期望 false）⇒ %s"
			% [str(near_hit), str(near_far), "✓" if fail_near.is_empty() else "✗"])

	# ---------- ⑦ 音乐接线（★★ 2026-10-07 重写：原版是"判据自己注入被测量"）----------
	# 原版手搓一个含 `an_crisis` 的字典喂给 `Music.battle_tension()` —— 它验的是**映射函数**，
	# 却把自己要验的那段**接线**（生产端到底有没有把这些字段发出去）当成前提自己提供了
	# ⇒ 接线断了它照样绿（本工程铁律 13 的"判据自己注入被测量"）。真发作过：`w_crisis`
	# 声明了、注释写着"危急度"，而 `music.gd` 的 `_read_battle_state()` 从来没发过这个字段。
	# 这一版改走**真路径**：这里的 `current_scene` **就是**对局场景 ⇒ 可以直接问
	# `Music._read_battle_state()` 拿到了什么，并逐项与场景的真实成员对账。
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.BLACK)
	ai_engine.ld_enabled = true
	# ★ 夹具本身是**空盘**（`_test_build_square_grid` 只铺邻接与空格）⇒ 必须先落几子，
	#   否则"三分类 0 块"与"赋值那行被删掉了"在日志里长得一模一样。
	#   （铁律 17：判据与自己喂的数据打架时先怀疑判据 —— 这一次**两边都要改**：
	#     判据得自己造料，而"密度项恒为 1.0"是真的缺陷，见下 ⑦g。）
	board[0] = Stone.BLACK
	board[1] = Stone.WHITE
	board[TEST_GRID_N * TEST_GRID_N - 1] = Stone.WHITE
	_refresh_analyze()
	var st_m: Dictionary = Music._read_battle_state()
	var sit_names: Array = Music.SITUATION_FIELDS
	# ⑦a 生产端必须发布**全部**局势字段（缺一个 ⇒ 音乐那个轴静默退回平静态）
	var miss_f: Array = []
	for f in sit_names:
		if not st_m.has(String(f)):
			miss_f.append(String(f))
	# ⑦b 逐项与**场景真实成员**对账（不是与手搓值对账）
	var mism: Array = []
	for f in sit_names:
		if str(st_m.get(String(f))) != str(get(String(f))):
			mism.append("%s 快照 %s ≠ 成员 %s" % [String(f), str(st_m.get(String(f))), str(get(String(f)))])
	# ⑦c 完整性闸（`has_situation`）必须有**阴性对照**：逐名删掉都必须判"不完整"
	#    —— 否则一个永远返回 true 的闸就能过（恒真式）。
	var nm: Dictionary = {}
	for p in get_property_list():
		nm[str(p["name"])] = true
	var gate_pos: bool = Music._situation_complete(nm)
	var gate_neg := true
	for f in sit_names:
		var nm2 := nm.duplicate()
		nm2.erase(String(f))
		if Music._situation_complete(nm2):
			gate_neg = false
	# ⑦d 三分类非空：夹具上**确实有棋子** ⇒ 已活/可做活/已死 不可能全为 0。
	#    这一条是"赋值被删掉/块统计被改坏"的闸（⑦a/⑦b 都咬不住那种：字段名还在、
	#    快照与成员也一致，只是两边一起恒等于 0）。
	var cls_sum := 0
	for f in ["an_live_blocks", "an_unsettled_blocks", "an_dead_blocks",
			"an_player_live_blocks", "an_player_unsettled_blocks", "an_player_dead_blocks"]:
		cls_sum += int(st_m.get(f, 0))
	# ⑦g 密度项必须**非平凡**：`0 < 已落子数 < 总格数`。
	#    ★ 这一条专治一个真踩过的缺陷：`board_size` 曾经发的是 `board.size()`（= **格数**，
	#    因为 `board` 字典把空格也占一条）⇒ 它**恒等于** `tiles_total` ⇒ 密度项恒为 1.0，
	#    而 `w_density` 看起来还"在工作"（只有一个常量偏置）。实测当时这里就是 `9 = 9`。
	var bsz := int(st_m.get("board_size", 0))
	var tsz := int(st_m.get("tiles_total", 0))
	var dens_ok: bool = bsz > 0 and bsz < tsz
	# ⑦e 生产端**逐项溯源**：六个"直接搬运"的字段必须与 `analyze_board()` 的源字段相等。
	#    ★ 这查的是 `_refresh_analyze()` 里的**搬运**（赋值行），而不是任何公式：
	#    删掉一行 `an_live_blocks = int(an["own_live_blocks"])` ⇒ 成员永远停在初值 0，当场红。
	var an_raw := ai_engine.analyze_board(board, ko_point)
	var trace_pairs := [
		["an_live_blocks", "own_live_blocks"], ["an_unsettled_blocks", "own_unsettled_blocks"],
		["an_dead_blocks", "own_dead_blocks"], ["an_player_live_blocks", "their_live_blocks"],
		["an_player_unsettled_blocks", "their_unsettled_blocks"],
		["an_player_dead_blocks", "their_dead_blocks"],
	]
	var trace_bad: Array = []
	for pr in trace_pairs:
		if int(get(String(pr[0]))) != int(an_raw.get(String(pr[1]), -999)):
			trace_bad.append("%s=%d ≠ %s=%d" % [String(pr[0]), int(get(String(pr[0]))),
					String(pr[1]), int(an_raw.get(String(pr[1]), -999))])
	# ⑦f 四轴：从**真局面**出发，单信号扰动只许动它自己那一轴（"从不同方面读取局势"）
	#    —— 与 music 自检的 ⑲ 同一件事，但基数是**这一局真的算出来的数**。
	var ax_b: Dictionary = Music.axes_from_state(st_m)
	var cross_bad: Array = []
	var perts := [
		["an_crisis", "loud", 1.0 if float(st_m.get("an_crisis", 0.0)) < 0.5 else 0.0],
		["an_player_diff", "pitch", -1.0 * Music.point_ref
			if float(st_m.get("an_player_diff", 0.0)) >= 0.0 else Music.point_ref],
	]
	for pr in perts:
		var st_p: Dictionary = st_m.duplicate()
		st_p[String(pr[0])] = float(pr[2])
		var ax_p: Dictionary = Music.axes_from_state(st_p)
		var moved: Array = []
		for kk in ["loud", "tempo", "pitch", "hue"]:
			if absf(float(ax_b.get(kk, 0.0)) - float(ax_p.get(kk, 0.0))) > 1e-9:
				moved.append(String(kk))
		if str(moved) != str([String(pr[1])]):
			cross_bad.append("%s ⇒ 动了 %s（期望只动 %s）" % [String(pr[0]), str(moved), String(pr[1])])
	# —— 汇总 ——
	if not miss_f.is_empty():
		fail_music.append("局势字段缺席 %s ⇒ 音乐对应轴会静默退回平静态" % str(miss_f))
	if not mism.is_empty():
		fail_music.append("音乐快照与真实成员不一致 %s" % str(mism.slice(0, 4)))
	if not (gate_pos and gate_neg):
		fail_music.append("完整性闸阳性=%s 阴性=%s ⇒ 这条闸没牙齿（缺字段也不会退回退化档）"
				% [str(gate_pos), str(gate_neg)])
	if cls_sum <= 0:
		fail_music.append("三分类块数之和=0，而夹具上是有棋子的 ⇒ 赋值/块统计坏了")
	if not dens_ok:
		fail_music.append("密度项非平凡失败：已落子 %d / 总格 %d（必须 0<落子<总格；相等 ⇒ 发的是格数）"
				% [bsz, tsz])
	if not trace_bad.is_empty():
		fail_music.append("生产端搬运不符 %s" % str(trace_bad))
	if not cross_bad.is_empty():
		fail_music.append("四轴交叉污染 %s" % str(cross_bad))
	var music_ok: bool = (miss_f.is_empty() and mism.is_empty() and gate_pos and gate_neg
			and cls_sum > 0 and dens_ok and trace_bad.is_empty() and cross_bad.is_empty())
	print("[analyzetest] ⑦ 音乐接线：局势字段 %d 个（缺 %d）· 成员对账不符 %d · 完整性闸 阳性=%s 阴性=%s"
			% [sit_names.size(), miss_f.size(), mism.size(), str(gate_pos), str(gate_neg)])
	print("[analyzetest] ⑦ 音乐接线：三分类 %d 块 · 密度 %d/%d 格 · 溯源不符 %d 项 · 交叉污染 %d 项 ⇒ %s"
			% [cls_sum, bsz, tsz, trace_bad.size(), cross_bad.size(), "✓" if music_ok else "✗"])
	print("[analyzetest] ⑦ 四轴（真局面）：危险度 %.3f ⇒ 响度 ×%.2f ｜ 进程 %.3f ⇒ 节奏 stride=%d ｜"
			% [float(ax_b.get("loud", 0.0)), float(ax_b.get("gain_scale", 1.0)),
			   float(ax_b.get("tempo", 0.0)), int(ax_b.get("stride", 1))])
	print("[analyzetest] ⑦ 四轴（真局面）：目数差 %.1f ⇒ 音高偏移 %d 度 ｜ 形态度 %.3f ⇒ 色彩 hue=%.3f"
			% [float(ax_b.get("pdiff", 0.0)), int(ax_b.get("pitch_deg", 0)),
			   float(ax_b.get("form", 0.0)), float(ax_b.get("hue", 0.0))])

	# ---------- 汇总 ----------
	var all_fail := (fail_dead + fail_live + fail_pos + fail_neg + fail_ro
			+ fail_mono + fail_music + fail_blk + fail_near)
	print("[analyzetest] 判据 10 段，失败 %d 项" % all_fail.size())
	# ★★ 必须逐条打印失败详情（铁律 12）：只打总数时，
	#   「失败 3 项」和「失败了但看不出为什么」在日志里长得一模一样。
	for f: String in all_fail:
		print("[analyzetest]   ✗ %s" % f)
	print("[analyzetest] 结论：%s" % ("通过 ✓" if all_fail.is_empty() else "失败 ✗"))
	get_tree().quit(0 if all_fail.is_empty() else 1)

## ---------------------------------------------------------------------------
## 自检（--anlzdir）`w_sealed_territory` 的**方向判据**。
##
## 要回答的问题（用户原话「AI 明明落后却宁愿在对方地盘继续落子」）：
##   这个惩罚**真的**把 AI 从「已被对方围死、攻不进去」的空区里推出来了吗？
##
## 为什么不 A/B 对打：检出 2.5pp 的胜率差需约 **12548 局**（铁律 24 的功效分析），
##   本会话跑不完；而「方向」不需要胜率统计，**配对**量就够 —— 同一局面、同一 RNG 状态、
##   只改一个权重，看选点有没有挪出来。这是机制层判据，**不等于**棋力结论（不许混说）。
##
## 配对纪律（缺了它测的是随机数不是权重）：`choose_move()` 每次调用都消耗 rng 流，
##   所以**每次调用前**都 `setup(..., sd)` 把种子复位。盘面 / 盘型 / pw / 颜色全固定。
##
## 三档（缺第三档时，前两档相同就分不清「机制无效」与「压根没触发」）：
##   OFF = 0 ｜ ON = -6（现状）｜ FLIP = +6（**阳性对照**：反号应把 AI 推向里面去）
## 期望：落进对方围死地的**计数**满足 FLIP ≥ OFF ≥ ON，且至少一处**严格**不等。
##   三轮全相等 ⇒ 报「在该档位上测不出效果」，并附「有多少局面根本没有 ③ 候选」
##   这个分母 —— 否则「无效果」与「没触发」在日志里长得一样（铁律 37）。
func _anlz_dir() -> void:
	var n_games := 4
	var cps: Array[int] = [70, 85, 100, 112]
	var pw := 24
	var bn := 11
	var side: int = int(Stone.BLACK)
	var n_pos := n_games * cps.size()
	print("[anlzdir] ===== w_sealed_territory 方向判据（**确定性**口径：分数 / 前K / 先验，不用 choose_move）=====")
	print("[anlzdir] 盘 %d×%d=%d 格（≈真实盘 120 格）｜%d 局 × 采样点 %s 手（pw=%d，造样本期关层）｜局面 %d 个"
			% [bn, bn, bn * bn, n_games, str(cps), pw, n_pos])
	print("[anlzdir] ★ 不用 choose_move 的原因：多线程搜索的合并依赖墙钟 ⇒ 同档同种子两次跑会飘")
	print("[anlzdir]   （引擎注释已写明；实测同一档 P16 两次跑得 手[49/49/49] 与 手[10/10/47]）")
	print("[anlzdir] 三档：OFF=0.0 ｜ ON=-6.0（现状）｜ FLIP=+6.0（阳性对照）")
	var ws: Array[float] = [0.0, -6.0, 6.0]
	var n_sens_pos := 0
	var sum_m := 0
	var sum_judge := 0
	var sum_mis := 0
	var aff_bad := 0
	var mono_eff := 0          # **有效分母**：③ 真触发 且 先验非全 0 的局面
	var mono_ok := 0
	var mono_strict := 0
	var mono_trivial := 0      # 三档先验全 0 ⇒ 0≥0≥0 恒真，不算证据
	var gate_pos := 0
	var champ_diff := 0
	var rep_bad := 0
	var rep_n := 0
	# 空区级：边界颜色构成直方图（6 桶）——回答"用户口中的『对方地盘』与引擎定义差多远"
	#   0 = 一颗子都没碰（开阔）｜1 = 对方占比 <0.25｜2 = 0.25~0.5｜3 = 0.5~0.75
	#   4 = 0.75~1（对方占多数但混有色）｜5 = **全是对方**（= 引擎 ③ 的第一条件）
	var hb_reg: Array[int] = [0, 0, 0, 0, 0, 0]      # 该桶的空区个数
	var hb_pts: Array[int] = [0, 0, 0, 0, 0, 0]      # 该桶的空点总数
	var hb_ink: Array[int] = [0, 0, 0, 0, 0, 0]      # 该桶里**进得了前K**的点数（竞争性）
	var hb_best: Array[int] = [0, 0, 0, 0, 0, 0]     # 该桶最竞争的那个点的名次（0 = 不在 el 里）
	var rows: Array = []
	var pi := 0
	for gi in n_games:
		var sd := 20261008 + gi
		reset_game(true)
		_test_build_square_grid(bn)
		ai_engine.setup(adjacency, side, sd)
		ai_engine.ld_enabled = true
		ai_engine.max_playouts = pw
		ai_engine.playout_cap_factor = 0.5
		ai_engine.use_analyze_bonus = false       # 造样本期关层（被测量不参与造样本）
		var played := 0
		for cp: int in cps:
			while played < cp:
				ai_engine._turn = int(Stone.BLACK) if (played % 2 == 0) else int(Stone.WHITE)
				ai_engine.ai_color = ai_engine._turn
				ai_engine._ko = -1
				var mvp := ai_engine.choose_move(board, -1)
				if mvp < 0 or int(board[mvp]) != int(Stone.EMPTY):
					break
				board[mvp] = ai_engine._turn
				played += 1
			pi += 1
			ai_engine.ai_color = side
			ai_engine.load_board_for_probe(board)
			ai_engine._turn = side
			ai_engine._ko = -1
			ai_engine.analyze_max_blocks = 2000
			var an := ai_engine.analyze_board()
			var tag_of: Dictionary = an.get("tag_of", {})
			# —— 确定性口径：与 `_prepare_root` **同一个过滤器**取候选全集（剪枝之前）——
			var opp_last := ai_engine._infer_opp_move()
			ai_engine.use_analyze_bonus = true
			ai_engine._sc_id += 1
			var el: Array[int] = []
			for v2 in board.size():
				if int(board[v2]) != int(Stone.EMPTY):
					continue
				if ai_engine._own_territory_only(v2):
					continue
				el.append(v2)
			var n_all := el.size()
			var kw := ai_engine._effective_root_width(n_all)
			var is_seal: Array[bool] = []
			for v2 in el:
				is_seal.append(_anlz_dir_sealed(an, v2, side))
			var fulls: Array = []
			var i_in: Array[int] = []
			var p_seal: Array[float] = []
			var champ_is: Array[int] = []
			var champ_mv: Array[int] = []
			for wi in ws.size():
				var ri := _anlz_dir_priors(board, el, ws[wi], side, opp_last, kw)
				fulls.append(ri["full_scores"])
				var kc: Array = ri["cands"]
				var pr: Array = ri["priors"]
				var cnt := 0
				var psum := 0.0
				for i in kc.size():
					if _anlz_dir_sealed(an, int(kc[i]), side):
						cnt += 1
						psum += float(pr[i])
				i_in.append(cnt)
				p_seal.append(psum)
				var cm := 0
				var cmv := -1
				if kc.size() > 0:
					var bi := 0
					for i in kc.size():
						if float(pr[i]) > float(pr[bi]):
							bi = i
					cmv = int(kc[bi])
					if _anlz_dir_sealed(an, cmv, side):
						cm = 1
				champ_is.append(cm)
				champ_mv.append(cmv)
			# —— 空区级：边界颜色构成（用去重字典数**每颗边界子**，不是数边）——
			var elidx: Dictionary = {}
			for i4 in n_all:
				elidx[el[i4]] = i4
			var rvis: Dictionary = {}
			for v1 in board.size():
				if int(board[v1]) != int(Stone.EMPTY) or rvis.has(v1):
					continue
				var q: Array[int] = [v1]
				rvis[v1] = true
				var qi := 0
				var szreg := 0
				var bseen: Dictionary = {}
				var nb_b := 0
				var nb_w := 0
				var best_rk := 0
				var ink := 0
				while qi < q.size():
					var cur: int = q[qi]
					qi += 1
					szreg += 1
					if elidx.has(cur):
						var ii: int = int(elidx[cur])
						var rr := 1
						for j4 in n_all:
							if float(fulls[0][j4]) > float(fulls[0][ii]):
								rr += 1
						if best_rk == 0 or rr < best_rk:
							best_rk = rr
						if rr <= kw:
							ink += 1
					var k1 := ai_engine._as[cur]
					var ke1 := ai_engine._as[cur + 1]
					while k1 < ke1:
						var nb1 := ai_engine._af[k1]
						k1 += 1
						var cc1 := int(ai_engine._b[nb1])
						if cc1 == int(Stone.EMPTY):
							if not rvis.has(nb1):
								rvis[nb1] = true
								q.append(nb1)
						elif not bseen.has(nb1):
							bseen[nb1] = true
							if cc1 == int(Stone.BLACK):
								nb_b += 1
							else:
								nb_w += 1
				var tbt := nb_b + nb_w
				var bi := 0
				if tbt > 0:
					var fo := (float(nb_w) / float(tbt)) if side == int(Stone.BLACK) else (float(nb_b) / float(tbt))
					if fo >= 0.999:
						bi = 5
					elif fo >= 0.75:
						bi = 4
					elif fo >= 0.5:
						bi = 3
					elif fo >= 0.25:
						bi = 2
					else:
						bi = 1
				hb_reg[bi] += 1
				hb_pts[bi] += szreg
				hb_ink[bi] += ink
				if best_rk > 0 and (hb_best[bi] == 0 or best_rk < hb_best[bi]):
					hb_best[bi] = best_rk
			# 敏感性 + 跨实现对拍：分数差值口径(M) 必须等于 探针分类口径(判)
			var a0: Array = fulls[0]
			var aF: Array = fulls[2]
			var m_sens := 0
			var dmax := 0.0
			for i in a0.size():
				var dd := absf(float(aF[i]) - float(a0[i]))
				if dd > 1.0e-9:
					m_sens += 1
					if dd > dmax:
						dmax = dd
			var n_judge := 0
			for b in is_seal:
				if b:
					n_judge += 1
			if m_sens != n_judge:
				sum_mis += 1
			if m_sens > 0:
				n_sens_pos += 1
			sum_m += m_sens
			sum_judge += n_judge
			if m_sens > 0 and absf(dmax - 6.0) > 1.0e-6:
				aff_bad += 1
			# 排名：③ 目标在 el 里按分数排第几（1 = 冠军）
			var rk0 := 0
			var rk6 := 0
			for i in n_all:
				if not is_seal[i]:
					continue
				var r0 := 1
				var r6 := 1
				for j in n_all:
					if float(fulls[0][j]) > float(fulls[0][i]):
						r0 += 1
					if float(fulls[2][j]) > float(fulls[2][i]):
						r6 += 1
				if rk0 == 0 or r0 < rk0:
					rk0 = r0
				if rk6 == 0 or r6 < rk6:
					rk6 = r6
			# 单调性（先验和）—— 只对**非全 0**的局面算有效分母
			var triv := (p_seal[0] == 0.0 and p_seal[1] == 0.0 and p_seal[2] == 0.0)
			if triv:
				mono_trivial += 1
			elif m_sens > 0:
				mono_eff += 1
				if p_seal[2] >= p_seal[0] and p_seal[0] >= p_seal[1]:
					mono_ok += 1
					if p_seal[2] > p_seal[1]:
						mono_strict += 1
			if m_sens > 0 and i_in[2] > i_in[1]:
				gate_pos += 1
			if champ_mv[2] != champ_mv[1]:
				champ_diff += 1
			# 复现性自测（前 4 个局面）：同档同种子连调 3 次
			var rep_note := ""
			if pi <= 4:
				var got: Array[int] = []
				for r3 in 3:
					ai_engine.setup(adjacency, side, sd)
					ai_engine.ld_enabled = true
					ai_engine.max_playouts = pw
					ai_engine.playout_cap_factor = 0.5
					ai_engine.use_analyze_bonus = true
					ai_engine.w_sealed_territory = -6.0
					ai_engine.ai_color = side
					ai_engine._turn = side
					ai_engine._ko = -1
					got.append(ai_engine.choose_move(board, -1))
				rep_n += 1
				var same := (got[0] == got[1] and got[1] == got[2])
				if not same:
					rep_bad += 1
				rep_note = " ｜ 复现[%d/%d/%d]%s" % [got[0], got[1], got[2],
					"" if same else " ✗不一致"]
			ai_engine.w_sealed_territory = -6.0
			rows.append("D%02d el=%3d K=%2d M=%2d 判=%2d Δ=%4.2f rk0=%3d rk6=%3d ｜ 内K %d→%d→%d ｜ P③ %.6f→%.6f→%.6f ｜ 冠 %d/%d/%d%s"
					% [pi, n_all, kw, m_sens, n_judge, dmax, rk0, rk6,
					i_in[0], i_in[1], i_in[2],
					p_seal[0], p_seal[1], p_seal[2],
					champ_is[0], champ_is[1], champ_is[2], rep_note])
	ai_engine.use_analyze_bonus = true
	ai_engine.analyze_max_blocks = 400
	for r: String in rows:
		print("[anlzdir]   %s" % r)
	print("[anlzdir] 汇总：③ 真触发 %d 次 / %d 个局面（探针分类口径 %d 次；两者不等 = **口径分岔**，%d 个局面）"
			% [sum_m, n_sens_pos, sum_judge, sum_mis])
	var hb_name: Array = ["0 开阔(一颗子都没碰)", "1 对方占比<0.25 (己方地盘)",
		"2 0.25~0.5", "3 0.5~0.75", "4 0.75~1 (对方占多数但混有色)", "5 全是对方 (= 引擎③第一条件)"]
	for bi in 6:
		print("[anlzdir] 空区桶 %s：区 %3d ｜ 空点 %4d ｜ 进前K %3d ｜ 该桶最竞争名次 %d"
				% [hb_name[bi], hb_reg[bi], hb_pts[bi], hb_ink[bi], hb_best[bi]])
	print("[anlzdir]   ⇒ 看桶 4/5：**对方占多数的空区**里有多少点真进得了前K。")
	print("[anlzdir]     · 进前K 的点若全在桶 0~3 ⇒ 引擎本来就不往对方地盘下，用户看到的是别的东西；")
	print("[anlzdir]     · 桶 4 若有点进前K ⇒ 缺的是把【多数即算地盘】写进判据，而不是调 ③ 的权重。")
	print("[anlzdir] 仿射检查：Δmax 应恰好 = 6.00，不符的局面 %d" % aff_bad)
	print("[anlzdir] 方向（先验和 FLIP≥OFF≥ON）：**有效分母** %d 个局面里成立 %d（严格 %d）｜" % [mono_eff, mono_ok, mono_strict])
	print("[anlzdir]   另 %d 个局面三档先验**全 0** ⇒ 0≥0≥0 是恒真式，**不计入证据**" % mono_trivial)
	print("[anlzdir] 闸门：③ 目标「+6 进前K 而 −6 不进」的局面 %d / %d ｜ 先验冠军变过的 %d / %d"
			% [gate_pos, n_pos, champ_diff, n_pos])
	print("[anlzdir] 复现性自测：同档同种子连调 3 次 choose_move，不完全一致的 %d / %d"
			% [rep_bad, rep_n])
	if sum_m == 0:
		print("[anlzdir] ⇒ **机制没触发**：③ 一个点都没生效 ⇒ 缺陷，不是尺度问题。")
	elif sum_mis > 0:
		print("[anlzdir] ⇒ **口径分岔**：分数差值口径与探针分类口径对不上 %d 个局面 ⇒ 先修仪器，别读结论。" % sum_mis)
	elif gate_pos == 0 and champ_diff == 0:
		print("[anlzdir] ⇒ **权重这条路不通**：③ 触发了 %d 次，但 ±6 既改不了前K成员、也改不了先验冠军" % sum_m)
		print("[anlzdir]    ⇒ 该改成**硬过滤**（照 `_own_territory_only()` 的样子在打分前剔除），不要再调权重。")
	else:
		print("[anlzdir] ⇒ ✓ 接线成立：权重能改前K成员 %d 个局面、先验冠军 %d 个局面。" % [gate_pos, champ_diff])
		print("[anlzdir]    阈值是否该调要另跑 A/B（本判据不含棋力结论）。")
	print("[anlzdir] ⚠️ 本判据只说**机制方向**，**不是**棋力结论（胜率差需约 12548 局，见铁律 24）。")
	get_tree().quit(0)


## 复刻 `_prepare_root` 的「打分 → top-K → softmax 先验」三步，**纯函数**（无 rng/线程/墙钟）。
## 返回 {cands, priors, scores, full_scores}；`full_scores` 是剪枝前 el 上的分数（敏感性要用）。
func _anlz_dir_priors(bd: Dictionary, el: Array[int], wv: float, side_c: int, opp_last: int,
		kw: int) -> Dictionary:
	ai_engine.w_sealed_territory = wv
	var full: Array[float] = []
	for v in el:
		ai_engine._sc_id += 1     # `_anlz()` 按 `_sc_id` 缓存，而 probe 走 `_load_board`（不推进）
		full.append(float(ai_engine.probe_root_score_last(bd, v, side_c, opp_last)))
	var pairs: Array = []
	for i in full.size():
		pairs.append([full[i], i])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var kk := mini(kw, full.size())
	var kc: Array[int] = []
	var ks: Array[float] = []
	for i in kk:
		kc.append(el[int(pairs[i][1])])
		ks.append(float(pairs[i][0]))
	var pr: Array[float] = ai_engine._softmax_priors(ks)
	return {"cands": kc, "priors": pr, "scores": ks, "full_scores": full}


## 自检（--scidtest）★ 局面版本号 `_sc_id` 的缓存失效纪律。
##
## 缺陷（2026-10-08 发现，**静默**）：按 `_sc_id` 失效的缓存有两处 ——
##   `_anlz()`（局势分析，`_an_cache`）与 `_own_area_layers()`（`_sc`/`_sv` 领地三态）。
##   推进 `_sc_id` 的只有 `_prepare_root()`（:3241）与 `probe_own_area()`（:2525）；
##   而 `load_board_for_probe()` → `_load_board()` **改了盘面却不推** ⇒
##   任何"换盘后再探分 / 再判领地"的路径都会**静默**拿到**上一局**的结论。
##   受影响的是 `game.gd` 里所有 `probe_root_score*` 调用（含 `--aidata` 的落盘，:3293/:3298）；
##   `choose_move()` 那条路径侥幸没炸：它 `_load_board()` 之后紧跟 `_prepare_root()`，后者会推。
##
## 判据（都落在真走的那两条路径上，不另写一份模型）：
##   A 局势缓存：换盘后 `_anlz()` 必须等于**现算**（`analyze_board()` 无参 = 直接用当前 `_b`）
##   B 领地缓存：换盘后 `_own_territory_only(v)` 必须等于**强制作废后重算**的值
##   阴性对照：同一个盘面连问两次必须**相同**（否则判据自己就不确定）
##   夹具体检：两盘的现算结论必须**不同**（否则判据没有区分力 —— 铁律 4）
func _scid_test() -> void:
	print("[scidtest] ===== `_sc_id` 缓存失效纪律（A 局势缓存 / B 领地缓存）=====")
	var bn := 11
	var fail: Array = []
	reset_game(true)
	_test_build_square_grid(bn)
	var b1 := _scid_fixture(bn, false)
	var b2 := _scid_fixture(bn, true)          # 环内多一颗黑子
	var v := 4 * bn + 4                        # 环内点 (4,4)
	# 视角必须是**白**：`_own_area_layers()` 用 `3 - _turn` 判"对手"、层 A 要求边界全是"己方"
	#   ⇒ 拿黑视角去问白环围出的空区，层 A 必然 false，判据会变成恒真（铁律 4）。
	ai_engine.setup(adjacency, int(Stone.WHITE), 20261008)
	ai_engine.ai_color = int(Stone.WHITE)
	ai_engine.ld_enabled = true
	ai_engine.analyze_max_blocks = 2000
	ai_engine.use_analyze_bonus = true
	# `_stamp_reset()` 把 `_sc_id` 归零且 `_sc.fill(0)` ⇒ `_sc[v] == _sc_id` 对未写过的点**恒真**
	#   ⇒ 领地三态缓存会"假装有效"。先推一格，把这份初值状态排除掉，免得两件事混在一处。（另记）
	ai_engine._sc_id += 1
	# —— 现算参照（不经任何缓存）——
	var fa := _scid_sig_fresh(b1)
	var fb := _scid_sig_fresh(b2)
	var fa2 := _scid_sig_fresh(b1)
	print("[scidtest] 阴性对照（同盘连问两次）：%s"
			% ["相同 ✓" if fa == fa2 else "★不同 ⇒ 判据本身不确定"])
	if fa != fa2:
		fail.append("阴性对照失效：同一盘面两次现算结论不同")
	print("[scidtest] 夹具体检 A：B1=%s ｜ B2=%s ⇒ %s" % [fa, fb,
			"两盘确实不同 ✓" if fa != fb else "★两盘相同 ⇒ 夹具没有区分力"])
	if fa == fb:
		fail.append("夹具没有区分力：B1/B2 的现算分析相同")
	# ★★ 防假绿（2026-10-08 实测踩到）：签名函数曾因 `String()` 构造报错而**返回空串**，
	#   于是"两条空串相等"⇒ 判据 A 印了「正确 ✓」。**判据自己出错必须报错**，
	#   不能让"两边都一样空"冒充证据（铁律 23 的同族）。
	if fa.is_empty() or fb.is_empty():
		fail.append("签名构造失败（返回空串）⇒ 判据自身出错，本段结论无效")
	if fa.contains("|?|") or fb.contains("|?|"):
		fail.append("签名里出现占位符 '?' ⇒ `analyze_board` 字段口径变了，本段结论无效")
	if fb.contains("|B0|"):
		fail.append("B2 明明有黑子，签名却报黑块 0 ⇒ 签名口径不对，本段结论无效")
	# —— 判据 A：局势缓存 ——
	var a1 := _scid_sig_cached(b1)
	var a2 := _scid_sig_cached(b2)             # ★ 换盘（修前：`_load_board` 不推 `_sc_id`）
	var a2f := _scid_an_sig(ai_engine.analyze_board())
	print("[scidtest] A 局势缓存：换盘后缓存=%s ｜ 现算=%s ｜ 上一盘=%s ⇒ %s"
			% [a2, a2f, a1, "正确 ✓" if a2 == a2f else "★★拿了上一局的分析"])
	if a2 != a2f:
		fail.append("A 局势缓存未随盘面失效（缓存 %s ≠ 现算 %s）" % [a2, a2f])
	# —— 判据 B：领地缓存 ——
	ai_engine.load_board_for_probe(b1)
	var t1 := ai_engine._own_territory_only(v)  # 首次计算并写 `_sc`/`_sv`
	ai_engine.load_board_for_probe(b2)          # ★ 换盘
	var t2 := ai_engine._own_territory_only(v)
	ai_engine._sc_id += 1                       # 强制作废 = 真值的定义
	var t2f := ai_engine._own_territory_only(v)
	print("[scidtest] 夹具体检 B：B1=%s ｜ B2=%s ⇒ %s" % [t1, t2f,
			"两盘不同 ✓" if t1 != t2f else "★两盘相同 ⇒ 判据没有区分力"])
	if t1 == t2f:
		fail.append("夹具体检 B 没有区分力：两盘在该点的领地结论相同（%s）" % str(t1))
	print("[scidtest] B 领地缓存：换盘后缓存=%s ｜ 作废后重算=%s ｜ 上一盘=%s ⇒ %s"
			% [t2, t2f, t1, "正确 ✓" if t2 == t2f else "★★拿了上一局的结论"])
	if t2 != t2f:
		fail.append("B 领地缓存未随盘面失效（缓存 %s ≠ 重算 %s）" % [str(t2), str(t2f)])
	print("[scidtest] 失败 %d 项：%s" % [fail.size(), str(fail)])
	print("[scidtest] 结论：%s" % ("通过 ✓" if fail.is_empty() else "失败 ✗"))
	get_tree().quit(0 if fail.is_empty() else 1)


## `--scidtest` 夹具：11×11 上白棋围一个 4 点空环；`break_it = true` 时环内多放一颗黑子。
## 层 A（空区边界全是己方子）**不依赖死活判定** ⇒ 夹具稳定，不押在会被别处改动的地基上。
func _scid_fixture(bn: int, break_it: bool) -> Dictionary:
	var d := {}
	var ring: Array = [
		[2, 2], [3, 2], [4, 2], [5, 2],
		[2, 3], [5, 3],
		[2, 4], [5, 4],
		[2, 5], [3, 5], [4, 5], [5, 5],
	]
	for p: Array in ring:
		d[int(p[1]) * bn + int(p[0])] = int(Stone.WHITE)
	if break_it:
		d[3 * bn + 3] = int(Stone.BLACK)
	return d


## `analyze_board()` 结论的紧凑签名（块清单 + 面积 + tag 表规模）。
## 用签名而不是逐字段比，是为了在日志里一眼看出"两盘确实不同"。
func _scid_an_sig(an: Dictionary) -> String:
	# ⚠️ `analyze_board()` 的 `"area"` 取到的是**块分类里的一项**（`"area": w["area"]`），
	#   实测是 Dictionary/其它非标量 ⇒ `String(x)` 会报 `Nonexistent 'String' constructor`
	#   并让本函数返回空串 —— 那会让"两条空串相等"冒充「正确 ✓」（铁律 23 的同族）。
	#   所以：① 一律用 `str()`（接受任意 Variant）；② 把 `typeof` 也打进签名；
	#   ③ `_scid_test()` 里有专门的守卫把"签名构造失败"判成**失败**，不许静默。
	var area_v: Variant = an.get("area", "?")
	var bb: Array = an.get("blocks_black", [])
	var bw: Array = an.get("blocks_white", [])
	var tm: Dictionary = an.get("tag_of", {})
	return "%s|B%d|W%d|T%d|t%d" % [str(area_v), bb.size(), bw.size(), tm.size(),
		typeof(area_v)]


## 现算：把盘面装进去后**直接**算（不碰 `_anlz()` 缓存）。
func _scid_sig_fresh(bd: Dictionary) -> String:
	ai_engine.load_board_for_probe(bd)
	return _scid_an_sig(ai_engine.analyze_board())


## 走缓存：把盘面装进去后经 `_anlz()` 取（这正是引擎热路径的取法）。
func _scid_sig_cached(bd: Dictionary) -> String:
	ai_engine.load_board_for_probe(bd)
	return _scid_an_sig(ai_engine._anlz())


## 判 `mv` 是不是「落在已被对方围死的空区里」= ③ 机制要拦的那种手。
## 与 `_analyze_bonus` ③ **同判据**（同一份 `_sealed_color` + `_has_live_block_near`）
## —— 否则「判据量的东西 ≠ 刀改的东西」（铁律 13）。
func _anlz_dir_sealed(an: Dictionary, mv: int, my: int) -> bool:
	if mv < 0 or int(board[mv]) != int(Stone.EMPTY):
		return false
	var seal := ai_engine._sealed_color(mv)
	return seal >= 0 and seal != my and ai_engine._has_live_block_near(an, mv, seal)


## ---------------------------------------------------------------------------
## 自检（--sealhard）★ 空区**硬过滤**：③ 从软权重升级成"打分前剔除" + 扩面。
##
## 起因（两件实测，都不是猜测）：
##   · `--anlzdir` 16 局面：③ 触发 11 次 / 8 局面、Δmax 恰好 6.00（仿射✓）、跨实现分岔 0，
##     但**目标排名全是最后一名** ⇒ `内K 0→0→0`、`冠 0/0/0` ⇒ **冗余惩罚**（铁律 69）。
##   · 空区边界构成直方图：己方侧（13 点）靠硬过滤做到**进前K 0**；对方侧（15 点）只靠
##     软权重 ⇒ **进前K 3**（桶4：4 点进 2，最好名次 8｜桶5：11 点进 1，最好名次 9）
##     ⇒ 治法 = 换成硬过滤并扩面。
##
## 判据六段（每段都必须**会红**才算数）：
##   ① 接线（**走真源**，不是手算）：`use_sealed_hard_filter = false` 时调 `_prepare_root()`，
##      它落下的 `sealed_hard_blocked_last` 必须**恰好 0**。这是本自检存在的理由 ——
##      没有这一条，"开关接了但 `_prepare_root` 忘了读它"会安静地全绿（死参数，铁律 22）。
##   ② 机制 + **跨实现对拍**：开档必须真的剔到点（> 0）；且**手算表的默认档剔除数**必须与
##      真路径的 `sealed_hard_blocked_last` **逐局面相等** ⇒ 手算表算错一位立刻报红。
##   ③ θ 单调，**单列有效分母**：θ 越大剔除越少。只对「θ=0.999 档就有剔除」的局面算有效，
##      否则 0 ≥ 0 ≥ 0 恒真（铁律 27 —— "没量到"不许印成满分证据）。
##   ④ 跨实现一致（口径对拍）：`_sealed_color()` 判「整片空区只碰一种颜色」的那些点，
##      必须是 `_sc_o == 0`（边界一颗己方子都没有）。两条 BFS 是**独立实现**
##      （`_sealed_color` 用邻接**对**语义，`_own_area_layers` 用**去重子**语义）
##      ⇒ 这条专门抓我新加的计数写错（去重戳号抢了别的 BFS 会静默漏计）。
##   ⑤ 安全阀：任何局面过滤后候选都不得为空 —— `choose_move()` 拿到空候选会**直接停一手**。
##   ⑥ θ 扫描表：θ ｜ 剔除数 ｜ 只过①②③（量条件④收窄了多少）｜ 其中「按关档分数进前K」
##      ｜ 其中「原本是冠军」｜ 被剔点的空区点数分布。这张表是**定默认值**用的，不是判据；
##      单独印出来，免得"表好看"被当证据。
##
## ⚠️ 本判据只量**机制**（剔除是否发生、剔了谁、会不会剔空），**不含棋力结论**：
##   硬过滤会不会掉棋力要跨盘胜率差，检出 2.5pp 需约 **12548 局**（铁律 24）。
##   所以默认档只敢取"有棋理安全阀兜着"的那一档，四个旋钮都做成运行期可调。
func _sealhard_test() -> void:
	print("[sealhard] ===== 空区硬过滤（③ 软权重 → 硬过滤 + 扩面）=====")
	var thetas: Array[float] = [0.999, 0.9, 0.75, 0.5]
	var n_th := thetas.size()
	var DEF := 2                       # 默认档下标（0.75）
	var rm_tot: Array[int] = []
	var rm_ink: Array[int] = []
	var rm_rk1: Array[int] = []
	var rm_sz: Array[int] = []
	var rm_n4_tot: Array[int] = []      # 只过 ①②③ 的剔除数（量条件 ④ 收窄了多少）
	# 被剔点的「空区点数」分布（定 `sealed_hard_max_size` 用）：
	#   桶 = 1 ｜ 2~3 ｜ 4~6 ｜ 7~9 ｜ 10+
	var rm_h: Array = []
	for i in n_th:
		rm_tot.append(0)
		rm_ink.append(0)
		rm_rk1.append(0)
		rm_sz.append(0)
		rm_n4_tot.append(0)
		rm_h.append([0, 0, 0, 0, 0])
	var n_pos := 0
	var sum_el := 0
	var pos_off_rm := 0          # ① 关档竟剔到点的局面（必须 0）
	var pos_on_rm := 0           # ② 开档剔到点的局面
	var cross_bad := 0           # ② 手算表 vs 真路径 对拍不一致的局面
	var mono_bad := 0            # ③ 单调违反处数（只在有效分母里数）
	var mono_trivial := 0        # ③ θ=0.999 档没剔除 ⇒ 该局面三档恒真，不计证据
	var n_seal3 := 0             # ④ ③ 现行目标点数
	var seal3_viol := 0          # ④ 其中 `_sc_o != 0` 的个数（必须 0）
	var pos_empty := 0           # ⑤ 过滤后候选为空的局面（必须 0）
	var cands_min := 1 << 30     # ⑤ 开档候选数最小值
	var cands_min_off := 1 << 30
	var fail: Array[String] = []

	var bt_list: Array[int] = [GameConfig.BOARD_PENROSE, GameConfig.BOARD_HAT]
	var cps: Array[int] = [60, 90, 115]
	var pw := 24
	for bt: int in bt_list:
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.STANDARD
		_apply_board_size(GameConfig.STANDARD)
		_generate_selected_board()
		for gi in 2:
			var sd := 20261008 + gi * 1013 + bt * 7
			reset_game(true)
			ai_engine.setup(adjacency, int(Stone.BLACK), sd)
			ai_engine.threads = 1              # ★ 造样本必须确定性（多线程合并依赖墙钟）
			ai_engine.ld_enabled = true
			ai_engine.max_playouts = pw
			ai_engine.playout_cap_factor = 0.5
			ai_engine.use_analyze_bonus = false   # 造样本期关层（被测量不参与造样本）
			ai_engine.use_sealed_hard_filter = false
			ai_engine.sealed_hard_max_size = 0    # ④ 的前提：无尺寸上限时硬过滤 ⊇ ③
			var played := 0
			for cp: int in cps:
				while played < cp:
					ai_engine._turn = int(Stone.BLACK) if (played % 2 == 0) else int(Stone.WHITE)
					ai_engine.ai_color = ai_engine._turn
					ai_engine._ko = -1
					var mvp := ai_engine.choose_move(board, -1)
					if mvp < 0 or int(board[mvp]) != int(Stone.EMPTY):
						break
					board[mvp] = ai_engine._turn
					played += 1
				# ================= 局面就位，量测一律走确定性路径 =================
				var side: int = int(Stone.BLACK)
				ai_engine.ai_color = side
				ai_engine.use_analyze_bonus = true
				ai_engine.analyze_max_blocks = 2000
				ai_engine.load_board_for_probe(board)
				ai_engine._turn = side
				ai_engine._ko = -1
				ai_engine._sc_id += 1
				# `el` = 与 `_prepare_root()` **同一个过滤器**取候选全集（剪枝前、硬过滤前）
				var el: Array[int] = []
				for v2 in board.size():
					if int(board[v2]) != int(Stone.EMPTY):
						continue
					if ai_engine._own_territory_only(v2):
						continue
					el.append(v2)
				n_pos += 1
				sum_el += el.size()
				# 关档分数（硬过滤**之前**），用来判"被剔的点是不是本来就在前K"
				ai_engine.use_sealed_hard_filter = false
				var offs: Array[float] = []
				for v2 in el:
					ai_engine._sc_id += 1
					offs.append(float(ai_engine.probe_root_score_last(board, v2, side, -1)))
				var kw := ai_engine._effective_root_width(el.size())
				# 空区构成（边界己/对去重子数 + 空区点数）—— 直读缓存，不另写 BFS
				ai_engine._sc_id += 1
				var oc: Array[int] = []
				var pc: Array[int] = []
				var zc: Array[int] = []
				for v2 in el:
					ai_engine._own_area_layers(v2)
					oc.append(int(ai_engine._sc_o[v2]))
					pc.append(int(ai_engine._sc_p[v2]))
					zc.append(int(ai_engine._sc_z[v2]))
				# ④ ③ 现行目标（三条件口径复用 `_anlz_dir_sealed`，不另写一份）
				var an := ai_engine.analyze_board()
				for i in el.size():
					if not _anlz_dir_sealed(an, int(el[i]), side):
						continue
					n_seal3 += 1
					if oc[i] != 0:
						seal3_viol += 1
				# ---- 手算表：逐 θ 档数"会剔掉谁"（读同一份缓存，纯只读）----
				var rm_pos: Array[int] = []
				var rm_no4: Array[int] = []
				for ti in n_th:
					rm_pos.append(0)
					rm_no4.append(0)
				for ti in n_th:
					var th: float = thetas[ti]
					for i in el.size():
						var tot := oc[i] + pc[i]
						if tot <= 0:
							continue
						if float(pc[i]) < th * float(tot):
							continue
						var zcap: int = int(ai_engine.sealed_hard_max_size)
						if zcap > 0 and zc[i] > zcap:
							continue
						rm_no4[ti] += 1        # 只过 ①②③：用来量条件 ④ 到底收窄了多少
						# ★ 条件 ④：必须与引擎 `_sealed_by_opp_hard()` **逐字同口径**。
						#   第一版漏了这一条 ⇒ 手算表比真路径多算 ⇒ 跨实现对拍 5 个局面报红。
						#   这正说明那条对拍判据有牙齿（铁律 4：对照本身也要有牙齿）。
						if not ai_engine._has_live_block_near(an, int(el[i]), 3 - side):
							continue
						rm_pos[ti] += 1
						rm_tot[ti] += 1
						if zc[i] > rm_sz[ti]:
							rm_sz[ti] = zc[i]
						if zc[i] <= 1:
							rm_h[ti][0] += 1
						elif zc[i] <= 3:
							rm_h[ti][1] += 1
						elif zc[i] <= 6:
							rm_h[ti][2] += 1
						elif zc[i] <= 9:
							rm_h[ti][3] += 1
						else:
							rm_h[ti][4] += 1
						var rk := 1
						for j in el.size():
							if offs[j] > offs[i]:
								rk += 1
						if rk <= kw:
							rm_ink[ti] += 1
						if rk == 1:
							rm_rk1[ti] += 1
				for ti in n_th:
					rm_n4_tot[ti] += rm_no4[ti]
				# ---- 真路径：调 `_prepare_root()`，读它自己落下的计数（判据走真源）----
				ai_engine.use_sealed_hard_filter = false
				var r_off: Dictionary = ai_engine._prepare_root(-1)
				var boff: int = int(ai_engine.sealed_hard_blocked_last)
				var coff: int = (r_off["cands"] as Array).size()
				ai_engine.sealed_hard_share = thetas[DEF]
				ai_engine.use_sealed_hard_filter = true
				var r_on: Dictionary = ai_engine._prepare_root(-1)
				var bon: int = int(ai_engine.sealed_hard_blocked_last)
				var con: int = (r_on["cands"] as Array).size()
				ai_engine.use_sealed_hard_filter = false
				if boff != 0:
					pos_off_rm += 1
				if bon > 0:
					pos_on_rm += 1
				if bon != rm_pos[DEF]:
					cross_bad += 1
				if con < cands_min:
					cands_min = con
				if coff < cands_min_off:
					cands_min_off = coff
				if con == 0:
					pos_empty += 1
				# ★★ 单调方向（2026-10-08 修 —— **判据自己写反了，不是引擎的问题**）：
				#   `thetas` 是**递减**的（0.999 → 0.9 → 0.75 → 0.5）⇒ θ 越小、满足
				#   `p ≥ θ·tot` 的点越多 ⇒ `rm_pos[ti]` 必须**非递减**。
				#   所以"违反"是 `rm_pos[ti] > rm_pos[ti+1]`。
				#   第一版写成 `<` ⇒ 把**正确**行为判成违反（实测 11 处）；而**同一屏上**
				#   表格里 70/70/79/140 正摆着递增 —— 这就是铁律 17 的指纹：
				#   **判据输出与它自己喂的数据自相矛盾 ⇒ 先怀疑判据，别去引擎里找 bug。**
				if rm_pos[0] > 0:
					for ti in range(0, n_th - 1):
						if rm_pos[ti] > rm_pos[ti + 1]:
							mono_bad += 1
				else:
					mono_trivial += 1
		print("[sealhard] 盘 %s：累计 %d 局面（空点合计 %d）" % [_bt_name(bt), n_pos, sum_el])

	print("[sealhard] ① 接线（走真源 `_prepare_root`）：开关 OFF 时剔除数 ≠ 0 的局面 %d（必须 0）"
			% pos_off_rm)
	print("[sealhard]      关档候选数最小值 %d（> 0 才算真的把旧路径走通了）" % cands_min_off)
	print("[sealhard] ② 机制：开档（θ=%.3f）剔除 > 0 的局面 %d / %d" % [thetas[DEF], pos_on_rm, n_pos])
	print("[sealhard]      跨实现对拍：手算表 ≠ 真路径计数的局面 %d（必须 0）" % cross_bad)
	print("[sealhard] ③ θ 单调：**有效分母** = θ=0.999 档就有剔除的局面 %d / %d ｜ 恒真不计证据 %d ｜ 违反 %d"
			% [n_pos - mono_trivial, n_pos, mono_trivial, mono_bad])
	print("[sealhard] ④ 跨实现口径：③ 现行目标点 %d 个，其中边界含己方子（应为 0）%d 个"
			% [n_seal3, seal3_viol])
	print("[sealhard] ⑤ 安全阀：开档候选数最小值 %d ｜ 过滤后候选为空 / 退回的局面 %d（必须 0）"
			% [cands_min, pos_empty])
	print("[sealhard] ⑥ θ 扫描表（%d 局面 / 空点合计 %d）：" % [n_pos, sum_el])
	print("[sealhard]      %-9s %-9s %-11s %-13s %-13s %-9s %s"
			% ["θ", "剔除数", "不过④", "其中进前K", "其中是冠军", "↓进前K占比", "被剔空区点数分布 1|2-3|4-6|7-9|10+"])
	for ti in n_th:
		var hr: Array = rm_h[ti]
		var pct := 0.0
		if rm_tot[ti] > 0:
			pct = 100.0 * float(rm_ink[ti]) / float(rm_tot[ti])
		print("[sealhard]      %-9.3f %-9d %-11d %-13d %-13d %-9.0f%% %d|%d|%d|%d|%d"
				% [thetas[ti], rm_tot[ti], rm_n4_tot[ti], rm_ink[ti], rm_rk1[ti], pct,
				int(hr[0]), int(hr[1]), int(hr[2]), int(hr[3]), int(hr[4])])
	print("[sealhard]      ※ 「不过④」= 只过 ①②③；与「剔除数」的差 = 条件 ④（对方附近有活块）收窄掉的")
	print("[sealhard]      ※ 各档被剔空区**最大点数**（定 `sealed_hard_max_size` 用）：%s" % str(rm_sz))
	print("[sealhard]      ※ 空点合计 %d ⇒ θ=%.3f 档剔掉 %.1f%% 的候选"
			% [sum_el, thetas[DEF], 100.0 * float(rm_tot[DEF]) / maxf(float(sum_el), 1.0)])

	if pos_off_rm != 0:
		fail.append("开关 OFF 竟剔了点 ⇒ `_prepare_root` 没接上开关（旧行为被改了）")
	if cands_min_off <= 0:
		fail.append("关档候选数最小值为 %d ⇒ 取样路径本身就不通，本段其余结论无效" % cands_min_off)
	if pos_on_rm == 0:
		fail.append("开档一个点都没剔 ⇒ 机制没触发（不是『没效果』，是『没接上』）")
	if cross_bad != 0:
		fail.append("手算表与真路径对拍不一致 %d 个局面 ⇒ 两套实现分岔，⑥ 那张表不可信" % cross_bad)
	if n_seal3 == 0:
		fail.append("③ 现行目标点为 0 ⇒ 本样本量不到 ③，④ 段无效（不是通过）")
	if seal3_viol != 0:
		fail.append("③ 的目标点里 %d 个边界含己方子 ⇒ 两条 BFS 口径分岔" % seal3_viol)
	if pos_empty != 0:
		fail.append("有 %d 个局面过滤后候选为空 ⇒ `choose_move()` 会直接停一手" % pos_empty)
	if mono_bad != 0:
		fail.append("θ 单调被违反 %d 处 ⇒ 阈值语义与实现不一致" % mono_bad)
	print("[sealhard] 失败 %d 项：%s" % [fail.size(), str(fail)])
	print("[sealhard] 结论：%s" % ("通过 ✓" if fail.is_empty() else "失败 ✗"))
	print("[sealhard] ⚠️ 本判据只说**机制方向**，**不是**棋力结论（胜率差需约 12548 局，铁律 24）")
	print("[sealhard] 旋钮（运行期可调）：use_sealed_hard_filter / sealed_hard_share / "
			+ "sealed_hard_max_size / sealed_hard_min_cands")
	get_tree().quit(0 if fail.is_empty() else 1)


## ---------------------------------------------------------------------------
## 自检（--anlzmis）局势层**机械缺陷 + 工作点**诊断（只读探针；只印数字）。
##
## 起因：`--anlzrate` 在 **120 手**处量出「② 提死子 0% / ③ 罚围死 0.2%」，
##   当时的结论是「`ld_cap_points` 眼位模型太窄」。重读代码后发现**另有四处更基本的
##   机械缺陷**，它们**先于**棋理问题生效 —— 眼位模型再宽也救不回来：
##
##   A. `analyze_board()` 的逐块去重键是 `_group()` 的返回值 = **成员计数**（不是块身份）：
##        `var g := _group(v) ... if seen.has(g): continue`
##      ⇒ **同尺寸的两块棋被当成一块，第二块起全部静默丢弃**。19×19 上单子块极多
##      ⇒ `blocks_*` 只剩「每种尺寸各一块」。
##      受害面：`_decide_win_rate`（胜率）· `own_*/their_*`（三分类）· `advice` ·
##      音乐 `an_*` · **以及 ②③ 两个机制的查表**（都要先在 `blocks_*` 里找到那一块）。
##
##   B. `_find_block(an, g, col)` 的形参名是 `rep`，而 ② 传进去的是 `_group(nb)` = **计数**
##      ⇒ 拿「块的子数」去比「代表点点号」= **量纲错配**，只有极偶然才撞上。
##
##   C. ① `w_rescue_own_live` 名为「救己方」，判据 `_eye_vital_flags(v)[1]` 却**不分颜色**
##      （对方未定形块的要点同样返回 true）⇒ 同一份奖励同时喂了「做活」与「点杀」两支。
##
##   D. ③ `_has_live_block_near()` 只比**代表点** `rep` 与 v 的邻接 ⇒ 大块的代表点
##      （= 该块里点号最小的那个子）不在 v 边上就查不到。
##
##   E. 工作点：三个机制服务的是**终局**行为（用户原话「往对方地盘落子」），
##      而 `--anlzrate` 在 **120 手**处量 —— 不许在错的档位下结论（铁律 4）。
##
## 本探针按**手数分档**逐条量化 A~D，并同时给出「修正口径」的对照列。
## 三个独立实现（`_anlz_*_indep`）**故意不调被测函数**：探针自己走邻接、查块表，
## 两边对上才算口径修正到位（独立复核不共用逻辑 ⇒ 铁律 13）。
func _anlz_mis() -> void:
	var n_games := 3
	var stages: Array[int] = [30, 60, 90, 115]
	var pw := 32
	var bn := 11
	print("[anlzmis] ===== 局势层机械缺陷 + 工作点诊断（%d 局；盘 %d×%d=%d 格；分档 %s 手；pw=%d）====="
			% [n_games, bn, bn, bn * bn, str(stages), pw])
	print("[anlzmis] 口径：造样本期 use_analyze_bonus=false（被测量不参与造样本 ⇒ 修前修后可逐字对比）")
	print("[anlzmis] 口径：扫描时 ai_color=BLACK；「同色/异色」皆相对 ai_color；计数量纲：点/块")
	print("[anlzmis] 口径：盘取 11×11（121 格）—— 真实「标准」彭罗斯盘实测 120 个落子格。")
	for stage in stages:
		var pts := 0
		var grp_indep := 0      # 独立枚举的块数（自己维护 visited）
		var grp_sum := 0        # 独立枚举的子数（应 == 盘面非空点数）
		var max_blk := 0        # 最大块的子数（样本质量：死活机制需要**小**块）
		var small_blk := 0      # ≤6 子的块数（能"做活"的块至少得这么小）
		var blk_n := 0          # blocks_black + blocks_white 的块数
		var blk_sum := 0        # 它们的 stones 之和
		var eye_tot := 0        # ① 要点命中总数
		var eye_same := 0       # ① 其中 rep 与 ai_color 同色（**该拿**）
		var eye_oppo := 0       # ① 其中 rep 异色（不该拿 = 错配量）
		var sc_opp := 0         # ③ 候选集：空区被「非 ai_color」单色围住
		var sc_rep := 0         # ③ 引擎口径（修后 = 整块）
		var sc_all := 0         # ③ 探针独立口径（两边必须相等 ⇒ 跨实现对拍）
		var cap_eng := 0        # ② 历史口径（计数当 rep 用，_find_block 保留复现）
		var cap_ok := 0         # ② 正确口径（邻点属某 DEAD 块）
		var bonus_pos := 0      # `_analyze_bonus` > 0 的点数（① 或 ② 命中）
		var bonus_neg := 0      # `_analyze_bonus` < 0 的点数（③ 命中）
		var empt := 0           # 空点总数（触发率的分母；**在扫描循环里真数出来**）
		for gi in n_games:
			reset_game(true)
			# ★★ 盘必须是**真实盘的尺寸**：彭罗斯「标准」盘实测 **120 个落子格**，
			#   而 TEST_GRID_N=19（361 格）是它的 3 倍 ⇒ 工作点错档：
			#   120 手在 361 格上只是中盘，在 121 格上已近终局。
			#   实测（19×19 版 E 列）：280 手时最大块 140 子、≤6 子的块 **0** 个 ——
			#   那种局面里**不存在死活问题**，死活机制的触发率必然是 0，
			#   与机制写得对不对无关。改用 11×11 重测。
			_test_build_square_grid(bn)
			ai_engine.setup(adjacency, Stone.BLACK, 20261008 + gi)
			ai_engine.ld_enabled = true
			ai_engine.max_playouts = pw
			ai_engine.playout_cap_factor = 0.5
			ai_engine.use_analyze_bonus = false     # ★ 造样本期关掉被测层
			var played := 0
			while played < stage:
				ai_engine._turn = int(Stone.BLACK) if (played % 2 == 0) else int(Stone.WHITE)
				ai_engine.ai_color = ai_engine._turn
				ai_engine._ko = -1
				var mv := ai_engine.choose_move(board, -1)
				if mv < 0 or int(board[mv]) != int(Stone.EMPTY):
					break
				board[mv] = ai_engine._turn
				played += 1
			# —— 快照 ——
			ai_engine.ai_color = Stone.BLACK
			ai_engine.load_board_for_probe(board)
			ai_engine._turn = int(Stone.BLACK)
			ai_engine._ko = -1
			# 排除「清单被 analyze_max_blocks 截断」这个混淆因素：截断会让 blk_n 变少，
			# 与「同尺寸丢块」症状**一模一样**，不分清就会归错因。
			ai_engine.analyze_max_blocks = 2000
			var an := ai_engine.analyze_board()
			# —— A + E：独立分组枚举（自己维护 visited，不共用被测去重逻辑）——
			var vis := {}
			var rp := {}                 # 点 → 所在块的代表点（供下面 O(1) 查表）
			for v in board.size():
				if int(board[v]) == int(Stone.EMPTY):
					continue
				pts += 1
				if vis.has(v):
					continue
				var cnt := ai_engine._group(v)
				grp_indep += 1
				grp_sum += cnt
				if cnt > max_blk:
					max_blk = cnt
				if cnt <= 6:
					small_blk += 1
				var rp_here := int(ai_engine._gbuf[0])
				for i in cnt:
					var m := int(ai_engine._gbuf[i])
					vis[m] = true
					rp[m] = rp_here
			var bb: Array = an.get("blocks_black", [])
			var bw: Array = an.get("blocks_white", [])
			blk_n += bb.size() + bw.size()
			for b: Dictionary in bb:
				blk_sum += int(b.get("stones", 0))
			for b: Dictionary in bw:
				blk_sum += int(b.get("stones", 0))
			# —— B/C/D/F：逐空点扫描 ——
			ai_engine.use_analyze_bonus = true      # 只在这一段打开被测层
			for v in board.size():
				if int(board[v]) != int(Stone.EMPTY):
					continue
				empt += 1
				var vf := ai_engine._eye_vital_flags(v)
				if bool(vf[1]):
					eye_tot += 1
					if int(ai_engine._b[int(vf[2])]) == int(Stone.BLACK):
						eye_same += 1
					else:
						eye_oppo += 1
				var seal := ai_engine._sealed_color(v)
				if seal >= 0 and seal != int(Stone.BLACK):
					sc_opp += 1
					if ai_engine._has_live_block_near(an, v, seal):
						sc_rep += 1
					if _anlz_live_near_indep(an, rp, v, seal):
						sc_all += 1
				if _anlz_cap_engine_indep(an, rp, v, 3 - int(Stone.BLACK)):
					cap_eng += 1
				if _anlz_dead_near_indep(an, rp, v, 3 - int(Stone.BLACK)):
					cap_ok += 1
				var add := ai_engine._analyze_bonus(v)
				if add > 0.0:
					bonus_pos += 1
				elif add < 0.0:
					bonus_neg += 1
			ai_engine.use_analyze_bonus = false
		print("[anlzmis] ---- %d 手档 ----" % stage)
		print("[anlzmis] A 块清单：盘面非空 %d ｜ 独立枚举 %d 块/%d 子 ｜ 清单 %d 块/%d 子 ｜ 丢块 %d ｜ 丢子 %d"
				% [pts, grp_indep, grp_sum, blk_n, blk_sum, grp_indep - blk_n, grp_sum - blk_sum])
		print("[anlzmis] E 样本质量：最大块 %d 子 ｜ ≤6 子的小块 %d 个 ｜ 平均块大小 %.1f"
				% [max_blk, small_blk, float(grp_sum) / maxf(float(grp_indep), 1.0)])
		print("[anlzmis] B ①要点：总 %d ｜ 同色(该拿) %d ｜ 异色(错配) %d" % [eye_tot, eye_same, eye_oppo])
		print("[anlzmis] C ③候选 %d ｜ 引擎口径 %d ｜ 探针独立口径 %d ｜ 跨实现差 %d"
				% [sc_opp, sc_rep, sc_all, sc_all - sc_rep])
		print("[anlzmis] D ②提死子：历史口径 %d ｜ 正确口径 %d" % [cap_eng, cap_ok])
		print("[anlzmis] F 三机制触发：_analyze_bonus>0 %d ｜ <0 %d ｜ 空点 %d ｜ 合计触发率 %.2f%%"
				% [bonus_pos, bonus_neg, empt,
				   100.0 * float(bonus_pos + bonus_neg) / maxf(float(empt), 1.0)])
	ai_engine.use_analyze_bonus = true
	ai_engine.analyze_max_blocks = 400
	print("[anlzmis] ===== 判读 =====")
	print("[anlzmis] A 修后「丢块=0 且 丢子=0」⇒ 同尺寸块不再被合并（胜率/三分类/②③查表恢复正确）。")
	print("[anlzmis] B「异色」应为 0：`w_rescue_own_live` 只救己方（修前它替对方做活）。")
	print("[anlzmis] C「跨实现差」应为 0：引擎与探针各自独立实现整块邻接，必须对拍一致。")
	print("[anlzmis] D 两列口径不同，历史列留着给「修前 0 次」做对照锚。")
	print("[anlzmis] E 判读样本本身：平均块远大于 6 子 / 小塊数近 0 ⇒ 这一档**没有死活结构**，")
	print("[anlzmis]   此时任何死活类机制的触发率都只能是 0，与机制写得对不对**无关**。")
	get_tree().quit(0)


## 独立实现：`v` 是否与颜色 `col` 的某块 **LIVE** 棋的**任一子**相邻。
## 故意不调 `ai_engine._has_live_block_near()` —— 那是被测对象。
## `rp` = 点 → 所在块代表点（调用方预建，O(1) 查，避免每个邻点都跑一次 `_group()`）。
func _anlz_live_near_indep(an: Dictionary, rp: Dictionary, v: int, col: int) -> bool:
	var key := "blocks_black" if col == int(Stone.BLACK) else "blocks_white"
	var live := {}
	for b: Dictionary in an.get(key, []):
		if String(b.get("tag", "")) == "LIVE":
			live[int(b.get("rep", -1))] = true
	if live.is_empty():
		return false
	var k := ai_engine._as[v]
	var ke := ai_engine._as[v + 1]
	while k < ke:
		var nb := int(ai_engine._af[k])
		k += 1
		if int(ai_engine._b[nb]) != col:
			continue
		if live.has(int(rp.get(nb, -1))):
			return true
	return false


## 独立实现：`v` 是否与颜色 `col` 的某块 **DEAD** 棋相邻（正确口径）。
func _anlz_dead_near_indep(an: Dictionary, rp: Dictionary, v: int, col: int) -> bool:
	var key := "blocks_black" if col == int(Stone.BLACK) else "blocks_white"
	var dead := {}
	for b: Dictionary in an.get(key, []):
		if String(b.get("tag", "")) == "DEAD":
			dead[int(b.get("rep", -1))] = true
	if dead.is_empty():
		return false
	var k := ai_engine._as[v]
	var ke := ai_engine._as[v + 1]
	while k < ke:
		var nb := int(ai_engine._af[k])
		k += 1
		if int(ai_engine._b[nb]) != col:
			continue
		if dead.has(int(rp.get(nb, -1))):
			return true
	return false


## 独立实现：**照抄** `_analyze_bonus` ② **历史**分支的算式（把 `_group()` 的**计数**
## 当 `rep` 交给 `_find_block`），用来给「量纲错配」留一个可重跑的对照锚。
func _anlz_cap_engine_indep(an: Dictionary, rp: Dictionary, v: int, col: int) -> bool:
	var k := ai_engine._as[v]
	var ke := ai_engine._as[v + 1]
	while k < ke:
		var nb := int(ai_engine._af[k])
		k += 1
		if int(ai_engine._b[nb]) != col:
			continue
		# 历史口径：`_group()` 的**返回值就是计数**，却被当 rep 传下去
		var g := ai_engine._group(nb)
		var blk := ai_engine._find_block(an, g, col)
		if not blk.is_empty() and String(blk.get("tag", "")) == "DEAD":
			return true
	return false


## 自检（--anlzrate）三个局势机制在**真实盘**上的**触发率**（决定「留哪个」）。
##
## 背景：`--anlzwhy` 实测 964 个候选点里 0 个要点 ⇒ `w_rescue_own_live` 在
## **AI 自战样本**上恒不触发。但另两个机制走不同分支（提对方死子 / 罚被围死地），
## 可能照样有效 ⇒ 三个分别计数，「留哪个」才有数据支撑。
##
## ⚠️ 样本局限：局面是 **AI 自战 pw24 / 120 手**——弱 AI 自己不做活，
##    自然形成不了眼位。所以「救活 0 触发」对**弱 AI 自战**成立，
##    不能直接外推到「有做活意图的真实对局」。
func _anlz_rate() -> void:
	var n_pos := 4
	var per_game := 120
	var pw := 24
	print("[anlzrate] ===== 三个局势机制的真实盘触发率（%d 局 × %d 手，pw=%d）====="
			% [n_pos, per_game, pw])
	var total := 0
	var hit_rescue := 0
	var hit_capture := 0
	var hit_sealed := 0
	var by_board := []# 每局的要点数（看是不是个别局的问题）
	for gi in n_pos:
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.BLACK, 20261007 + gi)
		ai_engine.ld_enabled = true
		ai_engine.max_playouts = pw
		ai_engine.playout_cap_factor = 0.5
		for _m in per_game:
			ai_engine._turn = int(Stone.BLACK) if (_m % 2 == 0) else int(Stone.WHITE)
			ai_engine.ai_color = ai_engine._turn
			ai_engine._ko = -1
			var mv := ai_engine.choose_move(board, -1)
			if mv < 0 or int(board[mv]) != int(Stone.EMPTY):
				break
			board[mv] = ai_engine._turn
		ai_engine.ai_color = Stone.BLACK
		ai_engine.load_board_for_probe(board)
		ai_engine._turn = int(Stone.BLACK)
		ai_engine._ko = -1
		ai_engine.use_analyze_bonus = true
		var v_cnt := 0
		for v in board.size():
			if int(board[v]) != int(Stone.EMPTY):
				continue
			total += 1
			if bool(ai_engine._eye_vital_flags(v)[1]):
				hit_rescue += 1
				v_cnt += 1
			var add := ai_engine._analyze_bonus(v)
			if add > 0.0:
				hit_capture += 1
			elif add < 0.0:
				hit_sealed += 1
		by_board.append(v_cnt)
	ai_engine.use_analyze_bonus = true
	var t := maxf(float(total), 1.0)
	print("[anlzrate] 候选空点总数 %d" % total)
	print("[anlzrate] ① 救活（w_rescue_own_live）：%d / %d = %.1f%%" % [hit_rescue, total, 100.0 * float(hit_rescue) / t])
	print("[anlzrate] ② 提死子（w_capture_dead）：%d / %d = %.1f%%" % [hit_capture, total, 100.0 * float(hit_capture) / t])
	print("[anlzrate] ③ 罚围死（w_sealed_territory）：%d / %d = %.1f%%" % [hit_sealed, total, 100.0 * float(hit_sealed) / t])
	print("[anlzrate]   逐局要点数：%s" % str(by_board))
	print("[anlzrate] 判读：")
	if hit_rescue == 0:
		print("[anlzrate]   ★ ① 在**弱 AI 自战**样本上**恒不触发** ⇒ 弱 AI 自己不做活，")
		print("[anlzrate]      盘上形成不了小眼位空间（实测 3~7 点空区 = 0 个）。")
		print("[anlzrate]      ⇒ 不能据此判「机制无效」，但**也不能**据此判「有效」。")
	if hit_capture > 0:
		print("[anlzrate]   ✓ ② 提死子**有触发**（%.0f%%）⇒ 这条机制在实战样本上活着" % (100.0 * float(hit_capture) / t))
	if hit_sealed > 0:
		print("[anlzrate]   ✓ ③ 罚围死**有触发**（%.0f%%）⇒ 上一轮修「触边未封闭」见效" % (100.0 * float(hit_sealed) / t))
	get_tree().quit(0)

## 自检（--anlzwhy）`_eye_vital_flags` 在真实盘上的**早退原因分布**。
##
## 背景：`--anlzreal` 实测 8 局 × 120 手、满盘 120 子 ⇒ **0 个要点**。
## 这不是「无处可救」，是某个早退点恒命中。四个早退点：
##   ① `_eye_rep_at(v) < 0`（区域过大 / 边界混色）
##   ② `_group_status(...) != 1`（该块不是「未定形」）
##   ③ `_ld_n <= 0`（局部图没建成）
##   ④ `_ld_kill_mask(_ld_n) == 0`（没有杀点）
## ⇒ 逐条计数，不猜。
func _anlz_why() -> void:
	var n_pos := 4
	var per_game := 120
	var pw := 24
	print("[anlzwhy] ===== 要点早退原因分布（%d 局 × %d 手，pw=%d）=====" % [n_pos, per_game, pw])
	var c1 := 0# 区域过大
	var c1b := 0     # 边界混色
	var c2 := 0# 块不是未定形
	var c3 := 0# 局部图没建成
	var c4 := 0# 没有杀点
	var ok := 0
	var total := 0
	var st_hist := {}     # _group_status 分布（0/1/2）
	var area_hist := {}   # 空区大小分布（分档）
	for gi in n_pos:
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.BLACK, 20261007 + gi)
		ai_engine.ld_enabled = true
		ai_engine.max_playouts = pw
		ai_engine.playout_cap_factor = 0.5
		for _m in per_game:
			ai_engine._turn = int(Stone.BLACK) if (_m % 2 == 0) else int(Stone.WHITE)
			ai_engine.ai_color = ai_engine._turn
			ai_engine._ko = -1
			var mv := ai_engine.choose_move(board, -1)
			if mv < 0 or int(board[mv]) != int(Stone.EMPTY):
				break
			board[mv] = ai_engine._turn
		ai_engine.ai_color = Stone.BLACK
		ai_engine.load_board_for_probe(board)
		ai_engine._turn = int(Stone.BLACK)
		ai_engine._ko = -1
		ai_engine.use_analyze_bonus = false
		for v in board.size():
			if int(board[v]) != int(Stone.EMPTY):
				continue
			total += 1
			var rep := ai_engine._eye_rep_at(v)
			if rep < 0:
				# 区分「区域过大」与「边界混色」：自己量一次空区大小与边界色数
				var reg := 0
				var seen := {}
				var stack: Array[int] = [v]
				seen[v] = true
				var cols := {}
				while not stack.is_empty():
					var cur: int = stack.pop_back()
					reg += 1
					for nb: int in adjacency[cur]:
						if int(board[nb]) == int(Stone.EMPTY):
							if not seen.has(nb):
								seen[nb] = true
								stack.append(nb)
						else:
							cols[int(board[nb])] = true
				var bucket := 0
				if reg > 7: bucket = 8
				elif reg <= 2: bucket = reg
				else: bucket = 3
				area_hist[bucket] = int(area_hist.get(bucket, 0)) + 1
				if cols.size() >= 2:
					c1b += 1
				else:
					c1 += 1
				continue
			var cnt := ai_engine._group(rep)
			var st := ai_engine._group_status(cnt, ai_engine._libs(cnt, -1))
			st_hist[st] = int(st_hist.get(st, 0)) + 1
			if st != 1:
				c2 += 1
				continue
			if ai_engine._ld_n <= 0:
				c3 += 1
				continue
			if ai_engine._ld_kill_mask(int(ai_engine._ld_n)) == 0:
				c4 += 1
				continue
			var vi := ai_engine._ldm_index(v, int(ai_engine._ld_n))
			if vi >= 0 and (int(ai_engine._ld_kill_mask(int(ai_engine._ld_n))) & (1 << vi)) != 0:
				ok += 1
	ai_engine.use_analyze_bonus = true
	print("[anlzwhy] 候选空点总数 %d" % total)
	print("[anlzwhy] ① 找不到眼位空间：%d（其中边界混色 %d / 区域过大或无色 %d）" % [c1 + c1b, c1b, c1])
	print("[anlzwhy] ② 块不是未定形(status≠1)：%d ｜ 分布 %s" % [c2, str(st_hist)])
	print("[anlzwhy] ③ 局部图没建成(_ld_n≤0)：%d" % c3)
	print("[anlzwhy] ④ 没有杀点：%d" % c4)
	print("[anlzwhy] ★ 成功识别为要点：%d" % ok)
	var parts := {}
	for k: int in area_hist.keys():
		parts[k] = area_hist[k]
	print("[anlzwhy] 空区大小分档（1/2/3/4-7/&gt;7 → 计数）：%s" % str(parts))
	print("[anlzwhy] 结论：%s" % (
			"机制在真盘上有效 ✓" if ok > 0 else
			("★ 卡在①「找不到眼位空间」⇒ 真盘上小眼位空间**几乎不存在**（占 %.0f%%）"
				% (100.0 * float(c1 + c1b) / maxf(float(total), 1.0)) if c1 + c1b > c2 + c3 + c4 else
			 "★ 卡在②「块不是未定形」⇒ 盘上都是已活/已死" if c2 >= c1 + c1b else
			 "★ 卡在④「没有杀点」")))
	get_tree().quit(0)

## 自检（--anlzreal）**真实局面采样**下量「救活加成的潜在价值」。
##
## 替换掉造夹具的思路（三次都失败，原因见补丁头）。这里用**真实中盘局面**——
## 那里才有「有个更吸引 AI 的点、做活要点被压住」的工作点。
##
## 全部确定性：只读先验（`_root_score` / `_eye_vital_flags`），不跑搜索、不用随机器。
## 局面来源：让引擎自己用固定种子 rollout 走 N 手（用 `_aitune` 那套确定性口径）。
func _anlz_real() -> void:
	var n_pos := 8
	var per_game := 120
	var pw := 24
	print("[anlzreal] ===== 真实局面采样（%d 局 × %d 手，pw=%d）=====" % [n_pos, per_game, pw])
	var ranks: Array = []
	var n_with_vital := 0
	var sum_rank := 0
	var boards_with_vital := 0
	for gi in n_pos:
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		# ★ 被测方= BLACK（`setup` 里显式给），它才是**真的在走的那个颜色**。
		#   第一版采样时 ai_color=WHITE 而盘面是黑走出来的 ⇒ 白方没棋 ⇒ 0 要点。
		ai_engine.setup(adjacency, Stone.BLACK, 20261007 + gi)
		ai_engine.ld_enabled = true
		ai_engine.max_playouts = pw
		ai_engine.playout_cap_factor = 0.5
		for _m in per_game:
			ai_engine._turn = int(Stone.BLACK) if (_m % 2 == 0) else int(Stone.WHITE)
			ai_engine.ai_color = ai_engine._turn
			ai_engine._ko = -1
			var mv := ai_engine.choose_move(board, -1)
			if mv < 0:
				break
			if int(board[mv]) != int(Stone.EMPTY):
				break                    # 引擎给了非法点 ⇒ 停，别污染局面
			board[mv] = ai_engine._turn
		# —— 采样：黑方视角（真正在走的那方）——
		ai_engine.ai_color = Stone.BLACK
		ai_engine.load_board_for_probe(board)
		ai_engine._turn = int(Stone.BLACK)
		ai_engine._ko = -1
		ai_engine.use_analyze_bonus = false
		var vital: Array = []
		for v in board.size():
			if int(board[v]) != int(Stone.EMPTY):
				continue
			if bool(ai_engine._eye_vital_flags(v)[1]):
				vital.append(v)
		if vital.is_empty():
			continue
		n_with_vital += 1
		boards_with_vital += 1
		var best_rank := 999
		for v in vital:
			var rk := _rank_of(board, int(v), 0.0)
			if rk < best_rank:
				best_rank = rk
		ranks.append(best_rank)
		sum_rank += best_rank
	ai_engine.use_analyze_bonus = true

	var nblk := 0
	for i in board.size():
		if int(board[i]) != int(Stone.EMPTY):
			nblk += 1
	print("[anlzreal] 末局盘面子数=%d ｜ 有要点的局面：%d / %d" % [nblk, n_with_vital, n_pos])
	if ranks.is_empty():
		print("[anlzreal] ✗ 全部局面都没有要点。两个可能：")
		print("[anlzreal]    (a) 真的无处可救（120 手后仍未定形 ⇒ 该盘偏乱）")
		print("[anlzreal]    (b) `_eye_vital_flags` 在真盘上从未触发 ⇒ ★机制接线问题")
		get_tree().quit(1)
		return
	var sr := ranks.duplicate()
	sr.sort()
	var med := int(sr[sr.size() / 2])
	var d1 := 0
	var d3 := 0
	var d5 := 0
	for r: int in ranks:
		if r <= 1: d1 += 1
		if r <= 3: d3 += 1
		if r <= 5: d5 += 1
	print("[anlzreal] 要点最好排名：中位 %d ｜前1 %d/%d 前3 %d/%d 前5 %d/%d ｜均值 %.1f"
			% [med, d1, ranks.size(), d3, ranks.size(), d5, ranks.size(),
			   float(sum_rank) / float(ranks.size())])

	print("[anlzreal] %-8s %-14s %-12s" % ["剂量", "要点夺冠局数", "占样本"])
	for d: float in [0.0, 6.0, 12.0, 18.0, 30.0, 50.0, 80.0]:
		var win := 0
		for r: int in ranks:
			if float(r - 1) * 1.5 <= d:
				win += 1
		print("[anlzreal] %-8.0f %-14d %-12s" % [d, win,
				"%.0f%%" % (100.0 * float(win) / float(ranks.size()))])
	print("[anlzreal] ★ 「名次差×1.5 分」是**粗估**（未实测每名分差），只判断量级。")
	get_tree().quit(0)

## 自检（--anlzdose）`w_rescue_own_live` 的**剂量-响应扫描**（确定性，秒级）。
##
## 技能 Part 11：剂量参数必须扫到**饱和**，取**最小有效剂量**。
## 只报 argmax 变没变是不够的 —— 那分不出「剂量不够」与「方向错」。
## ⇒ 打印每个剂量下「要点点的排名 / 与冠军的分差」，两者能区分这两件事。
func _anlz_dose() -> void:
	print("[anlzdose] ===== 救活权重剂量-响应（确定性，先验层面）=====")
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	ai_engine.ld_enabled = true
	var shape: Dictionary = {}
	for cs: Dictionary in _ld_shape_table():
		if String(cs.get("n", "")) == "丁四":
			shape = cs
			break
	if shape.is_empty():
		print("[anlzdose] ✗ 找不到丁四 ⇒ 无法自测")
		get_tree().quit(1)
		return
	# ★★★ 工作点（铁律 4 / 技能 Part 11）：裸眼形**本来就被基线选成冠军**
	#   （实测要点 101 = argmax，全部剂量「第 1 名」）⇒ 无病可治，判据恒假。
	#
	# ★★ 造干扰项的**两次失败**（写在这避免后人重踩）：
	#   ① 在眼形旁放被围死的黑子 ⇒「要点共 0 个」。
	#   ② 挪到远处 (11,2) ⇒ 仍然「要点共 0 个」。
	#   根因（读 `_eye_rep_at` 得到）：它要求该空区的边界**全部同色**，
	#   而 19×19 空盘上任何一颗子都会让大空区边界混色 ⇒ 要点判定直接失效。
	#   ⇒ ★ **不能靠加子造工作点**。
	#   正解：把 `w_center`（中心偏好，真源项）压低 —— 远离中心的非要点点基线分下降，
	#   要点相对上升 ⇒ 基线不再选它 ⇒ 加成有机会把它抬回来。
	#   这是**只动权重、不动控制流**的干预（技能 14.3 的纪律）。
	var sv_center := ai_engine.w_center
	ai_engine.w_center = 0.0
	_lay_eye_shape_with_libs(shape["pts"], Vector2i(5, 5), Stone.WHITE, Stone.BLACK, 0)
	#★★ 必须先把盘面交给引擎再查要点！
	#   `_eye_vital_flags` 读的是引擎内部的 `_b` / `_ld_pts`，不是 `board`。
	#   症状：「要点共 0 个」—— 而**同一夹具**在 `--anlzprobe` 下要点是有的（点 101）。
	#   差别：probe 在查要点前调过 `probe_root_argmax()`（内部 `load_board_for_probe`）
	#   ⇒ 引擎已是这块盘；dose 直接调 ⇒ 引擎还在**上一张盘** ⇒ 判定全 false。
	#   （技能 Part 13：「夹具换盘后必须把新图交给引擎」——我把它误当成只对 setup 生效。）
	ai_engine.load_board_for_probe(board)
	ai_engine._turn = int(Stone.WHITE)
	ai_engine.use_analyze_bonus = false
	var vital: Array = []
	for v in board.size():
		if int(board[v]) != int(Stone.EMPTY):
			continue
		if bool(ai_engine._eye_vital_flags(v)[1]):
			vital.append(v)
	print("[anlzdose] 夹具：丁四眼形 + 一颗被围死的黑子（制造「更强的假候选」）")
	print("[anlzdose] 要点共 %d 个：%s" % [vital.size(), str(vital)])
	if vital.is_empty():
		print("[anlzdose] ✗ 本局面没有要点 ⇒ 夹具失败（不该发生）")
		get_tree().quit(1)
		return
	var v0 := int(vital[0])

	# 基线排名（加成关）
	var base_rank := _rank_of(board, v0, 0.0)
	print("[anlzdose] 基线：要点的排名 = 第 %d 名（1 = 冠军）" % base_rank)
	if base_rank <= 1:
		print("[anlzdose] ★ 基线已经把要点选成冠军 ⇒ 仍是「无病可治」的工作点")
		print("[anlzdose]      ⇒ 这个夹具也不合格，需要更强的干扰项")
	else:
		print("[anlzdose] ★ 工作点合格：要点被压在第 %d 名 ⇒ 加成有机会把它抬上来" % base_rank)

	var doses := [0.0, 4.0, 8.0, 12.0, 18.0, 25.0, 40.0, 60.0, 90.0, 130.0]
	var first_effective := -1.0
	var prev := 999
	var mono_ok := true
	print("[anlzdose] %-7s %-10s %-10s" % ["剂量", "要点排名", "是否夺冠"])
	for d: float in doses:
		var rk := _rank_of(board, v0, d)
		var win := rk <= 1
		print("[anlzdose] %-7.0f %-10d %-10s" % [d, rk, "是 ✓" if win else "否"])
		if win and first_effective < 0.0:
			first_effective = d
		if rk > prev:
			mono_ok = false
		prev = rk
	ai_engine.w_rescue_own_live = 18.0
	ai_engine.w_center = sv_center
	ai_engine.use_analyze_bonus = true
	print("[anlzdose] 最小有效剂量 = %s" % ["%.0f" % first_effective if first_effective >= 0 else "★全部剂量都无效"])
	print("[anlzdose] 剂量-响应单调不降 = %s%s"
			% ["✓" if mono_ok else "✗（★有交互项或符号错）",
			   "" if first_effective >= 0 else "（且从未夺冠 ⇒ 方向或机制有 bug）"])
	get_tree().quit(0)

## 点 `v` 在「加了 `bonus` 分」之后的排名（1 = 冠军）。走 `probe_root_score_last`（确定性）。
func _rank_of(bd: Dictionary, v: int, bonus: float) -> int:
	var ranked: Array = []
	for x in board.size():
		if int(board[x]) != int(Stone.EMPTY):
			continue
		var sc: float = ai_engine.probe_root_score_last(bd, x, int(Stone.WHITE), -1)
		if x == v:
			sc += bonus
		ranked.append([sc, x])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for i in ranked.size():
		if int(ranked[i][1]) == v:
			return i + 1
	return 999

## 自检（--anlzprobe）局势层的**确定性机制探针**（秒级、无搜索、无随机）。
##
## 验的是「三个新权重在先验层面真的在动，且方向正确」，**不是**棋力。
## 分层验证（技能 Part 5）：机制确定性 → 棋力用 `--aitune` 对打。
##
## 关键：走 `probe_root_argmax()`（确定性）而**不是** `choose_move()`（有时间预算+线程+随机）。
func _anlz_probe() -> void:
	print("[anlzprobe] ===== 局势层机制探针（确定性，先验层面）=====")
	print("[anlzprobe] 判据① 开/关 argmax 必须不同；且三权重全 0 时两者必须相同")
	print("[anlzprobe] 判据② 方向：要点上的加成 > 非要点；被围地上的加成 < 0")
	print("[anlzprobe] 判据③ 阴性对照：关掉后逐点加成恒为 0")
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	ai_engine.ld_enabled = true

	# ★★ 夹具必须有子！第一版**只建了空网格** ⇒ 361 个空点加成全0（判据红的是夹具，
	#   不是机制）。三道门槛的输入全在「盘上有子」的域里：① 要未定形块的眼位要点、
	#   ② 要邻接对方死块、③ 要被对方同色包围的空区。
	# 摆一个**未定形**眼形（真源 st=1：直三/弯三/丁四/梅花五/刀把五）——
	#   它的眼位空间里必然有要点 ⇒ ① 有机会触发。
	# ★ `ring_color` 才是「有眼位的那块」⇒ 必须等于 ai_color（WHITE），
	#   否则测的是对方的块（`_eye_vital_flags` 只给己方奖励）。
	# 用真源表里的形名，**不硬编码坐标**（铁律 18：真源只一份）。
	var shape: Dictionary = {}
	for cs: Dictionary in _ld_shape_table():
		if String(cs.get("n", "")) == "丁四":     # 真源 st=1（未定形），4 点
			shape = cs
			break
	if shape.is_empty():
		print("[anlzprobe] ✗ 找不到丁四（真源表变动）⇒ 本探针无法自测")
		get_tree().quit(1)
		return
	_lay_eye_shape_with_libs(shape["pts"], Vector2i(5, 5), Stone.WHITE, Stone.BLACK, 0)
	print("[anlzprobe] 夹具：丁四（真源 st=1 未定形），ring=白 墙=黑，封闭眼形")
	var b_on := ai_engine.probe_root_argmax(board, int(Stone.WHITE))
	ai_engine.use_analyze_bonus = true
	var b_off := ai_engine.probe_root_argmax(board, int(Stone.WHITE))
	ai_engine.use_analyze_bonus = false
	# 阳性对照：把三个权重全部置 0（「等效于关掉」但走的是另一条代码路径）
	var sv := [ai_engine.w_rescue_own_live, ai_engine.w_capture_dead, ai_engine.w_sealed_territory]
	ai_engine.w_rescue_own_live = 0.0
	ai_engine.w_capture_dead = 0.0
	ai_engine.w_sealed_territory = 0.0
	var b_zero := ai_engine.probe_root_argmax(board, int(Stone.WHITE))
	ai_engine.w_rescue_own_live = sv[0]
	ai_engine.w_capture_dead = sv[1]
	ai_engine.w_sealed_territory = sv[2]
	ai_engine.use_analyze_bonus = true

	var fail: Array = []
	var arg_on := int(b_on.get("best", -1))
	var arg_off := int(b_off.get("best", -1))
	var arg_zero := int(b_zero.get("best", -1))
	print("[anlzprobe] argmax：加成开=%d 关=%d 三权重置0=%d" % [arg_on, arg_off, arg_zero])
	print("[anlzprobe] ① 开/关 %s；置0/关 %s"
			% ["不同 ✓" if arg_on != arg_off else "★相同 ⇒ 机制是装饰",
			   "相同 ✓（差异确实来自这三项）" if arg_zero == arg_off else "★不同 ⇒ 差异另有来源"])
	if arg_on == arg_off:
		fail.append("开/关 argmax 相同 ⇒ 局势加成在先验层面没起作用")

	# —— 逐点加成明细：方向判据②③——
	var n_pos := 0
	var n_neg := 0
	var n_zero_add := 0
	var vital_add := -1.0e9
	var plain_add := -1.0e9
	for v in board.size():
		if int(board[v]) != int(Stone.EMPTY):
			continue
		ai_engine.use_analyze_bonus = false
		var a_off := ai_engine._analyze_bonus(v)
		ai_engine.use_analyze_bonus = true
		var a_on := ai_engine._analyze_bonus(v)
		if absf(a_off) > 1e-9:
			fail.append("阴���对照失效：关掉后 v=%d 加成仍=%.3f" % [v, a_off])
		if absf(a_on) < 1e-9:
			n_zero_add += 1
			continue
		if a_on > 0.0:
			n_pos += 1
		else:
			n_neg += 1
		# 是不是做活要点（唯一真源口径）
		if bool(ai_engine._eye_vital_flags(v)[1]):
			vital_add = maxf(vital_add, a_on)
		else:
			plain_add = maxf(plain_add, a_on)
	ai_engine.use_analyze_bonus = true
	print("[anlzprobe] 逐点加成：正 %d 个 / 负 %d 个 / 零 %d 个（空点共 %d）"
			% [n_pos, n_neg, n_zero_add, _count_empty()])
	print("[anlzprobe] ② 要点上最大加成=%.1f｜非要点最大加成=%.1f ⇒ %s"
			% [vital_add, plain_add,
			   "要点更高 ✓" if vital_add > plain_add else "★要点不高于非要点"])
	if n_neg == 0:
		fail.append("没有任何点拿到负加成 ⇒ w_sealed_territory 在这个形状上从未触发")
	if n_pos == 0:
		fail.append("没有任何点拿到正加成 ⇒ 救活/抢死子在这个形状上从未触发")
	print("[anlzprobe] ③ 阴性对照（关掉后恒 0）%s"
			% ("✓" if fail.is_empty() or not String(fail[0]).begins_with("阴性") else "✗"))
	print("[anlzprobe] 失败 %d 项：%s" % [fail.size(), str(fail)])
	print("[anlzprobe] 结论：%s" % ("通过 ✓" if fail.is_empty() else "失败 ✗"))
	get_tree().quit(0 if fail.is_empty() else 1)

func _count_empty() -> int:
	var c := 0
	for i in board.size():
		if int(board[i]) == int(Stone.EMPTY):
			c += 1
	return c

## 局势字段（**生产端**）：`music.gd` 通过 `sc.get("an_crisis")` 这类**反射**读取，
## 所以必须是**成员变量**，函数读不到（踩过：`music_battle_extra()` 写成函数 ⇒ 音乐恒取默认 0）。
##
## ★★★ 视角纪律（2026-10-07）。本组里**凡带方向的量，名字里必须写清是谁的视角**，
##   且每一路都要按颜色**显式分两支**算出来 —— **绝不用一个 `sign` 乘上去**。
##   （本工程铁律 17：「多方向选点各写显式极值，绝不共用 sign 参数相乘 —— 共用必有一处反且静默」。）
##
##   为什么这条会被踩到：原来只有一个 `an_lead`，注释写「正 = 我方领先」，
##   但它的真源是 `analyze_board()["lead"] = win_black - win_white`，那是**黑方视角**；
##   而本工程 `PLAYER_COLOR = BLACK` / `AI_COLOR = WHITE` ⇒ **符号与注释正好相反**。
##   后果静默且致命：`behind = clampf(-an_lead / advice_deficit, 0, 1)`
##   ⇒ **AI 真落后时 behind 恒为 0、危急度反而不涨**，AI 领先时它才涨。
##   现在两个方向各自是一个变量，"谁领先"在代码里是读得出来的，不再靠注释。
var an_crisis := 0.0            ## 局面危急度 0..1 = max(玩家方, AI方)（**对称**，不含"我方"歧义）
var an_player_crisis := 0.0     ## 玩家方濒危度 0..1
var an_ai_crisis := 0.0         ## AI 方濒危度 0..1（与上式**同一个公式**，只是喂另一侧的数）
## 胜率差，用于濒危度（与 `ai_engine.advice_deficit` 同量纲：落后 0.12 胜率算"拉满"）。
var an_win_diff_player := 0.0   ## 正 = **玩家**胜率领先
var an_win_diff_ai := 0.0       ## 正 = **AI** 胜率领先
## 目数差，**无界**（铁律 14：有界量判不了单调性；映射比例的尺子在消费端 music.gd 手里）。
var an_player_diff := 0.0       ## 正 = **玩家**目数领先（无界）
var an_ai_diff := 0.0           ## 正 = **AI** 目数领先（无界）· 与上式各算一份，不共用 sign
var an_lead := 0.0              ## 旧字段保留：★ **正 = 黑领先**（注释已更正）
var an_live_blocks := 0         ## ★ AI 的已活块数
var an_unsettled_blocks := 0    ## ★ AI 的「可做活」块数（未定形）
var an_dead_blocks := 0         ## ★ AI 的「救不回来」块数
var an_player_live_blocks := 0  ## 玩家的已活块数
var an_player_unsettled_blocks := 0  ## 玩家的「可做活」块数
var an_player_dead_blocks := 0  ## 玩家的「救不回来」块数
var an_their_dead := 0          ## 对方（= 玩家）死子数
var an_sealed_empty := 0        ## 已被对方围死、攻不进去的空点数
var an_advice := ""             ## 行动指令（中文，可直接上UI）
var an_win_black := 0.5         ## 黑胜率
var an_win_white := 0.5         ## 白胜率


## 一侧的**濒危度**。三项**相乘**（任一为 0 则不危急）—— 用相加会漏掉
## 「落后但对方快死透了」这种该**放松**的局面。
## ★ 本函数**不碰颜色**：`behind` 由调用方按"该侧自己的"胜率差算好传进来。
##   这样"共用了一个反了向的 sign"在结构上就不可能发生（两个调用点各自喂自己的数）。
func _crisis_of(own_dead: float, own_unsettled: float, win_diff: float, opp_dead: float) -> float:
	var hopeless := 1.0 if (own_dead > 0.0 and own_unsettled <= 0.0) else 0.0
	# ★ 用 `maxf(-win_diff, 0.0)` 而不是直接 `-win_diff`：后者在 `win_diff = 0` 时是
	#   **-0.0**，它会一路传到 `an_crisis`，让 `--analyzetest` 印出 "危险度 -0.000"
	#   ——看着像缺陷，而且"到底是不是 0"要靠读符号。
	var behind := clampf(maxf(-win_diff, 0.0) / maxf(ai_engine.advice_deficit, 0.001), 0.0, 1.0)
	var opp_alive := 1.0 if opp_dead <= 0.0 else 0.0
	return hopeless * behind * opp_alive


## 算一次局势并写进上面这些成员。**只读**（只调 `analyze_board`），不改棋盘。
## 只在落子/提子/停手后调（局势只在那些时刻变），不进 `_process`。
func _refresh_analyze() -> void:
	var an := ai_engine.analyze_board(board, ko_point)
	if an.is_empty():
		return
	an_win_black = float(an["win_black"])
	an_win_white = float(an["win_white"])
	an_lead = float(an["lead"])
	an_advice = String(an["advice"])
	# —— AI 侧：`own_*` 就是 AI 的（ai_engine 以 `ai_color` 为"己方"）——
	an_live_blocks = int(an["own_live_blocks"])
	an_unsettled_blocks = int(an["own_unsettled_blocks"])
	an_dead_blocks = int(an["own_dead_blocks"])
	# —— 对方（玩家）侧：同一口径，字段名是 `their_*` ——
	an_player_live_blocks = int(an["their_live_blocks"])
	an_player_unsettled_blocks = int(an["their_unsettled_blocks"])
	an_player_dead_blocks = int(an["their_dead_blocks"])
	an_their_dead = int(an["their_dead_stones"])
	an_sealed_empty = int(an["sealed_empty"])
	# —— 胜率差 / 目数差：每侧**各写一条显式分支**（铁律 17），不共用一个 sign ——
	var wb := an_win_black
	var ww := an_win_white
	var pb := float(an["black_points"])
	var pw := float(an["white_points"])
	if PLAYER_COLOR == Stone.BLACK:
		an_win_diff_player = wb - ww
		an_player_diff = pb - pw
	else:
		an_win_diff_player = ww - wb
		an_player_diff = pw - pb
	if AI_COLOR == Stone.BLACK:
		an_win_diff_ai = wb - ww
		an_ai_diff = pb - pw
	else:
		an_win_diff_ai = ww - wb
		an_ai_diff = pw - pb
	# —— 濒危度：**同一个公式**跑两次，各喂自己那一侧的三分类与自己的胜率差 ——
	an_ai_crisis = _crisis_of(float(an["own_dead"]), float(an["own_unsettled"]),
			an_win_diff_ai, float(an["their_dead_stones"]))
	an_player_crisis = _crisis_of(float(an["their_dead_stones"]), float(an["their_unsettled"]),
			an_win_diff_player, float(an["own_dead"]))
	# 合成用 **max 不用平均**：音乐要表达的是"局面有多紧"，一方濒临崩盘就已经该紧；
	# 取平均会把「我大优但对手在挣扎」这种局面听成平淡。
	an_crisis = maxf(an_player_crisis, an_ai_crisis)

## 从 analyze_board() 的结果里取「对 color 而言的主体标签」：子数最多的那一块。
##为什么取最多的：夹具上会同时有若干碎块，真源眼形所在的那块才是被测对象。
func _dominant_tag(a: Dictionary, color: int) -> String:
	return String(_dominant_block(a, color).get("tag", "NONE"))

## 同上，但返回**整块**。为什么必须同一处选：
##   原先 ① 与 ⑧ 各自遍历一次挑「子数最多的块」，两次可能挑到不同的块
##   （blocks 顺序随 `_group` 的起点变）⇒ 判定与打标签不自洽。
func _dominant_block(a: Dictionary, color: int) -> Dictionary:
	var arr: Array = a["blocks_white"] if color == Stone.WHITE else a["blocks_black"]
	if arr.is_empty():
		return {"tag": "NONE", "stones": 0, "libs": 0, "region": 0, "status": -1}
	var best: Dictionary = arr[0]
	for b: Dictionary in arr:
		if int(b.get("stones", 0)) > int(best.get("stones", 0)):
			best = b
	return best


func _ai_own_area_judge_test() -> void:
	var base := Vector2i(4, 4)
	var shapes: Array = []
	for cs: Dictionary in _ld_shape_table():
		shapes.append(cs)
	var k_libs: Array[int] = [0, 1, 2, 3]
	var bad_a: Array = []      # 封住了未定形的眼位（下不出做活要点）
	var bad_b: Array = []      # 没封住已活定的眼形（可往活形里填）
	var rows := 0
	print("[areatest] 过滤层口径专项：口径 A = `_group_alive`（旧）／口径 B = `_group_status`（真死活求解器）")
	print("[areatest] 判据：两口径结论必须同向 —— 未定形(1) 不得被封；活(2) 宜被封（活形内部不该是可选项）")
	for cs: Dictionary in shapes:
		for kl: int in k_libs:
			reset_game(true)
			_test_build_square_grid(TEST_GRID_N)
			# ⚠️ 必须把新棋盘交给引擎：少了这一句，引擎还用着**上一张盘**的邻接表，
			#    探针会在垃圾数据上给出全绿（第一版就栽在这，60 行全是「拦=否 / 求解器=?」）。
			ai_engine.setup(adjacency, Stone.WHITE)
			ai_engine.ld_enabled = true
			var rep: int = _lay_eye_shape_with_libs(cs["pts"], base, Stone.WHITE, Stone.BLACK, kl)
			# ⚠️ 探针点必须是**眼位里的空点**：`_own_area_layers()` 是从 `v` 出发做空点 BFS 的，
			#    传内环上的**子**进去是无效输入（第一版就栽在这，60 行全出「拦=否」的假结论）。
			var probe_pt := _ld_id_of(cs["pts"][0], base)
			# 要点取真源表里的攻方要点（空集 = 真源判活形，没有要点 → 改用眼位空点当标尺）
			var vital := -1
			if not (cs["kill"] as Array).is_empty():
				vital = _ld_id_of(cs["kill"][0], base)
			# 先设 `_turn`（`prepare_root_for_dump()` 不设），再走与 `choose_move` 同一调用顺序
			ai_engine.probe_root_argmax(board, Stone.WHITE)
			# ⚠️ 另建一个引擎实例做口径探测：`probe_own_area()` 会 bump `_sc_id`/重建眼位模型，
			#    在 `prepare_root_for_dump()` **之后**调它不影响候选集（候选集已取到手）
			var pr: Dictionary = ai_engine.prepare_root_for_dump(board)
			var cands: Array = pr["cands"]
			var pa: Dictionary = ai_engine.probe_own_area(board, probe_pt, Stone.WHITE)
			var blocked := bool(pa["blocked"])
			var st := int(pa["status"])
			var libs := int(pa["libs"])
			var yard := vital if vital >= 0 else probe_pt
			var in_cands := cands.has(yard)
			rows += 1
			var note := ""
			# ⚠️ 判据只对**真源也是未定形**（st == 1）的形成立：`_group_status()` 在「非封闭」
			#    分支给的是取宽近似（气 ≤ ld_max_libs 即算未定），拿它当「必须保住要点」的
			#    依据会把真源判**死**的形（直二 / 方四）也算成违规 → 假阳性。
			if st == 1 and int(cs["st"]) == 1 and vital >= 0 and blocked:
				bad_a.append("%s+k%d" % [cs["n"], kl])
				note = " ✗（未定形却被封 → 做活要点不在候选集）"
			elif st == 1 and int(cs["st"]) == 1 and vital >= 0 and not in_cands:
				bad_a.append("%s+k%d(先验丢弃)" % [cs["n"], kl])
				note = " ✗（未被过滤但先验把它丢了 → 要点仍不可选）"
			elif st == 2 and not blocked and in_cands:
				bad_b.append("%s+k%d" % [cs["n"], kl])
				note = " ✗（已活定却没封 → 内部空点仍是可选项 = 可往活形里填）"
			print("[areatest] %-6s 外气+%d 总气=%d 真源=%d 求解器=%s 旧判据=%s 拦=%s 标尺%d入候选=%s%s" % [
				cs["n"], kl, libs, int(cs["st"]), _ld_st_name(st),
				"活" if bool(pa["alive_old"]) else "未活", "是" if blocked else "否",
				yard, "是" if in_cands else "否", note])
	print("[areatest] 方向 A 违规（未定形被过滤层封住，AI 下不出做活要点）：%d 例 %s" % [
		bad_a.size(), bad_a])
	print("[areatest] 方向 B 违规（活形没被封住，AI 可往自己活形里填）：%d 例 %s" % [
		bad_b.size(), bad_b])
	print("[areatest] 汇总（%d 行）：方向 A %d 例 / 方向 B %d 例 → %s" % [
		rows, bad_a.size(), bad_b.size(),
		("两口径一致 ✓" if bad_a.is_empty() and bad_b.is_empty()
			else "口径打架 ✗ —— 这是「不会做活」与「填自己的眼」的共同病根")])
	get_tree().quit()


## 自检（--ailife ①③④）：12 种小眼形逐条摆出来，对照真源表断言 ——
##   ① 判定层：三态结论与真源逐条一致；
##   ② 要点层：引擎算出的「攻方杀点集」与真源「攻方先手要点」**集合相等**；
##   ③ 旧口径对照：旧判据（单点真眼 ≥2 或 气 ≥6）会把真源活形误判成「未活」→
##      证明这一层不是装饰（错得越多，说明新层干的活越实）；
##   ④ 穷举超预算次数（预算够不够）。
## 全部走 `probe_ld`（纯判定，无搜索 / 无随机器 / 无线程）→ 确定性，可直接当回归断言。
func _ai_ld_truth_test() -> void:
	var base := Vector2i(4, 4)
	var shapes: Array = _ld_shape_table()
	var bad_st: Array = []
	var bad_kill: Array = []
	var legacy_wrong: Array = []
	var bail0: int = -1
	var bail1: int = -1
	for cs: Dictionary in shapes:
		var pts: Array = cs["pts"]
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.WHITE)
		var rep: int = _lay_eye_shape(pts, base, Stone.BLACK, Stone.WHITE)
		var t_ld0 := Time.get_ticks_usec()
		var r: Dictionary = ai_engine.probe_ld(board, rep)
		var t_ld_us: int = Time.get_ticks_usec() - t_ld0
		var bo: int = int(r["bailouts"])
		if bail0 < 0:
			bail0 = bo
		bail1 = bo
		var st: int = int(r["status"])
		var want_st: int = int(cs["st"])
		var got: Array = r["kills"]
		var want: Array = []
		for p: Vector2i in cs["kill"]:
			want.append(_ld_id_of(p, base))
		got.sort()
		want.sort()
		if st != want_st:
			bad_st.append(cs["n"])
		if got != want:
			bad_kill.append(cs["n"])
		var cnt: int = ai_engine._group(rep)
		var old_alive: bool = ai_engine._count_eyes(cnt) >= 2 or ai_engine._libs(cnt, -1) >= 6
		if old_alive != (want_st == 2):
			legacy_wrong.append("%s(旧=%s/真源=%s)" % [
				cs["n"], "活" if old_alive else "非活", "真源活" if want_st == 2 else "真源非活"])
		print("[ailife] ① %s 判定 真源=%s 引擎=%s %s | 杀点 真源=%s 引擎=%s %s | %dms" % [
			cs["n"], _ld_st_name(want_st), _ld_st_name(st),
			"✓" if st == want_st else "✗", want, got, "✓" if got == want else "✗",
			t_ld_us / 1000])
	print("[ailife] ① 汇总：判定层 %d/%d、要点层 %d/%d 一致 → %s" % [
		shapes.size() - bad_st.size(), shapes.size(), shapes.size() - bad_kill.size(), shapes.size(),
		("通过 ✓" if bad_st.is_empty() and bad_kill.is_empty()
			else "失败 ✗（判定不一致=%s 要点不一致=%s）" % [bad_st, bad_kill])])
	print("[ailife] ③ 旧口径（单点真眼≥2 / 气≥6）与真源不一致 %d 条：%s → %s" % [
		legacy_wrong.size(), ", ".join(legacy_wrong),
		"新层确实在干活 ✓" if legacy_wrong.size() >= 3 else "可疑 ✗（旧口径几乎全对 = 断言没在测东西）"])
	print("[ailife] ④ 死活穷举超预算次数（本次自检内）=%d → %s" % [
		bail1 - bail0, "预算充足 ✓" if bail1 == bail0 else "预算偏紧 ✗（调大 ld_node_budget）"])


## 自检（--ailife ⑤）：AI 当**防守方**（白）时要会做活 ——
## 摆五种「先手必须占要点」的小眼形，断言根先验的最优落点就是真源要点。
## 为什么用 `probe_root_argmax` 而不是 `choose_move`：前者无搜索 / 无线程 / 无预算 → **确定性**，
## 能直接当回归断言；后者会随预算与线程飘（实测同局面两次结论可能不同），这里只作参考打印。
## 阴性对照：关掉 `ld_enabled`（回退旧口径「单点真眼 ≥2」）后，比旧口径更难的
## 梅花五 / 刀把五 必须失手 —— 否则说明这条断言根本没在测新增的眼位空间机制。
func _ai_life_puzzle() -> void:
	var base := Vector2i(4, 4)
	var cases: Array = [
		{"n": "直三", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "key": Vector2i(1, 0)},
		{"n": "弯三", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)], "key": Vector2i(0, 0)},
		{"n": "丁四", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
			"key": Vector2i(1, 0)},
		{"n": "梅花五", "pts": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
			Vector2i(1, 2)], "key": Vector2i(1, 1)},
		{"n": "刀把五", "pts": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1),
			Vector2i(2, 1)], "key": Vector2i(1, 0)},
	]
	var fail_on: Array = []
	var fail_off: Array = []
	for cs: Dictionary in cases:
		var key_id: int = _ld_id_of(cs["key"], base)
		var st_on: int = -1
		var best_on: int = -1
		var mv_on: int = -1
		var best_off: int = -1
		for on: bool in [true, false]:
			reset_game(true)
			_test_build_square_grid(TEST_GRID_N)
			ai_engine.setup(adjacency, Stone.WHITE)
			ai_engine.ld_enabled = on
			var rep: int = _lay_eye_shape(cs["pts"], base, Stone.WHITE, Stone.BLACK)
			var rl: Dictionary = ai_engine.probe_ld(board, rep)
			var ra: Dictionary = ai_engine.probe_root_argmax(board, Stone.WHITE)
			var mv: int = ai_engine.choose_move(board, -1, Stone.WHITE)
			if on:
				st_on = int(rl["status"])
				best_on = int(ra["best"])
				mv_on = mv
			else:
				best_off = int(ra["best"])
		ai_engine.ld_enabled = true
		var hit_on: bool = best_on == key_id
		var hit_off: bool = best_off == key_id
		if not hit_on:
			fail_on.append(cs["n"])
		if not hit_off:
			fail_off.append(cs["n"])
		print("[ailife] ⑤ %s 做活（白防守，引擎真源状态=%s）→ 要点=%d 先验最优=%d %s | 实选=%d %s" % [
			cs["n"], _ld_st_name(st_on), key_id, best_on, "✓" if hit_on else "✗",
			mv_on, "✓" if mv_on == key_id else "（参考·未命中）"])
		print("[ailife] ⑤ %s 阴性对照（关掉机制）→ 先验最优=%d %s" % [
			cs["n"], best_off, "（应失手）" if not hit_off else "（仍命中 = 本形旧口径也够）"])
	print("[ailife] ⑤ 汇总：开机制 %d/%d 命中要点 → %s" % [
		cases.size() - fail_on.size(), cases.size(),
		("通过 ✓" if fail_on.is_empty() else "失败 ✗（未命中=%s）" % [fail_on])])
	print("[ailife] ⑤ 阴性对照：关掉机制后失手 %d/%d → %s" % [
		fail_off.size(), cases.size(),
		("通过 ✓" if fail_off.has("梅花五") and fail_off.has("刀把五")
			else "可疑 ✗（旧口径也能答对 = 断言没在测新机制）")])
	# 交叉验证：同一「直三」换成厚框老夹具（`_lay_three_in_a_row`）再摆一遍 ——
	# 局部眼位模型应当完全一致（区域=3 点、要点=中间），用来钉住夹具本身没写歪。
	reset_game(true)
	_test_build_square_grid(TEST_GRID_N)
	ai_engine.setup(adjacency, Stone.WHITE)
	_lay_three_in_a_row(Stone.WHITE)
	var r2: Dictionary = ai_engine.probe_ld(board, 8 * TEST_GRID_N + 8)
	var ra2: Dictionary = ai_engine.probe_root_argmax(board, Stone.WHITE)
	var want2: int = 9 * TEST_GRID_N + 9
	print("[ailife] ⑤ 交叉验证（厚框直三夹具）→ 状态=%s 区域=%d 先验最优=%d 要点=%d %s" % [
		_ld_st_name(int(r2["status"])), int(r2["region"]), int(ra2["best"]), want2,
		"✓" if int(ra2["best"]) == want2 else "✗"])
	# ⑥ 对称面：AI 当**攻方**（白）时要点杀 —— 黑围出未定形小块，白必须先手点要点。
	# 与 ⑤ 共用真源表的「攻方先手要点」列，是同一判据的另一半（白方视角）。
	var kill_hit: Array = []
	var kill_miss: Array = []
	for cs: Dictionary in cases:
		var key_id: int = _ld_id_of(cs["key"], base)
		reset_game(true)
		_test_build_square_grid(TEST_GRID_N)
		ai_engine.setup(adjacency, Stone.WHITE)
		ai_engine.ld_enabled = true
		_lay_eye_shape(cs["pts"], base, Stone.BLACK, Stone.WHITE)
		var ra: Dictionary = ai_engine.probe_root_argmax(board, Stone.WHITE)
		var mv: int = ai_engine.choose_move(board, -1, Stone.WHITE)
		if int(ra["best"]) == key_id:
			kill_hit.append(cs["n"])
		else:
			kill_miss.append(cs["n"])
		print("[ailife] ⑥ %s 点杀（白攻方）→ 要点=%d 先验最优=%d %s | 实选=%d %s" % [
			cs["n"], key_id, int(ra["best"]), "✓" if int(ra["best"]) == key_id else "✗",
			mv, "✓" if mv == key_id else "（参考·未命中）"])
	print("[ailife] ⑥ 汇总：点杀要点 %d/%d 命中 → %s" % [
		kill_hit.size(), cases.size(),
		("通过 ✓" if kill_miss.is_empty() else "失败 ✗（未命中=%s）" % [kill_miss])])


## 摆一个「直三」死活题：framer 色围出内部 3 个空点 (9,8)(9,9)(9,10)，
## 对手色在框外一圈封死，使 framer 那块的気只剩内部 3 点
func _lay_three_in_a_row(framer: int) -> void:
	var other: int = 3 - framer
	var n: int = TEST_GRID_N
	reset_game(true)
	for j in range(7, 12):
		board[8 * n + j] = framer
		board[10 * n + j] = framer
	board[9 * n + 7] = framer
	board[9 * n + 11] = framer
	for j in range(6, 13):
		board[7 * n + j] = other
		board[11 * n + j] = other
	for i in range(8, 11):
		board[i * n + 6] = other
		board[i * n + 12] = other

## 自检（--ailife）：让 AI 自己把一局下完，统计终局「只剩一口气的成块棋」。
## 对照组把死活相关机制全部关掉（不扣死子、rollout 不补活、先验不补强、树也退回浅层），
## 用来确认新机制真的让 AI 更会保护自己的弱棋，而不是"自我感觉变强了"。
func _ai_life_test() -> void:
	# ① 判定层 / 要点层：12 种小眼形逐条对照真源表（确定性，不看 AI 行为）
	_ai_ld_truth_test()
	# ② 行为层：该做活时会做活（白防守）、该点杀时会点杀（白攻方），带阴性对照
	_ai_life_puzzle()
	# ⑦ 开销 A/B（同进程开关对照，避开跨进程噪声）：关=旧口径 / 开=通用眼位死活。
	# 量两处：① 典型盘面（彭罗斯标准盘随机铺 12 手，多数局面根本没有封闭小眼位 → 应几乎零开销）；
	# ② 死活热点盘面（方形夹具摆梅花五，AI 自己那块正处在未定形眼位 → 走满穷举路径）。
	# 判据用「固定预算下的 playouts 数」，与 `--ladtest` 同款。
	var po_a: Array[int] = []
	var mv_a: Array[int] = []
	var po_b: Array[int] = []
	var mv_b: Array[int] = []
	var ms_a: Array[int] = [0, 0, 0]
	var ms_b: Array[int] = [0, 0, 0]
	for spot: bool in [false, true]:
		if spot:
			reset_game(true)
			_test_build_square_grid(TEST_GRID_N)
			ai_engine.setup(adjacency, AI_COLOR)
			_lay_eye_shape([Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
				Vector2i(1, 2)], Vector2i(4, 4), AI_COLOR, 3 - AI_COLOR)
		else:
			GameConfig.board_type = GameConfig.BOARD_PENROSE
			GameConfig.board_size = GameConfig.STANDARD
			_apply_board_size(GameConfig.STANDARD)
			generate_penrose()
			reset_game(true)
			ai_engine.setup(adjacency, AI_COLOR)
			ai_engine.scramble(12)
			_load_board_from_engine()
		ai_engine.time_budget_ms = 600
		var po: Array[int] = []
		var mvs: Array[int] = []
		for on: bool in [false, true]:
			ai_engine.ld_enabled = on
			ai_engine.reset_state()
			var mov: int = ai_engine.choose_move(board, -1, AI_COLOR)
			po.append(ai_engine.last_playouts)
			mvs.append(mov)
		# 灵敏度更高的一把尺：**根先验全盘扫描的墙钟时间**。
		# playouts 计数的粒度太粗（实测开关两档都是 288/420），毫秒级差异根本量不出来；
		# 而先验扫描正是新机制唯一被调用的地方（`_root_score`）。开档量两次：
		# 首扫（含每块眼位一次穷举 + 建缓存）与再扫（全是缓存命中）—— 后者才是一手棋的稳态开销。
		ai_engine.ld_enabled = false
		var t0 := Time.get_ticks_msec()
		ai_engine.probe_root_argmax(board, AI_COLOR)
		var ms_off := Time.get_ticks_msec() - t0
		ai_engine.ld_enabled = true
		t0 = Time.get_ticks_msec()
		ai_engine.probe_root_argmax(board, AI_COLOR)
		var ms_on1 := Time.get_ticks_msec() - t0
		t0 = Time.get_ticks_msec()
		ai_engine.probe_root_argmax(board, AI_COLOR)
		var ms_on2 := Time.get_ticks_msec() - t0
		ai_engine.ld_enabled = true
		if spot:
			po_b = po
			mv_b = mvs
			ms_b = [ms_off, ms_on1, ms_on2]
		else:
			po_a = po
			mv_a = mvs
			ms_a = [ms_off, ms_on1, ms_on2]
	var dr_a := 0.0
	var dr_b := 0.0
	if po_a[0] > 0:
		dr_a = (1.0 - float(po_a[1]) / float(po_a[0])) * 100.0
	if po_b[0] > 0:
		dr_b = (1.0 - float(po_b[1]) / float(po_b[0])) * 100.0
	# 判据：稳态（再扫）不超过关档的 1.5 倍 + 5ms。
	var ok_a: bool = float(ms_a[2]) <= float(ms_a[0]) * 1.5 + 5.0
	var ok_b: bool = float(ms_b[2]) <= float(ms_b[0]) * 1.5 + 5.0
	print("[ailife] ⑦ 开销·典型盘：根先验全扫 关=%dms 开首扫=%dms 开再扫=%dms | playouts 关=%d（落子 %d）开=%d（落子 %d，变化 %.1f%%）" % [
		ms_a[0], ms_a[1], ms_a[2], po_a[0], mv_a[0], po_a[1], mv_a[1], dr_a])
	print("[ailife] ⑦ 开销·死活热点盘：根先验全扫 关=%dms 开首扫=%dms 开再扫=%dms | playouts 关=%d（落子 %d）开=%d（落子 %d，变化 %.1f%%）→ %s" % [
		ms_b[0], ms_b[1], ms_b[2], po_b[0], mv_b[0], po_b[1], mv_b[1], dr_b,
		"可接受 ✓" if ok_a and ok_b else "过重 ✗（调小 ld_cap_points / ld_probe_libs / ld_node_budget）"])
	# ⑧ 自战统计（**噪声大**：自战带时间预算与多线程，同参数两次跑出的目差可以差很多，
	#    所以只当参考打印，不作断言 —— 断言全在上面 ①~⑦ 的确定性部分）
	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	generate_penrose()
	reset_game(true)
	var cases: Array = [
		{"name": "旧行为(无死活机制)", "dead": false, "p_eye": 0.0, "weak": 0.0, "eye": 0.0, "wk": 9.0},
		{"name": "新行为(有死活机制)", "dead": true, "p_eye": 0.30, "weak": 3.0, "eye": 14.0, "wk": 0.7},
	]
	for cs in cases:
		ai_engine.setup(adjacency, AI_COLOR)
		ai_engine.dead_penalty = cs["dead"]
		ai_engine.p_eye = cs["p_eye"]
		ai_engine.w_weak_each = cs["weak"]
		ai_engine.w_eye_make = cs["eye"]
		ai_engine.widen_k = cs["wk"]
		var r: Dictionary = ai_engine.selfplay_to_end(120, 220)
		var sc: Vector2i = r["our_area"]
		print("[ailife] %s → 手数=%d 提子=%d 盘上子=%d | 终局「只剩1气的成块棋」黑=%d 白=%d | 面积 黑=%d 白=%d" % [
			cs["name"], r["moves"], r["caps"], r["stones"],
			r["dead_black"], r["dead_white"], sc.x, sc.y])
	get_tree().quit()

## 自检（--aieye）：把「AI 填自己的眼」与「AI 不会做活」量出来 —— 用户点名的头号问题。
##
## 为什么另立一把尺子：`--ailife` ⑧ 只数「终局只剩 1 气的成块棋」，那是没做活的**后果**；
## 用户抱怨的是**过程**里那一手 —— 往自己眼里填子。一手废手就把活形变成送吃，
## 之后再怎么补都救不回来，而「终局统计」只看得见已经数不清的残局。
##
## 指标（一局自战，双方共用当前参数）：
##   · `填眼`：落子在**己方单点眼点**上（该点全部邻居都是自己子），按后果分
##     `致命`（填完 ≤1 气）/ `无害`（≥2 气）；
##   · `填眼细分`：填眼前该块**已有 ≥2 只眼**（候选过滤本该拦住 → 病根在过滤层）
##     vs **只有 ≤1 只眼**（`_own_territory_only()` 的做活豁免**设计上放行** → 病根在豁免口径）；
##   · `纯领地违规`：引擎自己的判据说「这是纯己方领地、不该落子」而 AI 还是落了
##     —— 与判据直接矛盾，**按构造应为 0**，所以它是本仪器的**阴性对照**；
##   · `没做活`：终局只剩 1 气 / 2 气的成块棋、以及一次提掉 ≥3 子（成块被提）的次数。
##
## 参数：`--aieye[=<tok>:...]`，盘型 token 同 `--aibud`（pen/cube/kite/snow/hat，默认彭罗斯），
##   另可 `gN` 每盘局数（默认 2）、`mN` 手数上限（默认 220）、`bN` 每手预算毫秒（默认 120）。
func _ai_eye_fill_probe() -> void:
	var bts: Array[int] = []
	var games := 2
	var max_moves := 220
	var budget := 120
	for a in _argv():
		if not a.begins_with("--aieye"):
			continue
		var suffix: String = a.substr(7)          # 7 = "--aieye".length()
		if suffix.begins_with("="):
			suffix = suffix.substr(1)
		for tok in suffix.split(":", false):
			match tok:
				"pen": _aibud_add_board(bts, GameConfig.BOARD_PENROSE)
				"cube": _aibud_add_board(bts, GameConfig.BOARD_CUBE)
				"kite": _aibud_add_board(bts, GameConfig.BOARD_KITE)
				"snow": _aibud_add_board(bts, GameConfig.BOARD_SNOWFLAKE)
				"hat": _aibud_add_board(bts, GameConfig.BOARD_HAT)
				_:
					# ⚠️ 盘型 token 必须走上面的**精确分支**：`snow` 若落到这里，
					#    会被 `g/m/b` 前缀分支当数值解析掉（--aibud 踩过这个坑）
					if _aibud_try_board_list(tok, bts):
						continue
					if tok.begins_with("g"):
						games = maxi(int(tok.substr(1)), 1)
					elif tok.begins_with("m"):
						max_moves = maxi(int(tok.substr(1)), 20)
					elif tok.begins_with("b"):
						budget = maxi(int(tok.substr(1)), 10)
	if bts.is_empty():
		bts = [GameConfig.BOARD_PENROSE]
	var tot := {"lethal": 0, "waste": 0, "eye2": 0, "eye1": 0, "viol": 0,
		"dead": 0, "dying": 0, "bigcaps": 0, "bigstones": 0, "moves": 0, "games": 0,
		"seen": 0, "open": 0, "vital": 0, "nonvital": 0, "blocked": 0, "exempt": 0,
		"echosen": 0, "evital": 0, "ewaste": 0, "evoid": 0, "fvoid": 0, "vpost": 0}
	print("[aieye] 填自己的眼 / 不会做活 —— 自战 %d 局/盘，每手 %dms，上限 %d 手，单线程" % [
		games, budget, max_moves])
	for bt in bts:
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.STANDARD
		_apply_board_size(GameConfig.STANDARD)
		_generate_selected_board()
		reset_game(true)
		print("[aieye] ===== 盘型=%s 档位=%s 格数=%d | 相邻度 %s =====" % [
			_bt_name(bt), _board_size_name(GameConfig.STANDARD), tiles.size(), _degree_hist_txt()])
		for gi in games:
			ai_engine.setup(adjacency, AI_COLOR, 20260921)
			ai_engine.threads = 1     # 单线程：自战也要可复现，否则同一份代码两遍数不一样
			ai_engine.time_budget_ms = budget
			var r: Dictionary = ai_engine.selfplay_to_end(budget, max_moves)
			var fl: Array = r["fill_lethal"]
			var fw: Array = r["fill_waste"]
			var fe2: Array = r["fill_eye2"]
			var fe1: Array = r["fill_eye1"]
			var tv: Array = r["terr_viol"]
			var fvi: Array = r["fill_vital"]
			var fnv: Array = r["fill_nonvital"]
			var ec: Array = r["exempt_chosen"]
			var ev: Array = r["exempt_vital"]
			var ew: Array = r["exempt_waste"]
			var evd: Array = r["exempt_void"]
			var fvd: Array = r["fill_void"]
			var fill_b := int(fl[0]) + int(fw[0])
			var fill_w := int(fl[1]) + int(fw[1])
			tot["lethal"] = int(tot["lethal"]) + int(fl[0]) + int(fl[1])
			tot["waste"] = int(tot["waste"]) + int(fw[0]) + int(fw[1])
			tot["eye2"] = int(tot["eye2"]) + int(fe2[0]) + int(fe2[1])
			tot["eye1"] = int(tot["eye1"]) + int(fe1[0]) + int(fe1[1])
			tot["viol"] = int(tot["viol"]) + int(tv[0]) + int(tv[1])
			tot["dead"] = int(tot["dead"]) + int(r["dead_black"]) + int(r["dead_white"])
			tot["dying"] = int(tot["dying"]) + int(r["dying_black"]) + int(r["dying_white"])
			tot["bigcaps"] = int(tot["bigcaps"]) + int(r["big_caps"])
			tot["bigstones"] = int(tot["bigstones"]) + int(r["big_cap_stones"])
			tot["moves"] = int(tot["moves"]) + int(r["moves"])
			tot["seen"] = int(tot["seen"]) + int(r["eye_pts_seen"])
			tot["open"] = int(tot["open"]) + int(r["eye_pts_open"])
			tot["vital"] = int(tot["vital"]) + int(fvi[0]) + int(fvi[1])
			tot["nonvital"] = int(tot["nonvital"]) + int(fnv[0]) + int(fnv[1])
			tot["blocked"] = int(tot["blocked"]) + int(r["blocked_pts"])
			tot["exempt"] = int(tot["exempt"]) + int(r["exempt_pts"])
			tot["echosen"] = int(tot["echosen"]) + int(ec[0]) + int(ec[1])
			tot["evital"] = int(tot["evital"]) + int(ev[0]) + int(ev[1])
			tot["ewaste"] = int(tot["ewaste"]) + int(ew[0]) + int(ew[1])
			tot["evoid"] = int(tot["evoid"]) + int(evd[0]) + int(evd[1])
			tot["fvoid"] = int(tot["fvoid"]) + int(fvd[0]) + int(fvd[1])
			tot["vpost"] = int(tot["vpost"]) + int(r["vital_post_hits"])
			tot["games"] = int(tot["games"]) + 1
			print("[aieye] 第%d局：手数=%d 提子=%d（成块被提≥3子 %d 次/%d 子）停一手=%d" % [
				gi + 1, r["moves"], r["caps"], r["big_caps"], r["big_cap_stones"], r["passes"]])
			print("[aieye]   ↳ 填自己的眼：黑%d/白%d（致命 %d ｜ 无害 %d）｜填眼前已≥2眼 %d ｜ ≤1眼 %d ｜ **要点 %d ／ 白填 %d ／ 判据失效区 %d**" % [
				fill_b, fill_w, int(fl[0]) + int(fl[1]), int(fw[0]) + int(fw[1]),
				int(fe2[0]) + int(fe2[1]), int(fe1[0]) + int(fe1[1]),
				int(fvi[0]) + int(fvi[1]), int(fnv[0]) + int(fnv[1]),
				int(fvd[0]) + int(fvd[1])])
			print("[aieye]   ↳ 过滤层口径：拦成「纯领地」%d 点次 ／ **豁免放行 %d 点次**（%.1f%%）｜眼点机会 共 %d，其中可选 %d（%d 手）" % [
				int(r["blocked_pts"]), int(r["exempt_pts"]),
				100.0 * float(int(r["exempt_pts"])) / float(maxi(int(r["blocked_pts"]) + int(r["exempt_pts"]), 1)),
				int(r["eye_pts_seen"]), int(r["eye_pts_open"]), int(r["eye_pts_turns"])])
			print("[aieye]   ↳ **落在豁免空区里的手：%d（要点 %d = 在做活 ／ 白填 %d ／ 判据失效区 %d）**" % [
				int(ec[0]) + int(ec[1]), int(ev[0]) + int(ev[1]),
				int(ew[0]) + int(ew[1]), int(evd[0]) + int(evd[1])])
			print("[aieye]   ↳ 纯领地违规=%d（阴性对照，按构造应为 0）｜终局只剩1气成块棋 %d 子，只剩2气 %d 子" % [
				int(tv[0]) + int(tv[1]), int(r["dead_black"]) + int(r["dead_white"]),
				int(r["dying_black"]) + int(r["dying_white"])])
			for tr in r["fill_trace"]:
				print("[aieye]     例：%s" % tr)
	# ---- 汇总与判据 ----
	var gcnt: int = maxi(int(tot["games"]), 1)
	var mcnt: int = maxi(int(tot["moves"]), 1)
	var fill_all: int = int(tot["lethal"]) + int(tot["waste"])
	print("[aieye] ===== 汇总（%d 局 / %d 手，平均 %.0f 手一局）=====" % [
		gcnt, mcnt, float(mcnt) / float(gcnt)])
	print("[aieye] 填自己的眼：共 %d 次（%.1f 手/局）｜其中致命 %d（%.2f 手/局）｜无害 %d" % [
		fill_all, float(fill_all) / float(gcnt),
		int(tot["lethal"]), float(int(tot["lethal"])) / float(gcnt), int(tot["waste"])])
	print("[aieye] 填眼病根拆分：填眼前已≥2眼 %d（= 过滤层漏洞）｜≤1眼 %d（= 做活豁免放行）" % [
		int(tot["eye2"]), int(tot["eye1"])])
	print("[aieye] 填眼性质：要点 %d（是做活，正手）｜**真·白填 %d**（空间识别得出要点、却没下在要点上）｜判据失效区 %d（空间给不出要点）" % [
		int(tot["vital"]), int(tot["nonvital"]), int(tot["fvoid"])])
	print("[aieye] 不会做活：终局只剩1气成块棋 %d 子（%.1f 子/局）｜只剩2气 %d 子｜成块被提 %d 次/%d 子" % [
		int(tot["dead"]), float(int(tot["dead"])) / float(gcnt), int(tot["dying"]),
		int(tot["bigcaps"]), int(tot["bigstones"])])
	# ★ 牙齿判据（先证尺子能响，再读数）：`open == 0` 说明整个自战里**没有一个**己方眼点
	# 通过候选过滤 —— 那么「填眼=0」不能证明 AI 不填眼，只能证明这把尺子没对准靶子。
	var teeth: bool = int(tot["open"]) > 0
	print("[aieye] 仪器牙齿：眼点机会 共 %d / 过滤后仍可选 %d → %s" % [
		int(tot["seen"]), int(tot["open"]),
		"尺子对准了靶子（有机会而不填，才算 AI 不填眼）✓" if teeth
		else "★尺子没牙齿★：自战全程无「过滤后仍可选」的己方眼点，「填眼=0」不构成证据"])
	print("[aieye] 豁免口子宽度：过滤层拦「纯领地」%d 点次，豁免放行 %d 点次（%.1f%%）｜口径 A∧¬B" % [
		int(tot["blocked"]), int(tot["exempt"]),
		100.0 * float(int(tot["exempt"])) / float(maxi(int(tot["blocked"]) + int(tot["exempt"]), 1))])
	print("[aieye] 落在豁免空区的手：%d 手（%.1f 手/局）｜要点（在做活）%d ／ **真·白填 %d**（%.1f 手/局）／判据失效区 %d" % [
		int(tot["echosen"]), float(int(tot["echosen"])) / float(gcnt),
		int(tot["evital"]), int(tot["ewaste"]), float(int(tot["ewaste"])) / float(gcnt),
		int(tot["evoid"])])
	# ★ 两截判词必须分开说：`ewaste` 才是「机器判据认定、惩罚也指向」的真·白填；
	#   `evoid` 是**判据失效区**（模型给不出要点）—— 既不该罚、也不能算病。
	#   把两者合起来报，就是拿判据的失效当证据（本工程 2026-09-21 踩过：合起来那版永远报 ✗）。
	var void_share: float = 100.0 * float(int(tot["evoid"])) / float(maxi(int(tot["echosen"]), 1))
	print("[aieye] ↳ 豁免空区里 %d 手落在「空间识别不出要点」的地方（占 %.0f%%）—— 这一档**判据失效、不能算病**；" % [
		int(tot["evoid"]), void_share])
	print("[aieye] ↳ 真正要看的是**真·白填** %d 手（%.1f 手/局）：落点空间有要点、却没下在要点上。" % [
		int(tot["ewaste"]), float(int(tot["ewaste"])) / float(gcnt)])
	if not teeth:
		print("[aieye] ↳ 也就是说：`_own_territory_only()` 在这些盘型的自战里把每一个己方眼点都拦住了。")
		print("[aieye] ↳ 要复现用户看到的「填自己的眼」，得去「豁免被触发」的场合 —— 见 --aieye 的夹具模式（下一步）")
	var ok_viol: bool = int(tot["viol"]) == 0
	var ok_fill: bool = int(tot["lethal"]) == 0 and int(tot["eye2"]) == 0
	print("[aieye] 判据：纯领地违规=%d → %s｜致命填眼=%d、已活棋填眼=%d → %s" % [
		int(tot["viol"]), "阴性对照成立 ✓" if ok_viol else "过滤层有洞，先修洞 ✗",
		int(tot["lethal"]), int(tot["eye2"]),
		"无致命/白送填眼 ✓" if ok_fill else "存在致命/白送填眼，看上方病根拆分 ✗"])
	print("[aieye] ★头号判据★：落在己方豁免空区且**空间有要点却没下在要点上**的手 %d（%.1f 手/局）→ %s" % [
		int(tot["ewaste"]), float(int(tot["ewaste"])) / float(gcnt),
		"零白填 → 无此病 ✓" if int(tot["ewaste"]) == 0
		else "仍有真·白填 ✗（看上方每一手的 `落子后气`：气 ≤1 = 致命，气高 = 无害补棋）"])
	print("[aieye] 要点判据自检（阴性对照）：落子**之后**仍判为要点的次数 %d → %s" % [
		int(tot["vpost"]),
		"0 ✓（符合构造：`_ld_pts` 只装空点，故要点必须在落子前判）" if int(tot["vpost"]) == 0
		else "★非 0★：`_ld_pts` 语义已变，落子前/后的判据需要重新定标"])
	get_tree().quit()

## 贴目 → 引擎的**接线唯一入口**（2026-10-02）。
##
## ★ 为什么必须抽成函数（一处写、一处读）：
##   贴目有两个改动点 —— `_ready()` 初始化与设置页那个「白方贴目」滑条 —— 而
##   **只改 `komi` 不改引擎**是最自然的一种漏法：滑条回调 `komi = int(v)` 看着
##   就"贴目已生效"（计分侧确实立刻变了），AI 侧却还在按 0 目评估。
##   ★ 这与用户"所有数值运行期实时可调"的口径直接冲突：拧着滑条看 AI 行为不变，
##     而旁边的 `root_width` / `rollout 上限` 拧了立刻生效 ⇒ 同一页里两种口径。
##   实测同类：同页其它滑条（`threads` / `root_width` / `max_playout_moves`）都是
##   直接写 `ai_engine.*`，只有贴目这条当初写在了 `_ready()` 里就再没管过。
func _sync_komi_to_engine() -> void:
	# 与游戏侧 `_compute_scores()` 同源：那边 `total_white = … + komi`（同口径）。
	if ai_engine:
		ai_engine.komi = float(komi)
	# ★ 2026-10-22：流水档的引擎**必须走同一个真源**同步，不许各自读 `komi`。
	#   漏了这一行不会报错 —— 症状正是本函数长注释里那个"AI 不知道自己有贴目"。
	if ai_liushui:
		ai_liushui.komi = float(komi)
	# ★ 2026-10-23：野马档同理 —— 它内部那个 `AIEngine` 的 komi 由 `YemaAI.komi` 转发，
	#   所以要在这里同时设 `YemaAI.komi`（本函数是 komi 的唯一同步出口）。
	if ai_yema:
		ai_yema.komi = float(komi)
		if ai_yema.inner != null:
			ai_yema.inner.komi = float(komi)

## 自检（--komitest，2026-10-02）：白方贴目必须在引擎终局评估里生效。
##
## ★ 为什么要这条（它守的是一个**曾经真的错了**的东西）：
##   `ai_engine.gd` 里 `komi` 曾**零命中** —— 引擎的 `_area_score()` 返回「白 - 黑」纯盘面差，
##   而游戏侧 `_compute_scores()` 的白方总分是 `... + komi`（game.gd:9805）。
##   **两边不同源 ⇒ AI 完全不知道自己白方有贴目**。后果不是"分数显示不对"这种表面问题，
##   而是**下棋决策错**：贴 7.5 目时 AI 仍按 0 目评估自己的形势，该收官时还在乱冲、
##   该止损时不认输。玩家体感到"AI 不会收官"。
##
## 口径（本条判据的全部意义都在"怎么量"上）：
##   ★ **绝不能比"绝对分"**。设 komi=k 时 `_area_score()` 返回 `白-黑+k`，
##     看着像"多了 k 分"就对了 —— 但那是**恒真式**：`return white - black` 那行删掉、
##     在别处随便加个常数也能同样通过，且分差大小会被死子修正/影响力口径污染。
##   ⇒ 只量**同一局面、只改 komi 时的分差偏移量**：`score(k) - score(0) == k`。
##     其它一切（局面、子数、影响力、死子修正、随机流）**全部同源抵消**，
##     只剩贴目这一个变量 ⇒ 这才真的在测 komi。
##   ★ 还要证明 `komi=0` 时**逐位不变**（默认路径不能被这次改动影响）——
##     `score(0)` 必须等于裸盘面差，也就是与 `game.gd` 计分口径在 k=0 处对齐。
func _ai_komi_probe() -> void:
	# ★ 引擎必须用**固定 seed** 建：`setup()` 的 seed 缺省是 0⇒ 落到
	#   `Time.get_ticks_usec()`（每次运行都不同）。不钉住的话"固定局面"是假的
	#   —— 实测同一份判据两次运行的 k=0 目差是 -26 与 +120（局面完全不同），
	#   偏移量仍对是因为比较发生在**同一次调用内**。钉住 seed 后逐位可复现。
	ai_engine.setup(adjacency, AI_COLOR, 20261002)
	var n: int = tiles.size()
	# ⚠️ 测试值必须用**整数**：`komi` 是 `int`（`@export_range(0,12,1)`，滑条步进 1），
	#   `komi = int(7.5)` 截断成 7 ⇒ 偏移 +7.0 对不上期望 +7.5，判据会**误报红**。
	#   （这跟"贴目能不能取半目"无关：那是 UI 步长的事，游戏侧口径就是整数，
	#     引擎侧 `komi: float` 只是为了评估时不做整数除法。）
	var ks: Array[float] = [0.0, 7.0, 12.0]
	var ok := true
	# ── ① 同一局面、只改 komi ⇒ 分差偏移量必须**恰好**等于 komi ──────────────────
	# 用 `probe_eval_quality` 的 `score_new`（=_area_score()，影响力口径 = 引擎默认）当读数。
	# 局面固定为 seed=1234 / moves=24，同一个 `_rollout_fill` 轨迹 ⇒ 可逐位比较。
	# ★★ 改 komi 必须走 `_sync_komi_to_engine()`（真源）而**不是**直接写 `ai_engine.komi`：
	#   直接写就等于**绕过接线**——那么"游戏侧有没有把 komi 传给引擎"这条永远测不到
	#   （实测踩过：negctl 的 K2「游戏侧不接线」刀在这种写法下**仍绿**＝没牙齿）。
	#   走真源后，K2 那类坏法会让 ① 的偏移恒为 0 ⇒ 立刻报红。
	var base := ai_engine.probe_eval_quality(24, 1234, n * 4)
	var s0 := float(base["score_new"])
	print("[komitest] 固定局面（seed=1234, moves=24, 下满）| komi=0 时引擎目差 %.4f" % s0)
	for k in ks:
		komi = int(k)          # 游戏侧贴目（int，0~12 滑条口径）
		_sync_komi_to_engine()  # ★ 走真源接线
		var a := ai_engine.probe_eval_quality(24, 1234, n * 4)
		var sk := float(a["score_new"])
		var shift := sk - s0
		# 容差 1e-4：komi 是 float 且参与加减，只该有浮点舍入，不可能更大。
		var good: bool = absf(shift - k) <= 1e-4
		if not good:
			ok = false
		print("[komitest] komi=%4.1f ⇒ 引擎目差 %.4f（偏移 %+.4f，期望 %+.4f）%s" % [
				k, sk, shift, k, "✓" if good else "✗ 偏移量 ≠ komi，贴目没真正进评估"])
	komi = 0
	_sync_komi_to_engine()
	# ── ② 阳性对照：读数必须**真的**随 komi 变，否则 ① 是"恒 0 也绿"的恒真式 ───────
	#   ⚠️ 判据的**方向**很容易写反（第一版就写反了 ⇒ 把正确实现判成失败）：
	#     `live` 要问的是「读数**随** komi 变了吗」，不是「读数与 komi **不符**吗」。
	#     正确实现恰好是"偏移恒等于 komi"，所以 ① 已绿时按反向条件去查必然是 false。
	#   正确的做法：量「komi=12 与 komi=0 两次读数之差**非零**」——
	#     这只证明"引擎读数确实受 komi 影响"，与偏移是否恰好（那才是 ① 的职责）无关。
	var live: bool = false
	var s_hi := s0
	komi = 12
	_sync_komi_to_engine()
	s_hi = float(ai_engine.probe_eval_quality(24, 1234, n * 4)["score_new"])
	komi = 0
	_sync_komi_to_engine()
	live = absf(s_hi - s0) > 1e-4
	if not live:
		ok = false
	print("[komitest] 阳性对照：读数确实随 komi 变（k=12 与 k=0 差 %.4f）→ %s" % [
			absf(s_hi - s0), "✓（① 不是恒真式）" if live else "✗ 读数与 komi 无关，① 是恒真式"])
	# ── ③ 口径对齐：komi=0 时引擎目差与游戏侧"同口径"成立 ────────────────────────
	#   `game.gd::_compute_scores()` 的 total_white - total_black 在 komi=0 时也等于
	#   「白盘面 - 黑盘面」。这里只锁"k=0 不会被这次改动挪动"（默认路径零影响）。
	var zero_kept: bool = absf(s0 - float(base["score_new"])) <= 1e-9
	if not zero_kept:
		ok = false
	print("[komitest] k=0 路径零影响 → %s" % [
			"✓（默认贴目下引擎行为与改动前一致）" if zero_kept else "✗ k=0 口径被挪动了"])
	# ── ④ worker 参数同步：多线程下每个 worker 也必须带同一个贴目 ────────────────
	#   `_copy_params_from()` 漏了 komi ⇒ worker 与主实例策略不同、候选混两种噪声，
	#   而**单线程时完全看不出来**（所以这条必须单独钉）。
	var w := AIEngine.new()
	w.komi = 3.5
	komi = 9
	_sync_komi_to_engine()
	w._copy_params_from(ai_engine)
	var sync_ok: bool = absf(w.komi - 9.0) <= 1e-6
	komi = 0
	_sync_komi_to_engine()
	if not sync_ok:
		ok = false
	print("[komitest] worker 参数同步（`_copy_params_from` 含 komi）→ %s" % [
			"✓（worker 拿到 %.1f）" % w.komi if sync_ok else "✗ worker 仍是 %.1f，多线程会混两种策略" % w.komi])
	# ── ⑤ 接线本身：`_sync_komi_to_engine()` 必须真的把游戏侧贴目推到引擎 ────────
	#   ★ 为什么 ① 量不到这条（**这是本轮判据设计踩过的真坑**）：
	#     ① 自己给引擎喂 komi 再读回来 ⇒ 只要 `ai_engine.komi` 这个字段存在、且
	#     `_area_score()` 用它，① 就全绿 —— **游戏侧那个"把 komi 递过去"的动作
	#     有没有做，① 一概看不见**。实测 negctl 的 K2 刀（把 `ai_engine.komi = float(komi)`
	#     改成 `= 0.0`）在旧写法下报"✓ 仍绿（没牙齿！）"。
	#   ⇒ 单独量「改游戏侧 komi → 调真源 → 引擎侧读到多少」，且**必须真调真源**。
	var kk := 6
	komi = kk
	ai_engine.komi = -999.0     # 先污染，确保读数只能来自真源
	_sync_komi_to_engine()
	var wired: bool = absf(ai_engine.komi - float(kk)) <= 1e-6
	komi = 0
	_sync_komi_to_engine()
	if not wired:
		ok = false
	print("[komitest] 游戏侧→引擎接线（`_sync_komi_to_engine` 真源）→ %s" % [
			"✓（komi=6 推到了引擎）" if wired
			else "✗ 游戏侧改了 komi、引擎侧没跟上 ⇒ AI 永远按 0 目评估"])
	print("[komitest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 自检（--rulestest，2026-10-02）：**棋理判据跨引擎一致**。
##
## ★★ 这条守的是一个"两套独立实现"的结构性隐患（用户 2026-09-30 盘点 P0 第 ③ 条）：
##   合法性判据（空点 / 打劫 / 自杀 / 提子）在本工程有**两份独立实现**：
##     · 游戏侧 `can_place_at()`（game.gd:9210）—— 玩家预览与点击走它；
##     · 引擎侧 `_play()`（ai_engine.gd:1302）—— AI 搜索走它。
##   两者**都实现了同一套规则，但没有共享真源、也没有任何交叉判据**
##   ⇒ 改一边，另一边静默保持旧行为 ⇒ 玩家看到的"能下"与 AI 认定的"能下"会分叉。
##   ★ `--hovertest` ④ 只对照了**游戏侧内部**（`can_place_at()` vs `place_stone()`），
##     它**看不见**跨引擎分叉 —— 这是"局部穷举 ≠ 全局一致"的典型。
##
## ★ 本判据的量法（承 komi 那条的经验）：**穷举逐点对拍**，不抽样。
##   对同一局面、每个空点 t，同时问两边「能下吗」，逐格比结论：
##     游戏侧 `can_place_at(t)`（只读）；
##     引擎侧 `load_board_for_probe(board)` + `_play(t) >= 0`（会改棋盘，故每点重载）。
##   ⇒ 任一侧规则改动造成分叉，立刻报红并**打印分歧点**，便于定位。
##
## ★ 为什么不用"绝对分/计数"式断言：分叉可能只在一两个特殊形状（打劫、自杀、提子后落点）
##   上出现，计数式断言要么漏、要么在盘型不覆盖时假绿。逐点对拍 + 打印样本最直接。
func _rules_cross_test() -> void:
	if tiles.is_empty():
		print("[rulestest] 结论：失败 ✗ 棋盘未生成")
		get_tree().quit()
		return
	# 局面必须用**合法落子**铺出来（与 `--hovertest` ④ 同一个理由）：
	# 随机填子会造出「无气串」这种非法局面，而非法局面下 `place_stone` 的
	#「先全局提死子」会比 `can_place_at` 多提子 → 假红。
	reset_game(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261002
	current_player = Stone.BLACK
	_quiet_place = true
	var played := 0
	var guard := 0
	while played < 80 and guard < 60000:
		guard += 1
		var t: int = rng.randi_range(0, tiles.size() - 1)
		if not can_place_at(t):
			continue
		if place_stone(t, false):
			played += 1
	_quiet_place = false
	# 快照（对拍时逐点回滚）
	var snap_board: Dictionary = board.duplicate()
	var snap_turn: int = current_player
	var snap_ko: int = ko_point
	var snap_bp: int = black_prisoners
	var snap_wp: int = white_prisoners
	var snap_pass: int = passes
	print("[rulestest] 局面：%d 手（seed=20261002），轮到 %s，ko=%d"
		% [played, "黑" if snap_turn == Stone.BLACK else "白", snap_ko])
	# ★ 引擎侧要**同一个手番**。`load_board_for_probe` 内部把 `_turn` 设成 `ai_color`，
	#   而这里要判的是"当前轮到谁" ⇒ 显式改回 `snap_turn` 再 `_play`。
	var mism := 0
	var n_empty := 0
	var n_legal := 0
	var samples: Array[String] = []
	for i in tiles.size():
		if board[i] != Stone.EMPTY:
			continue
		n_empty += 1
		# 游戏侧：只读判据
		var g_side: bool = can_place_at(i)
		# 引擎侧：重载棋盘 → 落子（返回 -1 即非法）→ 提问
		ai_engine.load_board_for_probe(snap_board)
		ai_engine._turn = snap_turn
		var e_side: bool = ai_engine._play(i) >= 0
		# 回滚游戏侧（引擎侧每点都重载过，不用管）
		board = snap_board.duplicate()
		current_player = snap_turn
		ko_point = snap_ko
		black_prisoners = snap_bp
		white_prisoners = snap_wp
		passes = snap_pass
		_place_anims.clear()
		_capture_anims.clear()
		if g_side != e_side:
			mism += 1
			if samples.size() < 5:
				# 带上邻居实况，便于判断是打劫/自杀/提子哪一类分叉
				var nbs: Array[String] = []
				for nb in adjacency[i]:
					nbs.append("t%d=%s" % [nb, str(board.get(nb, Stone.EMPTY))])
				samples.append("t%d：游戏侧%s/引擎侧%s（邻居 %s）"
					% [i, _yn(g_side), _yn(e_side), ", ".join(nbs)])
		if g_side:
			n_legal += 1
	var same_ok: bool = mism == 0 and n_legal > 0 and n_empty > 0
	print("[rulestest] ① 跨引擎逐点对拍（空点 %d：可下 %d / 拒 %d）分歧 %d → %s"
		% [n_empty, n_legal, n_empty - n_legal, mism, "✓ 两侧规则同源" if same_ok else "✗ 两侧规则分叉"])
	for s in samples:
		print("[rulestest]    分歧样本：", s)
	if not same_ok:
		ok_rulestest_fail()
		return
	# ── ② 劫点：两边都要**禁着**同一个点（单独钉，因为"提一子"这条分支只在
	#    真劫局面里触发，80 手随机局不一定造得出劫）──
	# 复用 `_setup_shot_capture()`（`--shotcap` 那套"黑提白一子"构造，同一几何不重写）
	# ★ 必须先 `reset_game` 清干净：上一段 ① 的逐点对拍虽然每个点都回滚了 board，
	#   但 `_setup_shot_capture()` 会在**当前局面上**摆子，残留状态会让劫点造不出来。
	reset_game(true)
	# ★★★ 造**真劫**（2026-10-02 试了四版才对，坑全记在下）：
	#   劫的实质 = 提一子后**落子方自己只剩一气**（气就是刚被提空的那点）⇒
	#   对方落回被提点就能**提回**那口气 ⇒ 双方来回同形，故禁一手。
	#   ⇒ 白子 t_c，黑子围住 t_c 的其它邻座，黑落 t_c 的最后一个空邻 `ko_v` 提子。
	#   ⚠ **只围 t_c 是不够的**：黑 `ko_v` 自己往往还有别的邻座是空的（实测 t1 的四邻
	#   t0/t14/t2/t4 在提子后仍全黑，但那是"围 t_c 围的"，`ko_v` 那一侧的气还在）
	#   ⇒ 造出来的不是劫而是"提一子自己还宽敞"，白落回被提点既提不到子也无气 = **自杀**
	#   ⇒ 判据的同点差值恒 0 ⇒ **对这类形状是瞎的**（第一版就栽在这，看起来"两侧一致"）。
	#   ⇒ 追加一步：**造完后量黑 `ko_v` 的气**，>1 就把它其余邻座也坐黑，直到 =1。
	#   （这才是"收紧到真劫"，而不是指望某个手写几何碰巧对。）
	# ★★★ 采一个**真劫**样本（2026-10-02 试了四版手写几何才对一半，最终放弃手写）：
	#   ⚠ **手写几何造不出真劫**（这条坑很贵，记全）：
	#     劫要求「被提方落回被提点能**提回一子**」，等价于放被提子的那个黑串
	#     **除被提点外完全没有气**。而"完全没有气"要求把它整串所有外侧空邻座
	#     都坐黑 —— 那会一路递归下去把整个盘填满，不是手写几何能收住的。
	#     实测第一版就这样：造出的是"提一子、自己还宽敞" ⇒ 白落回被提点
	#     既提不到子也无气 = **自杀** ⇒ 同点差值恒 0 ⇒ 判据对这类形状是**瞎的**
	#     （而"两侧一致"看起来是绿的 —— 这就是坏法 B 报"没牙齿"的真因）。
	#     第二版"留一邻空"更糟：白子根本没被提，`ko_point` 造不出来。
	#   ⇒ 改成**在随机对局里捞**：真对局里本来就有劫，且两侧面对的是**同一个真实劫形**
	#     （采样走游戏侧 `place_stone()`，引擎侧拿 `ko_pre_board` 重演那一手）。
	#   捞的判据就是"真劫"的定义：落子后 `ko_point` 指向某点，且**摘掉 ko 闸后
	#   对方落回该点是合法的** —— 合法才说明它提得到子/有气。
	var ko_c: int = -1              # 劫点（= 刚被提掉的那个点）
	var ko_v: int = -1              # 制造劫的那一手（落子点）
	var ko_side: int = -1           # 那一手的落子方
	var ko_pre_board: Dictionary = {}   # 那一手**之前**的面貌（引擎重演用）
	var ko_pre_ko: int = -1
	for seed_i in range(6):
		if ko_c >= 0:
			break
		reset_game(true)
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 20261003 + seed_i * 7919
		current_player = Stone.BLACK
		_quiet_place = true
		var played2 := 0
		var guard2 := 0
		while played2 < 260 and guard2 < 200000:
			guard2 += 1
			var t: int = rng2.randi_range(0, tiles.size() - 1)
			if not can_place_at(t):
				continue
			var pre: Dictionary = board.duplicate()
			var pre_ko: int = ko_point
			if not place_stone(t, false):
				continue
			played2 += 1
			if ko_point < 0:
				continue
			# ★ 「真劫」判定：摘掉 ko 闸后，对方落回 ko_point 必须**合法**
			#   （不合法 ⇒ 那个点同时是自杀点 ⇒ 判据对它瞎，v1/v2 就栽在这）
			var saved_ko: int = ko_point
			ko_point = -1
			var recap_ok: bool = can_place_at(saved_ko)
			ko_point = saved_ko
			if not recap_ok:
				continue
			ko_c = saved_ko
			ko_v = t
			ko_side = 3 - current_player    # `place_stone()` 收尾已把回合翻给对手
			ko_pre_board = pre
			ko_pre_ko = pre_ko
			break
		_quiet_place = false
	if ko_c >= 0:
		_place_anims.clear()
	_capture_anims.clear()
	var ko_t: int = ko_point
	var ko_g: bool = true
	if ko_t >= 0 and ko_v >= 0:
# ★★ 必须把**劫点分支与自杀分支拆开**（2026-10-02 踩到，负面对照逼出来的）：
		#   只问"两边都拒那个点"是不够的 —— 若那个点**同时也是自杀点**，
		#   把游戏侧的劫点闸剪掉（`if false and tile_id == ko_point`）它**照样绿**：
		#   两侧都被"自杀"这条**另一条**分支拒掉了 ⇒ 判据看着咬住了，实际没在测劫点。
		#   ⇒ 靠上面的采样把关（"摘 ko 后回提合法"才收）保证劫点**不是**自杀点，
		#     再用下面的**同点差值**证明 ko 闸真的在起作用。
		ko_g = can_place_at(ko_t)
		# 先量「引擎走成劫的那一手之后 `_ko` 指哪」—— 从**那一手之前**的面貌重演
		#   （`ko_pre_board` 是采样时 `place_stone()` 之前的快照，**带当时的 ko**）。
		#   ★ 不再手工"退回提子前"：那要凭空判断被提点的颜色与回合，退错一次就
		#   量到自杀分支（诊断里"轮到 2"就是退错留下的痕迹）。
		ai_engine.load_board_for_probe(ko_pre_board, ko_pre_ko)
		ai_engine._turn = ko_side
		var eng_nc: int = ai_engine._play(ko_v)
		var eng_ko: int = ai_engine._ko
		# 真劫点上的**同点差值**（带 ko 拒 / 摘 ko 放）：这是"这个 ko 闸本身在起作用"的硬量。
		#   ★ 当前 board 正是采样后（= 那一手已落）的真实局面，回提方 = `current_player`。
		ai_engine.load_board_for_probe(board, ko_t)
		ai_engine._turn = current_player
		var e_blocked: bool = not (ai_engine._play(ko_t) >= 0)
		ai_engine.load_board_for_probe(board, -1)  # ★ 摘掉 ko 闸
		ai_engine._turn = current_player
		var e_unblocked: bool = ai_engine._play(ko_t) >= 0
		# ── 闸的"可摘性"对照（这是让 ② 有牙齿的关键）──
		# ★★ 问法必须是**同一个点上的差值**（2026-10-02 换过三版才定稿，这条最贵）：
		#   v1「另找一个对照空点问放行」—— 错在**那个点本身可能是别的分支的禁点**
		#      （实测对照点 t3 恒不放行，而真劫点两侧其实已一致）
		#      ⇒ "放行=✗"分不清是 **ko 闸没摘掉**还是**别的闸在拒**。
		#   v2「扫全盘找第二个承重点」—— 更糟：一个 ko 点只有一个，扫不到 ⇒ 假红。
		#   v3（定稿）**同一个点**上问两次：带 `ko` 拒 → 摘掉 ko（`ko=-1`）放行。
		#      差值为 0 只可能是"ko 闸没接上/没设上"（例如旧引擎那种
		#      「提一子 + 己方仅一气」才设劫的过严条件：`_ko` 压根是 -1 ⇒ 两次读数相同）。
		#   ⇒ 引擎侧与游戏侧**各做一次同点差值**，互不代替。
		var real_ko2: int = ko_point
		# 游戏侧同点差值
		ko_point = real_ko2
		var g_blocked: bool = not can_place_at(ko_t)
		ko_point = -1
		var g_unblocked: bool = can_place_at(ko_t)
		ko_point = real_ko2
		# 判读：① 两侧在真劫点同禁 ② 引擎 `_ko` 真指对 ③ 两侧 ko 闸都真的承重（同点差值）
		var full_ok: bool = (not ko_g) and e_blocked and eng_ko == ko_t \
				and g_unblocked and e_unblocked
		print("[rulestest] ② 劫点 t%d：走成劫那手引擎提 %d 子、_ko=t%d（期望 %d）｜真劫点两侧同禁（游戏侧%s/引擎侧%s）｜ko 闸承重（摘掉 ko 后放行：游戏侧%s/引擎侧%s）→ %s"
			% [ko_t, eng_nc, eng_ko, ko_t, _yn(not ko_g), _yn(e_blocked),
				_yn(g_unblocked), _yn(e_unblocked),
				"✓ 劫点规则同源且两侧闸都承重" if full_ok else "✗ 劫点口径不一致"])
		if not full_ok:
			if not g_unblocked:
				# 把这一格的邻居实况打出来：判断"摘 ko 仍禁"到底是**自杀**（该点四邻全被围）
				# 还是别的分支。**只打不打就下结论 = 猜**，本条已经因此改过三版。
				var nb2: Array[String] = []
				for nb in adjacency[ko_t]:
					nb2.append("t%d=%d" % [nb, int(board.get(nb, Stone.EMPTY))])
				print("[rulestest]    诊断：游戏侧摘 ko 仍不放行；t%d 邻居 %s（轮到 %d）"
					% [ko_t, ", ".join(nb2), current_player])
			if not e_unblocked:
				print("[rulestest]    诊断：引擎侧摘掉 ko 仍不放行 ⇒ 引擎 `_ko` 可能压根没设上")
			ok_rulestest_fail()
			return
	else:
		print("[rulestest] ② 劫点：✗ 6 个随机种子都没捞到真劫（采样判据：落子后 ko_point≥0 且摘 ko 回提合法）—— 本条对拍无效"
			% [])
		ok_rulestest_fail()
		return
	# ── ③ 自杀点：造「邻居全白、白环外侧有气」⇒ 两侧都必须拒 ────────────────
	# ★ 必须 `reset_game` 重新起局：② 的劫点局面里 ko_point 还指着上一手，
	#   直接改 board 会让「点恰好落在 ko_point 上」与「自杀」两条规则混在一起，
	#   分不清是谁拒的 ⇒ 判据必须**每次只验一条规则**（铁律：量伤害最大的那一刻）。
	reset_game(true)
	current_player = Stone.BLACK
	_place_anims.clear()
	_capture_anims.clear()
	var t_sui := -1
	for i in tiles.size():
		if adjacency[i].size() >= 3:
			t_sui = i
			break
	var sui_g := true
	var sui_e := true
	if t_sui >= 0:
		for n in adjacency[t_sui]:
			board[n] = Stone.WHITE
		sui_g = can_place_at(t_sui)
		ai_engine.load_board_for_probe(board)
		ai_engine._turn = Stone.BLACK
		sui_e = ai_engine._play(t_sui) >= 0
	var sui_ok: bool = t_sui >= 0 and (not sui_g) and (not sui_e)
	print("[rulestest] ③ 自杀点（t%d 邻居全白）：游戏侧拒=%s；引擎侧拒=%s → %s"
		% [t_sui, _yn(not sui_g), _yn(not sui_e),
			"✓ 两侧同拒" if sui_ok else "✗ 自杀口径不一致"])
	if not sui_ok:
		ok_rulestest_fail()
		return
	# ── ④ superko（positional）：同形再现必须拒，且**只能**因 superko 拒 ──────────
	# ★★ 为什么用"夹具法"造场景，而不是手工摆一个循环劫：真循环劫要求「提回后局面与
	#   两手前逐点相同」，手工几何连"真劫"都造不出来（见 ② 那三条坑），更别说还要恰好
	#   撞上历史条目 —— 那是碰运气，不是判据。夹具法直接构造**规则语义本身**：
	#   把「在 t 落黑之后的局面指纹」塞进历史，等价于宣称"t 这点再落一次黑就会回到
	#   曾经出现过的局面" ⇒ 两个函数都必须拒。
	# ★★ 本段**必须跑在 `_quiet_place = false`**（与本函数 ①②③ 段相反，这是故意的）：
	#   superko 在探测性落子语境被三处守卫刻意关掉（`_superko_blocks` / `_superko_commit`
	#   / `place_stone`），因为 ① 与 `--hovertest` 的穷举对照都要**手动回滚盘面**、
	#   而探测性落子没有真实对局历史。若本段也跑在 true 下，它会**恒真地绿**。
	# ★★ 本段是 superko 的**唯一**判据：`can_place_at()`（预测式）与 `place_stone()`
	#   （实测式）的一致性，在任何穷举对照里都覆盖不到（见上一条）。
	reset_game(true)
	current_player = Stone.BLACK
	_place_anims.clear()
	_capture_anims.clear()
	var sk_init_ok: bool = _superko_hist.size() == 1 and _superko_zob.size() == tiles.size()
	# 夹具点必须是「棋理上可下」的空点 —— 否则那个"拒"来自**自杀**分支，判据就成了
	#   "看着咬住了、其实在测另一条规则"（② 的第一版正是这个坑，本工程已踩三次）。
	_quiet_place = true
	var sk_t := -1
	for i in tiles.size():
		if board[i] == Stone.EMPTY and can_place_at(i):
			sk_t = i
			break
	_quiet_place = false
	if sk_t < 0 or not sk_init_ok:
		print("[rulestest] ④ superko：✗ %s（历史 %d 条 / 指纹表 %d 格 / 盘面 %d 格）"
			% ["空盘找不到可下点" if sk_t < 0 else "空盘历史未就位",
				_superko_hist.size(), _superko_zob.size(), tiles.size()])
		ok_rulestest_fail()
		return
	var sk_pred: int = _superko_hash_after(sk_t, Stone.BLACK)
	var sk_fp_before: String = _undo_fingerprint()
	_superko_hist[sk_pred] = true      # ← 夹具：这一手之后的局面"已经出现过"
	print("[rulestest]    ④ 夹具就位（t%d 落黑后的局面指纹已入历史）；若下面出现「超级劫：全盘同形再现，落子无效」是**预期**日志，不是故障"
		% sk_t)
	# ① 带夹具：**两个函数都必须拒**，且盘面/回合/劫点一个字段都不许动
	var g_block: bool = not can_place_at(sk_t)
	var e_block: bool = not place_stone(sk_t, false)
	var sk_fp_kept: bool = _undo_fingerprint() == sk_fp_before
	# ② 摘掉夹具（**同一个点上的差值**）：两个函数都必须放行 ⇒ 证明 ① 那个"拒"真的
	#    来自 superko，而不是自杀/劫点等别的分支在拒（这是让本条有牙齿的关键）。
	_superko_hist.erase(sk_pred)
	var g_unblock: bool = can_place_at(sk_t)
	var e_unblock: bool = place_stone(sk_t, false)
	# ③ 真落子后实测指纹 == 落子前**预测**指纹 ⇒ 两种访问方式一致。
	#    （提子分支也在内：`_superko_hash_after()` 预测要提的串，必须与
	#     `remove_dead_stones()` 实际提掉的**完全同一批**。）
	var sk_predict_ok: bool = e_unblock and _superko_hash() == sk_pred
	# ④ 落子把新指纹记了档 —— 不单独验这条，下面"悔棋后重下"会**恒真**：
	#    若 commit 压根没写进去，`erase` 与 `has` 都是空转，判据等于没测。
	var sk_commit_ok: bool = e_unblock and _superko_hist.has(sk_pred)
	# ⑤ 悔棋必须把这一手的指纹**摘掉**：漏了 ⇒ 那个局面永久留档，
	#    悔完再重下同一手会被误判成"同形再现"（悔棋把未来的棋禁了）。
	var sk_undo_ok := false
	if sk_commit_ok and not _hist.is_empty():
		_pop_history_entry(_hist[_hist.size() - 1])
		sk_undo_ok = (not _superko_hist.has(sk_pred)) and can_place_at(sk_t) \
				and place_stone(sk_t, false)
	# ⑥ 指纹表的**尺寸守卫**（换盘路径的兜底；2026-10-14 `--hatdead` 逮到的越界）：
	#   把表缩掉一项 = 模拟"换了盘但表没重建"，`_superko_hash()` 必须**当场自愈**，
	#   且返回值与完好时**逐位相同**（否则 superko 会在换盘后悄悄判错局面）。
	#   ★ 有牙齿的写法：先存完好值 `sk_full`，缩表后再比 —— 只断"没抛错"是不够的
	#     （返回残值 0 也不抛错，而 0 恰是空盘指纹 ⇒ 静默误判）。
	var sk_full: int = _superko_hash()
	_superko_zob.erase(tiles.size() - 1)
	# ⚠️ 必须**先调** `_superko_hash()`（自愈发生在这里），**再**断尺寸 —— 写成
	#   `_superko_zob.size() == tiles.size() and _superko_hash() == sk_full` 的话，
	#   `and` 短路会在左半（此刻 size 已少一项 ⇒ false）就停下 ⇒ **永远不调** ⇒ 自愈
	#   从未被触发 ⇒ 判据恒假（2026-10-14 实跑逮到，属"判据自身的 bug"）。
	var sk_h2: int = _superko_hash()
	var sk_heal_ok: bool = _superko_zob.size() == tiles.size() and sk_h2 == sk_full
	var sk_ok: bool = sk_init_ok and g_block and e_block and sk_fp_kept \
			and g_unblock and e_unblock and sk_predict_ok and sk_commit_ok and sk_undo_ok \
			and sk_heal_ok
	print("[rulestest] ④ superko（夹具点 t%d）：预测/实测同拒=%s/%s｜失败未动盘面=%s｜摘掉历史后同放=%s/%s｜新指纹入档=%s｜预测=实测=%s｜悔棋后重下合法=%s｜表失配自愈=%s → %s"
		% [sk_t, _yn(g_block), _yn(e_block), _yn(sk_fp_kept), _yn(g_unblock), _yn(e_unblock),
			_yn(sk_commit_ok), _yn(sk_predict_ok), _yn(sk_undo_ok), _yn(sk_heal_ok),
			"✓ 同形再现被拦且两种访问方式同源" if sk_ok else "✗ superko 未生效/口径分叉"])
	if not sk_ok:
		ok_rulestest_fail()
		return
	# ── ⑤ 预测式 vs 实测式：**逐手对拍**（含提子分支）───────────────────────
	# ★ 为什么 ④ 不够（自查发现的判据缺陷）：④ 的夹具在**空盘**上落子 ⇒ 必然不提子
	#   ⇒ 那条"预测=实测"只覆盖 `_superko_hash_after()` 的**无提子**分支。而它的提子
	#   预测（`_libs_of_group_excluding()` + `get_group()`）恰是最容易写错的一半：
	#   写漏 ⇒ "提掉对方一子之后的局面"被算成另一个指纹 ⇒ superko 漏拦或误拦。
	# ★ **有效分母**：提子手必须真的出现过（=0 则报失败）—— 判据没覆盖到目标分支
	#   就不许绿着过关（否则是"恒真的绿"，§68/§66 的老坑）。
	# ★ 跑在 `_quiet_place = true`：本段只比两个**纯读**函数的返回值，与历史条目无关；
	#   quiet 还避免了"随机手被 superko 拒掉"这种与判据无关的干扰。
	reset_game(true)
	current_player = Stone.BLACK
	var sk5_rng := RandomNumberGenerator.new()
	sk5_rng.seed = 20261014
	var sk5_n := 0
	var sk5_cap := 0
	var sk5_bad := 0
	var sk5_first := ""
	_quiet_place = true
	var sk5_guard := 0
	while sk5_n < 100 and sk5_guard < 60000:
		sk5_guard += 1
		var t5: int = sk5_rng.randi_range(0, tiles.size() - 1)
		if not can_place_at(t5):
			continue
		var cur5: int = current_player
		var pred5: int = _superko_hash_after(t5, cur5)     # 预测式（落子前）
		var cap_before5: int = black_prisoners + white_prisoners
		if not place_stone(t5, false):
			continue
		sk5_n += 1
		var cap_now5: int = black_prisoners + white_prisoners
		if cap_now5 > cap_before5:
			sk5_cap += 1
		if _superko_hash() != pred5:                        # 实测式（落子后）
			sk5_bad += 1
			if sk5_first == "":
				sk5_first = "第%d手 t%d（提 %d 子）" % [sk5_n, t5, cap_now5 - cap_before5]
	_quiet_place = false
	var sk5_ok: bool = sk5_n >= 60 and sk5_cap > 0 and sk5_bad == 0
	print("[rulestest] ⑤ 预测/实测逐手对拍：%d 手（提子手 %d）｜不一致 %d%s → %s"
		% [sk5_n, sk5_cap, sk5_bad, "" if sk5_first == "" else "（首个：%s）" % sk5_first,
			"✓ 两种访问方式逐手同源" if sk5_ok else "✗ 分叉，或提子分支未被覆盖（判据无效）"])
	if not sk5_ok:
		ok_rulestest_fail()
		return
	print("[rulestest] 结论：通过 ✓")
	get_tree().quit()

## rulestest 的收尾（失败时统一出口：打结论行 + 退出）
func ok_rulestest_fail() -> void:
	print("[rulestest] 结论：失败 ✗ 棋理判据跨引擎不一致")
	get_tree().quit()

# ============================================================================
# 自检（--undotest）：悔棋
# ----------------------------------------------------------------------------
# 悔棋最容易出的不是"崩"，而是**静默地退得不对**：少退一手、提子没放回来、
# 劫点残留、提子计数虚增 —— 盘面看起来还是那么回事，要几十手之后才暴露。
# ⇒ 本判据的重心在 **③ 回滚等价性**：正走 N 手记快照 → 悔棋 → 重走同一批点，
#   若两次的 board/ko/turn 逐键相同，就证明回滚**没漏掉任何隐藏状态**。
#   这条能红 = 它真的在量"回滚损不损伤局面"，而不是只量"落子栈长度对不对"。
# ============================================================================

## 局面指纹：把"能不能安全回滚"相关的**全部**状态打成一个可比对的串。
## ★ 刻意把 ko_point / passes / _last_move / 提子计数都算进去 —— 它们正是**盘面推不出**
##   的那批（所以必须靠 `_hist` 存档）。只比 board 的话，回滚丢掉这三样也会判"通过"。
func _undo_fingerprint() -> String:
	var keys: Array = board.keys()
	keys.sort()
	var s := ""
	for k in keys:
		s += "%d=%d," % [k, board[k]]
	s += "|ko=%d,passes=%d,last=%d,bp=%d,wp=%d,turn=%d" % [
		ko_point, passes, _last_move, black_prisoners, white_prisoners, current_player]
	return s

## 走 n 手随机合法着法，返回落点序列（用于"重走同一批点"）。
## ★ 用固定种子：③ 的两次走子序列必须**逐点相同**，否则比对的就不是同一件事。
func _undo_random_moves(n: int, seed_v: int) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var seq: Array[int] = []
	for i in n:
		if i % 2 == 1 and i >= 2 and rng.randf() < 0.22:
			_apply_pass()      # ★ 掺入停一手：停手也占机会，必须一起被回滚干净
			seq.append(-1)
			continue
		var t: int = rng.randi_range(0, tiles.size() - 1)
		var guard: int = 0
		while not can_place_at(t) and guard < 400:
			t = rng.randi_range(0, tiles.size() - 1)
			guard += 1
		if not place_stone(t):
			_apply_pass()
			seq.append(-1)
		else:
			seq.append(t)
	return seq

# ====== 回放一致性（2026-10-02，棋谱阶段① 的核心判据）======
## 本段是**判据先行**的产物：先证明"种子决定论在**有落子**时也成立"，再写棋谱功能。
## ★ 为什么这条必须先做（规划文档 `棋谱与创意工坊_开发规划.md` §阶段①）：
##   棋谱**只存「盘型+种子+手数序列」而不存棋盘数据** —— 这个"省"字全部押在
##   「同种子必得同一张盘，且按谱重放能回到同一局面」上。
##   ⚠️ 之前只用**截图 MD5** 证明过**开局**可复现；带落子的整局**从未验证**。
##   而失败形态极隐蔽：棋谱能读回来、能显示、复盘能拖动，但**每一步复现的盘面都略有偏差**
##   ⇒ 提子/劫点/官子判断全错，而"看起来完全正常"。
##★ 判据口径（照 `undotest` ③ 那一课，**不做重建式比较**）：
##   「正走 N 手 → 重建棋盘 → 重放同一串 → 逐键对账」这个写法里，
##   **重放本身引入了与被测物无关的差异**（上一轮实测两处，见 `_undo_random_moves` 的注）。
##   ⇒ 分成两件事、分别对账：
##     ① **盘面重建**：同 `board_type/board_size/seed` ⇒ 重建出的 `tiles`/`board` 键集合
##        与原局**逐键相同**（这是"种子决定论"本身，与落子无关）；
##② **落子重放**：**不重建棋盘**（同一张盘上先 reset 再重放），
##        这样"重建误差"与"重放误差"不会混在一起，判红时能立刻分清是哪一层坏了。
##   最终判据 = ①② 都对，且**重放后的完整指纹**与原局逐键相同（board/ko/last_move/提子数/行棋方）。

## 只走合法落点的采样器（★ 刻意**不写** `_apply_pass()` 兜底）。
##   兜底会让"这一手本该被拒"变成"停一手"⇒ 重放序列与原局不是同一串东西，
##   而差异被误记成"重放不一致"。上一轮 `undotest` ③ 就是被这个坑污染过一次。
##   ⇒ 挑不到合法点就**如实返回 -1**，由调用方记录"提前收摊"，不伪造一手。
func _replay_pick(rng: RandomNumberGenerator, out: Array[int]) -> bool:
	for tries in 200:
		var t: int = rng.randi_range(0, tiles.size() - 1)
		if can_place_at(t):
			out.append(t)
			return true
	return false

## 局面指纹（与 `_undo_fingerprint` **同一套口径**，但**刻意多带两项**：
##   `_rand_seed` 与 `board` 键集合的摘要 —— 判"重建是否同一张盘"时要用，
##   而悔棋那条永远不重建棋盘所以不需要它。
##   ★ 两处指纹**必须同源**：各写一份公式就会变成 S7/S8 那个"自检另抄一遍"的老坑
##   （改实现时判据手里的"参考答案"还是旧常量 ⇒ 照旧全绿）。
func _replay_fingerprint() -> String:
	var keys: Array = board.keys()
	keys.sort()
	var s := "seed=%d,n=%d," % [_rand_seed, keys.size()]
	for k in keys:
		s += "%d=%d," % [k, board[k]]
	s += "|ko=%d,passes=%d,last=%d,bp=%d,wp=%d,turn=%d" % [
		ko_point, passes, _last_move, black_prisoners, white_prisoners, current_player]
	return s

# ====== 复盘器 host 接口（棋谱阶段②）======
# `replay.gd` 只调这四个 + `reset_game` / `place_stone` / `queue_redraw`。
# 刻意**窄接口**而不是把 `self` 整个交出去：那样它能改任何对局状态，
# "复盘状态与对局状态同名变量互相污染"那条风险就又回来了。

## 钉死复盘用的种子。复盘的盘必须与原局同一张，否则"重放"是在另一张盘上自说自话。
func replay_lock_seed(seed_val: int) -> void:
	if seed_val >= 0:
		_rand_seed = seed_val


## ★★ 进复盘前把**发生器**切回"谱里那张盘"：**盘型 + 尺寸 + 种子**。
##   必须在 `generate_board()` **之前**调 —— 晚了盘已经生成完了。
##
## ★★★ 为什么必须有这个函数（2026-10-09 用户报的 bug）：
##   **症状** = 棋谱页里点"我自己下的谱"进去却是一局**新棋**（不是复盘、也不报错）；
##             点"AI 训练留下的谱"却能正常播放。
##   **根因** = `_record_generator_fp()` 把 15 个生成器参数全编进指纹（开头就是
##             `t<board_type>|s<board_size>`），而 `replay_lock_seed()` **只掰种子**。
##             ⇒ 一张在**别种盘型**上下的谱，进复盘时种子对上了、盘型却还是当前选中的那张
##             ⇒ 指纹不符 ⇒ `replay_enter()` 拒载 ⇒ `_ready()` 静默落到普通对局。
##             ★ 于是"能不能复盘"取决于**谱里的盘型碰巧等不等于菜单当前选的盘型** ——
##               这正是"AI 训练谱能播、我自己的谱不能播"的原因（训练固定跑默认盘）。
##   **为什么单列一个函数而不是写进 `_ready()`**：headless 自检**复制不出**"重新进场景"
##     这个时机 ⇒ 只有把它抽成函数，`--browsetest` ⑪ 才量得到（否则这条永远是恒真式）。
func replay_apply_board_spec(rec: Dictionary) -> void:
	if rec.is_empty():
		return
	var bt: int = int(rec.get("board_type", -1))
	var bs: int = int(rec.get("board_size", -1))
	var sd: int = int(rec.get("board_seed", -1))
	if bt >= 0:
		GameConfig.board_type = bt
	if bs >= 0:            # ⚠️ 0 是合法值（RANDOM），判据必须是 `>= 0` 不是 `> 0`
		GameConfig.board_size = bs
	# ⚠️ 刻意**拿局部变量**调，不写成 `replay_lock_seed(int(rec.get("board_seed", -1)))`：
	#   `replay_enter()` 里有**逐字相同**的一行，而结构守卫的 `replay_seed_lock` 标记
	#   要求**恰好命中 1 次**（S46c 用它守"先钉种子再校验指纹"）⇒ 写一样就命中 2 次 ⇒ 假红。
	#   ★ 与"命名先查占用"同族：加代码前先想**它会不会撞上既有守卫的锚点**。
	replay_lock_seed(sd)

## 复盘里的「停一手」。走 `_apply_pass()` 真实路径（它才翻 `current_player` 与 `passes`）。
## ★ 不能直接改 board：那样"轮到谁"会与真实对局不一致，信息栏就会报错执色。
func replay_apply_pass() -> void:
	_apply_pass(current_player)

## 重放完后**不需要**掰执色 —— `place_stone()` 收尾的 `current_player = opponent` 已经天然对：
## 从 `reset_game()` 的 BLACK 起，走完 N 手后执色必然是"第 N 手的落子方的对手"。
## ★ 这里曾经有个 `replay_sync_turn()`，是**负控刀 BR2 揭穿的冗余**：删掉它后 `--browsetest` ④ 仍绿。
##   留着的唯一价值是 ④ 那条判据本身（它守住"执色正确"这个事实，防将来有人改坏 `place_stone()` 的翻转）。
func replay_sync_turn() -> void:
	pass

## 进复盘。`rec` 是 `GameRecord.load_by_id()` / `load_from()` 的返回值。
func replay_enter(rec: Dictionary) -> bool:
	if rec.is_empty() or (rec["moves"] as Array).is_empty():
		return false
	_record_close_if_unfinished()
	_replay = GameReplay.new()
	_replay.replay_record = rec
	# ★★ 顺序铁律：**先把引擎的种子掰回谱头那颗，再校验指纹**。
	#   指纹里含种子（`seed=%08x`），而它的作用是"确认当前这张盘就是谱里那张盘" ——
	#   不先掰回，校验时拿的是**别的种子**算出来的指纹，必然不符 ⇒ 换种子进复盘被一律拒。
	#   首版顺序写反了，症状是判据 ⑩「换种子对照」红，而 ⑨「指纹不符拒载」仍绿
	#   —— 两条判据互相打架，**根因是顺序而不是任一条判据写错**。
	replay_lock_seed(int(rec.get("board_seed", -1)))
	# ★ 生成器指纹对不上就**拒绝加载**：几何由种子决定只对同一个游戏版本成立，
	#   改了生成器（哪怕一个 ε）后旧谱会重放出另一张盘 —— 那不是"复盘"，是编故事。
	if str(rec.get("generator_fingerprint", "")) != _record_generator_fp():
		push_warning("复盘：生成器指纹与当前版本不符，拒绝加载")
		_replay = null
		# ★ 别把**上一次**复盘的工具条留在屏上：此刻 `_replay` 已是 null，
		#   工具条还在的话每个按钮都"点了没反应"（`_rp_*` 一族开头都查 `_replay == null`）。
		_show_replay_hud(false)
		return false
	replay_anim_enabled = false
	_replay.replay_goto(0, self)
	# 交互层接上：信号 → 工具条（游标自己变的路径也能刷新），工具条 → `_rp_*` 一族。
	_rp_bind()
	_show_replay_hud(true)
	_rp_sync_ui()
	return true

## 退出复盘，回到可对局状态。★ 必须**彻底复原**（铁律：判据/临时态测完要复原，
##   这里同族 —— 漏复原的症状是"复盘完开新局看到旧手数"）。
func replay_exit() -> void:
	if _replay == null:
		return
	_replay.replay_playing = false
	_replay = null
	replay_anim_enabled = true
	_show_replay_hud(false)
	# ★ 清空态：按钮文案回"播放"、滑条归 0、信息栏清空（`_rp_info_text()` 在无谱时返回空）
	_rp_sync_ui()
	reset_game(true)
	# 对局 HUD 重新可见后，文案要按**当前**对局态重算 —— 不能让它停在复盘前的旧文案上
	_update_hud()

## 自检主体
func _replay_consistency_test() -> void:
	# ⚠ 这条**必须在随机档 + 指定种子**下跑：固定盘（彭罗斯等）是"无种子也确定"，
	#   那样这条判据退化成"重放两次一样吗"（可重现性恒真）⇒ **什么也没测**
	#   ——与"空集合上的判据 = 没测"同族。所以这里先切随机档并锁一颗种子。
	var bt_save: int = GameConfig.board_type
	var bs_save: int = GameConfig.board_size
	var ok: bool = true
	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.RANDOM
	_rand_seed = 20261002
	generate_board()
	print("[replaytest] === 回放一致性自检（随机盘 %d 格 / 种子 %d）==="
		% [tiles.size(), _rand_seed])

	# ---- ① 盘面重建：同种子重建 ⇒ 键集合与**键序无关的逐键内容**完全相同 ----
	#   注意这一条跑在**空盘**上（还没落子）—— 它验的是"种子决定论"这个地基本身。
	var fp_board_a: String = _replay_fingerprint()
	var tiles_a: int = tiles.size()
	generate_board()                      # 同 `_rand_seed` 再生成一次
	var fp_board_b: String = _replay_fingerprint()
	var c1: bool = fp_board_a == fp_board_b
	print("[replaytest] ① 盘面重建：同种子两次生成（%d 格 / 种子 %d）→ %s"
		% [tiles_a, _rand_seed, "✓ 逐键相同" if c1 else "✗ 不同"])
	if not c1:
		ok = false
		print("[replaytest] ① 细节·首生成：%s" % fp_board_a.substr(0, 160))
		print("[replaytest] ① 细节·再生成：%s" % fp_board_b.substr(0, 160))

	# ---- ② 落子重放：原局走 N 手（记逐手指纹）⇒ **同一张盘**上重放同一串 ⇒ 逐步对账 ----
	#   ★ 关键：不重建棋盘。上一步已证明重建是同一张盘，这一步只验"落子序列能不能复现"。
	#
	# ★★ 为什么**走 90 手而不是 20几手**（实测踩到的坑）：短局里**几乎不出现劫争**
	#   —— 首版 26 手实测 `ko` 恒为 -1，于是"重放后 ko 相同"是在比两个**恒等**的值
	#   ⇒ 负控刀"落子时不更新劫点"照过来**照样绿**（报"没牙齿"）。
	#   ⇒ 手数必须够长，让样本里**真的出现劫争**，那一项才是真比对。
	#   同时对**多个种子**各走一局，避免"恰好这一局没劫争"这种运气。
	#   ⚠ 终局（`game_over`）后不能继续落子 ⇒ 收集到一个子里，超出就收尾换种子。
	var plies: int = 0
	var fp_orig: String = ""
	var seq_all: Array[int] = []
	var marks_all: Array[String] = []
	var c2: bool = true
	var ko_plies: int = 0
	for round_i in 4:
		reset_game(true)
		_quiet_place = false
		var rng := RandomNumberGenerator.new()
		rng.seed = 777001 + round_i * 131
		var seq: Array[int] = []
		var marks: Array[String] = []
		marks.append(_replay_fingerprint())        # marks[0] = 开局
		for i in 90:
			if game_over:
				break
			if not _replay_pick(rng, seq):
				break                              # 挑不到合法点 ⇒ 如实收摊，不伪造
			if not place_stone(seq[seq.size() - 1], true):
				break                              # 真源拒收（自杀等）⇒ 收摊
			marks.append(_replay_fingerprint())     # marks[k] = 走完第 k 手
		# 本局出现过的劫争手数（样本自检：见下面那句注释）
		for k in range(1, marks.size()):
			if marks[k].find("|ko=-1,") < 0:
				ko_plies += 1
		if round_i == 0:
			plies = seq.size()
			fp_orig = _replay_fingerprint()
			seq_all = seq.duplicate()
			marks_all = marks.duplicate()
		else:
			# 其余几局也要真比对（不存档也要验），否则那几个种子只是走过场
			reset_game(true)
			_quiet_place = false
			for i in seq.size():
				if not place_stone(seq[i], true):
					c2 = false
					print("[replaytest] ② 第%d局第%d手重放被拒（tile=%d）"
						% [round_i + 1, i + 1, seq[i]])
					break
				if _replay_fingerprint() != marks[i + 1]:
					c2 = false
					break

	# 原样重放第一局：把棋盘清回开局（**不重新 generate_board**），再走同一串
	reset_game(true)
	_quiet_place = false
	for i in seq_all.size():
		if not place_stone(seq_all[i], true):
			c2 = false
			print("[replaytest] ② 第%d手重放被拒（tile=%d）—— 谱面序列与棋理不自洽"
				% [i + 1, seq_all[i]])
			break
		var got: String = _replay_fingerprint()
		if got != marks_all[i + 1]:
			c2 = false
			print("[replaytest] ② 第%d手后不一致｜期望尾部 %s｜实得尾部 %s"
				% [i + 1, marks_all[i + 1].substr(marks_all[i + 1].find("|ko=")),
					got.substr(got.find("|ko="))])
			break
	# ★★ 样本自检（把"没测到"变成一条**看得见的红**）：劫争样本数必须 > 0。
	#   否则"重放后 ko 相同"这一项是**恒真式**（两个值都恒为 -1）⇒ 负控刀会报"没牙齿"，
	#   而根因是**判据的样本太平凡**，不是刀不对。
	var c2s: bool = ko_plies > 0
	print("[replaytest] ② 落子重放：首局 %d 手·共 4 局逐步对账 → %s｜劫争样本 %d 手%s"
		% [plies, "✓ 每步逐键相同" if c2 else "✗ 有一步对不上", ko_plies,
			"" if c2s else " —— ★ 样本里**没有劫争** ⇒ 「ko 相同」恒成立，那一项没测到"])
	if not c2:
		ok = false
	if not c2s:
		ok = false

	# ---- ③ 全局口径：重放终局 vs 原局终局，整串指纹逐键相同 ----
	var fp_replay: String = _replay_fingerprint()
	var c3: bool = fp_replay == fp_orig
	print("[replaytest] ③ 终局指纹：%d / %d 字符 → %s"
		% [fp_orig.length(), fp_replay.length(),
			"✓ 同一局面" if c3 else "✗ 分叉"])
	if not c3:
		ok = false
		print("[replaytest] ③ 尾部·原局：%s" % fp_orig.substr(fp_orig.find("|ko=")))
		print("[replaytest] ③ 尾部·重放：%s" % fp_replay.substr(fp_replay.find("|ko=")))

	# ---- ④ ★ 反向对照：换一个种子重建 ⇒ **必须不同**（否则 ① 恒真）----
	#   这条不是"应该不同"，而是守住"① 真的在比内容" —— 若两种盘型碰巧一致，
	#   ① 就退化成恒真式（"重建两次一样吗"恒成立），**什么也没测**。
	var seed_a: int = _rand_seed
	_rand_seed = 20261003
	generate_board()
	var fp_other: String = _replay_fingerprint()
	_rand_seed = seed_a
	var c4: bool = fp_other != fp_board_a
	print("[replaytest] ④ 反向对照：换种子重建 → %s（期望与①不同）"
		% ("✓ 确实不同" if c4 else "✗ 竟然相同 ⇒ ① 是恒真式"))
	if not c4:
		ok = false

	# ---- 复原现场（★ 判据扫多档/多形态后**必须复原**，否则污染后续自检）----
	GameConfig.board_type = bt_save
	GameConfig.board_size = bs_save
	generate_board()
	reset_game(true)
	_quiet_place = false

	print("[replaytest] 结论：%s" % ("通过 ✓" if ok else "失败 ✗ 回放不一致"))
	get_tree().quit()

# ====== 棋谱判据（2026-10-02，棋谱阶段①）======
## 与 `--replaytest` 的分工（别混）：
##   `--replaytest` 验的是**地基**："同种子 + 同一串手数 ⇒ 同一局面"，用的是内存里的手数数组。
##   `--grecotest` 验的是**棋谱功能**：手数真的**被记下来了**（逐字段对账）、**落盘了**、
##   **读回来还能用**、**悔棋会同步截**、**终局写了条目**、**自动化运行不碰玩家的库**。
## ★ 两条必须都绿：只有 replaytest 时"功能压根没记账"照样全绿（那是地基，不是功能）。

## 采样器：只走合法落点（与 `_replay_pick` 同一口径，同一条理由：不查合法性的话
##   "谱里有这手"就意味着棋谱能记下这局里根本下不出来的东西）。
func _record_pick(rng: RandomNumberGenerator, seq: Array[int]) -> bool:
	for tries in 200:
		var t: int = rng.randi_range(0, tiles.size() - 1)
		if can_place_at(t):
			seq.append(t)
			return true
	return false

## ★★ 逐手对拍：拿 `moves` 与 `_hist` **逐字段**比。
##   两条链**故意各写各的**（见 `_record` 声明处的理由），所以这份对拍才有牙齿：
##   若两者同源（一个函数里一起 append），"记错了"会同时错成一致 ⇒ 比出来永远 ✓。
##   ★ 口径差异（故意的，不算错）：`_hist` 记 `ko_before`（本手**之前**），
##   谱记 `ko`（本手**之后**）⇒ 所以对拍 ko 用的是**下一手**的 `ko_before`。
##   最后一手没有"下一手" ⇒ 用一个独立算出来的真值补（见调用处）。
func _record_cross_check(rec: Dictionary, label: String) -> Dictionary:
	var moves: Array = rec["moves"]
	var hist: Array = _hist
	var bad: Array[String] = []
	var cap_total: int = 0
	var ko_samples: int = 0
	for i in range(moves.size()):
		var mv: Dictionary = moves[i]
		var e: Dictionary = hist[i] if i < hist.size() else {}
		# tile / color：直接比（口径相同）
		if int(mv["tile"]) != int(e.get("tile", -999)):
			bad.append("第%d手 tile 谱=%d 栈=%d" % [i + 1, int(mv["tile"]), int(e.get("tile", -999))])
		if str(mv["color"]) != GameRecord.color_tag(int(e.get("color", -1))):
			bad.append("第%d手 color 谱=%s 栈=%s" % [i + 1, str(mv["color"]), str(e.get("color", -1))])
		# captures：谱记"提了几子"，栈记"提了哪些子"⇒ 比**个数**
		var n_caps: int = (e.get("captured", []) as Array).size()
		cap_total += n_caps
		if int(mv["captures"]) != n_caps:
			bad.append("第%d手 captures 谱=%d 栈=%d" % [i + 1, int(mv["captures"]), n_caps])
		# ko：本手之后的值 == 下一手的 ko_before（最后一手跳过，调用处另算）
		if i + 1 < hist.size():
			var ko_next: int = int((hist[i + 1] as Dictionary)["ko_before"])
			if int(mv["ko"]) != ko_next:
				bad.append("第%d手 ko 谱=%d 下一手 ko_before=%d" % [i + 1, int(mv["ko"]), ko_next])
			if ko_next != -1:
				ko_samples += 1
		# ply 必须连号（1起）—— 序号的错是"读回来第几手对不上"，复盘时才现形
		if int(mv["ply"]) != i + 1:
			bad.append("第%d手 ply=%d" % [i + 1, int(mv["ply"])])
	return {"bad": bad, "caps": cap_total, "ko_samples": ko_samples, "n": moves.size()}


func _record_test() -> void:
	# ⚠ 与 replaytest 同理：**必须跑随机档 + 指定种子**。固定盘"无种子也确定"，
	#   而阶段① 的核心风险是"重放回到同一张盘" ⇒ 固定档上这条判据会退化成可重现性恒真。
	var bt_save: int = GameConfig.board_type
	var bs_save: int = GameConfig.board_size
	var km_save: int = komi
	var mode_save: int = game_mode
	var ok: bool = true
	var bad_shape: Array[String] = []     # 铁律 12：判据条漏写判断位 ⇒ 这里变成"带名字的红"

	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.RANDOM
	komi = 7
	game_mode = VS_AI
	_rand_seed = 20261003
	generate_board()
	reset_game(true)
	_quiet_place = false
	print("[grecotest] === 棋谱自检（随机盘 %d 格 / 种子 %d / 贴目 %d）==="
		% [tiles.size(), _rand_seed, komi])

	# ---- ① 谱头：盘型/尺寸/种子/贴目/版本/生成器指纹 ----
	var h: Dictionary = _record
	var head_ok: bool = int(h.get("board_type", -1)) == GameConfig.board_type \
		and int(h.get("board_size", -1)) == GameConfig.board_size \
		and int(h.get("board_seed", -1)) == _rand_seed \
		and int(h.get("komi", -1)) == komi \
		and int(h.get("format_version", -1)) == GameRecord.FORMAT_VERSION \
		and str(h.get("game_build", "")) == GameRecord.GAME_BUILD \
		and str(h.get("generator_fingerprint", "")) != "" \
		and (h.get("result") == null)
	# ★ 指纹必须真的**逐位跟着几何参数走**：把种子格式化成 hex 那一段故意写进去了，
	#   判据断言"指纹里含当前种子的 hex" —— 否则有人把 `_record_generator_fp()` 改成常量返回，
	#   "指纹存在"这条照样绿，而"改了生成器旧谱会被拒"这件事就没测了。
	var fp: String = str(h.get("generator_fingerprint", ""))
	var fp_has_seed: bool = fp.find("%08x" % _rand_seed) >= 0
	print("[grecotest] ① 谱头：盘型%d/尺寸%d/种子%d/贴目%d/v%d + 指纹(%d 字节，含种子 %s) → %s"
		% [int(h.get("board_type", -1)), int(h.get("board_size", -1)), int(h.get("board_seed", -1)),
			int(h.get("komi", -1)), int(h.get("format_version", -1)), fp.length(),
			"✓" if fp_has_seed else "✗", "✓" if head_ok else "✗"])
	if not head_ok:
		ok = false
		bad_shape.append("①")
	if not fp_has_seed:
		ok = false
		bad_shape.append("① 指纹不含种子")

	# ---- ② 造局，逐手与 `_hist` 对拍 ----
	#   ★★ 为什么**跑 4 局**而不是一局（replaytest ② 的同一条教训，这里是它的第三例）：
	#   首版只跑一局 60 手，实测 **提子样本 0 子·劫争样本 0 手** ⇒ "captures 对得上"
	#   在比一串恒为 0 的值、"ko 对得上"在比一串恒为 -1 的值 ⇒ **两条都是恒真式**，
	#   而 ② 那个"逐字段一致"照样绿。多局累积把两个样本都变成非零。
	#   ⇒ 兜底不是"改成 120 手"而是"多局 + 把样本数做成会红的判据"（下面 c2s）。
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var seq: Array[int] = []
	var placed: int = 0
	var caps_all: int = 0
	var ko_all: int = 0
	var bad_all: Array[String] = []
	var n_all: int = 0
	var hist_all: int = 0
	for round_i in 4:
		reset_game(true)
		_quiet_place = false
		seq.clear()
		placed = 0
		for i in 60:
			if game_over:
				break
			if i == 30:
				_apply_pass()            # 中间插一手停手：谱必须也记它
				continue
			if not _record_pick(rng, seq):
				break
			if not place_stone(seq[placed], true):
				break
			placed += 1
		var cc: Dictionary = _record_cross_check(_record, "②")
		for b in (cc["bad"] as Array):
			bad_all.append("第%d局·%s" % [round_i + 1, str(b)])
		caps_all += int(cc["caps"])
		ko_all += int(cc["ko_samples"])
		if round_i == 0:
			# ★ 规模只在**第一局**取：循环结束时 `_hist`/`_record` 装的是最后一局，
			#   拿最后一局的栈去比第一局的手数会**恒不相等**（自己和自己错位）。
			n_all = int(cc["n"])
			hist_all = _hist.size()
	print("[grecotest] ② 逐手对拍：4 局 × %d 手（提子 %d 子·劫争 %d 手）→ %s%s"
		% [n_all, caps_all, ko_all, "✓ 逐字段一致" if bad_all.is_empty() else "✗",
			"" if bad_all.is_empty() else "｜首错：" + bad_all[0]])
	var c2: bool = bad_all.is_empty() and n_all == hist_all
	if not c2:
		ok = false
	# ★★ **样本非平凡**（铁律 13 ⑨）：把"提子/劫争确实出现过"做成会红的判据，
	#   而不是指望测试作者记得挑一手会提子的局面 —— 手数一改它就自己报红。
	var c2s: bool = caps_all > 0 and ko_all > 0
	print("[grecotest] ② 样本非平凡：提子样本 %d 子（期望 >0）· 劫争样本 %d 手（期望 >0）→ %s"
		% [caps_all, ko_all, "✓" if c2s else "✗ 这一局的样本平凡，上面那条比对在比恒等的值"])
	if not c2s:
		ok = false
	# ★ 最后一个 ko：谱里最后一手记的是"本手之后"的劫点，而它没有"下一手"可对拍
	#   ⇒ 直接比盘面真源 `ko_point`（不是比两个恒等的东西）。
	var mv_all: Array = _record["moves"]
	var last_ko: int = -2 if mv_all.is_empty() else int(mv_all[mv_all.size() - 1]["ko"])
	var c2k: bool = last_ko == ko_point
	print("[grecotest] ② 末手 ko：谱 %d / 盘面 ko_point %d → %s" % [last_ko, ko_point,
		"✓" if c2k else "✗"])
	if not c2k:
		ok = false

	# ---- ③ 探测性落子不得入谱（`_quiet_place` 守卫；负控刀 R5 盯的就是它）----
	var n_before: int = (_record["moves"] as Array).size()
	_quiet_place = true
	var probe_tile: int = -1
	for t in range(tiles.size()):
		if can_place_at(t):
			place_stone(t, false)
			probe_tile = t
			break
	_quiet_place = false
	var n_after: int = (_record["moves"] as Array).size()
	var c3: bool = n_before == n_after and n_before == (_hist.size())
	print("[grecotest] ③ 探测性落子不入谱：手数 %d → %d（试探点 t%d）→ %s"
		% [n_before, n_after, probe_tile, "✓" if c3 else "✗"])
	if not c3:
		ok = false
	#★★ 判据自身的坑（首版真踩了）：探针**是真落子**（只是不记账），
	#   所以 t%d 上**留着一颗子**。若不清掉，⑤ 的"原局指纹"就多了一颗子，
	#   而"按谱重放"那侧没有 ⇒ ⑤ 会红在一个**与谱无关**的差异上（t1=1 vs t1=0），
	#   读起来像"谱记错了"，实际是判据污染了自己的现场。⇒ 测完必须复原。
	if probe_tile >= 0:
		board[probe_tile] = Stone.EMPTY

	# ---- ④ 悔棋同步截谱 ----
	var n_pre_undo: int = (_record["moves"] as Array).size()
	var hist_pre: int = _hist.size()
	undo_to_my_turn()
	var n_post_undo: int = (_record["moves"] as Array).size()
	var c4: bool = n_post_undo < n_pre_undo and n_post_undo == _hist.size() \
		and n_pre_undo == hist_pre
	print("[grecotest] ④ 悔棋截谱：%d → %d 手（栈同刻 %d 手）→ %s"
		% [n_pre_undo, n_post_undo, _hist.size(), "✓" if c4 else "✗ 谱与盘面错位"])
	if not c4:
		ok = false

	# ---- ⑤ 落盘 → 读回 → 逐字段对账 + **按读回的谱重放到末手回到同一局面** ----
	#   ⚠ 这一条是阶段① 真正的 teeth（规划 §阶段①）：光"能存能读"是恒真式，
	#   必须"读回来的谱能重放出原局"。
	GameRecord.finish(_record, GameRecord.REASON_SCORE, Stone.BLACK, 88, 79)
	var path: String = GameRecord.save(_record)
	var c5a: bool = path != "" and FileAccess.file_exists(path)
	var back: Dictionary = GameRecord.load_from(path) if c5a else {}
	# ★★ 自动化闸（铁律 8）：落盘必须改道自检盘，**绝不能**写进玩家的 `user://records/`。
	#   这条判据要**真写一次**再量"玩家目录没被动"（只判 is_automated_run() 是恒真式）。
	var c5b: bool = path.begins_with(GameRecord.DIR_SELFTEST)
	print("[grecotest] ⑤ 落盘：%s → %s｜改道自检盘（玩家库 %s 未被写）→ %s"
		% [str(_record.get("id", "?")), path.replace("user://", ""),
			"user://records/" if c5b else "⚠ " + GameRecord.DIR_RECORDS, "✓" if c5a and c5b else "✗"])
	if not c5a:
		ok = false
	if not c5b:
		ok = false
	# 读回：逐字段（头 + 每手 + 终局条目）
	var c5c: bool = true
	if back.is_empty():
		c5c = false
		bad_shape.append("⑤ 读回为空")
	else:
		for key in ["format_version", "game_build", "board_type", "board_size", "board_seed", "komi", "mode"]:
			if str(back.get(key, "??")) != str(_record.get(key, "??")):
				c5c = false
				bad_shape.append("⑤ 读回头字段 %s = %s（应为 %s）" % [key, str(back.get(key)), str(_record.get(key))])
		var bm: Array = back.get("moves", [])
		if bm.size() != (_record["moves"] as Array).size():
			c5c = false
			bad_shape.append("⑤ 读回手数 %d ≠ %d" % [bm.size(), (_record["moves"] as Array).size()])
		else:
			for i in range(bm.size()):
				var a: Dictionary = bm[i]
				var b: Dictionary = (_record["moves"] as Array)[i]
				for f in ["ply", "tile", "color", "captures", "ko"]:
					if str(a.get(f, "?")) != str(b.get(f, "?")):
						c5c = false
						bad_shape.append("⑤ 第%d手 %s 读回=%s 原=%s" % [i + 1, f, str(a.get(f)), str(b.get(f))])
		var rres: Dictionary = GameRecord.result_of(back)
		if str(rres.get("winner", "")) != "BLACK" or str(rres.get("reason", "")) != GameRecord.REASON_SCORE \
				or int(rres.get("plies", -1)) != (back.get("moves", []) as Array).size():
			c5c = false
			bad_shape.append("⑤ 读回终局条目 = %s" % str(rres))
	# ★★★ **真正的 teeth**：把读回来的谱**从头重放**一遍，必须回到与原局**逐键相同**的盘面。
	#   为什么单独一条而不用"往返字段相同"顶替：字段相同只证明 JSON 没丢东西，
	#   **不证明这份谱描述的局面是对的**（比如 `_normalize` 把tile 转成了 float 键、
	#   或 seed 记错 ⇒ 字段都"相同"但重放出一张别的盘）。这一条才把"谱 = 局面"钉死。
	var c5d: bool = false
	if c5a and not back.is_empty():
		# 复原原局盘面（记一份完整指纹）
		var fp_orig: String = _replay_fingerprint()
		# 钉住种子重建盘面 + 空盘
		var keep_seed: int = _rand_seed
		_rand_seed = int(back["board_seed"])
		generate_board()
		reset_game(true)
		_quiet_place = false
		var replay_ok: bool = true
		var bad_ply: int = -1
		var bad_tile: int = -1
		var color_bad: int = -1        # 谱里的 color 与重放时"轮到谁"不一致的第一手（-1 = 全对）
		for i in range((back["moves"] as Array).size()):
			var mv: Dictionary = (back["moves"] as Array)[i]
			var tl: int = int(mv["tile"])
			# ★★ 颜色交叉验证（**这条是必需的，不是锦上添花**）：重放只把 `tile` 喂给
			#   `place_stone()`，颜色由盘面轮次自己定 ⇒ **谱里的 `color` 记错时重放照样成功**
			#   （负控刀 R2 实测：② 红了而 ⑤ 仍绿）。而 `color` 是复盘器信息栏与
			#   "这一步是谁走的"显示的依据 ⇒ 记错了玩家看到的是错的。
			#   ⇒ 这里显式断言"重放到第 i 手时该轮的颜色 == 谱里记的颜色"。
			#   ⚠ 停一手（tile < 0）也要比：那一下也是某一方做的。
			if str(mv["color"]) != GameRecord.color_tag(current_player) and color_bad < 0:
				color_bad = i + 1
			if tl < 0:
				_apply_pass()              # 停一手：走真实路径（它会自己判终局）
				continue
			# ★ 走真实落子入口（含棋理判据）—— 不"照着谱面直接写 board"：
			#   否则棋谱就成了绕过棋理的后门（规划 §阶段① 风险条目）。
			if not place_stone(tl, true):
				replay_ok = false
				bad_ply = i + 1
				bad_tile = tl
				break
		if replay_ok and color_bad > 0:
			print("[grecotest] ⑤ 细节·第 %d 手 color 与重放轮到的手不一致（谱记的 color 是显示字段，重放本身察觉不到 ⇒ 这条交叉验证是唯一牙齿）"
				% color_bad)
		if replay_ok:
			var fp_replay: String = _replay_fingerprint()
			c5d = fp_replay == fp_orig and color_bad < 0
			if fp_replay != fp_orig:
				print("[grecotest] ⑤ 细节·原局: %s" % fp_orig.substr(0, 200))
				print("[grecotest] ⑤ 细节·重放: %s" % fp_replay.substr(0, 200))
		else:
			print("[grecotest] ⑤ 细节·按谱重放在第 %d 手被真源拒绝（tile %d）" % [bad_ply, bad_tile])
		_rand_seed = keep_seed
	print("[grecotest] ⑤ 按读回的谱重放到末手（%d 手）→ %s"
		% [(back.get("moves", []) as Array).size(), "✓ 回到同一局面" if c5d else "✗"])
	if not c5c:
		ok = false
	if not c5d:
		ok = false

	# ---- ⑥ 索引：落盘后索引里应有这一条，且字段与谱头一致 ----
	#   ★★ 判据自身的坑（首版真踩了）：⑤ 里为了重放**重建过盘面**，`_record` 已经是
	#   `reset_game()` 开的新谱（0 手、result=null）⇒ 拿它去查索引必然"查不到"。
	#   ⇒ 判据必须认**落盘时那份 id**，不是"当前 `_record`"。
	var idx: Array = GameRecord.list_index()
	var saved_id: String = str(back.get("id", "")) if not back.is_empty() else ""
	var hit: Dictionary = {}
	for e in idx:
		if str((e as Dictionary).get("id", "")) == saved_id:
			hit = e
	var c6: bool = not hit.is_empty() and int(hit.get("plies", -1)) == (back.get("moves", []) as Array).size() \
		and int(hit.get("board_seed", -1)) == int(back.get("board_seed", -1)) \
		and str(hit.get("reason", "")) == GameRecord.REASON_SCORE
	print("[grecotest] ⑥ 索引：%d 条·命中本局 %s（%d 手/种子%d/%s）→ %s"
		% [idx.size(), saved_id, int(hit.get("plies", -1)), int(hit.get("board_seed", -1)),
			str(hit.get("reason", "-")), "✓" if c6 else "✗"])
	if not c6:
		ok = false

	# ---- ⑦ 中断标记：半局谱重开 ⇒ 落盘且 reason=INTERRUPTED（不是悄悄丢掉）----
	reset_game(true)
	_quiet_place = false
	var n_half: int = 0
	for i in 8:
		if not _record_pick(rng, seq):
			break
		if not place_stone(seq[placed], true):
			break
		placed += 1
		n_half += 1
	var half_id: String = ""
	_record_close_if_unfinished()
	var half_res: Dictionary = GameRecord.result_of(_record)
	half_id = str(_record.get("id", ""))
	var c7: bool = str(half_res.get("reason", "")) == GameRecord.REASON_INTERRUPTED \
		and int(half_res.get("plies", -1)) == n_half
	#★ 并且这份半局谱**真的落盘了**（能读回来）—— 只判内存里那个标记是不够的：
	#   漏落盘的症状是"复盘列表里找不到那局"，而内存里的标记照样是对的。
	var half_path: String = "%s/%s.json" % [GameRecord.records_dir(), half_id]
	var c7b: bool = c7 and half_id != "" and FileAccess.file_exists(half_path)
	var c7c: bool = c7b and str(GameRecord.result_of(GameRecord.load_from(half_path)).get("reason", "")) \
		== GameRecord.REASON_INTERRUPTED
	print("[grecotest] ⑦ 中断标记：%d 手半局重开 → reason=%s → %s｜已落盘且读得回 → %s"
		% [n_half, str(half_res.get("reason", "无")), "✓" if c7 else "✗",
			"✓" if c7c else "✗"])
	if not c7:
		ok = false
	if not c7c:
		ok = false

	# ---- ⑧ 终局幂等：已写终局条目的谱，再 `_record_flush()` 不得改写结局 ----
	#   （`_apply_pass()` 的 passes>=2 与联机平行路径都可能二次碰到终局）
	reset_game(true)
	_quiet_place = false
	var probe2: Array[int] = []
	_record_pick(rng, probe2)
	place_stone(probe2[0], true)
	GameRecord.finish(_record, GameRecord.REASON_SCORE, Stone.BLACK, 11, 22)
	GameRecord.finish(_record, GameRecord.REASON_RESIGN, Stone.WHITE, 33, 44)   # 第二次必须被忽略
	var c8: bool = str((_record["result"] as Dictionary).get("reason", "")) == GameRecord.REASON_SCORE \
		and int((_record["result"] as Dictionary).get("score", [0, 0])[0]) == 11
	print("[grecotest] ⑧ 终局幂等：第二次 finish 被忽略（reason仍=%s）→ %s"
		% [str((_record["result"] as Dictionary).get("reason", "?")), "✓" if c8 else "✗"])
	if not c8:
		ok = false

	# ---- ⑨ SGF 导出（棋谱库「导出 SGF」的数据层）----
	# ★★ 先在**真路径**上造一份样本够厚的谱：⑧ 走完之后 `_record` 只剩 1 手，
	#   拿 1 手去跑"往返 / 撞车"是**退化样本**（铁律 27：判据必须跑在会出问题的那一档）。
	#   造法与 ② 同款（同一套 `_record_pick` + `place_stone(…, true)` 真实落子路径），
	#   中间插一手停手 —— 顺带让 `tt` 那条分支也有样本。
	reset_game(true)
	_quiet_place = false
	var rng9 := RandomNumberGenerator.new()
	rng9.seed = 909090
	var seq9: Array[int] = []
	var placed9: int = 0
	for i in 60:
		if game_over:
			break
		if i == 30:
			_apply_pass()
			continue
		if not _record_pick(rng9, seq9):
			break
		if not place_stone(seq9[placed9], true):
			break
		placed9 += 1
	var rec9: Dictionary = _record
	# ★ 三层分开量（铁律 13：性质不同不许混进一个布尔）：
	#   ⑨a 结构：属性在不在、着法条数对不对
	#   ⑨b **往返**：`_sgf_point` → `_sgf_point_decode` 必须回到原瓦片编号，
	#       而且**不同瓦片不许撞成同一个值**（单看"能读回"漏掉的就是这一条）
	#   ⑨c 转义：值里带 `]` / `\` 时属性数不许变（`]` 提前收尾 ⇒ 后面整段被当成新属性）
	var sgf: String = GameRecord.to_sgf(rec9)
	var mv_arr: Array = rec9["moves"]
	# ⑨a：结构 —— 首字符 `(;`、末字符 `)`、着法条数 == 谱手数
	var n_sgf_moves: int = 0
	for ch in sgf:
		if ch == ";":
			n_sgf_moves += 1
	# 减掉根节点自身那个 `;`（`(;GM[1]…` 的根也是一个 `;`）
	n_sgf_moves -= 1
	var c9a: bool = sgf.begins_with("(;") and sgf.ends_with(")") \
		and n_sgf_moves == mv_arr.size() \
		and sgf.contains("GM[1]") and sgf.contains("SZ[") and sgf.contains("CA[UTF-8]")
	print("[grecotest] ⑨a SGF 结构：%d 字节·着法 %d 条（谱 %d 手）·GM/SZ/CA 齐 → %s"
		% [sgf.length(), n_sgf_moves, mv_arr.size(), "✓" if c9a else "✗"])
	if not c9a:
		ok = false
	# ⑨b：往返 —— **有效分母**必须单列（空谱/全 pass 的谱上这条恒真，铁律 27）
	var rt_hit: int = 0          # 真正参与往返的瓦片数（不含 pass）
	var rt_bad: int = -1         # 第一个对不上的瓦片编号
	var pass_ok: bool = true
	var seen: Dictionary = {}    # 编码值 → 瓦片编号（查"撞车"）
	var collide: int = -1
	var collide_two: int = -1
	for mv in mv_arr:
		var t: int = int((mv as Dictionary).get("tile", -1))
		var enc: String = GameRecord._sgf_point(t)
		if t < 0:
			if enc != "tt":
				pass_ok = false
			continue
		rt_hit += 1
		if GameRecord._sgf_point_decode(enc) != t and rt_bad < 0:
			rt_bad = t
		if seen.has(enc) and int(seen[enc]) != t and collide < 0:
			collide = t
			collide_two = int(seen[enc])
		seen[enc] = t
	var c9b: bool = rt_hit > 0 and rt_bad < 0 and collide < 0 and pass_ok
	print("[grecotest] ⑨b 瓦片编号往返：%d 个不同瓦片·撞车 %s·首次不符 t%d·pass 编码=%s → %s"
		% [seen.size(), "t%d/t%d" % [collide, collide_two] if collide >= 0 else "无",
			rt_bad, str(pass_ok), "✓" if c9b else "✗"])
	if not c9b:
		ok = false
	if rt_hit <= 0:
		bad_shape.append("⑨b 有效分母为 0：本谱没有任何真实落子（往返判据在这份谱上恒真）")
	# ⑨c：转义 —— 判据要能回答"塞进值里的 `]` 有没有把属性提前截断"，
	#   所以必须**从导出的文档里把那一项读回来**比对。
	#   ★★ 首版这条写的是"`[` 的个数不变" —— **它没有牙齿**：漏转义时多出来的那截里
	#     根本没有 `[`，计数当然不变（即"刀改转义、判据仍绿"）。按"判据必须有牙齿"重写：
	#     走 `_sgf_escape`/`_sgf_unescape` 成对往返 + `sgf_value()` 从文档里取值对拍。
	#   ★★ 第二版又踩了一次（**判据自己选错了靶子**）：把 12 字符的样本塞进 `created_at`，
	#     而 `DT[]` 只取前 10 位（那是"日期"属性，截断是**设计**）⇒ 判据报红，
	#     但病灶在"我挑的字段会截断"，不在转义。⇒ 靶子改成 `generator_fingerprint`
	#     （原样使用、不截断），日期另给**恰好 10 字符**的样本单独量一次。
	var nasty: Array[String] = ["2026-10-08]x", "a]b\\c]d", "\\", "]", "（）正常中文值"]
	var esc_bad: Array[String] = []
	for s_ins in nasty:
		var p2: Dictionary = rec9.duplicate(true)
		p2["generator_fingerprint"] = s_ins
		var doc: String = GameRecord.to_sgf(p2)
		if GameRecord.sgf_value(doc, "GF") != s_ins:
			esc_bad.append("文档取值不符:" + s_ins)
		if GameRecord._sgf_unescape(GameRecord._sgf_escape(s_ins)) != s_ins:
			esc_bad.append("往返不符:" + s_ins)
	# 日期字段单独一条（10 字符，正好不被 `substr(0,10)` 截掉）
	var p3: Dictionary = rec9.duplicate(true)
	p3["created_at"] = "2026-10-]x"
	if GameRecord.sgf_value(GameRecord.to_sgf(p3), "DT") != "2026-10-]x":
		esc_bad.append("DT 取值不符:2026-10-]x")
	var c9c: bool = esc_bad.is_empty()
	print("[grecotest] ⑨c SGF 转义：%d 组含 `]`/`\\` 的值 + DT 一条，从导出文档读回须逐字节相同 → %s%s"
		% [nasty.size(), "✓" if c9c else "✗", "" if c9c else "｜首错：" + esc_bad[0]])
	if not c9c:
		ok = false
	# ⑨d：**空谱**不许崩、也不许吐半截（`to_sgf({})` 返回空串）
	var c9d: bool = GameRecord.to_sgf({}) == ""
	print("[grecotest] ⑨d 空谱保护：to_sgf({}) = %s → %s"
		% [("空串" if c9d else GameRecord.to_sgf({})), "✓" if c9d else "✗"])
	if not c9d:
		ok = false

	# ---- 元判据（铁律 12 ②）：把上面"写歪了"的地方变成带名字的红，而不是静默通过 ----
	if not bad_shape.is_empty():
		for b in bad_shape:
			print("[grecotest] ✗ 细节·%s" % b)
		ok = false

	# ---- 复原现场（★ 判据扫多档/多形态后必须复原）----
	GameConfig.board_type = bt_save
	GameConfig.board_size = bs_save
	komi = km_save
	game_mode = mode_save
	generate_board()
	reset_game(true)
	_quiet_place = false

	print("[grecotest] 结论：%s" % ("通过 ✓" if ok else "失败 ✗ 棋谱记账/落盘不对"))
	get_tree().quit()

# ====== 复盘器判据（--browsetest，棋谱阶段②）======
## 造一份"原局快照序列"：造谱时**每落一手**就把局面指纹存下来，
## 供后面逐手跳转时对账。★ 必须存**值**（指纹字符串）而不是 board 的引用 ——
##   存引用会踩别名坑（下一手就把前面的"快照"改了），而症状是"逐手比对全绿"——
##   比的是同一份东西被自己改。**与铁律 13 ⑬ 同族。**
func _browse_collect(seq: Array[int], snaps: Array[String]) -> void:
	for _i in seq.size():
		place_stone(_i, false)
		snaps.append(_replay_fingerprint())

## 自检主体
func _replay_browse_test() -> void:
	# ⚠ 必须随机档 + 指定种子：复盘的全部前提是"重放回到同一张盘"，
	#   固定档（彭罗斯等）"无种子也确定" ⇒ 这条判据退化成可重现性恒真。
	var bt_save: int = GameConfig.board_type
	var bs_save: int = GameConfig.board_size
	var km_save: int = komi
	var mode_save: int = game_mode
	var ok: bool = true
	var bad_shape: Array[String] = []     # 铁律 12 ②：元判据
	var anim_save: bool = replay_anim_enabled

	GameConfig.board_type = GameConfig.BOARD_PENROSE
	GameConfig.board_size = GameConfig.RANDOM
	komi = 7
	game_mode = VS_AI
	_rand_seed = 20261004
	generate_board()
	print("[browsetest] === 复盘器自检（随机盘 %d 格 / 种子 %d）===" % [tiles.size(), _rand_seed])

	# ---- 造局：60 手 + 逐手快照 ----
	reset_game(true)
	_quiet_place = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 909090
	var seq: Array[int] = []
	for _i in 60:
		if not _record_pick(rng, seq):
			break
	var snaps: Array[String] = []
	_browse_collect(seq, snaps)
	# ★★ 刻意在第 18 手插一次「停一手」：负控刀 BR11（停一手不入复盘）首轮报"没牙齿"，
	#   根因是**判据造的谱里根本没有停一手**（`_record_pick` 只放子）⇒ 刀改的是一条
	#   **在判据样本之外**的路径。⇒ 样本为空 = 判据在空集上跑（铁律 13 ⑨ 的第四例）。
	#   这条插在第 18 手而不是末尾：末尾的停一手会连着触发两次终局，后面就没手可走了。
	if seq.size() > 18:
		_apply_pass()
		snaps.append(_replay_fingerprint())
	# 造完局直接给谱一个终局条目（否则 `GameRecord.save()` 会拒绝落盘 —— 阶段① 的闸）
	GameRecord.finish(_record, GameRecord.REASON_SCORE, Stone.EMPTY, 10, 8)
	var path: String = GameRecord.save(_record)
	var back: Dictionary = GameRecord.load_from(path)
	# ★ 实际手数 = 快照数（含那次停一手）。后面所有循环上界都用它，**不用 seq.size()** ——
	#   seq 只记落子、不含停一手 ⇒ 拿它当上界会**漏比最后那一手**（少比一遍还照样全绿）。
	var np: int = snaps.size()
	var c1: bool = not back.is_empty() and (back["moves"] as Array).size() == np
	print("[browsetest] ① 谱可落盘可读回：%d 手（含停一手）→ %s"
		% [(back["moves"] as Array).size() if not back.is_empty() else -1, "✓" if c1 else "✗"])
	if not c1:
		ok = false
		bad_shape.append("① 读回 %d 手 ≠ 原局 %d 手" % [
			(back["moves"] as Array).size() if not back.is_empty() else -1, np])
		print("[browsetest] 结论：%s" % ("通过 ✓" if ok else "失败 ✗ 谱读不回来"))
		get_tree().quit()
		return

	# ---- ② 进复盘：第 0 手必须是**空盘**，且种子被钉死成谱头那颗 ----
	_replay = null
	var entered: bool = replay_enter(back)
	var c2a: bool = entered and _replay != null
	var empty_ok: bool = true
	for k in board.keys():
		if int(board[k]) != Stone.EMPTY:
			empty_ok = false
			break
	var c2: bool = c2a and empty_ok and _rand_seed == int(back["board_seed"]) \
		and replay_anim_enabled == false
	print("[browsetest] ② 进复盘：进得去=%s 第0手空盘=%s 种子=%d(应 %d) 动画闸关=%s → %s"
		% ["✓" if c2a else "✗", "✓" if empty_ok else "✗", _rand_seed,
			int(back["board_seed"]), "✓" if not replay_anim_enabled else "✗",
			"✓" if c2 else "✗"])
	if not c2:
		ok = false

	# ---- ③ ★ 逐手跳转：每一步的盘面与**原局该手快照**逐键相同 **且游标与盘面同步** ----
	#   这是复盘器的**核心**判据。若这条绿而 ④ 红，说明"跳得回去"只是回到了某个局面，
	#   不是**那一手**的局面（信息栏与棋盘会张冠李戴，且静默）。
	# ★★ 游标自洽是**必需的第二半**（负控刀 BR1 首轮就假咬住）：刀把 `replay_ply` 改小 1，
	#   而 `_rebuild()` 传的是**正确**的 target ⇒ **盘面全对**，只有游标错。
	#   只比盘面的话 ③ 照样绿 —— 与"重放察觉不到 color 错"同族：
	#   **判据量的东西和刀改的东西不是同一个**。
	var jumps: int = 0
	var jump_bad: int = -1
	var cursor_bad: int = -1
	for k in range(1, np + 1):
		if not _replay.replay_goto(k, self):
			jump_bad = k
			break
		if _replay_fingerprint() != snaps[k - 1]:
			jump_bad = k
			break
		if _replay.replay_ply != k:
			cursor_bad = k
			break
		jumps += 1
	var c3: bool = jump_bad < 0 and cursor_bad < 0 and jumps == np
	print("[browsetest] ③ 逐手跳转：%d/%d 手回到原局该手局面（错在第 %d 手）｜游标同步（错在第 %d 手）→ %s"
		% [jumps, np, jump_bad, cursor_bad, "✓" if c3 else "✗"])
	if not c3:
		ok = false

	# ---- ④ 执色交叉验证：跳到第 k 手后 current_player == 谱里第 k 手的落子方的对手 ----
	#   ★ 这条**必需**，不是锦上添花：盘面轮次由重放自然推进，而"第 k 手该谁落"是谱里的信息。
	#   两者不一致时棋盘是对的、信息栏是错的 —— 而"棋盘对"足以让 ③ 全绿。
	#   （同 `--grecotest` ⑤ 那条颜色交叉验证：显示字段错时重放察觉不到。）
	var turn_bad: int = -1
	for k in range(1, np + 1):
		_replay.replay_goto(k, self)
		var mv: Dictionary = (back["moves"] as Array)[k - 1]
		var want: int = (Stone.WHITE if str(mv["color"]) == "B" else Stone.BLACK)
		if current_player != want:
			turn_bad = k
			break
	var c4: bool = turn_bad < 0
	print("[browsetest] ④ 执色交叉验证：%d 手轮到谁 == 谱记落子方的对手 → %s"
		% [np, "✓" if c4 else "✗（第 %d 手错）" % turn_bad])
	if not c4:
		ok = false

	# ---- ⑤ 倒着跳：k → j 必须也回到原局第 j 手 ----
	#   ★ 为什么这条不是 ③ 的重复：顺序重放的实现很容易写成"只能往前"，
	#   而"点棋盘跳到更早的一手"是复盘最常用的操作。
	var back_bad: int = -1
	var half: int = np / 2
	_replay.replay_goto(np, self)
	for k in range(np, half - 1, -1):
		_replay.replay_goto(k, self)
		if _replay_fingerprint() != snaps[k - 1]:
			back_bad = k
			break
	var c5: bool = back_bad < 0
	print("[browsetest] ⑤ 倒着跳：末手 → 第 %d 手（错在第 %d 手）→ %s"
		% [half, back_bad, "✓" if c5 else "✗"])
	if not c5:
		ok = false

	# ---- ⑥ ★ 播放速率：K 帧后游标增量 == 速率 × 时间（**不是**"最终到了末手"）----
	#   "最终到了末手"是恒真式：任何速率（含 0）最后都停在末手。
	#   真正要量的是**时间轴在按设定的速率走**。
	replay_anim_enabled = false
	_replay.replay_goto(0, self)
	_replay.replay_playing = true
	var rate: float = 10.0
	var frames: int = 5
	var dt: float = 0.1
	var expect: int = int(rate * dt * frames)      # 10 手/秒 × 0.1s × 5 帧 = 5 手
	var moved: int = 0
	for _f in frames:
		moved += _replay.replay_tick(dt, self, rate)
	var want_moved: int = mini(expect, np)
	var c6: bool = moved == want_moved and _replay.replay_ply == want_moved
	# ★ 刻意**不用** `%g` 拼中文：`%g` 后面紧跟非格式字符时 GDScript 会**静默放弃整条格式化**，
	#   输出原样字符串（症状：明明写了 `% [...]`，打出来还是 `%d 帧×...`）。
	#   —— 与本工程第 15 号坑同族（引号/转义被吞 ⇒ 整条语句退化为字面量）。
	print("[browsetest] ⑥ 播放速率：%d 帧 × %d 毫秒 × %s 手/秒 → 推进 %d 手（应 %d）→ %s" % [
		frames, int(dt * 1000.0), str(rate), moved, want_moved, "✓" if c6 else "✗"])
	if not c6:
		ok = false

	# ---- ⑥a ★ 余量累积：慢速下**也必须**走（不足一手的部分留到下一帧）----
	#   为什么单列一条：⑥ 用的是"整除"速率（10 × 0.1 = 1 手/帧，零余数）⇒
	#   把 `int()` 换成任何常数都照样对。而**慢速**（3 手/秒 × 16ms = 0.048 手/帧）
	#   才是暴露点：`int()` 每帧扔掉小数 ⇒ 整数时间也走不满，慢速会"越播越慢"。
	#   ★ 样本平凡会让判据恒真（铁律 13 ⑨），所以刻意选**除不尽**的组合。
	_replay.replay_goto(0, self)
	_replay.replay_playing = true
	_replay.replay_frac = 0.0
	var slow_rate: float = 3.0
	var slow_dt: float = 0.016
	var slow_frames: int = 100
	for _f in slow_frames:
		_replay.replay_tick(slow_dt, self, slow_rate)
	# 3 手/秒 × 1.6 秒 = 4.8 手 ⇒ 游标必须是 4（不是 0，也不是 100）
	var c6a: bool = _replay.replay_ply == 4 and _replay.replay_frac > 0.0
	print("[browsetest] ⑥a 余量累积：%d 帧×%d 毫秒×%s 手/秒（应 4.8 手）→ 游标 %d·余量 %.3f → %s" % [
		slow_frames, int(slow_dt * 1000.0), str(slow_rate),
		_replay.replay_ply, _replay.replay_frac, "✓" if c6a else "✗"])
	if not c6a:
		ok = false

	# ---- ⑥b 播放到末手自动停（replay_finished 之后 playing 必须为假）----
	# ★ 为什么要**逐帧检查**而不是"跑到底再看"：末手之后**下一帧**会走
	#   `if replay_ply >= replay_total()` 那条 early-return 把 `playing` 置假，
	#   所以"跑过头再查"永远是假（负控刀 BR6 首轮就报"没牙齿"——它把恢复那行改成永真，
	#   判据照样绿）。必须量**刚抵达末手的那一帧**。
	_replay.replay_goto(0, self)
	_replay.replay_playing = true
	var c6b: bool = false
	for _f in 400:
		_replay.replay_tick(0.05, self, 40.0)
		if _replay.replay_ply == np and _replay.replay_playing:
			c6b = false          # 到末手了却还在播 ⇒ 停不下来
			break
		if _replay.replay_ply == np and not _replay.replay_playing:
			c6b = true           # 刚到末手就已停 ⇒ 正确
			break
	print("[browsetest] ⑥b 播到末手自停：游标 %d/%d·playing=%s → %s"
		% [_replay.replay_ply, np, str(_replay.replay_playing),
			"✓" if c6b else "✗"])
	if not c6b:
		ok = false

	# ---- ⑦ 信息栏与谱一致（手数/执色/提子数/劫争）----
	_replay.replay_goto(np, self)
	var info: Dictionary = _replay.replay_info()
	var last_mv: Dictionary = (back["moves"] as Array)[np - 1]
	var c7: bool = int(info.get("ply", -1)) == np \
		and str(info.get("color", "")) == str(last_mv["color"]) \
		and int(info.get("captures", -1)) == int(last_mv["captures"]) \
		and int(info.get("ko_after", -2)) == int(last_mv["ko"])
	print("[browsetest] ⑦ 信息栏：%d手·%s·提子%d·劫后%d → %s"
		% [int(info.get("ply", -1)), str(info.get("color", "?")),
			int(info.get("captures", -1)), int(info.get("ko_after", -2)),
			"✓" if c7 else "✗"])
	if not c7:
		ok = false

	# ---- ⑧ ★ 退出复原：这是规划里点名的"最容易出的鬼 bug" ----
	#   症状是"复盘完开新局看到旧手数"。判据量**伤害最大的那一刻**（退出后立刻查），
	#   不是退出后再走几手。
	var was_playing: bool = _replay.replay_playing
	replay_exit()
	var c8: bool = _replay == null and replay_anim_enabled == true
	var board_empty: bool = true
	for k in board.keys():
		if int(board[k]) != Stone.EMPTY:
			board_empty = false
			break
	# 复盘**不该**往 `_hist` 里攒手：退出后按悔棋不能退到"复盘的手数"上
	var hist_empty: bool = _hist.is_empty()
	c8 = c8 and board_empty and hist_empty and current_player == Stone.BLACK
	print("[browsetest] ⑧ 退出复原：复盘对象清空=%s 动画闸复原=%s 盘面空=%s 悔棋栈空=%s"
		% [str(_replay == null), str(replay_anim_enabled), str(board_empty), str(hist_empty)]
		+ "（退出前 playing=%s）→ %s" % [str(was_playing), "✓" if c8 else "✗"])
	if not c8:
		ok = false

	# ---- ⑨ 指纹不符的谱必须被拒（几何由种子决定只对同一版本成立）----
	var tampered: Dictionary = back.duplicate(true)
	tampered["generator_fingerprint"] = "t9|s9|it1/c9.9999|伪造"
	var c9: bool = not replay_enter(tampered) and _replay == null
	print("[browsetest] ⑨ 指纹不符拒载：伪造谱 → %s" % ("✓ 拒绝" if c9 else "✗ 竟被接受"))
	if not c9:
		ok = false

	# ---- ⑩ ★ 换种子对照：复盘**必须**把种子掰回谱头那颗 ----
	#   为什么必需（负控刀 BR10 首轮报"没牙齿"的根因）：判据整轮都跑在**造局那颗种子**上，
	#   而 `_rand_seed` 从头到尾没变过 ⇒ 删掉 `replay_lock_seed()` 里那行赋值也照样全绿。
	#   —— 这是"**顺带也会变真的量**"（铁律 13 ①）的又一例。
	#   ⚠ 样本必须**自洽**：不能只改 `board_seed` 而留着含旧种子的 `generator_fingerprint`
	#   （那会变成"指纹与种子互相矛盾"的无效样本，判红也说明不了什么）。
	#   做法：谱头**原样**（种子 + 指纹都不动），只把**引擎当前种子**换成另一颗，
	#   看进复盘时 `replay_lock_seed` 会不会把 `_rand_seed` 掰回谱头那颗。
	var seed_now: int = _rand_seed
	_rand_seed = 777001
	generate_board()
	reset_game(true)
	var entered2: bool = replay_enter(back)      # back 原样：它声明的就是 seed_now
	var c10: bool = entered2 and _replay != null and _rand_seed == seed_now
	print("[browsetest] ⑩ 换种子对照：引擎 777001 → 进谱（谱声明 %d）→ 引擎 %d%s → %s" % [
		seed_now, _rand_seed, "（已掰回）" if _rand_seed == seed_now else "（没掰）",
		"✓" if c10 else "✗"])
	if not c10:
		ok = false
	replay_exit()
	_rand_seed = seed_now
	generate_board()
	reset_game(true)

	# ---- ⑩b ★★ 换**盘型**对照：复盘必须把**整张盘**掰回谱里那张（不只是种子）----
	#   ★★ 为什么这条**必需**（2026-10-09 用户报的 bug；**修它之前这条就是绿的** = 铁律 4）：
	#     ⑩ 只验种子，`replay_lock_seed()` 也只掰种子；而 `_record_generator_fp()` 把
	#     `board_type`/`board_size` 编在指纹**最前面**（`t%d|s%d|…`）⇒ 一张在**别种盘型**
	#     上下的谱，进复盘时种子对上了、**盘型却还是当前选中的那张** ⇒ 指纹不符 ⇒ **拒载**
	#     ⇒ `_ready()` 静默落到普通对局（症状：点谱进去是一局**新棋**，且不报错）。
	#     ⇒ "能不能复盘"取决于谱里的盘型碰巧等不等于菜单当前选的盘型 —— 这正是
	#       **"AI 训练谱能播、我自己的谱不能播"**的成因（训练固定跑默认盘，自己会换着盘型玩）。
	#   ★ 样本必须**先站到别的盘上再造谱**：若仍在本盘上造，谱里的盘型就等于当前盘型，
	#     于是"切盘"这一步**无事可做** ⇒ 判据在修好之前也是绿的（**顺带也会变真的量**）。
	var bt_here: int = GameConfig.board_type
	var bs_here: int = GameConfig.board_size
	var seed_here: int = _rand_seed
	# ★ 尺寸也要**与当前不同**：若谱里的尺寸碰巧等于当前尺寸，则"切尺寸"这一步**无事可做**，
	#   于是 BR22b（把切尺寸那一行整块干掉）**打不红** ⇒ ⑩b 只守住盘型那一半、尺寸那半裸奔。
	#   ★ 只在 {STANDARD, ENHANCED} 里挑：RANDOM(0) 在筝形上没有随机档，不适用。
	var other_bs: int = GameConfig.ENHANCED if bs_here != GameConfig.ENHANCED else GameConfig.STANDARD
	# ① 先在**另一种盘**上造一份真谱 —— 盘型**和**尺寸都与当前不同
	GameConfig.board_type = GameConfig.BOARD_KITE
	GameConfig.board_size = other_bs
	_rand_seed = 0
	generate_board()
	reset_game(true)
	for _k in [0, 3, 6, 9, 12, 15]:
		place_stone(_k, false)
	GameRecord.finish(_record, GameRecord.REASON_SCORE, Stone.EMPTY, 4, 2)
	var other_path: String = GameRecord.save(_record)
	var other_rec: Dictionary = GameRecord.load_from(other_path)
	var other_fp: String = str(other_rec.get("generator_fingerprint", ""))
	var other_mv: int = (other_rec.get("moves", []) as Array).size()
	# ② 切回原盘 —— 此刻引擎站在"菜单当前那张盘"上，与 `other_rec` 声明的盘**不同**
	GameConfig.board_type = bt_here
	GameConfig.board_size = bs_here
	_rand_seed = seed_here
	generate_board()
	reset_game(true)
	var fp_diff_before: bool = _record_generator_fp() != other_fp   # 切盘前：确实对不上
	# ③ 走真源：切盘 → 建盘 → 指纹必须**对上**，且真进得去复盘
	replay_apply_board_spec(other_rec)
	generate_board()
	var fp_same_after: bool = _record_generator_fp() == other_fp   # 切盘后：对上了
	var entered3: bool = replay_enter(other_rec)
	var c10b: bool = other_mv > 0 and fp_diff_before and fp_same_after and entered3 \
		and _replay != null and GameConfig.board_type == GameConfig.BOARD_KITE \
		and GameConfig.board_size == other_bs
	print("[browsetest] ⑩b 换盘对照：谱在 筝形/s%d（fp %s）·引擎在 t%d/s%d → 切盘前对不上=%s·"
		% [other_bs, other_fp.substr(0, 6), bt_here, bs_here, str(fp_diff_before)]
		+ "切盘后对上=%s·进复盘=%s·手数 %d → %s"
		% [str(fp_same_after), str(entered3), other_mv, "✓" if c10b else "✗"])
	if not c10b:
		ok = false
		bad_shape.append("⑩b 换盘：盘型%d→%d 尺寸%d→%d 切盘前对不上=%s 切盘后对上=%s 进复盘=%s 手数=%d"
			% [bt_here, GameConfig.board_type, bs_here, GameConfig.board_size,
			str(fp_diff_before), str(fp_same_after), str(entered3), other_mv])
	replay_exit()
	# ④ 复原（**含删掉这份临时谱** —— 判据不许往盘里堆垃圾）
	GameConfig.board_type = bt_here
	GameConfig.board_size = bs_here
	_rand_seed = seed_here
	generate_board()
	reset_game(true)
	if other_path != "":
		DirAccess.remove_absolute(other_path)

	# ====== 交互层判据（2026-10-08，棋谱阶段② 交互层）======
	# ★ 全部走 UI 的**真实入口**（`_rp_on_*` / `_input` / `_process` / 滑条的 `value_changed`），
	#   不绕过控件直接调 `replay.gd`。理由：交互层特有的坏法只有两类 ——
	#   ① 控件没接回调/信号（点了没反应）② 回调接错函数（点 A 干了 B 的事），
	#   这两类在"直接调 replay.gd"的判据下**全都测不到**（铁律 7）。
	replay_exit()
	var ui_entered: bool = replay_enter(back)
	if not ui_entered:
		ok = false
		print("[browsetest] ⑪ 交互层判据无法进行：进复盘的入口就失败了")

	# ---- ⑪a 工具条齐备 + 布局在视口内（当前档：期望值按谓词取）----
	# ★ 有效分母 = 按钮数：空数组上"每个按钮都在视口内"是**空集合上的判据**（恒真）。
	var jr_land: Array = judge_replay_hud_layout(-1.0)
	var hud_visible: bool = _rp_layer != null and _rp_layer.visible
	var game_hud_hidden: bool = _hud_layer != null and not _hud_layer.visible
	# ★ 末尾那条"高度 > 0"是**横屏档的补丁**：横屏的按钮高度下限本身是 0
	#   （`hud_btn_min_h_landscape`），所以 ⑪a 的高度判据在这一档恒真 ——
	#   真正量触摸目标的是 ⑪b（竖屏档，期望值 76）。这里只防"全被夹成 0 高"
	#   这种连出屏判据都照不出来的退化（0 高按钮的矩形照样在视口内）。
	var c11a: bool = ui_entered and hud_visible and game_hud_hidden \
		and _rp_buttons.size() == 6 and bool(jr_land[0]) \
		and _rp_buttons[0].size.y > 0.0
	print("[browsetest] ⑪a 复盘工具条：%d 个按钮·可见=%s·对局 HUD 让位=%s｜%s → %s" % [
		_rp_buttons.size(), str(hud_visible), str(game_hud_hidden), str(jr_land[1]),
		"✓" if c11a else "✗"])
	if not c11a:
		ok = false

	# ---- ⑪b 竖屏档：翻谓词 → 重摆 → 按钮必须够高 ----
	# ★ 期望值传**字面量** `HUD_TOUCH_MIN_PORTRAIT`，不传 `hud_button_min_height()`：
	#   要翻的正是那个谓词，一翻期望值就跟着变 0 ⇒ 高度判据被自己关掉（恒真）。
	var po_save: int = GameConfig.portrait_override
	GameConfig.portrait_override = 1
	_refit_replay_hud()
	var jr_port: Array = judge_replay_hud_layout(GameConfig.HUD_TOUCH_MIN_PORTRAIT)
	GameConfig.portrait_override = po_save
	_refit_replay_hud()
	# ★ 光断言"≥ 下限"不够 —— 还要断言**下限本身 > 0**，否则两档都没在量东西
	var c11b: bool = bool(jr_port[0]) and GameConfig.HUD_TOUCH_MIN_PORTRAIT > 0.0
	print("[browsetest] ⑪b 竖屏档重摆：下限 %.0f ｜%s → %s" % [
		GameConfig.HUD_TOUCH_MIN_PORTRAIT, str(jr_port[1]), "✓" if c11b else "✗"])
	if not c11b:
		ok = false

	# ---- ⑫ 跳转键（走 `_rp_on_*` 真实回调，逐步比对原局快照）----
	_rp_jump(0)
	_rp_on_next()
	var b_next: bool = _replay.replay_ply == 1 and _replay_fingerprint() == snaps[0]
	_rp_on_last()
	var b_last: bool = _replay.replay_ply == np and _replay_fingerprint() == snaps[np - 1]
	_rp_on_prev()
	var b_prev: bool = _replay.replay_ply == np - 1 and _replay_fingerprint() == snaps[np - 2]
	_rp_on_first()
	var b_first: bool = _replay.replay_ply == 0
	# ★ 有效分母：手数必须 > 2（否则"上一手/末手"是同一步，四个布尔退化成两个）
	var c12: bool = b_next and b_last and b_prev and b_first and np > 2
	print("[browsetest] ⑫ 跳转键：下一手=%s 末手=%s 上一手=%s 首手=%s（手数 %d）→ %s" % [
		str(b_next), str(b_last), str(b_prev), str(b_first), np, "✓" if c12 else "✗"])
	if not c12:
		ok = false

	# ---- ⑬ 滑条 ↔ 游标**双向**同步 ----
	# ★ 两个方向都要量，且两次目标必须**不同**：只测单向的话"滑条只是被游标单向刷新"
	#   这种坏法照样绿（拖动滑条不动盘面）。
	_rp_jump(0)
	var s1: int = mini(7, np)
	_rp_slider.value = float(s1)                  # 走 `value_changed` 真实路径
	var ply_after_drag: int = _replay.replay_ply
	var drag_fp_ok: bool = _replay_fingerprint() == snaps[maxi(s1 - 1, 0)]
	var c13a: bool = ply_after_drag == s1 and drag_fp_ok
	var s2: int = mini(23, np)
	_rp_goto(s2)
	var slider_after: int = int(round(_rp_slider.value))
	var c13b: bool = slider_after == s2 and _replay.replay_ply == s2
	var c13: bool = c13a and c13b and s1 > 0 and s2 != s1
	print("[browsetest] ⑬ 滑条双向：拖到 %d → 游标 %d/应 %d·盘面对 %s｜跳到 %d → 滑条 %d/应 %d → %s" % [
		s1, ply_after_drag, s1, str(drag_fp_ok), s2, slider_after, s2,
		"✓" if c13 else "✗"])
	if not c13:
		ok = false

	# ---- ⑭ 点盘跳转 ----
	# ★ 核心牙齿 = **倒扫语义**：一颗格可以被下、被提、再下，倒扫才给出"它**现在**这颗子
	#   被放下的那一手"。用手工谱测（期望值是字面量 3/2/0）——真实谱里几乎找不到同一格
	#   落两次的样本，拿真实谱测这条会让判据在**空集**上跑（恒真）。
	#   ⚠️ 手工谱会替换 `replay_record["moves"]` ⇒ 测完**必须复原**（判据会污染现场）。
	var moves_save: Array = _replay.replay_record["moves"]
	_replay.replay_record["moves"] = [
		{"ply": 1, "tile": 5, "color": "B", "captures": 0, "ko": -1},
		{"ply": 2, "tile": 9, "color": "W", "captures": 0, "ko": -1},
		{"ply": 3, "tile": 5, "color": "B", "captures": 0, "ko": -1},
	]
	var q_dup: int = _rp_ply_of_tile(5)
	var q_one: int = _rp_ply_of_tile(9)
	var q_none: int = _rp_ply_of_tile(77)
	_replay.replay_record["moves"] = moves_save
	# 真实谱：挑一个**只落过一次**的格子 ⇒ 点它必须落到那一手，且盘面与快照逐键相同
	var counts := {}
	for i in (back["moves"] as Array).size():
		var ti: int = int((back["moves"] as Array)[i]["tile"])
		if ti >= 0:
			counts[ti] = int(counts.get(ti, 0)) + 1
	var target_tile: int = -1
	var target_ply: int = 0
	for i in (back["moves"] as Array).size():
		var ti2: int = int((back["moves"] as Array)[i]["tile"])
		# ★ `i >= 1`（手数 > 1）是**有效分母**：第 1 手必然是"只落一次"的格子，
		#   若允许选到它，"点盘跳到第 k 手"这条就退化成"跳到第 1 手"——
		#   而第 1 手与"什么都不做"在盘面上几乎没差别（首版就是这么红的：挑到了 t0）。
		if ti2 >= 0 and int(counts.get(ti2, 0)) == 1 and i >= 1:
			target_tile = ti2
			target_ply = i + 1
			break
	var real_hit: int = _rp_ply_of_tile(target_tile)
	_rp_jump(real_hit)
	var real_fp_ok: bool = real_hit > 0 and _replay_fingerprint() == snaps[real_hit - 1]
	var ply_before_outside: int = _replay.replay_ply
	var q_outside: int = _rp_ply_of_tile(-1)          # 盘外：没有这颗格
	var outside_safe: bool = q_outside == 0 and _replay.replay_ply == ply_before_outside
	var c14: bool = q_dup == 3 and q_one == 2 and q_none == 0 \
		and target_tile >= 0 and real_hit == target_ply and target_ply > 1 \
		and real_fp_ok and outside_safe
	print("[browsetest] ⑭ 点盘跳转：重复格→%d(应3) 单次格→%d(应2) 谱外格→%d(应0)｜真实格 t%d→第 %d 手(应 %d·盘面对=%s)｜盘外不动=%s → %s" % [
		q_dup, q_one, q_none, target_tile, real_hit, target_ply, str(real_fp_ok),
		str(outside_safe), "✓" if c14 else "✗"])
	if not c14:
		ok = false

	# ---- ⑮a 连续播放（**走 `_process` 真实驱动**）到末手自停 ----
	# ★ 为什么必须走 `_process` 而不是直接调 `replay_tick()`：后者已在 ⑥ 验过。这里要量的
	#   是**引擎回调里那段推进到底跑没跑** —— 把复盘推进写在 `_process` 的"没有动画就
	#   return"**之后**是一个极容易犯、且完全静默的错（复盘态下动画表恒为空），
	#   只有走 `_process` 才照得出来。
	_rp_jump(0)
	_rp_on_play()
	var play_txt_on: String = _rp_play_btn.text
	var frames_used: int = 0
	for _f in 400:
		_process(0.05)
		frames_used += 1
		if _replay.replay_ply >= np and not _replay.replay_playing:
			break
	var play_txt_off: String = _rp_play_btn.text
	var slider_tail: int = int(round(_rp_slider.value))
	# ★ 有效分母：`frames_used > 1`（真的跑了不止一帧）—— 否则"到末手"可以是空转
	var c15a: bool = _replay.replay_ply == np and not _replay.replay_playing \
		and play_txt_on == "暂停" and play_txt_off == "播放" \
		and slider_tail == np and frames_used > 1
	print("[browsetest] ⑮a 播放到底：%d 帧 → 游标 %d/%d·按钮「%s」→「%s」·滑条 %d → %s" % [
		frames_used, _replay.replay_ply, np, play_txt_on, play_txt_off, slider_tail,
		"✓" if c15a else "✗"])
	if not c15a:
		ok = false

	# ---- ⑮b 播放中暂停：游标必须**真的停住** ----
	_rp_jump(0)
	_rp_on_play()
	for _f in 3:
		_process(0.05)
	var ply_mid: int = _replay.replay_ply
	_rp_on_play()                     # 再按一次 = 暂停
	var paused_ok: bool = not _replay.replay_playing and _rp_play_btn.text == "播放"
	for _f in 10:
		_process(0.05)
	var frozen: bool = _replay.replay_ply == ply_mid
	# ★ 播放中按「下一手」也必须停播：手动步进 = 明确的"我要自己走"（同 `_rp_step` 的注）。
	#   这条单列是因为"暂停键有效"与"单步会停播"是**两处**代码 —— 只测前者时，
	#   `_rp_step()` 漏掉 `replay_playing = false` 照样全绿（手动挪一格后播放又把它推走）。
	_rp_jump(0)
	_rp_on_play()
	_rp_on_next()
	var step_stops: bool = not _replay.replay_playing and _replay.replay_ply == 1
	# ★ 有效分母：`ply_mid > 0`（真的推进过，否则"没动过也没动"= 恒真）
	var c15b: bool = ply_mid > 0 and paused_ok and frozen and step_stops
	print("[browsetest] ⑮b 播放中暂停：推 3 帧到第 %d 手 → 暂停（playing=%s·按钮「%s」）→ 再推 10 帧游标 %d（应仍 %d）｜单步停播=%s → %s" % [
		ply_mid, str(_replay.replay_playing), _rp_play_btn.text, _replay.replay_ply, ply_mid,
		str(step_stops), "✓" if c15b else "✗"])
	if not c15b:
		ok = false

	# ---- ⑯ 键盘快捷键（走 `_input` 真实回调）----
	# ★ 顺带把「复盘键位必须排在 R / ESC 之前」钉住：`R` 在复盘里**不得**重开
	#   （重开会清盘，而 `_replay` 还在 ⇒ 盘面与游标脱节，且不报错）。
	_rp_jump(0)
	var ev_right := InputEventKey.new()
	ev_right.keycode = KEY_RIGHT
	ev_right.pressed = true
	_input(ev_right)
	var k_right: int = _replay.replay_ply
	var ev_end := InputEventKey.new()
	ev_end.keycode = KEY_END
	ev_end.pressed = true
	_input(ev_end)
	var k_end: int = _replay.replay_ply
	var ev_home := InputEventKey.new()
	ev_home.keycode = KEY_HOME
	ev_home.pressed = true
	_input(ev_home)
	var k_home: int = _replay.replay_ply
	var ev_space := InputEventKey.new()
	ev_space.keycode = KEY_SPACE
	ev_space.pressed = true
	_input(ev_space)
	var k_space_on: bool = _replay.replay_playing
	_input(ev_space)
	var k_space_off: bool = _replay.replay_playing
	# ★★ R 键这一条**必须在盘上有子时测**：首版跑在"刚 Home 回第 0 手"之后，
	#   那时盘面本来就是空的 ⇒ "按 R 前后棋子数相同"在**空盘上恒真**，
	#   负控刀 BR21（把 R 的处理插到复盘分支之前）照样全绿（实测）。
	#   —— 与 ⑭ 挑到第 1 手、⑮b 的 `ply_mid > 0` 是同一族：**退化样本上的判据 = 没测**。
	#   改到中盘测，并把 `stones_before > 0` 单列进有效分母。
	_rp_jump(np / 2)
	var stones_before: int = _rp_stone_count()
	var ev_r := InputEventKey.new()
	ev_r.keycode = KEY_R
	ev_r.pressed = true
	_input(ev_r)
	var r_safe: bool = _rp_stone_count() == stones_before and _replay != null \
		and stones_before > 0
	var c16: bool = k_right == 1 and k_end == np and k_home == 0 \
		and k_space_on and not k_space_off and r_safe and np > 1
	print("[browsetest] ⑯ 键盘：→=%d(应1) End=%d(应%d) Home=%d(应0) 空格 %s→%s｜R键清盘=%s（盘中 %d 子）→ %s" % [
		k_right, k_end, np, k_home, str(k_space_on), str(k_space_off),
		str(not r_safe), stones_before, "✓" if c16 else "✗"])
	if not c16:
		ok = false

	# ---- ⑰ 退出复盘：UI 复原 + **立刻**能正常落子 ----
	_rp_on_exit()
	var rp_hidden: bool = _rp_layer != null and not _rp_layer.visible
	var g_hud_back: bool = _hud_layer != null and _hud_layer.visible
	var cleared: bool = _replay == null and _rp_play_btn.text == "播放" \
		and _rp_slider.value == 0.0 and not _rp_slider.editable and _rp_info.text == ""
	# ★ 量**伤害最大的那一刻**：退出后立刻落子（不是"过几帧再落"）
	reset_game(true)
	_quiet_place = false
	var t17: int = _first_playable()
	var can_place_now: bool = t17 >= 0 and place_stone(t17, false)
	var c17: bool = rp_hidden and g_hud_back and cleared and can_place_now and _hist.size() == 1
	print("[browsetest] ⑰ 退出复原：工具条隐=%s 对局 HUD 回=%s 清空=%s 立刻可落子=%s → %s" % [
		str(rp_hidden), str(g_hud_back), str(cleared), str(can_place_now),
		"✓" if c17 else "✗"])
	if not c17:
		ok = false
	reset_game(true)
	_quiet_place = false

	# ---- 元判据（铁律 12 ②）----
	if not bad_shape.is_empty():
		for b in bad_shape:
			print("[browsetest] ✗ 细节·%s" % b)
		ok = false

	# ---- 复原现场 ----
	GameConfig.board_type = bt_save
	GameConfig.board_size = bs_save
	komi = km_save
	game_mode = mode_save
	replay_anim_enabled = anim_save
	generate_board()
	reset_game(true)
	_quiet_place = false

	print("[browsetest] 结论：%s" % ("通过 ✓" if ok else "失败 ✗ 复盘器跳转/播放/复原不对"))
	get_tree().quit()

## 自检主体
func _undo_test() -> void:
	reset_game(true)
	_quiet_place = false
	var ok: bool = true
	print("[undotest] === 悔棋自检（板 %d 格）===" % tiles.size())

	# ---- ① 落子/停手都入栈，探测性落子不入栈 ----
	reset_game(true)
	_hist.clear()
	place_stone(_first_playable(), true)
	var n1: int = _hist.size()
	_apply_pass()
	var n2: int = _hist.size()
	_quiet_place = true
	var before_q: int = _hist.size()
	for i in 5:
		var tq: int = _first_playable()
		if tq < 0:
			break
		place_stone(tq, false)
	_quiet_place = false
	var grew: int = _hist.size() - before_q
	var c1: bool = n1 == 1 and n2 == 2 and grew == 0
	print("[undotest] ① 入栈：落子后=%d(期望1) 停手后=%d(期望2) 探测落子入栈=%d(期望0) → %s"
		% [n1, n2, grew, "✓" if c1 else "✗"])
	if not c1:
		ok = false

	# ---- ② 语义：退到「我上一次落子之前」 ----
	reset_game(true)
	_hist.clear()
	_undo_random_moves(6, 20261004)
	var turn_before: int = current_player
	var depth_before: int = _hist.size()
	# ★ 快照必须在**悔棋之前**取：`undo_to_my_turn()` 会把栈弹短，之后再按
	#   `depth_before` 去索引就是越界（`Out of bounds get index '5'` ——
	#   而 `SCRIPT ERROR` 会**中止整个 `_undo_test`**，后面的判据一条都跑不到，
	#   看起来像"卡住"，实则是崩在半路）。
	var snap2: Array = _hist.duplicate(true)
	var undone: int = undo_to_my_turn()
	var me2: int = turn_before
	var expect_undone: int = 0
	var k: int = snap2.size() - 1
	while k >= 0 and int(snap2[k]["color"]) != me2:
		expect_undone += 1
		k -= 1
	if k >= 0:
		expect_undone += 1
	var c2: bool = undone == expect_undone and undone > 0 and current_player == me2
	print("[undotest] ② 语义：栈深%d current_player=%d → 撤%d手(期望%d) 回到%s行棋 → %s"
		% [depth_before, turn_before, undone, expect_undone,
			"黑" if current_player == Stone.BLACK else "白", "✓" if c2 else "✗"])
	if not c2:
		ok = false

	# ---- ③ ★回滚等价性（判据重心）：逐步存档 → 逐手弹栈 → 每步与存档对账 ----
	# ★★ 为什么不用"正走 N 手 → 悔 → 重走同一批点 → 比指纹"（第一版那么写的，已废）：
	#   重建过程会引入**与回滚无关**的差异，两处都实测踩到：
	#     ① `seq` 里的 `-1` 是停一手，重放时 `_apply_pass` 再吃一次 passes 配额，
	#        而落子那步把 passes 清零 ⇒ 两遍的 passes 落在不同相位；
	#     ② `_undo_random_moves` 有 `if not place_stone(t): _apply_pass()` 兜底，
	#        `seq` 记的是"尝试点"；重建时该点可能因盘面微差被拒 ⇒ 少一颗子
	#        （实测 tile 71：第一遍是白子、重建后是空）。
	#   这类差异会让判据指向**错误的病灶** —— 铁律：为了让判据变绿去改被测物，
	#   就会把本来正确的东西改坏（"判据口径错"比"判据不够严"贵得多）。
	#
	# ⇒ 改成**不重建**的严格表述：「弹掉第 k 手之后，盘面必须与走完第 k-1 手时逐键相同」。
	#   做法：正着走 12 手，**每走一手存一次指纹**；然后逐手弹栈，每弹一手
	#   就与对应存档对账。比较的是**回滚原语本身**，零重建误差。
	# ★ 为什么必须连 `ko/passes/_last_move/提子计数` 一起比：那正是**盘面推不出**的四个状态
	#   （只能靠 `_hist` 存档还原）。只比 `board` 的话，回滚把它们全丢了也会判"通过"。
	reset_game(true)
	_hist.clear()
	var marks: Array[String] = []
	marks.append(_undo_fingerprint())      # marks[0] = 开局
	for i in 12:
		var t: int = -1
		var guard_t: int = 0
		while guard_t < 400:
			var cand: int = _first_playable()
			if cand >= 0:
				t = cand
				break
			guard_t += 1
		if t >= 0:
			place_stone(t, true)
		else:
			_apply_pass()
		marks.append(_undo_fingerprint())    # marks[k] = 走完 k 手后的指纹
	var c3: bool = true
	var guard: int = 0
	# ★ marks[k] = "走完第 k 手后"的指纹，`marks[0]` 是开局。
	#   弹掉栈顶那一手 ⇒ 状态应退到"走完第 (栈深-1) 手"，也就是 `marks[栈深]`（不是 `栈深-1`！
	#   marks 下标是**手数**，与当前栈深相等 —— 栈深 12 时 `marks[12]` 才是走完 12 手的存档）。
	#   ⇒ 弹完先比 `marks[栈深]`，**比过再**把存档弹掉（否则下轮就错位一格）。
	while not _hist.is_empty() and guard < 40:
		guard += 1
		_pop_history_entry(_hist[_hist.size() - 1])
		var got: String = _undo_fingerprint()
		var want: String = marks[_hist.size()]
		if got != want:
			c3 = false
			print("[undotest] ③ 第%d次弹栈不一致（栈深%d）｜期望尾部 %s｜实得尾部 %s"
				% [guard, _hist.size(),
					want.substr(want.find("|ko=")),
					got.substr(got.find("|ko="))])
			break
	# 不需要同步弹 `marks`：下标是按 `_hist.size()` 取的（栈深 n ⇒ marks[n]），
	#   栈自己会缩，marks 保持"走完 k 手"的原始存档即可。
	print("[undotest] ③ 回滚等价性：12手逐步存档 → 逐手弹栈 %d 次 → %s"
		% [guard, "✓ 每步逐键相同（回滚无损）" if c3 else "✗ 有一步对不上"])
	if not c3:
		ok = false

	# ---- ④ 提子回滚 ----
	reset_game(true)
	_hist.clear()
	var c4: bool = _undo_capture_probe()
	print("[undotest] ④ 提子回滚：%s" % ("✓" if c4 else "✗"))
	if not c4:
		ok = false

	# ---- ⑤ 劫点回滚 ----
	reset_game(true)
	_hist.clear()
	var c5: bool = _undo_ko_probe()
	print("[undotest] ⑤ 劫点回滚：%s" % ("✓" if c5 else "✗"))
	if not c5:
		ok = false

	# ---- ⑥ 联机：冻结 + 额度 ----
	var m_save: int = game_mode
	var nc_save: int = _net_color
	var conn_save: bool = _net_connected
	var ph_save: String = _net_phase
	game_mode = ONLINE
	_net_connected = true
	_net_phase = "playing"
	_net_color = Stone.BLACK
	reset_game(true)
	_hist.clear()
	_undo_random_moves(4, 4242)
	_undo_freeze = false
	_undo_pending_from = -1
	var can_before: bool = _can_local_play()
	_undo_freeze = true
	var can_after: bool = _can_local_play()
	_undo_freeze = false
	_undo_used[Stone.BLACK] = 3
	var c6b: bool = not can_undo()
	_undo_used[Stone.BLACK] = 1
	var c6c: bool = can_undo()
	undo_to_my_turn()
	var c6d: bool = undo_used(Stone.BLACK) == 1
	var c6: bool = can_before and not can_after and c6b and c6c and c6d
	print("[undotest] ⑥ 联机：冻结前可动=%s 冻结后=%s(期望false) 额度3次后可悔=%s(期望false) 1次后=%s(期望true) 悔后额度=%d(期望仍1) → %s"
		% [_yn(can_before), _yn(can_after), _yn(not c6b), _yn(c6c),
			undo_used(Stone.BLACK), "✓" if c6 else "✗"])
	if not c6:
		ok = false
	game_mode = m_save
	_net_color = nc_save
	_net_connected = conn_save
	_net_phase = ph_save
	_undo_freeze = false
	_undo_pending_from = -1
	_undo_used.clear()

	# ---- ⑦ 终局后悔棋能收回 game_over ----
	reset_game(true)
	_hist.clear()
	_undo_random_moves(8, 99)
	game_over = true
	var u7: int = undo_to_my_turn()
	var c7: bool = u7 > 0 and not game_over
	print("[undotest] ⑦ 终局后悔棋：撤%d手 game_over 现=%s → %s"
		% [u7, _yn(game_over), "✓" if c7 else "✗"])
	if not c7:
		ok = false

	# ---- ⑧ 空栈：返回 0 且不动盘面 ----
	reset_game(true)
	_hist.clear()
	var fp0: String = _undo_fingerprint()
	var u0: int = undo_to_my_turn()
	var c8: bool = u0 == 0 and fp0 == _undo_fingerprint()
	print("[undotest] ⑧ 空栈：撤%d手(期望0) 盘面未动=%s → %s"
		% [u0, _yn(fp0 == _undo_fingerprint()), "✓" if c8 else "✗"])
	if not c8:
		ok = false

	# ---- ⑨ 联机两端对称：**两端都以请求方为"我"** 退 → 必须同一局面 ----
	#   ★ 这是本轮实测抓到的真 bug 的判据：原先两端各用各的 `_net_color` 当"我"，
	#     实测黑端 turn=1 / 白端 turn=2 ⇒ 两盘棋从此不是同一盘（联机静默分叉）。
	#
	# ★★★ 2026-10-02 **判据自身返工**（阴性对照 U5 当场把首版打成恒真式）：
	#   首版是「`undo_to_my_turn_as(BLACK)` 走一遍 → 重放 → 再走一遍 → 比两个指纹」。
	#   那测的是**可重现性**（同一函数、同一参数、同一盘面 ⇒ 本来就该相等），
	#   **根本没经过出错的那个函数**（`_on_undo_res_received`）⇒
	#   把那行 `undo_to_my_turn_as(target_color)` 换成 `undo_to_my_turn()`（= 各用各的
	#   `_net_color`）之后，两遍都改用 `_net_color`，两遍**照样相等** ⇒ 判据恒绿，
	#   而联机分叉这个 P0 依然存在（negctl U5 报「✓ 仍绿（没牙齿！）」）。
	#   ⇒ 教训：**判据必须走真实协议路径**（`_on_undo_res_received`），
	#     并且**让 `_net_color` 在两次调用里取不同值** —— 错法正是"读 `_net_color`"，
	#     变量不变化就照不出差别（同族：坐标系混用导致恒真式）。
	#   ⑨ 正向：两端 `_net_color` 不同，但都收到"同意、请求方=黑" ⇒ 必须逐键相同。
	#   ⑩ 反向：各用自己执色**必然分叉** —— 守住"为什么必须由 target_color 决定落点"。
	var seq_c: Array[int] = _undo_random_moves(10, 31337)
	# 第一遍：**白端**收到回执（`_net_color = 白`），回执说请求方是黑
	var m9a: int = game_mode
	var nc9a: int = _net_color
	game_mode = ONLINE
	_net_color = Stone.WHITE
	_on_undo_res_received(true, Stone.BLACK)
	var fp_black: String = _undo_fingerprint()
	# 第二遍：**黑端**收到同一份回执（`_net_color = 黑`）—— 必须与上面完全相同
	reset_game(true)
	_hist.clear()
	for t in seq_c:
		if t < 0:
			_apply_pass()
		else:
			place_stone(t, true)
	game_mode = ONLINE
	_net_color = Stone.BLACK
	_on_undo_res_received(true, Stone.BLACK)
	var fp_req_black: String = _undo_fingerprint()
	game_mode = m9a
	_net_color = nc9a
	# 第三遍（反向对照）：白端收到"请求方=白"的回执 ⇒ 必须与上面**不同**
	reset_game(true)
	_hist.clear()
	for t in seq_c:
		if t < 0:
			_apply_pass()
		else:
			place_stone(t, true)
	game_mode = ONLINE
	_net_color = Stone.BLACK
	_on_undo_res_received(true, Stone.WHITE)
	var fp_white: String = _undo_fingerprint()
	game_mode = m9a
	_net_color = nc9a
	_undo_used.clear()
	_undo_pending_from = -1
	_undo_freeze = false
	var c9: bool = fp_black == fp_req_black
	print("[undotest] ⑨ 两端同听请求方：白端/黑端各退一次，%d / %d 字符 → %s"
		% [fp_black.length(), fp_req_black.length(),
			"✓ 同一局面" if c9 else "✗ 分叉"])
	if not c9:
		ok = false
		print("[undotest] ⑨ 尾部·白端退完：%s" % fp_black.substr(fp_black.find("|ko=")))
		print("[undotest] ⑨ 尾部·黑端退完：%s" % fp_req_black.substr(fp_req_black.find("|ko=")))
	var c10: bool = fp_white != fp_req_black
	print("[undotest] ⑩ 反向对照：各用自己执色 → %s（期望与⑨不同）"
		% ("✓ 确实分叉" if c10 else "✗ 竟然相同 ⇒ 分叉模式测不到"))
	if not c10:
		ok = false
		print("[undotest] ⑩ 尾部·白为我的退点：%s" % fp_white.substr(fp_white.find("|ko=")))

	# ---- ⑪ 悔棋必须让"正在思考的 AI"那一代作废（`_ai_gen += 1`）----
	#   ★ 为什么单独一条（阴性对照 U6 当场把首版打成"没牙齿"）：`_ai_gen` 是**协程世代号**，
	#   它既不在 `_undo_fingerprint()` 里、⑥ 也只测冻结/额度 ⇒ 删掉 `+= 1` 全绿。
	#   而坏处极重：AI 思考协程醒来只查 `gen != _ai_gen`，不递增的话**它算好的那手会被
	#   落在已经撤销的盘面上** —— 症状是"悔完棋莫名其妙多出一颗子"，几十手后才显形。
	#   ⇒ 直接观测这个量：悔棋前后 `_ai_gen` 必须**严格变大**。
	reset_game(true)
	_hist.clear()
	_undo_random_moves(4, 606)
	var gen_before: int = _ai_gen
	undo_to_my_turn()
	var gen_after: int = _ai_gen
	var c11: bool = gen_after > gen_before
	print("[undotest] ⑪ AI 世代作废：_ai_gen %d → %d（期望严格变大）→ %s"
		% [gen_before, gen_after, "✓" if c11 else "✗ 正在思考的 AI 会把旧着落进已撤销的盘面"])
	if not c11:
		ok = false

	print("[undotest] 结论：%s" % ("通过 ✓" if ok else "失败 ✗ 悔棋判据不通过"))
	get_tree().quit()


## 供 ⑨ 用：显式指定"我"的颜色来退（联机两端执色不同，但同一串栈）。
## ★ 不走 `game_mode`/`_net_color` 改写 —— 那两处是联机真源，自检不该去污染。
func undo_to_my_turn_as(me: int) -> int:
	if _hist.is_empty():
		return 0
	var saved_mode: int = game_mode
	var saved_col: int = _net_color
	game_mode = ONLINE
	_net_color = me
	var n: int = undo_to_my_turn()
	game_mode = saved_mode
	_net_color = saved_col
	return n

## ④ 提子回滚探针：在随机局里找一手**提了子**的，悔棋后逐项对账。
func _undo_capture_probe() -> bool:
	for seed_i in range(14):
		reset_game(true)
		_hist.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5150 + seed_i * 131
		var found: Dictionary = {}
		var found_idx: int = -1
		# ★ 检查顺序：先落一手、再看栈顶有没有提子。
		#   反过来写（先判 `_hist.is_empty()` 再落子）的话，栈刚 clear() 过、
		#   第 0 轮必然 break ⇒ 循环体一次都不执行 ⇒ 探针报"没走到提子"是**假的**，
		#   判据看起来在测、实际什么都没测（"看不见 ≠ 没测"的一族）。
		for step in 400:
			if step > 0:
				var top: Dictionary = _hist[_hist.size() - 1] if not _hist.is_empty() else {}
				if not top.is_empty():
					var dead: Array = top["captured"]
					if dead.size() > 0:
						found = top
						found_idx = _hist.size() - 1
						break
			var t: int = rng.randi_range(0, tiles.size() - 1)
			if can_place_at(t):
				place_stone(t, false)
		if found.is_empty():
			continue
		# ★ 找到的那一刻就把两侧要用的东西全抓好（纪律，见下面诊断注释）：
		#   `found` 是 Dictionary **引用**，实测出现过「`found` 指的那一手 ≠ 弹的那一手」
		#   （found.tile=70 / popped.tile=42），症状极像"回滚用错计数桶"的实现 bug。
		#   根因是引用在"抓到"与"用"之间不是稳定的同一对象 ⇒ 别赌，抓当下。
		var tile: int = int(found["tile"])
		var mover: int = int(found["color"])
		var opp: int = Stone.WHITE if mover == Stone.BLACK else Stone.BLACK
		var dead2: Array = found["captured"]
		var bp_before: int = black_prisoners
		var wp_before: int = white_prisoners
		var empty_before: int = _empty_tiles()
		var fpid: int = found_idx
		var popped: Dictionary = _hist[found_idx]
		# 同指自检：若这条红，说明"抓到的那手"与"要撤的那手"不是同一手（本轮踩过一次）
		if int(popped["tile"]) != tile or int(popped["color"]) != mover:
			print("[undotest] ④ 同指核对失败：found(tile=%d,color=%d) vs popped(tile=%d,color=%d)"
				% [tile, mover, int(popped["tile"]), int(popped["color"])])
			return false
		_pop_history_entry(popped)
		# 三项对账：① 落点空了 ② 被提子**回到盘面**且是对方颜色 ③ 计数减回
		var a_ok: bool = board[tile] == Stone.EMPTY
		var b_ok: bool = true
		for vid in dead2:
			if board[vid] != opp:
				b_ok = false
		var c_ok: bool = true
		if mover == Stone.BLACK:
			c_ok = black_prisoners == bp_before - dead2.size()
		else:
			c_ok = white_prisoners == wp_before - dead2.size()
		var d_ok: bool = _empty_tiles() == empty_before - 1 + dead2.size()
		var all_ok: bool = a_ok and b_ok and c_ok and d_ok
		print("[undotest] ④ 细节：撤第%d手(提%d子, 落子方=%s) → 落点已空=%s 被提子归位且同色=%s 计数减回=%s 空点数复原=%s"
			% [fpid, dead2.size(), "黑" if mover == Stone.BLACK else "白",
				_yn(a_ok), _yn(b_ok), _yn(c_ok), _yn(d_ok)])
		if not c_ok:
			# ★ 只打 ✓/✗ 看不出"差了几"（可能是 maxi 夹住、也可能是加减用错了计数桶 ——
			#   症状完全一样）。把三个数字一起打出来，差值本身才是判据线索。
			print("[undotest] ④ 计数诊断：mover=%s 提%d子 | 黑 %d→%d（期望%d）| 白 %d→%d"
				% ["黑" if mover == Stone.BLACK else "白", dead2.size(),
					bp_before, black_prisoners, bp_before - dead2.size(),
					wp_before, white_prisoners])
		return all_ok
	print("[undotest] ④ 细节：14 个种子都没走到『提子』这一步 —— 判据没测到东西")
	return false

## ⑤ 劫点回滚探针：找到一手 `ko_before` **非 -1** 的（也就是"落子之前盘上已经有劫"），
##   撤它之后 ko_point 必须回到那个**具体的非 -1 值**。
##
## ★★ 挑选条件为什么必须是 `ko_before != -1`（阴性对照 U4 当场把首版挑法打成恒真式）：
##   首版挑的是 `ko_before != ko_point`（"这一手改变了 ko_point"）—— 而实战里这种手
##   **绝大多数是"刚造出一个劫"**，即 `ko_before == -1`、`ko_point == 101`。
##   于是"正确还原成存档值(-1)"与"**硬编码** `ko_point = -1`"**完全等价** ⇒ 判据恒绿
##   （negctl U4 报"✓ 仍绿（没牙齿！）"）。
##   记忆点：**判据挑的样本，必须让"对"与"错"的输出不同**；挑得不对就是恒真式，
##   与"没写判据"同族（空集合/平凡集合上的判据 = 没测）。
func _undo_ko_probe() -> bool:
	for seed_i in range(20):
		reset_game(true)
		_hist.clear()
		var rng := RandomNumberGenerator.new()
		rng.seed = 9090 + seed_i * 17
		var ko_idx: int = -1
		# 同 ④：先落子再看栈顶，避免第 0 轮空栈 break（注释见 `_undo_capture_probe`）
		for step in 400:
			if step > 0 and not _hist.is_empty():
				# ★ 判据的样本选择（见函数头）：要 `ko_before` 非 -1 那种手。
				if int(_hist[_hist.size() - 1]["ko_before"]) != -1:
					ko_idx = _hist.size() - 1
					break
			var t: int = rng.randi_range(0, tiles.size() - 1)
			if can_place_at(t):
				place_stone(t, false)
		if ko_idx < 0:
			continue
		# 重走回到那一手，单独弹它，核对 ko_point
		reset_game(true)
		_hist.clear()
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 9090 + seed_i * 17
		var ko_idx2: int = -1
		for step in 400:
			if step > 0 and not _hist.is_empty():
				# ★ 与第一遍**同一个**挑选条件（换条件就找不到同一手 ⇒ 对不上账）
				if int(_hist[_hist.size() - 1]["ko_before"]) != -1:
					ko_idx2 = _hist.size() - 1
					break
			var t2: int = rng2.randi_range(0, tiles.size() - 1)
			if can_place_at(t2):
				place_stone(t2, false)
		if ko_idx2 < 0:
			continue
		var before_ko: int = ko_point
		var expect: int = int(_hist[_hist.size() - 1]["ko_before"])
		_pop_history_entry(_hist[_hist.size() - 1])
		var after_ko: int = ko_point
		var okk: bool = after_ko == expect
		print("[undotest] ⑤ 细节：撤那一手 ko %d → %d（存档 %d）→ %s"
			% [before_ko, after_ko, expect, "✓" if okk else "✗"])
		return okk
	print("[undotest] ⑤ 细节：20 个种子都没造出劫 —— 判据没测到东西")
	return false

## 找一个合法落点（没有就返回 -1）
func _first_playable() -> int:
	for i in tiles.size():
		if can_place_at(i):
			return i
	return -1

## 自检（--aiterr）：终局评估质量探针 —— 诊断大盘棋力问题的核心工具。
##
## 背景：19×19 有 361 格，而 `_effective_playout_cap()` 返回 `min(n, 160)`，
## rollout 只下到 **44% 填充率**就被截断。此时大片空区边界黑白都有子，
## 传统「完全被单色围住才计分」一律判中立 → **面积分退化成纯子数差**，
## AI 完全学不到「围空」，只会往盘上堆子。彭罗斯 120 格能下满，所以小盘看不出这个病。
##
## 本探针把退化直接量出来：同一局面分别「下到截断上限」与「下满」，
## 比较两处算出的分差。判据是**截断处评估与终局真值的绝对误差**
## —— 评估若可靠，中盘就该能看出谁领先。
func _ai_territory_probe() -> void:
	ai_engine.setup(adjacency, AI_COLOR)
	var cap: int = ai_engine._effective_playout_cap()
	var tn: int = tiles.size()
	print("[aiterr] 棋盘=%s 格数=%d | rollout 上限=%d → 填充率上限=%.0f%%" % [
		_board_size_name(GameConfig.board_size), tn, cap,
		100.0 * float(cap) / float(maxi(tn, 1))])
	var cases := 8
	var last_err_old := 0.0
	var last_err_new := 0.0
	# 扫三档截断长度：引擎默认 / 1.5 倍 / 下满。看「多下一点」到底能挽回多少评估误差 ——
	# 这是判断「该改评估函数还是该加长 rollout」的直接依据
	var caps: Array[int] = [cap, int(cap * 1.5), tn]
	for c in caps:
		var ag_old := 0
		var ag_new := 0
		var err_old := 0.0
		var err_new := 0.0
		var fill := 0.0
		for s in cases:
			var mv0: int = 24 + s * 9
			var seed: int = 1234 + s * 77
			var a: Dictionary = ai_engine.probe_eval_quality(mv0, seed, c)
			var truth := float(a["score_true"])
			var so := float(a["score_old"])
			var sn := float(a["score_new"])
			var oko: bool = (so > 0) == (truth > 0)
			var okn: bool = (sn > 0) == (truth > 0)
			if oko:
				ag_old += 1
			if okn:
				ag_new += 1
			err_old += absf(so - truth)
			err_new += absf(sn - truth)
			fill += float(a["fill1"])
		print("[aiterr] 截断=%3d 填充=%.0f%% | 符号一致率 旧=%d/%d 新=%d/%d ｜ 平均绝对误差 旧=%.1f 新=%.1f" % [
			c, 100.0 * fill / float(cases),
			ag_old, cases, ag_new, cases,
			err_old / float(cases), err_new / float(cases)])
		last_err_old = err_old
		last_err_new = err_new
	# 断言：截断发生时（大盘）影响力评估必须更接近真值
	var ok := true
	if cap < tn:
		ok = last_err_new < last_err_old
	print("[aiterr] 结论：", "通过 ✓" if ok else "失败 ✗ 影响力评估未改善")
	get_tree().quit()


## 自检（--ailam）：给 AlphaGo 式 λ 混合定理论最优 λ。
##
## 为什么不用自对局比分来调 λ：19×19 一局 700 手、单局分差能到 ±700 目，
## 跑 20 局也读不出 3% 的机制差异（实测「自己打自己」方差水位就是 ±708 目）。
## 这里改测「估计量本身的均方误差」，几十次 rollout 就能定下 λ。
func _ai_lambda_probe() -> void:
	ai_engine.setup(adjacency, AI_COLOR)
	var cap: int = ai_engine._effective_playout_cap()
	var tn: int = tiles.size()
	var k: int = 24
	print("[ailam] 棋盘=%s 格数=%d | rollout 上限=%d | 每局面 %d 次 rollout" % [
		_board_size_name(GameConfig.board_size), tn, cap, k])
	var cases := 6
	var acc_old := 0.0
	var acc_new := 0.0
	var sum_sigma := 0.0
	for s in cases:
		var mv0: int = 40 + s * 22
		var seed: int = 4321 + s * 131
		var a: Dictionary = ai_engine.probe_lambda_opt(mv0, seed, cap, k)
		var lo: float = float(a["lambda_old"])
		var ln: float = float(a["lambda_new"])
		acc_old += lo
		acc_new += ln
		sum_sigma += float(a["sigma"])
		print("[ailam] 局面%-2d 填充=%.0f%% | σ=%.1f 偏差 旧=%.1f 新=%.1f | λ* 旧=%.2f 新=%.2f" % [
			s, 100.0 * float(a["fill"]), float(a["sigma"]),
			float(a["bias_old"]), float(a["bias_new"]), lo, ln])
	print("[ailam] 平均 σ=%.1f ｜ 推荐 λ（旧评估）=%.2f ｜ 推荐 λ（影响力评估）=%.2f" % [
		sum_sigma / float(cases), acc_old / float(cases), acc_new / float(cases)])
	get_tree().quit()


## 自检用：让两个引擎下一整局（黑/白各一方），返回 [黑总分, 白总分, 手数]
func _play_match(eng_black: AIEngine, eng_white: AIEngine) -> Array:
	game_mode = LOCAL            # 关掉人机自动接管，纯手动推演
	_quiet_place = true          # 一局几百手，落子日志会把自检汇总行淹没
	reset_game()
	var passes := 0
	var moves := 0
	var mmax: int = _match_max_moves if _match_max_moves > 0 else tiles.size() * 2
	while passes < 2 and moves < mmax:
		var turn_color: int = current_player
		var eng: AIEngine = eng_black if turn_color == Stone.BLACK else eng_white
		var mv: int = eng.choose_move(board, ko_point, turn_color)
		if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
			passes += 1
		elif place_stone(mv, false):
			moves += 1
			passes = 0
		else:
			passes += 1
		if current_player == turn_color:   # 停一手/被拒不会换行棋方 → 手动交换
			current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
	var sc: Dictionary = _compute_scores()
	# 健全性守卫：total = 盘上子 + 领空 + 提子数，其中（子+领空）≤ 格数、（提子数）≤ 落子手数，
	# 所以总分不可能超过「格数 + 手数 + 贴目」。超了说明提子计数被重复累加过
	var tot_b: int = int(sc.get("total_black", 0))
	var tot_w: int = int(sc.get("total_white", 0))
	var ceiling: int = tiles.size() + moves + int(komi) + 1
	if tot_b + tot_w > ceiling:
		push_error("[play_match] 计分异常：黑 %d + 白 %d > 上限 %d（提子计数可能被重复累加）" % [
			tot_b, tot_w, ceiling])
		print("[play_match] ⚠ 计分异常：黑 %d + 白 %d > 上限 %d" % [tot_b, tot_w, ceiling])
	return [tot_b, tot_w, moves]


## 造一个「旧行为」引擎：单线程、根全宽、关掉本次新增的全部死活机制、树退回浅层
func _make_legacy_engine(color: int, budget: int) -> AIEngine:
	var e := AIEngine.new()
	e.setup(adjacency, color)
	e.time_budget_ms = budget
	e.threads = 1
	e.root_width = 9999
	e.dead_penalty = false
	e.p_eye = 0.0
	e.w_weak_each = 0.0
	e.w_eye_make = 0.0
	e.widen_k = 9.0
	e.playout_cap_factor = 1.0
	e.full_scan_every = 10
	e.max_playout_moves = 220
	# KataGo 借鉴三项（2026-09-15 引入）对 legacy 基线一并关闭：
	# legacy 的语义是「改动前的引擎行为」，新增机制必须逐项退出
	e.dynamic_center_enabled = false
	e.pick_lcb_stdevs = 0.0
	e.obvious_early_stop = false
	return e


## 造一个引擎。spec 支持的键：
##   legacy=true   旧行为引擎（单线程/根全宽/关死活/浅树）
##   budget=N      思考预算 ms
##   threads=N     线程数（仅 legacy 以外生效）
##   life=false    关掉死活机制（死子惩罚 / rollout 补活 / 补强先验 / 做眼先验）
##   override={}   任意字段覆盖（键名 = AIEngine 属性名，用于单点消融）
func _make_spec_engine(spec: Dictionary, color: int) -> AIEngine:
	var b: int = int(spec.get("budget", 300))
	if bool(spec.get("legacy", false)):
		return _make_legacy_engine(color, b)
	var e := AIEngine.new()
	e.setup(adjacency, color)
	e.time_budget_ms = b
	if spec.has("threads"):
		e.threads = int(spec["threads"])
	if not bool(spec.get("life", true)):
		e.dead_penalty = false
		e.p_eye = 0.0
		e.w_weak_each = 0.0
		e.w_eye_make = 0.0
	for key in (spec.get("override", {}) as Dictionary).keys():
		e.set(key, spec["override"][key])
	return e


## 自检（--aiablate）：多局换色的消融/对照实验。
##
## 为什么必须多局换色：单局围棋方差极大（实测「旧行为打旧行为」能差出 90+ 目），
## 一局定胜负会把纯噪声读成机制效果。这里每组跑 rounds 轮，每轮黑先/白先各一局，
## 汇总总得分再比较；同时用「自己打自己」组标出方差水位。
##
## 命令行：`--aiablate=<轮数>[:<组键>,<组键>...]`
##   例 `--aiablate=4`（默认全组）、`--aiablate=4:life2`（只跑死活净效果对照）、`--aiablate=2:noise`
##   可用组键：base / life / life2 / thr / noise / var2 / bud / bud2 / dpen / peye / weye
##             / lad / infl / mix3 / mix5 / mixc / cap / l00 / i00 / l05 / l08 / l92 / s80 / s80b
##             / dc0 / lcb0 / obv0 / k0（KataGo 借鉴三项的净效果）
## 说明：单局比分方差极大，**轮数取偶数**时 A/B 两方的先手次数才严格相等（最干净）。
func _ai_ablate() -> void:
	var rounds := 2
	var pick := ""
	for a in _argv():
		if a.begins_with("--aiablate="):
			var parts: PackedStringArray = a.split("=")[1].split(":")
			rounds = maxi(int(parts[0]), 1)
			if parts.size() > 1:
				pick = parts[1]
	var wanted: PackedStringArray = pick.split(",") if pick != "" else PackedStringArray()
	var budget := 300
	# 大盘（19×19 = 361 格）一局要下 300+ 手，300ms/手会把自检拖到十几分钟。
	# `--aibudget=N` 用来把预算压下来跑对照（两边同预算，比较依然公平）。
	for a in _argv():
		if a.begins_with("--aibudget="):
			budget = maxi(int(a.substr(11)), 20)
	# `--aimoves=N` 只下 N 手就用确定性面积分判胜负：去掉官子随机填充的噪声
	for a in _argv():
		if a.begins_with("--aimoves="):
			_match_max_moves = maxi(int(a.substr(10)), 10)
	var fast := maxi(budget / 3, 60)
	# 每组 = {key, name, black: spec, white: spec}
	var groups: Array = [
		{"key": "base", "name": "① 新默认   vs 旧行为",
		 "black": {"budget": budget}, "white": {"legacy": true, "budget": budget}},
		{"key": "life", "name": "② 关死活   vs 旧行为",
		 "black": {"budget": budget, "life": false}, "white": {"legacy": true, "budget": budget}},
		{"key": "life2", "name": "②b 新默认 vs 关死活（死活机制净效果）",
		 "black": {"budget": budget}, "white": {"budget": budget, "life": false}},
		{"key": "thr", "name": "③ 单线程   vs 旧行为",
		 "black": {"budget": budget, "threads": 1}, "white": {"legacy": true, "budget": budget}},
		{"key": "noise", "name": "④ 新默认   vs 新默认（方差水位）",
		 "black": {"budget": budget}, "white": {"budget": budget}},
		{"key": "var2", "name": "⑤ 旧行为   vs 旧行为（方差水位）",
		 "black": {"legacy": true, "budget": budget}, "white": {"legacy": true, "budget": budget}},
		{"key": "bud", "name": "⑥ 新默认降预算 vs 新默认满预算",
		 "black": {"budget": fast}, "white": {"budget": budget}},
		{"key": "bud2", "name": "⑦ 新默认降预算 vs 旧行为满预算",
		 "black": {"budget": fast}, "white": {"legacy": true, "budget": budget}},
		# ---- 死活四件套的分项消融（每组只关一项，看谁在拖后腿）----
		{"key": "dpen", "name": "⑧ 只关「终局死子扣分」  vs 新默认",
		 "black": {"budget": budget, "override": {"dead_penalty": false}}, "white": {"budget": budget}},
		{"key": "peye", "name": "⑨ 只关「rollout 补活」   vs 新默认",
		 "black": {"budget": budget, "override": {"p_eye": 0.0}}, "white": {"budget": budget}},
		{"key": "weye", "name": "⑩ 只关「做眼/补强先验」 vs 新默认",
		 "black": {"budget": budget, "override": {"w_eye_make": 0.0, "w_weak_each": 0.0}},
		 "white": {"budget": budget}},
		{"key": "lad", "name": "⑪ 只关「征子判定」     vs 新默认",
		 "black": {"budget": budget, "override": {"ladder_enabled": false}}, "white": {"budget": budget}},
		# ---- 大盘（19×19）专项：终局评估的两条改进路径 ----
		{"key": "infl", "name": "⑫ 只关「影响力评估」   vs 新默认",
		 "black": {"budget": budget, "override": {"influence_enabled": false}}, "white": {"budget": budget}},
		{"key": "mix3", "name": "⑬ λ=0.3 静态混合       vs 纯 rollout",
		 "black": {"budget": budget, "override": {"eval_mix_lambda": 0.3}}, "white": {"budget": budget}},
		{"key": "mix5", "name": "⑭ λ=0.5 静态混合       vs 纯 rollout",
		 "black": {"budget": budget, "override": {"eval_mix_lambda": 0.5}}, "white": {"budget": budget}},
		{"key": "mixc", "name": "⑮ λ=0.5 + 影响力       vs 纯 rollout",
		 "black": {"budget": budget, "override": {"eval_mix_lambda": 0.5, "influence_enabled": true}},
		 "white": {"budget": budget, "override": {"influence_enabled": false}}},
		{"key": "cap", "name": "⑯ rollout 上限 240     vs 默认 160",
		 "black": {"budget": budget, "override": {"max_playout_moves": 240}}, "white": {"budget": budget}},
		# ---- λ 混合（AlphaGo 式）：基线一律「改之前的行为」= λ0 + 关影响力 ----
		# λ 取值由 --ailam 实测：19×19 上 rollout 噪声 σ≈65 目、静态评估偏差 b≈15 目，
		# 理论最优 λ* = σ²/(σ²+b²) ≈ 0.92。这里跑 0.5 / 0.8 / 0.92 三档验证
		{"key": "l00", "name": "⑰ 纯 rollout（改动前） vs 自身（方差水位）",
		 "black": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}},
		 "white": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}}},
		{"key": "i00", "name": "⑱ 只开影响力（λ=0）   vs 纯 rollout",
		 "black": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.0}},
		 "white": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}}},
		{"key": "l05", "name": "⑲ λ=0.5 + 影响力      vs 纯 rollout",
		 "black": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.5}},
		 "white": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}}},
		{"key": "l08", "name": "⑳ λ=0.8 + 影响力      vs 纯 rollout",
		 "black": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.8}},
		 "white": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}}},
		{"key": "l92", "name": "㉑ λ=0.92 + 影响力     vs 纯 rollout",
		 "black": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.92}},
		 "white": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}}},
		# ---- rollout 该多长？既然 σ≈65 目说明 rollout 近乎噪声，
		#      那「短 rollout + 多采样」应该优于「长 rollout + 少采样」（静态评估偏差仅 15 目）
		{"key": "s80", "name": "㉒ λ=0.8 + rollout 80  vs 纯 rollout",
		 "black": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.8, "max_playout_moves": 80}},
		 "white": {"budget": budget, "override": {"influence_enabled": false, "eval_mix_lambda": 0.0}}},
		{"key": "s80b", "name": "㉓ λ=0.8 + rollout 80  vs λ=0.8 + rollout 160",
		 "black": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.8, "max_playout_moves": 80}},
		 "white": {"budget": budget, "override": {"influence_enabled": true, "eval_mix_lambda": 0.8}}},
		# ---- KataGo 借鉴三项（动态分中心 / LCB 选点 / 显然手早停）的净效果 ----
		# 思想出处见 katago_study/KataGo研究报告.md：
		#   动态分中心 = 效用按「比上一手预计终局分改善多少」计（search.cpp recentScoreCenter）
		#   LCB 选点   = 实测胜率减 stdevs 倍标准误再参与选点（lcbStdevs）
		#   显然手早停 = 根层一边倒时提前结束（obviousMovesTimeFactor 的简化版）
		{"key": "dc0", "name": "㉔ 关「动态分中心」  vs 新默认",
		 "black": {"budget": budget, "override": {"dynamic_center_enabled": false}}, "white": {"budget": budget}},
		{"key": "lcb0", "name": "㉕ 开「LCB 选点」=2.0 vs 新默认(关)",
		 "black": {"budget": budget, "override": {"pick_lcb_stdevs": 2.0}}, "white": {"budget": budget}},
		{"key": "lcb1", "name": "㉕b 开「LCB 选点」=1.0 vs 新默认(关)",
		 "black": {"budget": budget, "override": {"pick_lcb_stdevs": 1.0}}, "white": {"budget": budget}},
		{"key": "obv0", "name": "㉖ 关「显然手早停」  vs 新默认",
		 "black": {"budget": budget, "override": {"obvious_early_stop": false}}, "white": {"budget": budget}},
		{"key": "k0", "name": "㉗ 三项全关（改动前）  vs 新默认",
		 "black": {"budget": budget, "override": {"dynamic_center_enabled": false, "pick_lcb_stdevs": 0.0, "obvious_early_stop": false}},
		 "white": {"budget": budget}},
		{"key": "dcw5", "name": "㉘ 半重定心(0.5)     vs 全重定心",
		 "black": {"budget": budget, "override": {"dynamic_center_zero_weight": 0.5}}, "white": {"budget": budget}},
		{"key": "dcw5b", "name": "㉙ 半重定心(0.5)     vs 关闭重定心",
		 "black": {"budget": budget, "override": {"dynamic_center_zero_weight": 0.5}},
		 "white": {"budget": budget, "override": {"dynamic_center_enabled": false}}},
	]
	if wanted.size() > 0:
		var filtered: Array = []
		for g in groups:
			if g["key"] in wanted:
				filtered.append(g)
		groups = filtered
	# 每组的黑白得分汇总（下标 0=组内黑方 spec，1=组内白方 spec）
	var totals := {}
	var gems := {}
	for i in groups.size():
		totals[i] = [0, 0, 0]      # [黑总分, 白总分, 局数]
		gems[i] = 0                # 胜局数（黑方视角净胜）
	var head := "[aiablate] 棋盘=%s 格数=%d | 满预算=%dms 降预算=%dms | %d 组 × %d 轮换色 = %d 局" % [
		_board_size_name(GameConfig.board_size), tiles.size(), budget, fast,
		groups.size(), rounds, groups.size() * rounds * 2]
	if rounds % 2 != 0:
		head += "  ⚠ 轮数为奇数 → A/B 先手次数不等，建议用偶数轮"
	print(head)
	_self_play_log("\n===== aiablate " + Time.get_datetime_string_from_system() + " =====")
	_self_play_log(head)
	for r in rounds:
		for i in groups.size():
			var g: Dictionary = groups[i]
			# 偶数轮：spec 黑 vs spec 白；奇数轮：交换颜色，抵消先手优势
			var spec_a: Dictionary = g["black"]
			var spec_b: Dictionary = g["white"]
			var a_is_black: bool = (r % 2 == 0)
			var eng_black := _make_spec_engine(spec_a if a_is_black else spec_b, Stone.BLACK)
			var eng_white := _make_spec_engine(spec_b if a_is_black else spec_a, Stone.WHITE)
			var t0 := Time.get_ticks_msec()
			var res: Array = _play_match(eng_black, eng_white)
			var tb: int = int(res[0])
			var tw: int = int(res[1])
			# 归一到「组内 A 方 / B 方」视角
			var sa: int = tb if a_is_black else tw
			var sb: int = tw if a_is_black else tb
			totals[i][0] = int(totals[i][0]) + sa
			totals[i][1] = int(totals[i][1]) + sb
			totals[i][2] = int(totals[i][2]) + 1
			if sa > sb:
				gems[i] = int(gems[i]) + 1
			var line := "[aiablate] 轮%d %s | A(黑=%s)=%d B(白=%s)=%d 手数=%d 用时=%ds" % [
				r + 1, g["name"],
				"新/降" if a_is_black else "基线", sa,
				"基线" if a_is_black else "新/降", sb,
				res[2], int((Time.get_ticks_msec() - t0) / 1000)]
			print(line)
			_self_play_log(line)
	print("[aiablate] ---------- 汇总（A = 组内第一方，多轮换色后已抵消先手）----------")
	for i in groups.size():
		var t: Array = totals[i]
		var n: int = int(t[2])
		var line := "[aiablate] %s → A %d : B %d | A 胜 %d/%d 局" % [
			groups[i]["name"], t[0], t[1], gems[i], n]
		print(line)
		_self_play_log(line)
	get_tree().quit()

## 自检（--aiprof）：AI 搜索剖析。
## 先制造一个真实中盘局面，再跑一手并打印：树深度（渐进加宽是否真的让搜索有前瞻）、
## 根准备 / 搜索 / 终局评估各占多少时间、热路径的 _play 调用次数。
func _ai_prof() -> void:
	# ★ 2026-10-27 加 `m<N>`：铺局手数覆盖。默认仍是 `n/3`（中盘），但**死子修正与
	#   influence 的命中率都随盘面填充度剧烈变化** —— `--aiprof` 首测（中盘）读到
	#   「死子修正 0/553 = 0.0%」，那是**口径问题**不是「这条代码死了」：中盘空点多，
	#   `_dead_correction` 的前置条件（`empty_cnt*6 <= n` 那类）根本不成立。
	#   要判「死活判别到底有没有生效」必须在**官子局面**重量（§33 死参数 / §106
	#   「判据要跑在能触发目标分支的局面」）。
	#   用法：`--aiprof=m90`（120 格 ⇒ 75% 填充）
	var nmoves_ov := -1
	for a in _argv():
		if a.begins_with("--aiprof=m"):
			nmoves_ov = maxi(int(a.substr(10)), 0)
	var sizes: Array[int] = [GameConfig.STANDARD, GameConfig.ENHANCED]
	for sz in sizes:
		GameConfig.board_size = sz
		_apply_board_size(sz)
		generate_penrose()
		reset_game()
		ai_engine.setup(adjacency, AI_COLOR)
		# 用 rollout 策略在引擎内部棋盘铺出中盘，再导出成对局棋盘（棋形比纯随机真实）
		var nmoves: int = nmoves_ov if nmoves_ov >= 0 else clampi(tiles.size() / 3, 30, 120)
		ai_engine.scramble(nmoves)
		_load_board_from_engine()
		ai_engine.reset_state()
		ai_engine.prof_on = true
		ai_engine.prof_reset()
		ai_engine.time_budget_ms = 800
		var t0 := Time.get_ticks_msec()
		var mv := ai_engine.choose_move(board, -1)
		var el := Time.get_ticks_msec() - t0
		ai_engine.prof_on = false
		var iters: int = ai_engine.prof_iters
		var avg_d := 0.0
		if iters > 0:
			avg_d = float(ai_engine.prof_depth_sum) / float(iters)
		var area_ms := float(ai_engine.prof_area_us) / 1000.0
		var area_each := 0.0
		if ai_engine.prof_area_calls > 0:
			area_each = float(ai_engine.prof_area_us) / float(ai_engine.prof_area_calls)
		print("[aiprof] 棋盘=%s 格数=%d 中盘着数=%d → 落子=%d" % [
			_board_size_name(sz), tiles.size(), nmoves, mv])
		# 存在性判据（§96）：命中率必须连着「盘面填充度」一起读，否则 0% 分不清是
		# 「代码死了」还是「这一档局面根本够不到那个分支」。
		var st_fill := 0
		for i in tiles.size():
			if board[i] != Stone.EMPTY:
				st_fill += 1
		print("[aiprof]   填充=%d/%d = %.1f%%" % [
			st_fill, tiles.size(),
			100.0 * float(st_fill) / float(maxi(tiles.size(), 1))])
		print("[aiprof]   迭代=%d 平均深度=%.1f 最大深度=%d | _play 调用=%d" % [
			iters, avg_d, ai_engine.prof_depth_max, ai_engine.prof_play_calls])
		print("[aiprof]   总耗时=%dms | 根准备=%.0fms 搜索=%.0fms 终局评估=%.0fms(%d 次, %.0f us/次)" % [
			el, float(ai_engine.prof_prepare_us) / 1000.0,
			float(ai_engine.prof_search_us) / 1000.0, area_ms,
			ai_engine.prof_area_calls, area_each])
		if el > 0:
			print("[aiprof]   模拟速率=%.0f 次/秒" % (float(iters) * 1000.0 / float(el)))
		# ★ 三个「一直靠估」的数，实测（2026-10-27）：四个计数器只自增+打印，零行为改动。
		#   为什么要它们：这三项直接决定排期，而此前全是推导/估计：
		#     · influence 命中率 → 「`_influence_field()` 懒化能省多少」（估 <50%~60%，[未测]）
		#     · 死子修正命中率 → 「`_dead_correction` 不对称值不值得修」（估 15~30%，[未测]）
		#     · 每叶子全扫次数 → 「`_scan_cnt` 相位是否真的均匀」（推导 0.857，核心假设未验证）
		var ac: int = ai_engine._area_calls
		var pc: int = ai_engine._playout_calls
		if ac > 0:
			print("[aiprof]   估计值实测：influence 需要 %d/%d = %.1f%% ｜ 死子修正 %d/%d = %.1f%%" % [
				ai_engine._influence_need, ac,
				100.0 * float(ai_engine._influence_need) / float(ac),
				ai_engine._dead_hit, ac,
				100.0 * float(ai_engine._dead_hit) / float(ac)])
		if pc > 0:
			print("[aiprof]   每叶子全盘扫描 %.3f 次（%d/%d，推导值 0.857）" % [
				float(ai_engine._scanall_calls) / float(pc),
				ai_engine._scanall_calls, pc])
		# ★ 叶子分标准差（2026-10-27）：这是「一阶」唯一可直接观测的量。
		#   本手 σ = `_dc_std`（上一手结算值）；跨手均值只在看趋势时用。
		#   ⚠️ σ 是**绝对分**的标准差，标准差对常数平移不变 ⇒ 与「目」级离线 std 可直接对照。
		var st_n: int = int(ai_engine._dc_std_cnt)
		print("[aiprof]   叶子分 σ = %.2f（本手结算）｜ 跨手均值 %.2f（%d 手）" % [
			ai_engine._dc_std, ai_engine._dc_std_sum / maxf(float(st_n), 1.0), st_n])
	get_tree().quit()

## 自战落盘日志：进程超时被杀时 stdout 缓冲区会丢失，写到文件才能看到进度
func _self_play_log(line: String) -> void:
	var path := "user://aiself.log"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()

## AI 自战自检（--aiself）：基线（单线程 + 根全宽）vs 新版（并行 + 根剪枝）同预算对打，
## 双方各先手一局，用于验证改动是否真的转化为棋力（而不是“更快地随机”）
func _ai_self_play() -> void:
	# --aiself=cross：跨档对照（旧策略给足时间 vs 新策略只用约 1/3 时间）。
	# 注意：不对棋盘做切换，始终在当前盘上对照 —— 换尺寸会让 board/adjacency 不一致，
	# 计分会出现超出棋盘总数的荒谬数值
	var cross: bool = _argv().has("--aiself=cross")
	var budget: int = 300
	var base_budget: int = 300
	var chal_budget: int = 300
	var rounds: int = 2
	if cross:
		base_budget = 1000      # 旧策略给足时间
		chal_budget = 300       # 新策略只用约 1/3 的时间
		budget = 0
		rounds = 1
	var base := AIEngine.new()
	base.setup(adjacency, Stone.BLACK)
	base.time_budget_ms = base_budget
	base.threads = 1
	base.root_width = 9999          # 等价旧行为：根节点全宽展开
	# 关掉本次新增的全部死活机制、并把树退回浅层，尽量还原「改造前」的引擎行为
	base.dead_penalty = false
	base.p_eye = 0.0
	base.w_weak_each = 0.0
	base.w_eye_make = 0.0
	base.widen_k = 9.0              # 极限加宽 → 子数上限立刻顶到上限，等效「先铺开再下探」
	base.playout_cap_factor = 1.0
	base.full_scan_every = 10
	base.max_playout_moves = 220    # 旧的 rollout 上限 min(n, 220)
	# KataGo 借鉴三项（2026-09-15）对基线一并关闭：基线语义 = 改动前的引擎行为
	base.dynamic_center_enabled = false
	base.pick_lcb_stdevs = 0.0
	base.obvious_early_stop = false
	var chal := AIEngine.new()
	chal.setup(adjacency, Stone.WHITE)
	chal.time_budget_ms = chal_budget   # 新版默认：threads=0（自动）、root_width=0（自适应）
	if cross:
		print("[aiself] 跨档对照：基线(旧/困难) %d ms vs 新版(普通) %d ms" % [base_budget, chal_budget])
	else:
		print("[aiself] 棋盘=", _board_size_name(GameConfig.board_size), " 格数=", tiles.size(),
			" | 双方预算 ", budget, " ms/手 | 基线=单线程全宽 vs 新版=并行+剪枝")
	var chal_wins := 0
	for flip in rounds:
		var black_eng := base if flip == 0 else chal
		var white_eng := chal if flip == 0 else base
		game_mode = LOCAL            # 关掉人机自动接管，纯手动推演
		reset_game()
		var illegal := 0
		var passes := 0
		var moves := 0
		var base_ms := 0
		var chal_ms := 0
		while passes < 2 and moves < tiles.size() * 2:
			var turn_color: int = current_player
			var eng := black_eng if turn_color == Stone.BLACK else white_eng
			var t0 := Time.get_ticks_msec()
			var mv: int = eng.choose_move(board, ko_point, turn_color)
			_self_play_log(" flip=%d move=%d color=%s mv=%d %dms commod=%d" % [
				flip, moves, "黑" if turn_color == Stone.BLACK else "白", mv,
				Time.get_ticks_msec() - t0, eng.last_playouts])
			if eng == base:
				base_ms += eng.last_ms
			else:
				chal_ms += eng.last_ms
			if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
				if mv >= 0:
					illegal += 1
				passes += 1
			elif place_stone(mv, false):
				moves += 1
				passes = 0
			else:
				illegal += 1
				passes += 1
			if current_player == turn_color:   # 停一手/被拒不会换行棋方 → 手动交换
				current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
		var sc: Dictionary = _compute_scores()
		var black_total: int = int(sc.get("total_black", 0))
		var white_total: int = int(sc.get("total_white", 0))
		var chal_is_black: bool = (flip == 1)
		var chal_total: int = black_total if chal_is_black else white_total
		var base_total: int = white_total if chal_is_black else black_total
		if chal_total > base_total:
			chal_wins += 1
		print("[aiself] 第 %d 局 先手=%s → 基线 %d : 新版 %d | 手数=%d 非法/被拒=%d | 累计耗时 基线 %dms / 新版 %dms | 本局领先=%s" % [
			flip + 1, "基线" if flip == 0 else "新版", base_total, chal_total, moves, illegal,
			base_ms, chal_ms,
			"新版" if chal_total > base_total else ("基线" if base_total > chal_total else "和")])
	print("[aiself] 新版战绩：%d/%d 局领先" % [chal_wins, rounds])
	get_tree().quit()

## 自检（--aitune）：参数对打仪 —— 两组引擎参数互打，胜率给外部调参 runner（爬山/随机搜索）当裁判。
##
## 为什么单独一把尺子：--aiself 的双方是写死的「旧引擎 vs 新引擎」，承载不了任意参数组；
## 调参需要的是「冠军配置 vs 挑战者配置」的胜率读数。纪律与 --aiself 一致：
## 双方同预算、单线程（可复现且不吃多核抖动）、换色对打消除先手优势。
##
## 参数（冒号分隔，盘型 token 同 --aibud）：--aitune=pen,snow,hat:r1:ms8000:pw150:A=c_uct=0.8
##   pen/cube/kite/snow/hat  盘型，**可给多个**（跨盘调参：只许在总账上赢，不许靠单盘刷分）。
##     每种盘型各自 `rN` 轮，逐盘出一行 RESULT，最后出 RESULT_TOTAL 总账。
##   rN     轮数（**每盘**的轮数，一轮 = 2 局换色；默认 1）
##   msN    每手预算毫秒（默认 150，双方相同）
##   pwN    每手模拟次数上限（默认 0=只用时间预算）。⚠️ 时间预算下的模拟次数随机器抖动，
##          同种子也不可复现（--aibud 踩过同款坑）；要确定性对打必须给 pw 且让次数先到。
## ★ 但 ms 必须给得**远大于** pw 的真实耗时（实测 pw150≈200ms/手 → ms 要 8000 这种量级）：
##   引擎内部有按墙钟的时间切片（约 ms/2），ms=400 时它在 ~194ms 就抢先截止了，
##   pw 根本没绑住 → 同种子两次跑出两盘不同的棋。正确写法：r2:ms8000:pw150（已验证逐字可复现）。
##   mN     单局手数上限（默认 220）
##   sN     基准种子（默认 20260926；第 i 局种子 = 基准 + i*97，同参数时两局也不重样）
##   A=k=v,k=v / B=k=v,k=v   参数覆盖（缺省 = 引擎默认值）
##   ⚠️ threads / time_budget_ms / max_playouts 不许覆盖 —— 公平性由仪器强制，违者硬报错退出
##   ⚠️ 参数名必须是 ai_engine.gd 的脚本变量且类型为 bool/int/float，拼错 = 硬报错退出（防静默失效）
## 机读判决行（runner 只认这两类）：
##   [aitune] RESULT board=<盘名> rounds=<r> a_wins=<w> b_wins=<l> draws=<d> a_diff_sum=<±d>
##   [aitune] RESULT_TOTAL boards=<n> rounds=<总轮> a_wins=<w> b_wins=<l> draws=<d>
## ⚠️ 目数差**不跨盘相加**（盘型格数 120/183/162/200/150 不等，分数不同量纲）——
##    跨盘只看胜率总账 + 逐盘胜率，逐盘目数差仅供人工排查。
func _ai_tune_match() -> void:
	var bts: Array[int] = []
	var rounds := 1
	var budget := 150
	var pw := 0
	var max_moves := 220
	var base_seed := 20260926
	var pa := ""
	var pb := ""
	for a in _argv():
		if not a.begins_with("--aitune"):
			continue
		var suffix: String = a.substr(8)          # 8 = "--aitune".length()
		if suffix.begins_with("="):
			suffix = suffix.substr(1)
		for tok in suffix.split(":", false):
			match tok:
				"pen": _aibud_add_board(bts, GameConfig.BOARD_PENROSE)
				"cube": _aibud_add_board(bts, GameConfig.BOARD_CUBE)
				"kite": _aibud_add_board(bts, GameConfig.BOARD_KITE)
				"snow": _aibud_add_board(bts, GameConfig.BOARD_SNOWFLAKE)
				"hat": _aibud_add_board(bts, GameConfig.BOARD_HAT)
				_:
					# ⚠️ ms 必须排在 m 前面：ms150 同样 begins_with("m")；pw 排在 m 前面同理
					if tok.begins_with("r"):
						rounds = maxi(int(tok.substr(1)), 1)
					elif tok.begins_with("ms"):
						budget = maxi(int(tok.substr(2)), 10)
					elif tok.begins_with("pw"):
						pw = maxi(int(tok.substr(2)), 10)
					elif tok.begins_with("m"):
						max_moves = maxi(int(tok.substr(1)), 20)
					elif tok.begins_with("s"):
						base_seed = int(tok.substr(1))
					elif tok.begins_with("A="):
						pa = tok.substr(2)
					elif tok.begins_with("B="):
						pb = tok.substr(2)
					elif "," in tok:
						# 容错：`pen,snow,hat` 也收（--aibud 风格是冒号分隔，这里顺手兼容逗号）
						for bt in tok.split(",", false):
							match bt:
								"pen": _aibud_add_board(bts, GameConfig.BOARD_PENROSE)
								"cube": _aibud_add_board(bts, GameConfig.BOARD_CUBE)
								"kite": _aibud_add_board(bts, GameConfig.BOARD_KITE)
								"snow": _aibud_add_board(bts, GameConfig.BOARD_SNOWFLAKE)
								"hat": _aibud_add_board(bts, GameConfig.BOARD_HAT)
								_:
									print("[aitune] ✗ 未知盘型：「%s」" % bt)
									get_tree().quit(1)
									return
					else:
						# ⚠️ 未知 token 必须硬报错：曾把 `pen,snow,hat` 静默吃成单盘彭罗斯，
						#    照常出结果、exit 0 —— "少跑了两个盘" 和 "三盘都过了" 长得一模一样
						print("[aitune] ✗ 未知 token：「%s」" % tok)
						get_tree().quit(1)
						return
	if bts.is_empty():
		bts = [GameConfig.BOARD_PENROSE]
	var eng_a := AIEngine.new()
	var eng_b := AIEngine.new()
	if not _aitune_apply(eng_a, pa, "A") or not _aitune_apply(eng_b, pb, "B"):
		print("[aitune] RESULT error=1")
		get_tree().quit(1)
		return
	eng_a.threads = 1
	eng_a.time_budget_ms = budget
	eng_b.threads = 1
	eng_b.time_budget_ms = budget
	if pw > 0:
		eng_a.max_playouts = pw
		eng_b.max_playouts = pw
	print("[aitune] 盘型 %d 种 | 每盘 %d 轮（换色） 预算=%dms/手%s 单线程 种子=%d" % [
		bts.size(), rounds, budget,
		(" 模拟上限=%d/手" % pw) if pw > 0 else "", base_seed])
	print("[aitune] A={%s}  B={%s}" % [pa if pa != "" else "默认", pb if pb != "" else "默认"])
	var t_a_wins := 0
	var t_b_wins := 0
	var t_draws := 0
	var gi := 0
	for bt in bts:
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.STANDARD
		_apply_board_size(GameConfig.STANDARD)
		_generate_selected_board()
		reset_game(true)
		print("[aitune] ===== 盘型=%s 格数=%d =====" % [_bt_name(bt), tiles.size()])
		var a_wins := 0
		var b_wins := 0
		var draws := 0
		var a_diff_sum := 0
		for _r in rounds:
			for flip in 2:
				var black_is_a: bool = (flip == 0)
				var eng_black := eng_a if black_is_a else eng_b
				var eng_white := eng_b if black_is_a else eng_a
				var seed_i := base_seed + gi * 97
				gi += 1
				game_mode = LOCAL
				reset_game(true)
				eng_black.setup(adjacency, Stone.BLACK, seed_i)
				eng_white.setup(adjacency, Stone.WHITE, seed_i)
				var illegal := 0
				var passes := 0
				var moves := 0
				var ms_a := 0
				var ms_b := 0
				while passes < 2 and moves < max_moves:
					var turn_color: int = current_player
					var eng := eng_black if turn_color == Stone.BLACK else eng_white
					var mv: int = eng.choose_move(board, ko_point, turn_color)
					if eng == eng_a:
						ms_a += eng.last_ms
					else:
						ms_b += eng.last_ms
					if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
						if mv >= 0:
							illegal += 1
						passes += 1
					elif place_stone(mv, false):
						moves += 1
						passes = 0
					else:
						illegal += 1
						passes += 1
					if current_player == turn_color:   # 停一手/被拒不换行棋方 → 手动交换（同 --aiself）
						current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
				var sc: Dictionary = _compute_scores()
				var a_total: int = int(sc.get("total_black", 0)) if black_is_a else int(sc.get("total_white", 0))
				var b_total: int = int(sc.get("total_white", 0)) if black_is_a else int(sc.get("total_black", 0))
				a_diff_sum += a_total - b_total
				var winner := "和"
				if a_total > b_total:
					a_wins += 1
					winner = "A"
				elif b_total > a_total:
					b_wins += 1
					winner = "B"
				else:
					draws += 1
				print("[aitune] 局 %d 黑=%s → A %d : B %d 胜=%s | 手数=%d 非法=%d | 耗时 A %dms / B %dms" % [
				gi, "A" if black_is_a else "B", a_total, b_total, winner, moves, illegal, ms_a, ms_b])
		print("[aitune] 盘型=%s 总结：A %d 胜 / B %d 胜 / 和 %d | A 目数差累计 %+d" % [
			_bt_name(bt), a_wins, b_wins, draws, a_diff_sum])
		print("[aitune] RESULT board=%s rounds=%d a_wins=%d b_wins=%d draws=%d a_diff_sum=%d" % [
			_bt_name(bt), rounds, a_wins, b_wins, draws, a_diff_sum])
		t_a_wins += a_wins
		t_b_wins += b_wins
		t_draws += draws
	print("[aitune] 总账：A %d 胜 / B %d 胜 / 和 %d（%d 盘 × %d 轮）" % [
		t_a_wins, t_b_wins, t_draws, bts.size(), rounds])
	print("[aitune] RESULT_TOTAL boards=%d rounds=%d a_wins=%d b_wins=%d draws=%d" % [
		bts.size(), bts.size() * rounds, t_a_wins, t_b_wins, t_draws])
	get_tree().quit()

## 数据（--aidata）：给第二档「浅层模型」落盘训练数据（2026-09-27）。
##
## 背景：主先验 `_root_score()` 本来就是「十七个特征 × w_*」的线性加权和，
## 所以第二档 = 学这组权重 + 一个浅层价值头；推理复用现成代码，引擎**零新增运行时开销**。
##
## ★ 取特征的办法（零改动、按构造精确）：把 17 个 `w_*` 逐个设成 1、其余设 0，
##   用 `probe_root_score` 的**差值**反解出每个特征的原始量（恒等式 score = Σ w_i·f_i + 固定项）。
##   代价是每候选 18 次评分，**只在落盘时付** —— 热路径一个字没动，也不存在「特征与训练时漂移」。
##
## 标签：① 策略头 = 教师引擎（模拟上限 `tN`）在该局面选的点记 1，其余候选记 0（蒸馏）；
##       ② 价值头 = 对局结束时出 `G` 行（终局目数），Python 侧按 game 拼回每手的目数差/胜负。
##
## 参数：--aidata=<盘>:gN:pN:tN:kN:mN:sN
##   gN 局数（默认 2）｜pN 走子方模拟上限（默认 150）｜tN 教师模拟上限（默认 600，0=不标注只走棋）
##   kN 每隔几手标注一次（默认 3）｜mN 单局手数上限（默认 220）｜sN 种子（默认 20260927）
## 输出（全部 `[aidata]` 前缀，Python 侧按前缀解析）：
##   FEATNAMES …  POSFEAT …   D,<局>,<手>,<色>,<候选点>,<教师标签>,<18 维特征>
##   V,<局>,<手>,<色>,<7 维位置特征>   G,<局>,<盘型>,<黑目>,<白目>,<手数>
## ★ 直接引用引擎的 `AIEngine.ROOT_W`（第二档策略头的 17 项顺序真源在引擎侧）。
##   原来这里自己抄一份，两份各写各的 —— 特征一旦错位一位，全盘静默：
##   训练器照样收敛、恒等式照样成立，只是学到的是**错位的权重**。
const AIDATA_W: Array[String] = AIEngine.ROOT_W

func _ai_data_dump() -> void:
	var bts: Array[int] = []
	var games := 2
	var pw_p := 150
	var pw_t := 600
	var every := 3
	var max_moves := 220
	var base_seed := 20260927
	for a in _argv():
		if not a.begins_with("--aidata"):
			continue
		var suffix: String = a.substr(8)          # 8 = "--aidata".length()
		if suffix.begins_with("="):
			suffix = suffix.substr(1)
		for tok in suffix.split(":", false):
			match tok:
				"pen": _aibud_add_board(bts, GameConfig.BOARD_PENROSE)
				"cube": _aibud_add_board(bts, GameConfig.BOARD_CUBE)
				"kite": _aibud_add_board(bts, GameConfig.BOARD_KITE)
				"snow": _aibud_add_board(bts, GameConfig.BOARD_SNOWFLAKE)
				"hat": _aibud_add_board(bts, GameConfig.BOARD_HAT)
				_:
					# 逗号连写盘型必须排在 p 前缀分支**前面**：否则 "pen,snow,hat"
					# 被 begins_with("p") 当走子参数吞掉（int("en,snow,hat")=0），
					# bts 保持空 → 静默只跑彭罗斯（2026-09-28 实测两批数据全中招）。
					if _aibud_try_board_list(tok, bts):
						continue
					if tok.begins_with("g"):
						games = maxi(int(tok.substr(1)), 1)
					elif tok.begins_with("p"):
						pw_p = maxi(int(tok.substr(1)), 10)
					elif tok.begins_with("t"):
						pw_t = maxi(int(tok.substr(1)), 0)
					elif tok.begins_with("k"):
						every = maxi(int(tok.substr(1)), 1)
					elif tok.begins_with("m"):
						max_moves = maxi(int(tok.substr(1)), 20)
					elif tok.begins_with("s"):
						base_seed = int(tok.substr(1))
					else:
						print("[aidata] ✗ 未知 token：「%s」" % tok)
						get_tree().quit(1)
						return
	if bts.is_empty():
		bts = [GameConfig.BOARD_PENROSE]
	var feat_eng := AIEngine.new()
	var teacher := AIEngine.new()
	var pol_b := AIEngine.new()
	var pol_w := AIEngine.new()
	# 价值头混入会进 probe_root_score 的常数项（逐候选相同、落在 base 里）——
	# 虽然恒等式仍成立，但特征语义要纯净：落盘仪器明确关掉。
	feat_eng.value_blend = 0.0
	for e in [feat_eng, teacher, pol_b, pol_w]:
		e.threads = 1
		e.time_budget_ms = 30000                  # 兜底：真正截止的是 max_playouts
	print("[aidata] 特征 %d 维（17 项先验特征 + 空邻数）| 盘 %d 种 × %d 局 | 走子 pw=%d 教师 pw=%d 每 %d 手标注 上限 %d 手" % [
		AIDATA_W.size() + 1, bts.size(), games, pw_p, pw_t, every, max_moves])
	var wdefs: Array[String] = []
	for nm in AIDATA_W:
		wdefs.append("%s=%.6f" % [nm, float(feat_eng.get(nm))])
	print("[aidata] FEATNAMES " + ",".join(AIDATA_W) + ",emp_nb,base,orig")
	print("[aidata] WDEFAULTS " + ",".join(wdefs))
	print("[aidata] POSFEAT own_atari_st,own_atari_grp,opp_atari_st,opp_atari_grp,own_2lib_grp,opp_2lib_grp,stone_diff")
	var gid := 0
	for bt in bts:
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.STANDARD
		_apply_board_size(GameConfig.STANDARD)
		_generate_selected_board()
		for _gi in games:
			gid += 1
			var seed_g := base_seed + gid * 1013
			game_mode = LOCAL
			reset_game(true)
			pol_b.setup(adjacency, Stone.BLACK, seed_g)
			pol_w.setup(adjacency, Stone.WHITE, seed_g + 1)
			teacher.setup(adjacency, Stone.BLACK, seed_g + 2)
			feat_eng.setup(adjacency, Stone.BLACK, seed_g + 3)
			pol_b.max_playouts = pw_p
			pol_w.max_playouts = pw_p
			teacher.max_playouts = maxi(pw_t, 1)
			var passes := 0
			var moves := 0
			# ★ 2026-10-04：`w_local`（贴身应战，第一档跨盘冠军）的触发条件是
			#   `if last >= 0 and _is_adj(v, last)`（ai_engine.gd:2715）⇒ **依赖"对手上一手"**。
			#   旧代码落盘时 last 恒 -1 ⇒ 该特征恒 0 ⇒ 训练器对它**没有梯度**（实测 72927 行里
			#   非零行数 = 0），而它恰是第一档的跨盘冠军参数 ⇒ 第二档学不到最重要的那个先验。
			#
			#   快照语义（**踩了三次才对**）：要的是「**对手上一手落子之前**」的盘面。
			#   ★ 错法一（已报红）：每步都更新 ⇒ 轮到我方时对手那子已在快照里 ⇒ 差分恒 -1。
			#   ★ 错法二（已报红）：只在 `current_player == tc`（换边）时更新 ⇒ `place_stone`
			#     内部**自己**换行棋方 ⇒ 那个分支基本不进 ⇒ 快照永远是空字典（prev_keys=0）。
			#   ⇒ 正确：**每步都记「本步落子之前的盘面」，并记住那步是谁走的**；
			#     轮到我方时，用**上一步（对手那步）之前的盘面**去做差分。
			var before_this_step: Dictionary = board.duplicate()
			var prev_step_color: int = -1          # 上一步落子的行棋方（-1=还没有）
			var board_before_prev_step: Dictionary = board.duplicate()  # 上上步之前的盘面
			while passes < 2 and moves < max_moves:
				var tc: int = current_player
				var eng := pol_b if tc == Stone.BLACK else pol_w
				if pw_t > 0 and moves % every == 0:
					# 上一步是对手落的 ⇒ 用「上上步之前的盘面」当差分基准。
					_aidata_emit(gid, moves, tc, teacher, feat_eng,
							board_before_prev_step if prev_step_color != tc else {})
				var mv: int = eng.choose_move(board, ko_point, tc)
				if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
					passes += 1
				elif place_stone(mv, false):
					moves += 1
					passes = 0
				else:
					passes += 1
				# 步进快照链：上上步 ← 上步 ← 本步之前
				board_before_prev_step = before_this_step
				before_this_step = board.duplicate()
				prev_step_color = tc
				if current_player == tc:           # 停一手/被拒不换行棋方 → 手动交换
					current_player = Stone.WHITE if tc == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			print("[aidata] G,%d,%s,%d,%d,%d" % [gid, _bt_name(bt),
				int(sc.get("total_black", 0)), int(sc.get("total_white", 0)), moves])
	get_tree().quit()

## 一个局面：先出价值头的 7 维位置特征，再对每个合法候选出策略头的 18 维特征 + 教师标签。
func _aidata_emit(gid: int, ply: int, color: int, teacher: AIEngine, fe: AIEngine,
		prev_board: Dictionary = {}) -> void:
	var tmv: int = teacher.choose_move(board, ko_point, color)
	print("[aidata] V,%d,%d,%d,%s" % [gid, ply, color, _aidata_fmt(_aidata_pos_feats(color))])
	# ★ 对手上一手：与引擎 `_infer_opp_move()` 同口径（唯一新增对手子；多于一个则 -1）
	#   ⚠️ `board` 是 Dictionary ⇒ 判"同一张盘"不能比 size()（键个数），要比**键集合**。
	var opp_last := -1
	if not prev_board.is_empty():
		opp_last = fe.probe_opp_last(board, prev_board, color)
	for v in tiles.size():
		if board[v] != Stone.EMPTY or v == ko_point:
			continue
		var f := _aidata_row(fe, v, color, opp_last)
		print("[aidata] D,%d,%d,%d,%d,%d,%s" % [gid, ply, color, v, int(v == tmv), _aidata_fmt(f)])


## 落盘一行的完整特征向量 = **引擎给的 18 项量** + **base** + **orig**（21 维）。
##   末两列不是重复信息：训练器靠 `orig == base + Σ w_i·terms_i` 做恒等式自检
##   （引擎改权重时若破坏了仿射性，这里立刻对不上，而不是静默学到错权重）。
##   ⚠️ 拼装只在这里做 —— `_aidata_features()` 保持"引擎量"的纯粹语义，
##   免得两处各自拼一遍、顺序拼错一位（那正是旧数据 `w_local` 恒零那类静默故障的形状）。
func _aidata_row(fe: AIEngine, v: int, turn: int, opp_last: int) -> PackedFloat32Array:
	var r: Dictionary = fe.probe_root_terms_last(board, v, turn, opp_last)
	var terms: PackedFloat32Array = r["terms"]
	var out := PackedFloat32Array()
	out.resize(AIDATA_W.size() + 3)          # 17 项 + emp_nb + base + orig
	for i in terms.size():
		out[i] = terms[i]
	out[AIDATA_W.size() + 1] = float(r["base"])
	out[AIDATA_W.size() + 2] = float(r["orig"])
	return out


## 价值头的位置特征：只装「棋块安危」这一类（用户点名的失误是「不救被吃的子 / 白送成块」）。
##   被打吃子数/块数（双方各二）、两气块数（薄棋）、盘面子数差。
func _aidata_pos_feats(color: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(7)
	var seen: Array[int] = []
	seen.resize(tiles.size())
	for i in tiles.size():
		seen[i] = 0
	var own_st := 0
	var opp_st := 0
	var q: Array[int] = []
	for s in tiles.size():
		if seen[s] != 0 or board[s] == Stone.EMPTY:
			continue
		var c: int = board[s]
		var gsz := 0
		var libs := 0
		var lseen: Array[int] = []
		lseen.resize(tiles.size())
		q.clear()
		q.append(s)
		seen[s] = 1
		var qi := 0
		while qi < q.size():
			var cur: int = q[qi]
			qi += 1
			gsz += 1
			for nb in adjacency[cur]:
				if board[nb] == Stone.EMPTY:
					if lseen[nb] == 0:
						lseen[nb] = 1
						libs += 1
				elif board[nb] == c and seen[nb] == 0:
					seen[nb] = 1
					q.append(nb)
		if c == color:
			own_st += gsz
			if libs == 1:
				out[0] += float(gsz)
				out[1] += 1.0
			elif libs == 2:
				out[4] += 1.0
		else:
			opp_st += gsz
			if libs == 1:
				out[2] += float(gsz)
				out[3] += 1.0
			elif libs == 2:
				out[5] += 1.0
	out[6] = float(own_st - opp_st)
	return out

func _aidata_fmt(a: PackedFloat32Array) -> String:
	var parts: Array[String] = []
	for x in a:
		parts.append("%.4f" % x)
	return ",".join(parts)


## 仪器（`--aigraph`，2026-10-23）：导出**图结构 + 局面 + 教师标签**，给「图无关」神经网络训练。
##
## 【为什么不能复用 `--aidata`】
## 那份数据每行只有**候选级 21 维标量**，既没有盘面也没有边表 ⇒ 训出来的东西必然锁死在
## 「17 项线性特征」这个天花板里（2026-10-04 已实测：策略头配对 t=+2.20，不过线）。
## 要「能匹配所有图」的网络，训练端必须拿到 **state + edge list** 自己算点级特征：
## 点级输入与盘点数/度数无关 ⇒ 120 格的彭罗斯上训出的权重可以直接喂 204/360 格的盘。
##
## 【输出格式】全部走 stdout（由外部重定向到文件），每行带 `GNN,` 前缀便于管道过滤：
##   GNN,H,<版本>,<盘型数>,<说明>
##   GNN,T,<tid>,<盘型名>,<n>,<边数>,<度数直方图>,<u0>,<v0>,<u1>,<v1>,…   ← 拓扑，每盘型一行
##   GNN,S,<gid>,<tid>,<ply>,<color>,<ko>,<state>                        ← 局面
##   GNN,L,<gid>,<ply>,<teacher_v>                                      ← 教师选点（-1=停一手）
##   GNN,G,<gid>,<tid>,<winner>,<black_total>,<white_total>,<moves>       ← 终局
##
## ★ `state` 是 **n 个单字符**（'0' 空 / '1' 黑 / '2' 白），不是逗号分隔的整数：
##   120~360 个数字用逗号会让每行膨胀约 3 倍，而这份数据要按万局面计。
## ★ 边表只存 u<v（无向去重）。彭罗斯 120 格 = **221 条边、平均度 3.68**（jevdump 实测）。
## ★ `color` 是**该局面轮到谁走**；`ko` 是该局的劫点（-1 = 无）。
##   Python 侧据此自己判合法点（空 + 非劫点），不要依赖 Godot 再吐一份候选表。
func _aigraph_probe() -> void:
	var games: int = 1
	var every: int = 1
	var max_moves: int = 220
	var pw_p: int = 150
	var pw_t: int = 600
	var base_seed: int = 20261023
	var bts: Array[int] = []
	# `--aigraph=` 正好 10 个字符（`--` + `aigraph`(7) + `=`）⇒ 从 10 切。
	# ⚠ 与 `--liudiag`（10）/`--liudrill`（11）同一条纪律：长度是硬编码字面量，差一位就静默错位（§109）。
	for a in _argv():
		if not a.begins_with("--aigraph="):
			continue
		for tok in a.substr(10).split(":", false):
			var pr := tok.split("=")
			var k: String = str(pr[0])
			var val: String = "" if pr.size() < 2 else str(pr[1])
			if k == "g":
				games = int(val)
			elif k == "every":
				every = maxi(int(val), 1)
			elif k == "max":
				max_moves = int(val)
			elif k == "pp":
				pw_p = int(val)
			elif k == "pt":
				pw_t = int(val)
			elif k == "s":
				base_seed = int(val)
			elif k == "bt":
				for nm in val.split(",", false):
					var b: int = _aigraph_bt(nm)
					if b < 0:
						print("[aigraph] ✗ 未知盘型「%s」（支持 penrose/cube/kite/snow/hat）" % nm)
						get_tree().quit(1)
						return
					bts.append(b)
			else:
				print("[aigraph] ✗ 未知 token：「%s」（支持 g=/every=/max=/pp=/pt=/s=/bt=）" % tok)
				get_tree().quit(1)
				return
	if bts.is_empty():
		bts = [GameConfig.BOARD_PENROSE]

	# 本仪器**不写谱**：它按万局面跑，一局一谱会把用户棋谱库灌满。
	# （名字不含 "test" ⇒ 不走 `is_automated_run()` 的自动改道，必须手动静音。）
	_record_muted = true

	var teacher := AIEngine.new()
	var pol_b := AIEngine.new()
	var pol_w := AIEngine.new()
	teacher.threads = 1
	teacher.time_budget_ms = 30000        # 真正兜底的是 max_playouts
	teacher.max_playouts = maxi(pw_t, 1)
	for e in [pol_b, pol_w]:
		e.threads = 1
		e.time_budget_ms = 30000
		e.max_playouts = maxi(pw_p, 1)

	print("GNN,H,1,%d,state=char01black2white;edges=u<v;color=next-to-move;ko=-1=none" % bts.size())
	var gid := 0
	for bt in bts:
		# ★ tid 必须是**与盘型绑定的稳定值**，不能用自增计数器：
		#   训练数据常常由多次导出拼成（先彭罗斯、再立方体…），每次进程都从 1 开始编号
		#   ⇒ 两个文件的 tid 撞车 ⇒ Python 侧 `topo[tid]` 静默覆盖成另一张盘的边表
		#   （"训练和推理不是同一张图"这种错不会报任何异常）。用枚举值 +1 就永久不会撞。
		var tid: int = bt + 1
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.STANDARD
		_apply_board_size(GameConfig.STANDARD)
		_generate_selected_board()
		var n: int = tiles.size()
		# ---- 拓扑：每盘型一行（边表 + 度数直方图）—— 格式真源在 `_topo_line()` ----
		print(_topo_line("GNN", tid, bt))
		for _gi in games:
			gid += 1
			var seed_g: int = base_seed + gid * 1013
			game_mode = LOCAL
			reset_game(true)
			pol_b.setup(adjacency, Stone.BLACK, seed_g)
			pol_w.setup(adjacency, Stone.WHITE, seed_g + 1)
			teacher.setup(adjacency, Stone.BLACK, seed_g + 2)
			var passes := 0
			var moves := 0
			while passes < 2 and moves < max_moves:
				var tc: int = current_player
				if pw_t > 0 and moves % every == 0:
					# 局面行 + 教师标签行成对出现 ⇒ Python 侧读到 S 就等 L，不必靠顺序猜。
					var st := ""
					for v in n:
						st += str(board[v])
					print("GNN,S,%d,%d,%d,%d,%d,%s" % [gid, tid, moves, tc, ko_point, st])
					var tv: int = teacher.choose_move(board, ko_point, tc)
					if tv < 0 or tv >= n or board[tv] != Stone.EMPTY or tv == ko_point:
						tv = -1
					print("GNN,L,%d,%d,%d" % [gid, moves, tv])
				var eng := pol_b if tc == Stone.BLACK else pol_w
				var mv: int = eng.choose_move(board, ko_point, tc)
				if mv < 0 or mv >= n or board[mv] != Stone.EMPTY or mv == ko_point:
					passes += 1
				elif place_stone(mv, false):
					moves += 1
					passes = 0
				else:
					passes += 1
				if current_player == tc:           # 停一手/被拒不换行棋方 → 手动交换
					current_player = Stone.WHITE if tc == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			var tb: int = int(sc.get("total_black", 0))
			var tw: int = int(sc.get("total_white", 0))
			var winner: int = 0
			if tb > tw:
				winner = 1
			elif tw > tb:
				winner = 2
			print("GNN,G,%d,%d,%d,%d,%d,%d" % [gid, tid, winner, tb, tw, moves])
	get_tree().quit()


## `--aigraph` 的盘型名 → GameConfig 枚举；未知返回 -1（由调用方报错退出）。
func _aigraph_bt(nm: String) -> int:
	match nm.to_lower():
		"penrose": return GameConfig.BOARD_PENROSE
		"cube": return GameConfig.BOARD_CUBE
		"kite": return GameConfig.BOARD_KITE
		"snow": return GameConfig.BOARD_SNOWFLAKE
		"hat": return GameConfig.BOARD_HAT
		_: return -1


## 拓扑行 —— `--aigraph` 与 `--selfplay` 的**唯一真源**（2026-10-24 抽出）。
##
## ★ 为什么必须抽成一个函数：这段格式是**训练端与引擎端的契约**。留两份拷贝迟早漂移，
##   而漂移的症状是「训练用的图和推理用的图不是同一张」—— 不报任何异常，模型照样训、
##   照样出报告，只是推理时节点顺序对不上（§8 一处写一处读）。
##
## 前置条件：调用方已经把 `adjacency` / `tiles` 生成为目标盘型。
## 行格式：`<prefix>,T,<tid>,<盘型名>,<n>,<边数>,<度数直方图>,<u0>,<v0>,...`
## 边表只出 `nb > v` 的一半（无向图），消费侧自行补反向。
func _topo_line(prefix: String, tid: int, bt: int) -> String:
	var n: int = tiles.size()
	var parts: Array[String] = []
	var ne := 0
	var hist: Dictionary = {}
	for v in n:
		hist[adjacency[v].size()] = int(hist.get(adjacency[v].size(), 0)) + 1
		for nb in adjacency[v]:
			if nb > v:
				ne += 1
				parts.append("%d" % v)
				parts.append("%d" % nb)
	var hnames: Array[int] = []
	for dk in hist.keys():
		hnames.append(int(dk))
	hnames.sort()
	var hparts: Array[String] = []
	for dk in hnames:
		hparts.append("%d:%d" % [dk, int(hist[dk])])
	return "%s,T,%d,%s,%d,%d,%s,%s" % [prefix, tid, _bt_name(bt), n, ne,
		"|".join(hparts), ",".join(parts)]


## 自检（--dcwtest）：动态分中心混合权重 `dynamic_center_zero_weight` 专项
##（2026-10-05）。
##
## 【这个 bug 的性质】该参数在 @export 与 copy_to 里都有，但 `_result_impl`
##   **从不读它** ⇒ 完全失效 ⇒ `--aiablate` 的 ㉘/㉙ 两组消融结论无效。
##   这不是"哪个参数更好"的问题，是**参数没接上** ⇒ 可确定性论证。
##
## 判据四段（每段都必须会红）：
##   ① **牙齿段（最关键）**：w=0.5 必须**不等于** w=0。
##      旧代码忽略 w ⇒ 两者恒等 ⇒ 修前必红。这段是本自检存在的原因。
##   ② **阴性对照 · w=0**精确退化为「纯相对分」sc - center（抓符号反了）。
##   ③ **阴性对照 · w=1**精确退化为「纯绝对分」sc（抓多减了一次 center）。
##      ⚠️ w=1 走的是**带 cap 的分支**（不是 `_dc_has=false` 那条）——
##      故意：若拿"关掉重定心"那路当等价，极端分差下 cap 行为不同 ⇒ 必须分开钉。
##   ④ **单调性**：效用对 w 必须**单调递增**（w 越大越偏绝对分；
##      本夹具 sc>center>0 ⇒ rel 随 w 增大 ⇒ tanh 增大）。抓"混合方向写反"。
##   ⑤ 自身自检：同参数两次调用必须**完全相等**（抓随机性污染）。
func _dc_weight_test() -> void:
	var E := ai_engine
	_test_build_square_grid(TEST_GRID_N)
	reset_game(true)
	E.setup(adjacency, Stone.BLACK)
	var ok := true
	# 夹具取值：sc 与 center 同号且 sc>center>0 ⇒ rel = sc-(1-w)*center 全程为正，
	# 且 w 增大时 rel 单调增 ⇒ 避开 tanh 负半轴上"先增后减"的歧义。
	var sc := 12.0
	var center := 5.0

	# ① 牙齿：w=0.5 与 w=0 必须不同（旧代码下两者恒等 ⇒ 修前必红）
	var u_w0: float = E.probe_dc_utility(sc, center, 0.0)
	var u_w05: float = E.probe_dc_utility(sc, center, 0.5)
	var gap: float = absf(u_w05 - u_w0)
	var ok1: bool = gap > 1e-6
	print("[dcwtest] ① 牙齿 w=0.5(%.6f) vs w=0(%.6f) 差 %.6f ⇒ %s"
		% [u_w05, u_w0, gap, "有差异 ✓" if ok1 else "完全相同 ✗ 参数仍未生效"])
	ok = ok and ok1

	# ② 阴性对照 w=0：精确等于 tanh(sc - center)
	var exp0: float = 0.5 + 0.5 * tanh((sc - center) / maxf(E.score_soft, 0.5))
	var ok2: bool = absf(u_w0 - exp0) < 1e-9
	print("[dcwtest] ② w=0 纯相对分 实测 %.9f 期望 %.9f ⇒ %s"
		% [u_w0, exp0, "通过 ✓" if ok2 else "未通过 ✗"])
	ok = ok and ok2

	# ③ 阴性对照 w=1：精确等于 tanh(sc)（注意仍走带 cap 的分支）
	var exp1: float = 0.5 + 0.5 * tanh(sc / maxf(E.score_soft, 0.5))
	var u_w1: float = E.probe_dc_utility(sc, center, 1.0)
	var ok3: bool = absf(u_w1 - exp1) < 1e-9
	print("[dcwtest] ③ w=1 纯绝对分 实测 %.9f 期望 %.9f ⇒ %s"
		% [u_w1, exp1, "通过 ✓" if ok3 else "未通过 ✗"])
	ok = ok and ok3

	# ④ 严格递增：w 从 0 → 1 效用必须**每一步都严格增**。
	#    ⚠️ 不能只判"单调不减"—— 修前（参数失效）全序列恒等，"非递减"照样通过
	#    ⇒ 那是一条恒真判据（铁律 4：对照/判据本身也要有牙齿）。
	#    本夹具 sc>center>0 ⇒ rel 随 w 严格增 ⇒ tanh 严格增。
	var us: Array[float] = []
	for w in [0.0, 0.25, 0.5, 0.75, 1.0]:
		us.append(E.probe_dc_utility(sc, center, w))
	var mono := true
	for i in range(1, us.size()):
		if us[i] <= us[i - 1] + 1e-9:
			mono = false
	print("[dcwtest] ④ 严格递增 w=0→1 效用 %s ⇒ %s"
		% [str(us), "严格增 ✓" if mono else "非严格增 ✗（修前会是全等 ⇒ 恒真判据已避开）"])
	ok = ok and mono

	# ⑤ 自身自检：两次调用必须完全相等
	var again: float = E.probe_dc_utility(sc, center, 0.5)
	var ok5: bool = absf(again - u_w05) < 1e-12
	print("[dcwtest] ⑤ 自身自检 两次调用差 %.12f ⇒ %s"
		% [absf(again - u_w05), "通过 ✓" if ok5 else "未通过 ✗ 存在随机性"])
	ok = ok and ok5

	# 附：has_center=false 必须退化为绝对分（首手无锚点路径）
	var u_no: float = E.probe_dc_utility(sc, center, 0.0, false)
	var ok6: bool = absf(u_no - exp1) < 1e-9
	print("[dcwtest] 附 无锚点(首手) %.9f == 绝对分 %.9f ⇒ %s"
		% [u_no, exp1, "通过 ✓" if ok6 else "未通过 ✗"])
	ok = ok and ok6

	# 附★ 默认值零行为变化：本修复的**上线前提**是 w 保持默认 0.0（否则等于悄悄改了棋力）。
	#   逐位验证 (1-0)*center == center ⇒ clamp 输入相同 ⇒ 输出必然相同。
	# 扫多档极端分/锚点（含|sc|>cap 的饱和区），证明「修后 w=0」== 「修前公式」。
	var zero_same := true
	for n2v in [61, 120, 183, 381]:
		var cap2: float = sqrt(float(n2v))
		for sc2 in [-300.0, -7.0, 0.0, 7.0, 300.0]:
			for c2 in [-200.0, -30.0, 0.0, 30.0, 200.0]:
				var old_u: float = 0.5 + 0.5 * tanh(clampf(sc2 - c2, -cap2, cap2) / maxf(E.score_soft, 0.5))
				var new_u: float = 0.5 + 0.5 * tanh(
					clampf(sc2 - (1.0 - 0.0) * c2, -cap2, cap2) / maxf(E.score_soft, 0.5))
				if absf(old_u - new_u) > 1e-12:
					zero_same = false
	print("[dcwtest] 附★ 默认 w=0 零行为变化（4盘×5分×5锚点=100 组，含饱和区）⇒ %s"
		% ("逐位相同 ✓" if zero_same else "出现差异 ✗ 默认值下行为变了"))
	ok = ok and zero_same

	print("[dcwtest] 结果：%s" % ("通过 ✓" if ok else "失败 ✗"))
	get_tree().quit()


## 自检（--vtest）：价值头专项（2026-09-28）。
## 风险：引擎 `_value_after_move` 与落盘仪器 `_aidata_pos_feats` 是**两套 7 维特征
## 实现**——不对拍迟早分岔（铁律：同一判据两处实现必须互检）。判据：
##   ① 空盘首手：value 精确 = v_bias + v_stone_diff（对方视角 sd=−1、其余特征 0）；
##   ② 提子局面：引擎对「落子提 3 子后」盘面的预测 == 落盘仪器特征 × 训练权重的
##     手工展开取负。②同时抓「漏提子」：不提子 sd 差 3 子 → 差约 8 目，必红；
##   ③ 混入口径：value_blend 0↔1 的 probe_root_score 差值 == 直接调用的 value 值
##     （抓挂钩接错位置 / 符号反了）。
func _value_head_test() -> void:
	var E := ai_engine
	# ① 空盘首手（坐标跑在方形邻接夹具上，同 --ladtest）
	_test_build_square_grid(TEST_GRID_N)
	reset_game(true)
	E.setup(adjacency, Stone.BLACK)     # 引擎必须按夹具重 setup，否则 n=120 → 121 越界
	E.load_board_for_probe(board)
	var v0: float = E._value_after_move(6 * TEST_GRID_N + 7, Stone.BLACK)
	# 推导：黑落 1 子 → 对方(行棋方)视角 sd=−1 → pred = v_bias − v_stone_diff
	#       → value = −pred = v_stone_diff − v_bias（★ 别忘了取负）
	var exp0: float = E.v_stone_diff - E.v_bias
	var ok1: bool = absf(v0 - exp0) < 0.01
	print("[vtest] ① 空盘首手 value=%.4f（期望 %.4f = v_stone_diff−v_bias）→ %s" % [
		v0, exp0, "通过 ✓" if ok1 else "未通过 ✗"])
	# ② 提子局面（--ladtest ⑥ 同款几何、黑白对调：白 3 子被叫吃，黑下提子点）
	reset_game(true)
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		board[p.y * TEST_GRID_N + p.x] = Stone.WHITE
	for p in [Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(4, 5), Vector2i(5, 6),
			  Vector2i(6, 6), Vector2i(8, 5)]:
		board[p.y * TEST_GRID_N + p.x] = Stone.BLACK
	var cap := Vector2i(7, 6)
	board[cap.y * TEST_GRID_N + cap.x] = Stone.BLACK              # 落子
	for p in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)]:
		board[p.y * TEST_GRID_N + p.x] = Stone.EMPTY              # 提掉 3 白子
	# 落盘仪器实现（game.gd，V 行数据的来源）算同一盘面（行棋方=白=对方视角）
	var fg: PackedFloat32Array = _aidata_pos_feats(Stone.WHITE)
	var pred_gd: float = E.v_bias \
		+ E.v_own_atari_st * fg[0] + E.v_own_atari_grp * fg[1] \
		+ E.v_opp_atari_st * fg[2] + E.v_opp_atari_grp * fg[3] \
		+ E.v_own_2lib_grp * fg[4] + E.v_opp_2lib_grp * fg[5] \
		+ E.v_stone_diff * fg[6]
	var exp2: float = -pred_gd
	E.load_board_for_probe(board)
	var v2: float = E._value_after_move(cap.y * TEST_GRID_N + cap.x, Stone.BLACK)
	var ok2: bool = absf(v2 - exp2) < 0.01
	print("[vtest] ② 提子对拍 引擎=%.4f 仪器展开=%.4f（提3子后白视角 sd=−8）→ %s" % [
		v2, exp2, "通过 ✓" if ok2 else "未通过 ✗"])
	# ③ 混入口径：找任意空点，probe 差值必须等于直接调用值
	var vp := -1
	for i in tiles.size():
		if board[i] == Stone.EMPTY:
			vp = i
			break
	E.value_blend = 0.0
	var s0v: float = E.probe_root_score(board, vp, Stone.BLACK)
	E.value_blend = 1.0
	var s1v: float = E.probe_root_score(board, vp, Stone.BLACK)
	E.value_blend = 0.0
	var v3: float = E._value_after_move(vp, Stone.BLACK)
	var d3: float = s1v - s0v
	var ok3: bool = absf(d3 - v3) < 0.01
	print("[vtest] ③ 混入口径 probe差值=%.4f 直接调用=%.4f → %s" % [
		d3, v3, "通过 ✓" if ok3 else "未通过 ✗"])
	get_tree().quit()

## --aitune 的参数覆盖层：只收 ai_engine.gd 的脚本变量（bool/int/float），
## 拼错 / 覆盖公平性字段 → 硬报错（返回 false，调用方 quit(1)）。
## 用 get_property_list() 运行期点名册而不是手抄清单：引擎加参数不用同步改这里。
func _aitune_apply(eng: AIEngine, spec: String, side: String) -> bool:
	if spec.is_empty():
		return true
	for kv in spec.split(",", false):
		var eq := kv.find("=")
		if eq <= 0:
			print("[aitune] ✗ %s 方参数格式错误（应为 k=v）：「%s」" % [side, kv])
			return false
		var key := kv.substr(0, eq)
		var val_s := kv.substr(eq + 1)
		if key == "threads" or key == "time_budget_ms" or key == "max_playouts":
			print("[aitune] ✗ %s 方不许覆盖 %s（公平性由仪器强制：单线程+同预算）" % [side, key])
			return false
		var found := false
		for p in eng.get_property_list():
			if p["name"] == key and (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				found = true
				match int(p["type"]):
					TYPE_BOOL:
						eng.set(key, val_s == "true" or val_s == "1")
					TYPE_INT:
						eng.set(key, int(round(val_s.to_float())))
					TYPE_FLOAT:
						eng.set(key, val_s.to_float())
					_:
						print("[aitune] ✗ %s 方参数 %s 类型不支持（只收 bool/int/float）" % [side, key])
						return false
				break
		if not found:
			print("[aitune] ✗ %s 方未知参数：「%s」（名册见 ai_engine.gd 的 @export）" % [side, key])
			return false
	return true

## 自检（仅 --passtest 触发）：本地双人模式停一手 → 只能换手给另一位人类，不得出现 AI
func _self_test_local_pass() -> void:
	print("[自检] 模式=", "本地" if game_mode == LOCAL else "人机",
		" | 起手=", ("黑" if current_player == Stone.BLACK else "白"))
	print("[自检] 停一手按钮存在=", _pass_btn != null)
	var ok := true
	_on_pass_pressed()
	print("[自检] 第 1 次停一手 → 轮到 ", ("黑" if current_player == Stone.BLACK else "白"),
		" | is_ai_thinking=", is_ai_thinking, " | game_over=", game_over)
	if is_ai_thinking or game_over or current_player != Stone.WHITE:
		ok = false
	_on_pass_pressed()
	print("[自检] 第 2 次停一手 → 轮到 ", ("黑" if current_player == Stone.BLACK else "白"),
		" | is_ai_thinking=", is_ai_thinking, " | game_over=", game_over)
	if is_ai_thinking or not game_over:
		ok = false
	# ---- AI 停一手必须入账（`_hist` + 棋谱 + 桥的 parity 不变量）----
	# 2026-10-13 实测 bug：`_apply_ai_move(-1)` 原来只 `passes += 1` + 换手，
	# 不入 `_hist` 也不入谱 ⇒ ① 棋谱缺这一手 ⇒ 记录出现连续两手同色，按谱复盘重放必错；
	# ⚠ 铁律 4：修之前 passtest 就是绿的 ⇒ 它根本没测 AI 停一手（只测了人类停一手）。
	game_mode = VS_AI
	reset_game()
	# 玩家（黑）真落一手 ⇒ 轮到 AI（白）。走 `place_stone()` 真路径，不手摆回合状态
	var spot := -1
	for t in tiles.size():
		if can_place_at(t, Stone.BLACK):
			spot = t
			break
	var placed: bool = spot >= 0 and place_stone(spot, false)
	var ai_ph: Dictionary = {}
	var ai_pr: Dictionary = {}
	if placed and current_player == AI_COLOR:
		# 被测函数。`_start_ai_turn()` → `_apply_ai_move()` 的接线本次没动，
		# bug 在函数内部（该入账没入账）⇒ 直接调它就是打在同一处上
		_apply_ai_move(-1)
		if not _hist.is_empty():
			ai_ph = _hist.back()
		var rm: Array = _record.get("moves", []) as Array
		if not rm.is_empty():
			ai_pr = rm.back()
	else:
		ok = false
		print("[自检] AI 停一手前置失败：摆不下玩家第一手或回合不对（placed=%s 轮到=%s）" % [
			placed, "白" if current_player == Stone.WHITE else "黑"])
	var c_hist: bool = (int(ai_ph.get("tile", 0)) == -1
		and bool(ai_ph.get("pass_move", false))
		and int(ai_ph.get("color", -1)) == AI_COLOR)
	var c_rec: bool = int(ai_pr.get("tile", 0)) == -1
	# ★ 行棋方 parity 不变量（Ludii 退役后**保留**）：把 `_hist` 序列化成 [color, tile]，
	#   按着手方计数推出的「该谁走」必须等于 `current_player` —— 它是「停一手也必须入账」
	#   这条契约的**独立**表达（原来借桥的 history desync 校验来暴露，现在由本机自检自己断言）。
	var payload: Array = []
	for e in _hist:
		payload.append([int(e["color"]), int(e["tile"])])
	var first_c: int = Stone.BLACK if payload.is_empty() else int(payload[0][0])
	var implied: int = first_c if payload.size() % 2 == 0 else (
		Stone.WHITE if first_c == Stone.BLACK else Stone.BLACK)
	var c_par: bool = implied == current_player
	var c_state: bool = passes == 1 and current_player == PLAYER_COLOR and not game_over
	var c_ai: bool = c_hist and c_rec and c_par and c_state
	if not c_ai:
		ok = false
	print("[自检] AI 停一手入账：_hist 末手=%s｜谱末手 tile=%d｜parity 推算=%s 实际=%s｜passes=%d 轮到=%s → %s" % [
		"pass_move ✓" if c_hist else "缺 pass_move ✗", int(ai_pr.get("tile", 0)),
		"白" if implied == Stone.WHITE else "黑", "白" if current_player == Stone.WHITE else "黑",
		passes, "白" if current_player == Stone.WHITE else "黑",
		"通过 ✓" if c_ai else "失败 ✗"])
	# 玩家再停一手 ⇒ 连续两次 ⇒ 终局；两手停一手都必须同时在栈和谱里
	# （缺一手 = 复盘重放与悔棋回滚都会错位）
	_apply_pass()
	var rm2: Array = _record.get("moves", []) as Array
	var c_end: bool = (game_over and passes >= 2 and _hist.size() >= 2 and rm2.size() >= 2
		and int(_hist[_hist.size() - 2].get("tile", 0)) == -1
		and int(_hist[_hist.size() - 1].get("tile", 0)) == -1
		and int((rm2[rm2.size() - 2] as Dictionary).get("tile", 0)) == -1
		and int((rm2[rm2.size() - 1] as Dictionary).get("tile", 0)) == -1)
	if not c_end:
		ok = false
	print("[自检] 双方连停终局：game_over=%s passes=%d｜栈末两手 tile=%d,%d｜谱末两手 tile=%d,%d → %s" % [
		game_over, passes,
		int(_hist[_hist.size() - 2].get("tile", 0)) if _hist.size() >= 2 else -9,
		int(_hist[_hist.size() - 1].get("tile", 0)) if not _hist.is_empty() else -9,
		int((rm2[rm2.size() - 2] as Dictionary).get("tile", 0)) if rm2.size() >= 2 else -9,
		int((rm2[rm2.size() - 1] as Dictionary).get("tile", 0)) if not rm2.is_empty() else -9,
		"通过 ✓" if c_end else "失败 ✗"])
	print("[自检] 结果：", "通过 ✓（本地停一手不触发 AI；AI 停一手入账 + 桥 parity 不变量成立）" if ok else "失败 ✗")
	# 自检必须自己退出：少了这一句，场景会一直空跑，harness 只能等超时
	# （表现为 exit=124，日志明明「通过」却要白白烧掉整个 timeout）
	get_tree().quit()

## 根据菜单选择的棋盘大小设定生成参数
## 应用菜单设置页选定的配色。立方体三面由瓷砖主色派生，保持「同一立方体明暗三面」的错觉
func _apply_appearance() -> void:
	GameConfig.load_appearance()
	# ★ 底色走 `GameConfig.page_surface()` 这个**唯一真源**：`_style_game_button()` 给 HUD 按钮算
	#   "要从哪张面上浮出来"时读的是同一个函数 ⇒ 两者不可能各算一遍后分叉
	#   （旧写法在这儿写 `bg_color * bg_brightness`，与其它两处重复，见该函数的注）。
	background_color = GameConfig.page_surface()
	fat_color = GameConfig.tile_color_a
	thin_color = GameConfig.tile_color_b
	line_color = GameConfig.line_color
	board_tile_color = GameConfig.board_color   # 棋盘颜色随主题（宣纸=木黄 / 玄石=石板灰…）
	# ★ 棋子色也是**主题的一部分**（2026-10-08 起）：霓虹/赛博这类主题的棋盘是深底，
	#   必须配荧光子 —— 棋盘色与棋子色是**一对**，在 `GameConfig.apply_preset()` 里同一处写入。
	#   ⚠️ 这会**覆盖**在检查器里临时改的棋子色（每次应用外观都重设）。刻意如此：主题说了算；
	#     想在本次运行里临时改，改完别再去点主题即可（重开游戏也会回到主题设定）。
	#   ★ 默认主题（宣纸）不带 `stone_*` ⇒ 取到的是默认黑白 ⇒ **对既有观感零变化**。
	piece_color_black = GameConfig.stone_color_black
	piece_color_white = GameConfig.stone_color_white
	# ⚰️ 2026-10-17 墓碑（名字不许回收）：这里原有 `cube_face_light` / `cube_face_dark`
	#   两个 @export 的赋值。它们**从来没有读者**（`_draw()` 的立方体只用 `cube_face_mid`，
	#   见 11038 那条"兼容联机快照"注释）⇒ 声明与赋值一并删除（铁律 §33 死参数）。
	cube_face_mid = GameConfig.cube_mid()
	queue_redraw()

## 对局场景里"浮在页面底色上"的按钮（HUD 那一簇）套主题色样式。
## ★ 表面取 `GameConfig.page_surface()` —— 与 `_apply_appearance()` 写给 `background_color`、
##   以及 `_draw()` 里 `draw_rect(...)` 铺的是**同一个值**（2026-10-15 收纳成一处，
##   此前这个乘积在三个文件里各写了一遍）。
## ★★ 内边距用**紧档**（`BTN_PAD_TIGHT`）：HUD 是"贴右下角的一行五个按钮"，
##   而横屏实际能腾出来的宽度**是个紧预算** —— 逐档实测（2026-10-15，`--portraittest`）：
##     引擎默认 305px ✓ / 紧档 315px ✓ / 紧凑档 345px ✗（末位「返回菜单」出屏 40px）/ 页面档 435px ✗
##   ⇒ 只有紧档及以下塞得进。缺的从来不是"主题色"，而是那点内边距（内边距是**布局量**）。
##   ⚠️ 2026-10-16 口径更新：那个预算**不再是某个常量**。原先是 `hud_landscape_right = 320`
##     （已删，见 `game_config.gd` 墓碑）硬定"右边缘留 320"；现在 `_refit_hud()` 横屏分支
##     用 `get_combined_minimum_size()` **实测**这一行要多宽，再按 `hud_landscape_margin`
##     （= `UITokens.BOARD_MARGIN_LANDSCAPE`，32）贴右下角 ⇒ 行宽自适应、边距独立成量。
##     上面的 305/315/345/435 仍是有效的"档位排序"记录，但它们现在决定的是"这一行多宽"
##     而不是"塞不塞得进常量"。
##   ⚠️ 这个坑由 `--portraittest` ⑤b（横屏档按钮不得出屏）+ ⑤c（四边留白 ≥ 32）钉着；改这里务必重跑。
func _style_game_button(btn: Button) -> void:
	GameConfig.style_theme_button(btn, GameConfig.page_surface(), GameConfig.BTN_PAD_TIGHT)

## 复盘工具条那块底板的**唯一真源**：面板底色与"六个按钮浮在它上面"的调色板入参都读它。
## ★ 口径仍是"**跟随主题、但恒为深色**"：`overlay_surface()` 保证明度 ≤ `PANEL_LUM_MAX`
##   并去掉大半饱和度 ⇒ 压在任意配色的棋盘上都能分辨（旧实现是写死的深蓝灰，
##   与"界面其余部分都跟主题"直接冲突 —— 用户口令「没有用上主题色」的那一家）。
## ★ 留 0.9 的透明度：它是**浮动**在棋局上的工具条，全不透明等于把底下的棋子挖掉一块。
func _replay_surface() -> Color:
	var s: Color = GameConfig.overlay_surface()
	s.a = 0.9
	return s

## 自检（--apprt）：进对局后立刻返回菜单（菜单侧在等这一趟）。
## ★ 必须等 `Transition.is_busy()` 归假：本函数是从 `_ready()` 里调的，那一刻上一次转场
##   （菜单 → 对局）还没走完，此时 `change_scene()` 会被**静默丢弃**（实测空跑到超时）。
func _apprt_back_to_menu() -> void:
	while Transition.is_busy():
		await get_tree().process_frame
	Transition.change_scene("res://menu.tscn")

func _apply_board_size(size_id: int) -> void:
	# 立方体盘：环数（随机 → 由生成器按目标格数生长、这里只占位 / 标准 4 / 加强 6）
	# → 61/127 个六边形 → 183/381 落子格；随机档的 _cube_hex_r 在生成后回填为实际环数
	match size_id:
		GameConfig.RANDOM: _cube_hex_r = 0
		GameConfig.ENHANCED: _cube_hex_r = 6
		_: _cube_hex_r = 4
	# 筝形盘：正六边形**环数 R**（迷你 2 / 标准 3 / 加强 4）
	# → 正六边形选区在三角形级取样：R=2 → 24 个三角形 / 72 落子格；
	#   R=3 → 54 / 162；R=4 → 96 / 288。边界是严格正六边形（六条边各 R 条单位边）。
	# 筝形无随机档：全局 RANDOM 槽位在筝形下即「迷你」固定盘（菜单槽位 0 显示「迷你」）。
	match size_id:
		GameConfig.RANDOM: _kite_r_actual = 2
		GameConfig.ENHANCED: _kite_r_actual = 4
		_: _kite_r_actual = 3
	# 雪花盘：**层数 n**（octagrid 圆窗半径 R = 0.75n）。
	# 实测格数阶梯：n=3→72（迷你）/ n=5→200（标准）/ n=6→296（加强）。
	# 雪花 2026-09-16 起**有随机档**：RANDOM 槽位下 _snow_r_actual 不参与生成
	#（半径由目标格数现算，见 _generate_snowflake_random），这里的值只作占位。
	match size_id:
		GameConfig.RANDOM: _snow_r_actual = 3
		GameConfig.ENHANCED: _snow_r_actual = 6
		_: _snow_r_actual = 5
	# 爱因斯坦盘（帽子家族）：**没有可连续调节的几何参数**（盘 = 池 + BFS 收 N 片），所以「尺寸档」
	# 直接就是目标落子格数：标准 hat_std_tiles（150）/ 加强 hat_big_tiles（310）；随机档用
	# 爱因斯坦专用的 hat_rand_tiles ± random_tile_jitter（默认 270±12，2026-09-20 用户口径
	# 「三种类随机盘 240~300 格」，与其它盘共用的 random_target_tiles 分开）。
	# ★ 2026-09-19 起菜单里**爱因斯坦这个槽位不再出尺寸行**，那一行改成选种类（帽子/海龟/幽灵），
	#   且三种类都走随机档（用户口径：「都是随机约200格」）→ 菜单永远只写 board_size = RANDOM。
	#   标准/加强两档在代码里保留，只留给自检（--hattest ④ 的确定性盘）与命令行截图用。
	match size_id:
		GameConfig.RANDOM: _hat_target = hat_rand_tiles
		GameConfig.ENHANCED: _hat_target = hat_big_tiles
		_: _hat_target = hat_std_tiles
	match size_id:
		GameConfig.RANDOM:
			# 随机档：先铺出一张足够大的密铺（迭代 5、不裁剪），
			# 真正取哪一扇窗口由 _generate_penrose_random() 按目标格数现算（见 random_target_tiles）
			iterations = 5
			clip_radius = 1.05
		GameConfig.ENHANCED:
			iterations = 5
			clip_radius = 0.88   # 约 360 落子格 / 401 顶点
		_:  # STANDARD or unknown
			iterations = 4
			clip_radius = 0.82   # 约 120 落子格 / 141 顶点
	use_circle_clip = true
	var head_txt := _board_size_name(size_id)
	if GameConfig.board_type == GameConfig.BOARD_CUBE:
		head_txt = "立方体 " + (str(_cube_hex_r) + " 环" if _cube_hex_r > 0 else "随机") + "（" + _board_size_name(size_id) + "）"
	elif GameConfig.board_type == GameConfig.BOARD_KITE:
		head_txt = "筝形 " + str(_kite_r_actual) + " 环（" + _board_size_name(size_id) + "）"
	elif GameConfig.board_type == GameConfig.BOARD_SNOWFLAKE:
		# 随机档没有「层数」这个概念（半径由目标格数现算）→ 直接写「随机」
		head_txt = ("雪花 随机（" + _board_size_name(size_id) + "）" if size_id == GameConfig.RANDOM
			else "雪花 " + str(_snow_r_actual) + " 层（" + _board_size_name(size_id) + "）")
	elif GameConfig.board_type == GameConfig.BOARD_HAT:
		# 「爱因斯坦」大类 = 帽子家族三档（帽子 / 海龟 / 幽灵）→ 横幅必须带上种类名，
		# 否则「同一张盘换个种类」在日志里完全看不出来。
		# 随机档的格数由 random_target_tiles 现算 → 直接写目标值，不写死格数。
		var hk: String = _hat_kind_name(GameConfig.hat_kind)
		head_txt = ("爱因斯坦·" + hk + " 随机 ~" + str(hat_rand_tiles) + " 格"
			if size_id == GameConfig.RANDOM
			else "爱因斯坦·" + hk + " " + str(_hat_target) + " 格（" + _board_size_name(size_id) + "）")
	print("棋盘：", head_txt, " | 迭代：", iterations, " | 裁剪半径：", clip_radius)

func _board_size_name(size_id: int) -> String:
	if size_id == GameConfig.RANDOM:
		# 只剩筝形盘没有随机档：全局 RANDOM 槽位在它下面是「迷你」固定盘
		#（雪花 2026-09-16、帽子 2026-09-19 起都有真随机档 → 不能再算进「迷你」）
		return "迷你" if GameConfig.board_type == GameConfig.BOARD_KITE else "随机"
	if size_id == GameConfig.ENHANCED:
		return "加强"
	return "标准"

func _capture_and_quit() -> void:
	await get_tree().create_timer(2.0).timeout
	# ★ 再确认开场淡入（0.5s 黑→透明）真的结束了：2s 等待目前够，但这条不变量不能靠"够长"
	#   （短了整张图会被均匀压暗 —— 实测菜单侧就是这么被压暗 8% 的，量对比度直接失真）。
	var fw := 0.0
	while Transition.cover_alpha() > 0.01 and fw < 1.5:
		await get_tree().create_timer(0.05).timeout
		fw += 0.05
	await RenderingServer.frame_post_draw
	# 打印真实几何：截图审外观/审"窗口有没有居中"时都要拿它对照
	#（居中 = 窗口位置 == 屏幕位置 + (屏幕尺寸 − 窗口尺寸)/2；多屏时屏幕取当前屏）
	var scr: int = DisplayServer.window_get_current_screen()
	print("[shot] 视口=%s 窗口=%s 位置=%s 屏幕位置=%s 屏幕尺寸=%s 可用区=%s 模式=%d" % [
		str(get_viewport_rect().size), str(DisplayServer.window_get_size()),
		str(DisplayServer.window_get_position()), str(DisplayServer.screen_get_position(scr)),
		str(DisplayServer.screen_get_size(scr)), str(GameConfig.screen_usable_rect()),
		DisplayServer.window_get_mode()])
	# 「窗口有没有居中」只看数字容易看漏（偏 24px 肉眼就是"看着别扭"）→ 直接出判据。
	# ★ 基准是**可用区**（去掉任务栏），不是整屏 —— 见 GameConfig.screen_usable_rect()
	print("[shot] 窗口居中 = %s（偏差=%s；基准=可用区）" % [
		GameConfig.window_center_verdict(), str(GameConfig.window_center_delta())])
	# 画布基座：审"竖屏/横屏"截图时必须知道这张图是哪个基座下截的，
	# 否则「UI 怎么变大了」会被当成渲染 bug（其实是单位从 1152 换成了 720）。
	print("[shot] %s" % GameConfig.canvas_verdict())
	# HUD 的真实矩形：竖屏 HUD 改版后"按钮够不够大、有没有出屏"必须**量**，不能看图猜
	print("[shot] HUD %s" % hud_layout_verdict())
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var p := "user://debug_board.png"
		var ok: int = img.save_png(p)
		print("截图保存 ok=", ok, " path=", ProjectSettings.globalize_path(p))
	else:
		print("截图失败：image 为空")
	get_tree().quit()

# ====== 侧抽屉几何（2026-10-21，唯一真源）======
## 用户原话：「严防重叠，把对局棋盘左右空白做成抽屉，左边放玩家信息及表情等，
## 右边放对局按键，还能折叠收回屏幕侧边」。
##
## ★★ 为什么"严防重叠"只能靠几何，不能靠调 UI 坐标：
##   本轮之前棋盘是在**整个视口**里居中缩放的（`_adapt_to_screen()` 只扣 `board_margin()`），
##   而 HUD / 身份槽是被"摆到棋盘四角的空白处"的 —— 那是**目测出来的巧合**：密铺盘的四角
##   本来就是空的，所以 196×56 的小槽浮上去不打架。可窗口一窄、换一张盘、HUD 多一个按钮，
##   巧合就破了，而且**破了不会有任何报错**（两者都"可见"）。
##   ⇒ 本节的唯一职责：给"棋盘能用哪块矩形"一个**唯一的**答案 `board_area()`，
##     让棋盘先在扣掉两侧抽屉的矩形里缩放。抽屉占宽一变 ⇒ 棋盘跟着重算，
##     "压到棋盘上"在**结构上**不可能发生（而不是"这一版调得刚好不压"）。
##
## ★ 全部函数都是**纯几何**：只读 `game_mode` / 两个开合开关 / 视口尺寸 / `GameConfig`，
##   不读任何节点。所以 `_adapt_to_screen()` 在 `_build_game_hud()` **之前**跑也拿得到正确值
##   （`_ready()` 里正是这个顺序：492 行定 mode → 532 行缩放 → 541 行建 HUD），
##   不会出现"棋盘先按老几何缩一次、建完 UI 再跳一下"。
##
## ★ 三层闸门，各管一件事，**不许合并**：
##   ① `_drawer_available()` —— 这一侧**有没有内容**（左抽屉只在联机态存在）；
##   ② `_drawer_cramped()`   —— 视口**够不够宽**（不够就退化成浮层，不挤棋盘）；
##   ③ `_drawer_wants_open()`—— **用户**点没点开。
##   面板"画不画"（`_drawer_shows()`）与"占多宽"（`_drawer_band()`）是**两个**函数。
##   ★ 2026-10-22 起 `_drawer_band()` **不读开合**（用户口令「棋盘固定在中心不要动」）：
##     它恒按"抽屉展开时该占多少"算，折叠只影响 `_drawer_shows()` 与面板贴哪条边。

## 抽屉宽度（逻辑像素）。左右取同一个值：内容宽 172 = 3 个 52px 表情格 + 2 个 8px 间隙。
const DRAWER_W_LEFT: float = 200.0
const DRAWER_W_RIGHT: float = 200.0
## 折叠状态只剩一条贴边的把手 —— 把手就是"抽屉缩回侧边"的那条边。
const DRAWER_HANDLE_W: float = 18.0
const DRAWER_HANDLE_H: float = 96.0
## 面板底 → 内容的内边距。
## ★ 取 14：面板圆角 10 + 描边 1 ⇒ 内容离面板边 14 才不会压进圆角里（另一侧对着把手留白）。
## ⚰️ 2026-10-22 墓碑：这个常量的取值理由原本是"面板底吃 `style_dialog_panel()` 那套，
##   描边内侧还有 ~18px 的 content margin"。抽屉底色改成同深浅的自拼 StyleBox 之后
##   content margin 已定为 0（见 `_drawer_stylebox()`）⇒ 那半句不再成立，取值本身不变。
const DRAWER_PAD: float = 14.0
## 视口窄到"两侧都展开就挤不出这么宽的棋盘" ⇒ 退化成浮层（面板浮在盘上，不挤棋盘）。
## 取 380：标准盘在 1152 基准视口下本来就有 600+，380 已经小到落子点要挤在一起。
const DRAWER_MIN_BOARD_W: float = 380.0
## 抽屉底色 = 页面底朝 `ink` 方向混这一小步。
## ★ 用户口令「抽屉也用和背景较接近的颜色（同深浅）」⇒ 明度只挪 7%，靠 1px 淡描边界定边界。
## ★ 为什么朝 `ink` 而不是朝反方向：朝 ink 走 ⇒ "抽屉 vs 页面"只会更分得开，画在上面的
##   字（`readable_ink_on(抽屉面)`）对比度只可能变高、不可能因这次改色而变差。
##   朝反方向（提亮）会让浅底主题上的白字掉进 §130 那个明度死区。
const DRAWER_SURFACE_MIX: float = 0.07

## 这一侧**有没有内容**。左抽屉只有联机内容（双方头像 + 表情）⇒ 单机/人机档连把手都不出现
## （否则玩家会去点一条点了没反应的边）。
func _drawer_available(side: int) -> bool:
	if side == 0:
		return game_mode == ONLINE
	return true


func _drawer_width(side: int) -> float:
	return DRAWER_W_LEFT if side == 0 else DRAWER_W_RIGHT


## 用户想要的展开态。**不**含"视口太窄"那条派生（见 `_drawer_cramped()`）。
func _drawer_wants_open(side: int) -> bool:
	return _drawer_left_open if side == 0 else _drawer_right_open


## 视口放不下两条侧栏 ⇒ 抽屉退化成**浮层**。纯函数（只读视口 + 配置 + 盘边距），
## 不读 `_drawer_*_open` ⇒ 它自己不会跟"用户开合"互相递归（那会变成 no-op 死循环）。
## ★ 竖屏一律算"放不下"：盘在竖屏只能靠宽度吃饭，两条侧栏一定把盘挤没。
## ★★ 2026-10-22 改：`need` **两侧恒算**（原来只在 `game_mode == ONLINE` 时加左侧）。
##   棋盘现在恒居中于窗口（见 `_drawer_band()`），左右**必须**一起预留 ⇒ 判定也必须一起算，
##   否则单机窄窗下会"以为还宽"（少算 200）从而不退化，盘被挤到 380 以下还不报红。
func _drawer_cramped() -> bool:
	if GameConfig.use_portrait_canvas():
		return true
	var vs := get_viewport_rect().size
	var need: float = 2.0 * GameConfig.hud_landscape_margin \
			+ _drawer_width(0) + _drawer_width(1)
	var m: float = GameConfig.board_margin() + (board_panel_pad if board_panel_enabled else 0.0)
	return vs.x - need - 2.0 * m < DRAWER_MIN_BOARD_W


## 抽屉**真的展开**了吗（面板嵌在版面里、内容完整可见）。
## ★ 2026-10-22 起它**不再影响棋盘**：棋盘按 `_drawer_band()` 永久让位（口径与开合无关）。
##   它现在只管两件事 —— 面板贴屏幕边还是贴边距（`_drawer_rect()`）、把手在内侧还是外侧。
func _drawer_expanded(side: int) -> bool:
	if not _drawer_available(side):
		return false
	if _drawer_cramped():
		return false
	return _drawer_wants_open(side)


## 面板**画不画**。与 `_drawer_expanded()` 的差别只有一处 —— 浮层态下用户点开也画，
## 只是不占宽度。★ 两者分开是这一节的关键：合并成一个函数的话，
## "浮层时挤棋盘"与"浮层时不显示"必居其一，两种都错。
func _drawer_shows(side: int) -> bool:
	if not _drawer_available(side):
		return false
	return _drawer_wants_open(side)


## 某一侧**占掉的横向带宽**。`board_area()` 读它 —— 所以它就是"严防重叠"的那个数。
##
## ## ★★ 2026-10-22 改：**不再读用户开合**（用户口令「棋盘固定在中心不要动」）
## 上一版按 `_drawer_expanded(side)` 分两档（展开 250 / 折叠 18）⇒ 每点一次把手，棋盘都跟着
## 缩放重排一遍。用户看到的正是"点一下抽屉，整盘棋跳一下"。
## 现在的口径 = **棋盘尺寸恒为"全部抽屉都展开"时的尺寸**：
##   · 非 cramped：`边距 + 面板 + 把手` —— 够放两条 200 面板 + 把手，且与开合**无关**；
##   · cramped（视口放不下 ⇒ 浮层）：只让出把手宽，面板浮在盘上方（那一档本来就承认重叠）。
## 两个分支都**不含**开合状态 ⇒ `board_area()` 在会话内只随视口尺寸变。
## 折叠 = "面板与内容不再画出来 + 左右多出空白"，棋盘纹丝不动。
##
## ## ★★ 2026-10-22 第二条口令：**也不再读 `_drawer_available()`**
## 用户：「本地和人机模式棋盘也要放在正中间」。原来左抽屉只在联机态存在 ⇒ 单机态带宽是
## `(0, 250)` ⇒ `board_area()` 的中心比窗口中心偏左 **125px**，盘整体左移。
## 现在两侧**恒等预留** ⇒ `board_area()` 恒以窗口中线对称 ⇒ **棋盘永远在正中间**，
## 与模式、与开合全都无关。
## ★ 代价：单机态左侧那 250 是**纯留白**（那里没有抽屉内容）。这是"恒居中"的直接后果 ——
##   想在左边放东西（例如单机也显示双方身份），是另一件事，不在几何里决定。
## ★ 代价（用户已知并选择）：折叠**拿不回**空间。想拿回就得让棋盘动，两者互斥。
func _drawer_band(side: int) -> float:
	# 浮层态：面板贴屏幕边浮在盘上，只有把手是需要让位的（它必须能点到，不许压在盘上）。
	if _drawer_cramped():
		return DRAWER_HANDLE_W * _drawer_band_ratio
	return (GameConfig.hud_landscape_margin + _drawer_width(side) + DRAWER_HANDLE_W) \
			* _drawer_band_ratio


func drawer_bands() -> Vector2:
	return Vector2(_drawer_band(0), _drawer_band(1))


## 棋盘可以用的矩形 —— **全工程唯一真源**。`_adapt_to_screen()` 在这里面居中缩放。
func board_area() -> Rect2:
	var vs := get_viewport_rect().size
	var bands := drawer_bands()
	var margin: float = GameConfig.board_margin() + (board_panel_pad if board_panel_enabled else 0.0)
	return Rect2(bands.x + margin, margin,
			maxf(vs.x - bands.x - bands.y - 2.0 * margin, 1.0),
			maxf(vs.y - 2.0 * margin, 1.0))


## 抽屉**面板**的屏幕矩形。整条通高（从 `hud_landscape_margin` 到同距离的底），
## 所以它永远完整落在视口内，且高度不依赖内容（不读节点 ⇒ 仍是纯几何）。
func _drawer_rect(side: int) -> Rect2:
	var vs := get_viewport_rect().size
	if not _drawer_available(side):
		return Rect2(0.0, 0.0, 0.0, 0.0)
	var w: float = _drawer_width(side)
	var m: float = GameConfig.hud_landscape_margin
	var x: float = m if side == 0 else vs.x - m - w
	if not _drawer_expanded(side):
		# 浮层态：贴屏幕边，不占版面（band 仍是把手宽 —— 它就盖在盘上，收起即消失）。
		x = 0.0 if side == 0 else vs.x - w
	return Rect2(x, m, w, maxf(vs.y - 2.0 * m, 0.0))


## 抽屉内容区（面板底扣掉内边距）。`_hud_box` / 身份槽 / 表情格都往这里摆。
func drawer_content_rect(side: int) -> Rect2:
	var r := _drawer_rect(side)
	if r.size.x <= 2.0 * DRAWER_PAD or r.size.y <= 2.0 * DRAWER_PAD:
		return r
	return r.grow(-DRAWER_PAD)


## 把手的屏幕矩形。展开时贴在面板**内侧**（panel 与棋盘之间），
## 折叠/浮层时贴屏幕边 —— 两种位置都在 `_drawer_band()` 让出来的范围里，不会压盘。
func _drawer_handle_rect(side: int) -> Rect2:
	var vs := get_viewport_rect().size
	if not _drawer_available(side):
		return Rect2(0.0, 0.0, 0.0, 0.0)
	var hh: float = minf(DRAWER_HANDLE_H, vs.y)
	var y: float = (vs.y - hh) * 0.5
	if not _drawer_expanded(side):
		return Rect2(0.0 if side == 0 else vs.x - DRAWER_HANDLE_W, y,
				DRAWER_HANDLE_W, hh)
	var pr := _drawer_rect(side)
	var hx: float = pr.end.x if side == 0 else pr.position.x - DRAWER_HANDLE_W
	return Rect2(hx, y, DRAWER_HANDLE_W, hh)


## 翻一侧的抽屉。★ 只改"用户意图"那一个布尔，摆位交给 `_refit_hud()` ——
## 在这里顺手摆一次的话，窗口尺寸一变就有两处各摆一份（铁律 8）。
## ★ 2026-10-22：棋盘**不再为开合重算**（`_drawer_band()` 已与开合脱钩）。
##   `_refit_drawers()` 里那句 `_adapt_to_screen()` 保留 —— 它是自归一的，跑一遍结果不变，
##   但少了它就漏掉了"`game_mode` 中途变联机"那条路径（见那里的注释）。
func _toggle_drawer(side: int) -> void:
	if not _drawer_available(side):
		return
	if side == 0:
		_drawer_left_open = not _drawer_left_open
	else:
		_drawer_right_open = not _drawer_right_open
	# 只翻"用户意图"，摆位与棋盘重算全交给 `_refit_hud()`（→ `_refit_drawers()` → `_adapt_to_screen()`）。
	# ★ 这里**不**再顺手调一次 `_adapt_to_screen()`：那会让"棋盘怎么缩"多出第二个写入口，
	#   而窗口尺寸变化走的是另一条路（`size_changed` → `_refit_hud`）⇒ 迟早只改一处。
	_refit_hud()


func _on_drawer_handle_pressed(side: int) -> void:
	_toggle_drawer(side)


# ====== 自适应窗口 ======
func _adapt_to_screen():
	if vertices.size() == 0:
		return
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for v in vertices:
		if v.x < min_x: min_x = v.x
		if v.x > max_x: max_x = v.x
		if v.y < min_y: min_y = v.y
		if v.y > max_y: max_y = v.y
	var size_x: float = max_x - min_x
	var size_y: float = max_y - min_y
	# 边距走 GameConfig：横 40 / 竖 14（竖屏下棋盘瓶颈恒是宽度，省下的边距直接变成格子面积）
	# ★★ 盘的**外扩量必须算进边距**：`_adapt_to_screen()` 缩放的是**棋盘顶点**，而盘还要往外长
	#   `board_panel_pad` —— 只按 `board_margin()` 缩放，盘就会吃掉那 40px 边距、几乎贴到窗口边
	#   （实测加盘后上下只剩 11 物理像素，用户报「棋盘大小有点超出窗口了」）。
	#   计入之后 ⇒ **盘距窗口恒为 `board_margin()`，与 pad 取值无关**；代价是棋盘比原来小 2×pad，
	#   换来的是"改 pad 不会把盘顶出窗口"这条结构性保证，而不是靠默认值凑巧合适。
	# ★ 盘关掉时（`board_panel_enabled = false`）退回原口径，逐像素与加盘之前一致。
	# ★★ 2026-10-21：这一行**保留在注释里而不是代码里** —— 边距的真源已经搬进 `board_area()`
	#   （见那里），这里再算一遍就是"同一个公式两处各写一份"，迟早只改一处。
	#   `board_area()` 用的正是 `GameConfig.board_margin() + board_panel_pad`，语义完全一样。
	# ★★ 2026-10-21 改：不再在**整个视口**里居中，而是在 `board_area()`（已扣掉两侧抽屉）里
	#   居中缩放。`board_area()` 自己已经扣过边距，所以这里直接把它的 `size` 喂给缩放比、
	#   把它的 `center` 当落点（§111 同一公式只许一处）。
	#   ★ 抽屉全折叠时结果与改前**逐像素一致**：`Rect2(0+m, m, vs.x-2m, vs.y-2m)` 的中心
	#     就是 `vs/2`、宽高就是 `vs-2m`。这条退化保证拿来验"没抽屉时我没改坏"
	#     （`--drawertest` ② 就是把两条抽屉都关掉、与旧公式对拍）。
	var area: Rect2 = board_area()
	var scale_factor: float = min(area.size.x / size_x, area.size.y / size_y)
	var center: Vector2 = Vector2((min_x + max_x) / 2, (min_y + max_y) / 2)
	var target: Vector2 = area.get_center()
	for i in range(vertices.size()):
		vertices[i] = (vertices[i] - center) * scale_factor + target
	_compute_tile_metrics()
	_rebuild_edge_map()   # 几何定稿后重建共享边映射（所有生成/快照路径都经此处）
	_fit_click_area()     # ★ 让「可点区域」跟着棋盘走（见下），否则窗口一变比例边缘格子就点不动

## 把 `click_area`（落子的物理拾取区）摆到**棋盘包围盒**上，四边各留 `pad` 余量。
##
## ⚠️ 原来的写法是**写死** `RectangleShape2D.size = 2000×2000` 且 Area2D 在原点 ——
##    可点范围恒为 x,y ∈ [-1000, 1000]。而棋盘是**按视口居中并放大**的：
##    `_adapt_to_screen()` 只用 40px 边距，于是棋盘盒右（下）边界最大可到 `视口-40`。
##    只要视口宽（或高）超过 1040，边缘瓷砖就会跑到这个方框**外面** → 那部分区域的
##    物理拾取**收不到事件**，点了既不落子也不报"已有子/自杀"——**完全静默**。
##    实测（窗口→逻辑视口→越界格数）：1152×720→0、1920×1080→0（16:9 与拉伸基准等比，
##    侥幸不越界）、2560×1080→**6 格**（21:9 超宽屏）、1152×1152→**21 格**（方/高窗）。
##    症状就是用户报的「右侧边缘空格无法落子」。
##
## 修法：不再写死尺寸，而是按当前几何**贴合**棋盘（几何是唯一真源，窗口怎么变都对）。
func _fit_click_area() -> void:
	if click_area == null or vertices.size() == 0:
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in vertices:
		mn.x = minf(mn.x, v.x)
		mn.y = minf(mn.y, v.y)
		mx.x = maxf(mx.x, v.x)
		mx.y = maxf(mx.y, v.y)
	var pad := 80.0
	var box := Rect2(mn - Vector2(pad, pad), (mx - mn) + Vector2(pad * 2.0, pad * 2.0))
	click_area.position = box.get_center()
	for ch in click_area.get_children():
		if ch is CollisionShape2D and (ch as CollisionShape2D).shape is RectangleShape2D:
			((ch as CollisionShape2D).shape as RectangleShape2D).size = box.size

# ====== 落子格（瓷砖）几何度量 ======
## 瓷砖中心与内切半径。须在 _adapt_to_screen() 缩放之后调用（坐标已是像素）。
## 用「顶点平均」当中心、「r = 2A / P」当内切半径（A=面积 P=周长）。
## 四边形下与旧版逐位一致；n 边形（帽子盘）同样成立。
func _compute_tile_metrics() -> void:
	tile_centers.resize(tiles.size())
	tile_r.resize(tiles.size())
	_min_tile_r = INF
	for i in range(tiles.size()):
		var vs: Array = tiles[i]
		var n: int = vs.size()
		var c := Vector2.ZERO
		for idx in vs:
			c += vertices[idx]
		c /= float(maxi(n, 1))        # n 边形通用（帽子盘是 13 边形）
		tile_centers[i] = c
		var peri := 0.0
		var cross_sum := 0.0
		for k in range(n):
			var p1: Vector2 = vertices[vs[k]]
			var p2: Vector2 = vertices[vs[(k + 1) % n]]
			peri += p1.distance_to(p2)
			cross_sum += p1.cross(p2)
		var area: float = absf(cross_sum) * 0.5
		var r: float = 2.0 * area / maxf(peri, 1e-6)
		tile_r[i] = r
		if r < _min_tile_r:
			_min_tile_r = r
	# 盘的多边形与 tile_centers **同生命周期**（都由顶点像素坐标派生）⇒ 在这里一次算好
	_rebuild_board_panel()

## 共享边 → 邻接瓷砖 映射（纯几何，与坐标无关）。盘面生成 / 联机快照后在
## _adapt_to_screen() 里重建一次；_draw 每帧查表即可判断「相邻两块瓷砖是否同色棋子」。
## key = mini(a,b)*1000000 + maxi(a,b)（a/b 为边两端顶点索引）；值 = 邻居 tile_id，外边界为 -1。
func _rebuild_edge_map() -> void:
	_edge_neighbor.clear()
	for i in range(tiles.size()):
		var tvs: Array = tiles[i]
		var n := tvs.size()
		for k in n:
			var a: int = tvs[k]
			var b: int = tvs[(k + 1) % n]
			var key: int = mini(a, b) * 1000000 + maxi(a, b)
			if _edge_neighbor.has(key):
				continue   # 共享边已在邻居那边登记过
			var nb := -1
			for j in adjacency[i]:
				if j == i or j < 0 or j >= tiles.size():
					continue
				var ntvs: Array = tiles[j]
				if ntvs.has(a) and ntvs.has(b):
					nb = j
					break
			_edge_neighbor[key] = nb

## 统一棋子像素半径：以全盘最小内切圆为基准（瘦菱形约束最紧）
## 立方体盘用 cube_stone_scale（略小），保证棋子视觉上明确落在格子内部。
## （经典网格盘下线后，原本专用于它的 grid_stone_scale 一并移除。）
func _stone_px() -> float:
	if _min_tile_r == INF:
		return 0.0  # 棋盘尚未生成
	if _is_cube:
		return _min_tile_r * cube_stone_scale
	return _min_tile_r * stone_scale

## 鼠标点命中的瓷砖 id（点在瓷砖多边形内）；点空隙返回 -1
func _tile_at_point(p: Vector2) -> int:
	for i in range(tiles.size()):
		var poly := PackedVector2Array()
		for idx in tiles[i]:
			poly.append(vertices[idx])
		if Geometry2D.is_point_in_polygon(p, poly):
			return i
	return -1

# ====== 生成彭罗斯菱形镶嵌（Robinson 三角替换法）======
## 按棋盘类型分派。所有「生成/重建棋盘」的入口都走这里（_ready / 开新局），
## 免得各处重复 if/elif 之后漏掉某一种棋盘。
## ⚠️ 原先这里还有第三种「经典 19×19 网格盘（BOARD_GRID）」，已于 2026-09-15 下线
##（位置先验对它有系统性劣势且无处安放专门模型）；如今有彭罗斯 / 立方体 / 筝形三种。
func generate_board() -> void:
	# 按棋盘类型分派。所有「生成/重建棋盘」的入口都走这里（_ready / 开新局），
	# 免得各处重复 if/elif 之后漏掉某一种棋盘。
	# ⚠️ 原先这里还有第三种「经典 19×19 网格盘（BOARD_GRID）」，已于 2026-09-15 下线
	#（位置先验对它有系统性劣势且无处安放专门模型）；如今有彭罗斯 / 立方体 / 筝形三种。
	# 换盘 = 瓷砖索引全部换人：悬浮格必须作废（否则会画在「另一块砖」上，见 reset_game 同注）
	_hover_tile = -1
	match GameConfig.board_type:
		GameConfig.BOARD_CUBE:
			generate_cube()
		GameConfig.BOARD_KITE:
			generate_kite()
		GameConfig.BOARD_SNOWFLAKE:
			generate_snowflake()
		GameConfig.BOARD_HAT:
			generate_hat()
		_:
			generate_penrose()

## 是否走「随机」档：每局现场生成一张盘，格数≈random_target_tiles。
## 彭罗斯 / 立方体 / 雪花 / 帽子 有随机档（雪花自 2026-09-16、帽子自 2026-09-19 起）；
## 只剩筝形没有（RANDOM 槽位下是「迷你」固定盘）
## —— 这一处排除，让抽种子/启动横幅/重开重生成/调参滑条对它们全部自动走固定档逻辑。
func _is_random_board() -> bool:
	return GameConfig.board_size == GameConfig.RANDOM \
		and GameConfig.board_type != GameConfig.BOARD_KITE

## 抽一颗新的随机种子（非 0；0 留给「未指定 / 由对端下发」的语义）
func _fresh_seed() -> int:
	var s: int = randi() % 2147483647
	return s if s != 0 else 1

func generate_penrose() -> void:
	if _is_random_board():
		_generate_penrose_random()
		return
	vertices.clear()
	_is_cube = false
	_is_kite = false
	_is_snow = false
	_is_hat = false
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()

	# 1) Star 种子 + deflation 迭代
	var tris: Array = _build_seed_star()
	for i in range(iterations):
		tris = _deflate_all(tris)

	# 2) 配对菱形并重建顶点表
	var result: Dictionary = _build_rhombi(tris)
	var raw_verts: Array[Vector2] = result["verts"]
	var rhombi: Array = result["rhombi"]

	# 3) 圆形裁剪（去掉边缘不完整的菱形）
	if use_circle_clip:
		var clipped: Dictionary = _clip_rhombi(raw_verts, rhombi, clip_radius)
		raw_verts = clipped["verts"]
		rhombi = clipped["rhombi"]

	# 4) 转为本项目棋盘结构 —— 落子单元是“瓷砖”，不是顶点
	_assemble_tiles(raw_verts, rhombi)
	print("生成彭罗斯棋盘，顶点数: ", vertices.size(), "，瓷砖: ", tiles.size(), "（落子格）")
	find_tiles()  # 旧逻辑占位；几何生成已完成

## 菱形表 → 落子格结构（顶点表 / 环序 / 配色 / 邻接 / 空盘）。
## 固定盘与随机盘共用这一段，保证两条路径的数据结构完全一致（邻接也是同一套算法）。
func _assemble_tiles(raw_verts: Array[Vector2], rhombi: Array) -> void:
	vertices = raw_verts
	tiles.clear()
	tile_colors.clear()
	for r in rhombi:
		var tile := _sort_tile_by_angle(r["verts"])
		tiles.append(tile)
		tile_colors.append(thin_color if r["type"] == "thin" else fat_color)

	# 瓷砖邻接：共享整条边的两块瓷砖互为邻居（这就是围棋里的“气路”）
	adjacency.resize(tiles.size())
	for i in range(tiles.size()):
		adjacency[i] = []
	var edge_owners: Dictionary = {}
	for ti in range(tiles.size()):
		var vs: Array = tiles[ti]
		for k in range(4):
			var key: String = _edge_key(vs[k], vs[(k + 1) % 4])
			if not edge_owners.has(key):
				edge_owners[key] = []
			edge_owners[key].append(ti)
	for key in edge_owners:
		var owners: Array = edge_owners[key]
		if owners.size() == 2:
			adjacency[owners[0]].append(owners[1])
			adjacency[owners[1]].append(owners[0])

	# 落子格初始化：每块瓷砖一个可落子格
	board.clear()
	for i in range(tiles.size()):
		board[i] = Stone.EMPTY

## 「随机」档彭罗斯盘：**按密铺规则现造一张盘**（de Bruijn 五格网对偶，见 _pentagrid_rhombi），
## 而不是老办法「铺一张固定大密铺 → 随机开一扇圆形窗口切范围」。
##
## 老办法的病根：素材永远是同一张 5 代车轮密铺，每局只是窗口位置不同 ——
## 局部拼花（五角星/船/太阳）完全一样，玩家多开几局就能看出「都是同一张图」。
##
## 随机源升级为五格网的 5 个随机相位：每组 γ 通过对偶生成一张**结构全新**的合法 P3 密铺，
## 花纹全局随机。圆形窗口仍然保留，但只负责「取景 + 凑格数」：
## 完整密铺的格数由「种子×代数」决定，是离散的（车轮 4 代=120、5 代≈310），凑不出可调的 200±jitter；
## 而圆形取景切出近圆凸区域，下起来才像一张棋盘（随机生长会拖出触手，边角气异常少）。
func _generate_penrose_random() -> void:
	vertices.clear()
	_is_cube = false
	_is_kite = false
	_is_snow = false
	_is_hat = false
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = _rand_seed
	var target: int = maxi(20, random_target_tiles + rng.randi_range(-random_tile_jitter, random_tile_jitter))
	_rand_target = target

	# 5 个随机相位 = 一张全新密铺；同一 _rand_seed 必复现同一张盘
	#（和条件 Σγ ≡ 0 mod 1 见 _random_gammas，守住真·彭罗斯 LI 类）
	var gammas: Array = _random_gammas(rng)

	var wc := Vector2.ZERO
	var radius := _fit_pentagrid_radius(gammas, wc, target)
	var result: Dictionary = _pentagrid_rhombi(gammas, wc, radius)
	_assemble_tiles(result["verts"], result["rhombi"])
	var dropped := _prune_to_largest_component()
	print("生成随机彭罗斯棋盘（五格网） 种子=", _rand_seed, " 目标=", target, " 实际=", tiles.size(),
		" 落子格（半径=", snappedf(radius, 0.01), " 剔掉孤块=", dropped, "）顶点数: ", vertices.size())

## 自检（--pentest）：五格网生成器的数学健全性 —— 它是「随机」档的素材来源，
## 几何错了整档棋盘全废，所以单独断言到数学量上：
##  ① 胖瘦比 ≈ φ（P3 密铺的标志量）：胖瘦判定写反、退化处理错漏时立刻暴露
##  ② 无重叠：任何一条边不允许被 ≥3 块菱形共享（菱形交叠的拓扑特征）
##  ③ 复现：同相位两次生成结果完全一致（联机由房主下发种子，依赖这一点）
##  ④ 走完整随机档装配路径后，格数与目标偏差 ≤2（二分收敛）
func _pentagrid_self_test() -> void:
	var ok := true
	var phi := 1.6180339887
	for s in 3:
		_rand_seed = 1000 + s * 7919
		var rng := RandomNumberGenerator.new()
		rng.seed = _rand_seed
		var gammas: Array = _random_gammas(rng)
		var res: Dictionary = _pentagrid_rhombi(gammas, Vector2.ZERO, 9.0)
		var verts: Array[Vector2] = res["verts"]
		var rhombi: Array = res["rhombi"]
		var fat := 0
		for r in rhombi:
			if r["type"] == "fat":
				fat += 1
		var thin: int = rhombi.size() - fat
		var ratio: float = float(fat) / float(maxi(thin, 1))
		if thin == 0 or absf(ratio - phi) > 0.1:
			ok = false
		# ② 无重叠：一条边至多被 2 块菱形共享（内部边=2，边界边=1）
		var edge_count: Dictionary = {}
		for r in rhombi:
			var vs: Array = r["verts"]
			for k in 4:
				var key: String = _edge_key(vs[k], vs[(k + 1) % 4])
				edge_count[key] = int(edge_count.get(key, 0)) + 1
		var over := 0
		for key in edge_count:
			if int(edge_count[key]) > 2:
				over += 1
		if over > 0:
			ok = false
		# ③ 复现
		var res2: Dictionary = _pentagrid_rhombi(gammas, Vector2.ZERO, 9.0)
		if (res2["verts"] as Array).size() != verts.size() \
				or (res2["rhombi"] as Array).size() != rhombi.size():
			ok = false
		print("[pentest] 种子=%d 格数=%d（胖%d 瘦%d 比=%.3f 期望≈1.618）重叠边=%d 复现=%s" % [
			_rand_seed, rhombi.size(), fat, thin, ratio, over,
			"一致" if (res2["verts"] as Array).size() == verts.size() else "不一致"])
	# ④ 完整装配路径：格数贴近目标
	_rand_seed = 42
	_generate_penrose_random()
	var dev: int = absi(tiles.size() - _rand_target)
	if dev > 2:
		ok = false
	print("[pentest] 装配：目标=%d 实际=%d 偏差=%d 连通剔块看上一行日志" % [_rand_target, tiles.size(), dev])
	print("[pentest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 二分搜索「窗口内格数最接近 target」的半径（格数随半径单调不减 → 可二分）。
## pentagrid 是按需生成的（半径参数直接决定枚举范围），每轮重新生成再数。
func _fit_pentagrid_radius(gammas: Array, wc: Vector2, target: int) -> float:
	var lo := 0.5
	var hi := 30.0
	for _b in 30:
		var mid: float = (lo + hi) * 0.5
		if (_pentagrid_rhombi(gammas, wc, mid)["rhombi"] as Array).size() < target:
			lo = mid
		else:
			hi = mid
	# hi = 刚好够、lo = 差一点；取离目标更近的那个
	var n_hi: int = (_pentagrid_rhombi(gammas, wc, hi)["rhombi"] as Array).size()
	var n_lo: int = (_pentagrid_rhombi(gammas, wc, lo)["rhombi"] as Array).size()
	return hi if absi(n_hi - target) <= absi(n_lo - target) else lo

## 随机相位组：前 4 个自由随机，第 5 个按 de Bruijn「和条件」Σγ ≡ 0 (mod 1) 反解。
## 和条件不满足时对偶仍是合法菱形密铺，但属于其它 LI 类（会出现十瘦星等 P3 禁排顶点构型）；
## 满足时才是真·彭罗斯类。同一 rng 序列必复现同一组相位（联机由房主下发种子依赖这一点）。
func _random_gammas(rng: RandomNumberGenerator) -> Array:
	var gammas: Array = []
	for k in 4:
		gammas.append(rng.randf())
	var s := 0.0
	for g in gammas:
		s += float(g)
	gammas.append(posmod(-s, 1.0))
	return gammas

## de Bruijn 五格网（pentagrid）→ P3 菱形密铺 —— 「按密铺规则造盘」的核心。
##
## 5 族平行线 L_k: n_k·x = γ_k + m（m ∈ Z），n_k = (cos 72°·k, sin 72°·k)。
## 对偶顶点 = 胞指标与网格法向的**线性组合** v(K) = Σ_m K_m·n_m（de Bruijn 1981 正交对偶）：
##   - 线性映射在 Z⁵ 上的核恰为 c·(1,1,1,1,1)（Φ₅ 关系），而实现胞恒满足条带条件
##     Σ K_m ∈ (−Γ−5, −Γ]（宽 5 的整数窗，Γ = Σγ）→ 同窗内两胞不可能相差 5·1 →
##     **对胞单射**：共享胞的菱形共享顶点 → 天然边到边、无重叠无缝隙（--pentest ② 钉死）。
##   - 边向量 = ±n_k → 所有边等长（= 网格线距）且**垂直**于对应网格线。
##   ⚠ 对偶公式若误写成「指数版」Σ ζ^{K_m}（K_m 作指数）会因「指数 mod 5 的任意重排
##   给出同一点」大量碰撞（v1 实测 478 格只有 81 个顶点、重复菱形 370）—— 两个公式长得像，
##   必须用线性版。
## 交点 p = L_i∩L_j（非奇异）对应**恰好一块**菱形：四角 = p 两侧 4 胞
## （K_i ∈ {mi−1,mi} × K_j ∈ {mj−1,mj}，其余族取 floor）的对偶点，
## 按**环序** (0,0)→(1,0)→(1,1)→(0,1) 登记 —— 顺序错了会把对角当边（蝴蝶结），装配必然碎裂。
## 胖瘦由**族号差**决定：posmod(j−i,5) ∈ {1,4} → 边夹角 72° = 胖；∈ {2,3} → 36° = 瘦。
## 奇异网格（三线共点）在随机浮点下概率 ≈ 0，命中则跳过该交点做防御。
## 返回结构与 _build_rhombi 一致（{"verts": Array[Vector2], "rhombi": [{type, verts:[4 索引]}]}），
## 直接喂给 _assemble_tiles，与 deflation 路径共用同一套装配/邻接/配色逻辑。
func _pentagrid_rhombi(gammas: Array, wc: Vector2, radius: float) -> Dictionary:
	var norms: Array[Vector2] = []
	for k in 5:
		var a: float = TAU * float(k) / 5.0
		norms.append(Vector2(cos(a), sin(a)))

	var vkey_to_idx: Dictionary = {}
	var verts: Array[Vector2] = []
	var rhombi: Array = []
	var reach: float = radius + 3.0   # 线号扫描范围；+3 余量防边缘漏格
	for i in 5:
		for j in range(i + 1, 5):
			var det: float = norms[i].cross(norms[j])
			# 胖瘦由族号差决定（见函数头注释）：相邻族 72° 胖，隔一族 36° 瘦
			var thick: bool = posmod(j - i, 5) == 1 or posmod(j - i, 5) == 4
			var i_lo: int = int(ceil(-reach - gammas[i]))
			var i_hi: int = int(floor(reach - gammas[i]))
			var j_lo: int = int(ceil(-reach - gammas[j]))
			var j_hi: int = int(floor(reach - gammas[j]))
			for mi in range(i_lo, i_hi + 1):
				for mj in range(j_lo, j_hi + 1):
					var bi: float = float(mi) + gammas[i]
					var bj: float = float(mj) + gammas[j]
					var p := Vector2(
						(bi * norms[j].y - bj * norms[i].y) / det,
						(bj * norms[i].x - bi * norms[j].x) / det)
					if (p - wc).length() > radius:
						continue   # 菱形中心在窗口外 → 不要
					# 其余 3 族的胞指标；若恰落在另一族线上（三线共点 = 奇异）→ 跳过。
					# 阈值 1e-9：只为防 float 抖动翻转 floor，随机浮点下命中概率 ≈ 0
					var base: Array = []
					var singular := false
					for m in 5:
						if m == i or m == j:
							continue
						var t: float = norms[m].dot(p) - gammas[m]
						if absf(t - roundf(t)) < 1e-9:
							singular = true
							break
						base.append(int(floor(t)))
					if singular:
						continue
					# 交点两侧 4 个胞的对偶顶点（i/j 族各取 m-1 / m 两档）。
					# **环序 (0,0)→(1,0)→(1,1)→(0,1)**：相邻两档只差一族胞编号，相邻顶点连出的才是真边。
					# 若按 (di,dj) 双重循环自然序 (0,0)(0,1)(1,0)(1,1) 输出，P00 与 P11 是对角 ——
					# 第 2/4 条边变成对角线，画出来是蝴蝶结：边不与邻居共享、还横穿邻块内部。
					var quad: Array[Vector2] = []
					for combo in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var ki: int = mi - 1 + int(combo[0])
						var kj: int = mj - 1 + int(combo[1])
						var v := Vector2.ZERO
						var q := 0
						for m in 5:
							var km: int
							if m == i:
								km = ki
							elif m == j:
								km = kj
							else:
								km = int(base[q])
								q += 1
							v += float(km) * norms[m]   # 线性对偶；不能用 ζ^{K_m} 指数版（见函数头）
						quad.append(v)
					# 顶点去重（与 _build_rhombi 同一套 quantize）+ 登记菱形
					var idxs: Array[int] = []
					for v in quad:
						var key: String = _vkey(v)
						if not vkey_to_idx.has(key):
							vkey_to_idx[key] = verts.size()
							verts.append(v)
						idxs.append(vkey_to_idx[key])
					rhombi.append({
						"type": "fat" if thick else "thin",
						"verts": idxs,
					})
	return {"verts": verts, "rhombi": rhombi}

## 连通性守卫：只保留最大的那一块连通区域，返回被剔掉的格数。
##
## 圆形窗口切下来的片**理论上**是完整一块，但边界上偶尔会出现「自己中心在窗口内、
## 所有邻居中心都在窗口外」的孤块 —— 它没有气路连到主盘，下上去就是死棋，必须剔掉。
## 固定盘不需要这个（圆裁剪 + 迭代结构下从来没出现过），随机盘窗口位置任意，必须守一道。
func _prune_to_largest_component() -> int:
	if tiles.size() == 0:
		return 0
	var seen: Array = []
	seen.resize(tiles.size())
	var best: Array[int] = []
	for s in range(tiles.size()):
		if seen[s]:
			continue
		var comp: Array[int] = [s]
		seen[s] = true
		var head := 0
		while head < comp.size():
			var cur: int = comp[head]
			head += 1
			for nb in adjacency[cur]:
				if not seen[nb]:
					seen[nb] = true
					comp.append(nb)
		if comp.size() > best.size():
			best = comp
	if best.size() == tiles.size():
		return 0                       # 本来就一整块，什么都不用做
	best.sort()
	var id_to_new: Dictionary = {}
	for k in best.size():
		id_to_new[best[k]] = k
	var old_to_new: Dictionary = {}
	var new_verts: Array[Vector2] = []
	var new_tiles: Array = []
	var new_colors: Array[Color] = []
	for id in best:
		var vs: Array = tiles[id]
		var nv: Array[int] = []
		for vi in vs:
			if not old_to_new.has(vi):
				old_to_new[vi] = new_verts.size()
				new_verts.append(vertices[vi])
			nv.append(old_to_new[vi])
		new_tiles.append(nv)
		new_colors.append(tile_colors[id])
	var new_adj: Array = []
	new_adj.resize(new_tiles.size())
	for k in best.size():
		var arr: Array[int] = []
		for nb in adjacency[best[k]]:
			if id_to_new.has(nb):
				arr.append(id_to_new[nb])
		new_adj[k] = arr
	var removed: int = tiles.size() - new_tiles.size()
	vertices = new_verts
	tiles = new_tiles
	tile_colors = new_colors
	adjacency = new_adj
	board.clear()
	for i in tiles.size():
		board[i] = Stone.EMPTY
	return removed

## 将瓷砖顶点按"绕重心的极角"排成环形顺序。
## find_tiles() 找到的 i→j→k→l 只是邻接可达顺序，不一定是绕瓷砖一圈的顺序，
## 直接传给 draw_colored_polygon() 会产生自交多边形，导致三角化失败。
func _sort_tile_by_angle(tile: Array) -> Array:
	var center := Vector2.ZERO
	for idx in tile:
		center += vertices[idx]
	center /= tile.size()
	tile.sort_custom(func(a: int, b: int) -> bool:
		return (vertices[a] - center).angle() < (vertices[b] - center).angle())
	return tile

func find_tiles() -> void:
	# 几何在 generate_penrose() / generate_cube() 里已完成；这里保留函数签名供旧调用使用。
	pass

## ====== 自检专用夹具：n×n 方形网格的**纯邻接**（不是棋盘！）======
##
## 为什么还留它：经典 19×19 网格棋盘 2026-09-15 已从产品里下线，但三个 AI 自检的局面是按
## 方形坐标（idx = y*n + x）**手工验算**出来的 ——
##   · --captest：提子计数（倍数重复 append 的历史 bug）
##   · --ladtest：征子的「无效叫吃 / 真征子」两例 + 先验增量对照
##   · --ailife：死活（12 种小眼形真源对照 + 做活/点杀要点 + 阴性对照 + 自战统计）
## 彭罗斯 P3 与立方体蜂窝的索引都不规整，移植等于重算并**重新手工验算**三套局面，
## 收益远小于引入错误的风险。所以这里只留 12 行的邻接构造：不产生任何顶点、
## 不进 generate_board() 分发，产品路径（渲染 / 星位 / _adapt_to_screen / 联机快照）零引用。
const TEST_GRID_N: int = 19

func _test_build_square_grid(n: int) -> void:
	_is_cube = false
	_is_kite = false
	_is_snow = false
	_is_hat = false
	_cube_star_tiles.clear()
	tiles.clear()
	adjacency.clear()
	board.clear()
	for i in n * n:
		tiles.append([])
		adjacency.append([])
		board[i] = Stone.EMPTY      # board 是 Dictionary（按 tile id 取子色），不是数组
	for y in n:
		for x in n:
			var a: Array = adjacency[y * n + x]
			if x > 0:     a.append(y * n + x - 1)
			if x < n - 1: a.append(y * n + x + 1)
			if y > 0:     a.append((y - 1) * n + x)
			if y < n - 1: a.append((y + 1) * n + x)

## 网格棋盘：把顶点 (x,y) 写入顶点表并返回索引（相邻块共享顶点自动去重）
## ⚠️ 别看名字带 grid —— 立方体盘的六边形生成也在用它作「通用顶点去重器」。
func _grid_vid(x: float, y: float, vert_map: Dictionary, vlist: Array[Vector2]) -> int:
	var key := str(snapped(x, 0.001), ",", snapped(y, 0.001))
	if vert_map.has(key):
		return vert_map[key]
	var idx := vlist.size()
	vlist.append(Vector2(x, y))
	vert_map[key] = idx
	return idx

# ====== 生成「立方体」棋盘：3 块 60°/120° 菱形拼成一个正六边形（等距立方体），六边形再排成蜂窝 ======
## 每个正六边形 = 一个「立方体」的等距投影（三个面 = 三块菱形），六边形按蜂窝（六边形网格）排列 → 大盘。
## 几何：六边形中心 O、六顶点 V0..V5（0°/60°/…/300°，|OV|=边长 a），
##   三块菱形 = {V0,V1,V2,O} / {V2,V3,V4,O} / {V4,V5,V0,O}（各含两个等边三角形）。
##   同一六边形内：相邻两面共享「辐条边」O-Vk；相邻六边形间：共享外缘边 V-V。
##   → 菱形之间严格共边、无缝无叠，每块菱形最多 4 邻（与经典围棋的四气一致）。
##   六边形中心 = 立方体「看得见的那个角」，三面明暗不同 → 经典的滚落方块/立方体错觉。
## 大小（_cube_hex_r = 环数 R）：R=4 → 61 六边形/183 格（标准）；R=6 → 127/381（加强）；
## 随机档不看环数，按目标格数随机生长（见 _generate_cube_random）。
## 六边形补丁的全部轴向坐标（半径 R 的六边形区域）
func _cube_patch_coords(R: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-R, R + 1):
		for r in range(-R, R + 1):
			var s: int = -q - r
			if maxi(maxi(absi(q), absi(r)), absi(s)) > R:
				continue                             # 只取六边形补丁（半径 R 的六边形区域）
			out.append(Vector2i(q, r))
	return out

func generate_cube() -> void:
	if _is_random_board():
		_generate_cube_random()
		return
	vertices.clear()
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()
	_cube_star_tiles.clear()
	_is_cube = true
	_is_kite = false
	_is_snow = false
	_is_hat = false

	var R: int = _cube_hex_r
	var coords := _cube_patch_coords(R)
	var hex_first_tile := _build_cube_from_coords(coords)
	_cube_star_tiles = _cube_star_coords(R, hex_first_tile)
	print("生成立方体棋盘 环数 ", R, "，六边形：", hex_first_tile.size(),
		"，瓷砖：", tiles.size(), "（落子格），星位：", _cube_star_tiles.size())

## 「随机」档立方体盘：从中心六边形开始，每次从「贴着已有区域的候选」里随机挑一个长上去，
## 直到六边形数达到 目标格数/3（每六边形 3 块菱形）。
##
## 为什么用生长而不是「大补丁里随机删」：生长出来的区域**必然连通**（每步都贴着已有区域），
## 删减则要反复做连通性检查，还容易删出带洞或带细颈的畸形盘。
## 随机挑前沿 → 形状是有机的一团（不是规整六边形），每局都不一样。
func _generate_cube_random() -> void:
	vertices.clear()
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()
	_cube_star_tiles.clear()
	_is_cube = true
	_is_kite = false
	_is_snow = false
	_is_hat = false

	var rng := RandomNumberGenerator.new()
	rng.seed = _rand_seed
	var target: int = maxi(20, random_target_tiles + rng.randi_range(-random_tile_jitter, random_tile_jitter))
	_rand_target = target
	var want_hex: int = maxi(3, int(round(float(target) / 3.0)))

	var coords := _cube_grown_coords(want_hex, rng)
	# 回填一个「等效环数」：HUD/日志里显示用，也保证 _cube_hex_r 不是占位值 0
	var rr: int = 0
	for cd: Vector2i in coords:
		rr = maxi(rr, maxi(maxi(absi(cd.x), absi(cd.y)), absi(-cd.x - cd.y)))
	_cube_hex_r = rr
	var hex_first_tile := _build_cube_from_coords(coords, rng)
	_cube_star_tiles = _cube_star_sectors(coords, hex_first_tile)
	print("生成随机立方体棋盘 种子=", _rand_seed, " 目标=", target, " 实际=", tiles.size(),
		" 落子格（", coords.size(), " 个六边形 / 等效 ", rr, " 环），星位：", _cube_star_tiles.size())

## 随机生长出 n 个六边形的连通坐标集（前沿随机选取 → 有机形状）
const _HEX_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
func _cube_grown_coords(n: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var chosen: Array[Vector2i] = [Vector2i(0, 0)]
	var in_set: Dictionary = {"0,0": true}
	var frontier: Array[Vector2i] = []
	for d: Vector2i in _HEX_DIRS:
		frontier.append(d)
	while chosen.size() < n and frontier.size() > 0:
		# 锦标赛选择：随机抽 random_grow_compact 个候选，取离中心最近的那个。
		# 纯随机（=1）会长出毛糙的、带长条触手的形状；这样挑能让轮廓收敛成圆润的一团。
		var pick := rng.randi_range(0, frontier.size() - 1)
		if random_grow_compact > 1:
			var bu := Vector2(1.5, sqrt(3.0) * 0.5)
			var bv := Vector2(0.0, sqrt(3.0))
			var best_d := INF
			for _t in random_grow_compact:
				var idx: int = rng.randi_range(0, frontier.size() - 1)
				var c2: Vector2i = frontier[idx]
				var d: float = (float(c2.x) * bu + float(c2.y) * bv).length()
				if d < best_d:
					best_d = d
					pick = idx
		var cd: Vector2i = frontier[pick]
		frontier.remove_at(pick)
		var key: String = "%d,%d" % [cd.x, cd.y]
		if in_set.has(key):
			continue
		in_set[key] = true
		chosen.append(cd)
		for d: Vector2i in _HEX_DIRS:
			var nb: Vector2i = cd + d
			if not in_set.has("%d,%d" % [nb.x, nb.y]):
				frontier.append(nb)
	return chosen

## 按轴向坐标建出全部六边形（每块 3 片菱形）、顶点去重、算邻接、初始化空盘。
## 固定盘与随机盘共用，返回值是 "q,r" → 该六边形第一块菱形 tile id（星位用）。
## orient_rng：随机盘传一个 RandomNumberGenerator，让每个小立方体随机旋转/镜像朝向；固定盘传 null（不旋转，与旧版一致）。
func _build_cube_from_coords(coords: Array, orient_rng: RandomNumberGenerator = null) -> Dictionary:
	var a := 1.0                                    # 菱形边长（= 六边形边长 = 中心到顶点距离）
	var sq3: float = sqrt(3.0)
	var bu := Vector2(1.5 * a, sq3 * 0.5 * a)        # 轴向基向量 q+1（30° 方向）
	var bv := Vector2(0.0, sq3 * a)                  # 轴向基向量 r+1（90° 方向）
	# 相邻六边形中心距 = |bu| = |bv| = sqrt(3)·a，正好是蜂窝密铺间距（共边无缝）

	var vert_map: Dictionary = {}
	var vlist: Array[Vector2] = []
	var hex_first_tile: Dictionary = {}              # "q,r" → 该六边形第一块菱形的 tile id（星位用）

	for cd in coords:
		var q: int = cd.x
		var r: int = cd.y
		var c: Vector2 = float(q) * bu + float(r) * bv
		var vs: Array[int] = []
		for k in range(6):
			var ang: float = float(k) * PI / 3.0
			vs.append(_grid_vid(c.x + a * cos(ang), c.y + a * sin(ang), vert_map, vlist))
		var oc: int = _grid_vid(c.x, c.y, vert_map, vlist)   # 六边形中心（立方体的内角点）
		# 每个小立方体的随机朝向：仅随机盘传了 orient_rng；固定盘为 null → 不旋转，与旧版一致。
		# 正六边形的三菱形分解在几何上只有两种不同朝向（转 120° 不变形）：
		#   dir=0 → 三条内辐条指向偶顶点 vs0/2/4；dir=1 → 指向奇顶点 vs1/3/5（等效旋转 60°）。
		# 统一底色后 tile_colors 不再参与渲染，旧版「0/120/240 三向 + 镜像」只改过配色序，本就不可见。
		# 内辐条与轮廓边随朝向变化，但六边形轮廓与共享边不变 → 邻接仍由下方共享边重建。
		var dir: int = 0
		if orient_rng != null and cube_hex_random_rot:
			dir = orient_rng.randi_range(0, 1)
		hex_first_tile["%d,%d" % [q, r]] = tiles.size()
		for p in range(3):
			var s: int = (dir + 2 * p) % 6   # dir=0: 0,2,4；dir=1: 1,3,5
			tiles.append([vs[s], vs[(s + 1) % 6], vs[(s + 2) % 6], oc])
			tile_colors.append(cube_face_mid)   # 兼容联机快照（已不用于渲染）

	vertices = vlist

	# 邻接：共享一条边（两端顶点相同）的两块菱形互为邻居
	adjacency.resize(tiles.size())
	for i in range(tiles.size()):
		adjacency[i] = []
	var edge_map: Dictionary = {}
	for i in range(tiles.size()):
		var tt: Array = tiles[i]
		for k in range(4):
			var v1i: int = tt[k]
			var v2i: int = tt[(k + 1) % 4]
			var ekey: String = "%d,%d" % [mini(v1i, v2i), maxi(v1i, v2i)]
			if not edge_map.has(ekey):
				edge_map[ekey] = []
			var owners: Array = edge_map[ekey]
			owners.append(i)
	for ekey2 in edge_map:
		var own: Array = edge_map[ekey2]
		if own.size() == 2:                          # 内部边：恰好两块菱形共享；边界边只有一块
			adjacency[own[0]].append(own[1])
			adjacency[own[1]].append(own[0])

	board.clear()
	for i in range(tiles.size()):
		board[i] = Stone.EMPTY
	return hex_first_tile

## 立方体盘星位：中心六边形 + 六个角六边形，各取其中一块菱形（共 7 个标记点）
func _cube_star_coords(R: int, hex_first_tile: Dictionary) -> Array[int]:
	var pts: Array[int] = []
	var coords: Array[Vector2i] = [Vector2i(0, 0)]
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
			Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]:
		coords.append(Vector2i(d.x * R, d.y * R))
	for cd in coords:
		var k2: String = "%d,%d" % [cd.x, cd.y]
		if hex_first_tile.has(k2):
			pts.append(int(hex_first_tile[k2]))
	return pts

## 随机（生长）盘的星位：中心六边形 + 六个 60° 扇区里各自最远的那个六边形 → 恒 7 个标记点。
## 固定盘的「六个角」在生长出来的形状里未必存在（_cube_star_coords 会取不到、星位就少了），
## 所以这里改用扇区取最远；对规整的六边形补丁，它取到的恰好就是那六个角。
func _cube_star_sectors(coords: Array, hex_first_tile: Dictionary) -> Array[int]:
	var bu := Vector2(1.5, sqrt(3.0) * 0.5)
	var bv := Vector2(0.0, sqrt(3.0))
	var best: Array[int] = []
	var best_d: Array[float] = []
	for i in 6:
		best.append(-1)
		best_d.append(-1.0)
	var center_id := -1
	for cd in coords:
		var key: String = "%d,%d" % [cd.x, cd.y]
		var c: Vector2 = float(cd.x) * bu + float(cd.y) * bv
		if cd.x == 0 and cd.y == 0:
			center_id = int(hex_first_tile[key])
			continue
		var d: float = c.length()
		var sec: int = int(floori((c.angle() + PI) / (PI / 3.0))) % 6
		if d > best_d[sec]:
			best_d[sec] = d
			best[sec] = int(hex_first_tile[key])
	var pts: Array[int] = []
	if center_id >= 0:
		pts.append(center_id)
	for i in 6:
		if best[i] >= 0:
			pts.append(best[i])
	return pts


# ====== 生成「筝形」棋盘：3 块筝形钝角相对拼成一个等边三角形，三角形再密铺 ======
## 筝形的几何（kite = 两组邻边分别相等的四边形）：**长边 a/2 ×2 + 短边 a/(2√3) ×2**
## （这里 `a` 一律指**等边三角形的边长**，也就是菱形的边；筝形自己的长边是它的一半），
## 四个角依次是 **60°（尖角）/ 90° / 120°（钝角）/ 90°**。
## 对称轴 = 尖角顶点 ↔ 钝角顶点；沿轴切开是两个全等的 30-60-90 三角形
## （斜边 a/2、长直角边 a/(2√3)·√3 = a/4、短直角边 a/(4√3)）。
##
## **「钝角相对」的确切做法（推导过一轮，别改）**：
##   等边三角形 ABC（边长 a），中心 O = 质心，三边中点 M_AB / M_BC / M_CA。
##   三块筝形各取**一个三角形顶点**作尖角，再取该顶点两条**邻边**的中点，钝角落在 O：
##     kite_A = { A(尖角), M_AB, O(钝角), M_CA }
##     kite_B = { B(尖角), M_BC, O(钝角), M_AB }
##     kite_C = { C(尖角), M_CA, O(钝角), M_BC }
##   边长：A→M_AB = A→M_CA = a/2（长边）；M_AB→O = M_CA→O = a/(2√3)（短边）。
##   三块**全等**、面积各 = 三角形面积 / 3（A = a²/(4√3)，三块和 = √3a²/4 ✔）、
##   两两严格共边（共享边 = O 到三个边中点的三条线段），无缝无叠、恰好铺满三角形。
##
##   ⚠️ 踩过的三个坑（都写成数学证明了，别再试）：
##     ① 钝角放「三角形中心、短边从中心指向顶点」→ 三块虽然面积各 1/3，
##        但边长是 a/2 与 a/(2√3) 混搭、角度谱跑成 40.89/158.21，不是筝形；
##     ② 钝角放**边中点** → 那点的内外角是 180°，永远不是 120°；
##     ③ 若强行要求「钝角全在 O 且短边都从 O 出发」，第三块的对顶点会退化成 180°
##        （余弦定理：设钝角两边夹角 120°、三角形那两顶点处各占 30° → 第四角 = 180°）。
##
## **密铺（已验证 0 重叠、邻接 2~4）**：
##   铺块 = **60/120 菱形**（两条等边三角形沿一条公共边对贴而成的菱形，
##   四个顶点 A(0,0) / B(a,0) / V_上(a/2,+h) / V_下(a/2,-h)，四条边都是 a）。
##   ⚠️ 不是「1.5a / 30° 菱形」那套写法 —— 那套的 r 步长是 2h，配出的三角形成对关系
##   不是「共享 A-B」，自检直接表现为「连通块数 == 三角形数」、邻接全断、
##   随机盘被 `_prune_to_largest_component()` 剔到只剩一个三角形（6 格）。
##   晶格基向量：**bu = (a, 0)**、**bv = (a/2, h = √3a/2)**，即
##     菱形中心 c = q·(a, 0) + r·(a/2, √3a/2)。
##   上下两个三角形的**原点都用同一个 c**（上三角形 V 朝上 = c+(a/2,+h)，
##   下三角形 V 朝下 = c+(a/2,-h)，两者水平边同为 A-B = c→c+(a,0)，天然共边）。
##
## 与立方体盘的关系：立方体盘 = 「3 块 90/90/60/120 菱形 → 一个六边形 → 蜂窝」，
## 筝形盘 = 「3 块 90/90/60/120 筝形 → 一个等边三角形 → 三角格」。同样的「3 合一」结构，
## 只是合成出来的单元从六边形换成三角形。
##
## 全局编号约定（**全程只用它，别在别处另立一套**）：
##   菱形 g = [q, r]，内部槽位 gidx = 0..5：前 3 个是该菱形的「上三角形」三块筝形、
##   后 3 个是「下三角形」三块筝形。
##   全局槽位号 s = 6·g + gidx —— 于是「一个三角形」= 连续 3 个槽位、
##   「一个菱形」= 连续 6 个槽位，邻接/星位/自检全都按这个步长走。
## 半径 R 的菱形补丁 → 6R²+6R+1 个菱形 → 6·(6R²+6R+1) 个落子格（每菱形 6 块）。
const _KITE_SQ3: float = 1.7320508075688772
## 顶点去重容差：相邻菱形的公共顶点是「不同浮点来源算出的同一个点」，
## 直接用 `==` 做 key 会留下重影顶点 → 边对不上 → 邻接全断。
const _KITE_EPS: float = 1e-5


## 顶点 id 去重（浮点容差）。
##
## `_grid_vid` 用的是 `Vector2` 精确相等做字典 key；立方体/彭罗斯盘上顶点坐标由**整数**格点
## 线性组合得到，浮点完全一致，所以没问题。但筝形盘里同一个顶点会从**不同棱**算出：
## 例如三角形顶点 (a, 0) 既是「A 顶点」又是「尖角在中点的那个菱形」的钝角邻居……
## 两条路径的浮点表达式不同 → 末位可能差 1ulp → 判成两个顶点 → 公共边不匹配 → 邻接丢失。
## 所以这里用网格化（量化到 _KITE_EPS）的 key 做去重，并对已存顶点做邻域回查兜底。
func _kite_vid(x: float, y: float, vert_map: Dictionary, vlist: Array[Vector2]) -> int:
	var qx: int = int(round(x / _KITE_EPS))
	var qy: int = int(round(y / _KITE_EPS))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key: String = "%d,%d" % [qx + dx, qy + dy]
			if vert_map.has(key):
				var vid: int = int(vert_map[key])
				if (vlist[vid] as Vector2).distance_squared_to(Vector2(x, y)) <= _KITE_EPS * _KITE_EPS * 4.0:
					return vid
	var key2: String = "%d,%d" % [qx, qy]
	var id: int = vlist.size()
	vlist.append(Vector2(x, y))
	vert_map[key2] = id
	return id


## 半径 R 的菱形补丁（菱形级六边形判据）——**仅供「向外扩一圈再筛」的候选池使用**。
##
## ⚠️ **不要**直接拿它当盘面！菱形并集的轮廓**永远不可能是正六边形**：
##   菱形的边只有 60°/120° 两个方向，而正六边形的六条边需要 **三组**平行方向
##   （0°/60°/120°）—— 两个方向凑不出三组。实测 R=2 的边界环是
##   `60×3 300 60 300 60 300×3 240×3 120 240 120 240 120×3`，即
##   「上/下各 4 个三角尖角（锯齿）+ 左右各一个锯齿尖」，正是用户看到的样子。
##   真正的正六边形必须在**三角形级**选区 —— 见 `_kite_hex_cells()`。
func _kite_patch_coords(R: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-R, R + 1):
		for r in range(-R, R + 1):
			var s: int = -q - r
			if maxi(maxi(absi(q), absi(r)), absi(s)) > R:
				continue
			out.append(Vector2i(q, r))
	return out


## **正六边形选区（本盘的边界真源）** —— 在**三角形级**上筛，而不是菱形级。
##
## 为什么三角形级就能拼出正六边形：等边三角形的边方向是 **{0°, 60°, 120°}**，
## 正好是正六边形需要的三组平行边方向。于是「取所有顶点都落在某个正六边形内的
## 三角形」这个选区，其并集边界**恰好就是那个正六边形**（每条边由 R 条单位边拼成，
## 60° 旋转对称，零锯齿）。
##
## 判据用的是 **pointy-top 正六边形距离**（顶点朝上/下，共 6 条边）：
##   hexdist(x, y) = max( |y|, |y/2 − (√3/2)x|, |y/2 + (√3/2)x| ) <= R
## 即「以原点为中心、到三条轴（y 轴 + 两条 60° 斜轴）的距离都不超过 R」。
## **必须用「三角形的 3 个顶点全部在六边形内」做判定**（不是只判重心）——
## 只判重心会切出半截三角形，边界立刻重新变锯齿。
##
## 返回 `[q, r, half]` 三元组数组；half 0 = 上三角形（V 朝上）、1 = 下三角形。
## R=1 → 6 个三角形 / 18 格；R=3 → 54 / 162；R=4 → 96 / 288。
func _kite_hex_cells(R: float) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var a := 1.0
	var h: float = _KITE_SQ3 * 0.5 * a
	# 候选池要留足余量：三角形中心比菱形中心偏半格，六边形外还要往外扩一圈
	var lim: int = int(ceil(R / h)) + 3
	for q in range(-lim, lim + 1):
		for r in range(-lim, lim + 1):
			var cx: float = float(q) * a + float(r) * a * 0.5
			var cy: float = float(r) * h
			for half in 2:
				var sy: float = 1.0 if half == 0 else -1.0
				# 三角形三顶点（与 _kite_quad_pts 的展开同源）：A(c)、B(c+(a,0))、V(c+(a/2, ±h))
				var vs: Array = [
					Vector2(cx, cy),
					Vector2(cx + a, cy),
					Vector2(cx + a * 0.5, cy + sy * h),
				]
				var inside := true
				for v: Vector2 in vs:
					if _kite_hex_dist(v.x, v.y) > R + 1e-9:
						inside = false
						break
				if inside:
					out.append(Vector3i(q, r, half))
	return out


## pointy-top 正六边形距离：到三条轴（y 轴、两条 ±60° 斜轴）的距离取最大。
## 三条轴把平面分成 6 个 60° 扇区 —— 这个式子对 60° 旋转严格不变，
## 所以 `<= R` 的区域天然是正六边形（而不是被坐标轴「压扁」的六边形）。
##
## ⚠️ **三个绝对值必须一律用 `absf()`，绝不能写 `absi()`** ——
## `absi()` 是**整数**绝对值，喂给它 float 会先**截断成整数**：`absi(3.464) == 3`。
## 后果很隐蔽：`hd` 在竖轴方向上被系统性压小 → 多收一整圈三角形
## （R=3 时实测 64 个三角形 / 34 菱形 / 192 格，正确值是 54 / 30 / 162），
## 而且**不会报错、不会下标越界**，只是棋盘悄悄变大、边界重新长出锯齿。
## （踩坑记录：一开始就是写成 absi，靠 Python 复算 absi 截断行为才定位到。）
func _kite_hex_dist(x: float, y: float) -> float:
	var k: float = _KITE_SQ3 * 0.5
	return maxf(maxf(absf(y), absf(y * 0.5 - k * x)), absf(y * 0.5 + k * x))


## 把三角形级选区摊平成 `_build_kite_from_coords` 直接能吃的菱形坐标 + 半边掩码。
##
## `_build_kite_from_coords` 是按「菱形 → 上下两个三角形」两层循环建的，
## 而正六边形选区在边缘会出现**只有一半的菱形**（该菱形只有一个三角形入选）。
## 于是这里返回 (coords, mask)：mask 的 key 是 `"q,r"`，value 是 2 位掩码
## （bit0 = 收上三角形、bit1 = 收下三角形；3 = 两个都收）。
## 完整成对的菱形仍然是**连续 6 个槽位**，边缘半菱形只有 3 个槽位 —— 邻接/自检都按
## 实际 tiles 数走，不依赖「菱形恒定 6 块」这个假设。
func _kite_hex_patch(R: float) -> Array:
	var cells := _kite_hex_cells(R)
	var mask: Dictionary = {}
	var order: Array[Vector2i] = []
	for c in cells:
		var key: String = "%d,%d" % [c.x, c.y]
		if not mask.has(key):
			mask[key] = 0
			order.append(Vector2i(c.x, c.y))
		# half 0 → bit0（上三角形）；half 1 → bit1（下三角形）
		mask[key] = int(mask[key]) | (1 << c.z)
	# 稳定排序：先按环号、再按角度，保证同一 R 下盘面编号确定（联机快照要一致）
	order.sort_custom(func(x: Vector2i, y: Vector2i) -> bool:
		var dx: int = maxi(maxi(absi(x.x), absi(x.y)), absi(-x.x - x.y))
		var dy: int = maxi(maxi(absi(y.x), absi(y.y)), absi(-y.x - y.y))
		if dx != dy:
			return dx < dy
		return atan2(float(x.y), float(x.x)) < atan2(float(y.y), float(y.x)))
	return [order, mask]


## 第 gidx 块筝形的顶点（**局部坐标，菱形左下角 A 为原点**；sgn=±1 决定上/下三角形）。
##
## 由上面已验证的分解直接展开（a=1 时数值见下，全部按 a 缩放）：
##   上三角形：A(0,0) V(a/2, √3a/2) B(a,0)，中心 O(a/2, √3a/6)
##     gidx0（尖角在 V）：V, mid(V,A), O, mid(V,B)      → (-a/2,√3a/2) (-3a/4,√3a/4) (-a/2,√3a/6) (-a/4,√3a/4)
##     gidx1（尖角在 A）：A, mid(A,V), O, mid(A,B)      → (-a,0) (-3a/4,√3a/4) (-a/2,√3a/6) (-a/2,0)
##     gidx2（尖角在 B）：B, mid(B,V), O, mid(B,A)      → (0,0) (-a/4,√3a/4) (-a/2,√3a/6) (-a/2,0)
##   下三角形：A(0,0) B(a,0) D(a/2,-√3a/2)，中心 O(a/2,-√3a/6)；把上式的 y 取反即可。
##
## 环序**按位置**（左上 / 左下 / 下中 / 下右）写死、不随 sgn 变 ——
## 于是上下两个三角形在共享的水平边 A-B 上给出的顶点顺序一致
## （gidx1 与 gidx2 都含 (-a/2,0) 与 (-a/2, sgn√3a/6)），能正确配成共享边。
func _kite_quad_pts(gidx: int, sgn: float, a: float, b: float) -> Array[Vector2]:
	var h2: float = _KITE_SQ3 * 0.5 * a          # √3a/2（三角形高 = 长边）
	var h6: float = _KITE_SQ3 / 6.0 * a          # √3a/6（中心到水平边的距离）
	var h4: float = _KITE_SQ3 * 0.25 * a         # √3a/4（上/下半边高）
	var c2: float = a * 0.5
	var c4: float = a * 0.25
	var c34: float = a * 0.75
	match gidx:
		0:
			return [Vector2(-c2, sgn * h2), Vector2(-c34, sgn * h4),
				Vector2(-c2, sgn * h6), Vector2(-c4, sgn * h4)]
		1:
			return [Vector2(-a, 0.0), Vector2(-c34, sgn * h4),
				Vector2(-c2, sgn * h6), Vector2(-c2, 0.0)]
		_:
			return [Vector2(0.0, 0.0), Vector2(-c4, sgn * h4),
				Vector2(-c2, sgn * h6), Vector2(-c2, 0.0)]


## 建出全部筝形（每三角形 3 块）、顶点去重、算邻接、初始化空盘。
## 固定盘与随机盘共用；返回值与 _build_cube_from_coords 同型：全局槽位号 s → 该三角形
## 「第一块」筝形的 tile id（星位用）。三角形号 tri = s / 3。
##
## mirror / rot_step 只给**随机盘**用：整盘网格已按 rot 旋转、按 mirror 镜像，
## 菱形内部的三角形朝向也必须跟着转 —— 否则观感上像"贴图没跟着转"。
## rot_step = rot / 60° 的整步数（三角形格在 60° 旋转下自映射，故只有 6 档）；
## mirror=true 时把侧向翻转（上/下三角形互换 + 左右互换）。固定盘传 (false, 0)，与旧版一致。
##
## `mask`（可选）：`"q,r"` → 2 位掩码，bit0 = 收上三角形、bit1 = 收下三角形。
## 正六边形选区在边缘会出现**只有一半的菱形**（`_kite_hex_patch` 产出），
## 传 null 时默认两个三角形都收（旧行为，完整菱形）。
func _build_kite_from_coords(coords: Array, mirror: bool = false, rot_step: int = 0,
		mask: Dictionary = {}) -> Dictionary:
	var a := 1.0                                  # 等边三角形边长（= 筝形长边）
	var b: float = a * 0.5 / _KITE_SQ3             # 筝形短边 = a/(2√3)
	var h: float = _KITE_SQ3 * 0.5 * a             # 等边三角形高 = √3a/2 = 半个菱形高
	# 密铺基向量 —— **60/120 菱形（= 两条等边三角形沿一条边对贴）的晶格**：
	#   菱形四顶点 = A(c)、B(c+(a,0))、V_上(c+(a/2, h))、V_下(c+(a/2, -h))。
	#   它沿 bu=(a,0) 与 bv=(a/2,h) 平移即密铺整平面（已验证：重叠边 0）。
	#   ⚠️ 别把它当成「1.5a/h」那套 30° 菱形：那套的 r 步长是 2h，
	#   配出的三角形成对关系不是「共享 A-B」，自检会看到连通块 == 三角形数。
	var bu := Vector2(a, 0.0)                     # 菱形晶格基向量（水平，长 a）
	var bv := Vector2(a * 0.5, h)                 # 菱形晶格基向量（60° 方向，长 a）

	var vert_map: Dictionary = {}
	var vlist: Array[Vector2] = []
	var tri_first_tile: Dictionary = {}           # 三角形号 (int) → 第一块筝形的 tile id
	var rot_n: int = posmod(rot_step, 6)

	for cd in coords:
		var q: int = cd.x
		var r: int = cd.y
		var c: Vector2 = float(q) * bu + float(r) * bv
		# 上三角形（sgn=+1，编号 0/1/2）与下三角形（sgn=-1，编号 3/4/5）。
		#
		# **两个三角形共用同一个原点 c** —— 这是整块几何的关键：
		#   上三角形的顶点朝上（V 在 c+(a/2,+h)），下三角形的顶点朝下（V 在 c+(a/2,-h)），
		#   两者的水平边都是同一条 A-B = c→c+(a,0)，于是天然共边、合起来正好是一个
		#   60/120 菱形（四顶点 A、B、V_上、V_下，四条边都长 a）。
		#   （筝形短边 b = a/(2√3) 只出现在「钝角点到两腰中点」的内部棱上，不参与跨块拼合。）
		for half in 2:
			# 半边掩码：正六边形边缘的「半菱形」只收其中一个三角形。
			# 掩码为空（旧行为）→ 两位都收，与改动前完全一致。
			if not mask.is_empty():
				var mkey: String = "%d,%d" % [q, r]
				if not mask.has(mkey) or (int(mask[mkey]) & (1 << half)) == 0:
					continue
			var sgn: float = 1.0 if half == 0 else -1.0
			var tri_no: int = (q * 3 + r) * 2 + half
			tri_first_tile[tri_no] = tiles.size()
			var org: Vector2 = c
			# 轮换 3 块筝形的位置 = 三角形绕自己中心转 120° 的整数倍；镜像再翻一次侧向
			var start: int = posmod(-rot_n, 3)
			var step: int = 1 if rot_n < 3 else -1
			var m_sgn: float = -sgn if mirror else sgn
			for j in 3:
				var gidx: int = posmod(start + step * j, 3)
				var ids: Array[int] = []
				for p in _kite_quad_pts(gidx, m_sgn, a, b):
					# 镜像时 x 也要翻（否则每块是镜像的、整盘却不是）
					var px: float = -p.x if mirror else p.x
					ids.append(_kite_vid(org.x + px, org.y + p.y, vert_map, vlist))
				tiles.append(ids)
				tile_colors.append(thin_color)

	vertices = vlist

	# 邻接：共享一条边（两端顶点相同）的两块筝形互为邻居
	adjacency.resize(tiles.size())
	for i in range(tiles.size()):
		adjacency[i] = []
	var edge_map: Dictionary = {}
	for i in range(tiles.size()):
		var tt: Array = tiles[i]
		for k in range(4):
			var v1i: int = tt[k]
			var v2i: int = tt[(k + 1) % 4]
			var ekey: String = "%d,%d" % [mini(v1i, v2i), maxi(v1i, v2i)]
			if not edge_map.has(ekey):
				edge_map[ekey] = []
			(edge_map[ekey] as Array).append(i)
	for ekey2 in edge_map:
		var own: Array = edge_map[ekey2]
		if own.size() == 2:                       # 内部边：恰好两块共享；边界边只有一块
			adjacency[own[0]].append(own[1])
			adjacency[own[1]].append(own[0])

	board.clear()
	for i in range(tiles.size()):
		board[i] = Stone.EMPTY
	return tri_first_tile


## 筝形盘（固定档）：迷你 2 环 / 标准 3 环 / 加强 4 环，边界均为严格正六边形。
func generate_kite() -> void:
	vertices.clear()
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()
	_cube_star_tiles.clear()
	_is_cube = false
	_is_kite = true
	_is_snow = false

	# 固定盘用 `_kite_r_actual`（由 `_apply_board_size()` 按尺寸档设定：迷你 2 / 标准 3 / 加强 4），
	# **不能**直接用 @export 的 `_kite_r` —— 那是编辑器调参用的，菜单尺寸档不会去改它。
	#
	# **正六边形边界**：选区走 `_kite_hex_patch(R)`（三角形级 pointy-top 正六边形），
	# 而不是 `_kite_patch_coords(R)`（菱形级）—— 后者轮廓必然带锯齿，见前者注释里的证明。
	var R: int = _kite_r_actual if _kite_r_actual > 0 else _kite_r
	var patch := _kite_hex_patch(float(R))
	var coords: Array = patch[0]
	var mask: Dictionary = patch[1]
	var tri_first := _build_kite_from_coords(coords, false, 0, mask)
	_cube_star_tiles = _kite_star_coords(R, tri_first)
	print("生成筝形棋盘 环数 ", R, "，菱形：", coords.size(),
		"，瓷砖：", tiles.size(), "（落子格），星位：", _cube_star_tiles.size())


## 固定筝形盘星位：中心三角形 + 六个角方向的三角形（共 7 块标记点）。
##
## ⚠️ **不要**再用「沿菱形晶格六个方向走 R 环」那套取法 —— 正六边形选区的角**不落在**
## 菱形晶格轴上（两套朝向相差 30°），实测 6 个角里有 3 个取不到
## （R=3 时 `(3,0) (0,3) (3,-3)` 全在盘外）→ 星位只剩 6 个，自检报「星位数不符」。
## 直接用**扇区法**（`_kite_star_sectors`）：按极角分 6 个 60° 扇区、
## 每扇区取最远三角形。正六边形角正好在 0°/60°/…/300°，与扇区边界对齐，
## 于是 6 个扇区各恰好吃到一个角 → 恒 7 个标记点。
func _kite_star_coords(R: int, tri_first: Dictionary) -> Array[int]:
	# 固定盘不旋转也不镜像（rotate=0 / mirror=+1 是恒等变换）
	return _kite_star_sectors(_kite_hex_patch(float(R))[0], tri_first, 1.0, 0.0)


## 筝形盘星位（扇区法）：中心三角形 + 六个 60° 扇区里各自最远的那个三角形 → 恒 7 个标记点。
## 与 _cube_star_sectors 同一套扇区法（mirror/rot 参数保留通用性，固定盘传恒等变换）。
func _kite_star_sectors(coords: Array, tri_first: Dictionary, mirror: float, rot: float) -> Array[int]:
	var a := 1.0
	var bu := Vector2(a, 0.0)                     # 菱形晶格基向量（与 _build_kite_from_coords 同源）
	var bv := Vector2(a * 0.5, _KITE_SQ3 * 0.5 * a)   # 与 _build_kite_from_coords 同源，别写成 √3a
	var best: Array[int] = [-1, -1, -1, -1, -1, -1]
	var best_d: Array[float] = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0]
	var center_id := -1
	for cd in coords:
		var p: Vector2 = Vector2(float(cd.x) * bu.x + float(cd.y) * bv.x,
			float(cd.x) * bu.y + float(cd.y) * bv.y)
		p = Vector2(p.x * mirror, p.y).rotated(rot)
		var t: int = _kite_center_tri(cd.x, cd.y)
		if not tri_first.has(t):
			continue
		if cd.x == 0 and cd.y == 0:
			center_id = int(tri_first[t])
			continue
		var d: float = p.length()
		# 扇区判定必须用 **roundi 而非 floori**：正六边形的 6 个角方向（0°/60°/…/300°）
		# 恰好落在扇区**边界**上，floor 对浮点 ε 敏感 —— R=2 时 60° 方向的角三角形
		#（中心精确在 60°）实测被 floor 划进 0° 的扇区，6 个角只占 5 个扇区 → 星位只剩 6。
		# round 让边界角稳定归入「其角度对应」的扇区：0°→sec3、60°→sec4、…、300°→sec2，
		# 六角与六扇区构成双射，R=2/3/4 恒 7 星。
		var sec: int = posmod(int(roundi((p.angle() + PI) / (PI / 3.0))), 6)
		if d > best_d[sec]:
			best_d[sec] = d
			best[sec] = int(tri_first[t])
	var pts: Array[int] = []
	if center_id >= 0:
		pts.append(center_id)
	for i in 6:
		if best[i] >= 0:
			pts.append(best[i])
	return pts


## 中心三角形号——**必须与 _build_kite_from_coords 里的一致**
func _kite_center_tri(q: int, r: int) -> int:
	return (q * 3 + r) * 2


## 边统计里「只被 1 块占用」的边数（= 盘面边界边；不算判负，只作参考量）
func n_border_edges(edge_count: Dictionary) -> int:
	var n := 0
	for key in edge_count:
		if int(edge_count[key]) == 1:
			n += 1
	return n


## **正六边形边界验证**（`--kitetest` 自检用）。
##
## 做法：取当前盘（筝形）所有「只被 1 块占用」的边，把整条边界按**顶点串成闭合环**，
## 然后断言环恰好是正六边形。判据不靠「数边数」而是**几何量**：
##   ① 环顶点数 == 6R（六条边各 R 段）；
##   ② 逐边方向只落在 {0°, 60°, 120°, 180°, 240°, 300°} 六个方向（容差 1°），
##      且**连续同向段恰好 6 段、每段长度都是 R**；
##   ③ 六段的方向是**等差 60° 的完整一圈**（不是两段 60° + 两段 120° 那种锯齿谱）；
##   ④ 对边两两平行（方向差严格 180°）。
## 这四条同时成立 ⇔ 边界是正六边形。任何锯齿（比如旧菱形级选区的
## `60×3 300 60 300 60 300×3 ...`）都会在 ② 或 ③ 上当场挂掉。
func _kite_hex_boundary_report() -> Dictionary:
	var res: Dictionary = {"vertices": 0, "cycles": 0, "sides": 0,
		"uniform_sides": false, "six_dirs": false, "is_hex": false}
	if not _is_kite or tiles.is_empty():
		return res

	# 收集「只被 1 块占用」的边（= 边界边），并统计每块筝形的 4 条边被谁占用
	var owner: Dictionary = {}
	for i in range(tiles.size()):
		var tt: Array = tiles[i]
		if tt.size() < 3:
			continue
		for k in range(tt.size()):
			var v1i: int = tt[k]
			var v2i: int = tt[(k + 1) % tt.size()]
			var ekey: String = "%d,%d" % [mini(v1i, v2i), maxi(v1i, v2i)]
			owner[ekey] = int(owner.get(ekey, 0)) + 1
	var nb: Dictionary = {}                      # 顶点 id → 相邻顶点 id 列表（只沿边界边）
	for ekey in owner:
		if int(owner[ekey]) != 1:
			continue
		var parts: PackedStringArray = (ekey as String).split(",")
		var a2: int = int(parts[0])
		var b2: int = int(parts[1])
		if not nb.has(a2):
			nb[a2] = []
		if not nb.has(b2):
			nb[b2] = []
		(nb[a2] as Array).append(b2)
		(nb[b2] as Array).append(a2)
	if nb.is_empty():
		return res
	res["vertices"] = nb.size()

	# 串环（边界是单一闭合环；若串出多环说明盘面有洞/有孤岛，直接判非六边形）
	var seen: Dictionary = {}
	var cycles: Array = []
	for s in nb:
		if seen.has(s):
			continue
		var ring: Array[int] = [s]
		seen[s] = true
		var prev: int = -1
		var cur: int = s
		var closed := false
		while true:
			var nxt: int = -1
			for cand: int in (nb[cur] as Array):
				if cand != prev:
					nxt = cand
					break
			if nxt < 0:
				break
			if nxt == s:
				closed = true
				break
			if seen.has(nxt):
				break
			ring.append(nxt)
			seen[nxt] = true
			prev = cur
			cur = nxt
		if closed:
			cycles.append(ring)
	res["cycles"] = cycles.size()
	if cycles.size() != 1:
		print("[hex] 边界不是单一闭合环（环数=", cycles.size(), "）→ 非正六边形")
		return res
	var ring2: Array = cycles[0]
	var n: int = ring2.size()
	if n < 6:
		return res

	# 逐边方向 + 长度
	var dirs: Array[float] = []
	var lens: Array[float] = []
	for i in range(n):
		var p: Vector2 = vertices[ring2[i]]
		var q2: Vector2 = vertices[ring2[(i + 1) % n]]
		var dv: Vector2 = q2 - p
		lens.append(dv.length())
		dirs.append(rad_to_deg(atan2(dv.y, dv.x)))

	# ② 同向段：连续方向相同的边归为一段（方向容差 1°，且考虑 ±180° 等价）
	var runs: Array = []                        # [{dir, count, len}]
	for i in range(n):
		var d: float = dirs[i]
		var merged := false
		if not runs.is_empty():
			var last: Dictionary = runs[runs.size() - 1]
			var dd: float = absf(fposmod(d - float(last["dir"]) + 180.0, 360.0) - 180.0)
			if dd < 1.0:
				last["count"] = int(last["count"]) + 1
				last["len"] = float(last["len"]) + lens[i]
				merged = true
		if not merged:
			runs.append({"dir": d, "count": 1, "len": lens[i]})
	# 首尾同向则合并（环是闭合的）
	if runs.size() > 1:
		var first: Dictionary = runs[0]
		var last2: Dictionary = runs[runs.size() - 1]
		var dd2: float = absf(fposmod(float(first["dir"]) - float(last2["dir"]) + 180.0, 360.0) - 180.0)
		if dd2 < 1.0:
			last2["count"] = int(last2["count"]) + int(first["count"])
			last2["len"] = float(last2["len"]) + float(first["len"])
			runs.remove_at(0)
	res["sides"] = runs.size()

	# ② 六段等长
	var uni := runs.size() == 6
	if uni:
		var l0: float = float(runs[0]["len"])
		var c0: int = int(runs[0]["count"])
		for r in runs:
			if absf(float(r["len"]) - l0) > 1e-4 or int(r["count"]) != c0:
				uni = false
	res["uniform_sides"] = uni

	# ③ 六段方向等差 60° 走满一圈
	var six := uni
	if six:
		var ds: Array[float] = []
		for r in runs:
			ds.append(fposmod(float(r["dir"]), 180.0))
		ds.sort()
		# 折到 [0,180) 后，正六边形的边方向 = {0, 60, 120} 各出现两次
		var want: Array[float] = [0.0, 60.0, 120.0]
		for w: float in want:
			var hit := 0
			for d2: float in ds:
				if absf(fposmod(d2 - w + 90.0, 180.0) - 90.0) < 1.0:
					hit += 1
			if hit != 2:
				six = false
	res["six_dirs"] = six

	res["is_hex"] = uni and six and cycles.size() == 1
	print("[hex] 边界环：顶点 %d | 环 %d | 同向段 %d | 各段等长 %s | 方向谱 {0,60,120}×2 %s | 正六边形 %s" % [
		n, cycles.size(), runs.size(), "✓" if uni else "✗", "✓" if six else "✗",
		"✓" if res["is_hex"] else "✗"])
	if not res["is_hex"]:
		var txt := ""
		for r in runs:
			txt += "%.0f°×%d " % [float(r["dir"]), int(r["count"])]
		print("[hex] 实际同向段：", txt)
	return res


# ==================== 雪花棋盘（Ammann-Beenker 密铺：45° 菱形 + 正方形） ====================
##
## **几何构造（de Bruijn 四格网对偶，octagrid）**：4 族平行线 L_k: n_k·x = γ + m，
## 法向 n_k = (cos45°·k, sin45°·k)。对偶顶点 = 胞指标与法向的**线性组合** v(K) = ΣK_m·n_m
##（与 P3 五格网同一套机制，见 _pentagrid_rhombi；4 条法向 Q-线性无关 → 映射天然单射，
## 不需要五格网那条「宽 5 条带窗」）。族号差决定瓷砖形状：
## posmod(j−i,4) ∈ {1,3} → **45°/135° 胖菱形**；== 2 → **正方形**；所有边等长 = 1。
##
## **雪花从哪来**：等相位（4 族 γ 相同）→ 网格关于原点**严格 8 重旋转对称**；
## 且 γ = −0.5 时原点的条带指标 = floor(0−γ) = 0 → 中央胞恰为 (0,0,0,0)，
## 等相位下它是 4 条等宽条带之交 = **正八边形胞**，其对偶顶点 v(0) = 0 上
## **8 块 45° 菱形锐角共点（8×45°=360°）＝一朵完整雪花**（盘心），相邻雪花之间由正方形搭桥。
##（γ≡+0.5 与 −0.5 是同一张线网，只是胞编号平移；取 −0.5 是为了让雪花尖正好落在原点。）
##
## **选区（圆窗）**：只收「瓷砖中心（= 网格交点）落在 |p| ≤ R 内」的瓷砖，
## R = 0.75·n（n = 层数）。实测格数阶梯 n=3/5/6 → 72/200/296（自检钉死）。
## 圆窗 × 8 重对称网格 → 外轮廓**严格 45° 旋转对称**（自检钉死）。

## AB 四格网相位：4 族全部 −0.5（见上：对称性 + 盘心雪花尖的双重来源）
const _AB_GAMMA: float = -0.5
## 层数 n → 圆窗半径：R = _AB_R_PER_N·n + _AB_R_BASE
const _AB_R_PER_N: float = 0.75
const _AB_R_BASE: float = 0.0


## de Bruijn 四格网（octagrid）→ Ammann-Beenker 密铺 ——「按密铺规则造盘」的核心。
## 与 _pentagrid_rhombi（P3 五格网）同一套对偶机制，差别只有三点：
##   - 4 族平行线 L_k: n_k·x = γ + m，n_k = (cos45°·k, sin45°·k)（k=0..3）；
##   - 4 条法向 Q-线性无关（Q(ζ₈) 的次数恰为 4）→ 对偶映射 v(K)=ΣK_m·n_m **天然单射**，
##     不需要五格网那条「宽 5 条带窗」去堵 (1,1,1,1,1) 核——那是 Σζ^k=0 特有的关系；
##   - 瓷砖形状由族号差决定：posmod(j−i,4) ∈ {1,3} → 45°/135° 胖菱形；== 2 → **正方形**。
## 交点 p = L_i∩L_j 对应**恰好一块**瓷砖：四角 = p 两侧 4 胞的对偶点，按**环序**
## (0,0)→(1,0)→(1,1)→(0,1) 登记 —— 顺序错了会把对角当边（蝴蝶结），装配必然碎裂
##（详见五格网同款注释）。边向量 = ±n_k → 所有边等长（=1）且垂直于对应网格线。
## 奇异网格（三线共点）在 γ=−0.5 下可证**不存在**（任意三族联立都会逼出
## √2·整数 = 整数 的矛盾）；随机 γ 下它是 γ 空间里的**零测集**（三条线在实平面上共点
## 要恰好解出整数线号），实际遇不到。1e-9 防御照留，并按 "singular" 报数给自检盯着。
## 返回 {"tiles": [{vs: [4 Vector2 环序], sq: 是否正方形}], "singular": 被跳过的奇异交点数}。
func _octagrid_tiles(radius: float, gammas: Array = [], wc: Vector2 = Vector2.ZERO, rot: float = 0.0) -> Dictionary:
	# 相位 γ：固定盘传空 → 4 族全 −0.5（等相位 = 8 重对称 + 盘心一朵雪花）；
	# 随机盘传随机 γ（见 _random_octagrid_gammas）。wc = 取景圆心（随机档会偏心），
	# rot = 整盘的随机朝向（只转法向，对偶 v=ΣK·n 跟着转 → 整张盘一起转）。
	var gs: Array[float] = []
	for k in 4:
		gs.append(float(gammas[k]) if gammas.size() >= 4 else _AB_GAMMA)
	var norms: Array[Vector2] = []
	for k in 4:
		var a: float = TAU * float(k) / 8.0 + rot
		norms.append(Vector2(cos(a), sin(a)))

	var out: Array = []
	var singular_n := 0
	var margin: float = 1.0   # 线号扫描余量：圆窗外沿再多扫一格，交给下面的 |p−wc|≤R 精确剔除
	for i in 4:
		for j in range(i + 1, 4):
			var det: float = norms[i].cross(norms[j])
			# 形状由族号差决定（见函数头注释）：隔一族 90° → 正方形，相邻/隔两族 → 45° 菱形
			var square: bool = posmod(j - i, 4) == 2
			# 圆心偏到 wc 后，第 i 族的线号范围跟着平移：|n_i·(p−wc)| ≤ R → n_i·p ∈ [n_i·wc − R, n_i·wc + R]
			var ci: float = norms[i].dot(wc)
			var cj: float = norms[j].dot(wc)
			var i_lo: int = int(ceil(ci - radius - margin - gs[i]))
			var i_hi: int = int(floor(ci + radius + margin - gs[i]))
			var j_lo: int = int(ceil(cj - radius - margin - gs[j]))
			var j_hi: int = int(floor(cj + radius + margin - gs[j]))
			for mi in range(i_lo, i_hi + 1):
				for mj in range(j_lo, j_hi + 1):
					var bi: float = float(mi) + gs[i]
					var bj: float = float(mj) + gs[j]
					var p := Vector2(
						(bi * norms[j].y - bj * norms[i].y) / det,
						(bj * norms[i].x - bi * norms[j].x) / det)
					if (p - wc).length() > radius:
						continue   # 瓷砖中心在圆窗外 → 不要
					# 其余 2 族的胞指标；若恰落在另一族线上（三线共点 = 奇异）→ 跳过（防御，
					# γ=−0.5 下数学上不存在，见函数头）
					var base: Array = []
					var singular := false
					for m in 4:
						if m == i or m == j:
							continue
						var t: float = norms[m].dot(p) - gs[m]
						if absf(t - roundf(t)) < 1e-9:
							singular = true
							break
						base.append(int(floor(t)))
					if singular:
						singular_n += 1
						continue
					# 交点两侧 4 个胞的对偶顶点（i/j 族各取 m-1 / m 两档），
					# **环序 (0,0)→(1,0)→(1,1)→(0,1)**（与五格网同款，防蝴蝶结）
					var quad: Array[Vector2] = []
					for combo in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var ki: int = mi - 1 + int(combo[0])
						var kj: int = mj - 1 + int(combo[1])
						var v := Vector2.ZERO
						var q := 0
						for m2 in 4:
							var km: int
							if m2 == i:
								km = ki
							elif m2 == j:
								km = kj
							else:
								km = int(base[q])
								q += 1
							v += float(km) * norms[m2]   # 线性对偶；同一胞必算出逐位相同的 float
						quad.append(v)
					out.append({"vs": [quad[0], quad[1], quad[2], quad[3]], "sq": square})
	return {"tiles": out, "singular": singular_n}


## 雪花盘生成：固定档 = 等相位 γ=−0.5（盘心一朵完整雪花），层数 n 决定圆窗半径 R=0.75n。
## 随机档（尺寸槽位 = RANDOM）改走 _generate_snowflake_random()。
func generate_snowflake() -> void:
	if _is_random_board():
		_generate_snowflake_random()
		return
	_snow_clear()
	var radius: float = _AB_R_PER_N * float(_snow_r_actual) + _AB_R_BASE
	var n_sq: int = _snow_build([], Vector2.ZERO, radius, 0.0)
	_cube_star_tiles = _snow_star_current()
	print("生成雪花棋盘(A-B密铺) 层数 ", _snow_r_actual, "，瓷砖：", tiles.size(),
		"（落子格，其中正方形桥 ", n_sq, " 块），星位：", _cube_star_tiles.size())

## 清空 + 置「当前是雪花盘」标志（固定档与随机档共用，保证两条路径状态完全一致）
func _snow_clear() -> void:
	vertices.clear()
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()
	_cube_star_tiles.clear()
	_is_cube = false
	_is_kite = false
	_is_snow = true
	_is_hat = false

## octagrid → 编号排序 → 顶点去重 → 配色 → 邻接 → 空盘（固定档与随机档**共用这一段**）。
## 返回正方形桥的块数。
## 编号稳定性：先按瓷砖中心到原点距离（量化 1/8 格）、再按极角排序，
## 同一组参数恒定同一编号（联机快照 / 复现性依赖这一点）。
## ⚠️ 星位不在这里选：随机档还要过一遍 _prune_to_largest_component()，索引会重排，
##    必须在 prune 之后用 _snow_star_current() 选（固定档也走同一函数，口径一致）。
func _snow_build(gammas: Array, wc: Vector2, radius: float, rot: float = 0.0) -> int:
	var result: Dictionary = _octagrid_tiles(radius, gammas, wc, rot)
	_snow_last_singular = int(result["singular"])
	var raw: Array = result["tiles"]               # {vs: Array[Vector2]（环序）, sq: bool}
	for t in raw:
		var vs: Array = t["vs"]
		var c: Vector2 = ((vs[0] as Vector2) + (vs[2] as Vector2)) * 0.5
		t["ring"] = int(roundf(c.length() * 8.0))
		t["ang"] = c.angle()
	raw.sort_custom(func(x, y) -> bool:
		if int(x["ring"]) != int(y["ring"]):
			return int(x["ring"]) < int(y["ring"])
		return (x["ang"] as float) < (y["ang"] as float))

	var vert_map: Dictionary = {}
	var vlist: Array[Vector2] = []
	var n_sq := 0
	for r2 in raw:
		var ids: Array[int] = []
		for v2: Vector2 in r2["vs"]:
			ids.append(_kite_vid(v2.x, v2.y, vert_map, vlist))
		tiles.append(ids)
		# 正方形桥 = fat_color（蓝灰），45° 胖菱形 = thin_color（浅黄）—— 雪花/桥一眼可辨
		var sq: bool = bool(r2["sq"])
		if sq:
			n_sq += 1
		tile_colors.append(fat_color if sq else thin_color)
	vertices = vlist

	# 邻接：共享一条边（两端顶点相同）的两块互为邻居（与筝形同一套 edge_map 法）
	adjacency.resize(tiles.size())
	for i in range(tiles.size()):
		adjacency[i] = []
	var edge_map: Dictionary = {}
	for i in range(tiles.size()):
		var tt: Array = tiles[i]
		for k2 in range(4):
			var v1i: int = tt[k2]
			var v2i: int = tt[(k2 + 1) % 4]
			var ekey: String = "%d,%d" % [mini(v1i, v2i), maxi(v1i, v2i)]
			if not edge_map.has(ekey):
				edge_map[ekey] = []
			(edge_map[ekey] as Array).append(i)
	for ekey2 in edge_map:
		var own: Array = edge_map[ekey2]
		if own.size() == 2:                       # 内部边：恰好两块共享；边界边只有一块
			adjacency[own[0]].append(own[1])
			adjacency[own[1]].append(own[0])

	board.clear()
	for i in range(tiles.size()):
		board[i] = Stone.EMPTY
	return n_sq

## 雪花盘「随机」档（2026-09-16 起）：**按密铺规则现造一张全新的 A-B 密铺**，
## 而不是「拿固定那张雪花盘换个窗口切」—— 后者每局的局部拼花完全一样，一眼看穿。
##
## 三个随机源（比彭罗斯随机档多两个）：
##   ① **4 个相位 γ**（真·随机源）：每组 γ 决定一整张结构不同的合法 A-B 密铺
##      （前 3 个自由，第 4 个按 de Bruijn 和条件反解，见 _random_octagrid_gammas）；
##   ② **整盘朝向 rot**：法向整体转 θ → 对偶 v=ΣK·n 跟着转 → 每局盘面朝向不同；
##   ③ **取景偏心 wc**：圆窗圆心沿随机方向挪开 偏心系数×半径（用户要的「偏移量放大」，
##      由 @export random_window_offset 实时调）。
## 圆窗半径仍由 _fit_octagrid_radius() 二分到目标格数（random_target_tiles ± jitter），
## 切完再过 _prune_to_largest_component() 剔掉边界孤块。
func _generate_snowflake_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rand_seed
	var target: int = maxi(20, random_target_tiles + rng.randi_range(-random_tile_jitter, random_tile_jitter))
	_rand_target = target
	var gammas: Array = _random_octagrid_gammas(rng)
	var rot: float = rng.randf() * (TAU / 8.0)      # 密铺 8 重对称 → 转 45° 即覆盖全部不同朝向

	# 半径：先按同心圆窗估一次，定出偏心量后再带着偏心重估一次（收敛到目标格数）
	var radius: float = _fit_octagrid_radius(gammas, Vector2.ZERO, target, rot)
	var dir := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if dir.length_squared() < 1e-9:
		dir = Vector2(1.0, 0.0)
	var wc: Vector2 = dir.normalized() * (random_window_offset * radius)
	radius = _fit_octagrid_radius(gammas, wc, target, rot)

	_snow_clear()
	var n_sq: int = _snow_build(gammas, wc, radius, rot)
	var dropped := _prune_to_largest_component()
	_center_board_on_origin()          # 随机 γ 会把整盘平移走（见函数注释），星位/判据都以原点为准
	_cube_star_tiles = _snow_star_current()
	print("生成随机雪花棋盘(四格网) 种子=", _rand_seed, " 目标=", target, " 实际=", tiles.size(),
		" 落子格（半径=", snappedf(radius, 0.01), " 偏心=", snappedf(wc.length(), 0.01),
		" 朝向=", snappedf(rad_to_deg(rot), 1), "° 正方形桥 ", n_sq,
		" 剔掉孤块=", dropped, "），星位：", _cube_star_tiles.size())

## 四格网随机相位：前 3 个自由随机，第 4 个按 de Bruijn「和条件」Σγ ≡ 0 (mod 1) 反解。
## 固定盘 γ=(−0.5,−0.5,−0.5,−0.5) 的 Σγ = −2 ≡ 0 —— 守住同一个条件，随机盘与固定盘就落在
## **同一个 A-B LI 类**（局部构型谱一致），只是抽到了这张无穷密铺里的另一块补丁。
##（对偶本身对任意 γ 都单射，见 _octagrid_tiles；这条只管「是不是同一类密铺」。）
func _random_octagrid_gammas(rng: RandomNumberGenerator) -> Array:
	var gs: Array = []
	var s := 0.0
	for _k in 3:
		var g: float = rng.randf()
		gs.append(g)
		s += g
	gs.append(posmod(-s, 1.0))
	return gs

## 二分搜索「窗口内格数最接近 target」的半径（格数随半径单调不减 → 可二分）。
## 四格网是按需生成的（半径直接决定枚举范围），每轮重新生成再数，与 _fit_pentagrid_radius 同法。
func _fit_octagrid_radius(gammas: Array, wc: Vector2, target: int, rot: float = 0.0) -> float:
	var lo := 0.5
	var hi := 20.0
	for _b in 26:
		var mid: float = (lo + hi) * 0.5
		if (_octagrid_tiles(mid, gammas, wc, rot)["tiles"] as Array).size() < target:
			lo = mid
		else:
			hi = mid
	# hi = 刚好够、lo = 差一点；取离目标更近的那个
	var n_hi: int = (_octagrid_tiles(hi, gammas, wc, rot)["tiles"] as Array).size()
	var n_lo: int = (_octagrid_tiles(lo, gammas, wc, rot)["tiles"] as Array).size()
	return hi if absi(n_hi - target) <= absi(n_lo - target) else lo

## 瓷砖的「快速中心」：**四边形用对角中点**（与旧版逐位一致，绝不改已有盘的观感），
## 其它边形用顶点平均 —— 帽子盘是 13 边形，对角中点没有意义。
## 只被 _center_board_on_origin() 与 _snow_star_current() 用来定位「盘心 / 中心星位」。
func _tile_center_quick(vs: Array) -> Vector2:
	if vs.size() == 4:
		return ((vertices[vs[0]] as Vector2) + (vertices[vs[2]] as Vector2)) * 0.5
	var c := Vector2.ZERO
	for idx in vs:
		c += vertices[idx]
	return c / float(maxi(vs.size(), 1))


## 把整张盘**平移到「瓷砖中心的重心 = 原点」**（只平移，不改形状）。
##
## 为什么随机档必须做：对偶 v ≈ 2p − Σγ_m·n_m —— 随机 γ 那一项是**整盘的常量平移**，
## 加上取景偏心 wc，盘心会被推到离原点好几个单位远的地方。不归心的话：
##   · 星位按「绕原点 6 等分扇区」取（_snow_star_current），会有扇区整片踩空 → 星位不足 7；
##   · 盘面在屏幕上也会偏（_adapt_to_screen 按包围盒居中，但原点不在盘心会影响一切以原点
##     为基准的判据）。固定盘 8 重对称 → 重心本就在原点，这步是恒等变换。
func _center_board_on_origin() -> void:
	if tiles.size() == 0 or vertices.size() == 0:
		return
	var c := Vector2.ZERO
	for i in tiles.size():
		c += _tile_center_quick(tiles[i])
	c /= float(tiles.size())
	if c.length_squared() < 1e-12:
		return
	for i in vertices.size():
		vertices[i] = (vertices[i] as Vector2) - c

## 从**当前 tiles/vertices** 选星位（离中心最近的 1 块 + 6 个 60° 扇区里最远的各 1 块 → 恒 7）。
## 盘面无关于棋盘类型（四边形与 n 边形通用），雪花盘与帽子盘共用。
## 随机档必须 prune 之后再选（索引会重排），固定档走同一个函数，两边口径一致。
func _snow_star_current() -> Array[int]:
	var best: Array[int] = [-1, -1, -1, -1, -1, -1]
	var best_d: Array[float] = [-1.0, -1.0, -1.0, -1.0, -1.0, -1.0]
	var center_id := -1
	var center_d := INF
	for k in tiles.size():
		var tt: Array = tiles[k]
		if tt.size() < 3:
			continue
		var c: Vector2 = _tile_center_quick(tt)
		var d: float = c.length()
		if d < center_d - 1e-9:
			center_d = d
			center_id = k
		var sec: int = posmod(int(roundi((c.angle() + PI) / (PI / 3.0))), 6)
		if d > best_d[sec]:
			best_d[sec] = d
			best[sec] = k
	var pts: Array[int] = []
	if center_id >= 0:
		pts.append(center_id)
	for i in 6:
		if best[i] >= 0 and best[i] != center_id:
			pts.append(best[i])
	return pts


## 自检（--snowtest）：Ammann-Beenker 雪花盘的数学健全性。
##   ① 每块瓷砖恰为两种之一（边长全 1）：45°/135° 胖菱形（角谱 45×2 + 135×2、
##      面积 = sin45° = √2/2）或正方形（角谱 90×4、面积 1）—— 出现第三种形状即失败；
##   ② 无缝无叠：一条边至多被 2 块共享；**正方形必须存在**（雪花之间的桥，本盘的招牌构型）；
##   ③ 顶点价谱：8 块共点 = 雪花尖，**原点必须是一朵**（中央正八边形胞的对偶顶点），
##      任何顶点价 ≤ 8（4 族胞至多八边形）；
##   ④ 装配：全盘连通、邻接 1~4、星位 7、两次生成同指纹、**边界 45° 旋转对称**
##      （圆窗 × 8 重对称网格 → 外轮廓必须严格对称，抓「某一边缺块/多块」的不规则）；
##   ⑤ 层数阶梯：迷你 n=3 → 72 / 标准 n=5 → 200 / 加强 n=6 → 296（圆窗实测钉死）；
##   ⑥ 随机档（2026-09-16 起）：8 颗种子各造一张 → 互不相同 / 同种子复现 / 连通 /
##      格数落在目标带内 / 长宽比 ≤1.6 且填充率 ≥0.55 / 仍是「菱形 + 正方形桥」二选一 /
##      奇异交点 = 0（随机 γ 下三线共点是零测集，出现即说明相位退化）/ 星位 7。
## 逐块体检**当前盘**：每块必须是边长 1 的 45°/135° 胖菱形或正方形，第三种形状 = 生成器错。
## 固定档与随机档共用（判据必须一致，否则随机档出畸形砖没人发现）。
## 返回 {bad_quad: 非四边形, bad_len: 边长≠1, bad_shape: 角谱/面积不符, rhomb: 菱形数, sq: 正方形数}。
func _snow_shape_audit() -> Dictionary:
	var area_rhomb: float = 0.5 * sqrt(2.0)     # 45° 胖菱形（边长 1）面积 = sin45°
	var area_square: float = 1.0
	var bad_quad := 0
	var bad_len := 0
	var bad_shape := 0
	var n_rhomb := 0
	var n_sq := 0
	for i in range(tiles.size()):
		var tt: Array = tiles[i]
		if tt.size() != 4:
			bad_quad += 1
			continue
		var poly: Array[Vector2] = []
		for k in 4:
			poly.append(vertices[tt[k]])
		var L: Array[float] = []
		for k in 4:
			L.append(poly[k].distance_to(poly[(k + 1) % 4]))
		for k in 4:
			if absf(L[k] - 1.0) > 1e-4:
				bad_len += 1
				break
		# 角谱 + 面积 → 二选一：正方形（90×4）或 45° 胖菱形（45×2 + 135×2）
		var n45 := 0
		var n90 := 0
		var n135 := 0
		var cs := 0.0
		for k in 4:
			var p0: Vector2 = poly[(k + 3) % 4]
			var p1: Vector2 = poly[k]
			var p2: Vector2 = poly[(k + 1) % 4]
			var v1: Vector2 = (p0 - p1).normalized()
			var v2: Vector2 = (p2 - p1).normalized()
			var ang: float = rad_to_deg(acos(clampf(v1.dot(v2), -1.0, 1.0)))
			if absf(ang - 45.0) < 0.5:
				n45 += 1
			elif absf(ang - 90.0) < 0.5:
				n90 += 1
			elif absf(ang - 135.0) < 0.5:
				n135 += 1
			cs += poly[k].cross(poly[(k + 1) % 4])
		var area := absf(cs) * 0.5
		if n90 == 4 and n45 == 0 and n135 == 0:
			n_sq += 1
			if absf(area - area_square) > 1e-4:
				bad_shape += 1
		elif n45 == 2 and n135 == 2 and n90 == 0:
			n_rhomb += 1
			if absf(area - area_rhomb) > 1e-4:
				bad_shape += 1
		else:
			bad_shape += 1
	return {"bad_quad": bad_quad, "bad_len": bad_len, "bad_shape": bad_shape,
		"rhomb": n_rhomb, "sq": n_sq}

func _snow_self_test() -> void:
	var ok := true

	# ①②③ 小盘（固定档 n=3 = 72 格）逐块查几何 + 正方形桥 + 盘心雪花
	# ⚠️ 不能再靠 RANDOM 槽位取「迷你」：2026-09-16 起雪花 RANDOM = 真随机档，这里直接钉层数
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	_snow_r_actual = 3
	generate_snowflake()

	# 逐块体检抽成 _snow_shape_audit()（随机档那段复用同一个判据，见下）
	var au: Dictionary = _snow_shape_audit()
	var bad_quad: int = int(au["bad_quad"])
	var bad_len: int = int(au["bad_len"])
	var bad_shape: int = int(au["bad_shape"])
	var n_rhomb: int = int(au["rhomb"])
	var n_sq: int = int(au["sq"])
	if bad_quad > 0 or bad_len > 0 or bad_shape > 0 or n_sq == 0:
		ok = false
	print("[snowtest] 瓷砖：查 %d 块 | 胖菱形 %d | 正方形桥 %d | 非四边形 %d | 边长≠1 %d | 形状/面积不符 %d %s" % [
		tiles.size(), n_rhomb, n_sq, bad_quad, bad_len, bad_shape,
		"✓" if bad_quad == 0 and bad_len == 0 and bad_shape == 0 and n_sq > 0 else "✗"])

	# ② 无重叠：一条边至多 2 块共享
	var edge_count: Dictionary = {}
	for tt2 in tiles:
		for k2 in 4:
			var key: String = "%d,%d" % [mini(tt2[k2], tt2[(k2 + 1) % 4]), maxi(tt2[k2], tt2[(k2 + 1) % 4])]
			edge_count[key] = int(edge_count.get(key, 0)) + 1
	var over := 0
	for key2 in edge_count:
		if int(edge_count[key2]) > 2:
			over += 1
	if over > 0:
		ok = false
	print("[snowtest] 边共享：重叠边（≥3 块）=%d %s | 边界边（1 块）=%d" % [
		over, "✓" if over == 0 else "✗", n_border_edges(edge_count)])

	# ③ 顶点价谱：8 块共点 = 雪花尖（原点必须是一朵）；任何顶点 ≤ 8
	var share: Dictionary = {}
	for tt3 in tiles:
		for v3 in tt3:
			share[int(v3)] = int(share.get(int(v3), 0)) + 1
	var n_star8 := 0
	var bad_share := 0
	for vid in share:
		var m: int = int(share[vid])
		if m == 8:
			n_star8 += 1
		elif m > 8:
			bad_share += 1
	var origin_val := -1
	for vid2 in share:
		if (vertices[int(vid2)] as Vector2).length_squared() < 1e-12:
			origin_val = int(share[vid2])
			break
	if n_star8 < 1 or bad_share > 0 or origin_val != 8:
		ok = false
	print("[snowtest] 顶点谱：雪花尖(8块共点)=%d | 盘心价=%d（期望 8=原点一朵完整雪花）| 越界(>8块)=%d %s" % [
		n_star8, origin_val, bad_share,
		"✓" if n_star8 >= 1 and bad_share == 0 and origin_val == 8 else "✗"])

	# ⑤ 三固定档循环（迷你 3 / 标准 5 / 加强 6）—— 层数直接钉 _snow_r_actual
	#（RANDOM 槽位现在是随机档，不能再拿它当「迷你」用）
	var ladder := [
		{"size": GameConfig.STANDARD, "name": "迷你", "n": 3, "tiles": 72},
		{"size": GameConfig.STANDARD, "name": "标准", "n": 5, "tiles": 200},
		{"size": GameConfig.ENHANCED, "name": "加强", "n": 6, "tiles": 296},
	]
	for ld in ladder:
		GameConfig.board_size = ld["size"]
		_apply_board_size(ld["size"])
		_snow_r_actual = int(ld["n"])
		generate_snowflake()
		if tiles.size() != int(ld["tiles"]):
			ok = false
			print("[snowtest] ", ld["name"], "盘格数不符：", tiles.size(), "（期望 ", ld["tiles"], "）")
		if not _all_tiles_connected():
			ok = false
			print("[snowtest] ", ld["name"], "盘不连通（连通块 ", _component_count(), "）")
		if n_star8_of_current() < 1:
			ok = false
			print("[snowtest] ", ld["name"], "盘没有雪花尖（8 块共点顶点 = 0）")
		var min_adj := 99
		var max_adj := 0
		for i2 in range(tiles.size()):
			max_adj = maxi(max_adj, adjacency[i2].size())
			min_adj = mini(min_adj, adjacency[i2].size())
		if min_adj < 1 or max_adj > 4:
			ok = false
			print("[snowtest] ", ld["name"], "盘邻接越界：min=", min_adj, " max=", max_adj, "（期望 1~4）")
		if _cube_star_tiles.size() != 7:
			ok = false
			print("[snowtest] ", ld["name"], "盘星位数不符：", _cube_star_tiles.size(), "（期望 7）")
		var fp: int = _board_fingerprint()
		generate_snowflake()
		if _board_fingerprint() != fp:
			ok = false
			print("[snowtest] ", ld["name"], "盘两次生成不一致（固定盘必须恒定）")
		var asym := _snow_symmetry_defects()
		if asym > 0:
			ok = false
			print("[snowtest] ", ld["name"], "盘边界不对称：", asym, " 个顶点旋转 45° 后无对应")
		print("[snowtest] ", ld["name"], "盘（n=%d）：格数 %d %s | 星位 %d | 邻接 %s | 复现 ✓ | 边界 45° 对称 %s" % [
			int(ld["n"]), tiles.size(),
			"✓" if tiles.size() == int(ld["tiles"]) else "✗", _cube_star_tiles.size(),
			_adj_histogram(), "✓" if asym == 0 else "✗"])

	# ⑥ 随机档：8 颗种子各造一张 —— 互不相同 / 同种子复现 / 连通 / 格数在目标带内 /
	#    形状不扁不空 / 仍是「菱形 + 正方形桥」二选一 / 奇异交点 = 0 / 星位 7
	GameConfig.board_size = GameConfig.RANDOM
	_apply_board_size(GameConfig.RANDOM)
	var rfps: Dictionary = {}
	var rlo := 999999
	var rhi := 0
	var r_band := 0
	var r_conn := 0
	var r_rep := 0
	var r_shape := 0
	var r_geom := 0
	var r_sq := 0
	var r_sing := 0
	var r_star := 0
	var r_star_lo := 99
	var r_star_hi := 0
	var r_aspect := 0.0
	var r_fill := 1.0
	for s in 8:
		_rand_seed = 3000 + s * 104729
		generate_snowflake()
		rlo = mini(rlo, tiles.size())
		rhi = maxi(rhi, tiles.size())
		if absi(tiles.size() - random_target_tiles) > random_tile_jitter + 6:
			r_band += 1
		if not _all_tiles_connected():
			r_conn += 1
		var rfp: int = _board_fingerprint()
		rfps[rfp] = true
		generate_snowflake()                     # 同种子再生成一次 → 指纹必须一致（联机依赖）
		if _board_fingerprint() != rfp:
			r_rep += 1
		var rm: Array[float] = _rand_shape_metrics()
		r_aspect = maxf(r_aspect, rm[0])
		r_fill = minf(r_fill, rm[1])
		if rm[0] > 1.6 or rm[1] < 0.55:
			r_shape += 1
		var rau: Dictionary = _snow_shape_audit()
		if int(rau["bad_quad"]) + int(rau["bad_len"]) + int(rau["bad_shape"]) > 0:
			r_geom += 1
		if int(rau["sq"]) == 0:
			r_sq += 1
		if _snow_last_singular != 0:
			r_sing += 1
		r_star_lo = mini(r_star_lo, _cube_star_tiles.size())
		r_star_hi = maxi(r_star_hi, _cube_star_tiles.size())
		if _cube_star_tiles.size() != 7:
			r_star += 1
	if rfps.size() != 8 or r_band + r_conn + r_rep + r_shape + r_geom + r_sq + r_sing + r_star > 0:
		ok = false
	print("[snowtest] 随机档：8 颗种子 | 格数 %d~%d %s | 互不相同 %d/8 %s | 复现 %s | 连通 %s | 形状(长宽比≤%.2f/填充≥%.2f) %s | 几何 %s | 正方形桥 %s | 奇异交点 %s | 星位 %d~%d %s" % [
		rlo, rhi, "✓" if r_band == 0 else "✗", rfps.size(), "✓" if rfps.size() == 8 else "✗",
		"✓" if r_rep == 0 else "✗", "✓" if r_conn == 0 else "✗", r_aspect, r_fill,
		"✓" if r_shape == 0 else "✗", "✓" if r_geom == 0 else "✗", "✓" if r_sq == 0 else "✗",
		"✓" if r_sing == 0 else "✗", r_star_lo, r_star_hi, "✓" if r_star == 0 else "✗"])
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	print("[snowtest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()


## 当前盘「被恰好 8 块共享的顶点」数（= 完整雪花尖数，自检用）
func n_star8_of_current() -> int:
	var share: Dictionary = {}
	for tt in tiles:
		for v in tt:
			share[int(v)] = int(share.get(int(v), 0)) + 1
	var n := 0
	for vid in share:
		if int(share[vid]) == 8:
			n += 1
	return n


## 当前盘边界（只被 1 块占用的边）的端点集绕原点旋转 45° 后的不对称数（自检用）：
## 每个边界顶点旋转 45° 后必须仍落在边界顶点集里（容差 1e-6）。
## 等相位 octagrid 网格 + 圆窗 → 外轮廓天然 8 重旋转对称——任何一边缺块/多块都会在这里暴露。
func _snow_symmetry_defects() -> int:
	var owner: Dictionary = {}
	for i in range(tiles.size()):
		var tt: Array = tiles[i]
		for k in 4:
			var ekey: String = "%d,%d" % [mini(tt[k], tt[(k + 1) % 4]), maxi(tt[k], tt[(k + 1) % 4])]
			owner[ekey] = int(owner.get(ekey, 0)) + 1
	var bpts: Array[Vector2] = []
	for ekey2 in owner:
		if int(owner[ekey2]) != 1:
			continue
		for part in (ekey2 as String).split(","):
			var p: Vector2 = vertices[int(part)]
			var dup := false
			for q in bpts:
				if q.distance_squared_to(p) < 1e-12:
					dup = true
					break
			if not dup:
				bpts.append(p)
	var asym := 0
	for p2 in bpts:
		var q2: Vector2 = p2.rotated(TAU / 8.0)
		var hit := false
		for r in bpts:
			if r.distance_squared_to(q2) < 1e-10:
				hit = true
				break
		if not hit:
			asym += 1
	return asym


# ==================== 帽子棋盘（爱因斯坦瓦片 / the hat，非周期单瓦片） ====================
##
## 每个落子格 = **一整块帽子瓦片**（aperiodic monotile；Smith / Myers / Kaplan / Goodman-Strauss, 2023）。
## 形状：顶点表 14 点，其中一个是共线点 → **13 条有效边**；边长只有两种 —— 8 条 1 与 6 条 √3；
## 内角只有 90° 与 120°（含 2 个 240°、2 个 270° 的**反角**，所以它是凹多边形）。面积 = 8√3。
## 等价说法：它恰好由 **8 块筝形**拼成 —— 正是「筝形棋盘」用的那种筝形（边长比 1 : √3）。
##
## **生成 = H7/H8 替换系统**（论文图 2.11 的 6 条规则，见 `_hat_supers`）：
##   两个原型 —— 单块帽（记 H8）、帽＋其镜像（记 H7）；每层「膨胀」一次：
##     H8' = H8 + 5×H8 + H7        H7' = H8 + 4×H8 + H7
##   实测池规模（取 H8 支）：level 1 → 8 / 2 → 55 / 3 → 377 / 4 → 2584 片。
##
## **取盘 = 池 + BFS 圆底 + 剔叶片修补**（与其它盘的「圆窗裁剪」不同：这里没有可连续调节的参数）：
##   迭代到 level 4（池 2584 片）→ 按**共享边**建池内邻接 → 从种子片 BFS 收 N 片，再把
##   「度数 ≤1 的叶片」反复剔掉并从凹处补回（`_hat_grow_pick()`）。好处：
##     ① 格数**精确可控**（标准 150 / 随机 ≈200 / 加强 310），且**最小邻接度 ≥2**；
##     ② 选区天然连通，不需要 _prune_to_largest_component()；
##     ③ 换种子片 + 整盘朝向 → 随机档每局拿到的是**这张无穷密铺里另一块补丁**。
##   ⚠️ **不能退回「裸 BFS」**（2026-09-19 用户报「边界有一个格子只有一口气」）：BFS 是「按离种子
##      几步切一刀」，而池是 H8 树展平出来的、带**细长触手** → 球的最外那层正好切在触手尖上，
##      触手尖在这张密铺里本来就只有 1 个邻居 → 收进盘的那片**度数 = 1**（初始一口气，
##      唯一邻居一落子它就无气被提）。详见 `_hat_grow_pick()`，自检 ⑤ 带阴性对照把这条钉死。
##   ⚠️ 池必须比目标大出一圈：选区贴着池边界会被削平。实测 level 3 池（377 片）取 310 片时
##      填充率掉到 0.51 < 0.55 门槛，所以默认 level 4（--hattest ⑤ 钉死这一条）。
##
## **几何精度**：坐标用裸 float，但旋转角恒为 30° 的整数倍，且拼接靠「对齐边界点」
## （平移量 = 两个逐位相同的 float 之差 → 拼接点精确重合）。实测 float 版与 ℤ[√3] 精确版
## 逐顶点最大偏差 3.9e-15，远小于顶点去重容差 _KITE_EPS=1e-5（--hattest ① 复核）。
##
## **★★ 踩过的坑（勿回退）：参考实现里有两种旋转约定，方向相反，必须各就各位。**
##   · 造基底瓦片的**边长方向**用 `M^p @ r`（矩阵 × 列向量）= 转 **−30°·p**；
##   · 转**整个多边形**用 `p @ M`（行向量 × 矩阵）= 转 **+30°·p**。
##   若「统一成同一种约定」（看起来更干净），基底瓦片会变成**镜像**，与替换规则的旋转手性
##   不一致 → level 2 起整盘开始重叠（实测：47 片里 69 条边被 3 块共享、134 个 T 型接点）。
##   对应到本文件：`_hat_base()` 用 `rotated(−ANG30·p)`，`_hat_xform()` 用 `rotated(+ANG30·p)`。
const _HAT_ANG30: float = PI / 6.0

## 顶点**合并容差**（见 `_hat_vertex_ids()`）。两头夹出来的实测值（技能脚本 `tiling_diag.py` 可复算）：
## · 同一顶点的两份拷贝**最大偏差**：level 3 = 7.76e-6，**level 4 = 2.39e-5**（量程 ±160 的 float32，几个 ulp）；
## · 合并后**不同**代表点的**最小间距** > 1e-2（在 1e-2 尺度的 3×3 邻域里找不到第二个代表点）。
## → 1e-3 比偏差大 **41.8 倍**（level 4），比代表点间距小 **10 倍以上**，稳落在安全区中间。
## ⚠️ 量「拷贝偏差」时桶径就是量程上限：用 1e-6 的桶去量只能得到 ≤1e-6 的假数（我踩过，别再用
##    「同桶最大点距」当偏差 —— 桶径必须 ≥ 待测量的上界）。
const _HAT_MERGE_TOL: float = 1e-3

## level 3 / level 4 池的**真**顶点数（容差判据下的去重结果）——自检 ③ 拿它当廉价探针。
## 偏大 = 同一顶点被拆开（共享边会丢）；偏小 = 不同顶点被并成一个。改动合并容差/几何必复核。
const _HAT_EXPECT_VERTS: Array = [2530, 16496]

## 帽子的边长序列：(是否走长边 a=1 / 否则短边 b=√3, 角号 p)。方向 = 转 −30°·p（见上面的坑）。
## 前 13 条里 8 条 a、5 条 b，且 **a 边的矢量和恰为 0** → 余量 (0,−b) 正好由「回到起点」那条
## 闭合边（也是 b）补上 → 14 个顶点构成闭合多边形，边长谱 = 8×1 + 6×√3。
const _HAT_EDGES: Array = [
	[true, 12], [true, 10], [false, 1], [false, 11], [true, 8], [true, 10], [false, 7],
	[false, 9], [true, 6], [true, 4], [true, 4], [true, 2], [false, 5],
]

## 替换系统的 6 条规则（论文图 2.11）：[转 30°·p, 子块上用来对齐的点号, 已放块上的点号, 取哪个原型]。
## 每层：以「单帽」起手，依次把 6 块原型块按「子块第 pivot 点 ↦ 上一块第 anchor 点」摆上去。
## 全部 7 块 = H8'；去掉最后摆的那块（tiles[:-1]）= H7'。
const _HAT_RULES: Array = [
	[2, 2, 0, 0], [4, 2, 0, 0], [12, 1, 1, 1],
	[8, 2, 2, 0], [10, 2, 0, 0], [12, 2, 0, 0],
]


## ★★ 爱因斯坦（帽子家族）三档 —— 同一个 `Tile(a, b)` 连续族，**方向序列 / 角谱 / 替换系统全同**，
##   只差两组边长（长边 La 共 8 条、短边 Lb 共 6 条）：
##     · 帽子 Hat     = (1, √3)：面积 8√3        —— 原始论文的 the hat
##     · 海龟 Turtle  = (√3, 1)：面积 10√3       —— 长短边对调（同一族的另一个成员）
##     · 幽灵 Spectre = (1, 1) ：面积 (3+√3)√3 ≈ 8.196 —— 等边 14 边形
##       （论文的 chiral spectre 的**直线版**：它必须靠「只许旋转、不许镜像」才非周期，
##        而我们这套 H7/H8 替换是带镜像的 —— 所以它在这里不是「非周期单瓦片」的严格成员，
##        但**照样是一张合法的边到边密铺**，见下一条的实测结论。）
##
## 「只换边长就能换种类」这条不是推测，已用**独立于本文件的精确算术实现**验证过
##（工作区脚本 `爱因斯坦瓦片参考/_family_kinds.py`，坐标用 ℚ(√3) 精确表示）：
##   · 三档 level 1~4 池全部「无缝无叠 + 无 T 型接点」（边配对直方图里没有 ≥3 次的边）；
##   · 三档的**瓦片数与精确顶点数逐位相同**：level 3 = 377 片 / 2530 点，
##     level 4 = 2584 片 / 16496 点 —— 也就是说拓扑只由**组合粘合**决定、与边长无关；
##   · 三档「不同顶点最小间距」= 1.0 / 1.0 / 0.897 → 对 `_HAT_MERGE_TOL = 1e-3` 都有 ~900 倍余量。
## ⇒ 结论：池生成 / 装配 / 邻接 / 自检**只写一份**，靠这个函数把 (La, Lb) 参数化就够，
##   **绝不要**给每种种类复制一套生成器（那是三份会各自漂移的几何真源）。
func _hat_kind_lengths(kind: int) -> Array[float]:
	var sq3: float = sqrt(3.0)
	match kind:
		GameConfig.HAT_TURTLE:
			return [sq3, 1.0] as Array[float]
		GameConfig.HAT_SPECTRE:
			return [1.0, 1.0] as Array[float]
		_:
			return [1.0, sq3] as Array[float]


## 种类显示名（启动横幅 / 自检输出共用一处，别在各处硬编码字符串）
func _hat_kind_name(kind: int) -> String:
	match kind:
		GameConfig.HAT_TURTLE:
			return "海龟"
		GameConfig.HAT_SPECTRE:
			return "幽灵"
		_:
			return "帽子"


## 三档瓦片的**理论面积**（自检当期望值用）。由两组边长与 14 个顶点唯一确定：
##   帽子 (1,√3)  = 8√3；海龟 (√3,1) = 10√3；幽灵 (1,1) = (3+√3)√3 = 3√3 + 3。
## 三档互不相同 —— 这正是自检 ① 的阴性对照所依赖的（种类参数必须真的进到几何里）。
func _hat_kind_area(kind: int) -> float:
	var sq3: float = sqrt(3.0)
	match kind:
		GameConfig.HAT_TURTLE:
			return 10.0 * sq3
		GameConfig.HAT_SPECTRE:
			return 3.0 * sq3 + 3.0
		_:
			return 8.0 * sq3


## 基础瓦片模板：{pts: 14 点（环序）, bnd: 4 个「准边界点」}。
## bnd 是替换系统用来对齐子块的 4 个关键角（沿用原码取的索引 1/3/9/13）。
## `kind` 只改两组边长（见 `_hat_kind_lengths()`）；方向序列 `_HAT_EDGES` 三档共用 → 角谱恒等。
func _hat_base(kind: int = 0) -> Dictionary:
	var Ls: Array[float] = _hat_kind_lengths(kind)
	var pts: Array[Vector2] = [Vector2.ZERO]
	var cur := Vector2.ZERO
	for e in _HAT_EDGES:
		var L: float = Ls[0] if bool(e[0]) else Ls[1]
		cur += Vector2(L, 0.0).rotated(-_HAT_ANG30 * float(int(e[1]) % 12))
		pts.append(cur)
	var bnd: Array[Vector2] = [pts[1], pts[3], pts[9], pts[13]]
	return {"pts": pts, "bnd": bnd}


## 两个原型：单块瓦片（H8）与「瓦片 + 其镜像」（H7）。
## 镜像 = 沿 x 轴翻转再平移到与原瓦片贴合（原码 `bases()` 的 y/x[0]−y[5] 平移）。
## ⚠️ 这里用的索引 5、以及 `bnd` 的 1/3/9/13 都是**组合口径**，与边长无关 ——
##    三档能共用同一套替换系统正是因为这个（已用精确算术验证，见 `_hat_kind_lengths()` 上方）。
func _hat_bases(kind: int = 0) -> Array:
	var x: Dictionary = _hat_base(kind)
	var xs: Array[Vector2] = x["pts"]
	var y: Array[Vector2] = []
	for i in range(xs.size() - 1, -1, -1):
		y.append(Vector2(xs[i].x, -xs[i].y))
	var d: Vector2 = xs[0] - y[5]
	for i in y.size():
		y[i] += d
	var bnd: Array[Vector2] = [xs[1], xs[3], xs[9], xs[13]]
	var yb: Array[Vector2] = [y[1], y[3], y[9], y[13]]
	return [
		{"pts": xs, "bnd": bnd},
		{"subs": [{"pts": xs.duplicate(), "bnd": bnd}, {"pts": y, "bnd": yb}], "bnd": bnd},
	]


## 把一块子块整体「转 +30°·p 再平移 dx」，返回**全新**节点（绝不改原节点）。
## 叶子（单帽，有 "pts"）与内部节点（复合块，有 "subs"）都走这里 —— 相当于原码的 copy()+mul()+add()。
func _hat_xform(node: Dictionary, p: int, dx: Vector2) -> Dictionary:
	var ang: float = _HAT_ANG30 * float(p % 12)
	var sb: Array = node["bnd"]
	var ob: Array[Vector2] = []
	ob.resize(sb.size())
	for i in sb.size():
		ob[i] = (sb[i] as Vector2).rotated(ang) + dx
	if node.has("pts"):
		var src: Array = node["pts"]
		var out: Array[Vector2] = []
		out.resize(src.size())
		for i in src.size():
			out[i] = (src[i] as Vector2).rotated(ang) + dx
		return {"pts": out, "bnd": ob}
	var subs: Array = node["subs"]
	var ns: Array = []
	ns.resize(subs.size())
	for i in subs.size():
		ns[i] = _hat_xform(subs[i], p, dx)
	return {"subs": ns, "bnd": ob}


## 膨胀一层：返回 [H8', H7']（H7' = H8' 去掉最后摆的那一块）。
func _hat_supers(subs: Array) -> Array:
	var tiles: Array = [subs[0]]
	for r in _HAT_RULES:
		var src: Dictionary = subs[int(r[3])]
		var p: int = int(r[0])
		# 对齐点：把「子块转好之后的 pivot 点」搬到「已摆好的上一块的 anchor 点」上
		var anchor_pt: Vector2 = tiles[tiles.size() - 1]["bnd"][int(r[2])]
		var pivot_pt: Vector2 = (src["bnd"][int(r[1])] as Vector2).rotated(_HAT_ANG30 * float(p % 12))
		tiles.append(_hat_xform(src, p, anchor_pt - pivot_pt))
	# 新块的 4 个准边界点，沿用原码取的「第 1/2/4/6 块的边界点」
	var bnd: Array[Vector2] = [
		tiles[1]["bnd"][3], tiles[2]["bnd"][0], tiles[4]["bnd"][3], tiles[6]["bnd"][0]]
	return [
		{"subs": tiles, "bnd": bnd},
		{"subs": tiles.slice(0, tiles.size() - 1), "bnd": bnd},
	]


func _hat_flatten(node: Dictionary, out: Array) -> void:
	if node.has("pts"):
		out.append(node["pts"])
		return
	for c in node["subs"]:
		_hat_flatten(c, out)


## 迭代 level 层后取 H8 支展平 → 池（每元素 = 一块瓦片的 14 点数组）。
## `kind` 只影响边长，**不影响片数与顶点数**（精确算术已验证，见 `_hat_kind_lengths()` 上方）
## → 池规模阶梯 8 / 55 / 377 / 2584 是三档共用的常数。
func _hat_pool(level: int, kind: int = 0) -> Array:
	var subs: Array = _hat_bases(kind)
	for _i in level:
		subs = _hat_supers(subs)
	var out: Array = []
	_hat_flatten(subs[0], out)
	return out


## ★★ 顶点合并（**容差判据，不是量化键**）。返回 {"ids": 每片一行全局顶点号, "reps": 代表点}。
##
## 为什么不能用「坐标量化成整数键」（2026-09-19 修掉的真 bug —— 用户报的「帽子盘有时候同色
## 相邻棋子判为不连」就是它）：量化键要求同一个顶点的**两份拷贝落进同一个格子**。
## 「步长 ≫ 误差」**并不够** —— 只要顶点真实位置压在格线附近，两份拷贝就会分别四舍五入到相邻
## 两个格子 → 键不等 → 那条共享边从邻接里**静默消失**。而「压在格线附近」的概率恰好是
## **偏差 / 步长**：level 4 偏差 2.39e-5、旧步长 5e-4 → **4.8% 每顶点**，2584 片 × 14 = 3.6 万个
## 顶点里约 1700 个踩线 → 实测「未配对边」量化键报 2126 条、容差判据下真边界只有 1982 条
## → **丢了 132 条内部边**。旧注释写的「16 倍余量」听着很安全，实际错误率接近 5%。
## 池里丢掉的边是**固定的**，可每局的选区落在池的哪一块是随机的 → 有时落在盘内、有时落到选区
## 外 → 表现成「**有时候**出现同色相邻棋子不连」。
##
## 治法和 `_kite_vid()` 一致：先按桶定位，再在 **3×3 邻桶**里做**距离判据**。这样与格线位置
## 无关，不再依赖「误差有多大」这种运气。
##
## 桶号编码：偏移 2^20、进制 2^21 → 坐标量程 ±400（level 4 池约 ±160，bucket 索引 ±4e5）内
## 不会撞键，键值 < 2^42。
func _hat_vertex_ids(pool: Array, tol: float = _HAT_MERGE_TOL) -> Dictionary:
	var inv: float = 1.0 / tol
	var tol2: float = tol * tol
	var reps: Array[Vector2] = []
	var buckets: Dictionary = {}
	var ids: Array = []
	ids.resize(pool.size())
	for i in pool.size():
		var t: Array = pool[i]
		var row: Array[int] = []
		row.resize(t.size())
		for k in t.size():
			var v: Vector2 = t[k]
			var bx: int = int(floor(v.x * inv))
			var by: int = int(floor(v.y * inv))
			var found := -1
			for dx in [-1, 0, 1]:
				if found >= 0:
					break
				for dy in [-1, 0, 1]:
					var bk: int = (bx + dx + 1048576) * 2097152 + (by + dy + 1048576)
					for rid in buckets.get(bk, []):
						if (reps[int(rid)] as Vector2).distance_squared_to(v) <= tol2:
							found = int(rid)
							break
					if found >= 0:
						break
			if found < 0:
				found = reps.size()
				reps.append(v)
				buckets[(bx + 1048576) * 2097152 + (by + 1048576)] = [found]
			row[k] = found
		ids[i] = row
	return {"ids": ids, "reps": reps}


## 池内邻接：共享一条边（两端顶点**合并后同号**）的两片互为邻居。
## 顶点合并走 `_hat_vertex_ids()`（容差判据，与格线无关）。这里是整个帽子盘邻接的**唯一真源**，
## `generate_hat()` 只把池索引重映射到棋盘格号，绝不按坐标再算一遍（见那边的注释）。
## `vd` 可由调用方传入（`generate_hat` 里「邻接」与「装配」要共用同一份合并结果，避免重复计算）。
func _hat_pool_adj(pool: Array, vd: Dictionary = {}) -> Array:
	var vids: Dictionary = vd if not vd.is_empty() else _hat_vertex_ids(pool)
	var vid: Array = vids["ids"]
	var em: Dictionary = {}
	for i in pool.size():
		var t: Array = vid[i]
		var n: int = t.size()
		for k in n:
			var ka: int = int(t[k])
			var kb: int = int(t[(k + 1) % n])
			var key: String = "%d,%d" % [mini(ka, kb), maxi(ka, kb)]
			if not em.has(key):
				em[key] = []
			(em[key] as Array).append(i)
	var adj: Array = []
	adj.resize(pool.size())
	for i in pool.size():
		adj[i] = []
	for key in em:
		var own: Array = em[key]
		if own.size() == 2:      # 内部边恰好两片共享；边界边只有一片 → 不构成邻接
			(adj[own[0]] as Array).append(own[1])
			(adj[own[1]] as Array).append(own[0])
	return adj


func _hat_poly_center(pts: Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / float(maxi(pts.size(), 1))


## 种子试选用的**参考几何**：池的每片形心，**固定用帽子档（Tile(1,√3)）算**，与当前种类无关。
##
## ★ 为什么必须与种类无关：种子试选要按「几何紧致度」挑，而几何量本身随种类变（三种类边长不同）
##   → 若用**当前种类**的形心，三档会各自挑出不同的种子片，自检 ⑥「同种子三档同构」随即变红
##   （2026-09-19 实测）。改成「一律用帽子档的参考形心当评分几何」后，评分对所有种类**逐位相同**，
##   而判据仍是真几何 → 既恢复盘面圆度、又守住 ⑥。
##   池的片数与片序与种类无关（族体检 `hat_family_probe.py` 已证），所以池索引可直接对应。
##   只在池层数变化时重建一次，之后缓存复用（首帧多花一次 _hat_pool，可忽略）。
var _hat_ref_level: int = -1
var _hat_ref_cents: Array[Vector2] = []


func _hat_ref_centers(level: int) -> Array[Vector2]:
	if _hat_ref_level != level or _hat_ref_cents.size() == 0:
		var ref_pool: Array = _hat_pool(level, GameConfig.HAT_HAT)
		var out: Array[Vector2] = []
		out.resize(ref_pool.size())
		for i in ref_pool.size():
			out[i] = _hat_poly_center(ref_pool[i])
		_hat_ref_cents = out
		_hat_ref_level = level
	return _hat_ref_cents


## 从种子片 BFS 收 n_target 片（按共享边邻接）。返回池索引数组（恰好 n_target 个，除非池不够）。
func _hat_bfs_pick(adj: Array, seed: int, n_target: int) -> Array:
	var out: Array = [seed]
	var seen: Dictionary = {seed: true}
	var head := 0
	while head < out.size() and out.size() < n_target:
		var cur: int = out[head]
		head += 1
		for nb in adj[cur]:
			if seen.has(nb):
				continue
			seen[nb] = true
			out.append(nb)
			if out.size() >= n_target:
				break
	return out


## 池邻接的**去重版**：同一条直边被拆成两段时，同一对邻居会被记多次
##（`_hat_pool_adj()` 是按「共享边」逐条记的，**故意不去重**，因为池的「每条边恰 2 片」审计
##  要看原始配对）。但盘面邻接表是用 `.has(j)` 去重的 → **盘面度数是去重口径**。
## ★ 任何「数邻居」的地方都必须用这一版：2026-09-19 实测，剔叶判定按原始条目数，
##   把池里 14 号片的度 1 叶片（真邻居 {8,13,15} 只有 13 在选区内）误算成度 3
##   （13 被记了 3 遍）→ 判定「没有叶片」→ 一次都没剔 → 那片「只有一口气」的格子留在盘面上。
func _hat_adj_dedup(adj: Array) -> Array:
	var out: Array = []
	out.resize(adj.size())
	for i in adj.size():
		var seen: Dictionary = {}
		var row: Array = []
		for nb in adj[i]:
			var u: int = int(nb)
			if seen.has(u):
				continue
			seen[u] = true
			row.append(u)
		out[i] = row
	return out


## 池内「离 seed 几步」的距离场。随机档按**图的步数**限幅要用它 ——
## 不能按坐标比例限：池形状不规则，坐标上的「半径内」可能已经在池外了。
func _hat_dist_field(adj: Array, seed: int) -> Array[int]:
	var dist: Array[int] = []
	dist.resize(adj.size())
	dist.fill(-1)
	dist[seed] = 0
	var q: Array[int] = [seed]
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		for nb in adj[cur]:
			if dist[nb] < 0:
				dist[nb] = dist[cur] + 1
				q.append(nb)
	return dist


## 从已有的 `sel` 继续**贪婪补片**到 n_target 片：每步取「已在选区内邻居数最多」的前沿片；
## 并列时离种子近者优先，再并列取「进入前沿更早」者（→ 同种子逐位复现，**全程无 rng 参与**）。
## `banned` 里的池索引永不入选。
##
## ★ 补片为什么不接着 BFS 走：BFS 会顺着细长触手继续往外，等于把叶片换到更远处 —— 越修越糟。
##   按「最被包围」补，补上来的片天然贴在已选区的凹处，既消掉叶片、又不把盘面拉长。
func _hat_refill(adj: Array, sel: Array, n_target: int, dist: Array[int], banned: Dictionary) -> Array:
	var n: int = adj.size()
	if n <= 0:
		return sel
	var need: int = mini(n_target, n)
	var picked: PackedByteArray = PackedByteArray()
	picked.resize(n)
	picked.fill(0)
	var inflag: PackedByteArray = PackedByteArray()
	inflag.resize(n)
	inflag.fill(0)
	# cnt[v] = v 在选区内已有几个邻居；ord[v] = v 进入前沿的序号（并列判据，避免用池索引）
	var cnt: Array[int] = []
	cnt.resize(n)
	cnt.fill(0)
	var ord: Array[int] = []
	ord.resize(n)
	ord.fill(0)
	var ord_next := 0
	var frontier: Array[int] = []
	var out: Array = []
	for v in sel:
		var iv: int = int(v)
		if iv < 0 or iv >= n or picked[iv] == 1:
			continue
		picked[iv] = 1
		out.append(iv)
	if out.is_empty():
		return out
	for v in out:
		for nb in adj[int(v)]:
			var u: int = int(nb)
			if picked[u] == 1:
				continue
			cnt[u] += 1
			if inflag[u] == 0 and not banned.has(u):
				inflag[u] = 1
				ord[u] = ord_next
				ord_next += 1
				frontier.append(u)
	while out.size() < need and not frontier.is_empty():
		var best_fi := -1
		var best_v := -1
		var bc := -1
		var bd := 0x7FFFFFFF
		var bo := 0x7FFFFFFF
		for fi in frontier.size():
			var v: int = frontier[fi]
			if picked[v] == 1 or cnt[v] <= 0:
				continue          # 已入选 / 被剔除后降到 0（跟选区连都连不上，绝不能收）
			var c: int = cnt[v]
			var dd: int = dist[v] if dist.size() > 0 else 0
			var better := false
			if c > bc:
				better = true
			elif c == bc:
				if dd < bd:
					better = true
				elif dd == bd and ord[v] < bo:
					better = true
			if better:
				bc = c
				bd = dd
				bo = ord[v]
				best_v = v
				best_fi = fi
		if best_fi < 0:
			break                 # 前沿全是「连不上」的 → 池被 banned 切断了，收工
		# 从 frontier 换位删除（顺序不影响结果：排序键与下标无关，确定性由键保证）
		frontier[best_fi] = frontier[frontier.size() - 1]
		frontier.pop_back()
		inflag[best_v] = 0
		picked[best_v] = 1
		out.append(best_v)
		for nb in adj[best_v]:
			var u: int = int(nb)
			if picked[u] == 1:
				continue
			cnt[u] += 1
			if inflag[u] == 0 and not banned.has(u):
				inflag[u] = 1
				ord[u] = ord_next
				ord_next += 1
				frontier.append(u)
	return out


## 收 n_target 片：**BFS 圆底 + 剔叶片修补**。
##
## ★ 为什么要修补（2026-09-19 用户报「边界有一个格子只有一口气」）：
##   普通 BFS 是「按离种子几步切一刀」，而池是 H8 树展平出来的、带**细长触手** → 球的最外那层
##   正好切在触手尖上，触手尖在这张密铺里本来就只有 1 个邻居 → 收进盘的那片**度数 = 1**：
##   初始只有一口气，唯一邻居一落子它就无气被提（等于白送一手，盘面还长毛刺很难看）。
##   ⇒ 反复「剔掉度数 ≤1 的叶片 → 从凹处补回同样多的片」，直到最小度 ≥2（最多 8 轮）。
##
## ★ 为什么不整盘改用「贪婪长胖」（试过，实测更差）：
##   贪婪长胖（每步取邻居最多的前沿片）确实能消灭叶片，但它的并列判据落在池索引上，而池索引
##   （H8 展平序）在空间上有方向性偏置 → 选区长成扇形：实测长宽比峰 1.13 → **1.37**、
##   填充谷 0.69 → 0.65。BFS 圆底 + 只修补叶片才能两全（叶片消掉、圆度保留）。
##
## ★ 传进来的 `adj` 必须是**去重版**（`_hat_adj_dedup()`）—— 否则「同一条直边被拆成两段」
##   会让同一对邻居被数多次，度 1 的叶片被误算成度 3，剔叶判定直接致盲（2026-09-19 实测）。
## ★ 只用**纯组合量**（图距离 / 邻居计数 / 前沿进入序），一律不碰坐标 ——
##   否则三种类会因几何不同而挑出不同的种子片/选区，自检 ⑥「同种子三档同构」就站不住。
## 若某轮补不回 n_target（banned 把池切小了），**撤回该轮**并收工 —— 宁可留一片叶片，
## 也不让盘面凭空缺一块（缺块会让格数断言与形状体检双双失真）。
func _hat_grow_pick(adj: Array, seed: int, n_target: int, dist: Array[int]) -> Array:
	var banned: Dictionary = {}
	var sel: Array = _hat_bfs_pick(adj, seed, n_target)
	for _pass in 8:
		var in_sel: PackedByteArray = PackedByteArray()
		in_sel.resize(adj.size())
		in_sel.fill(0)
		for v in sel:
			in_sel[int(v)] = 1
		var leaves: Array = []
		for v in sel:
			var iv: int = int(v)
			# ★ 种子片**不豁免**：它若恰好也是叶片（种子落在池的触手尖上），照样要剔 ——
			#   `_hat_refill()` 能从剩下的选区接着补，不需要种子在最终选区里。
			var d := 0
			for nb in adj[iv]:
				if in_sel[int(nb)] == 1:
					d += 1
			if d <= 1:
				leaves.append(iv)
		if leaves.is_empty():
			break
		var kept: Array = []
		for v in sel:
			if not leaves.has(int(v)):
				kept.append(int(v))
		if kept.is_empty():
			break                        # 全盘都是叶片（盘太小）→ 没得剔，收工
		for lv in leaves:
			banned[int(lv)] = true
		_hat_trim_passes += 1
		_hat_trim_banned += leaves.size()
		var trial: Array = _hat_refill(adj, kept, n_target, dist, banned)
		if trial.size() < n_target:
			for lv in leaves:
				banned.erase(int(lv))
			_hat_trim_aborted = 1
			break
		sel = trial
	# 选区平滑（2026-09-20 用户报「随机盘不圆、有的缺个口子」）：等量换片填凹口 / 削凸角。
	# 只用图量、格数不变；关掉必须变差 —— 阴性对照见 --hattest ⑤。
	if _hat_round_mode == 0:
		sel = _hat_round_sel(adj, sel, banned)
	return sel


## 选区平滑（2026-09-20 用户报「随机盘不圆、有的缺个口子」）：
## **等量换片**的局部搜索 —— 每轮全池找一对「换入 u / 换出 b」：
##   u = 空点、在选区内邻居最多（贴在凹口里）；b = 选区片、在选区内邻居最少（凸出的角）。
## 换完「选区内边数」严格增加（增量 = deg_in(u) − deg_in(b) ≥ 1）⇒ 周长单调下降：
## 凹口被逐层填平、凸角被削圆，**格数始终不变**，且不求助于任何坐标量。
## 剔叶已保证 deg_in(b) ≥ 2，配对真赚不亏；并列取池索引最小（确定性）。
## ★ 连通性保护：换出前 BFS 验证「选区 − {b} + {u}」仍连通，不行就把 b 拉进保护名单重找。
## ★ 三档同构：只用去重邻接表 / 邻居计数 / 池索引 —— 池拓扑与种类无关，
##   同种子三档换出的片逐位相同（--hattest ⑥ 不受影响）。
func _hat_round_sel(adj: Array, sel: Array, banned: Dictionary) -> Array:
	var n: int = adj.size()
	if n <= 0 or sel.size() < 7:
		return sel
	var picked: PackedByteArray = PackedByteArray()
	picked.resize(n)
	picked.fill(0)
	var out: Array = []
	for v in sel:
		var iv: int = int(v)
		if iv >= 0 and iv < n and picked[iv] == 0:
			picked[iv] = 1
			out.append(iv)
	if out.size() < 7:
		return out
	# deg_in[v] = v 的邻居里在选区内的个数（换片时增量维护）
	var deg_in: PackedInt32Array = PackedInt32Array()
	deg_in.resize(n)
	deg_in.fill(0)
	for v in n:
		var d := 0
		for nb in adj[v]:
			if picked[int(nb)] == 1:
				d += 1
		deg_in[v] = d
	var protect: Dictionary = {}
	var guard := 8 * out.size()
	while guard > 0:
		guard -= 1
		var bu := -1
		var bd_u := 0
		var bb := -1
		var bd_b := 9999
		for v in n:
			var dv := deg_in[v]
			if picked[v] == 1:
				if dv < bd_b and not protect.has(v):
					bd_b = dv
					bb = v
			elif not banned.has(v) and dv > bd_u:
				bd_u = dv
				bu = v
		if bu < 0 or bb < 0 or bd_u - bd_b < 1:
			break                      # 没有净赚的配对 → 已到局部最优（紧致形）
		# 试换：先验连通（b 是割点的话这颗 b 不能换出）
		picked[bb] = 0
		picked[bu] = 1
		var seen: Dictionary = {bu: true}
		var st: Array[int] = [bu]
		var head := 0
		while head < st.size():
			var cur: int = st[head]
			head += 1
			for nb in adj[cur]:
				var u2 := int(nb)
				if picked[u2] == 1 and not seen.has(u2):
					seen[u2] = true
					st.append(u2)
		if seen.size() < out.size():
			picked[bb] = 1             # 换出会切断 → 撤回，这颗 b 本轮保护
			picked[bu] = 0
			protect[bb] = true
			if protect.size() >= 16:
				break
			continue
		# 提交：增量维护 deg_in
		for nb in adj[bb]:
			deg_in[int(nb)] -= 1
		for nb in adj[bu]:
			deg_in[int(nb)] += 1
		for i in out.size():
			if int(out[i]) == bb:
				out[i] = bu
				break
		_hat_round_swaps += 1
		protect.clear()
	return out


## 选区总入口：正常走「BFS 圆底 + 剔叶片」；`_hat_pick_mode == 1` 时走**裸 BFS**（只给自检做阴性对照）。
func _hat_pick(adj: Array, seed: int, n_target: int, dist: Array[int]) -> Array:
	if _hat_pick_mode == 1:
		return _hat_bfs_pick(adj, seed, n_target)
	return _hat_grow_pick(adj, seed, n_target, dist)


## 清空 + 置「当前是帽子盘」标志（固定档与随机档共用，保证两条路径状态完全一致）
func _hat_clear() -> void:
	vertices.clear()
	adjacency.clear()
	board.clear()
	tiles.clear()
	tile_colors.clear()
	_cube_star_tiles.clear()
	_is_cube = false
	_is_kite = false
	_is_snow = false
	_is_hat = true


## 爱因斯坦盘（帽子家族：帽子 / 海龟 / 幽灵）生成。三种类共用同一套装配，只差两组边长
##（见 `_hat_kind_lengths()`）；同一档内固定盘与随机盘再差两点：
##   ① **种子片**：固定档恒取「离池形心最近那片」（→ 同一档每次一模一样）；
##      随机档在「离形心 t 步」的环上随机取一片（t 由池半径与目标格数算出，保证 BFS 球放得下）。
##   ② **整盘朝向**：随机档再转一个随机角（<30°，密铺 12 重对称 → 转 30° 即覆盖全部不同朝向）。
func generate_hat() -> void:
	var t0: int = Time.get_ticks_msec()
	_hat_clear()
	var kind: int = GameConfig.hat_kind
	_hat_kind_used = kind
	var is_rand: bool = _is_random_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = _rand_seed
	var target: int = _hat_target
	if is_rand:
		# 爱因斯坦随机档用自己的目标（hat_rand_tiles，240~300 窗口），不用全局 random_target_tiles
		target = maxi(20, hat_rand_tiles + rng.randi_range(-random_tile_jitter, random_tile_jitter))
		_rand_target = target

	# 1) 池 + 池内邻接 + 池形心（池的**片数与拓扑与种类无关**，只有坐标被边长线性缩放）
	var pool: Array = _hat_pool(_hat_pool_level, kind)
	_hat_pool_size = pool.size()
	# 顶点合并只做一次，「邻接」与「装配」共用同一份结果（两份口径 = 当年那个 bug 的温床）
	var vd: Dictionary = _hat_vertex_ids(pool)
	var padj: Array = _hat_pool_adj(pool, vd)
	# ★ 选区侧一律用**去重版**：盘面邻接表是去重口径（`.has(j)`），若选区侧数原始条目，
	#   两套口径就会在「同一条直边被拆成两段」的片上分叉 → 度数判定失效（见 `_hat_adj_dedup()`）。
	var padj_u: Array = _hat_adj_dedup(padj)
	# ★ 形心一律取自**帽子档的参考几何**（`_hat_ref_centers()`）：与当前种类无关 →
	#   「中心片 + 环 + 种子评分」对三档逐位相同，这正是 ⑥ 的根据。
	#   （族体检已证池的片数与片序与种类无关，故池索引可直接对应；尺寸不符时退回本盘形心兜底。）
	var rcents: Array[Vector2] = _hat_ref_centers(_hat_pool_level)
	if rcents.size() != pool.size():
		var fb: Array[Vector2] = []
		fb.resize(pool.size())
		for i in pool.size():
			fb[i] = _hat_poly_center(pool[i])
		rcents = fb
	var gc := Vector2.ZERO
	for i in pool.size():
		gc += rcents[i]
	gc /= float(maxi(pool.size(), 1))
	var center_tile := 0
	var best := INF
	for i in rcents.size():
		var d: float = (rcents[i] as Vector2).distance_squared_to(gc)
		if d < best:
			best = d
			center_tile = i

	# 2) 种子片
	var seed_tile: int = center_tile
	# 「离中心片几步」的距离场：贪婪长胖的并列判据要用它，随机档另按它给种子限幅。
	# ★ 必须在 `if is_rand` 之外先算好 —— 固定档不消耗 rng，两条路径的随机数流仍然一致。
	var dc: Array[int] = _hat_dist_field(padj_u, center_tile)
	if is_rand:
		var max_d := 0
		for v in dc:
			max_d = maxi(max_d, v)
		# 留出 BFS 球的半径（≈ √(N/π)）再加 3 步余量；池边界的 45% 之外一律不取
		var r_est: int = int(ceil(sqrt(float(target) / PI))) + 3
		var cap: int = maxi(0, int(float(max_d) * 0.45) - r_est)
		var ring: Array = []
		for i in dc.size():
			if dc[i] >= cap / 2 and dc[i] <= cap:
				ring.append(i)
		if ring.size() > 0:
			# ★ 光按「离形心几步」限幅是不够的：池不可能是圆盘 —— H8 树展平出来的区域带
			#   细长触手，种子一落在触手上，BFS 球就被拉长（实测 12 颗种子里长宽比冲到 1.59，
			#   阈值 1.6 只剩 0.6% 余量）。所以环上**试几个候选、挑最紧致的那颗**：
			#   用瓦片形心的最小外接矩形长宽比当代理（此时 vertices 还没装配，形心够用）。
			#   候选数固定 6、越界判定用同一颗 rng → 同种子仍然逐位复现。
			# ★ 候选评分必须是**纯组合量**（与种类无关）：原先用「瓦片形心的最小外接矩形长宽比」
			#   当代理 —— 那是**几何**量，而三种类的边长不同、形心配置是一次非均匀形变 →
			#   三档各自挑出不同的种子片 → ⑥「同种子三档同构」随机变红（2026-09-19 实测）。
			#   改用**等周判据**：在池内 BFS 收够 target 片，数这个选区的**边界边数**
			#   （选区内某片的池邻居落在选区外的条数）—— 越小越紧凑。这正是我们要的
			#   「盘面圆、边界光滑」，且只用到图结构。种子落在细长触手上时边界边数会明显偏大。
			#   12 个候选**每次都抽满**（不做提前 break），随机数消耗与候选好坏无关。
			# ★ 评分几何用**帽子档的参考形心**（`_hat_ref_centers()`）—— 与当前种类无关，
			#   所以 12 个候选的评分对三档**逐位相同** → ⑥「同种子三档同构」稳。
			#   判据回到原始的「选区形心的**最小外接矩形长宽比**」（越小越圆）—— 实测这是对
			#   最终观感最贴题的代理。⚠️ 实测记录（帽子档 8 颗种子、长宽比峰）：
			#     几何长宽比 = 1.13（最好）｜图半径 = 1.27｜边界边数 = 1.49（最差）。
			#   候选上限 12，够到 ≤1.25 就提前收工（提前收工与否只取决于该长宽比，与种类无关）。
			var best_seed: int = center_tile
			var best_asp := INF
			for _try in 12:
				var cand: int = int(ring[rng.randi_range(0, ring.size() - 1)])
				var trial: Array = _hat_bfs_pick(padj_u, cand, target)
				if trial.size() < target:
					continue                 # 该候选凑不出 target 片（不该发生）
				var pts: Array[Vector2] = []
				for ti in trial:
					pts.append(rcents[int(ti)])
				var asp: float = (_min_area_rect(pts) as Array[float])[0]
				if asp < best_asp:
					best_asp = asp
					best_seed = cand
				if asp <= 1.25:
					break                # 已经足够圆，不再多花时间
			seed_tile = best_seed
	_hat_trim_passes = 0
	_hat_trim_banned = 0
	_hat_trim_aborted = 0
	_hat_round_swaps = 0
	var sel: Array = _hat_pick(padj_u, seed_tile, target, _hat_dist_field(padj_u, seed_tile))
	if sel.size() < target:                 # 种子贴边 → 池不够，退回中心片重来
		seed_tile = center_tile
		sel = _hat_pick(padj_u, center_tile, target, dc)
	_hat_seed_tile = seed_tile

	# 3) 装配（随机档再整体转一个随机朝向）
	# ★ 顶点号**沿用池的合并结果**（上面那份 `vd`），不在这里用 `_kite_vid` 重按坐标合一遍。
	#   理由：① 与邻接**同源** → 「邻接说这条边配对」与「几何上是同一个顶点」永不打架；
	#   ② 两套容差（池 1e-3 vs `_kite_vid` 2e-5）混用就是当年那个丢边 bug 的同型隐患 ——
	#   实测 150 片标准盘：池口径约 957 个真顶点，而 `_kite_vid` 只合到 1050，多出 ~93 个
	#   相距 1e-7 的重复点（当前无害，但没必要留）。
	var rot: float = rng.randf() * _HAT_ANG30 if is_rand else 0.0
	_hat_rot_deg = rad_to_deg(rot)
	var vid_all: Array = vd["ids"]
	var reps_all: Array = vd["reps"]
	var vmap: Dictionary = {}
	var vlist: Array[Vector2] = []
	for idx in sel:
		var row: Array = vid_all[int(idx)]
		var ids: Array[int] = []
		for pv in row:
			var pvid: int = int(pv)
			if not vmap.has(pvid):
				vmap[pvid] = vlist.size()
				vlist.append((reps_all[pvid] as Vector2).rotated(rot))
			ids.append(int(vmap[pvid]))
		tiles.append(ids)
		tile_colors.append(fat_color)
	vertices = vlist

	# 4) 邻接：**直接把「池邻接」映射成棋盘格号**，不再自己按顶点 id 重算一遍。
	#
	# ⚠️ 为什么不能重算（2026-09-19 实测踩坑）：按坐标在棋盘上重算邻接，容差取小了（`_kite_vid` 的 2e-5）
	# 就会「有的顶点合上了、有的没合上」→ 共享边键时有时无 → 150 片的标准盘实测**丢 17 条边、裂成 2 块**，
	# 而且「同一对邻居沿直边两段各记一次」还会把度数刷到 14（帽子只有 13 条有效边，14 度不可能）。
	# 池邻接是**唯一真源**（`_hat_vertex_ids()` 的容差判据 + 「池内共享边恰两片」的整型判据），
	# 且池的边到边性与「丢边 = 0」已由自检 ③ 钉死 → 这里只做「索引重映射 + 去重」。
	var pos: Dictionary = {}
	for k in sel.size():
		pos[int(sel[k])] = k
	adjacency.resize(tiles.size())
	for i in tiles.size():
		adjacency[i] = []
	for k in sel.size():
		for nb in padj_u[int(sel[k])]:  # 去重口径（与选区判定同源；`.has(j)` 只作双保险）
			if not pos.has(int(nb)):
				continue          # 邻居不在选区内（选区外边界）
			var j: int = int(pos[int(nb)])
			if (adjacency[k] as Array).has(j):
				continue          # 直边两段会让同一对邻居被记两次 → 去重
			(adjacency[k] as Array).append(j)
			(adjacency[j] as Array).append(k)
	board.clear()
	for i in tiles.size():
		board[i] = Stone.EMPTY

	# 5) 归心 → 星位（顺序不能反：星位是绕**原点**分 6 扇区取的，选区形心不在原点会有扇区踩空）
	_center_board_on_origin()
	_cube_star_tiles = _snow_star_current()
	var rot_txt: String = (" | 朝向=" + str(snappedf(_hat_rot_deg, 1)) + "°") if is_rand else ""
	# ★ 横幅里带上「连通块数」必须恒为 1：用户报的「同色相邻棋子判为不连」正是它不等于 1 的症状 ——
	#   以后再出这类问题，看一行日志就能定位，不用猜。O(N)，开销可忽略。
	print("生成爱因斯坦棋盘（", _hat_kind_name(kind), "）池=", _hat_pool_level, " 层（", _hat_pool_size, " 片）| 种子片=", seed_tile,
		" | 目标=", target, " 实际=", tiles.size(), " 落子格", rot_txt,
		" | 顶点=", vertices.size(), " | 星位=", _cube_star_tiles.size(),
		" | 换片=", _hat_round_swaps,
		" | 连通=", _component_count(),
		" | 耗时=", Time.get_ticks_msec() - t0, "ms")


## 「8 块筝形」判定（--hattest ①，**定义级**判据）：帽子按定义是筝形 polykite。
## 用反射法生成一张筝形网格（筝形 = 边长 1 与 √3 的 60/90/120/90，与「筝形棋盘」同族），
## 数「形心落在帽子内部」的筝形块数并要求**恰好 8、面积比 1.0**。
## 这条能把镜像参数（边长 8×√3 + 6×1）直接判死 —— 那套的面积是 10√3，比例只有 0.9。
## 返回 [块数, 面积比]。
func _hat_kite_probe(hat: Array) -> Array:
	var sq3: float = sqrt(3.0)
	var kite: Array[Vector2] = [
		Vector2(0.0, 0.0), Vector2(1.5, sq3 * 0.5), Vector2(2.0, 0.0), Vector2(1.5, -sq3 * 0.5)]
	# 帽子的包围半径 → 网格只需铺到这么大（自适应，免得写死的半径盖不住）
	var rmax := 0.0
	for p in hat:
		rmax = maxf(rmax, (p as Vector2).length() + 2.0)
	var grid: Array = [kite]
	var seen: Dictionary = {_hat_poly_key(kite): true}
	var frontier: Array = [kite]
	while frontier.size() > 0:
		var nxt: Array = []
		for poly in frontier:
			var pp: Array = poly
			var n: int = pp.size()
			for i in n:
				var cand: Array[Vector2] = []
				for q in pp:
					cand.append(_hat_mirror(q, pp[i], pp[(i + 1) % n]))
				var c := Vector2.ZERO
				for q in cand:
					c += q
				c /= 4.0
				if c.length() > rmax:
					continue
				var key: String = _hat_poly_key(cand)
				if seen.has(key):
					continue
				seen[key] = true
				nxt.append(cand)
				grid.append(cand)
		frontier = nxt
	var hat_poly := PackedVector2Array(hat)
	var inside := 0
	var ka := 0.0
	for poly in grid:
		var c := Vector2.ZERO
		for q in poly:
			c += q
		c /= 4.0
		if Geometry2D.is_point_in_polygon(c, hat_poly):
			inside += 1
			ka += _hat_poly_area(poly)
	return [inside, ka / maxf(_hat_poly_area(hat), 1e-9)]


## 把点 q 关于「过 a、方向 b−a」的直线镜像
func _hat_mirror(q: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var u: Vector2 = (b - a).normalized()
	var v: Vector2 = q - a
	return a + u * (2.0 * v.dot(u)) - v


## 多边形身份键（`_hat_kite_probe` 的网格去重用）。
## ★ 用**形心量化**而不是顶点量化（2026-09-19 修）：顶点量化踩的是同一个格线坑 ——
##   `_hat_mirror()` 的反射链让同一块筝形的坐标带 ~1e-6 抖动，只要压在格线上就判成「新块」，
##   同一块筝形被塞进网格两次 → 自检 ① 数出 **15 块 / 面积比 1.875**（真值 8 / 1.0）。
##   形心量化步长 0.125 远小于「不同筝形形心的最小间距 ≈ 1.0」→ 踩空概率 ~1e-5，且形心
##   对刚体平移更稳。
func _hat_poly_key(poly: Array) -> String:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= float(maxi(poly.size(), 1))
	return "%d,%d" % [int(round(c.x / 0.125)), int(round(c.y / 0.125))]


func _hat_poly_area(poly: Array) -> float:
	var s := 0.0
	var n: int = poly.size()
	for i in n:
		s += (poly[i] as Vector2).cross(poly[(i + 1) % n])
	return absf(s) * 0.5


## 池的拼贴质量审计（--hattest ③）：返回 [重叠边数, T 型接点数, 连通块数]。
## 重叠边 = 同一条边被 ≥3 片共享（真帽子密铺里不可能出现）。
## T 型接点 = 某片顶点**严格落在**边界边的内部 → 不是边到边（只查该片及其邻片，够快）。
func _hat_pool_audit(pool: Array, padj: Array, tol: float = _HAT_MERGE_TOL) -> Array:
	var vd: Dictionary = _hat_vertex_ids(pool, tol)
	var vid: Array = vd["ids"]
	var em: Dictionary = {}
	for i in pool.size():
		var t: Array = vid[i]
		var n: int = t.size()
		for k in n:
			var ka: int = int(t[k])
			var kb: int = int(t[(k + 1) % n])
			var key: String = "%d,%d" % [mini(ka, kb), maxi(ka, kb)]
			if not em.has(key):
				em[key] = []
			(em[key] as Array).append([i, k])
	var over := 0
	var bnd_list: Array = []
	for key in em:
		var own: Array = em[key]
		if own.size() >= 3:
			over += 1
		elif own.size() == 1:
			bnd_list.append(own[0])
	var tj := 0
	for e in bnd_list:
		var ti: int = int(e[0])
		var k: int = int(e[1])
		var tt: Array = pool[ti]
		var n: int = tt.size()
		var a: Vector2 = tt[k]
		var b: Vector2 = tt[(k + 1) % n]
		for tj_tile in ([ti] as Array + padj[ti]):
			var ot: Array = pool[int(tj_tile)]
			for q in ot:
				var v: Vector2 = q
				if v.distance_squared_to(a) < 1e-9 or v.distance_squared_to(b) < 1e-9:
					continue
				var ab: Vector2 = b - a
				if absf(ab.cross(v - a)) > 1e-7 * ab.length():
					continue
				var dot: float = (v - a).dot(ab)
				if dot > 1e-7 and dot < ab.length_squared() - 1e-7:
					tj += 1
	# ★ **丢边审计**（旧版缺的就是这一段，于是 bug 被静默掩盖了很久）。
	#   旧口径把「未配对」一律当成「边界边」；可未配对还有第二种成因：同一条边的两份拷贝
	#   因为顶点合并漏配而拿到**不同的键**，两边各剩一条「孤边」。计数上它和边界边长得一模一样，
	#   只有几何上能分开 → 交给 `_hat_lost_edges()` 用探针判。
	var lost: int = _hat_lost_edges(pool, vid, bnd_list)
	# 连通块数
	var seen: Array = []
	seen.resize(pool.size())
	var comps := 0
	for s in range(pool.size()):
		if seen[s]:
			continue
		comps += 1
		seen[s] = true
		var stack: Array[int] = [s]
		while stack.size() > 0:
			var cur: int = stack.pop_back()
			for nb in padj[cur]:
				if not seen[nb]:
					seen[nb] = true
					stack.append(nb)
	return [over, tj, comps, lost]


## 丢边审计（几何探针）：数出「**未配对，但对面其实真有邻片**」的边 = 邻接图里静默缺失的连接。
##
## 判据：取未配对边 (a,b) 的中点 m，沿边的**两个法向**各挪 _hat_probe 得到 q±。若 q± 落在
## **另一片**（且那片与本片至少共用一个顶点号）的多边形内部 → 那片与本片分享这条边 → 本边本该
## 配对 → 计一次丢边。两侧都探是为了不依赖多边形的绕向（帽子有 240°/270° 反角，边长方向与
## 形心连线不一定同侧）。
## ★ 为什么必须有这一条：量化键踩格线造成的丢边，在「边被几种片共享」的计数里与真边界边**完全
##   同形**（都是 owner == 1）。只数不探，就永远看不见它 —— 用户报的 bug 正是这么漏过去的。
## 代价：只对未配对边跑，level 4 池约 2000 条 × 邻域几片 → 自检里几秒，不进运行期热路径。
func _hat_lost_edges(pool: Array, vid: Array, bnd_list: Array) -> int:
	if bnd_list.is_empty():
		return 0
	# 按形心把片分桶（片尺度约 3，桶取 4 就够；探针点只查 3×3 邻桶）
	var cell: float = 4.0
	var cidx: Dictionary = {}
	for i in pool.size():
		var tc: Vector2 = _hat_poly_center(pool[i])
		var ck: int = (int(floor(tc.x / cell)) + 1048576) * 2097152 \
			+ (int(floor(tc.y / cell)) + 1048576)
		if not cidx.has(ck):
			cidx[ck] = []
		(cidx[ck] as Array).append(i)
	var lost := 0
	for e in bnd_list:
		var ti: int = int(e[0])
		var k: int = int(e[1])
		var tt: Array = pool[ti]
		var n: int = tt.size()
		var a: Vector2 = tt[k]
		var b: Vector2 = tt[(k + 1) % n]
		var ab: Vector2 = b - a
		if ab.length_squared() < 1e-18:
			continue
		var m: Vector2 = (a + b) * 0.5
		var nrm: Vector2 = ab.normalized().orthogonal() * 1e-3
		var hit := false
		for q in [m + nrm, m - nrm]:
			var cx: int = int(floor(q.x / cell))
			var cy: int = int(floor(q.y / cell))
			for dx in [-1, 0, 1]:
				if hit:
					break
				for dy in [-1, 0, 1]:
					var ck2: int = (cx + dx + 1048576) * 2097152 + (cy + dy + 1048576)
					for ti2 in cidx.get(ck2, []):
						if int(ti2) == ti:
							continue
						if not _hat_shares_vert(vid, ti, int(ti2)):
							continue
						if Geometry2D.is_point_in_polygon(q, PackedVector2Array(pool[int(ti2)])):
							hit = true
							break
					if hit:
						break
			if hit:
				break
		if hit:
			lost += 1
	return lost


## 两片是否至少共用一个顶点号（丢边探针的守卫：防止「只共一个顶点的斜对角片」被误判成邻片）
func _hat_shares_vert(vid: Array, i: int, j: int) -> bool:
	var ri: Array = vid[i]
	var rj: Array = vid[j]
	for x in ri:
		if rj.has(int(x)):
			return true
	return false


## 两片是否共享**至少一条边**（顶点号层面：存在一对连续顶点，在另一片里也连续出现，方向可反 ——
## 帽子的 H7 原型含镜像块，相邻两片的绕向不一定相同）
func _edge_shared_between(ti: Array, tj: Array) -> bool:
	var ni: int = ti.size()
	var nj: int = tj.size()
	for k in ni:
		var a: int = ti[k]
		var b: int = ti[(k + 1) % ni]
		for m in nj:
			var c: int = tj[m]
			var d: int = tj[(m + 1) % nj]
			if (c == a and d == b) or (c == b and d == a):
				return true
	return false


## ★ 邻接 ⇔ 真共边 的一致性检查（自检用）：`adjacency` 里**每一对邻居**都必须在顶点号层面真的共边。
##
## 为什么非查不可 —— 这是**第二条会表现成「同色相邻棋子未连接」的路径**：
## `_rebuild_edge_map()` 要靠顶点号在 `adjacency[i]` 里反查邻居（`ntvs.has(a) and ntvs.has(b)`）来
## 给每条边定「对面是谁」。要是两片相邻瓦片的共享边顶点被拆成不同号，`nb` 就查不到 → 那条**内部边
## 被当成外边界画** → 视觉上就是一道缝、两团同色棋子看着没连上，**哪怕 `adjacency` 本身是对的**。
## 现在装配与邻接同源（都走 `_hat_vertex_ids`），这条恒成立；一旦哪天又有人「顺手重算一遍」，它会报警。
## 返回不一致的邻居对数（期望 0）。`tls` 可传入替身（自检做阴性对照用），默认查当前 `tiles`。
func _adj_edge_consistency(tls: Array = []) -> int:
	var tl_all: Array = tiles if tls.is_empty() else tls
	var bad := 0
	for i in tl_all.size():
		for j in adjacency[i]:
			if int(j) <= i:
				continue          # 无向对只查一次
			if not _edge_shared_between(tl_all[i], tl_all[int(j)]):
				bad += 1
	return bad


## 自检（--hattest）：爱因斯坦瓦片族（帽子 / 海龟 / 幽灵）与盘面的数学健全性。
##   ① 三档瓦片模板：都是 14 点 / 恰好 1 个共线点（→ 12 条几何边）/ 角谱恒 {90°,120°,180°}
##      （方向序列 `_HAT_EDGES` 三档共用）/ 边长谱 {1×8,√3×6}、{√3×8,1×6}、{1×14} /
##      面积 8√3、10√3、(3+√3)√3；**三档面积两两不同**（阴性对照：种类参数必须真的进到几何里）/
##      帽子档另跑**定义级**判据「恰好由 8 块筝形拼成」（面积比 1.0）——
##      那条判据只对 (1,√3) 成立，海龟/幽灵不在这张筝形网格上，故不套用；
##   ② 池规模阶梯：level 1→8 / 2→55 / 3→377（H8 支）——**三档共用的组合常数**；
##   ③ 拼贴质量（三档 × level 3，默认档另查 level 4）：无重叠边、无 T 型接点（边到边）、整池连通、
##      **丢边 = 0**（未配对但对面真有邻片 → 邻接静默缺边，用户报的「同色相邻不连」就是它；
##      根因是顶点量化键踩格线，2026-09-19 改成容差判据 `_hat_vertex_ids()`）、顶点数 = 真值
##      （**三档同一个真值** → 顺手把「拓扑与边长无关」这条钉死），
##      外加**阴性对照**（容差故意砸到 1e-7）证明这两条探针真的会报警；
##   ④ 固定盘：每档 × 标准/加强 **精确命中**格数、星位 7、连通、两次生成同指纹、
##      **邻接 ⇔ 真共边 一致**（`_adj_edge_consistency()`：防 `_rebuild_edge_map()` 把内部边
##      画成外边界 —— 那是「同色相邻棋子没连上」的**第二条**路径，与邻接丢边并列）；
##   ⑤ 随机档：每档若干颗种子 → 互不相同 / 同种子复现 / 格数在目标带内 / 长宽比 ≤1.6 且填充率 ≥0.55 /
##      星位 7（归心之后取，否则扇区会踩空）/ 连通 / 共边一致；
##   ⑥ **跨档同构**：同一颗种子下三档的「格数 + 邻接度直方图」必须逐位相同 ——
##      种类只换边长、不换拓扑。这一条就是把「三档共用同一份池/装配/邻接代码」钉死的地方。
func _hat_self_test() -> void:
	var ok := true
	var sq3: float = sqrt(3.0)
	var kinds: Array = [GameConfig.HAT_HAT, GameConfig.HAT_TURTLE, GameConfig.HAT_SPECTRE]

	print("[hattest] ===== ① 瓦片模板（三档种类）=====")
	var areas: Array[float] = []
	for kind in kinds:
		var pts: Array = _hat_base(kind)["pts"]
		var Ls: Array[float] = _hat_kind_lengths(kind)
		var la: float = Ls[0]
		var lb: float = Ls[1]
		var col := 0
		for i in pts.size():
			var a: Vector2 = pts[(i - 1 + pts.size()) % pts.size()]
			var b: Vector2 = pts[i]
			var c: Vector2 = pts[(i + 1) % pts.size()]
			if absf((a - b).normalized().cross((c - b).normalized())) < 1e-6:
				col += 1
		var n_la := 0
		var n_lb := 0
		var bad_len := 0
		for i in pts.size():
			var L: float = (pts[i] as Vector2).distance_to(pts[(i + 1) % pts.size()])
			if absf(L - la) < 1e-6:
				n_la += 1
			elif absf(L - lb) < 1e-6:
				n_lb += 1
			else:
				bad_len += 1
		var area: float = _hat_poly_area(pts)
		var area_want: float = _hat_kind_area(kind)
		areas.append(area)
		# 等边档（幽灵）两组边长相同 → 14 条边全归入 a，期望 14/0；其余档 8/6
		var len_ok: bool = (n_la == 14 and n_lb == 0) if absf(la - lb) <= 1e-6 \
			else (n_la == 8 and n_lb == 6)
		var s1: bool = pts.size() == 14 and col == 1 and len_ok and bad_len == 0 \
			and absf(area - area_want) < 1e-4
		if not s1:
			ok = false
		print("[hattest] ① %s：顶点 %d（共线 %d → 几何边 %d）| 边长 a=%.4f×%d + b=%.4f×%d + 异常 %d | 面积 %.6f（期望 %.6f）→ %s"
			% [_hat_kind_name(kind), pts.size(), col, pts.size() - col,
				la, n_la, lb, n_lb, bad_len, area, area_want, "✓" if s1 else "✗"])
		# 帽子的**定义级**判据：恰好 8 块筝形（面积比 1.0）。只对 (1,√3) 有意义
		if kind == GameConfig.HAT_HAT:
			var kp: Array = _hat_kite_probe(pts)
			var sk: bool = int(kp[0]) == 8 and absf(float(kp[1]) - 1.0) < 1e-4
			if not sk:
				ok = false
			print("[hattest] ① 帽子筝形分解（定义级）：形心在瓦片内的筝形 %d 块（期望 8）| 面积比 %.4f（期望 1.0）→ %s"
				% [int(kp[0]), float(kp[1]), "✓" if sk else "✗"])
	# ★ 阴性对照（证明「种类参数真的进了几何」）：三档面积两两不同。
	#   若哪天 _hat_kind_lengths() 被改坏、三档退化成同一个瓦片，这里立刻红。
	var d01: float = absf(areas[0] - areas[1])
	var d12: float = absf(areas[1] - areas[2])
	var d02: float = absf(areas[0] - areas[2])
	var distinct: bool = d01 > 1.0 and d12 > 1.0 and d02 > 1.0
	if not distinct:
		ok = false
	print("[hattest] ① 阴性对照（三档必须互不相同）：|帽−龟|=%.4f |龟−幽|=%.4f |帽−幽|=%.4f（均须 > 1.0）→ %s"
		% [d01, d12, d02, "✓" if distinct else "✗ 三档退化成同一个瓦片了"])

	print("[hattest] ===== ② 池规模阶梯 =====")
	var want: Array = [8, 55, 377]
	for lv in [1, 2, 3]:
		var got: int = _hat_pool(lv).size()
		var good: bool = got == int(want[lv - 1])
		if not good:
			ok = false
		print("[hattest] ② level %d → %d 片（期望 %d）%s" % [lv, got, int(want[lv - 1]), "✓" if good else "✗"])

	print("[hattest] ===== ③ 拼贴质量（三档 × level 3；默认档另查 level 4）=====")
	for kind in kinds:
		# level 4 的审计（含几何丢边探针）是这里最贵的一段，约几秒；三档的**组合拓扑已被精确算术
		# 证明逐位相同**（工作区 `_family_kinds.py`），所以 level 4 只跑默认档，其余档跑 level 3。
		var levels: Array = [3, 4] if kind == GameConfig.HAT_HAT else [3]
		for lv in levels:
			var poolq: Array = _hat_pool(lv, kind)
			var padjq: Array = _hat_pool_adj(poolq)
			var au: Array = _hat_pool_audit(poolq, padjq)
			# ★ 顶点数必须**恰好**等于真值：偏大 = 合并漏了（同一顶点被拆开 → 共享边会丢，正是用户
			#   报的 bug）；偏小 = 合过了（不同顶点被并成一个 → 假邻接）。这是「丢边」的**廉价探针**，
			#   几何探针太慢进不了盘。两者都在这一行钉死。
			# ★★ 期望值三档**共用同一对数**（2530 / 16496）—— 精确算术已证明三档的顶点数逐位相同
			#   （拓扑只由组合粘合决定），所以「三档都命中同一个真值」本身就是「拓扑与边长无关」的断言。
			var nv_expect: int = int(_HAT_EXPECT_VERTS[0]) if lv == 3 else int(_HAT_EXPECT_VERTS[1])
			var nv: int = (((_hat_vertex_ids(poolq) as Dictionary)["reps"]) as Array).size()
			var s3: bool = int(au[0]) == 0 and int(au[1]) == 0 and int(au[2]) == 1 \
				and int(au[3]) == 0 and nv == nv_expect
			if not s3:
				ok = false
			print("[hattest] ③ %s level %d 池 %d 片：重叠边 %d（期望 0）| T 型接点 %d（期望 0）| 连通块 %d（期望 1）| **丢边 %d（期望 0）** | 顶点 %d（期望 %d）→ %s"
				% [_hat_kind_name(kind), lv, poolq.size(), int(au[0]), int(au[1]), int(au[2]),
					int(au[3]), nv, nv_expect, "✓" if s3 else "✗"])
			if kind == GameConfig.HAT_HAT and lv == 3:
				# ★ **阴性对照（测试自己也要被测试）**：把合并容差砸到 1e-7 —— 比同一顶点两份拷贝的
				#   实测最大偏差（level 4 = 2.39e-5）小两个数量级 → 必然拆开一大堆顶点。此时**两条探针
				#   都必须报警**：
				#     ① 顶点数变大（廉价探针，运行期可用）；
				#     ② 丢边探针报出 > 0（几何探针，独立于顶点号，直接看几何）。
				#   这里要是没报警，说明探针是瞎的 —— 那种「自检通过」毫无意义（丢边这个 bug 能藏
				#   这么久，就是因为老审计只数边被几片共享，对「拆开导致的孤边」完全失明）。
				#   三档只跑一遍：对照证明的是**探针**有牙齿，不是某一档的几何。
				var nv_bad: int = (((_hat_vertex_ids(poolq, 1e-7) as Dictionary)["reps"]) as Array).size()
				var au_bad: Array = _hat_pool_audit(poolq, padjq, 1e-7)
				var ctl: bool = nv_bad > nv and int(au_bad[3]) > 0
				if not ctl:
					ok = false
				print("[hattest] ③ 阴性对照（容差 1e-7，故意拆开）：顶点 %d（须 > %d）| 丢边 %d（须 > 0）→ %s"
					% [nv_bad, nv, int(au_bad[3]), "✓" if ctl else "✗"])

	print("[hattest] ===== ④ 固定盘（三档种类 × 标准/加强）=====")
	var saved_size: int = GameConfig.board_size
	var saved_kind: int = GameConfig.hat_kind
	var ladders: Array = [
		{"name": "标准", "size": GameConfig.STANDARD, "tiles": hat_std_tiles},
		{"name": "加强", "size": GameConfig.ENHANCED, "tiles": hat_big_tiles},
	]
	for kind in kinds:
		GameConfig.hat_kind = kind
		for ld in ladders:
			GameConfig.board_size = int(ld["size"])
			_apply_board_size(int(ld["size"]))
			generate_hat()
			var n0: int = tiles.size()
			var fp: int = _board_fingerprint()
			var st: int = _cube_star_tiles.size()
			generate_hat()
			var same: bool = _board_fingerprint() == fp
			var dmax: int = _adj_max_degree()
			# 瓦片只有 13 条**有效**边（14 个顶点里 1 个共线）→ 邻居数上限就是 13。
			# 「同一对邻居沿同一条直边的两段各记一次」会把度数刷到 14 —— 这条就是抓它的。
			# `ec`：邻接里每一对邻居都必须真的共边（否则 `_rebuild_edge_map` 会把内部边画成外边界，
			# 视觉上就是「同色相邻棋子没连上」—— 与邻接丢边并列的第二条失效路径）。
			var ec: int = _adj_edge_consistency()
			var good: bool = n0 == int(ld["tiles"]) and st == 7 and same and _all_tiles_connected() \
				and dmax <= 13 and ec == 0
			if not good:
				ok = false
			print("[hattest] ④ %s·%s盘：格数 %d（期望 %d）| 星位 %d（期望 7）| 两次生成%s | 连通 %s | 最大度 %d（≤13）| 邻接共边不一致 %d（期望 0）| %s"
				% [_hat_kind_name(kind), ld["name"], n0, int(ld["tiles"]), st,
					"一致" if same else "不一致",
					"✓" if _all_tiles_connected() else "✗", dmax, ec, "✓" if good else "✗"])
			print("[hattest] ④   ", _adj_histogram())

	# ★ 阴性对照（证明「邻接 ⇔ 真共边」这条检查真有牙齿）：把**度数最高那一格**的所有顶点号
	#   换成一组全新号 —— 忠实模拟「合并漏配」（这片与邻片各持不同号）。
	#   注意别写成「把所有瓦片里的某个共用号一起换掉」：那样两片**仍然一致**，检查照样通过，
	#   对照就成了摆设（实测第一版就是这么写的，反被这条对照抓出来）。
	var i0 := 0
	for i in tiles.size():
		if (adjacency[i] as Array).size() > (adjacency[i0] as Array).size():
			i0 = i
	var broken: Array = []
	for ti in tiles.size():
		var tl: Array = tiles[ti]
		if ti != i0:
			broken.append(tl)
			continue
		var row2: Array = []
		for k in tl.size():
			row2.append(900000 + k)
		broken.append(row2)
	var ec_bad: int = _adj_edge_consistency(broken)
	var ectl: bool = (adjacency[i0] as Array).size() >= 2 and ec_bad > 0
	if not ectl:
		ok = false
	print("[hattest] ④ 阴性对照（把第 %d 格 —— %d 度 —— 的顶点号全换成新号）：共边不一致 %d（须 > 0）→ %s"
		% [i0, (adjacency[i0] as Array).size(), ec_bad, "✓" if ectl else "✗"])

	print("[hattest] ===== ⑤ 随机档（三档种类）=====")
	GameConfig.board_size = GameConfig.RANDOM
	var round_any := 0                     # 平滑器是否真的开过火（阴性对照要用）
	for kind in kinds:
		GameConfig.hat_kind = kind
		# ★ 横幅必须在 hat_kind 设好**之后**再打，否则会带着上一段残留的种类名
		#   （日志写成「爱因斯坦·幽灵 随机」而实际生成的是帽子 → 「日志会骗人」）。
		#   _apply_board_size 只设字段 + 打印一行，重复调用无副作用。
		_apply_board_size(GameConfig.RANDOM)
		# 默认档 8 颗种子（与其它盘的随机档同口径）；另两档 3 颗 —— 三档的几何共性由 ⑥ 专管，
		# 这里对它们只需确认「能出盘、盘面健全」。
		var n_seed: int = 8 if kind == GameConfig.HAT_HAT else 3
		# 爱因斯坦随机档用自己的目标（240~300 窗口），不用全局 random_target_tiles
		var hat_tgt: int = hat_rand_tiles
		var fps: Dictionary = {}
		var cnt_lo := 99999
		var cnt_hi := -1
		var min_deg := 99
		var trim_hi := 0
		var ban_hi := 0
		var abort_n := 0
		var round_hi := 0
		var worst_gap := 0
		var asp_hi := 0.0
		var fill_lo := INF
		var hull_lo := INF
		for i in n_seed:
			_rand_seed = 3000 + i * 7919
			generate_hat()
			var n0: int = tiles.size()
			var fp: int = _board_fingerprint()
			fps[fp] = true
			min_deg = mini(min_deg, _adj_min_degree())
			trim_hi = maxi(trim_hi, _hat_trim_passes)
			ban_hi = maxi(ban_hi, _hat_trim_banned)
			round_hi = maxi(round_hi, _hat_round_swaps)
			round_any = maxi(round_any, _hat_round_swaps)
			if _hat_trim_aborted > 0:
				abort_n += 1
			cnt_lo = mini(cnt_lo, n0)
			cnt_hi = maxi(cnt_hi, n0)
			worst_gap = maxi(worst_gap, absi(n0 - hat_tgt))
			var m: Array[float] = _rand_shape_metrics()
			asp_hi = maxf(asp_hi, m[0])
			fill_lo = minf(fill_lo, m[1])
			hull_lo = minf(hull_lo, m[2])
			if _cube_star_tiles.size() != 7:
				ok = false
				print("[hattest] ⑤ ", _hat_kind_name(kind), " 种子 ", _rand_seed, " 星位 ",
					_cube_star_tiles.size(), "（期望 7）")
			if not _all_tiles_connected():
				ok = false
				print("[hattest] ⑤ ", _hat_kind_name(kind), " 种子 ", _rand_seed, " 盘面不连通")
			var ecr: int = _adj_edge_consistency()
			if ecr != 0:
				ok = false
				print("[hattest] ⑤ ", _hat_kind_name(kind), " 种子 ", _rand_seed,
					" 邻接共边不一致 ", ecr, " 对（期望 0）")
			generate_hat()
			if _board_fingerprint() != fp:
				ok = false
				print("[hattest] ⑤ ", _hat_kind_name(kind), " 种子 ", _rand_seed, " 同种子两次生成不一致")
		var band_ok: bool = worst_gap <= random_tile_jitter + 6
		var uniq_ok: bool = fps.size() == n_seed
		# 2026-09-20 定稿口径（两把尺子，主次分明）：
		#   主判据 = 凸包填充率（hull_lo）：缺口只要不在边界矩形极值上，矩形填充就看不见，
		#     凸包填充对「凹口」一票敏感（圆盘 ≈1.0）。实测谷：帽子 0.840 / 海龟 0.859 /
		#     幽灵 0.856（平滑器开），门槛钉 0.82（平滑器关的对照谷 0.832 也能过，留余量）。
		#   次级护栏 = 矩形填充率（fill_lo）≥0.60：只防「整体被削平 / 拖成长条」这类
		#     大形畸变（实测谷 0.67；旧门槛 0.72 是拿错尺子才挂的，凹口不碰极值时它量不到）。
		var shape_ok: bool = asp_hi <= 1.35 and fill_lo >= 0.60 and hull_lo >= 0.82
		# ★ 最小邻接度 ≥2：度数 1 的格子就是边界上「只有一口气」的尖头（用户 2026-09-19 报的）。
		#   成因与修法见 _hat_grow_pick() 的注释。
		var deg_ok: bool = min_deg >= 2
		if not (band_ok and uniq_ok and shape_ok and deg_ok):
			ok = false
		print("[hattest] ⑤ %s：目标=%d±%d | 格数 %d~%d | 离目标最远 %d 格 %s | 互不相同 %d/%d %s | 长宽比峰 %.2f（≤1.35）矩形填充谷 %.2f（≥0.60）%s | 换片峰 %d"
			% [_hat_kind_name(kind), hat_tgt, random_tile_jitter, cnt_lo, cnt_hi,
				worst_gap, "✓" if band_ok else "✗", fps.size(), n_seed, "✓" if uniq_ok else "✗",
				asp_hi, fill_lo, "✓" if shape_ok else "✗（太扁或缺口：平滑失效或池太小）", round_hi])
		print("[hattest] ⑤ %s：凸包填充谷 %.3f（缺口主判据，≥0.82；越接近 1 越圆）%s"
			% [_hat_kind_name(kind), hull_lo, "✓" if hull_lo >= 0.82 else "✗（有缺口没抹平）"])
		print("[hattest] ⑤ %s：最小邻接度 %d（期望 ≥2；1 度 = 「只有一口气」的尖头）→ %s | 剔叶最多 %d 轮 / 累计禁 %d 片 / 撤回 %d 颗种子"
			% [_hat_kind_name(kind), min_deg, "✓" if deg_ok else "✗", trim_hi, ban_hi, abort_n])

	# ⑤ 阴性对照：把选区切回**裸 BFS**（不做剔叶修补），扫若干颗种子，**必须至少有一颗**
	#    出现度数 1 的尖头 —— 否则说明「最小邻接度 ≥2」这条探针是瞎的（探针自己也要被测试）。
	#    ★ 不能钉死某一颗种子：种子片是按「最小图半径」组合判据挑的（v2 起），
	#      换判据后某一颗特定的种子可能恰好不带叶片，那样对照会假红。用**统计**才稳。
	GameConfig.hat_kind = GameConfig.HAT_HAT
	_hat_pick_mode = 1
	var bfs_bad := 0
	var bfs_seeds: Array[int] = []
	for _i in 12:
		_rand_seed = 3000 + _i * 7919
		generate_hat()
		if _adj_min_degree() <= 1:
			bfs_bad += 1
			bfs_seeds.append(_rand_seed)
	_hat_pick_mode = 0
	var ctl_ok: bool = bfs_bad >= 1
	if not ctl_ok:
		ok = false
	print("[hattest] ⑤ 阴性对照（切回裸 BFS，扫 12 颗种子）：出现「一口气」尖头的种子 %d 颗（须 ≥1）→ %s%s"
		% [bfs_bad, "✓" if ctl_ok else "✗（探针是瞎的：它测不出已知的坏情况）",
			"  种子=" + str(bfs_seeds) if bfs_bad > 0 else ""])

	# ⑤ 平滑器阴性对照：把「选区平滑」关掉扫同样 8 颗种子 —— 填充谷必须**不高于**开着时，
	#    且开着时换片数 > 0（机制真的开过火），否则说明平滑器没在干活（探针没牙）。
	#    种子与主循环 ⑤ 完全同源（3000 + i×7919），填充率差值只来自平滑器本身。
	_hat_round_mode = 1
	var fill_off := INF
	var hull_off := INF
	for _i in 8:
		_rand_seed = 3000 + _i * 7919
		generate_hat()
		fill_off = minf(fill_off, (_rand_shape_metrics() as Array[float])[1])
		hull_off = minf(hull_off, (_rand_shape_metrics() as Array[float])[2])
	_hat_round_mode = 0
	var fill_on := INF
	var hull_on := INF
	for _i in 8:
		_rand_seed = 3000 + _i * 7919
		generate_hat()
		fill_on = minf(fill_on, (_rand_shape_metrics() as Array[float])[1])
		hull_on = minf(hull_on, (_rand_shape_metrics() as Array[float])[2])
	var rctl_ok: bool = hull_on >= hull_off and round_any > 0
	if not rctl_ok:
		ok = false
	print("[hattest] ⑤ 平滑器对照（同 8 颗种子）：凸包谷 开 %.3f vs 关 %.3f（开须 ≥ 关）| 矩形谷 开 %.2f vs 关 %.2f | 换片 %d → %s"
		% [hull_on, hull_off, fill_on, fill_off, round_any, "✓" if rctl_ok else "✗（平滑器没干活或没效果）"])

	# ⑤ 正面检查（比上面的 8 颗种子更狠）：**默认算法**扫 12 颗种子，每一颗都必须最小度 ≥2。
	#   种类参数完全不参与选区（选区只用图距离/邻居计数/前沿进入序），所以只测帽子档即可覆盖三档
	#   —— ⑥ 已另证「同种子三档同一张组合盘」。这条才是「用户要的那个性质」的直接验收。
	GameConfig.hat_kind = GameConfig.HAT_HAT
	var pos_bad: Array[int] = []
	for _i in 12:
		_rand_seed = 3000 + _i * 7919
		generate_hat()
		if _adj_min_degree() <= 1:
			pos_bad.append(_rand_seed)
	var pos_ok: bool = pos_bad.is_empty()
	if not pos_ok:
		ok = false
	print("[hattest] ⑤ 正面检查（默认算法扫 12 颗种子）：出现「一口气」尖头的种子 %d 颗（须 0）→ %s"
		% [pos_bad.size(), "✓" if pos_ok else "✗ 种子=" + str(pos_bad)])

	# ⑥ 跨档同构：**同一颗种子下三档必须给出同一张组合盘**（只有坐标被边长缩放）。
	#    判据用「格数 + 邻接度直方图」——两者都是纯组合量，与坐标无关，是最贴题的口径。
	#    这条是「三档共用同一份池/装配/邻接代码」的验收：哪天有人给某一档另写一套生成器，
	#    或者种类参数不小心漏进 rng 流（多/少消费一次随机数 → 种子片或朝向漂移），这里立刻红。
	print("[hattest] ===== ⑥ 跨档同构（同种子 → 同格数 + 同邻接度直方图）=====")
	_rand_seed = 3000
	var ref_n := -1
	var ref_hist := ""
	var ref_deg := 0
	var iso := true
	for kind in kinds:
		GameConfig.hat_kind = kind
		generate_hat()
		var h: String = _adj_histogram()
		if ref_n < 0:
			ref_n = tiles.size()
			ref_hist = h
			ref_deg = _adj_max_degree()
			# 防「空探针的假相等」：参照值本身必须有内容（盘够大、直方图非空），
			# 否则三档同为「空盘 + 直方图[]」也能"通过"，那种相等毫无意义。
			if ref_n < 20 or ref_hist == "直方图[]":
				iso = false
			continue
		var same_iso: bool = tiles.size() == ref_n and h == ref_hist
		if not same_iso:
			iso = false
		print("[hattest] ⑥ %s：格数 %d（参照 %d）| 最大度 %d（参照 %d）| %s → %s"
			% [_hat_kind_name(kind), tiles.size(), ref_n, _adj_max_degree(), ref_deg, h,
				"✓" if same_iso else "✗ 与参照档不同（种类不该改拓扑）"])
	if not iso:
		ok = false
	print("[hattest] ⑥ 同种子 %d 三档同构：参照（帽子）格数 %d / %s → %s"
		% [_rand_seed, ref_n, ref_hist,
			"✓ 三档拓扑逐位相同（种类只换边长、不动拓扑）" if iso else "✗"])

	GameConfig.board_size = saved_size
	GameConfig.hat_kind = saved_kind
	_apply_board_size(saved_size)
	print("[hattest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()


## 最大邻接度（自检用）：帽子盘上限 13（14 顶点 − 1 共线点 = 13 条有效边）
## 当前盘面的最小邻接度。**1 = 边界上「只有一口气」的尖头**（唯一邻居一落子就无气被提），
## 正常盘必须 ≥2；度数 0 = 孤立格（更不允许）。
func _adj_min_degree() -> int:
	if tiles.size() <= 0:
		return 0
	var m := 999999
	for i in range(tiles.size()):
		m = mini(m, (adjacency[i] as Array).size())
	return m


func _adj_max_degree() -> int:
	var m := 0
	for i in range(tiles.size()):
		m = maxi(m, (adjacency[i] as Array).size())
	return m


## 邻接直方图 + 连通块数（自检用）：`min~max` 会被中间的空档掩盖，
## 「邻接 2~3 但全盘不连通」这种自相矛盾的读数必须靠直方图定位。
func _adj_histogram() -> String:
	var hist: Dictionary = {}
	for i in range(tiles.size()):
		var d: int = adjacency[i].size()
		hist[d] = int(hist.get(d, 0)) + 1
	var keys: Array = hist.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%d度×%d" % [int(k), int(hist[k])])
	return "直方图[" + ", ".join(parts) + "]"


## 连通块数（自检用）
func _component_count() -> int:
	var seen: Array = []
	seen.resize(tiles.size())
	var n := 0
	for s in range(tiles.size()):
		if seen[s]:
			continue
		n += 1
		seen[s] = true
		var stack: Array[int] = [s]
		while stack.size() > 0:
			var cur: int = stack.pop_back()
			for nb in adjacency[cur]:
				if not seen[nb]:
					seen[nb] = true
					stack.append(nb)
	return n


## 自检（--kitetest）：筝形几何的数学健全性。这块几何错了整档棋盘全废，故断言到数学量上：
##   ① 每块筝形：**两组邻边长度分别是 a/2 与 a/(2√3)**（环序下恰好是 [长,长,短,短] 的循环移位）
##      —— 短边取错（比如漏了 /2）立刻暴露；
##   ② 每块的角度谱恰好是 **60°（尖角）/ 90° / 120°（钝角）/ 90°**，不能多也不能少；
##   ③ **钝角相对**：同一三角形的三块筝形，钝角顶点必须**共点**（都落在三角形中心）；
##   ④ 尖角（60°）三顶点必须**两两互异**（三块各自占据一个三角形顶点）——
##      这一条专抓「三块绕同一顶点摆」那种看似合理的错排；
##   ⑤ **无缝无叠**：三块面积之和 == 等边三角形面积，且一条边至多被 2 块共享；
##   ⑥ 装配后：格数 == 3×三角形数、全盘连通、邻接上下界合理、星位 7 个；
##   ⑥b **边界是正六边形**（`_kite_hex_boundary_report`）：单一闭环、连续同向段恰好 6 段、
##      各段等长、方向谱恰为 {0°,60°,120°} 各两次 —— 标准档 R=3 与加强档 R=4 各查一遍；
##   ⑦ 随机档：格数贴目标 / 连通 / 同种子复现 / 不同种子多样。
##
## ⚠️ 第 ⑥ 条**不再是** `格数 == 6×菱形数`：正六边形选区在边缘会切出**半菱形**
## （只有一个三角形入选），所以格数 = 3×三角形数，且 `tiles.size() % 6 != 0` 是正常的。
##
## 坑：本函数里几何断言必须**逐个三角形独立累计**，不要用 `ang_ok` 之类的中间标志短路
## 后续统计 —— 一旦短路，所有计数会一起爆成「三角形总数」，看不出到底哪一项坏。
func _kite_self_test() -> void:
	var ok := true
	var a := 1.0                          # 等边三角形边长（= 菱形的边 = 共享边 A-B 的长度）
	var lng: float = a * 0.5              # 筝形**长边** = a/2（尖角顶点到两腰中点）
	var b: float = a * 0.5 / _KITE_SQ3    # 筝形**短边** = a/(2√3)（钝角顶点到两腰中点）
	var tri_area: float = _KITE_SQ3 * 0.25 * a * a      # 等边三角形面积 = √3/4·a²

	# ①②③④⑤ 逐块查几何
	var coords := _kite_patch_coords(1)
	vertices.clear(); tiles.clear(); tile_colors.clear(); adjacency.clear(); board.clear()
	var tri_first := _build_kite_from_coords(coords)
	var n_tri: int = coords.size() * 2
	if tiles.size() != coords.size() * 6:
		ok = false
		print("[kitetest] 格数 != 菱形数×6：", tiles.size(), " vs ", coords.size() * 6)
	for i in range(tiles.size()):
		if tiles[i].size() != 4:
			ok = false
			print("[kitetest] 第 ", i, " 块不是四边形（size=", tiles[i].size(), "）")
			break
	var checked := 0
	var bad_lens := 0
	var bad_ang := 0
	var bad_common := 0
	var bad_spike := 0
	var bad_area := 0
	var bad_order := 0
	for ti in n_tri:
		var base: int = ti * 3
		var polys: Array = []
		for j in 3:
			var vs: Array = tiles[base + j]
			var poly: Array[Vector2] = []
			for k in 4:
				poly.append(vertices[vs[k]])
			polys.append(poly)
			# ① 邻边长度：四条边恰好是 {长,长,短,短} = {a/2, a/2, a/(2√3), a/(2√3)}。
			#    **必须**取排序后逐位比 —— 本盘的边序是 [短,长,长,短]（两长边相邻、
			#    两短边也相邻），「环序移位等于 [长,长,短,短]」那种写法永远匹配不上。
			#    也**必须**拿 a/2 当长边：`a` 是等边三角形的边长，不是筝形的边。
			var L: Array[float] = []
			for k in 4:
				L.append(poly[k].distance_to(poly[(k + 1) % 4]))
			L.sort()
			if absf(L[0] - b) > 1e-4 or absf(L[1] - b) > 1e-4 \
					or absf(L[2] - lng) > 1e-4 or absf(L[3] - lng) > 1e-4:
				bad_lens += 1

		# ② 角度谱：每块必须恰好是 60°/90°/120°/90°，
		#    且**顶点序**与 `_kite_quad_pts` 的返回序一致 —— 钝角固定在索引 2
		#    （`_kite_quad_pts` 三个分支的第 3 项都是三角形中心 O）。
		#    顺序错了虽然几何一样，但三块的编号会互相打架（邻接/星位/快照都按编号走），
		#    所以单独记一个 bad_order。
		var spike: Array[Vector2] = []           # 该三角形三块的尖角（60°）顶点
		var obt: Array[Vector2] = []              # 该三角形三块的钝角（120°）顶点
		var ang_ok := true
		for j in 3:
			var poly2: Array[Vector2] = polys[j]
			var n60 := 0
			var n90 := 0
			var n120 := 0
			var i60 := -1
			var i120 := -1
			for k in 4:
				var p0: Vector2 = poly2[(k + 3) % 4]
				var p1: Vector2 = poly2[k]
				var p2: Vector2 = poly2[(k + 1) % 4]
				# 内角 = 两条邻边的无向夹角。**不能**用 `angle_to`（有符号，>180° 的角
				# 会以负值返回，120° 变成 -120°，直接判反）；acos 的向量形式最稳。
				var v1: Vector2 = (p0 - p1).normalized()
				var v2: Vector2 = (p2 - p1).normalized()
				var ang: float = rad_to_deg(acos(clampf(v1.dot(v2), -1.0, 1.0)))
				if absf(ang - 120.0) < 0.5:
					n120 += 1
					i120 = k
				elif absf(ang - 60.0) < 0.5:
					n60 += 1
					i60 = k
				elif absf(ang - 90.0) < 0.5:
					n90 += 1
			if n60 != 1 or n90 != 2 or n120 != 1:
				ang_ok = false
			# 环序约定：钝角恒在索引 2，尖角在索引 0（gidx0）或索引 3（gidx1/2）
			if i120 != 2 or (i60 != 0 and i60 != 3):
				bad_order += 1
			if i60 >= 0:
				spike.append(poly2[i60])
			if i120 >= 0:
				obt.append(poly2[i120])
		if not ang_ok:
			bad_ang += 1

		# ③ 钝角共点：三块钝角必须落在同一点（= 三角形中心）
		if obt.size() == 3:
			if obt[0].distance_to(obt[1]) > 1e-3 or obt[0].distance_to(obt[2]) > 1e-3:
				bad_common += 1
		else:
			bad_common += 1

		# ④ 尖角互异：三块尖角两两不重合（专抓「三块绕同一顶点摆」那种看似合理的错排）
		if spike.size() == 3:
			var dup := false
			for j in 3:
				for k in range(j + 1, 3):
					if spike[j].distance_to(spike[k]) < 1e-3:
						dup = true
			if dup:
				bad_spike += 1
		else:
			bad_spike += 1
		# ⑤ 面积和 == 等边三角形面积
		var area_sum := 0.0
		for j in 3:
			var poly3: Array[Vector2] = polys[j]
			var cs := 0.0
			for k in 4:
				cs += poly3[k].cross(poly3[(k + 1) % 4])
			area_sum += absf(cs) * 0.5
		if absf(area_sum - tri_area) > 1e-4:
			bad_area += 1
		checked += 1
	if bad_lens > 0:
		ok = false
	if bad_ang > 0:
		ok = false
	if bad_common > 0:
		ok = false
	if bad_spike > 0:
		ok = false
	if bad_order > 0:
		ok = false
	if bad_area > 0:
		ok = false
	print("[kitetest] 筝形：查 %d 个三角形 | 边 长=%.4f 短=%.4f | 边长不符 %d | 角度谱不符 %d | 环序不符 %d | 钝角不共点 %d | 尖角重合 %d | 面积和不符 %d" % [
		checked, lng, b, bad_lens, bad_ang, bad_order, bad_common, bad_spike, bad_area])

	# ⑤b 无重叠：一条边至多 2 块共享
	var edge_count: Dictionary = {}
	for tt in tiles:
		for k in 4:
			var key: String = "%d,%d" % [mini(tt[k], tt[(k + 1) % 4]), maxi(tt[k], tt[(k + 1) % 4])]
			edge_count[key] = int(edge_count.get(key, 0)) + 1
	var over := 0
	for key in edge_count:
		if int(edge_count[key]) > 2:
			over += 1
	if over > 0:
		ok = false
	print("[kitetest] 边共享：重叠边（≥3 块）=%d %s | 边界边（1 块）=%d" % [
		over, "✓" if over == 0 else "✗", n_border_edges(edge_count)])

	# ⑤ 固定盘装配 + 星位 + **正六边形边界断言**
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	generate_kite()
	# ⚠️ 正六边形选区在边缘会切出**半菱形**（只有一个三角形入选）→ 不再是 6 的倍数。
	# 改为断言「格数 == 三角形数 × 3」，三角形数由选区自己给出。
	var std_cells := _kite_hex_cells(3.0)
	var std_tri_pairs: int = 0
	for c in std_cells:
		if c.z == 0:
			std_tri_pairs += 1
	var expect_tiles: int = std_cells.size() * 3
	if tiles.size() != expect_tiles:
		ok = false
		print("[kitetest] 固定盘格数不符（正六边形选区）：", tiles.size(), " vs ", expect_tiles)
	if not _all_tiles_connected():
		ok = false
		print("[kitetest] 固定盘不连通（连通块 ", _component_count(), "）")
	var max_adj := 0
	var min_adj := 99
	for i in range(tiles.size()):
		max_adj = maxi(max_adj, adjacency[i].size())
		min_adj = mini(min_adj, adjacency[i].size())
	if min_adj < 1 or max_adj > 4:
		ok = false
		print("[kitetest] 固定盘邻接越界：min=", min_adj, " max=", max_adj, "（期望 1~4）")
	if _cube_star_tiles.size() != 7:
		ok = false
		print("[kitetest] 固定盘星位数不符：", _cube_star_tiles.size(), "（期望 7）")
	# **边界形状断言**：把边界边按「六边形距离」归类，必须得到正六边形
	var hexb := _kite_hex_boundary_report()
	for k in hexb:
		if k != "vertices" and not bool(hexb[k]):
			ok = false
	print("[kitetest] 标准盘：菱形 %d | 落子格 %d | 顶点 %d | 星位 %d | 邻接 %d~%d %s" % [
		std_cells.size() - std_tri_pairs, tiles.size(), vertices.size(), _cube_star_tiles.size(),
		min_adj, max_adj, _adj_histogram()])

	# ⑤b 加强档：R=4 → 96 三角形 / 288 格，同样必须是正六边形
	#     ⚠️ 必须显式调 `_apply_board_size()` —— 它才负责把尺寸档翻译成 `_kite_r_actual`；
	#     光设 `GameConfig.board_size` 不会生效（`generate_kite()` 不读尺寸档本身）。
	GameConfig.board_size = GameConfig.ENHANCED
	_apply_board_size(GameConfig.ENHANCED)
	generate_kite()
	var enh_cells := _kite_hex_cells(4.0)
	if tiles.size() != enh_cells.size() * 3:
		ok = false
		print("[kitetest] 加强盘格数不符：", tiles.size(), " vs ", enh_cells.size() * 3, "（期望 288）")
	if not _all_tiles_connected():
		ok = false
		print("[kitetest] 加强盘不连通（连通块 ", _component_count(), "）")
	if _cube_star_tiles.size() != 7:
		ok = false
		print("[kitetest] 加强盘星位数不符：", _cube_star_tiles.size(), "（期望 7）")
	print("[kitetest] 加强盘：%d 格 | 星位 %d %s" % [
		tiles.size(), _cube_star_tiles.size(), "✓" if tiles.size() == 288 else "✗"])
	var hexb2 := _kite_hex_boundary_report()
	for k in hexb2:
		if k != "vertices" and not bool(hexb2[k]):
			ok = false
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)

	# ⑥ 三固定档：迷你(R=2)/标准(R=3)/加强(R=4)。筝形已无随机档（2026-09-16）——
	#    原随机 8 局测试随随机模式一起移除，改为验证三档的 6R² 格数阶梯 + 连通 + 星位
	#    + 复现性（固定盘两次生成必须同指纹）+ 正六边形边界。
	#    ⚠️ 必须显式调 `_apply_board_size()` —— 只有它负责把尺寸档翻译成 `_kite_r_actual`；
	#    光设 `GameConfig.board_size` 不会生效（`generate_kite()` 不读尺寸档本身）。
	#    迷你档占用全局 RANDOM 槽位（菜单槽位 0 在筝形下显示「迷你」）。
	var ladder := [
		{"size": GameConfig.RANDOM, "name": "迷你", "r": 2.0, "tiles": 72},
		{"size": GameConfig.STANDARD, "name": "标准", "r": 3.0, "tiles": 162},
		{"size": GameConfig.ENHANCED, "name": "加强", "r": 4.0, "tiles": 288},
	]
	for ld in ladder:
		GameConfig.board_size = ld["size"]
		_apply_board_size(ld["size"])
		generate_kite()
		var ld_cells := _kite_hex_cells(ld["r"])
		if tiles.size() != ld_cells.size() * 3 or tiles.size() != int(ld["tiles"]):
			ok = false
			print("[kitetest] ", ld["name"], "盘格数不符：", tiles.size(), " vs 选区 ",
				ld_cells.size() * 3, " / 阶梯 ", ld["tiles"])
		if not _all_tiles_connected():
			ok = false
			print("[kitetest] ", ld["name"], "盘不连通（连通块 ", _component_count(), "）")
		if _cube_star_tiles.size() != 7:
			ok = false
			print("[kitetest] ", ld["name"], "盘星位数不符：", _cube_star_tiles.size(), "（期望 7）")
		var fp_mini: int = _board_fingerprint()
		generate_kite()
		if _board_fingerprint() != fp_mini:
			ok = false
			print("[kitetest] ", ld["name"], "盘两次生成不一致（固定盘必须恒定）")
		var hexb3 := _kite_hex_boundary_report()
		for k in hexb3:
			if k != "vertices" and not bool(hexb3[k]):
				ok = false
		print("[kitetest] ", ld["name"], "盘（R=%d）：格数 %d %s | 星位 %d | 复现 ✓ | 正六边形边界 ✓" % [
			int(ld["r"]), tiles.size(),
			"✓" if tiles.size() == int(ld["tiles"]) else "✗", _cube_star_tiles.size()])
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	print("[kitetest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()


## 自检（--randtest）：随机棋盘的格数 / 连通性 / 复现性 / 多样性。
## 这四项是随机盘能不能上桌的硬门槛：
##   ① 格数必须稳定落在「目标 ± 浮动」附近（否则「约 200 格」就是空话）；
##   ② 全盘必须连通（有孤块 = 有格子下不进去）；
##   ③ 同种子必须复现同一张盘（联机靠种子同步，这条挂了双端就会错盘）；
##   ④ 不同种子必须给出不同的盘（否则「随机」是假的）。
func _rand_self_test() -> void:
	var ok := true
	var n := 12
	var saved_type: int = GameConfig.board_type
	var saved_size: int = GameConfig.board_size
	# 筝形盘已无随机档，不进这个循环 —— 「互不相同/每局换盘」断言对固定盘不适用。
	# 它的 RANDOM 槽位 = 迷你固定盘，恒定性单独在循环后验证。
	# 雪花 2026-09-16（四格网随机相位 + 偏心取景）、帽子 2026-09-19（池 + 随机种子片 +
	# 整盘朝向）都有真随机档，一起验。
	for bt in [GameConfig.BOARD_PENROSE, GameConfig.BOARD_CUBE, GameConfig.BOARD_SNOWFLAKE,
			GameConfig.BOARD_HAT]:
		GameConfig.board_type = bt
		GameConfig.board_size = GameConfig.RANDOM
		_apply_board_size(GameConfig.RANDOM)
		var tname: String = "彭罗斯" if bt == GameConfig.BOARD_PENROSE \
			else ("立方体" if bt == GameConfig.BOARD_CUBE \
				else ("雪花" if bt == GameConfig.BOARD_SNOWFLAKE else "帽子"))
		# 爱因斯坦随机档用自己的目标格数（hat_rand_tiles，240~300 窗口），不用全局的
		var tgt: int = hat_rand_tiles if bt == GameConfig.BOARD_HAT else random_target_tiles
		var counts: Array[int] = []
		var fps: Dictionary = {}
		var worst_gap := 0
		var aspect_lo := INF
		var aspect_hi := 0.0
		var fill_lo := INF
		var fill_hi := 0.0
		for i in n:
			_rand_seed = 1000 + i * 7919
			generate_board()
			counts.append(tiles.size())
			var fp := _board_fingerprint()
			fps[fp] = true
			var gap: int = absi(tiles.size() - tgt)
			if gap > worst_gap:
				worst_gap = gap
			var m: Array[float] = _rand_shape_metrics()
			aspect_lo = minf(aspect_lo, m[0]); aspect_hi = maxf(aspect_hi, m[0])
			fill_lo = minf(fill_lo, m[1]); fill_hi = maxf(fill_hi, m[1])
			if not _all_tiles_connected():
				ok = false
				print("[randtest] ", tname, " 种子 ", _rand_seed, " 盘面不连通！")
			# 复现性：同种子再生成一次，指纹必须一致
			generate_board()
			if _board_fingerprint() != fp:
				ok = false
				print("[randtest] ", tname, " 种子 ", _rand_seed, " 同种子两次生成不一致！")
			if tiles.size() < 2 or vertices.size() < 2:
				ok = false
				print("[randtest] ", tname, " 种子 ", _rand_seed, " 盘面过小")
		var lo: int = counts[0]
		var hi: int = counts[0]
		var sum := 0
		for c in counts:
			lo = mini(lo, c)
			hi = maxi(hi, c)
			sum += c
		var band_ok: bool = worst_gap <= random_tile_jitter + 6
		if not band_ok:
			ok = false
		var uniq_ok: bool = fps.size() == n
		if not uniq_ok:
			ok = false
		# 形状门槛：长宽比 ≤1.6（不能太扁）、填充率 ≥0.55（不能被削平或拖出长条）
		var shape_ok: bool = aspect_hi <= 1.6 and fill_lo >= 0.55
		if not shape_ok:
			ok = false
		print("[randtest] %s 目标=%d±%d | 格数 %d~%d 均值 %.1f | 离目标最远 %d 格 %s | 互不相同 %d/%d %s" % [
			tname, tgt, random_tile_jitter, lo, hi,
			float(sum) / float(counts.size()), worst_gap, "✓" if band_ok else "✗",
			fps.size(), n, "✓" if uniq_ok else "✗"])
		# 「每局开局都换一张盘」：走的是玩家真正会走的路径（restart_game 重抽种子）
		var restart_fps: Dictionary = {}
		for i in 3:
			restart_game()
			restart_fps[_board_fingerprint()] = true
		if restart_fps.size() != 3:
			ok = false
			print("[randtest] ", tname, " 连续开新局盘面没有变化（随机档没起作用）")
		print("[randtest]   连续开 3 局：盘面互不相同 ", restart_fps.size(), "/3 ",
			"✓" if restart_fps.size() == 3 else "✗")
		print("[randtest]   形状：长宽比 %.2f~%.2f | 填充率 %.2f~%.2f %s" % [
			aspect_lo, aspect_hi, fill_lo, fill_hi, "✓" if shape_ok else "✗（太扁或被削平）"])
	# 筝形（唯一无随机档）：RANDOM 槽位 = 迷你固定盘（R=2）。固定盘不重抽种子也不重生成
	#（_regen_on_restart 对非随机盘恒 false），所以这里只验「恒定」而非「每局换盘」。
	GameConfig.board_type = GameConfig.BOARD_KITE
	GameConfig.board_size = GameConfig.RANDOM
	_apply_board_size(GameConfig.RANDOM)
	generate_board()
	var mini_tiles: int = tiles.size()
	var mini_fp: int = _board_fingerprint()
	generate_board()
	var mini_stable: bool = (mini_tiles == 72) and (_board_fingerprint() == mini_fp)
	if not mini_stable:
		ok = false
		print("[randtest] 筝形迷你盘不恒定：格数=", mini_tiles, "（期望 72），指纹一致=",
			_board_fingerprint() == mini_fp)
	print("[randtest] 筝形（无随机档）：迷你固定盘 %d 格，两次生成 %s" % [
		mini_tiles, "恒定 ✓" if mini_stable else "✗"])
	GameConfig.board_type = saved_type
	GameConfig.board_size = saved_size
	print("[randtest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()

## 整张盘的指纹（顶点数 + 瓷砖顶点表）：用于「同种子必复现 / 不同种子必不同」的断言
func _board_fingerprint() -> int:
	var s: String = "%d/%d" % [tiles.size(), vertices.size()]
	for t in tiles:
		s += "|" + str(t)
	return s.hash()

## **最小面积外接矩形**（旋转不变）：返回 [长宽比(≥1), 矩形面积]。
## 枚举凸包的每条边当矩形一条边（最小面积矩形必有一边贴合凸包边），取面积最小者。
## 点少于 3 个时返回 [1.0, 0.0]。
func _min_area_rect(points: Array) -> Array[float]:
	if points.size() < 3:
		return [1.0, 0.0]
	var hull: PackedVector2Array = Geometry2D.convex_hull(PackedVector2Array(points))
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	var hn: int = hull.size()
	var best_area := INF
	var bw := 1.0
	var bh := 1.0
	for i in hn:
		var e: Vector2 = hull[(i + 1) % hn] - hull[i]
		var L: float = e.length()
		if L < 1e-9:
			continue
		var u: Vector2 = e / L
		var v := Vector2(-u.y, u.x)
		var lo_u := INF
		var hi_u := -INF
		var lo_v := INF
		var hi_v := -INF
		for p in hull:
			var du: float = p.dot(u)
			var dv: float = p.dot(v)
			lo_u = minf(lo_u, du)
			hi_u = maxf(hi_u, du)
			lo_v = minf(lo_v, dv)
			hi_v = maxf(hi_v, dv)
		var a: float = (hi_u - lo_u) * (hi_v - lo_v)
		if a < best_area:
			best_area = a
			bw = hi_u - lo_u
			bh = hi_v - lo_v
	bw = maxf(bw, 1e-6)
	bh = maxf(bh, 1e-6)
	return [maxf(bw / bh, bh / bw), best_area]


## 形状体检（自检用）：[长宽比, 填充率]。
## 长宽比 ≈ 1 表示盘面不扁；填充率 = 瓷砖总面积 / 外接矩形面积，正圆约 0.785。
##
## ⚠️ **外接矩形必须用「最小面积外接矩形」而不是轴对齐包围盒**（2026-09-19 改）：
## 随机帽子盘会整盘转一个随机角，而**轴对齐盒子的面积是随朝向变的** —— 实测同一张
## 200 片球，0° 时填充率 0.70、30° 时掉到 0.61，于是「朝向不同」被误判成「盘面被削平」
## （--hattest ⑤ 一度报 0.52 假红）。最小面积外接矩形**旋转不变**，且是同一盘在任何
## 朝向下都成立的真指标。
## 对已有盘：矩形变小 → 填充率只会变高（阈值 0.55 更安全），长宽比变成真伸缩比。
## 顶点集凸包面积（Andrew 单调链，O(n log n)）。自检用。
func _convex_hull_area(pts: Array) -> float:
	if pts.size() < 3:
		return 0.0
	var ps: Array = pts.duplicate()
	ps.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	var cross := func(o: Vector2, a: Vector2, b: Vector2) -> float:
		return (a - o).cross(b - o)
	var lo: Array = []
	for p in ps:
		while lo.size() >= 2 and cross.call(lo[lo.size() - 2], lo[lo.size() - 1], p) <= 0.0:
			lo.pop_back()
		lo.append(p)
	var up: Array = []
	for i in ps.size():
		var p: Vector2 = ps[ps.size() - 1 - i]
		while up.size() >= 2 and cross.call(up[up.size() - 2], up[up.size() - 1], p) <= 0.0:
			up.pop_back()
		up.append(p)
	var hull: Array = lo
	hull.append_array(up.slice(1, -1))
	var a := 0.0
	for i in hull.size():
		a += (hull[i] as Vector2).cross(hull[(i + 1) % hull.size()])
	return absf(a) * 0.5


func _rand_shape_metrics() -> Array[float]:
	var rect: Array[float] = _min_area_rect(vertices)
	var area_sum := 0.0
	for i in tiles.size():
		var vs: Array = tiles[i]
		var n: int = vs.size()
		var cross_sum := 0.0
		for k in n:
			cross_sum += vertices[vs[k]].cross(vertices[vs[(k + 1) % n]])
		area_sum += absf(cross_sum) * 0.5
	var rect_area: float = maxf(rect[1], 1e-6)
	# 凸包填充率 = 盘面积 / 凸包面积：圆盘 ≈1.0；**凹口（用户报的「缺口」）立刻掉** ——
	# 矩形填充率对不触及矩形极值点的凹口是瞎的（矩形不变、面积恒为 格数×单片面积）。
	var hull_area: float = maxf(_convex_hull_area(vertices), 1e-6)
	return [rect[0], area_sum / rect_area, area_sum / hull_area]

## 连通性：从 0 号格 BFS，能否走遍全盘
func _all_tiles_connected() -> bool:
	if tiles.size() == 0:
		return false
	var seen: Dictionary = {0: true}
	var stack: Array[int] = [0]
	while stack.size() > 0:
		var cur: int = stack.pop_back()
		for nb in adjacency[cur]:
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() == tiles.size()

## 立方体盘自检（仅 --cubetest 触发）：校验六边形数/瓷砖数/邻接/星位/落子格数，并退出。
func _cube_self_check() -> void:
	var ok := true
	var expect_hex := 3 * _cube_hex_r * _cube_hex_r + 3 * _cube_hex_r + 1
	var expect_tiles := expect_hex * 3
	# 随机档没有「R 环 = 3R²+3R+1 个六边形」这个等式，改判「格数落在目标带内」
	if _is_random_board():
		if absi(tiles.size() - random_target_tiles) > random_tile_jitter + 6:
			ok = false
			print("[自检] 随机盘格数跑偏：实际 ", tiles.size(), " 目标 ", random_target_tiles,
				"±", random_tile_jitter)
		if tiles.size() % 3 != 0:
			ok = false
			print("[自检] 随机盘格数不是 3 的倍数（六边形被切开了）：", tiles.size())
	elif tiles.size() != expect_tiles:
		ok = false
		print("[自检] 瓷砖数不符：实际 ", tiles.size(), " 期望 ", expect_tiles, "(=", expect_hex, " 六边形 ×3)")
	if vertices.size() < 2:
		ok = false
		print("[自检] 顶点数异常：", vertices.size())
	# 校验每块菱形都有 4 个顶点
	for i in range(tiles.size()):
		if tiles[i].size() != 4:
			ok = false
			print("[自检] 第 ", i, " 块不是四边形（size=", tiles[i].size(), "）")
			break
	# 校验邻接表：每块菱形 1~4 邻（立方体盘每面最多 4 邻）
	var max_adj := 0
	for i in range(tiles.size()):
		max_adj = maxi(max_adj, adjacency[i].size())
	# 边界块（角上）应至少 1 邻；中心块可达 4 邻
	if max_adj < 1 or max_adj > 4:
		ok = false
		print("[自检] 邻接数异常：最大 ", max_adj, "（期望 1~4）")
	# 星位：中心六边形 + 六个角 → 共 7 块
	if _cube_star_tiles.size() != 7:
		ok = false
		print("[自检] 星位数不符：", _cube_star_tiles.size(), "（期望 7）")
	# 一致性：每格都可达（连通性）— BFS 从 0 出发
	var seen: Dictionary = {}
	var stack: Array[int] = [0]
	seen[0] = true
	while stack.size() > 0:
		var cur: int = stack.pop_back()
		for nb in adjacency[cur]:
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	if seen.size() != tiles.size():
		ok = false
		print("[自检] 连通性失败：可达 ", seen.size(), " / ", tiles.size())
	print("[自检] 立方体盘 R=", _cube_hex_r, " | 六边形 ",
		(tiles.size() / 3) if _is_random_board() else expect_hex,
		" | 瓷砖 ", tiles.size(),
		" | 顶点 ", vertices.size(), " | 星位 ", _cube_star_tiles.size(), " | 最大邻接 ", max_adj,
		" | 结果：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()


## 第 i 块瓷砖的顶点（像素坐标，已是环序）
func _tile_poly(i: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for idx in tiles[i]:
		poly.push_back(vertices[idx])
	return poly


## 第 i 块瓷砖的四条边长（用于比对两块砖是否全等）
# ====== Robinson 三角替换法辅助函数 ======
## Star 种子: 10 个锐角三角形围绕原点 (10×36° = 360°)
## 彭罗斯种子：围绕原点铺 10 个 Robinson 锐角三角形（标准「太阳」种子）。
## rot_rad / mirror 仅随机盘使用（随机朝向 → 每局截到的菱形网格指向不同方向）；
## 固定盘传默认 (0, false)，与旧版完全一致。
func _build_seed_star(rot_rad: float = 0.0, mirror: bool = false) -> Array:
	var tris: Array = []
	for i in range(10):
		var a1: float = (2.0 * float(i) - 1.0) * PI / 10.0 + rot_rad
		var a2: float = (2.0 * float(i) + 1.0) * PI / 10.0 + rot_rad
		var v2 := Vector2(cos(a1), sin(a1))
		var v3 := Vector2(cos(a2), sin(a2))
		if mirror:
			v2 = Vector2(v2.x, -v2.y)
			v3 = Vector2(v3.x, -v3.y)
		if i % 2 == 0:
			var t := v2
			v2 = v3
			v3 = t
		tris.append({"type": "acute", "pts": [Vector2.ZERO, v2, v3]})
	return tris


## deflation 一步:
##   锐角 (36°@pts[0]) → 1 锐角 + 1 钝角
##   钝角 (108°@pts[0]) → 2 钝角 + 1 锐角
func _deflate_all(tris: Array) -> Array:
	var out: Array = []
	for tri in tris:
		var t: String = tri["type"]
		var pts: Array = tri["pts"]
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var c: Vector2 = pts[2]
		if t == "acute":
			var p1: Vector2 = a + (b - a) / PHI
			out.append({"type": "acute",  "pts": [c, p1, b]})
			out.append({"type": "obtuse", "pts": [p1, c, a]})
		else:
			var p2: Vector2 = b + (a - b) / PHI
			var p3: Vector2 = b + (c - b) / PHI
			out.append({"type": "obtuse", "pts": [p3, c, a]})
			out.append({"type": "obtuse", "pts": [p2, p3, b]})
			out.append({"type": "acute",  "pts": [p3, p2, a]})
	return out


## 三角形按底边配对 → 菱形。
## 锐角对底边 = 瘦菱形 (thin); 钝角对底边 = 胖菱形 (fat)
func _build_rhombi(tris: Array) -> Dictionary:
	# 顶点去重（坐标 quantize 1e-4）
	var vkey_to_idx: Dictionary = {}
	var verts: Array[Vector2] = []
	var tri_vidx: Array = []
	for tri in tris:
		var idxs: Array[int] = []
		for p in tri["pts"]:
			var key: String = _vkey(p)
			if not vkey_to_idx.has(key):
				vkey_to_idx[key] = verts.size()
				verts.append(p)
			idxs.append(vkey_to_idx[key])
		tri_vidx.append(idxs)

	# 底边哈希: key → [三角形索引...]
	var edge_map: Dictionary = {}
	for i in range(tris.size()):
		var e: String = _edge_key(tri_vidx[i][1], tri_vidx[i][2])
		if not edge_map.has(e):
			edge_map[e] = []
		edge_map[e].append(i)

	# 同类型共享底边 → 配对成菱形
	var used: Dictionary = {}
	var rhombi: Array = []
	for i in range(tris.size()):
		if used.has(i):
			continue
		var e: String = _edge_key(tri_vidx[i][1], tri_vidx[i][2])
		var partner: int = -1
		for j in edge_map[e]:
			if j != i and not used.has(j) and tris[j]["type"] == tris[i]["type"]:
				partner = j
				break
		if partner != -1:
			used[i] = true
			used[partner] = true
			var ti: Array = tri_vidx[i]
			var tj: Array = tri_vidx[partner]
			# 环序: 底端1 → 顶点A → 底端2 → 顶点B
			rhombi.append({
				"type": "thin" if tris[i]["type"] == "acute" else "fat",
				"verts": [ti[1], ti[0], ti[2], tj[0]],
			})

	# 重建顶点表: 只保留菱形用到的顶点
	var old_to_new: Dictionary = {}
	var new_verts: Array[Vector2] = []
	for r in rhombi:
		var vs: Array = r["verts"]
		for k in range(vs.size()):
			var vi: int = vs[k]
			if not old_to_new.has(vi):
				old_to_new[vi] = new_verts.size()
				new_verts.append(verts[vi])
			vs[k] = old_to_new[vi]

	return {"rhombi": rhombi, "verts": new_verts}


## 圆形裁剪: 只保留中心距 <= radius 的菱形，同时重建顶点表
## center：窗口圆心（固定盘恒为原点；随机盘会随机偏心，见 _generate_penrose_random）
func _clip_rhombi(verts: Array, rhombi: Array, radius: float, center: Vector2 = Vector2.ZERO) -> Dictionary:
	var kept: Array = []
	var old_to_new: Dictionary = {}
	var new_verts: Array[Vector2] = []
	for r in rhombi:
		var c: Vector2 = Vector2.ZERO
		for vi in r["verts"]:
			c += verts[vi]
		c /= 4.0
		if (c - center).length() > radius:
			continue
		kept.append(r)
		var vs: Array = r["verts"]
		for k in range(vs.size()):
			var vi: int = vs[k]
			if not old_to_new.has(vi):
				old_to_new[vi] = new_verts.size()
				new_verts.append(verts[vi])
			vs[k] = old_to_new[vi]
	return {"rhombi": kept, "verts": new_verts}


func _vkey(p: Vector2) -> String:
	return "%06d_%06d" % [
		int(snappedf(p.x, 1e-4) * 10000.0),
		int(snappedf(p.y, 1e-4) * 10000.0),
	]


func _edge_key(a: int, b: int) -> String:
	return str(min(a, b)) + "," + str(max(a, b))


# ====== 点击检测 ======
func _setup_click_detection():
	click_area = Area2D.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# 这里的尺寸只是**临时占位**：真正的可点范围由 `_fit_click_area()` 在 `_adapt_to_screen()`
	# 末尾按棋盘包围盒贴合（写死尺寸会让窗口比例一变、边缘格子就点不动，见 `_fit_click_area()`）。
	rect.size = Vector2(2000, 2000)
	collision.shape = rect
	click_area.add_child(collision)
	add_child(click_area)
	click_area.input_event.connect(_on_area_input)

## 落子准入判据 —— ★★ **悬浮预览与真实点击共用同一个门槛**（改判据只改这一处）。
## 返回 "" = 这一手在流程/界面层面可下；否则返回**要打印的那句人话**（含前缀）。
##
## 为什么必须共用：预览若用另一套宽松判据，就会出现「半透明棋子挂着、
## 点下去一声不响」的错觉 —— 本工程「静默失败」同族坑（见 `_hat_dead_self_test()` 上方那段）。
## ⚠️ 这里只管**流程/界面**层；棋理层（已占 / 打劫 / 自杀）在 `can_place_at()`，
##    `_draw_hover_preview()` 两边都要过。
##
## tile_id >= 0 时额外查「格子中心是否被 HUD 的 STOP 控件压住」——
## 被压住的格子事件会被 GUI 吃掉（`_hat_dead_self_test()` 用真实合成点击证实过），
## 于是它同样属于「点了没反应」，预览也不该在它上面亮起来。
## （与 `--hatdead` ① 同口径：只查中心。格子边缘被压属于既有的已知行为，不在本判据范围内。）
func _place_block_reason(tile_id: int = -1) -> String:
	if game_over:
		return "[落子被忽略] 已终局"
	if is_ai_thinking:
		return "[落子被忽略] 电脑思考中（这期间点击全部无效）"
	# ESC 暂停面板开着：忽略落子。
	# ⚠️ 这里原本写着「物理拾取与 GUI 遮罩是两条管线，遮罩的 mouse_filter=STOP 挡不住 Area2D 的
	#    input_event」——**实测是错的**：2026-09-21 用真实合成点击做 A/B 对照证明，点落在 STOP
	#    控件矩形内时 Area2D 的 `input_event` **不会触发**（GUI 先把事件标记为已处理，物理拾取
	#    跳过它）。所以这层显式拦截属于双保险（保留无害），但也意味着 **HUD 按钮压住的格子
	#    是真的点不动** —— 详见 `_fit_click_area()` 上方那段与 `_hat_dead_self_test()`。
	if _pause_layer != null:
		return "[落子被忽略] 暂停面板开着"
	# 人机模式：只有玩家（执黑）能点；本地双人：任意当前回合方都能点

	if game_mode == VS_AI and current_player != PLAYER_COLOR:
		return "现在是电脑思考时间，请稍候"
	if game_mode == ONLINE and not _can_local_play():
		# ★ 2026-10-21（用户口令「一定要双方都准备好了再进入对局」的另一面）：
		#   闸要挡住，**理由也要说得对**。座位可选之后，玩家在准备阶段点棋盘若被回一句
		#   「还没轮到你落子」，他会以为"对方在思考 / 是不是卡了"，而真实原因是
		#   **他自己没点「准备」**（或对方没点）。这两种情况的处置完全不同。
		#   ⚠️ 这条只改**文案**，判据一行没动 —— `_can_local_play()` 仍是唯一真源。
		if _net_phase == "ready":
			return "[落子被忽略] 双方都点「准备」后才开始对局"
		return "还没轮到你落子"
	if tile_id >= 0 and _tile_center_covered(tile_id):
		return "[落子被忽略] 该格被 HUD 控件压住（事件会被界面吃掉）"
	return ""

## 格子**中心**是否落在某个可见的 STOP 控件矩形内（HUD 遮挡判据，见 `_place_block_reason`）。
func _tile_center_covered(tile_id: int) -> bool:
	if tile_id < 0 or tile_id >= tile_centers.size():
		return false
	var stops: Array = []
	_collect_stop_controls(self, stops)
	var c: Vector2 = tile_centers[tile_id]
	for e in stops:
		if (e as Control).get_global_rect().has_point(c):
			return true
	return false

func _on_area_input(viewport, event, shape_idx):
	# 只在「左键按下」这一刻落子。忽略松开、鼠标移动(motion)等事件——
	# 否则按住拖动时 Area2D 会沿路径持续派发事件，导致连续落子（滑动落子）。
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	# ★★ 复盘态：点棋盘 = **跳到该格最后一手**（规划 §阶段② 的"点盘跳转"）。
	#   ⚠️ 必须排在 `_place_block_reason()` **之前**：那条闸按"轮到谁 / 是否 AI 思考"
	#      拒绝点击，而复盘态下这两件事与会话无关（`current_player` 由重放推进）
	#      ⇒ 放在后面会出现"点盘跳转只在某些手有效"这种**看起来随机**的失灵。
	if _replay != null:
		var rt: int = _tile_at_point(event.position)
		var rply: int = _rp_ply_of_tile(rt)
		if rply > 0:
			_rp_jump(rply)
			print("[复盘] 点第 %d 格 → 跳到第 %d 手" % [rt, rply])
		else:
			print("[复盘] 第 %d 格在谱里没有落子" % rt)
		return
	# ① 流程 / 界面层门槛（与悬浮预览共用）
	var reason := _place_block_reason()
	if reason != "":
		print(reason)
		return
	# ⚠️ 下面这条原本是**静默** return：点空处（瓷砖间隙 / 盘外）什么提示都没有，
	#    导出后（无控制台）与"自杀被拒"、"拾取框外"完全无法区分 —— 用户报"点不动"
	#    时没法定性。打印坐标后，任何一次点击无论成败都留痕。
	var tile_id := _tile_at_point(event.position)
	if tile_id == -1:
		print("[落子被忽略] 该点不在任何瓷砖内（间隙/盘外）坐标 %s" % str(event.position.round()))
		return  # 点在了瓷砖间隙/棋盘空白处
	# ② 同一门槛再带 tile 查一次（HUD 遮挡只有知道格子才判得了）
	reason = _place_block_reason(tile_id)
	if reason != "":
		print(reason)
		return
	if board[tile_id] != Stone.EMPTY:
		print("该瓷砖内已有棋子")
		return
	if game_mode == ONLINE:
		_net_send_action({"type": "place", "tile": tile_id, "color": current_player})
	else:
		if place_stone(tile_id):
			if game_mode == VS_AI and current_player == AI_COLOR:
				_start_ai_turn()


# ====== 围棋逻辑（气 / 连通块 / 提子）—— 2026-10-18 正文迁至 rules_kernel.gd ======
## ★ 规则内核拆分：本节 / superko / 数子判定的**函数体**迁到 `rules_kernel.gd`
##   （class RulesKernel，RefCounted；实例 `_rk` 在 `_ready()` 最先创建，经 `host`
##   反读本文件的棋盘状态）。**状态不搬**：board / adjacency / tiles / _superko_zob /
##   _superko_hist 等真源仍在本文件（rulestest 夹具 / place_stone / 悔棋 / 联机加入
##   4 处直接引用未动）。下面保留同名薄委托——调用点（AI / hover / 自检夹具 /
##   place_stone）零改动。内核侧逐字未动，只加了 `host.` 前缀。
var _rk: RulesKernel

func get_neighbors(tile_id: int) -> Array:
	return _rk.get_neighbors(tile_id)

func get_group(tile_id: int) -> Array[int]:
	return _rk.get_group(tile_id)

func get_liberties(group: Array[int]) -> int:
	return _rk.get_liberties(group)

## remove_group 宿主内无外部调用点（仅被同节 remove_dead_stones 使用）→ 随迁内核，
## 不留委托（2026-10-18）。
func remove_dead_stones(color: int) -> Array[int]:
	return _rk.remove_dead_stones(color)

# ====== superko（positional，2026-10-14，研报 §3 的规则补课）======
## 此前全工程只有**单点劫**（`ko_point` 只禁立即回提一格）⇒ 三劫 / 循环劫 / 多劫交替
## 可致对局无法终止（双方永不停手）。研报 §3 定案：这是唯一的规则缺口。
##
## ★ 口径 = **positional superko**：禁止「落子后局面」与**历史任一局面**相同。
##   pass 不产生新局面 ⇒ 不入历史，连停两手终局不受影响。
## ★ **只在真实对局生效**（`not _quiet_place`）—— 与 `_hist` 入栈同口径。理由实测：
##   `--rulestest`(6612) 与 `--hovertest`(17187) 的穷举对照都在 `_quiet_place = true` 下
##   手动 `board = snap_board` 回滚盘面，若也记历史会留脏条目；且探测性落子没有真实对局历史。
## ★ **hash 每次从 `board` 重算**，不做增量 XOR：120 格的 XOR 是微秒级（AI 200ms/手、
##   hover 每帧一次），换来"hash 不可能与 board 不同步"。工程里有 3 处手动回滚盘面，
##   增量维护要求每一次 board 变化都被跟踪 —— 任何绕过点都会**静默**不一致。
## ★ **同种子同生成式**（`SUPERKO_SEED`，与镜像 `_xg_reset()` 同一套）⇒ 同盘得同一张指纹表。
##   `--xgtest` 的两套 hash 因此可逐位对拍。
## ⚠️ 已知遗留：联机**中途加入**（`_apply_snapshot()` 直接设盘面）时，加入方的历史缺早期局面
##   ⇒ 其 superko 判定可能与房主不同。superko 局面本身罕见，影响面小；要做到底需让
##   快照携带历史（或加入时把当前局面并入历史）。**本轮不动联机侧**，在此留档。
## 2026-10-18 规则内核拆分：`SUPERKO_SEED` 与本节全部**函数体**（_superko_rand64 /
## _superko_rebuild_table / _superko_init / _superko_hash / _superko_commit /
## _superko_hash_after / _superko_blocks / can_place_at / _libs_of_group_excluding）
## 迁至 rules_kernel.gd（逐字未动，成员访问加 `host.` 前缀）。状态变量留宿主——
## rulestest 夹具 / place_stone / 悔棋 / 联机加入仍在直接读写它们。薄委托只列
## **宿主内确有调用点**的名字：_superko_rand64 / _superko_rebuild_table 内核自用、
## _superko_blocks 仅被内核 can_place_at 调 ⇒ 三者不留委托。
var _superko_zob: Dictionary = {}     # tile_id -> [空,黑,白] 三个 64 位数（索引 0 恒 0）
var _superko_hist: Dictionary = {}    # 历史局面指纹 -> true

func _superko_init() -> void:
	_rk._superko_init()

func _superko_hash() -> int:
	return _rk._superko_hash()

func _superko_commit() -> void:
	_rk._superko_commit()

func _superko_hash_after(tile_id: int, color: int) -> int:
	return _rk._superko_hash_after(tile_id, color)

## 这一手**棋理上是否可下**（空点 + 非劫点 + 不是自杀）—— ★ **只读、无副作用**，
## 2026-10-18 判据正文迁至 rules_kernel.gd（判定三条件 / 真源纪律的档案注释随迁）。
func can_place_at(tile_id: int, color: int = -1) -> bool:
	return _rk.can_place_at(tile_id, color)

## 某子所在串的**气数**，但把 `exclude` 这个点当作已被占掉（＝我们正打算落在那里）。
## 2026-10-18 正文迁至 rules_kernel.gd。
func _libs_of_group_excluding(stone_id: int, exclude: int) -> int:
	return _rk._libs_of_group_excluding(stone_id, exclude)

# ====== 棋谱记账（2026-10-02，棋谱阶段①）======
## 本节只做四件事，**全部薄封装**，棋理与格式一律在 `record.gd`：
##   `_record_begin()`   开一局时建谱头（谁/什么盘/贴目/生成器指纹）
##   `_record_move()`    记一手（**唯一写点**，在 `place_stone()` 与 `_apply_pass()` 里各调一次）
##   `_record_trim()`    悔棋同步截谱
##   `_record_finish()`  终局条目 + 落盘（**三处终局共用**，见该函数注释）
##
## ★★ **为什么不直接把 `GameRecord` 挂成 Autoload**（规划 §阶段① 已写）：
##   棋谱只在 `game.gd` 的记账点与将来的 `menu.gd` 棋谱库界面被显式调用，不需要跨场景常驻状态。

## ★ 写谱总闸（2026-10-22，为 `--liuh2h` 对打仪而加）：为真时 `_record_flush()` **一律不落盘**。
## 为什么需要它：`reset_game()` 里有 `_record_close_if_unfinished()` ⇒ 每开一局都会把上一局
##   标 `INTERRUPTED` 落盘。仪器连开 30 局就会往**用户的棋谱库**里灌 30 条半局废谱
##   （而仪器名不含 "test"，`is_automated_run()` 判不到 ⇒ 走的就是 `user://records`）。
## ★ 为什么闸装在 `_record_flush()` 而不是 `_record_move()`：flush 是落盘**唯一写点**（铁律 8），
##   闸在最下游 ⇒ `_record_finish()` / `_record_close_if_unfinished()` 两条路一起被挡住，
##   不会漏一条。组装照记（内存里），只是不写盘 —— 所以"重放写谱"阶段把它放开即可。
## ★ 默认 false：真实对局的写谱路径一字未变（这是纯抑制器，不是新语义）。
var _record_muted: bool = false

## ★ 谱头双方名的**覆盖口**（同上，为 `--liuh2h` 而加）：非空时 `_record_players()` 直接返回它。
## 为什么需要它：`_record_players()` 按 `game_mode` 给「玩家/AI」这类**角色名**，而 AI 对 AI
##   的谱要记「磐石/疾风/流水」—— 那是引擎名，不是角色名。★ 不给仪器另开一个"写谱头"的岔路
##   （那会变成 `players` 的第二写点）：覆盖口仍在 `_record_players()` 这**一个**真源里生效。
var _record_players_override: Dictionary = {}

## ★ 这一局属于哪一类（见 `GameRecord.KIND_*`）：真实对局恒为 `KIND_HUMAN`；
## 仪器批量自弈（`--liuh2h` 这一族）在开跑前把它置成 `KIND_MACHINE` 再复原。
## ★ 为什么由**写谱方**给而不是事后猜：猜就得按双方名去认引擎名，改名即静默失效（§113）。
var _record_kind: int = GameRecord.KIND_HUMAN

## 记录影响棋盘几何的全部参数（生成器指纹）。★ 少记一个就等于"改了那个参数旧谱照样能重放"，
##   而重放出来的盘是**另一张** —— 所以这里宁可多写。
##   ⚠ 新增任何影响几何的 `@export` 时**必须在这里加一行**，否则 `--grecotest` ⑥ 会红（它守着这条）。
func _record_generator_fp() -> String:
	# ★ 占位符与参数**逐个对齐**（改参数时数一遍 `%`）：数目不符时 GDScript 只在
	#   **运行到这一行**时报 `validated_evaluate`，而自检若不调它就是**零信号**。
	return "t%d|s%d|it%d|c%.4f|rt%d|rj%.1f|rw%.3f|pr%d|pm%d|kh%d|ch%d|ht%d|sr%d|hq%d|seed=%08x" % [
		GameConfig.board_type, GameConfig.board_size, iterations, clip_radius,
		random_target_tiles, random_tile_jitter, random_window_offset,
		1 if penrose_random_seed_rot else 0, 1 if penrose_random_seed_mirror else 0,
		_hat_kind_used, _cube_hex_r, _hat_target, _snow_r_actual, _hat_pool_size,
		_rand_seed,
	]

## 开一局 ⇒ 建一份新谱头。**每次 `reset_game()` 都调**（新局/重开都算新局）。
## ⚠ 必须在 `generate_board()` **之后**调：谱头要记 `_rand_seed` 与格数，随机档的种子在生成时才定。
func _record_begin() -> void:
	_record_gen_fp = _record_generator_fp()
	_record = GameRecord.new_record(
		game_mode, GameConfig.board_type, GameConfig.board_size,
		_rand_seed, komi, _record_gen_fp, _record_players(), _record_kind)

## 对局双方的名字。联机取 Steam 名（拿不到就退回"对手"）—— ★ 不写进谱**不影响重放**
##   （重放只靠盘型 + 种子 + 手数），但写上才有"这盘是谁下的"的可读性。
func _record_players() -> Dictionary:
	if not _record_players_override.is_empty():
		return _record_players_override.duplicate()
	match game_mode:
		VS_AI:
			return {"black": "玩家", "white": "AI"}
		ONLINE:
			return {"black": "房主" if GameConfig.is_host else "我", "white": "对手" if GameConfig.is_host else "房主"}
		_:
			return {"black": "黑方", "white": "白方"}

## 记一手。**唯一写点**（铁律 8「一处写、一处读」）。
## `tile` = -1 表示停一手。`ko` 传**本手落定之后**的 `ko_point`（不是 `_hist` 那份 `ko_before`）。
## ⚠ 调用方负责 `_quiet_place` 守卫（与 `_hist` 同一条判据、同一处if）——
##   探测性落子进谱 ⇒ 自检几百手会攒出一条谁也没下过的假谱，真复盘时局面与谱对不上。
func _record_move(tile: int, color: int, captures: int, ko: int) -> void:
	if _record.is_empty():
		_record_begin()
	GameRecord.append_move(_record, tile, color, captures, ko)

## 悔棋同步截谱：`_hist.pop_back()` 的棋谱对偶。调用点在 `_pop_history_entry()` 里。
## ★ 必须与退手**同一个原语**里做，否则两条链会错位（谱比盘面多手 ⇒ 复盘末手与实际终局不符）。
func _record_trim() -> void:
	if _record.is_empty():
		return
	GameRecord.trim_moves(_record, (_record["moves"] as Array).size() - 1)

## 终局条目 + 落盘。**三处终局共用这一个函数**（铁律 8）：
##   `_finish_game()`（面积终局）/ `_resign_game()`（玩家或 AI 认输）/ `_apply_pass()` 连停两次
##   （它转手调用 `_finish_game()`，不重复写）⇒ 实际上只有两个调用点。
## `reason` 用 `GameRecord` 的常量（SCORE / RESIGN），**不要传自由文本**：
##   复盘器与棋谱库界面要按它分类（"为什么结束"是玩法信息，不是显示信息）。
func _record_finish(reason: String, scores: Dictionary) -> void:
	if _record.is_empty():
		_record_begin()
	var tb: int = int(scores.get("total_black", 0))
	var tw: int = int(scores.get("total_white", 0))
	var winner: int = Stone.EMPTY
	if tb > tw:
		winner = Stone.BLACK
	elif tw > tb:
		winner = Stone.WHITE
	GameRecord.finish(_record, reason, winner, tb, tw)
	_record_flush()

## 落盘（唯一写点）。★ 中途中断（重开/退出）也落一份标了 `INTERRUPTED` 的谱——
##   否则玩家中途退出那一局就彻底丢了，而那往往正是他想复盘的那一局。
func _record_flush(interrupted: bool = false) -> String:
	# ★ 精简版（`GameConfig.lite`）**不落棋谱**：拦在写盘总闸，一处关掉
	#   「终局落盘 / 中断落盘 / 重开前落盘」全部出口（三处都走本函数）。
	#   ⚠️ 别改成"菜单侧不显示"了事：那样 `user://records/` 仍会悄悄长出一堆谱，
	#      而玩家在界面上找不到任何入口 —— 最坏的那种残留。
	if GameConfig.lite:
		return ""
	if _record.is_empty():
		return ""
	# ★ 写谱总闸（见 `_record_muted` 声明处）：仪器批量自弈时抑制落盘，默认 false ⇒ 真实对局无影响。
	if _record_muted:
		return ""
	if interrupted:
		GameRecord.mark_interrupted(_record)
	if _record.get("result") == null:
		# 没终局也没中断标记（例如被人直接调flush）⇒ 不落盘：库里不该有"不知道结局"的条目
		return ""
	return GameRecord.save(_record)

## ★★ 待下文的**中断标记**入口：重开一局时若有半局谱，先标中断落盘再开新局。
##放在 `_regen_on_restart()` 判定之后、有盘面的任何重开路径上都能用。
func _record_close_if_unfinished() -> void:
	if _record.is_empty() or _record.get("result") != null:
		return
	_record_flush(true)

func place_stone(tile_id: int, animate: bool = true) -> bool:
	if board[tile_id] != Stone.EMPTY:
		return false
	if tile_id == ko_point:
		if not _quiet_place:
			print("禁止打劫")
		return false

	var backup: Dictionary = board.duplicate()
	# ★ 悔棋存档的三个「被覆写状态」必须抓在**本手之前**（理由见 `_hist` 声明处）。
	#   落子会覆写 ko_point / _last_move、并在收尾把 passes 清零 ⇒ 事后无处可取。
	var ko_before := ko_point
	var last_move_before := _last_move
	var passes_before := passes
	# ★★ 落子方必须在**这里**抓：`current_player` 在函数收尾会被翻给 `opponent`，
	#   而 `opponent` 这个局部变量从一开始就是"对手"—— 拿它当落子方会把黑白记反。
	#   症状（2026-10-02 实测，`--undotest` ④ 逮到）：黑提白 1 子却记进 `white_prisoners`，
	#   回滚时又按错桶去减 ⇒ 提子数漂、且 `current_player` 被交到**对手**手里
	#   （"我撤了自己的棋，却轮不到我走"）。③ 之所以还是绿的：
	#   它比的是"两次同样错的结果"⇒ **两边一致 ≠ 对**。
	var mover_color: int = current_player
	board[tile_id] = current_player
	var opponent: int = Stone.WHITE if current_player == Stone.BLACK else Stone.BLACK

	var removed_ids: Array[int] = remove_dead_stones(opponent)

	var my_group: Array[int] = get_group(tile_id)
	if get_liberties(my_group) == 0:
		board = backup
		if not _quiet_place:
			print("自杀，落子无效")
		return false

	# ★★ superko：落子后局面与历史同形 ⇒ 判非法回滚（positional superko）。
	#   检查点选在这里是有意的：此刻盘面**已定稿**（含提子，所以 `_superko_hash()` 直接可用，
	#   不需要 `can_place_at()` 那套预测），而提子记账 / `ko_point` / `_hist` / 棋谱**都还没动**
	#   ⇒ 回滚只需还原 `board`（比上面自杀分支还干净，连 ko_point 都不用恢复）。
	#   ⚠️ 别把它挪到 `ko_point` 赋值之后 —— 那样回滚就得额外还原 ko_point，多一处易漏。
	if (not _quiet_place or _superko_enforce) and _superko_hist.has(_superko_hash()):
		board = backup
		if not _quiet_place:
			print("超级劫：全盘同形再现，落子无效")
		return false
	_superko_commit()

	# 落子成立：记录本手提子（黑提白记 black_prisoners，白提黑记 white_prisoners）
	if removed_ids.size() > 0:
		if current_player == Stone.BLACK:
			black_prisoners += removed_ids.size()
		else:
			white_prisoners += removed_ids.size()

	# 提子动画：被提的棋子向上平移淡出。★ 起手**延迟** = 落子动画时长 + 本颗所在的**波前层**
	# 的起手偏移（两段串行 + 一层层往外提）—— 见 `_capture_delay()` / `_capture_wave_start()`。
	# ★★ 分层用 `_capture_depths(tile_id, removed_ids)`：第 0 层就是贴着刚落那手的子。
	#    `removed_ids` 是**本地变量**（`remove_dead_stones` 的返回值），此处棋盘上这些子已被清掉，
	#    所以分层只能靠它 + `adjacency`，**不能**去 board 里找连通块（见 `_capture_depths()` 注释）。
	if animate:
		var depths: Dictionary = _capture_depths(tile_id, removed_ids)
		var wave_max: int = _capture_wave_max(depths)
		for vid in removed_ids:
			if _place_anims.has(vid):   # 清掉可能残留的落子动画，避免叠加
				_place_anims.erase(vid)
			var wave: int = int(depths.get(vid, 0))
			_capture_anims[vid] = {
				"time_left": STONE_ANIM_TIME,
				"delay": _capture_delay() + _capture_wave_start(wave, wave_max),
				"color": opponent,
				"wave": wave,               # 层号留档：自检断言"顺序真的按层来"，不靠反推 delay
				"wave_max": wave_max,
			}

	# 落子动画：新子从 0 长到满（ease-out）
	if animate:
		if _capture_anims.has(tile_id):
			_capture_anims.erase(tile_id)
		_place_anims[tile_id] = STONE_ANIM_TIME
		_last_move = tile_id   # 记录上一步落子，供提示标记使用（探测性落子 animate=false 不记）

	if removed_ids.size() == 1:
		var diff_pos: int = removed_ids[0]
		ko_point = diff_pos if diff_pos in get_neighbors(tile_id) else -1
	else:
		ko_point = -1

	if not _quiet_place:
		print("落子瓷砖 %d 成功，提掉 %d 子" % [tile_id, removed_ids.size()])
	current_player = opponent
	passes = 0  # 落了子 → 连续停手计数清零
	# ★ 悔棋入栈放在**这里**（而不是紧跟落子）：此刻 `removed_ids` / `ko_point` / `current_player`
	#   才全部定稿，可以存一份自洽的快照。
	#   `_quiet_place` 是探测性落子的开关 ⇒ 不入栈（理由见 `_hist` 声明处）。
	# `pass_move`: false。
	#   ★ 棋谱记账与它**同一个守卫、紧挨着**写（见 `_record_move` 的注释）：
	#     守卫写成两处（"两处都记得"不是不变量，本工程的老坑）⇒ 负控刀R5 盯的就是这条。
	if not _quiet_place:
		_hist.append({
			"tile": tile_id,
			"color": mover_color,   # ★ 落子方（函数入口的 current_player），不是 `opponent`
			"captured": removed_ids.duplicate(),
			"ko_before": ko_before,
			"passes_before": passes_before,
			"last_move_before": last_move_before,
			"pass_move": false,
		})
		# ★★ 棋谱也记一手（阶段①）。`ko` 传**本手之后**的 ko_point（与 `_hist` 的 `ko_before`
		#   口径相反，两条链故意不同 —— `--grecotest` ③ 拿它们逐字段对拍）。
		#   ⚠ `mover_color` 不是 `opponent`（同 `_hist` 那条坑）；负控刀 R4 把这里换成
		#     `opponent` ⇒ 谱里黑白颠倒，而复盘时按谱重放会在第 3 手就撞"已有子"而失败。
		_record_move(tile_id, mover_color, removed_ids.size(), ko_point)
		# ★ 棋钟：这一手落定（手频统计 + 加秒 + 读秒重置）。
		#   ⚠️ 守卫与棋谱/悔棋栈**同一口径**（`_quiet_place`）：探测性落子（`_random_legal_move`、
		#   各种自检夹具）**不许计入手频** —— 否则 AI 每探一次合法点就把自己的手速刷一遍，
		#   音乐跟着飙到最快档，而这条路**不报任何错**。
		if _clk != null:
			_clk.on_move(mover_color)
	# 玩家无视「是否数子」提示直接落子 = 用行动选了「继续下棋」，顺手把提示收掉
	# （提示层不拦截棋盘点击，不主动关闭会留下一个僵尸面板）
	_clear_count_prompt()
	queue_redraw()
	# 落子音效（Music 全局单例；未注册时安全跳过）
	var _m := get_node_or_null("/root/Music")
	if _m != null and _m.has_method("play_sfx_place"):
		_m.play_sfx_place()

	# ★ 局势刷新：胜负已定、turn 已换 ⇒ 这时算出来的领先/危急才是新局面的。
	#   只读（`analyze_board` 不改棋盘），且它自带 `_sc_id` 缓存。
	_refresh_analyze()
	return true


## 引擎给出着法后的统一收尾：停一手 / 非法兜底 / 真正落子
func _apply_ai_move(move_id: int) -> void:
	if game_over or current_player != AI_COLOR:
		return
	if move_id == -1:
		# AI 主动停一手（候选着法全被过滤：无利可图 / 只剩自填己方眼位）
		# ★★★ 必须走 `_apply_pass()` 同一条入账路径（`_hist` + 棋谱都记，tile=-1）——
		#   2026-10-13 实测（两局真实对局 p94/p86 都是这么死的）：这里原来只
		#   `passes += 1` + 换手，三处静默丢账：
		#   ① 棋谱缺这一手 ⇒ 记录里出现连续两手同色，按谱复盘重放到此必错；
		#   ③ 悔棋栈缺这一手 ⇒ 回滚出的 `passes` 与盘面对不上（`_apply_pass` 同款症状）。
		print("AI 停一手（候选被过滤 / 无利可图）")
		_apply_pass(AI_COLOR)
		return
	if move_id < 0 or move_id >= tiles.size() or board[move_id] != Stone.EMPTY:
		# 防御：引擎出现意外时退回随机合法着法
		push_warning("AI 引擎返回非法着法 %d，退回随机" % move_id)
		move_id = _random_legal_move()
		if move_id == -1:
			# 全场无合法着法 ⇒ 只能停一手；同样入账（理由同上）
			print("AI 无合法着法，停一手")
			_apply_pass(AI_COLOR)
			return

	if place_stone(move_id):
		print("AI 落子在瓷砖 %d" % move_id)
		if _empty_tiles() == 0:
			_finish_game()
	else:
		# 落子被规则拒绝（劫/边缘竞态）：视作停一手；同样入账（理由同上）
		print("AI 落子被拒，停一手")
		_apply_pass(AI_COLOR)

func _random_legal_move() -> int:
	# ★★ 探测期必须**静音**（`_quiet_place`）：本函数是"探明哪一格合法"，做法是真调
	#   `place_stone()` 再手工还原下面那 6 个存档 —— 而 `place_stone()` 在非静音语境
	#   还会**入 `_hist` 栈**（悔棋存档）并（2026-10-14 起）**记 `_superko_hist`**。
	#   这两样都**不在**那 6 个存档里 ⇒ 漏还原就是"探测留脏"：
	#     ① `_hist` 多一条**从没下过**的手 ⇒ 悔棋会退到不存在的局面；
	#     ② `_superko_hist` 多一个**从没下过**的局面指纹 ⇒ 以后真下到那个局面会被
	#        误判「同形再现」而拒绝落子（玩家看到"这点明明能下，点了没反应"）。
	#   ★ 实测逮到（2026-10-14，`--counttest` ⑥ 红了）：探测落 t20 → 立即回滚盘面 →
	#     紧接着真落 t20 ⇒ 打印「超级劫：全盘同形再现，落子无效」、`place_stone` 返回 false。
	#   ★ 静音开关与 `_hist`/`_superko_hist` 的守卫**同一口径**（都在 `place_stone()` 内），
	#     故一处覆盖两处、结构上不可能只同步一半。调用方拿返回值去真落子时仍在**非静音**
	#     语境 ⇒ superko 照旧生效，本函数只关掉"探测这一下"的记账。
	var quiet_before: bool = _quiet_place
	_quiet_place = true
	var candidates: Array[int] = []
	for vid in board.keys():
		if board[vid] == Stone.EMPTY and vid != ko_point:
			candidates.append(vid)
	candidates.shuffle()
	for vid in candidates:
		# ★ 六个存档的类型与它们各自的真源一致（`board: Dictionary` / 其余全 `: int`）——
		#   回滚时**逐个赋回**，注释掉/漏掉一个都不会报错，只会让状态漂（铁律：被覆写状态全还原）。
		var b_backup: Dictionary = board.duplicate()
		var k_backup: int = ko_point
		var p_backup: int = current_player
		var ps_backup: int = passes
		var bp_backup: int = black_prisoners
		var wp_backup: int = white_prisoners
		if place_stone(vid, false):
			# 只是探明合法性，真正落子交给 ai_move 完成，故全部还原
			board = b_backup
			ko_point = k_backup
			current_player = p_backup
			passes = ps_backup
			black_prisoners = bp_backup
			white_prisoners = wp_backup
			_quiet_place = quiet_before
			return vid
	_quiet_place = quiet_before
	return -1

# ====== AI 主动认输 ======
## 形势判定（AI 视角）。返回 {should_resign, deficit, empties, margin, played, min_played, enough, hopeless}
##
## 判据是「满打满算也追不回来」，而不是「现在落后」：
## 计分口径直接复用终局的 `_compute_scores()`，所以「AI 觉得该不该认」和
## 「终局实际会怎么判」用的是同一把尺子，不会出现「认输了却发现其实领先」的荒唐结果。
##
## 追分上限取剩余空点数 empties：本作总分 = 盘面子 + 领地 + 提子，每一格最终非「子」即「领地」、
## 只计一次，所以剩余空点**全部**归 AI 也只能补上 empties 点。连这个乐观上限都补不平，
## 才是真的没救。再减去一个安全余量，抵消提子 / 劫争带来的额外摆动。
func _ai_resign_eval() -> Dictionary:
	var n: int = tiles.size()
	if n == 0:
		return {"should_resign": false, "deficit": 0, "empties": 0, "margin": 0,
			"played": 0, "min_played": 0, "enough": false, "hopeless": false}
	var sc: Dictionary = _compute_scores()
	var my_total: int = int(sc["total_white"]) if AI_COLOR == Stone.WHITE else int(sc["total_black"])
	var op_total: int = int(sc["total_black"]) if AI_COLOR == Stone.WHITE else int(sc["total_white"])
	var deficit: int = op_total - my_total
	var empties: int = _empty_tiles()
	var margin: int = int(round(float(n) * ai_resign_margin_ratio))
	var played: int = (int(sc["stones_black"]) + int(sc["stones_white"])
			+ black_prisoners + white_prisoners)
	var min_played: int = int(float(n) * ai_resign_min_stones_ratio)
	var enough: bool = played >= min_played
	var hopeless: bool = deficit > empties + margin
	return {
		"should_resign": ai_resign_enabled and enough and hopeless and not game_over,
		"deficit": deficit, "empties": empties, "margin": margin,
		"played": played, "min_played": min_played,
		"enough": enough, "hopeless": hopeless,
	}

## AI 认输检查：成立则直接终局并返回 true。
## 必须放在**搜索之前**调用 —— 既省掉一次注定无用的搜索，也让「认输」表现得像个决断
## （而不是先装模作样想半天再认）。
func _ai_try_resign() -> bool:
	if game_mode != VS_AI or game_over or current_player != AI_COLOR:
		return false
	var ev: Dictionary = _ai_resign_eval()
	if not bool(ev["should_resign"]):
		return false
	print("[AI 认输] 落后 %d 点 | 剩余空点 %d | 安全余量 %d | 已落 %d 手（门槛 %d）" % [
		ev["deficit"], ev["empties"], ev["margin"], ev["played"], ev["min_played"]])
	_resign_game(AI_COLOR, "AI 判断大势已去：落后 %d 点，剩余空点全拿也只到 %d 点" % [
		ev["deficit"], ev["empties"]])
	return true

## 自检（--liushuitest，2026-10-22）：流水（渗流引擎）在**真实盘**上接得上、走得出合法手。
##
## ★ 为什么必须单列一条、不能只信引擎自带的 31 项：那些跑在 9×9 方格与 150 点环面上，
##   而真实 Penrose 盘的**环长分布**与**边界度分布**都不同 —— `local_radius=6` 的邻域
##   在真实盘上可能大一圈，单步耗时会变。本条量的正是"换了盘以后还成不成立"
##   （铁律 §96：`exit=0 ≠ 跑到了`，所以每条都打印实际数字）。
##
## 四条判据（各自"红了做什么"）：
##   ① `ai_liushui` 非空 + `liushui_play_mode` 为真 + n 等于邻接表长度
##      —— 红了 = 接入没接上 / 菜单标记没下发 / 盘规格变了
##   ② 空盘起手返回合法空点 —— 红了 = 引擎在**边界盘**上选点越界（合成分支覆盖不到）
##   ③ 中盘（60 手）返回合法空点 —— 红了 = 势场 / 候选筛选在密集盘面上失效
##   ④ 单步耗时 ≤ 预算 × 4 —— 红了 = 真实盘邻域太大，要调 `local_radius` 或尺度档
func _liushui_smoke_test() -> void:
	var bad: Array[String] = []
	if ai_liushui == null:
		print("[liushuitest] ✗ ai_liushui 为 null —— `liushui_play_mode` 没生效（接入断了）")
		print("[liushuitest] 结论：失败 ✗")
		get_tree().quit()
		return
	if not liushui_play_mode:
		bad.append("liushui_play_mode=false 但 ai_liushui 非空（状态不一致）")
	if ai_liushui.n != adjacency.size():
		bad.append("n=%d ≠ 邻接表 %d" % [ai_liushui.n, adjacency.size()])
	var deg_hist := {}
	for i in ai_liushui.n:
		var d: int = ai_liushui._deg[i]
		deg_hist[d] = int(deg_hist.get(d, 0)) + 1
	print("[liushuitest] 盘：n=%d 度数分布=%s 预算=%dms" % [
		ai_liushui.n, str(deg_hist), int(ai_liushui.time_budget_ms)])

	# ② 空盘起手
	var t0 := Time.get_ticks_msec()
	var mv: int = ai_liushui.choose_move({}, -1, AI_COLOR)
	var dt := Time.get_ticks_msec() - t0
	if mv < 0 or mv >= ai_liushui.n:
		bad.append("空盘起手返回 %d" % mv)
	print("[liushuitest] 空盘：mv=%d %dms（精算 %d 次）" % [mv, dt, ai_liushui.last_evals])
	if dt > int(ai_liushui.time_budget_ms) * 4:
		bad.append("空盘 %dms > 预算×4" % dt)

	# ③ 中盘起手（60 手真实局面，用引擎自己的规则铺）
	# ★★ 2026-10-22 修（本轮踩到）：`scramble()` 用的是 `setup()` 播的 rng，而接入路径
	#   `setup(adjacency, AI_COLOR)` **没传 seed** ⇒ 落成 `ticks_usec` ⇒ **每次跑的局面都不一样**。
	#   实测后果：同一条判据连跑，`mv` 在 71/77/99/115 之间跳，其中 mv=99 那次 ⑤ 报
	#   「游戏侧 can_place_at 判非法」，下一轮又全绿 —— **判据自己不可复现**，
	#   于是"红"不能当结论读（§125 同族：不可复现的环境不许按单次运行下判断）。
	#   ⇒ 钉死种子：局面固定下来，红了能查、绿了算数。
	ai_liushui.rng.seed = 20261022
	ai_liushui.scramble(60)
	var mid: Dictionary = ai_liushui.export_board()
	var t1 := Time.get_ticks_msec()
	var mv2: int = ai_liushui.choose_move(mid, -1, int(ai_liushui._turn))
	var dt2 := Time.get_ticks_msec() - t1
	if mv2 < 0 or mv2 >= ai_liushui.n:
		bad.append("中盘起手返回 %d" % mv2)
	elif int(mid.get(mv2, 0)) != 0:
		bad.append("中盘起手落在已占点 %d" % mv2)
	print("[liushuitest] 中盘（%d 子）：mv=%d %dms（精算 %d 次）" % [
		mid.size(), mv2, dt2, ai_liushui.last_evals])
	if dt2 > int(ai_liushui.time_budget_ms) * 4:
		bad.append("中盘 %dms > 预算×4" % dt2)
	# ④ 盘上还有空点时不许停一手（停一手 = 玩家看到"AI 弃权"）
	if mv2 == -1 and mid.size() < ai_liushui.n:
		bad.append("中盘返回停一手，但盘上还有 %d 个空点" % (ai_liushui.n - mid.size()))

	# ⑤ **跨引擎合法性**：流水（第四套规则实现）选出的手，游戏侧必须也判能落。
	#   ★★ 这条是整段里唯一能逮住"两份规则分叉"的判据 —— 而分叉的症状是**静默**的：
	#     `_apply_ai_move()` 拿到非法点只会什么都不做，玩家看到的是"AI 卡住不动"，
	#     引擎侧自己的自测（31 项）**全绿**，因为分叉根本不在它视野里
	#     （`ai.md` 记着同一类事故：引擎设劫条件过严 ⇒ 引擎放行、玩家看不到那一手）。
	#   做法：把流水的局面灌进游戏侧 `board` + 同步劫点，然后用**游戏侧真源**
	#   `can_place_at()`（= `RulesKernel`）问一次；问完立刻还原，不留状态。
	if mv2 >= 0:
		# ⚠️ 必须**逐点整盘覆盖**，不能 `board.clear()` 后只灌非空点：
		#   游戏侧 `board` 是**全点预填**的（`reset_game()` 里 `for vid in board.keys(): board[vid]=EMPTY`），
		#   而 `RulesKernel` 内部直接 `board[x]` 索引 —— 灌成稀疏表会刷
		#   `Invalid access to property or key` 的 SCRIPT ERROR（实测），判据还照样绿。
		var n_all: int = adjacency.size()
		var board_bak: Dictionary = board.duplicate()
		var ko_bak: int = ko_point
		for i in n_all:
			board[i] = int(mid.get(i, 0))
		ko_point = int(ai_liushui._ko)
		var ok_cross: bool = can_place_at(mv2, AI_COLOR)
		for i in n_all:
			board[i] = int(board_bak.get(i, 0))
		ko_point = ko_bak
		if not ok_cross:
			bad.append("流水选点 %d 游戏侧 can_place_at 判非法（两份规则已分叉）" % mv2)
		print("[liushuitest] 跨引擎合法性：mv=%d 游戏侧=%s" % [mv2, "✓可落" if ok_cross else "✗判非法"])

	# ---- ⑤b 多种子扫（2026-10-22 新增，把"偶发"变成"必现或不存在"）----
	# ★★ 为什么加：⑤ 第一版只有一个局面，而那个局面**每次不一样**（见 ③ 的注释）。
	#   实测抓到过一次 mv=99 判非法，钉死种子后那个局面消失了 ⇒ "红过一次但复现不了"。
	#   这类账只有两种去处：要么扫够多个**固定**局面把它逼出来，要么永远说不清。
	#   ⇒ 4 个固定种子各铺 60 手，每条都过同样四面（在界内 / 不落已占点 / 空盘时不许停手 /
	#     游戏侧 `can_place_at` 放行）。红了直接点名种子号 ⇒ **可复现**。
	# ★ 口径与 ⑤ 完全一致（同一套 `can_place_at` 真源、同样整盘覆盖后还原），不另立第二套判据。
	var sweep_seeds: Array[int] = [20261023, 20261024, 20261025]
	var sweep_bad: Array[String] = []
	var sweep_ms: Array[int] = []
	for sd in sweep_seeds:
		ai_liushui.rng.seed = sd
		ai_liushui.scramble(60)
		var mb: Dictionary = ai_liushui.export_board()
		var t3 := Time.get_ticks_msec()
		var mvb: int = ai_liushui.choose_move(mb, -1, int(ai_liushui._turn))
		sweep_ms.append(Time.get_ticks_msec() - t3)
		if mvb < 0 or mvb >= ai_liushui.n:
			sweep_bad.append("seed%d 返回 %d" % [sd, mvb])
			continue
		if int(mb.get(mvb, 0)) != 0:
			sweep_bad.append("seed%d 落在已占点 %d" % [sd, mvb])
		if mvb == -1 and mb.size() < ai_liushui.n:
			sweep_bad.append("seed%d 空盘面停手" % sd)
		var nb_all: int = adjacency.size()
		var bbak: Dictionary = board.duplicate()
		var kbak: int = ko_point
		for i in nb_all:
			board[i] = int(mb.get(i, 0))
		ko_point = int(ai_liushui._ko)
		var ok_b: bool = can_place_at(mvb, AI_COLOR)
		for i in nb_all:
			board[i] = int(bbak.get(i, 0))
		ko_point = kbak
		if not ok_b:
			sweep_bad.append("seed%d 选点 %d 游戏侧判非法" % [sd, mvb])
	if not sweep_bad.is_empty():
		for s in sweep_bad:
			bad.append("⑤b 多种子扫：" + s)
	print("[liushuitest] ⑤b 多种子扫（%d 个固定局面）：异常 %d 处%s｜耗时 %s ms" % [
		sweep_seeds.size(), sweep_bad.size(),
		"" if sweep_bad.is_empty() else " " + str(sweep_bad), str(sweep_ms)])

	# ⑥ **后台线程路径**：对局真实走的是 `choose_move_async()`，它在 Thread 里跑
	#   `_search_entry → choose_move`。这里直接调 `_search_entry` 起线程等它跑完 ——
	#   验的是"线程侧不崩、返回值合法"。
	#   ★ 为什么不整条 `await choose_move_async()`：那要把 `_ready` 变成协程，
	#     而本工程的 `_ready` 有"提前 return 会让启动横幅与全部分派变死代码"的前科
	#     （S103 就是为它立的）。协程尾部那段 `await process_frame` 是照抄 `AIEngine`
	#     的样板，真正的风险在"线程里跑引擎"这一半 ⇒ 只测这一半。
	#   ★ 也不重实现线程逻辑：直接调引擎自己的 `_search_entry`（铁律 §70）。
	var th := Thread.new()
	var terr: int = th.start(ai_liushui._search_entry.bind({}, -1, AI_COLOR), Thread.PRIORITY_NORMAL)
	if terr != OK:
		bad.append("线程启动失败 err=%d" % terr)
	else:
		var t2 := Time.get_ticks_msec()
		while th.is_alive():
			OS.delay_msec(2)
		var mv_th: int = int(th.wait_to_finish())
		var dt_th := Time.get_ticks_msec() - t2
		if mv_th < 0 or mv_th >= ai_liushui.n:
			bad.append("线程侧返回 %d（非法）" % mv_th)
		print("[liushuitest] 后台线程：mv=%d %dms（对局走的就是这条）" % [mv_th, dt_th])

	print("[liushuitest] 结论：%s %s" % ["通过 ✓" if bad.is_empty() else "失败 ✗", str(bad)])
	get_tree().quit()


# ============================================================================
# 自检（--yematest，2026-10-23）：野马档 = **神经网络先验 + 磐石搜索**。
#
# ★ 为什么必须单列一条：`nn_score.gd` 接入前是旁挂的 —— `--liushuitest` / `--xgtest`
#   一个字都不碰它。而接入坏掉的方式**全都是静默的**，正好三处：
#     ① 权重没进导出包 / 路径写错 ⇒ `nn_ready=false`。若有人顺手把
#        `allow_fallback_to_panshi` 打开，就变成"以为在下野马、其实在下磐石"；
#     ② 钩子位置错（例如放到 Top-K 剪枝**之后**）⇒ 网络对"哪些候选能进搜索"毫无影响，
#        而日志、耗时、返回的手**全都正常**；
#     ③ 网络分数退化成常数（权重全零 / 加载到别的 arch）⇒ 混合后顺序逐位不变，
#        `ext_prior_last_mix` 照样 > 0 ⇒ 读数看起来"接上了"。
#   下面七条判据分别对着这三处（③ 用 ⑥c 的**非哨兵极差** + ⑤a 的**排序变动点数**抓 ③ 那一类；
#   ⚠️ 2026-10-24 更正：**不要**再用 `ext_prior_last_top1_moved` 抓 ③ —— 训练标签就是教师
#   自己的选点（网络是磐石的学生），"首选没换人"在正品上也会发生，见 `ai_engine.gd` 字段处 ★★）。
#
# ★ 口径纪律：
#   · 所有"同一局面"比对都钉死 **单线程 + 定 pw + 定 seed**（不钉则停止条件是墙钟，
#     同一局面的两次运行不是同一局 —— §125 / `--jevdump` 的口径）。
#   · 每个探针量都先问"它红了我要做什么"，答不出来的不放进来。
# ============================================================================

## 关态等价用的模拟次数上限。**必须钉死**（见上面口径纪律）。
const YEMA_TEST_PW: int = 90
## 时间预算设成兜底值（永远到不了）⇒ 让 `max_playouts` 成为**唯一**停止条件。
const YEMA_TEST_MS: int = 60000

## 判据收集器：同步段 ①~⑥ 往里 append，异步段 ⑦ 收尾时统一打印结论。
var _yema_bad: Array[String] = []
## 固定局面（`_yema_lay_board()` 摆出来的副本；见该函数注释）。
var _yema_boards: Array[Dictionary] = []
## 开态实例（异步段 ⑦ 还要用它 ⇒ 提升成成员）。
var _yema_nn: YemaAI = null


## 摆一个固定局面并按整盘副本返回。
##
## 为什么不用现成的 `_lay_ratio_board()`：它是"前 n 格黑、接着白"的**聚块**摆法，
## 在彭罗斯盘的顶点编号顺序下会造出大片同色团（乃至 0 气死团）。引擎拿到那种局面
## 会先提子，于是"同一局面"在两条路径上就不再是同一个起点了。
## 这里按 `(i*7+off)%5` 交错分配（黑/白/空），同色点几乎不相邻。
func _yema_lay_board(off: int) -> Dictionary:
	for vid in board.keys():
		board[vid] = Stone.EMPTY
	black_prisoners = 0
	white_prisoners = 0
	ko_point = -1
	_last_move = -1
	passes = 0
	game_over = false
	for i in tiles.size():
		var m: int = (i * 7 + off) % 5
		if m == 0:
			board[i] = Stone.BLACK
		elif m == 1:
			board[i] = Stone.WHITE
	return board.duplicate()


## 给一个引擎实例钉死"可复现三件套"（单线程 / 定 pw / 定 seed 已在 setup 里）。
func _yema_pin(eng: AIEngine) -> void:
	eng.threads = 1
	eng.max_playouts = YEMA_TEST_PW
	eng.time_budget_ms = YEMA_TEST_MS
	eng.root_width = 12


## 仪器：`--nnprobe=权重.json,golden.json`（2026-10-26）。
##
## 验三件事，缺一不可：
##   ① `load_weights()` 收下这份权重（结构/维度/exportable 三道闸门都过）；
##   ② **特征**对拍：引擎复算的特征 == 训练侧导出的 `X`；
##   ③ **前向**对拍：引擎算出的分数 == 训练侧写进 golden 的 `scores`。
##
## ★ ③ 是换结构之后唯一有牙齿的判据。图网络的邻接聚合写错时，①②都可能通过
##   （特征一样、权重形状也对），只有分数不同 —— 而分数不同不报错，
##   在实战里只会表现成"引擎好像没变强"，那种错追不出来。
## ★ 退出码：0 全绿 / 1 对拍不一致 / 2 权重加载失败。脚本里能直接判。
func _nn_probe(arg: String) -> void:
	var parts := arg.split(",")
	if parts.size() < 2:
		print("[nnprobe] ✗ 用法：--nnprobe=权重.json,golden.json")
		get_tree().quit(2)
		return
	var wpath := parts[0].strip_edges()
	var gpath := parts[1].strip_edges()
	var nn := NNScore.new()
	nn.setup(adjacency)
	if not nn.load_weights(wpath):
		print("[nnprobe] ✗ 权重加载失败：%s" % wpath)
		print("[nnprobe] 结论：失败 ✗")
		get_tree().quit(2)
		return
	# 参数个数（只打印，不同结构不可比 —— 用来确认"加载的确实是那份权重"）
	var nparam := 0
	if nn.arch == "mlp":
		for L in nn.layers:
			var W: Array = (L as Dictionary)["W"]
			if W.size() > 0:
				nparam += W.size() * ((W[0] as Array).size() + 1)
	else:
		for L2 in ([nn.g_enc] + nn.g_msg + nn.g_upd + [nn.g_out]):
			var W2: Array = (L2 as Dictionary)["W"]
			for row in W2:
				nparam += (row as PackedFloat32Array).size() + 1
	print("[nnprobe] ① 加载 ✓：arch=%s feat_dim=%d%s 参数≈%d" % [
		nn.arch, nn.feat_dim,
		" h=%d 层=%d" % [nn.g_h, nn.g_msg.size()] if nn.arch == "gnn" else "",
		nparam])
	# ②③ 对拍
	var bad := nn.check_golden(gpath)
	# 计时：空盘是候选最多的情形（120 个空点）⇒ 这是每手耗时的**上界**
	var bd := {}
	for v in nn.n:
		bd[v] = 0
	var t0 := Time.get_ticks_usec()
	var reps := 10
	for _i in reps:
		nn.score_points(bd, 1, 0, -1)
	var ms := (Time.get_ticks_usec() - t0) / 1000 / reps
	print("[nnprobe] ④ 空盘计时 %d ms/手（%d 次平均，候选 %d 个；预算 200ms）"
		% [ms, reps, nn.n])
	print("[nnprobe] 结论：%s" % ("通过 ✓" if bad == 0 else "失败 ✗"))
	get_tree().quit(0 if bad == 0 else 1)


func _yema_smoke_test() -> void:
	var bad := _yema_bad
	# ---- ① 接入面 ----
	if ai_yema == null:
		print("[yematest] ✗ ai_yema 为 null —— `yema_play_mode` 没生效（接入断了）")
		print("[yematest] 结论：失败 ✗")
		get_tree().quit()
		return
	if not yema_play_mode:
		bad.append("yema_play_mode=false 但 ai_yema 非空（状态不一致）")
	if ai_yema.n != adjacency.size():
		bad.append("n=%d ≠ 邻接表 %d" % [ai_yema.n, adjacency.size()])
	# ★ 权重真的加载了才算"野马"。`allow_fallback_to_panshi` 默认 false ⇒ 加载失败时
	#   `choose_move` 会返回 -1，但**自检要比那更早报**：否则读日志的人只看到"引擎返回 -1"，
	#   要追三层才知道是权重没进包。
	if not ai_yema.nn_ready:
		bad.append("nn_ready=false（%s）" % ai_yema.weights_path)
	print("[yematest] ① 盘：n=%d 权重=%s 参数=%s" % [
		ai_yema.n, "✓已加载" if ai_yema.nn_ready else "✗未加载（" + ai_yema.nn_error + "）",
		"pw=%d/ms=%d" % [YEMA_TEST_PW, YEMA_TEST_MS]])

	# ---- 固定局面 ----
	_yema_boards.clear()
	for off in [0, 1, 2]:
		_yema_boards.append(_yema_lay_board(off))
	var stones0 := 0
	for v in _yema_boards[0].keys():
		if int(_yema_boards[0][v]) != 0:
			stones0 += 1
	print("[yematest] ② 固定局面 %d 个（局面0 有 %d 子 / 共 %d 点）" % [
		_yema_boards.size(), stones0, adjacency.size()])

	# ---- ③ 关态逐位等价磐石（A/B 的基线；破了则所有对比结论作废）----
	# ★ 参照物必须是**另一个独立实例**（`AIEngine`），不能是 `ai_yema.inner` 自己
	#   （§110：参照物与被测物不许退化成同一对象 ⇒ 会恒绿）。
	var e_ref := AIEngine.new()
	e_ref.setup(adjacency, AI_COLOR, 20261023)
	_yema_pin(e_ref)
	var e_off := YemaAI.new()
	e_off.setup(adjacency, AI_COLOR, 20261023)
	e_off.nn_enabled = false
	e_off.threads = 1
	e_off.time_budget_ms = YEMA_TEST_MS
	e_off.root_width = 12
	e_off._apply_search_params()          # 上面两个赋值在 setup() 之后 ⇒ 重放一次
	e_off.inner.max_playouts = YEMA_TEST_PW
	var eq_bad: Array[String] = []
	var steps_done := 0
	for bi in _yema_boards.size():
		var b_a: Dictionary = _yema_boards[bi].duplicate()
		var b_b: Dictionary = _yema_boards[bi].duplicate()
		var mover: int = AI_COLOR
		for step in 3:
			var m_a: int = e_ref.choose_move(b_a, -1, mover)
			var m_b: int = e_off.choose_move(b_b, -1, mover)
			steps_done += 1
			if m_a != m_b:
				eq_bad.append("局面%d 第%d手 磐石=%d 关态=%d" % [bi, step + 1, m_a, m_b])
				break
			if m_a >= 0 and m_a < e_ref.n:
				b_a[m_a] = mover
				b_b[m_b] = mover
			mover = 3 - mover
	# ★ 存在性判据（§96）：关态分支**真的跑到了**。`fallback_calls == 0` ⇒ 探针没被触发，
	#   "逐手一致"就只是"两个磐石都一样"这种废话 ⇒ 必须报红，不许当通过。
	if e_off.fallback_calls == 0:
		eq_bad.append("fallback_calls=0 ⇒ 关态分支没跑到（本条判据无效）")
	if e_off.prior_calls != 0:
		eq_bad.append("关态 prior_calls=%d（应为 0：关态不许算网络）" % e_off.prior_calls)
	for s in eq_bad:
		bad.append("③ " + s)
	print("[yematest] ③ 关态逐手等价磐石：比对 %d 手 · 关态分支命中 %d 次 · 异常 %d 处%s" % [
		steps_done, e_off.fallback_calls, eq_bad.size(),
		"" if eq_bad.is_empty() else " " + str(eq_bad)])

	# ---- ④⑤ 开态：先验进根层了吗 / 真的推翻了磐石排序吗 ----
	_yema_nn = YemaAI.new()
	_yema_nn.setup(adjacency, AI_COLOR, 20261023)
	_yema_nn.threads = 1
	_yema_nn.time_budget_ms = YEMA_TEST_MS
	_yema_nn.root_width = 12
	_yema_nn._apply_search_params()
	_yema_nn.inner.max_playouts = YEMA_TEST_PW
	var mix_max := 0
	var moved_cnt := 0
	var is_net_cnt := 0
	var agree_cnt := 0
	var odiff_min := 1 << 30
	var odiff_txt: Array[String] = []
	var mix_w := -1.0
	var rank_txt: Array[String] = []
	var priors_ms: Array[int] = []
	var nn_bad: Array[String] = []
	var cross_bad: Array[String] = []
	for bi in _yema_boards.size():
		var b_n: Dictionary = _yema_boards[bi].duplicate()
		var mv_n: int = _yema_nn.choose_move(b_n, -1, AI_COLOR)
		mix_max = maxi(mix_max, _yema_nn.inner.ext_prior_last_mix)
		if _yema_nn.inner.ext_prior_last_top1_moved == 1:
			moved_cnt += 1
			rank_txt.append("局面%d→磐石原第%d" % [bi, _yema_nn.inner.ext_prior_last_top1_rank + 1])
		if _yema_nn.inner.ext_prior_last_top1_is_net == 1:
			is_net_cnt += 1
		if _yema_nn.inner.ext_prior_last_top1_agree == 1:
			agree_cnt += 1
		var od: int = _yema_nn.inner.ext_prior_last_order_diff
		odiff_min = mini(odiff_min, od)
		odiff_txt.append(str(od))
		mix_w = maxf(mix_w, _yema_nn.inner.ext_prior_last_w)
		priors_ms.append(_yema_nn.last_priors_ms)
		# ⑥ 跨引擎合法性：野马选的点，游戏侧真源必须也判能落
		#   （两份规则分叉的症状同样是静默的：`_apply_ai_move()` 拿到非法点什么都不做，
		#     玩家看到的是"AI 卡住不动"，而引擎自己的自测全绿。）
		if mv_n >= 0:
			var n_all: int = adjacency.size()
			var board_bak: Dictionary = board.duplicate()
			var ko_bak: int = ko_point
			for i in n_all:
				board[i] = int(b_n.get(i, 0))
			ko_point = -1
			var ok_cross: bool = can_place_at(mv_n, AI_COLOR)
			for i in n_all:
				board[i] = int(board_bak.get(i, 0))
			ko_point = ko_bak
			if not ok_cross:
				cross_bad.append("局面%d 选点 %d 游戏侧判非法（两份规则已分叉）" % [bi, mv_n])
	if _yema_nn.prior_calls != _yema_boards.size():
		nn_bad.append("prior_calls=%d ≠ 局面数 %d（有局面没注入先验）" % [
			_yema_nn.prior_calls, _yema_boards.size()])
	if mix_max <= 0:
		nn_bad.append("ext_prior_last_mix 恒 0 ⇒ 先验没进根层（钩子没跑，或被剪枝吃掉了）")
	# ★★ ⑤ 的红条件**不再是** "首选必须换人"（2026-10-24 改，原写法会误杀正品）：
	#   本工程的训练标签就是**教师（`AIEngine`）自己的选点**（`--aigraph` 的 `GNN,L,`
	#   行 `teacher_v`）⇒ 网络是磐石的学生 ⇒ 与磐石**首选一致恰恰是学得好**。
	#   换成 v2 权重后实测 0/3（v1 时是 3/3），而 ⑥b 同一批局面"换进/换出 9 个"、
	#   ⑥c 跨度 11.3454 > v1 的 9.5387 ⇒ 不是退化，是**判据口径错**（§71）。
	#   改量两个**方向无关**的量（§101 多面拆条）：
	#     ⑤a `order_diff > 0`：混合后排序必须真的动过（0 = 装了等于没装）
	#     ⑤b `w≥1` 时首选必须 = 网络首选：满权时混合结果必须**完全忠于网络**
	#        （`scores` 没写回 / `w` 没生效 / 排序口径被改坏，三种静默故障都会踩这条）
	if odiff_min <= 0:
		nn_bad.append("开态混合后排序与磐石逐位相同（各局面变动 %s 点）⇒ 网络对排序无影响（装了等于没装）" % str(odiff_txt))
	# ★ ⑤b 的**有效分母** = "网络首选与磐石首选不同"的局面数，必须先算再断言（§106）：
	#   本批 3 个固定局面上两者 3/3 全一致 ⇒ 分母 0 ⇒ 这条**一次都没测到**，不许当通过。
	var disagree_cnt: int = _yema_boards.size() - agree_cnt
	if mix_w >= 0.999 and disagree_cnt > 0 and is_net_cnt < _yema_boards.size():
		nn_bad.append("w=%.2f 但混合后首选只在 %d/%d 个局面 = 网络首选 ⇒ scores 没写回 / 排序口径坏了" % [
			mix_w, is_net_cnt, _yema_boards.size()])
	var worst_ms := 0
	for x in priors_ms:
		worst_ms = maxi(worst_ms, x)
	if worst_ms > 200:
		nn_bad.append("先验耗时 %dms > 200ms（本轮预算被吃掉）" % worst_ms)
	for s in nn_bad:
		bad.append("④ " + s)
	# ★ 这条与 ④ 分开计（§101：多面须拆条）：④ 量"先验进没进根层"，⑤ 量"进得多深"。
	for s in cross_bad:
		bad.append("⑥ " + s)
	print("[yematest] ④ 开态先验：prior_calls=%d · 根层混合候选最多 %d 个 · 先验耗时 %s ms" % [
		_yema_nn.prior_calls, mix_max, str(priors_ms)])
	print("[yematest] ⑤ 开态排序受先验影响：排序变动 %s 点（min %d）· 首选=网络首选 %d/%d · w=%.2f · 首选换人 %d/%d%s" % [
		str(odiff_txt), odiff_min, is_net_cnt, _yema_boards.size(), mix_w,
		moved_cnt, _yema_boards.size(),
		"" if rank_txt.is_empty() else " " + str(rank_txt)])
	print("[yematest] ⑤b 有效分母：网络与磐石首选一致的局面上 %d/%d ⇒ ⑤b 实测分母 %d%s" % [
		agree_cnt, _yema_boards.size(), disagree_cnt,
		"（**0 ⇒ 本条本批无分辨力**，不是通过）" if disagree_cnt == 0 else ""])
	if moved_cnt == 0:
		# ★ 不是红：如实说明"为什么一次都没换人"，免得下一个人重新怀疑一遍。
		print("[yematest] ⑤ 说明：本批局面里网络与磐石**首选完全一致** —— 训练标签即教师选点（网络是磐石的学生），一致属正常。影响力看上面的排序变动点数。")
	print("[yematest] ⑥ 跨引擎合法性：异常 %d 处%s" % [
		cross_bad.size(), "" if cross_bad.is_empty() else " " + str(cross_bad)])

	# ---- ⑥b 钩子位置：网络必须能改变"**哪些**候选进搜索" ----
	# ★★ 为什么单列（这是本次接入最容易犯、最难看出来的一处）：
	#   `_prepare_root()` 里的 Top-K 剪枝本身就是"按 `scores` 排序取前 K 个"。
	#   把 `_mix_external_prior()` 放在剪枝**之后**，网络就只改内部顺序、对**候选集毫无影响**
	#   —— 而 ④（混合发生了）与 ⑤（根层首选变了）**照样全绿**，日志一切正常，
	#   只是"网络本来能救回来的候选永远进不了搜索"。
	# 判据：同一局面、同参数下，`w=1` 与 `w=0` 两次 `_prepare_root()` 的**候选集**必须不同。
	#   走的是真源 `prepare_root_for_dump()`（不搜索、秒级、与 `choose_move` 同一调用序列）。
	# ★ 元断言（§106）：候选集只有 `< root_width` 个时剪枝根本没裁剪 ⇒ "候选集不变"是废话
	#   ⇒ 这种情况**报红**，不许当通过。
	var b9: Dictionary = _yema_boards[0].duplicate()
	var st9 := 0
	for v in b9.keys():
		if int(b9[v]) != 0:
			st9 += 1
	var pri9: PackedFloat32Array = _yema_nn.nn.score_points(b9, AI_COLOR, st9, -1)
	var e_on := AIEngine.new()
	e_on.setup(adjacency, AI_COLOR, 20261023)
	_yema_pin(e_on)
	e_on.ext_prior = pri9
	e_on.w_external_prior = 1.0
	var r_on: Dictionary = e_on.prepare_root_for_dump(b9, -1)
	var e_off2 := AIEngine.new()
	e_off2.setup(adjacency, AI_COLOR, 20261023)
	_yema_pin(e_off2)
	e_off2.w_external_prior = 0.0
	var r_off: Dictionary = e_off2.prepare_root_for_dump(b9, -1)
	var c_on: Array = r_on["cands"]
	var c_off: Array = r_off["cands"]
	var set_off := {}
	for v in c_off:
		set_off[int(v)] = true
	var set_on := {}
	for v in c_on:
		set_on[int(v)] = true
	var only_on := 0
	for v in c_on:
		if not set_off.has(int(v)):
			only_on += 1
	var only_off := 0
	for v in c_off:
		if not set_on.has(int(v)):
			only_off += 1
	var pos_bad: Array[String] = []
	if c_off.size() < 12:
		pos_bad.append("关先验候选集只有 %d 个（< root_width 12）⇒ 剪枝没生效，本条无分辨力" % c_off.size())
	elif only_on + only_off == 0:
		pos_bad.append("开/关先验的根候选集**完全相同**（%d 个）⇒ 钩子在剪枝之后" % c_on.size())
	for s in pos_bad:
		bad.append("⑥b " + s)
	print("[yematest] ⑥b 钩子位置（须在剪枝前）：候选集 %d → %d · 网络换进 %d 个/换出 %d 个%s" % [
		c_off.size(), c_on.size(), only_on, only_off,
		"" if pos_bad.is_empty() else " · " + str(pos_bad)])

	# ---- ⑥c 网络输出必须是**非常数**（输入层的元判据）----
	# ★ 为什么单列：若权重全零 / 特征归一化常数被改坏 / 加载到别的 arch，`ext_prior` 会退化成
	#   常数。此时 ④（混合发生了）、⑥b（候选集变了 —— 全平手时排序的不稳定足以让集合抖动）、
	#   ⑤（根层首选变了）**都可能照样绿**，而"网络其实一个字的判断都没提供"不会被打印出来。
	#   判据只看极差：常数 ⇒ 直接报红（§106「有效分母=0 须报红」的同族）。
	# ⚠️ 量的是 `inner.ext_prior`（引擎**真正拿到**的那份），不是自检自己算的另一份
	#   —— 否则砍 YemaAI 的注入代码时它不会红（两边不是同一个对象，§110）。
	# ★★ 哨兵必须排除在跨度之外：`score_points()` 对**非空点 / 劫点**填 `-1.0e9`
	#   （见该函数的 `out.fill(-1.0e9)`）。把它们算进来，跨度恒 ≥ 1e9 ⇒ 网络真的退化成
	#   常数（真实候选分数全 0）时极差照样 1e9 ⇒ 这条判据**恒绿**。
	#   本轮实测踩到：第一版打印的跨度是 1000000007.7596，而真实候选的跨度只有约 3。
	var pv: PackedFloat32Array = _yema_nn.inner.ext_prior
	var p_lo := 1e30
	var p_hi := -1e30
	var p_live := 0
	for x in pv:
		if x <= -1.0e8:
			continue                      # 哨兵：非空点 / 劫点
		p_live += 1
		p_lo = minf(p_lo, x)
		p_hi = maxf(p_hi, x)
	var span_ok: bool = pv.size() == adjacency.size() and p_live > 0 and (p_hi - p_lo) > 1e-6
	if pv.size() != adjacency.size():
		bad.append("⑥c 注入的 ext_prior 长度 %d ≠ n %d" % [pv.size(), adjacency.size()])
	elif p_live == 0:
		bad.append("⑥c 没有任何非哨兵点（有效分母 0）⇒ 本条无分辨力")
	elif not span_ok:
		bad.append("⑥c 网络输出退化成常数（非哨兵极差 %.9f）⇒ 权重/特征坏了，等于没接" % (p_hi - p_lo))
	print("[yematest] ⑥c 网络输出：非哨兵 %d 点 · 跨度 %.4f（%.4f ~ %.4f）· 哨兵 %d 个%s" % [
		p_live, p_hi - p_lo, p_lo, p_hi, pv.size() - p_live, "" if span_ok else " ✗ 常数！"])

	# ---- ⑦ 特征对拍（引擎侧 vs 训练脚本导出的**两档** golden）----
	# 这一条是"接入前必跑一次"的那条 —— 特征是训练与推理之间唯一可能悄悄分叉的地方
	# （改动 `_feat_at()` 的归一化常数、或换 `norm` 口径，都会让权重彻底失效而**不报错**）。
	# ★★ 为什么必须**两份**：`_feat_at()` 现在有 v1(17 维) / v2(25 维) 两条口径，按权重的
	#   `feat_dim` 二选一。只验 v2 ⇒ 线上仍在用的 v1 权重那条分支变成"没人看"的死代码
	#   （§138：没有对照组就不知道它坏没坏）。两份 golden 各自声明 `feat_version`，
	#   `check_golden()` 按声明选口径 ⇒ 两条分支各有一把刀。
	# ★ 顺手把两份耗时打出来：v2 多一次整盘 `_group_info()` + 每点结构量。两份 golden
	#   的局面数与点数**完全相同**，所以这两个数可以直接当"v2 比 v1 慢多少倍"读。
	var gfiles: Array = ["res://ai/yema_golden.json", "res://ai/yema_golden_v1.json"]
	for gp in gfiles:
		if not FileAccess.file_exists(gp):
			# ★ §96：没跑不许长得像通过 —— 缺失本身报红（少一份 = 少一条分支的守卫）
			print("[yematest] ⑦ 特征对拍 ✗ %s：**未跑**（文件不存在）" % gp)
			bad.append("⑦ %s 不存在 ⇒ 该口径的特征分叉无法发现" % gp)
			continue
		var t_g0: int = Time.get_ticks_usec()
		var gbad: int = _yema_nn.nn.check_golden(gp)
		var gdt: float = float(Time.get_ticks_usec() - t_g0) / 1000.0
		var gwhy := ""
		if gbad == -1:
			gwhy = "（文件读不了 / 不是 JSON）"
		elif gbad == -2:
			gwhy = "（有效分母 0：golden 的盘型与这张盘点数不符 ⇒ 本条无分辨力）"
		elif gbad > 0:
			gwhy = "（改动特征口径会让权重失效且不报错）"
		if gbad != 0:
			bad.append("⑦ 特征对拍 %s 失败 %d 条%s" % [gp, gbad, gwhy])
		print("[yematest] ⑦ 特征对拍 %s %s：不一致 %d 条 · 检查 %d 点 · 耗时 %.1f ms%s" % [
			"✓" if gbad == 0 else "✗", gp, gbad,
			_yema_nn.nn.golden_checked, gdt, gwhy])

	# ---- ⑦b v1/v2 特征耗时对照（同一局面、同一条 `_feat_at()`）----
	# ★ 为什么必须单列：`④` 测的是**当前权重那一条口径**，而线上权重是 v1
	#   ⇒ 换成 v2 权重之前，v2 的耗时**根本不会被 ④ 摸到**（先验预算 200 ms 是硬约束：
	#   `ai_engine.gd` 的 `time_budget_ms`）。加 8 维结构特征后必须知道它涨到多少。
	# ★ 判据为什么是**比值**：绝对毫秒随机器变，而"v2 / v1 的倍数"能直接咬住一种静默坏法
	#   —— 把 `_group_info()` 挪进**逐点循环**（O(n+E) 变成 O(n×(n+E))）。那种改法在功能上
	#   **完全正确**（⑦ 的 golden 对拍照样 0 条不一致），只是慢几十倍，而且日志一片绿。
	# ★ 阈值为什么是 **10×**（不是 3×）：实测正品就是 2.9×（v1 0.27ms / v2 0.78ms），
	#   阈值贴着实测值写会变成"随机器抖动随机报红"的假牙（§121 哑刀第三种形态）。
	#   而真正要咬的坏法是 ~120×（每个候选各跑一次 O(n+E)）⇒ 10× 离两边都远，留足余量。
	var f_v1: float = _yema_feat_cost_ms(_yema_boards[0], 1, 12)
	var f_v2: float = _yema_feat_cost_ms(_yema_boards[0], 2, 12)
	var f_ratio: float = f_v2 / maxf(f_v1, 0.001)
	var f_ok: bool = f_ratio <= 10.0 and f_v2 <= 60.0
	if not f_ok:
		bad.append("⑦b 整盘特征耗时 v1=%.2fms v2=%.2fms（%.2f×）⇒ %s" % [
			f_v1, f_v2, f_ratio,
			"多半把 _group_info() 挪进了逐点循环（功能对但慢几十倍）" if f_ratio > 10.0
			else "v2 整盘特征已吃掉先验预算的一大半（>60ms / 200ms）"])
	print("[yematest] ⑦b 整盘特征耗时 %s：v1 %.2f ms → v2 %.2f ms（%.2f×，先验预算 200 ms）" % [
		"✓" if f_ok else "✗", f_v1, f_v2, f_ratio])

	# ---- ⑧ 异步路径（对局走的就是它）----
	# 不能在这里 await：`_ready` 一旦变成协程，启动横幅与全部分派都会变成"恢复后才跑"的
	# 代码（本工程有 S103 那条前科）⇒ 用 call_deferred 把它推到下一帧独立跑。
	_yema_async_probe.call_deferred()


## ⑦b 用：测"整盘特征"耗时（ms/次），被测物 = `NNScore.compute_feats()` 本体。
##
## ★★ 为什么调 `compute_feats()` 而不是自己写一遍"先算 grp 再逐点"的循环：
##   那样写等于判据自己重实现被测逻辑 —— 把 `score_points()` 里的 `_group_info()`
##   **挪进逐点循环**时，我这个循环照样算得快、判据照样绿（§70 的形态）。
##   抽成 `compute_feats()` 之后，`score_points()` 与这条判据是**同一个函数**，
##   坏在哪边都跑不掉。
## ★ 不跑 `_forward()`：这条要在 v1/v2 **两条口径**上各量一次，而当前加载的权重可能
##   只匹配其中一条（权重 17 列 / 特征 25 维）⇒ 硬跑前向会 `row[j]` 越界。
##   `_forward()` 与特征口径无关（工作量 = 点数 × 层宽），省掉它不影响比值。
func _yema_feat_cost_ms(board_dict: Dictionary, version: int, reps: int) -> float:
	var nn: NNScore = _yema_nn.nn
	var r: int = maxi(reps, 1)
	var t0: int = Time.get_ticks_usec()
	for _rep in r:
		nn.compute_feats(board_dict, AI_COLOR, 0, -1, version)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(r)


## ⑧ 异步路径专项：`choose_move_async()` 里先验必须在 `await` **之前**注入。
##
## ★ 判据为什么是 `ext_prior_last_mix > 0`：`_prepare_prior()` 若被挪到
##   `await inner.choose_move_async(...)` **之后**，本手搜索时 `inner.ext_prior` 还是空的
##   ⇒ `_prepare_root()` 的条件不成立 ⇒ `ext_prior_last_mix == 0`。而**同步路径（④⑤）
##   会照样全绿** —— 两面各自独立，只有这一条能红。
##   ⚠️ Godot 4.7 编译器禁止"调用协程不带 await"（实测 Parse Error:
##      `Function "_f()" is a coroutine, so it must be called with "await"`），
##      所以拿不到"调用前后 prior_calls 有没有涨"那种时序探针 ⇒ 改用上面这个间接量。
func _yema_async_probe() -> void:
	if _yema_nn == null or _yema_boards.is_empty():
		_yema_bad.append("⑧ 前置状态缺失（同步段没跑到开态实例）")
		_finish_yema_test()
		return
	# ★★ 必须用**全新实例**，不能复用 `_yema_nn`。
	#   实测证据（刀 2）：第一版就是复用 —— 于是把 `_prepare_prior()` 挪到 `await` **之后**
	#   之后，本手搜索仍然读到 `_yema_nn.inner.ext_prior` 里**上一手（同步段第 3 手）残留**的
	#   先验（`size()==n` 且 `w==1` 两个条件都还成立）⇒ `ext_prior_last_mix` 照样 = 72
	#   ⇒ **本条恒绿，刀砍不动**。这正是 §110：判据的参照物不能与被测物共用
	#   "已经有值"的状态。换一个从没注入过先验的实例，空 `ext_prior` 才是有分辨力的起点。
	var e_async := YemaAI.new()
	e_async.setup(adjacency, AI_COLOR, 20261023)
	e_async.threads = 1
	e_async.time_budget_ms = YEMA_TEST_MS
	e_async.root_width = 12
	e_async._apply_search_params()
	e_async.inner.max_playouts = YEMA_TEST_PW
	var async_bad: Array[String] = []
	var mv_async: int = await e_async.choose_move_async(
		_yema_boards[0].duplicate(), -1, AI_COLOR)
	if e_async.inner.ext_prior_last_mix <= 0:
		async_bad.append("异步首手 ext_prior_last_mix=0 ⇒ 先验没在 await 之前注入"
			+ "（本手搜索用的是空的 ext_prior）")
	if mv_async < -1 or mv_async >= adjacency.size():
		async_bad.append("异步返回 %d（越界）" % mv_async)
	for s in async_bad:
		_yema_bad.append("⑧ " + s)
	print("[yematest] ⑧ 异步路径（全新实例首手）：mv=%d · 根层混合 %d 个 · prior_calls=%d%s → %s" % [
		mv_async, e_async.inner.ext_prior_last_mix, e_async.prior_calls,
		"" if async_bad.is_empty() else " · " + str(async_bad),
		"✓" if async_bad.is_empty() else "✗"])
	_finish_yema_test()


func _finish_yema_test() -> void:
	print("[yematest] 结论：%s %s" % [
		"通过 ✓" if _yema_bad.is_empty() else "失败 ✗", str(_yema_bad)])
	get_tree().quit()


func _start_ai_turn():
	# 防守：本地双人/联机模式下绝不允许 AI 接管回合

	if game_mode != VS_AI:
		return
	if current_player != AI_COLOR or is_ai_thinking or game_over:
		return
	is_ai_thinking = true
	_show_ai_hud(true)
	_update_hud()  # 立即显示“白棋思考中”
	# 稍微停顿一下再思考，让玩家看清刚才那手（0.12s：既能看清，又不至于在每手固定加一段可感延迟）
	await get_tree().create_timer(0.12).timeout
	if game_over or current_player != AI_COLOR:
		# 等待期间被重置/终局：必须自己把思考态收回，否则 HUD 会一直停在「思考中」，
		# 秒表协程也会永远 await 下去（重置路径靠 reset_game 清标记，终局路径没人清）
		_show_ai_hud(false)
		is_ai_thinking = false
		_update_hud()
		return
	var gen: int = _ai_gen
	# ★ 骨架对手模式（测试按钮）：不走 ai_engine，白方由第三套实现接管。
	#   1 手贪心（TT 面积差最大化），无搜索、不认输 —— 骨架的诚实棋力。
	if xg_play_mode:
		_show_ai_hud(true, "骨架思考中…")
		# ★ 2026-10-20：走**异步版**（后台线程）。原先同步调 => 每手约 90ms 不给主线程一帧
		#   ⇒ HUD 文字改了却没重绘、画面定格 ≈5~6 帧，用户看到的就是"落子前卡一下"。
		#   `await` 让主线程边等边渲染；`gen != _ai_gen` 的作废检查在下面照旧生效。
		var xmove: int = await _xg_choose_move_async(AI_COLOR)
		if gen != _ai_gen or game_over or current_player != AI_COLOR:
			_show_ai_hud(false)
			is_ai_thinking = false
			_update_hud()
			return
		_apply_ai_move(xmove)
		_show_ai_hud(false)
		is_ai_thinking = false
		_update_hud()
		return
	# 极度劣势时先认输，不再浪费一次搜索（判据见 _ai_resign_eval）
	if _ai_try_resign():
		_show_ai_hud(false)
		is_ai_thinking = false
		_update_hud()
		return
	_show_ai_hud(true, "AI 思考中…")
	_ai_hud_tick()   # 并发跑秒表（不 await：思考本身仍在下一条语句里）
	var move_id: int = -1
	# 搜索在后台线程进行，主线程每帧让出：思考期间画面/提示不会冻结
	# ★ 2026-10-22：流水档走 `ai_liushui`（渗流引擎），其余走生产引擎。
	#   两者的 `choose_move_async` **签名/语义/MCTS 作废机制完全相同**（都是快照 + 后台线程 +
	#   `gen != _ai_gen` 作废），所以下面的收尾代码一行都不用分叉。
	# ★ 2026-10-23：野马档走 `ai_yema`（神经网络先验 + 内部磐石搜索）。它**也**满足上面那条
	#   "签名/语义/作废机制完全相同"——`YemaAI.choose_move_async` 只是先同步算一次网络先验
	#   （3~8ms，在主线程，比 200ms 的搜索短一个量级），再 `await` 内部磐石的同名方法。
	#   所以收尾代码同样不分叉。
	if yema_play_mode:
		move_id = await ai_yema.choose_move_async(board, ko_point, AI_COLOR)
	elif liushui_play_mode:
		move_id = await ai_liushui.choose_move_async(board, ko_point, AI_COLOR)
	else:
		move_id = await ai_engine.choose_move_async(board, ko_point)
	# 思考期间可能发生了重置/终局/换局：本轮结果作废
	if gen != _ai_gen or game_over or current_player != AI_COLOR:
		_show_ai_hud(false)
		is_ai_thinking = false
		_update_hud()
		return

	_apply_ai_move(move_id)
	_show_ai_hud(false)
	is_ai_thinking = false
	_update_hud()


# ====== AI 思考提示 HUD ======
var _ai_hud_layer: CanvasLayer
var _ai_hud_label: Label

func _build_ai_hud() -> void:
	_ai_hud_layer = GameConfig.new_themed_layer()
	_ai_hud_layer.name = "AIHud"
	_ai_hud_layer.layer = 20
	_ai_hud_layer.visible = false
	add_child(_ai_hud_layer)
	_ai_hud_label = Label.new()
	_ai_hud_label.text = "AI 思考中…"
	_ai_hud_label.add_theme_font_size_override("font_size", 26)
	_ai_hud_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1))
	_ai_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ai_hud_label.add_theme_constant_override("outline_size", 6)
	var vsize := get_viewport_rect().size
	_ai_hud_label.position = Vector2(vsize.x - 220, 20)
	_ai_hud_layer.add_child(_ai_hud_label)

func _show_ai_hud(show: bool, text: String = "") -> void:
	if _ai_hud_layer:
		_ai_hud_layer.visible = show
	if show and text != "" and _ai_hud_label:
		_ai_hud_label.text = text

## 思考期间在 HUD 上滚动显示已用时间。
## 目的不是装饰：固定预算下玩家无法判断「还要等多久」会显得比实际更久，
## 给出秒表后等待就有了上限感（本函数与搜索协程并发运行，靠 is_ai_thinking 收尾）
func _ai_hud_tick() -> void:
	var t0 := Time.get_ticks_msec()
	while is_ai_thinking:
		await get_tree().process_frame
		if _ai_hud_label == null or not _ai_hud_layer.visible:
			continue
		var el := float(Time.get_ticks_msec() - t0) / 1000.0
		_ai_hud_label.text = "AI 思考中…  %.1fs" % el

# ====== 重置 ======
func reset_game(quiet: bool = false) -> void:
	# AI 思考是异步的：代次 +1 后，上一局遗留的思考协程返回时会发现代数变了，自行丢弃结果
	_ai_gen += 1
	# ★ 覆盖层一并失效：重开新局必须回到正常 HUD 轮换（否则"加载失败"提示会卡到下一局）。
	_hud_override = ""
	for vid in board.keys():
		board[vid] = Stone.EMPTY
	current_player = Stone.BLACK
	ko_point = -1
	is_ai_thinking = false
	passes = 0
	game_over = false
	black_prisoners = 0
	white_prisoners = 0
	_place_anims.clear()
	_capture_anims.clear()
	_last_move = -1
	# 悔棋栈也清：新局没有"上一次落子"可言（残留旧栈 ⇒ 悔一把回到上一局的局面）。
	# ★ 同理 `_undo_used`：它是**每局**额度，重新开始 = 新的一局。
	_hist.clear()
	# ★ superko 历史同样每局重建（新局 = 新历史），且此刻 `board` 已清空 ⇒ 首个局面是空盘。
	_superko_init()
	_undo_used.clear()
	_undo_pending_from = -1
	_undo_freeze = false
	_clear_undo_overlay()
	# ★ 棋谱开新局（阶段①）。放在这里而不是 `restart_game()`：联机加入方是
	#   `_apply_snapshot()` 之后**不走** `restart_game()` 的，而它的盘/种子也是房主下发的，
	#   谱头必须跟着换（否则加入方记的是"我自己那张随机盘"的种子 ⇒ 复盘重放出一张别的盘）。
	#   `reset_game()` 是"清盘面重下一局"的**唯一**入口 ⇒ 谱的生命周期与盘面严格同生命周期。
	_record_close_if_unfinished()
	_record_begin()
	# 悬浮预览也要清：棋盘换了（或棋清了）之后 _hover_tile 可能指向另一块砖 —— 鼠标没动时
	# 没有任何 motion 事件来纠正它，会画出一块「没跟踪鼠标」的鬼影。
	_hover_tile = -1
	_terr_mark.clear()
	_clear_result_overlay()
	_clear_count_prompt()
	# ★ 棋钟：新局 = 双方时间回满、读秒次数复位、频率样本清空、超时标记清掉。
	#   放在这里（而不是 `restart_game()`）：`reset_game()` 是"清盘面重下一局"的**唯一**
	#   入口 —— 联机加入方走的是快照路径、并不经过 `restart_game()`，同样要把钟归零。
	if _clk != null:
		_clk.reset()
		clk = _clk.snapshot()
	_show_ai_hud(false)
	# 新棋局必须清空 AI 的搜索树与历史快照，否则会复用上一局的局面
	if ai_engine:
		ai_engine.reset_state()
	_update_hud()
	queue_redraw()
	if not quiet:
		print("游戏已重置")

## 开一局新的：单机随机档会**重新抽种子并重新生成棋盘**（每局一张新盘），固定档只清盘面。
## seed_val >= 0 时直接用它而不是重抽（自检/复现用）。
##
## 联机不换盘（见 _regen_on_restart）：一场对局的盘面是开局那一刻定下来的，
## 中途「重新开始」只是把棋清空重下；换盘会让对手莫名其妙，也白白多一个同步面。
func restart_game(seed_val: int = -1) -> void:
	# ★ 换盘前先把旧谱关掉：`restart_game()` 会在 `reset_game()` 里开新谱，
	#   而新谱一开就把 `_record` 换了 ⇒ 半局谱连"中断"这一句都没写上就没了。
	#   （顺序不能反：`_record_close_if_unfinished()` 只看 `_record`，此刻它还是旧那局。）
	_record_close_if_unfinished()
	if _regen_on_restart():
		_rand_seed = seed_val if seed_val >= 0 else _fresh_seed()
		generate_board()
		_adapt_to_screen()
		if ai_engine:
			ai_engine.setup(adjacency, AI_COLOR)
			ai_engine.time_budget_ms = ai_time_ms
			ai_engine.threads = GameConfig.ai_threads
			ai_engine.root_width = GameConfig.ai_root_width
	reset_game(true)

## 重开时是否重生成棋盘：随机档 × 非联机。
## 联机之所以排除：双端盘面靠「房主下发几何 + 同种种子」保持一致，
## 让每一局都换盘需要多播一次种子，收益却只是「重置时换个形状」，不值得引入这个风险。
## 想换盘就退回菜单再开一局（那时两边都会重新生成）。
func _regen_on_restart() -> bool:
	return _is_random_board() and game_mode != ONLINE

# ====== 棋钟（2026-10-16）======
## 时钟内核。★ **逻辑全在 `game_clock.gd`**（纯逻辑、可喂固定 delta 复现）；这里只有
## 三件接线：每帧喂 `delta`、落子/停手时通知它、把快照挂到 `clk` 上。
var _clk: GameClock = null
## 棋钟**只读快照**。★★ 音乐靠**反射**读它（`music.gd::_read_battle_state()` 里的
## `sc.get("clk")`）：字段名必须叫 `clk`、类型必须是 `Dictionary`，
## 这条契约由**两侧各一条判据**共同守着 ——
##   · 静态：`--musictest` 判据⑦ 查源码里有 `var clk`（改名 ⇒ 当场红）；
##   · 运行期：`--clocktest` 判据⑬ 在**真场景**上核对它真的挂上去了、且带音乐要的三个键。
var clk: Dictionary = {}

# ====== 常驻对局 HUD（停一手 / 重新开始 / 回合提示）======
var _hud_layer: CanvasLayer
var _hud_box: VBoxContainer
var _hud_buttons: Array[Button] = []
var _hud_turn_label: Label
var _hud_override: String = ""   # 对局 HUD 轮换文案的**覆盖层**：非空时 `_update_hud()` 优先显示它
var _pass_btn: Button
var _undo_btn: Button            # 悔棋按钮（文案随 `can_undo()` / 额度变化，见 _update_hud）
## 「邀请好友」（2026-10-21 用户口令「在游戏里直接点击就能召唤 steam 邀请好友窗口」）。
## ★★ **刻意不进** `_hud_buttons`：那个数组是 `_refit_hud()` 与 `judge_hud_layout()` 的
##   **枚举基**（出屏 / 触摸目标两条判据都按它走）。本按钮只在「联机 · 我是房主 · 房间号已回」
##   时可见，混进枚举基之后那两条判据在**本地/人机**档就会量到一个 size=0 的隐藏按钮
##   ⇒ 判据红得没有意义（同 `_hud_clock_label` 与复盘按钮那两处的理由）。
##   代价是它的尺寸要在 `_refit_hud()` 里**单独**设一份 —— 那段与按钮组紧挨着，改的时候一起改。
var _invite_btn: Button = null
## 棋钟那一行（"▶黑 9:58 · 白 9:32"）。★ 与回合提示同列、紧跟其后，但**不进**
## `_hud_buttons`：它不是按钮，而 `judge_hud_layout()` 是按 `_hud_buttons` 枚举的
##（同 `_rp_buttons` 那条理由：判据量的集合不许混进非按钮）。
var _hud_clock_label: Label = null

# ====== 联机身份条 / 快捷表情（2026-10-21）======
# 需求原话：「联机太单调了，能不能把双方头像放进去，或者更进一步加入表情包或者聊天」。
# 本批交付：**双方 Steam 头像 + 昵称 + 执色/准备状态** 常驻对局页，加 **一键快捷表情**。
# 文字聊天**不在本批**：`LineEdit` 会抢键盘焦点（对局里 R=重置 等快捷键会被吃掉），
# 且 IME 输入在 `--headless` 自检里根本测不到 —— 那是独立一档，见记忆 §128。
#
# ★★ 全部新 UI 都**不进** `_hud_buttons` / `_hud_box`：
#   那两个是 `_refit_hud()` 与 `judge_hud_layout()` 的**枚举基**（出屏 / 触摸目标两条判据
#   都按它走）。身份条与表情只在联机态可见，混进枚举基之后那两条判据在本地/人机档
#   就会量到一堆 size=0 的隐藏控件 ⇒ 判据红得毫无意义（同 `_invite_btn` / `_hud_clock_label`
#   那两处的理由）。代价是尺寸要各自单独设一份 —— 但换来的是一整套既有判据不用动。
#
# ★★★ 2026-10-21 第二轮（用户口令「严防重叠，把对局棋盘左右空白做成抽屉…」）：
#   身份槽与表情**搬进左抽屉**，对局按键（`_hud_box`）**搬进右抽屉**。
#   `_net_id_layer` 因此退役 —— 它的全部职责换成了 `_drawer_left_panel.visible`
#   （同一个派生点 `_refresh_net_extras()`，见那里）。
var _drawer_layer: CanvasLayer = null
## ★ 面板类型是 `Panel` 而不是 `PanelContainer`：见 `_build_drawers()` 那段注释
##   （`PanelContainer` 会被内容撑宽，而让位宽度是算出来的 ⇒ 两者会分家）。
var _drawer_left_panel: Panel = null
var _drawer_right_panel: Panel = null
var _drawer_left_body: VBoxContainer = null
var _drawer_left_handle: Button = null
var _drawer_right_handle: Button = null
## 左抽屉内容：两条身份槽 + 8 个表情（3 列）。★ 尺寸与摆法全在 `_refit_net_identity()`
## 与 `_build_drawers()`，两个函数各管一行（"谁摆位置 / 谁定尺寸"别混）。
var _emote_grid: GridContainer = null
var _net_id_self: Control = null            # 左抽屉内：自己（上）
var _net_id_peer: Control = null            # 左抽屉内：对端（下）
## 头像圆的 CPU 遮罩缓存：steam_id -> Texture2D（圆形 alpha）。
## ★ 只缓存"圆形化之后"的那张：原图在 `SteamNet` 里有自己的缓存，这里再存一份没有意义。
var _avatar_circle_cache: Dictionary = {}
## 两个槽**当前显示**的头像（0=自己 1=对端）。★ `_draw` 只读它，绝不在绘制里调 Steam ——
## 绘制里做"可能失败 + 要解码 + 要遍历像素"的活，会让一帧的耗时随头像是否就绪而变
## （掉帧且看不出原因），而且 `_draw` 会重绘很多次。
var _avatar_tex: Array[Texture2D] = [null, null]
## 自检用：各绘制入口被真实调用过的次数（key: identity / emote_cell / bubble）。
## ★ 判据"画出来了"不能靠"函数存在"，只能靠"这个计数涨了" —— 反例见 §121 哑刀三态。
var _draw_ticks: Dictionary = {}
var _avatar_retry_acc: float = 0.0          # 头像重试节奏累加器（0.5s 一问）

## 抽屉开合的用户意图（点把手翻的就是这两个）。★ **不含**"视口太窄"那条派生 ——
## 那是 `_drawer_cramped()` 的事，两者一混就再也说不清"面板为什么是收起的"。
var _drawer_left_open: bool = true
var _drawer_right_open: bool = true
## 让位宽度**系数**：`1.0` = 按几何真源让位。
## ★ 存在的唯一理由是给判据配一把**阴性对照刀**：压到 0 ⇒ 面板照旧展开、棋盘不再让位 ⇒
##   `judge_drawer_layout()` 必须当场报红。没有它的话，"面板与棋盘不重叠"这条判据
##   只能在**已经摆对**的局面里跑，永远绿 —— 等于没有判据（§110 参照物不许与被测物同源）。
## ★ 出货恒为 1.0，且 `--drawertest` ⑦ 会断言它就是 1.0（防止有人把这把刀留在半开的位置）。
var _drawer_band_ratio: float = 1.0
## 抽屉面板**实际**的底色。所有画在抽屉上的东西（身份槽、表情格、回合提示、棋钟行）
## 挑字色都只认 `_drawer_surface()` —— **不是** `page_surface()`。
## ★★ 2026-10-21 实测踩到的真 bug：抽屉底是**深色**（`overlay_surface()`，L≈0.1），
##   而身份槽与回合提示仍在按 `page_surface()`（宣纸主题下是暖米白）挑字色 ⇒
##   **深棕字压在深棕底上**。截图量出来的对比度：身份槽 1.2、回合提示 ~1.0（等于没字）。
##   ⚠️ 当时 `--emotetest` 13 条全绿、`judge_hud_text_theme` 也绿 —— 因为它量的参照面
##     是页面底，而字根本不画在页面底上。**判据的参照物选错，绿得毫无意义**（§110）。
## ⚰️ 2026-10-22 墓碑（名字不许回收）：这里原有 `var _drawer_surface_cache: Color`。
##   它是"建抽屉时拍一张底色快照"，主题一变就与 StyleBox 脱钩（底与字一起停在旧主题）。
##   底色本来就是从页面底推出来的**纯函数** ⇒ 缓存已删，真源搬到 `_drawer_surface()`。

## 两个槽各自的**剩余寿命**（秒）。>0 = 正在显示。★ 与 `_emote_bubble_idx` 一一对应：
## 只写寿命不写 idx 就会"淡出时闪回上一个表情"（这类错位只在快速连发时看得见）。
var _emote_bubble_left: Array[float] = [0.0, 0.0]
var _emote_bubble_idx: Array[int] = [-1, -1]
## 探针：上一帧**实际画出去**的表情 alpha，以及画那一刻的剩余寿命。
## 判据读这两个（真画出去的数 + 当时的输入），不读 `emote_slot_alpha()` ——
## 读派生函数等于判据自己问自己（§70）。
## ★ 为什么还要记 `_last_emote_left`：判据要断的是**两者的函数关系**（alpha 由剩余寿命
##   线性派生），而不是"某一时刻等于某个绝对值"。后者会被帧间自动 tick 扣掉的一两帧
##   干扰到必须放宽容差（那就是掩盖）。前者与时序无关，而且同样能断住"二值开关"那种退化。
var _last_emote_alpha: Array[float] = [0.0, 0.0]
var _last_emote_left: Array[float] = [0.0, 0.0]
var _emote_last_sent_ms: int = 0            # 上次发送时刻（节流用）

## ⚰️ 2026-10-22 墓碑（名字不许回收）：这里原有三个变量 ——
##   `_emote_bubble_layer`（CanvasLayer 27）/ `_emote_self_bubble` / `_emote_peer_bubble`。
##   那是一套**飘在棋盘上**的 132px 气泡面板，落点取 `board_area()` 的水平中线 ⇒ 说话时
##   必然盖住盘面上的空点。用户口令「表情包不要遮挡棋盘」⇒ 整套删除，
##   表情改成**画在身份槽的头像圆里**（那块区域在左抽屉内，结构上到不了棋盘）。
##   寿命 / 索引两个数组保留（它们是"谁在说什么、还剩多久"的真源，与画在哪无关）。

## 身份槽几何（逻辑像素）。★ 头像直径与槽位高是**一对**：头像比槽位高就会画出边框。
## ★★ 宽度必须 ≤ 左抽屉内容宽（`DRAWER_W_LEFT − 2×DRAWER_PAD` = 172）：
##   超出去的表现不是报错，而是内容把所在容器撑开 ⇒ 面板比 `_drawer_band()` 算的宽度更宽
##   ⇒ **右侧压到棋盘上**（正是这一轮要严防的那件事）。`--drawertest` ④ 就是量这条。
const NET_ID_AVATAR_DIA := 44.0
const NET_ID_SLOT_W := 172.0
const NET_ID_SLOT_H := 56.0
## 表情格：3 列 × 3 行（`Emotes.count()` = 8，最后一行 2 个）。
## ★ 3 列而不是 4：抽屉在**基准横屏 1152×720** 下每侧只能借到 ~250px，
##   4 列（4×52+3×8=232）会把面板撑到 252、进而把棋盘挤掉一档。3 列刚好塞进 172 内容宽。
const EMOTE_PANEL_COLS := 3
const EMOTE_CELL := 52.0
const EMOTE_CELL_GAP := 8.0
## 表情在头像上停留的时长 / 淡出段（秒）。
## ⚰️ 2026-10-22：这里原有 `EMOTE_BUBBLE_DIA = 132.0`（棋盘气泡面板的直径）。
##   气泡整套删掉、表情改画进头像圆之后它没有任何读者 ⇒ 删除（§33 死参数 = 旋钮拧不动）。
const EMOTE_BUBBLE_LIFE := 2.6
const EMOTE_BUBBLE_FADE := 0.45
## 表情发送节流（毫秒）。★ 防连点刷屏：P2P 是 reliable 通道，连发会排队挤压落子消息。
const EMOTE_SEND_GAP_MS := 600

# ====== 复盘 HUD（棋谱阶段② 交互层，2026-10-08）======
# ★★ 为什么是**独立一层**而不是往 `_hud_buttons` 里塞几个按钮：
#   `_hud_buttons` 是 `_refit_hud()` 与 `judge_hud_layout()` 的**枚举基**（出屏 / 触摸目标
#   两条判据都按它走）。复盘按钮混进去，那两条判据在复盘态下就会量到一组**对局里根本
#   不存在的按钮** ⇒ "判据量的东西"与"刀改的东西"当场分家（铁律 13）。
# ★ 复盘态下对局 HUD 整个隐藏（`_show_replay_hud()`），所以两层不会互相遮挡。
var _rp_layer: CanvasLayer = null
var _rp_panel: PanelContainer = null
var _rp_box: VBoxContainer = null
## 复盘按钮的枚举基（`judge_replay_hud_layout()` 用，形状与 `_hud_buttons` 对齐）。
var _rp_buttons: Array[Button] = []
var _rp_first_btn: Button = null
var _rp_prev_btn: Button = null
var _rp_play_btn: Button = null
var _rp_next_btn: Button = null
var _rp_last_btn: Button = null
var _rp_exit_btn: Button = null
var _rp_slider: HSlider = null
var _rp_info: Label = null
## 窄屏档：面板宽 < `RP_NARROW_W` 时按钮改用短符号文案（否则六个中文按钮会撑出面板）。
## ★ 它只由 `_refit_replay_hud()` 按**实测宽度**翻，且文案一律走 `_rp_label_for()`
##   —— 两处各写一份的话，窄屏下按一次播放就会把文案写回中文长版（静默、只在窄屏出现）。
const RP_NARROW_W: float = 520.0
var _rp_short: bool = false
## ★★ 滑条与游标的**互写重入闸**。`_rp_sync_ui()` 会写 `_rp_slider.value`，
##   而给 `HSlider.value` 赋值会**同步**触发 `value_changed` ⇒ 没有这道闸时
##   `_rp_on_slider_changed()` 会在一次跳转里再跑一遍 `replay_goto()`（重建两次盘面）。
##   症状不是崩，是**每次跳转都白重建一次** + 将来任何"跳转后再做点别的"的逻辑跑两遍。
var _rp_ui_lock: bool = false

func _build_game_hud() -> void:
	_hud_layer = GameConfig.new_themed_layer()
	_hud_layer.name = "GameHud"
	_hud_layer.layer = 25
	add_child(_hud_layer)
	var vb := VBoxContainer.new()
	vb.name = "HudBox"
	vb.add_theme_constant_override("separation", 8)
	_hud_box = vb
	# 位置不在这里定死：交给 _refit_hud()（横/竖两套摆法，且必须随窗口尺寸变化跟随）。
	# ★ 原来这里写死 `Vector2(vs.x - 320, vs.y - 110)` 且**没有任何 resize 跟随** ——
	#   窗口一缩放（或切全屏）HUD 就停在旧位置，**静默**（按钮还在，只是不在该在的地方）。
	#   与暂停面板 `_refit_pause_menu` 同一套路：手动定位 + size_changed 实时重排。
	_hud_layer.add_child(vb)
	_hud_turn_label = Label.new()
	_hud_turn_label.add_theme_font_size_override("font_size", 15)
	vb.add_child(_hud_turn_label)
	# 棋钟行：紧跟回合提示 —— "谁的钟在走"与"轮到谁"是同一条信息的两半，放一起才读得顺。
	# 字号/字色/SIZE 全在 `_refit_hud()` 里设（那里是 HUD 外观的唯一入口）。
	_hud_clock_label = Label.new()
	_hud_clock_label.name = "HudClock"
	_hud_clock_label.add_theme_font_size_override("font_size", 15)
	vb.add_child(_hud_clock_label)
	# ★★ 2026-10-21 改：HBoxContainer → VBoxContainer。
	#   用户口令「把对局棋盘左右空白做成抽屉，右边放对局按键」⇒ 按钮竖排进右抽屉
	#   （抽屉内宽 180，六个中文按钮横排根本塞不下：套上主题内边距后一行要 500+）。
	#   竖排的副作用是 HUD 变高 —— 但它现在在最右侧的**独立一列**里，不再浮在盘上，
	#   所以"变高"只是抽屉里多占几行，不会压棋盘（这正是抽屉的好处）。
	var hb := VBoxContainer.new()
	hb.name = "HudButtons"
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	_hud_buttons.clear()
	_pass_btn = Button.new()
	_pass_btn.text = "停一手"
	_pass_btn.focus_mode = Control.FOCUS_NONE
	_style_game_button(_pass_btn)     # 主题色（此前是引擎默认灰：用户报「没几个按钮用上主题色」）
	_pass_btn.pressed.connect(_on_pass_pressed)
	hb.add_child(_pass_btn)
	_hud_buttons.append(_pass_btn)
	# 悔棋（2026-10-02）：人机/本地直接悔，联机发请求。放进 `_hud_buttons` 才参与
	#   `_refit_hud()` 的横竖两套排版与 `judge_hud_layout()` 的出屏/高度判据 ——
	#   不进这个数组的按钮不会被排版也不会被量，等于"看得见但没人管"。
	_undo_btn = Button.new()
	_undo_btn.text = "悔棋"
	_undo_btn.focus_mode = Control.FOCUS_NONE
	_style_game_button(_undo_btn)
	_undo_btn.pressed.connect(_on_undo_pressed)
	hb.add_child(_undo_btn)
	_hud_buttons.append(_undo_btn)
	# 邀请好友（2026-10-21）：Steam 官方覆盖层邀请（`activateGameOverlayInviteDialog`）。
	# ★ 放进同一个按钮列（跟按钮组排在一起），但**不进** `_hud_buttons`（理由见变量声明处）。
	# ★ 默认隐藏：它只在 `_refresh_invite_btn()` 判定"我是房主且房间号已回"时才显示，
	#   而那一步在 `_update_hud()` 里 —— 建页时先藏，避免首帧闪出一个点不了的按钮。
	_invite_btn = Button.new()
	_invite_btn.text = "邀请好友"
	_invite_btn.focus_mode = Control.FOCUS_NONE
	_invite_btn.visible = false
	_style_game_button(_invite_btn)
	_invite_btn.pressed.connect(_on_invite_pressed)
	hb.add_child(_invite_btn)
	# ⚰️ 2026-10-21 墓碑（名字不许回收）：「表情」按钮与它的弹出九宫格面板整族删除。
	#   用户口令把表情收进**左抽屉** ⇒ 一直都是可见的，不需要一个"点开面板"的入口。
	#   留在原处的坏处：右抽屉里一个按钮点了只是为了弹出浮层盖住棋盘，与"严防重叠"直接冲突。
	var reset_btn := Button.new()
	reset_btn.text = "重新开始"
	reset_btn.focus_mode = Control.FOCUS_NONE
	_style_game_button(reset_btn)
	reset_btn.pressed.connect(_on_reset_pressed)
	hb.add_child(reset_btn)
	_hud_buttons.append(reset_btn)
	var resign_btn := Button.new()
	resign_btn.text = "认输"
	resign_btn.focus_mode = Control.FOCUS_NONE
	_style_game_button(resign_btn)
	resign_btn.pressed.connect(_on_resign_pressed)
	hb.add_child(resign_btn)
	_hud_buttons.append(resign_btn)
	var menu_btn := Button.new()
	menu_btn.text = "返回菜单"
	menu_btn.focus_mode = Control.FOCUS_NONE
	_style_game_button(menu_btn)
	menu_btn.pressed.connect(_on_return_to_menu_pressed)
	hb.add_child(menu_btn)
	_hud_buttons.append(menu_btn)
	# 窗口缩放 / 转屏（横↔竖）都要重排：`_refit_hud()` 是唯一的摆位入口。
	# ★ 2026-10-21 起 HUD **不再是浮在盘上的独立一簇**：它被摆进右抽屉，
	#   而右抽屉的宽度由 `board_area()` 从棋盘那里扣掉 ⇒ 棋盘与 HUD **结构性不重叠**。
	if not get_viewport().size_changed.is_connected(_refit_hud):
		get_viewport().size_changed.connect(_refit_hud)
	_build_drawers()
	_refit_hud()
	# 首帧容器的 size 还没有内容高度（BoxContainer 是延迟排版的），再摆一次精定位。
	# 这个 await 不会阻塞调用方：_build_game_hud 从 _ready() 里调用，await 之后的部分
	# 在协程里继续跑，_ready() 照常结束。
	await get_tree().process_frame
	_refit_hud()
	_update_hud()

## 按当前视口与横/竖形态重排 HUD。**这是唯一一处**决定 HUD 位置与触摸目标大小的地方
##（铁律 8：一处写、一处读）。首帧容器 size 可能还是 0，所以调用方要在一帧后再调一次。
func _refit_hud() -> void:
	if _hud_box == null or not is_instance_valid(_hud_box):
		return
	var portrait: bool = GameConfig.use_portrait_canvas()
	var min_h: float = GameConfig.hud_button_min_height()
	var fnt: int = GameConfig.hud_button_font_size()
	for b in _hud_buttons:
		if not is_instance_valid(b):
			continue
		b.custom_minimum_size = Vector2(0.0, min_h)
		# ★ 2026-10-21：按钮现在**竖排**在右抽屉里（`_build_game_hud()` 里 HBox → VBox），
		#   VBoxContainer 的横轴本来就把子节点拉满容器宽 ⇒ 这个 flag 只剩"语义"作用，
		#   两种形态统一 EXPAND_FILL（不要因为"横屏不是这一档"就退回 FILL，
		#   那会让将来的横轴容器改动时竖屏又变成不铺满）。
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if fnt > 0:
			b.add_theme_font_size_override("font_size", fnt)
		else:
			b.remove_theme_font_size_override("font_size")
	# ★ 邀请按钮与按钮组**同一把尺子**（触摸目标高度 / 横向伸展 / 字号）：
	#   它不在 `_hud_buttons` 里（见变量声明处），所以必须在这里单独设一份。
	#   ⚠️ 少写这一段的表现是"联机时它比邻座矮一截"——不是崩，只在目检里看得出来。
	# ★★ 2026-10-21：原来这里是给邀请按钮单独写的三行；加表情按钮时**没有复制粘贴**，
	#   改成"不在枚举基里的可见按钮"共用一份公式（§111 同一公式只许一处）。
	#   表情按钮已退役（表情搬进左抽屉），数组里只剩邀请按钮 —— 结构留着，
	#   下一个这类按钮只需往这个数组里追加。
	for extra in [_invite_btn]:
		if extra == null or not is_instance_valid(extra):
			continue
		var eb: Button = extra
		eb.custom_minimum_size = Vector2(0.0, min_h)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if fnt > 0:
			eb.add_theme_font_size_override("font_size", fnt)
		else:
			eb.remove_theme_font_size_override("font_size")
	_hud_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if portrait \
		else HORIZONTAL_ALIGNMENT_LEFT
	# ★ 自动换行：这两行现在住在**宽 172 的抽屉**里（不再横跨整屏）。不换行的话
	#   「对手已认输，你赢了」这类长文案会把 `_hud_box` 的 min 宽撑到 172 以上 ⇒
	#   文字溢出抽屉右沿、压到棋盘上（而且不报错）。换行后 min 宽退化成 1 个字宽。
	_hud_turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_turn_label.add_theme_font_size_override("font_size",
		GameConfig.hud_label_font_size(15))
	# ★★ 2026-10-16 补（用户口令「对局中的『轮到你』文字颜色**没有配合主题**」）：
	#   本行上方原先是**只有字号**的 —— 字色一直吃**引擎默认主题**（近白 0.875）：
	#     深色主题下碰巧可读，**浅色主题下就是近白字压在浅色页面上**（对比度 ~1.0 = 等于没字），
	#     而它**没有任何报错**，也没有任何判据看得见（判据只查 HUD 的几何与高度）。
	#   ★ 真源 = `GameConfig.readable_ink_on(参照面)` —— "在这块面上写字该用什么色"
	#     全工程只有这一个答案，这里另写一份就是老坑。
	# ★★ 2026-10-21 改参照面：**页面底色 → 抽屉底色**。这一簇控件已经搬进右抽屉，
	#   它现在浮在**深色面板**上而不是页面底上 —— 沿用页面底挑出来的是深棕字，
	#   压在深棕面板上（截图实测对比度 ~1.0，等于整行没字）。同一天在身份槽上踩的是同一个坑。
	#   ⚠️ `judge_hud_text_theme()` 的参照面必须同步改成 `_drawer_surface()`，
	#     否则判据会拿"字的色 vs 一块字根本不画在上面的面"算对比度 —— 绿得毫无意义（§110）。
	#   ⚠️ 放在 `_refit_hud()` 里（而不是 `_build_game_hud()` 里设一次）：本函数是
	#     "HUD 外观的唯一一处"（字号 / 按钮高 / 横竖摆法都在这儿）⇒ 转屏、重建、
	#     以及将来任何"重排之后"的路径都会跟着重设，不会漏。
	_hud_turn_label.add_theme_color_override("font_color",
		GameConfig.readable_ink_on(_drawer_surface()))
	# 棋钟行与回合提示**同面同尺**：它俩在同一个 VBox、浮在同一块面（抽屉底）上，
	# 字色各写一份的话，将来改主题只改一处 ⇒ 另一半又变成"深字压深底"（等于没字）。
	if _hud_clock_label != null and is_instance_valid(_hud_clock_label):
		_hud_clock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hud_clock_label.add_theme_font_size_override("font_size",
			GameConfig.hud_label_font_size(15))
		_hud_clock_label.horizontal_alignment = _hud_turn_label.horizontal_alignment
		_hud_clock_label.add_theme_color_override("font_color",
			GameConfig.readable_ink_on(_drawer_surface()))
	# ★★ 2026-10-21 改：原来这里有"竖屏底部通栏 / 横屏右下角一簇"两套摆法
	#   （其中横屏那套还带着 `hud_landscape_right` 当偏移用、把整簇顶到屏幕边的老 bug）。
	#   现在**只有一套**：`_hud_box` 固定在右抽屉的内容矩形里，位置与宽度都由
	#   `drawer_content_rect(1)` 给。竖/横的差别只剩"按钮高"与"文字对齐"两条（上面几行）。
	#   ⇒ 两套摆法合成一套，正好消灭了那个"预算当偏移"的老坑（它是被删掉，不是被修好）。
	_refit_drawers()
	# ⚰️ 2026-10-22 墓碑：这里原有 `_refit_emote_bubbles()`（把两个飘在棋盘中央的气泡摆到
	#   盘的中线）。表情改成画在身份槽头像圆里之后**不需要摆位** —— 位置由槽自己决定，
	#   而槽已经在 `_refit_drawers()` 里排过。

## 人读摘要（给自检打印用）。★ 报的是**按钮自己的全局矩形**，不是包裹它们的容器 ——
## 容器对不对不代表按钮对不对（夹到 0 高、被容器压扁都能让容器看着正常）。
func hud_layout_verdict() -> String:
	if _hud_box == null or not is_instance_valid(_hud_box):
		return "HUD 未建"
	var vs := get_viewport_rect().size
	var parts: Array[String] = []
	for b in _hud_buttons:
		if is_instance_valid(b):
			parts.append("%s h=%.0f y=%.0f" % [b.text, b.size.y, b.global_position.y])
	return "竖=%s 视口=(%d,%d) 按钮下限=%.0f | %s" % [
		"是" if GameConfig.use_portrait_canvas() else "否",
		int(vs.x), int(vs.y), GameConfig.hud_button_min_height(), ", ".join(parts)]

## 判据（自检用）：所有 HUD 按钮必须①完整落在视口内 ②高度 ≥ 触摸目标下限
## ③（**可选**，`want_gap` ≥ 0 时才查）离屏幕四边的最小留白 ≥ `want_gap`。
## 返回 [bool, 人读摘要]。**阴性对照**由调用方做（把下限调 0 后同一条判据必须报警），
## 否则"永远绿"的判据等于没有判据。
##
## ★★ 第 ③ 项为什么必须存在（2026-10-16 用户口令「对局中按钮接近屏幕边缘，修一下」）：
##   ①② 只问"在不在屏内" —— 而病灶是**紧贴屏幕边**（横屏实测右沿只剩 **5px**：因为宽度
##   预算 320 被当成了"距右"用，行宽 315 ⇒ 320−315=5）⇒ 5px 与 200px 在 ①② 眼里一模一样
##   （⑤b 只在"真的出屏"时才红）。**"没出屏但紧贴"这一类只能由留白下限咬住。**
##   ⚠️ 它是**可选**项（默认 −1 = 不查）而不是"永远查"：竖屏那一档的留白是**结构性**给的
##     （`size.x = vs.x - 2m` + `position.x = m`，左右下三边恒等于 m），而横屏那一档才是
##     "被算错的"（原实现拿预算当偏移）⇒ 两个档的射程不同，判据项也分开（铁律 §11：
##     一条判据一件事）——⑤ 走竖屏档（不传 want_gap）、⑤c 走横屏档（传 want_gap）。
##
## ★ `want_h` 必须由调用方显式传入（自检传 `GameConfig.HUD_TOUCH_MIN_PORTRAIT` 这个**字面常量**），
##   不能默认从 `GameConfig.hud_button_min_height()` 取 —— 那个值由 `use_portrait_canvas()` 派生，
##   而阴性对照要翻的正是那个谓词：一翻期望值就跟着变 0，高度判据被自己关掉（空判据恒真）。
##   传 −1 才表示"按当前谓词取值"，仅供 `[shot]` 打印用。
##   ★ `want_gap` 同理传**字面常量**（`GameConfig.HUD_EDGE_MARGIN_LANDSCAPE`）：
##     ⑤d 的阴性对照改的是**被测物** `hud_landscape_margin`（变量），期望值全程不动。
func judge_hud_layout(want_h: float = -1.0, want_gap: float = -1.0) -> Array:
	if _hud_box == null or not is_instance_valid(_hud_box):
		return [false, "HUD 未建"]
	var vs := get_viewport_rect().size
	var expect_h: float = want_h if want_h >= 0.0 else GameConfig.hud_button_min_height()
	var bad: Array[String] = []
	var heights: Array[String] = []
	var gap_min: float = -1.0
	var gap_who: String = ""
	for b in _hud_buttons:
		if not is_instance_valid(b):
			continue
		var r: Rect2 = b.get_global_rect()
		heights.append("%.0f" % b.size.y)
		if r.position.x < -0.5 or r.position.y < -0.5 \
			or r.end.x > vs.x + 0.5 or r.end.y > vs.y + 0.5:
			bad.append("%s 出屏 %s" % [b.text, str(r)])
		# ★ 四边都量、取最小（"离屏幕边最近的那一条边"才是眼睛看到的紧贴程度）
		var g: float = minf(minf(r.position.x, r.position.y),
			minf(vs.x - r.end.x, vs.y - r.end.y))
		if gap_min < 0.0 or g < gap_min:
			gap_min = g
			gap_who = b.text
		# ★ 两个都查：`custom_minimum_size` 是**同步**可读的（我们刚写进去的），
		#   而 `size` 要等容器重排才更新。只查 `size` 的话，阴性对照（切回横屏、
		#   下限归 0）会因为"按钮还保持着上一次的 76 高"而**测不出来** —— 假绿。
		if b.custom_minimum_size.y < expect_h - 0.5 or b.size.y < expect_h - 0.5:
			bad.append("%s 高 下限%.0f/实测%.0f < 期望%.0f" % [
				b.text, b.custom_minimum_size.y, b.size.y, expect_h])
	if want_gap >= 0.0 and gap_min < want_gap - 0.5:
		bad.append("离屏幕边最近 %.1f < 期望 %.1f（%s 那一侧）" % [gap_min, want_gap, gap_who])
	var ok: bool = bad.is_empty()
	var msg: String = "按钮高 [%s] 期望下限 %.0f（谓词给出 %.0f）｜离屏幕边最近 %.1f（%s）视口 (%d,%d)" % [
		", ".join(heights), expect_h, GameConfig.hud_button_min_height(),
		gap_min, gap_who, int(vs.x), int(vs.y)]
	if not ok:
		msg += " → " + "; ".join(bad)
	return [ok, msg]

## 判据（自检用）：**侧抽屉与棋盘不重叠** —— 本轮"严防重叠"的牙齿（2026-10-21）。
## 返回 [bool, 人读摘要]。四项，各量一件事（§11 一条判据一件事，红点直接指方向）：
##   ① 展开态的抽屉面板与棋盘**不相交**；
##   ② 把手与棋盘**不相交**（折叠态下把手是唯一还在屏幕侧边上的东西）；
##   ③ 棋盘（含盘的外扩 `board_panel_pad`）完整落在 `board_area()` 里；
##   ④ 面板与把手完整落在视口内（不能为了"不压盘"把面板推到屏幕外）。
##
## ★★ 为什么必须量**真实矩形**而不是量 `board_area()` 的算术：
##   算术是"我算的"，面板的实际尺寸是"画出来的"。两者一旦分家（`PanelContainer` 被内容撑宽、
##   某个主题的内边距更大、字号变了），只有前者会继续报绿 —— 而用户看到的是重叠。
##   ⇒ 面板侧一律读 `get_global_rect()`（真节点），棋盘侧读 `_board_bbox()`（真顶点）。
## ★ 棋盘侧要**加上盘的外扩**：`_board_bbox()` 只是顶点盒，而实际画出来的是 `BoardPanel`。
##   用顶点盒当"棋盘"会漏掉最外圈 13px —— 而 `board_area()` 的边距里算的正是 `board_panel_pad`，
##   两者不同源的话，判据会比真实情形宽松 13px（"判据绿、眼睛看见压上去了"）。
func judge_drawer_layout() -> Array:
	var bb: Rect2 = _board_bbox()
	if board_panel_enabled:
		bb = bb.grow(board_panel_pad)
	var vs := get_viewport_rect().size
	var view := Rect2(Vector2.ZERO, vs)
	var bad: Array[String] = []
	var who := ["左", "右"]
	# ① 面板
	for side in [0, 1]:
		if not _drawer_shows(side):
			continue
		var r: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
		if _drawer_expanded(side):
			r = _drawer_rect(side)
		else:
			# 浮层态：面板贴在屏幕边，本来就盖在盘上（用户主动拉开的）⇒ 这一项跳过，
			# 但 ④ 的"不出视口"照样查它。
			continue
		if r.intersects(bb):
			bad.append("%s面板 %s 压住棋盘 %s" % [who[side], str(r), str(bb)])
	# ② 把手
	for side in [0, 1]:
		if not _drawer_available(side):
			continue
		var hr := _drawer_handle_rect(side)
		if hr.size.x > 0.0 and hr.intersects(bb):
			bad.append("%s把手 %s 压住棋盘 %s" % [who[side], str(hr), str(bb)])
	# ③ 棋盘在可用区内
	# ★ 容差要把 `board_panel_pad` 补回来：`board_area()` 的边距里已经算进了 pad
	#   （见 `_adapt_to_screen()` 那段注释：盘距窗口恒为 `board_margin()`，与 pad 无关），
	#   而这里的 `bb` 是"顶点盒 + pad" ⇒ 它比 `board_area()` 每边多出 pad 是**设计如此**。
	#   ⚠️ 第一版写成 `area.grow(1)` 直接比，结果恒红 —— 那不是重叠，是判据把 pad 忘了。
	var pad_extra: float = board_panel_pad if board_panel_enabled else 0.0
	var area := board_area()
	if not area.grow(pad_extra + 1.0).encloses(bb):
		bad.append("棋盘 %s 越出可用区 %s（容许 pad %.0f）" % [str(bb), str(area), pad_extra])
	# ④ 面板 / 把手在视口内
	for side in [0, 1]:
		if not _drawer_available(side):
			continue
		var hr2 := _drawer_handle_rect(side)
		if hr2.size.x > 0.0 and not view.grow(0.5).encloses(hr2):
			bad.append("%s把手 %s 出视口" % [who[side], str(hr2)])
		if not _drawer_shows(side):
			continue
		var pr := _drawer_rect(side)
		if not view.grow(0.5).encloses(pr):
			bad.append("%s面板 %s 出视口" % [who[side], str(pr)])
	var ok: bool = bad.is_empty()
	var msg := "棋盘 %s ｜ 可用区 %s ｜ 带宽 %s ｜ 视口 (%d,%d)%s" % [
		str(bb), str(area), str(drawer_bands()), int(vs.x), int(vs.y),
		"" if ok else " → " + "; ".join(bad)]
	return [ok, msg]

## 判据（自检用）：对局 HUD 的**回合提示文字**必须①**真的套过**主题字色（不是吃引擎默认）
## ②在它所在的那块面上**可读**（对比度 ≥ 按钮文字同一把尺子）。
## 返回 [bool, 人读摘要]。**阴性对照**由调用方做（把 override 清掉后同一条判据必须报警）。
##
## ★★ 为什么必须**两条一起**（2026-10-16 用户报的真 bug：「对局中的『轮到你』文字颜色没有
##   配合主题」）：`_hud_turn_label` 原先**只设字号**、字色吃引擎默认（近白 0.875）——
##   深色主题下碰巧可读，**浅色主题下就是近白字压在浅色页面底上**（对比度 ~1.3 = 基本没字）。
##   · ① `has_theme_color_override` 守的是"**我们接线了**"。⚠️ 只查对比度**不够**：
##     引擎默认那个近白在**深色主题下恰好是达标的** ⇒ 光看对比度，"压根没接线"这个真缺陷
##     在深色主题下照样绿（而用户装的正是浅色主题 ⇒ 只在别人机器上现形，本工程刚为字体
##     那件事付过一次同款的账）。
##   · ② 对比度守的是"接上去的那个值**真的可读**"（阈值取 `BTN_TEXT_MIN_CONTRAST`，
##     与 `readable_ink_on()` 内部同源 —— 判据不许自己另定一个阈值）。
##   ★ 面取 `_drawer_surface()`（抽屉面板底）：这一簇控件挂在 `_hud_box` 里，
##     而 `_hud_box` 现在**摆在右抽屉面板上**（见 `_refit_drawers()`）⇒ 它浮的就是**面板底**。
##     ⚠️ 2026-10-21 之前这里取 `page_surface()`：那时 HUD 没有底板、直接浮在页面底上，
##     口径是对的；搬进抽屉后不跟着改，判据就会拿"深棕字 vs 米白页面底"算出一个漂亮的
##     6.40 分 —— 而字实际画在深棕面板上，对比度 ~1.0。**参照物与被测物的落点必须是同一个地方。**
##   ⚠️ 只覆盖 `_hud_turn_label`，**不含** `_ai_hud_label`（「AI 思考中…」）：那一个刻意用
##     "近白 + 6px 黑描边"做**背景无关**的可读性（它浮在棋盘上，底色不是面板底而是盘面），
##     改用主题墨色反而会在某些主题下与盘面撞色。它是**有意的例外**，不是漏接线。
func judge_hud_text_theme() -> Array:
	if _hud_turn_label == null or not is_instance_valid(_hud_turn_label):
		return [false, "HUD 回合提示未建"]
	var surface: Color = _drawer_surface()
	var has: bool = _hud_turn_label.has_theme_color_override("font_color")
	var ink: Color = _hud_turn_label.get_theme_color("font_color")
	var cr: float = GameConfig.contrast_of(ink, surface)
	var bad: Array[String] = []
	if not has:
		bad.append("字色没有 override（吃引擎默认 %s）" % str(ink))
	if cr < GameConfig.BTN_TEXT_MIN_CONTRAST:
		bad.append("字色对页面底 %.2f < 阈值 %.2f" % [cr, GameConfig.BTN_TEXT_MIN_CONTRAST])
	return [bad.is_empty(), "字色 %s（override=%s）对页面底 %s 对比度 %.2f 异常 %s" % [
		str(ink), "是" if has else "否", str(surface), cr, str(bad)]]


func _update_hud() -> void:
	# ★★ 棋钟行必须在**所有分支之前**（理由同下面那行悔棋按钮）：`_update_hud()` 在
	#   ONLINE 分支与"菜单阶段"分支都会 `return` —— 放到分支后面的话，那两档永远不刷新
	#   （联机虽说不走钟，但"棋钟关闭"这一态也写不出去，会留着上一局的读数）。
	_update_clock_hud()
	# 邀请好友按钮同理（2026-10-21）：可见性必须**在所有 return 之前**派生 ——
	# 下面 ONLINE 分支有多个 return，塞进分支里就会漏掉某些态（典型"看起来没接线"）。
	_refresh_invite_btn()
	# 身份条 + 表情按钮同理（2026-10-21）：**联机专属**，可见性同样必须在所有 return 之前派。
	_refresh_net_extras()
	# ★ 悔棋按钮先刷（**在所有分支之前**）：下面 ONLINE 分支会 `return`，
	#   放到分支后面的话联机模式下这个按钮就永远不刷新（典型"看起来没接线"）。
	#   文案与可用性都从 `can_undo()` 派生（铁律 7）：只改文案不改谓词 = "能点但点了没反应"。
	if _undo_btn != null and is_instance_valid(_undo_btn):
		if _undo_pending_from >= 0:
			_undo_btn.text = "等待对方…" if _undo_pending_from == _net_color else "对方请求悔棋"
			_undo_btn.disabled = true
		elif game_mode == ONLINE and undo_used(_net_color) >= UNDO_LIMIT_ONLINE:
			_undo_btn.text = "悔棋(%d/%d)" % [UNDO_LIMIT_ONLINE, UNDO_LIMIT_ONLINE]
			_undo_btn.disabled = true
		elif game_mode == ONLINE and undo_used(_net_color) > 0:
			_undo_btn.text = "悔棋(%d/%d)" % [undo_used(_net_color), UNDO_LIMIT_ONLINE]
			_undo_btn.disabled = not can_undo()
		else:
			_undo_btn.text = "悔棋"
			_undo_btn.disabled = not can_undo()
	if not _hud_turn_label:
		return
	# ★ 覆盖层优先：非空时**直接显示它并返回**，不被下面的 ONLINE / 轮换文案刷掉。
	#   （`_start_ai_turn()` 会无条件 `_update_hud()`，若不在这里拦住，"加载失败"提示活不过一帧。）
	if _hud_override != "":
		_hud_turn_label.text = _hud_override
		return
	if game_mode == ONLINE:
		if not _net_connected:
			if _is_host and GameConfig.invite_code != "":
				_hud_turn_label.text = "连接中… 邀请码：%s（发给好友）" % GameConfig.invite_code
			else:
				_hud_turn_label.text = "连接中…"
		elif game_over:
			_hud_turn_label.text = "对局结束"
		elif _net_phase == "ready":
			_hud_turn_label.text = "等待双方点击「准备」…"
		else:
			var me := "黑" if _net_color == Stone.BLACK else "白"
			var turn := "你" if current_player == _net_color else "对方"
			var code_prefix := ""
			if _is_host and GameConfig.invite_code != "":
				code_prefix = "房间码：%s\n" % GameConfig.invite_code
			_hud_turn_label.text = code_prefix + "联机 · 你执%s · 轮到%s" % [me, turn]
		return
	if game_mode < 0:
		# 主菜单阶段：隐藏对局内 HUD
		if _hud_layer:
			_hud_layer.visible = false
		return
	if _hud_layer:
		_hud_layer.visible = true
	if game_over:
		_hud_turn_label.text = "对局结束"
	elif is_ai_thinking:
		_hud_turn_label.text = "白棋（AI）思考中…"
	elif game_mode == VS_AI:
		_hud_turn_label.text = "轮到你 —— 执黑"
	else:
		_hud_turn_label.text = "轮到" + ("黑方" if current_player == Stone.BLACK else "白方")


# ====== 邀请好友（2026-10-21）======
## 「邀请好友」按钮的**唯一**可见性 / 可用性派生点。
##
## ★★ 三个条件缺一不可（`game_mode == ONLINE` / `_is_host` / `invite_code != ""`）：
##   邀请窗口是**按 lobby_id 弹的**，房间号还没回来时弹出来邀请不到这个房
##   （Steam 那边不报错，好友接受后也进不来）⇒ 没房间号就干脆不显示，而不是显示了再失败。
##   `_is_host` 那一半：加入方没有"自己的房间"可邀请，显示出来是误导。
##
## ★ 可点性走 `SteamNet.invite_capability()`（覆盖层是否启用 / 方法是否存在都问它）——
##   不在这里另写一份判断（那种"能点但点了没反应"正是本条要消灭的东西）。
func _refresh_invite_btn() -> void:
	if _invite_btn == null or not is_instance_valid(_invite_btn):
		return
	var show: bool = game_mode == ONLINE and _is_host and GameConfig.invite_code != ""
	_invite_btn.visible = show
	if not show:
		return
	var cap: Dictionary = SteamNet.invite_capability()
	var can: bool = bool(cap.get("ok", false))
	_invite_btn.disabled = not can
	# 能点 ⇒ 提示"覆盖层可能没启用"这类**警告**；不能点 ⇒ 提示**拒绝理由**。
	# 两者都写进 tooltip，点不了时玩家能自己查（不留"灰按钮，无解释"）。
	_invite_btn.tooltip_text = str(cap.get("warn", "")) if can else str(cap.get("reason", ""))


# ====== 侧抽屉：左 = 玩家信息 + 表情 / 右 = 对局按键（2026-10-21 第二轮）======
## 用户原话：「严防重叠，把对局棋盘左右空白做成抽屉，左边放玩家信息及表情等，
## 右边放对局按键，还能折叠收回屏幕侧边」。几何真源见 `board_area()` 那一节。
##
## ★★ 第一版（同日早些时候）是"贴四角浮在盘上"（左上自己、右上对端）+ 一个弹出式表情面板。
##   那条路能跑纯属**巧合**：密铺盘的四角本来就是空的，所以 196×56 的小槽浮上去不打架。
##   可它不是**结构**上的保证 —— 窗口一窄、换一张盘、HUD 多一个按钮，浮层就会压到盘上，
##   而且**不会报错**（判据只看"控件在不在屏内"，看不见"压在盘上"）。
##   本版把"不重叠"做成结构：两侧抽屉的宽度由 `board_area()` 从棋盘那里扣掉。
##
## ★ 面板用 **`Panel` 而不是 `PanelContainer`**：`PanelContainer` 的尺寸取
##   「样式内边距 + 内容的 combined_min_size」，内容一旦比预算宽（换个主题、字号变大、
##   多加一个表情格），面板就会**自己变宽**并压到棋盘上，而 `_drawer_band()` 算的还是老宽度。
##   `Panel` 只画底、尺寸完全由 `_refit_drawers()` 写入 ⇒ 面板宽度与让出的宽度**恒等**。
##   内容（身份槽 + 表情格）是它下面的自由 `VBoxContainer`，位置由同一个内容矩形给。
##
## ★ 只用 `Control` + `draw` 自绘身份槽，不用 Label / TextureRect：
##   ① 头像要做圆形遮罩、名字要按可用宽度省略号截断 —— `Label` 的 `text_overrun_behavior`
##      是另一套口径，凑起来还不如一次画完；
##   ② **不吃主题遍历**：`--menutest` ⑯ 那套明度扫描走的是控件树，自绘控件天然不在其中
##      ⇒ 加这一层不会给 ⑯ 引入新的"异常处"（§126 那次踩过的坑）。
func _build_drawers() -> void:
	if _drawer_layer != null and is_instance_valid(_drawer_layer):
		return
	# 右抽屉挂在 `_hud_layer` 上 ⇒ 它没建好就整批不建（建一半会留下"只有左抽屉"的中间态，
	# 而 `_drawer_layer != null` 会让下一次调用以为已经建完了）。
	if _hud_layer == null or not is_instance_valid(_hud_layer):
		return
	# ---- 左抽屉（联机身份 + 表情）：独立一层 ----
	# ★ 它单独一层是**必须**的：可见性由"联机态"（`_refresh_net_extras()`）决定，
	#   而 `_hud_layer.visible` 已经有三处写点（联机未连 / 复盘 / 面板互斥）——
	#   混进同一层就会出现"复盘时左抽屉跟着消失"或"返回菜单后它还留着"这类静默错。
	_drawer_layer = GameConfig.new_themed_layer()
	_drawer_layer.name = "DrawerLeftLayer"
	_drawer_layer.layer = 24
	_drawer_layer.visible = false     # 默认藏：只有 `_refresh_net_extras()` 在联机态打开
	add_child(_drawer_layer)
	_drawer_left_panel = Panel.new()
	_drawer_left_panel.name = "DrawerLeft"
	_drawer_left_panel.add_theme_stylebox_override("panel", _drawer_stylebox())
	# ⚰️ 2026-10-22 墓碑：这里原有三行"先把抽屉底色缓存定下来再建内容"。
	#   `_drawer_surface()` 改成纯函数之后顺序问题**从结构上消失**（谁先问都能算对），
	#   那三行连同 `_drawer_surface_cache` 一起删除。
	# ★ STOP：抽屉盖住的那块不许穿透到棋盘（浮层态下它就压在盘上，
	#   穿透的后果是"点表情点出一手棋"——很难查，因为两者都会正常响应）。
	_drawer_left_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer_layer.add_child(_drawer_left_panel)
	_drawer_left_body = VBoxContainer.new()
	_drawer_left_body.name = "DrawerLeftBody"
	_drawer_left_body.add_theme_constant_override("separation", 10)
	_drawer_left_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_left_panel.add_child(_drawer_left_body)
	_net_id_self = _make_identity_slot(0)
	_net_id_peer = _make_identity_slot(1)
	_emote_grid = GridContainer.new()
	_emote_grid.name = "EmoteGrid"
	_emote_grid.columns = EMOTE_PANEL_COLS
	_emote_grid.add_theme_constant_override("h_separation", EMOTE_CELL_GAP)
	_emote_grid.add_theme_constant_override("v_separation", EMOTE_CELL_GAP)
	_emote_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_left_body.add_child(_emote_grid)
	for i in range(Emotes.count()):
		_emote_grid.add_child(_make_emote_cell(i))
	_drawer_left_handle = _make_drawer_handle(0)
	_drawer_layer.add_child(_drawer_left_handle)
	# ---- 右抽屉（对局按键）：挂在 `_hud_layer` 上 ----
	# ★★ 必须是 `_hud_layer` 的子节点（而不是另建一层）：`_hud_layer.visible` 已经有三个
	#   写点（联机未连 / 复盘进出 / 面板互斥），另建一层的话"隐藏 HUD"会退化成
	#   "只藏按钮、留一块空面板"，而且**没有任何判据看得见**。
	# ★ 加在最前面再 `move_child(0)`：CanvasItem 按树序绘制，面板必须在 `_hud_box` **之下**
	#   （`_hud_box` 没有底板，被面板盖住就等于整簇按钮消失）。
	_drawer_right_panel = Panel.new()
	_drawer_right_panel.name = "DrawerRight"
	_drawer_right_panel.add_theme_stylebox_override("panel", _drawer_stylebox())
	_drawer_right_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud_layer.add_child(_drawer_right_panel)
	_hud_layer.move_child(_drawer_right_panel, 0)
	_drawer_right_handle = _make_drawer_handle(1)
	_hud_layer.add_child(_drawer_right_handle)
	_refit_drawers()
	# ⚰️ 2026-10-22 墓碑：这里原有 `_build_emote_bubbles()`（建两个 132px 棋盘气泡面板）。
	#   表情改画进身份槽之后不再有独立节点可建。


## 抽屉底色：从 `_drawer_surface()`（唯一真源）取，**不再借用** `style_dialog_panel()`。
## ★ 为什么不用 `PanelContainer` 直接吃它：见本节开头的注释（内容会把面板撑宽）。
## ★ 描边必须留：底色与页面只差一档明度，没有这条 1px 淡边就分不清面板在哪
##   （描边色用**抽屉面上的**墨色 13%，不是页面面上的 —— 参照面要跟被测面走，§130）。
## ★ 不用 `shadow_*`：§128 那次退出崩溃的教训针对的是自绘抗锯齿图元，阴影是引擎画的、
##   理论上无关，但这一档没必要冒风险 —— 描边已经够用。
func _drawer_stylebox() -> StyleBox:
	var surf: Color = _drawer_surface()
	var ink: Color = GameConfig.readable_ink_on(surf)
	var sb := StyleBoxFlat.new()
	sb.bg_color = surf
	sb.border_color = Color(ink.r, ink.g, ink.b, 0.13)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	# 内容边距全 0：子节点位置/尺寸由 `_refit_drawers()` + `drawer_content_rect()` 手动写，
	# 面板不吃内容边距 —— 留一份在这里就和 `DRAWER_PAD` 变成两个真源（§111）。
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


## 抽屉面板**实际的**底色 —— 唯一真源。`_drawer_stylebox()` 的 `bg_color` 就是它。
##
## ## ★★ 2026-10-22 改（用户口令「抽屉也用和背景较接近的颜色（同深浅）」）
## 上一版直接吃 `style_dialog_panel()` ⇒ 底色等于 `overlay_surface()`，而那是给**弹窗**
## 定制的"恒深色面板"（明度 ≤ `PANEL_LUM_MAX` = 0.16，见那段长论证）—— 两块深色砖压在
## 浅色页面上，用户一眼就嫌它跳。
## 现在 = `页面底.lerp(ink, DRAWER_SURFACE_MIX)`：
##   · 明度只挪 7% ⇒ 观感是"同一块面上的浅浮雕"，不是浮窗；
##   · 方向**朝 ink** ⇒ 无论页面底是浅是深，抽屉都只会比页面更"实"一点，画在上面的字
##     对比度只可能更高（这是选方向时的唯一判据，不是审美）。
##
## ## ★ 为什么**不缓存**了（原来有个 `_drawer_surface_cache`）
## 那个缓存是"建抽屉那一刻从 StyleBox 里取一份快照"。它带来两个毛病：
##   ① 主题一变（哪怕只是菜单里换完再进对局以外的情况）它就永远是上一个主题的底色，
##      而**字色参照面也是它** ⇒ 底色和字色一起停在旧主题，且没有任何判据看得见；
##   ② 真源方向反了：底色本来是"从页面底推出来的纯函数"，却要靠一份快照去和 StyleBox 对齐。
## 现在反过来 —— `_drawer_stylebox()` 从这里取值 ⇒ 一处写、一处读、永远跟主题同步。
func _drawer_surface() -> Color:
	var page: Color = GameConfig.page_surface()
	return page.lerp(GameConfig.readable_ink_on(page), DRAWER_SURFACE_MIX)


## 折叠把手：贴在抽屉内侧（展开）或屏幕边（折叠）的一条窄键。
## ★ 样式**自己拼**、不用 `style_theme_button()`：那条路径会带上 16/9 的内边距，
##   而把手只有 18px 宽 —— 内边距一加，最小宽度就超过 `DRAWER_HANDLE_W`，
##   `_drawer_band()` 算的让位宽度就不够了（症状：把手压在棋盘边缘格子上）。
## ★ 文字用 ASCII 的 `<` / `>`，不用 `◀` / `▶`：本工程的 UI 字体是中文正文字体，
##   几何形状字符（U+25C0/U+25B6）不一定有，缺字时画出来是豆腐块且**不报错**。
##   （同族先例：复盘 HUD 的窄屏短符号用的是 `|<` `<<` `>` `>>` `>|`。）
func _make_drawer_handle(side: int) -> Button:
	var b := Button.new()
	b.name = "DrawerHandle%d" % side
	b.text = "<" if side == 0 else ">"
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 15)
	var page := GameConfig.page_surface()
	var ink := GameConfig.readable_ink_on(page)
	var accent := GameConfig.accent_color()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ink.r, ink.g, ink.b, 0.16 if st == "normal" else 0.26)
		sb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		# 四边内容边距全 0：宽度由 `custom_minimum_size` 说了算（见上面那段注释）。
		sb.content_margin_left = 0.0
		sb.content_margin_right = 0.0
		sb.content_margin_top = 0.0
		sb.content_margin_bottom = 0.0
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_focus_color", ink)
	b.custom_minimum_size = Vector2(DRAWER_HANDLE_W, DRAWER_HANDLE_H)
	b.pressed.connect(_on_drawer_handle_pressed.bind(side))
	return b


## 一个表情格：按钮（外观 + 点击）+ **子 Control**（自绘）。
## ★ 自绘挂在子 Control 上、**绝不**挂 Button 自己的 `draw`：见下面那段 2026-10-21 的实测。
func _make_emote_cell(idx: int) -> Button:
	var b := Button.new()
	b.name = "EmoteCell%d" % idx
	b.text = ""            # 表情全靠子节点自绘，按钮只提供外观与点击
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(EMOTE_CELL, EMOTE_CELL)
	b.tooltip_text = Emotes.name_of(idx)
	# 抽屉底 = `overlay_surface()`（`style_dialog_panel()` 用的就是它）⇒ 按钮配色必须按
	# **同一块面**反推，否则浅色主题下会出现"按页面底色挑的字色画在面板底色上"（§110）。
	GameConfig.style_theme_button(b, _emote_panel_surface())
	b.pressed.connect(_on_emote_pick.bind(idx))
	# ★★ 自绘挂在**子 Control** 上，**绝不**挂在 Button 自己的 `draw` 信号上。
	#   2026-10-21 实测（`_emote_stability.py`，6 轮对照）：
	#     · 挂在 Button 自己身上 ⇒ 退出时 **2/6 概率 0xC0000005 访问违规**
	#       （截图已落盘、stdout 完整，崩在 `quit()` 之后的清理阶段）；
	#     · 挂到子 Control（本写法）/ 干脆不画 ⇒ **6/6 全部干净退出**。
	#   区别在于 Button 自己也要发绘制命令（StyleBox + 文字），引擎会把两者的
	#   渲染命令混在同一条 canvas item 序列里清 —— 而普通 Control 只有我们这一份。
	#   ⚠️ 这类崩溃**只在退出时发作**，任何"看日志有没有 ERROR"的判据都抓不到，
	#      只有"连跑 N 次统计退出码"能看见（§17 重复优于单次印象）。
	var paint := Control.new()
	paint.name = "CellPaint"
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	paint.draw.connect(_draw_emote_cell.bind(paint, idx))
	b.add_child(paint)
	return b


func _make_identity_slot(slot: int) -> Control:
	var c := Control.new()
	c.name = "IdSlot%d" % slot
	c.custom_minimum_size = Vector2(NET_ID_SLOT_W, NET_ID_SLOT_H)
	c.size = Vector2(NET_ID_SLOT_W, NET_ID_SLOT_H)
	# ★ 左侧这条边两侧都不需要吃事件：抽屉面板自己是 STOP，槽位再 STOP 只会把
	#   "面板收到的点击"截在中间（表情格在它下面，不受影响）。
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(_draw_identity_slot.bind(c, slot))
	_drawer_left_body.add_child(c)
	return c


## 摆抽屉：面板 / 内容 / 把手三者的矩形全部来自几何真源（`_drawer_rect()` /
## `drawer_content_rect()` / `_drawer_handle_rect()`），本函数**只负责写进去**。
## ★ 由 `_refit_hud()` 调（它已经连着 `viewport.size_changed`）—— 不另连一个信号：
##   两处各自连 `size_changed` 会在同一帧里各排一次，而且迟早有一处忘记解绑。
func _refit_drawers() -> void:
	# ★★ 第一件事：**按当前几何重算棋盘**。
	#   抽屉带宽会因三件事变化 —— 视口尺寸 / 用户开合 / `game_mode` 变联机，而棋盘必须
	#   跟着重算，否则"先缩好盘、后来才出现左抽屉"就会直接压上去。
	#   `_ready()` 的正常路径里 `game_mode` 是在缩放**之前**定的（没事），但运行期
	#   `_start_network()` 成功、`--shotemote` 这类入口都是在盘缩好**之后**才改成 ONLINE。
	#   实测症状（2026-10-21 截图）：盘的左沿在 155、抽屉占 32..232，**盖住 77px 的盘**，
	#   而且没有任何判据会红（棋盘几何本身没动过）。
	#   ⇒ 干脆把它变成**不变量**：任何一次重排都以"棋盘已经按当前 `board_area()` 缩过"为前提。
	#   `_adapt_to_screen()` 是自归一的（把当前包围盒重新塞进目标矩形），重复调用结果不变，
	#   所以放在这里不会抖、也不需要"变了才调"的探测器。
	if not vertices.is_empty():
		_adapt_to_screen()
	# ---- 左 ----
	if _drawer_left_panel != null and is_instance_valid(_drawer_left_panel):
		var lr := _drawer_rect(0)
		_drawer_left_panel.position = lr.position
		_drawer_left_panel.size = lr.size
		_drawer_left_panel.visible = _drawer_shows(0)
	if _drawer_left_handle != null and is_instance_valid(_drawer_left_handle):
		var lh := _drawer_handle_rect(0)
		_drawer_left_handle.position = lh.position
		_drawer_left_handle.size = lh.size
		_drawer_left_handle.visible = _drawer_available(0)
		_drawer_left_handle.text = "<" if _drawer_wants_open(0) else ">"
	# ---- 右 ----
	if _drawer_right_panel != null and is_instance_valid(_drawer_right_panel):
		var rr := _drawer_rect(1)
		_drawer_right_panel.position = rr.position
		_drawer_right_panel.size = rr.size
		_drawer_right_panel.visible = _drawer_shows(1)
	if _drawer_right_handle != null and is_instance_valid(_drawer_right_handle):
		var rh := _drawer_handle_rect(1)
		_drawer_right_handle.position = rh.position
		_drawer_right_handle.size = rh.size
		_drawer_right_handle.visible = _drawer_available(1)
		_drawer_right_handle.text = ">" if _drawer_wants_open(1) else "<"
	# ---- 左抽屉内容：位置由面板内的内容矩形给，尺寸由 `_refit_net_identity()` 给 ----
	if _drawer_left_body != null and is_instance_valid(_drawer_left_body):
		var cr := drawer_content_rect(0)
		_drawer_left_body.position = cr.position - _drawer_rect(0).position
		_drawer_left_body.size = cr.size
	_refit_net_identity()
	# ---- 右抽屉内容 = `_hud_box`：★ 手动摆（它就是 `_hud_layer` 下的自由 VBox） ----
	if _hud_box != null and is_instance_valid(_hud_box):
		# ★★ 2026-10-22 修（用户报「抽屉收起仍有按钮在」）：`_hud_box` **不是**
		#   `_drawer_right_panel` 的子节点（它是 `_hud_layer` 下的自由 VBox），所以面板一隐藏，
		#   那一簇按钮**留在原地**：没底板、浮在棋盘右边，看着像一片孤儿按钮。
		#   ⇒ 面板与内容必须**同生同灭**，"内容跟着抽屉走"这件事只在这一处派生。
		#   ⚠️ 这里用 `.visible`（我们写的那个量）而不是 `is_visible_in_tree()`：`_hud_layer`
		#     在复盘态会整体隐藏，用后者会让这一条在那些档下恒假（§131 的另一面）。
		_hud_box.visible = _drawer_shows(1)
		var cr2 := drawer_content_rect(1)
		# 高度取「容器算出来的 size.y」与「组合最小高」的较大者 —— 首帧 `size.y` 还可能是 0，
		# 只信它的话第一帧会把整簇按钮压在面板顶边上（看起来像闪了一下）。
		var hbox_h: float = maxf(_hud_box.size.y, _hud_box.get_combined_minimum_size().y)
		_hud_box.position = cr2.position
		_hud_box.size = Vector2(cr2.size.x, hbox_h)


## 身份槽只需**定尺寸**：位置由 `_drawer_left_body`（VBoxContainer）排。
## ★ 仍然要设 `size`：VBox 只管位置与宽度，高度取 `custom_minimum_size`，
##   而 `_draw_identity_slot()` 是按 `node.size` 画的 —— 不设就会画在 0 高的框里（空白）。
func _refit_net_identity() -> void:
	var sz := Vector2(NET_ID_SLOT_W, NET_ID_SLOT_H)
	for c in [_net_id_self, _net_id_peer]:
		if c != null and is_instance_valid(c):
			c.custom_minimum_size = sz
			c.size = sz


## 联机专属 UI（左抽屉：身份槽 + 表情）的**唯一**可见性派生点。
## ★ 必须是"唯一"：`game_mode` 的写点不止一处（开局 / 返回菜单 / 复盘退出），
##   而 `_update_hud()` 在所有写点之后都会被调用 ⇒ 可见性挂在这里就不会漏。
func _refresh_net_extras() -> void:
	var online: bool = game_mode == ONLINE
	if _drawer_layer == null or not is_instance_valid(_drawer_layer):
		return
	_drawer_layer.visible = online
	if not online:
		return
	_refit_drawers()
	_redraw_identity()


func _redraw_identity() -> void:
	for c in [_net_id_self, _net_id_peer]:
		if c != null and is_instance_valid(c):
			c.queue_redraw()


## 某一槽对应的 SteamID。0 = 拿不到（无 Steam / 还没连上）。
## ★ 对端 id 必须问传输层（`SteamTransport._peer` 就是对方的 SteamID64）——
##   不要去猜"房主=某个固定 id"，座位可选之后那条假设本来就不成立了。
func _steam_id_for(slot: int) -> int:
	if slot == 0:
		return SteamNet.my_id()
	if _chan is SteamTransport:
		return (_chan as SteamTransport).get_peer()
	return 0


func _color_for_slot(slot: int) -> int:
	if slot == 0:
		return _net_color
	return _opposite_stone(_net_color)


## 名字：Steam 昵称优先，取不到退回"你 / 对手"。
## ★ 退回值是**必须**有的：无 Steam（编辑器自检 / 单机调试）时 `persona_of()` 返回 ""，
##   直接拿去画就是两个空槽，看起来像"身份条坏了"。
func _display_name_for(slot: int) -> String:
	var sid := _steam_id_for(slot)
	if sid != 0:
		var p := SteamNet.persona_of(sid)
		if p != "":
			return p
	return "你" if slot == 0 else "对手"


func _identity_state_text(slot: int) -> String:
	var col := _color_for_slot(slot)
	var parts: Array[String] = ["执" + ("黑" if col == Stone.BLACK else "白")]
	if game_mode == ONLINE:
		if not _net_connected:
			parts.append("连接中")
		elif _net_phase == "ready":
			parts.append("已准备" if _ready_set.has(col) else "未准备")
		else:
			parts.append("对局中")
	return " · ".join(parts)


func _draw_identity_slot(node: Control, slot: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	_draw_ticks["identity"] = int(_draw_ticks.get("identity", 0)) + 1
	var r := Rect2(Vector2.ZERO, node.size)
	# ★★ 参照面 = **抽屉底色**（`_drawer_surface()`），不是 `page_surface()`。
	#   这一行是 2026-10-21 目检抓到的真 bug 的修复：抽屉底是深色，按页面底挑出来的
	#   深棕字压在深棕底上，量出来对比度 1.2（等于没字），而当时全部判据都是绿的。
	var page := _drawer_surface()
	var ink := GameConfig.readable_ink_on(page)
	var accent := GameConfig.accent_color()
	# 毛玻璃底：用 ink 的低 alpha 而不是"页面色的半透明版" ——
	# 后者等于把页面色再画一遍，深浅两档下都几乎看不见（等于没有底）。
	node.draw_rect(r, Color(ink.r, ink.g, ink.b, 0.08), true)
	node.draw_rect(r, Color(ink.r, ink.g, ink.b, 0.20), false, 1.0)
	# ★★ 两槽**都靠左**（头像在左、文字在右）。第一版是"贴四角"的摆法：自己那槽在左上、
	#   对端在右上，所以对端整条**镜像**过去。现在两槽在左抽屉里上下串成一列，镜像只会让人
	#   多读一遍方向 ⇒ 统一左对齐；区分"谁是谁"改由**头像圆环**承担（自己=主题强调色、
	#   对端=墨色淡环）。头像圆的几何走 `_avatar_rect_in_slot()` —— 判据也要量它（同一真源）。
	var av_rect: Rect2 = _avatar_rect_in_slot(r.size)
	var av_c: Vector2 = av_rect.get_center()
	var dia: float = av_rect.size.x
	# ---- 头像圆里画什么：说话中 → 表情；否则 → Steam 头像 / 首字占位 ----
	# ★★ 2026-10-22（用户口令「表情包不要遮挡棋盘」）：表情就画在这里。
	#   这块区域 ⊂ 身份槽 ⊂ 左抽屉内容区 ⊂ 抽屉面板，而抽屉面板与棋盘不相交
	#   （`--drawertest` ① 钉着）⇒ "表情压到盘上"结构上不可能，不是靠调坐标。
	var emote_a: float = emote_slot_alpha(slot)
	_last_emote_alpha[slot] = emote_a
	_last_emote_left[slot] = _emote_bubble_left[slot]
	if emote_a > 0.0 and Emotes.is_valid(_emote_bubble_idx[slot]):
		_draw_ticks["bubble"] = int(_draw_ticks.get("bubble", 0)) + 1
		# 表情半径取头像圆的 0.42（不是 0.5）：留一圈让下面的圆环仍然读得出"这是谁"。
		Emotes.draw_emote(node, _emote_bubble_idx[slot], av_c, dia * 0.42,
				Color(ink.r, ink.g, ink.b, emote_a),
				Color(accent.r, accent.g, accent.b, emote_a))
	else:
		var tex: Texture2D = _avatar_tex[slot]
		if tex != null and is_instance_valid(tex):
			node.draw_texture_rect(tex, Rect2(av_c - Vector2(dia, dia) * 0.5, Vector2(dia, dia)), false)
		else:
			# 占位：淡 ink 圆 + 名字首字。**这条分支必须存在**（无 Steam / 头像没下载下来 /
			# 对方没设头像），否则那几种情形下玩家看到的是"两个空槽"。
			# ★ 用 ink 的 alpha 而不是 accent：accent 在浅色主题下本身就是深色，
			#   28% 的深棕圆看着像"禁用/离线"（2026-10-21 目检）。
			node.draw_circle(av_c, dia * 0.5, Color(ink.r, ink.g, ink.b, 0.12))
			var f0 := UITheme.body_font()
			if f0 != null:
				var ini: String = _display_name_for(slot).substr(0, 1)
				var fs0 := int(dia * 0.42)
				var tw: float = f0.get_string_size(ini, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0).x
				node.draw_string(f0, av_c + Vector2(-tw * 0.5, fs0 * 0.36), ini,
						HORIZONTAL_ALIGNMENT_LEFT, -1, fs0, ink)
	# 头像圆环：自己是主题强调色（"这一条是我"），对端是墨色淡环。
	# ★ `antialiased = false` —— 铁律 §128：自绘图元带抗锯齿会在退出时偶发 0xC0000005。
	var ring := Color(accent.r, accent.g, accent.b, 0.75) if slot == 0 \
		else Color(ink.r, ink.g, ink.b, 0.30)
	node.draw_arc(av_c, dia * 0.5, 0.0, TAU, 40, ring, 1.3, false)
	var f := UITheme.body_font()
	if f == null:
		return
	var text_x := 6.0 + dia + 8.0
	var text_w: float = r.size.x - 6.0 - dia - 8.0 - 8.0
	var align := HORIZONTAL_ALIGNMENT_LEFT
	var name_txt := _ellipsize(f, _display_name_for(slot), text_w, 15)
	node.draw_string(f, Vector2(text_x, r.size.y * 0.46), name_txt, align, text_w, 15, ink)
	# 第二行：说话中临时显示表情名（头像上画的那个），否则显示执色/准备状态。
	# ★ 换掉的只是**这一行**，名字那行不动 —— 否则"谁在说话"反而认不出来了。
	var sub_txt: String = _identity_state_text(slot)
	var sub_a: float = 0.72
	if emote_a > 0.0 and Emotes.is_valid(_emote_bubble_idx[slot]):
		sub_txt = Emotes.name_of(_emote_bubble_idx[slot])
		sub_a = maxf(emote_a, 0.45)     # 淡出时别把字一起淡没了（头像淡是"消失"，字淡是"看不清"）
	node.draw_string(f, Vector2(text_x, r.size.y * 0.80), sub_txt,
			align, text_w, 12, Color(ink.r, ink.g, ink.b, sub_a))


## 按可用宽度截断并加省略号。
## ★ `draw_string()` 的 `width` 参数**只影响对齐，不裁剪**（超长文字照样画出去）——
##   这条不写的话，最长 32 字符的 Steam 昵称会直接压到对端槽上，而且不报任何错。
func _ellipsize(f: Font, text: String, max_w: float, fs: int) -> String:
	if f == null or max_w <= 0.0 or text == "":
		return text
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var s := text
	while s.length() > 1 \
			and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		s = s.substr(0, s.length() - 1)
	return s + "…"


## 取某人头像的**圆形遮罩版**并缓存。
## ★ 圆遮罩在 CPU 上做一次（64×64 = 4096 像素），结果缓存；
##   换成 shader 的话要多一个资源 + 一套 uniform 绑定，为一个 44px 的圆不值得。
func _avatar_circle_for(steam_id: int) -> Texture2D:
	if steam_id == 0:
		return null
	var key := "%d" % steam_id
	var hit: Variant = _avatar_circle_cache.get(key)
	if hit != null and is_instance_valid(hit):
		return hit as Texture2D
	var raw := SteamNet.avatar_texture(steam_id, SteamNet.AVATAR_MEDIUM)
	if raw == null:
		return null
	var img := raw.get_image()
	if img == null or img.is_empty():
		return null
	_circle_mask(img)
	var tex := ImageTexture.create_from_image(img)
	_avatar_circle_cache[key] = tex
	return tex


## 把方形头像裁成圆（1px 抗锯齿过渡）。**就地修改**传入的 Image。
func _circle_mask(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var c := Vector2(w, h) * 0.5
	var rad: float = minf(w, h) * 0.5
	for y in range(h):
		for x in range(w):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			var a: float = clampf(rad - d + 0.5, 0.0, 1.0)
			if a >= 1.0:
				continue       # 圆内绝大多数像素：省掉 get/set，64×64 也就 4096 次循环
			var col := img.get_pixel(x, y)
			col.a = col.a * a
			img.set_pixel(x, y, col)


## 头像重试的**唯一**节奏点（0.5s 一问，问几句什么时候停由 `SteamNet.avatar_pending()` 定）。
## ★ 由 `_process()` 在"没有动画就 early return"那句**之前**调用：
##   摆在后面的话，静默的对局里头像永远不会被取回来（正是最需要它的时刻）。
func _tick_net_identity(delta: float) -> void:
	if _drawer_layer == null or not is_instance_valid(_drawer_layer):
		return
	if not _drawer_layer.visible:
		return
	_avatar_retry_acc += delta
	if _avatar_retry_acc < 0.5:
		return
	_avatar_retry_acc = 0.0
	var changed := false
	for slot in [0, 1]:
		var cur: Texture2D = _avatar_tex[slot]
		if cur != null and is_instance_valid(cur):
			continue
		var sid := _steam_id_for(slot)
		if sid == 0:
			continue
		if not SteamNet.avatar_pending(sid, SteamNet.AVATAR_MEDIUM):
			continue
		var t := _avatar_circle_for(sid)
		if t != null:
			_avatar_tex[slot] = t
			changed = true
	if changed:
		_redraw_identity()


# ====== 快捷表情（2026-10-21）======
## 表情格所在的那块面 = **抽屉底色**。
## 抽屉面板的底、按钮的底、以及"画在按钮上的表情该用什么色"全都从这一个量出发。
## ★★ 2026-10-21 目检抓到的真 bug：原来返回 `page_surface()`（宣纸主题下是暖米白），
##   而按钮实际是**浅色**（`style_theme_button()` 在深色面板上给浅底深字）、表情却按
##   深色面挑成了**近白**墨 ⇒ 白线压浅金底，量出来对比度 1.79（糊成一片）。
##   ⇒ 参照面必须与"它实际画在哪"一致。
func _emote_panel_surface() -> Color:
	return _drawer_surface()


## 一个表情格该用的墨色。
## ★★ 直接读**按钮自己**的 `font_color`（`style_theme_button()` 刚按那块面算好的那个值），
##   而不是再按"面"推一遍：按钮底色是调色板从面推出来的**第二层派生**，拿面去推墨会差一层
##   亮度 —— 实测就是"白线压浅金底"。读按钮自己 = 与按钮文字**同一支笔**，差不了。
func _emote_cell_ink(node: Control) -> Color:
	var b: Node = node.get_parent() if node != null else null
	if b is Button and (b as Button).has_theme_color_override("font_color"):
		return (b as Button).get_theme_color("font_color")
	return GameConfig.readable_ink_on(_drawer_surface())


func _draw_emote_cell(node: Control, idx: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	_draw_ticks["emote_cell"] = int(_draw_ticks.get("emote_cell", 0)) + 1
	var r := Rect2(Vector2.ZERO, node.size)
	Emotes.draw_emote(node, idx, r.size * 0.5, minf(r.size.x, r.size.y) * 0.38,
			_emote_cell_ink(node), GameConfig.accent_color())


## 选定一个表情：本地先放 → 再发出去。
## ★ 2026-10-21 起不再"选完关面板"：表情格一直在左抽屉里，没有面板可关。
func _on_emote_pick(idx: int) -> void:
	send_emote(idx)


## 发一个表情（**自检也走这里**，别在自检里另写一份发送逻辑）。
## 返回是否真的发出去了（节流挡掉 / idx 非法 ⇒ false）—— 自检据此判"节流生效"。
func send_emote(idx: int) -> bool:
	if not Emotes.is_valid(idx):
		return false
	var now := Time.get_ticks_msec()
	if _emote_last_sent_ms > 0 and now - _emote_last_sent_ms < EMOTE_SEND_GAP_MS:
		return false
	_emote_last_sent_ms = now
	# 本地先放（= `call_local` 语义）：自己的表情自己也该看见，不该等对端回声。
	_play_emote(0, idx)
	if game_mode == ONLINE and _chan != null and _chan.is_live():
		_chan.send_message({"m": "emote", "e": idx})
	return true


## 让某个槽显示一个表情（slot 0=自己 / 1=对端）。
## ★ 2026-10-22：表情现在**画在身份槽的头像圆里**，不再是一个飘在棋盘上的气泡面板
##   （用户口令「表情包不要遮挡棋盘」）。这个函数因而只剩"记状态 + 让槽重画"。
func _play_emote(slot: int, idx: int) -> void:
	if slot < 0 or slot > 1 or not Emotes.is_valid(idx):
		return
	_emote_bubble_idx[slot] = idx
	_emote_bubble_left[slot] = EMOTE_BUBBLE_LIFE
	_redraw_identity()


## 某槽表情的**淡出系数**（1 = 刚发出、0 = 已消失）。唯一派生点。
## ★ 抽出来的理由（§111）：这个公式原来只写在 `_tick_emote_bubbles()` 里当 `modulate.a`，
##   现在既要在绘制里用、又要在判据里读 —— 两处各写一遍迟早只改一处。
## ⚠️ 判据**不许**读它当"画了多少"的证据（那是自己问自己，§70）；
##   判据读探针 `_last_emote_alpha`（真画出去的那个数）。
func emote_slot_alpha(slot: int) -> float:
	if slot < 0 or slot > 1:
		return 0.0
	if _emote_bubble_left[slot] <= 0.0:
		return 0.0
	return clampf(_emote_bubble_left[slot] / EMOTE_BUBBLE_FADE, 0.0, 1.0)


## 头像圆在**槽内**的矩形（局部坐标）。绘制与判据共用的唯一几何真源。
## ★ 2026-10-22 抽出来是为了让「表情画在哪」可以被判据直接量 ——
##   以前头像位置只是 `_draw_identity_slot()` 里的一个局部变量，判据根本拿不到。
func _avatar_rect_in_slot(node_size: Vector2) -> Rect2:
	var dia: float = minf(NET_ID_AVATAR_DIA, node_size.y - 10.0)
	var c := Vector2(6.0 + dia * 0.5, node_size.y * 0.5)
	return Rect2(c - Vector2(dia, dia) * 0.5, Vector2(dia, dia))


## 头像圆的**屏幕矩形**。判据拿它去和棋盘盒比"碰不碰"。
func avatar_screen_rect(slot: int) -> Rect2:
	var n: Control = _net_id_self if slot == 0 else _net_id_peer
	if n == null or not is_instance_valid(n):
		return Rect2()
	var r := _avatar_rect_in_slot(n.size)
	return Rect2(n.global_position + r.position, r.size)


## 表情生命周期。★ 与 `_tick_net_identity` 同理，必须在 `_process()` 的 early return 之前：
## 动画表恒空时（静默对局）表情也得会淡出，否则它会一直挂在头像上。
func _tick_emote_bubbles(delta: float) -> void:
	var dirty := false
	for slot in [0, 1]:
		if _emote_bubble_left[slot] <= 0.0:
			continue
		_emote_bubble_left[slot] = maxf(_emote_bubble_left[slot] - delta, 0.0)
		if _emote_bubble_left[slot] <= 0.0:
			_emote_bubble_idx[slot] = -1
		dirty = true
	# ★ 只在真有表情在走时重绘：身份槽是自绘控件，没有"改了 modulate 就自己重画"那条路
	#   （那是 Control 节点才有的便利，而承载表情的节点已经不在了）。
	if dirty:
		_redraw_identity()


## ⚰️ 2026-10-22 墓碑（名字不许回收）：这一段原有四个函数
##   `_draw_emote_bubble()` / `_build_emote_bubbles()` / `_make_emote_bubble()` /
##   `_refit_emote_bubbles()` —— 一整套 132px 的**棋盘中央气泡面板**（CanvasLayer 27）。
##   落点取 `board_area()` 的水平中线、纵向 16% / 68% ⇒ 说话时正好压在盘面的空点上，
##   而盘面上那些点是要落的子。用户口令「表情包不要遮挡棋盘」⇒ 整套删除。
##   表情改画在身份槽的头像圆里（见 `_draw_identity_slot()`），那块区域在左抽屉内，
##   **结构上到不了棋盘** —— 不是"挪个位置凑巧不压"。
##   ⚠️ 顺带：`EMOTE_BUBBLE_DIA` 常量随之删除（§33 死参数 = 旋钮拧不动）。



## ★ 失败与警告**都必须让人看见**：覆盖层弹不出来时屏幕上什么都不会发生，玩家只会反复点。
##   ⇒ 走 `_show_invite_note()`（写 HUD 覆盖行，3 秒后自动收回）。
func _on_invite_pressed() -> void:
	var r: Dictionary = SteamNet.open_invite_dialog()
	if not bool(r.get("ok", false)):
		_show_invite_note("邀请失败：%s" % str(r.get("reason", "未知原因")))
		return
	var warn := str(r.get("warn", ""))
	if warn != "":
		_show_invite_note("已请求邀请窗口；" + warn)


## 把一条临时说明写进 HUD 覆盖行，`INVITE_NOTE_SEC` 秒后收回。
## ★ 收回前先核对自己写的还是不是那条：别的代码也用这个覆盖层（棋谱加载失败），
##   不核对就会把别人的提示一起抹掉（或者自己那条永远收不掉）。
## ★ 用一次性定时器的**回调**而不是 `await`：本函数会被按钮回调直接调用，
##   带 await 会让调用方变成协程（连点就攒下一串等待中的协程，语义还不好读）。
const INVITE_NOTE_SEC: float = 5.0
func _show_invite_note(msg: String) -> void:
	_hud_override = msg
	_update_hud()
	print("[invite] ", msg)
	get_tree().create_timer(INVITE_NOTE_SEC).timeout.connect(func() -> void:
		if _hud_override == msg:
			_hud_override = ""
			_update_hud())


# ====== 棋钟接线（2026-10-16）======
## 建棋盘内核（只建一次；`_ready` 里在 `reset_game()` 之前调）。
func _build_clock() -> void:
	if _clk != null:
		return
	_clk = GameClock.new()
	_clk.name = "GameClock"
	add_child(_clk)          # add_child 会触发它的 `_ready()` ⇒ 参数就位 + `reset()`
	# 调试 / 回退口：`--clock=0` 关掉棋钟（钟不走、HUD 不显示那一行）。
	# ★ 与 `--musicloopfix=0` 同一条理由：新系统必须有一条**一键回退**的路，
	#   而且它顺手让"没有棋钟时游戏照常"这条能被一条命令验到。
	for a in _argv():
		if a.begins_with("--clock="):
			_clk.clk_enabled = a.substr(8).to_int() != 0
			print("[clock] 棋钟已按命令行关闭" if not _clk.clk_enabled else "[clock] 棋钟开启")
			break
	clk = _clk.snapshot()


## 每帧推进棋钟。★★ **必须在 `_process()` 的最前面调用**：`_process()` 中段有一句
## "两个动画表都空就 early return"，而"长考"（画面最静、钟走得最要紧的那一段）恰好
## 就是动画表为空的那一段 —— 放到它后面等于**长考不走钟**（同族坑：复盘推进那句注释）。
func _tick_clock(delta: float) -> void:
	if _clk == null:
		return
	# 走钟的准入条件（**全工程唯一一处**判定"什么算在对局中"）：
	#   · `game_mode >= 0`：菜单阶段（负数）不走；
	#   · 未终局、不在复盘中；
	#   · ★ **联机档不走钟**。理由不是"没做"，是"现在做一定是错的"：剩余时间是各机
	#     用本地 `delta` 累加出来的，网络抖动/掉帧会让两端读出不同的数字，而超时是要
	#     **判负**的 —— 让两台机器各自判罚必然出事。要做就得先有权威时钟（房主下发、
	#     加入方按快照校正），那是独立的一件事，这一轮明确不做。
	var active: bool = game_mode >= 0 and not game_over and _replay == null \
		and game_mode != ONLINE
	_clk.tick(delta, current_player, active)
	clk = _clk.snapshot()
	# 超时判负：走既有的 `_resign_game()`（**不另写一套终局路径** —— 那条路上还挂着
	# 联机战绩、棋谱终局条目、结果浮层，各写一遍迟早会漏一处）。
	if not game_over and _clk.timed_out != 0:
		var loser: int = _clk.timed_out
		var who := "黑方" if loser == Stone.BLACK else "白方"
		var why := "读秒用尽" if _clk.mode == GameClock.MODE_BYOYOMI else "用时耗尽"
		_resign_game(loser, "%s超时判负（%s）" % [who, why])


## 棋钟那一行文字。★ 文案的**唯一拼装处**是 `GameClock.hud_text()`（UI 不自己拼时间：
## "读秒还剩几次"这类口径一分成两份，迟早只改一处）。
func _update_clock_hud() -> void:
	if _hud_clock_label == null or not is_instance_valid(_hud_clock_label):
		return
	var txt := ""
	if _clk != null and bool(clk.get("enabled", false)):
		txt = str(clk.get("hud", ""))
	var vis: bool = txt != ""
	if _hud_clock_label.text == txt and _hud_clock_label.visible == vis:
		return                  # 只在**真的变了**才写（写文本会惊动容器的重排）
	# ★ 只有**可见性**变了才重排：横屏 HUD 的落点依赖 `get_combined_minimum_size()`，
	#   而那一行文字的长短变化**不改**这个尺寸（宽度由按钮行决定）—— 每次秒数跳动都
	#   重排一次是白干，而且在窄屏上会让整簇 HUD 每秒钟抖一下。
	var need_refit: bool = _hud_clock_label.visible != vis
	_hud_clock_label.text = txt
	_hud_clock_label.visible = vis
	if need_refit:
		_refit_hud()


## 棋钟自检入口（`--clocktest`）。
## ★ 分工：内核判据（走时/读秒/加秒/超时/手频/压力）全在 `GameClock.run_selftest()` ——
##   它们是纯逻辑，只有内核自己拿得到细节；这里只补**两条对局侧才能验**的契约。
func _clock_self_test() -> void:
	print("[clocktest] ===== 棋钟 × 音乐节拍耦合 =====")
	if _clk == null:
		print("[clocktest] ⓪ ✗ 棋钟未建（`_build_clock()` 没跑？）")
		print("[clocktest] 结论：失败 ✗")
		return
	# ★ 自检**强制开启**棋钟：`--clocktest --clock=0` 时若跟着关掉，⑬⑭⑮⑯ 会集体假红 ——
	#   而回退档真正要验的是"游戏照常跑"（那由冒烟覆盖：`--clock=0 res://game.tscn --quit`），
	#   不是棋钟自己。收尾还原。
	var en_keep: bool = _clk.clk_enabled
	if not _clk.clk_enabled:
		print("[clocktest] 注意：棋钟被 --clock=0 关闭 ⇒ 本次自检临时开启（回退档由冒烟覆盖）")
		_clk.clk_enabled = true
	# ⓪ 黑白索引契约：`game_clock.gd` 里各写一份的索引常量必须与 `enum Stone` 一致。
	#   ★ 为什么必须有人看着：调换 `Stone` 的声明顺序不会报任何错，症状是
	#     黑白的**钟走反了**（看起来像"AI 不思考"，其实是时间记到别人头上）。
	var index_ok: bool = GameClock.BLACK == Stone.BLACK and GameClock.WHITE == Stone.WHITE
	print("[clocktest] ⓪ 黑白索引契约｜内核常量与 enum Stone 对齐%s（真源 %d/%d · 内核 %d/%d）" % [
		"" if index_ok else " ✗", Stone.BLACK, Stone.WHITE,
		GameClock.BLACK, GameClock.WHITE])
	# ⑬ 快照契约（**运行期面**）：对局侧真的把 `clk` 挂上去了，且带音乐要读的三个键。
	#   静态面（源码里有 `var clk`）在 `--musictest` 判据⑦ —— 两面缺一，改名都只有一半会被逮到。
	var names: Dictionary = {}
	for p in get_property_list():
		names[str(p["name"])] = true
	var need_keys := ["clk_bpm", "clk_pressure", "hud"]
	var miss_key: Array[String] = []
	for k in need_keys:
		if not clk.has(k):
			miss_key.append(k)
	var snap_ok: bool = names.has("clk") and (clk is Dictionary) and miss_key.is_empty()
	print("[clocktest] ⑬ 快照契约｜真场景暴露 clk 且含音乐要读的键%s（缺 %s）" % [
		"" if snap_ok else " ✗", str(miss_key)])
	# ⑭ 端到端接线：走一帧 ⇒ 时间真的在减少、落一手 ⇒ 手频真的记上了、HUD 行真的出字。
	#   ★ 内核那 12 条量的是**纯逻辑**（喂固定 delta）；这一条量的是
	#     `_process() → _tick_clock() → 内核 → clk 快照 → HUD 行` 这条链真的通。
	#     同族坑：内核全绿而对局侧根本没搭这条线 ⇒ 钟永远不走，而判据一条都不红。
	#   ⚠️ 自检期间要走钟，得让准入分支成立（`game_mode >= 0` 且未终局）——
	#     所以临时改成 LOCAL 并在收尾还原；本函数结尾就 quit，但**还原仍要做**：
	#     判据③ 的"只碰自己 new 的实例"是纪律，这里碰的是真场景状态，必须收干净。
	var gm_keep: int = game_mode
	game_mode = LOCAL
	game_over = false
	_clk.reset()
	_tick_clock(2.0)
	var moved_ok: bool = absf(float(clk["black"]) - (_clk.main_seconds - 2.0)) < 0.01
	_clk.on_move(Stone.BLACK)
	_tick_clock(1.0)
	_update_clock_hud()
	var hud_ok: bool = _hud_clock_label != null and _hud_clock_label.visible \
		and _hud_clock_label.text.contains("▶")
	# ⑮ 跨组件真接线：音乐**真的**从本场景读到了棋钟（读它读到的那一份来对账）
	#   ★ ⑬ 只证明"字段挂上去了"，这一条证明"对端真的读到" —— 缺了它，
	#     名字/结构对不上时音乐会静默退回固定 BPM，而两侧判据全绿。
	var st_m: Dictionary = Music._read_battle_state()
	var link_ok: bool = st_m.has("clk_bpm") and st_m.has("clk_pressure") \
		and absf(float(st_m["clk_bpm"]) - float(clk["clk_bpm"])) <= 1e-6 \
		and absf(float(st_m["clk_pressure"]) - float(clk["clk_pressure"])) <= 1e-6
	print("[clocktest] ⑭ 端到端接线｜走钟 2s ⇒ 黑剩 %.1fs｜落一手 ⇒ 手频 %.1f 手/分｜HUD 行「%s」%s" % [
		float(clk["black"]), float(clk["rate"]), str(_hud_clock_label.text if
			_hud_clock_label != null else ""), "" if (moved_ok and hud_ok) else " ✗"])
	print("[clocktest] ⑮ 跨组件接线｜音乐反射读到的 clk_bpm=%.1f / clk_pressure=%.3f（本场景 %.1f / %.3f）%s" % [
		float(st_m.get("clk_bpm", -1.0)), float(st_m.get("clk_pressure", -1.0)),
		float(clk["clk_bpm"]), float(clk["clk_pressure"]),
		"" if link_ok else " ✗"])
	# ⑯ 换速时的**相位重标定**（本轮唯一的时序判据，也是这一族里最隐蔽的坑）：
	#   小节头换速后，`_clock` 里"距下一步的余量"必须按 新/旧 步长之比缩放 ——
	#   不缩放的话，新步长更短会让余量**当场够一步** ⇒ 补跳一拍（听感 = 抢拍），
	#   而它不报任何错（音符照发，只是节奏挪了一下）。
	#   ★★ 参数是**挑过**的，不是随手写的：每小节必须只有 **2 步**、总推进 2.7s。
	#   首版写成"每小节 4 步 + 推 4.7s"⇒ 跨 4 步刚好撞上 `_advance()` 的
	#   `_MAX_CATCHUP`（长卡顿丢积压）兜底，`_clock` 被无条件清零 ⇒ **有没有重标定
	#   都是 4 步** —— 一条恒真式判据（正是 §110 那一族）。
	#   现在：重标定 ⇒ 2 步且余量 0.35；不重标定 ⇒ 3 步（余量 0.7 ≥ 新步长 0.5）。
	var m_bpm: float = Music.bpm
	var m_spb: int = Music.beats_per_bar
	var m_sd: int = Music.subdiv
	Music.bpm = 60.0
	Music.beats_per_bar = 2
	Music.subdiv = 1                 # ⇒ 步长 1.0s，每小节 2 步（换速点在第 2 步）
	Music._step_idx = 0
	Music._clock = 0.0
	Music._bpm_now = 0.0
	_clk.bpm_now = 120.0             # 棋钟把目标提到 120 ⇒ 第 2 步（小节头）提交换速
	_clk.snapshot()
	Music._advance(2.7)
	var phase_ok: bool = Music._step_idx == 2 \
		and absf(Music._clock - 0.35) <= 1e-6 \
		and absf(Music.effective_bpm() - 120.0) <= 1e-9
	print("[clocktest] ⑯ 换速相位重标定｜走 2.7s 须只跨 2 步且余量 0.35｜换速须真的生效%s（实测 %d 步 · 步长 %.3fs · 余量 %.3f · 生效 %.0f BPM）" % [
		"" if phase_ok else " ✗", Music._step_idx, Music.step_seconds(),
		Music._clock, Music.effective_bpm()])
	Music.bpm = m_bpm
	Music.beats_per_bar = m_spb
	Music.subdiv = m_sd
	Music._step_idx = 0
	Music._clock = 0.0
	Music._bpm_now = 0.0
	game_mode = gm_keep
	_clk.clk_enabled = en_keep
	_clk.reset()
	clk = _clk.snapshot()
	_update_clock_hud()
	var res: Array = _clk.run_selftest()
	var pass_all: bool = index_ok and snap_ok and moved_ok and hud_ok and link_ok \
		and phase_ok and bool(res[0])
	print("[clocktest] 内核判据：%s" % str(res[1]))
	print("[clocktest] 结论：", "通过 ✓" if pass_all else "失败 ✗",
		"（说明：联机档刻意不走钟 —— 双端各自累加的时钟不能用来判负）")
	# 与其它游戏侧自检同一口径：跑完自己退出，退出码由结论决定（铁律 1：exit=0 ≠ 通过，
	# 所以这里两个信息都给：行内的 ✓/✗ 与退出码）。
	get_tree().quit(0 if pass_all else 1)

# ====== 复盘 HUD（棋谱阶段② 交互层，2026-10-08）======
# 规划 §阶段② 的五件交互：跳转键 · 手数滑条 · 连续播放 · 点盘跳转 · 信息栏。
# ★ 四条输入路（按钮 / 滑条 / 键盘 / 点盘）**全部汇到 `_rp_goto()` 与 `_rp_jump()`** ——
#   每条路各写一遍 `replay_goto()` 的话，"手动跳转要清播放余量"这类共性要么漏一处、
#   要么写成四份（本工程"两处都记得不是不变量"那条老坑）。
# ★ 判据走的就是这些函数本身（铁律 7：自检走真实交互路径），不是绕过 UI 直接调 replay.gd。

## 建复盘 HUD。**只建一次**（`_ready` 里调）：复盘是反复进出的模式，
##   每次进都重建一层的话旧层不会释放 —— 症状是"进出几次之后按钮越点越慢"，
##   且 `judge_replay_hud_layout()` 量的按钮数越来越多（判据被自己的历史污染）。
func _build_replay_hud() -> void:
	if _rp_layer != null:
		return
	_rp_layer = GameConfig.new_themed_layer()
	_rp_layer.name = "ReplayHud"
	# 层号比对局 HUD（25）高一档：复盘与对局**不会同时可见**（`_show_replay_hud` 互斥），
	# 高过它才能保证将来叠加的提示层不会把工具条压住。
	_rp_layer.layer = 26
	_rp_layer.visible = false
	add_child(_rp_layer)
	_rp_panel = PanelContainer.new()
	_rp_panel.name = "ReplayPanel"
	# 深色半透明底板：棋盘配色有 12 套单档主题（2026-10-08 起；旧版是 14 套 = 7 色系 × 深浅），
	# 纯文字在浅色盘上读不清。
	# ★ 2026-10-15：底色从**写死的深蓝灰**改成 `_replay_surface()`（= 主题棋盘色推到"恒为深色"
	#   的那一支）—— 理由与判据口径见该函数。六个按钮的调色板入参读的也是它，
	#   所以"按钮浮在它自己那张面上"由结构保证（此前这里写死颜色 ⇒ 按钮不可能跟主题）。
	var sb := StyleBoxFlat.new()
	sb.bg_color = _replay_surface()
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	# 描边用**对深色底提亮过的**主题标题色（原 accent 在深底上常常等于没有；纯白又丢了主题）
	var tc_bd: Color = GameConfig.dialog_title_color()
	sb.border_color = Color(tc_bd.r, tc_bd.g, tc_bd.b, 0.55)
	sb.set_content_margin_all(10.0)
	_rp_panel.add_theme_stylebox_override("panel", sb)
	_rp_layer.add_child(_rp_panel)
	var vb := VBoxContainer.new()
	vb.name = "ReplayBox"
	vb.add_theme_constant_override("separation", 8)
	_rp_panel.add_child(vb)
	_rp_box = vb
	_rp_info = Label.new()
	_rp_info.name = "ReplayInfo"
	_rp_info.add_theme_color_override("font_color", Color(0.94, 0.94, 0.96))
	_rp_info.add_theme_font_size_override("font_size", GameConfig.hud_label_font_size(15))
	vb.add_child(_rp_info)
	_rp_slider = HSlider.new()
	_rp_slider.name = "ReplaySlider"
	_rp_slider.min_value = 0.0
	_rp_slider.max_value = 0.0
	_rp_slider.step = 1.0
	_rp_slider.custom_minimum_size = Vector2(320.0, 0.0)
	_rp_slider.value_changed.connect(_rp_on_slider_changed)
	vb.add_child(_rp_slider)
	var hb := HBoxContainer.new()
	hb.name = "ReplayButtons"
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	_rp_buttons.clear()
	_rp_first_btn = _rp_make_button("first", _rp_on_first)
	_rp_prev_btn = _rp_make_button("prev", _rp_on_prev)
	_rp_play_btn = _rp_make_button("play", _rp_on_play)
	_rp_next_btn = _rp_make_button("next", _rp_on_next)
	_rp_last_btn = _rp_make_button("last", _rp_on_last)
	_rp_exit_btn = _rp_make_button("exit", _rp_on_exit)
	for b in [_rp_first_btn, _rp_prev_btn, _rp_play_btn, _rp_next_btn, _rp_last_btn, _rp_exit_btn]:
		hb.add_child(b)
		_rp_buttons.append(b)
	if not get_viewport().size_changed.is_connected(_refit_replay_hud):
		get_viewport().size_changed.connect(_refit_replay_hud)
	_refit_replay_hud()


## 复盘按钮的唯一工厂。★ 走工厂而不是逐行 `Button.new()`：`focus_mode = FOCUS_NONE`
##   这类"每个按钮都要有"的属性漏一支是**静默**的 —— 漏的那支会在按空格时被焦点
##   抢走键盘事件（症状是"空格有时暂停有时不响应"，看起来像随机）。
func _rp_make_button(kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = _rp_label_for(kind)
	b.focus_mode = Control.FOCUS_NONE
	# ★ 样式也走工厂：六个按钮"每个都要有"的东西又多了一样（`focus_mode` 是第一个）——
	#   样式漏一支同样**静默**（那一支退回引擎默认灰，而其余五支是主题色，
	#   看起来像"这个按钮是禁用态"）。表面读 `_replay_surface()`，与它父面板同一真源。
	#   ★ 内边距用**紧凑档**：工具条一行六个按钮压在盘上，宽度是硬约束（`RP_NARROW_W` 那套
	#     窄屏换文案的机制就是为了省宽），盒子大小必须与改动前一致。
	GameConfig.style_theme_button(b, _replay_surface(), GameConfig.BTN_PAD_COMPACT)
	b.pressed.connect(cb)
	return b


## 六个按钮的文案真源（唯一）。短/长两档 × 播放键两态，全部从这里出：
##   `_refit_replay_hud()`（窄屏切换）与 `_rp_sync_ui()`（播放状态变化）都调它。
##   ★ 两处各写一份的话，窄屏下按一次播放就把文案写回中文长版（静默，只在窄屏出现）。
func _rp_label_for(kind: String) -> String:
	var playing: bool = _replay != null and _replay.replay_playing
	if _rp_short:
		match kind:
			"first": return "|<"
			"prev": return "<<"
			"play": return "||" if playing else ">"
			"next": return ">>"
			"last": return ">|"
			"exit": return "X"
		return ""
	match kind:
		"first": return "首手"
		"prev": return "上一手"
		"play": return "暂停" if playing else "播放"
		"next": return "下一手"
		"last": return "末手"
		"exit": return "退出复盘"
	return ""


## 把六个按钮文案按当前档位刷新。★ 外提成函数是因为有**两个**触发点
##   （窄屏切换 / 播放状态变化）；其中播放键最要紧 —— 它漏刷的症状是
##   "按了播放但按钮还写着播放"，看着像按钮没接线。
func _refresh_rp_labels() -> void:
	var pairs: Array = [["first", _rp_first_btn], ["prev", _rp_prev_btn], ["play", _rp_play_btn],
		["next", _rp_next_btn], ["last", _rp_last_btn], ["exit", _rp_exit_btn]]
	for pr in pairs:
		var b: Button = pr[1]
		if is_instance_valid(b):
			b.text = _rp_label_for(str(pr[0]))


## 复盘面板摆位：**底部整条居中**（横竖屏同一套）。复盘时玩家的眼睛在盘中央，
##   工具条贴底最不挡棋；它很矮，横竖两套摆法在这里没有收益。
func _refit_replay_hud() -> void:
	if _rp_panel == null or not is_instance_valid(_rp_panel):
		return
	var vs := get_viewport_rect().size
	var m: float = 12.0
	var w: float = clampf(vs.x - m * 2.0, 280.0, 720.0)
	_rp_short = w < RP_NARROW_W
	var min_h: float = GameConfig.hud_button_min_height()
	var fnt: int = GameConfig.hud_button_font_size()
	for b in _rp_buttons:
		if not is_instance_valid(b):
			continue
		b.custom_minimum_size = Vector2(0.0, min_h)
		if fnt > 0:
			b.add_theme_font_size_override("font_size", fnt)
		else:
			b.remove_theme_font_size_override("font_size")
	if _rp_info != null and is_instance_valid(_rp_info):
		_rp_info.add_theme_font_size_override("font_size", GameConfig.hud_label_font_size(15))
	_refresh_rp_labels()
	_rp_panel.custom_minimum_size = Vector2(w, 0.0)
	# ★ 高取"容器的 size.y"与"刚设完下限的组合最小高"的较大者（同 `_refit_hud()`）：
	#   首帧容器的 `size.y` 还可能是 0，只信它会把面板摆到屏幕外（`vs.y - m - 0`）。
	var h: float = maxf(_rp_panel.size.y, _rp_panel.get_combined_minimum_size().y)
	_rp_panel.size = Vector2(w, h)
	_rp_panel.position = Vector2((vs.x - w) * 0.5, vs.y - m - h)


## 复盘 HUD 显隐（**唯一入口**）。★ 顺带管对局 HUD 的显隐 ——
##   两者同时可见时，复盘工具条会与"停一手 / 悔棋 / 认输"叠在一起，
##   而那四个按钮在复盘态下点了什么都不会发生（看着像坏了）。
func _show_replay_hud(on: bool) -> void:
	if _rp_layer != null and is_instance_valid(_rp_layer):
		_rp_layer.visible = on
		if on:
			_refit_replay_hud()
	if _hud_layer != null and is_instance_valid(_hud_layer):
		_hud_layer.visible = not on


## 把当前 `_replay` 的信号接到工具条。进复盘时调一次。
## ★ 为什么接信号而不是"每次操作后自己刷一次"：游标还有**第三条**变化路径 ——
##   `replay_tick()` 内部的自动推进与 `replay_finished`。漏掉播放那条路，
##   滑条就会在播放时停在原地（按钮文案与信息栏也跟着不动）。
func _rp_bind() -> void:
	if _replay == null:
		return
	if not _replay.replay_ply_changed.is_connected(_on_replay_ply_changed):
		_replay.replay_ply_changed.connect(_on_replay_ply_changed)
	if not _replay.replay_finished.is_connected(_on_replay_finished):
		_replay.replay_finished.connect(_on_replay_finished)


func _on_replay_ply_changed(_ply: int) -> void:
	_rp_sync_ui()


## 到末手自动停：播放键文案必须跟着回"播放"，否则玩家看到的还是"暂停"。
func _on_replay_finished() -> void:
	_rp_sync_ui()


## 把复盘状态一次性写进 UI（滑条值 / 按钮文案与可用性 / 信息栏）。
## ★ **唯一**写这些控件的地方：分散写的话"按了播放但按钮还写着播放"这类不一致会静默存在。
func _rp_sync_ui() -> void:
	if _rp_layer == null or not is_instance_valid(_rp_layer):
		return
	# ★ `_replay == null` 时走**空态**而不是 early return：退出复盘后按钮文案、滑条、
	#   信息栏都要被清干净 —— 直接 return 的话工具条会停在"暂停"上，
	#   下次进复盘前那一瞬间看着像"上一次的复盘还在"。
	var n: int = _replay.replay_total() if _replay != null else 0
	var p: int = _replay.replay_ply if _replay != null else 0
	# ★★ 顺序铁律：**先设 max 再设 value**。反过来的话，第一次同步（max 还是 0）会把
	#   value 夹成 0 ⇒ 滑条与游标**永久错位**。重入由 `_rp_ui_lock` 挡（见其声明处）。
	_rp_ui_lock = true
	_rp_slider.max_value = float(maxi(n, 0))
	_rp_slider.value = float(p)
	_rp_ui_lock = false
	_rp_slider.editable = n > 0
	_rp_first_btn.disabled = p <= 0
	_rp_prev_btn.disabled = p <= 0
	_rp_next_btn.disabled = p >= n
	_rp_last_btn.disabled = p >= n
	_refresh_rp_labels()
	_rp_info.text = _rp_info_text()


## 信息栏文案。★ 唯一的真源是 `replay.gd::replay_info()`，这里**只做排版** ——
##   任何"自己再从 `replay_record["moves"]` 算一遍"的写法都会与它分家
##   （正是"另写一份口径不同的副本"那条铁律）。
func _rp_info_text() -> String:
	if _replay == null:
		return ""
	var n: int = _replay.replay_total()
	var p: int = _replay.replay_ply
	var info: Dictionary = _replay.replay_info()
	# 空盘（游标 0）时 `replay_info()` 按设计返回空字典 —— 那不是错误，是"还没落子"
	if info.is_empty():
		return "第 0/%d 手 · 空盘" % n
	var color_txt: String = "停一手" if bool(info.get("is_pass", false)) \
		else ("黑" if str(info.get("color", "")) == "B" else "白")
	var txt: String = "第 %d/%d 手 · %s · 提 %d 子" % [
		p, n, color_txt, int(info.get("captures", 0))]
	if bool(info.get("in_ko", false)):
		txt += " · 劫争中"
	return txt


## 跳转到第 ply 手（按钮 / 滑条 / 键盘 / 点盘四条路的**唯一汇合点**）。
func _rp_goto(ply: int) -> void:
	if _replay == null:
		return
	_replay.replay_goto(ply, self)
	_rp_sync_ui()


## 跳到指定手并**停下播放**（"首手 / 末手"按钮与键盘 Home/End 共用）。
func _rp_jump(ply: int) -> void:
	if _replay == null:
		return
	_replay.replay_playing = false
	_rp_goto(ply)


## 单步 ±1。★ 手动步进要**停播**（棋谱软件的通行行为）：不停的话手动挪一格后
##   播放继续把游标推走，玩家会以为"点了没用"。
func _rp_step(delta_ply: int) -> void:
	if _replay == null:
		return
	_replay.replay_playing = false
	_rp_goto(_replay.replay_ply + delta_ply)


## 这颗格子「最后一手」是第几手（点盘跳转用）。0 = 该格在谱里没落过子。
## ★★ 必须**倒着扫**到第一次命中：一颗格可以被下、被提、再下 —— 正着扫会跳到**最早**
##   那一手，而玩家的预期是"跳到它**现在**这颗子被放下的那一手"（棋谱软件的通行做法）。
##   症状极隐蔽：多数格子只被下过一次，正着扫也"对" —— 只有"被提过再下"的格子会跳错。
func _rp_ply_of_tile(tile: int) -> int:
	if _replay == null or tile < 0:
		return 0
	var moves: Array = _replay.replay_record.get("moves", []) as Array
	for i in range(moves.size() - 1, -1, -1):
		if int((moves[i] as Dictionary).get("tile", -1)) == tile:
			return i + 1
	return 0


## 盘上棋子数（判据用：核对"复盘态按 R 不会把盘清空"这类"键位顺序"坏法）。
func _rp_stone_count() -> int:
	var n: int = 0
	for k in board.keys():
		if int(board[k]) != Stone.EMPTY:
			n += 1
	return n


func _rp_on_slider_changed(v: float) -> void:
	# ★ 重入闸：`_rp_sync_ui()` 写 `value` 时也会触发本函数（见 `_rp_ui_lock` 的声明处）
	if _rp_ui_lock or _replay == null:
		return
	_replay.replay_playing = false      # 手动拖滑条同样要停播（同 `_rp_step`）
	_rp_goto(int(round(v)))


func _rp_on_first() -> void:
	_rp_jump(0)


func _rp_on_prev() -> void:
	_rp_step(-1)


func _rp_on_play() -> void:
	if _replay == null:
		return
	_replay.replay_toggle_play(self)
	_rp_sync_ui()


func _rp_on_next() -> void:
	_rp_step(1)


func _rp_on_last() -> void:
	if _replay == null:
		return
	_rp_jump(_replay.replay_total())


func _rp_on_exit() -> void:
	replay_exit()


## 判据（自检用）：复盘 HUD ①已建 ②六个按钮全在视口内 ③按钮高度 ≥ 触摸目标下限
## ④面板本身在视口内。返回 [bool, 人读摘要]。
## ★ 与 `judge_hud_layout()` 分开写而不是复用：那条按 `_hud_buttons` 枚举（对局按钮），
##   复用它就得先把复盘按钮塞进那个数组 —— 正是本文件开头那段注里否掉的写法。
func judge_replay_hud_layout(want_h: float = -1.0) -> Array:
	if _rp_panel == null or not is_instance_valid(_rp_panel):
		return [false, "复盘 HUD 未建"]
	var vs := get_viewport_rect().size
	var expect_h: float = want_h if want_h >= 0.0 else GameConfig.hud_button_min_height()
	var bad: Array[String] = []
	var heights: Array[String] = []
	for b in _rp_buttons:
		if not is_instance_valid(b):
			continue
		var r: Rect2 = b.get_global_rect()
		heights.append("%.0f" % b.size.y)
		if r.position.x < -0.5 or r.position.y < -0.5 \
			or r.end.x > vs.x + 0.5 or r.end.y > vs.y + 0.5:
			bad.append("%s 出屏 %s" % [b.text, str(r)])
		# 与 `judge_hud_layout()` 同口径：`custom_minimum_size` 同步可读，`size` 要等重排
		if b.custom_minimum_size.y < expect_h - 0.5 or b.size.y < expect_h - 0.5:
			bad.append("%s 高 下限%.0f/实测%.0f < 期望%.0f" % [
				b.text, b.custom_minimum_size.y, b.size.y, expect_h])
	var pr: Rect2 = _rp_panel.get_global_rect()
	if pr.position.x < -0.5 or pr.position.y < -0.5 \
		or pr.end.x > vs.x + 0.5 or pr.end.y > vs.y + 0.5:
		bad.append("面板出屏 %s" % str(pr))
	var ok: bool = bad.is_empty() and _rp_buttons.size() > 0
	var msg: String = "%d 个按钮 高 [%s] 期望下限 %.0f 面板 %s 视口 (%d,%d)" % [
		_rp_buttons.size(), ", ".join(heights), expect_h, str(pr),
		int(vs.x), int(vs.y)]
	if not ok:
		msg += " → " + ("; ".join(bad) if not bad.is_empty() else "按钮数为 0")
	return [ok, msg]


## 玩家点击“停一手”：本回合不落子，交给对手；双方连续停 2 次 → 终局
func _on_pass_pressed() -> void:
	if game_over or game_mode < 0:
		return
	if is_ai_thinking and game_mode == VS_AI:
		print("AI 思考中，请稍候再停一手")
		return
	# 联机：把停一手作为动作发给服务器（由服务器权威应用并广播）
	if game_mode == ONLINE:
		if not _can_local_play():
			print("还没轮到你停一手")
			return
		_net_send_action({"type": "pass", "color": current_player})
		return
	if game_mode == VS_AI and current_player != PLAYER_COLOR:
		print("现在不是你的回合")
		return
	_apply_pass()
	if game_mode == VS_AI and current_player == AI_COLOR:
		_start_ai_turn()

## 玩家点击“认输”：立即终局，判对方胜，不走面积法（认输方 = 当前落子方）
func _on_resign_pressed() -> void:
	if game_over or game_mode < 0:
		return
	if is_ai_thinking and game_mode == VS_AI:
		print("AI 思考中，请稍候再认输")
		return
	if game_mode == ONLINE:
		if not _can_local_play():
			print("还没轮到你认输")
			return
		_net_send_action({"type": "resign", "loser": current_player, "color": current_player})
		return
	_resign_game(current_player)

## 认输终局：直接判 loser 一方告负，并附当前盘面参考得分
## reason 非空时作为额外说明显示（AI 主动认输时会带上落后多少点）
func _resign_game(loser: int, reason: String = "") -> void:
	if game_over:
		return
	game_over = true
	is_ai_thinking = false
	_show_ai_hud(false)
	_clear_count_prompt()
	# ★ 联机战绩（2026-10-01）：认输方 loser 告负 ⇒ 我赢了 = loser 不是我。
	#   只记联机（mode == ONLINE），人机/本地不计 —— 大厅胜率只反映"和真人打"的战绩。
	if game_mode == ONLINE:
		GameConfig.add_record_result(loser != _net_color)
	var verdict := ""
	if game_mode == VS_AI:

		if loser == PLAYER_COLOR:
			verdict = "你认输，白方（AI）获胜！"
		else:
			verdict = "AI 认输，黑方（你）获胜！"
	else:
		verdict = ("黑方认输" if loser == Stone.BLACK else "白方认输") + "，对方获胜！"
	var details := PackedStringArray()
	if reason != "":
		details.append(reason)
	var scores: Dictionary = _compute_scores()
	details.append("（认输时盘面参考）黑 %d / 白 %d" % [scores["total_black"], scores["total_white"]])
	details.append("按 R 或点右下角「重新开始」再来一局")
	# ★ 棋谱终局条目（阶段①）。**认输也必须写**：这是复盘时最需要保留的一局
	#   （"他是在这个局面认输的"），漏写的话谱停在最后一手、看不出是投降还是断线。
	#   走 `_record_finish()` 这一个口（不自己拼 result 字典）。
	_record_finish(GameRecord.REASON_RESIGN, scores)
	_show_result_overlay(verdict, details)
	_update_hud()
	queue_redraw()

func _empty_tiles() -> int:
	var cnt := 0
	for vid in board.keys():
		if board[vid] == Stone.EMPTY:
			cnt += 1
	return cnt

# ====== 终局胜负判定（简单面积法）======
## 终局后在空瓷砖上画的归属标记：tile_id -> Stone
var _terr_mark: Dictionary = {}
## 棋盘「盘」的几何缓存：顶点凸包外扩后的多边形（换盘 / 改 pad 时重算，见 `_rebuild_board_panel()`）。
var _panel_poly: PackedVector2Array = PackedVector2Array()
var _panel_pad_cached: float = -1.0

func _finish_game() -> void:
	if game_over:
		return
	game_over = true
	is_ai_thinking = false
	_show_ai_hud(false)
	_clear_count_prompt()

	var scores: Dictionary = _compute_scores()
	var total_b: int = scores["total_black"]
	var total_w: int = scores["total_white"]
	var verdict := ""
	if total_b > total_w:
		verdict = "黑方（你）获胜！"
	elif total_w > total_b:
		verdict = "白方（AI）获胜！"
	else:
		verdict = "平局"

	# ★ 联机战绩（2026-10-01）：数子终局 —— 我赢 = 我执黑且黑胜，或我执白且白胜；平局不计。
	#   只记联机（mode == ONLINE），人机/本地不计（大厅胜率只反映"和真人打"的战绩）。
	if game_mode == ONLINE:
		GameConfig.add_record_result(
				(_net_color == Stone.BLACK and total_b > total_w)
				or (_net_color == Stone.WHITE and total_w > total_b))

	var details := PackedStringArray()
	details.append("黑方(你)：盘面 %d + 领地 %d + 提子 %d = %d" % [
		scores["stones_black"], scores["territory_black"], black_prisoners, total_b])
	details.append("白方(AI)：盘面 %d + 领地 %d + 提子 %d + 贴目 %d = %d" % [
		scores["stones_white"], scores["territory_white"], white_prisoners, komi, total_w])
	details.append("按 R 或点右下角「重新开始」再来一局")
	# ★ 棋谱终局条目（阶段①）。与 `_resign_game()` **共用** `_record_finish()`（铁律 8）：
	#   两个终局路径的口径必须一致（winner 怎么判、比分怎么算、reason 怎么写），
	#   各写一遍迟早会漂 —— 而漂了之后症状是"认输的谱没有 winner 字段"，复盘时才现形。
	_record_finish(GameRecord.REASON_SCORE, scores)
	_show_result_overlay(verdict, details)
	_update_hud()
	queue_redraw()

## 2026-10-18 数子判定（纯逻辑部分）迁至 rules_kernel.gd（`_rk._compute_scores()`）；
## 领地描边 `_terr_mark` 仍在本文件（绘制层读），内核经 `host` 写入。
func _compute_scores() -> Dictionary:
	return _rk._compute_scores()

# ====== 「对方停一手 → 是否数子」提示 ======
## 背景：原先对手停一手后，玩家必须自己也点一次「停一手」才会终局（双方连续停手才结束），
## 玩家很容易卡在「对面都停了我该干嘛」。现在对手一停手就当面问一句要不要数子。
##
## 只对「该由人来决定」的那一侧弹窗：
##   人机   → 只有 AI 停手才弹（问玩家）
##   联机   → 只有**对方**停手才弹（问本地玩家；自己点的停一手不弹）
##   本地双人 → 任意一方停手都弹（由另一位决定）
## 联机下「数子」= 发一手 pass：连续第二手停手，由服务器权威终局，
## 因此**不需要新增任何协议/动作类型**，双端状态天然一致。
var _count_layer: CanvasLayer = null
## 关掉后回到旧行为（必须自己点「停一手」才终局）；保留开关便于对照
@export var count_prompt_enabled: bool = true

func _should_prompt_count(passer: int) -> bool:
	match game_mode:
		VS_AI: return passer == AI_COLOR
		ONLINE: return passer != _net_color
		LOCAL: return true
	return false

## 停一手之后的统一入口（人机 / 本地双人 / 联机共用）
func _prompt_count_after_pass(passer: int) -> void:
	if not count_prompt_enabled or game_over or _count_layer != null:
		return
	if not _should_prompt_count(passer):
		return
	_show_count_prompt(passer)

## 弹窗居中：等一帧拿到**实际**尺寸后再按视口定位。
## 原先写死「半个预设宽高」的偏移（如 -215/-95），而面板尺寸随内容变化
## （多一行说明、认输原因等）就会偏；CanvasLayer 子控件也不能靠 anchors 居中
## （它拿不到视口矩形当父区域，实测锚点 0.5 会定位到左上角之外）。
func _center_popup(panel: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var vs := get_viewport_rect().size
	panel.position = (vs - panel.size) * 0.5

func _show_count_prompt(passer: int) -> void:
	_clear_count_prompt()
	_count_layer = GameConfig.new_themed_layer()
	_count_layer.name = "CountPrompt"
	_count_layer.layer = 40
	add_child(_count_layer)
	var panel := PanelContainer.new()
	_count_layer.add_child(panel)
	GameConfig.style_dialog_panel(panel)     # 主题推导的深色面板（此前是引擎默认灰面板）
	_center_popup(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "对方停一手"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GameConfig.dialog_title_color())
	vb.add_child(title)
	var who := "黑方" if passer == Stone.BLACK else "白方"
	var body := Label.new()
	body.text = "%s已停一手，是否数子终局？" % who
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", GameConfig.dialog_text_color())
	vb.add_child(body)
	var hint := Label.new()
	hint.text = "选「继续下棋」则本局继续（空点下完会自动终局）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", GameConfig.dialog_text_color())
	vb.add_child(hint)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var yes := Button.new()
	yes.name = "CountYes"
	yes.text = "数子终局"
	yes.focus_mode = Control.FOCUS_NONE
	yes.custom_minimum_size = Vector2(150, 44)
	GameConfig.style_dialog_button(yes)      # 与 ESC 暂停面板同一套（紧凑档 + 五个状态全给）
	yes.pressed.connect(_on_count_confirmed)
	hb.add_child(yes)
	var no := Button.new()
	no.name = "CountNo"
	no.text = "继续下棋"
	no.focus_mode = Control.FOCUS_NONE
	no.custom_minimum_size = Vector2(150, 44)
	GameConfig.style_dialog_button(no)
	no.pressed.connect(_on_count_declined)
	hb.add_child(no)

## 「数子终局」：单机直接结算；联机发一手 pass（构成连续两次停手，服务器权威终局）
func _on_count_confirmed() -> void:
	_clear_count_prompt()
	if game_over:
		return
	if game_mode == ONLINE:
		if not _can_local_play():
			print("还没轮到你数子")
			return
		_net_send_action({"type": "pass", "color": current_player})
		return
	_finish_game()

## 「继续下棋」：只是关掉提示，盘面/回合完全不变
func _on_count_declined() -> void:
	_clear_count_prompt()
	if not game_over:
		print("选择继续下棋（不数子）")

func _clear_count_prompt() -> void:
	if _count_layer != null and is_instance_valid(_count_layer):
		_count_layer.queue_free()
		_count_layer = null

# ====== 结算结果面板 ======
var _result_layer: CanvasLayer = null

func _show_result_overlay(verdict: String, details: PackedStringArray) -> void:
	_clear_result_overlay()
	_result_layer = GameConfig.new_themed_layer()
	_result_layer.name = "ResultOverlay"
	_result_layer.layer = 40
	add_child(_result_layer)
	var panel := PanelContainer.new()
	_result_layer.add_child(panel)
	GameConfig.style_dialog_panel(panel)     # 主题推导的深色面板 + 主题色描边
	_center_popup(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var title := Label.new()
	title.text = verdict
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GameConfig.dialog_title_color())
	vb.add_child(title)
	for line in details:
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", GameConfig.dialog_text_color())
		vb.add_child(lbl)

func _clear_result_overlay() -> void:
	if _result_layer:
		_result_layer.queue_free()
		_result_layer = null

# ====== 返回菜单 ======
## 对局中点击“返回菜单”：切回独立的菜单场景（本场对局状态随场景释放，下次进入重新开始）
## （ESC 也走这里 —— 先经 _show_pause_menu 确认，不再直接切场景）
func _on_return_to_menu_pressed() -> void:
	_clear_pause_menu()
	# 联机局礼貌断开通道（第 5 步后只剩 Steam 一条）。
	# ★ `_chan != null` 这个判空**不能省**：`--onlinetest` 自检里 `GameConfig.online` 为真，
	#   但它从不建通道（单进程自环）；直接调 `_chan.close_relay()` 会空指针崩溃。
	if GameConfig.online and _chan != null:
		_chan.close_relay()
	_clear_ready_overlay()
	Transition.change_scene("res://menu.tscn")

# ====== ESC 暂停菜单 ======
## 按 ESC 弹出的确认面板。原先 ESC **直接**切回主菜单 —— 对局状态随场景释放，
## 误按一下整盘就没了（长局/联机尤其痛），所以改成先弹面板再确认。
var _pause_layer: CanvasLayer = null
var _pause_panel: Control = null
var _pause_dim: ColorRect = null

func _toggle_pause_menu() -> void:
	if _pause_layer != null:
		_clear_pause_menu()
	else:
		_show_pause_menu()

## 层号 50：盖过 HUD(20/25) 与数子提示/结算面板(40)。
## ⚠️ CanvasLayer 子控件拿不到视口矩形当父区域，anchors 不可靠（见 _center_popup 注释），
## 所以遮罩与面板都用**手动定位**；居中交给 _refit_pause_menu，随窗口缩放实时跟随。
func _show_pause_menu() -> void:
	_clear_pause_menu()
	_pause_layer = GameConfig.new_themed_layer()
	_pause_layer.name = "PauseMenu"
	_pause_layer.layer = 50
	add_child(_pause_layer)
	# 全屏遮罩：变暗 + 吃掉所有 GUI 点击（STOP），面板关闭前棋盘上方按钮都点不到
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_dim = dim
	_pause_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "DialogPanel"
	_pause_panel = panel
	# 底色/圆角/描边/内边距走 GameConfig（与 menu.gd 的 ESC 退出确认**同一套**：
	# 面板底色必须不透明才谈得上"文字对比度达标"，详见 game_config.gd 里那段坑注释）
	GameConfig.style_dialog_panel(panel)
	_pause_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.name = "DialogTitle"
	title.text = "暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	# ★ 不能再用 accent_color()：那是"对棋盘背景"推导的，浅色主题下是深棕，压在深色面板上
	#   实测对比度只有 2.88。dialog_title_color() = 同一强调色**提亮到对面板底色达标**，
	#   色相不变（仍是主题专属色），2026-09-22 用户报的"字看不清"就是这个。
	title.add_theme_color_override("font_color", GameConfig.dialog_title_color())
	vb.add_child(title)
	var hint := Label.new()
	hint.name = "DialogHint"
	hint.text = "对局尚未结束，再按 ESC 或点「继续对局」回到棋盘"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	# 同理不能用 ink_color()：浅色主题下它是近黑 (0.10,0.10,0.12)，对面板底对比度实测 **1.06**
	# （等于没字）。这里用柔和近白，对面板底色 ≥6。
	hint.add_theme_color_override("font_color", GameConfig.dialog_text_color())
	vb.add_child(hint)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var cont := Button.new()
	cont.name = "PauseContinue"
	cont.text = "继续对局"
	cont.focus_mode = Control.FOCUS_NONE
	cont.custom_minimum_size = Vector2(150, 46)
	cont.add_theme_font_size_override("font_size", 16)
	GameConfig.style_dialog_button(cont)
	cont.pressed.connect(_clear_pause_menu)
	hb.add_child(cont)
	var back := Button.new()
	back.name = "PauseBack"
	back.text = "返回主菜单"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(150, 46)
	back.add_theme_font_size_override("font_size", 16)
	GameConfig.style_dialog_button(back)
	back.pressed.connect(_on_return_to_menu_pressed)
	hb.add_child(back)
	var quit := Button.new()
	quit.name = "PauseQuit"
	quit.text = "退出游戏"
	quit.focus_mode = Control.FOCUS_NONE
	quit.custom_minimum_size = Vector2(150, 46)
	quit.add_theme_font_size_override("font_size", 16)
	GameConfig.style_dialog_button(quit)
	quit.pressed.connect(_quit_game_from_menu)
	hb.add_child(quit)
	# 始终居中：先按估算尺寸摆一次（不闪到角落），布局完成后精确居中，
	# 之后窗口缩放/切全屏都会实时跟随（一次性定位在 resize 后就偏了）
	if not get_viewport().size_changed.is_connected(_refit_pause_menu):
		get_viewport().size_changed.connect(_refit_pause_menu)
	_refit_pause_menu()
	await get_tree().process_frame
	_refit_pause_menu()

## 面板/遮罩按当前视口重排：遮罩铺满、面板正中
func _refit_pause_menu() -> void:
	if _pause_layer == null:
		return
	var vs := get_viewport_rect().size
	if _pause_dim != null and is_instance_valid(_pause_dim):
		_pause_dim.position = Vector2.ZERO
		_pause_dim.size = vs
	# size==0 = 首帧布局未完成，跳过（否则会按 0 尺寸摆到中心点右下，等一帧精定位即可）
	if _pause_panel != null and is_instance_valid(_pause_panel) and _pause_panel.size.x > 0.0:
		_pause_panel.position = (vs - _pause_panel.size) * 0.5

func _clear_pause_menu() -> void:
	if get_viewport().size_changed.is_connected(_refit_pause_menu):
		get_viewport().size_changed.disconnect(_refit_pause_menu)
	if _pause_layer != null and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
	_pause_layer = null
	_pause_panel = null
	_pause_dim = null

## 从暂停菜单退出整个程序：联机先礼貌断开再退（服务器会按掉线处理）
func _quit_game_from_menu() -> void:
	# 同上：判空不可省（`--onlinetest` 自检没有通道）
	if GameConfig.online and _chan != null:
		_chan.close_relay()
	get_tree().quit()

# ====== 输入 ======
func _input(event: InputEvent):
	# 鼠标移动 → 更新悬浮预览格。**不用 `_on_area_input` 的 motion**：那条管线只在
	# 「按住拖动」时才派发（`_on_area_input` 开头专门挡掉了它，防滑动落子）；
	# 这里收的是全局移动事件，即使不按键也会来。
	# ⚠️ `InputEventMouseMotion.position` 已是**视口逻辑坐标**（引擎在 `push_input` 里按
	#    `get_final_transform()` 的逆变换压过一道），与 `vertices`/`_tile_at_point` 同一套；
	#    这条由 `--hovertest` ② 用真实合成移动事件钉死（别改成窗口坐标）。
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		# ★★ 复盘态的键位**必须排在下面那串对局快捷键之前**：否则 `R`（重开）在复盘里
		#   会把盘清空、`ESC` 会弹出暂停面板 —— 两者都不报错，只是"复盘里按 R 就乱"。
		# ★ 走 `_rp_step/_rp_jump/_rp_on_play` 这几个**与按钮同一个**入口，不自己碰
		#   `replay_goto()`：键盘与按钮的语义必须逐位一致（否则"键盘能跳到的手法按钮做不到"）。
		if _replay != null:
			match event.keycode:
				KEY_LEFT: _rp_step(-1)
				KEY_RIGHT: _rp_step(1)
				KEY_HOME: _rp_jump(0)
				KEY_END: _rp_jump(_replay.replay_total())
				KEY_SPACE: _rp_on_play()
				KEY_ESCAPE: replay_exit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_R:
			if game_mode >= 0:
				if game_mode == ONLINE:
					_on_reset_pressed()
				else:
					restart_game()
		elif event.keycode == KEY_TAB:
			# ⚰️ 2026-10-13：这里原有「翻出运行时调参面板」。面板已整块删除 ⇒ Tab 回归空操作；
			#   但仍要**吞掉**这个键：不吞就会落到 Godot 默认的**焦点导航**上（按 Tab 跳焦点环），
			#   那是删面板带来的**行为漂移**，不只是"少了个面板"。
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			# 结算面板打开时不弹暂停（它有自己的按钮，再叠一层只会挡住）
			if _result_layer == null:
				_toggle_pause_menu()
			get_viewport().set_input_as_handled()

## 鼠标移出窗口：悬浮预览必须收掉，否则会在盘上留一块**永远不动**的鬼影
##（没有 motion 事件来改它，下一次重绘还画在那里）。
func _notification(what: int) -> void:

	if what == NOTIFICATION_WM_MOUSE_EXIT and _hover_tile != -1:
		_hover_tile = -1
		queue_redraw()

# ====== 落子 / 提子动画驱动 ======
func _process(delta: float) -> void:
	# ★★ 棋钟必须在这一行（**早于下面那句"没有动画就 early return"**）：
	#   长考时动画表恒空，把它放在早退之后 ⇒ **长考期间棋钟不走**，
	#   而那正是最需要走钟的时刻（旧口径见 `_tick_clock()` 的注释）。
	_tick_clock(delta)
	# ★ 联机身份条的头像重试 + 表情气泡淡出（2026-10-21）**同样必须在下一句 early return
	#   之前**：静默对局里 `_place_anims` / `_capture_anims` 恒空，摆在后面就成了
	#   "头像永远取不回来、气泡永远不消失"——而且完全静默（与上面棋钟那条同一个病）。
	_tick_net_identity(delta)
	_tick_emote_bubbles(delta)
	# ★★ 复盘推进必须在下一行那个「没有动画就早退」**之前**：复盘态下动画表恒为空
	#   （离位动画被 `replay_anim_enabled` 关掉了）⇒ 放到后面的话连续播放会被这行
	#   **整段吃掉**，症状是"按了播放但一动不动"，且没有任何报错。
	#   —— 本工程"闸放错位置"那一族的又一例（同 `replay_playing` 自锁死那条）。
	if _replay != null:
		if _replay.replay_tick(delta, self, replay_plays_per_sec) > 0:
			_rp_sync_ui()
	if _place_anims.is_empty() and _capture_anims.is_empty():
		return
	# `_anim_freeze`：只给截图自检（`--screenshot --shotdrop` / `--screenshot --shotcap`）用 ——
	# 把动画定在半途，否则等 2 秒截图时动画早跑完了，截到的永远是「已落定」，这个自检就等于没测。
	if _anim_freeze:
		queue_redraw()
		return
	for k in _place_anims.keys():
		_place_anims[k] -= delta
		if _place_anims[k] <= 0.0:
			_place_anims.erase(k)
	for k in _capture_anims.keys():
		var d: Dictionary = _capture_anims[k]
		# ★ 提子动画**排在落子动画之后**（2026-09-29 用户口令「提子动画要放在落子动画结束之后」）：
		#   `delay` 没走完就**只推 delay、不动 `time_left`** —— 于是 `time_left` 一直是满的，
		#   `_capture_fade_state()` 算出来必然是"原格 + 不透明"（被提的子先原样停着），
		#   等 delay 归零才开始升空淡出。⇒ **两段天然串行**，不需要在 `_stone_paint()` 里
		#   再加一条"delay>0 就当成起手帧"的守卫（那种永不生效的分支只会烂在那里）。
		# ★★ 时间必须**结转**：一帧的 delta 比剩余 delay 长时，多出来的那段要落到 `time_left` 上。
		#    第一版写成"delay 分支直接 `continue`" ⇒ 多余时间被**整段吞掉** ——
		#    平时 1/60s 一帧看不出来（误差最多一帧），但**只要有人一次推一大段**（截图冻结、
		#    自检里模拟多帧）就会表现为"提子永远不动"，且不报任何错（本轮实测踩到）。
		var dt := delta
		var dl := float(d.get("delay", 0.0))
		if dl > 0.0:
			var used: float = minf(dl, dt)
			dl -= used
			dt -= used
			d["delay"] = dl
			if dl > 0.0:
				continue
		d["time_left"] -= dt
		if d["time_left"] <= 0.0:
			_capture_anims.erase(k)
	queue_redraw()

# ====== 绘制 ======
## 重算棋盘「盘」的多边形（**几何**）：所有瓷砖顶点 → `BoardPanel.shape()`（凸包 + 外扩圆角）。
##
## ★ 几何与画法都在 `board_panel.gd::BoardPanel` 里（设置页预览共用同一份），
##   本函数只负责"什么时候算"：调用它的是 `_compute_tile_metrics()` 末尾，
##   那时顶点已换算成像素坐标 ⇒ 盘与 `tile_centers` **同生命周期**。
func _rebuild_board_panel() -> void:
	_panel_pad_cached = board_panel_pad
	_panel_poly = BoardPanel.shape(PackedVector2Array(vertices), board_panel_pad)


## 画棋盘「盘」—— 一块**托住棋盘的实体板**（面模式与图模式共用这一个函数，
## 画法本身在 `board_panel.gd::BoardPanel.draw()`，与设置页预览也是同一份）。
##
## ★ 盘必须画在**瓷砖 / 网格线之前**：它是底板，不是覆盖层。
## ★ 面模式下盘与瓷砖**同色**（瓷砖色就是主题棋盘色）⇒ 两者连成一片，
##   观感是"一整块木盘上刻着格子"；pad 那一圈露出来的就是盘边。
## ★ 图模式没有瓷砖面，盘是唯一的大面积底色 ⇒ 白/黑棋子与网格线的对比全部落在它身上。
## ★ `board_panel_tint` 乘在主题棋盘色上：默认白 = 原样跟随主题（"采用主题色"就是这条）。
func _draw_board_panel() -> void:
	if not board_panel_enabled:
		return
	if not is_equal_approx(_panel_pad_cached, board_panel_pad):
		_rebuild_board_panel()          # 运行期改 pad 立刻生效（`@export` 是旋钮，不能只在启动时读一次）
	if _panel_poly.size() < 3:
		return
	var edge: Color = line_color
	edge.a = minf(edge.a + 0.25, 1.0)
	BoardPanel.draw(self, _panel_poly, board_tile_color * board_panel_tint,
		board_panel_thickness, edge, maxf(line_width * 0.9, 1.2))


func _draw():
	# 几何尚未就绪（如 headless 自测尚未填充 tile_centers）时跳过，避免空数组越界
	if tiles.is_empty() or tile_centers.is_empty() or tile_centers.size() != tiles.size():
		return
	# ★★ 图模式（设置页「显示」开关）走**另一条完整画序**，见 `_draw_graph_mode()` 的长注释。
	#   两套的画序语义是**相反**的（面模式：线压棋子；图模式：棋子压线）⇒ 不能挤进一个函数。
	if GameConfig.graph_mode:
		_draw_graph_mode()
		return
	# 背景
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), background_color)
	# 棋盘「盘」：托住整块棋盘的实体板（必须画在瓷砖之前 —— 它是底板，不是覆盖层）
	_draw_board_panel()

	# 绘制瓷砖（纯色平涂：全盘统一低调底色，结构由边线表达）
	for i in range(tiles.size()):
		draw_colored_polygon(_tile_points_for_draw(i), board_tile_color)

	# 把瓷砖本身作为棋子：占格瓷砖染成玩家色（沿用釉面质感，与盘面瓷砖统一观感）；
	# 落子为棋子色从透明渐显，提子为棋子色渐隐回瓷砖本色——替代原来的圆形棋子。
	#
	# ★★ 棋子分**两遍**画（②a 静止、②b 正在下落），不是一遍 —— 正在下落的那一手必须
	#    **压在所有棋子之上**。按瓷砖索引序一遍画完时，"落点索引小于某块旧棋子"的那一手
	#    会被旧棋子盖住 → 表现为「落子**有概率**被已有棋子遮挡」（是否发生取决于索引与
	#    邻接关系，所以是"概率"，2026-09-29 用户报的正是这个）。
	#    ★ 为什么拆两遍不会改变别的观感：落定的棋子与本格瓷砖**不重叠**（瓷砖互不重叠），
	#      所以"把它排到最后画"与"按索引画"逐像素等价 —— 唯一存在重叠的时刻，
	#      就是它被抬离地面停在空中那一段。
	# ★★ 两遍都从 `_stone_paint()` 取"该格此刻画成什么"，**不在这里各自复算门槛** ——
	#    复算过一次就出过事：提子渐隐那条分支被 `board[i] == Stone.EMPTY` 挡死
	#    （提子时 `remove_group()` 已经把这一格置空），整条**永远不可达**，
	#    观感退化成"提子瞬间消失"，而且**不报任何错**、headless 也量不到（2026-09-29 修）。
	#    现在门槛只有 `_stone_paint()` 一处，`--captest` 断言的也是它。
	#    ★ 层号语义 = **离不离位**：0 = 落定在原格，1 = 离位（下落 / 提子升空）。
	# ②a 落定在原格的棋子（layer 0：不与任何格重叠，按瓷砖索引画即等价）
	for i in range(tiles.size()):
		var pa: Dictionary = _stone_paint(i)
		if not pa["draw"] or int(pa["layer"]) != 0:
			continue
		var ca: Color = pa["col"]
		var oa: Vector2 = pa["off"]
		_draw_tile_fill(i, ca, oa)
	# ②b **离位**的棋子（layer 1：下落的那一手 + 正在升空散尽的提子）**不在这里画** ——
	#    它要压在所有盘面标记（瓷砖边线 / 星位 / 最后一手点 / 终局领地）之上，见本函数末尾。
	#    ★★ 2026-09-29 用户报「落子时偶尔出现棋子被**棋盘边界线**遮挡，白子尤为明显」
	#    —— 真因就是这块层原先排在这里（边线**之前**）：砖一抬离本格，网格线就落在它**身上**。
	#    实测（`--hovertest` ⑨ 的 ⑨ 探针，抬离 16.1px 的标准盘）：**120 块全被划**，
	#    共 368 条边线从块内部穿过（其中 192 条是它**自己那块砖**的边线），单块最多 4 条；
	#    而同样一块砖不抬（h=0）时是 **0 条** —— 边线恰好压在棋子轮廓上，静止时根本看不出来。
	#    白子更显眼的原因也被量出来了：线色亮度 0.21，对白子对比 0.70、对黑子只有 0.14（4.9 倍）。
	#    ⇒ 不是"边线盖住了棋子"，而是"**抬起来的**棋子撞进了边线的地盘"。

	# 绘制瓷砖边线：同色相邻棋子（都是黑子瓷砖或都是白子瓷砖）的共享边不画，
	# 棋群在视觉上连成一整块；空点之间与棋子-空点之间照常画线。
	# ★ 段清单由 `_drawn_edge_segments(i)` 产出（**单一真源**）：`--hovertest` ⑨ 要量
	#   「离位的那块砖被几条边线从内部穿过」，量的必须是**真会画的那几条** ——
	#   自检里另抄一遍"同色相邻不画"，量到的就不是画面上那几条线了（§真源唯一）。
	for i in range(tiles.size()):
		for s in _drawn_edge_segments(i):
			draw_line(s[0], s[1], line_color, line_width)

	# 立方体棋盘：星位（中心 + 六个角六边形各取一块菱形）小黑点，绘制在瓷砖之上、棋子之下
	var star_tiles: Array[int] = _cube_star_tiles
	if _is_cube and star_tiles.size() > 0 and _min_tile_r > 0:
		var star_r := maxf(_min_tile_r * 0.16, 2.5)
		var star_col := Color(0.12, 0.12, 0.14)
		for t in star_tiles:
			if t >= 0 and t < tile_centers.size():
				draw_circle(tile_centers[t], star_r, star_col)

	# 落子半径（供最后一手点定位使用，已不再用于圆形棋子）
	var stone_r := _stone_px()

	# 上一步落子提示：在最近一手棋子上画一个高对比小圆点，便于看清轮到谁、刚下在哪
	# ★★ 2026-10-08 第三轮：**去掉硬编码反色**。旧写法 `Color.WHITE if 黑子 else Color.BLACK`
	#   在多主题下会失效 —— 实测「霓虹」的荧光绿黑子对白点只有 **1.23**、「赛博」的琥珀黑子
	#   只有 **1.22**（都 < 1.35 ⇒ 圆点几乎看不见），因为那两套的"黑方"本身比白点还亮。
	#   现在取色走 `GameConfig.last_move_dot_color(该子颜色)` 这条唯一真源：accent 达标就用
	#   accent（与整体配色同门），否则取近白/近黑里对比更大的那个并推到 ≥3.0。
	#   ⚠️ 必须传**这颗棋子的实际绘制色**（主题可能换过棋子色），不许按 Stone.BLACK/WHITE 猜黑白。
	if _last_move != -1 and _last_move < tiles.size() and board[_last_move] != Stone.EMPTY:
		var stone_col: Color = piece_color_black if board[_last_move] == Stone.BLACK else piece_color_white
		var dot_col: Color = GameConfig.last_move_dot_color(stone_col)
		draw_circle(tile_centers[_last_move], maxf(stone_r * 0.30, 2.5), dot_col)

	# 终局：空区归属标记（深色点=黑方领地，白点=白方领地），直观展示胜负判定依据
	# ★ 2026-10-20 用户口令：改成**落子点中心的小圆 + 同色邻点连线**（原来是沿瓷砖轮廓描边），
	#   对标腾讯围棋的标点法。两套画法共用 `_draw_terr_marks()`，半径各自按自己那套的棋子半径算。
	if game_over and _terr_mark.size() > 0:
		_draw_terr_marks(stone_r)

	# ②b **离位**的棋子（layer 1：下落的那一手 + 正在升空散尽的提子）：**最后画**。
	# ★★ 位置有两重含义，两条都是踩出来的：
	#   ① 必须排在 **②a 之后**（压在所有落定的棋子之上）—— 这是「落子有概率被已有棋子遮挡」
	#      那条 bug 的修法（一遍按索引画时，落点索引小的那一手会被旧棋子盖住）。
	#   ② 必须排在**所有盘面标记之后**（瓷砖边线 / 星位 / 最后一手点 / 终局领地）——
	#      2026-09-29 用户报「落子时棋子被**棋盘边界线**遮挡，白子尤为明显」。
	#      砖抬离本格之后，它自己那块砖的边线与上方邻格的边线都落在它**身上**：
	#      实测（`--hovertest` ⑨）抬离 16.1px 时**120 块全被划**、共 368 条穿过。
	# ★ 为什么可以统一排到最后而**不会改变任何别的观感**（不是"碰巧没坏"）：
	#   块只有在**离位**（`off != 0`）时才可能与别的格重叠 —— 落定在原格的那些（layer 0）
	#   与任何格都不重叠，也不与任何边线交叉（边线只走在格的边界上）。
	#   所以"离位块排在标记之后"与"按索引夹在中间"在**落定态下逐像素等价**，
	#   唯一有差别的就是"停在空中 / 正在升空"那一段 —— 而那段本来就该压在一切之上。
	# ★★ 2026-09-29 用户口令「**落子时保留侧边厚度**」：离位块现在**带侧壁** ——
	#   与悬浮预览共用 `_block_side_walls()` / `_side_color_for()`，于是
	#   「预览（有厚度的板）→ 落下（一直有厚度，落到地面时侧面高度自然归零）」是连续的，
	#   而不是"预览一块板、落下来一张纸"。侧壁色从**顶面色**派生 ⇒ 提子升空淡出时
	#   那一圈墙裙跟着一起淡，不会剩下"没有顶面的空壳"。
	for i in range(tiles.size()):
		var pb: Dictionary = _stone_paint(i)
		if not pb["draw"] or int(pb["layer"]) != 1:
			continue
		var cb: Color = pb["col"]
		var ob: Vector2 = pb["off"]
		if ob != Vector2.ZERO:
			var wb: Color = _side_color_for(cb)
			for q in _block_side_walls(i, ob):
				draw_colored_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), wb)
		_draw_tile_fill(i, cb, ob)

	# 悬浮预览放在**最后**（除了边框）：它模拟「浮在盘面上方的一块砖」，
	# 压在瓷砖边线上才符合视觉预期；跟着棋子那一层画会显得它是嵌在网格下面的。
	_draw_hover_preview()

	# 绘制棋盘边框
	var rect: Rect2 = Rect2(Vector2.ZERO, get_viewport_rect().size)
	draw_rect(rect, Color(0, 0, 0, 0.3), false, 3.0)


## 图模式（设置页「显示」开关）的**整条画序** —— 与面模式并列的另一套表达：
## 落子点 = 每块瓷砖的中心（不变）；**棋盘 = 落子点与相邻落子点的连线**；
## **棋子 = 圆形**（经典围棋的观感），直径全盘固定。
##
## ★ 用户口径（2026-10-20 定稿）：「落子点在每块瓷砖的中心，落子点与相邻落子点连线形成棋盘，
##   而不是现在瓷砖模式的框架；棋子直径取固定的**最近落子点间距**」
##   —— 密铺的落子单元 / 邻接 / 盘型一律不变，只换"怎么画"。
##   ★ 注意「连线形成棋盘」不等于「画瓷砖边」：前者是**对偶图**（顶点在格心、边跨过共享边），
##     后者是格子轮廓。v1 画的是瓷砖边 ⇒ 观感仍是瓷砖框，被否掉了。
##
## ★★ 为什么单起一条分支，而不是在 `_draw()` 里到处 `if graph`（第一版就是这么写的，已废弃）：
##   两套的**画序语义相反** ——
##     · 面模式：棋子是"整块染色"⇒ 边线必须压在棋子**之后**（砖缝从棋子面上划过去正是它的风格）；
##     · 图模式：棋子是**圆**，必须压在网格线**之上**（否则线从棋子面上穿过，像被切开）。
##   塞进一个函数 = 每次改动都要同时维持两条互相矛盾的约束。分开之后面模式那段**一行不动**
##   ⇒「关掉时逐像素不变」是结构性的，不靠运气。
## ★ 几何真源仍然各只有一份：网格走 `_graph_edge_segments()`（中心对 + `adjacency`，按 tile 对去重）、
##   棋子"该不该画/画成什么色/离位多少"全走 `_stone_paint()`、圆心走 `tile_centers`、
##   半径走 `_graph_stone_r(gap)`（`gap` 由 ① 那一次遍历给出）—— 本函数**不另算任何几何**。
func _draw_graph_mode() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), background_color)
	# 棋盘「盘」：与面模式**同一块板、同一套配色**（图模式没有瓷砖面，盘是唯一的大面积底色
	# ⇒ 网格线与白/黑棋子的对比全部落在它身上）
	_draw_board_panel()
	# ① 网格 = **落子点两两连线**：每个落子点（`tile_centers`）连到它所有**邻格**的中心
	#   （邻接真源 = `adjacency`，与判气/提子/AI 用的是同一份 —— 换棋盘关系这批线自动跟着变）。
	#   面模式那条"同色相邻棋子的共享边不画"是给整块染色用的，图模式棋子是圆的 ⇒ 网格必须完整。
	# ★ 这一次遍历同时得到 `gap` = 全盘**最近落子点间距**，它是图模式棋子直径的唯一基准。
	#   在这里顺带算而不是另起一个函数：网格线与 `gap` 必须**同一批线段**（否则就是两个"最近间距"）。
	var segs: Array = _graph_edge_segments()
	var gap: float = INF
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var d2: float = a.distance_squared_to(b)
		if d2 < gap:
			gap = d2
		draw_line(a, b, line_color, line_width * graph_grid_width_scale)
	gap = 0.0 if is_inf(gap) else sqrt(gap)
	# ② 星位点（立方体盘）：压在网格线上、棋子之下
	var star_tiles: Array[int] = _cube_star_tiles
	if _is_cube and star_tiles.size() > 0 and _min_tile_r > 0.0:
		var star_r: float = maxf(_min_tile_r * 0.16, 2.5)
		var star_col := Color(0.12, 0.12, 0.14)
		for t in star_tiles:
			if t >= 0 and t < tile_centers.size():
				draw_circle(tile_centers[t], star_r, star_col)
	# ④ 终局领地标记（空区归属；那些格上本来就没有棋子）—— 落子点中心的小圆 + 同色邻点连线，
	#   与面模式**同一个实现** `_draw_terr_marks()`，只有"棋子半径"这一项按本画法的口径取。
	#   ★ 图模式里这些连线正好压在棋盘网格上 ⇒ "这片网格归谁"直接看出来，比一堆散点清楚得多。
	if game_over and _terr_mark.size() > 0:
		_draw_terr_marks(_graph_stone_r(gap))
	# 棋子直径**全盘一个数**（`_graph_stone_r(gap)`，理由见那个函数）—— 不看本格大小。
	# ⑤ 落定的棋子（layer 0）。层号语义与面模式**同一个真源** `_stone_paint()`
	#   ⇒「下落的那一手要压在旧棋子上」这条行为由同一套判据覆盖，不是两套。
	for i in range(tiles.size()):
		var p0: Dictionary = _stone_paint(i)
		if not p0["draw"] or int(p0["layer"]) != 0:
			continue
		var c0: Color = p0["col"]
		var o0: Vector2 = p0["off"]
		_draw_round_stone(tile_centers[i] + o0, c0, _graph_stone_r(gap))
	# ⑥ 上一步落子提示：圆棋子中心的小点。
	#   ★ 位置与面模式**同一个层间位置**（落定棋子之后、离位棋子之前）：
	#     落在 ⑤ 之后才不会被刚画的那颗棋子盖掉；而"正在下落的那一手"抬离了本格，
	#     格中心是空的 ⇒ 再画 ⑦ 也不会把它压没（与面模式的相对次序一致）。
	if _last_move != -1 and _last_move < tiles.size() and board[_last_move] != Stone.EMPTY:
		var pm: Dictionary = _stone_paint(_last_move)
		if pm["draw"]:
			var cm: Color = pm["col"]
			var om: Vector2 = pm["off"]
			var dot_col: Color = GameConfig.last_move_dot_color(cm)
			var rm: float = _graph_stone_r(gap)
			draw_circle(tile_centers[_last_move] + om, maxf(rm * 0.30, 2.5), dot_col)
	# ⑦ **离位**的棋子（layer 1：下落中的那一手 + 正在升空散尽的提子）—— 最后画，压在所有盘面标记之上
	for i in range(tiles.size()):
		var p1: Dictionary = _stone_paint(i)
		if not p1["draw"] or int(p1["layer"]) != 1:
			continue
		var c1: Color = p1["col"]
		var o1: Vector2 = p1["off"]
		_draw_round_stone(tile_centers[i] + o1, c1, _graph_stone_r(gap))
	# ⑧ 悬浮预览：同样是**圆**（面模式那块"带侧壁的板"属于整块染色那套表达）
	_draw_graph_hover(gap)
	# ⑨ 屏幕边框（与面模式同一句）
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.3), false, 3.0)


## 图模式圆棋子的**半径** —— 全盘一个数：`最近落子点间距 / 2 × graph_stone_scale`。
##
## ★ **与格无关**（所以没有 `i` 参数）：面模式那颗 `stone_scale` 的口径是"相对本格内切半径"，
##   每格都不同 ⇒ 同一盘里一颗大一颗小；图模式要的是经典棋盘那种观感：**棋子等大**。
## ★ 基准为什么取「最近落子点间距」而不是内切半径：
##   棋盘本身就是落子点连线（见 `_draw_graph_mode()` ①），所以两个落子点之间能摆下的最大圆
##   = 间距的一半。取全盘**最近**的那一对当基准 ⇒ 每颗棋子都摆得下、**永不互相压住**；
##   取中位数/最大内切半径都会在密的地方糊成一片。
## ★ 代价（已知、且是用户选的口径）：Penrose 里最近的相邻对总是瘦菱形那一侧，那里的间距
##   明显小于其它方向 ⇒ 圆子看起来比「占满本格」小一圈，疏的地方缝隙更明显。
##   想更满就拧 `graph_stone_scale`（>1 会开始出现互相压住）。
## ★ `gap <= 0` = 网格没建起来（邻接空 / 屏太小）⇒ 返回 0，`_draw_round_stone()` 直接不画，
##   而不是画出一堆负半径的怪东西。
func _graph_stone_r(gap: float) -> float:
	if gap <= 0.0:
		return 0.0
	return gap * 0.5 * graph_stone_scale


## 领地归属标记的**唯一取色口径**：黑方领地 = 深色点、白方领地 = 白色点。
## ★ 只有这一份：口径原本在面模式 / 图模式两处各写一遍；现在是两个 `@export` 参数
##   （`territory_black_color` / `territory_white_color`，理由与取值见它们的注释）。
func _terr_mark_color(owner: int) -> Color:
	return territory_black_color if owner == Stone.BLACK else territory_white_color


## 领地**连线**的颜色 —— 它不是"点色压暗"，而是**朝与点色相反的方向偏移一档**：
##   浅点（白）压暗、深点（黑）提亮。
##
## ★ 为什么不能像第一版那样统一 `darkened(0.45)`：黑点(0.24)压暗成 0.13 比点本身还深，
##   整片领地看起来是"一坨近黑的网"，反而把点吃了；白点压暗成中灰倒是对的。
##   两边方向相反 ⇒ 一个方向压不过两头。
## ★ 结果：两种领地的线都落在**中灰**附近（深点配浅线、浅点配深线），
##   线与点之间恒有一档差 ⇒ 点看起来像"被线框住"，网格整体也统一成灰色，不与棋子抢眼。
func _terr_link_color(owner: int) -> Color:
	var c: Color = _terr_mark_color(owner)
	var out: Color = c.darkened(0.35) if c.get_luminance() > 0.5 else c.lightened(0.30)
	out.a = 0.85
	return out


## 画**一整片领地标记** —— 面模式与图模式**共用的唯一实现**（2026-10-20 用户口令
## 「终局领地描边改为落子点中心圆形标记」+「这个点有点太小了，然后再连接一下吧，
## 参考腾讯围棋的标点方法」）。
##
## 画法 = 腾讯围棋的标点法：每个落子点一颗**圆点** + 同一片领地**相邻点之间连线**。
##   只画点的话整盘是一堆散点，"成不成片"看不出来；把同色邻点串起来，一片地就是一张网，
##   势力边界就是网与网之间那道**天然断口**（不需要额外描边）。
##
## ★ `stone_r` 由调用方传，**不在本函数里判断画法**：两套的棋子半径量纲不同
##   （面模式 `_stone_px()` 逐格各不同、图模式 `_graph_stone_r(gap)` 全盘一个数），
##   在这里 `if graph_mode` 一次就又长出两套口径 —— 传参让"哪个半径"留在**画法那一侧**。
## ★ 连线只连**同色**领地的邻格，邻接真源仍是 `adjacency`（与判气 / 提子 / AI 同一份）。
## ★ 连线色走 `_terr_link_color()`（**朝点色的反方向**偏移一档：深点配浅线、浅点配深线），
##   不是"点色统一压暗"。理由见那个函数 —— 统一压暗会让黑线比黑点还深，把点吃掉；
##   而白线不压暗则在米白底上整个消失（实测第一版裸画白圆，右半盘一个点都看不见）。
##   两条约束方向相反，所以只能按亮度分支。
## ★ 分**两遍**画：先全部连线、再全部圆点 —— 否则后画的线横穿先画好的圆点，交点处一圈缺口。
## ★ 连线宽度跟着点半径走（`× 0.22`），不单开参数：腾讯那套里线就是"把点串起来的细线"，
##   点放大线跟着略粗才对；多一个旋钮只会让人忘了调。
## ★ 半径下限 2px：小盘 / 缩得很小的窗口下点会退到像素级，看不见就等于没标。
func _draw_terr_marks(stone_r: float) -> void:
	var dot_r: float = maxf(stone_r * territory_dot_scale, 2.0)
	var link_w: float = maxf(1.5, dot_r * 0.22)
	var seen := {}
	# ① 连线（同色领地的相邻落子点之间）—— 去重键与网格线同一套 min*1e6+max
	for tid in _terr_mark:
		var t: int = int(tid)
		if t < 0 or t >= tile_centers.size() or t >= adjacency.size():
			continue
		var owner: int = int(_terr_mark[t])
		var link_col: Color = _terr_link_color(owner)
		for nb in adjacency[t]:
			var j: int = int(nb)
			if not _terr_mark.has(j) or int(_terr_mark[j]) != owner:
				continue
			var key: int = mini(t, j) * 1000000 + maxi(t, j)
			if seen.has(key):
				continue
			seen[key] = true
			draw_line(tile_centers[t], tile_centers[j], link_col, link_w)
	# ② 圆点（压在连线之上）
	for tid in _terr_mark:
		var t2: int = int(tid)
		if t2 < 0 or t2 >= tile_centers.size():
			continue
		_draw_round_stone(tile_centers[t2], _terr_mark_color(int(_terr_mark[t2])), dot_r)


## 图模式的**网格线**唯一真源：每个落子点（`tile_centers`）与它**相邻**落子点的连线，
## 按 tile 对**去重**后返回 `[[起点中心, 终点中心], ...]`。
##
## ★ 顶点 = 瓷砖中心、边 = `adjacency` 里的一条邻接关系 ⇒ 这张网格就是「落子点连线」本身。
##   它和面模式那套「瓷砖边」是两个**不同**的东西，别混：
##     · 面模式（`_drawn_edge_segments(i)`）：线是砖缝，圈出来的是**瓷砖轮廓**；
##     · 图模式（本函数）：线是棋盘，连的是**落子点** —— 玩家看到的每一格由「中心 + 连线」围成。
##   邻接用的就是判气 / 提子 / AI 那一份 `adjacency`（自检⑰守它对称）⇒ 棋盘关系没有第二个副本。
## ★ 去重键 = `min*1000000 + max`（与 `_edge_neighbor` 同一套）：邻接是**对称**的，
##   不去重每条内部线会画两遍 —— `line_color` 带 alpha（默认 0.68~0.70）叠加后内部线明显更深，
##   一眼就看得出"网格深浅不匀"。
## ★ 不依赖 `tiles` 的顶点环序（面模式那套要 `pts[k]` 与 `tvs[k]` 下标对齐），只依赖中心 + 邻接。
func _graph_edge_segments() -> Array:
	var out: Array = []
	var seen := {}
	var n_tiles: int = tile_centers.size()
	for i in range(n_tiles):
		if i >= adjacency.size():
			break
		for nb in adjacency[i]:
			var j: int = int(nb)
			if j < 0 or j >= n_tiles:
				continue
			var key: int = mini(i, j) * 1000000 + maxi(i, j)
			if seen.has(key):
				continue
			seen[key] = true
			out.append([tile_centers[i], tile_centers[j]])
	return out


## 画一颗**带描边的圆** —— 图模式的圆棋子与**两套画法的领地标记**共用这一个实现。
## ★ 实现本体在 `board_panel.gd::BoardPanel.round_stone()`：设置页预览的图模式也要画同样的圆，
##   两份会漂（"所见即对局所得"就断了）。本函数保留成薄转发**是为了调用点零改动**
##   （`_draw_graph_mode()` / `_draw_terr_marks()` 里那几处都是守卫锚点）。
func _draw_round_stone(c: Vector2, col: Color, r: float) -> void:
	BoardPanel.round_stone(self, c, col, r)


## 图模式的悬浮预览：一颗抬离盘面的圆棋子（抬离高度读 `_hover_preview_state()`，
## 与面模式**同一个真源** —— 面模式用它的 `off` 抬整块砖，这里抬圆心）。
## ★ `gap` 由 `_draw_graph_mode()` ① 那次遍历算好后传进来（棋子直径的唯一基准），
##   这里**不许**自己再求一次最近间距 —— 那就是第二个"最近落子点间距"了。
func _draw_graph_hover(gap: float) -> void:
	if not _hover_preview_visible():
		return
	if _hover_tile < 0 or _hover_tile >= tile_centers.size():
		return
	var st: Dictionary = _hover_preview_state()
	var off_h: Vector2 = st["off"]
	var c: Color = piece_color_black if current_player == Stone.BLACK else piece_color_white
	c.a = st["alpha"]
	_draw_round_stone(tile_centers[_hover_tile] + off_h, c, _graph_stone_r(gap))


## 绘制指定瓷砖的 4 个顶点位置
func _tile_points_for_draw(i: int) -> PackedVector2Array:
	var tile: Array = tiles[i]
	var pts := PackedVector2Array()
	for idx in tile:
		pts.push_back(vertices[idx])
	return pts


## 第 `i` 格**实际会画出来**的瓷砖边线段（`[[起点, 终点], ...]`）—— `_draw()` 与自检⑨共用。
## ★ 抽出来是必须的：⑨ 要量"离位的那块砖被哪几条边线从内部划过"，如果自检自己再写一遍
##   「同色相邻棋子的共享边不画」这条规则，量到的就不是画面上那几条线
##   （§真源唯一 —— 判据另抄一份 = 没测那一份）。
func _drawn_edge_segments(i: int) -> Array:
	var out: Array = []
	var points := _tile_points_for_draw(i)
	var tvs: Array = tiles[i]
	var n := points.size()
	for k in n:
		var a: int = tvs[k]
		var b: int = tvs[(k + 1) % n]
		var nb: int = _edge_neighbor.get(mini(a, b) * 1000000 + maxi(a, b), -1)
		if nb >= 0 and board[i] != Stone.EMPTY and board[i] == board[nb]:
			continue
		out.append([points[k], points[(k + 1) % n]])
	return out


## 多边形包围盒（自检用；`Rect2(顶点[0], ZERO)` + expand 的惯用法抽成一处）
func _poly_bbox(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	return bb


## 线段 (a,b) 的**中点**是否含在 poly 内部、且离边界 > `margin` 像素 ——
## 也就是"这条线从这块砖**里面**穿过去、肉眼看得见"（自检⑨的原子操作）。
## ★ 为什么用中点而不是求交长度：`Geometry2D` 没有对任意多边形都稳定的折线裁剪，
##   而"中点深在内部"这个口径**单调**且好解释 —— 它就是用户看到的那道划痕。
## ★ `margin` 是关键：边线**恰好压在边界上**时（h=0 的静止棋子）不算穿过，
##   否则静止棋子也会被数成"被遮挡"，判据就分不出"抬离才出问题"这个事实。
func _seg_crosses_poly(a: Vector2, b: Vector2, poly: PackedVector2Array, margin: float) -> bool:
	var mid := (a + b) * 0.5
	if not Geometry2D.is_point_in_polygon(mid, poly):
		return false
	return _dist_to_boundary(mid, poly) > margin


## 线段 (a,b) 的包围盒是否与 rect 相交（自检⑨的**剪枝**：全盘 N 块 × M 条边线，
## 不做剪枝在 300 块的盘上会跑几秒；剪枝后剩下的才做多边形点测试）
func _seg_bbox_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var sbb := Rect2(minf(a.x, b.x), minf(a.y, b.y), absf(a.x - b.x), absf(a.y - b.y))
	return r.intersects(sbb)


## --screenshot --shotcap[=drop|fade]：构造「黑提白一子」的真实提子局面再截 ——
## 验证「落子下落 → 提子升空淡出」两段**串行**这件事（2026-10-20 起与瓷砖碎裂无关，
## 碎裂效果已整套删除；本夹具保留是因为它造的是**真实提子局面**，`--hovertest` ⑥ 也复用它）。
## 这类**只在提子后存在一瞬**的视觉效果，人工下棋截不到（AI 下一手立刻清掉标记）。
## 做法：找一块居中瓷砖 T 白占，黑占其全部邻居但留一个口 P，黑下 P → 真实走
## place_stone(animate=true) 提掉 T → ko_point 指向 T 且不再有下一手 → 标记稳定可见。
func _setup_shot_capture() -> void:
	reset_game(true)
	var best := -1
	var best_d := 1.0e18
	var vc := get_viewport_rect().size * 0.5
	for i in tiles.size():
		var dd: float = tile_centers[i].distance_squared_to(vc)
		if dd < best_d:
			best_d = dd
			best = i
	if best < 0:
		return
	var nbs: Array = adjacency[best]
	board[best] = Stone.WHITE
	for j in range(1, nbs.size()):
		board[nbs[j]] = Stone.BLACK
	current_player = Stone.BLACK
	place_stone(nbs[0], true)
	# ★ 把**被提的那一格**（= 提子动画的主角）与**刚落的那一格**的砖心/包围盒打出来：
	#   审 A/B 差分图时要把差异区换算成文件像素后**叠回来对账**，光看形状认物件会认错
	#   （`--shotdrop` 那次就白烧过一轮，见技能 §7.6 J.4）。画布 → 文件像素的倍率 =
	#   窗口宽 / 画布宽（本工程截图取的是物理窗口）—— 用公共的 `_shot_scale()`，别就地再算一份。
	var mul: float = _shot_scale()
	for pair in [["被提格(提子主角)", best], ["刚落格(带最后一手点)", nbs[0]]]:
		var tid: int = pair[1]
		var pts := _tile_points_for_draw(tid)
		var bb := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bb = bb.expand(p)
		print("[shotcap]   %s t%d 砖心%s 包围盒%s（逻辑坐标；×%.2f = 截图文件像素）" % [
			pair[0], tid, str(tile_centers[tid]), str(bb), mul])
	print("[shotcap] 冻结档位=%s（drop=落子半途/提子还没轮到；fade=提子升空淡出半途）" % _shot_freeze_phase())
	# ★ 必须冻结动画：`_capture_and_quit()` 要等 2 秒（等开场淡入），而落子/提子各只有
	#   `STONE_ANIM_TIME`(0.3s) —— 不冻结的话截到的永远是"两段都跑完了"，
	#   这张截图对动画这件事等于没测（同 `--shotdrop` 的道理）。
	#   ★★ **两档缺一不可**（`--capfreeze=`）：这是**两件不同的观感**，一张图只能证一件 ——
	#     `drop` = 落子下落半途，且被提的子**还没轮到**（原样停在原格）⇒ 证「两段串行」
	#     `fade` = 提子升空淡出半途（默认）                    ⇒ 证「向上平移淡出」
	#   只截 fade 的话，"提子排在落子之后"这件事**在图上完全看不出来**。
	#   ★★ 两档都是**真的调 `_process()` 把时间推过去再冻结**，而不是手写动画字段 ——
	#      手写状态会被"照抄一份公式"骗过去：A/B 对照里把 `delay` 改成 0（= 并排跑）时，
	#      手写 `time_left=满` 会让改坏的那一版也显示"没动"，两张图**逐像素相同**，
	#      等于这一刀什么都没测。走真 `_process` 才分得出来（见技能 §7.6 J.2）。
	#   只影响 `--screenshot` 路径（`--hovertest` ⑥ 也调本函数造劫局，别给它加冻结：
	#   冻结会让 `_process` 提前返回，那边的穷举对照会读到不推进的动画状态）。
	if "--screenshot" in _argv() and _capture_anims.size() > 0:
		var phase := _shot_freeze_phase()
		# 推进到想看的时刻：drop = 落子走一半；fade = 落子走完 + 提子再走一半
		_process(STONE_ANIM_TIME * (0.5 if phase == "drop" else 1.5))
		_anim_freeze = true


## `--shotwave` 造的龙长（格）。8 格在标准盘上约 3~4 层可见梯度（层数由龙的实际走向决定，
## 不是本值本身 —— 龙拐弯时"离落点"的图距离会比格数短）。
const SHOT_WAVE_LEN: int = 8

## --screenshot --shotemote：**两条侧抽屉 + 两个头像上的表情**（2026-10-21，10-22 改版）。
## ★ 这一档**只为一件事存在**：自绘图形（脸 / 心 / 星）的好坏没有任何断言能抓 ——
##   线宽在 52px 格子里糊不糊、心形缩放后是不是被压扁、"淡底的脸"会不会和底板混成一片，
##   全是"看着不对但全部判据都绿"。⇒ 必须真窗口截一张，用眼睛看。
## ★ 为什么把寿命直接推到 999 秒而不是加一个"截图保持"开关：
##   `_tick_emote_bubbles()` 是生产逻辑，为截图加一条 `if _shot_hold: return` 就等于
##   在生产路径里插一个**只有截图会走到的分支**（那类分支没人测，改坏了也不知道）。
##   把寿命设大是纯数据操作，走的还是同一条 tick（alpha 恒 1.0，因为 999/0.45 > 1）。
func _setup_shot_emote() -> void:
	game_mode = ONLINE
	_net_color = Stone.BLACK
	_net_connected = true
	_net_phase = "playing"
	_ready_set = {Stone.BLACK: true}
	if _drawer_layer == null or not is_instance_valid(_drawer_layer):
		_build_drawers()
	_refresh_net_extras()
	_refit_drawers()
	# 自己 → 比心（多边形填充那条分支）；对端 → 大笑（弧 + 填充半圆那条分支）
	_play_emote(0, 6)
	_play_emote(1, 1)
	_emote_bubble_left[0] = 999.0
	_emote_bubble_left[1] = 999.0
	_redraw_identity()
	# ★ 2026-10-22：这张图现在同时拍到三样东西 —— 左抽屉（两个头像：上面对端"大笑"、
	#   下面自己"比心"）、8 个表情格、右抽屉按键列，而**棋盘上一个遮挡物都没有**。
	#   "表情有没有压到盘上"一眼可判（这正是 `--drawertest` / `--emotetest` 的判据管不到
	#   的部分：判据只量矩形与计数，看不出"看着挤不挤"）。
	print("[shotemote] 身份条 自己=%s 对端=%s｜头像上表情 idx=(%d,%d)｜表情格 %d 格｜抽屉带宽 %s" % [
		_display_name_for(0), _display_name_for(1),
		_emote_bubble_idx[0], _emote_bubble_idx[1], Emotes.count(), str(drawer_bands())])


## --screenshot --shotwave：造一条**长龙**，一手提掉它，然后冻在"波前"途中。
## ★★ 为什么要单独一档：用户口令里"从贴着刚落那手的子开始、接着它旁边的子、依次提完"这件事
##   是**一串时刻上的顺序**，单张静态图本来证不了。但冻在途中就有办法：**同一帧里**近端已经散尽、
##   中段半透明、远端还完全没动 —— 那条"从近到远的亮度梯度"就是顺序本身被拍下来了。
##   （等价于给时间轴做了一次空间切片，同 §7.6 O"一处观感一张图"的思路。）
## 做法：① 从盘心附近走一条**尽量直**的路径（每步挑"方向最接上前一步"的邻居）当白龙；
##   ② 把它**所有**气封成黑子、只留一个当最后一口气；③ 黑下那一口气 → 真实 `place_stone()`
##   把整条龙提掉（分层/摊开全走真代码，不手工写动画字段 —— 手写会被"照抄公式"骗过去）。
func _setup_shot_wave() -> void:
	reset_game(true)
	var vc: Vector2 = get_viewport_rect().size * 0.5
	var start := -1
	var best_d := 1.0e18
	for i in tiles.size():
		var dd: float = tile_centers[i].distance_squared_to(vc)
		if adjacency[i].size() >= 3 and dd < best_d:
			best_d = dd
			start = i
	if start < 0:
		return
	# ① 尽量直的路径：第一步随便挑（取邻居里离盘心最近的），之后每步取"方向最接上前一步"的邻居。
	#    ⚠️ 贪心直线可能走进死角 ⇒ 长度不够就**接受**（够长即可，别为凑数把龙绕成一团）。
	var path: Array[int] = []
	var used: Dictionary = {}
	var cur: int = start
	var heading: Vector2 = Vector2.ZERO
	for _step in SHOT_WAVE_LEN:
		path.append(cur)
		used[cur] = true
		var nxt := -1
		var best_score := -1.0e18
		for nb in adjacency[cur]:
			if used.has(nb):
				continue
			var dir: Vector2 = (tile_centers[nb] - tile_centers[cur])
			if dir.length_squared() < 0.0001:
				continue
			dir = dir.normalized()
			var sc: float = 1.0e6 if heading == Vector2.ZERO else dir.dot(heading)
			if sc > best_score:
				best_score = sc
				nxt = nb
		if nxt < 0:
			break
		heading = (tile_centers[nxt] - tile_centers[cur]).normalized()
		cur = nxt
	if path.size() < 3:
		_anim_freeze = true
		return
	for t in path:
		board[t] = Stone.WHITE
	# ② 封气：路径以外的邻居全封黑，只留一个当"最后一口气"
	var libs: Array[int] = []
	for t in path:
		for nb in adjacency[t]:
			if not used.has(nb) and board[nb] == Stone.EMPTY and not libs.has(nb):
				libs.append(nb)
	if libs.is_empty():
		_anim_freeze = true
		return
	var liberty: int = libs[0]          # 挑"第一口气"（= 贴着路径起点那一端，画面上最自然）
	for i in range(1, libs.size()):
		board[libs[i]] = Stone.BLACK
	# ③ 真实提子（分层 + 摊开起手时刻全走 `place_stone()` 真路径）
	current_player = Stone.BLACK
	place_stone(liberty, true)
	if _capture_anims.is_empty():
		_anim_freeze = true
		return
	# 冻结时刻取**摊开窗口的 45%**：此时第 0 层已散掉大半、中段半透明、深层还没起手。
	if "--screenshot" in _argv():
		_process(_capture_delay() + (_capture_total_time() - STONE_ANIM_TIME) * 0.45)
		_anim_freeze = true
	_shot_wave_report(path, liberty)


## `--shotwave` 的证据打印：把"波前真的存在"变成**数字**，别只靠看那张图。
## 逐层报出颗数与**该层此刻的 alpha 区间**（问的是 `_stone_paint()` —— `_draw()` 画的就是它）。
## 判据形态两条（⚠️ 第一版把第一条写成"严格递增"，结果**误报** —— 实测层4~7 都还没起手、
## alpha 全是 1.00，那是正确的"排队等"，不是顺序没做出来）：
##   ① **非降**：层号越大，该层"最不透明的那颗"alpha 不能**更小**（越靠外的越没动）；
##   ② **真有梯度**：至少有一对相邻层的 alpha 不同（全是 1.00 ⇒ 就是"齐提"，波前没做出来）。
func _shot_wave_report(path: Array[int], liberty: int) -> void:
	var by_wave: Dictionary = {}
	for k in _capture_anims.keys():
		var w: int = int(_capture_anims[k].get("wave", 0))
		if not by_wave.has(w):
			by_wave[w] = []
		by_wave[w].append(k)
	var waves: Array = by_wave.keys()
	waves.sort()
	var txt: Array = []
	var prev_hi := 2.0
	var mono := true
	var graded := false
	for w in waves:
		var lo := 2.0
		var hi := -1.0
		for k in by_wave[w]:
			var a: float = float(_stone_paint(k)["col"].a)
			lo = minf(lo, a)
			hi = maxf(hi, a)
		txt.append("层%d×%d α[%.2f,%.2f]" % [w, (by_wave[w] as Array).size(), lo, hi])
		# ① 非降（允许相等：深层还没起手 ⇒ 整层 alpha 恒 1.00，是"排队等"）
		if hi < prev_hi - 0.001 and prev_hi <= 1.0:
			mono = false
		if prev_hi <= 1.0 and hi > prev_hi + 0.001:
			graded = true
		prev_hi = hi
	var wave_ok: bool = mono and graded
	print("[shotwave] 龙长 %d 格｜最后一口气 t%d 砖心%s（第 0 层就该贴着它）｜波前 %d 层｜起手延迟 %.2fs + 摊开 %.2fs｜梯度非降 %s｜真有梯度 %s ⇒ %s" % [
		path.size(), liberty, str(tile_centers[liberty].round()), waves.size(), _capture_delay(),
		_capture_total_time() - STONE_ANIM_TIME, "✓" if mono else "✗", "✓" if graded else "✗",
		"波前可见 ✓" if wave_ok else "失败 ✗（波前没做出来）"])
	print("[shotwave] %s" % " ｜ ".join(txt))
	var mul: float = _shot_scale()
	print("[shotwave] 结束时刻最晚那颗 = %.2fs（封顶 %.2fs）" % [
		_capture_end_time(waves[waves.size() - 1] if waves.size() > 0 else 0,
			waves[waves.size() - 1] if waves.size() > 0 else 0),
		_capture_delay() + _capture_total_time()])
	var keys: Array = _capture_anims.keys()
	keys.sort_custom(func(a: int, b: int) -> bool:
		return int(_capture_anims[a].get("wave", 0)) < int(_capture_anims[b].get("wave", 0)))
	for k in keys:
		var pts := _tile_points_for_draw(k)
		var bb := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bb = bb.expand(p)
		print("[shotwave]   t%d 层%d 砖心%s 包围盒%s（逻辑坐标；×%.2f = 截图文件像素）" % [
			k, int(_capture_anims[k].get("wave", 0)), str(tile_centers[k].round()), str(bb), mul])


## 截图冻结档位（`--capfreeze=drop|fade`，默认 fade）：只给 `--shotcap` 用。
## 为什么不合成一档：`drop` 那一帧要"提子**还没动**"，`fade` 那一帧要"提子**动到一半**"，
## 二者互斥 ⇒ 必须分两档，否则两件观感里总有一件没有图可证。
func _shot_freeze_phase() -> String:
	for a in _argv():
		if a.begins_with("--capfreeze="):
			return a.substr("--capfreeze=".length())
	return "fade"


## --screenshot --shotdrop：定格「鼠标悬浮预览 + 另一格棋子正落到半途」。
## 为什么必须冻结（`_anim_freeze`）：`_capture_and_quit()` 要等 2 秒（等开场淡入结束）才截，
## 而 `STONE_ANIM_TIME` 只有 0.3 秒 —— 不冻结的话下落早跑完了，截到的永远是「已落定」，
## 这个自检就等于没测。做法：① 落点起手后把剩余时长改成半途（= 空中那块砖），
## ② 另挑一块不重叠的居中空砖挂上 `_hover_tile`（= 悬浮预览鬼影），一张图同时看到两者。
## ⚠️ 只影响截图路径，正常对局永远不会置 `_anim_freeze`。
func _setup_shot_drop() -> void:
	reset_game(true)
	var center: Vector2 = get_viewport_rect().size * 0.5
	var order: Array[int] = []
	for i in tiles.size():
		order.append(i)
	# 按「离屏幕中心近」排序 —— 截出来的东西必须在画面中央才方便目检
	order.sort_custom(func(a: int, b: int) -> bool:
		return tile_centers[a].distance_squared_to(center) < tile_centers[b].distance_squared_to(center))
	if order.size() < 2:
		_anim_freeze = true
		return
	# 落点：取最近的、邻居 ≥3 的砖（多边形越饱满，"这是一块砖"越看得出来）
	var drop_tile: int = order[0]
	for i in order:
		if adjacency[i].size() >= 3:
			drop_tile = i
			break
	# 悬浮格：离落点足够远、两块不重叠，才看得清是两个东西
	var hover_tile: int = -1
	for i in order:
		if i != drop_tile and tile_centers[i].distance_to(tile_centers[drop_tile]) > _min_tile_r * 3.0:
			hover_tile = i
			break
	current_player = Stone.BLACK
	# ★ 「遮挡者」：在落点**正上方**、且**瓷砖序号比落点大**的那块砖上先摆一颗黑子。
	#   这是用户报的「落子被已有棋子遮挡」的**确切条件** —— 一遍写法按瓷砖序号画，
	#   序号大的后画 ⇒ 上方那颗旧子会盖住抬到空中的这一手（序号小的方向则不会，所以
	#   用户看到的是"有概率"）。摆上它，这一张截图才能**目检 z 序**，否则拍到的永远是
	#   一块孤零零的空中砖，修没修都长一个样（= 这个截图自检没测这件事）。
	#   ★★ 必须按**多边形真实重叠面积**挑，不能按"中心在上方"挑：与落点共享**竖直边**的
	#     侧邻砖，被竖直上抬的砖是"沿着那条边滑动" —— 重叠面积恒为 0（实测：按中心挑出来的
	#     t92 就属于这种，A/B 两张图**逐像素相同**，等于这一刀什么都没测到）。
	#     判据用 `Geometry2D.intersect_polygons` 的真实交面积，取面积最大者 ⇒ 保证"看得见"。
	var up := Vector2(0.0, -_drop_height())
	var raised := PackedVector2Array()
	for p in _tile_points_for_draw(drop_tile):
		raised.push_back(p + up)
	var blocker: int = -1
	var best_area := 0.0
	for i in tiles.size():
		if i == drop_tile or board[i] != Stone.EMPTY or i <= drop_tile:
			continue                       # 序号必须**比落点大**：旧写法才会被它压住
		var inter := Geometry2D.intersect_polygons(raised, _tile_points_for_draw(i))
		for poly in inter:
			var area := 0.0
			for k in poly.size():
				var va: Vector2 = poly[k]
				var vb: Vector2 = poly[(k + 1) % poly.size()]
				area += va.x * vb.y - vb.x * va.y
			area = absf(area) * 0.5
			if area > best_area:
				best_area = area
				blocker = i
	# ★ 预览色 = 当前回合方。默认黑（鬼影与落子同色 ⇒ 一张图就能对「预览==下落起手」下结论）。
	#   `--whitepreview` 切白：**白子的侧壁是浅色**，"背后的棋盘边界透出来"在白子上最扎眼
	#   （用户 2026-09-29 报的正是白子）—— 没有这个开关，那条只能拿**黑子**截图目检：
	#   黑子侧壁 ≈ 深色棋盘色，压上去几乎看不出差别 ⇒ 图上是"什么都好"，等于没测。
	#   ⚠️ 切白时遮挡者必须跟着换成黑（下面那条注释的对比度要求对**任意一对**颜色都成立）。
	var preview_color: int = Stone.WHITE if "--whitepreview" in _argv() else Stone.BLACK
	if blocker >= 0:
		# ★★ 遮挡者必须是**对面颜色** —— 这一条是 A/B 能不能拍出差异的**全部关键**：
		#   同色时，"半透明 X 压在实心 X 上"与"实心 X 压在 X 上"**逐像素相同**，
		#   改没改画序图都长一个样（实测过：对调后 A/B 差分 = 0 像素、采样色完全相同）。
		#   对面色才有对比：错的时候对面色把落子的上半截**咬掉**，对的时候落子压在它上面。
		#   这也正是用户看得见遮挡的真实场景（旧子多为对方色）。
		board[blocker] = Stone.BLACK if preview_color == Stone.WHITE else Stone.WHITE
	current_player = preview_color
	place_stone(drop_tile, true)
	# ★★ 落子会**把回合翻给对面** ⇒ 预览鬼影（取色 = `current_player`）会与刚落那一手**不同色**。
	#   原版没有这个问题，纯粹因为它把 `current_player = Stone.BLACK` 写在 `place_stone()`
	#   **之后**——那是**隐式**抵消；2026-09-29 加 `--whitepreview` 时把赋值挪到前面，
	#   语义当场就反了（实测取样：默认档的鬼影是**白**的、`--whitepreview` 档反而是黑的）。
	#   ⇒ 两处都显式写：`board[drop_tile]` 才是下落那一手取色的真源（`_stone_paint()` ① 读它），
	#     直接赋值，不再依赖 `place_stone()` 内部的回合行为。
	current_player = preview_color
	board[drop_tile] = preview_color
	# 冻在 45%：既明显离开了落点（看得出在空中），又还没贴身（看得出是同一块砖）
	_place_anims[drop_tile] = STONE_ANIM_TIME * 0.45
	_hover_tile = hover_tile
	_anim_freeze = true
	print("[shotdrop] 落点 t%d（动画冻在 %.2fs / 共 %.2fs）｜悬浮预览 t%d｜遮挡者 t%d 重叠面积 %.0fpx²（>0 = 旧写法下它必然盖住落点）｜悬浮/下落高度 %.1fpx｜砖内切半径 %.1fpx｜预览色=%s 落子色=%s（必须一致，`--whitepreview` 可切白）"
		% [drop_tile, _place_anims[drop_tile], STONE_ANIM_TIME, hover_tile, blocker, best_area, _drop_height(), _min_tile_r,
			"黑" if preview_color == Stone.BLACK else "白",
			"黑" if board[drop_tile] == Stone.BLACK else "白"])
	# 三块相关砖的**砖心 + 包围盒**（逻辑坐标）也打出来：审"截图里那块灰的是谁"时靠它叠回对账。
	# ★ 别靠"看形状猜哪块是哪块" —— 本轮就栽在这上面：把落点/遮挡者/鬼影认错了位置，
	#   A/B 差分明明指出了差异区，却被我读成了另一个对象（多花了一轮）。
	for pair in [["落点", drop_tile], ["遮挡者", blocker], ["悬浮预览", hover_tile]]:
		var tid: int = pair[1]
		if tid < 0:
			continue
		var pts := _tile_points_for_draw(tid)
		var bb := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			bb = bb.expand(p)
		print("[shotdrop]   %s t%d 砖心%s 包围盒%s（逻辑坐标；×%.2f = 截图文件像素）"
			% [pair[0], tid, str(tile_centers[tid].round()), str(bb), _shot_scale()])
	# 悬浮预览的**侧壁几何**也打出来：审"截图里有没有那块厚度"时靠它**叠回截图对账**
	#（§7.5 的纪律：看不清就用数据判，别拿眼睛在放大图上找几 px 的面）。
	var wall_txt: Array = []
	for q in _hover_side_walls():
		wall_txt.append("%s→%s" % [str((q[0] as Vector2).round()), str((q[2] as Vector2).round())])
	print("[shotdrop] 预览侧壁 %d 面（逻辑坐标，截图文件坐标 = ×%.2f）：%s"
		% [wall_txt.size(), _shot_scale(), " ｜ ".join(wall_txt)])
	# ★★ 2026-09-29 用户报「落子时棋子被**棋盘边界线**遮挡，白子尤为明显」——
	#   这一张截图是**唯一能同时看到"停在空中那块砖"和"抬起的预览块"的帧**，
	#   所以把"这两块各被几条**真会画**的瓷砖边线从内部穿过"打出来：
	#   A/B 差分图里那几道划痕落在哪一格、是谁划的，靠这组数字叠回对账（别拿眼睛在放大图上找）。
	#   ⚠️ 这一组是**几何量**：改画序前后**数值不变**（变的是"谁盖住谁"）。
	#      能自证"修好了"的只有结构判据 S9 与 A/B 差分本身（`ab_mut.py` 的 `dropline` job）。
	var lum_line2: float = line_color.get_luminance()
	for pair in [["落点抬离块", raised, board[drop_tile]],
			# ★ 预览的取色必须读**当前回合方**（原来是硬写的 `Stone.BLACK`）—— 否则
			#   `--whitepreview` 下这行对比度是按黑子算的，与画面上那块白板对不上（静默不一致）。
			["预览抬离块", _shifted_poly(hover_tile, _drop_height()), current_player]]:
		var poly: PackedVector2Array = pair[1]
		if poly.is_empty():
			continue
		var pbb: Rect2 = _poly_bbox(poly)
		var hitn := 0
		for j in tiles.size():
			for s in _drawn_edge_segments(j):
				if _seg_bbox_hits(s[0], s[1], pbb) and _seg_crosses_poly(s[0], s[1], poly, 1.0):
					hitn += 1
		var cbl: Color = piece_color_black if int(pair[2]) == Stone.BLACK else piece_color_white
		print("[shotdrop] %s 被 %d 条瓷砖边线从内部穿过（边线亮度 %.2f vs 块色 %.2f ⇒ 差 %.2f；0 条 = 这一块没被划）"
			% [pair[0], hitn, lum_line2, cbl.get_luminance(),
				absf(lum_line2 - cbl.get_luminance())])


## 把第 `i` 格的多边形整体上移 `h`（自检/截图报告用的几何助手）
func _shifted_poly(i: int, h: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if i < 0 or i >= tiles.size():
		return out
	for p in _tile_points_for_draw(i):
		out.push_back(p + Vector2(0.0, -h))
	return out

## 截图文件像素 / 视口逻辑像素 的比值（窗口 1.5× 缩放时 = 1.5）：把引擎坐标叠回截图要用它
func _shot_scale() -> float:
	var v: Vector2 = get_viewport_rect().size
	return float(DisplayServer.window_get_size().x) / maxf(v.x, 1.0)


## 自检（--hovertest）：悬浮预览 + 落子下落（2026-09-29 用户口令「鼠标悬浮出现半透明瓷砖、
## 落子就是这块预览向下落下」）。
##
## 八条判据，**每条都走真实代码路径**（不另抄一份公式），并且刻意做了「跨处一致性」交叉断言：
##  ① 悬浮格跟随：格心 → 该格；盘外 → -1
##  ② 真实事件路径：合成 `InputEventMouseMotion` 经 `push_input` 走 `_input` 分支
##     —— 钉死「事件坐标 == 顶点坐标」这套口径（若被改成窗口坐标，这条立刻红）
##  ③ 准入门槛：预览可见性必须与 `_place_block_reason()` 同向（终局 / AI 思考 / 已占格都不亮）
##  ④ 棋理判据 vs 落子真源**穷举对照**：每个空点同时跑 `can_place_at()` 与真 `place_stone()`，
##     逐格比结论（全量快照 + 回滚）—— 防「预览说有戏、点下去没反应」及其反向
##  ⑤ 自杀点：造一个「邻居全白、白环外侧有气」的局面，断言两套口径都拒，而**朴素口径**
##     （只看「是不是空点」）会放行 → 证明这套判据真的在起作用（有牙齿）
##  ⑥ 劫点：复用 `--shotcap` 的提子局面构造出真劫，断言禁着（同上，朴素口径会放行）
##  ⑦ **预览与下落同貌**（本轮需求的硬不变量）：`_hover_preview_state()` 必须逐位等于
##     `_place_drop_state(0.0)`；`k=1` 必须落定；中间帧确实在空中；高度参数确实被读到
##  ⑧ **预览侧壁**（厚度感）：面数/每个面的四点位置，附三条对照（门槛同源、参数敏感、厚度可见）
##     （门槛同源：已占格给 0 条；参数敏感：抬高量 ×3 时线长跟着变）
func _hover_test() -> void:
	var ok := true
	reset_game(true)
	if tiles.is_empty():
		print("[hovertest] 结论：失败 ✗ 棋盘未生成")
		get_tree().quit()
		return

	# ---------- ① 悬浮格跟随 ----------
	# 挑 6 块彼此离得远的砖（固定顺序遍历，必然含盘边缘的），格心必须命中自己
	var probe: Array[int] = []
	for i in tiles.size():
		var far_enough := true
		if not probe.is_empty():
			far_enough = tile_centers[i].distance_to(
				tile_centers[probe[probe.size() - 1]]) > _min_tile_r * 5.0
		if far_enough:
			probe.append(i)
		if probe.size() >= 6:
			break
	var follow_bad := 0
	for i in probe:
		_update_hover(tile_centers[i])
		if _hover_tile != i:
			follow_bad += 1
	_update_hover(Vector2(-500.0, -500.0))          # 盘外（视口外，四周还留 40px 边距）
	var far_ok: bool = _hover_tile == -1
	var follow_ok: bool = follow_bad == 0 and far_ok
	print("[hovertest] ① 悬浮格跟随 %s（6 块抽样错 %d 格；盘外点→-1 %s）"
		% ["✓" if follow_ok else "✗", follow_bad, "✓" if far_ok else "✗"])
	if not follow_ok:
		ok = false

	# ---------- ② 真实事件路径（坐标口径） ----------
	# 先置成不可能的值：证明 `_hover_tile` 是**这个事件**改的，而不是上一步的残留
	_hover_tile = -2
	var xf: Transform2D = get_viewport().get_final_transform()
	var mv := InputEventMouseMotion.new()
	mv.position = xf * tile_centers[probe[0]]       # 与 `_hat_click_probe` 同一套补偿口径
	mv.global_position = mv.position
	get_viewport().push_input(mv)
	await get_tree().process_frame
	var real_ok: bool = _hover_tile == probe[0]
	print("[hovertest] ② 合成移动事件经 push_input 命中 t%d %s（实际 %d）"
		% [probe[0], "✓" if real_ok else "✗", _hover_tile])
	if not real_ok:
		ok = false

	# ---------- ③ 准入门槛 ----------
	_hover_tile = probe[0]
	var vis_free := _hover_preview_visible()                  # 正常：该亮
	board[probe[0]] = Stone.BLACK
	var vis_occ := _hover_preview_visible()                   # 已占：不该亮
	board[probe[0]] = Stone.EMPTY
	game_over = true
	var vis_over := _hover_preview_visible()                  # 终局：不该亮
	game_over = false
	var save_think: bool = is_ai_thinking
	is_ai_thinking = true
	var vis_ai := _hover_preview_visible()                    # 电脑思考中：不该亮
	is_ai_thinking = save_think
	var gate_ok: bool = vis_free and not vis_occ and not vis_over and not vis_ai
	print("[hovertest] ③ 准入门槛 %s（空点=%s 已占=%s 终局=%s 思考中=%s）"
		% ["✓" if gate_ok else "✗", _yn(vis_free), _yn(vis_occ), _yn(vis_over), _yn(vis_ai)])
	if not gate_ok:
		ok = false

	# ---------- ④ 棋理判据 vs 落子真源：穷举对照 ----------
	# ⚠️ 局面必须用**合法落子**铺出来：随机填子会造出「无气串」这种非法局面，
	#    而非法局面下 `place_stone` 的「先全局提死子」会比 `can_place_at` 多提子 → 假红。
	reset_game(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	current_player = Stone.BLACK
	_quiet_place = true
	var played := 0
	var guard := 0
	while played < 60 and guard < 40000:
		guard += 1
		var t: int = rng.randi_range(0, tiles.size() - 1)
		if not can_place_at(t):
			continue
		if place_stone(t, false):
			played += 1
	_quiet_place = false
	# 快照 → 逐空点「预测 vs 真下」→ 回滚
	var snap_board: Dictionary = board.duplicate()
	var snap_turn: int = current_player
	var snap_ko: int = ko_point
	var snap_bp: int = black_prisoners
	var snap_wp: int = white_prisoners
	var snap_pass: int = passes
	var mism := 0
	var n_legal := 0
	var n_block := 0
	_quiet_place = true
	for i in tiles.size():
		if board[i] != Stone.EMPTY:
			continue
		var pred: bool = can_place_at(i)
		var real: bool = place_stone(i, false)
		board = snap_board.duplicate()
		current_player = snap_turn
		ko_point = snap_ko
		black_prisoners = snap_bp
		white_prisoners = snap_wp
		passes = snap_pass
		if pred != real:
			mism += 1
		if pred:
			n_legal += 1
		else:
			n_block += 1
	_quiet_place = false
	# 非空跑判据：这局面里「可下」与「被拒」两类都得出现，对照才不是空转
	var sweep_ok: bool = mism == 0 and n_legal > 0
	print("[hovertest] ④ 棋理判据 vs place_stone 穷举对照 %s（%d 手局面，空点 %d：可下 %d / 被拒 %d，分歧 %d）"
		% ["✓" if sweep_ok else "✗", played, n_legal + n_block, n_legal, n_block, mism])
	if not sweep_ok:
		ok = false

	# ---------- ⑤ 自杀点（阴性对照：朴素口径必须放行） ----------
	reset_game(true)
	current_player = Stone.BLACK
	var t_sui := -1
	for i in tiles.size():
		if adjacency[i].size() >= 3:
			t_sui = i
			break
	var ring_libs := 0
	var sui_pred := true
	var sui_real := true
	if t_sui >= 0:
		for n in adjacency[t_sui]:
			board[n] = Stone.WHITE
		for n in adjacency[t_sui]:          # 白环自身的对外气（有气 → 提不掉 → 黑必自杀）
			for m in adjacency[n]:
				if m != t_sui and board[m] == Stone.EMPTY:
					ring_libs += 1
		sui_pred = can_place_at(t_sui)
		_quiet_place = true
		sui_real = place_stone(t_sui, false)
		_quiet_place = false
	var naive_sui: bool = t_sui >= 0 and board[t_sui] == Stone.EMPTY   # 朴素口径：只看空点
	# ★ 还要钉住「棋理层真的参与**预览门槛**」：只测 `can_place_at()` 的话，
	#   把 `_hover_preview_visible()` 里那一步剪掉（预览无视自杀点）不会有人发现。
	var vis_sui := false
	if t_sui >= 0:
		_hover_tile = t_sui
		vis_sui = _hover_preview_visible()
	var sui_ok: bool = t_sui >= 0 and naive_sui and (not sui_pred) and (not sui_real) and (not vis_sui)
	print("[hovertest] ⑤ 自杀点拒下 %s（t%d 白环外气 %d；判据=%s 真下=%s 预览不亮=%s 朴素口径=%s）"
		% ["✓" if sui_ok else "✗", t_sui, ring_libs, _yn(sui_pred), _yn(sui_real),
			_yn(not vis_sui), _yn(naive_sui)])
	if not sui_ok:
		ok = false

	# ---------- ⑥ 劫点 ----------
	# 复用 --shotcap 的「黑提白一子」构造（同一套几何，不再写一遍）
	_quiet_place = true
	_setup_shot_capture()
	_quiet_place = false
	var ko_t: int = ko_point
	var ko_pred := true
	var ko_real := true
	if ko_t >= 0:
		ko_pred = can_place_at(ko_t)
		_quiet_place = true
		ko_real = place_stone(ko_t, false)
		_quiet_place = false
	_place_anims.clear()
	_capture_anims.clear()
	var naive_ko: bool = ko_t >= 0 and board[ko_t] == Stone.EMPTY
	# 同 ⑤：预览门槛也必须挡住劫点（否则会出现「预览亮着、点下去提示禁止打劫」）
	var vis_ko := false
	if ko_t >= 0:
		_hover_tile = ko_t
		vis_ko = _hover_preview_visible()
	var ko_ok: bool = ko_t >= 0 and naive_ko and (not ko_pred) and (not ko_real) and (not vis_ko)
	print("[hovertest] ⑥ 劫点禁着 %s（ko_point=t%d；判据=%s 真下=%s 预览不亮=%s 朴素口径=%s）"
		% ["✓" if ko_ok else "✗", ko_t, _yn(ko_pred), _yn(ko_real), _yn(not vis_ko), _yn(naive_ko)])
	if not ko_ok:
		ok = false

	# ---------- ⑦ 预览与下落同貌（硬不变量） ----------
	var hov: Dictionary = _hover_preview_state()
	var d0: Dictionary = _place_drop_state(0.0)
	var d1: Dictionary = _place_drop_state(1.0)
	var dmid: Dictionary = _place_drop_state(0.5)
	# 起手逐位相同：这是「落子就是这个预览往下落」的全部内容 —— 与透明度旋钮取值**无关**
	var same_ok: bool = Vector2(hov["off"]) == Vector2(d0["off"]) \
			and is_equal_approx(float(hov["alpha"]), float(d0["alpha"]))
	# 落定：位移归零、颜色不透明
	var land_ok: bool = Vector2(d1["off"]) == Vector2.ZERO \
			and is_equal_approx(float(d1["alpha"]), 1.0)
	# 半途：确实在空中（位移为负且没到地面）
	var mid_y: float = Vector2(dmid["off"]).y
	var mid_pos_ok: bool = mid_y < 0.0 and absf(mid_y) < _drop_height()
	# ★★ 透明度爬升：**只在旋钮 < 1 时才成立** —— 2026-09-29 用户口令「预览棋子改成不透明」
	#   把默认值提到了 1.0，于是 `lerpf(1.0, 1.0, t) ≡ 1.0`：全程不透明的**自然退化**，
	#   不是"爬升坏了"。判据必须跟着旋钮走，否则这条会变成"跟配置较劲"的假红。
	#   两个分支都要有牙齿：旋钮 <1 时钉住"起手=旋钮值、半途严格居中、落定=1"；
	#   旋钮 =1 时钉住"确实没有爬升"（不然把默认值悄悄改回 0.45 也没人发现）。
	var ramp_txt := ""
	var ramp_ok := true
	if hover_preview_alpha < 0.999:
		ramp_ok = is_equal_approx(float(d0["alpha"]), hover_preview_alpha) \
				and float(dmid["alpha"]) > float(d0["alpha"]) \
				and float(dmid["alpha"]) < 1.0
		ramp_txt = "旋钮 %.2f：起手 %.2f → 半途 %.2f → 落定 1.00（爬升 %s）" % [
			hover_preview_alpha, float(d0["alpha"]), float(dmid["alpha"]), _yn(ramp_ok)]
	else:
		ramp_ok = is_equal_approx(float(d0["alpha"]), 1.0) \
				and is_equal_approx(float(dmid["alpha"]), 1.0)
		ramp_txt = "旋钮 1.00（不透明）：起手/半途/落定 α 全 = %.2f（无爬升 %s）" % [
			float(dmid["alpha"]), _yn(ramp_ok)]
	# 阴性对照：高度参数必须真的被读到（比例 ×10 → 高度必须跟着变，不能是写死的数）
	var save_ratio: float = drop_height_ratio
	var h1: float = _drop_height()
	drop_height_ratio = 6.0
	var h2: float = _drop_height()
	drop_height_ratio = save_ratio
	var knob_ok: bool = h2 > h1 and is_equal_approx(h2, _min_tile_r * 6.0)
	# 阴性对照：透明度旋钮必须真的被读到 —— 拧到 0.2 后，**落子起手 α** 与**预览顶面 α**
	# 都必须跟着变。★ 两处都要查：`_place_drop_state()` 与 `_hover_preview_state()` 是两个
	# 独立的表达式（§"两条表达式各写一份、由自检钉在一起才叫不变量"），只查一处会漏掉
	# "预览顶面被写死"这种失效（那正是用户口令「预览棋子改成不透明」的落点）。
	var save_hpa: float = hover_preview_alpha
	hover_preview_alpha = 0.2
	var a_knob: float = float(_place_drop_state(0.0)["alpha"])
	var h_knob: float = float(_hover_preview_state()["alpha"])
	hover_preview_alpha = save_hpa
	var a_knob_ok: bool = is_equal_approx(a_knob, 0.2) and is_equal_approx(h_knob, 0.2)
	var drop_ok: bool = same_ok and land_ok and mid_pos_ok and ramp_ok and knob_ok and a_knob_ok
	print("[hovertest] ⑦ 预览与下落同貌 %s（起手相同=%s 落定=%s 半途 y=%.1f α=%.2f｜%s｜高度参数生效=%s %.1fpx 砖内切 %.1fpx｜顶面 α 旋钮生效=%s＜起手 %.2f / 预览 %.2f＞）"
		% ["✓" if drop_ok else "✗", _yn(same_ok), _yn(land_ok), mid_y,
			float(dmid["alpha"]), ramp_txt, _yn(knob_ok), _drop_height(), _min_tile_r,
			_yn(a_knob_ok), a_knob, h_knob])
	if not drop_ok:
		ok = false

	# ---------- ⑧ 悬浮预览的**侧壁**（厚度感；已取代原来的「对齐虚线」） ----------
	# 断言五件事：① 面数 == 该砖边数 ② 每个面的 4 个点必须恰好是
	#「抬高后的边 a→b」+「落点的边 b→a」（= 把落点那条边整体上移 `_drop_height()`）。
	# 再配三条对照：
	#   · 门槛同源：`_hover_tile` 指到**已占格** → 一个面都不该有（走真 `_hover_preview_visible()`）
	#   · 参数敏感：抬高量 ×3 后侧壁高度跟着 ×3（否则说明这是写死的装饰）
	#   · ★★ **厚度真的看得见**：侧壁必须比顶面暗（`hover_side_darken` 真被读到）；
	#     把这个旋钮置 0 时必须与棋子色**完全一致** —— 否则"厚度"只是名义上的。
	#     黑白两方都判（浅色棋子的"暗面"更容易被调没）。
	#   · **侧壁不透明 + 顶面不透明**（口径两轮都翻过，见 `hover_side_alpha` 的注释：
	#     第一轮"侧边改半透明"⇒ 0.5；第二轮用户看到实物后"要改成完全不透明"⇒ 1.0）：
	#     判据是"**不透明**（≥0.999）＋ 旋钮真被读到（拧 0 → 全透明、拧 1 → 全不透明）
	#     ＋ 侧壁 α 跟着顶面 α 走"，**不是**"默认值等于多少"的同义反复。
	#     ⚠️ 默认值回到 1.0 之后，**光断言 ≥0.999 已经没有牙齿**（把旋钮写死成 1.0 也绿）
	#     ⇒ 这一条的牙齿**全靠那两条敏感性对照**（0 → 0.00、1 → 1.00）。别删它们。
	# ★★ 这一族判据**一律读 `_hover_side_color()` 本身**（不是另抄一遍公式）——
	#   2026-09-29 实测：菜单侧那条原先自己算 `hbase.darkened(SIDE_DARKEN)`，
	#   把实现改成 `darkened(0.0)`（厚度感消失）后它**照旧全绿**（阴性对照里唯一一条没牙齿的）。
	reset_game(true)
	# 挑一块「预览真能亮」的砖（用真门槛挑，而不是写死第 0 块 —— 第 0 块的中心有可能正好
	# 落在 HUD 底下，那样这里会拿到空数组，看起来像"侧壁功能坏了"）
	var w_t := -1
	for i in tiles.size():
		_hover_tile = i
		if _hover_preview_visible():
			w_t = i
			break
	if w_t < 0:
		print("[hovertest] ⑧ 预览侧壁 ✗（找不到能亮预览的砖，判据无法成立）")
		ok = false
		w_t = 0
	_hover_tile = w_t
	var walls: Array = _hover_side_walls()
	var wpts := _tile_points_for_draw(w_t)
	var wh: float = _drop_height()
	var wbad := 0
	for i in walls.size():
		var q: Array = walls[i]
		var a: Vector2 = wpts[i]
		var b: Vector2 = wpts[(i + 1) % wpts.size()]
		var exp := [a + Vector2(0.0, -wh), b + Vector2(0.0, -wh), b, a]
		for k in 4:
			if (q[k] as Vector2).distance_to(exp[k]) > 0.01:
				wbad += 1
	var wall_ok: bool = walls.size() == wpts.size() and wbad == 0
	# 对照 A：门槛同源（已占格 → 没有侧壁）
	var saved_mark: int = board[w_t]
	board[w_t] = Stone.BLACK
	_hover_tile = w_t
	var walls_blocked: int = _hover_side_walls().size()
	board[w_t] = saved_mark
	# 对照 B：参数敏感（抬高量 ×3 → 侧壁高跟着 ×3）
	var save_ratio2: float = drop_height_ratio
	drop_height_ratio = save_ratio2 * 3.0
	var walls2: Array = _hover_side_walls()
	var w_h2: float = 0.0
	if walls2.size() > 0:
		w_h2 = (Vector2(walls2[0][3])).distance_to(Vector2(walls2[0][0]))
	drop_height_ratio = save_ratio2
	# 对照 C：厚度真的看得见（黑白两方；旋钮置 0 时侧壁必须与棋子色完全一致）
	var save_dark: float = hover_side_darken
	var lum_side := 0.0
	var lum_flat := 0.0
	var thick_ok: bool = true
	for col in [Stone.BLACK, Stone.WHITE]:
		current_player = col
		var wl: float = _hover_side_color().get_luminance()
		hover_side_darken = 0.0
		var tl: float = _hover_side_color().get_luminance()
		hover_side_darken = save_dark
		if lum_side == 0.0:
			lum_side = wl
			lum_flat = tl
		# 侧壁必须**可辨识地**暗于顶面（只暗千分之一也算"没做"）
		if not (wl <= tl * 0.95):
			thick_ok = false
	current_player = Stone.BLACK
	# 对照 D：侧壁**不透明**（`hover_side_alpha`）＋ 顶面**不透明**（`hover_preview_alpha`）。
	# ★★ 这条判据的口径**两年内翻过两次**（0.5 → 1.0），每次翻面都按纪律**补新的牙齿**：
	#   第一轮（「侧边改半透明」）：原先钉 `w.a == 1.0`（刻意不透明，理由是"相邻边侧壁在窄角
	#   重叠、半透明叠两次出深斑"——实测对**凸砖不成立**，沿同一方向平移时两个侧面只共一条
	#   竖棱、面积重叠为 0）；翻成"半透明"时必须补**敏感性对照**，否则只断言"α 等于 0.5"
	#   是同义反复（把常数写死也绿）。
	#   第二轮（「要改成完全不透明才好」）：改回 1.0 —— 此时"≥0.999"同样**没有牙齿**
	#   （写死 1.0 也绿）⇒ 牙齿**依旧全靠**那两条敏感性对照（拧 0 → 必须 0.00；拧 1 → 1.00）。
	#   ⚠️ 教训一句话：**判据的牙齿不在"钉住默认值"，而在"拧动旋钮它必须跟着动"** ——
	#     默认值每改一次，前者就废一次，后者永远不会。
	#   ★ 顶面那一半也要判：它可能就是被随手改回 0.45（用户两轮都明确要求"不透明"）。
	var wall_alpha: float = _hover_side_color().a
	var top_alpha: float = float(_hover_preview_state()["alpha"])
	var save_sa: float = hover_side_alpha
	hover_side_alpha = 0.0
	var sa_zero: float = _hover_side_color().a
	hover_side_alpha = 1.0
	var sa_one: float = _hover_side_color().a
	hover_side_alpha = save_sa
	# ★ 侧壁 α 必须**跟着顶面 α 走**（顶面调淡 → 侧壁一起淡，提子升空时不会剩一圈空壳墙裙）
	var save_hpa2: float = hover_preview_alpha
	hover_preview_alpha = 0.4
	var sa_follow: float = _hover_side_color().a
	hover_preview_alpha = save_hpa2
	var sa_follow_ok: bool = is_equal_approx(sa_follow, save_sa * 0.4)
	# 侧壁必须**不透明**（用户第二轮口令："要改成完全不透明才好"）—— 背后盘面不许透出来
	var side_solid_ok: bool = wall_alpha >= 0.999
	var alpha_ok: bool = is_equal_approx(wall_alpha, save_sa) \
			and is_equal_approx(sa_zero, 0.0) and is_equal_approx(sa_one, 1.0) \
			and sa_follow_ok and side_solid_ok
	var top_ok: bool = top_alpha >= 0.999
	var wall_ctl: bool = walls_blocked == 0 and absf(w_h2 - _drop_height() * 3.0) < 0.05
	var wall_final: bool = wall_ok and wall_ctl and thick_ok and alpha_ok and top_ok
	print("[hovertest] ⑧ 预览侧壁 %s（t%d 边 %d → 面 %d，几何错 %d 处｜已占格给 %d 面｜侧壁高随参数 %.1f→%.1f｜厚度可见 %s｜侧壁 α=%.2f 不透明 %s（旋钮敏感 0→%.2f / 1→%.2f、随顶面 0.4→%.2f %s）%s｜顶面 α=%.2f 不透明 %s）"
		% ["✓" if wall_final else "✗", w_t, wpts.size(), walls.size(), wbad,
			walls_blocked, wh, w_h2, "✓ %.2f<%.2f" % [lum_side, lum_flat * 0.95],
			wall_alpha, "✓" if side_solid_ok else "✗",
			sa_zero, sa_one, sa_follow, "✓" if sa_follow_ok else "✗",
			"✓" if alpha_ok else "✗", top_alpha, "✓" if top_ok else "✗"])
	if not wall_final:
		ok = false

	# ---------- ⑨ 「离位块被瓷砖边线内部划过」——量的就是用户报的「落子被棋盘边界线遮挡」 ----------
	# ★★ 这一条量的是**几何事实**（抬离之后有多少条真会画的边线从块内部穿过），
	#    所以它在**改画序之前与之后都是 ✓** —— 它证明的是"病灶存在且非平凡"，
	#    不是"修好了"。真正守"修好了"的是另外两件，缺一不可：
	#      · 结构判据 S9（`瓷砖边线段` 必须排在 `②b 离位层` **之前**的行序）—— 守画序；
	#      · A/B 目检 job `dropline`（把 ②b 挪回边线之前 → 截 `--shotdrop`，差分出差异区）—— 守观感。
	#    ★ 为什么不能指望这一条自己变红（纪律「审计要有牙齿」）：画序错了**没有运行时观测量**
	#      （headless 不渲染、拿不到像素），只能退守"能产生该观测量的那行代码在不在、在什么位置"。
	# ★ 「白子尤为明显」也在这里被量化：边线色 vs 白子/黑子的亮度差 —— 白子上那道划痕
	#   对比度高得多，所以用户**先看见**白子（不是"只有白子被挡"）。数值只打印，不参与判定
	#   （主题一换线色就变，拿它当判据会变成"跟主题配置较劲"）。
	reset_game(true)
	var o_h: float = _drop_height()
	var o_lum_line: float = line_color.get_luminance()
	var o_dw: float = absf(o_lum_line - piece_color_white.get_luminance())
	var o_db: float = absf(o_lum_line - piece_color_black.get_luminance())
	# 口径：只搜 i 的 **2 环邻域**的边线（抬高量 h < 一格宽 ⇒ 抬离块不可能碰到更远的砖；
	# 2 环留了余量）。下面用"最惨的那块按全盘边线重算"来自证这个剪枝没漏 —— 这才是胆子。
	var o_ring: Array = []
	for i in tiles.size():
		var nb2: Dictionary = {i: true}
		for a in adjacency[i]:
			nb2[a] = true
			for b in adjacency[a]:
				nb2[b] = true
		o_ring.append(nb2.keys())
	var o_lift := 0        # 抬离块被边线从内部穿过：条数（全盘合计）
	var o_flat := 0        # 对照：不抬（h=0）时穿过几条 —— 必须 = 0，否则"抬离才出问题"不成立
	var o_self := 0        # 其中属于"自己那块砖的边线"
	var o_blocks := 0      # 有多少块抬离块至少被划过一次
	var o_worst := 0
	var o_worst_tile := -1
	for i in tiles.size():
		var o_pts := _tile_points_for_draw(i)
		var o_up := PackedVector2Array()
		for p in o_pts:
			o_up.push_back(p + Vector2(0.0, -o_h))
		var o_bb: Rect2 = _poly_bbox(o_up)
		var o_fbb: Rect2 = _poly_bbox(o_pts)
		var o_n := 0
		for j in o_ring[i]:
			for s in _drawn_edge_segments(j):
				var sa: Vector2 = s[0]
				var sb: Vector2 = s[1]
				if _seg_bbox_hits(sa, sb, o_bb) and _seg_crosses_poly(sa, sb, o_up, 1.0):
					o_lift += 1
					o_n += 1
					if j == i:
						o_self += 1
				if _seg_bbox_hits(sa, sb, o_fbb) and _seg_crosses_poly(sa, sb, o_pts, 1.0):
					o_flat += 1
		if o_n > 0:
			o_blocks += 1
			if o_n > o_worst:
				o_worst = o_n
				o_worst_tile = i
	# 剪枝口径自证：最惨那块按**全盘边线**重算，两数必须相等（不等 ⇒ 上面那个 2 环漏了东西）
	var o_full := 0
	if o_worst_tile >= 0:
		var fp := _tile_points_for_draw(o_worst_tile)
		var fup := PackedVector2Array()
		for p in fp:
			fup.push_back(p + Vector2(0.0, -o_h))
		var fbb: Rect2 = _poly_bbox(fup)
		for j in tiles.size():
			for s in _drawn_edge_segments(j):
				if _seg_bbox_hits(s[0], s[1], fbb) and _seg_crosses_poly(s[0], s[1], fup, 1.0):
					o_full += 1
	var o_ok: bool = o_lift > 0 and o_flat == 0 and o_full == o_worst
	print("[hovertest] ⑨ 离位块被瓷砖边线内部划过 %s（抬离 %.1fpx：%d/%d 块被划、共 %d 条穿过（其中自身 %d 条），单块最多 %d 条@t%d＝全盘重算 %d 条｜h=0 对照 %d 条｜线亮度 %.2f ⇒ 白子对比 %.2f / 黑子 %.2f = %.1f×）"
		% ["✓" if o_ok else "✗", o_h, o_blocks, tiles.size(), o_lift, o_self, o_worst,
			o_worst_tile, o_full, o_flat, o_lum_line, o_dw, o_db,
			o_dw / maxf(o_db, 0.0001)])
	if not o_ok:
		ok = false

	print("[hovertest] 结论：", "通过 ✓" if ok else "失败 ✗")
	get_tree().quit()


## 自检日志用：布尔 → ✓/✗（`--hovertest` 专用，避免每处都写三目）
func _yn(b: bool) -> String:
	return "✓" if b else "✗"


func _dist_to_boundary(p: Vector2, poly: PackedVector2Array) -> float:
	var d := INF
	var n := poly.size()
	for i in n:
		var c := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % n])
		d = minf(d, c.distance_to(p))
	return d


# 把指定瓷砖填成给定色（与盘面同色，使「瓷砖即棋子」与盘面统一）。
# col 的 alpha 控制透明度，供悬浮预览 / 落子下落 / 提子渐隐动画复用。
# off：整块瓷砖的位移（落子下落动画用 —— 把多边形整体上移即为「还在空中」）。
## 某一格此刻该画成什么 —— **棋子层的唯一真源**（`_draw()` 的两遍与 `--captest` 共用）。
## 返回 `{ "draw": bool, "col": Color, "off": Vector2, "layer": int }`：
##   layer 0 = **落定在原格**的棋子（位置不动，按瓷砖索引画即可）
##   layer 1 = **离位**的棋子（落子下落 / 提子升空，必须最后画）
##   `off`    = 位移（离位才非零）
##
## ★ 为什么值得抽成一个函数（而不是在 `_draw()` 里现算）：
##   这里原本是三条互斥分支，而**门槛写错不会有任何报错** —— 提子渐隐那一条曾被
##   `board[i] == Stone.EMPTY` 挡死（提子时 `remove_group()` 已把这一格置空），
##   于是"提子渐隐"**整条不可达**，实际观感退化成"提子瞬间消失"，
##   且没有任何判据能发现（渲染结果在 headless 下量不到）。
##   抽出来之后 `--captest` 就能直接断言"这一格此刻必须 draw=true、且 alpha 真的在降"。
func _stone_paint(i: int) -> Dictionary:
	# ① 正在落下的那一手（刚落下的格子 board 必非空）。优先级最高。
	if _place_anims.has(i):
		var ps: Dictionary = _place_drop_state(1.0 - _place_anims[i] / STONE_ANIM_TIME)
		var cd: Color = piece_color_black if board[i] == Stone.BLACK else piece_color_white
		cd.a *= ps["alpha"]
		return {"draw": true, "col": cd, "off": ps["off"], "layer": 1}
	# ② 正在消散的提子。⚠️ 此刻 `board[i]` **已经是 EMPTY**（`place_stone()` 里先
	#    `remove_dead_stones()` 把棋盘清掉、再记 `_capture_anims`）⇒ 判定**只能**看
	#    `_capture_anims`，绝不能再加一条"board 非空"的前提（那正是原来的 bug）。
	#    颜色取记录里的 `color`（被提方）；位移与透明度走 `_capture_fade_state()`。
	# ★★ 层号必须与下落那一手**同为 1**：口径是「**任何离位的棋子都最后画**」——
	#    提子从 2026-09-29 起会**向上升出本格**（必然压到上方邻格），若还留在 layer 0
	#    按索引序画，序号更大的邻格棋子就会把它盖住 —— 与「落子被已有棋子遮挡」同一个坑。
	#    起手那一帧 off=0（棋子还在自己格上、不与任何格重叠）⇒ 挪到最后画**逐像素等价**。
	if _capture_anims.has(i):
		var cap: Dictionary = _capture_anims[i]
		var t := 1.0 - clampf(cap["time_left"] / STONE_ANIM_TIME, 0.0, 1.0)
		var cs: Dictionary = _capture_fade_state(t)
		var cc: Color = piece_color_black if cap["color"] == Stone.BLACK else piece_color_white
		cc.a *= cs["alpha"]
		return {"draw": true, "col": cc, "off": cs["off"], "layer": 1}
	# ③ 静止棋子
	if board[i] != Stone.EMPTY:
		var cst: Color = piece_color_black if board[i] == Stone.BLACK else piece_color_white
		return {"draw": true, "col": cst, "off": Vector2.ZERO, "layer": 0}
	return {"draw": false, "col": Color(0, 0, 0, 0), "off": Vector2.ZERO, "layer": 0}


func _draw_tile_fill(i: int, col: Color, off: Vector2 = Vector2.ZERO) -> void:
	var points := _tile_points_for_draw(i)
	if off != Vector2.ZERO:
		var shifted := PackedVector2Array()
		for p in points:
			shifted.push_back(p + off)
		points = shifted
	draw_colored_polygon(points, col)

## 落子「悬浮 + 下落」的公共高度（像素）：与最小瓷砖内切半径挂钩 —— 小盘不夸张、大盘不局促。
## ★ 悬浮预览浮起的高度 = 下落动画的起点高度 = 本值（**同一个数**）：于是预览与落下的棋子
##   起手状态逐位相同，不会出现「预览悬浮 5px、落下却从 30px 开始」的跳变。
func _drop_height() -> float:
	if _min_tile_r == INF:
		return 6.0
	# ⚠️ 地板值只能取**很小**：取 12 时，标准盘（砖内切 15px）算出来 9px 会被抬到 12px，
	#    `drop_height_ratio` 调小就完全没反应 —— 旋钮失效比数字难看更糟（用户口径：必须可调）。
	return maxf(6.0, _min_tile_r * drop_height_ratio)

## 落子下落的瞬时状态：`k` = **已过**比例 0→1（0 = 刚点下、还在空中；1 = 已落定）。
## ★ `_draw()` 与 `--hovertest` ⑥ 共用本函数 —— 自检测的就是真公式，而不是另抄一份。
## `1 - tt*tt` = 加速下落（自由落体观感）；透明度 **线性** 从预览透明度涨到实心
## —— 线性是刻意的：起手那一帧与悬浮预览逐位相同，落地那一刻刚好满实心，
## 中间一直是「半透明的砖在空中」；早先用的 `tt*1.8` 到 45% 就 90% 不透明，
## 「预览渐变成实心」这个过程根本看不见（已按截图目检定标改回）。
## ★ 不变量（自检钉死）：k=0 时的位移/透明度 **必须**等于悬浮预览（`_hover_preview_state()`）。
func _place_drop_state(k: float) -> Dictionary:
	var tt := clampf(k, 0.0, 1.0)
	return {
		"off": Vector2(0.0, -_drop_height() * (1.0 - tt * tt)),
		"alpha": lerpf(hover_preview_alpha, 1.0, tt),
	}

## 悬浮预览的位移与不透明度。
## ★★ 与 `_place_drop_state(0.0)` **必须逐位相同** —— 这是本轮需求的硬不变量
##    （「落子效果就是这个预览向下落下」），由 `--hovertest` ⑥ 交叉断言。
##    故意**不**写成 `_place_drop_state(0.0)` 的转发：那样「两边一致」就成了废话（同一个函数），
##    谁改了下落曲线都不会被发现。两条表达式各写一份、由自检钉在一起，才叫不变量。
func _hover_preview_state() -> Dictionary:
	return {"off": Vector2(0.0, -_drop_height()), "alpha": hover_preview_alpha}

## 提子动画的**起手延迟** = 落子动画时长 ⇒ 两段**串行**：先把新子落下、再让被提的子升空散尽。
## 2026-09-29 用户口令「提子动画要放在落子动画结束之后」（此前两段是并排跑的）。
## ★ 抽成具名函数而不是就地写 `STONE_ANIM_TIME`：口径是"**等于**落子动画的时长"，
##   落子时长将来一改，这一处必须跟着走 —— `--captest` 断言的正是"delay ≥ 落子动画时长"。
func _capture_delay() -> float:
	return STONE_ANIM_TIME

## 整段提子过程的**总时长**（含地板，见 `capture_total_time` 的说明）。
## ★ 单抽一个函数是必须的：`_capture_wave_start()` 与自检都要问它，**谁都不许就地复算
##   `maxf(...)`** —— 复算一次就漂一次（§"真源要唯一，判据只能读那一份"）。
func _capture_total_time() -> float:
	return maxf(STONE_ANIM_TIME, capture_total_time)

## 第 `wave` 层（`wave_max` = 最深层的层号）的**起手偏移**（秒，不含 `_capture_delay()`）。
## ★★ 归一化 `wave / wave_max` 是"总时长封顶"的**全部关键**：
##   第 0 层（贴着刚落那一手）起手偏移 = 0；最深层起手偏移 = `总时长 - 单颗时长`，
##   于是**最深的那一层刚好在总时长处散尽**，且**与层数无关**（2 层和 20 层一样久）。
##   写成 `spread * wave`（去掉归一化）时长就随串长线性爆炸 —— 阴性对照 M24 守这一条。
## ★ 起手偏移**严格随层号递增**（同层并列）；`wave_max <= 0`（只提得动一层）时返回 0 ⇒
##   所有子同时升空 = 旧观感（不是特例分支，是归一化的自然退化）。
func _capture_wave_start(wave: int, wave_max: int) -> float:
	if wave_max <= 0:
		return 0.0
	var spread: float = maxf(0.0, _capture_total_time() - STONE_ANIM_TIME)
	return spread * float(wave) / float(wave_max)

## 被提的每颗子离**刚落那一手**有几层（BFS）：返回 `{ tile_id: 层号 }`。
## ★★ 2026-09-29 用户口令「从对方所下棋子旁边的子开始被提走，接着它旁边的子被提走，依次提完」——
##   本函数就是"从哪颗开始、接着哪颗"的定义处。
## · 只在**被提的集合**里搜：一圈一圈从 `placed` 往外推，第 0 层 = 与刚落那手相邻的被提子，
##   第 1 层 = 与第 0 层相邻的被提子……（提子后棋盘已置空，**不能**拿 board 判连通，
##   只能靠 `adjacency` 与"是否在被提集合里"）。
## · ⚠️ **绝不靠 board 找连通块**：`remove_dead_stones()` 已经把子清掉了（同 §"门槛复算 board
##   导致分支不可达"那族坑）；`removed_ids` 才是真源。
## · 兜底：理论上被提的块必定有子贴着刚落那手（"最后一口气"按定义就挨着某个子），
##   但真出现"整个集合都够不着"时**全部并进第 0 层** —— 宁可"同时提"，也绝不能留一颗不提
##   （漏动画是**静默**的，看不出是 bug）。
func _capture_depths(placed: int, ids: Array[int]) -> Dictionary:
	var depth: Dictionary = {}
	if ids.is_empty():
		return depth
	var want: Dictionary = {}
	for i in ids:
		want[i] = true
	var frontier: Array[int] = []
	for i in ids:
		if adjacency[i].has(placed):
			depth[i] = 0
			frontier.append(i)
	if frontier.is_empty():
		for i in ids:
			depth[i] = 0
		return depth
	var d := 0
	while not frontier.is_empty() and depth.size() < ids.size():
		d += 1
		var next: Array[int] = []
		for f in frontier:
			for nb in adjacency[f]:
				if want.has(nb) and not depth.has(nb):
					depth[nb] = d
					next.append(nb)
		frontier = next
	for i in ids:                      # 兜底（不该发生）：剩下的并进最后一层，别丢下不管
		if not depth.has(i):
			depth[i] = d
	return depth

## 本手提子的**最深层层号**（只提一层时为 0）。自检与记录共用，别就地再算一遍。
func _capture_wave_max(depths: Dictionary) -> int:
	var mx := 0
	for v in depths.values():
		mx = maxi(mx, int(v))
	return mx

## 某颗被提的子**整段动画结束的时刻**（相对"落子动画起手"的时间轴，秒）。
## 自检据此断言"整段不超封顶"，与 `_process()` 的推进口径同源（delay + time_left 两段相加）。
func _capture_end_time(wave: int, wave_max: int) -> float:
	return _capture_delay() + _capture_wave_start(wave, wave_max) + STONE_ANIM_TIME

## 提子消散的瞬时状态：`k` = **已过**比例 0→1（0 = 刚被提、棋子还在原格；1 = 已升空散尽）。
## 2026-09-29 用户口令「把提子也改成向上平移淡出」—— 与落子成**镜像**：
##   落子 = 从上方落下来 + 由淡转实；提子 = **向上升走** + 由实转无。
## ★ 两条硬规矩（都按"这 0.3 秒里人能看到什么"定的，不是手感）：
##   ① **高度必须复用 `_drop_height()`**，绝不能新开一个旋钮 ——
##      于是「提子的终点 == 落子的起点」是同一个数，两段位移合起来正好是一趟来回。
##      新增旋钮会让两处各调各的、必然调歪（同 §"高度只留一个旋钮"那条）。
##   ② 缓动取**先快后慢** `1-(1-t)²`，**不是**落子 `1-t²` 的时间反演：
##      反演会把位移全挤进最后 30%，而那时 alpha 已经 ≈0.2 ⇒ 用户**根本看不见平移**，
##      只剩"原地淡出"—— 正是这次要改掉的东西。自检据此钉死「半途至少走完 40% 行程」。
func _capture_fade_state(k: float) -> Dictionary:
	var tt := clampf(k, 0.0, 1.0)
	var back := 1.0 - tt
	return {
		"off": Vector2(0.0, -_drop_height() * (1.0 - back * back)),
		"alpha": 1.0 - tt,
	}

## 此刻是否该显示悬浮预览 —— ★ `_draw_hover_preview()` 与自检共用本判据（自检测的是真门槛）。
## 三层：① 鼠标确实停在某块瓷砖上；② 该格是空点；③ 流程/界面层（`_place_block_reason`，
## 含 HUD 遮挡）与棋理层（`can_place_at`：劫点 / 自杀）两道门槛都放行。
func _hover_preview_visible() -> bool:
	if _hover_tile < 0 or _hover_tile >= tiles.size():
		return false
	if _place_block_reason(_hover_tile) != "":
		return false
	return can_place_at(_hover_tile)

## **任意一块砖**的侧壁几何：把「砖的每条边」竖直拉到 `off` 之前的那个位置。
## 返回 `[[抬高后的边的起点, 抬高后的边的终点, 落点边的终点, 落点边的起点], ...]`（与顶点同序）。
## ★★ 抽成"带 tile / off 参数"的通用函数是 2026-09-29 用户口令
##   「**落子时保留侧边厚度**」带来的：厚度此前只有"悬浮预览"有，真正落下来的那一手
##   （`_place_anims`）与升空散尽的提子（`_capture_anims`）都只是**平铺的一块面** ——
##   观感上是"预览是有厚度的板，落下来却变成一张纸"。
##   现在 `_draw_hover_preview()`（悬浮）、`_draw()` 的 ②b（下落 / 提子）三处**共用本函数**，
##   于是"预览 → 落下"整段连厚度都逐位连续（起手那一帧 == 预览那一帧，硬不变量仍然成立）。
## ★ `off` 归零 ⇒ 侧面高度为 0、面积 0，自动消失（不需要额外判"落地了就不画"）。
func _block_side_walls(i: int, off: Vector2) -> Array:
	var out: Array = []
	if i < 0 or i >= tiles.size():
		return out
	var pts := _tile_points_for_draw(i)
	var n := pts.size()
	for k in n:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % n]
		out.append([a + off, b + off, b, a])
	return out


## 悬浮预览块的侧壁几何（= 该格的侧壁、抬高量取预览位移）。
## ★ 与 `_draw_hover_preview()` `--hovertest` ⑧ 共用 —— 自检断言的就是这套几何。
## ★★ 2026-09-29 用户口令「落子预览虚线不好看，改成整个侧边，体现出厚度感」——
##   取代了原来的 `_hover_align_segments()`（逐顶点对齐虚线，已删）。三条理由：
##   ① 侧壁把预览从"一片贴纸 + 几根线"变成**一块有厚度的板材**，这才是用户要的厚度感；
##   ② 它**顺带**承担了虚线唯一的职责 —— 侧壁的**底边就是落点轮廓**，
##      "会落到哪一格"一眼可辨（比虚线更硬、更准，还不依赖线宽/不透明度那些调参）；
##   ③ 逐顶点虚线在**有竖直边的砖**上会与砖自身边缘完全重合（画了也看不见，踩过）；
##      侧壁没有这个问题：竖直边的侧壁投影宽度为 0 —— 那是**正确**的
##      （纯竖直位移下，与位移平行的侧面本来就不该可见）。
func _hover_side_walls() -> Array:
	if not _hover_preview_visible():
		return []
	return _block_side_walls(_hover_tile, _hover_preview_state()["off"])


## **一块砖的侧壁色**：从它自己的**顶面色**派生 —— 压暗 + 按 `hover_side_alpha` 半透明，
## 且透明度**跟着顶面的透明度走**（`top.a` 是乘数）。
## ★ 为什么"跟着顶面走"这条关系必须成立：提子升空时顶面一路淡出，若侧壁恒不透明，
##   最后一帧会剩下一圈**没有顶面的墙裙**（看着像块空壳）；顶面淡、侧壁一起淡才干净。
## ★★ 顶面色是**唯一入口**：`_hover_side_color()`（悬浮预览）与 `_draw()` ②b（下落 / 提子）
##   都走这里 —— 侧壁色只有这一个来源（§真源唯一；结构守卫 S7/S8 守的就是"别就地另算一份"）。
func _side_color_for(top: Color) -> Color:
	var w: Color = top.darkened(hover_side_darken)
	w.a = clampf(hover_side_alpha * top.a, 0.0, 1.0)
	return w


## 悬浮预览的侧壁颜色 —— `_draw_hover_preview()` 与 `--hovertest` ⑧ 共用本函数，
## 自检断言的"厚度真的看得见"与"侧壁半透明"就是断言它（见 `hover_side_darken` / `hover_side_alpha`）。
## ★ 顶面色要先按预览透明度旋钮打折再交给 `_side_color_for()` —— 于是
##   「顶面调淡 ⇒ 侧壁跟着淡」这条关系在预览上也成立，而不是写死一个 alpha 常量。
func _hover_side_color() -> Color:
	var base: Color = piece_color_black if current_player == Stone.BLACK else piece_color_white
	base.a = _hover_preview_state()["alpha"]
	return _side_color_for(base)


## 鼠标悬浮预览：砖块停在落点**上方 `_drop_height()` 处**，颜色 = 当前回合方的棋子色，
## 并把"从落点竖上来的那一圈侧面"画成**压暗的暗面**（= 厚度）。
## 画在 `_draw()` 的**最后一层**（瓷砖边线之上）—— 它模拟的是「浮在盘面上方」的一块板，
## 压在网格线上才符合视觉预期。只在 `_hover_preview_visible()` 为真时画。
## 画序：**侧壁 → 顶面 → 落点轮廓**。顶面必须压在侧壁之上（侧壁只有露在顶面之外的那一圈可见，
## 正是"一块板看过去的样子"）；轮廓最后画 ⇒ 它在顶面之上仍然清晰（"落在哪一格"是硬信息）。
## ★★ 2026-09-29 用户口令「预览动画侧边改成半透明，预览棋子改成不透明」：
##   侧壁与顶面现在是**两个独立旋钮**（`hover_side_alpha` / `hover_preview_alpha`），
##   默认 0.5 / 1.0 —— 观感从"半透明贴纸 + 一圈实心墙"变成"实心板材 + 半透明侧壁"。
func _draw_hover_preview() -> void:
	if not _hover_preview_visible():
		return
	var st: Dictionary = _hover_preview_state()
	# ① 侧壁：压暗的棋子色，不透明度 = `hover_side_alpha` × 顶面不透明度
	var wall := _hover_side_color()
	for q in _hover_side_walls():
		draw_colored_polygon(PackedVector2Array([q[0], q[1], q[2], q[3]]), wall)
	# ② 落点轮廓：侧壁底边那一圈加一道硬边，"会落到哪一格"不用眼力猜
	# ★★ 2026-09-29（第二轮）用户报「**白子**预览时棋子仍能看到其后的棋盘边界」——
	#    真凶就是这一道：它原先画在**顶面之后**，而预览块是**抬离 `_drop_height()`** 的 ⇒
	#    "落点那一圈"的**上边**正好落进抬起来的顶面内部，白棋子面上就多了一道横线。
	#    实测取样（标准盘，抬离 9.1px，`preview_leak.py`）：
	#      白鬼影：轮廓压在白顶面上 = (171,171,180) vs 顶面 (230,230,242) ⇒ 差 **59**（一眼可见）
	#      黑鬼影：同一条       = ( 11, 11, 15) vs 顶面 ( 15, 15, 20) ⇒ 差 **4**（看不见）
	#    差 **15 倍** —— 这就是"白子尤为明显"的全部原因（用户看到的"其后的棋盘边界"，
	#    其实是**落点那一圈的轮廓被画到了棋子面上**）。
	# ★ 修法是**改画序**，不是把线调淡/删掉：轮廓先画、顶面压上去 ⇒ 落在顶面内部的那段被
	#   不透明顶面盖住，只剩"落点外沿"那一圈 —— "会落到哪一格"这个硬信息一字不少。
	# ⚠️ 与量具的关系：这是**画序**问题，几何量改前改后**完全一样**（轮廓的边与顶面的内外
	#   关系不变）⇒ 运行时判据看不见，只能靠结构守卫 **S13** 与像素量具
	#   （工作区 `preview_leak.py`：顶面内"非纯棋子色"的像素数必须为 0）来守。
	if hover_foot_line > 0.0:
		var foot: Color = wall.darkened(0.25)
		var fp := _tile_points_for_draw(_hover_tile)
		for k in fp.size():
			draw_line(fp[k], fp[(k + 1) % fp.size()], foot,
				maxf(1.0, line_width * hover_foot_line))
	# ③ 顶面：棋子色（默认不透明），与下落起手逐位相同。
	#    ★ 必须**最后画**：它要盖住 ① 的墙裙内侧、以及 ② 里落进顶面内部的那段轮廓。
	#      （顺序写反 = 白子面上多一道横线，而且黑子上看不出来 —— 见 ② 的实测数字。）
	var c: Color = piece_color_black if current_player == Stone.BLACK else piece_color_white
	c.a = st["alpha"]
	_draw_tile_fill(_hover_tile, c, st["off"])

## 更新悬浮格（鼠标移动时调用）。变了才 queue_redraw —— 每帧都重绘会白烧 GPU。
func _update_hover(pos: Vector2) -> void:
	var t := _tile_at_point(pos)
	if t != _hover_tile:
		_hover_tile = t
		queue_redraw()


# ====== 联机（客户端-服务器权威模型）======
# 房主 = peer 1（服务器兼执黑）；加入方 = 执白。所有落子/加砖/停手/认输/重置
# 都经 RPC 发给服务器，服务器验证后权威应用并广播，所有客户端回放同一动作序列，
# 因此棋盘状态始终一致（双方按同一动作序列确定性回放）。
var _is_host: bool = false
var _net_color: int = Stone.BLACK      # 本机执色（host=黑 / client=白）
var _net_connected: bool = false       # 已与对家建立同步（收到/发出初始盘面）
var _net_awaiting: bool = false        # 已发送动作、等待服务器广播回放（防连点）
var _peer_white: int = -1              # 服务器侧：对方（白方）peer id
var _chan: NetChannel = null           # 对局通道（第 5 步后 = Steam P2P，唯一实现）。
#   ★ 非 null 表示本局走**传输层通道**（而不是直呼本地）—— 这是全工程唯一的传输层判据。
#   ★ 2026-09-30 §24 第 5 步：自建中继（`RelayTransport`）已删除，本工程只注册了
#     `SteamTransport` 一种实现，但**变量类型仍是基类 `NetChannel`**、调用点一处没改 ——
#     这正是 §21 第 3 步引入基类的收益：删掉一个实现不需要动任何调用处。
var _steamnet_active: bool = false       # Steam P2P 自环自检（--steamnet）开关
var _init_applied: bool = false          # 已**应用**过对端下发的初始盘面（收到 init 那一刻置真）
#   ★ 为什么不复用 `_net_connected`（就在上面几行）：那是**双向**语义（收到**或**发出）——
#     房主在 `_on_relay_ready() → _on_peer_joined()` 里就把它置真了，与"有没有收到包"无关。
#     实测证据（阴性对照 E3：把收包按来源过滤 ⇒ 一条都收不到）：进程卡在等初始盘面，
#     而看门狗打印的现场里 `_net_connected` **仍然是 true**。
#     ⇒ 拿它当"初始盘面经 P2P 回环送达"的判据 = **恒真式**（等于没测那件事）。
#     教训同本工程那一条：**判据必须读真源；读一个"顺带也会变真"的量 = 没测**。
var _steam_peer_override: int = 0        # 自检用：强制 Steam 对端（同账号自环，见 SteamTransport.start）
var _net_phase: String = "playing"        # ONLINE 专用：双方准备阶段 ready / 已开始 playing
var _ready_set: Dictionary = {}           # 房主侧记录谁已准备：{color: true}
var _ready_layer: CanvasLayer = null      # 「准备」按钮覆盖层
## 「准备」按钮。★ 2026-10-15 加：它必须**存成员** —— 刷新函数原先靠
## `get_node_or_null("ReadyBtn")` 找它，而那是相对路径（只查直接子节点），按钮在
## `PanelContainer/VBoxContainer/` 底下 ⇒ 恒 null ⇒ "已准备"那一档永远刷不出来。
var _ready_btn: Button = null
## 准备覆盖层里的状态行（"你执X · 对方执Y / 黑 已准备 ｜ 白 未准备"）。
## ★ 与 `_ready_btn` 同一套生命周期：建层时赋值、`_clear_ready_overlay()` 清空
##   （清了以后 `_update_ready_overlay()` 会安全跳过 —— 否则就是往死节点上写字）。
var _ready_hint: Label = null

## 房主开局执哪一色（2026-10-21 座位可选）。**只在 `_start_network()` 里调一次**。
## ★ 随机档在这里掷一次骰子、结果落进 `_net_color`；`_send_init()` 读的是
##   `_opposite_stone(_net_color)`，**不再掷第二次**（两处各掷 = 双方执色相反且静默）。
func _host_color_from_seat() -> int:
	match int(GameConfig.seat_choice):
		GameConfig.SEAT_WHITE:
			return Stone.WHITE
		GameConfig.SEAT_RANDOM:
			return Stone.BLACK if (randi() % 2) == 0 else Stone.WHITE
		_:
			return Stone.BLACK


## 黑白互换（`Stone` 只有 EMPTY/BLACK/WHITE 三值，EMPTY 不参与）。
func _opposite_stone(c: int) -> int:
	return Stone.WHITE if c == Stone.BLACK else Stone.BLACK


func _is_net_server() -> bool:
	# 仅表示「本端是否为权威方（房主）」；
	# 与 _net_connected（是否处于已连接对局）解耦，避免 _on_peer_joined 里出现
	# 「要先 _net_connected 才设 _net_connected」的循环依赖。
	# ★ 2026-09-30 §24 第 5 步：原先这里是 `if _chan != null: return _is_host`，
	#   兜底才是 `multiplayer.is_server()`（ENet）。自建中继 / ENet 双双下线后
	#   **只剩通道一条路**，而且 Steam 侧从来没有 `MultiplayerPeer`（P2P 是我们自己读包）
	#   ⇒ 兜底那一行是**永远走不到**的代码（留着会让"权威怎么定"看起来有两个来源）。
	return _is_host

func _can_local_play() -> bool:
	if game_over or not _net_connected:
		return false
	if game_mode != ONLINE:
		return true
	if _net_phase != "playing":
		return false   # 双方准备阶段，禁止落子/停手/认输
	if _net_awaiting:
		return false
	# ★ 悔棋请求在飞时冻结一切行动：对方正在决定要不要撤，我方此时落子/停手/认输，
	#   会让"退回到我上一手之前"这个语义当场失效（判据 `--undotest` ⑥ 盯着这条）。
	if _undo_freeze:
		return false
	return current_player == _net_color

## 启动联机：房主建大厅 / 加入进大厅（第 5 步后线上只剩 Steam P2P 一条通道）；
## 返回 false 表示失败（调用方应退出 _ready）。
func _start_network() -> bool:
	_is_host = GameConfig.is_host
	# ★★ 座位可选（2026-10-21 用户口令「要能选择座位（黑白棋）」）：房主按
	#   `GameConfig.seat_choice` 定色；加入方这里只能给个占位（白），**真颜色由房主在
	#   `init` 消息里下发**（`_on_relay_message` 的 `"init"` 分支会覆盖它）。
	#   ⚠️ 随机档必须**在这一处掷一次**并落进 `_net_color`：在 `_send_init()` 里再掷一次
	#     就是"两处各掷骰" —— 双方执色会相反，而且**一条错都不报**（本工程 §110 那一家）。
	_net_color = _host_color_from_seat() if _is_host else Stone.WHITE
	_net_phase = "playing"      # 连接成功后若非自检会切到 ready
	_ready_set = {}
	# ★ 2026-09-30 §24 第 5 步删掉了这里的 5 行：`Matchmaking.server_url = …` 与四条
	#   `NetworkManager.*.connect(…)`（peer_joined / peer_left / connected_to_host /
	#   disconnected_from_host）—— 前者属于自建信令服，后者属于 ENet 直连，双双下线。
	#   ⇒ 随之变成**死函数**的 `_on_peer_left` / `_on_net_connected` / `_on_net_disconnected`
	#     也一并删了（它们原本只被这四行引用）；`_on_peer_joined` **保留** ——
	#     Steam 侧的 `_on_relay_ready()` 会直接调它。
	if "--steamnet" in _argv():
		# Steam P2P 自环自检：**同一 Steam 账号、同一台机器**下把对端强制设为自己。
		# ★ 为什么必须强制：实测（`--steamp2p`）同账号 `joinLobby` 自己建的房返回 OK，
		#   但**成员数仍是 1** —— 一个 SteamID 在一个房里只算一个成员 ⇒ 「等对端加入」
		#   这条路在单账号下永远不会成立；而 P2P **回环本身是通的**（发送返回 true、
		#   自己的 readP2PPacket 能收到，只是来源 id 报 0）⇒ 指定对端即可跑通整条链路。
		# ★★ **必须先初始化、再取自己的 id**：`my_id()` 在 `ensure_init()` 之前返回 **0**，
		#    于是 peer_override=0（=不覆盖）⇒ 自检退化成"等第二个成员"⇒ 永远等不到
		#    ⇒ 进程挂死到被 timeout 杀；而 stdout 走管道是块缓冲，被杀时不 flush
		#    ⇒ **日志一个字都没有**，看起来像"代码根本没跑"。实测踩了这一脚。
		_steamnet_active = true
		if not SteamNet.ensure_init():
			print("[steamnet] 环境不可用：state=%s reason=%s" % [SteamNet.state(), SteamNet.reason()])
			print("[steamnet] 结论：失败 ✗（环境不可用 ≠ 代码坏；请先开 Steam 客户端并登录）")
			get_tree().quit()
			return false
		_steam_peer_override = SteamNet.my_id()
		if _steam_peer_override == 0:
			print("[steamnet] 结论：失败 ✗（初始化后仍拿不到自己的 SteamID64）")
			get_tree().quit()
			return false
		print("[steamnet] 自检：Steam 自环模式（对端强制为自己 =%d）" % _steam_peer_override)
		_steamnet_watchdog()
	if "--onlinetest" in _argv():
		# 单进程自环：跳过真实网络，直接模拟已连接（仅用于离线自检 _apply_action 路径）
		_net_connected = true
		_peer_white = 1
		print("联机自检：跳过真实网络，进入自环模式")
		return true
	var err: int
	if _use_steam():
		# Steam P2P（第 2 步）：NAT 穿透由 Steam 自己做，不需要我们运维中继服务器。
		# ★ 房主的 lobby_id 是**异步回调**给的 ⇒ 本函数返回 true 时它可能还是 0，
		#   这不是错误 —— 房间号要在 `_on_steam_lobby_ready()` 里回填（见那里的说明）。
		var sa := _steam_arg()
		var st := SteamTransport.new()
		add_child(st)
		st.relay_ready.connect(_on_relay_ready)
		st.message_received.connect(_on_relay_message)
		st.relay_failed.connect(_on_relay_failed)
		st.lobby_ready.connect(_on_steam_lobby_ready)
		err = st.start(int(sa["lobby"]), str(sa["role"]), int(sa["peer"]))
		if err != OK:
			st.queue_free()
			GameConfig.connection_error = "Steam 联机启动失败：%s（%s）" % [SteamNet.state(), SteamNet.reason()]
			printerr("联机启动失败：", GameConfig.connection_error)
			GameConfig.online = false
			Transition.change_scene("res://menu.tscn")
			return false
		_chan = st
		print("联机启动（Steam P2P）：", sa["role"], " | lobby=", sa["lobby"], " | peer_override=", sa["peer"])
		return true
	# ★★ 2026-09-30 §24 第 5 步：这里原本还有两路 ——
	#   ① `if _use_relay():` 自建 TCP 中继（`RelayTransport` + `Matchmaking.relay_host/port`）；
	#   ② 兜底的 ENet 直连（`NetworkManager.create_server / join_server`）。
	#   两条都随「删除自建联机代码」一起删掉了，所以走到这里 = **没有任何可用通道**。
	#   ★ 必须**显式报错回菜单**，不能静默返回 true：静默的话进程会停在"等初始盘面"，
	#     看起来像网络卡住（本工程在 `--steamnet` 看门狗那里踩过同一类坑：
	#     失败不打印 ⇒ 下游只能看到"没结论"，不知道卡在哪一步）。
	GameConfig.connection_error = "联机启动失败：未指定联机方式（第 5 步后线上只有 Steam P2P 一条通道）"
	printerr("联机启动失败：", GameConfig.connection_error)
	GameConfig.online = false
	Transition.change_scene("res://menu.tscn")
	return false


## 是否走 Steam P2P。
## ★ 第 2 步先用**命令行入口**（`--steamhost` / `--steamjoin=<lobby_id>`）：传输层因此
##   能独立验证，不必等第 3 步的菜单 UI。第 3 步的菜单「联机方式」接上后走的是
##   **同一条分支** —— 菜单只需产出同样的那个字典（`_steam_arg()`）。
func _use_steam() -> bool:
	return not _steam_arg().is_empty()


## Steam 路径的启动参数：`{"role": "host"|"guest", "lobby": int, "peer": int}`。
## 空字典 = 不走 Steam。`peer` 非 0 只有自检用（见 `SteamTransport.start` 的 peer_override）。
func _steam_arg() -> Dictionary:
	# ★ `--onlinetest`（单进程自环，**不进网络**）显式返回空：它把 `mode` 置成 ONLINE
	#   （见 `_ready()` 开头的预处理），不排除就会命中下面那条菜单路径 ⇒ `_use_steam()` 为真。
	#   眼下虽然被 `_start_network()` 里那个 `--onlinetest` 分支抢先 `return true` 兜住，
	#   但那是**靠分支顺序**兜住的 —— 顺序一变就静默分叉，所以判据要写在判据自己身上。
	if "--onlinetest" in _argv():
		return {}
	for a in _argv():
		if a == "--steamhost":
			return {"role": "host", "lobby": 0, "peer": _steam_peer_override}
		if a == "--steamnet":
			# 自检：同机同账号自环（对端强制为自己，见 _start_network 里的说明）
			return {"role": "host", "lobby": 0, "peer": _steam_peer_override}
		if a.begins_with("--steamjoin="):
			# ⚠️ 解析失败（用户输错）时 lobby 会是 0 ⇒ 交给 SteamTransport 判错并给提示，
			#    不要在这里静默退化成"当房主"（那种错法最难查）。
			return {"role": "guest", "lobby": int(a.split("=", true, 1)[1]), "peer": 0}
	# ★★ 菜单路径（§21 第 3 步）：命令行没给参数时读 `GameConfig` —— **两边产出同一个字典**，
	#   所以 `_start_network()` 的第三路与 `SteamTransport` 一个字都不用改。
	# ★★ 两个条件**一个都不能少**（2026-09-30 §24 追修，P0 实测）：`mode` 回答"这一局
	#   **是不是**联机"，`net_channel` 回答"联机**走哪条通道**" —— 两者正交，只认一边必然误判另一边。
	#   · 只认 `net_channel`（首版写法）的代价：第 5 步后通道**恒为** `CHAN_STEAM`（自建档已删）
	#     ⇒ 判据恒真 ⇒ **单机/人机局**与**全部游戏侧自检**都被 `_ready()` 的预处理改写成
	#     ONLINE + Steam。Steam 客户端在跑时**真的建了个大厅**（`--hatdead` 实测建了 lobby，
	#     之后卡在"等对端"，退出时 `Stalled cross-thread pipe` ⇒ exit=1）；
	#     不在跑时自检**整条不跑**（日志零判据行）而 `exit` 仍是 0 ——
	#     `--captest` / `--gridtest` / `--randtest` / `--cubetest` 就是这样假绿过去的。
	#   · 只认 `mode` 的代价：菜单里选了 Steam 但没点"进入对局"时会被当成联机（同类静默分叉）。
	#   ★ `mode` 是**安全**的那一半：它由菜单在同一个必经点写（`_push_board_choice()` 旁，
	#     见 `menu.gd::_host_enter_game()` / `_steam_join_by_id()` / `_start_from_setup()`），
	#     铁律 8"一处写、一处读"。自检/直接启动 `game.tscn` 时它是 `-1` ⇒ 天然不联机。
	#   ⇒ 结构守卫 **S33** 钉的就是下面这一行（少写一半立即红）。
	if GameConfig.mode == GameConfig.ONLINE and GameConfig.net_channel == GameConfig.CHAN_STEAM:
		var as_host: bool = GameConfig.is_host
		return {
			"role": "host" if as_host else "guest",
			# 房主侧 lobby 恒 0（id 由 `createLobby` 的异步回调给出，见 `_on_steam_lobby_ready`）；
			# 加入方必须带真实 id —— 为 0 时 `SteamTransport.start()` 会判错，不会静默当房主。
			"lobby": 0 if as_host else GameConfig.steam_lobby,
			"peer": _steam_peer_override,
		}
	return {}


## 房主侧「拿到房间号」的时刻 —— **早于** `relay_ready()`。
## ★ 这是 Steam 与自建中继**最本质的差异**：中继的邀请码在开局前就已知，而 Steam 的
##   `lobby_id` 是 `createLobby()` 异步回调之后才有的。⇒ UI 绝不能同步去读它，
##   房主进对局后"房间号先空着、随后回填"是**正常**行为，不是 bug。
##   （第 3 步的菜单/大厅 UI 要挂在 `SteamTransport.lobby_ready` 上。）
func _on_steam_lobby_ready(lobby_id: int) -> void:
	GameConfig.invite_code = str(lobby_id)
	_update_hud()
	# ★ 联机大厅（2026-10-01）：房主把自己的标识写进 lobby data，陌生人浏览大厅时读到并显示。
	#   只有房主写（加入方不建房、没有 lobby 可写）。`game` 是浏览时的过滤键（SteamNet.request_lobby_list）。
	SteamNet.lobby_set_data(lobby_id, SteamNet.LOBBY_GAME_KEY, SteamNet.LOBBY_GAME_TAG)
	SteamNet.lobby_set_data(lobby_id, SteamNet.LOBBY_NAME_KEY, SteamNet.my_persona())
	SteamNet.lobby_set_data(lobby_id, SteamNet.LOBBY_RECORD_KEY, GameConfig.record_str())
	# ★ 固定前缀的一行，便于自动化核对（阴性对照仪也靠它）
	print("[steamnet] 房间号 lobby_id=", lobby_id)


## `--steamnet` 自检的判据体。**在收到房主初始盘面之后**才跑 —— 因为那一刻已经覆盖了
## 建房 → lobby_id → P2P 回环 → 解码 → `_apply_snapshot` → `_net_connected` 整条链，
## 是最有牙齿的位置（前面每一步断了都到不了这里）。
func _steam_net_selftest_finish() -> void:
	print("[steamnet] ---- 判据 ----")
	var checks: Array = []

	# ★★ 判据名的格式纪律（**必须遵守，否则这条红读不出来**）：
	#   名字里**不许用全角括号**，用 `｜` 分隔 —— 阴性对照仪靠 `line.split("（")[0]`
	#   切出"哪一条判据红了"，名字里带全角括号会把尾巴切掉，于是那条红退化成
	#   「无编号判据红，看结论」（第 1 步 `②a` / `④c` 就是这么被吞掉理由的，本轮又犯一次）。
	#   ★ 这条纪律现在有**静态守卫**：struct_guard.py 的 S26 扫 `append(["…` 里的第一段字符串。
	checks.append(["① 通道是 SteamTransport｜第三路真的接上了，不是退回中继/ENet",
			_chan is SteamTransport, "类型=%s" % ("SteamTransport" if _chan is SteamTransport else str(_chan))])
	var st: SteamTransport = _chan as SteamTransport
	checks.append(["② 通道已就绪 is_live()", st != null and st.is_live(),
			"is_live=%s" % str(st != null and st.is_live())])
	var lid := st.get_lobby_id() if st != null else 0
	checks.append(["③ 拿到有效 lobby_id｜建房回调真的回来了", lid != 0, "lobby_id=%d" % lid])
	var my := SteamNet.my_id()
	checks.append(["④ 对端是自己｜证明 peer_override 生效｜同账号自环",
			st != null and st.get_peer() == my, "peer=%d 自己=%d" % [
					st.get_peer() if st != null else -1, my]])
	# ★⑤ 最有牙齿的一条：初始盘面**真的经 P2P 回环被应用了** ——
	#   发送 / 编码 / Steam 投递 / 读取 / 解码 / 应用，任何一环断了都到不了这里。
	#   ⚠️ 口径必须是 `_init_applied`（只在收到 init 那一刻置真），**不能**读 `_net_connected`：
	#     后者是双向语义，房主在 `_on_relay_ready() → _on_peer_joined()` 里就把它置真了 ——
	#     实测（阴性对照 E3：收包全被过滤）卡在等盘面时它**依然是 true** ⇒ 读它 = 恒真式。
	checks.append(["⑤ 初始盘面经 P2P 回环送达且已应用｜_init_applied 置真", _init_applied,
			"_init_applied=%s _net_connected=%s 瓷砖=%d" % [
					str(_init_applied), str(_net_connected), board.size()]])

	# ⑥ 业务消息真往返：临时再发一条**自定义**消息（不经对局业务路径），断言收到
	var got: Array = []
	var cb := func(m: Dictionary) -> void:
		got.append(str(m.get("m", "")))
	if st != null:
		st.message_received.connect(cb)
		st.send_message({"m": "probe_steamnet", "n": 42})
	var w := 0
	while got.is_empty() and w < 180:
		await get_tree().process_frame
		w += 1
	if st != null:
		st.message_received.disconnect(cb)
	checks.append(["⑥ 业务消息真往返｜发一条自定义消息，经 P2P 回环收到",
			got.has("probe_steamnet"), "等待 %d 帧 收到=%s" % [w, str(got)]])

	# ⑦ 房间号真的**回填进了配置** —— 第 3 步的菜单/大厅 UI 就挂在 `lobby_ready` 上。
	# ★ 为什么必须单列一条：③ 读的是 `st.get_lobby_id()`（传输层内部状态），
	#   本条读的是 `GameConfig.invite_code`（「信号 → 回调 → 回填」那一整条链路）。
	#   把 `st.lobby_ready.connect(_on_steam_lobby_ready)` 摘掉、或在 `_on_steam_lobby_ready`
	#   里把赋值删掉，**③ 照样绿** —— 只有本条会红。那种坏法在 UI 上的表现是
	#   "房主进对局后房间号永远是空的"，而其它判据一片绿（静默失效）。
	var lid_s := str(lid)
	checks.append(["⑦ 房间号已回填 GameConfig.invite_code｜lobby_ready 信号真接到了 handler",
			lid != 0 and GameConfig.invite_code == lid_s,
			"invite_code=%s 期望=%s" % [GameConfig.invite_code, lid_s]])

	# ⑦b 邀请好友按钮（2026-10-21 用户口令「在游戏里直接点击就能召唤 steam 邀请好友窗口」）：
	#   房主建房后它必须**真的出现在 HUD 上且可点**。
	#   ★ 为什么这条必须在这里（`--steamnet` 自环）而不是在 HUD 布局自检里：
	#     它是**联机专属**控件，只有走到"房主 + 房间号已回"这一刻才该出现 ——
	#     布局自检跑在本地档，永远看不到它（量不到 = 等于没有判据）。
	#   ★ 先重派生一次再量：可见性的唯一写点是 `_update_hud() → _refresh_invite_btn()`，
	#     判据要量的是**派生结果**，不是在别处手写一个 visible=true 来通过。
	#   ⚠️ 必须排在下面 ⑧ 的阴性对照**之前**：`close_relay()` 会退房 ⇒ 房间号归零 ⇒
	#     按钮按设计变成"不可点"，那时再量就是拿一个已失效的状态当被测物。
	_update_hud()
	var inv_exists: bool = _invite_btn != null and is_instance_valid(_invite_btn)
	var inv_vis: bool = inv_exists and _invite_btn.visible
	var inv_can: bool = inv_exists and not _invite_btn.disabled
	checks.append(["⑦b 邀请好友按钮在房主态可见且可点｜用户口令的入口真的存在",
			inv_exists and inv_vis and inv_can,
			"存在=%s 可见=%s 可点=%s 房间号=%s 提示=%s" % [
					str(inv_exists), str(inv_vis), str(inv_can),
					GameConfig.invite_code,
					(_invite_btn.tooltip_text if inv_exists else "")]])

	# ⑧ 阴性对照：证明 ② 不是恒真（关掉之后必须转 false）
	if st != null:
		st.close_relay()
	checks.append(["⑧ 关闭后 is_live() 转 false｜阴性对照：证明 ② 不是恒真",
			st != null and not st.is_live(), "关闭后 is_live=%s" % str(st != null and st.is_live())])

	var failed: Array = []
	for c in checks:
		var okc: bool = (c[1] is bool) and (c[1] as bool)
		if not okc:
			failed.append(str(c[0]))
		print("[steamnet] %s %s（%s）" % [c[0], "✓" if okc else "✗", c[2]])
	print("[steamnet] 判据 %d 条，失败 %d 条%s" % [checks.size(), failed.size(),
			"" if failed.is_empty() else "：" + ", ".join(failed)])
	print("[steamnet] 结论：", "通过 ✓" if failed.is_empty() and checks.size() > 0 else "失败 ✗")
	get_tree().quit()


## `--steamnet` 的看门狗：任何一步卡住（等建房回调、等 P2P 回环）都**不许挂死到被 timeout 杀** ——
## 那时 stdout 的块缓冲整个丢失，日志里连一行判据都没有，看起来像"代码根本没跑"（实测踩过）。
## 到点强制打印结论再退出，把"卡在哪一步"变成一条**可读的红**。
func _steamnet_watchdog() -> void:
	await get_tree().create_timer(30.0).timeout
	var lid := -1
	var peer := -1
	var live := false
	if _chan is SteamTransport:
		lid = (_chan as SteamTransport).get_lobby_id()
		peer = (_chan as SteamTransport).get_peer()
		live = _chan.is_live()
	print("[steamnet] 看门狗：30 秒内没走完（卡在等建房回调 / 等 P2P 回环）")
	print("[steamnet] 现场：_chan=%s｜lobby_id=%d｜peer=%d｜is_live=%s｜_init_applied=%s｜_net_connected=%s" % [
			str(_chan), lid, peer, str(live), str(_init_applied), str(_net_connected)])
	# ★★ 结论行的**前缀必须与主出口逐字一致**（`[steamnet] 结论：`）——
	#   这个自检有**两个出口**（正常跑完 / 看门狗兜底），而下游解析器（阴性对照仪、
	#   回归里的 grep）只认这一个前缀。首版写成「看门狗：… ⇒ 结论：失败 ✗」，
	#   字符串里**不含** `[steamnet] 结论` ⇒ 对照仪当场报「?? 没找到结论行（自检没跑起来 /
	#   进程挂了）」，把一条**明明打出来了的红**读成了"没有结论"（实测踩过）。
	#   ⇒ 第 1 步那条教训的新面孔：**同一个自检有多条出口时，每条出口的格式必须与
	#     解析器约定逐字一致**；多一条出口就要多验一次格式。
	print("[steamnet] 结论：失败 ✗（看门狗超时：等建房回调 / 等 P2P 回环没走完）")
	get_tree().quit()


## 发送本地动作到对端（server-authoritative）
## 房主（= 权威方）本地即为权威：直接应用 + 广播给对端；加入方发给房主等待回放。
## ★★ 2026-09-30 §24 第 5 步：这里原先还有 ENet 那一路（`apply_action.rpc()` /
##   `request_action.rpc_id(1, …)`）以及一个 `if _chan != null:` 的双路判断，两个 `@rpc`
##   函数（`request_action` / `apply_action`）也在这里。自建联机下线后通道成为**唯一**路径，
##   「所有动作都经 `_chan`」不再有例外 ⇒ 双路判断与两个 `@rpc` 一并删除
##   （删 `@rpc` 的依据：它们的**唯一**调用者就是刚删掉的那两行，全工程再无引用）。
func _net_send_action(action: Dictionary) -> void:
	if not _net_connected:
		print("未连接到对局，无法发送动作")
		return
	if _chan == null:
		# 通道未建立 ⇒ **不许退回"本地应用"**：那会让两端状态**静默分叉**（最难查的一类）。
		# 显式报错、丢弃动作。`--onlinetest` 自环虽然满足 `_net_connected=true` 却没有通道，
		# 但它从来不走本函数（判据里直接调 `_apply_action`），所以不受影响。
		printerr("对局通道未建立，动作被丢弃：", action)
		return
	# 房主本地即权威 → 应用 + 发给对端；加入方发给房主等待回放
	if _is_host:
		_apply_action(action)
		_chan.send_message({"m": "apply", "action": action})
	else:
		_net_awaiting = true
		_chan.send_message({"m": "request", "action": action})

## ====== 对局通道（第 5 步后 = Steam P2P）======
## 通道只负责把消息原样送到对端；权威判定 / 回放 / 校验仍全部在本文件。
## ★ 函数名保留 `relay_*` 前缀：它是 `NetChannel` 基类的信号名（契约），改名要动基类与
##   `SteamTransport` 两侧，收益为零 —— 「中继」在这里只是历史词，不再是通道类型。
func _on_relay_ready() -> void:
	if _is_host:
		# 通道就绪 ⇒ 等价于「对方已加入」，房主随即下发初始盘面。
		# （`peer_id` 传 2 只是沿用中继时代的占位：真正用到的是 `_peer_white` 这个槽位，
		#   而且通道**从不拿它做 RPC 目标** —— 证据见 `_on_peer_joined()` 的函数体。）
		#   ★ 第 5 步后只有 Steam 一条通道，将来若把 2 改成别的值也**不该**改行为，
		#     它只是个"非负数"占位（`_peer_white < 0` 才是"还没有对端"的判据）。
		_on_peer_joined(2)
	else:
		print("[Chan] 已连上房主，等待初始盘面…")
		_update_hud()

func _on_relay_message(msg: Dictionary) -> void:
	match msg.get("m", ""):
		# ---- 悔棋协议（2026-10-02）：请求 / 回执，两条都不是"权威动作" ----
		# ★ 刻意**不进** `_apply_action`/`_validate_action`：那套是"房主权威 → 直接执行"，
		#   而悔棋是**双方同意**语义 —— 收到 req 不能自顾自地撤，必须先问本机玩家。
		#   另起两个 m 值的原因就在这里（塞进 action 里就得给 `_validate_action` 加豁免，
		#   那会让"回合校验"这层多出一个例外口子）。
		"undo_req":
			var asker: int = int(msg.get("color", -1))
			if asker < 0 or asker == _net_color:
				return
			if _undo_pending_from >= 0:
				return      # 本机也有请求在飞 → 双方各提各的会打成死循环，忽略后到的那条
			_on_undo_req_received(asker)
		"undo_res":
			_on_undo_res_received(bool(msg.get("ok", false)), int(msg.get("target_color", -1)))
		"emote":
			# ── 快捷表情（2026-10-21）──
			# ★ 刻意**不进** `_apply_action` / `_validate_action`：那套是"房主权威 → 直接执行"，
			#   而表情不改变任何棋盘状态、也不需要房主仲裁（与 `undo_req`/`undo_res` 同一个定位：
			#   塞进 action 里就得给回合校验加豁免，"该谁走"那层会多一个例外口子）。
			# ★ "idx 是否合法"**不在这里另写一份**：唯一守卫在 `_play_emote()` 开头。
			#   两处各校验一次的话，删掉其中一处判据根本不会红（行为被另一处兜住了）——
			#   那是"看着有两道防线、实际只有一道"的典型（§111 同一公式只许一处）。
			#   这里只负责把 Variant 收成 int（§109：Dictionary 取值赋给 int 形参前显式转）。
			_play_emote(1, int(msg.get("e", -1)))
		"request":
			# 仅房主处理：校验 → 本地应用 → 广播回放给对端
			if not _is_host:
				return
			var action: Dictionary = msg["action"]
			if not _validate_action(action, _peer_white):
				print("拒绝非法/非当前回合动作：", action)
				return
			_apply_action(action)
			_chan.send_message({"m": "apply", "action": action})
		"apply":
			_apply_action(msg["action"])
			_net_awaiting = false
		"init":
			var data: Dictionary = msg["data"]
			# ★ 座位可选之后这一行是**加入方执色的唯一真源**（`_start_network()` 里那个
			#   `Stone.WHITE` 只是占位；房主执白时真值在这里覆盖成黑）。按本工程口径
			#   （§109）Dictionary 取值赋给 int 前显式 `int()` —— 解码层给的是 Variant。
			_net_color = int(data["net_color"])
			_apply_snapshot(data)
			_net_connected = true
			_init_applied = true    # ★ `--steamnet` 判据 ⑤ 读这个（理由见变量声明处）
			_update_hud()
			print("已接收房主初始盘面，开始对局")
			if _steamnet_active:
				# Steam 自环自检：能走到这里就说明「建房 → lobby_id → P2P 回环 → 解码 →
				# _apply_snapshot → _net_connected」整条链已经跑通（判据见 _steam_net_selftest_finish）。
				_steam_net_selftest_finish()
				return
			# ★ 2026-09-30 §24 第 5 步：这里原有两条 `_matchtest_active`（自建中继
			#   邀请自检）分支 —— 客户端核对 `board[0]` 那条、以及下面 `if not …` 的
			#   "自检跳过准备阶段" 那条，随自检一起删除。现在**无条件**进准备阶段。
			#   Steam 自检（`_steamnet_active`）走的是上面那条 `return`，不受影响。
			_net_phase = "ready"
			_show_ready_overlay()

func _on_relay_failed() -> void:
	# ★ 这个回调是 `NetChannel` 基类的契约（各实现共用）。虽然第 5 步后线上只剩 Steam，
	#   这里**仍然保持"通道无关"的写法**、不硬编码 "Steam"：将来再加一条通道时它会自动跟上。
	#   反例就在眼前 —— 2026-09-30 §21 第 3 步之前这里写死的是"中继"，接上 Steam 后
	#   掉线提示会对玩家说"中继连接已丢失"（玩家根本不知道有中继这回事）。
	print("[Chan] 对局通道中断（%s）" % ("Steam" if _chan is SteamTransport else "未知通道"))
	_net_connected = false
	_net_phase = "playing"
	_net_awaiting = false
	_clear_ready_overlay()
	_show_result_overlay("与对家断开", PackedStringArray(["与对家的连接已丢失，按返回菜单"]))
	_update_hud()

## 纯权威应用：落子 / 加砖 / 停手 / 认输 / 重置。服务器本地执行一次，
## 所有客户端通过 apply_action 回放同一份，保证状态一致。
func _apply_action(action: Dictionary) -> void:
	match action["type"]:
		"place":
			place_stone(action["tile"])
		"pass":
			# 容错：正常路径上 color 必存在（_validate_action 已校验），
			# 缺失时退回当前回合方，避免畸形动作把对局打断
			_apply_pass(int(action.get("color", current_player)))
		"resign":
			_resign_game(action["loser"])
		"reset":
			restart_game(int(action.get("seed", -1)))
		"ready":
			_on_ready(action["color"])
		"start":
			_begin_play()
	_update_hud()
	queue_redraw()

## 停一手纯逻辑（单机与联机共用）：交换回合，连续两次 → 终局
## passer：停手方颜色。联机时由动作携带（`action["color"]`）—— 不能用 `current_player` 代替，
## 因为服务器/客户端回放的时序不同，显式传参才能保证「谁停的手」判断一致。
func _apply_pass(passer: int = -1) -> void:
	var who_color: int = current_player if passer < 0 else passer
	# ★ 停一手也入悔棋栈：它同样把行棋权交给对方，同样"消耗一次机会"。
	#   只记落子不记停手 ⇒ 连着两次停手终局后点悔棋，会撤到"停过一手"的那个局面，
	#   而 passes 已经被终局收尾改过 ⇒ 回滚出来的 passes 与盘面对不上（症状：悔完又立刻终局）。
	var passes_before := passes
	passes += 1
	var who := "黑方" if who_color == Stone.BLACK else "白方"
	print("%s停一手（连续 %d 次）" % [who, passes])
	if not _quiet_place:
		_hist.append({
			"tile": -1,
			"color": who_color,
			"captured": [] as Array[int],
			"ko_before": ko_point,
			"passes_before": passes_before,
			"last_move_before": _last_move,
			"pass_move": true,
		})
		# ★ 停一手**同样入谱**（tile = -1）：谱只记落子的话，按谱重放会在连停两手终局处
		#   少走两手 ⇒ 重放出来的局面根本到不了终局（差的是"谁停的、停了几次"这条信息）。
		#   ⚠ 同 `place_stone()`：守卫与 `_hist` 写在一起，负控刀 R5 盯的就是这一处。
		_record_move(-1, who_color, 0, ko_point)
		# ★ 棋钟：停一手**同样算一手**（同样消耗时间、同样重置读秒）。
		#   不算的话，"钟快没了就停一手"会变成一条免费的续命漏洞（还在读秒里白赚 30 秒）。
		if _clk != null:
			_clk.on_move(who_color)
	queue_redraw()
	if passes >= 2:
		_finish_game()
		return
	current_player = Stone.WHITE if current_player == Stone.BLACK else Stone.BLACK
	_update_hud()
	# 轮到「人」来决定了 → 问一句要不要数子（自己点的停一手不会弹给自己）
	_prompt_count_after_pass(who_color)

# ====== 悔棋（退到「我上一次落子之前」）======
## ★ 语义（用户 2026-10-02 定调「悔棋一手」在棋理上唯一成立的形态）：
##   **退到发起方上一次落子之前** —— 即撤销「对方那手 + 我上一手」，
##   回到"轮到我、且我能改走上一手"的那个点。
##   为什么不能只退盘面最后一手：那一手是**对方**下的 ⇒ 撤了它，轮到我走却把我上一手留着了，
##   等于我连走两步、对方一步都没走 —— 这不是悔棋，是让棋。只退自己的手则要等"我下完还没轮到我"
##   的时刻才成立，而正常对局里点悔棋时**已经轮到我了**，那个时刻不存在。
## ⇒ 这个定义天然统一三种模式，不需要三套代码：
##   · VS_AI  "我" = 玩家色（黑），推到最近一次玩家落子之前 ⇒ 接下来 AI 会重新走一遍
##   · LOCAL   "我" = 当前玩家（同屏双人，切到另一侧视角重走）
##   · ONLINE  "我" = 请求方（对方同意后两端各自回滚到**同一个**局面）
## ★ 联机两端各自调 `undo_to_my_turn()` 而不是"退固定手数"：栈是同步的、退化规则也是确定的
##   ⇒ 两端退到同一位置（判据 `--undotest` ⑨ 逐键对账）。
##
## 返回：实际撤销了几手（0 = 没得撤，调用方据此给提示）。
func undo_to_my_turn() -> int:
	if _hist.is_empty():
		return 0
	# ★ `game_over` **不清栈**，而是允许悔棋把它收回 —— 终局后悔棋是真实需求
	#   （数子完觉得算错了，退回去接着下）。判据 `--undotest` ⑧ 盯着这条。
	#   `_ai_gen` 代次仍要递增：终局时 AI 的协程可能正在收尾，同族坑见下。
	# ★ 我（发起方）认定的颜色：联机是本机执色，其余是当前行棋方。
	#   LOCAL 的"我"= current_player，所以先记下来再改（下面会把 current_player 翻回去）。
	var me: int = _net_color if game_mode == ONLINE else current_player
	var undone: int = 0
	# 第一步：撤销**对方**那手（若栈顶不是我落的，说明我还没走过 → 那就只能退到开局）。
	#   之后反复弹栈，直到「栈空」或「栈顶是我的手」为止 —— 那才是"我上一次落子"。
	while not _hist.is_empty():
		var e: Dictionary = _hist[_hist.size() - 1]
		if int(e["color"]) == me:
			break
		_pop_history_entry(e)
		undone += 1
		if undone > 2:
			# 理论上不可能（我与对方交替落子），但**必须有这个刹车**：
			# 万一栈被某种路径污染成连续 3 手对方，`while` 会一路退到开局而无从察觉。
			# 宁可真源出错时立刻停下（后续判据会红），也不要静默把整局撤光。
			push_error("[悔棋] 栈中连续 %d 手都是对方所下，已中止回滚（历史可能异常）" % undone)
			break
	if _hist.is_empty():
		# 退到开局：行棋方必须回黑（开局永远黑先），不能停在"被撤那手之前的那个 current_player"
		#   —— 那些值是对方手的前驱语义，与开局无关。
		current_player = Stone.BLACK
		ko_point = -1
		passes = 0
		_last_move = -1
	else:
		_pop_history_entry(_hist[_hist.size() - 1])
		undone += 1
	_place_anims.clear()
	_capture_anims.clear()
	_clear_count_prompt()
	# ★★ 三处必须由悔棋**主动**做，没有别处会替它做：
	#   ① `_ai_gen += 1`：AI 正在思考时，它的协程醒来只查 `gen != _ai_gen`
	#     （`_start_ai_turn` 第 799 行）⇒ 不递增的话，**正在算的那手会被落在已撤销的盘面上**
	#     —— 即"悔完棋 AI 又落一子"，而且是落在一个根本不存在的局面里。
	#   ② `is_ai_thinking = false` + `_show_ai_hud(false)`：思考态的收尾原本只在
	#     `_start_ai_turn` 自己的收尾里做，悔棋把它掐断 ⇒ 秒表协程会永远 await 下去。
	#   ③ 末尾重新 `_start_ai_turn()`：**没人会因为"盘面变了"自动触发 AI 回合**
	#     （`_start_ai_turn()` 的四个调用点全是"玩家刚下完子"）⇒ 漏了这行，
	#     悔完棋 AI 就永远不再走（用户看到的是"悔棋没反应"）。
	_ai_gen += 1
	is_ai_thinking = false
	_show_ai_hud(false)
	# 终局态也要收回：悔棋的语义是"退回到我上次能走的时候"，那时这局还没结束。
	#   不收回的话 `game_over` 仍为 true → HUD 继续显示结算、`can_undo()` 恒 false、
	#   `_validate_action` 也拒收联机动作，等于"悔了但这局还锁着"。
	if game_over:
		game_over = false
		_clear_result_overlay()
		_terr_mark.clear()      # 终局描边是按终局盘面 flood fill 出来的，退回后全部作废
	# ★ `_undo_used` **刻意不清**：联机 3 次/局是"每局"的额度，悔棋不重置额度
	#   （否则联机方可以无限悔 —— 判据 `--undotest` ⑦ 咬着这条）。
	queue_redraw()
	_update_hud()
	if game_mode == VS_AI and current_player == AI_COLOR and not game_over:
		_start_ai_turn()
	return undone

## 弹掉一条历史并把盘面**精确还原**到它落下之前。
## ★ 三处「不是改一个值」而是「按存档恢复」的地方，都是曾想过就地凑合的地方：
##   ① 被提的子要**放回盘面**且颜色 = 落子方的对方（放错颜色 = 棋形凭空变色）；
##   ② `black_prisoners/white_prisoners` 要**减掉**本手提子数（不减 = 每悔一次提子数就虚增，
##      终局分数会一路漂上去，且只增不减 —— 典型的"慢漂"型 bug，肉眼要下几十手才发现）；
##   ③ 动画字典要清（不然会留一个"悔掉的子"还在下落/淡出）。
func _pop_history_entry(e: Dictionary) -> void:
	_hist.pop_back()
	# ★ superko 历史同步：撤掉的这一手若产生过一个新局面，要从历史里摘掉 ——
	#   否则那个局面**永久留档**，以后真的下到它会被误判成"同形再现"（悔棋把未来的棋禁了）。
	#   ⚠️ 必须在**回滚盘面之前**取 hash（此时 `_superko_hash()` 反映的正是"被撤那手之后"的局面）。
	#   ⚠️ 必须跳过 pass：pass 不产生新局面，盘面未变 ⇒ 取到的 hash 是**上一手落子后**的，
	#     不跳过就会把那一手的历史误摘（症状：悔完再重下同一手被判同形再现）。
	#   同一局面不可能由两手产生（superko 本就禁止重复）⇒ 直接 erase 是安全的。
	if not bool(e.get("pass_move", false)) and not _quiet_place:
		_superko_hist.erase(_superko_hash())
	# ★ 棋谱同步截断**在同一个原语里**（不是各调用方自己记得截）：
	#   漏截的后果不是"谱多一行"而是"按谱重放走到末手时盘面与实际终局不同"，且**静默**。
	_record_trim()
	var mover: int = int(e["color"])
	var dead: Array = e["captured"]
	if not bool(e["pass_move"]):
		var t: int = int(e["tile"])
		if t >= 0 and t < board.size():
			board[t] = Stone.EMPTY
		var opp: int = Stone.WHITE if mover == Stone.BLACK else Stone.BLACK
		for vid in dead:
			board[vid] = opp      # ① 放回原位，颜色是被提方
		if dead.size() > 0:        # ② 提子计数同步减回
			if mover == Stone.BLACK:
				black_prisoners = maxi(0, black_prisoners - dead.size())
			else:
				white_prisoners = maxi(0, white_prisoners - dead.size())
	current_player = mover           # ③ 行棋权交回落子方（它才可能改走这一手）
	ko_point = int(e["ko_before"])
	passes = int(e["passes_before"])
	_last_move = int(e["last_move_before"])

## 已用悔棋次数（按颜色计）。联机每方各自 3 次。
func undo_used(color: int) -> int:
	return int(_undo_used.get(color, 0))

## 悔棋是否可用 —— HUD 按钮的 enabled 与 `_update_hud()` 都读它（**一处判、一处读**，
## 铁律 7：按钮显示与实际行为必须由同一个谓词派生，只改文案不改行为 = "点了没反应"）。
func can_undo() -> bool:
	if game_over or _hist.is_empty():
		return false
	if _undo_pending_from >= 0:
		return false        # 有请求在飞：锁住，防止连点发出第二个请求
	if game_mode == ONLINE:
		if not _net_connected:
			return false
		if undo_used(_net_color) >= UNDO_LIMIT_ONLINE:
			return false
	return true

## 服务器校验：发送方必须是该颜色持有者，且必须是当前回合方，动作本身合法
func _validate_action(action: Dictionary, sender: int) -> bool:
	if not _net_connected or game_over:
		return false
	if not action.has("type") or not action.has("color"):
		return false
	var color: int = action["color"]
	if sender != _peer_of_color(color):
		# 房主自己发给自己的动作（peer 1）也视为合法
		if not (_is_net_server() and sender == 1):
			return false
	# 准备（ready）不校验回合：任意一方在自己准备阶段点「准备」都合法
	if action["type"] != "ready":
		if current_player != color:
			return false
	match action["type"]:
		"place":
			var t: int = action.get("tile", -1)
			if not board.has(t) or board[t] != Stone.EMPTY:
				return false
			if t == ko_point:
				return false
		"pass", "resign", "reset", "ready", "start":
			pass
		_:
			return false
	return true

## 颜色 → 持有该颜色的 peer id。
## ★★ 2026-10-21 座位可选后**不许再假设"房主恒黑"**：房主执白时，黑方是**对方**。
##   旧实现 `return 1 if color == Stone.BLACK else _peer_white` 会让"对方执黑"的每一个动作
##   都被 `_validate_action()` 判成"发错人"而拒收 —— 症状是黑方一步都落不下去、房主侧日志
##   刷「拒绝非法/非当前回合动作」，而双方网络完全正常（静默失效里最难查的一家）。
## ★ 口径：`_net_color` 在**房主侧就是房主的颜色**（`_start_network()` 按座位定），
##   所以"谁是 1 号"由它派生，不再由枚举值写死。
func _peer_of_color(color: int) -> int:
	if _is_host:
		return 1 if color == _net_color else _peer_white
	# 加入方：房主是 peer 1。本函数主要在房主侧被 `_validate_action()` 调用，
	# 这里按同一口径兜住（不假设"房主=黑"）。
	return _peer_white if color == _net_color else 1

# ====== 悔棋（2026-10-02 用户口令「AI 对战可以自由悔棋一手，联机则需要发送请求双方同意」）======
## 悔棋按钮按下。**三模式分派**只有一处（铁律 8：一处写、一处读）。
func _on_undo_pressed() -> void:
	if game_mode == ONLINE:
		_online_undo_pressed()
		return
	# 人机 / 本地双人：直接悔，无次数上限（用户口径「AI 对战可以自由悔棋」）
	if not can_undo():
		print("现在不能悔棋（棋局已终、尚无落子、或联机请求在飞）")
		return
	var n: int = undo_to_my_turn()
	print("悔棋：撤销 %d 手 → 回到%s行棋" % [n, "黑" if current_player == Stone.BLACK else "白"])

## 联机：发悔棋请求（**不**直接执行 —— 对方可能不认）。
## ★ 这里**故意不走 `_net_send_action`**：那条是"发出去对方 `_apply_action` 直接执行"，
##   而悔棋是**双方同意**语义 —— 发出后本机必须等回执，期间不能自己撤。
##   另开 `undo_req`/`undo_res` 两种消息，见 `_on_relay_message` 的对应分支。
func _online_undo_pressed() -> void:
	if not _net_connected:
		print("未连接，无法请求悔棋")
		return
	if _undo_pending_from >= 0:
		print("已发出悔棋请求，等对方回应")
		return
	if undo_used(_net_color) >= UNDO_LIMIT_ONLINE:
		print("悔棋次数已用完（每局 %d 次）" % UNDO_LIMIT_ONLINE)
		return
	if _hist.is_empty():
		print("还没有落子，无从悔起")
		return
	_undo_pending_from = _net_color
	_undo_freeze = true          # 冻结本机落子/停手/认输（`_can_local_play` 读它）
	_chan.send_message({"m": "undo_req", "color": _net_color})
	_show_undo_overlay("等待对方同意", "已向对方发出悔棋请求", false)
	_update_hud()

## 收到对方的悔棋请求：弹裁决面板（同意 / 拒绝）。
## ★ 冻结落子的理由：悔棋要撤"上一手"，对方在这期间落子会让回滚语义与请求发出时不一致
##   （本机栈顶是对方那手，但对方新落的子已经压在上面了 ⇒ 两端退回不同局面）。
func _on_undo_req_received(from_color: int) -> void:
	_undo_pending_from = from_color
	_undo_freeze = true
	_show_undo_overlay("对方请求悔棋", "对方希望退回到自己上一手之前", true)
	_update_hud()

## 裁决结果回执。
##   `ok == true`  → **两端各自**调 `undo_to_my_turn()`：栈在两端同步、退化规则确定，
##                    所以退到的是同一个局面（判据 `--undotest` ⑨ 逐键对账，
##                    而不是"退固定手数"那种看起来能对、实际会飘的做法）。
##   `ok == false` → 只清冻结态，盘面一子不动。
func _on_undo_res_received(ok: bool, target_color: int) -> void:
	if ok:
		# 额度记在**请求方**名下（`target_color` 由请求方给出，两端记同一个键）。
		_undo_used[target_color] = undo_used(target_color) + 1
		# ★★★ 两端都必须以 **target_color（请求方）** 为"我"来退，**不能**各用各的 `_net_color`。
		#   这是本轮实测抓到的真 bug：`undo_to_my_turn()` 在联机取 `me = _net_color`，
		#   而请求方是黑、被请求方是白 ⇒ 黑端撤「白那手 + 黑上上手」、白端撤「黑那手 + 白上上手」
		#   ⇒ **两端退回不同局面**（判据 `--undotest` ⑨ 实测 turn=1 vs turn=2）。
		#   症状很隐蔽：两边盘面看着都合法、都能继续下，但从此两边的棋**已经不是同一盘**了
		#   —— 属于"联机静默分叉"，是这类改动最危险的一类故障。
		#   ⇒ 语义定死：**悔棋的落点由请求方决定，两端执行同一个决策**。
		undo_to_my_turn_as(target_color)
		_clear_undo_overlay()
	else:
		_clear_undo_overlay()
		_show_result_overlay("对方拒绝了悔棋",
				PackedStringArray(["悔棋需要双方同意，本次未撤销"]))
	_undo_pending_from = -1
	_undo_freeze = false
	_update_hud()

## 联机裁决按钮回调（弹窗上的两个按钮共用，按 name 区分）。
func _on_undo_decide(agree: bool) -> void:
	var asker: int = _undo_pending_from
	if asker < 0:
		_clear_undo_overlay()
		return
	_chan.send_message({"m": "undo_res", "ok": agree, "target_color": asker})
	if agree:
		# 被请求方自己也撤，**同样以请求方 `asker` 为"我"** —— 与上面 `_on_undo_res_received`
		#   同一个理由：两端必须执行同一个决策，各自用自己的执色会退到不同局面。
		_undo_used[asker] = undo_used(asker) + 1
		undo_to_my_turn_as(asker)
	_clear_undo_overlay()
	_undo_pending_from = -1
	_undo_freeze = false
	_update_hud()

# ====== 悔棋裁决弹窗 ======
var _undo_layer: CanvasLayer = null

## `askable` = true 时带「同意 / 拒绝」两个按钮（我是被请求方）；
## false 时只有一行状态（我是请求方，在等回执）。
func _show_undo_overlay(title: String, body: String, askable: bool) -> void:
	_clear_undo_overlay()
	_undo_layer = GameConfig.new_themed_layer()
	_undo_layer.name = "UndoOverlay"
	_undo_layer.layer = 45
	add_child(_undo_layer)
	var panel := PanelContainer.new()
	_undo_layer.add_child(panel)
	GameConfig.style_dialog_panel(panel)
	_center_popup(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", GameConfig.dialog_title_color())
	vb.add_child(t)
	var b := Label.new()
	b.text = body
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", GameConfig.dialog_text_color())
	vb.add_child(b)
	if askable:
		var hb := HBoxContainer.new()
		hb.name = "UndoDecide"
		hb.add_theme_constant_override("separation", 12)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(hb)
		var ok_btn := Button.new()
		ok_btn.name = "AgreeBtn"
		ok_btn.text = "同意悔棋"
		ok_btn.focus_mode = Control.FOCUS_NONE
		ok_btn.custom_minimum_size = Vector2(150, 46)
		GameConfig.style_dialog_button(ok_btn)
		ok_btn.pressed.connect(_on_undo_decide.bind(true))
		hb.add_child(ok_btn)
		var no_btn := Button.new()
		no_btn.name = "RefuseBtn"
		no_btn.text = "拒绝"
		no_btn.focus_mode = Control.FOCUS_NONE
		no_btn.custom_minimum_size = Vector2(120, 46)
		GameConfig.style_dialog_button(no_btn)
		no_btn.pressed.connect(_on_undo_decide.bind(false))
		hb.add_child(no_btn)

func _clear_undo_overlay() -> void:
	if _undo_layer != null and is_instance_valid(_undo_layer):
		_undo_layer.queue_free()
	_undo_layer = null

# ====== 连接生命周期 ======
func _on_peer_joined(peer_id: int) -> void:
	if _is_net_server() and _peer_white < 0:
		_peer_white = peer_id
		_net_connected = true
		_send_init()
		_update_hud()
		print("对方已加入（peer ", peer_id, "），已发送初始盘面")
		# 进入「双方准备」阶段：双方都点「准备」后才开始对局
		# （`--steamnet` 自检跳过准备，直接开始，以验证落子与初始盘面的跨端同步）
		# ★ 2026-09-30 §24 第 5 步：这里原有 `if _matchtest_active and _is_host:`（自建中继
		#   邀请自检：房主自动落子 0 → 打印 → 退出）随自检一并删除。
		#   同时删掉的还有**三个只被 ENet 用的生命周期回调** ——
		#     `_on_peer_left` / `_on_net_connected` / `_on_net_disconnected`，
		#   它们的唯一订阅点就是 `_start_network()` 里那四行 `NetworkManager.*.connect()`。
		#   ★ 删 `_on_net_disconnected()` **不会**丢掉"对端断开"的提示：Steam 掉线走的是
		#     `_on_relay_failed()`（`NetChannel.relay_failed` 契约）—— 别再把它加回来。
		if not _steamnet_active:
			_net_phase = "ready"
			_ready_set = {}
			_show_ready_overlay()

## 房主把权威初始盘面发给新加入的客户端（几何确定性，这里主要作一致性保险）
## ★ 参数只剩几何/状态本身：原先还有个 `peer_id`，但它的唯一用途是最后那行
##   `sync_init.rpc_id(peer_id, data)`（ENet 路径，第 5 步已删）⇒ 参数一并去掉，
##   否则会留下一个"看着像有目标、其实没人读"的形参（GDScript 只给 warning，静默）。
func _send_init() -> void:
	# ★ 第 5 步后通道是**唯一**路径，`if _chan != null:` 这个分支没有意义了。
	_chan.send_message({"m": "init", "data": _init_payload()})


## 初始盘面**载荷真源**（2026-10-21 从 `_send_init()` 里抽出来）。
## ★ 为什么必须抽：原先这段字典**焊死在发送函数里**，于是"房主执白时下发的加入方颜色
##   到底是黑还是白"这件事**只能靠发一次真包去观察** ⇒ 自检拿不到它，只能退而测
##   `_opposite_stone()` 这个小助手（= 测中间量，铁律 §110 那一族：助手是对的、
##   载荷里却还写死 `Stone.WHITE`，判据照样全绿）。
##   ⇒ 载荷与发送分开：本函数**只造数据、不发**（`--readygate` 判据 ⑧ 直接读它），
##     `_send_init()` 只负责送。同一份公式**只有这一处**（铁律 §111）。
func _init_payload() -> Dictionary:
	return {
		# ★ 加入方的颜色 = 房主的**相反色**（2026-10-21 座位可选）。
		#   旧版写死 `Stone.WHITE`（房主恒黑那套）。现在房主可能执白，写死就会让双方同色 ——
		#   症状是"两人都能落同一个色"，而 `_validate_action` 只校验回合，不会拦住。
		"net_color": _opposite_stone(_net_color),
		"vertices": vertices,
		"tiles": tiles,
		"tile_colors": tile_colors,
		"board": board,
		"current_player": current_player,
		"passes": passes,
		"komi": komi,
		"game_over": game_over,
		"rand_seed": _rand_seed,     # 随机盘的种子：客户端存下来，之后 reset 才能跟房主同步换盘
		# 几何必须整套下发，不能只发顶点/瓷砖：
		# 邻接表（气路）与盘型标记（星位 / 立方体三面 / 网格）也是盘面的一部分。
		# 固定盘时两边各自生成的结果完全一致，漏发也不会出错；
		# 随机盘下两边开局各有各的种子，只发一半就会让客户端拿着自己那张盘的邻接
		# 去访问房主的 board（实测报 Invalid access to property or key '197'）。
		"adjacency": adjacency,
		"is_cube": _is_cube,
		"cube_star": _cube_star_tiles,
		"cube_hex_r": _cube_hex_r,
		"is_kite": _is_kite,
		"kite_r": _kite_r_actual,
		"is_snow": _is_snow,
		"snow_r": _snow_r_actual,
		"is_hat": _is_hat,
		"hat_kind": _hat_kind_used,      # 爱因斯坦大类的种类（帽子/海龟/幽灵）——换种类 = 换盘，必须下发
		"hat_target": _hat_target,
		"hat_pool": _hat_pool_size,
	}

# ★★ 2026-09-30 §24 第 5 步删掉了 `@rpc sync_init(data)` **整个函数** ——
#   它是 ENet 时代"加入方收初始盘面"的入口，与 `_on_relay_message()` 里 `"init"`
#   那条分支**功能重复**（后者才是通道路径现在真正走的那条）。它的调用者只有一个，
#   就是上面刚删掉的 `sync_init.rpc_id(peer_id, data)`。
#   ⇒ 加入方现在收初始盘面**只**经 `_on_relay_message()` 的 `"init"` 分支；
#     那条比它多置一个 `_init_applied`（`--steamnet` 判据 ⑤ 的读点），其余步骤逐条对齐。

func _apply_snapshot(data: Dictionary) -> void:
	vertices = data["vertices"]
	tiles = data["tiles"]
	tile_colors = data["tile_colors"]
	board = data["board"]
	current_player = data["current_player"]
	passes = data["passes"]
	komi = data["komi"]
	game_over = data["game_over"]
	# 盘面是一整套：邻接表 + 盘型标记也要跟着换，否则客户端会拿着自己那张盘的拓扑
	# 去访问房主的 board（越键）。见 _send_init 里的说明。
	if data.has("adjacency"):
		adjacency = data["adjacency"]
	_is_cube = bool(data.get("is_cube", _is_cube))
	_cube_hex_r = int(data.get("cube_hex_r", _cube_hex_r))
	_is_kite = bool(data.get("is_kite", _is_kite))
	_kite_r_actual = int(data.get("kite_r", _kite_r_actual))
	_is_snow = bool(data.get("is_snow", _is_snow))
	_snow_r_actual = int(data.get("snow_r", _snow_r_actual))
	_is_hat = bool(data.get("is_hat", _is_hat))
	# 爱因斯坦大类的种类：加入方在「重开一局 / 重生成棋盘」时要用同一个种类，否则会造出另一族的盘。
	_hat_kind_used = int(data.get("hat_kind", _hat_kind_used))
	GameConfig.hat_kind = _hat_kind_used
	# 爱因斯坦盘的格数由「池 + BFS」现算：两边只要种子 + 尺寸档 + 种类一致就必然同盘。
	# 这里仍把目标格数带过来，便于客户端日志核对（盘面本体以 vertices/tiles 为准）。
	_hat_target = int(data.get("hat_target", _hat_target))
	_hat_pool_size = int(data.get("hat_pool", _hat_pool_size))
	_cube_star_tiles = _int_array(data.get("cube_star", null))
	_rand_seed = int(data.get("rand_seed", _rand_seed))
	# 房主已按视口缩放过顶点，但两边窗口尺寸未必相同 → 按本机视口重新适配一次。
	# 固定盘时这一步是幂等的（同样的盘、同样的算法），随机盘则能保证不因盘面大小差异画歪。
	_adapt_to_screen()
	# 加入方开局时是按「自己那张盘」建的引擎，收到房主盘面后必须按新邻接重建，
	# 否则 AI 拿着旧拓扑搜索（随机盘下两张盘格数/编号都不一样）。
	if ai_engine:
		ai_engine.setup(adjacency, AI_COLOR)
		ai_engine.time_budget_ms = ai_time_ms
		ai_engine.threads = GameConfig.ai_threads
		ai_engine.root_width = GameConfig.ai_root_width
	# ★★ superko 的**指纹表是按盘建的**（`_superko_zob[i]`，i 取遍 0..`tiles.size()-1`），
	#   而快照换的是**整套**盘面（vertices/tiles/adjacency/board 一起换）—— 沿用加入方
	#   自己那张盘的旧表，`_superko_hash()` 会去取**新盘**才有的 tile_id ⇒ 越界/取空
	#   （是**报错**，不是"判定不准"）。故必须按新盘重建。
	#   重建顺带把"加入那一刻的既成局面"并入历史（`_superko_init()` 末尾那行把当前局面
	#   记档）—— 否则加入方下一手若恰好重复自己刚收到的局面，会被自己误拒。
	#   ⚠️ 已知遗留（2026-10-14 留档）：快照**不携带历史** ⇒ 加入方的 superko 判定弱于
	#   房主（它不知道"开局 → 加入"之间的那些局面）。superko 局面本身罕见，影响面小；
	#   要做到底需让快照带上历史指纹（或改为由房主裁定落子合法性）。本轮只做上面两步。
	_superko_init()
	# ★ 2026-09-30 §24 第 5 步：这里原有 `if _net_init_tiles >= 0: _remember_board_size()`
	#   （给 `--nettest-*` 自检刷新"终局要看的那张盘"），随两个变量与自检一起删除。
	_update_hud()
	queue_redraw()

## 把网络下发的（无类型）数组还原成 Array[int]；null → 空数组
func _int_array(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if v == null:
		return out
	for x in v:
		out.append(int(x))
	return out

## ====== 双方准备阶段 ======
## 连接建立后进入 ready：双方都点「准备」→ 房主广播 start → 双方进入 playing。
func _on_ready(color: int) -> void:
	_ready_set[color] = true
	_update_ready_overlay()
	if _is_net_server() and _ready_set.has(Stone.BLACK) and _ready_set.has(Stone.WHITE):
		_host_start_game()

## 房主：双方已准备 → 本机开始并广播 start 给客户端
func _host_start_game() -> void:
	_begin_play()
	# ★ 第 5 步后通道是唯一路径（`else: apply_action.rpc(...)` 那行 ENet 分支已删）。
	_chan.send_message({"m": "apply", "action": {"type": "start"}})

## 进入对局（本地）：清准备覆盖层、切到 playing、刷新 HUD
func _begin_play() -> void:
	_net_phase = "playing"
	_clear_ready_overlay()
	_update_hud()
	queue_redraw()

## 玩家点「准备」：发送 ready 动作（server-authoritative）
func _on_ready_pressed() -> void:
	if _net_phase != "ready":
		return
	_net_send_action({"type": "ready", "color": _net_color})

## 显示「准备」覆盖层（双方都需点击后才开始）
func _show_ready_overlay() -> void:
	_clear_ready_overlay()
	_ready_layer = GameConfig.new_themed_layer()
	_ready_layer.name = "ReadyOverlay"
	_ready_layer.layer = 40
	add_child(_ready_layer)
	var panel := PanelContainer.new()
	_ready_layer.add_child(panel)
	GameConfig.style_dialog_panel(panel)
	_center_popup(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "双方准备后开始"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", GameConfig.dialog_title_color())
	vb.add_child(title)
	var hint := Label.new()
	hint.name = "ReadyHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", GameConfig.dialog_text_color())
	vb.add_child(hint)
	_ready_hint = hint
	var ready_btn := Button.new()
	ready_btn.name = "ReadyBtn"
	ready_btn.text = "准备"
	ready_btn.focus_mode = Control.FOCUS_NONE
	ready_btn.custom_minimum_size = Vector2(220, 48)
	# ★ "已准备"那一档要**禁用**（`_update_ready_overlay()` 会写 `disabled = true`），
	#   所以这里必须用带 `disabled` 态的样式 —— 页面档 `style_theme_button()` 已经补过这一态，
	#   而下面 `_ready_btn` 那处修好之前，那个禁用态**根本走不到**（见那里的注）。
	GameConfig.style_dialog_button(ready_btn)
	ready_btn.pressed.connect(_on_ready_pressed)
	vb.add_child(ready_btn)
	_ready_btn = ready_btn
	_update_ready_overlay()

## 根据本人是否已准备，刷新「准备」按钮文案/可用状态
## ★★ 2026-10-15 修（真 bug，与本轮"按钮接线"同一族）：这里原来写的是
##   `_ready_layer.get_node_or_null("ReadyBtn")` —— 那是**相对路径**，只查**直接子节点**，
##   而按钮在 `PanelContainer/VBoxContainer/` 底下 ⇒ **恒为 null** ⇒ 函数第一件事就 return。
##   症状：点了「准备」之后按钮文案不变、也不变灰，玩家看到的是"点了没反应"
##   （而网络状态其实是好的：`_ready_set` 已经记上了）。⇒ 改成读成员（一处写一处读）。
func _update_ready_overlay() -> void:
	if _ready_layer == null:
		return
	var btn: Button = _ready_btn
	if btn == null or not is_instance_valid(btn):
		return
	var me_ready: bool = _ready_set.get(_net_color, false)
	if me_ready:
		btn.text = "已准备 ✓（等待对方）"
		btn.disabled = true
	else:
		btn.text = "准备"
		btn.disabled = false
	# ★ 2026-10-21：这一行要把「谁执哪一色」和「两边各自准备好没有」都说清楚。
	#   座位可选之后，"你执黑还是白"不再是恒定事实（房主可能执白），而准备阶段正是
	#   玩家唯一能确认这件事的时刻；只写「等待双方都点击准备」会让执白的人一直以为
	#   自己执黑（进局后 HUD 才纠正，已经落子了）。
	if _ready_hint != null and is_instance_valid(_ready_hint):
		var mine: String = "黑" if _net_color == Stone.BLACK else "白"
		var theirs: String = "白" if _net_color == Stone.BLACK else "黑"
		_ready_hint.text = "你执%s · 对方执%s\n黑 %s ｜ 白 %s\n双方都点「准备」后才开始对局" % [
				mine, theirs,
				"已准备" if _ready_set.has(Stone.BLACK) else "未准备",
				"已准备" if _ready_set.has(Stone.WHITE) else "未准备"]

func _clear_ready_overlay() -> void:
	if _ready_layer != null and is_instance_valid(_ready_layer):
		_ready_layer.queue_free()
	_ready_layer = null
	# ★ 清空点也是写点（铁律 8）：成员跟着一起清 —— 留着指向已 `queue_free()` 的按钮，
	#   下一轮 `_update_ready_overlay()` 就会写到一个死节点上（`is_instance_valid` 兜住，
	#   但那是兜底、不是契约）。
	_ready_btn = null
	_ready_hint = null

## 房主重置按钮 / R 键：仅房主可发起，广播给双方
func _on_reset_pressed() -> void:
	if game_mode == ONLINE:
		if not _is_net_server():
			print("只有房主可以重置对局")
			return
		# 随机盘联机不换盘（见 _regen_on_restart）：这里只广播「清空重下」
		_net_send_action({"type": "reset", "color": current_player})
		return
	restart_game()

## 联机自检测试（--onlinetest）：单进程模拟双方各走几手，验证 _apply_action 权威路径
func _self_test_online() -> void:
	_is_host = true
	_net_color = Stone.BLACK
	_net_connected = true
	_peer_white = 1
	print("[联机自检] 自环启动，房主执黑，模拟双方动作")
	_apply_action({"type": "place", "tile": 0, "color": Stone.BLACK})
	print("[联机自检] 黑落子0 → 轮到 ", ("黑" if current_player == Stone.BLACK else "白"))
	_apply_action({"type": "pass", "color": Stone.WHITE})
	print("[联机自检] 白停一手 → passes=", passes)
	_apply_action({"type": "reset", "color": Stone.BLACK})
	print("[联机自检] reset → current_player=", ("黑" if current_player == Stone.BLACK else "白"), " passes=", passes)
	print("[联机自检] 通过 ✓（_apply_action 权威路径无异常）")
	get_tree().quit()


## 合成一次"点在格子中心"的左键按下，喂给**真实入口** `_on_area_input()`。
## ★ 为什么不直接调 `_net_send_action()`：那等于跳过被测的那道闸 —— 判据就永远绿。
##   这里复现的是玩家手指真正走的那条路：`_on_area_input() → _place_block_reason() →
##   _tile_at_point() → _net_send_action()`。任何一个括号里的环节被删掉，判据都会红。
func _rg_click(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	_on_area_input(get_viewport(), ev, 0)


## 自检（--readygate，2026-10-21）：联机「**双方都准备好了再进入对局**」的端到端闸。
## 用户口令原文：「然后一定要双方都准备好了再进入对局」。
##
## ★ 为什么不能只断言 `_can_local_play()`：那是**中间量**。一个"恒返回 false"的实现能让
##   「未准备不许落子」全绿，同时「都准备好了就该能落子」没人测（本工程 §110 那一族：
##   被测物与它的退化出口是同一个对象 ⇒ 恒绿）。本自检走**真实点击入口**，看**棋盘变没变**，
##   并且正 / 负两档成对：
##     · 正对照（playing 档）：必须**真的落下** —— 证明这条路本来就通；
##     · 负对照（ready 档）  ：必须**一点没动** —— 这才是"闸真的挡住了"的证据。
##   只有负对照没有正对照 ⇒ "这条路本来就是死的"也全绿（等于没测）。
##
## ★ 另一族（⑤⑥）测的是"**单方准备不许开局**"：`_ready_set` 只记了一个色时，
##   房主侧一次都不许进 playing。⑦⑧ 测座位：映射三档 + 房主执白时下发/校验的口径。
func _ready_gate_self_test() -> void:
	print("[readygate] ===== 联机准备闸（双方都准备好才开局）=====")
	var checks: Array = []

	# ---- 摆状态：房主 + 已连接 + 一条真通道 ----
	#   `NetChannel` 基类的 `send_message()` 是空实现（契约原文：未就绪时静默丢弃），
	#   足够让 `_net_send_action()` 走到"房主本地即权威 ⇒ `_apply_action()`"那一步 ——
	#   于是"有没有真的落子"变成一个**可观测的盘面事实**，而不是靠打印猜。
	var sv := {
		"game_mode": game_mode, "is_host": _is_host, "net_connected": _net_connected,
		"net_color": _net_color, "peer_white": _peer_white, "chan": _chan,
		"net_phase": _net_phase, "ready_set": _ready_set.duplicate(),
		"current_player": current_player, "quiet": _quiet_place, "game_over": game_over,
		"net_awaiting": _net_awaiting, "undo_freeze": _undo_freeze,
		"board": board.duplicate(), "ko": ko_point, "last_move": _last_move,
		"passes": passes, "bp": black_prisoners, "wp": white_prisoners,
		"superko": _superko_hist.duplicate(), "seat": GameConfig.seat_choice,
		"place_anims": _place_anims.duplicate(), "capture_anims": _capture_anims.duplicate(),
	}
	game_mode = ONLINE
	_is_host = true
	_net_connected = true
	_net_color = Stone.BLACK
	_peer_white = 2
	# ★ 这条桩通道要留个句柄：`Node` **不是** RefCounted ⇒ `.new()` 之后丢了引用就是泄漏
	#   （实测：退出时报 `1 resources still in use at exit`）。复原时显式 `free()`。
	var rg_chan: NetChannel = NetChannel.new()
	_chan = rg_chan
	_net_phase = "playing"
	_ready_set = {}
	_quiet_place = true     # 探测性落子：不入悔棋栈 / 不写棋谱 / 不 dirty 盘面记录
	game_over = false
	_net_awaiting = false
	_undo_freeze = false
	current_player = Stone.BLACK
	_update_hud()

	# ---- 挑一个"干净可点"的格子：空、不在劫点、中心没被 HUD 压住 ----
	#   ★ 有效分母为 0 必须报红（本工程口径）：一个都挑不到说明"下面两条判据压根没跑"，
	#     绝不能因为"没得测"就绿过去。
	var cand: Array[int] = []
	for t in range(board.size()):
		if board[t] != Stone.EMPTY or t == ko_point or _tile_center_covered(t):
			continue
		# ★ 再钉一层：格子中心要能**回投**到自己（`_tile_at_point()` 是点击路径真源）。
		#   不回投就点下去落到别的格上，② "落下了"会绿、③ "没动"却是在看另一格 ——
		#   两条判据同时看错格子，是最难读的一种假绿。
		if _tile_at_point(tile_centers[t]) != t:
			continue
		cand.append(t)
	var tile: int = cand[0] if cand.size() > 0 else -1
	var have_tile: bool = tile >= 0
	checks.append(["① 找到可点空格｜分母必须 > 0，否则下面两条判据等于没跑",
			have_tile, "候选 %d 个 / 盘 %d 格" % [cand.size(), board.size()]])

	# ---- ② 正对照：playing 档点一下必须真落下 ----
	#   ★ 这一条是负对照的**前提**：没有它，"点击这条路根本不通"与"闸挡住了"长得一模一样。
	_net_phase = "playing"
	current_player = Stone.BLACK
	if have_tile:
		# ⚠️ 只在 have_tile 时写盘：`board` 是 Dictionary，`board[-1] = …` 会**真的加一个
		#   键 -1**（不报错）⇒ 盘面多出一个幽灵格，后面的 `board.size()` 全跟着偏。
		board[tile] = Stone.EMPTY
		_rg_click(tile_centers[tile])
	var placed: bool = have_tile and board[tile] == Stone.BLACK
	checks.append(["② 正对照｜playing 档点棋盘必须真的落下，证明这条路本来就通",
			placed, "第 %d 格落子后=%d（期望 %d=黑）" % [tile, board[tile], Stone.BLACK]])

	# ---- ③ 负对照：ready 档 + 只有我一方准备 → 点**同一个位置**必须一点没动 ----
	_net_phase = "ready"
	_ready_set = {Stone.BLACK: true}       # 我已准备，对方没准备
	current_player = Stone.BLACK
	if have_tile:
		board[tile] = Stone.EMPTY          # 把 ② 那手撤掉，回到"这一格是空的"
		_rg_click(tile_centers[tile])
	checks.append(["③ 准备阶段点棋盘必须无效｜只有一方准备时不许落下任何一子",
			have_tile and board[tile] == Stone.EMPTY and current_player == Stone.BLACK,
			"第 %d 格=%d（期望 %d=空）｜current_player=%d（期望 %d）" % [
					tile, board[tile], Stone.EMPTY, current_player, Stone.BLACK]])

	# ---- ④ 另外两个动作入口也必须在 ready 档被挡住 ----
	#   ★ 只测落子是不够的：`_can_local_play()` 有**四个**读者（落子 / 停一手 / 认输 / 悔棋），
	#     铁律 §123「一类行为多条出口 ⇒ 先枚举出口再抽唯一出口挂总闸」——
	#     这里把"出口没挂上闸"变成一条可读的红。
	#   ★★ 必须先**把现场重置干净**再量：③ 一旦被拆闸（阴性对照实测就是这样），
	#     它那一手会顺手把 `current_player` 翻成白 ⇒ ④ 的停手会被"不是你的回合"那条**挡在另一道闸上**，
	#     红的理由看起来对、其实量错了人。判据要**只量它自己那件事**。
	_net_phase = "ready"
	_ready_set = {Stone.BLACK: true}
	current_player = Stone.BLACK
	if have_tile:
		board[tile] = Stone.EMPTY
	var passes_before: int = passes
	_on_pass_pressed()
	var passes_after: int = passes
	#   · 认输：**故意切到加入方**（`_is_host=false`）再点 —— 否则一旦闸被拆掉，
	#     房主侧会真的执行 `_resign_game()`，而它**会写 `user://records`（联机战绩）**，
	#     自检就污染了用户数据（铁律 §8：自检不写 user://）。加入方侧只置 `_net_awaiting`，
	#     是个干净的可观测量。
	_is_host = false
	_net_awaiting = false
	_on_resign_pressed()
	var awaiting_after: bool = _net_awaiting
	var over_after: bool = game_over
	_is_host = true
	checks.append(["④ 停一手 / 认输在准备阶段同样无效｜四个读 `_can_local_play()` 的出口都要挂闸",
			passes_after == passes_before and not awaiting_after and not over_after,
			"停手被挡=%s（passes %d→%d）｜认输被挡=%s（_net_awaiting=%s game_over=%s）" % [
					str(passes_after == passes_before), passes_before, passes_after,
					str(not awaiting_after and not over_after),
					str(awaiting_after), str(over_after)]])

	# ---- ⑤ 单方准备不许开局 ----
	_net_phase = "ready"
	_ready_set = {}
	_on_ready(Stone.BLACK)
	var one_side: String = _net_phase
	# ---- ⑥ 双方都准备 → 房主侧开局的唯一写点 `_host_start_game()` 被调到 ----
	_on_ready(Stone.WHITE)
	var both_side: String = _net_phase
	checks.append(["⑤ 只有一方准备时不开局｜`_ready_set` 只有一个色，phase 必须仍是 ready",
			one_side == "ready", "一方准备后 phase=%s（期望 ready）" % one_side])
	checks.append(["⑥ 双方都准备后才开局｜房主侧 phase 转为 playing",
			both_side == "playing", "两方准备后 phase=%s（期望 playing）" % both_side])

	# ---- ⑦ 座位 → 房主执色映射（三档） ----
	var seat_ok := true
	var seat_bad: Array[String] = []
	GameConfig.seat_choice = GameConfig.SEAT_BLACK
	if _host_color_from_seat() != Stone.BLACK:
		seat_ok = false
		seat_bad.append("我执黑→%d" % _host_color_from_seat())
	GameConfig.seat_choice = GameConfig.SEAT_WHITE
	if _host_color_from_seat() != Stone.WHITE:
		seat_ok = false
		seat_bad.append("我执白→%d（期望白）" % _host_color_from_seat())
	#   ★ 随机档的判据必须是"**两色都出现过**"，不能写成"等于某个色" ——
	#     "恒返回黑"能让"等于黑"绿过去，而那恰好就是随机档失效的样子。
	GameConfig.seat_choice = GameConfig.SEAT_RANDOM
	var saw_b := 0
	var saw_w := 0
	for i in range(64):
		if _host_color_from_seat() == Stone.BLACK:
			saw_b += 1
		else:
			saw_w += 1
	if saw_b == 0 or saw_w == 0:
		seat_ok = false
		seat_bad.append("随机 64 次只出现一色：黑%d 白%d" % [saw_b, saw_w])
	checks.append(["⑦ 座位三档映射都对｜随机档必须两色都出现过，不是等于某个色",
			seat_ok,
			"；".join(seat_bad) if not seat_bad.is_empty()
					else "黑→黑 白→白 随机：黑%d / 白%d" % [saw_b, saw_w]])

	# ---- ⑧ 房主执白时：加入方拿到黑，且 `_peer_of_color()` 不许把 1 号当黑 ----
	#   ★ 这是座位可选**最容易静默坏**的一处：旧实现写死"房主 = 1 号 = 黑"，
	#     房主执白时加入方（黑）的每一个动作都会被 `_validate_action()` 判成"发错人"拒收 ——
	#     症状是"黑方一步都落不下去"，而网络正常、日志一片安静（静默失效里最难查的一家）。
	#   ★ 读的是 `_init_payload()`（**载荷真源**），不是 `_opposite_stone()` 这个小助手：
	#     助手测对了、而载荷里仍然写死 `Stone.WHITE` 的坏法，只有读载荷才逮得到。
	_net_color = Stone.WHITE          # 房主执白
	_peer_white = 2                   # 加入方 peer id
	var sent_color: int = int(_init_payload().get("net_color", -1))
	checks.append(["⑧ 房主执白时下发的加入方颜色是黑｜读载荷真源 _init_payload",
			sent_color == Stone.BLACK,
			"下发 net_color=%d（期望 %d=黑）" % [sent_color, Stone.BLACK]])
	# ⑨ 与 ⑧ **必须拆成两条**（铁律 §101「多面须拆条」）：它们坏起来的样子完全不同 ——
	#   ⑧ 坏 ⇒ 双方同色；⑨ 坏 ⇒ 颜色对了、但黑方每个动作都被拒收。合成一条时，
	#   一把刀只能告诉你"这条红了"，说不出坏的是哪一面。
	var pw_white: int = _peer_of_color(Stone.WHITE)
	var pw_black: int = _peer_of_color(Stone.BLACK)
	checks.append(["⑨ _peer_of_color 不假设房主恒黑｜房主执白时黑方是对方而不是 1 号",
			pw_white == 1 and pw_black == 2,
			"白→peer%d（期望 1）｜黑→peer%d（期望 2）" % [pw_white, pw_black]])

	# ---- 复原现场（本自检跑在自己这套真状态上，不能把后面的事弄脏）----
	game_mode = int(sv["game_mode"])
	_is_host = bool(sv["is_host"])
	_net_connected = bool(sv["net_connected"])
	_net_color = int(sv["net_color"])
	_peer_white = int(sv["peer_white"])
	_chan = sv["chan"]
	if rg_chan != null and is_instance_valid(rg_chan):
		rg_chan.free()
	_net_phase = str(sv["net_phase"])
	_ready_set = sv["ready_set"]
	current_player = int(sv["current_player"])
	_quiet_place = bool(sv["quiet"])
	game_over = bool(sv["game_over"])
	_net_awaiting = bool(sv["net_awaiting"])
	_undo_freeze = bool(sv["undo_freeze"])
	board = sv["board"]
	ko_point = int(sv["ko"])
	_last_move = int(sv["last_move"])
	passes = int(sv["passes"])
	black_prisoners = int(sv["bp"])
	white_prisoners = int(sv["wp"])
	_superko_hist = sv["superko"]
	GameConfig.seat_choice = int(sv["seat"])
	_place_anims = sv["place_anims"]
	_capture_anims = sv["capture_anims"]
	_update_hud()
	queue_redraw()

	var failed: Array = []
	for c in checks:
		var okc: bool = (c[1] is bool) and (c[1] as bool)
		if not okc:
			failed.append(str(c[0]))
		print("[readygate] %s %s（%s）" % [c[0], "✓" if okc else "✗", c[2]])
	print("[readygate] 判据 %d 条，失败 %d 条%s" % [checks.size(), failed.size(),
			"" if failed.is_empty() else "：" + ", ".join(failed)])
	print("[readygate] 结论：", "通过 ✓" if failed.is_empty() and checks.size() > 0 else "失败 ✗")
	get_tree().quit()


## 自检（--emotetest，2026-10-21）：快捷表情 + 联机身份条。
##
## ★ 不需要 Steam：全部判据走**本地可复现**的链路 —— 表情消息入口 / 气泡状态 / 真实绘制计数 /
##   身份条可见性与几何。头像"真的从 Steam 拿到图"那一条在 `--steamtest`（需要真 Steam）。
##
## ★ 为什么每条都选"可观测结果"而不是"中间量"（本工程 §110 / §127）：
##   · ③ 测 `send_emote()` 之后**本地气泡状态变了**，不是"按钮连了信号"；
##   · ⑨ 测 `draw` 信号**真的被调用了几次**，不是"绘制函数存在"（函数在但没人画 = 全绿是假象）；
##   · ⑩ 两种 `game_mode` 各量一次，正 / 负成对 —— 只测"联机时可见"的话，
##     一个"恒可见"的实现也能全绿。
func _emote_self_test() -> void:
	print("[emotetest] ===== 快捷表情 + 联机身份条 =====")
	var checks: Array = []
	var sv := {
		"game_mode": game_mode, "net_color": _net_color, "chan": _chan,
		"net_phase": _net_phase, "connected": _net_connected,
	}
	# 自检自己把 UI 建好：`_build_game_hud()` 里有 `await`，本自检可能跑在它完成之前。
	if _drawer_layer == null or not is_instance_valid(_drawer_layer):
		_build_drawers()
	game_mode = ONLINE
	_net_color = Stone.BLACK
	_net_connected = true
	_net_phase = "playing"
	_chan = null                    # 不连真通道：发送走 `is_live()` = false 的静默丢弃
	_refresh_net_extras()

	# ---- ① 表情表完整 ----
	var names_ok: bool = Emotes.count() == 8
	var seen: Dictionary = {}
	var bad_name := ""
	for i in range(Emotes.count()):
		var nm := Emotes.name_of(i)
		if nm == "":
			names_ok = false
			bad_name = "第 %d 个名字为空" % i
		elif seen.has(nm):
			names_ok = false
			bad_name = "重名：" + nm
		seen[nm] = true
	checks.append(["① 表情表完整｜数量固定且名字非空互不重名",
			names_ok, bad_name if bad_name != "" else "%d 个：%s" % [
					Emotes.count(), ", ".join(Emotes.NAMES)]])

	# ---- ② 越界表情号被唯一守卫挡掉 ----
	var guard_ok: bool = (not Emotes.is_valid(-1)) \
			and (not Emotes.is_valid(Emotes.count())) \
			and Emotes.name_of(-1) == "" and Emotes.name_of(99) == ""
	checks.append(["② 越界表情号一律非法｜-1 与 count 本身都不是合法值",
			guard_ok, "is_valid(-1)=%s is_valid(%d)=%s" % [
					str(Emotes.is_valid(-1)), Emotes.count(), str(Emotes.is_valid(Emotes.count()))]])

	# ---- ③ 发送走真实入口 → 本地气泡立刻出现（call_local 语义）----
	_emote_last_sent_ms = 0
	_emote_bubble_idx[0] = -1
	_emote_bubble_left[0] = 0.0
	var sent1: bool = send_emote(2)
	checks.append(["③ 发表情后自己这边立刻看见｜本地先放再发，不等对端回声",
			sent1 and _emote_bubble_idx[0] == 2 and _emote_bubble_left[0] > 0.0,
			"send=%s idx=%d 寿命=%.2f" % [str(sent1), _emote_bubble_idx[0], _emote_bubble_left[0]]])

	# ---- ④ 收到对端消息 → 对端气泡（走真实消息分发）----
	_on_relay_message({"m": "emote", "e": 3})
	checks.append(["④ 收到对端表情消息后对端气泡出现｜走 _on_relay_message 分发",
			_emote_bubble_idx[1] == 3 and _emote_bubble_left[1] > 0.0,
			"对端 idx=%d（期望 3）寿命=%.2f" % [_emote_bubble_idx[1], _emote_bubble_left[1]]])

	# ---- ⑤ 脏表情消息不改任何状态（唯一守卫在 _play_emote）----
	#   ★ 先把状态清成"空"，再喂 99：不清的话 ④ 留下的 idx=3 会让"没变化"与"没被改"
	#     长得一模一样（典型的假绿）。
	_emote_bubble_idx[1] = -1
	_emote_bubble_left[1] = 0.0
	_on_relay_message({"m": "emote", "e": 99})
	_on_relay_message({"m": "emote"})              # 连键都不带的畸形包
	checks.append(["⑤ 越界与畸形表情消息不改任何状态｜入口不另写校验，唯一守卫在 _play_emote",
			_emote_bubble_idx[1] == -1 and _emote_bubble_left[1] == 0.0,
			"对端 idx=%d（期望 -1）寿命=%.2f（期望 0）" % [_emote_bubble_idx[1], _emote_bubble_left[1]]])

	# ---- ⑥ 发送节流 ----
	_emote_last_sent_ms = 0
	var t1: bool = send_emote(1)
	var t2: bool = send_emote(1)
	checks.append(["⑥ 表情发送有节流｜%d 毫秒内连发只认第一条" % EMOTE_SEND_GAP_MS,
			t1 and not t2, "第一次=%s 紧接着第二次=%s" % [str(t1), str(t2)]])

	# ---- ⑦ 表情到期后**不再画**（状态清 + 绘制计数停涨，双证据）----
	#   ★ 2026-10-22 改写：原来查的是 `_emote_self_bubble.visible`（那个节点已随气泡整套删除）。
	#     现在表情画在身份槽里，只有"状态"没有"节点可见性"这种东西可查 ⇒ 改量两样：
	#     ① `_emote_bubble_idx` 清回 -1、探针 `_last_emote_alpha` 归 0；
	#     ② **绘制计数停涨** —— 只查 flag 会被"flag 清了但还在画"骗过（§110 的形态）。
	_refresh_net_extras()          # 保证身份槽在树里且可见，否则根本不会重绘
	_play_emote(0, 5)
	_emote_bubble_left[0] = 0.1
	await get_tree().process_frame
	var paint_before: int = int(_draw_ticks.get("bubble", 0))
	_tick_emote_bubbles(0.2)       # 寿命走完 ⇒ idx 清回 -1
	_redraw_identity()
	await get_tree().process_frame
	var paint_after: int = int(_draw_ticks.get("bubble", 0))
	var hidden_ok: bool = _emote_bubble_idx[0] == -1 \
			and _last_emote_alpha[0] == 0.0 \
			and paint_after == paint_before
	checks.append(["⑦ 表情到期后头像上不再画｜状态清回 -1 且绘制计数停涨",
			hidden_ok, "idx=%d 画出去的 alpha=%.2f 绘制 %d→%d" % [
					_emote_bubble_idx[0], _last_emote_alpha[0], paint_before, paint_after]])

	# ---- ⑧ 淡出按剩余寿命线性派生（不是"突然消失"，也不是"恒为满值"）----
	#   ★ 断的是**函数关系**：`alpha == clamp(剩余 / 淡出段)`，取两组探针当场比。
	#     不调 `emote_slot_alpha()` 算期望值（那是拿被测函数给自己当答案，§70）。
	#   ★ 为什么不像第一版那样断言"alpha 精确等于 0.333"：自检里有 `await`，帧间
	#     `_process → _tick_emote_bubbles()` 会再扣掉一两帧，精确值必然偏 ——
	#     那种情况下唯一能做的"修法"就是放宽容差，而放宽容差就是掩盖。
	#   ★ 另两条一起断：剩余必须落在**淡出段内**（< FADE）且 alpha < 0.9 ——
	#     把"二值开关"（alive ? 1.0 : 0.0）改回来会同时违反这两条。
	_play_emote(0, 1)
	_emote_bubble_left[0] = 0.2
	_tick_emote_bubbles(0.05)          # ⇒ 剩 0.15（落进淡出段）
	_redraw_identity()
	await get_tree().process_frame
	var got_a: float = _last_emote_alpha[0]
	var got_left: float = _last_emote_left[0]
	var want_a: float = clampf(got_left / EMOTE_BUBBLE_FADE, 0.0, 1.0)
	var fade_ok: bool = absf(got_a - want_a) < 0.001 \
			and got_left > 0.0 and got_left < EMOTE_BUBBLE_FADE \
			and got_a < 0.9
	checks.append(["⑧ 表情淡出跟着剩余寿命走｜alpha 与剩余寿命的线性关系，不是二值开关",
			fade_ok, "alpha=%.3f 由剩余 %.3f 推出（期望 %.3f）" % [got_a, got_left, want_a]])

	# ---- ⑨ 8 个表情都真的被画出来（真实 draw 信号计数）----
	#   ★ 这是本自检里唯一一条"看得见像素之外"的判据：`Emotes.draw_emote()` 是纯绘制代码，
	#     headless 下没法回读像素，但 `draw` 信号**确实会触发**（CanvasItem 的 draw
	#     与渲染后端无关）⇒ 靠计数证明"8 个都被送进绘制了"。
	#   ★ 一条反例：如果只断言"Emotes.count()==8 且 draw_emote 存在"，那么把表情格
	#     循环改成 `for i in range(3)` 也全绿 —— 计数断不住这种东西。
	var tick0: int = int(_draw_ticks.get("emote_cell", 0))
	var probes: Array[Control] = []
	for i in range(Emotes.count()):
		var probe := Control.new()
		probe.name = "EmoteProbe%d" % i
		probe.size = Vector2(48, 48)
		probe.custom_minimum_size = Vector2(48, 48)
		probe.draw.connect(_draw_emote_cell.bind(probe, i))
		_emote_grid.add_child(probe)
		probes.append(probe)
	await get_tree().process_frame
	await get_tree().process_frame
	var drew: int = int(_draw_ticks.get("emote_cell", 0)) - tick0
	checks.append(["⑨ 8 个表情都真的进了绘制｜靠 draw 信号的真实调用计数，不靠函数存在",
			drew >= Emotes.count(), "两帧内 emote_cell 绘制 %d 次（期望 ≥ %d）" % [drew, Emotes.count()]])
	for probe in probes:
		probe.queue_free()

	# ---- ⑩ 左抽屉（身份 + 表情）只在联机态可见（正负成对）----
	game_mode = ONLINE
	_refresh_net_extras()
	# ★ 面板问 `is_visible_in_tree()` 而不是 `visible`：它挂在 `_drawer_layer` 下面，
	#   **父层藏起来时子节点的 `visible` 仍然是 true**（Godot 语义）。第一版写成 `.visible`
	#   ⇒ 人机档那条恒假、"只在联机态出现"这条判据一半根本没在测。
	var vis_online: bool = _drawer_layer.visible and _drawer_left_panel.is_visible_in_tree()
	game_mode = VS_AI
	_refresh_net_extras()
	var vis_offline: bool = (not _drawer_layer.visible) \
			and (not _drawer_left_panel.is_visible_in_tree())
	game_mode = ONLINE
	_refresh_net_extras()
	checks.append(["⑩ 左抽屉只在联机态出现｜身份槽与表情格两档各量一次，正负成对",
			vis_online and vis_offline, "联机时可见=%s 人机时隐藏=%s" % [
					str(vis_online), str(vis_offline)]])

	# ---- ⑪ 两条身份槽完整落在左抽屉里（不是"落在视口内"）----
	#   ★ 判据口径从"在视口内"收紧成"在左抽屉内容区内"：抽屉出现之后，只要它们跑到面板外面
	#     （比如宽度撑破面板），"在视口内"照样绿 —— 那会当场压到棋盘上，而这正是本轮要防的。
	_refit_drawers()
	await get_tree().process_frame
	var slot_ok := true
	var slot_msg := ""
	var cr0 := drawer_content_rect(0)
	for c in [_net_id_self, _net_id_peer]:
		if c == null or not is_instance_valid(c):
			slot_ok = false
			slot_msg = "身份槽未建"
			continue
		var gr: Rect2 = c.get_global_rect()
		# 容差 1.5px：VBoxContainer 的行间距与 `size` 的一致性会有亚像素差。
		if not cr0.grow(1.5).encloses(gr):
			slot_ok = false
			slot_msg += " %s 越界 %s" % [c.name, str(gr)]
	checks.append(["⑪ 两条身份槽完整落在左抽屉内容区内｜内容区 %s%s" % [
			str(cr0), "" if slot_msg == "" else "，" + slot_msg],
			slot_ok, "自己 %s ｜ 对端 %s" % [
					str(_net_id_self.get_global_rect()), str(_net_id_peer.get_global_rect())]])

	# ---- ⑫ 拿不到 SteamID 时头像为空、名字退回占位 ----
	_chan = null
	var av_null: bool = _avatar_circle_for(0) == null
	var nm0 := _display_name_for(0)
	var nm1 := _display_name_for(1)
	checks.append(["⑫ 拿不到 SteamID 时头像为空并退回占位名｜不许假设头像非空",
			av_null and nm0 == "你" and nm1 == "对手",
			"头像=%s 名字：自己=%s 对端=%s" % ["null" if av_null else "非空", nm0, nm1]])

	# ---- ⑬ 两条身份槽都真的画过 ----
	var id_ticks: int = int(_draw_ticks.get("identity", 0))
	checks.append(["⑬ 两条身份槽都真的画过｜identity 绘制计数 ≥ 2",
			id_ticks >= 2, "identity 绘制 %d 次（期望 ≥ 2）" % id_ticks])

	# ---- ⑭ 表情只画在头像圆里，那块区域到不了棋盘（用户口令：表情包不要遮挡棋盘）----
	#   ★ 三个量一起断，缺一个都能骗过判据：
	#     ① 两个槽的头像圆都完整落在左抽屉内容区内（表情就画在这个圆里）；
	#     ② 头像圆与**棋盘盒**不相交（棋盘盒含盘的外扩，比顶点盒严 13px）；
	#     ③ 探针证明表情**真的在画**（alpha > 0）—— 否则"一个表情都没有"也能让 ①② 全绿，
	#        等于这条判据什么都没测（§106 有效分母为 0 须报红）。
	_play_emote(0, 6)
	_play_emote(1, 1)
	_redraw_identity()
	await get_tree().process_frame
	var bb_all: Rect2 = _board_bbox()
	if board_panel_enabled:
		bb_all = bb_all.grow(board_panel_pad)
	var av_ok := true
	var av_msg := ""
	for slot in [0, 1]:
		var ar: Rect2 = avatar_screen_rect(slot)
		if not ar.has_area():
			av_ok = false
			av_msg += " 槽%d 头像圆为空" % slot
			continue
		if not cr0.grow(1.5).encloses(ar):
			av_ok = false
			av_msg += " 槽%d 头像圆越出抽屉 %s" % [slot, str(ar)]
		if ar.intersects(bb_all):
			av_ok = false
			av_msg += " 槽%d 头像圆压住棋盘 %s" % [slot, str(ar)]
	var painted: bool = _last_emote_alpha[0] > 0.0 and _last_emote_alpha[1] > 0.0
	checks.append(["⑭ 表情只画在头像圆里且不碰棋盘｜两槽各量一次且必须真有表情在画%s" % av_msg,
			av_ok and painted, "头像圆 自己 %s ｜ 对端 %s ｜ 棋盘 %s ｜ alpha=(%.2f,%.2f)" % [
					str(avatar_screen_rect(0)), str(avatar_screen_rect(1)), str(bb_all),
					_last_emote_alpha[0], _last_emote_alpha[1]]])

	# ---- ⑮ 棋盘恒在窗口正中间（联机 / 人机两档各量一次，正负成对）----
	#   ★ 用户口令：「本地和人机模式棋盘也要放在正中间」。
	#   口径：**棋盘盒（含盘的外扩）的中心 x 必须等于视口中线**，两档都要成立。
	#   ★ 为什么必须两档都量：只量联机档会漏掉病根本身 —— 左抽屉只在联机态存在，
	#     于是单机态带宽是 `(0, 250)`、盘整体左移 **125px**。那是"看着不对但全绿"的典型
	#     （棋盘几何完全合法，只是不在中间）。
	#   ★ 判据量 `_board_bbox()` 而不是 `board_area()`：前者是**盘的顶点**，后者是"能用哪块矩形"。
	#     两者中心差一个 pad 的事，量面积法关系容易自己骗自己（§70 判据不许重实现被测逻辑）。
	var mid_ok := true
	var mid_msg := ""
	for mode in [ONLINE, VS_AI]:
		game_mode = mode
		_refresh_net_extras()
		_refit_hud()
		var bb2: Rect2 = _board_bbox()
		if board_panel_enabled:
			bb2 = bb2.grow(board_panel_pad)
		var off: float = bb2.get_center().x - get_viewport_rect().size.x * 0.5
		if absf(off) > 1.5:
			mid_ok = false
			mid_msg += " mode=%d 偏 %.1fpx" % [mode, off]
	checks.append(["⑮ 棋盘恒在窗口正中间｜联机与人机两档各量一次，偏移 ≤1.5px%s" % mid_msg,
			mid_ok, "视口中线 %.1f ｜ 联机/人机下盘的盒中心都须落在它上面" % (
					get_viewport_rect().size.x * 0.5)])

	# ---- 复原现场 ----
	game_mode = int(sv["game_mode"])
	_net_color = int(sv["net_color"])
	_chan = sv["chan"]
	_net_phase = str(sv["net_phase"])
	_net_connected = bool(sv["connected"])
	_emote_bubble_left = [0.0, 0.0]
	_emote_bubble_idx = [-1, -1]
	_last_emote_alpha = [0.0, 0.0]
	_last_emote_left = [0.0, 0.0]
	_refresh_net_extras()

	var failed: Array = []
	for c in checks:
		var okc: bool = (c[1] is bool) and (c[1] as bool)
		if not okc:
			failed.append(str(c[0]))
		print("[emotetest] %s %s（%s）" % [c[0], "✓" if okc else "✗", c[2]])
	print("[emotetest] 判据 %d 条，失败 %d 条%s" % [checks.size(), failed.size(),
			"" if failed.is_empty() else "：" + ", ".join(failed)])
	print("[emotetest] 结论：", "通过 ✓" if failed.is_empty() and checks.size() > 0 else "失败 ✗")
	get_tree().quit()


## 自检（--drawertest，2026-10-21）：侧抽屉几何 + 「严防重叠」。
##
## ★ 这一档存在的理由：用户口令是「**严防**重叠」—— 一个"防"字就说明它不能靠目测，
##   必须有一条能在**窄窗口 / 换盘型 / 换主题**下都成立的判据。核心那条
##   （`judge_drawer_layout()`）量的是真实矩形，且配了一把阴性对照刀（④）：
##   把让位系数压 0 ⇒ 面板照旧展开、棋盘不再让位 ⇒ 判据必须当场报红。
##   没有 ④ 的话，"不重叠"只能在一片已经摆对的局面里跑，永远绿（§110）。
func _drawer_self_test() -> void:
	print("[drawertest] ===== 侧抽屉：左右空白 / 折叠收回侧边 / 严防重叠 =====")
	var checks: Array = []
	var sv := {
		"game_mode": game_mode, "left": _drawer_left_open, "right": _drawer_right_open,
		"net_color": _net_color, "connected": _net_connected, "phase": _net_phase,
		"cramped_margin": GameConfig.hud_landscape_margin,
	}
	if _drawer_layer == null or not is_instance_valid(_drawer_layer):
		_build_drawers()
	# 联机态 + 两侧展开 = 最挤的一档（两条 200px 面板同时在场）。
	game_mode = ONLINE
	_net_color = Stone.BLACK
	_net_connected = true
	_net_phase = "playing"
	_drawer_left_open = true
	_drawer_right_open = true
	_drawer_band_ratio = 1.0
	_refresh_net_extras()
	_refit_hud()
	_adapt_to_screen()
	await get_tree().process_frame
	await get_tree().process_frame

	# ---- ① 两侧都展开时判据必须绿（正判据）----
	var jr: Array = judge_drawer_layout()
	checks.append(["① 两侧展开时面板/把手都不碰棋盘｜量真实矩形，不量算术",
			bool(jr[0]), String(jr[1])])

	# ---- ② 可用区与带宽自洽：棋盘盒必须落在"视口 − 两侧带宽 − 边距"里 ----
	#   ★ 这一条与 ① 射程不同：① 管"没压上"，② 管"让位量算对了"（没用得太多、也没用得太少）。
	var bands := drawer_bands()
	var m_eff: float = GameConfig.board_margin() \
			+ (board_panel_pad if board_panel_enabled else 0.0)
	var vs := get_viewport_rect().size
	var want_area := Rect2(bands.x + m_eff, m_eff,
			vs.x - bands.x - bands.y - 2.0 * m_eff, vs.y - 2.0 * m_eff)
	var area := board_area()
	var area_ok: bool = absf(area.size.x - want_area.size.x) <= 0.5 \
			and absf(area.position.x - want_area.position.x) <= 0.5 \
			and bands.x > DRAWER_W_LEFT and bands.y > DRAWER_W_RIGHT
	checks.append(["② 可用区 = 视口 − 两侧带宽 − 边距｜带宽 %s" % str(bands),
			area_ok, "可用区 %s 期望 %s" % [str(area), str(want_area)]])

	# ---- ③ 折叠前后**棋盘一动不动**（用户口令：棋盘固定在中心不要动）----
	#   ★ 这一条**曾经是反的**：上一版断言"折叠后棋盘拿回空间"（`w_closed > w_open + 200`）。
	#     那个口径下每点一次把手棋盘就要缩放重排一遍 —— 正是用户报的"一点抽屉整盘棋跳一下"。
	#     现在 `_drawer_band()` 与开合脱钩 ⇒ 折叠只让**面板与内容消失**，棋盘必须逐像素不变。
	#   ★ 顺带钉住"折叠后带宽仍 ≥ 把手宽"：把手是要点的，棋盘缩到它底下 = 把那块点击送给棋盘。
	var area_open := board_area()
	var bb_open: Rect2 = _board_bbox()
	_drawer_left_open = false
	_drawer_right_open = false
	_refit_hud()
	_adapt_to_screen()
	var area_closed := board_area()
	var bb_closed: Rect2 = _board_bbox()
	var bands_closed := drawer_bands()
	var still_ok: bool = area_open.is_equal_approx(area_closed) \
			and bb_open.is_equal_approx(bb_closed) \
			and absf(bands_closed.x - bands.x) < 0.5 \
			and absf(bands_closed.y - bands.y) < 0.5 \
			and bands_closed.x >= DRAWER_HANDLE_W - 0.5 \
			and bands_closed.y >= DRAWER_HANDLE_W - 0.5
	checks.append(["③ 折叠前后棋盘纹丝不动｜钉住棋盘固定在中心这条口令", still_ok,
			"棋盘盒 %s → %s ｜ 带宽 %s → %s" % [
					str(bb_open.size), str(bb_closed.size), str(bands), str(bands_closed)]])

	# ---- ④ **阴性对照**：让位系数压 0 ⇒ 面板照旧展开、棋盘不再让位 ⇒ ①必须报红 ----
	_drawer_left_open = true
	_drawer_right_open = true
	_drawer_band_ratio = 0.0
	_refit_hud()
	_adapt_to_screen()
	var jr_bad: Array = judge_drawer_layout()
	checks.append(["④ 阴性对照·让位系数压 0 后判据必须报红｜没有这一半 ① 可能恒真",
			not bool(jr_bad[0]), String(jr_bad[1])])
	_drawer_band_ratio = 1.0
	_refit_hud()
	_adapt_to_screen()

	# ---- ⑤ 走**真实点击入口**翻抽屉：状态翻、面板与**按钮簇**一起翻、棋盘不动 ----
	#   ★ 用 `pressed.emit()` 而不是直接改 `_drawer_right_open`：后者只证明"赋值语句能跑"，
	#     证明不了"按钮接的是这条线"（§127 判据要量真实入口）。
	#   ★ 2026-10-22 加断言 `_hud_box.visible`（用户报「抽屉收起仍有按钮在」）：
	#     `_hud_box` 不是面板的子节点 ⇒ 面板藏了、按钮还浮着。**只查面板会全绿**，
	#     因为面板确实藏了 —— 这一类"半藏"只有同时查内容才逮得到。
	var before_open: bool = _drawer_right_open
	var before_vis: bool = _drawer_right_panel.visible
	var before_box: bool = _hud_box.visible
	var bb_before: Rect2 = _board_bbox()
	_drawer_right_handle.pressed.emit()
	await get_tree().process_frame
	var after_open: bool = _drawer_right_open
	var after_vis: bool = _drawer_right_panel.visible
	var after_box: bool = _hud_box.visible
	var bb_after: Rect2 = _board_bbox()
	var toggle_ok: bool = (after_open != before_open) and (after_vis != before_vis) \
			and (after_box != before_box) and bb_before.is_equal_approx(bb_after)
	checks.append(["⑤ 点把手真的翻转抽屉｜面板与按钮簇同生同灭且棋盘不动",
			toggle_ok, "开={%s→%s} 面板={%s→%s} 按钮簇={%s→%s}" % [
					str(before_open), str(after_open), str(before_vis), str(after_vis),
					str(before_box), str(after_box)]])
	_drawer_right_handle.pressed.emit()      # 还原成展开
	await get_tree().process_frame

	# ---- ⑥ 右抽屉内容（`_hud_box` 那一簇按钮）完整落在内容区内 ----
	#   ★ 抓的是"按钮把面板撑破"这一类：面板是 `Panel`（尺寸被写死），内容一旦超宽就溢出到
	#     棋盘那一侧，而 `judge_drawer_layout()` 只看面板矩形 ⇒ 它看不见溢出。
	_refit_hud()
	await get_tree().process_frame
	var cr1 := drawer_content_rect(1)
	var box_rect := Rect2(_hud_box.position, _hud_box.size)
	var box_ok: bool = cr1.grow(2.0).encloses(box_rect)
	checks.append(["⑥ 右抽屉的按钮簇完整落在内容区内｜内容区 %s" % str(cr1),
			box_ok, "按钮簇 %s" % str(box_rect)])

	# ---- ⑦ 窄视口自动折叠（`_drawer_cramped()` 真的会挡住展开）----
	#   ★ 用一个**能改的量**把视口"变窄"：把横屏边距调到 4000 ⇒ 需要的宽度远超视口。
	#     改的是被测谓词的输入（边距），不是判据的期望值 —— 与 `--portraittest` ⑤d 同一条纪律。
	var keep_m: float = GameConfig.hud_landscape_margin
	GameConfig.hud_landscape_margin = 4000.0
	_refit_hud()
	var cramped_now: bool = _drawer_cramped()
	var bands_cramped := drawer_bands()
	var cramped_ok: bool = cramped_now \
			and (not _drawer_expanded(0)) and (not _drawer_expanded(1)) \
			and absf(bands_cramped.x - DRAWER_HANDLE_W) < 0.5 \
			and absf(bands_cramped.y - DRAWER_HANDLE_W) < 0.5
	GameConfig.hud_landscape_margin = keep_m
	_refit_hud()
	_adapt_to_screen()
	# ★ 摘要里的每个数字都要在**当场**取好：第一版写在还原之后，于是打印出
	#   "谓词 false … cramped=true"，同一行自相矛盾（判据绿、说明是假话）。
	checks.append(["⑦ 视口放不下时两侧自动退化成把手｜把横屏边距调到 4000 改被测谓词的输入",
			cramped_ok, "cramped=%s 带宽 %s" % [str(cramped_now), str(bands_cramped)]])

	# ---- ⑧ 出货态：让位系数必须是 1.0（防止有人把这把刀留在半开）----
	checks.append(["⑧ 让位系数出货为 1.0｜它是阴性对照的刀，不许留在半开位置",
			absf(_drawer_band_ratio - 1.0) < 0.0001, "系数 %.3f" % _drawer_band_ratio])

	# ---- ⑨ 抽屉底色与页面底**同深浅**（用户口令：抽屉也用和背景较接近的颜色）----
	#   ★ 三个量一起钉，缺一个都能骗过判据：
	#     ① 明度差 ≤ 0.10 —— "同深浅"，不许再出现深色砖压在浅色页面上；
	#     ② 明度差 ≥ 0.015 —— 也不许混成完全一样（那样面板没了边界，只剩一条描边说不清范围）；
	#     ③ 画在上面的墨色对比度 ≥ 4.5 —— 改底色最容易连带的坏法就是字看不见了（§130）。
	#        ★ 参照面必须是 `_drawer_surface()` 本身，**不是** `page_surface()`：
	#          2026-10-21 那两个"全绿的真 bug"就是被判据拿页面底当参照面放过去的。
	var dsurf: Color = _drawer_surface()
	var psurf: Color = GameConfig.page_surface()
	var dl: float = dsurf.get_luminance()
	var pl: float = psurf.get_luminance()
	var ink_cr: float = GameConfig.contrast_ratio(GameConfig.readable_ink_on(dsurf), dsurf)
	var lum_gap: float = absf(dl - pl)
	var surf_ok: bool = lum_gap <= 0.10 and lum_gap >= 0.015 and ink_cr >= 4.5
	checks.append(["⑨ 抽屉底色与页面底同深浅且字仍达标｜明度差 %.3f 字对比 %.2f" % [lum_gap, ink_cr],
			surf_ok, "抽屉 L=%.3f 页面 L=%.3f" % [dl, pl]])

	# ---- 复原现场 ----
	game_mode = int(sv["game_mode"])
	_net_color = int(sv["net_color"])
	_net_connected = bool(sv["connected"])
	_net_phase = str(sv["phase"])
	_drawer_left_open = bool(sv["left"])
	_drawer_right_open = bool(sv["right"])
	GameConfig.hud_landscape_margin = float(sv["cramped_margin"])
	_refresh_net_extras()
	_refit_hud()
	_adapt_to_screen()

	var failed: Array = []
	for c in checks:
		var okc: bool = (c[1] is bool) and (c[1] as bool)
		if not okc:
			failed.append(str(c[0]))
		print("[drawertest] %s %s（%s）" % [c[0], "✓" if okc else "✗", c[2]])
	print("[drawertest] 判据 %d 条，失败 %d 条%s" % [checks.size(), failed.size(),
			"" if failed.is_empty() else "：" + ", ".join(failed)])
	print("[drawertest] 结论：", "通过 ✓" if failed.is_empty() and checks.size() > 0 else "失败 ✗")
	get_tree().quit()

# ============================================================================
# ★ 2026-09-30 §24 第 5 步：本文件尾部原有 **5 个函数、约 190 行**自建联机自检，
#   已按用户口令「删除自建联机代码」整体移除（13010 行 → 12823 行）：
#     `_self_test_network()`    ← `--nettest-host / --nettest-client`（ENet 双进程 + RPC）
#     `_verify_net_result()`    ← 上者的终局核对（读 `_net_init_tiles` / `_net_init_verts`）
#     `_remember_board_size()`  ← 上者与两条邀请自检共用的"记盘面尺寸"
#     `_self_test_invite()`     ← `--matchtest-* / --relaytest-*`（走自建信令服建房号）
#     `_self_test_matchmake()`  ← `--mqtest-*`（走自建信令服快速匹配）
#
#   ★ 保留的联机自检**只有一条**：`_self_test_online()`（`--onlinetest`）—— 它不进网络，
#     单进程直呼 `_apply_action()` 验权威路径，与通道无关（回归清单里的 `onlinetest` 靠它）。
#   ★ Steam 侧的联机自检在**别处**，一条未动：`--steamtest`（`steam_net.gd`，25 条判据）、
#     `--steamnet`（本文件的 `_steam_net_selftest_finish`，8 条，P2P 自环）。
#   ★ 回退**不能只恢复这个尾巴**：第 5 步在文件中段还删了中继路 / ENet 路 / 两个 `@rpc` /
#     四个 `NetworkManager` 订阅，必须一并回退才跑得起来 —— 完整回退清单（五组一起做）见
#     工程根 `Steam上线_部署指南.md` **§7.5**「第 5 步的回退清单」。本文件的改前快照：
#     `瓷砖围棋_临时输出/step5/game.gd.bak_step5_tail`（工程外的工作区目录）。
# ============================================================================

# ============================================================================
# 自检（--xgtest，2026-10-14）：图围棋骨架（第三套独立实现）与生产引擎逐手对拍
# ----------------------------------------------------------------------------
# 背景：《图围棋规则引擎研究.md》的最小骨架（工作区 go_graph.gd）把「严格模拟落子 /
#   Tromp–Taylor 面积计分 / Zobrist superko」拼成了一份独立实现。本判据把它接进真盘：
#   邻接表直接取生产 `adjacency`（真 Penrose 图），随机局逐手镜像，逐手断言一致。
# ★ 三方角色（两套实现对拍 ≠ 这里有三套）：
#   · 生产 place_stone()/can_place_at() —— 被测主实现（玩家点击路径）
#   · ai_engine._play()                 —— 第二实现（--rulestest 已对拍）
#   · _xg_* 镜像（本节）                 —— 第三实现（独立写法，零共享代码）
# ★ 已知口径差（不是 bug，判据里显式豁免）：
#   · 生产=单点劫（ko_point 一格禁着）；镜像=superko（全历史同形禁着）更严 ⇒
#     「生产收、镜像拒(superko)」记为**命中**并豁免重放（命中率正是 10-14 对账
#     认定的缺口数据：superko 若落地，真实对局会被多拦多少手）。
#   · 生产总分 = 子数+领地+提子(+komi)；镜像 TT = 子数+领地（提子已化为空点领地）
#     ⇒ 终局对拍只比「子数+领地」两个分量，不比总分（口径不同，总量必不等）。
# 红了做什么：任一分歧 ⇒ 生产与独立实现规则分叉（抓陈旧气/提子/自杀类回归），
#   按 [xgtest] 打印的局号+手数+tile 三元组直接复现定位。

var _xg_board: Dictionary = {}      # tile_id -> Stone.EMPTY/BLACK/WHITE
var _xg_adj: Dictionary = {}        # tile_id -> Array[int]（复制自生产 adjacency）
var _xg_ss_of: Dictionary = {}      # tile_id -> ssid（-1=空）
var _xg_strings: Dictionary = {}    # ssid -> {"nodes":Dictionary,"chi":Dictionary}
var _xg_next_ssid: int = 0
var _xg_zob: Dictionary = {}        # tile_id -> [空,黑,白] 各一个 64 位随机数
var _xg_hash: int = 0
var _xg_hist: Dictionary = {}       # 历史局面指纹 -> true（positional superko）

func _xg_rand64(rng: RandomNumberGenerator) -> int:
	# Godot 4 int 是 64 位有符号：高 31 位<<32 | 低 32 位，避开符号位溢出
	return ((rng.randi() & 0x7FFFFFFF) << 32) | (rng.randi() & 0xFFFFFFFF)

func _xg_reset() -> void:
	_xg_board.clear(); _xg_adj.clear(); _xg_ss_of.clear(); _xg_strings.clear()
	_xg_zob.clear(); _xg_hist.clear()
	_xg_next_ssid = 0
	_xg_hash = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261014      # 固定种子：同盘必得同一张指纹表（判定与随机数无关，只求可复现）
	for i in tiles.size():
		_xg_board[i] = Stone.EMPTY
		_xg_ss_of[i] = -1
		var row := [0, _xg_rand64(rng), _xg_rand64(rng)]
		_xg_zob[i] = row
		_xg_hash ^= row[0]
		_xg_adj[i] = (adjacency[i] as Array).duplicate()
	_xg_hist[_xg_hash] = true   # 空盘也是历史局面之一

func _xg_snapshot() -> Dictionary:
	var ss := {}
	for k in _xg_strings.keys():
		var s: Dictionary = _xg_strings[k]
		ss[k] = {"nodes": (s["nodes"] as Dictionary).duplicate(),
			"chi": (s["chi"] as Dictionary).duplicate()}
	return {"board": _xg_board.duplicate(), "ss_of": _xg_ss_of.duplicate(),
		"strings": ss, "next_ssid": _xg_next_ssid, "hash": _xg_hash}

func _xg_restore(s: Dictionary) -> void:
	_xg_board = (s["board"] as Dictionary).duplicate()
	_xg_ss_of = (s["ss_of"] as Dictionary).duplicate()
	_xg_strings.clear()
	for k in (s["strings"] as Dictionary).keys():
		var d: Dictionary = (s["strings"] as Dictionary)[k]
		_xg_strings[k] = {"nodes": (d["nodes"] as Dictionary).duplicate(),
			"chi": (d["chi"] as Dictionary).duplicate()}
	_xg_next_ssid = int(s["next_ssid"])
	_xg_hash = int(s["hash"])

func _xg_rechi(ssid: int) -> void:
	var chi := {}
	for n in (_xg_strings[ssid]["nodes"] as Dictionary).keys():
		for nb in _xg_adj[n]:
			if _xg_board[nb] == Stone.EMPTY:
				chi[nb] = true
	_xg_strings[ssid]["chi"] = chi

## 第三套实现的严格模拟落子。返回 {"ok":bool, "captured":Array, "reason":String}
## reason ∈ ""(成功) / "occupied" / "suicide" / "superko"（check_superko=false 不产 superko）
func _xg_try_place(t: int, color: int, check_superko: bool) -> Dictionary:
	if _xg_board[t] != Stone.EMPTY:
		return {"ok": false, "captured": [], "reason": "occupied"}
	var snap := _xg_snapshot()
	var enemy: int = Stone.WHITE if color == Stone.BLACK else Stone.BLACK
	_xg_board[t] = color
	# 合并友串（独立写法：新 ssid + 搬 nodes）
	var friends: Array = []
	for nb in _xg_adj[t]:
		if _xg_board[nb] == color and _xg_ss_of[nb] != -1 and not friends.has(_xg_ss_of[nb]):
			friends.append(_xg_ss_of[nb])
	var ssid: int = _xg_next_ssid
	_xg_next_ssid += 1
	var nodes := {t: true}
	for f in friends:
		for n in (_xg_strings[f]["nodes"] as Dictionary).keys():
			nodes[n] = true
		_xg_strings.erase(f)
	_xg_strings[ssid] = {"nodes": nodes, "chi": {}}
	for n in nodes.keys():
		_xg_ss_of[n] = ssid
	_xg_rechi(ssid)
	# 提敌串：只查落点邻居（合法序列里远处的串不可能新死；生产 remove_dead_stones
	# 是全盘扫，但对合法序列两者等价——这正是要对拍的不变量之一）
	var captured: Array = []
	for nb in _xg_adj[t]:
		if _xg_board[nb] == enemy:
			var es: int = _xg_ss_of[nb]
			_xg_rechi(es)
			if (_xg_strings[es]["chi"] as Dictionary).is_empty():
				for n in (_xg_strings[es]["nodes"] as Dictionary).keys():
					_xg_board[n] = Stone.EMPTY
					_xg_ss_of[n] = -1
					captured.append(n)
				_xg_strings.erase(es)
	# 自杀判据：没提子且新串无气 ⇒ 回滚
	if captured.is_empty() and (_xg_strings[ssid]["chi"] as Dictionary).is_empty():
		_xg_restore(snap)
		return {"ok": false, "captured": [], "reason": "suicide"}
	# 提子后刷己方邻串气（防陈旧气）
	for nb in _xg_adj[t]:
		if _xg_board[nb] == color:
			_xg_rechi(_xg_ss_of[nb])
	# superko：O(1) 增量指纹（落子 XOR 进；被提子把敌色 XOR 出）
	var new_hash: int = int(snap["hash"]) ^ _xg_zob[t][color]
	for n in captured:
		new_hash ^= _xg_zob[n][enemy]
	if check_superko and _xg_hist.has(new_hash):
		_xg_restore(snap)
		return {"ok": false, "captured": [], "reason": "superko"}
	_xg_hash = new_hash
	_xg_hist[new_hash] = true
	return {"ok": true, "captured": captured, "reason": ""}

## TT 面积计分的「子数+领地」分量（独立写法；不含提子/komi——生产总分口径不同）
func _xg_area() -> Dictionary:
	var visited := {}
	var sb := 0
	var sw := 0
	for i in tiles.size():
		if _xg_board[i] == Stone.BLACK:
			sb += 1
		elif _xg_board[i] == Stone.WHITE:
			sw += 1
	for start in tiles.size():
		if _xg_board[start] != Stone.EMPTY or visited.has(start):
			continue
		var region: Array[int] = [start]
		visited[start] = true
		var qi := 0
		var touch_b := false
		var touch_w := false
		while qi < region.size():
			var cur: int = region[qi]
			qi += 1
			for nb in _xg_adj[cur]:
				var st: int = _xg_board[nb]
				if st == Stone.EMPTY:
					if not visited.has(nb):
						visited[nb] = true
						region.append(nb)
				elif st == Stone.BLACK:
					touch_b = true
				else:
					touch_w = true
		if touch_b and not touch_w:
			sb += region.size()
		elif touch_w and not touch_b:
			sw += region.size()
	return {Stone.BLACK: sb, Stone.WHITE: sw}

func _gograph_cross_test() -> void:
	if tiles.is_empty():
		print("[xgtest] 结论：失败 ✗ 棋盘未生成")
		get_tree().quit()
		return
	var games := 3
	var max_moves := 300
	var bites := 0                  # 生产收、镜像因 superko 拒 = 同形再现被拦
	var bite_samples: Array[String] = []
	var total_moves := 0
	for g in range(games):
		reset_game(true)
		_xg_reset()
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261014 + g * 7919
		current_player = Stone.BLACK
		_quiet_place = true
		var played := 0
		var guard := 0
		while played < max_moves and guard < 120000:
			guard += 1
			var t: int = rng.randi_range(0, tiles.size() - 1)
			if not can_place_at(t):
				continue
			var bp0: int = black_prisoners
			var wp0: int = white_prisoners
			if not place_stone(t, false):
				continue
			played += 1
			var mover: int = 3 - current_player    # place_stone 收尾已翻手（与 rulestest 同口径）
			var r: Dictionary = _xg_try_place(t, mover, true)
			if (not r["ok"]) and str(r["reason"]) == "superko":
				bites += 1
				if bite_samples.size() < 3:
					bite_samples.append("局%d 第%d手 t%d" % [g, played, t])
				r = _xg_try_place(t, mover, false)   # 豁免 superko 重放，保持两盘同步
			if not r["ok"]:
				_quiet_place = false
				print("[xgtest] 结论：失败 ✗ 镜像拒收生产合法手：局%d 第%d手 t%d reason=%s"
					% [g, played, t, r["reason"]])
				get_tree().quit()
				return
			# ① 盘面逐点一致（抓提子/自杀/陈旧气任何一类分叉）
			var diff := 0
			var sample := -1
			for i in tiles.size():
				if _xg_board[i] != board.get(i, Stone.EMPTY):
					diff += 1
					if sample < 0:
						sample = i
			if diff > 0:
				_quiet_place = false
				print("[xgtest] 结论：失败 ✗ 盘面分叉：局%d 第%d手 t%d 共%d点不一致（样本 生产=%d/镜像=%d）"
					% [g, played, t, diff, board.get(sample, -1), _xg_board[sample]])
				get_tree().quit()
				return
			# ② 提子数一致（生产按落子方入桶）
			var pc: int = (black_prisoners - bp0) if mover == Stone.BLACK else (white_prisoners - wp0)
			if pc != (r["captured"] as Array).size():
				_quiet_place = false
				print("[xgtest] 结论：失败 ✗ 提子数不一致：局%d 第%d手 t%d 生产=%d 镜像=%d"
					% [g, played, t, pc, (r["captured"] as Array).size()])
				get_tree().quit()
				return
		_quiet_place = false
		total_moves += played
		# ③ 终局「子数+领地」分量对拍（生产总分含提子/komi，不比总量）
		var ps: Dictionary = _compute_scores()
		var ms: Dictionary = _xg_area()
		var pb: int = int(ps["stones_black"]) + int(ps["territory_black"])
		var pw: int = int(ps["stones_white"]) + int(ps["territory_white"])
		if pb != int(ms[Stone.BLACK]) or pw != int(ms[Stone.WHITE]):
			print("[xgtest] 结论：失败 ✗ 终局面积分量不一致：局%d 生产 黑%d/白%d vs 镜像 黑%d/白%d"
				% [g, pb, pw, int(ms[Stone.BLACK]), int(ms[Stone.WHITE])])
			get_tree().quit()
			return
		print("[xgtest] 局%d：%d 手，终局子+地 黑=%d 白=%d 两侧一致 ✓" % [g, played, pb, pw])
	# ★ 刀 XG1（阴性对照）：把镜像第一颗非空子改成对方色 ⇒ 对拍必须立刻见分歧；
	#   打完即还原（判据对自身产物幂等）。它咬不住 = 上面整套逐手对拍是白装。
	var knife := -1
	for i in tiles.size():
		if _xg_board[i] != Stone.EMPTY:
			knife = i
			break
	var knife_ok := false
	if knife >= 0:
		var keep: int = _xg_board[knife]
		_xg_board[knife] = Stone.WHITE if keep == Stone.BLACK else Stone.BLACK
		var d := 0
		for i in tiles.size():
			if _xg_board[i] != board.get(i, Stone.EMPTY):
				d += 1
		_xg_board[knife] = keep
		knife_ok = d > 0
	if not knife_ok:
		print("[xgtest] 结论：失败 ✗ 阴性对照无牙齿（改一颗镜像子对拍仍报一致）")
		get_tree().quit()
		return
	# ④ 骨架对手冒烟：黑随机 / 白骨架自弈，必须全程合法。
	#   ★ 二版起骨架**不再用镜像**（评估走 `_xg_occ_*` 占位），故这里不再 `_xg_reset()`。
	reset_game(true)
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 20261015
	current_player = Stone.BLACK
	_quiet_place = true
	var moves3 := 0
	var guard3 := 0
	var xg_usec := 0        # 骨架每手耗时累加（二版评估成本的可观测口径）
	var xg_wmoves := 0
	while moves3 < 240 and guard3 < 60000:
		guard3 += 1
		if current_player == Stone.BLACK:
			var t3: int = rng3.randi_range(0, tiles.size() - 1)
			if not can_place_at(t3):
				continue
			if not place_stone(t3, false):
				continue
			moves3 += 1
		else:
			var us0: int = Time.get_ticks_usec()
			var wm: int = _xg_choose_move(Stone.WHITE)
			xg_usec += Time.get_ticks_usec() - us0
			xg_wmoves += 1
			if wm < 0:
				current_player = Stone.BLACK   # 白停一手（内联翻手，免弹数子提示）
				continue
			if not place_stone(wm, false):
				_quiet_place = false
				var nbs: Array[String] = []
				for nb in adjacency[wm]:
					nbs.append("t%d=%d" % [nb, int(board.get(nb, Stone.EMPTY))])
				print("[xgtest]    诊断：t%d 邻居 %s；ko=%d；can_place=%s"
					% [wm, ", ".join(nbs), ko_point, _yn(can_place_at(wm))])
				var occd: Array = _xg_occ_from_board()
				var ood: Dictionary = _xg_occ_play(occd, wm, Stone.WHITE)
				print("[xgtest]    骨架自评：ok=%s captured=%d" % [str(ood["ok"]), int(ood["captured"])])
				var dlist: Array[int] = []
				var no: Array = ood["occ"] as Array
				if no.size() == occd.size():
					for i in occd.size():
						if int(no[i]) != int(occd[i]):
							dlist.append(i)
				print("[xgtest]      骨架 occ 差异点=%s（%d 点）" % [str(dlist), no.size()])
				# （此处曾有"重放提子段"的打印，用于定 10-14 那个漏 break 的根因；已删 ——
				#   铁律 §70：判据不许重实现被测逻辑。上面"骨架自评 + occ 差异点 + 每个邻居的串与气"
				#   已足够定位，不必再养一份平行实现。）
				for nb in _xg_adj[wm]:
					var v: int = int(occd[nb])
					if v == Stone.EMPTY:
						print("[xgtest]      邻 t%d=空" % nb)
						continue
					var gg: Array = get_group(nb)
					var libs_all: Array[int] = []
					for g in gg:
						for m in adjacency[g]:
							if board.get(m, Stone.EMPTY) == Stone.EMPTY and not libs_all.has(m):
								libs_all.append(m)
					print("[xgtest]      邻 t%d=%d 串%s 全部气=%s 除落点气=%d"
						% [nb, v, str(gg), str(libs_all), _libs_of_group_excluding(nb, wm)])
				place_stone(wm, false)   # 静默已关：让生产自己打印拒绝原因
				print("[xgtest] 结论：失败 ✗ 骨架贪心给出非法着法 t%d（第%d手）" % [wm, moves3])
				get_tree().quit()
				return
			moves3 += 1
	_quiet_place = false
	if moves3 <= 0:
		print("[xgtest] 结论：失败 ✗ 骨架自弈零着（冒烟无效）")
		get_tree().quit()
		return
	print("[xgtest] ④ 骨架自弈冒烟：%d 手（黑随机/白骨架）全程合法 ✓；骨架 %d 手共 %.1f ms（均 %.1f ms/手）"
		% [moves3, xg_wmoves, float(xg_usec) / 1000.0,
			(float(xg_usec) / 1000.0) / float(maxi(xg_wmoves, 1))])
	print("[xgtest] 共 %d 局 %d 手：逐手盘面/提子对拍 0 分歧；终局面积分量全等；刀 XG1 咬合 ✓"
		% [games, total_moves])
	print("[xgtest] superko 命中 %d 次（生产单点劫放行、镜像按同形再现拦下）%s"
		% [bites, str(bite_samples)])
	print("[xgtest] 结论：通过 ✓")
	get_tree().quit()


# ============================================================================
# 骨架对手（主菜单「对战方式·疾风」档，2026-10-14 立项为「测试AI」/10-15 转正定名）
# ----------------------------------------------------------------------------
# 白方由第三套实现接管。
# 入口 = 主菜单「对战方式」行「疾风」瓷砖（用户口令 10-14：从游戏内 HUD 挪进菜单；
#   10-15 用户口令「把测试AI也划为正式吧」⇒ 转正定名 + 选中态持久化）。
#   菜单开局写 `GameConfig.mode = VS_AI` + `GameConfig.xg_opponent = true`；
#   本文件 `_ready` 把后者转成 `xg_play_mode` ⇒ `_start_ai_turn()` 里白方不走 ai_engine，
#   由 `_xg_choose_move()` 接管。
#
# ★★★ 二版（2026-10-14 晚，**用户实测反馈驱动**）：「它菜的不行，下棋像随机，但是速度非常快」。
#   体检结论：一版是「纯 1 手 TT 面积差」，缺陷是**结构性**的，调参救不了：
#     ① **并列爆炸 ⇒ 看起来随机**：空盘上落任何一点，整片空区都只挨着自己 ⇒ 逐点面积差
#        **完全相同**（首手 120 个候选全并列）；中盘同理 —— 领地归属是"翻转式"的
#        （单色触 = 归他 / 双色触 = dame），大多数着法差值恰好 0 ⇒ 大量并列靠随机挑。
#     ② **送死是"赚"的**：往对方实空丢一子会让那片大空触双色 ⇒ 对方瞬间掉一大块，
#        自己只多 1 子 ⇒ 1 手贪心**鼓励**入侵送死（面积差贪心的经典病，与权重无关）。
#     ③ 没有「别填自家实空」的概念 ⇒ 终盘在自己空里乱填（面积计分下收益恒 0，还白丢一手）。
#   二版三条对策：**次级启发**（提子 / 被打吃 / 接触）+ **看对手一手回应** + **跳过自家实空**。
#   用户那句"速度非常快"正是预算来源（实测每手耗时见 `--xgtest` ④ 的打印）。
#
# ★ 评估（数值全部 `@export`，运行期可调 —— 用户长期口径：别把数值写死）：
#     eval(c) = 面积差(子+领地) + w_capture×本手提子数 − w_atari×己方被打吃子数
#                                + w_contact×接触点数
#   两层选择：先按 eval 取我方前 `xg_top_k`，再让对手按同一 eval 挑其最优回应，
#   最终分 = 我落子后的分 − 对手最优回应分（`xg_depth=1` 退回一版，供 `--xgfight` 对照）。
#
# ★ 实现口径：评估**不碰**镜像棋串表（`_xg_board`/`_xg_strings` 只服务 `--xgtest` 的逐手对拍），
#   而是把占位拷成 `Array[int]` 做局部 flood fill ⇒ 单次试落比 `_xg_try_place` 便宜得多
#   （二版一手 ≈ 千次试落，靠这个才跑得动）。
#   ⚠️ 这套 flood fill **必须同色连通**（判据写 `== 落点色`，不是 `!= EMPTY`）—— 同款坑在
#     一版的 `_xg_sync_from_board`（本轮已删）上踩过：`!= EMPTY` 会把黑白灌进同一串，
#     气判定全错、镜像判合法而生产判自杀。重建/遍历棋串时先问"同色了没有"。
var xg_play_mode := false        # true = 白方由骨架接管（疾风档；_ready 从 GameConfig.xg_opponent 读）
## true = 白方由**渗流引擎** `LiushuiAI` 接管（流水档；_ready 从 GameConfig.liushui_opponent 读）。
## ★ 与 `xg_play_mode` 平级、互斥、恒 false 的默认值 —— 三档（磐石/疾风/流水）里只有一档为真。
var liushui_play_mode := false
## true = 白方由**神经网络先验引擎** `YemaAI` 接管（野马档；_ready 从 GameConfig.yema_opponent 读）。
## ★ 与上两者平级、互斥。四档（磐石/疾风/流水/野马）里恒只有一档为真。
var yema_play_mode := false
var _xg_rng := RandomNumberGenerator.new()


@export var xg_depth: int = 2             # 1=一版（纯 1 手面积差）｜2=加对手一手回应
@export var xg_top_k: int = 12            # 我方候选上限（按 eval 取前 K；越大越慢越强）
@export var xg_w_capture: float = 3.0     # 每提一子的额外权重（面积已含基础收益，这是"想提子"的偏好）
@export var xg_w_atari: float = 1.5       # 己方落子后仍处 1 气的子（每子）罚分 ⇒ 压制自打吃
@export var xg_w_contact: float = 0.5     # 每个相邻已占点（己/敌）加分 ⇒ 别在空处乱丢子
@export var xg_skip_own_eye: bool = true  # 跳过「四邻皆己色」的自家实空/真眼
# ★ 2026-10-20 新增两项启发。默认值 = `--xgtune` 实测定出来的（n6 × 换色配对）：
#   关着两项 vs 开着两项 ⇒ 2 胜 10 负、目差均值 -38.4、**配对 t=-3.33**（超过 |t|≥3 门槛）。
#   · `xg_w_weak2`：己方 2 气子（每子）轻罚。原版只罚 1 气 ⇒ 3 气→2 气这一步**没有梯度**，
#     评估看不见"我的棋在变薄"，等掉到 1 气往往已经晚一手。
#   · `xg_w_enemy_atari`：对方 1 气子（每子）奖励。原版只有真提掉（`captured`）才算分
#     ⇒ 看不见"这一手能先手攻它 4 个子"，白丢大量攻杀先手。
#   两项都在 `_xg_occ_metrics()` 的**同一次遍历**里顺手统计（`libs.size()` 本来就算了）。
@export var xg_w_weak2: float = 0.5
@export var xg_w_enemy_atari: float = 2.0
# ★ 2026-10-20 二轮：`xg_w_enemy_weak2` = 对方 **2 气**子（每子）奖励。
#   上一轮给**己方**补了 2 气梯度（`weak2`）就换来 +39 目 / t=3.85，说明"气数梯度"是这台引擎的
#   主要盲区；而敌方那半边一直只有 1 气（`enemy_atari`）⇒ **3 气压到 2 气这一步评估完全看不见**，
#   攻势压到一半就转去别处。与己方对称补上，同一趟遍历顺带统计（`libs.size()` 本就算出）＝零额外成本。
#   ★ 2026-10-21 定案 1.0（两批独立 pin，预登记两阶段协议）：
#     探索 p20261021 n=32：A 11 / B 20 / 平 1，均值 −30.88，t=−2.84
#     确认 p20261022 n=60：A 23 / B 36 / 平 1，均值 −20.13，**t=−3.16（过 |t|≥3）**
#   为什么是 1.0 而不是 2.0/4.0：那两档在探索阶段都是平的（t=−0.94 / −0.36）
#     ⇒ 敌方 2 气奖励是**轻推**，压重了会把评估从"求稳"推到"乱攻"。
@export var xg_w_enemy_weak2: float = 1.0
# ★ 2026-10-20：可复现开关。≥0 时每手用这个种子代替 `randomize()`（仪器/调参要配对），
#   -1 = 真实对局的随机性（保持现状）。没有它，A/B 对照的差异里永远混着随机噪声。
@export var xg_rng_pin: int = -1

## 占位快照（Array[int]，索引 = tile_id）。比 `_xg_board` 便宜：没有棋串表。
## `src` 为空 = 读实时 `board`；非空 = 读传入的**快照**。
## ★ 快照入口是给**后台线程**用的（`_xg_choose_move_async()`）：线程要跑 ~117ms，
##   而主线程在这段时间里可能悔棋/重开（会写 `board`）⇒ 线程若直接读成员 `board`，
##   就是**并发读写同一个 Dictionary**（Godot 容器非线程安全 ⇒ 可能崩，不只是"算错"）。
##   ⇒ 异步路径一律传 `board.duplicate()`，线程只碰那份拷贝。
##   ⚠️ `ko_point` 故意不传：它是 `int`（值语义），误读最坏让骨架算错一手，
##     而那种结果会被 `gen != _ai_gen` 的作废检查丢掉，不落盘、不改局面。
func _xg_occ_from_board(src: Dictionary = {}) -> Array:
	var from: Dictionary = board if src.is_empty() else src
	var occ: Array = []
	occ.resize(tiles.size())
	for i in tiles.size():
		occ[i] = int(from.get(i, Stone.EMPTY))
	return occ

## 占位上试落一手。提子/自杀判据与生产同源。返回 {"ok", "occ"(新占位), "captured"(提子数)}。
## ⚠️ 只查落点邻居的敌串 —— 合法序列里远处的串不可能新死（与生产 `remove_dead_stones` 等价）。
func _xg_occ_play(o: Array, t: int, color: int) -> Dictionary:
	if o[t] != Stone.EMPTY:
		return {"ok": false, "occ": [], "captured": 0}
	var enemy: int = Stone.WHITE if color == Stone.BLACK else Stone.BLACK
	var p: Array = o.duplicate()
	p[t] = color
	var captured := 0
	var seen_e := {}
	for nb in _xg_adj[t]:
		if p[nb] != enemy or seen_e.has(nb):
			continue
		var comp: Array[int] = [nb]
		seen_e[nb] = true
		var qi := 0
		var has_lib := false
		# ★★ 不许提前 break：必须把整串完整扩展完，再一次性判气。
		#   提前 break 只标记了串的一部分，却把"半成品"写进**跨串共享**的 `seen_e`；
		#   之后从同一串的**另一个**入口进来时 `seen_e.has(m)` 为真 ⇒ 无法扩展 ⇒
		#   串被截断，若截剩下的那点自己四邻无空 ⇒ 误判「无气、可提」。
		#   病例（2026-10-14 `--xgtest` ④）：白落 t88，黑串 [77,87] 实有气 75/76，
		#   骨架却把 87 当死子提掉（captured=1）判合法，生产判自杀。
		#   口径与生产 `remove_dead_stones()` 同源：先求完整串，再判气。
		while qi < comp.size():
			var cur: int = comp[qi]
			qi += 1
			for m in _xg_adj[cur]:
				if p[m] == Stone.EMPTY:
					has_lib = true
				elif p[m] == enemy and not seen_e.has(m):
					seen_e[m] = true
					comp.append(m)
		if not has_lib:
			for m in comp:
				p[m] = Stone.EMPTY
			captured += comp.size()
	# 自杀判据：提了子则被提点就在旁边 ⇒ 己方必有气，只需在没提子时算
	if captured == 0:
		var seen_m := {t: true}
		var comp2: Array[int] = [t]
		var qi2 := 0
		var has_lib2 := false
		while qi2 < comp2.size():
			var cur2: int = comp2[qi2]
			qi2 += 1
			for m2 in _xg_adj[cur2]:
				if p[m2] == Stone.EMPTY:
					has_lib2 = true
				elif p[m2] == color and not seen_m.has(m2):
					seen_m[m2] = true
					comp2.append(m2)
		if not has_lib2:
			return {"ok": false, "occ": [], "captured": 0}
	return {"ok": true, "occ": p, "captured": captured}

## 占位上的一体化度量（两趟 flood fill）：TT 面积分量 + 己方被打吃子数。
func _xg_occ_metrics(o: Array, color: int) -> Dictionary:
	var n := o.size()
	var seen: Array = []
	seen.resize(n)
	seen.fill(0)
	var sb := 0
	var sw := 0
	var atari := 0
	var weak2 := 0          # ★ 2026-10-20：己方 2 气子数（"正在变薄"的梯度）
	var enemy_atari := 0    # ★ 2026-10-20：对方 1 气子数（先手攻杀的奖励）
	var enemy_weak2 := 0    # ★ 2026-10-20 二轮：对方 2 气子数（攻击的中间梯度）
	for i in n:                                   # ① 棋串（棋子数 + 1 气串）
		var c: int = o[i]
		if c == Stone.EMPTY or seen[i] == 1:
			continue
		var comp: Array[int] = [i]
		seen[i] = 1
		var qi := 0
		var libs := {}
		while qi < comp.size():
			var cur: int = comp[qi]
			qi += 1
			for nb in _xg_adj[cur]:
				var v: int = o[nb]
				if v == Stone.EMPTY:
					libs[nb] = true
				elif v == c and seen[nb] == 0:
					seen[nb] = 1
					comp.append(nb)
		if c == Stone.BLACK:
			sb += comp.size()
		else:
			sw += comp.size()
		# ★ 2026-10-20：同一次遍历分出三档（`libs.size()` 本来就算出来了 ⇒ 零额外成本）。
		var nl: int = libs.size()
		if c == color:
			if nl == 1:
				atari += comp.size()
			elif nl == 2:
				weak2 += comp.size()
		else:
			if nl == 1:
				enemy_atari += comp.size()
			elif nl == 2:
				enemy_weak2 += comp.size()
	for i in n:                                   # ② 空区归属（单色触 ⇒ 归他；双色触 ⇒ dame）
		if o[i] != Stone.EMPTY or seen[i] == 1:
			continue
		var comp2: Array[int] = [i]
		seen[i] = 1
		var qi2 := 0
		var touch_b := false
		var touch_w := false
		while qi2 < comp2.size():
			var cur2: int = comp2[qi2]
			qi2 += 1
			for nb2 in _xg_adj[cur2]:
				var v2: int = o[nb2]
				if v2 == Stone.EMPTY:
					if seen[nb2] == 0:
						seen[nb2] = 1
						comp2.append(nb2)
				elif v2 == Stone.BLACK:
					touch_b = true
				else:
					touch_w = true
		if touch_b and not touch_w:
			sb += comp2.size()
		elif touch_w and not touch_b:
			sw += comp2.size()
	return {"black": sb, "white": sw, "atari": atari, "weak2": weak2,
		"enemy_atari": enemy_atari, "enemy_weak2": enemy_weak2}

## 一手的「己方视角」评估分（含三项启发）。返回 {"ok", "score"}。
func _xg_occ_score(o: Array, t: int, color: int) -> Dictionary:
	var r: Dictionary = _xg_occ_play(o, t, color)
	if not r["ok"]:
		return {"ok": false, "score": 0.0}
	var m: Dictionary = _xg_occ_metrics(r["occ"] as Array, color)
	var mine: int = int(m["black"]) if color == Stone.BLACK else int(m["white"])
	var theirs: int = int(m["white"]) if color == Stone.BLACK else int(m["black"])
	var contact := 0
	for nb in _xg_adj[t]:
		if o[nb] != Stone.EMPTY:
			contact += 1
	var sc: float = float(mine - theirs) \
		+ xg_w_capture * float(int(r["captured"])) \
		- xg_w_atari * float(int(m["atari"])) \
		- xg_w_weak2 * float(int(m["weak2"])) \
		+ xg_w_enemy_atari * float(int(m["enemy_atari"])) \
		+ xg_w_enemy_weak2 * float(int(m["enemy_weak2"])) \
		+ xg_w_contact * float(contact)
	return {"ok": true, "score": sc}

## 「四邻皆己色」= 自家实空内部点（真眼/实地）：面积计分下填它收益恒 0 且白丢一手 ⇒ 跳过。
## （四邻皆己 ⇒ 不可能提到子，所以跳过不会有副作用。）
func _xg_occ_own_eye(o: Array, t: int, color: int) -> bool:
	for nb in _xg_adj[t]:
		if o[nb] != color:
			return false
	return true

## 按评估分排序取前 k。返回 [{"t":int,"score":float}, ...] 降序。
func _xg_rank_occ(o: Array, color: int, k: int) -> Array:
	var out: Array = []
	for t in o.size():
		if o[t] != Stone.EMPTY or t == ko_point:
			continue   # 与生产单点劫闸同源（骨架 superko 不参与对局）
		if xg_skip_own_eye and _xg_occ_own_eye(o, t, color):
			continue
		var r: Dictionary = _xg_occ_score(o, t, color)
		if r["ok"]:
			out.append({"t": t, "score": float(r["score"])})
	out.sort_custom(func(x, y): return float(x["score"]) > float(y["score"]))
	if k > 0 and out.size() > k:
		out.resize(k)
	return out

## 骨架的着法选择（二版）。无着可下（含"只剩自家实空"）返回 -1 ⇒ 走 `_apply_ai_move` 的停一手路径。
func _xg_choose_move(color: int, src: Dictionary = {}) -> int:
	# ★ 邻接表自建（二版评估只用 `_xg_adj`，**不再依赖镜像 `_xg_reset()`**）：
	#   `_xg_adj` 原先只在 `_xg_reset()` 里构建，而二版已把 ④ 段的 `_xg_reset()` 删掉、
	#   `--xgfight` 那条路更是从没建过表 ⇒ 单独跑它时表为空（实测打印 `_xg_adj=0`）。
	#   表空 ⇒ `_xg_occ_play` 落点邻居循环 0 次 ⇒ 自杀判据"零邻居 ⇒ 零气" ⇒ 全盘误判自杀。
	#   成本可忽略（120 次浅拷贝），故每手无条件重建，顺带免疫任何陈旧/错位。
	_xg_adj.clear()
	for i in tiles.size():
		_xg_adj[i] = (adjacency[i] as Array).duplicate()
	var occ: Array = _xg_occ_from_board(src)
	var enemy: int = Stone.WHITE if color == Stone.BLACK else Stone.BLACK
	var top: Array = _xg_rank_occ(occ, color, xg_top_k)
	if top.is_empty():
		return -1
	var best: float = -(1 << 60)
	var cands: Array[int] = []
	for e in top:
		var t: int = int(e["t"])
		var v: float = float(e["score"])
		if xg_depth >= 2:
			# 对手最优回应：把它能拿到的分从我方收益里扣掉
			# ⇒ 「一手看着赚」的送死 / 自打吃当场掉分（一版看不见这一层）
			var r: Dictionary = _xg_occ_play(occ, t, color)
			if r["ok"]:
				var rep: Array = _xg_rank_occ(r["occ"] as Array, enemy, 1)
				if not rep.is_empty():
					v -= float(rep[0]["score"])
		if v > best + 0.0001:
			best = v
			cands.clear()
			cands.append(t)
		elif absf(v - best) <= 0.0001:
			cands.append(t)
	# ★ 2026-10-20：`xg_rng_pin >= 0` 时钉住种子 ⇒ 同局面同着法（仪器/调参要可配对）；
	#   默认 -1 ⇒ 每手 `randomize()`，保持真实对局的随机性（不会每局一模一样）。
	if xg_rng_pin >= 0:
		_xg_rng.seed = xg_rng_pin
	else:
		_xg_rng.randomize()
	return cands[_xg_rng.randi_range(0, cands.size() - 1)]

## 异步版选点：**后台线程**跑上面那个函数，主线程每帧照常渲染。
## ★ 为什么需要（2026-10-20 用户反馈「跟骨架下棋的时候落子会卡一下再播放落子动画」）：
##   二版（`xg_depth=2` + `xg_top_k=12`）每手约 **90ms**（要对 12 个候选各再做一轮
##   "对手最优回应"）⇒ 同步跑 = 主线程掉 5~6 帧，肉眼就是"卡一下，然后动画才开始"。
##   一版只要 5~10ms，所以当年没这问题 —— **卡顿是二版棋力的代价，不是渲染 bug**。
##   ⚠️ 别用"调小 `xg_top_k` / `xg_depth`"来治：那确实立刻不卡，但那是**降棋力**。
##     算的活一点不减，只把它挪出主线程。
## ★ 一致性是**结构性的**：这里调的就是同步版那个函数（不是复制一份实现）⇒
##   三个仪器（`--xgfight` / `--xgduel` / `--xgtest`）与真实对局**不可能**算出不同结果。
## ★ 线程安全依据：核心只读 `board`/`adjacency`/`ko_point`/`xg_*`（AI 回合里没人改它们），
##   只写 `_xg_adj`（每手开头整体重建）与 `_xg_rng`（末尾一次）—— 都是骨架私有状态，
##   主线程在对局中不碰，三大 `--xg*` 仪器又是同步跑的。结果经 `box` 回传，
##   `wait_to_finish()` 之后才读 ⇒ 有 happens-before。
## ⚠️ `wait_to_finish()` **必须**调到：不调 = 线程泄漏（退出时 Godot 会报"Thread 未等待"）。
func _xg_choose_move_async(color: int) -> int:
	var box := {"move": -1}
	# ★ 盘面快照：线程**只碰这份拷贝**（并发读写同一个 Dictionary 是会崩的，
	#   而"算错的着法"反倒无害 —— 它会被 `gen != _ai_gen` 作废）。微秒级开销。
	var snap: Dictionary = board.duplicate()
	var th := Thread.new()
	var job := func() -> void:
		box["move"] = _xg_choose_move(color, snap)
	var err: int = th.start(job)
	if err != OK:
		# 起不了线程就退回同步执行（宁卡一下，不崩、也不静默不出手）
		push_warning("骨架异步选点：线程启动失败 err=%d，退回同步" % err)
		return _xg_choose_move(color)
	while th.is_alive():
		await get_tree().process_frame
	th.wait_to_finish()
	return int(box["move"])


# ============================================================================
# 仪器（--xgfight，2026-10-14）：骨架二版 vs 一版配对换色自弈
# ----------------------------------------------------------------------------
# 为什么要有它：二版把棋力交给 5 个 `@export` 旋钮（深度/候选/三项权重/跳眼），
#   没有量具的话"能调"就是空话（铁律 §33：旋钮拧不动 = 死参数）。
#   本仪器**无判定、只出数**：各半局换色配对，报胜负与目差（komi=0，消除贴目偏置），
#   走的是生产的 `place_stone()` / `_compute_scores()` ⇒ 终局分口径与真实对局一致。
# ⚠️ 一版 = `xg_depth=1` + 三项权重清零 + 不跳自家眼（同一次运行里切旋钮，跑完复原）。
func _xg_fight_probe() -> void:
	var per_side := 6
	var komi_bak: float = komi
	komi = 0.0
	var wins_v2 := 0
	var wins_v1 := 0
	var margin_sum := 0
	var detail: Array[String] = []
	var fallback_n := 0        # 非法着法被兜底的次数（>0 ⇒ 下面的胜负数不可信）
	var w2_b := 0              # 二版**持黑**时的胜场
	var w2_w := 0              # 二版**持白**时的胜场
	var t0: int = Time.get_ticks_usec()
	for g in range(per_side * 2):
		reset_game(true)
		current_player = Stone.BLACK
		var v2_color: int = Stone.BLACK if g % 2 == 0 else Stone.WHITE
		_quiet_place = true
		var moves := 0
		var guard := 0
		while moves < 300 and guard < 80000:
			guard += 1
			var is_v2: bool = current_player == v2_color
			xg_depth = 2 if is_v2 else 1
			xg_w_capture = 3.0 if is_v2 else 0.0
			xg_w_atari = 1.5 if is_v2 else 0.0
			xg_w_contact = 0.5 if is_v2 else 0.0
			xg_skip_own_eye = is_v2
			var mv: int = _xg_choose_move(current_player)
			if mv < 0:
				passes += 1
				if passes >= 2:
					break
				current_player = Stone.WHITE if current_player == Stone.BLACK else Stone.BLACK
				continue
			if not place_stone(mv, false):
				var fallback := -1
				for t in tiles.size():
					if can_place_at(t):
						fallback = t
						break
				if fallback < 0:
					break
				fallback_n += 1
				place_stone(fallback, false)
			moves += 1
		_quiet_place = false
		xg_depth = 2
		xg_w_capture = 3.0
		xg_w_atari = 1.5
		xg_w_contact = 0.5
		xg_skip_own_eye = true
		var sc: Dictionary = _compute_scores()
		var tb: int = int(sc["total_black"])
		var tw: int = int(sc["total_white"])
		var s_v2: int = tb if v2_color == Stone.BLACK else tw
		var s_v1: int = tw if v2_color == Stone.BLACK else tb
		margin_sum += s_v2 - s_v1
		if s_v2 > s_v1:
			wins_v2 += 1
			if v2_color == Stone.BLACK:
				w2_b += 1
			else:
				w2_w += 1
		elif s_v1 > s_v2:
			wins_v1 += 1
		detail.append("%d手 二%d:%d一" % [moves, s_v2, s_v1])
	print("[xgfight] 二版 %d 胜 / 一版 %d 胜 / 平 %d（各 %d 局，换色配对，komi=0）"
		% [wins_v2, wins_v1, per_side * 2 - wins_v2 - wins_v1, per_side])
	print("[xgfight] 目差合计（二版−一版）= %d，均值 %+.1f；明细 %s"
		% [margin_sum, float(margin_sum) / float(per_side * 2), str(detail)])
	print("[xgfight] ★ 换色对称性体检：二版持黑 %d 胜 / 持白 %d 胜（各 %d 局）—— 两侧都赢 ⇒ 先后手偏置解释不了上面的比分"
		% [w2_b, w2_w, per_side])
	print("[xgfight] 非法着法兜底 %d 次%s"
		% [fallback_n, "（＝0，上面胜负数是引擎真实产出）" if fallback_n == 0 else "  ⚠️ >0 说明数据被兜底污染，先修引擎再看数"])
	print("[xgfight] 耗时 %.1fs（含 %d 局自弈）"
		% [float(Time.get_ticks_usec() - t0) / 1000000.0, per_side * 2])
	komi = komi_bak
	get_tree().quit()


## 骨架 7 个旋钮的**统一读写口**（仪器用）。
## ★ 抽出来的理由：`--xgtune` 每手都要在两套旋钮之间切换，写 14 行赋值两遍必然漏一项
##   （漏了就是"改了旋钮但没生效"，而仪器照样打印一份看起来很正常的表）。
## 旋钮键 → 属性名（**唯一真源**，§123）。加旋钮只改这一张表：
## 读（`_xg_knobs`）/ 写（`_xg_apply_knobs`）/ 校验（`_xg_knob_key_ok`）/ 打印（`_xg_knobs_text`）
## 四处全部由它派生。原先四处是手写的 —— 加一个键要补 4 行，漏一行的症状是
## "旋钮改了但没生效"，而仪器照样打印一份看起来正常的表（§113 同族，且**不报错**）。
const XG_KNOB_PROPS := {
	"cap": "xg_w_capture", "atari": "xg_w_atari", "contact": "xg_w_contact",
	"weak2": "xg_w_weak2", "enemy_atari": "xg_w_enemy_atari",
	"enemy_weak2": "xg_w_enemy_weak2",
	"topk": "xg_top_k", "depth": "xg_depth",
}

func _xg_knobs() -> Dictionary:
	var d := {}
	for k in XG_KNOB_PROPS:
		d[k] = get(XG_KNOB_PROPS[k])
	return d

func _xg_apply_knobs(d: Dictionary) -> void:
	# 类型按**属性现类型**决定（原先手写 int/float ⇒ 加一个 int 型旋钮就必须记得改这一行）。
	for k in XG_KNOB_PROPS:
		var prop: String = XG_KNOB_PROPS[k]
		if typeof(get(prop)) == TYPE_INT:
			set(prop, int(round(float(d[k]))))
		else:
			set(prop, float(d[k]))

## 元断言（§117）：**旋钮真的被写进去了吗**。
## 症状驱动：`_xg_apply_knobs()` 若漏一项（或键拼错被静默忽略），A/B 两臂实际是同一套旋钮
## ⇒ 逐局目差恒 0 ⇒ sd=0 ⇒ t=0 ⇒ 打印"无显著差异"，读起来像一次体面的阴性结果。
## 这是本工程最贵的一类假数据（§110 同族：参照物与被测物同退化）。
## ⇒ 写进去之后**回读**逐键比对，不等就立刻失败：宁可炸掉，也不许交出一份假表。
func _xg_knobs_verify(want: Dictionary, tag: String) -> bool:
	var got: Dictionary = _xg_knobs()
	for k in want:
		if not got.has(k):
			print("[xgtune] ✗ %s 回读缺键 %s" % [tag, k])
			return false
		if typeof(got[k]) == TYPE_INT:
			if int(got[k]) != int(want[k]):
				print("[xgtune] ✗ %s 旋钮回读不符：%s 写 %d 读 %d" % [tag, k, int(want[k]), int(got[k])])
				return false
		else:
			if absf(float(got[k]) - float(want[k])) > 0.0001:
				print("[xgtune] ✗ %s 旋钮回读不符：%s 写 %.4f 读 %.4f" % [tag, k, float(want[k]), float(got[k])])
				return false
	return true

func _xg_knob_key_ok(k: String) -> bool:
	return k in XG_KNOB_PROPS

func _xg_knobs_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	for k in XG_KNOB_PROPS:
		if typeof(get(XG_KNOB_PROPS[k])) == TYPE_INT:
			parts.append("%s=%d" % [k, int(d[k])])
		else:
			parts.append("%s=%.2f" % [k, float(d[k])])
	return " ".join(parts)


# ============================================================================
# 仪器（--xgtune，2026-10-20）：骨架**A/B 旋钮**配对换色自弈 + 配对 t 值
# ----------------------------------------------------------------------------
# 为什么有它：`--xgfight` 把旋钮写死成"二版 vs 一版"，评不了"新加的两项启发有用吗"；
#   而且它**只报胜负与目差合计、没有显著性** ⇒ 12 局 7:5 读不出"更强"还是"噪声"。
#   ⇒ 本仪器把 A/B 两组旋钮做成参数，并直接给**配对 t**（铁律 §16：|t|≥3 且 Δ>0）。
#
# ★ 可复现：每局设 `xg_rng_pin`。`_xg_choose_move()` 原本每手 `randomize()`，
#   于是"同分候选里选哪个"是个纯噪声源 —— 不钉住它，任何 A/B 差异都掺着随机性。
# ★ 换色配对：A 持黑 N 局 + 持白 N 局，swap 掉先手偏置（同 `--xgduel` 的口径）。
# ★ 方向：`d_i = 分_A − 分_B`，所以 `mean > 0` = **A 更强**（B 的改动没用），
#   `mean < 0` = **B 更强**。别把它读反（本工程的经典坑：符号反了结论就整个颠倒）。
# ============================================================================
func _xg_tune_probe() -> void:
	var per_side := 4
	var pin_base := 20261020      # pin 基：换一批 = 换一批开局，用于**独立复验**（防对某批 pin 过拟合）
	# ★ 默认覆盖组**必须为空**：上一轮的 `{"weak2":0.5,"enemy_atari":2.0}` 已经写进默认值了，
	#   若还留在这里，A/B 两臂就完全相同 ⇒ 逐局目差恒 0 ⇒ t=0 ⇒ 打印"无显著差异"（假阴性）。
	#   ⇒ 这里不再给默认假设，只接受命令行 `b=`；下面还有两道闸（空覆盖 / 两臂相同）。
	var over := {}
	for a in _argv():
		if a.begins_with("--xgtune="):
			for tok in a.substr(9).split(":"):
				if tok.is_empty():
					continue
				if tok.begins_with("n"):
					per_side = int(tok.substr(1))
				elif tok.begins_with("p"):
					pin_base = int(tok.substr(1))
				elif tok.begins_with("b="):
					over.clear()
					for kv in tok.substr(2).split(","):
						var p: PackedStringArray = kv.split("=")
						if p.size() != 2 or not _xg_knob_key_ok(p[0]):
							print("[xgtune] ✗ 未知旋钮「%s」（支持 %s）" % [kv, ", ".join(XG_KNOB_PROPS.keys())])
							get_tree().quit(1)
							return
						over[p[0]] = float(p[1])
				else:
					print("[xgtune] ✗ 未知 token「%s」（支持 nN / b=key=val,key=val）" % tok)
					get_tree().quit(1)
					return
	if per_side < 1:
		print("[xgtune] ✗ n 至少 1")
		get_tree().quit(1)
		return
	var base: Dictionary = _xg_knobs()
	var kb: Dictionary = base.duplicate()
	for k in over:
		kb[k] = over[k]
	if over.is_empty():
		print("[xgtune] ✗ 必须给 `b=key=val,...`：没给覆盖组 = A/B 两臂相同 = 假阴性")
		get_tree().quit(1)
		return
	if kb == base:
		print("[xgtune] ✗ 覆盖组与基线完全相同（%s）⇒ 这一轮什么也没测，不跑" % str(over))
		get_tree().quit(1)
		return
	if not _xg_knobs_verify(base, "A"):
		get_tree().quit(1)
		return
	_xg_apply_knobs(kb)
	if not _xg_knobs_verify(kb, "B"):
		_xg_apply_knobs(base)
		get_tree().quit(1)
		return
	_xg_apply_knobs(base)
	var komi_bak: float = komi
	var pin_bak: int = xg_rng_pin
	komi = 0.0
	var a_wins := 0
	var b_wins := 0
	var draws := 0
	var a_b := 0            # A 持黑胜场（换色体检：两侧都赢 ⇒ 先后手偏置解释不了比分）
	var a_w := 0
	var fallback_n := 0
	var diffs: Array[float] = []
	var detail: Array[String] = []
	var t0: int = Time.get_ticks_usec()
	var n_games: int = per_side * 2
	print("[xgtune] 盘=%s 格数=%d | A（基线）：%s" % [
		_bt_name(GameConfig.board_type), tiles.size(), _xg_knobs_text(base)])
	print("[xgtune] B（覆盖 %s）：%s" % [str(over), _xg_knobs_text(kb)])
	for gi in range(n_games):
		var a_color: int = Stone.BLACK if gi % 2 == 0 else Stone.WHITE
		xg_rng_pin = pin_base + gi * 131      # 每局一个固定 pin（同局两侧共用）
		_quiet_place = true
		reset_game(true)
		current_player = Stone.BLACK
		var moves := 0
		var guard := 0
		while moves < 260 and guard < 80000:
			guard += 1
			_xg_apply_knobs(base if current_player == a_color else kb)
			var mv: int = _xg_choose_move(current_player)
			if mv < 0:
				passes += 1
				if passes >= 2:
					break
				current_player = Stone.WHITE if current_player == Stone.BLACK else Stone.BLACK
				continue
			if not place_stone(mv, false):
				var fb := -1
				for t in tiles.size():
					if can_place_at(t):
						fb = t
						break
				if fb < 0:
					break
				fallback_n += 1
				place_stone(fb, false)
			moves += 1
		_quiet_place = false
		var sc: Dictionary = _compute_scores()
		var tb: int = int(sc["total_black"])
		var tw: int = int(sc["total_white"])
		var s_a: int = tb if a_color == Stone.BLACK else tw
		var s_b: int = tw if a_color == Stone.BLACK else tb
		diffs.append(float(s_a - s_b))
		if s_a > s_b:
			a_wins += 1
			if a_color == Stone.BLACK:
				a_b += 1
			else:
				a_w += 1
		elif s_b > s_a:
			b_wins += 1
		else:
			draws += 1
		detail.append("%d手 %d:%d" % [moves, s_a, s_b])
	# 收尾：旋钮与 pin 一律还原（否则会污染同进程后续的自检/对局）
	_xg_apply_knobs(base)
	xg_rng_pin = pin_bak
	komi = komi_bak
	var n: int = diffs.size()
	var mean := 0.0
	for d in diffs:
		mean += d
	mean = mean / float(maxi(1, n))
	var var_sum := 0.0
	for d in diffs:
		var_sum += (d - mean) * (d - mean)
	var sd: float = sqrt(var_sum / float(maxi(1, n - 1)))
	var tval := 0.0 if sd <= 0.0001 else mean / (sd / sqrt(float(maxi(1, n))))
	var sig: bool = absf(tval) >= 3.0 and absf(mean) > 0.5
	var who: String = "无显著差异"
	if sig:
		who = "A（基线）显著更强 ⇒ **B 的改动无效**" if mean > 0.0 else "B（覆盖组）显著更强 ⇒ **B 的改动有效**"
	print("[xgtune] A 胜 %d / B 胜 %d / 平 %d（各 %d 局，换色配对，komi=0，pin 固定）"
		% [a_wins, b_wins, draws, per_side])
	print("[xgtune] 目差（A−B）：合计 %+d｜均值 %+.2f｜sd %.2f｜配对 t=%+.2f（n=%d）"
		% [int(mean * float(n)), mean, sd, tval, n])
	print("[xgtune] ★ 门槛 |t|≥3 且 |均值|>0.5 ⇒ %s" % who)
	print("[xgtune] 换色体检：A 持黑 %d 胜 / 持白 %d 胜（各 %d 局）" % [a_b, a_w, per_side])
	print("[xgtune] 非法着法兜底 %d 次%s" % [fallback_n,
		"（＝0，上面的数是引擎真实产出）" if fallback_n == 0 else "  ⚠️ >0 ⇒ 数据被兜底污染，先修引擎"])
	print("[xgtune] 明细 %s" % str(detail))
	print("[xgtune] 耗时 %.1fs（%d 局自弈）" % [float(Time.get_ticks_usec() - t0) / 1000000.0, n])
	get_tree().quit()


# ============================================================================
# 仪器（--xgduel，2026-10-14）：**生产引擎 vs 骨架二版** 配对换色对打
# ----------------------------------------------------------------------------
# 为什么要有它：用户实测「测试AI（= 现在的疾风档）比自研的强」—— 手感印象必须变成硬数据。
#   本仪器量的是**引擎对引擎**，两侧跑同一个对局驱动器（回路口径照 `--aitune`）：
#     · 生产侧 = `AIEngine`，真实对局预算（与玩家面对的一致），有完整搜索；
#     · 骨架侧 = `_xg_choose_move()`，1~2 手贪心 + 五条启发，每手约 90ms。
#   它直接回答「生产 AI 是不是真的比骨架弱」—— 是"要不要把骨架那几条启发移植进生产
#   引擎"的决策依据。若生产赢，则"骨架更强"更可能是**人类视角的错觉**（下得蠢但未必输），
#   那移植的目标就不是 Elo 而是"不犯蠢"（坏棋模式率），两个指标不能混。
# 纪律：komi=0（消贴目偏置）· 换色配对（消先手优势）· 单线程（可复现）· 双方各自自然速度
#   （**故意不拉平预算**：玩家面对的是 200ms 的生产 AI，不是"公平算力"）。
# 读数：胜负 + 目差 + 非法着法数（>0 则数据要打折看）。
# 参数（冒号分隔，全部可选）：--xgduel=r3:ms200:m260:s20261015
#   rN 轮数（每轮 2 局换色，默认 3）｜ msN 生产侧每手预算 ms（默认 200）
#   mN 单局手数上限（默认 260）｜ sN 基准种子（默认 20261015，第 i 局 = 基准 + i*97）
func _xg_duel_probe() -> void:
	var rounds := 3
	var budget := GameConfig.ai_time_ms   # 与真实对局同源（默认 200）
	var max_moves := 260
	var base_seed := 20261015
	var threads_override := -1        # <0 = 用真实对局配置（GameConfig.ai_threads）
	for a in _argv():
		if a.begins_with("--xgduel="):
			for tok in a.substr(9).split(":"):
				if tok.begins_with("t"):
					threads_override = int(tok.substr(1))
				elif tok.begins_with("ms"):
					budget = int(tok.substr(2))
				elif tok.begins_with("r"):
					rounds = int(tok.substr(1))
				elif tok.begins_with("m"):
					max_moves = int(tok.substr(1))
				elif tok.begins_with("s"):
					base_seed = int(tok.substr(1))
				else:
					# 未知 token 硬报错：静默吃掉的参数会印出"看起来正常"的结果（同 --aitune 的坑）
					print("[xgduel] ✗ 未知 token：「%s」（支持 rN/msN/mN/sN）" % tok)
					get_tree().quit(1)
					return
	var komi_bak: float = komi
	komi = 0.0
	var quiet_bak: bool = _quiet_place
	_quiet_place = true
	var p_wins := 0
	var x_wins := 0
	var x_b := 0             # 骨架**持黑**时的胜场
	var x_w := 0             # 骨架**持白**时的胜场
	var draws := 0
	var diff_sum := 0
	var illegal_all := 0
	var detail: Array[String] = []
	var t0: int = Time.get_ticks_usec()
	var gi := 0
	var th_show: int = threads_override if threads_override >= 0 else GameConfig.ai_threads
	print("[xgduel] 盘=%s 格数=%d | 生产：预算 %dms/手、线程 %d%s、root_width %d%s | 骨架 ~90ms/手 | %d 轮（每轮 2 局换色）komi=0"
		% [_bt_name(GameConfig.board_type), tiles.size(), budget, th_show,
			"（自动）" if th_show == 0 else "", GameConfig.ai_root_width,
			"（自适应）" if GameConfig.ai_root_width == 0 else "", rounds])
	for _r in rounds:
		for flip in 2:
			var xg_is_black: bool = (flip == 0)
			var seed_i: int = base_seed + gi * 97
			gi += 1
			game_mode = LOCAL
			reset_game(true)
			var eng := AIEngine.new()
			# ★ 生产侧必须复刻**真实对局配置**（否则等于把它按住打）：
			#   真实对局 = GameConfig.ai_threads(0 ⇒ 多核自适应、上限 4) + ai_root_width(0 ⇒ 自适应 14)。
			#   ⚠️ 本仪器首版照抄 `--aitune` 写死 `threads = 1` —— 那套纪律是为「引擎 vs 引擎」
			#   的**对称**比较服务的（两边一起单线程）；本仪器公平的基准是"玩家实际面对的生产 AI"，
			#   单线程化 = 削弱被测方。要强制单线程做复现实验请显式 `t1`。
			eng.threads = threads_override if threads_override >= 0 else GameConfig.ai_threads
			eng.root_width = GameConfig.ai_root_width
			eng.time_budget_ms = budget
			eng.setup(adjacency, Stone.WHITE if xg_is_black else Stone.BLACK, seed_i)
			var passes := 0
			var moves := 0
			var illegal := 0
			var ms_p := 0
			while passes < 2 and moves < max_moves:
				var turn_color: int = current_player
				var prod_turn: bool = (turn_color == Stone.BLACK) != xg_is_black
				var mv := -1
				if prod_turn:
					mv = eng.choose_move(board, ko_point, turn_color)
					ms_p += eng.last_ms
				else:
					mv = _xg_choose_move(turn_color)
				if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
					if mv >= 0:
						illegal += 1
					passes += 1
				elif place_stone(mv, false):
					moves += 1
					passes = 0
				else:
					illegal += 1
					passes += 1
				if current_player == turn_color:   # 停一手/被拒不换行棋方 → 手动交换（同 --aitune）
					current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			var pb: int = int(sc.get("total_black", 0))
			var pw: int = int(sc.get("total_white", 0))
			var p_total: int = pw if xg_is_black else pb
			var x_total: int = pb if xg_is_black else pw
			diff_sum += p_total - x_total
			illegal_all += illegal
			var winner := "和"
			if p_total > x_total:
				p_wins += 1
				winner = "生产"
			elif x_total > p_total:
				x_wins += 1
				if xg_is_black:
					x_b += 1
				else:
					x_w += 1
				winner = "骨架"
			else:
				draws += 1
			detail.append("%d手 生%d:%d骨" % [moves, p_total, x_total])
			print("[xgduel] 局 %d 黑=%s → 生产 %d : 骨架 %d 胜=%s | 手数=%d 非法=%d | 生产耗时 %dms"
				% [gi, "骨架" if xg_is_black else "生产", p_total, x_total, winner, moves, illegal, ms_p])
	komi = komi_bak
	_quiet_place = quiet_bak
	print("[xgduel] 总账：生产 %d 胜 / 骨架 %d 胜 / 和 %d（%d 局换色）| 目差合计 %+d 均值 %+.1f"
		% [p_wins, x_wins, draws, gi, diff_sum, float(diff_sum) / float(maxi(gi, 1))])
	print("[xgduel] ★ 换色对称性体检：骨架持黑 %d 胜 / 持白 %d 胜（各 %d 局）" % [x_b, x_w, rounds])
	print("[xgduel] 非法着法 %d 次%s" % [
		illegal_all, "（＝0 ⇒ 双方着法全合法）" if illegal_all == 0 else "  ⚠️ >0 ⇒ 数据要打折看"])
	print("[xgduel] 明细 %s" % [str(detail)])
	print("[xgduel] 耗时 %.1fs" % [float(Time.get_ticks_usec() - t0) / 1000000.0])
	get_tree().quit()


## 仪器（--yemaduel，2026-10-23）：野马**开网络** vs **关网络**（= 同参数磐石）配对换色自弈。
##
## ★ 为什么必须有这一条：`--yematest` 能证明"网络接上了、先验进了根层、钩子位置对"，
##   但它**一个字都没说棋有没有变强**。而 §137（Goodhart）的教训正是"训练场指标涨、
##   真局反而退"—— 那次自救率 23.6%→62% 的旋钮，真局配对是被提子**多了** 24 个/局。
##   ⇒ 接入后的第一件事就是真局 A/B，且**只认结构量**（胜负 / 被提子数）；
##     目差只当参考：同一批数据在双峰分布下"均值+t"与"胜率"会给出相反结论（§125）。
##
## ★ 可复现（否则配对结论不能读）：**单线程 + 固定 pw + 固定 seed** 三件套，
##   时间预算设成兜底值 ⇒ `max_playouts` 是唯一停止条件。
##   （对比 `--xgduel`：它复刻真实 200ms 预算 ⇒ 依机器负载而变 ⇒ 实测同 seed 两次
##    跑的不是同一局，只能合并算、不能按同局配对。本仪器刻意不那样。）
##
## 用法：`--yemaduel`（默认 8 轮 = 16 局）｜`--yemaduel=r12`｜`--yemaduel=r8:pw80:s20261023`
func _yema_duel_probe() -> void:
	var rounds := 8
	var pw_lim := 50
	var base_seed := 20261023
	var max_moves := 260
	var nn_w := 1.0            # 开NN 那一侧的 `nn_weight`（0.3 = 名次混合只取三成）
	# ★ `--yemaB=<权重.json>`（2026-10-26 加）：**第二份权重**。
	#   给了 ⇒ 两侧都用网络（A=线上权重、B=这一份）⇒ 变成**两个 checkpoint 换色对打**；
	#   没给 ⇒ 老行为：B 侧关网络（= 同参数磐石）。两种模式由这一个变量决定，没有第三种。
	#   为什么需要：`val_top1` 换目标就不可比，且已知被搜索噪声主导（另见 nn/probe_ceiling.py）
	#   ⇒ "新权重更强"这句话只有对打能说。用独立 flag 而不是 `--yemaduel` 的 token，
	#   因为 token 分隔符是 `:`，而 Windows 绝对路径 `C:/...` 本身就带冒号。
	var nn_b_path := ""
	for a in _argv():
		if a == "--yemaB" or a.begins_with("--yemaB="):
			# ★ 写成整条字面量 `"--yemaB"` 才能被孤儿闸认出来（§113），
			#   只写 begins_with("--yemaB=") 的话这个入口对闸**隐形**。
			nn_b_path = a.substr(8).strip_edges()
			if nn_b_path == "":
				print("[yemaduel] ✗ 用法：--yemaB=<权重.json>（裸写会静默退化成老行为，所以直接拒）")
				get_tree().quit(2)
				return
			break
	for a in _argv():
		if a.begins_with("--yemaduel="):
			for tok in a.substr(11).split(":"):
				if tok.begins_with("r"):
					rounds = int(tok.substr(1))
				elif tok.begins_with("pw"):
					pw_lim = int(tok.substr(2))
				elif tok.begins_with("s"):
					base_seed = int(tok.substr(1))
				elif tok.begins_with("w"):
					# `w30` = 0.30。★ 必须能调：`nn_weight=1` 是"完全用网络排序替换磐石排序"，
					# 而磐石的 `_root_score` 是长期调过的复合启发式 —— 两者的**最优混合比**
					# 是个经验问题，不是"接上就该用满"。实测 pw30 下全开是 4:0 全败。
					nn_w = float(tok.substr(1)) / 100.0
				else:
					# 未知 token 硬报错：静默吃掉的参数会印出"看起来正常"的结果（同 --xgduel）
					print("[yemaduel] ✗ 未知 token：「%s」（支持 rN/pwN/sN/wN）" % tok)
					get_tree().quit(1)
					return
	if pw_lim <= 0 or rounds <= 0:
		print("[yemaduel] ✗ 参数非法：pw=%d rounds=%d" % [pw_lim, rounds])
		get_tree().quit(1)
		return
	var komi_bak: float = komi
	komi = 0.0
	var quiet_bak: bool = _quiet_place
	_quiet_place = true
	var on_wins := 0
	var off_wins := 0
	var draws := 0
	# 两侧的**名字**：模式不同时标签必须跟着变，否则报告会印成"开NN vs 关NN"而实际是两个 checkpoint
	# 对打 —— 读数的人会按错的口径解释（§118 换量纲必须同时改名）。
	var on_tag := "A(开NN)"
	var off_tag := "关NN"
	var b_note := ""
	if nn_b_path != "":
		on_tag = "A(线上权重)"
		off_tag = "B(第二份权重)"
		b_note = " | B 权重=%s" % nn_b_path
	var on_cap_sum := 0            # 开NN方**被提子数**合计（结构量，越小越好）
	var off_cap_sum := 0
	var illegal_all := 0
	var detail: Array[String] = []
	var t0: int = Time.get_ticks_usec()
	var gi := 0
	print("[yemaduel] 盘=%s 格数=%d | %s vs %s (nn_weight=%.2f) | pw=%d 单线程 komi=0 | %d 轮（每轮 2 局换色）%s"
		% [_bt_name(GameConfig.board_type), tiles.size(), on_tag, off_tag, nn_w, pw_lim, rounds,
			b_note])
	for _r in rounds:
		for flip in 2:
			var on_is_black: bool = (flip == 0)
			var seed_i: int = base_seed + gi * 97
			gi += 1
			game_mode = LOCAL
			reset_game(true)
			# 两个实例只差一个开关：`nn_enabled`。其余（pw/线程/根宽/种子）逐项相同，
			# 否则测的就不是"网络有没有用"而是"配置差"（§119：参照物不许动被测参数，
			# 反过来也成立 —— 参照物与被测物除了被测参数之外必须逐项相同）。
			var e_on := YemaAI.new()
			e_on.setup(adjacency, Stone.WHITE if on_is_black else Stone.BLACK, seed_i)
			e_on.time_budget_ms = 60000
			e_on.threads = 1
			e_on.root_width = 12
			e_on.nn_weight = nn_w
			e_on._apply_search_params()
			e_on.inner.max_playouts = pw_lim
			var e_off := YemaAI.new()
			# ★ `weights_path` 必须在 `setup()` **之前**设：setup 里就把权重 load 了。
			if nn_b_path != "":
				e_off.weights_path = nn_b_path
			e_off.setup(adjacency, Stone.BLACK if on_is_black else Stone.WHITE, seed_i)
			# 给了第二份权重 ⇒ 这一侧也开网络（只差权重本身）；没给 ⇒ 老行为：关网络。
			e_off.nn_enabled = (nn_b_path != "")
			e_off.time_budget_ms = 60000
			e_off.threads = 1
			e_off.root_width = 12
			if nn_b_path != "":
				# 两侧 `nn_weight` 必须相同：否则测的就是"混合比差"而不是"权重差"（§119）
				e_off.nn_weight = nn_w
			e_off._apply_search_params()
			e_off.inner.max_playouts = pw_lim
			# ★ 硬失败：权重没加载成功时 `YemaAI` 会**静默**退化成"磐石"（ext_prior 空），
			#   于是一场"两个 checkpoint 对打"实际测的是"磐石 vs 磐石"，而报告照样印胜率。
			#   ⇒ 只要有一侧网络没就绪就直接判失败，不许出数（§106 有效分母为 0 须报红）。
			if not e_on.nn_ready or (nn_b_path != "" and not e_off.nn_ready):
				print("[yemaduel] ✗ 网络未就绪：A ready=%s err=%s｜B ready=%s err=%s"
					% [str(e_on.nn_ready), e_on.nn_error, str(e_off.nn_ready), e_off.nn_error])
				print("[yemaduel] ⇒ 这样打出来的是「磐石 vs 磐石」，没有分辨力 ⇒ 判失败，不出数")
				komi = komi_bak
				_quiet_place = quiet_bak
				get_tree().quit(1)
				return
			var passes := 0
			var moves := 0
			var illegal := 0
			while passes < 2 and moves < max_moves:
				var turn_color: int = current_player
				var on_turn: bool = (turn_color == Stone.BLACK) == on_is_black
				var mv := -1
				if on_turn:
					mv = e_on.choose_move(board, ko_point, turn_color)
				else:
					mv = e_off.choose_move(board, ko_point, turn_color)
				if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
					if mv >= 0:
						illegal += 1
					passes += 1
				elif place_stone(mv, false):
					moves += 1
					passes = 0
				else:
					illegal += 1
					passes += 1
				if current_player == turn_color:   # 停一手/被拒不换行棋方 → 手动交换（同 --xgduel）
					current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			var pb: int = int(sc.get("total_black", 0))
			var pw_score: int = int(sc.get("total_white", 0))
			var on_total: int = pw_score if on_is_black else pb
			var off_total: int = pb if on_is_black else pw_score
			# 结构量：**己方被提子数**。`black_prisoners` = 黑提掉的（= 白被提），反之亦然。
			var on_cap: int = white_prisoners if on_is_black else black_prisoners
			var off_cap: int = black_prisoners if on_is_black else white_prisoners
			on_cap_sum += on_cap
			off_cap_sum += off_cap
			illegal_all += illegal
			var winner := "和"
			if on_total > off_total:
				on_wins += 1
				winner = on_tag
			elif off_total > on_total:
				off_wins += 1
				winner = off_tag
			else:
				draws += 1
			detail.append("%d手 开%d:%d关 被提%d:%d" % [moves, on_total, off_total, on_cap, off_cap])
			print("[yemaduel] 局 %d 黑=%s → %s %d : %s %d 胜=%s | 手数=%d 非法=%d | 被提 开%d:关%d"
				% [gi, on_tag if on_is_black else off_tag, on_tag, on_total, off_tag, off_total,
					winner, moves, illegal, on_cap, off_cap])
	komi = komi_bak
	_quiet_place = quiet_bak
	var n_dec: int = on_wins + off_wins
	print("[yemaduel] 总账：%s %d 胜 / %s %d 胜 / 和 %d（%d 局换色）"
		% [on_tag, on_wins, off_tag, off_wins, draws, gi])
	print("[yemaduel] ★ 结构量·平均被提子数：%s %.2f / %s %.2f（差 %+.2f；**负 = A 更少被提 = 更好**）"
		% [on_tag, float(on_cap_sum) / float(maxi(gi, 1)), off_tag,
			float(off_cap_sum) / float(maxi(gi, 1)),
			(float(on_cap_sum) - float(off_cap_sum)) / float(maxi(gi, 1))])
	if n_dec > 0:
		var z: float = (float(on_wins) - float(n_dec) * 0.5) / sqrt(float(n_dec) * 0.25)
		print("[yemaduel] 符号检验（只算分出胜负的 %d 局）：%s 胜率 %.1f%% · z=%+.2f%s"
			% [n_dec, on_tag, 100.0 * float(on_wins) / float(n_dec), z,
				"（|z|≥1.96 才算有意差；不到就写「未定」，不许拿胜率当结论）"
					if absf(z) < 1.96 else " ← 显著"])
	print("[yemaduel] 非法着法 %d 次%s" % [
		illegal_all, "（=0 ⇒ 双方着法全合法）" if illegal_all == 0 else "  ⚠️ >0 ⇒ 数据要打折看"])
	print("[yemaduel] 明细 %s" % [str(detail)])
	print("[yemaduel] 耗时 %.1fs" % [float(Time.get_ticks_usec() - t0) / 1000000.0])
	get_tree().quit()


## 仪器（--aiscale，2026-10-24）：**棋力-预算曲线** —— 同一引擎，两边只差 `max_playouts`。
##
## ★★ 为什么先做这个测量，而不是先去训网络：
##   终局目标是"人类无法战胜"。这个目标有两条成本完全不同的路径：
##     (a) **算力换棋力**：pw / 时间上去，棋力跟着上去 ⇒ 不需要重训网络，只需要把预算
##         开大 + 把「AI 时间预算」做成难度档；
##     (b) **质量换棋力**：pw 加上去已经饱和（多给 2.5 倍模拟，胜率一动不动）⇒
##         多给算力毫无意义，唯一出路是改先验/搜索结构，**自训练才轮得到**。
##   不先测这一条就谈自训练 = 不知道自己补的是哪一段。
##
## ★ 口径（同 `--yemaduel`）：**单线程 + 固定 pw + 固定 seed**，时间预算设兜底值
##   ⇒ `max_playouts` 是唯一停止条件 ⇒ 可复现、能按同局读配对。
##   两边**只差 pw**，其余（种子/根宽/线程）逐项相同（§119）。
##
## ★ 元判据（这条决定数据有没有意义）：B 侧每手平均耗时必须明显大于 A 侧
##   （期望 ≈ pw 比）。若耗时比 < 1.3 ⇒ `max_playouts` 根本没起作用、两边其实在算同一件事
##   ⇒ **本轮数据作废**（§96：exit=0 ≠ 跑到了）。
##
## 用法：`--aiscale`（默认 A=pw60 vs B=pw150，3 轮 = 6 局）
##      `--aiscale=pa60:pb400:r3:s20261024`
func _ai_scale_probe() -> void:
	var rounds := 3
	var pw_a := 60
	var pw_b := 150
	var base_seed := 20261024
	var max_moves := 260
	var es_off := false            # true = 关掉「显然手早停」（否则大预算会被它截断）
	for a in _argv():
		if a.begins_with("--aiscale="):
			# ⚠️ 偏移是 **10**（`--` + `aiscale`(7) + `=`），不是 11 —— 差一位会把首个
			#   token 的第一个字符吃掉（`r1` → `1`），实测就是这么报的「未知 token」。
			for tok in a.substr(10).split(":"):
				if tok.begins_with("pa"):
					pw_a = int(tok.substr(2))
				elif tok.begins_with("pb"):
					pw_b = int(tok.substr(2))
				elif tok == "es0":
					# ★★ 为什么需要这个开关：`obvious_early_stop` 默认开着，条件之一是
					#   「访问数 ≥ `obvious_min_visits`(80) 且第一名明显领先」⇒ 预算给到
					#   pw300 时会被它**提前截断**。实测（`pa60:pb300`）B 侧每手耗时只有
					#   A 的 2.92 倍（期望 5.00）⇒ 那一轮测的根本不是"5 倍算力"。
					#   ⇒ 测「预算的边际收益」必须关掉它；测「用户调大时间预算实际能得到
					#     什么」则要保留（那是真实对局配置）。两种口径都要跑。
					es_off = true
				elif tok.begins_with("r"):
					rounds = int(tok.substr(1))
				elif tok.begins_with("s"):
					base_seed = int(tok.substr(1))
				else:
					# 未知 token 硬报错：静默吃掉参数会印出"看起来正常"的结果
					print("[aiscale] ✗ 未知 token：「%s」（支持 rN/paN/pbN/sN）" % tok)
					get_tree().quit(1)
					return
	if pw_a <= 0 or pw_b <= 0 or pw_a == pw_b or rounds <= 0:
		print("[aiscale] ✗ 参数非法：pa=%d pb=%d rounds=%d（pa 与 pb 必须不同）" % [pw_a, pw_b, rounds])
		get_tree().quit(1)
		return
	var komi_bak: float = komi
	komi = 0.0
	var quiet_bak: bool = _quiet_place
	_quiet_place = true
	var a_wins := 0
	var b_wins := 0
	var draws := 0
	var diff_sum := 0                 # B 方目数 − A 方目数（正 = B 领先）
	var ms_a_sum := 0
	var ms_b_sum := 0
	var na_sum := 0
	var nb_sum := 0
	var illegal_all := 0
	var detail: Array[String] = []
	var t0: int = Time.get_ticks_usec()
	var gi := 0
	print("[aiscale] 盘=%s 格数=%d | A(pw%d) vs B(pw%d)｜单线程 komi=0 | %d 轮（每轮 2 局换色）"
		% [_bt_name(GameConfig.board_type), tiles.size(), pw_a, pw_b, rounds])
	for _r in rounds:
		for flip in 2:
			var b_is_black: bool = (flip == 0)
			var seed_i: int = base_seed + gi * 97
			gi += 1
			game_mode = LOCAL
			reset_game(true)
			var ea := AIEngine.new()
			ea.setup(adjacency, Stone.WHITE if b_is_black else Stone.BLACK, seed_i)
			ea.threads = 1
			ea.time_budget_ms = 600000      # 兜底，永不到
			ea.max_playouts = pw_a
			ea.root_width = 12
			if es_off:
				ea.obvious_early_stop = false
			var eb := AIEngine.new()
			eb.setup(adjacency, Stone.BLACK if b_is_black else Stone.WHITE, seed_i)
			eb.threads = 1
			eb.time_budget_ms = 600000
			eb.max_playouts = pw_b
			eb.root_width = 12
			if es_off:
				eb.obvious_early_stop = false
			var passes := 0
			var moves := 0
			var illegal := 0
			while passes < 2 and moves < max_moves:
				var turn_color: int = current_player
				var b_turn: bool = (turn_color == Stone.BLACK) == b_is_black
				var mv := -1
				if b_turn:
					mv = eb.choose_move(board, ko_point, turn_color)
					ms_b_sum += eb.last_ms
					nb_sum += 1
				else:
					mv = ea.choose_move(board, ko_point, turn_color)
					ms_a_sum += ea.last_ms
					na_sum += 1
				if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
					if mv >= 0:
						illegal += 1
					passes += 1
				elif place_stone(mv, false):
					moves += 1
					passes = 0
				else:
					illegal += 1
					passes += 1
				if current_player == turn_color:   # 停一手/被拒不换行棋方 → 手动交换（同 --xgduel）
					current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			var pb_s: int = int(sc.get("total_black", 0))
			var pw_s: int = int(sc.get("total_white", 0))
			var b_total: int = pw_s if b_is_black else pb_s
			var a_total: int = pb_s if b_is_black else pw_s
			diff_sum += b_total - a_total
			illegal_all += illegal
			var winner := "和"
			if b_total > a_total:
				b_wins += 1
				winner = "B"
			elif a_total > b_total:
				a_wins += 1
				winner = "A"
			else:
				draws += 1
			detail.append("%d手 %d:%d 胜=%s" % [moves, a_total, b_total, winner])
			print("[aiscale] 局 %d 黑=%s → A %d : B %d 胜=%s | 手数=%d 非法=%d"
				% [gi, "B" if b_is_black else "A", a_total, b_total, winner, moves, illegal])
	komi = komi_bak
	_quiet_place = quiet_bak
	var per_a: float = float(ms_a_sum) / float(maxi(na_sum, 1))
	var per_b: float = float(ms_b_sum) / float(maxi(nb_sum, 1))
	var ratio: float = per_b / maxf(per_a, 0.001)
	var expect: float = float(pw_b) / float(pw_a)
	print("[aiscale] 总账：A(pw%d) %d 胜 / B(pw%d) %d 胜 / 和 %d（%d 局换色）"
		% [pw_a, a_wins, pw_b, b_wins, draws, gi])
	print("[aiscale] 目差：B − A 合计 %+d 均值 %+.1f（正 = 多算那边领先）"
		% [diff_sum, float(diff_sum) / float(maxi(gi, 1))])
	print("[aiscale] 每手平均耗时：A %.0fms / B %.0fms ⇒ 比 %.2f（期望 ≈ pw 比 %.2f）"
		% [per_a, per_b, ratio, expect])
	var n_dec: int = a_wins + b_wins
	if n_dec > 0:
		var z: float = (float(b_wins) - float(n_dec) * 0.5) / sqrt(float(n_dec) * 0.25)
		print("[aiscale] 符号检验（只算分胜负的 %d 局）：B 胜率 %.1f%% · z=%+.2f%s"
			% [n_dec, 100.0 * float(b_wins) / float(n_dec), z,
				"（|z|≥1.96 才算有意差；不到就写「未定」）" if absf(z) < 1.96 else " ← 显著"])
	# ★★ 元判据：没真的多算 ⇒ 数据无意义，不许当"预算没用"的证据。
	#   ⚠️ 界必须**挂在期望的 pw 比上**（`expect`），不能写死一个绝对数 ——
	#   本仪器第一版写死 `ratio < 1.3`，于是 `pa60:pb300` 那轮（实际只跑到期望的 58%，
	#   被 `obvious_early_stop` 截断）**照样通过**，把"没测到的东西"当成"测过了"。
	#   （§121 同族：换了物理量，界就得跟着这个量重算。）
	if ratio < expect * 0.8:
		print("[aiscale] ✗ 元判据失败：实际耗时只到期望的 %.0f%%（比 %.2f / 期望 %.2f）"
			% [100.0 * ratio / maxf(expect, 0.001), ratio, expect]
			+ " ⇒ 预算没真正生效（多半是 `obvious_early_stop` 提前截断）"
			+ " ⇒ **本轮数据作废**，不能据此说「预算无用」。重跑请加 `es0`。")
	print("[aiscale] 非法着法 %d 次%s" % [
		illegal_all, "（=0 ⇒ 双方着法全合法）" if illegal_all == 0 else "  ⚠️ >0 ⇒ 数据要打折看"])
	print("[aiscale] 明细 %s" % [str(detail)])
	print("[aiscale] 耗时 %.1fs" % [float(Time.get_ticks_usec() - t0) / 1000000.0])
	get_tree().quit()


# ----------------------------------------------------------------------------
# 仪器（--aispec，2026-10-27）：**任意引擎参数** A vs B 配对换色自弈（可复现、可按同局配对读）
# ----------------------------------------------------------------------------
## 用法：`--aispec=r6:pw100:a=max_playout_moves=40:b=max_playout_moves=120:es0`
##   rN 轮数（每轮 2 局换色）｜pwN 每手 playouts（两侧同值，除非在 `a=`/`b=` 里覆盖）
##   a=<k=v,k=v> / b=<k=v,k=v>：覆盖键 = `AIEngine` 的属性名，逗号分隔；两侧互不干扰
##   sN 基础种子（默认 20261027）｜es0 = 关「显然手早停」（大预算会被它截断）
##
## ★ 为什么需要它（`--aiscale` 与 `--aiablate` 都不够）：
##   `--aiscale` 只会扫 `max_playouts`；`--aiablate` 的组是**写死在源码里**的。
##   而「换叶子价值口径」这一类改动全落在别的属性上（`eval_mix_lambda` /
##   `max_playout_moves` / `prior_visits` / `root_width` / `c_puct` / `pick_lcb_stdevs`…）。
##   没有通用入口 ⇒ 每试一个旋钮就要改一次源码，改完还得记住拨回去
##   （§120：拨回初版要钉住每个参与读取的参数 —— 靠人记必然漏）。
##
## ★★ 三道硬闸（本仪器的主要风险恰恰是"看起来跑通了"）：
##   ① 覆盖键必须是**真实存在的属性**。GDScript 的 `set()` 对不存在的键**静默无效**
##      ⇒ 打错一个字母就变成「A 打 A」，而报告照样印出漂亮的胜负（§113 同族）。
##      这里对实例 `get(k)` 取现值，取不到就直接退出。
##   ② 值的**类型必须与现有属性同类型**。`eval_mix_lambda` 是 float，写成 `=1` 会被
##      `set()` 隐式转换、语义悄悄漂移 ⇒ 类型不符也退出，并提示该写成 `1.0`。
##   ③ `a=` 与 `b=` 字面相同 ⇒ 测的是自己打自己 ⇒ **直接拒**（不是警告，是退出）。
##
## ★ 可复现三件套（照抄 `--yemaduel` / `--aiscale`）：固定种子 + 固定 pw + 单线程。
##   时间预算设成兜底值 ⇒ `max_playouts` 是唯一停止条件 ⇒ 能按同局配对读（§125）。
##   两侧共用同一个 `seed_i`：共同随机流 = 共同随机数（CRN），配对方差更小。
func _ai_spec_probe() -> void:
	var rounds := 6
	var pw := 100
	var base_seed := 20261027
	var max_moves := 260
	var es_off := false
	var sk_on := false          # `sk` token：打开位置超级劫（见 `_superko_enforce`）
	## ★ 生产保真：`tN` 线程数（默认 1 = 历史口径）、`tbN` 时间预算毫秒（0 = 不用，历史口径）
	var threads_ov := 1
	var tb_ms := 0
	var raw_a := ""
	var raw_b := ""
	for a in _argv():
		if a.begins_with("--aispec="):
			# 偏移 = 9（`--`(2) + `aispec`(6) + `=`(1)）。差一位会把首个 token 的首字符
			# 吃掉（`--aiscale` 就在这上面踩过：`r1` → `1` ⇒ 报"未知 token"）。
			for tok in a.substr(9).split(":"):
				if tok.begins_with("a="):
					raw_a = tok.substr(2)
				elif tok.begins_with("b="):
					raw_b = tok.substr(2)
				elif tok.begins_with("pw"):
					pw = int(tok.substr(2))
				elif tok == "es0":
					es_off = true
				elif tok == "sk":
					# ★ 2026-10-27：打开**位置超级劫**（默认关，见 `_superko_enforce` 声明处）。
					#   不打开 = 沿用历史口径（无超级劫），两侧同规则 ⇒ 胜负比较仍有效，
					#   但**比分分布不真实**：120 格盘能跑到 200+ 分（反复投子被反复提）。
					#   凡要读「崩盘率 / 目差分布」的实验，必须带 sk。
					sk_on = true
				elif tok.begins_with("tb"):
					# ★ 2026-10-27 生产保真：用**时间预算**代替固定模拟数（不可逐位复现，见 §125）
					tb_ms = maxi(int(tok.substr(2)), 0)
				elif tok.begins_with("t"):
					# ★ `t0` = **按核数自动**（上限 8），这正是生产配置（`GameConfig.ai_threads` 默认 0）；
					#   `t1` = 单线程（历史 A/B 口径）；`tN` = 固定 N 线程。
					#   不许把下界夹成 1：夹了以后 `t0` 和 `t1` 同义，生产口径就永远测不到。
					threads_ov = maxi(int(tok.substr(1)), 0)
				elif tok.begins_with("r"):
					rounds = int(tok.substr(1))
				elif tok.begins_with("s"):
					base_seed = int(tok.substr(1))
				else:
					print("[aispec] ✗ 未知 token：「%s」（支持 rN/pwN/tbN/tN/a=…/b=…/sN/es0/sk）" % tok)
					get_tree().quit(1)
					return
	if raw_a == "" or raw_b == "":
		print("[aispec] ✗ 必须同时给 a=<覆盖> 与 b=<覆盖>（缺一方就不知道在比什么）")
		get_tree().quit(1)
		return
	if raw_a == raw_b:
		print("[aispec] ✗ a 与 b 字面相同（「%s」）⇒ 这是自己打自己，有效分母为 0 ⇒ 拒绝出数" % raw_a)
		get_tree().quit(1)
		return
	if pw <= 0 or rounds <= 0:
		print("[aispec] ✗ 参数非法：pw=%d rounds=%d" % [pw, rounds])
		get_tree().quit(1)
		return
	var probe_e := AIEngine.new()
	var errs: Array[String] = []
	var ov_a := _ai_spec_parse(probe_e, raw_a, "A", errs)
	var ov_b := _ai_spec_parse(probe_e, raw_b, "B", errs)
	if errs.size() > 0:
		for msg in errs:
			print("[aispec] ✗ %s" % msg)
		print("[aispec] ⇒ 覆盖没生效 / 只生效一半的数据一律不许读（那会变成「A 打 A 却印出胜负」）")
		get_tree().quit(1)
		return
	var komi_bak: float = komi
	komi = 0.0
	var quiet_bak: bool = _quiet_place
	var sk_bak: bool = _superko_enforce
	_quiet_place = true
	# ★ 2026-10-27：`_quiet_place` 原来**顺带关掉了位置超级劫**（`place_stone` 的关口是
	#   `if not _quiet_place and ...`）⇒ 历史所有 `--aispec` 数据都跑在「无超级劫」规则下。
	#   现在拆开了：默认 `sk_on=false` 沿用历史口径（与老日志可逐位对照），带 `sk` token 才开。
	_superko_enforce = sk_on
	var a_wins := 0
	var b_wins := 0
	var draws := 0
	var diff_sum := 0
	var ms_a := 0
	var ms_b := 0
	var na := 0
	var nb := 0
	var illegal_all := 0
	var detail: Array[String] = []
	var t0: int = Time.get_ticks_usec()
	var gi := 0
	print("[aispec] 盘=%s 格数=%d | A{%s} vs B{%s} | 停止=%s 线程=%s komi=0 早停=%s 超级劫=%s | %d 轮（每轮 2 局换色）"
		% [_bt_name(GameConfig.board_type), tiles.size(), _ai_spec_desc(ov_a),
			_ai_spec_desc(ov_b),
			("tb%dms（★ 不可逐位复现，§125）" % tb_ms) if tb_ms > 0 else ("pw=%d" % pw),
			("自动(生产)" if threads_ov == 0 else str(threads_ov)), "关" if es_off else "开",
			"开(sk)" if sk_on else "关(历史口径)", rounds])
	for _r in rounds:
		for flip in 2:
			var b_is_black: bool = (flip == 0)
			var seed_i: int = base_seed + gi * 97
			gi += 1
			game_mode = LOCAL
			reset_game(true)
			var ea := AIEngine.new()
			ea.setup(adjacency, Stone.WHITE if b_is_black else Stone.BLACK, seed_i)
			ea.threads = threads_ov
			ea.time_budget_ms = (tb_ms if tb_ms > 0 else 600000)      # 兜底，永不到 ⇒ max_playouts 是唯一停止条件
			ea.root_width = 12
			ea.max_playouts = (1000000 if tb_ms > 0 else pw)
			if es_off:
				ea.obvious_early_stop = false
			# 覆盖**放在基础赋值之后**：a=/b= 里的同名键必须能压过上面的默认值
			for k in ov_a.keys():
				ea.set(k, ov_a[k])
			var eb := AIEngine.new()
			eb.setup(adjacency, Stone.BLACK if b_is_black else Stone.WHITE, seed_i)
			eb.threads = threads_ov
			eb.time_budget_ms = (tb_ms if tb_ms > 0 else 600000)
			eb.root_width = 12
			eb.max_playouts = (1000000 if tb_ms > 0 else pw)
			if es_off:
				eb.obvious_early_stop = false
			for k in ov_b.keys():
				eb.set(k, ov_b[k])
			var passes := 0
			var moves := 0
			var illegal := 0
			while passes < 2 and moves < max_moves:
				var turn_color: int = current_player
				var b_turn: bool = (turn_color == Stone.BLACK) == b_is_black
				var mv := -1
				if b_turn:
					mv = eb.choose_move(board, ko_point, turn_color)
					ms_b += eb.last_ms
					nb += 1
				else:
					mv = ea.choose_move(board, ko_point, turn_color)
					ms_a += ea.last_ms
					na += 1
				if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
					if mv >= 0:
						illegal += 1
					passes += 1
				elif place_stone(mv, false):
					moves += 1
					passes = 0
				else:
					illegal += 1
					passes += 1
				if current_player == turn_color:   # 停一手/被拒不换行棋方 → 手动交换（同 --aiscale）
					current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			var pb_s: int = int(sc.get("total_black", 0))
			var pw_s: int = int(sc.get("total_white", 0))
			var b_total: int = pw_s if b_is_black else pb_s
			var a_total: int = pb_s if b_is_black else pw_s
			diff_sum += b_total - a_total
			illegal_all += illegal
			var winner := "和"
			if b_total > a_total:
				b_wins += 1
				winner = "B"
			elif a_total > b_total:
				a_wins += 1
				winner = "A"
			else:
				draws += 1
			detail.append("%d手 %d:%d 胜=%s" % [moves, a_total, b_total, winner])
			print("[aispec] 局 %d 黑=%s → A %d : B %d 胜=%s | 手数=%d 非法=%d"
				% [gi, "B" if b_is_black else "A", a_total, b_total, winner, moves, illegal])
	komi = komi_bak
	_quiet_place = quiet_bak
	_superko_enforce = sk_bak
	# ★ 存在的判据（§138 对照组）：`superko=开` 必须**看得见历史表在长**。
	#   `=1` 意味着历史表只有初始局面 ⇒ 超级劫实际是空操作（曾经就是：
	#   `rules_kernel._superko_commit()` 被 `_quiet_place` 早退 ⇒ 表从不写入）。
	#   所以这条数不印出来，"开了 sk 却没效果"和"开了 sk 但超级劫真没触发过"无法区分。
	print("[aispec] superko 历史条目=%d（≤1 ⇒ 没在记，`sk` 是空操作；仅 `sk` 模式有意义）"
		% [_superko_hist.size()])
	print("[aispec] 总账：A %d 胜 / B %d 胜 / 和 %d（%d 局换色）" % [a_wins, b_wins, draws, gi])
	print("[aispec] 目差：B − A 合计 %+d 均值 %+.1f（正 = B 领先）"
		% [diff_sum, float(diff_sum) / float(maxi(gi, 1))])
	print("[aispec] 每手平均耗时：A %.0fms / B %.0fms（比 %.2f）"
		% [float(ms_a) / float(maxi(na, 1)), float(ms_b) / float(maxi(nb, 1)),
			float(ms_b) / float(maxi(ms_a, 1))])
	var n_dec: int = a_wins + b_wins
	if n_dec > 0:
		var z: float = (float(b_wins) - float(n_dec) * 0.5) / sqrt(float(n_dec) * 0.25)
		print("[aispec] 符号检验（只看分出胜负的 %d 局）：B 胜率 %.1f%% · z=%+.2f%s"
			% [n_dec, 100.0 * float(b_wins) / float(n_dec), z,
				" ← 显著" if absf(z) >= 1.96 else "（|z|<1.96 ⇒ 未定，不许当结论）"])
	else:
		print("[aispec] ✗ 有效分母为 0：一局都没分出胜负 ⇒ 本轮无分辨力")
	print("[aispec] 非法着法 %d 次%s" % [
		illegal_all, "（=0 ⇒ 双方着法全合法）" if illegal_all == 0 else "  ⚠️ >0 ⇒ 数据要打折看"])
	print("[aispec] 明细 %s" % [str(detail)])
	print("[aispec] 耗时 %.1fs" % [float(Time.get_ticks_usec() - t0) / 1000000.0])
	get_tree().quit()


## `--aispec` 用：把 `k=v,k=v` 解析成**类型化**覆盖字典。
## 错误一律收进 `errs`、不在这里退出 —— 让调用方**一次性**把全部问题印出来再判失败。
## 半截生效的 spec 是最难查的一种（报告看起来正常），所以宁可一条都不生效。
func _ai_spec_parse(e: AIEngine, raw: String, tag: String, errs: Array[String]) -> Dictionary:
	var out := {}
	for kv in raw.split(",", false):
		var parts: PackedStringArray = kv.split("=")
		if parts.size() != 2:
			errs.append("%s「%s」不是 k=v 形式" % [tag, kv])
			continue
		var k: String = parts[0].strip_edges()
		var vs: String = parts[1].strip_edges()
		var cur: Variant = e.get(k)
		if cur == null:
			# ★ 这一条是核心：`set("拼错的键", x)` 不会报错、什么也不做 ⇒
			#   两侧覆盖同时失效 ⇒ 变成「A 打 A」，而报告照样印胜负。
			errs.append("%s 覆盖键「%s」在 AIEngine 上不存在（拼错会被 set() 静默忽略）" % [tag, k])
			continue
		var want: int = typeof(cur)
		var v: Variant = null
		if vs == "true" or vs == "false":
			v = (vs == "true")
		elif vs.contains(".") or vs.contains("e") or vs.contains("E"):
			v = float(vs)
		else:
			v = int(vs)
		if typeof(v) != want:
			errs.append("%s「%s」类型不符：属性是 %s，写的是 %s（float 要写成 1.0，别写 1）"
				% [tag, k, type_string(want), type_string(typeof(v))])
			continue
		out[k] = v
	return out


## `--aispec` 用：把覆盖字典印成人读形式（空 = 默认参数）
func _ai_spec_desc(ov: Dictionary) -> String:
	if ov.is_empty():
		return "默认"
	var parts: Array[String] = []
	for k in ov.keys():
		parts.append("%s=%s" % [k, str(ov[k])])
	return ",".join(parts)


# ----------------------------------------------------------------------------
# 仪器（--selfplay，2026-10-24）：**自对弈数据工厂**（AlphaZero 式）
# ----------------------------------------------------------------------------
## 用法：`--selfplay=g=4:pw=50:s=20261024:tau0=30:tau=1.0`
##   gN 局数｜pwN 每手 playouts｜sN 基础种子｜tau0N 前几手用高温｜tauX 高温值
##   maxN 手数上限｜gid0N 对局号起点（**分段生成时必须传**，否则跨文件 gid 撞车）
##   thrN 搜索线程数（默认 1；自对弈不需要严格可复现，开多线程能线性提速）
##   bt=<盘型>（penrose/cube/kite/snow/hat，默认 penrose）
##
## ★★ 与 `--aigraph` 的分工（两件事，别混）：
##   `--aigraph`  = **教师蒸馏**：低预算学生 + 高预算教师，标签是教师**选中的那一个点**（argmax）。
##   `--selfplay` = **自我提升**：一方自己的搜索既是落子依据、也是标签；标签是**完整访问
##     分布**，另加终局胜负当 value。MCTS 分布天生强于原始策略（搜索比 2449 参数的网络强），
##     所以"学自己的搜索"这一循环本身带增益，不需要外部教师。
##
## ★ 为什么现在做（三条实测同时成立才该做，缺一条都别做）：
##   ① `--aiscale`：pw60 vs pw300 = 2:2（z=0.00）、pw60 vs pw240 = 1:3（z=+1.00）
##      ⇒ **算力换棋力已饱和**。（⚠️ n=4 无分辨力，要断言饱和须补到 16 局，先记着）
##   ② `--yemaduel` v2：开 NN 18.8%、z=−2.50 ⇒ 现有 argmax 蒸馏出来的先验是**负资产**。
##   ③ 同特征线性基线 22.95% vs 网络 38.03% ⇒ 信息确实在局面里，是 argmax 标签把分布形状丢光了。
##   ⇒ 唯一剩下的方向：让**标签携带更多信息**，而不是让搜索更久。
##
## ★ 访问数口径（最容易错的一处）：`last_root_visits` 含 `prior_visits` 的虚拟注入
##   （单线程 envs=1 ⇒ 每候选一律 +prior_visits≈10.6）。**导出前必须扣**：pw=50 时每候选
##   真实访问只几次，+10.6 的常数会把标签拉成近似均匀 ⇒ 训出来等于没学，而报告照样好看。
##
## ★ 采样落子（AlphaZero 标准做法，别改成 argmax）：前 `tau0` 手按 `visits^(1/tau)` 采样，
##   之后降到 tau=0.25 转贪。全程 argmax 会让每局棋谱高度相似 ⇒ 数据多样性塌掉，
##   这是自对弈最常见的静默失败（指标全绿、模型没长进）。
##   ⚠️ 采样 RNG **独立**于引擎 rng，否则污染引擎可复现性（同 `--yemaduel` 三件套）。
##
## ★ 成本（**首跑必须自己实测，别信这行注释**）：按 `--yemaduel`（pw=50、16 局、479s）
##   反推约 4.6ms/playout ⇒ 一局 ≈ 130 手 × pw × 4.6ms。pw=50 → ~30s/局，pw=200 → ~120s/局。
##   先 `g=1` 量真实速度，再按可用时间倒推规模。
##
## 【输出】stdout，`SP,` 前缀：
##   SP,H,1,<盘型数>,<口径>
##   SP,T,<tid>,<盘型名>,<n>,<边数>,<直方图>,<u0>,<v0>,...   ← 拓扑（`_topo_line()` 真源）
##   SP,S,<gid>,<tid>,<ply>,<color>,<ko>,<state>             ← 局面，state 逐点 0/1/2
##   SP,V,<gid>,<ply>,<k>,<mv0>,<v0>,<mv1>,<v1>,...          ← 访问分布（**已扣注入**）
##   SP,Q,<gid>,<ply>,<k>,<mv0>,<q0>,<mv1>,<q1>,...          ← 每候选真实 Q ∈[0,1]（与 V 同序同批）
##   SP,X,<gid>,<ply>,<原因>                                 ← 这一手无可用标签（有效分母）
##   SP,G,<gid>,<tid>,<winner>,<tb>,<tw>,<moves>             ← 终局（value 标签）
##   ⚠️ S 与 V 成对：消费侧读到 S 就等 V，不靠行序猜（同 aigraph 的 S/L 对）。
func _selfplay_probe() -> void:
	var games := 4
	var pw_lim := 50
	var base_seed := 20261024
	var tau0 := 30
	var tau_hi := 1.0
	var tau_lo := 0.25
	var max_moves := 260
	var gid0 := 0
	# ★ 自对弈**不需要**严格可复现（数据多样性反而更好），所以可以开多线程提速。
	#   对比 `--yemaduel` 必须单线程：那是配对判据，复现性优先。
	var threads := 1
	var bt: int = GameConfig.BOARD_PENROSE
	# `--selfplay=` = 11 个字符（`--` 2 + `selfplay` 8 + `=` 1）。
	# ⚠ 长度是硬编码字面量，差一位就静默吃掉首 token 的首字符（§109，`--aiscale` 踩过一次）。
	for a in _argv():
		if not a.begins_with("--selfplay="):
			continue
		for tok in a.substr(11).split(":", false):
			var pr := tok.split("=")
			var k: String = str(pr[0])
			var val: String = "" if pr.size() < 2 else str(pr[1])
			if k == "g":
				games = int(val)
			elif k == "pw":
				pw_lim = int(val)
			elif k == "s":
				base_seed = int(val)
			elif k == "tau0":
				tau0 = int(val)
			elif k == "tau":
				tau_hi = float(val)
			elif k == "max":
				max_moves = int(val)
			elif k == "gid0":
				gid0 = int(val)
			elif k == "thr":
				threads = int(val)
			elif k == "bt":
				var b2: int = _aigraph_bt(val)
				if b2 < 0:
					print("[selfplay] ✗ 未知盘型「%s」（支持 penrose/cube/kite/snow/hat）" % val)
					get_tree().quit(1)
					return
				bt = b2
			else:
				print("[selfplay] ✗ 未知 token：「%s」（支持 g=/pw=/s=/tau0=/tau=/max=/gid0=/thr=/bt=）" % tok)
				get_tree().quit(1)
				return
	if games <= 0 or pw_lim <= 0:
		print("[selfplay] ✗ 参数非法：g=%d pw=%d" % [games, pw_lim])
		get_tree().quit(1)
		return

	# 本仪器**不写谱**：要跑上百局，一局一谱会把用户棋谱库灌满（同 `--aigraph`）。
	# 名字里也没有 "test" ⇒ 不走 `is_automated_run()` 的改道，必须手动静音。
	_record_muted = true
	var quiet_bak: bool = _quiet_place
	_quiet_place = true
	var komi_bak: float = komi
	komi = 0.0

	GameConfig.board_type = bt
	GameConfig.board_size = GameConfig.STANDARD
	_apply_board_size(GameConfig.STANDARD)
	_generate_selected_board()
	var n: int = tiles.size()
	# tid 绑定盘型枚举（同 aigraph）：自增计数器跨文件会撞车 ⇒ Python 侧 topo 静默覆盖。
	var tid: int = bt + 1
	print("SP,H,1,1,vfeat=visits_minus_prior;sample=visits^(1/tau);state=char012;tau0=%d;tau_lo=%.2f"
		% [tau0, tau_lo])
	print(_topo_line("SP", tid, bt))
	print("[selfplay] 盘=%s 格数=%d tid=%d | 双方同预算 pw=%d 单线程 komi=0 | %d 局 | 种子 %d"
		% [_bt_name(bt), n, tid, pw_lim, games, base_seed])

	var e_b := AIEngine.new()
	var e_w := AIEngine.new()
	for e in [e_b, e_w]:
		e.threads = maxi(threads, 1)
		e.time_budget_ms = 60000     # 真正兜底的是 max_playouts（同 --yemaduel）
		e.max_playouts = pw_lim
	var samp := RandomNumberGenerator.new()
	var t0: int = Time.get_ticks_usec()
	var n_s := 0
	var n_v := 0
	var n_x := 0
	var n_illegal := 0
	var sum_keep := 0
	var sum_vis := 0
	for gi in games:
		# ★★ gid 必须**跨分段文件全局唯一**。`split_by_game()` 按 gid 切验证集：
		#   若每段都从 1 重新编号，530 局会被看成 50 个不同对局 ⇒ 验证集里混进训练集
		#   的同 gid 对局 ⇒ 指标偏乐观，而且报告里**看不出任何异常**（同局泄漏）。
		#   `${gid0}` 由 `make_selfplay.sh` 按段起点传入。
		var gid: int = gid0 + gi + 1
		var seed_g: int = base_seed + gid * 1013
		game_mode = LOCAL
		reset_game(true)
		e_b.setup(adjacency, Stone.BLACK, seed_g)
		e_w.setup(adjacency, Stone.WHITE, seed_g + 1)
		samp.seed = seed_g + 2       # 采样 RNG 独立且每局可复现
		var passes := 0
		var moves := 0
		while passes < 2 and moves < max_moves:
			var tc: int = current_player
			var eng: AIEngine = e_b if tc == Stone.BLACK else e_w
			var mv: int = eng.choose_move(board, ko_point, tc)
			# 分布必须在 choose_move 之后**立刻**取：下一次调用会覆盖它（字段声明处有说明）。
			var cands: Array[int] = eng.last_root_cands
			var vis: PackedFloat32Array = eng.last_root_visits
			var playable: bool = not (mv < 0 or mv >= n or board[mv] != Stone.EMPTY or mv == ko_point)
			if playable:
				# ---- 标签：局面 + 访问分布（与本次实际落子的那次搜索**同源**）----
				# 注入量由引擎给（单线程 prior_visits / 多线程 W×prior_visits）——
				# 这里**不许**自己用 `eng.prior_visits` 猜，开多线程时会少扣 (W−1) 份。
				var inj: float = eng.last_root_v_inj
				# 真实 Q（[0,1]；未访问 = −1）。与访问数**同源于** `_root_real_stats()`。
				var qs: PackedFloat32Array = eng.last_root_q
				var kv: Array[String] = []
				var kq: Array[String] = []
				var sum_real := 0
				if cands.size() >= 2 and vis.size() == cands.size():
					for kk in cands.size():
						var rv: int = roundi(maxf(0.0, vis[kk] - inj))
						if rv <= 0:
							continue
						kv.append("%d" % cands[kk])
						kv.append("%d" % rv)
						kq.append("%d" % cands[kk])
						kq.append("%.3f" % (qs[kk] if kk < qs.size() else -1.0))
						sum_real += rv
				if kv.size() >= 4 and sum_real > 0:
					var st := ""
					for v in n:
						st += str(board[v])
					print("SP,S,%d,%d,%d,%d,%d,%s" % [gid, tid, moves, tc, ko_point, st])
					print("SP,V,%d,%d,%d,%s" % [gid, moves, int(kv.size() / 2), ",".join(kv)])
					# Q 行与 V 行**同序同批**（同样滤掉未访问候选）。未访问的候选不必导出：
					# 消费侧从 state 就能枚举全部空点，dist 里没出现的即为未访问
					# ⇒ completed-Q 用根值补全，不需要引擎逐点声明（省一半字节）。
					print("SP,Q,%d,%d,%d,%s" % [gid, moves, int(kq.size() / 2), ",".join(kq)])
					n_s += 1
					n_v += 1
					sum_keep += int(kv.size() / 2)
					sum_vis += sum_real
				else:
					# 有效分母为 0 的场合必须**明说**，不许静默少一行（§106）
					print("SP,X,%d,%d,cands=%d,vis=%d,sum=%d"
						% [gid, moves, cands.size(), vis.size(), sum_real])
					n_x += 1
			# ---- 落子：按分布采样（前 tau0 手高温），采不到就退回引擎选点 ----
			var tau: float = tau_hi if moves < tau0 else tau_lo
			var pick: int = _sp_sample_move(cands, vis, tau, samp)
			if pick < 0:
				pick = mv
			if pick < 0 or pick >= n or board[pick] != Stone.EMPTY or pick == ko_point:
				passes += 1
				if pick >= 0:
					n_illegal += 1
			elif place_stone(pick, false):
				moves += 1
				passes = 0
			else:
				n_illegal += 1
				passes += 1
			if current_player == tc:     # 停一手/被拒不换行棋方 → 手动交换（同 --yemaduel）
				current_player = Stone.WHITE if tc == Stone.BLACK else Stone.BLACK
		var sc: Dictionary = _compute_scores()
		var tb: int = int(sc.get("total_black", 0))
		var tw: int = int(sc.get("total_white", 0))
		var winner := 0
		if tb > tw:
			winner = 1
		elif tw > tb:
			winner = 2
		print("SP,G,%d,%d,%d,%d,%d,%d" % [gid, tid, winner, tb, tw, moves])
		print("[selfplay] 局 %d/%d %d手 黑%d:白%d 胜=%d | 累计标签 %d 条 / 无标签 %d 条"
			% [gid, games, moves, tb, tw, winner, n_s, n_x])

	komi = komi_bak
	_quiet_place = quiet_bak
	var dt: float = float(Time.get_ticks_usec() - t0) / 1000000.0
	print("[selfplay] 总账：%d 局 · 标签 %d 条 · 无标签 %d 条 · 非法 %d 次 · 耗时 %.1fs（%.1fs/局）"
		% [games, n_s, n_x, n_illegal, dt, dt / float(maxi(games, 1))])
	if n_v > 0:
		print("[selfplay] 分布统计：平均候选 %.2f 个/局面 · 平均有效访问 %.1f 次/局面"
			% [float(sum_keep) / float(n_v), float(sum_vis) / float(n_v)])
	# ★★ 元判据（§96：exit=0 ≠ 跑到了）。V 行数是整条管线的存在性判据：
	#   它是 0 就说明 `last_root_*` 出口没接上、或早退分支把快照清掉了 ⇒ 数据作废。
	if n_v == 0:
		print("[selfplay] ✗✗ 致命：一条 SP,V 都没有 ⇒ 分布出口没工作，本次数据**作废**")
		get_tree().quit(2)
		return
	if n_x > n_v:
		print("[selfplay] ⚠️ 无标签 %d 条 > 有标签 %d 条 ⇒ pw=%d 太小、分布没展开，数据要打折看"
			% [n_x, n_v, pw_lim])
	print("[selfplay] ✓ 完成")
	get_tree().quit()


## 按 `visits^(1/tau)` 采样一个**格点**；无可用候选时返 −1（调用方退回引擎选点）。
## `+1` 平滑只为避免除零，**不进入标签**（标签走 `SP,V` 的实数，见调用处）。
func _sp_sample_move(cands: Array[int], vis: PackedFloat32Array, tau: float,
		rng: RandomNumberGenerator) -> int:
	if cands.is_empty() or vis.size() != cands.size():
		return -1
	var inv: float = 1.0 / maxf(tau, 0.05)
	var ws := PackedFloat32Array()
	ws.resize(cands.size())
	var sum := 0.0
	for k in cands.size():
		var w: float = pow(maxf(vis[k], 0.0) + 1.0, inv)
		ws[k] = w
		sum += w
	if sum <= 0.0:
		return -1
	var r: float = rng.randf() * sum
	for k in ws.size():
		r -= ws[k]
		if r <= 0.0:
			return cands[k]
	return cands[cands.size() - 1]


# ----------------------------------------------------------------------------
# 仪器（--liuh2h，2026-10-22）：三款 AI **两两对战** + 选出 6 局写进**用户棋谱库**
# ----------------------------------------------------------------------------
# 用户口令：「让三款AI两两对战十局，告诉我战况，然后取两两之间胜负各一局，总共六局，
#   放进棋谱让我查阅」。
# 三款 = 磐石（`AIEngine`，生产引擎）/ 疾风（`_xg_choose_move()` 骨架二版）/ 流水（`LiushuiAI`）。
#
# 纪律（照抄 `--xgduel`，理由见那边的注释）：
#   · komi=0 消贴目偏置；换色配对消先手偏置；`_quiet_place=true` 免刷屏
#   · 磐石跑**真实对局预算**（玩家面对的就是它，不拉平算力）
#   · `xg_rng_pin` 每局钉死 ⇒ 疾风可复现；引擎 seed 每局不同 ⇒ 三款都不是"死记同一盘"
#
# ★★ 棋谱**为什么不能靠"重放"造**（本仪器最容易踩的坑，先说清）：
#   重放只能走 `place_stone()`，而它用的是 `current_player` ⇒ **严格交替**。可对局里一旦
#   有一手被拒（非法/自杀/打劫），驱动器会手动翻行棋方 ⇒ 真实着法的颜色序列会出现
#   "同色连走"。按严格交替重放就会**把颜色记错**，而错色的谱在复盘器里看起来完全正常
#   （它只按谱走子，不校验颜色是否交替）⇒ 静默产出一份假谱。
#   ⇒ 本仪器的做法：**对局时就由真源记谱**（`place_stone()` 内 `_record_move()` 无条件被调，
#     `_quiet_place` 不拦记谱），每局结束把 `_record` 整份快照存下来；选中的 6 局直接拿
#     快照走 `_record_finish()`（= `GameRecord.finish()` + `_record_flush()`，落盘唯一写点）。
#     好处：谱与 `_hist` 同源，captures / ko 一个都不用手搓，也不可能记错色。
#
# ★ 参数（冒号分隔，全部可选）：--liuh2h=n10:m300:s20261022
#   nN 每对局数（默认 10，换色 ⇒ 5 黑 5 白）｜ mN 单局手数上限（默认 300）｜ sN 基准种子
func _liuh2h_probe() -> void:
	var per_pair := 10
	var max_moves := 300
	var base_seed := 20261022
	for a in _argv():
		if a.begins_with("--liuh2h="):
			for tok in a.substr(9).split(":"):
				if tok.begins_with("n"):
					per_pair = int(tok.substr(1))
				elif tok.begins_with("m"):
					max_moves = int(tok.substr(1))
				elif tok.begins_with("s"):
					base_seed = int(tok.substr(1))
				else:
					# 未知 token 硬报错（同 --xgduel）：静默吃掉的参数会印出"看起来正常"的战况
					print("[liuh2h] ✗ 未知 token：「%s」（支持 nN/mN/sN）" % tok)
					get_tree().quit(1)
					return
	# ★ 前置判据：这次运行**必须不是**自动化运行 —— 否则棋谱会落进 `user://records_selftest`，
	#   用户在菜单「棋谱」里永远看不到这 6 局。"跑完了但查不到"是最坏的失败方式（静默）。
	#   `is_automated_run()` 的口径 = 参数名里含 "test" ⇒ 本仪器名**不许**带 test。
	if GameConfig.is_automated_run():
		print("[liuh2h] ✗ 本次运行被判为自动化运行 ⇒ 棋谱会落进 %s，用户查不到。请去掉含 test 的参数。"
			% GameRecord.records_dir())
		get_tree().quit(1)
		return
	print("[liuh2h] 棋谱落盘目录 = %s（= 用户棋谱库）" % GameRecord.records_dir())

	var komi_bak: int = komi
	var quiet_bak: bool = _quiet_place
	var mode_bak: int = game_mode
	var pin_bak: int = xg_rng_pin
	var mute_bak: bool = _record_muted
	var ovr_bak: Dictionary = _record_players_override
	var kind_bak: int = _record_kind
	komi = 0
	_quiet_place = true
	_record_muted = true      # 30 局里一条都不落盘（理由见 `_record_muted` 声明处）
	# ★ 本仪器产出的谱一律是**机器对局**（AI vs AI）：棋谱列表要靠它把实验证据与玩家的对局分开。
	_record_kind = GameRecord.KIND_MACHINE
	game_mode = LOCAL

	var names: Dictionary = {"prod": "磐石", "xg": "疾风", "liu": "流水"}
	var pairs: Array = [["prod", "xg"], ["prod", "liu"], ["xg", "liu"]]
	var prod := AIEngine.new()
	prod.threads = GameConfig.ai_threads
	prod.root_width = GameConfig.ai_root_width
	prod.time_budget_ms = GameConfig.ai_time_ms
	var liu := LiushuiAI.new()

	var all_games: Array = []     # 每局一条：{pair,a,b,a_is_black,a_total,b_total,scores,snap,...}
	var illegal_all := 0
	var gi := 0
	var t0: int = Time.get_ticks_usec()
	print("[liuh2h] 盘=%s 格数=%d | 每对 %d 局（换色）| 手数上限 %d | 磐石 %dms/手 线程 %d root_width %d | komi=0"
		% [_bt_name(GameConfig.board_type), tiles.size(), per_pair, max_moves,
			prod.time_budget_ms, prod.threads, prod.root_width])

	for pair in pairs:
		var ea: String = str(pair[0])
		var eb: String = str(pair[1])
		var a_wins := 0
		var b_wins := 0
		var pair_draws := 0
		var pair_idx: Array = []      # 本对每局在 all_games 里的下标
		print("[liuh2h] ===== %s vs %s（%d 局）=====" % [str(names[ea]), str(names[eb]), per_pair])
		for k in per_pair:
			var a_is_black: bool = (k % 2) == 0
			var seed_i: int = base_seed + gi * 97
			# ★ 谱头双方名必须在 `reset_game()` **之前**设：谱头是在它内部 `_record_begin()` 建的。
			#   走 `_record_players_override` 这个覆盖口（仍是 `_record_players()` 一个真源）。
			_record_players_override = {
				"black": str(names[ea]) if a_is_black else str(names[eb]),
				"white": str(names[eb]) if a_is_black else str(names[ea]),
			}
			xg_rng_pin = base_seed + gi * 131
			var my_index: int = gi
			gi += 1
			reset_game(true)      # 只清盘面，**不换盘**（`reset_game()` 不重生成棋盘）
			prod.setup(adjacency, Stone.BLACK if a_is_black else Stone.WHITE, seed_i)
			liu.setup(adjacency, Stone.BLACK if a_is_black else Stone.WHITE, seed_i)
			var passes := 0
			var placed := 0
			var illegal := 0
			var ms_p := 0
			var ms_x := 0
			var ms_l := 0
			while passes < 2 and placed < max_moves:
				var turn_color: int = current_player
				var mover: String = ea if ((turn_color == Stone.BLACK) == a_is_black) else eb
				var mv := -1
				if mover == "prod":
					mv = prod.choose_move(board, ko_point, turn_color)
					ms_p += prod.last_ms
				elif mover == "xg":
					var tx: int = Time.get_ticks_msec()
					mv = _xg_choose_move(turn_color)
					ms_x += Time.get_ticks_msec() - tx
				else:
					mv = liu.choose_move(board, ko_point, turn_color)
					ms_l += liu.last_ms
				if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
					if mv >= 0:
						illegal += 1
					# ★ 真·停一手（引擎返回 -1）也要在谱里**留痕**：`_apply_pass()` 干的就是这一句。
					#   不记的话谱上会看到"同色连走"且手数对不上（复盘仍然能走完，但谱本身是错的）。
					if mv < 0:
						_record_move(-1, turn_color, 0, ko_point)
					passes += 1
				else:
					var pr_b: int = black_prisoners
					var pr_w: int = white_prisoners
					if place_stone(mv, false):
						placed += 1
						passes = 0
						# ★★ 记谱**必须在这里手动补**（第一版就栽在这，留作档案）：
						#   `place_stone()` 里那两句 `_hist.append` / `_record_move()` 是写在
						#   `if not _quiet_place:` **里面**的（见 `_record_move()` 的注释
						#   「⚠ 调用方负责 `_quiet_place` 守卫」）⇒ 本仪器为了静音把
						#   `_quiet_place` 置真，谱就**一手都不会记**。第一版实测产出 3 份
						#   **0 手谱**，而"读回校验"照样全绿 —— 因为参照物（快照手数）也是 0，
						#   两边同退化 ⇒ 恒绿（**§110 形态**，第二次踩）。
						#   ⇒ 提子数取**真源计数器**的差值：黑白两个提子桶加起来就是本手提掉的子数
						#     （一手不可能既提子又被提，自杀已在上游被拒）；`ko` 取**本手之后**的
						#     `ko_point`（`append_move` 的口径，与 `_hist` 的 `ko_before` 相反）。
						_record_move(mv, turn_color,
							(black_prisoners - pr_b) + (white_prisoners - pr_w), ko_point)
					else:
						illegal += 1
						passes += 1
				# 停一手 / 被拒不换行棋方 ⇒ 手动交换（同 --xgduel / --aitune）
				if current_player == turn_color:
					current_player = Stone.WHITE if turn_color == Stone.BLACK else Stone.BLACK
			var sc: Dictionary = _compute_scores()
			var pb: int = int(sc.get("total_black", 0))
			var pw: int = int(sc.get("total_white", 0))
			var a_total: int = pb if a_is_black else pw
			var b_total: int = pw if a_is_black else pb
			illegal_all += illegal
			var win_txt := "和"
			if a_total > b_total:
				a_wins += 1
				win_txt = str(names[ea])
			elif b_total > a_total:
				b_wins += 1
				win_txt = str(names[eb])
			else:
				pair_draws += 1
			# ★ 谱快照：`duplicate(true)` 深拷，否则下一局 `reset_game()` 换掉 `_record` 时会一起没。
			all_games.append({
				"pair": "%s-%s" % [ea, eb],
				"a": ea, "b": eb, "a_is_black": a_is_black,
				"a_total": a_total, "b_total": b_total, "scores": sc,
				"plies": placed, "illegal": illegal,
				# ★ 记两个不同口径的手数，别混（第一版混了 ⇒ 自校验假红）：
				#   `plies`        = **落子数**（成功 `place_stone()` 的次数）
				#   `rec_plies`    = **谱条目数**（含停手 `-1`，因为 `_apply_pass()` 也会记一手）
				#   终局时连停两手 ⇒ 谱比落子数多 2 条以上。判"谱全不全"必须用后者。
				"rec_plies": (_record["moves"] as Array).size(),
				"snap": _record.duplicate(true),
			})
			pair_idx.append(all_games.size() - 1)
			print("[liuh2h] 局 %2d %s vs %s（%s执黑）→ %d : %d 胜=%s | 盘上%d手 非法=%d | %d/%d/%dms"
				% [my_index + 1, str(names[ea]), str(names[eb]),
					str(names[ea]) if a_is_black else str(names[eb]),
					a_total, b_total, win_txt, placed, illegal, ms_p, ms_x, ms_l])
			# ★ 每局都印一次跑了多久：这批要十几分钟，没有进度就只能干等（且区分不出"卡死"）
			print("[liuh2h]   … 累计 %d 局 / %.1fs" % [all_games.size(),
				float(Time.get_ticks_usec() - t0) / 1000000.0])
		print("[liuh2h] 小结 %s %d 胜 / %s %d 胜 / 和 %d"
			% [str(names[ea]), a_wins, str(names[eb]), b_wins, pair_draws])

	# ---------- 选局：每对「胜/负各一局」→ 取**最胶着**的那一局（边距最小） ----------
	# 为什么取最胶着：这 6 局是给人看的，碾压局学不到东西；且小边距的局最能体现两者差别。
	var picks: Array = []        # {rec(游戏字典), why}
	for pair in pairs:
		var ea: String = str(pair[0])
		var eb: String = str(pair[1])
		var best_a: Dictionary = {}
		var best_b: Dictionary = {}
		for g in all_games:
			var gd: Dictionary = g
			if str(gd["pair"]) != "%s-%s" % [ea, eb]:
				continue
			var a_total: int = int(gd["a_total"])
			var b_total: int = int(gd["b_total"])
			if a_total > b_total:
				if best_a.is_empty() or (a_total - b_total) < (int(best_a["a_total"]) - int(best_a["b_total"])):
					best_a = gd
			elif b_total > a_total:
				if best_b.is_empty() or (b_total - a_total) < (int(best_b["b_total"]) - int(best_b["a_total"])):
					best_b = gd
		if best_a.is_empty() or best_b.is_empty():
			# ★ 一边倒（某一方 N:0）时「胜负各一局」**字面上不成立**。不许拿碾压局冒充"负局"：
			#   改成取**这一对最胶着的 2 局**（边距最小），并在日志/报告里点名说明。
			#   ★ 第一版这里是"只入 1 局"⇒ 两对一边倒就只写出 4 局，用户要的 6 局交不出来。
			var swept_by: String = str(names[eb]) if best_a.is_empty() else str(names[ea])
			var two: Array = []
			for g in all_games:
				var gd3: Dictionary = g
				if str(gd3["pair"]) != "%s-%s" % [ea, eb]:
					continue
				two.append(gd3)
			two.sort_custom(func(x, y) -> bool:
				return absi(int(x["a_total"]) - int(x["b_total"])) \
					< absi(int(y["a_total"]) - int(y["b_total"])))
			print("[liuh2h] ⚠️ %s vs %s：%s 全胜（%d:0）⇒「胜负各一局」不成立，改取**最胶着的 2 局**"
				% [str(names[ea]), str(names[eb]), swept_by, per_pair])
			for i2 in mini(2, two.size()):
				picks.append({"rec": two[i2], "why": "一边倒·最胶着"})
		else:
			picks.append({"rec": best_a, "why": "最胶着"})
			picks.append({"rec": best_b, "why": "最胶着"})

	# ---------- 第二阶段：把选中的局写进用户棋谱库 ----------
	# ★ 只在写这几条时放开写谱闸；`_record_finish()` 是唯一入口（`GameRecord.finish` + `_record_flush`）。
	_record_players_override = {}
	print("[liuh2h] ===== 入谱 %d 局 =====" % [picks.size()])
	var saved: Array = []
	for p in picks:
		var rec_g: Dictionary = (p as Dictionary)["rec"]
		var snap: Dictionary = rec_g["snap"]
		_record = (snap as Dictionary).duplicate(true)
		# ★★ 防撞名（第一版实测踩到）：`GameRecord.make_id()` = **保存那一秒** + 手数 + 棋盘种子
		#   ⇒ 同一秒内保存、手数与种子又相同的两局**同名**，而 `save()` 见到已设的 id 就直接写
		#   同名文件 ⇒ **静默覆盖前一份**（第一版 3 局全写成同一个 id，库里只剩 1 份）。
		#   本仪器 6 局的手数/种子经常相同 ⇒ 必然撞。做法：先按真源算出 id，被占了就等一秒重算。
		var tries := 0
		while tries < 8:
			var probe_id: String = GameRecord.make_id(_record)
			if not FileAccess.file_exists("%s/%s.json" % [GameRecord.records_dir(), probe_id]):
				break
			OS.delay_msec(1100)
			tries += 1
		_record_muted = false
		_record_finish(GameRecord.REASON_SCORE, rec_g["scores"] as Dictionary)
		_record_muted = true
		var rid: String = str(_record.get("id", ""))
		# ★ 落盘自校验：读回来对三件事（手数 / 比分 / 原因）。写盘成功 ≠ 内容对。
		var back: Dictionary = GameRecord.load_by_id(rid) if rid != "" else {}
		var n_back: int = (back.get("moves") as Array).size() if not back.is_empty() else -1
		var n_want: int = (snap.get("moves") as Array).size()
		# ★ 别写 `back.get("result") as Dictionary`：`result` 为 null 时 `as` 得到 null，
		#   赋给 `var res: Dictionary` 会报类型错（record.gd `_index_entry` 踩过同一个坑）。
		var res: Dictionary = {}
		var rv: Variant = back.get("result")
		if typeof(rv) == TYPE_DICTIONARY:
			res = rv
		var scv: Array = res.get("score", [])
		var sb: int = int(scv[0]) if scv.size() > 0 else -1
		var sw: int = int(scv[1]) if scv.size() > 1 else -1
		# ★ 三面都要断：读回手数 == 快照手数、快照手数 == **谱条目数**、且**不为 0**。
		#   ⚠ 第三面的参照物必须取 `rec_plies`（= `_record["moves"].size()`），**不能取 `plies`**：
		#     后者是"落子数"，而谱里还含停手条目（终局连停两手 ⇒ 谱比落子数多 2 条）⇒ 必假红。
		var ok_plies: bool = n_back == n_want and n_want == int(rec_g["rec_plies"]) and n_want > 0
		var ok_score: bool = sb == int(rec_g["scores"]["total_black"]) and sw == int(rec_g["scores"]["total_white"])
		var ok_reason: bool = str(res.get("reason", "")) == GameRecord.REASON_SCORE
		var ovr: Dictionary = back.get("players", {}) as Dictionary
		var na: String = str(names[str(rec_g["a"])])
		var nb: String = str(names[str(rec_g["b"])])
		var black_name: String = na if bool(rec_g["a_is_black"]) else nb
		print("[liuh2h] 入谱 %s vs %s（%s执黑）→ id=%s | %d手 | 比分 %d:%d | 读回 %s（手数%s 比分%s 原因%s）| 谱头 %s vs %s"
			% [na, nb, black_name, rid, n_want,
				int(rec_g["a_total"]), int(rec_g["b_total"]),
				"✓" if (ok_plies and ok_score and ok_reason) else "✗",
				"✓" if ok_plies else "✗", "✓" if ok_score else "✗", "✓" if ok_reason else "✗",
				str(ovr.get("black", "?")), str(ovr.get("white", "?"))])
		if not (ok_plies and ok_score and ok_reason):
			print("[liuh2h]   ⚠️ 这条读回校验不全绿 ⇒ 库里的谱可能不完整")
		saved.append({"id": rid, "pair": str(rec_g["pair"]), "plies": n_want,
			"a": na, "b": nb, "a_black": bool(rec_g["a_is_black"]),
			"a_total": int(rec_g["a_total"]), "b_total": int(rec_g["b_total"])})

	# ---------- 复原 ----------
	komi = komi_bak
	_quiet_place = quiet_bak
	game_mode = mode_bak
	xg_rng_pin = pin_bak
	_record_muted = mute_bak
	_record_players_override = ovr_bak
	_record_kind = kind_bak
	_record = {}

	print("[liuh2h] ===== 总账 =====")
	var tot: Dictionary = {}
	for g2 in all_games:
		var gd2: Dictionary = g2
		var key: String = str(gd2["pair"])
		if not tot.has(key):
			tot[key] = {"a": 0, "b": 0, "d": 0, "diff": 0, "n": 0}
		var t: Dictionary = tot[key]
		t["n"] = int(t["n"]) + 1
		t["diff"] = int(t["diff"]) + int(gd2["a_total"]) - int(gd2["b_total"])
		if int(gd2["a_total"]) > int(gd2["b_total"]):
			t["a"] = int(t["a"]) + 1
		elif int(gd2["b_total"]) > int(gd2["a_total"]):
			t["b"] = int(t["b"]) + 1
		else:
			t["d"] = int(t["d"]) + 1
	for key in tot.keys():
		var t2: Dictionary = tot[key]
		var nm: Array = String(key).split("-")
		print("[liuh2h] %s vs %s：%s %d 胜 / %s %d 胜 / 和 %d（%d 局）| 目差合计 %+d 均值 %+.1f"
			% [str(names[nm[0]]), str(names[nm[1]]),
				str(names[nm[0]]), int(t2["a"]), str(names[nm[1]]), int(t2["b"]), int(t2["d"]),
				int(t2["n"]), int(t2["diff"]), float(int(t2["diff"])) / float(maxi(int(t2["n"]), 1))])
	print("[liuh2h] 全部 %d 局 | 非法着法 %d 次%s"
		% [all_games.size(), illegal_all,
			"（＝0 ⇒ 双方着法全合法）" if illegal_all == 0 else "  ⚠️ >0 ⇒ 数据要打折看"])
	print("[liuh2h] 耗时 %.1fs" % [float(Time.get_ticks_usec() - t0) / 1000000.0])
	# ★ 仪器账落盘（`user://liuh2h_last.json`）：30 局的双方/比分/手数/着法序列全在。
	#   为什么要它：本仪器**最贵的是跑 30 局**（n10 实测 11min15s），写谱只是最后一个零头。
	#   第一版没存账 ⇒ "选局"规则一改（一边倒那两对只能挤出 4 局）就得**重跑一整批 AI**，
	#   而且重跑后 30 局的比分是**另一批数**（磐石有 200ms 预算 ⇒ 不可复现，§125），
	#   报告里的战况与库里的谱会来自两次不同的运行。存了账就不再有这个问题。
	var dump: Array = []
	for g3 in all_games:
		var gd4: Dictionary = g3
		var sn: Dictionary = gd4["snap"]
		dump.append({
			"pair": gd4["pair"], "a": gd4["a"], "b": gd4["b"],
			"a_is_black": gd4["a_is_black"],
			"a_total": gd4["a_total"], "b_total": gd4["b_total"],
			"plies": gd4["plies"], "rec_plies": gd4["rec_plies"],
			"created_at": str(sn.get("created_at", "")),
			"moves": sn.get("moves", []),
		})
	var df := FileAccess.open("user://liuh2h_last.json", FileAccess.WRITE)
	if df != null:
		df.store_string(JSON.stringify({"games": dump}, " "))
		df.close()
		print("[liuh2h] 仪器账已落盘 user://liuh2h_last.json（%d 局，%d 字节）"
			% [dump.size(), FileAccess.get_file_as_bytes("user://liuh2h_last.json").size()])
	else:
		print("[liuh2h] ⚠️ 仪器账落盘失败（err %d）—— 下次要改选局规则就得重跑" % FileAccess.get_open_error())
	get_tree().quit()


# ----------------------------------------------------------------------------
# 流水诊断/调参仪器（--liudiag，2026-10-22）
# ----------------------------------------------------------------------------
# 为什么要有它：`--liuh2h` 只给"谁赢了多少目"，而流水的病是**结构性**的
#   （10 局被提 1242 子、自己只提 212；平均每局落 123 子、被提 124 子）。
#   要改它就得知道**丢的子是在什么局面下丢的**，于是本仪器按"轮到我时我有没有块只剩 1 气"
#   给每一次丢子归因。四个量：
#     · turns_danger  —— 轮到流水时，己方"恰 1 气"的组里子数合计 > 0 的手数
#     · lost_total    —— 对手提掉我方子的总数（全期）
#     · lost_ignored  —— 其中"上一手我明明有 1 气的块"那一档（= 我有机会救却没救）
#     · self_atari    —— 自己把刚落那颗子弄成 1 气（且没提子）的手数
#   ⇒ `lost_ignored / lost_total` 就是"该救没救"的占比。这个数高，说明第一优先级是**自保项**；
#     这个数低，说明丢子另有原因（例如被连续叫吃、或势场把它往死里推），别乱加权重。
#
# ★ 对手默认**疾风**：它与流水都确定性（同一批逐局比分逐位相同，§125 的"可复现"前提），
#   所以 A/B 两臂是**同一批局面**，差值可以直接配对读。`opp=prod`（磐石）有 200ms 预算
#   ⇒ 不可复现，只当参考，不许拿它算配对 t。
#
# 用法：`--liudiag=n2`（默认 2 局）
#       `--liudiag=n4:k=w_danger=-6`           只调一个旋钮 → A/B 的另一臂
#       `--liudiag=n4:k=w_danger=-6,w_save=0`  多个旋钮（用逗号）
#       `--liudiag=n4:opp=prod`                对磐石（参考）
#       `--liudiag=n4:s20261022`               换基种子（整批局面换掉）
#
# ★★ 旋钮口径（§33 死参数）：`k=名字=值` 里的名字必须是引擎上**真存在**的 `@export`。
#   做法是"设完立刻读回、值不等就硬报错 + 列出可用旋钮" —— 不维护第二张名字表
#   （表会跟引擎漂：改了属性名，表里那条**静默**失效，见 §113）。
func _liudiag_probe() -> void:
	var games_n: int = 2
	var opp: String = "xg"
	var base_seed: int = 20261023
	var knobs: Array = []          # [[name, value], ...]
	var spec := ""
	for a in _argv():
		if a.begins_with("--liudiag="):
			# `--liudiag=` 正好 10 个字符（`--` + `liudiag` 7 + `=`）⇒ 从 10 开始切。
			# ⚠ 首版写成 11（把 `n` 切掉了 ⇒ 报「未知 token：2」）—— 这就是 §109
			#   「插参数后逐个调用点核对实参」那条：长度是硬编码的字面量，差一位就静默错位。
			spec = a.substr(10)
	for tok in spec.split(":", false):
		if tok.begins_with("n"):
			games_n = int(tok.substr(1))
		elif tok.begins_with("opp="):
			opp = tok.substr(4)
		elif tok.begins_with("s") and not tok.contains("="):
			base_seed = int(tok.substr(1))
		elif tok.begins_with("k="):
			for kv in tok.substr(2).split(",", false):
				var pair := kv.split("=")
				if pair.size() != 2:
					print("[liudiag] ✗ 旋钮 token 形状不对：「%s」（应为 名字=值）" % kv)
					get_tree().quit(1)
					return
				knobs.append([str(pair[0]), str(pair[1])])
		elif tok != "":
			print("[liudiag] ✗ 未知 token：「%s」（支持 nN / opp=xg|prod / sN / k=名=值）" % tok)
			get_tree().quit(1)
			return
	if opp != "xg" and opp != "prod":
		print("[liudiag] ✗ opp 只支持 xg / prod，收到「%s」" % opp)
		get_tree().quit(1)
		return

	var komi_bak: int = komi
	var quiet_bak: bool = _quiet_place
	var mode_bak: int = game_mode
	var pin_bak: int = xg_rng_pin
	var mute_bak: bool = _record_muted
	var ovr_bak: Dictionary = _record_players_override
	komi = 0
	_quiet_place = true
	# ★ 本仪器**不写谱**：它是调参用的（会跑很多臂），一局一谱会把用户棋谱库灌满。
	#   `--liudiag` 不含 "test" ⇒ 不写 `_record_muted` 的话它会落进**用户棋谱库**。
	_record_muted = true
	_record_players_override = {"black": "流水", "white": "疾风"}
	game_mode = LOCAL

	var liu := LiushuiAI.new()
	var prod: AIEngine = null
	if opp == "prod":
		prod = AIEngine.new()
		prod.threads = GameConfig.ai_threads
		prod.root_width = GameConfig.ai_root_width
		prod.time_budget_ms = GameConfig.ai_time_ms

	# ---- 旋钮覆盖 + 回读（§33：设了不生效 = 假实验）----
	var knob_note: Array[String] = []
	for kn in knobs:
		var nm: String = str(kn[0])
		var raw: String = str(kn[1])
		var cur: Variant = liu.get(nm)
		if cur == null:
			print("[liudiag] ✗ 未知旋钮「%s」—— 引擎上没有这个属性。可用的数值旋钮：%s"
				% [nm, _liu_knob_names(liu)])
			get_tree().quit(1)
			return
		var nv: Variant = raw
		if typeof(cur) == TYPE_INT:
			nv = int(raw)
		elif typeof(cur) == TYPE_FLOAT:
			nv = float(raw)
		elif typeof(cur) == TYPE_BOOL:
			nv = raw.to_lower() == "true"
		liu.set(nm, nv)
		var back: Variant = liu.get(nm)
		if back != nv:
			print("[liudiag] ✗ 旋钮「%s」设成 %s 读回是 %s（没生效）" % [nm, str(nv), str(back)])
			get_tree().quit(1)
			return
		knob_note.append("%s=%s（原 %s）" % [nm, str(back), str(cur)])
	if not knob_note.is_empty():
		print("[liudiag] 旋钮：%s" % "｜".join(knob_note))
	else:
		print("[liudiag] 旋钮：全部默认（基准臂）")

	var t_start: int = Time.get_ticks_usec()
	print("[liudiag] 盘=%s 格数=%d｜流水 vs %s｜%d 局（换色）｜komi=0｜基种子 %d"
		% [_bt_name(GameConfig.board_type), tiles.size(),
			"疾风" if opp == "xg" else "磐石", games_n, base_seed])

	var rows: Array = []
	for k in games_n:
		var liu_is_black: bool = (k % 2) == 0
		reset_game(true)
		var my_color: int = Stone.BLACK if liu_is_black else Stone.WHITE
		var opp_color: int = Stone.WHITE if liu_is_black else Stone.BLACK
		liu.setup(adjacency, my_color, base_seed + k * 97)
		if prod != null:
			prod.setup(adjacency, opp_color, base_seed + k * 97)
		xg_rng_pin = base_seed + k * 131
		var passes := 0
		var placed := 0
		var illegal := 0
		var turns_danger := 0
		var atari_stones := 0
		var lost_total := 0
		var lost_ignored := 0
		var lost_big := 0
		var self_atari := 0
		var prev_big_cells: Array[int] = []
		var danger_turn := false
		while passes < 2 and placed < 300:
			var tc: int = current_player
			var mv := -1
			var is_mine: bool = tc == my_color
			if is_mine:
				# 轮到我时先量"己方恰 1 气的组"—— 这一手的价值要拿它做归因分母
				var dg: Dictionary = _liudiag_atari(my_color)
				atari_stones += int(dg["stones"])
				danger_turn = int(dg["stones"]) > 0
				if danger_turn:
					turns_danger += 1
				# 把"大块 1 气"的格点记下来：对手下一手若把它们吃掉，就是"我有机会没救"
				prev_big_cells = dg["big_cells"]
				mv = liu.choose_move(board, ko_point, tc)
			elif prod != null:
				mv = prod.choose_move(board, ko_point, tc)
			else:
				mv = _xg_choose_move(tc)
			if mv < 0 or mv >= tiles.size() or board[mv] != Stone.EMPTY or mv == ko_point:
				if mv >= 0:
					illegal += 1
				passes += 1
				continue
			# ★★ 取"**这一手落子方自己**的提子计数"（黑提子数在 `black_prisoners` 里）：
			#   我下手时它=我提了多少；对手下手时它=对手提了多少=**我被提了多少**。
			#   ⚠ 首版取的是"我方"计数（`my_color` 那一侧）⇒ 对手那一支永远量到 0，
			#   于是「被提 / 该救没救」两个量恒 0 而汇总照样打印 —— 静默假绿（§110 形态）。
			var pr_before: int = black_prisoners if tc == Stone.BLACK else white_prisoners
			if not place_stone(mv, false):
				passes += 1
				continue
			placed += 1
			passes = 0
			var pr_now: int = black_prisoners if tc == Stone.BLACK else white_prisoners
			var took: int = pr_now - pr_before
			if is_mine:
				# 自己把刚落这颗子弄成 1 气（且这一手没提到子）= 送吃
				if took == 0:
					var g: Array[int] = _rk.get_group(mv)
					if _rk.get_liberties(g) == 1:
						self_atari += 1
			elif took > 0:
				# 对手这一手提掉的正是我方子（`took` = 这一手新增的提子数）
				lost_total += took
				if danger_turn:
					lost_ignored += took
				# 其中有多少落在我上一手"大块只剩 1 气"的那批点上（= 真的该救没救）
				var hit_big := 0
				for c in prev_big_cells:
					if board[c] == Stone.EMPTY:
						hit_big += 1
				lost_big += hit_big
		var sc: Dictionary = _compute_scores()
		var mine_score: int = int(sc.get("total_black" if my_color == Stone.BLACK else "total_white", 0))
		var opp_score: int = int(sc.get("total_black" if opp_color == Stone.BLACK else "total_white", 0))
		# ★ 提子数的**归属口径**：`black_prisoners` = 黑方提掉的白子数（见声明处），
		#   所以"我提了多少"= 我自己那一侧。首版写反过（印出来"提/被提"互换，且与比分矛盾
		#   ——那正是能当场看出写反的信号），这里按真源写清。
		var my_caps: int = black_prisoners if my_color == Stone.BLACK else white_prisoners
		var opp_caps: int = white_prisoners if my_color == Stone.BLACK else black_prisoners
		rows.append({
			"k": k, "liu_black": liu_is_black, "plies": placed, "illegal": illegal,
			"mine": mine_score, "opp": opp_score, "my_caps": my_caps, "opp_caps": opp_caps,
			"turns_danger": turns_danger, "atari_stones": atari_stones,
			"lost_total": lost_total, "lost_ignored": lost_ignored, "lost_big": lost_big,
			"self_atari": self_atari,
		})
		print("[liudiag] 局%d 流水执%s：%d 手｜分 %d : %d（%+d）｜提 %d 被提 %d｜危局 %d 手（累计 1 气子 %d）｜该救没救 %d/%d（大块 %d）｜送吃 %d｜非法 %d"
			% [k + 1, "黑" if liu_is_black else "白", placed, mine_score, opp_score,
				mine_score - opp_score, my_caps, opp_caps,
				turns_danger, atari_stones, lost_ignored, lost_total, lost_big,
				self_atari, illegal])

	# ---- 汇总（A/B 读这一行）----
	var sum_diff := 0
	var sum_lost := 0
	var sum_ign := 0
	var sum_big := 0
	var sum_caps := 0
	var sum_danger := 0
	var sum_self := 0
	var sum_plies := 0
	for r in rows:
		var rd: Dictionary = r
		sum_diff += int(rd["mine"]) - int(rd["opp"])
		sum_lost += int(rd["lost_total"])
		sum_ign += int(rd["lost_ignored"])
		sum_big += int(rd["lost_big"])
		sum_caps += int(rd["my_caps"])
		sum_danger += int(rd["turns_danger"])
		sum_self += int(rd["self_atari"])
		sum_plies += int(rd["plies"])
	var nn: int = maxi(rows.size(), 1)
	var ign_pct: float = 100.0 * float(sum_ign) / float(maxi(sum_lost, 1))
	var big_pct: float = 100.0 * float(sum_big) / float(maxi(sum_lost, 1))
	print("[liudiag] === 汇总 %d 局 === 目差合计 %+d（均 %+.1f）｜流水提 %d 被提 %d｜危局 %d 手（%.1f/局）｜该救没救 %d/%d = %.1f%%（其中**大块** %d = %.1f%%）｜送吃 %d｜均手数 %.1f"
		% [rows.size(), sum_diff, float(sum_diff) / float(nn), sum_caps, sum_lost,
			sum_danger, float(sum_danger) / float(nn), sum_ign, sum_lost, ign_pct,
			sum_big, big_pct, sum_self, float(sum_plies) / float(nn)])
	print("[liudiag] 耗时 %.1fs｜臂 = %s" % [
		float(Time.get_ticks_usec() - t_start) / 1000000.0,
		"默认" if knob_note.is_empty() else "｜".join(knob_note)])

	komi = komi_bak
	_quiet_place = quiet_bak
	game_mode = mode_bak
	xg_rng_pin = pin_bak
	_record_muted = mute_bak
	_record_players_override = ovr_bak
	get_tree().quit()


# ----------------------------------------------------------------------------
# 流水战术训练场（--liudrill，2026-10-22）
# ----------------------------------------------------------------------------
# ★★ 为什么要有它（本轮最重要的方法论结论）：
#   `--liudiag` 的**对局结果**在 n=20 上仍不可分辨 —— 逐局目差从 +26 一路到 −213，
#   同一个旋钮改一档，均值动 ±3 目而 t≈−0.1；连"被提子数"上的 t 也只有 −0.34。
#   原因不是样本不够，而是这个量**被混沌放大**：一手不同 ⇒ 整局走向完全不同。
#   ⇒ 想训练一个新手引擎，必须先有一个**低方差**的量。战术正确率就是：
#     每个局面只问一个二选一的问题（"对方只剩 1 气，你提不提？"/"你只剩 1 气，你救不救？"），
#     每局是一张伯努利票，n 个局面给 ±5% 的精度 —— 比打 20 局棋便宜得多。
#
# 三道题（全部用**游戏侧规则内核**判真值，不用引擎自己的 `_libs`，§13 跨实现对拍）：
#   ① 捕获：盘上存在对方"恰 1 气"的组，且那口气能落子 ⇒ 引擎该下那一口气点。
#   ② 自救：己方有"恰 1 气"的组（≥2 子，1 子的弃子不算题）⇒ 引擎下完，该组气数必须 ≥2。
#   ③ 送吃（阴性）：引擎这一手不许**制造**新的"恰 1 气"己方组（原本没有 1 气组时才算题）。
#   ⚠ 三道题的**分母必须分别报**：某一道 0 次 = 这批局面没覆盖到，"没考"不等于"考过"（§106）。
#
# 用法：`--liudrill=n40`（40 个局面）｜`--liudrill=n40:s123:k=root_width=30`（可带旋钮）
func _liudrill_probe() -> void:
	var trials: int = 40
	var base_seed: int = 20261024
	var spec := ""
	for a in _argv():
		if a.begins_with("--liudrill="):
			# `--liudrill=` = `--` + `liudrill`(8) + `=` = 11 个字符。
			# ⚠ 这里和 `--liudiag`（10）一样是个硬编码长度，写多一位就把首个 token 切坏
			#   —— 本轮两个仪器**各踩了一次**，所以两处都写了这条注（§109）。
			spec = a.substr(11)
	var knobs: Array = []
	for tok in spec.split(":", false):
		if tok.begins_with("n"):
			trials = int(tok.substr(1))
		elif tok.begins_with("s") and not tok.contains("="):
			base_seed = int(tok.substr(1))
		elif tok.begins_with("k="):
			for kv in tok.substr(2).split(",", false):
				var pr := kv.split("=")
				if pr.size() != 2:
					print("[liudrill] ✗ 旋钮 token 形状不对：「%s」" % kv)
					get_tree().quit(1)
					return
				knobs.append([str(pr[0]), str(pr[1])])
		elif tok != "":
			print("[liudrill] ✗ 未知 token：「%s」（支持 nN / sN / k=名=值）" % tok)
			get_tree().quit(1)
			return

	var liu := LiushuiAI.new()
	liu.setup(adjacency, Stone.BLACK, base_seed)
	for kn in knobs:
		var nm: String = str(kn[0])
		var cur: Variant = liu.get(nm)
		if cur == null:
			print("[liudrill] ✗ 未知旋钮「%s」—— 可用：%s" % [nm, _liu_knob_names(liu)])
			get_tree().quit(1)
			return
		var nv: Variant = str(kn[1])
		if typeof(cur) == TYPE_INT:
			nv = int(str(kn[1]))
		elif typeof(cur) == TYPE_FLOAT:
			nv = float(str(kn[1]))
		elif typeof(cur) == TYPE_BOOL:
			# ★ 布尔旋钮（如 `tactical_roots`）必须显式转 bool：直接 `set()` 一个 String
			#   会抛「Invalid operands 'bool' and 'String' in operator '!='」——
			#   而且是在引擎**内部**用它的时候炸，不在 set 那一句（本仪器首版就这么崩的）。
			nv = str(kn[1]).to_lower() == "true"
		liu.set(nm, nv)
		if liu.get(nm) != nv:
			print("[liudrill] ✗ 旋钮「%s」没生效（读回 %s）" % [nm, str(liu.get(nm))])
			get_tree().quit(1)
			return
	print("[liudrill] 盘=%s｜%d 个局面｜基种子 %d｜旋钮 %s"
		% [_bt_name(GameConfig.board_type), trials, base_seed,
			"默认" if knobs.is_empty() else str(knobs)])

	var board_bak: Dictionary = board.duplicate()
	var ko_bak: int = ko_point
	var t0: int = Time.get_ticks_usec()
	var cap_n := 0
	var cap_ok := 0
	var save_n := 0
	var save_ok := 0
	var safe_n := 0
	var safe_ok := 0
	var miss_examples: Array[String] = []
	var miss_save: Array[String] = []
	var q_nocand := 0    # 局面里连"≥2 子且气数 2~4"的己方块都没有
	var q_nofit := 0     # 有候选块，但一个候选逃生口都造不出有解的题面
	var q_noisy := 0     # 别处也有"救得活"的 1 气块 ⇒ 引擎去救那块同样合理，不算它错
	var q_safe_dead := 0 # ③ 的题面**无解**（每个空点落下去都会造出 1 气己方块）⇒ 不进分母
	var save_with_other := 0   # 出成的题里有几道带着"额外的 1 气块"（更接近真局的取舍场景）
	for ti in trials:
		liu.rng.seed = base_seed + ti * 17
		liu.scramble(35 + (ti * 7) % 45)          # 35~79 手：覆盖中盘到收官
		var snap: Dictionary = liu.export_board()
		var mover: int = int(liu._turn)
		# 把局面灌进游戏侧（`_rk` 读的就是 `board`），量真值
		for i in adjacency.size():
			board[i] = int(snap.get(i, Stone.EMPTY))
		ko_point = -1                              # 打劫局面不在本训练场的题型内
		# ---- 找题 ----
		var opp: int = 3 - mover
		var cap_pts: Array[int] = []
		var my_atari_before := 0
		var seen := {}
		for i in adjacency.size():
			if board[i] == Stone.EMPTY or seen.has(i):
				continue
			var col: int = board[i]
			var g: Array[int] = _rk.get_group(i)
			for c in g:
				seen[c] = true
			if _rk.get_liberties(g) != 1:
				continue
			if col == opp:
				# 对方只剩 1 气 ⇒ 提掉它（气点必须能落子）
				for c in g:
					for nb in adjacency[c]:
						if board[nb] == Stone.EMPTY and not cap_pts.has(nb):
							cap_pts.append(nb)
			elif g.size() >= 2:
				my_atari_before += g.size()
		var mv: int = liu.choose_move(snap, -1, mover)
		var mv_ok: bool = mv >= 0 and mv < tiles.size() and board[mv] == Stone.EMPTY
		# ---- ③ 的元判据：这题到底**有没有解** ----
		# ★★ 2026-10-22 第二轮补。来历：`w_self_atari` 从 −18 扫到 **−90**，③ 一位不动
		#   —— 典型的死参数（§33）。查下去发现 ③ 缺的正是 ② v1 踩过的那个坑：
		#   **题面可能无解**。③ 的条件是"落子前盘上没有 1 气己方块"，但若**每个空点
		#   落下去**都会把相邻己方块压成 1 气（scramble 到 35~79 手时满盘薄块，很常见），
		#   那引擎下哪儿都算送吃 ⇒ 分母里混着死题，权重再大也涨不了（§106 / §110）。
		#   判法：枚举所有空点，落一手看该组气数 —— 只要有一个 ≥2 气，这题就有解。
		#   （落子只会影响与 p 相邻的己方块，而它们全部并入 `get_group(p)`；落子前又
		#    已保证没有 1 气块 ⇒ 只查这一个组就够，不必扫全盘。）
		var safe_q: bool = my_atari_before == 0 and cap_pts.is_empty() and mv_ok
		var safe_possible := false
		if safe_q:
			for p in adjacency.size():
				if board[p] != Stone.EMPTY:
					continue
				board[p] = mover
				var libp: int = _rk.get_liberties(_rk.get_group(p))
				board[p] = Stone.EMPTY
				if libp >= 2:                 # 0 = 自杀、1 = 送吃，都不算解
					safe_possible = true
					break
		# ★★ 必须把这一手**真的落到 `board` 上**再判 ②③：`_rk` 读的是 `board`，
		#   不落子就永远看到"落子前"的局面 ⇒ 「自救」那道题会恒判失败（假红）。
		#   落完不用还原：每轮开头会整盘重灌。
		if mv_ok:
			board[mv] = mover
		# ---- 判 ① 捕获 ----
		if not cap_pts.is_empty():
			cap_n += 1
			if mv_ok and cap_pts.has(mv):
				cap_ok += 1
			elif miss_examples.size() < 6:
				miss_examples.append("捕获#%d 该下 %s，下了 %d" % [ti, str(cap_pts), mv])
		# ---- 判 ③ 送吃（阴性）----
		# ★★ 2026-10-22 第二轮修：**口径从"全盘"改成"落子点所在组"**。
		#   首版判的是"落子后全盘有没有 1 气己方块" —— 可是盘上本来就可能有 1 气的
		#   **孤子**（1 子），它们被提是**正常弃子**，与这一手毫无关系。而且出题条件那边
		#   用的是 `g.size() >= 2`（把单子排除在外），两处口径**互相矛盾**：
		#   出题时说"没有 1 气块"，判分时却把单子算成送吃。
		#   对拍证据（临时引擎实例，同一手）：被判送吃的那几手，**落子组气数是 3 / 2 / 2 / 5**
		#   ⇒ 一手都没送吃。于是 55% / 27% / 27% 全是**假红**，`w_self_atari` 从 −18 扫到
		#   −90、`forbid_self_atari` 硬过滤、`prefilter_width` 30→300 三把刀"一位不动"
		#   也是**必然的**：根本没有东西可砍（§71：判据与数据矛盾，先疑判据）。
		if safe_q and not safe_possible:
			q_safe_dead += 1              # 无解题：不进分母，单独记账
		elif safe_q:
			safe_n += 1
			var libs_mv: int = _rk.get_liberties(_rk.get_group(mv))
			if libs_mv >= 2:
				safe_ok += 1
			elif miss_examples.size() < 6:
				# 真送吃：留对拍信息（引擎侧同一手的气数），万一两条实现哪天分叉能立刻看见。
				var liu2 := LiushuiAI.new()
				liu2.setup(adjacency, mover, 1)
				liu2._load_board(snap, -1)
				var eng_libs := -1
				var dp: int = liu2._play(mv, mover)
				if dp >= 0:
					eng_libs = liu2._libs(liu2._group(mv))
					liu2._rollback()
				miss_examples.append(
					"送吃#%d 落子组只剩 %d 气（mv=%d｜引擎侧同一手 = %d 气）"
					% [ti, libs_mv, mv, eng_libs])

	# ---- ② 自救题：**构造**出来，不等随机局面撞上（2026-10-22 实测：40 个随机局面里 0 道）----
	# ★ 为什么必须构造：`scramble()` 的随机着法几乎不会留下"己方只剩 1 气"的块，
	#   于是首版这一道的**分母是 0** —— 而"没考"与"考过且通过"在报告里长得完全不同（§106）。
	# ★ 构造法 v2（2026-10-22 第二轮修正）：找己方一块**气数 2~4**（≥2 子）的组 →
	#   枚举"留哪个气点当**逃生口**"，其余气点**逐个用对方子堵掉** ⇒ 该块恰剩那 1 口气。
	# ★★ v1 的错（§71 现场）：v1 只找"**正好 2 气**"的块再堵一个气点 —— 实测 18 道题里
	#   **16 道根本无解**：块挨着盘缘时剩下那口气点只有 2 个邻居、其中一个就是刚堵上的
	#   对方子 ⇒ 落上去 0 气（自杀）。判据自己就打印了「题面无效 16 处（应 0）」，
	#   而 v1 报的"自救 11%"正是在那 2 道有效题上算的（真实是 2/2 = 100%）。
	#   ⇒ 分母里混着无解题，是**判据坏**，不是引擎不行。
	for ti in trials:
		liu.rng.seed = base_seed + 5000 + ti * 23
		liu.scramble(30 + (ti * 11) % 50)
		var snap2: Dictionary = liu.export_board()
		var mover2: int = int(liu._turn)
		var opp2: int = 3 - mover2
		for i in adjacency.size():
			board[i] = int(snap2.get(i, Stone.EMPTY))
		ko_point = -1
		# 找一块气数 2~4 的己方块当题面
		var anchor := -1
		var esc_pt := -1
		var plugs: Array[int] = []
		var had_cand := false
		var noisy_once := false
		var other_atari_kept := 0     # 这题出成时，盘上另外还有几个 1 气己方块
		# ★ `libs` 必须声明在循环**外**：GDScript 的块作用域把它限制在内层 `for` 里，
		#   而下面的元判据要用"另一个气点" ⇒ 声明在里层会编译报「Identifier not found」。
		var libs: Array[int] = []
		var seen3 := {}
		for i in adjacency.size():
			if anchor >= 0:
				break
			if board[i] != mover2 or seen3.has(i):
				continue
			var g5: Array[int] = _rk.get_group(i)
			for c in g5:
				seen3[c] = true
			if g5.size() < 2:
				continue
			var nlib: int = _rk.get_liberties(g5)
			if nlib < 2 or nlib > 4:
				continue
			had_cand = true
			libs = []
			for c in g5:
				for nb in adjacency[c]:
					if board[nb] == Stone.EMPTY and not libs.has(nb):
						libs.append(nb)
			if libs.size() != nlib:
				continue          # 气数与该块相邻空点数不符 ⇒ 这道不造（防御性，正常不会发生）
			# 枚举"留哪个气点当逃生口"，其余全堵
			for cand in libs:
				var pl: Array[int] = []
				var dead: Array[int] = []      # 堵子顺手吃掉的己方子（必须能还原）
				var ok_all := true
				for p in libs:
					if p == cand:
						continue
					# ★ 堵子是否合法**走真源** `_rk.can_place_at`：它自带"若我占这一点，
					#   相邻对方块 0 气就能吃"的推演。自己写"落完数气 < 1 就判自杀"会把
					#   **能提子**的堵点误判成自杀（首版就这么写的，白扔一批题）。
					if not _rk.can_place_at(p, opp2):
						ok_all = false
						break
					board[p] = opp2
					pl.append(p)
				if ok_all:
					# ★ 堵子可能顺手把己方**别的**块吃到 0 气 —— 真实对局里这就是"对方这一手
					#   吃了我一块"。不把那些子从盘上拿走，题面就是个带 0 气块的**非法局面**，
					#   引擎看到的是怪盘。题面块自己有逃生口（`cand` 被跳过），不会被吃。
					var seen5 := {}
					for k in adjacency.size():
						if board[k] != mover2 or seen5.has(k):
							continue
						var g8: Array[int] = _rk.get_group(k)
						for c in g8:
							seen5[c] = true
						if _rk.get_liberties(g8) == 0:
							for c in g8:
								board[c] = Stone.EMPTY
								dead.append(c)
				# ★★ 元判据 ①（§110）：**先证明这道题有解** —— 用真源替引擎走"逃生口"
				#   这一手，它必须把这块救到 ≥2 气。救不活 ⇒ 这题是坏的，**不进分母**。
				var saved := false
				if ok_all:
					board[cand] = mover2
					saved = _rk.get_liberties(_rk.get_group(int(g5[0]))) >= 2
					board[cand] = Stone.EMPTY
				# ★★ 元判据 ②（放宽版）：**题面是唯一"救得活"的 1 气块**。
				#   首版要求"全盘只有这一块 1 气"—— 实测 60 个局面里 **45 个过不了**
				#   （堵子会牵连到别的己方块，把它们也压到 1 气），而那 45 个局面恰恰是
				#   **更真实**的考题（同时两处告急，正是流水输棋的地方）。真正会冤枉引擎的
				#   情形只有一种：**另一块也救得活、引擎选了它** ⇒ 只把这一种排掉。
				var other_live := 0
				var other_atari := 0
				if saved:
					var seen4 := {}
					for k in adjacency.size():
						if board[k] != mover2 or seen4.has(k):
							continue
						var g7: Array[int] = _rk.get_group(k)
						for c in g7:
							seen4[c] = true
						if _rk.get_liberties(g7) != 1:
							continue
						if g7.has(int(g5[0])):
							continue              # 这就是题面块本身
						other_atari += 1
						# 1 气块的空邻点只有一个；落上去能到 ≥2 气 ⇒ 这块也救得活
						var esc2 := -1
						for c in g7:
							for nb in adjacency[c]:
								if board[nb] == Stone.EMPTY:
									esc2 = nb
						if esc2 >= 0:
							board[esc2] = mover2
							if _rk.get_liberties(_rk.get_group(int(g7[0]))) >= 2:
								other_live += 1
							board[esc2] = Stone.EMPTY
				if ok_all and saved and other_live == 0:
					anchor = int(g5[0])
					esc_pt = cand
					plugs = pl
					other_atari_kept = other_atari
					break
				# 这个候选不成 ⇒ **完整还原**（堵子 + 被吃掉的己方子都要放回去），
				# 否则下一个候选是在一个被污染过的盘面上判的。
				if ok_all and saved:
					noisy_once = true
				for q in pl:
					board[q] = Stone.EMPTY
				for q in dead:
					board[q] = mover2
		if anchor < 0 or esc_pt < 0:
			# ★ 没造出题也必须分类记账，且**每个局面只归一类**（否则三个桶加起来会超过
			#   局面数，"跳过了多少"这个信息量就假了）。`q_noisy` 优先 —— 它说明"有解
			#   题面确实存在，只是盘上还有别的 1 气块"，与"根本没有候选块"完全是两码事。
			if noisy_once:
				q_noisy += 1
			elif had_cand:
				q_nofit += 1
			else:
				q_nocand += 1
			continue                      # 分母不加（§106：没考 ≠ 考过且通过）
		# ★★ 元判据（§110）：**先证明这道题有解**，再看引擎能不能解 —— 没有这一步，
		#   "0/20 = 0%" 就分不清是引擎不行还是判据坏了，而这两种在报告里长得一模一样
		#   （本工程 §110 记着同一形态的两次事故，v1 正是第三次）。
		# ★ 两条元判据现在**都在上面那个候选枚举里**逐候选做掉了。为什么不能挪到这里做：
		#   挪下来就只能验"顺手挑中的那一个候选"，而坏候选（落在盘缘、堵完救不活）
		#   恰恰是最容易被顺手挑中的那些 ⇒ 又回到 v1 的老路。
		save_n += 1
		if other_atari_kept > 0:
			save_with_other += 1
		var board_q: Dictionary = {}
		for i in adjacency.size():
			if board[i] != Stone.EMPTY:
				board_q[i] = board[i]
		var mv2: int = liu.choose_move(board_q, -1, mover2)
		var ok2: bool = mv2 >= 0 and mv2 < tiles.size() and board[mv2] == Stone.EMPTY
		if ok2:
			board[mv2] = mover2
			if board[anchor] == mover2:
				var g6: Array[int] = _rk.get_group(anchor)
				if _rk.get_liberties(g6) >= 2:
					save_ok += 1
				elif miss_save.size() < 6:
					miss_save.append("自救#%d 那块落子后仍 %d 气（下了 %d，逃生口 %d，已堵 %s）"
						% [ti, _rk.get_liberties(g6), mv2, esc_pt, str(plugs)])
			else:
				# 原块已经不在了（被提或被他处合并）⇒ 这一手没救到题面那块
				if miss_save.size() < 6:
					miss_save.append("自救#%d 题面那块不见了（下了 %d）" % [ti, mv2])
		elif miss_save.size() < 6:
			miss_save.append("自救#%d 只剩 1 气却没落子（mv=%d）" % [ti, mv2])

	for i in adjacency.size():
		board[i] = int(board_bak.get(i, Stone.EMPTY))
	ko_point = ko_bak

	var pct := func(a: int, b: int) -> String:
		if b <= 0:
			return "n/a（分母 0：这批局面没出这种题）"
		return "%d/%d = %.0f%%" % [a, b, 100.0 * float(a) / float(b)]
	print("[liudrill] ① 捕获机会：%s" % pct.call(cap_ok, cap_n))
	print("[liudrill] ② 自救机会：%s" % pct.call(save_ok, save_n))
	# ★ ②的自救题是**构造**出来的，所以"跳过多少个局面"是这一栏最重要的信息量：
	#   `save_n` 小的时候那几个百分点的置信区间宽得能装下任何结论。这里不给它留静默空间。
	print("[liudrill]    ② 跳过的局面 %d／%d（无候选块 %d ／ 候选全无解 %d ／ 别处也救得活 %d）%s"
		% [q_nocand + q_nofit + q_noisy, trials, q_nocand, q_nofit, q_noisy,
			"" if save_n * 2 >= trials else "  ⚠ 有效题不到一半，这一栏的百分比别拿去定优劣"])
	print("[liudrill]    ② 出成的 %d 道题里，%d 道同时另有 1 气块（= 真局里那种『救哪块』的取舍）"
		% [save_n, save_with_other])
	print("[liudrill] ③ 不送吃（阴性）：%s｜无解题 %d 处（这些局面下**每个空点**落下去都会造出 1 气己方块）"
		% [pct.call(safe_ok, safe_n), q_safe_dead])
	print("[liudrill] 合计得分 %d/%d｜耗时 %.1fs"
		% [cap_ok + save_ok + safe_ok, cap_n + save_n + safe_n,
			float(Time.get_ticks_usec() - t0) / 1000000.0])
	if not miss_examples.is_empty():
		print("[liudrill] ①③ 漏点样本（最多 6 条）：")
		for s in miss_examples:
			print("[liudrill]   · %s" % s)
	if not miss_save.is_empty():
		print("[liudrill] ② 漏点样本（最多 6 条）：")
		for s in miss_save:
			print("[liudrill]   · %s" % s)
	get_tree().quit()


## 列出一份引擎实例上**数值型** `@export` 的名字（给 `--liudiag` 报错时用，不维护第二张表）。
func _liu_knob_names(o: Object) -> String:
	var out: Array[String] = []
	for p in o.get_property_list():
		var pd: Dictionary = p
		var usage: int = int(pd.get("usage", 0))
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var t: int = int(pd.get("type", 0))
		if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
			out.append(str(pd.get("name", "")))
	out.sort()
	return ", ".join(out)


## 己方"只剩 1 气"的组：返回 {"stones": 全部子数, "big": 大块子数, "big_cells": 大块格点, "pts": 气点}。## ★ 走**游戏侧规则内核**（`_rk.get_group` / `_rk.get_liberties`）—— 诊断读的是"真实死活量"，
##   与引擎内部那套 `_libs()` 互为独立实现（§13 跨实现对拍的同一条纪律：别用被测物自证）。
## ★★ 为什么分"大块"（≥3 子）：1~2 颗子被提是**正常弃子**，几乎每局都会发生；
##   把它算进"该救没救"会把弃子误判成失误（首版就是这么算的，于是 63% 这个数被抬高）。
##   真正值得救的是**已经成规模、救了能活**的块 ⇒ 只有大块被提才算"失误"。
func _liudiag_atari(color: int) -> Dictionary:
	var seen := {}
	var stones := 0
	var big := 0
	var big_cells: Array[int] = []
	var pts: Array[int] = []
	for i in adjacency.size():
		if board[i] != color or seen.has(i):
			continue
		var g: Array[int] = _rk.get_group(i)
		for c in g:
			seen[c] = true
		if _rk.get_liberties(g) == 1:
			stones += g.size()
			if g.size() >= 3:
				big += g.size()
				for c in g:
					big_cells.append(c)
			for c in g:
				for nb in adjacency[c]:
					if board[nb] == Stone.EMPTY and not pts.has(nb):
						pts.append(nb)
	return {"stones": stones, "big": big, "big_cells": big_cells, "pts": pts}


# ----------------------------------------------------------------------------
# 维护仪器（--recmig，2026-10-22）：给**老棋谱**补齐 `kind` 分类字段 + 补 `players` 索引投影
# ----------------------------------------------------------------------------
# 为什么需要：`kind`（分类）与索引里的 `players`（对局双方）都是 2026-10-22 才加的，
#   之前的谱没有它们 ⇒ ① 仪器批量自弈产出的机器对局会被默认值归到「我的对局」里；
#   ② 列表显示不出「磐石 vs 疾风」这种双方名（只能显示"本地"）。
#
# ★ 为什么必须"读全谱 → 补 → `save()`"，而不是直接改 `index.json`：
#   索引的**唯一写点**是 `save()` → `_index_upsert()` → `_index_entry()`。手写索引就是在
#   `save()` 之外开了第二个索引写点（铁律 8 的老坑），而且投影逻辑会立刻跟真源分叉。
#
# ★ 认领口径（**只对"缺 kind 的老谱"生效**，一次性）：谱头双方名都在
#   `GameRecord.MACHINE_PLAYER_NAMES` 里 ⇒ 机器对局。新谱一律由写谱方直接给 `kind`，
#   所以这条"按名字猜"的规则**不会长期承重**（§113 担心的正是长期承重的名字推断）。
#
# ⚠️ 本 instrument 名字**不含 test** ⇒ `is_automated_run()` 为假 ⇒ 它动的是**用户棋谱库**。
#   这是刻意的（要迁移的就是真库），但也意味着它是一条**写用户数据**的命令，只该人工跑一次。
func _record_migrate_kind() -> void:
	var idx: Array = GameRecord.list_index()
	var n_all := 0
	var n_need := 0
	var n_ok := 0
	var n_machine := 0
	var n_err := 0
	for e in idx:
		if not (e is Dictionary):
			continue
		n_all += 1
		var id: String = str((e as Dictionary).get("id", ""))
		if id == "":
			n_err += 1
			continue
		var rec: Dictionary = GameRecord.load_by_id(id)
		if rec.is_empty():
			# 索引里有、文件没了 ⇒ 旧摘要（例如导出后手工删过文件）。不动索引，只报出来。
			n_err += 1
			print("[recmig] ⚠️ %s 读不出（文件已不存在，索引是旧摘要）" % id)
			continue
		var pl: Dictionary = {}
		var pv: Variant = rec.get("players")
		if typeof(pv) == TYPE_DICTIONARY:
			pl = pv
		var bn: String = str(pl.get("black", ""))
		var wn: String = str(pl.get("white", ""))
		var need: bool = int(rec.get("kind", -1)) < 0
		if need:
			var is_machine: bool = GameRecord.MACHINE_PLAYER_NAMES.has(bn) \
				and GameRecord.MACHINE_PLAYER_NAMES.has(wn)
			rec["kind"] = GameRecord.KIND_MACHINE if is_machine else GameRecord.KIND_HUMAN
			n_need += 1
		if int(rec.get("kind", GameRecord.KIND_HUMAN)) == GameRecord.KIND_MACHINE:
			n_machine += 1
		# ★ 无条件重写一遍（不只"补过字段的那些"）：老索引里还缺 `players` 投影，
		#   而列表要显示双方名。`save()` 会连索引一起 upsert ⇒ 一次走完两个缺口。
		var p: String = GameRecord.save(rec)
		if p == "":
			n_err += 1
			print("[recmig] ⚠️ %s 重写失败" % id)
			continue
		n_ok += 1
		if need:
			print("[recmig] %s → %s（%s vs %s）" % [id,
				"机器对局" if int(rec["kind"]) == GameRecord.KIND_MACHINE else "我的对局", bn, wn])
	# ---- 回读校验（写盘成功 ≠ 索引变了：判据读**真源** `list_index()`，不读自己的计数器）----
	var after: Array = GameRecord.list_index()
	var lack_kind := 0
	var lack_pl := 0
	var mach_after := 0
	for e2 in after:
		var d2: Dictionary = e2
		if not d2.has("kind"):
			lack_kind += 1
		var pv2: Variant = d2.get("players")
		if typeof(pv2) != TYPE_DICTIONARY or str((pv2 as Dictionary).get("black", "")) == "":
			lack_pl += 1
		if int(d2.get("kind", GameRecord.KIND_HUMAN)) == GameRecord.KIND_MACHINE:
			mach_after += 1
	print("[recmig] 索引 %d 条｜补 kind %d 条｜重写成功 %d｜机器对局 %d｜失败 %d" % [
		n_all, n_need, n_ok, n_machine, n_err])
	print("[recmig] 回读：索引 %d 条｜仍缺 kind %d（应0）｜仍缺 players %d（应0）｜机器对局 %d → %s" % [
		after.size(), lack_kind, lack_pl, mach_after,
		"✓" if (lack_kind == 0 and lack_pl == 0 and n_err == 0
			and mach_after == n_machine and after.size() == n_all) else "✗"])
	get_tree().quit()


# ============================================================================
# 自检（--aipristest）**叶子评估「提子项」接线**（2026-10-27）
# ============================================================================
## 被测对象：`AIEngine.count_prisoners` + `_pris_b/_pris_w` 计数器 + `_pris_term()` 出口。
##
## 【为什么必须有一条不靠对打的判据】这个改动的四种坏法**全是静默的**：
##   ① `@export` 名字打错 / 没同步进 `copy_to()` ⇒ 开关形同不存在；
##   ② `_search_budget()` 没清零 ⇒ 计数跨手累积，越下越偏；
##   ③ 符号反了（`_pris_w - _pris_b` 写反）⇒ AI 变成「提子吃亏」，比不做还坏；
##   ④ `_undo()` 没回滚 ⇒ rollout 每退一手就永久少一份提子。
## 四种都会让 A/B 对打呈现「没差别」，于是被读成「提子项没用」（铁律 §33/§138/§106）。
## ⇒ 先用**代数恒等式**钉住接线，再谈对打：
##   关态 `_pris_term()` 恒 0；开态提 1 子后 `_result()` 反解出的目差**恰好**变化 1.0；
##   且 `_last_area_*` 两态**逐位相同**（证明只动搜索效用、没污染分析层）。
##
## 确定性：无搜索、无线程、无随机器；`eval_mix_lambda=0` + 关动态分中心
##   ⇒ `_result()` 就是 `0.5 + 0.5·tanh(sc/score_soft)`，反解可逆 ⇒ 恒等式是**等式**不是阈值。
func _ai_prisoner_term_test() -> void:
	var fails: Array[String] = []
	# 居中挑一块 >=3 邻居的瓷砖当「被提的子」，邻居里留一个空口给提子方落子
	var T := -1
	var best := 1.0e18
	var vc := get_viewport_rect().size * 0.5
	for i in tiles.size():
		if (adjacency[i] as Array).size() < 3:
			continue
		var dd: float = tile_centers[i].distance_squared_to(vc)
		if dd < best:
			best = dd
			T = i
	if T < 0:
		print("[aipristest] ✗ 找不到 >=3 邻居的瓷砖（棋盘未就绪）")
		get_tree().quit()
		return
	var nb: Array = adjacency[T]
	var P := int(nb[0])                     # 空口 = 提子方落子点
	# ★★★ 造局必须**均衡**（第一版就栽在这）：只摆「被提的子 + 围它的子」的话，
	#   整盘 120 格几乎全同色 ⇒ 裸目差 ≈ −120 ⇒ `tanh(−120/7)` 早饱和到 0.0 胜率，
	#   开/关两态的胜率**都**是 0.0 ⇒ 「差 1 目」量不出来 ⇒ ⑤ 恒红但红的是局面不是代码。
	#   ⇒ 其余瓷砖按黑白交替铺满（只留 P 空），让裸目差落在 tanh 的线性区（|sc| ≲ 10）。
	#   顺带这也更接近真实叶子：真实局面的分差是几目到几十目，不是 ±120。
	var bd_bcap := {T: Stone.WHITE}         # 白被围 ⇒ 黑落 P 提白 1 子
	var bd_wcap := {T: Stone.BLACK}         # 黑被围 ⇒ 白落 P 提黑 1 子
	for j in range(1, nb.size()):
		bd_bcap[int(nb[j])] = Stone.BLACK
		bd_wcap[int(nb[j])] = Stone.WHITE
	var used := {T: true, P: true}
	for x in nb:
		used[int(x)] = true
	var k := 0
	for i in tiles.size():
		if used.has(i):
			continue
		# 交替铺：黑组先补白、白组先补黑（让被提那一方的盘面先少一子，正负对称）
		bd_bcap[i] = Stone.WHITE if k % 2 == 0 else Stone.BLACK
		bd_wcap[i] = Stone.BLACK if k % 2 == 0 else Stone.WHITE
		k += 1

	var e := AIEngine.new()
	e.setup(adjacency, Stone.BLACK)
	e.threads = 1
	e.eval_mix_lambda = 0.0
	e.dynamic_center_enabled = false
	# 死子修正会额外改分项（`dead_penalty`），而本判据只关心**提子项**：
	# 它在两态行为完全相同、会抵消，但关掉能让 ⑤ 的等式更纯粹地只反映提子项。
	e.dead_penalty = false

	print("[aipristest] 提子项接线（瓷砖 T=t%d 白/黑互换，空口 P=t%d）" % [T, P])
	for grp in [["黑提白", bd_bcap, Stone.BLACK, -1.0],
			["白提黑", bd_wcap, Stone.WHITE, 1.0]]:
		var gname: String = grp[0]
		var gbd: Dictionary = grp[1]
		var gcol: int = grp[2]
		var gsign: float = grp[3]           # ±1：提子项 = 白提子 − 黑提子
		e.ai_color = gcol
		var off := _pris_probe_once(e, gbd, P, false)
		var on := _pris_probe_once(e, gbd, P, true)
		# ★ 期望值**不写死 1**：交替铺满后 P 周围常有**多块**白（黑）棋同时只剩 P 一口气，
		#   实测这一手提 11 子。写死 1 会让判据红在「我造局时的想象」上，而不是代码上
		#   （第一版就这么红的）。期望由**引擎自己返回的提子数**推：`nc` 走的是提子机器，
		#   `_pris_term()` 走的是计数器 —— 两条不同的代码路径，互校才有牙齿（铁律 §13）。
		var ncap: int = int(on["nc"])
		var gexp: float = gsign * float(ncap)
		var s_off := _pris_score_from_result(float(off["r"]), e.score_soft)
		var s_on := _pris_score_from_result(float(on["r"]), e.score_soft)
		var dsc := s_off - s_on             # 白方目差变化（正 = 白亏）
		# 有效分母：这一手必须**真的提了子**，否则后面全是空转恒真
		var cap_ok: bool = ncap > 0 and int(off["nc"]) == ncap
		var c1: bool = float(off["before"]) == 0.0 and float(on["before"]) == 0.0
		var c2: bool = float(off["after"]) == 0.0
		var c3: bool = absf(float(on["after"]) - gexp) < 1.0e-9
		var c4: bool = float(on["undo"]) == 0.0
		var c5: bool = absf(dsc + gexp) < 1.0e-3    # 目差变化 = −提子项（精确等式）
		var c6: bool = float(off["ab"]) == float(on["ab"]) and float(off["aw"]) == float(on["aw"])
		# ⑦ **非饱和守卫**（第一版补的牙）：tanh 饱和时「差 1 目」在胜率上完全不可见，
		#   ⑤ 会恒红；而如果两态都被压在同一个饱和点上，它也可能被凑成绿。
		#   ⇒ 必须显式断言裸目差落在 `_pris_score_from_result` 可逆区间内
		#   （反解按 x 夹到 ±0.999999 ⇒ 可测上限 |sc| ≈ score_soft·atanh(0.999999) ≈ 50.7）。
		#   这里红了 = **判据无分辨力**，不许当成"代码坏了"也不许当成"过了"（铁律 §106）。
		var c7: bool = absf(s_off) <= 45.0 and absf(s_on) <= 45.0
		print("[aipristest] %s：提子 %d/%d（须 1/1）｜_pris_term 关=%s 开=%s（期望 %s）｜undo=%s" % [
			gname, int(off["nc"]), int(on["nc"]),
			str(off["after"]), str(on["after"]), str(gexp), str(on["undo"])])
		print("[aipristest]   %s ① 装载后归零 %s ② 关态恒 0 %s ③ 开态符号量值 %s ④ LIFO 回滚 %s" % [
			gname, "✓" if c1 else "✗", "✓" if c2 else "✗",
			"✓" if c3 else "✗", "✓" if c4 else "✗"])
		print("[aipristest]   %s ⑤ 目差恒等：关−开=%.6f 期望=%.6f %s ⑥ _last_area 未污染 %s（黑 %s/%s 白 %s/%s）" % [
			gname, dsc, -gexp, "✓" if c5 else "✗", "✓" if c6 else "✗",
			str(off["ab"]), str(on["ab"]), str(off["aw"]), str(on["aw"])])
		print("[aipristest]   %s ⑦ 非饱和（裸目差 %s / %s，须 |x|<=45） %s" % [
			gname, str(s_off), str(s_on), "✓" if c7 else "✗"])
		if not cap_ok:
			fails.append("%s：有效分母为 0（这一手没提子）" % gname)
		for pair in [["①归零", c1], ["②关态恒0", c2], ["③开态符号", c3],
				["④LIFO回滚", c4], ["⑤目差恒等", c5], ["⑥分析层未污染", c6],
				["⑦非饱和", c7]]:
			if not bool(pair[1]):
				fails.append("%s %s" % [gname, pair[0]])
	print("[aipristest] 汇总：%d 条判据 × 2 组，失败 %d 条 %s" % [
		7, fails.size(), "→ 通过 ✓" if fails.is_empty() else "→ 失败 ✗ " + str(fails)])
	get_tree().quit()


## `--aipristest` 的单次采样：装载局面 → 落 P → 记提子项/目差/分项 → 悔回。
func _pris_probe_once(e: AIEngine, bd: Dictionary, v: int, on: bool) -> Dictionary:
	e.count_prisoners = on
	e.load_board_for_probe(bd, -1)
	var out := {"on": on, "before": e._pris_term(), "nc": 0, "after": 0.0,
		"undo": 0.0, "r": 0.0, "ab": 0.0, "aw": 0.0}
	out["nc"] = e._play(v)
	out["after"] = e._pris_term()
	out["r"] = e._result()               # 内部会写 `_last_area_*`
	out["ab"] = e._last_area_black
	out["aw"] = e._last_area_white
	e._undo()
	out["undo"] = e._pris_term()          # LIFO 回滚后必须回到落子前
	return out


## 从 `_result()` 反解裸目差（`_result_impl` = 0.5 + 0.5·tanh(sc/soft) ⇒ 可逆）。
## 反解而不是比胜率：胜率是压过的，差 1 目在不同分差下差出不同的胜率增量，
## 没有恒等关系可断言（铁律 §139：报告里出现「整数值」先疑计算路径）。
func _pris_score_from_result(r: float, soft: float) -> float:
	var x: float = clampf(2.0 * r - 1.0, -0.999999, 0.999999)
	return 0.5 * log((1.0 + x) / (1.0 - x)) * maxf(soft, 0.5)
