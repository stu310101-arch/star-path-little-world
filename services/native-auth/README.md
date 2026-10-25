# 星途 Windows 登入交接

此 Worker 與既有 Cloudflare Static Assets 共用正式網域，只處理 `/api/native-auth/`。
其餘路徑交由 `ASSETS.fetch`。服務不讀取或保存考試成績；成績由已登入的網頁直接存取 Firestore。

## 部署接點

- 在本目錄執行 `npm ci`、`npm run typecheck`、`npm test`、`npm run dry-run`。
- `wrangler deploy --dry-run --outdir .build` 產生 `.build/index.js`；由總發布流程複製到發布包，設定 `main` 指向它。
- 正式 Wrangler 必須包含本目錄 `wrangler.jsonc` 的兩個 Durable Object bindings 與 `native-auth-v1` SQLite migration。
- Static Assets 設 `binding: "ASSETS"`、`run_worker_first: ["/api/native-auth/*"]`。遊戲下載仍由靜態資產服務處理。
- 變數 `PUBLIC_ORIGIN` 必須是實際 HTTPS origin，沒有尾端斜線；`FIREBASE_PROJECT_ID`、`FIREBASE_API_KEY` 與前端使用相同 Firebase 專案。
- 設定簽章服務帳號的 `SERVICE_ACCOUNT_EMAIL`；私鑰以 `wrangler secret put SERVICE_ACCOUNT_PRIVATE_KEY` 輸入 PEM，或由受控部署憑證渠道寫入。不得放進網站、發布 manifest、版本庫或命令列參數。
- Google 的 `accounts:lookup` 需接受這把 Firebase API key 的伺服器呼叫；若前端 key 有 HTTP referrer 限制，服務端請使用同專案、僅允許 Identity Toolkit API 的專用 key。
- 未完成正式設定時 API 回覆 `503 {"error":"not_configured"}`，不產生假登入或示範憑證。
- 本服務停用 Worker observability，不記錄 request bodies、Authorization、verifier 或 token。其他外部日誌工具也不得擷取上述內容。

## HTTP 契約

所有回應都是 JSON、`Cache-Control: no-store`。錯誤為 `{ "error": "machine_code" }`。
除 `status` 外均為同 origin 的 `POST application/json`，必須攜帶精確 `Origin: PUBLIC_ORIGIN`。
服務不提供跨網域 CORS，也不接受 URL 中的認證資訊。

| 路徑 | 輸入 | 回應 |
| --- | --- | --- |
| `create` | `{verifierHash}` | `201 {requestId,code,approvalUrl,expiresAt}` |
| `status?requestId=...` | GET，隨機 requestId | `200 {code,status,expiresAt}`；無 UID 或憑證 |
| `confirm` | `{requestId,code}`，Authorization Bearer Firebase ID token | `200 {status:"confirmed"}` |
| `exchange` | `{requestId,verifier}` | `202 {status:"pending"}` 或 `200 {customToken}` |
| `cancel` | `{requestId,verifier}` | `200 {status:"cancelled"}` |

`verifier` 是 Windows host 隨機產生的至少 32 bytes base64url 字串（43–128 字元）。
`verifierHash` 是這個字串 UTF-8 bytes 的 SHA-256 小寫 hex（64 字元）。
原 verifier 只留在 Windows host 記憶體，`create` 僅提交 hash；不可放入網址、Godot bridge 或本機偏好設定。
瀏覽器開啟 `approvalUrl` 後讀取 `status`，顯示配對碼及明確「確認連結」按鈕；不可自動確認。
Windows 同時顯示配對碼，使用者核對後才在瀏覽器確認。Google OAuth 僅在系統瀏覽器執行。

Windows 每兩秒兌換一次；遇 `429` 退避至少十秒，`410` 立即終止。
`401` 表示登入已失效，`403` 表示來源／配對碼／密鑰不符。
關閉登入時呼叫 `cancel` 並清除本機 verifier。交接總效期五分鐘，不因輪詢而延長。
Custom token 有效六十秒，host 立即交給原 WebView 的 Firebase `signInWithCustomToken`，不得傳給 Godot。
一次性保證來自 DO 原子消耗交接資料，而不是 custom token 自身。
若兌換回應遺失或簽章暫時故障，須重新建立配對；不得重播已消耗的交接。

## 驗證與安全邊界

`confirm` 先限制每筆最多五次嘗試，再核對配對碼。服務驗證 Google RS256 簽章、issuer、audience、sub、exp、iat、auth_time，
並向 Firebase `accounts:lookup` 檢查 UID、disabled 與 validSince 撤銷時間。等待 Google 期間取消或逾時，確認不會覆寫已關閉狀態。
`exchange` 在真正的 SQLite transaction 中重查效期、密鑰和狀態，先消耗再簽章，競爭兌換只有一方成功。
DO 不保存 ID token、custom token 或原 verifier；成功／取消後立即清除 UID，五分鐘後 alarm 刪除全部交接儲存。

預設限制：每個 IP 每分鐘建立 10 筆、其他請求 300 次；每筆交接每分鐘最多 90 次請求。
IP 以 SHA-256(IP + minute) 對應兩分鐘短效 DO，不保存 IP 原文。校園共用出口若需調整，先觀察拒絕率再調整限制。

測試在 Cloudflare workerd 內使用真 SQLite DO，Google 外部請求由測試攔截，簽章金鑰每次測試臨時生成。
這些測試不替代正式 Google 帳號、Windows WebView2、Firebase 專案及 Cloudflare 網域端對端驗證。

參考：[Firebase token 驗證](https://firebase.google.com/docs/auth/admin/verify-id-tokens)、[custom token](https://firebase.google.com/docs/auth/admin/create-custom-tokens)、[SQLite DO](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)。
