# `make upgrade` 定期実行通知の再設計

- 日付: 2026-08-12
- 対象: `scripts/upgrade-scheduled.sh`、`group_vars/all.yml`

## 背景と課題

launchd から1日2回実行される `make upgrade` は、結果を macOS の通知センターに表示している。
現行実装には2つの問題がある。

1. **通知の全文が読めない。** `osascript` の `display notification` はバナー表示が2行程度で
   打ち切られる。
2. **クリックしても詳細に飛べない。** `display notification` はクリックアクションを持てない
   という macOS 側の仕様上の制約。

加えて、調査の過程で現行の要約生成そのものに問題があることが判明した。

## 現行実装の問題（要約生成）

現行スクリプトはログを `claude -p --model haiku` に渡して200文字以内に要約させている。
実ログを検証した結果、この処理は不要と判断した。

1. **要約する分量がない。** 実ログは67行・4KB未満。スクリプトの `tail -c 40000` は
   ログ全体より大きく、圧縮対象が存在しない。
2. **必要な情報は構造化されて出力済み。** `roles/homebrew/tasks/upgrade.yml` は
   `loop` + `loop_control.label` でアップグレードを回すため、更新パッケージ名は
   `changed: [host] => (item=NAME)` の形で機械的に取得できる。手動対応の案内は
   `debug` の固定文言、成否は PLAY RECAP と exit status から取れる。
3. **既存実装自身が LLM 出力を信用していない。** 「手動」対応の有無は要約の取りこぼしを
   防ぐため別途 `grep` して追記している。最重要情報を機械判定に戻している時点で、
   この設計は機能していない。
4. **非決定的。** 同じログでも実行ごとに文面が変わり、前回との比較ができない。
5. **カテゴリ誤り。** プロンプトは「Mac App Store の更新件数」を要求しているが、
   `roles/mas/tasks/upgrade.yml` は `mas outdated` を案内するだけで自動更新を一切行わない。
   MAS は「更新件数」ではなく「要手動対応」に分類されるべき項目であり、この件数は常に0にしかならない。

LLM を廃止する副次的効果として、「200文字以内」という文字数制約が消える。
制約はバナーに収めるためのものだったが、クリックで開くファイルに全文を出す方針では不要になる。

## 設計

### 全体構成

`scripts/upgrade-scheduled.sh` 内で完結する。Ansible ロールには変更を加えない。

```
make upgrade → logs/upgrade-<timestamp>.log   （従来通り・最新20件を保持）
                     ↓ awk でパース
               logs/latest-summary.txt        （固定パス・毎回上書き）
                     ↓
               terminal-notifier で通知 → クリックで latest-summary.txt を開く
```

クリック先を固定パスにするのが要点。通知ごとに異なるパスを渡す必要がなく、
「いつでも最新が同じ場所にある」状態になる。

`latest-summary.txt` は `upgrade-*.log` のグロブに一致しないため、
既存のログ間引き処理（`KEEP_LOGS=20`）の対象外となる。

### サマリファイルの内容

該当がないセクションは、セクションごと省略する。

```
make upgrade: 失敗 (exit 2)
2026-08-12 10:07:03 → 10:09:41

[更新]
Formula (2)
  awscli
  ollama
Cask (2)
  notion
  slack

[要手動対応]
sudo が必要な Cask (3)
  brew upgrade --cask docker-desktop logi-options+ microsoft-office
Mac App Store (1)
  Xcode
  → App Store の「アップデート」タブから手動で

[エラー]
workspace-base : workspace-baseをclone/更新
  Permission denied (publickey) — ssh-agent の署名に失敗

[詳細ログ]
logs/upgrade-20260812-100703.log
```

### パース方式

`TASK [...]` 行で状態を持つ awk を書き、直後の結果行から項目名を拾う。
実ログで以下の2書式を確認済み。

- `changed: [<host>] => (item=<NAME>)`
- `failed: [<host>] (item=<NAME>) =>`

アンカーとなるタスク名は以下。

| 抽出項目 | アンカー |
|---|---|
| Formula 更新 | `TASK [homebrew : Formulaパッケージをアップグレード]` |
| Cask 更新 | `TASK [homebrew : 通常のCaskパッケージをアップグレード]` |
| sudo 必要 Cask | debug 文言 `以下のCaskはrootパスワードが必要なため` |
| 権限エラー Cask | debug 文言 `以下のCaskは対象Appの所有者/権限がずれているため` |
| MAS 要対応 | debug 文言 `以下のMac App Storeアプリにアップデートがあります` |
| エラー | `fatal: [<host>]` 行と、直近の `TASK [...]` 行から得たタスク名 |
| 成否 | `PLAY RECAP` 行および exit status |

エラーの詳細は `msg:` 配下が複数行にわたるため、サマリには先頭1〜2行のみを載せる。
全文は詳細ログを参照させる。

これらのタスク名・文言はこのリポジトリ自身が定義しているため、実質的に固定できる。
ただしロール側のリネームでパーサが壊れる結合があるため、**アンカー文字列はスクリプト
冒頭に定数としてまとめて定義し、結合点を1箇所に閉じ込める。**

### 通知

```
title: make upgrade: 失敗
body:  更新 Formula 2 / Cask 2
       ⚠️ 要手動 4件・エラー 1件
```

バナーに収まる2行に抑え、全文はクリックで開かせる。
`terminal-notifier -open "file:///.../latest-summary.txt"` を使用する。

拡張子は `.md` ではなく `.txt` とする。既定で TextEdit が開くため、
ハンドラ未登録でクリックしても何も起きない事故を避けられる。

**未検証事項:** `terminal-notifier` は現時点で未インストールのため `-open` の挙動は未確認。
実装時に実際に実行して確認し、期待通りに動作しない場合は `-execute "open <path>"` に切り替える。

### 通知の発行条件

以下のいずれかに該当する場合のみ通知する。

- exit status が 0 以外
- 更新があった（Formula または Cask が1件以上）
- 要手動対応がある（sudo 必要 Cask / 権限エラー Cask / MAS のいずれか1件以上）

上記のいずれにも該当しない場合（exit 0・更新0件・要対応0件）は通知しない。
1日2回の実行で「更新なし」通知が定期的に流れるのを避け、
「通知が出た＝何かある」状態を維持して通知そのものの情報量を上げる。

**サマリファイルは通知の有無にかかわらず常に生成する。** 静かな回でも、
見たいときに `open logs/latest-summary.txt` すれば最新の結果を確認できる。

### 依存の追加

`group_vars/all.yml` の `brew_formula` に `terminal-notifier` を追加する。
反映は `make homebrew`。初回のみシステム設定での通知許可の承認が必要。

### フォールバック

`terminal-notifier` が存在しない場合（プロビジョニング前のマシンなど）は、
従来の `osascript display notification` で同じ2行を表示する。
クリックはできないが通知は途切れない。

### 削除するもの

- `CLAUDE_BIN` 定数
- `PROMPT` ヒアドキュメント
- `claude -p` 呼び出し
- LLM 失敗時の `ok=` 行フォールバック
- 「手動」の `grep` 判定（構造化パースに吸収）

## テスト方針

パース処理をスクリプト本体から切り出し、ログファイルを引数に取ってサマリを標準出力する
形にすることで、実際の `make upgrade` を走らせずに検証できるようにする。

`logs/` に残っている既存ログが、そのままテストケースとして使える。

| ログ | 検証内容 |
|---|---|
| `upgrade-20260812-100703.log` | 更新0件・sudo 必要 Cask 3件・エラー1件（failed=1） |
| `upgrade-20260811-102156.log` | Formula 2件・Cask 更新および failed 混在 |
| `upgrade-20260810-170703.log` | Cask 1件のみ更新 |

通知の発行条件（正常無変化で黙る）も、これらのログに対する判定結果で確認する。

## 影響範囲

| ファイル | 変更 |
|---|---|
| `scripts/upgrade-scheduled.sh` | 要約生成の置き換え、通知発行条件の追加 |
| `group_vars/all.yml` | `brew_formula` に `terminal-notifier` を追加 |
| `CLAUDE.md` | 「Scheduled `make upgrade` (launchd)」節の記述を更新 |

`roles/launchd/` および plist テンプレートには変更なし。スケジュールも現行のまま
（10:07 / 17:07）。
