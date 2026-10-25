# 小地圖渲染效能：2026-10-20

本輪診斷發現，HUD 的繪圖提交是受測畫面的一項主要成本。原生測試暫時隱藏 HUD 後，draw calls 減少約 67–80%；有效的 Web 測試進一步確認，小地圖占其中大部分。這些數字用來決定優化方向，尚不是正式小地圖快取的改善幅度。

## 瓶頸證據

原生資料來自 [submission-native/report.json](../deliverables/render-budget/submission-native/report.json)，相鄰基線的計算結果見 [analysis.json](../deliverables/render-budget/submission-native/analysis.json)。Godot 4.7.2、GL Compatibility、AMD Radeon RX 5700 XT；以下全部使用固定 1280 × 800、3D scale 1、MSAA 2×。

表中的基線為該次 `without_ui` 前後兩個完整畫面階段之中位數的平均；每列只比較同一次測試、同一個凍結場景。CPU 時間單位為 ms。

| 視角／畫質策略 | 完整 HUD draws | 暫隱 HUD draws | 減少 draws | Render CPU：基線 → 暫隱 |
| --- | ---: | ---: | ---: | ---: |
| overview／standard | 966 | 319 | 647（67.0%） | 0.974 → 0.346 |
| waterfront_0／standard | 1,042 | 336 | 706（67.8%） | 1.104 → 0.391 |
| overview／low | 1,064 | 358 | 706（66.4%） | 1.053 → 0.358 |
| waterfront_0／low | 880 | 174 | 706（80.2%） | 1.109 → 0.322 |
| overview／mobile | 1,064 | 358 | 706（66.4%） | 1.023 → 0.351 |
| waterfront_0／mobile | 880 | 174 | 706（80.2%） | 1.129 → 0.297 |

standard 的 overview 與 waterfront_0 隱藏 HUD 後，rendered primitives 分別減少 116,987、120,530。這是引擎實際繪圖提交的計數差，包括已三角化的 2D 圖形；不可當成刪除了同等數量的 3D 資產面。原生這組測試只隔離整個 HUD，不能把全部差值直接歸給小地圖。

有效的 [submission-web/report.json](../deliverables/render-budget/submission-web/report.json) 是 standard／overview 的短版重測，單階段 1,500 ms。六個階段開始與結束都記錄為 `focused=true`、`hidden=false`、`visibility=visible`，沒有超過 250 ms 的幀，`timing_valid=true`、`invalid_reasons=[]`。

| Web 階段 | Draw calls 中位數 | Render CPU 中位數 | 幀間隔中位數 | 幀間隔 P95 |
| --- | ---: | ---: | ---: | ---: |
| 完整畫面 `baseline_start` | 966 | 2.10 ms | 16.8 ms | 25.1 ms |
| 暫隱全部 HUD `without_ui` | 319 | 1.20 ms | 16.8 ms | 25.2 ms |
| 恢復 HUD `restored_ui` | 966 | 2.10 ms | 16.8 ms | 25.1 ms |
| 僅暫隱小地圖 `without_minimap` | 367 | 1.40 ms | 16.7 ms | 25.3 ms |
| 恢復小地圖 `restored_minimap` | 966 | 2.00 ms | 16.8 ms | 25.2 ms |

僅隱藏小地圖就少了 599 draws，約為完整畫面的 62.0%，也占整個 HUD 隔離差值的約 92.6%。以 `restored_ui` 和 `restored_minimap` 夾住這次測試，render CPU 基線為 2.05 ms，暫隱小地圖後為 1.40 ms，下降約 31.7%。

Web 的典型幀間隔仍是 16.7–16.8 ms，接近 60 Hz 的瀏覽器更新節奏；P95 約 25 ms。這組短測支持「減少提交與 render CPU 成本」，沒有證明 FPS 提升，也不代表每一幀都達到 60 FPS。Web GPU timer 不可用，報告以 `null` 表示，不能解讀為 GPU 成本是零。

## 量測方法

診斷程式為 [render_submission_probe.gd](../game/tests/render_submission_probe.gd)。原生測試每個階段取樣 700 ms，使用 overview、waterfront_0 兩個固定視角，依序測 standard、low、mobile 策略。Web 有效短版只測 standard／overview。

1. 固定實際 viewport 為 1280 × 800、3D scale 1、3D MSAA 2×，並在診斷中暫時斷開畫質自適應取樣。報告的 `effective_msaa=1` 是 Godot 的 `MSAA_2X` 列舉值。這不是把抗鋸齒關掉，也不是正式 low／mobile 的預設像素配置。
2. 先另記錄仍在運作的 `live_baseline`，再凍結世界模擬，避免角色、車輛、可見性更新等改變 A/B 場景。
3. 在同一程序和同一視角內，執行完整畫面 A → 暫時排除一類 B → 恢復完整畫面 A。UI 使用 CanvasLayer visibility，3D 類別使用 render layer，陰影類別使用燈光的 shadow 開關；全部只在診斷實例中暫改並還原。
4. 以 B 前後相鄰 A 的中位數平均作為局部基線。`live_baseline` 保留供查閱，不混入凍結階段的改善比例。
5. 原生診斷關閉 VSync 與引擎幀率上限以觀察成本；Web 即使引擎上限為 0，仍受瀏覽器呈現節奏影響。記錄 draws、primitives、frame、render CPU、process、physics 與可取得的 GPU timer，分開解讀。

隱藏 HUD 或小地圖是找出成本來源的診斷手段，不是產品優化內容。產品仍須顯示完整地圖、導航和操作資訊。原生診斷與還原流程的 17 項檢查見 [submission-native/README.md](../deliverables/render-budget/submission-native/README.md)。

### 為何不再呼叫 `_draw()` 仍然有成本

Godot 的 retained CanvasItem 可以保存上一次 `_draw()` 建立的繪圖命令。人物靜止時不再 `queue_redraw()`，能省下 GDScript 投影、裁切、三角化和命令重建；保存下來的線段、多邊形、文字仍會在每個可見畫面中提交與繪製。

Texture cache 才會把地圖的結果先畫到 SubViewport texture，之後以一張貼圖呈現；位置、尺寸、像素密度或內容改變時再重建。導航箭頭等需要獨立更新的內容仍保留獨立繪製。這個區別說明為何既有「靜止時不重畫命令」不足以消除本次測得的提交成本。快取是否真的保持相同像素、字型與 AA，以及更新中的成本，必須另測，不能由隱藏測試推算。

## 限制與未採信資料

- **不跨畫質排名絕對時間。** 原生每一列的 A/B/A 有相同凍結狀態，但後續 overview 已經保留完成載入的角色與不同 HUD 內容，因此 standard overview 的 966 draws 與後續 1,064 draws 不是單純由畫質設定造成。low／mobile 也刻意固定了像素配置，不能拿來代表其正常遊玩 FPS。
- **不採信失效的 Web 計時。** [submission-web-invalid/report.json](../deliverables/render-budget/submission-web-invalid/report.json) 保留作追蹤資料；多個階段只有 2–4 幀，間隔約 1,000 ms，出現背景節流或停頓特徵，沒有有效前景短測的完整有效性記錄。本文件不使用其時間、FPS 或改善百分比作結論，也不與有效短版拼接。
- **短測只用來定位。** 原生 700 ms 與 Web 1,500 ms 的時間窗不足以代表長時間遊玩；小成本的變動可能是噪音。某些零 draws 差異仍伴隨時間變動，不能把每個微小差值都當成優化機會。Web `process` 指標也有離群值，本文件沒有據此宣稱整個主執行緒的改善比例。
- **類別差值不能任意相加。** 關閉陰影會改變多種幾何的 pass；遠景已合批的 mesh 也可能同時包含多種物件，故保留 `mixed_overview` 分類。某類別在這個視角沒有差值，不代表它在整張地圖都沒有成本。
- **資產盤點不等於實際 draws。** Surface 數量沒有包含所有視錐剔除、陰影 pass、合批和可見性效果；跨區域的候選總數也不會同時出現在一幀。
- **尚未證明手機與溫度表現。** 原生是桌機量測，有效 Web 是桌面瀏覽器短測；沒有手機硬體或長時間溫度／耗電資料。不能據此承諾所有手機、所有畫質都穩定或不發熱。

## 其他候選與本輪相關修改

[runtime-batching-summary.json](../deliverables/render-budget/runtime-batching-summary.json) 盤點了跨 chunk 的等值材質，以及路燈、花盆等局部合批候選。候選要求材質屬性、UV、法線、變換、可見性與 camera fade 邊界相容；跨物件共用材質本身不保證減少 draw calls。現有四種世界 shader 的程式資源沒有重複載成多份，不能把重複 ShaderMaterial identity 說成重複 shader 程式。

本輪沒有將新的 runtime material pool、街景合批或角色合批裝入產品。[material_intern_fixture.gd](../game/tests/material_intern_fixture.gd) 僅是可還原的診斷工具，15 項檢查通過；它不修改來源 mesh，亦不取代後續實際 A/B 與畫面驗證。

本輪另將 WebPacks 的一般 HUD 進度查詢改為輕量 `get_startup_status()`：戶外啟動完成後，避免反覆跨 Wasm／JavaScript 取得下載快照及複製診斷歷史；按需室內載入仍使用自己的資源進度。主代理回報 [web_pack_checks.gd](../game/tests/web_pack_checks.gd) 的 120 項檢查通過。這是獨立的輪詢成本修改，沒有單獨量測收益，不能把它併入上述小地圖隔離數字。

## 最終快取結果

### 原生 r2：省下穩定畫面的提交，重建尖峰仍存在

以下 render CPU 計數來自 root viewport；快取子 viewport 的重建時間另存在原始報告 `cartography_update_frames`，不能把 root 指標當作所有 viewport 或整個主執行緒的總成本。

修正小數像素對齊與字型 oversampling 後的 [minimap-cache-native-r2/report.json](../deliverables/render-budget/minimap-cache-native-r2/report.json) 及 [analysis.json](../deliverables/render-budget/minimap-cache-native-r2/analysis.json)，使用同一程序、凍結 3D 世界模擬，執行 direct A0 → texture cache B → direct A1。standard 材質與陰影、1280 × 800、3D scale 1、MSAA 2× 均保持相同。這次 B 保留完整 HUD，是實際快取的比較。

| 原生指標 | Direct A0 | Cache B | Direct A1 |
| --- | ---: | ---: | ---: |
| 靜止 draws 中位數 | 1,042 | 397 | 1,042 |
| 靜止 render CPU 中位數 | 1.218 ms | 0.500 ms | 1.227 ms |
| 靜止幀間隔中位數 | 2.127 ms | 0.980 ms | 2.137 ms |
| 移動期間、非重建幀中位數 | 2.066 ms | 1.023 ms | 2.065 ms |
| 移動期間、重建幀中位數 | 15.652 ms | 15.478 ms | 15.253 ms |
| 移動期間、重建幀 P95 | 17.277 ms | 17.547 ms | 16.796 ms |

靜止時少了 645 draws（61.9%）；以相鄰 direct 階段平均比較，render CPU 約由 1.223 降至 0.500 ms。移動測試每階段都沿同一條按經過時間計算的路線走 4 秒，20 Hz、共 80 次 refresh 呼叫（79 次實際底圖重畫），沒有藉由減少更新次數取得差值。

**約 15 ms 的地圖重建幀沒有改善。** 快取改善的是兩次重建之間的重複提交；全幀 P95 在 cache 階段下降，也受到穩定幀變快、重建幀占樣本不到 5% 的影響。因此必須同時保留上表獨立的重建幀分布，不能宣稱走動尖峰已消除。這些未限幀的桌機時間也不是正式遊玩 FPS 或手機保證。

### 像素與生命週期驗證

r2 包含原始視窗、resize、1.5× 實體／邏輯比例三組 direct/cache 圖片。各組最大色彩通道差均為 2/255，平均絕對通道差約 0.17/255；超過 1/255 的像素數依序為 2、2、1，沒有超過 4/255 的像素。這並非逐通道位元完全相同，而是 render target 合成後的小量色彩捨入差。驗證代理已目視覆核修正後 1.5× 圖片，先前的幾何／字型偏移已不再出現；實際圖片與方法見 [r2 README](../deliverables/render-budget/minimap-cache-native-r2/README.md)。

先前 [minimap-cache-native](../deliverables/render-budget/minimap-cache-native/report.json) 的高 DPI 首次嘗試留存作問題追蹤，不能作通過證據。1.5× 是合成的像素比例測試，仍不能替代真實手機或作業系統 DPI 的驗收。

[minimap-cache-checks.json](../deliverables/low-end/minimap-cache-checks.json) 的 73 項 headless 檢查全部通過，來源 SHA256 與 r2 的 `world_minimap.gd` 相同。涵蓋靜止貼圖重用、移動與尺寸失效更新、獨立導航層、原字型 oversampling、旋轉時回到 direct 繪製，以及室內離樹時解除外部 resize callback、返回後重新連接與更新像素尺寸、離樹後釋放世界。Headless 結果證明程式行為，像素判讀則以上述實際渲染圖片為準。

### Web r2：有效階段降低提交與 root viewport render CPU，幀率節奏不變

正式快取比較採用 [minimap-cache-web-r2/report.json](../deliverables/render-budget/minimap-cache-web-r2/report.json) 的三個有效靜止階段，以及 [minimap-cache-web-compact-r2/report.json](../deliverables/render-budget/minimap-cache-web-compact-r2/report.json) 全部六個有效階段。每個採用階段都為 `timing_valid=true`、`invalid_reasons=[]`、沒有超過 250 ms 的幀，且開始與結束都記錄為前景、可見、有焦點。這些是保留完整 HUD 的 direct/cache A/B/A，與前文暫隱小地圖的成本定位分開。

下表 direct 數值為同組相鄰 A0/A1 中位數的平均，CPU 單位為 ms；不同 HUD 之間不作速度排名。

| Web HUD／有效範圍 | Draws：Direct → Cache | 靜止 render CPU：Direct → Cache | 移動 render CPU：Direct → Cache |
| --- | ---: | ---: | ---: |
| 標準 HUD／僅靜止 | 958 → 313（−67.3%） | 2.20 → 1.30（−40.9%） | 排除：三段無效 |
| Compact HUD／靜止與移動 | 638 → 274（−57.1%） | 1.85 → 1.10（−40.5%） | 1.45 → 0.90（−37.9%） |

Compact 的每個移動階段約 4 秒、240 幀，沿相同按經過時間計算的路線，均有 80 次地圖 refresh、79 次實際底圖重畫（20 Hz）。所有採用階段都保持 **1280 × 800、3D scale 1、MSAA 2×**；Compact 僅使用手機版 HUD 配置，執行硬體仍是桌面瀏覽器，並非手機效能測試。各階段全幀中位數均為 16.7 ms，持續在約 60 Hz 的呈現節奏；本次主張是 render CPU 與 draw calls 下降，沒有 FPS 增加的主張。

標準 HUD 的 r2 移動 A0/B/A1 全部帶有 `frames_over_250ms_possible_throttling_or_stall`：每段各有 4 個超過 250 ms 的幀，只完成 10／11／8 次 refresh。雖然頭尾的前景狀態顯示可見且有焦點，這仍不足以排除期間的節流或停頓，所以三段都不採信，不用它們計算改善比例。

較早的 [minimap-cache-web-r2-first/report.json](../deliverables/render-budget/minimap-cache-web-r2-first/report.json) 也保留作追蹤。其移動 A0 同樣因 `frames_over_250ms_possible_throttling_or_stall` 無效，出現 1 個長幀且只完成 61 次 refresh；即使 B/A1 各完成 80 次且標為有效，這一輪仍缺少完整有效的 A/B/A，因此不作移動改善證據，也不與另一輪任意拼接。標準 HUD 的有效 Web 移動比較仍未完成；Compact 的有效結果不能替代它。Web GPU timer 仍不可用，沒有 GPU 耗時、手機溫度或耗電結論。

### 未採用的離屏 stroke 篩選

為調查走動重建成本，另做純函式原樣頂點篩選：對每條線段檢查安全外擴矩形，輸出原始連續 slices，保留接角前後鄰點，不重新取樣；閉環 seam、零長度等不確定情況保留整條。local Godot 4.7.2 renderer 的 miter 長度上限為 3、`FEATHER_SIZE=1.25`，採用更保守的 `3*max(width,1)+6` margin。24 點以下的短線直接保留。

[minimap-stroke-clip.json](../deliverables/performance-20261020/minimap-stroke-clip.json) 的最後一次 headless 測量使用實際地圖投影與相同 stroke widths，每組 4 次預熱、12 次計時，包含 helper 與原生 AA 命令建立時間。這不是 GPU 或 Web FPS 測試。

| 地圖／視角 | 原始點數 → 保留點數 | Direct 原生 AA | 原樣 slices + 原生 AA |
| --- | ---: | ---: | ---: |
| 標準 246×180／counseling | 17,983 → 7,606 | 2.870 ms | 4.602 ms |
| 標準 246×180／bridge | 19,106 → 6,770 | 2.987 ms | 4.898 ms |
| Compact 128×90／counseling | 1,204 → 910 | 0.209 ms | 0.367 ms |
| Compact 128×90／bridge | 1,454 → 1,005 | 0.257 ms | 0.427 ms |

雖然標準地圖少了約 58–65% 的線條點，GDScript 掃描自身的時間抵銷了原生 AA 建立成本的節省，四組都變慢，因此沒有接入產品。22 項檢查通過，包括可見線段不遺漏、原鄰點保留、閉環與零長度 fallback、100 條固定種子的 coverage 檢查；候選封存在 [minimap_stroke_clip_fixture.gd](../game/tests/minimap_stroke_clip_fixture.gd)，正式 export 的 `tests/*` 排除範圍內。

原生 `Geometry2D.intersect_polyline_with_polygon` 也僅作 CPU 對照：兩組標準地圖連同 AA 約為 2.326、2.323 ms，compact 則變慢。其 Clipper precision 5 會量化座標、產生新交點，且 `PreserveCollinear(false)` 會移除共線原頂點，不符合這次保留全部可見原頂點的契約；也沒有取得像素等效驗證，所以同樣未採用。

## 發布與交付

已於台灣時間 2026-10-21 凌晨部署至既有 [星途網址](https://star-path-little-world.star-path-little-world.workers.dev/)。

- build `cf-ffd112c5d2c569f4`；來源 `packs-57cfcbe5ad52ae62`；Cloudflare version `d8f87613-f2c1-401b-a427-2b70a6511c0a`。
- Web desktop/mobile 各 20 包，438／436 個匯入資源掛載通過；378 個發布檔、9 個分片原檔的重組 SHA256 通過。10 個公開路徑內容與登入 headers 核對通過，詳見 [公開驗證](../deliverables/render-budget/minimap-public-deployment.json)。
- Windows：`build/StarPath-Windows-Minimap-20261020.zip`，280,128,246 bytes、22 檔；CRC／逐檔 SHA256／release manifest 通過。ZIP SHA256 `4fde82b5d6d38633059778827857533547be3f4a8c688d6e29707df0b599d539`。
- [三平台編譯資源檢查](../deliverables/render-budget/minimap-export-verification.json) 確認四支更新腳本一致、21 個來源封版雜湊一致。畫質設定、mobile quality、世界表面與天空著色器的 compiled payload 與上一版一致；本次沒有降低原有解析度、AA 或改變可見模型。
- 本機正式 Web 輸出已驗啟動、漫遊進入、小地圖與全圖開關、關閉後 paused=false；最高檔實際 3D 與 UI 像素同為 1457×911、scale 1、MSAA 2×。此為功能冒煙測試，沒有把該次幀數當作無干擾的性能對照。
- Firebase、admissions 來源與登入 Worker SHA 保持；本輪未重新執行實際 Google／Email 或跨裝置雲端成績驗收。
- 回退保留 `build/cloudflare-performance-20261020/` 及 `build/StarPath-Windows-Performance-20261020.zip`。回退必須使用原完整 `wrangler.jsonc`，保留登入 Durable Object bindings／migration。

完整交付索引：[minimap-delivery.json](../deliverables/render-budget/minimap-delivery.json)。未操作 Git 提交、推送或 staging。


### 公網首開驗收限制

公開頁確認載入新版分片腳本，但截至 2026-10-21 00:12（台灣），首次啟動包僅完成 31.6／46.1 MB，尚未進入遊戲，故**未宣稱線上手機介面遊玩驗收通過**。DOM 沒有錯誤，進度仍增加。新／舊／小分片抽查均 HTTP 200，長度及前 1 KiB 符合本地；另一個新分片的 15 秒下載取樣僅收到 17,513 bytes（首回應 3.284 秒），支持目前公網傳輸緩慢，不能當作整檔雜湊驗證。沒有因此修改畫質或重部署 loader。來源相同的本機正式輸出及前述固定場景 A/B 已完成驗收。

證據：[線上待驗紀錄](../deliverables/render-budget/minimap-online-smoke-pending.json)、[分片抽查](../deliverables/release-debug/chunk-probe-20261021.json)。Chrome 公開頁保留下載；10 個小型公開路徑雜湊通過與實際遊戲畫面驗收分開記錄。
