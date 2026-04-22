# Swift Kana-Kanji

Swift ネイティブのかな漢字変換プロトタイプです。

Mozc の `dictionary00.txt` 〜 `dictionary09.txt` を基本辞書としてビルド済み LOUDS 辞書を生成します。さらに emoji・emoticon・symbol・reading_correction・kotowaza・single_kanji の補助辞書を独立した artifact セットとしてビルド・ロードできます。接続コスト `connection_single_column.txt` も使用できます。

辞書 lookup は Swift 実装の LOUDS trie を使います。LOUDS のビット列は `UInt64` に pack し、rank/select で子ノード範囲を引きます。

変換は C++ 版と同じ流れで、入力位置ごとの候補ノードグラフを構築し、forward DP で累積コストを計算したあと、EOS 側から backward A* で N-best を列挙します。

---

## 対応している辞書種類

| kind (rawValue)      | 説明                              | ソースファイル                          | connection matrix |
|----------------------|-----------------------------------|-----------------------------------------|-------------------|
| `main`               | Mozc OSS メイン辞書               | `dictionary00.txt` … `dictionary09.txt` | 必要              |
| `single_kanji`       | 単漢字補助辞書                    | `single_kanji.tsv`                      | 不要              |
| `emoji`              | 絵文字補助辞書                    | `emoji_data.tsv`                        | 不要              |
| `emoticon`           | 顔文字補助辞書                    | `emoticon.tsv`                          | 不要              |
| `symbol`             | 記号補助辞書                      | `symbol.tsv`                            | 不要              |
| `reading_correction` | 読み誤り補正辞書                  | `reading_correction.tsv`                | 不要              |
| `kotowaza`           | ことわざ補助辞書                  | `kotowaza.tsv`                          | 不要              |

各補助辞書の入力ファイルは Kotlin 参照実装の `src/main/bin/` と同じフォーマットです。
このリポジトリでは `Resources/bin/` を補助辞書ソース置き場として使います。GitHub Actions の release workflow は、ここにある `*.tsv` を Mozc の取得済みソースディレクトリへコピーしてから `build-all-dictionaries` を実行します。

`emoji_data.tsv`、`emoticon.tsv`、`symbol.tsv`、`reading_correction.tsv` は Kotlin 参照実装由来のファイルを同梱しています。`single_kanji.tsv` と `kotowaza.tsv` は、少なくとも現在参照している Kotlin `src/main/bin/` には存在しないため標準同梱ではありません。必要な場合は互換フォーマットの TSV を `Resources/bin/` または `--source` ディレクトリに追加してください。存在するものだけビルドされ、無い補助辞書はスキップされます。

---

## 出力ディレクトリ構成

`build-all-dictionaries` および `build-dictionary --kind` コマンドは、辞書種別ごとにサブディレクトリを作成します。

```
<output>/
  main/
    yomi_termid.louds
    tango.louds
    token_array.bin
    pos_table.bin
    connection_single_column.bin   ← main のみ
  single_kanji/
    yomi_termid.louds
    tango.louds
    token_array.bin
    pos_table.bin
  emoji/
    yomi_termid.louds  …
  emoticon/  …
  symbol/    …
  reading_correction/  …
  kotowaza/  …
```

> **互換性:** 既存の `build-dictionary --source X --output Y`（`--kind` なし）は従来通りフラット出力（直接 `Y/` 以下にファイルを書く）のまま動作します。

---

## 辞書のダウンロード（Mozc メイン辞書）

```bash
swift run kana-kanji download --output ./mozc_fetch
# 既存ファイルを上書きする場合:
swift run kana-kanji download --output ./mozc_fetch --overwrite
```

---

## 全辞書のビルド

メイン辞書と補助辞書をまとめてビルドします。ソースファイルが存在しない補助辞書はスキップされます。

```bash
swift run kana-kanji download --output ./mozc_fetch --overwrite
cp Resources/bin/*.tsv ./mozc_fetch/
swift run kana-kanji build-all-dictionaries \
  --source ./mozc_fetch \
  --output ./dist
```

`build-all-dictionaries` の `--source` には、Mozc の `dictionary00.txt` 〜 `dictionary09.txt`、必要なら `connection_single_column.txt`、および補助辞書 TSV 群（`emoji_data.tsv`、`emoticon.tsv`、`symbol.tsv`、`reading_correction.tsv`、`single_kanji.tsv`、`kotowaza.tsv`）をまとめて置いたディレクトリを渡します。

GitHub Actions では `Resources/bin/*.tsv` が自動的に利用されます。ローカルでも同じ構成にしたい場合は、上の例のように `Resources/bin/*.tsv` を `mozc_fetch/` へコピーしてからビルドしてください。一部の TSV だけを置いた場合は、その種類だけ `dist/<kind>/` が生成されます。

補助辞書だけをローカルで確認したい場合は、`--source Resources/bin` のままでも実行できます。この場合、Mozc メイン辞書はスキップされ、存在する補助辞書だけが生成されます。

デフォルトでは、ソースファイルが無い辞書 kind はスキップされます。`--no-skip-missing` フラグを付けると、無いソースファイルでエラーを出します。

### Release workflow の辞書生成

`.github/workflows/release-dictionaries.yml` は tag push または manual dispatch で次の流れを実行します。

1. `kana-kanji download --output mozc_fetch --overwrite` で Mozc メイン辞書ソースを取得
2. `Resources/bin/*.tsv` があれば `mozc_fetch/` にコピー
3. `kana-kanji build-all-dictionaries --source mozc_fetch --output dist` を実行
4. `dist/<kind>/` ごとに `<kind>.zip` を作成
5. `main.zip` と後方互換用の `dist/` 直下 main artifact 5 ファイルを必須 release asset として upload
6. `emoji.zip`、`emoticon.zip`、`symbol.zip`、`reading_correction.zip`、`single_kanji.zip`、`kotowaza.zip` は、生成されたものだけ best-effort で upload

`Resources/bin/*.tsv` が 1 個も無い場合でも `main` のみ生成して成功します。一部だけある場合は、その TSV に対応する補助辞書だけが zip 化されます。

---

## 単一辞書のビルド

### メイン辞書（後方互換・フラット出力）

```bash
swift run kana-kanji build-dictionary \
  --source ./mozc_fetch \
  --output ./artifacts
```

### 補助辞書（`--kind` 指定・サブディレクトリ出力）

```bash
# emoji のみビルド → ./dict_root/emoji/ 以下に書き出す
swift run kana-kanji build-dictionary \
  --kind emoji \
  --source ./mozc_fetch \
  --output ./dict_root

# 利用可能な kind 一覧を確認
swift run kana-kanji list-dictionary-kinds
```

---

## 実行

### メイン辞書を使って変換

```bash
swift run kana-kanji \
  --artifacts-dir ./artifacts \
  --connection ./artifacts/connection_single_column.bin \
  --connection-binary \
  --query きょうのてんき \
  --limit 10
```

標準入力からも変換できます。

```bash
echo きょうのてんき | swift run kana-kanji \
  --artifacts-dir ./artifacts \
  --connection ./artifacts/connection_single_column.bin \
  --connection-binary
```

出力は `候補\t読み\tスコア` です。

---

## Swift から使う

### メイン辞書

```swift
import KanaKanjiCore

let sourceDir = URL(fileURLWithPath: "./mozc_fetch")
let artifactsDir = URL(fileURLWithPath: "./artifacts")

try MozcDictionaryDownloader.downloadDictionaryOSS(to: sourceDir)
try MozcDictionary.buildArtifacts(from: sourceDir, to: artifactsDir)

let dictionary = try MozcDictionary(artifactsDirectory: artifactsDir)
let connection = try ConnectionMatrix.loadBinaryBigEndianInt16(
    artifactsDir.appendingPathComponent("connection_single_column.bin")
)
let converter = KanaKanjiConverter(dictionary: dictionary, connectionMatrix: connection)

let candidates = converter.convert("きょうのてんき")
print(candidates.map(\.text))
```

### 全辞書をビルドしてロード

```swift
import KanaKanjiCore

let sourceDir  = URL(fileURLWithPath: "./mozc_fetch")
let outputRoot = URL(fileURLWithPath: "./dict_root")

// 全辞書ビルド（ソースが存在しない補助辞書はスキップ）
let built = try DictionaryArtifactBuilder.buildAll(from: sourceDir, to: outputRoot)
print("Built:", built.map(\.rawValue))

// 全辞書を一括ロード
let dicts = try DictionaryArtifactBuilder.loadAll(from: outputRoot)

// 絵文字辞書を使って検索
if let emojiDict = dicts[.emoji] {
    let matches = emojiDict.prefixMatches(in: Array("えもじ"), from: 0)
    print(matches.flatMap { $0.entries.map(\.surface) })
}
```

### 補助辞書を個別にビルド・ロード

```swift
import KanaKanjiCore

let sourceDir  = URL(fileURLWithPath: "./mozc_fetch")
let outputRoot = URL(fileURLWithPath: "./dict_root")

// emoji だけビルド
try DictionaryArtifactBuilder.build(kind: .emoji, from: sourceDir, to: outputRoot)

// ロード（便利メソッド）
let emojiDict = try MozcDictionary.load(kind: .emoji, from: outputRoot)
let kotowazaDict = try MozcDictionary.load(kind: .kotowaza, from: outputRoot)
```

### エントリリストから直接ビルド

```swift
let entries = [
    DictionaryEntry(yomi: "えもじ", leftId: 2641, rightId: 2641, cost: 6000, surface: "😀"),
]
let outputDir = URL(fileURLWithPath: "./my_emoji_artifacts")
try DictionaryArtifactBuilder.buildFromEntries(entries, to: outputDir)
let dict = try MozcDictionary(artifactsDirectory: outputDir)
```

---

## 入力ファイルフォーマット

### emoji_data.tsv / emoticon.tsv

タブ区切り。1 列目が絵文字/顔文字（表記）、2 列目以降は半角スペース区切りの読み文字列。

```
😀    えもじ わらい    にこにこ
(^^)  にこ にこにこ
```

### symbol.tsv

空白区切り。1 列目が記号（表記）、それ以降が読み文字列。

```
、    とうてん , 、 ， てん
```

### reading_correction.tsv

タブ区切り 3 列: `表記\t誤読み\t正しい読み`

```
お土産    おどさん    おみやげ
```

誤読み（2 列目）が yomi として登録されます。surface は `"表記\t正しい読み"` でエンコードされます。

### kotowaza.tsv

タブ区切り 2 列: `表記\t読み`

```
一期一会    いちごいちえ
```

### single_kanji.tsv

タブまたはカンマ区切り 2 列: `読み\t漢字列`（漢字列の 1 文字ずつが個別エントリになる）

```
あ    亜哀挨愛
い    以位意
```

---

## 現在の範囲

- Mozc `dictionary_oss` のダウンロード
- Mozc TSV 辞書のロード
- **7 種類の辞書を個別 artifact セットとしてビルド**
- LOUDS trie による読み common prefix search
- packed bit vector + rank/select
- predictive search 用の LOUDS subtree traversal
- C++ 版と同じ graph construction
- forward DP + backward A* による N-best 変換
- 単語コスト + 接続コストによるスコアリング
- 未知語 1 文字 fallback
- CLI とユニットテスト
