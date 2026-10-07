# 背景下載與啟動驗收（2026-10-07）

此文件記錄最新「全部內容先下載、場景仍延後建立」版本。**`packs-d07f707a87666ad1` 已重新匯出，通過真實隱藏分頁下載、取消、重試、六區互動與傳送、室內及設定回歸。** 同日 localhost 單次比較中，新 context 的全景首個可回應 rAF 由 29.46 秒降至 22.19 秒，再開為 3.20／3.39 秒；新版全部包掛載完成為 31.80／12.38 秒。這不足以證明穩定加速或所有裝置皆可正常運行，實測遊玩幀率仍偏低。下方保留中間候選診斷並與最終版本分列；10 月 1 日 `startup-performance-report.md` 的按需下載結果維持為歷史記錄。

## 本輪變更

- HTML 在 Godot 引擎啟動前排入全部 16 個內容包，透過非 rAF 驅動的 fetch／stream Promise 下載；全景可先顯示，全部驗證掛載完成後才放行遊玩。傳送時仍可能建立目的地節點，正常不再需要抓新包。
- JS 內容包暫存上限為 128 MiB，建置檢查全部內容能否容納。這不是遊戲總 RAM 上限，也不是跨重新整理的持久快取；隱藏分頁下載不涵蓋分頁凍結／丟棄或系統睡眠。
- Godot 寫檔時增量計算 SHA-256，避免下載後再掃整個檔案；每區塊 256 KiB、每幀最多 4 MiB，區塊間檢查 **8 ms 軟性預算**。單區塊可超過剩餘預算，因此不是硬性幀時間保證。驗證完成下一幀才掛載，掛載與區域節點卸載分開處理。
- Web 寫入前按 manifest 的確切大小配置 MEMFS 目的檔，避免反覆擴充／複製已有內容。配置失敗可重試；已配置長度不能冒充下載完成，實收 bytes、雜湊 bytes 及 SHA 仍須全部符合。減少重複配置的理由來自程式路徑，未做單獨隔離此修改的時間／記憶體 A/B 測試；配置本身也可能同步耗時。
- 啟動 PCK／WASM 新增可回退 gzip 傳輸及等待階段文字，保留原 Godot loader 與未壓縮檔。減少 bytes 的同時增加解壓、驗證與暫存成本，不能用壓縮率當作秒數收益。
- 生成的全景／永久靜態副本統一中性 vertex color／emission 路徑，保留原 StandardMaterial3D 光照及幾何。目的為減少必要 shader 變體；畫面已檢視，最終版本 program 數未另量測，不能把啟動時間差全部歸因於此。
- 生成內容採暫存兄弟檔、保留 UID、逐檔原子替換／有限重試、catalog 最後發布，失敗停止匯出；不是整個目錄交易。

完整設計、限制與指令見 [startup-packs.md](startup-packs.md) 及 [web-boot-delivery.md](web-boot-delivery.md)。未更換部署平台、渲染器、Web 執行緒、解析度或貼圖品質；未新增第五項持久快取。

## 本輪匯出與資源大小

已匯出並組裝到 `_site` 的最終候選版本為 **`packs-d07f707a87666ad1`**，建立時間 2026-10-07 09:47:56 UTC；來源基準 commit 為 `b5a2d1e65d8d924a3543e41b21d92cf4026f8c1f`，來源 SHA-256 為 `d07f707a87666ad1dff98c5d3dc68e0e68710ab16e603330fe64dfa35abaf2f4`。此版本包含 MEMFS 預配置及 8 ms 接收預算。版本、各檔案大小與 SHA 見 `_site/index.release.json`；下表讀取同次匯出的 `index.delivery.json`、`index.packs.json`。

| 本輪內容 | 原始檔 bytes | 使用 gzip 啟動傳輸時的檔案 bytes |
| --- | ---: | ---: |
| 啟動 PCK | 35,604,120 | 32,542,325 |
| WASM | 39,514,754 | 10,114,291 |
| 啟動 PCK＋WASM 小計 | **75,118,874** | **42,656,616** |
| 全部 16 個內容包 | 101,286,296 | 101,286,296 |
| 全部 PCK＋WASM 合計 | **176,405,170** | **143,942,912** |

本次 gzip 啟動檔比本次原始啟動檔減少 **43.21%**。相同「完整遊戲資源」口徑下，上一版 `b5a2d1e` 的全部 PCK 136,690,352 B 加 WASM 39,514,754 B，合計 **176,205,106 B**；本次採 gzip 路徑合計 **143,942,912 B**，少 **32,262,194 B（18.31%）**。這是發布檔案大小的計算，不是瀏覽器實際 wire bytes、下載秒數或啟動速度結論；HTML、JS、manifest、授權檔未包含在小計內。

舊版不會在啟動時下載全部內容，所以不能把上述完整資源比較寫成「新頁面首次流量比舊首景少 18.31%」。新版依需求一開始下載全部內容。若 gzip 不支援或失敗而回退，須使用原檔；失敗後已傳輸的 bytes 還可能額外增加流量。伺服器若已有 Content-Encoding，檔案大小亦不等於實際網路流量。JS 內容包總量 101,286,296 B 低於 128 MiB 上限，但不能推論遊戲總 RAM 或其他裝置表現。

## 已完成的生成與結構驗證

| 驗證 | 結果 | 證據 |
| --- | --- | --- |
| 最終完整生成 | exit 0；86 chunks，94 材質／192 meshes 正規化 | `deliverables/startup-packs/overview-material-generation.log` |
| 材質與幾何副本保持 | 154／154 | `deliverables/startup-packs/overview-material-checks.log` |
| 原有 material pool | 36／36 | `deliverables/startup-packs/streaming-material-checks.log` |
| 原子檔案發布 | 3／3，包括失敗保留及路徑限制 | `deliverables/startup-packs/atomic-publication-checks.log` |
| 重新生成後結構 | 2790／2790；86 chunks、105 dependencies | `deliverables/startup-packs/streaming-build-normalization-checks.log` |
| WebPacks 原生下載／掛載回歸 | 2026-10-07：101／101，包括接收預算、預配置輔助路徑、接收／雜湊完整性、掛載中重複請求保護及掛載失敗回退 | `build/web-pack-budget-checks.log`；原生測試不代表真實 Web MEMFS 效能 |
| 隔離目錄完整包掛載／解碼 | 17 packs（啟動包＋16 內容包）、146 imports、154 source resources；failures 為空 | `build/web-validate-packs.log` |
| Pages 打包／組裝驗證 | 啟動 PCK 35,604,120 B，44 個其他檔案；prepare／assemble 成功 | `build/web-prepare.log`、`build/web-assemble.log` |
| 背景下載及 gzip JavaScript 測試 | 30／30 | 2026-10-05 `node --test tools/test_web_background_packs.cjs tools/test_web_boot_delivery.cjs` 命令結果；未另存 log |
| gzip 建置及 Pages 打包 Python 測試 | 6／6、2／2 | 2026-10-05 `test_prepare_web_delivery.py`、`test_web_package.py` 命令結果；未另存 log |
| 最終組裝版本檔案核對 | `packs-d07f707a87666ad1` 的 26 個 release 檔案大小／SHA-256 全部符合；三份 release manifest bytes 完全一致；目前來源指紋與 manifest 的 `d07f707a…` 完全相符 | 2026-10-07 獨立命令核對 `_site`、`build/web`、`deploy/github-pages/files` 及來源指紋；未另存 log |
| 最終候選 Web 故障／重試 | 11／11；預期 503 注入外無錯誤，真實按鈕重試成功，全部 16 包掛載後可漫遊 | `deliverables/startup-packs/final-delivery.json`，`passed=true`、`errors=[]`，完成於 2026-10-07 09:56:43 UTC |
| 最終候選真實背景分頁／全區傳送 | 19／19；隱藏期間收完 16 包，回前景掛載成功，走路及六區傳送沒有追加包請求 | `deliverables/startup-packs/final-background-verified.json`，`passed=true`、`errors=[]`，完成於 2026-10-07 10:00:12 UTC |
| 最終候選完整玩法／設定回歸 | 39／39；六區互動、室內進出、跨區走路、快速鏡頭、全景旋轉縮放、三次進出，以及 MSAA／30／60／90 設定與重新整理保存 | `deliverables/performance/final-functional.json`，`passed=true`、`errors=[]`，完成於 2026-10-07 10:06:11 UTC |

全景結構維持 1,009,913 三角形、893,393 頂點、316 個受保護地面及 384 個永久碰撞。檢查涵蓋六站節點／metadata、碰撞與生成相依，不含 `.building_` 暫存路徑。這些檢查不能取代 Web 畫面、操作、shader program 或 GPU／CPU 負擔量測。

## 已量測的修改前基準與中間候選

兩份記錄均在 Windows localhost、Chrome **154.0.8037.58** 無介面模式、**1200×800** 視窗、Intel Iris Xe／ANGLE Direct3D11 執行，採初始全景、沒有操作路線，使用被動探針而沒有包裝 WebGL／WASM API。每版本各測新 context 一次及同 context 再開一次；未清除 OS／驅動快取，也未隔離系統暖機與其他負載。

`deliverables/startup-packs/round2-before-passive.json` 自 2026-10-03 08:50:20 UTC 開始，測的是 `build/startup-round2-before` 的舊版 **`packs-c674b2a47ed31edd`**。它保留舊有按需下載排程，`waitAllPacks=false`，所以沒有完整可玩前的全部包掛載比較值。

| 自導航起算 | 新 context | 同 context 再次開啟 |
| --- | ---: | ---: |
| 啟動 PCK／WASM 最後一筆 body 完成 | 1.0405 s | 0.6248 s |
| 世界 ready 事件 | 9.5307 s | 7.2903 s |
| 世界 ready 後首個 rAF | 42.1823 s | 19.2135 s |

`deliverables/startup-packs/round2-after-passive.json` 自 2026-10-03 08:53:23 UTC 開始，測的是已被取代的中間候選 **`packs-b40e50186599378f`**，尚未包含 MEMFS 預配置；它已啟用全部初始下載，`waitAllPacks=true`。這是診斷記錄，**不是目前最終候選的驗收結果**。

| 自導航起算 | 新 context | 同 context 再次開啟 |
| --- | ---: | ---: |
| gzip 啟動 PCK／WASM 最後一筆 body 完成 | 2.3087 s | 8.7598 s |
| 世界 ready 事件 | 11.0082 s | 32.1987 s |
| 世界 ready 後首個 rAF | 32.7838 s | 99.7628 s |
| 全部內容驗證／掛載 `contentReady` | 136.3390 s | 176.7502 s |

上述 body 完成時間取自 Resource Timing；它不包含後續解壓／驗證與引擎初始化。中間候選的再開遠慢於首開，不能用首開一筆改善就宣稱穩定加速。舊版與中間候選都屬被動探針，但初始下載排程及等待終點不同，不能拿舊版首景與新版全部掛載當同一指標比較。`contentReady` 也不等於角色已建立、已完成操作驗收。

兩份記錄各只有一筆 `/favicon.ico` HTTP 404，沒有記錄到引擎錯誤。兩版本再開時啟動 PCK／WASM 仍有完整 body 傳輸記錄，因此這些「再開」不代表 PCK／WASM 全部命中 HTTP 快取。各條件只測一次，不能替代重複測量；rAF 是回呼可執行的代理指標，不是精確呈現時間、可操作時間或 GPU 工作完成時間。

### 2 ms 接收預算的診斷

`deliverables/startup-packs/final-preallocated-passive.json` 於 2026-10-05 15:09:45 UTC 開始，記錄中間候選 **`packs-f5871a13083729ea`**，已有 MEMFS 預配置，但仍使用 2 ms 預算。環境為 localhost、Chrome **154.0.8037.93**、1200×800、Intel Iris Xe／ANGLE Direct3D11，被動探針、初始全景；瀏覽器版本已不同於 10 月 3 日，不能視為嚴格控制條件的跨日速度比較。

| 自導航起算／診斷值 | 新 context | 同 context 再次開啟 |
| --- | ---: | ---: |
| 世界 ready 後首個 rAF | 49.5711 s | 36.6814 s |
| JS 收完全部內容包 bytes | 56.7738 s | 43.2232 s |
| 全部內容驗證／掛載 `contentReady` | 90.8078 s | 82.5795 s |
| 內容 bytes 收齊到全部掛載 | 34.0340 s | 39.3563 s |
| 實際單幀最大接收量 | 256 KiB | 256 KiB |
| 單幀接收工作最大耗時 | 13.9 ms | 133.6 ms |

兩次都只做到每幀一個區塊，取樣時全景約 13／11 FPS。**後段等待並非全部來自網路**：JS 已收齊資料，引擎仍需數十秒寫檔／雜湊／掛載。新候選將區塊間預算提高到 8 ms，以提高低幀率時的接收吞吐量；代價是每個前景幀可花較多時間處理資料，新版結果見下節。表中的 JS 收齊時間也可能受同步引擎工作延後 Promise 回呼影響，不能單獨當作網路頻寬結果。

## 最終版本同日啟動比較

`final-baseline-passive.json` 於 2026-10-07 10:06:31 UTC 開始，接著 `final-release-passive.json` 於 10:07:12 UTC 開始，兩者皆已完成。條件為同機 localhost、Chrome **154.0.8037.98** 無介面模式、1200×800、初始全景、`?performance`、被動探針，沒有包裝 WebGL／WASM API。每版本各一筆新 context 及同 context 再開，依序執行；未清除 OS／驅動快取，亦未隔離其他系統負載。

| 自導航起算 | 舊版新 context | 新版新 context | 舊版再開 | 新版再開 |
| --- | ---: | ---: | ---: | ---: |
| 啟動 PCK／WASM 最後一筆 body 完成 | 0.6364 s | 1.2003 s | 0.4952 s | 0.8290 s |
| 世界 ready 事件 | 4.9455 s | 6.9699 s | 2.1155 s | 2.5880 s |
| 世界 ready 後首個 rAF | 29.4588 s | 22.1911 s | 3.2045 s | 3.3877 s |
| 啟動 body 完成到首個 rAF | 28.8224 s | 20.9908 s | 2.7093 s | 2.5587 s |
| 全部 16 包 JS 收齊 | 不適用 | 26.1939 s | 不適用 | 7.4747 s |
| 全部包驗證／掛載 `contentReady` | 未量測 | 31.7980 s | 未量測 | 12.3769 s |
| 全部包收齊到掛載完成 | 未量測 | 5.6041 s | 未量測 | 4.9022 s |

舊版為 `packs-c674b2a47ed31edd`，保留按需下載，不具目前全部包就緒終點；新版為 `packs-d07f707a87666ad1`。新 context 全景 rAF 在本次少 7.27 秒，再開則多 0.18 秒，只有一組樣本，不能保證固定改善。當日新版 8 ms 接收預算下，實際每幀最多處理 **1,310,720 B（1.25 MiB）**，接收工作最大 **11.2／10.3 ms**；舊有 `f587` 的跨日 2 ms 診斷可解釋修改動機，不能當作只改預算的嚴格因果比較。

新版啟動 gzip PCK／WASM body 分別為 **32,542,325／10,114,291 B**；Resource Timing 的單檔下載 duration 為首開 **0.9313／0.3512 秒**，再開 **0.7768／0.1637 秒**。CDP 記錄全部 PCK＋WASM 的傳輸量（含 HTTP 標頭）為 **143,946,606／134,910,408 B**；再開只有五個音樂包命中快取，啟動 gzip 仍完整傳輸，因此不能稱為全資源快取命中的載入時間。內容包在 JavaScript 收齊時間前可能受同步引擎工作延後回呼，不能將 26.19 秒全部當成純網路等待；啟動 gzip 還有解壓／SHA 與引擎編譯成本。

兩份原始記錄各有一筆 favicon 404，沒有引擎錯誤。rAF 是回呼可執行代理值，`contentReady` 是包驗證與掛載終點；兩者都不是精確的首個像素呈現或角色可操作時間。後者已透過操作測試驗證，但沒有單獨精確計時。

## 最終版本功能與量測範圍

版本為上列 **`packs-d07f707a87666ad1`**。下表僅接受這次匯出的實測，前節中間候選數字不填入本表。已完成操作測試使用 Windows localhost、Chrome **154.0.8037.98**、1200×800 瀏覽器視窗（Godot 邏輯 viewport 1440×900）：

- 故障／重試：首次角色請求注入 503、Tab 準備、移動／跳躍阻擋、Esc 返回總覽、真實按鈕重試。
- 隱藏分頁：一般有介面 Chrome、全新暫存 profile、同視窗真實第二分頁，沒有強制 focus／取消背景節流的啟動旗標。localhost 內容包每 20 ms 傳 64 KiB、`no-store`，角色包在第一塊後停住，等 Tab／Esc 與真實隱藏狀態穩定後放行。完成下載後切回遊戲、掛載、走路並傳送六區。

上述為功能驗收，不能使用故障／人工限速路線的時間代替一般啟動速度比較。

| 項目 | 本輪結果 | 狀態／原因 |
| --- | --- | --- |
| PCK／WASM、全部 16 包 bytes 與下載時間 | 已量測 | 發布檔案大小、Resource Timing、CDP 及 JS 收齊時間分列於前節；不是公網速度測試 |
| 首開／再開全景 rAF、全部掛載、後段處理時間 | 已量測 | 見同日比較表；可操作時間未精確計時，只有真實操作通過 |
| shader program／compile 呼叫數及查詢牆鐘 | 未量測 | 最終版使用被動探針，沒有加入 WebGL 包裝診斷 |
| 隱藏分頁完成全部 HTTP bytes | 已驗收 | `final-background-verified.json`：16 包共 101,286,296 B 全部客戶端 EOF，逐包伺服器大小／SHA 符合；引擎 telemetry ticks 前後皆 36,247 |
| 準備中禁止移動、取消、失敗重試 | 已驗收 | `final-delivery.json`：11／11，角色重試只追加一次請求，啟動包不重抓；全景初始完整區域 chunks 為 0 |
| 回前景掛載、六區傳送不新增包請求 | 已驗收 | 回前景全部 16 包 ready；走路及 counseling／admissions／recommendations／universities／life／wordking 傳送前後請求數皆為 16 |
| 全景／近景外觀及既有互動 | 已驗收 | `final-functional.json`：39／39；全景、漫遊、室內與 390 px 設定畫面已檢視；390 px 是視窗測試，並非實機手機測試 |
| 全景／近景 FPS、幀時間、切換卡頓 | 已取樣，非前後受控比較 | 同版本完整路線數據見下節；實測仍有低幀率與同步建立尖峰 |
| JS 暫存峰值 | 已量測 | 隱藏測試峰值 101,286,296 B；回前景掛載後為 0；未超過 128 MiB 上限，這不是完整瀏覽器 RAM |
| 引擎／節點與反覆進出 | 已取樣，不能證明長期無洩漏 | 三次卸載節點 1253／1256／1253、資源 805／806／805，完整 chunks 每次歸零；JS heap 同期仍上升，詳見下節 |
| 引擎靜態記憶體、完整瀏覽器 RSS | 未量測 | Web `MEMORY_STATIC` 回傳 0，監測值不可用，不是 RAM 為零；沒有全程序 RSS 證據 |
| GPU time、完整 CPU profile、其他裝置 | 未量測 | 尚無對應 profiler／其他裝置證據 |

需區分「新瀏覽器 context」與「完全清除 OS／驅動快取」，以及完整 body 的 HTTP 200 與真正快取命中。WebGL API 牆鐘不是獨立 GPU 編譯時間；同步 load／instantiate 尖峰也不能誤算為網路等待。

### 遊玩路線取樣與仍存在的成本

`deliverables/performance/final-functional.json` 使用同一 Chrome／視窗，透過真實鍵鼠及唯讀 telemetry 驗收。MSAA／幀率選項測試後恢復原始預設（MSAA 開、上限 60 FPS），以下路線值取自恢復後；功能檢查通過不等於達到 60 FPS。機器為 Intel Core i7-1165G7、約 8 GB RAM（8,075,584 KiB）、Intel Iris Xe／ANGLE，當日起始可用實體記憶體約 481,176 KiB，未隔離其他系統負載。

| 取樣位置 | FPS | 平均／最大幀 ms | process／physics ms | draw calls | 遮擋候選／判定 μs | ready districts／chunks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| counseling | 11 | 77.04／95.83 | 99.3／1.2 | 372 | 2／600 | 1／28 |
| admissions | 10 | 85.10／108.20 | 110.1／0.6 | 365 | 2／400 | 1／28 |
| recommendations | 22 | 40.88／56.06 | 57.6／1.9 | 368 | 1／500 | 2／31 |
| universities | 17 | 56.84／66.67 | 62.3／0.7 | 337 | 0／400 | 2／42 |
| life | 16 | 61.18／63.50 | 66.1／0.9 | 377 | 0／400 | 2／36 |
| wordking | 10 | 108.83／125.53 | 125.6／4.2 | 321 | 1／800 | 1／24 |
| 快速鏡頭 | 14 | 71.38／83.10 | 74.3／0.6 | 375 | 2／500 | 1／28 |
| 跨區走路 | 6 | 125.73／139.77 | 151.7／6.6 | 614 | 4／400 | 2／24 |
| 全景旋轉縮放後 | 12 | 81.70／84.23 | 94.8／0.3 | 505 | 已停用 | 0／0 |

FPS、幀時間與 process／physics 使用不同監測窗口，不能互相倒算或相加；process 為 Godot `TIME_PROCESS`，不是純 GDScript CPU profile。遮擋耗時為該次快照最後判定，非整段路線最大值；全景留下的最後候選數／耗時不能算成正在運行。完整路線記錄到單次區域串流操作最大 **137.7 ms**，角色建立操作最大 **303.6 ms**，所以全部下載完成仍不代表後續零卡頓。室內進出已操作驗證，但世界 telemetry 在室內不能作為獨立室內 FPS 數據。

三次同區進入再返回全景後，完整 chunks／細節節點均回到 0，節點為 **1253／1256／1253**、資源 **805／806／805**，沒有逐次累積。相同卸載階段的 JS heap used 為 **213,401,624／215,437,432／220,589,450 B**，仍增加約 7.19 MB；未強制 GC、未測更長循環，因此不能宣稱整體記憶體已穩定或不存在洩漏。渲染 buffer monitor 為 141,705,126／141,711,618／141,705,126 B，也不等於 GPU 總記憶體。Web 靜態記憶體 monitor 回傳 0 而不可用；JS heap、WASM buffer、PCK 暫存、GPU 及整個瀏覽器 RSS 必須分別解讀。

`final-background.json` 保留為未通過的測試記錄，不列入成功驗收：客戶端已收完 16 包且伺服器 bytes／SHA 相符，但工具將完整 body 後的 CDP `ERR_ABORTED` 判成失敗；最後一站操作又因視窗被遮蔽而使引擎停幀逾時。測試工具改用客戶端 EOF 加伺服器完整性記錄確認下載，並在需要操作時確認遊戲回到前景；這些修正沒有更動正式遊戲。修正後重新完整執行的 `final-background-verified.json` 為上列 19／19 通過結果。

本輪只做 localhost 驗收；GitHub 依使用者指示提交推送，不做線上網站／Actions 效能驗證，也沒有 Cloudflare 比較測試。平台傳輸差異不能由 localhost 結果推斷。
