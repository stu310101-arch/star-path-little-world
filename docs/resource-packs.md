# 低階／滿血資源包

首次開啟先選擇資源包；網頁在下載 WASM 與主要遊戲內容前顯示選擇。選擇保存在目前裝置，之後從主頁「遊戲設定 → 切換材質包」下載另一包並重新啟動。切換前可勾選是否保留原包，也可刪除已保留的另一包。共用檔案不會隨另一包刪除，帳號、成績與探索進度也不屬於資源快取。

Windows 發行資料夾包含可離線安裝的 `packs/`；第一次只把選中的包安裝到 Godot 使用者資料夾。請保留整份發行資料夾，才能重新安裝另一包。瀏覽器則透過網路下載選中的包，並由 Service Worker 保留已驗證的檔案；儲存空間不足時會顯示無法保留的訊息，不會把偏好設定當成「已下載」的證據。

第一站輔導室使用唯一一套高階美術，獨立於兩種主包，進入該室時才取得。`shared_on_demand` 記錄其完整依賴；已取得的輔導室資源不會因刪除另一種主包而遺失。本次未製作輔導室低階材質包，詳見 [輔導室與帳號量表](counseling-interest-20261024.md)。只修改這類共用室內時，Web 建置可加 `--reuse-low-resources` 沿用已存在的完整低階資產。

## 低階內容

以原有美術為基礎降低密度與細節，保留各區特色；不把場景換成純色方塊。

- 戶外裝飾建物由 48 棟減為 30 棟；抽樣保留 108 棵原有造型的樹，刪去密集重複植栽。櫻花林整區移除，小地圖與傳送選項同步更新。
- 船舶由 7 艘減為 2 艘、魚由 102 尾減為 21 尾；保留原本運動路徑，降低更新頻率。海面由 29,621 三角面減為 9,408，半徑不變，岸邊行走碰撞保留。
- 一般色彩貼圖縮至最長邊 256，閱讀畫作保留 512；保留 UV、透明葉片與原有材質色彩，減少法線／粗糙度貼圖負擔。適合減面的靜態模型以保留約一半面數為目標，地面與必要輪廓保留。
- 大學館保留原本展廳與展台，各校最多四個代表模型；138 筆資料、搜尋、閱讀、導覽、收藏和探索進度保留。
- 交流區保留原本廣場、迴廊、花台、座椅與建築風格；省去東側工坊、東側閱讀小屋及部分重複樹木與花草。五區、40 台留言裝置及原有識別碼與通行路線保留，已移除建物的碰撞同步移除。
- 練功區省去大型展示櫃、額外角色展示、部分嵌條及植物浮雕；保留三台電腦、13 本可讀書籍、座椅、畫作、燈具及單字王裝置。
- 落點分析站保留原有工作室、桌椅及窗景；減少兩組盆栽、重複文件、鍵盤細件及裝飾線條。六個主要操作入口與八個座位保留。
- 輔導室以 r8 暖窗書房另製低階副本：保留兩個年級量表區、兩張可移動木椅、兩個沙發座位、窗景與主要擺設；抽減重複書冊、一盆小植栽及細縫線。模型由 155,556 面降至 58,386 面，色彩貼圖最長邊 256，省略法線／粗糙度貼圖。沿用全部 17 個碰撞代理及原有座位、量表和出口配置。低階包載入獨立 `generated/low/counseling/`；滿血版仍按需載入原模型。
- 低階包有獨立畫面設定檔，預設降低 3D 解析度、關閉 MSAA 與陰影。滿血包仍使用原設定。

完整場景及 Blender 母檔保留。新內容位於 `game/generated/low/` 與 `game/scenes/world_low.tscn`；滿血版仍使用原來的 `world.tscn` 和 `generated/streaming/`。建置前後的原始高階內容雜湊比對保存在本機驗證報告；Web 字型子集會加入新介面所需文字，原始字型不變。

## 登入與手機主畫面

帳號服務改用 Firebase `browserLocalPersistence`，Web 與 Windows WebView 都沿用有效登入狀態。開啟遊戲會在背景恢復登入並確認原有身分；明確登出、登入失效或裝置清除資料後才需要再登入。遊戲設定內保留「登出」與「切換帳號」。遊戲不自行儲存密碼或權杖。

手機入口提供「加入手機主畫面」；支援的 Android 瀏覽器可使用安裝提示，iOS 提供「分享 → 加入主畫面」指引。Manifest 具有 192／512 圖示、180 Apple touch 圖示、共同應用程式 ID 與 standalone 啟動。實際安裝仍由手機瀏覽器操作。

## 重建與驗證

需要 Godot 4.7.2、Node 24+ 與 Python 的 NumPy、Pillow、fontTools。更新交流區／落點分析站的低階美術副本時，先以 Blender 5.2 執行 `tools/export_low_art.py`（`--background --factory-startup`）；副本寫入 `art/LowResources/runtime_exports/`，不覆寫來源 `.blend`。

```powershell
python tools/build_web_release.py --godot <Godot-console.exe> --local-only
python tools/build_selectable_windows.py --godot <Godot-console.exe>
```

只更新輔導室低階副本：以 Blender 背景執行 `tools/export_low_art.py -- --only counseling`，再執行 Godot `--headless --path game --script res://tools/build_low_resource_pack.gd -- --counseling-only`。後續 Web 建置使用 `--reuse-low-resources`。使用者要求略過驗收時加上 `--skip-runtime-validation`，只建置與封裝，不啟動驗收場景。

Web 輸出為 `build/web/` 與 `_site/`；Windows 選包版為 `build/windows-resource-packs/`。移除 `--local-only` 才會更新 GitHub Pages 的待發布檔案，建置不會自動提交或推送。

帳號網站來源在獨立的 `admissions-site/` checkout；修改後需 `npm run typecheck`、相關測試及 `npm run build`，並用 `tools/snapshot_admissions_source.py snapshot` 更新整合來源快照。Cloudflare 發布包須一併納入新的 `admissions-site/out/`，才會套用持續登入設定。

主要檢查：

```powershell
python -m unittest discover -s tools -p test_resource_profiles.py
node --test tools/test_resource_cache.cjs tools/test_web_account_bridge.cjs
godot --headless --path game --script res://tests/resource_profile_checks.gd
godot --headless --path game --script res://tests/native_resource_cache_checks.gd
godot --headless --path game --script res://tests/persistent_account_checks.gd
node tools/check_resource_profiles_browser.cjs _site
```

瀏覽器檢查使用本機帳號協定測試頁，不登入正式帳號；手機測試屬 Chromium 觸控模擬，不能當作真實 iPhone 安裝或效能測量。
