# 畫面設定與抗鋸齒選項

檢查日期：2026-10-01。工作區引擎為 Godot `4.7.2.stable.official.ed1daf0bf`，專案桌面與 mobile override 均使用 `gl_compatibility`。Web preset 保持 `variant/thread_support=false`。本次沒有更換渲染器、解析度、貼圖品質或物理更新頻率。

## 已完成的玩家設定

世界畫面的「畫面設定」提供 MSAA 開啟／關閉，以及 30／60／90 FPS 上限。預設保留原專案的 **2× MSAA、60 FPS**。開啟設定時暫停角色移動並結束鏡頭拖曳，關閉時依世界模式恢復控制；Esc 可以關閉面板。手機直向與橫向使用可捲動面板，完成按鈕固定在面板底部。

設定立即套用至 root viewport 的 `msaa_3d` 與 `Engine.max_fps`，儲存在 `user://graphics_settings.cfg`。損壞或不合法的值回復對應預設；寫入失敗或瀏覽器不支援持久儲存時，面板顯示說明，本次設定仍可生效。Web 儲存屬於目前瀏覽器／網站的本機資料，清除網站資料後會失去設定，不會同步到其他裝置。

訓練室與室外共用 root viewport。現有室內轉場會暫時移除室外場景，已套用的 MSAA 與 FPS 值會保留；返回世界也不重設。設定入口目前位於室外世界 HUD。

30／60／90 是**上限**，不是保證幀率。90 仍受螢幕更新率、既有 V-Sync、瀏覽器排程及 GPU 負載限制；本次不關閉 V-Sync 來強求 90。Godot 官方也明確說明 `Engine.max_fps` 與顯示同步的限制，Web 高刷新率需由瀏覽器支援。[Engine.max_fps](https://docs.godotengine.org/en/stable/classes/class_engine.html#class-engine-property-max-fps)

## 可以選擇的方案

| 方案 | 相容性與成本 | 畫質／體驗代價 | 本次狀態 |
| --- | --- | --- | --- |
| 2× MSAA＋60 FPS | 沿用 Compatibility 可用的 MSAA；保留原設定 | 保留目前幾何邊緣平滑程度 | 預設，已提供 |
| 2× MSAA＋30 FPS | 降低最高畫面更新頻率；場景若已低於 30 FPS，單靠上限不會提高幀率 | 空間畫質不變，動作與旋轉的時間流暢度降低 | 玩家自行選擇，已提供 |
| 關閉 MSAA＋60 或 30 FPS | 移除多重取樣的成本，適合裝置 GPU 吃緊時嘗試 | 輪廓鋸齒與細線閃爍較明顯；不降低解析度與貼圖 | 玩家自行選擇，已提供 |
| 2× MSAA＋90 FPS | 沿用目前 AA，要求較高的更新能力 | 空間畫質不變，耗電與發熱可能較高 | 玩家自行選擇，已提供；不保證實際 90 FPS |
| 4× MSAA | Godot Compatibility 支援；取樣數增加，GPU 與記憶體成本通常高於 2× | 輪廓更平滑，但對部分材質內部鋸齒幫助有限 | **未套用、未量測**；屬畫質優先的候選，並非低成本優化 |
| 自訂全螢幕後製抗鋸齒 | Compatibility 支援自訂 screen texture／fullscreen quad，因此可另行製作；不能視為引擎內建 FXAA 已可用 | 可能使紋理細節變軟，增加一次畫面取樣／後製成本；需要處理 HUD 與透明材質 | **未實作、未量測**；必須先做同路線實測與畫質對照，再取得同意才套用 |

若重視整體畫質且裝置偏慢，可以先在本次既有設定中選擇 **保留 2× MSAA、30 FPS 上限**；若瓶頸仍在 GPU，再自行嘗試關閉 MSAA。這只是可試的使用順序，不能取代對特定裝置的測量。

## 為何沒有啟用 TAA、內建 FXAA 或內建 SMAA

官方 Compatibility 功能表列出 3D MSAA 可用，但 TAA、FXAA 與 SMAA 不可用。Web 使用 Compatibility，因此不能只設定對應開關就宣稱獲得那些效果；本次保留 2× MSAA 預設。陰影是光線遮蔽，抗鋸齒是邊緣取樣處理，兩者功能不同；關閉太陽陰影不由 TAA 或其他 AA 取代。[Godot renderers 功能表](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html#antialiasing)

MSAA 主要平滑幾何邊緣，不會自動修正所有貼圖、著色器及高光閃爍。提高 MSAA 次數不是所有鋸齒問題的通用解答。[Godot 3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html)

## 驗證與範圍

`game/tests/graphics_settings_checks.gd` 使用獨立 HUD fixture，檢查讀寫持久設定、不合法值、即時 viewport/MSAA/FPS 套用、保存失敗提示、開關設定的控制狀態、室內轉場所用的場景移出／移回生命週期，以及 1280×800、390×844、844×390 的面板範圍與按鈕不重疊。Godot 4.7.2／Compatibility／MX330 渲染測試為 **34 項通過、0 失敗**，並確認關閉面板釋放 GUI 焦點，讓空白鍵與 Tab 回到遊戲操作。輸出保存在 `deliverables/performance/graphics-settings-tests.json`。加上 `--capture-settings` 可保存三種尺寸的面板畫面；這些是設定介面 fixture，不是完整遊戲性能比較。

`tools/check_performance_browser.cjs` 另外提供 localhost 發行版功能 QA：用真正滑鼠與鍵盤切換設定、重新載入檢查儲存、巡訪六區入口、進出訓練室、快速轉動鏡頭、實際行走及反覆卸載。它只讀取 `?performance` 的診斷資料，沒有經由 JavaScript 修改遊戲節點或繞過互動。腳本限制只能連線 localhost；結果以 `deliverables/performance/<label>.json` 的實際 checks、errors 與未量測項目為準，腳本存在本身不代表測試通過。此次驗證範圍不包含 GitHub Pages 線上網站。

390px Web 檢查是在桌面 Chrome 縮窄視窗後操作，不能當作手機實機或觸控測試。現有遊戲保留 16:10 內容比例，直向視窗上下會有黑邊，整體 HUD 隨內容縮小；此次沒有改動這個既有全局縮放方式。QA 輸入座標會排除黑邊，獨立 HUD fixture 的響應式面板測試與完整 Web 畫面測試分開記錄。

本次採用的抗鋸齒結論是保留 **2× MSAA／60 FPS 預設**，由玩家視裝置選擇 MSAA 關閉或 30／90 FPS 上限。4× MSAA 和自訂後製只列為候選，不因這次介面測試就宣稱能提升特定裝置效能，也不會自動套用。

2026-10-01 的 localhost 發行版功能 QA 使用 Chrome `154.0.8037.58`，驗證 build `streaming-3f7c73f0246b34c7`，**37 項通過、沒有執行錯誤**。其中已實際點擊 MSAA 開／關與 30／60／90、重新載入後確認 90／MSAA 關保留、恢復 60／MSAA 開，並完成六區傳送與入口互動、練功室進出及三次區域卸載。首輪測試的黑邊座標誤差、另一輪誤觸優先長椅互動，都保留為分開的 runner 診斷證據；正式結果以 `release-functional.json` 為準，沒有為了通過 QA 修改遊戲互動規則。

三次卸載後，Godot 節點數均為 1,250、物件數 3,926、資源數 939、已載入細節塊為 0，渲染 buffer 都是 141,311,050 bytes；然而 Chrome 回報的 JS used heap 為 216,130,765 → 226,136,762 → 233,333,105 bytes，這些短期樣本不足以證明整體記憶體不再增長或排除洩漏。Web release 的 `static_memory_bytes` 回報 0，無法作為有效使用量；原生常駐 RAM 標示未量測，也不能把這個 0 解讀為零記憶體。瀏覽器步行路線實際移動約 5.70m，受到既有花盆碰撞阻擋而未穿越區域邊界，因此 **Web 真實徒步跨區仍標示未量測**；六區傳送與室內進出是另外通過的項目，不能用它們替代徒步跨區。

MSAA 各模式在六區實際遊玩時的獨立 GPU 成本、原生 Android／iOS／macOS 可用性、手機觸控與儲存持久性，在這份設定專項測試中均**未量測**。本次程式使用跨平台 Godot API，但不把 Windows fixture 測試當成實機手機或原生桌面發行驗證。完整世界前後比較與 Web 部署狀態另見本次效能報告。

目前 Web preset 的 VRAM 壓縮仍沿用 `for_desktop=true`、`for_mobile=false`。這不是手機相容性保證。官方指出，同時打包 desktop／mobile 壓縮格式可增加相容性，也會增加發布包大小；本次沒有在尚未量測大小與手機畫面前悄悄增加第二組貼圖。未來手機原生／Web 發行需選擇對應格式並做實機測試，不能只靠 FPS 上限解決缺少 WebGL 2 或 GPU 格式支援的裝置。[Godot Web export settings](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformweb.html)
