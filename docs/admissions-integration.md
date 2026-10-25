# 星途落點分析與帳號

整合網站沿用 `stu310101-arch/113-115-admission-screening`，正式路徑為
`https://star-path-little-world.star-path-little-world.workers.dev/admissions/`。
原 GitHub Pages 網站不由這套發布流程修改。

## 遊戲內工作空間

落點分析站進入可行走的分析室，設一般大學、APCS 校系、特殊招生三個工作台，入口有共用成績紀錄台。桌面用有框操作螢幕保留周圍 3D 空間，手機保留較小場景邊界以確保表單可操作。關閉操作螢幕回到工作台前；離開分析室再回到外部入口原位置。

特殊招生工作台只使用現有來源支援的資訊與官方入口；不以一般大學門檻假裝計算警大或其他特殊管道的錄取結果。

## 程式與資料

- `admissions-site/` 是獨立上游 checkout；可重現來源與整合 patch 存在 `integrations/admissions/`。
- 網頁版由 `tools/web_account_bridge.js` 按需載入同源 `/admissions/host/`。
- Windows 使用 `account_native_host.gd` 與獨立 `user://starpath_account/webview`；不共用圍棋 profile。
- `account_session.gd` 只接收登入狀態、顯示名稱與開關事件。UID、密碼、ID token、custom token 與配對兌換密鑰留在網站執行環境。
- Firebase 專案 `star-path-75457`；Firestore `(default)` 位於 `asia-east1`，使用 Spark 方案。
- 成績存於 `users/{uid}/examAttempts/{attemptId}`；未來性向調查與輔導資料沒有開放存取規則。

## 發布順序

1. 在 `admissions-site/` 跑原站測試、新增成績測試與 Firebase Emulator 規則測試；部署 `firestore.rules` 及 `firestore.indexes.json`。
2. 在 `services/native-auth/` 執行 `npm test`、`npm run typecheck`、`npm run dry-run`。
3. 確認 `admissions-site/public/firebase-config.json` 只有公開 Web SDK 欄位。以 `/admissions` base path 建置靜態網站。
4. 用 `build/python-env/Scripts/python.exe tools/build_web_release.py --godot <Godot 4.7.2 console> --node <Node 24> --local-only` 建置兩種網頁遊戲。
5. 執行 `tools/prepare_cloudflare_release.py`，提供 `--admissions-source admissions-site`、`--admissions-out admissions-site/out`、`--auth-worker services/native-auth/.build/index.js` 與公開 `--auth-vars` JSON；輸出到新的發布目錄。
6. Worker 公開變數只含 `PUBLIC_ORIGIN`、`FIREBASE_PROJECT_ID`、`FIREBASE_API_KEY`、`SERVICE_ACCOUNT_EMAIL`。簽章私鑰使用 `SERVICE_ACCOUNT_PRIVATE_KEY` Worker secret，不放進 JSON、Git 或遊戲包。
7. 使用該發布目錄的 `wrangler.jsonc` 部署。站台檔案會驗證 SHA-256；網站來源 commit、修改後來源雜湊及輸出雜湊存在 `admissions-source.json`。
8. 以 `tools/build_windows_release.py --godot <Godot> --preset "Windows Standard" --output <新目錄>` 產生 Windows 包，保留前版。

世界 service worker 的預先下載清單排除 admissions 網站；Firebase 與網站不增加首次進世界的必要下載項目。
登入交接 API 位於 `/api/native-auth/`，所有回應禁止快取。配對五分鐘到期，原子兌換一次；custom token 另有短效時限。

## 驗收與回退

應驗證桌面與手機瀏覽器，以及 Windows WebView2：Google／Email 登入、儲存／更新／另存／刪除、分頁歷史、帳號切換、跨平台同 UID 資料、關閉返回位置與焦點。模擬器結果不能替代正式 Google 登入與真實雲端同步。

Windows 專用 smoke 為 `game/tests/account_native_smoke.gd`，只用獨立 QA profile；完整登入需要正式 Worker 與 Firebase 設定。

`services/native-auth/scripts/live-smoke.mjs --production` 會建立兩個一次性 `example.invalid` 測試帳號，測試正式 Firestore 權限、成績與登入交接，並在 finally 清除測試資料和帳號。它只輸出通過項目，憑證留在記憶體。2026-10-20 已另外確認正式網站的 Google 瀏覽器登入成功，帳號頁顯示預期使用者、Google 登入方式及已驗證信箱，證據見 `build/admissions-evidence/google-browser-acceptance.json`。同日使用者回報 Windows 登入交接及跨裝置成績同步實測通過，記錄於 `build/admissions-evidence/user-native-sync-acceptance.json`；這兩項正常流程以使用者回報為證據，未由 agent 獨立重跑，也不代表所有異常流程與手機回歸均已驗收。

先前公開網站的發布檔保存在 `build/cloudflare-20261018-world-correction/`。新增 Durable Object migration 後，不應假設可以直接回到 migration 前的 Worker version；回退時應將保留的前版靜態網站與目前 DO 綁定一起部署，不刪除 Firebase 資料或 Durable Object namespace。Windows 則發回保留的前版完整資料夾。

正式部署紀錄與可見驗證證據存放於 `build/admissions-evidence/`；只有實際完成的驗證才記為通過。
