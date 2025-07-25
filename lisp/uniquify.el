;;; uniquify.el --- unique buffer names dependent on file name -*- lexical-binding: t -*-

;; Copyright (C) 1989, 1995-1997, 2001-2025 Free Software Foundation,
;; Inc.

;; Author: Dick King <king@reasoning.com>
;; Maintainer: emacs-devel@gnu.org
;; Keywords: files
;; Created: 15 May 86
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

;; Emacs's traditional method for making buffer names unique adds <2>, <3>,
;; etc. to the end of (all but one of) the buffers.  This file replaces
;; that behavior, for buffers visiting files and Dired buffers, with a
;; uniquification that adds parts of the file name until the buffer names
;; are unique.  For instance, buffers visiting /u/mernst/tmp/Makefile and
;; /usr/projects/zaphod/Makefile would be named Makefile|tmp and
;; Makefile|zaphod, respectively (instead of Makefile and Makefile<2>).
;; Other buffer name styles are also available.

;; To use this file, do (require 'uniquify)
;; and set uniquify-buffer-name-style to one of its non-nil alternative values.

;; For other options, see "User-visible variables", below.

;;; Change Log:

;; Originally by Dick King <king@reasoning.com> 15 May 86
;; Converted for Emacs 18 by Stephen Gildea <stepheng+emacs@gildea.com>
;; Make uniquify-min-dir-content 0 truly non-invasive.  gildea 23 May 89
;; Some cleanup.  uniquify-min-dir-content default 0.  gildea 01 Jun 89
;; Don't rename to "".  Michael Ernst <mernst@theory.lcs.mit.edu> 15 Jun 94
;; Add kill-buffer-hook.  Kenneth Manheimer <ken.manheimer@nist.gov> 09 May 95
;; Add advice for rename-buffer and create-file-buffer, handle dired buffers,
;;  kill-buffer-rationalize-buffer-names-p, documentation.  mernst 24 May 95
;; Remove free variables, fix typos.  mernst 5 Jun 95
;; Efficiently support Emacs 19.27 & earlier.  ken.manheimer, mernst 10 Jun 95
;; Rename user options to "uniquify-...", add uniquify-reverse-dir-content-p,
;;  add uniquify-ask-about-buffer-names-p.  king, mernst 13 Jun 95
;; Prefix functions by "uniquify-..."; rename mnemonic-buffer-names to
;;  uniquify-buffer-name-style; add 'forward and 'post-forward-angle-brackets
;;  styles; remove uniquify-reverse-dir-content-p; add
;;  uniquify-trailing-separator-p.  mernst 4 Aug 95
;; Don't call expand-file-name on nil.  mernst 7 Jan 96
;; Check whether list-buffers-directory is bound.  mernst 11 Oct 96
;; Ignore non-file non-dired buffers. Colin Rafferty <craffert@ml.com> 3 Mar 97
;; Use last component, not "", for file name of directories.  mernst 27 Jun 97
;; Use directory-file-name; code cleanup.  mernst 6 Sep 97
;; Add uniquify-ignore-buffers-re.
;;  Andre Srinivasan <andre@visigenic.com> 9 Sep 97
;; Add uniquify-list-buffers-directory-modes
;;   Stefan Monnier <monnier@cs.yale.edu> 17 Nov 2000
;; Algorithm and data structure changed to reduce consing with lots of buffers
;;   Francesco Potortì <pot@gnu.org> (ideas by rms and monnier) 2001-07-18

;; Valuable feedback was provided by
;; Paul Smith <psmith@baynetworks.com>,
;; Alastair Burt <burt@dfki.uni-kl.de>,
;; Bob Weiner <weiner@footloose.sps.mot.com>,
;; Albert L. Ting <alt@vlibs.com>,
;; gyro@reasoning.com,
;; Bryan O'Sullivan <bos@eng.sun.com>.


;;; Code:

(eval-when-compile (require 'cl-lib))

;;; User-visible variables

(defgroup uniquify nil
  "Unique buffer names dependent on file name."
  :group 'files)

(defun uniquify--buffer-refresh ()
  "Refreshes all `uniquify'-managed buffers with current options."
  (when uniquify-buffer-name-style
    (save-current-buffer
      (dolist (buffer (buffer-list))
        (set-buffer buffer)
        (when uniquify-managed
          (rename-buffer (uniquify-buffer-base-name) 'unique))))))

(defun uniquify--set-option (variable value)
  "Call in `defcustom' :set keyword when `uniquify--buffer-refresh' is needed.
VARIABLE is set to VALUE if `uniquify' is loaded."
  (when (featurep 'uniquify) ; in case `uniquify' was unloaded
    (set-default variable value)
    (uniquify--buffer-refresh)))

(defcustom uniquify-buffer-name-style 'post-forward-angle-brackets
  "How to construct unique buffer names for files with the same base name.
The value can be one of: `forward', `reverse', `post-forward',
`post-forward-angle-brackets', or nil.

For example, the files `/foo/bar/mumble/name' and `/baz/quux/mumble/name'
would have the following buffer names in the various styles:

  forward                       bar/mumble/name    quux/mumble/name
  reverse                       name\\mumble\\bar    name\\mumble\\quux
  post-forward                  name|bar/mumble    name|quux/mumble
  post-forward-angle-brackets   name<bar/mumble>   name<quux/mumble>
  nil                           name               name<2>

The value can be set to a customized function with two arguments
BASE and EXTRA-STRINGS where BASE is a string and EXTRA-STRINGS
is a list of strings.  For example the current implementation for
post-forward-angle-brackets could be:

  (defun my-post-forward-angle-brackets (base extra-string)
    (concat base \"<\" (mapconcat #\\='identity extra-string \"/\") \">\"))

The \"mumble\" part may be stripped as well, depending on the
setting of `uniquify-strip-common-suffix'.

Setting this variable directly will not usually take effect; use either
\\[customize] or `setopt', or call `uniquify--set-option'; otherwise
reload your buffers.

For more options that you can set, browse the `uniquify' custom group."
  :type '(radio (const forward)
		(const reverse)
		(const post-forward)
		(const post-forward-angle-brackets)
                (function :tag "Other")
		(const :tag "numeric suffixes" nil))
  :initialize #'custom-initialize-default
  :set #'uniquify--set-option
  :version "24.4"
  :require 'uniquify)

(define-obsolete-variable-alias 'uniquify-after-kill-buffer-p
  'uniquify-after-kill-buffer-flag "31.1")
(defcustom uniquify-after-kill-buffer-flag t
  "If non-nil, rerationalize buffer names after a buffer has been killed."
  :type 'boolean
  :version "31.1")

(defcustom uniquify-ignore-buffers-re nil
  "Regular expression matching buffer names that should not be uniquified.
For instance, set this to \"^draft-[0-9]+$\" to avoid having uniquify
rename draft buffers even if `uniquify-after-kill-buffer-flag' is
non-nil and the visited file name isn't the same as that of the buffer.

Setting this variable directly will not usually take effect; use either
\\[customize] or `setopt', or call `uniquify--set-option'; otherwise
reload your buffers."
  :type '(choice (const :tag "Uniquify all buffers" nil) regexp)
  :initialize #'custom-initialize-default
  :set #'uniquify--set-option)

(defcustom uniquify-min-dir-content 0
  "Minimum number of directory name components included in buffer name.
Setting this variable directly will not usually take effect; use either
\\[customize] or `setopt', or call `uniquify--set-option'; otherwise
reload your buffers."
  :type 'integer
  :initialize #'custom-initialize-default
  :set #'uniquify--set-option)

(defcustom uniquify-separator nil
  "String separator for buffer name components.
When `uniquify-buffer-name-style' is `post-forward', separates
base file name from directory part in buffer names (default \"|\").
When `uniquify-buffer-name-style' is `reverse', separates all
file name components (default \"\\\").

Setting this variable directly will not usually take effect; use either
\\[customize] or `setopt', or call `uniquify--set-option'; otherwise
reload your buffers."
  :type '(choice (const nil) string)
  :initialize #'custom-initialize-default
  :set #'uniquify--set-option)

(define-obsolete-variable-alias 'uniquify-trailing-separator-p
  'uniquify-trailing-separator-flag "31.1")
(defcustom uniquify-trailing-separator-flag nil
  "Non-nil means add a file name separator to Dired buffer names.
If `uniquify-buffer-name-style' is `forward', add the separator at the end;
if it is `reverse', add the separator at the beginning; otherwise, this
variable is ignored."
  :type 'boolean
  :version "31.1")

(defcustom uniquify-strip-common-suffix
  ;; Using it when uniquify-min-dir-content>0 doesn't make much sense.
  (eq 0 uniquify-min-dir-content)
  "If non-nil, strip common directory suffixes of conflicting files.
E.g. if you open /a1/b/c/d and /a2/b/c/d, the buffer names will say
\"d|a1\" and \"d|a2\" instead of \"d|a1/b/c\" and \"d|a2/b/c\".
This can be handy when you have deep parallel hierarchies.

Setting this variable directly will not usually take effect; use either
\\[customize] or `setopt', or call `uniquify--set-option'; otherwise
reload your buffers."
  :type 'boolean
  :initialize #'custom-initialize-default
  :set #'uniquify--set-option)

(defvar uniquify-list-buffers-directory-modes '(dired-mode cvs-mode vc-dir-mode)
  "List of modes for which uniquify should obey `list-buffers-directory'.
That means that when `buffer-file-name' is set to nil, `list-buffers-directory'
contains the name of the directory which the buffer is visiting.")

(defcustom uniquify-dirname-transform #'identity
  "Function to transform buffer's directory name when uniquifying buffer's name.

When `uniquify-buffer-name-style' is non-nil, Emacs makes buffer
names unique by adding components of the buffer's directory name
until the resulting name is unique.  This function is used to
transform the buffer's directory name during this uniquifying
process, allowing the unique buffer name to include strings
from sources other than the buffer's directory.  The default is
`identity', so the unmodified buffer's directory name is used for
uniquifying.

This function is called with the buffer's directory name and
should return a string which names a file (that does not need to
actually exist in the filesystem); the components of this file
name will then be used to uniquify the buffer's name.

To include components from the `project-name' of the buffer, set
this variable to `project-uniquify-dirname-transform'.

Setting this variable directly will not usually take effect; use either
\\[customize] or `setopt', or call `uniquify--set-option'; otherwise
reload your buffers."
  :type `(choice (function-item :tag "Use directory name as-is" identity)
                 (function-item :tag "Include project name in directory name"
                                ,#'project-uniquify-dirname-transform)
                 function)
  :initialize #'custom-initialize-default
  :set #'uniquify--set-option
  :version "30.1"
  :group 'uniquify)

;;; Utilities

;; uniquify-fix-list data structure
(cl-defstruct (uniquify-item
	    (:constructor nil) (:copier nil)
	    (:constructor uniquify-make-item
	     (base dirname buffer &optional proposed)))
  base dirname buffer proposed)

;; Internal variables used free
(defvar uniquify-possibly-resolvable nil)

(defvar-local uniquify-managed nil
  "Non-nil if the name of this buffer is managed by uniquify.
It actually holds the list of `uniquify-item's corresponding to the conflict.")
(put 'uniquify-managed 'permanent-local t)

;; Used in desktop.el to save the non-uniquified buffer name
(defun uniquify-buffer-base-name ()
  "Return the base name of the current buffer.
Return nil if the buffer is not managed by uniquify."
  (and uniquify-managed
       (uniquify-item-base (car uniquify-managed))))

;;; Main entry point.

(defun uniquify-rationalize-file-buffer-names (base dirname newbuf)
  "Make file buffer names unique by adding segments from file name.
If `uniquify-min-dir-content' > 0, always pulls that many
file name elements.
Arguments BASE, DIRNAME, and NEWBUF specify the new buffer that causes
this rationalization."
  (interactive
   (list (if uniquify-managed
	     (uniquify-item-base (car uniquify-managed)) (buffer-name))
	 (uniquify-buffer-file-name (current-buffer))
	 (current-buffer)))
  ;; Make sure we don't get confused by outdated uniquify-managed info in
  ;; this buffer.
  (with-current-buffer newbuf (setq uniquify-managed nil))
  (when dirname
    (setq dirname (funcall uniquify-dirname-transform
                           (expand-file-name (directory-file-name dirname))))
    (let ((fix-list (list (uniquify-make-item base dirname newbuf
                                              nil)))
	  items)
      (dolist (buffer (buffer-list))
	(when (and (not (and uniquify-ignore-buffers-re
			     (string-match uniquify-ignore-buffers-re
					   (buffer-name buffer))))
		   ;; Only try to rename buffers we actually manage.
		   (setq items (buffer-local-value 'uniquify-managed buffer))
		   (equal base (uniquify-item-base (car items)))
		   ;; Don't re-add stuff we already have.  Actually this
		   ;; whole `and' test should only match at most once.
		   (not (memq (car items) fix-list)))
	  (unless (cdr items)
	    ;; If there was no conflict, the buffer-name is equal to the
	    ;; base-name and we may have missed a rename-buffer because
	    ;; of code like in set-visited-file-name:
	    ;; (or (string= new-name (buffer-name)) (rename-buffer new-name t))
	    ;; So we need to refresh the dirname of the uniquify-item.
	    (setf (uniquify-item-dirname (car items))
		  (uniquify-buffer-file-name
		   (uniquify-item-buffer (car items))))
	    ;; This shouldn't happen, but maybe there's no dirname any more.
	    (unless (uniquify-item-dirname (car items))
	      (with-current-buffer (uniquify-item-buffer (car items))
		(setq uniquify-managed nil))
	      (setq items nil)))
          ;; In case we missed some calls to kill-buffer, there may be dead
          ;; buffers in uniquify-managed, so filter them out.
          (setq items
                (delq nil (mapcar
                           (lambda (item)
                             (if (buffer-live-p (uniquify-item-buffer item))
                                 item))
                           items)))
          ;; Other buffer's `uniquify-managed' lists may share
          ;; elements.  Ensure that we don't add these elements more
          ;; than once to this buffer's `uniquify-managed' list.
          (let ((new-items nil))
            (dolist (item items)
              (unless (memq item fix-list)
                (push item new-items)))
	    (setq fix-list (append fix-list new-items)))))
      ;; selects buffers whose names may need changing, and others that
      ;; may conflict, then bring conflicting names together
      (uniquify-rationalize fix-list))))

;; uniquify's version of buffer-file-name; result never contains trailing slash
(defun uniquify-buffer-file-name (buffer)
  "Return name of directory, file BUFFER is visiting, or nil if none.
Works on ordinary file-visiting buffers and buffers whose mode is mentioned
in `uniquify-list-buffers-directory-modes', otherwise returns nil."
  (with-current-buffer buffer
    (let ((filename
	   (or buffer-file-name
	       (if (memq major-mode uniquify-list-buffers-directory-modes)
		   list-buffers-directory))))
      (when filename
	 (funcall uniquify-dirname-transform
	          (directory-file-name
	          (file-name-directory
	           (expand-file-name
	            (directory-file-name filename)))))))))

(defun uniquify-rerationalize-w/o-cb (fix-list)
  "Re-rationalize the buffers in FIX-LIST, but ignoring `current-buffer'."
  (let ((new-fix-list nil))
    (dolist (item fix-list)
      (let ((buf (uniquify-item-buffer item)))
	(unless (or (eq buf (current-buffer)) (not (buffer-live-p buf)))
	  (push item new-fix-list))))
    (when new-fix-list
      (uniquify-rationalize new-fix-list))))

(defun uniquify-rationalize (fix-list)
  ;; Set up uniquify to re-rationalize after killing/renaming
  ;; if there is a conflict.
  (dolist (item fix-list)
    (with-current-buffer (uniquify-item-buffer item)
      (setq uniquify-managed fix-list)))
  (uniquify-rationalize--generic fix-list #'uniquify-rename-buffer #'get-buffer))

(defun uniquify-rationalize--generic (fix-list rename-buffer-fn get-buffer-fn)
  (dolist (item fix-list)
    (with-current-buffer (uniquify-item-buffer item)
      ;; Refresh the dirnames and proposed names.
      (setf (uniquify-item-proposed item)
	    (uniquify-get-proposed-name (uniquify-item-base item)
					(uniquify-item-dirname item)
                                        nil))))
  ;; Strip any shared last directory names of the dirname.
  (when (and (cdr fix-list) uniquify-strip-common-suffix)
    (let ((strip t))
      (while (let* ((base (file-name-nondirectory
			   (uniquify-item-dirname (car fix-list))))
		    (items fix-list))
	       (when (> (length base) 0)
		 (while (and strip items)
		   (unless (equal base (file-name-nondirectory
					(uniquify-item-dirname (pop items))))
		     (setq strip nil)))
		 strip))
	;; It's all the same => strip.
	(dolist (item (prog1 fix-list (setq fix-list nil)))
	  ;; Create new items because the old ones are kept (with the true
	  ;; `dirname') for later rerationalizing.
	  (push (uniquify-make-item (uniquify-item-base item)
				    (let ((f (file-name-directory
					      (uniquify-item-dirname item))))
				      (and f (directory-file-name f)))
				    (uniquify-item-buffer item)
				    (uniquify-item-proposed item))
		fix-list)))))
  ;; If uniquify-min-dir-content is 0, this will end up just
  ;; passing fix-list to uniquify-rationalize-conflicting-sublist.
  (uniquify-rationalize-a-list fix-list nil rename-buffer-fn get-buffer-fn))

(defun uniquify-item-greaterp (item1 item2)
  (string-lessp (uniquify-item-proposed item2)
		(uniquify-item-proposed item1)))

(defun uniquify-rationalize-a-list (fix-list depth rename-buffer-fn get-buffer-fn)
  (unless depth (setq depth uniquify-min-dir-content))
  (let (conflicting-sublist	; all elements have the same proposed name
	(old-proposed "")
	proposed)
    ;; Divide fix-list into items with same proposed names and pass them
    ;; to uniquify-rationalize-conflicting-sublist.
    (dolist (item (sort (copy-sequence fix-list) 'uniquify-item-greaterp))
      (setq proposed (uniquify-item-proposed item))
      (unless (equal proposed old-proposed)
	(uniquify-rationalize-conflicting-sublist conflicting-sublist
						  old-proposed depth
                                                  rename-buffer-fn get-buffer-fn)
	(setq conflicting-sublist nil))
      (push item conflicting-sublist)
      (setq old-proposed proposed))
    (uniquify-rationalize-conflicting-sublist conflicting-sublist
					      old-proposed depth
                                              rename-buffer-fn get-buffer-fn)))

(defun uniquify-get-proposed-name (base dirname &optional depth)
  (unless depth (setq depth uniquify-min-dir-content))
  (cl-assert (equal (directory-file-name dirname) dirname)) ;No trailing slash.

  (let ((extra-string nil)
	(n depth))
    (while (and (> n 0) dirname)
      (let ((file (file-name-nondirectory dirname)))
	(when (setq dirname (file-name-directory dirname))
	  (setq dirname (directory-file-name dirname)))
	(setq n (1- n))
	(push (if (zerop (length file)) ;nil or "".
		  (prog1 (or (file-remote-p dirname) "")
		    (setq dirname nil)) ;Could be `dirname' iso "".
		file)
	      extra-string)))
    (when (zerop n)
      (if (and dirname extra-string
	       (equal dirname (file-name-directory dirname)))
	  ;; We're just before the root.  Let's add the leading / already.
	  ;; With "/a/b"+"/c/d/b" this leads to "/a/b" and "d/b" but with
	  ;; "/a/b"+"/c/a/b" this leads to "/a/b" and "a/b".
	  (push "" extra-string))
      (setq uniquify-possibly-resolvable t))

    (cond
     ((null extra-string) base)
     ((string-equal base "") ;Happens for dired buffers on the root directory.
      (mapconcat #'identity extra-string "/"))
     ((eq uniquify-buffer-name-style 'reverse)
      (mapconcat #'identity
		 (cons base (nreverse extra-string))
		 (or uniquify-separator "\\")))
     ((eq uniquify-buffer-name-style 'forward)
      (mapconcat #'identity (nconc extra-string (list base))
		 "/"))
     ((eq uniquify-buffer-name-style 'post-forward)
      (concat base (or uniquify-separator "|")
	      (mapconcat #'identity extra-string "/")))
     ((eq uniquify-buffer-name-style 'post-forward-angle-brackets)
      (concat base "<" (mapconcat #'identity extra-string "/")
	      ">"))
     ((functionp uniquify-buffer-name-style)
      (funcall uniquify-buffer-name-style base extra-string))
     (t (error "Bad value for uniquify-buffer-name-style: %s"
	       uniquify-buffer-name-style)))))


;; Deal with conflicting-sublist, all of whose elements have identical
;; "base" components.
(defun uniquify-rationalize-conflicting-sublist (conf-list old-name depth rename-buffer-fn get-buffer-fn)
  (when conf-list
    (if (or (cdr conf-list)
	    ;; Check that the proposed name doesn't conflict with some
	    ;; existing buffer.
	    (let ((buf (funcall get-buffer-fn old-name)))
	      (and buf (not (eq buf (uniquify-item-buffer (car conf-list)))))))
	(when uniquify-possibly-resolvable
	  (setq uniquify-possibly-resolvable nil
		depth (1+ depth))
	  (dolist (item conf-list)
	    (setf (uniquify-item-proposed item)
		  (uniquify-get-proposed-name
		   (uniquify-item-base item)
		   (uniquify-item-dirname item)
		   depth)))
	  (uniquify-rationalize-a-list conf-list depth rename-buffer-fn get-buffer-fn))
      (unless (string= old-name "")
	(funcall rename-buffer-fn (car conf-list) old-name)))))

(defun uniquify-rename-buffer (item newname)
  (let ((buffer (uniquify-item-buffer item)))
    (unless (equal newname (buffer-name buffer))
      (with-current-buffer buffer
	(let ((uniquify-buffer-name-style nil))	;Avoid hooks on rename-buffer.
	  ;; Pass the `unique' arg, so the advice doesn't mark it as unmanaged.
	  (rename-buffer newname t))))))

(defvar-local uniquify--stateless-curname nil
  "The current unique name of this buffer in `uniquify-get-unique-names'.")

(defun uniquify-get-unique-names (buffers)
  "Return a list with unique names for buffers in BUFFERS.

The names are unique only among BUFFERS, and may conflict with other
buffers not in that list.  Each string has a text property
`uniquify-orig-buffer' that stores the corresponding buffer.

This does not rename the buffers or change any state; the unique name is
only present in the returned alist."
  (let ((buffer-names (make-hash-table :size (length buffers) :test 'equal))
        fix-lists-by-base)
    (dolist (buf buffers)
      (with-current-buffer buf
        (setq uniquify--stateless-curname (buffer-name buf))
        (puthash (buffer-name buf) buf buffer-names)
        (when uniquify-managed
          (let ((base (uniquify-item-base (car uniquify-managed))))
            (push
             (uniquify-make-item base (uniquify-buffer-file-name buf) buf nil)
             (alist-get base fix-lists-by-base nil nil #'equal))))))
    (dolist (pair fix-lists-by-base)
      (uniquify-rationalize--generic
       (cdr pair)
       (lambda (item name)              ; rename-buffer
         (with-current-buffer (uniquify-item-buffer item)
           (remhash uniquify--stateless-curname buffer-names)
           (setq uniquify--stateless-curname name)
           (puthash name (current-buffer) buffer-names)))
       (lambda (name)                   ; get-buffer
         (gethash name buffer-names)))))
  (mapcar (lambda (buf)
            (with-current-buffer buf
              (let ((name
                     (if (eq uniquify--stateless-curname
                             (buffer-name buf))
                         (copy-sequence uniquify--stateless-curname)
                       uniquify--stateless-curname)))
                (when name
                  (put-text-property 0 1 'uniquify-orig-buffer buf name))
                (kill-local-variable 'uniquify--stateless-curname)
                name)))
          buffers))

;;; Hooks from the rest of Emacs

(defun uniquify-maybe-rerationalize-w/o-cb ()
  "Re-rationalize buffer names, ignoring current buffer."
  (and (cdr uniquify-managed)
       uniquify-buffer-name-style
       (uniquify-rerationalize-w/o-cb uniquify-managed)))

;; Buffer deletion
;; Rerationalize after a buffer is killed, to reduce coinciding buffer names.
;; This mechanism uses `kill-buffer-hook', which runs *before* deletion, so
;; it calls `uniquify-rerationalize-w/o-cb' to rerationalize the buffer list
;; ignoring the current buffer (which is going to be deleted anyway).
(defun uniquify-kill-buffer-function ()
  "Re-rationalize buffer names, ignoring current buffer.
For use on `kill-buffer-hook'."
  (and uniquify-after-kill-buffer-flag
       (uniquify-maybe-rerationalize-w/o-cb)))

;; Ideally we'd like to add it buffer-locally, but that doesn't work
;; because kill-buffer-hook is not permanent-local :-(
;; FIXME kill-buffer-hook _is_ permanent-local in 22+.
(add-hook 'kill-buffer-hook 'uniquify-kill-buffer-function)

;; The logical place to put all this code is in generate-new-buffer-name.
;; It's written in C, so we would add a generate-new-buffer-name-function
;; which, if non-nil, would be called instead of the C.  One problem with
;; that is that generate-new-buffer-name takes a potential buffer name as
;; its argument -- not other information, such as what file the buffer will
;; visit.

;; The below solution works because generate-new-buffer-name is called
;; only by rename-buffer (which, as of 19.29, is never called from C) and
;; generate-new-buffer, which is called only by Lisp functions
;; create-file-buffer and rename-uniquely.  Rename-uniquely generally
;; isn't used for buffers visiting files, so it's sufficient to hook
;; rename-buffer and create-file-buffer.  (Setting find-file-hook isn't
;; sufficient.)

;; (advice-add 'rename-buffer :around #'uniquify--rename-buffer-advice)
(defun uniquify--rename-buffer-advice (newname &optional unique)
  ;; BEWARE: This is called directly from `buffer.c'!
  "Uniquify buffer names with parts of directory name."
  (uniquify-maybe-rerationalize-w/o-cb)
  (if (null unique)
      ;; Mark this buffer so it won't be renamed by uniquify.
      (setq uniquify-managed nil)
    (when uniquify-buffer-name-style
      ;; Rerationalize w.r.t the new name.
      (uniquify-rationalize-file-buffer-names
       newname
       (uniquify-buffer-file-name (current-buffer))
       (current-buffer)))))


;; (advice-add 'create-file-buffer :around #'uniquify--create-file-buffer-advice)
(defun uniquify--create-file-buffer-advice (buf filename basename)
  ;; BEWARE: This is called directly from `files.el'!
  "Uniquify buffer names with parts of directory name."
  (when uniquify-buffer-name-style
    (uniquify-rationalize-file-buffer-names
     basename
     (file-name-directory (expand-file-name (directory-file-name filename)))
     buf)))

(defun uniquify-unload-function ()
  "Unload the uniquify library."
  (save-current-buffer
    (let ((buffers nil))
      (dolist (buf (buffer-list))
	(set-buffer buf)
	(when uniquify-managed
	  (push (cons buf (uniquify-item-base (car uniquify-managed))) buffers)))
      (dolist (buf buffers)
	(set-buffer (car buf))
	(rename-buffer (cdr buf) t))))
  ;; continue standard unloading
  nil)

(provide 'uniquify)

;;; uniquify.el ends here
