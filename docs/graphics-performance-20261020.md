# 畫質效能清理技術驗收 — 2026-10-20

幾何、設定、原生恢復流程及桌面 Web 畫質切換已有下列證據。本文不代表已完成手機真機效能或溫度驗收；發布版本記錄見文末。

## 範圍與畫質約束

本輪移除不可見的匯出殘留、無效或埋藏面，將保守的地球遮擋剔除與精確空間分塊套用到所有畫質，並減少真正進入背景時的無用工作。**沒有下調既有解析度、AA、陰影、材質表現或可見物件密度設定。**

這不表示所有畫質本來就使用相同解析度或全部開啟 AA：各 profile 的既有差異、balanced 的自適應解析度，以及既有 mobile 材質／LOD 行為仍保留。本輪沒有以降低預設畫質、縮減可見植被、取消陰影或關閉 AA 來取得改善。

材質並非所有屬性都逐位不變：通過檢查的不透明表面啟用背面剔除。原有顏色、貼圖、法線、粗糙度等正面外觀保留；profile 切換須恢復原材質引用。碰撞、座椅與工作桌互動、可編輯 Blender 來源均保留。

## 背景省工與帳號視窗

實作位於 [graphics_settings.gd](../game/scripts/graphics_settings.gd)。

- Web 以實際 `document.hidden`／`visibilitychange` 判斷隱藏；Windows 以真正的 `WINDOW_MODE_MINIMIZED` 判斷。單純失去焦點或將焦點移到 iframe，不會停止 3D 繪製。
- 真正隱藏時暫停 RenderingServer render loop，將實際 `Engine.max_fps` 暫時限制到最多 10。使用者選擇的 `frame_limit`、畫質、AA、3D scale 與物理頻率不因此改寫。
- 恢復時還原進入背景前的 render-loop 狀態，套用最新的使用者 FPS 選擇，並重新暖機效能採樣。若進入背景前另有機制停用 render loop，恢復時不擅自開啟。
- 全世界與室內帳號視窗都排除自適應效能採樣，避免開啟網頁兩分鐘後，將低遊戲負載誤判為可提高解析度。現有有邊框的網頁介面仍露出 3D 世界，因此保持背景正常繪製。
- 設定服務在室外世界暫離 SceneTree、玩家進入室內期間仍持續運作；真正銷毀時解除瀏覽器 listener 並恢復執行狀態。

`get_state()` 提供使用者 FPS 與實際 FPS、hidden、render-loop 狀態，以及最多八筆含單調時間的背景切換紀錄。紀錄可於返回前景後讀取，避免瀏覽器停止 rAF 時的舊 telemetry 快照被當成即時狀態；沒有增加逐幀 JavaScript 呼叫。

已驗證：目前 headless 報告 25 項、零失敗；原生視窗紀錄 26 項、零失敗，包含實際最小化／恢復及恢復後 `frame_post_draw` 可繼續。原生紀錄早於兩項 telemetry 歷史檢查，不能將兩者合併聲稱為同一輪原生 28 項通過。真實 Web 瀏覽器的切換分頁流程仍待新版匯出驗證。

證據：[政策與生命週期報告](../deliverables/performance-20261020/background-graphics-checks.json)、[headless 紀錄](../deliverables/performance-20261020/background-graphics-headless.log)、[原生紀錄](../deliverables/performance-20261020/background-graphics-native.log)。

## 世界匯出殘留清理

[streaming_export_cleanup.gd](../game/tools/streaming_export_cleanup.gd) 只處理明確標記為過時來源副本、且本地 `visible=false` 的節點。允許的 metadata 僅為 `world_architecture_source_preserved` 與 `street_furniture_source_preserved`；帶腳本的候選根節點保留。一般暫時隱藏的遊戲節點不屬於清理範圍。

[streaming_world_builder.gd](../game/tools/streaming_world_builder.gd) 先擷取永久碰撞，再處理匯出副本。原始完整 generated 場景不回寫，清理輸出限於 streaming 資產。

| 指標 | 清理前 | 清理後 |
| --- | ---: | ---: |
| Streaming chunks | 93 | 89 |
| 全景三角形 | 881,848 | 881,848 |
| 永久碰撞 bodies | 491 | 491 |
| 移除的明確隱藏來源節點 | — | 222 |
| 移除的來源副本實例三角形 | — | 113,078 |

這 113,078 個三角形原本已不可見，主要減少匯出資產、載入、記憶體與節點管理負擔，**不能解讀為每一幀少畫 113,078 個可見三角形，也不能直接換算 FPS**。原有 overview 植被 LOD、mobile LOD、精確分塊的數量與保留三角形數，在前後 catalog 中相同。

證據：[baseline catalog](../deliverables/render-budget/baseline-catalog.json)、[目前 catalog](../game/generated/streaming/catalog.json)、[獨立檢查報告](../deliverables/performance-20261020/streaming-cleanup-review.json)。專用 fixture 五項斷言通過；過程發現的 PrimitiveMesh 統計 API 問題已修正，重跑零失敗。報告記錄目前來源雜湊供比對，沒有把缺少先前快照的檔案宣稱為已做前後雜湊驗證。

## 所有畫質的保守遮擋剔除

實作位於 [mobile_render_quality.gd](../game/scripts/mobile_render_quality.gd) 與 [district_streaming.gd](../game/scripts/district_streaming.gd)。名稱保留既有命名，但本輪的精確分塊與地球遮擋判定適用所有 profile／平台，不依賴 mobile 材質模式。

精確分塊保留原三角形、頂點屬性、材質與 shadow/layer 設定；漫遊時子分塊取代原 batch，總覽時恢復原 batch，避免兩份幾何重複繪製。遮擋只移除完全位於不透明地球背面的候選，跨越切線或不確定的包圍範圍仍保留。相機移動使用保守眼點快取；移動界線及相反側相機恢復已有檢查。

剔除保持父節點 `visible`，避免父網格被遮擋時連帶隱藏仍在前方的子節點。無投影物件可設 `layers=0`；原本投影的物件保留 layer 並改為 `SHADOWS_ONLY`。雙面陰影物件保留原模式，不以無法等價表達的模式替換。串流載入在套用美術後註冊，卸載前解除，並防護失效 weak reference。原本隱藏或受腳本獨立驅動的分支不覆寫。

目前遮擋檢查 20 項通過，包括 mobile → standard 材質引用恢復、父子可見性、陰影、總覽互斥、卸載與相機換側。獨立幾何 oracle 檢查 572 個被剔除範圍、36,608 條取樣射線，未發現錯誤遮擋；這是該取樣集的結果，不是所有可能相機位置的數學完備證明。原有 mobile 品質檢查報告目前為 1,892 項、零失敗。

世界表面 shader 的背面剔除保留原正面著色運算。[winding audit](../deliverables/render-budget/surface-winding.json) 記錄的 `world_surface` 樣本為 966,644 個正向、0 個反向、380 個退化三角形；此統計不代表本輪另刪除這 380 個面。

朝向檢查本身不證明網格封閉。另核對目前可到達視角：標牌為厚盒、正反文字分開；護欄梁有側面與端蓋；薄木棧道高度約 0.104 m、櫻花橋最高約 0.216 m，均低於正常漫遊相機下界約 0.564 m，且玩家的地面檢查不允許走入橋下水域。目前實際地形資料也低於該相機下界；若未來增高山坡、開放游泳／地下鏡頭，必須重新檢查世界表面雙面需求，不能將此次驗證沿用到新內容。

證據：[地球遮擋報告](../deliverables/render-budget/planet-visibility-checks.json)、[獨立檢查紀錄](../deliverables/performance-20261020/planet-visibility-review.log)、[品質檢查報告](../deliverables/mobile-render/quality-checks.json)。

## 室內幾何與背面清理

完整規則與重建方式見 [indoor-geometry-optimization.md](indoor-geometry-optimization.md)。

| 執行時資產 | 原三角形 | 清理後 | 移除 |
| --- | ---: | ---: | ---: |
| 落點書房 | 111,744 | 111,602 | 142 |
| 訓練室啟動版 | 64,517 | 57,160 | 7,357 |
| 訓練室完整細節版 | 131,513 | 123,436 | 8,077 |
| 大學中庭 | 286,892 | 286,892 | 0 |
| 大學展廳外殼 | 306,549 | 306,549 | 0 |
| 大學展示套件 | 259,392 | 259,382 | 10 |
| 大學特色書本 | 648 | 648 | 0 |

訓練室啟動版與完整細節版是替換關係，兩者合計 15,434 個三角形的減少是資產總量，不能當成同一幀節省量。各版本分別減少約 11.40% 與 6.14%。

只刪除精確零面積、同 surface 同索引同繞序的重複面，以及通過明確模型名稱、閉合性與地板高度防護的埋藏面。小而有效的面、屬性接縫、反向面與不同材質間的重疊面保留。背面剔除只套用到檢查合格的不透明閉合表面；玻璃、植被、頭髮、水面、螢幕與光學效果排除。Furina 角色及其頭髮材質未改。

訓練室重建逐位元比較原始頂點／法線／UV／切線 buffer，只修改索引與合格材質的 culling；GLB 也保留原屬性與影像資料。這不是焊接或一般減面。再次 dry run 沒有額外刪除或 culling 變更。

既有室內驗收記錄：八項規則測試、五個 GLB 成功重新匯入、21 個實際室內渲染視角與八個座位視角已檢視，未發現本輪清理造成的破洞；座椅整合 86 項通過。這些檢查使用 Godot 4.7.2／Windows Compatibility／RX 5700 XT，並非手機效能測試。

GLB 為保留原資料而附加新索引區段，來源檔案可能增加；例如書房約 12.38 MB → 12.65 MB。本輪不宣稱所有下載檔案變小。背面剔除也不會將三角形計數直接減半，其收益須由相同場景的實際繪製成本評估。

證據：[室內清理報告](../deliverables/graphics-performance/indoor-optimization.json)、[訓練室清理報告](../deliverables/graphics-performance/training-optimization.json)、[室內最終 dry run](../deliverables/graphics-performance/indoor-dry-run.json)、[訓練室最終 dry run](../deliverables/graphics-performance/training-dry-run.json)、[21 視角報告](../deliverables/graphics-performance/indoor-visual/report.json)、[座位截圖目錄](../deliverables/admissions-room/seats/)。

## 使用者設定保留

[graphics-settings-tests.json](../deliverables/performance/graphics-settings-tests.json) 85 項、零失敗。設定持久化仍寫入使用者選擇的 `msaa_enabled`、`frame_limit`、`quality_profile`，以及原有 mobile policy version。暫時的背景 FPS、hidden 與 render-loop 狀態不寫入偏好檔。

驗收時必須同時比較「選擇值」與「實際執行值」：例如選擇 60 FPS、真正隱藏時實際上限 10、回到前景恢復 60，屬於預期行為；不能將背景實際上限顯示成玩家改選了 10 FPS。balanced 原有自適應行為也不能誤記為本輪新增的畫質下調。

## 固定 GPU 前後比較

Windows／Godot 4.7.2 GL Compatibility／AMD RX 5700 XT，1280×800 原生視窗。每個固定視角等待載入並暖機兩秒、採樣 2.5 秒。standard、low、mobile 關閉 VSync 與幀率上限；mobile 是桌面上啟用手機政策，不是手機硬體。各組前後的實際像素尺寸、MSAA 設定一致。完整指標與逐張圖像審查見 [comparison-review.json](../deliverables/render-budget/comparison-review.json)。

| standard 可比視角 | primitives 前 → 後 | draw calls 前 → 後 | GPU 中位數 ms 前 → 後 |
| --- | ---: | ---: | ---: |
| overview | 1,056,140 → 996,122 | 1,040 → 945 | 1.138 → 1.005 |
| waterfront_0 | 1,003,920 → 848,542 | 1,030 → 1,021 | 1.158 → 1.168 |
| waterfront_1 | 1,005,832 → 827,078 | 1,145 → 1,144 | 1.251 → 1.246 |
| waterfront_2 | 953,612 → 724,709 | 967 → 956 | 1.060 → 1.029 |
| waterfront_3 | 1,127,435 → 884,623 | 1,463 → 1,399 | 1.767 → 1.439 |

四個有效水岸視角的 primitive 提交減少 15.48%～24.00%；溪谷視角 GPU 中位數減少約 18.6%。其他視角可能持平，不能將單一最佳結果寫成所有視角的提升。`primitives` 是 Godot 渲染提交計數，包含渲染 passes／UI，不能直接叫做模型本身的精確三角面數。

standard 的 `waterfront_4`、`waterfront_5` 基準被帳號載入視窗干擾，其中前者還改變鏡頭方向，**兩組全部排除比較**。low、mobile 各七組畫面可比；42 張前後截圖逐張審查，未見新增地面破洞、物件缺失或陰影消失。

low 六個水岸視角的 primitive 提交減少約 24.5%～37.5%，但這輪 GPU 中位數增加 0.105～0.164 ms；mobile 原本已有剔除，部分視角幾何相同或略增，GPU 中位數增加 0.098～0.164 ms。這些資料不能支持「每檔幀率都提升」。

另以相同程序、固定 water0 相機、暫停模擬的 A/B/A/B/A 測量，B 暫時將所有 `SHADOWS_ONLY` 候選的 layers 設為 0，A 恢復。兩檔的 draw／primitive 各階段完全一致；low 的 GPU 中位數在 1.309～1.524 ms 間波動，B 沒有一致優勢；mobile 的 A/B 差異也沒有一致方向。因此未基於此假說修改產品，保留投影正確性。這排除了該測試中的明顯固定收益，不能反過來證明先前回退的根因；不同時間的桌面量測仍有環境與時脈限制。見 [隔離測試](../deliverables/render-budget/caster-cost-isolation/report.json)。

balanced 只列為功能測試：原有自適應套用設定時會恢復 90 FPS 的測試上限，因此最後兩個視角約 11.1 ms 不能當成 uncapped GPU 吞吐量。相機剔除 CPU 測試共 240 幀、1,099 個候選，僅 18 次重算，headless 呼叫中位數 0 µs、p95 約 0.83 ms；也是桌面測量。

## 桌面 Web 功能驗收

新匯出包透過 Chrome 真實 UI 切換 standard → mobile → balanced → low → standard。最後恢復 3D scale 1、2× MSAA，所有檔的 planet culling 均開啟；角色實際移動約 0.835 m，未記錄 console error／warning。見 [web-acceptance.json](../deliverables/render-budget/web-acceptance.json) 與 [最高檔畫面](../deliverables/render-budget/web-standard.png)。

此次自動化環境開新分頁、點擊正常 `target=_blank` 連結均未產生 `document.hidden` 事件，因此沒有把空的事件歷史誤判成背景驗收通過。保留 [本機手動測試伺服器](../tools/serve_graphics_qa.py)，只對 `?performance&background-qa` 加入真實分頁連結；未注入假的 visibility 事件，測試 UI 不會發布。原生實際最小化／恢復證據仍有效。

## 舊手機策略與尚未驗證的界線

通用策略是讓每個畫質都少做看不到的工作：離線移除冗餘面與過時來源、按空間精確拆分原網格、保守保留可見及投影內容、對靜止相機使用安全快取，並在真正背景時停止繪製。這些措施能減少不必要負擔，但不能消除最高畫質本來的像素、AA、陰影與著色成本，也不能保證任意舊手機都維持指定 FPS 或不發熱。

目前沒有手機真機的持續 FPS、溫度、降頻、耗電證據。模擬 mobile profile、桌面縮小視窗或桌面 Web 瀏覽器都不能替代真機驗收。尚待：

1. 新版 Web 實際切換分頁／返回，確認 `background_events` 的 `document.hidden` 轉換、render-loop 與實際 FPS 恢復；iframe 取得焦點時不得誤停畫面。重複室內外切換後再驗證。
2. 在具名手機、OS 與瀏覽器記錄版本、DPR、畫質、AA、亮度、充電與環境條件，以相同路線連續操作至少 10–15 分鐘，涵蓋漫遊、快轉、三種室內、工作桌及返回。
3. 記錄持續 frame-time 分布與卡頓、前後同視角外觀，以及設備可提供的溫度／thermal state／電量資料。沒有可讀取的溫度感測資料時應標記未測，不能用觸感或 FPS 推論「不過熱」。

在上述資料完成前，可確認的是本文件列出的清理、安全邊界與恢復檢查；手機全畫質流暢度與長時間熱狀態維持未驗證。

## 發布與回退

2026-10-20 已發布至 [星途](https://star-path-little-world.star-path-little-world.workers.dev/)：

- Cloudflare build `cf-bf1907d93039df49`，來源 `packs-93e6276151a31be6`，Worker version `ca78cabe-a836-45cb-8180-293784d385da`。
- `build/cloudflare-performance-20261020/`：378 檔、552,466,158 bytes，9 個分片原檔重組 SHA-256 全通過；桌面／手機各 20 個 Web pack、438／436 個匯入資源通過。正式 10 個入口／資源的 HTTP、內容 SHA-256 與登入相關 headers 通過，見 [public-deployment.json](../deliverables/render-budget/public-deployment.json)。
- Admissions 網站來源 SHA-256 `e43ff216d5bc8516f0335b75deaa13a668ee4ed5cf78272747768ba5c8ab14c0`、登入 Worker SHA-256 `3f76a1b3d545f3853ec650565ab57d5a0e5c2357f08543a435e4c8500954a70a` 均與上一版一致。
- Windows 新包 `build/StarPath-Windows-Performance-20261020.zip`：280,123,936 bytes、22 檔；CRC、逐檔 SHA-256、release.json 一致性通過。ZIP SHA-256 `ad3ae9343820f79eba0f72e5a0da1716539ce610abd5558ebf2aeda1d5523839`。見 [套件驗證](../deliverables/render-budget/windows-package.json) 與 [效能執行資源核對](../deliverables/render-budget/windows-performance-export.json)。

正式 Chrome 已啟動並顯示新 build、全檔剔除與背景狀態欄位，沒有 console error／warning，見 [正式瀏覽器證據](../deliverables/render-budget/public-browser.json)。該正式 origin 的既有偏好為 standard、MSAA 關閉，驗收保留此偏好；這與本機獨立 origin 的 2× MSAA 切換測試是不同驗收條件。所有測試分頁、原生 GPU 程序與本機測試伺服器均已關閉，避免留下額外渲染負擔。

上一版 `build/cloudflare-admissions-studio-final-20261020/` 及 `build/StarPath-Windows-20261020.zip` 保留。若回退網站，使用該目錄的 `wrangler.jsonc`，保留登入 Worker、兩個 Durable Object bindings 與既有 migration；不可用不含登入服務的舊純靜態設定覆蓋。沒有 Git 提交、推送或 staging 操作。
