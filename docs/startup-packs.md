# Web 啟動下載與延後場景建立（2026-10-07）

目前依使用者最新需求，**開啟頁面就排入全部 16 個內容包，所有內容驗證並掛載後才允許遊玩**。全景可先呈現；角色、區域細節與室內仍按使用需求建立。這已取代 10 月 1 日「接近區域才下載」的排程。沒有新增 Service Worker、PWA、Cache Storage、IndexedDB 或版本化持久快取；保留 Compatibility、單執行緒 Web、既有設定儲存、解析度、貼圖品質與原始模型。

## 下載、掛載與遊玩是三個不同階段

1. 正常 Godot Web 匯出後，`collect_web_pack_dependencies.gd` 列舉靜態依賴，加上角色、區域 catalog、室內與音樂的明確動態入口。新增但未分類的 `res://` 字串會阻止建置，避免漏包。
2. `split_web_packs.py` 驗證原 PCK 索引／MD5，保留必要 entry 原始 bytes 與資源路徑，建立啟動包及 16 個內容包。完全相同內容可共享實體 payload，不重新壓縮貼圖或修改模型。啟動包含全景、必要碰撞／入口、UI／字型、程式與資料。
3. `prepare_web_delivery.py` 將包 manifest 寫入 HTML。通過瀏覽器功能檢查後，**在 `engine.startGame()` 前排入全部內容包**；這表示開始排程，不表示引擎等下載完才啟動。`index.background.js` 使用單一活動 fetch 及 ReadableStream Promise 接續讀取，完成一包就排下一包，角色優先。啟動 PCK／WASM 同時走原啟動器及可回退 gzip 傳輸，見 [啟動壓縮傳輸](web-boot-delivery.md)。
4. 內容包網路讀取不等待 Godot `_process` 或 `requestAnimationFrame`。一般切到其他分頁時網路可繼續；回到遊戲後，引擎繼續寫檔、驗證、掛載與場景建立。這不是 Worker，也不保證瀏覽器凍結／丟棄分頁、關閉瀏覽器或系統睡眠後仍下載。單執行緒同步工作仍可能延後 JavaScript Promise 回呼。
5. `WebPacks` 在前景幀中將收到的 bytes 寫入 Web 記憶體檔案系統 `/tmp/little-world-packs`。Web 路徑先按 manifest 的確切大小配置目的檔案，避免 MEMFS 邊寫入邊擴充、反覆複製先前內容；配置失敗會顯示錯誤並停止該包。配置長度不代表已收到資料，仍另外追蹤實收與雜湊 bytes，對成功寫入的相同 bytes 增量計算 SHA-256，不再另掃整個檔案。每區塊最多 256 KiB、每幀最多 4 MiB，每個區塊後檢查 **8 ms 軟性預算**；單區塊可超過剩餘預算，目的檔配置亦可能同步耗時，因此不是硬性幀時間上限。先前 2 ms 版本在實測低幀率下每幀最多只處理一個 256 KiB 區塊，JS 收齊後仍花約 34–39 秒寫檔／驗證／掛載；8 ms 是提高啟動接收吞吐量的取捨，會占用較多前景幀時間。新版當日測得每幀最多處理 1.25 MiB，實際最大接收工作 11.2／10.3 ms；與舊候選不同日測試，不能把全部時間差歸因於預算修改。接收量、檔案長度與 SHA 均符合 manifest 後，下一幀才掛載。原生 HTTP 測試／無 JS 傳輸介面的路徑保留非阻塞 HTTPClient。
6. 世界向同一傳輸工具確認全部包，已排程請求不重抓。`all_resources_ready()` 等 16 包全部 ready 才放行漫遊與室內入口；角色及目的地節點亦須準備完成。準備中可取消進入、留在全景或切換分頁，取消不取消整批下載。錯誤提供重試，不把尚未掛載內容當成就緒。
7. 角色載入、模型建立、骨架配對分成五次操作，只在需要漫遊時進行。音樂只解碼／建立當前 stream，但音樂包已包含在啟動下載內。區域依距離、視角、不同載入／卸載門檻與延遲時間分幀建立、停用或卸載。單次 Godot load／instantiate 仍可能同步阻塞，不能宣稱傳送沒有初始化成本。
8. 桌面／手機原生版使用本地資源，不走 Web HTTP 下載；仍沿用角色延後建立、區域串流與音樂延後載入。

分包仍隔離引擎初始依賴，但**目前不再以按需網路下載減少完整可玩前的總下載量**。初次頁面資料量應計入啟動 PCK、WASM 與全部內容包；網路完成、全景首幀、全部掛載完成、角色可操作須分開記錄。本輪實際 Chrome 驗收已確認：隱藏分頁收齊 16 包，回前景全部掛載後走路及六區傳送，包請求數保持 16；詳見 [驗收記錄](background-startup-report.md)。這不代表區域節點建立或 shader 編譯沒有耗時。

## 記憶體、錯誤與卸載

- JS 內容包 buffer 配置總額上限為 **128 MiB**。建置／stamp 確認全部 16 包 bytes 總和不超過上限，讓沒有 Godot 前景幀的隱藏分頁也有容量收完整批；超出就停止建置。上限不包含 gzip 啟動檔、Response／瀏覽器內部 buffer、WASM heap、引擎資源或 GPU 記憶體，不能描述成遊戲總 RAM 上限。
- 各包交給 Godot 後釋放對應 JS buffer。PCK 檔案、掛載索引與解碼資源是另一層；Godot 沒有此處可用的 PCK 卸載流程，掛載包及虛擬檔案在頁面存活期間保留。
- 區域節點及不再引用的引擎資源依串流規則釋放；這不等於釋放網路包、所有快取或全部常駐記憶體。再次進區域重新建立必要節點，使用本頁已掛載資源。
- 網路最長等待 600 秒；非 200、大小／SHA 不符或寫入失敗不掛載，重試重新請求失敗包。HTTP 404 提示「找不到遊戲內容（HTTP 404），請重新整理後再試。」，因為舊頁面可能引用新部署已移除的 hash 包；不自動刷新。
- 沒有跨重新整理的新快取，瀏覽器既有 HTTP 快取照常運作。取消準備釋放區域 pin、返回全景並保留下載；E、跳躍、設定與室內切換受準備狀態保護。

## 在生成階段整理材質

`overview_material_normalizer.gd` 只處理離線生成的全景／永久靜態視覺副本：區域簡化視覺、`globe_base.scn`、新 `stations_base.scn`。`world.tscn` 使用後者，保留六站節點、入口 metadata、位置與碰撞；原 `stations.tscn` 不變。

- 統一開啟 StandardMaterial3D 的 vertex color albedo。原本忽略頂點色的表面，副本 RGBA 改為白色，避免啟用先前被忽略的顏色造成染色；原有效頂點色完整保留。
- 原本關閉 emission 的材質副本，改為啟用但用黑色／零能量、無 emission texture 的中性輸入；原有效發光參數保留。
- 維持原 StandardMaterial3D 光照、cull、透明、shading、diffuse／specular、位置／法線／UV／索引及包圍盒；不換成自製簡化光照 shader。骨架、形態鍵、LOD、自訂頂點通道、overlay、script、local-to-scene、next pass 等複雜／動態情況跳過。近景 MultiMesh 原始 buffer 與高細節來源不重寫。
- 原 material pool 仍只共用完整參數及匯入設定相同的資源；正規化是額外的靜態副本處理，不能混稱為完全相同材質合併。

生成記錄為 94 個正規化材質、192 個 meshes、148 個中性頂點色表面。全景仍為 1,009,913 三角形、893,393 頂點、316 個受保護地面與 384 個永久碰撞。這是結構數據；本輪已檢視 Web 畫面並記錄啟動時間，但沒有另量測最終 shader program 數量，不能把啟動時間差全部歸因於材質正規化。

Compatibility 燈光編譯容量沿用每種類型／物件 4 盞、每畫面 8 盞 positional lights；完整室內 4 Omni＋1 Spot、全景 2 Directional 保留。後者不占 positional 配額，鑑賞視窗另有 World3D。沒有改燈色、強度或室內陰影；新增燈光須重新評估容量，見 `render_light_limits_checks.gd`。[官方容量說明](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-opengl-max-lights-per-object)

Godot 4.7.2 Compatibility 的 Web shader 編譯／連結狀態查詢仍可能同步阻塞；本次沒有啟用非同步編譯、切換渲染器或增加 Web 執行緒。[引擎實作](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shader_gles3.cpp)

## 可重現建置與驗證

```powershell
python tools/build_web_release.py --godot <Godot-4.7.2-console-path>
```

模型／材質生成規則變動時加 `--rebuild-world`；需要相同版本匯出模板及可執行的 Python。流程依序為 generate（選用）、export、dependency inventory、split、隔離目錄掛載／解碼驗證、boot delivery、notices、stamp、prepare、assemble，失敗即停止，每步 log 位於 `build/web-*.log`。

生成場景先存同目錄 `.building_<pid>_*` 暫存檔並保留既有 UID；SHA 相同略過覆寫。不同時由 `atomic_replace_generated.py` 用 `os.replace` 原子替換單一檔案，占用時最多嘗試 10 次。失敗保留舊檔及暫存並回傳非零狀態；catalog 最後發布，任何場景失敗就不發布新 catalog，也不繼續匯出。這是**逐檔原子發布，並非整個生成目錄交易**；中途失敗後應重新完成生成及結構檢查才發布。

`index.packs.json` 必須與啟動 PCK 的 `res://data/web_packs.json` 及 HTML 包 metadata 一致。release stamp、Pages manifest 及組裝涵蓋全部包大小／SHA；gzip 原檔、壓縮檔及解碼結果亦驗證。GitHub workflow 仍只組裝已提交匯出檔，沒有雲端 Godot 匯出。

主要回歸工具：

- `tools/test_split_web_packs.py`、`test_web_package.py`、`test_prepare_web_delivery.py`：依賴閉包、索引／雜湊、組裝及完整下載暫存預算。
- `node --test tools/test_web_background_packs.cjs`、`node --test tools/test_web_boot_delivery.cjs`：Promise 排程、buffer 生命週期、錯誤／重試與 gzip 回退。
- `game/tests/web_pack_checks.gd`：HTTP／相依掛載、全部資源就緒門檻、增量 SHA、錯誤拒絕及重試，需 fixture 指定的 localhost HTTP 伺服器。
- `game/tests/overview_material_checks.gd`、`streaming_material_checks.gd`、`streaming_build_checks.gd`：材質／幾何保持、material pool、站點／碰撞／chunks／依賴及禁止暫存路徑。
- `game/tests/lazy_avatar_music_checks.gd` 與既有角色／世界／室內測試：延後建立、取消及玩法。
- `tools/measure_startup_packs.cjs <localhost URL> <label> --wait-all-packs`：同一 1200×800 Chrome 條件首開／再開，分開記錄下載、全景首個可回應 rAF、`contentReady` 全部掛載。`--no-gl-timing` 不包裝 WebGL／WASM API；`--shader-sources --single` 是額外診斷，不混入一般比較。
- `tools/check_background_downloads.cjs _site <label>`：自有 localhost 限速服務、實際切換分頁、下載中禁止移動／取消、隱藏期間收完 bytes、回前景掛載、六區傳送不追加包請求。
- `tools/check_web_pack_delivery.cjs`、`tools/check_performance_browser.cjs`：故障注入／重試、設定、六區互動、室內、快速鏡頭及反覆進出，須以目前入口門檻解讀結果。

本輪狀態見 [背景下載與啟動驗收](background-startup-report.md)。[10 月 1 日報告](startup-performance-report.md) 保留為歷史版本，當時按需下載及數字不代表目前行為。下載 bytes、資源數、JS heap、整個瀏覽器常駐記憶體與 GPU 記憶體不能互相替代。
