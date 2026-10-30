# Changelog

## 0.1.0 - 2026-10-30

First release.

- `markdown-tblfm-recalculate`: evaluate the Advanced Tables formulas
  (`<!-- TBLFM: ... -->`) of the Markdown table at point.
- `markdown-tblfm-recalculate-buffer`: do the same for every table in the
  buffer.
- Supported: cell and range references, arithmetic, `sum`, `mean`, `if`,
  `;%.2f` formatting, `::` chaining and several formula lines.
- The table is realigned (wide characters count as two columns) and the
  delimiter row alignment is kept.
