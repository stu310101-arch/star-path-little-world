# 本機共用帳號驗證

此流程啟動正式遊戲入口，仍須建立帳號、登入及選擇身分。帳號、留言與進度寫入本機 Firebase Auth／Firestore 模擬器，不修改正式 Firebase 設定、不部署網站，也不碰原 WordKing 服務。模擬器關閉後，未另行匯出的測試資料會消失。

先在 `admissions-site` 使用既有相依套件完成新版靜態網站；WordKing／圍棋資產須先由專案根目錄的 `python tools/package_wordking.py` 準備，再執行 `npm run build`。

在第一個 PowerShell 終端執行：

```powershell
Set-Location admissions-site
$javaRuntime = Join-Path $env:USERPROFILE '.codex/cache/starpath-jre21/jdk-21.0.12.1+1-jre'
$env:PATH = "$javaRuntime/bin;$env:PATH"
npx firebase emulators:start --only auth,firestore --project demo-starpath-tests
```

在第二個 PowerShell 終端執行：

```powershell
Set-Location admissions-site
$env:STARPATH_EMULATORS = '1'
node scripts/serve-preview.mjs
```

網站只監聽 `127.0.0.1:4317`；它從最新 `out` 目錄供應 `/admissions/`，並僅對本機回應模擬器設定。Auth 使用 `9099`、Firestore 使用 `8080`、模擬器管理服務使用 `4400`。

第三個終端從專案根目錄啟動遊戲：

```powershell
python tools/run_local_account_game.py --check-only
python tools/run_local_account_game.py
```

啟動器檢查網站及兩個模擬器，再為此 Godot 子程序設定 `STARPATH_DEV_HOST_ORIGIN=http://127.0.0.1:4317`。本機 WebView 使用獨立資料目錄。Godot release export 會忽略這個變數；只有 debug engine 接受精確的 `http://127.0.0.1:PORT` 或 `http://localhost:PORT`，不接受其他來源、路徑或查詢字串。

上方 Java 路徑是本工作區已安裝的 JRE 21；若系統本來就能執行 `java`，可省略這兩行環境設定。

測試時可用任意本機測試信箱建立帳號及設定身分。本機 emulator 模式在 native 視窗直接顯示 email 註冊／登入，正式 native 仍採原有瀏覽器配對。確認初始未登入不能透過 Esc／Tab 進入世界；登入後第五站進入五區場景；留言及回覆可選匿名；關閉視窗可繼續移動；切換帳號或登出會立即鎖住遊戲。兩個瀏覽器工作階段可共用模擬器資料來驗證不同帳號的公開留言與私人進度隔離。

此流程驗證新版實作與本機規則，不能代替正式環境驗收。2026-10-23 已另行更新正式星途帳號網站與規則；一般 Godot 編輯器 F5 使用正式服務，只有下述啟動器設定的子程序使用本機模擬器。詳見 `docs/account-login-fix-20261023.md`。

自動原生整合驗證可執行 `python tools/run_local_account_game.py --smoke-test login`。`--smoke-test garden` 另外經正常第五站入口驗證真實留言／回覆、原生 IPC、裝置互動與返回；兩者均在本機 emulator 建立一次性帳號並經實際登入表單通過門檻，完成後刪除該 Auth 帳號。花園測試會留下已刪除的測試留言位置，直到模擬器關閉。
