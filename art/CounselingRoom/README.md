# 第一站輔導室：暖窗書房（r8 家具修訂，簡短驗收完成）

2026-10-25 補充：已從本 r8 母檔另製獨立低階副本，位於 `../LowResources/runtime_exports/counseling.glb` 與 `../../game/generated/low/counseling/`。低階保留兩張可移動木椅、兩個沙發座位、兩個量表區及 17 個碰撞代理，減少重複書冊、一盆小植栽和細縫線；輸出場景 58,386 三角面、256 色彩貼圖，模型及版面均由低階包獨立載入。此補充不改寫 r8 高階母檔；本次依使用者要求不做驗收，以下 r8 驗收紀錄不適用於新增低階副本。重建方式見 `../../docs/resource-packs.md`。

此目錄目前是 r8 家具修訂，已完成簡短遊戲內驗收，可供本輪打包。r8 正式部署結果記錄於 `../../build/counseling-delivery-20261024-r8/delivery.json`。已發布 r6 `cf-46e7f42872298ffb` 的 Windows、Web 與來源資產 ZIP 固定保留在 `../../build/counseling-delivery-20261024-r6/`，r7 本機設計與圖片亦保留。

## 本輪家具調整

- 沙發向窗邊移動 25 公分（中心 X 從 -4.43 改為 -4.68），同步調整扶手毯、縫線、碰撞與兩個坐位位置。
- 移除沙發底下原有的綠色地毯，沙發直接放在木地板上；兩個電腦桌前的量表區地毯保留。
- 木頭圓邊桌往入口方向移動 50 公分（Z 從 1.95 改為 2.45），書本與碰撞一併移動。
- 兩個電腦桌前各增加一張全木製椅：淺凹實木坐面、弧形木椅背、三根細背柱、外張椅腳與橫撐。坐面中心高約 50 公分，椅背高約 92 公分，朝向桌面。
- 木椅各保留獨立空間網格。按 E 坐下後以 WASD 依鏡頭方向移動，實測約 2.6m/s，約為正常步行 3.8m/s 的七成；椅子、角色、碰撞及起身錨點同步移動。F 開啟對應年級量表，面板開啟時停止移動，再按 E 安全起身。

## 保留的 r7 設計

- 窗下增加窄幅框式護牆板，使用柔和漆面與細木質頂帽；入口側牆採同一組構件。
- 天花板周邊增加三層薄線腳，保留原有高度，沒有低垂橫梁。
- 右側壁架下方增加淺收納格、帶蓋紙製檔案盒與斜口雜誌架，書冊可從上方看到；左格放中空亞麻收納袋及布製提把。
- 沙發原先單層布片改成沿扶手垂落的織物，含摺返、自然皺褶與包邊縫線。

房間維持 10.8×8.6×3.5m，只有高一、高三兩個資料區。出生點與出口沿用原配置，現在共有兩個沙發座位及兩個木椅座位、17 個碰撞代理（包含一個相機專用代理）。本輪只增加使用者要求的兩張桌前木椅，沒有加入路中展示車或其他重複家具。調整後的實際動線與坐姿操作由簡短遊戲內驗收確認。

## 來源與執行資產

- `CounselingRoom.blend`：可編輯母檔，保留具名零件、倒角、布厚、分區及封裝貼圖。
- `../../tools/build_counseling_room.py`：背景 Blender 重建腳本，使用 Godot Y-up 公尺座標。
- `../../tools/counseling_soft_furnishings.py`：本輪原創扶手毯及中空布製收納袋。
- `../../tools/counseling_botanicals.py`：先前原創三枝鬱金香、曲面葉片與中空花器。
- `../../tools/counseling_wood_chair.py`：本輪原創全木製桌椅，局部朝向 -Z，每張 2,078 三角面；不建立材質貼圖或自行新增碰撞。
- `../../game/assets/counseling_room/counseling_room.glb`：155,556 三角面、8 個空間網格、40 個實際使用材質、36,008,128 bytes；上限 180,000 三角面。
- `../../game/assets/counseling_room/layout.json`：修訂標記 `2026-10-24-counseling-studio-r8`；記錄新的家具、互動及碰撞位置。
- 貼圖仍為 11 張 canonical PNG：地板與家具各 3 張原生 2K PBR，布料共 5 張 1K。新增物件重用原有材質，未新增貼圖、低階房間或低階材質包。

來源、授權和修改記錄見 [SOURCE_NOTES.md](SOURCE_NOTES.md)。外部素材原件與雜湊保存於 `sources/`、`sources.json`、`source-verification-2k.json`。

## 設計預覽與目前狀態

r7 的 `../../deliverables/counseling-room/r7/blender-design-overview.png`、`blender-design-wall-storage.png` 是當時的 Blender Cycles／設計相機預覽，並非 r8 遊戲畫面或驗收證據。年級牌的中文標示由既有 Godot `Label3D` 在執行時加入，因此 Blender 預覽的牌面留白，不代表遊戲功能標示被移除。r8 的圖片與簡短檢查結果另存於 `../../deliverables/counseling-room/r8/`。

**r8 簡短驗收完成：原生 51 項、直線動線 23 項全部通過，材質依賴檢查零失敗。** 檢查涵蓋實際角色步行、E 坐下／起身、WASD 速度與同步、桌面及牆壁阻擋、F 開啟量表、面板暫停、沙發座位及鏡頭避障。已人工檢視原生圖片，包括 `studio-overview.png`、兩年級坐姿與 `sofa-table-floor.png`。沒有追加完整帳號／瀏覽器、實體手機或持續效能測試。

首輪測試診斷保留於 `r8/history/`：速度改採實際物理 tick 的模擬時間；碰撞探針排除地板；材質改用雙軸 UV 非退化判定，保留完整 UV／切線檢查。細縫線 UV 範圍約 0.00270×0.02769，符合公尺尺度貼圖，沒有為測試放大或更換材質。最終成功報告位於 r8 根目錄；`acceptance-manifest.json` 記錄本版來源雜湊與驗收範圍。

## 後續重建

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python tools/build_counseling_room.py -- --no-render
```

遊戲整合應先做正常 editor import，更新 canonical 貼圖引用；不能使用 recovery mode 略過材質後處理。GLB 匯出副本按空間合併，兩張可移動木椅保留獨立網格，母檔保持可編輯。

## 功能範圍

高一 `interest_high1` 對應六項 RIASEC；高三 `interest_high3` 對應 33 項知識及兩種適配列。裝置與遊戲設定共用 Godot 面板與帳號資料，沒有新增施測日期。本輪執行時變更僅配合家具與坐姿操作，不重新定義量表或帳號資料格式。歷史 r4／r5／r6 證據、已發布包及 r7 設計預覽保留，不套用為 r8 的驗收結論。
