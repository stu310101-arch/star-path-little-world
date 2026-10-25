# 星途 · 海岸群島世界

以 Godot 4.7.2 / Compatibility 製作的獨立專案。開啟本目錄的 `project.godot`，按 F5 執行；`scenes/world.tscn` 可在編輯器直接檢視海岸、街區與六站平台。原本 `art/Graduate/Godot` 的人物展示專案未修改。

## 2026-10-13 海岸世界重建

完整球形世界半徑600m，六區分布於六個軸向，12座主橋保留跨半球自由繞行。近距離10m地面的曲率落差約8.3cm；總覽可以旋轉看完整星球。每區拓展至約450–500m寬的獨立生態地形，包含12–28m山脊、林群、岩層、戶外湖泊與山徑。六站各有獨立抵達區及雙面入口牌。地形、碰撞、傳送、小地圖共用座標和岸線資料。

48棟建築改用連續外牆、凹窗與完整屋頂；全區以石材、暗金屬、木材及草土岩岸材質統一。植物依實際地形接地。原始來源模型保留；美術生成來源在 `scripts/world_architecture.gd`、`scripts/world_art_direction.gd`、`tools/world_landforms.gd`。

大學展覽館行走鏡頭改成跟隨角色位移，只有環視及遮擋偏移做平滑，修正渲染與物理更新頻率不同造成的晃動。

重新生成：`Godot --headless --path game --script res://tools/build_world.gd`。這會同步烘焙小地圖實際48棟地基與碼頭圖資，附上layout雜湊。實際六區畫面：執行 `Godot --path game --script res://tools/capture_world_redesign.gd`，輸出在 `deliverables/world-redesign/after/`（從儲存庫根目錄執行命令）。

標準Windows成品：`python tools/build_windows_release.py --godot <Godot-console.exe> --preset "Windows Standard"`，輸出 `build/windows-world/`。原低配預設仍可用原命令重建。既有玩家畫質設定仍保留。

## 2026-10-11 大學館

在世界選擇「大學館」，於入口按 E 進入獨立空間。深木書牆、石材地面與挑高中庭構成共用展覽空間。中庭有北、中、南、東、離島五個地區展區入口；各展廊最多八個展位，共 20 間、138 個條目。縮景為依正文設計的藝術化模型，並非各校建築測繪。

各校「校園印象」頁的「近看校園模型」可切換到模型近觀，拖曳改變角度、滾輪或按鈕縮放；按 Esc 或「返回展廊」恢復行走。近觀沿用展位的實際模型，角色暫時隱藏，低配模式也僅在此時啟用一盞局部陰影燈。

- WASD 移動、滑鼠拖曳觀景；靠近物件按 E 或點互動按鈕。M 開導覽，J 開收藏手冊；Esc 優先關閉閱讀，返回世界回到原本戶外位置。
- 導覽支援校名、別名、校區資訊搜尋及地區／已探索／收藏篩選。可從結果直接前往展位，也可從展廊出口走到下一間。
- 閱讀有短版介紹、五類完整正文與來源分頁；開啟介紹記錄已探索，收藏由玩家切換。`user://university_exploration.json` 保存固定條目 ID，內容更動不會重編 ID。
- 原文 `../content/universities/source-20261009.txt` 與人工短版 `../content/universities/editorial.json` 分開保存。`data/universities.json` 由 `python tools/import_university_content.py` 產生（從儲存庫根目錄執行）。來源區不當成正文條目；國防大學三學院各自展示並共用學校實體 ID。
- 共用 `scripts/indoor_transition.gd` 保留戶外實例、位置朝向、共享音樂與畫質；大學館模型放在延後下載分包，進館後才載入。載入中／失敗時可返回，下載失敗可重試。
- Blender 可編輯來源位於 `../art/UniversityHall/`，生成器為 `../tools/build_university_hall.py`；GLB 與碰撞／燈位資料位於 `assets/university_hall/`。

驗證：`python -m unittest discover -s tools -p test_university_content.py`；Godot 執行 `--headless --path game --script res://tests/check_university_hall.gd` 及 `res://tests/interior_transition_checks.gd`。去掉 `--headless` 並在尾端加 `-- --capture` 可記錄實際遊戲畫面；結果位於 `../deliverables/university-hall/`。Web 完整互動檢查使用 `node tools/check_university_web.cjs`。

本機測試匯出：`python tools/build_web_release.py --godot <Godot-console.exe> --local-only` 產生 `_site/`；`python tools/build_windows_release.py --godot <Godot-console.exe>` 產生 Windows 成品。上列命令均從儲存庫根目錄執行，並不發布公開網站。

Web 重建需要 Python 的 `numpy`、`fonttools` 與 Node 24+。本機可使用隔離環境：`python -m venv build/python-env`，接著 `build/python-env/Scripts/python.exe -m pip install numpy fonttools`；再以上述 Python 執行匯出工具。

本機試玩伺服器：從儲存庫根目錄執行 `python -m http.server 8768 --bind 127.0.0.1 --directory _site`，開啟 `http://127.0.0.1:8768/`。只在本機提供檔案，終端機按 Ctrl+C 停止。

地坪只保留一個平面，鋪面、灰縫與徽章整合在材質中，避免薄層重疊閃爍；地面獨立於建築模型的距離簡化。擷取檢查可加 `--floor-motion` 產生中庭與展廊各 12 個相鄰移動視角。

## 2026-10-10 Windows 圍棋與單字王

- 練功區第一台電腦：靠近椅子按 E 坐下，按 F／Enter 或點「進入」；圍棋在遊戲視窗內顯示，Esc／返回按鈕回到座位，再按 E 起身。棋局會保存在本機，重開可繼續。
- 中央單字王裝置：按 E 直接用預設瀏覽器開啟 `https://stu310101-arch.github.io/wordking/?page=home`。本次不整合帳號，日後內嵌由 `training_room.gd::_open_external_url` 這個交接點替換。
- Windows 內嵌採用 Godot WRY v1.0.2／Microsoft Edge WebView2 Runtime，來源與雜湊見 `addons/godot_wry/SOURCE.md`。圍棋 HTML 原樣保留，工具列在獨立 `web_games/native_go.html`。Web 匯出沿用 iframe，排除 Windows 元件。
- 從儲存庫根目錄執行 `python tools/build_windows_release.py --godot <Godot-console.exe>`，輸出 `build/windows-low/LittleWorld.exe`。請整份資料夾一起交付，保留 PCK、DLL 與授權。
- 原生圍棋整合檢查：有畫面的 Godot 執行 `--path game --script res://tests/native_go_checks.gd`；另以 `check_training_computer_games.gd` 驗證坐下與控制恢復、`check_training_props.gd` 驗證單字王入口及失敗重試。

## 2026-09-29 練功區互動

在大世界前往練功區入口按 E 進入室內，入口傳送門按 E 返回。室內共 12 個可坐座位，靠近按 E 坐下／起身；第一台電腦坐穩後 F／Enter 進入圍棋。走近書架按 E 選書，選定後角色拿起並打開，E／Esc 闔上放回，書頁暫無內容。

單字王投影裝置的 E 現已改為開啟網站；閱讀燈可開關，展示櫃固定關閉。原地圖換成梵谷《星夜》，可按 E 查看；茶具、陶器及牆面裝飾可旋轉檢視。沙發放大 16%，補上局部裝飾並保留中央通道；湖畔異常岸石改為低矮圓石。重建及驗證見 `../art/TrainingRoom/GAME_INTEGRATION.md`。

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

- 半徑 600 m 的完整球體，人物維持原尺度，建築按各地塊獨立設定米制尺寸；六片生態地形與街區由 12 座跨海步橋相連，保留跨半球往返與櫻花庭園支線。
- 六個現代都市街區共 48 棟建築：商業高樓、公共服務場館、住宅及街角商店。主幹道、橫向街道、外圍車道、人行道和行穿線相連；建築面向街道並保留入口及庭院。18 輛車沿外圍道路行駛，遇玩家和前車會停下。
- 櫻花庭園有 12 株手工安排的樹木，入口留白、中央標本收冠、東西觀景凹位與閉合散步路；花瓣動畫保留。2.7 m 寬的木橋具備側掛扶手碰撞與兩端引道，能從市街步行進入。
- 海上有 7 艘緩慢航行的客船／拖船／釣魚船，以及 7 組共 28 條在水下游動的魚。船舶使用真實尺寸的新模型，港灣另有繫泊小船。
- 六區分別採湖畔市政中心、曲岸商務碼頭、文化步行院落、溪谷大學校園、林蔭慢行住宅與濕地創業工坊的獨立配置；每區道路、建築座標、入口和庭院不同。
- 六區配置 623 株新榿木／白樺／柳樹／松樹及 4,366 個林下植被實例，依生態地形組成林群、草甸和蘆葦帶。城內水岸與外圍湖泊皆保留真實水域空缺，指定跨水步道有木棧道。
- 48 棟建築重建為完整石材、抹灰與金屬窗框外觀；原始素材保留，碰撞和入口沿用共同地塊座標。
- 六套生態配置位於 `data/biomes.json`，包含山脊、步道、湖泊、樹群及岩層；舊四套風景預設保留作歷史來源。
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

世界、街區、平台分別在 `generated/globe.tscn`（幾何存於壓縮的 `globe.scn`）、`generated/neighborhood.tscn`、`generated/stations.tscn`。每個街區獨立儲存在 `generated/districts/`，四套風景在 `generated/presets/`（歷史預設，本版改用獨立生態配置）。`scenes/world.tscn` 負責組合與照明；人物與 UI 在執行時建立。替換正式地球時，保留球心為原點，並確保可行走表面的半徑與碰撞一致。素材原檔保持不變，材質及幾何修改烘焙在產生的場景內。

## 動畫與後續整合

原始角色 `art/Graduate/Godot/assets/graduate.glb` 保留不變。世界專用版本由根目錄 `tools/prepare_world_character.py` 產生：保留 Walk／Run／JumpDown 及 Idle 第 0 幀，移除未使用的布料形變；來源與輸出大小、SHA256 及刪除權重驗證在 `assets/character/derivation.json`。骨架與布料由同一 AnimationPlayer 同步取樣，沒有額外加入呼吸動畫。入口的上升與淡出是視覺動畫，獨立於正常走路物理。

新增船和魚使用 Kenney／Quaternius CC0 素材；來源和授權在 `assets/scenery/SOURCES.md`。櫻花樹、坐姿釣客、釣竿是本專案新建模型。`art/WorldScenery/` 保留可修改的 Blender 母檔。先用 `tools/prepare_scenery_blender.py` 重建海上素材，再執行 `tools/refine_sakura_blender.py` 產生新版櫻花（後者會覆寫遊戲專用樹木 GLB，保留早期母檔）。新版母檔為 `sakura_refined_0.blend` 至 `_2.blend` 及 `sakura_petal.blend`。花簇與花瓣貼圖為本專案生成的原創素材，非宣稱下載的 CC0 貼圖。現代建築、汽車與授權見 `assets/urban/SOURCES.md`。

`world.gd` 提供 `world_ready`、`request_open_station(station_id, return_token)` 訊號，以及 `pause_world()`、`resume_world(return_token)`、`teleport_to(station_id)`。return token 目前是 Godot Dictionary，含 Vector3 位置與朝向；接 JavaScriptBridge 時需要另外序列化，這版未假裝完成 Web 資料橋接。

練功區已接入可探索室內：在世界入口圓台按 E，進入 `scenes/training_room.tscn`；在室內入口傳送門附近按 E，回到同一個世界及原先位置。室內有一台單字王展示裝置、六格空角色展示櫃、沙發及電競區，沿用既有角色和走跑跳操作。來源為 `art/TrainingRoom/WordKing_TrainingRoom_Game.blend`，遊戲資產為 `assets/training_room/wordking_training_room.glb`；修改模型後需同步 `layout.json` 碰撞資料。詳見根目錄 `art/TrainingRoom/GAME_INTEGRATION.md`。

其餘四站目前仍為功能入口預覽。登入、量表、落點分析、留言，以及 WordKing 網站帳號與練習內容尚未連接。人物只能走在陸地、道路、橋面與平台上；在海岸會停止，海洋球體不參與正常人物碰撞。球體核心碰撞只用於隔離測試。

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
