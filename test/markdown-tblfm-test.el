;;; markdown-tblfm-test.el --- Tests for markdown-tblfm  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 otaqq

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run with: make test

;;; Code:

(require 'ert)
(require 'markdown-tblfm)

(defmacro markdown-tblfm-test--with (text &rest body)
  "Run BODY in a temp buffer holding TEXT, with point at `@'.
If TEXT has no `@', point is at the start of the buffer."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (goto-char (point-min))
     (when (search-forward "@@" nil t)
       (delete-char -2))
     ,@body))

(defun markdown-tblfm-test--recalc (text)
  "Recalculate the table in TEXT at point and return the buffer string."
  (markdown-tblfm-test--with text
    (markdown-tblfm-recalculate)
    (buffer-string)))

(ert-deftest markdown-tblfm-test-column-and-sum ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| item | hours | amount |
| ---- | ----- | ------ |
| a    | 3     |        |
| b    | 1.5   |        |
| tot  |       |        |
<!-- TBLFM: $3=($2*4000) -->
<!-- TBLFM: @>$2=sum(@I..@-1) -->
")
    "| item | hours | amount |
| ---- | ----- | ------ |
| a    | 3     | 12000  |
| b    | 1.5   | 6000   |
| tot  | 4.5   | 0      |
<!-- TBLFM: $3=($2*4000) -->
<!-- TBLFM: @>$2=sum(@I..@-1) -->
")))

(ert-deftest markdown-tblfm-test-chained-mean-and-format ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| x | y |
|---|---|
| 1 |   |
| 2 |   |
|   |   |
<!-- TBLFM: @>$1=mean(@I..@-1);%.2f :: @>$2=sum(@I..@-1) -->
")
    "| x    | y   |
| ---- | --- |
| 1    |     |
| 2    |     |
| 1.50 | 0   |
<!-- TBLFM: @>$1=mean(@I..@-1);%.2f :: @>$2=sum(@I..@-1) -->
")))

(ert-deftest markdown-tblfm-test-keeps-alignment ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| name | n |
| :--: | --: |
| a | 2 |
| b | 3 |
| sum |  |
<!-- TBLFM: @>$2=sum(@I..@-1) -->
")
    "| name |   n |
| :--: | --: |
|  a   |   2 |
|  b   |   3 |
| sum  |   5 |
<!-- TBLFM: @>$2=sum(@I..@-1) -->
")))

(ert-deftest markdown-tblfm-test-wide-characters ()
  ;; Full-width letters are two columns wide each.
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| ＩＤ | ＨＲ |
| --- | --- |
| ＡＡ | 3 |
| ＢＢ | 2 |
| ＴＬ | |
<!-- TBLFM: @>$2=sum(@I..@-1) -->
")
    "| ＩＤ | ＨＲ |
| ---- | ---- |
| ＡＡ | 3    |
| ＢＢ | 2    |
| ＴＬ | 5    |
<!-- TBLFM: @>$2=sum(@I..@-1) -->
")))

(ert-deftest markdown-tblfm-test-escaped-pipe ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| a \\| b | n |
| --- | --- |
| x | 1 |
| y |  |
<!-- TBLFM: @>$2=(@-1*2) -->
")
    "| a \\| b | n   |
| ------ | --- |
| x      | 1   |
| y      | 2   |
<!-- TBLFM: @>$2=(@-1*2) -->
")))

(ert-deftest markdown-tblfm-test-if ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| n | big |
| --- | --- |
| 1 | |
| 5 | |
<!-- TBLFM: $2=if($1 > 2, 1, 0) -->
")
    "| n   | big |
| --- | --- |
| 1   | 0   |
| 5   | 1   |
<!-- TBLFM: $2=if($1 > 2, 1, 0) -->
")))

(ert-deftest markdown-tblfm-test-point-on-formula-line ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| n |
| --- |
| 1 |
|   |
<!-- @@TBLFM: @>$1=(@-1+1) -->
")
    "| n   |
| --- |
| 1   |
| 2   |
<!-- TBLFM: @>$1=(@-1+1) -->
")))

(ert-deftest markdown-tblfm-test-keeps-point-row ()
  (markdown-tblfm-test--with "| n |
| --- |
| 1 |
| @@  |
<!-- TBLFM: @>$1=(@-1+1) -->
"
    (markdown-tblfm-recalculate)
    (should (= (line-number-at-pos) 4))))

(ert-deftest markdown-tblfm-test-no-trailing-newline ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "| n |
| --- |
| 1 |
|   |
<!-- TBLFM: @>$1=(@-1+1) -->")
    "| n   |
| --- |
| 1   |
| 2   |
<!-- TBLFM: @>$1=(@-1+1) -->")))

(ert-deftest markdown-tblfm-test-leaves-surrounding-text ()
  (should
   (equal
    (markdown-tblfm-test--recalc
     "Before.

@@| n |
| --- |
| 1 |
|   |
<!-- TBLFM: @>$1=(@-1+1) -->

After.
")
    "Before.

| n   |
| --- |
| 1   |
| 2   |
<!-- TBLFM: @>$1=(@-1+1) -->

After.
")))

(ert-deftest markdown-tblfm-test-no-formulas ()
  (markdown-tblfm-test--with "| n |\n| --- |\n| 1 |\n"
    (should-error (markdown-tblfm-recalculate) :type 'user-error)))

(ert-deftest markdown-tblfm-test-not-in-table ()
  (markdown-tblfm-test--with "Just text.\n"
    (should-error (markdown-tblfm-recalculate) :type 'user-error)))

(ert-deftest markdown-tblfm-test-unsupported-format ()
  (markdown-tblfm-test--with "| t |\n| --- |\n|   |\n<!-- TBLFM: $1=(@-1+1);dt -->\n"
    (should-error (markdown-tblfm-recalculate) :type 'user-error)))

(ert-deftest markdown-tblfm-test-buffer ()
  (markdown-tblfm-test--with "| a |
| --- |
| 1 |
|   |
<!-- TBLFM: @>$1=(@-1+1) -->

Text.

| b |
| --- |
| 10 |
|   |
<!-- TBLFM: @>$1=(@-1*2) -->

| c |
| --- |
| 1 |
"
    (should (= (markdown-tblfm-recalculate-buffer) 2))
    (should (equal (buffer-string)
                   "| a   |
| --- |
| 1   |
| 2   |
<!-- TBLFM: @>$1=(@-1+1) -->

Text.

| b   |
| --- |
| 10  |
| 20  |
<!-- TBLFM: @>$1=(@-1*2) -->

| c |
| --- |
| 1 |
"))))

(ert-deftest markdown-tblfm-test-translate ()
  (should (equal (markdown-tblfm--translate '("@>$2=sum(@I..@-1)"))
                 "@>$2=vsum(@I..@-1);N"))
  (should (equal (markdown-tblfm--translate '("$3=mean($1..$2);%.1f"))
                 "$3=vmean($1..$2);%.1fN"))
  (should (equal (markdown-tblfm--translate '("$1=(1+1) :: $2=(2+2)" "$3=vsum($1..$2)"))
                 "$1=(1+1);N :: $2=(2+2);N :: $3=vsum($1..$2);N")))

(provide 'markdown-tblfm-test)

;;; markdown-tblfm-test.el ends here
