# 移動卡頓與持續負載 — 2026-10-21

本輪針對「iPhone 14 過熱、舊電腦瀏覽器即使最低檔仍在走路時卡住」。方案適用所有裝置，不依 iPhone 型號或 GPU 名稱建立白名單。無法以桌機測試保證任意裝置與瀏覽器流暢；手機長時間溫度、耗電與幀率仍需真機驗收。

## 實際修改

1. 最低檔原先只在手機瀏覽器啟用部分輕量材質，桌機最低檔仍載入整區細節。現在最低檔在所有平台、手機的低檔預設，以及自動效能保護，使用常駐烘焙世界直接漫遊，不再為走路建立整區細節節點或請求其資源包。地形、道路、建築輪廓、植物與入口仍在；窗框等裝飾減少，車輛、魚等細節演員不載入。原始美術資產保留。
2. 偵測到前景持續低於約 22 FPS、累積至少六秒的運算壓力時，即使原先選擇最高檔，也會啟用效能保護。單次停頓、背景分頁、開啟選單不構成證據。串流準備期間可觸發結構降載；保護保留到本次執行結束，避免恢復後重新灌回原負載。
3. 受限路徑活動時最高 30 FPS；靜止八秒後 15 FPS，輸入或相機移動即恢復。保留原儲存偏好與物理頻率，設定畫面分別顯示偏好及實際限制。壓力保護也會停用 MSAA，對最高／low 檔限制實際 3D 像素。手機自適應一旦因過載降解析度，本次執行不再自動升回去。
4. 低檔／效能保護的小地圖使用輕量底圖；底圖最多 5 Hz 重建，玩家位置及方向仍 20 Hz 更新。箭頭在快取底圖上使用實際位置；傳送、尺寸與品質變化立即更新，完整世界地圖仍保留完整資料。
5. 落點書房兩盞光源、大學展廳近看燈原先仍開啟即時陰影，現在遵從低檔及效能保護；光色與能量保持。落點房間的手機判斷改為進室時快取，移除每幀 JS 查詢。
6. 已卸載細節的材質快取改為弱引用，避免全球快取長期持有區域貼圖。

## 量測與限制

六入口的原生隔離比較使用相同材質、鏡頭、0.5 render scale、MSAA 關閉，不含 HUD 或角色；不能當成整個遊戲或手機幀率。

| 指標 | 原細節串流 | 烘焙漫遊 |
| --- | ---: | ---: |
| 每個入口載入的細節 chunks | 7–9 | 0 |
| Draw calls | 182–264 | 114–137 |
| 三角形提交 | 293,418–343,099 | 197,371–219,735 |
| 渲染 buffer | 約 69–72 MB | 約 55.7 MB |

完整結果與十二張圖：[constrained-streaming-rendered/report.json](../deliverables/low-end-20261021/constrained-streaming-rendered/report.json)。永久 **527 個碰撞體、24 座位與六入口**保持；396 個橋面／接近點碰撞採樣通過。catalog 的 491 不是完整執行期永久碰撞總數。

小地圖同程序 A/B/A、四秒同路線各 80 次導航更新：最終 headless 桌面底圖 CPU 相鄰 A 平均 450.82 → 50.61 ms（−88.8%），compact 176.32 → 99.17 ms（−43.8%）。這是整段路線累積的地圖 CPU 工作，不是單幀時間、全遊戲 FPS 或 GPU 效率。原生實際渲染版本亦取得一致方向的降低，來源整合後的資料以 [minimap-budget.json](../deliverables/low-end-20261021/minimap-budget.json) 及同目錄檔案為準。

## 驗證

- runtime pressure、背景、閒置及脫樹後輸入喚醒：14 項。
- 自適應圖形：62 項；圖形設定與畫面標示：91 項，含實際渲染手機直向排版。
- constrained 串流：50 項；既有串流 44 項；球體剔除 20 項；LOD／材質 1,894 項。
- 室內品質：73 項；既有落點房間 52 項。
- 地圖預算 14 項、既有快取 73 項、完整地圖 32 項、compact HUD 59 項。
- 正式 Web 兩種匯出各 20 包，desktop 438／mobile 436 個匯入資源解碼，沒有失敗。
- 分階段室內載入 17、constrained 練功區返回 32、室內往返 81、落點座椅整合 78，共 208 項回歸通過。

上述腳本測試不能替代 Safari 真機持續漫遊。正式瀏覽器操作與發布紀錄另外保存在 `deliverables/low-end-20261021/`，不將下載成功、headless 通過或手機介面模擬冒充真機效能驗收。

## 正式匯出瀏覽器操作

[Web 驗收報告](../deliverables/low-end/web-constrained-20261021/report.json) 30 項通過。使用 Windows 桌面 Chrome 155、AMD RX 5700 XT，每個正常路段約 12 秒，以真實 W/S 或 CDP 觸控操作持續往返；各路段皆記錄可見、有焦點的前景樣本。

| 路段 | 呈現節奏 | 最大幀間隔 | >100 ms 幀 |
| --- | ---: | ---: | ---: |
| 桌面最低檔行走 | 30.00 FPS | 37.7 ms | 0 |
| 同一最低檔，CDP 合成 CPU 4× 降速 | 29.54 FPS | 87.0 ms | 0 |
| 手機介面觸控行走 | 29.99 FPS | 37.7 ms | 0 |

CPU 降速不模擬舊 GPU、記憶體容量、耗電或手機溫度。手機介面因桌面 GPU 的 ETC2 格式檢測結果使用桌面資源包，這不是 iPhone Safari 或正式 Web Mobile ETC2 的真機渲染驗收。

另以 standard／偏好 60 FPS 注入 12× CPU 壓力，確認程式自行將 `runtime_pressure` 從 false 變 true，細節區塊 7 → 6 → 2 → 0。這個故障注入路段含 57 個 >100 ms 幀、最大 1,424 ms，**不作流暢度達標證據**。移除節流後的行走為 29.61 FPS、沒有 >100 ms 幀；保護維持、沒有重新載入細節。這證明自動降載與恢復行為，不能把移除節流前後的速度差歸因於優化。

三個 context 沒有 script、shader 或瀏覽器執行錯誤；報告另保留一次未歸屬 HTTP 404 與下載取消紀錄，沒有宣稱所有網路請求完全無錯。場景與手機觸控截圖已目視檢查。

## 發布與公開驗收

已部署至 [星途原網址](https://star-path-little-world.star-path-little-world.workers.dev/)，build `cf-128fa286e43bff69`，來源 `packs-7398aa350089301f`，Cloudflare version `94e7a583-2f86-48f0-a770-f336508fd643`。

- [公開內容核對](../deliverables/low-end-20261021/public-deployment.json)：10 個路徑 HTTP／完整內容 SHA256 與登入相關 headers 通過。首輪 Node IPv6 連線逾時，改 IPv4-first 重跑成功；不影響 Chrome 的公開遊戲驗收。
- [公開遊戲驗收](../deliverables/low-end-20261021/public-gameplay.json)：2026-10-21 台灣時間 22:08 完成，7／7 通過。從公開頁冷啟動，選最低檔、進入漫遊、真實 W/S 四段移動、開關完整地圖，返回後 `paused=false`、`overview=false`，保持 0 個細節 chunks／nodes。沒有 script／shader／瀏覽器執行錯誤。這是桌面 Chrome 功能驗收，不是手機長時間性能證據。
- [匯出核對](../deliverables/low-end-20261021/export-verification.json)：8 支更新腳本的 runnable payload 在 desktop／mobile 匯出一致，全部 PCK payload 驗證通過；登入 Worker、DO bindings、Firebase 設定與落點來源保持。
- 回退目錄保留 `build/cloudflare-minimap-performance-20261020/`。本輪未重建 Windows 執行檔，未操作 Git commit、push 或 staging。

交付索引：[delivery.json](../deliverables/low-end-20261021/delivery.json)。
