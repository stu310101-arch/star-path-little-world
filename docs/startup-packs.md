# 啟動包與按需下載（2026-10-01）

本次實作前四項；沒有新增 Service Worker、PWA、Cache Storage 或版本化本機資源快取。保留既有畫面設定儲存、Compatibility、單執行緒 Web、解析度、貼圖品質與原始模型。

## 運作方式

1. 普通 Godot Web 匯出後，`collect_web_pack_dependencies.gd` 列舉靜態依賴，加上角色、區域 catalog、室內與音樂的明確動態入口。新增但未分類的 `res://` 字串會阻止建置，避免靜默漏包。
2. `split_web_packs.py` 驗證原 PCK 的所有索引／MD5，保留必要 entry 原始 bytes 與資源路徑，建立啟動包及 16 個延後包。不同路徑的完全相同內容可共享實體 payload；不重新壓縮貼圖或修改模型。
3. 啟動包只含全景、必要碰撞／入口、UI／字型、程式與資料。WebPacks 在全景初始幀後才請求角色，音樂只請求當前情境；區域及室內隨需求下載。
4. `WebPacks` 以單一非阻塞 HTTPClient 排程，依賴包優先，目的地優先於背景音樂。以 64 KiB 區塊寫至 Web 的 `/tmp/little-world-packs`，每幀最多 512 KiB；SHA-256 另以每幀最多 512 KiB 驗證，完成後下一幀掛載。自行管理檔案生命週期，避開 Godot 4.7.2 HTTPRequest 在 Web 未知長度 EOF 成功路徑刪掉下載檔的問題。
5. 角色資源載入、模型建立、骨架配對分成五次操作，只在需要漫遊時進行。單次 Godot load／instantiate 仍是同步操作，不能宣稱完全消除切換卡頓。
6. 目的地包、必要細節與角色都準備好才啟用漫遊。準備中可取消或重試；E、跳躍及設定切換受狀態保護。室內包準備完成才切場景，返回沿用原世界實例。
7. 桌面／手機原生版使用本地資源，不走 Web HTTP 下載，但仍使用相同的角色延後建立、區域串流與音樂延後載入。

這是真正減少啟動下載的分包。原本的區域節點分幀建立仍保留，兩者是不同層次。

## 生命週期與限制

- Godot 沒有此處可用的 PCK 卸載流程；已掛載包及虛擬檔案在本次頁面存活期間保留。區域節點與不再引用的引擎資源仍依既有距離門檻卸載。完整走訪後的包資料量會趨向全部發布包，不能把節點卸載描述成網路包記憶體全部釋放。
- 同一頁面重進區域不重複下載、掛載相同包。取消準備會返回全景，已排入下載仍可能繼續。沒有跨重新整理的新快取功能；瀏覽器原本的 HTTP 快取行為不變。
- HTTP 最長等待 600 秒，以容納慢速連線；錯誤／大小或雜湊不符不會掛載。準備提示提供重試與返回；音樂失敗時音樂按鈕改為重試。
- 前後的材質整理只共用全部渲染參數與匯入設定相同的資源；近景 MultiMesh 的原始 buffer 不改。全景保持 1,009,913 三角形、893,393 頂點、316 個受保護地面及 384 碰撞。
- 既有中文完整字型與角色形態鍵仍保留。因此啟動包不是極小的空殼；第一次漫遊也仍有角色準備成本。

Compatibility 的燈光編譯容量另調整為每種類型／物件 4 盞、每次畫面 8 盞 positional lights，原為 8／32。完整室內含投影與閱讀燈共 4 Omni + 1 Spot；全景的 2 Directional 不占此 positional 配額，鑑賞視窗另有自己的 World3D。沒有刪燈或改燈色／強度／室內陰影。`render_light_limits_checks.gd` 實際建立場景確認容量；未來新增燈光超過此範圍必須重新評估。

Godot 4.7 Compatibility 會先編譯通用 shader，包含目前場景未使用的燈光／反射分支，所以只關閉太陽陰影不會消除所有啟動編譯。這次縮小有餘裕的燈光容量，不修改引擎、替換 shader 或加 Web 執行緒。[官方容量說明](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-opengl-max-lights-per-object)、[引擎初始化實作](https://github.com/godotengine/godot/blob/4.7/drivers/gles3/shader_gles3.cpp)。

## 可重現建置與驗證

```powershell
python tools/build_web_release.py --godot <Godot-4.7.2-console-path>
```

模型／材質生成規則改動時加 `--rebuild-world`。需要相同版本的匯出模板。建置依序完成 export、dependency inventory、split、隔離目錄掛載／解碼驗證、notices、release stamp、prepare 與 assemble；失敗即停止。每步 log 位於 `build/web-*.log`。

`index.packs.json` 必須與啟動 PCK 內 `res://data/web_packs.json` 完全一致。`index.release.json`、Pages manifest 與組裝程序都涵蓋延後包的大小／SHA-256。GitHub workflow 仍只組裝已提交的匯出檔，沒有雲端 Godot 匯出。

主要回歸工具：

- `tools/test_split_web_packs.py`、`tools/test_web_package.py`：錯誤索引、資源閉包、雜湊、重複 payload、組裝與安全清理。
- `game/tests/web_pack_checks.gd`：HTTP 下載、相依掛載、不重複下載、損壞內容拒絕與重試；需根目錄的 localhost:8947 靜態伺服器。
- `game/tests/lazy_avatar_music_checks.gd`、既有角色／世界／室內測試：延後準備契約與玩法。
- `tools/measure_startup_packs.cjs <localhost URL> <label>`：相同 1200×800 Chrome 條件下首次／再次開啟，分開記錄下載與首個可回應 rAF。`--shader-sources --single` 額外收集 shader 診斷，不混入一般基準比較。
- `tools/check_web_pack_delivery.cjs <localhost URL>`：首次角色包 HTTP 503，全景仍可用、準備阻擋操作、取消、真實按鈕重試與漫遊就緒。
- `tools/check_performance_browser.cjs`：設定、六區互動、室內返回、快速鏡頭與反覆進出。

實測數字與未量測項目另見本輪測量報告。下載 bytes、引擎資源數、JS heap 與整個瀏覽器常駐記憶體不能互相替代。
