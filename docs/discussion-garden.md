# 校園生活誌的五區 3D 場景

2026-10-23 整體更新已完成縮距、環道、五區美術、HUD 與最低檔管線，最新數據與畫面見 [整體更新紀錄](discussion-overhaul-20261023.md)。以下保留場景定位與來源說明。

第五站 `life` 使用 `game/scenes/discussion_garden.tscn`，由大世界原有室內轉場進入，返回時恢復原來的大世界位置。大學展覽館仍是第四站。

| 分區 | 場景 | 留言裝置材料 |
| --- | --- | --- |
| 大學交流 | 湖畔木棧台、弧形坐階、柳樹 | 胡桃木、冷灰石座、金屬細節 |
| 科系交流 | 紅磚工坊街、鋼桁架、藝術與機械工作室 | 鋼外框、木柱、紅磚底座 |
| 未來就業 | 玻璃立面、城市露台、工作休憩區 | 深色金屬、灰色水磨石感底座 |
| 高中生發問 | 戶外曲線步道、兩側閱讀屋、林木 | 淺橡木、天然石座 |
| 校園討論 | 石灰岩拱廊、藤架、噴泉 | 胡桃木、石灰岩、黃銅 |

每區每頁八座裝置，每座顯示一篇主留言；回覆在同一篇討論中閱讀。公開暱稱及身分來自共用帳號；匿名留言顯示「匿名」與身分。這些文字由 Godot／網頁介面呈現，不烘焙進模型。

## 已修正的配置問題

- 分區產製函式隔離座標與角度，防止森林植栽迴圈覆蓋裝置與鏡頭方向。
- 森林區八座裝置都在閱讀屋外，正面朝中央步道；屋體範圍與連續步行測試會驗證這個條件。
- 入口花台移至道路之間的草地，座椅同步移動；五條 4.2 公尺道路保留完整通行寬度。
- Compatibility renderer 使用 Linear tonemap，避免石地與木材在 Filmic 下過曝。

## 美術來源與重建

可編輯來源為 `art/DiscussionGarden/DiscussionGarden.blend`；概念圖與來源雜湊見同目錄 `art-manifest.json`。五區 Blender 實際渲染為 `<zone>-blender.png`；遊戲內截圖位於 `deliverables/discussion-garden/qa/`。

重建命令（專案根目錄）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python tools/build_discussion_garden.py
```

`tools/discussion_environment.py` 管理共用場景、裝置變體與連接道路；`tools/discussion_zones/` 內五支檔案定義獨立區域。匯出保留原可編輯網格及修改器，GLB 依區域合併；`clean_discussion_glb.py` 僅清除匯出後零面積三角形，不更動材質、貼圖與有效頂點。模型與動態裝置位置分別在 `game/assets/discussion_garden/*.glb`、`layout.json`。

## 本機驗證與服務界線

實際碰撞步行驗證包含五條道路的中線、左右各 1.35 公尺往返，以及八座森林留言裝置的戶外位置、面向、互動和相機。結果、GLB/layout 雜湊、桌面／直式截圖與十秒本機效能採樣，均存於 `deliverables/discussion-garden/qa/`。來源規則與真實模擬器帳號測試另見 `docs/discussion-forum-checkpoint.md`。

完整登入與留言的本機操作方式見 `docs/local-account-game.md`。帳號／論壇網站、Firestore 規則及索引已於先前登入與獨立裝置修正發布，見 `docs/independent-discussion-devices.md`；本輪新的 3D 花園尚未部署至正式網頁遊戲。原 WordKing 的 Cloudflare、Firebase、網站和其他使用者資料完全未修改。
