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

(provide 'test-util)