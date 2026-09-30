# Godot 3D 世界與 Blender 美術工作

## 自動選用美術技能

使用者要求在執行相關任務、設計 3D 世界時，自動選用已安裝的美術技能，不必等待使用者逐一點名。根據本次工作選用必要技能並先讀取其 SKILL.md；不用把整套技能一次載入。純程式修正若不涉及美術，就使用對應 Godot 技能。

技能位置：`C:/Users/xuan9/.codex/skills/<技能名稱>/SKILL.md`。

| 任務 | 自動選用 |
| --- | --- |
| 世界風格、場景氛圍、整體美術製作 | `blender-pro-workflow`、`environment-artist`，按需要搭配燈光、材質與鏡頭技能 |
| 建築、地形、模組化場景 | `environment-artist`、`blender-modeling` |
| 道具、家具、可互動物件 | `prop-artist`、`blender-modeling` |
| 操作 Blender、修改既有模型 | `codex-blender` 加上本次修改領域的技能 |
| 重拓撲與變形網格 | `retopology` |
| UV、貼圖配置與材質 | `uv-workflow`、`blender-materials` |
| 骨架、權重與動畫 | `rigging`、`blender-animation`；引擎整合用 `godot-animation` |
| 燈光、構圖與参考圖校準 | `blender-lighting`、`blender-cameras`、`reference-look-calibration`，依任務選取 |
| 模型效能與碰撞 | `asset-optimization`、`collision-proxy`；引擎物理用 `godot-physics` |
| Blender 模型交付 Godot | `blender-export`、`godot`，按需要搭配 `godot-3d-essentials`、`godot-shaders` |
| Godot 原生幾何資產 | `godot-create-3d-assets`，先確認其需要的 MCP 工具確實可用；否則改用 `godot` CLI 工作流程並明確說明限制 |

## 美術與交付原則

- 以使用者的風格、參考圖與世界設計為準。先建立尺度、輪廓與可探索的場景，再深化材質、燈光、構圖與細節。
- 修改前查看既有場景與模型；保留可編輯的 `.blend`、骨架、形態鍵與來源資產。減面或套用破壞性修改器時使用匯出副本。
- Godot 資產交換優先使用 GLB/glTF，並在實際遊戲場景檢查尺度、方向、材質、碰撞及動畫；不能只憑匯出檔存在就宣稱完成。
- 多邊形、貼圖、植被與模擬規模依目前硬體和專案目標設定；避免直接套用高階硬體的固定預算。
- 美術改動要查看實際畫面與遊戲視角；角色改動涉及變形時，檢查相關動作及穿插。無法驗證的部分如實說明。
- 本檔設定技能選用方式，不代表自動開始製作新內容；以每次使用者提出的任務範圍為準。
