# 2026-10-23 正式登入入口修正

使用者從 Godot 編輯器 F5 啟動新版入口，仍連到正式舊版帳號頁。舊頁可完成登入，但沒有新版必填身分與 session generation，Godot 拒絕該封包後持續鎖住遊戲。這是遊戲與網站發布版本不一致，並非使用者密碼錯誤。

已發布新版帳號網站到既有星途 Worker `star-path-little-world`，version `840994f3-026b-410e-818e-f90f0478b715`。`tools/patch_account_release.py` 要求原發布包與公開 manifest 完全相同，再只替換 admissions 網站及相應 manifest；156 個遊戲檔案和 auth Worker／DO 設定保留原內容。既有世界 build ID 維持 `cf-128fa286e43bff69`，帳號更新另記於 `account_update`。

Firebase 僅更新星途專案 `star-path-75457` 的 Firestore rules，SHA-256 `211f20bf0bbaf1e78ef01aaee03dd2371e3846f8a5bedd8e6803be61b387b867`；編輯器草稿與本機通過測試的規則雜湊完全一致。新增 collection 索引 `discussionThreads`: `zone ASC, createdAt DESC`，ID `CICAgJiUpoMK`；保留既有成績索引。沒有修改原 WordKing 的服務、設定、帳號或資料，也沒有替使用者建立或改寫身分資料。

Godot 現在會對舊版 signed-in 封包顯示可重試的版本錯誤，關閉帳號視窗後也保留原因。登入門檻仍要求伺服器確認身分，沒有加入訪客入口或偽造登入狀態。

驗證：178 項網站測試、28 項 Firestore Emulator 規則測試、17 項原生 host 邊界檢查、12 項遊戲 gate 檢查通過；TypeScript 與 production build 通過。正式六個公開路徑和發布包逐位元組一致。使用者選擇高中生，親自完成重新登入／配對與身分設定，並回覆「已進入遊戲」。實際遊戲畫面已確認能進入交流花園。正式發文與跨裝置資料同步仍未在本輪完整驗收。

發布包與證據：`build/cloudflare-account-login-20261023/`。原服務使用 session persistence，重開遊戲仍需重新配對；這次未改為長期保存登入憑證。模擬器與正式帳號仍分開。

回退時可使用保留的 `build/cloudflare-low-end-20261021/wrangler.jsonc` 及其完整舊網站／auth Worker，或回到先前 Worker version `94e7a583-2f86-48f0-a770-f336508fd643`。但舊 host 不支援新版登入門檻，回退網站時需同步使用舊版遊戲入口；不可單獨回退後讓新 gate 再次卡住。規則保留版本歷史，不刪除資料或重設帳號。
