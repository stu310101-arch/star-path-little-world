# 交流花園：渲染與最低檔驗證

此更新保留每座留言裝置的獨立腳本、留言地址、碰撞及標籤。只將同區相同網格的靜態外觀放進 `MultiMesh`；不合併使用者資料或互動。

## 已驗證的管線

- `discussion_render_optimizer.gd`：40 個網格、200 個 surface 合成 5 個 MultiMesh、25 個 surface。原始 transform、AABB、各自 Label3D/碰撞、還原及重建共 48 項檢查通過。原美術的五區固定視角各少 35 次 draw calls，入口視角不變。初始化批次約 1.1 ms，這是本機量測。
- `discussion_avatar_prewarm.gd`：讀取既有玩家選定的 walk/jump 路徑，等待 WebPacks 就緒後背景載入並保留 PackedScene，讓共用玩家原本的同步 `load()` 命中快取。不替換角色，也不修改共用玩家。離開花園時由 LoadReaper 排空未完成工作。9 項準備、快取、取消與釋放檢查通過。
- `share_discussion_textures.py`：把 GLB 原 PNG/JPEG bytes 原封不動抽成以 SHA-256 命名的共同檔案。圖片陣列與 texture.source 索引、材質、UV/accessor、動畫/幾何 buffer bytes 保留。去掉不再引用的圖片 bufferView 後重新對齊 GLB。為外部貼圖明確啟用 mipmaps，避免新 PNG 預設不產生 mipmaps 導致遠景閃爍；保留既有 import UID 和其餘設定。7 項測試含實際裝置資產、重複執行與 mipmaps 設定驗證。
- WebPacks 分成 `discussion_common`（layout/裝置）、`discussion_garden`（標準環境）、`discussion_garden_low`（最低檔環境）。兩種環境依賴 common/avatar/shared，互不依賴。Splitter 防止最低檔間接拉進標準環境，並防止任何花園幾何流入 boot；19 項 splitter 測試通過。
- `batch_discussion_low.py`：標準版保留 62 個細分網格；最低版依 collection/材質合批為 14 個網格、106 surfaces（原先 344）。最低版 273,068 三角形完全不變，UV/COLOR/NORMAL bytes 與材質/圖片/sampler 資料保留，世界頂點誤差上限 0.00000763 m。5 項 fixture 檢查通過，實際序列化 GLB 的 14 組世界 AABB 最大邊界偏差 0.00000382 m。代價是較粗的 frustum culling 和 uint32 索引增加約 1.92 MB 源檔；最終 WebPack 仍僅 9.61 MB。工具只接受目前平面、純位移的靜態節點，遇到骨架、動畫、旋轉、縮放、morph 或未外部化的嵌入圖片即在寫入前拒絕，並保存原 GLB。另經獨立只讀審查。

## 測量方式與限制

`game/tests/discussion_performance_benchmark.gd` 必須使用真正的 Compatibility renderer，拒絕 headless。原生視窗 1280 × 800，3D scale 0.675（864 × 540，對應 native mobile 檔上限），UI 維持原尺寸。關閉 VSync、FPS 上限設 0，關閉自動畫幀後，每個 process_frame 強制一次含 swap 的真實繪製。分開記錄：

1. `frame_ms`：process_frame 的實際牆鐘間隔，包含程式處理及繪製提交。
2. `draw_submit_ms`：force_draw 呼叫耗時，不能直接當成 GPU 時間。
3. `gpu_ms`：Godot viewport GPU timestamp 量測。
4. draws、primitives、載入階段與 avatar 狀態、記憶體、模型 SHA、相機位置與畫面。

最終測試使用新版 layout 的入口與五區 controls.point，維持 65° FOV。新版縮短區域間距，因此這六點代表相同活動位置，但並非相同世界座標或完全相同構圖；場景 draws/primitives 數據反映完整新版場景，不能隔離歸因為單一程式優化。`--movement` 使用真正 CharacterBody 行走與轉鏡，單點約 3 秒，並記錄實際移動距離。保留 `--reference-cameras` 僅供未改布局時的固定構圖診斷，最終版本不使用它。

本機是 AMD Radeon RX 5700 XT，並非最低配置。原版在本機已呈現很短的穩態 frame interval；不將此推算為舊筆電、iPhone 14 或瀏覽器的玩家 FPS。桌面同時存在的工作、shader 首次編譯及檔案快取也會影響載入尖峰，因此分別報告幾何量、渲染負擔及載入分幀結構。只有「原美術只合批裝置」是相同布局和構圖的隔離比較；冷啟與暖啟不可混算百分比。

載入測試同樣取消 FPS 上限，因此 `load_ready_ms` 不是遊戲正式 30/60 FPS 限速或瀏覽器下載時的等待秒數。分幀建立需要多個畫面，實際限速會延長總等待，但可維持載入畫面回應；本報告將總準備時間與最大單幀分開列出。

## 原版基準

來源 GLB SHA-256：`08169d62e9e3023d63155dcb7ce3b2c4ec0b7a130035b766f4fbaa38f0d3a7cd`。整個 GLB 962,594 三角形、127 surfaces、12 個巨大合併網格，69,953,044 bytes。原版腳本快照及 JSON/PNG 位於 `deliverables/discussion-overhaul/performance/`。

| 固定視角 | 原版 draw calls | 只合批裝置後 | 原版提交 primitives |
|---|---:|---:|---:|
| 入口 | 160 | 160 | 622,308 |
| 大學交流 | 166 | 131 | 218,796 |
| 科系交流 | 158 | 123 | 242,044 |
| 未來就業 | 152 | 117 | 137,628 |
| 高中生發問 | 163 | 128 | 380,918 |
| 校園討論 | 153 | 118 | 246,904 |

原版暖啟移動測試總準備約 1,066 ms，最大幀 231.45 ms 在七個模型就緒後同幀建立整個場景/40 裝置；另外角色同步載入造成約 98/112 ms 兩次尖峰。首次跑曾有約 709 ms 幀，包含冷快取/編譯，不能直接拿來計算改善率。

## 最終最低檔結果（2026-10-23）

完整原始 JSON、相機起訖位置、幾何 SHA、六點截圖及比較在 `deliverables/discussion-overhaul/performance/`。資料採同一台 RX 5700 XT／原生 GL Compatibility，均取消 VSync 與 FPS 上限。兩組測試各涵蓋入口和五區，每點 3 秒；移動組各走約 11.34–11.40 m。最終兩組穩態沒有超過 50 ms 的幀，載入階段仍有下述尖峰。

| 代表性位置 | 原版／最終 draws | 原版／最終 primitives | 原版／最終 frame p95 (ms) | 原版／最終 GPU p95 (ms) |
| --- | ---: | ---: | ---: | ---: |
| 入口廣場 | 160 / 178 | 622,308 / 285,816 | 0.900 / 0.857 | 0.683 / 0.511 |
| 大學交流 | 166 / 101 | 218,796 / 75,410 | 0.757 / 0.591 | 0.439 / 0.283 |
| 科系交流 | 158 / 133 | 242,044 / 173,972 | 0.744 / 0.666 | 0.446 / 0.336 |
| 未來就業 | 152 / 100 | 137,628 / 65,126 | 0.715 / 0.593 | 0.386 / 0.273 |
| 高中生發問 | 163 / 136 | 380,918 / 193,232 | 0.756 / 0.677 | 0.456 / 0.349 |
| 校園討論 | 153 / 116 | 246,904 / 196,172 | 0.674 / 0.651 | 0.340 / 0.327 |

布局已縮短，表格不是完全相同構圖的單一優化 A/B。入口仍比原版多 18 draws，但相較新美術使用細分低版時的 319 draws，已降為 178（-44.2%）；該次細分低版入口 frame p95 為 1.231 ms，GPU p95 為 0.670 ms。合批讓該構圖提交三角形由約 198k 增至 286k，代價已反映在實際 GPU 計時中。最終移動組 frame p95 為 0.643–0.915 ms；校園移動 p95 由 0.671 增至 0.753 ms、科系由 0.708 至 0.712 ms，因此不宣稱所有移動場景均變快。

暖啟靜態組總準備 1,040 → 1,023 ms、最大幀 238.48 → 73.40 ms；移動組總準備 1,066 → 988 ms、最大幀 231.45 → 66.37 ms。背景 avatar 準備的主執行緒單步最高 0.040／0.034 ms；原本同步讀取角色的約 88／105 ms 工作已移至背景，角色後續處理仍另計。場景第一次顯示的 GPU 資源／shader 準備仍可能停頓：中途首次低版測到 508 ms，最終數據是在畫面驗收後的暖快取，不視為冷啟動保證。

最終 CPU static memory 約 90.5 MB（原版約 86.1–86.4 MB），Godot 報告 GPU memory 約 137.1 MB（原基準未記此欄位，不能比較百分比）。最低環境 273,068 三角形，較原環境 962,594 少 71.6%；此數字不含 40 座裝置、角色、UI 與另加的 128 三角形鋼構補件。最低實載六個 GLB 與 21 張唯一來源貼圖合計約 27.0 MB；這與 PCK 壓縮大小、GPU 記憶體不同。

最終 Web Mobile 匯出中，`discussion_garden_low` 9,609,256 bytes，標準環境 17,336,816 bytes，common 310,420 bytes，shared 4,875,356 bytes；最低版不依賴標準環境。從空目錄只掛 boot + avatar/shared/common/low，29 項環境／裝置／layout／貼圖皆成功解碼，`standard_available=false`，沒有 UID 警告或失敗。這是本機匯出與封包隔離驗證，未部署，也未在 iPhone 或最低硬體做瀏覽器長時間熱測。

上述 GPU benchmark 完成後，`discussion_garden.gd`／`discussion_navigation.gd` 增加按需導航的合法起點避障；未啟用導航時沒有新增繪圖或運算路徑，本輪沒有重跑 GPU benchmark。已重新收集相依並完成最新 Web Mobile export／split／空目錄 closure；確認兩支最新編譯腳本及 remap 都進入 boot PCK，與完整匯出的 bytes 相同。29 個模型／來源貼圖 SHA 與已量測版本一致，discussion_common／標準環境／最低環境／shared 四包 SHA 也與前次完全一致。記錄在 `web-final-refresh.json`；目前 boot PCK SHA-256 為 `84f26220dc2a826b977317ebf0649f47b92e3d6ad109bc6a3aa0d834dfc242a1`。

## 重現命令

用已安裝的 Godot 4.7.2 執行：

```text
godot --path game --script res://tests/discussion_performance_benchmark.gd -- --report res://../deliverables/discussion-overhaul/performance/final-minimum.json
godot --path game --script res://tests/discussion_performance_benchmark.gd -- --movement --report res://../deliverables/discussion-overhaul/performance/final-minimum-movement.json
godot --headless --path game --script res://tests/discussion_render_optimizer_checks.gd
godot --headless --path game --script res://tests/discussion_avatar_prewarm_checks.gd
godot --headless --path game --script res://tests/discussion_texture_mipmap_checks.gd -- res://../deliverables/discussion-overhaul/performance/texture-mipmaps.json
python tools/test_share_discussion_textures.py
python tools/test_split_web_packs.py
python tools/test_batch_discussion_low.py
python tools/audit_discussion_runtime_assets.py
python tools/summarize_discussion_benchmark.py
```

Web 匯出後，`discussion_pack_closure_checks.gd` 從空目錄以 boot PCK 開始，只掛最低檔依賴，再讀入環境、裝置、layout 和貼圖；必須得到 `standard_available: false`、`failures: []`。它不借用開發專案中的資產補漏。
