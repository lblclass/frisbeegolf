# Master Shoot Guide — Disc Golf Ad

> 给视频/图像生成模型操作员的一站式生产手册。

## 总时长 24 秒，6 镜，分两次生成

```
镜 1 ─┐
镜 2 ─┼─  第一次生成（11s）
镜 3 ─┘

镜 4 ─┐
镜 5 ─┼─  第二次生成（13s）
镜 6 ─┘
```

如果模型支持的话，每镜独立生成质量更好（避免长视频跨镜头一致性问题），剪辑软件拼接。

## 6 镜逐镜信息

| # | 时长 | 文件 | 概要 |
|---|---|---|---|
| 1 | 4s | shot1_locker | 更衣室准备，挎飞盘包 |
| 2 | 4s | shot2_real_throw_fail | 草原扔盘撞树（**慢动作撞击**）|
| 3 | 3s | shot3_phone_pickup | 掏手机打开游戏 UI（**转场关键**）|
| 4 | 5s | shot4_game_play | 游戏画面：森林→湖泊→硬地（**广告卖点核心**）|
| 5 | 4s | shot5_redemption | 男孩自信复盘投出（**对比 Shot 2**）|
| 6 | 4s | shot6_chains_logo | 进筐 + Logo CTA |

每个分镜在两个文件夹各有一份：
- `prompts/shot*.md` — 图像生成 prompt（用于 keyframe）
- `video_prompts/shot*.md` — 视频生成 prompt（用于动画）

## 推荐生产流程

### 阶段 1：keyframe 生成（图像）
对每个分镜的 `prompts/shot*.md`：
1. 把整段 prompt 喂给图像模型
2. 生成 4 张候选，挑最好的 1 张
3. 保存到 `ad_assets/keyframes/shot1_keyframe.png` 等

### 阶段 2：视频生成
对每个分镜的 `video_prompts/shot*.md`：
1. 用阶段 1 的 keyframe 作为起始帧
2. 把 video prompt 喂给视频模型
3. 生成 15s 内（每段 3-5s）
4. 保存到 `ad_assets/videos/shot1.mp4` 等

### 阶段 3：剪辑拼接
1. 6 段视频按顺序拼接
2. 加配乐 + 音效（鼓点 + 链子声 + Logo "叮"）
3. 加字幕（如果用中文版）
4. 导出 1080p 24s

## 风格基调（必须一致！）

- **整体**：日式漫画 / cel-shaded anime（**禁用**写实摄影、3D 渲染）
- **角色**：青少年男孩，黑色乱发，亮眼，运动装
- **色调**：
  - **现实场景**（Shot 1, 2, 5）：暖色温（金色光、深红、黄绿草地）
  - **游戏场景**（Shot 3 屏内, 4）：高饱和扁平色（亮黄盘、青色轨迹、深绿草地）
- **字体**：Logo 用粗体漫画字体，CTA 用干净 sans-serif
- **品牌色**：黄 + 青（贯穿整片）

## Reference 文件夹的图片用途

`reference/` 里有 10 张 CC0 图（Unsplash 下载）：
- `disc_thrower_*.jpg` — 投盘姿势参考
- `disc_basket_1.jpg` — 真实筐子链子
- `forest_*.jpg` — 树木材质
- `lake_*.jpg` — 水面
- `desert_*.jpg` — 开阔地
- `locker_*.jpg` — 更衣室光线
- `phone_gaming_1.jpg` — 手机持握姿势

**这些是 reference，不是最终素材**。生成模型可以参考它们的构图、光线、姿态，但风格要统一在 anime cel-shaded 上。

## Shot 4 的关键操作

Shot 4 的 keyframe 应该**直接用游戏实机截图**，不用图像生成。流程：

1. F5 跑游戏
2. 进入 Level 3 (Forest) 投盘到中段时按系统截图（Mac: Cmd+Shift+4）
3. Level 4 (Lakes) 飞盘飞越水面瞬间截图
4. Level 5 (Hard Ground) 飞盘下降到硬地瞬间截图
5. 把截图喂给视频模型作为 keyframe，prompt 用 `video_prompts/shot4_game_play.md`

这样 Shot 4 是**真游戏画面**，不是 AI 假画的"看起来像游戏"。这是最强的真实性。

## 配乐建议（broll music suggestions）

- **0-4s** Shot 1：低沉鼓点 + 钢琴（紧张铺垫）
- **4-8s** Shot 2：紧张电子音 → 撞击重音 → 失落弦乐
- **8-11s** Shot 3：清脆电子音转场（手机滴一声）
- **11-16s** Shot 4：轻快流行 / 律动节拍（沉浸感）
- **16-20s** Shot 5：弦乐渐强 + 鼓点 build-up
- **20-24s** Shot 6：进筐高潮 + logo 收尾

参考曲风：游戏宣传片的"启发式"配乐。可以在 Pixabay / Epidemic Sound 找 royalty-free。

## 字幕版本

- **英文**：默认走 prompts 里的英文文案
- **中文**：把 prompts 里出现的英文文字标语翻译，例如：
  - "DISC GOLF" → "飞盘高尔夫"
  - "Out Now on iOS / Android / Steam" → "iOS / Android / Steam 立即游玩"
  - HUD 文字（"Stroke", "MID", "Hyzer"）可保留英文（玩家熟悉）或改成"杆数 / 中投 / 倾角"

## 检查清单（生成完后核对）

- [ ] 6 段视频按顺序拼接是否流畅
- [ ] 角色形象在 6 段中是否一致（同一男孩）
- [ ] 飞盘颜色是否一致（建议**统一为黄色**，避免 Shot 2 红 Shot 5 黄混乱）
- [ ] 青色轨迹线在 Shot 3/4/5 是否出现（重要的 brand callback）
- [ ] Logo 是否清晰可读
- [ ] 总时长是否 ≤ 30s（社交媒体最佳长度）
- [ ] 有无水印 / 模型 logo 残留
