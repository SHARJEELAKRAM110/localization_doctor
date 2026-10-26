# Examples

Two small projects demonstrate what `localization_doctor` reports. Neither is
meant to be built: they contain only what the audit reads.

| Project | Contents |
|---|---|
| [`sample_app`](sample_app) | A gen-l10n project (ARB, English base, Urdu and French). It has one missing translation, one unused key, one placeholder mismatch and one empty value. |
| [`broken_project`](broken_project) | Intentionally broken files: duplicate keys in ARB and nested JSON, a malformed JSON file, a malformed ARB file, an ICU syntax error and a nested-structure mismatch. |

Run them from the package root:

```bash
dart run localization_doctor audit --path example/sample_app
dart run localization_doctor audit --path example/broken_project --base-locale en
dart run localization_doctor audit --path example/sample_app --format terminal --format json --format html --output-dir build/demo
```

Both projects are expected to fail the audit (exit code 1).
