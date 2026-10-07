# 室內分階段載入與資產副本

本輪保留原始 `WordKing_TrainingRoom.blend`、`WordKing_TrainingRoom_Game.blend`、原始 GLB／圖片與 `layout.json`。室內來源 GLB 的 SHA-256 為 `6437899552ceb817192ea089b4576b44e6e15eac8d1d62a85326acd16c213633`；生成器只讀取來源，另輸出遊戲副本。

## 啟動與進門

啟動包包含 `scenes/training_room.tscn`、原始配置、簡易 `generated/training_room/light.scn`，並不建立室內場景。完整訓練室包不再列入戶外啟動下載或漫遊就緒門檻。

進門先建立簡易房間、原有固定碰撞、出生點、出口與家具互動；之後才由室內請求 `generated/training_room/detail_catalog.json` 所屬的完整包。素材驗證掛載完成後，逐一載入獨立 Mesh 資源，下一幀才套用。替換既有 MeshInstance3D 的 mesh 屬性，保留節點識別、位置、比例、櫃門樞紐、座位與書籍參照。

下載、準備、錯誤狀態均顯示於 HUD。下載期間可移動、互動或按「返回世界」；失敗保留簡易房間並提供重試。繪畫鑑賞讀取當前材質的圖片，簡易版本也可使用，不會嘗試同步載入尚未下載的原始圖檔。

每間房間自行輪詢掛載狀態，不持有跨場景 await 回呼；離開時釋放待套用 Mesh、清單、節點索引與室內場景，遲到的包不會套用至戶外或其他房間。低配模式保留戶外世界狀態，但在室內每幀卸載一個戶外細節 chunk。

## 資產成本與取捨

| 資產 | 三角形 | 節點／資源策略 |
| --- | ---: | --- |
| 原始室內 | 275,739 | 152 個 Mesh 節點，原始 GLB 17,401,164 bytes |
| 簡易室內 | 60,261 | 保留 152 個具名 Mesh 節點，`light.scn` 1,312,604 bytes |
| 完整遊戲副本 | 132,473 | 152 個獨立 Mesh + 25 個共用材質資源，合計 4,828,043 bytes，另有清單 18,907 bytes |

主要減少沙發與電競椅的密集曲面；建築接縫、地板、入口、投影裝置與書籍保留幾何，碰撞完全沿用原始 layout。完整副本也經過模型優化，並非只延後下載原始高面數模型。簡易版家具曲面較粗糙、少量細線裝飾不完整，準備完成後換上詳細副本。

室內只有一張繪畫圖片：遊戲完整副本限制最長邊 1024 px，簡易副本 256 px；原始高解析圖片保留。1024 px 大於現有 512 px 鑑賞視窗，避免載入遠大於顯示尺寸的圖片。低配同時關閉室內天花板燈即時陰影，物件鑑賞視窗改 256 px；主視圖繼承全域 3D 解析度、MSAA 與幀率設定。

## 記憶體生命週期

下載工作、掛載 PCK、解碼的 Mesh／材質與場景節點是不同生命週期。`queue_free()` 室內僅釋放場景與失去引用的視覺資源，不代表 WebAssembly 記憶體立即縮小，也不代表已掛載的 PCK 已卸載。

Godot 的公開 [ProjectSettings API](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-method-load-resource-pack) 提供載入包，沒有逐包卸載 API；[4.7 PackedData 原始碼](https://raw.githubusercontent.com/godotengine/godot/4.7-stable/core/io/file_access_pack.h)保留資源路徑索引，[FileAccessPack](https://raw.githubusercontent.com/godotengine/godot/4.7-stable/core/io/file_access_pack.cpp)在後續讀取時仍會開啟原包檔。因此掛載後的包檔保留至分頁／程式結束，不刪除仍被索引的包檔。再次進入可使用已掛載資料，不必重新下載；本輪沒有新增跨重新整理的持久快取。

## 已執行驗證

- `staged_room_checks.gd`：17 項通過，涵蓋進門前零室內請求、簡易畫面／碰撞／互動、失敗重試、穩定節點／變換、離開後遲到結果、再次進入重用。使用受控包狀態的原生測試；不等同真實網路驗證。
- 原有 `check_training_props.gd`：86 項通過。圖片檢查由舊檔名斷言改為與原圖縮至 16×16 後比較像素內容，允許材質內嵌圖片；最終輸出沒有 Godot 錯誤或警告。
- 實際 NVIDIA MX330／OpenGL Compatibility 畫面檢視：簡易／完整沙發、電競椅、入口與房間佈置。截圖位於 `deliverables/low-memory/room-*.png`。截圖使用未更換角色前的中間版，完整最終版本的 Web／原生測試以總報告為準。
- 最終室內副本的 headless 單項資源載入最大值約 9.05 ms；這不是 GPU 幀時間或 4GB 裝置效能證明。早期原尺寸繪畫版本在 MX330 有約 85 ms 的單次準備耗時，已據此限制遊戲副本圖片尺寸；最終瀏覽器／原生渲染結果需以整體測試報告為準。

### 最終 Web 室內生命週期實測

2026-10-07 20:43:14–20:46:10（Asia/Taipei），Chrome 154.0.8037.98、全新瀏覽器內容、1200×800、真實本機 HTTP 伺服器；最終凍結版本 `packs-7bd866e6416621ee`（source SHA-256 `7bd866e6416621eeebe332c9fe9fd921c9e95a4313901600535e7cd08049e225`）的 HTML／JS／WASM／PCK 在測試前後都通過發布識別及 SHA-256 核對。`deliverables/low-memory/low-final-staged-room-7bd866-v2.json` 共 **29 項通過、零非預期錯誤**：

- 戶外啟動完成後，完整室內 HTTP 請求仍是零。
- 首次進門故意回應 HTTP 503，簡易房間仍有角色、152 個具名模型節點與可用互動；重試按鈕使用真實滑鼠點擊。
- 重試的 HTTP 回應在 64 KiB 後暫停；角色可以用 W 移動、點擊返回。返回戶外後才放行剩餘資料，未重新建立室內場景。
- 收到的完整室內包 **4,863,392 bytes**，SHA-256 `2921631c6807839af5543d1f9acae12515d9b59490484b112bd0ca112aed0e45` 與 manifest 完全一致。三次再次進入沒有額外室內下載；總共只有故意失敗一次和成功重試一次。
- 詳細模型替換前後，152 個實際節點的識別與變換摘要相同；完整室內繼承低配模式。
- 在簡易版本等待下載、完整版本已就緒兩種狀態，都實際切至 1440×900 並恢復 1200×800，角色位置變化小於 5 cm、場景不變且沒有引擎錯誤。
- 每次縮放後清除舊觀察並重新記錄實際 WebGL viewport 呼叫：3D 均為 **1152×720**；1440×900 視窗的 UI 為 **1440×900**，1200×800 視窗則依原始比例保留黑邊、UI 為 **1200×750**。MSAA 關閉、上限 30 FPS；不是只檢查低配旗標或設定值。
- 完整素材已掛載的那次進入，從室內 `_ready` 開始到完整版就緒 **16.895 秒**（包含簡易房間與互動初始化，非純模型準備耗時），單次準備操作最大 **11.1 ms**；期間可以遊玩簡易版本。這不是網路下載時間，也不是穩定 FPS 或 4GB 電腦達標證明。

已檢視本次最終 Web 的簡易／完整畫面（`low-final-staged-room-7bd866-v2-resize-light-restored.png`、`low-final-staged-room-7bd866-v2-detail-ready.png`）：房間佈置、書櫃、電競椅、投影裝置與角色仍可辨識。低配關閉 MSAA 後，細金屬線條與家具邊緣鋸齒可見；簡易窗簾和曲面較粗，完整模型套用後恢復較完整輪廓。快速返回兩次的戶外節點／資源快照為 1227／678、1399／680，戶外細節當時完成程度不同，這組數字不能證明資源無增長，也不能當成長時間記憶體洩漏測試或瀏覽器 RSS。兩次返回後均無待處理下載工作；掛載 PCK 的生命週期限制仍如上所述。

此測試以真實 HTTP 503 與分段暫停回應驗證生命週期；HTTP `no-store`、人為等待與重試時間不能當作一般網路效能數字。遊戲操作全由鍵盤／滑鼠執行，JavaScript 僅讀取 opt-in 遙測及觀察 WebGL viewport，不寫入引擎狀態。測試結束後已關閉所屬瀏覽器與本機伺服器。

### 中間版紀錄與測試工具修正

- `packs-ffe690a7da341c41` 的 `low-final-staged-room.json` 曾通過 21 項功能檢查，但當時未驗證實際 3D 緩衝尺寸，不能當成最終低配解析度證明。
- `packs-b5d3f7b94e1d8bec` 的 `low-final-staged-room-v3.json` 通過 29 項，含實際 GL 720p；此版本早於最後戶外 CPU 優化，保留作中間紀錄，不將其耗時套到最終版本。該版 v2 的失敗來自測試把 CSS 焦點邊框誤計為畫布解析度，已改用實體 backing store 與原始比例計算。
- 最終版第一次執行的 `low-final-staged-room-7bd866.json` 在啟動後設定面板點擊未生效時停止，未完成室內流程。測試工具增加等待新一輪 HUD 排版遙測，並確認面板開啟才點選畫質；同一份凍結匯出重測時，設定面板第一次點擊即成功。上述修正僅限測試工具，沒有更改遊戲程式或測試中的引擎狀態。

生成流程由 `tools/build_training_room_runtime.py`（全新 Blender 背景程序）及 `game/tools/build_training_room_runtime.gd`（Godot）重現。`art/TrainingRoom/runtime_exports/` 為既有忽略規則下的中間副本；發布使用 `game/generated/training_room/` 的生成內容。
