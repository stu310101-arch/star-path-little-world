# 落點分析整合發布驗收與回退

2026-10-20 已將整合網站與新版工作室部署至既有 Cloudflare 網址，version `d2c4d339-d909-42a7-84ac-01f4008af54e`，build `cf-cb6f04660e3ab7c3`。公開遊戲、手機、分析 host、填分、Windows 配對頁及設定／來源清單共八個路徑均回應 200，內容 SHA-256 與發布包一致，Firebase 設定禁止快取。新版本的正式雲端成績／權限／原子交接測試亦通過，測試資料與帳號已清理。正式 Google 瀏覽器登入已由使用者完成，並以 CUA 確認登入後帳號畫面；Windows 登入交接及同帳號跨裝置成績同步已於 2026-10-20 記為使用者實測通過。下列異常流程與其餘項目仍待驗收，不能將目前狀態視為所有測試完成。

## 已有證據

| 項目 | 已確認範圍 | 證據 |
| --- | --- | --- |
| Firebase 設定 | 專案 `star-path-75457`、Firestore `asia-east1`、Spark、Email 與 Google provider、正式來源及規則部署 | `build/admissions-evidence/provisioning.json` |
| 正式雲端協定 | Email 測試帳號、部分科目／零分／英聽 F／APCS、跨帳號與非法資料拒絕、更新保留建立時間、索引查詢、同 UID custom token 登入、競爭兌換唯一勝出、取消 | `build/admissions-evidence/live-cloud-smoke.json` |
| 瀏覽器與正式 Firestore | 本機前端 `localhost:4318` 實際 Email 登入、新增／讀取／更新／另存、帶回原工作桌、刪除確認及取消、登出清除草稿 | `build/admissions-evidence/browser-cloud-acceptance.json` 及同資料夾截圖 |
| 正式 Google 瀏覽器登入 | 使用者回報登入成功；CUA 實際確認正式 `/admissions/account/` 顯示「我的帳號」、預期使用者姓名／信箱、電子信箱已驗證及登入方式 Google；不包含帳號連結或 Windows 配對 | [驗收紀錄](../build/admissions-evidence/google-browser-acceptance.json)、[登入後畫面](../build/admissions-evidence/google-browser-signed-in.png) |
| Windows 登入交接與同帳號跨裝置成績同步 | 2026-10-20 使用者在被告知這兩項仍待實測後回覆「我測過了 可以」，依上下文記為正常流程使用者實測通過；agent 未獨立重跑，未據此確認取消／到期／錯誤配對等細節 | [使用者驗收回報](../build/admissions-evidence/user-native-sync-acceptance.json) |
| 房間功能與畫面 | 實際 Godot renderer，61 項通過；7 個空間 mesh、111,744 三角形；五站、E／Esc、手機 callback、位置方向還原、返回訊號 | `deliverables/admissions-room/checks.json` |
| 連續走動與鏡頭 | 39.98m、825 幀、64 項通過；每站多組角度與距離、跳躍；鏡頭球體重疊 0 幀 | `deliverables/admissions-room/studio-walk/report.json` |
| 座椅與沙發 | 8 座、86 項實際互動檢查通過；桌面及觸控、坐姿開桌、返回座位及起身；初始鏡頭距離超過 2.5m | `game/tests/admissions_seat_integration_checks.gd`；`deliverables/admissions-room/seats/` |
| 網頁遊戲實際操作 | 本機完整遊戲 `localhost:8767` 進出特殊招生桌，關閉後恢復移動；訪客椅坐下、F 開桌、Esc 回到座位通過 | `build/admissions-evidence/game-web-room.png`、`game-web-special.png`、`game-web-seated.png`；由發布執行者實測回報 |
| 網站年度路由 | 一般／APCS 的結果及說明頁跨年度保留實際子路由；17 targeted checks、TypeScript、22 頁建置及 6 項 rendered HTML 檢查通過 | `admissions-site/tests/host-navigation.test.ts`；網站執行者封版與瀏覽器驗證回報 |
| 最終網頁候選包 | 年度路由修正已重包，靜態檔案與分片重建 SHA-256 驗證通過；build `cf-cb6f04660e3ab7c3`、source build `packs-c84d10340059ec60`，含 optional admissions_room pack | `build/cloudflare-admissions-studio-final-20261020/verification.json` |
| Windows 候選包 | exe／pck／DLL／授權與來源雜湊已生成；這不是登入驗收 | `build/windows-admissions-studio-20261019/release.json` |
| 正式部署內容 | 八個公開路徑 HTTP 200、SHA-256 與最終包一致；登入相關頁未設阻擋 popup 的 COOP／COEP；正式 Firebase config no-store | `build/admissions-evidence/public-deployment.json`；2026-10-20 09:52:46 UTC 驗證 |
| 正式 Windows WebView host | 13／13 通過：query／scores／account 的實際文件、固定 heading、desk/year/native context，bounded viewport、trusted ready、Esc IPC、關閉隱藏與重用原 WebView；未執行登入與成績讀寫 | `build/admissions-evidence/native-host-smoke.json` 及 `.log`；`host_ui_acceptance=true` |
| 公開遊戲啟動 | Chrome 實際從正式網址下載分片、啟動引擎並顯示星球總覽；觀察時 console warn/error 為空，未以此宣稱手機效能 | `build/admissions-evidence/public-game-overview.png` |

上述正式雲端協定及 Email 成績操作測試使用可清理的測試帳號及資料，證據記錄測試資料與帳號已清除。瀏覽器測試尚未點擊永久刪除最後確認；確認及取消已驗證，實際刪除由授權測試資料 REST 清理驗證，兩者不能混稱為完整 UI 刪除驗收。

背景 Chrome 頁籤曾在 Esc 關閉 iframe 後延後重繪；點擊與起身後恢復正常。程式與日誌未發現停止 render loop 或場景暫停，較符合背景節流；仍不能把這次背景操作宣稱為前景流暢度驗收。

## 仍需完成的驗收

1. Google／Email 帳號連結、Email 註冊／信箱驗證／重設密碼；取消登入與錯誤提示須回到可重試狀態。Google 瀏覽器登入成功已驗收，不代表這些延伸流程已通過。
2. Windows 登入配對的異常與中止流程：配對中關閉視窗、取消、到期、錯誤配對及失敗後重試。正常登入交接與同帳號跨裝置成績同步已有使用者實測通過回報，這些細節尚未明確回報。
3. 正式桌面與手機瀏覽器完成成績新增／更新／另存／永久刪除、歷史分頁、切換帳號清除前帳號畫面；關閉表單後檢查角色位置、朝向、焦點與手機觸控。
4. 真實裝置回歸圍棋、練功區及返回世界；本機窄視窗截圖不能取代真實手機瀏覽器，原生 WebView 佈局 smoke 與使用者回報的正常登入也未涵蓋登入異常流程。本輪包已核對圍棋 HTML／wrapper、WRY、練功區 layout 與目前來源一致，既有回歸證據保留，沒有冒稱重新操作所有既有遊戲。

以上項目只能在取得相應證據後改列通過。provider 已啟用、API 測試通過與網站已上線，是三個不同狀態。

## 來源與發布追蹤

上游固定為 `31d5a8ed4ebac38dda78195cef4ee4993f1b9704`。整合來源封存在 `integrations/admissions/`；每次修正網站都重新封存，發布只能使用最新封存對應的 `out/`。

`source-manifest.json` 的 `source_sha256` 是 Git canonical bytes，`working_tree_sha256` 是擷取當時工作目錄 raw bytes。候選站台的 `admissions-source.json`／`verification.json` 以 raw source inventory 計算，應對照 `working_tree_sha256`，不可誤比 canonical SHA。

年度修正封版 r4 含 150 個來源檔案；原工作目錄 bytes 驗證通過，`build/admissions-restore-verification-r4/` 從 HTTPS 上游全新 clone、套用 patch 及完整 inventory 驗證通過。

| r4 雜湊 | SHA-256 |
| --- | --- |
| integration patch | `bccfb6d16fdaf770ec250465b4ad435b32c93882b8bdabd8093555c1ff151fb0` |
| canonical source | `c311280c10d7cac566b5c8785bb08c3f50aa88f5947cc142c925826feddf2f2c` |
| raw working tree | `e43ff216d5bc8516f0335b75deaa13a668ee4ed5cf78272747768ba5c8ab14c0` |

最終候選包的來源 SHA 已與上述 raw SHA 一致。Windows 包另依 `release.json` 核對遊戲程式、模型與 metadata；它透過正式網址使用網站。

## 回退方式

已保留前版靜態網站 `build/cloudflare-20261018-world-correction/site/`，build ID 為 `cf-dfe7e29832db62ff`。登入交接已另行分階段部署，`build/cloudflare-auth-stage-20261019/wrangler.jsonc` 直接使用這組舊靜態檔案，並保留目前兩個 DO bindings、`native-auth-v1` migration 與 auth Worker。其已記錄 version ID 為 `71ddaf15-a083-4d89-bba1-8def59088b61`。

若新版整合發生問題，以保留的 auth-stage 設定重新部署舊靜態網站；不要直接拿 migration 前的純靜態設定覆蓋現有 Worker。執行前先核對該設定的資產路徑、Worker 檔與公開環境變數仍存在，並使用已設定的 Worker secret，無須重新產生或輸出簽章私鑰。

回退保留 Firebase 使用者、Firestore 成績、已部署安全規則與 DO namespace，不做資料刪除或降權。舊網站不提供新版分析室入口；已發出的新版 Windows 包可能因 `/admissions/` 不再提供而暫時無法登入，應同步改發保留的前版完整 Windows 資料夾，不能混用不同版本的 exe、pck 與 DLL。

回退後需再確認公開站台 build ID、桌面／手機進世界及既有圍棋／練功區；正式回退時間與結果同樣記錄在 `build/admissions-evidence/`。本文件只列出可執行方式，尚未執行回退。
