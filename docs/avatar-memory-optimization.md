# 輕量角色匯出與驗證

本輪採用 `game/assets/character/runtime/` 的行走、跑步與跳躍匯出副本。原本的三個角色 GLB、所有 `.blend`、骨架、形態鍵與動畫來源未改寫。坐姿繼續使用既有 `graduate_rest.glb` 的 12 組矯正形態。

角色重量確實主要在逐幀布料形態資料：原行走模型只有 11,874 個三角形、18,070 個匯出頂點，卻有 3,003 組分散在各部件的 morph targets；跳躍為 6,707 個三角形、13,444 個頂點與 1,936 組 targets。

## 最終選擇

`tools/build_lightweight_avatar.py` 對原動畫的每個時間樣本計算位置與法線誤差，保留必要的布料姿態、共用完全相同的姿態，去除無意義的靜態微小差異。每個網格同時最多使用兩個形態；骨架軌道、原始關鍵時間、拓撲、UV、權重和材質都保持原值。沒有角色減面，也沒有降低骨架動畫更新率。

設定上限為位置 2 mm、法線向量差 0.05。輸出逐樣本實測最大位置差為 **1.700 mm**，最大法線向量差 **0.04248**。原曲線和新曲線在相同關鍵時間使用線性插值，因此未經法線正規化的中間向量誤差受端點界限約束；報告不把這個數學界限直接當作全部渲染結果。

| 資產 | 原 GLB | 最終 GLB | targets 原／新 |
|---|---:|---:|---:|
| 行走、跑步、入場、待機 | 58,256,952 B | 42,021,116 B | 3,003 / 916 |
| 跳躍、翻轉、落地 | 49,957,832 B | 40,778,928 B | 1,936 / 1,179 |
| 合計 | 108,214,784 B | 82,800,044 B | 4,939 / 2,095 |

Godot 實際匯入的兩個 `.scn` 合計從 **47,658,091 B** 降至 **35,164,246 B**。這是資產大小，不能直接當作 PCK 傳輸量或執行記憶體節省比例。原 GLB 在專案中保留，正式 Web／Windows 匯出需排除原行走／跳躍檔，只封裝 runtime 副本與仍使用的坐姿模型。

`PlanetPlayer` 在既有分階段準備流程使用新路徑，並快取有形態的網格和動畫名稱，切換動作不再搜尋整個模型樹。行走和跳躍兩套小型副本仍事先準備，原因是兩者衣服拓撲不同，而且落地後會同時取樣兩套骨架來接回行走；臨時在按跳躍時載入會引入停頓。沒有宣稱已把兩套幾何合成一套。

## 同機原生比較

`tools/benchmark_avatar_variants.py` 實際執行三個獨立 Godot 程序，各暖機 5 秒後量測 30 秒，動作路線相同：走路、跑步、待機、起跳、翻轉、落地、入場。1280×720、MSAA 關閉、VSync 關閉、FPS 不限速，兩套模型同時載入；這是隔離的角色成本測試，**不是全世界遊玩 FPS**。

Godot 4.7.2，Compatibility／原生 OpenGL 3.3，實際 GPU 為 NVIDIA GeForce MX330，驅動 511.69。Windows RSS 與 private commit 透過實際 `godot.exe` 的程序計數器每 250 ms 讀取；不是 console 啟動器、JS heap 或 Web 中為 0 的監視器。GPU 專用／共用記憶體未包含於這張程序記憶體表。

| 單次測試 | 原始角色 | 最終自適應取樣 | 實驗 PCA |
|---|---:|---:|---:|
| 平均 FPS（角色場景、不限速） | 224.69 | 241.22 | 46.03 |
| P95 幀時間 | 6.436 ms | 7.153 ms | 32.233 ms |
| >100 ms 停頓（暖機後） | 0 | 0 | 0 |
| 程序峰值 RSS | 355,852,288 B | 267,509,760 B | 245,284,864 B |
| 程序峰值 private commit | 445,325,312 B | 334,315,520 B | 302,985,216 B |
| 可見模型最多同時非零形態 | 54 | 38 | 464 |

最終方案這次量到峰值 RSS 少 **88,342,528 B**、private commit 少 **111,009,792 B**。FPS 與 P95 並非同方向改善，只跑了一次，因此不宣稱穩定 FPS 提升或所有 4GB 電腦都達標。

也實際製作並量測了誤差相同的 PCA 小基底方案。它比最終方案另外少約 22 MB 峰值 RSS，但同時啟用很多形態，隔離場景 P95 上升到 32.2 ms，因此沒有用於遊戲。Compatibility 的非零形態需要額外混合處理，見 [Godot GLES3 實作](https://github.com/godotengine/godot/blob/4.5/drivers/gles3/storage/mesh_storage.cpp#L1293)；這裡的採用決定依上表的本機 4.7.2 實測，不只依較早版本原始碼推斷。實驗資產移至忽略的 `build/avatar-pca-experiment/`，正式場景不引用它。

## 外觀與功能驗證

`game/tests/lightweight_avatar_checks.gd` 使用真實 Compatibility 渲染器，把原始與最終角色並排，檢查 7 個動作的 42 個取樣姿態，再擷取半坐與完整坐姿。共 **56 項檢查通過**；實際匯入後網格讀回的最大位置差 **1.286 mm**，法線向量差 **0.03895**。`bake_mesh_from_current_blend_shape_mix` 是網格形態讀回，骨架軌道另外以原始資料相等檢查；它不是全身穿插的自動判定。相關 API 見 [Godot MeshInstance3D](https://docs.godotengine.org/en/stable/classes/class_meshinstance3d.html#class-meshinstance3d-method-bake-mesh-from-current-blend-shape-mix)。

已實際查看走路、跑步、起跳、翻轉、翻轉後伸展、兩段落地與坐姿畫面；未見本次新增的明顯衣服穿插或角色辨識度改變。這些姿態截圖不取代主遊戲的碰撞與長時間路線驗證。既有 `lazy_avatar_music_checks.gd` **41 項通過**，包含無角色全景、分階段建立、31 根落地恢復骨骼映射、動作切換、重複準備不增加節點及入場材質還原。

仍有單次同步 `load` 成本：這次 headless API 檢查量到行走 140.5 ms、跳躍 160.1 ms。兩個載入操作已有不同幀，不能把「分幀」宣稱成每個操作都低於 33 ms。Web 實際初始化及整體記憶體仍以主報告的最終匯出測試為準。

數據與截圖：`deliverables/low-memory/avatar/` 的 `engine-validation.json`、`benchmark-*.json`、`memory-*.json` 和 `Walk/Run/JumpStart/JumpAir/JumpLand/Sit-*.png`。生成誤差與來源 SHA-256 在 `game/assets/character/runtime/derivation.json`。第一次原生啟動的 ANGLE/EGL 失敗在開始量測前發生，改用可運作的原生 OpenGL 驅動後重新執行全組；失敗日誌保留在 `build/avatar-native-angle-failed.log`，未混入表中。

## 後續 surface 合併可行性：未套用、未量測效能

2026-10-07 對最終 `packs-7bd866e6416621ee` 使用的兩個 runtime GLB 做唯讀 JSON／程式檢查：每個均為 **27 meshes、39 primitives、1 skin、11 材質**，沒有圖片、UV 或頂點色；現有 Godot 匯入設定已開啟 `array_mesh/deduplicate_surfaces`。下列合併尚未產生任何實驗副本，沒有更動凍結版本，也沒有 FPS 改善數據。

所有 mesh 節點使用 skin 0、相同父節點 `GraduateRig`（node 58）、identity 局部 TRS。不含形態且沒有節點動畫軌道的部件，行走模型為 mesh **5、10–15、26**（領口、襯衫、帽子、帽釦、補回的手臂）；跳躍模型另含 **16–24**（流蘇）。這些部件的屬性都是 POSITION／NORMAL／JOINTS_0／WEIGHTS_0，可以研究依原材質拼接頂點與偏移索引，保留 skin、inverse bind、各頂點權重與幾何。其餘含形態的網格與動畫軌道保持獨立，坐姿模型不納入此方案。

| 尚未實作的策略 | 行走 surface 數 | 跳躍 surface 數 | 限制 |
|---|---:|---:|---|
| 僅合併上述部件的完全相同材質 | 39 → 35 | 39 → 27 | 不需改顏色；理論上可原值拼接，仍需匯入／動作驗證 |
| 各形態網格內合併只有底色不同的材質 | 39 → 31 | 39 → 31 | 普通頂點色不是無損方案，見下段 |
| 再將上述無形態部件按底色以外屬性合併 | 39 → 26 | 39 → 18 | 同樣有顏色精度限制；mesh 數潛力為 20／11 |

材質只忽略名稱與 baseColorFactor 後，分組為 **[0,1,2,5,10]**（黑衣摺痕／襯衫／褲子，metallic 0、roughness 0.75）、**[7,8,9]**（皮膚／眼／髮，metallic 0、roughness 0.82）；**3** 緞帶、**4** 金邊、**6** 流蘇陰影仍各自獨立。網格內的減少量來自長袍與左右袖各 3→1，以及臉／手／褲網格 4→2；每個原形態的 POSITION／NORMAL 必須按照同一頂點映射拼接，不能刪掉形態或改變其權重與時間。

**不能將 baseColorFactor 直接搬進 COLOR_0 就稱作顏色完全一致。** 已核對實際 Godot **4.7.2.stable.ed1daf0bf** 原始碼：[RenderingServer 將 ARRAY_COLOR 乘 255 後截斷為 8 位元](https://github.com/godotengine/godot/blob/ed1daf0bf/servers/rendering/rendering_server.cpp#L649)，[GLES3 以 normalized GL_UNSIGNED_BYTE 讀取](https://github.com/godotengine/godot/blob/ed1daf0bf/drivers/gles3/storage/mesh_storage.cpp#L875)；[glTF 顏色 accessor 直接讀取數值](https://github.com/godotengine/godot/blob/ed1daf0bf/modules/gltf/structures/gltf_accessor.cpp#L726)。即使 GLB 使用 float 顏色，白底材質搭配原始深色 0.007499 與 0.005182 都會存成 1/255，可能失去衣服摺痕色差。使用有界誤差分組或浮點色盤需要另外驗證，不能盲目採用普通頂點色合併。

後續若實驗，較保守的起點是第一列的原材質合併；保留原始 GLB／blend 與所有骨骼、形態和關鍵時間。生成工具目前的「逐 mesh／surface 相等」檢查，以及 `lightweight_avatar_checks.gd` 的一對一索引比較，必須改成可回溯的來源頂點／三角形映射檢查，不能直接刪除斷言；還要重新檢查走跑跳落地／坐姿／入場淡出。自訂色盤 shader 也會影響 `PlanetPlayer.begin_entry()` 目前只處理 StandardMaterial3D 的淡出流程，因此不是直接換材質即可。表內數字僅為資料結構潛力，不能換算成實際 draw calls、transform-feedback 次數或 FPS。
