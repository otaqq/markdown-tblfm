# markdown-tblfm

Evaluate spreadsheet formulas in Markdown tables from Emacs, using the
syntax of the Obsidian plugin [Advanced Tables][at].

Formulas live in HTML comments right below the table, so the same file can be
recalculated in Emacs and in Obsidian, and renders as a plain table on GitHub
and everywhere else.

```markdown
| item | hours | amount |
| ---- | ----- | ------ |
| a    | 3     | 12000  |
| b    | 1.5   | 6000   |
| tot  | 4.5   | 18000  |
<!-- TBLFM: $3=($2*4000) -->
<!-- TBLFM: @>$2=sum(@I..@-1) :: @>$3=sum(@I..@-1) -->
```

## Install

Requires Emacs 27.1 or later. Org is used for the calculation and ships with
Emacs. It works in any buffer; `markdown-mode` is not required.

```elisp
(use-package markdown-tblfm
  :vc (:url "https://github.com/otaqq/markdown-tblfm")
  :commands (markdown-tblfm-recalculate markdown-tblfm-recalculate-buffer))
```

Or put `markdown-tblfm.el` on your `load-path` and `(require 'markdown-tblfm)`.

## Usage

| Command | What it does |
| ------- | ------------ |
| `M-x markdown-tblfm-recalculate` | Recalculate the table at point (point may also be on a formula line). With `C-u`, recalculate every table in the buffer |
| `M-x markdown-tblfm-recalculate-buffer` | Recalculate every table with formulas in the buffer |

No key is bound by default. For example:

```elisp
(global-set-key (kbd "C-c =") #'markdown-tblfm-recalculate)
```

Then `C-c =` recalculates the table at point and `C-u C-c =` every table in the
buffer.

To recalculate every table each time a Markdown file is saved:

```elisp
(add-hook 'markdown-mode-hook
          (lambda ()
            (add-hook 'before-save-hook #'markdown-tblfm-recalculate-buffer nil t)))
```

The table is reformatted on recalculation: columns are padded to the same
width (wide characters count as two columns) and the alignment in the delimiter
row (`:---`, `:---:`, `---:`) is kept.

## Formula syntax

See the Advanced Tables [formula documentation][fm]. In short:

- `@` is a row and `$` is a column: `@2$3`, `$>` (last column), `@>` (last
  row), `@I` (the header separator), relative `@-1`, `$+2`.
- Ranges: `@I..@-1`, `$1..$3`.
- Arithmetic in parentheses: `($2*4000)`, `(@-1+1)`.
- Functions: `sum()`, `mean()`, `if(cond, a, b)`.
- Formatting: `;%.2f`.
- Chain formulas with `::`, or put them on several `TBLFM` lines.

## How it works

The table is copied into a temporary Org buffer, the formulas are translated
(`sum` → `vsum`, `mean` → `vmean`) and evaluated by the Org spreadsheet, and the
result is written back as a Markdown table.

Differences from Advanced Tables:

- Every field is read as a number (Org's `N` mode): empty or text fields count
  as 0.
- Org evaluates column formulas before field formulas, regardless of the order
  in which they are written.
- The Org spreadsheet accepts more than Advanced Tables does (any Calc function,
  arithmetic without parentheses). Formulas using it will not work in Obsidian.
- Date and duration formats (`;dt`, `;hm`) are not supported.

## Development

Uses [Eask](https://emacs-eask.github.io/). Install it from the Eask releases,
or with [mise](https://mise.jdx.dev/) (`mise install`, see `mise.toml`).

```sh
make deps     # install development dependencies (package-lint)
make          # byte-compile, lint (checkdoc, package-lint) and test
make test
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).

[at]: https://github.com/tgrosinger/advanced-tables-obsidian
[fm]: https://github.com/tgrosinger/md-advanced-tables/blob/main/docs/formulas.md
