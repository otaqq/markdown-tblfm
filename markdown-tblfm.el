;;; markdown-tblfm.el --- Evaluate Advanced Tables formulas in Markdown tables  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 otaqq

;; Author: otaqq <taqqan@gmail.com>
;; Maintainer: otaqq <taqqan@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: wp, convenience
;; URL: https://github.com/otaqq/markdown-tblfm
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Evaluate spreadsheet formulas in Markdown tables, using the syntax of
;; the Obsidian plugin Advanced Tables.  Formulas live in HTML comments
;; directly below the table, so the same file can be recalculated in
;; Emacs and in Obsidian, and renders as a plain table everywhere else:
;;
;;   | item | hours | amount |
;;   | ---- | ----- | ------ |
;;   | a    | 3     |        |
;;   | b    | 1.5   |        |
;;   | tot  |       |        |
;;   <!-- TBLFM: $3=($2*4000) -->
;;   <!-- TBLFM: @>$2=sum(@I..@-1) :: @>$3=sum(@I..@-1) -->
;;
;; M-x markdown-tblfm-recalculate fills in the table at point; with a
;; prefix argument (C-u), or with M-x markdown-tblfm-recalculate-buffer,
;; every table in the buffer is recalculated.
;;
;; The formulas are evaluated by the Org table spreadsheet: the table is
;; copied into a temporary Org buffer, the formulas are translated
;; (`sum' -> `vsum', `mean' -> `vmean'), and the results are written back
;; as a Markdown table.  Column alignment in the delimiter row is kept.

;;; Code:

(require 'org)
(require 'org-table)
(require 'seq)
(require 'subr-x)

(defgroup markdown-tblfm nil
  "Evaluate Advanced Tables formulas in Markdown tables."
  :group 'text
  :prefix "markdown-tblfm-")

(defconst markdown-tblfm--row-re "^[ \t]*|"
  "Regexp matching a Markdown table row.")

(defconst markdown-tblfm--formula-re
  "^[ \t]*<!--[ \t]*TBLFM:[ \t]*\\(.*?\\)[ \t]*-->[ \t]*$"
  "Regexp matching a formula line; group 1 is the formula text.")

(defconst markdown-tblfm--delimiter-cell-re "\\`:?-+:?\\'"
  "Regexp matching one cell of the header delimiter row.")

(defconst markdown-tblfm--pipe-placeholder (string #xE000)
  "Stand-in for an escaped pipe while the table is in Org.")

(defconst markdown-tblfm--functions
  '(("sum" . "vsum") ("mean" . "vmean"))
  "Advanced Tables function names and their Org (Calc) counterparts.")

;;;; Parsing

(defun markdown-tblfm--split-row (line)
  "Split the Markdown table LINE into a list of trimmed cell strings.
Escaped pipes are replaced by `markdown-tblfm--pipe-placeholder'."
  (let ((s (string-trim
            (replace-regexp-in-string
             "\\\\|" markdown-tblfm--pipe-placeholder line t t))))
    (setq s (string-remove-prefix "|" s))
    (when (string-suffix-p "|" s)
      (setq s (substring s 0 -1)))
    (mapcar #'string-trim (split-string s "|"))))

(defun markdown-tblfm--delimiter-row-p (cells)
  "Return non-nil if CELLS form a header delimiter row."
  (and cells
       (seq-every-p (lambda (c) (string-match-p markdown-tblfm--delimiter-cell-re c))
                    cells)))

(defun markdown-tblfm--alignment (cell)
  "Return the alignment of the delimiter CELL: left, right, center or nil."
  (let ((l (string-prefix-p ":" cell))
        (r (string-suffix-p ":" cell)))
    (cond ((and l r) 'center) (l 'left) (r 'right))))

(defun markdown-tblfm--bounds ()
  "Return (BEG END FORMULAS) for the table at point.
BEG and END delimit the table rows; END is the start of the line after
the table.  FORMULAS is the list of formula strings below the table.
Point may be on a table row or on one of its formula lines."
  (save-excursion
    (beginning-of-line)
    (while (and (looking-at markdown-tblfm--formula-re) (not (bobp)))
      (forward-line -1))
    (unless (looking-at markdown-tblfm--row-re)
      (user-error "Not in a Markdown table"))
    (while (and (not (bobp))
                (save-excursion
                  (forward-line -1)
                  (looking-at markdown-tblfm--row-re)))
      (forward-line -1))
    (let ((beg (point)) end formulas)
      (while (and (not (eobp)) (looking-at markdown-tblfm--row-re))
        (forward-line 1))
      (setq end (point))
      (while (and (not (eobp)) (looking-at markdown-tblfm--formula-re))
        (push (match-string-no-properties 1) formulas)
        (forward-line 1))
      (list beg end (nreverse formulas)))))

;;;; Formula translation

(defun markdown-tblfm--translate-one (formula)
  "Translate one Advanced Tables FORMULA into Org syntax."
  (when (string-match-p ";[^;]*\\_<\\(dt\\|hm\\)\\_>[^;]*\\'" formula)
    (user-error "Date and duration formats (;dt, ;hm) are not supported: %s"
                formula))
  (let ((f (string-trim formula)))
    (dolist (pair markdown-tblfm--functions)
      (setq f (replace-regexp-in-string
               (concat "\\(\\`\\|[^[:alnum:]_]\\)" (car pair) "(")
               (concat "\\1" (cdr pair) "(") f t)))
    ;; Treat every field as a number (empty or text fields count as 0).
    (if (string-match ";\\([^;]*\\)\\'" f)
        (if (string-match-p "N" (match-string 1 f)) f (concat f "N"))
      (concat f ";N"))))

(defun markdown-tblfm--translate (formulas)
  "Translate FORMULAS (a list of formula lines) into one Org TBLFM string.
Each line may chain several formulas with \"::\"."
  (mapconcat #'markdown-tblfm--translate-one
             (seq-mapcat (lambda (line) (split-string line "::" t "[ \t]+"))
                         formulas)
             " :: "))

;;;; Evaluation

(defun markdown-tblfm--evaluate (rows tblfm)
  "Evaluate the Org TBLFM string over ROWS and return the resulting rows.
ROWS is a list whose elements are lists of cells or the symbol `hline'."
  (with-temp-buffer
    (let ((org-inhibit-startup t))
      (delay-mode-hooks (org-mode)))
    (dolist (row rows)
      (insert (if (eq row 'hline)
                  "|-|"
                (concat "| " (mapconcat #'identity row " | ") " |"))
              "\n"))
    (insert "#+TBLFM: " tblfm "\n")
    (goto-char (point-min))
    (let ((inhibit-message t))
      (org-table-recalculate t))
    (goto-char (point-min))
    (mapcar (lambda (row)
              (if (listp row) (mapcar #'substring-no-properties row) row))
            (org-table-to-lisp))))

(defun markdown-tblfm--clean-number (new old)
  "Return NEW without the trailing dot of a whole float from Calc.
Only cells whose value changed from OLD are touched."
  (if (and (not (equal new old))
           (string-match "\\`\\(-?[0-9]+\\)\\.\\'" new))
      (match-string 1 new)
    new))

;;;; Rendering

(defun markdown-tblfm--pad (cell width align)
  "Pad CELL to WIDTH columns according to ALIGN."
  (let ((gap (max 0 (- width (string-width cell)))))
    (pcase align
      ('right (concat (make-string gap ?\s) cell))
      ('center (let ((left (/ gap 2)))
                 (concat (make-string left ?\s) cell
                         (make-string (- gap left) ?\s))))
      (_ (concat cell (make-string gap ?\s))))))

(defun markdown-tblfm--delimiter (width align)
  "Return a delimiter cell of WIDTH columns for ALIGN."
  (pcase align
    ('left (concat ":" (make-string (1- width) ?-)))
    ('right (concat (make-string (1- width) ?-) ":"))
    ('center (concat ":" (make-string (- width 2) ?-) ":"))
    (_ (make-string width ?-))))

(defun markdown-tblfm--render (rows aligns indent)
  "Render ROWS as Markdown table lines, using ALIGNS and INDENT.
Return a list of strings, one per line."
  (let* ((rows (mapcar
                (lambda (row)
                  (if (listp row)
                      (mapcar (lambda (cell)
                                (replace-regexp-in-string
                                 markdown-tblfm--pipe-placeholder "\\|" cell t t))
                              row)
                    row))
                rows))
         (ncol (apply #'max 1 (mapcar (lambda (r) (if (listp r) (length r) 0))
                                      rows)))
         (widths (make-vector ncol 3)))
    (dolist (row rows)
      (when (listp row)
        (seq-do-indexed
         (lambda (cell i)
           (aset widths i (max (aref widths i) (string-width cell))))
         row)))
    (mapcar
     (lambda (row)
       (concat
        indent "| "
        (mapconcat
         #'identity
         (seq-map-indexed
          (lambda (width i)
            (let ((align (nth i aligns)))
              (if (eq row 'hline)
                  (markdown-tblfm--delimiter width align)
                (markdown-tblfm--pad (or (nth i row) "") width align))))
          (append widths nil))
         " | ")
        " |"))
     rows)))

;;;; Commands

(defun markdown-tblfm--recalculate-at-point ()
  "Recalculate the table at point.  Return non-nil if it had formulas."
  (pcase-let ((`(,beg ,end ,formulas) (markdown-tblfm--bounds)))
    (when formulas
      (let* ((text (buffer-substring-no-properties beg end))
             (lines (split-string (string-trim-right text "\n") "\n"))
             (indent (progn (string-match "\\`[ \t]*" (car lines))
                            (match-string 0 (car lines))))
             (aligns nil)
             (rows (mapcar
                    (lambda (line)
                      (let ((cells (markdown-tblfm--split-row line)))
                        (if (and (null aligns)
                                 (markdown-tblfm--delimiter-row-p cells))
                            (progn
                              (setq aligns (mapcar #'markdown-tblfm--alignment
                                                   cells))
                              'hline)
                          cells)))
                    lines))
             (result (markdown-tblfm--evaluate
                      rows (markdown-tblfm--translate formulas)))
             (result (seq-mapn
                      (lambda (new old)
                        (if (listp new)
                            (seq-map-indexed
                             (lambda (cell i)
                               (markdown-tblfm--clean-number
                                cell (and (listp old) (nth i old))))
                             new)
                          new))
                      result rows))
             (new-text (concat (string-join
                                (markdown-tblfm--render result aligns indent)
                                "\n")
                               (if (string-suffix-p "\n" text) "\n" "")))
             (line (count-lines beg (line-beginning-position)))
             (col (current-column)))
        (unless (equal new-text text)
          (save-excursion
            (goto-char beg)
            (delete-region beg end)
            (insert new-text))
          (goto-char beg)
          (forward-line line)
          (move-to-column col))
        t))))

;;;###autoload
(defun markdown-tblfm-recalculate (&optional all)
  "Evaluate the TBLFM formulas of the Markdown table at point.
Point may be on a table row or on a formula line below the table.
With prefix argument ALL, recalculate every table in the buffer, as
`markdown-tblfm-recalculate-buffer' does."
  (interactive "P")
  (if all
      (call-interactively #'markdown-tblfm-recalculate-buffer)
    (unless (markdown-tblfm--recalculate-at-point)
      (user-error "No TBLFM formulas below this table"))))

;;;###autoload
(defun markdown-tblfm-recalculate-buffer ()
  "Evaluate the TBLFM formulas of every Markdown table in the buffer.
Return the number of tables recalculated."
  (interactive)
  (let ((count 0))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward markdown-tblfm--formula-re nil t)
        (beginning-of-line)
        (when (and (not (bobp))
                   (save-excursion
                     (forward-line -1)
                     (looking-at markdown-tblfm--row-re)))
          (forward-line -1)
          (when (markdown-tblfm--recalculate-at-point)
            (setq count (1+ count))))
        ;; Skip past this table's formula lines.
        (pcase-let ((`(,_ ,end ,_) (markdown-tblfm--bounds-or-nil)))
          (goto-char (or end (line-beginning-position 2))))
        (while (and (not (eobp)) (looking-at markdown-tblfm--formula-re))
          (forward-line 1))))
    (when (called-interactively-p 'interactive)
      (message "Recalculated %d table%s" count (if (= count 1) "" "s")))
    count))

(defun markdown-tblfm--bounds-or-nil ()
  "Like `markdown-tblfm--bounds', but return nil instead of signaling."
  (condition-case nil (markdown-tblfm--bounds) (user-error nil)))

(provide 'markdown-tblfm)

;;; markdown-tblfm.el ends here
