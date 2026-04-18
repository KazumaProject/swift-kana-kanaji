# Swift Kana-Kanji

Swift ネイティブのかな漢字変換プロトタイプです。

Mozc の `dictionary00.txt` 〜 `dictionary09.txt` からビルド済み LOUDS 辞書を生成し、その辞書をロードしてかな入力の候補を返します。接続コスト `connection_single_column.txt` も使用できます。

辞書 lookup は Swift 実装の LOUDS trie を使います。LOUDS のビット列は `UInt64` に pack し、rank/select で子ノード範囲を引きます。

変換は C++ 版と同じ流れで、入力位置ごとの候補ノードグラフを構築し、forward DP で累積コストを計算したあと、EOS 側から backward A* で N-best を列挙します。

## 辞書のダウンロード

Mozc の `dictionary_oss` から、辞書 10 ファイルと接続コストをダウンロードできます。

```bash
swift run kana-kanji download --output ./mozc_fetch
```

既存ファイルを上書きする場合:

```bash
swift run kana-kanji download --output ./mozc_fetch --overwrite
```

## LOUDS 辞書のビルド

ダウンロードした Mozc TSV から、実行時に使う LOUDS 辞書ファイルを生成します。

```bash
swift run kana-kanji build-dictionary \
  --source ./mozc_fetch \
  --output ./artifacts
```

`./artifacts` には C++ 版 release と同じ構成のファイルを出力します。

- `yomi_termid.louds`
- `tango.louds`
- `token_array.bin`
- `pos_table.bin`
- `connection_single_column.bin`

## 実行

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

## Swift から使う

```swift
import KanaKanjiCore

let dictionaryDirectory = URL(fileURLWithPath: "./mozc_fetch")
let artifactsDirectory = URL(fileURLWithPath: "./artifacts")

try MozcDictionaryDownloader.downloadDictionaryOSS(to: dictionaryDirectory)
try MozcDictionary.buildArtifacts(
    from: dictionaryDirectory,
    to: artifactsDirectory
)

let dictionary = try MozcDictionary(artifactsDirectory: artifactsDirectory)
let connection = try ConnectionMatrix.loadBinaryBigEndianInt16(
    artifactsDirectory.appendingPathComponent("connection_single_column.bin")
)
let converter = KanaKanjiConverter(dictionary: dictionary, connectionMatrix: connection)

let candidates = converter.convert("きょうのてんき")
print(candidates.map(\.text))
```

## 現在の範囲

- Mozc `dictionary_oss` のダウンロード
- Mozc TSV 辞書のロード
- C++ 版 release と同じ 5 artifact の生成
- `yomi_termid.louds` / `tango.louds` / `token_array.bin` / `pos_table.bin` のロード
- LOUDS trie による読み common prefix search
- packed bit vector + rank/select
- predictive search 用の LOUDS subtree traversal
- C++ 版と同じ graph construction
- forward DP + backward A* による N-best 変換
- 単語コスト + 接続コストによるスコアリング
- 未知語 1 文字 fallback
- CLI とユニットテスト

今後の高速化候補は、ビルド済み辞書をさらに compact な可変長整数形式にし、起動時に mmap で読む形式にすることです。
