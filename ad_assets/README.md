# Disc Golf 广告片 (AV) 资产包

所有广告片相关的设计、参考图、提示词都放在这个文件夹。

## 目录结构

```
ad_assets/
├── README.md                       ← 本文件（创意 + 整体规划）
├── reference/                      ← 互联网参考图（CC0/可商用）
│   └── (下载脚本 + 图片)
├── prompts/                        ← 图像生成 prompts（每个分镜的 keyframe）
│   ├── shot1_locker.md
│   ├── shot2_real_throw_fail.md
│   ├── shot3_phone_pickup.md
│   ├── shot4_game_play.md
│   ├── shot5_redemption.md
│   └── shot6_chains_logo.md
└── video_prompts/                  ← 视频生成 prompts（每个分镜的动作描述）
    ├── shot1_locker.md
    ├── shot2_real_throw_fail.md
    ├── shot3_phone_pickup.md
    ├── shot4_game_play.md
    ├── shot5_redemption.md
    └── shot6_chains_logo.md
```

## 创意概要

漫画风格的"现实→游戏→现实"三段式广告。

- **总时长**：约 24 秒，分 2 次 15s 视频生成拼接
- **风格**：日式漫画/动漫线稿（cel-shaded），干净色块，明确轮廓
- **目标**：卖**游戏**，不是真实运动 —— 必须有清晰的游戏画面 + UI 元素

## 6 分镜总览

| # | 时长 | 场景 | 情绪 |
|---|---|---|---|
| 1 | 4s | 更衣室准备 | 期待 |
| 2 | 4s | 草原扔盘撞树 | 沮丧 |
| 3 | 3s | 掏手机打开游戏 | 转场 |
| 4 | 5s | 游戏画面：森林→湖泊→硬地 | 投入 |
| 5 | 4s | 回归现实自信投盘 | 高涨 |
| 6 | 4s | 进筐 + Logo CTA | 胜利 |

## 用法

1. 先看 `reference/` 里的图片，确定风格基调
2. 把 `prompts/shot*_*.md` 喂给图像生成模型，得到每个分镜的 keyframe 图像
3. 把图像 + `video_prompts/shot*_*.md` 喂给视频生成模型
4. 把 6 段视频按顺序拼接成最终 24s 广告片

## 拼接方案

由于视频模型一次最多生成 15s：

- **第 1 次生成**：分镜 1+2+3 = 11s
- **第 2 次生成**：分镜 4+5+6 = 13s

各自单镜也可以单独生成，再用剪辑软件拼接。
