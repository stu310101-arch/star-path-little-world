# 輔導室重疊面修正 — 2026-10-25

- 高三轉角桌以可編輯 Boolean Union 合成單一表面；原側桌操作物件保留在 `COL_RepairOperands`，不重複匯出。
- 畫框橫條、書刊架底板、書封／書脊、窗框、窗台、踢腳板與天花線板改為避開共平面的接合；東側成長圖移到背板前方。
- 更新 Blender 母檔、完整 GLB、低階匯出與 Godot 低階房間。完整模型 155,532 三角面，低階執行模型 58,470 三角面。
- 同一方法的幾何檢查：完全相同的面由 144 降至 0；軸向共平面包圍盒候選由 144 降至 29。後者含地板下接觸面、相接封閉物件和包圍盒誤判，不代表仍有 29 個可見閃面。
- 一次高／低階原生遊戲檢查共 16 項通過，保存並查看 6 張實際畫面。兩個木椅網格、4 個座位、17 個碰撞代理與兩個年級裝置保留。沒有進行回滾或擴大長時間驗收。
- 證據：`build/counseling-faces-audit.json`、`build/counseling-faces-after.json`、`deliverables/counseling-room/double-faces-20261025/brief-checks.json`。

整站建置遇到另一項進行中的推薦室相依設定尚未完成，因此使用 `tools/patch_counseling_faces_release.py`，以先前正式版為基底，只替換桌面及手機高／低階輔導室包中的模型。其他 PCK 項目逐 byte 保留，並更新包雜湊、啟動包內清單、gzip、下載清單與服務工作者。帳號網站及登入 Worker 沿用正式內容。部署結果另記於 `build/counseling-double-faces-deploy.log` 和 `build/releases/LATEST.json`。
