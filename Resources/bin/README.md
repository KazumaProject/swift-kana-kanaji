# Supplemental Dictionary Sources

`Resources/bin/` is the repository-local source directory for supplemental dictionary TSV files.
GitHub Actions copies any `*.tsv` files from this directory into the Mozc source directory before running:

```bash
kana-kanji build-all-dictionaries --source mozc_fetch --output dist
```

Local builds can use the same convention:

```bash
swift run kana-kanji download --output ./mozc_fetch --overwrite
cp Resources/bin/*.tsv ./mozc_fetch/
swift run kana-kanji build-all-dictionaries --source ./mozc_fetch --output ./dist
```

The following TSV files are currently checked in from the Kotlin reference implementation's `src/main/bin/` directory:

- `emoji_data.tsv`
- `emoticon.tsv`
- `symbol.tsv`
- `reading_correction.tsv`

The Kotlin reference archive used for the initial import is distributed under the MIT license. See `LICENSE.kotlin-kana-kanji-converter` in this directory for the copied license notice.

`single_kanji.tsv` and `kotowaza.tsv` are supported input names, but they are not present in the Kotlin `src/main/bin/` source used for this import. They are optional supplemental dictionaries: place either file in this directory when you have a compatible source, and the release workflow will build and publish that dictionary automatically. If they are absent, `build-all-dictionaries` skips those kinds.
