;;; simple.el --- basic editing commands for Emacs  -*- lexical-binding: t -*-

;; Copyright (C) 1985-1987, 1993-2025 Free Software Foundation, Inc.

;; Maintainer: emacs-devel@gnu.org
;; Keywords: internal
;; Package: emacs

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A grab-bag of basic Emacs commands not specifically related to some
;; major mode or to file-handling.

;;; Code:

(eval-when-compile (require 'cl-lib))

(declare-function widget-apply "wid-edit" (widget property &rest args))
(declare-function widget-convert "wid-edit" (type &rest args))

;;; From compile.el
(defvar compilation-current-error)
(defvar compilation-context-lines)

(make-obsolete-variable 'idle-update-delay 'which-func-update-delay "30.1")
(defcustom idle-update-delay 0.5
  "Idle time delay before updating various things on the screen.
Various Emacs features that update auxiliary information when point moves
wait this many seconds after Emacs becomes idle before doing an update."
  :type 'number
  :group 'display
  :version "22.1")

(defvar amalgamating-undo-limit 20
  "The maximum number of changes to possibly amalgamate when undoing changes.
The `undo' command will normally consider \"similar\" changes
(like inserting characters) to be part of the same change.  This
is called \"amalgamating\" the changes.  This variable says what
the maximum number of changes considered is when amalgamating.  A
value of 1 means that nothing is amalgamated.")

(defgroup killing nil
  "Killing and yanking commands."
  :group 'editing)

(defgroup paren-matching nil
  "Highlight (un)matching of parens and expressions."
  :group 'matching)

(defvar-local escaped-string-quote "\\"
  "String to insert before a string quote character in a string to escape it.
This is typically a backslash (in most languages):

  \\='foo\\\\='bar\\='
  \"foo\\\"bar\"

But in SQL, for instance, it's \"\\='\":

  \\='foo\\='\\='bar\\='

This can also be a function, which is called with the string
terminator as the argument, and should return a string to be
used as the escape.

This variable is used by the `yank-in-context' command.")


;;; next-error support framework

(defgroup next-error nil
  "`next-error' support framework."
  :group 'compilation
  :version "22.1")

(defface next-error
  '((t (:inherit region)))
  "Face used to highlight next error locus."
  :group 'next-error
  :version "22.1")

(defcustom next-error-highlight 0.5
  "Highlighting of locations in the selected buffer.
If a number, highlight the locus in `next-error' face for the given time
in seconds, or until the next command is executed.
If t, highlight the locus until the next command is executed, or until
some other locus replaces it.
If nil, don't highlight the locus in the source buffer.
If `fringe-arrow', indicate the locus by the fringe arrow
indefinitely until some other locus replaces it.
See `next-error-highlight-no-select' to customize highlighting
of the locus in non-selected buffers."
  :type '(choice (number :tag "Highlight for specified time")
                 (const :tag "Semipermanent highlighting" t)
                 (const :tag "No highlighting" nil)
                 (const :tag "Fringe arrow" fringe-arrow))
  :group 'next-error
  :version "22.1")

(defcustom next-error-highlight-no-select 0.5
  "Highlighting of locations in non-selected source buffers.
Usually non-selected buffers are displayed by `next-error-no-select'.
If number, highlight the locus in `next-error' face for given time in seconds.
If t, highlight the locus indefinitely until some other locus replaces it.
If nil, don't highlight the locus in the source buffer.
If `fringe-arrow', indicate the locus by the fringe arrow
indefinitely until some other locus replaces it.
See `next-error-highlight' to customize highlighting of the locus
in the selected buffer."
  :type '(choice (number :tag "Highlight for specified time")
                 (const :tag "Semipermanent highlighting" t)
                 (const :tag "No highlighting" nil)
                 (const :tag "Fringe arrow" fringe-arrow))
  :group 'next-error
  :version "22.1")

(defcustom next-error-recenter nil
  "Display the line in the visited source file recentered as specified.
If non-nil, the value is passed directly to `recenter'."
  :type '(choice (integer :tag "Line to recenter to")
                 (const :tag "Center of window" (4))
                 (const :tag "No recentering" nil))
  :group 'next-error
  :version "23.1")

(defcustom next-error-message-highlight nil
  "If non-nil, highlight the current error message in the `next-error' buffer.
If the value is `keep', highlighting is permanent, so all visited error
messages are highlighted; this helps to see what messages were visited."
  :type '(choice (const :tag "Highlight the current error" t)
                 (const :tag "Highlight all visited errors" keep)
                 (const :tag "No highlighting" nil))
  :group 'next-error
  :version "28.1")

(defface next-error-message
  '((t (:inherit highlight :extend t)))
  "Face used to highlight the current error message in the `next-error' buffer."
  :group 'next-error
  :version "28.1")

(defvar-local next-error--message-highlight-overlay
  nil
  "Overlay highlighting the current error message in the `next-error' buffer.")

(defvar global-minor-modes nil
  "A list of the currently enabled global minor modes.
This is a list of symbols.")

(defcustom next-error-hook nil
  "List of hook functions run by `next-error' after visiting source file."
  :type 'hook
  :group 'next-error)

(defcustom next-error-verbose t
  "If non-nil, `next-error' always outputs the current error buffer.
If nil, the message is output only when the error buffer
changes."
  :group 'next-error
  :type 'boolean
  :safe #'booleanp
  :version "27.1")

(defvar next-error-highlight-timer nil)

(defvar next-error-overlay-arrow-position nil)
(put 'next-error-overlay-arrow-position 'overlay-arrow-string "=>")
(add-to-list 'overlay-arrow-variable-list 'next-error-overlay-arrow-position)

(defvar next-error-last-buffer nil
  "The most recent `next-error' buffer.
A buffer becomes most recent when its compilation, grep, or
similar mode is started, or when it is used with \\[next-error]
or \\[compile-goto-error].")

(defvar-local next-error-buffer nil
  "The buffer-local value of the most recent `next-error' buffer.")
;; next-error-buffer is made buffer-local to keep the reference
;; to the parent buffer used to navigate to the current buffer, so the
;; next call of next-buffer will use the same parent buffer to
;; continue navigation from it.

(defvar-local next-error-function nil
  "Function to use to find the next error in the current buffer.
The function is called with 2 parameters:
ARG is an integer specifying by how many errors to move.
RESET is a boolean which, if non-nil, says to go back to the beginning
of the errors before moving.
Major modes providing compile-like functionality should set this variable
to indicate to `next-error' that this is a candidate buffer and how
to navigate in it.")

(defvar-local next-error-move-function nil
  "Function to use to move to an error locus.
It takes two arguments, a buffer position in the error buffer
and a buffer position in the error locus buffer.
The buffer for the error locus should already be current.
nil means use `goto-char' using the second argument position.")

(defsubst next-error-buffer-p (buffer
			       &optional avoid-current
			       extra-test-inclusive
			       extra-test-exclusive)
  "Return non-nil if BUFFER is a `next-error' capable buffer.
If AVOID-CURRENT is non-nil, and BUFFER is the current buffer,
return nil.

The function EXTRA-TEST-INCLUSIVE, if non-nil, is called if
BUFFER would not normally qualify.  If it returns non-nil, BUFFER
is considered `next-error' capable, anyway, and the function
returns non-nil.

The function EXTRA-TEST-EXCLUSIVE, if non-nil, is called if the
buffer would normally qualify.  If it returns nil, BUFFER is
rejected, and the function returns nil."
  (and (buffer-name buffer)		;First make sure it's live.
       (not (and avoid-current (eq buffer (current-buffer))))
       (with-current-buffer buffer
	 (if next-error-function   ; This is the normal test.
	     ;; Optionally reject some buffers.
	     (if extra-test-exclusive
		 (funcall extra-test-exclusive)
	       t)
	   ;; Optionally accept some other buffers.
	   (and extra-test-inclusive
		(funcall extra-test-inclusive))))))

(defcustom next-error-find-buffer-function #'ignore
  "Function called to find a `next-error' capable buffer.
This function takes the same three arguments as the function
`next-error-find-buffer', and should return the buffer to be
used by the subsequent invocation of the command `next-error'
and `previous-error'.
If the function returns nil, `next-error-find-buffer' will
try to use the buffer it used previously, and failing that
all other buffers."
  :type '(choice (const :tag "No default" ignore)
                 (const :tag "Single next-error capable buffer on selected frame"
                        next-error-buffer-on-selected-frame)
                 (const :tag "Current buffer if next-error capable and outside navigation"
                        next-error-buffer-unnavigated-current)
                 (function :tag "Other function"))
  :group 'next-error
  :version "28.1")

(defun next-error-buffer-on-selected-frame (&optional _avoid-current
                                                      extra-test-inclusive
                                                      extra-test-exclusive)
  "Return a single visible `next-error' buffer on the selected frame."
  (let ((window-buffers
         (delete-dups
          (delq nil (mapcar (lambda (w)
                              (if (next-error-buffer-p
				   (window-buffer w)
                                   t
                                   extra-test-inclusive extra-test-exclusive)
                                  (window-buffer w)))
                            (window-list))))))
    (if (eq (length window-buffers) 1)
        (car window-buffers))))

(defun next-error-buffer-unnavigated-current (&optional avoid-current
                                                        extra-test-inclusive
                                                        extra-test-exclusive)
  "Try the current buffer when outside navigation.
But return nil if we navigated to the current buffer by the means
of `next-error' command.  Otherwise, return it if it's `next-error'
capable."
  ;; Check that next-error-buffer has no buffer-local value
  ;; (i.e. we never navigated to the current buffer from another),
  ;; and the current buffer is a `next-error' capable buffer.
  (if (and (not (local-variable-p 'next-error-buffer))
           (next-error-buffer-p (current-buffer) avoid-current
                                extra-test-inclusive extra-test-exclusive))
      (current-buffer)))

(defun next-error-find-buffer (&optional avoid-current
					 extra-test-inclusive
					 extra-test-exclusive)
  "Return a `next-error' capable buffer.

If AVOID-CURRENT is non-nil, treat the current buffer
as an absolute last resort only.

The function EXTRA-TEST-INCLUSIVE, if non-nil, is called in each buffer
that normally would not qualify.  If it returns t, the buffer
in question is treated as usable.

The function EXTRA-TEST-EXCLUSIVE, if non-nil, is called in each buffer
that would normally be considered usable.  If it returns nil,
that buffer is rejected."
  (or
   ;; 1. If a customizable function returns a buffer, use it.
   (funcall next-error-find-buffer-function avoid-current
                                            extra-test-inclusive
                                            extra-test-exclusive)
   ;; 2. If next-error-last-buffer is an acceptable buffer, use that.
   (if (and next-error-last-buffer
            (next-error-buffer-p next-error-last-buffer avoid-current
                                 extra-test-inclusive extra-test-exclusive))
       next-error-last-buffer)
   ;; 3. If the current buffer is acceptable, choose it.
   (if (next-error-buffer-p (current-buffer) avoid-current
			    extra-test-inclusive extra-test-exclusive)
       (current-buffer))
   ;; 4. Look for any acceptable buffer.
   (let ((buffers (buffer-list)))
     (while (and buffers
                 (not (next-error-buffer-p
		       (car buffers) avoid-current
		       extra-test-inclusive extra-test-exclusive)))
       (setq buffers (cdr buffers)))
     (car buffers))
   ;; 5. Use the current buffer as a last resort if it qualifies,
   ;; even despite AVOID-CURRENT.
   (and avoid-current
	(next-error-buffer-p (current-buffer) nil
			     extra-test-inclusive extra-test-exclusive)
	(progn
	  (message "This is the only buffer with error message locations")
	  (current-buffer)))
   ;; 6. Give up.
   (error "No buffers contain error message locations")))

(defun next-error (&optional arg reset)
  "Visit next `next-error' message and corresponding source code.

If all the error messages parsed so far have been processed already,
the message buffer is checked for new ones.

A prefix ARG specifies how many error messages to move;
negative means move back to previous error messages.
Just \\[universal-argument] as a prefix means reparse the error message buffer
and start at the first error.

The RESET argument specifies that we should restart from the beginning.

\\[next-error] normally uses the most recently started
compilation, grep, or occur buffer.  It can also operate on any
buffer with output from the \\[compile], \\[grep] commands, or,
more generally, on any buffer in Compilation mode or with
Compilation Minor mode enabled, or any buffer in which
`next-error-function' is bound to an appropriate function.
To specify use of a particular buffer for error messages, type
\\[next-error] in that buffer.  You can also use the command
`next-error-select-buffer' to select the buffer to use for the subsequent
invocation of `next-error'.

Once \\[next-error] has chosen the buffer for error messages, it
runs `next-error-hook' with `run-hooks', and stays with that buffer
until you use it in some other buffer that uses Compilation mode
or Compilation Minor mode.

To control which errors are matched, customize the variable
`compilation-error-regexp-alist'."
  (interactive "P")
  (if (consp arg) (setq reset t arg nil))
  (let ((buffer (next-error-find-buffer)))
    (when buffer
      ;; We know here that next-error-function is a valid symbol we can funcall
      (with-current-buffer buffer
        (funcall next-error-function (prefix-numeric-value arg) reset)
        (let ((prev next-error-last-buffer))
          (next-error-found buffer (current-buffer))
          (when (or next-error-verbose
                    (not (eq prev next-error-last-buffer)))
            (message "%s locus from %s"
                     (cond (reset                             "First")
                           ((eq (prefix-numeric-value arg) 0) "Current")
                           ((< (prefix-numeric-value arg) 0)  "Previous")
                           (t                                 "Next"))
                     next-error-last-buffer)))))))

(defun next-error-internal ()
  "Visit the source code corresponding to the `next-error' message at point."
  (let ((buffer (current-buffer)))
    ;; We know here that next-error-function is a valid symbol we can funcall
    (funcall next-error-function 0 nil)
    (let ((prev next-error-last-buffer))
      (next-error-found buffer (current-buffer))
      (when (or next-error-verbose
                (not (eq prev next-error-last-buffer)))
        (message "Current locus from %s" next-error-last-buffer)))))

(defun next-error-quit-window (from-buffer to-buffer)
  "Quit window of FROM-BUFFER when the prefix arg is 0.
Intended to be used in `next-error-found-function'."
  (when (and (eq current-prefix-arg 0) from-buffer
             (not (eq from-buffer to-buffer)))
    (let ((window (get-buffer-window from-buffer)))
      (when (window-live-p window)
        (quit-restore-window window)))))

(defcustom next-error-found-function #'ignore
  "Function called when a next locus is found and displayed.
Function is called with two arguments: a FROM-BUFFER buffer
from which `next-error' navigated, and a target buffer TO-BUFFER."
  :type '(choice (const :tag "No default" ignore)
                 (const :tag "Quit previous window with M-0"
                        next-error-quit-window)
                 (function :tag "Other function"))
  :group 'next-error
  :version "27.1")

(defun next-error-found (&optional from-buffer to-buffer)
  "Function to call when the next locus is found and displayed.
FROM-BUFFER is a buffer from which `next-error' navigated,
and TO-BUFFER is a target buffer."
  (setq next-error-last-buffer (or from-buffer (current-buffer)))
  (when to-buffer
    (with-current-buffer to-buffer
      (setq next-error-buffer from-buffer)))
  (when next-error-recenter
    (recenter next-error-recenter))
  (funcall next-error-found-function from-buffer to-buffer)
  (next-error-message-highlight from-buffer)
  (run-hooks 'next-error-hook))

(defun next-error-select-buffer (buffer)
  "Select a `next-error' capable BUFFER and set it as the last used.
This means that the selected buffer becomes the source of locations
for the subsequent invocation of `next-error' or `previous-error'.
Interactively, this command allows selection only among buffers
where `next-error-function' is bound to an appropriate function."
  (interactive
   (list (get-buffer
          (read-buffer "Select next-error buffer: " nil nil
                       (lambda (b) (next-error-buffer-p (cdr b)))))))
  (setq next-error-last-buffer buffer))

(defalias 'goto-next-locus 'next-error)
(defalias 'next-match 'next-error)

(defun previous-error (&optional n)
  "Visit previous `next-error' message and corresponding source code.

Prefix arg N says how many error messages to move backwards (or
forwards, if negative).

This operates on the output from the \\[compile] and \\[grep] commands.

See `next-error' for the details."
  (interactive "p")
  (next-error (- (or n 1))))

(defun first-error (&optional n)
  "Restart at the first error.
Visit corresponding source code.
With prefix arg N, visit the source code of the Nth error.
This operates on the output from the \\[compile] command, for instance."
  (interactive "p")
  (next-error n t))

(defun next-error-no-select (&optional n)
  "Move point to the next error in the `next-error' buffer and highlight match.
Prefix arg N says how many error messages to move forwards (or
backwards, if negative).
Finds and highlights the source line like \\[next-error], but does not
select the source buffer."
  (interactive "p")
  (save-selected-window
    (let ((next-error-highlight next-error-highlight-no-select)
          (display-buffer-overriding-action
           '(nil (inhibit-same-window . t))))
      (next-error n))))

(defun next-error-this-buffer-no-select (&optional n)
  "Move point to the next error in the current buffer and highlight match.
Prefix arg N says how many error messages to move forwards (or
backwards, if negative).
Finds and highlights the source line like \\[next-error], but does not
select the source buffer."
  (interactive "p")
  (next-error-select-buffer (current-buffer))
  (next-error-no-select n))

(defun previous-error-no-select (&optional n)
  "Move point to the previous error in the `next-error' buffer and highlight match.
Prefix arg N says how many error messages to move backwards (or
forwards, if negative).
Finds and highlights the source line like \\[previous-error], but does not
select the source buffer."
  (interactive "p")
  (next-error-no-select (- (or n 1))))

(defun previous-error-this-buffer-no-select (&optional n)
  "Move point to the previous error in the current buffer and highlight match.
Prefix arg N says how many error messages to move forwards (or
backwards, if negative).
Finds and highlights the source line like \\[previous-error], but does not
select the source buffer."
  (interactive "p")
  (next-error-select-buffer (current-buffer))
  (previous-error-no-select n))

;; Internal variable for `next-error-follow-mode-post-command-hook'.
(defvar next-error-follow-last-line nil)

(define-minor-mode next-error-follow-minor-mode
  "Minor mode for compilation, occur and diff modes.

When turned on, cursor motion in the compilation, grep, occur or diff
buffer causes automatic display of the corresponding source code location."
  :group 'next-error :init-value nil :lighter " Fol"
  (if (not next-error-follow-minor-mode)
      (remove-hook 'post-command-hook 'next-error-follow-mode-post-command-hook t)
    (add-hook 'post-command-hook 'next-error-follow-mode-post-command-hook nil t)
    (make-local-variable 'next-error-follow-last-line)))

;; Used as a `post-command-hook' by `next-error-follow-mode'
;; for the *Compilation* *grep* and *Occur* buffers.
(defun next-error-follow-mode-post-command-hook ()
  (unless (equal next-error-follow-last-line (line-number-at-pos))
    (setq next-error-follow-last-line (line-number-at-pos))
    (condition-case nil
	(let ((compilation-context-lines nil))
	  (setq compilation-current-error (point))
	  (next-error-no-select 0))
      (error t))))

(defun next-error-message-highlight (error-buffer)
  "Highlight the current error message in the `next-error' buffer."
  (when next-error-message-highlight
    (with-current-buffer error-buffer
      (when (and next-error--message-highlight-overlay
                 (not (eq next-error-message-highlight 'keep)))
        (delete-overlay next-error--message-highlight-overlay))
      (let ((ol (make-overlay (line-beginning-position) (1+ (line-end-position)))))
        ;; do not override region highlighting
        (overlay-put ol 'priority -50)
        (overlay-put ol 'face 'next-error-message)
        (overlay-put ol 'window (get-buffer-window))
        (setf next-error--message-highlight-overlay ol)))))

(defun recenter-current-error (&optional arg)
  "Recenter the current displayed error in the `next-error' buffer."
  (interactive "P")
  (save-selected-window
    (let ((next-error-highlight next-error-highlight-no-select)
          (display-buffer-overriding-action
           '(nil (inhibit-same-window . t))))
      (next-error 0)
      (set-buffer (window-buffer))
      (recenter-top-bottom arg))))

;;;

(defun fundamental-mode ()
  "Major mode not specialized for anything in particular.
Other major modes are defined by comparison with this one."
  (interactive)
  (kill-all-local-variables)
  (run-mode-hooks))

(define-derived-mode clean-mode fundamental-mode "Clean"
  "A mode that removes all overlays and text properties."
  (kill-all-local-variables t)
  (let ((inhibit-read-only t))
    (dolist (overlay (overlays-in (point-min) (point-max)))
      (delete-overlay overlay))
    (set-text-properties (point-min) (point-max) nil)
    (setq-local yank-excluded-properties t)))

;; Special major modes to view specially formatted data rather than files.

(defvar-keymap special-mode-map
  :suppress t
  "q" #'quit-window
  "SPC" #'scroll-up-command
  "S-SPC" #'scroll-down-command
  "DEL" #'scroll-down-command
  "?" #'describe-mode
  "h" #'describe-mode
  ">" #'end-of-buffer
  "<" #'beginning-of-buffer
  "g" #'revert-buffer)

(put 'special-mode 'mode-class 'special)
(define-derived-mode special-mode nil "Special"
  "Parent major mode from which special major modes should inherit.

A special major mode is intended to view specially formatted data
rather than files.  These modes usually use read-only buffers."
  (setq buffer-read-only t))

;; Making and deleting lines.

(defvar self-insert-uses-region-functions nil
  "Special hook to tell if `self-insert-command' will use the region.
It must be called via `run-hook-with-args-until-success' with no arguments.

If any function on this hook returns a non-nil value, `delete-selection-mode'
will act on that value (see `delete-selection-helper') and will
usually delete the region.  If all the functions on this hook return
nil, it is an indication that `self-insert-command' needs the region
untouched by `delete-selection-mode' and will itself do whatever is
appropriate with the region.
Any function on `post-self-insert-hook' that acts on the region should
add a function to this hook so that `delete-selection-mode' could
refrain from deleting the region before the `post-self-insert-hook'
functions are called.
This hook is run by `delete-selection-uses-region-p', which see.")

(defvar hard-newline (propertize "\n" 'hard t 'rear-nonsticky '(hard))
  "Propertized string representing a hard newline character.")

(defun newline (&optional arg interactive)
   "Insert a newline, and move to left margin of the new line.
With prefix argument ARG, insert that many newlines.

If `electric-indent-mode' is enabled, this indents the final new line
that it adds, and reindents the preceding line.  To just insert
a newline, use \\[electric-indent-just-newline].

If `auto-fill-mode' is enabled, this may cause automatic line
breaking of the preceding line.  A non-nil ARG inhibits this.

If `use-hard-newlines' is enabled, the newline is marked with the
text-property `hard'.

A non-nil INTERACTIVE argument means to run the `post-self-insert-hook'."
  (interactive "*P\np")
  (barf-if-buffer-read-only)
  (when (and arg
             (< (prefix-numeric-value arg) 0))
    (error "Repetition argument has to be non-negative"))
  ;; Call self-insert so that auto-fill, abbrev expansion etc. happen.
  ;; Set last-command-event to tell self-insert what to insert.
  (let* ((was-page-start (and (bolp) (looking-at page-delimiter)))
         (beforepos (point))
         (last-command-event ?\n)
         ;; Don't auto-fill if we have a prefix argument.
         (inhibit-auto-fill (or inhibit-auto-fill arg))
         (arg (prefix-numeric-value arg))
         (procsym (make-symbol "newline-postproc")) ;(bug#46326)
         (postproc
          ;; Do the rest in post-self-insert-hook, because we want to do it
          ;; *before* other functions on that hook.
          (lambda ()
            (remove-hook 'post-self-insert-hook procsym t)
            ;; Mark the newline(s) `hard'.
            (if use-hard-newlines
                (set-hard-newline-properties
                 (- (point) arg) (point)))
            ;; If the newline leaves the previous line blank, and we
            ;; have a left margin, delete that from the blank line.
            (save-excursion
              (goto-char beforepos)
              (beginning-of-line)
              (and (looking-at "[ \t]+$")
                   (> (current-left-margin) 0)
                   (delete-region (point)
                                  (line-end-position))))
            ;; Indent the line after the newline, except in one case:
            ;; when we added the newline at the beginning of a line that
            ;; starts a page.
            (or was-page-start
                (move-to-left-margin nil t)))))
    (fset procsym postproc)
    (if (not interactive)
	;; FIXME: For non-interactive uses, many calls actually
	;; just want (insert "\n"), so maybe we should do just
	;; that, so as to avoid the risk of filling or running
	;; abbrevs unexpectedly.
	(let ((post-self-insert-hook (list postproc)))
	  (self-insert-command arg))
      (unwind-protect
	  (progn
	    (add-hook 'post-self-insert-hook procsym nil t)
	    (self-insert-command arg))
	;; We first used let-binding to protect the hook, but that
	;; was naive since add-hook affects the symbol-default
	;; value of the variable, whereas the let-binding might
	;; protect only the buffer-local value.
	(remove-hook 'post-self-insert-hook procsym t))))
  nil)

(defun set-hard-newline-properties (from to)
  (let ((sticky (get-text-property from 'rear-nonsticky)))
    (put-text-property from to 'hard 't)
    ;; If rear-nonsticky is not "t", add 'hard to rear-nonsticky list
    (if (and (listp sticky) (not (memq 'hard sticky)))
	(put-text-property from (point) 'rear-nonsticky
			   (cons 'hard sticky)))))

(defun open-line (n)
  "Insert a newline and leave point before it.
If there is a fill prefix and/or a `left-margin', insert them on
the new line if the line would have been blank.
With arg N, insert N newlines."
  (interactive "*p")
  (let* ((do-fill-prefix (and fill-prefix (bolp)))
	 (do-left-margin (and (bolp) (> (current-left-margin) 0)))
	 (loc (point-marker))
         ;; Don't expand an abbrev before point.
	 (abbrev-mode nil))
    (newline n)
    (goto-char loc)
    (while (> n 0)
      (cond ((bolp)
	     (if do-left-margin (indent-to (current-left-margin)))
	     (if do-fill-prefix (insert-and-inherit fill-prefix))))
      (forward-line 1)
      (setq n (1- n)))
    (goto-char loc)
    ;; Necessary in case a margin or prefix was inserted.
    (end-of-line)))

(defun split-line (&optional arg)
  "Split current line, moving portion beyond point vertically down.
If the current line starts with `fill-prefix', insert it on the new
line as well.  With prefix ARG, don't insert `fill-prefix' on new line.

When called from Lisp code, ARG may be a prefix string to copy."
  (interactive "*P")
  (skip-chars-forward " \t")
  (let* ((col (current-column))
	 (pos (point))
	 ;; What prefix should we check for (nil means don't).
	 (prefix (cond ((stringp arg) arg)
		       (arg nil)
		       (t fill-prefix)))
	 ;; Does this line start with it?
	 (have-prfx (and prefix
			 (save-excursion
			   (beginning-of-line)
			   (looking-at (regexp-quote prefix))))))
    (newline 1)
    (if have-prfx (insert-and-inherit prefix))
    (indent-to col 0)
    (goto-char pos)))

(defface separator-line
  '((((type graphic) (background dark))
     :height 0.1 :background "#505050")
    (((type graphic) (background light))
     :height 0.1 :background "#a0a0a0")
    (t
     :foreground "ForestGreen" :underline t))
  "Face for separator lines."
  :version "29.1"
  :group 'text)

(defun make-separator-line (&optional length)
  "Make a string appropriate for usage as a visual separator line.
This uses the `separator-line' face.

If LENGTH is nil, use the window width."
  (if (or (display-graphic-p)
          (display-supports-face-attributes-p '(:underline t)))
      (if length
          (concat (propertize (make-string length ?\s) 'face 'separator-line)
                  "\n")
        (propertize "\n" 'face '(:inherit separator-line :extend t)))
    ;; In terminals (that don't support underline), use a line of dashes.
    (concat (propertize (make-string (or length (1- (window-width))) ?-)
                        'face 'separator-line)
            "\n")))

(defun delete-indentation (&optional arg beg end)
  "Join this line to previous and fix up whitespace at join.
If there is a fill prefix, delete it from the beginning of this
line.
With prefix ARG, join the current line to the following line.
When BEG and END are non-nil, join all lines in the region they
define.  Interactively, BEG and END are, respectively, the start
and end of the region if it is active, else nil.  (The region is
ignored if prefix ARG is given.)"
  (interactive
   (progn (barf-if-buffer-read-only)
          (cons current-prefix-arg
                (and (use-region-p)
                     (list (region-beginning) (region-end))))))
  ;; Consistently deactivate mark even when no text is changed.
  (setq deactivate-mark t)
  (if (and beg (not arg))
      ;; Region is active.  Go to END, but only if region spans
      ;; multiple lines.
      (and (goto-char beg)
           (> end (line-end-position))
           (goto-char end))
    ;; Region is inactive.  Set a loop sentinel
    ;; (subtracting 1 in order to compare less than BOB).
    (setq beg (1- (line-beginning-position (and arg 2))))
    (when arg (forward-line)))
  (let ((prefix (and (> (length fill-prefix) 0)
                     (regexp-quote fill-prefix))))
    (while (and (> (line-beginning-position) beg)
                (forward-line 0)
                (= (preceding-char) ?\n))
      (delete-char -1)
      ;; If the appended line started with the fill prefix,
      ;; delete the prefix.
      (if (and prefix (looking-at prefix))
          (replace-match "" t t))
      (fixup-whitespace))))

(defalias 'join-line #'delete-indentation) ; easier to find

(defun delete-blank-lines ()
  "On blank line, delete all surrounding blank lines, leaving just one.
On isolated blank line, delete that one.
On nonblank line, delete any immediately following blank lines."
  (interactive "*")
  (let (thisblank singleblank)
    (save-excursion
      (beginning-of-line)
      (setq thisblank (looking-at "[ \t]*$"))
      ;; Set singleblank if there is just one blank line here.
      (setq singleblank
	    (and thisblank
		 (not (looking-at "[ \t]*\n[ \t]*$"))
		 (or (bobp)
		     (progn (forward-line -1)
			    (not (looking-at "[ \t]*$")))))))
    ;; Delete preceding blank lines, and this one too if it's the only one.
    (if thisblank
	(progn
	  (beginning-of-line)
	  (if singleblank (forward-line 1))
	  (delete-region (point)
			 (if (re-search-backward "[^ \t\n]" nil t)
			     (progn (forward-line 1) (point))
			   (point-min)))))
    ;; Delete following blank lines, unless the current line is blank
    ;; and there are no following blank lines.
    (if (not (and thisblank singleblank))
	(save-excursion
	  (end-of-line)
	  (forward-line 1)
	  (delete-region (point)
			 (if (re-search-forward "[^ \t\n]" nil t)
			     (progn (beginning-of-line) (point))
			   (point-max)))))
    ;; Handle the special case where point is followed by newline and eob.
    ;; Delete the line, leaving point at eob.
    (if (looking-at "^[ \t]*\n\\'")
	(delete-region (point) (point-max)))))

(defcustom delete-trailing-lines t
  "If non-nil, \\[delete-trailing-whitespace] deletes trailing lines.
Trailing lines are deleted only if `delete-trailing-whitespace'
is called on the entire buffer (rather than an active region)."
  :type 'boolean
  :group 'editing
  :version "24.3")

(defun region-modifiable-p (start end)
  "Return non-nil if the region contains no read-only text."
  (and (not (get-text-property start 'read-only))
       (eq end (next-single-property-change start 'read-only nil end))))

(defun delete-trailing-whitespace (&optional start end)
  "Delete trailing whitespace between START and END.
If called interactively, START and END are the start/end of the
region if the mark is active, or of the buffer's accessible
portion if the mark is inactive.

This command deletes whitespace characters after the last
non-whitespace character in each line between START and END.  It
does not consider formfeed characters to be whitespace.

If this command acts on the entire buffer (i.e. if called
interactively with the mark inactive, or called from Lisp with
END nil), it also deletes all trailing lines at the end of the
buffer if the variable `delete-trailing-lines' is non-nil."
  (interactive (progn
                 (barf-if-buffer-read-only)
                 (if (use-region-p)
                     (list (region-beginning) (region-end))
                   (list nil nil))))
  (save-match-data
    (save-excursion
      (let ((end-marker (and end (copy-marker end))))
        (goto-char (or start (point-min)))
        (with-syntax-table (make-syntax-table (syntax-table))
          ;; Don't delete formfeeds, even if they are considered whitespace.
          (modify-syntax-entry ?\f "_")
          (while (re-search-forward "\\s-$" end-marker t)
            (skip-syntax-backward "-" (line-beginning-position))
            (let ((b (point)) (e (match-end 0)))
              (if (region-modifiable-p b e)
                  (delete-region b e)
                (goto-char e)))))
        (if end
            (set-marker end-marker nil)
          ;; Delete trailing empty lines.
          (and delete-trailing-lines
               ;; Really the end of buffer.
               (= (goto-char (point-max)) (1+ (buffer-size)))
               (<= (skip-chars-backward "\n") -2)
               (region-modifiable-p (1+ (point)) (point-max))
               (delete-region (1+ (point)) (point-max)))))))
  ;; Return nil for the benefit of `write-file-functions'.
  nil)

(defun delete-trailing-whitespace-if-possible ()
  "Call `delete-trailing-whitespace' unless the buffer is read-only."
  (unless buffer-read-only (delete-trailing-whitespace)))

(define-minor-mode delete-trailing-whitespace-mode
  "Delete trailing whitespace before saving the current buffer."
  :global nil
  (cond
   (delete-trailing-whitespace-mode
    (add-hook 'before-save-hook
              #'delete-trailing-whitespace-if-possible nil t))
   (t
    (remove-hook 'before-save-hook
                 #'delete-trailing-whitespace-if-possible t))))

(defun newline-and-indent (&optional arg)
  "Insert a newline, then indent according to major mode.
Indentation is done using the value of `indent-line-function'.
In programming language modes, this is the same as TAB.
In some text modes, where TAB inserts a tab, this command indents to the
column specified by the function `current-left-margin'.

With ARG, perform this action that many times.

Also see `open-line' (bound to \\[open-line]) for a command that
just inserts a newline without doing any indentation."
  (interactive "*p")
  (delete-horizontal-space t)
  (unless arg
    (setq arg 1))
  (let ((electric-indent-mode nil))
    (dotimes (_ arg)
      (newline nil t)
      (indent-according-to-mode))))

(defun reindent-then-newline-and-indent ()
  "Reindent current line, insert newline, then indent the new line.
Indentation of both lines is done according to the current major mode,
which means calling the current value of `indent-line-function'.
In programming language modes, this is the same as TAB.
In some text modes, where TAB inserts a tab, this indents to the
column specified by the function `current-left-margin'."
  (interactive "*")
  ;; Use a marker because the call to 'newline' below could insert some
  ;; text, e.g., if 'abbrev-mode' is turned on.
  (let ((pos (point-marker))
        (electric-indent-mode nil))
    ;; Be careful to insert the newline before indenting the line.
    ;; Otherwise, the indentation might be wrong.
    (newline)
    (save-excursion
      (goto-char pos)
      ;; We are at EOL before the call to indent-according-to-mode, and
      ;; after it we usually are as well, but not always.  We tried to
      ;; address it with `save-excursion' but that uses a normal marker
      ;; whereas we need `move after insertion', so we do the save/restore
      ;; by hand.
      (setq pos (copy-marker pos t))
      (indent-according-to-mode)
      (goto-char pos)
      ;; Remove the trailing white-space after indentation because
      ;; indentation may introduce the whitespace.
      (delete-horizontal-space t))
    (indent-according-to-mode)))

(defcustom read-quoted-char-radix 8
  "Radix for \\[quoted-insert] and other uses of `read-quoted-char'.
Supported radix values are 8, 10 and 16."
 :type '(choice (const 8) (const 10) (const 16))
 :group 'editing-basics)

(defun read-quoted-char (&optional prompt)
  "Like `read-char', but do not allow quitting.
Also, if the first character read is an octal digit,
we read any number of octal digits and return the
specified character code.  Any nondigit terminates the sequence.
If the terminator is RET, it is discarded;
any other terminator is used itself as input.

The optional argument PROMPT specifies a string to use to prompt the user.
The variable `read-quoted-char-radix' controls which radix to use
for numeric input."
  (let ((message-log-max nil)
	(help-events (delq nil (mapcar (lambda (c) (unless (characterp c) c))
				       help-event-list)))
	done (first t) (code 0) char translated)
    (while (not done)
      (let ((inhibit-quit first)
	    ;; Don't let C-h or other help chars get the help
	    ;; message--only help function keys.  See bug#16617.
	    (help-char nil)
	    (help-event-list help-events)
	    (help-form
	     "Type the special character you want to use,
or the octal character code.
RET terminates the character code and is discarded;
any other non-digit terminates the character code and is then used as input."))
	(setq char (read-event (and prompt (format "%s-" prompt)) t))
	(if inhibit-quit (setq quit-flag nil)))
      ;; Translate TAB key into control-I ASCII character, and so on.
      ;; Note: `read-char' does it using the `ascii-character' property.
      ;; We tried using read-key instead, but that disables the keystroke
      ;; echo produced by 'C-q', see bug#24635.
      (let ((translation (lookup-key local-function-key-map (vector char))))
	(setq translated (if (arrayp translation)
			     (aref translation 0)
			   char)))
      (if (integerp translated)
	  (setq translated (char-resolve-modifiers translated)))
      (cond ((null translated))
	    ((not (integerp translated))
	     (setq unread-command-events (list char)
		   done t))
	    ((/= (logand translated ?\M-\^@) 0)
	     ;; Turn a meta-character into a character with the 0200 bit set.
	     (setq code (logior (logand translated (lognot ?\M-\^@)) 128)
		   done t))
	    ((and (<= ?0 translated)
                  (< translated (+ ?0 (min 10 read-quoted-char-radix))))
	     (setq code (+ (* code read-quoted-char-radix) (- translated ?0)))
	     (and prompt (setq prompt (message "%s %c" prompt translated))))
	    ((and (<= ?a (downcase translated))
		  (< (downcase translated)
                     (+ ?a -10 (min 36 read-quoted-char-radix))))
	     (setq code (+ (* code read-quoted-char-radix)
			   (+ 10 (- (downcase translated) ?a))))
	     (and prompt (setq prompt (message "%s %c" prompt translated))))
	    ((and (not first) (eq translated ?\C-m))
	     (setq done t))
	    ((not first)
	     (setq unread-command-events (list char)
		   done t))
	    (t (setq code translated
		     done t)))
      (setq first nil))
    code))

(defun quoted-insert (arg)
  "Read next input character and insert it.
This is useful for inserting control characters.
With argument, insert ARG copies of the character.

If the first character you type is an octal digit, the sequence of
one or more octal digits you type is interpreted to specify a
character code.  Any character that is not an octal digit terminates
the sequence.  If the terminator is a RET, it is discarded; any
other terminator is used itself as input and is inserted.

The variable `read-quoted-char-radix' specifies the radix for this feature;
set it to 10 or 16 to use decimal or hex instead of octal.  If you change
the radix, the characters interpreted as specifying a character code
change accordingly: 0 to 9 for decimal, 0 to F for hex.

In overwrite mode, this function inserts the character anyway, and
does not handle octal (or decimal or hex) digits specially.  This means
that if you use overwrite mode as your normal editing mode, you can use
this function to insert characters when necessary.

In binary overwrite mode, this function does overwrite, and octal
\(or decimal or hex) digits are interpreted as a character code.  This
is intended to be useful for editing binary files."
  (interactive "*p")
  (let* ((char
	  ;; Avoid "obsolete" warnings for translation-table-for-input.
	  (with-no-warnings
	    (let (translation-table-for-input input-method-function)
	      (if (or (not overwrite-mode)
		      (eq overwrite-mode 'overwrite-mode-binary))
		  (read-quoted-char)
		(read-char))))))
    ;; This used to assume character codes 0240 - 0377 stand for
    ;; characters in some single-byte character set, and converted them
    ;; to Emacs characters.  But in 23.1 this feature is deprecated
    ;; in favor of inserting the corresponding Unicode characters.
    ;; (if (and enable-multibyte-characters
    ;;          (>= char ?\240)
    ;;          (<= char ?\377))
    ;;     (setq char (unibyte-char-to-multibyte char)))
    (unless (characterp char)
      (user-error "%s is not a valid character"
		  (key-description (vector char))))
    (if (> arg 0)
	(if (eq overwrite-mode 'overwrite-mode-binary)
	    (delete-char arg)))
    (while (> arg 0)
      (insert-and-inherit char)
      (setq arg (1- arg)))))

(defun forward-to-indentation (&optional arg)
  "Move forward ARG lines and position at first nonblank character."
  (interactive "^p")
  (forward-line (or arg 1))
  (skip-chars-forward " \t"))

(defun backward-to-indentation (&optional arg)
  "Move backward ARG lines and position at first nonblank character."
  (interactive "^p")
  (forward-line (- (or arg 1)))
  (skip-chars-forward " \t"))

(defun back-to-indentation ()
  "Move point to the first non-whitespace character on this line."
  (interactive "^")
  (beginning-of-line 1)
  (skip-syntax-forward " " (line-end-position))
  ;; Move back over chars that have whitespace syntax but have the p flag.
  (backward-prefix-chars))

(defun fixup-whitespace ()
  "Fixup white space between objects around point.
Leave one space or none, according to the context."
  (interactive "*")
  (save-excursion
    (delete-horizontal-space)
    (if (or (looking-at "^\\|$\\|\\s)")
	    (save-excursion (forward-char -1)
			    (looking-at "$\\|\\s(\\|\\s'")))
	nil
      (insert ?\s))))

(defun delete-horizontal-space (&optional backward-only)
  "Delete all spaces and tabs around point.
If BACKWARD-ONLY is non-nil (interactively, the prefix argument), delete
them only before point."
  (interactive "*P")
  (delete-space--internal " \t" backward-only))

(defun delete-all-space (&optional backward-only)
  "Delete all spaces, tabs, and newlines around point.
If BACKWARD-ONLY is non-nil, delete them only before point."
  (interactive "*P")
  (delete-space--internal " \t\r\n" backward-only))

(defun delete-space--internal (chars backward-only)
  "Delete CHARS around point.
If BACKWARD-ONLY is non-nil, delete them only before point."
  (let ((orig-pos (point)))
    (delete-region
     (if backward-only
         orig-pos
       (progn
         (skip-chars-forward chars)
         (constrain-to-field nil orig-pos t)))
     (progn
       (skip-chars-backward chars)
       (constrain-to-field nil orig-pos)))))

(defun just-one-space (&optional n)
  "Delete all spaces and tabs around point, leaving one space (or N spaces).
Interactively, N is the prefix numeric argument.
If N is negative, delete newlines as well, leaving -N spaces.
See also `cycle-spacing'."
  (interactive "*p")
  (let ((orig-pos        (point))
        (skip-characters (if (and n (< n 0)) " \t\n\r" " \t"))
        (num             (abs (or n 1))))
    (skip-chars-backward skip-characters)
    (constrain-to-field nil orig-pos)
    (let* ((num   (- num (skip-chars-forward " " (+ num (point)))))
           (mid   (point))
           (end   (progn
                    (skip-chars-forward skip-characters)
                    (constrain-to-field nil orig-pos t))))
      (delete-region mid end)
      (insert (make-string num ?\s)))))

(defvar cycle-spacing--context nil
  "Stored context used in consecutive calls to `cycle-spacing' command.
The value is a property list with the following elements:
- `:orig-pos'    The original position of point when starting the
                 sequence.
- `:whitespace-string' All whitespace characters around point
                       including newlines.
- `:n'            The prefix arg given to the initial invocation
                  which is reused for all actions in this cycle.
- `:last-action'  The last action performed in the cycle.")

(defcustom cycle-spacing-actions
  '( just-one-space
     delete-all-space
     restore)
  "List of actions cycled through by `cycle-spacing'.
Supported values are:
- `just-one-space'      Delete all but N (prefix arg) spaces.
                        See that command's docstring for details.
- `delete-space-after'  Delete spaces after point keeping only N.
- `delete-space-before' Delete spaces before point keeping only N.
- `delete-all-space'    Delete all spaces around point.
- `restore'             Restore the original spacing.

All actions make use of the prefix arg given to `cycle-spacing'
in the initial invocation, i.e., `just-one-space' keeps this
amount of spaces deleting surplus ones.  `just-one-space' and all
other actions have the contract that a positive prefix arg (or
zero) only deletes tabs and spaces whereas a negative prefix arg
also deletes newlines.

The `delete-space-before' and `delete-space-after' actions handle
the prefix arg \\[negative-argument] without a number provided
specially: all spaces before/after point are deleted (as if N was
0) including newlines (as if N was negative).

In addition to the predefined actions listed above, any function
which accepts one argument is allowed.  It receives the raw
prefix arg of this cycle.

In addition, an action may take the form (ACTION ARG) where
ACTION is one of the predefined actions (except for `restore')
and ARG is either
- an integer with the meaning that ACTION should always use this
  fixed integer instead of the actual prefix arg or
- the symbol `inverted-arg' with the meaning that ACTION should
  be performed with the inverted actual prefix arg.
- the symbol `-' with the meaning that ACTION should include
  newlines but it's up to the ACTION to decide how to interpret
  it as a number, e.g., `delete-space-before' and
  `delete-space-after' treat it like 0 whereas `just-one-space'
  treats it like -1 as is usual."
  :group 'editing-basics
  :type (let ((actions
               '((const :tag "Just N (prefix arg) spaces" just-one-space)
                 (const :tag "Delete spaces after point" delete-space-after)
                 (const :tag "Delete spaces before point" delete-space-before)
                 (const :tag "Delete all spaces around point" delete-all-space)
                 (function :tag "Function receiving a numeric arg"))))
          `(repeat
            (choice
             ,@actions
             (list :tag "Action with modified arg"
                   (choice ,@actions)
                   (choice (const :tag "Inverted prefix arg" inverted-arg)
                           (integer :tag "Fixed numeric arg")
                           (const :tag "Negative arg" -)))
             (const :tag "Restore the original spacing" restore))))
  :version "29.1")

(defun cycle-spacing (&optional n)
  "Manipulate whitespace around point in a smart way.
Repeated calls perform the actions in `cycle-spacing-actions' one
after the other, wrapping around after the last one.

All actions are amendable using a prefix arg N.  In general, a
zero or positive prefix arg allows only for deletion of tabs and
spaces whereas a negative prefix arg also allows for deleting
newlines.

The prefix arg given at the first invocation starting a cycle is
provided to all following actions, i.e.,
    \\[negative-argument] \\[cycle-spacing] \\[cycle-spacing] \\[cycle-spacing]
is equivalent to
    \\[negative-argument] \\[cycle-spacing] \\[negative-argument] \\[cycle-spacing] \\[negative-argument] \\[cycle-spacing].

A new sequence can be started by providing a different prefix arg
than provided at the initial invocation (except for 1), or by
doing any other command before the next \\[cycle-spacing]."
  (interactive "*P")
  ;; Initialize `cycle-spacing--context' if needed.
  (when (or (not (equal last-command this-command))
            (not cycle-spacing--context)
            ;; With M-5 M-SPC M-SPC... we pass the prefix arg 5 to
            ;; each action and only start a new cycle when a different
            ;; prefix arg is given and which is not the default value
            ;; 1.
            (and n (not (equal (plist-get cycle-spacing--context :n)
                               n))))
    (let ((orig-pos (point))
          (skip-characters " \t\n\r"))
      (save-excursion
        (skip-chars-backward skip-characters)
        (constrain-to-field nil orig-pos)
        (let ((start (point))
              (end   (progn
                       (skip-chars-forward skip-characters)
                       (constrain-to-field nil orig-pos t))))
          (setq cycle-spacing--context  ;; Save for later.
                (list :orig-pos orig-pos
                      :whitespace-string (buffer-substring start end)
                      :n n
                      :last-action nil))))))

  ;; Cycle through the actions in `cycle-spacing-actions'.
  (when cycle-spacing--context
    (cl-labels ((next-action ()
                  (let* ((l cycle-spacing-actions)
                         (elt (plist-get cycle-spacing--context
                                         :last-action)))
                    (if (null elt)
                        (car cycle-spacing-actions)
                      (catch 'found
                        (while l
                          (cond
                           ((null (cdr l))
                            (throw 'found
                                   (when (eq elt (car l))
                                     (car cycle-spacing-actions))))
                           ((and (eq elt (car l))
                                 (cdr l))
                            (throw 'found (cadr l)))
                           (t (setq l (cdr l)))))))))
                (skip-chars (chars max-dist direction)
                  (if (eq direction 'forward)
                      (skip-chars-forward
                       chars
                       (and max-dist (+ (point) max-dist)))
                    (skip-chars-backward
                     chars
                     (and max-dist (- (point) max-dist)))))
                (delete-space (n include-newlines direction)
                  (let ((orig-point (point))
                        (chars (if include-newlines
                                   " \t\r\n"
                                 " \t")))
                    (when (or (zerop n)
                              (= n (abs (skip-chars chars n direction))))
                      (let ((start (point))
                            (end (progn
                                   (skip-chars chars nil direction)
                                   (point))))
                        (unless (= start end)
                          (delete-region start end))
                        (goto-char (if (eq direction 'forward)
                                       orig-point
                                     (+ n end)))))))
                (restore ()
                  (delete-all-space)
                  (insert (plist-get cycle-spacing--context
                                     :whitespace-string))
                  (goto-char (plist-get cycle-spacing--context
                                        :orig-pos))))
      (let ((action (next-action)))
        (atomic-change-group
          (restore)
          (unless (eq action 'restore)
            ;; action can be some-action or (some-action <arg>) where
            ;; arg is either an integer, the arg to be always used for
            ;; this action or - to use the inverted context n for this
            ;; action.
            (let* ((actual-action (if (listp action)
                                      (car action)
                                    action))
                   (arg (when (listp action)
                          (nth 1 action)))
                   (context-n (plist-get cycle-spacing--context :n))
                   (actual-n (cond
                              ((integerp arg) arg)
                              ((eq 'inverted-arg arg)
                               (* -1 (prefix-numeric-value context-n)))
                              ((eq '- arg) '-)
                              (t context-n)))
                   (numeric-n (prefix-numeric-value actual-n))
                   (include-newlines (or (eq actual-n '-)
                                         (and (integerp actual-n)
                                              (< actual-n 0)))))
              (cond
               ((eq actual-action 'just-one-space)
                (just-one-space numeric-n))
               ((eq actual-action 'delete-space-after)
                (delete-space (if (eq actual-n '-) 0 (abs numeric-n))
                              include-newlines 'forward))
               ((eq actual-action 'delete-space-before)
                (delete-space (if (eq actual-n '-) 0 (abs numeric-n))
                              include-newlines 'backward))
               ((eq actual-action 'delete-all-space)
                (if include-newlines
                    (delete-all-space)
                  (delete-horizontal-space)))
               ((functionp actual-action)
                (funcall actual-action actual-n))
               (t
                (error "Don't know how to handle action %S" action)))))
          (setf (plist-get cycle-spacing--context :last-action)
                action))))))

(defun beginning-of-buffer (&optional arg)
  "Move point to the beginning of the buffer.
With numeric arg N, put point N/10 of the way from the beginning.
If the buffer is narrowed, this command uses the beginning of the
accessible part of the buffer.

Push mark at previous position, unless either a \\[universal-argument] prefix
is supplied, or Transient Mark mode is enabled and the mark is active."
  (declare (interactive-only "use `(goto-char (point-min))' instead."))
  (interactive "^P")
  (or (consp arg)
      (region-active-p)
      (push-mark))
  (let ((size (- (point-max) (point-min))))
    (goto-char (if (and arg (not (consp arg)))
		   (+ (point-min) 1
		      (/ (* size (prefix-numeric-value arg)) 10))
		 (point-min))))
  (if (and arg (not (consp arg))) (forward-line 1)))

(defun end-of-buffer (&optional arg)
  "Move point to the end of the buffer.
With numeric arg N, put point N/10 of the way from the end.
If the buffer is narrowed, this command uses the end of the
accessible part of the buffer.

Push mark at previous position, unless either a \\[universal-argument] prefix
is supplied, or Transient Mark mode is enabled and the mark is active."
  (declare (interactive-only "use `(goto-char (point-max))' instead."))
  (interactive "^P")
  (or (consp arg) (region-active-p) (push-mark))
  (let ((size (- (point-max) (point-min))))
    (goto-char (if (and arg (not (consp arg)))
		   (- (point-max)
		      (/ (* size (prefix-numeric-value arg)) 10))
		 (point-max))))
  ;; If we went to a place in the middle of the buffer,
  ;; adjust it to the beginning of a line.
  (cond ((and arg (not (consp arg))) (forward-line 1))
	((and (eq (current-buffer) (window-buffer))
              (> (point) (window-end nil t)))
	 ;; If the end of the buffer is not already on the screen,
	 ;; then scroll specially to put it near, but not at, the bottom.
	 (overlay-recenter (point))
	 ;; FIXME: Arguably if `scroll-conservatively' is set, then
         ;; we should pass -1 to `recenter'.
	 (recenter (if (and scroll-minibuffer-conservatively
	                    (window-minibuffer-p))
	               -1 -3)))))

(defcustom delete-active-region t
  "Whether single-char deletion commands delete an active region.
This has an effect only if Transient Mark mode is enabled, and
affects `delete-forward-char' and `delete-backward-char', though
not `delete-char'.

If the value is the symbol `kill', the active region is killed
instead of deleted."
  :type '(choice (const :tag "Delete active region" t)
                 (const :tag "Kill active region" kill)
                 (const :tag "Do ordinary deletion" nil))
  :group 'killing
  :version "24.1")

(setq region-extract-function
      (lambda (method)
        ;; This call either signals an error (if there is no region)
        ;; or returns a number.
        (let ((beg (region-beginning)))
          (cond
           ((eq method 'bounds)
            (list (cons beg (region-end))))
           ((eq method 'delete-only)
            (delete-region beg (region-end)))
           (t
            (filter-buffer-substring beg (region-end) method))))))

(defvar region-insert-function
  (lambda (lines)
    (let ((first t))
      (while lines
        (or first
            (insert ?\n))
        (insert-for-yank (car lines))
        (setq lines (cdr lines)
              first nil))))
  "Function to insert the region's content.
Called with one argument LINES.
Insert the region as a list of lines.")

(defun delete-backward-char (n &optional killflag)
  "Delete the previous N characters (following if N is negative).
If Transient Mark mode is enabled, the mark is active, and N is 1,
delete the text in the region and deactivate the mark instead.
To disable this, set option `delete-active-region' to nil.

Optional second arg KILLFLAG, if non-nil, means to kill (save in
kill ring) instead of delete.  If called interactively, a numeric
prefix argument specifies N, and KILLFLAG is also set if a prefix
argument is used.

When killing, the killed text is filtered by
`filter-buffer-substring' before it is saved in the kill ring, so
the actual saved text might be different from what was killed.

In Overwrite mode, single character backward deletion may replace
tabs with spaces so as to back over columns, unless point is at
the end of the line."
  (declare (interactive-only delete-char))
  (interactive "p\nP")
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (cond ((and (use-region-p)
	      delete-active-region
	      (= n 1))
	 ;; If a region is active, kill or delete it.
	 (if (eq delete-active-region 'kill)
	     (kill-region (region-beginning) (region-end) 'region)
           (funcall region-extract-function 'delete-only)))
	;; In Overwrite mode, maybe untabify while deleting
	((null (or (null overwrite-mode)
		   (<= n 0)
		   (memq (char-before) '(?\t ?\n))
		   (eobp)
		   (eq (char-after) ?\n)))
	 (let ((ocol (current-column)))
           (delete-char (- n) killflag)
	   (save-excursion
	     (insert-char ?\s (- ocol (current-column)) nil))))
	;; Otherwise, do simple deletion.
	(t (delete-char (- n) killflag))))

(defun delete-forward-char (n &optional killflag)
  "Delete the following N characters (previous if N is negative).
If Transient Mark mode is enabled, the mark is active, and N is 1,
delete the text in the region and deactivate the mark instead.
To disable this, set variable `delete-active-region' to nil.

If N is positive, characters composed into a single grapheme cluster
count as a single character and are deleted together.  Thus,
\"\\[universal-argument] 2 \\[delete-forward-char]\" when two grapheme clusters follow point will
delete the characters composed into both of the grapheme clusters.

Optional second arg KILLFLAG non-nil means to kill (save in kill
ring) instead of delete.  If called interactively, a numeric
prefix argument specifies N, and KILLFLAG is also set if a prefix
argument is used.

When killing, the killed text is filtered by
`filter-buffer-substring' before it is saved in the kill ring, so
the actual saved text might be different from what was killed."
  (declare (interactive-only delete-char))
  (interactive "p\nP")
  (unless (integerp n)
    (signal 'wrong-type-argument (list 'integerp n)))
  (cond ((and (use-region-p)
	      delete-active-region
	      (= n 1))
	 ;; If a region is active, kill or delete it.
	 (if (eq delete-active-region 'kill)
	     (kill-region (region-beginning) (region-end) 'region)
	   (funcall region-extract-function 'delete-only)))

	;; For forward deletion, treat composed characters as a single
	;; character to delete.
        ((>= n 1)
         (let ((pos (point))
               start cmp)
           (setq start pos)
           (while (> n 0)
             ;; 'find-composition' will return (FROM TO ....) or nil.
             (setq cmp (find-composition pos))
             (setq pos
                   (if cmp
                       (let ((from (car cmp))
                             (to (cadr cmp)))
                         (cond
                          ((and (= (length cmp) 3) ; static composition
                                (booleanp (nth 2 cmp)))
                           to)
                          ;; TO can be at POS, in which case we want
                          ;; to make sure we advance at least by 1
                          ;; character.
                          ((<= to pos)
                           (1+ pos))
                          (t
                           (lgstring-glyph-boundary (nth 2 cmp)
                                                    from (1+ pos)))))
                     (1+ pos)))
             (setq n (1- n)))
           (delete-char (- pos start) killflag)))

	;; Otherwise, do simple deletion.
	(t (delete-char n killflag))))

(defun mark-whole-buffer ()
  "Put point at beginning and mark at end of buffer.
Also push mark at point before pushing mark at end of buffer.
If narrowing is in effect, uses only the accessible part of the buffer.
You probably should not use this function in Lisp programs;
it is usually a mistake for a Lisp function to use any subroutine
that uses or sets the mark."
  (declare (interactive-only t))
  (interactive)
  (push-mark)
  (push-mark (point-max) nil t)
  ;; This is really `point-min' in most cases, but if we're in the
  ;; minibuffer, this is at the end of the prompt.
  (goto-char (minibuffer-prompt-end)))

;; Counting lines, one way or another.

(defcustom goto-line-history-local nil
  "If this option is nil, `goto-line-history' is shared between all buffers.
If it is non-nil, each buffer has its own value of this history list.

Note that on changing from non-nil to nil, the former contents of
`goto-line-history' for each buffer are discarded on use of
`goto-line' in that buffer."
  :group 'editing
  :type 'boolean
  :safe #'booleanp
  :version "28.1")

(defvar goto-line-history nil
  "History of values entered with `goto-line'.")

(defun goto-line-read-args (&optional relative)
  "Read arguments for `goto-line' related commands."
  (if (and current-prefix-arg (not (consp current-prefix-arg)))
      (list (prefix-numeric-value current-prefix-arg))
    ;; Look for a default, a number in the buffer at point.
    (let* ((number (number-at-point))
           (default (and (natnump number) number))
           ;; Decide if we're switching buffers.
           (buffer
            (if (consp current-prefix-arg)
                (other-buffer (current-buffer) t)))
           (buffer-prompt
            (if buffer
                (concat " in " (buffer-name buffer))
              "")))
      ;; Has the buffer locality of `goto-line-history' changed?
      (cond ((and goto-line-history-local (not (local-variable-p 'goto-line-history)))
             (make-local-variable 'goto-line-history))
            ((and (not goto-line-history-local) (local-variable-p 'goto-line-history))
             (kill-local-variable 'goto-line-history)))
      ;; Read the argument, offering that number (if any) as default.
      (list (read-number (format "Goto%s line%s: "
                                 (if (buffer-narrowed-p)
                                     (if relative " relative" " absolute")
                                   "")
                                 buffer-prompt)
                         (list default (if (or relative (not (buffer-narrowed-p)))
                                           (line-number-at-pos)
                                         (save-restriction
                                           (widen)
                                           (line-number-at-pos))))
                         'goto-line-history)
            buffer))))

(defun goto-line (line &optional buffer relative)
  "Go to LINE, counting from line 1 at beginning of buffer.
If called interactively, a numeric prefix argument specifies
LINE; without a numeric prefix argument, read LINE from the
minibuffer.

If optional argument BUFFER is non-nil, switch to that buffer and
move to line LINE there.  If called interactively with \\[universal-argument]
as argument, BUFFER is the most recently selected other buffer.

If optional argument RELATIVE is non-nil, counting starts at the beginning
of the accessible portion of the (potentially narrowed) buffer.

If the variable `widen-automatically' is non-nil, cancel narrowing and
leave all lines accessible.  If `widen-automatically' is nil, just move
point to the edge of visible portion and don't change the buffer bounds.

Prior to moving point, this function sets the mark (without
activating it), unless Transient Mark mode is enabled and the
mark is already active.

This function is usually the wrong thing to use in a Lisp program.
What you probably want instead is something like:
  (goto-char (point-min))
  (forward-line (1- N))
If at all possible, an even better solution is to use char counts
rather than line counts."
  (declare (interactive-only forward-line))
  (interactive (goto-line-read-args))
  ;; Switch to the desired buffer, one way or another.
  (if buffer
      (let ((window (get-buffer-window buffer)))
	(if window (select-window window)
	  (switch-to-buffer-other-window buffer))))
  ;; Leave mark at previous position
  (or (region-active-p) (push-mark))
  ;; Move to the specified line number in that buffer.
  (let ((pos (save-restriction
               (unless relative (widen))
               (goto-char (point-min))
               (if (eq selective-display t)
                   (re-search-forward "[\n\C-m]" nil 'end (1- line))
                 (forward-line (1- line)))
               (point))))
    (when (and (not relative)
               (buffer-narrowed-p)
               widen-automatically
               ;; Position is outside narrowed part of buffer
               (or (> (point-min) pos) (> pos (point-max))))
      (widen))
    (goto-char pos)))

(defun goto-line-relative (line &optional buffer)
  "Go to LINE, counting from line at (point-min).
The line number is relative to the accessible portion of the narrowed
buffer.  The argument BUFFER is the same as in the function `goto-line'."
  (declare (interactive-only forward-line))
  (interactive (goto-line-read-args t))
  (with-suppressed-warnings ((interactive-only goto-line))
    (goto-line line buffer t)))

(defun count-words-region (start end &optional arg)
  "Count the number of words in the region.
If called interactively, print a message reporting the number of
lines, words, and characters in the region (whether or not the
region is active); with prefix ARG, report for the entire buffer
rather than the region.

If called from Lisp, return the number of words between positions
START and END."
  (interactive (if current-prefix-arg
		   (list nil nil current-prefix-arg)
		 (list (region-beginning) (region-end) nil)))
  (cond ((not (called-interactively-p 'any))
	 (count-words start end))
	(arg
	 (message "%s" (count-words--buffer-format)))
	(t
	 (message "%s" (count-words--format "Region" start end)))))

(defun count-words (start end &optional totals)
  "Count words between START and END.
If called interactively, START and END are normally the start and
end of the buffer; but if the region is active, START and END are
the start and end of the region.  Print a message reporting the
number of lines, sentences, words, and chars.  With prefix
argument, also include the data for the entire (un-narrowed)
buffer.

If called from Lisp, return the number of words between START and
END, without printing any message.  TOTALS is ignored when called
from Lisp."
  (interactive (list nil nil current-prefix-arg))
  ;; When called from Lisp, return the data.
  (if (not (called-interactively-p 'any))
      (let ((words 0)
            ;; Count across field boundaries. (Bug#41761)
            (inhibit-field-text-motion t))
	(save-excursion
	  (save-restriction
	    (narrow-to-region start end)
	    (goto-char (point-min))
	    (while (forward-word-strictly 1)
	      (setq words (1+ words)))))
	words)
    ;; When called interactively, message the data.
    (let ((totals (if (and totals
                           (or (use-region-p)
                               (buffer-narrowed-p)))
                      (save-restriction
                        (widen)
                        (count-words--format "; buffer in total"
                                             (point-min) (point-max)))
                    "")))
      (if (use-region-p)
	  (message "%s%s" (count-words--format
                           "Region" (region-beginning) (region-end))
                   totals)
        (message "%s%s" (count-words--buffer-format) totals)))))

(defun count-words--buffer-format ()
  (count-words--format
   (if (buffer-narrowed-p) "Narrowed part of buffer" "Buffer")
   (point-min) (point-max)))

(defun count-words--format (str start end)
  (let ((lines (count-lines start end))
	(sentences (count-sentences start end))
	(words (count-words start end))
	(chars (- end start)))
    (format "%s has %d line%s, %d sentence%s, %d word%s, and %d character%s"
	     str
	     lines (if (= lines 1) "" "s")
	     sentences (if (= sentences 1) "" "s")
	     words (if (= words 1) "" "s")
	     chars (if (= chars 1) "" "s"))))

(defun what-line ()
  "Print the current buffer line number and narrowed line number of point."
  (interactive)
  (let ((start (point-min))
	(n (line-number-at-pos)))
    (if (= start 1)
	(message "Line %d" n)
      (save-excursion
	(save-restriction
	  (widen)
	  (message "line %d (narrowed line %d)"
		   (+ n (line-number-at-pos start) -1) n))))))

(defun count-lines (start end &optional ignore-invisible-lines)
  "Return number of lines between START and END.
This is usually the number of newlines between them, but can be
one more if START is not equal to END and the greater of them is
not at the start of a line.

When IGNORE-INVISIBLE-LINES is non-nil, invisible lines are not
included in the count."
  (declare (ftype (function ((or integer marker) (or integer marker) &optional t)
                           integer))
           (side-effect-free t))
  (save-excursion
    (save-restriction
      (narrow-to-region start end)
      (cond ((and (not ignore-invisible-lines)
                  (eq selective-display t))
             (goto-char (point-min))
	     (save-match-data
	       (let ((done 0))
		 (while (re-search-forward "\n\\|\r[^\n]" nil t 40)
		   (setq done (+ 40 done)))
		 (while (re-search-forward "\n\\|\r[^\n]" nil t 1)
		   (setq done (+ 1 done)))
		 (goto-char (point-max))
		 (if (and (/= start end)
			  (not (bolp)))
		     (1+ done)
		   done))))
	    (ignore-invisible-lines
             (goto-char (point-min))
	     (save-match-data
	       (- (buffer-size)
                  (forward-line (buffer-size))
		  (let ((invisible-count 0)
		        prop)
		    (goto-char (point-min))
		    (while (re-search-forward "\n\\|\r[^\n]" nil t)
		      (setq prop (get-char-property (1- (point)) 'invisible))
		      (if (if (eq buffer-invisibility-spec t)
			      prop
			    (or (memq prop buffer-invisibility-spec)
			        (assq prop buffer-invisibility-spec)))
			  (setq invisible-count (1+ invisible-count))))
		    invisible-count))))
	    (t
             (goto-char (point-max))
             (if (bolp)
                 (1- (line-number-at-pos))
               (line-number-at-pos)))))))

(defcustom what-cursor-show-names nil
  "Whether to show character names in `what-cursor-position'."
  :type 'boolean
  :version "27.1"
  :group 'editing-basics)

(defun what-cursor-position (&optional detail)
  "Print info on cursor position (on screen and within buffer).
Also describe the character after point, and give its character
code in octal, decimal and hex.  If `what-cursor-show-names' is
non-nil, additionally show the name of the character.

For a non-ASCII multibyte character, also give its encoding in the
buffer's selected coding system if the coding system encodes the
character safely.  If the character is encoded into one byte, that
code is shown in hex.  If the character is encoded into more than one
byte, just \"...\" is shown.

In addition, with prefix argument, show details about that character
in *Help* buffer.  See also the command `describe-char'."
  (interactive "P")
  (let* ((char (following-char))
         (char-name (and what-cursor-show-names
                         (char-to-name char)))
         (char-name-fmt (if char-name
                            (format ", %s" char-name)
                          ""))
	 (bidi-fixer
	  ;; If the character is one of LRE, LRO, RLE, RLO, it will
	  ;; start a directional embedding, which could completely
	  ;; disrupt the rest of the line (e.g., RLO will display the
	  ;; rest of the line right-to-left).  So we put an invisible
	  ;; PDF character after these characters, to end the
	  ;; embedding, which eliminates any effects on the rest of
	  ;; the line.  For RLE and RLO we also append an invisible
	  ;; LRM, to avoid reordering the following numerical
	  ;; characters.  For LRI/RLI/FSI we append a PDI.
	  (cond ((memq char '(?\x202a ?\x202d))
		 (propertize (string ?\x202c) 'invisible t))
		((memq char '(?\x202b ?\x202e))
		 (propertize (string ?\x202c ?\x200e) 'invisible t))
		((memq char '(?\x2066 ?\x2067 ?\x2068))
		 (propertize (string ?\x2069) 'invisible t))
		;; Strong right-to-left characters cause reordering of
		;; the following numerical characters which show the
		;; codepoint, so append LRM to countermand that.
		((memq (get-char-code-property char 'bidi-class) '(R AL))
		 (propertize (string ?\x200e) 'invisible t))
		(t
		 "")))
	 (beg (point-min))
	 (end (point-max))
         (pos (point))
	 (total (buffer-size))
	 (percent (round (* 100.0 (1- pos)) (max 1 total)))
	 (hscroll (if (= (window-hscroll) 0)
		      ""
		    (format " Hscroll=%d" (window-hscroll))))
	 (col (current-column)))
    (if (= pos end)
	(if (or (/= beg 1) (/= end (1+ total)))
	    (message "point=%d of %d (%d%%) <%d-%d> column=%d%s"
		     pos total percent beg end col hscroll)
	  (message "point=%d of %d (EOB) column=%d%s"
		   pos total col hscroll))
      (let ((coding buffer-file-coding-system)
	    encoded encoding-msg display-prop under-display)
	(if (or (not coding)
		(eq (coding-system-type coding) t))
	    (setq coding (or (default-value 'buffer-file-coding-system)
                             ;; A nil value of `buffer-file-coding-system'
                             ;; means "no conversion" which means each byte
                             ;; is a char and vice versa.
                             'binary)))
	(if (eq (char-charset char) 'eight-bit)
	    (setq encoding-msg
		  (format "(%d, #o%o, #x%x%s, raw-byte)" char char char char-name-fmt))
	  ;; Check if the character is displayed with some `display'
	  ;; text property.  In that case, set under-display to the
	  ;; buffer substring covered by that property.
	  (setq display-prop (get-char-property pos 'display))
	  (if display-prop
	      (let ((to (or (next-single-char-property-change pos 'display)
			    (point-max))))
		(if (< to (+ pos 4))
		    (setq under-display "")
		  (setq under-display "..."
			to (+ pos 4)))
		(setq under-display
		      (concat (buffer-substring-no-properties pos to)
			      under-display)))
	    (setq encoded (and (>= char 128) (encode-coding-char char coding))))
	  (setq encoding-msg
		(if display-prop
		    (if (not (stringp display-prop))
			(format "(%d, #o%o, #x%x%s, part of display \"%s\")"
				char char char char-name-fmt under-display)
		      (format "(%d, #o%o, #x%x%s, part of display \"%s\"->\"%s\")"
			      char char char char-name-fmt under-display display-prop))
		  (if encoded
		      (format "(%d, #o%o, #x%x%s, file %s)"
			      char char char char-name-fmt
			      (if (> (length encoded) 1)
				  "..."
				(encoded-string-description encoded coding)))
		    (format "(%d, #o%o, #x%x%s)" char char char char-name-fmt)))))
	(if detail
	    ;; We show the detailed information about CHAR.
	    (describe-char (point)))
	(if (or (/= beg 1) (/= end (1+ total)))
	    (message "Char: %s%s %s point=%d of %d (%d%%) <%d-%d> column=%d%s"
		     (if (< char 256)
			 (single-key-description char)
		       (buffer-substring-no-properties (point) (1+ (point))))
		     bidi-fixer
		     encoding-msg pos total percent beg end col hscroll)
	  (message "Char: %s%s %s point=%d of %d (%d%%) column=%d%s"
		   (if enable-multibyte-characters
		       (if (< char 128)
			   (single-key-description char)
			 (buffer-substring-no-properties (point) (1+ (point))))
		     (single-key-description char))
		   bidi-fixer encoding-msg pos total percent col hscroll))))))

;; Initialize read-expression-map.  It is defined at C level.
(defvar-keymap read-expression-map
  :parent minibuffer-local-map
  "C-M-i" #'completion-at-point
  ;; Might as well bind TAB to completion, since inserting a TAB char is
  ;; much too rarely useful.
  "TAB" #'completion-at-point
  "M-g M-c" #'read-expression-switch-to-completions)

(defvar-keymap read--expression-map
  :doc "Keymap used by `read--expression'."
  :parent read-expression-map
  "RET" #'read--expression-try-read
  "C-j" #'read--expression-try-read)

(defun read-minibuffer (prompt &optional initial-contents)
  "Return a Lisp object read using the minibuffer, unevaluated.
Prompt with PROMPT.  If non-nil, optional second arg INITIAL-CONTENTS
is a string to insert in the minibuffer before reading.
\(INITIAL-CONTENTS can also be a cons of a string and an integer.
Such arguments are used as in `read-from-minibuffer'.)"
  ;; Used for interactive spec `x'.
  (read-from-minibuffer prompt initial-contents minibuffer-local-map
                        t 'minibuffer-history))

(defun eval-minibuffer (prompt &optional initial-contents)
  "Return value of Lisp expression read using the minibuffer.
Prompt with PROMPT.  If non-nil, optional second arg INITIAL-CONTENTS
is a string to insert in the minibuffer before reading.
\(INITIAL-CONTENTS can also be a cons of a string and an integer.
Such arguments are used as in `read-from-minibuffer'.)"
  ;; Used for interactive spec `X'.
  (eval (read--expression prompt initial-contents)))

(defvar minibuffer-default nil
  "The current default value or list of default values in the minibuffer.
The functions `read-from-minibuffer' and `completing-read' bind
this variable locally.")

(defcustom eval-expression-print-level 4
  "Value for `print-level' while printing value in `eval-expression'.
A value of nil means no limit."
  :group 'lisp
  :type '(choice (const :tag "No Limit" nil) integer)
  :version "21.1")

(defcustom eval-expression-print-length 12
  "Value for `print-length' while printing value in `eval-expression'.
A value of nil means no limit."
  :group 'lisp
  :type '(choice (const :tag "No Limit" nil) integer)
  :version "21.1")

(defcustom eval-expression-debug-on-error t
  "If non-nil set `debug-on-error' to t in `eval-expression'.
If nil, don't change the value of `debug-on-error'."
  :group 'lisp
  :type 'boolean
  :version "21.1")

(defcustom eval-expression-print-maximum-character 127
  "The largest integer that will be displayed as a character.
This affects printing by `eval-expression' (via
`eval-expression-print-format')."
  :group 'lisp
  :type `(choice (const :tag "ASCII characters" 127)
                 (const :tag "All characters" ,(max-char))
                 (integer :tag "Max codepoint to display as character"))
  :version "26.1")

(defun eval-expression-print-format (value)
  "If VALUE is an integer, return a specially formatted string.
This string will typically look like \" (#o1, #x1, ?\\C-a)\".
If VALUE is not an integer, return nil.
This function is used by commands like `eval-expression' that
display the result of expression evaluation."
  (when (integerp value)
    (let ((char-string
           (and (characterp value)
                (<= value eval-expression-print-maximum-character)
                (char-displayable-p value)
                (prin1-char value))))
      (if char-string
          (format " (#o%o, #x%x, %s)" value value char-string)
        (format " (#o%o, #x%x)" value value)))))

(defvar eval-expression-minibuffer-setup-hook nil
  "Hook run by `eval-expression' when entering the minibuffer.")

(defun read--expression (prompt &optional initial-contents)
  "Read an Emacs Lisp expression from the minibuffer.

PROMPT and optional argument INITIAL-CONTENTS do the same as in
function `read-from-minibuffer'."
  (minibuffer-with-setup-hook
      (lambda ()
        ;; FIXME: instead of just applying the syntax table, maybe
        ;; use a special major mode tailored to reading Lisp
        ;; expressions from the minibuffer? (`emacs-lisp-mode'
        ;; doesn't preserve the necessary keybindings.)
        (set-syntax-table emacs-lisp-mode-syntax-table)
        (add-hook 'completion-at-point-functions
                  #'elisp-completion-at-point nil t)
        (setq-local trusted-content :all)
        (run-hooks 'eval-expression-minibuffer-setup-hook))
    (read-from-minibuffer prompt initial-contents
                          read--expression-map t
                          'read-expression-history)))

(defun read--expression-try-read ()
  "Try to read an Emacs Lisp expression in the minibuffer.

Exit the minibuffer if successful, else report the error to the
user and move point to the location of the error.  If point is
not already at the location of the error, push a mark before
moving point."
  (interactive)
  (unless (> (minibuffer-depth) 0)
    (error "Minibuffer must be active"))
  (if (let* ((contents (minibuffer-contents))
             (error-point nil))
        (with-temp-buffer
          (condition-case err
              (progn
                (insert contents)
                (goto-char (point-min))
                ;; `read' will signal errors like "End of file during
                ;; parsing" and "Invalid read syntax".
                (read (current-buffer))
                ;; Since `read' does not signal the "Trailing garbage
                ;; following expression" error, we check for trailing
                ;; garbage ourselves.
                (or (progn
                      ;; This check is similar to what `string_to_object'
                      ;; does in minibuf.c.
                      (skip-chars-forward " \t\n")
                      (= (point) (point-max)))
                    (error "Trailing garbage following expression")))
            (error
             (setq error-point (+ (length (minibuffer-prompt)) (point)))
             (with-current-buffer (window-buffer (minibuffer-window))
               (unless (= (point) error-point)
                 (push-mark))
               (goto-char error-point)
               (minibuffer-message (error-message-string err)))
             nil))))
      (exit-minibuffer)))

(defun eval-expression-get-print-arguments (prefix-argument)
  "Get arguments for commands that print an expression result.
Returns a list (INSERT-VALUE NO-TRUNCATE CHAR-PRINT-LIMIT) based
on PREFIX-ARGUMENT.  This function determines the interpretation
of the prefix argument for `eval-expression' and
`eval-last-sexp'."
  (let ((num (prefix-numeric-value prefix-argument)))
    (list (not (memq prefix-argument '(- nil)))
          (= num 0)
          (cond ((not (memq prefix-argument '(0 -1 - nil))) nil)
                ((= num -1) most-positive-fixnum)
                (t eval-expression-print-maximum-character)))))

(defun eval-expression--debug (err)
  (funcall debugger 'error err :backtrace-base #'eval-expression--debug))

;; We define this, rather than making `eval' interactive,
;; for the sake of completion of names like eval-region, eval-buffer.
(defun eval-expression (exp &optional insert-value no-truncate char-print-limit)
  "Evaluate EXP and print value in the echo area.
When called interactively, read an Emacs Lisp expression and
evaluate it.  Value is also consed on to front of the variable
`values'.  Optional argument INSERT-VALUE non-nil (interactively,
with a non `-' prefix argument) means insert the result into the
current buffer instead of printing it in the echo area.

Normally, this function truncates long output according to the
value of the variables `eval-expression-print-length' and
`eval-expression-print-level'.  When NO-TRUNCATE is
non-nil (interactively, with a prefix argument of zero), however,
there is no such truncation.

If the resulting value is an integer, and CHAR-PRINT-LIMIT is
non-nil (interactively, unless given a non-zero prefix argument)
it will be printed in several additional formats (octal,
hexadecimal, and character).  The character format is used only
if the value is below CHAR-PRINT-LIMIT (interactively, if the
prefix argument is -1 or the value doesn't exceed
`eval-expression-print-maximum-character').

Runs the hook `eval-expression-minibuffer-setup-hook' on entering the
minibuffer.

If `eval-expression-debug-on-error' is non-nil, which is the default,
this command arranges for all errors to enter the debugger."
  (interactive
   (cons (read--expression "Eval: ")
         (eval-expression-get-print-arguments current-prefix-arg)))

  (let* (result
         (runfun
          (lambda ()
            (setq result
                  (values--store-value
                   (eval (let ((lexical-binding t)) (macroexpand-all exp))
                         t))))))
    (if (null eval-expression-debug-on-error)
        (funcall runfun)
      (handler-bind ((error #'eval-expression--debug))
        (funcall runfun)))

    (let ((print-length (unless no-truncate eval-expression-print-length))
          (print-level  (unless no-truncate eval-expression-print-level))
          (eval-expression-print-maximum-character char-print-limit)
          (deactivate-mark))
      (let ((out (if insert-value (current-buffer) t)))
        (prog1
            (prin1 result out)
          (let ((str (and char-print-limit
                          (eval-expression-print-format result))))
            (when str (princ str out))))))))

(defun edit-and-eval-command (prompt command)
  "Prompting with PROMPT, let user edit COMMAND and eval result.
COMMAND is a Lisp expression.  Let user edit that expression in
the minibuffer, then read and evaluate the result."
  (let ((command
	 (let ((print-level nil)
	       (minibuffer-history-sexp-flag (1+ (minibuffer-depth))))
	   (unwind-protect
	       (read-from-minibuffer prompt
				     (prin1-to-string command)
				     read-expression-map t
				     'command-history)
	     ;; If command was added to command-history as a string,
	     ;; get rid of that.  We want only evaluable expressions there.
             (when (stringp (car command-history))
               (pop command-history))))))

    (add-to-history 'command-history command)
    (eval command)))

(defun repeat-complex-command (arg)
  "Edit and re-evaluate last complex command, or ARGth from last.
A complex command is one that used the minibuffer.
The command is placed in the minibuffer as a Lisp form for editing.
The result is executed, repeating the command as changed.
If the command has been changed or is not the most recent previous
command it is added to the front of the command history.
You can use the minibuffer history commands \
\\<minibuffer-local-map>\\[next-history-element] and \\[previous-history-element]
to get different commands to edit and resubmit."
  (interactive "p")
  (let ((elt (nth (1- arg) command-history))
	newcmd)
    (if elt
	(progn
	  (setq newcmd
		(let ((print-level nil)
		      (minibuffer-history-position arg)
		      (minibuffer-history-sexp-flag (1+ (minibuffer-depth))))
		  (unwind-protect
		      (read-from-minibuffer
		       "Redo: " (prin1-to-string elt) read-expression-map t
		       (cons 'command-history arg))

		    ;; If command was added to command-history as a
		    ;; string, get rid of that.  We want only
		    ;; evaluable expressions there.
                    (when (stringp (car command-history))
                      (pop command-history)))))

          (add-to-history 'command-history newcmd)
          (apply #'funcall-interactively
		 (car newcmd)
		 (mapcar (lambda (e) (eval e t)) (cdr newcmd))))
      (if command-history
	  (error "Argument %d is beyond length of command history" arg)
	(error "There are no previous complex commands to repeat")))))


(defvar extended-command-history nil)
(defvar execute-extended-command--last-typed nil)

(defcustom read-extended-command-predicate nil
  "Predicate to use to determine which commands to include when completing.
If it's nil, include all the commands.
If it's a function, it will be called with two parameters: the
symbol of the command and the current buffer.  The predicate should
return non-nil if the command should be considered as a completion
candidate for \\`M-x' in that buffer.

Several predicate functions suitable for various optional behaviors
are available:

  `command-completion-default-include-p'
         This excludes from completion candidates those commands
         which have been marked specific to modes other than the
         current buffer's mode.  Commands that are not specific
         to any mode are included.  If a command has a
         `(declare completion...' form which specifies a predicate,
         that predicate will be called to determine whether to
         include the command in the completion candidates.

  `command-completion-using-modes-p'
         This includes in completion candidates only commands
         marked as specific to the current buffer's mode.

  `command-completion-using-modes-and-keymaps-p'
         This includes commands marked as specific to the current
         buffer's modes and commands that have keybindings in the
         current buffer's active local keymaps.  It also includes
         several commands, like Customize commands, which should
         always be available."
  :version "28.1"
  :group 'completion
  :type '(choice (const :tag "Don't exclude any commands" nil)
                 (const :tag "Exclude commands irrelevant to current buffer's mode"
                        command-completion-default-include-p)
                 (const :tag "Include only commands relevant to current buffer's mode"
                        command-completion-using-modes-p)
                 (const :tag "Commands relevant to current buffer's mode or bound in its keymaps"
                        command-completion-using-modes-and-keymaps-p)
                 (function :tag "Other predicate function")))

(defun execute-extended-command-cycle ()
  "Choose the next version of the extended command predicates.
See `extended-command-versions'."
  (interactive)
  (throw 'cycle
         (cons (minibuffer-contents)
               (- (point) (minibuffer-prompt-end)))))

(defvar extended-command-versions
  (list (list "M-x " (lambda () read-extended-command-predicate))
        (list "M-X " #'command-completion--command-for-this-buffer-function))
  "Alist of prompts and what the extended command predicate should be.
This is used by the \\<minibuffer-local-must-match-map>\\[execute-extended-command-cycle] command when reading an extended command.")

(defvar-keymap read-extended-command-mode-map
  :doc "Local keymap added to the current map when reading an extended command."
  "M-X" #'execute-extended-command-cycle)

(define-minor-mode read-extended-command-mode
  "Minor mode used for completion in `read-extended-command'.")

(defun read-extended-command (&optional prompt)
  "Read and return name of command to invoke via `execute-extended-command'.
Use `read-extended-command-predicate' to determine which commands
to include among completion candidates.

This function activates the `read-extended-command-mode' minor
mode when reading the command name."
  (let ((default-predicate read-extended-command-predicate)
        (read-extended-command-predicate read-extended-command-predicate)
        already-typed ret)
    ;; If we have a prompt (which is the name of the version of the
    ;; command), then set up the predicate from
    ;; `extended-command-versions'.
    (if (not prompt)
        (setq prompt (caar extended-command-versions))
      (setq read-extended-command-predicate
            (funcall (cadr (assoc prompt extended-command-versions)))))
    ;; Normally this will only execute once.
    (while (not (stringp ret))
      (when (consp (setq ret (catch 'cycle
                               (read-extended-command-1 prompt
                                                        already-typed))))
        ;; But if the user hit `M-X', then we `throw'ed out to that
        ;; `catch', and we cycle to the next setting.
        (let ((next (or (cadr (memq (assoc prompt extended-command-versions)
                                    extended-command-versions))
                        ;; Last one; cycle back to the first.
                        (car extended-command-versions))))
          ;; Restore the user's default predicate.
          (setq read-extended-command-predicate default-predicate)
          ;; Then calculate the next.
          (setq prompt (car next)
                read-extended-command-predicate (funcall (cadr next))
                already-typed ret))))
    ret))

(defun read-extended-command-1 (prompt initial-input)
  (let ((buffer (current-buffer)))
    (minibuffer-with-setup-hook
        (lambda ()
          (add-hook 'post-self-insert-hook
                    (lambda ()
                      (setq execute-extended-command--last-typed
                            (minibuffer-contents)))
                    nil 'local)
          ;; This is so that we define the `M-X' toggling command.
          (read-extended-command-mode)
          (setq-local minibuffer-default-add-function
	              (lambda ()
	                ;; Get a command name at point in the original buffer
	                ;; to propose it after M-n.
	                (let ((def
                               (with-current-buffer
			           (window-buffer (minibuffer-selected-window))
			         (and (commandp (function-called-at-point))
				      (format
                                       "%S" (function-called-at-point)))))
		              (all (sort (minibuffer-default-add-completions)
                                         #'string<)))
		          (if def
		              (cons def (delete def all))
		            all)))))
      ;; Read a string, completing from and restricting to the set of
      ;; all defined commands.  Save the command read on the
      ;; extended-command history list.
      (completing-read
       (concat (cond
	        ((eq current-prefix-arg '-) "- ")
	        ((and (consp current-prefix-arg)
		      (eq (car current-prefix-arg) 4))
		 "C-u ")
	        ((and (consp current-prefix-arg)
		      (integerp (car current-prefix-arg)))
	         (format "%d " (car current-prefix-arg)))
	        ((integerp current-prefix-arg)
	         (format "%d " current-prefix-arg)))
	       ;; This isn't strictly correct if `execute-extended-command'
	       ;; is bound to anything else (e.g. [menu]).
	       ;; It could use (key-description (this-single-command-keys)),
	       ;; but actually a prompt other than "M-x" would be confusing,
	       ;; because "M-x" is a well-known prompt to read a command
	       ;; and it serves as a shorthand for "Extended command: ".
               (or prompt "M-x "))
       (lambda (string pred action)
         (if (and suggest-key-bindings (eq action 'metadata))
	     '(metadata
	       (affixation-function . read-extended-command--affixation)
	       (category . command))
           (let ((pred
                  (if (memq action '(nil t))
                      ;; Exclude from completions obsolete commands
                      ;; lacking a `current-name', or where `when' is
                      ;; not the current major version.
                      (lambda (sym)
                        (let ((obsolete (get sym 'byte-obsolete-info)))
                          (and (funcall pred sym)
                               (or (equal string (symbol-name sym))
                                   (not obsolete)
                                   (and
                                    ;; Has a current-name.
                                    (functionp (car obsolete))
                                    ;; when >= emacs-major-version
                                    (condition-case nil
                                        (>= (car (version-to-list
                                                  (caddr obsolete)))
                                            emacs-major-version)
                                      ;; If the obsoletion version isn't
                                      ;; valid, include the command.
                                      (error t)))))))
                    pred)))
             (complete-with-action action obarray string pred))))
       (lambda (sym)
         (and (commandp sym)
              (cond ((null read-extended-command-predicate))
                    ((functionp read-extended-command-predicate)
                     ;; Don't let bugs break M-x completion; interpret
                     ;; them as the absence of a predicate.
                     (condition-case-unless-debug err
                         (funcall read-extended-command-predicate sym buffer)
                       (error (message "read-extended-command-predicate: %s: %s"
                                       sym (error-message-string err))))))))
       t initial-input 'extended-command-history))))

(defun command-completion-using-modes-p (symbol buffer)
  "Say whether SYMBOL has been marked as a mode-specific command in BUFFER."
  ;; Check the modes.
  (when-let* ((modes (command-modes symbol)))
    ;; Common fast case: Just a single mode.
    (if (null (cdr modes))
        (or (provided-mode-derived-p
             (buffer-local-value 'major-mode buffer) (car modes))
            (memq (car modes)
                  (buffer-local-value 'local-minor-modes buffer))
            (memq (car modes) global-minor-modes))
      ;; Uncommon case: Multiple modes.
      (command-completion-with-modes-p modes buffer))))

(defun command-completion-default-include-p (symbol buffer)
  "Say whether SYMBOL should be offered as a completion.
If there's a `completion-predicate' for SYMBOL, the result from
calling that predicate is called.  If there isn't one, this
predicate is true if the command SYMBOL is applicable to the
major mode in BUFFER, or any of the active minor modes in
BUFFER."
  (if (get symbol 'completion-predicate)
      ;; An explicit completion predicate takes precedence.
      (funcall (get symbol 'completion-predicate) symbol buffer)
    (or (null (command-modes symbol))
        (command-completion-using-modes-p symbol buffer))))

(defun command-completion-with-modes-p (modes buffer)
  "Say whether MODES are in action in BUFFER.
This is the case if either the major mode is derived from one of MODES,
or (if one of MODES is a minor mode), if it is switched on in BUFFER."
  (or (provided-mode-derived-p (buffer-local-value 'major-mode buffer) modes)
      ;; It's a minor mode.
      (seq-intersection modes
                        (buffer-local-value 'local-minor-modes buffer)
                        #'eq)
      (seq-intersection modes global-minor-modes #'eq)))

(defun command-completion-using-modes-and-keymaps-p (symbol buffer)
  "Return non-nil if SYMBOL is marked for BUFFER's mode or bound in its keymaps."
  (with-current-buffer buffer
      (let ((keymaps
             ;; The major mode's keymap and any active minor modes.
             (nconc
              (and (current-local-map) (list (current-local-map)))
              (mapcar
               #'cdr
               (seq-filter
                (lambda (elem)
                  (symbol-value (car elem)))
                minor-mode-map-alist)))))
        (or (command-completion-using-modes-p symbol buffer)
            ;; Include commands that are bound in a keymap in the
            ;; current buffer.
            (and (where-is-internal symbol keymaps)
                 ;; But not if they have a command predicate that
                 ;; says that they shouldn't.  (This is the case
                 ;; for `ignore' and `undefined' and similar
                 ;; commands commonly found in keymaps.)
                 (or (null (get symbol 'completion-predicate))
                     (funcall (get symbol 'completion-predicate)
                              symbol buffer)))
            ;; Include customize-* commands (do we need a list of such
            ;; "always available" commands? customizable?)
            (string-match-p "customize-" (symbol-name symbol))))))


(defun command-completion-button-p (category buffer)
  "Return non-nil if there's a button of CATEGORY at point in BUFFER."
  (with-current-buffer buffer
    (and (get-text-property (point) 'button)
         (eq (get-text-property (point) 'category) category))))

(defun read-extended-command--affixation (command-names)
  (with-selected-window (or (minibuffer-selected-window) (selected-window))
    (mapcar
     (lambda (command-name)
       (let* ((fun (and (stringp command-name) (intern-soft command-name)))
              (binding (where-is-internal fun overriding-local-map t))
              (obsolete (get fun 'byte-obsolete-info))
              (alias (symbol-function fun))
              (suffix (cond ((symbolp alias)
                             (format " (%s)" alias))
                            (obsolete
                             (format " (%s)" (car obsolete)))
                            ((and binding (not (stringp binding)))
                             (format " (%s)" (key-description binding)))
                            (t ""))))
         (put-text-property 0 (length suffix)
                            'face 'completions-annotations suffix)
         (list command-name "" suffix)))
     command-names)))

(defcustom suggest-key-bindings t
  "Non-nil means show the equivalent keybinding when \
\\[execute-extended-command] has one.
The value can be a length of time to show the message for.
If the value is non-nil and not a number, we wait 2 seconds.

Also see `extended-command-suggest-shorter'.

Equivalent key-bindings are also shown in the completion list of
\\[execute-extended-command] for all commands that have them."
  :group 'keyboard
  :type '(choice (const :tag "off" nil)
                 (natnum :tag "time" 2)
                 (other :tag "on" t)))

(defcustom extended-command-suggest-shorter t
  "If non-nil, show a shorter \\[execute-extended-command] invocation \
when there is one.

Also see `suggest-key-bindings'."
  :group 'keyboard
  :type 'boolean
  :version "26.1")

(defun execute-extended-command--shorter-1 (name length)
  (cond
   ((zerop length) (list ""))
   ((equal name "") nil)
   (t
    (nconc (mapcar (lambda (s) (concat (substring name 0 1) s))
                   (execute-extended-command--shorter-1
                    (substring name 1) (1- length)))
           (when (string-match "\\`\\(-\\)?[^-]*" name)
             (execute-extended-command--shorter-1
              (substring name (match-end 0)) length))))))

(defun execute-extended-command--shorter (name typed)
  (let ((candidates '())
        commands
        (max (length typed))
        (len 1)
        binding)
    ;; Precompute a list of commands once to avoid repeated `commandp' testing
    ;; of symbols in the `completion-try-completion' call inside the loop below
    (mapatoms (lambda (s) (when (commandp s) (push s commands))))
    (while (and (not binding)
                (progn
                  (unless candidates
                    (setq len (1+ len))
                    (setq candidates (execute-extended-command--shorter-1
                                      name len)))
                  ;; Don't show the help message if the binding isn't
                  ;; significantly shorter than the M-x command the user typed.
                  (< len (- max 5))))
      (input-pending-p)    ;Dummy call to trigger input-processing, bug#23002.
      (let ((candidate (pop candidates)))
        (when (equal name
                     (car-safe (completion-try-completion
                                candidate commands nil len)))
          (setq binding candidate))))
    binding))

(defvar execute-extended-command--binding-timer nil)

(defun execute-extended-command--describe-binding-msg (function binding shorter)
  (format-message "You can run the command `%s' with %s"
                  function
                  (propertize (cond (shorter (concat "M-x " shorter))
                                    ((stringp binding) binding)
                                    (t (key-description binding)))
                              'face 'help-key-binding)))

(defun execute-extended-command (prefixarg &optional command-name typed)
  "Read a command name, then read the arguments and call the command.
To pass a prefix argument to the command you are
invoking, give a prefix argument to `execute-extended-command'.

This command provides completion when reading the command name.
Which completion candidates are shown can be controlled by
customizing `read-extended-command-predicate'."
  (declare (interactive-only command-execute))
  ;; FIXME: Remember the actual text typed by the user before completion,
  ;; so that we don't later on suggest the same shortening.
  (interactive
   (let ((execute-extended-command--last-typed nil))
     (list current-prefix-arg
           (read-extended-command)
           execute-extended-command--last-typed)))
  ;; Emacs<24 calling-convention was with a single `prefixarg' argument.
  (unless command-name
    (let ((current-prefix-arg prefixarg) ; for prompt
          (execute-extended-command--last-typed nil))
      (setq command-name (read-extended-command))
      (setq typed execute-extended-command--last-typed)))
  (let* ((function (and (stringp command-name) (intern-soft command-name)))
         (binding (and suggest-key-bindings
		       (not executing-kbd-macro)
		       (where-is-internal function overriding-local-map t)))
         (delay-before-suggest 0)
         find-shorter shorter)
    (unless (commandp function)
      (error "`%s' is not a valid command name" command-name))
    ;; If we're executing a command that's remapped, we can't actually
    ;; execute that command with the keymapping we've found with
    ;; `where-is-internal'.
    (when (and binding (command-remapping function))
      (setq binding nil))
    ;; Some features, such as novice.el, rely on this-command-keys
    ;; including M-x COMMAND-NAME RET.
    (set--this-command-keys (concat "\M-x" (symbol-name function) "\r"))
    (setq this-command function)
    ;; Normally `real-this-command' should never be changed, but here we really
    ;; want to pretend that M-x <cmd> RET is nothing more than a "key
    ;; binding" for <cmd>, so the command the user really wanted to run is
    ;; `function' and not `execute-extended-command'.  The difference is
    ;; visible in cases such as M-x <cmd> RET and then C-x z (bug#11506).
    (setq real-this-command function)
    (let ((prefix-arg prefixarg))
      (command-execute function 'record))
    ;; Ensure that we never have two of the suggest-binding timers in
    ;; flight.
    (when execute-extended-command--binding-timer
      (cancel-timer execute-extended-command--binding-timer))
    (when (and suggest-key-bindings
               (or binding
                   (and extended-command-suggest-shorter typed)))
      ;; If this command displayed something in the echo area, then
      ;; postpone the display of our suggestion message a bit.
      (setq delay-before-suggest
            (cond
             ((zerop (length (current-message))) 0)
             ((numberp suggest-key-bindings) suggest-key-bindings)
             (t 2)))
      (when (and extended-command-suggest-shorter
                 (not binding)
                 (not executing-kbd-macro)
                 (symbolp function)
                 (> (length (symbol-name function)) 2))
        ;; There's no binding for CMD.  Let's try and find the shortest
        ;; string to use in M-x.  But don't actually do anything yet.
        (setq find-shorter t))
      (when (or binding find-shorter)
        (setq execute-extended-command--binding-timer
              (run-at-time
               delay-before-suggest nil
               (lambda ()
                 ;; If the user has typed any other commands in the
                 ;; meantime, then don't display anything.
                 (when (eq function real-last-command)
                   ;; Find shorter string.
                   (when find-shorter
                     (while-no-input
                       ;; FIXME: Can be slow.  Cache it maybe?
                       (setq shorter (execute-extended-command--shorter
                                      (symbol-name function) typed))))
                   (when (or binding shorter)
                     (with-temp-message
                         (execute-extended-command--describe-binding-msg
                          function binding shorter)
                       (sit-for (if (numberp suggest-key-bindings)
                                    suggest-key-bindings
                                  2))))))))))))

(defun execute-extended-command-for-buffer (prefixarg &optional
                                                      command-name typed)
  "Query user for a command relevant for the current mode, and then execute it.
This is like `execute-extended-command', but it limits the
completions to commands that are particularly relevant to the
current buffer.  This includes commands that have been marked as
being specially designed for the current major mode (and enabled
minor modes), as well as commands bound in the active local key
maps."
  (declare (interactive-only command-execute))
  (interactive
   (let ((execute-extended-command--last-typed nil))
     (list current-prefix-arg
           (read-extended-command "M-X ")
           execute-extended-command--last-typed)))
  (with-suppressed-warnings ((interactive-only execute-extended-command))
    (execute-extended-command prefixarg command-name typed)))

(defun command-completion--command-for-this-buffer-function ()
  (let ((keymaps
         ;; The major mode's keymap and any active minor modes.
         (nconc
          (and (current-local-map) (list (current-local-map)))
          (mapcar
           #'cdr
           (seq-filter
            (lambda (elem)
              (symbol-value (car elem)))
            minor-mode-map-alist)))))
    (lambda (symbol buffer)
      (or (command-completion-using-modes-p symbol buffer)
          ;; Include commands that are bound in a keymap in the
          ;; current buffer.
          (and (where-is-internal symbol keymaps)
               ;; But not if they have a command predicate that
               ;; says that they shouldn't.  (This is the case
               ;; for `ignore' and `undefined' and similar
               ;; commands commonly found in keymaps.)
               (or (null (get symbol 'completion-predicate))
                   (funcall (get symbol 'completion-predicate)
                            symbol buffer)))))))

(cl-defgeneric function-documentation (function)
  "Extract the raw docstring info from FUNCTION.
FUNCTION is expected to be a function value rather than, say, a mere symbol.
This is intended to be specialized via `cl-defmethod' but not called directly:
if you need a function's documentation use `documentation' which will call this
function as needed."
  (let ((docstring-p (lambda (doc)
                       ;; A docstring can be either a string or a reference
                       ;; into either the `etc/DOC' or a `.elc' file.
                       (or (stringp doc)
                           (fixnump doc) (fixnump (cdr-safe doc))))))
    (pcase function
      ((pred closurep)
       (when (> (length function) 4)
         (let ((doc (aref function 4)))
           (when (funcall docstring-p doc) doc))))
      ((or (pred stringp) (pred vectorp)) "Keyboard macro.")
      (`(keymap . ,_)
       "Prefix command (definition is a keymap associating keystrokes with commands).")
      ((or `(lambda ,_args . ,body) `(autoload ,_file . ,body))
       (let ((doc (car body)))
	 (when (funcall docstring-p doc)
           doc)))
      ((pred symbolp)
       (let ((f (indirect-function function)))
         (if f (function-documentation f)
           (signal 'void-function (list function)))))
      (`(macro . ,f) (function-documentation f))
      (_
       (let ((doc (internal-subr-documentation function)))
         (if (eq t doc)
             (signal 'invalid-function (list function))
           doc))))))

(cl-defmethod function-documentation ((function accessor))
  (oclosure--accessor-docstring function)) ;; FIXME: η-reduce!

(cl-defmethod function-documentation ((f cconv--interactive-helper))
  (function-documentation (cconv--interactive-helper--fun f)))

;; This should be in `oclosure.el' but that file is loaded before `cl-generic'.
(cl-defgeneric oclosure-interactive-form (_function)
  "Return the interactive form of FUNCTION or nil if none.
This is called by `interactive-form' when invoked on OClosures.
It should return either nil or a two-element list of the form (interactive FORM)
where FORM is like the first arg of the `interactive' special form.
Add your methods to this generic function, but always call `interactive-form'
instead."
  ;; (interactive-form function)
  nil)

(cl-defmethod oclosure-interactive-form ((f cconv--interactive-helper))
  (let ((if (cconv--interactive-helper--if f)))
    `(interactive ,(if (functionp if) `(funcall ',if) if))))

(defun command-execute (cmd &optional record-flag keys special)
  ;; BEWARE: Called directly from the C code.
  "Execute CMD as an editor command.
CMD must be a symbol that satisfies the `commandp' predicate.

Optional second arg RECORD-FLAG non-nil means unconditionally put
this command in the variable `command-history'.  Otherwise, that
is done only if an arg is read using the minibuffer.

The argument KEYS specifies the value to use instead of the
return value of the `this-command-keys' function when reading the
arguments; if it is nil, `this-command-keys' is used.

The argument SPECIAL, if non-nil, means that this command is
executing a special event, so ignore the prefix argument and
don't clear it."
  (setq debug-on-next-call nil)
  (let ((prefixarg (unless special
                     ;; FIXME: This should probably be done around
                     ;; pre-command-hook rather than here!
                     (prog1 prefix-arg
                       (setq current-prefix-arg prefix-arg)
                       (setq prefix-arg nil)
                       (when current-prefix-arg
                         (prefix-command-update)))))
        query)
    (if (and (symbolp cmd)
             (get cmd 'disabled)
             (or (and (setq query (and (consp (get cmd 'disabled))
                                       (eq (car (get cmd 'disabled)) 'query)))
                      (not (command-execute--query cmd)))
                 (and (not query) disabled-command-function)))
        (when (not query)
          ;; FIXME: Weird calling convention!
          (run-hooks 'disabled-command-function))
      (let ((final cmd))
        (while
            (progn
              (setq final (indirect-function final))
              (if (autoloadp final)
                  (setq final (autoload-do-load final cmd)))))
        (cond
         ((arrayp final)
          ;; If requested, place the macro in the command history.  For
          ;; other sorts of commands, call-interactively takes care of this.
          (when record-flag
            (add-to-history
             'command-history `(execute-kbd-macro ,final ,prefixarg) nil t))
          (execute-kbd-macro final prefixarg))
         (t
          ;; Pass `cmd' rather than `final', for the backtrace's sake.
          (prog1 (call-interactively cmd record-flag keys)
            (when-let* ((info
                         (and (symbolp cmd)
                              (not (get cmd 'command-execute-obsolete-warned))
                              (get cmd 'byte-obsolete-info))))
              (put cmd 'command-execute-obsolete-warned t)
              (message "%s" (macroexp--obsolete-warning
                             cmd info "command"
                             (help--key-description-fontified
                              (where-is-internal (car info) nil t))))))))))))

(defun command-execute--query (command)
  "Query the user whether to run COMMAND."
  (let ((query (get command 'disabled)))
    (funcall (if (nth 1 query) #'yes-or-no-p #'y-or-n-p)
             (nth 2 query))))

;;;###autoload
(defun command-query (command query &optional verbose)
  "Make executing COMMAND issue QUERY to the user.
This will, by default, use `y-or-n-p', but if VERBOSE,
`yes-or-no-p' is used instead."
  (put command 'disabled
       (list 'query (not (not verbose)) query)))


(defvar minibuffer-history nil
  "Default minibuffer history list.
This is used for all minibuffer input
except when an alternate history list is specified.

Maximum length of the history list is determined by the value
of `history-length', which see.")
(defvar minibuffer-history-sexp-flag nil
  "Control whether history list elements are expressions or strings.
If the value of this variable equals current minibuffer depth,
they are expressions; otherwise they are strings.
\(That convention is designed to do the right thing for
recursive uses of the minibuffer.)")
(setq minibuffer-history-variable 'minibuffer-history)
(setq minibuffer-history-position nil)  ;; Defvar is in C code.
(defvar minibuffer-history-search-history nil)

(defvar minibuffer-text-before-history nil
  "Text that was in this minibuffer before any history commands.
This is nil if there have not yet been any history commands
in this use of the minibuffer.")

(add-hook 'minibuffer-setup-hook 'minibuffer-history-initialize)

(defun minibuffer-history-initialize ()
  (setq minibuffer-text-before-history nil))

(defun minibuffer-avoid-prompt (_new _old)
  "A point-motion hook for the minibuffer, that moves point out of the prompt."
  (declare (obsolete cursor-intangible-mode "25.1"))
  (constrain-to-field nil (point-max)))

(defcustom minibuffer-history-case-insensitive-variables nil
  "Minibuffer history variables for which matching should ignore case.
If a history variable is a member of this list, then the
\\[previous-matching-history-element] and \\[next-matching-history-element]\
 commands ignore case when searching it,
regardless of `case-fold-search'."
  :type '(repeat variable)
  :group 'minibuffer)

(defun previous-matching-history-element (regexp n)
  "Find the previous history element that matches REGEXP.
\(Previous history elements refer to earlier actions.)
With prefix argument N, search for Nth previous match.
If N is negative, find the next or Nth next match.
Normally, history elements are matched case-insensitively if
`case-fold-search' is non-nil, but an uppercase letter in REGEXP
makes the search case-sensitive.
See also `minibuffer-history-case-insensitive-variables'."
  (interactive
   (let* ((n (prefix-numeric-value current-prefix-arg))
          (enable-recursive-minibuffers t)
	  (regexp (read-from-minibuffer
                   (format-prompt "%s element matching regexp"
                                  (and minibuffer-history-search-history
                                       (car minibuffer-history-search-history))
                                  (if (>= n 0) "Previous" "Next"))
		   nil minibuffer-local-map nil
		   'minibuffer-history-search-history
		   (car minibuffer-history-search-history))))
     ;; Use the last regexp specified, by default, if input is empty.
     (list (if (string= regexp "")
	       (if minibuffer-history-search-history
		   (car minibuffer-history-search-history)
                 (user-error "No history search regexp"))
	     regexp)
           n)))
  (unless (zerop n)
    (if (and (zerop minibuffer-history-position)
	     (null minibuffer-text-before-history))
	(setq minibuffer-text-before-history
	      (minibuffer-contents-no-properties)))
    (let ((history (minibuffer-history-value))
	  (case-fold-search
	   (if (isearch-no-upper-case-p regexp t) ; assume isearch.el is dumped
	       ;; On some systems, ignore case for file names.
	       (if (memq minibuffer-history-variable
			 minibuffer-history-case-insensitive-variables)
		   t
		 ;; Respect the user's setting for case-fold-search:
		 case-fold-search)
	     nil))
	  prevpos
	  match-string
	  match-offset
	  (pos minibuffer-history-position))
      (while (/= n 0)
	(setq prevpos pos)
	(setq pos (min (max 1 (+ pos (if (< n 0) -1 1))) (length history)))
	(when (= pos prevpos)
	  (user-error (if (= pos 1)
                          "No later matching history item"
                        "No earlier matching history item")))
	(setq match-string
	      (if (eq minibuffer-history-sexp-flag (minibuffer-depth))
		  (let ((print-level nil))
		    (prin1-to-string (nth (1- pos) history)))
		(nth (1- pos) history)))
	(setq match-offset
	      (if (< n 0)
		  (and (string-match regexp match-string)
		       (match-end 0))
		(and (string-match (concat ".*\\(" regexp "\\)") match-string)
		     (match-beginning 1))))
	(when match-offset
	  (setq n (+ n (if (< n 0) 1 -1)))))
      (setq minibuffer-history-position pos)
      (goto-char (point-max))
      (delete-minibuffer-contents)
      (insert match-string)
      (goto-char (+ (minibuffer-prompt-end) match-offset))))
  (if (memq (car (car command-history)) '(previous-matching-history-element
					  next-matching-history-element))
      (setq command-history (cdr command-history))))

(defun next-matching-history-element (regexp n)
  "Find the next history element that matches REGEXP.
\(The next history element refers to a more recent action.)
With prefix argument N, search for Nth next match.
If N is negative, find the previous or Nth previous match.
Normally, history elements are matched case-insensitively if
`case-fold-search' is non-nil, but an uppercase letter in REGEXP
makes the search case-sensitive."
  (interactive
   (let* ((n (prefix-numeric-value current-prefix-arg))
          (enable-recursive-minibuffers t)
          (regexp (read-from-minibuffer
                   (format-prompt "%s element matching regexp"
                                  (and minibuffer-history-search-history
                                       (car minibuffer-history-search-history))
                                  (if (>= n 0) "Next" "Previous"))
                   nil minibuffer-local-map nil
                   'minibuffer-history-search-history
                   (car minibuffer-history-search-history))))
     ;; Use the last regexp specified, by default, if input is empty.
     (list (if (string= regexp "")
	       (if minibuffer-history-search-history
		   (car minibuffer-history-search-history)
                 (user-error "No history search regexp"))
	     regexp)
           n)))
  (previous-matching-history-element regexp (- n)))

(defvar minibuffer-temporary-goal-position nil)

(defvar minibuffer-default-add-function 'minibuffer-default-add-completions
  "Function run by `goto-history-element' before consuming default values.
This is useful to dynamically add more elements to the list of default values
when `goto-history-element' reaches the end of this list.
Before calling this function `goto-history-element' sets the variable
`minibuffer-default-add-done' to t, so it will call this function only
once.  In special cases, when this function needs to be called more
than once, it can set `minibuffer-default-add-done' to nil explicitly,
overriding the setting of this variable to t in `goto-history-element'.")

(defvar-local minibuffer-default-add-done nil
  "When nil, add more elements to the end of the list of default values.
The value nil causes `goto-history-element' to add more elements to
the list of defaults when it reaches the end of this list.  It does
this by calling a function defined by `minibuffer-default-add-function'.")

(defun minibuffer-default-add-completions ()
  "Return a list of all completions without the default value.
This function is used to add all elements of the completion table to
the end of the list of defaults just after the default value.
If you don't want to add initial completions to the default value,
use either `minibuffer-setup-hook' or `minibuffer-with-setup-hook'
to set the value of `minibuffer-default-add-function' to nil."
  (let ((def minibuffer-default)
        ;; Avoid some popular completions with undefined order
        (all (unless (memq minibuffer-completion-table
                           `(help--symbol-completion-table ,obarray))
               (all-completions ""
                                minibuffer-completion-table
                                minibuffer-completion-predicate))))
    (if (listp def)
	(append def all)
      (cons def (delete def all)))))

(defun minibuffer-history-value ()
  "Return the value of the minibuffer input history list.
If `minibuffer-history-variable' points to a buffer-local variable and
the minibuffer is active, return the buffer-local value for the buffer
that was current when the minibuffer was activated."
  (buffer-local-value minibuffer-history-variable
                      (window-buffer (minibuffer-selected-window))))

(defun goto-history-element (nabs)
  "Insert into the minibuffer the element of minibuffer history specified by NABS.
Interactively, NABS is the prefix numeric argument, and defaults to 1.
It specifies the absolute history position in descending order,
where 0 means the current element and a positive number N means
the Nth previous element.  NABS that is a negative number -N means
the Nth entry of \"future history.\""
  (interactive "p")
  (when (and (not minibuffer-default-add-done)
	     (functionp minibuffer-default-add-function)
	     (< nabs (- (if (listp minibuffer-default)
			    (length minibuffer-default)
			  1))))
    (setq minibuffer-default-add-done t
	  minibuffer-default (funcall minibuffer-default-add-function)))
  (let ((minimum (if minibuffer-default
		     (- (if (listp minibuffer-default)
			    (length minibuffer-default)
			  1))
		   0))
	elt minibuffer-returned-to-present)
    (if (and (zerop minibuffer-history-position)
	     (null minibuffer-text-before-history))
	(setq minibuffer-text-before-history
	      (minibuffer-contents-no-properties)))
    (if (< nabs minimum)
	(user-error (if minibuffer-default
                        "End of defaults; no next item"
                      "End of history; no default available")))
    (if (> nabs (if (listp (minibuffer-history-value))
                    (length (minibuffer-history-value))
                  0))
	(user-error "Beginning of history; no preceding item"))
    (unless (memq last-command '(next-history-element
				 previous-history-element))
      (let ((prompt-end (minibuffer-prompt-end)))
        (setq-local minibuffer-temporary-goal-position
                    (cond ((<= (point) prompt-end) prompt-end)
                          ((eobp) nil)
                          (t (point))))))
    (goto-char (point-max))
    (delete-minibuffer-contents)
    (setq minibuffer-history-position nabs)
    (cond ((< nabs 0)
	   (setq elt (if (listp minibuffer-default)
			 (nth (1- (abs nabs)) minibuffer-default)
		       minibuffer-default)))
	  ((= nabs 0)
	   (setq elt (or minibuffer-text-before-history ""))
	   (setq minibuffer-returned-to-present t)
	   (setq minibuffer-text-before-history nil))
	  (t (setq elt (nth (1- minibuffer-history-position)
			    (minibuffer-history-value)))))
    (insert
     (if (and (eq minibuffer-history-sexp-flag (minibuffer-depth))
	      (not minibuffer-returned-to-present))
	 (let ((print-level nil))
	   (prin1-to-string elt))
       elt))
    (goto-char (or minibuffer-temporary-goal-position (point-max)))))

(defun next-history-element (n)
  "Insert into the minibuffer the Nth next element of minibuffer history.
Interactively, N is the prefix numeric argument and defaults to 1.
The value N can go beyond the current position in the minibuffer
history,  and invoke \"future history.\""
  (interactive "p")
  (or (zerop n)
      (goto-history-element (- minibuffer-history-position n))))

(defun previous-history-element (n)
  "Insert into the minibuffer the Nth previous element of minibuffer history.
Interactively, N is the prefix numeric argument and defaults to 1."
  (interactive "p")
  (or (zerop n)
      (goto-history-element (+ minibuffer-history-position n))))

(defun next-line-or-history-element (&optional arg)
  "Move cursor vertically down ARG lines, or to the next history element.
When point moves over the bottom line of multi-line minibuffer, puts ARGth
next element of the minibuffer history in the minibuffer."
  (interactive "^p")
  (or arg (setq arg 1))
  (let* ((old-point (point))
         ;; Don't add newlines if they have the mode enabled globally.
         (next-line-add-newlines nil)
	 ;; Remember the original goal column of possibly multi-line input
	 ;; excluding the length of the prompt on the first line.
	 (prompt-end (minibuffer-prompt-end))
	 (old-column (unless (and (eolp) (> (point) prompt-end))
		       (if (= (line-number-at-pos) 1)
			   (max (- (current-column)
				   (save-excursion
				     (goto-char (1- prompt-end))
				     (current-column)))
				0)
			 (current-column)))))
    (condition-case nil
	(with-no-warnings
	  (next-line arg))
      (end-of-buffer
       ;; Restore old position since `line-move-visual' moves point to
       ;; the end of the line when it fails to go to the next line.
       (goto-char old-point)
       (next-history-element arg)
       ;; Reset `temporary-goal-column' because a correct value is not
       ;; calculated when `next-line' above fails by bumping against
       ;; the bottom of the minibuffer (bug#22544).
       (setq temporary-goal-column 0)
       ;; Restore the original goal column on the last line
       ;; of possibly multi-line input.
       (goto-char (point-max))
       (when old-column
	 (if (= (line-number-at-pos) 1)
	     (move-to-column (+ old-column
				(save-excursion
				  (goto-char (1- (minibuffer-prompt-end)))
				  (current-column))))
	   (move-to-column old-column)))))))

(defun previous-line-or-history-element (&optional arg)
  "Move cursor vertically up ARG lines, or to the previous history element.
When point moves over the top line of multi-line minibuffer, puts ARGth
previous element of the minibuffer history in the minibuffer."
  (interactive "^p")
  (or arg (setq arg 1))
  (let* ((old-point (point))
	 ;; Remember the original goal column of possibly multi-line input
	 ;; excluding the length of the prompt on the first line.
	 (prompt-end (minibuffer-prompt-end))
	 (old-column (unless (and (eolp) (> (point) prompt-end))
		       (if (= (line-number-at-pos) 1)
			   (max (- (current-column)
				   (save-excursion
				     (goto-char (1- prompt-end))
				     (current-column)))
				1)
			 (current-column)))))
    (condition-case nil
	(with-no-warnings
	  (previous-line arg)
          ;; Avoid moving point to the prompt
          (when (< (point) (minibuffer-prompt-end))
            ;; If there is minibuffer contents on the same line
            (if (<= (minibuffer-prompt-end)
                    (save-excursion
                      (if (or truncate-lines (not line-move-visual))
                          (end-of-line)
                        (end-of-visual-line))
                      (point)))
                ;; Move to the beginning of minibuffer contents
                (goto-char (minibuffer-prompt-end))
              ;; Otherwise, go to the previous history element
              (signal 'beginning-of-buffer nil))))
      (beginning-of-buffer
       ;; Restore old position since `line-move-visual' moves point to
       ;; the beginning of the line when it fails to go to the previous line.
       (goto-char old-point)
       (previous-history-element arg)
       ;; Reset `temporary-goal-column' because a correct value is not
       ;; calculated when `previous-line' above fails by bumping against
       ;; the top of the minibuffer (bug#22544).
       (setq temporary-goal-column 0)
       ;; Restore the original goal column on the first line
       ;; of possibly multi-line input.
       (goto-char (minibuffer-prompt-end))
       (if old-column
	   (if (= (line-number-at-pos) 1)
	       (move-to-column (+ old-column
				  (save-excursion
				    (goto-char (1- (minibuffer-prompt-end)))
				    (current-column))))
	     (move-to-column old-column))
	 (if (not line-move-visual) ; Handle logical lines (bug#42862)
	     (end-of-line)
	   ;; Put the cursor at the end of the visual line instead of the
	   ;; logical line, so the next `previous-line-or-history-element'
	   ;; would move to the previous history element, not to a possible upper
	   ;; visual line from the end of logical line in `line-move-visual' mode.
	   (end-of-visual-line)
	   ;; Since `end-of-visual-line' puts the cursor at the beginning
	   ;; of the next visual line, move it one char back to the end
	   ;; of the first visual line (bug#22544).
	   (unless (eolp) (backward-char 1))))))))

(defun next-complete-history-element (n)
  "Get next history element that completes the minibuffer before the point.
The contents of the minibuffer after the point are deleted and replaced
by the new completion."
  (interactive "p")
  (let ((point-at-start (point)))
    (next-matching-history-element
     (concat
      "^" (regexp-quote (buffer-substring (minibuffer-prompt-end) (point))))
     n)
    ;; next-matching-history-element always puts us at (point-min).
    ;; Move to the position we were at before changing the buffer contents.
    ;; This is still sensible, because the text before point has not changed.
    (goto-char point-at-start)))

(defun previous-complete-history-element (n)
  "\
Get previous history element that completes the minibuffer before the point.
The contents of the minibuffer after the point are deleted and replaced
by the new completion."
  (interactive "p")
  (next-complete-history-element (- n)))

;; For compatibility with the old subr of the same name.
(defun minibuffer-prompt-width ()
  "Return the display width of the minibuffer prompt.
Return 0 if current buffer is not a minibuffer."
  ;; Return the width of everything before the field at the end of
  ;; the buffer; this should be 0 for normal buffers.
  (1- (minibuffer-prompt-end)))

;; isearch minibuffer history
(add-hook 'minibuffer-setup-hook 'minibuffer-history-isearch-setup)

(defvar-local minibuffer-history-isearch-message-overlay)

(defun minibuffer-history-isearch-setup ()
  "Set up a minibuffer for using isearch to search the minibuffer history.
Intended to be added to `minibuffer-setup-hook'."
  (setq-local isearch-search-fun-function
              #'minibuffer-history-isearch-search)
  (setq-local isearch-message-function
              #'minibuffer-history-isearch-message)
  (setq-local isearch-wrap-function
              #'minibuffer-history-isearch-wrap)
  (setq-local isearch-push-state-function
              #'minibuffer-history-isearch-push-state)
  (setq-local isearch-lazy-count nil)
  (add-hook 'isearch-mode-end-hook 'minibuffer-history-isearch-end nil t))

(defun minibuffer-history-isearch-end ()
  "Clean up the minibuffer after terminating isearch in the minibuffer."
  (if minibuffer-history-isearch-message-overlay
      (delete-overlay minibuffer-history-isearch-message-overlay)))

(defun minibuffer-history-isearch-search ()
  "Return the proper search function, for isearch in minibuffer history."
  (lambda (string bound noerror)
    (let ((search-fun
	   ;; Use standard functions to search within minibuffer text
	   (isearch-search-fun-default))
	  found)
      ;; Avoid lazy-highlighting matches in the minibuffer prompt when
      ;; searching forward.  Lazy-highlight calls this lambda with the
      ;; bound arg, so skip the minibuffer prompt.
      (if (and bound isearch-forward (< (point) (minibuffer-prompt-end)))
	  (goto-char (minibuffer-prompt-end)))
      (or
       ;; 1. First try searching in the initial minibuffer text
       (funcall search-fun string
		(if isearch-forward bound (minibuffer-prompt-end))
		noerror)
       ;; 2. If the above search fails, start putting next/prev history
       ;; elements in the minibuffer successively, and search the string
       ;; in them.  Do this only when bound is nil (i.e. not while
       ;; lazy-highlighting search strings in the current minibuffer text).
       (unless bound
	 (condition-case nil
	     (progn
	       (while (not found)
		 (cond (isearch-forward
			(next-history-element 1)
			(goto-char (minibuffer-prompt-end)))
		       (t
			(previous-history-element 1)
			(goto-char (point-max))))
		 (setq isearch-barrier (point) isearch-opoint (point))
		 ;; After putting the next/prev history element, search
		 ;; the string in them again, until next-history-element
		 ;; or previous-history-element raises an error at the
		 ;; beginning/end of history.
		 (setq found (funcall search-fun string
				      (unless isearch-forward
					;; For backward search, don't search
					;; in the minibuffer prompt
					(minibuffer-prompt-end))
				      noerror)))
	       ;; Return point of the new search result
	       (point))
	   ;; Return nil when next(prev)-history-element fails
	   (error nil)))))))

(defun minibuffer-history-isearch-message (&optional c-q-hack ellipsis)
  "Display the minibuffer history search prompt.
If there are no search errors, this function displays an overlay with
the isearch prompt which replaces the original minibuffer prompt.
Otherwise, it displays the standard isearch message returned from
the function `isearch-message'."
  (if (not (and (minibufferp) isearch-success (not isearch-error)))
      ;; Use standard function `isearch-message' when not in the minibuffer,
      ;; or search fails, or has an error (like incomplete regexp).
      ;; This function overwrites minibuffer text with isearch message,
      ;; so it's possible to see what is wrong in the search string.
      (isearch-message c-q-hack ellipsis)
    ;; Otherwise, put the overlay with the standard isearch prompt over
    ;; the initial minibuffer prompt.
    (if (overlayp minibuffer-history-isearch-message-overlay)
	(move-overlay minibuffer-history-isearch-message-overlay
		      (point-min) (minibuffer-prompt-end))
      (setq minibuffer-history-isearch-message-overlay
	    (make-overlay (point-min) (minibuffer-prompt-end)))
      (overlay-put minibuffer-history-isearch-message-overlay 'evaporate t))
    (overlay-put minibuffer-history-isearch-message-overlay
		 'display (isearch-message-prefix c-q-hack ellipsis))
    ;; And clear any previous isearch message.
    (message "")))

(defun minibuffer-history-isearch-wrap ()
  "Wrap the minibuffer history search when search fails.
Move point to the first history element for a forward search,
or to the last history element for a backward search."
  ;; When `minibuffer-history-isearch-search' fails on reaching the
  ;; beginning/end of the history, wrap the search to the first/last
  ;; minibuffer history element.
  (if isearch-forward
      (goto-history-element (length (minibuffer-history-value)))
    (goto-history-element 0))
  (goto-char (if isearch-forward (minibuffer-prompt-end) (point-max))))

(defun minibuffer-history-isearch-push-state ()
  "Save a function restoring the state of minibuffer history search.
Save `minibuffer-history-position' to the additional state parameter
in the search status stack."
  (let ((pos minibuffer-history-position))
    (lambda (cmd)
      (minibuffer-history-isearch-pop-state cmd pos))))

(defun minibuffer-history-isearch-pop-state (_cmd hist-pos)
  "Restore the minibuffer history search state.
Go to the history element by the absolute history position HIST-POS."
  (goto-history-element hist-pos))


(add-hook 'minibuffer-setup-hook 'minibuffer-error-initialize)

(defun minibuffer-error-initialize ()
  "Set up minibuffer error processing."
  (setq-local command-error-function 'minibuffer-error-function))

(defun minibuffer-error-function (data context caller)
  "Display error messages in the active minibuffer.
The same as `command-error-default-function' but display error messages
at the end of the minibuffer using `minibuffer-message' to not obscure
the minibuffer contents."
  (if (memq 'minibuffer-quit (get (car data) 'error-conditions))
      (ding t)
    (discard-input)
    (ding))
  (let ((string (error-message-string data)))
    ;; If we know from where the error was signaled, show it in
    ;; *Messages*.
    (let ((inhibit-message t))
      (message "%s%s" (if caller (format "%s: " caller) "") string))
    ;; Display an error message at the end of the minibuffer.
    (minibuffer-message (apply #'propertize (format " [%s%s]" context string)
                               minibuffer-prompt-properties))))


(defconst undo-equiv-table (make-hash-table :test 'eq :weakness t)
  "Table mapping redo records to the corresponding undo one.
A redo record for an undo in region maps to `undo-in-region'.
A redo record for ordinary undo maps to the following (earlier) undo.
A redo record that undoes to the beginning of the undo list maps to t.
In the rare case where there are (erroneously) consecutive nil's in
`buffer-undo-list', `undo' maps the previous valid undo record to
`empty', if the previous record is a redo record, `undo' doesn't change
its mapping.

To be clear, a redo record is just an undo record, the only difference
is that it is created by an undo command (instead of an ordinary buffer
edit).  Since a record used to undo ordinary change is called undo
record, a record used to undo an undo is called redo record.

`undo' uses this table to make sure the previous command is `undo'.
`undo-redo' uses this table to set the correct `pending-undo-list'.

When you undo, `pending-undo-list' shrinks and `buffer-undo-list'
grows, and Emacs maps the tip of `buffer-undo-list' to the tip of
`pending-undo-list' in this table.

For example, consider this undo list where each node represents an
undo record: if we undo from 4, `pending-undo-list' will be at 3,
`buffer-undo-list' at 5, and 5 will map to 3.

    |
    3  5
    | /
    |/
    4")

(defvar undo-in-region nil
  "Non-nil if `pending-undo-list' is not just a tail of `buffer-undo-list'.")

(defcustom undo-no-redo nil
  "If t, `undo' doesn't go through redo entries."
  :type 'boolean
  :group 'undo)

(defvar pending-undo-list nil
  "Within a run of consecutive undo commands, list remaining to be undone.
If t, we undid all the way to the end of it.")

(defun undo--last-change-was-undo-p (undo-list)
  (while (and (consp undo-list) (eq (car undo-list) nil))
    (setq undo-list (cdr undo-list)))
  (gethash undo-list undo-equiv-table))

(defun undo (&optional arg)
  "Undo some previous changes.
Repeat this command to undo more changes.
A numeric ARG serves as a repeat count.

In Transient Mark mode when the mark is active, undo changes only within
the current region.  Similarly, when not in Transient Mark mode, just \\[universal-argument]
as an argument limits undo to changes within the current region."
  (interactive "*P")
  ;; Make last-command indicate for the next command that this was an undo.
  ;; That way, another undo will undo more.
  ;; If we get to the end of the undo history and get an error,
  ;; another undo command will find the undo history empty
  ;; and will get another error.  To begin undoing the undos,
  ;; you must type some other command.
  (let* ((modified (buffer-modified-p))
	 ;; For an indirect buffer, look in the base buffer for the
	 ;; auto-save data.
	 (base-buffer (or (buffer-base-buffer) (current-buffer)))
	 (recent-save (with-current-buffer base-buffer
			(recent-auto-save-p)))
         ;; Allow certain commands to inhibit an immediately following
         ;; undo-in-region.
         (inhibit-region (and (symbolp last-command)
                              (get last-command 'undo-inhibit-region)))
	 message)
    ;; If we get an error in undo-start,
    ;; the next command should not be a "consecutive undo".
    ;; So set `this-command' to something other than `undo'.
    (setq this-command 'undo-start)
    ;; Here we decide whether to break the undo chain.  If the
    ;; previous command is `undo', we don't call `undo-start', i.e.,
    ;; don't break the undo chain.
    (unless (and (eq last-command 'undo)
		 (or (eq pending-undo-list t)
		     ;; If something (a timer or filter?) changed the buffer
		     ;; since the previous command, don't continue the undo seq.
		     (undo--last-change-was-undo-p buffer-undo-list)))
      (setq undo-in-region
	    (and (or (region-active-p) (and arg (not (numberp arg))))
                 (not inhibit-region)))
      (if undo-in-region
	  (undo-start (region-beginning) (region-end))
	(undo-start))
      ;; get rid of initial undo boundary
      (undo-more 1))
    ;; If we got this far, the next command should be a consecutive undo.
    (setq this-command 'undo)
    ;; Check to see whether we're hitting a redo record, and if
    ;; so, ask the user whether she wants to skip the redo/undo pair.
    (let ((equiv (gethash pending-undo-list undo-equiv-table)))
      (or (eq (selected-window) (minibuffer-window))
	  (setq message (format "%s%s"
                                (if (or undo-no-redo (not equiv))
                                    "Undo" "Redo")
                                (if undo-in-region " in region" ""))))
      (when (and (consp equiv) undo-no-redo)
	;; The equiv entry might point to another redo record if we have done
	;; undo-redo-undo-redo-... so skip to the very last equiv.
	(while (let ((next (gethash equiv undo-equiv-table)))
		 (if next (setq equiv next))))
	(setq pending-undo-list (if (consp equiv) equiv t))))
    (undo-more
     (if (numberp arg)
	 (prefix-numeric-value arg)
       1))
    ;; Record the fact that the just-generated undo records come from an
    ;; undo operation--that is, they are redo records.
    ;; In the ordinary case (not within a region), map the redo
    ;; record to the following undos.
    ;; I don't know how to do that in the undo-in-region case.
    (let ((list buffer-undo-list))
      ;; Strip any leading undo boundaries there might be, like we do
      ;; above when checking.
      (while (eq (car list) nil)
	(setq list (cdr list)))
      (puthash list
               (cond
                (undo-in-region 'undo-in-region)
                ;; Prevent identity mapping.  This can happen if
                ;; consecutive nils are erroneously in undo list.  It
                ;; has to map to _something_ so that the next `undo'
                ;; command recognizes that the previous command is
                ;; `undo' and doesn't break the undo chain.
                ((eq list pending-undo-list)
                 (or (gethash list undo-equiv-table)
                     'empty))
                (t pending-undo-list))
	       undo-equiv-table))
    ;; Don't specify a position in the undo record for the undo command.
    ;; Instead, undoing this should move point to where the change is.
    (let ((tail buffer-undo-list)
	  (prev nil))
      (while (car tail)
	(when (integerp (car tail))
	  (let ((pos (car tail)))
	    (if prev
		(setcdr prev (cdr tail))
	      (setq buffer-undo-list (cdr tail)))
	    (setq tail (cdr tail))
	    (while (car tail)
	      (if (eq pos (car tail))
		  (if prev
		      (setcdr prev (cdr tail))
		    (setq buffer-undo-list (cdr tail)))
		(setq prev tail))
	      (setq tail (cdr tail)))
	    (setq tail nil)))
	(setq prev tail tail (cdr tail))))
    ;; Record what the current undo list says,
    ;; so the next command can tell if the buffer was modified in between.
    (and modified (not (buffer-modified-p))
	 (with-current-buffer base-buffer
	   (delete-auto-save-file-if-necessary recent-save)))
    ;; Display a message announcing success.
    (if message
	(message "%s" message))))

(defun buffer-disable-undo (&optional buffer)
  "Make BUFFER stop keeping undo information.
No argument or nil as argument means do this for the current buffer."
  (interactive)
  (with-current-buffer (if buffer (get-buffer buffer) (current-buffer))
    (setq buffer-undo-list t)))

(defun undo-only (&optional arg)
  "Undo some previous changes.
Repeat this command to undo more changes.
A numeric ARG serves as a repeat count.
Contrary to `undo', this will not redo a previous undo."
  (interactive "*p")
  (let ((undo-no-redo t)) (undo arg)))

(defun undo-redo (&optional arg)
  "Undo the last ARG undos, i.e., redo the last ARG changes.
Interactively, ARG is the prefix numeric argument and defaults to 1."
  (interactive "*p")
  (cond
   ((not (undo--last-change-was-undo-p buffer-undo-list))
    (user-error "No undone changes to redo"))
   (t
    (let* ((ul buffer-undo-list)
           (new-ul
            (let ((undo-in-progress t))
              (while (and (consp ul) (eq (car ul) nil))
                (setq ul (cdr ul)))
              (primitive-undo (or arg 1) ul)))
           (new-pul (undo--last-change-was-undo-p new-ul)))
      (message "Redo%s" (if undo-in-region " in region" ""))
      (setq this-command 'undo)
      (setq pending-undo-list new-pul)
      (setq buffer-undo-list new-ul)))))

(defvar undo-in-progress nil
  "Non-nil while performing an undo.
Some change-hooks test this variable to do something different.")

(defun undo-more (n)
  "Undo back N undo-boundaries beyond what was already undone recently.
Call `undo-start' to get ready to undo recent changes,
then call `undo-more' one or more times to undo them."
  (or (listp pending-undo-list)
      (user-error (concat "No further undo information"
                          (and undo-in-region " for region"))))
  (let ((undo-in-progress t))
    ;; Note: The following, while pulling elements off
    ;; `pending-undo-list' will call primitive change functions which
    ;; will push more elements onto `buffer-undo-list'.
    (setq pending-undo-list (primitive-undo n pending-undo-list))
    (if (null pending-undo-list)
	(setq pending-undo-list t))))

(defun primitive-undo (n list)
  "Undo N records from the front of the list LIST.
Return what remains of the list."

  ;; This is a good feature, but would make undo-start
  ;; unable to do what is expected.
  ;;(when (null (car (list)))
  ;;  ;; If the head of the list is a boundary, it is the boundary
  ;;  ;; preceding this command.  Get rid of it and don't count it.
  ;;  (setq list (cdr list))))

  (let ((arg n)
        ;; In a writable buffer, enable undoing read-only text that is
        ;; so because of text properties.
        (inhibit-read-only t)
        ;; We use oldlist only to check for EQ.  ++kfs
        (oldlist buffer-undo-list)
        (did-apply nil)
        (next nil))
    (while (> arg 0)
      (while (setq next (pop list))     ;Exit inner loop at undo boundary.
        ;; Handle an integer by setting point to that value.
        (pcase next
          ((pred integerp) (goto-char next))
          ;; Element (t . TIME) records previous modtime.
          ;; Preserve any flag of NONEXISTENT_MODTIME_NSECS or
          ;; UNKNOWN_MODTIME_NSECS.
          (`(t . ,time)
           ;; If this records an obsolete save
           ;; (not matching the actual disk file)
           ;; then don't mark unmodified.
           (let ((visited-file-time (visited-file-modtime)))
             ;; Indirect buffers don't have a visited file, so their
             ;; file-modtime can be bogus.  In that case, use the
             ;; modtime of the base buffer instead.
             (if (and (numberp visited-file-time)
                      (= visited-file-time 0)
                      (buffer-base-buffer))
                 (setq visited-file-time
                      (with-current-buffer (buffer-base-buffer)
                        (visited-file-modtime))))
	     (when (time-equal-p time visited-file-time)
               (unlock-buffer)
               (set-buffer-modified-p nil))))
          ;; Element (nil PROP VAL BEG . END) is property change.
          (`(nil . ,(or `(,prop ,val ,beg . ,end) pcase--dontcare))
           (when (or (> (point-min) beg) (< (point-max) end))
             (error "Changes to be undone are outside visible portion of buffer"))
           (put-text-property beg end prop val))
          ;; Element (BEG . END) means range was inserted.
          (`(,(and beg (pred integerp)) . ,(and end (pred integerp)))
           ;; (and `(,beg . ,end) `(,(pred integerp) . ,(pred integerp)))
           ;; Ideally: `(,(pred integerp beg) . ,(pred integerp end))
           (when (or (> (point-min) beg) (< (point-max) end))
             (error "Changes to be undone are outside visible portion of buffer"))
           ;; Set point first thing, so that undoing this undo
           ;; does not send point back to where it is now.
           (goto-char beg)
           (delete-region beg end))
          ;; Element (apply FUN . ARGS) means call FUN to undo.
          (`(apply . ,fun-args)
           (let ((currbuff (current-buffer)))
             (if (integerp (car fun-args))
                 ;; Long format: (apply DELTA START END FUN . ARGS).
                 (pcase-let* ((`(,delta ,start ,end ,fun . ,args) fun-args)
                              (start-mark (copy-marker start nil))
                              (end-mark (copy-marker end t)))
                   (when (or (> (point-min) start) (< (point-max) end))
                     (error "Changes to be undone are outside visible portion of buffer"))
                   (apply fun args) ;; Use `save-current-buffer'?
                   ;; Check that the function did what the entry
                   ;; said it would do.
                   (unless (and (= start start-mark)
                                (= (+ delta end) end-mark))
                     (error "Changes undone by function are different from the announced ones"))
                   (set-marker start-mark nil)
                   (set-marker end-mark nil))
               (apply fun-args))
             (unless (eq currbuff (current-buffer))
               (error "Undo function switched buffer"))
             (setq did-apply t)))
          ;; Element (STRING . POS) means STRING was deleted.
          (`(,(and string (pred stringp)) . ,(and pos (pred integerp)))
           (let ((valid-marker-adjustments nil)
                 (apos (abs pos)))
             (when (or (< apos (point-min)) (> apos (point-max)))
               (error "Changes to be undone are outside visible portion of buffer"))
             ;; Check that marker adjustments which were recorded
             ;; with the (STRING . POS) record are still valid, ie
             ;; the markers haven't moved.  We check their validity
             ;; before reinserting the string so as we don't need to
             ;; mind marker insertion-type.
             (while (and (markerp (car-safe (car list)))
                         (integerp (cdr-safe (car list))))
               (let* ((marker-adj (pop list))
                      (m (car marker-adj)))
                 (and (eq (marker-buffer m) (current-buffer))
                      (= apos m)
                      (push marker-adj valid-marker-adjustments))))
             ;; Insert string and adjust point
             (if (< pos 0)
                 (progn
                   (goto-char (- pos))
                   (insert string))
               (goto-char pos)
               (insert string)
               (goto-char pos))
             ;; Adjust the valid marker adjustments
             (dolist (adj valid-marker-adjustments)
               ;; Insert might have invalidated some of the markers
               ;; via modification hooks.  Update only the currently
               ;; valid ones (bug#25599).
               (if (marker-buffer (car adj))
                   (set-marker (car adj)
                               (- (car adj) (cdr adj)))))))
          ;; (MARKER . OFFSET) means a marker MARKER was adjusted by OFFSET.
          (`(,(and marker (pred markerp)) . ,(and offset (pred integerp)))
           (warn "Encountered %S entry in undo list with no matching (TEXT . POS) entry"
                 next)
           ;; Even though these elements are not expected in the undo
           ;; list, adjust them to be conservative for the 24.4
           ;; release.  (Bug#16818)
           (when (marker-buffer marker)
             (set-marker marker
                         (- marker offset)
                         (marker-buffer marker))))
          (_ (error "Unrecognized entry in undo list %S" next))))
      (setq arg (1- arg)))
    ;; Make sure an apply entry produces at least one undo entry,
    ;; so the test in `undo' for continuing an undo series
    ;; will work right.
    (if (and did-apply
             (eq oldlist buffer-undo-list))
        (setq buffer-undo-list
              (cons (list 'apply 'cdr nil) buffer-undo-list))))
  list)

;; Deep copy of a list
(defun undo-copy-list (list)
  "Make a copy of undo list LIST."
  (mapcar 'undo-copy-list-1 list))

(defun undo-copy-list-1 (elt)
  (if (consp elt)
      (cons (car elt) (undo-copy-list-1 (cdr elt)))
    elt))

(defun undo-start (&optional beg end)
  "Set `pending-undo-list' to the front of the undo list.
The next call to `undo-more' will undo the most recently made change.
If BEG and END are specified, then undo only elements
that apply to text between BEG and END are used; other undo elements
are ignored.  If BEG and END are nil, all undo elements are used."
  (if (eq buffer-undo-list t)
      (user-error "No undo information in this buffer"))
  (setq pending-undo-list
	(if (and beg end (not (= beg end)))
	    (undo-make-selective-list (min beg end) (max beg end))
	  buffer-undo-list)))

;; The positions given in elements of the undo list are the positions
;; as of the time that element was recorded to undo history.  In
;; general, subsequent buffer edits render those positions invalid in
;; the current buffer, unless adjusted according to the intervening
;; undo elements.
;;
;; Undo in region is a use case that requires adjustments to undo
;; elements.  It must adjust positions of elements in the region based
;; on newer elements not in the region so as they may be correctly
;; applied in the current buffer.  undo-make-selective-list
;; accomplishes this with its undo-deltas list of adjustments.  An
;; example undo history from oldest to newest:
;;
;; buf pos:
;; 123456789 buffer-undo-list undo-deltas
;; --------- ---------------- -----------
;; aaa       (1 . 4)          (1 . -3)
;; aaba      (3 . 4)          N/A (in region)
;; ccaaba    (1 . 3)          (1 . -2)
;; ccaabaddd (7 . 10)         (7 . -3)
;; ccaabdd   ("ad" . 6)       (6 . 2)
;; ccaabaddd (6 . 8)          (6 . -2)
;;  |   |<-- region: "caab", from 2 to 6
;;
;; When the user starts a run of undos in region,
;; undo-make-selective-list is called to create the full list of in
;; region elements.  Each element is adjusted forward chronologically
;; through undo-deltas to determine if it is in the region.
;;
;; In the above example, the insertion of "b" is (3 . 4) in the
;; buffer-undo-list.  The undo-delta (1 . -2) causes (3 . 4) to become
;; (5 . 6).  The next three undo-deltas cause no adjustment, so (5
;; . 6) is assessed as in the region and placed in the selective list.
;; Notably, the end of region itself adjusts from "2 to 6" to "2 to 5"
;; due to the selected element.  The "b" insertion is the only element
;; fully in the region, so in this example undo-make-selective-list
;; returns (nil (5 . 6)).
;;
;; The adjustment of the (7 . 10) insertion of "ddd" shows an edge
;; case.  It is adjusted through the undo-deltas: ((6 . 2) (6 . -2)).
;; Normally an undo-delta of (6 . 2) would cause positions after 6 to
;; adjust by 2.  However, they shouldn't adjust to less than 6, so (7
;; . 10) adjusts to (6 . 8) due to the first undo delta.
;;
;; More interesting is how to adjust the "ddd" insertion due to the
;; next undo-delta: (6 . -2), corresponding to reinsertion of "ad".
;; If the reinsertion was a manual retyping of "ad", then the total
;; adjustment should be (7 . 10) -> (6 . 8) -> (8 . 10).  However, if
;; the reinsertion was due to undo, one might expect the first "d"
;; character would again be a part of the "ddd" text, meaning its
;; total adjustment would be (7 . 10) -> (6 . 8) -> (7 . 10).
;;
;; undo-make-selective-list assumes in this situation that "ad" was a
;; new edit, even if it was inserted because of an undo.
;; Consequently, if the user undos in region "8 to 10" of the
;; "ccaabaddd" buffer, they could be surprised that it becomes
;; "ccaabad", as though the first "d" became detached from the
;; original "ddd" insertion.  This quirk is a FIXME.

(defun undo-make-selective-list (start end)
  "Return a list of undo elements for the region START to END.
The elements come from `buffer-undo-list', but we keep only the
elements inside this region, and discard those outside this
region.  The elements' positions are adjusted so as the returned
list can be applied to the current buffer."
  (let ((ulist buffer-undo-list)
        ;; A list of position adjusted undo elements in the region.
        (selective-list (list nil))
        ;; A list of undo-deltas for out of region undo elements.
        undo-deltas
        undo-elt)
    (while ulist
      (when undo-no-redo
        (while (consp (gethash ulist undo-equiv-table))
          (setq ulist (gethash ulist undo-equiv-table))))
      (setq undo-elt (car ulist))
      (cond
       ((null undo-elt)
        ;; Don't put two nils together in the list
        (when (car selective-list)
          (push nil selective-list)))
       ((and (consp undo-elt) (eq (car undo-elt) t))
        ;; This is a "was unmodified" element.  Keep it
        ;; if we have kept everything thus far.
        (when (not undo-deltas)
          (push undo-elt selective-list)))
       ;; Skip over marker adjustments, instead relying
       ;; on finding them after (TEXT . POS) elements
       ((markerp (car-safe undo-elt))
        nil)
       (t
        (let ((adjusted-undo-elt (undo-adjust-elt undo-elt
                                                  undo-deltas)))
          (if (undo-elt-in-region adjusted-undo-elt start end)
              (progn
                (setq end (+ end (cdr (undo-delta adjusted-undo-elt))))
                (push adjusted-undo-elt selective-list)
                ;; Keep (MARKER . ADJUSTMENT) if their (TEXT . POS) was
                ;; kept.  primitive-undo may discard them later.
                (when (and (stringp (car-safe adjusted-undo-elt))
                           (integerp (cdr-safe adjusted-undo-elt)))
                  (let ((list-i (cdr ulist)))
                    (while (markerp (car-safe (car list-i)))
                      (push (pop list-i) selective-list)))))
            (let ((delta (undo-delta undo-elt)))
              (when (/= 0 (cdr delta))
                (push delta undo-deltas)))))))
      (pop ulist))
    (nreverse selective-list)))

(defun undo-elt-in-region (undo-elt start end)
  "Determine whether UNDO-ELT falls inside the region START ... END.
If it crosses the edge, we return nil.

Generally this function is not useful for determining
whether (MARKER . ADJUSTMENT) undo elements are in the region,
because markers can be arbitrarily relocated.  Instead, pass the
marker adjustment's corresponding (TEXT . POS) element."
  (cond ((integerp undo-elt)
         (<= start undo-elt end))
	((eq undo-elt nil)
	 t)
	((atom undo-elt)
	 nil)
	((stringp (car undo-elt))
	 ;; (TEXT . POSITION)
	 (<= start (abs (cdr undo-elt)) end))
	((and (consp undo-elt) (markerp (car undo-elt)))
	 ;; (MARKER . ADJUSTMENT)
         (<= start (car undo-elt) end))
	((null (car undo-elt))
	 ;; (nil PROPERTY VALUE BEG . END)
	 (let ((tail (nthcdr 3 undo-elt)))
	   (and (>= (car tail) start)
		(<= (cdr tail) end))))
	((integerp (car undo-elt))
	 ;; (BEGIN . END)
	 (and (>= (car undo-elt) start)
	      (<= (cdr undo-elt) end)))))

(defun undo-elt-crosses-region (undo-elt start end)
  "Test whether UNDO-ELT crosses one edge of that region START ... END.
This assumes we have already decided that UNDO-ELT
is not *inside* the region START...END."
  (declare (obsolete nil "25.1"))
  (cond ((atom undo-elt) nil)
	((null (car undo-elt))
	 ;; (nil PROPERTY VALUE BEG . END)
	 (let ((tail (nthcdr 3 undo-elt)))
	   (and (< (car tail) end)
		(> (cdr tail) start))))
	((integerp (car undo-elt))
	 ;; (BEGIN . END)
	 (and (< (car undo-elt) end)
	      (> (cdr undo-elt) start)))))

(defun undo-adjust-elt (elt deltas)
  "Return adjustment of undo element ELT by the undo DELTAS list."
  (pcase elt
    ;; POSITION
    ((pred integerp)
     (undo-adjust-pos elt deltas))
    ;; (BEG . END)
    (`(,(and beg (pred integerp)) . ,(and end (pred integerp)))
     (undo-adjust-beg-end beg end deltas))
    ;; (TEXT . POSITION)
    (`(,(and text (pred stringp)) . ,(and pos (pred integerp)))
     (cons text (* (if (< pos 0) -1 1)
                   (undo-adjust-pos (abs pos) deltas))))
    ;; (nil PROPERTY VALUE BEG . END)
    (`(nil . ,(or `(,prop ,val ,beg . ,end) pcase--dontcare))
     `(nil ,prop ,val . ,(undo-adjust-beg-end beg end deltas)))
    ;; (apply DELTA START END FUN . ARGS)
    ;; FIXME
    ;; All others return same elt
    (_ elt)))

;; (BEG . END) can adjust to the same positions, commonly when an
;; insertion was undone and they are out of region, for example:
;;
;; buf pos:
;; 123456789 buffer-undo-list undo-deltas
;; --------- ---------------- -----------
;; [...]
;; abbaa     (2 . 4)          (2 . -2)
;; aaa       ("bb" . 2)       (2 . 2)
;; [...]
;;
;; "bb" insertion (2 . 4) adjusts to (2 . 2) because of the subsequent
;; undo.  Further adjustments to such an element should be the same as
;; for (TEXT . POSITION) elements.  The options are:
;;
;;   1: POSITION adjusts using <= (use-< nil), resulting in behavior
;;      analogous to marker insertion-type t.
;;
;;   2: POSITION adjusts using <, resulting in behavior analogous to
;;      marker insertion-type nil.
;;
;; There was no strong reason to prefer one or the other, except that
;; the first is more consistent with prior undo in region behavior.
(defun undo-adjust-beg-end (beg end deltas)
  "Return cons of adjustments to BEG and END by the undo DELTAS list."
  (let ((adj-beg (undo-adjust-pos beg deltas)))
    ;; Note: option 2 above would be like (cons (min ...) adj-end)
    (cons adj-beg
          (max adj-beg (undo-adjust-pos end deltas t)))))

(defun undo-adjust-pos (pos deltas &optional use-<)
  "Return adjustment of POS by the undo DELTAS list, comparing
with < or <= based on USE-<."
  (dolist (d deltas pos)
    (when (if use-<
              (< (car d) pos)
            (<= (car d) pos))
      (setq pos
            ;; Don't allow pos to become less than the undo-delta
            ;; position.  This edge case is described in the overview
            ;; comments.
            (max (car d) (- pos (cdr d)))))))

;; Return the first affected buffer position and the delta for an undo element
;; delta is defined as the change in subsequent buffer positions if we *did*
;; the undo.
(defun undo-delta (undo-elt)
  (if (consp undo-elt)
      (cond ((stringp (car undo-elt))
	     ;; (TEXT . POSITION)
	     (cons (abs (cdr undo-elt)) (length (car undo-elt))))
	    ((integerp (car undo-elt))
	     ;; (BEGIN . END)
	     (cons (car undo-elt) (- (car undo-elt) (cdr undo-elt))))
	    ;; (apply DELTA BEG END FUNC . ARGS)
	    ((and (eq (car undo-elt) 'apply) (integerp (nth 1 undo-elt)))
	     (cons (nth 2 undo-elt) (nth 1 undo-elt)))
	    (t
	     '(0 . 0)))
    '(0 . 0)))

;;; Default undo-boundary addition
;;
;; This section adds a new undo-boundary at either after a command is
;; called or in some cases on a timer called after a change is made in
;; any buffer.
(defvar-local undo-auto--last-boundary-cause nil
  "Describe the cause of the last `undo-boundary'.

If `explicit', the last boundary was caused by an explicit call to
`undo-boundary', that is one not called by the code in this
section.

If it is equal to `timer', then the last boundary was inserted
by `undo-auto--boundary-timer'.

If it is equal to `command', then the last boundary was inserted
automatically after a command, that is by the code defined in
this section.

If it is equal to a list, then the last boundary was inserted by
an amalgamating command.  The car of the list is the number of
times an amalgamating command has been called, and the cdr are the
buffers that were changed during the last command.")

(defvar undo-auto-current-boundary-timer nil
  "Current timer which will run `undo-auto--boundary-timer' or nil.

If set to non-nil, this will effectively disable the timer.")

(defvar undo-auto--this-command-amalgamating nil
  "Non-nil if `this-command' should be amalgamated.
This variable is set to nil by `undo-auto--boundaries' and is set
by `undo-auto-amalgamate'." )

(defun undo-auto--needs-boundary-p ()
  "Return non-nil if `buffer-undo-list' needs a boundary at the start."
  (car-safe buffer-undo-list))

(defun undo-auto--last-boundary-amalgamating-number ()
  "Return the number of amalgamating last commands or nil.
Amalgamating commands are, by default, either
`self-insert-command' and `delete-char', but can be any command
that calls `undo-auto-amalgamate'."
  (car-safe undo-auto--last-boundary-cause))

(defun undo-auto--ensure-boundary (cause)
  "Add an `undo-boundary' to the current buffer if needed.
REASON describes the reason that the boundary is being added; see
`undo-auto--last-boundary-cause' for more information."
  (when (and
         (undo-auto--needs-boundary-p))
    (let ((last-amalgamating
           (undo-auto--last-boundary-amalgamating-number)))
      (undo-boundary)
      (setq undo-auto--last-boundary-cause
            (if (eq 'amalgamate cause)
                (cons
                 (if last-amalgamating (1+ last-amalgamating) 0)
                 undo-auto--undoably-changed-buffers)
              cause)))))

(defun undo-auto--boundaries (cause)
  "Check recently changed buffers and add a boundary if necessary.
REASON describes the reason that the boundary is being added; see
`undo-auto--last-boundary-cause' for more information."
  ;; (Bug #23785) All commands should ensure that there is an undo
  ;; boundary whether they have changed the current buffer or not.
  (when (eq cause 'command)
    (add-to-list 'undo-auto--undoably-changed-buffers (current-buffer)))
  (dolist (b undo-auto--undoably-changed-buffers)
          (when (buffer-live-p b)
            (with-current-buffer b
              (undo-auto--ensure-boundary cause))))
  (setq undo-auto--undoably-changed-buffers nil))

(defun undo-auto--boundary-timer ()
  "Timer function run by `undo-auto-current-boundary-timer'."
  (setq undo-auto-current-boundary-timer nil)
  (undo-auto--boundaries 'timer))

(defun undo-auto--boundary-ensure-timer ()
  "Ensure that the `undo-auto-current-boundary-timer' is set."
  (unless undo-auto-current-boundary-timer
    (setq undo-auto-current-boundary-timer
          (run-at-time 10 nil #'undo-auto--boundary-timer))))

(defvar undo-auto--undoably-changed-buffers nil
  "List of buffers that have changed recently.

This list is maintained by `undo-auto--undoable-change' and
`undo-auto--boundaries' and can be affected by changes to their
default values.")

(defun undo-auto--add-boundary ()
  "Add an `undo-boundary' in appropriate buffers."
  (undo-auto--boundaries
   (let ((amal undo-auto--this-command-amalgamating))
     (setq undo-auto--this-command-amalgamating nil)
     (if amal
         'amalgamate
       'command))))

(defun undo-auto-amalgamate ()
  "Amalgamate undo if necessary.
This function can be called before an amalgamating command.  It
removes the previous `undo-boundary' if a series of such calls
have been made.  `self-insert-command' and `delete-char' are the
most common amalgamating commands, although this function can be
called by any command which desires this behavior.
`analyze-text-conversion' (which see) is also an amalgamating
command in most circumstances."
  (let ((last-amalgamating-count
         (undo-auto--last-boundary-amalgamating-number)))
    (setq undo-auto--this-command-amalgamating t)
    (when last-amalgamating-count
      (if (and (< last-amalgamating-count amalgamating-undo-limit)
               (eq this-command last-command))
          ;; Amalgamate all buffers that have changed.
          ;; This may be needed for example if some *-change-functions
          ;; reflected these changes in some other buffer.
          (dolist (b (cdr undo-auto--last-boundary-cause))
            (when (buffer-live-p b)
              (with-current-buffer
                  b
                (when (and (consp buffer-undo-list)
                           ;; `car-safe' doesn't work because
                           ;; `buffer-undo-list' need not be a list!
                           (null (car buffer-undo-list)))
                  ;; The head of `buffer-undo-list' is nil.
                  (setq buffer-undo-list
                        (cdr buffer-undo-list))))))
        (setq undo-auto--last-boundary-cause 0)))))

(defun undo-auto--undoable-change ()
  "Called after every undoable buffer change."
  (unless (memq (current-buffer) undo-auto--undoably-changed-buffers)
    (let ((bufs undo-auto--undoably-changed-buffers))
      ;; Drop dead buffers from the list, to avoid memory leak in
      ;; (while t (with-temp-buffer (setq buffer-undo-list nil) (insert "a")))
      (while bufs
        (let ((next (cdr bufs)))
          (if (or (buffer-live-p (car bufs)) (null next))
              (setq bufs next)
            (setcar bufs (car next))
            (setcdr bufs (cdr next))))))
    (push (current-buffer) undo-auto--undoably-changed-buffers))
  (undo-auto--boundary-ensure-timer))
;; End auto-boundary section

(defun undo-amalgamate-change-group (handle)
  "Amalgamate changes in change-group since HANDLE.
Remove all undo boundaries between the state of HANDLE and now.
HANDLE is as returned by `prepare-change-group'."
  (dolist (elt handle)
    (with-current-buffer (car elt)
      (setq elt (cdr elt))
      (when (consp buffer-undo-list)
        (let ((old-car (car-safe elt))
              (old-cdr (cdr-safe elt)))
          (unwind-protect
              (progn
                ;; Temporarily truncate the undo log at ELT.
                (when (consp elt)
                  (setcar elt t) (setcdr elt nil))
                (when
                    (or (null elt)        ;The undo-log was empty.
                        ;; `elt' is still in the log: normal case.
                        (eq elt (last buffer-undo-list))
                        ;; `elt' is not in the log any more, but that's because
                        ;; the log is "all new", so we should remove all
                        ;; boundaries from it.
                        (not (eq (last buffer-undo-list) (last old-cdr))))
                  (cl-callf (lambda (x) (delq nil x))
                      (if (car buffer-undo-list)
                          buffer-undo-list
                        ;; Preserve the undo-boundaries at either ends of the
                        ;; change-groups.
                        (cdr buffer-undo-list)))))
            ;; Reset the modified cons cell ELT to its original content.
            (when (consp elt)
              (setcar elt old-car)
              (setcdr elt old-cdr))))))))


(defcustom undo-ask-before-discard nil
  "If non-nil ask about discarding undo info for the current command.
Normally, Emacs discards the undo info for the current command if
it exceeds `undo-outer-limit'.  But if you set this option
non-nil, it asks in the echo area whether to discard the info.
If you answer no, there is a slight risk that Emacs might crash, so
do it only if you really want to undo the command.

This option is mainly intended for debugging.  You have to be
careful if you use it for other purposes.  Garbage collection is
inhibited while the question is asked, meaning that Emacs might
leak memory.  So you should make sure that you do not wait
excessively long before answering the question."
  :type 'boolean
  :group 'undo
  :version "22.1")

(defvar-local undo-extra-outer-limit nil
  "If non-nil, an extra level of size that's ok in an undo item.
We don't ask the user about truncating the undo list until the
current item gets bigger than this amount.

This variable matters only if `undo-ask-before-discard' is non-nil.")

;; When the first undo batch in an undo list is longer than
;; undo-outer-limit, this function gets called to warn the user that
;; the undo info for the current command was discarded.  Garbage
;; collection is inhibited around the call, so it had better not do a
;; lot of consing.
(setq undo-outer-limit-function 'undo-outer-limit-truncate)
(defun undo-outer-limit-truncate (size)
  (if undo-ask-before-discard
      (when (or (null undo-extra-outer-limit)
		(> size undo-extra-outer-limit))
	;; Don't ask the question again unless it gets even bigger.
	;; This applies, in particular, if the user quits from the question.
	;; Such a quit quits out of GC, but something else will call GC
	;; again momentarily.  It will call this function again,
	;; but we don't want to ask the question again.
	(setq undo-extra-outer-limit (+ size 50000))
	(if (let (use-dialog-box track-mouse executing-kbd-macro )
	      (yes-or-no-p (format-message
                            "Buffer `%s' undo info is %d bytes long; discard it? "
                            (buffer-name) size)))
	    (progn (setq buffer-undo-list nil)
		   (setq undo-extra-outer-limit nil)
		   t)
	  nil))
    (display-warning '(undo discard-info)
		     (concat
		      (format-message
                       "Buffer `%s' undo info was %d bytes long.\n"
                       (buffer-name) size)
		      "The undo info was discarded because it exceeded \
`undo-outer-limit'.

This is normal if you executed a command that made a huge change
to the buffer.  In that case, to prevent similar problems in the
future, set `undo-outer-limit' to a value that is large enough to
cover the maximum size of normal changes you expect a single
command to make, but not so large that it might exceed the
maximum memory allotted to Emacs.

If you did not execute any such command, the situation is
probably due to a bug and you should report it.

You can disable the popping up of this buffer by adding the entry
\(undo discard-info) to the user option `warning-suppress-types',
which is defined in the `warnings' library.\n")
		     :warning)
    (setq buffer-undo-list nil)
    t))

;;;; Shell commands

(defconst shell-command-buffer-name "*Shell Command Output*"
  "Name of the output buffer for shell commands.")

(defconst shell-command-buffer-name-async "*Async Shell Command*"
  "Name of the output buffer for asynchronous shell commands.")

(defvar shell-command-history nil
  "History list for some commands that read shell commands.

Maximum length of the history list is determined by the value
of `history-length', which see.")

(defvar shell-command-switch "-c"
  "Switch used to have the shell execute its command line argument.")

(defvar shell-command-default-error-buffer nil
  "Buffer name for `shell-command' and `shell-command-on-region' error output.
This buffer is used when `shell-command' or `shell-command-on-region'
is run interactively.  A value of nil means that output to stderr and
stdout will be intermixed in the output stream.")

(declare-function dired-get-filename "dired" (&optional localp no-error-if-not-filep))
(declare-function shell-command-guess "dired-aux" (files))

(defun minibuffer-default-add-shell-commands ()
  "Return a list of all commands associated with the current file.
This function is used to add all related commands retrieved by
`shell-command-guess' to the end of the list of defaults just
after the default value."
  (let* ((filename (if (listp minibuffer-default)
		       (car minibuffer-default)
		     minibuffer-default))
	 (commands (and filename (require 'dired-aux)
                        (shell-command-guess (list filename)))))
    (setq commands (mapcar (lambda (command)
			     (concat command " " filename))
			   commands))
    (if (listp minibuffer-default)
	(append minibuffer-default commands)
      (cons minibuffer-default commands))))

(declare-function shell-completion-vars "shell" ())

(defvar minibuffer-local-shell-command-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map minibuffer-local-map)
    (define-key map "\t"       #'completion-at-point)
    (define-key map [M-up]     #'minibuffer-previous-completion)
    (define-key map [M-down]   #'minibuffer-next-completion)
    (define-key map [?\M-\r]   #'minibuffer-choose-completion)
    map)
  "Keymap used for completing shell commands in minibuffer.")

(defun read-shell-command (prompt &optional initial-contents hist &rest args)
  "Read a shell command from the minibuffer, and return it as a string.
The arguments are the same as the ones of `read-from-minibuffer',
except READ and KEYMAP are missing and HIST defaults
to `shell-command-history'."
  (require 'shell)
  (minibuffer-with-setup-hook
      (lambda ()
        (shell-completion-vars)
        (setq-local minibuffer-default-add-function
                    #'minibuffer-default-add-shell-commands))
    (apply #'read-from-minibuffer prompt initial-contents
	   minibuffer-local-shell-command-map
	   nil
	   (or hist 'shell-command-history)
	   args)))

(defcustom async-shell-command-buffer 'confirm-new-buffer
  "What to do when the output buffer is used by another shell command.
This option specifies how to resolve the conflict where a new command
wants to direct its output to the buffer whose name is stored
in `shell-command-buffer-name-async', but that buffer is already
taken by another running shell command.

The value `confirm-kill-process' is used to ask for confirmation before
killing the already running process and running a new process
in the same buffer, `confirm-new-buffer' for confirmation before running
the command in a new buffer with a name other than the default buffer name,
`new-buffer' for doing the same without confirmation,
`confirm-rename-buffer' for confirmation before renaming the existing
output buffer and running a new command in the default buffer,
`rename-buffer' for doing the same without confirmation."
  :type '(choice (const :tag "Confirm killing of running command"
			confirm-kill-process)
		 (const :tag "Confirm creation of a new buffer"
			confirm-new-buffer)
		 (const :tag "Create a new buffer"
			new-buffer)
		 (const :tag "Confirm renaming of existing buffer"
			confirm-rename-buffer)
		 (const :tag "Rename the existing buffer"
			rename-buffer))
  :group 'shell
  :version "24.3")

(defcustom async-shell-command-display-buffer t
  "Whether to display the command buffer immediately.
If t, display the buffer immediately; if nil, wait until there
is output."
  :type '(choice (const :tag "Display buffer immediately"
			t)
		 (const :tag "Display buffer on output"
			nil))
  :group 'shell
  :version "26.1")

(defcustom async-shell-command-width nil
  "Number of display columns available for asynchronous shell command output.
If nil, use the shell default number (usually 80 columns).
If a positive integer, tell the shell to use that number of columns for
command output."
  :type '(choice (const :tag "Use system limit" nil)
                 (integer :tag "Fixed width" :value 80))
  :group 'shell
  :version "27.1")

(defcustom shell-command-prompt-show-cwd nil
  "If non-nil, show current directory when prompting for a shell command.
This affects `shell-command' and `async-shell-command'."
  :type 'boolean
  :group 'shell
  :version "27.1")

(defcustom shell-command-dont-erase-buffer nil
  "Whether to erase the output buffer before executing shell command.

A nil value erases the output buffer before execution of the
shell command, except when the output buffer is the current one.

The value `erase' ensures the output buffer is erased before
execution of the shell command even if it is the current buffer.

Other non-nil values prevent the output buffer from being erased; they
also reposition point in the shell output buffer after execution of the
shell command, except when the output buffer is the current buffer.

The value `beg-last-out' sets point at the beginning of the last
output, `end-last-out' sets point at the end of the last output,
and `save-point' restores the buffer position as it was before the
shell command."
  :type '(choice
          (const :tag "Erase output buffer if not the current one" nil)
          (const :tag "Always erase output buffer" erase)
          (const :tag "Set point to beginning of last output" beg-last-out)
          (const :tag "Set point to end of last output" end-last-out)
          (const :tag "Save point" save-point))
  :group 'shell
  :version "27.1")

(defvar shell-command-saved-pos nil
  "Record of point positions in output buffers after command completion.
The value is an alist whose elements are of the form (BUFFER . POS),
where BUFFER is the output buffer, and POS is the point position
in BUFFER once the command finishes.
This variable is used when `shell-command-dont-erase-buffer' is non-nil.")

(defun shell-command-save-pos-or-erase (&optional output-to-current-buffer)
  "Store a buffer position or erase the buffer.
Optional argument OUTPUT-TO-CURRENT-BUFFER, if non-nil, means that the output
of the shell command goes to the caller current buffer.

See `shell-command-dont-erase-buffer'."
  (let ((sym shell-command-dont-erase-buffer)
        pos)
    (setq buffer-read-only nil)
    ;; Setting buffer-read-only to nil doesn't suffice
    ;; if some text has a non-nil read-only property,
    ;; which comint sometimes adds for prompts.
    (setq pos
          (cond ((eq sym 'save-point)
                 (if (not output-to-current-buffer)
                     (point)))
                ((eq sym 'beg-last-out)
                 (if (not output-to-current-buffer)
                     (point-max)))
                ((or (eq sym 'erase)
                     (and (null sym) (not output-to-current-buffer)))
                 (let ((inhibit-read-only t))
                   (erase-buffer) nil))))
    (when pos
      (goto-char (point-max))
      (push (cons (current-buffer) pos)
            shell-command-saved-pos))))

(defun shell-command-set-point-after-cmd (&optional buffer)
  "Set point in BUFFER after command complete.
BUFFER is the output buffer of the command; if nil, then defaults
to the current BUFFER.
Set point to the `cdr' of the element in `shell-command-saved-pos'
whose `car' is BUFFER."
  (when shell-command-dont-erase-buffer
    (let* ((sym  shell-command-dont-erase-buffer)
           (buf  (or buffer (current-buffer)))
           (pos  (alist-get buf shell-command-saved-pos)))
      (setq shell-command-saved-pos
            (assq-delete-all buf shell-command-saved-pos))
      (when (buffer-live-p buf)
        (let ((win   (car (get-buffer-window-list buf)))
              (pmax  (with-current-buffer buf (point-max))))

          ;; The first time we run a command in a freshly created buffer
          ;; we have not saved positions yet; advance to `point-max', so that
          ;; successive commands know where to start.
          (unless (and pos (memq sym '(save-point beg-last-out end-last-out)))
            (setq pos pmax))
          ;; Set point in the window displaying buf, if any; otherwise
          ;; display buf temporary in selected frame and set the point.
          (if win
              (set-window-point win pos)
            (when pos
              (with-current-buffer buf (goto-char pos)))
            (save-window-excursion
              (let ((win (display-buffer
                          buf
                          '(nil (inhibit-switch-frame . t)))))
                (set-window-point win pos)))))))))

;; Implementation note: the next function intentionally tries to use
;; the same signature as 'shell-command', although the 3rd arg is
;; currently ignored, to allow us to implement support for specifying
;; ERROR-BUFFER in the future.
(defun async-shell-command (command &optional output-buffer error-buffer)
  "Execute string COMMAND asynchronously in background.

Like `shell-command', but adds `&' at the end of COMMAND
to execute it asynchronously.

The output appears in OUTPUT-BUFFER, which could be a buffer or
the name of a buffer, and defaults to `shell-command-buffer-name-async'
if nil or omitted.  That buffer is in major mode specified by the
variable `async-shell-command-mode'.  Note that, unlike with
`shell-command', OUTPUT-BUFFER can only be a buffer, a buffer's name
(a string), or nil.

You can customize `async-shell-command-buffer' to specify what to do
when the buffer specified by `shell-command-buffer-name-async' is
already taken by another running shell command.

To run COMMAND without displaying the output in a window you can
configure `display-buffer-alist' to use the action
`display-buffer-no-window' for the buffer given by
`shell-command-buffer-name-async'.

Optional argument ERROR-BUFFER is for backward compatibility; it
is ignored, and error output of the async command is always
mingled with its regular output.

In Elisp, you will often be better served by calling `start-process'
directly, since it offers more control and does not impose the use of
a shell (with its need to quote arguments)."
  (interactive
   (list
    (read-shell-command (if shell-command-prompt-show-cwd
                            (format-message "Async shell command in `%s': "
                                            (abbreviate-file-name
                                             default-directory))
                          "Async shell command: ")
                        nil nil
			(let ((filename
			       (cond
				(buffer-file-name)
				((eq major-mode 'dired-mode)
				 (dired-get-filename nil t)))))
			  (and filename (file-relative-name filename))))
    nil
    ;; FIXME: the following argument is always ignored by 'shell-command',
    ;; when the command is invoked asynchronously, except, perhaps, when
    ;; 'default-directory' is remote.
    shell-command-default-error-buffer))
  (unless (string-match "&[ \t]*\\'" command)
    (setq command (concat command " &")))
  (shell-command command output-buffer error-buffer))

(declare-function comint-output-filter "comint" (process string))
(declare-function comint-term-environment "comint" ())

(defvar async-shell-command-mode 'shell-command-mode
  "Major mode to use for the output of asynchronous `shell-command'.")

(defun shell-command (command &optional output-buffer error-buffer)
  "Execute string COMMAND in inferior shell; display output, if any.
With prefix argument, insert the COMMAND's output at point.

Interactively, prompt for COMMAND in the minibuffer.
If `shell-command-prompt-show-cwd' is non-nil, show the current
directory in the prompt.

If COMMAND ends in `&', execute it asynchronously.
The output appears in the buffer whose name is specified
by `shell-command-buffer-name-async'.  That buffer is in major mode
specified by the variable `async-shell-command-mode'.  You can also use
`async-shell-command' that automatically adds `&'.

Otherwise, COMMAND is executed synchronously.  The output appears in
the buffer named by `shell-command-buffer-name'.  If the output is
short enough to display in the echo area (which is determined by the
variables `resize-mini-windows' and `max-mini-window-height'), it is
shown there, but it is nonetheless available in buffer named by
`shell-command-buffer-name' even though that buffer is not
automatically displayed.

To specify a coding system for converting non-ASCII characters
in the shell command output, use \\[universal-coding-system-argument] \
before this command.

Noninteractive callers can specify coding systems by binding
`coding-system-for-read' and `coding-system-for-write'.

The optional second argument OUTPUT-BUFFER, if non-nil,
says to put the output in some other buffer.
If OUTPUT-BUFFER is a buffer or buffer name, erase that buffer
and insert the output there; a non-nil value of
`shell-command-dont-erase-buffer' prevents the buffer from being
erased.  If OUTPUT-BUFFER is not a buffer and not nil (which happens
interactively when the prefix argument is given), insert the
output in current buffer after point leaving mark after it.  This
cannot be done asynchronously.

If OUTPUT-BUFFER is a buffer or buffer name different from the
current buffer, instead of outputting at point in that buffer,
the output will be appended at the end of that buffer.

The user option `shell-command-dont-erase-buffer', which see, controls
whether the output buffer is erased and where to put point after
the shell command.

If the command terminates without error, but generates output,
and you did not specify \"insert it in the current buffer\",
the output can be displayed in the echo area or in its buffer.
If the output is short enough to display in the echo area
\(determined by the variable `max-mini-window-height' if
`resize-mini-windows' is non-nil), it is shown there.
Otherwise, the buffer containing the output is displayed.
Note that if `shell-command-dont-erase-buffer' is non-nil,
the echo area could display more than just the output of the
last command.

If there is output and an error, and you did not specify \"insert it
in the current buffer\", a message about the error goes at the end
of the output.

If the optional third argument ERROR-BUFFER is non-nil, it is a buffer
or buffer name to which to direct the command's standard error output.
If it is nil, error output is mingled with regular output.
In an interactive call, the variable `shell-command-default-error-buffer'
specifies the value of ERROR-BUFFER.

In Elisp, you will often be better served by calling `call-process' or
`start-process' directly, since they offer more control and do not
impose the use of a shell (with its need to quote arguments)."

  (interactive
   (list
    (read-shell-command (if shell-command-prompt-show-cwd
                            (format-message "Shell command in `%s': "
                                            (abbreviate-file-name
                                             default-directory))
                          "Shell command: ")
                        nil nil
			(let ((filename
			       (cond
				(buffer-file-name)
				((eq major-mode 'dired-mode)
				 (dired-get-filename nil t)))))
			  (and filename (file-relative-name filename))))
    current-prefix-arg
    shell-command-default-error-buffer))
  ;; Look for a handler in case default-directory is a remote file name.
  (let ((handler
	 (find-file-name-handler (directory-file-name default-directory)
				 'shell-command)))
    (if handler
	(funcall handler 'shell-command command output-buffer error-buffer)
      (if (and output-buffer
               (not (string-match "[ \t]*&[ \t]*\\'" command))
               (or (eq output-buffer (current-buffer))
                   (and (stringp output-buffer) (eq (get-buffer output-buffer) (current-buffer)))
	           (not (or (bufferp output-buffer) (stringp output-buffer))))) ; Bug#39067
	  ;; Synchronous command with output in current buffer.
	  (let ((error-file
                 (and error-buffer
                      (make-temp-file
                       (expand-file-name "scor"
                                         (or small-temporary-file-directory
                                             temporary-file-directory))))))
	    (barf-if-buffer-read-only)
	    (push-mark nil t)
            (shell-command-save-pos-or-erase 'output-to-current-buffer)
	    ;; We do not use -f for csh; we will not support broken use of
	    ;; .cshrcs.  Even the BSD csh manual says to use
	    ;; "if ($?prompt) exit" before things that are not useful
	    ;; non-interactively.  Besides, if someone wants their other
	    ;; aliases for shell commands then they can still have them.
            (call-process-shell-command command nil (if error-file
                                                        (list t error-file)
                                                      t))
	    (when (and error-file (file-exists-p error-file))
              (when (< 0 (file-attribute-size (file-attributes error-file)))
                (with-current-buffer (get-buffer-create error-buffer)
                  (let ((pos-from-end (- (point-max) (point))))
                    (or (bobp)
                        (insert "\f\n"))
                    ;; Do no formatting while reading error file,
                    ;; because that can run a shell command, and we
                    ;; don't want that to cause an infinite recursion.
                    (format-insert-file error-file nil)
                    ;; Put point after the inserted errors.
                    (goto-char (- (point-max) pos-from-end)))
                  (display-buffer (current-buffer))))
	      (delete-file error-file))
	    ;; This is like exchange-point-and-mark, but doesn't
	    ;; activate the mark.  It is cleaner to avoid activation,
	    ;; even though the command loop would deactivate the mark
	    ;; because we inserted text.
	    (goto-char (prog1 (mark t)
			 (set-marker (mark-marker) (point)
				     (current-buffer)))))
	;; Output goes in a separate buffer.
	(if (string-match "[ \t]*&[ \t]*\\'" command)
	    ;; Command ending with ampersand means asynchronous.
            (let* ((_ (or (bufferp output-buffer)
                          (stringp output-buffer)
                          (error "Asynchronous shell commands cannot output to current buffer")))
                   (buffer (get-buffer-create
                            (or output-buffer shell-command-buffer-name-async)))
                   (bname (buffer-name buffer))
                   (proc (get-buffer-process buffer))
                   (directory default-directory))
	      ;; Remove the ampersand.
	      (setq command (substring command 0 (match-beginning 0)))
	      ;; Ask the user what to do with already running process.
	      (when proc
		(cond
		 ((eq async-shell-command-buffer 'confirm-kill-process)
		  ;; If will kill a process, query first.
                  (shell-command--same-buffer-confirm "Kill it")
		  (kill-process proc))
		 ((eq async-shell-command-buffer 'confirm-new-buffer)
		  ;; If will create a new buffer, query first.
                  (shell-command--same-buffer-confirm "Use a new buffer")
                  (setq buffer (generate-new-buffer bname)))
		 ((eq async-shell-command-buffer 'new-buffer)
		  ;; It will create a new buffer.
                  (setq buffer (generate-new-buffer bname)))
		 ((eq async-shell-command-buffer 'confirm-rename-buffer)
		  ;; If will rename the buffer, query first.
                  (shell-command--same-buffer-confirm "Rename it")
		  (with-current-buffer buffer
		    (rename-uniquely))
                  (setq buffer (get-buffer-create bname)))
		 ((eq async-shell-command-buffer 'rename-buffer)
		  ;; It will rename the buffer.
		  (with-current-buffer buffer
		    (rename-uniquely))
                  (setq buffer (get-buffer-create bname)))))
	      (with-current-buffer buffer
                (shell-command-save-pos-or-erase)
		(setq default-directory directory)
                ;; There could be left connection-local values.  (Bug#76888)
                (kill-local-variable 'shell-file-name)
                (kill-local-variable 'shell-command-switch)
                (require 'shell)
                (let ((process-environment
                       (append
                        (and (natnump async-shell-command-width)
                             (list
                              (format "COLUMNS=%d"
                                      async-shell-command-width)))
                        (comint-term-environment)
                        process-environment)))
		  (setq proc
			(start-process-shell-command "Shell" buffer command)))
		(setq mode-line-process '(":%s"))
                (funcall async-shell-command-mode)
                (setq-local revert-buffer-function
                            (lambda (&rest _)
                              (async-shell-command command buffer)))
                (set-process-sentinel proc #'shell-command-sentinel)
		;; Use the comint filter for proper handling of
		;; carriage motion (see comint-inhibit-carriage-motion).
                (set-process-filter proc #'comint-output-filter)
                (if async-shell-command-display-buffer
                    ;; Display buffer immediately.
                    (display-buffer buffer '(nil (allow-no-window . t)))
                  ;; Defer displaying buffer until first process output.
                  ;; Use disposable named advice so that the buffer is
                  ;; displayed at most once per process lifetime.
                  (let ((nonce (make-symbol "nonce")))
                    (add-function :before (process-filter proc)
                                  (lambda (proc _string)
                                    (let ((buf (process-buffer proc)))
                                      (when (buffer-live-p buf)
                                        (remove-function (process-filter proc)
                                                         nonce)
                                        (display-buffer buf '(nil (allow-no-window . t))))))
                                  `((name . ,nonce)))))))
	  ;; Otherwise, command is executed synchronously.
	  (shell-command-on-region (point) (point) command
				   output-buffer nil error-buffer))))))

(defun shell-command--same-buffer-confirm (action)
  (let ((help-form
         (format
          "There's a command already running in the default buffer,
so we can't start a new one in the same one.

Answering \"yes\" will %s.

Answering \"no\" will exit without doing anything, and won't
start the new command.

Also see the `async-shell-command-buffer' variable."
          (downcase action))))
    (unless (yes-or-no-p
             (format "A command is running in the default buffer.  %s? "
                     action))
      (user-error "Shell command in progress"))))

(defun file-user-uid ()
  "Return the connection-local effective uid.
This is similar to `user-uid', but may invoke a file name handler
based on `default-directory'.  See Info node `(elisp)Magic File
Names'.

If a file name handler is unable to retrieve the effective uid,
this function will instead return -1."
  (if-let* ((handler (find-file-name-handler default-directory 'file-user-uid)))
      (funcall handler 'file-user-uid)
    (user-uid)))

(defun file-group-gid ()
  "Return the connection-local effective gid.
This is similar to `group-gid', but may invoke a file name handler
based on `default-directory'.  See Info node `(elisp)Magic File
Names'.

If a file name handler is unable to retrieve the effective gid,
this function will instead return -1."
  (if-let* ((handler (find-file-name-handler default-directory 'file-group-gid)))
      (funcall handler 'file-group-gid)
    (group-gid)))

(defun max-mini-window-lines (&optional frame)
  "Compute maximum number of lines for echo area in FRAME.
As defined by `max-mini-window-height'.  FRAME defaults to the
selected frame.  Result may be a floating-point number,
i.e. include a fractional number of lines."
  (cond ((floatp max-mini-window-height) (* (frame-height frame)
					    max-mini-window-height))
	((integerp max-mini-window-height) max-mini-window-height)
	(t 1)))

(defun display-message-or-buffer (message &optional buffer-name action frame)
  "Display MESSAGE in the echo area if possible, otherwise in a pop-up buffer.
MESSAGE may be either a string or a buffer.

A pop-up buffer is displayed using `display-buffer' if MESSAGE is too long
for maximum height of the echo area, as defined by `max-mini-window-lines'
if `resize-mini-windows' is non-nil.

Returns either the string shown in the echo area, or when a pop-up
buffer is used, the window used to display it.

If MESSAGE is a string, then the optional argument BUFFER-NAME is the
name of the buffer used to display it in the case where a pop-up buffer
is used, defaulting to `*Message*'.  In the case where MESSAGE is a
string and it is displayed in the echo area, it is not specified whether
the contents are inserted into the buffer anyway.

Optional arguments ACTION and FRAME are as for `display-buffer',
and are used only if a pop-up buffer is displayed."
  (cond ((and (stringp message) (not (string-search "\n" message)))
	 ;; Trivial case where we can use the echo area
	 (message "%s" message))
	((and (stringp message)
	      (= (string-search "\n" message) (1- (length message))))
	 ;; Trivial case where we can just remove single trailing newline
	 (message "%s" (substring message 0 (1- (length message)))))
	(t
	 ;; General case
	 (with-current-buffer
	     (if (bufferp message)
		 message
	       (get-buffer-create (or buffer-name "*Message*")))

	   (unless (bufferp message)
	     (erase-buffer)
	     (insert message))

	   (let ((lines
		  (if (= (buffer-size) 0)
		      0
		    (count-screen-lines nil nil nil (minibuffer-window)))))
	     (cond ((= lines 0))
		   ((and (or (<= lines 1)
			     (<= lines
				 (if resize-mini-windows (max-mini-window-lines)
				   1)))
			 ;; Don't use the echo area if the output buffer is
			 ;; already displayed in the selected frame.
			 (not (get-buffer-window (current-buffer))))
		    ;; Echo area
		    (goto-char (point-max))
		    (when (bolp)
		      (backward-char 1))
		    (message "%s" (buffer-substring (point-min) (point))))
		   (t
		    ;; Buffer
		    (goto-char (point-min))
		    (display-buffer (current-buffer) action frame))))))))


;; We have a sentinel to prevent insertion of a termination message
;; in the buffer itself, and to set the point in the buffer when
;; `shell-command-dont-erase-buffer' is non-nil.
;; For remote shells, `process-command' does not serve the proper shell
;; command.  We use process property `remote-command' instead.  (Bug#71049)
(defun shell-command-sentinel (process signal)
  (when (memq (process-status process) '(exit signal))
    (shell-command-set-point-after-cmd (process-buffer process))
    (message "%s: %s."
             (car (cdr (cdr (or (process-get process 'remote-command)
                                (process-command process)))))
             (substring signal 0 -1))))

(defun shell-command-on-region (start end command
				      &optional output-buffer replace
				      error-buffer display-error-buffer
				      region-noncontiguous-p)
  "Execute string COMMAND in inferior shell with region as input.
Normally display output (if any) in temp buffer specified
by `shell-command-buffer-name'; prefix arg means replace the region
with it.  Return the exit code of COMMAND.

To specify a coding system for converting non-ASCII characters
in the input and output to the shell command, use \\[universal-coding-system-argument]
before this command.  By default, the input (from the current buffer)
is encoded using coding-system specified by `process-coding-system-alist',
falling back to `default-process-coding-system' if no match for COMMAND
is found in `process-coding-system-alist'.

Noninteractive callers can specify coding systems by binding
`coding-system-for-read' and `coding-system-for-write'.

If the command generates output, the output may be displayed
in the echo area or in a buffer.
If the output is short enough to display in the echo area
\(determined by the variable `max-mini-window-height' if
`resize-mini-windows' is non-nil), it is shown there.
Otherwise it is displayed in the buffer named by `shell-command-buffer-name'.
The output is available in that buffer in both cases.
Note that if `shell-command-dont-erase-buffer' is non-nil,
the echo area could display more than just the output of the
last command.

If there is output and an error, a message about the error
appears at the end of the output.

Optional fourth arg OUTPUT-BUFFER specifies where to put the
command's output.  If the value is a buffer or buffer name,
erase that buffer and insert the output there; a non-nil value of
`shell-command-dont-erase-buffer' prevents erasing the buffer.
If the value is nil, use the buffer specified by `shell-command-buffer-name'.
Any other non-nil value means to insert the output in the
current buffer after START.

Optional fifth arg REPLACE, if non-nil, means to insert the
output in place of text from START to END, putting point and mark
around it.  If REPLACE is the symbol `no-mark', don't set the mark.

Optional sixth arg ERROR-BUFFER, if non-nil, specifies a buffer
or buffer name to which to direct the command's standard error
output.  If nil, error output is mingled with regular output.
When called interactively, `shell-command-default-error-buffer'
is used for ERROR-BUFFER.

Optional seventh arg DISPLAY-ERROR-BUFFER, if non-nil, means to
display the error buffer if there were any errors.  When called
interactively, this is t.

Non-nil REGION-NONCONTIGUOUS-P means that the region is composed of
noncontiguous pieces.  The most common example of this is a
rectangular region, where the pieces are separated by newline
characters.

If COMMAND names a shell (e.g., via `shell-file-name'), keep in mind
that behavior of various shells when commands are piped to their
standard input is shell- and system-dependent, and thus non-portable.
The differences are especially prominent when the region includes
more than one line, i.e. when piping to a shell commands with embedded
newlines."
  (interactive (let (string)
		 (unless (mark)
		   (user-error "The mark is not set now, so there is no region"))
		 ;; Do this before calling region-beginning
		 ;; and region-end, in case subprocess output
		 ;; relocates them while we are in the minibuffer.
		 (setq string (read-shell-command "Shell command on region: "))
		 ;; call-interactively recognizes region-beginning and
		 ;; region-end specially, leaving them in the history.
		 (list (region-beginning) (region-end)
		       string
		       current-prefix-arg
		       current-prefix-arg
		       shell-command-default-error-buffer
		       t
		       (region-noncontiguous-p))))
  (let ((error-file
	 (if error-buffer
	     (make-temp-file
	      (expand-file-name "scor"
				(or small-temporary-file-directory
				    temporary-file-directory)))
	   nil))
	exit-status)
    ;; Unless a single contiguous chunk is selected, operate on multiple chunks.
    (if region-noncontiguous-p
        (let ((input (concat (funcall region-extract-function (when replace 'delete)) "\n"))
              output)
          (with-temp-buffer
            (insert input)
            (call-process-region (point-min) (point-max)
                                 shell-file-name t t
                                 nil shell-command-switch
                                 command)
            (setq output (split-string (buffer-substring
                                        (point-min)
                                        ;; Trim the trailing newline.
                                        (if (eq (char-before (point-max)) ?\n)
                                            (1- (point-max))
                                          (point-max)))
                                       "\n")))
          (cond
           (replace
            (goto-char start)
            (funcall region-insert-function output))
           (t
            (let ((buffer (get-buffer-create
                           (or output-buffer shell-command-buffer-name))))
              (with-current-buffer buffer
                (erase-buffer)
                (funcall region-insert-function output))
              (display-message-or-buffer buffer)))))
      (if (or replace
              (and output-buffer
                   (not (or (bufferp output-buffer) (stringp output-buffer)))))
          ;; Replace specified region with output from command.
          (let ((swap (and replace (< start end))))
            ;; Don't muck with mark unless REPLACE says we should.
            (goto-char start)
            (when (and replace
                       (not (eq replace 'no-mark)))
              (push-mark (point) 'nomsg))
            (setq exit-status
                  (call-shell-region start end command replace
                                       (if error-file
                                           (list t error-file)
                                         t)))
            ;; It is rude to delete a buffer that the command is not using.
            ;; (let ((shell-buffer (get-buffer shell-command-buffer-name)))
            ;;   (and shell-buffer (not (eq shell-buffer (current-buffer)))
            ;; 	 (kill-buffer shell-buffer)))
            ;; Don't muck with mark unless REPLACE says we should.
            (when (and replace swap
                       (not (eq replace 'no-mark)))
              (exchange-point-and-mark)))
        ;; No prefix argument: put the output in a temp buffer,
        ;; replacing its entire contents.
        (let ((buffer (get-buffer-create
                       (or output-buffer shell-command-buffer-name))))
          (set-buffer-major-mode buffer) ; Enable globalized modes (bug#38111)
          (unwind-protect
              (if (and (eq buffer (current-buffer))
                       (or (memq shell-command-dont-erase-buffer '(nil erase))
                           (and (not (eq buffer (get-buffer
                                                 shell-command-buffer-name)))
                                (not (region-active-p)))))
                  ;; If the input is the same buffer as the output,
                  ;; delete everything but the specified region,
                  ;; then replace that region with the output.
                  (progn (setq buffer-read-only nil)
                         (delete-region (max start end) (point-max))
                         (delete-region (point-min) (min start end))
                         (setq exit-status
                               (call-process-region (point-min) (point-max)
                                                    shell-file-name t
                                                    (if error-file
                                                        (list t error-file)
                                                      t)
                                                    nil shell-command-switch
                                                    command)))
                ;; Clear the output buffer, then run the command with
                ;; output there.
                (let ((directory default-directory))
                  (with-current-buffer buffer
                    (if (not output-buffer)
                        (setq default-directory directory))
                    (shell-command-save-pos-or-erase)))
                (setq exit-status
                      (call-shell-region start end command nil
                                           (if error-file
                                               (list buffer error-file)
                                             buffer))))
            ;; Report the output.
            (with-current-buffer buffer
              (setq-local revert-buffer-function
                          (lambda (&rest _)
                            (shell-command command)))
              (setq mode-line-process
                    (cond ((null exit-status)
                           " - Error")
                          ((stringp exit-status)
                           (format " - Signal [%s]" exit-status))
                          ((not (equal 0 exit-status))
                           (format " - Exit [%d]" exit-status)))))
            (if (with-current-buffer buffer (> (point-max) (point-min)))
                ;; There's some output, display it
                (progn
                  (display-message-or-buffer buffer)
                  (shell-command-set-point-after-cmd buffer))
            ;; No output; error?
              (let ((output
                     (if (and error-file
                              (< 0 (file-attribute-size
				    (file-attributes error-file))))
                         (format "some error output%s"
                                 (if shell-command-default-error-buffer
                                     (format " to the \"%s\" buffer"
                                             shell-command-default-error-buffer)
                                   ""))
                       "no output")))
                (cond ((null exit-status)
                       (message "(Shell command failed with error)"))
                      ((equal 0 exit-status)
                       (message "(Shell command succeeded with %s)"
                                output))
                      ((stringp exit-status)
                       (message "(Shell command killed by signal %s)"
                                exit-status))
                      (t
                       (message "(Shell command failed with code %d and %s)"
                                exit-status output))))
              ;; Don't kill: there might be useful info in the undo-log.
              ;; (kill-buffer buffer)
              )))))

    (when (and error-file (file-exists-p error-file))
      (if (< 0 (file-attribute-size (file-attributes error-file)))
	  (with-current-buffer (get-buffer-create error-buffer)
            (goto-char (point-max))
            ;; Insert a separator if there's already text here.
	    (unless (bobp)
	      (insert "\f\n"))
	    ;; Do no formatting while reading error file,
	    ;; because that can run a shell command, and we
	    ;; don't want that to cause an infinite recursion.
	    (format-insert-file error-file nil)
	    (and display-error-buffer
		 (display-buffer (current-buffer)))))
      (delete-file error-file))
    exit-status))

(defun shell-command-to-string (command)
  "Execute shell command COMMAND and return its output as a string.
Use `shell-quote-argument' to quote dangerous characters in
COMMAND before passing it as an argument to this function.

Use this function only when a shell interpreter is needed.  In
other cases, consider alternatives such as `call-process' or
`process-lines', which do not invoke the shell.  Consider using
built-in functions like `rename-file' instead of the external
command \"mv\".  For more information, see Info node
`(elisp)Security Considerations'.

If COMMAND includes several separate commands to run one after
the other, the separator between the individual commands needs
to be shell- and system-dependent.  In particular, the MS-Windows
shell cmd.exe doesn't support commands with embedded newlines;
use the \"&&\" separator instead."
  (with-output-to-string
    (with-current-buffer standard-output
      (shell-command command t))))

(defun process-file (program &optional infile buffer display &rest args)
  "Process files synchronously in a separate process that runs PROGRAM.
Similar to `call-process', but may invoke a file name handler based on
`default-directory'.  The current working directory of the
subprocess is `default-directory'.

If PROGRAM is a remote file name, it should be processed
by `file-local-name' before passing it to this function.

Handle file names in INFILE and BUFFER normally; this differs
from `call-process', which does not support file name handlers
for INFILE and BUFFER.  However, pass ARGS to the process
verbatim without file name handling, as `call-process' does.

Some file name handlers might not support all variants.  For
example, they might treat DISPLAY as nil regardless of the actual
value passed."
  (let ((fh (find-file-name-handler default-directory 'process-file))
        lc stderr-file)
    (unwind-protect
        (if fh (apply fh 'process-file program infile buffer display args)
          (when infile (setq lc (file-local-copy infile)))
          (setq stderr-file (when (and (consp buffer) (stringp (cadr buffer)))
                              (make-temp-file "emacs")))
          (prog1
              (apply 'call-process program
                     (or lc infile)
                     (if stderr-file (list (car buffer) stderr-file) buffer)
                     display args)
            (when stderr-file (copy-file stderr-file (cadr buffer) t))))
      (when stderr-file (delete-file stderr-file))
      (when lc (delete-file lc)))))

(defvar process-file-side-effects t
  "Whether a call of `process-file' changes remote files.

By default, this variable is always set to t, meaning that a
call of `process-file' could potentially change any file on a
remote host.  When set to nil, a file name handler could optimize
its behavior with respect to remote file attribute caching.

You should only ever change this variable with a let-binding;
never with `setq'.")

(defcustom process-file-return-signal-string nil
  "Whether to return a string describing the signal interrupting a process.
When a process returns an exit code greater than 128, it is
interpreted as a signal.  `process-file' requires returning a
string describing this signal.
Since there are processes violating this rule, returning exit
codes greater than 128 which are not bound to a signal,
`process-file' returns the exit code as natural number also in
this case.  Setting this user option to non-nil forces
`process-file' to interpret such exit codes as signals, and to
return a corresponding string."
  :version "28.1"
  :type 'boolean)

(defun start-file-process (name buffer program &rest program-args)
  "Start a program in a subprocess.  Return the process object for it.

Similar to `start-process', but may invoke a file name handler based on
`default-directory'.  See Info node `(elisp)Magic File Names'.

This handler ought to run PROGRAM, perhaps on the local host,
perhaps on a remote host that corresponds to `default-directory'.
In the latter case, the local part of `default-directory', the one
produced from it by `file-local-name', becomes the working directory
of the process on the remote host.

PROGRAM and PROGRAM-ARGS might be file names.  They are not
objects of file name handler invocation, so they need to be obtained
by calling `file-local-name', in case they are remote file names.

File name handlers might not support pty association, if PROGRAM is nil."
  (let ((fh (find-file-name-handler default-directory 'start-file-process)))
    (if fh (apply fh 'start-file-process name buffer program program-args)
      (apply 'start-process name buffer program program-args))))

;;;; Process menu

(defvar tabulated-list-format)
(defvar tabulated-list-entries)
(defvar tabulated-list-sort-key)
(declare-function tabulated-list-init-header  "tabulated-list" ())
(declare-function tabulated-list-print "tabulated-list"
                  (&optional remember-pos update))

(defvar process-menu-query-only nil)

(defvar-keymap process-menu-mode-map
  "d" #'process-menu-delete-process)

(define-derived-mode process-menu-mode tabulated-list-mode "Process Menu"
  "Major mode for listing the processes called by Emacs."
  (setq tabulated-list-format [("Process" 15 t)
			       ("PID"      7 t)
			       ("Status"   7 t)
                               ;; 25 is the length of the long standard buffer
                               ;; name "*Async Shell Command*<10>" (bug#30016)
			       ("Buffer"  25 t)
			       ("TTY"     12 t)
			       ("Thread"  12 t)
			       ("Command"  0 t)])
  (make-local-variable 'process-menu-query-only)
  (setq tabulated-list-sort-key (cons "Process" nil))
  (add-hook 'tabulated-list-revert-hook 'list-processes--refresh nil t))

(defun process-menu-delete-process ()
  "Kill process at point in a `list-processes' buffer."
  (interactive)
  (let ((pos (point)))
    (delete-process (tabulated-list-get-id))
    (revert-buffer)
    (goto-char (min pos (point-max)))
    (if (eobp)
        (forward-line -1)
      (beginning-of-line))))

(declare-function thread-name "thread.c")

(defun list-processes--refresh ()
  "Recompute the list of processes for the Process List buffer.
Also, delete any process that is exited or signaled."
  (setq tabulated-list-entries nil)
  (dolist (p (process-list))
    (cond ((memq (process-status p) '(exit signal closed))
	   (delete-process p))
	  ((or (not process-menu-query-only)
	       (process-query-on-exit-flag p))
	   (let* ((buf (process-buffer p))
		  (type (process-type p))
		  (pid  (if (process-id p) (format "%d" (process-id p)) "--"))
		  (name (process-name p))
		  (status (symbol-name (process-status p)))
		  (buf-label (if (buffer-live-p buf)
				 `(,(buffer-name buf)
				   face link
				   help-echo ,(format-message
					       "Visit buffer `%s'"
					       (buffer-name buf))
				   follow-link t
				   process-buffer ,buf
				   action process-menu-visit-buffer)
			       "--"))
		  (tty (or (process-tty-name p) "--"))
		  (thread
                   (cond
                    ((or
                      (null (process-thread p))
                      (not (fboundp 'thread-name))) "--")
                    ((eq (process-thread p) main-thread) "Main")
		    ((thread-name (process-thread p)))
		    (t "--")))
		  (cmd
		   (if (memq type '(network serial pipe))
		       (let ((contact (process-contact p t t)))
			 (if (eq type 'network)
			     (format "(%s %s)"
				     (if (plist-get contact :type)
					 "datagram"
				       "network")
				     (if (plist-get contact :server)
					 (format
                                          "server on %s"
					  (if (plist-get contact :host)
                                              (format "%s:%s"
						      (plist-get contact :host)
                                                      (plist-get
                                                       contact :service))
					    (plist-get contact :local)))
				       (format "connection to %s:%s"
					       (plist-get contact :host)
					       (plist-get contact :service))))
			   (format "(serial port %s%s)"
				   (or (plist-get contact :port) "?")
				   (let ((speed (plist-get contact :speed)))
				     (if speed
					 (format " at %s b/s" speed)
				       "")))))
		     (mapconcat 'identity (process-command p) " "))))
	     (push (list p (vector name pid status buf-label tty thread cmd))
		   tabulated-list-entries)))))
  (tabulated-list-init-header))

(defun process-menu-visit-buffer (button)
  (display-buffer (button-get button 'process-buffer)))

(defun list-processes (&optional query-only buffer)
  "Display a list of all processes that are Emacs sub-processes.
If optional argument QUERY-ONLY is non-nil, only processes with
the query-on-exit flag set are listed.
Any process listed as exited or signaled is actually eliminated
after the listing is made.
Optional argument BUFFER specifies a buffer to use, instead of
\"*Process List*\".
The return value is always nil.

This function lists only processes that were launched by Emacs.  To
see other processes running on the system, use `list-system-processes'."
  (interactive)
  (or (fboundp 'process-list)
      (error "Asynchronous subprocesses are not supported on this system"))
  (unless (bufferp buffer)
    (setq buffer (get-buffer-create "*Process List*")))
  (with-current-buffer buffer
    (process-menu-mode)
    (setq process-menu-query-only query-only)
    (list-processes--refresh)
    (tabulated-list-print))
  (display-buffer buffer)
  nil)

;;;; Prefix commands

(setq prefix-command--needs-update nil)
(setq prefix-command--last-echo nil)

(defun internal-echo-keystrokes-prefix ()
  ;; BEWARE: Called directly from C code.
  ;; If the return value is non-nil, it means we are in the middle of
  ;; a command with prefix, such as a command invoked with prefix-arg.
  (if (not prefix-command--needs-update)
      prefix-command--last-echo
    (setq prefix-command--last-echo
          (let ((strs nil))
            (run-hook-wrapped 'prefix-command-echo-keystrokes-functions
                              (lambda (fun) (push (funcall fun) strs) nil))
            (setq strs (delq nil strs))
            (when strs (mapconcat #'identity strs " "))))))

(defvar prefix-command-echo-keystrokes-functions nil
  "Abnormal hook that constructs the description of the current prefix state.
Each function is called with no argument, should return a string or nil.")

(defun prefix-command-update ()
  "Update state of prefix commands.
Call it whenever you change the \"prefix command state\"."
  (setq prefix-command--needs-update t))

(defvar prefix-command-preserve-state-hook nil
  "Normal hook run when a command needs to preserve the prefix.")

(defun prefix-command-preserve-state ()
  "Pass the current prefix command state to the next command.
Should be called by all prefix commands.
Runs `prefix-command-preserve-state-hook'."
  (run-hooks 'prefix-command-preserve-state-hook)
  ;; If the current command is a prefix command, we don't want the next (real)
  ;; command to have `last-command' set to, say, `universal-argument'.
  (setq this-command last-command)
  (setq real-this-command real-last-command)
  (prefix-command-update))

(defun reset-this-command-lengths ()
  (declare (obsolete prefix-command-preserve-state "25.1"))
  nil)

;;;;; The main prefix command.

;; FIXME: Declaration of `prefix-arg' should be moved here!?

(add-hook 'prefix-command-echo-keystrokes-functions
          #'universal-argument--description)
(defun universal-argument--description ()
  (when prefix-arg
    (concat "C-u"
            (pcase prefix-arg
              ('(-) " -")
              (`(,(and (pred integerp) n))
               (let ((str ""))
                 (while (and (> n 4) (= (mod n 4) 0))
                   (setq str (concat str " C-u"))
                   (setq n (/ n 4)))
                 (if (= n 4) str (format " %s" prefix-arg))))
              (_ (format " %s" prefix-arg))))))

(add-hook 'prefix-command-preserve-state-hook
          #'universal-argument--preserve)
(defun universal-argument--preserve ()
  (setq prefix-arg current-prefix-arg)
  (setq current-prefix-arg last-prefix-arg))

(defvar universal-argument-map
  (let ((map (make-sparse-keymap))
        (universal-argument-minus
         ;; For backward compatibility, minus with no modifiers is an ordinary
         ;; command if digits have already been entered.
         `(menu-item "" negative-argument
                     :filter ,(lambda (cmd)
                                (if (integerp prefix-arg) nil cmd)))))
    (define-key map [switch-frame]
      (lambda (e) (interactive "e")
        (handle-switch-frame e) (universal-argument--mode)))
    (define-key map [?\C-u] 'universal-argument-more)
    (define-key map [?-] universal-argument-minus)
    (define-key map [?0] 'digit-argument)
    (define-key map [?1] 'digit-argument)
    (define-key map [?2] 'digit-argument)
    (define-key map [?3] 'digit-argument)
    (define-key map [?4] 'digit-argument)
    (define-key map [?5] 'digit-argument)
    (define-key map [?6] 'digit-argument)
    (define-key map [?7] 'digit-argument)
    (define-key map [?8] 'digit-argument)
    (define-key map [?9] 'digit-argument)
    (define-key map [kp-0] 'digit-argument)
    (define-key map [kp-1] 'digit-argument)
    (define-key map [kp-2] 'digit-argument)
    (define-key map [kp-3] 'digit-argument)
    (define-key map [kp-4] 'digit-argument)
    (define-key map [kp-5] 'digit-argument)
    (define-key map [kp-6] 'digit-argument)
    (define-key map [kp-7] 'digit-argument)
    (define-key map [kp-8] 'digit-argument)
    (define-key map [kp-9] 'digit-argument)
    (define-key map [kp-subtract] universal-argument-minus)
    map)
  "Keymap used while processing \\[universal-argument].")

(defun universal-argument--mode ()
  (prefix-command-update)
  (set-transient-map universal-argument-map nil))

(defun universal-argument ()
  "Begin a numeric argument for the following command.
Digits or minus sign following \\[universal-argument] make up the numeric argument.
\\[universal-argument] following the digits or minus sign ends the argument.
\\[universal-argument] without digits or minus sign provides 4 as argument.
Repeating \\[universal-argument] without digits or minus sign
 multiplies the argument by 4 each time.
For some commands, just \\[universal-argument] by itself serves as a flag
that is different in effect from any particular numeric argument.
These commands include \\[set-mark-command] and \\[start-kbd-macro]."
  (interactive)
  (prefix-command-preserve-state)
  (setq prefix-arg (list 4))
  (universal-argument--mode))

(defun universal-argument-more (arg)
  ;; A subsequent C-u means to multiply the factor by 4 if we've typed
  ;; nothing but C-u's; otherwise it means to terminate the prefix arg.
  (interactive "P")
  (prefix-command-preserve-state)
  (setq prefix-arg (if (consp arg)
                       (list (* 4 (car arg)))
                     (if (eq arg '-)
                         (list -4)
                       arg)))
  (when (consp prefix-arg) (universal-argument--mode)))

(defun negative-argument (arg)
  "Begin a negative numeric argument for the next command.
\\[universal-argument] following digits or minus sign ends the argument."
  (interactive "P")
  (prefix-command-preserve-state)
  (setq prefix-arg (cond ((integerp arg) (- arg))
                         ((eq arg '-) nil)
                         (t '-)))
  (universal-argument--mode))

(defun digit-argument (arg)
  "Part of the numeric argument for the next command.
\\[universal-argument] following digits or minus sign ends the argument."
  (interactive "P")
  (prefix-command-preserve-state)
  (let* ((char (if (integerp last-command-event)
		   last-command-event
		 (get last-command-event 'ascii-character)))
	 (digit (- (logand char ?\177) ?0)))
    (setq prefix-arg (cond ((integerp arg)
                            (+ (* arg 10)
			       (if (< arg 0) (- digit) digit)))
                           ((eq arg '-)
                            ;; Treat -0 as just -, so that -01 will work.
                            (if (zerop digit) '- (- digit)))
                           (t
                            digit))))
  (universal-argument--mode))


(defvar filter-buffer-substring-functions nil
  "This variable is a wrapper hook around `buffer-substring--filter'.
\(See `with-wrapper-hook' for details about wrapper hooks.)")
(make-obsolete-variable 'filter-buffer-substring-functions
                        'filter-buffer-substring-function "24.4")

(defvar filter-buffer-substring-function #'buffer-substring--filter
  "Function to perform the filtering in `filter-buffer-substring'.
The function is called with the same 3 arguments (BEG END DELETE)
that `filter-buffer-substring' received.  It should return the
buffer substring between BEG and END, after filtering.  If DELETE is
non-nil, it should delete the text between BEG and END from the buffer.")

(defun filter-buffer-substring (beg end &optional delete)
  "Return the buffer substring between BEG and END, after filtering.
If DELETE is non-nil, delete the text between BEG and END from the buffer.

This calls the function that `filter-buffer-substring-function' specifies
\(passing the same three arguments that it received) to do the work,
and returns whatever it does.  The default function does no filtering,
unless a hook has been set.

Use `filter-buffer-substring' instead of `buffer-substring',
`buffer-substring-no-properties', or `delete-and-extract-region' when
you want to allow filtering to take place.  For example, major or minor
modes can use `filter-buffer-substring-function' to exclude text properties
that are special to a buffer, and should not be copied into other buffers."
  (funcall filter-buffer-substring-function beg end delete))

(defun buffer-substring--filter (beg end &optional delete)
  "Default function to use for `filter-buffer-substring-function'.
Its arguments and return value are as specified for `filter-buffer-substring'.
Also respects the obsolete wrapper hook `filter-buffer-substring-functions'
(see `with-wrapper-hook' for details about wrapper hooks).
No filtering is done unless a hook says to."
  (subr--with-wrapper-hook-no-warnings
    filter-buffer-substring-functions (beg end delete)
    (cond
     (delete
      (save-excursion
        (goto-char beg)
        (delete-and-extract-region beg end)))
     (t
      (buffer-substring beg end)))))


;;;; Window system cut and paste hooks.

(defvar interprogram-cut-function #'gui-select-text
  "Function to call to make a killed region available to other programs.
Most window systems provide a facility for cutting and pasting
text between different programs, such as the clipboard on X and
MS-Windows, or the pasteboard on Nextstep/Mac OS.

This variable holds a function that Emacs calls whenever text is
put in the kill ring, to make the new kill available to other
programs.  The function takes one argument, TEXT, which is a
string containing the text that should be made available.")

(defvar interprogram-paste-function #'gui-selection-value
  "Function to call to get text cut from other programs.
Most window systems provide a facility for cutting and pasting
text between different programs, such as the clipboard on X and
MS-Windows, or the pasteboard on Nextstep/Mac OS.

This variable holds a function that Emacs calls to obtain text
that other programs have provided for pasting.  The function is
called with no arguments.  If no other program has provided text
to paste, the function should return nil (in which case the
caller, usually `current-kill', should use the top of the Emacs
kill ring).  If another program has provided text to paste, the
function should return that text as a string (in which case the
caller should put this string in the kill ring as the latest
kill).

The function may also return a list of strings if the window
system supports multiple selections.  The first string will be
used as the pasted text, but the other will be placed in the kill
ring for easy access via `yank-pop'.

Note that the function should return a string only if a program
other than Emacs has provided a string for pasting; if Emacs
provided the most recent string, the function should return nil.
If it is difficult to tell whether Emacs or some other program
provided the current string, it is probably good enough to return
nil if the string is equal (according to `string=') to the last
text Emacs provided.")



;;;; The kill ring data structure.

(defvar kill-ring nil
  "List of killed text sequences.
Since the kill ring is supposed to interact nicely with cut-and-paste
facilities offered by window systems, use of this variable should
interact nicely with `interprogram-cut-function' and
`interprogram-paste-function'.  The functions `kill-new',
`kill-append', and `current-kill' are supposed to implement this
interaction; you may want to use them instead of manipulating the kill
ring directly.")

(defcustom kill-ring-max 120
  "Maximum length of kill ring before oldest elements are thrown away."
  :type 'natnum
  :group 'killing
  :version "29.1")

(defvar kill-ring-yank-pointer nil
  "The tail of the kill ring whose car is the last thing yanked.")

(defcustom save-interprogram-paste-before-kill nil
  "Whether to save existing clipboard text into kill ring before replacing it.
A non-nil value means the clipboard text is saved to the `kill-ring'
prior to any kill command.  Such text can subsequently be retrieved
via \\[yank] \\[yank-pop].  This ensures that Emacs kill operations
do not irrevocably overwrite existing clipboard text.

The value of this variable can also be a number, in which case the
clipboard data is only saved to the `kill-ring' if it's shorter
(in characters) than that number.  Any other non-nil value will save
the clipboard data unconditionally."
  :type '(choice (const nil)
                 number
                 (other :tag "Always" t))
  :group 'killing
  :version "23.2")

(defcustom kill-do-not-save-duplicates nil
  "If non-nil, don't add a string to `kill-ring' if it duplicates the last one.
The comparison is done using `equal-including-properties'."
  :type 'boolean
  :group 'killing
  :version "23.2")

(defcustom kill-transform-function nil
  "Function to call to transform a string before it's put on the kill ring.
The function is called with one parameter (the string that's to
be put on the kill ring).  It should return a string or nil.  If
the latter, the string is not put on the kill ring."
  :type '(choice (const :tag "No transform" nil)
                 function)
  :group 'killing
  :version "28.1")

(defun kill-new (string &optional replace)
  "Make STRING the latest kill in the kill ring.
Set `kill-ring-yank-pointer' to point to it.
If `interprogram-cut-function' is non-nil, apply it to STRING.
Optional second argument REPLACE non-nil means that STRING will replace
the front of the kill ring, rather than being added to the list.

When `save-interprogram-paste-before-kill' and `interprogram-paste-function'
are non-nil, save the interprogram paste string(s) into `kill-ring' before
STRING.

When the yank handler has a non-nil PARAM element, the original STRING
argument is not used by `insert-for-yank'.  However, since Lisp code
may access and use elements from the kill ring directly, the STRING
argument should still be a \"useful\" string for such uses."
  ;; Allow the user to transform or ignore the string.
  (when (or (not kill-transform-function)
            (setq string (funcall kill-transform-function string)))
    (unless (and kill-do-not-save-duplicates
	         ;; Due to text properties such as 'yank-handler that
	         ;; can alter the contents to yank, comparison using
	         ;; `equal' is unsafe.
	         (equal-including-properties string (car kill-ring)))
      (if (fboundp 'menu-bar-update-yank-menu)
	  (menu-bar-update-yank-menu string (and replace (car kill-ring)))))
    (when save-interprogram-paste-before-kill
      (let ((interprogram-paste
             (and interprogram-paste-function
                  ;; On X, the selection owner might be slow, so the user might
                  ;; interrupt this. If they interrupt it, we want to continue
                  ;; so we become selection owner, so this doesn't stay slow.
                  (if (eq (window-system) 'x)
                      (ignore-error quit (funcall interprogram-paste-function))
                    (funcall interprogram-paste-function)))))
        (when interprogram-paste
          (setq interprogram-paste
                (if (listp interprogram-paste)
                    ;; Use `reverse' to avoid modifying external data.
                    (reverse interprogram-paste)
		  (list interprogram-paste)))
          (when (or (not (numberp save-interprogram-paste-before-kill))
                    (< (seq-reduce #'+ (mapcar #'length interprogram-paste) 0)
                       save-interprogram-paste-before-kill))
            (dolist (s interprogram-paste)
	      (unless (and kill-do-not-save-duplicates
                           (equal-including-properties s (car kill-ring)))
	        (push s kill-ring)))))))
    (unless (and kill-do-not-save-duplicates
	         (equal-including-properties string (car kill-ring)))
      (if (and replace kill-ring)
	  (setcar kill-ring string)
        (let ((history-delete-duplicates nil))
          (add-to-history 'kill-ring string kill-ring-max t))))
    (setq kill-ring-yank-pointer kill-ring)
    (if interprogram-cut-function
        (funcall interprogram-cut-function string))))

;; It has been argued that this should work like `self-insert-command'
;; which merges insertions in `buffer-undo-list' in groups of 20
;; (hard-coded in `undo-auto-amalgamate').
(defcustom kill-append-merge-undo nil
  "Amalgamate appending kills with the last kill for undo.
When non-nil, appending or prepending text to the last kill makes
\\[undo] restore both pieces of text simultaneously."
  :type 'boolean
  :group 'killing
  :version "25.1")

(defun kill-append (string before-p)
  "Append STRING to the end of the latest kill in the kill ring.
If BEFORE-P is non-nil, prepend STRING to the kill instead.
If `interprogram-cut-function' is non-nil, call it with the
resulting kill.
If `kill-append-merge-undo' is non-nil, remove the last undo
boundary in the current buffer."
  (let ((cur (car kill-ring)))
    (kill-new (if before-p (concat string cur) (concat cur string))
              (or (= (length cur) 0)
                  (null (get-text-property 0 'yank-handler cur)))))
  (when (and kill-append-merge-undo (not buffer-read-only))
    (let ((prev buffer-undo-list)
          (next (cdr buffer-undo-list)))
      ;; Find the next undo boundary.
      (while (car next)
        (pop next)
        (pop prev))
      ;; Remove this undo boundary.
      (when prev
        (setcdr prev (cdr next))))))

(defcustom yank-pop-change-selection nil
  "Whether rotating the kill ring changes the window system selection.
If non-nil, whenever the kill ring is rotated (usually via the
`yank-pop' command), Emacs also calls `interprogram-cut-function'
to copy the new kill to the window system selection."
  :type 'boolean
  :group 'killing
  :version "23.1")

(defun current-kill (n &optional do-not-move)
  "Rotate the yanking point by N places, and then return that kill.
If N is zero and `interprogram-paste-function' is set to a
function that returns a string or a list of strings, and if that
function doesn't return nil, then that string (or list) is added
to the front of the kill ring and the string (or first string in
the list) is returned as the latest kill.

If N is not zero, and if `yank-pop-change-selection' is
non-nil, use `interprogram-cut-function' to transfer the
kill at the new yank point into the window system selection.

If optional arg DO-NOT-MOVE is non-nil, then don't actually
move the yanking point; just return the Nth kill forward."

  (let ((interprogram-paste (and (= n 0)
				 interprogram-paste-function
				 (funcall interprogram-paste-function))))
    (if interprogram-paste
	(progn
	  ;; Disable the interprogram cut function when we add the new
	  ;; text to the kill ring, so Emacs doesn't try to own the
	  ;; selection, with identical text.
          ;; Also disable the interprogram paste function, so that
          ;; `kill-new' doesn't call it repeatedly.
          (let ((interprogram-cut-function nil)
                (interprogram-paste-function nil))
	    (if (listp interprogram-paste)
                ;; Use `reverse' to avoid modifying external data.
                (mapc #'kill-new (reverse interprogram-paste))
	      (kill-new interprogram-paste)))
	  (car kill-ring))
      (or kill-ring (error "Kill ring is empty"))
      (let ((ARGth-kill-element
	     (nthcdr (mod (- n (length kill-ring-yank-pointer))
			  (length kill-ring))
		     kill-ring)))
	(unless do-not-move
	  (setq kill-ring-yank-pointer ARGth-kill-element)
	  (when (and yank-pop-change-selection
		     (> n 0)
		     interprogram-cut-function)
	    (funcall interprogram-cut-function (car ARGth-kill-element))))
	(car ARGth-kill-element)))))



;;;; Commands for manipulating the kill ring.

(defcustom kill-read-only-ok nil
  "Non-nil means don't signal an error for killing read-only text."
  :type 'boolean
  :group 'killing)

(defcustom kill-region-dwim nil
  "Behavior when `kill-region' is invoked without an active region.
If set to nil (default), kill the region even if it is inactive,
signaling an error if there is no region.
If set to `emacs-word', kill the last word as defined by the
current major mode.
If set to `unix-word', kill the last word in the style of a shell like
Bash.  This ignores the major mode like `unix-word-rubout' (which see)."
  :type '(choice (const :tag "Kill region even when inactive" nil)
                 (const :tag "Kill a word like `backward-kill-word'" emacs-word)
                 (const :tag "Kill a word like Bash would" unix-word))
  :group 'killing
  :version "31.1")

(defun kill-region (beg end &optional region)
  "Kill (\"cut\") text between point and mark.
This deletes the text from the buffer and saves it in the kill ring.
The command \\[yank] can retrieve it from there.
\(If you want to save the region without killing it, use \\[kill-ring-save].)

If you want to append the killed region to the last killed text,
use \\[append-next-kill] before \\[kill-region].

Any command that calls this function is a \"kill command\".
If the previous command was also a kill command,
the text killed this time appends to the text killed last time
to make one entry in the kill ring.

The killed text is filtered by `filter-buffer-substring' before it is
saved in the kill ring, so the actual saved text might be different
from what was killed.

If the buffer is read-only, Emacs will beep and refrain from deleting
the text, but put the text in the kill ring anyway.  This means that
you can use the killing commands to copy text from a read-only buffer.

Lisp programs should use this function for killing text.
 (To delete text, use `delete-region'.)
Supply two arguments, character positions BEG and END indicating the
 stretch of text to be killed.  If the optional argument REGION is
 `region', the function ignores BEG and END, and kills the current
 region instead.  Interactively, REGION is always non-nil, and so
 this command always kills the current region.  It is possible to
 override this behavior by customizing the user option
 `kill-region-dwim'."
  ;; Pass mark first, then point, because the order matters when
  ;; calling `kill-append'.
  (interactive (progn
                 (let ((beg (mark kill-region-dwim))
                       (end (point)))
                   (cond
                    ((and kill-region-dwim (not (use-region-p)))
                     (list beg end kill-region-dwim))
                    ((not (and beg end))
                     (user-error "The mark is not set now, so there is no region"))
                    ((list beg end 'region))))))

  (condition-case nil
      (let ((string (cond
                     ((memq region '(unix-word emacs-word))
                      (let ((end (point)))
                        (save-excursion
                          (if (eq region 'emacs-word)
                              (forward-word -1)
                            (forward-unix-word -1))
                          (filter-buffer-substring (point) end 'delete))))
                     (region
                      (funcall region-extract-function 'delete))
                     ((filter-buffer-substring beg end 'delete)))))
	(when string			;STRING is nil if BEG = END
	  ;; Add that string to the kill ring, one way or another.
	  (if (and (not (memq region '(unix-word emacs-word)))
		   (eq last-command 'kill-region))
	      (kill-append string (< end beg))
	    (kill-new string)))
	(when (and (not (memq region '(unix-word emacs-word)))
		   (or string (eq last-command 'kill-region)))
	  (setq this-command 'kill-region))
	(setq deactivate-mark t)
	nil)
    ((buffer-read-only text-read-only)
     ;; The code above failed because the buffer, or some of the characters
     ;; in the region, are read-only.
     ;; We should beep, in case the user just isn't aware of this.
     ;; However, there's no harm in putting
     ;; the region's text in the kill ring, anyway.
     (copy-region-as-kill beg end region)
     ;; Set this-command now, so it will be set even if we get an error.
     (setq this-command 'kill-region)
     ;; This should barf, if appropriate, and give us the correct error.
     (if kill-read-only-ok
	 (progn (message "Read only text copied to kill ring") nil)
       ;; Signal an error if the buffer is read-only.
       (barf-if-buffer-read-only)
       ;; If the buffer isn't read-only, the text is.
       (signal 'text-read-only (list (current-buffer)))))))

;; copy-region-as-kill no longer sets this-command, because it's confusing
;; to get two copies of the text when the user accidentally types M-w and
;; then corrects it with the intended C-w.
(defun copy-region-as-kill (beg end &optional region)
  "Save the region as if killed, but don't kill it.
In Transient Mark mode, deactivate the mark.
If `interprogram-cut-function' is non-nil, also save the text for a window
system cut and paste.

The copied text is filtered by `filter-buffer-substring' before it is
saved in the kill ring, so the actual saved text might be different
from what was in the buffer.

When called from Lisp, save in the kill ring the stretch of text
between BEG and END, unless the optional argument REGION is
non-nil, in which case ignore BEG and END, and save the current
region instead.

This command's old key binding has been given to `kill-ring-save'."
  ;; Pass mark first, then point, because the order matters when
  ;; calling `kill-append'.
  (interactive (list (mark) (point) 'region))
  (let ((str (if region
                 (funcall region-extract-function nil)
               (filter-buffer-substring beg end))))
    (if (eq last-command 'kill-region)
        (kill-append str (< end beg))
      (kill-new str)))
  (setq deactivate-mark t)
  nil)

(defun kill-ring-save (beg end &optional region)
  "Save the region as if killed, but don't kill it.
In Transient Mark mode, deactivate the mark.
If `interprogram-cut-function' is non-nil, also save the text for a window
system cut and paste.

If you want to append the killed region to the last killed text,
use \\[append-next-kill] before \\[kill-ring-save].

The copied text is filtered by `filter-buffer-substring' before it is
saved in the kill ring, so the actual saved text might be different
from what was in the buffer.

When called from Lisp, save in the kill ring the stretch of text
between BEG and END, unless the optional argument REGION is
non-nil, in which case ignore BEG and END, and save the current
region instead.

This command is similar to `copy-region-as-kill', except that it gives
visual feedback indicating the extent of the region being copied."
  ;; Pass mark first, then point, because the order matters when
  ;; calling `kill-append'.
  (interactive (list (mark) (point) 'region))
  (copy-region-as-kill beg end region)
  ;; This use of called-interactively-p is correct because the code it
  ;; controls just gives the user visual feedback.
  (if (called-interactively-p 'interactive)
      (indicate-copied-region)))

(defcustom copy-region-blink-delay 1
  "Time in seconds to delay after showing the other end of the region.
It's used by the command `kill-ring-save' and the function
`indicate-copied-region' to blink the cursor between point and mark.
The value 0 disables blinking."
  :type 'number
  :group 'killing
  :version "28.1")

(defcustom copy-region-blink-predicate #'region-indistinguishable-p
  "Whether the cursor must be blinked after a copy.
When this condition holds, and the copied region fits in the
current window, `kill-ring-save' will blink the cursor between
point and mark for `copy-region-blink-delay' seconds."
  :type '(radio (function-item region-indistinguishable-p)
                (function-item :doc "Always blink point and mark." always)
                (function-item :doc "Never blink point and mark." ignore)
                (function :tag "Other predicate function"))
  :group 'killing
  :version "29.1")

(defun region-indistinguishable-p ()
  "Whether the current region is not denoted visually.
This holds when the region is inactive, or when the `region' face
cannot be distinguished from the `default' face."
  (not (and (region-active-p)
            (face-differs-from-default-p 'region))))

(defun indicate-copied-region (&optional message-len)
  "Indicate that the region text has been copied interactively.
If the mark is visible in the selected window, blink the cursor between
point and mark if there is currently no active region highlighting.
The option `copy-region-blink-delay' can disable blinking.

If the mark lies outside the selected window, display an
informative message containing a sample of the copied text.  The
optional argument MESSAGE-LEN, if non-nil, specifies the length
of this sample text; it defaults to 40."
  (let ((mark (mark t))
	(point (point))
	;; Inhibit quitting so we can make a quit here
	;; look like a C-g typed as a command.
	(inhibit-quit t))
    (if (pos-visible-in-window-p mark (selected-window))
	;; Swap point-and-mark quickly so as to show the region that
	;; was selected.  Don't do it if the region is highlighted.
	(when (and (numberp copy-region-blink-delay)
		   (> copy-region-blink-delay 0)
		   (funcall copy-region-blink-predicate))
	  ;; Swap point and mark.
	  (set-marker (mark-marker) (point) (current-buffer))
	  (goto-char mark)
	  (sit-for copy-region-blink-delay)
	  ;; Swap back.
	  (set-marker (mark-marker) mark (current-buffer))
	  (goto-char point)
	  ;; If user quit, deactivate the mark
	  ;; as C-g would as a command.
	  (and quit-flag (region-active-p)
	       (deactivate-mark)))
      (let ((len (min (abs (- mark point))
		      (or message-len 40))))
	(if (< point mark)
	    ;; Don't say "killed" or "saved"; that is misleading.
	    (message "Copied text until \"%s\""
		     ;; Don't show newlines literally
		     (query-replace-descr
		      (buffer-substring-no-properties (- mark len) mark)))
	  (message "Copied text from \"%s\""
		   (query-replace-descr
		    (buffer-substring-no-properties mark (+ mark len)))))))))

(defun append-next-kill (&optional interactive)
  "Cause following command, if it kills, to add to previous kill.
If the next command kills forward from point, the kill is
appended to the previous killed text.  If the command kills
backward, the kill is prepended.  Kill commands that act on the
region, such as `kill-region', are regarded as killing forward if
point is after mark, and killing backward if point is before
mark.

If the next command is not a kill command, `append-next-kill' has
no effect.

The argument is used for internal purposes; do not supply one."
  (interactive "p")
  ;; We don't use (interactive-p), since that breaks kbd macros.
  (if interactive
      (progn
	(setq this-command 'kill-region)
	(message "If the next command is a kill, it will append"))
    (setq last-command 'kill-region)))

(defvar bidi-directional-controls-chars "\x202a-\x202e\x2066-\x2069"
  "Character set that matches bidirectional formatting control characters.")

(defvar bidi-directional-non-controls-chars "^\x202a-\x202e\x2066-\x2069"
  "Character set that matches any character except bidirectional controls.")

(defun squeeze-bidi-context-1 (from to category replacement)
  "A subroutine of `squeeze-bidi-context'.
FROM and TO should be markers, CATEGORY and REPLACEMENT should be strings."
  (let ((pt (copy-marker from))
	(limit (copy-marker to))
	(old-pt 0)
	lim1)
    (setq lim1 limit)
    (goto-char pt)
    (while (< pt limit)
      (if (> pt old-pt)
	  (move-marker lim1
		       (save-excursion
			 ;; L and R categories include embedding and
			 ;; override controls, but we don't want to
			 ;; replace them, because that might change
			 ;; the visual order.  Likewise with PDF and
			 ;; isolate controls.
			 (+ pt (skip-chars-forward
				bidi-directional-non-controls-chars
				limit)))))
      ;; Replace any run of non-RTL characters by a single LRM.
      (if (null (re-search-forward category lim1 t))
	  ;; No more characters of CATEGORY, we are done.
	  (setq pt limit)
	(replace-match replacement nil t)
	(move-marker pt (point)))
      (setq old-pt pt)
      ;; Skip directional controls, if any.
      (move-marker
       pt (+ pt (skip-chars-forward bidi-directional-controls-chars limit))))))

(defun squeeze-bidi-context (from to)
  "Replace characters between FROM and TO while keeping bidi context.

This function replaces the region of text with as few characters
as possible, while preserving the effect that region will have on
bidirectional display before and after the region."
  (let ((start (set-marker (make-marker)
			   (if (> from 0) from (+ (point-max) from))))
	(end (set-marker (make-marker) to))
	;; This is for when they copy text with read-only text
	;; properties.
	(inhibit-read-only t))
    (if (null (marker-position end))
	(setq end (point-max-marker)))
    ;; Replace each run of non-RTL characters with a single LRM.
    (squeeze-bidi-context-1 start end "\\CR+" "\x200e")
    ;; Replace each run of non-LTR characters with a single RLM.  Note
    ;; that the \cR category includes both the Arabic Letter (AL) and
    ;; R characters; here we ignore the distinction between them,
    ;; because that distinction affects only Arabic Number (AN)
    ;; characters, which are weak and don't affect the reordering.
    (squeeze-bidi-context-1 start end "\\CL+" "\x200f")))

(defun line-substring-with-bidi-context (start end &optional no-properties)
  "Return buffer text between START and END with its bidi context.

START and END are assumed to belong to the same physical line
of buffer text.  This function prepends and appends to the text
between START and END bidi control characters that preserve the
visual order of that text when it is inserted at some other place."
  (if (or (< start (point-min))
	  (> end (point-max)))
      (signal 'args-out-of-range (list (current-buffer) start end)))
  (let ((buf (current-buffer))
	substr para-dir from to)
    (save-excursion
      (goto-char start)
      (setq para-dir (current-bidi-paragraph-direction))
      (setq from (line-beginning-position)
	    to (line-end-position))
      (goto-char from)
      ;; If we don't have any mixed directional characters in the
      ;; entire line, we can just copy the substring without adding
      ;; any context.
      (if (or (looking-at-p "\\CR*$")
	      (looking-at-p "\\CL*$"))
	  (setq substr (if no-properties
			   (buffer-substring-no-properties start end)
			 (buffer-substring start end)))
	(setq substr
	      (with-temp-buffer
		(if no-properties
		    (insert-buffer-substring-no-properties buf from to)
		  (insert-buffer-substring buf from to))
		(squeeze-bidi-context 1 (1+ (- start from)))
		(squeeze-bidi-context (- end to) nil)
		(buffer-substring 1 (point-max)))))

      ;; Wrap the string in LRI/RLI..PDI pair to achieve 2 effects:
      ;; (1) force the string to have the same base embedding
      ;; direction as the paragraph direction at the source, no matter
      ;; what is the paragraph direction at destination; and (2) avoid
      ;; affecting the visual order of the surrounding text at
      ;; destination if there are characters of different
      ;; directionality there.
      (concat (if (eq para-dir 'left-to-right) "\x2066" "\x2067")
	      substr "\x2069"))))

(defun buffer-substring-with-bidi-context (start end &optional no-properties)
  "Return portion of current buffer between START and END with bidi context.

This function works similar to `buffer-substring', but it prepends and
appends to the text bidi directional control characters necessary to
preserve the visual appearance of the text if it is inserted at another
place.  This is useful when the buffer substring includes bidirectional
text and control characters that cause non-trivial reordering on display.
If copied verbatim, such text can have a very different visual appearance,
and can also change the visual appearance of the surrounding text at the
destination of the copy.

Optional argument NO-PROPERTIES, if non-nil, means copy the text without
the text properties."
  (let (line-end substr)
    (if (or (< start (point-min))
	    (> end (point-max)))
	(signal 'args-out-of-range (list (current-buffer) start end)))
    (save-excursion
      (goto-char start)
      (setq line-end (min end (line-end-position)))
      (while (< start end)
	(setq substr
	      (concat substr
		      (if substr "\n" "")
		      (line-substring-with-bidi-context start line-end
							no-properties)))
	(forward-line 1)
	(setq start (point))
	(setq line-end (min end (line-end-position))))
      substr)))

;; Yanking.

(defcustom yank-handled-properties
  '((font-lock-face . yank-handle-font-lock-face-property)
    (category . yank-handle-category-property))
  "List of special text property handling conditions for yanking.
Each element should have the form (PROP . FUN), where PROP is a
property symbol and FUN is a function.  When the `yank' command
inserts text into the buffer, it scans the inserted text for
stretches of text that have `eq' values of the text property
PROP; for each such stretch of text, FUN is called with three
arguments: the property's value in that text, and the start and
end positions of the text.

This is done prior to removing the properties specified by
`yank-excluded-properties'."
  :group 'killing
  :type '(repeat (cons (symbol :tag "property symbol")
                       function))
  :version "24.3")

;; This is actually used in subr.el but defcustom does not work there.
(defcustom yank-excluded-properties
  '(category field follow-link fontified font-lock-face help-echo
    intangible invisible keymap local-map mouse-face read-only
    yank-handler)
  "Text properties to discard when yanking.
The value should be a list of text properties to discard or t,
which means to discard all text properties.

See also `yank-handled-properties'."
  :type '(choice (const :tag "All" t) (repeat symbol))
  :group 'killing
  :version "24.3")

(defvar yank-transform-functions nil
  "Hook run on strings to be yanked.
Each function in this list will be called (in order) with the
string to be yanked as the sole argument, and should return the (possibly)
transformed string.

The functions will be called with the destination buffer as the current
buffer, and with point at the place where the string is to be inserted.")

(defvar yank-window-start nil)
(defvar yank-undo-function nil
  "If non-nil, function used by `yank-pop' to delete last stretch of yanked text.
Function is called with two parameters, START and END corresponding to
the value of the mark and point; it is guaranteed that START <= END.
Normally set from the UNDO element of a yank-handler; see `insert-for-yank'.")

(defun yank-pop (&optional arg)
  "Replace just-yanked stretch of killed text with a different stretch.
The main use of this command is immediately after a `yank' or a
`yank-pop'.  At such a time, the region contains a stretch of
reinserted (\"pasted\") previously-killed text.  `yank-pop' deletes
that text and inserts in its place a different stretch of killed text
by traversing the value of the `kill-ring' variable and selecting
another kill from there.

With no argument, the previous kill is inserted.
With argument N, insert the Nth previous kill.
If N is negative, it means to use a more recent kill.

The sequence of kills wraps around, so if you keep invoking this command
time after time, and pass the oldest kill, you get the newest one.

You can also invoke this command after a command other than `yank'
or `yank-pop'.  This is the same as invoking `yank-from-kill-ring',
including the effect of the prefix argument; see there for the details.

This command honors the `yank-handled-properties' and
`yank-excluded-properties' variables, and the `yank-handler' text
property, in the way that `yank' does."
  (interactive "p")
  (if (not (eq last-command 'yank))
      (yank-from-kill-ring (read-from-kill-ring "Yank from kill-ring: ")
                           current-prefix-arg)
    (setq this-command 'yank)
    (unless arg (setq arg 1))
    (let ((inhibit-read-only t)
          (before (< (point) (mark t))))
      (if before
          (funcall (or yank-undo-function 'delete-region) (point) (mark t))
        (funcall (or yank-undo-function 'delete-region) (mark t) (point)))
      (setq yank-undo-function nil)
      (set-marker (mark-marker) (point) (current-buffer))
      (insert-for-yank (current-kill arg))
      ;; Set the window start back where it was in the yank command,
      ;; if possible.
      (set-window-start (selected-window) yank-window-start t)
      (if before
          ;; This is like exchange-point-and-mark, but doesn't activate the mark.
          ;; It is cleaner to avoid activation, even though the command
          ;; loop would deactivate the mark because we inserted text.
          (goto-char (prog1 (mark t)
                       (set-marker (mark-marker) (point) (current-buffer))))))
    nil))

(defun yank (&optional arg)
  "Reinsert (\"paste\") the last stretch of killed text.
More precisely, reinsert the most recent kill, which is the stretch of
text most recently killed OR yanked, as returned by `current-kill' (which
see).  Put point at the end, and set mark at the beginning without
activating it. With just \\[universal-argument] as argument, put point
at beginning, and mark at end.
With argument N, reinsert the Nth most recent kill.

This command honors the `yank-handled-properties' and
`yank-excluded-properties' variables, and the `yank-handler' text
property, as described below.

Properties listed in `yank-handled-properties' are processed,
then those listed in `yank-excluded-properties' are discarded.

STRING will be run through `yank-transform-functions'.
`yank-in-context' is a command that uses this mechanism to
provide a `yank' alternative that conveniently preserves
string/comment syntax.

If STRING has a non-nil `yank-handler' property anywhere, the
normal insert behavior is altered, and instead, for each contiguous
segment of STRING that has a given value of the `yank-handler'
property, that value is used as follows:

The value of a `yank-handler' property must be a list of one to four
elements, of the form (FUNCTION PARAM NOEXCLUDE UNDO).
FUNCTION, if non-nil, should be a function of one argument (the
 object to insert); FUNCTION is called instead of `insert'.
PARAM, if present and non-nil, is passed to FUNCTION (to be handled
 in whatever way is appropriate; e.g. if FUNCTION is `yank-rectangle',
 PARAM may be a list of strings to insert as a rectangle).  If PARAM
 is nil, then the current segment of STRING is used.
If NOEXCLUDE is present and non-nil, the normal removal of
 `yank-excluded-properties' is not performed; instead FUNCTION is
 responsible for the removal.  This may be necessary if FUNCTION
 adjusts point before or after inserting the object.
UNDO, if present and non-nil, should be a function to be called
 by `yank-pop' to undo the insertion of the current PARAM.  It is
 given two arguments, the start and end of the region.  FUNCTION
 may set `yank-undo-function' to override UNDO.

See also the command `yank-pop' (\\[yank-pop])."
  (interactive "*P")
  (setq yank-window-start (window-start))
  ;; If we don't get all the way thru, make last-command indicate that
  ;; for the following command.
  (setq this-command t)
  (push-mark)
  (insert-for-yank (current-kill (cond
				  ((listp arg) 0)
				  ((eq arg '-) -2)
				  (t (1- arg)))))
  (if (consp arg)
      ;; This is like exchange-point-and-mark, but doesn't activate the mark.
      ;; It is cleaner to avoid activation, even though the command
      ;; loop would deactivate the mark because we inserted text.
      (goto-char (prog1 (mark t)
		   (set-marker (mark-marker) (point) (current-buffer)))))
  ;; If we do get all the way thru, make this-command indicate that.
  (if (eq this-command t)
      (setq this-command 'yank))
  nil)

(defun rotate-yank-pointer (arg)
  "Rotate the yanking point in the kill ring.
With ARG, rotate that many kills forward (or backward, if negative)."
  (interactive "p")
  (current-kill arg))

(defun yank-in-context (&optional arg)
  "Insert the last stretch of killed text while preserving syntax.
In particular, if point is inside a string, any quote characters
in the killed text will be quoted, so that the string remains a
valid string.

If point is inside a comment, ensure that the inserted text is
also marked as a comment.

This command otherwise behaves as `yank'.  See that command for
explanation of ARG.

This function uses the `escaped-string-quote' buffer-local
variable to determine how strings should be escaped."
  (interactive "*P")
  (let ((yank-transform-functions (cons #'yank-in-context--transform
                                        yank-transform-functions)))
    (yank arg)))

(defun yank-in-context--transform (string)
  (let ((ppss (syntax-ppss)))
    (cond
     ;; We're in a string.
     ((ppss-string-terminator ppss)
      (string-replace
       (string (ppss-string-terminator ppss))
       (concat (if (functionp escaped-string-quote)
                   (funcall escaped-string-quote
                            (ppss-string-terminator ppss))
                 escaped-string-quote)
               (string (ppss-string-terminator ppss)))
       string))
     ;; We're in a comment.
     ((or (ppss-comment-depth ppss)
          (and (bolp)
               (not (eobp))
               ;; If we're in the middle of a bunch of commented text,
               ;; we probably want to be commented.  This is quite DWIM.
               (or (bobp)
                   (save-excursion
                     (forward-line -1)
                     (forward-char 1)
                     (ppss-comment-depth (syntax-ppss))))
               (ppss-comment-depth
                (setq ppss (save-excursion
                             (forward-char 1)
                             (syntax-ppss))))))
      (cond
       ((and (eq (ppss-comment-depth ppss) t)
             (> (length comment-end) 0)
             (string-search comment-end string))
        (user-error "Can't insert a string containing a comment terminator in a comment"))
       ;; If this is a comment syntax that has an explicit end, then
       ;; we can just insert as is.
       ((> (length comment-end) 0) string)
       ;; Line-based comment formats.
       ((or (string-search "\n" string)
            (bolp))
        (let ((mode major-mode)
              (bolp (bolp))
              (eolp (eolp))
              (comment-style 'plain))
          (with-temp-buffer
            (funcall mode)
            (insert string)
            (when (string-match-p "\n\\'" string)
              (cond
               ((not eolp) (delete-char -1))
               (bolp (insert "\n"))))
            (comment-normalize-vars)
            (comment-region-default-1
             (if bolp
                 (point-min)
               (save-excursion
                 (goto-char (point-min))
                 (forward-line 1)
                 (point)))
             (point-max))
            (buffer-string))))
       (t string)))
     (t string))))

(defvar read-from-kill-ring-history)
(defun read-from-kill-ring (prompt)
  "Read a `kill-ring' entry using completion and minibuffer history.
PROMPT is a string to prompt with.
Return the entry as a string."
  ;; `current-kill' updates `kill-ring' with a possible interprogram-paste
  (current-kill 0)
  (let* ((history-add-new-input nil)
         (history-pos (when yank-from-kill-ring-rotate
                        (- (length kill-ring)
                           (length kill-ring-yank-pointer))))
         (ellipsis (if (char-displayable-p ?…) "…" "..."))
         ;; Remove keymaps from text properties of copied string,
         ;; because typing RET in the minibuffer might call
         ;; an irrelevant command from the map of copied string.
         (read-from-kill-ring-history
          (mapcar (lambda (s)
                    (remove-list-of-text-properties
                     0 (length s)
                     '(
                       keymap local-map action mouse-action
                       read-only button category help-args)
                     s)
                    s)
                  kill-ring))
         (completions
          (mapcar (lambda (s)
                    (let* ((s (query-replace-descr s))
                           (b 0)
                           (limit (frame-text-cols)))
                      ;; Add ellipsis on leading whitespace
                      (when (string-match "\\`[[:space:]]+" s)
                        (setq b (match-end 0))
                        (add-text-properties 0 b `(display ,ellipsis) s))
                      ;; Add ellipsis at the end of a long string
                      (when (> (length s) (+ limit b))
                        (add-text-properties
                         (min (+ limit b) (length s)) (length s)
                         `(display ,ellipsis) s))
                      s))
                  read-from-kill-ring-history)))
    (minibuffer-with-setup-hook
        (lambda ()
          ;; Allow ‘SPC’ to be self-inserting
          (use-local-map
           (let ((map (make-sparse-keymap)))
             (set-keymap-parent map (current-local-map))
             (define-key map " " nil)
             (define-key map "?" nil)
             map)))
      (completing-read
       prompt
       ;; Keep sorted by recency
       (completion-table-with-metadata
        completions '((display-sort-function . identity)))
       nil nil nil
       (if history-pos
           (cons 'read-from-kill-ring-history
                 (if (zerop history-pos) history-pos (1+ history-pos)))
         'read-from-kill-ring-history)))))

(defcustom yank-from-kill-ring-rotate t
  "Whether using `yank-from-kill-ring' should rotate `kill-ring-yank-pointer'.
If non-nil, the kill ring is rotated after selecting previously killed text."
  :type 'boolean
  :group 'killing
  :version "28.1")

(defun yank-from-kill-ring (string &optional arg)
  "Select a stretch of previously killed text and insert (\"paste\") it.
This command allows you to select one of the stretches of text
killed or yanked by previous commands, which are recorded in
`kill-ring', and reinsert the chosen kill at point.

This command prompts for a previously-killed text in the minibuffer.
Use the minibuffer history and search commands, or the minibuffer
completion commands, to select a previously-killed text.  In
particular, typing \\<minibuffer-local-completion-map>\\[minibuffer-complete] at the prompt will pop up a buffer showing
all the previously-killed stretches of text from which you can
choose the one you want to reinsert.
Once you select the text you want to reinsert, type \\<minibuffer-local-map>\\[exit-minibuffer] to actually
insert it and exit the minibuffer.
You can also edit the selected text in the minibuffer before
inserting it.

With \\[universal-argument] as argument, this command puts point at
beginning of the inserted text and mark at the end, like `yank' does.

When called from Lisp, insert STRING like `insert-for-yank' does."
  (interactive (list (read-from-kill-ring "Yank from kill-ring: ")
                     current-prefix-arg))
  (setq yank-window-start (window-start))
  (push-mark)
  (insert-for-yank string)
  (when yank-from-kill-ring-rotate
    (let ((pos (seq-position kill-ring string)))
      (if pos
          (setq kill-ring-yank-pointer (nthcdr pos kill-ring))
        (kill-new string))))
  (if (consp arg)
      ;; Swap point and mark like in `yank' and `yank-pop'.
      (goto-char (prog1 (mark t)
                   (set-marker (mark-marker) (point) (current-buffer))))))


;; Some kill commands.

;; Internal subroutine of delete-char
(defun kill-forward-chars (arg)
  (if (listp arg) (setq arg (car arg)))
  (if (eq arg '-) (setq arg -1))
  (kill-region (point) (+ (point) arg)))

;; Internal subroutine of backward-delete-char
(defun kill-backward-chars (arg)
  (if (listp arg) (setq arg (car arg)))
  (if (eq arg '-) (setq arg -1))
  (kill-region (point) (- (point) arg)))

(defcustom backward-delete-char-untabify-method 'untabify
  "The method for untabifying when deleting backward.
Can be `untabify' -- turn a tab to many spaces, then delete one space;
       `hungry' -- delete all whitespace, both tabs and spaces;
       `all' -- delete all whitespace, including tabs, spaces and newlines;
       nil -- just delete one character."
  :type '(choice (const untabify) (const hungry) (const all) (const nil))
  :version "20.3"
  :group 'killing)

(defun backward-delete-char-untabify (arg &optional killp)
  "Delete characters backward, changing tabs into spaces.
The exact behavior depends on `backward-delete-char-untabify-method'.

Delete ARG chars, and kill (save in kill ring) if KILLP is non-nil.

If Transient Mark mode is enabled, the mark is active, and ARG is 1,
delete the text in the region and deactivate the mark instead.
To disable this, set option `delete-active-region' to nil.

Interactively, ARG is the prefix arg (default 1)
and KILLP is t if a prefix arg was specified."
  (interactive "*p\nP")
  (if (and (use-region-p)
           delete-active-region
           (= arg 1))
      ;; Delete the text of the region and deactivate the mark, in the
      ;; same way that `delete-backward-char' does.
      (with-no-warnings (delete-backward-char 1 killp))
    (when (eq backward-delete-char-untabify-method 'untabify)
      (let ((count arg))
        (save-excursion
	  (while (and (> count 0) (not (bobp)))
	    (if (= (preceding-char) ?\t)
	        (let ((col (current-column)))
		  (forward-char -1)
		  (setq col (- col (current-column)))
		  (insert-char ?\s col)
		  (delete-char 1)))
	    (forward-char -1)
	    (setq count (1- count))))))
    (let* ((skip (cond ((eq backward-delete-char-untabify-method 'hungry) " \t")
                       ((eq backward-delete-char-untabify-method 'all)
                        " \t\n\r")))
           (n (if skip
                  (let* ((oldpt (point))
                         (wh (- oldpt (save-excursion
                                        (skip-chars-backward skip)
                                        (constrain-to-field nil oldpt)))))
                    (+ arg (if (zerop wh) 0 (1- wh))))
                arg)))
      ;; Avoid warning about delete-backward-char
      (with-no-warnings (delete-backward-char n killp)))))

(defun char-uppercase-p (char)
  "Return non-nil if CHAR is an upper-case character.
If the Unicode tables are not yet available, e.g. during bootstrap,
then gives correct answers only for ASCII characters."
  (cond ((unicode-property-table-internal 'lowercase)
         (characterp (get-char-code-property char 'lowercase)))
        ((<= ?A char ?Z))))

(defun zap-to-char (arg char &optional interactive)
  "Kill up to and including ARGth occurrence of CHAR.
When run interactively, the argument INTERACTIVE is non-nil.
Case is ignored if `case-fold-search' is non-nil in the current buffer.
Goes backward if ARG is negative; error if CHAR not found.
See also `zap-up-to-char'.
If called interactively, do a case sensitive search if CHAR
is an upper-case character."
  (interactive (list (prefix-numeric-value current-prefix-arg)
		     (read-char-from-minibuffer "Zap to char: "
						nil 'read-char-history)
               t))
  ;; Avoid "obsolete" warnings for translation-table-for-input.
  (with-no-warnings
    (if (char-table-p translation-table-for-input)
	(setq char (or (aref translation-table-for-input char) char))))
  (let ((case-fold-search (if (and interactive (char-uppercase-p char))
                              nil
                            case-fold-search)))
    (kill-region (point) (search-forward (char-to-string char) nil nil arg))))

;; kill-line and its subroutines.

(defcustom kill-whole-line nil
  "If non-nil, `kill-line' with no arg at start of line kills the whole line.
This variable also affects `kill-visual-line' in the same way as
it does `kill-line'."
  :type 'boolean
  :group 'killing)

(defun kill-line (&optional arg)
  "Kill the rest of the current line; if no nonblanks there, kill thru newline.
With prefix argument ARG, kill that many lines from point.
Negative arguments kill lines backward.
With zero argument, kills the text before point on the current line.

When calling from a program, nil means \"no arg\",
a number counts as a prefix arg.

To kill a whole line, when point is not at the beginning, type \
\\[move-beginning-of-line] \\[kill-line] \\[kill-line].

If `show-trailing-whitespace' is non-nil, this command will just
kill the rest of the current line, even if there are no nonblanks
there.

If option `kill-whole-line' is non-nil, then this command kills the whole line
including its terminating newline, when used at the beginning of a line
with no argument.  As a consequence, you can always kill a whole line
by typing \\[move-beginning-of-line] \\[kill-line].

If you want to append the killed line to the last killed text,
use \\[append-next-kill] before \\[kill-line].

If the buffer is read-only, Emacs will beep and refrain from deleting
the line, but put the line in the kill ring anyway.  This means that
you can use this command to copy text from a read-only buffer.
\(If the variable `kill-read-only-ok' is non-nil, then this won't
even beep.)"
  (interactive "P")
  (kill-region (point)
	       ;; It is better to move point to the other end of the kill
	       ;; before killing.  That way, in a read-only buffer, point
	       ;; moves across the text that is copied to the kill ring.
	       ;; The choice has no effect on undo now that undo records
	       ;; the value of point from before the command was run.
	       (progn
		 (if arg
		     (forward-visible-line (prefix-numeric-value arg))
		   (if (eobp)
		       (signal 'end-of-buffer nil))
		   (let ((end
			  (save-excursion
			    (end-of-visible-line) (point))))
		     (if (or (save-excursion
			       ;; If trailing whitespace is visible,
			       ;; don't treat it as nothing.
			       (unless show-trailing-whitespace
				 (skip-chars-forward " \t" end))
			       (= (point) end))
			     (and kill-whole-line (bolp)))
			 (forward-visible-line 1)
		       (goto-char end))))
		 (point))))

(defun kill-whole-line (&optional arg)
  "Kill current line.
With prefix ARG, kill that many lines starting from the current line.
If ARG is negative, kill backward.  Also kill the preceding newline.
\(This is meant to make \\[repeat] work well with negative arguments.)
If ARG is zero, kill current line but exclude the trailing newline."
  (interactive "p")
  (or arg (setq arg 1))
  (if (and (> arg 0) (eobp) (save-excursion (forward-visible-line 0) (eobp)))
      (signal 'end-of-buffer nil))
  (if (and (< arg 0) (bobp) (save-excursion (end-of-visible-line) (bobp)))
      (signal 'beginning-of-buffer nil))
  (unless (eq last-command 'kill-region)
    (kill-new "")
    (setq last-command 'kill-region))
  ;; - We need to kill in two steps, because the previous command
  ;;   could have been a kill command, in which case the text before
  ;;   point needs to be prepended to the current kill ring entry and
  ;;   the text after point appended.
  ;; - We need to be careful to avoid copying text twice to the kill
  ;;   ring in read-only buffers.
  ;; - We need to determine the boundaries of visible lines before we
  ;;   do the first kill.  Otherwise `after-change-functions' may
  ;;   change visibility (bug#65734).
  (let (;; The beginning of both regions to kill
        (regions-begin (point-marker))
        ;; The end of the first region to kill.  Moreover, after
        ;; evaluation of the value form, (point) will be the end of
        ;; the second region to kill.
        (region1-end (cond ((zerop arg)
                            (prog1 (save-excursion
                                     (forward-visible-line 0)
                                     (point-marker))
                              (end-of-visible-line)))
	                   ((< arg 0)
	                    (prog1 (save-excursion
                                     (end-of-visible-line)
                                     (point-marker))
                              (forward-visible-line (1+ arg))
	                      (unless (bobp) (backward-char))))
	                   (t
	                    (prog1 (save-excursion
                                     (forward-visible-line 0)
                                     (point-marker))
	                      (forward-visible-line arg))))))
    ;; - Pass the marker positions and not the markers themselves.
    ;;   kill-region determines whether to prepend or append to a
    ;;   previous kill by checking the direction of the region.  But
    ;;   it deletes the content and hence moves the markers before
    ;;   that.  That effectively makes every region delimited by
    ;;   markers an (empty) forward region.
    ;; - Make the first kill-region emit a non-local exit only if the
    ;;   second kill-region below would not operate on a non-empty
    ;;   region.
    (let ((kill-read-only-ok (or kill-read-only-ok
                                 (/= regions-begin (point)))))
      (kill-region (marker-position regions-begin)
                   (marker-position region1-end)))
    (kill-region (marker-position regions-begin)
                 (point))
    (set-marker regions-begin nil)
    (set-marker region1-end nil)))

(defun forward-visible-line (arg)
  "Move forward by ARG lines, ignoring currently invisible newlines only.
If ARG is negative, move backward -ARG lines.
If ARG is zero, move to the beginning of the current line."
  (condition-case nil
      (if (> arg 0)
	  (progn
	    (while (> arg 0)
	      (or (zerop (forward-line 1))
		  (signal 'end-of-buffer nil))
	      ;; If the newline we just skipped is invisible,
	      ;; don't count it.
	      (if (invisible-p (1- (point)))
		  (setq arg (1+ arg)))
	      (setq arg (1- arg)))
	    ;; If invisible text follows, and it is a number of complete lines,
	    ;; skip it.
	    (let ((opoint (point)))
	      (while (and (not (eobp))
			  (invisible-p (point)))
		(goto-char
		 (if (get-text-property (point) 'invisible)
		     (or (next-single-property-change (point) 'invisible)
			 (point-max))
		   (next-overlay-change (point)))))
	      (unless (bolp)
		(goto-char opoint))))
	(let ((first t))
	  (while (or first (<= arg 0))
	    (if first
		(beginning-of-line)
	      (or (zerop (forward-line -1))
		  (signal 'beginning-of-buffer nil)))
	    ;; If the newline we just moved to is invisible,
	    ;; don't count it.
	    (unless (bobp)
	      (unless (invisible-p (1- (point)))
		(setq arg (1+ arg))))
	    (setq first nil))
	  ;; If invisible text follows, and it is a number of complete lines,
	  ;; skip it.
	  (let ((opoint (point)))
	    (while (and (not (bobp))
			(invisible-p (1- (point))))
	      (goto-char
	       (if (get-text-property (1- (point)) 'invisible)
		   (or (previous-single-property-change (point) 'invisible)
		       (point-min))
		 (previous-overlay-change (point)))))
	    (unless (bolp)
	      (goto-char opoint)))))
    ((beginning-of-buffer end-of-buffer)
     nil)))

(defun end-of-visible-line ()
  "Move to end of current visible line."
  (end-of-line)
  ;; If the following character is currently invisible,
  ;; skip all characters with that same `invisible' property value,
  ;; then find the next newline.
  (while (and (not (eobp))
	      (save-excursion
		(skip-chars-forward "^\n")
		(invisible-p (point))))
    (skip-chars-forward "^\n")
    (if (get-text-property (point) 'invisible)
	(goto-char (or (next-single-property-change (point) 'invisible)
		       (point-max)))
      (goto-char (next-overlay-change (point))))
    (end-of-line)))

(defun kill-current-buffer ()
  "Kill the current buffer.
When called in the minibuffer, get out of the minibuffer
using `abort-recursive-edit'.

This is like `kill-this-buffer', but it doesn't have to be invoked
via the menu bar, and pays no attention to the menu-bar's frame."
  (interactive)
  (let ((frame (selected-frame)))
    (if (and (frame-live-p frame)
             (not (window-minibuffer-p (frame-selected-window frame))))
        (kill-buffer (current-buffer))
      (abort-recursive-edit))))


(defun insert-buffer (buffer)
  "Insert after point the contents of BUFFER.
Puts mark after the inserted text.
BUFFER may be a buffer or a buffer name."
  (declare (interactive-only insert-buffer-substring))
  (interactive
   (list
    (progn
      (barf-if-buffer-read-only)
      (read-buffer "Insert buffer: "
		   (if (eq (selected-window) (next-window))
		       (other-buffer (current-buffer))
		     (window-buffer (next-window)))
		   t))))
  (push-mark
   (save-excursion
     (insert-buffer-substring (get-buffer buffer))
     (point)))
  nil)

(defun append-to-buffer (buffer start end)
  "Append to specified BUFFER the text of the region.
The text is inserted into that buffer before its point.
BUFFER can be a buffer or the name of a buffer; this
function will create BUFFER if it doesn't already exist.

When calling from a program, give three arguments:
BUFFER (or buffer name), START and END.
START and END specify the portion of the current buffer to be copied."
  (interactive
   (list (read-buffer "Append to buffer: " (other-buffer (current-buffer) t))
	 (region-beginning) (region-end)))
  (let* ((oldbuf (current-buffer))
         (append-to (get-buffer-create buffer))
         (windows (get-buffer-window-list append-to t t))
         point)
    (save-excursion
      (with-current-buffer append-to
        (setq point (point))
        (barf-if-buffer-read-only)
        (insert-buffer-substring oldbuf start end)
        (dolist (window windows)
          (when (= (window-point window) point)
            (set-window-point window (point))))))))

(defun prepend-to-buffer (buffer start end)
  "Prepend to specified BUFFER the text of the region.
The text is inserted into that buffer after its point.
BUFFER can be a buffer or the name of a buffer; this
function will create BUFFER if it doesn't already exist.

When calling from a program, give three arguments:
BUFFER (or buffer name), START and END.
START and END specify the portion of the current buffer to be copied."
  (interactive "BPrepend to buffer: \nr")
  (let ((oldbuf (current-buffer)))
    (with-current-buffer (get-buffer-create buffer)
      (barf-if-buffer-read-only)
      (save-excursion
	(insert-buffer-substring oldbuf start end)))))

(defun copy-to-buffer (buffer start end)
  "Copy to specified BUFFER the text of the region.
The text is inserted into that buffer, replacing existing text there.
BUFFER can be a buffer or the name of a buffer; this
function will create BUFFER if it doesn't already exist.

When calling from a program, give three arguments:
BUFFER (or buffer name), START and END.
START and END specify the portion of the current buffer to be copied."
  (interactive "BCopy to buffer: \nr")
  (let ((oldbuf (current-buffer)))
    (with-current-buffer (get-buffer-create buffer)
      (barf-if-buffer-read-only)
      (erase-buffer)
      (save-excursion
	(insert-buffer-substring oldbuf start end)))))

(define-error 'mark-inactive "The mark is not active now")

(defvar activate-mark-hook nil
  "Hook run when the mark becomes active.
It is also run when the region is reactivated, for instance after
using a command that switches back to a buffer that has an active
mark.")

(defvar deactivate-mark-hook nil
  "Hook run when the mark becomes inactive.")

(defun mark (&optional force)
  "Return this buffer's mark value as integer, or nil if never set.

In Transient Mark mode, this function signals an error if
the mark is not active.  However, if `mark-even-if-inactive' is non-nil,
or the argument FORCE is non-nil, it disregards whether the mark
is active, and returns an integer or nil in the usual way.

If you are using this in an editing command, you are most likely making
a mistake; see the documentation of `set-mark'."
  (declare (ftype (function (&optional t) (or integer null)))
           (side-effect-free t))
  (if (or force (not transient-mark-mode) mark-active mark-even-if-inactive)
      (marker-position (mark-marker))
    (signal 'mark-inactive nil)))

;; Behind display-selections-p.

(defun deactivate-mark (&optional force)
  "Deactivate the mark.
If Transient Mark mode is disabled, this function normally does
nothing; but if FORCE is non-nil, it deactivates the mark anyway.

Deactivating the mark sets `mark-active' to nil, updates the
primary selection according to `select-active-regions' (unless
`deactivate-mark' is `dont-save'), and runs
`deactivate-mark-hook'.

If Transient Mark mode was temporarily enabled, reset the value
of the variable `transient-mark-mode'; if this causes Transient
Mark mode to be disabled, don't change `mark-active' to nil or
run `deactivate-mark-hook'."
  (when (or (region-active-p) force)
    (when (and (if (eq select-active-regions 'only)
		   (eq (car-safe transient-mark-mode) 'only)
		 select-active-regions)
               (not (eq deactivate-mark 'dont-save))
	       (region-active-p)
	       (display-selections-p))
      ;; The var `saved-region-selection', if non-nil, is the text in
      ;; the region prior to the last command modifying the buffer.
      ;; Set the selection to that, or to the current region.
      (cond (saved-region-selection
	     (if (gui-backend-selection-owner-p 'PRIMARY)
		 (gui-set-selection 'PRIMARY saved-region-selection))
	     (setq saved-region-selection nil))
	    ;; If another program has acquired the selection, region
	    ;; deactivation should not clobber it (Bug#11772).
	    ((and (/= (region-beginning) (region-end))
		  (or (gui-backend-selection-owner-p 'PRIMARY)
		      (null (gui-backend-selection-exists-p 'PRIMARY))))
	     (gui-set-selection 'PRIMARY
                                (funcall region-extract-function nil)))))
    (when mark-active (force-mode-line-update)) ;Refresh toolbar (bug#16382).
    (cond
     ((eq (car-safe transient-mark-mode) 'only)
      (setq transient-mark-mode (cdr transient-mark-mode))
      (if (eq transient-mark-mode (default-value 'transient-mark-mode))
          (kill-local-variable 'transient-mark-mode)))
     ((eq transient-mark-mode 'lambda)
      (kill-local-variable 'transient-mark-mode)))
    (setq mark-active nil)
    (run-hooks 'deactivate-mark-hook)
    (redisplay--update-region-highlight (selected-window))))

(defun activate-mark (&optional no-tmm)
  "Activate the mark.
If NO-TMM is non-nil, leave `transient-mark-mode' alone."
  (when (mark t)
    (unless (region-active-p)
      (force-mode-line-update) ;Refresh toolbar (bug#16382).
      (setq mark-active t)
      (unless (or transient-mark-mode no-tmm)
        (setq-local transient-mark-mode 'lambda))
      (run-hooks 'activate-mark-hook))))

(defun set-mark (pos)
  "Set this buffer's mark to POS.  Don't use this function!
That is to say, don't use this function unless you want
the user to see that the mark has moved, and you want the previous
mark position to be lost.

Normally, when a new mark is set, the old one should go on the stack.
This is why most applications should use `push-mark', not `set-mark'.

Novice Emacs Lisp programmers often try to use the mark for the wrong
purposes.  The mark saves a location for the user's convenience.
Most editing commands should not alter the mark.
To remember a location for internal use in the Lisp program,
store it in a Lisp variable.  Example:

   (let ((beg (point))) (forward-line 1) (delete-region beg (point)))."
  (if pos
      (progn
        (set-marker (mark-marker) pos (current-buffer))
        (activate-mark 'no-tmm))
    ;; Normally we never clear mark-active except in Transient Mark mode.
    ;; But when we actually clear out the mark value too, we must
    ;; clear mark-active in any mode.
    (deactivate-mark t)
    ;; `deactivate-mark' sometimes leaves mark-active non-nil, but
    ;; it should never be nil if the mark is nil.
    (setq mark-active nil)
    (set-marker (mark-marker) nil)))

(defun save-mark-and-excursion--save ()
  (cons
   (let ((mark (mark-marker)))
     (and (marker-position mark) (copy-marker mark)))
   mark-active))

(defun save-mark-and-excursion--restore (saved-mark-info)
  (let ((saved-mark (car saved-mark-info))
        (omark (marker-position (mark-marker)))
        (nmark nil)
        (saved-mark-active (cdr saved-mark-info)))
    ;; Mark marker
    (if (null saved-mark)
        (set-marker (mark-marker) nil)
      (setf nmark (marker-position saved-mark))
      (set-marker (mark-marker) nmark)
      (set-marker saved-mark nil))
    ;; Mark active
    (let ((cur-mark-active mark-active))
      (setq mark-active saved-mark-active)
      ;; If mark is active now, and either was not active or was at a
      ;; different place, run the activate hook.
      (if saved-mark-active
          (when (or (not cur-mark-active)
                    (not (eq omark nmark)))
            (run-hooks 'activate-mark-hook))
        ;; If mark has ceased to be active, run deactivate hook.
        (when cur-mark-active
          (run-hooks 'deactivate-mark-hook))))))

(defmacro save-mark-and-excursion (&rest body)
  "Like `save-excursion', but also save and restore the mark state.
This macro does what `save-excursion' did before Emacs 25.1."
  (declare (indent 0) (debug t))
  (let ((saved-marker-sym (make-symbol "saved-marker")))
    `(let ((,saved-marker-sym (save-mark-and-excursion--save)))
       (unwind-protect
            (save-excursion ,@body)
         (save-mark-and-excursion--restore ,saved-marker-sym)))))

(defcustom use-empty-active-region nil
  "Whether \"region-aware\" commands should act on empty regions.
If nil, region-aware commands treat the empty region as inactive.
If non-nil, region-aware commands treat the region as active as
long as the mark is active, even if the region is empty.

Region-aware commands are those that act on the region if it is
active and Transient Mark mode is enabled, and on the text near
point otherwise."
  :type 'boolean
  :version "23.1"
  :group 'editing-basics)

(defun use-region-beginning ()
  "Return the start of the region if `use-region-p' returns non-nil.
This is a convenience function to use in `interactive' forms of
commands that need to act on the region when it is active."
  (and (use-region-p) (region-beginning)))

(defun use-region-end ()
  "Return the end of the region if `use-region-p' returns non-nil.
This is a convenience function to use in `interactive' forms of
commands that need to act on the region when it is active."
  (and (use-region-p) (region-end)))

(defun use-region-noncontiguous-p ()
  "Return non-nil for a non-contiguous region if `use-region-p'."
  (and (use-region-p) (region-noncontiguous-p)))

(defun use-region-p ()
  "Return t if the region is active and it is appropriate to act on it.
This is used by commands that act specially on the region under
Transient Mark mode.

The return value is t if Transient Mark mode is enabled and the
mark is active; furthermore, if `use-empty-active-region' is nil,
the region must not be empty.  Otherwise, the return value is nil.

If `use-empty-active-region' is non-nil, there is one further
caveat: If the user has used `mouse-1' to set point, but used the
mouse to move point to a different character yet, this function
returns nil.

For some commands, it may be appropriate to ignore the value of
`use-empty-active-region'; in that case, use `region-active-p'.

Also see the convenience functions `use-region-beginning' and
`use-region-end', which may be handy when writing `interactive'
specs."
  (and (region-active-p)
       (or (> (region-end) (region-beginning))
           (and use-empty-active-region
                (not (eq (car-safe last-input-event) 'down-mouse-1))
                (not (mouse-movement-p last-input-event))))))

(defun region-active-p ()
  "Return t if Transient Mark mode is enabled and the mark is active.

Some commands act specially on the region when Transient Mark
mode is enabled.  Usually, such commands should use
`use-region-p' instead of this function, because `use-region-p'
also checks the value of `use-empty-active-region'."
  (and transient-mark-mode mark-active
       ;; FIXME: Somehow we sometimes end up with mark-active non-nil but
       ;; without the mark being set (e.g. bug#17324).  We really should fix
       ;; that problem, but in the mean time, let's make sure we don't say the
       ;; region is active when there's no mark.
       (progn (cl-assert (mark)) t)))

(defun region-bounds ()
  "Return the boundaries of the region.
Value is a list of one or more cons cells of the form (START . END).
It will have more than one cons cell when the region is non-contiguous,
see `region-noncontiguous-p' and `extract-rectangle-bounds'."
  (funcall region-extract-function 'bounds))

(defun region-noncontiguous-p ()
  "Return non-nil if the region contains several pieces.
An example is a rectangular region handled as a list of
separate contiguous regions for each line."
  (let ((bounds (region-bounds))) (and (cdr bounds) bounds)))

(defun redisplay--unhighlight-overlay-function (rol)
  "If ROL is an overlay, call `delete-overlay'."
  (when (overlayp rol) (delete-overlay rol)))

(defvar redisplay-unhighlight-region-function
  #'redisplay--unhighlight-overlay-function
  "Function to remove the region-highlight overlay.")

(defun redisplay--highlight-overlay-function (start end window rol &optional face)
  "Update the overlay ROL in WINDOW with FACE in range START-END."
  (unless face (setq face 'region))
  (if (not (overlayp rol))
      (let ((nrol (make-overlay start end)))
        (funcall redisplay-unhighlight-region-function rol)
        (overlay-put nrol 'window window)
        (overlay-put nrol 'face face)
        ;; Normal priority so that a large region doesn't hide all the
        ;; overlays within it, but high secondary priority so that if it
        ;; ends/starts in the middle of a small overlay, that small overlay
        ;; won't hide the region's boundaries.
        (overlay-put nrol 'priority '(nil . 100))
        nrol)
    (unless (eq (overlay-get rol 'face) face)
      (overlay-put rol 'face face))
    (unless (and (eq (overlay-buffer rol) (current-buffer))
                 (eq (overlay-start rol) start)
                 (eq (overlay-end rol) end))
      (move-overlay rol start end (current-buffer)))
    rol))

(defvar redisplay-highlight-region-function
  #'redisplay--highlight-overlay-function
  "Function to move the region-highlight overlay.
This function is called with four parameters, START, END, WINDOW
and OVERLAY.  If OVERLAY is nil, a new overlay is created.  In
any case, the overlay is adjusted to reflect the other three
parameters.

The overlay is returned by the function.")

(defun redisplay--update-region-highlight (window)
  (let ((rol (window-parameter window 'internal-region-overlay)))
    (if (not (and (region-active-p)
                  (or highlight-nonselected-windows
                      (eq window (selected-window))
                      (and (window-minibuffer-p)
                           (eq window (minibuffer-selected-window))))))
        (funcall redisplay-unhighlight-region-function rol)
      (let* ((pt (window-point window))
             (mark (mark))
             (start (min pt mark))
             (end   (max pt mark))
             (new
              (funcall redisplay-highlight-region-function
                       start end window rol)))
        (unless (equal new rol)
          (set-window-parameter window 'internal-region-overlay new))))))

(defcustom cursor-face-highlight-nonselected-window nil
  "Non-nil means highlight text with `cursor-face' even in nonselected windows.
This variable is similar to `highlight-nonselected-windows'."
  :local t
  :type 'boolean
  :version "29.1")

(defun redisplay--update-cursor-face-highlight (window)
  "Highlights the overlay used to highlight text with cursor-face."
  (let ((rol (window-parameter window 'internal-cursor-face-overlay)))
    (if-let* (((or cursor-face-highlight-nonselected-window
                   (eq window (selected-window))
                   (and (window-minibuffer-p)
                        (eq window (minibuffer-selected-window)))))
              (pt (window-point window))
              (cursor-face (get-text-property pt 'cursor-face)))
        (let* ((start (previous-single-property-change
                       (min (1+ pt) (point-max)) 'cursor-face nil (point-min)))
               (end (next-single-property-change
                     pt 'cursor-face nil (point-max)))
               (new (redisplay--highlight-overlay-function
                     start end window rol cursor-face)))
          (unless (equal new rol)
            (set-window-parameter window 'internal-cursor-face-overlay new)))
      (redisplay--unhighlight-overlay-function rol))))

(defvar pre-redisplay-functions (list #'redisplay--update-region-highlight)
  "Hook run just before redisplay.
It is called in each window that is to be redisplayed.  It takes one argument,
which is the window that will be redisplayed.  When run, the `current-buffer'
is set to the buffer displayed in that window.")

(define-minor-mode cursor-face-highlight-mode
  "When enabled, highlight text that has `cursor-face' property near point."
  :global nil
  (if cursor-face-highlight-mode
      (add-hook 'pre-redisplay-functions
                #'redisplay--update-cursor-face-highlight nil t)
    (remove-hook 'pre-redisplay-functions
                 #'redisplay--update-cursor-face-highlight t)))

(defun redisplay--pre-redisplay-functions (windows)
  (with-demoted-errors "redisplay--pre-redisplay-functions: %S"
    (if (null windows)
        (with-current-buffer (window-buffer (selected-window))
          (run-hook-with-args 'pre-redisplay-functions (selected-window)))
      (dolist (win (if (listp windows) windows (window-list-1 nil nil t)))
        (with-current-buffer (window-buffer win)
          (run-hook-with-args 'pre-redisplay-functions win))))))

(when (eq pre-redisplay-function #'ignore)
  ;; Override the default set in the C code.
  ;; This is not done using `add-function' so as to loosen the bootstrap
  ;; dependencies.
  (setq pre-redisplay-function #'redisplay--pre-redisplay-functions))

(defvar-local mark-ring nil
  "The list of former marks of the current buffer, most recent first.")
(put 'mark-ring 'permanent-local t)

(defcustom mark-ring-max 16
  "Maximum size of mark ring.  Start discarding off end if gets this big."
  :type 'natnum
  :group 'editing-basics)

(defvar global-mark-ring nil
  "The list of saved global marks, most recent first.")

(defcustom global-mark-ring-max 16
  "Maximum size of global mark ring.  \
Start discarding off end if gets this big."
  :type 'natnum
  :group 'editing-basics)

(defun pop-to-mark-command ()
  "Jump to mark, and pop a new position for mark off the ring.
\(Does not affect global mark ring)."
  (interactive)
  (if (null (mark t))
      (user-error "No mark set in this buffer")
    (if (= (point) (mark t))
	(message "Mark popped"))
    (goto-char (mark t))
    (pop-mark)))

(defun push-mark-command (arg &optional nomsg)
  "Set mark at where point is.
If no prefix ARG and mark is already set there, just activate it.
Display `Mark set' unless the optional second arg NOMSG is non-nil."
  (interactive "P")
  (let ((mark (mark t)))
    (if (or arg (null mark) (/= mark (point)))
	(push-mark nil nomsg t)
      (activate-mark 'no-tmm)
      (unless nomsg
	(message "Mark activated")))))

(defcustom set-mark-command-repeat-pop nil
  "Non-nil means repeating \\[set-mark-command] after popping mark pops it again.
That means that \\[universal-argument] \\[set-mark-command] \\[set-mark-command]
will pop the mark twice, and
\\[universal-argument] \\[set-mark-command] \\[set-mark-command] \\[set-mark-command]
will pop the mark three times.

A value of nil means \\[set-mark-command]'s behavior does not change
after \\[universal-argument] \\[set-mark-command]."
  :type 'boolean
  :group 'editing-basics)

(defun set-mark-command (arg)
  "Set the mark where point is, and activate it; or jump to the mark.
Setting the mark also alters the region, which is the text
between point and mark; this is the closest equivalent in
Emacs to what some editors call the \"selection\".

With no prefix argument, set the mark at point, and push the
old mark position on local mark ring.  Also push the new mark on
global mark ring, if the previous mark was set in another buffer.

When Transient Mark Mode is off, immediately repeating this
command activates `transient-mark-mode' temporarily.

With prefix argument (e.g., \\[universal-argument] \\[set-mark-command]), \
jump to the mark, and set the mark from
position popped off the local mark ring (this does not affect the global
mark ring).  Use \\[pop-global-mark] to jump to a mark popped off the global
mark ring (see `pop-global-mark').

If `set-mark-command-repeat-pop' is non-nil, repeating
the \\[set-mark-command] command with no prefix argument pops the next position
off the local (or global) mark ring and jumps there.

With \\[universal-argument] \\[universal-argument] as prefix
argument, unconditionally set mark where point is, even if
`set-mark-command-repeat-pop' is non-nil.

Novice Emacs Lisp programmers often try to use the mark for the wrong
purposes.  See the documentation of `set-mark' for more information."
  (interactive "P")
  (cond ((eq transient-mark-mode 'lambda)
	 (kill-local-variable 'transient-mark-mode))
	((eq (car-safe transient-mark-mode) 'only)
	 (deactivate-mark)))
  (cond
   ((and (consp arg) (> (prefix-numeric-value arg) 4))
    (push-mark-command nil))
   ((not (eq this-command 'set-mark-command))
    (if arg
	(pop-to-mark-command)
      (push-mark-command t)))
   ((and set-mark-command-repeat-pop
	 (eq last-command 'pop-global-mark)
	 (not arg))
    (setq this-command 'pop-global-mark)
    (pop-global-mark))
   ((or (and set-mark-command-repeat-pop
             (eq last-command 'pop-to-mark-command))
        arg)
    (setq this-command 'pop-to-mark-command)
    (pop-to-mark-command))
   ((eq last-command 'set-mark-command)
    (if (region-active-p)
        (progn
          (deactivate-mark)
          (message "Mark deactivated"))
      (activate-mark)
      (message "Mark activated")))
   (t
    (push-mark-command nil))))

(defun push-mark (&optional location nomsg activate)
  "Set mark at LOCATION (point, by default) and push old mark on mark ring.
If the last global mark pushed was not in the current buffer,
also push LOCATION on the global mark ring.
Display `Mark set' unless the optional second arg NOMSG is non-nil.

Novice Emacs Lisp programmers often try to use the mark for the wrong
purposes.  See the documentation of `set-mark' for more information.

In Transient Mark mode, activate mark if optional third arg ACTIVATE non-nil."
  (when (mark t)
    (let ((old (nth mark-ring-max mark-ring))
          (history-delete-duplicates nil))
      (add-to-history 'mark-ring (copy-marker (mark-marker)) mark-ring-max t)
      (when old
        (set-marker old nil))))
  (set-marker (mark-marker) (or location (point)) (current-buffer))
  ;; Don't push the mark on the global mark ring if the last global
  ;; mark pushed was in this same buffer.
  (unless (and global-mark-ring
               (eq (marker-buffer (car global-mark-ring)) (current-buffer)))
    (let ((old (nth global-mark-ring-max global-mark-ring))
          (history-delete-duplicates nil))
      (add-to-history
       'global-mark-ring (copy-marker (mark-marker)) global-mark-ring-max t)
      (when old
        (set-marker old nil))))
  (or nomsg executing-kbd-macro (> (minibuffer-depth) 0)
      (message "Mark set"))
  (if (or activate (not transient-mark-mode))
      (set-mark (mark t)))
  nil)

(defun pop-mark ()
  "Pop off mark ring into the buffer's actual mark.
Does not set point.  Does nothing if mark ring is empty."
  (when mark-ring
    (setq mark-ring (nconc mark-ring (list (copy-marker (mark-marker)))))
    (set-marker (mark-marker) (car mark-ring))
    (set-marker (car mark-ring) nil)
    (pop mark-ring))
  (deactivate-mark))

(defcustom exchange-point-and-mark-highlight-region t
  "Activate region when exchanging point and mark.

When set to nil, this modifies `exchange-point-and-mark' so that it
doesn't activate the mark if it is not already active, except when there
is a prefix argument.  Setting this variable to nil effectively swaps
the meanings of the presence and absence of a prefix argument to
`exchange-point-and-mark'.

This variable has no effect when Transient Mark mode is off."
  :type 'boolean
  :group 'editing-basics
  :version "31.1")

(defun exchange-point-and-mark (&optional arg)
  "Put the mark where point is now, and point where the mark is now.
This command works even when the mark is not active, and it reactivates
the mark unless `exchange-point-and-mark-highlight-region' is nil.

If Transient Mark mode is on, a prefix ARG deactivates the mark if it is
active, and otherwise avoids reactivating it.  However, if
`exchange-point-and-mark-highlight-region' is nil, then using a prefix
argument does reactivate the mark; effectively, when Transient Mark mode
is on, setting `exchange-point-and-mark-highlight-region' to nil swaps
the meanings of the presence and absence of a prefix argument.

If Transient Mark mode is off, a prefix ARG enables Transient Mark mode
temporarily."
  (interactive "P")
  (let ((omark (mark t))
        (region-was-active (region-active-p))
	(temp-highlight (eq (car-safe transient-mark-mode) 'only)))
    (if (null omark)
        (user-error "No mark set in this buffer"))
    (set-mark (point))
    (goto-char omark)
    (cond (temp-highlight)
          ((xor arg (if exchange-point-and-mark-highlight-region
                        (not (region-active-p))
                      (not region-was-active)))
	   (deactivate-mark))
	  (t (activate-mark)))
    nil))

(defcustom shift-select-mode t
  "When non-nil, shifted motion keys activate the mark momentarily.

While the mark is activated in this way, any shift-translated point
motion key extends the region, and if Transient Mark mode was off, it
is temporarily turned on.  Furthermore, the mark will be deactivated
by any subsequent point motion key that was not shift-translated, or
by any action that normally deactivates the mark in Transient Mark mode.

When the value is `permanent', the mark will be deactivated by any
action which normally does that, but not by motion keys that were
not shift-translated.

See `this-command-keys-shift-translated' for the meaning of
shift-translation."
  :type '(choice (const :tag "Off" nil)
                 (const :tag "Permanent" permanent)
                 (other :tag "On" t))
  :version "28.1"
  :group 'editing-basics)

(defun handle-shift-selection ()
  "Activate/deactivate mark depending on invocation thru shift translation.
This function is called by `call-interactively' when a command
with a `^' character in its `interactive' spec is invoked, before
running the command itself.

If `shift-select-mode' is enabled and the command was invoked
through shift translation, set the mark and activate the region
temporarily, unless it was already set in this way.  See
`this-command-keys-shift-translated' for the meaning of shift
translation.

Otherwise, if the region has been activated temporarily,
deactivate it, and restore the variable `transient-mark-mode' to
its earlier value."
  (cond ((and (eq shift-select-mode 'permanent)
              this-command-keys-shift-translated)
         (unless mark-active
           (push-mark nil nil t)))
        ((and shift-select-mode
              this-command-keys-shift-translated)
         (unless (and mark-active
		      (eq (car-safe transient-mark-mode) 'only))
	   (setq-local transient-mark-mode
                       (cons 'only
                             (unless (eq transient-mark-mode 'lambda)
                               transient-mark-mode)))
           (push-mark nil nil t)))
        ((eq (car-safe transient-mark-mode) 'only)
         (setq transient-mark-mode (cdr transient-mark-mode))
         (if (eq transient-mark-mode (default-value 'transient-mark-mode))
             (kill-local-variable 'transient-mark-mode))
         (deactivate-mark))))

(define-minor-mode transient-mark-mode
  "Toggle Transient Mark mode.

Transient Mark mode is a global minor mode.  When enabled, the
region is highlighted with the `region' face whenever the mark
is active.  The mark is \"deactivated\" after certain non-motion
commands, including those that change the text in the buffer, and
during shift or mouse selection by any unshifted cursor motion
command (see Info node `Shift Selection' for more details).

You can also deactivate the mark by typing \\[keyboard-quit] or
\\[keyboard-escape-quit].

Many commands change their behavior when Transient Mark mode is
in effect and the mark is active, by acting on the region instead
of their usual default part of the buffer's text.  Examples of
such commands include \\[comment-dwim], \\[flush-lines], \\[keep-lines],
\\[query-replace], \\[query-replace-regexp], \\[ispell], and \\[undo].
To see the documentation of commands that are sensitive to the
Transient Mark mode, invoke \\[apropos-documentation] and type \"transient\"
or \"mark.*active\" at the prompt."
  :global t
  ;; It's defined in C/cus-start, this stops the d-m-m macro defining it again.
  :variable (default-value 'transient-mark-mode))

(define-minor-mode indent-tabs-mode
  "Toggle whether indentation can insert TAB characters."
  :group 'indent)

(defvar widen-automatically t
  "Non-nil means it is ok for commands to call `widen' when they want to.
Some commands will do this in order to go to positions outside
the current accessible part of the buffer.

If `widen-automatically' is nil, these commands will do something else
as a fallback, and won't change the buffer bounds.")

(defvar non-essential nil
  "Whether the currently executing code is performing an essential task.
This variable should be non-nil only when running code that should not
disturb the user.  E.g., it can be used to prevent Tramp from prompting
the user for a password when we are simply scanning a set of files in the
background or displaying possible completions before the user even asked
for it.")

(defun pop-global-mark ()
  "Pop off global mark ring and jump to the top location."
  (interactive)
  ;; Pop entries that refer to non-existent buffers.
  (while (and global-mark-ring (not (marker-buffer (car global-mark-ring))))
    (setq global-mark-ring (cdr global-mark-ring)))
  (or global-mark-ring
      (error "No global mark set"))
  (let* ((marker (car global-mark-ring))
	 (buffer (marker-buffer marker))
	 (position (marker-position marker)))
    (setq global-mark-ring (nconc (cdr global-mark-ring)
				  (list (car global-mark-ring))))
    (set-buffer buffer)
    (or (and (>= position (point-min))
	     (<= position (point-max)))
	(if widen-automatically
	    (widen)
	  (error "Global mark position is outside accessible part of buffer %s"
                 (buffer-name buffer))))
    (goto-char position)
    (switch-to-buffer buffer)))

(defcustom next-line-add-newlines nil
  "If non-nil, `next-line' inserts newline to avoid `end of buffer' error."
  :type 'boolean
  :version "21.1"
  :group 'editing-basics)

(defun next-line (&optional arg try-vscroll)
  "Move cursor vertically down ARG lines.
Interactively, vscroll tall lines if `auto-window-vscroll' is enabled.
Non-interactively, use TRY-VSCROLL to control whether to vscroll tall
lines: if either `auto-window-vscroll' or TRY-VSCROLL is nil, this
function will not vscroll.

ARG defaults to 1.

If there is no character in the target line exactly under the current column,
the cursor is positioned after the character in that line that spans this
column, or at the end of the line if it is not long enough.
If there is no line in the buffer after this one, behavior depends on the
value of `next-line-add-newlines'.  If non-nil, it inserts a newline character
to create a line, and moves the cursor to that line.  Otherwise it moves the
cursor to the end of the buffer.

If the variable `line-move-visual' is non-nil, this command moves
by display lines.  Otherwise, it moves by buffer lines, without
taking variable-width characters or continued lines into account.
See \\[next-logical-line] for a command that always moves by buffer lines.

The command \\[set-goal-column] can be used to create
a semipermanent goal column for this command.
Then instead of trying to move exactly vertically (or as close as possible),
this command moves to the specified goal column (or as close as possible).
The goal column is stored in the variable `goal-column', which is nil
when there is no goal column.  Note that setting `goal-column'
overrides `line-move-visual' and causes this command to move by buffer
lines rather than by display lines."
  (declare (interactive-only forward-line))
  (interactive "^p\np")
  (or arg (setq arg 1))
  (if (and next-line-add-newlines (= arg 1))
      (if (save-excursion (end-of-line) (eobp))
	  ;; When adding a newline, don't expand an abbrev.
	  (let ((abbrev-mode nil))
	    (end-of-line)
	    (insert (if use-hard-newlines hard-newline "\n")))
	(line-move arg nil nil try-vscroll))
    (if (called-interactively-p 'interactive)
	(condition-case err
	    (line-move arg nil nil try-vscroll)
	  ((beginning-of-buffer end-of-buffer)
	   (signal (car err) (cdr err))))
      (line-move arg nil nil try-vscroll)))
  nil)

(defun previous-line (&optional arg try-vscroll)
  "Move cursor vertically up ARG lines.
Interactively, vscroll tall lines if `auto-window-vscroll' is enabled.
Non-interactively, use TRY-VSCROLL to control whether to vscroll tall
lines: if either `auto-window-vscroll' or TRY-VSCROLL is nil, this
function will not vscroll.

ARG defaults to 1.

If there is no character in the target line exactly over the current column,
the cursor is positioned after the character in that line that spans this
column, or at the end of the line if it is not long enough.

If the variable `line-move-visual' is non-nil, this command moves
by display lines.  Otherwise, it moves by buffer lines, without
taking variable-width characters or continued lines into account.
See \\[previous-logical-line] for a command that always moves by buffer lines.

The command \\[set-goal-column] can be used to create
a semipermanent goal column for this command.
Then instead of trying to move exactly vertically (or as close as possible),
this command moves to the specified goal column (or as close as possible).
The goal column is stored in the variable `goal-column', which is nil
when there is no goal column.  Note that setting `goal-column'
overrides `line-move-visual' and causes this command to move by buffer
lines rather than by display lines."
  (declare (interactive-only
            "use `forward-line' with negative argument instead."))
  (interactive "^p\np")
  (or arg (setq arg 1))
  (if (called-interactively-p 'interactive)
      (condition-case err
	  (line-move (- arg) nil nil try-vscroll)
	((beginning-of-buffer end-of-buffer)
	 (signal (car err) (cdr err))))
    (line-move (- arg) nil nil try-vscroll))
  nil)

(defcustom track-eol nil
  "Non-nil means vertical motion starting at end of line keeps to ends of lines.
This means moving to the end of each line moved onto.
The beginning of a blank line does not count as the end of a line.
This has no effect when the variable `line-move-visual' is non-nil."
  :type 'boolean
  :group 'editing-basics)

(defcustom goal-column nil
  "Semipermanent goal column for vertical motion, as set by \\[set-goal-column], or nil.
A non-nil setting overrides the variable `line-move-visual', which see."
  :type '(choice integer
		 (const :tag "None" nil))
  :local t
  :group 'editing-basics)

(defvar temporary-goal-column 0
  "Current goal column for vertical motion.
It is the column where point was at the start of the current run
of vertical motion commands.

When moving by visual lines via the function `line-move-visual', it is a cons
cell (COL . HSCROLL), where COL is the x-position, in pixels,
divided by the default column width, and HSCROLL is the number of
columns by which window is scrolled from left margin.

When the `track-eol' feature is doing its job, the value is
`most-positive-fixnum'.")

(defcustom line-move-ignore-invisible t
  "Non-nil means commands that move by lines ignore invisible newlines.
When this option is non-nil, \\[next-line], \\[previous-line], \\[move-end-of-line], and \\[move-beginning-of-line] behave
as if newlines that are invisible didn't exist, and count
only visible newlines.  Thus, moving across 2 newlines
one of which is invisible will be counted as a one-line move.
Also, a non-nil value causes invisible text to be ignored when
counting columns for the purposes of keeping point in the same
column by \\[next-line] and \\[previous-line].

Outline mode sets this."
  :type 'boolean
  :group 'editing-basics)

(defcustom line-move-visual t
  "When non-nil, `line-move' moves point by visual lines.
This movement is based on where the cursor is displayed on the
screen, instead of relying on buffer contents alone.  It takes
into account variable-width characters and line continuation.
If nil, `line-move' moves point by logical lines.
A non-nil setting of `goal-column' overrides the value of this variable
and forces movement by logical lines.
A window that is horizontally scrolled also forces movement by logical
lines."
  :type 'boolean
  :group 'editing-basics
  :version "23.1")

;; Used only if display-graphic-p.
(declare-function font-info "font.c" (name &optional frame))

(defun default-font-height ()
  "Return the height in pixels of the current buffer's default face font.

If the default font is remapped (see `face-remapping-alist'), the
function returns the height of the remapped face.
This function uses the definition of the default face for the currently
selected frame."
  (let ((default-font (face-font 'default)))
    (cond
     ((and (display-multi-font-p)
	   ;; Avoid calling font-info if the frame's default font was
	   ;; not changed since the frame was created.  That's because
	   ;; font-info is expensive for some fonts, see bug #14838.
	   (not (string= (frame-parameter nil 'font) default-font)))
      (aref (font-info default-font) 3))
     (t (frame-char-height)))))

(defun default-font-width ()
  "Return the width in pixels of the current buffer's default face font.

If the default font is remapped (see `face-remapping-alist'), the
function returns the width of the remapped face.
This function uses the definition of the default face for the currently
selected frame."
  (let ((default-font (face-font 'default)))
    (cond
     ((and (display-multi-font-p)
	   ;; Avoid calling font-info if the frame's default font was
	   ;; not changed since the frame was created.  That's because
	   ;; font-info is expensive for some fonts, see bug #14838.
	   (not (string= (frame-parameter nil 'font) default-font)))
      (let* ((info (font-info (face-font 'default)))
	     (width (aref info 11)))
	(if (> width 0)
	    width
	  (aref info 10))))
     (t (frame-char-width)))))

(defun default-line-height ()
  "Return the pixel height of current buffer's default-face text line.

The value includes `line-spacing', if any, defined for the buffer
or the frame.
This function uses the definition of the default face for the currently
selected frame."
  (let ((dfh (default-font-height))
	(lsp (if (display-graphic-p)
		 (or line-spacing
		     (default-value 'line-spacing)
		     (frame-parameter nil 'line-spacing)
		     0)
	       0)))
    (if (floatp lsp)
	(setq lsp (truncate (* (frame-char-height) lsp))))
    (+ dfh lsp)))

(defun window-screen-lines ()
  "Return the number of screen lines in the text area of the selected window.

This is different from `window-text-height' in that this function counts
lines in units of the height of the font used by the default face displayed
in the window, not in units of the frame's default font, and also accounts
for `line-spacing', if any, defined for the window's buffer or frame.

The value is a floating-point number."
  (let ((edges (window-inside-pixel-edges))
	(dlh (default-line-height)))
    (/ (float (- (nth 3 edges) (nth 1 edges))) dlh)))

;; Returns non-nil if partial move was done.
(defun line-move-partial (arg noerror &optional _to-end)
  (if (< arg 0)
      ;; Move backward (up).
      ;; If already vscrolled, reduce vscroll
      (let ((vs (window-vscroll nil t))
	    (dlh (default-line-height)))
	(when (> vs dlh)
	  (set-window-vscroll nil (- vs dlh) t)))

    ;; Move forward (down).
    (let* ((lh (window-line-height -1))
	   (rowh (car lh))
	   (vpos (nth 1 lh))
	   (ypos (nth 2 lh))
	   (rbot (nth 3 lh))
	   (this-lh (window-line-height))
	   (this-height (car this-lh))
	   (this-ypos (nth 2 this-lh))
	   (dlh (default-line-height))
	   (wslines (window-screen-lines))
	   (edges (window-inside-pixel-edges))
	   (winh (- (nth 3 edges) (nth 1 edges) 1))
	   py vs last-line)
      (if (> (mod wslines 1.0) 0.0)
	  (setq wslines (round (+ wslines 0.5))))
      (when (or (null lh)
		(>= rbot dlh)
		(<= ypos (- dlh))
		(null this-lh)
		(<= this-ypos (- dlh)))
	(unless lh
	  (let ((wend (pos-visible-in-window-p t nil t)))
	    (setq rbot (nth 3 wend)
		  rowh  (nth 4 wend)
		  vpos (nth 5 wend))))
	(unless this-lh
	  (let ((wstart (pos-visible-in-window-p nil nil t)))
	    (setq this-ypos (nth 2 wstart)
		  this-height (nth 4 wstart))))
	(setq py
	      (or (nth 1 this-lh)
		  (let ((ppos (posn-at-point))
			col-row)
		    (setq col-row (posn-actual-col-row ppos))
		    (if col-row
			(- (cdr col-row) (window-vscroll))
		      (cdr (posn-col-row ppos))))))
	;; VPOS > 0 means the last line is only partially visible.
	;; But if the part that is visible is at least as tall as the
	;; default font, that means the line is actually fully
	;; readable, and something like line-spacing is hidden.  So in
	;; that case we accept the last line in the window as still
	;; visible, and consider the margin as starting one line
	;; later.
	(if (and vpos (> vpos 0))
	    (if (and rowh
		     (>= rowh (default-font-height))
		     (< rowh dlh))
		(setq last-line (min (- wslines scroll-margin) vpos))
	      (setq last-line (min (- wslines scroll-margin 1) (1- vpos)))))
	(cond
	 ;; If last line of window is fully visible, and vscrolling
	 ;; more would make this line invisible, move forward.
	 ((and (or (< (setq vs (window-vscroll nil t)) dlh)
		   (null this-height)
		   (<= this-height dlh))
	       (or (null rbot) (= rbot 0)))
	  nil)
	 ;; If cursor is not in the bottom scroll margin, and the
	 ;; current line is not too tall, or if there's a continuation
	 ;; line below this one, move forward.
	 ((and (or (null this-height) (<= this-height winh))
	       vpos
	       (> vpos 0)
	       (or (< py last-line)
                   (display--line-is-continued-p)))
	  nil)
	 ;; When already vscrolled, we vscroll some more if we can,
	 ;; or clear vscroll and move forward at end of tall image.
	 ((> vs 0)
	  (when (or (and rbot (> rbot 0))
		    (and this-height (> this-height dlh)))
	    (set-window-vscroll nil (+ vs dlh) t)))
	 ;; If cursor just entered the bottom scroll margin, move forward,
	 ;; but also optionally vscroll one line so redisplay won't recenter.
	 ((and vpos
	       (> vpos 0)
	       (= py last-line))
	  ;; Don't vscroll if the partially-visible line at window
	  ;; bottom is not too tall (a.k.a. "just one more text
	  ;; line"): in that case, we do want redisplay to behave
	  ;; normally, i.e. recenter or whatever.
	  ;;
	  ;; Note: ROWH + RBOT from the value returned by
	  ;; pos-visible-in-window-p give the total height of the
	  ;; partially-visible glyph row at the end of the window.  As
	  ;; we are dealing with floats, we disregard sub-pixel
	  ;; discrepancies between that and DLH.
	  (if (and rowh rbot (>= (- (+ rowh rbot) winh) 1))
	      (set-window-vscroll nil dlh t))
	  (line-move-1 arg noerror)
	  t)
	 ;; If there are lines above the last line, scroll-up one line.
	 ((and vpos (> vpos 0))
	  (scroll-up 1)
	  t)
	 ;; Finally, start vscroll.
	 (t
	  (set-window-vscroll nil dlh t)))))))


;; This is like line-move-1 except that it also performs
;; vertical scrolling of tall images if appropriate.
;; That is not really a clean thing to do, since it mixes
;; scrolling with cursor motion.  But so far we don't have
;; a cleaner solution to the problem of making C-n do something
;; useful given a tall image.
(defun line-move (arg &optional noerror _to-end try-vscroll)
  "Move forward ARG lines.
If NOERROR, don't signal an error if we can't move ARG lines.
TO-END is unused.
TRY-VSCROLL controls whether to vscroll tall lines: if either
`auto-window-vscroll' or TRY-VSCROLL is nil, this function will
not vscroll."
  (if noninteractive
      (line-move-1 arg noerror)
    (unless (and auto-window-vscroll try-vscroll
		 ;; Only vscroll for single line moves
		 (= (abs arg) 1)
		 ;; Under scroll-conservatively, the display engine
		 ;; does this better.
		 (zerop scroll-conservatively)
		 ;; But don't vscroll in a keyboard macro.
		 (not defining-kbd-macro)
		 (not executing-kbd-macro)
                 ;; Lines are not truncated...
                 (not
                  (and
                   (or truncate-lines (truncated-partial-width-window-p))
                   ;; ...or if lines are truncated, this buffer
                   ;; doesn't have very long lines.
                   (long-line-optimizations-p)))
		 (line-move-partial arg noerror))
      (set-window-vscroll nil 0 t)
      (if (and line-move-visual
	       ;; Display-based column are incompatible with goal-column.
	       (not goal-column)
               ;; Lines aren't truncated.
               (not
                (and
                 (or truncate-lines (truncated-partial-width-window-p))
                 (long-line-optimizations-p)))
	       ;; When the text in the window is scrolled to the left,
	       ;; display-based motion doesn't make sense (because each
	       ;; logical line occupies exactly one screen line).
	       (not (> (window-hscroll) 0))
	       ;; Likewise when the text _was_ scrolled to the left
	       ;; when the current run of vertical motion commands
	       ;; started.
	       (not (and (memq last-command
			       `(next-line previous-line ,this-command))
			 auto-hscroll-mode
			 (numberp temporary-goal-column)
			 (>= temporary-goal-column
			    (- (window-width) hscroll-margin)))))
	  (prog1 (line-move-visual arg noerror)
	    ;; If we moved into a tall line, set vscroll to make
	    ;; scrolling through tall images more smooth.
	    (let ((lh (line-pixel-height))
		  (edges (window-inside-pixel-edges))
		  (dlh (default-line-height))
		  winh)
	      (setq winh (- (nth 3 edges) (nth 1 edges) 1))
	      (if (and (< arg 0)
		       (< (point) (window-start))
		       (> lh winh))
		  (set-window-vscroll
		   nil
		   (- lh dlh) t))))
	(line-move-1 arg noerror)))))

;; Display-based alternative to line-move-1.
;; Arg says how many lines to move.  The value is t if we can move the
;; specified number of lines.
(defun line-move-visual (arg &optional noerror)
  "Move ARG lines forward.
If NOERROR, don't signal an error if we can't move that many lines."
  (let ((opoint (point))
	(hscroll (window-hscroll))
        (lnum-width (line-number-display-width t))
	target-hscroll)
    ;; Check if the previous command was a line-motion command, or if
    ;; we were called from some other command.
    (if (and (consp temporary-goal-column)
	     (memq last-command `(next-line previous-line ,this-command)))
	;; If so, there's no need to reset `temporary-goal-column',
	;; but we may need to hscroll.
        (if (or (/= (cdr temporary-goal-column) hscroll)
                (>  (cdr temporary-goal-column) 0))
            (setq target-hscroll (cdr temporary-goal-column)))
      ;; Otherwise, we should reset `temporary-goal-column'.
      (let ((posn (posn-at-point))
	    x-pos)
	(cond
	 ;; Handle the `overflow-newline-into-fringe' case
	 ;; (left-fringe is for the R2L case):
	 ((memq (nth 1 posn) '(right-fringe left-fringe))
	  (setq temporary-goal-column (cons (window-width) hscroll)))
	 ((car (posn-x-y posn))
	  (setq x-pos (- (car (posn-x-y posn)) lnum-width))
	  ;; In R2L lines, the X pixel coordinate is measured from the
	  ;; left edge of the window, but columns are still counted
	  ;; from the logical-order beginning of the line, i.e. from
	  ;; the right edge in this case.  We need to adjust for that.
	  (if (eq (current-bidi-paragraph-direction) 'right-to-left)
	      (setq x-pos (- (window-body-width nil t) 1 x-pos)))
	  (setq temporary-goal-column
		(cons (/ (float x-pos)
			 (frame-char-width))
                      hscroll)))
	 (executing-kbd-macro
	  ;; When we move beyond the first/last character visible in
	  ;; the window, posn-at-point will return nil, so we need to
	  ;; approximate the goal column as below.
	  (setq temporary-goal-column
		(mod (current-column) (window-text-width)))))))
    (if target-hscroll
	(set-window-hscroll (selected-window) target-hscroll))
    ;; vertical-motion can move more than it was asked to if it moves
    ;; across display strings with newlines.  We don't want to ring
    ;; the bell and announce beginning/end of buffer in that case.
    (or (and (or (and (>= arg 0)
		      (>= (vertical-motion
			   (cons (or goal-column
				     (if (consp temporary-goal-column)
					 (car temporary-goal-column)
				       temporary-goal-column))
				 arg))
			  arg))
		 (and (< arg 0)
		      (<= (vertical-motion
			   (cons (or goal-column
				     (if (consp temporary-goal-column)
					 (car temporary-goal-column)
				       temporary-goal-column))
				 arg))
			  arg)))
	     (or (>= arg 0)
		 (/= (point) opoint)
		 ;; If the goal column lies on a display string,
		 ;; `vertical-motion' advances the cursor to the end
		 ;; of the string.  For arg < 0, this can cause the
		 ;; cursor to get stuck.  (Bug#3020).
		 (= (vertical-motion arg) arg)))
	(unless noerror
	  (signal (if (< arg 0) 'beginning-of-buffer 'end-of-buffer)
		  nil)))))

;; This is the guts of next-line and previous-line.
;; Arg says how many lines to move.
;; The value is t if we can move the specified number of lines.
(defun line-move-1 (arg &optional noerror _to-end)
  ;; Don't run any point-motion hooks, and disregard intangibility,
  ;; for intermediate positions.
  (with-suppressed-warnings ((obsolete inhibit-point-motion-hooks))
  (let ((outer-ipmh inhibit-point-motion-hooks)
	(inhibit-point-motion-hooks t)
	(opoint (point))
	(orig-arg arg))
    (if (consp temporary-goal-column)
	(setq temporary-goal-column (+ (car temporary-goal-column)
				       (cdr temporary-goal-column))))
    (unwind-protect
	(progn
	  (if (not (memq last-command '(next-line previous-line)))
	      (setq temporary-goal-column
		    (if (and track-eol (eolp)
			     ;; Don't count beg of empty line as end of line
			     ;; unless we just did explicit end-of-line.
			     (or (not (bolp)) (eq last-command 'move-end-of-line)))
			most-positive-fixnum
		      (current-column))))

	  (if (not (or (integerp selective-display)
                       line-move-ignore-invisible))
	      ;; Use just newline characters.
	      ;; Set ARG to 0 if we move as many lines as requested.
	      (or (if (> arg 0)
		      (progn (if (> arg 1) (forward-line (1- arg)))
			     ;; This way of moving forward ARG lines
			     ;; verifies that we have a newline after the last one.
			     ;; It doesn't get confused by intangible text.
			     (end-of-line)
			     (if (zerop (forward-line 1))
				 (setq arg 0)))
		    (and (zerop (forward-line arg))
			 (bolp)
			 (setq arg 0)))
		  (unless noerror
		    (signal (if (< arg 0)
				'beginning-of-buffer
			      'end-of-buffer)
			    nil)))
	    ;; Move by arg lines, but ignore invisible ones.
	    (let (done)
	      (while (and (> arg 0) (not done))
		;; If the following character is currently invisible,
		;; skip all characters with that same `invisible' property value.
		(while (and (not (eobp)) (invisible-p (point)))
		  (goto-char (next-char-property-change (point))))
		;; Move a line.
		;; We don't use `end-of-line', since we want to escape
		;; from field boundaries occurring exactly at point.
		(goto-char (constrain-to-field
			    (let ((inhibit-field-text-motion t))
			      (line-end-position))
			    (point) t t
			    'inhibit-line-move-field-capture))
		;; If there's no invisibility here, move over the newline.
		(cond
		 ((eobp)
		  (if (not noerror)
		      (signal 'end-of-buffer nil)
		    (setq done t)))
		 ((and (> arg 1)  ;; Use vertical-motion for last move
		       (not (integerp selective-display))
		       (not (invisible-p (point))))
		  ;; We avoid vertical-motion when possible
		  ;; because that has to fontify.
		  (forward-line 1))
		 ;; Otherwise move a more sophisticated way.
		 ((zerop (vertical-motion 1))
		  (if (not noerror)
		      (signal 'end-of-buffer nil)
		    (setq done t))))
		(unless done
		  (setq arg (1- arg))))
	      ;; The logic of this is the same as the loop above,
	      ;; it just goes in the other direction.
	      (while (and (< arg 0) (not done))
		;; For completely consistency with the forward-motion
		;; case, we should call beginning-of-line here.
		;; However, if point is inside a field and on a
		;; continued line, the call to (vertical-motion -1)
		;; below won't move us back far enough; then we return
		;; to the same column in line-move-finish, and point
		;; gets stuck -- cyd
		(forward-line 0)
		(cond
		 ((bobp)
		  (if (not noerror)
		      (signal 'beginning-of-buffer nil)
		    (setq done t)))
		 ((and (< arg -1) ;; Use vertical-motion for last move
		       (not (integerp selective-display))
		       (not (invisible-p (1- (point)))))
		  (forward-line -1))
		 ((zerop (vertical-motion -1))
		  (if (not noerror)
		      (signal 'beginning-of-buffer nil)
		    (setq done t))))
		(unless done
		  (setq arg (1+ arg))
		  (while (and ;; Don't move over previous invis lines
			  ;; if our target is the middle of this line.
			  (or (zerop (or goal-column temporary-goal-column))
			      (< arg 0))
			  (not (bobp)) (invisible-p (1- (point))))
		    (goto-char (previous-char-property-change (point))))))))
	  ;; This is the value the function returns.
	  (= arg 0))

      (cond ((> arg 0)
	     ;; If we did not move down as far as desired, at least go
	     ;; to end of line.  Be sure to call point-entered and
	     ;; point-left-hooks.
	     (let* ((npoint (prog1 (line-end-position)
			      (goto-char opoint)))
		    (inhibit-point-motion-hooks outer-ipmh))
	       (goto-char npoint)))
	    ((< arg 0)
	     ;; If we did not move up as far as desired,
	     ;; at least go to beginning of line.
	     (let* ((npoint (prog1 (line-beginning-position)
			      (goto-char opoint)))
		    (inhibit-point-motion-hooks outer-ipmh))
	       (goto-char npoint)))
	    (t
	     (line-move-finish (or goal-column temporary-goal-column)
			       opoint (> orig-arg 0) (not outer-ipmh))))))))

(defun line-move-finish (column opoint forward &optional not-ipmh)
  (let ((repeat t))
    (while repeat
      ;; Set REPEAT to t to repeat the whole thing.
      (setq repeat nil)

      (let (new
	    (old (point))
	    (line-beg (line-beginning-position))
	    (line-end
	     ;; Compute the end of the line
	     ;; ignoring effectively invisible newlines.
	     (save-excursion
	       ;; Like end-of-line but ignores fields.
	       (skip-chars-forward "^\n")
	       (while (and (not (eobp)) (invisible-p (point)))
		 (goto-char (next-char-property-change (point)))
		 (skip-chars-forward "^\n"))
	       (point))))

	;; Move to the desired column.
        (if (and line-move-visual
                 (not noninteractive)
                 (not (or truncate-lines (truncated-partial-width-window-p))))
            ;; Under line-move-visual, goal-column should be
            ;; interpreted in units of the frame's canonical character
            ;; width, which is exactly what vertical-motion does.
            (vertical-motion (cons column 0))
          (line-move-to-column (truncate column)))

	;; Corner case: suppose we start out in a field boundary in
	;; the middle of a continued line.  When we get to
	;; line-move-finish, point is at the start of a new *screen*
	;; line but the same text line; then line-move-to-column would
	;; move us backwards.  Test using C-n with point on the "x" in
	;;   (insert "a" (propertize "x" 'field t) (make-string 89 ?y))
	(and forward
	     (< (point) old)
	     (goto-char old))

	(setq new (point))

	;; Process intangibility within a line.
	;; With inhibit-point-motion-hooks bound to nil, a call to
	;; goto-char moves point past intangible text.

	;; However, inhibit-point-motion-hooks controls both the
	;; intangibility and the point-entered/point-left hooks.  The
	;; following hack avoids calling the point-* hooks
	;; unnecessarily.  Note that we move *forward* past intangible
	;; text when the initial and final points are the same.
	(goto-char new)
	(with-suppressed-warnings ((obsolete inhibit-point-motion-hooks))
	  (let ((inhibit-point-motion-hooks (not not-ipmh)))
	    (goto-char new)

	    ;; If intangibility moves us to a different (later) place
	    ;; in the same line, use that as the destination.
	    (if (<= (point) line-end)
	        (setq new (point))
	      ;; If that position is "too late",
	      ;; try the previous allowable position.
	      ;; See if it is ok.
	      (backward-char)
	      (if (if forward
		      ;; If going forward, don't accept the previous
		      ;; allowable position if it is before the target line.
		      (< line-beg (point))
		    ;; If going backward, don't accept the previous
		    ;; allowable position if it is still after the target line.
		    (<= (point) line-end))
		  (setq new (point))
		;; As a last resort, use the end of the line.
		(setq new line-end)))))

	;; Now move to the updated destination, processing fields
	;; as well as intangibility.
	(goto-char opoint)
	(with-suppressed-warnings ((obsolete inhibit-point-motion-hooks))
	  (let ((inhibit-point-motion-hooks (not not-ipmh)))
	    (goto-char
	     ;; Ignore field boundaries if the initial and final
	     ;; positions have the same `field' property, even if the
	     ;; fields are non-contiguous.  This seems to be "nicer"
	     ;; behavior in many situations.
	     (if (eq (get-char-property new 'field)
		     (get-char-property opoint 'field))
		 new
	       (constrain-to-field new opoint t t
				   'inhibit-line-move-field-capture)))))

	;; If all this moved us to a different line,
	;; retry everything within that new line.
	(when (or (< (point) line-beg) (> (point) line-end))
	  ;; Repeat the intangibility and field processing.
	  (setq repeat t))))))

(defun line-move-to-column (col)
  "Try to find column COL, considering invisibility.
This function works only in certain cases,
because what we really need is for `move-to-column'
and `current-column' to be able to ignore invisible text."
  (if (zerop col)
      (beginning-of-line)
    (move-to-column col))

  (when (and line-move-ignore-invisible
	     (not (bolp)) (invisible-p (1- (point))))
    (let ((normal-location (point))
	  (normal-column (current-column)))
      ;; If the following character is currently invisible,
      ;; skip all characters with that same `invisible' property value.
      (while (and (not (eobp))
		  (invisible-p (point)))
	(goto-char (next-char-property-change (point))))
      ;; Have we advanced to a larger column position?
      (if (> (current-column) normal-column)
	  ;; We have made some progress towards the desired column.
	  ;; See if we can make any further progress.
	  (line-move-to-column (+ (current-column) (- col normal-column)))
	;; Otherwise, go to the place we originally found
	;; and move back over invisible text.
	;; that will get us to the same place on the screen
	;; but with a more reasonable buffer position.
	(goto-char normal-location)
	(let ((line-beg
               ;; We want the real line beginning, so it's consistent
               ;; with bolp below, otherwise we might infloop.
               (let ((inhibit-field-text-motion t))
                 (line-beginning-position))))
	  (while (and (not (bolp)) (invisible-p (1- (point))))
	    (goto-char (previous-char-property-change (point) line-beg))))))))

(defun move-end-of-line (arg)
  "Move point to end of current line as displayed.
With argument ARG not nil or 1, move forward ARG - 1 lines first.
If point reaches the beginning or end of buffer, it stops there.

To ignore the effects of the `intangible' text or overlay
property, bind `inhibit-point-motion-hooks' to t.
If there is an image in the current line, this function
disregards newlines that are part of the text on which the image
rests."
  (interactive "^p")
  (or arg (setq arg 1))
  (let (done)
    (while (not done)
      (let ((newpos
	     (save-excursion
	       (let ((goal-column 0)
		     (line-move-visual nil)
                     ;; Always move to eol when invoking `C-e' from
                     ;; within the minibuffer's prompt string (see
                     ;; bug#65980).
                     (inhibit-field-text-motion (minibufferp)))
		 (and (line-move arg t)
		      ;; With bidi reordering, we may not be at bol,
		      ;; so make sure we are.
		      (skip-chars-backward "^\n")
		      (not (bobp))
		      (progn
			(while (and (not (bobp)) (invisible-p (1- (point))))
			  (goto-char (previous-single-char-property-change
                                      (point) 'invisible)))
			(backward-char 1)))
		 (point)))))
	(goto-char newpos)
	(if (and (> (point) newpos)
		 (eq (preceding-char) ?\n))
	    (backward-char 1)
	  (if (and (> (point) newpos) (not (eobp))
		   (not (eq (following-char) ?\n)))
	      ;; If we skipped something intangible and now we're not
	      ;; really at eol, keep going.
	      (setq arg 1)
	    (setq done t)))))))

(defun move-beginning-of-line (arg)
  "Move point to visible beginning of current logical line.
This disregards any invisible newline characters.

When moving from position that has no `field' property, this
command doesn't enter text which has non-nil `field' property.
In particular, when invoked in the minibuffer, the command will
stop short of entering the text of the minibuffer prompt.
See `inhibit-field-text-motion' for how to inhibit this.

With argument ARG not nil or 1, move forward ARG - 1 lines first.
If point reaches the beginning or end of buffer, it stops there.
\(But if the buffer doesn't end in a newline, it stops at the
beginning of the last line.)

To ignore intangibility, bind `inhibit-point-motion-hooks' to t.
For motion by visual lines, see `beginning-of-visual-line'."
  (interactive "^p")
  (or arg (setq arg 1))

  (let ((orig (point))
	first-vis first-vis-field-value)

    ;; Move by lines, if ARG is not 1 (the default).
    (if (/= arg 1)
	(let ((line-move-visual nil))
	  (line-move (1- arg) t)))

    ;; Move to beginning-of-line, ignoring fields and invisible text.
    (let ((inhibit-field-text-motion t))
      (goto-char (line-beginning-position))
      (while (and (not (bobp)) (invisible-p (1- (point))))
        (goto-char (previous-char-property-change (point)))
        (goto-char (line-beginning-position))))

    ;; Now find first visible char in the line.
    (while (and (< (point) orig) (invisible-p (point)))
      (goto-char (next-char-property-change (point) orig)))
    (setq first-vis (point))

    ;; See if fields would stop us from reaching FIRST-VIS.
    (setq first-vis-field-value
	  (constrain-to-field first-vis orig (/= arg 1) t nil))

    (goto-char (if (/= first-vis-field-value first-vis)
		   ;; If yes, obey them.
		   first-vis-field-value
		 ;; Otherwise, move to START with attention to fields.
		 ;; (It is possible that fields never matter in this case.)
		 (constrain-to-field (point) orig
				     (/= arg 1) t nil)))))


;; Many people have said they rarely use this feature, and often type
;; it by accident.  Maybe it shouldn't even be on a key.
(put 'set-goal-column 'disabled t)

(defun set-goal-column (arg)
  "Set the current horizontal position as a goal column.
This goal column will affect the \\[next-line] and \\[previous-line] commands,
as well as the \\[scroll-up-command] and \\[scroll-down-command] commands.

Those commands will move to this position in the line moved to
rather than trying to keep the same horizontal position.

With a non-nil argument ARG, clears out the goal column so that
these commands resume normal motion.

The goal column is stored in the variable `goal-column'.  This is
a buffer-local setting."
  (interactive "P")
  (if arg
      (progn
        (setq goal-column nil)
        (message "No goal column"))
    (setq goal-column (current-column))
    (message "Goal column %d %s"
             goal-column
	     (substitute-command-keys
	      "(use \\[set-goal-column] with an arg to unset it)")))
  nil)

;;; Editing based on visual lines, as opposed to logical lines.

(defun end-of-visual-line (&optional n)
  "Move point to end of current visual line.
With argument N not nil or 1, move forward N - 1 visual lines first.
If point reaches the beginning or end of buffer, it stops there.
To ignore intangibility, bind `inhibit-point-motion-hooks' to t."
  (interactive "^p")
  (or n (setq n 1))
  (if (/= n 1)
      (let ((line-move-visual t))
	(line-move (1- n) t)))
  ;; Unlike `move-beginning-of-line', `move-end-of-line' doesn't
  ;; constrain to field boundaries, so we don't either.
  (vertical-motion (cons (window-width) 0)))

(defun beginning-of-visual-line (&optional n)
  "Move point to beginning of current visual line.
With argument N not nil or 1, move forward N - 1 visual lines first.
If point reaches the beginning or end of buffer, it stops there.
\(But if the buffer doesn't end in a newline, it stops at the
beginning of the last visual line.)
To ignore intangibility, bind `inhibit-point-motion-hooks' to t."
  (interactive "^p")
  (or n (setq n 1))
  (let ((opoint (point)))
    (if (/= n 1)
	(let ((line-move-visual t))
	  (line-move (1- n) t)))
    (vertical-motion 0)
    ;; Constrain to field boundaries, like `move-beginning-of-line'.
    (goto-char (constrain-to-field (point) opoint (/= n 1)))))

(defun kill-visual-line (&optional arg)
  "Kill the rest of the visual line.
With prefix argument ARG, kill that many visual lines from point.
If ARG is negative, kill visual lines backward.
If ARG is zero, kill the text before point on the current visual
line.

If the variable `kill-whole-line' is non-nil, and this command is
invoked at start of a line that ends in a newline, kill the newline
as well.

If you want to append the killed line to the last killed text,
use \\[append-next-kill] before \\[kill-line].

If the buffer is read-only, Emacs will beep and refrain from deleting
the line, but put the line in the kill ring anyway.  This means that
you can use this command to copy text from a read-only buffer.
\(If the variable `kill-read-only-ok' is non-nil, then this won't
even beep.)"
  (interactive "P")
  ;; Like in `kill-line', it's better to move point to the other end
  ;; of the kill before killing.
  (let ((opoint (point))
        (kill-whole-line (and kill-whole-line (bolp)))
        (orig-vlnum (cdr (nth 6 (posn-at-point)))))
    (if arg
	(vertical-motion (prefix-numeric-value arg))
      (end-of-visual-line 1)
      (if (= (point) opoint)
	  (vertical-motion 1)
        ;; The first condition below verifies we are still on the same
        ;; screen line, i.e. that the line isn't continued, and that
        ;; end-of-visual-line didn't overshoot due to complications
        ;; like display or overlay strings, intangible text, etc.:
        ;; otherwise, we don't want to kill a character that's
        ;; unrelated to the place where the visual line wraps.
        (and (= (cdr (nth 6 (posn-at-point))) orig-vlnum)
             ;; Make sure we delete the character where the line wraps
             ;; under visual-line-mode, be it whitespace or a
             ;; character whose category set permits wrapping at it.
             (or (looking-at-p "[ \t]")
                 (and word-wrap-by-category
                      (aref (char-category-set (following-char)) ?\|)))
             (forward-char))))
    (kill-region opoint (if (and kill-whole-line (= (following-char) ?\n))
			    (1+ (point))
			  (point)))))

(defun next-logical-line (&optional arg try-vscroll)
  "Move cursor vertically down ARG lines.
This is identical to `next-line', except that it always moves
by logical lines instead of visual lines, ignoring the value of
the variable `line-move-visual'."
  (interactive "^p\np")
  (let ((line-move-visual nil))
    (with-no-warnings
      (next-line arg try-vscroll))))

(defun previous-logical-line (&optional arg try-vscroll)
  "Move cursor vertically up ARG lines.
This is identical to `previous-line', except that it always moves
by logical lines instead of visual lines, ignoring the value of
the variable `line-move-visual'."
  (interactive "^p\np")
  (let ((line-move-visual nil))
    (with-no-warnings
      (previous-line arg try-vscroll))))

(defgroup visual-line nil
  "Editing based on visual lines."
  :group 'convenience
  :version "23.1")

(defvar visual-line-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap kill-line] 'kill-visual-line)
    (define-key map [remap move-beginning-of-line] 'beginning-of-visual-line)
    (define-key map [remap move-end-of-line]  'end-of-visual-line)
    ;; These keybindings interfere with xterm function keys.  Are
    ;; there any other suitable bindings?
    ;; (define-key map "\M-[" 'previous-logical-line)
    ;; (define-key map "\M-]" 'next-logical-line)
    map))

(defcustom visual-line-fringe-indicators '(nil nil)
  "How fringe indicators are shown for wrapped lines in `visual-line-mode'.
The value should be a list of the form (LEFT RIGHT), where LEFT
and RIGHT are symbols representing the bitmaps to display, to
indicate wrapped lines, in the left and right fringes respectively.
See also `fringe-indicator-alist'.
The default is not to display fringe indicators for wrapped lines.
This variable does not affect fringe indicators displayed for
other purposes."
  :type '(list (choice (const :tag "Hide left indicator" nil)
		       (const :tag "Left curly arrow" left-curly-arrow)
		       (symbol :tag "Other bitmap"))
	       (choice (const :tag "Hide right indicator" nil)
		       (const :tag "Right curly arrow" right-curly-arrow)
		       (symbol :tag "Other bitmap")))
  :set (lambda (symbol value)
	 (dolist (buf (buffer-list))
	   (with-current-buffer buf
	     (when (and (boundp 'visual-line-mode)
			(symbol-value 'visual-line-mode))
	       (setq fringe-indicator-alist
		     (cons (cons 'continuation value)
			   (assq-delete-all
			    'continuation
			    (copy-tree fringe-indicator-alist)))))))
	 (set-default symbol value)))

(defvar visual-line--saved-state nil)

(define-minor-mode visual-line-mode
  "Toggle visual line based editing (Visual Line mode) in the current buffer.

When Visual Line mode is enabled, `word-wrap' is turned on in
this buffer, and simple editing commands are redefined to act on
visual lines, not logical lines.  See Info node `Visual Line
Mode' for details.
Turning on this mode disables line truncation set up by
variables `truncate-lines' and `truncate-partial-width-windows'."
  :keymap visual-line-mode-map
  :group 'visual-line
  :lighter " Wrap"
  (if visual-line-mode
      (progn
        (unless visual-line--saved-state
	  (setq-local visual-line--saved-state (list nil))
	  ;; Save the local values of some variables, to be restored if
	  ;; visual-line-mode is turned off.
	  (dolist (var '(line-move-visual truncate-lines
		                          truncate-partial-width-windows
		                          word-wrap fringe-indicator-alist))
	    (if (local-variable-p var)
	        (push (cons var (symbol-value var))
		      visual-line--saved-state))))
        (setq-local line-move-visual t)
        (setq-local truncate-partial-width-windows nil)
	(setq truncate-lines nil
	      word-wrap t
	      fringe-indicator-alist
	      (cons (cons 'continuation visual-line-fringe-indicators)
		    fringe-indicator-alist)))
    (kill-local-variable 'line-move-visual)
    (kill-local-variable 'word-wrap)
    (kill-local-variable 'truncate-lines)
    (kill-local-variable 'truncate-partial-width-windows)
    (kill-local-variable 'fringe-indicator-alist)
    (dolist (saved visual-line--saved-state)
      (when (car saved)
        (set (make-local-variable (car saved)) (cdr saved))))
    (kill-local-variable 'visual-line--saved-state)))

(defun turn-on-visual-line-mode ()
  (visual-line-mode 1))

(define-globalized-minor-mode global-visual-line-mode
  visual-line-mode turn-on-visual-line-mode)


(defun transpose-chars (arg)
  "Interchange characters around point, moving forward one character.
With prefix arg ARG, effect is to take character before point
and drag it forward past ARG other characters (backward if ARG negative).
If at end of line, the previous two chars are exchanged."
  (interactive "*p")
  (when (and (eolp) (not (bobp))
	     (not (get-text-property (1- (point)) 'read-only)))
    (forward-char -1))
  (transpose-subr #'forward-char arg))

(defun transpose-words (arg)
  "Interchange words around point, leaving point at end of them.
With prefix arg ARG, effect is to take word before or around point
and drag it forward past ARG other words (backward if ARG negative).
If ARG is zero, the words around or after point and around or after mark
are interchanged."
  ;; FIXME: `foo a!nd bar' should transpose into `bar and foo'.
  (interactive "*p")
  (transpose-subr 'forward-word arg))

(defun transpose-sexps-default-function (arg)
  "Default method to locate a pair of points for `transpose-sexps'."
  ;; Here we should try to simulate the behavior of
  ;; (cons (progn (forward-sexp x) (point))
  ;;       (progn (forward-sexp (- x)) (point)))
  ;; Except that we don't want to rely on the second forward-sexp
  ;; putting us back to where we want to be, since forward-sexp-function
  ;; might do funny things like infix-precedence.
  (if (if (> arg 0)
	  (looking-at "\\sw\\|\\s_")
	(and (not (bobp))
	     (save-excursion
               (forward-char -1)
               (looking-at "\\sw\\|\\s_"))))
      ;; Jumping over a symbol.  We might be inside it, mind you.
      (progn (funcall (if (> arg 0)
			  #'skip-syntax-backward #'skip-syntax-forward)
		      "w_")
	     (cons (save-excursion (forward-sexp arg) (point)) (point)))
    ;; Otherwise, we're between sexps.  Take a step back before jumping
    ;; to make sure we'll obey the same precedence no matter which
    ;; direction we're going.
    (funcall (if (> arg 0) #'skip-syntax-backward #'skip-syntax-forward)
             " .")
    (cons (save-excursion (forward-sexp arg) (point))
	  (progn (while (or (forward-comment (if (> arg 0) 1 -1))
			    (not (zerop (funcall (if (> arg 0)
						     #'skip-syntax-forward
						   #'skip-syntax-backward)
						 ".")))))
		 (point)))))

(defvar transpose-sexps-function #'transpose-sexps-default-function
  "If non-nil, `transpose-sexps' delegates to this function.

This function takes one argument ARG, a number.  Its expected
return value is a position pair, which is a cons (BEG . END),
where BEG and END are buffer positions.")

(defun transpose-sexps (arg &optional interactive)
  "Like \\[transpose-chars] (`transpose-chars'), but applies to sexps.
Unlike `transpose-words', point must be between the two sexps and not
in the middle of a sexp to be transposed.
With non-zero prefix arg ARG, effect is to take the sexp before point
and drag it forward past ARG other sexps (backward if ARG is negative).
If ARG is zero, the sexps ending at or after point and at or after mark
are interchanged.
If INTERACTIVE is non-nil, as it is interactively,
report errors as appropriate for this kind of usage."
  (interactive "*p\nd")
  (if interactive
      (condition-case nil
          (transpose-sexps arg nil)
        (scan-error (user-error "Not between two complete sexps")))
    (transpose-subr transpose-sexps-function arg 'special)))

(defun transpose-lines (arg)
  "Exchange current line and previous line, leaving point after both.
With argument ARG, takes previous line and moves it past ARG lines.
With argument 0, interchanges line point is in with line mark is in."
  (interactive "*p")
  (transpose-subr (lambda (arg)
                    (if (> arg 0)
                        (progn
                          ;; Move forward over ARG lines,
                          ;; but create newlines if necessary.
                          (setq arg (forward-line arg))
                          (if (/= (preceding-char) ?\n)
                              (setq arg (1+ arg)))
                          (if (> arg 0)
                              (newline arg)))
                      (forward-line arg)))
		  arg))

;; FIXME seems to leave point BEFORE the current object when ARG = 0,
;; which seems inconsistent with the ARG /= 0 case.
;; FIXME document SPECIAL.
(defun transpose-subr (mover arg &optional special)
  "Subroutine to do the work of transposing objects.
Works for lines, sentences, paragraphs, etc.  MOVER is a function
that moves forward by units of the given
object (e.g. `forward-sentence', `forward-paragraph'), or a
function calculating a cons of buffer positions.

  If ARG is zero, exchanges the current object with the one
containing mark.  If ARG is an integer, moves the current object
past ARG following (if ARG is positive) or preceding (if ARG is
negative) objects, leaving point after the current object."
  (let ((aux (if special mover
	       (lambda (x)
		 (cons (progn (funcall mover x) (point))
		       (progn (funcall mover (- x)) (point))))))
	pos1 pos2)
    (cond
     ((= arg 0)
      (save-excursion
	(setq pos1 (funcall aux 1))
	(goto-char (or (mark) (error "No mark set in this buffer")))
	(setq pos2 (funcall aux 1))
	(transpose-subr-1 pos1 pos2))
      (exchange-point-and-mark))
     ((> arg 0)
      (setq pos1 (funcall aux -1))
      (setq pos2 (funcall aux arg))
      (transpose-subr-1 pos1 pos2)
      (goto-char (car pos2)))
     (t
      (setq pos1 (funcall aux -1))
      (goto-char (car pos1))
      (setq pos2 (funcall aux arg))
      (transpose-subr-1 pos1 pos2)
      (goto-char (+ (car pos2) (- (cdr pos1) (car pos1))))))))

(defun transpose-subr-1 (pos1 pos2)
  (unless (and pos1 pos2)
    (error "Don't have two things to transpose"))
  (when (> (car pos1) (cdr pos1)) (setq pos1 (cons (cdr pos1) (car pos1))))
  (when (> (car pos2) (cdr pos2)) (setq pos2 (cons (cdr pos2) (car pos2))))
  (when (> (car pos1) (car pos2))
    (let ((swap pos1))
      (setq pos1 pos2 pos2 swap)))
  (if (> (cdr pos1) (car pos2)) (error "Don't have two things to transpose"))
  (atomic-change-group
    ;; This sequence of insertions attempts to preserve marker
    ;; positions at the start and end of the transposed objects.
    (let* ((word (buffer-substring (car pos2) (cdr pos2)))
	   (len1 (- (cdr pos1) (car pos1)))
	   (len2 (length word))
	   (boundary (make-marker)))
      (set-marker boundary (car pos2))
      (goto-char (cdr pos1))
      (insert-before-markers word)
      (setq word (delete-and-extract-region (car pos1) (+ (car pos1) len1)))
      (goto-char boundary)
      (insert word)
      (goto-char (+ boundary len1))
      (delete-region (point) (+ (point) len2))
      (set-marker boundary nil))))

(defun backward-word (&optional arg)
  "Move backward until encountering the beginning of a word.
With argument ARG, do this that many times.
If ARG is omitted or nil, move point backward one word.

The word boundaries are normally determined by the buffer's
syntax table and character script (according to
`char-script-table'), but `find-word-boundary-function-table',
such as set up by `subword-mode', can change that.  If a Lisp
program needs to move by words determined strictly by the syntax
table, it should use `backward-word-strictly' instead.  See Info
node `(elisp) Word Motion' for details."
  (interactive "^p")
  (forward-word (- (or arg 1))))

(defun mark-word (&optional arg allow-extend)
  "Set mark ARG words from point or move mark one word.
When called from Lisp with ALLOW-EXTEND omitted or nil, mark is
set ARG words from point.
With ARG and ALLOW-EXTEND both non-nil (interactively, with prefix
argument), the place to which mark goes is the same place \\[forward-word]
would move to with the same argument; if the mark is active, it moves
ARG words from its current position, otherwise it is set ARG words
from point.
When invoked interactively without a prefix argument and no active
region, mark moves one word forward.
When invoked interactively without a prefix argument, and region
is active, mark moves one word away of point (i.e., forward
if mark is at or after point, back if mark is before point), thus
extending the region by one word.  Since the direction of region
extension depends on the relative position of mark and point, you
can change the direction by \\[exchange-point-and-mark]."
  (interactive "P\np")
  (cond ((and allow-extend
	      (or (and (eq last-command this-command) (mark t))
		  (region-active-p)))
	 (setq arg (if arg (prefix-numeric-value arg)
		     (if (< (mark) (point)) -1 1)))
	 (set-mark
	  (save-excursion
	    (goto-char (mark))
	    (forward-word arg)
	    (point))))
	(t
	 (push-mark
	  (save-excursion
	    (forward-word (prefix-numeric-value arg))
	    (point))
	  nil t))))

(defun kill-word (arg)
  "Kill characters forward until encountering the end of a word.
With argument ARG, do this that many times."
  (interactive "p")
  (kill-region (point) (progn (forward-word arg) (point))))

(defun backward-kill-word (arg)
  "Kill characters backward until encountering the beginning of a word.
With argument ARG, do this that many times."
  (interactive "p")
  (kill-word (- arg)))

(defun current-word (&optional strict really-word)
  "Return the word at or near point, as a string.
The return value includes no text properties.

If optional arg STRICT is non-nil, return nil unless point is
within or adjacent to a word, otherwise look for a word within
point's line.  If there is no word anywhere on point's line, the
value is nil regardless of STRICT.

By default, this function treats as a single word any sequence of
characters that have either word or symbol syntax.  If optional
arg REALLY-WORD is non-nil, only characters of word syntax can
constitute a word."
  (save-excursion
    (let* ((oldpoint (point)) (start (point)) (end (point))
	   (syntaxes (if really-word "w" "w_"))
	   (not-syntaxes (concat "^" syntaxes)))
      (skip-syntax-backward syntaxes) (setq start (point))
      (goto-char oldpoint)
      (skip-syntax-forward syntaxes) (setq end (point))
      (when (and (eq start oldpoint) (eq end oldpoint)
		 ;; Point is neither within nor adjacent to a word.
		 (not strict))
	;; Look for preceding word in same line.
	(skip-syntax-backward not-syntaxes (line-beginning-position))
	(if (bolp)
	    ;; No preceding word in same line.
	    ;; Look for following word in same line.
	    (progn
	      (skip-syntax-forward not-syntaxes (line-end-position))
	      (setq start (point))
	      (skip-syntax-forward syntaxes)
	      (setq end (point)))
	  (setq end (point))
	  (skip-syntax-backward syntaxes)
	  (setq start (point))))
      ;; If we found something nonempty, return it as a string.
      (unless (= start end)
	(buffer-substring-no-properties start end)))))

(defun forward-unix-word (n &optional delim)
  "Move forward N Unix-words.
A Unix-word is whitespace-delimited.
A negative N means go backwards to the beginning of Unix-words.

Unix-words differ from Emacs words in that they are always delimited by
whitespace, regardless of the buffer's syntax table.  This function
emulates how C-w at the Unix terminal or shell identifies words.

Optional argument DELIM specifies what characters are considered
whitespace.  It is a string as might be passed to `skip-chars-forward'.
The default is \"\\s\\f\\n\\r\\t\\v\".  Do not prefix a `^' character."
  (when (string-prefix-p "^" delim)
    (error "DELIM argument must not begin with `^'"))
  (unless (zerop n)
    ;; We do skip over newlines by default because `backward-word' does.
    (let* ((delim (or delim "\s\f\n\r\t\v"))
           (ndelim (format "^%s" delim))
           (start (point))
           (fun (if (> n 0)
                    #'skip-chars-forward
                  #'skip-chars-backward)))
      (dotimes (_ (abs n))
        (funcall fun delim)
        (funcall fun ndelim))
      (constrain-to-field nil start))))

(defun unix-word-rubout (arg)
  "Kill ARG Unix-words backwards.
A Unix-word is whitespace-delimited.
Interactively, ARG is the numeric prefix argument, defaulting to 1.
A negative ARG means to kill forwards.

Unix-words differ from Emacs words in that they are always delimited by
whitespace, regardless of the buffer's syntax table.
Thus, this command emulates C-w at the Unix terminal or shell.
See also this command's nakesake in Info node
`(readline)Commands For Killing'."
  (interactive "^p")
  (let ((start (point)))
    (forward-unix-word (- arg))
    (kill-region start (point))))

(defun unix-filename-rubout (arg)
  "Kill ARG Unix-words backwards, also treating slashes as word delimiters.
A Unix-word is whitespace-delimited.
Interactively, ARG is the numeric prefix argument, defaulting to 1.
A negative ARG means to kill forwards.

This is like `unix-word-rubout' (which see), but `/' and `\\' are also
treated as delimiting words.  See this command's namesake in Info node
`(readline)Commands For Killing'."
  (interactive "^p")
  (let ((start (point)))
    (forward-unix-word (- arg) "\\\\/\s\f\n\r\t\v")
    (kill-region start (point))))

(defcustom fill-prefix nil
  "String for filling to insert at front of new line, or nil for none."
  :type '(choice (const :tag "None" nil)
                 string)
  :safe #'string-or-null-p
  :local t
  :group 'fill)

(defcustom auto-fill-inhibit-regexp nil
  "Regexp to match lines that should not be auto-filled."
  :type '(choice (const :tag "None" nil)
		 regexp)
  :group 'fill)

(defun do-auto-fill ()
  "The default value for `normal-auto-fill-function'.
This is the default auto-fill function, some major modes use a different one.
Returns t if it really did any work."
  (let (fc justify give-up
	   (fill-prefix fill-prefix))
    (if (or (not (setq justify (current-justification)))
	    (null (setq fc (current-fill-column)))
	    (and (eq justify 'left)
		 (<= (current-column) fc))
	    (and auto-fill-inhibit-regexp
		 (save-excursion (beginning-of-line)
				 (looking-at auto-fill-inhibit-regexp))))
	nil ;; Auto-filling not required
      (if (memq justify '(full center right))
	  (save-excursion (unjustify-current-line)))

      ;; Choose a fill-prefix automatically.
      (when (and adaptive-fill-mode
		 (or (null fill-prefix) (string= fill-prefix "")))
	(let ((prefix
	       (fill-context-prefix
		(save-excursion (fill-forward-paragraph -1) (point))
		(save-excursion (fill-forward-paragraph 1) (point)))))
	  (and prefix (not (equal prefix ""))
	       ;; Use auto-indentation rather than a guessed empty prefix.
	       (not (and fill-indent-according-to-mode
			 (string-match "\\`[ \t]*\\'" prefix)))
	       (setq fill-prefix prefix))))

      (while (and (not give-up) (> (current-column) fc))
        ;; Determine where to split the line.
        (let ((fill-point
               (save-excursion
                 (beginning-of-line)
                 ;; Don't split earlier in the line than the length of the
                 ;; fill prefix, since the resulting line would be longer.
                 (when fill-prefix
                   (move-to-column (string-width fill-prefix)))
                 (let ((after-prefix (point)))
                    (move-to-column (1+ fc))
                    (fill-move-to-break-point after-prefix)
                    (point)))))

	  ;; See whether the place we found is any good.
	  (if (save-excursion
		(goto-char fill-point)
		(or (bolp)
		    ;; There is no use breaking at end of line.
		    (save-excursion (skip-chars-forward " ") (eolp))
		    ;; Don't split right after a comment starter
		    ;; since we would just make another comment starter.
		    (and comment-start-skip
			 (let ((limit (point)))
			   (beginning-of-line)
			   (and (re-search-forward comment-start-skip
						   limit t)
				(eq (point) limit))))))
	      ;; No good place to break => stop trying.
	      (setq give-up t)
	    ;; Ok, we have a useful place to break the line.  Do it.
	    (let ((prev-column (current-column)))
	      ;; If point is at the fill-point, do not `save-excursion'.
	      ;; Otherwise, if a comment prefix or fill-prefix is inserted,
	      ;; point will end up before it rather than after it.
	      (if (save-excursion
		    (skip-chars-backward " \t")
		    (= (point) fill-point))
		  (default-indent-new-line t)
		(save-excursion
		  (goto-char fill-point)
		  (default-indent-new-line t)))
	      ;; Now do justification, if required
	      (if (not (eq justify 'left))
		  (save-excursion
		    (end-of-line 0)
		    (justify-current-line justify nil t)))
	      ;; If making the new line didn't reduce the hpos of
	      ;; the end of the line, then give up now;
	      ;; trying again will not help.
	      (if (>= (current-column) prev-column)
		  (setq give-up t))))))
      ;; Justify last line.
      (justify-current-line justify t t)
      t)))

(defvar comment-line-break-function 'comment-indent-new-line
  "Mode-specific function that line breaks and continues a comment.
This function is called during auto-filling when a comment syntax
is defined.
The function should take a single optional argument, which is a flag
indicating whether it should use soft newlines.")

(defun default-indent-new-line (&optional soft force)
  "Break line at point and indent.
If a comment syntax is defined, call `comment-line-break-function'.

The inserted newline is marked hard if variable `use-hard-newlines' is true,
unless optional argument SOFT is non-nil."
  (interactive (list nil t))
  (if comment-start
      ;; Force breaking the line when called interactively.
      (if force
          (let ((comment-auto-fill-only-comments nil))
            (funcall comment-line-break-function soft))
        (funcall comment-line-break-function soft))
    ;; Insert the newline before removing empty space so that markers
    ;; get preserved better.
    (if soft (insert-and-inherit ?\n) (newline 1))
    (save-excursion (forward-char -1) (delete-horizontal-space))
    (delete-horizontal-space)

    (if (and fill-prefix (not adaptive-fill-mode))
	;; Blindly trust a non-adaptive fill-prefix.
	(progn
	  (indent-to-left-margin)
	  (insert-before-markers-and-inherit fill-prefix))

      (cond
       ;; If there's an adaptive prefix, use it unless we're inside
       ;; a comment and the prefix is not a comment starter.
       (fill-prefix
	(indent-to-left-margin)
	(insert-and-inherit fill-prefix))
       ;; If we're not inside a comment, just try to indent.
       (t (indent-according-to-mode))))))

(defvar inhibit-auto-fill nil
  "Non-nil means to do as if `auto-fill-mode' was disabled.")

(defun internal-auto-fill ()
  "The function called by `self-insert-command' to perform auto-filling."
  (unless (or inhibit-auto-fill
              (and comment-start
                   comment-auto-fill-only-comments
                   (not (nth 4 (syntax-ppss)))))
    (funcall auto-fill-function)))

(defvar normal-auto-fill-function 'do-auto-fill
  "The function to use for `auto-fill-function' if Auto Fill mode is turned on.
Some major modes set this.")

(put 'auto-fill-function :minor-mode-function 'auto-fill-mode)
;; `functions' and `hooks' are usually unsafe to set, but setting
;; auto-fill-function to nil in a file-local setting is safe and
;; can be useful to prevent auto-filling.
(put 'auto-fill-function 'safe-local-variable 'null)

(define-minor-mode auto-fill-mode
  "Toggle automatic line breaking (Auto Fill mode).

When Auto Fill mode is enabled, inserting a space at a column
beyond `current-fill-column' automatically breaks the line at a
previous space.

When `auto-fill-mode' is on, the `auto-fill-function' variable is
non-nil.

The value of `normal-auto-fill-function' specifies the function to use
for `auto-fill-function' when turning Auto Fill mode on."
  :variable (auto-fill-function
             . (lambda (v) (setq auto-fill-function
                            (if v normal-auto-fill-function)))))

;; This holds a document string used to document auto-fill-mode.
(defun auto-fill-function ()
  "Automatically break line at a previous space, in insertion of text."
  nil)

(defun turn-on-auto-fill ()
  "Unconditionally turn on Auto Fill mode."
  (auto-fill-mode 1))

(defun turn-off-auto-fill ()
  "Unconditionally turn off Auto Fill mode."
  (auto-fill-mode -1))

(custom-add-option 'text-mode-hook 'turn-on-auto-fill)

(defun set-fill-column (arg)
  "Set `fill-column' to specified argument.
Use \\[universal-argument] followed by a number to specify a column.
Just \\[universal-argument] as argument means to use the current column."
  (interactive
   (list (or current-prefix-arg
             ;; We used to use current-column silently, but C-x f is too easily
             ;; typed as a typo for C-x C-f, so we turned it into an error and
             ;; now an interactive prompt.
             (read-number (format "Change fill-column from %s to: " fill-column)
                          (current-column)))))
  (if (consp arg)
      (setq arg (current-column)))
  (if (not (integerp arg))
      ;; Disallow missing argument; it's probably a typo for C-x C-f.
      (error "set-fill-column requires an explicit argument")
    (message "Fill column set to %d (was %d)" arg fill-column)
    (setq fill-column arg)))

(defun set-selective-display (arg)
  "Set `selective-display' to ARG; clear it if no arg.
When the value of `selective-display' is a number > 0,
lines whose indentation is >= that value are not displayed.
The variable `selective-display' has a separate value for each buffer."
  (interactive "P")
  (if (eq selective-display t)
      (error "selective-display already in use for marked lines"))
  (let ((current-vpos
	 (save-restriction
	   (narrow-to-region (point-min) (point))
	   (goto-char (window-start))
	   (vertical-motion (window-height)))))
    (setq selective-display
	  (and arg (prefix-numeric-value arg)))
    (recenter current-vpos))
  (set-window-start (selected-window) (window-start))
  (princ "selective-display set to " t)
  (prin1 selective-display t)
  (princ "." t))

(defvaralias 'indicate-unused-lines 'indicate-empty-lines)

(defun toggle-truncate-lines (&optional arg)
  "Toggle truncating of long lines for the current buffer.
When truncating is off, long lines are folded.
With prefix argument ARG, truncate long lines if ARG is positive,
otherwise fold them.  Note that in side-by-side windows, this
command has no effect if `truncate-partial-width-windows' is
non-nil."
  (interactive "P")
  (setq truncate-lines
	(if (null arg)
	    (not truncate-lines)
	  (> (prefix-numeric-value arg) 0)))
  (force-mode-line-update)
  (unless truncate-lines
    (let ((buffer (current-buffer)))
      (walk-windows (lambda (window)
		      (if (eq buffer (window-buffer window))
			  (set-window-hscroll window 0)))
		    nil t)))
  (message "Truncate long lines %s%s"
	   (if truncate-lines "enabled" "disabled")
           (if (and truncate-lines visual-line-mode)
               (progn
                 (visual-line-mode -1)
                 (format-message " and `visual-line-mode' disabled"))
             "")))

(defun toggle-word-wrap (&optional arg)
  "Toggle whether to use word-wrapping for continuation lines.
With prefix argument ARG, wrap continuation lines at word boundaries
if ARG is positive, otherwise wrap them at the right screen edge.
This command toggles the value of `word-wrap'.  It has no effect
if long lines are truncated."
  (interactive "P")
  (setq word-wrap
	(if (null arg)
	    (not word-wrap)
	  (> (prefix-numeric-value arg) 0)))
  (force-mode-line-update)
  (message "Word wrapping %s"
	   (if word-wrap "enabled" "disabled")))

(defvar overwrite-mode-textual " Ovwrt"
  "The string displayed in the mode line when in overwrite mode.")
(defvar overwrite-mode-binary " Bin Ovwrt"
  "The string displayed in the mode line when in binary overwrite mode.")

(define-minor-mode overwrite-mode
  "Toggle Overwrite mode.

When Overwrite mode is enabled, printing characters typed in
replace existing text on a one-for-one basis, rather than pushing
it to the right.  At the end of a line, such characters extend
the line.  Before a tab, such characters insert until the tab is
filled in.  \\[quoted-insert] still inserts characters in
overwrite mode; this is supposed to make it easier to insert
characters when necessary."
  :variable (overwrite-mode
             . (lambda (v) (setq overwrite-mode (if v 'overwrite-mode-textual)))))

(define-minor-mode binary-overwrite-mode
  "Toggle Binary Overwrite mode.

When Binary Overwrite mode is enabled, printing characters typed
in replace existing text.  Newlines are not treated specially, so
typing at the end of a line joins the line to the next, with the
typed character between them.  Typing before a tab character
simply replaces the tab with the character typed.
\\[quoted-insert] replaces the text at the cursor, just as
ordinary typing characters do.

Note that Binary Overwrite mode is not its own minor mode; it is
a specialization of overwrite mode, entered by setting the
`overwrite-mode' variable to `overwrite-mode-binary'."
  :variable (overwrite-mode
             . (lambda (v) (setq overwrite-mode (if v 'overwrite-mode-binary)))))

(define-minor-mode line-number-mode
  "Toggle line number display in the mode line (Line Number mode).

Line numbers do not appear for very large buffers and buffers
with very long lines; see variables `line-number-display-limit'
and `line-number-display-limit-width'.

See `mode-line-position-line-format' for how this number is
presented."
  :init-value t :global t :group 'mode-line)

(define-minor-mode column-number-mode
  "Toggle column number display in the mode line (Column Number mode).

See `mode-line-position-column-format' for how this number is
presented."
  :global t :group 'mode-line)

(define-minor-mode size-indication-mode
  "Toggle buffer size display in the mode line (Size Indication mode)."
  :global t :group 'mode-line)

(defvar-local mode-line-invisible--buf-state)

(define-minor-mode mode-line-invisible-mode
  "Toggle the mode-line visibility of the current buffer.
Hide the mode line if it is shown, and show it if it's hidden."
  :global nil
  :group 'mode-line
  (if mode-line-invisible-mode
      (progn
        (add-hook 'after-change-major-mode-hook #'mode-line-invisible-mode nil t)
        (setq mode-line-invisible--buf-state
              (buffer-local-set-state mode-line-format nil)))

    (remove-hook 'after-change-major-mode-hook #'mode-line-invisible-mode t)

    ;; Restore buffer mode line if buffer had one by default
    (when mode-line-invisible--buf-state
      (setq mode-line-invisible--buf-state
            (buffer-local-restore-state mode-line-invisible--buf-state)))

    ;; Otherwise display one
    (unless mode-line-format
      (setq-local mode-line-format (default-value 'mode-line-format)))

    ;; Update mode line
    (when (called-interactively-p 'any)
      (force-mode-line-update))))

(put 'mode-line-invisible--buf-state 'permanent-local t)
(put 'mode-line-invisible-mode 'permanent-local-hook t)

(defcustom remote-file-name-inhibit-auto-save nil
  "When nil, `auto-save-mode' will auto-save remote files.
Any other value means that it will not."
  :group 'auto-save
  :group 'tramp
  :type 'boolean
  :version "30.1")

(define-minor-mode auto-save-mode
  "Toggle auto-saving in the current buffer (Auto Save mode).

When this mode is enabled, Emacs periodically saves each file-visiting
buffer in a separate \"auto-save file\".  This is a safety measure to
prevent you from losing more than a limited amount of work if the
system crashes.

Auto-saving does not alter the file visited by the buffer: the visited
file is changed only when you request saving it explicitly (such as
with \\[save-buffer]).  If you want to save the buffer into its
visited files automatically, use \\[auto-save-visited-mode]).

For more details, see Info node `(emacs) Auto Save'."
  :variable ((and buffer-auto-save-file-name
                  ;; If auto-save is off because buffer has shrunk,
                  ;; then toggling should turn it on.
                  (>= buffer-saved-size 0))
             . (lambda (val)
                 (setq buffer-auto-save-file-name
                       (cond
                        ((null val) nil)
                        ((and buffer-file-name remote-file-name-inhibit-auto-save
                              (file-remote-p buffer-file-name))
                         nil)
                        ((and buffer-file-name auto-save-visited-file-name
                              (not buffer-read-only))
                         buffer-file-name)
                        (t (make-auto-save-file-name))))))
  ;; If -1 was stored here, to temporarily turn off saving,
  ;; turn it back on.
  (and (< buffer-saved-size 0)
       (setq buffer-saved-size 0)))

(defgroup paren-blinking nil
  "Blinking matching of parens and expressions."
  :prefix "blink-matching-"
  :group 'paren-matching)

(defcustom blink-matching-paren t
  "Non-nil means show matching open-paren when close-paren is inserted.
If this is non-nil, then when you type a closing delimiter, such as a
closing parenthesis or brace, Emacs briefly indicates the location
of the matching opening delimiter.

The valid values are:

  t                 Highlight the matching open-paren if it is visible
                    in the window, otherwise show the text with matching
                    open-paren in the echo area.  This is the default.
  `jump'            If the matching open-paren is visible in the window,
                    briefly move cursor to its position; otherwise show
                    the text with matching open-paren in the echo area.
  `jump-offscreen'  Briefly move cursor to the matching open-paren
                    even if it is not visible in the window.
  nil               Don't show the matching open-paren.

Any other non-nil value is handled the same as t."

  :type '(choice
          (const :tag "Disable" nil)
          (const :tag "Highlight open-paren if visible" t)
          (const :tag "Move cursor to open-paren if visible" jump)
          (const :tag "Move cursor even if it's off screen" jump-offscreen))
  :group 'paren-blinking)

(defcustom blink-matching-paren-on-screen t
  "Non-nil means show matching open-paren when it is on screen.
If nil, don't show it (but the open-paren can still be shown
in the echo area when it is off screen).

This variable has no effect if `blink-matching-paren' is nil.
\(In that case, the open-paren is never shown.)
It is also ignored if `show-paren-mode' is enabled."
  :type 'boolean
  :group 'paren-blinking)

(defcustom blink-matching-paren-distance (* 100 1024)
  "If non-nil, maximum distance to search backwards for matching open-paren.
If nil, search stops at the beginning of the accessible portion of the buffer."
  :version "23.2"                       ; 25->100k
  :type '(choice (const nil) integer)
  :group 'paren-blinking)

(defcustom blink-matching-delay 1
  "Time in seconds to delay after showing a matching paren."
  :type 'number
  :group 'paren-blinking)

(defcustom blink-matching-paren-dont-ignore-comments nil
  "If nil, `blink-matching-paren' ignores comments.
More precisely, when looking for the matching parenthesis,
it skips the contents of comments that end before point."
  :type 'boolean
  :group 'paren-blinking)

(defcustom blink-matching-paren-highlight-offscreen nil
  "If non-nil, highlight matched off-screen open paren in the echo area.
This highlighting uses the `blink-matching-paren-offscreen' face."
  :type 'boolean
  :version "30.1"
  :group 'paren-blinking)

(defface blink-matching-paren-offscreen
  '((t :foreground "green"))
  "Face for showing in the echo area matched open paren that is off-screen.
This face is used only when `blink-matching-paren-highlight-offscreen'
is non-nil."
  :version "30.1"
  :group 'paren-blinking)

(defun blink-matching-check-mismatch (start end)
  "Return whether or not START...END are matching parens.
END is the current point and START is the blink position.
START might be nil if no matching starter was found.
Returns non-nil if we find there is a mismatch."
  (let* ((end-syntax (syntax-after (1- end)))
         (matching-paren (and (consp end-syntax)
                              (eq (syntax-class end-syntax) 5)
                              (cdr end-syntax))))
    ;; For self-matched chars like " and $, we can't know when they're
    ;; mismatched or unmatched, so we can do it only for parens.
    (when matching-paren
      (not (and start
                (or
                 (eq (char-after start) matching-paren)
                 ;; The cdr might hold a new paren-class info rather than
                 ;; a matching-char info, in which case the two CDRs
                 ;; should match.
                 (eq matching-paren (cdr-safe (syntax-after start)))))))))

(defvar blink-matching-check-function #'blink-matching-check-mismatch
  "Function to check parentheses mismatches.
The function takes two arguments (START and END) where START is the
position just before the opening token and END is the position right after.
START can be nil, if it was not found.
The function should return non-nil if the two tokens do not match.")

(defvar blink-matching--overlay
  (let ((ol (make-overlay (point) (point) nil t)))
    (overlay-put ol 'face 'show-paren-match)
    (delete-overlay ol)
    ol)
  "Overlay used to highlight the matching paren.")

(defun blink-matching-open ()
  "Momentarily highlight the beginning of the sexp before point."
  (interactive)
  (when (and (not (bobp))
	     blink-matching-paren)
    (let* ((oldpos (point))
	   (message-log-max nil) ; Don't log messages about paren matching.
	   (blinkpos
            (save-excursion
              (save-restriction
		(syntax-propertize (point))
                (if blink-matching-paren-distance
                    (narrow-to-region
                     (max (minibuffer-prompt-end) ;(point-min) unless minibuf.
                          (- (point) blink-matching-paren-distance))
                     oldpos))
                (let ((parse-sexp-ignore-comments
                       (and parse-sexp-ignore-comments
                            (not blink-matching-paren-dont-ignore-comments))))
                  (condition-case ()
                      (progn
                        (forward-sexp -1)
                        ;; backward-sexp skips backward over prefix chars,
                        ;; so move back to the matching paren.
                        (while (and (< (point) (1- oldpos))
                                    (let ((code (syntax-after (point))))
                                      (or (eq (syntax-class code) 6)
                                          (eq (logand 1048576 (car code))
                                              1048576))))
                          (forward-char 1))
                        (point))
                    (error nil))))))
           (mismatch (funcall blink-matching-check-function blinkpos oldpos)))
      (cond
       (mismatch
        (if blinkpos
            (if (minibufferp)
                (minibuffer-message "Mismatched parentheses")
              (message "Mismatched parentheses"))
          (if (minibufferp)
              (minibuffer-message "No matching parenthesis found")
            (message "No matching parenthesis found"))))
       ((not blinkpos) nil)
       ((or
         (eq blink-matching-paren 'jump-offscreen)
         (pos-visible-in-window-p blinkpos))
        ;; Matching open within window, temporarily move to or highlight
        ;; char after blinkpos but only if `blink-matching-paren-on-screen'
        ;; is non-nil.
        (and blink-matching-paren-on-screen
             (not show-paren-mode)
             (if (memq blink-matching-paren '(jump jump-offscreen))
                 (save-excursion
                   (goto-char blinkpos)
                   (sit-for blink-matching-delay))
               (unwind-protect
                   (progn
                     (move-overlay blink-matching--overlay blinkpos (1+ blinkpos)
                                   (current-buffer))
                     (sit-for blink-matching-delay))
                 (delete-overlay blink-matching--overlay)))))
       ((not show-paren-context-when-offscreen)
        (minibuffer-message
         "%s%s"
         (propertize "Matches " 'face 'shadow)
         (blink-paren-open-paren-line-string blinkpos)))))))

(defun blink-paren-open-paren-line-string (pos)
  "Return the line string that contains the openparen at POS.
Remove the line string's properties but give the openparen a distinct
face if `blink-matching-paren-highlight-offscreen' is non-nil."
  (save-excursion
    (goto-char pos)
    ;; Capture the regions in terms of (beg . end) conses whose
    ;; buffer-substrings we want to show as a context string.  Ensure
    ;; they are font-locked (bug#59527).
    (let (regions
          openparen-idx)
      (cond
       ;; Show what precedes the open in its line, if anything.
       ((save-excursion (skip-chars-backward " \t") (not (bolp)))
        (let ((bol (line-beginning-position)))
          (setq regions (list (cons bol (1+ pos)))
                openparen-idx (- pos bol))))
       ;; Show what follows the open in its line, if anything.
       ((save-excursion
          (forward-char 1)
          (skip-chars-forward " \t")
          (not (eolp)))
        (setq regions (list (cons pos (line-end-position)))
              openparen-idx 0))
       ;; Otherwise show the previous nonblank line,
       ;; if there is one.
       ((save-excursion (skip-chars-backward "\n \t") (not (bobp)))
        (setq regions (list (cons
                             (let (bol)
                               (skip-chars-backward "\n \t")
                               (setq bol (line-beginning-position)
                                     openparen-idx (- bol))
                               bol)
                             (let (eol)
                               (end-of-line)
                               (skip-chars-backward " \t")
                               (setq eol (point)
                                     openparen-idx (+ openparen-idx
                                                      eol
                                                      ;; (length "...")
                                                      3))
                               eol))
                            (cons pos (1+ pos)))))
       ;; There is nothing to show except the char itself.
       (t (setq regions (list (cons pos (1+ pos)))
                openparen-idx 0)))
      ;; Ensure we've font-locked the context region.
      (font-lock-ensure (caar regions) (cdar (last regions)))
      (let ((line-string
             (mapconcat
              (lambda (region)
                (buffer-substring (car region) (cdr region)))
              regions
              "..."))
            (openparen-next-char-idx (1+ openparen-idx)))
        (setq line-string (substring-no-properties line-string))
        (concat
         (substring line-string
                    0 openparen-idx)
         (let ((matched-offscreen-openparen
                (substring line-string
                           openparen-idx openparen-next-char-idx)))
           (if blink-matching-paren-highlight-offscreen
               (propertize matched-offscreen-openparen
                           'face 'blink-matching-paren-offscreen)
             matched-offscreen-openparen))
         (substring line-string
                    openparen-next-char-idx))))))

(defvar blink-paren-function 'blink-matching-open
  "Function called, if non-nil, whenever a close parenthesis is inserted.
More precisely, a char with closeparen syntax is self-inserted.")

(defun blink-paren-post-self-insert-function ()
  (when (and (eq (char-before) last-command-event) ; Sanity check.
             (memq (char-syntax last-command-event) '(?\) ?\$))
             blink-paren-function
             (not executing-kbd-macro)
             (not noninteractive)
	     ;; Verify an even number of quoting characters precede the close.
             ;; FIXME: Also check if this parenthesis closes a comment as
             ;; can happen in Pascal and SML.
	     (oddp (- (point)
		      (save-excursion
			(forward-char -1)
			(skip-syntax-backward "/\\")
			(point)))))
    (funcall blink-paren-function)))

(put 'blink-paren-post-self-insert-function 'priority 100)

(add-hook 'post-self-insert-hook #'blink-paren-post-self-insert-function
          ;; Most likely, this hook is nil, so this arg doesn't matter,
          ;; but I use it as a reminder that this function usually
          ;; likes to be run after others since it does
          ;; `sit-for'. That's also the reason it get a `priority' prop
          ;; of 100.
          'append)

;; This executes C-g typed while Emacs is waiting for a command.
;; Quitting out of a program does not go through here;
;; that happens in the maybe_quit function at the C code level.
(defun keyboard-quit ()
  "Signal a `quit' condition.
During execution of Lisp code, this character causes a quit directly.
At top-level, as an editor command, this simply beeps."
  (interactive)
  ;; Avoid adding the region to the window selection.
  (setq saved-region-selection nil)
  (let (select-active-regions)
    (deactivate-mark))
  (if (fboundp 'kmacro-keyboard-quit)
      (kmacro-keyboard-quit))
  (when completion-in-region-mode
    (completion-in-region-mode -1))
  ;; Force the next redisplay cycle to remove the "Def" indicator from
  ;; all the mode lines.
  (if defining-kbd-macro
      (force-mode-line-update t))
  (setq defining-kbd-macro nil)
  (let ((debug-on-quit nil))
    (signal 'quit nil)))

(defvar buffer-quit-function nil
  "Function to call to \"quit\" the current buffer, or nil if none.
\\[keyboard-escape-quit] calls this function when its more local actions
\(such as canceling a prefix argument, minibuffer or region) do not apply.")

(defun keyboard-escape-quit ()
  "Exit the current \"mode\" (in a generalized sense of the word).
This command can exit an interactive command such as `query-replace',
can clear out a prefix argument or a region,
can get out of the minibuffer or other recursive edit,
cancel the use of the current buffer (for special-purpose buffers),
or go back to just one window (by deleting all but the selected window)."
  (interactive)
  (cond ((eq last-command 'mode-exited) nil)
	((region-active-p)
	 (deactivate-mark))
	((> (minibuffer-depth) 0)
	 (abort-recursive-edit))
	(current-prefix-arg
	 nil)
	((> (recursion-depth) 0)
	 (exit-recursive-edit))
	(buffer-quit-function
	 (funcall buffer-quit-function))
	((not (one-window-p t))
	 (delete-other-windows))
	((string-match "^ \\*" (buffer-name (current-buffer)))
	 (bury-buffer))))

(defun play-sound-file (file &optional volume device)
  "Play sound stored in FILE.
VOLUME and DEVICE correspond to the keywords of the sound
specification for `play-sound'."
  (interactive "fPlay sound file: ")
  (let ((sound (list :file file)))
    (if volume
	(plist-put sound :volume volume))
    (if device
	(plist-put sound :device device))
    (push 'sound sound)
    (play-sound sound)))


(defcustom read-mail-command 'rmail
  "Your preference for a mail reading package.
This is used by some keybindings that support reading mail.
See also `mail-user-agent' concerning sending mail."
  :type '(radio (function-item :tag "Rmail" :format "%t\n" rmail)
                (function-item :tag "Gnus" :format "%t\n" gnus)
                (function-item :tag "Emacs interface to MH"
                               :format "%t\n" mh-rmail)
                (function :tag "Other"))
  :version "21.1"
  :group 'mail)

(defcustom mail-user-agent 'message-user-agent
  "Your preference for a mail composition package.
Various Emacs Lisp packages (e.g. Reporter) require you to compose an
outgoing email message.  This variable lets you specify which
mail-sending package you prefer.

Valid values include:

  `message-user-agent'  -- use the Message package.
                           See Info node `(message)'.
  `sendmail-user-agent' -- use the Mail package.
                           See Info node `(emacs)Sending Mail'.
  `mh-e-user-agent'     -- use the Emacs interface to the MH mail system.
                           See Info node `(mh-e)'.
  `gnus-user-agent'     -- like `message-user-agent', but with Gnus
                           paraphernalia if Gnus is running, particularly
                           the Gcc: header for archiving.

Additional valid symbols may be available; check in the manual of
your mail user agent package for details.  You may also define
your own symbol to be used as value for this variable using
`define-mail-user-agent'.

See also `read-mail-command' concerning reading mail."
  :type '(radio (function-item :tag "Message package"
			       :format "%t\n"
			       message-user-agent)
		(function-item :tag "Mail package"
			       :format "%t\n"
			       sendmail-user-agent)
		(function-item :tag "Emacs interface to MH"
			       :format "%t\n"
			       mh-e-user-agent)
		(function-item :tag "Message with full Gnus features"
			       :format "%t\n"
			       gnus-user-agent)
		(symbol :tag "Other"))
  :version "23.2"                       ; sendmail->message
  :group 'mail)

(defcustom compose-mail-user-agent-warnings t
  "If non-nil, `compose-mail' warns about changes in `mail-user-agent'.
If the value of `mail-user-agent' is the default, and the user
appears to have customizations applying to the old default,
`compose-mail' issues a warning."
  :type 'boolean
  :version "23.2"
  :group 'mail)

(defun rfc822-goto-eoh ()
  "If the buffer starts with a mail header, move point to the header's end.
Otherwise, moves to `point-min'.
The end of the header is the start of the next line, if there is one,
else the end of the last line.  This function obeys RFC 822 (or later)."
  (goto-char (point-min))
  (when (re-search-forward
	 "^\\([:\n]\\|[^: \t\n]+[ \t\n]\\)" nil 'move)
    (goto-char (match-beginning 0))))

;; Used by Rmail (e.g., rmail-forward).
(defvar mail-encode-mml nil
  "If non-nil, mail-user-agent's `sendfunc' command should mml-encode
the outgoing message before sending it.")

(defun compose-mail (&optional to subject other-headers continue
		     switch-function yank-action send-actions
		     return-action)
  "Start composing a mail message to send.
This uses the user's chosen mail composition package
as selected with the variable `mail-user-agent'.
The optional arguments TO and SUBJECT specify recipients
and the initial Subject field, respectively.

OTHER-HEADERS is an alist specifying additional
header fields.  Elements look like (HEADER . VALUE) where both
HEADER and VALUE are strings.

By default, if an unsent message is already being composed, this
command will ask whether to erase the unsent message, and will not
start a new message if the user doesn't allow erasing.  However, if
CONTINUE is non-nil, it means to continue editing a message already
being composed without asking.  Interactively, CONTINUE is the prefix
argument.

SWITCH-FUNCTION, if non-nil, is a function to use to
switch to and display the buffer used for mail composition.

YANK-ACTION, if non-nil, is an action to perform, if and when necessary,
to insert the raw text of the message being replied to.
It has the form (FUNCTION . ARGS).  The user agent will apply
FUNCTION to ARGS, to insert the raw text of the original message.
\(The user agent will also run `mail-citation-hook', *after* the
original text has been inserted in this way.)

SEND-ACTIONS is a list of actions to call when the message is sent.
Each action has the form (FUNCTION . ARGS).

RETURN-ACTION, if non-nil, is an action for returning to the
caller.  It has the form (FUNCTION . ARGS).  The function is
called after the mail has been sent or put aside, and the mail
buffer buried."
  (interactive
   (list nil nil nil current-prefix-arg))

  ;; In Emacs 23.2, the default value of `mail-user-agent' changed
  ;; from sendmail-user-agent to message-user-agent.  Some users may
  ;; encounter incompatibilities.  This hack tries to detect problems
  ;; and warn about them.
  (and compose-mail-user-agent-warnings
       (eq mail-user-agent 'message-user-agent)
       (let (warn-vars)
	 (dolist (var '(mail-mode-hook mail-send-hook mail-setup-hook
			mail-citation-hook mail-archive-file-name
			mail-default-reply-to mail-mailing-lists
			mail-self-blind))
	   (and (boundp var)
		(symbol-value var)
		(push var warn-vars)))
	 (when warn-vars
	   (display-warning 'mail
			    (format-message "\
The default mail mode is now Message mode.
You have the following Mail mode variable%s customized:
\n  %s\n\nTo use Mail mode, set `mail-user-agent' to sendmail-user-agent.
To disable this warning, set `compose-mail-user-agent-warnings' to nil."
				    (if (> (length warn-vars) 1) "s" "")
				    (mapconcat 'symbol-name
					       warn-vars " "))))))

  (let ((function (get mail-user-agent 'composefunc)))
    (unless function
      (error "Invalid value for `mail-user-agent'"))
    (funcall function to subject other-headers continue switch-function
	     yank-action send-actions return-action)))

(defun compose-mail-other-window (&optional to subject other-headers continue
					    yank-action send-actions
					    return-action)
  "Like \\[compose-mail], but edit the outgoing message in another window."
  (interactive (list nil nil nil current-prefix-arg))
  (compose-mail to subject other-headers continue
		'switch-to-buffer-other-window yank-action send-actions
		return-action))

(defun compose-mail-other-frame (&optional to subject other-headers continue
					    yank-action send-actions
					    return-action)
  "Like \\[compose-mail], but edit the outgoing message in another frame."
  (interactive (list nil nil nil current-prefix-arg))
  (compose-mail to subject other-headers continue
		'switch-to-buffer-other-frame yank-action send-actions
		return-action))


(defvar set-variable-value-history nil
  "History of values entered with `set-variable'.

Maximum length of the history list is determined by the value
of `history-length', which see.")

(defun set-variable (variable value &optional make-local)
  "Set VARIABLE to VALUE.  VALUE is a Lisp object.
VARIABLE should be a user option variable name, a Lisp variable
meant to be customized by users.  You should enter VALUE in Lisp syntax,
so if you want VALUE to be a string, you must surround it with doublequotes.
VALUE is used literally, not evaluated.

If VARIABLE has a `variable-interactive' property, that is used as if
it were the arg to `interactive' (which see) to interactively read VALUE.

If VARIABLE has been defined with `defcustom', then the type information
in the definition is used to check that VALUE is valid.

Note that this function is at heart equivalent to the basic `set' function.
For a variable defined with `defcustom', it does not pay attention to
any :set property that the variable might have (if you want that, use
\\[customize-set-variable] instead).

With a prefix argument, set VARIABLE to VALUE buffer-locally.

When called interactively, the user is prompted for VARIABLE and
then VALUE.  The current value of VARIABLE will be put in the
minibuffer history so that it can be accessed with \\`M-n', which
makes it easier to edit it."
  (interactive
   (let* ((default-var (variable-at-point))
          (var (if (custom-variable-p default-var)
		   (read-variable (format-prompt "Set variable" default-var)
				  default-var)
		 (read-variable "Set variable: ")))
	  (minibuffer-help-form `(describe-variable ',var))
	  (prop (get var 'variable-interactive))
          (obsolete (car (get var 'byte-obsolete-variable)))
	  (prompt (format "Set %s %s to value: " var
			  (cond ((local-variable-p var)
				 "(buffer-local)")
				((or current-prefix-arg
				     (local-variable-if-set-p var))
				 "buffer-locally")
				(t "globally"))))
	  (val (progn
                 (when obsolete
                   (message (concat "`%S' is obsolete; "
                                    (if (symbolp obsolete) "use `%S' instead" "%s"))
                            var obsolete)
                   (sit-for 3))
                 (if prop
                     ;; Use VAR's `variable-interactive' property
                     ;; as an interactive spec for prompting.
                     (call-interactively `(lambda (arg)
                                            (interactive ,prop)
                                            arg))
                   (read-from-minibuffer prompt nil
                                         read-expression-map t
                                         'set-variable-value-history
                                         (format "%S" (symbol-value var)))))))
     (list var val current-prefix-arg)))

  (and (custom-variable-p variable)
       (not (get variable 'custom-type))
       (custom-load-symbol variable))
  (let ((type (get variable 'custom-type)))
    (when type
      ;; Match with custom type.
      (require 'cus-edit)
      (setq type (widget-convert type))
      (unless (widget-apply type :match value)
	(user-error "Value `%S' does not match type %S of %S"
		    value (car type) variable))))

  (if make-local
      (make-local-variable variable))

  (set variable value)

  ;; Force a thorough redisplay for the case that the variable
  ;; has an effect on the display, like `tab-width' has.
  (force-mode-line-update))

;; Define the major mode for lists of completions.

(defvar completion-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map "g" nil) ;; There's nothing to revert from.
    (define-key map [mouse-2] 'choose-completion)
    (define-key map [follow-link] 'mouse-face)
    (define-key map [down-mouse-2] nil)
    (define-key map "\C-m" 'choose-completion)
    (define-key map "\e\e\e" 'delete-completion-window)
    (define-key map [remap keyboard-quit] #'delete-completion-window)
    (define-key map [up] 'previous-line-completion)
    (define-key map [down] 'next-line-completion)
    (define-key map [left] 'previous-completion)
    (define-key map [right] 'next-completion)
    (define-key map [?\t] 'next-completion)
    (define-key map [backtab] 'previous-completion)
    (define-key map [M-up] 'minibuffer-previous-completion)
    (define-key map [M-down] 'minibuffer-next-completion)
    (define-key map "\M-\r" 'minibuffer-choose-completion)
    (define-key map "z" 'kill-current-buffer)
    (define-key map "n" 'next-completion)
    (define-key map "p" 'previous-completion)
    (define-key map "\M-g\M-c" 'switch-to-minibuffer)
    map)
  "Local map for completion list buffers.")

;; Completion mode is suitable only for specially formatted data.
(put 'completion-list-mode 'mode-class 'special)

(defvar completion-reference-buffer nil
  "Record the buffer that was current when the completion list was requested.
This is a local variable in the completion list buffer.
Initial value is nil to avoid some compiler warnings.")

(defvar completion-no-auto-exit nil
  "Non-nil means `choose-completion-string' should never exit the minibuffer.
This also applies to other functions such as `choose-completion'.")

(defvar completion-base-position nil
  "Position of the base of the text corresponding to the shown completions.
This variable is used in the *Completions* buffers.
Its value is a list of the form (START END) where START is the place
where the completion should be inserted and END (if non-nil) is the end
of the text to replace.  If END is nil, point is used instead.")

(defvar completion-list-insert-choice-function #'completion--replace
  "Function to use to insert the text chosen in *Completions*.
Called with three arguments (BEG END TEXT), it should replace the text
between BEG and END with TEXT.  Expected to be set buffer-locally
in the *Completions* buffer.")

(defun delete-completion-window ()
  "Delete the completion list window.
Go to the window from which completion was requested."
  (interactive)
  (let ((buf completion-reference-buffer))
    (if (one-window-p t)
	(if (window-dedicated-p) (delete-frame))
      (delete-window (selected-window))
      (if (get-buffer-window buf)
	  (select-window (get-buffer-window buf))))))

(defcustom completion-auto-wrap t
  "Non-nil means to wrap around when selecting completion candidates.
This affects the commands `next-completion', `previous-completion',
`next-line-completion' and `previous-line-completion'.
When `completion-auto-select' is t, it wraps through the minibuffer
for the commands bound to the TAB key."
  :type 'boolean
  :version "29.1"
  :group 'completion)

(defcustom completion-auto-select nil
  "If non-nil, automatically select the window showing the *Completions* buffer.
When the value is t, pressing TAB will switch to the completion list
buffer when Emacs pops up a window showing that buffer.
If the value is `second-tab', then the first TAB will pop up the
window showing the completions list buffer, and the next TAB will
select that window.
See `completion-auto-help' for controlling when the window showing
the completions is popped up and down."
  :type '(choice (const :tag "Don't auto-select completions window" nil)
                 (const :tag "Select completions window on first TAB" t)
                 (const :tag "Select completions window on second TAB"
                        second-tab))
  :version "29.1"
  :group 'completion)

(defun first-completion ()
  "Move to the first item in the completions buffer."
  (interactive)
  (goto-char (point-min))
  (if (get-text-property (point) 'mouse-face)
      (unless (get-text-property (point) 'first-completion)
        (let ((inhibit-read-only t))
          (add-text-properties (point) (min (1+ (point)) (point-max))
                               '(first-completion t))))
    (when-let* ((pos (next-single-property-change (point) 'mouse-face)))
      (goto-char pos))))

(defun last-completion ()
  "Move to the last item in the completions buffer."
  (interactive)
  (goto-char (previous-single-property-change
              (point-max) 'mouse-face nil (point-min)))
  ;; Move to the start of last one.
  (unless (get-text-property (point) 'mouse-face)
    (when-let* ((pos (previous-single-property-change (point) 'mouse-face)))
      (goto-char pos))))

(defun previous-completion (n)
  "Move to the previous item in the completions buffer.
With prefix argument N, move back N items (negative N means move
forward).

Also see the `completion-auto-wrap' variable."
  (interactive "p")
  (next-completion (- n)))

(defun completion--move-to-candidate-start ()
  "If in a completion candidate, move point to its start."
  (when (and (get-text-property (point) 'mouse-face)
             (not (bobp))
             (get-text-property (1- (point)) 'mouse-face))
    (goto-char (previous-single-property-change (point) 'mouse-face))))

(defun completion--move-to-candidate-end ()
  "If in a completion candidate, move point to its end."
  (when (and (get-text-property (point) 'mouse-face)
             (not (eobp))
             (get-text-property (1+ (point)) 'mouse-face))
    (goto-char (or (next-single-property-change (point) 'mouse-face) (point-max)))))

(defun next-completion (n)
  "Move to the next item in the completions buffer.
With prefix argument N, move N items (negative N means move
backward).

Also see the `completion-auto-wrap' variable."
  (interactive "p")
  (let ((tabcommand (member (this-command-keys) '("\t" [backtab])))
        pos)
    (catch 'bound
      (when (and (bobp)
                 (> n 0)
                 (get-text-property (point) 'mouse-face)
                 (not (get-text-property (point) 'first-completion)))
        (let ((inhibit-read-only t))
          (add-text-properties (point) (1+ (point)) '(first-completion t)))
        (setq n (1- n)))

      (while (> n 0)
        (setq pos (point))
        ;; If in a completion, move to the end of it.
        (when (get-text-property pos 'mouse-face)
          (setq pos (next-single-property-change pos 'mouse-face)))
        (when pos (setq pos (next-single-property-change pos 'mouse-face)))
        (if pos
            ;; Move to the start of next one.
            (goto-char pos)
          ;; If at the last completion option, wrap or skip
          ;; to the minibuffer, if requested.
          (when completion-auto-wrap
            (if (and (eq completion-auto-select t) tabcommand
                     (minibufferp completion-reference-buffer))
                (throw 'bound nil)
              (first-completion))))
        (setq n (1- n)))

      (while (< n 0)
        (setq pos (point))
        ;; If in a completion, move to the start of it.
        (when (and (get-text-property pos 'mouse-face)
                   (not (bobp))
                   (get-text-property (1- pos) 'mouse-face))
          (setq pos (previous-single-property-change pos 'mouse-face)))
        (when pos (setq pos (previous-single-property-change pos 'mouse-face)))
        (if pos
            (progn
              (goto-char pos)
              ;; Move to the start of that one.
              (unless (get-text-property (point) 'mouse-face)
                (goto-char (previous-single-property-change
                            (point) 'mouse-face nil (point-min)))))
          ;; If at the first completion option, wrap or skip
          ;; to the minibuffer, if requested.
          (when completion-auto-wrap
            (if (and (eq completion-auto-select t) tabcommand
                     (minibufferp completion-reference-buffer))
                (progn
                  (throw 'bound nil))
              (last-completion))))
        (setq n (1+ n))))

    (when (/= 0 n)
      (switch-to-minibuffer))))

(defun previous-line-completion (&optional n)
  "Move to completion candidate on the previous line in the completions buffer.
With prefix argument N, move back N lines (negative N means move forward).

Also see the `completion-auto-wrap' variable."
  (interactive "p")
  (next-line-completion (- n)))

(defun next-line-completion (&optional n)
  "Move to completion candidate on the next line in the completions buffer.
With prefix argument N, move N lines forward (negative N means move backward).

Also see the `completion-auto-wrap' variable."
  (interactive "p")
  (let (line column pos found)
    (when (and (bobp)
               (> n 0)
               (get-text-property (point) 'mouse-face)
               (not (get-text-property (point) 'first-completion)))
      (let ((inhibit-read-only t))
        (add-text-properties (point) (1+ (point)) '(first-completion t)))
      (setq n (1- n)))

    (if (get-text-property (point) 'mouse-face)
        ;; If in a completion, move to the start of it.
        (completion--move-to-candidate-start)
      ;; Try to move to the previous completion.
      (setq pos (previous-single-property-change (point) 'mouse-face))
      (if pos
          ;; Move to the start of the previous completion.
          (progn
            (goto-char pos)
            (unless (get-text-property (point) 'mouse-face)
              (goto-char (previous-single-property-change
                          (point) 'mouse-face nil (point-min)))))
        (cond ((> n 0) (setq n (1- n)) (first-completion))
              ((< n 0) (first-completion)))))

    (while (> n 0)
      (setq found nil pos nil column (current-column) line (line-number-at-pos))
      (completion--move-to-candidate-end)
      (while (and (not found)
                  (eq (forward-line 1) 0)
                  (not (eobp))
                  (move-to-column column))
        (when (get-text-property (point) 'mouse-face)
          (setq found t)))
      (when (not found)
        (if (not completion-auto-wrap)
            (last-completion)
          (save-excursion
            (goto-char (point-min))
            (when (and (eq (move-to-column column) column)
                       (get-text-property (point) 'mouse-face))
              (setq pos (point)))
            (while (and (not pos) (> line (line-number-at-pos)))
              (forward-line 1)
              (when (and (eq (move-to-column column) column)
                         (get-text-property (point) 'mouse-face))
                (setq pos (point)))))
          (if pos (goto-char pos))))
      (setq n (1- n)))

    (while (< n 0)
      (setq found nil pos nil column (current-column) line (line-number-at-pos))
      (completion--move-to-candidate-start)
      (while (and (not found)
                  (eq (forward-line -1) 0)
                  (move-to-column column))
        (when (get-text-property (point) 'mouse-face)
          (setq found t)))
      (when (not found)
        (if (not completion-auto-wrap)
            (first-completion)
          (save-excursion
            (goto-char (point-max))
            (when (and (eq (move-to-column column) column)
                       (get-text-property (point) 'mouse-face))
              (setq pos (point)))
            (while (and (not pos) (< line (line-number-at-pos)))
              (forward-line -1)
              (when (and (eq (move-to-column column) column)
                         (get-text-property (point) 'mouse-face))
                (setq pos (point)))))
          (if pos (goto-char pos))))
      (setq n (1+ n)))))

(defvar choose-completion-deselect-if-after nil
  "If non-nil, don't choose a completion candidate if point is right after it.

This makes `completions--deselect' effective.")

(defun completion-list-candidate-at-point (&optional pt)
  "Candidate string and bounds at PT in completions buffer.
The return value has the format (STR BEG END).
The optional argument PT defaults to (point)."
  (setq pt (or pt (point)))
  (when (cond
         ((and (/= pt (point-max))
               (get-text-property pt 'completion--string))
          (incf pt))
         ((and (/= pt (point-min))
               (get-text-property (1- pt) 'completion--string))))
    (setq pt (or (previous-single-property-change pt 'completion--string) pt))
    (list (get-text-property pt 'completion--string) pt
          (or (next-single-property-change pt 'completion--string)
              (point-max)))))

(defun choose-completion (&optional event no-exit no-quit)
  "Choose the completion at point.
If EVENT, use EVENT's position to determine the starting position.
With prefix argument NO-EXIT, insert the completion at point to the
minibuffer, but don't exit the minibuffer.  When the prefix argument
is not provided, then whether to exit the minibuffer depends on the value
of `completion-no-auto-exit'.
If NO-QUIT is non-nil, insert the completion at point to the
minibuffer, but don't quit the completions window."
  (interactive (list last-nonmenu-event current-prefix-arg))
  ;; In case this is run via the mouse, give temporary modes such as
  ;; isearch a chance to turn off.
  (run-hooks 'mouse-leave-buffer-hook)
  (with-current-buffer (window-buffer (posn-window (event-start event)))
    (let ((buffer completion-reference-buffer)
          (base-position completion-base-position)
          (insert-function completion-list-insert-choice-function)
          (completion-no-auto-exit (if no-exit t completion-no-auto-exit))
          (choice
           (if choose-completion-deselect-if-after
               (or (get-text-property (posn-point (event-start event))
                                      'completion--string)
                   (error "No completion here"))
             (or (car (completion-list-candidate-at-point
                       (posn-point (event-start event))))
                 (error "No completion here")))))

      (unless (buffer-live-p buffer)
        (error "Destination buffer is dead"))
      (unless no-quit
        (quit-window nil (posn-window (event-start event))))

      (with-current-buffer buffer
        (choose-completion-string
         choice buffer
         (or base-position
             ;; If all else fails, just guess.
             (list (choose-completion-guess-base-position choice)))
         insert-function)))))

;; Delete the longest partial match for STRING
;; that can be found before POINT.
(defun choose-completion-guess-base-position (string)
  (save-excursion
    (let ((opoint (point))
          len)
      ;; Try moving back by the length of the string.
      (goto-char (max (- (point) (length string))
                      (minibuffer-prompt-end)))
      ;; See how far back we were actually able to move.  That is the
      ;; upper bound on how much we can match and delete.
      (setq len (- opoint (point)))
      (if completion-ignore-case
          (setq string (downcase string)))
      (while (and (> len 0)
                  (let ((tail (buffer-substring (point) opoint)))
                    (if completion-ignore-case
                        (setq tail (downcase tail)))
                    (not (string= tail (substring string 0 len)))))
        (setq len (1- len))
        (forward-char 1))
      (point))))

(defvar choose-completion-string-functions nil
  "Functions that may override the normal insertion of a completion choice.
These functions are called in order with three arguments:
CHOICE - the string to insert in the buffer,
BUFFER - the buffer in which the choice should be inserted,
BASE-POSITION - where to insert the completion.

Functions should also accept and ignore a potential fourth
argument, passed for backwards compatibility.

If a function in the list returns non-nil, that function is supposed
to have inserted the CHOICE in the BUFFER, and possibly exited
the minibuffer; no further functions will be called.

If all functions in the list return nil, that means to use
the default method of inserting the completion in BUFFER.")

(defun choose-completion-string (choice &optional
                                        buffer base-position insert-function)
  "Switch to BUFFER and insert the completion choice CHOICE.
BASE-POSITION says where to insert the completion.
INSERT-FUNCTION says how to insert the completion and falls
back on `completion-list-insert-choice-function' when nil."

  ;; If BUFFER is the minibuffer, exit the minibuffer
  ;; unless it is reading a file name and CHOICE is a directory,
  ;; or completion-no-auto-exit is non-nil.

  (let* ((buffer (or buffer completion-reference-buffer))
	 (mini-p (minibufferp buffer)))
    ;; If BUFFER is a minibuffer, barf unless it's the currently
    ;; active minibuffer.
    (if (and mini-p
             (not (and (active-minibuffer-window)
                       (equal buffer
			     (window-buffer (active-minibuffer-window))))))
	(error "Minibuffer is not active for completion")
      ;; Set buffer so buffer-local choose-completion-string-functions works.
      (set-buffer buffer)
      (unless (run-hook-with-args-until-success
	       'choose-completion-string-functions
               ;; The fourth arg used to be `mini-p' but was useless
               ;; (since minibufferp can be used on the `buffer' arg)
               ;; and indeed unused.  The last used to be `base-size', so we
               ;; keep it to try and avoid breaking old code.
	       choice buffer base-position nil)
        ;; This remove-text-properties should be unnecessary since `choice'
        ;; comes from buffer-substring-no-properties.
        ;;(remove-text-properties 0 (length choice) '(mouse-face nil) choice)
	;; Insert the completion into the buffer where it was requested.
        (funcall (or insert-function completion-list-insert-choice-function)
                 (or (car base-position) (point))
                 (or (cadr base-position) (point))
                 choice)
        ;; Update point in the window that BUFFER is showing in.
	(let ((window (get-buffer-window buffer t)))
	  (set-window-point window (point)))
	;; If completing for the minibuffer, exit it with this choice.
	(and (not completion-no-auto-exit)
             (minibufferp buffer)
	     minibuffer-completion-table
	     ;; If this is reading a file name, and the file name chosen
	     ;; is a directory, don't exit the minibuffer.
             (let* ((result (buffer-substring (field-beginning) (point)))
                    (bounds
                     (completion-boundaries result minibuffer-completion-table
                                            minibuffer-completion-predicate
                                            "")))
               (if (eq (car bounds) (length result))
                   ;; The completion chosen leads to a new set of completions
                   ;; (e.g. it's a directory): don't exit the minibuffer yet.
                   (let ((mini (active-minibuffer-window)))
                     (select-window mini)
                     (when minibuffer-auto-raise
                       (raise-frame (window-frame mini))))
                 (exit-minibuffer))))))))

(define-derived-mode completion-list-mode nil "Completion List"
  "Major mode for buffers showing lists of possible completions.
Type \\<completion-list-mode-map>\\[choose-completion] in the completion list\
 to select the completion near point.
Or click to select one with the mouse.

See the `completions-format' user option to control how this
buffer is formatted.

\\{completion-list-mode-map}")

(defun completion-list-mode-finish ()
  "Finish setup of the completions buffer.
Called from `temp-buffer-show-hook'."
  (when (eq major-mode 'completion-list-mode)
    (setq buffer-read-only t)))

(add-hook 'temp-buffer-show-hook 'completion-list-mode-finish)


;; Variables and faces used in `completion-setup-function'.

(defcustom completion-show-help t
  "Non-nil means show help message in *Completions* buffer."
  :type 'boolean
  :version "22.1"
  :group 'completion)

(defvar minibuffer-visible-completions--always-bind)

;; This function goes in completion-setup-hook, so that it is called
;; after the text of the completion list buffer is written.
(defun completion-setup-function ()
  (let* ((mainbuf (current-buffer))
         (base-dir
          ;; FIXME: This is a bad hack.  We try to set the default-directory
          ;; in the *Completions* buffer so that the relative file names
          ;; displayed there can be treated as valid file names, independently
          ;; from the completion context.  But this suffers from many problems:
          ;; - It's not clear when the completions are file names.  With some
          ;;   completion tables (e.g. bzr revision specs), the listed
          ;;   completions can mix file names and other things.
          ;; - It doesn't pay attention to possible quoting.
          ;; - With fancy completion styles, the code below will not always
          ;;   find the right base directory.
          (if minibuffer-completing-file-name
              (file-name-directory
               (expand-file-name
                (buffer-substring (minibuffer-prompt-end) (point)))))))
    (with-current-buffer standard-output
      (let ((base-position completion-base-position)
            (insert-fun completion-list-insert-choice-function)
            (lazy-button completions--lazy-insert-button))
        (completion-list-mode)
        (when completions-highlight-face
          (setq-local cursor-face-highlight-nonselected-window t))
        (setq-local completions--lazy-insert-button lazy-button)
        (setq-local completion-base-position base-position)
        (setq-local completion-list-insert-choice-function insert-fun))
      (setq-local completion-reference-buffer mainbuf)
      (if base-dir (setq default-directory base-dir))
      (when completion-tab-width
        (setq tab-width completion-tab-width))
      ;; Maybe enable cursor completions-highlight.
      (when completions-highlight-face
        (cursor-face-highlight-mode 1))
      ;; Maybe insert help string.
      (when completion-show-help
	(goto-char (point-min))
        (if minibuffer-visible-completions
            (let ((helps
                   (with-current-buffer (window-buffer (active-minibuffer-window))
                     (let ((minibuffer-visible-completions--always-bind t))
                       (list
                        (substitute-command-keys
	                 (if (display-mouse-p)
	                     "Click or type \\[minibuffer-choose-completion-or-exit] on a completion to select it.\n"
                           "Type \\[minibuffer-choose-completion-or-exit] on a completion to select it.\n"))
                        (substitute-command-keys
		         "Type \\[minibuffer-next-completion], \\[minibuffer-previous-completion], \
\\[minibuffer-next-line-completion], \\[minibuffer-previous-line-completion] \
to move point between completions.\n\n"))))))
              (dolist (help helps)
                (insert help)))
          (insert (substitute-command-keys
	           (if (display-mouse-p)
	               "Click or type \\[minibuffer-choose-completion] on a completion to select it.\n"
                     "Type \\[minibuffer-choose-completion] on a completion to select it.\n")))
          (insert (substitute-command-keys
		   "Type \\[minibuffer-next-completion] or \\[minibuffer-previous-completion] \
to move point between completions.\n\n")))))))

(add-hook 'completion-setup-hook #'completion-setup-function)

(defun switch-to-completions ()
  "Select the completion list window."
  (interactive)
  (when-let* ((window (or (get-buffer-window "*Completions*" 0)
		          ;; Make sure we have a completions window.
                          (progn (minibuffer-completion-help)
                                 (get-buffer-window "*Completions*" 0)))))
    (select-window window)
    (completion--lazy-insert-strings)
    (when (bobp)
      (cond
       ((and (memq this-command '(completion-at-point minibuffer-complete))
             (equal (this-command-keys) [backtab]))
        (goto-char (point-max))
        (last-completion))
       (t (first-completion))))))

(defun read-expression-switch-to-completions ()
  "Select the completion list window while reading an expression."
  (interactive)
  (completion-help-at-point)
  (switch-to-completions))

(defun switch-to-minibuffer ()
  "Select the minibuffer window."
  (interactive)
  (when (active-minibuffer-window)
    (select-window (active-minibuffer-window))))

;;; Support keyboard commands to turn on various modifiers.

;; These functions -- which are not commands -- each add one modifier
;; to the following event.

(defun event-apply-alt-modifier (_ignore-prompt)
  "\\<function-key-map>Add the Alt modifier to the following event.
For example, type \\[event-apply-alt-modifier] & to enter Alt-&."
  (vector (event-apply-modifier (read-event) 'alt 22 "A-")))
(defun event-apply-super-modifier (_ignore-prompt)
  "\\<function-key-map>Add the Super modifier to the following event.
For example, type \\[event-apply-super-modifier] & to enter Super-&."
  (vector (event-apply-modifier (read-event) 'super 23 "s-")))
(defun event-apply-hyper-modifier (_ignore-prompt)
  "\\<function-key-map>Add the Hyper modifier to the following event.
For example, type \\[event-apply-hyper-modifier] & to enter Hyper-&."
  (vector (event-apply-modifier (read-event) 'hyper 24 "H-")))
(defun event-apply-shift-modifier (_ignore-prompt)
  "\\<function-key-map>Add the Shift modifier to the following event.
For example, type \\[event-apply-shift-modifier] & to enter Shift-&."
  (vector (event-apply-modifier (read-event) 'shift 25 "S-")))
(defun event-apply-control-modifier (_ignore-prompt)
  "\\<function-key-map>Add the Ctrl modifier to the following event.
For example, type \\[event-apply-control-modifier] & to enter Ctrl-&."
  (vector (event-apply-modifier (read-event) 'control 26 "C-")))
(defun event-apply-meta-modifier (_ignore-prompt)
  "\\<function-key-map>Add the Meta modifier to the following event.
For example, type \\[event-apply-meta-modifier] & to enter Meta-&."
  (vector (event-apply-modifier (read-event) 'meta 27 "M-")))

(defun event-apply-modifier (event symbol lshiftby prefix)
  "Apply a modifier flag to event EVENT.
SYMBOL is the name of this modifier, as a symbol.
LSHIFTBY is the numeric value of this modifier, in keyboard events.
PREFIX is the string that represents this modifier in an event type symbol."
  (if (numberp event)
      ;; Use the base event to determine how the control and shift
      ;; modifiers should be applied.
      (let* ((base-event (event-basic-type event)))
        (cond ((eq symbol 'control)
	       (if (<= 64 (upcase base-event) 95)
                   ;; Apply the control modifier...
		   (logior (- (upcase base-event) 64)
                           ;; ... and any additional modifiers
                           ;; specified in the original event...
                           (logand event (logior ?\M-\0 ?\C-\0 ?\S-\0
					         ?\H-\0 ?\s-\0 ?\A-\0))
                           ;; ... including any shift modifier that
                           ;; `event-basic-type' may have removed.
                           (if (<= ?A event ?Z) ?\S-\0 0))
	         (logior (ash 1 lshiftby) event)))
	      ((eq symbol 'shift)
               ;; FIXME: Should we also apply this "upcase" behavior of shift
               ;; to non-ascii letters?
	       (if (<= ?a base-event ?z)
                   ;; Apply the Shift modifier.
		   (logior (upcase base-event)
                           ;; ... and any additional modifiers
                           ;; specified in the original event.
                           (logand event (logior ?\M-\0 ?\C-\0 ?\S-\0
					         ?\H-\0 ?\s-\0 ?\A-\0)))
	         (logior (ash 1 lshiftby) event)))
	      (t
	       (logior (ash 1 lshiftby) event))))
    (if (memq symbol (event-modifiers event))
	event
      (let ((event-type (if (symbolp event) event (car event))))
	(setq event-type (intern (concat prefix (symbol-name event-type))))
	(if (symbolp event)
	    event-type
	  (cons event-type (cdr event)))))))

;; This is what makes "C-x @" followed by [hsmaSc] work even though
;; you won't find any (define-key ctl-x-map "@" ...) binding.
(define-key function-key-map [?\C-x ?@ ?h] 'event-apply-hyper-modifier)
(define-key function-key-map [?\C-x ?@ ?s] 'event-apply-super-modifier)
(define-key function-key-map [?\C-x ?@ ?m] 'event-apply-meta-modifier)
(define-key function-key-map [?\C-x ?@ ?a] 'event-apply-alt-modifier)
(define-key function-key-map [?\C-x ?@ ?S] 'event-apply-shift-modifier)
(define-key function-key-map [?\C-x ?@ ?c] 'event-apply-control-modifier)

;;;; Keypad support.

;; Make the keypad keys act like ordinary typing keys.  If people add
;; bindings for the function key symbols, then those bindings will
;; override these, so this shouldn't interfere with any existing
;; bindings.

;; Also tell read-char how to handle these keys.
(mapc
 (lambda (keypad-normal)
   (let ((keypad (nth 0 keypad-normal))
	 (normal (nth 1 keypad-normal)))
     (put keypad 'ascii-character normal)
     (define-key function-key-map (vector keypad) (vector normal))))
 ;; See also kp-keys bound in bindings.el.
 '((kp-space ?\s)
   (kp-tab ?\t)
   (kp-enter ?\r)
   (kp-separator ?,)
   (kp-equal ?=)
   ;; Do the same for various keys that are represented as symbols under
   ;; GUIs but naturally correspond to characters.
   (backspace 127)
   (delete 127)
   (tab ?\t)
   (linefeed ?\n)
   (clear ?\C-l)
   (return ?\C-m)
   (escape ?\e)
   ))

;;;;
;;;; forking a twin copy of a buffer.
;;;;

(defvar clone-buffer-hook nil
  "Normal hook to run in the new buffer at the end of `clone-buffer'.")

(defun clone-process (process &optional newname)
  "Create a twin copy of PROCESS.
If NEWNAME is nil, it defaults to PROCESS' name;
NEWNAME is modified by adding or incrementing <N> at the end as necessary.
If PROCESS is associated with a buffer, the new process will be associated
  with the current buffer instead.
Returns nil if PROCESS has already terminated."
  (setq newname (or newname (process-name process)))
  (if (string-match "<[0-9]+>\\'" newname)
      (setq newname (substring newname 0 (match-beginning 0))))
  (when (memq (process-status process) '(run stop open))
    (let* ((process-connection-type (process-tty-name process))
	   (new-process
	    (if (memq (process-status process) '(open))
		(let ((args (process-contact process t)))
		  (setq args (plist-put args :name newname))
		  (setq args (plist-put args :buffer
					(if (process-buffer process)
					    (current-buffer))))
		  (apply 'make-network-process args))
	      (apply 'start-process newname
		     (if (process-buffer process) (current-buffer))
		     (process-command process)))))
      (set-process-query-on-exit-flag
       new-process (process-query-on-exit-flag process))
      (set-process-inherit-coding-system-flag
       new-process (process-inherit-coding-system-flag process))
      (set-process-filter new-process (process-filter process))
      (set-process-sentinel new-process (process-sentinel process))
      (set-process-plist new-process (copy-sequence (process-plist process)))
      new-process)))

;; things to maybe add (currently partly covered by `funcall mode'):
;; - syntax-table
;; - overlays
(defun clone-buffer (&optional newname display-flag)
  "Create and return a twin copy of the current buffer.
Unlike an indirect buffer, the new buffer can be edited
independently of the old one (if it is not read-only).
NEWNAME is the name of the new buffer.  It may be modified by
adding or incrementing <N> at the end as necessary to create a
unique buffer name.  If nil, it defaults to the name of the
current buffer, with the proper suffix.  If DISPLAY-FLAG is
non-nil, the new buffer is shown with `pop-to-buffer'.  Trying to
clone a file-visiting buffer, or a buffer whose major mode symbol
has a non-nil `no-clone' property, results in an error.

Interactively, DISPLAY-FLAG is t and NEWNAME is the name of the
current buffer with appropriate suffix.  However, if a prefix
argument is given, then the command prompts for NEWNAME in the
minibuffer.

This runs the normal hook `clone-buffer-hook' in the new buffer
after it has been set up properly in other respects."
  (interactive
   (progn
     (if buffer-file-name
	 (error "Cannot clone a file-visiting buffer"))
     (if (get major-mode 'no-clone)
	 (error "Cannot clone a buffer in %s mode" mode-name))
     (list (if current-prefix-arg
	       (read-buffer "Name of new cloned buffer: " (current-buffer)))
	   t)))
  (if buffer-file-name
      (error "Cannot clone a file-visiting buffer"))
  (if (get major-mode 'no-clone)
      (error "Cannot clone a buffer in %s mode" mode-name))
  (setq newname (or newname (buffer-name)))
  (if (string-match "<[0-9]+>\\'" newname)
      (setq newname (substring newname 0 (match-beginning 0))))
  (let ((buf (current-buffer))
	(ptmin (point-min))
	(ptmax (point-max))
	(pt (point))
	(mk (if mark-active (mark t)))
	(modified (buffer-modified-p))
	(mode major-mode)
	(lvars (buffer-local-variables))
	(process (get-buffer-process (current-buffer)))
	(new (generate-new-buffer (or newname (buffer-name)))))
    (save-restriction
      (widen)
      (with-current-buffer new
	(insert-buffer-substring buf)))
    (with-current-buffer new
      (narrow-to-region ptmin ptmax)
      (goto-char pt)
      (if mk (set-mark mk))
      (set-buffer-modified-p modified)

      ;; Clone the old buffer's process, if any.
      (when process (clone-process process))

      ;; Now set up the major mode.
      (funcall mode)

      ;; Set up other local variables.
      (mapc (lambda (v)
	      (condition-case ()
		  (if (symbolp v)
		      (makunbound (make-local-variable v))
		    (set (make-local-variable (car v)) (cdr v)))
		(setting-constant nil))) ;E.g. for enable-multibyte-characters.
	    lvars)

      (setq mark-ring (mapcar (lambda (mk) (copy-marker (marker-position mk)))
                              mark-ring))

      ;; Run any hooks (typically set up by the major mode
      ;; for cloning to work properly).
      (run-hooks 'clone-buffer-hook))
    (if display-flag
        ;; Presumably the current buffer is shown in the selected frame, so
        ;; we want to display the clone elsewhere.
        (let ((same-window-regexps nil)
              (same-window-buffer-names))
          (pop-to-buffer new)))
    new))


(defun clone-indirect-buffer (newname display-flag &optional norecord)
  "Create an indirect buffer that is a twin copy of the current buffer.

Give the indirect buffer name NEWNAME.  Interactively, read NEWNAME
from the minibuffer when invoked with a prefix arg.  If NEWNAME is nil
or if not called with a prefix arg, NEWNAME defaults to the current
buffer's name.  The name is modified by adding a `<N>' suffix to it
or by incrementing the N in an existing suffix.  Trying to clone a
buffer whose major mode symbol has a non-nil `no-clone-indirect'
property results in an error.

DISPLAY-FLAG non-nil means show the new buffer with `pop-to-buffer'.
This is always done when called interactively.

Optional third arg NORECORD non-nil means do not put this buffer at the
front of the list of recently selected ones.

Returns the newly created indirect buffer."
  (interactive
   (progn
     (if (get major-mode 'no-clone-indirect)
	 (error "Cannot indirectly clone a buffer in %s mode" mode-name))
     (list (if current-prefix-arg
	       (read-buffer "Name of indirect buffer: " (current-buffer)))
	   t)))
  (if (get major-mode 'no-clone-indirect)
      (error "Cannot indirectly clone a buffer in %s mode" mode-name))
  (setq newname (or newname (buffer-name)))
  (if (string-match "<[0-9]+>\\'" newname)
      (setq newname (substring newname 0 (match-beginning 0))))
  (let* ((name (generate-new-buffer-name newname))
	 (buffer (make-indirect-buffer (current-buffer) name t)))
    (when display-flag
      (pop-to-buffer buffer nil norecord))
    buffer))


(defun clone-indirect-buffer-other-window (newname display-flag &optional norecord)
  "Like `clone-indirect-buffer' but display in another window."
  (interactive
   (progn
     (if (get major-mode 'no-clone-indirect)
	 (error "Cannot indirectly clone a buffer in %s mode" mode-name))
     (list (if current-prefix-arg
	       (read-buffer "Name of indirect buffer: " (current-buffer)))
	   t)))
  ;; For compatibility, don't display the buffer if display-flag is nil.
  (let ((buffer (clone-indirect-buffer newname nil norecord)))
    (when display-flag
      (switch-to-buffer-other-window buffer norecord))))


;;; Handling of Backspace and Delete keys.

(defcustom normal-erase-is-backspace 'maybe
  "Set the default behavior of the Delete and Backspace keys.

If set to t, Delete key deletes forward and Backspace key deletes
backward.

If set to nil, both Delete and Backspace keys delete backward.

If set to `maybe' (which is the default), Emacs automatically
selects a behavior.  On window systems, the behavior depends on
the keyboard used.  If the keyboard has both a Backspace key and
a Delete key, and both are mapped to their usual meanings, the
option's default value is set to t, so that Backspace can be used
to delete backward, and Delete can be used to delete forward.

If not running under a window system, customizing this option
accomplishes a similar effect by mapping \\`C-h', which is usually
generated by the Backspace key, to \\`DEL', and by mapping \\`DEL' to
\\`C-d' via `keyboard-translate'.  The former functionality of \\`C-h'
is available on the F1 key.  You should probably not use this
setting if you don't have both Backspace, Delete and F1 keys.

Setting this variable with setq doesn't take effect.  Programmatically,
call `normal-erase-is-backspace-mode' (which see) instead."
  :type '(choice (const :tag "Off" nil)
		 (const :tag "Maybe" maybe)
		 (other :tag "On" t))
  :group 'editing-basics
  :version "21.1"
  :set (lambda (symbol value)
	 ;; The fboundp is because of a problem with :set when
	 ;; dumping Emacs.  It doesn't really matter.
	 (when (fboundp 'normal-erase-is-backspace-mode)
	   (normal-erase-is-backspace-mode (or value 0)))
	 (set-default symbol value)))

(defun normal-erase-is-backspace-setup-frame (&optional frame)
  "Set up `normal-erase-is-backspace-mode' on FRAME, if necessary."
  (unless frame (setq frame (selected-frame)))
  (with-selected-frame frame
    (unless (terminal-parameter nil 'normal-erase-is-backspace)
      (normal-erase-is-backspace-mode
       (if (if (eq normal-erase-is-backspace 'maybe)
               (and (not noninteractive)
                    (or (memq system-type '(ms-dos windows-nt))
			(memq window-system '(w32 ns pgtk haiku android))
                        (and (eq window-system 'x)
                             (fboundp 'x-backspace-delete-keys-p)
                             (x-backspace-delete-keys-p))
                        ;; If the terminal Emacs is running on has erase char
                        ;; set to ^H, use the Backspace key for deleting
                        ;; backward, and the Delete key for deleting forward.
                        (and (null window-system)
                             (eq tty-erase-char ?\^H))))
             normal-erase-is-backspace)
           1 0)))))

(declare-function display-symbol-keys-p "frame" (&optional display))

(define-minor-mode normal-erase-is-backspace-mode
  "Toggle the Erase and Delete mode of the Backspace and Delete keys.

On window systems, when this mode is on, Delete is mapped to \\`C-d'
and Backspace is mapped to \\`DEL'; when this mode is off, both
Delete and Backspace are mapped to \\`DEL'.  (The remapping goes via
`local-function-key-map', so binding Delete or Backspace in the
global or local keymap will override that.)

In addition, on window systems, the bindings of C-Delete, M-Delete,
C-M-Delete, C-Backspace, M-Backspace, and C-M-Backspace are changed in
the global keymap in accordance with the functionality of Delete and
Backspace.  For example, if Delete is remapped to \\`C-d', which deletes
forward, C-Delete is bound to `kill-word', but if Delete is remapped
to \\`DEL', which deletes backward, C-Delete is bound to
`backward-kill-word'.

If not running on a window system, a similar effect is accomplished by
remapping \\`C-h' (normally produced by the Backspace key) and \\`DEL'
via `keyboard-translate': if this mode is on, \\`C-h' is mapped to
\\`DEL' and \\`DEL' to \\`C-d'; if it's off, the keys are not remapped.

When not running on a window system, and this mode is turned on, the
former functionality of \\`C-h' is available on the F1 key.  You should
probably not turn on this mode on a text-only terminal if you don't
have both Backspace, Delete and F1 keys.

See also `normal-erase-is-backspace'."
  :variable ((eq (terminal-parameter nil 'normal-erase-is-backspace) 1)
             . (lambda (v)
                 (setf (terminal-parameter nil 'normal-erase-is-backspace)
                       (if v 1 0))))
  (let ((enabled (eq 1 (terminal-parameter
                        nil 'normal-erase-is-backspace))))

    (cond ((display-symbol-keys-p)
	   (let ((bindings
		  '(([M-delete] [M-backspace])
		    ([C-M-delete] [C-M-backspace])
		    ([?\e C-delete] [?\e C-backspace]))))

	     (if enabled
		 (progn
		   (define-key local-function-key-map [delete] [deletechar])
		   (define-key local-function-key-map [kp-delete] [deletechar])
		   (define-key local-function-key-map [backspace] [?\C-?])
                   (dolist (b bindings)
                     ;; Not sure if input-decode-map is really right, but
                     ;; keyboard-translate-table (used below) works only
                     ;; for integer events, and key-translation-table is
                     ;; global (like the global-map, used earlier).
                     (define-key input-decode-map (car b) nil)
                     (define-key input-decode-map (cadr b) nil)))
	       (define-key local-function-key-map [delete] [?\C-?])
	       (define-key local-function-key-map [kp-delete] [?\C-?])
	       (define-key local-function-key-map [backspace] [?\C-?])
               (dolist (b bindings)
                 (define-key input-decode-map (car b) (cadr b))
                 (define-key input-decode-map (cadr b) (car b))))))
	  (t
	   (if enabled
	       (progn
                 (key-translate "C-h" "DEL")
                 (key-translate "DEL" "C-d"))
             (key-translate "C-h" "C-h")
             (key-translate "DEL" "DEL"))))

    (if (called-interactively-p 'interactive)
	(message "Delete key deletes %s"
		 (if (eq 1 (terminal-parameter nil 'normal-erase-is-backspace))
		     "forward" "backward")))))

(defvar vis-mode-saved-buffer-invisibility-spec nil
  "Saved value of `buffer-invisibility-spec' when Visible mode is on.")

(define-minor-mode read-only-mode
  "Change whether the current buffer is read-only.

If buffer is read-only and `view-read-only' is non-nil, enter
view mode.

Do not call this from a Lisp program unless you really intend to
do the same thing as the \\[read-only-mode] command, including
possibly enabling or disabling View mode.  Also, note that this
command works by setting the variable `buffer-read-only', which
does not affect read-only regions caused by text properties.  To
ignore read-only status in a Lisp program (whether due to text
properties or buffer state), bind `inhibit-read-only' temporarily
to a non-nil value.

Reverting a buffer will keep the read-only status set by using
this command."
  :variable buffer-read-only
  ;; We're saving this value here so that we can restore the
  ;; readedness state after reverting the buffer to the value that's
  ;; been explicitly set by the user.
  (setq-local read-only-mode--state buffer-read-only)
  (cond
   ((and (not buffer-read-only) view-mode)
    (View-exit-and-edit)
    (setq-local view-read-only t))		; Must leave view mode.
   ((and buffer-read-only view-read-only
         ;; If view-mode is already active, `view-mode-enter' is a nop.
         (not view-mode)
         (not (eq (get major-mode 'mode-class) 'special)))
    (view-mode-enter))))

(define-minor-mode visible-mode
  "Toggle making all invisible text temporarily visible (Visible mode).

This mode works by saving the value of `buffer-invisibility-spec'
and setting it to nil."
  :lighter " Vis"
  :group 'editing-basics
  (when (local-variable-p 'vis-mode-saved-buffer-invisibility-spec)
    (setq buffer-invisibility-spec vis-mode-saved-buffer-invisibility-spec)
    (kill-local-variable 'vis-mode-saved-buffer-invisibility-spec))
  (when visible-mode
    (setq-local vis-mode-saved-buffer-invisibility-spec
                buffer-invisibility-spec)
    (setq buffer-invisibility-spec nil)))


(defvar-keymap messages-buffer-mode-map
  :parent special-mode-map
  "g" nil) ; nothing to revert

(define-derived-mode messages-buffer-mode special-mode "Messages"
  "Major mode used in the \"*Messages*\" buffer."
  ;; Make it easy to do like "tail -f".
  (setq-local window-point-insertion-type t))

(defun messages-buffer ()
  "Return the \"*Messages*\" buffer.
If it does not exist, create it and switch it to `messages-buffer-mode'."
  (or (get-buffer "*Messages*")
      (with-current-buffer (get-buffer-create "*Messages*")
        (messages-buffer-mode)
        (current-buffer))))


;; Minibuffer prompt stuff.

;;(defun minibuffer-prompt-modification (start end)
;;  (error "You cannot modify the prompt"))
;;
;;
;;(defun minibuffer-prompt-insertion (start end)
;;  (let ((inhibit-modification-hooks t))
;;    (delete-region start end)
;;    ;; Discard undo information for the text insertion itself
;;    ;; and for the text deletion.above.
;;    (when (consp buffer-undo-list)
;;      (setq buffer-undo-list (cddr buffer-undo-list)))
;;    (message "You cannot modify the prompt")))
;;
;;
;;(setq minibuffer-prompt-properties
;;  (list 'modification-hooks '(minibuffer-prompt-modification)
;;	'insert-in-front-hooks '(minibuffer-prompt-insertion)))


;;;; Problematic external packages.

;; rms says this should be done by specifying symbols that define
;; versions together with bad values.  This is therefore not as
;; flexible as it could be.  See the thread:
;; https://lists.gnu.org/r/emacs-devel/2007-08/msg00300.html
(defconst bad-packages-alist nil
  "Alist of packages known to cause problems in this version of Emacs.
Each element has the form (PACKAGE SYMBOL REGEXP STRING).
PACKAGE is either a regular expression to match file names, or a
symbol (a feature name), like for `with-eval-after-load'.
SYMBOL is either the name of a string variable, or t.  Upon
loading PACKAGE, if SYMBOL is t or matches REGEXP, display a
warning using STRING as the message.")
(make-obsolete-variable 'bad-packages-alist nil "29.1")

(defun bad-package-check (package)
  "Run a check using the element from `bad-packages-alist' matching PACKAGE."
  (declare (obsolete nil "29.1"))
  (condition-case nil
      (let* ((list (assoc package bad-packages-alist))
             (symbol (nth 1 list)))
        (and list
             (boundp symbol)
             (or (eq symbol t)
                 (and (stringp (setq symbol (symbol-value symbol)))
                      (string-match-p (nth 2 list) symbol)))
             (display-warning package (nth 3 list) :warning)))
    (error nil)))


;;; Generic dispatcher commands

;; Macro `define-alternatives' can be used to create generic commands.
;; Generic commands are commands that can have different alternative
;; implementations, and choosing among them is the matter of user
;; preference in each case.  For example, you could have a generic
;; command `open' capable of "opening" a text file, a URL, a
;; directory, or a binary file, and each of these alternatives would
;; invoke a different Emacs function.

;; (define-alternatives COMMAND) creates a new interactive command
;; M-x COMMAND and a customizable variable COMMAND-alternatives.
;; Typically, the user will not need to customize this variable; packages
;; wanting to add alternative implementations should use
;;
;; ;;;###autoload (push '("My impl name" . my-impl-symbol) COMMAND-alternatives

(defmacro define-alternatives (command &rest customizations)
  "Define a new generic COMMAND which can have several implementations.

The argument `COMMAND' should be an unquoted symbol.

Running `\\[execute-extended-command] COMMAND RET' for \
the first time prompts for the
alternative implementation to use and records the selected alternative.
Thereafter, `\\[execute-extended-command] COMMAND RET' will \
automatically invoke the recorded selection.

Running `\\[universal-argument] \\[execute-extended-command] COMMAND RET' \
again prompts for an alternative
and overwrites the previous selection.

The macro creates a `defcustom' named `COMMAND-alternatives'.
CUSTOMIZATIONS, if non-nil, should be pairs of `defcustom'
keywords and values to add to the definition of that `defcustom';
typically, these keywords will be :group and :version with the
appropriate values.

To be useful, the value of `COMMAND-alternatives' should be an
alist describing the alternative implementations of COMMAND.
The elements of this alist should be of the form
  (ALTERNATIVE-NAME . FUNCTION)
where ALTERNATIVE-NAME is the name of the alternative to be shown
to the user as a selectable alternative, and FUNCTION is the
interactive function to call which implements that alternative.
The variable could be populated with associations describing the
alternatives either before or after invoking `define-alternatives';
if the variable is not defined when `define-alternatives' is invoked,
the macro will create it with a nil value, and your Lisp program
should then populate it."
  (declare (indent defun))
  (let* ((command-name (symbol-name command))
         (varalt-name (concat command-name "-alternatives"))
         (varalt-sym (intern varalt-name))
         (varimp-sym (intern (concat command-name "--implementation"))))
    `(progn

       (defcustom ,varalt-sym nil
         ,(format "Alist of alternative implementations for the `%s' command.

Each entry must be a pair (ALTNAME . ALTFUN), where:
ALTNAME - The name shown at user to describe the alternative implementation.
ALTFUN  - The function called to implement this alternative."
                  command-name)
         :type '(alist :key-type string :value-type function)
         ,@customizations)

       (put ',varalt-sym 'definition-name ',command)
       (defvar ,varimp-sym nil "Internal use only.")

       (defun ,command (&optional arg)
         ,(format "Run generic command `%s'.
If used for the first time, or with interactive ARG, ask the user which
implementation to use for `%s'.  The variable `%s'
contains the list of implementations currently supported for this command."
                  command-name command-name varalt-name)
         (interactive "P")
         (when (or arg (null ,varimp-sym))
           (let ((val (completing-read
		       ,(format-message
                         "Select implementation for command `%s': "
                         command-name)
		       ,varalt-sym nil t)))
             (unless (string-equal val "")
	       (when (null ,varimp-sym)
		 (message
		  "Use `C-u M-x %s RET' to select another implementation"
		  ,command-name)
		 (sit-for 3))
	       (customize-save-variable ',varimp-sym
					(cdr (assoc-string val ,varalt-sym))))))
         (if ,varimp-sym
             (call-interactively ,varimp-sym)
           (message "%s" ,(format-message
                           "No implementation selected for command `%s'"
                           command-name)))))))


;;; Functions for changing capitalization that Do What I Mean
(defun upcase-dwim (arg)
  "Upcase words in the region, if active; if not, upcase word at point.
If the region is active, this function calls `upcase-region'.
Otherwise, it calls `upcase-word', with prefix argument passed to it
to upcase ARG words."
  (interactive "*p")
  (if (use-region-p)
      (upcase-region (region-beginning) (region-end) (region-noncontiguous-p))
    (upcase-word arg)))

(defun downcase-dwim (arg)
    "Downcase words in the region, if active; if not, downcase word at point.
If the region is active, this function calls `downcase-region'.
Otherwise, it calls `downcase-word', with prefix argument passed to it
to downcase ARG words."
  (interactive "*p")
  (if (use-region-p)
      (downcase-region (region-beginning) (region-end) (region-noncontiguous-p))
    (downcase-word arg)))

(defun capitalize-dwim (arg)
  "Capitalize words in the region, if active; if not, capitalize word at point.
If the region is active, this function calls `capitalize-region'.
Otherwise, it calls `capitalize-word', with prefix argument passed to it
to capitalize ARG words."
  (interactive "*p")
  (if (use-region-p)
      (capitalize-region (region-beginning) (region-end) (region-noncontiguous-p))
    (capitalize-word arg)))

;;; Accessors for `decode-time' values.

(cl-defstruct (decoded-time
               (:constructor nil)
               (:copier nil)
               (:type list))
  (second nil :documentation "\
This is an integer or a Lisp timestamp (TICKS . HZ) representing a nonnegative
number of seconds less than 61.  (If not less than 60, it is a leap second,
which only some operating systems support.)")
  (minute nil :documentation "This is an integer between 0 and 59 (inclusive).")
  (hour nil :documentation "This is an integer between 0 and 23 (inclusive).")
  (day nil :documentation "This is an integer between 1 and 31 (inclusive).")
  (month nil :documentation "\
This is an integer between 1 and 12 (inclusive).  January is 1.")
  (year nil :documentation "This is a four digit integer.")
  (weekday nil :documentation "\
This is a number between 0 and 6, and 0 is Sunday.")
  (dst -1 :documentation "\
This is t if daylight saving time is in effect, nil if it is not
in effect, and -1 if daylight saving information is not available.
Also see `decoded-time-dst'.")
  (zone nil :documentation "\
This is an integer indicating the UTC offset in seconds, i.e.,
the number of seconds east of Greenwich.")
  )

;; Document that decoded-time-dst is problematic on 6-element lists.
;; It should return -1 indicating unknown DST, but currently returns
;; nil indicating standard time.
(put 'decoded-time-dst 'function-documentation
     "Access slot \"dst\" of `decoded-time' struct CL-X.
This is t if daylight saving time is in effect, nil if it is not
in effect, and -1 if daylight saving information is not available.
As a special case, return an unspecified value when given a list
too short to have a dst element.

(fn CL-X)")

(defun get-scratch-buffer-create ()
  "Return the *scratch* buffer, creating a new one if needed."
  (or (get-buffer "*scratch*")
      (let ((scratch (get-buffer-create "*scratch*")))
        ;; Don't touch the buffer contents or mode unless we know that
        ;; we just created it.
        (with-current-buffer scratch
          (when initial-scratch-message
            (insert (substitute-command-keys initial-scratch-message))
            (set-buffer-modified-p nil))
          (funcall initial-major-mode)
          (when (eq initial-major-mode 'lisp-interaction-mode)
            (setq-local trusted-content :all)))
        scratch)))

(defun scratch-buffer ()
  "Switch to the *scratch* buffer.
If the buffer doesn't exist, create it first."
  (interactive)
  (pop-to-buffer-same-window (get-scratch-buffer-create)))

(defun kill-buffer--possibly-save (buffer)
  "Ask the user to confirm killing of a modified BUFFER.

If the user confirms, optionally save BUFFER that is about to be
killed."
  (let ((response
         (cadr
          (read-multiple-choice
           (format "Buffer %s modified; kill anyway?"
                   (buffer-name))
           '((?y "yes" "kill buffer without saving")
             (?n "no" "exit without doing anything")
             (?s "save and then kill" "save the buffer and then kill it"))
           nil nil (and (not use-short-answers)
                        (not (use-dialog-box-p)))))))
    (if (equal response "no")
        nil
      (unless (equal response "yes")
        (with-current-buffer buffer
          (save-buffer)))
      t)))

(defsubst string-empty-p (string)
  "Check whether STRING is empty."
  (declare (pure t) (side-effect-free t))
  (string= string ""))

(defun read-signal-name ()
  "Read a signal number or name.
Return the signal number, if the user entered a number, otherwise
the signal symbol."
  (let ((value
         (completing-read "Signal code or name: "
                          (signal-names)
                          nil
                          (lambda (value)
                            (or (string-match "\\`[0-9]+\\'" value)
                                (member value (signal-names)))))))
    (if (string-match "\\`[0-9]+\\'" value)
        (string-to-number value)
      (intern (concat "sig" (downcase value))))))

(defun lax-plist-get (plist prop)
  "Extract a value from a property list, comparing with `equal'."
  (declare (ftype (function (list t) t))
           (pure t) (side-effect-free t) (obsolete plist-get "29.1"))
  (plist-get plist prop #'equal))

(defun lax-plist-put (plist prop val)
  "Change value in PLIST of PROP to VAL, comparing with `equal'."
  (declare (obsolete plist-put "29.1"))
  (plist-put plist prop val #'equal))



;; Text conversion support.  See textconv.c for more details about
;; what this is.

;; Actually in textconv.c.
(defvar text-conversion-edits)

;; Actually in elec-pair.el.
(defvar electric-pair-preserve-balance)
(declare-function electric-pair-analyze-conversion "elec-pair.el")

;; Actually in emacs-lisp/timer.el.
(declare-function timer-set-time "emacs-lisp/timer.el")

(defvar-local post-text-conversion-hook nil
  "Hook run after text is inserted by an input method.
Each function in this list is run until one returns non-nil.
When run, `last-command-event' is bound to the last character
that was inserted by the input method.")

(defun analyze-text-conversion ()
  "Analyze the results of the previous text conversion event.

For each insertion:

  - Look for the insertion of a string starting or ending with a
    character inside `auto-fill-chars', and fill the text around
    it if `auto-fill-mode' is enabled.

  - Look for the insertion of a new line, and cause automatic
    line breaking of the previous line when `auto-fill-mode' is
    enabled.

  - Look for the deletion of a single electric pair character,
    and delete the adjacent pair if
    `electric-pair-delete-adjacent-pairs'.

  - Run `post-self-insert-hook' for the last character of
    any inserted text so that modes such as `electric-pair-mode'
    can work.

  - Run `post-text-conversion-hook' with `last-command-event' set
    to the last character of any inserted text to finish up.

Finally, amalgamate recent changes to the undo list with previous
ones, unless a new line has been inserted or auto-fill has taken
place.  If undo information is being recorded, make sure
`undo-auto-current-boundary-timer' will run within the next 5
seconds."
  (interactive)
  ;; One important consideration to bear in mind when adjusting this
  ;; code is to _never_ move point in reaction to an edit so long as
  ;; the additional processing undertaken by this function does not
  ;; also edit the buffer text.
  (let ((any-nonephemeral nil)
        point-moved)
    ;; The list must be processed in reverse.
    (dolist (edit (reverse text-conversion-edits))
      ;; Filter out ephemeral edits and deletions after point.  Here, we
      ;; are only interested in insertions or deletions whose contents
      ;; can be identified.
      (when (stringp (nth 3 edit))
        (with-current-buffer (car edit)
          ;; Record that the point hasn't been moved by the execution
          ;; of a post command or text conversion hook.
          (setq point-moved nil)
          (if (not (eq (nth 1 edit) (nth 2 edit)))
              ;; Process this insertion.  (nth 3 edit) is the text which
              ;; was inserted.
              (let* ((inserted (nth 3 edit))
                     ;; Get the first and last characters.
                     (start (aref inserted 0))
                     (end (aref inserted (1- (length inserted))))
                     ;; Figure out whether or not to auto-fill.
                     (auto-fill-p (or (aref auto-fill-chars start)
                                      (aref auto-fill-chars end)))
                     ;; Figure out whether or not a newline was inserted.
                     (newline-p (string-search "\n" inserted))
                     ;; Save the current undo list to figure out
                     ;; whether or not auto-fill has actually taken
                     ;; place.
                     (old-undo-list buffer-undo-list)
                     ;; Save the point position to return it there
                     ;; later.
                     (old-point (point)))
                (save-excursion
                  (if (and auto-fill-function newline-p)
                      (progn (goto-char (nth 2 edit))
                             (previous-logical-line)
                             (funcall auto-fill-function)
                             (setq old-point (point)))
                    (when (and auto-fill-function auto-fill-p)
                      (goto-char (nth 2 edit))
                      (funcall auto-fill-function)
                      (setq old-point (point))))
                  ;; Record whether or not this edit should result in
                  ;; an undo boundary being added.
                  (setq any-nonephemeral
                        (or any-nonephemeral newline-p
                            ;; See if auto-fill has taken place by
                            ;; comparing the current undo list with
                            ;; the saved head.
                            (not (eq old-undo-list
                                     buffer-undo-list)))))
                (goto-char (nth 2 edit))
                (let ((last-command-event end)
                      (point (point)))
                  (unless (run-hook-with-args-until-success
                           'post-text-conversion-hook)
                    (run-hooks 'post-self-insert-hook))
                  (when (not (eq (point) point))
                    (setq point-moved t)))
                ;; If post-self-insert-hook doesn't move the point,
                ;; restore it to its previous location.  Generally,
                ;; the call to goto-char upon processing the last edit
                ;; recorded text-conversion-edit will see to this, but
                ;; if the input method sets point expressly, no edit
                ;; will be recorded, and point will wind up away from
                ;; where the input method believes it is.
                (unless point-moved
                  (goto-char old-point)))
            ;; Process this deletion before point.  (nth 2 edit) is the
            ;; text which was deleted.  Input methods typically prefer
            ;; to edit words instead of deleting characters off their
            ;; ends, but they seem to always send proper requests for
            ;; deletion for punctuation.
            (when (and (boundp 'electric-pair-delete-adjacent-pairs)
                       (symbol-value 'electric-pair-delete-adjacent-pairs)
                       ;; Make sure elec-pair is loaded.
                       (fboundp 'electric-pair-analyze-conversion)
                       ;; Only do this if only a single edit happened.
                       text-conversion-edits)
              (save-excursion
                (goto-char (nth 2 edit))
                (electric-pair-analyze-conversion (nth 3 edit))))))))
    ;; If all edits were ephemeral, make this an amalgamating command.
    ;; Then, make sure that an undo boundary is placed within the next
    ;; five seconds.
    (unless any-nonephemeral
      (undo-auto-amalgamate)
      (let ((timer undo-auto-current-boundary-timer))
        (if timer
            ;; The timer is already running.  See if it's due to expire
            ;; within the next five seconds.
            (let ((time (timer--time timer)))
              (unless (<= (time-convert (time-subtract time nil)
                                        'integer)
                          5)
                ;; It's not, so make it run in 5 seconds.
                (timer-set-time undo-auto-current-boundary-timer
                                (time-add nil 5))))
          ;; Otherwise, start it for five seconds from now.
          (setq undo-auto-current-boundary-timer
                (run-at-time 5 nil #'undo-auto--boundary-timer)))))))

(provide 'simple)

;;; simple.el ends here
