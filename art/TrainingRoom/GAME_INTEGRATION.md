# 練功區遊戲整合

遊戲入口：開啟專案 `game/project.godot` 按 F5，進入 3D 世界後前往「06 練功區」，靠近入口圓台按 **E**。也可用既有「選擇目的地」抵達該區。在室內入口傳送門旁按 **E** 返回同一世界與原本位置。

空間名稱為「練功區」；「單字王」僅指室內其中一台裝置。內部站點 ID `wordking` 保留，以維持既有傳送及音樂連接。

## 美術

- 可編輯遊戲版：`WordKing_TrainingRoom_Game.blend`，原黑藍版 `WordKing_TrainingRoom.blend` 保留。
- 米白牆、霧面石地、木色框架、青綠軟包、淡金燈帶配合既有小鎮；保留沙發曲面、抱枕、滾邊及縫線。
- 保持 20 × 18 m、1 台單字王裝置、6 格展示櫃與入口傳送門。下層中央已展示芙寧娜手持靜水流湧，其餘五格保留。
- GLB 路徑：`game/assets/training_room/wordking_training_room.glb`；152 個網格、25 個材質、275,739 三角面。可互動零件獨立匯出，網格具 normals、UV、tangents，《星夜》貼圖內嵌於 GLB。
- 東側入口牆設木作書架、訂製軟墊閱讀座；原導覽圖換成梵谷 1889 年《星夜》。增加織毯、茶具、落地燈、玄關陶器、掛鐘及植物浮雕，中央通道保持暢通。
- 沙發保留縫線、滾邊與抱枕，整體放大 16%；沙發與閱讀座坐面約 0.57 m，配合 1.75 m 的畢業生角色。
- 裝置獨立使用藍色投影材質。`training_projector.gd` 套用螢幕／光束 shader、鏡頭光暈及局部藍光，投影不產生實體陰影；底座保留實體陰影。相容性渲染器不依賴全螢幕 bloom。
- 風格與匯出來源腳本：`tools/style_export_training_room.py`。匯出清理只作用於副本，母檔可編輯。

## 遊戲流程

`world.gd` 沿用既有 E 進站動畫，僅 wordking 站導向實體室內。`training_room_transition.gd` 暫存同一顆世界節點，室內外共用原音樂控制器；返回還原位置、朝向、鏡頭及音樂偏好。

直接執行 `scenes/training_room.tscn`（F6／獨立預覽）時沒有暫存的主世界，右上角「返回世界」、入口 E 及載入中的 Esc 會開啟主世界總覽。2026-10-10 修正原先只發出無接收者的返回訊號、導致角色與房間停止更新的問題；正常從主世界進入時仍還原原世界。迴歸測試為 `game/tests/training_return_checks.gd`（獨立場景四種返回路徑及連點）與 `game/tests/check_training_room.gd`（正常 E／按鈕往返）。

`training_room.gd` 負責場景、燈光、鏡頭、UI及碰撞。`indoor_player.gd` 沿用畢業生骨架與原有移動／跳躍動畫，改用平面重力。操作仍為 WASD、Shift、Space、左／右鍵拖曳視角及滾輪縮放。

`layout.json` 保存 Godot Y-up 公尺制配置，地板 y=.0375，出生點 `[0,.09,6.2]`，返回點 `[0,.04,8.48]`，22 件家具代理碰撞。閱讀座的低座、牆板及頂板分開，L 形沙發轉角使用獨立碰撞。牆地板及裝置碰撞由室內腳本建立。Web 匯出明確包含該 JSON。

## 家具與書籍操作

- 走近沙發、電競椅或閱讀座按 **E** 坐下，再按 **E** 起身。共 12 個座位，坐著仍可拖曳環顧。
- 電腦一與椅子 `gaming_1` 配置「圍棋」；靠近顯示名稱，坐穩後螢幕前出現「進入」，可點擊或按 **F／Enter**。電腦二、三保留空位並顯示「尚未安裝遊戲」。遊戲與座椅以 `game/data/training_computer_games.json` 的明確 ID 配對。
- Web 版以同頁 iframe 開啟圍棋；Windows 版使用 Godot WRY／WebView2，在 Godot 遊戲視窗內載入內附 HTML。按「返回練功區」或 **Esc** 回到原座位，再按 **E** 起身。重開保留棋局，重新進入室內或重啟遊戲可從本機存檔繼續。
- 到書架前會顯示 **E 選取書籍閱讀**。選書後角色拿起並打開書本，原書暫時從書架移除；按 **E／Esc** 或「闔上並放回書架」歸還。13 本書僅使用編號，書頁保持空白。
- 靠近單字王裝置按 **E** 直接用預設瀏覽器開啟 `https://stu310101-arch.github.io/wordking/?page=home`，投影保持亮起；本次沒有帳號串接。閱讀燈按 **E** 可切換開關；六扇展示門固定關閉，沒有開櫃互動。
- 靠近畫作按 **E** 欣賞完整《星夜》；茶具、玄關陶器與牆面裝飾可進入 3D 檢視，左右方向鍵旋轉，**E／Esc** 關閉。

`training_room_interactions.gd` 負責最近互動物、坐下／起身、選書及閱讀；`training_reading_pose.gd` 只調整持書時的角色姿態；`training_room_props.gd` 操作匯出的家具零件。關閉介面後還原角色控制，起身點先以完整膠囊檢查空間。

`training_computer_games.gd` 負責每台電腦的遊戲名稱、座位與進入按鈕。2026-10-10 改用使用者本次提供的木色棋盤單檔，原樣複製至 `game/web_games/go/index.html`，SHA-256 為 `1ff0c27530b735e97ead690e459794ee2db85062954f2a17242cf4a2a227ff8c`。`native_computer_game.gd` 負責 Windows 內嵌、焦點與關閉，`web_games/native_go.html` 負責返回工具列；沒有改動圍棋內部規則或 AI。`tools/package_training_games.py` 將原始 HTML 與瀏覽器介面加入 Web 成品，排除原生工具列；圍棋僅在進入時載入。

## 驗證

- `game/tests/check_indoor_player.gd`：平面移動、原角色跳躍、牆碰撞與停用控制。
- `game/tests/check_training_room.gd`：真實 E 進出兩輪、W移動、Space跳躍、通道及家具碰撞、原世界與音樂狀態還原。
- `game/tests/capture_training_room.gd`：實際 Godot OpenGL 遊戲視角；成果在 `deliverables/training-room/`。
- `game/tests/check_training_interactions.gd`：12 個座位、13 本書、取消／放回及控制恢復；加 `-- --capture` 產生原生畫面。
- `game/tests/check_training_props.gd`：由真正 E 輸入驗證裝置、座位、櫃門、燈、畫作及裝飾檢視；加 `-- --capture` 產生原生畫面。
- `game/tests/check_training_computer_games.gd`：座位與遊戲配對、靠近／坐下／開啟／關閉／起身與空電腦；網頁啟動使用測試替身，另以瀏覽器驗證實際 HTML。

2026-10-10：芙寧娜與靜水流湧已接入 `SOCKET_Genshin_181`，使用使用者提供的持劍姿勢；展示高度 1.12 m，保留補光，不設腳下名牌，櫃上中文「原神角色展示區」已移除。展示為靜態模型，獨立於可操作角色與櫃門。`training_character_display.gd` 等待室內資源包就緒後載入，Web 打包分類包含展示 GLB。可編輯母檔及匯出報告位於 `art/FurinaDisplay/`。

`game/tests/check_furina_display.gd` 驗證櫃位、貼圖、尺寸、握劍模型存在及固定櫃門及展示無名牌，並擷取實際遊戲渲染。

書籍正文、中央裝置的單字練習內容與其他原神角色展示仍待後續製作。
