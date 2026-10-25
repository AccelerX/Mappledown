# Mappledown

A lightweight iPad app for reading and editing Markdown with real LaTeX math. Open `.md` files from the Files app, read them with MathJax-quality formulas, make quick edits, and export to PDF or HTML.

- **Math:** MathJax 3, bundled in the app (works offline). Handles `$…$`, `$$…$$`, `\(…\)`, `\[…\]`, `align`, `cases`, matrices, `\newcommand`, equation numbers and `\eqref`.
- **Markdown:** markdown-it with tables, footnotes and code highlighting.
- **Editing:** Edit, Split or Preview, live preview while you type, math keys, autosave back to the original file.
- **Export:** paged PDF (A4 or US Letter, page numbers) or a self-contained HTML file, through the iPad share sheet.
- **Requires:** iPadOS 16 or later. Installed with TrollStore.

## Install on your iPad

1. On the iPad, open [Releases › latest](https://github.com/AccelerX/Mappledown/releases/tag/latest) in Safari and download **Mappledown.ipa**.
2. In the Files app, open **Downloads**, touch and hold `Mappledown.ipa`, tap **Share**, then **TrollStore**.
3. Tap **Install**. To update later, install the new .ipa over the old one.

## How it's built

There is no Xcode project in the repo. A GitHub Actions workflow (`.github/workflows/build.yml`) runs on a cloud Mac:

1. tests the Markdown/math renderer in Chromium (`scripts/preview-test.js`),
2. generates the Xcode project from `project.yml` with XcodeGen,
3. builds the app without Apple signing, fakesigns it with `ldid`, and packs `Mappledown.ipa`,
4. publishes it to the `latest` release on every push to `main`.

## Layout

| Path | What it is |
| --- | --- |
| `Mappledown/App` | App entry point |
| `Mappledown/Models` | Settings, open document, recents and linked folders |
| `Mappledown/Views` | SwiftUI screens: library, folders, document, export, settings |
| `Mappledown/Render` | The preview web view and PDF/HTML export |
| `Mappledown/Resources/Web` | The preview page: `render.js` (Markdown + math plugin), CSS, bundled libraries |
| `Mappledown/Resources/Samples` | `Math stress test.md`, copied to On My iPad on first launch |

To check rendering on any computer: `npm install playwright && node scripts/preview-test.js your-file.md out.png`.

## Licenses

MathJax (Apache 2.0), markdown-it and markdown-it-footnote (MIT), highlight.js (BSD 3-Clause). Their license files are in `Mappledown/Resources/Web/vendor`.
