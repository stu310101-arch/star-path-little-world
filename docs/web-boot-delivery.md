# 可回復的 Web 啟動壓縮傳輸（2026-10-07）

`tools/prepare_web_delivery.py` 在正常 Godot 匯出及 PCK 分包後，額外建立 gzip 版啟動 PCK／WASM。原始 `index.pck`、`index.wasm` 保留。2026-10-10 起另對固定版本 JS loader 的單一 scissor 布林查詢做等價替換；WASM 不變。`index.delivery.json` 記錄原始及壓縮 bytes／SHA-256，HTML 內有相同 manifest，發布 stamp 會驗證两者及 gzip 解碼結果。Pages 打包會收錄啟動檔與有收益的內容包 gzip 檔。最新量測與修改細節見 [網頁優化報告](web-optimization.md)。

這是應用程式讀取 `.gz` 檔再解壓，伺服器不必設定 `Content-Encoding`，不使用 Service Worker、Cache Storage、IndexedDB 或其他新增持久快取。支援 gzip `DecompressionStream` 及 WebCrypto 的瀏覽器才使用此路徑；不支援則照原方式載入。

`index.delivery.js` 只攔截啟動器的兩個同來源、完全相同 URL、沒有自訂 options 的 `fetch(string)` 呼叫，隨即還原 `fetch`；後續角色／區域、其他來源、query、Request 物件及其他 HTTP method 均不受影響。兩個檔案仍平行處理。404、連線錯誤、逾時、gzip 損壞、解碼大小或 SHA 不符，會改抓該檔的原始 URL。

解碼以 manifest 大小預先配置一個有上限的輸出陣列。gzip 解碼器檢查 footer 的 CRC／大小，另外以 WebCrypto 核對完整解碼 SHA-256。只有全部成功才將完成的 Response 交給 Godot。這是刻意的取捨：4.7.2 匯出啟動器的 body-stream 及 WASM Promise 錯誤沒有完整向外傳遞，直接交付未完成的解壓串流可能在中途網路失敗時卡住。這裡保留原啟動器，以完整驗證及回退維持相容性。

因此它會增加解壓／雜湊 CPU 工作、暫時的解碼 buffer，以及瀏覽器 Response／WebCrypto 可能產生的副本；WASM 無法再與網路下載重疊編譯。不能把壓縮率當作實際啟動秒數或 RAM 改善。低階裝置、網路中斷、瀏覽器回退及實際啟動時間須分開驗收。

目前 `_site` 候選版本 **`packs-d07f707a87666ad1`**（2026-10-07 09:47:56 UTC 匯出，含 8 ms 內容接收預算）的 gzip level 6 發布檔案大小如下。數值來自同版本 `index.delivery.json`，不是瀏覽器傳輸時間；Web 驗收結果見 [背景下載報告](background-startup-report.md)：

| 檔案 | 原始 bytes | gzip bytes |
| --- | ---: | ---: |
| 啟動 PCK | 35,604,120 | 32,542,325 |
| WASM | 39,514,754 | 10,114,291 |
| 合計 | 75,118,874 | 42,656,616 |

這是相對同版本未壓縮 body 減少約 **43.21%**。另外 16 個內容包共 **101,286,296 B** 也在啟動時下載，因此完整 PCK＋WASM 為 **143,942,912 B**，不能只用上表 42.66 MB 表示完整遊戲首次下載量；HTML／JS 等小檔另計。如果原 CDN 已有 gzip／Brotli，外網新增收益會較小或沒有。此數字沒有重新請求 GitHub 網站，不代表線上目前缺少壓縮。

建置只接受已審閱的 Godot 4.7.2 單執行緒 loader SHA-256 與 format-4 PCK。更換引擎／模板時會停止，必須先審阅 API 再更新版本約束。`window.planetBootDelivery` 及 `planet-boot-delivery` 事件提供下載、驗證、完成／回退階段，供 HTML 顯示及量測使用；解碼中的 bytes 可由狀態取樣，不代表網路 wire bytes。

啟動畫面另有繁體中文狀態文字，分開顯示「下載啟動檔」、「驗證啟動檔」與「啟動引擎與準備畫面」。解碼階段最多每 250ms 取樣更新進度，明確標示「已解壓」的 bytes，不冒充壓縮後網路傳输量；完成或回退時交回原啟動器的進度回呼。進度覆蓋層移除或顯示錯誤後會停止取樣。這改善等待期間的資訊，不會自行縮短同步引擎／繪圖初始化。

另外複製的 `index.background.js` 是內容包的分頁生命週期傳輸工具，其實作位於 `tools/web_background_packs.js`；與兩個 gzip 啟動檔分開驗證。Godot 在前景幀中把已收到的內容包 bytes 寫入預先配置的 Web MEMFS 檔案，增量驗證，收齊並驗證後才掛載。每區塊最多 256 KiB、每幀最多 4 MiB，區塊後檢查 8 ms 軟性預算，允許單區塊超時；這與 gzip 啟動檔的解碼輸出陣列是兩種不同的暫存，皆不構成跨重新整理的快取。

啟動所需的延後包會在 HTML 通過瀏覽器功能檢查後、`engine.startGame()` 之前排入下載，不必等世界第一幀；標示 `startup: false` 的室內包仍按需載入。HTML 內的包 metadata 必須與 `index.packs.json` 相同，後續 Godot 重複提出請求不會重抓已排程的包。建置與 stamp 必須確認啟動包 bytes 總和不超過 128 MiB，讓隱藏分頁在沒有 Godot 消耗畫面幀時也能收完。2026-10-10 起最多同時下載兩包，按解壓後大小預留同一個 128 MiB 上限；有超過 5% 壓縮收益時才建立選用 gzip 版本。若未來增加內容超過上限，建置會停止；必須重新評估暫存與排程，不能靜默造成等待。

`tools/measure_startup_packs.cjs --no-gl-timing` 使用事件及 Resource Timing，不包裝 WebGL／WASM API。另加 `--wait-all-packs` 才等待 `planetAllResourcesReady`，並記錄 `planet-content-ready` 的 `contentReady` 時間；預設仍在首次畫面回呼後兩秒取樣，供舊量測對照。全景出現與全部資源準備完成是不同時間點。

快速回歸：`node --test tools/test_web_boot_delivery.cjs`、`python -m unittest discover -s tools -p test_prepare_web_delivery.py -v`、`python -m unittest discover -s tools -p test_web_package.py -v`。這些是資料與流程測試，不能取代實際 Web 啟動與背景分頁驗收。
