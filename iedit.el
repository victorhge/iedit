;;; iedit.el --- Edit multiple regions in one buffer simultaneously.

;; Copyright (C) 2010, 2011, 2012 Victor Ren

;; Time-stamp: <2012-02-19 00:36:34 Victor Ren>
;; Author: Victor Ren <victorhge@gmail.com>
;; Keywords: occurrence region replace simultaneous
;; Version: 0.94
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

;; This package provides a more intuitive way of replace-string operation.
;; Normal scenario of iedit-mode is like:

;; - Start iedit minor mode - by press C-;
;;   The target contents (all occurrences of a symbol, string or a rectangle) in
;;   the buffer are highlighted.  The content varies corresponding to mark,
;;   point and prefix. Refer to the comments of `iedit-mode'.
;;
;; - Edit one of the contents
;;   The change is applied to other contents simultaneously
;;
;; - Finish - by pressing C-; again

;; If you would like to operate on certain region, use "narrowing" first.

;; With several lines of additional code, the package also provides rectangle
;; support with visible rectangle highlighting, which is simular with `cua-rect'.

;;; Suggested key bindings:
;;
;; (define-key global-map (kbd "C-;") 'iedit-mode)
;; (define-key isearch-mode-map (kbd "C-;") 'iedit-mode)

;;; todo:
;; - profile to find bottleneck for huge file
;; - Add more easy access keys for whole occurrence
;; - C-n,C-p is slow when unmatched lines are hided.
;; - toggle blank line between matched lines?
;; - ert unit test
;; - update documents for rectangle support

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
  "Edit multiple regions with the same content simultaneously."
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
  "If no-nil, matching is case sensitive"
  :type 'boolean
  :group 'iedit)

(defcustom iedit-only-at-symbol-boundaries t
  "If no-nil, matches have to start and end at symbol boundaries.
  For example, when invoking iedit-mode on the \"in\" in the
  sentence \"The king in the castle...\", the \"king\" is not
  edited."
  :type 'boolean
  :group 'iedit)

(defcustom iedit-unmatched-lines-invisible-default nil
  "If no-nil, hide lines that do not cover any occurrences by
default."
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

(defvar iedit-occurrences-overlays nil
  "The occurrences slot contains a list of overlays used to
indicate the position of each occurrence.  In addition, the
occurrence overlay is used to provide a different face
configurable via `iedit-occurrence-face'.")

(defvar iedit-case-sensitive iedit-case-sensitive-default
  "This is buffer local variable. If no-nil, matching is case
  sensitive.")

(defvar iedit-unmatched-lines-invisible nil
  "This is buffer local variable which indicates whether
unmatched lines are hided.")

(defvar iedit-last-occurrence-in-history nil
  "This is buffer local variable which is the occurrence when
iedit mode is turned off last time.")

(defvar iedit-occurrence-is-complete-symbol nil
  "This is buffer local variable which indicates the occurrence
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
(defvar iedit-skipped-modification-once nil
  "Variable used to skip first modification hook run when insertion against a zero-width occurrence.")

(defvar iedit-aborting nil
  "This is buffer local variable which indicates iedit-mode is aborting.")

(defvar iedit-buffering nil
  "This is buffer local variable which indicates iedit-mode is
buffering, which means the modification to the current
occurrence is not applied to other occurrences when it is true.")

(defvar iedit-rectangle nil
  "This buffer local variable which is the rectangle geometry if
 current mode is iedit-rect. Otherwise it is nil.
(car iedit-rectangle) is the top-left corner and
(cadr iedit-rectangle) is the bottom-right corner" )

(defvar iedit-current-keymap)

(defvar iedit-occurrence-context-lines 0
  "The number of lines before or after the occurrence.")

(make-variable-buffer-local 'iedit-occurrences-overlays)
(make-variable-buffer-local 'iedit-unmatched-lines-invisible)
(make-variable-buffer-local 'iedit-case-sensitive)
(make-variable-buffer-local 'iedit-last-occurrence-in-history)
(make-variable-buffer-local 'iedit-forward-success)
(make-variable-buffer-local 'iedit-before-modification-string)
(make-variable-buffer-local 'iedit-before-modification-undo-list)
(make-variable-buffer-local 'iedit-skipped-modification-once)
(make-variable-buffer-local 'iedit-aborting)
(make-variable-buffer-local 'iedit-buffering)
(make-variable-buffer-local 'iedit-rectangle)
(make-variable-buffer-local 'iedit-current-keymap)
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
  "Keymap for characters following the Help key for iedit mode.")

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
  (let (same-window-buffer-names same-window-regexps)
    (with-help-window "*Help*"
      (with-current-buffer standard-output
        (princ "Iedit Mode Bindings: ")
        (princ (substitute-command-keys "\\{iedit-current-keymap}"))))))

(defun iedit-describe-key ()
  "Display documentation of the function invoked by iedit key."
  (interactive)
  (let (same-window-buffer-names same-window-regexps)
    (call-interactively 'describe-key)))

(defun iedit-describe-mode ()
  "Display documentation of iedit mode."
  (interactive)
  (let (same-window-buffer-names same-window-regexps)
    (describe-function 'iedit-mode)))

;;; Define iedit mode map
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
  "Keymap used while iedit mode is enabled.")

(defvar iedit-occurrence-local-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map iedit-mode-map)
    (define-key map (kbd "M-u") 'iedit-upcase-occurrences)
    (define-key map (kbd "M-l") 'iedit-downcase-occurrences)
    (define-key map (kbd "M-r") 'iedit-replace-occurrences)
    (define-key map (kbd "M-C") 'iedit-clear-occurrences)
    (define-key map (kbd "M-c") 'iedit-toggle-case-sensitive)
    (define-key map (kbd "M-D") 'iedit-delete-occurrences)
    (define-key map (kbd "M-N") 'iedit-number-occurrences)
    (define-key map [C-return] 'iedit-toggle-buffering)
    (define-key map (kbd "C-?") 'iedit-help-for-occurrences)
    map)
  "Keymap used within overlays in iedit mode.")

(defvar iedit-rect-local-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map iedit-occurrence-local-map)
    (define-key map (kbd "M-k") 'iedit-kill-rectangle)
    map)
  "Keymap used within overlays in iedit-RECT mode.")

(defun iedit-help-for-occurrences ()
  "Display `iedit-occurrence-local-map' or `iedit-rect-local-map'."
  (interactive)
  (message (concat "M-u/l:up/downcase M-r:replace M-C:clear M-D:delete M-n:number C-return:buffering"
                   (if iedit-rectangle
                       " M-k:kill"))))

(defun iedit-get-symbols-in-region (beg end)
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (loop while (re-search-forward "\\_<\\(.*?\\)\\_>" nil t)
            collect (match-string-no-properties 1)))))

(or (assq 'iedit-mode minor-mode-map-alist)
    (setq minor-mode-map-alist
          (cons (cons 'iedit-mode iedit-mode-map) minor-mode-map-alist)))

;;;###autoload
(defun iedit-mode (&optional arg)
  "Toggle iedit mode.
If iedit mode is off, turn iedit mode on, off otherwise.

In Transient Mark mode, when iedit mode is turned on, all the
occurrences of the current region are highlighted.  If one
occurrence is modified, the change are propagated to all other
occurrences simultaneously.

If Transient Mark mode is disabled or the region is not active,
the current symbol (returns from `current-word') is used as the
occurrence by default.  The occurrences of the current
symbol, but not include occurrences that are part of other
symbols, are highlighted.  This is good for renaming refactoring
during programming.  If you still want to match all the
occurrences, even though they are parts of other symbols, you may
have to select the symbol first.

You can also switch to iedit mode from isearch mode directly. The
current search string is used as occurrence.  All occurrences of
the current search string are highlighted.

With a universal prefix argument and no active region, the
occurrence when iedit is turned off last time is used as
occurrence.  This is intended to recover last iedit which is
turned off by mistake.

With a universal prefix argument and region active, interactively
edit region as a string rectangle.

With universal prefix specified twice, e.g. C-u C-u, then you can
choose to edit complete symbols within the region.  This is
useful for code refactoring.

Commands:
\\{iedit-current-keymap}"
  (interactive "P")
  (if iedit-mode
      (iedit-done)
    (let (occurrence complete-symbol rect-string restrict-beg restrict-end)
      (cond ((and (equal arg '(4))
                  (or (not transient-mark-mode) (not mark-active)
                      (equal (mark) (point)))
                  iedit-last-occurrence-in-history)
             (setq occurrence iedit-last-occurrence-in-history)
             (setq complete-symbol iedit-occurrence-is-complete-symbol))
            ((and (equal arg '(4))
                  transient-mark-mode mark-active (not (equal (mark) (point))))
             (setq rect-string t))
            ((and (equal arg '(16))
                  transient-mark-mode mark-active (not (equal (mark) (point))))
             (setq occurrence (regexp-quote
                               (completing-read
                                "Symbol: "
                                (iedit-get-symbols-in-region (region-beginning) (region-end))
                                nil
                                nil
                                nil
                                'iedit-read-symbol-hist))
                   restrict-beg (region-beginning)
                   restrict-end (region-end)
                   complete-symbol t))
            ((and transient-mark-mode mark-active (not (equal (mark) (point))))
             (setq occurrence (regexp-quote (buffer-substring-no-properties
                                             (mark) (point)))))
            ((and isearch-mode (not (string= isearch-string "")))
             (setq occurrence (regexp-quote (buffer-substring-no-properties
                                             (point) isearch-other-end)))
             (isearch-exit))
            ((and iedit-current-symbol-default (current-word t))
             (setq occurrence (regexp-quote (current-word)))
             (when iedit-only-at-symbol-boundaries
               (setq complete-symbol t)))
            (t (error "No candidate of the occurrence, cannot enable iedit mode.")))
      (setq iedit-occurrence-is-complete-symbol complete-symbol)
      (if rect-string
          (let ((beg (region-beginning))
                (end (region-end)))
            (deactivate-mark)
            (iedit-rectangle-start beg end))
        (deactivate-mark)
        (setq iedit-case-sensitive iedit-case-sensitive-default)
        (if (and restrict-beg restrict-end)
            (save-restriction
              (narrow-to-region restrict-beg restrict-end)
              (iedit-start occurrence)
              (goto-char (point-min))
              (iedit-next-occurrence))
          (iedit-start occurrence))))))

(defun iedit-start (occurrence-exp)
  "Start an iedit for the occurrence-exp in the current buffer."
  (setq iedit-unmatched-lines-invisible iedit-unmatched-lines-invisible-default)
  (setq iedit-aborting nil)
  (setq iedit-rectangle nil)
  (setq iedit-current-keymap iedit-occurrence-local-map)
  (iedit-refresh occurrence-exp)
  (run-hooks 'iedit-mode-hook)
  ;; (add-hook 'mouse-leave-buffer-hook 'iedit-done)
  (add-hook 'kbd-macro-termination-hook 'iedit-done))

(defun iedit-refresh (occurrence-exp)
  "Refresh iedit-mode."
  (setq iedit-occurrences-overlays nil)
  (when iedit-occurrence-is-complete-symbol
    (setq occurrence-exp (concat "\\_<" occurrence-exp "\\_>")))
  ;; Find and record each occurrence's markers and add the overlay to the occurrences
  (let ((counter 0)
        (case-fold-search (not iedit-case-sensitive)))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward occurrence-exp nil t)
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
                                   'face 'font-lock-warning-face))))
  (force-mode-line-update))

(defun iedit-rectangle-start (beg end)
  "Start an iedit for the region as a rectangle."
  (barf-if-buffer-read-only)
  (setq iedit-mode (propertize " Iedit-RECT" 'face 'font-lock-warning-face))
  (setq iedit-occurrences-overlays nil)
  (setq iedit-rectangle (list beg end))
  (setq iedit-current-keymap iedit-rect-local-map)
  (force-mode-line-update)
  (run-hooks 'iedit-mode-hook)
  (add-hook 'kbd-macro-termination-hook 'iedit-done)
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
      (setq iedit-occurrences-overlays (nreverse iedit-occurrences-overlays)))))

(defun iedit-done ()
  "Exit iedit mode."
  (if iedit-buffering
      (iedit-stop-buffering))
  (setq iedit-last-occurrence-in-history (iedit-current-occurrence-string))
  (remove-overlays (point-min) (point-max) iedit-occurrence-overlay-name t)
  (iedit-show-all)
  (setq iedit-occurrences-overlays nil)
  (setq iedit-aborting nil)
  (setq iedit-before-modification-string "")
  (setq iedit-before-modification-undo-list nil)
  (setq iedit-mode nil)
  (force-mode-line-update)
  (remove-hook 'kbd-macro-termination-hook 'iedit-done)
  (run-hooks 'iedit-mode-end-hook))

(defun iedit-make-occurrence-overlay (begin end)
  "Create an overlay for an occurrence in iedit mode.
Add the properties for the overlay: a face used to display a
occurrence's default value, and modification hooks to update
occurrences if the user starts typing."
  (let ((occurrence (make-overlay begin end (current-buffer) nil t)))
    (overlay-put occurrence iedit-occurrence-overlay-name t)
    (overlay-put occurrence 'face iedit-occurrence-face)
    (overlay-put occurrence 'local-map iedit-current-keymap)
    (overlay-put occurrence 'insert-in-front-hooks '(iedit-occurrence-update))
    (overlay-put occurrence 'insert-behind-hooks '(iedit-occurrence-update))
    (overlay-put occurrence 'modification-hooks '(iedit-occurrence-update))
    occurrence))

(defun iedit-make-unmatched-lines-overlay (begin end)
  "Create an overlay for lines between two occurrences in iedit mode."
  (let ((unmatched-lines-overlay (make-overlay begin end (current-buffer) nil t)))
    (overlay-put unmatched-lines-overlay iedit-invisible-overlay-name t)
    (overlay-put unmatched-lines-overlay 'invisible 'iedit-invisible-overlay-name)
;;    (overlay-put unmatched-lines-overlay 'intangible t)
    unmatched-lines-overlay))

(defun iedit-reset-aborting ()
  "Turning iedit-mode off and reset iedit-aborting.

This is added to `post-command-hook when aborting iedit-mode is
decided. `iedit-done' is postponed after the current command is
executed for avoiding iedit-occurrence-update is called for a
removed overlay."
  (iedit-done)
  (remove-hook 'post-command-hook 'iedit-reset-aborting t)
  (setq iedit-aborting nil))

(defun iedit-occurrence-update (occurrence after beg end &optional change)
  "Update all occurrences.
This modification hook is triggered when a user edits any
occurrence and is responsible for updating all other occurrences.
Current supported edits are insertion, yank, deletion and
replacement.  If this modification is going out of the
occurrence, it will exit iedit mode."
  (when (and (not iedit-aborting )
             (not undo-in-progress)) ; undo will do all the update
    ;; before modification
    (if (null after)
        (if (or (< beg (overlay-start occurrence))
                (> end (overlay-end occurrence)))
            (progn (setq iedit-aborting t) ; abort iedit-mode
                   (add-hook 'post-command-hook 'iedit-reset-aborting nil t))
          (setq iedit-before-modification-string
                (buffer-substring-no-properties beg end)))
      ;; after modification
      (when (not iedit-buffering)
        ;; Check if we are inserting into zero-width occurrence.  If so, then
        ;; TWO modification hooks will be called -- "insert-in-front-hooks" and
        ;; "insert-behind-hooks".  We need to run just once.
        (if (and (= beg (overlay-start occurrence))
                 (= end (overlay-end occurrence))
                 (= change 0)
                 (not iedit-skipped-modification-once))
            (setq iedit-skipped-modification-once t)
          (setq iedit-skipped-modification-once nil)
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
                    (dolist (another-occurrence (remove occurrence iedit-occurrences-overlays))
                      (progn
                        (goto-char (+ (overlay-start another-occurrence) offset))
                        (insert-and-inherit value)))
                  ;; deletion
                  (dolist (another-occurrence (remove occurrence iedit-occurrences-overlays))
                    (let* ((beginning (+ (overlay-start another-occurrence) offset))
                           (ending (+ beginning change)))
                      (delete-region beginning ending)
                      (unless (eq beg end) ;; replacement
                        (goto-char beginning)
                        (insert-and-inherit value)))))))))))))
;; (elp-instrument-list '(insert-and-inherit delete-region goto-char iedit-occurrence-update buffer-substring-no-properties string= re-search-forward replace-match))

(defun iedit-next-occurrence ()
  "Move forward to the next occurrence in the `iedit'.
If the point is already in the last occurrences, you are asked to type
another `iedit-next-occurrence', it starts again from the
beginning of the buffer."
  (interactive)
  (let ((pos (point))
        (in-occurrence (get-char-property (point) 'iedit-occurrence-overlay-name)))
    (when in-occurrence
      (setq pos  (next-single-char-property-change pos 'iedit-occurrence-overlay-name)))
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

(defun iedit-toggle-unmatched-lines-visible (&optional arg)
  "Toggle whether to display unmatched lines.
A prefix ARG specifies how many lines before and after the
occurrences are not hided; negative is treated the same as zero.

If no prefix argument, the prefix argument last time or default
value of `iedit-occurrence-context-lines' is used for this time."
  (interactive "P")
  (if (null arg)
      (progn (setq iedit-unmatched-lines-invisible (not iedit-unmatched-lines-invisible))
             (if iedit-unmatched-lines-invisible
                  (iedit-hide-unmatched-lines iedit-occurrence-context-lines)
               (iedit-show-all)))
    (setq arg (prefix-numeric-value arg))
    (if (< arg 0)
        (setq arg 0))
    (unless (and iedit-unmatched-lines-invisible
                 (= arg iedit-occurrence-context-lines))
      (when iedit-unmatched-lines-invisible
        (remove-overlays (point-min) (point-max) iedit-invisible-overlay-name t))
      (setq iedit-occurrence-context-lines arg)
      (setq iedit-unmatched-lines-invisible t)
      (iedit-hide-unmatched-lines iedit-occurrence-context-lines))))

(defun iedit-show-all()
  "Show hided lines."
  (setq line-move-ignore-invisible nil)
  (remove-overlays (point-min) (point-max) iedit-invisible-overlay-name t)
  (remove-from-invisibility-spec '(iedit-invisible-overlay-name . t)))

(defun iedit-hide-unmatched-lines (context-lines)
  "Hide unmatched lines using invisible overlay."
  (let ((prev-occurrence-end 0)
        (unmatched-lines nil))
    (save-excursion
      (dolist (overlay iedit-occurrences-overlays)
        (goto-char (overlay-start overlay))
        (forward-line (- context-lines))
        (let ((line-beginning (line-beginning-position)))
          (if (> line-beginning (1+ prev-occurrence-end))
              (push  (list (1+ prev-occurrence-end) (1- line-beginning)) unmatched-lines)))
        (goto-char (overlay-end overlay))
        (forward-line context-lines)
        (setq prev-occurrence-end (line-end-position)))
      (if (< prev-occurrence-end (point-max))
          (push (list (1+ prev-occurrence-end) (point-max)) unmatched-lines))
      (when unmatched-lines
        (set (make-local-variable 'line-move-ignore-invisible) t)
        (add-to-invisibility-spec '(iedit-invisible-overlay-name . t))
        (dolist (unmatch unmatched-lines)
          (iedit-make-unmatched-lines-overlay (car unmatch) (cadr unmatch)))))))

;;;; functions for overlay local-map
(defun iedit-apply-on-occurrences (function &rest args)
  "Call function for each occurrence."
  (let* ((ov (car iedit-occurrences-overlays))
         (beg (overlay-start ov))
         (end (overlay-end ov)))
    (when (/= beg end)
      (let ((inhibit-modification-hooks t))
        (save-excursion
          (dolist (occurrence  iedit-occurrences-overlays)
            (apply function (overlay-start occurrence) (overlay-end occurrence) args)))))))

(defun iedit-upcase-occurrences ()
  "Covert occurrences to upper case."
  (interactive "*")
  (iedit-apply-on-occurrences 'upcase-region))

(defun iedit-downcase-occurrences()
  "Covert occurrences to lower case."
  (interactive "*")
  (iedit-apply-on-occurrences 'downcase-region))

(defun iedit-replace-occurrences(string)
  "Replace occurrences with STRING."
  (interactive "*sReplace with: ")
  (let* ((ov (iedit-find-current-occurrence-overlay))
         (offset (- (point) (overlay-start ov))))
    (iedit-apply-on-occurrences
     (lambda (beg end string)
         (delete-region beg end)
         (goto-char beg)
         (insert-and-inherit string))
     string)
    (goto-char (+ (overlay-start ov) offset))))

(defun iedit-clear-occurrences()
  "Replace occurrences with blank spaces."
  (interactive "*")
  (let* ((ov (car iedit-occurrences-overlays))
         (count (- (overlay-end ov) (overlay-start ov))))
  (iedit-replace-occurrences (make-string count 32))))

(defun iedit-delete-occurrences()
  "Delete occurrences."
  (interactive "*")
  (iedit-apply-on-occurrences 'delete-region))

(defun iedit-toggle-case-sensitive ()
  "Toggle case-sensitive matching occurrences."
  (interactive)
  (if iedit-buffering
      (iedit-stop-buffering))
  (setq iedit-last-occurrence-in-history (iedit-current-occurrence-string))
  (remove-overlays (point-min) (point-max) iedit-occurrence-overlay-name t)
  (iedit-show-all)
  (setq iedit-occurrences-overlays nil)
  (setq iedit-case-sensitive (not iedit-case-sensitive))
  (if iedit-last-occurrence-in-history
      (iedit-refresh iedit-last-occurrence-in-history)))

(defun iedit-toggle-buffering ()
  "Toggle buffering.
This is intended to improve iedit's response time. If the number
of occurrences are huge, iedit might be slow to update all the
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
  (setq iedit-mode (propertize " Iedit-B" 'face 'font-lock-warning-face))
  (force-mode-line-update))

(defun iedit-stop-buffering ()
  "Stop buffering and apply the modification to other occurrences.
If current point is not at any occurrence, the buffered
modification is not going to be applied to other occurrences."
  (let ((ov (iedit-find-current-occurrence-overlay)))
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
                  (insert-and-inherit modified-string)))))
          (goto-char (+ (overlay-start ov) offset))))))
  (setq iedit-buffering nil)
  (setq iedit-mode (propertize
                    (concat " Iedit:" (number-to-string (length iedit-occurrences-overlays)))
                    'face 'font-lock-warning-face))
  (force-mode-line-update)
  (setq iedit-before-modification-undo-list nil))

(defvar iedit-number-line-counter 1
  "Occurrence number for 'iedit-number-occurrences")

(defun iedit-default-line-number-format (start-at)
  (concat "%"
          (int-to-string
           (length (int-to-string
                    (1- (+ (length iedit-occurrences-overlays) start-at)))))
	  "d "))

(defun iedit-number-occurrences (start-at &optional format)
  "Insert numbers in front of the occurrences.
START-AT, if non-nil, should be a number from which to begin
counting.  FORMAT, if non-nil, should be a format string to pass
to `format' along with the line count.  When called interactively
with a prefix argument, prompt for START-AT and FORMAT."
  (interactive
   (if current-prefix-arg
       (let* ((start-at (read-number "Number to count from: " 1)))
         (list start-at
               (read-string "Format string: "
                            (iedit-default-line-number-format
                             start-at))))
     (list  1 nil)))
  (unless format
    (setq format (iedit-default-line-number-format start-at)))
  (let ((iedit-number-line-counter start-at))
    (iedit-apply-on-occurrences
     (lambda (beg _end format-string)
       (goto-char beg)
       (insert (format format-string iedit-number-line-counter))
       (setq iedit-number-line-counter
             (1+ iedit-number-line-counter))) format)))

(defun iedit-kill-rectangle(&optional fill)
  "Kill the rectangle.
The behavior is the same as `kill-rectangle' in rect mode."
  (interactive "*P")
  (let ((inhibit-modification-hooks t))
    (kill-rectangle (car iedit-rectangle)
                    (cadr iedit-rectangle)
                    fill)))

;;; help functions
(defun iedit-find-current-occurrence-overlay ()
  "Return the current occurrence overlay  at point or point - 1.
This function is supposed to be called in overlay local-map."
  (or (iedit-find-overlay (point) 'iedit-occurrence-overlay-name)
      (iedit-find-overlay (1- (point)) 'iedit-occurrence-overlay-name)))

(defun iedit-find-overlay (point property)
  "Return the overlay with PROPERTY at POINT."
  (let ((overlays (overlays-at point))
        found)
    (while (and overlays (not found))
      (let ((overlay (car overlays)))
        (if (overlay-get overlay property)
            (setq found overlay)
          (setq overlays (cdr overlays)))))
    found))

(defun iedit-current-occurrence-string ()
  "Return occurrence string."
  (let* ((ov (car iedit-occurrences-overlays))
         (beg (overlay-start ov))
         (end (overlay-end ov)))
    (if (and ov (/=  beg end))
        (regexp-quote (buffer-substring-no-properties beg end))
      nil)))

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

(provide 'iedit)

;;; iedit.el ends here
