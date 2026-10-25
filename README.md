# 星途 · 3D 球型世界

2026-10-25 已將「星圖羅盤探索室」推薦功能與 r3 可坐工作台、動態天文儀發布至 Cloudflare 正式站。正式版為 `cf-a5ad2b01262d5612`；啟動、資產、部署及驗證紀錄見 [選校推薦室說明](docs/recommendation-room.md)。

**[直接遊玩 Cloudflare 正式版](https://star-path-little-world.star-path-little-world.workers.dev/)**。首次進入需下載遊戲資源，請等候 Godot 載入完成。

可編輯原始專案位於 **game/project.godot**，使用 Godot 4.7.2 開啟後按 F5。

正式網站使用 Cloudflare Workers 與 Static Assets，同包提供遊戲、帳號網站與 Windows 登入服務。GitHub 儲存庫保存可重建來源；舊 GitHub Pages 發行流程仍保留於 [GitHub Pages release](deploy/github-pages/README.md)。

本機的 `deliverables/` 畫面與詳細檢查紀錄沒有包含在公開儲存庫；公開驗證摘要保存在 `docs/`，正式遊戲入口為上方 Cloudflare 網址。

練功區已接入可探索室內：靠近世界中的入口圓台按 E 進入，在室內入口傳送門按 E 返回原位置。單字王是其中一台裝置。[練功區整合說明](art/TrainingRoom/GAME_INTEGRATION.md)

本機版已接入獨立的「大學館」：五個地區展區、138 個校園條目，依展廊步行探索或搜尋直達展位；按 E 閱讀位置、周邊、美食、學生評價與校園風氣，收藏與已探索進度保存在本機。「校園印象」可進入模型近觀，拖曳及縮放查看細節。內容以使用者提供的 2026-10-09 文件為參考，保留五類正文與原始來源；新增官方查證另列日期，與學生個人經驗分開呈現。各校有明確的縮景配置，美術來源位於 `art/UniversityHall/`。Web 與 Windows 發布包皆由同一份來源重建。

Windows 版已接入圍棋與單字王：第一台電腦椅按 E 坐下，再按 F／Enter，在遊戲內遊玩圍棋；中央單字王裝置按 E 直接用瀏覽器開啟指定首頁。本次不整合帳號。Windows 標準畫質成品位於 `build/windows-world/LittleWorld.exe`，整份資料夾保留即可使用；重建指令見 [操作與重建說明](game/README.md)。

室內沙發、電競椅與閱讀座可按 E 坐下／起身；到書架按 E 選書，角色會拿起書閱讀，關閉後放回原位（書頁內容尚未加入）。閱讀燈可開關，梵谷《星夜》與茶具／陶器可近看。沙發比例與湖畔岸石已修整。

- [操作與重建說明](game/README.md)
- [目前完成狀態與驗證位置](PROGRESS_CURRENT.md)
- [世界配置](game/data/world_layout.json)
- [六區建築與風景配置](game/data/districts.json)

世界保留完整球面與六方向跨區往返，半徑為 600 m；近距離地面曲率降低，12 條跨海步橋連接六區。每區有獨立生態地形：草甸湖丘、岩岸港灣、砂岩高地、山地針葉林、秋季混合林、蘆葦濕地，包含 12–28 m 山脊、外湖、岩層和步道。48 棟建築、18 輛真尺寸車輛、三種船舶、入口與抵達區採統一座標；小地圖直接使用真實岸線、建物地基、步道和站號資料。

本儲存庫包含遊戲使用的角色資產，以及 `art/TrainingRoom/`、`art/Ecology/`、`art/Vehicles/`、`art/Vessels/` 的 Blender 母檔。`game/` 是 Godot 原始專案；`deploy/github-pages/` 是可重建的線上版本。既有人物美術來源、使用者提供的原始素材與製作過程畫面保留於本機工作資料夾。

選校研究所正在製作本機候選：以完成量表或手選學類與單份成績，提供可解釋的校系推薦、收藏比較及大學館連結。後端技術檢查已通過；實際房間、跨平台操作與候選包狀態見 [推薦室技術說明](docs/recommendation-room.md)。本輪尚未將推薦功能發布到正式網站。
