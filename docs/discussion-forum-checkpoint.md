# 校園生活誌：技術檢查點（2026-10-23）

**使用者已撤回提案等待條件，授權直接實作 3D 場景；正式製作與整合已恢復。**

第五站 `life` 的五區為大學交流、科系交流、未來就業、高中生發問、校園生活。先前花園場景屬於使用者否定的內部測試素材，已由新的五種分區環境取代製作方向；不能把舊場景當成最終美術。新的 Blender 腳本分別製作湖畔步道、紅磚工作室街、現代城市露台、橡木書屋林園與石灰岩拱廊噴泉庭院。五區已由 Blender 匯出 GLB 並整合到 Godot。已修正森林區旋轉角度污染、裝置落入屋內／背向步道、入口花台阻擋連接道路，以及地面過曝；實際畫面與具碰撞的連續步行皆已驗證。使用者尚未對最終畫面作新一輪主觀美術評價。

使用者最新指示為「算了 都可以了 你直接實作3D場景吧」，因此不再等待 15 張提案的逐張選定。已生成的 A1–A3、B1–B3 六張參考圖保存於 `art/DiscussionGarden/proposals/`；[美術來源清單](../art/DiscussionGarden/art-manifest.json) 記錄原生成路徑、雜湊、五區方向、留言裝置材料與既有植物／貼圖重用。原生成檔均保留；各區實作選擇依使用者授權完成，不表示使用者曾逐一選定某張編號提案。

## 已保存的技術內容

2026-10-23 後續修正：全部 40 座留言裝置已改為獨立固定地址，空裝置靠近可發文，已有留言可閱讀／回覆，關閉面板自動更新該區。Godot 105 項、原生 E2E 16 項、瀏覽器裝置 E2E 11 項、Vitest 含規則 210 項、Web bridge 10 項通過。正式留言頁已更新，詳見 [獨立留言裝置紀錄](independent-discussion-devices.md)。以下較早的驗證數量保留為先前里程碑。

- 共用 Firebase 帳號、必填公開暱稱與四種身分；雲端確認後才能通過遊戲入口。身分可在帳號設定修改，畢業生不另設資格限制。
- 五區論壇：每頁 8 則主留言、每頁 20 則回覆；主留言 2000 字、回覆 1000 字；逐則匿名選項仍顯示身分；作者編輯及刪除占位。
- 公開留言只保存顯示欄位，不含 UID、信箱或穩定作者識別碼。私人作者權限與留言以交易共同建立；帳號切換會使舊操作失效。
- Web／原生 host 協定提供身分狀態、分頁留言與大學館進度；Godot 不接收認證憑證。每包上限 4096 UTF-8 bytes，預覽 120 字，分頁項目包含 index。
- WordKing 同源副本及 Go 使用星途私人資料庫；大學館收藏與探索進度依帳號儲存。舊資料只透過使用者明確操作匯入。

`admissions-site/` 是獨立、被根目錄忽略的來源 checkout；可重建內容保存在 `integrations/admissions/integration.patch` 與 `source-manifest.json`。`tools/snapshot_admissions_source.py` 使用暫存索引，不更動實際 Git index。WordKing 整合包由 `tools/package_wordking.py` 從本機唯讀來源產生，包內 manifest 固定來源 commit 與檔案雜湊；`wordking-source/` 僅是本機來源副本。

## 已執行驗證

- TypeScript typecheck 通過；Next production build 通過，包含 `/forum`。
- Vitest：178 項通過；另 28 項 Firestore Emulator 測試通過，涵蓋成績、身分、論壇作者權限、匿名資料限制與私人遊戲進度。
- Web account bridge：9 項通過，涵蓋來源驗證、敏感欄位移除、過期帳號回應及封包限制。
- 新增帳號／論壇模組局部 ESLint 通過；完整 lint 仍有既有 React effect/ref 規則與 WordKing 原始 UMD 模組問題，未將完整 lint 宣稱為通過。
- WordKing／Go 帳號 A→B→A 的本機瀏覽器 fixture 與行動版 WordKing 已由整合代理驗證；這不是生產帳號測試。
- 真實本機 Auth／Firestore 瀏覽器 E2E：14 項通過，使用正式 Web bridge、host 與 repository，未 mock 儲存層。涵蓋註冊、四身分、暱稱更新、主留言、另一帳號匿名回覆、帳號切換、原作者編刪、回覆作者編刪，以及 390px 手機版；沒有頁面錯誤或正式服務網路請求。測試腳本為 `tools/check_forum_emulator_browser.cjs`，報告與截圖位於 `deliverables/discussion-forum/`。
- 原生 WRY 視窗本機 E2E：16 項通過，實際 React 註冊／身分設定後由 host IPC 解鎖遊戲，經正常第五站轉場、Firestore 真實寫入匿名主文與回覆、3D 裝置頁、開啟實際討論、返回大世界及登出鎖定。一次性測試帳號與留言已清理；這不是正式配對服務測試。
- Godot 連續物理步行：196 項通過，五區道路中線及左右各 1.35 公尺往返、控制點及森林區八座裝置；實走 1,334 公尺，相機碰撞 0。桌面／390×844 直式畫面檢查通過。結果與資產雜湊在 `deliverables/discussion-garden/qa/`，藝術重建說明見 `docs/discussion-garden.md`。
- 最終 GLB 962,594 個三角形，匯出後稽核零退化面；RX 5700 XT、1440×900 標準陰影的森林入口十秒採樣為 29.97 FPS（上限 30），不是手機或全地圖效能保證。

## 明確界線與尚待完成

原 WordKing 網站、Cloudflare／Firebase 設定、其他使用者帳號及資料均未修改；沒有提交或暫存 Git 變更。唯讀匯出工具只供使用者在自己的原帳號頁面明確執行，尚未以真實原帳號驗證。

2026-10-23 登入修正：使用者從 Godot 編輯器啟動時連到正式舊版 host，舊頁登入成功卻沒有回傳 profileReady／identity／sessionGeneration，新版必填身分門檻因而無法解鎖。已將新版帳號／論壇網站發布到星途自己的 Worker `star-path-little-world`，version `840994f3-026b-410e-818e-f90f0478b715`，同步發布 `star-path-75457` 的規則並建立 discussionThreads 的 zone／createdAt 索引。既有 WordKing 專案未接觸。原生端新增舊版 host 提示，關閉視窗後仍保留錯誤原因。

使用者選擇「高中生」、重新完成正式配對與身分設定後回覆「已進入遊戲」。六個公開路徑內容與發布包逐位元組一致；發布包保留 156 個既有遊戲檔案及原 auth Worker／DO 設定，未重發網頁遊戲的模型／PCK。正式跨裝置與正式發文／回覆完整流程仍需獨立驗收，不能由登入成功推定通過。證據見 `build/cloudflare-account-login-20261023/evidence/public-deployment.json`；發布與回退方式見 `docs/account-login-fix-20261023.md`。

本機啟動、註冊與登入方式見 `docs/local-account-game.md`；只有 loopback 且已連接 Auth emulator 的原生視窗允許直接 email 登入，正式原生流程保留瀏覽器配對。
