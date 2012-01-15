;;; iedit.el --- Edit multiple regions with the same content simultaneously.

;; Copyright (C) 2010, 2011 Victor Ren

;; Time-stamp: <2012-01-14 23:12:48 Victor Ren>
;; Author: Victor Ren <victorhge@gmail.com>
;; Keywords: occurrence region replace simultaneous
;; Version: 0.90
;; X-URL: http://www.emacswiki.org/emacs/iedit.el
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

;; This package provides a more intuitive way of replace-string operation:
;;
;; - Select the occurrence in the buffer
;;   In Transient Mark mode, just mark a region, the content of the 
;;   region will be used as the occurrence. (if Transient Mark mode is disabled,
;;   using C-u C-x C-x or C-SPC C-SPC to activate it just for this one time).
;;
;; - Start iedit minor mode - by press C-;
;;   All occurrences of the content in the buffer are highlighted
;;
;; - Edit one of the contents
;;   The change is applied to other contents simultaneously
;;
;; - Finish - by pressing C-; again

;; If Transient Mark mode is disabled or the region is not active,
;; the `current-word' is used as the occurrence by default.

;; You can also switch to iedit mode from isearch mode directly. The current
;; search string is used as the occurrence.

;; If you would like to replace-string on certain region, use "narrowing" first.

;;; Suggested key bindings:
;;
;; (define-key global-map (kbd "C-;") 'iedit-mode)
;; (define-key isearch-mode-map (kbd "C-;") 'iedit-mode)

;;; todo:
;; - C-n,C-p is slow when unmachted lines are hided.
;; - Lazy highlight feature (from isearch)?
;; - toggle blank line between matched lines?
;; - ert unit test
;; - profile to find bottleneck for huge file

;;; Contributors
;; Adam Lindberg <eproxus@gmail.com> added a case sensitivity option that can be toggled.

;;; Code:

(eval-when-compile (require 'cl))

(defgroup iedit nil
  "Edit multiple regions with the same content simultaneously."
  :prefix "iedit-"
  :group 'replace
  :group 'convenience)

(defcustom iedit-occurrence-face 'highlight
  "*Face used for the occurrences' default values."
  :type 'face
  :group 'iedit)

(defcustom iedit-current-word-default 't
  "If no-nil, use current word by default for the occurrence."
  :type 'boolean
  :group 'iedit)

(defcustom iedit-case-sensitive-default 't
  "If no-nil, matching is case sensitive"
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

(defvar iedit-case-sensitive nil
  "This is buffer local variable. If no-nil, matching is case
  sensitive.")

(defvar iedit-unmatched-lines-invisible nil
  "This is buffer local variable which indicates whether
unmatched lines are hided.")

(defvar iedit-last-occurrence-in-history nil
  "This is buffer local variable which is the occurrence when
iedit mode is turned off last time.")

(defvar iedit-forward-success t
  "This is buffer local variable which indicate the moving
forward or backward successful")

(make-variable-buffer-local 'iedit-occurrences-overlays)
(make-variable-buffer-local 'iedit-unmatched-lines-invisible)
(make-variable-buffer-local 'iedit-case-sensitive)
(make-variable-buffer-local 'iedit-last-occurrence-in-history)
(make-variable-buffer-local 'iedit-forward-success)

(defconst iedit-occurrence-overlay-name 'iedit-occurrence-overlay-name)
(defconst iedit-invisible-overlay-name 'iedit-invisible-overlay-name)

;;; Define iedit help map.
(eval-when-compile (require 'help-macro))

(defvar iedit-help-map
  (let ((map (make-sparse-keymap)))
;;    (define-key map [t] 'iedit-other-control-char)
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

(make-help-screen iedit-help-for-help-internal
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
	(princ "Iedit Mode Bindings:\n")
	(princ (substitute-command-keys "\\{iedit-mode-map}"))))))

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
(defvar iedit-mode-map nil
  "Keymap used while iedit mode is enabled.")

(if iedit-mode-map
    nil
  (setq iedit-mode-map (make-sparse-keymap))
  ;; Default key bindings
  (define-key iedit-mode-map (kbd "TAB") 'iedit-next-occurrence)
  (define-key iedit-mode-map (kbd "<S-tab>") 'iedit-prev-occurrence)
  (define-key iedit-mode-map (kbd "<S-iso-lefttab>") 'iedit-prev-occurrence)
  (define-key iedit-mode-map (kbd "<backtab>") 'iedit-prev-occurrence)
  (define-key iedit-mode-map (kbd "C-'") 'iedit-toggle-unmatched-lines-visible)
  (define-key iedit-mode-map (char-to-string help-char) iedit-help-map)
  (define-key iedit-mode-map [help] iedit-help-map)
  (define-key iedit-mode-map [f1] iedit-help-map))

(or (assq 'iedit-mode minor-mode-map-alist)
    (setq minor-mode-map-alist
          (cons (cons 'iedit-mode iedit-mode-map) minor-mode-map-alist)))

;;;###autoload
(defun iedit-mode (&optional arg)
  "Toggle iedit mode.
If iedit mode is off, turn iedit mode on, off otherwise.

In Transient Mark mode, when iedit mode is turned on, all the
occurrences of the current region are highlighted. If one
occurrence is modified, the change are propagated to all other
occurrences simultaneously.

If Transient Mark mode is disabled or the region is not active,
the `current-word' is used as occurrence. All the occurrences of
the `current-word' are highlighted.

You can also switch to iedit mode from isearch mode directly. The
current search string is used as occurrence.  All occurrences of
the current search string are highlighted.

With a prefix argument, the occurrence when iedit is turned off
last time is used as occurrence.  This is intended to recover
last iedit which is turned off by mistake.

Commands:
\\{iedit-mode-map}"
  (interactive "P")
  (if iedit-mode
      (iedit-done)
    (let (occurrence
          occurrence-is-regexp-p)
      (cond ((and arg iedit-last-occurrence-in-history)
             (setq occurrence iedit-last-occurrence-in-history))
            ((and transient-mark-mode mark-active (not (equal (mark) (point))))
             (setq occurrence (buffer-substring-no-properties (mark) (point))))
            ((and isearch-mode (not (string= isearch-string "")))
             (setq occurrence (buffer-substring-no-properties (point) isearch-other-end))
             (isearch-exit))
            ((and iedit-current-word-default (current-word t))
             (setq occurrence (regexp-quote (current-word))
                   occurrence-is-regexp-p t))
            (t (error "No candidate of the occurrence, cannot enable iedit mode.")))
      (deactivate-mark)
      (iedit-start (if occurrence-is-regexp-p
                       occurrence
                     (regexp-quote occurrence))))))

(defun iedit-start (occurrence-exp)
  "Start an iedit for the occurrence-exp in the current buffer."
  (setq	iedit-mode " Iedit")
  (setq iedit-occurrences-overlays nil)
  (setq iedit-unmatched-lines-invisible iedit-unmatched-lines-invisible-default)
  (setq iedit-case-sensitive iedit-case-sensitive-default)
  (force-mode-line-update)
  (run-hooks 'iedit-mode-hook)
  ;; (add-hook 'mouse-leave-buffer-hook 'iedit-done)
  (add-hook 'kbd-macro-termination-hook 'iedit-done)
  ;; Find and record each occurrence's markers and add the overlay to the occurrences
  (let ((counter 0)
        (case-fold-search (not iedit-case-sensitive)))
  (save-excursion
    (goto-char (point-min))
      (while (search-forward-regexp occurrence-exp nil t)
      (push (iedit-make-occurrence-overlay (match-beginning 0) (match-end 0))
            iedit-occurrences-overlays)
      (setq counter (1+ counter)))      ; at less 1
      (setq iedit-occurrences-overlays (nreverse iedit-occurrences-overlays))
      (if iedit-unmatched-lines-invisible
          (iedit-hide-unmatched-lines))
      (message "%d matches for \"%s\"" 
               counter 
               (if (> (length occurrence-exp) 50)
                   (concat (substring occurrence-exp 0 50) "...")
                 occurrence-exp)))))

(defun iedit-hide-unmatched-lines ()
  "Hide unmatched lines using invisible overlay."
  (let ((prev-occurrence-end 0)
        (unmatched-lines nil))
    (save-excursion
      (dolist (overlay iedit-occurrences-overlays)
        (let ((match-start (overlay-start overlay))
              (match-end (overlay-end overlay)))
          (goto-char match-start)
          (if (> (line-beginning-position) (1+ prev-occurrence-end))
              (let ((unmatch-start (1+ prev-occurrence-end))
                    (unmatch-end (1- (line-beginning-position))))
                (push  (list unmatch-start unmatch-end) unmatched-lines)))
          (goto-char match-end)
          (setq prev-occurrence-end (line-end-position))))
      (if (< prev-occurrence-end (point-max))
          (push (list (1+ prev-occurrence-end) (point-max)) unmatched-lines))
      (when unmatched-lines
        (dolist (unmatch unmatched-lines)
          (iedit-make-unmatched-lines-overlay (car unmatch) (cadr unmatch)))))))

(defun iedit-done ()
  "Exit iedit mode."
  (let ((ov (car iedit-occurrences-overlays)))
    (if ov 
        (setq iedit-last-occurrence-in-history 
              (buffer-substring (overlay-start ov) (overlay-end ov)))))
  (remove-overlays (point-min) (point-max) iedit-occurrence-overlay-name t)
  (remove-overlays (point-min) (point-max) iedit-invisible-overlay-name t)
  (setq iedit-occurrences-overlays nil)
  ;; (remove-hook 'mouse-leave-buffer-hook 'iedit-done)
  (remove-hook 'kbd-macro-termination-hook 'iedit-done)
  (setq iedit-mode nil)
  (force-mode-line-update)
  (run-hooks 'iedit-mode-end-hook))

(defun iedit-make-occurrence-overlay (begin end)
  "Create an overlay for an occurrence in iedit mode.
Add the properties for the overlay: a face used to display a
occurrence's default value, and modification hooks to update
occurrences if the user starts typing."
  (let ((occurrence (make-overlay begin end (current-buffer) nil t)))
    (overlay-put occurrence iedit-occurrence-overlay-name t)
    (overlay-put occurrence 'face iedit-occurrence-face)
    (overlay-put occurrence 'insert-in-front-hooks '(iedit-occurrence-update))
    (overlay-put occurrence 'insert-behind-hooks '(iedit-occurrence-update))
    (overlay-put occurrence 'modification-hooks '(iedit-occurrence-update))
    occurrence))

(defun iedit-make-unmatched-lines-overlay (begin end)
  "Create an overlay for lines between two occurrences in iedit mode."
  (let ((unmatched-lines-overlay (make-overlay begin end (current-buffer) nil t)))
    (overlay-put unmatched-lines-overlay iedit-invisible-overlay-name t)
    (overlay-put unmatched-lines-overlay 'invisible t)
    (overlay-put unmatched-lines-overlay 'intangible t)
    unmatched-lines-overlay))

(defun iedit-occurrence-update (occurrence after beg end &optional change)
  "Update all occurrences.
This modification hook is triggered when a user edits any
occurrence and is responsible for updating all other
occurrences."
  (when (and after (not undo-in-progress)) ; undo will do all the work
    (let ((value (buffer-substring (overlay-start occurrence) (overlay-end occurrence)))
          (inhibit-modification-hooks t))
      (save-excursion
        (dolist (like-occurrence iedit-occurrences-overlays)
          (if (not (eq like-occurrence occurrence))
              (progn
                (goto-char (overlay-start like-occurrence))
                (delete-region (overlay-start like-occurrence)
                               (overlay-end like-occurrence))
                (insert value))))))))

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
            (setq pos (next-single-char-property-change (point-min) 'iedit-occurrence-overlay-name)))
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

(defun iedit-toggle-unmatched-lines-visible ()
  "Toggle whether to display unmatched lines."
  (interactive)
  (setq iedit-unmatched-lines-invisible (not iedit-unmatched-lines-invisible))
  (if iedit-unmatched-lines-invisible
      (iedit-hide-unmatched-lines)
    (remove-overlays (point-min) (point-max) iedit-invisible-overlay-name t)))

(provide 'iedit)

;;; iedit.el ends here
