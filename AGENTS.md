# Godot 3D 世界與 Blender 美術工作

## 自動選用美術技能

使用者要求在執行相關任務、設計 3D 世界時，自動選用已安裝的美術技能，不必等待使用者逐一點名。根據本次工作選用必要技能並先讀取其 SKILL.md；不用把整套技能一次載入。純程式修正若不涉及美術，就使用對應 Godot 技能。

技能位置：`$CODEX_HOME/skills/<技能名稱>/SKILL.md`，未設定時使用使用者家目錄下的 `.codex/skills`；本機目前為 `C:/Users/admin/.codex/skills/<技能名稱>/SKILL.md`。

| 任務 | 自動選用 |
| --- | --- |
| 世界風格、場景氛圍、整體美術製作 | `create-game-assets`、`environment-artist`，按需要搭配 `lighting`、`materials`、`camera-cinematography`；低多邊形風格使用 `lowpoly-style` |
| 建築、地形、模組化場景 | `environment-artist`、`blender-modeler` |
| 道具、家具、可互動物件 | `prop-artist`、`blender-modeler` |
| 操作 Blender、修改既有模型 | `blender-modeler` 加上本次修改領域的技能 |
| 角色造型、比例、服裝與可動畫化網格 | `character-artist`，依需要搭配 `retopology` |
| 重拓撲與變形網格 | `retopology` |
| UV、貼圖配置與材質 | `uv-workflow`、`materials` |
| 骨架、權重、IK/FK 與動畫 | `rigging`、`animation`；引擎整合用 `godot-animation` |
| 燈光、構圖與參考圖校準 | `lighting`、`camera-cinematography`，依任務選取；共用參考檔在技能根目錄的 `references/` |
| 模型效能與碰撞 | `asset-optimization`、`collision-proxy`；引擎物理用 `godot-physics` |
| Blender 模型交付 Godot | `godot-export`，按需要搭配 `godot-3d-essentials`、`godot-shaders`、`godot-animation` |
| Godot 3D 場景、原生幾何與材質 | `godot-3d-essentials`、`godot-nodes-scenes`、`godot-shaders` |
| Godot 程式、場景結構與物理 | `godot-gdscript`、`godot-nodes-scenes`、`godot-physics` |

## 工具與版本適配

- 安裝技能不等於已連接 Blender MCP。先確認實際工具與本機 Blender/Godot 執行檔；MCP 不可用時，可以用本機 Blender 的 Python/bpy 或背景模式及 Godot CLI 完成已授權的工作，並驗證輸出。不能把工具需求當成已具備的能力。
- 先核對專案及執行檔版本，再使用技能中的 API 範例；Godot 技能標示目標為 4.7。本專案使用 GL Compatibility，效果與效能設定需符合實際渲染器。
- 社群技能的命名、預算、公式與工作流程是參考；以使用者要求、既有資產約定與對應版本的官方文件為準。Godot 碰撞匯入不能直接沿用 Unreal 的 UCX 命名；UV texel density 應以貼圖像素數、UV 覆蓋量與模型實際尺寸計算。
- 2026-10-10 安裝 22 個技能，來源為 `minhhoit/gamedev-agent-skills` 與 `arjun988/blender-skills`。每個技能目錄的 `INSTALL_SOURCE.json` 記錄來源與固定 commit，並附授權檔；完整清單位於 `C:/Users/admin/.codex/skill-install-manifests/game-art-20261010.json`。

## 美術與交付原則

- 以使用者的風格、參考圖與世界設計為準。先建立尺度、輪廓與可探索的場景，再深化材質、燈光、構圖與細節。
- 修改前查看既有場景與模型；保留可編輯的 `.blend`、骨架、形態鍵與來源資產。減面或套用破壞性修改器時使用匯出副本。
- Godot 資產交換優先使用 GLB/glTF，並在實際遊戲場景檢查尺度、方向、材質、碰撞及動畫；不能只憑匯出檔存在就宣稱完成。
- 多邊形、貼圖、植被與模擬規模依目前硬體和專案目標設定；避免直接套用高階硬體的固定預算。
- 美術改動要查看實際畫面與遊戲視角；角色改動涉及變形時，檢查相關動作及穿插。無法驗證的部分如實說明。
- 本檔設定技能選用方式，不代表自動開始製作新內容；以每次使用者提出的任務範圍為準。
