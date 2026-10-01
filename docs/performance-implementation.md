# 小星球效能修改與重建方式

本次維持 Godot 4.7.2、Compatibility、Web 單執行緒、原解析度、原貼圖、2× MSAA／60 FPS 預設。太陽只關閉即時陰影，光源、顏色與環境光保留。玩家可在「畫面設定」自行切換 MSAA 與 30／60／90 FPS 上限；相容性與替代方案見 [performance-antialiasing.md](performance-antialiasing.md)。

畫面對照發現關閉陰影後整體略暗。以同一工作區完整模型、相同相機與燈光參數，只切換 `Sun.shadow_enabled` 即重現此明暗差；因此與 Compatibility 目前的陰影開關渲染結果相關，不能歸因於模型簡化或降低貼圖。本次未調高燈光補償，也未改動材質。比較圖保存於 `deliverables/performance/comparison-workspace-*.png`。

## 場景與區域生命週期

`game/generated/globe.tscn`、`neighborhood.tscn`、`districts/` 與原始美術資產仍是可編輯來源。離線工具 `streaming_world_builder.gd` 從原場景產生 `generated/streaming/` 的二進位 bases、細節 chunks 與 JSON catalog。主場景只直接依賴 bases 與互動入口；catalog 用字串路徑登記細節，沒有 preload 完整地區。

全景保留原地形、道路、水域、橋、主要建築輪廓與植物顏色。離線合併靜態網格，對建築／植被使用網格 LOD 並剔除小型裝飾；不在玩家啟動時簡化。地面、道路、水域與薄貼地網格保留來源曲面幾何，只合併批次：早期全景測試發現減面會產生缺口，因此以同一工作區相機／燈光對照修正，沒有抬高地形來掩蓋缺口。合併材質依完整儲存屬性分類，保留不同材質外觀。簡化網格重新索引，避免留下已不用的高細節頂點。

原本的 384 個靜態碰撞物件保留於 bases，包括地面、建築與椅子，沿原祖先變換展平。因此細節正在載入或已卸載時仍能維持道路、橋、傳送、椅子與角色的物理安全。細節節點不重複包含那些碰撞。六個互動入口也持續存在。

`district_streaming.gd` 集中管理以下初始參數（球面弦距、公尺）：

| 參數 | 值 | 用途 |
| --- | ---: | --- |
| `LOAD_DISTANCE` | 45 | 提前載入 |
| `ACTIVE_DISTANCE` | 38 | 顯示完整細節；離開後到 45 才退回簡化 |
| `UNLOAD_DISTANCE` | 57 | 卸載距離，與載入門檻不同 |
| `UNLOAD_DELAY` | 4 秒 | 超出卸載範圍後的緩衝 |
| `CONTEXT_INTERVAL` | 0.15 秒 | 更新區域需求 |
| `OVERVIEW_DETAIL_CAMERA_ALTITUDE` | 70 | 全景拉近至此高度時，以鏡頭朝向的球面區域預取 |
| `PIN_SECONDS` | 20 秒 | 傳送、切近景／室內返回預取保護；切回全景取消 |

每幀至多執行一個分塊 load、instantiate 或卸載步驟；load 與 instantiate 分開到不同幀。Web 沒有新增執行緒，單次引擎呼叫仍是同步的，所以用離線節點／三角形預算限制其大小，並記錄實際 `max_operation_ms`。此數字包括腳本操作及登記索引，不代表整個 GPU 幀時間。

一區載完才以細節替換該區簡化外觀。停用區域使用 `PROCESS_MODE_DISABLED`；全景拉近時即使顯示細節，仍不啟動動物與車輛腳本。離開後分幀釋放場景。重新進入恢復湖泊、海洋與車流的動畫時間、車輛路徑進度與輪子角度；只保留純數值，沒有保留舊節點／材質參照。這是凍結再恢復，離開期間不模擬遠處動物。

**所有細節仍在同一 PCK 下載。** 分幀建立不等於網路按需下載。首次下載量由實際匯出清單決定；Web preset 排除已被衍生檔取代的完整 generated 場景，但保留來源於 Git。

## 鏡頭遮擋

建築與植被以靜態空間格索引覆蓋整段「鏡頭到角色」視線走廊。区域新增／卸載更新索引；弱參照與移除通知清理舊節點。永久碰撞的 `camera_visual_group` 對應當前細節外觀。室內轉場卸下世界時重置索引，返回同一世界時重新建立目前仍存在的區塊所有權。

昂貴判定初始為每 0.1 秒一次；大幅位移、快速旋轉、傳送與模式切換可提前觸發。相機與材質淡入淡出仍逐幀執行。全景關閉判定，恢復透明度／植被只在狀態切換做一次。

靜態 AABB、逆矩陣、原始 MultiMesh transforms／colors／custom data、淡出材質皆可重用。只有可見集合改變才壓縮可見實例到前綴並設定 `visible_instance_count`，不移至遠方或用零縮放隱藏。恢復時保留原始可見數與順序。

目前被索引的建築和樹木不會在執行期移動。父區塊的全域變換與 mesh resource 的 `changed` 通知會更新快取；未來若程式直接替換 mesh 或改動區塊內的靜態子節點／原始實例變換，需在修改後呼叫 `camera_obstruction.invalidate(region)`。現有會移動的海洋、魚與車流演員不屬於靜態植被索引。

## 重建與發布檔

在根目錄執行（`godot_console` 必須為 4.7.2，匯出模板也相同）：

```powershell
godot_console --headless --path game --script res://tools/build_streaming_world.gd
godot_console --headless --path game --script res://tools/configure_performance_world.gd
godot_console --headless --path game --script res://tests/streaming_build_checks.gd
python tools/build_web_release.py --godot godot_console
```

完整世界生成與區域、水域、石岸、櫻花座椅更新工具已接上衍生場景重建，避免只修改一次輸出、下次生成失效。生成器會刪除上一個 catalog 已不再使用的 chunks。

`index.release.json` 記錄來源摘要、build ID，以及同次匯出的 HTML／JS／WASM／PCK 大小和 SHA-256。manifest 與 assemble 驗證每個 PCK 分片及所有發布檔；prepare 只移除上一份 manifest 所擁有、這次已不用的檔案。

2026-10-01 起，上述統一建置命令還會列舉靜態與明確宣告的動態依賴，將普通 Web 匯出拆成啟動包及按需下載包，並從隔離目錄實際解碼所有匯出資源。`index.packs.json` 與啟動包內的同名清單必須一致；`index.release.json` 也涵蓋全部分包。直接省略此步驟匯出，會回到單一大 PCK。

現有 GitHub workflow **只組裝已匯出的發布檔，不執行 Godot 匯出**。因此必須連同 `deploy/github-pages/` 一起提交。依本次最新要求，只做 localhost 驗證、Git 提交與推送，不檢查 Actions 或公開網站。

## 診斷

Web 加上 `?performance` 會每秒提供唯讀 `window.planetPerformance`，包含區域／分塊數、遮擋候選數／耗時、MultiMesh 寫入次數、引擎節點數與可用的效能監視器。一般遊玩不啟動此採樣。原生以 `-- --performance` 開啟。

`tools/measure_web_performance.cjs` 保存冷啟動、同一瀏覽器 context 再次開啟及固定操作路線；`tools/check_performance_browser.cjs` 用真實滑鼠與鍵盤操作設定、六區互動、室內返回與反覆進出。測量數字與未量測範圍見本次效能報告。
