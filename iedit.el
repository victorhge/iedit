;;; iedit.el --- Edit multiple regions in the same way simultaneously.

;; Copyright (C) 2010, 2011, 2012 Victor Ren

;; Time-stamp: <2012-08-28 15:52:48 Victor Ren>
;; Author: Victor Ren <victorhge@gmail.com>
;; Keywords: occurrence region simultaneous rectangle refactoring
;; Version: 0.97
;; X-URL: http://www.emacswiki.org/emacs/Iedit
;; Compatibility: GNU Emacs: 22.x, 23.x, 24.x

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

;; This package is an Emacs minor mode and allows you to edit one occurrence of
;; some text in a buffer (possibly narrowed) or region, and simultaneously have
;; other occurrences edited in the same way.
;;
;; Normal scenario of iedit-mode is like:
;;
;; - Highlight certain contents - by press C-;
;;   All occurrences of a symbol, string or a rectangle in the buffer or a
;;   region may be highlighted corresponding to current mark, point and prefix
;;   argument.  Refer to the document of `iedit-mode' for details.
;;
;; - Edit one of the occurrences
;;   The change is applied to other occurrences simultaneously.
;;
;; - Finish - by pressing C-; again
;;
;; This package also provides rectangle support with *visible rectangle*
;; highlighting, which is similar with cua mode rectangle support, but still
;; quite different.

;; You can also use Iedit mode as a quick way to temporarily show only the
;; buffer lines that match the current text being edited.  This gives you the
;; effect of a temporary `keep-lines' or `occur'.  To get this effect, hit C-'
;; when in Iedit mode - it toggles hiding non-matching lines.
;;
;; Renaming refactoring is convenient in Iedit mode
;;
;; - The symbol under point is selected as occurrence by default and only
;;   complete symbols are matched
;; - With digit prefix argument 0, only symbols in current function are matched
;; - Restricting symbols in current region can be done by pressing C-; again
;; - Last renaming refactoring is remembered and can be applied to other buffers
;;   later
;;
;; There are also some other facilities you may never think about.  Refer to the
;; document of function `iedit-mode' (C-h f iedit-mode RET) for more details.

;; The code was developed and fully tested on Gnu Emacs 24.0.93, partially
;; tested on Gnu Emacs 22. If you have any compatible problem, please let me
;; know.

;;; todo:
;; - Add more easy access keys for whole occurrence

;;; Contributors
;; Adam Lindberg <eproxus@gmail.com> added a case sensitivity option that can be toggled.

;; Tassilo Horn <tassilo@member.fsf.org> added an option to match only complete
;; words, not inside words

;; Le Wang <l26wang@gmail.com> proposed to match only complete symbols,  not
;; inside symbols, contributed rectangle support

;;; Code:

(eval-when-compile (require 'cl))
(require 'rect) ;; kill rectangle

(defgroup iedit nil
  "Edit multiple regions in the same way simultaneously."
  :prefix "iedit-"
  :group 'replace
  :group 'convenience)

(defcustom iedit-occurrence-face 'highlight
  "*Face used for the occurrences' default values."
  :type 'face
  :group 'iedit)

(defcustom iedit-current-symbol-default t
  "If no-nil, use current symbol by default for the occurrence."
  :type 'boolean
  :group 'iedit)

(defcustom iedit-case-sensitive-default t
  "If no-nil, matching is case sensitive."
  :type 'boolean
  :group 'iedit)

(defcustom iedit-only-at-symbol-boundaries t
  "If no-nil, matches have to start and end at symbol boundaries.
For example, when invoking command `iedit-mode' on the \"in\" in the
  sentence \"The king in the castle...\", the \"king\" is not
  edited."
  :type 'boolean
  :group 'iedit)

(defcustom iedit-unmatched-lines-invisible-default nil
  "If no-nil, hide lines that do not cover any occurrences by default."

  :type 'boolean
  :group 'iedit)

(defcustom iedit-transient-mark-sensitive t
  "If no-nil, Iedit mode is sensitive to the Transient Mark mode."
  :type 'boolean
  :group 'iedit)

(defvar iedit-mode-hook nil
  "Function(s) to call after starting up an iedit.")

(defvar iedit-mode-end-hook nil
  "Function(s) to call after terminating an iedit.")

(defvar iedit-mode nil) ;; Name of the minor mode

(make-variable-buffer-local 'iedit-mode)

(or (assq 'iedit-mode minor-mode-alist)
    (nconc minor-mode-alist
           (list '(iedit-mode iedit-mode))))

;;; Default key bindings:
(define-key global-map (kbd "C-;") 'iedit-mode)
(define-key isearch-mode-map (kbd "C-;") 'iedit-mode)
(define-key esc-map (kbd "C-;") 'iedit-execute-last-modification)
(define-key help-map (kbd "C-;") 'iedit-mode-toggle-on-function)
(define-key global-map [C-return] 'iedit-rectangle-mode)

(defvar iedit-last-initial-string-global nil
  "This is a global variable which is the last initial occurrence string.")

(defvar iedit-initial-string-local nil
  "This is buffer local variable which is the initial string to start Iedit mode.")

(defvar iedit-occurrences-overlays nil
  "The occurrences slot contains a list of overlays used to
indicate the position of each occurrence.  In addition, the
occurrence overlay is used to provide a different face
configurable via `iedit-occurrence-face'.")

(defvar iedit-case-sensitive-local iedit-case-sensitive-default
  "This is buffer local variable.
If no-nil, matching is case sensitive.")

(defvar iedit-case-sensitive-global iedit-case-sensitive-default
  "This is global variable.
If no-nil, matching is case sensitive.")

(defvar iedit-unmatched-lines-invisible nil
  "This is buffer local variable which indicates whether
unmatched lines are hided.")

(defvar iedit-last-occurrence-local nil
  "This is buffer local variable which is the occurrence when
Iedit mode is turned off last time.")

(defvar iedit-last-occurrence-global nil
  "This is global variable which is the occurrence when
Iedit mode is turned off last time.")

(defvar iedit-only-complete-symbol-local nil
  "This is buffer local variable which indicates the occurrence
only matches complete symbol.")

(defvar iedit-only-complete-symbol-global nil
  "This is global variable which indicates the last global occurrence
only matches complete symbol.")

(defvar iedit-forward-success t
  "This is buffer local variable which indicates the moving
forward or backward successful")

(defvar iedit-before-modification-string ""
  "This is buffer local variable which is the buffer substring that is going to be changed.")

(defvar iedit-before-modification-undo-list nil
  "This is buffer local variable which is the buffer undo list before modification.")

;; `iedit-occurrence-update' gets called twice when change==0 and occurrence
;; is zero-width (beg==end)
;; -- for front and back insertion.
(defvar iedit-skip-modification-once t
  "Variable used to skip first modification hook run when
insertion against a zero-width occurrence.")

(defvar iedit-aborting nil
  "This is buffer local variable which indicates Iedit mode is aborting.")

(defvar iedit-post-undo-hook-installed nil
  "This is buffer local variable which indicated if
  iedit-post-undo-hook is installed in `post-command-hook'.")

(defvar iedit-buffering nil
  "This is buffer local variable which indicates iedit-mode is
buffering, which means the modification to the current occurrence
is not applied to other occurrences when it is true.")

(defvar iedit-rectangle nil
  "This buffer local variable which is the rectangle geometry if
current mode is iedit-rect. Otherwise it is nil.
\(car iedit-rectangle) is the top-left corner and
\(cadr iedit-rectangle) is the bottom-right corner" )

(defvar iedit-current-keymap 'iedit-occurrence-keymap
  "The current keymap, `iedit-occurrence-keymap' or `iedit-rect-keymap'.")

(defvar iedit-occurrence-context-lines 1
  "The number of lines before or after the occurrence.")

(make-variable-buffer-local 'iedit-occurrences-overlays)
(make-variable-buffer-local 'iedit-unmatched-lines-invisible)
(make-variable-buffer-local 'iedit-case-sensitive-local)
(make-variable-buffer-local 'iedit-last-occurrence-local)
(make-variable-buffer-local 'iedit-only-complete-symbol-local)
(make-variable-buffer-local 'iedit-forward-success)
(make-variable-buffer-local 'iedit-before-modification-string)
(make-variable-buffer-local 'iedit-before-modification-undo-list)
(make-variable-buffer-local 'iedit-skip-modification-once)
(make-variable-buffer-local 'iedit-aborting)
(make-variable-buffer-local 'iedit-buffering)
(make-variable-buffer-local 'iedit-rectangle)
(make-variable-buffer-local 'iedit-current-keymap)
(make-variable-buffer-local 'iedit-post-undo-hook-installed)
(make-variable-buffer-local 'iedit-occurrence-context-lines)

(defconst iedit-occurrence-overlay-name 'iedit-occurrence-overlay-name)
(defconst iedit-invisible-overlay-name 'iedit-invisible-overlay-name)

;;; Define iedit help map.
(eval-when-compile (require 'help-macro))

(defvar iedit-help-map
  (let ((map (make-sparse-keymap)))
    (define-key map (char-to-string help-char) 'iedit-help-for-help)
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
        (keymap (substitute-command-keys "\\{iedit-current-keymap}")))
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

;;; Define Iedit mode map
(defvar iedit-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Default key bindings
    (define-key map (kbd "TAB") 'iedit-next-occurrence)
    (define-key map (kbd "<S-tab>") 'iedit-prev-occurrence)
    (define-key map (kbd "<S-iso-lefttab>") 'iedit-prev-occurrence)
    (define-key map (kbd "<backtab>") 'iedit-prev-occurrence)
    (define-key map (kbd "C-'") 'iedit-toggle-unmatched-lines-visible)
    (define-key map (char-to-string help-char) iedit-help-map)
    (define-key map [help] iedit-help-map)
    (define-key map [f1] iedit-help-map)
    map)
  "Keymap used while Iedit mode is enabled.")

(defvar iedit-occurrence-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map iedit-mode-map)
    (define-key map (kbd "M-U") 'iedit-upcase-occurrences)
    (define-key map (kbd "M-L") 'iedit-downcase-occurrences)
    (define-key map (kbd "M-R") 'iedit-replace-occurrences)
    (define-key map (kbd "M-SPC") 'iedit-blank-occurrences)
    (define-key map (kbd "M-C") 'iedit-toggle-case-sensitive)
    (define-key map (kbd "M-D") 'iedit-delete-occurrences)
    (define-key map (kbd "M-N") 'iedit-number-occurrences)
    (define-key map (kbd "M-;") 'iedit-apply-global-modification)
    (define-key map (kbd "M-B") 'iedit-toggle-buffering)
    (define-key map (kbd "M-<") 'iedit-first-occurrence)
    (define-key map (kbd "M->") 'iedit-last-occurrence)
    (define-key map (kbd "M-H") 'iedit-restrict-function)
    (define-key map (kbd "C-?") 'iedit-help-for-occurrences)
    map)
  "Keymap used within overlays in Iedit mode.")

(defvar iedit-rect-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map iedit-occurrence-keymap)
    (define-key map (kbd "M-K") 'iedit-kill-rectangle)
    map)
  "Keymap used within overlays in iedit-RECT mode.")

(defun iedit-help-for-occurrences ()
  "Display `iedit-occurrence-keymap' or `iedit-rect-keymap'."
  (interactive)
  (message (concat (substitute-command-keys "\\[iedit-upcase-occurrences]") "/"
                   (substitute-command-keys "\\[iedit-downcase-occurrences]") ":up/downcase "
                   (substitute-command-keys "\\[iedit-replace-occurrences]") ":replace "
                   (substitute-command-keys "\\[iedit-blank-occurrences]") ":blank "
                   (substitute-command-keys "\\[iedit-delete-occurrences]") ":delete "
                   (substitute-command-keys "\\[iedit-number-occurrences]") ":number "
                   (substitute-command-keys "\\[iedit-toggle-case-sensitive]") ":case "
                   (substitute-command-keys "\\[iedit-apply-global-modification]") ":redo "
                   (substitute-command-keys "\\[iedit-toggle-buffering]") ":buffering "
                   (substitute-command-keys "\\[iedit-first-occurrence]") "/"
                   (substitute-command-keys "\\[iedit-last-occurrence]") ":first/last "
                   (substitute-command-keys "\\[iedit-restrict-function]") ":restrict "
                   (if iedit-rectangle
                       (concat
                        (substitute-command-keys "\\[iedit-kill-rectangle]") ":kill")))))

(or (assq 'iedit-mode minor-mode-map-alist)
    (setq minor-mode-map-alist
          (cons (cons 'iedit-mode iedit-mode-map) minor-mode-map-alist)))

;; Avoid to restore Iedit mode when restoring desktop
(add-to-list 'desktop-minor-mode-handlers
             '(iedit-mode . nil))

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

If region is not active, the current symbol (returns from
`current-word') is used as the occurrence by default.  The
occurrences of the current symbol, but not include occurrences
that are part of other symbols, are highlighted.  If you still
want to match all the occurrences, even though they are parts of
other symbols, you may have to mark the symbol first.

In the above two situations, with digit prefix argument 0, only
occurrences in current function are matched.  This is good for
renaming refactoring in programming.

You can also switch to Iedit mode from isearch mode directly. The
current search string is used as occurrence.  All occurrences of
the current search string are highlighted.

With an universal prefix argument, the occurrence when Iedit mode
is turned off last time in current buffer is used as occurrence.
This is intended to recover last Iedit mode which is turned off.
If region active, Iedit mode is limited within the current
region.

With repeated universal prefix argument, the occurrence when
Iedit mode is turned off last time (might be in other buffer) is used
as occurrence.  If region active, Iedit mode is limited within
the current region.

If Iedit mode is on and region is active, Iedit mode is
restricted in the region, e.g. the occurrences outside of the region
is excluded.

If Iedit mode is on and region is active, with an universal
prefix argument, Iedit mode is restricted outside of the region,
e.g. the occurrences in the region is excluded.

Turn off Iedit mode in other situations.

Commands:
\\{iedit-current-keymap}"
  (interactive "P")
  (if iedit-mode
      (iedit-mode-on-action arg)
    (let (occurrence
          complete-symbol
          (beg (if (eq major-mode 'occur-edit-mode) ; skip the first occurrence
                   (next-single-char-property-change 1 'read-only)
                 (point-min)))
          (end (point-max)))
      (cond ((and arg
                  (= 4 (prefix-numeric-value arg))
                  iedit-last-occurrence-local)
             (setq occurrence iedit-last-occurrence-local)
             (setq complete-symbol iedit-only-complete-symbol-local))
            ((and arg
                  (= 16 (prefix-numeric-value arg))
                  iedit-last-initial-string-global)
             (setq occurrence iedit-last-initial-string-global)
             (setq complete-symbol iedit-only-complete-symbol-global))
            ((iedit-region-active)
             (setq occurrence  (buffer-substring-no-properties
                                (mark) (point))))
            ((and isearch-mode (not (string= isearch-string "")))
             (setq occurrence  (buffer-substring-no-properties
                                (point) isearch-other-end))
             (isearch-exit))
            ((and iedit-current-symbol-default (current-word t))
             (setq occurrence  (current-word))
             (when iedit-only-at-symbol-boundaries
               (setq complete-symbol t)))
            (t (error "No candidate of the occurrence, cannot enable Iedit mode")))
      (when arg
        (if (= 0 (prefix-numeric-value arg))
            (save-excursion
              (mark-defun)
              (setq beg (region-beginning))
              (setq end (region-end)))
          (when (iedit-region-active)
            (setq beg (region-beginning))
            (setq end (region-end)))))
      (setq iedit-only-complete-symbol-local complete-symbol)
      (set-mark nil)
      (setq iedit-case-sensitive-local iedit-case-sensitive-default)
      (iedit-start occurrence beg end))))

;;;###autoload
(defun iedit-mode-toggle-on-function ()
  "Toggle Iedit mode on current function."
  (interactive)
  (iedit-mode 0))

;;;###autoload
(defun iedit-rectangle-mode ()
  "Toggle iedit-RECT mode."
  (interactive)
  (if iedit-mode
      (iedit-mode-on-action)
    (if (iedit-region-active)
        (let ((beg (region-beginning))
              (end (region-end)))
          (set-mark nil)
          (iedit-rectangle-start beg end)))))

(defun iedit-mode-on-action (&optional arg)
  "Turn off Iedit mode or restrict it in a region if region is active."
  (if (iedit-region-active)
      ;; Restrict iedit-mode
      (let ((beg (region-beginning))
            (end (region-end)))
        (if (null (iedit-find-overlay beg end 'iedit-occurrence-overlay-name arg))
            (iedit-done)
          (iedit-restrict-region beg end arg)
          (iedit-first-occurrence)))
    (iedit-done)))

(defun iedit-start (occurrence-exp beg end)
  "Start Iedit mode for the OCCURRENCE-EXP in the current buffer."
  (setq iedit-unmatched-lines-invisible iedit-unmatched-lines-invisible-default)
  (setq iedit-aborting nil)
  (setq iedit-rectangle nil)
  (setq iedit-current-keymap iedit-occurrence-keymap)
  (iedit-refresh occurrence-exp beg end)
  (run-hooks 'iedit-mode-hook)
  (add-hook 'kbd-macro-termination-hook 'iedit-done nil t)
  (add-hook 'change-major-mode-hook 'iedit-done nil t))

(defun iedit-refresh (occurrence-exp beg end)
  "Refresh Iedit mode."
  (setq iedit-occurrences-overlays nil)
  (setq iedit-initial-string-local occurrence-exp)
  (setq occurrence-exp (regexp-quote occurrence-exp))
  (when iedit-only-complete-symbol-local
    (setq occurrence-exp (concat "\\_<" occurrence-exp "\\_>")))
  ;; Find and record each occurrence's markers and add the overlay to the occurrences
  (let ((counter 0)
        (case-fold-search (not iedit-case-sensitive-local)))
    (save-excursion
      (goto-char beg)
      (while (re-search-forward occurrence-exp end t)
        (push (iedit-make-occurrence-overlay (match-beginning 0) (match-end 0))
              iedit-occurrences-overlays)
        (setq counter (1+ counter)))
      (if (= 0 counter)
          (error "0 matches for \"%s\"" (iedit-printable occurrence-exp))
        (setq iedit-occurrences-overlays (nreverse iedit-occurrences-overlays))
        (if iedit-unmatched-lines-invisible
            (iedit-hide-unmatched-lines iedit-occurrence-context-lines)))
      (message "%d matches for \"%s\"" counter (iedit-printable occurrence-exp))
      (setq iedit-mode (propertize (concat " Iedit:" (number-to-string counter))
                                   'face 'font-lock-warning-face))
      (force-mode-line-update))))

(defun iedit-rectangle-start (beg end)
  "Start Iedit mode for the region as a rectangle."
  (barf-if-buffer-read-only)
  (setq iedit-occurrences-overlays nil)
  (setq iedit-rectangle (list beg end))
  (setq iedit-initial-string-local nil)
  (setq iedit-current-keymap iedit-rect-keymap)
  (save-excursion
    (let ((beg-col (progn (goto-char beg) (current-column)))
          (end-col (progn (goto-char end) (current-column))))
      (when (< end-col beg-col)
        (rotatef beg-col end-col))
      (goto-char beg)
      (loop do (progn
                 (push (iedit-make-occurrence-overlay
                        (progn
                          (move-to-column beg-col t)
                          (point))
                        (progn
                          (move-to-column end-col t)
                          (point)))
                       iedit-occurrences-overlays)
                 (forward-line 1))
            until (> (point) end))
      (setq iedit-occurrences-overlays (nreverse iedit-occurrences-overlays))))
  (setq iedit-mode (propertize
                    (concat " Iedit-RECT:" (number-to-string (length iedit-occurrences-overlays)))
                    'face 'font-lock-warning-face))
  (force-mode-line-update)
  (run-hooks 'iedit-mode-hook)
  (add-hook 'kbd-macro-termination-hook 'iedit-done nil t)
  (add-hook 'change-major-mode-hook 'iedit-done nil t))

(defun iedit-done ()
  "Exit Iedit mode.
Save the current occurrence string locally and globally.  Save
the initial string globally."
  (if iedit-buffering
      (iedit-stop-buffering))
  (when (null iedit-rectangle)
    (setq iedit-last-occurrence-local (iedit-current-occurrence-string))
    (setq iedit-last-occurrence-global iedit-last-occurrence-local)
    (setq iedit-only-complete-symbol-global iedit-only-complete-symbol-local)
    (setq iedit-last-initial-string-global iedit-initial-string-local)
    (setq iedit-case-sensitive-global iedit-case-sensitive-local))
  (remove-overlays nil nil iedit-occurrence-overlay-name t)
  (iedit-show-all)
  (setq iedit-occurrences-overlays nil)
  (setq iedit-aborting nil)
  (setq iedit-before-modification-string "")
  (setq iedit-before-modification-undo-list nil)
  (setq iedit-mode nil)
  (force-mode-line-update)
  (remove-hook 'kbd-macro-termination-hook 'iedit-done t)
  (remove-hook 'change-major-mode-hook 'iedit-done t)
  (run-hooks 'iedit-mode-end-hook))

(defun iedit-execute-last-modification (&optional arg)
  "Apply last modification in Iedit mode to the current buffer or an active region."
  (interactive "*P")
  (or (and iedit-last-initial-string-global
           (not (string= iedit-last-initial-string-global iedit-last-occurrence-global)))
      (error "No modification available"))
  (let ((occurrence-exp (regexp-quote iedit-last-initial-string-global))
        (replacement  iedit-last-occurrence-global)
        (case-fold-search (not iedit-case-sensitive-global))
        beg end)
    (when case-fold-search
      (setq occurrence-exp (downcase occurrence-exp))
      (setq replacement (downcase replacement)))
    (if iedit-only-complete-symbol-global
        (setq occurrence-exp (concat "\\_<"  occurrence-exp "\\_>")))
    (when (iedit-region-active)
          (setq beg (region-beginning))
          (setq end (region-end)))
    (perform-replace occurrence-exp replacement t t nil nil nil beg end)))

(defun iedit-make-occurrence-overlay (begin end)
  "Create an overlay for an occurrence in Iedit mode.
Add the properties for the overlay: a face used to display a
occurrence's default value, and modification hooks to update
occurrences if the user starts typing."
  ;; Text inserted at the beginning and in the end is inside of the overlay.
  ;; Conjoined occurrences might be overlapped after modification
  (let ((occurrence (make-overlay begin end (current-buffer) nil t)))
    (overlay-put occurrence iedit-occurrence-overlay-name t)
    (overlay-put occurrence 'face iedit-occurrence-face)
    (overlay-put occurrence 'keymap iedit-current-keymap)
    (overlay-put occurrence 'insert-in-front-hooks '(iedit-occurrence-update))
    (overlay-put occurrence 'insert-behind-hooks '(iedit-occurrence-update))
    (overlay-put occurrence 'modification-hooks '(iedit-occurrence-update))
    occurrence))

(defun iedit-make-unmatched-lines-overlay (begin end)
  "Create an overlay for lines between two occurrences in Iedit mode."
  (let ((unmatched-lines-overlay (make-overlay begin end (current-buffer) nil t)))
    (overlay-put unmatched-lines-overlay iedit-invisible-overlay-name t)
    (overlay-put unmatched-lines-overlay 'invisible 'iedit-invisible-overlay-name)
    ;;    (overlay-put unmatched-lines-overlay 'intangible t)
    unmatched-lines-overlay))

(defun iedit-post-undo-hook ()
  "Check if it is time to abort iedit.

This is added to `post-command-hook' when undo command is executed
in occurrences."
  (if (iedit-same-length)
      nil
    (iedit-done))
  (remove-hook 'post-command-hook 'iedit-post-undo-hook t)
  (setq iedit-post-undo-hook-installed nil))

(defun iedit-reset-aborting ()
  "Turning Iedit mode off and reset `iedit-aborting'.

This is added to `post-command-hook' when aborting Iedit mode is
decided.  `iedit-done' is postponed after the current command is
executed for avoiding `iedit-occurrence-update' is called for a
removed overlay."
  (iedit-done)
  (remove-hook 'post-command-hook 'iedit-reset-aborting t)
  (setq iedit-aborting nil))

;; There are two ways to update all occurrence.  One is to redefine all key
;; stroke map for overlay, the other is to figure out three basic modification
;; in the modification hook.  This function chooses the latter.
(defun iedit-occurrence-update (occurrence after beg end &optional change)
  "Update all occurrences.
This modification hook is triggered when a user edits any
occurrence and is responsible for updating all other occurrences.
Current supported edits are insertion, yank, deletion and
replacement.  If this modification is going out of the
occurrence, it will abort Iedit mode."
  (if undo-in-progress
      (when (not iedit-post-undo-hook-installed)
        (add-hook 'post-command-hook 'iedit-post-undo-hook nil t)
        (setq iedit-post-undo-hook-installed t))
    (when (and (not iedit-aborting ))
    ;; before modification
    (if (null after)
        (if (or (< beg (overlay-start occurrence))
                (> end (overlay-end occurrence)))
            (progn (setq iedit-aborting t) ; abort iedit-mode
                   (add-hook 'post-command-hook 'iedit-reset-aborting nil t))
          (setq iedit-before-modification-string
                (buffer-substring-no-properties beg end))
          ;; Check if this is called twice before modification. When inserting
          ;; into zero-width occurrence or between two conjoined occurrences,
          ;; both insert-in-front-hooks and insert-behind-hooks will be
          ;; called.  Two calls will make `iedit-skip-modification-once' true.
          (setq iedit-skip-modification-once (not iedit-skip-modification-once)))
      ;; after modification
      (when (not iedit-buffering)
        (if iedit-skip-modification-once
            ;; Skip the first hook
            (setq iedit-skip-modification-once nil)
          (setq iedit-skip-modification-once t)
          (when (or (eq 0 change) ;; insertion
                    (eq beg end)  ;; deletion
                    (not (string= iedit-before-modification-string
                                  (buffer-substring-no-properties beg end))))
            (let ((inhibit-modification-hooks t) ; todo: extract this as a function
                  (offset (- beg (overlay-start occurrence)))
                  (value (buffer-substring-no-properties beg end)))
              (save-excursion
                ;; insertion or yank
                (if (eq 0 change)
                    (dolist (another-occurrence iedit-occurrences-overlays)
                      (let* ((beginning (+ (overlay-start another-occurrence) offset))
                             (ending (+ beginning (- end beg))))
                        (when (not (eq another-occurrence occurrence))
                          (goto-char beginning)
                          (insert-and-inherit value)
                          ;; todo: reconsider this change Quick fix for
                          ;; multi-occur occur-edit-mode: multi-occur depend on
                          ;; after-change-functions to update original
                          ;; buffer. Since inhibit-modification-hooks is set to
                          ;; non-nil, after-change-functions hooks are not going
                          ;; to be called for the changes of other occurrences.
                          ;; So run the hook here.
                          (run-hook-with-args 'after-change-functions
                                              beginning
                                              ending
                                              change))
                        (iedit-move-conjoined-overlays another-occurrence)))
                  ;; deletion
                  (dolist (another-occurrence (remove occurrence iedit-occurrences-overlays))
                    (let* ((beginning (+ (overlay-start another-occurrence) offset))
                           (ending (+ beginning change)))
                      (delete-region beginning ending)
                      (unless (eq beg end) ;; replacement
                        (goto-char beginning)
                        (insert-and-inherit value))
                      (run-hook-with-args 'after-change-functions
                                          beginning
                                          ending
                                          change)))))))))))))

(defun iedit-next-occurrence ()
  "Move forward to the next occurrence in the `iedit'.
If the point is already in the last occurrences, you are asked to type
another `iedit-next-occurrence', it starts again from the
beginning of the buffer."
  (interactive)
  (let ((pos (point))
        (in-occurrence (get-char-property (point) 'iedit-occurrence-overlay-name)))
    (when in-occurrence
      (setq pos (next-single-char-property-change pos 'iedit-occurrence-overlay-name)))
    (setq pos (next-single-char-property-change pos 'iedit-occurrence-overlay-name))
    (if (/= pos (point-max))
        (setq iedit-forward-success t)
      (if (and iedit-forward-success in-occurrence)
          (progn (message "This is the last occurrence.")
                 (setq iedit-forward-success nil))
        (progn
          (if (get-char-property (point-min) 'iedit-occurrence-overlay-name)
              (setq pos (point-min))
            (setq pos (next-single-char-property-change
                       (point-min)
                       'iedit-occurrence-overlay-name)))
          (setq iedit-forward-success t)
          (message "Located the first occurrence."))))
    (when iedit-forward-success
      (goto-char pos))))

(defun iedit-prev-occurrence ()
  "Move backward to the previous occurrence in the `iedit'.
If the point is already in the first occurrences, you are asked to type
another `iedit-prev-occurrence', it starts again from the end of
the buffer."
  (interactive)
  (let ((pos (point))
        (in-occurrence (get-char-property (point) 'iedit-occurrence-overlay-name)))
    (when in-occurrence
      (setq pos (previous-single-char-property-change pos 'iedit-occurrence-overlay-name)))
    (setq pos (previous-single-char-property-change pos 'iedit-occurrence-overlay-name))
    ;; At the start of the first occurrence
    (if (or (and (eq pos (point-min))
                 (not (get-char-property (point-min) 'iedit-occurrence-overlay-name)))
            (and (eq (point) (point-min))
                 in-occurrence))
        (if (and iedit-forward-success in-occurrence)
            (progn (message "This is the first occurrence.")
                   (setq iedit-forward-success nil))
          (progn
            (setq pos (previous-single-char-property-change (point-max) 'iedit-occurrence-overlay-name))
            (if (not (get-char-property (- (point-max) 1) 'iedit-occurrence-overlay-name))
                (setq pos (previous-single-char-property-change pos 'iedit-occurrence-overlay-name)))
            (setq iedit-forward-success t)
            (message "Located the last occurrence.")))
      (setq iedit-forward-success t))
    (when iedit-forward-success
      (goto-char pos))))

(defun iedit-first-occurrence ()
  "Move to the first occurrence."
  (interactive)
  (let ((pos (if (get-char-property (point-min) 'iedit-occurrence-overlay-name)
                 (point-min)
               (next-single-char-property-change
                (point-min) 'iedit-occurrence-overlay-name))))
    (setq iedit-forward-success t)
    (goto-char pos)
    (message "Located the first occurrence.")))

(defun iedit-last-occurrence ()
  "Move to the last occurrence."
  (interactive)
  (let ((pos (previous-single-char-property-change (point-max) 'iedit-occurrence-overlay-name)))
    (if (not (get-char-property (- (point-max) 1) 'iedit-occurrence-overlay-name))
        (setq pos (previous-single-char-property-change pos 'iedit-occurrence-overlay-name)))
    (setq iedit-forward-success t)
    (goto-char pos)
    (message "Located the last occurrence.")))

(defun iedit-toggle-unmatched-lines-visible (&optional arg)
  "Toggle whether to display unmatched lines.
A prefix ARG specifies how many lines before and after the
occurrences are not hided; negative is treated the same as zero.

If no prefix argument, the prefix argument last time or default
value of `iedit-occurrence-context-lines' is used for this time."
  (interactive "P")
  (if (null arg)
      ;; toggle visible
      (progn (setq iedit-unmatched-lines-invisible (not iedit-unmatched-lines-invisible))
             (if iedit-unmatched-lines-invisible
                 (iedit-hide-unmatched-lines iedit-occurrence-context-lines)
               (iedit-show-all)))
    ;; reset invisible lines
    (setq arg (prefix-numeric-value arg))
    (if (< arg 0)
        (setq arg 0))
    (unless (and iedit-unmatched-lines-invisible
                 (= arg iedit-occurrence-context-lines))
      (when iedit-unmatched-lines-invisible
        (remove-overlays nil nil iedit-invisible-overlay-name t))
      (setq iedit-occurrence-context-lines arg)
      (setq iedit-unmatched-lines-invisible t)
      (iedit-hide-unmatched-lines iedit-occurrence-context-lines))))

(defun iedit-show-all()
  "Show hided lines."
  (setq line-move-ignore-invisible nil)
  (remove-from-invisibility-spec '(iedit-invisible-overlay-name . t))
  (remove-overlays nil nil iedit-invisible-overlay-name t))

(defun iedit-hide-unmatched-lines (context-lines)
  "Hide unmatched lines using invisible overlay."
  (let ((prev-occurrence-end 1)
        (unmatched-lines nil))
    (save-excursion
      (dolist (overlay iedit-occurrences-overlays)
        (goto-char (overlay-start overlay))
        (forward-line (- context-lines))
        (let ((line-beginning (line-beginning-position)))
          (if (> line-beginning prev-occurrence-end)
              (push  (list prev-occurrence-end (1- line-beginning)) unmatched-lines)))
        (goto-char (overlay-end overlay))
        (forward-line context-lines)
        (setq prev-occurrence-end (line-end-position)))
      (if (< prev-occurrence-end (point-max))
          (push (list prev-occurrence-end (point-max)) unmatched-lines))
      (when unmatched-lines
        (set (make-local-variable 'line-move-ignore-invisible) t)
        (add-to-invisibility-spec '(iedit-invisible-overlay-name . t))
        (dolist (unmatch unmatched-lines)
          (iedit-make-unmatched-lines-overlay (car unmatch) (cadr unmatch)))))))

;;;; functions for overlay keymap
(defun iedit-apply-on-occurrences (function &rest args)
  "Call function for each occurrence."
  (let ((inhibit-modification-hooks t))
      (save-excursion
        (dolist (occurrence iedit-occurrences-overlays)
          (apply function (overlay-start occurrence) (overlay-end occurrence) args)))))

(defun iedit-upcase-occurrences ()
  "Covert occurrences to upper case."
  (interactive "*")
  (iedit-apply-on-occurrences 'upcase-region))

(defun iedit-downcase-occurrences()
  "Covert occurrences to lower case."
  (interactive "*")
  (iedit-apply-on-occurrences 'downcase-region))

(defun iedit-apply-global-modification ()
  "Apply last global modification."
  (interactive "*")
  (if (and iedit-last-initial-string-global
           (string= iedit-initial-string-local iedit-last-initial-string-global)
           (not (string= iedit-last-initial-string-global iedit-last-occurrence-global)))
      (iedit-replace-occurrences iedit-last-occurrence-global)
    (message "No global modification available.")))

(defun iedit-replace-occurrences(to-string)
  "Replace occurrences with STRING.
This function preserves case."
  (interactive "*sReplace with: ")
  (let* ((ov (iedit-find-current-occurrence-overlay))
         (offset (- (point) (overlay-start ov)))
         (from-string (downcase (buffer-substring-no-properties
                                 (overlay-start ov)
                                 (overlay-end ov)))))
    (iedit-apply-on-occurrences
     (lambda (beg end from-string to-string)
       (goto-char beg)
       (search-forward from-string end)
       (replace-match to-string nil))
     from-string to-string)
    (goto-char (+ (overlay-start ov) offset))))

(defun iedit-blank-occurrences()
  "Replace occurrences with blank spaces."
  (interactive "*")
  (let* ((ov (car iedit-occurrences-overlays))
         (offset (- (point) (overlay-start ov)))
         (count (- (overlay-end ov) (overlay-start ov))))
    (iedit-apply-on-occurrences
     (lambda (beg end )
       (delete-region beg end)
       (goto-char beg)
       (insert-and-inherit (make-string count 32))))
    (goto-char (+ (overlay-start ov) offset))))

(defun iedit-delete-occurrences()
  "Delete occurrences."
  (interactive "*")
  (iedit-apply-on-occurrences 'delete-region))

(defun iedit-toggle-case-sensitive ()
  "Toggle case-sensitive matching occurrences."
  (interactive)
  (setq iedit-case-sensitive-local (not iedit-case-sensitive-local))
  (if iedit-buffering
      (iedit-stop-buffering))
  (setq iedit-last-occurrence-local (iedit-current-occurrence-string))
  (when iedit-last-occurrence-local
    (remove-overlays nil nil iedit-occurrence-overlay-name t)
    (iedit-show-all)
    (iedit-refresh iedit-last-occurrence-local (point-min) (point-max))))

;; todo: add cancel buffering
(defun iedit-toggle-buffering ()
  "Toggle buffering.
This is intended to improve iedit's response time.  If the number
of occurrences are huge, it might be slow to update all the
occurrences for each key stoke.  When buffering is on,
modification is only applied to the current occurrence and will
be applied to other occurrences when buffering is off."
  (interactive "*")
  (if iedit-buffering
      (iedit-stop-buffering)
    (iedit-start-buffering))
  (message (concat "Iedit-mode buffering "
                   (if iedit-buffering
                       "started."
                     "stopped."))))

(defun iedit-start-buffering ()
  "Start buffering."
  (setq iedit-buffering t)
  (setq iedit-before-modification-string (iedit-current-occurrence-string))
  (setq iedit-before-modification-undo-list buffer-undo-list)
  (message "Start buffering editing...")
  ;; (setq iedit-mode (propertize
  ;;                   (concat " Iedit-B:" (number-to-string (length iedit-occurrences-overlays)))
  ;;                   'face 'font-lock-warning-face))
  ;; (force-mode-line-update)
  )

(defun iedit-stop-buffering ()
  "Stop buffering and apply the modification to other occurrences.
If current point is not at any occurrence, the buffered
modification is not going to be applied to other occurrences."
  (let ((ov (iedit-find-current-occurrence-overlay))
        (inhibit-modification-hooks t))
    (when ov
      (let* ((beg (overlay-start ov))
             (end (overlay-end ov))
             (modified-string (buffer-substring-no-properties beg end))
             (offset (- (point) beg))) ;; delete-region moves cursor
        (when (not (string= iedit-before-modification-string modified-string))
          (save-excursion
            ;; Rollback the current modification and buffer-undo-list. This is to
            ;; avoid the inconsistency if user undoes modifications
            (delete-region beg end)
            (goto-char beg)
            (insert-and-inherit iedit-before-modification-string)
            (setq buffer-undo-list iedit-before-modification-undo-list)
            (dolist (occurrence iedit-occurrences-overlays) ; todo:extract as a function
              (let ((beginning (overlay-start occurrence))
                    (ending (overlay-end occurrence)))
                (delete-region beginning ending)
                (unless (eq beg end) ;; replacement
                  (goto-char beginning)
                  (insert-and-inherit modified-string))
                (iedit-move-conjoined-overlays occurrence))))
          (goto-char (+ (overlay-start ov) offset))))))
  (setq iedit-buffering nil)
  ;; (setq iedit-mode (propertize
  ;;                   (concat (if iedit-rectangle " Iedit-RECT:" " Iedit:")
  ;;                           (number-to-string (length iedit-occurrences-overlays)))
  ;;                   'face 'font-lock-warning-face))
  ;; (force-mode-line-update)
  (message "Buffered modification applied.")
  (setq iedit-before-modification-undo-list nil))

(defun iedit-move-conjoined-overlays (occurrence)
  "This function keeps overlays conjoined after modification.
After modification, conjoined overlays may be overlapped."
  (let ((beginning (overlay-start occurrence))
        (ending (overlay-end occurrence)))
    (unless (= beginning (point-min))
      (let ((previous-overlay (iedit-find-overlay-at-point
                               (1- beginning)
                               'iedit-occurrence-overlay-name)))
        (if previous-overlay ; two conjoined occurrences
            (move-overlay previous-overlay
                          (overlay-start previous-overlay)
                          beginning))))
    (unless (= ending (point-max))
      (let ((next-overlay (iedit-find-overlay-at-point
                           ending
                           'iedit-occurrence-overlay-name)))
        (if next-overlay ; two conjoined occurrences
            (move-overlay next-overlay ending (overlay-end next-overlay)))))))

(defvar iedit-number-line-counter 1
  "Occurrence number for 'iedit-number-occurrences.")

(defun iedit-default-occurrence-number-format (start-at)
  (concat "%"
          (int-to-string
           (length (int-to-string
                    (1- (+ (length iedit-occurrences-overlays) start-at)))))
          "d "))

(defun iedit-number-occurrences (start-at &optional format-string)
  "Insert numbers in front of the occurrences.
START-AT, if non-nil, should be a number from which to begin
counting.  FORMAT, if non-nil, should be a format string to pass
to `format-string' along with the line count.  When called
interactively with a prefix argument, prompt for START-AT and
FORMAT."
  (interactive
   (if current-prefix-arg
       (let* ((start-at (read-number "Number to count from: " 1)))
         (list start-at
               (read-string "Format string: "
                            (iedit-default-occurrence-number-format
                             start-at))))
     (list  1 nil)))
  (unless format-string
    (setq format-string (iedit-default-occurrence-number-format start-at)))
  (let ((iedit-number-occurrence-counter start-at)
        (inhibit-modification-hooks t))
    (save-excursion
      (dolist (occurrence iedit-occurrences-overlays)
        (goto-char (overlay-start occurrence))
        (insert (format format-string iedit-number-occurrence-counter))
        (iedit-move-conjoined-overlays occurrence)
        (setq iedit-number-occurrence-counter
              (1+ iedit-number-occurrence-counter))))))

(defun iedit-kill-rectangle(&optional fill)
  "Kill the rectangle.
The behavior is the same as `kill-rectangle' in rect mode."
  (interactive "*P")
  (or (and iedit-rectangle (iedit-same-column))
      (error "Not a rectangle"))
  (let ((inhibit-modification-hooks t)
        (beg (overlay-start (car iedit-occurrences-overlays)))
        (end (overlay-end (progn (iedit-last-occurrence)
                                 (iedit-find-current-occurrence-overlay)))))
    (kill-rectangle beg end fill)))

(defun iedit-restrict-function(&optional arg)
  "Restricting Iedit mode in current function."
  (interactive "P")
  (save-excursion
    (mark-defun)
    (iedit-restrict-region (region-beginning) (region-end) arg)))

;;; help functions
(defun iedit-find-current-occurrence-overlay ()
  "Return the current occurrence overlay  at point or point - 1.
This function is supposed to be called in overlay keymap."
  (or (iedit-find-overlay-at-point (point) 'iedit-occurrence-overlay-name)
      (iedit-find-overlay-at-point (1- (point)) 'iedit-occurrence-overlay-name)))

(defun iedit-find-overlay-at-point (point property)
  "Return the overlay with PROPERTY at POINT."
  (let ((overlays (overlays-at point))
        found)
    (while (and overlays (not found))
      (let ((overlay (car overlays)))
        (if (overlay-get overlay property)
            (setq found overlay)
          (setq overlays (cdr overlays)))))
    found))

(defun iedit-same-column ()
  "Return t if all occurrences are at the same column."
  (save-excursion
    (let ((column (progn (goto-char (overlay-start (car iedit-occurrences-overlays)))
                         (current-column)))
          (overlays (cdr  iedit-occurrences-overlays))
          (same t))
      (while (and overlays same)
        (let ((overlay (car overlays)))
          (if (/= (progn (goto-char (overlay-start overlay))
                         (current-column))
                  column)
              (setq same nil)
            (setq overlays (cdr overlays)))))
      same)))

(defun iedit-same-length ()
  "Return t if all occurrences are the same length."
  (save-excursion
    (let ((length (iedit-occurrence-string-length))
          (overlays (cdr iedit-occurrences-overlays))
          (same t))
      (while (and overlays same)
        (let ((ov (car overlays)))
          (if (/= (- (overlay-end ov) (overlay-start ov))
                  length)
              (setq same nil)
            (setq overlays (cdr overlays)))))
      same)))

;; This function might be called out of any occurrence
(defun iedit-current-occurrence-string ()
  "Return current occurrence string.
Return nil if occurrence string is empty string."
  (let* ((ov (or (iedit-find-current-occurrence-overlay)
                 (car iedit-occurrences-overlays)))
         (beg (overlay-start ov))
         (end (overlay-end ov)))
    (if (and ov (/=  beg end))
        (buffer-substring-no-properties beg end)
      nil)))

(defun iedit-occurrence-string-length ()
  "Return the length of current occurrence string."
  (let ((ov (car iedit-occurrences-overlays)))
    (- (overlay-end ov) (overlay-start ov))))

(defun iedit-find-overlay (beg end property &optional exclusive)
  "Return a overlay with property in region, or out of the region if EXCLUSIVE is not nil."
  (if exclusive
      (or (iedit-find-overlay-in-region (point-min) beg property)
          (iedit-find-overlay-in-region end (point-max) property))
    (iedit-find-overlay-in-region beg end property)))

(defun iedit-find-overlay-in-region (beg end property)
  "Return a overlay with property in region."
  (let ((overlays (overlays-in beg end))
        found)
    (while (and overlays (not found))
      (let ((overlay (car overlays)))
        (if (and (overlay-get overlay property)
                 (>= (overlay-start overlay) beg)
                 (<= (overlay-end overlay) end))
            (setq found overlay)
          (setq overlays (cdr overlays)))))
    found))

(defun iedit-restrict-region (beg end &optional inclusive)
  "Restricting Iedit mode in a region."
  (when iedit-buffering
    (iedit-stop-buffering))
  (setq iedit-last-occurrence-local (iedit-current-occurrence-string))
  (set-mark nil)
  (iedit-show-all)
  (iedit-cleanup-occurrences-overlays beg end inclusive)
  (setq iedit-rectangle nil)
  (if iedit-unmatched-lines-invisible
      (iedit-hide-unmatched-lines iedit-occurrence-context-lines))
  (setq iedit-mode (propertize
                    (concat " Iedit:" (number-to-string
                                       (length iedit-occurrences-overlays)))
                    'face 'font-lock-warning-face))
  (force-mode-line-update))

(defun iedit-cleanup-occurrences-overlays (beg end &optional inclusive)
  "Remove deleted overlays from list `iedit-occurrences-overlays'."
  (if inclusive
      (remove-overlays beg end iedit-occurrence-overlay-name t)
    (remove-overlays (point-min) beg iedit-occurrence-overlay-name t)
    (remove-overlays end (point-max) iedit-occurrence-overlay-name t))
  (let (overlays)
    (dolist (overlay iedit-occurrences-overlays)
      (if (overlay-buffer overlay)
          (push overlay overlays)))
    (setq iedit-occurrences-overlays (nreverse overlays))))

(defun iedit-printable (string)
  "Return a omitted substring that is not longer than 50.
STRING is already `regexp-quote'ed"
  (let ((first-newline-index (string-match "$" string))
        (length (length string)))
    (if (and first-newline-index
             (/= first-newline-index length))
        (if (< first-newline-index 50)
            (concat (substring string 0 first-newline-index) "...")
          (concat (substring string 0 50) "..."))
      (if (> length 50)
          (concat (substring string 0 50) "...")
        string))))

(defun iedit-region-active ()
  "Return t if region is active and not empty.
If variable `iedit-transient-mark-sensitive' is t, active region
means `transient-mark-mode' is on and mark is active. Otherwise,
it just means mark is active."
  (and (if iedit-transient-mark-sensitive
           transient-mark-mode
         t)
       mark-active (not (equal (mark) (point)))))

(provide 'iedit)

;;; iedit.el ends here

;;  LocalWords:  iedit el MERCHANTABILITY kbd isearch todo ert Lindberg Tassilo
;;  LocalWords:  eval rect defgroup defcustom boolean defvar assq alist nconc
;;  LocalWords:  substring cadr keymap defconst purecopy bkm defun princ prev
;;  LocalWords:  iso lefttab backtab upcase downcase concat setq autoload arg
;;  LocalWords:  refactoring propertize cond goto nreverse progn rotatef eq elp
;;  LocalWords:  dolist pos unmatch args ov sReplace iedit's cdr quote'ed
