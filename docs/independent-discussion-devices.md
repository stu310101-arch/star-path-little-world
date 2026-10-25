# 每座留言裝置獨立操作（2026-10-23）

使用者要求走近任何一座留言裝置都能操作。原實作只允許已有預覽的裝置開啟，空裝置被停用，發文接在入口；依時間排序的留言也會換到別座裝置。這次修正將五區共 40 座裝置各自綁定固定位置。

## 行為

- 水平距離 2.8 公尺內、垂直落差不超過 2 公尺，按 E 或點「在此留言」開啟目前最近的裝置。
- 空裝置顯示主留言表單；已有留言則顯示該裝置主文與回覆。作者可編輯自己的主文或回覆。
- 每座裝置只接受一則主留言，交易原子建立作者權限；兩人同時投稿只允許一方成功，另一方的草稿保留。
- 關閉面板恢復玩家與相機位置，重新載入該區預覽。入口提供本區總覽；從總覽發文須選一座空裝置。
- 既有隨機 ID 留言保留在本區總覽，未搬移、刪除或改寫。刪除主文仍保留占位與既有回覆。

## 固定地址與傳輸

`discussion_device.gd` 每個實例持有 zone、slot、page、thread_id 與 preview。20 字元公開文件 ID 為 `SPDEV` + 區域代碼（UN/MA/CA/HS/CL）+ 12 位組號 + 0–7 的 slot。組號限定 0–999999；換組時載入另一組固定地址，不依發文時間重排。

遊戲請求帶 `devices: true`；host 逐一讀取八個文件，明確送出 `page-item` 或 `page-empty`，並在 `page-begin` 帶 `devicePage`。Godot 驗證地址與位置完全吻合後才套用完整頁；各區請求分開追蹤，跨區移動不會丟失另一區的回應。

論壇面板接受 `{zone, deviceId}`，與 `threadId`／`compose` 互斥。Firestore 規則限制保留前綴的 ID 必須對應正確區域與範圍；原有帳號、私人作者權限與資料保護保留。

## 驗證與發布

- Godot 105 項檢查：五區 40 座分別以空白、已有留言兩種狀態，在 2.4 公尺距離開啟精確地址；確認獨立 ID、遠處禁用、面板開關恢復與完整頁交換。
- 原生 Godot + WRY + 本機 Firebase E2E 16 項通過，正常第五站入口、真實主文與回覆、裝置開啟、離開與帳號門檻皆通過。
- Vitest 含 Firestore Emulator 共 210 項通過；Web bridge 10 項通過；TypeScript 與 production build 通過。
- 兩帳號真實本機瀏覽器 E2E 11 項通過，包含空裝置、投稿衝突、草稿、回覆、固定位置、作者編輯與 390px 版面。報告：`deliverables/discussion-forum/independent-device-browser.json`；腳本：`tools/check_forum_devices_browser.cjs`。這些寫入只在測試 emulator。
- 本機來源快照 canonical SHA：`835d40ecd0ce3f5a0f5805677f81284cceeddde5d47dd206b160b04479f56b77`，已驗證原始工作檔 bytes。
- 正式帳號頁發布包 `build/cloudflare-device-interaction-20261023`，Worker version `85f6d0e2-5865-4617-9d0b-878229435bf0`。保留 156 個既有網頁遊戲檔案及 auth Worker；未重匯出正式網站的 Godot PCK。
- `star-path-75457` 正式規則 SHA：`6f0923a6d149bb3ce8cc6bde8dc7e8e87ca485cb183a80650f5e0481487b9d01`；Firebase Console 顯示 7:20 PM 發布，discussionThreads 索引 `CICAgJiUpoMK` 已 Enabled。

正式公開檔案比對紀錄在發布包 `evidence/public-deployment.json`。沒有在正式使用者帳號建立測試留言。原本 WordKing 的 Cloudflare、Firebase 與其他使用者資料均未改動。

Godot 編輯器目前已開啟的遊戲仍持有舊場景腳本；重新執行本機專案後套用。正式帳號配對流程保持原設定。
