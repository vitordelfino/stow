;;; company.el --- Modular text completion framework  -*- lexical-binding: t -*-

;; Copyright (C) 2009-2021  Free Software Foundation, Inc.

;; Author: Nikolaj Schumacher
;; Maintainer: Dmitry Gutov <dgutov@yandex.ru>
;; URL: http://company-mode.github.io/
;; Version: 0.9.13
;; Keywords: abbrev, convenience, matching
;; Package-Requires: ((emacs "25.1"))

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
;;
;; Company is a modular completion framework.  Modules for retrieving completion
;; candidates are called backends, modules for displaying them are frontends.
;;
;; Company comes with many backends, e.g. `company-etags'.  These are
;; distributed in separate files and can be used individually.
;;
;; Enable `company-mode' in all buffers with M-x global-company-mode.  For
;; further information look at the documentation for `company-mode' (C-h f
;; company-mode RET).
;;
;; If you want to start a specific backend, call it interactively or use
;; `company-begin-backend'.  For example:
;; M-x company-abbrev will prompt for and insert an abbrev.
;;
;; To write your own backend, look at the documentation for `company-backends'.
;; Here is a simple example completing "foo":
;;
;; (defun company-my-backend (command &optional arg &rest ignored)
;;   (interactive (list 'interactive))
;;   (pcase command
;;     (`interactive (company-begin-backend 'company-my-backend))
;;     (`prefix (company-grab-symbol))
;;     (`candidates (list "foobar" "foobaz" "foobarbaz"))
;;     (`meta (format "This value is named %s" arg))))
;;
;; Sometimes it is a good idea to mix several backends together, for example to
;; enrich gtags with dabbrev-code results (to emulate local variables).  To do
;; this, add a list with both backends as an element in `company-backends'.
;;
;;; Change Log:
;;
;; See NEWS.md in the repository.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'pcase)

(defgroup company nil
  "Extensible inline text completion mechanism."
  :group 'abbrev
  :group 'convenience
  :group 'matching)

(defgroup company-faces nil
  "Faces used by Company."
  :group 'company
  :group 'faces)

(defface company-tooltip
  '((((class color) (min-colors 88) (background light))
     (:foreground "black" :background "cornsilk"))
    (((class color) (min-colors 88) (background dark))
     (:background "gray26"))
    (t (:foreground "black" :background "yellow")))
  "Face used for the tooltip.")

(defface company-tooltip-selection
  '((((class color) (min-colors 88) (background light))
     (:background "light blue"))
    (((class color) (min-colors 88) (background dark))
     (:background "gray31"))
    (t (:background "green")))
  "Face used for the selection in the tooltip.")

(defface company-tooltip-search
  '((default :inherit highlight))
  "Face used for the search string in the tooltip.")

(defface company-tooltip-search-selection
  '((default :inherit highlight))
  "Face used for the search string inside the selection in the tooltip.")

(defface company-tooltip-mouse
  '((default :inherit highlight))
  "Face used for the tooltip item under the mouse.")

(defface company-tooltip-common
  '((((background light))
     :foreground "darkred")
    (((background dark))
     :foreground "pale turquoise"))
  "Face used for the common completion in the tooltip.")

(defface company-tooltip-common-selection
  '((default :inherit company-tooltip-common))
  "Face used for the selected common completion in the tooltip.")

(defface company-tooltip-annotation
  '((((background light))
     :foreground "firebrick4")
    (((background dark))
     :foreground "LightCyan3"))
  "Face used for the completion annotation in the tooltip.")

(defface company-tooltip-annotation-selection
  '((default :inherit company-tooltip-annotation))
  "Face used for the selected completion annotation in the tooltip.")

(defface company-tooltip-quick-access
  '((default :inherit company-tooltip-annotation))
  "Face used for the quick-access hints shown in the tooltip."
  :package-version '(company . "0.9.14"))

(defface company-tooltip-quick-access-selection
  '((default :inherit company-tooltip-annotation-selection))
  "Face used for the selected quick-access hints shown in the tooltip."
  :package-version '(company . "0.9.14"))

(defface company-scrollbar-fg
  '((((background light))
     :background "darkred")
    (((background dark))
     :background "gray33"))
  "Face used for the tooltip scrollbar thumb.")

(defface company-scrollbar-bg
  '((((background light))
     :background "wheat")
    (((background dark))
     :background "gray28"))
  "Face used for the tooltip scrollbar background.")

(defface company-preview
  '((default :inherit (company-tooltip-selection company-tooltip)))
  "Face used for the completion preview.")

(defface company-preview-common
  '((default :inherit company-tooltip-common-selection))
  "Face used for the common part of the completion preview.")

(defface company-preview-search
  '((default :inherit company-tooltip-common-selection))
  "Face used for the search string in the completion preview.")

(defface company-echo nil
  "Face used for completions in the echo area.")

(defface company-echo-common
  '((((background light)) (:foreground "firebrick4"))
    (((background dark)) (:foreground "firebrick1")))
  "Face used for the common part of completions in the echo area.")

;; Too lazy to re-add :group to all defcustoms down below.
(setcdr (assoc load-file-name custom-current-group-alist)
        'company)

(defun company-frontends-set (variable value)
  ;; Uniquify.
  (let ((value (delete-dups (copy-sequence value))))
    (and (or (and (memq 'company-pseudo-tooltip-unless-just-one-frontend value)
                  (memq 'company-pseudo-tooltip-frontend value))
             (and (memq 'company-pseudo-tooltip-unless-just-one-frontend-with-delay value)
                  (memq 'company-pseudo-tooltip-frontend value))
             (and (memq 'company-pseudo-tooltip-unless-just-one-frontend-with-delay value)
                  (memq 'company-pseudo-tooltip-unless-just-one-frontend value)))
         (user-error "Pseudo tooltip frontend cannot be used more than once"))
    (and (or (and (memq 'company-preview-if-just-one-frontend value)
                  (memq 'company-preview-frontend value))
             (and (memq 'company-preview-if-just-one-frontend value)
                  (memq 'company-preview-common-frontend value))
             (and (memq 'company-preview-frontend value)
                  (memq 'company-preview-common-frontend value))
             )
         (user-error "Preview frontend cannot be used twice"))
    (and (memq 'company-echo value)
         (memq 'company-echo-metadata-frontend value)
         (user-error "Echo area cannot be used twice"))
    ;; Preview must come last.
    (dolist (f '(company-preview-if-just-one-frontend company-preview-frontend company-preview-common-frontend))
      (when (cdr (memq f value))
        (setq value (append (delq f value) (list f)))))
    (set variable value)))

(defcustom company-frontends '(company-pseudo-tooltip-unless-just-one-frontend
                               company-preview-if-just-one-frontend
                               company-echo-metadata-frontend)
  "The list of active frontends (visualizations).
Each frontend is a function that takes one argument.  It is called with
one of the following arguments:

`show': When the visualization should start.

`hide': When the visualization should end.

`update': When the data has been updated.

`pre-command': Before every command that is executed while the
visualization is active.

`post-command': After every command that is executed while the
visualization is active.

`unhide': When an asynchronous backend is waiting for its completions.
Only needed in frontends which hide their visualizations in `pre-command'
for technical reasons.

The visualized data is stored in `company-prefix', `company-candidates',
`company-common', `company-selection', `company-point' and
`company-search-string'."
  :set 'company-frontends-set
  :type '(repeat (choice (const :tag "echo" company-echo-frontend)
                         (const :tag "echo, strip common"
                                company-echo-strip-common-frontend)
                         (const :tag "show echo meta-data in echo"
                                company-echo-metadata-frontend)
                         (const :tag "pseudo tooltip"
                                company-pseudo-tooltip-frontend)
                         (const :tag "pseudo tooltip, multiple only"
                                company-pseudo-tooltip-unless-just-one-frontend)
                         (const :tag "pseudo tooltip, multiple only, delayed"
                                company-pseudo-tooltip-unless-just-one-frontend-with-delay)
                         (const :tag "preview" company-preview-frontend)
                         (const :tag "preview, unique only"
                                company-preview-if-just-one-frontend)
                         (const :tag "preview, common"
                                company-preview-common-frontend)
                         (function :tag "custom function" nil))))

(defcustom company-tooltip-limit 10
  "The maximum number of candidates in the tooltip."
  :type 'integer)

(defcustom company-tooltip-minimum 6
  "The minimum height of the tooltip.
If this many lines are not available, prefer to display the tooltip above."
  :type 'integer)

(defcustom company-tooltip-minimum-width 0
  "The minimum width of the tooltip's inner area.
This doesn't include the margins and the scroll bar."
  :type 'integer
  :package-version '(company . "0.8.0"))

(defcustom company-tooltip-maximum-width most-positive-fixnum
  "The maximum width of the tooltip's inner area.
This doesn't include the margins and the scroll bar."
  :type 'integer
  :package-version '(company . "0.9.5"))

(defcustom company-tooltip-width-grow-only nil
  "When non-nil, the tooltip width is not allowed to decrease."
  :type 'boolean
  :package-version '(company . "0.9.14"))

(defcustom company-tooltip-margin 1
  "Width of margin columns to show around the toolip."
  :type 'integer)

(defcustom company-tooltip-offset-display 'scrollbar
  "Method using which the tooltip displays scrolling position.
`scrollbar' means draw a scrollbar to the right of the items.
`lines' means wrap items in lines with \"before\" and \"after\" counters."
  :type '(choice (const :tag "Scrollbar" scrollbar)
                 (const :tag "Two lines" lines)))

(defcustom company-tooltip-align-annotations nil
  "When non-nil, align annotations to the right tooltip border."
  :type 'boolean
  :package-version '(company . "0.7.1"))

(defcustom company-tooltip-flip-when-above nil
  "Whether to flip the tooltip when it's above the current line."
  :type 'boolean
  :package-version '(company . "0.8.1"))

(defvar company-safe-backends
  '((company-abbrev . "Abbrev")
    (company-bbdb . "BBDB")
    (company-capf . "completion-at-point-functions")
    (company-clang . "Clang")
    (company-cmake . "CMake")
    (company-css . "CSS (obsolete backend)")
    (company-dabbrev . "dabbrev for plain text")
    (company-dabbrev-code . "dabbrev for code")
    (company-elisp . "Emacs Lisp (obsolete backend)")
    (company-etags . "etags")
    (company-files . "Files")
    (company-gtags . "GNU Global")
    (company-ispell . "Ispell")
    (company-keywords . "Programming language keywords")
    (company-nxml . "nxml (obsolete backend)")
    (company-oddmuse . "Oddmuse")
    (company-semantic . "Semantic")
    (company-tempo . "Tempo templates")))
(put 'company-safe-backends 'risky-local-variable t)

(defun company-safe-backends-p (backends)
  (and (consp backends)
       (not (cl-dolist (backend backends)
              (unless (if (consp backend)
                          (company-safe-backends-p backend)
                        (assq backend company-safe-backends))
                (cl-return t))))))

(defcustom company-backends `(company-bbdb
                              ,@(unless (version<= "26" emacs-version)
                                  (list 'company-nxml))
                              ,@(unless (version<= "26" emacs-version)
                                  (list 'company-css))
                              company-semantic
                              company-cmake
                              company-capf
                              company-clang
                              company-files
                              (company-dabbrev-code company-gtags company-etags
                               company-keywords)
                              company-oddmuse company-dabbrev)
  "The list of active backends (completion engines).

Only one backend is used at a time.  The choice depends on the order of
the items in this list, and on the values they return in response to the
`prefix' command (see below).  But a backend can also be a \"grouped\"
one (see below).

`company-begin-backend' can be used to start a specific backend,
`company-other-backend' will skip to the next matching backend in the list.

Each backend is a function that takes a variable number of arguments.
The first argument is the command requested from the backend.  It is one
of the following:

`prefix': The backend should return the text to be completed.  It must be
text immediately before point.  Returning nil from this command passes
control to the next backend.  The function should return `stop' if it
should complete but cannot (e.g. when in the middle of a symbol).
Instead of a string, the backend may return a cons (PREFIX . LENGTH)
where LENGTH is a number used in place of PREFIX's length when
comparing against `company-minimum-prefix-length'.  LENGTH can also
be just t, and in the latter case the test automatically succeeds.

`candidates': The second argument is the prefix to be completed.  The
return value should be a list of candidates that match the prefix.

Non-prefix matches are also supported (candidates that don't start with the
prefix, but match it in some backend-defined way).  Backends that use this
feature must disable cache (return t to `no-cache') and might also want to
respond to `match'.

Optional commands
=================

`sorted': Return t here to indicate that the candidates are sorted and will
not need to be sorted again.

`duplicates': If non-nil, company will take care of removing duplicates
from the list.

`no-cache': Usually company doesn't ask for candidates again as completion
progresses, unless the backend returns t for this command.  The second
argument is the latest prefix.

`ignore-case': Return t here if the backend returns case-insensitive
matches.  This value is used to determine the longest common prefix (as
used in `company-complete-common'), and to filter completions when fetching
them from cache.

`meta': The second argument is a completion candidate.  Return a (short)
documentation string for it.

`doc-buffer': The second argument is a completion candidate.  Return a
buffer with documentation for it.  Preferably use `company-doc-buffer'.  If
not all buffer contents pertain to this candidate, return a cons of buffer
and window start position.

`location': The second argument is a completion candidate.  Return a cons
of buffer and buffer location, or of file and line number where the
completion candidate was defined.

`annotation': The second argument is a completion candidate.  Return a
string to be displayed inline with the candidate in the popup.  If
duplicates are removed by company, candidates with equal string values will
be kept if they have different annotations.  For that to work properly,
backends should store the related information on candidates using text
properties.

`match': The second argument is a completion candidate.  Return a positive
integer, the index after the end of text matching `prefix' within the
candidate string.  Alternatively, return a list of (CHUNK-START
. CHUNK-END) elements, where CHUNK-START and CHUNK-END are indexes within
the candidate string.  The corresponding regions are be used when rendering
the popup.  This command only makes sense for backends that provide
non-prefix completion.

`require-match': If this returns t, the user is not allowed to enter
anything not offered as a candidate.  Please don't use that value in normal
backends.  The default value nil gives the user that choice with
`company-require-match'.  Return value `never' overrides that option the
other way around (using that value will indicate that the returned set of
completions is often incomplete, so this behavior will not be useful).

`init': Called once for each buffer. The backend can check for external
programs and files and load any required libraries.  Raising an error here
will show up in message log once, and the backend will not be used for
completion.

`post-completion': Called after a completion candidate has been inserted
into the buffer.  The second argument is the candidate.  Can be used to
modify it, e.g. to expand a snippet.

`kind': The second argument is a completion candidate.  Return a symbol
describing the kind of the candidate.  Refer to `company-vscode-icons-mapping'
for the possible values.

The backend should return nil for all commands it does not support or
does not know about.  It should also be callable interactively and use
`company-begin-backend' to start itself in that case.

Grouped backends
================

An element of `company-backends' can also be a list of backends.  The
completions from backends in such groups are merged, but only from those
backends which return the same `prefix'.

If a backend command takes a candidate as an argument (e.g. `meta'), the
call is dispatched to the backend the candidate came from.  In other
cases (except for `duplicates' and `sorted'), the first non-nil value among
all the backends is returned.

The group can also contain keywords.  Currently, `:with' and `:separate'
keywords are defined.  If the group contains keyword `:with', the backends
listed after this keyword are ignored for the purpose of the `prefix'
command.  If the group contains keyword `:separate', the candidates that
come from different backends are sorted separately in the combined list.

Asynchronous backends
=====================

The return value of each command can also be a cons (:async . FETCHER)
where FETCHER is a function of one argument, CALLBACK.  When the data
arrives, FETCHER must call CALLBACK and pass it the appropriate return
value, as described above.  That call must happen in the same buffer as
where completion was initiated.

True asynchronous operation is only supported for command `candidates', and
only during idle completion.  Other commands will block the user interface,
even if the backend uses the asynchronous calling convention."
  :type `(repeat
          (choice
           :tag "backend"
           ,@(mapcar (lambda (b) `(const :tag ,(cdr b) ,(car b)))
                     company-safe-backends)
           (symbol :tag "User defined")
           (repeat :tag "Merged backends"
                   (choice :tag "backend"
                           ,@(mapcar (lambda (b)
                                       `(const :tag ,(cdr b) ,(car b)))
                                     company-safe-backends)
                           (const :tag "With" :with)
                           (symbol :tag "User defined"))))))

(put 'company-backends 'safe-local-variable 'company-safe-backends-p)

(defcustom company-transformers nil
  "Functions to change the list of candidates received from backends.

Each function gets called with the return value of the previous one.
The first one gets passed the list of candidates, already sorted and
without duplicates."
  :type '(choice
          (const :tag "None" nil)
          (const :tag "Sort by occurrence" (company-sort-by-occurrence))
          (const :tag "Sort by backend importance"
                 (company-sort-by-backend-importance))
          (const :tag "Prefer case sensitive prefix"
                 (company-sort-prefer-same-case-prefix))
          (repeat :tag "User defined" (function))))

(defcustom company-completion-started-hook nil
  "Hook run when company starts completing.
The hook is called with one argument that is non-nil if the completion was
started manually."
  :type 'hook)

(defcustom company-completion-cancelled-hook nil
  "Hook run when company cancels completing.
The hook is called with one argument that is non-nil if the completion was
aborted manually."
  :type 'hook)

(defcustom company-completion-finished-hook nil
  "Hook run when company successfully completes.
The hook is called with the selected candidate as an argument.

If you indend to use it to post-process candidates from a specific
backend, consider using the `post-completion' command instead."
  :type 'hook)

(defcustom company-after-completion-hook nil
  "Hook run at the end of completion, successful or not.
The hook is called with one argument which is either a string or a symbol."
  :type 'hook)

(defcustom company-minimum-prefix-length 3
  "The minimum prefix length for idle completion."
  :type '(integer :tag "prefix length"))

(defcustom company-abort-manual-when-too-short nil
  "If enabled, cancel a manually started completion when the prefix gets
shorter than both `company-minimum-prefix-length' and the length of the
prefix it was started from."
  :type 'boolean
  :package-version '(company . "0.8.0"))

(defcustom company-abort-on-unique-match t
  "If non-nil, typing a full unique match aborts completion.

You can still invoke `company-complete' manually to run the
`post-completion' handler, though.

If it's nil, completion will remain active until you type a prefix that
doesn't match anything or finish it manually, e.g. with RET."
  :type 'boolean)

(defcustom company-require-match 'company-explicit-action-p
  "If enabled, disallow non-matching input.
This can be a function do determine if a match is required.

This can be overridden by the backend, if it returns t or `never' to
`require-match'.  `company-auto-commit' also takes precedence over this."
  :type '(choice (const :tag "Off" nil)
                 (function :tag "Predicate function")
                 (const :tag "On, if user interaction took place"
                        'company-explicit-action-p)
                 (const :tag "On" t)))

(define-obsolete-variable-alias
  'company-auto-complete
  'company-auto-commit
  "0.9.14")

(defcustom company-auto-commit nil
  "Determines whether to auto-commit.
If this is enabled, all characters from `company-auto-commit-chars'
trigger insertion of the selected completion candidate.
This can also be a function."
  :type '(choice (const :tag "Off" nil)
                 (function :tag "Predicate function")
                 (const :tag "On, if user interaction took place"
                        'company-explicit-action-p)
                 (const :tag "On" t))
  :package-version '(company . "0.9.14"))

(define-obsolete-variable-alias
  'company-auto-complete-chars
  'company-auto-commit-chars
  "0.9.14")

(defcustom company-auto-commit-chars '(?\  ?\) ?.)
  "Determines which characters trigger auto-commit.
See `company-auto-commit'.  If this is a string, each character in it
triggers auto-commit.  If it is a list of syntax description characters (see
`modify-syntax-entry'), characters with any of those syntaxes do that.

This can also be a function, which is called with the new input and should
return non-nil if company should auto-commit.

A character that is part of a valid completion never triggers auto-commit."
  :type '(choice (string :tag "Characters")
                 (set :tag "Syntax"
                      (const :tag "Whitespace" ?\ )
                      (const :tag "Symbol" ?_)
                      (const :tag "Opening parentheses" ?\()
                      (const :tag "Closing parentheses" ?\))
                      (const :tag "Word constituent" ?w)
                      (const :tag "Punctuation." ?.)
                      (const :tag "String quote." ?\")
                      (const :tag "Paired delimiter." ?$)
                      (const :tag "Expression quote or prefix operator." ?\')
                      (const :tag "Comment starter." ?<)
                      (const :tag "Comment ender." ?>)
                      (const :tag "Character-quote." ?/)
                      (const :tag "Generic string fence." ?|)
                      (const :tag "Generic comment fence." ?!))
                 (function :tag "Predicate function"))
  :package-version '(company . "0.9.14"))

(defcustom company-idle-delay .2
  "The idle delay in seconds until completion starts automatically.
The prefix still has to satisfy `company-minimum-prefix-length' before that
happens.  The value of nil means no idle completion."
  :type '(choice (const :tag "never (nil)" nil)
                 (const :tag "immediate (0)" 0)
                 (function :tag "Predicate function")
                 (number :tag "seconds")))

(defcustom company-tooltip-idle-delay .5
  "The idle delay in seconds until tooltip is shown when using
`company-pseudo-tooltip-unless-just-one-frontend-with-delay'."
  :type '(choice (const :tag "never (nil)" nil)
                 (const :tag "immediate (0)" 0)
                 (number :tag "seconds")))

(defcustom company-begin-commands '(self-insert-command
                                    org-self-insert-command
                                    orgtbl-self-insert-command
                                    c-scope-operator
                                    c-electric-colon
                                    c-electric-lt-gt
                                    c-electric-slash)
  "A list of commands after which idle completion is allowed.
If this is t, it can show completions after any command except a few from a
pre-defined list.  See `company-idle-delay'.

Alternatively, any command with a non-nil `company-begin' property is
treated as if it was on this list."
  :type '(choice (const :tag "Any command" t)
                 (const :tag "Self insert command" '(self-insert-command))
                 (repeat :tag "Commands" function))
  :package-version '(company . "0.8.4"))

(defcustom company-continue-commands '(not save-buffer save-some-buffers
                                           save-buffers-kill-terminal
                                           save-buffers-kill-emacs
                                           completion-at-point)
  "A list of commands that are allowed during completion.
If this is t, or if `company-begin-commands' is t, any command is allowed.
Otherwise, the value must be a list of symbols.  If it starts with `not',
the cdr is the list of commands that abort completion.  Otherwise, all
commands except those in that list, or in `company-begin-commands', or
commands in the `company-' namespace, abort completion."
  :type '(choice (const :tag "Any command" t)
                 (cons  :tag "Any except"
                        (const not)
                        (repeat :tag "Commands" function))
                 (repeat :tag "Commands" function)))

(defun company-custom--set-quick-access (option value)
  "Re-bind quick-access key sequences on OPTION VALUE change."
  (when (boundp 'company-active-map)
    (company-keymap--unbind-quick-access company-active-map))
  (when (boundp 'company-search-map)
    (company-keymap--unbind-quick-access company-search-map))
  (custom-set-default option value)
  (when (boundp 'company-active-map)
    (company-keymap--bind-quick-access company-active-map))
  (when (boundp 'company-search-map)
    (company-keymap--bind-quick-access company-search-map)))

(defcustom company-quick-access-keys '("1" "2" "3" "4" "5" "6" "7" "8" "9" "0")
  "Character strings used as a part of quick-access key sequences.
To change this value without Customize interface, use `customize-set-variable'.

To change the quick-access key sequences modifier, customize
`company-quick-access-modifier'.

If `company-show-quick-access' is non-nil, show quick-access hints
beside the candidates."
  :set #'company-custom--set-quick-access
  :type '(choice
          (const :tag "Digits" ("1" "2" "3" "4" "5" "6" "7" "8" "9" "0"))
          (const :tag "QWERTY home row" ("a" "s" "d" "f" "g" "h" "j" "k" "l" ";"))
          ;; TODO un-comment on removal of `M-n' `company--select-next-and-warn'.
          ;; (const :tag "Dvorak home row" ("a" "o" "e" "u" "i" "d" "h" "t" "n" "s"))
          (repeat :tag "User defined" string))
  :package-version '(company . "0.9.14"))

(defcustom company-quick-access-modifier 'meta
  "Modifier key used for quick-access keys sequences.
To change this value without Customize interface, use `customize-set-variable'.
See `company-quick-access-keys' for more details."
  :set #'company-custom--set-quick-access
  :type '(choice (const :tag "Meta key" meta)
                 (const :tag "Super key" super)
                 (const :tag "Hyper key" hyper)
                 (const :tag "Control key" control))
  :package-version '(company . "0.9.14"))

(defun company-keymap--quick-access-modifier ()
  "Return string representation of the `company-quick-access-modifier'."
  (if-let ((modifier (assoc-default company-quick-access-modifier
                                    '((meta . "M")
                                      (super . "s")
                                      (hyper . "H")
                                      (control . "C")))))
      modifier
    (warn "company-quick-access-modifier value unknown: %S"
          company-quick-access-modifier)
    "M"))

(defun company-keymap--unbind-quick-access (keymap)
  (let ((modifier (company-keymap--quick-access-modifier)))
    (dolist (key company-quick-access-keys)
      (let ((key-seq (company-keymap--kbd-quick-access modifier key)))
        (when (equal (lookup-key keymap key-seq) 'company-complete-quick-access)
          (define-key keymap key-seq nil))))))

(defun company-keymap--bind-quick-access (keymap)
  (let ((modifier (company-keymap--quick-access-modifier)))
    (dolist (key company-quick-access-keys)
      (let ((key-seq (company-keymap--kbd-quick-access modifier key)))
        (if (lookup-key keymap key-seq)
            (warn "Key sequence %s already bound" (key-description key-seq))
          (define-key keymap key-seq #'company-complete-quick-access))))))

(defun company-keymap--kbd-quick-access (modifier key)
  (kbd (format "%s-%s" modifier key)))

(define-obsolete-variable-alias
  'company-show-numbers
  'company-show-quick-access
  "0.9.14")

(defcustom company-show-quick-access nil
  "If non-nil, show quick-access hints beside the candidates.

For a tooltip frontend, non-nil value enables a column with the hints
on the right side of the tooltip, unless the configured value is `left'.

To change the quick-access key bindings, customize `company-quick-access-keys'
and `company-quick-access-modifier'.

To change the shown quick-access hints, customize
`company-quick-access-hint-function'."
  :type '(choice (const :tag "off" nil)
                 (const :tag "left" left)
                 (const :tag "on" t)))

(defcustom company-show-numbers-function nil
  "Function called to get quick-access numbers for the first ten candidates.

The function receives the candidate number (starting from 1) and should
return a string prefixed with one space."
  :type 'function)
(make-obsolete-variable
 'company-show-numbers-function
 "use `company-quick-access-hint-function' instead,
but adjust the expected values appropriately."
 "0.9.14")

(defcustom company-quick-access-hint-function #'company-quick-access-hint-key
  "Function called to get quick-access hints for the candidates.

The function receives a candidate's 0-based number
and should return a string.
See `company-show-quick-access' for more details."
  :type 'function)

(defun company-quick-access-hint-key (candidate)
  "Return a quick-access key for the CANDIDATE number.
This is a default value of `company-quick-access-hint-function'."
  (if company-show-numbers-function
      (funcall company-show-numbers-function (1+ candidate))
    (format "%s"
            (if (< candidate (length company-quick-access-keys))
                (nth candidate company-quick-access-keys)
              ""))))

(defcustom company-selection-wrap-around nil
  "If enabled, selecting item before first or after last wraps around."
  :type '(choice (const :tag "off" nil)
                 (const :tag "on" t)))

(defcustom company-async-redisplay-delay 0.005
  "Delay before redisplay when fetching candidates asynchronously.

You might want to set this to a higher value if your backends respond
quickly, to avoid redisplaying twice per each typed character."
  :type 'number)

(defvar company-async-wait 0.03
  "Pause between checks to see if the value's been set when turning an
asynchronous call into synchronous.")

(defvar company-async-timeout 2
  "Maximum wait time for a value to be set during asynchronous call.")

;;; mode ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar company-mode-map (make-sparse-keymap)
  "Keymap used by `company-mode'.")

(defvar company-active-map
  (let ((keymap (make-sparse-keymap)))
    (define-key keymap "\e\e\e" 'company-abort)
    (define-key keymap "\C-g" 'company-abort)
    (define-key keymap (kbd "M-n") 'company--select-next-and-warn)
    (define-key keymap (kbd "M-p") 'company--select-previous-and-warn)
    (define-key keymap (kbd "C-n") 'company-select-next-or-abort)
    (define-key keymap (kbd "C-p") 'company-select-previous-or-abort)
    (define-key keymap (kbd "<down>") 'company-select-next-or-abort)
    (define-key keymap (kbd "<up>") 'company-select-previous-or-abort)
    (define-key keymap [remap scroll-up-command] 'company-next-page)
    (define-key keymap [remap scroll-down-command] 'company-previous-page)
    (define-key keymap [down-mouse-1] 'ignore)
    (define-key keymap [down-mouse-3] 'ignore)
    (define-key keymap [mouse-1] 'company-complete-mouse)
    (define-key keymap [mouse-3] 'company-select-mouse)
    (define-key keymap [up-mouse-1] 'ignore)
    (define-key keymap [up-mouse-3] 'ignore)
    (define-key keymap [return] 'company-complete-selection)
    (define-key keymap (kbd "RET") 'company-complete-selection)
    (define-key keymap [tab] 'company-complete-common)
    (define-key keymap (kbd "TAB") 'company-complete-common)
    (define-key keymap (kbd "<f1>") 'company-show-doc-buffer)
    (define-key keymap (kbd "C-h") 'company-show-doc-buffer)
    (define-key keymap "\C-w" 'company-show-location)
    (define-key keymap "\C-s" 'company-search-candidates)
    (define-key keymap "\C-\M-s" 'company-filter-candidates)
    (company-keymap--bind-quick-access keymap)
     keymap)
  "Keymap that is enabled during an active completion.")

(defvar company--disabled-backends nil)

(defun company--select-next-and-warn (&optional arg)
  (interactive "p")
  (company--warn-changed-binding)
  (company-select-next arg))

(defun company--select-previous-and-warn (&optional arg)
  (interactive "p")
  (company--warn-changed-binding)
  (company-select-previous arg))

(defun company--warn-changed-binding ()
  (interactive)
  (run-with-idle-timer
   0.01 nil
   (lambda ()
     (message "Warning: default bindings are being changed to C-n and C-p"))))

(defun company-init-backend (backend)
  (and (symbolp backend)
       (not (fboundp backend))
       (ignore-errors (require backend nil t)))
  (cond
   ((symbolp backend)
    (condition-case err
        (progn
          (funcall backend 'init)
          (put backend 'company-init t))
      (error
       (put backend 'company-init 'failed)
       (unless (memq backend company--disabled-backends)
         (message "Company backend '%s' could not be initialized:\n%s"
                  backend (error-message-string err)))
       (cl-pushnew backend company--disabled-backends)
       nil)))
   ;; No initialization for lambdas.
   ((functionp backend) t)
   (t ;; Must be a list.
    (cl-dolist (b backend)
      (unless (keywordp b)
        (company-init-backend b))))))

(defun company--maybe-init-backend (backend)
  (or (not (symbolp backend))
      (eq t (get backend 'company-init))
      (unless (get backend 'company-init)
        (company-init-backend backend))))

(defcustom company-lighter-base "company"
  "Base string to use for the `company-mode' lighter."
  :type 'string
  :package-version '(company . "0.8.10"))

(defvar company-lighter '(" "
                          (company-candidates
                           (:eval
                            (if (consp company-backend)
                                (when company-selection
                                  (company--group-lighter (nth company-selection
                                                               company-candidates)
                                                          company-lighter-base))
                              (symbol-name company-backend)))
                           company-lighter-base))
  "Mode line lighter for Company.

The value of this variable is a mode line template as in
`mode-line-format'.")

(put 'company-lighter 'risky-local-variable t)

;;;###autoload
(define-minor-mode company-mode
  "\"complete anything\"; is an in-buffer completion framework.
Completion starts automatically, depending on the values
`company-idle-delay' and `company-minimum-prefix-length'.

Completion can be controlled with the commands:
`company-complete-common', `company-complete-selection', `company-complete',
`company-select-next', `company-select-previous'.  If these commands are
called before `company-idle-delay', completion will also start.

Completions can be searched with `company-search-candidates' or
`company-filter-candidates'.  These can be used while completion is
inactive, as well.

The completion data is retrieved using `company-backends' and displayed
using `company-frontends'.  If you want to start a specific backend, call
it interactively or use `company-begin-backend'.

By default, the completions list is sorted alphabetically, unless the
backend chooses otherwise, or `company-transformers' changes it later.

regular keymap (`company-mode-map'):

\\{company-mode-map}
keymap during active completions (`company-active-map'):

\\{company-active-map}"
  :lighter company-lighter
  (if company-mode
      (progn
        (add-hook 'pre-command-hook 'company-pre-command nil t)
        (add-hook 'post-command-hook 'company-post-command nil t)
        (add-hook 'yas-keymap-disable-hook 'company--active-p nil t)
        (mapc 'company-init-backend company-backends))
    (remove-hook 'pre-command-hook 'company-pre-command t)
    (remove-hook 'post-command-hook 'company-post-command t)
    (remove-hook 'yas-keymap-disable-hook 'company--active-p t)
    (company-cancel)
    (kill-local-variable 'company-point)))

(defcustom company-global-modes t
  "Modes for which `company-mode' mode is turned on by `global-company-mode'.
If nil, means no modes.  If t, then all major modes have it turned on.
If a list, it should be a list of `major-mode' symbol names for which
`company-mode' should be automatically turned on.  The sense of the list is
negated if it begins with `not'.  For example:
 (c-mode c++-mode)
means that `company-mode' is turned on for buffers in C and C++ modes only.
 (not message-mode)
means that `company-mode' is always turned on except in `message-mode' buffers."
  :type '(choice (const :tag "none" nil)
                 (const :tag "all" t)
                 (set :menu-tag "mode specific" :tag "modes"
                      :value (not)
                      (const :tag "Except" not)
                      (repeat :inline t (symbol :tag "mode")))))

;;;###autoload
(define-globalized-minor-mode global-company-mode company-mode company-mode-on)

(defun company-mode-on ()
  (when (and (not (or noninteractive (eq (aref (buffer-name) 0) ?\s)))
             (cond ((eq company-global-modes t)
                    t)
                   ((eq (car-safe company-global-modes) 'not)
                    (not (memq major-mode (cdr company-global-modes))))
                   (t (memq major-mode company-global-modes))))
    (company-mode 1)))

(defsubst company-assert-enabled ()
  (unless company-mode
    (company-uninstall-map)
    (user-error "Company not enabled")))

;;; keymaps ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-my-keymap nil)

(defvar company-emulation-alist '((t . nil)))

(defun company-enable-overriding-keymap (keymap)
  (company-uninstall-map)
  (setq company-my-keymap keymap))

(defun company-ensure-emulation-alist ()
  (unless (eq 'company-emulation-alist (car emulation-mode-map-alists))
    (setq emulation-mode-map-alists
          (cons 'company-emulation-alist
                (delq 'company-emulation-alist emulation-mode-map-alists)))))

(defun company-install-map ()
  (unless (or (cdar company-emulation-alist)
              (null company-my-keymap))
    (setf (cdar company-emulation-alist) company-my-keymap)))

(defun company-uninstall-map ()
  (setf (cdar company-emulation-alist) nil))

(defun company--company-command-p (keys)
  "Checks if the keys are part of company's overriding keymap"
  (or (equal [company-dummy-event] keys)
      (commandp (lookup-key company-my-keymap keys))))

;; To avoid warnings in Emacs < 26.
(declare-function line-number-display-width "indent.c")

(defun company--posn-col-row (posn)
  (let ((col (car (posn-col-row posn)))
        ;; `posn-col-row' doesn't work well with lines of different height.
        ;; `posn-actual-col-row' doesn't handle multiple-width characters.
        (row (cdr (or (posn-actual-col-row posn)
                      ;; When position is non-visible for some reason.
                      (posn-col-row posn)))))
    (when (bound-and-true-p display-line-numbers)
      (cl-decf col (+ 2 (line-number-display-width))))
    (cons (+ col (window-hscroll)) row)))

(defun company--col-row (&optional pos)
  (company--posn-col-row (posn-at-point pos)))

(defun company--row (&optional pos)
  (cdr (company--col-row pos)))

;;; backends ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-backend nil)

(defun company-grab (regexp &optional expression limit)
  (when (looking-back regexp limit)
    (or (match-string-no-properties (or expression 0)) "")))

(defun company-grab-line (regexp &optional expression)
  "Return a match string for REGEXP if it matches text before point.
If EXPRESSION is non-nil, return the match string for the respective
parenthesized expression in REGEXP.
Matching is limited to the current line."
  (let ((inhibit-field-text-motion t))
    (company-grab regexp expression (point-at-bol))))

(defun company-grab-symbol ()
  "If point is at the end of a symbol, return it.
Otherwise, if point is not inside a symbol, return an empty string."
  (if (looking-at "\\_>")
      (buffer-substring (point) (save-excursion (skip-syntax-backward "w_")
                                                (point)))
    (unless (and (char-after) (memq (char-syntax (char-after)) '(?w ?_)))
      "")))

(defun company-grab-word ()
  "If point is at the end of a word, return it.
Otherwise, if point is not inside a symbol, return an empty string."
  (if (looking-at "\\>")
      (buffer-substring (point) (save-excursion (skip-syntax-backward "w")
                                                (point)))
    (unless (and (char-after) (eq (char-syntax (char-after)) ?w))
      "")))

(defun company-grab-symbol-cons (idle-begin-after-re &optional max-len)
  "Return a string SYMBOL or a cons (SYMBOL . t).
SYMBOL is as returned by `company-grab-symbol'.  If the text before point
matches IDLE-BEGIN-AFTER-RE, return it wrapped in a cons."
  (let ((symbol (company-grab-symbol)))
    (when symbol
      (save-excursion
        (forward-char (- (length symbol)))
        (if (looking-back idle-begin-after-re (if max-len
                                                  (- (point) max-len)
                                                (line-beginning-position)))
            (cons symbol t)
          symbol)))))

(defun company-in-string-or-comment ()
  "Return non-nil if point is within a string or comment."
  (let ((ppss (syntax-ppss)))
    (or (car (setq ppss (nthcdr 3 ppss)))
        (car (setq ppss (cdr ppss)))
        (nth 3 ppss))))

(defun company-call-backend (&rest args)
  (company--force-sync #'company-call-backend-raw args company-backend))

(defun company--force-sync (fun args backend)
  (let ((value (apply fun args)))
    (if (not (eq (car-safe value) :async))
        value
      (let ((res 'trash)
            (start (time-to-seconds)))
        (funcall (cdr value)
                 (lambda (result) (setq res result)))
        (while (eq res 'trash)
          (if (> (- (time-to-seconds) start) company-async-timeout)
              (error "Company: backend %s async timeout with args %s"
                     backend args)
            ;; XXX: Reusing the trick from company--fetch-candidates here
            ;; doesn't work well: sit-for isn't a good fit when we want to
            ;; ignore pending input (results in too many calls).
            ;; FIXME: We should deal with this by standardizing on a kind of
            ;; Future object that knows how to sync itself. In most cases (but
            ;; not all), by calling accept-process-output, probably.
            (sleep-for company-async-wait)))
        res))))

(defun company-call-backend-raw (&rest args)
  (condition-case-unless-debug err
      (if (functionp company-backend)
          (apply company-backend args)
        (apply #'company--multi-backend-adapter company-backend args))
    (user-error (user-error
                 "Company: backend %s user-error: %s"
                 company-backend (error-message-string err)))
    (error (error "Company: backend %s error \"%s\" with args %s"
                  company-backend (error-message-string err) args))))

(defun company--multi-backend-adapter (backends command &rest args)
  (let ((backends (cl-loop for b in backends
                           when (or (keywordp b)
                                    (company--maybe-init-backend b))
                           collect b))
        (separate (memq :separate backends)))

    (when (eq command 'prefix)
      (setq backends (butlast backends (length (member :with backends)))))

    (setq backends (cl-delete-if #'keywordp backends))

    (pcase command
      (`candidates
       (company--multi-backend-adapter-candidates backends (car args) separate))
      (`sorted separate)
      (`duplicates (not separate))
      ((or `prefix `ignore-case `no-cache `require-match)
       (let (value)
         (cl-dolist (backend backends)
           (when (setq value (company--force-sync
                              backend (cons command args) backend))
             (when (and (eq command 'ignore-case)
                        (eq value 'keep-prefix))
               (setq value t))
             (cl-return value)))))
      (_
       (let ((arg (car args)))
         (when (> (length arg) 0)
           (let ((backend (or (get-text-property 0 'company-backend arg)
                              (car backends))))
             (apply backend command args))))))))

(defun company--multi-backend-adapter-candidates (backends prefix separate)
  (let ((pairs (cl-loop for backend in backends
                        when (equal (company--prefix-str
                                     (let ((company-backend backend))
                                       (company-call-backend 'prefix)))
                                    prefix)
                        collect (cons (funcall backend 'candidates prefix)
                                      (company--multi-candidates-mapper
                                       backend
                                       separate
                                       ;; Small perf optimization: don't tag the
                                       ;; candidates received from the first
                                       ;; backend in the group.
                                       (not (eq backend (car backends))))))))
    (company--merge-async pairs (lambda (values) (apply #'append values)))))

(defun company--multi-candidates-mapper (backend separate tag)
  (lambda (candidates)
    (when separate
      (let ((company-backend backend))
        (setq candidates
              (company--preprocess-candidates candidates))))
    (when tag
      (setq candidates
            (mapcar
             (lambda (str)
               (propertize str 'company-backend backend))
             candidates)))
    candidates))

(defun company--merge-async (pairs merger)
  (let ((async (cl-loop for pair in pairs
                        thereis
                        (eq :async (car-safe (car pair))))))
    (if (not async)
        (funcall merger (cl-loop for (val . mapper) in pairs
                                 collect (funcall mapper val)))
      (cons
       :async
       (lambda (callback)
         (let* (lst
                (pending (mapcar #'car pairs))
                (finisher (lambda ()
                            (unless pending
                              (funcall callback
                                       (funcall merger
                                                (nreverse lst)))))))
           (dolist (pair pairs)
             (push nil lst)
             (let* ((cell lst)
                    (val (car pair))
                    (mapper (cdr pair))
                    (this-finisher (lambda (res)
                                     (setq pending (delq val pending))
                                     (setcar cell (funcall mapper res))
                                     (funcall finisher))))
               (if (not (eq :async (car-safe val)))
                   (funcall this-finisher val)
                 (let ((fetcher (cdr val)))
                   (funcall fetcher this-finisher)))))))))))

(defun company--prefix-str (prefix)
  (or (car-safe prefix) prefix))

;;; completion mechanism ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-prefix nil)

(defvar-local company-candidates nil)

(defvar-local company-candidates-length nil)

(defvar-local company-candidates-cache nil)

(defvar-local company-candidates-predicate nil)

(defvar-local company-common nil)

(defvar company-selection-default 0
  "The default value for `company-selection'.")
(defvar-local company-selection company-selection-default)

(defvar-local company-selection-changed nil)

(defvar-local company--manual-action nil
  "Non-nil, if manual completion took place.")

(defvar-local company--manual-prefix nil)

(defvar-local company--point-max nil)

(defvar-local company-point nil)

(defvar company-timer nil)
(defvar company-tooltip-timer nil)

(defsubst company-strip-prefix (str)
  (substring str (length company-prefix)))

(defun company--insert-candidate (candidate)
  (when (> (length candidate) 0)
    (setq candidate (substring-no-properties candidate))
    ;; XXX: Return value we check here is subject to change.
    (if (eq (company-call-backend 'ignore-case) 'keep-prefix)
        (insert (company-strip-prefix candidate))
      (unless (equal company-prefix candidate)
        (delete-region (- (point) (length company-prefix)) (point))
        (insert candidate)))))

(defmacro company-with-candidate-inserted (candidate &rest body)
  "Evaluate BODY with CANDIDATE temporarily inserted.
This is a tool for backends that need candidates inserted before they
can retrieve meta-data for them."
  (declare (indent 1))
  `(let ((inhibit-modification-hooks t)
         (inhibit-point-motion-hooks t)
         (modified-p (buffer-modified-p)))
     (company--insert-candidate ,candidate)
     (unwind-protect
         (progn ,@body)
       (delete-region company-point (point))
       (set-buffer-modified-p modified-p))))

(defun company-explicit-action-p ()
  "Return whether explicit completion action was taken by the user."
  (or company--manual-action
      company-selection-changed))

(defun company-reformat (candidate)
  ;; company-ispell needs this, because the results are always lower-case
  ;; It's mory efficient to fix it only when they are displayed.
  ;; FIXME: Adopt the current text's capitalization instead?
  (if (eq (company-call-backend 'ignore-case) 'keep-prefix)
      (let ((prefix (company--clean-string company-prefix)))
        (concat prefix (substring candidate (length prefix))))
    candidate))

(defun company--should-complete ()
  (and (eq company-idle-delay 'now)
       (not (or buffer-read-only
                overriding-local-map))
       ;; Check if in the middle of entering a key combination.
       (or (equal (this-command-keys-vector) [])
           (not (keymapp (key-binding (this-command-keys-vector)))))
       (not (and transient-mark-mode mark-active))))

(defun company--should-continue ()
  (or (eq t company-begin-commands)
      (eq t company-continue-commands)
      (if (eq 'not (car company-continue-commands))
          (not (memq this-command (cdr company-continue-commands)))
        (or (memq this-command company-begin-commands)
            (memq this-command company-continue-commands)
            (and (symbolp this-command)
                 (string-match-p "\\`company-" (symbol-name this-command)))))))

(defun company-call-frontends (command)
  (cl-loop for frontend in company-frontends collect
           (condition-case-unless-debug err
               (funcall frontend command)
             (error (error "Company: frontend %s error \"%s\" on command %s"
                           frontend (error-message-string err) command)))))

(defun company-set-selection (selection &optional force-update)
  "Set SELECTION for company candidates.
This will update `company-selection' and related variable.
Only update when the current selection is changed, but optionally always
update if FORCE-UPDATE."
  (when selection
    (let* ((offset (if company-selection-default 0 1))
           (company-candidates-length
            (+ company-candidates-length offset)))
      (setq selection (+ selection offset))
      (setq selection
            (if company-selection-wrap-around
                (mod selection company-candidates-length)
              (max 0 (min (1- company-candidates-length) selection))))
      (setq selection (unless (< selection offset)
                        (- selection offset)))))
  (when (or force-update (not (equal selection company-selection)))
    (setq company-selection selection
          company-selection-changed t)
    (company-call-frontends 'update)))

(defun company--group-lighter (candidate base)
  (let ((backend (or (get-text-property 0 'company-backend candidate)
                     (cl-some (lambda (x) (and (not (keywordp x)) x))
                              company-backend))))
    (when (and backend (symbolp backend))
      (let ((name (replace-regexp-in-string "company-\\|-company" ""
                                            (symbol-name backend))))
        (format "%s-<%s>" base name)))))

(defun company-update-candidates (candidates)
  (setq company-candidates-length (length candidates))
  (if company-selection-changed
      ;; Try to restore the selection
      (let ((selected (and company-selection
                           (nth company-selection company-candidates))))
        (setq company-candidates candidates)
        (when selected
          (setq company-selection 0)
          (catch 'found
            (while candidates
              (let ((candidate (pop candidates)))
                (when (and (string= candidate selected)
                           (equal (company-call-backend 'annotation candidate)
                                  (company-call-backend 'annotation selected)))
                  (throw 'found t)))
              (cl-incf company-selection))
            (setq company-selection company-selection-default
                  company-selection-changed nil))))
    (setq company-selection company-selection-default
          company-candidates candidates))
  ;; Calculate common.
  (let ((completion-ignore-case (company-call-backend 'ignore-case)))
    ;; We want to support non-prefix completion, so filtering is the
    ;; responsibility of each respective backend, not ours.
    ;; On the other hand, we don't want to replace non-prefix input in
    ;; `company-complete-common', unless there's only one candidate.
    (setq company-common
          (if (cdr company-candidates)
              (let ((common (try-completion "" company-candidates)))
                (when (string-prefix-p company-prefix common
                                       completion-ignore-case)
                  common))
            (car company-candidates)))))

(defun company-calculate-candidates (prefix ignore-case)
  (let ((candidates (cdr (assoc prefix company-candidates-cache))))
    (or candidates
        (when company-candidates-cache
          (let ((len (length prefix))
                (completion-ignore-case ignore-case)
                prev)
            (cl-dotimes (i (1+ len))
              (when (setq prev (cdr (assoc (substring prefix 0 (- len i))
                                           company-candidates-cache)))
                (setq candidates (all-completions prefix prev))
                (cl-return t)))))
        ;; No cache match, call the backend.
        (let ((refresh-timer (run-with-timer company-async-redisplay-delay
                                             nil #'company--sneaky-refresh)))
          (setq candidates (company--preprocess-candidates
                            (company--fetch-candidates prefix)))
          ;; If the backend is synchronous, no chance for the timer to run.
          (cancel-timer refresh-timer)
          ;; Save in cache.
          (push (cons prefix candidates) company-candidates-cache)))
    ;; Only now apply the predicate and transformers.
    (company--postprocess-candidates candidates)))

(defun company--unique-match-p (candidates prefix ignore-case)
  (and candidates
       (not (cdr candidates))
       (eq t (compare-strings (car candidates) nil nil
                              prefix nil nil ignore-case))))

(defun company--fetch-candidates (prefix)
  (let* ((non-essential (not (company-explicit-action-p)))
         (inhibit-redisplay t)
         (c (if (or company-selection-changed
                    ;; FIXME: This is not ideal, but we have not managed to deal
                    ;; with these situations in a better way yet.
                    (company-require-match-p))
                (company-call-backend 'candidates prefix)
              (company-call-backend-raw 'candidates prefix))))
    (if (not (eq (car c) :async))
        c
      (let ((res 'none))
        (funcall
         (cdr c)
         (lambda (candidates)
           (when (eq res 'none)
             (push 'company-foo unread-command-events))
           (setq res candidates)))
        (if (company--flyspell-workaround-p)
            (while (and (eq res 'none)
                        (not (input-pending-p)))
              (sleep-for company-async-wait))
          (while (and (eq res 'none)
                      (sit-for 0.5 t))))
        (while (member (car unread-command-events)
                       '(company-foo (t . company-foo)))
          (pop unread-command-events))
        (prog1
            (and (consp res) res)
          (setq res 'exited))))))

(defun company--sneaky-refresh ()
  (when company-candidates (company-call-frontends 'unhide))
  (let (inhibit-redisplay)
    (redisplay))
  (when company-candidates (company-call-frontends 'pre-command)))

(defun company--flyspell-workaround-p ()
  ;; https://debbugs.gnu.org/23980
  (and (bound-and-true-p flyspell-mode)
       (version< emacs-version "27")))

(defun company--preprocess-candidates (candidates)
  (cl-assert (cl-every #'stringp candidates))
  (unless (company-call-backend 'sorted)
    (setq candidates (sort candidates 'string<)))
  (when (company-call-backend 'duplicates)
    (company--strip-duplicates candidates))
  candidates)

(defun company--postprocess-candidates (candidates)
  (when (or company-candidates-predicate company-transformers)
    (setq candidates (copy-sequence candidates)))
  (when company-candidates-predicate
    (setq candidates (cl-delete-if-not company-candidates-predicate candidates)))
  (company--transform-candidates candidates))

(defun company--strip-duplicates (candidates)
  (let ((c2 candidates)
        (extras 'unk))
    (while c2
      (setcdr c2
              (let ((str (pop c2)))
                (while (let ((str2 (car c2)))
                         (if (not (equal str str2))
                             (progn
                               (setq extras 'unk)
                               nil)
                           (when (eq extras 'unk)
                             (setq extras (list (cons (company-call-backend
                                                       'annotation str)
                                                      (company-call-backend
                                                       'kind str)))))
                           (let ((extra2 (cons (company-call-backend
                                                'annotation str2)
                                               (company-call-backend
                                                'kind str2))))
                             (if (member extra2 extras)
                                 t
                               (push extra2 extras)
                               nil))))
                  (pop c2))
                c2)))))

(defun company--transform-candidates (candidates)
  (let ((c candidates))
    (dolist (tr company-transformers)
      (setq c (funcall tr c)))
    c))

(defcustom company-occurrence-weight-function
  #'company-occurrence-prefer-closest-above
  "Function to weigh matches in `company-sort-by-occurrence'.
It's called with three arguments: cursor position, the beginning and the
end of the match."
  :type '(choice
          (const :tag "First above point, then below point"
                 company-occurrence-prefer-closest-above)
          (const :tag "Prefer closest in any direction"
                 company-occurrence-prefer-any-closest)))

(defvar company-vscode-icons-mapping
  '((array . "symbol-array.svg")
    (boolean . "symbol-boolean.svg")
    (class . "symbol-class.svg")
    (color . "symbol-color.svg")
    (constant . "symbol-constant.svg")
    (constructor . "symbol-method.svg")
    (enum-member . "symbol-enumerator-member.svg")
    (enum . "symbol-enumerator.svg")
    (event . "symbol-event.svg")
    (field . "symbol-field.svg")
    (file . "symbol-file.svg")
    (folder . "folder.svg")
    (interface . "symbol-interface.svg")
    (keyword . "symbol-keyword.svg")
    (method . "symbol-method.svg")
    (function . "symbol-method.svg")
    (module . "symbol-namespace.svg")
    (numeric . "symbol-numeric.svg")
    (operator . "symbol-operator.svg")
    (parameter . "symbol-parameter.svg")
    (property . "symbol-property.svg")
    (ruler . "symbol-ruler.svg")
    (snippet . "symbol-snippet.svg")
    (string . "symbol-string.svg")
    (struct . "symbol-structure.svg")
    (text . "symbol-key.svg")
    (value . "symbol-enumerator.svg")
    (variable . "symbol-variable.svg")
    (t . "symbol-misc.svg")))

(defconst company-icons-root
  (file-name-as-directory
   (expand-file-name "icons"
                     (file-name-directory (or load-file-name buffer-file-name)))))

(defcustom company-icon-size '(auto-scale . 16)
  "Size of icons indicating completion kind in the popup."
  :type '(choice (integer :tag "Size in pixels" :value 16)
                 (cons :tag "Size in pixels, scaled 2x on HiDPI screens"
                       (const auto-scale)
                       (integer :value 16))))

(defcustom company-icon-margin 2
  "Width of the margin that shows the icons, in characters."
  :type 'integer)

(defun company--render-icons-margin (icon-mapping root-dir candidate selected)
  (if-let ((ws (window-system))
           (candidate candidate)
           (kind (company-call-backend 'kind candidate))
           (icon-file (or (alist-get kind icon-mapping)
                          (alist-get t icon-mapping))))
      (let* ((bkg (face-attribute (if selected
                                      'company-tooltip-selection
                                    'company-tooltip)
                                  :background))
             (dfw (default-font-width))
             (icon-size (cond
                         ((integerp company-icon-size)
                          company-icon-size)
                         ;; XXX: Also consider smooth scaling, e.g. using
                         ;; (aref (font-info (face-font 'default)) 2)
                         ((and (consp company-icon-size)
                               (eq 'auto-scale (car company-icon-size)))
                          (let ((base-size (cdr company-icon-size))
                                (dfh (default-font-height)))
                            (min
                             (if (> dfh (* 2 base-size))
                                 (* 2 base-size)
                               base-size)
                             (* company-icon-margin dfw))))))
             (spec (list 'image
                         :file (expand-file-name icon-file root-dir)
                         :type 'svg
                         :width icon-size
                         :height icon-size
                         :ascent 'center
                         :background (unless (eq bkg 'unspecified)
                                       bkg)))
             (spacer-px-width (- (* company-icon-margin dfw) icon-size)))
        (concat
         (propertize " " 'display spec)
         (propertize (company-space-string (1- company-icon-margin))
                     'display `(space . (:width (,spacer-px-width))))))
    nil))

(defun company-vscode-dark-icons-margin (candidate selected)
  "Margin function which returns icons from vscode's dark theme."
  (company--render-icons-margin company-vscode-icons-mapping
                                (expand-file-name "vscode-dark" company-icons-root)
                                candidate
                                selected))

(defun company-vscode-light-icons-margin (candidate selected)
  "Margin function which returns icons from vscode's light theme."
  (company--render-icons-margin company-vscode-icons-mapping
                                (expand-file-name "vscode-light" company-icons-root)
                                candidate
                                selected))

(defcustom company-text-icons-mapping
  '((array "a" font-lock-type-face)
    (boolean "b" font-lock-builtin-face)
    (class "c" font-lock-type-face)
    (color "#" success)
    (constant "c" font-lock-constant-face)
    (enum-member "e" font-lock-builtin-face)
    (enum "e" font-lock-builtin-face)
    (field "f" font-lock-variable-name-face)
    (file "f" font-lock-string-face)
    (folder "d" font-lock-doc-face)
    (interface "i" font-lock-type-face)
    (keyword "k" font-lock-keyword-face)
    (method "m" font-lock-function-name-face)
    (function "f" font-lock-function-name-face)
    (module "{" font-lock-type-face)
    (numeric "n" font-lock-builtin-face)
    (operator "o" font-lock-comment-delimiter-face)
    (parameter "p" font-lock-builtin-face)
    (property "p" font-lock-variable-name-face)
    (ruler "r" shadow)
    (snippet "S" font-lock-string-face)
    (string "s" font-lock-string-face)
    (struct "%" font-lock-variable-name-face)
    (text "w" shadow)
    (value "v" font-lock-builtin-face)
    (variable "v" font-lock-variable-name-face)
    (t "." shadow))
  "Mapping of the text icons.
The format should be an alist of (KIND . CONF) where CONF is a list of the
form (ICON FG BG) which is used to propertize the icon to be shown for a
candidate of kind KIND. FG can either be color string or a face from which
we can get a color string (using the :foreground face-property). BG must be
of the same form as FG or a cons cell of (BG . BG-WHEN-SELECTED) which each
should be of the same form as FG.

The only mandatory element in CONF is ICON, you can omit both the FG and BG
fields without issue.

When BG is omitted and `company-text-icons-add-background' is non-nil, a BG
color will be generated using a gradient between the active tooltip color and
the FG color."
  :type 'list)

(defcustom company-text-face-extra-attributes '(:weight bold)
  "Additional attributes to add to text icons' faces.
If non-nil, an anonymous face will be generated.
Only affects `company-text-icons-margin'."
  :type 'list)

(defcustom company-text-icons-format " %s "
  "Format string for printing the text icons."
  :type 'string)

(defcustom company-text-icons-add-background nil
  "When non-nil, generate a background color for text icons when none is given.
See `company-text-icons-mapping'."
  :type 'boolean)

(defun company-text-icons-margin (candidate selected)
  "Margin function which returns unicode icons."
  (when-let ((candidate candidate)
             (kind (company-call-backend 'kind candidate))
             (conf (or (alist-get kind company-text-icons-mapping)
                       (alist-get t company-text-icons-mapping))))
    (cl-destructuring-bind (icon &optional fg bg) conf
      (propertize
       (format company-text-icons-format icon)
       'face
       (company-text-icons--face fg bg selected)))))

(declare-function color-rgb-to-hex "color")
(declare-function color-gradient "color")

(defun company-text-icons--extract-property (face property)
  "Try to extract PROPERTY from FACE.
If FACE isn't a valid face return FACE as is. If FACE doesn't have
PROPERTY return nil."
  (if (facep face)
      (let ((value (face-attribute face property)))
        (unless (eq value 'unspecified)
          value))
    face))

(defun company-text-icons--face (fg bg selected)
  (let ((fg-color (company-text-icons--extract-property fg :foreground)))
    `(,@company-text-face-extra-attributes
      ,@(and fg-color
             (list :foreground fg-color))
      ,@(let* ((bg-is-cons (consp bg))
               (bg (if bg-is-cons (if selected (cdr bg) (car bg)) bg))
               (bg-color (company-text-icons--extract-property bg :background))
               (tooltip-bg-color (company-text-icons--extract-property
                                  (if selected
                                      'company-tooltip-selection
                                    'company-tooltip)
                                  :background)))
          (cond
           ((and company-text-icons-add-background selected
                 (not bg-is-cons) bg-color tooltip-bg-color)
            ;; Adjust the coloring of the background when *selected* but user hasn't
            ;; specified an alternate background color for selected item icons.
            (list :background
                  (apply #'color-rgb-to-hex
                         (nth 0 (color-gradient (color-name-to-rgb tooltip-bg-color)
                                                (color-name-to-rgb bg-color)
                                                2)))))
           (bg
            ;; When background is configured we use it as is, even if it doesn't
            ;; constrast well with other candidates when selected.
            (and bg-color
                 (list :background bg-color)))
           ((and company-text-icons-add-background fg-color tooltip-bg-color)
            ;; Lastly attempt to generate a background from the foreground.
            (list :background
                  (apply #'color-rgb-to-hex
                         (nth 0 (color-gradient (color-name-to-rgb tooltip-bg-color)
                                                (color-name-to-rgb fg-color)
                                                10))))))))))

(defcustom company-dot-icons-format "● "
  "Format string for `company-dot-icons-margin'."
  :type 'string)

(defun company-dot-icons-margin (candidate selected)
  "Margin function that uses a colored dot to display completion kind."
  (when-let ((kind (company-call-backend 'kind candidate))
             (conf (or (assoc-default kind company-text-icons-mapping)
                       (assoc-default t company-text-icons-mapping))))
    (cl-destructuring-bind (_icon &optional fg bg) conf
      (propertize company-dot-icons-format
                  'face
                  (company-text-icons--face fg bg selected)))))

(defun company-detect-icons-margin (candidate selected)
  "Margin function which picks the appropriate icon set automatically."
  (if (and (display-graphic-p)
           (image-type-available-p 'svg))
      (cl-case (frame-parameter nil 'background-mode)
        ('light (company-vscode-light-icons-margin candidate selected))
        (t (company-vscode-dark-icons-margin candidate selected)))
    (company-text-icons-margin candidate selected)))

(defcustom company-format-margin-function #'company-detect-icons-margin
  "Function to format the margin.
It accepts 2 params `candidate' and `selected' and can be used for
inserting prefix/image before the completion items. Typically, the
functions call the backends with `kind' and then insert the appropriate
image for the returned kind image. Function is called with (nil nil) to get
the default margin."
  :type '(choice
          (const :tag "Disabled" nil)
          (const :tag "Detect icons theme base on conditions" company-detect-icons-margin)
          (const :tag "Text characters as icons" company-text-icons-margin)
          (const :tag "Colored dots as icons" company-dot-icons-margin)
          (const :tag "VScode dark icons theme" company-vscode-dark-icons-margin)
          (const :tag "VScode light icons theme" company-vscode-light-icons-margin)
          (function :tag "Custom icon function.")))

(defun company-occurrence-prefer-closest-above (pos match-beg match-end)
  "Give priority to the matches above point, then those below point."
  (if (< match-beg pos)
      (- pos match-end)
    (- match-beg (window-start))))

(defun company-occurrence-prefer-any-closest (pos _match-beg match-end)
  "Give priority to the matches closest to the point."
  (abs (- pos match-end)))

(defun company-sort-by-occurrence (candidates)
  "Sort CANDIDATES according to their occurrences.
Searches for each in the currently visible part of the current buffer and
prioritizes the matches according to `company-occurrence-weight-function'.
The rest of the list is appended unchanged.
Keywords and function definition names are ignored."
  (let* ((w-start (window-start))
         (w-end (window-end))
         (start-point (point))
         occurs
         (noccurs
          (save-excursion
            (cl-delete-if
             (lambda (candidate)
               (goto-char w-start)
               (when (and (not (equal candidate ""))
                          (search-forward candidate w-end t)
                          ;; ^^^ optimize for large lists where most elements
                          ;; won't have a match.
                          (catch 'done
                            (goto-char (1- start-point))
                            (while (search-backward candidate w-start t)
                              (when (save-match-data
                                      (company--occurrence-predicate))
                                (throw 'done t)))
                            (goto-char start-point)
                            (while (search-forward candidate w-end t)
                              (when (save-match-data
                                      (company--occurrence-predicate))
                                (throw 'done t)))))
                 (push
                  (cons candidate
                        (funcall company-occurrence-weight-function
                                 start-point
                                 (match-beginning 0)
                                 (match-end 0)))
                  occurs)
                 t))
             candidates))))
    (nconc
     (mapcar #'car (sort occurs (lambda (e1 e2) (<= (cdr e1) (cdr e2)))))
     noccurs)))

(defun company--occurrence-predicate ()
  (defvar comint-last-prompt)
  (let ((beg (match-beginning 0))
        (end (match-end 0))
        (comint-last-prompt (bound-and-true-p comint-last-prompt)))
    (save-excursion
      (goto-char end)
      ;; Workaround for python-shell-completion-at-point's behavior:
      ;; https://github.com/company-mode/company-mode/issues/759
      ;; https://github.com/company-mode/company-mode/issues/549
      (when (derived-mode-p 'inferior-python-mode)
        (let ((lbp (line-beginning-position)))
          (setq comint-last-prompt (cons lbp lbp))))
      (and (not (memq (get-text-property (1- (point)) 'face)
                      '(font-lock-function-name-face
                        font-lock-keyword-face)))
           (let ((prefix (company--prefix-str
                          (company-call-backend 'prefix))))
             (and (stringp prefix)
                  (= (length prefix) (- end beg))))))))

(defun company-sort-by-backend-importance (candidates)
  "Sort CANDIDATES as two priority groups.
If `company-backend' is a function, do nothing.  If it's a list, move
candidates from backends before keyword `:with' to the front.  Candidates
from the rest of the backends in the group, if any, will be left at the end."
  (if (functionp company-backend)
      candidates
    (let ((low-priority (cdr (memq :with company-backend))))
      (if (null low-priority)
          candidates
        (sort candidates
              (lambda (c1 c2)
                (and
                 (let ((b2 (get-text-property 0 'company-backend c2)))
                   (and b2 (memq b2 low-priority)))
                 (let ((b1 (get-text-property 0 'company-backend c1)))
                   (or (not b1) (not (memq b1 low-priority)))))))))))

(defun company-sort-prefer-same-case-prefix (candidates)
  "Prefer CANDIDATES with the exact same prefix.
If a backend returns case insensitive matches, candidates with the an exact
prefix match (same case) will be prioritized."
  (cl-loop for candidate in candidates
           if (string-prefix-p company-prefix candidate)
           collect candidate into same-case
           else collect candidate into other-case
           finally return (append same-case other-case)))

(defun company-idle-begin (buf win tick pos)
  (and (eq buf (current-buffer))
       (eq win (selected-window))
       (eq tick (buffer-chars-modified-tick))
       (eq pos (point))
       (when (company-auto-begin)
         (let ((this-command 'company-idle-begin))
           (company-post-command)))))

(defun company-auto-begin ()
  (and company-mode
       (not company-candidates)
       (let ((company-idle-delay 'now))
         (condition-case-unless-debug err
             (let ((inhibit-quit nil))
               (company--perform)
               ;; Return non-nil if active.
               company-candidates)
           (error (message "Company: An error occurred in auto-begin")
                  (message "%s" (error-message-string err))
                  (company-cancel))
           (quit (company-cancel))))))

;;;###autoload
(defun company-manual-begin ()
  (interactive)
  (company-assert-enabled)
  (setq company--manual-action t)
  (unwind-protect
      (let ((company-minimum-prefix-length 0))
        (or company-candidates
            (company-auto-begin)))
    (unless company-candidates
      (setq company--manual-action nil))))

(defun company-other-backend (&optional backward)
  (interactive (list current-prefix-arg))
  (company-assert-enabled)
  (let* ((after (if company-backend
                    (cdr (member company-backend company-backends))
                  company-backends))
         (before (cdr (member company-backend (reverse company-backends))))
         (next (if backward
                   (append before (reverse after))
                 (append after (reverse before)))))
    (company-cancel)
    (cl-dolist (backend next)
      (when (ignore-errors (company-begin-backend backend))
        (cl-return t))))
  (unless company-candidates
    (user-error "No other backend")))

(defun company-require-match-p ()
  (let ((backend-value (company-call-backend 'require-match)))
    (or (eq backend-value t)
        (and (not (eq backend-value 'never))
             (if (functionp company-require-match)
                 (funcall company-require-match)
               (eq company-require-match t))))))

(defun company-auto-commit-p (input)
  "Return non-nil if INPUT should trigger auto-commit."
  (and (if (functionp company-auto-commit)
           (funcall company-auto-commit)
         company-auto-commit)
       (if (functionp company-auto-commit-chars)
           (funcall company-auto-commit-chars input)
         (if (consp company-auto-commit-chars)
             (memq (char-syntax (string-to-char input))
                   company-auto-commit-chars)
           (string-match (regexp-quote (substring input 0 1))
                          company-auto-commit-chars)))))

(defun company--incremental-p ()
  (and (> (point) company-point)
       (> (point-max) company--point-max)
       (not (eq this-command 'backward-delete-char-untabify))
       (equal (buffer-substring (- company-point (length company-prefix))
                                company-point)
              company-prefix)))

(defun company--continue-failed (new-prefix)
  (cond
   ((and (or (not (company-require-match-p))
             ;; Don't require match if the new prefix
             ;; doesn't continue the old one, and the latter was a match.
             (not (stringp new-prefix))
             (<= (length new-prefix) (length company-prefix)))
         (member company-prefix company-candidates))
    ;; Last input was a success,
    ;; but we're treating it as an abort + input anyway,
    ;; like the `unique' case below.
    (company-cancel 'non-unique))
   ((company-require-match-p)
    ;; Wrong incremental input, but required match.
    (delete-char (- company-point (point)))
    (ding)
    (message "Matching input is required")
    company-candidates)
   (t (company-cancel))))

(defun company--good-prefix-p (prefix)
  (and (stringp (company--prefix-str prefix)) ;excludes 'stop
       (or (eq (cdr-safe prefix) t)
           (let ((len (or (cdr-safe prefix) (length prefix))))
             (if company--manual-prefix
                 (or (not company-abort-manual-when-too-short)
                     ;; Must not be less than minimum or initial length.
                     (>= len (min company-minimum-prefix-length
                                  (length company--manual-prefix))))
               (>= len company-minimum-prefix-length))))))

(defun company--continue ()
  (when (company-call-backend 'no-cache company-prefix)
    ;; Don't complete existing candidates, fetch new ones.
    (setq company-candidates-cache nil))
  (let* ((new-prefix (company-call-backend 'prefix))
         (ignore-case (company-call-backend 'ignore-case))
         (c (when (and (company--good-prefix-p new-prefix)
                       (setq new-prefix (company--prefix-str new-prefix))
                       (= (- (point) (length new-prefix))
                          (- company-point (length company-prefix))))
              (company-calculate-candidates new-prefix ignore-case))))
    (cond
     ((and company-abort-on-unique-match
           (company--unique-match-p c new-prefix ignore-case))
      ;; Handle it like completion was aborted, to differentiate from user
      ;; calling one of Company's commands to insert the candidate,
      ;; not to trigger template expansion, etc.
      (company-cancel 'unique))
     ((consp c)
      ;; incremental match
      (setq company-prefix new-prefix)
      (company-update-candidates c)
      c)
     ((and (characterp last-command-event)
           (company-auto-commit-p (string last-command-event)))
      ;; auto-commit
      (save-excursion
        (goto-char company-point)
        (company-complete-selection)
        nil))
     ((not (company--incremental-p))
      (company-cancel))
     (t (company--continue-failed new-prefix)))))

(defun company--begin-new ()
  (let (prefix c)
    (cl-dolist (backend (if company-backend
                            ;; prefer manual override
                            (list company-backend)
                          company-backends))
      (setq prefix
            (if (or (symbolp backend)
                    (functionp backend))
                (when (company--maybe-init-backend backend)
                  (let ((company-backend backend))
                    (company-call-backend 'prefix)))
              (company--multi-backend-adapter backend 'prefix)))
      (when prefix
        (when (company--good-prefix-p prefix)
          (let ((ignore-case (company-call-backend 'ignore-case)))
            (setq company-prefix (company--prefix-str prefix)
                  company-backend backend
                  c (company-calculate-candidates company-prefix ignore-case))
            (cond
             ((and company-abort-on-unique-match
                   (company--unique-match-p c company-prefix ignore-case)
                   (if company--manual-action
                       ;; If `company-manual-begin' was called, the user
                       ;; really wants something to happen.  Otherwise...
                       (ignore (message "Sole completion"))
                     t))
              ;; ...abort and run the hooks, e.g. to clear the cache.
              (company-cancel 'unique))
             ((null c)
              (when company--manual-action
                (message "No completion found")))
             (t ;; We got completions!
              (when company--manual-action
                (setq company--manual-prefix prefix))
              (company-update-candidates c)
              (run-hook-with-args 'company-completion-started-hook
                                  (company-explicit-action-p))
              (company-call-frontends 'show)))))
        (cl-return c)))))

(defun company--perform ()
  (cond
   (company-candidates
    (company--continue))
   ((company--should-complete)
    (company--begin-new)))
  (if (not company-candidates)
      (setq company-backend nil)
    (setq company-point (point)
          company--point-max (point-max))
    (company-ensure-emulation-alist)
    (company-enable-overriding-keymap company-active-map)
    (company-call-frontends 'update)))

(defun company-cancel (&optional result)
  (let ((prefix company-prefix)
        (backend company-backend))
    (setq company-backend nil
          company-prefix nil
          company-candidates nil
          company-candidates-length nil
          company-candidates-cache nil
          company-candidates-predicate nil
          company-common nil
          company-selection company-selection-default
          company-selection-changed nil
          company--manual-action nil
          company--manual-prefix nil
          company--point-max nil
          company-point nil)
    (when company-timer
      (cancel-timer company-timer))
    (company-echo-cancel t)
    (company-search-mode 0)
    (company-call-frontends 'hide)
    (company-enable-overriding-keymap nil)
    (when prefix
      (if (stringp result)
          (let ((company-backend backend))
            (run-hook-with-args 'company-completion-finished-hook result)
            (company-call-backend 'post-completion result))
        (run-hook-with-args 'company-completion-cancelled-hook result))
      (run-hook-with-args 'company-after-completion-hook result)))
  ;; Make return value explicit.
  nil)

(defun company-abort ()
  (interactive)
  (company-cancel 'abort))

(defun company-finish (result)
  (company--insert-candidate result)
  (company-cancel result))

(defsubst company-keep (command)
  (and (symbolp command) (get command 'company-keep)))

(defun company--active-p ()
  company-candidates)

(defun company-pre-command ()
  (company--electric-restore-window-configuration)
  (unless (company-keep this-command)
    (condition-case-unless-debug err
        (when company-candidates
          (company-call-frontends 'pre-command)
          (unless (company--should-continue)
            (company-abort)))
      (error (message "Company: An error occurred in pre-command")
             (message "%s" (error-message-string err))
             (company-cancel))))
  (when company-timer
    (cancel-timer company-timer)
    (setq company-timer nil))
  (company-echo-cancel t)
  (company-uninstall-map))

(defun company-post-command ()
  (when (and company-candidates
             (null this-command))
    ;; Happens when the user presses `C-g' while inside
    ;; `flyspell-post-command-hook', for example.
    ;; Or any other `post-command-hook' function that can call `sit-for',
    ;; or any quittable timer function.
    (company-abort)
    (setq this-command 'company-abort))
  (unless (company-keep this-command)
    (condition-case-unless-debug err
        (progn
          (unless (equal (point) company-point)
            (let (company-idle-delay) ; Against misbehavior while debugging.
              (company--perform)))
          (if company-candidates
              (company-call-frontends 'post-command)
            (let ((delay (company--idle-delay)))
             (and (numberp delay)
                  (not defining-kbd-macro)
                  (company--should-begin)
                  (setq company-timer
                        (run-with-timer delay nil
                                        'company-idle-begin
                                        (current-buffer) (selected-window)
                                        (buffer-chars-modified-tick) (point)))))))
      (error (message "Company: An error occurred in post-command")
             (message "%s" (error-message-string err))
             (company-cancel))))
  (company-install-map))

(defun company--idle-delay ()
  (let ((delay
          (if (functionp company-idle-delay)
              (funcall company-idle-delay)
            company-idle-delay)))
    (if (memql delay '(t 0 0.0))
        0.01
      delay)))

(defvar company--begin-inhibit-commands '(company-abort
                                          company-complete-mouse
                                          company-complete
                                          company-complete-common
                                          company-complete-selection
                                          company-complete-tooltip-row)
  "List of commands after which idle completion is (still) disabled when
`company-begin-commands' is t.")

(defun company--should-begin ()
  (if (eq t company-begin-commands)
      (not (memq this-command company--begin-inhibit-commands))
    (or
     (memq this-command company-begin-commands)
     (and (symbolp this-command) (get this-command 'company-begin)))))

;;; search ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defcustom company-search-regexp-function #'regexp-quote
  "Function to construct the search regexp from input.
It's called with one argument, the current search input.  It must return
either a regexp without groups, or one where groups don't intersect and
each one wraps a part of the input string."
  :type '(choice
          (const :tag "Exact match" regexp-quote)
          (const :tag "Words separated with spaces" company-search-words-regexp)
          (const :tag "Words separated with spaces, in any order"
                 company-search-words-in-any-order-regexp)
          (const :tag "All characters in given order, with anything in between"
                 company-search-flex-regexp)))

(defvar-local company-search-string "")

(defvar company-search-lighter '(" "
                                 (company-search-filtering "Filter" "Search")
                                 ": \""
                                 company-search-string
                                 "\""))

(defvar-local company-search-filtering nil
  "Non-nil to filter the completion candidates by the search string")

(defvar-local company--search-old-selection 0)

(defvar-local company--search-old-changed nil)

(defun company-search-words-regexp (input)
  (mapconcat (lambda (word) (format "\\(%s\\)" (regexp-quote word)))
             (split-string input " +" t) ".*"))

(defun company-search-words-in-any-order-regexp (input)
  (let* ((words (mapcar (lambda (word) (format "\\(%s\\)" (regexp-quote word)))
                        (split-string input " +" t)))
         (permutations (company--permutations words)))
    (mapconcat (lambda (words)
                 (mapconcat #'identity words ".*"))
               permutations
               "\\|")))

(defun company-search-flex-regexp (input)
  (if (zerop (length input))
      ""
    (concat (regexp-quote (string (aref input 0)))
            (mapconcat (lambda (c)
                         (concat "[^" (string c) "]*"
                                 (regexp-quote (string c))))
                       (substring input 1) ""))))

(defun company--permutations (lst)
  (if (not lst)
      '(nil)
    ;; FIXME: Replace with `mapcan' in Emacs 26.
    (cl-mapcan
     (lambda (e)
       (mapcar (lambda (perm) (cons e perm))
               (company--permutations (cl-remove e lst :count 1))))
     lst)))

(defun company--search (text lines)
  (let ((re (funcall company-search-regexp-function text))
        (i 0))
    (cl-dolist (line lines)
      (when (string-match-p re line)
        (cl-return i))
      (cl-incf i))))

(defun company-search-printing-char ()
  (interactive)
  (company--search-assert-enabled)
  (let* ((event-type (event-basic-type last-command-event))
         (event-string (if (characterp event-type)
                           (string last-command-event)
                         ;; Handle key press on the keypad.
                         (let ((name (symbol-name event-type)))
                           (if (string-match "kp-\\([0-9]\\)" name)
                               (match-string 1 name)
                             (error "Unexpected printing char input")))))
         (ss (concat company-search-string event-string)))
    (when company-search-filtering
      (company--search-update-predicate ss))
    (company--search-update-string ss)))

(defun company--search-update-predicate (ss)
  (let* ((re (funcall company-search-regexp-function ss))
         (company-candidates-predicate
          (and (not (string= re ""))
               company-search-filtering
               (lambda (candidate) (string-match re candidate))))
         (cc (company-calculate-candidates company-prefix
                                           (company-call-backend 'ignore-case))))
    (unless cc (user-error "No match"))
    (company-update-candidates cc)))

(defun company--search-update-string (new)
  (let* ((selection (or company-selection 0))
         (pos (company--search new (nthcdr selection company-candidates))))
    (if (null pos)
        (ding)
      (setq company-search-string new)
      (company-set-selection (+ selection pos) t))))

(defun company--search-assert-input ()
  (company--search-assert-enabled)
  (when (string= company-search-string "")
    (user-error "Empty search string")))

(defun company-search-repeat-forward ()
  "Repeat the incremental search in completion candidates forward."
  (interactive)
  (company--search-assert-input)
  (let* ((selection (or company-selection 0))
         (pos (company--search company-search-string
                              (cdr (nthcdr selection company-candidates)))))
    (if (null pos)
        (ding)
      (company-set-selection (+ selection pos 1) t))))

(defun company-search-repeat-backward ()
  "Repeat the incremental search in completion candidates backwards."
  (interactive)
  (company--search-assert-input)
  (let* ((selection (or company-selection 0))
         (pos (company--search company-search-string
                              (nthcdr (- company-candidates-length
                                         selection)
                                      (reverse company-candidates)))))
    (if (null pos)
        (ding)
      (company-set-selection (- selection pos 1) t))))

(defun company-search-toggle-filtering ()
  "Toggle `company-search-filtering'."
  (interactive)
  (company--search-assert-enabled)
  (setq company-search-filtering (not company-search-filtering))
  (let ((ss company-search-string))
    (company--search-update-predicate ss)
    (company--search-update-string ss)))

(defun company-search-abort ()
  "Abort searching the completion candidates."
  (interactive)
  (company--search-assert-enabled)
  (company-search-mode 0)
  (company-set-selection company--search-old-selection t)
  (setq company-selection-changed company--search-old-changed))

(defun company-search-other-char ()
  (interactive)
  (company--search-assert-enabled)
  (company-search-mode 0)
  (company--unread-this-command-keys))

(defun company-search-delete-char ()
  (interactive)
  (company--search-assert-enabled)
  (if (string= company-search-string "")
      (ding)
    (let ((ss (substring company-search-string 0 -1)))
      (when company-search-filtering
        (company--search-update-predicate ss))
      (company--search-update-string ss))))

(defvar company-search-map
  (let ((i 0)
        (keymap (make-keymap)))
    (if (fboundp 'max-char)
        (set-char-table-range (nth 1 keymap) (cons #x100 (max-char))
                              'company-search-printing-char)
      (with-no-warnings
        ;; obsolete in Emacs 23
        (let ((l (generic-character-list))
              (table (nth 1 keymap)))
          (while l
            (set-char-table-default table (car l) 'company-search-printing-char)
            (setq l (cdr l))))))
    (define-key keymap [t] 'company-search-other-char)
    (while (< i ?\s)
      (define-key keymap (make-string 1 i) 'company-search-other-char)
      (cl-incf i))
    (while (< i 256)
      (define-key keymap (vector i) 'company-search-printing-char)
      (cl-incf i))
    (dotimes (i 10)
      (define-key keymap (kbd (format "<kp-%d>" i)) 'company-search-printing-char))
    (let ((meta-map (make-sparse-keymap)))
      (define-key keymap (char-to-string meta-prefix-char) meta-map)
      (define-key keymap [escape] meta-map))
    (define-key keymap (vector meta-prefix-char t) 'company-search-other-char)
    (define-key keymap (kbd "C-n") 'company-select-next-or-abort)
    (define-key keymap (kbd "C-p") 'company-select-previous-or-abort)
    (define-key keymap (kbd "M-n") 'company--select-next-and-warn)
    (define-key keymap (kbd "M-p") 'company--select-previous-and-warn)
    (define-key keymap (kbd "<down>") 'company-select-next-or-abort)
    (define-key keymap (kbd "<up>") 'company-select-previous-or-abort)
    (define-key keymap "\e\e\e" 'company-search-other-char)
    (define-key keymap [escape escape escape] 'company-search-other-char)
    (define-key keymap (kbd "DEL") 'company-search-delete-char)
    (define-key keymap [backspace] 'company-search-delete-char)
    (define-key keymap "\C-g" 'company-search-abort)
    (define-key keymap "\C-s" 'company-search-repeat-forward)
    (define-key keymap "\C-r" 'company-search-repeat-backward)
    (define-key keymap "\C-o" 'company-search-toggle-filtering)
    (company-keymap--bind-quick-access keymap)
    keymap)
  "Keymap used for incrementally searching the completion candidates.")

(define-minor-mode company-search-mode
  "Search mode for completion candidates.
Don't start this directly, use `company-search-candidates' or
`company-filter-candidates'."
  :lighter company-search-lighter
  (if company-search-mode
      (if (company-manual-begin)
          (progn
            (setq company--search-old-selection company-selection
                  company--search-old-changed company-selection-changed)
            (company-call-frontends 'update)
            (company-enable-overriding-keymap company-search-map))
        (setq company-search-mode nil))
    (kill-local-variable 'company-search-string)
    (kill-local-variable 'company-search-filtering)
    (kill-local-variable 'company--search-old-selection)
    (kill-local-variable 'company--search-old-changed)
    (when company-backend
      (company--search-update-predicate "")
      (company-call-frontends 'update))
    (company-enable-overriding-keymap company-active-map)))

(defun company--search-assert-enabled ()
  (company-assert-enabled)
  (unless company-search-mode
    (company-uninstall-map)
    (user-error "Company not in search mode")))

(defun company-search-candidates ()
  "Start searching the completion candidates incrementally.

\\<company-search-map>Search can be controlled with the commands:
- `company-search-repeat-forward' (\\[company-search-repeat-forward])
- `company-search-repeat-backward' (\\[company-search-repeat-backward])
- `company-search-abort' (\\[company-search-abort])
- `company-search-delete-char' (\\[company-search-delete-char])

Regular characters are appended to the search string.

Customize `company-search-regexp-function' to change how the input
is interpreted when searching.

The command `company-search-toggle-filtering' (\\[company-search-toggle-filtering])
uses the search string to filter the completion candidates."
  (interactive)
  (company-search-mode 1))

(defun company-filter-candidates ()
  "Start filtering the completion candidates incrementally.
This works the same way as `company-search-candidates' immediately
followed by `company-search-toggle-filtering'."
  (interactive)
  (company-search-mode 1)
  (setq company-search-filtering t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun company-select-next (&optional arg)
  "Select the next candidate in the list.

With ARG, move by that many elements.
When `company-selection-default' is nil, add a special pseudo candidates
meant for no selection."
  (interactive "p")
  (when (company-manual-begin)
    (let ((selection (+ (or arg 1)
                        (or company-selection
                            company-selection-default
                            -1))))
      (company-set-selection selection))))

(defun company-select-previous (&optional arg)
  "Select the previous candidate in the list.

With ARG, move by that many elements."
  (interactive "p")
  (company-select-next (if arg (- arg) -1)))

(defun company-select-next-or-abort (&optional arg)
  "Select the next candidate if more than one, else abort
and invoke the normal binding.

With ARG, move by that many elements."
  (interactive "p")
  (if (> company-candidates-length 1)
      (company-select-next arg)
    (company-abort)
    (company--unread-this-command-keys)))

(defun company-select-previous-or-abort (&optional arg)
  "Select the previous candidate if more than one, else abort
and invoke the normal binding.

With ARG, move by that many elements."
  (interactive "p")
  (if (> company-candidates-length 1)
      (company-select-previous arg)
    (company-abort)
    (company--unread-this-command-keys)))

(defun company-select-first ()
  "Select the first completion candidate."
  (interactive)
  (company-set-selection 0))

(defun company-select-last ()
  "Select the last completion candidate."
  (interactive)
  (company-set-selection (1- company-candidates-length)))

(defun company-next-page ()
  "Select the candidate one page further."
  (interactive)
  (when (company-manual-begin)
    (if (and company-selection-wrap-around
             (= company-selection (1- company-candidates-length)))
        (company-set-selection 0)
      (let (company-selection-wrap-around)
        (company-set-selection (+ company-selection
                                  company-tooltip-limit))))))

(defun company-previous-page ()
  "Select the candidate one page earlier."
  (interactive)
  (when (company-manual-begin)
    (if (and company-selection-wrap-around
             (zerop company-selection))
        (company-set-selection (1- company-candidates-length))
      (let (company-selection-wrap-around)
        (company-set-selection (- company-selection
                                  company-tooltip-limit))))))

(defun company--event-col-row (event)
  (company--posn-col-row (event-start event)))

(defvar company-mouse-event nil
  "Holds the mouse event from `company-select-mouse'.
For use in the `select-mouse' frontend action.  `let'-bound.")

(defun company-select-mouse (event)
  "Select the candidate picked by the mouse."
  (interactive "e")
  (or (let ((company-mouse-event event))
        (cl-some #'identity (company-call-frontends 'select-mouse)))
      (progn
        (company-abort)
        (company--unread-this-command-keys)
        nil)))

(defun company-complete-mouse (event)
  "Insert the candidate picked by the mouse."
  (interactive "e")
  (when (company-select-mouse event)
    (company-complete-selection)))

(defun company-complete-selection ()
  "Insert the selected candidate."
  (interactive)
  (when (and (company-manual-begin) company-selection)
    (let ((result (nth company-selection company-candidates)))
      (company-finish result))))

(defun company-complete-common ()
  "Insert the common part of all candidates."
  (interactive)
  (when (company-manual-begin)
    (if (and (not (cdr company-candidates))
             (equal company-common (car company-candidates)))
        (company-complete-selection)
      (company--insert-candidate company-common))))

(defun company-complete-common-or-cycle (&optional arg)
  "Insert the common part of all candidates, or select the next one.

With ARG, move by that many elements."
  (interactive "p")
  (when (company-manual-begin)
    (let ((tick (buffer-chars-modified-tick)))
      (call-interactively 'company-complete-common)
      (when (eq tick (buffer-chars-modified-tick))
        (let ((company-selection-wrap-around t)
              (current-prefix-arg arg))
          (call-interactively 'company-select-next))))))

(defun company-indent-or-complete-common (arg)
  "Indent the current line or region, or complete the common part."
  (interactive "P")
  (cond
   ((use-region-p)
    (indent-region (region-beginning) (region-end)))
   ((memq indent-line-function
          '(indent-relative indent-relative-maybe))
    (company-complete-common))
   ((let ((old-point (point))
          (old-tick (buffer-chars-modified-tick))
          (tab-always-indent t))
      (indent-for-tab-command arg)
      (when (and (eq old-point (point))
                 (eq old-tick (buffer-chars-modified-tick)))
        (company-complete-common))))))

(defun company-select-next-if-tooltip-visible-or-complete-selection ()
  "Insert selection if appropriate, or select the next candidate.
Insert selection if only preview is showing or only one candidate,
otherwise select the next candidate."
  (interactive)
  (if (and (company-tooltip-visible-p) (> company-candidates-length 1))
      (call-interactively 'company-select-next)
    (call-interactively 'company-complete-selection)))

;;;###autoload
(defun company-complete ()
  "Insert the common part of all candidates or the current selection.
The first time this is called, the common part is inserted, the second
time, or when the selection has been changed, the selected candidate is
inserted."
  (interactive)
  (when (company-manual-begin)
    (if (or company-selection-changed
            (and (eq real-last-command 'company-complete)
                 (eq last-command 'company-complete-common)))
        (call-interactively 'company-complete-selection)
      (call-interactively 'company-complete-common)
      (when company-candidates
        (setq this-command 'company-complete-common)))))

(define-obsolete-function-alias
  'company-complete-number
  'company-complete-tooltip-row
  "0.9.14")

(defun company-complete-tooltip-row (number)
  "Insert a candidate visible on the tooltip's row NUMBER.

Inserts one of the first ten candidates,
numbered according to the current scrolling position starting with 1.

When called interactively, uses the last typed digit, stripping the
modifiers and translating 0 into 10, so `M-1' inserts the first visible
candidate, and `M-0' insert to 10th one.

To show hint numbers beside the candidates, enable `company-show-quick-access'."
  (interactive
   (list (let* ((type (event-basic-type last-command-event))
                (char (if (characterp type)
                          ;; Number on the main row.
                          type
                        ;; Keypad number, if bound directly.
                        (car (last (string-to-list (symbol-name type))))))
                (number (- char ?0)))
           (if (zerop number) 10 number))))
  (company--complete-nth (1- number)))

(defun company-complete-quick-access (row)
  "Insert a candidate visible on a ROW matched by a quick-access key binding.
See `company-quick-access-keys' for more details."
  (interactive
   (list (let* ((event-type (event-basic-type last-command-event))
                (event-string (if (characterp event-type)
                                  (string event-type)
                                (error "Unexpected input"))))
           (cl-position event-string company-quick-access-keys :test 'equal))))
  (when row
    (company--complete-nth row)))

(defvar-local company-tooltip-offset 0
  "Current scrolling state of the tooltip.
Represented by the index of the first visible completion candidate
from the candidates list.")

(defun company--complete-nth (row)
  "Insert a candidate visible on the tooltip's zero-based ROW."
  (when (company-manual-begin)
    (and (or (< row 0) (>= row (- company-candidates-length
                                  company-tooltip-offset)))
         (user-error "No candidate on the row number %d" row))
    (company-finish (nth (+ row company-tooltip-offset)
                         company-candidates))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst company-space-strings-limit 100)

(defconst company-space-strings
  (let (lst)
    (dotimes (i company-space-strings-limit)
      (push (make-string (- company-space-strings-limit 1 i) ?\  ) lst))
    (apply 'vector lst)))

(defun company-space-string (len)
  (if (< len company-space-strings-limit)
      (aref company-space-strings len)
    (make-string len ?\ )))

(defun company-safe-substring (str from &optional to)
  (let ((bis buffer-invisibility-spec))
    (if (> from (string-width str))
        ""
      (with-temp-buffer
        (setq buffer-invisibility-spec bis)
        (insert str)
        (move-to-column from)
        (let ((beg (point)))
          (if to
              (progn
                (move-to-column to)
                (concat (buffer-substring beg (point))
                        (let ((padding (- to (current-column))))
                          (when (> padding 0)
                            (company-space-string padding)))))
            (buffer-substring beg (point-max))))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-last-metadata nil)

(defun company-fetch-metadata ()
  (let ((selected (nth (or company-selection 0) company-candidates)))
    (unless (eq selected (car company-last-metadata))
      (setq company-last-metadata
            (cons selected (company-call-backend 'meta selected))))
    (cdr company-last-metadata)))

(defun company-doc-buffer (&optional string)
  (with-current-buffer (get-buffer-create "*company-documentation*")
    (erase-buffer)
    (fundamental-mode)
    (when string
      (save-excursion
        (insert string)
        (visual-line-mode)))
    (current-buffer)))

(defvar company--electric-saved-window-configuration nil)

(defvar company--electric-commands
  '(scroll-other-window scroll-other-window-down mwheel-scroll)
  "List of Commands that won't break out of electric commands.")

(defun company--electric-restore-window-configuration ()
  "Restore window configuration (after electric commands)."
  (when (and company--electric-saved-window-configuration
             (not (memq this-command company--electric-commands)))
    (set-window-configuration company--electric-saved-window-configuration)
    (setq company--electric-saved-window-configuration nil)))

(defmacro company--electric-do (&rest body)
  (declare (indent 0) (debug t))
  `(when (company-manual-begin)
     (cl-assert (null company--electric-saved-window-configuration))
     (setq company--electric-saved-window-configuration (current-window-configuration))
     (let ((height (window-height))
           (row (company--row)))
       ,@body
       (and (< (window-height) height)
            (< (- (window-height) row 2) company-tooltip-limit)
            (recenter (- (window-height) row 2))))))

(defun company--unread-this-command-keys ()
  (when (> (length (this-command-keys)) 0)
    (setq unread-command-events (nconc
                                 (listify-key-sequence (this-command-keys))
                                 unread-command-events))
    (clear-this-command-keys t)))

(defun company-show-doc-buffer ()
  "Temporarily show the documentation buffer for the selection."
  (interactive)
  (let ((other-window-scroll-buffer)
        (selection (or company-selection 0)))
    (company--electric-do
      (let* ((selected (nth selection company-candidates))
             (doc-buffer (or (company-call-backend 'doc-buffer selected)
                             (user-error "No documentation available")))
             start)
        (when (consp doc-buffer)
          (setq start (cdr doc-buffer)
                doc-buffer (car doc-buffer)))
        (setq other-window-scroll-buffer (get-buffer doc-buffer))
        (let ((win (display-buffer doc-buffer t)))
          (set-window-start win (if start start (point-min))))))))
(put 'company-show-doc-buffer 'company-keep t)

(defun company-show-location ()
  "Temporarily display a buffer showing the selected candidate in context."
  (interactive)
  (let (other-window-scroll-buffer)
    (company--electric-do
      (let* ((selected (nth company-selection company-candidates))
             (location (company-call-backend 'location selected))
             (pos (or (cdr location) (user-error "No location available")))
             (buffer (or (and (bufferp (car location)) (car location))
                         (find-file-noselect (car location) t))))
        (setq other-window-scroll-buffer (get-buffer buffer))
        (with-selected-window (display-buffer buffer t)
          (save-restriction
            (widen)
            (if (bufferp (car location))
                (goto-char pos)
              (goto-char (point-min))
              (forward-line (1- pos))))
          (set-window-start nil (point)))))))
(put 'company-show-location 'company-keep t)

;;; package functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-callback nil)

(defun company-remove-callback (&optional ignored)
  (remove-hook 'company-completion-finished-hook company-callback t)
  (remove-hook 'company-completion-cancelled-hook 'company-remove-callback t)
  (remove-hook 'company-completion-finished-hook 'company-remove-callback t))

(defun company-begin-backend (backend &optional callback)
  "Start a completion at point using BACKEND."
  (interactive (let ((val (completing-read "Company backend: "
                                           obarray
                                           'functionp nil "company-")))
                 (when val
                   (list (intern val)))))
  (when (setq company-callback callback)
    (add-hook 'company-completion-finished-hook company-callback nil t))
  (add-hook 'company-completion-cancelled-hook 'company-remove-callback nil t)
  (add-hook 'company-completion-finished-hook 'company-remove-callback nil t)
  (setq company-backend backend)
  ;; Return non-nil if active.
  (or (company-manual-begin)
      (user-error "Cannot complete at point")))

(defun company-begin-with (candidates
                           &optional prefix-length require-match callback)
  "Start a completion at point.
CANDIDATES is the list of candidates to use and PREFIX-LENGTH is the length
of the prefix that already is in the buffer before point.
It defaults to 0.

CALLBACK is a function called with the selected result if the user
successfully completes the input.

Example: \(company-begin-with \\='\(\"foo\" \"foobar\" \"foobarbaz\"\)\)"
  (let ((begin-marker (copy-marker (point) t)))
    (company-begin-backend
     (lambda (command &optional arg &rest ignored)
       (pcase command
         (`prefix
          (when (equal (point) (marker-position begin-marker))
            (buffer-substring (- (point) (or prefix-length 0)) (point))))
         (`candidates
          (all-completions arg candidates))
         (`require-match
          require-match)))
     callback)))

(declare-function find-library-name "find-func")
(declare-function lm-version "lisp-mnt")

(defun company-version (&optional show-version)
  "Get the Company version as string.

If SHOW-VERSION is non-nil, show the version in the echo area."
  (interactive (list t))
  (with-temp-buffer
    (require 'find-func)
    (insert-file-contents (find-library-name "company"))
    (require 'lisp-mnt)
    (if show-version
        (message "Company version: %s" (lm-version))
      (lm-version))))

(defun company-diag ()
  "Pop a buffer with information about completions at point."
  (interactive)
  (let* ((bb company-backends)
         (mode (symbol-name major-mode))
         backend
         (prefix (cl-loop for b in bb
                          thereis (let ((company-backend b))
                                    (setq backend b)
                                    (company-call-backend 'prefix))))
         (c-a-p-f completion-at-point-functions)
         cc annotations)
    (when (or (stringp prefix) (consp prefix))
      (let ((company-backend backend))
        (condition-case nil
            (setq cc (company-call-backend 'candidates (company--prefix-str prefix))
                  annotations
                  (mapcar
                   (lambda (c) (cons c (company-call-backend 'annotation c)))
                   cc))
          (error (setq annotations 'error)))))
    (pop-to-buffer (get-buffer-create "*company-diag*"))
    (setq buffer-read-only nil)
    (erase-buffer)
    (insert (format "Emacs %s (%s) of %s on %s"
                    emacs-version system-configuration
                    (format-time-string "%Y-%m-%d" emacs-build-time)
                    emacs-build-system))
    (insert "\nCompany " (company-version) "\n\n")
    (insert "company-backends: " (pp-to-string bb))
    (insert "\n")
    (insert "Used backend: " (pp-to-string backend))
    (insert "\n")
    (when (if (listp backend)
              (memq 'company-capf backend)
            (eq backend 'company-capf))
      (insert "Value of c-a-p-f: "
              (pp-to-string c-a-p-f)))
    (insert "Major mode: " mode)
    (insert "\n")
    (insert "Prefix: " (pp-to-string prefix))
    (insert "\n")
    (insert "Completions:")
    (unless cc (insert " none"))
    (if (eq annotations 'error)
        (insert "(error fetching)")
      (save-excursion
        (dolist (c annotations)
          (insert "\n  " (prin1-to-string (car c)))
          (when (cdr c)
            (insert " " (prin1-to-string (cdr c)))))))
    (special-mode)))

;;; pseudo-tooltip ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company--tooltip-current-width 0)

(defun company-tooltip--lines-update-offset (selection num-lines limit)
  (cl-decf limit 2)
  (setq company-tooltip-offset
        (max (min selection company-tooltip-offset)
             (- selection -1 limit)))

  (when (<= company-tooltip-offset 1)
    (cl-incf limit)
    (setq company-tooltip-offset 0))

  (when (>= company-tooltip-offset (- num-lines limit 1))
    (cl-incf limit)
    (when (= selection (1- num-lines))
      (cl-decf company-tooltip-offset)
      (when (<= company-tooltip-offset 1)
        (setq company-tooltip-offset 0)
        (cl-incf limit))))

  limit)

(defun company-tooltip--simple-update-offset (selection _num-lines limit)
  (setq company-tooltip-offset
        (if (< selection company-tooltip-offset)
            selection
          (max company-tooltip-offset
               (- selection limit -1)))))

;;; propertize

(defun company-round-tab (arg)
  (* (/ (+ arg tab-width) tab-width) tab-width))

(defun company-plainify (str)
  (let ((prefix (get-text-property 0 'line-prefix str)))
    (when prefix ; Keep the original value unmodified, for no special reason.
      (setq str (concat prefix str))
      (remove-text-properties 0 (length str) '(line-prefix) str)))
  (let* ((pieces (split-string str "\t"))
         (copy pieces))
    (while (cdr copy)
      (setcar copy (company-safe-substring
                    (car copy) 0 (company-round-tab (string-width (car copy)))))
      (pop copy))
    (apply 'concat pieces)))

(defun company-fill-propertize (value annotation width selected left right)
  (let* ((margin (length left))
         (common (or (company-call-backend 'match value)
                     (if company-common
                         (string-width company-common)
                       0)))
         (_ (setq value (company-reformat (company--pre-render value))
                  annotation (and annotation (company--pre-render annotation t))))
         (ann-ralign company-tooltip-align-annotations)
         (ann-truncate (< width
                          (+ (length value) (length annotation)
                             (if ann-ralign 1 0))))
         (ann-start (+ margin
                       (if ann-ralign
                           (if ann-truncate
                               (1+ (length value))
                             (- width (length annotation)))
                         (length value))))
         (ann-end (min (+ ann-start (length annotation)) (+ margin width)))
         (line (concat left
                       (if (or ann-truncate (not ann-ralign))
                           (company-safe-substring
                            (concat value
                                    (when (and annotation ann-ralign) " ")
                                    annotation)
                            0 width)
                         (concat
                          (company-safe-substring value 0
                                                  (- width (length annotation)))
                          annotation))
                       right)))
    (setq width (+ width margin (length right)))

    (font-lock-append-text-property 0 width 'mouse-face
                                    'company-tooltip-mouse
                                    line)
    (when (< ann-start ann-end)
      (add-face-text-property ann-start ann-end
                              (if selected
                                  'company-tooltip-annotation-selection
                                'company-tooltip-annotation)
                              t line))
    (cl-loop
     with width = (- width (length right))
     for (comp-beg . comp-end) in (if (integerp common) `((0 . ,common)) common)
     for inline-beg = (+ margin comp-beg)
     for inline-end = (min (+ margin comp-end) width)
     when (< inline-beg width)
     do (add-face-text-property inline-beg inline-end
                                (if selected
                                    'company-tooltip-common-selection
                                  'company-tooltip-common)
                                nil line))
    (when (let ((re (funcall company-search-regexp-function
                             company-search-string)))
            (and (not (string= re ""))
                 (string-match re value)))
      (pcase-dolist (`(,mbeg . ,mend) (company--search-chunks))
        (let ((beg (+ margin mbeg))
              (end (+ margin mend))
              (width (- width (length right))))
          (when (< beg width)
            (add-face-text-property beg (min end width)
                                    (if selected
                                        'company-tooltip-search-selection
                                      'company-tooltip-search)
                                    nil line)))))
    (when selected
      (add-face-text-property 0 width 'company-tooltip-selection t line))
    (add-face-text-property 0 width 'company-tooltip t line)
    line))

(defun company--search-chunks ()
  (let ((md (match-data t))
        res)
    (if (<= (length md) 2)
        (push (cons (nth 0 md) (nth 1 md)) res)
      (while (setq md (nthcdr 2 md))
        (when (car md)
          (push (cons (car md) (cadr md)) res))))
    res))

(defun company--pre-render (str &optional annotation-p)
  (or (company-call-backend 'pre-render str annotation-p)
      (progn
        (when (or (text-property-not-all 0 (length str) 'face nil str)
                  (text-property-not-all 0 (length str) 'mouse-face nil str))
          (setq str (copy-sequence str))
          (remove-text-properties 0 (length str)
                                  '(face nil font-lock-face nil mouse-face nil)
                                  str))
        str)))

(defun company--clean-string (str)
  (replace-regexp-in-string
   "\\([^[:graph:] ]\\)\\|\\(\ufeff\\)\\|[[:multibyte:]]"
   (lambda (match)
     (cond
      ((match-beginning 1)
       ;; FIXME: Better char for 'non-printable'?
       ;; We shouldn't get any of these, but sometimes we might.
       ;; The official "replacement character" is not supported by some fonts.
       ;;"\ufffd"
       "?"
       )
      ((match-beginning 2)
       ;; Zero-width non-breakable space.
       "")
      ((> (string-width match) 1)
       (concat
        (make-string (1- (string-width match)) ?\ufeff)
        match))
      (t match)))
   str))

;;; replace

(defun company-buffer-lines (beg end)
  (goto-char beg)
  (let (lines lines-moved)
    (while (and (not (eobp)) ; http://debbugs.gnu.org/19553
                (> (setq lines-moved (vertical-motion 1)) 0)
                (<= (point) end))
      (let ((bound (min end (point))))
        ;; A visual line can contain several physical lines (e.g. with outline's
        ;; folding overlay).  Take only the first one.
        (push (buffer-substring beg
                                (save-excursion
                                  (goto-char beg)
                                  (re-search-forward "$" bound 'move)
                                  (point)))
              lines))
      ;; One physical line can be displayed as several visual ones as well:
      ;; add empty strings to the list, to even the count.
      (dotimes (_ (1- lines-moved))
        (push "" lines))
      (setq beg (point)))
    (unless (eq beg end)
      (push (buffer-substring beg end) lines))
    (nreverse lines)))

(defun company-modify-line (old new offset)
  (concat (company-safe-substring old 0 offset)
          new
          (company-safe-substring old (+ offset (length new)))))

(defun company--show-numbers (numbered)
  (format " %s" (if (<= numbered 10)
                    (mod numbered 10)
                  " ")))
(make-obsolete
 'company--show-numbers
 "use `company-quick-access-hint-key' instead,
but adjust the expected values appropriately."
 "0.9.14")

(defsubst company--window-height ()
  (if (fboundp 'window-screen-lines)
      (floor (window-screen-lines))
    (window-body-height)))

(defun company--window-width ()
  (let ((ww (window-body-width)))
    ;; Account for the line continuation column.
    (when (zerop (cadr (window-fringes)))
      (cl-decf ww))
    (when (bound-and-true-p display-line-numbers)
      (cl-decf ww (+ 2 (line-number-display-width))))
    ;; whitespace-mode with newline-mark
    (when (and buffer-display-table
               (aref buffer-display-table ?\n))
      (cl-decf ww (1- (length (aref buffer-display-table ?\n)))))
    ww))

(defun company--face-attribute (face attr)
  ;; Like `face-attribute', but accounts for faces that have been remapped to
  ;; another face, a list of faces, or a face spec.
  (cond ((null face) nil)
        ((symbolp face)
         (let ((remap (cdr (assq face face-remapping-alist))))
           (if remap
               (company--face-attribute
                ;; Faces can be remapped to their unremapped selves, but that
                ;; would cause us infinite recursion.
                (if (listp remap) (remq face remap) remap)
                attr)
             (face-attribute face attr nil t))))
        ((keywordp (car-safe face))
         (or (plist-get face attr)
             (company--face-attribute (plist-get face :inherit) attr)))
        ((listp face)
         (cl-find-if #'stringp
                     (mapcar (lambda (f) (company--face-attribute f attr))
                             face)))))

(defun company--replacement-string (lines column-offset old column nl &optional align-top)
  (cl-decf column column-offset)

  (when (< column 0) (setq column 0))

  (when (and align-top company-tooltip-flip-when-above)
    (setq lines (reverse lines)))

  (let ((width (length (car lines)))
        (remaining-cols (- (+ (company--window-width) (window-hscroll))
                           column)))
    (when (> width remaining-cols)
      (cl-decf column (- width remaining-cols))))

  (let (new)
    (when align-top
      ;; untouched lines first
      (dotimes (_ (- (length old) (length lines)))
        (push (pop old) new)))
    ;; length into old lines.
    (while old
      (push (company-modify-line (pop old) (pop lines) column)
            new))
    ;; Append whole new lines.
    (while lines
      (push (concat (company-space-string column) (pop lines))
            new))

    ;; XXX: Also see branch 'more-precise-extend'.
    (let* ((nl-face `(,@(when (version<= "27" emacs-version)
                          '(:extend t))
                     :inverse-video nil
                     :background ,(or (company--face-attribute 'default :background)
                                     (face-attribute 'default :background nil t))))
           (str (apply #'concat
                       (when nl " \n")
                       (cl-mapcan
                        ;; https://debbugs.gnu.org/cgi/bugreport.cgi?bug=42552#23
                        (lambda (line) (list line (propertize "\n" 'face nl-face)))
                        (nreverse new)))))
      ;; https://debbugs.gnu.org/38563
      (add-face-text-property 0 (length str) 'default t str)
      (when nl (put-text-property 0 1 'cursor t str))
      str)))

(defun company--create-lines (selection limit)
  (let ((len company-candidates-length)
        (window-width (company--window-width))
        left-margins
        left-margin-size
        lines
        width
        lines-copy
        items
        previous
        remainder
        scrollbar-bounds)

    ;; Maybe clear old offset.
    (when (< len (+ company-tooltip-offset limit))
      (setq company-tooltip-offset 0))

    (let ((selection (or selection 0)))
      ;; Scroll to offset.
      (if (eq company-tooltip-offset-display 'lines)
          (setq limit (company-tooltip--lines-update-offset selection len limit))
        (company-tooltip--simple-update-offset selection len limit))

      (cond
       ((eq company-tooltip-offset-display 'scrollbar)
        (setq scrollbar-bounds (company--scrollbar-bounds company-tooltip-offset
                                                          limit len)))
       ((eq company-tooltip-offset-display 'lines)
        (when (> company-tooltip-offset 0)
          (setq previous (format "...(%d)" company-tooltip-offset)))
        (setq remainder (- len limit company-tooltip-offset)
              remainder (when (> remainder 0)
                          (setq remainder (format "...(%d)" remainder)))))))

    (when selection
      (cl-decf selection company-tooltip-offset))

    (setq width (max (length previous) (length remainder))
          lines (nthcdr company-tooltip-offset company-candidates)
          len (min limit len)
          lines-copy lines)

    (when scrollbar-bounds (cl-decf window-width))

    (when company-format-margin-function
      (let ((lines-copy lines-copy)
            res)
        (dotimes (i len)
          (push (funcall company-format-margin-function
                         (pop lines-copy)
                         (equal selection i))
                res))
        (setq left-margins (nreverse res))))

    ;; XXX: format-function outputting shorter strings than the
    ;; default margin is not supported (yet?).
    (setq left-margin-size (apply #'max company-tooltip-margin
                                  (mapcar #'length left-margins)))

    (cl-decf window-width company-tooltip-margin)
    (cl-decf window-width left-margin-size)

    (dotimes (_ len)
      (let* ((value (pop lines-copy))
             (annotation (company-call-backend 'annotation value))
             (left (or (pop left-margins)
                       (company-space-string left-margin-size))))
        (setq value (company--clean-string value))
        (when annotation
          (setq annotation (company--clean-string annotation))
          (when company-tooltip-align-annotations
            ;; `lisp-completion-at-point' adds a space.
            (setq annotation (string-trim-left annotation))))
        (push (list value annotation left) items)
        (setq width (max (+ (length value)
                            (if (and annotation company-tooltip-align-annotations)
                                (1+ (length annotation))
                              (length annotation)))
                         width))))

    (setq width (min window-width
                     company-tooltip-maximum-width
                     (max company-tooltip-minimum-width
                          (if company-show-quick-access
                              (+ 2 width)
                            width))))

    (when company-tooltip-width-grow-only
      (setq width (max company--tooltip-current-width width))
      (setq company--tooltip-current-width width))

    (let ((items (nreverse items))
          (row (if company-show-quick-access 0 99999))
          new)
      (when previous
        (push (company--scrollpos-line previous width left-margin-size) new))

      (dotimes (i len)
        (let* ((item (pop items))
               (str (car item))
               (annotation (cadr item))
               (left (nth 2 item))
               (right (company-space-string company-tooltip-margin))
               (width width)
               (selected (equal selection i)))
          (when company-show-quick-access
            (let ((quick-access (gv-ref (if (eq company-show-quick-access 'left)
                                            left right)))
                  (qa-hint (company-tooltip--format-quick-access-hint
                            row selected)))
              (cl-decf width (string-width qa-hint))
              (setf (gv-deref quick-access)
                    (concat qa-hint (gv-deref quick-access))))
            (cl-incf row))
          (push (concat
                 (company-fill-propertize str annotation
                                          width selected
                                          left
                                          right)
                 (when scrollbar-bounds
                   (company--scrollbar i scrollbar-bounds)))
                new)))

      (when remainder
        (push (company--scrollpos-line remainder width left-margin-size) new))

      (cons
       left-margin-size
       (nreverse new)))))

(defun company--scrollbar-bounds (offset limit length)
  (when (> length limit)
    (let* ((size (ceiling (* limit (float limit)) length))
           (lower (floor (* limit (float offset)) length))
           (upper (+ lower size -1)))
      (cons lower upper))))

(defun company--scrollbar (i bounds)
  (propertize " " 'face
              (if (and (>= i (car bounds)) (<= i (cdr bounds)))
                  'company-scrollbar-fg
                'company-scrollbar-bg)))

(defun company--scrollpos-line (text width fancy-margin-width)
  (propertize (concat (company-space-string company-tooltip-margin)
                      (company-safe-substring text 0 width)
                      (company-space-string fancy-margin-width))
              'face 'company-tooltip))

(defun company-tooltip--format-quick-access-hint (row selected)
  "Format a quick-access hint for outputting on a tooltip's ROW.
Value of SELECTED determines the added face."
  (propertize (format "%2s" (funcall company-quick-access-hint-function row))
              'face
              (if selected
                  'company-tooltip-quick-access-selection
                'company-tooltip-quick-access)))

;; show

(defvar-local company-pseudo-tooltip-overlay nil)

(defun company--inside-tooltip-p (event-col-row row height)
  (let* ((ovl company-pseudo-tooltip-overlay)
         (column (overlay-get ovl 'company-column))
         (width (overlay-get ovl 'company-width))
         (evt-col (car event-col-row))
         (evt-row (cdr event-col-row)))
    (and (>= evt-col column)
         (< evt-col (+ column width))
         (if (> height 0)
             (and (> evt-row row)
                  (<= evt-row (+ row height) ))
           (and (< evt-row row)
                (>= evt-row (+ row height)))))))

(defun company--pseudo-tooltip-height ()
  "Calculate the appropriate tooltip height.
Returns a negative number if the tooltip should be displayed above point."
  (let* ((lines (company--row))
         (below (- (company--window-height) 1 lines)))
    (if (and (< below (min company-tooltip-minimum company-candidates-length))
             (> lines below))
        (- (max 3 (min company-tooltip-limit lines)))
      (max 3 (min company-tooltip-limit below)))))

(defun company-pseudo-tooltip-show (row column selection)
  (company-pseudo-tooltip-hide)

    (let* ((height (company--pseudo-tooltip-height))
           above)

      (when (< height 0)
        (setq row (+ row height -1)
              above t))

      ;; This can happen in Emacs versions which allow arbitrary scrolling,
      ;; such as Yamamoto's Mac Port.
      (unless (pos-visible-in-window-p (window-start))
        (cl-decf row))

      (let (nl beg end ov args)
        (save-excursion
          (setq nl (< (move-to-window-line row) row)
                beg (point)
                end (save-excursion
                      (move-to-window-line (+ row (abs height)))
                      (point))
                ov (make-overlay beg end nil t)
                args (list (mapcar 'company-plainify
                                   (company-buffer-lines beg end))
                           column nl above)))

        (setq company-pseudo-tooltip-overlay ov)
        (overlay-put ov 'company-replacement-args args)

        (let* ((lines-and-offset (company--create-lines selection (abs height)))
               (lines (cdr lines-and-offset))
               (column-offset (car lines-and-offset)))
          (overlay-put ov 'company-display
                       (apply 'company--replacement-string
                              lines column-offset args))
          (overlay-put ov 'company-width (string-width (car lines))))

        (overlay-put ov 'company-column column)
        (overlay-put ov 'company-height height))))

(defun company-pseudo-tooltip-show-at-point (pos column-offset)
  (let* ((col-row (company--col-row pos))
         (col (- (car col-row) column-offset)))
    (when (< col 0) (setq col 0))
    (company-pseudo-tooltip-show (1+ (cdr col-row)) col company-selection)))

(defun company-pseudo-tooltip-edit (selection)
  (let* ((height (overlay-get company-pseudo-tooltip-overlay 'company-height))
         (lines-and-offset  (company--create-lines selection (abs height)))
         (lines (cdr lines-and-offset))
         (column-offset (car lines-and-offset)))
    (overlay-put company-pseudo-tooltip-overlay 'company-width
                 (string-width (car lines)))
    (overlay-put company-pseudo-tooltip-overlay 'company-display
                 (apply 'company--replacement-string
                        lines column-offset
                        (overlay-get company-pseudo-tooltip-overlay
                                     'company-replacement-args)))))

(defun company-pseudo-tooltip-hide ()
  (when company-pseudo-tooltip-overlay
    (delete-overlay company-pseudo-tooltip-overlay)
    (setq company-pseudo-tooltip-overlay nil)))

(defun company-pseudo-tooltip-hide-temporarily ()
  (when (overlayp company-pseudo-tooltip-overlay)
    (overlay-put company-pseudo-tooltip-overlay 'invisible nil)
    (overlay-put company-pseudo-tooltip-overlay 'line-prefix nil)
    (overlay-put company-pseudo-tooltip-overlay 'after-string nil)
    (overlay-put company-pseudo-tooltip-overlay 'display nil)
    (overlay-put company-pseudo-tooltip-overlay 'face nil)))

(defun company-pseudo-tooltip-unhide ()
  (when company-pseudo-tooltip-overlay
    (let* ((ov company-pseudo-tooltip-overlay)
           (disp (overlay-get ov 'company-display)))
      ;; Beat outline's folding overlays.
      ;; And Flymake (53). And Flycheck (110).
      (overlay-put ov 'priority 111)
      ;; No (extra) prefix for the first line.
      (overlay-put ov 'line-prefix "")
      (overlay-put ov 'after-string disp)
      ;; `display' is better than `invisible':
      ;; https://debbugs.gnu.org/18285
      ;; https://debbugs.gnu.org/20847
      ;; https://debbugs.gnu.org/42521
      (overlay-put ov 'display "")
      (overlay-put ov 'window (selected-window)))))

(defun company-pseudo-tooltip-guard ()
  (list
   (save-excursion (beginning-of-visual-line))
   (window-width)
   (let ((ov company-pseudo-tooltip-overlay)
         (overhang (save-excursion (end-of-visual-line)
                                   (- (line-end-position) (point)))))
     (when (>= (overlay-get ov 'company-height) 0)
       (cons
        (buffer-substring-no-properties (point) (overlay-start ov))
        (when (>= overhang 0) overhang))))))

(defun company-pseudo-tooltip-frontend (command)
  "`company-mode' frontend similar to a tooltip but based on overlays."
  (cl-case command
    (pre-command (company-pseudo-tooltip-hide-temporarily))
    (unhide
     (let ((ov company-pseudo-tooltip-overlay))
       (when (> (overlay-get ov 'company-height) 0)
         ;; Sleight of hand: if the current line wraps, we adjust the
         ;; start of the overlay so that the popup does not zig-zag,
         ;; but don't update the popup's background.  This seems just
         ;; non-annoying enough to avoid the work required for the latter.
         (save-excursion
           (vertical-motion 1)
           (unless (= (point) (overlay-start ov))
             (move-overlay ov (point) (overlay-end ov))))))
     (company-pseudo-tooltip-unhide))
    (post-command
     (unless (when (overlayp company-pseudo-tooltip-overlay)
               (let* ((ov company-pseudo-tooltip-overlay)
                      (old-height (overlay-get ov 'company-height))
                      (new-height (company--pseudo-tooltip-height)))
                 (and
                  (>= (* old-height new-height) 0)
                  (>= (abs old-height) (abs new-height))
                  (equal (company-pseudo-tooltip-guard)
                         (overlay-get ov 'company-guard)))))
       ;; Redraw needed.
       (company-pseudo-tooltip-show-at-point (point) (length company-prefix))
       (overlay-put company-pseudo-tooltip-overlay
                    'company-guard (company-pseudo-tooltip-guard)))
     (company-pseudo-tooltip-unhide))
    (show (setq company--tooltip-current-width 0))
    (hide (company-pseudo-tooltip-hide)
          (setq company-tooltip-offset 0))
    (update (when (overlayp company-pseudo-tooltip-overlay)
              (company-pseudo-tooltip-edit company-selection)))
    (select-mouse
     (let ((event-col-row (company--event-col-row company-mouse-event))
           (ovl-row (company--row))
           (ovl-height (and company-pseudo-tooltip-overlay
                            (min (overlay-get company-pseudo-tooltip-overlay
                                              'company-height)
                                 company-candidates-length))))
       (cond ((and ovl-height
                   (company--inside-tooltip-p event-col-row ovl-row ovl-height))
              (company-set-selection (+ (cdr event-col-row)
                                        (1- company-tooltip-offset)
                                        (if (and (eq company-tooltip-offset-display 'lines)
                                                 (not (zerop company-tooltip-offset)))
                                            -1 0)
                                        (- ovl-row)
                                        (if (< ovl-height 0)
                                            (- 1 ovl-height)
                                          0)))
              t))))))

(defun company-pseudo-tooltip-unless-just-one-frontend (command)
  "`company-pseudo-tooltip-frontend', but not shown for single candidates."
  (unless (and (memq command '(post-command unhide))
               (company--show-inline-p))
    (company-pseudo-tooltip-frontend command)))

(defun company-pseudo-tooltip--ujofwd-on-timer (command)
  (when company-candidates
    (company-pseudo-tooltip-unless-just-one-frontend-with-delay command)))

(defun company-pseudo-tooltip-unless-just-one-frontend-with-delay (command)
  "`compandy-pseudo-tooltip-frontend', but shown after a delay.
Delay is determined by `company-tooltip-idle-delay'."
  (defvar company-preview-overlay)
  (when (and (memq command '(pre-command hide))
             company-tooltip-timer)
    (cancel-timer company-tooltip-timer)
    (setq company-tooltip-timer nil))
  (cl-case command
    (post-command
     (if (or company-tooltip-timer
             (overlayp company-pseudo-tooltip-overlay))
         (if (not (overlayp company-preview-overlay))
             (company-pseudo-tooltip-unless-just-one-frontend command)
           (let (company-tooltip-timer)
             (company-call-frontends 'pre-command))
           (company-call-frontends 'post-command))
       (setq company-tooltip-timer
             (run-with-timer company-tooltip-idle-delay nil
                             'company-pseudo-tooltip--ujofwd-on-timer
                             'post-command))))
    (unhide
     (when (overlayp company-pseudo-tooltip-overlay)
       (company-pseudo-tooltip-unless-just-one-frontend command)))
    (t
     (company-pseudo-tooltip-unless-just-one-frontend command))))

;;; overlay ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-preview-overlay nil)

(defun company-preview-show-at-point (pos completion)
  (company-preview-hide)

  (setq completion (copy-sequence (company--pre-render completion)))
  (add-face-text-property 0 (length completion) 'company-preview
                          nil completion)
  (add-face-text-property 0 (length company-common) 'company-preview-common
                          nil completion)

    ;; Add search string
    (and (string-match (funcall company-search-regexp-function
                                company-search-string)
                       completion)
         (pcase-dolist (`(,mbeg . ,mend) (company--search-chunks))
           (add-face-text-property mbeg mend 'company-preview-search
                                   nil completion)))

    (setq completion (company-strip-prefix completion))

    (and (equal pos (point))
         (not (equal completion ""))
         (add-text-properties 0 1 '(cursor 1) completion))

    (let* ((beg pos)
           (pto company-pseudo-tooltip-overlay)
           (ptf-workaround (and
                            pto
                            (char-before pos)
                            (eq pos (overlay-start pto)))))
      ;; Try to accommodate for the pseudo-tooltip overlay,
      ;; which may start at the same position if it's at eol.
      (when ptf-workaround
        (cl-decf beg)
        (setq completion (concat (buffer-substring beg pos) completion)))

      (setq company-preview-overlay (make-overlay beg pos))

      (let ((ov company-preview-overlay))
        (overlay-put ov (if ptf-workaround 'display 'after-string)
                     completion)
        (overlay-put ov 'window (selected-window)))))

(defun company-preview-hide ()
  (when company-preview-overlay
    (delete-overlay company-preview-overlay)
    (setq company-preview-overlay nil)))

(defun company-preview-frontend (command)
  "`company-mode' frontend showing the selection as if it had been inserted."
  (pcase command
    (`pre-command (company-preview-hide))
    (`unhide
     (when company-selection
       (let* ((current (nth company-selection company-candidates))
              (company-prefix (if (equal current company-prefix)
                                  ;; Would be more accurate to compare lengths,
                                  ;; but this is shorter.
                                  current
                                (buffer-substring
                                 (- company-point (length company-prefix))
                                 (point)))))
         (company-preview-show-at-point (point) current))))
    (`post-command
     (when company-selection
       (company-preview-show-at-point (point)
                                      (nth company-selection company-candidates))))
    (`hide (company-preview-hide))))

(defun company-preview-if-just-one-frontend (command)
  "`company-preview-frontend', but only shown for single candidates."
  (when (or (not (memq command '(post-command unhide)))
            (company--show-inline-p))
    (company-preview-frontend command)))

(defun company--show-inline-p ()
  (and (not (cdr company-candidates))
       company-common
       (not (eq t (compare-strings company-prefix nil nil
                                   (car company-candidates) nil nil
                                   t)))
       (or (eq (company-call-backend 'ignore-case) 'keep-prefix)
           (string-prefix-p company-prefix company-common))))

(defun company-tooltip-visible-p ()
  "Returns whether the tooltip is visible."
  (when (overlayp company-pseudo-tooltip-overlay)
    (not (overlay-get company-pseudo-tooltip-overlay 'invisible))))

(defun company-preview-common--show-p ()
  "Returns whether the preview of common can be showed or not"
  (and company-common
       (or (eq (company-call-backend 'ignore-case) 'keep-prefix)
           (string-prefix-p company-prefix company-common))))

(defun company-preview-common-frontend (command)
  "`company-mode' frontend preview the common part of candidates."
  (when (or (not (memq command '(post-command unhide)))
            (company-preview-common--show-p))
    (pcase command
      (`pre-command (company-preview-hide))
      ((or 'post-command 'unhide)
       (company-preview-show-at-point (point) company-common))
      (`hide (company-preview-hide)))))

;;; echo ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local company-echo-last-msg nil)

(defvar company-echo-timer nil)

(defvar company-echo-delay .01)

(defcustom company-echo-truncate-lines t
  "Whether frontend messages written to the echo area should be truncated."
  :type 'boolean
  :package-version '(company . "0.9.3"))

(defun company-echo-show (&optional getter)
  (when getter
    (setq company-echo-last-msg (funcall getter)))
  (let ((message-log-max nil)
        (message-truncate-lines company-echo-truncate-lines))
    (if company-echo-last-msg
        (message "%s" company-echo-last-msg)
      (message ""))))

(defun company-echo-show-soon (&optional getter delay)
  (company-echo-cancel)
  (setq company-echo-timer (run-with-timer (or delay company-echo-delay)
                                           nil
                                           'company-echo-show getter)))

(defun company-echo-cancel (&optional unset)
  (when company-echo-timer
    (cancel-timer company-echo-timer))
  (when unset
    (setq company-echo-timer nil)))

(defun company-echo-format ()
  (let ((selection (or company-selection 0)))
    (let ((limit (window-body-width (minibuffer-window)))
          (len -1)
          (candidates (nthcdr selection company-candidates))
          (numbered (if company-show-quick-access selection 99999))
          (qa-keys-len (length company-quick-access-keys))
          comp msg)

      (while candidates
        (setq comp (propertize
                    (company-reformat (company--clean-string (pop candidates)))
                    'face
                    'company-echo)
              len (+ len 1 (length comp)))
        (let ((beg 0)
              (end (string-width (or company-common ""))))
          (when (< numbered qa-keys-len)
            (let ((qa-hint
                   (format "%s: " (funcall
                                   company-quick-access-hint-function
                                   numbered))))
              (setq beg (string-width qa-hint)
                    end (+ beg end))
              (cl-incf len beg)
              (setq comp (propertize (concat qa-hint comp) 'face 'company-echo)))
            (cl-incf numbered))
          ;; FIXME: Add support for the `match' backend action, and thus,
          ;; non-prefix matches.
          (add-text-properties beg end '(face company-echo-common) comp))
        (if (>= len limit)
            (setq candidates nil)
          (push comp msg)))

      (mapconcat 'identity (nreverse msg) " "))))

(defun company-echo-strip-common-format ()
  (let ((selection (or company-selection 0)))
    (let ((limit (window-body-width (minibuffer-window)))
          (len (+ (length company-prefix) 2))
          (candidates (nthcdr selection company-candidates))
          (numbered (if company-show-quick-access selection 99999))
          (qa-keys-len (length company-quick-access-keys))
          comp msg)

      (while candidates
        (setq comp (company-strip-prefix (pop candidates))
              len (+ len 2 (length comp)))
        (when (< numbered qa-keys-len)
          (let ((qa-hint (format " (%s)"
                                 (funcall company-quick-access-hint-function
                                          numbered))))
            (setq comp (concat comp qa-hint))
            (cl-incf len (string-width qa-hint)))
          (cl-incf numbered))
        (if (>= len limit)
            (setq candidates nil)
          (push (propertize comp 'face 'company-echo) msg)))

      (concat (propertize company-prefix 'face 'company-echo-common) "{"
              (mapconcat 'identity (nreverse msg) ", ")
              "}"))))

(defun company-echo-hide ()
  (unless (equal company-echo-last-msg "")
    (setq company-echo-last-msg "")
    (company-echo-show)))

(defun company-echo-frontend (command)
  "`company-mode' frontend showing the candidates in the echo area."
  (pcase command
    (`post-command (company-echo-show-soon 'company-echo-format 0))
    (`hide (company-echo-hide))))

(defun company-echo-strip-common-frontend (command)
  "`company-mode' frontend showing the candidates in the echo area."
  (pcase command
    (`post-command (company-echo-show-soon 'company-echo-strip-common-format 0))
    (`hide (company-echo-hide))))

(defun company-echo-metadata-frontend (command)
  "`company-mode' frontend showing the documentation in the echo area."
  (pcase command
    (`post-command (company-echo-show-soon 'company-fetch-metadata))
    (`unhide (company-echo-show))
    (`hide (company-echo-hide))))

(provide 'company)
;;; company.el ends here
