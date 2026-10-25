# 大學館：各校展示配置

138 個條目各有一份 `art_profile`，共配置 570 個可見模組。展示差異來自正文中的山坡、湖泊、海岸、交通、附近生活圈、展演與實作場域，以及明確列出的官方補充。採用 8 種展示臺、13 種構圖骨架與 35 種實際使用的景物模組；模組可共用，不以隨機色彩、編號或細微位移製造唯一性。

## 資料來源與維護

- `source-20261009.txt` 是使用者提供的原文件，保持位元組不變。
- `art-profile-plan.tsv` 是逐校編輯的模組選擇與原文關鍵字，138 列均有具體正文依據。臺科大列印設備使用 `@official-ntust-printing` 明確引用官方補充，不假冒原文關鍵字。
- `build_art_profiles.py` 將原文關鍵字解析成完整原句，套用構圖與明確幾何變換，更新 `editorial.json`。
- `official_enrichment.json` 保存 2026-10-11 查閱的 8 校官方補充、11 個來源連結及重新編輯的短版內容，包括傅鐘造型與臺科大列印資源。
- `tools/import_university_content.py` 驗證內容後生成 `game/data/universities.json` 與驗證報告。
- `tools/test_university_content.py` 驗證五類原文、原有來源、編輯資料、展示線索與模型範圍。

重建順序：

```text
python content/universities/build_art_profiles.py
python tools/import_university_content.py
python tools/test_university_content.py
```

## 執行介面

`entry.art_profile` 含以下欄位：

| 欄位 | 用途 |
| --- | --- |
| `version` | 配置格式版本，目前為 1 |
| `display_variant` | 8 種展示臺之一，執行端加上 `display_` 查找 kit child |
| `composition` | 編輯意圖 ID、共用構圖類別及繁中構圖說明；8 個代表展位另有 `primary_modules` 和主從比例說明 |
| `palette` | 木、石、抹灰、金屬與景觀配色的美術指引；不是官方校色，也不覆蓋共用組件的 PBR 材質 |
| `modules` | 完整 `component_*` key、可讀標籤、位置、比例、Y 軸角度及來源 cue IDs |
| `source_cues` | 569 筆正文線索有正文欄位與精確原句；1 筆官方新增線索使用 `source_kind: official`、`statement`、`source_urls` 與 `reviewed_on`，不含假的 `quote`／`section` |
| `representation_note` | 顯示於閱讀介面的藝術化呈現說明 |
| `external_sources`、`reviewed_on`、`research_cues` | 僅 8 個官方補充條目具有，與原文件日期分開 |

`entry.research_update` 使用 `{reviewed_on, sources:[{title,url,note}], note}`，供介面顯示官方補充日期與連結。官方資料只支持景點、校區或教學資源等事實，不代替學生評價。

模型座標使用 Godot XYZ、公尺制，相對於展示根節點 `(0, .88, -.15)`；局部限制為 `x ±2.25`、`z ±.8`、`y 0–1.25`。`rotation_y` 是角度。每個模組的底部原點為 0。表面之間至少保留 .03 公尺；政大的橋與河是唯一刻意疊置，橋底提升至 .05 公尺。

## 代表展位

| 條目 | 可辨識輪廓與配置 |
| --- | --- |
| 臺大 001 | 成列椰林、獨立傅鐘、偏側醉月湖，與公館街市分組 |
| 中興 003 | 大水面、林蔭、田間研究與乳品實習商店 |
| 政大 006 | 階坡與水平河帶，橋梁在水面上方；山上山下動線作主題 |
| 東海 009 | 專用四片上收曲面教堂，搭配低平牧場、樹列與乳品陳列 |
| 海大 020 | 不規則海岸、山體與船舶，區分校園生態與附近港灣 |
| 北藝大 025 | 開放劇場、側翼階坡、展廊與創作工坊 |
| 北醫 056 | 醫療、實驗雙量體與吳興街區；相鄰擺設不表示兩校區實際相鄰 |
| 臺科 075 | 以放大的 FDM 龍門、線材盤、列印平台與旁側光固化機為主景；工程實驗、模型工坊及公館日常為配景 |
| 敏實 122 | 機械手臂、程式控制與機電操作形成製造學習鏈 |

弘光 095 與中華醫事 111 的正文都包含臨床照護、烘焙及食品技能，所以保留相近的模組組合。這是內容相似的結果，並未為數字上的「138 種唯一」而加入沒有依據的地標。

## 驗證範圍

21 項內容測試涵蓋 138 個固定 ID、690 段正文、803 個原始 URL、各模組來源對應、官方補充隔離、代表展位的不同主輪廓，以及幾何變換與標牌淨空。8 個代表展位的主要地標占地均至少為最大配景的 1.7 倍，並非把所有物件等比例放大。

本輪以含 44 個 child 的最終精修 kit 檢查 570 個配置，21 項測試全部通過，沒有越界或非預期的地面重疊。結果、最高位置及 manifest SHA256 寫入 `deliverables/university-hall/content-report.json` 的 `art_geometry_audit`；最高模型頂部為 2.00896 公尺。

標籤底板下緣為 1.97 公尺，不能只用 2.13 公尺中心判定遮擋。傅鐘已校準為 1.933844 公尺，低於底板 3.6 公分。東海教堂及臺科列印機接近或略高於底板下緣，幾何上與後方底板的 Z 位置分離；兩項已列在 `near_tag_plaque_height`，仍須由實際相機畫面判斷視覺相切或遮擋。

這些測試證明資料與幾何範圍符合約定；實際外觀、操作與效能另由 Godot 畫面和平台測試判定。
