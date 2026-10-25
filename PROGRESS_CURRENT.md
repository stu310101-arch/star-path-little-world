# 選校推薦室 — 2026-10-25（r3 已發布至 Cloudflare）

正式版 `cf-a5ad2b01262d5612`，Cloudflare version `440e4776-8bde-4446-b397-34e2ad8e4bea`。入口：https://star-path-little-world.star-path-little-world.workers.dev/ 。

- 完成以完成版量表與一份成績推薦 115 年 64 校／2,206 校系，含三種排序、原因、歷年回測、每頁 20 筆、三校系比較、帳號設定／收藏及大學館往返。
- 房間採不同造型的三台與五個可坐座位；電腦前方文件已移到後櫃，坐下 F 使用工作台、E 起身。天文儀兩環與星體沿不同軸速運轉，可暫停並尊重減少動態效果。
- 完整／低階房間 104＋104、實際原生帳號 31、原生協定／UI 53、Web bridge 17、最終桌面／手機模擬 Web 34 項通過；手機尚非實機驗證。
- Windows／Web r3 候選及可編輯資產留在 `build/recommendation-delivery-20261025/`；來源提交包含必要的帳號、大學館與資源包前置。正式 Firestore 僅新增推薦規則，索引未變動；既有登入 Worker 與兩個 Durable Object 綁定保留。
- 已發布的帳號頁、推薦 host 與正式 Firestore 共 14 項操作檢查通過，合成帳號與其資料已完整清理。正式規則讀回 SHA 與本機一致；發布封存位於 `build/releases/20261025-cf-a5ad2b01262d5612/`。
- 操作、建置與驗證：[推薦室說明](docs/recommendation-room.md)。

---

# 輔導室重疊面修正 — 2026-10-25（已發布）

正式版 `cf-c915bee8bee26338`，Cloudflare version `793bba73-4627-481f-b6b3-f50305ff4528`。

- 已修正轉角桌、畫框、書刊架、書封、窗框、窗台與線板共平面接合；東側畫作移至背板前方。完全重複面 144 → 0。
- 高／低階原生遊戲簡短檢查 16 項全數通過，已查看 6 張實際畫面；4 座位及 17 碰撞代理保留。
- 只更新正式版桌面／手機 Web 輔導室高低階模型與下載中繼資料，未帶入其他進行中的推薦室內容。沒有回滾或擴大完整驗收。
- 正式版 release manifest 已讀回一致。來源、證據及部署紀錄見 `docs/counseling-double-faces-20261025.md`、`deliverables/counseling-room/double-faces-20261025/`、`build/releases/20261025-cf-c915bee8bee26338/`。

---

<!-- counseling-low-published:cf-bafcd361353fd1ce:18e3b3e1-29bb-4db0-b484-210282aa366a -->
# 輔導室低階資源包 — 2026-10-25（已發布並保存）

正式網址：https://star-path-little-world.star-path-little-world.workers.dev/。版本 `cf-bafcd361353fd1ce`，來源 `packs-2b38d7a24c341eba`，Cloudflare version `18e3b3e1-29bb-4db0-b484-210282aa366a`。

- 以 r8 暖窗書房製作獨立低階副本，保留房間結構、窗簾、主要家具、壁架與部分植栽；適量減少重複書本、小盆栽與細部縫線。
- 低階模型 58,386 三角面、貼圖上限 256px；保留兩個年級量表區、4 個座位、木椅移動、出口與 17 個碰撞代理。高階原始美術維持原樣。
- 接入既有資源包選擇與切換，低階設定載入專用輔導室；桌面 Web、手機 Web 和 Windows 發行包均已建置。
- 資產／本輪整合來源、Windows、Web 三份 ZIP 位於 `build/counseling-low-delivery-20261025/`。資產 ZIP 並非完整遊戲原始碼；其餘來源仍在工作區與先前完整來源封存。
- 依使用者要求未執行遊戲、手機或部署後驗收；發布成功依 Cloudflare 部署回覆，紀錄位於 `build/counseling-low-deploy-retry-20261025.log`。

---

<!-- counseling-r8-published:cf-be9d59433f64fd24:d9752512-2625-4472-b961-21569a81e55b -->
# 第一站輔導室 r8 家具與可移動木椅 — 2026-10-24（已發布）

已發布至 https://star-path-little-world.star-path-little-world.workers.dev/ ，build `cf-be9d59433f64fd24`、來源 `packs-f3106eab31bb4621`、Cloudflare version `d9752512-2625-4472-b961-21569a81e55b`。實際成功回覆保存在 `build/counseling-r8-cloudflare-deploy.log`；發布封存位置為 `build/releases/20261024-cf-be9d59433f64fd24/`，完整壓縮包在 `build/counseling-delivery-20261024-r8/`。

- 沙發向窗邊移動25公分並移除底墊，旁邊圓木桌向入口前移50公分；兩個地毯區電腦桌前各有一張木椅。
- 木椅操作：E坐下、WASD以2.6m/s帶動椅子、E起身、F開啟量表；面板開啟期間停止移動。房間共有4個座位、17個碰撞代理、8個空間網格、155,556三角面、40材質和11張貼圖。
- 高一集中六項RIASEC；高三保留33項知識、最適合／適合與Z分數。沒有施測日期，房間裝置與設定仍共用本人帳號資料及Godot面板。
- 本輪實際通過51項原生簡短檢查與23項動線／視線檢查；材質相依11張貼圖、15個引用、0失敗。保存11張原生PNG，主流程已查看其中5張關鍵圖。報告位於 `deliverables/counseling-room/r8/`。
- 初輪fixture計時、地板排除與小縫線UV閾值修正紀錄保存在 `r8/history/`，未刪除或改稱最終通過。此次未擴大為完整帳號、瀏覽器操作、手機或持續效能驗收。
- 公開站點4檔讀回：`index.html`、`index.release.json`、`index.packs.json`、`mobile/index.packs.json`，4項HTTP200／逐byte比對通過；結果來自 `r8/public-release-checks.json`，不是完整瀏覽器操作測試。
- 3份ZIP的大小、CRC與SHA-256以封裝工具實際metadata為準，記錄於交付資料夾的 `packages.json`、`assets.json`。Firebase規則與索引和r6已部署副本一致，本輪未變更；r6發布封存及r7設計證據保留。

---

# 輔導室 r7 追加設計 — 2026-10-24（本機設計已保存，暫不驗收）

r6 已發布並固定封存後，依最新要求完成這輪追加美術。這輪只更新本機來源及 Blender 設計預覽，沒有進行 Godot 匯入、完整驗收、遊戲發行包重建或再次部署。

- 已加入窗下木作護牆、細緻天花周邊線板、右側淺壁櫃、書刊分類架、帶蓋收納盒與帆布提把收納盒。
- 沙發扶手毯布改為有厚度、自然垂墜、回折層和縫邊的模型；新增物件收在牆面與既有家具內，未增加路中展示車或重複桌椅。
- 高一／高三兩個資料區、裝置、出生點、出口、座位及碰撞配置保留。模型目前 151,828 三角面、40 材質、6 個空間網格，沿用 11 張貼圖與唯一高階資產。
- 可編輯來源：`art/CounselingRoom/CounselingRoom.blend`、`tools/build_counseling_room.py`、`tools/counseling_soft_furnishings.py`；本機 GLB 位於 `game/assets/counseling_room/counseling_room.glb`。
- 設計預覽：`deliverables/counseling-room/r7/blender-design-overview.png`、`blender-design-wall-storage.png`。這是 Blender 作者視角，並非 Godot／Web 遊戲畫面或操作驗收。
- 正式網站仍為已發布 r6 `cf-46e7f42872298ffb`；r7 尚未驗收、尚未發布。r6 壓縮包、部署目錄與發布紀錄維持原樣。

---

# 第一站暖窗書房與帳號量表 r6 — 2026-10-24（已發布並封存）

已完成輔導室 r6 全面重設及 Web／Windows 封裝，Web build `cf-46e7f42872298ffb`、遊戲來源 `packs-5e19389db77eaca4`。Firebase rules／indexes 與 Cloudflare 網站已發布成功。正式網址 https://star-path-little-world.star-path-little-world.workers.dev/ ，Cloudflare version `869aa1c9-1536-42d0-8575-760c9ef4ff53`；最新封存記錄於 `build/releases/20261024-cf-46e7f42872298ffb/` 及 `build/releases/LATEST.json`。

- 房間只有高一、高三兩個資料區：高一集中六項 RIASEC；高三包含 33 項知識、最適合／適合與 Z 分數。沒有施測日期。房間裝置和遊戲設定共用 Godot 面板及本人帳號資料，不導向網站表單。
- 10.8×8.6×3.5m 暖窗書房：實牆、深窗台、木作操作區、共用沙發、壁架、書頁、陶器、植物及立體鬱金香；已完成窄幅摺簾、燕麥色地毯、中空燈罩與窗光。移除舊入口展示車與路中書架。123,744 三角面、40 材質、11 張原始 2K／1K 貼圖，只有一套高階資產。
- 39 項必填、兩組初始 25 列可新增適配資料、草稿、歷次紀錄、推薦依據、版本衝突與帳號隔離保持既有實作。歷史證據保留 54 項表單、31 項 Windows／WRY、15 項 Web 帳號往返及 r4 完整 Web 38 項檢查；本次未改動表單／帳號功能程式，不把舊測試改稱為 r6 最終驗收。
- r6 初版配置曾通過 37 項直線動線／視線與 25 項 headless 檢查；它們早於最後出生點、螢幕與材質調整。最終美術已正常匯入並保存 7 張 Godot 原生圖片。依使用者要求，未追加最終完整原生、材質、動線、效能或 Web 驗收；詳見 `deliverables/counseling-room/r6/verification-status.json`。r5 入口阻路的失敗基準也保留。
- 輔導室使用獨立延後載入包，兩種主資源設定共用完整房間。本次 Web／Windows 建置與分包完成，沿用既有低階世界資產，未新增低階輔導室。
- 交付封裝：`build/counseling-delivery-20261024-r6/`，含 Windows ZIP、Cloudflare ZIP、可編輯來源資產 ZIP、Firestore 規則與 SHA-256。Firebase 成功紀錄為 `build/counseling-r6-firebase-deploy.log`；Cloudflare 紀錄為 `build/counseling-r6-cloudflare-retry.log`。舊正式版與 r4／r5 封存保留，未 stage、commit 或 push。
- 最新指示：先完成本版上傳及封存，再繼續追加本機設計，暫不驗收。後續設計另記修訂，不覆寫 r6 封存或自動覆蓋正式網站。

詳細說明與限制見 `docs/counseling-interest-20261024.md`、資產說明 `art/CounselingRoom/README.md`。以下保留原發布紀錄。

---

# 低階／滿血材質包發布與版本封存 — 2026-10-24

已發布至 https://star-path-little-world.star-path-little-world.workers.dev/ ，build `cf-0666eb774cdfdd23`、來源 `packs-54fe4b02e9261e93`、Cloudflare version `420550c1-01d6-4d48-af1c-878e7a1726db`。

- 包含低階／滿血選包與下載切換、舊包保留／刪除、持續登入與登出／切換帳號、手機 PWA 入口，以及目前整合的遊戲與帳號網站內容。
- 低階適量減少建物、植栽、船舶與魚群，保留原有風格及主要互動；滿血原始美術保留。詳細內容見 `docs/resource-packs.md`。
- 最新封存：`build/releases/20261024-cf-0666eb774cdfdd23/`，含來源 ZIP、Windows ZIP、Cloudflare 完整發布 ZIP、`version.json` 與平台發布紀錄。最新位置另存 `build/releases/LATEST.json`。
- 本次依使用者要求不追加測試或發布後功能驗證；發布成功依 Cloudflare deploy 回報。Git 暫存、提交與推送維持原狀。
- 回退目錄 `build/cloudflare-device-interaction-20261023/` 保留；回退需沿用完整登入 Worker、Durable Object bindings 與既有 migration。

---

# 校園交流花園整體更新 — 2026-10-23

本機專案已完成五區縮距、連接環道、建築與植栽整理、照明／水面、互動HUD、鏡頭與避障導覽。廣場到各入口縮短31–38%；40座留言裝置保留獨立固定地址與近距離操作。

- 最低環境273,068三角形（原962,594），14網格／106 surfaces；共同貼圖、裝置MultiMesh、分幀建立與背景角色預載已整合。RX5700XT暖啟最大幀由231–238ms降到66–73ms；中心仍比原版多18draws，沒有任意最低硬體皆流暢的保證。
- 實際連續步行338／338、近柱鏡頭12,544樣本零穿入；裝置契約105、場景整合112、導航85與新增自由探索避障53項全部通過。標準／最低版28張遊戲實拍已檢查。
- 新Windows輸出：`build/windows-discussion-overhaul-20261023/LittleWorld.exe`；模型、腳本、shader與layout核對通過。Web最低版已驗證不載入標準環境，這輪尚未部署新3D內容至正式網站。
- 本輪沒有變更原WordKing Cloudflare、Firebase、使用者帳號或資料。

詳見[整體更新與驗收](docs/discussion-overhaul-20261023.md)、[效能數據及限制](docs/discussion-render-pipeline.md)。以下為先前更新歷史。

---

# 跨裝置移動負載與自動效能保護 — 2026-10-21

瀏覽器版已部署至原星途網址，build `cf-128fa286e43bff69`、來源 `packs-7398aa350089301f`、Cloudflare version `94e7a583-2f86-48f0-a770-f336508fd643`。

- 最低檔全平台、手機低檔與自動保護直接使用烘焙世界漫遊，不再載入整區細節。保留 527 永久碰撞體、24 座位、六入口；省略近景裝飾與動態細節演員。六入口相同材質／像素的隔離渲染 draws 降 25–49%、三角形提交降 25–36%。
- 持續前景過載自動啟用保護，沒有型號白名單或新畫質選項；最高 30 FPS、閒置八秒後 15 FPS，恢復輸入即醒。儲存偏好與物理 tick 保持，HUD 顯示實際限制。手機降解析度後本次執行不再自動升回。
- 低檔小地圖底圖最多 5 Hz、導航 20 Hz；同路線累積 CPU 桌面減約 89%，compact 減約 44%。落點書房及展廳的漏套用陰影設定已修復。
- 正式本機 Web 真實移動 30 項通過：桌面約 30 FPS，4× 合成 CPU 約 29.54 FPS，手機介面觸控約 29.99 FPS；三段各約 12 秒且無 >100 ms 幀。12× 壓力注入確認自動卸載 7→0 chunks，但該段有長幀，僅作保護功能證據。手機介面使用桌面 GPU／資源格式，並非 iPhone 真機。
- 新串流 50、runtime 14、自適應 62、圖形 UI 91、室內品質 73、室內往返等 208 項通過；既有串流／材質／地圖回歸亦通過。Web desktop/mobile 各 20 包、438／436 匯入資源解碼，8 支更新腳本跨包一致。登入 Worker、DO bindings、落點來源與 Firebase 設定核對不變。
- 公開網址已完成真正冷啟動、W/S 移動、地圖開關與返回漫遊 7／7 驗收；10 路徑內容 SHA256 核對通過。未測實體 iPhone／舊電腦的長時間幀率、耗電與溫度，沒有「任意裝置必定流暢」結論。本輪未重建 Windows 執行檔，未操作 Git commit／push／staging。

詳細：[實作與驗收](docs/low-end-runtime-20261021.md)、[交付紀錄](deliverables/low-end-20261021/delivery.json)。回退保留 `build/cloudflare-minimap-performance-20261020/`，需使用其原完整登入 Worker 設定。

---

# 小地圖提交瓶頸與同畫質快取 — 2026-10-21

已更新正式星途網址，build `cf-ffd112c5d2c569f4`、來源 `packs-57cfcbe5ad52ae62`、Cloudflare version `d8f87613-f2c1-401b-a427-2b70a6511c0a`。本次追查上一輪 low／mobile 沒有變快的原因，固定像素／AA 做同程序 A/B/A；沒有變動畫質設定、可見模型或世界著色器。

- 找到主要成本之一是 HUD 小地圖 retained commands 每幀仍提交數百次繪圖。改為按實際物理像素的 SubViewport 快取，內容變動才重建，導航獨立更新；保留原字型、線條 AA 與更新頻率。高 DPI 分數位置修正後，三尺寸像素對照最大通道差 2/255。
- 原生靜止場景 draws 1042→397；Web 標準 HUD 958→313、手機 compact HUD 638→274。Web compact 移動同路線各 4 秒／80 refresh／79 重畫有效，root viewport render CPU 中位數相鄰 A 平均 1.45→0.90 ms；呈現仍約 60 Hz，沒有 FPS 提升主張。
- **未解決**：原生移動時底圖重建幀約 15.5 ms，沒有下降；Web 標準 HUD 移動階段因長幀無效，不作改善證據。手機 HUD 在桌面瀏覽器驗證，不是老手機長時間 FPS／耗電／溫度測試。
- 離屏線段篩選候選雖少 58–65% 頂點，但 GDScript 掃描反而更慢，因此只留測試 fixture，未加入產品。材質合併候選未經有效收益驗證，亦未加入。
- HUD 進度改用輕量查詢，戶外啟動完成後停止 10 Hz 的下載快照跨 JS 查詢及歷史深拷貝；室內按需載入保持獨立。120 項載入測試通過。
- 小地圖快取 73 項、投影 35,562 面／320,058 coverage probes、實際世界對齊等回歸通過。Web desktop/mobile 各 20 包、438／436 個匯入資源通過；10 個公開路徑的 HTTP／內容與登入 headers 驗證通過。
- Windows 新包 `build/StarPath-Windows-Minimap-20261020.zip`，280,128,246 bytes、22 檔；CRC／逐檔 SHA256 通過，ZIP SHA256 `4fde82b5d6d38633059778827857533547be3f4a8c688d6e29707df0b599d539`。三平台四支腳本與 21 個封版來源檢查通過。

公網首開仍待完成：截至 00:12 首包 31.6／46.1 MB，傳輸極慢但有前進、無瀏覽器錯誤，故未將小型公開路徑的成功誤記為線上遊戲畫面驗收。完整本機正式輸出的操作驗證已通過。

詳細：[同畫質效能驗收](docs/minimap-render-performance-20261020.md)、[交付索引](deliverables/render-budget/minimap-delivery.json)。上一版 Cloudflare／Windows 包保留，登入與落點來源未變。本輪未操作 Git 提交、推送或 staging。

---

# 全畫質幾何與背景負載清理 — 2026-10-20

已部署至既有星途 Cloudflare 網址，build `cf-bf1907d93039df49`、來源 `packs-93e6276151a31be6`、Cloudflare version `ca78cabe-a836-45cb-8180-293784d385da`。使用者要求不綁手機型號，保留既有畫質；本輪沒有下調各檔原有解析度、AA、陰影或可見物件密度。

- 所有畫質共用精確地形分區與保守球體遮擋剔除；原幾何／UV／法線／材質及碰撞保持。離屏投影來源保留，快速換側與剔除快取邊界已有檢查。
- 匯出副本移除 222 個永久隱藏的舊來源節點，涉及 113,078 個實例三角形；491 個碰撞與全景可見模型面數不變。這是資產及節點清理，不能直接當成逐幀省下的面數。
- 練功區完整細節減少 8,077 面，啟動替代版減少 7,357 面；落點書房減少 142 面，大學展示組件減少 10 個退化面。安全的閉合不透明表面啟用背面剔除，可編輯 Blender 來源保留。
- 真正背景／Windows 最小化時停止繪圖，暫時最多 10 FPS；返回後恢復使用者設定。iframe 焦點不觸發停繪。原生實際最小化／恢復通過；自動化 Chrome 未產生真正的 hidden 事件，所以 Web 背景流程仍待真實事件驗收。
- 原生最高檔四個有效水岸視角的 primitive 提交減少約 15%～24%，其中溪谷 GPU 中位數約減 19%。兩個受帳號 modal 干擾的基準排除。low／mobile 的部分 GPU 耗時反而略增，同程序 A/B 未證實為保留投影資格造成；不能宣稱每檔普遍變快，更不能換算成手機 FPS。
- 世界剔除 20 項、實際幾何／材質 1,892 項、串流 44 項、世界建置 4,900 項、座位 86 項等檢查通過。42 張世界前後圖與 29 張室內／座位圖未見新增缺面。Chrome 四檔切換、恢復原解析度／2× MSAA 與移動通過。
- Web 兩套輸出各 20 包、436／438 個匯入資源驗證通過；378 個發布檔、9 個分片原檔重組 SHA-256 通過，10 個公開路徑 HTTP／內容與登入 headers 驗證通過。Firebase 與登入 Worker 來源未變。

Windows 新包：`build/StarPath-Windows-Performance-20261020.zip`，280,123,936 bytes、22 檔，CRC／逐檔 SHA-256／發布清單通過。ZIP SHA-256 `ad3ae9343820f79eba0f72e5a0da1716539ce610abd5558ebf2aeda1d5523839`。

詳細證據與限制：[效能驗收](docs/graphics-performance-20261020.md)、`deliverables/render-budget/`。沒有手機真機持續幀率、發熱與耗電證據，不能宣稱任意老機最高畫質皆流暢、不過熱。上一版發布目錄 `build/cloudflare-admissions-studio-final-20261020/` 與 Windows ZIP 均保留，可用含原登入 DO bindings／migration 的設定回退。本輪未操作 Git 提交、推送或 staging。

---

# 落點分析工作室與 Firebase 整合 — 2026-10-20（歷史紀錄）

已完成可行走的 Blender 工作室、一般大學／特殊招生／APCS 三個獨立工作桌，以及帳號／成績紀錄入口。一般大學排除 APCS 校系，APCS 桌只顯示採 APCS 的校系；桌面上不提供跨分類切換，需關閉後走到另一張桌。特殊招生保留原站官方管道資料，未虛構原站未收錄的錄取計算。

- 八個椅子／沙發座位支援 E 坐下與起身，桌邊坐著可按 F 開啟工作桌；關閉後還原座位及鏡頭。依使用者最後更正，茶杯只有擺設，沒有喝茶或茶杯互動。
- 填分區可直接選擇已儲存的模擬考／自行練習紀錄；保留目前年度及校系條件。新增、更新與另存分開，留白不轉成零分，輸入與試算不自動新增考試。
- 正式 Firebase `star-path-75457` 使用 Spark、Firestore `asia-east1`；本人資料規則、索引與 Cloudflare 登入交接服務已部署。專用簽章私鑰已放 Worker secret，本機下載副本已刪除。遊戲場景不接收 Firebase 憑證。
- 房間 61 項、座椅整合 86 項、連續走動／鏡頭 64 項檢查通過；完整網頁遊戲實測進入房間、開關特殊桌、移動、坐下與 F 操作。背景頁籤曾出現關閉後重繪延遲，輸入後恢復，未將此宣稱為前景效能驗收。
- 正式 Email 瀏覽器操作與 Firestore 讀寫、權限、原子交接協定測試通過；測試資料與測試帳號已清理。帳號連結、Email 註冊／信箱驗證／重設密碼、取消登入與錯誤恢復、Windows 配對中關閉／取消／到期／錯誤配對及重試、實際手機完整操作仍待驗收，不能宣稱所有測試完成。
- 正式 Google 瀏覽器登入已驗收：使用者完成登入，CUA 確認正式帳號頁顯示預期使用者、電子信箱已驗證與登入方式 Google。證據：[驗收紀錄](build/admissions-evidence/google-browser-acceptance.json)、[登入後畫面](build/admissions-evidence/google-browser-signed-in.png)。
- Windows 登入交接及同帳號跨裝置成績同步於 2026-10-20 記為「使用者實測通過」：使用者在得知這兩項仍待實測後回覆「我測過了 可以」。agent 未獨立重跑，也未據此認定異常配對流程通過。證據：[使用者驗收回報](build/admissions-evidence/user-native-sync-acceptance.json)。
- 網站來源 r4 已封存至 `integrations/admissions/`，150 檔與全新上游 clone/apply 驗證通過。結果／說明頁切換年度保持原頁的修正已納入。
- 正式 Windows WebView host 13／13 檢查通過，包含三個頁面實際載入、Esc IPC 關閉與重用同一視窗；登入交接與同帳號同步另以使用者實測回報記錄驗收。

最終發布包為 `build/cloudflare-admissions-studio-final-20261020/`，build `cf-cb6f04660e3ab7c3`，來源 `packs-c84d10340059ec60`；已發布至既有 Cloudflare 網址，version `d2c4d339-d909-42a7-84ac-01f4008af54e`。八個公開路徑 HTTP／內容 SHA-256／登入相關 headers 驗證通過，正式版本與證據見 `build/admissions-evidence/`。Windows 完整包為 `build/StarPath-Windows-20261020.zip`，22 檔 CRC／來源比對通過，SHA-256 `78d6e5437611c2172865605fc204edaab842db56c4dfd72e54deaec709dd357c`。

詳細已驗／待驗範圍與保留 DO migration 的回退流程見 `docs/admissions-release-acceptance.md`。原 GitHub Pages 未修改；本輪未操作 Git 提交、推送或 staging。

---

# 練功區抖動、路牌與世界距離修正 — 2026-10-18（歷史紀錄）

使用者再次確認：保留目前人物與建築的相對大小及正常走路節奏，縮短各區間的實際距離。下方 2026-10-17 的「0.4 倍人物仍走 3.8 m/s」是已修正的舊設定，不能再當作正常步速。

- 戶外人物與資產維持 0.4 倍；走／跑使用原始人物尺度的 3.8／6.4，換算實際世界為 1.52／2.56 m/s，步頻與原室內人物一致。沒有加速動畫、物理時間或人物。球半徑 24→21.6，製作半徑 60→54，相鄰區中心距離 37.70→33.93 m（縮短 10%）。完整道路、海岸、橋梁、串流區塊與地圖已重建。
- 大學區中央原有路面間隙補上實體鋪面，避免正常步速撞上路緣。實際控制器 24 趟雙向跨區行走全數通過，耗時 22.40–25.05 秒；174 項檢查確認每條實際路程比修正前短、地面連續，且未跑步或中途傳送。不能沿用舊版加速後的 10 秒數字宣稱正常行走時間。
- 練功區鏡頭和角色顯示共用插值位置，鏡頭先跟隨位移，再平滑轉向／避障；起身與傳送重設插值。原先 45／90 FPS 下約 3.6–4 cm 的鏡頭距離振盪，原生實測修正後低於 0.002 mm。30／45／90 FPS 都通過。213 項家具／閱讀互動與 44 項室內往返檢查通過；往返測試退出時仍有既有資源清理警告，不能聲稱整次程序零錯誤。
- 橋梁、步道與入口牌的支桿止於牌面下緣；橋牌與步道牌提供兩側正常朝向文字。110 項牌面／支桿檢查及原生正反面實拍通過。
- 載入期簡化背牆原有破碎條紋，初始場景改用既有完整背牆幾何，沿用內嵌啟動材質，不預載整個細節包；只增加約 75 KB。完整來源模型未修改。
- 手機／桌面 Web 已重建，兩版各 19 包、416／418 個匯入資源掛載通過；發布包 `cf-dfe7e29832db62ff` 的 152 檔案及 9 個分片原檔 SHA-256 重組驗證通過。此處不代表手機真機幀率驗收。

已部署至 https://star-path-little-world.star-path-little-world.workers.dev/ ，Cloudflare 版本 `7e6e69ed-e89b-4dae-9796-85dc23fb1b24`。線上版本清單一致，6 個入口／資源清單 SHA-256 一致，150 個公開資源皆回應 200；`_headers` 是伺服器設定，不作公開資源驗收。

本輪原生畫面與前後量測：`deliverables/world-correction/`，線上驗證見 `public-verification.json`，交付紀錄見 `delivery.json`。本輪未操作 Git 提交、推送或 staging。

---

# 手機畫面、移動與人物比例更新 — 2026-10-17（歷史紀錄）

已部署至既有免費 Cloudflare 網址：https://star-path-little-world.star-path-little-world.workers.dev/ 。本輪沒有操作 GitHub、推送、提交或修改 Git staging。

- 戶外球體半徑 24，場景與人物同為 0.4 倍；碰撞、跳躍、鏡頭及座椅互動一致縮放。走路 3.8／跑步 6.4 不變，相鄰區 24 趟實測約 10～11 秒；室內保留原尺寸。
- 手機／平板隱藏桌面側欄，使用收合選單、虛擬搖桿、螢幕安全區、全圖視窗與全螢幕入口，新增 standalone manifest。全螢幕成功進入及手機真機 FPS 尚未驗證。
- 移動顯示插值、緊湊小地圖、手機植被與地面可見性，以及背景下載預算與依賴重試修正；不以桌面量測保證手機順跑。
- 發布套件 `cf-d73e2d2b92ac5688`，Cloudflare 版本 `d21e2aef-8d02-4bdc-98f3-159650b66905`。完整檢查與線上驗證見 [本輪報告](deliverables/mobile-smooth-screen/README.md)。

以下保留 2026-10-14 歷史紀錄，並非目前尺度或 GitHub 操作指示。

# 球形生態世界重建與展館行走鏡頭 — 2026-10-14

**使用者要求先推送備份，後續繼續。** 原始碼與已生成的世界已納入本次備份；新版 Web／Windows 發布與瀏覽器驗收尚待完成。完整驗證數字與接續步驟見 [重建備份進度](docs/world-redesign-checkpoint.md)。

統一Globe、Neighborhood、Stations、串流細節、碰撞與地圖的世界座標。保留完整六方向球面與12條跨海連接，半徑48→600m；10m距離的地面下降從1.04m降為8.3cm，20m為33.3cm。

六區擴展為濱湖草甸、岩岸港灣、砂岩高地、山地針葉林、秋季混合林與蘆葦濕地。手工地形脊線12–28m、外圍湖泊、岩層、林群和山徑皆有實際地形碰撞；港灣保留碼頭與船舶的水域。海岸、外湖與步道共用資料產生小地圖。

重建48棟建築外觀、3款真尺寸車輛、3種船舶與4種樹木；新車船、植物可編輯Blender來源與生成器包含於儲存庫。18輛道路車依真車長避讓；船舶使用完整船體尺度及碼頭繫纜。六站抵達區、入口、招牌與01–06地圖站號同源。展館相機修正位置平滑與注視點不同步造成的行走震盪。小地圖的共線清理改用線性流程並剔除視野外球面區域，保留原投影精度。

實際原生GPU畫面與驗證報告保存在本機 `deliverables/world-redesign/`、`deliverables/vehicles/`、`deliverables/vessels/`；重建來源與操作方式見 `game/README.md`。發布前須重建Web與Windows包並驗證來源一致。

---

# 練功區家具互動、閱讀與湖岸石修正 — 2026-09-29

湖邊原本皺裂狀的物件是 `bank_stones` 岸石，原網格變形過大並有反向面。已改成三顆低矮圓石，更新大世界原有 37 組配置；地形、水面、植栽與其餘世界配置保持不變。前後實拍及接地檢查在 `deliverables/lake-bank-revision/`。

沙發保留曲面、縫線與抱枕並放大 16%；沙發與閱讀座約 0.57 m 坐面，依實際椅墊深度校正坐姿，避免膝腿穿入。12 個座位均可 E 坐下／起身；坐著仍可環顧，电競椅可 F 開關面前螢幕。坐姿鏡頭排除該座位碰撞代理，並於起身還原原視角。

書架 E 開啟 13 本書的選擇介面。選定後角色拿起該本書、雙手托住打開的書，書架上原物件暫時隱藏；E／Esc 或關閉按鈕闔上並歸還，移動與原視角恢復。所有書頁目前保持空白，沒有新增書籍正文。

地圖換成梵谷 1889 年《星夜》（《星空》）完整公版圖像；新增閱讀毯、落地燈、茶具、玄關陶器、掛鐘與植物浮雕。投影、三台電腦、六扇展示門與閱讀燈支援開關；畫作可放大欣賞，三組擺飾可旋轉檢視。單字王仍只有一台，原神六格展示位仍留空。

原生 Godot OpenGL 驗證：家具／書籍 227 項、其他物件 91 項、世界 E 往返與移動 48 項均通過；沒有 ERROR/WARNING。實際畫面確認了坐姿、持書、畫作、櫃門、燈具與擺飾檢視。記錄位於 `deliverables/training-room/interaction-checks.json`、`props-native-report.json`、`capture-report.json`。功能測試成功不代表各裝置的練習內容已完成。

最後再以對角坐姿校正沙發轉角，15 項局部原生检查通過；電競椅側面 17 項检查確認桌下空間。完整 227 項報告另保留於 `interaction-full-native.json`。Web 已重新匯出（PCK 176,279,832 bytes），實際掛載輸出包核對 `layout.json` 雜湊與最終來源相同，包含轉角 0.66 m 前移定位；本輪完整操作與外觀驗證使用原生 Godot，沒有宣稱瀏覽器已重新跑完全部流程。

最新 GLB 為 17,401,164 bytes、275,739 三角面、152 網格、25 材質、22 件家具碰撞，含獨立互動零件及內嵌畫作。可編輯 `.blend` 與改前版本均保留。操作及重建說明見 `art/TrainingRoom/GAME_INTEGRATION.md`、`INTERACTIVE_ART.md`；本輪交付與輸出雜湊见 `deliverables/training-room/interaction-delivery.json`。

---
# 練功區牆面、名稱與投影修正 — 2026-09-29

空間統一稱「練功區」；世界目的地、入口牌、室內 HUD 及 Blender 背牆均已同步。「單字王」是唯一已製作的練習裝置，六格原神展示位保持空白。

東側原本空白拱線牆改成木作閱讀牆，包含書櫃、軟墊長椅與區域導覽。長椅座面、牆板及頂棚分別設碰撞，中央動線與東側通道均可通行。

裝置的螢幕、光束、文字、網格及底座燈環使用分開的藍色材質。Godot 光束不投射實體陰影，底座保留實體陰影；局部藍色補光與鏡頭光暈呈現投影來源。降低頂燈強度並朝下照明，移除先前的天花熱點與地板過曝。

可編輯來源 `art/TrainingRoom/WordKing_TrainingRoom_Game.blend` 與 `game/assets/training_room/` 已同步。最終 GLB 為 268,963 三角面、73 網格、24 材質，家具碰撞共 19 個。原始黑藍版母檔保留。

驗證：`revision-after-report.json` 的 33 項原生檢查通過；`capture-report.json` 的 48 項完整原生檢查通過，含真實 E 輸入往返兩輪、角色移動／跳躍、世界與音樂狀態還原。前後固定鏡頭圖在 `deliverables/training-room/revision-{before,after}-*.png`。色彩比較僅作診斷，房間背景仍採遊戲的米白木色風格。

Web 匯出已更新，PCK 為 171,460,960 bytes；HTTP 預覽可啟動並以 Tab 進入世界。本轮完整 E 往返及房間外觀驗證使用 Godot 原生 OpenGL，沒有宣稱內嵌瀏覽器已完整重測。產物雜湊與驗證範圍見 `deliverables/training-room/revision-delivery.json`。

---

# 練功室接入與遊戲風格調整 — 2026-09-27

`game/` 已將單字練功區世界入口按 E 接至 `scenes/training_room.tscn`。室內入口傳送門按 E 回到同一世界節點及原位置，保留朝向、相機與音樂設定。其他五站原入口行為保留。

新版美術為米白／霧面石地／木色／青綠軟包／淡金，維持 20×18 m、一台裝置、六格空櫃及精細沙發。可編輯母檔 `art/TrainingRoom/WordKing_TrainingRoom_Game.blend`，原黑藍版保留。GLB 為63個合併網格、20材質、245,607三角面；家具代理碰撞含斜向桌櫃與L沙發兩段。

驗證：室內控制器10項、完整流程headless41項、真實OpenGL流程48項通過，無error/warning；最後一輪調亮度與HUD字重後重新跑48項並產生7張遊戲實拍。見 `deliverables/training-room/`。Chrome實際透過目的地選單到練功區，按 E 成功進入室內且可拖曳鏡頭，console無error/warn。瀏覽器返回流程未完成自動驗證，桌面版已連續兩輪實測返回；瀏覽器世界總覽採樣約1 FPS，不能視為流暢效能驗收。瀏覽器截圖曾暫時呈黑，重新聚焦畫面恢復。

主 Web 匯出更新於 `build/web/`，本機預覽：<http://127.0.0.1:8765/index.html?v=training-room>。詳見 `art/TrainingRoom/GAME_INTEGRATION.md`。練功題目／帳號與原神展示模型不在本次接入範圍。

# 五首循環背景音樂接入 — 2026-09-26

使用指定對話「生成循環背景音樂」的五首原始 OGG，已完整加入 `game/assets/audio/music/` 並重新匯出主遊戲。預覽：<http://127.0.0.1:8765/index.html?v=20260926-music>。

- 世界總覽／櫻花林與其他未另配樂區域：《星球漫遊》96 秒。
- 落點分析：《靜光座標》；練功區：《蓄力迴路》；推薦區：《精靈羅盤》；輔導室：《暖窗絮語》，各 120 秒。
- 原檔不轉碼、不變速；循環 offset 為 0，換曲交叉淡化 1.8 秒。同區不重頭播放，海岸邊界停留 0.75 秒才換曲，明確傳送立即選曲。
- 右上角新增曲名、靜音與音量控制，預設 40%，設定會保存。Web 首次輸入後開始播放；背景暫停並接續，功能入口面板中配樂維持。
- 51 項音樂管理／五首真實 OGG 循環解碼測試、36 項實際世界區域／HUD 測試、12 項真實瀏覽器播放／操作驗證通過；71 個資源、14 個場景靜態驗證無錯誤／警告。五首下載原檔與遊戲副本 SHA-256 一致，瀏覽器已確認每首有非靜音輸出且無警告／錯誤。

完整記錄：`deliverables/music-integration/README.md`；曲目設定：`game/data/music_tracks.json`；管理器：`game/scripts/world_music.gd`。外部網站維持既有入口預覽，本次未部署網站或推送。前空翻修正版 GLB 雜湊保持不變。

---

# 前空翻精修與落地衣襬回落 — 2026-09-26

正式遊戲角色資產已更新為 `game/assets/character/graduate_jump.glb`；可編輯來源為 `art/Graduate/Male_Graduate_Frontflip_Refined.blend`。原 GameReady 母檔與 Idle／Walk／Run 資產 SHA-256 保持不變；前空翻舊版及控制程式備份在 `deliverables/frontflip-refined/before-20260925/`。

- 重做起跳蓄力、連續翻轉曲線、收腿與展身、屈膝落地；空中段 0.72 秒，落地回落段 1.20 秒。
- 以 Blender 重力／慣性及身體、手臂碰撞模擬衣襬與袖口，經低模褶皺修整後烘焙。落地後衣襬繼續回落；0.28 秒後逐漸銜接移動骨架，保留完整布料尾段與行走相位。這是可匯出的物理烘焙，並非即時布料解算。
- 跳躍與世界整合 117 項通過；68 個資源、14 個場景檢查無錯誤／警告；Web 已重新匯出。
- 實際 Godot WebGL 站定側面及移動正面逐格驗證均為 PASS、errors 0；212 幀製成 30 FPS、7.07 秒影片。完整主世界也已實際 Tab 進入漫遊、Space 空翻並接地回復，瀏覽器無 warning／error。
- 本機主遊戲：<http://127.0.0.1:8765/index.html?v=20260926-frontflip>。逐格回放：<http://127.0.0.1:8766/index.html?qa=1>（Standing／Moving 重設，Play 播放）。服務需保持執行。

預覽：`deliverables/frontflip-refined/frontflip-refined-preview.mp4`；關鍵影格：`deliverables/frontflip-refined/frontflip-refined-contact-sheet.png`。完整證據與重建順序見 `deliverables/frontflip-refined/README.md`。本次原生圖形裝置無法建立，因此最終視覺驗證使用 Codex 內建瀏覽器；逐格錄製不代表效能基準。倒立中兩幀保留小於 3.7 mm 的低模碰撞探針殘差，未宣稱所有姿態完全無穿插。本輪未公開部署或推送。

---

# 可見游標拖曳、完整動線與全域美術複核 — 2026-09-25

最新來源為 `game/`，本機輸出為 `build/web/`。新版預覽：<http://127.0.0.1:8765/index.html?v=20260925-authored>。本輪先審核既有畫面與人物尺度，再修配置、重建並用實際 Godot 畫面複核。下方舊輪次保留作歷史，不能代替本次結果。

## 本次修正

- 左／右鍵按住拖曳時保持游標可見；不鎖定、隱藏或重設位置。放開、離開視窗、失焦與開啟介面時結束拖曳。總覽兩軸可完整旋轉，球體變換、畫面球心、相機距離和 FOV 保持固定；按住拖曳時忽略滾輪輸入。
- 漫遊旋轉維持使用者選定的距離。鏡頭進入建築時淡出整個外殼；櫻花枝幹和花卡一起處理，生態樹只暫時隱藏擋住人物的單株，視線清除／切回總覽後恢復原配置。這些處理不改物理通路。
- 櫻花庭園改成明確橋口、閉合環路與兩個帶護欄的觀景凹位；座椅朝海並退開通道。木橋保留完整 2.7m 使用寬度，欄杆避開市街人行道，兩端與石路接續。
- 六區建築、路燈和家具按完整人行道、公共步道與前庭校正。48 棟建築門面依實際網格修整到至少 2.05m 高、0.95m 寬，保留原始 GLB；修正一棟基座侵入河道的建築。全基座對岸線也納入驗證。
- 林地與街燈改為可檢查的固定配置：62 棵生態樹、60 組低矮植被／岸石，保留 18 棵庭園標本樹；櫻花园 12 棵。統一長椅、路燈、鋪面與建築明度，入口與碼頭告示牌都有繁體中文字及正確朝向。
- 小地圖共享實際櫻花園岸線、環路和觀景平台；箭頭按人物模型朝向旋轉，地圖方位保持穩定。區域名稱優先判斷實際島嶼範圍，修正生活區步道誤標為櫻花林。
- 修復靜態 MultiMesh 在無視窗建造時遺失位置矩陣：花朵與落花以原始位置資料在執行時上傳。最後重拍的櫻花園 04／06 未再出現巨大青色帶。

## 已完成的原生驗證

| 範圍 | 結果 |
| --- | --- |
| 最終靜態檢查及匯出 | 64 個檔案、14 個場景，0 錯誤、0 警告；Web 重新匯出及授權檔打包通過 |
| 全區通路及家具退讓 | 129 項通過，74,780 次人物膠囊掃掠、37,970 次地面探測 |
| 世界功能／跨島與水岸設施 | 118 項／101 項通過 |
| 固定球心、游標、距離、建築遮鏡 | 17 項通過 |
| 生態樹逐株遮擋及恢復 | 17 項通過 |
| 靜態花朵及落花保存／重載 | 780 項通過，原矩陣保留 |
| 建築岸線 | 48 棟、143,478 個基座取樣通過；最小水岸距離 0.616m |
| 小地圖 | 基礎 39 項、區域名稱 38 項、櫻花配置 35 項通過；652 個位置的投影及裁切覆蓋檢查通過 |
| 畫面複核 | 44 張重新拍攝：19 張真正人物漫遊視角、1 張花園配置俯視、24 張全區／市政入口／水岸視角 |

Web 的 18 項既有操作及 66 項新增可見游標檢查全部通過，errors=[]。左右鍵各以三次連續拖曳累計旋轉約 470°，未要求或進入 Pointer Lock；球心、球體變換、相機距離與 FOV 保持固定，放開後游標沒有跳位。結果見 `deliverables/world-polish-browser-review.json` 與 `deliverables/visible-drag-browser-review.json`。

實際圖片位於 `deliverables/authored-garden/`、`deliverables/authored-streets/`、`deliverables/authored-world/`。審核過程、修正前後判斷與取景限制見 `deliverables/world-art-review.md`。以 `python tools/capture_authored_review.py` 重拍，以 `python tools/verify_authored_world.py` 順序重跑檢查與匯出。

目前仍採用風格化低面數素材。部分自然步道的材質層次、遠端目的地引導、重複樹冠與立面仍有提升空間；本次通路、鏡頭及畫面檢查不等於 3A 資產品質或完整商業效能驗收。素材、字型及引擎原文授權隨 Web 輸出放在 `THIRD_PARTY_NOTICES.txt` 與 `licenses/`。

---

## 以下為先前修訂紀錄

# 世界路網、水岸、碼頭與小地圖精修 — 2026-09-25

專案：`game/project.godot`。本機 Web 輸出：`build/web/`。本輪修改前來源備份：`deliverables/world-polish-before/`。

## 本輪完成

- 六區共用 `world_routes.gd`，補齊 12 座跨島橋與 24 個引道；橋梁有連續護欄、甲板側緣、接縫及碰撞。擋住商務區西引道的商店移至 `[-24,-6]`，保留通店步道。
- 商務區新增獨立曲岸碼頭：5.4 m 寬木甲板、三側護欄、開放入口、兩張座椅、繫船柱、救生圈、照明告示及釣魚船。植栽避開碼頭和船隻，額外留出樹冠淨空。
- 乾路／木棧道共用球面投影、路線取樣與接縫，過河路段不再疊上灰色路面；WordKing 及 life 相連步道合併以共用轉角。前庭路面與主步道分層，消除共面三角閃面。
- 六區入口補上石材鋪面、長椅、花台；標線依真實步道與前庭連接位置產生並退讓路口。木棧道欄杆、標線及細部物件按材質合併網格。
- 小地圖保持地圖方位穩定，箭頭跟隨人物模型實際朝向，包含側走／倒退；水域依河岸輪廓填色、沿球面細分並裁切；顯示真正的全部跨島橋與碼頭輪廓。
- 左／右鍵按住拖曳與放開停止、選單優先處理滑鼠、失焦釋放等操作保留。

## 已完成驗證

- `game/tests/results.json`：118 項通過，含六區路面、棧道、角色操作與左右鍵控制。
- `game/tests/infrastructure_results.json`：101 項通過；7,484 次 ray 探測、12 橋全寬接地與護欄、24 次完整雙向行走，碼頭 66 段護欄 ray 及 64 次角色膠囊接頭掃描。
- 小地圖基礎 39 項通過。額外球面投影回歸：652 個位置、19,062 個水面、16,144 個裁切面及 171,558 個覆蓋探針，三角化及水域遺失／新增錯誤均為 0。
- `deliverables/world-polish-final-static.log`：41 個資源、14 個場景實例化，0 錯誤、0 警告。
- `deliverables/world-polish/`：第二輪原生 Godot 24 個視角，含六區全景、六區入口、六區自然景觀、碼頭兩向、河道、濕地轉角、校園溪流及跨島橋；已逐圖複核並完成獨立視覺審查。
- Web 已重新匯出，`index.pck` 為 122,169,816 bytes。Chrome 18 項真實輸入檢查全數通過，errors=[]；涵蓋左鍵拖曳／放開停止、固定地圖與旋轉箭頭、WASD、選單，以及 1200×800／960×640 畫面。結果記於 `deliverables/world-polish-browser-review.json`。
- 可重跑 `python tools/verify_world_polish.py`；各階段紀錄為 `deliverables/world-polish-final-*.log`。本機預覽服務需先啟動。

本輪沒有公開部署或推送。場景仍沿用既有風格化低模素材；此處的功能與畫面驗證不代表已完成效能基準測試。

---

## 先前輪次紀錄（以下數據與方向設定已由本輪更新）

# 獨立街區、紅屋頂住宅與生態景觀 — 2026-09-24

專案：`game/project.godot`。原始附件、素材包、角色及早期 Blender 母檔均保留。

## 新增：左上角小地圖與左鍵拖曳

- `game/scripts/world_minimap.gd` 依現有配置快取 2D 地圖，顯示道路、步道、水域、建築、六站入口及櫻花林。角色置中、面向朝上，包含街區名稱及 10 m 比例尺；最高每秒更新 10 次，不增加第二次 3D 場景渲染。
- 小地圖置於左上角標誌下方，目的地選單在下方展開並可捲動；原本的站點及自然景點入口均保留。
- 左鍵按住可拖曳世界總覽及漫遊視角，右鍵功能保留。左鍵開始拖曳經 GUI 處理後才接收，避免選單點擊誤轉相機；放開、失焦及切換模式時結束拖曳。
- 118 項世界功能檢查通過，包含六站（南北極）小地圖位置與朝向、左鍵按住／放開／失焦；專案靜態及執行診斷均 0 錯誤、0 警告。1280×800、960×640 的總覽及漫遊 UI 報告均 0 重疊、0 超出畫面、0 零尺寸。
- 驗證記錄：`deliverables/minimap-tests.log`、`minimap-validation.json`、`minimap-runtime-diagnostics.json`、`minimap-ui-1280-result.json`、`minimap-ui-960-result.json`。UI 報告工具本身有 enum cast 警告，來源是技能工具而非本專案；另以專案專用驗證器確認乾淨診斷。
- Chrome 真實滑鼠操作通過：左鍵按住拖曳世界總覽、放開後不再旋轉、漫遊時左鍵拖曳轉向、左鍵點目的地選單不啟動相機拖曳，errors=[]。畫面已檢查，見 `deliverables/minimap-web-roaming.png`、`minimap-web-menu.png`；記錄為 `minimap-browser-review.json`。Web PCK 已更新為 111,740,364 bytes，本機網址仍為 `http://127.0.0.1:8765/index.html`。本輪 Chrome 採樣約 3 FPS，並非效能優化成果。
- 修改前的 UI 與相機程式備份在 `deliverables/minimap-before/`。

## 後續修復：道路與步道接縫

- 依 2026-09-24 14:47 截圖修正湖邊道路轉彎處的三角露底。根因為各段矩形路面獨立結束，缺少外側接角。
- 六區環形道路及自然步道使用共用接角和一致細分的球面網格；棧道板面、扶手與碰撞同步接合。修改回填建造程式，已重建 `generated/` 與本機 Web 匯出。
- 102 項世界檢查全部通過；新增轉角內外側完整寬度的碰撞探測及湖邊道路雙向實際行走。靜態驗證 31 個資源、0 錯誤、0 警告，見 `deliverables/seam-validation.json`。
- 原生 Godot 實際近景已成功擷取並檢查：`seam-lake-road-after.png`、`seam-lake-path-after.png`、`seam-boardwalk-after.png`。本次原生顯示可正常啟動；下方的顯示驅動失敗紀錄保留為上一輪歷史。
- Chrome Web 匯出複驗通過：三處自然近景、實際步行約 3.78 m、errors=[]，見 `deliverables/seam-browser-review.json` 與 `seam-web-0/4/5.png`。本次 PCK 為 111,730,400 bytes，本機預覽為 `http://127.0.0.1:8765/index.html`。
- 修復前的來源程式與畫面備份在 `deliverables/seam-fix-before/`。本次未調整角色、尺寸、街區資料或公開發布網站，也未進行效能優化。

## 本輪內容

- 球體半徑由 36 m 調整為 48 m，表面積增加約 78%。建築、角色與車輛沿用米制尺寸，未隨球體放大。
- 六份獨立城市配置：湖畔市政中心、曲岸商務碼頭、文化步行院落、溪谷大學校園、林蔭慢行住宅、濕地創業工坊。道路輪廓、建築座標、庭院和場館入口各自不同。
- 48 棟建築；其中六棟改用第一版房屋的磚紅屋頂修改版。18 輛汽車沿各區自己的道路路線行駛並讓行。
- 四處湖泊、兩條溪流／河口，地表依岸線裁切，水面不提供行走碰撞。跨水的指定步道有板縫、欄杆和碰撞。
- 76 棵榿木、白樺、柳樹、松樹，以及 536 組蕨類、香蒲、岸石；依林地或水岸條件放置，避開步道。全部是本專案用 Blender 製作的原創植物／岸石模型，使用枝條、彎曲葉片及頂點色，非掃描素材。
- 保留 14 棵精製櫻花樹、動態落花、船隻、魚群、球面移動、右鍵視角、海岸阻擋及 E 跳躍淡出。
- 修正放大後櫻花橋的公園端銜接；修正無頭建造時批次植物變換資料未保存的問題。植物按區域分組，編輯器及遊戲載入時上傳位置。
- 新增「自然景點」選單，直接選擇六處自然目的地。

## 重建與素材

- `game/data/districts.json`：各區 loop/roads/paths、urban_buildings、civic、water、habitat、visit。
- `game/tools/urban_design.gd`、`ecology_world.gd`：街區、地形與自然景觀建造。
- `tools/author_ecology_blender.py` → `art/Ecology` / `game/assets/ecology`。
- `tools/red_roof_houses.py` → `art/RedRoofHomes` / `game/assets/kenney/suburban-edited`。原始 UV 與牆面保留，綠屋頂材質改為磚紅。
- 原始素材授權仍位於各素材包；新增原創幾何與修改说明位於兩個新素材資料夾的 SOURCES.md。
- `tools/plan_biome_world.py` 可重設本版配置，會覆寫後續人工配置，重設前會自動備份。

## 驗證

- `game/tests/results.json`：88 項通過、0 失敗。包含六區場館圓台退讓車道、六區不同配置、六處自然景點落地、步道與棧道連續、水面無隱藏陸地、沼澤棧道轉彎實際行走、櫻花橋完整往返、海岸阻擋、站立不飄移、球面重力與場館跳躍返回。
- `game/validation.json`：30 個腳本／場景／shader 資源，0 錯誤、0 警告。
- 新版 Web 匯出完成（index.pck 106,852,040 bytes）。Chrome 實際擷取六區街景及四處自然近景，確認批次植物已正常顯示。截圖為 deliverables/district-0.png 至 district-5.png、ecology-0/3/4/5.png 及 biome-world-overview.png。
- Chrome 實際操作通過：右鍵旋轉、步行、E 進場淡出、Escape 返回；`deliverables/ecology-browser-review.json` 記錄 errors=[]。本輪未重跑 Edge，不沿用上一版結果宣稱新版 Edge 已驗證。
- `deliverables/parcel-clearances.json`：48 棟實際模型占地在切平面配置中的車道重疊數為 0，最小退讓約 0.5 m；另已做實際場景畫面與碰撞檢查。
- **效能限制：** 本輪 Chrome 操作採樣約 4–6 FPS，仍不流暢；這次亦遇原生 Godot 顯示驅動初始化失敗。功能通過不代表效能達標，尚需後續效能優化或在正常 GPU 環境重測。
- 原生畫面擷取遇本機 OpenGL／ANGLE 顯示初始化失敗，未將此誤報為場景腳本錯誤；本輪改以實際 Chrome WebGL 畫面複查。

## 保留的限制

場館仍是入口預覽，網站與帳號尚未整合。汽車為環境交通，不可駕駛。樹木是風格化植物幾何，非寫實掃描。瀏覽器首次需載入引擎與大型角色資源，本輪不承諾所有裝置的幀率。

---

<!-- recommendations-local-20261025 -->
# 選校研究所推薦系統 — 2026-10-25（本機候選，整合驗證進行中）

- 以完成量表或手選學類，搭配單份成績建立 115 年校系推薦；提供興趣／均衡／成績三檔排序，同層只按校系編號陳列。缺資料另列，沒有錄取率或心理適配百分比。
- TypeScript host 已完成按需資料載入、64 校大學館對照、原生面板協定、私人設定與校系收藏；Firestore 僅做本機 emulator 驗證，未發布正式規則。
- Typecheck、7 檔 70 項單元／回歸、2 檔 11 項 emulator 測試通過；/admissions 靜態網站建置成功。房間、原生／Web bridge 與候選包驗證另行追加，不由這些結果代替。
- 架構、演算法、資料界線及後續證據見 [推薦室技術說明](docs/recommendation-room.md)。
