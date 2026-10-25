# 選校研究所：推薦、收藏與比較

本輪 r3 已於 2026-10-25 發布至 [Cloudflare 正式站](https://star-path-little-world.star-path-little-world.workers.dev/)。推薦依據來自已選用的完成量表或使用者自行選擇的學類，以及明確選定的一份已存成績。主候選固定為 115 學年度；113、114 年只在詳細資料作歷史對照。這是興趣方向與歷史一階門檻的整理工具，沒有計算錄取機率，也沒有將報告分數重新解釋為心理適配百分比。

## 操作與分工

獨立推薦室以「我的資料與偏好」「我的推薦」「收藏比較」三台工作台連到同一套 Godot 原生面板。量表、成績、權重模式、搜尋及結果狀態使用同一份選擇；收藏以校系為單位，可比較並連到大學館相應展位。房間、面板、轉場與實際候選包的最終驗證，另在本文末尾記錄，不以網站建置通過代替遊戲操作驗收。

空間採不對稱分區：左側書寫檔案桌、北側羅盤儀器台、右側比較展架，各有不同輪廓與工作方式；休息座位也採不同設計，不重複鏡像家具。第三版模型完整模式 98,212 三角形、低階模式 31,168 三角形，均為 13 材質。全室有五個座位，其中三張工作椅坐下後可按 F 開啟對應工作台；白色陳設移至後側櫃體，保留操作區視線。可編輯母檔、完整／低階模型與來源說明一併保存。

北側星儀使用三個獨立旋轉片段，外環、內環與軌道分別沿不同軸以不同速度運動。低階模式停止內環，保留外環與軌道；切到背景、失去焦點、開啟面板或瀏覽器偏好減少動態時暫停。HUD「暫停星儀」可手動切換並儲存偏好。

- Godot 保有顯示、操作與小型返回狀態；隱藏的帳號 host 負責 Firebase、校系資料與推薦計算。認證 UID、密碼及權杖不傳進遊戲。
- `admissions-site/lib/recommendationService.ts` 按需載入資料及引擎，每 64 筆以 `MessageChannel` 讓出事件迴圈，避免隱藏 WebView 對計時器節流造成逾時。翻頁使用同一份查詢快照，避免每頁重新排名；新查詢、換帳號與登出會讓舊快照失效，快照最長保留 30 分鐘。
- 獨立 `starpath-recommendations` 通道每封上限 64 KiB、每頁最多 20 筆。過大的列表頁減少實際筆數並正確推進游標，不截斷或丟失結果；完整條件與失敗原因逐筆讀取。
- 完整 wire 定義在 [recommendation-protocol.md](../admissions-site/docs/recommendation-protocol.md)。操作為 bootstrap、listExams、query、page、detail、saveSettings、listFavorites、setFavorite；原生入口為 `StarPathHost.recommendationCommand`。

## 推薦規則

精確命中採「學群＋學類」配對。報告的 `bestFits`／`suitableFits` 分別作為最適合／適合；自行選擇則為優先探索／也想探索。多列命中取最強程度，不因列數較多而累加。RIASEC、33 項知識與 Z 分數只呈現在說明中，不參與排序，也不自行產生 Z 分數。

內部產品排序點數為 I=2／1、A=2／1：I 表示最適合／適合，A 表示完整可判定的歷史達標／未達。三檔以整數權重計算，畫面只呈現優先層與理由。

| 情況 | 興趣較重 7:3 | 均衡 5:5 | 成績較重 3:7 |
| --- | ---: | ---: | ---: |
| 最適合＋達標 | 20 | 20 | 20 |
| 最適合＋未達 | 17 | 15 | 13 |
| 適合＋達標 | 13 | 15 | 17 |
| 適合＋未達 | 10 | 10 | 10 |

均衡的中間兩種情況同層；同層僅以 `year:programCode` 固定陳列順序，不另用學校聲望、Z、補分差距或命中數暗中打破同層。未達條件與補分仍可展開閱讀。沒有選成績時只作興趣探索，依興趣程度顯示，沒有共同優先層。

回測沿用既有 `evaluateProgram`／`evaluateAcademicCriteria`。推薦層額外檢查必要科目、APCS、官方性別組別、資料完整性與特殊條件，不單憑 engine 的 `passed` 就判定完整達標。缺資料為 pending，沒有 A 值；詳細條件的 `passed:null` 表示尚待輸入，缺科不顯示成 0，也不產生以 0 為基準的虛構補分。英聽補分使用 F／C／B／A 文字；APCS 與學測分開呈現。

不支援的特殊條件只顯示可核對部分及官方來源。各年度原始門檻保留，不把缺年的對應或官方 `--` 當成未通過，更不把歷年回測合成平均錄取率。

## 資料與帳號保存

- 115 候選有 2,206 筆校系、64 所學校。來源沿用既有 CAC 113–115 年資料與 ColleGo! 分類快照；沒有把大學館全部 138 個條目視為可回測的一般個申校系。
- `scripts/buildRecommendationCatalog.mjs` 產生 `data/recommendation_catalog.json`，保留 6,582 筆歷年分類 adapter、180 個可選學群／學類配對、來源年度與 URL，並以內容雜湊識別版本。生成時只用本機既有資料，不重新爬取或猜測校系。
- 分類只正規化全半形、空白與末尾「學類」，另保留少數明確縮寫（資工、資管、電機）。未對應的報告名稱提出提示，不以模糊系名強行命中。跨校同名推定、只有學群的 override、跨域與多系分發只列「同學群延伸」，必須切到延伸結果組查看，不混入預設精確名單。
- 招生校碼與大學館 ID 使用明確對照；115 年 64 校全部有唯一館內目標。清華招生校碼 011 對應館內 010；馬偕使用館內既有明確新名 alias 對應 064。不能直接拿招生校碼當館內 ID。
- `InterestRepository.getActiveCompletedSnapshot()` 在交易中讀選用紀錄的 `content/complete`，回傳完成內容的名稱、revision 與 selectionRevision。較新草稿不會污染推薦輸入。原 `getActiveCompleted()` 介面維持相容。
- 成績只使用選定的一次已存紀錄，不平均不同考試、不取多次最高分、不把未填變成 0。未選方向的空白 manual 快照回傳 0 筆推薦及提示，仍可查看收藏詳情以進行比較。
- 設定位於 `users/{uid}/recommendationSettings/main`，校系收藏位於 `users/{uid}/recommendationFavorites/{year}_{code}`，與大學館學校收藏分開。每次寫入有 revision，並以 requestId 建立不可改寫的 mutation receipt；相同重試不重複寫入，重用編號但更改內容會失敗。取消收藏保留 tombstone revision，避免遲到重試復活已取消項目。
- Firestore 規則限制本人存取、列表上限與版本關係；host 再驗證每個 manual 列與校系身份。新規則先在本機 emulator 驗證，再於正式網站發布前以 rules-only 部署到 `star-path-75457`；索引沒有變動。

## 已完成的技術驗證

截至本段記錄，實際執行：

- `npm run typecheck` 通過。
- 推薦、量表、host protocol、回測、成績、數 A/B 與官方性別組別共 7 檔 **70 項** Vitest 通過，其中推薦新增 **17 項**。包含三種權重、同層不暗排、缺科與 APCS、純興趣探索、保守分類、64 校館內對照、跨年度身份、分頁及帳號隔離。
- Firestore emulator 的推薦及量表共 2 檔 **11 項**通過，其中推薦新增 **5 項**。驗證本人隔離、重試冪等、版本衝突、取消收藏 tombstone、過期帳號，以及完成快照不讀取新草稿。
- 以 `NEXT_PUBLIC_BASE_PATH=/admissions` 執行 `npm run build` 成功，輸出 23 個靜態頁至 `admissions-site/out/`。建置不是發布，也不代表玩家操作通過。
- `admissions-site/tests/fixtures/recommendation-wire.json` 由實際 service／protocol 與合成量表、成績產生，供 Godot 精確 schema 驗證。fixture 包含缺科的 nullable rule；沒有使用使用者個人分數。
- 原生隱藏 host 曾因 `setTimeout(0)` 被節流而超過 25 秒；改用訊息佇列後，同一合成帳號查詢約 137 ms 回傳。新增 34 次讓出執行權均不使用計時器的測試，推薦套件目前 **18 項**通過。這是本機驗證數據，不代表所有硬體的固定延遲。
- 交付工具 `tools/package_recommendation_delivery.py` 的 **9 項**測試通過：無寫入預演、候選 SHA／大小核對、修改來源及快照拒絕、私有測試檔排除、路徑限制、建包中變更拒絕、CRC 與 ZIP 內每檔 SHA 檢查。

本機 Node 合成輸入單次量測曾得到 2,071 筆可完整回測校系約 8–67 ms；這只是開發機量測，不能當成手機或 WebView 的效能承諾。前端仍採延後載入及分批運算。

## 候選包與整合驗證

第三版整合驗證已完成原生帳號操作 **31 項**、原生面板與協定 **53 項**、bridge **17 項**，以及瀏覽器帳號準備 **20 項**與跨端回讀 **6 項**。座位／工作台與大學館往返 **29 項**、完整／低階星儀資產與動態 **28 項**通過。帳號測試僅使用本機 emulator 合成資料；證據留在 `deliverables/recommendations/` 與 `deliverables/recommendation-room/`，測試帳密及私有 session 不推送。

原生候選位於 `build/windows-recommendation-20261025-r3`，Web 發布包位於 `build/cloudflare-recommendation-20261025-r3`。最終 Web 原始版本為 `packs-5d46d01076303192`，封裝版本為 `cf-a5ad2b01262d5612`。可重建來源已推回 GitHub，包含帳號、大學館、室內與資源包等既有前置；正式網站使用同一份已驗證的 r3 發布包。

- r3 完整／低階房間各 **104 項**原生檢查通過：五個座位、三張工作椅的 F 使用／關閉保持坐姿／E 起身、17 條直達路線、鏡頭與碰撞。兩版模型分別 98,212／31,168 三角面，共用相同 layout；低階貼圖最長邊 256。
- 最終 Web **34 項**通過：桌面完整包、390×844 低階手機模擬、正常登入、進房才載入對應模型、三種排序、每頁 20 筆的上一頁／下一頁、三校系比較及返回戶外。無瀏覽器、Godot 腳本或 shader 錯誤；已查看實際遊戲畫面。這不是實體手機、Safari、熱降頻或完整純觸控驗證。
- Windows 建包來源與實際封裝內容的 SHA 核對成功。Web 全低階資源隔離檢查通過，Cloudflare 九個超過單檔上限的檔案已由真實本機 HTTP 分塊重組並逐一核對 SHA。
- 建包驗證 Python **20 項**、分包 Python **22 項**及交付封裝 Python **9 項**通過。詳盡本機證據位於 `deliverables/recommendation-room/`，可公開追溯的摘要見 [recommendation-validation-20261025.json](recommendation-validation-20261025.json)。

交付預演使用 `python tools/package_recommendation_delivery.py --dry-run`，預設讀取上述 r3 候選目錄。候選檔案須與 release manifest 的清單、SHA-256、大小一致；網站的來源清單須對應 `integrations/admissions/source-manifest.json` 的工作目錄 bytes。移除 `--dry-run` 才會在全新 `build/recommendation-delivery-20261025` 建立三個 ZIP，並寫入內容清單、provenance 與 ZIP 雜湊。既有輸出不會覆寫。

Windows 的 `Start-Local-Candidate.ps1` 用於本機模擬器測試；直接啟動 EXE 使用正式帳號 host，推薦通道已隨本次 Cloudflare 發布上線。本機測試先依 snapshot README 還原並建置 admissions-site，再從該目錄執行 `npx firebase emulators:start --only auth,firestore --project demo-starpath-tests`；另一個終端從主專案執行 `python tools/serve_recommendation_candidate.py --web build/cloudflare-recommendation-20261025-r3/site`。啟動器會核對 localhost 的 Auth 9099、Firestore 8080 及 demo 專案。合成測試帳密、私有 session、模擬器資料與測試紀錄都不列入交付包。

## 正式 Cloudflare 發布

2026-10-25 將同一份 r3 發布包上傳至既有 Worker `star-path-little-world`，Cloudflare version 為 `440e4776-8bde-4446-b397-34e2ad8e4bea`。保留 `ASSETS`、`NATIVE_AUTH`、`NATIVE_AUTH_LIMITS`、`native-auth-v1` 及既有簽章 secret。發布前版本 `793bba73-4627-481f-b6b3-f50305ff4528`／`cf-c915bee8bee26338` 保留於先前封存，沒有執行回退。

正式 Firestore 僅增加 57 行推薦規則，既有規則與索引維持原內容。讀回 ruleset `0b3893be-c68e-40a1-9502-ee6ef5daa9d4` 與本機逐 byte 一致，SHA-256 為 `c5cdacb00dd6b4e4ba5611d82795f3f8521cfd053ca9062ae8fe623bfd3cdef4`。

正式驗證 14 項通過：已發布登入頁、橋接與隱藏 host、正式成績讀取／推薦查詢、設定寫入回讀、收藏新增／取消及重試不復活。只使用一個新建合成帳號，未寄驗證信；其 Firestore 子樹與 Auth 帳號已刪除並確認不存在。外層是隔離測試頁，不能當成正式遊戲畫布或實體手機驗收。公開檔案核對及此項證據位於 `deliverables/recommendation-room/public-deployment.json`、`production-rules.json`、`production-smoke.json`，發布紀錄封存於 `build/releases/20261025-cf-a5ad2b01262d5612/`。
