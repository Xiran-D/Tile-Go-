# ============================================================================
#  ai_engine.gd —— 瓷砖围棋 AI 引擎 v2
#
#  棋盘是“彭罗斯菱形瓷砖的邻接图”：共享边的瓷砖互为邻居，棋子落在瓷砖内。
#  引擎本身与几何无关，只依赖邻接表，因此换任何棋盘形状都可直接复用。
#
#  架构：MCTS + RAVE(AMAF) + PUCT 先验引导 + 强 Rollout 策略
#
#  为什么重写（v1 的 6 个致命弱点）：
#    1. rollout 75% 是纯随机落子 —— 随机走满一盘的结果近乎噪声，MCTS 学不到东西
#    2. 没有 RAVE —— 分支因子 90、模拟次数只有千级，每个根着法分到的访问太少
#    3. 每手从零建树 —— 上一次的搜索结果全部作废
#    4. 先验只在根节点生效且用 min-max 线性归一化 —— 分数被压扁，引导几乎失效
#    5. 节点 untried 是全盘 90 点（含非法点）且只试 24 次 —— 中后局展开大面积失败
#    6. 热路径每次迭代都 new S 对象、_group_of 每次分配数组、邻接表每次访问都装箱
#
#  v2 的对策：
#    1. 强 rollout：提子 → 逃叫吃 → 局部接触选点；禁止自填眼、禁止送吃
#    2. RAVE(AMAF) 与 MC 值按 β 混合，配合 PUCT 探索项
#    3. 树复用：用棋盘 diff 自动推导对手落子，把子树提为新根
#    4. softmax 先验（根，真正归一化的概率分布）+ 全树先验（内部节点）
#    5. 展开用全局随机排列 + 每节点随机偏移，O(1) 内存且不会漏着法
#    6. CSR 扁平邻接 + 单一可变棋盘 + move/undo 栈，热路径零分配
#
#  颜色常量与 game.gd 的 Stone 枚举一致：0=空 1=黑 2=白
# ============================================================================
class_name AIEngine
extends RefCounted

const EMPTY := 0
const BLACK := 1
const WHITE := 2

# ------------------------------------------------------------------ 可调参数
@export_group("时间预算")
## 每手思考毫秒数。不是“难度档位”，是性能/延迟旋钮，TAB 面板里可实时调
@export var time_budget_ms: int = 800
## 模拟次数上限（安全阀，正常情况下由时间预算先触发）
@export var max_playouts: int = 100000
## 后台并行搜索线程数：1 = 单线程；0 = 按 CPU 核数自动（上限 8）。
## 多线程能线性提高模拟次数，是提高棋力最直接的一档旋钮
@export var threads: int = 0

@export_group("搜索")
## 根节点最多保留的候选着法数（0 = 自适应）。
## 关键：分支因子上百时若全宽展开，每个根子节点平均只有 1~2 次访问，
## MCTS 会被方差淹没、退化成随机选点。剪枝把预算集中到少数好候选上
@export var root_width: int = 0
## `root_width = 0`（自动）时的根候选上限。默认 14：实测这个数量下每个候选能拿到
## 15~120 次真实访问，搜索才真正收敛（详见 `_effective_root_width` 的注释与 `--aibud`）
@export var auto_root_width: int = 14
## ---- 外部先验注入（2026-10-23，为「野马」`YemaAI` 而加）----
## `ext_prior` 非空且 `w_external_prior > 0` 时，`_prepare_root()` 会把根候选的排序与这份
## 按格点索引的分数**按名次混合**。空数组 + 0.0 = 完全走原路径，逐位等价于改动前。
##
## ★ 为什么是「名次混合」而不是「分数加权」：`_root_score()` 的量纲是几万（还含 `-0.5e9`
##   这种非法哨兵值），而神经网络输出只有 −4.5~−1.6。直接把两者相加，网络的贡献会被完全
##   吞掉，看起来"接上了"却一点效果都没有 —— 而且不报错。名次混合对量纲免疫。
## ★ 这个钩子只影响**根层候选顺序**，不碰 playout 评估、不碰硬过滤
##   （`_sealed_by_opp_hard` 等安全阀照旧先跑）。所以最坏情况是"先验更差"，不会下出非法手。
var ext_prior := PackedFloat32Array()
@export_range(0.0, 1.0, 0.01) var w_external_prior: float = 0.0
## 上一次 `_prepare_root()` 实际参与混合的候选数（0 = 没注入）。探针读它判"钩子到底跑没跑"。
var ext_prior_last_mix: int = 0
## 上一次混合**有没有真的换掉根层首选**（1 = 换人了，0 = 没换）。
## ★ 为什么光有 `ext_prior_last_mix` 不够：它只证明"钩子跑了"，**不证明网络对排序有任何影响**。
##   若 `ext_prior` 退化成常数（例如网络加载失败却返回全 0、或权重全零），混合后顺序
##   与原顺序逐位相同，`last_mix` 照样 > 0 —— 而实际是"装了网络等于没装"，**静默**。
## ⚠️ 但**这个量本身不能当判据**（2026-10-24 更正）：请改读下面的 `top1_is_net` /
##   `order_diff`。本量现在只是**信息量**（"网络把首选换掉过几次"），原因见下方 ★★。
var ext_prior_last_top1_moved: int = 0
## 新首选在**原始磐石排序**里的名次（0 = 磐石本来就这么选；-1 = 本次没混合）。
## 用于读"网络把一块原本排第 N 的候选顶上来"到底有多常见（信息量，不作单独判据）。
var ext_prior_last_top1_rank: int = -1
## ★★ 上面那个 `top1_moved` **不能单独当判据**（2026-10-24 踩到）：它只说明"首选换了人"，
##   而"没换人"有两种完全相反的原因 ——
##     ① 网络退化/写不回去（真故障，要红）；
##     ② 网络学得好、与磐石在首选上**判断一致**（正品，必须绿）。
##   本工程的训练标签就是**教师（`AIEngine`）自己的选点**（`GNN,L,` 行的 `teacher_v`）⇒
##   网络是磐石的学生 ⇒ 它会**越来越常**与磐石首选一致。用 `top1_moved` 当红条件，
##   等于"学生学得越像越判它坏"（§71 判据与数据矛盾 → 先疑判据 / §137 Goodhart）。
##   ⇒ 拆成下面两个**方向无关**的量：一个量"是否忠于网络"，一个量"排序是否真的动了"。
## 混合后的根层首选是否 = **网络自己的首选**（1=是）。`w=1` 时按名次混合的定义必然成立；
## 若为 0 则说明 `scores` 没写回 / `w` 没生效 / 排序口径被改坏 —— 都是静默故障。
var ext_prior_last_top1_is_net: int = 0
## 混合后排序与**磐石原排序**名次不同的点数（0 = 排序逐位没变 ⇒ 网络一个字的判断都没进来）。
## 与 `top1_moved` 的区别：它不看名次 0 那一个位置，所以"首选恰好一致"不会把它压成 0。
var ext_prior_last_order_diff: int = 0
## 本次实际用的混合权重（回调时读，供判据决定断言分支；-1 = 本次没混合）。
var ext_prior_last_w: float = -1.0
## 网络首选是否与磐石首选**本来就是同一个点**（1=一致，-1=本次没混合）。
## ★ 为什么要有这一位：`top1_is_net` 的**有效分母**就是"两者不一致"的局面。
##   若一批局面全是"一致"，`top1_is_net` 恒为 1、永远绿 —— 看着像通过、其实一次都没测到
##   （§106 有效分母=0 / §138 无输出型判据）。判据侧必须能把这个分母打出来。
##   2026-10-24 实测：`--yematest` 的 3 个固定局面恰好全一致（网络是磐石的学生）。
var ext_prior_last_top1_agree: int = -1
## rollout 最长手数上限（0 = 自动 min(n, 220)）。
## 大盘下完满一盘要数百手，截断后单次模拟明显变快（未定型的空区不计分）
@export var max_playout_moves: int = 0
## 终局评估是否扣除「只剩一口气的成块死子」。开着才学得会补活（关掉可对照测试）
@export var dead_penalty: bool = true
## 死子扣除的**闸门除数**：`empty_cnt * dead_fill_gate <= n` 才扣（值越大越严格）。
##
## · `6`（默认）= 空点 ≤ n/6 ⇒ 盘面填充 ≥83.3%，与 2026-10-27 之前的行为**逐位相同**。
## · `3` ⇒ 填充 ≥66.7%；`2` ⇒ ≥50%；`0` ⇒ **不门控，永远扣**。
##
## ★ 为什么要有这个旋钮（2026-10-28）：原来硬件写死 `* 6`。而生产档
##   `playout_cap_factor = 0.10` ⇒ rollout 只走约 12 手 ⇒ 叶子普遍停在中盘
##   **填充 50~70%** ⇒ 这道闸**几乎永远不开** ⇒ 叶子里「对手空里的死子」仍被当成活子计分
##   = 评估的**系统性偏差**（不是噪声）。实测铺到 75% 填充时命中率 15.8%，
##   而正常叶子根本到不了那个填充度。
## ⚠️ 口径：扣的是「只剩一口气的整块」。中盘那些只剩一气的块多半是**战术性叫吃**
##   （下一手就逃/吃掉对方），不是死棋 ⇒ 闸门放开**必然引入新的偏差**，方向未知。
##   ⇒ 这是个纯 A/B 问题，不许凭直觉定值。
@export var dead_fill_gate: int = 6
## 树的最大下探深度（手）。防极端情况下把整盘铺满而爆栈
@export var max_tree_depth: int = 40
## 渐进加宽系数 k：节点的子节点数上限 = clamp(ceil(k * visits^alpha), 1, widen_max)。
## 这是让搜索「有前瞻」的关键：子数上限随访问数缓慢放开，
## 于是早期能一路深潜（做活/对杀都是 3~5 手的连续手段），后期才逐步加宽比较更多着法。
## k=1（配合 alpha=0.5）即经典形式「子节点数 ≈ 访问数的平方根」
@export var widen_k: float = 0.7
## 渐进加宽指数 alpha（0.5 = 平方根增长，标准取值）
@export var widen_alpha: float = 0.5
## 单个节点的子节点数硬上限。围棋一个局面的高价值着法本来就集中在局部十余点，
## 不必按棋盘格数放开（否则预算又会被摊薄成"每子 1~2 次访问"的老问题）
@export var widen_max: int = 16
## 根节点 PUCT 探索常数（越大越倾向探索低访问着法）。
## 必须配 prior_visits 一起看：预算只有几百次模拟时，探索项一大，
## 搜索就会用噪声盖掉精心设计的先验，棋力反而下降（实测）
@export var c_puct: float = 0.35
## 树内部 PUCT 探索常数
## ★ 2026-09-27 起 = `--aitune` 爬山的跨盘冠军（pen+hat 双闸门，pw150 口径）：
##   原默认 0.7 → 0.92488。注意：这是 pw150（小预算）下的最优，实战预算更大时**未必**同值，
##   若要按实战工作点重调，用 `--aitune` + 工作区 `AI调参/ai_tune.py`（见技能 Part 14）。
@export var c_uct: float = 0.92488
## RAVE 等效访问数：越大越信任 AMAF 统计（小预算时应偏大）
@export var rave_equiv: float = 250.0
## 根子节点的先验虚拟访问数。
## 这是「谁说话算数」的旋钮：给得高，就必须积累更多真实模拟才允许推翻先验判断。
## 本引擎的先验（提子/救子/紧气威胁/连接/贴身应战/做眼）在几百次模拟的预算下比 MCTS 更可靠，
## 所以默认给足虚拟访问 —— 让搜索贴着先验走，只在证据充分时偏离（实测该配置远胜「剪枝+MCTS 主导」）。
## ★ 2026-09-27 起 = 跨盘冠军 10.5675（原 12.0；口径同 c_uct，pen+hat 双闸门 @pw150）
@export var prior_visits: float = 10.5675
## 内部节点的先验虚拟访问数
@export var prior_visits_inner: float = 1.0
## 终局分差软化系数：越小则胜负判定越接近二元（降低方差）
@export var score_soft: float = 7.0

@export_group("KataGo 借鉴（动态分中心 / LCB 选点 / 显然手早停）")
## 【动态分中心】效用按「本次 rollout 预计终局分 − 上一手搜索的平均预计终局分」计算，
## 而不是绝对目差（KataGo recentScoreCenter 思想，其 search.cpp 中
## recentScoreCenter = 当前期望终局分，效用围绕它做软截断）。
## 动机：绝对目差效用下，落后方「少输 2 目」与领先方「多赢 2 目」权重相同，
## AI 落后时会去堆目差而不是下最大的棋；重定心后效用衡量的是「比当前预期改善多少」。
## 首手前没有锚点（_dc_has=false）自动退化为旧行为；关闭后完全等价旧公式。
@export var dynamic_center_enabled: bool = true
## 0 = 完全按相对分（KataGo 默认）；1 = 完全按绝对分（等效关闭重定心）。
## 中间值 = 部分重定心（保留一点绝对目差态度）。
@export var dynamic_center_zero_weight: float = 0.0
## 相对分软截断半径 = sqrt(格数) × 该系数：个别 rollout 的极端分差超出半径后
## 对 tanh 的边际影响趋零，防止一次怪 rollout 把效用打满。
@export var dynamic_center_scale: float = 1.0
## 【LCB 选点】最终选点时对实测胜率做置信下界收缩：
## q_lcb = q − stdevs·sqrt(q(1−q)/V)，再走原有的证据收缩公式。
## 防止「真实访问只有几次、靠运气赢出来的高胜率」抢走选点（KataGo lcbStdevs=4，
## 但 KataGo 每手访问数以千计）。
## ⚠️ 实测（--aiablate lcb0，彭罗斯 120ms×120 手）：stdevs=2 在我们的访问量级
## （每手真实访问仅几十次）下惩罚过重，反而拖累棋力（2 局全负）→ 默认关闭。
## stdevs=1.0 的更温和档位留待后续消融（组键 lcb1）。
## 0 = 关闭（默认）。
@export var pick_lcb_stdevs: float = 0.0
## 【显然手早停】根层某手的真实访问数同时满足
## ① ≥ obvious_min_visits ② 占（前二名之和）比 ≥ obvious_share
## ③ 对第二名领先 ≥ obvious_lead（相对 top1）→ 提前结束搜索。
## KataGo obviousMovesTimeFactor 思想：显然手不值得烧满预算，玩家体感是 AI「秒下」。
@export var obvious_early_stop: bool = true
@export var obvious_min_visits: int = 80
@export var obvious_share: float = 0.45
@export var obvious_lead: float = 0.25

@export_group("影响力评估（influence）")
## 【大盘关键】rollout 被截断在中盘时，大片空区边界黑白都有子，传统「完全围住才计分」
## 一律判为中立 → 面积分退化成**纯子数差**，AI 学不到「围空」，只会往盘上堆子。
## 19×19（361 格）rollout 上限 160 手、填充率仅 44%，这个退化是致命的
##（彭罗斯 120 格能下满，所以同样的代码在小盘上没问题）。
##
## 开启后：未定型的空区按**影响力**分配 —— 每个空点归给「棋盘距离更近」的一方
##（多源 BFS，只经空点扩散，所以对方的墙会挡住影响力）。
## 这等价于 AlphaGo 里「价值网络」承担的角色：在局面未终了时给出合理的胜负估计。
@export var influence_enabled: bool = true
## 影响力最远扩散距离（超出该距离视为中立）。太小 → 大片空区无人认领；
## 太大 → 远方的子也会认领空地，估计变糊
@export var influence_max_d: int = 7
## 白方贴目（目）。**与 `game.gd::komi` 同口径**（0~12，默认 0）。
##
## ★★ 为什么引擎必须认识它（2026-10-02 加；之前本文件 `komi` 零命中）：
##   终局评估 `_area_score()` 返回的是「白 - 黑」的**纯盘面**目差，而游戏侧真正的终局
##   分数是 `total_white = stones_w + terr_w + white_prisoners + komi`
##   （`game.gd::_compute_scores()`，game.gd:9801）。**两边不同源 ⇒ AI 不知道自己有贴目。**
##   后果很具体：贴 7.5 目时 AI 仍按 0 目评估，白方该领先的形势它当平局甚至劣势，
##   于是**该收官时还在乱冲、该止损时不认** —— 玩家体感就是"AI 不会收官"。
##   ⇒ 修法：在**唯一的目差真源** `_area_score()` 的返回值上加 `komi`，
##     上层（`_result_impl` 的 tanh 压胜率、λ 混合、动态重定心、价值头锚点）
##     **自动全部继承** —— 不在每一层各写一遍（那正是"两份真相"那一族）。
## ⚠️ 口径纪律：白方贴目 ⇒ **加给白方**（返回的是 `白 - 黑`，所以是 `+komi`）。
##   若将来改成黑方贴目（棋盘大小/先后手补偿），这里要翻成 `-komi`，别只改 UI 标签。
@export var komi: float = 0.0
## 未定型空区「死区」宽度（2026-10-27 加，**默认 1 = 逐位复现旧行为**）。
##
## 【它改什么】`_area_score()` 对未定型空区逐点按「谁更近」归属。新增：
##   `db + dz <= dw` 判归黑、`dw + dz <= db` 判归白，**其余判中立**。
##   ⇒ `dz=1` 与原式等价（整数距离下 `db < dw` ⟺ `db + 1 <= dw`）—— 这一点是**逐位相等**，
##     可以拿 `--capftest` 同种子跑两次、6/6 选点必须一致来当免费的正向对照。
##
## 【为什么要它】离线 12613 对相邻手（同局真值恒等 ⇒ 差值全是纯误差）实测，
##   重尾的来源是**距离场在 `influence_max_d` 处的一道悬崖**：一颗新子能把对侧从
##   「够不着（-1）」变成「6~7 步」⇒ 该点从独占跳到可争夺，一次翻一大片。
##   适度死区把「差 1~2 步」这种**没有分辨力**的比较判中立，从而压掉尾部。
##
## 【已测的权衡（valuenet 离线，`nn/probe_area_variants.py`，基线逐位等于数据集 `r.area`）】
##   dead   配对std  std比值s  P95    %>10   MAE
##   0(旧)   17.014   1.000    24.7   6.7%   30.994
##   2       17.882   1.051    21.3   6.2%   30.758
##   4       17.931   1.054    19.5   6.0%   30.704
##   6       18.694   1.099    17.3   5.8%   30.577
##   ⇒ **不是免费午餐**：尾部（P95/-21%）换离散（std +5.4%）。取 2~4，别取 8。
##
## ⚠️ **改这个必须同时改 `score_soft`**：std 上升意味着 `_area_score` 的尺度变了，
##   `tanh` 的工作区间跟着变。离线给的换算是 `score_soft_eff ≈ score_soft × s`（s 见上表）。
##   只动 dz 不动 score_soft = 两个旋钮混在一起（§47），对打会读出"AI 变保守"这种假象。
## ⚠️ 默认值**必须是 1**，不能是 0：`dz=0` 会把「两边同距」也判归黑（`elif` 顺序偏置），
##   **那是对旧行为的一次静默偏置**，不是"关闭新功能"。
@export var infl_dead_zone: int = 1

## 影响力**源门控**（2026-10-27 加，默认 **0 = 完全关闭、逐位复现旧行为**）。
##
## 【它改什么】`_influence_dist()` 目前把「该色的每一个子」都当等价的辐射源（逐点播种）。
##   于是一颗**只剩 1 气的弃子**与一条 30 子大龙，对周边空区的影响力完全相同 ——
##   引擎会认为「马上要死的子」稳稳控制着它周围的空，这是系统性高估。
##   开启后：气数 ≤ 本值的**整块棋不做辐射源**，但它**仍然是墙**（仍是子，照样隔断对方）。
##
## 【为什么这是独立维度】`influence_max_d` 改的是**量程**、`infl_dead_zone` 改的是
##   **距离比较的死区**；两者都碰不到「谁有资格辐射」这一维（§47 一次只动一个轴）。
##
## 【为什么默认 0 而不是「等价旧行为的某个值」】本旋钮没有「等价写法」：
##   `0` 表示不做门控（关闭）；`1` 已经会把所有 1 气块排除。两种约定别混（同 `dead_penalty`）。
##
## ⚠️ 依赖调用顺序：门控里要调 `_group()`/`_libs()`，它们占用 `_gst`/`_gid`。
##   安全的前提是 `_area_score()` 里 `_influence_field()` 在 `_gid += 1` **之前**。
##   若将来把影响力改成「懒化到空区循环里再算」，本门控会把空区 flood fill 拦腰截断
##   （`_gst` 被覆写）⇒ 静默漏算空区。改懒化前必须先解决这个耦合。
@export var infl_src_min_libs: int = 0

## ★★ 叶子评估是否计入**提子项**（2026-10-27 加，默认关 = 逐位复现旧行为）。
##
## 【为什么要它】引擎原先的 `_area_score()` 只算「盘上子数 + 领空」，而工程里分数的
##   **唯一真源** `rules_kernel._compute_scores()`（以及 game.gd 的注释口径）是
##   `total = 盘上子 + 领空 + 提子数`。于是：
##     total 差 = `_area_score()` 返回值 + (白提子数 − 黑提子数)
##   ⇒ 引擎原来**把提子按零价计**（被提的子从盘面消失，却没有任何人因此得分），
##     而不是半价 —— 少掉的正是 `(提子差)` 这一整项。
##   代数检验：白提 5 子后，白方盘面 +1 子、空区可能 +5 点、**黑方少了 5 子**；
##   真值总差里那 5 子归白方（`white_prisoners`），而 `_area_score()` 只让黑方少 5
##   ⇒ 白方净赚被低估 5 目。整盘被提光时低估可达上百目 ⇒ 与实测崩盘形态吻合
##   （226:1、180:17，AI 该吃不吃、该逃不逃）。
##
## 【口径边界】**只加在搜索效用里**（`_result_impl()`），**不动 `_last_area_*`**：
##   后者的读者是分析层（`--anlz*` / `--areatest`），那里的语义是「盘面目数」，
##   改成含提子的总分会让一批既有判据的期望值整体漂移（铁律 8：一处写一处读）。
##
## 【计数器口径】`_pris_b/_pris_w` = **本手搜索以来**（`_search_budget()` / `reset_state()`
##   清零）双方各自的提子数。根节点之前的历史提子**不计入** ⇒ 相当于假定
##   根节点时双方提子相等；这是个**只影响分中心饱和点、不影响叶子间排序**的常数
##   （tanh 单调），而 A/B 判据（`--aispec`）比的是选点分布，对这种常数不敏感。
@export var count_prisoners: bool = false
## 【AlphaGo 的 λ 混合】终局评估里「静态评估」占的权重（0 = 纯 rollout，1 = 纯静态）。
##
## 为什么需要它 —— 这是大盘棋力的第二个主杠杆，动机与 AlphaGo 用价值网络**完全相同**：
## 单次 rollout 的方差极大（实测 19×19 上即使下满，同一局面两次 rollout 的分差
## 平均也能差 47 目），而 MCTS 的每一次迭代都在拿这个噪声当信号。
## 静态评估（子数 + 围空 + 影响力）是**确定性的、零方差**的，
## 把两者加权平均，等于用零方差分量稀释掉一部分 rollout 噪声 ——
## AlphaGo 2015 论文用的正是 `v = (1-λ)·rollout + λ·value_net`，λ=0.5。
##
## ⚠️ 两分量必须量纲一致：这里都是「白 - 黑」的目差，可以直接加权。
## λ=0 时完全等价于旧行为（连 `_area_score` 都只调一次，无额外开销）。
##
## 取值不是拍脑袋定的，是 `--ailam` 量出来的（原理见该探针注释）：
## 混合值的均方误差 MSE(λ) = (1-λ)²σ² + λ²b²，对 λ 求导得 **λ* = σ²/(σ²+b²)**
## （σ = rollout 噪声标准差，b = 静态评估偏差）。
##   19×19：σ=65.6 目、b≈15 目 → λ*≈0.92
##   彭罗斯：σ=17.7 目、b≈10 目 → λ*≈0.59
## 但**实测 λ* 并不是最优棋力**：λ=0.92 对局 366:370（无效，甚至略负），
## λ=0.5 却是 573:304。原因是 λ→1 时 rollout 的死活推演被完全丢弃，
## 而那部分信息是静态评估给不了的 —— 所以取 0.5（与 AlphaGo 论文一致），
## 落在大盘 λ* 的左侧、小盘 λ* 的附近，两盘都稳。
@export var eval_mix_lambda: float = 0.5

## ★ 根先验 17 项的**顺序真源**（第二档训练落盘口径）。
##   `game.gd` 的 `AIDATA_W` 直接引用本常量 —— 两边各写一份必然漂移
##   （特征错位一位时全盘静默：训练器照样收敛，只是学到错的权重）。
##   索引同时是 `_root_terms()` 里 `_rt[]` 的槽位号。
const ROOT_W: Array[String] = [
	"w_cap_bonus", "w_cap_each", "w_save_each", "w_ladder_run", "w_threat_each",
	"w_ladder_good", "w_ladder_bad", "w_self_atari", "w_lib", "w_tighten",
	"w_conn", "w_center", "w_local", "w_weak_each", "w_eye_make", "w_kill_point",
	"w_fill_own_eye",
]
## `_root_terms()` 的产物：前 17 项 = 各 w_* 的原始量，末项 = emp_nb。
var _rt := PackedFloat32Array()

@export_group("先验权重")
@export var w_cap_bonus: float = 30.0     # 只要能提子就有的固定奖励
@export var w_cap_each: float = 16.0      # 每提一子
@export var w_save_each: float = 13.0     # 每救回一子（己方被打吃的组）
@export var w_self_atari: float = -16.0   # 送吃惩罚
@export var w_threat_each: float = 10.0   # 把对方某组打成一气（按对方组规模加权）
@export var w_lib: float = 2.2            # 己方气数
@export var w_conn: float = 1.5           # 连接己方子
@export var w_local: float = 2.93695      # 贴身应战（紧邻对手上一手）★ 跨盘冠军（原 2.5，口径同 c_uct）
@export var w_center: float = 1.5         # 中心偏好
@export var w_weak_each: float = 3.0      # 补强「只剩 2~3 气且尚未活」的己方块（每子加权）
@export var w_eye_make: float = 14.0      # 此手能让己方某未活棋块多出一只「单点真眼」
## 【真·自紧气惩罚】未提子、贴己方、又不带来任何新气的落子（gate 口径的 tighten 类）。
## 依据 game.gd `_ai_move_gate` 的拆分（2026-09-19 实测）：lib_drop 总数里一半是连通（正手），
## 剩下里「己方空区做眼」也是正手 —— 只有「既不连通、也不在己方空区」的才是真自紧气。
## 只罚这一类（判据与 gate 完全同口径，见 _root_score 内注释）。0 = 关闭（阴性对照）。
@export var w_tighten: float = -6.0

## 【白填己方眼位】落子自己在「小眼位空间」里、却**不是要点** —— 白送一手，且会毁掉活形。
##
## 为什么必须单独罚（三项机制叠加起来把这件事变成了**正分**，2026-09-21 实测）：
##   · 「做活豁免」把整片己方眼位空间开闸（那是为了让**要点**能被选中）→ 里面的非要点也成了候选；
##   · 它们拿不到 `_eye_vital_bonus()`（不是要点）；
##   · 又躲过了 `w_tighten`（`_root_region_has_enemy()` 判「己方空区做眼 = 正手」→ 豁免）；
##   · 还照吃 `w_conn` 的贴己方子奖励（眼点四邻全是自己子 → 拿满）。
## 只罚**非要点**：要点是棋理上唯一值得下的点（直三的中、梅花五的心、刀把五的腰），
## 其余点落下去会把活形毁掉（梅花五填一臂 → 变丁四 → 反而成死形）。
## 权重按 `sqrt(块大小)` 缩放。`0` = 整条关掉（回退旧行为做 A/B）。
@export var w_fill_own_eye: float = -10.0

## 【分析门槛与权重解耦】（2026-09-27，第二档训练的前提）：下面三条「要不要做这项分析」
## 必须是**布尔开关**，不能借「权重 != 0」来当开关。原因：权重基分解（`--aidata`，策略头
## 训练的特征仪器）要求打分对 17 个 `w_*` **纯线性** —— 借权重当开关会让「权重=0 的世界」
## 走上另一条分类路径（实测：`w_ladder_run=0` 时逃征子推演被跳过 → 救回数把「逃了也白逃」
## 的子也算进去，同一局面的恒等式 base+Σw·f=orig 差出 91 分）。想**彻底关掉某项的打分**，
## 仍把对应权重设 0 即可（`s += 0` 恒等，行为与旧「0=关闭」完全一致），只是分析照跑
## （A/B 消融多付一点推演开销）。
@export var ladder_escape_check: bool = true   # 逃征子判定（区分「救回」与「逃了也白逃」）
@export var tighten_check: bool = true         # 自紧气识别（判据与 gate 同口径）
@export var fill_own_eye_check: bool = true    # 白填己方眼位识别（依赖通用眼位死活）

# ---- 价值头（2026-09-28，第二档）----
# 训练口径（aidata_value_train.py，15 局 960 样本，验证 MAE 72 目/基线 101、方向命中 79.8%）：
#   落子后轮到对方行棋 → 特征从**对方**视角算（「own」= 对方的子），预测对方的终局目差，
#   取负 = 我方目差，乘 value_blend 混入 _root_score。单位 = 目，与分数量纲同阶。
# 权重语义：own_* = 当前行棋方（=落子后的对方）的棋块；y 拟合自 --aidata 自战对局。
@export var value_blend: float = 1.0           # 混入增益。★ 2026-09-28 裁判升位：
											   # --aitune=pen,hat:r2:ms8000:pw150 A(=1.0) vs B(=0)
											   # 总账 7:1（彭罗斯 3:1 目差+235，爱因斯坦 4:0 目差+561）。
											   # 单位 = 目，与分数量纲同阶，1.0 即训练口径原样混入。
@export var v_own_atari_st: float = -3.9488    # 行棋方被打吃的子数 → 每子约 -4 目
@export var v_own_atari_grp: float = 6.3512    # 行棋方被打吃的块数
@export var v_opp_atari_st: float = 4.3722     # 对方被打吃的子数 → 每子约 +4 目
@export var v_opp_atari_grp: float = -9.1034   # 对方被打吃的块数
@export var v_own_2lib_grp: float = -0.2615    # 行棋方两气（薄棋）块数
@export var v_opp_2lib_grp: float = 7.1209     # 对方两气块数
@export var v_stone_diff: float = 2.6948       # 盘面子数差 → 每子约 +2.7 目
@export var v_bias: float = 0.8102             # 偏置

@export_group("通用眼位死活（做活 / 点杀）")
## 总开关。关掉后退回旧的「单点真眼 + 气≥6」口径 —— 自检靠它做**阴性对照**
## （关掉必须答错，否则说明断言根本没在测这套机制）。
@export var ld_enabled: bool = true
## 串的气超过这个数就判活（不启动穷举）。大龙在随机对局里基本杀不掉，
## 与旧实现「气≥6 判活」同精神；数值=6 时行为与旧口径最接近。
@export var ld_max_libs: int = 6
## 眼位空间点数上限。超过就判活（取宽）—— 2026-09-20 定标（真源 8 点抽样，见
## 死活真源/结果_8点定标.txt）：**旧值 6 有已知反例** —— 7 目阶梯形（P 形）是未定形，
## 判活会让 AI 既不补活也不点杀。7 目形全部可在预算内精确解（节点中位 ~4900、最大 5900），
## 8 目形全部超 8000 预算（127/127 抽样）→ 7 是「能精确解」与「只能判活」的分界线。
## 上限内精确穷举（含杀点集），超上限直接判活 —— 既省算力又不丢能解的结论。
@export var ld_cap_points: int = 7
## 单次死活穷举的节点预算（硬上限，保证先验开销可控）。只对**真正递归展开**的节点计数
## （命中记忆的调用不计）。2026-09-20 定标：7 目眼位加早退剪枝后 1200~4700 节点，
## 8000 覆盖全部 7 目形；8 目形 9900~15700 节点，本来就该由 cap 挡住。
## 超预算则判活并计一次 `last_ld_bailouts`（自检盯着：恒为 0 才说明预算够）。
@export var ld_node_budget: int = 8000
## 【2026-10-05 标注为废弃别名】根先验里「值得做死活分析」的**眼位空间点数**上限。
##
## ⚠️ **它已被 `ld_cap_points` 取代，且本变量从未被引擎读取过** —— 改它没有任何效果，
##   而 `game.gd` 的性能提示文案还在让用户「调小 ld_probe_libs」，是实打实的误导。
##   保留它只为不破坏外部可能存在的赋值，并由 `_sync_ld_caps()` 保证二者同步。
## 历史（从注释链可读出）：本项默认 5 → `ld_cap_points` 试过 6（「有已知反例：7 目阶梯形
##   P 形是未定形」）→ 定标 7（7 目形全部可在预算内精确解，8 目形 127/127 超 8000 节点预算）
##   ⇒ **「5 = 覆盖全部 7 目形」这句里的 7 指的是目形数，与点数上限同量级**。
@export var ld_probe_libs: int = 5
## 点杀要点奖励：这一手落在**对方未定形棋块**的眼位要点上 —— 即「攻方先手落此点可杀」的点。
## 每子 sqrt 加权。旧版取值口径是「让对方由非死变死」，但眼位空间一旦被攻方踏进去就不再
## 「封闭」，判定层只会给出 UNSETTLED，因此那个口径实测**永远不触发**（已改成要点集判定）。
@export var w_kill_point: float = 16.0
@export_group("征子判定（ladder）")
## 征子（追吃）成立时的额外奖励：把对方大串打到 1 气、且对方沿气逃也逃不掉。
## 没有这一项时，「叫吃」一律按 w_threat_each 加分，于是 AI 常走无效叫吃（对方一长就跑掉，
## 还帮对方走厚）。这是本引擎此前最明显的战术盲区。
@export var w_ladder_good: float = 20.0
## 判定为「无效叫吃」（对方长气后气 >= 3，征不掉）时的惩罚
@export var w_ladder_bad: float = -9.0
@export var ladder_min_size: int = 3      # 只对 >= 该子数的对方串做征子推演（小子无所谓）
@export var ladder_max_plies: int = 22    # 推演上限（超步保守判「逃得掉」）。
#   2026-09-20 由 14 提到 22：分支化实测（ladtest ⑤），沿边廊的标准征子要 13~14 层
#   才打到边界，14 正好卡线 bail 成「逃得掉」—— 判定系统性偏保守。开销由 ladtest ③ 盯。
## 总开关。关掉后回退到旧行为（叫吃一律按 w_threat_each 加分）。
## 主要用途是 A/B 对照：判定「棋力变化」到底来不来自征子，以及测它对 playouts 的开销。
@export var ladder_enabled: bool = true
## 逃征子惩罚（2026-09-20 新增）：己方串被打吃、逃出去之后攻方按同一套推演仍征得死
## → 逃跑是废手（白送对方继续走厚）。这类「逃」不给 w_save_each 奖励，改给这笔小额惩罚
## （宁可在别处制造反制手段也不要白跑）。0 = 关（恢复旧行为：一律给逃跑奖励）。
@export var w_ladder_run: float = -6.0
## 征子分支推演的节点预算（2026-09-20 续打分支化：所有叫吃点全试，任一征死即成立）。
## 超预算保守判「逃得掉」（与 ladder_max_plies 同向）。ladtest ③ 盯总开销。
@export var ladder_node_budget: int = 600
## 根先验 softmax 温度：越小则先验越尖锐（好棋拿到越高的探索权重）
@export var prior_temp: float = 0.28
## 最终选点时「实测胜率」相对「先验」的最大权重（0 = 纯先验；见 `_pick_merged`）。
## 实际生效的权重还会被样本量收缩：真实访问数 V 越少，权重越低。
@export var prior_pick_weight: float = 0.6
## 证据收缩强度：score = 先验 + w×(真实胜率-先验)×V/(V+evidence_k)。
## 调大 → 需要更多访问数才肯偏离先验（更稳、更省时间）；调小 → 更信搜索
@export var evidence_k: float = 10.0

@export_group("全局局势分析（analyze_board）")
## 是否启用「死子目不计负分」的真负分。这是本层对 AI 行为影响最大的一项：
## 关掉时死子与活子一样计入面积评估 ⇒ AI 落后时宁可在对方地盘落子也不救自己的死块。
@export var score_true_live: bool = true
## 胜率→ 行动的映射：落后多少才进入「止损模式」（0 = 永不止损，永远按最优play）。
@export var advice_deficit: float = 0.12
## 「已被对方围死、攻不进去」的地盘权重：这类空点落子只是自填，评估里要压到接近 0。
@export var w_sealed_territory: float = -6.0
## 救自己可做活块的额外权重（叠在 _root_score 之上，见_analyze_bonus）。
@export var w_rescue_own_live: float = 18.0
## 抢对方死子的额外权重（对方已死块里的空点 = 真目）。
@export var w_capture_dead: float = 12.0
## ★★ 2026-10-08 新增：把 ③（`w_sealed_territory`）从**软权重**升级成**硬过滤**。
## 【为什么必须换机制】③ 的确定性裁决（`--anlzdir` 16 局面）：它确实触发（11 次 / 8 局面）、
##   Δmax 恰好 6.00（仿射✓）、跨实现分岔 0 —— 但**目标排名全是最后一名**（`rk0 ≈ el`），
##   +6 只把 D14 从 35 挪到 33（共 36）⇒ `内K 0→0→0`、`冠 0/0/0`。
##   ⇒ 它罚的点本来就沉底 = **冗余惩罚**（铁律 69）⇒ 调权重永远不会有可测效应。
## 【空区边界构成直方图给的出路】（16 局面 / 468 空点，口径 = 数**去重边界子**）
##   桶1「己方地盘」13 点 ⇒ **进前K 0**（`_own_territory_only()` 是**硬过滤**，真做到了）
##   桶4「对方占 75%~99%（混了一颗己方子）」4 点 ⇒ **进前K 2**（最好名次 8）
##   桶5「边界全是对方」11 点 ⇒ 进前K 1（最好名次 9）
##   ⇒ 对比干净：己方侧靠硬过滤做到 0 漏，对方侧只靠软权重 ⇒ 漏的就是桶 4/5。
@export var use_sealed_hard_filter: bool = true
## 对方**边界占比**阈值。0.75 = 扩面（桶4+桶5 都拦）｜0.999 = 只拦「边界全是对方」（桶5）。
## ⚠️ 用乘法比较（`p < θ·tot`）而不是除法，省掉除零判断与浮点边界歧义。
##
## ★ 默认 0.75 是**实测定的**（`--sealhard`：真 120~150 格盘 × 12 局面 / 454 个空点）：
##     θ=0.999 → 剔除 65 ｜ 其中进前K 19 ｜ **其中本来是冠军 0**
##     θ=0.900 → 剔除 65 ｜ 进前K 19 ｜ 冠军 0
##     θ=0.750 → 剔除 72 ｜ 进前K 21 ｜ **冠军 1**   ← 扩面多拦的那 7 个点里就有 1 个是冠军
##     θ=0.500 → 剔除 112（24.7%）｜ 进前K 38 ｜ 冠军 2 ｜ 但**开始出现 10 点以上的空区**
##   ⇒ 「扩面」才是收益所在（0.999 档拦不住任何一手真会下的棋）；0.5 档太狠，不取。
##   ⇒ 想更保守就把本值调回 0.999（一个旋钮，运行期可调）。
@export var sealed_hard_share: float = 0.75
## 被拦空区的**点数上限**（0 = 不限）。**这是棋理安全阀**：大面积空区即使边界全是对方，
##   也可能是可打入/可做活的战场，不该硬拦。
##   ★ 实测被剔空区的**最大点数 = 8**（θ=0.75 档；θ=0.999 也是 8，θ=0.5 才升到 10）
##     ⇒ 默认 0（不限）在本样本上**不 binding**；要给棋理再加一道保险可设 6
##     （代价：放过 7 个落在 7~9 点空区里的候选，见 `--sealhard` ⑥ 的分布列）。
@export var sealed_hard_max_size: int = 0
## 安全阀下限：硬过滤**不许**把候选剔到少于这个数（默认 1 = 只在真会被剔空时整批放行）。
##   为什么必须有：`choose_move()` 拿到空候选会**直接返回 -1（停一手）**，
##   那会被读成"AI 主动弃权"，而绝大多数局面下这是错的（真该弃权是终局收完的时候）。
##   ★ 实测（θ=0.75）：过滤后候选数**最小值 = 1**（有个局面 el=9、被剔掉 8）⇒ 安全阀没触发
##     但贴着边。想让 AI"至少有两个选择"可以调到 2~3（代价：那些局面退回全放行）。
@export var sealed_hard_min_cands: int = 1
## 局势分析的区块缓存上限（块数远小于 n，此值只防极端盘型）。
@export var analyze_max_blocks: int = 400

@export_group("Rollout 策略")
@export var p_capture: float = 0.93       # 有子可提时执行提子的概率
@export var p_save: float = 0.90          # 己方被打吃时逃跑的概率
@export var p_no_self_atari: float = 0.92 # 拒绝送吃的概率
## 己方有「只剩 2 气且未活」的棋块时，优先在其气点补活的概率。
## 注意不能给太高：rollout 里若双方都忙着补活，随机对局会变得"只守不攻"，
## 胜率估计随之系统性偏向防守方，AI 实战会变消极（实测 p_eye=0.8 会掉棋）
@export var p_eye: float = 0.30
## rollout 最长手数 = n * 该系数（过短则终局评估不可靠，过长则拖慢模拟）
## ★★ 2026-10-27：**`<= 0` 是一个独立模式，不是"很短的 rollout"** —— 叶子**完全不跑随机对局**，
##   效用只由静态评估决定。依据（实测，见 `.workbuddy/memory/2026-10-27.md`）：
##     · 120 格盘上 rollout 噪声 σ≈24.6 目，而候选手之间的真实价值差只有 ~6 目
##       ⇒ 单次 rollout 的信噪比 0.24，几乎不携带信息；
##     · rollout 吃掉单次模拟 98% 的时间（37.6µs × 116 手 vs 静态评估 87µs）
##       ⇒ 它同时是最贵与最不准的那一半；
##     · 12 局换色实测：短 rollout（12 手）+ 5 倍模拟 打赢 长 rollout（116 手），8:4、
##       目差 +12.1，且每手耗时更低（549ms vs 587ms）。
##   机理：**偏差在同层兄弟候选之间大体相消**（它们吃的是同一份系统性偏差），独立噪声不相消
##   ⇒ 选点时"低方差有偏"优于"高方差无偏"。（§16 配对优于跨样本的同族道理。）
##   ⚠️ 刻意**不**复用 `eval_mix_lambda`：λ 是"两个分量如何加权"，本开关是"要不要第二个分量"；
##   合成一个旋钮会出现"λ=1 却仍在跑 rollout"这种自相矛盾的状态（§118 一个量不要两种语义）。
##
## ★★ 2026-10-27 默认值 **1.0 → 0.1**（rollout 116 手 → 12 手）。这是本轮唯一通过显著性检验的改动：
##   52 局换色（三批独立种子 12+24+16），A=旧默认 vs B=本改动（pw 从 60 提到 300 补齐算力）：
##     批次1 seed 20261027：B 8:4（66.7%）｜批次2 seed 20261029：B 15:9（62.5%）
##     批次3 seed 20261031：B 14:2（87.5%，z=+3.00）｜**合计 B 37:15 = 71.2%，z=+3.05，p≈0.002**
##   三批方向一致，且**每一批 B 的每手耗时都更低**（549/509/445ms vs 587/562/509ms）
##   ⇒ 「同等甚至更省的时间下更强」，不是拿时间换的。
##   ⚠️ 验证范围：**只有 120 格的彭罗斯标准盘**。360 格加强盘未做 A/B（rollout 会变成 36 手，
##   而 `_effective_playout_cap` 的旧注释记载"实测过 96 手会掉分"）⇒ 换大盘前请先跑
##   `--aispec=r6:pw60:a=playout_cap_factor=1.0:b=playout_cap_factor=0.1:es0`。
@export var playout_cap_factor: float = 0.1
## 每隔多少手做一次全盘叫吃扫描（其余手只扫上一手附近）。
## 调大 → 更快但可能漏掉远处的叫吃；调小 → 更准但更慢
@export var full_scan_every: int = 14
@export var wq_own: float = 1.3           # 安静手：邻接己方子的权重
@export var wq_opp: float = 0.9           # 安静手：邻接对方子的权重
@export var wq_emp: float = 0.12          # 安静手：邻接空点的权重
## 【性能开关，仅供基准对照】rollout 里「送吃判定」的 BFS 守卫是否用收紧版。
## true（默认）= 仅当落点空邻点 <2 时才做 BFS。落点有 ≥2 个空邻点时，合并后的棋块
##   气数必然 ≥2（空邻点互不相同，且提子只会让空点变多），送吃判定不可能命中，
##   所以这次 BFS 是纯浪费；旧守卫写作 `own == 0 and emp >= 2`，own > 0 时同样成立却没被利用。
## false = 退回旧行为（每次都做 BFS）。两条路径的**棋力完全相同**，
##   可在 `--aibench` 里同进程 A/B 测出真实提速比，不受多进程抢 CPU 干扰。
@export var narrow_self_atari_guard: bool = true
@export var wq_center: float = 0.6        # 安静手：中心偏好
@export var wq_local: float = 1.2         # 安静手：紧邻上一手

# ------------------------------------------------------------------ 图（CSR）
var n := 0
var adj: Array = []                    # 原始邻接表（外部传入，仅作留存）
var _as := PackedInt32Array()          # adj_start，长度 n+1
var _af := PackedInt32Array()          # adj_flat，长度 2E
var _deg := PackedInt32Array()         # 每点度数
var _cent := PackedFloat32Array()      # 中心度 0=边界 1=最深内部

# ------------------------------------------------------------------ 搜索棋盘
var ai_color := WHITE
var _b := PackedByteArray()            # 当前棋盘（唯一可变权威状态）
var _ko := -1
var _turn := BLACK

# BFS 缓冲（全部预分配，热路径零分配）
var _gst := PackedInt32Array()         # 串 BFS 访问标记
var _gid := 0
var _gbuf := PackedInt32Array()        # 串成员缓冲
var _gbuf2 := PackedInt32Array()       # 空区域 flood fill 缓冲（终局计分）
var _lst := PackedInt32Array()         # 气统计标记
## ★ `_sealed_color()` 专用标记（2026-10-06）。**不可复用 `_gst`**：
##   `_gst` 是 `_group()` 的 BFS 标记，覆写它会把串拦腰截断（实测漏掉一半块）。
var _ast := PackedInt32Array()
var _asid := 0
## ★ `_area_score()` 最近一次扫描的双方分项（黑绝对面积 / 白绝对面积）。
## 有了它，调用方不必再把净值当绝对值用（见 `_decide_win_rate`）。
var _last_area_black := 0.0
var _last_area_white := 0.0
## ★ 局势缓存（2026-10-06）：`analyze_board()` 的结果，按 `_sc_id`（局面版本号）失效。
## `_root_score()` 每个候选点都会调它 ⇒ 不缓存就是 n 次全盘扫描（太贵）。
var _an_cache: Dictionary = {}
var _an_cache_id := -1
## 局势加成是否已并入 `_root_score`（可在自检里单独关掉做 A/B）。
@export var use_analyze_bonus: bool = true
var _lid := 0
var _libs_last := -1                   # _libs() 顺带记录最后一口气
var _cst := PackedInt32Array()         # 提子/威胁扫描去重用
var _cid := 0
var _cst2 := PackedInt32Array()        # 己方组扫描去重用
var _cid2 := 0
var _sst := PackedInt32Array()         # rollout 扫描去重用
var _sid := 0
var _cbuf := PackedInt32Array()        # 本次落子的提子结果

# move/undo 栈（LIFO，回退顺序与落子顺序严格相反）
var _ply := 0
var _mv_st := PackedInt32Array()
var _nc_st := PackedInt32Array()
var _ko_st := PackedInt32Array()
var _tn_st := PackedInt32Array()
var _capst := PackedInt32Array()
var _capsp := 0
## 本手搜索以来的提子数（**只有 `count_prisoners` 为真时才被读取**，见该参数声明处）。
## 写入点在 `_play()`/`_undo()`（O(1)，且 `_undo()` 严格 LIFO ⇒ 直接相减即可）。
var _pris_b := 0                        # 黑方提掉的白子数
var _pris_w := 0                        # 白方提掉的黑子数

# ---- 统计计数器（2026-10-27 加）：**只自增、只打印，不参与任何分支**
# 为什么要它们：下面三个比值现在全是**估计**，而它们直接决定排期：
#   · `_dead_hit/_area_calls`      = `_dead_correction` 真实触发率（估 15~30%，hotpath 推导 [未测]）
#   · `_influence_need/_area_calls`= `_influence_field()` 在真实叶子上"确实需要"的比例
#                                    （决定"懒化"能省多少：估 <50% [未测]）
#   · `_scanall_calls/_playout_calls` = 每叶子全盘扫描次数（**推导 0.857，核心假设"相位均匀"未验证**）
# 铁律 §147：这三条一律不许当成已测结论往报告里写，直到 `--aiprof` 真打出数字。
var _area_calls := 0
var _dead_hit := 0
var _influence_need := 0
var _scanall_calls := 0
var _playout_calls := 0

# 本轮迭代的走子日志（供 RAVE/AMAF 回传）
var _log := PackedInt32Array()
var _logc := PackedInt32Array()
var _logn := 0

# RAVE 统计（根节点视角）
var _aw := PackedFloat32Array()
var _an := PackedFloat32Array()
# ---- 动态分中心状态（上一手搜索的预计终局分作为本手效用锚点）----
var _dc_center := 0.0      # 锚点：上一手搜索所有叶子 rollout 分（白-黑）的平均值
var _dc_has := false       # 首手搜索前 false → 效用退化为绝对分（旧行为）
var _dc_sum := 0.0         # 本手搜索期间收集的叶子分累计
var _dc_n := 0.0
## 叶子分**方差**累加器（2026-10-27 加，只为可观测量：不动任何分支）。
## 为什么需要它：`--capftest` 量的是**选点**，量不出**叶子值方差**——而「离线
## 抖动降 31%」这类改动的唯一实测通道就是方差。没有 σ 就无法判断它一阶在哪。
var _dc_sq := 0.0
## 上一手搜索的叶子分标准差（`_dc_finalize()` 结算，供 `--aiprof`/`--capftest` 打印）。
## ⚠️ 这是**绝对分**的 σ（含提子项、含贴目），与 `_area_score()` 的 σ 差一个常数平移，
##   标准差对常数平移不变 ⇒ 两者**相等**，可以直接与离线的「目」级 std 对照。
var _dc_std := 0.0
## 已结算过的 σ 的累计均值（跨手；只看趋势用，不参与决策）。
var _dc_std_sum := 0.0
var _dc_std_cnt := 0.0
var _dc_collect := false   # 只在主入口的搜索期间收集（探针/自检的手动调用不污染锚点）

# 全局随机排列：节点展开顺序 = _perm[(off + k) % n]，每个节点只存 off/nxt
var _perm := PackedInt32Array()

# 树复用
var _tree: MNode = null                # 树复用：上一次搜索的根（null = 无树可复用）
var _tree_move := -1                   # 我方上一手的落点
var _prev_board := PackedByteArray()
var _has_prev := false

# 迭代期路径缓冲（复用）
var _path: Array[MNode] = []

# rollout 候选缓冲（复用，避免每手分配）
var _cappts: Array[int] = []
var _capsz: Array[int] = []
var _savepts: Array[int] = []
var _qpts: Array[int] = []             # 安静手候选（上一手两圈内的空点）
var _lpts: Array[int] = []             # 局部叫吃扫描的起始点
var _scan_cnt := 0
var _bpts := PackedInt32Array()        # 空区边界上的棋子点（归属/死活判定用）
var _eye_st := PackedInt32Array()      # 眼位去重标记
var _eye_id := 0
var _gmark := PackedInt32Array()       # 组内点标记（值 = 组标记号），供眼位判定查「是否属于本组」
var _gmark_id := 0
var _weak := PackedInt32Array()        # 己方「未活且气少」的棋块，其气点作为补活候选
var _ladbuf := PackedInt32Array()      # 征子推演：某串的气点（_atari_point 用）
var _lad_nodes := 0                    # 征子分支推演节点计数（每次判定重置，超预算保守判逃）
var _lad_n: int = 0
var _weak_n := 0
var _sc := PackedInt32Array()          # 「纯己方领地」判定缓存轮次
var _sv := PackedByteArray()           # 该轮的判定结果（1 = 纯领地，可过滤）
## ★ 2026-10-08：空区**边界构成**（与 `_sc`/`_sv` 由**同一次 BFS** 写入、按 `_sc_id` 同步失效）。
##   为什么挂在 `_own_area_layers()` 上而不是另写一份 flood fill：那条 BFS 本来就要遍历整片
##   空区并检查全部邻点，顺手按颜色去重计数是零额外代价；另写一份 = 第二套口径，早晚分岔。
##   ⚠️ 与 `bpn`（`(空点, 边界子)` 邻接**对数**）语义不同：这里是**去重子数**，
##   与 `--anlzdir` 直方图同口径。两者都保留，各按各的用途。
var _sc_o := PackedInt32Array()        # 边界上**己方**去重子数
var _sc_p := PackedInt32Array()        # 边界上**对方**去重子数
var _sc_z := PackedInt32Array()        # 该空区的空点数
## 边界子去重标记。**不复用 `_cst`** —— 那是块去重（`cid`）用的，抢了会把块判错。
var _bst := PackedInt32Array()
var _bid := 0
var _sc_id := 0
## 最近一次 `_prepare_root()` 里被硬过滤剔掉 / 安全阀退回的计数（供 `--sealhard` 读）。
##   必须是**成员变量**：否则判据只能靠重算一遍来推断，那就成了"判据自己注入被测量"。
var sealed_hard_blocked_last := 0
var sealed_hard_fallback_last := 0
# 影响力场（终局评估用）：到最近黑/白子的棋盘距离，只经空点扩散
var _db := PackedInt32Array()
var _dw := PackedInt32Array()
var _dq := PackedInt32Array()          # 影响力 BFS 队列

# 并行搜索：额外 worker 实例（主线程自己也跑一份，不浪费一个核）
var _workers: Array[AIEngine] = []
var _eff_cap := 0          # 本次搜索生效的 rollout 手数上限（0 = 不限）

var rng := RandomNumberGenerator.new()

# 对外暴露的统计（HUD 显示用）
var last_playouts := 0
var last_ms := 0
var last_depth := 0            # 本次搜索的最大树深度（渐进加宽是否生效的直接证据）

## 最后一次搜索的**根层访问分布**快照（2026-10-24，自对弈数据工厂 `--selfplay` 用）。
## `last_root_cands[k]` 与 `last_root_visits[k]` 按下标对齐；`visits` 是**含**先验
## 虚拟注入的原始访问数（与 `probe_root_visits()` 同口径 ⇒ 消费侧不许再扣一次）。
## ★ 唯一写入点是 `choose_move()` 的**四条收尾/早退路径**，且早退必须**清空**：
##   残留上一手的分布会让"局面 ↔ 标签"静默错位，而错位的数据照样能训练、照样出报告
##   （§107 同族：守卫不许写入正在被查询的状态，但**必须**把它清干净）。
## ★ 为什么不在消费侧改用 `probe_root_visits()`：那个会**再跑一遍 pw**，自对弈成本翻倍，
##   而且它自己建的树与 `choose_move` 不是同一次搜索 ⇒ 标签与实际落子不同源（§136）。
var last_root_cands: Array[int] = []
var last_root_visits: PackedFloat32Array = PackedFloat32Array()
## 与 `last_root_visits` 配套的**虚拟注入量**（消费侧要从每个候选里扣掉它）。
## ★★ 必须由引擎给出、不能让消费侧自己猜：单线程是 `prior_visits`，多线程是
##   `W × prior_visits`（每个 worker 各注入一份，见 `_pick_merged` 里的 `vinj`）。
##   猜错的后果：多线程下只扣 1/W ⇒ 真实访问被高估、标签被拉成近似均匀 ⇒
##   训出来等于没学，而且报告**完全正常**（这是本节最容易静默出错的一处）。
var last_root_v_inj: float = 0.0
## 与 `last_root_cands` 配套的**真实 Q 值**（已扣注入，取值 [0,1]；**未访问置 −1**）。
## ★ 为什么未访问要单独编码成 −1、不能用 0：0 是合法的"胜率 0%"，混起来训练端会把
##   "没搜过"当成"必输"，正好把 Gumbel 的 completed-Q 补全做成反的。
## ★ 口径由 `_root_real_stats()` 给出，与选点用的 `_pick_merged()` **同一份真源**。
var last_root_q: PackedFloat32Array = PackedFloat32Array()

# ---- 性能剖析（仅 --aiprof 时打开；正常对局为零开销）----
var prof_on := false
var prof_iters := 0
var prof_depth_sum := 0
var prof_depth_max := 0
var prof_play_calls := 0
var prof_prepare_us := 0
var prof_search_us := 0
var prof_area_us := 0
var prof_area_calls := 0


## 清空根层分布快照。**每个早退分支都要调**（见 `last_root_cands` 字段声明处）。
func _clear_root_dist() -> void:
	last_root_cands.clear()
	last_root_visits = PackedFloat32Array()
	last_root_v_inj = 0.0
	last_root_q = PackedFloat32Array()


## 清空剖析计数
func prof_reset() -> void:
	prof_iters = 0
	prof_depth_sum = 0
	prof_depth_max = 0
	prof_play_calls = 0
	prof_prepare_us = 0
	prof_search_us = 0
	prof_area_us = 0
	prof_area_calls = 0


# ============================================================================
#  MCTS 树节点
# ============================================================================
class MNode:
	var move: int = -1
	var player: int = -1      # 落这颗子的颜色（用于胜负视角换算）
	var prior: float = 0.0    # 先验，同时作为初始 Q 的贝叶斯估计
	var visits := 0
	var wins := 0.0
	var children: Array[MNode] = []
	var off := 0              # 展开顺序在 _perm 上的随机起点
	var nxt := 0              # 已尝试的候选数


# ============================================================================
#  初始化
# ============================================================================
func setup(adjacency: Array, ai: int, seed: int = 0) -> void:
	adj = adjacency
	n = adjacency.size()
	ai_color = ai
	# 棋盘/邻接变了（换棋盘或改尺寸）：旧 worker 的缓冲区尺寸已失效，全部丢弃重建
	_workers.clear()
	if seed == 0:
		seed = int(Time.get_ticks_usec())
	rng.seed = seed

	# CSR 扁平邻接：消除 Array[Array[int]] 的 Variant 装箱开销
	var total := 0
	for i in n:
		total += adjacency[i].size()
	_as.resize(n + 1)
	_af.resize(total)
	_deg.resize(n)
	var w := 0
	for i in n:
		_as[i] = w
		var row: Array = adjacency[i]
		_deg[i] = row.size()
		for v in row:
			_af[w] = int(v)
			w += 1
	_as[n] = w

	# 缓冲区一次性分配到位
	var maxd := 4 * n + 512
	_b.resize(n)
	_gst.resize(n)
	_gbuf.resize(n)
	_gbuf2.resize(n)
	_lst.resize(n)
	_ast.resize(n)
	_cst.resize(n)
	_cst2.resize(n)
	_sst.resize(n)
	_cbuf.resize(n)
	_bpts.resize(n)
	_eye_st.resize(n)
	_gmark.resize(n)
	_ld_pts.resize(n)
	_ld_q.resize(n)
	_ld_vis.resize(n)
	_weak.resize(n)
	_ladbuf.resize(n)
	_sc.resize(n)
	_sv.resize(n)
	_sc_o.resize(n)
	_sc_p.resize(n)
	_sc_z.resize(n)
	_bst.resize(n)
	_db.resize(n)
	_dw.resize(n)
	_dq.resize(n)
	_mv_st.resize(maxd)
	_nc_st.resize(maxd)
	_ko_st.resize(maxd)
	_tn_st.resize(maxd)
	_capst.resize(maxd * 4)
	_log.resize(maxd)
	_logc.resize(maxd)
	_aw.resize(n)
	_an.resize(n)
	_perm.resize(n)
	for i in n:
		_perm[i] = i
	# PackedInt32Array 没有 shuffle()，手工 Fisher-Yates
	for i in range(1, n):
		var j := rng.randi() % (i + 1)
		var tmp := _perm[i]
		_perm[i] = _perm[j]
		_perm[j] = tmp

	_stamp_reset()
	_compute_centrality()
	reset_state()


## 长时间对局后时间戳可能逼近溢出，统一清零
func _stamp_reset() -> void:
	_gst.fill(0)
	_lst.fill(0)
	_cst.fill(0)
	_cst2.fill(0)
	_sst.fill(0)
	_eye_st.fill(0)
	_ld_vis.fill(0)
	_gmark.fill(0)
	_sc.fill(0)
	_sc_o.fill(0)
	_sc_p.fill(0)
	_sc_z.fill(0)
	_bst.fill(0)
	_bid = 0
	_gid = 0
	_lid = 0
	_cid = 0
	_cid2 = 0
	_sid = 0
	_eye_id = 0
	_gmark_id = 0
	_sc_id = 0


## 棋盘变了 / 重置棋局后必须调用：清空树与历史快照
func reset_state() -> void:
	_tree = null
	_tree_move = -1
	_has_prev = false
	_prev_board.resize(n)
	_prev_board.fill(EMPTY)
	_ply = 0
	_capsp = 0
	_pris_b = 0
	_pris_w = 0
	_logn = 0
	# ★ 2026-09-21 修：`_scan_cnt` 是「距上次全盘叫吃扫描经过了几个 rollout 步」的相位计数器
	# （`_playout_move()` 里 `_scan_cnt += 1`，满 `full_scan_every=14` 才做一次全盘扫描，
	# 否则只看上一手附近）。它**跨 choose_move 一直累积**，而 reset_state() 原来不清它 ——
	# 后果：同一局面、同一预算、同一随机种子连调两次，一次走 `_scan_all`、一次走 `_scan_local`，
	# rollout 的候选集不同 → 消耗的随机数个数不同 → 整棵搜索树分叉 → 选出不同的手。
	# 实测（--aibud + 逐步打印 `rng.state`）：三次调用**迭代前**的 state 完全相同，
	# 第一次迭代后就分岔，最终 `28 | 102 | 102`。
	# 它同时是个**棋力**问题，不只是复现性问题：rollout 的行为会随「这盘棋之前搜过多少次」
	# 漂移（同一局面在不同时间点会被评估成不同样子）。
	_scan_cnt = 0
	_aw.fill(0.0)
	_an.fill(0.0)
	# 新对局：动态分中心锚点失效（旧局的预计终局分对新局无意义）
	_dc_has = false
	_dc_center = 0.0
	_dc_collect = false
	_dc_sum = 0.0
	_dc_sq = 0.0
	_dc_n = 0.0
	# 「上一次分析建好的眼位模型」也是跨局/跨手状态：不清的话，`_eye_vital_bonus()`
	# 会拿旧盘、旧手的 `_ld_pts` / `_ldm_nbr` 去判新局面的候选点（不只是复现性问题，
	# 实战里每一手都带着上一手的图在工作）。`_group_status()` 内部已修成"任何早退都
	# 先作废"，这里再兜一道：换局/换手时模型整体失效。
	_ld_n = 0


## 多源 BFS 距边界（度<=3 视为边界）的层数，归一化为中心度
func _compute_centrality() -> void:
	_cent.resize(n)
	_cent.fill(1.0)
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var frontier: Array[int] = []
	for i in n:
		if _deg[i] <= 3:
			dist[i] = 0
			frontier.append(i)
	if frontier.size() == 0:
		return
	var d := 0
	while frontier.size() > 0:
		var nxt: Array[int] = []
		for v in frontier:
			var k := _as[v]
			var ke := _as[v + 1]
			while k < ke:
				var nb := _af[k]
				k += 1
				if dist[nb] == -1:
					dist[nb] = d + 1
					nxt.append(nb)
		frontier = nxt
		d += 1
	var maxd := 0
	for i in n:
		if dist[i] > maxd:
			maxd = dist[i]
	if maxd <= 0:
		return
	for i in n:
		if dist[i] >= 0:
			_cent[i] = 1.0 - float(dist[i]) / float(maxd)


# ============================================================================
#  图搜索原语（全部基于 _b，零分配）
# ============================================================================
## 收集 start 所在的同色串，成员写入 _gbuf[0..cnt)，返回 cnt
func _group(start: int) -> int:
	_gid += 1
	var sid := _gid
	var color: int = _b[start]
	_gbuf[0] = start
	_gst[start] = sid
	var cnt := 1
	var qi := 0
	while qi < cnt:
		var cur := _gbuf[qi]
		qi += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] == color and _gst[nb] != sid:
				_gst[nb] = sid
				_gbuf[cnt] = nb
				cnt += 1
	return cnt


## 串 _gbuf[0..cnt) 的气数；exclude 指定的点不视为气。顺带把最后一口气写入 _libs_last
func _libs(cnt: int, exclude: int) -> int:
	_lid += 1
	var sid := _lid
	var c := 0
	var last := -1
	for i in cnt:
		var v := _gbuf[i]
		var k := _as[v]
		var ke := _as[v + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if nb != exclude and _b[nb] == EMPTY and _lst[nb] != sid:
				_lst[nb] = sid
				last = nb
				c += 1
	_libs_last = last
	return c


func _is_adj(a: int, b: int) -> bool:
	var k := _as[a]
	var ke := _as[a + 1]
	while k < ke:
		if _af[k] == b:
			return true
		k += 1
	return false


# ============================================================================
#  近似死活（做活 / 补活判定）—— 这是「AI 会做活」的基础设施
# ============================================================================
## 统计 _gbuf[0..cnt) 这个己方串拥有的「单点真眼」数。
## 眼的定义：一个空点，其全部邻居都属于本串（对方无法从内部切断或填塞）。
## 用 _eye_st/_eye_id 对空点去重：同一个眼点挨着本串多个子时只算一只。
func _count_eyes(cnt: int) -> int:
	_eye_id += 1
	var eid := _eye_id
	_gmark_id += 1
	var mid := _gmark_id
	var i := 0
	while i < cnt:
		_gmark[_gbuf[i]] = mid
		i += 1
	var eyes := 0
	i = 0
	while i < cnt:
		var p := _gbuf[i]
		i += 1
		var k := _as[p]
		var ke := _as[p + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] != EMPTY or _eye_st[nb] == eid:
				continue
			_eye_st[nb] = eid
			var inner := true
			var kk := _as[nb]
			var kk2 := _as[nb + 1]
			while kk < kk2:
				if _gmark[_af[kk]] != mid:
					inner = false
					break
				kk += 1
			if inner:
				eyes += 1
				if eyes >= 2:
					return eyes
	return eyes


## 自检用（只读，不参与决策）：v 是不是 color 的「单点眼点」——
## 空点，且**全部**邻居都是 color 的子（一个邻点都不是空、不是对方）。
## 与 `_count_eyes()` 内部的 inner 判据同口径（那边多一层「必须属于本串」的限定）。
## 纯几何判据，**不判真假眼**（对方能否扑入/打劫），只用来数「AI 往自己眼里填子」这个行为。
func _is_own_eye_point(v: int, color: int) -> bool:
	if v < 0 or _b[v] != EMPTY:
		return false
	var k := _as[v]
	var ke := _as[v + 1]
	var own := 0
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != color:
			return false
		own += 1
	return own > 0


## 自检用（只读）：v 邻接的己方块里「最多单点真眼数」和「该块规模」。
## 返回 [最大眼数, 对应块规模]；v 没有己方邻子时返回 [-1, 0]。
## 用途 —— 把「填自己的眼」分成两种病理，指向两处不同的病根：
##   · 眼数 >= 2：该块**已经有活形**，还去填 → 说明候选过滤（`_prepare_root`）根本没拦住；
##   · 眼数 <= 1：该块**本来就没活** → `_own_territory_only()` 的「做活豁免」会放行这类空区，
##     所以这里被放行是**设计如此**，要判的是「放行之后 AI 是不是把最后一只眼也填了」。
func _adj_own_eye_info(v: int, color: int) -> Array:
	var best_e := -1
	var best_sz := 0
	_cid2 += 1
	var wid := _cid2
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != color or _cst2[nb] == wid:
			continue
		var gsz := _group(nb)
		for j in gsz:
			_cst2[_gbuf[j]] = wid
		var e := _count_eyes(gsz)
		if e > best_e:
			best_e = e
			best_sz = gsz
	return [best_e, best_sz]


## 眼位空间的「要点」判据（**唯一真源**）：返回 [本空间是否识别出要点, v 本身是不是要点, 被围那块棋的代表点]。
##   · `rep < 0`（不是小眼位空间）/ 该块已活或已死（`_group_status != 1`）/ 模型建不起来
##     / **杀点集为空** → 一律 [false, false, -1]；
##   · 注意第二项「杀点集为空」的语义：不是「这里没有要点」，而是**模型没能识别出要点**
##     （典型：非封闭区域、或区域吸收了外气点 → 局部图给不出杀点）。这种情况必须返回
##     [false, ...] 而不是 [true, false]，否则调用方会把它当成「有要点、但 v 不是」，
##     进而把棋理上的那个要点也一起罚掉（实测：直三/弯三 +3 外气 的要点被挤出候选集）。
##   · 第 3 项 `rep` 是**点号**，不受 `_gbuf` 被 `_group_status()` 覆盖的影响，可直接用。
##
## `_eye_vital_bonus()`（奖励要点）与 `w_fill_own_eye`（惩罚非要点）**共用这一份判据** ——
## 分开写两份的话，「奖励了甲、又惩罚了甲」这种自相矛盾迟早出现（本工程踩过口径不齐）。
func _eye_vital_flags(v: int) -> Array:
	var rep := _eye_rep_at(v)
	if rep < 0:
		return [false, false, -1]
	var cnt := _group(rep)
	if _group_status(cnt, _libs(cnt, -1)) != 1 or _ld_n <= 0:
		return [false, false, -1]
	var km := _ld_kill_mask(_ld_n)
	if km == 0:
		return [false, false, -1]
	var vi := _ldm_index(v, _ld_n)
	return [true, vi >= 0 and (km & (1 << vi)) != 0, rep]


## 自检用（只读）：`v` 是不是做活/点杀的**要点**。判据见 `_eye_vital_flags()`。
func _is_vital_point(v: int) -> bool:
	return bool(_eye_vital_flags(v)[1])


## 近似死活判定：_gbuf[0..cnt) 这个串是否已经「活」。
## 判据（取宽，宁可多判活；活 → 内部空点视作纯领地、不再往里面填）：
##   ① 已有两只以上单点真眼（标准的活形）；
##   ② 气数 >= 6（大龙在随机对局里基本杀不掉，也说明外部有出路）。
## 门槛不能太高：判「未活」的棋块会获得额外补强先验，门槛过高会让 AI 到处补棋、失去先手
func _group_alive(cnt: int) -> bool:
	if _count_eyes(cnt) >= 2:
		return true
	return _libs(cnt, -1) >= 6


# ============================================================================
#  通用眼位空间死活（纯图模型 → 方形网格与 2~6 度非周期密铺同样成立）
# ============================================================================
#  为什么需要它：旧 `_count_eyes` 只认「单点真眼」，于是
#    · 弯三 / 丁四 / 梅花五 / 刀把五 这些**要点不在串上**的眼位形状完全看不见
#      （梅花五的要点是区域中心点，它四邻全是空点，压根不是任何子串的「眼」）；
#    · 直四 / 曲四 / 直六 / 葡萄六 这些**已经是活形**的形状也看不见 → 判成未活 →
#      AI 会往自己的活棋里反复补棋（白送目）或被「弱棋」先验牵着走。
#  这里改判「眼位空间」整体，判据与围棋规则逐条对应：
#    · 眼位空间 = 「只被本串触及」的空点连通块（封闭判据的传递闭包，含中心内点）；
#    · 提掉整串 ⇔ 它的气被填光，所以「填最后一口气」是**合法手**（不是自杀）
#      —— 少了这条，攻方永远点不进单点眼，会得出「单眼也活」的错结论；
#    · 防守方永远可以 pass；连续两 pass → 静态判定「攻方能否独自填光」。
#  真源：工作区 `死活真源/eye_ld_solver2.py`（方形网格穷举，结论已与棋理逐条对照）。
#  ⚠️ 只在**根先验**里调用（rollout 热路径仍走 `_group_alive` 的廉价口径，见那里的注释）。
var _ld_pts := PackedInt32Array()      # 眼位空间点集（全局点号）
var _ld_q := PackedInt32Array()        # BFS 队列
var _ld_vis := PackedInt32Array()      # 访问标记（轮次戳，避免每次 fill）
var _ld_id := 0
var _ld_mid := 0                       # 本次 _ld_region 给本串打的 _gmark 标记
var _ld_sealed := true                 # 本串的气是否**全在**眼位空间内（= 完全被本串包围）
## 上一次 `_group_status()` 成功建好局部眼位模型时的区域点数（0 = 没有可用模型）。
## `_eye_vital_bonus()` 靠它判断「现在能不能用 `_ld_kill_mask()` / `_ldm_index()`」。
var _ld_n := 0
## 杀点集缓存：区域键 → 位掩码（bit i = `_ld_pts[i]` 是攻方先手可杀之点）。
var _ld_kills := {}
# 局部模型：局部下标 0..m-1 = 眼位点，下标 m = 「防守方整串」超级节点
var _ldm_n := 0
var _ldm_nbr: Array = []               # 长度 m+1，每项 PackedInt32Array（局部下标）
var _ldm_def := BLACK
var _ldm_memo := {}
var _ldm_nodes := 0
var _ld_cache := {}
var last_ld_bailouts := 0              # 超预算次数（自检盯着，恒为 0 才说明预算够）


## 取「本串的眼位空间」，返回点数（点号写入 _ld_pts[0..ret)）；
## 「是否完全封闭」写进 _ld_sealed —— 不封闭（外面还有出路）就不能判无条件活。
func _ld_region(cnt: int) -> int:
	_ld_id += 1
	var lid := _ld_id
	_gmark_id += 1
	var mid := _gmark_id
	_ld_mid = mid
	var i := 0
	while i < cnt:
		_gmark[_gbuf[i]] = mid
		i += 1
	var rn := 0
	var qn := 0
	# 起点：本串的「封闭气点」（所有非空邻居都属于本串）
	i = 0
	while i < cnt:
		var p := _gbuf[i]
		i += 1
		var k := _as[p]
		var ke := _as[p + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] != EMPTY or _ld_vis[nb] == lid:
				continue
			if not _ld_is_sealed(nb, mid):
				continue
			_ld_vis[nb] = lid
			_ld_pts[rn] = nb
			rn += 1
			_ld_q[qn] = nb
			qn += 1
	# 传递闭包：只经过封闭空点扩散（梅花五的中心点就是这样进来的 —— 它不与本串相邻）
	var qi := 0
	while qi < qn:
		var cur := _ld_q[qi]
		qi += 1
		var k2 := _as[cur]
		var ke2 := _as[cur + 1]
		while k2 < ke2:
			var nb2 := _af[k2]
			k2 += 1
			if _b[nb2] != EMPTY or _ld_vis[nb2] == lid:
				continue
			if not _ld_is_sealed(nb2, mid):
				continue
			_ld_vis[nb2] = lid
			_ld_pts[rn] = nb2
			rn += 1
			_ld_q[qn] = nb2
			qn += 1
	# 封闭性：本串每一口气都要落在区域内
	_ld_sealed = true
	i = 0
	while i < cnt:
		var p2 := _gbuf[i]
		i += 1
		var k3 := _as[p2]
		var ke3 := _as[p2 + 1]
		while k3 < ke3:
			var nb3 := _af[k3]
			k3 += 1
			if _b[nb3] == EMPTY and _ld_vis[nb3] != lid:
				_ld_sealed = false
				break
		if not _ld_sealed:
			break
	return rn


## 空点 q 是否「封闭」：它的所有非空邻居都属于本串
## （= 旧 `_count_eyes` 里那只单点真眼的判据，这里把它传播出去）
func _ld_is_sealed(q: int, mid: int) -> bool:
	var k := _as[q]
	var ke := _as[q + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != EMPTY and _gmark[nb] != mid:
			return false
	return true


## 死活状态：0 = DEAD（攻方先手可杀）、1 = UNSETTLED、2 = ALIVE（无条件活）
## libs_hint 传调用方已算好的气数（避免重复遍历整串）。
func _group_status(cnt: int, libs_hint: int = -1) -> int:
	# ★ 2026-09-21 修：「作废上一个形的模型」必须发生在**任何** return 之前。
	#   原来 `_ld_n = 0` 写在 `libs == 0` 那条早退**之后** → 那条路径把「上一个形 / 上一手」
	#   的 `_ld_n` 留在原处，而下面那句注释本来就写着「任何早退路径都不得留上一个形的旧模型」：
	#   实现违反了自己的意图，而且是**静默**的 —— `_eye_vital_bonus()` 只看 `_ld_n > 0`
	#   就敢用 `_ld_kill_mask()` / `_ldm_index()`，于是拿**旧的** `_ld_pts` / `_ldm_nbr`
	#   去判当前候选点，一旦 v 恰好落在旧点集里就白送 w_eye_make / w_kill_point
	#   （14~16 分，足以翻转选点）。
	#   实测（--aibud，同一局面、同一 8000ms 预算、都跑满 pw64，连调三次）：
	#   `28 | 102 | 102` —— 第 1 次 `_ld_n` 还是进程初值 0（不给奖励），此后带着上一次
	#   分析留下的图（给奖励）。修复后三次逐位一致。
	_ld_n = 0
	if cnt <= 0 or cnt > _gbuf.size():
		return 1
	var libs := libs_hint if libs_hint >= 0 else _libs(cnt, -1)
	if libs == 0:
		return 0
	var m := _ld_region(cnt)
	if not _ld_sealed:
		# 外面还有出路 → 谈不到「无条件活」；但气宽仍按大龙级判活（旧口径，取宽）——
		# 能藏未定形（阶梯七）的是**封闭**小眼位，开阔地带没有这回事。
		# ★ 2026-09-21 修：**照样建图**。要点集与「封闭与否」无关：一块还有外气的棋，
		#   它的眼位空间里照样有必争的要点（敌先手点进去就少一只眼）。
		#   原来这里直接 return、不调 `_ldm_ready()` → `_ld_n` 保持 0 →
		#   `_eye_vital_bonus()` 恒返回 0 → **「有外气的棋块」永远拿不到做活/点杀先验**，
		#   在 `_prepare_root()` 的 Top-K 剪枝里被当低分候选丢掉。
		#   实测（`--areatest`）：梅花五 +1/+2 外气时，「不论封闭与否要点都该可选」这一条失败，
		#   而 +0 外气（封闭）时通过 —— 差别只在这一句。
		if m > 0 and m <= ld_cap_points:
			_ldm_ready(m)
		return 2 if libs > ld_max_libs else 1
	if m <= 0:
		return 1
	if m > ld_cap_points:
		return 2                              # 眼位太大 → 判活（取宽）
	# 2026-09-20：走到这里必然是「封闭且 m ≤ cap」→ **一律精确解**。
	# 旧版把「气 ≥6 判活」捷径排在区域分析之前，气 6~8 的封闭未定形（7 目阶梯形）
	# 整体被误判成活 —— 阶梯七气恰好 6，钻的就是这条捷径。
	var key := _ld_cache_key(m)
	var hit: Variant = _ld_cache.get(key, null)
	if hit != null:
		_ldm_ready(m)                         # 命中缓存也要建图：要点集判定要用它
		return int(hit)
	_ldm_ready(m)
	var st := 1
	# 先问「攻方先手能不能杀」：不能 → 无条件活
	if _ldm_search(0, 3 - _ldm_def, false) == 2:
		st = 2
	elif _ldm_search(0, _ldm_def, false) == 0:
		st = 0
	if _ld_cache.size() > 8192:
		_ld_cache.clear()
	_ld_cache[key] = st
	return st


## 建好「本次眼位空间」的局部图并把 `_ld_n` 置位
## —— `_eye_vital_bonus()` 只看 `_ld_n > 0` 就敢用 `_ld_kill_mask()` / `_ldm_index()`。
func _ldm_ready(m: int) -> void:
	_ldm_build(m)
	_ldm_def = _b[_gbuf[0]]
	_ldm_nodes = 0
	_ld_n = m


## 缓存键：眼位点集 + 防守方颜色。**不含**具体是哪一串 ——
## 区域的边界子必然全属于该串，所以「同样的点集」必然导出同一张局部图。
func _ld_cache_key(m: int) -> String:
	var s := "%d|" % _b[_gbuf[0]]
	var i := 0
	while i < m:
		s += str(_ld_pts[i]) + ","
		i += 1
	return s


## 由 _ld_pts[0..m) 建局部图（含「防守方整串」超级节点 m）
## ⚠️ 邻接必须**双向**填：眼位点 ↔ 整串。只填单向会让「整串的气」恒为 0 → 所有形状一律判死，
##   而判死又会让每个点都变成「杀点」→ 真源对照会以「全盘皆死」这种很显眼的方式整体失败。
func _ldm_build(m: int) -> void:
	_ldm_n = m
	_ldm_nbr.clear()
	var i := 0
	while i <= m:
		_ldm_nbr.append(PackedInt32Array())
		i += 1
	i = 0
	while i < m:
		var p := _ld_pts[i]
		var k := _as[p]
		var ke := _as[p + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			var j := _ldm_index(nb, m)
			if j >= 0:
				_ldm_nbr[i].append(j)
		if _ld_touches(p):
			_ldm_nbr[i].append(m)          # 与防守方整串相邻
			_ldm_nbr[m].append(i)          # ★ 必须对称填！否则 `_ldm_libs(mask={m})` 恒为 0
		i += 1
	_ldm_memo.clear()


## 全局点号 → 局部下标（m ≤ 8，线性查找足够）
func _ldm_index(g: int, m: int) -> int:
	var i := 0
	while i < m:
		if _ld_pts[i] == g:
			return i
		i += 1
	return -1


## 该点是否与本串（本次 _ld_region 标记的那一串）相邻
func _ld_touches(p: int) -> bool:
	var k := _as[p]
	var ke := _as[p + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != EMPTY and _gmark[nb] == _ld_mid:
			return true
	return false


## 局部颜色：下标 m 恒为防守方
func _ldm_color(state: int, i: int) -> int:
	if i >= _ldm_n:
		return _ldm_def
	return (state >> (2 * i)) & 3


## 局部同色连通块（位掩码，含超级节点）
func _ldm_gmask(state: int, start: int) -> int:
	var col := _ldm_color(state, start)
	var mask := 1 << start
	var stack: Array[int] = [start]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for w in _ldm_nbr[u]:
			if (mask & (1 << w)) != 0:
				continue
			if _ldm_color(state, w) != col:
				continue
			mask |= (1 << w)
			stack.append(w)
	return mask


## 掩码对应串的气数（空点去重）
func _ldm_libs(state: int, mask: int) -> int:
	var seen := 0
	var libs := 0
	var i := 0
	while i <= _ldm_n:
		if (mask & (1 << i)) != 0:
			for w in _ldm_nbr[i]:
				if w >= _ldm_n:
					continue
				if ((state >> (2 * w)) & 3) != EMPTY:
					continue
				if (seen & (1 << w)) != 0:
					continue
				seen |= (1 << w)
				libs += 1
		i += 1
	return libs


## 落子（局部）。合法返回新 state，非法返回 -1。
## 与真源同款的三条要点：
##   ① 只提**对方**子（把自己刚落的自杀子也提走会让「自杀」退化成「返回原局面」→ 死循环）；
##   ② **绝不清掉含超级节点 m 的串** —— m 代表整块棋，它的死活只能由 `_ldm_ring_libs == 0`
##      表达。若按普通串把它「提」掉，状态里就凭空多出气点，死活结论会整体偏向「活」
##      （真源 Python 里对应 `RING in g → continue`，移植时最容易漏这一条）；
##   ③ **提掉整串算合法手**（否则「填最后一口气」被误判成自杀，攻方永远点不进眼）。
func _ldm_place(state: int, i: int, color: int) -> int:
	if i >= _ldm_n or ((state >> (2 * i)) & 3) != EMPTY:
		return -1
	var ns := state | (color << (2 * i))
	while true:
		var changed := false
		var j := 0
		while j < _ldm_n:
			var cj := (ns >> (2 * j)) & 3
			if cj != EMPTY and cj != color:
				var gm := _ldm_gmask(ns, j)
				if (gm & (1 << _ldm_n)) != 0:
					j += 1
					continue                       # ② 整块棋不走提子路径
				if _ldm_libs(ns, gm) == 0:
					var k := 0
					while k < _ldm_n:
						if (gm & (1 << k)) != 0:
							ns &= ~(3 << (2 * k))
						k += 1
					changed = true
			j += 1
		if not changed:
			break
	if _ldm_libs(ns, _ldm_gmask(ns, _ldm_n)) == 0:
		return ns                              # 提掉整串 → 合法
	if _ldm_libs(ns, _ldm_gmask(ns, i)) == 0:
		return -1                              # 自杀
	return ns


## 防守方整串的气
func _ldm_ring_libs(state: int) -> int:
	return _ldm_libs(state, _ldm_gmask(state, _ldm_n))


## 攻方独自填光（防守方一直脱先）—— 终局静态判定。单调：攻方子只增 → 无环。
func _ldm_fill_all(state: int) -> bool:
	if _ldm_ring_libs(state) == 0:
		return true
	var opp := 3 - _ldm_def
	var i := 0
	while i < _ldm_n:
		if ((state >> (2 * i)) & 3) == EMPTY:
			var ns := _ldm_place(state, i, opp)
			if ns >= 0:
				if _ldm_ring_libs(ns) == 0:
					return true
				if _ldm_fill_all(ns):
					return true
		i += 1
	return false


## 局部死活搜索：2 = 防守方活、0 = 防守方被提。
func _ldm_search(state: int, turn: int, last_pass: bool) -> int:
	if _ldm_ring_libs(state) == 0:
		return 0
	var key := (state << 3) | ((turn - 1) << 1) | (1 if last_pass else 0)
	var hit: Variant = _ldm_memo.get(key, null)
	if hit != null:
		return int(hit)
	# 预算只对**真正递归展开**的节点计数 —— 命中记忆的调用很便宜，计进去会让预算虚耗光
	# （实测踩过：把 memo 命中一起计数 → 6 点眼位必然超预算 → 一律 bail 成「活」→ 全盘皆活）
	_ldm_nodes += 1
	if _ldm_nodes > ld_node_budget:
		last_ld_bailouts += 1
		return 2                               # 超预算 → 判活（取宽 + 硬上限）
	_ldm_memo[key] = 2                         # 循环 → 攻方无进展 → 防守方活（死活题标准约定）
	# ★ 剪枝（2026-09-20，与真源同款）：极小极大早退 —— 找到极值即可收，
	#   返回的是真极值 → 结论与全遍历逐位相同，memo 安全。
	#   7 目眼位进精确解后全遍历要 2000~5000 节点，剪枝把「找到杀 / 找到活」的
	#   证明提前收口（真源实测：阶梯七白先杀证明 4706 → 429 节点）。
	var vals: Array[int] = []
	if last_pass:
		vals.append(2 if not _ldm_fill_all(state) else 0)   # 双方都 pass → 终局
	else:
		vals.append(_ldm_search(state, 3 - turn, true))
	var best_want := 2 if turn == _ldm_def else 0
	if vals[0] == best_want:
		_ldm_memo[key] = vals[0]
		return vals[0]
	var i := 0
	while i < _ldm_n:
		if ((state >> (2 * i)) & 3) == EMPTY:
			var ns := _ldm_place(state, i, turn)
			if ns >= 0:
				var v := _ldm_search(ns, 3 - turn, false)
				if v == best_want:
					_ldm_memo[key] = v
					return v
				vals.append(v)
		i += 1
	var best := -1
	if turn == _ldm_def:
		for v in vals:
			if v > best:
				best = v
	else:
		best = 3
		for v in vals:
			if v < best:
				best = v
	_ldm_memo[key] = best
	return best


## 攻方杀点集（位掩码，bit i 对应 `_ld_pts[i]`）：眼位空间里「攻方先手落此点 → 防守方死」的点。
## 这是真源 `outcome(board, 攻方)` 的要点列，也是「敌之要点即我之要点」的判据来源。
## 按区域键缓存 —— 同一个眼位空间在整个搜索里只算一次。
func _ld_kill_mask(m: int) -> int:
	var key := _ld_cache_key(m)
	var hit: Variant = _ld_kills.get(key, null)
	if hit != null:
		return int(hit)
	var mask := 0
	var opp := 3 - _ldm_def
	var i := 0
	while i < m:
		var ns := _ldm_place(0, i, opp)
		if ns >= 0 and _ldm_search(ns, _ldm_def, false) == 0:
			mask |= 1 << i
		i += 1
	if _ld_kills.size() > 8192:
		_ld_kills.clear()
	_ld_kills[key] = mask
	return mask


## 从 v 出发做小范围空点 BFS，判断 v 是否落在某个「小眼位空间」里；是则返回被围那块棋的代表点。
## 返回 -1 = 不是小眼位空间（开阔地带 / 区域大于 ld_cap_points / 边界混色 = 被双方夹着）。
##
## ★ 为什么必须**从 v 出发**而不是从串出发：要点常常不在串上 —— 梅花五的要点是十字中心，
## 它四邻全是空点、压根不碰任何子。只扫 v 的 1 环邻居永远看不见它（旧实现就栽在这里）。
func _eye_rep_at(v: int) -> int:
	var cap: int = maxi(ld_cap_points, 1)
	var reg: Array[int] = [v]
	var rep := -1
	var i := 0
	while i < reg.size():
		var cur: int = reg[i]
		i += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] == EMPTY:
				if reg.has(nb):
					continue
				if reg.size() >= cap:
					return -1              # 区域过大 → 不是小眼位空间
				reg.append(nb)
			elif rep < 0:
				rep = nb
			elif _b[rep] != _b[nb]:
				return -1                  # 边界混色 → 不是谁的眼位空间
	return rep



# ============================================================================
#  落子 / 悔子（全局可变棋盘 + 显式栈）
# ============================================================================
## 落子。成功返回提子数（>=0）并压栈；失败返回 -1 且棋盘不变
func _play(v: int) -> int:
	if prof_on:
		prof_play_calls += 1
	if _b[v] != EMPTY or v == _ko:
		return -1
	var color: int = _turn
	var opp := 3 - color
	var old_ko := _ko
	var nc := 0

	# 1) 预判提子（v 视为已占，故统计对方组气数时排除 v）
	_cid += 1
	var cid := _cid
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != opp or _cst[nb] == cid:
			continue
		var gsz := _group(nb)
		var dead := _libs(gsz, v) == 0
		for i in gsz:
			var x := _gbuf[i]
			_cst[x] = cid          # 无论死活都打标，避免同一串重复 BFS
			if dead:
				_cbuf[nc] = x
				nc += 1

	# 2) 无提子时必须检查自杀（提子后我方必有气，故跳过）
	if nc == 0:
		_gid += 1
		var sid := _gid
		_gbuf[0] = v
		_gst[v] = sid
		var cnt := 1
		var qi := 0
		var libs := 0
		while qi < cnt:
			var cur := _gbuf[qi]
			qi += 1
			var kk := _as[cur]
			var ke2 := _as[cur + 1]
			while kk < ke2:
				var nb := _af[kk]
				kk += 1
				if _b[nb] == color and _gst[nb] != sid:
					_gst[nb] = sid
					_gbuf[cnt] = nb
					cnt += 1
				elif _b[nb] == EMPTY and nb != v and _gst[nb] != sid:
					_gst[nb] = sid
					libs += 1
		if libs == 0:
			return -1

	# 3) 提交
	if _capsp + nc > _capst.size():
		_capst.resize(_capst.size() * 2)
	_b[v] = color
	for i in nc:
		_b[_cbuf[i]] = EMPTY
	_ko = -1
	if nc == 1:
		# ★★ 设劫条件（2026-10-02 修，与 `game.gd::place_stone()` 对齐）：
		#   **标准定义** = 「提一子，且被提点紧邻落子点」—— 对方若立刻回提就形成同形循环
		#   （劫争之所以要禁一手），故该点在本手**不可**下。
		#   旧条件额外要求 `_group(v) == 1 and _libs(1,-1) == 1`（"自己仅一气"）——
		#   ★ 那个"自己仅一气"量的是**能不能立刻提回来**，是另一件事，
		#     **不是**设劫的条件。带上它 ⇒ 「提一子、自己不止一气」这种局面**根本不设劫**
		#     ⇒ 引擎认定可下，而游戏侧（玩家实际看到的）禁着 ⇒ **两套规则分叉**。
		#   实测（`--rulestest` ②）：`_setup_shot_capture()` 那个标准劫形下
		#   `game.gd::ko_point = t91` 而引擎 `_ko = -1`（引擎是**靠自杀分支**拒掉那一手的，
		#   劫点机制本身没生效）。这正是"两套独立实现、无交叉判据"会让 bug 静默活下来的样子。
		#   邻接性仍要查（`cappt` 未必贴着落点：提一子可能提的是远处一串的最后一子）。
		var cappt := _cbuf[0]
		if _is_adj(v, cappt):
			_ko = cappt
	_mv_st[_ply] = v
	_nc_st[_ply] = nc
	_ko_st[_ply] = old_ko
	_tn_st[_ply] = color
	for i in nc:
		_capst[_capsp + i] = _cbuf[i]
	_capsp += nc
	# 提子计数（O(1)，`nc == 0` 时零开销）。不读开关，因为读开关会把「本手提子数」
	# 变成「开关打开后提的子」，中期拨开关就得到半份计数（铁律 33：死参数）。
	# 只有 `_result_impl()` 在 `count_prisoners` 为真时才把它加进效用。
	if nc > 0:
		if color == BLACK:
			_pris_b += nc
		else:
			_pris_w += nc
	_ply += 1
	_log[_logn] = v
	_logc[_logn] = color
	_logn += 1
	_turn = opp
	return nc


## 悔最近一步（必须严格 LIFO）
func _undo() -> void:
	_ply -= 1
	var v := _mv_st[_ply]
	var nc := _nc_st[_ply]
	if nc > 0 and _tn_st[_ply] == BLACK:
		_pris_b -= nc
	elif nc > 0:
		_pris_w -= nc
	_b[v] = EMPTY
	if nc > 0:
		var opp := 3 - _tn_st[_ply]
		_capsp -= nc
		for i in nc:
			_b[_capst[_capsp + i]] = opp
	_ko = _ko_st[_ply]
	_turn = _tn_st[_ply]


# ============================================================================
#  Rollout 策略（v2 的核心改进）
# ============================================================================
## 一步 rollout 着法；返回 -1 表示停一手
##
## 性能要点：绝不做 O(n) 全盘扫描。叫吃扫描默认只看上一手附近（O(deg²)），
## 每隔 full_scan_every 手才做一次全盘兜底；安静手的候选也限定在上一手两圈内。
## 这既快得多，也更贴近真实棋形（围棋是高度局部的游戏）。
func _playout_move(last: int) -> int:
	var color := _turn
	var opp := 3 - color

	# ---- 1) 叫吃扫描 ----
	_cappts.clear()
	_capsz.clear()
	_savepts.clear()
	_weak_n = 0
	_scan_cnt += 1
	if last < 0 or _scan_cnt >= full_scan_every:
		_scan_cnt = 0
		_scan_all(color, opp)
	else:
		_scan_local(last, color, opp)

	# ---- 2) 提子：优先吃最大的一串（best-of-3 抽样）----
	if _cappts.size() > 0 and rng.randf() < p_capture:
		var m := _cappts.size()
		var bi := rng.randi() % m
		for t in mini(2, m - 1):
			var j := rng.randi() % m
			if _capsz[j] > _capsz[bi]:
				bi = j
		if _play(_cappts[bi]) >= 0:
			return _cappts[bi]

	# ---- 3) 逃叫吃 ----
	if _savepts.size() > 0 and rng.randf() < p_save:
		var m2 := _savepts.size()
		var st := rng.randi() % m2
		for t in mini(3, m2):
			var j := (st + t) % m2
			if _play(_savepts[j]) >= 0:
				return _savepts[j]

	# ---- 3.5) 补活：己方大龙只剩 2 气（且无活形）时，往它的气点补一手 ----
	# 旧 rollout 完全不管 2 气的棋，于是随机对局里己方大龙经常被杀，
	# 面积分随之系统性低估「补活」的价值 —— AI 也就学不会做活。
	if _weak_n > 0 and rng.randf() < p_eye:
		var wst := rng.randi() % _weak_n
		for t in mini(2, _weak_n):
			var j := (wst + t) % _weak_n
			if _play(_weak[j]) >= 0:
				return _weak[j]

	# ---- 4) 安静的一手 ----
	# 候选限定在上一手两圈内（围棋高度局部，这样更快也更真实）。
	# 用“拒绝采样”代替轮盘赌：随机抽候选 → 算权重 → 按 w/wmax 概率接受，
	# 平均只需算 1~2 次权重，而不是遍历全部候选。
	_qpts.clear()
	var ring1 := 0
	if last >= 0:
		_sid += 1
		var sid := _sid
		var k1 := _as[last]
		var ke1 := _as[last + 1]
		while k1 < ke1:
			var nb := _af[k1]
			k1 += 1
			if _b[nb] == EMPTY and _sst[nb] != sid:
				_sst[nb] = sid
				_qpts.append(nb)
		ring1 = _qpts.size()
		for i in ring1:
			var v := _qpts[i]
			var k2 := _as[v]
			var ke2 := _as[v + 1]
			while k2 < ke2:
				var nb := _af[k2]
				k2 += 1
				if _b[nb] == EMPTY and _sst[nb] != sid:
					_sst[nb] = sid
					_qpts.append(nb)
	if _qpts.size() < 4:
		# 开局或局部已填满 → 退回全盘候选
		_qpts.clear()
		ring1 = 0
		for i in n:
			if _b[i] == EMPTY:
				_qpts.append(i)

	if _qpts.size() > 0:
		var m3 := _qpts.size()
		var wmax := 1.0 + wq_own * 3.0 + wq_opp * 3.0 + wq_emp * 4.0 \
				+ wq_center + wq_local
		for attempt in 3:
			var sel := -1
			var sel_emp := 0
			for t in mini(6, m3):
				var j := rng.randi() % m3
				var v := _qpts[j]
				var own := 0
				var op := 0
				var emp := 0
				var k := _as[v]
				var ke := _as[v + 1]
				while k < ke:
					var nb := _af[k]
					k += 1
					var cc := _b[nb]
					if cc == color:
						own += 1
					elif cc == opp:
						op += 1
					else:
						emp += 1
				if own + op == 0:
					continue                  # 不挨任何棋子，实战不会这么下
				if own == _deg[v]:
					continue                  # 自己的眼，不填
				var w := 1.0 + wq_own * float(own) + wq_opp * float(op) \
						+ wq_emp * float(emp) + wq_center * _cent[v]
				if j < ring1:
					w += wq_local
				if rng.randf() * wmax <= w:
					sel = j
					sel_emp = emp
					break
			if sel < 0:
				break
			var mv := _qpts[sel]
			var nc := _play(mv)
			if nc < 0:
				continue
			if nc == 0 and (not narrow_self_atari_guard or sel_emp < 2):
				# 落点本身有 >=2 个空邻点时，合并后的棋块气数必然 >=2（空邻点互不相同，
				# 且提子只会让空点变多），所以「送吃」判定不可能命中 —— 直接省掉这次 BFS。
				# 旧守卫写作 `own == 0 and emp >= 2`，但 own > 0 时结论同样成立，
				# 于是大量本该跳过的 BFS 被白跑了（纯性能问题，不影响行为）。
				# `narrow_self_atari_guard=false` 可退回旧行为做基准对照
				var gsz := _group(mv)
				if _libs(gsz, -1) == 1 and rng.randf() < p_no_self_atari:
					_undo()
					continue
			return mv

	# ---- 5) 兜底：沿随机排列扫描合法点 ----
	# 不用「随机点重试 12 次」：中盘空点稀疏时随机点会反复撞在已占位上，
	# 而 _perm 是 0..n-1 的一个排列，扫过的点绝不重复，尝试次数直接砍半
	var bst := rng.randi() % n
	for t in 10:
		var v := _perm[(bst + t) % n]
		if _play(v) >= 0:
			return v
	return -1


## 全盘扫描叫吃串（贵，仅周期性调用）。顺带把「己方只剩 2 气的大龙」的气点
## 收进 _weak，供 rollout 的补活分支使用
func _scan_all(color: int, opp: int) -> void:
	_scanall_calls += 1
	_sid += 1
	var sid := _sid
	for i in n:
		var c := _b[i]
		if c == EMPTY or _sst[i] == sid:
			continue
		var gsz := _group(i)
		for j in gsz:
			_sst[_gbuf[j]] = sid
		var lg := _libs(gsz, -1)
		if lg == 1:
			var lib := _libs_last
			if lib == -1 or lib == _ko:
				continue
			if c == opp:
				_cappts.append(lib)
				_capsz.append(gsz)
			else:
				_savepts.append(lib)
		elif lg == 2 and c == color and gsz >= 4:
			_collect_weak(gsz)


## 只扫描上一手及其直接邻居所在的串（便宜，绝大多数手数走这条路径）
func _scan_local(last: int, color: int, opp: int) -> void:
	_sid += 1
	var sid := _sid
	_lpts.clear()
	_lpts.append(last)
	var k := _as[last]
	var ke := _as[last + 1]
	while k < ke:
		_lpts.append(_af[k])
		k += 1
	for v in _lpts:
		var c := _b[v]
		if c == EMPTY or _sst[v] == sid:
			continue
		var gsz := _group(v)
		for j in gsz:
			_sst[_gbuf[j]] = sid
		var lg := _libs(gsz, -1)
		if lg == 1:
			var lib := _libs_last
			if lib == -1 or lib == _ko:
				continue
			if c == opp:
				_cappts.append(lib)
				_capsz.append(gsz)
			else:
				_savepts.append(lib)
		elif lg == 2 and c == color and gsz >= 4:
			_collect_weak(gsz)


## 把「只剩 2 气」的己方大龙的气点收进 _weak（最多 2 个），供 rollout 补活。
## 复用 _eye_st/_eye_id 对气点去重，避免同一气点被多个相邻组重复加入
func _collect_weak(gsz: int) -> void:
	_eye_id += 1
	var eid := _eye_id
	var added := 0
	var i := 0
	while i < gsz:
		var p := _gbuf[i]
		i += 1
		var k := _as[p]
		var ke := _as[p + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] != EMPTY or _eye_st[nb] == eid:
				continue
			_eye_st[nb] = eid
			if _weak_n >= n:
				return
			_weak[_weak_n] = nb
			_weak_n += 1
			added += 1
			if added >= 2:
				return


## 跑完一次随机对局并返回白方视角的胜率值 [0,1]
## 自检用：从当前局面按 rollout 策略往下铺到上限，**不回退、不计分**。
## 调用方负责保存/恢复棋盘与手番。用于量化评估质量（--aiterr）。
func _rollout_fill(last: int, cap: int) -> int:
	# 必须清 RAVE 日志游标：本函数直接调 _playout_move → _play，而 _play 只管往 _log 追加、
	# 不清零（清零是 _playout 的职责）。多局连跑（--ailam 一局面 24 次）会溢出 _log，
	# 报 "Out of bounds set index (on base: PackedInt32Array)"，且报错点在 _play 很难联想到这里
	_logn = 0
	var passes := 0
	var moves := 0
	var lm := last
	while passes < 2 and moves < cap:
		var mv := _playout_move(lm)
		if mv == -1:
			passes += 1
			_turn = 3 - _turn
			_ko = -1
		else:
			passes = 0
			moves += 1
			lm = mv
	return moves


## 自检用：当前盘面的填充率（非空点占比）
func _fill_rate() -> float:
	var c := 0
	for i in n:
		if _b[i] != EMPTY:
			c += 1
	return float(c) / float(maxi(n, 1))


## 自检探针（--aiterr）：量化「rollout 截断处的评估」与「该局面的真实价值」差多少。
##
## 这是诊断大盘棋力问题的核心工具。19×19 有 361 格而 rollout 上限 160 手（填充率 44%），
## 传统「完全围住才计分」会让面积分退化成纯子数差；本探针把这个退化直接量出来。
##
## ⚠️ 口径（第一版踩过坑，别再退回去）：
## 必须在**同一个局面 A** 上比较三种分数 —— 旧评估(A) / 新评估(A) / 真值(从 A 下满)。
## 若拿「S 下 160 手的局面 A」去比「S 下满的局面 B」，两者是**两条不同的随机轨迹**，
## 分差本来就不该相等，比出来的是 rollout 自身的方差，完全说明不了评估函数的好坏。
##
## 返回：score_old / score_new（同一局面 A 的两种评估）、score_true（从 A 下满的真值）
func probe_eval_quality(moves: int, seed: int, cap: int) -> Dictionary:
	var saved_seed := rng.seed
	rng.seed = seed
	clear_board()
	scramble(moves)
	var snap_s := _b.duplicate()
	var t_s := _turn
	var k_s := _ko
	var base := _ply
	var out := {}
	# ① 从起手局面铺到截断上限 → 局面 A
	out["moves1"] = _rollout_fill(-1, cap)
	out["fill1"] = _fill_rate()
	# ② 在**同一个**局面 A 上分别用两种评估打分（_area_score 不改棋盘，安全）
	var old_infl := influence_enabled
	influence_enabled = false
	out["score_old"] = _area_score()
	influence_enabled = true
	out["score_new"] = _area_score()
	influence_enabled = old_infl
	# ③ 从局面 A 继续下满 → 真值
	out["moves2"] = _rollout_fill(-1, n * 4)
	out["fill2"] = _fill_rate()
	out["score_true"] = _area_score()
	# ④ 恢复
	while _ply > base:
		_undo()
	_b = snap_s.duplicate()
	_turn = t_s
	_ko = k_s
	rng.seed = saved_seed
	return out


## 自检探针（--ailam）：给 λ 混合定「理论最优 λ」，而不是靠噪声极大的自对局比分去试。
##
## 原理：rollout 值 = 真值 + 噪声（方差 σ²，均值无偏）；静态评估 = 真值 + 偏差（偏差 b²，零方差）。
## 混合 v(λ) = (1-λ)·rollout + λ·static 的均方误差
##     MSE(λ) = (1-λ)²σ² + λ²b²
## 对 λ 求导得最小值            λ* = σ² / (σ² + b²)
## —— 静态评估越准（b 越小）、rollout 噪声越大（σ 越大），λ 就该越大；这正是大盘的情形。
##
## 本探针在同一个局面 A 上：跑 K 次完整 rollout 估出 σ 与真值均值 μ，
## 再量两种静态评估相对 μ 的偏差 b_old / b_new，最后给出 λ*。
func probe_lambda_opt(moves: int, seed: int, cap: int, k: int) -> Dictionary:
	var saved_seed := rng.seed
	rng.seed = seed
	clear_board()
	scramble(moves)
	# ① 铺到截断上限 → 局面 A
	_rollout_fill(-1, cap)
	var A := _b.duplicate()
	var tA := _turn
	var kA := _ko
	var pA := _ply
	var out := {}
	out["fill"] = _fill_rate()
	# ② 同一局面 A 上的两种静态评估
	var old_infl := influence_enabled
	influence_enabled = false
	out["static_old"] = _area_score()
	influence_enabled = true
	out["static_new"] = _area_score()
	influence_enabled = old_infl
	# ③ K 次完整 rollout：均值当真值 μ，样本标准差当 σ
	var sum := 0.0
	var sum2 := 0.0
	for i in k:
		while _ply > pA:
			_undo()
		_b = A.duplicate()
		_turn = tA
		_ko = kA
		_rollout_fill(-1, n * 4)
		var s: float = _area_score()
		sum += s
		sum2 += s * s
	while _ply > pA:
		_undo()
	_b = A.duplicate()
	var mu: float = sum / float(maxi(k, 1))
	var varc: float = sum2 / float(maxi(k, 1)) - mu * mu
	var sigma: float = sqrt(maxf(varc, 0.0))
	out["mu"] = mu
	out["sigma"] = sigma
	var b_old: float = absf(float(out["static_old"]) - mu)
	var b_new: float = absf(float(out["static_new"]) - mu)
	out["bias_old"] = b_old
	out["bias_new"] = b_new
	out["lambda_old"] = varc / (varc + b_old * b_old) if (varc + b_old * b_old) > 0.0 else 0.0
	out["lambda_new"] = varc / (varc + b_new * b_new) if (varc + b_new * b_new) > 0.0 else 0.0
	# ④ 恢复
	_b = A.duplicate()
	_turn = tA
	_ko = kA
	rng.seed = saved_seed
	return out


func _playout(last: int) -> float:
	_playout_calls += 1
	var base := _ply
	var t0 := _turn
	var k0 := _ko
	# 静态评估：在**当前叶子节点**直接打分（确定性、零方差）。
	# 与 rollout 结果按 eval_mix_lambda 加权混合，稀释单次 rollout 的噪声（见该参数注释）。
	# λ=0 时完全跳过，不产生任何额外开销。
	var static_sc := 0.0
	if eval_mix_lambda > 0.0:
		static_sc = _area_score() + _pris_term()
	# ---- 零 rollout 模式（`playout_cap_factor <= 0`，见该参数的声明处）----
	# 叶子不做随机对局：效用 = 静态评估。**不推进任何手**，所以无需 `_undo()`；
	# 但 `_turn`/`_ko` 仍按原样恢复（本函数契约：调用前后局面与行棋方不变）。
	if playout_cap_factor <= 0.0:
		if eval_mix_lambda <= 0.0:
			# λ=0 时上面没算静态分，而它是唯一的分量 ⇒ 必须补算。
			static_sc = _area_score() + _pris_term()
		# `_result()` 内部仍会再算一次 `_area_score()`（两分量同值时算式恒等于它本身）。
		# 那 87µs 是白跑的，但改 `_result_impl` 会动到 `_last_area_*` 的写入时机，
		# 风险大于收益 ⇒ 先留着，见本条注释。174µs/模拟仍比 rollout 的 ~4300µs 低 25 倍。
		var r0 := _result(static_sc)
		_turn = t0
		_ko = k0
		return r0
	var passes := 0
	var moves := 0
	var capi := int(float(n) * playout_cap_factor)
	if _eff_cap > 0:
		capi = mini(capi, _eff_cap)   # 大盘截断：省下末盘无谓的填充手
	# 树内已经真实走过 _ply 手（渐进加宽让深度可达几十层），rollout 只需补足
	# 到同一份「总手数预算」，越深的叶子 rollout 越短 —— 这是深度换来的净提速
	capi = maxi(capi - _ply, 12)
	var lm := last
	while passes < 2 and moves < capi:
		var mv := _playout_move(lm)
		if mv == -1:
			passes += 1
			_turn = 3 - _turn
			_ko = -1
		else:
			passes = 0
			moves += 1
			lm = mv
	var r := _result(static_sc)
	while _ply > base:
		_undo()
	_turn = t0
	_ko = k0
	return r


# ============================================================================
#  终局评估
# ============================================================================
## 终局死子修正：盘面里「只剩一口气、且成块（>=2 子）」的棋，对手下一手就能提掉，
## 这些子不该算作自己的地盘。
## 这是让 MCTS 学会补活的关键一环：不修正的话，「下满盘多占点」永远比「花一手补活」
## 在面积分上更划算，rollout 就会教 AI「不要补活、被吃也照算」。
func _dead_correction() -> Vector2i:
	var db := 0
	var dw := 0
	_cid += 1
	var cid := _cid
	for i in n:
		var c: int = _b[i]
		if c == EMPTY or _cst[i] == cid:
			continue
		var gsz := _group(i)
		for j in gsz:
			_cst[_gbuf[j]] = cid
		if gsz >= 2 and _libs(gsz, -1) <= 1:
			if c == BLACK:
				db += gsz
			else:
				dw += gsz
	return Vector2i(db, dw)


## 影响力场：算出每个空点到「最近黑子 / 最近白子」的棋盘距离。
## 只经**空点**扩散 —— 对方的子是墙，会挡住影响力，所以被黑墙围住的区域
## 白方只能绕远路，自然判给黑。这正是「势力范围」该有的行为。
## 距离超过 influence_max_d 就不再扩散（该点保持 -1 = 无人认领）。
func _influence_field() -> void:
	_influence_dist(BLACK, _db)
	_influence_dist(WHITE, _dw)


## 单色多源 BFS：out[v] = v 到最近的 color 色棋子的距离（只经空点）；够不着则为 -1
func _influence_dist(color: int, out: PackedInt32Array) -> void:
	out.fill(-1)
	var q := _dq
	var qn := 0
	# ★ 源门控（`infl_src_min_libs`，默认 0 = 关闭 ⇒ 走到下面两行原文，逐位不变）
	var gate: bool = infl_src_min_libs > 0
	var gcid := 0
	if gate:
		_cid += 1
		gcid = _cid
	for i in n:
		if _b[i] == color:
			if gate:
				# 按**整块**去重（同一块只判一次气），弱块跳过 ⇒ 不辐射、但仍是墙
				if _cst[i] == gcid:
					continue
				var gsz := _group(i)
				for j in gsz:
					_cst[_gbuf[j]] = gcid
				if _libs(gsz, -1) <= infl_src_min_libs:
					continue
			out[i] = 0
			q[qn] = i
			qn += 1
	var qi := 0
	while qi < qn:
		var cur := q[qi]
		qi += 1
		var d: int = out[cur] + 1
		if d > influence_max_d:
			continue
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] != EMPTY or out[nb] != -1:
				continue
			out[nb] = d
			q[qn] = nb
			qn += 1


## 领地式面积计分：子数 + 完全被单色围住的空点；返回 白 - 黑
##
## ⚠️ 大盘（19×19 = 361 格）的致命退化：rollout 上限 160 手，填充率只有 44%，
## 空区连成一片、边界黑白都有子 → 按老规则**全部判为中立、一分不给**，
## 于是面积分 ≈ 纯子数差，AI 完全学不到「围空」，只会往盘上堆子。
## 现在补上第二条计分路径：未定型空区按影响力（BFS 距离）逐点归属。
func _area_score() -> float:
	_area_calls += 1
	var black := 0.0
	var white := 0.0
	for i in n:
		var c := _b[i]
		if c == BLACK:
			black += 1.0
		elif c == WHITE:
			white += 1.0
	if influence_enabled:
		_influence_field()
	_gid += 1
	var sid := _gid
	var empty_cnt := 0
	for i in n:
		if _b[i] != EMPTY or _gst[i] == sid:
			continue
		_gst[i] = sid
		_gbuf2[0] = i
		var cnt := 1
		var qi := 0
		var tb := false
		var tw := false
		while qi < cnt:
			var cur := _gbuf2[qi]
			qi += 1
			var k := _as[cur]
			var ke := _as[cur + 1]
			while k < ke:
				var nb := _af[k]
				k += 1
				var cc := _b[nb]
				if cc == EMPTY:
					if _gst[nb] != sid:
						_gst[nb] = sid
						_gbuf2[cnt] = nb
						cnt += 1
				elif cc == BLACK:
					tb = true
				else:
					tw = true
		if tb and not tw:
			black += float(cnt)
		elif tw and not tb:
			white += float(cnt)
		elif influence_enabled:
			_influence_need += 1
			# 未定型空区：逐点按影响力归属（近的一方得 1 分，同距则中立）
			for j in cnt:
				var v := _gbuf2[j]
				var dbb: int = _db[v]
				var dww: int = _dw[v]
				if dbb < 0:
					if dww >= 0:
						white += 1.0
				elif dww < 0:
					black += 1.0
				elif dbb + infl_dead_zone <= dww:
					black += 1.0
				elif dww + infl_dead_zone <= dbb:
					white += 1.0
		empty_cnt += cnt
	# 闸门：`dead_fill_gate = 0` ⇒ 不门控（永远扣）；否则空点必须少到 n/gate 才扣。
	# 展开成这个形状是为了让默认值 6 **逐位等于**旧式 `empty_cnt * 6 <= n`。
	if dead_penalty and (dead_fill_gate <= 0 or empty_cnt * dead_fill_gate <= n):
		_dead_hit += 1
		# 只在盘面基本填满时（默认空点少于 1/6）才扣死子：
		# rollout 若被截断在中盘，盘上「只剩一口气」的多半只是战术性叫吃，不是死棋
		# （这条理由就是 `dead_fill_gate` 的取值风险，见该参数声明处）
		var dz := _dead_correction()
		black -= float(dz.x)
		white -= float(dz.y)
	# ★★ 贴目在这一层加（2026-10-02）：**唯一真源**。
	#   为什么必须是这里、而不是上层各写一遍：
	#     · `_result_impl()` 的 tanh 压胜率、λ 混合、动态重定心、`_dc_center` 锚点、
	#       `_value_after_move()` 的锚定，全都吃这个返回值 ⇒ 加一次全部继承；
	#     · 加在 `_result_impl()` 里只覆盖 rollout 路径，λ 混合的静态分量仍不含贴目
	#       ⇒ **两个分量量纲不一致**（那是最隐蔽的一种"看起来有、其实错"）；
	#     · 加在选点那一层则连自检里的 `probe_root_score()` 等探针量到的仍是裸盘面差。
	#   口径：返回的是 `白 - 黑`，白方贴目 ⇒ `+ komi`（贴目是白方的"便宜"）。
	# ★ 2026-10-06：把双方分项一并带出（供局势层用）。
	#   原先只返回 `black - white` 的**净值**，被调用方当成了「某一方绝对面积」
	#   ⇒ 落后方拿到负面积（实测 black_points = -177.5）。
	#   ⇒ 这里把 black / white 两个累加器**原样**带出，语义与返回值同源（铁律 18）。
	_last_area_black = black
	_last_area_white = white
	return white - black + komi

func _result(static_sc_given: float = 0.0) -> float:
	if prof_on:
		prof_area_calls += 1
		var t0 := Time.get_ticks_usec()
		var r := _result_impl(static_sc_given)
		prof_area_us += Time.get_ticks_usec() - t0
		return r
	return _result_impl(static_sc_given)


## 提子项（白提子 − 黑提子），**唯一出口**。`count_prisoners` 为假时恒 0.0
## ⇒ 关态与旧版逐位相同。见 `count_prisoners` 的声明处与 `_result_impl()`。
func _pris_term() -> float:
	if not count_prisoners:
		return 0.0
	return float(_pris_w - _pris_b)


func _result_impl(static_sc_given: float) -> float:
	# ★★ 提子项（`count_prisoners`）：`_area_score()` 只算「盘上子 + 领空」，
	#   而真源 `rules_kernel._compute_scores()` 是「盘上子 + 领空 + 提子数」。
	#   ⇒ 总目差 = 本返回值 + (白提子 − 黑提子)。关掉时 `_pris_term()` 恒 0，
	#   逐位复现旧行为（含 RNG 序列：本函数不掷骰）。
	#   ⚠️ **加在 λ 混合之前**：混合的两个分量必须同量纲 ——
	#   `static_sc_given` 在 `_playout()` 里算的时候**已经含提子项**（叶子时刻的值），
	#   而 `_area_score()` 这里是 rollout **之后**的盘面。若加在混合之后，
	#   `(1-λ)·rollout` 这一支拿到的是 rollout 后的提子数、`λ·static` 那一支
	#   被重复加了一遍叶子时刻的提子数 ⇒ 两分量量纲又分叉（正是 λ 注释里警告的那族）。
	var sc := _area_score() + _pris_term()
	if eval_mix_lambda > 0.0:
		sc = (1.0 - eval_mix_lambda) * sc + eval_mix_lambda * static_sc_given
	# 动态分中心：收集本手搜索的叶子分（供下一手做锚点），并把效用重定心到锚点附近。
	# 注意：收集的是**绝对分** sc（锚点=本手叶子分均值），重定心只影响返回的效用值。
	if _dc_collect:
		_dc_sum += sc
		_dc_sq += sc * sc
		_dc_n += 1.0
	if dynamic_center_enabled and _dc_has:
		var cap: float = sqrt(float(n)) * dynamic_center_scale
		# ★ 2026-10-05 修：此前 `dynamic_center_zero_weight` **只在 @export 声明与 copy_to
		#   出现，本函数从不读它** ⇒ 该参数完全失效，--aiablate 的 ㉘/㉙ 两组消融
		#   （「半重定心(0.5) vs 全重定心」/「半重定心(0.5) vs 关闭重定心」）
		#   实测的其实是「全 vs 全」和「全 vs 无」⇒ 两组结论无效。
		#   语义（见 @export 注释）：0 = 完全按相对分；1 = 完全按绝对分；中间 = 部分重定心。
		#   混合式：rel_full = sc - _dc_center，rel_abs = sc
		#     ⇒ rel = mix(rel_full, rel_abs, w) = sc - (1 - w) * _dc_center
		#   ⚠️ w=1 时**不能**走「关掉重定心」那条分支来取等价 —— 那条是 `sc` 未经 clamp，
		#     而本分支有 cap 软截断；两条路对极端分差的行为不同（cap=√n·scale）。
		#     这里只减锚点、保留 cap，与「部分重定心」语义一致（自检 --vtest ④③ 钉住两端）。
		var zw: float = clampf(dynamic_center_zero_weight, 0.0, 1.0)
		var rel: float = clampf(sc - (1.0 - zw) * _dc_center, -cap, cap)
		return 0.5 + 0.5 * tanh(rel / maxf(score_soft, 0.5))
	return 0.5 + 0.5 * tanh(sc / maxf(score_soft, 0.5))


# ============================================================================
#  先验
# ============================================================================
## 空点 v 所在的整片空区：若边界棋子全部为己方、**且这些己方棋块都已经活**，
## 说明这里是安全的己方领地，落子 = 自填眼位，纯亏目 → 这一手不值得下（应停一手）。
##
## 关键修正（AI「不会做活」的直接病根）：
## 旧实现只看「边界是否全为己方」，于是**未活棋块的内部空点也被一并禁掉**——
## 一块只有一只眼、等着补一手做活的龙，AI 连补活的手都下不出来，只能眼睁睁被吃。
## 现在改为：只要边界上任一己方棋块还没活，该空区就是「做眼要点」，允许落子。
## 边界完全没有棋子的情况（如全盘皆空的开局）不算领地，返回 false。
## 同一片空区在一手之内结果相同，用 _sc/_sv 缓存整片空区，避免 O(空区²) 重复计算。
func _own_territory_only(v: int) -> bool:
	if _sc[v] == _sc_id:
		return _sv[v] == 1
	var lay := _own_area_layers(v)
	return bool(lay[0]) and bool(lay[1])


## ★★ 2026-10-08 新增：**空区硬过滤** —— 把 ③（`w_sealed_territory`）从**软权重**升级成
## 「照 `_own_territory_only()` 的样子在**打分前剔除**」，并把适用面从「边界全是对方」扩到
## 「对方占多数」。开关 = `use_sealed_hard_filter`：关掉时本函数恒 false ⇒ 逐位复现旧行为。
##
## 【四个条件，缺一不可】
##   ① 边界非空（`o + p > 0`）—— 与 `_sealed_color()` 的 `col < 0`（一颗子都没碰）同口径。
##      缺这条的后果有实测：`_sealed_color` 第一版在 19×19 空盘上把 325 个空点里的 321 个
##      判成「被对方围死」（98.8%）⇒ `w_sealed_territory=-6` 变成全局落子惩罚。
##   ② 对方占比 ≥ `sealed_hard_share`（默认 0.75 = 扩面；0.999 = 只拦"全是对方"）。
##   ③ 空区点数 ≤ `sealed_hard_max_size`（0 = 不限）。**棋理安全阀**：大面积空区即使边界
##      全是对方，也可能是可打入/可做活的战场，硬拦会把进攻性一起削掉。
##   ④ 对方在该区附近**已有活块**（复用 ③ 的第二条件）—— 对方没活块 ⇒ 这手可能是杀棋/攻防
##      （正是 `w_kill_point` / `w_capture_dead` 的目标），拦掉 = 自断进攻。
##
## ⚠️ 与 `_own_territory_only()` 是**镜像**关系、不是同一件事：那边 = 「边界全是己方 ∧
##   边界每一块己方都已活」；这边 = 「边界全是/多数是对方 ∧ 对方附近有活块」。
##   刻意**不**要求「边界对方块都已活」：对方只要有一块活棋挨着，那块地就已经是他的了
##   （要求全活反而会漏拦 —— 对方外围有未定形块 ≠ 里面不是他的目）。
##
## 【性能】复用 `_own_area_layers()` 的**同一次 BFS**：边界构成与层 A 一起写进 `_sc_o/_sc_p`，
##   按 `_sc_id` 失效 ⇒ 本过滤每候选 O(1)，整手一次 BFS。`_anlz()` 也有按 `_sc_id` 的缓存，
##   所以条件 ④ 只付一次 `analyze_board()`（`use_analyze_bonus` 开着时本来就要付）。
func _sealed_by_opp_hard(v: int) -> bool:
	if not use_sealed_hard_filter:
		return false
	_own_area_layers(v)
	if _sc[v] != _sc_id:
		# BFS 没写成（不该发生）⇒ **放行**：宁可漏拦，不可误拦。
		return false
	var o := _sc_o[v]
	var p := _sc_p[v]
	var tot := o + p
	if tot <= 0:
		return false                                  # ① 开阔地带
	if float(p) < sealed_hard_share * float(tot):
		return false                                  # ② 对方占比不够
	if sealed_hard_max_size > 0 and _sc_z[v] > sealed_hard_max_size:
		return false                                  # ③ 空区太大
	return _has_live_block_near(_anlz(), v, 3 - _turn)  # ④ 对方附近有活块


## `_own_territory_only()` 的两层判定**拆开**返回（共用同一份 BFS 与缓存 → 口径不会漂）：
##   · 层 A = `v` 所在整片空区的边界全是己方子（且边界非空）→「己方独占空区」；
##   · 层 B = 该区域边界上**每一块**己方棋块都「已活」→「纯领地（落子 = 自填）」。
## `_own_territory_only()` = A ∧ B。**A ∧ ¬B 就是「做活豁免」**：为了让未活的块能补眼，
## 整片空区都对 AI 开闸 —— 这既是当年修「AI 不会做活」时开的口子，也是
## 「AI 填自己的眼」唯一可能的入口。它的宽度必须量得出来（见 `selfplay_to_end` 的 `eye_pts_open`）。
##
## 返回 [A, B]。缓存 `_sv` 用**三态**编码：0 = A 不成立 / 1 = A∧B（纯领地）/ 3 = A∧¬B（豁免）。
## 这样 `_own_territory_only()` 判 `_sv[v] == 1` 依旧正确，诊断侧又能读出口子有多大；
## 若拆成两份各自 BFS，两处口径早晚会分岔（本工程已踩过「宽严不齐 → A/B 白做」）。
func _own_area_layers(v: int) -> Array:
	if _sc[v] == _sc_id:
		var cv: int = _sv[v]
		return [cv != 0, cv == 1]
	var opp := 3 - _turn
	_sid += 1
	var sid := _sid
	# ★ 2026-10-08：边界构成去重标记用**独立**戳号（不复用 `_sid`/`_cid`）——
	#   复用的后果与 `_ast` 那次同族：抢了别的 BFS 的戳号会把那次遍历截断（静默漏块）。
	_bid += 1
	var bid := _bid
	_gbuf2[0] = v
	_sst[v] = sid
	var cnt := 1
	var qi := 0
	var bpn := 0
	var opp_hit := false
	# 边界构成：己/对**去重子数**（`bpn` 是邻接对数，用途不同，两者都留）
	var o_cnt := 0
	var p_cnt := 0
	# 空区成员写 _gbuf2：判定边界棋块死活时 _group() 会占用 _gbuf
	while qi < cnt:
		var cur := _gbuf2[qi]
		qi += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			var cc := _b[nb]
			if cc == EMPTY:
				if _sst[nb] != sid:
					_sst[nb] = sid
					_gbuf2[cnt] = nb
					cnt += 1
			elif cc == opp:
				opp_hit = true
				if _bst[nb] != bid:
					_bst[nb] = bid
					p_cnt += 1
			else:
				_bpts[bpn] = nb
				bpn += 1
				if _bst[nb] != bid:
					_bst[nb] = bid
					o_cnt += 1

	var layer_a: bool = bpn > 0 and not opp_hit
	var layer_b := false
	if layer_a:
		layer_b = true
		_cid += 1
		var cid := _cid
		for i in bpn:
			var p := _bpts[i]
			if _cst[p] == cid:
				continue                 # 同一棋块只判一次
			var gsz := _group(p)
			for j in gsz:
				_cst[_gbuf[j]] = cid
			# ★ 2026-09-21 修（口径不齐 → 两向都出病）：这里原来用 `_group_alive()`
			#   （= ≥2 只单点眼 **或** 气 ≥6），而本工程真正的死活判据是 `_group_status()`
			#   （封闭小眼位穷举求解 / 非封闭按 `ld_max_libs` 比气）。两个口径实测**两个方向都打架**
			#   —— `--areatest` 60 行里 12 例违规：
			#     A) 求解器判「未定形(1)」（要点是必争的做活手）而过滤层判「活」→ 整片眼位空间被封
			#        → **AI 连自己的做活要点都进不了候选集**（直三/弯三/丁四/方四/梅花五/刀把五/
			#        阶梯七 各有一档命中）。这就是「AI 不会做活」。
			#     B) 求解器判「活(2)」（真源判活形）而过滤层判「未活」→ 没封 → 眼位空点仍是候选
			#        → **AI 往自己活形里填**（直四/曲四/直五）。这就是「AI 填自己的眼」。
			#   现在统一到同一个 `_group_status()`。但**必须是「取或」而不是「换一套」**：
			#     · 求解器判活（含「气 > ld_max_libs」的取宽）→ 活；
			#     · **或** 已有 ≥2 只单点真眼 —— 这是不受「非封闭按气比大小」那条取宽近似影响的
			#       **直接**活棋证据，漏掉它会让「两只眼齐备、但外气不多且没封闭」的棋块被当成
			#       未定形 → 眼位空点重新开闸。实测（2026-09-21 第一版只换不取或）：
			#       `--aieye` 立刻出现「填眼前已≥2眼」5 例（修前是 0 例）—— 反向病根被引进来了。
			#     · 刻意**不用** `_group_alive()` 整条：它那条「气 ≥6 就算活」正是方向 A 的错源
			#       （气**恰好等于 6** 时把求解器判的「未定形」盖成「活」→ 封住做活要点）。
			#   `ld_enabled = false`（阴性对照档）仍整条退回旧判据，保证那条路径逐位不变。
			var b_alive := false
			if ld_enabled:
				b_alive = _group_status(gsz, _libs(gsz, -1)) == 2 or _count_eyes(gsz) >= 2
			else:
				b_alive = _group_alive(gsz)
			if not b_alive:
				layer_b = false          # 还有未活的棋块 → 需要留出做眼空间
				break
	var code: int = 0
	if layer_a:
		code = 1 if layer_b else 3
	for i in cnt:
		var q := _gbuf2[i]
		_sc[q] = _sc_id
		_sv[q] = code
		_sc_o[q] = o_cnt
		_sc_p[q] = p_cnt
		_sc_z[q] = cnt
	return [layer_a, layer_b]


## v 所在整片空区的边界上有没有对方子（与 game.gd 的 `_gate_empty_region_has_enemy`
## 同口径）。真·自紧气豁免判据的第二条：边界没有对方子 = 在己方空区里做眼/补活，正手。
## ⚠️ 与 `_own_territory_only()` 的区别：那边还要求「边界各己方块都已活」才算纯领地；
## 这里只要「边界无对方子」就豁免 —— 口径必须与 gate 一致，宽严不齐会让「引擎罚的手」
## 和「仪器数的手」对不上，A/B 就白做了。
## 只在根先验的真自紧气检查里调用（能走到这里的候选极少），不做跨候选缓存。
func _root_region_has_enemy(v: int, opp: int) -> bool:
	_sid += 1
	var sid := _sid
	_gbuf2[0] = v
	_sst[v] = sid
	var cnt := 1
	var qi := 0
	while qi < cnt:
		var cur := _gbuf2[qi]
		qi += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			var cc := _b[nb]
			if cc == EMPTY:
				if _sst[nb] != sid:
					_sst[nb] = sid
					_gbuf2[cnt] = nb
					cnt += 1
			elif cc == opp:
				return true
	return false


## 根层着法评分：一次预判落子，产出综合特征分；非法返回 -1e9
# ============================================================================
#  征子（ladder）判定 —— 回答「这手叫吃到底有没有用」
# ============================================================================
## 我方 color 在 v 落子（调用时 v 尚未落）后，被叫吃的对方串能不能逃掉。
## 用真实 _play/_undo 交替推演「我打 → 他长气 → 我续打 …」：
##   · 他长气后气数 >= 3 → 逃掉了（false：这手就是无效叫吃，还帮对方走厚）
##   · 他长气后仍只有 2 气 → 我找一个能把它打回 1 气的点继续追（递推）
##   · 他没有合法长气点 / 中途被提 → 征死（true）
## 用 _ply 记录栈深，返回前一次性回退，保证棋盘状态干净；只在根先验里调用。
func _ladder_works(v: int, color: int) -> bool:
	var opp := 3 - color
	var ply0 := _ply
	if _play(v) < 0:
		while _ply > ply0:
			_undo()
		return false
	var seed := -1
	var best := 0
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != opp:
			continue
		var gsz := _group(nb)
		if _libs(gsz, -1) == 1 and gsz > best:
			best = gsz
			seed = nb
	var ok := false
	if seed >= 0 and best >= ladder_min_size:
		_lad_nodes = 0
		ok = _ladder_chase(seed, color, 0)
	while _ply > ply0:
		_undo()
	return ok


## 征子续打：此刻 seed 所在串处于被打吃（1 气）状态，推演后续。
## 2026-09-20 分支化：我方续打点**全部都试**（任一征死即成立）——旧版贪心取第一个
## 叫吃点，选错线会把「征得死」误判成「逃得掉」（ladtest ① 的几何沿右边一线其实
## 征得死，贪心读者判错）。防守方长气点唯一（1 气）→ 天然强制，无需分支。
func _ladder_chase(seed: int, color: int, depth: int) -> bool:
	if depth >= ladder_max_plies:
		return false                       # 推得太长，保守判「逃得掉」
	_lad_nodes += 1
	if _lad_nodes > ladder_node_budget:
		return false                       # 预算耗尽 → 同向保守（逃得掉）
	var gsz := _group(seed)
	if _libs(gsz, -1) != 1:
		return false
	var esc := _libs_last                  # 对方唯一的长气点
	if esc < 0:
		return true                        # 没有气点 → 死
	if _play(esc) < 0:
		return true                        # 逃不动（自杀 / 劫）→ 征死
	var g2 := _group(esc)
	var l2 := _libs(g2, -1)
	if l2 >= 3:
		return false                       # 长气后气数 >= 3 → 逃掉了
	if l2 <= 1:
		return true                        # 长气后反而没气 → 死
	var conts: Array[int] = []
	if _atari_points(esc, color, conts) == 0:
		return false                       # 打不动了
	# 探索顺序（2026-09-20，纯启发、不改语义）：先试「强制逃点空邻更少」的续打 ——
	# 此刻守方恰 2 气、conts 就是这两口气，打其中一口则另一口成为强制逃点；
	# 逃点被堵得越死，征死线越短。不排序则坏分支可能把节点/深度预算耗在前面。
	var ord: Array = []
	for q in conts:
		var other := -1
		for r in conts:
			if r != q:
				other = r
		var tight := 0
		if other >= 0:
			var tk := _as[other]
			var tke := _as[other + 1]
			while tk < tke:
				var tnb := _af[tk]
				tk += 1
				if _b[tnb] == EMPTY:
					tight += 1
		ord.append([tight, q])
	ord.sort_custom(func(a, b): return a[0] < b[0])
	var works := false
	for pr in ord:
		var q: int = pr[1]
		var ply1 := _ply
		if _play(q) >= 0:
			works = _ladder_chase(esc, color, depth + 1)
		while _ply > ply1:
			_undo()
		if works:
			break
	return works


## 收集「把 seed 串打到只剩 1 气（或直接提掉）」的全部点（征子续打分支用），返回数量
func _atari_points(seed: int, color: int, out: Array[int]) -> int:
	out.clear()
	var gsz := _group(seed)
	_lid += 1
	var sid := _lid
	_lad_n = 0
	for i in gsz:
		var p := _gbuf[i]
		var k := _as[p]
		var ke := _as[p + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] == EMPTY and _lst[nb] != sid:
				_lst[nb] = sid
				_ladbuf[_lad_n] = nb
				_lad_n += 1
	for i in _lad_n:
		var q := _ladbuf[i]
		var ply0 := _ply
		var caps := _play(q)
		if caps < 0:
			continue
		if caps > 0:                       # 直接能提 → 就是续手
			while _ply > ply0:
				_undo()
			out.append(q)
			continue
		var g2 := _group(seed)
		var l := _libs(g2, -1)
		while _ply > ply0:
			_undo()
		if l == 1:
			out.append(q)
	return out.size()



## 防守方视角（2026-09-20 新增）：己方串 seed 被打吃、我在其唯一气点 v 逃出之后，
## 攻方按同一套推演（所有续打点分支）还能不能征死。true = 逃跑无用。
## 与 `_ladder_works` 同一套 _play/_undo 纪律：返回前一次性回退，棋盘状态干净。
func _escape_futile(seed: int, v: int, color: int) -> bool:
	var opp := 3 - color
	var ply0 := _ply
	_lad_nodes = 0
	var fut := false
	if _play(v) >= 0:
		if _libs(_group(seed), -1) >= 2:
			var conts: Array[int] = []
			if _atari_points(seed, opp, conts) > 0:
				for q in conts:
					var ply1 := _ply
					var caught := false
					if _play(q) >= 0:
						caught = _ladder_chase(seed, opp, 0)
					while _ply > ply1:
						_undo()
					if caught:
						fut = true
						break
	while _ply > ply0:
		_undo()
	return fut


## 自检探针（--ladtest 用）。
## 征子推演依赖引擎内部棋盘 `_b` / 手番 `_turn`，而 `_b` 只在 `_load_board()`（即 `choose_move`
## 起始）才从外部棋盘同步 —— 直接从外部调 `_ladder_works` 会打在没摆子的空盘上，判定恒为假。
## 所以这里借一次真实的 choose_move 把局面载进来，落子后再在引擎内部调用判定。
## 返回 {"move": 选着, "ladder": 落子点的征子判定, "playouts": ...}
func probe_ladder(board_dict: Dictionary, v: int) -> Dictionary:
	load_board_for_probe(board_dict)
	_turn = ai_color
	var ok := _ladder_works(v, ai_color)
	return {"move": v, "ladder": ok, "turn": _turn}


## 只把外部棋盘同步进引擎（自检用；不含搜索）
##
## ★★ `ko` 参数（2026-10-02 加，`--rulestest` 逼出来的）：原来**硬编码 -1**，
##   于是"问引擎某个点是不是劫点"这件事**永远测不到** —— 载入就把劫点清了，
##   `_play()` 走的是"已占/自杀"分支，不是劫点分支。
##   实测踩到：判据先在载入后手工 `ai_engine._ko = ctrl`，但紧接着又
##   `load_board_for_probe()` 把它冲回 -1 ⇒ 读数"恒放行"，看着像两侧一致。
##   ⇒ 劫点必须**随棋盘一起进**（`ko` 缺省 -1 保持既有 5 个调用点行为不变）。
func load_board_for_probe(board_dict: Dictionary, ko: int = -1) -> void:
	_load_board(board_dict, ko)


## 根先验分数探针（--ladtest 用）：把局面载入后返回 `_root_score(v, -1)`。
## 这是**确定性**的（不含搜索/随机/线程），所以适合做回归断言 ——
## 而「比较 choose_move 的选着」会因时间预算与多线程而飘（实测同局面两次跑结论不同）。
func probe_root_score(board_dict: Dictionary, v: int, turn_color: int) -> float:
	load_board_for_probe(board_dict)
	_turn = turn_color
	_ko = -1
	return _root_score(v, -1)


## ★ 同上，但**可指定 `last`（对手上一手）** —— 2026-10-04 为修--aidata 加。
## 【为什么必须有这个】`_root_score()` 里`w_local`（贴身应战）的触发条件是
##   `if last >= 0 and _is_adj(v, last)`（:2715）—— **依赖 last**。
## 而旧的 `probe_root_score()` 把 `last` 写死 -1 ⇒ `w_local` 分支**永不进入**
## ⇒ `--aidata` 反解出来的 `w_local` 特征**恒为 0**（实测 72927 行里非零行数 = 0）
## ⇒ 训练器对它**没有梯度**，学到的值必然 == 默认值。
## 而 `w_local` 恰是第一档爬山选出的**跨盘冠军参数** ⇒ 第二档学不到最重要的那个先验。
## ⇒ 落盘必须传真实的对手上一手。
func probe_root_score_last(board_dict: Dictionary, v: int, turn_color: int,
		last: int) -> float:
	load_board_for_probe(board_dict)
	_turn = turn_color
	_ko = -1
	return _root_score(v, last)


## ★ 落盘用：**按盘面差分推断对手上一手**，与 `_infer_opp_move()` **同一套语义**。
## 【为什么不直接用 game.gd 的 `_last_move`】引擎选点时认的是"唯一一个新增的对手子"
## （`_infer_opp_move`：多于一个新增就返回 -1，因为无法确定是哪一手）。
## 落盘必须与运行路径**同口径**，否则特征量到的是另一件事（铁律：判据读真源）。
## 传入 `prev_board` = 上一步之前的盘面快照（game.gd 侧自己维护一份即可）。
func probe_opp_last(board_dict: Dictionary, prev_board: Dictionary, turn_color: int) -> int:
	var opp := 3 - turn_color
	var found := -1
	var cnt := 0
	# ⚠️ `board` 是 **Dictionary**（记忆铁律：`board[i] = ...`）⇒ **`size()` 返回键个数，
	#   不是下标上界**。直接 `for i in board_dict.size()` 会把循环上界当成"元素个数"，
	#   于是只扫了前 N 个下标（实测表现为 w_local 仍恒 0 —— 判据报红是对的，修复没生效）。
	# ⇒ 必须走 keys()拿真实下标。
	var keys := board_dict.keys()
	for i in keys:
		if not prev_board.has(i):
			continue
		if int(prev_board[i]) == EMPTY and int(board_dict[i]) == opp:
			found = i
			cnt += 1
			if cnt > 1:
				return -1
	return found


## ★★ 落盘用：**一次**返回全部 18 项（17 个 w_* 的原始量 + emp_nb）+ base/orig。
##   返回 {terms: PackedFloat32Array(18), base: float, orig: float}。
##
## 【为什么必须一次算完，而不是权重基分解的 19 次 `_root_score()`】
##   旧做法：置 1 个 w=1、其余 0，反解该项 ⇒ 每候选 19 次调用。而 `_root_score()`
## 里挂着**眼位穷举**（`ld_node_budget=8000`）和**征子推演**
##   （`ladder_node_budget=600`）⇒ 实测 8 分钟只落 2 个局面，18 局采集不可行。
##   而 `_root_score()` 对 17 个 `w_*` **严格仿射**（所有分支门只读盘面，
##   见 `_root_terms()` 头部注释）⇒ 一次遍历就够，19 次纯属把同一批推演重算 19 遍。
##   实测提速约 19 倍，落盘口径与旧实现**逐位相同**（由 `--aibench` 恒等式自检钉住）。
##
## 【与旧口径的等价性】`orig` 仍用**当前权重**算（不是 17 个都为 0），
##   所以恒等式 `orig == base + Σ w_i · terms_i` 依然逐位成立 —— 这条判据
##   既验证仿射性没被破坏，也让训练器能在落盘时自检漂移。
func probe_root_terms_last(board_dict: Dictionary, v: int, turn_color: int,
		last: int) -> Dictionary:
	load_board_for_probe(board_dict)
	_turn = turn_color
	_ko = -1
	var base: float = _root_terms(v, last)
	var orig: float = base
	for i in ROOT_W.size():
		orig += float(self.get(ROOT_W[i])) * _rt[i]
	var terms := _rt.duplicate()
	return {"terms": terms, "base": base, "orig": orig}


## 根先验 argmax 探针（--ailife 用）：一次载入扫完所有空点，返回最高/次高分的点号。
## 与 `choose_move` 的区别：**完全确定性**（无搜索、无线程、无时间预算），所以能直接当回归断言；
## 而 `choose_move` 的选着会随预算与线程数飘（实测同局面两次跑结论不同）。
func probe_root_argmax(board_dict: Dictionary, turn_color: int) -> Dictionary:
	load_board_for_probe(board_dict)
	_turn = turn_color
	_ko = -1
	var best := -1
	var second := -1
	var bs := -1.0e18
	var b2 := -1.0e18
	for v in n:
		if _b[v] != EMPTY:
			continue
		var sc := _root_score(v, -1)
		if sc > bs:
			b2 = bs
			second = best
			bs = sc
			best = v
		elif sc > b2:
			b2 = sc
			second = v
	return {"best": best, "score": bs, "second": second, "score2": b2}


## 眼位空间死活探针（--ailife 用）：对 start 所在的整串返回
##   {"status": 0/1/2, "region": 眼位点数, "kills": 攻方杀点点号数组, "bailouts": 累计超预算次数}
## 纯判定、无搜索/随机器 → 确定性，可直接做回归断言。
## 仅供自检：装盘后返回 `v` 处「己方空区」两层判定的结论 —— 与 `_own_territory_only()` **同源**
## （直接调 `_own_area_layers()`，不另写一份 BFS，否则两处口径早晚分岔）。
##
## 为什么要它：过滤层的层 B 用的是**旧**判据 `_group_alive()`（≥2 只单点眼 **或** 气 ≥6），
## 而真死活求解器是 `_group_status()`。把两者的结论并排打出来，才能看出「谁封了谁」。
func probe_own_area(board_dict: Dictionary, v: int, turn_color: int) -> Dictionary:
	load_board_for_probe(board_dict)
	_turn = turn_color
	_sc_id += 1                        # 与 `_prepare_root()` 一致：一次探测作废一次缓存
	var lay := _own_area_layers(v)
	var rep := _eye_rep_at(v)
	var st := -1
	var libs := -1
	var region := 0
	if rep >= 0:
		var cnt := _group(rep)
		libs = _libs(cnt, -1)
		st = _group_status(cnt, libs)
		region = _ld_n
	var alive_old: bool = false
	if rep >= 0:
		var cnt2 := _group(rep)
		alive_old = _group_alive(cnt2)
	return {"layer_a": bool(lay[0]), "layer_b": bool(lay[1]),
		"blocked": bool(lay[0]) and bool(lay[1]),
		"status": st, "libs": libs, "region": region, "eye_rep": rep,
		"alive_old": alive_old}


func probe_ld(board_dict: Dictionary, start: int) -> Dictionary:
	load_board_for_probe(board_dict)
	var cnt := _group(start)
	var st := _group_status(cnt, _libs(cnt, -1))
	var pts: Array[int] = []
	if _ld_n > 0:
		var km := _ld_kill_mask(_ld_n)
		var i := 0
		while i < _ld_n:
			if (km & (1 << i)) != 0:
				pts.append(_ld_pts[i])
			i += 1
	return {"status": st, "region": _ld_n, "libs": _libs(cnt, -1),
		"kills": pts, "bailouts": last_ld_bailouts}


## 价值头（第二档，2026-09-28）：在草稿盘上真实落 v、提掉 0 气对方串，
## 然后按训练口径（--aidata V 行特征从**行棋方**视角算、y = 行棋方终局目差，
## 训练器 aidata_value_train.py）算 7 维棋块安危特征。
## 落子后行棋方是**对方** → 特征从对方视角算，预测取负 = 我方目差。单位 = 目。
## ★ 只在 _root_score 出口按 value_blend 混入（根准备每候选一次，不在模拟热路径）。
func _value_after_move(v: int, color: int) -> float:
	var opp := 3 - color
	var tmp := _b.duplicate()
	tmp[v] = color
	var seen := PackedInt32Array()
	seen.resize(n)
	var lseen := PackedInt32Array()
	lseen.resize(n)
	var q := PackedInt32Array()
	var lsz := 0                      # lseen 戳号：跨串递增，不许重置（重置会让第二串把
									  # 第一串标过的气点当成「没见过」→ 气数虚高 → 漏提）
	# ① 提掉 0 气的对方串
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if tmp[nb] != opp or seen[nb] != 0:
			continue
		seen[nb] = 1
		q.clear()
		q.append(nb)
		var qi := 0
		var gsz := 0
		var libs := 0
		lsz += 1
		var rm: Array[int] = []
		while qi < q.size():
			var cur := q[qi]
			qi += 1
			gsz += 1
			rm.append(cur)
			var j := _as[cur]
			var je := _as[cur + 1]
			while j < je:
				var w := _af[j]
				j += 1
				if tmp[w] == EMPTY:
					if lseen[w] != lsz:
						lseen[w] = lsz
						libs += 1
				elif tmp[w] == opp and seen[w] == 0:
					seen[w] = 1
					q.append(w)
		if libs == 0:
			for st in rm:
				tmp[st] = EMPTY
	# ② 7 维特征：p = 对方（落子后的行棋方）。own_* = p 的棋块。
	var p := opp
	for i in n:
		seen[i] = 0
	var fa_st := 0.0
	var fa_grp := 0.0
	var fb_st := 0.0
	var fb_grp := 0.0
	var fa_2lib := 0.0
	var fb_2lib := 0.0
	var p_st := 0
	var o_st := 0
	var stamp := 0
	for s0 in n:
		if seen[s0] != 0 or tmp[s0] == EMPTY:
			continue
		var c := tmp[s0]
		stamp += 1
		var lsz2 := stamp
		seen[s0] = 1
		q.clear()
		q.append(s0)
		var qi2 := 0
		var gsz2 := 0
		var libs2 := 0
		while qi2 < q.size():
			var cur2 := q[qi2]
			qi2 += 1
			gsz2 += 1
			var j2 := _as[cur2]
			var je2 := _as[cur2 + 1]
			while j2 < je2:
				var w2 := _af[j2]
				j2 += 1
				if tmp[w2] == EMPTY:
					if lseen[w2] != lsz2 + 1000000:
						lseen[w2] = lsz2 + 1000000
						libs2 += 1
				elif tmp[w2] == c and seen[w2] == 0:
					seen[w2] = 1
					q.append(w2)
		if c == p:
			p_st += gsz2
			if libs2 == 1:
				fa_st += float(gsz2)
				fa_grp += 1.0
			elif libs2 == 2:
				fa_2lib += 1.0
		else:
			o_st += gsz2
			if libs2 == 1:
				fb_st += float(gsz2)
				fb_grp += 1.0
			elif libs2 == 2:
				fb_2lib += 1.0
		if s0 == v and c == color and libs2 == 0:
			return 0.0              # 自杀（非法，候选层应已滤）→ 中性兜底
	var pred := v_bias \
		+ v_own_atari_st * fa_st + v_own_atari_grp * fa_grp \
		+ v_opp_atari_st * fb_st + v_opp_atari_grp * fb_grp \
		+ v_own_2lib_grp * fa_2lib + v_opp_2lib_grp * fb_2lib \
		+ v_stone_diff * float(p_st - o_st)
	return -pred                       # 预测的是对方的目差 → 取负 = 我方


## ★ 一次遍历算出 17 项先验的**原始量**（不是分数）+ base，返回 base。
##   量写入成员 `_rt`（长 18：前 17 项对应 ROOT_W，最后一项是 emp_nb）。
##   `score = base + Σ ROOT_W[i] * _rt[i]` —— 对 w_* 严格仿射，见文件头说明。
##   ⚠️ 不要在这里读任何 w_***（除了最后乘那一步）—— 一旦某个分支门改成读权重，
##   仿射性就破了，`--aibench` 恒等式自检会立刻报红。
func _root_terms(v: int, last: int) -> float:
	_rt.resize(18)
	_rt.fill(0.0)
	if _b[v] != EMPTY or v == _ko:
		return -1.0e9
	var color: int = _turn
	var opp := 3 - color

	# 对方串：提子数
	var caps := 0
	_cid += 1
	var cid := _cid
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != opp or _cst[nb] == cid:
			continue
		var gsz := _group(nb)
		for j in gsz:
			_cst[_gbuf[j]] = cid
		if _libs(gsz, v) == 0:
			caps += gsz

	# 己方被打吃的串：v 能否救回
	var saved := 0
	var run_wt := 0.0                      # 「逃了也白逃」的子数权重（sqrt 加权，与 save 同口径）
	_cid2 += 1
	var cid2 := _cid2
	k = _as[v]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != color or _cst2[nb] == cid2:
			continue
		var gsz := _group(nb)
		for j in gsz:
			_cst2[_gbuf[j]] = cid2
		if _libs(gsz, -1) == 1:
			# 2026-09-20 逃征子判定：逃出去之后攻方按同一套推演仍征得死 → 逃跑是废手，
			# 不给 w_save_each 奖励、改记 run_wt（评分处加 w_ladder_run 小惩罚）。
			if ladder_enabled and ladder_escape_check and _escape_futile(nb, v, color):
				run_wt += sqrt(float(gsz))
			else:
				saved += gsz

	# 自杀检查（有提子则跳过）
	var mylibs := 0
	if caps == 0:
		_gid += 1
		var sid := _gid
		_gbuf[0] = v
		_gst[v] = sid
		var cnt := 1
		var qi := 0
		while qi < cnt:
			var cur := _gbuf[qi]
			qi += 1
			var kk := _as[cur]
			var ke2 := _as[cur + 1]
			while kk < ke2:
				var nb := _af[kk]
				kk += 1
				if _b[nb] == color and _gst[nb] != sid:
					_gst[nb] = sid
					_gbuf[cnt] = nb
					cnt += 1
				elif _b[nb] == EMPTY and nb != v and _gst[nb] != sid:
					_gst[nb] = sid
					mylibs += 1
		if mylibs == 0:
			return -1.0e9      # _rt 已清零 ⇒ 与旧的 base/orig 口径一致
	else:
		mylibs = 4

	var base := 0.0
	if caps > 0:
		_rt[0] += 1.0
		_rt[1] += float(caps)
	_rt[2] += float(saved)
	if run_wt > 0.0:
		_rt[3] += run_wt

	# 威胁：把对方某串打到只剩一气（按对方串规模加权）
	var threat := 0
	_cid += 1
	cid = _cid
	k = _as[v]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] != opp or _cst[nb] == cid:
			continue
		var gsz := _group(nb)
		for j in gsz:
			_cst[_gbuf[j]] = cid
		if caps == 0 and _libs(gsz, v) == 1:
			threat += gsz
			# 征子判定（新算法）：叫吃未必吃得掉。逃不掉的才重奖，逃得掉的按无效叫吃扣分
			# ——旧行为是一律按 w_threat_each 加分，于是 AI 爱走「打一下、对方一长就跑」的废手。
			if ladder_enabled and gsz >= ladder_min_size:
				if _ladder_works(v, color):
					_rt[5] += sqrt(float(gsz))
				else:
					_rt[6] += sqrt(float(gsz))
		_rt[4] += float(threat)

	if mylibs == 1 and caps == 0:
		_rt[7] += 1.0
	_rt[8] += float(mini(mylibs, 4))
	# ---- 真·自紧气惩罚（连通 / 己方空区做眼豁免）----
	# 判据与 game.gd 的 `_ai_move_gate` 拆分完全同口径（技能 Part 9：先拆再罚）。
	# 前提：caps == 0（提子手是好手；且提子分支里 mylibs 不是真实气数）。
	# gate 那边 libs_before 含 v（此刻还是空点）、判「落子后 < 前」；这边并集不含 v，
	# 等价条件是 mylibs <= union_before —— 落子后的新块气 = 并集气 ∪ v 的空邻点，
	# 只有 v 的空邻点全在并集里（这手不带来任何新气）时才可能命中。
	# 豁免（都是正手，不许削）：own_groups >= 2 → 连通（并块必然气少 1，
	# gate 实测占 lib_drop 一半）；空区边界无对方子 → 己方空区做眼/补活。
	# mylibs == 1 是自送吃，上面 w_self_atari 已罚，gate 同口径不重复计。
	if caps == 0 and mylibs >= 2 and tighten_check:
		_cid2 += 1
		var tid := _cid2
		var own_groups := 0
		var union_before := 0
		_lid += 1
		var lid2 := _lid
		var tk := _as[v]
		var tke := _as[v + 1]
		while tk < tke:
			var tnb := _af[tk]
			tk += 1
			if _b[tnb] != color or _cst2[tnb] == tid:
				continue
			own_groups += 1
			var tgsz := _group(tnb)
			for j in tgsz:
				_cst2[_gbuf[j]] = tid
			for j in tgsz:
				var tp := _gbuf[j]
				var tkk := _as[tp]
				var tkee := _as[tp + 1]
				while tkk < tkee:
					var tq := _af[tkk]
					tkk += 1
					if _b[tq] == EMPTY and tq != v and _lst[tq] != lid2:
						_lst[tq] = lid2
						union_before += 1
		if own_groups == 1 and union_before > 0 and mylibs <= union_before \
				and _root_region_has_enemy(v, opp):
			_rt[9] += 1.0

	var own_nb := 0
	var emp_nb := 0
	k = _as[v]
	while k < ke:
		var nb := _af[k]
		k += 1
		var cc := _b[nb]
		if cc == color:
			own_nb += 1
		elif cc == EMPTY:
			emp_nb += 1
	_rt[10] += float(own_nb)
	base += 0.15 * float(mini(emp_nb, 4))       # 写死的常数项，不参与重训
	_rt[11] += _cent[v]
	if last >= 0 and _is_adj(v, last):
		_rt[12] += 1.0

	# ---- 补强：v 邻接的己方块气紧、且尚未活时，落子能长气就奖励 ----
	# 只在 v 邻接「尚未活、气又不宽裕」的棋块时才落子模拟，属稀有路径。
	if caps == 0:
		_cid2 += 1
		var wid := _cid2
		k = _as[v]
		ke = _as[v + 1]
		while k < ke:
			var nb2 := _af[k]
			k += 1
			if _b[nb2] != color or _cst2[nb2] == wid:
				continue
			var gsz2 := _group(nb2)
			for j in gsz2:
				_cst2[_gbuf[j]] = wid
			var libs_before := _libs(gsz2, -1)
			if libs_before > 3:
				continue                       # 气还不算紧，不急着补（太宽会到处补、失去先手）
			var eyes_before := 0
			if ld_enabled:
				if _group_status(gsz2, libs_before) == 2:
					continue                   # 已无条件活（直四/曲四/葡萄六等大眼活形）→ 不必再补
			else:
				eyes_before = _count_eyes(gsz2)
				if eyes_before >= 2:
					continue                   # 旧口径：单点真眼 ≥ 2
			if _play(v) >= 0:
				var gsz3 := _group(v)          # 落子后 v 已与本块联通，重新收集
				var libs_after := _libs(gsz3, -1)
				var wgt := sqrt(float(gsz3))
				var made_eye := false
				if not ld_enabled:
					made_eye = _count_eyes(gsz3) >= 2 and eyes_before < 2
				if made_eye:
					_rt[14] += wgt           # 旧口径做活奖励（阴性对照 / 回退用）
				elif libs_after > libs_before:
					_rt[13] += wgt
				_undo()
	# ---- 眼位要点（做活 / 点杀**同一判据**）----
	# 旧实现的两个死角都在这里消掉：
	#   ① 只认「单点真眼」（`_count_eyes`）→ 弯三 / 丁四 / 梅花五 / 刀把五 这些
	#      **要点不在串上**的形状完全看不见（梅花五的要点是十字中心，它四邻全空）；
	#   ② 拿「落子后 `_group_status == 2`」当做活判据也救不回来 —— 落在梅花五中心的那子
	#      **不与本块连通**（四邻全是空点），收集到的是孤立单子，判不出活。
	# 现在改成「v 所在眼位空间的攻方杀点集」→ 与连通性无关，且做活与点杀共用一条真源结论
	# （攻方杀点集 ⊆ 防守方做活要点集，未定形小形里两者重合 = 「敌之要点即我之要点」）。
	# 开销：`_eye_rep_at` 的小 BFS 上限 `ld_cap_points` 点，开阔处几个点就超限退出 → 常数级。
	if caps == 0 and ld_enabled:
		# 与 `_eye_vital_bonus()` **同判据**（`_eye_vital_flags()` 是唯一真源），
		# 只把「乘 w_eye_make 还是乘 w_kill_point」换成记到对应的量槽。
		var vf_b := _eye_vital_flags(v)
		if bool(vf_b[1]):
			var rep_b: int = int(vf_b[2])
			var wgt_b := sqrt(float(_group(rep_b)))
			if _b[rep_b] == color:
				_rt[14] += wgt_b        # 己方未定形 → 抢要点做活
			else:
				_rt[15] += wgt_b        # 对方未定形 → 抢要点点杀
	# ---- 白填己方眼位（豁免开闸的副作用，见 `w_fill_own_eye` 的声明处）----
	# 与上面那条互补：`_eye_vital_bonus()` 只**奖励要点**，不惩罚「同一片空间里的非要点」。
	# 而豁免是**整片**开闸的，于是非要点也成了候选（还要吃 `w_conn` 的贴子奖励）——
	# `--aieye` 实测自战里每局仍有 1~2 手这么白填，且出现过填完该块只剩 1 气的致命一例。
	# 判据收得很窄（三条豁免，缺一条都会误伤正手）：
	#   ① 必须落在**己方**的小眼位空间里（`_eye_rep_at()` 能识别 = 封闭小空间）；
	#   ② **该空间必须识别得出要点**（`_eye_vital_flags()[0]`）。模型给不出杀点集时
	#      （非封闭区域 / 区域吸收了外气点）**禁止惩罚** —— 否则会把棋理上的那个要点
	#      连同整片空间一起罚掉。实测漏了这条：直三/弯三 +3 外气 的要点被挤出候选集。
	#   ③ v 本身不是要点，且不是「接」（相邻 ≥2 块己方棋 —— 从假眼里接出去是正手）。
	if caps == 0 and fill_own_eye_check and ld_enabled:
		var vf := _eye_vital_flags(v)
		if bool(vf[0]) and not bool(vf[1]):
			var rep_f: int = int(vf[2])
			if _b[rep_f] == color:
				_cid2 += 1
				var cid_f := _cid2
				var og := 0
				var kf := _as[v]
				var kfe := _as[v + 1]
				while kf < kfe:
					var nf := _af[kf]
					kf += 1
					if _b[nf] != color or _cst2[nf] == cid_f:
						continue
					og += 1
					var gsf := _group(nf)
					for j in gsf:
						_cst2[_gbuf[j]] = cid_f
				if og < 2:
					var cnt_f := _group(rep_f)
					_rt[16] += sqrt(float(cnt_f))
	# 价值头混入（第二档）：value_blend == 0 时完全不走这段（零开销，且
	# --aidata 权重基分解 / --ladtest 差值口径不受影响 —— 混入项在同一局面
	# 的两次评分差里恒相消）。
	if value_blend != 0.0:
		base += value_blend * _value_after_move(v, color)
	_rt[17] = float(mini(emp_nb, 4))
	return base


## 根先验分数 = base + Σ ROOT_W[i]·量 —— **唯一实现**，热路径与落盘共用。
##   薄封装不是重复实现：量只由 `_root_terms()` 算一次，这里只做点积。
## 局势加成：**只读**，按 `_sc_id` 缓存（一次全盘扫描，n 个候选点共用）。
## ★ 2026-10-08：缓存的**唯一**失效来源是 `_sc_id`；推进它的地方有三个 ——
##   `_prepare_root()`、`probe_own_area()`、以及 `_load_board()`（换盘必须作废，见那里的注释）。
##   修前 `_load_board()` 不推 ⇒ 探针换盘后会拿到**上一局**的分析（`--scidtest` 判据 A）。
func _anlz() -> Dictionary:
	if _an_cache_id == _sc_id:
		return _an_cache
	# 引擎内部的棋盘快照： 给的是 Dictionary，ko 用当前的 _ko。
	_an_cache = analyze_board(export_board(), _ko)
	_an_cache_id = _sc_id
	return _an_cache

## 候选点 `v` 的局势加成。三项各自对应用户报的那个病：
##  · 落在**己方未定形块的要点**上 ⇒ 救活（`w_rescue_own_live`）
##  · 落在**对方死块**里⇒ 提子是真目（`w_capture_dead`）
##  · 落在**已被对方围死**的空区里 ⇒ 无谓投入（`w_sealed_territory`，负）
func _analyze_bonus(v: int) -> float:
	if not use_analyze_bonus:
		return 0.0
	var an := _anlz()
	var add := 0.0
	var tagd: Dictionary = an.get("tag_of", {})
	# ① 救活：`_eye_vital_flags` 是**唯一真源**（与 `w_eye_make` 同口径，铁律 18）
	# ★★ 2026-10-08 修：必须**再卡一道颜色**。`_eye_vital_flags(v)[1]` 只说
	#   「v 是某个**未定形块**的要点」，它**不分颜色** —— 对方未定形块的要点同样返回 true。
	#   原实现于是把「救己方」的 18 分发给了「点杀对方」的手，而 `_rt[15]`（w_kill_point）
	#   那边还照发一份 ⇒ 同一个点吃两份奖励，其中一份名不副实。
	#   这类「名字与行为对不上」是静默的：看分值、看日志、跑回归都看不出来。
	if w_rescue_own_live != 0.0:
		var vf := _eye_vital_flags(v)
		if bool(vf[1]) and int(_b[int(vf[2])]) == ai_color:
			add += w_rescue_own_live
	# ② 提对方死子：候选点周围有对方 DEAD 块的子
	# ★★ 2026-10-08 修：原实现是 `_find_block(an, _group(nb), opp_col)` ——
	#   `_group()` 返回**成员计数**，而 `_find_block` 的形参是**代表点点号**
	#   ⇒ 拿「块有几子」去比「代表点坐标」= **量纲错配**，只有极偶然才撞上
	#   （`--anlzmis` D 列实测：现状口径 0 次）。
	#   现在直接查 `tag_of`：邻点本身就是块成员，O(1) 且无歧义。
	if w_capture_dead != 0.0:
		var opp_col := 3 - ai_color
		var k := _as[v]
		var ke := _as[v + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			if _b[nb] == opp_col and String(tagd.get(nb, "")) == "DEAD":
				add += w_capture_dead
				break
	# ③ 被围死的空区：不许投子。
	#   两个必要条件（缺一不可）：
	#     ① `_sealed_color(v) >= 0` —— 该空区被**单一颜色完整包围**（-1 触两色/-2 触边缘）
	#     ② 对方在该区附近**已有活块** —— 围一个没有子的空区没有棋理意义
	#★ 第一版只有①的弱版本（"只被一种颜色围"，边缘不算色）⇒ 实测 98.8% 的空点被罚。
	if w_sealed_territory != 0.0:
		var seal := _sealed_color(v)
		if seal >= 0 and seal != ai_color and _has_live_block_near(an, v, seal):
			add += w_sealed_territory
	return add

## 顶点 `v` 的邻域里有没有颜色 `col` 的**已活**块（有活块才谈得上"这块地被围死了"）。
##
## ★★ 2026-10-08 修（两处，都是静默漏判）：
##   ① 原实现只比**代表点**：`_is_adj(rep, v)`。`rep` 是该块里**点号最小**的那个子，
##      一块棋几十个子时，v 明明挨着块尾却离代表点很远 ⇒ 查不到 ⇒ ③ 机制漏触发。
##      实测（`--analyzetest` ⑩）：v=140 与块内子 (6,7) 相邻，而代表点 100 与 v 不相邻
##      ⇒ 原实现返回 false（正确口径应为 true）。阴性对照（远离该块的点）两边都 false。
##   ② 改成查 `tag_of`（点 → tag，由 `analyze_board` 一次建好，O(1)）：
##      直接看 v 的邻点里有没有「颜色 col 且 tag=LIVE」的子 = **整块口径**，
##      且不必再「拿 rep 去 blocks_* 里找块」。
func _has_live_block_near(an: Dictionary, v: int, col: int) -> bool:
	var tagd: Dictionary = an.get("tag_of", {})
	if tagd.is_empty():
		return false
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		if _b[nb] == col and String(tagd.get(nb, "")) == "LIVE":
			return true
	return false

## 在 analyze_board 的清单里找「含代表点 `rep` 的那一块」（找不到返回 {}）。
## ⚠️ 2026-10-08 起**引擎内已无调用者**：② 改走 `tag_of` 按子查表了。
##   保留它只为 `game.gd` 的诊断探针（`_anlzmis` 的 D 列要复现「量纲错配」的历史口径，
##   好让「修前 0 次 / 修后 N 次」这个对照能重跑）。
##   ★ 新代码不要再用它 —— 它的形参是**代表点点号**，而调用方很容易顺手传进
##   `_group()` 的**计数**（那正是它历史上出过的那次 bug，且完全静默）。
func _find_block(an: Dictionary, rep: int, col: int) -> Dictionary:
	var key := "blocks_black" if col == BLACK else "blocks_white"
	for b: Dictionary in an.get(key, []):
		if int(b.get("rep", -1)) == rep:
			return b
	return {}

func _root_score(v: int, last: int) -> float:
	var b := _root_terms(v, last)
	var s := b
	for i in ROOT_W.size():
		s += float(self.get(ROOT_W[i])) * _rt[i]
	# ★ 局势加成（2026-06）：解决「落后时宁可去对方地盘落子也不救自己死块」。
	#   这三项**只读**、不改既有棋理判据；权重全@export（运行期可调）。
	#   ⚠️ `_analyze_bonus` 内部会调 `_group` / `_eye_vital_flags`，它们会动 `_gbuf` 等缓冲
	#   ⇒ 必须在 `_root_terms` **之后**调用（那时 `_rt` 已经取完）。
	s += _analyze_bonus(v)
	return s


## 内部节点的轻量先验，直接作为初始 Q 使用（量纲 = 胜率）
func _quick_prior(v: int, nc: int) -> float:
	var color := _tn_st[_ply - 1]
	var opp := 3 - color
	var s := 0.40 + 0.18 * _cent[v]
	if nc > 0:
		s = 0.72 + 0.05 * float(nc)
	else:
		var gsz := _group(v)
		var l := _libs(gsz, -1)
		if l == 1:
			s -= 0.26
		elif l >= 3:
			s += 0.05
	var own := 0
	var op := 0
	var k := _as[v]
	var ke := _as[v + 1]
	while k < ke:
		var nb := _af[k]
		k += 1
		var cc := _b[nb]
		if cc == color:
			own += 1
		elif cc == opp:
			op += 1
	s += 0.05 * float(own) + 0.03 * float(op)
	return clampf(s, 0.05, 0.95)


## 把启发式分数转成归一化的先验概率分布（softmax，先归一化到 [0,1] 再取指数）
func _softmax_priors(scores: Array[float]) -> Array[float]:
	var out: Array[float] = []
	if scores.size() == 0:
		return out
	var mn := 1.0e9
	var mx := -1.0e9
	for s in scores:
		if s < mn:
			mn = s
		if s > mx:
			mx = s
	var span := mx - mn
	if span < 1.0e-6:
		var u := 1.0 / float(scores.size())
		for s in scores:
			out.append(u)
		return out
	var tot := 0.0
	var t := maxf(prior_temp, 0.02)
	for s in scores:
		var z := (s - mn) / span
		var e := exp(z / t)
		out.append(e)
		tot += e
	for i in out.size():
		out[i] = out[i] / tot
	return out


# ============================================================================
#  树策略
# ============================================================================
## 根节点：PUCT 探索项 + RAVE(AMAF) 与 MC 值按 β 混合
func _select_root_child(root: MNode) -> MNode:
	var best: MNode = null
	var bs := -INF
	var sq := sqrt(float(max(root.visits, 1)))
	for c in root.children:
		var v := float(c.visits)
		var q: float = c.wins / v
		var an := _an[c.move]
		if an > 0.0:
			var beta: float = rave_equiv / (rave_equiv + v)
			q = (1.0 - beta) * q + beta * (_aw[c.move] / an)
		var sc := q + c_puct * c.prior * sq / (1.0 + v)
		if sc > bs:
			bs = sc
			best = c
	return best


## 内部节点：PUCT（先验引导的 UCT）
func _select_child(node: MNode) -> MNode:
	var best: MNode = null
	var bs := -INF
	var sq := sqrt(float(max(node.visits, 1)))
	for c in node.children:
		var v := float(c.visits)
		var sc: float = c.wins / v + c_uct * c.prior * sq / (1.0 + v)
		if sc > bs:
			bs = sc
			best = c
	return best


## 一次 MCTS 迭代：下探 → 展开 → rollout → 回传
func _iterate(root: MNode) -> void:
	_logn = 0
	if prof_on:
		prof_iters += 1
	var node: MNode = root
	_path.clear()          # 复用成员缓冲，避免每次迭代分配数组

	# --- 树策略：只穿越“已完全展开且有子”的节点 ---
	# guard 必须无条件递增：若 _play 失败走 continue，跳过递增会死循环
	var guard := 0
	while node.children.size() > 0 and guard < 512:
		guard += 1
		# 渐进加宽（progressive widening）：允许的子节点数随访问数缓慢放开。
		# 旧条件是「node.nxt >= n」——要求把一个节点的 n 个空点全部试过才允许继续下探。
		# 标准盘 n=120、加强盘 n=360，而预算内每个节点只有几十次访问，永远达不到，
		# 于是树恒为 2 层、AI 完全没有前瞻（做活/对杀是 3~5 手的连续手段，深度 2 看不见）。
		if node.nxt < n and node.children.size() < _widening_limit(node.visits):
			break
		if _path.size() >= max_tree_depth:
			break
		var child := _select_root_child(root) if node == root else _select_child(node)
		if child == null:
			break
		if _play(child.move) < 0:
			child.visits += 1
			continue
		node = child
		_path.append(node)

	# --- 展开：沿随机排列找一个尚未尝试过的合法着法 ---
	if node.nxt < n:
		while node.nxt < n:
			var mv := _perm[(node.off + node.nxt) % n]
			node.nxt += 1
			if mv == _ko or _b[mv] != EMPTY:
				continue
			var nc := _play(mv)
			if nc < 0:
				continue
			var cn := MNode.new()
			cn.move = mv
			cn.player = 3 - _turn      # _play 已翻转 turn，落子方是原 turn
			cn.prior = _quick_prior(mv, nc)
			cn.off = rng.randi() % n
			cn.visits = int(maxf(prior_visits_inner, 1.0))
			cn.wins = cn.prior * float(cn.visits)
			node.children.append(cn)
			node = cn
			_path.append(cn)
			break

	# --- rollout ---
	var res := _playout(node.move)

	# --- 回传（root 不入 path，其 visits 由调用方累计）---
	for p in _path:
		p.visits += 1
		if p.player == WHITE:
			p.wins += res
		else:
			p.wins += 1.0 - res

	# --- RAVE(AMAF)：把本次模拟走过的所有着法按根视角记账 ---
	var rp := ai_color
	var rp_res := res if rp == WHITE else 1.0 - res
	for i in _logn:
		var m := _log[i]
		_an[m] += 1.0
		_aw[m] += rp_res if _logc[i] == rp else (1.0 - rp_res)

	if prof_on:
		var d := _path.size()
		prof_depth_sum += d
		if d > prof_depth_max:
			prof_depth_max = d

	while _ply > 0:
		_undo()


## 准备根节点：算出全部合法候选的启发式评分，按先验剪枝成 Top-K，返回 {cands, priors}
##
## 停一手逻辑：若某空点所在的整片空区边界只有己方棋子（纯己方领地/眼位），
## 落子纯属自填、毫无收益，直接过滤；全部被过滤则 cands 为空 → 调用方返回 -1（停一手）
func _prepare_root(opp_last: int) -> Dictionary:
	_sc_id += 1                    # 新的一手：作废「纯领地」缓存
	var cands: Array[int] = []
	var scores: Array[float] = []
	var blocked: Array[int] = []
	for v in n:
		if _b[v] != EMPTY or v == _ko:
			continue
		if _own_territory_only(v):
			continue
		# ★★ 2026-10-08：空区硬过滤（③ 软权重 → 硬过滤 + 扩面）。见 `_sealed_by_opp_hard()`。
		#   放在 `_root_score` **之前**：硬过滤的定义与分数无关，先剔掉能省下这些点的打分
		#   （眼位穷举 + 征子推演都不便宜）。
		if _sealed_by_opp_hard(v):
			blocked.append(v)
			continue
		var s := _root_score(v, opp_last)
		if s <= -0.5e9:
			continue
		cands.append(v)
		scores.append(s)

	# ★ 安全阀（2026-10-08）：硬过滤**不许**把候选剔空 —— `choose_move()` 拿到空候选会
	#   直接返回 -1（停一手），那会被读成"AI 主动弃权"，而绝大多数局面下这是错的
	#   （真该弃权是终局收完的时候）。阈值 = `sealed_hard_min_cands`。
	#   退回时**整批放行**而不是只放一个：候选集若依赖"排序中间态"，口径就会随排序实现漂。
	#   两个计数落成成员变量，供 `--sealhard` ⑤ 判据读（判据量得到才叫有牙齿）。
	if blocked.size() > 0:
		if cands.size() < maxi(sealed_hard_min_cands, 0):
			sealed_hard_fallback_last = 1
			for v in blocked:
				var s2 := _root_score(v, opp_last)
				if s2 <= -0.5e9:
					continue
				cands.append(v)
				scores.append(s2)
		else:
			sealed_hard_fallback_last = 0
	sealed_hard_blocked_last = blocked.size()

	# ---- 外部先验注入（野马）：按名次混合，量纲无关 ----
	# ★ 必须放在下面 Top-K 剪枝**之前**：剪枝本身就是按 `scores` 排序取前 K 个，
	#   所以要让网络影响"**哪些**候选能进搜索"，只能在这之前改 `scores`。
	#   放到剪枝后面就只影响内部顺序 —— 看起来接上了，实际网络对候选集毫无影响（不报错）。
	if ext_prior.size() == n and w_external_prior > 0.0 and cands.size() >= 2:
		_mix_external_prior(cands, scores)
	else:
		# ★ 探针必须**每手清零**：只在混合分支里写、不清零的话，上一手留下的 `last_mix`
		#   会让"这一手根本没注入"读起来像"注入了 m 个候选"（探针撒谎，且是静默的）。
		#   同族事故：§105「探测→静音」与 §134「探针≠派生函数」。
		ext_prior_last_mix = 0
		ext_prior_last_top1_moved = 0
		ext_prior_last_top1_rank = -1
		ext_prior_last_top1_is_net = 0
		ext_prior_last_order_diff = 0
		ext_prior_last_w = -1.0
		ext_prior_last_top1_agree = -1

	# 先验剪枝：分支因子远大于模拟预算时，全宽展开只会让每个子节点分到 1~2 次访问，
	# 统计差异完全被方差掩盖。只保留评分最高的 K 个候选，搜索才真正起作用
	var k := _effective_root_width(cands.size())
	if k < cands.size():
		var pairs: Array = []
		for i in scores.size():
			pairs.append([scores[i], i])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var kcands: Array[int] = []
		var kscores: Array[float] = []
		for i in k:
			var mi: int = pairs[i][1]
			kcands.append(cands[mi])
			kscores.append(scores[mi])
		cands = kcands
		scores = kscores

	# 剪枝后先验重新归一化：直接在全集上算出的 softmax 会因被删去的候选而失真
	var priors := _softmax_priors(scores)
	return {"cands": cands, "priors": priors}

## 仅供自检 `--jevdump` 用：装回局面并返回根层候选与先验（**不搜索**）。
##
## 调用顺序与 `choose_move` 完全一致（`_load_board` -> `_infer_opp_move` -> `_prepare_root`）。
## 少了这一步、或在调用方自己拼这几句，导出的先验就未必是这次搜索真正用的那一份，
## 而探针拿它去和外部模型做相关时**不会报错**，只会给出一个偏掉的相关系数。
func prepare_root_for_dump(board_dict: Dictionary, ko: int = -1) -> Dictionary:
	_load_board(board_dict, ko)
	return _prepare_root(_infer_opp_move())


## 把外部先验（神经网络分数）与 `_root_score` 按**名次**混合，**原地改写** `scores`。
##
## 为什么用名次而不是分数加权：两者量纲差约 4 个数量级（`_root_score` 是几万量级，
## 网络 logit 只有 −4.5~−1.6）。直接相加时网络的贡献会被完全吞掉 —— 而且**不报错**，
## 只表现成"接了个网络但强度一点没变"。名次法对量纲、温度、饱和全都免疫。
##
## `w_external_prior = 1` ⇒ 完全采用外部排序；`0` ⇒ 调用方不会进来（有守卫）。
## 混合后 `scores` 的数值域变成 [0,1]，与 `_root_score` 无关 —— 这是**故意**的：
## 下游只有 `_softmax_priors()` 读它，而 softmax 只关心相对大小。
func _mix_external_prior(cands: Array[int], scores: Array[float]) -> void:
	var m := cands.size()
	var idx_r: Array[int] = []
	var idx_e: Array[int] = []
	for i in m:
		idx_r.append(i)
		idx_e.append(i)
	# 降序排列 ⇒ 名次 0 = 最好
	idx_r.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b])
	idx_e.sort_custom(func(a: int, b: int) -> bool:
		return ext_prior[cands[a]] > ext_prior[cands[b]])
	var inv := 1.0 / float(maxi(m - 1, 1))
	var w := clampf(w_external_prior, 0.0, 1.0)
	var blended := PackedFloat32Array()
	blended.resize(m)
	# 先摆磐石的名次分
	for r in m:
		blended[idx_r[r]] = 1.0 - r * inv
	# 再按 w 混入网络名次分（注意 `blended[i]` 此刻装的是磐石名次分）
	for r in m:
		var i: int = idx_e[r]
		blended[i] = (1.0 - w) * blended[i] + w * (1.0 - r * inv)
	for i in m:
		scores[i] = blended[i]
	ext_prior_last_mix = m
	# ---- 探针：混合到底有没有改变根层首选（2026-10-23，野马接入用）----
	# 口径：`idx_r[0]` 是**混合前**磐石的首选（名次 0）。混合后重新取一次最大 ⇒
	#   两者不同就是"网络真的推翻了磐石"。同时记下新首选在原始排序里的名次，
	#   用于区分"网络把第 1 名顶掉"（rank=1，差一点）与"网络把第 9 名顶上来"（rank=9，强证据）。
	var new_top: int = 0
	for i in m:
		if scores[i] > scores[new_top]:
			new_top = i
	ext_prior_last_top1_moved = int(new_top != idx_r[0])
	var orig_rank := -1
	for r in m:
		if idx_r[r] == new_top:
			orig_rank = r
			break
	ext_prior_last_top1_rank = orig_rank
	# ---- 探针（方向无关版，2026-10-24）：见字段声明处 ①② 的说明 ----
	# `top1_is_net`：混合后的首选必须是**网络的首选**（`idx_e[0]`）。`w=1` 时由构造保证；
	#   为 0 ⇒ 写回/权重/排序口径三者之一坏了。
	# `order_diff`：混合后排序与磐石原排序逐位比较、数名次不同的点。**不看名次 0**，
	#   所以"网络与磐石首选一致但其余位置不同"照样 > 0（这正是 v2 权重的实际情况，
	#   见 2026-10-24 日志：⑥b 换进/换出 9 个，而 top1_moved=0）。
	ext_prior_last_top1_is_net = int(new_top == idx_e[0])
	ext_prior_last_top1_agree = int(idx_e[0] == idx_r[0])
	ext_prior_last_w = w
	var idx_a: Array[int] = []
	for i in m:
		idx_a.append(i)
	idx_a.sort_custom(func(a: int, b: int) -> bool: return scores[a] > scores[b])
	var odiff := 0
	for r in m:
		if idx_a[r] != idx_r[r]:
			odiff += 1
	ext_prior_last_order_diff = odiff

## 自适应根宽度。实测结论（多组对照）：**不剪枝最强**。
## 早期版本把根宽压到 8~24，想让预算集中在少数候选上；实测却大败给「全宽 + 纯先验」——
## 预算几百次模拟时，每个候选分到十几次访问的统计完全不可靠，
## MCTS 会拿噪声盖掉本来正确的先验排序。所以默认保留全部候选，
## 让先验排序主导、搜索只负责修正（先验高的手天然更可能被访问，从而被验证）。
##
## `root_width = 0`（自动）时用 `auto_root_width` 封顶。
## **这个上限是「搜索是否收敛」的关键**：实测（`--aibud`：同一局面、固定种子、单线程，
## 比较 300/560/700/2400ms 四个预算各自选出的着法）：
##   全宽 96 个候选 → 不同预算的一致率只有 13~38%，即决策被噪声主导、多给时间也没收敛；
##   限到 12 个候选  → 一致率升到 75~100%（300ms 与 2400ms 完全一致）。
## 原因很直白：96 个候选时每个候选只分到 0.4~3 次真实访问，胜率估计是纯噪声；
## 限到 12~14 个后是 15~120 次，证据才真的能判断。所以宁可窄而准，不要宽而虚。
##
## **反向验证（2026-09-13 二轮扫描，标准盘 8 局面 × 预算 150/300/420/900）**：
## 曾设想「困难档给更长的预算时，把根候选也放宽一点，让多出来的时间花在更多候选上而不是更深」。
## 实测这个设想是错的，宽度必须**钉死在 14 附近**：
##   rw=14 → 两两一致率 88~100%（8 个局面里 7 个四档全同手）＝收敛；
##   rw=28 → 50~75% ＝开始被噪声主导；
##   rw=48 → 13~50% ＝退化成掷骰子。
## 即「加宽根候选」会把问题一键还原成最初的 96 候选病。加时间不如改先验。
func _effective_root_width(cands_size: int) -> int:
	if root_width > 0:
		return mini(root_width, cands_size)
	return mini(cands_size, maxi(auto_root_width, 1))

## rollout 手数上限。
## 用「绝对手数」而不是 n 的比例：局部战斗在 150 手内基本定型，
## 若按棋盘格数放大（加强盘 n=360 时会跑到 200+ 手），大盘每次模拟会白烧两倍时间。
## 但也不能压太短 —— rollout 没下到接近终局时面积分噪声很大，棋力反而下降（实测过 96 手会掉分）
##
## ★★ 2026-10-27：**必须把 `playout_cap_factor` 一起算进来**（此前不算）。
##   理由不是性能，是**判据口径**：`_playout()` 真正用的长度 = `min(n×factor, 本函数返回值)`，
##   而 `--ailam` / `--aiterr` 打印的"rollout 上限"来自本函数 ⇒ 不同步时**探针量的是另一个长度**，
##   它算出的 σ/λ* 与生产实际执行的东西不是一回事（§133 一个量服务两个语义 / §110 参照物必须同源）。
##   把系数并到这里之后，"探针说的上限" = "rollout 真正跑的手数"，只有一处算式。
func _effective_playout_cap() -> int:
	if max_playout_moves > 0:
		return max_playout_moves
	var base := mini(n, 160)
	if playout_cap_factor > 0.0:
		base = mini(base, int(float(n) * playout_cap_factor))
	return base

## 渐进加宽上限：节点允许展开的子节点数 = clamp(ceil(k * visits^alpha), 1, min(n, widen_max))
func _widening_limit(visits: int) -> int:
	var lim := int(ceil(widen_k * pow(float(maxi(visits, 1)), widen_alpha)))
	return clampi(lim, 1, mini(n, maxi(widen_max, 1)))

## 生效线程数（>1 时并行；=1 时走原来的单线程 + 树复用路径）。
## 实测线程数与棋力并非单调正相关：每份独立搜索的迭代数太少时，方差会污染合并结果
## （8 线程并行明显弱于单线程）。所以上限收到 4，换取每份足够的迭代深度
func _effective_threads() -> int:
	var t: int = threads
	if t <= 0:
		t = mini(OS.get_processor_count(), 4)
	return clampi(t, 1, 16)

## 建/扩容 worker 池。每个 worker 是独立 AIEngine：自带棋盘缓冲与随机流，
## 线程之间不共享可变状态，因此无需加锁
func _ensure_workers(want_extra: int) -> void:
	# 防御：缓冲区尺寸与当前棋盘不符的 worker 一律丢弃（换盘/改尺寸后可能残留）
	for i in range(_workers.size() - 1, -1, -1):
		if _workers[i].n != n:
			_workers.remove_at(i)
	while _workers.size() < want_extra:
		var w := AIEngine.new()
		w.setup(adj, ai_color, int(rng.randi()))
		_workers.append(w)
	# 每次都同步参数：玩家可能刚在 TAB 面板里改过线程数/剪枝宽度等旋钮
	for w in _workers:
		w._copy_params_from(self)

## 把可调参数复制给 worker 实例，保证 worker 与主引擎同策略、只有随机流不同。
## ai_color 必须同步：self-play / 联机换色等场景会改主实例的行棋色，
## 若 worker 停留在旧颜色，回传的 wins 视角就会整体反转
func _copy_params_from(src: AIEngine) -> void:
	ai_color = src.ai_color
	time_budget_ms = src.time_budget_ms
	max_playouts = src.max_playouts
	threads = src.threads
	root_width = src.root_width
	auto_root_width = src.auto_root_width
	max_playout_moves = src.max_playout_moves
	max_tree_depth = src.max_tree_depth
	widen_k = src.widen_k
	widen_alpha = src.widen_alpha
	widen_max = src.widen_max
	dead_penalty = src.dead_penalty
	dead_fill_gate = src.dead_fill_gate
	# ★★ 贴目（2026-10-02）：**必须同步**，否则多线程下每个 worker 各按 0 目评估 ——
	#   分出来的候选带不同贴目噪声，合并选点（`_pick_merged`）就等于在混两种策略。
	#   这与 `ai_color` 必须同步是同一条理由：worker 与主实例策略不同，结论必错。
	komi = src.komi
	c_puct = src.c_puct
	c_uct = src.c_uct
	rave_equiv = src.rave_equiv
	prior_visits = src.prior_visits
	prior_visits_inner = src.prior_visits_inner
	score_soft = src.score_soft
	influence_enabled = src.influence_enabled
	influence_max_d = src.influence_max_d
	eval_mix_lambda = src.eval_mix_lambda
	# ★★ 提子项（2026-10-27）：**必须同步**，理由与 `komi` 完全相同 ——
	#   否则多线程 worker 各自按「不含提子」的口径评估，合并选点等于混两种策略。
	count_prisoners = src.count_prisoners
	# 同理必须同步：不同步 ⇒ 每个 worker 按另一套归属口径评估，合并选点 = 混两种策略
	infl_dead_zone = src.infl_dead_zone
	infl_src_min_libs = src.infl_src_min_libs
	w_cap_bonus = src.w_cap_bonus
	w_cap_each = src.w_cap_each
	w_save_each = src.w_save_each
	w_self_atari = src.w_self_atari
	w_threat_each = src.w_threat_each
	w_lib = src.w_lib
	w_conn = src.w_conn
	w_local = src.w_local
	w_center = src.w_center
	w_weak_each = src.w_weak_each
	w_eye_make = src.w_eye_make
	w_tighten = src.w_tighten
	w_fill_own_eye = src.w_fill_own_eye
	w_kill_point = src.w_kill_point
	ld_enabled = src.ld_enabled
	ladder_escape_check = src.ladder_escape_check
	tighten_check = src.tighten_check
	fill_own_eye_check = src.fill_own_eye_check
	value_blend = src.value_blend
	# ★ 2026-10-08：空区硬过滤的四个参数。**防御性同步** —— 今天 worker 拿到的是**已备好的根**
	#   （`_parallel_search()` 把 `cands`/`priors` 直接传进去，worker 不调 `_prepare_root()`），
	#   所以这四项其实读不到；但一旦将来有人让 worker 自己备根，没有这一句就会出现
	#   「主实例拦了、worker 没拦」= 同一次搜索里两套策略（komi 那次就是这个形状，
	#   见 `komi` 上方那条注释）。同步是零代价的。
	use_sealed_hard_filter = src.use_sealed_hard_filter
	sealed_hard_share = src.sealed_hard_share
	sealed_hard_max_size = src.sealed_hard_max_size
	sealed_hard_min_cands = src.sealed_hard_min_cands
	v_own_atari_st = src.v_own_atari_st
	v_own_atari_grp = src.v_own_atari_grp
	v_opp_atari_st = src.v_opp_atari_st
	v_opp_atari_grp = src.v_opp_atari_grp
	v_own_2lib_grp = src.v_own_2lib_grp
	v_opp_2lib_grp = src.v_opp_2lib_grp
	v_stone_diff = src.v_stone_diff
	v_bias = src.v_bias
	w_ladder_run = src.w_ladder_run
	ladder_node_budget = src.ladder_node_budget
	ld_max_libs = src.ld_max_libs
	ld_cap_points = src.ld_cap_points
	ld_node_budget = src.ld_node_budget
	ld_probe_libs = src.ld_probe_libs
	prior_temp = src.prior_temp
	prior_pick_weight = src.prior_pick_weight
	evidence_k = src.evidence_k
	p_capture = src.p_capture
	p_eye = src.p_eye
	p_save = src.p_save
	p_no_self_atari = src.p_no_self_atari
	narrow_self_atari_guard = src.narrow_self_atari_guard
	playout_cap_factor = src.playout_cap_factor
	full_scan_every = src.full_scan_every
	wq_own = src.wq_own
	wq_opp = src.wq_opp
	wq_emp = src.wq_emp
	wq_center = src.wq_center
	wq_local = src.wq_local
	# KataGo 借鉴三项：worker 与主引擎必须同策略
	dynamic_center_enabled = src.dynamic_center_enabled
	dynamic_center_zero_weight = src.dynamic_center_zero_weight
	dynamic_center_scale = src.dynamic_center_scale
	pick_lcb_stdevs = src.pick_lcb_stdevs
	obvious_early_stop = src.obvious_early_stop
	obvious_min_visits = src.obvious_min_visits
	obvious_share = src.obvious_share
	obvious_lead = src.obvious_lead
	# 锚点是**状态**不是参数：本手搜索前主引擎会把最新锚点同步过来（见 _parallel_search）
	_dc_center = src._dc_center
	_dc_has = src._dc_has
	_dc_collect = false          # worker 不收集（收了也没人读），主引擎自己收集

# ============================================================================
#  并行搜索（Root Parallelization）
# ============================================================================
## 在自己的棋盘副本上建同构根，跑到 deadline 为止，返回根子节点统计供主线程合并。
## p: {b(PackedByteArray), ko, turn, cap, cands, priors, deadline}
func _search_budget(p: Dictionary) -> Dictionary:
	_b = (p["b"] as PackedByteArray).duplicate()
	_ko = int(p["ko"])
	_turn = int(p["turn"])
	_eff_cap = int(p["cap"])
	_ply = 0
	_capsp = 0
	_pris_b = 0
	_pris_w = 0
	_logn = 0
	_stamp_reset()
	_aw.fill(0.0)
	_an.fill(0.0)

	var cands: Array[int] = p["cands"]
	var priors: Array[float] = p["priors"]
	var root := MNode.new()
	root.off = rng.randi() % n
	for k in cands.size():
		var cn := MNode.new()
		cn.move = cands[k]
		cn.player = ai_color
		cn.prior = priors[k]
		cn.off = rng.randi() % n
		cn.visits = int(maxf(prior_visits, 1.0))
		cn.wins = cn.prior * float(cn.visits)
		root.children.append(cn)
	root.nxt = n          # 根已一次性展开全部（剪枝后的）候选

	var deadline: int = int(p["deadline"])
	var iters := 0
	var chk := 0
	while iters < max_playouts:
		root.visits += 1
		_iterate(root)
		iters += 1
		chk += 1
		if chk >= 12:
			chk = 0
			if Time.get_ticks_msec() >= deadline:
				break
			# 显然手早停：根层已经一边倒时不再烧满预算（各引擎独立判定，
			# 真显然手会全体早停 → 并行路径同样省时间；分歧手则照常跑满）
			if iters >= obvious_min_visits and _obvious_root(root):
				break
	while _ply > 0:
		_undo()

	var vs := PackedFloat32Array()
	var ws := PackedFloat32Array()
	vs.resize(cands.size())
	ws.resize(cands.size())
	for k in cands.size():
		vs[k] = float(root.children[k].visits)
		ws[k] = root.children[k].wins
	return {
		"visits": vs, "wins": ws, "iters": iters,
		"aw": _aw.duplicate(), "an": _an.duplicate(),
	}

## worker 线程入口（运行在 worker 实例上，故 self 就是那个独立引擎）
func _thread_entry(p: Dictionary) -> Dictionary:
	return _search_budget(p)

## 并行搜索：主线程自己跑一份，其余交后台线程；汇总根子节点访问数与 RAVE 统计
func _parallel_search(cands: Array[int], priors: Array[float], deadline: int, nthreads: int) -> Dictionary:
	_ensure_workers(maxi(nthreads - 1, 0))
	var vs := PackedFloat32Array()
	var ws := PackedFloat32Array()
	vs.resize(cands.size())
	ws.resize(cands.size())
	var aw_sum := PackedFloat32Array()
	var an_sum := PackedFloat32Array()
	aw_sum.resize(n)
	an_sum.resize(n)

	# 顺序很关键：先起后台线程，主线程自己再跑一份，两者共享同一个绝对 deadline
	# （若先同步跑主线程那份，起线程时 deadline 已过，worker 会立刻空手退出）
	var ths: Array[Thread] = []
	for i in _workers.size():
		var snap: PackedByteArray = _b.duplicate()
		var p: Dictionary = {
			"b": snap, "ko": _ko, "turn": _turn, "cap": _eff_cap,
			"cands": cands, "priors": priors, "deadline": deadline,
		}
		var th := Thread.new()
		ths.append(th)
		th.start(_workers[i]._thread_entry.bind(p), Thread.PRIORITY_NORMAL)

	var local := _search_budget({
		"b": _b, "ko": _ko, "turn": _turn, "cap": _eff_cap,
		"cands": cands, "priors": priors, "deadline": deadline,
	})
	var total_iters: int = int(local["iters"])
	_accumulate_stats(local, vs, ws, aw_sum, an_sum)

	for i in ths.size():
		var r: Dictionary = ths[i].wait_to_finish()
		total_iters += int(r["iters"])
		_accumulate_stats(r, vs, ws, aw_sum, an_sum)

	_aw = aw_sum
	_an = an_sum
	_tree = null            # 并行模式下不复用树（各 worker 树独立且已丢弃）
	return {"visits": vs, "wins": ws, "iters": total_iters}

## 把一份结果累加到总计上
func _accumulate_stats(r: Dictionary, vs: PackedFloat32Array, ws: PackedFloat32Array,
		aw_sum: PackedFloat32Array, an_sum: PackedFloat32Array) -> void:
	var rvs: PackedFloat32Array = r["visits"]
	var rws: PackedFloat32Array = r["wins"]
	for k in vs.size():
		vs[k] += rvs[k]
		ws[k] += rws[k]
	var raw: PackedFloat32Array = r["aw"]
	var ran: PackedFloat32Array = r["an"]
	for m in n:
		aw_sum[m] += raw[m]
		an_sum[m] += ran[m]

## 从合并统计里挑最终着法：**先验打底，证据按样本量收缩**。
##
## 旧规则是 `q + w × 先验`，其中 q 是「每个引擎 12 次先验虚拟访问 + 少量真实访问」的混合胜率。
## 根层**真实统计**：扣掉各引擎注入的先验伪访问 / 伪 wins。
##
## ★ 这是 `_pick_merged()`（选点）与 `last_root_q`（训练标签）的**唯一真源**。
##   两处各写一份会漂移成"选点用的 Q 和标签里的 Q 不是同一个数"，而这种错
##   **不报任何异常**：模型照样训、报告照样好看，只是目标与引擎行为悄悄分了家
##   （§8 一处写一处读 / §136 出题条件与判分口径必须同源）。
##
## 注入量：每个引擎实例（主线程 + 各 worker）都给每个根子节点注入 `prior_visits` 次
## 虚拟访问，对应伪 wins = prior × prior_visits ⇒ 总注入是 `envs × prior_visits`。
## 返回 {"v": 真实访问（≥0）, "q": 真实胜率（[0,1]；**未访问 = −1**）}
func _root_real_stats(cands: Array[int], priors: Array[float], agg: Dictionary,
		envs: int) -> Dictionary:
	var vs: PackedFloat32Array = agg["visits"]
	var ws: PackedFloat32Array = agg["wins"]
	var vinj: float = float(maxi(envs, 1)) * prior_visits
	var ov := PackedFloat32Array()
	var oq := PackedFloat32Array()
	ov.resize(cands.size())
	oq.resize(cands.size())
	for k in cands.size():
		var vr: float = maxf(vs[k] - vinj, 0.0)
		ov[k] = vr
		if vr <= 0.0:
			# 未访问 ⇒ −1。**不许写 0**：0 是"胜率 0%"的合法值，两者混起来训练端会把
			# "没搜过"读成"必输"，completed-Q 补全就成了反的。
			oq[k] = -1.0
			continue
		var wr: float = maxf(ws[k] - vinj * priors[k], 0.0)
		oq[k] = clampf(wr / vr, 0.0, 1.0)
	return {"v": ov, "q": oq, "inj": vinj}


## 真实访问只有个位数时，**多赢一次就能把 q 抬高 1/13**，足以盖过先验之间的差距 ——
## 于是根节点的决定被噪声主导。实测（`--aibud`：同一局面、固定随机种子、单线程）：
## 把预算从 300ms 换成 2400ms，选出的着法在**几乎全部局面**上都变了（合理区间本应高度一致），
## 也就是说多给的思考时间并没有换来收敛 —— 那几秒钟基本是在掷骰子。
##
## 改为标准的「样本量收缩」（等价于给胜率加一个强度 `evidence_k` 的 Beta 先验）：
##     score = 先验 + w × (真实胜率 - 先验) × V / (V + evidence_k)
## 其中 V = 真实访问数（已扣掉各引擎初始注入的先验虚拟访问）。
## V 很小 → 系数≈0，直接按先验走；V 攒够 → 证据才逐步说话。无门槛跳变，不会出现
## 「刚好够 V 的手突然翻盘」这种不连续。
func _pick_merged(cands: Array[int], priors: Array[float], agg: Dictionary, envs: int) -> int:
	var rs: Dictionary = _root_real_stats(cands, priors, agg, envs)
	var rv: PackedFloat32Array = rs["v"]
	var rq: PackedFloat32Array = rs["q"]
	var best_k := 0
	var best_sc := -INF
	for k in cands.size():
		var p: float = priors[k]
		var v_real: float = rv[k]
		var sc: float = p
		if v_real > 0.0:
			var q_real: float = rq[k]
			# LCB（置信下界）：真实胜率减 stdevs 倍标准误。访问数越少、运气成分越大，
			# 惩罚越重 → 低访问数的「幸运高胜率」抢不走选点（KataGo lcbStdevs 思想）。
			var q_use := q_real
			if pick_lcb_stdevs > 0.0 and v_real > 1.0:
				q_use = clampf(q_real - pick_lcb_stdevs * sqrt(q_real * (1.0 - q_real) / v_real), 0.0, 1.0)
			sc = p + prior_pick_weight * (q_use - p) * (v_real / (v_real + maxf(evidence_k, 0.0)))
		if sc > best_sc:
			best_sc = sc
			best_k = k
	return cands[best_k]


## 动态分中心效用探针（--dcwtest 自检专用，2026-10-05）。
## 给定绝对分 sc 与锚点，返回 `0.5+0.5·tanh(rel/score_soft)`，rel 按
## `dynamic_center_zero_weight` 混合（0=纯相对分、1=纯绝对分）。
## ⚠️ **不要在生产路径调它** —— 它绕过了 `_dc_collect` 收集，且用调用方给的 sc
##   而非引擎自己的 `_area_score()`；自检专用是为了把「权重公式」这一件事
##   从 MCTS 随机性里剥出来单独验（铁律：判据量的东西 = 刀改的东西）。
func probe_dc_utility(sc: float, center: float, zero_weight: float,
		has_center: bool = true) -> float:
	var zw: float = clampf(zero_weight, 0.0, 1.0)
	if not dynamic_center_enabled or not has_center:
		return 0.5 + 0.5 * tanh(sc / maxf(score_soft, 0.5))
	var cap: float = sqrt(float(n)) * dynamic_center_scale
	var rel: float = clampf(sc - (1.0 - zw) * center, -cap, cap)
	return 0.5 + 0.5 * tanh(rel / maxf(score_soft, 0.5))


## 结算本手搜索收集到的叶子分均值，作为下一手搜索的动态分中心锚点。
## 一手只结算一次（choose_move 的各返回路径末尾调用）；没有样本时保持旧锚点。
func _dc_finalize() -> void:
	if _dc_n > 0.0:
		_dc_center = _dc_sum / _dc_n
		_dc_has = true
		# σ = sqrt(E[x²] − E[x]²)；用 maxf 夹掉浮点负零（同分叶子多时 0 附近会 -1e-18）
		_dc_std = sqrt(maxf(_dc_sq / _dc_n - _dc_center * _dc_center, 0.0))
		_dc_std_sum += _dc_std
		_dc_std_cnt += 1.0
	_dc_collect = false
	_dc_sum = 0.0
	_dc_sq = 0.0
	_dc_n = 0.0


## 根层候选的**访问分布**探针（`--capftest` 判据④a 用，2026-10-05）。
##
## 【为什么必须有它】`--capftest` 第一次跑出「换随机种子也 100% 一致」，
## 而同一份代码在 `--aitune` 里明明会因种子不同走出不同棋谱。两个结论都指向同一个问题：
## **在这些局面上，搜索统计到底有没有话语权？**
## `_pick_merged()` 是「先验 + 证据收缩」，非冠军候选若 `v_real ≈ 0` 就**恒按先验打分**，
## 此时选点与 RNG 无关是**构造上的必然**，不是「引擎对随机不敏感」——
## 这两个诊断指向完全相反的处置（引擎 bug vs 局面太浅/预算太小），不能靠猜。
##
## 返回：{cands, visits, wins, priors, playouts}
##   `visits[k]` 是**含**先验虚拟注入的原始访问数（`_pick_merged` 内部会再扣 `envs*prior_visits`）。
## ⚠️ 本探针只读、不改状态，但它**必须在 `choose_move` 之前**装载棋盘并自己跑一遍搜索，
##   否则拿不到那一次的统计；调用方负责保证种子/线程/预算与被测调用一致（铁律 13：
##   判据量的东西 = 刀改的东西）。
func probe_root_visits(board_dict: Dictionary, ko: int, ai: int,
		playouts: int) -> Dictionary:
	_load_board(board_dict, ko)
	ai_color = ai
	_eff_cap = _effective_playout_cap()
	var opp_last := _infer_opp_move()
	var info: Dictionary = _prepare_root(opp_last)
	var cands: Array[int] = info["cands"]
	var priors: Array[float] = info["priors"]
	if cands.size() <= 1:
		# ⚠️ 早退分支也必须给全所有键：调用方按名取值，缺一个就是运行时崩。
		return {"cands": cands.size(), "visits": PackedInt32Array(), "wins": PackedFloat32Array(),
			"priors": priors, "playouts": 0, "spread": 0.0, "top2": 0.0, "zero_frac": 1.0,
			"prior_gap": 0.0, "se1": 0.0, "fix_cap": 0.0, "v_top1": 0.0, "v_top2": 0.0}
	var root: MNode = _reuse_tree(opp_last)
	if root == null:
		root = MNode.new()
		root.off = rng.randi() % n
		for k in cands.size():
			var cn := MNode.new()
			cn.move = cands[k]
			cn.player = ai_color
			cn.prior = priors[k]
			cn.off = rng.randi() % n
			cn.visits = int(maxf(prior_visits, 1.0))
			cn.wins = cn.prior * float(cn.visits)
			root.children.append(cn)
		root.nxt = n
	var iters := 0
	while iters < playouts:
		root.visits += 1
		_iterate(root)
		iters += 1
	var vs := PackedInt32Array()
	var wss := PackedFloat32Array()
	vs.resize(cands.size())
	wss.resize(cands.size())
	var vmax := 0
	var vmin := 1 << 30
	var zero := 0
	for k in cands.size():
		vs[k] = root.children[k].visits
		wss[k] = root.children[k].wins
		vmax = maxi(vmax, root.children[k].visits)
		vmin = mini(vmin, root.children[k].visits)
		if root.children[k].visits - int(prior_visits) <= 0:
			zero += 1
	# top2 真实访问份额：`_pick_merged` 里非冠军候选若无真实访问就恒按先验打分，
	# 所以「top2 占了多少」直接决定证据有没有话语权。
	var rv: Array[int] = []
	for k in cands.size():
		rv.append(root.children[k].visits - int(prior_visits))
	rv.sort_custom(func(a: int, b: int) -> bool: return a > b)
	var top2 := 0.0
	if iters > 0:
		top2 = float(rv[0] + (rv[1] if rv.size() > 1 else 0)) / float(iters)
	# ★★ 新增（2026-10-05）：**证据强度**与**先验差距**这两个量各自多大？
	# 「换种子也 100% 一致」有两种完全不同的成因，处置相反：
	#   (a) 证据太弱（top1 真实访问少 ⇒ 标准误大，但同时修正量也小）
	#   (b) 先验差距太大（`_softmax_priors` 把冠军的先验拉得极高，
	#       而 `_pick_merged` 的修正被 `prior_pick_weight × V/(V+evidence_k)` 压住）
	# 只有同时打印 `top1_prior - top2_prior`（先验差距）与 `q` 的标准误（证据噪声），
	# 才分得清是哪一种。光看一致率 100% 一律读不出来。
	var vinj1 := float(maxf(prior_visits, 1.0))
	var bi := 0
	for k in cands.size():
		if root.children[k].visits > root.children[bi].visits:
			bi = k
	var vr1 := maxf(float(root.children[bi].visits) - vinj1, 0.0)
	# ⚠️ 2026-10-05 修 bug：`bj` 原先初始化成 `bi`（全局访问最多者），
	#   而 `visits[k] > visits[bj]` 对任何 k 都不可能成立 ⇒ bj 恒 = bi
	#   ⇒ prior_gap 恒为 0 ⇒ ④a 打出「先验差距 0.0000」并误判成因。
	#   必须在 `k != bi` 的集合里**独立**求最大（哨兵 -1 起）。
	var bj := -1
	for k in cands.size():
		if k == bi:
			continue
		if bj < 0 or root.children[k].visits > root.children[bj].visits:
			bj = k
	var vr2 := maxf(float(root.children[bj].visits) - vinj1, 0.0)
	# 先验差距（softmax 后的概率差）
	var prior_gap := 0.0
	if bj >= 0 and bj != bi:
		prior_gap = absf(float(priors[bi]) - float(priors[bj]))
	# top1 胜率估计的标准误：sqrt(q(1-q)/V) —— 「换种子能推动 q 多大」
	var se1 := 0.0
	if vr1 > 1.0:
		var q1 := clampf((maxf(float(root.children[bi].wins) - vinj1 * float(priors[bi]), 0.0)) / vr1, 0.0, 1.0)
		se1 = sqrt(q1 * (1.0 - q1) / vr1)
	# `_pick_merged` 对 top1 施加的修正量上限：prior_pick_weight × V/(V+evidence_k) × |q-p|
	var fix_cap := 0.0
	if vr1 > 0.0:
		fix_cap = prior_pick_weight * (vr1 / (vr1 + maxf(evidence_k, 0.0)))
	return {"cands": cands.size(), "visits": vs, "wins": wss, "priors": priors,
		"playouts": iters, "spread": float(vmax - vmin),
		"top2": top2, "zero_frac": float(zero) / float(cands.size()),
		"prior_gap": prior_gap, "se1": se1, "fix_cap": fix_cap,
		"v_top1": vr1, "v_top2": vr2}


## 根层「显然手」判定（KataGo obviousMovesTimeFactor 思想的简化版）：
## top1 的真实访问数同时满足 ①绝对量 ≥ obvious_min_visits
## ②占前二名之和的比 ≥ obvious_share ③对 top2 的领先 ≥ obvious_lead（相对 top1）。
## 三个条件都要 —— 只看占比的话，开局少数几个候选时 80 次访问就能凑出高占比。
# ============================================================================
#  全局局势分析（只读）
# ============================================================================
##★ 本层**绝不改棋盘或内部状态**。`_group_status()` 会写 `_ld_n`（并用 `_ld_cache`），
##   所以每次调用后必须 `_ld_n = 0` 复位 —— 否则后续搜索会拿到上一个形的模型，
##   让 `_eye_vital_bonus()` 白送 `w_eye_make`（2026-09-21 已踩，14~16 分足够翻转选点）。
##   判据：`analyze_t` 0/ai 侧只读性、`--areatest` 第⑤段。

## 一块棋的分类结果（返回 Dictionary 的字段名 = 契约，别改）
##   stones / libs      该块的子数与气数
##   region             眼位空间点数（0 = 没建出模型）
##   status             _group_status 原始三态：0 死 / 1 未定形 / 2 活
##   tag                分类标签：LIVE / UNSETTLED / DEAD / SEALED_TERRITORY
## ★ `cnt` 是 `_group()` 返回的**成员计数**，不是顶点下标 —— 两者语义完全不同。
##   第一版把 `cnt` 直接当顶点下标传给 `_group_stones` / `_turn_of`
##   （它们内部做 `_as[cnt]`）⇒ **量纲错配**⇒ 实测「白块 5 子 vs 盘面 10 子」。
##⇒ 结构修法：本函数开头先取出**代表点** `rep`（`_group` 留在 `_gbuf[0]` 的那个），
##   之后凡是「要顶点」的函数一律传 `rep`，「要计数」的才用 `cnt`。
func _classify_block(cnt: int) -> Dictionary:
	var rep: int = _gbuf[0]                # `_group(start)` 的第一个成员 = 代表点
	var color := int(_b[rep])
	var libs := _libs(cnt, -1)
	var st := _group_status(cnt, libs)
	# ★ 必须取完所有字段再复位 `_ld_n`：`region` 来自 `_ld_n`，复位后就没了。
	var region := _ld_n
	_ld_n = 0# 铁律 1：只读 —— 立刻作废本次模型
	var tag := "UNSETTLED"
	if libs == 0:
		tag = "DEAD"                      # 无气 = 已被提掉 / 本就死
	elif st == 2:
		tag = "LIVE"                      # 两方都杀不掉
	elif st == 0:
		tag = "DEAD"# 攻方先手能杀，且防守方先手也活不了
	return {
		"rep": rep, "color": color, "stones": cnt,
		"libs": libs, "region": region, "status": st, "tag": tag,
	}

## ★ 这两个函数已删（2026-10-06）。它们把 `_group()` 的**成员计数** `cnt`
## 当成**顶点下标**用（`_as[cnt]`）⇒ 量纲错配 ⇒ 块大小算错（实测 5 vs 10）。
## 现在 `_classify_block()` 直接：
##   · `stones = cnt`（成员计数本身就是子数）
##   · `color  = _b[rep]`（代表点的颜色）
##   · `rep` 存进返回字典，供判据按坐标核账（判据⑧ 用）。

## 全盘分析（**外部入口**）。返回的Dictionary 就是判据与音乐层的唯一接口。
##   win_black / win_white : 各自的胜率 ∈ 0..1（两者之和 = 1）
##   lead                  : win_black - win_white，★ **正 = 黑领先 ≠ "我方领先"**（见下面的视角警告）
##   black_points / _white : 各自的**无界**目数（可以是负数）—— 判据要量单调性就量它（铁律 14）
##   blocks_black / _white : 逐块清单（`_classify_block` 的字段）
##   own_* / their_*       : **对 `ai_color` 而言**的「己方 / 对方」三分类
##                           （已活 LIVE / 可做活 UNSETTLED / 已死 DEAD 的子数与块数，两边都给）
##   sealed_empty          : 「已被对方围死、攻不进去」的空点数（AI 不该往这儿投子）
##   advice                : 行动指令字符串（中文，直接给 UI/音乐/日志）
##
## ⚠️⚠️ **视角警告（2026-10-07 实测踩到）**：`lead` 与 `black_points/white_points` 是
##   **绝对颜色视角（黑/白）**，而 `own_* / their_*` 是 **`ai_color` 相对视角**。
##   两者**混用就会静默反向**：`game.gd` 曾把 `lead` 当"我方领先"用（注释也这么写），
##   而本工程 `AI_COLOR = WHITE` ⇒ AI 真落后时 `-lead > 0` 被算成"领先"
##   ⇒ 危急度恰好在最该涨的时候恒为 0。
##   ⇒ 规矩：**凡带方向的量，在消费端必须自己按颜色显式分两支算出来并写进名字里**
##     （见 `game.gd` 的 `an_player_diff` / `an_ai_diff`），**不许共用一个 `sign` 乘上去**。
func analyze_board(board_dict: Dictionary = {}, ko: int = -1) -> Dictionary:
	# ★ 必须自己装载棋盘： /  是引擎的内部状态，只有跑过 
	#   或  之后才有值。外部直接调 时它们是空的
	#   ⇒ 逐块循环零次迭代 ⇒ 返回全空（实测白块 0 / 黑块 0 / win_rate 0）。
	#    也有同样要求，但调用方记得传 —— 显式参数比记得先装载可靠。
	if not board_dict.is_empty():
		_load_board(board_dict, ko)
	var blocks_black: Array = []
	var blocks_white: Array = []
	var sealed_empty := 0
	var sealed_of_black := 0
	# ★★ 2026-10-08 修：去重键必须是**块身份**，绝不能是 `_group()` 的返回值。
	#   `_group()` 返回的是**成员计数** `cnt`；原写法 `if seen.has(g): continue` 于是变成
	#   「**按块大小**去重」：尺寸相同的两块棋被当成同一块，**第二块起整体丢弃**。
	#   实测（`--anlzmis`，19×19 / 120 手档）：独立枚举 16 块·360 子 vs 清单 13 块·313 子
	#   ⇒ **丢 3 块、丢 47 子**。最小复现（`--analyzetest` ⑨）：白 3/3/1/1 四块 → 只剩 2 块 4 子。
	#   全部症状都是**静默**的：胜率 / 三分类 / `advice` / 音乐 `an_*` 只是数值偏，
	#   而 ②③ 两个机制靠「在 blocks_* 里找到那一块」查表 ⇒ 直接恒不触发。
	#   新实现用「点 → 已登记」字典当访问标记；块成员全部登记，回头再遇到即跳过。
	var done := {}
	# ★ `tag_of`（点 → tag）与 `blocks_*` 同一次扫描里建出来，供 ②③ **按子查表**用。
	#   之前是「拿一个值去 blocks_* 里按 `rep` 找块」—— ①找错键（②的量纲错配）
	#   ②只比代表点（③的漏判）都出自这个模式。改成按子查表后，这类 bug 没有立足点。
	var tag_of := {}
	var nblk := 0
	var truncated := false
	# —— 逐块分类 ——
	for v in n:
		if _b[v] == EMPTY or done.has(v):
			continue
		if nblk >= analyze_max_blocks:
			truncated = true       # 防御：极端盘型下别把循环跑飞（显式标记，不静默截断）
			break
		var g := _group(v)
		var rep_pt: int = int(_gbuf[0])        # 本次 BFS 起点 = 该块里**点号最小**的子
		# 先把成员抄出来：下面还要用 `_gbuf` 之外的调用，抄一份才安全
		var members: Array[int] = []
		for i in g:
			members.append(int(_gbuf[i]))
		var b := _classify_block(g)
		if int(b["region"]) <= 0 and int(b["libs"]) == 0:
			# 无气块：盘上却还有子（`_libs` 口径如此）⇒ 按死子记，**不重复计目**
			b["tag"] = "DEAD"
		var tg := String(b["tag"])
		for m: int in members:
			done[m] = true
			tag_of[m] = tg
		nblk += 1
		# ★ 用返回里的 `color`（代表点颜色），不再调那个被删掉的错位函数。
		#   `rep_pt` 与 `b["rep"]` 同源（都是 `_gbuf[0]`），此处不重复写。
		if int(b["color"]) == BLACK:
			blocks_black.append(b)
		else:
			blocks_white.append(b)
	# —— 已被围死、攻不进去的空点 ——
	#   判据：它的**整个空区**同色包围（`_own_territory_only` 的逆用）+ 对方在该区
	#   已有活块。逐点扫描即可，n=120 足够快，且不依赖任何模型。
	for v in n:
		if _b[v] != EMPTY:
			continue
		if _sealed_by_opponent(v):
			sealed_empty += 1
			if _sealed_color(v) == BLACK:
				sealed_of_black += 1

	var w := _decide_win_rate(blocks_black, blocks_white, sealed_of_black)
	var mine: Array = blocks_white if ai_color == WHITE else blocks_black
	var theirs: Array = blocks_black if ai_color == WHITE else blocks_white
	var own_live := _sum_tag(mine, "LIVE")
	var own_unsettled := _sum_tag(mine, "UNSETTLED")
	var own_dead := _sum_tag(mine, "DEAD")
	var their_dead := _sum_tag(theirs, "DEAD")
	# ★ 2026-10-07：**对方**的「已活 / 可做活」也一并算出来。
	#   为什么必须两边都给：消费端（音乐层）要分别为**玩家**与**AI**各算一次「濒危度」，
	#   而濒危度 = 死块 + 无未定形块 + 落后 + 对方无死子。只给 `own_*` 的话，
	#   玩家那一侧就只能拿"死子数"凑一个**形式不同**的公式 ⇒ 两边的判据不可比，
	#   而"两边公式不一样"这种事在听感上完全看不出来。
	var their_live := _sum_tag(theirs, "LIVE")
	var their_unsettled := _sum_tag(theirs, "UNSETTLED")
	var lead := float(w["win_black"]) - float(w["win_white"])

	return {
		"win_black": w["win_black"], "win_white": w["win_white"],
		# ★ 原始未归一化目数也必须透出：`win_rate` 有界 ∈[0,1]，
		#   严格单调判在它上面不可满足（铁律 14）⇒ 判据要量就得量**无界**的那个量。
		"black_points": w["black_points"], "white_points": w["white_points"],
		"area": w["area"],
		"lead": lead, "komi": komi,
		"blocks_black": blocks_black, "blocks_white": blocks_white,
		"own_live": own_live["stones"], "own_unsettled": own_unsettled["stones"],
		"own_dead": own_dead["stones"],
		"own_live_blocks": own_live["count"], "own_unsettled_blocks": own_unsettled["count"],
		"own_dead_blocks": own_dead["count"], "their_dead_stones": their_dead["stones"],
		# ★ 对方（= 非 `ai_color` 的那一方）的同口径三分类。`own_*` 与 `their_*` 合起来
		#   才够消费端**两边各算一份**，且两边用的是同一个公式。
		"their_live": their_live["stones"], "their_unsettled": their_unsettled["stones"],
		"their_live_blocks": their_live["count"], "their_unsettled_blocks": their_unsettled["count"],
		"their_dead_blocks": their_dead["count"],
		"sealed_empty": sealed_empty,
		# ★ `tag_of`：点 → tag（每个子一份）。②③ 两个机制按**子**查表用，
		#   避免「拿猜测的值去 blocks_* 里按 rep 找块」（历史上出过两次静默错配）。
		#   `truncated`：块数撞到 `analyze_max_blocks` 而上限截断（此时清单不完整）。
		"tag_of": tag_of, "truncated": truncated,
		"advice": _advise(lead, own_live, own_unsettled, own_dead, their_dead, sealed_empty),
	}

## 空点 v 是否「已被对方围死、攻不进去」：整个空区只被一种颜色包围，且不是自己。
func _sealed_by_opponent(v: int) -> bool:
	return _sealed_color(v) >= 0 and _sealed_color(v) != ai_color

## 返回包围 v 所在整个空区的颜色（BLACK/WHITE）；若该区触及两色或触边 ⇒ -1（不算围死）。
func _sealed_color(v: int) -> int:
	var col := -1
	# ★ 用专用标记 `_ast` / 独立计数 `_asid`，**不复用 `_gst` / `_gid`**：
	#   那两个是 `_group()` 的 BFS 资源，抢了会把串截断（判据⑧ 实测漏块）。
	_asid += 1
	var sid := _asid
	_ast[v] = sid
	_gbuf2[0] = v
	var cnt := 1
	var qi := 0
	while qi < cnt:
		var cur := _gbuf2[qi]
		qi += 1
		var k := _as[cur]
		var ke := _as[cur + 1]
		while k < ke:
			var nb := _af[k]
			k += 1
			var cc := _b[nb]
			if cc == EMPTY:
				if _ast[nb] != sid:
					_ast[nb] = sid
					_gbuf2[cnt] = nb
					cnt += 1
			elif int(cc) != col:
				if col < 0:
					col = int(cc)
				elif col != int(cc):
					return -1# 触两色 ⇒ 开放的空区
	#★ `col < 0` = 这个空区**一个子都没碰到** ⇒ 开阔地带，不算任何人的地盘。
	#   缺这一条时（第一版）：19×19 空盘上**任何**空区都「只被一种颜色围」
	#   ⇒ 实测 325 个空点里 321 个被判「被围死」（98.8%）
	#   ⇒ `w_sealed_territory=-6` 变成全局落子惩罚，把救活奖励完全盖掉。
	#   ⚠️ 2026-10-08 注释纠偏：把 98.8%→0.6% 归功于「触边判 -2」是**错的** ——
	#   真正生效的是这一句。下面那个循环**不可能**返回 -2：第一段 while 已经把
	#   区域内每个点的全部非空邻居都查过（混合色在那里就 `return -1` 了），
	#   所以第二段再查一遍时，非空邻居必然都等于 `col`。保留它只为让「边界全是 col」
	#   这一条读起来显式；**不要**在别处依赖 -2（不可达）。
	if col < 0:
		return -1                      # 一个子都没触到：开阔地带
	for p in _gbuf2range(cnt):
		var k := _as[p]
		var ke := _as[p + 1]
		while k < ke:
			var q := _af[k]
			k += 1
			if _b[q] == EMPTY:
				continue
			# 这个方向上越过所有子就到了盘外 ⇒ 该空区开口
			#（简化：只要空区里任一格与「非对方子」相邻就算未完全封闭）
			if int(_b[q]) != col:
				return -2
	return col

## 遍历 `_gbuf2[0..cnt)`。抽出来是为了让上面的循环读起来清楚（不直接暴露缓冲下标）。
func _gbuf2range(cnt: int) -> Array[int]:
	var out: Array[int] = []
	for q in cnt:
		out.append(int(_gbuf2[q]))
	return out

## 净胜率：**活子目 − 死子目** 为核心，地盘用 _area_score 兜底。
## score_true_live 开着时，死子**不扣分**（真负分：死子终将被提，己方拿不到也不亏）
##   —— 这一条正是「AI 落后时不去救自己死块」的解药：
##   旧口径下死子照样占面积，救它是净亏；新口径下救活它才不亏。
func _decide_win_rate(bb: Array, bw: Array, sealed_black: int) -> Dictionary:
	var b_live := _sum_tag(bb, "LIVE")
	var b_dead := _sum_tag(bb, "DEAD")
	var w_live := _sum_tag(bw, "LIVE")
	var w_dead := _sum_tag(bw, "DEAD")
	# 面积：只数已围住的空区（不含死活信息）。★ 调一次，同时取回**双方分项**。
	var area := _area_score()
	var area_b: float = maxf(_last_area_black, 0.0)
	var area_w: float = maxf(_last_area_white, 0.0)
	# 真负分：己方死子从自己应得目里扣掉（死子终将被提，己方拿不到也不算亏）
	var b_raw: float = float(b_live["stones"]) - (float(b_dead["stones"]) if score_true_live else 0.0)
	var w_raw: float = float(w_live["stones"]) - (float(w_dead["stones"]) if score_true_live else 0.0)
	# ★ 面积按**各自绝对值**并入（权重 0.5：面积仍有信息，但不该当全部）。
	#   第一版误把 `area`（= 黑 - 白 的**净值**）加给黑方、不给白方
	#   ⇒ 落后方拿到负面积（实测 black_points = -177.5）⇒ 双方都被算错且方向相反。
	var b_pts: float = b_raw + area_b * 0.5
	var w_pts: float = w_raw + area_w * 0.5 + komi   # 贴目只给白（沿用引擎既有 komi 语义）
	# 目数不可能为负（子数与围空都是非负计数）⇒ 先各自夹到 ≥0 再算占比
	b_pts = maxf(b_pts, 0.0)
	w_pts = maxf(w_pts, 0.0)
	var total := maxf(b_pts + w_pts, 1.0)
	return {"win_black": clampf(b_pts / total, 0.0, 1.0),
			"win_white": clampf(w_pts / total, 0.0, 1.0),
			"black_points": b_pts, "white_points": w_pts,
			"area": area}

## 按 tag 汇总块的个数与子数。返回 {count, stones}。
func _sum_tag(blocks: Array, tag: String) -> Dictionary:
	var c := 0
	var st := 0
	for b in blocks:
		if String(b.get("tag", "")) == tag:
			c += 1
			st += int(b.get("stones", 0))
	return {"count": c, "stones": st}

## 行动指令：**纯函数**，只依赖传进来的量 ⇒ 自检能逐条断言。
## 优先级（对应用户诉求「落后还去对方地盘落子」）：
##   ① 自己有未定形块→ 提示先救（这是本层存在的意义）
##   ② 落后超过阈值 → 明确「止损」：别再往对方围死的地里投子
##   ③ 对方有死块     → 提示提子收官
##   ④ 对方已围死空点多 → 提示那是无谓投入
func _advise(lead: float, own_live: Dictionary, own_unsettled: Dictionary,
		own_dead: Dictionary, their_dead: Dictionary, sealed_empty: int) -> String:
	if int(own_dead["count"]) > 0 and int(own_unsettled["count"]) > 0:
		return "止损：%d 块已死救不回，%d 块可做活 —— 先救可做活的" % [
			int(own_dead["count"]), int(own_unsettled["count"])]
	if int(own_unsettled["count"]) > 0:
		return "救活：%d 块未定形（%d 子）还能做活，优先补眼" % [
			int(own_unsettled["count"]), int(own_unsettled["stones"])]
	if lead < -advice_deficit:
		return "落后 %.0f%%：死子已定，勿投被围地%d 点，转向提子收官" % [
			-100.0 * lead, sealed_empty]
	if int(their_dead["stones"]) > 0:
		return "收官：对方 %d 子已成死子，提掉即真目" % int(their_dead["stones"])
	if int(own_live["count"]) > 0 and sealed_empty > 12:
		return "均势：我方已活，%d 点被围死无需争夺" % sealed_empty
	return "均势僵持：找要点"

func _obvious_root(root: MNode) -> bool:
	if not obvious_early_stop:
		return false
	var best := 0.0
	var second := 0.0
	var vinj: float = maxf(prior_visits, 1.0)
	for c in root.children:
		var rv: float = float(c.visits) - vinj
		if rv > best:
			second = best
			best = rv
		elif rv > second:
			second = rv
	if best < float(obvious_min_visits):
		return false
	if best + second <= 0.0 or best < obvious_share * (best + second):
		return false
	if second > 0.0 and (best - second) < obvious_lead * best:
		return false
	return true

# ============================================================================
#  对外主入口
# ============================================================================
## 线程入口包装：在后台线程完整跑一次思考（供 choose_move_async 使用）
func _search_entry(board_snapshot: Dictionary, ko: int, ai: int) -> int:
	return choose_move(board_snapshot, ko, ai)

## 协程版主入口：搜索在后台进行，主线程每帧让出、界面不冻结。
## 用法：var mv: int = await ai_engine.choose_move_async(board, ko_point)
func choose_move_async(board_dict: Dictionary, ko: int, ai: int = -1) -> int:
	var snap: Dictionary = {}
	for k in board_dict.keys():
		snap[k] = int(board_dict[k])
	var th := Thread.new()
	th.start(_search_entry.bind(snap, ko, ai), Thread.PRIORITY_NORMAL)
	var tree := Engine.get_main_loop() as SceneTree
	while th.is_alive():
		if tree != null:
			await tree.process_frame
		else:
			OS.delay_msec(4)
	return int(th.wait_to_finish())
## 给定当前棋盘与劫点，返回 AI 落子瓷砖号（-1 表示停一手）
func choose_move(board_dict: Dictionary, ko: int, ai: int = -1) -> int:
	if ai != -1:
		ai_color = ai
	# 防溢出：长时间对局后时间戳可能逼近 int32 上限
	# `_sc_id` 现在每 `_load_board()` 也会涨（见下），与 `_gid`/`_sid` 同量级 ⇒ 一并纳入。
	if _gid > 1000000000 or _sid > 1000000000 or _sc_id > 1000000000:
		_stamp_reset()

	_load_board(board_dict, ko)
	# ★★ 2026-10-27：五个统计计数器**按手归零**。
	#   此前它们只有声明与自增（`_area_calls` :2192 / `_influence_need` :2238 /
	#   `_dead_hit` :2255 / `_scanall_calls` / `_playout_calls`），**全文没有任何归零点**
	#   ⇒ `--aiprof` 打出的百分比是**进程生命周期累计值**：中盘（空区多、需要 influence）
	#   的分母被末盘（空区碎、根本不需要）的叶子摊薄 ⇒ 用它判「懒化能省多少」必然**低估**。
	#   也正是这个口径把 `_influence_need/_area_calls` 读到 478%~1090%（>100% 是因为
	#   它数的是「未定型空区**个数**」，一次评估可以有多个）⇒ 结论是
	#   **「几乎每次评估都有未定型空区」⇒ 懒化跳过整段 BFS 省不到钱**，已据此放弃该优化。
	_area_calls = 0
	_influence_need = 0
	_dead_hit = 0
	_scanall_calls = 0
	_playout_calls = 0
	var t0 := Time.get_ticks_msec()
	_eff_cap = _effective_playout_cap()

	# 动态分中心：本手搜索期间收集叶子分，结算后的均值成为下一手的锚点
	_dc_collect = true
	_dc_sum = 0.0
	_dc_sq = 0.0
	_dc_n = 0.0

	# 对手上一手（用于“贴身应战”先验 + 树复用）
	var opp_last := _infer_opp_move()

	# 根层候选 + 先验（内部已做 Top-K 剪枝）
	var tp0 := Time.get_ticks_usec()
	var root_info: Dictionary = _prepare_root(opp_last)
	if prof_on:
		prof_prepare_us += Time.get_ticks_usec() - tp0
	var cands: Array[int] = root_info["cands"]
	var priors: Array[float] = root_info["priors"]
	if cands.size() == 0:
		_clear_root_dist()
		_dc_finalize()
		_after_move(-1)
		return -1
	if cands.size() == 1:
		_clear_root_dist()
		_dc_finalize()
		_after_move(cands[0])
		return cands[0]

	var W := _effective_threads()
	var deadline := t0 + time_budget_ms

	# ---- 多线程：每份（主/后台）各自跑满预算，合并根节点统计 ----
	if W > 1:
		var ts0 := Time.get_ticks_usec()
		var agg: Dictionary = _parallel_search(cands, priors, deadline, W)
		if prof_on:
			prof_search_us += Time.get_ticks_usec() - ts0
			last_depth = prof_depth_max
		var best_v: int = _pick_merged(cands, priors, agg, W)
		# 快照必须在 `_after_move()` **之前**取：它会把子树提为新根，根分布随即失效。
		# 统计（真实访问 / 真实 Q / 注入量）全部来自 `_root_real_stats()` 这一处，
		# 与 `_pick_merged()` 选点用的是同一份数（§136）。
		var _rs: Dictionary = _root_real_stats(cands, priors, agg, W)
		last_root_cands = cands.duplicate()
		last_root_visits = (agg["visits"] as PackedFloat32Array).duplicate()
		last_root_q = (_rs["q"] as PackedFloat32Array).duplicate()
		last_root_v_inj = float(_rs["inj"])
		last_playouts = int(agg["iters"])
		last_ms = Time.get_ticks_msec() - t0
		_dc_finalize()
		_after_move(best_v)
		return best_v

	# ---- 单线程：建树 / 复用上一次的子树，原有迭代式搜索 ----
	var root: MNode = _reuse_tree(opp_last)
	if root == null:
		root = MNode.new()
		root.off = rng.randi() % n
		for k in cands.size():
			var cn := MNode.new()
			cn.move = cands[k]
			cn.player = ai_color
			cn.prior = priors[k]
			cn.off = rng.randi() % n
			cn.visits = int(maxf(prior_visits, 1.0))
			cn.wins = cn.prior * float(cn.visits)
			root.children.append(cn)
		root.nxt = n          # 根已一次性展开全部合法着法

	# 搜索
	var iters := 0
	var chk := 0
	while iters < max_playouts:
		root.visits += 1
		_iterate(root)
		iters += 1
		chk += 1
		if chk >= 24:
			chk = 0
			if Time.get_ticks_msec() >= deadline:
				break
			if iters >= obvious_min_visits and _obvious_root(root):
				break
	last_playouts = iters
	last_ms = Time.get_ticks_msec() - t0
	if prof_on:
		last_depth = prof_depth_max

	# 选子：与并行路径**统一**走 _pick_merged（先验打底 + 按样本量收缩的证据）。
	# 旧实现在这里单独用「访问数最多、平局偏先验高」，与并行路径是两套规则 ——
	# 后果是「简单档（单线程）」与「普通/困难档」的选点逻辑不同，
	# 调试单线程也测不到并行路径真正的选点行为（曾经据此得出过错误结论）。
	# 树复用时子节点集合可能与本次 cands 不完全一致 → 按 move 对齐，对不上的当作「无证据」。
	var agg := _agg_from_children(root.children, cands)
	var best_v: int = _pick_merged(cands, priors, agg, 1)
	# 同上：快照取在 `_after_move()` 之前（树复用会把子树提为新根）。
	# 三个量同源于 `_root_real_stats()` —— 别在这里另算一份（§8 / §136）。
	var _rs: Dictionary = _root_real_stats(cands, priors, agg, 1)
	last_root_cands = cands.duplicate()
	last_root_visits = (agg["visits"] as PackedFloat32Array).duplicate()
	last_root_q = (_rs["q"] as PackedFloat32Array).duplicate()
	last_root_v_inj = float(_rs["inj"])
	_dc_finalize()
	_after_move(best_v)
	return best_v


## 把「单线程路径的根子节点」整理成与 `_parallel_search` 同构的统计字典，
## 好让两条路径共用 `_pick_merged`。cands 里没有对应子节点的按 0 计数（= 只有先验）。
func _agg_from_children(children: Array, cands: Array[int]) -> Dictionary:
	var vs := PackedFloat32Array()
	var ws := PackedFloat32Array()
	vs.resize(cands.size())
	ws.resize(cands.size())
	var by_move := {}
	for c in children:
		by_move[c.move] = c
	for k in cands.size():
		var c: MNode = by_move.get(cands[k], null)
		if c != null:
			vs[k] = float(c.visits)
			ws[k] = float(c.wins)
	return {"visits": vs, "wins": ws}


func _load_board(board_dict: Dictionary, ko: int) -> void:
	for i in n:
		_b[i] = int(board_dict.get(i, EMPTY))
	_ko = ko
	_turn = ai_color
	_ply = 0
	_capsp = 0
	_pris_b = 0
	_pris_w = 0
	_logn = 0
	# ★★ 2026-10-08 修（**静默缺陷**）：盘面变了就**必须**推进局面版本号。
	#   按 `_sc_id` 失效的缓存有两处：`_anlz()`（局势分析 `_an_cache`）与
	#   `_own_area_layers()`（`_sc`/`_sv` 领地三态）。推进 `_sc_id` 的只有
	#   `_prepare_root()`（:3241）与 `probe_own_area()`（:2525）——
	#   而 `load_board_for_probe()` → `_load_board()` **改了盘面却不推**
	#   ⇒ 任何"换盘后再探分 / 再判领地"的路径都会**静默**拿到**上一局**的结论。
	#   受影响者：`game.gd` 里所有 `probe_root_score*` 调用（含 `--aidata` 的落盘，:3293/:3298）。
	#   `choose_move()` 那条路径**侥幸**没炸：它 `_load_board()` 之后紧跟 `_prepare_root()`，
	#   后者会推 —— 也就是说这个 bug 只吃探针与落盘，不吃对局本身，因此格外难被发现。
	#   判据：`game.gd` 的 `--scidtest`（A 局势缓存 / B 领地缓存，修前 2 项红、修后绿）。
	_sc_id += 1


## 通过棋盘 diff 推断对手上一手：找“原来空、现在是对方色”的点。
## 找到 0 个（对手停一手）或 >1 个（重置/悔棋/局面不连续）都返回 -1
func _infer_opp_move() -> int:
	if not _has_prev:
		return -1
	var opp := 3 - ai_color
	var found := -1
	var cnt := 0
	for i in n:
		if _prev_board[i] == EMPTY and _b[i] == opp:
			found = i
			cnt += 1
			if cnt > 1:
				return -1
	return found


## 把上一次搜索树中“我方上一手 → 对手上一手”对应的子树提为新根
func _reuse_tree(opp_last: int):
	_aw.fill(0.0)
	_an.fill(0.0)
	if _tree == null or _tree_move < 0:
		_tree = null
		return null
	var mid: MNode = null
	for c in _tree.children:
		if c.move == _tree_move:
			mid = c
			break
	if mid == null:
		_tree = null
		return null
	if opp_last < 0:
		return mid                  # 对手停一手：根就是我方落子后的节点
	for g in mid.children:
		if g.move == opp_last:
			_tree = g
			return g
	_tree = null
	return null


## 落子后收尾：快照棋盘（供下次 diff）、保存搜索树
func _after_move(best: int) -> void:
	if best >= 0 and _play(best) >= 0:
		_prev_board = _b.duplicate()
		while _ply > 0:
			_undo()
		_has_prev = true
		_tree_move = best
		return
	_has_prev = false
	_tree_move = -1
	if best >= 0:
		_tree = null


# ============================================================================
#  基准测试（调参用）
# ============================================================================
## 在给定毫秒内尽可能多地跑纯 rollout，返回完成次数。用于衡量策略开销
## 计时精度很关键：旧写法是 `for i in 32: ... ` 里才查一次时间，
## 于是返回的计数永远是 32 的整数倍（64 / 96 / 128）——
## 一次 rollout 只要几毫秒，32 次的粒度就等于 ±几成误差，
## A/B 比速时这点粒度会把 30% 的提速直接抹平（实测反复出现「两边都是 128」）。
## 改为每次 rollout 后用微秒时钟判断，粒度降到「1 次」，比值才有意义。
func benchmark(ms: int) -> int:
	clear_board()          # 固定从空盘起步，否则第二次调用是接着上一轮的残局跑，数字不可比
	var cnt := 0
	var t0 := Time.get_ticks_usec()
	var lim := ms * 1000
	while true:
		_logn = 0
		_playout(-1)
		cnt += 1
		if Time.get_ticks_usec() - t0 >= lim:
			break
	return cnt


# ============================================================================
#  自检辅助（仅供 --aiprof 等 headless 自检使用，不参与对局逻辑）
# ============================================================================
## 把内部棋盘导出成 {tile_id: color} 字典（只含非空点）
func export_board() -> Dictionary:
	var d := {}
	for i in n:
		if _b[i] != EMPTY:
			d[i] = int(_b[i])
	return d


## 在内部棋盘上用 rollout 策略快速铺 moves 手，制造一个真实的中盘局面。
## 用 _playout_move 而不是纯随机：它自带「不填自己眼」「不自杀」等约束，棋形更像真的
func scramble(moves: int) -> void:
	clear_board()
	_turn = BLACK
	_ko = -1
	_ply = 0
	_pris_b = 0
	_pris_w = 0
	_stamp_reset()
	var lm := -1
	var m := 0
	# ★ 2026-10-27 补护栏（缺陷修复，不是调参）：本函数是全文**唯一**没有「双方连续停手」
	#   上限的 rollout 循环 —— `_playout()` 与 `_rollout_fill()` 都写成
	#   `while passes < 2 and moves < cap`，只有这里 `continue` 后既不递增 `m`、也没有上限。
	#   盘面一旦进入「双方都无合法点」（空点全是自方单眼 / 劫点，`_playout_move` 的兜底
	#   搜索也找不到合法点 ⇒ 恒返回 -1）⇒ **死循环：无输出、无报错、进程还活着**。
	#   这是真会踩的：`--capftest` 用 `scramble(depth_step * (ci + 1))` 铺局面，
	#   s6 就要 240 手（盘只有 120 格），加到 s16 要 640 手。
	#   铺得够满时 `passes` 永远到不了 2 ⇒ 退出条件不变，逐位行为等价。
	var passes := 0
	while m < moves and passes < 2:
		var v := _playout_move(lm)
		if v == -1:
			passes += 1
			_turn = 3 - _turn
			_ko = -1
			continue
		passes = 0
		lm = v
		m += 1
	if m < moves:
		push_warning("[scramble] 只铺了 %d/%d 手：双方已无合法点（盘面填满或全剩单眼/劫点）" % [m, moves])


## 把内部棋盘清空。
## 注意 `setup()` 只做 `resize`，**不会**把 `_b` 置空（PackedInt32Array 只在首次分配时是 0），
## 所以「换盘/复用同一实例」后遗留的子会留在盘上；
## 铺局面的 `scramble()` 与测速的 `benchmark()` 必须显式清盘，否则第二次调用是从
## 「上一次留下的残局」继续落子 —— 自检里表现为局面越来越满、参数对照失真。
func clear_board() -> void:
	_b.fill(EMPTY)
	_ply = 0
	_capsp = 0
	_pris_b = 0
	_pris_w = 0
	_logn = 0
	_ko = -1
	_has_prev = false


## 自检用：引擎自己跟自己把一局下完（双方共用当前参数），返回终局统计。
## 用来量化「AI 会不会做活」——核心指标是终局还剩多少「只剩一口气的成块棋」：
## 这个数字越低，说明双方越会补活/保护弱棋（被叫吃没人管 = 没做活）
##
## ★ 2026-09-21 增记「填自己的眼」（用户头号抱怨）。三种计数分开记，各指一个病根：
##   · `fill_*`：落子落在**己方单点眼点**上（该点全部邻居都是自己子）。再按落子后
##     该块气数分 `lethal`（≤1 气 = 自紧气/送吃）与 `waste`（≥2 气 = 白费一手）；
##     并按落子**前**该块眼数细分：`eye2` = 已有 ≥2 只眼还去填（候选过滤本该拦住）；
##     `eye1` = 只有 ≤1 只眼（`_own_territory_only()` 的「做活豁免」**设计上就放行**
##     这类空区 → 要判的是放行之后 AI 有没有把最后一只眼也填掉）。
##   · `terr_viol_*`：引擎自己的判据 `_own_territory_only(v)` 判「此处是纯己方领地、不该落子」
##     而 AI 仍然落在这里 —— 与判据直接矛盾。**按构造应为 0**（`_prepare_root` 已过滤），
##     所以它是这套仪器的**阴性对照**：它若 >0，说明过滤层有洞，先修洞再谈调参。
func selfplay_to_end(budget_ms: int, max_moves: int) -> Dictionary:
	_b.fill(EMPTY)
	_ko = -1
	_ply = 0
	_capsp = 0
	_pris_b = 0
	_pris_w = 0
	_logn = 0
	_stamp_reset()
	_aw.fill(0.0)
	_an.fill(0.0)
	var turn := BLACK
	var moves := 0
	var passes := 0
	var caps := 0
	# ---- 填眼 / 做活记账（[黑, 白]）----
	var fill_lethal := [0, 0]
	var fill_waste := [0, 0]
	var fill_eye2 := [0, 0]
	var fill_eye1 := [0, 0]
	var fill_vital := [0, 0]          # 填的点正是做活要点 → 其实是在做活，不算病
	var fill_nonvital := [0, 0]       # 填的点不是要点，**且该空间识别得出要点** → 真·白填眼位
	var fill_void := [0, 0]           # 填的点不是要点，但**空间给不出要点**（判据失效区，不算病）
	var exempt_chosen := [0, 0]       # 落在「豁免开闸的己方空区」里的手数
	var exempt_vital := [0, 0]        # 其中落在做活要点上（正手）
	var exempt_waste := [0, 0]        # 其中「空间有要点却没下在要点上」= 真·白填己方眼位
	var exempt_void := [0, 0]         # 其中「空间给不出要点」= 判据失效区，**不能算病**
	var terr_viol := [0, 0]
	var fill_trace: Array = []
	var big_caps := 0
	var big_cap_stones := 0
	## 阴性对照：**落子之后**再问一次「这手是不是要点」。按构造必须恒为 0
	## （`_ld_pts` 只装空点，落子后 mv 自己成了子 → `_ldm_index()` 必返 -1）。
	## 非零即说明 `_ld_pts` 的语义变了、这条陷阱不复存在，那时才该改用落子后的值。
	var vital_post_hits := 0
	var eye_pts_seen := 0             # 全部「己方眼点」机会（含被过滤的）
	var eye_pts_open := 0             # 其中通过候选过滤、AI 真能选的（= 疾病唯一可能发生的场合）
	var blocked_pts := 0              # 「纯领地」被拦掉的空点（层 A∧B）
	var exempt_pts := 0               # 「豁免」开闸放行的空点（层 A∧¬B）= 口子宽度
	var eye_pts_turns := 0
	var old_budget := time_budget_ms
	time_budget_ms = budget_ms
	while moves < max_moves and passes < 2:
		var snapshot := export_board()
		var mv := choose_move(snapshot, _ko, turn)
		if mv < 0:
			passes += 1
			turn = 3 - turn
			continue
		# ---- 落子前的诊断：必须在 `_play` 之前采集，落子之后眼点就不存在了 ----
		# 此刻 `_turn == turn`（下面 `_play` 依赖这一点），且 `_ply == 0`（搜索已完全回卷），
		# 所以这些只读查询不会踩到搜索栈。
		var ci: int = 0 if turn == BLACK else 1
		var is_fill := false
		var eyes_before := -1
		var terr := false
		var in_exempt := false
		var vital_pre := false
		var vital_space := false
		if _b[mv] == EMPTY:
			# ★ 过滤层口径拆两层后，**落点本身**归哪一类直接可读：
			#   A∧B = 纯领地（过滤应拦下；落在这里 = 过滤层有洞，见 `terr_viol` 阴性对照）；
			#   A∧¬B = **做活豁免开闸的空区**：既包括「补活要点」（正手），也包括
			#          「往自己未定形的眼位里乱填」（用户的抱怨）—— 两者必须靠「是不是要点」分开。
			var laym := _own_area_layers(mv)
			var la_mv: bool = bool(laym[0])
			var lb_mv: bool = bool(laym[1])
			if la_mv and lb_mv:
				terr_viol[ci] += 1
				terr = true
			in_exempt = la_mv and not lb_mv
			if _is_own_eye_point(mv, turn):
				is_fill = true
				var info := _adj_own_eye_info(mv, turn)
				eyes_before = int(info[0])
			# ★★ 要点判据必须在 `_play(mv)` **之前**算。`_ld_pts` 只装**空点**，
			#   一旦落子，mv 自己成了子 → `_ldm_index(mv)` 必然 -1 → 判据**恒为假**。
			#   第一版把它写在落子之后，于是「要点 0 ／ 非要点 N」里的 N 一直只是
			#   「落在豁免空区的手数」的别名，这一列**从来没被测到过**（看着像结论，其实是假红）。
			# ★★ 而且「不是要点」还必须再拆两层 —— `_eye_vital_flags()` 返回的第 1 项
			#   「本空间识别得出要点吗」决定了这句判词到底成不成立（见该函数的注释）：
			#     · 空间识别得出要点、这手却没下在要点上 → **真·白填**（机器判据与惩罚都指向它）；
			#     · 空间压根给不出要点（非小眼位空间 / 已活已死 / 杀点集为空 = 判据失效区）
			#       → 既不该罚、也不能算病；把它算进「白填」就是**拿判据的失效当证据**。
			if is_fill or in_exempt:
				var vf_pre := _eye_vital_flags(mv)
				vital_space = bool(vf_pre[0])
				vital_pre = bool(vf_pre[1])
		# ---- 机会数（仪器的**牙齿** + 病根 B 的口子大小）----
		# 没有这几列，「填眼=0」到底是「AI 不填」还是「压根没有眼点可填」根本分不开 ——
		# 后者说明这把尺子在这个盘型上从来没对准靶子（技能纪律：先证仪器能响）。
		#   · `eye_pts_seen`：本手棋盘上共有多少个「己方眼点」；
		#   · `eye_pts_open`：其中**通过候选过滤**、AI 真能选的那些 —— 疾病只可能出现在这里；
		#   · `exempt_pts`：豁免开闸的**全部**空点（含非单点眼的活形内部，如直四/曲四/葡萄六）。
		#     ⚠️ 只数「单点眼」会漏掉整整一类：直四/曲四/直六/葡萄六这些**已经是活形**的形状
		#     单点眼数 = 0、气 < 6 → 被旧判据 `_group_alive` 判成「未活」→ 整片空间开闸，
		#     于是 AI 可以往里填 —— 这类「填眼」在第一版尺子里根本不可见。
		for v in n:
			if _b[v] != EMPTY:
				continue
			var lay := _own_area_layers(v)
			var is_blocked: bool = bool(lay[0]) and bool(lay[1])
			if bool(lay[0]):
				if is_blocked:
					blocked_pts += 1
				else:
					exempt_pts += 1
			if _is_own_eye_point(v, turn):
				eye_pts_seen += 1
				if not is_blocked:
					eye_pts_open += 1
		eye_pts_turns += 1
		var nc := _play(mv)
		if nc < 0:
			passes += 1
			turn = 3 - turn
			continue
		# ★ 落点落在「豁免开闸的己方空区」里 → 记一笔，并用**是不是要点**分成两类。
		#   这一列才是「AI 填自己的眼」在实战里真正该看的宽度（单点眼只是其中最扎眼的一种）。
		if in_exempt:
			exempt_chosen[ci] += 1
		if is_fill or in_exempt:
			var gsz := _group(mv)          # 落子后 v 已并入本块
			var la := _libs(gsz, -1)
			# 决定性问题：落点**是不是做活/点杀的要点**？
			#   是 → 这手其实是在做活（`_eye_vital_bonus` 给的正分），不算病；
			#   不是 → 再看「本空间识别得出要点吗」（`vital_space`）：
			#         能识别 → 真·白填（`*_waste`）；识别不出 → 判据失效区（`*_void`，不算病）。
			# ⚠️ 两个取值都来自**落子前**（原因见上面的 ★★ 注释）。
			# 这里再算一次**落子后**的值，纯粹当阴性对照：它必须恒为假。
			var vital := vital_pre
			if _is_vital_point(mv):
				vital_post_hits += 1
			if in_exempt:
				if vital:
					exempt_vital[ci] += 1
				elif vital_space:
					exempt_waste[ci] += 1
				else:
					exempt_void[ci] += 1
			if is_fill:
				if vital:
					fill_vital[ci] += 1
				elif vital_space:
					fill_nonvital[ci] += 1
				else:
					fill_void[ci] += 1
				if la <= 1:
					fill_lethal[ci] += 1
				else:
					fill_waste[ci] += 1
				if eyes_before >= 2:
					fill_eye2[ci] += 1
				else:
					fill_eye1[ci] += 1
			if fill_trace.size() < 12:
				fill_trace.append("第%d手%s 点%d %s眼数=%d 落子后气=%d 要点=%s%s%s" % [
					moves + 1, "黑" if turn == BLACK else "白", mv,
					"单点眼(填眼前" if is_fill else "豁免空区(落点非单点眼，",
					eyes_before, la,
					"是(在做活)" if vital
					else ("★否(白填眼位)★" if vital_space else "—(空间给不出要点)"),
					"｜致命" if la <= 1 else "", "｜纯领地违规" if terr else ""])
		if nc >= 3:
			big_caps += 1
			big_cap_stones += nc
		caps += nc
		passes = 0
		moves += 1
		turn = _turn               # _play 已把 _turn 推进为下一手该下的颜色
	time_budget_ms = old_budget

	# 终局统计：只剩一口气的成块棋（>=3 子）= 没做活的直接体现
	var dead_b := 0
	var dead_w := 0
	var dy_b := 0                     # 只剩 2 气（濒死/未定形）
	var dy_w := 0
	var ntaken := 0
	_cid += 1
	var cid := _cid
	for i in n:
		var c: int = _b[i]
		if c == EMPTY or _cst[i] == cid:
			continue
		var gsz := _group(i)
		for j in gsz:
			_cst[_gbuf[j]] = cid
		if gsz >= 3:
			var gl := _libs(gsz, -1)
			if gl <= 1:
				if c == BLACK:
					dead_b += gsz
				else:
					dead_w += gsz
			elif gl == 2:
				if c == BLACK:
					dy_b += gsz
				else:
					dy_w += gsz
	for i in n:
		if _b[i] != EMPTY:
			ntaken += 1
	return {
		"moves": moves, "caps": caps, "stones": ntaken,
		"dead_black": dead_b, "dead_white": dead_w,
		"dying_black": dy_b, "dying_white": dy_w,
		"passes": passes, "big_caps": big_caps, "big_cap_stones": big_cap_stones,
		"fill_lethal": fill_lethal, "fill_waste": fill_waste,
		"fill_eye2": fill_eye2, "fill_eye1": fill_eye1,
		"fill_vital": fill_vital, "fill_nonvital": fill_nonvital, "fill_void": fill_void,
		"exempt_chosen": exempt_chosen, "exempt_vital": exempt_vital, "exempt_waste": exempt_waste,
		"exempt_void": exempt_void,
		"terr_viol": terr_viol, "fill_trace": fill_trace,
		"eye_pts_seen": eye_pts_seen, "eye_pts_open": eye_pts_open, "eye_pts_turns": eye_pts_turns,
		"blocked_pts": blocked_pts, "exempt_pts": exempt_pts,
		"vital_post_hits": vital_post_hits,
		"area": _area_score(), "our_area": _sum_area_scores(),
	}


## 中国规则数子：己方子 + 己方独占空区（用于自检输出，双方各算一次）
func _sum_area_scores() -> Vector2i:
	var tb := 0
	var tw := 0
	for i in n:
		var c: int = _b[i]
		if c == BLACK:
			tb += 1
		elif c == WHITE:
			tw += 1
	_gid += 1
	var sid := _gid
	for i in n:
		if _b[i] != EMPTY or _gst[i] == sid:
			continue
		_gst[i] = sid
		_gbuf2[0] = i
		var cnt := 1
		var qi := 0
		var ob := false
		var ow := false
		while qi < cnt:
			var cur := _gbuf2[qi]
			qi += 1
			var k := _as[cur]
			var ke := _as[cur + 1]
			while k < ke:
				var nb := _af[k]
				k += 1
				var cc := _b[nb]
				if cc == EMPTY:
					if _gst[nb] != sid:
						_gst[nb] = sid
						_gbuf2[cnt] = nb
						cnt += 1
				elif cc == BLACK:
					ob = true
				else:
					ow = true
		if ob and not ow:
			tb += cnt
		elif ow and not ob:
			tw += cnt
	return Vector2i(tb, tw)
