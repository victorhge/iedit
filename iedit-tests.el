;;; iedit-tests.el --- iedit's automatic-tests

;; Copyright (C) 2010 - 2019, 2020 Victor Ren

;; Time-stamp: <2021-08-12 13:50:27 Victor Ren>
;; Author: Victor Ren <victorhge@gmail.com>
;; Version: 0.9.9.9
;; X-URL: https://github.com/victorhge/iedit
;;        https://www.emacswiki.org/emacs/Iedit
;; Compatibility: GNU Emacs: 22.x, 23.x, 24.x, 25.x

;; This file is not part of GNU Emacs, but it is distributed under
;; the same terms as GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file is part of iedit.

;;; Code:
(require 'ert)
(require 'iedit)
(require 'iedit-rect)
(require 'elp)

(ert-deftest iedit-batch-compile-test ()
  (with-temp-buffer
	(call-process-shell-command "emacs -L . -Q --batch -f batch-byte-compile *.el" nil (current-buffer))
    (should (string= (buffer-string) "Iedit default key binding is C-;
Iedit-rect default key binding is <C-x> <r> <RET>
"))
	(delete-file (byte-compile-dest-file "iedit-lib.el") nil)
	(delete-file (byte-compile-dest-file "iedit-rect.el") nil)
	(delete-file (byte-compile-dest-file "iedit-tests.el") nil)
	(delete-file (byte-compile-dest-file "iedit.el") nil)))

(defmacro with-iedit-test-buffer (buffer-name &rest body)
  (declare (indent 1) (debug t))
  `(progn
     (when (get-buffer ,buffer-name)
       (kill-buffer ,buffer-name))
     (with-current-buffer (get-buffer-create ,buffer-name)
       ;; Give the current temp buffer a window. Otherwise `recenter' will
       ;; trigger an error message.
       (progn (set-window-buffer nil ,buffer-name)
              ,@body))))

(defun marker-position-list (l)
  "convert list of markers to positions"
  (mapcar (lambda (m) (marker-position m)) l))

(defun goto-word (word &optional beginning)
  (goto-char (point-min))
  (search-forward word)
  (when beginning
    (goto-char (- (point) (length word)))))

(defun goto-word-beginning (word)
  (goto-word word t))

(defun with-iedit-test-fixture (input-buffer-string body)
  "iedit test fixture"
  (let ((old-transient-mark-mode transient-mark-mode)
        (old-iedit-transient-sensitive iedit-transient-mark-sensitive))
    (unwind-protect
        (progn
          (with-iedit-test-buffer "* iedit transient mark *"
            (transient-mark-mode t)
            (setq iedit-transient-mark-sensitive t)
			(setq iedit-case-sensitive t)
            (insert input-buffer-string)
            (goto-char 1)
            (iedit-mode)
            (funcall body))
          (with-iedit-test-buffer "* iedit NO transient mark *"
            (setq iedit-transient-mark-sensitive nil)
			(setq iedit-case-sensitive t)
            (transient-mark-mode -1)
            (insert input-buffer-string)
            (goto-char 1)
            (iedit-mode)
            (funcall body)))
      (transient-mark-mode old-transient-mark-mode)
      (setq iedit-transient-mark-sensitive old-transient-mark-mode))))

(ert-deftest iedit-mode-base-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (should (= 3 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (set-mark-command nil)
     (forward-line 2)
     (iedit-mode)
     (should (= 2 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (iedit-mode)
     (should (null iedit-occurrences-overlays)))))

(ert-deftest iedit-mode-with-region-test ()
  (with-iedit-test-fixture
"foobar
 foo
 foo
 bar
foo"
   (lambda ()
     (iedit-mode)
     (goto-char 1)
     (set-mark-command nil)
     (forward-char 3)
     (iedit-mode)
     (should (= 4 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (should (eq 'selection iedit-occurrence-type-local))
     (goto-char 1)
     (set-mark-command nil)
     (forward-line 3)
     (iedit-mode 4)
     (should (= 1 (length iedit-occurrences-overlays))))))

(ert-deftest iedit-mode-with-tag-pair-test ()
  (with-iedit-test-fixture
   "<div> foo </div>
<div> bar </div>
<div> foobar </div>
div
foobar
 foo
 bar
foo"
   (lambda ()
     (iedit-mode)
     (goto-char 2)
     (iedit-mode)
     (should (= 2 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "div"))
     ;; (should (eq 'tag iedit-occurrence-type-local))
     (iedit-mode)
     (sgml-electric-tag-pair-mode t)
     (iedit-mode)
     (should (= 3 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "<div>"))
     (should (eq 'symbol iedit-occurrence-type-local))
     (sgml-electric-tag-pair-mode))))

(ert-deftest iedit-move-conjointed-overlays-test ()
  (with-iedit-test-fixture
"foobar
 foofoofoo
 foofoo
 foo"
   (lambda ()
     (iedit-mode)
     (goto-char 1)
     (set-mark-command nil)
     (forward-char 3)
     (iedit-mode)
     (should (= 7 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (should (eq 'selection iedit-occurrence-type-local))
     (goto-char 1)
	 (insert "123")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"123foobar
 123foo123foo123foo
 123foo123foo
 123foo"))
     (forward-char 3)
     (insert "456")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"123foo456bar
 123foo456123foo456123foo456
 123foo456123foo456
 123foo456")))))

(ert-deftest iedit-overlay-at-end-of-buffer ()
  (with-iedit-test-fixture
   "foo
foo"
   (lambda ()
     (iedit-mode)
     (goto-char (point-min))
     (goto-char (point-at-eol))
     (iedit-mode)
     (delete-region (point) (1- (point)))
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
                      "fo
fo"))
     (insert "b")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
                      "fob
fob")))))

(ert-deftest iedit-mode-start-from-isearch-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (should (= 3 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (iedit-mode)
     (forward-line 2)
     (isearch-mode t)
     (isearch-process-search-char ?f)
     (isearch-process-search-char ?o)
     (isearch-process-search-char ?o)
     (call-interactively 'iedit-mode-from-isearch)
     (should (string= iedit-initial-string-local "foo"))
     (should (= 4 (length iedit-occurrences-overlays)))
     (iedit-mode)
     (should (null iedit-occurrences-overlays)))))

(ert-deftest iedit-mode-start-from-isearch-regexp-test ()
  (with-iedit-test-fixture
"foo
  fobar
  foobar
  fooobar
   barfoo
   foo"
   (lambda ()
     (iedit-mode)
     (call-interactively 'isearch-forward-regexp)
     (isearch-process-search-char ?f)
     (isearch-process-search-char ?o)
     (isearch-process-search-char ?*)
     (isearch-process-search-char ?b)
     (call-interactively 'iedit-mode-from-isearch)
     (should (null iedit-occurrences-overlays))
     (should (null iedit-mode)) ;; (should (string= (current-message) "Matches are not the same length."))
     (goto-char (point-min))
     (call-interactively 'isearch-forward-regexp)
     (isearch-process-search-char ?f)
     (isearch-process-search-char ?o)
     (isearch-process-search-char ?.)
     (isearch-process-search-char ?b)
     (call-interactively 'iedit-mode-from-isearch)
     (should (= 1 (length iedit-occurrences-overlays)))
    )))

(ert-deftest iedit-mode-last-local-occurrence-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (should (= 3 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (iedit-mode)
     (goto-char 15)
     (iedit-mode 4) ; last local
     (should (string= iedit-initial-string-local "foo"))
     (should (= 3 (length iedit-occurrences-overlays))))))

(ert-deftest iedit-mode-last-global-occurrence-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (should (= 3 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (iedit-mode)
     (with-temp-buffer
       (set-window-buffer nil (current-buffer))
       (insert "bar foo foo")
       (goto-char 1)
       (iedit-mode 16)
     (should (string= iedit-initial-string-local "foo"))
     (should (= 2 (length iedit-occurrences-overlays)))))))

(ert-deftest iedit-execute-last-modification-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (should (= 3 (length iedit-occurrences-overlays)))
     (should (string= iedit-initial-string-local "foo"))
     (iedit-mode)
     (with-temp-buffer
       (insert "bar foo foo")
       (should-error (iedit-execute-last-modification))))))

(ert-deftest iedit-movement-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo "
   (lambda ()
     (iedit-goto-last-occurrence)
     (should (= (point) 24))
     (should (= iedit-occurrence-index 3))
     (iedit-goto-first-occurrence)
     (should (= (point) 1))
     (should (= iedit-occurrence-index 1))
     (iedit-next-occurrence 1)
     (should (= (point) 7))
     (should (= iedit-occurrence-index 2))
     (iedit-next-occurrence 1)
     (should (= (point) 24))
     (should (= iedit-occurrence-index 3))
     (iedit-next-occurrence 1)
     (should (= (point) 24)) ;; (should (string= (current-message) "This is the last occurrence."))
     (should (= iedit-occurrence-index 3))
     (iedit-next-occurrence 1)
     (should (= (point) 1)) ;; (should (string= (current-message) "Located the first occurrence."))
     (should (= iedit-occurrence-index 1))
     (iedit-next-occurrence 1)
     (should (= (point) 7))
     (should (= iedit-occurrence-index 2))
     (goto-char (point-max))
     (iedit-prev-occurrence 1)
     (should (= (point) 24))
     (should (= iedit-occurrence-index 3))
     (iedit-prev-occurrence 1)
     (should (= (point) 7))
     (iedit-prev-occurrence 1)
     (should (= (point) 1))
     (iedit-prev-occurrence 1)
     (should (= (point) 1)) ;; (should (string= (current-message) "This is the first occurrence."))
     (iedit-prev-occurrence 1)
     (should (= (point) 24)) ;; (should (string= (current-message) "Located the last occurrence."))
     )))

(ert-deftest iedit-occurrence-update-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (insert "1")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"1foo
  1foo
   barfoo
   1foo"))
     (backward-delete-char 1)
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"foo
  foo
   barfoo
   foo"))
     (capitalize-word 1)
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"Foo
  Foo
   barfoo
   Foo"))
     ;; test insert from empty
     (iedit-delete-occurrences)
     (insert "1")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"1
  1
   barfoo
   1")))))

(ert-deftest iedit-occurrence-update-with-read-only-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (iedit-mode)
     (put-text-property 1 2 'read-only t)
     (iedit-mode)
     (goto-char 2)
     (should-error (insert "1"))
     (should (string= (buffer-string)
"foo
  foo
   barfoo
   foo"))
     (goto-char 7)
     (insert "1")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"foo
  1foo
   barfoo
   1foo"))
     )))

(ert-deftest iedit-aborting-test ()
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (kill-region (point) (+ 4 (point)))
     (should (string= (buffer-string)
"  foo
   barfoo
   foo")))))

(ert-deftest iedit-toggle-case-sensitive-test ()
  (with-iedit-test-fixture
"foo
  Foo
   barfoo
   foo"
   (lambda ()
     (should (= 2 (length iedit-occurrences-overlays)))
     (iedit-toggle-case-sensitive)
     (should (= 3 (length iedit-occurrences-overlays)))
     (iedit-next-occurrence 1)
     (iedit-toggle-case-sensitive)
     (should (= 1 (length iedit-occurrences-overlays))))))

(ert-deftest iedit-toggle-search-invisible-test ()
  (with-iedit-test-fixture
"foo
* foo
** foo"
   (lambda ()
     (iedit-mode) ; turn off iedit-mode
	 (outline-mode)
	 (forward-line 1)
	 (call-interactively 'outline-hide-subtree)
	 (setq iedit-search-invisible t)
	 (goto-char 1)
	 (iedit-mode)
     (should (= 3 (length iedit-occurrences-overlays)))
	 (should (= 0 iedit-lib-skip-invisible-count))
     (iedit-toggle-search-invisible)
     (should (= 2 (length iedit-occurrences-overlays)))
	 (should (null iedit-search-invisible))
	 (should (= 1 iedit-lib-skip-invisible-count))
	 (iedit-toggle-search-invisible)
	 (should (= 3 (length iedit-occurrences-overlays)))
	 (should (= 0 iedit-lib-skip-invisible-count))
	 (should (eq 'open iedit-search-invisible)))))

(ert-deftest iedit-case-preserve-test ()
  (with-iedit-test-fixture
"foo
  Foo
   barFoo
   FOO"
(lambda ()
  (iedit-mode)
  (goto-char 1)
  (set-mark-command nil)
  (forward-char 3)
  (let ((iedit-case-sensitive nil)
		(case-replace t))
	(iedit-mode)
	(goto-char 1)
	(insert "bar")
	(run-hooks 'post-command-hook)
	(should (string= (buffer-string)
"barfoo
  BarFoo
   barBarFoo
   BARFOO"))))))

(ert-deftest iedit-apply-on-occurrences-test ()
  "Test functions deal with the whole occurrences"
  (with-iedit-test-fixture
"foo
  foo
   barfoo
   foo"
   (lambda ()
     (iedit-upcase-occurrences)
     (should (string= (buffer-string)
"FOO
  FOO
   barfoo
   FOO"))
     (iedit-downcase-occurrences)
     (should (string= (buffer-string)
"foo
  foo
   barfoo
   foo"))
     (iedit-replace-occurrences "bar")
     (should (string= (buffer-string)
"bar
  bar
   barfoo
   bar"))
     (iedit-number-occurrences 1 "%d ")
     (should (string= (buffer-string)
"1 bar
  2 bar
   barfoo
   3 bar")))))

(ert-deftest iedit-blank-occurrences-test ()
  "Test functions deal with the whole occurrences"
  (with-iedit-test-fixture
"foo foo barfoo foo"
   (lambda ()
     (iedit-blank-occurrences)
     (should (string= (buffer-string) "        barfoo    ")))))

(ert-deftest iedit-blank-occurrences-rectangle-test ()
  "Test functions deal with the whole occurrences"
  (with-iedit-test-fixture
"foo
 foo barfoo foo"
   (lambda ()
     (iedit-mode) ; turn off iedit
     (goto-char 2)
     (set-mark-command nil)
     (goto-char 7)
     (call-interactively 'iedit-rectangle-mode)
     (iedit-blank-occurrences)
     (should (string= (buffer-string) "f o
  oo barfoo foo")))))

(ert-deftest iedit-delete-occurrences-test ()
  "Test functions deal with the whole occurrences"
  (with-iedit-test-fixture
"foo foo barfoo foo"
   (lambda ()
     (iedit-delete-occurrences)
     (should (string= (buffer-string) "  barfoo ")))))

(ert-deftest iedit-toggle-buffering-test ()
  (with-iedit-test-fixture
"foo
 foo
  barfoo
    foo"
   (lambda ()
     (iedit-toggle-buffering)
     (insert "bar")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"barfoo
 foo
  barfoo
    foo"))
     (iedit-toggle-buffering)
     (should (string= (buffer-string)
"barfoo
 barfoo
  barfoo
    barfoo"))
     (should (= (point) 4))
     (iedit-toggle-buffering)
     (backward-delete-char 3)
     (should (string= (buffer-string)
"foo
 barfoo
  barfoo
    barfoo"))
     (goto-char 15) ;not in an occurrence
     (should (null (iedit-find-current-occurrence-overlay)))
     (iedit-toggle-buffering)
     (should (string= (buffer-string)
"foo
 barfoo
  barfoo
    barfoo")))))

(ert-deftest iedit-buffering-undo-test ()
  (with-iedit-test-fixture
"foo
 foo
  barfoo
    foo"
   (lambda ()
	 (iedit-mode)						;turnoff
     (setq iedit-auto-buffering t)
	 (push nil buffer-undo-list)
	 (call-interactively 'iedit-mode)
     (insert "bar")
	 (run-hooks 'post-command-hook)
     (should (string= (buffer-string)
"barfoo
 foo
  barfoo
    foo"))
     (call-interactively 'iedit-mode)
     (should (string= (buffer-string)
"barfoo
 barfoo
  barfoo
    barfoo"))
     (should (= (point) 4))
	 (push nil buffer-undo-list)
	 (undo 1)
	 (should (= (point) 1))
     (should (string= (buffer-string)
"foo
 foo
  barfoo
    foo"))
     )))

(ert-deftest iedit-rectangle-start-test ()
  (with-iedit-test-fixture
   "foo
 foo
  barfoo
    foo"
   (lambda ()
     (iedit-mode)
     (set-mark-command nil)
     (forward-char 3)
     (forward-line 3)
     (call-interactively 'iedit-rectangle-mode)
     (should (equal (marker-position-list iedit-rectangle) '(1 19)))
     (call-interactively 'iedit-rectangle-mode)
     (goto-char (point-min))
     (set-mark-command nil)
     (goto-char (point-max))
     (call-interactively 'iedit-rectangle-mode)
     (should (equal (marker-position-list iedit-rectangle) '(1 33))))))

(ert-deftest iedit-kill-rectangle-error-test ()
  (with-iedit-test-fixture
   "foo
 foo
  barfoo
    foo"
   (lambda ()
     (iedit-mode)
     (set-mark-command nil)
     (goto-char 22)
     (call-interactively 'iedit-rectangle-mode)
     (should (iedit-same-column))
     (should (equal (marker-position-list iedit-rectangle) '(1 22)))
     (iedit-prev-occurrence 1)
     (delete-char -1)
     (should (not (iedit-same-column)))
     (should-error (iedit-kill-rectangle)))))

(ert-deftest iedit-expand-to-occurrence-test ()
  (with-iedit-test-fixture
   "a a
a a a
a a a"
   (lambda()
     (goto-char 5)
     (iedit-restrict-current-line)
     (call-interactively 'iedit-expand-down-to-occurrence)
     (should (equal (length iedit-occurrences-overlays) 4))
     (should (= (point) 11))
     (call-interactively 'iedit-expand-up-to-occurrence)
     (should (equal (length iedit-occurrences-overlays) 5))
     (should (= (point) 3))
     (call-interactively 'iedit-expand-up-to-occurrence)
     (call-interactively 'iedit-expand-up-to-occurrence)
     (should (equal (length iedit-occurrences-overlays) 6))
     (should (= (point) 1))
     (call-interactively 'iedit-expand-down-to-occurrence)
     (call-interactively 'iedit-expand-down-to-occurrence)
     (call-interactively 'iedit-expand-down-to-occurrence)
     (should (equal (length iedit-occurrences-overlays) 8))
     (should (= (point) 15)))))

(ert-deftest iedit-kill-rectangle-test ()
  (with-iedit-test-fixture
"foo
 foo
  barfoo
    foo"
   (lambda ()
   (iedit-mode)
   (set-mark-command nil)
   (goto-char 22)
   (call-interactively 'iedit-rectangle-mode)
   (should (iedit-same-column))
   (should (equal (marker-position-list iedit-rectangle) '(1 22)))
   (iedit-kill-rectangle)
   (should (string= (buffer-string)
"
o
arfoo
 foo"))
 (should (equal killed-rectangle '("foo" " fo" "  b" "   "))))))

(ert-deftest iedit-kill-rectangle-fill-extra-spaces ()
  "lines within rectangle shorter than rectangle right column
  should have spaces filled in."
  (with-iedit-test-fixture
   "foo
 foo
  barfoo
    foo"
   (lambda ()
     (iedit-mode)
     (setq indent-tabs-mode nil)
     (set-mark-command nil)
     (goto-word "barfoo")
     (call-interactively 'iedit-rectangle-mode)
     (should (iedit-same-column))
     (should (equal '(1 27) (marker-position-list iedit-rectangle))))))

(ert-deftest iedit-restrict-defun-test ()
  (with-iedit-test-fixture
"a
(defun foo (foo bar foo)
\"foo bar foobar\" nil)
 (defun bar (bar foo bar)
  \"bar foo barfoo\" nil)"
   (lambda ()
      (iedit-mode)
      (emacs-lisp-mode)
      (goto-char 5)
      (iedit-mode)
      (setq iedit-auto-narrow t)
      (iedit-restrict-function)
      (should (= 1 (length iedit-occurrences-overlays)))
      (should (equal (buffer-narrowed-p) iedit-is-narrowed))
      (iedit-mode)
      (goto-char 13)
      (setq iedit-auto-narrow nil)
      (call-interactively 'iedit-mode-toggle-on-function)
      (should (= 4 (length iedit-occurrences-overlays)))
      (iedit-mode)
      (iedit-mode)
      (mark-defun)
      (iedit-mode)
      (should (= 4 (length iedit-occurrences-overlays))))))

(ert-deftest iedit-transient-sensitive-test ()
  (with-iedit-test-fixture
"a
(defun foo (foo bar foo)
\"foo bar foobar\" nil)
 (defun bar (bar foo bar)
  \"bar foo barfoo\" nil)"
   (lambda ()
      (iedit-mode)
      (emacs-lisp-mode)
      (setq iedit-transient-mark-sensitive t)
      (transient-mark-mode -1)
      (goto-char 5)
      (iedit-mode)
      (iedit-restrict-function)
      (should (= 1 (length iedit-occurrences-overlays)))
      (iedit-mode)
      (goto-char 13)
      (iedit-mode 0)
      (should (= 4 (length iedit-occurrences-overlays)))
      (iedit-mode) ;;turn off iedit mode
      (iedit-mode)
      (mark-defun)
      (iedit-mode)
      (should (= 0 (length iedit-occurrences-overlays))))))

(defvar iedit-printable-test-lists
  '(("" "")
    ("abc" "abc")
    ("abc
bcd" "abc...")
    ("abc\n34" "abc...")
    ("12345678901234567890123456789012345678901234567890abc" "12345678901234567890123456789012345678901234567890...")
    ("12345678901234567890123456789012345678901234567890abc
abcd" "12345678901234567890123456789012345678901234567890...")))

(ert-deftest iedit-printable-test ()
  (dolist (test iedit-printable-test-lists)
    (should (string= (iedit-printable (car test)) (cadr test)))))

(ert-deftest iedit-hide-context-lines-test ()
  "Test function iedit-hide-context-lines."
  (with-iedit-test-fixture
   "foo
foo
a
  foo bar
a
a
bar foo
a
a
a
bar foo
a
a
a
a
 foo bar
a
a
a
a
a
foo"
   (lambda ()
     (should (equal (iedit-hide-context-lines 0) '((64 73) (47 54) (33 38) (21 24) (9 10))))
     (iedit-show-all)
     (should (equal (iedit-hide-context-lines 1) '((66 71) (49 52) (35 36))))
     (iedit-show-all)
     (should (equal (iedit-hide-context-lines 2) '((68 69)) ))
     (iedit-show-all)
     (should (equal (iedit-hide-context-lines 3) nil)))))

(ert-deftest iedit-hide-occurrence-lines-test ()
  "Test function iedit-hide-occurrence-lines."
  (with-iedit-test-fixture
   "foo
foo
a
  foo bar
a
a
bar foo
a
a
a
bar foo
a
a
a
a
 foo bar
a
a
a
a
a
foo"
   (lambda ()
     (should (equal (iedit-hide-occurrence-lines) '((74 77) (55 63) (39 46) (25 32) (11 20) (1 8)))))))

;; todo add a auto performance test
(setq elp-function-list '(;; insert-and-inherit
                       ;; delete-region
                       ;; goto-char
                       ;; iedit-occurrence-update
                       ;; buffer-substring-no-properties
                       ;; string=
                       re-search-forward
                       ;; replace-match
                       text-property-not-all
                       iedit-make-occurrence-overlay
                       iedit-make-occurrences-overlays
                       match-beginning
                       match-end
                       push
                       ))


;;; iedit-tests.el ends here
