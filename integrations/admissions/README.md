# 落點分析網站整合來源

`admissions-site/` 是被主專案忽略的獨立 checkout。本資料夾保存可重現的整合變更，避免主專案發布後遺失網站原始碼。

- 上游：[113–115 admission screening](https://github.com/stu310101-arch/113-115-admission-screening)
- `source-manifest.json` 固定上游完整 commit、整合後來源檔案清單、Git tree、模式與 SHA-256。
- `integration.patch` 是相對該 commit 的 Git binary patch，包含新增且原本未追蹤的來源檔、修改及刪除。
- Firebase Web 設定是公開設定；簽章私鑰、`.env*`、`.dev.vars*`、PEM 與忽略的建置／套件／模擬器檔案不進入 snapshot。

從主專案根目錄，在來源修改與測試都完成後執行：

```powershell
python tools/snapshot_admissions_source.py snapshot
python tools/snapshot_admissions_source.py verify --original-bytes
```

snapshot 使用臨時 `GIT_INDEX_FILE`：`read-tree HEAD`、`add -A`、輸出 binary patch；不修改原 checkout 的 index、不 commit、不更動上游網站。
若來源在擷取期間變動會失敗，請停止編輯後重試。每次更新需一起納入 patch 與 manifest。

在尚無 `admissions-site/` 的 checkout 還原：

```powershell
python tools/snapshot_admissions_source.py restore
python tools/snapshot_admissions_source.py verify
```

也可指定另一個**尚不存在**的目錄驗證還原，現有資料夾永遠不會被覆寫：

```powershell
python tools/snapshot_admissions_source.py restore --destination C:/temp/starpath-admissions-restored
```

restore 會 clone 固定上游、checkout 指定 commit、檢查並套用 patch，再驗證所有來源檔（含新增檔）的完整 inventory。
新增檔仍為 untracked，修改檔維持 unstaged。套件與靜態輸出請依網站 `package.json` 重新安裝／建置。

Git 的文字正規化可能把 Windows checkout 的 CRLF 存成 LF。可重現的 `source_files` 與 `source_sha256` 以 Git canonical blob bytes 計算；restore 固定 `core.autocrlf=false`。
`working_tree_files`／`working_tree_sha256` 另保留擷取當時的原始工作目錄 bytes，可與發布包的來源追蹤清單對照。
因此跨平台還原使用一般 `verify`；只有比對當時原 checkout 才使用 `--original-bytes`。

工具的 fixture 測試包含已修改與新增 binary/text source、刪除、忽略檔排除、來源 index 不變、確定性、損毀與既存還原目錄拒絕：

```powershell
python -m unittest discover -s tools -p test_snapshot_admissions_source.py
```
