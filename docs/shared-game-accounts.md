# 星途帳號：單字王、圍棋與大學館進度

本次整合是獨立的星途版本。原單字王 Cloudflare／Firebase 的服務、設定、原始碼與所有帳號資料均未修改，也沒有部署到原站。`wordking-source` 是唯讀本機來源，固定上游 commit `2d446cb27775b7c2e4af2a4693fd8891650dfa58`；`integrations/wordking` 保存可還原的來源清單與空差異檔。

## 建置

必要時以 `python tools/snapshot_admissions_source.py restore --snapshot integrations/wordking --destination wordking-source` 還原來源；執行 `python tools/package_wordking.py` 產生 `admissions-site/public/wordking-app` 及 `public/games/go`，再執行 admissions 網站建置。原始單字王程式、公開單字庫和美術保留；整合版本移除原 Firebase 初始化及 CDN SDK，所有雲端操作透過持續存在的星途 host 同一 JavaScript realm repository 執行。

## 資料邊界

- 單字王：`users/{uid}/wordkingLibraries/{libraryId}`，`main` 是星途單字庫；明確匯入的資料使用來源 UID、來源 app 與完整內容的 SHA-256 形成 `import_<hash>`。相同備份重試只開啟既有資料庫，不覆寫 main 或已編輯的匯入資料。
- 每份單字王狀態包含 `userOverrides`、`customWords`、`hiddenWordIds`、`userFolders`、`settings`，保留 `isWrong` 的 true／false。JSON 以 Unicode 安全分段保存，所有分段與目前版本指標在同一 transaction 寫入；讀取的是完整且不可變的版本。完整 JSON 上限 8 MiB，錯誤會保留原資料。
- 圍棋：`users/{uid}/gameProgress/go` 保存完整棋盤、歷史、設定及死子資料，使用 revision 拒絕跨裝置覆蓋。單局完整 JSON 上限 750,000 UTF-8 bytes；保存失敗時棋局留在畫面，提供重試及檔案匯出。星途模式不自動讀寫舊的無帳號 localStorage 存檔；只有使用者按下匯入並確認，才複製到空的雲端棋局。
- 大學館：`users/{uid}/gameProgress/university`，收藏採明確 boolean（false 是取消收藏）；探索紀錄採聯集。只接受現有 `001`–`138` 編號。舊本機進度只能明確匯入，不能把雲端 false 重新變成 true。
- 所有 repository 綁定 UID 及帳號 session generation；登出、帳號切換或 profile 未就緒時停止讀寫，畫面清空私人狀態。

## 原單字王備份流程

整合版提供檔案選擇、內容數量預覽及「確認匯入為獨立單字庫」。只接受 `format: wordking-current-snapshot`、`version: 1`、`schemaVersion: 6`、`complete: true` 與全部五種目前資料欄位。原站 `exportRecovery()` 是歷史遷移資料，不代表目前完整內容，因此明確拒絕直接匯入。

`tools/export_wordking_readonly.js` 是選用的本機工具，使用者必須在自己已登入的原單字王頁面親自執行。它只讀取該 UID 的穩定 schema 6 文件，前後檢查 revision、遷移標記及登入 UID，下載完整 JSON；沒有登入操作、寫入 API 或 `persistence.load()`。整合版的「原站唯讀操作說明」提供下載連結。若來源版本、登入或瀏覽器政策不符，匯入保持不可用，不修改原站設定；可改用使用者已持有的完整備份。

## 驗證與限制

- 7 項快照／進度單元測試通過。
- 5 項 Firestore Emulator 測試通過：完整跨 realm／Unicode 分段往返、revision 衝突、重複匯入不覆蓋、跨帳號與未登入拒絕、UID 失效及 Go 匯入保護。
- Chromium 實際執行整合版 WordKing 與 Go：A→B→A 私人狀態、待複習狀態、390px 無橫向溢出、圍棋落子雲端寫入、舊本機檔案不變及登出遮罩；使用隔離 fixture，沒有正式帳號或原 Firebase／CDN 請求。畫面與報告在 `deliverables/shared-games`。
- 2026-10-23 已將新版 Firebase rules／網站發布至星途自己的專案；使用者已完成正式登入、身分設定並進入遊戲。正式跨裝置進度與共享遊戲完整流程仍待驗收，原站真實帳號匯出未執行。詳見 `docs/account-login-fix-20261023.md`。
