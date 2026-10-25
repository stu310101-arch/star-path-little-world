# 第一站暖窗書房與帳號量表（r6）

新增第一站獨立室內、量表平板及 Godot 原生填寫面板。世界的「遊戲設定 → 我的興趣量表」與房間裝置使用同一個帳號資料服務。輸入留在遊戲介面；隱藏的帳號 host 僅處理認證與 Firebase 讀寫。

## 使用方式

1. 登入星途後，選擇第一站並進入輔導室。房間只有高一、高三兩個資料區；走近對應裝置按 E 或觸控操作按鈕。
2. 高一「興趣量表」填寫六項 RIASEC（0–90 整數）；高三「學系探索量表」填寫 33 種知識分數（0–18 整數）。分數留白與 0 分分別保存。
3. 高三區內可切換「33 種知識」與「適配度與 Z 分數」。最適合及適合各有 25 個起始列，可以新增。未取得的項目可留白；開始填寫的列須有學群、學類及正負小數 Z 分數。學類保留報告名稱，重複學群／學類會提示修正。
4. 可隨時保存草稿。完成紀錄必須通過所有分數與適配列驗證。歷次紀錄可取名；依使用者最新要求，不提供或要求填寫施測日期。
5. 第一份完成紀錄自動作為未來推薦依據。其後可在「我的紀錄」選用其他已完成紀錄。修改草稿不會取代原本有效的完成版本。「我的紀錄」是獨立管理按鈕，不另設第三個測驗資料區。

本次只收集及保存量表，未自行換算 Z 分數、推斷適配門檻或實作校系推薦演算法。未納入隨身碟圖片中的個人分數。

## 資料與同步

固定代碼、量表版本與高一／高三階段對照位於 `game/data/interest_catalog.json`；網站內有逐 byte 驗證的副本，保證獨立來源封存可重建。RIASEC 對應高一，33 項知識及兩種適配列對應高三。舊協定的兩個日期欄位僅作相容保留，新紀錄為空字串，不呈現在填寫或歷史介面，也不阻擋完成保存。

- 私人路徑：`users/{uid}/interestRecords/{id}` metadata、`content/draft`、`content/complete`；選用紀錄為 `users/{uid}/interestState/main`。
- `starpath-interest` 是獨立 64 KiB 訊息通道。單份 profile 上限 60 KiB、每個適配程度最多 512 列；超限明確失敗，不截斷。列表每頁 20 筆，完整資料逐筆讀取。
- 每次寫入檢查 revision；相同 requestId 的重試具冪等性。收到成功回應後才顯示已保存。逾時保留目前輸入，較晚回覆不覆蓋後續編輯。
- 帳號 host 保有 UID、權杖與憑證；遊戲只接收經驗證的量表與狀態。requestId、sessionGeneration、回覆類型與 recordId 均核對，換帳號與登出清除舊資料。
- Firestore rules 限本人讀寫並保護版本、39 項分數及完成／草稿關係；適配列的逐列語意由 host/repository 驗證。未來推薦資料入口 `getActiveCompleted()` 重新驗證並只回傳完成版本。

## 美術與資產

已完成 r6「暖窗書房」整體重設，空間為 10.8×8.6×3.5 公尺，123,744 三角形、6 個空間網格、40 種實際使用材質，低於 180,000 三角面上限。實牆、深窗台與木框形成房間主體；左側鼠尾草綠抽屜書桌為高一區，右側杏陶色轉角操作櫃為高三區。窗邊設一組兩人沙發，裝飾集中在壁架、窗台及桌面，包括書脊與紙頁、翻開的筆記、原創成長圖、陶器、植物及一瓶立體鬱金香。窄幅摺簾、燕麥色編織地毯、中空內襯燈罩和窗光已完成。入口展示車、路中書架及舊溫室構圖已移除。

Godot GL Compatibility 使用同一套完整高階房間。地板木材與家具木材各有 3 張原生 2K PBR 貼圖，布料共 5 張 1K 貼圖，合計 11 張 canonical PNG；沒有放大素材或新增低階美術版本。家具、陶器、紙張與布料採用分開的材質。layout 保留 15 個碰撞盒（其中 1 個為相機專用）、兩個年級裝置及兩個沙發座位。模型面數與匯出結構是資產規格，不代表視覺品質或最終效能驗收。

可編輯母檔及原始貼圖位於 `art/CounselingRoom/`，執行 GLB、碰撞、座位及互動錨點位於 `game/assets/counseling_room/`。來源與修改內容見 `art/CounselingRoom/SOURCE_NOTES.md`；Poly Haven Wood Floor、Wood Table 001 與 ambientCG Fabric060 均採 CC0。原創鬱金香生成程式為 `tools/counseling_botanicals.py`。

Web 與 Windows 使用獨立 `counseling_room` 延後載入包，首次進入室內才請求；不列入高、低階主資源包的預載清單。已取得的輔導室與共用依賴在切換主包後仍保留。模型匯入產生的多餘抽取貼圖排除於發布包。兩種 Web 紋理編碼沿用相同完整房間，沒有新增低階美術版本。

## 已有證據與本次範圍

證據集中於 `deliverables/counseling-room/`。使用者要求以目前完成進度打包上傳，之後繼續追加設計，暫不驗收。因此最終 r6 未追加完整原生、材質依賴、直線動線、效能或桌面／手機 Web 操作驗收；詳細狀態見 `r6/verification-status.json`。先前帳號測試使用本機 Auth／Firestore emulators 與合成測試帳號，未動用使用者分數或正式帳號資料。

- r6 初版空間配置通過 37 項直線動線／螢幕視線檢查與 25 項 headless 房間檢查，包含兩個年級裝置、表單控制還原、216 組相機球體取樣及兩個座位。這些檢查早於最終出生點、螢幕與材質細修，僅作初版證據；報告為 `r6/blockout-direct-routes.json`、`r6/blockout/headless-checks.json`。
- r6 最終房間已正常匯入 Godot，保存並檢視 7 張原生畫面：`studio-overview.png`、`studio-beauty.png`、`entrance.png`、`desktop-journal-closeup.png`、`terminal-hinge-closeup.png`、`tulip-shelf-closeup.png`、`window-textile-closeup.png`。圖片均在 `r6/`，不能代替完整操作或效能驗收。
- 歷史表單／帳號證據保留：`form-validation.json` 的 54 項面板檢查、`account/` 的 31 項 Windows／WRY 與 15 項 Web 帳號往返檢查，以及 `web/` 的 r4 完整 Web 38 項操作檢查。此次重設未改動表單與帳號功能程式；這些仍是原版本的測試證據，不改稱為 r6 最終驗收。
- r5 房間與 Web 報告仍在 `r5/`。後續嚴格直線動線測試發現其入口書架／推車阻路，失敗基準保存於 `r5/direct-route-regression.json`；原先繞行測試的通過結果不能證明直接入口通行。
- 本次 Web／Windows 建置與壓縮封裝完成；建置工具的依賴、分包及壓縮完整性檢查屬發布流程，不等同玩家操作驗收。r6 的 7 項合成帳號準備檢查只驗證測試前置服務；服務已關閉，見 `r6/qa-services-cleanup.json`。

手機尺寸與桌面 Chromium 觸控模擬不是實體手機。實體 Android／iOS 軟鍵盤、Safari、長時間溫度與耗電須在裝置上另驗；不得將桌面 GPU 測試數字套用到手機。

r6 沒有最終效能數據。r5 原生效能報告保留於 `r5/native-performance.json`，只適用於當時的房間，不能套用到重設後的 r6。

## 發布與後續設計

目前封裝位於 `build/counseling-delivery-20261024-r6/`，Web build 為 `cf-46e7f42872298ffb`、遊戲來源為 `packs-5e19389db77eaca4`。交付資料夾包含 Windows、Cloudflare、可編輯資產三份 ZIP、Firestore 規則及 SHA-256。`packages.json`、`assets.json` 保存壓縮包資訊。版本識別已涵蓋房間模型、11 張 canonical 貼圖與匯入設定。

1. Firebase `star-path-75457` 的 Firestore rules 與 indexes 已發布成功，回覆保存在 `build/counseling-r6-firebase-deploy.log`。
2. Cloudflare 已發布成功，version `869aa1c9-1536-42d0-8575-760c9ef4ff53`，正式網址 https://star-path-little-world.star-path-little-world.workers.dev/ 。帳號 host 與遊戲同包發布，保留原 native auth Worker、兩個 Durable Object bindings 與 `native-auth-v1` migration。Windows 包使用同一正式 host。
3. 發布完成回覆保存在 `build/counseling-r6-cloudflare-retry.log`。實際版本 ID 與封存位置已寫入 `build/releases/20261024-cf-46e7f42872298ffb/version.json` 及 `build/releases/LATEST.json`；依最新指示未追加發布後功能測試。
4. 既有正式版 `cf-0666eb774cdfdd23` 的封存及 r4／r5 候選包保留。回退不刪除私人興趣紀錄或 Firebase 使用者資料。

依最新要求，先完成本版上傳與封存，再繼續追加本機設計，暫不追加驗收。後續設計須使用新的修訂紀錄，不覆寫已封存的 r6 ZIP、發布目錄或證據，也不自動覆蓋正式網站版本。

網站獨立來源封存於 `integrations/admissions/`。本次沒有 Git staging、commit 或 push。


## r7 本機追加設計（未發布、未驗收）

r6 上傳成功並封存後，已依最新要求完成一輪本機美術細修：窗下護牆、天花線板、右側淺壁櫃與書刊收納，以及扶手垂墜毯布和帆布收納盒。原有兩區、裝置、出生／出口／座位與碰撞配置維持；沿用現有材質及貼圖。可編輯 Blender 與 GLB 已保存，151,828 三角面、40 材質、6 個空間網格。

目前工作區的房間來源為 r7；正式網站與 `build/counseling-delivery-20261024-r6/` 仍固定為已發布 r6。這輪只有 Blender 作者預覽，位於 `deliverables/counseling-room/r7/`；未進行 Godot 匯入、遊戲操作、效能或 Web 驗收，也沒有重建或上傳新遊戲包。詳見 `art/CounselingRoom/README.md`。


<!-- counseling-r8-published:cf-be9d59433f64fd24:d9752512-2625-4472-b961-21569a81e55b -->
## r8 家具與可移動木椅（已發布，2026-10-24）

正式網址：https://star-path-little-world.star-path-little-world.workers.dev/ 。本輪build `cf-be9d59433f64fd24`、來源 `packs-f3106eab31bb4621`、Cloudflare version `d9752512-2625-4472-b961-21569a81e55b`，以 `build/counseling-r8-cloudflare-deploy.log` 的成功回覆為據。發布紀錄封存於 `build/releases/20261024-cf-be9d59433f64fd24/`；發行封裝位於 `build/counseling-delivery-20261024-r8/`。

沙發向窗邊移動0.25m、沙發底墊移除，圓木邊桌向入口移動0.50m。兩張電腦桌前各新增全木製椅，坐面約0.50m高，使用弧形椅背、外張椅腳與橫撐。保留4個座位、17個碰撞代理、8個空間網格、155,556三角面、40材質與11張貼圖，仍只有一套完整高階房間。

靠近木椅按E坐下；坐著可用WASD以2.6m/s帶動椅子，按E起身、F開啟量表。開啟量表等modal時停止椅子移動。高一RIASEC與高三33項知識／兩種適配資料維持原介面與本人帳號保存，沒有新增施測日期。

### 本輪實際檢查與範圍

- `r8/native-brief-checks.json`：51項通過；`r8/direct-routes.json`：23項通過。
- `r8/material-dependencies.json`：11張canonical貼圖、15個材質引用、0失敗。
- 保存11張原生PNG；主流程已查看5張關鍵圖。Blender預覽及歷史r6／r7圖像不代替本輪Godot證據。
- `r8/history/` 保留初輪fixture計時、地板排除與小縫線UV閾值修正紀錄。這些診斷記錄不與最後的通過報告混算。
- 未擴測完整帳號、瀏覽器遊戲操作、手機或長時間持續效能；上述簡短檢查不能外推為這些場景的完整驗收。
- `r8/public-release-checks.json` 實際記錄4檔公開讀回成功：HTTP200且與候選檔逐byte一致，檔案為 `index.html`、`index.release.json`、`index.packs.json`、`mobile/index.packs.json`。報告範圍：Public HTTP readback of entry and resource manifests; not a browser gameplay or account-write test.

### 封裝與部署資料

以下CRC與SHA-256來自本輪封裝工具的實際metadata；本進度腳本未重算整包hash。

| ZIP | Bytes | CRC | SHA-256 |
| --- | ---: | --- | --- |
| `StarPath-Windows-Counseling-20261024.zip` | 360,209,555 | 通過 | `38a47ce82a1a8b6aaaea4e5a853edbd1f5644cda3ccac960e8b50230b4485138` |
| `StarPath-Web-Counseling-20261024.zip` | 605,749,260 | 通過 | `26a78e68cc29d2da733ca00684dc18e512a146002fe7f11b6c7feb669d83dcac` |
| `Counseling-Assets-20261024.zip` | 104,625,700 | 通過 | `b60f17abeccc02843d0a4c958d455667e9b3674d33a6e8069d0084043dfc60d7` |

帳號host與Web遊戲同包發布；Windows完整ZIP保存在本機交付資料夾。Firebase規則與索引沿用r6已部署內容，與封存檔逐byte相同，本輪未變更。r6發布目錄、r6三份ZIP及r7設計證據均保留。r8成功後由發布記錄腳本更新 `build/releases/LATEST.json`；本段不會替換歷史章節。
