# 暖窗書房 r8 家具修訂：來源與授權

第一站輔導室的唯一完整高階美術。10.8 × 8.6 公尺室內保留高一／高三兩個資料區、共用窗邊沙發、實體窗洞與木作深窗台、窄幅摺簾、淺壁架、書籍與一瓶鬱金香。建築、家具、裝置、書頁、花器與植物均為本專案原創幾何；沒有沿用舊溫室的玻璃拱梁、展示車、大葉紋地毯或扁平花朵。

## r8 原創家具與位置修訂

`../../tools/counseling_wood_chair.py` 建立全木製量表桌椅：淺凹實木坐面、弧形椅背、細木背柱、外張椅腳及橫撐。每張 2,078 三角面，兩張椅子使用既有 `joinery` PBR 材質，沒有新增下載、貼圖或低階資產。坐面中心高約 0.50m，總高約 0.92m，局部朝向 -Z；碰撞、座位與起身位置由房間 layout 定義。

窗邊沙發向窗移動 0.25m，沙發下方的綠色地毯移除，木圓邊桌往入口移動 0.50m。原有扶手毯與縫線隨沙發移動。兩個量表桌前保留各自的地毯，新增一張木椅。木椅使用獨立空間網格，已整合坐姿 WASD 移動，實測速度 2.6m/s，約為一般步行 3.8m/s 的七成。椅體、人物、碰撞及起身錨點同步；桌面與牆面阻擋、量表暫停及 E 起身已通過本輪原生簡驗。

## 保留的 r7 原創追加內容

窗下護牆板、天花板周邊線腳、淺壁面收納格、帶蓋檔案盒與開口雜誌架由主建模腳本原創。`../../tools/counseling_soft_furnishings.py` 原創扶手垂毯、包邊縫線、中空布製收納袋與提把。這些物件重用既有木作、漆面、紙張及布料材質；沒有新增外部下載、貼圖或低階資產。

正式 r6 及其來源 ZIP 已固定封存，r7 本機預覽與紀錄保留。最新授權允許 r8 簡短遊戲內驗收及發布；本文件更新時結果待主流程記錄。Blender 設計預覽不代表 Godot 實機畫面，建模完成也不代表已發布。

## 可編輯來源

- `CounselingRoom.blend` 保留具名構件、修飾器、材質和封裝貼圖。
- `../../tools/build_counseling_room.py` 以 Godot Y-up 公尺座標建立可重建場景。`../../tools/counseling_botanicals.py` 建立三枝具重疊杯狀花瓣、彎曲莖葉與中空花器的原創鬱金香。
- `../../tools/counseling_wood_chair.py` 為 r8 原創木椅；`../../tools/counseling_soft_furnishings.py` 保留扶手毯與帆布收納袋原創來源。
- `prepare_textures.py` 使用官方原始下載，產生兩組 2K 木紋和一組 1K 布料的 canonical PNG。原圖與記錄保存於 `sources/` 和 `sources.json`。
- GLB 匯出副本按空間合併，母檔保持可編輯；碰撞／互動錨點由獨立 `layout.json` 定義。
- 牆上的「ROOM TO GROW／NOTICE／EXPLORE／TRY」小幅成長圖由原創幾何與 Blender 內建文字生成；中文功能標示由 Godot 既有字型呈現，沒有外部插畫下載。

## 外部素材與授權

1. **Poly Haven — Wood Floor**，Dimitrios Savva。
   - 資產：https://polyhaven.com/a/wood_floor
   - 授權：https://polyhaven.com/license — CC0 1.0 Universal。
   - 官方原生 2K Diffuse、Roughness、Normal GL，均為 2048×2048；原始 JPG 與官方 MD5／尺寸核對記錄完整保留。
   - 用於地板。修改底圖色彩、明暗對比與淺木色；法線與粗糙度保留來源。
2. **Poly Haven — Wood Table 001**，Dimitrios Savva（攝影）、Rico Cilliers（處理）。
   - 資產：https://polyhaven.com/a/wood_table_001
   - 授權：https://polyhaven.com/license — CC0 1.0 Universal。
   - 官方原生 2K Diffuse、Roughness、Normal GL，均為 2048×2048。`sources/wood_table_001-files.json` 保留官方 API；下載檔逐一比對 byte size 與 MD5，`sources.json` 保存 SHA-256。
   - 用於桌面、木作、木椅、壁架與窗框；底圖轉為溫暖蜂蜜木色，法線、粗糙度與實際木紋保留。與地板使用不同素材，沒有把地板拼板紋套至家具。
3. **ambientCG — Fabric 060**，ambientCG。
   - 資產：https://ambientcg.com/view?id=Fabric060
   - 授權：https://docs.ambientcg.com/license/ — CC0 1.0 Universal。
   - 1K Color、Roughness、Normal GL；原始 ZIP 和使用的 JPG 保留。
   - 底圖染為鼠尾草綠、杏桃與燕麥亞麻色；共用低強度布紋法線及粗糙度，用於地毯、軟墊、窗簾及燈罩。陶器、紙張、金屬、彩繪木材與花瓣各用獨立材質。

下載日期：2026-10-24。全部木紋直接取自原生 2K，沒有圖片放大。11 張 runtime PNG 的原始來源與修改可由 `prepare_textures.py` 重現。未使用來源網站的品牌、文字或示範渲染作遊戲資產。

CC0 允許複製、修改、商用及散布，不要求署名；本專案仍保存作者、來源與修改紀錄。完整法律文字：https://creativecommons.org/publicdomain/zero/1.0/legalcode 。

## 美術參考與引擎

參考 Pounce Light《Tiny Glade》的柔和建築與自然圍合（https://pouncelight.games/tiny-glade/）、Toukana《Dorfromantik》的安定色塊（https://www.toukana.com/dorfromantik），以及 Witch Beam《Unpacking》的生活物件與安靜空間（https://www.unpackinggame.com/）。僅借鑑設計原則，未取用遊戲模型、圖像、角色或商標。

Godot 4.7.2 GL Compatibility；公尺制重複 UV、粗糙度、OpenGL 法線、mipmap 與各向異性取樣。2K 家具木紋保留近距離桌面細節；布料使用 1K。只提供一套完整資產，不增加低階版本。r8 目前模型為 155,556 三角面、8 個空間網格、40 材質、11 張貼圖；`export-report.json` 記錄匯出預算與網格檢查。本輪簡短遊戲內驗收與發布待完成，完成結果由 `acceptance-manifest.json` 及發布紀錄另行記載；不以 Blender 圖片、r6 實機圖或舊版效能代替本版遊戲驗證。

