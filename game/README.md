# 星途 · 球型世界原型

以 Godot 4.7.2 / Compatibility 製作的獨立專案。開啟本目錄的 `project.godot`，按 F5 執行；`scenes/world.tscn` 可在編輯器直接檢視球體、街區與六站平台。原本 `art/Graduate/Godot` 的人物展示專案未修改。

## 2026-09-29 練功區互動

在大世界前往練功區入口按 E 進入室內，入口傳送門按 E 返回。室內共 12 個可坐座位，靠近按 E 坐下／起身；坐在電競椅時 F 可開關面前螢幕。走近書架按 E 選書，選定後角色拿起並打開，E／Esc 闔上放回，書頁暫無內容。

投影、三組螢幕、展示櫃門及閱讀燈支援 E 開關。原地圖換成梵谷《星夜》，可按 E 查看；茶具、陶器及牆面裝飾可旋轉檢視。沙發放大 16%，補上局部裝飾並保留中央通道；湖畔異常岸石改為低矮圓石。重建及驗證見 `../art/TrainingRoom/GAME_INTEGRATION.md`。

## 2026-09-26 長椅休息

櫻花庭園兩張長椅改朝散步路，側欄杆縮短，正面保留 2.75 m 寬入口；碼頭兩張長椅轉向中央甲板。全世界 34 張長椅統一支援靠近後按 E／點畫面按鈕坐下，再按 E 起身。角色坐下時停止移動與跳躍，仍可拖曳觀景；傳送會清除休息狀態。建築入口與座椅採最近可用目標，不會同時觸發。

坐姿使用獨立的 `assets/character/graduate_rest.glb`，包含膝蓋、手臂及衣袍的過渡形狀；原有行走與前空翻資產保持原樣。可編輯來源為 `../art/Graduate/Male_Graduate_Bench_Rest.blend`，生成器為 `../tools/author_bench_rest.py`。座椅配置增量重建：`--headless --path game --script res://tools/build_sakura_seating.gd`；互動驗證：`res://tests/bench_interaction_checks.gd`；原生畫面擷取：`res://tools/capture_bench_rest.gd`。資料與畫面位於 `../deliverables/bench-rest/`。

## 2026-09-25 世界精修

本次修訂以 `../deliverables/world-art-review.md` 的全域美術審核為依據；最終配置、可見游標相機及接合驗證使用 `python tools/verify_authored_world.py`。

- 拖曳期間游標保持可見，不擷取、不重置位置；總覽兩軸可完整旋轉，球心固定畫面中央，遠近鏡頭保持所選距離。房屋與櫻花遮擋使用完整物件淡出，生態樹只暫時隱藏遮擋視線的單株，離開後恢復。
- 櫻花庭園採明確橋口、閉環散步路與兩座獨立觀景凹位；小地圖共享實際園路、海岸和平台，並按真實島嶼範圍判斷區域名稱。新版玩家高度圖位於 `../deliverables/authored-garden/` 與 `../deliverables/authored-streets/`。
- 六區路線、房屋入口、街燈與植栽逐項留出完整人物通行空間；門口以原模型首層網格修整至真人尺度。原始 GLB 保留。
- 所有林地與街燈使用手工定點配置。`data/ecology_planting.json` 記錄具名群落及視線窗口，`data/street_lighting.json` 記錄街燈座標。
- 靜態花朵與落花以 `placements` 保存原矩陣，在實際渲染器啟動後上傳，避免無視窗建造器漏存 MultiMesh buffer。動態花瓣仍按既有動畫更新。
- 每次 Web 匯出後執行 `python tools/package_web_notices.py`，同步原文素材／字型／引擎授權與來源說明。

以下為先前水岸修訂的基礎功能；最新驗收記錄以 `../PROGRESS_CURRENT.md` 為準。

- 共用路線資料連接六區全部 24 個引道與 12 座跨島橋，橋側有連續扶手及碰撞；西側阻路商店移至路旁。
- 商務區獨立曲岸碼頭：木甲板、周邊護欄、開放入口、座椅、繫船柱、救生圈、告示及停泊船。
- 乾路與木棧道使用相同球面投影、分段與接縫，消除灰路重疊和轉角破面。
- 六區新增小型入口石材鋪面、座椅及花台；斑馬線根據真正行人路線退讓路口。
- 小地圖依真實河岸、道路與碼頭繪圖；方位固定，箭頭跟隨人物轉身，全球橋梁投影有獨立回歸檢查。
- 細部模型按材質合併，第二輪畫面在 `../deliverables/world-polish/`。
- 完整順序驗證：專案根目錄執行 `python tools/verify_world_polish.py`（需本機預覽服務）。

## 已完成

- 半徑 48 m 的可替換球體（前版 36 m，表面積增加約 78%），人物維持原尺度，建築按各地塊獨立設定米制尺寸；六個陸地街區和櫻花小島由步道相連。
- 六個現代都市街區共 48 棟建築：商業高樓、公共服務場館、住宅及街角商店。主幹道、橫向街道、外圍車道、人行道和行穿線相連；建築面向街道並保留入口及庭院。18 輛車沿外圍道路行駛，遇玩家和前車會停下。
- 櫻花庭園有 12 株手工安排的樹木，入口留白、中央標本收冠、東西觀景凹位與閉合散步路；花瓣動畫保留。2.7 m 寬的木橋具備側掛扶手碰撞與兩端引道，能從市街步行進入。
- 海上有 7 艘緩慢航行的郵輪／拖船／釣魚小船，以及 7 組共 28 條會躍水的魚。
- 六區分別採湖畔市政中心、曲岸商務碼頭、文化步行院落、溪谷大學校園、林蔭慢行住宅與濕地創業工坊的獨立配置；每區道路、建築座標、入口和庭院不同。
- 六區配置 62 棵榿木／白樺／柳樹／松樹及 60 組低矮植被／岸石，包含保留的 18 棵庭園樹；具名樹群留出 7 個看水及入口視線窗口。四處湖泊與兩條溪流／河口保留真實水域空缺，指定跨水步道有木棧道。
- 六棟第一版矮房使用獨立磚紅屋頂修改版，原始 Kenney 素材保持不變。
- 四套可重複使用的風景場景：garden、woodland、coast、courtyard，已完成配置，開啟遊戲即顯示。
- 建築依球面法線直立，平坦基座嵌入地面；修改後的材質與球面道路另存在 `generated/`。
- 都市路面沿長度與寬度均細分後貼合球面，碰撞來自同份曲面網格；交叉路口不會露出其他人行道的三角面。跨島橋只保留海面段，避免橋面蓋住市街。
- 現有黑金學士角色，走路 3.8 m/s、跑步 6.4 m/s；球心重力、平行傳輸朝向、遠近視角及相機遮擋檢查。
- 左／右鍵按住可水平及垂直旋轉；游標全程可見，放開、離開視窗、失焦或開啟入口時停止。總覽使用固定球心與半徑的旋轉，相機不因旋轉自行放大。左鍵點擊選單優先操作介面。
- 左上角小地圖：角色置中、地圖方位固定，箭頭跟隨人物實際朝向（含側走與倒退），顯示附近道路、步道、水域、建築、六個入口及櫻花林；最高每秒更新 10 次，使用快取的 2D 圖形，不新增第二個 3D 攝影機。目的地選單在下方展開，可捲動。
- 六站名稱、發光平台、快速傳送與入口预覽；按 E 對齊圓台後播放 JumpDown，原地起跳並淡出，再顯示面板；返回恢復人物與原位置。

## 操作

| 操作 | 按鍵 |
|---|---|
| 開始漫遊／世界總覽 | Tab 或畫面按鈕 |
| 移動 | WASD |
| 跑步 | Shift + WASD |
| 水平轉向／上下旋轉視角 | 按住滑鼠左鍵或右鍵拖曳；游標全程可見，放開停止 |
| 縮放 | 滾輪 |
| 自然區域 | 展開「自然景點」選擇湖畔、河口、林地、溪谷或沼澤 |
| 前往另一站 | 左側目的地按鈕；漫遊時先展開「選擇目的地」 |
| 跳躍進入場館預覽 | 靠近發光平台後按 E；動畫期間不能重複觸發 |
| 坐下休息／起身 | 走到長椅正面按 E，或點「坐下休息」；再按 E 起身 |
| 關閉面板 | Escape 或「繼續探索」 |
| 返回輔導室附近 | Home |

## 編輯與重建

2026-09-24 道路接縫修復：六區環形道路、人行道與自然步道改用連續球面轉角網格，兩側共享接角與相同細分，避免矩形路段直接拼接造成三角露底及細縫。濕地棧道板面與扶手沿同一接角排列，碰撞由修正後的網格產生。`tests/world_checks.gd` 現有 102 項檢查，包括每個轉角的內外側覆蓋與湖邊道路雙向實際行走。近景擷取工具為 `tools/capture_seams.gd`；修復圖與驗證記錄位於根目錄 `deliverables/seam-*`。

`data/world_layout.json` 記錄球體半徑、六站 ID／方向及起始街區配置；`data/districts.json` 的 `loop`／`roads`／`paths` 記錄各區道路與步道，`water`／`habitat` 記錄生態分區，`civic` 是場館入口位置；`urban_buildings` 記錄各棟建築的用途、位置、朝向、目標高度及地塊尺寸上限。早期 `placements`／`buildings` 僅作歷史配置保留，現代市街不讀取它們。修改後重新執行建造工具。工具會覆寫 `generated/`，手動美術修改請另存場景，或回填配置與工具，避免被重建覆蓋。

在本目錄執行（將 `godot_console` 換成本機 Godot 執行檔即可）：

```powershell
godot_console --headless --path . --import
godot_console --headless --path . --script res://tools/build_world.gd
godot_console --headless --debug --ignore-error-breaks --path . --script res://tests/world_checks.gd
godot_console --path .
```

物件尺寸沿用米制，人物約 1.75 m。調整球體半徑不會自動縮放人物與建築；重建後應重新驗證移動時間、道路接縫與基座。

世界、街區、平台分別在 `generated/globe.tscn`、`generated/neighborhood.tscn`、`generated/stations.tscn`。每個街區獨立儲存在 `generated/districts/`，四套風景在 `generated/presets/`（歷史預設，本版改用獨立生態配置）。`scenes/world.tscn` 負責組合與照明；人物與 UI 在執行時建立。替換正式地球時，保留球心為原點，並確保可行走表面的半徑與碰撞一致。素材原檔保持不變，材質及幾何修改烘焙在產生的場景內。

## 動畫與後續整合

原始角色 `art/Graduate/Godot/assets/graduate.glb` 保留不變。世界專用版本由根目錄 `tools/prepare_world_character.py` 產生：保留 Walk／Run／JumpDown 及 Idle 第 0 幀，移除未使用的布料形變；來源與輸出大小、SHA256 及刪除權重驗證在 `assets/character/derivation.json`。骨架與布料由同一 AnimationPlayer 同步取樣，沒有額外加入呼吸動畫。入口的上升與淡出是視覺動畫，獨立於正常走路物理。

新增船和魚使用 Kenney／Quaternius CC0 素材；來源和授權在 `assets/scenery/SOURCES.md`。櫻花樹、坐姿釣客、釣竿是本專案新建模型。`art/WorldScenery/` 保留可修改的 Blender 母檔。先用 `tools/prepare_scenery_blender.py` 重建海上素材，再執行 `tools/refine_sakura_blender.py` 產生新版櫻花（後者會覆寫遊戲專用樹木 GLB，保留早期母檔）。新版母檔為 `sakura_refined_0.blend` 至 `_2.blend` 及 `sakura_petal.blend`。花簇與花瓣貼圖為本專案生成的原創素材，非宣稱下載的 CC0 貼圖。現代建築、汽車與授權見 `assets/urban/SOURCES.md`。

`world.gd` 提供 `world_ready`、`request_open_station(station_id, return_token)` 訊號，以及 `pause_world()`、`resume_world(return_token)`、`teleport_to(station_id)`。return token 目前是 Godot Dictionary，含 Vector3 位置與朝向；接 JavaScriptBridge 時需要另外序列化，這版未假裝完成 Web 資料橋接。

練功區已接入可探索室內：在世界入口圓台按 E，進入 `scenes/training_room.tscn`；在室內入口傳送門附近按 E，回到同一個世界及原先位置。室內有一台單字王展示裝置、六格空角色展示櫃、沙發及電競區，沿用既有角色和走跑跳操作。來源為 `art/TrainingRoom/WordKing_TrainingRoom_Game.blend`，遊戲資產為 `assets/training_room/wordking_training_room.glb`；修改模型後需同步 `layout.json` 碰撞資料。詳見根目錄 `art/TrainingRoom/GAME_INTEGRATION.md`。

其餘五站目前仍為功能入口預覽。登入、量表、落點分析、留言，以及 WordKing 網站帳號與練習內容尚未連接。人物只能走在陸地、道路、橋面與平台上；在海岸會停止，海洋球體不參與正常人物碰撞。球體核心碰撞只用於隔離測試。

車輛為環境交通，不能駕駛；沒有實作機車或腳踏車。

碰撞層：1 為可行走表面、2 為測試用球體核心、4 為人物、8 為建築及圍籬。新增場景請維持此區分，避免把屋頂誤判成可行走海岸。人物停步後保留落腳點，動畫播放速度依實際位移調整，遇到阻擋不會持續原地走路；靜止待機不會逐幀重算布料。

## Web 本機測試

本機已安裝對應 4.7.2 的官方 Web 匯出範本。使用單執行緒 Web 匯出，不依賴 SharedArrayBuffer：

```powershell
godot_console --headless --path . --export-debug Web ../build/web/index.html
python -m http.server 8765 --bind 127.0.0.1 --directory ../build/web
```

在瀏覽器開啟 `http://127.0.0.1:8765/index.html`，不要直接打開 HTML 檔案。此為本機預覽，未發布網站。`tools/check_planet_browser.cjs`（專案根目錄）會測試已安裝的 Chrome 與 Edge，需 Playwright。

當前角色來源 GLB 約 118 MB，加入跳躍後世界專用版本約 58 MB；首次開啟仍需下載 Web 引擎與資料。瀏覽器測試記錄包含實際右鍵拖曳、視角、位移、走跑及跳躍動畫與面板返回狀態，不能視為所有裝置的效能保證。

## 授權與驗證

- 原始附件完整保留於根目錄 `assets/source/attachments.zip`。
- 三組 Kenney 素材的 License.txt 保留在 `assets/kenney` 各自目錄，均標記 CC0；人物授權在 `assets/character/License.txt`。
- 中文字體採 Noto Sans TC，OFL 授權保留於 `assets/fonts/OFL.txt`。
- `tests/results.json`：六站落地、道路碰撞與通行、面板返回、整球重力與南北極方向連續性。
- `validation.json`：Godot 靜態解析及場景實例檢查。
- 根目錄 `deliverables/`：原生與瀏覽器截圖、瀏覽器驗證結果。


## 自然區與紅屋頂模型重建

1. 在獨立 Blender 背景程序執行 `tools/author_ecology_blender.py` 與 `tools/red_roof_houses.py`（均位於專案根目錄）。母檔保存在 `art/Ecology` 及 `art/RedRoofHomes`。
2. Godot `--headless --editor --import` 匯入新 GLB。
3. 執行 `res://tools/build_world.gd`。`ecology_world.gd` 會依水域輪廓裁切地表，再放置植被；`ecology_instances.gd` 會在編輯器與遊戲載入批次模型位置，避免無頭建造時遺失 MultiMesh 資料。
4. 執行 `res://tests/world_checks.gd`，重新匯出 Web 並做畫面檢查。

`tools/plan_biome_world.py` 可重建本版配置，但會覆寫之後手動修改的配置；只有刻意重設時才執行。它會先保存設定備份。

本輪（2026-09-24 生態版）Chrome 功能及畫面已驗證，但操作採樣約 4–6 FPS，尚未達到流暢試玩標準。原生擷取遇顯示驅動初始化失敗；效能不可沿用前版測量值。詳見 PROGRESS_CURRENT.md。
