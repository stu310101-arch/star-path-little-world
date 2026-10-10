# 網頁遊玩與載入優化（2026-10-10）

此版本針對同一台電腦原生 Godot 順暢、Web 走路掉幀的差異，保留操作、速度、碰撞、世界內容、原始材質及動畫時間。原始 `.blend` 與角色 GLB 保留；Web 使用可重建的匯出副本。

## 修改

- **角色繪製**：`tools/build_web_avatar.py` 按相同材質將 39 個 surface 合併成 11 個。衣服形態鍵使用原 LINEAR 曲線的原始時間點，將同步姿態合併；相鄰時間點最多啟用兩個全身姿態，避免單純合併網格反而累加所有局部形態鍵。保留全部頂點、三角形、材質值、骨架、權重及骨骼動畫；沒有減面、改材質或降低採樣頻率。`runtime_web/derivation.json` 留存來源 SHA、映射及驗證結果。原生平台繼續使用 `runtime/`。
- **Web 呈現**：只對 SHA 已固定的 Godot 4.7.2 單執行緒 loader，將一次 `gl.getParameter(SCISSOR_TEST)` 改成等價的 `gl.isEnabled(SCISSOR_TEST)`。保留 scissor 狀態還原；沒有跨幀快取 WebGL 狀態。未知模板拒絕修改，重複建置保持一致，WASM 不變。
- **資源封裝**：對匯出的 RSCC/Zstandard 資源重新分塊壓縮，小資源 64 KiB、大資源 1 MiB。逐個資源核對解壓後 bytes，只有確實縮小才替換；不改來源及 Godot import cache。223 個候選資源由 125,556,847 B 降至 96,293,724 B。這是相對「合併角色後、重新壓縮前」的數字，不能冒充相對線上舊版的下載改善。
- **內容下載**：最多兩個並行請求；仍按解壓後完整大小預留 128 MiB 暫存上限。只有 gzip 額外節省超過 5% 的包才使用串流解壓；不支援時使用原始包，gzip HTTP 失敗也可回退原始包。解壓內容繼續經 Godot 原有長度／SHA 驗證後掛載。每幀寫入預算、按需室內載入與頁面生命週期限制保持原樣。
- **幀率**：Web 新設定及「恢復預設」為 60 FPS，原生仍 30；已有的 30／60／90 設定繼續保留。原來低配／標準畫質與 MSAA 選項不變。

## 量測方法與邊界

Chrome 155、AMD Radeon RX 5700 XT、ANGLE D3D11、1920×1080 瀏覽器視窗。比較時兩版都指定 60 FPS、MSAA 關；使用實際鍵鼠輸入，等待下載與場景準備後，分別量測站立、直線走路、拖曳轉視角。每條件重複三次、每次四秒。低配的 3D 像素為 1152×720，標準為 1728×1080。

`check_movement_smoothing.cjs` 觀測有 WebGL 提交的 requestAnimationFrame 間隔；這是提交頻率，並非 GPU 完成時間或螢幕實際顯示幀。Godot HUD 的瞬時 FPS 不作唯一依據。量測不與其他遊戲測試同時執行。

| 低配，同設定、同 localhost 環境 | 原版 | 優化版 |
| --- | ---: | ---: |
| 站立提交頻率 | 60.0 FPS | 60.0 FPS |
| 走路提交頻率（三次合併） | 38.8 FPS | 55.7 FPS |
| 走路 P95 幀間隔 | 33.4 ms | 24.9 ms |
| 轉視角提交頻率 | 60.1 FPS | 60.0 FPS |

走路平均提升約 **43.4%**；優化後三次走路為 56.6／52.7／57.7 FPS。兩版皆只有第一個走路樣本含區域串流操作，後兩次沒有。站立、轉視角與走路所有測量區間均無超過 100 ms 的提交間隔。另測優化版標準畫質、MSAA 關：走路約 60.0 FPS，P95 19.8 ms；未把它和低配舊版當成同條件比較。

完整原始資料位於 `deliverables/movement-smoothing/final-fullhd-rx5700.json`；同一台 localhost 原版對照為 `original-local-fullhd-rx5700.json`。低配與標準使用不同內部解析度，兩者數字不能當成單一變數實驗。這些結果限於此機器、瀏覽器及所測路線，沒有證明所有裝置或初次冷啟動完全沒有停頓。

## 實際交付大小

下表以舊版下載副本與新建置 manifest 計算，包含選用 gzip 的 body 大小，沒有重複計算保留的原始回退檔。HTML／JS、HTTP 標頭及另外開啟的電腦小遊戲不在內。

| PCK＋WASM body | 舊版 | 優化版 |
| --- | ---: | ---: |
| 啟動檔＋全部啟動內容包 | 112,905,199 B | 104,940,944 B |
| 加上按需室內包 | 117,768,591 B | 109,722,400 B |
| 角色包（已包含在上述總計） | 38,410,516 B | 36,805,020 B |

整體 body 減少約 6.8%；不是首次載入秒數改善百分比。合併角色的未壓縮資料更大；低配重複走路前的 Godot render-buffer 計數由約 119.9 MiB 增至 164.4–164.6 MiB。這是用約 45 MiB 繪圖緩衝資料換取較少提交／變形工作；沒有宣稱所有記憶體指標都改善。Godot buffer 計數、節點數與 JS heap 均不能替代整個 GPU 顯存或瀏覽器 RSS 量測。

## 重建與驗證

需要 Godot **4.7.2** 與相符匯出模板、Python（含 NumPy）、Node **24+**（Zstandard），瀏覽器測試另需 Chrome 及 Playwright。

```powershell
python tools/build_web_release.py --godot <Godot-console.exe> --node <node.exe> --local-only
python -m unittest discover -s tools -p 'test_*.py' -v
node --test tools/test_web_background_packs.cjs tools/test_web_boot_delivery.cjs tools/test_training_computer_games.cjs tools/test_recompress_web_resources.cjs
node tools/check_movement_smoothing.cjs --self-test
```

建置會重新產生 Web 角色、匯出、重壓縮、分包，並讓 Godot 從空目錄讀取全部 17 包，確認 322 個匯入資源及 332 個來源資源可解碼，再驗證、stamp 並組成 `_site`。`--local-only` 不改 `deploy/github-pages`。

Pages 打包納入 `packs/*.pck.gz`，並檢查 release stamp 的每個檔案都已收錄；組裝後再核對所有 bytes／SHA，缺檔不能以 HTTP 回退掩蓋。最終本機版為 `packs-60ebceee28b43f74`。效能量測版 `packs-aa5602d129834d7d` 到最終版的遊戲／JS／WASM／內容包 hash 全部相同；後續修正是打包收錄、來源指紋與測試等待條件，證据見 `deliverables/web-optimization/final-build-equivalence.json`。

```powershell
python -m http.server 8766 --bind 127.0.0.1 --directory _site
node tools/check_movement_smoothing.cjs http://127.0.0.1:8766/ final-fullhd-rx5700 _site/index.release.json --profile=both --repeats=3 --duration=4000 --viewport=1920x1080 --visual-smoke
node tools/check_performance_browser.cjs http://127.0.0.1:8766/ web-optimized-functional _site/index.release.json
node tools/check_training_computer_browser.cjs http://127.0.0.1:8766/
node tools/check_staged_room_browser.cjs _site web-optimized-room
```

角色驗證需真正的繪圖後端：`Godot-console.exe --path game --script res://tests/web_avatar_checks.gd --rendering-method gl_compatibility`。它在同樣鏡頭、光線、時間點比較 7 個動作共 42 個姿態的骨架並輸出前後圖片，另需檢視實际 Web 跑步、跳躍與恢復走路畫面。序列截圖可能錯過短暫姿態，不能聲稱已逐幀排除所有衣物穿插。

本機結果：42 個姿態骨架檢查全部通過，84 張前後圖的最大單色通道差為 4/255，任何一張的平均通道差不超過 0.00227/255；沒有差異超過 8/255 的像素。原生的畫面設定、延後角色／音樂、動畫採樣、串流、鏡頭、34 張座椅、室內分階段載入及分包測試通過。`web_pack_checks.gd` 另需先在 repo 根目錄執行 `python -m http.server 8947 --bind 127.0.0.1`，提供其 HTTP fixture。

Python 封裝測試 28 項、Node 傳輸／解壓／小遊戲測試 49 項通過。最終 Web 完整功能路線 53 項及電腦圍棋 11 項通過，包括六個入口、跨區步行、相機、設定保存、不同視窗大小與三次進出卸載。三次卸載後節點／物件／資源計數分別維持 1171／3567／631，不將此視為完整 RAM 證明。

實際 HTTP 503 → 重試 → 暫停回應 body → 室內行走及返回 → 室外完成下載 → 再次進入的 29 項檢查也通過。內容包 SHA、152 個室內網格身份／變換、掛載重用、重複進出不額外下載都經驗證。報告為 `deliverables/low-memory/web-optimized-room.json`。

發布前應以同一組打包檔案更新 Pages，不能只替换 PCK、JS 或 HTML 其中之一。此工作建立本機候選版，發布狀態另以 GitHub Pages 實際版本為準。
