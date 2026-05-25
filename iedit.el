;;; iedit.el --- Edit multiple regions in the same way simultaneously. -*-lexical-binding: t-*-

;; Copyright (C) 2010 - 2019, 2020, 2021 Victor Ren

;; Author: Victor Ren <victorhge@gmail.com>
;; Keywords: occurrence region simultaneous refactoring
;; Version: 0.9.9.9.9
;; X-URL: https://github.com/victorhge/iedit
;;        https://www.emacswiki.org/emacs/Iedit
;; Compatibility: GNU Emacs: 24.x, 25.x

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

;; This package includes Emacs minor modes (iedit-mode and iedit-rectangle-mode)
;; based on a API library (iedit-lib) and allows you to alter one occurrence of
;; some text in a buffer (possibly narrowed) or region, and simultaneously have
;; other occurrences changed in the same way, with visual feedback as you type.

;; `iedit-mode' is a great alternative of build-in replace commands:

;;  - A more intuitive way to alter all the occurrences at once
;;  - Visual feedback
;;  - Less keystrokes in most cases

;; Normal work flow of Iedit mode is like:

;;  - Move point to a target by `isearch' or other moving commands
;;
;;  - Press C-;(The default key binding) to enable Iedit mode.  The thing under
;;    the point is recognized as an occurrence, and all the occurrences in the
;;    buffer are highlighted

;;  - Edit one of the occurrences
;;    The change is applied to other occurrences simultaneously.

;;  - Finish - by pressing C-; again

;; Many other work flows to highlight occurrences are possible, for example,
;; rectangle selection, incremental selection and markup tag pair selection.

;; You can also use Iedit mode as a quick way to temporarily show only the
;; buffer lines that match the current text being edited.  This gives you the
;; effect of a temporary `keep-lines' or `occur'.  To get this effect, hit C-'
;; when in Iedit mode - it toggles hiding non-matching lines.

;; `iedit-mode' is optimized for renaming refactoring in many ways:

;;  - The symbol under point is selected as occurrence by default and only complete
;;    symbols are matched

;;  - With digit prefix argument 0, only occurrences in current function are matched

;;  - Last renaming refactoring is remembered and can be applied to other buffers
;;    later

;;  - Once in iedit mode, you can select a region and hit C-; again to restrict
;;    the search area to the region

;;  - Restricting the search area to just the current line can be done by
;;    pressing M-I.

;;  - Restricting the search area to the lines near the current line can
;;    be done by pressing M-{ and M-}.  These will expand the search
;;    region one line at a time from the top and bottom.  Add a prefix
;;    argument to go the opposite direction.

;; Iedit-rectangle-mode provides rectangle support with *visible rectangle*
;; highlighting, which is similar with cua mode rectangle support.  But it's
;; lighter weight and uses iedit mechanisms.

;; There are also some other facilities you may never think about.  Refer to the
;; document of function `iedit-mode' (C-h f iedit-mode RET) for more details.

;;; Contributors
;; Adam Lindberg <eproxus@gmail.com> added a case sensitivity option that can be toggled.

;; Tassilo Horn <tassilo@member.fsf.org> added an option to match only complete
;; words, not inside words

;; Le Wang <l26wang@gmail.com> proposed to match only complete symbols,  not
;; inside symbols, contributed rectangle support

;; Pierre Rouleau <prouleau001@gmail.com> added lexical-binding, fixed warnings
;; and improved docstrings

;;; Code:

(eval-when-compile
  (require 'cl-lib)
  (require 'sgml-mode))
(require 'iedit-lib)

(defcustom iedit-toggle-key-default (kbd "C-;")
  "If non-nil, key is inserted into key maps.
The key maps are: `global-map', `isearch-mode-map', `esc-map' and `help-map'."
  :type 'string
  :group 'iedit)

(defvar iedit-mode-hook nil
  "Function(s) to call after starting up an iedit.")

(defvar iedit-mode-end-hook nil
  "Function(s) to call after terminating an iedit.")

(defvar-local iedit-mode nil) ;; Name of the minor mode

(defcustom iedit-auto-narrow nil
  "If non-nil, narrow buffer if `iedit-mode' is enabled on current defun.
The narrowing is temporary."
  :type 'boolean
  :group 'iedit)

(defcustom iedit-auto-save-occurrence-in-kill-ring t
  "If non-nil, save occurrence in the kill ring when exiting from iedit mode."
  :type 'boolean
  :group 'iedit)

(defvar-local iedit-is-narrowed nil
  "If non-nil the current buffer is narrowed by iedit temporarily.")

(defvar-local iedit-use-symbol-boundaries t
  "If non-nil, matches have to start and end at symbol boundaries.
Otherwise, matches starts and end at word boundaries.")

(defvar iedit-last-occurrence-global nil
  "The occurrence when Iedit mode is turned off last time.
It is a cons cell (TYPE . STRING) giving the occurrence type and
string. `type' might be any of (symbol word email url markup-tag regexp
selection other)")

(defvar iedit-last-initial-occurrence-global nil
  "The last initial occurrence.")

(defvar-local iedit-initial-occurrence-local nil
  "The initial occurrence to start Iedit mode in current buffer.")

(defvar-local iedit-initial-region nil
  "The initial region where Iedit mode is started from in current buffer.")

(defvar iedit-num-lines-to-expand-up 0
  "Number of lines up from point to include in the replacement region.")

(defvar iedit-num-lines-to-expand-down 0
  "Number of lines down from point to include in the replacement region.")

(defvar-local iedit-default-occurrence-local nil
  "The function which returns a list (type string) as occurrence candidate.
It is called in `iedit-default-occurrence'.  This buffer local
variable can be configured in some modes.  An example of how to
use this variable:
\(add-hook \\='perl-mode-hook
          \\='(lambda ()
             (setq iedit-default-occurrence-local
                   \\='(lambda ()
                      (let* ((bound (bounds-of-thing-at-point \\='symbol))
                             (prefix-char (char-after (1- (car bound)))))
                        (list \\='regexp
                           (if (memq prefix-char \\='(?$ ?% ?@ ?*))
                              (concat (regexp-quote
                                       (buffer-substring-no-properties
                                        (1- (car bound)) (cdr bound)))
                                       \"\\\\_>\")
                          (buffer-substring-no-properties (car bound)
                                                          (cdr bound)))))))))
\\='$%@*\\=' will be included in the occurrences in perl mode.")

(defcustom iedit-mode-line
  `(" Iedit:" (:eval (format ,(propertize "%d/%d" 'face 'font-lock-warning-face)
                             iedit-occurrence-index (iedit-counter))))
  "Mode-line format for Iedit.
This should be set before Iedit is loaded."
  :type 'string
  :risky t
  :group 'iedit)

(or (assq 'iedit-mode minor-mode-alist)
    (nconc minor-mode-alist
           (list `(iedit-mode ,iedit-mode-line))))

;;; Define iedit help map.
(eval-when-compile (require 'help-macro))

(defvar iedit-help-map
  (let ((map (make-sparse-keymap)))
    (define-key map (vector (event-convert-list `(,help-char))) 'iedit-help-for-help)
    (define-key map [help] 'iedit-help-for-help)
    (define-key map [f1] 'iedit-help-for-help)
    (define-key map "?" 'iedit-help-for-help)
    (define-key map "b" 'iedit-describe-bindings)
    (define-key map "k" 'iedit-describe-key)
    (define-key map "m" 'iedit-describe-mode)
    (define-key map "q" 'help-quit)
    map)
  "Keymap for characters following the Help key for Iedit mode.")

(make-help-screen
  iedit-help-for-help-internal
  (purecopy "Type a help option: [bkm] or ?")
  "You have typed %THIS-KEY%, the help character.  Type a Help option:
\(Type \\<help-map>\\[help-quit] to exit the Help command.)

b           Display all Iedit key bindings.
k KEYS      Display full documentation of Iedit key sequence.
m           Display documentation of Iedit mode.

You can't type here other help keys available in the global help map,
but outside of this help window when you type them in Iedit mode,
they exit Iedit mode before displaying global help."
  iedit-help-map)

(defun iedit-help-for-help ()
  "Display Iedit help menu."
  (interactive)
  (let (same-window-buffer-names same-window-regexps)
    (iedit-help-for-help-internal)))

(defun iedit-describe-bindings ()
  "Show a list of all keys defined in Iedit mode, and their definitions.
This is like `describe-bindings', but displays only Iedit keys."
  (interactive)
  (let (same-window-buffer-names
        same-window-regexps
        (keymap (substitute-command-keys "\\{iedit-mode-keymap}\\{iedit-mode-occurrence-keymap}")))
    (with-help-window "*Help*"
      (with-current-buffer standard-output
        (princ "Iedit Mode Bindings: ")
        (princ keymap)))))

(defun iedit-describe-key ()
  "Display documentation of the function invoked by Iedit mode key."
  (interactive)
  (let (same-window-buffer-names same-window-regexps)
    (call-interactively 'describe-key)))

(defun iedit-describe-mode ()
  "Display documentation of Iedit mode."
  (interactive)
  (let (same-window-buffer-names same-window-regexps)
    (describe-function 'iedit-mode)))

(defun iedit-counter ()
  "Return the number of active occurrences."
  (length iedit-occurrences-overlays))

;;; Default key bindings:
(defun iedit-update-key-bindings (key)
  "Update default KEY bindings."
  (when (and key (not (eq key
                          (car (where-is-internal 'iedit-mode)))))
    (let ((key-def (lookup-key (current-global-map) key)))
      (if key-def
          (display-warning 'iedit (format "Iedit default key %S is occupied by %s."
                                          (key-description key)
                                          key-def)
                           :warning)
        (define-key global-map key 'iedit-mode)
        (define-key isearch-mode-map key 'iedit-mode-from-isearch)
        (define-key esc-map key 'iedit-execute-last-modification)
        (define-key help-map key 'iedit-mode-toggle-on-function)))))

(when (and iedit-toggle-key-default (null (where-is-internal 'iedit-mode)))
  (iedit-update-key-bindings iedit-toggle-key-default))

;; Avoid to restore Iedit mode when restoring desktop
(add-to-list 'desktop-minor-mode-handlers
             '(iedit-mode . ignore))

;;; Define iedit help map.
(eval-when-compile (require 'help-macro))

(defvar iedit-mode-occurrence-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map iedit-occurrence-keymap-default)
    (define-key map (kbd "M-H") 'iedit-restrict-function)
    (define-key map (kbd "M-I") 'iedit-restrict-current-line)
    (define-key map (kbd "M-{") 'iedit-expand-up-a-line)
    (define-key map (kbd "M-}") 'iedit-expand-down-a-line)
    (define-key map (kbd "M-p") 'iedit-expand-up-to-occurrence)
    (define-key map (kbd "M-n") 'iedit-expand-down-to-occurrence)
    (define-key map (kbd "M-G") 'iedit-apply-last-modification)
    (define-key map (kbd "M-C") 'iedit-toggle-case-sensitive)
    (define-key map (kbd "M-S") 'iedit-toggle-search-invisible)
    map)
  "Keymap used within overlays in Iedit mode.")

(defvar iedit-mode-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map iedit-lib-keymap)
    (define-key map (vector (event-convert-list `(,help-char))) iedit-help-map)
    (define-key map [help] iedit-help-map)
    (define-key map [f1] iedit-help-map)
    (define-key map (kbd "M-;") 'iedit-toggle-selection)
    (define-key map (kbd "M-\"") 'iedit-toggle-apply-isearch-filter)
    map)
  "Keymap used while Iedit mode is enabled.")

;;; Define Iedit mode map
(or (assq 'iedit-mode minor-mode-map-alist)
    (setq minor-mode-map-alist
          (cons (cons 'iedit-mode iedit-mode-keymap) minor-mode-map-alist)))

;;;###autoload
(defun iedit-mode (&optional arg)
  "Toggle Iedit mode.
This command behaves differently, depending on the mark, point,
prefix argument and variable `iedit-transient-mark-sensitive'.

If Iedit mode is off, turn Iedit mode on.

When Iedit mode is turned on, all the occurrences of the current
region in the buffer (possibly narrowed) or a region are
highlighted.  If one occurrence is modified, the change are
propagated to all other occurrences simultaneously.

If region is not active, `iedit-default-occurrence' is called to
get an occurrence candidate, according to the thing at point.  It
might be url, email address, markup tag or current symbol(or
word).

In the above two situations, with digit prefix argument 0, only
occurrences in current function are matched.  This is good for
renaming refactoring in programming.

You can also switch to Iedit mode from isearch mode directly.  The
current search string is used as occurrence.  All occurrences of
the current search string are highlighted.

With an universal prefix argument ARG, the occurrence when Iedit mode is
turned off last time (might be in other buffer) is used as occurrence.
If region active, Iedit mode is limited within the current region.

With digital prefix argument 1, Iedit mode is limited on the
current symbol or the active region, which means just one
instance is highlighted.  This behavior serves as a start point
of incremental selection work flow.

If Iedit mode is on and region is active, Iedit mode is
restricted in the region, e.g. the occurrences outside of the
region is excluded.

If Iedit mode is on and region is active, with an universal
prefix argument, Iedit mode is restricted outside of the region,
e.g. the occurrences in the region is excluded.

Turn off Iedit mode in other situations.

Commands:
\\{iedit-mode-keymap}
Keymap used within overlays:
\\{iedit-mode-occurrence-keymap}"
  (declare (interactive-only
            "use `call-interactively' if you have to."))
  (interactive "P")
  (if iedit-mode
      (iedit-mode-on-action arg)
    (iedit-barf-if-lib-active)
    (let (occurrence beg end)
      ;; Get the occurrence (TYPE . STRING)
      (cond ((and arg
                  (= 4 (prefix-numeric-value arg))
                  iedit-last-initial-occurrence-global)
             (setq occurrence iedit-last-initial-occurrence-global))
            ((iedit-region-active)
             (setq occurrence (cons 'selection  (buffer-substring-no-properties
                                (mark) (point)))))
            (t (setq occurrence (iedit-default-occurrence))
               (unless occurrence
                 (error "No candidate of the occurrence, cannot enable Iedit mode"))))
      ;; Get the scope
      (cl-multiple-value-setq (beg end) (iedit--get-scope arg))
      (setq mark-active nil)
      (run-hooks 'deactivate-mark-hook)
      (iedit-start occurrence beg end)
      (unless iedit-occurrences-overlays
        ;; (message "No matches found for %s" (iedit-regexp-quote occurrence))
        (iedit-done)))))

(unless (boundp 'isearch-regexp-function)
  (defvaralias 'isearch-regexp-function 'isearch-word))

;;;###autoload
(defun iedit-mode-from-isearch (&optional arg)
  "Start Iedit mode using last search string as the regexp.
With optional ARG, perform a symbol search."
  (interactive "P")
  (or isearch-success
      (error "No match" ))
  (let ((regexp (cond
                 ((functionp isearch-regexp-function)
                  (funcall isearch-regexp-function isearch-string))
                 (isearch-regexp-function (word-search-regexp isearch-string))
                 (isearch-regexp isearch-string)
                 (t (regexp-quote isearch-string))))
        (iedit-case-sensitive (not isearch-case-fold-search))
        result
        beg
        end)
    (isearch-exit)
    (cl-multiple-value-setq (beg end) (iedit--get-scope arg))
    (setq mark-active nil)
    (run-hooks 'deactivate-mark-hook)
    (when iedit-mode
      (iedit-lib-cleanup))
    (setq result
          (catch 'not-same-length
            (iedit-start (cons 'regexp regexp) beg end)))
    (cond ((not iedit-occurrences-overlays)
           (message "No matches found for %s" regexp)
           (iedit-done))
          ((equal result 'not-same-length)
           (message "Matches are not the same length.")
           (iedit-done)))))

(defun iedit--get-scope (arg)
  "Return a region according to the prefix argument ARG."
  (let ((beg (if (eq major-mode 'occur-edit-mode) ; skip the first occurrence
                 (next-single-char-property-change 1 'read-only)
               (point-min)))
        (end (point-max)))
    (when arg
      (cond
       ((= 0 (prefix-numeric-value arg))
        (save-excursion
          ;; Since Emacs 26.1, `mark-defun' marks the next defun if the
          ;; mark is active.
          (deactivate-mark t)
          (mark-defun)
          (setq beg (region-beginning))
          (setq end (region-end)))
        (when (and iedit-auto-narrow (not (buffer-narrowed-p)))
          (narrow-to-region beg end)
          (setq iedit-is-narrowed t)))
       ((and (= 1 (prefix-numeric-value arg))
             (not (iedit-region-active)))
        (let ((region (bounds-of-thing-at-point 'symbol)))
          (setq beg (car region))
          (setq end (cdr region))))
       ((iedit-region-active)
        (setq beg (region-beginning))
        (setq end (region-end)))))
    (list beg end)))

(defun iedit-start (occurrence beg end)
  "Start Iedit mode for the OCCURRENCE-REGEXP in the current buffer.
BEG and END identify the start and end of the initial region."
  (setq iedit-initial-region (list beg end))
  (setq iedit-initial-occurrence-local occurrence)
  (let ((counter 0)
        (occurrence-regexp (iedit-regexp-quote occurrence)))
    (if (eq (car occurrence) 'markup-tag)
        (progn
          (setq iedit-occurrence-keymap iedit-occurrence-keymap-default)
          (iedit-make-markers-overlays iedit-occurrences-overlays)
          (setq counter 2))
      (setq iedit-occurrence-keymap iedit-mode-occurrence-keymap)
      (setq counter (iedit-make-occurrences-overlays occurrence-regexp beg end)))
    (message "%d matches for \"%s\""
             counter
             (iedit-printable occurrence-regexp))
    (setq iedit-mode t))
  (iedit-lib-start 'iedit-done)
  (run-hooks 'iedit-mode-hook))

(defun iedit-default-occurrence()
  "Return the occurrence candidate string.
The candidate depends on the thing at point."
  (let (occurrence-type occurrence-str)
    (cond
     ((thing-at-point 'url)
      (setq occurrence-str (thing-at-point 'url))
      (setq occurrence-type 'url))

     ((thing-at-point 'email)
      (setq occurrence-str (thing-at-point 'email))
      (setq occurrence-type 'email))

     (iedit-default-occurrence-local
      (cl-multiple-value-setq (occurrence-type occurrence-str)
        (funcall iedit-default-occurrence-local)))
     ;; Try to mark sgml pair anyway
     ((and (not (bound-and-true-p sgml-electric-tag-pair-mode))
           (setq occurrence-str (iedit-mark-sgml-pair)))
      (setq occurrence-type 'markup-tag))

     ((and iedit-use-symbol-boundaries ;option
           (thing-at-point 'symbol))
      (setq occurrence-str (thing-at-point 'symbol))
      (setq occurrence-type 'symbol))

     ((thing-at-point 'word)
      (setq occurrence-str (thing-at-point 'word))
      (setq occurrence-type 'word)))
    (cons occurrence-type occurrence-str)))

(defun iedit-regexp-quote (occurrence)
  "Return a regexp for the occurrence string."
  (cl-case (car occurrence)
    (symbol (concat "\\_<" (regexp-quote (cdr occurrence)) "\\_>"))
    (word   (concat "\\<" (regexp-quote (cdr occurrence)) "\\>"))
    (regexp (cdr occurrence))
    ( t      (regexp-quote (cdr occurrence)))))

(defun iedit-mark-sgml-pair ()
  "Check if the cursor is on a markup tag.
If the cursor is on a markup tag, the position of the opening and
closing markup tags are saved in `iedit-occurrences-overlays'
temporarily.

The code is adapted from
`sgml-electric-tag-pair-before-change-function'.

Return the tag if succeeded, nil if failed."
  (condition-case nil
      (save-excursion
        (skip-chars-backward "[:alnum:]-_.:")
        (if  (or (eq (char-before) ?<)
                 (and (eq (char-before) ?/)
                      (eq (char-before (1- (point))) ?<)))
            (let* ((endp (eq (char-before) ?/))
                   (cl-start (point))
                   (cl-end (progn (skip-chars-forward "[:alnum:]-_.:") (point)))
                   (match
                    (if endp
                        (with-no-warnings (when (sgml-skip-tag-backward 1) (forward-char 1) t))
                      (with-syntax-table sgml-tag-syntax-table
                        (up-list -1)
                        (with-no-warnings (when (sgml-skip-tag-forward 1))
                                          (backward-sexp 1)
                                          (forward-char 2)
                                          t)))))
              (when (and match
                         (/= cl-end cl-start)
                         (equal (buffer-substring cl-start cl-end)
                                (buffer-substring (point)
                                                  (save-excursion
                                                    (skip-chars-forward "[:alnum:]-_.:")
                                                    (point))))
                         (or (not endp) (eq (char-after cl-end) ?>)))
                (push (cons cl-start cl-end) iedit-occurrences-overlays)
                (push (cons (point) (+ (point) (- cl-end cl-start))) iedit-occurrences-overlays)
                (buffer-substring cl-start cl-end)))))
    (error nil)))

(defun iedit-current-occurrence()
  "Return a cons cell (TYPE . STRING) giving the current occurrence."
  (let ((occurrence-str (iedit-current-occurrence-string)))
    (if occurrence-str  (cons (car iedit-initial-occurrence-local) occurrence-str)
      nil)))

(defun iedit-done ()
  "Exit Iedit mode.
Save the current occurrence string locally and globally.  Save
the initial string globally."
  (setq iedit-last-initial-occurrence-global iedit-initial-occurrence-local)
  (setq iedit-last-occurrence-global (iedit-current-occurrence))
  (if (and iedit-auto-save-occurrence-in-kill-ring iedit-last-occurrence-global)
      (kill-new (cdr iedit-last-occurrence-global))) ; Make occurrence the latest kill in the kill ring.
  (setq iedit-num-lines-to-expand-up 0)
  (setq iedit-num-lines-to-expand-down 0)

  (iedit-lib-cleanup)

  (when iedit-is-narrowed
    (widen)
    (setq iedit-is-narrowed nil))
  (setq iedit-initial-occurrence-local nil)
  (setq iedit-mode nil)
  (force-mode-line-update)
  (run-hooks 'iedit-mode-end-hook))

(defun iedit-mode-on-action (&optional arg)
  "Turn off Iedit mode or restrict it in a region if region is active.
Also restrict it if optional ARG value is 0"
  (cond ((iedit-region-active)
         (iedit-restrict-region (region-beginning) (region-end) arg))
        ((and arg
              (= 0 (prefix-numeric-value arg)))
         (iedit-restrict-function nil))
        ((and arg
              (= 4 (prefix-numeric-value arg)))
         (iedit-cycle-occurrence-type))
        (t (iedit-done))))

;;;###autoload
(defun iedit-mode-toggle-on-function ()
  "Toggle Iedit mode on current function."
  (interactive)
  (if iedit-mode
      (iedit-done)
    (let ((current-prefix-arg '(0)))
       (call-interactively 'iedit-mode))))

;;;###autoload
(defun iedit-execute-last-modification ()
  "Apply the modifications from the most recent Iedit session to the
current buffer or the active region."
  (interactive "*")
  (or (and iedit-last-initial-occurrence-global
           (not (equal iedit-last-initial-occurrence-global iedit-last-occurrence-global)))
      (error "No modification available"))
  (let ((occurrence-exp (iedit-regexp-quote iedit-last-initial-occurrence-global))
        (replacement (cdr iedit-last-occurrence-global))
        (case-fold-search (not iedit-case-sensitive))
        beg end)
    (when case-fold-search
      (setq occurrence-exp (downcase occurrence-exp))
      (setq replacement (downcase replacement)))
    (when (iedit-region-active)
      (setq beg (region-beginning))
      (setq end (region-end)))
    (perform-replace occurrence-exp replacement t t nil nil nil beg end)))

(defun iedit-apply-last-modification ()
  "Apply the modifications from the most recent Iedit session to this."
  (interactive "*")
  (if (and iedit-last-initial-occurrence-global
           (equal iedit-initial-occurrence-local iedit-last-initial-occurrence-global)
           (not (equal iedit-last-initial-occurrence-global iedit-last-occurrence-global)))
      (iedit-replace-occurrences (cdr iedit-last-occurrence-global))
    (message "No modification available.")))

(defun iedit-toggle-selection ()
  "Select or deselect the occurrence under point."
  (interactive)
  (iedit-barf-if-buffering)
  (let ((ov (iedit-find-current-occurrence-overlay)))
    (if ov
        (iedit-restrict-region (overlay-start ov) (overlay-end ov) t)
      (let ((current-occurrence (iedit-current-occurrence)))
        (when current-occurrence
          (save-excursion
            (goto-char (if (> (point) (length (cdr current-occurrence)))
                           (- (point) (length (cdr current-occurrence)))
                         (point-min)))
            (iedit-add-next-occurrence-overlay
             (iedit-regexp-quote  current-occurrence)))
          (force-mode-line-update))))))

(defun iedit-restrict-function(&optional exclusive)
  "Restrict Iedit mode in current function.
If optional EXCLUSIVE argument is non-nil restrict outside current function."
  (interactive "P")
  (let (beg end)
    (save-excursion
      (deactivate-mark t)
      (mark-defun)
      (setq beg (region-beginning))
      (setq end (region-end)))
    (iedit-restrict-region beg end exclusive)
    (when (and (not exclusive)
               iedit-auto-narrow
               (not (buffer-narrowed-p)))
      (narrow-to-region beg end)
      (setq iedit-is-narrowed t)))
  (message "Restricted in current function, %d matches."
           (length iedit-occurrences-overlays)))

(defun iedit-restrict-current-line ()
  "Restrict Iedit mode to current line."
  (interactive)
  (iedit-restrict-region (iedit-char-at-bol) (iedit-char-at-eol))
  (setq iedit-num-lines-to-expand-up 0
        iedit-num-lines-to-expand-down 0)
  (message "Restricted to current line, %d match%s."
           (length iedit-occurrences-overlays)
           (if (= 1 (length iedit-occurrences-overlays)) "" "es")))

(defun iedit-expand-by-a-line (where n-lines)
  "Expand the top or bottom of search region upwards or downwards by N-LINES.
The region being acted upon is controlled with WHERE: - \\='top to act
on the top, anything else for the bottom.  If N-LINES is negative,
collapses the top or bottom of the search region by - N-LINES."
  (let ((occurrence (iedit-current-occurrence)))
    (iedit-lib-cleanup)
    (if (eq where 'top)
        (setq iedit-num-lines-to-expand-up
              (max 0 (+ n-lines iedit-num-lines-to-expand-up)))
      (setq iedit-num-lines-to-expand-down
            (max 0 (+ n-lines iedit-num-lines-to-expand-down))))
    (iedit-start occurrence
                 (iedit-char-at-bol (- iedit-num-lines-to-expand-up))
                 (iedit-char-at-eol iedit-num-lines-to-expand-down))
    (message "Now looking -%d/+%d lines around current line, %d match%s."
             iedit-num-lines-to-expand-up
             iedit-num-lines-to-expand-down
             (length iedit-occurrences-overlays)
             (if (= 1 (length iedit-occurrences-overlays)) "" "es"))))

(defun iedit-expand-up-a-line (&optional N)
  "Expand search region upward by N lines.
N defaults to 1.  If N is negative, collapses the top of the search
region by -N lines.
Use after starting `iedit-mode' on current symbol or the active region."
  (interactive "p")
  (iedit-expand-by-a-line 'top N))

(defun iedit-expand-down-a-line (&optional N)
  "Expand search region downward by N lines.
N defaults to 1.  If N is negative, collapses the bottom of the search
region by -N lines.
Use after starting `iedit-mode' on current symbol or the active region."
  (interactive "p")
  (iedit-expand-by-a-line 'bottom N))

(defun iedit-expand-down-to-occurrence (&optional arg)
  "Expand the search region downwards until reaching a new occurrence.
If no such occurrence can be found, throw an error.  With a
prefix ARG, bring the bottom of the region back up one occurrence."
  (interactive "P")
  (if arg
      (progn (iedit-restrict-region
              (iedit-first-occurrence)
              (1- (iedit-last-occurrence)))
             (when iedit-mode
               (goto-char (iedit-last-occurrence))))
    (iedit-expand-to-occurrence t)))

(defun iedit-expand-up-to-occurrence (&optional arg)
  "Expand the search region upwards until reaching a new occurrence.
If no such occurrence can be found, throw an error.  With a
prefix ARG, bring the top of the region back down one occurrence."
  (interactive "P")
  (if arg
      (progn (iedit-restrict-region
              (+ (iedit-occurrence-string-length) (iedit-first-occurrence))
              (+ (iedit-occurrence-string-length) (iedit-last-occurrence)))
             (when iedit-mode
               (goto-char (iedit-first-occurrence))))
    (iedit-expand-to-occurrence nil)))

(defun iedit-expand-to-occurrence (forward)
  "Expand to next or previous occurrence.
Expand to next when FORWARD is non-nil, to previous otherwise."
  (let ((pos (iedit-add-occurrence-overlay
              (iedit-regexp-quote (iedit-current-occurrence))
              (if forward
                  (1+ (iedit-last-occurrence))
                (iedit-first-occurrence))
              forward)))
    (when pos
      (goto-char pos)
      (force-mode-line-update))))

(defun iedit-restrict-region (beg end &optional exclusive)
  "Restrict Iedit mode in region that ranges from BEG to END position.
If EXCLUSIVE is non-nil return it for outside of specified region."
  (if (null (iedit-find-overlay beg end 'iedit-occurrence-overlay-name exclusive))
      (iedit-done)
    (setq mark-active nil)
    (run-hooks 'deactivate-mark-hook)
    (iedit-cleanup-occurrences-overlays beg end exclusive)
    (setq iedit-initial-region (list beg end exclusive))
    (if iedit-hiding
        (iedit-hide-context-lines iedit-occurrence-context-lines))
    (force-mode-line-update)))

(defun iedit-toggle-case-sensitive ()
  "Toggle case-sensitive matching occurrences."
  (interactive)
  (setq iedit-case-sensitive (not iedit-case-sensitive))
  (let ((occurrence (iedit-current-occurrence)))
    (when occurrence
      (iedit-cleanup-occurrences-overlays)
      (let* ((occurrence-regexp (iedit-regexp-quote  occurrence))
             (begin (car iedit-initial-region))
             (end (cadr iedit-initial-region))
             (counter (iedit-make-occurrences-overlays occurrence-regexp begin end)))
        (message "iedit %s. %d matches for \"%s\""
                 (if iedit-case-sensitive
                     "is case sensitive"
                   "ignores case")
                 counter
                 (iedit-printable occurrence-regexp))
        (force-mode-line-update)))))

(defun iedit-toggle-apply-isearch-filter ()
  "Toggle `isearch-filter-predicate' matching occurrences."
  (interactive)
  (setq iedit-apply-isearch-filter (not iedit-apply-isearch-filter))
  (let ((occurrence (iedit-current-occurrence)))
    (when occurrence
      (iedit-cleanup-occurrences-overlays)
      (let* ((occurrence-regexp (iedit-regexp-quote  occurrence))
             (begin (car iedit-initial-region))
             (end (cadr iedit-initial-region))
             (counter (iedit-make-occurrences-overlays occurrence-regexp begin end)))
        (message "iedit %s. %d matches for \"%s\""
                 (if iedit-apply-isearch-filter
                     "is filtered by `isearch-filter-predicate'"
                   "ignores `isearch-filter-predicate'")
                 counter
                 (iedit-printable occurrence-regexp))
        (force-mode-line-update)))))

(defun iedit-toggle-search-invisible ()
  "Toggle `search-invisible' matching occurrences."
  (interactive)
  (setq iedit-search-invisible
        (if iedit-search-invisible
            nil
          (or search-invisible 'open)))
  (let ((occurrence (iedit-current-occurrence)))
    (when occurrence
      (iedit-cleanup-occurrences-overlays)
      (let* ((occurrence-regexp (iedit-regexp-quote occurrence))
             (begin (car iedit-initial-region))
             (end (cadr iedit-initial-region))
             (counter (iedit-make-occurrences-overlays occurrence-regexp begin end)))
        (message "iedit %s. %d matches for \"%s\""
                 (if iedit-search-invisible
                     "matching invisible"
                   "matching visible")
                 counter
                 (iedit-printable occurrence-regexp))
        (force-mode-line-update)))))

(defun iedit-cycle-occurrence-type()
  "Cycling occurrence type in (symbol word regexp other)."
  (interactive)
  (let ((occurrence (or (iedit-current-occurrence) iedit-initial-occurrence-local)))
    (when occurrence
      (setq occurrence
            (cons
             (cl-case (car occurrence)
               (symbol 'word)
               (word   'regexp)
               (regexp 'selection)
               (t  'symbol))
             (cdr occurrence)))
      (setq iedit-initial-occurrence-local occurrence)
      (iedit-cleanup-occurrences-overlays)
      (let* ((occurrence-regexp (iedit-regexp-quote  occurrence))
             (begin (car iedit-initial-region))
             (end (cadr iedit-initial-region))
             (counter (iedit-make-occurrences-overlays occurrence-regexp begin end)))
        (message "%d matches for %s \"%s\""
                 counter
                 (car occurrence)
                 (iedit-printable occurrence-regexp))
        (force-mode-line-update)))))

(provide 'iedit)

;;; iedit.el ends here

;;  LocalWords:  iedit el MERCHANTABILITY kbd isearch todo ert Lindberg Tassilo
;;  LocalWords:  eval defgroup defcustom boolean defvar assq alist nconc Ren
;;  LocalWords:  substring cadr keymap defconst purecopy bkm defun princ prev
;;  LocalWords:  iso lefttab backtab upcase downcase concat setq autoload arg
;;  LocalWords:  refactoring propertize cond goto nreverse progn rotatef eq elp
;;  LocalWords:  dolist pos unmatch args ov sReplace iedit's cdr quote'ed RET
;;  LocalWords:  sgml esc num perl memq url functionp funcall str alnum endp
;;  LocalWords:  sexp bol eol
