# 星途 · 3D 球型世界

**[直接遊玩瀏覽器版本](https://stu310101-arch.github.io/star-path-little-world/)**。首次進入需下載遊戲資源，請等候 Godot 載入完成。

可編輯原始專案位於 **game/project.godot**，使用 Godot 4.7.2 開啟後按 F5。

GitHub Pages 的瀏覽器版本由 `.github/workflows/deploy-pages.yml` 發布；可重建的 Web 發布包及更新方法見 [GitHub Pages release](deploy/github-pages/README.md)。

本機的 `deliverables/` 畫面與檢查紀錄沒有包含在公開儲存庫；可玩的網站以 GitHub Pages 版本為準。

練功區已接入可探索室內：靠近世界中的入口圓台按 E 進入，在室內入口傳送門按 E 返回原位置。單字王是其中一台裝置。[練功區整合說明](art/TrainingRoom/GAME_INTEGRATION.md)

室內沙發、電競椅與閱讀座可按 E 坐下／起身；到書架按 E 選書，角色會拿起書閱讀，關閉後放回原位（書頁內容尚未加入）。螢幕、投影、櫃門及閱讀燈可開關，梵谷《星夜》與茶具／陶器可近看。沙發比例與湖畔岸石已修整。

- [操作與重建說明](game/README.md)
- [目前完成狀態與驗證位置](PROGRESS_CURRENT.md)
- [世界配置](game/data/world_layout.json)
- [六區建築與風景配置](game/data/districts.json)

世界半徑 48 m：六個配置不同的現代都市區，新增湖畔、溪谷、林地與沼澤木棧道、48 棟建築（包含第一版矮房的紅屋頂修改版）與 18 輛慢行車輛；櫻花公園採自然分枝、精細花簇與飄落花瓣，透過可步行木橋與城市連接。左／右鍵按住拖曳旋轉、走跑、圓台按 E 起跳淡出仍保留。六站網站與帳號功能待後續整合。

本儲存庫包含遊戲使用的角色資產，以及 `art/TrainingRoom/` 和 `art/Ecology/` 的 Blender 母檔。`game/` 是 Godot 原始專案；`deploy/github-pages/` 是可重建的線上版本。既有人物美術來源、使用者提供的原始素材與製作過程畫面保留於本機工作資料夾。
