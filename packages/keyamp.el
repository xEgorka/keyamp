;;; keyamp.el --- Key Amplifier -*- coding: utf-8; lexical-binding: t; -*-

;; Author: Egor Maltsev <x0o1@ya.ru>
;; Version: 1.0 2023-09-13 Koala Paw
;;      _                   _
;;    _|_|_               _|_|_
;;   |_|_|_|             |_|_|_|
;;           _ _     _ _
;;          | | |   | | |
;;          |_|_|   |_|_|

;; This package is part of input model.
;; Follow the link: https://github.com/xEgorka/keyamp

;;; Commentary:

;; Keyamp provides 3 modes: insert, command and repeat. Command mode
;; based on persistent transient keymap.

;; Repeat mode pushes transient remaps to keymap stack on top of
;; command mode for easy repeat of commands chains during screen
;; positioning, cursor move and editing. Point color indicates
;; transient remap is active. ESDF and IJKL are mostly used, DEL/ESC
;; and RET/SPC control EVERYTHING. Home row and thumb cluster only.

;; DEL and SPC are two leader keys, RET activates insert mode, ESC for
;; command one. Holding down each of the keys posts control sequence
;; depending on mode. Keyboard has SYMMETRIC layout: left side for
;; editing, «No» and «Escape» while right side for moving, «Yes» and
;; «Enter». Any Emacs major or minor mode could be remaped to fit the
;; model, find examples in the package.

;; Karabiner integration allows to post control or leader sequences by
;; holding down a key. NO need to have any modifier or arrows keys at
;; ALL. Holding down posts leader layer. The same symmetric layout
;; might be configured on ANSI keyboard, ergonomic split and virtual
;; keyboards. See the link for layouts and karabiner config.

;; This package is a fork of xah-fly-keys.

;;; Code:



(defgroup keyamp nil "Customization options for keyamp"
  :group 'help :prefix "keyamp-")

(defvar keyamp-command-hook nil "Hook for `keyamp-command'")
(defvar keyamp-insert-hook  nil "Hook for `keyamp-insert'")

(defconst keyamp-karabiner-cli
  "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
  "Karabiner-Elements CLI executable")

(defconst keyamp-command-indicator "🟢" "Character indicating command is active.")
(defconst keyamp-insert-indicator  "🟠" "Character indicating insert is active.")
(defconst keyamp-repeat-indicator  "🔵" "Character indicating repeat is active.")

(defconst keyamp-command-cursor "lawngreen"   "Cursor color command.")
(defconst keyamp-insert-cursor  "gold"        "Cursor color insert.")
(defconst keyamp-repeat-cursor  "deepskyblue" "Cursor color repeat.")

(defconst keyamp-idle-timeout 60 "Idle timeout.")



(defvar keyamp-layouts nil "A alist. Key is layout name, string type.
Value is a alist, each element is of the form (\"e\" . \"d\").
First char is qwerty, second is corresponding char of the destination layout.
When a char is not in this alist, they are assumed to be the same.")

(push '("qwerty" . nil) keyamp-layouts)

(push
 '("engineer-engram" .
   (("-" . "#") ("=" . "%") ("`" . "`")  ("q" . "b") ("w" . "y") ("e" . "o")
    ("r" . "u") ("t" . "'") ("y" . "\"") ("u" . "l") ("i" . "d") ("o" . "w")
    ("p" . "v") ("[" . "z") ("]" . "{")  ("a" . "c") ("s" . "i") ("d" . "e")
    ("f" . "a") ("g" . ",") ("h" . ".")  ("j" . "h") ("k" . "t") ("l" . "s")
    (";" . "n") ("'" . "q") ("\\" . "}") ("z" . "g") ("x" . "x") ("c" . "j")
    ("v" . "k") ("b" . "-") ("n" . "?")  ("m" . "r") ("," . "m") ("." . "f")
    ("/" . "p") ("_" . "|") ("+" . "^")  ("~" . "~") ("Q" . "B") ("W" . "Y")
    ("E" . "O") ("R" . "U") ("T" . "(")  ("Y" . ")") ("U" . "L") ("I" . "D")
    ("O" . "W") ("P" . "V") ("{" . "Z")  ("}" . "[") ("A" . "C") ("S" . "I")
    ("D" . "E") ("F" . "A") ("G" . ";")  ("H" . ":") ("J" . "H") ("K" . "T")
    ("L" . "S") (":" . "N") ("\"" . "Q") ("|" . "]") ("Z" . "G") ("X" . "X")
    ("C" . "J") ("V" . "K") ("B" . "_")  ("N" . "!") ("M" . "R") ("<" . "M")
    (">" . "F") ("?" . "P") ("1" . "7")  ("2" . "5") ("3" . "1") ("4" . "3")
    ("5" . "9") ("6" . "8") ("7" . "2")  ("8" . "0") ("9" . "4") ("0" . "6")
    ("!" . "@") ("@" . "&") ("#" . "/")  ("$" . "$") ("%" . "<") ("^" . ">")
    ("&" . "*") ("*" . "=") ("(" . "+")  (")" . "\\"))) keyamp-layouts)

(defvar keyamp-current-layout "engineer-engram"
  "The current keyboard layout. Value is a key in `keyamp-layouts'.")

(defvar keyamp--convert-table nil
  "A alist that's the conversion table from qwerty to current layout.
Value structure is one of the key's value of `keyamp-layouts'.
Value is programmatically set from value of `keyamp-current-layout'.
Do not manually set this variable.")

(setq keyamp--convert-table
      (cdr (assoc keyamp-current-layout keyamp-layouts)))

(defun keyamp--convert-kbd-str (Charstr)
  "Return the corresponding char Charstr according to
`keyamp--convert-table'. Charstr must be a string that is the argument
to `kbd'. E.g. \"a\" and \"a b c\". Each space separated token is
converted according to `keyamp--convert-table'."
  (mapconcat 'identity
             (mapcar
              (lambda (x) (let ((xresult (assoc x keyamp--convert-table)))
                            (if xresult (cdr xresult) x)))
              (split-string Charstr " +")) " "))

(defvar keyamp-command-alist nil
  "Alist of `keyamp-command-map' in qwerty format for command lookup by key code.")

(defun keyamp--lookup-command-by-key-code (KeyCodeOrCmd)
  "Return the corresponding command from `keyamp-command-alist' by key code.
If no result, return KEYCODEORCMD unchanged."
  (let ((xresult (assoc KeyCodeOrCmd keyamp-command-alist)))
    (if xresult (cdr xresult) KeyCodeOrCmd)))

(defmacro keyamp--map (KeymapName KeyCmdAlist &optional Direct-p)
  "Map `define-key' over a alist KEYCMDALIST, with key layout remap.
The key is remapped from qwerty to the current keyboard layout by
`keyamp--convert-kbd-str'.
If Direct-p is t, do not remap key to current keyboard layout."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       (if (eq ,xkeymapName keyamp-command-map) (setq keyamp-command-alist ,KeyCmdAlist))
       ,@(mapcar
          (lambda (xpair)
            `(define-key ,xkeymapName
               (kbd (,(if Direct-p #'identity #'keyamp--convert-kbd-str) ,(car xpair)))
               ,(list 'quote (cdr xpair))))
          (cadr KeyCmdAlist)))))

(defmacro keyamp--map-translation (KeyKeyAlist State-p)
  "Map `define-key' for `key-translation-map' over a alist KEYKEYALIST.
If State-p is nil, remove the mapping."
  `(let ()
     ,@(mapcar
        (lambda (xpair)
          `(define-key
            key-translation-map (kbd ,(car xpair)) (if ,State-p (kbd ,(cdr xpair)))))
        (cadr KeyKeyAlist))))

(defmacro keyamp--remap (KeymapName CmdCmdAlist)
  "Map `define-key' remap over a alist CMDCMDALIST."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xpair)
            `(define-key
              ,xkeymapName [remap ,(keyamp--lookup-command-by-key-code (car xpair))] ,(list 'quote (cdr xpair))))
          (cadr CmdCmdAlist)))))

(defmacro keyamp--set-map (KeymapName CmdList &optional CommandMode InsertMode How)
  "Map `set-transient-map' using `advice-add' over a list CMDLIST.
Advice default HOW :after might be changed by specific HOW.
Activate command or insert mode optionally."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xcmd)
            `(advice-add ,(list 'quote xcmd) (if ,How ,How :after)
                         (lambda (&rest r) "Repeat."
                           (if ,CommandMode (keyamp-command))
                           (set-transient-map ,xkeymapName)
                           (if ,InsertMode (keyamp-insert)))))
          (cadr CmdList)))))

(defmacro keyamp--set-map-hook
    (KeymapName HookList &optional CommandMode InsertMode RepeatMode)
  "Map `set-transient-map' using `add-hook' over a list HOOKLIST.
Activate command, insert or repeat mode optionally."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       ,@(mapcar
          (lambda (xhook)
            `(add-hook ,(list 'quote xhook)
                       (lambda () "Repeat."
                         (if ,CommandMode (keyamp-command))
                         (if ,InsertMode (keyamp-insert))
                         (set-transient-map ,xkeymapName)
                         (if ,RepeatMode (setq this-command 'keyamp--repeat-dummy)))))
          (cadr HookList)))))

(defmacro keyamp--map-leaders (KeymapName CmdCons)
  "Map leader keys using `keyamp--map'."
  (let ((xkeymapName (make-symbol "keymap-name")))
    `(let ((,xkeymapName ,KeymapName))
       (keyamp--map ,xkeymapName
        '(("DEL" . ,(keyamp--lookup-command-by-key-code (car (cadr CmdCons))))
          ("<backspace>" . ,(keyamp--lookup-command-by-key-code (car (cadr CmdCons))))
          ("SPC" . ,(keyamp--lookup-command-by-key-code (cdr (cadr CmdCons)))))))))

(defmacro with-sparse-keymap-x (&rest body)
  "Make sparse keymap x for next use in BODY."
  `(let ((x (make-sparse-keymap))) ,@body))



(defconst keyamp-engineer-engram-to-russian-computer
  '(("a" . "а") ("b" . "й") ("c" . "ф") ("d" . "ш") ("e" . "в")
    ("f" . "ю") ("g" . "я") ("h" . "о") ("i" . "ы") ("j" . "с")
    ("k" . "м") ("l" . "г") ("m" . "б") ("n" . "ж") ("o" . "у")
    ("q" . "э") ("r" . "ь") ("s" . "д") ("t" . "л") ("u" . "к")
    ("v" . "з") ("w" . "щ") ("x" . "ч") ("y" . "ц") ("z" . "х")
    ("." . "р") ("?" . "т") ("-" . "и") ("," . "п") ("'" . "е")
    ("`" . "ё") ("{" . "ъ") ("\"" . "н"))
  "Mapping for `keyamp-define-input-source'")

(defun keyamp-quail-get-translation (from)
  "Get translation Engineer Engram to russian-computer.
From character to character code."
  (let ((to (alist-get from keyamp-engineer-engram-to-russian-computer
             nil nil 'string-equal)))
    (when (stringp to)
      (string-to-char to))))

(defun keyamp-define-input-source (input-method)
  "Build reverse mapping for `input-method'.
Use Russian input source for command mode. Respect Engineer Engram layout."
  (interactive
   (list (read-input-method-name "Use input method (default current): ")))
  (if (and input-method (symbolp input-method))
      (setq input-method (symbol-name input-method)))
  (let ((current current-input-method)
        (modifiers '(nil (control))))
    (when input-method
      (activate-input-method input-method))
    (when (and current-input-method quail-keyboard-layout)
      (dolist (map (cdr (quail-map)))
        (let* ((to (car map))
               (from (if (string-equal keyamp-current-layout "engineer-engram")
                         (keyamp-quail-get-translation (char-to-string to))
                       (quail-get-translation (cadr map) (char-to-string to) 1))))
          (when (and (characterp from) (characterp to))
            (dolist (mod modifiers)
              (define-key local-function-key-map
                (vector (append mod (list from)))
                (vector (append mod (list to)))))))))
    (when input-method
      (activate-input-method current))))



(defconst quail-keyboard-layout-engineer-engram
  "\
                              \
  7@5&1/3$9<8>2*0=4+6\\#|%^`~  \
  bByYoOuU'(\")lLdDwWvVzZ{[    \
  cCiIeEaA,;.:hHtTsSnNqQ}]    \
  gGxXjJkK-_?!rRmMfFpP        \
                              "
  "Engineer Engram keyboard layout for Quail, e.g. for input method.")

(require 'quail)
(push (cons "engineer-engram" quail-keyboard-layout-engineer-engram)
      quail-keyboard-layout-alist)

(defun keyamp-qwerty-to-engineer-engram ()
  "Toggle translate qwerty layout to engineer engram on Emacs level.
Useful when Engineer Engram layout not available on OS or keyboard level."
  (interactive)
  (if (get 'keyamp-qwerty-to-engineer-engram 'state)
      (progn
        (put 'keyamp-qwerty-to-engineer-engram 'state nil)
        (quail-set-keyboard-layout "standard")
        (message "Translation deactivated"))
    (progn
      (put 'keyamp-qwerty-to-engineer-engram 'state t)
      (quail-set-keyboard-layout "engineer-engram")
      (message "Translation activated")))
  (let ()
    (keyamp--map-translation
     '(("-" . "#") ("=" . "%") ("`" . "`")  ("q" . "b") ("w" . "y") ("e" . "o")
       ("r" . "u") ("t" . "'") ("y" . "\"") ("u" . "l") ("i" . "d") ("o" . "w")
       ("p" . "v") ("[" . "z") ("]" . "{")  ("a" . "c") ("s" . "i") ("d" . "e")
       ("f" . "a") ("g" . ",") ("h" . ".")  ("j" . "h") ("k" . "t") ("l" . "s")
       (";" . "n") ("'" . "q") ("\\" . "}") ("z" . "g") ("x" . "x") ("c" . "j")
       ("v" . "k") ("b" . "-") ("n" . "?")  ("m" . "r") ("," . "m") ("." . "f")
       ("/" . "p") ("_" . "|") ("+" . "^")  ("~" . "~") ("Q" . "B") ("W" . "Y")
       ("E" . "O") ("R" . "U") ("T" . "(")  ("Y" . ")") ("U" . "L") ("I" . "D")
       ("O" . "W") ("P" . "V") ("{" . "Z")  ("}" . "[") ("A" . "C") ("S" . "I")
       ("D" . "E") ("F" . "A") ("G" . ";")  ("H" . ":") ("J" . "H") ("K" . "T")
       ("L" . "S") (":" . "N") ("\"" . "Q") ("|" . "]") ("Z" . "G") ("X" . "X")
       ("C" . "J") ("V" . "K") ("B" . "_")  ("N" . "!") ("M" . "R") ("<" . "M")
       (">" . "F") ("?" . "P") ("1" . "7")  ("2" . "5") ("3" . "1") ("4" . "3")
       ("5" . "9") ("6" . "8") ("7" . "2")  ("8" . "0") ("9" . "4") ("0" . "6")
       ("!" . "@") ("@" . "&") ("#" . "/")  ("$" . "$") ("%" . "<") ("^" . ">")
       ("&" . "*") ("*" . "=") ("(" . "+")  (")" . "\\"))
     (get 'keyamp-qwerty-to-engineer-engram 'state))))


;; keymaps

(defvar keyamp-map (make-sparse-keymap)
  "Parent keymap of `keyamp-command-map'.
Define keys that are available in both command and insert modes here.")

(defvar keyamp-command-map (cons 'keymap keyamp-map)
  "Keymap that takes precedence over all other keymaps in command mode.
Inherits bindings from `keyamp-map'.

In command mode, if no binding is found in this map
`keyamp-map' is checked, then if there is still no binding,
the other active keymaps are checked like normal. However, if a key is
explicitly bound to nil in this map, it will not be looked up in
`keyamp-map' and lookup will skip directly to the normally
active maps.

In this way, bindings in `keyamp-map' can be disabled by this map.
Effectively, this map takes precedence over all others when command mode
is enabled.")



(progn
  (defconst keyamp-tty-seq-timeout 30
    "Timeout in ms to wait sequence after ESC sent in tty.")

  (defun keyamp-tty-ESC-filter (map)
    (if (and (equal (this-single-command-keys) [?\e])
             (sit-for (/ keyamp-tty-seq-timeout 1000.0)))
        [escape] map))

  (defun keyamp-lookup-key (map key)
    (catch 'found
      (map-keymap (lambda (k b) (if (equal key k) (throw 'found b))) map)))

  (defun keyamp-catch-tty-ESC ()
    "Setup key mappings of current terminal to turn a tty's ESC into <escape>."
    (when (memq (terminal-live-p (frame-terminal)) '(t pc))
      (let ((esc-binding (keyamp-lookup-key input-decode-map ?\e)))
        (define-key input-decode-map
          [?\e] `(menu-item "" ,esc-binding :filter keyamp-tty-ESC-filter)))))

  (define-key key-translation-map (kbd "ESC") (kbd "<escape>")))


;; setting keys

(keyamp--map keyamp-map
  '(("<escape>" . keyamp-escape)      ("S-<escape>" . ignore)
    ("C-^" . keyamp-left-leader-map)  ("C-+" . keyamp-left-leader-map)
    ("C-_" . keyamp-right-leader-map) ("C-И" . keyamp-right-leader-map)))

(keyamp--map keyamp-command-map
  '(("RET" . keyamp-insert)           ("<return>"    . keyamp-insert)          ("S-<return>"    . ignore)
    ("DEL" . keyamp-left-leader-map)  ("<backspace>" . keyamp-left-leader-map) ("S-<backspace>" . ignore)
    ("SPC" . keyamp-right-leader-map)

    ;; left half
    ("`" . delete-forward-char)          ("ё" . delete-forward-char)     ("~" . keyamp-qwerty-to-engineer-engram) ("Ë" . keyamp-qwerty-to-engineer-engram)
    ("1" . kmacro-record)                                                ("!" . ignore)
    ("2" . kmacro-helper)                                                ("@" . ignore)
    ("3" . kmacro-play)                                                  ("#" . ignore) ("№" . ignore)
    ("4" . append-to-register-1)                                         ("$" . ignore)
    ("5" . repeat)                                                       ("%" . ignore)

    ("q" . insert-space-before)          ("й" . insert-space-before)     ("Q" . ignore) ("Й" . ignore)
    ("w" . backward-kill-word)           ("ц" . backward-kill-word)      ("W" . ignore) ("Ц" . ignore)
    ("e" . undo)                         ("у" . undo)                    ("E" . ignore) ("У" . ignore)
    ("r" . kill-word)                    ("к" . kill-word)               ("R" . ignore) ("К" . ignore)
    ("t" . cut-text-block)               ("е" . cut-text-block)          ("T" . ignore) ("Е" . ignore)

    ("a" . shrink-whitespaces)           ("ф" . shrink-whitespaces)      ("A" . ignore) ("Ф" . ignore)
    ("s" . open-line)                    ("ы" . open-line)               ("S" . ignore) ("Ы" . ignore)
    ("d" . delete-backward)              ("в" . delete-backward)         ("D" . ignore) ("В" . ignore)
    ("f" . newline)                      ("а" . newline)                 ("F" . ignore) ("А" . ignore)
    ("g" . mark-mode)                    ("п" . mark-mode)               ("G" . ignore) ("П" . ignore)

    ("z" . toggle-comment)               ("я" . toggle-comment)          ("Z" . ignore) ("Я" . ignore)
    ("x" . cut-line-or-selection)        ("ч" . cut-line-or-selection)   ("X" . ignore) ("Ч" . ignore)
    ("c" . copy-line-or-selection)       ("с" . copy-line-or-selection)  ("C" . ignore) ("С" . ignore)
    ("v" . paste-or-paste-previous)      ("м" . paste-or-paste-previous) ("V" . ignore) ("М" . ignore)
    ("b" . toggle-letter-case)           ("и" . toggle-letter-case)      ("B" . ignore) ("И" . ignore)

    ;; right half
    ("6" . pass)                                                         ("^" . ignore)
    ("7" . number-to-register)                                           ("&" . ignore)
    ("8" . copy-to-register)                                             ("*" . goto-matching-bracket) ; qwerty「*」→「=」engram, qwerty「/」→「=」ru pc karabiner
    ("9" . eshell)                                                       ("(" . ignore)
    ("0" . terminal)                                                     (")" . ignore)
    ("-" . tetris)                                                       ("_" . ignore)
    ("=" . goto-matching-bracket)                                        ("+" . ignore)

    ("y"  . search-current-word)         ("н" . search-current-word)     ("Y" . ignore) ("Н" . ignore)
    ("u"  . back-word)                   ("г" . back-word)               ("U" . ignore) ("Г" . ignore)
    ("i"  . previous-line)               ("ш" . previous-line)           ("I" . ignore) ("Ш" . ignore)
    ("o"  . forw-word)                   ("щ" . forw-word)               ("O" . ignore) ("Щ" . ignore)
    ("p"  . exchange-point-and-mark)     ("з" . exchange-point-and-mark) ("P" . ignore) ("З" . ignore)
    ("["  . other-frame)                 ("х" . other-frame)             ("{" . ignore) ("Х" . ignore)
    ("]"  . write-file)                  ("ъ" . write-file)              ("}" . ignore) ("Ъ" . ignore)
    ("\\" . bookmark-set)                                                ("|" . ignore)

    ("h" . beg-of-line-or-block)         ("р" . beg-of-line-or-block)    ("H"  . ignore) ("Р" . ignore)
    ("j" . backward-char)                ("о" . backward-char)           ("J"  . ignore) ("О" . ignore)
    ("k" . next-line)                    ("л" . next-line)               ("K"  . ignore) ("Л" . ignore)
    ("l" . forward-char)                 ("д" . forward-char)            ("L"  . ignore) ("Д" . ignore)
    (";" . end-of-line-or-block)         ("ж" . end-of-line-or-block)    (":"  . ignore) ("Ж" . ignore)
    ("'" . alternate-buffer)             ("э" . alternate-buffer)        ("\"" . ignore) ("Э" . ignore)

    ("n" . isearch-forward)              ("т" . isearch-forward)         ("N" . ignore) ("Т" . ignore)
    ("m" . backward-left-bracket)        ("ь" . backward-left-bracket)   ("M" . ignore) ("Ь" . ignore)
    ("," . next-window-or-frame)         ("б" . next-window-or-frame)    ("<" . ignore) ("Б" . ignore)
    ("." . forward-right-bracket)        ("ю" . forward-right-bracket)   (">" . ignore) ("Ю" . ignore)
    ("/" . goto-matching-bracket)                                        ("?" . ignore)

    ("<left>" . prev-user-buffer) ("<right>" . next-user-buffer)
    ("<up>"   . up-line)          ("<down>"  . down-line)))

(keyamp--map (define-prefix-command 'keyamp-left-leader-map)
  '(("SPC" . select-text-in-quote)
    ("DEL" . select-block)             ("<backspace>" . select-block)
    ("RET" . execute-extended-command) ("<return>"    . execute-extended-command)
    ("TAB" . toggle-ibuffer)           ("<tab>"       . toggle-ibuffer)
    ("ESC" . ignore)                   ("<escape>"    . ignore)

    ;; left leader left half
    ("`" . ignore)
    ("1" . periodic-chart)
    ("2" . kmacro-name-last-macro)
    ("3" . apply-macro-to-region-lines)
    ("4" . clear-register-1)
    ("5" . repeat-complex-command)

    ("q" . reformat-lines)
    ("w" . org-ctrl-c-ctrl-c)
    ("e" . split-window-below)
    ("r" . query-replace)
    ("t" . kill-line)

    ("a" . delete-window)
    ("s" . prev-user-buffer)
    ("d" . delete-other-windows)
    ("f" . next-user-buffer)
    ("g" . rectangle-mark-mode)

    ("z" . universal-argument)
    ("x" . save-buffers-kill-terminal)
    ("c" . copy-to-register-1)
    ("v" . paste-from-register-1)
    ("b" . toggle-previous-letter-case)

    ;; left leader right half
    ("6" . ignore)
    ("7" . jump-to-register)
    ("8" . ignore)
    ("9" . ignore)
    ("0" . ignore)
    ("-" . ignore)
    ("=" . ignore)
    ("y" . find-name-dired)
    ("u" . bookmark-jump)

    ("i e" . flyspell-buffer)               ("i i" . show-in-desktop)
    ("i f" . count-words)                   ("i j" . set-buffer-file-coding-system)
    ("i s" . count-matches)                 ("i l" . revert-buffer-with-coding-system)

    ("o"  . switch-to-buffer)
    ("p"  . view-echo-area-messages)
    ("["  . screenshot)
    ("]"  . find-file)
    ("\\" . bookmark-rename)
    ("h"  . recentf-open-files)

    ("j e" . hl-line-mode)                  ("j i" . abbrev-mode)
    ("j s" . display-line-numbers-mode)     ("j l" . narrow-to-region-or-block)
    ("j d" . whitespace-mode)               ("j k" . narrow-to-defun)
    ("j f" . toggle-case-fold-search)       ("j j" . widen)
    ("j g" . toggle-word-wrap)              ("j h" . narrow-to-page)
    ("j a" . text-scale-adjust)             ("j ;" . glyphless-display-mode)
    ("j t" . toggle-truncate-lines)         ("j y" . visual-line-mode)

    ("k e" . json-pretty-print-buffer)      ("k i" . move-to-column)
    ("k s" . space-to-newline)              ("k l" . list-recently-closed)
    ("k d" . ispell-word)                   ("k k" . list-matching-lines)
    ("k f" . delete-matching-lines)
    ("k g" . delete-non-matching-lines)     ("k h" . reformat-to-sentence-lines)
    ("k r" . quote-lines)                   ("k u" . escape-quotes)
    ("k t" . delete-duplicate-lines)        ("k y" . slash-to-double-backslash)
    ("k v" . change-bracket-pairs)          ("k n" . double-backslash-to-slash)
    ("k w" . sort-lines-key-value)          ("k o" . slash-to-backslash)
    ("k x" . insert-column-a-z)             ("k ." . sort-lines-block-or-region)
    ("k c" . cycle-hyphen-lowline-space)    ("k ," . sort-numeric-fields)

    ("l" . describe-foo-at-point)
    (";" . bookmark-bmenu-list)
    ("'" . toggle-debug-on-error)
    ("n" . proced)
    ("m" . downloads)
    ("," . open-last-closed)
    ("." . player)
    ("/" . goto-line)

    ("i ESC" . ignore) ("i <escape>" . ignore)
    ("j ESC" . ignore) ("j <escape>" . ignore)
    ("k ESC" . ignore) ("k <escape>" . ignore)))

(keyamp--map (define-prefix-command 'keyamp-right-leader-map)
  '(("SPC" . extend-selection)
    ("DEL" . select-line)              ("<backspace>" . select-line)
    ("RET" . execute-extended-command) ("<return>"    . execute-extended-command)
    ("TAB" . news)                     ("<tab>"       . news)
    ("ESC" . ignore)                   ("<escape>"    . ignore)

    ;; right leader left half
    ("`" . ignore)
    ("1" . ignore)
    ("2" . insert-kbd-macro)
    ("3" . ignore)
    ("4" . ignore)
    ("5" . ignore)

    ("q" . fill-or-unfill)
    ("w" . sun-moon)

    ("e e" . todo)                      ("e i" . shopping)
    ("e d" . calendar)                  ("e k" . weather)
    ("e f" . org-time-stamp)            ("e j" . clock)

    ("r" . query-replace-regexp)
    ("t" . calculator)
    ("a" . mark-whole-buffer)
    ("s" . clean-whitespace)

    ("d e" . org-shiftup)               ("d i" . eval-defun)
    ("d s" . shell-command-on-region)   ("d l" . elisp-eval-region-or-buffer)
    ("d d" . insert-date)               ("d k" . run-current-file)
    ("d f" . shell-command)             ("d j" . eval-last-sexp)
    ("d r" . async-shell-command)       ("d p" . elisp-byte-compile-file)
    ("d v" . stow)

    ("f e" . insert-emacs-quote)        ("f i" . insert-ascii-single-quote)
    ("f f" . insert-char)               ("f j" . insert-brace)
    ("f d" . emoji-insert)              ("f k" . insert-paren)
    ("f s" . insert-formfeed)           ("f l" . insert-square-bracket)
    ("f g" . insert-curly-single-quote) ("f h" . insert-double-curly-quote)
    ("f r" . insert-single-angle-quote) ("f u" . insert-ascii-double-quote)
    ("f t" . insert-double-angle-quote) ("f v" . insert-backtick-quote)

    ("g" . new-empty-buffer)
    ("z" . goto-char)
    ("x" . cut-all)
    ("c" . copy-all)
    ("v" . tasks)
    ("b" . title-case-region-or-line)

    ;; right leader right half
    ("6" . ignore)
    ("7" . increment-register)
    ("8" . insert-register)
    ("9" . toggle-theme)
    ("0" . ignore)
    ("-" . snake)
    ("=" . ignore)

    ("y"  . find-text)
    ("u"  . pop-local-mark-ring)
    ("i"  . copy-file-path)
    ("o"  . set-mark-deactivate-mark)
    ("p"  . show-kill-ring)
    ("["  . toggle-frame-maximized)
    ("]"  . rename-visited-file)
    ("\\" . bookmark-delete)

    ("h" . scroll-down-command)
    ("j" . read-only-mode)
    ("k" . make-backup-and-save)
    ("l" . describe-key)
    (";" . scroll-up-command)
    ("'" . sync)

    ("n" . save-buffer)
    ("m" . dired-jump)
    ("," . save-close-current-buffer)
    ("." . recenter-top-bottom)
    ("/" . mark-defun)     ("*" . mark-defun)

    ("e ESC" . ignore) ("e <escape>" . ignore)
    ("d ESC" . ignore) ("d <escape>" . ignore)
    ("f ESC" . ignore) ("f <escape>" . ignore)))


;; core remaps

(keyamp--map-leaders help-map '(lookup-word-definition . lookup-google-translate))
(keyamp--map help-map
  '(("ESC" . ignore)           ("<escape>" . ignore)
    ("RET" . lookup-web)       ("<return>" . lookup-web)
    ("TAB" . lookup-wikipedia) ("<tab>"    . lookup-wikipedia)
    ("e" . describe-char)      ("i" . info)
    ("s" . info-lookup-symbol) ("j" . describe-function)
    ("d" . man)                ("k" . describe-key)
    ("f" . elisp-index-search) ("l" . describe-variable)
    ("q" . describe-syntax)    ("p" . apropos-documentation)                               ("<f1>" . ignore) ("<help>" . ignore) ("C-w" . ignore) ("C-c" . ignore)
    ("w" . describe-bindings)  ("o" . lookup-all-dictionaries)                             ("C-o"  . ignore) ("C-\\"   . ignore) ("C-n" . ignore) ("C-f" . ignore)
    ("r" . describe-mode)      ("u" . lookup-all-synonyms)                                 ("C-s"  . ignore) ("C-e"    . ignore) ("'"   . ignore) ("6"   . ignore)
    ("a" . describe-face)      (";" . lookup-wiktionary)                                   ("9"    . ignore) ("L"      . ignore) ("n"   . ignore) ("p"   . ignore) ("v" . ignore)
    ("g" . apropos-command)    ("h" . view-lossage)                                        ("?"    . ignore) ("A"      . ignore) ("U"   . ignore) ("S"   . ignore)
    ("z" . apropos-variable)   ("." . lookup-word-dict-org)
    ("x" . apropos-value)      ("," . lookup-etymology)
    ("c" . describe-coding-system)))

(keyamp--map global-map '(("C-r" . open-file-at-cursor) ("C-t" . hippie-expand)
  ("<double-mouse-1>" . extend-selection)   ("<mouse-3>" . select-block)
  ("<header-line> <mouse-1>" . other-frame) ("<header-line> <mouse-3>" . make-frame-command)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . repeat)))
  (keyamp--map-leaders x '("d" . "d")) (keyamp--set-map x '(repeat)))
(with-sparse-keymap-x (keyamp--map-leaders x '(hippie-expand-undo . insert-space-before))
  (keyamp--map x '(("RET" . hippie-expand) ("<return>" . hippie-expand)))
  (keyamp--set-map x '(hippie-expand)))

(keyamp--map isearch-mode-map '(("<escape>" . isearch-cancel) ("C-^" . ignore)
    ("C-h"   . isearch-repeat-backward) ("C-r"   . isearch-repeat-forward)
    ("TAB"   . isearch-yank-kill)       ("<tab>" . isearch-yank-kill)))
(with-sparse-keymap-x (keyamp--map x
    '(("i" . isearch-ring-retreat)    ("ш" . isearch-ring-retreat)
      ("j" . isearch-repeat-backward) ("о" . isearch-repeat-backward)
      ("k" . isearch-ring-advance)    ("л" . isearch-ring-advance)
      ("l" . isearch-repeat-forward)  ("д" . isearch-repeat-forward)
      ("e" . isearch-ring-retreat)    ("у" . isearch-ring-retreat)
      ("s" . isearch-repeat-backward) ("ы" . isearch-repeat-backward)
      ("d" . isearch-ring-advance)    ("в" . isearch-ring-advance)
      ("f" . isearch-repeat-forward)  ("а" . isearch-repeat-forward)))
  (keyamp--map-leaders x '(isearch-repeat-backward . isearch-repeat-forward))
  (keyamp--set-map x '(isearch-ring-retreat isearch-repeat-backward isearch-ring-advance
      isearch-repeat-forward search-current-word isearch-yank-kill)))
(with-sparse-keymap-x (keyamp--map-leaders x '(isearch-ring-retreat . isearch-ring-advance))
  (keyamp--map x '(("v" . isearch-yank-kill) ("м" . isearch-yank-kill)))
  (keyamp--set-map-hook x '(isearch-mode-hook) nil nil :repeat))


;; command screen

(with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
  (keyamp--map x '(("TAB" . toggle-ibuffer) ("<tab>" . toggle-ibuffer)))
  (keyamp--remap x '(("q" . delete-frame) ("w" . sun-moon)
      ("e" . split-window-below)   ("r" . make-frame-command)
      ("t" . calculator)           ("u" . bookmark-jump)
      ("o" . switch-to-buffer)     ("p" . view-echo-area-messages)
      ("a" . delete-window)        ("s" . prev-user-buffer)
      ("d" . delete-other-windows) ("f" . next-user-buffer)
      ("g" . new-empty-buffer)     ("x" . works)
      ("c" . agenda)               ("v" . tasks)
      ("m" . downloads)            ("." . player)))
  (keyamp--set-map x '(next-user-buffer prev-user-buffer delete-other-windows
    save-close-current-buffer split-window-below alternate-buffer)))

(with-sparse-keymap-x (keyamp--map-leaders x '("'" . "m"))
  (keyamp--remap x '(("m" . dired-jump)
    ("e" . split-window-below) ("d" . delete-other-windows)
    ("s" . prev-user-buffer)   ("f" . next-user-buffer)))
  (keyamp--set-map x '(dired-jump downloads player)))
(with-sparse-keymap-x (keyamp--map-leaders x '("," . "m"))
  (keyamp--remap x '(("," . save-close-current-buffer) ("m" . dired-jump)))
  (keyamp--set-map x '(save-close-current-buffer)))
(with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
  (keyamp--remap x '(("s" . prev-user-buffer) ("f" . tasks)
  ("x" . works) ("c" . agenda) ("v" . tasks))) (keyamp--set-map x '(tasks)))
(with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
  (keyamp--remap x '(("s" . prev-user-buffer) ("f" . works)
  ("x" . works) ("c" . agenda) ("v" . tasks))) (keyamp--set-map x '(works)))
(with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
  (keyamp--remap x '(("s" . dired-find-prev-file) ("f" . dired-find-next-file)))
  (keyamp--set-map x '(dired-find-prev-file dired-find-next-file)))


;; command edit

(with-sparse-keymap-x (keyamp--map-leaders x '("`" . "`"))
  (keyamp--set-map x '(delete-forward-char)))
(with-sparse-keymap-x (keyamp--map-leaders x '("d" . "q"))
  (keyamp--set-map x '(delete-backward insert-space-before)))
(with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
  (keyamp--remap x '(("s" . backward-kill-word) ("f" . kill-word)))
  (keyamp--set-map x '(backward-kill-word kill-word)))
(with-sparse-keymap-x (keyamp--map-leaders x '("e" . "d"))
  (keyamp--remap x '(("d" . undo-redo))) (keyamp--set-map x '(undo undo-redo)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . cut-text-block)))
  (keyamp--set-map x '(cut-text-block)))

(with-sparse-keymap-x (keyamp--remap x '(("d" . shrink-whitespaces)))
  (keyamp--map-leaders x '("d" . "d")) (keyamp--set-map x '(shrink-whitespaces)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . toggle-comment)))
  (keyamp--map-leaders x '("d" . "d")) (keyamp--set-map x '(toggle-comment)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . cut-line-or-selection)))
  (keyamp--map-leaders x '("d" . "d")) (keyamp--set-map x '(cut-line-or-selection)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . copy-line-or-selection)))
  (keyamp--map-leaders x '("d" . "d")) (keyamp--set-map x '(copy-line-or-selection)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . paste-or-paste-previous)))
  (keyamp--set-map x '(paste-or-paste-previous)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . toggle-letter-case)))
  (keyamp--set-map x '(toggle-letter-case)))

(with-sparse-keymap-x (keyamp--map-leaders x '("d" . "e"))
  (keyamp--remap x '(("e" . org-shiftup) ("d" . org-shiftdown) ("c" . agenda)))
  (keyamp--set-map x '(org-shiftup org-shiftdown)))
(with-sparse-keymap-x (keyamp--remap x '(("e" . todo) ("c" . agenda)))
  (keyamp--set-map x '(todo insert-date)))
(with-sparse-keymap-x (keyamp--remap x '(("d" . cycle-hyphen-lowline-space)))
  (keyamp--set-map x '(cycle-hyphen-lowline-space)))


;; command repeat

(with-sparse-keymap-x (keyamp--remap x '(("i" . up-line) ("k" . down-line)))
  (keyamp--map-leaders x '("<up>" . "<down>"))
  (keyamp--set-map x '(up-line down-line)))
(with-sparse-keymap-x (keyamp--map-leaders x '("m" . "."))
  (keyamp--set-map x '(backward-left-bracket forward-right-bracket)))
(with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
  (keyamp--remap x '(("i" . beg-of-line-or-block)  ("k" . end-of-line-or-block)
    ("h" . beg-of-line-or-buffer) (";" . end-of-line-or-buffer)))
  (keyamp--set-map x '(beg-of-line-or-block end-of-line-or-block
    beg-of-line-or-buffer end-of-line-or-buffer)))

(with-sparse-keymap-x (keyamp--remap x '(("j" . back-word) ("l" . forw-word)
    ("u" . backward-punct) ("o" . forward-punct)))
  (keyamp--map-leaders x '("j" . "l"))
  (keyamp--set-map x '(back-word forw-word backward-punct forward-punct)))
(with-sparse-keymap-x (keyamp--remap x '(("i" . scroll-down-line) ("k" . scroll-up-line)))
  (keyamp--map-leaders x '("i" . "k")) (keyamp--set-map x '(scroll-down-line scroll-up-line)))
(with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
  (keyamp--remap x '(("i" . scroll-down-command) ("k" . scroll-up-command)
    ("e" . scroll-down-command) ("d" . scroll-up-command)))
  (keyamp--set-map x '(scroll-down-command scroll-up-command)))

(with-sparse-keymap-x (keyamp--remap x '(("k" . pop-local-mark-ring)))
  (keyamp--set-map x '(pop-local-mark-ring)))
(with-sparse-keymap-x (keyamp--map-leaders x '("k" . "k"))
  (keyamp--remap x '(("k" . recenter-top-bottom))) (keyamp--set-map x '(recenter-top-bottom)))
(with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
  (keyamp--remap x '(("i" . beg-of-line-or-block) ("k" . select-block)))
  (keyamp--set-map x '(select-block)))
(with-sparse-keymap-x (keyamp--map-leaders x '("k" . "k"))
  (keyamp--remap x '(("k" . extend-selection))) (keyamp--set-map x '(extend-selection)))
(with-sparse-keymap-x (keyamp--map-leaders x '("k" . "k"))
  (keyamp--remap x '(("k" . select-line))) (keyamp--set-map x '(select-line)))
(with-sparse-keymap-x (keyamp--map-leaders x '("k" . "k"))
  (keyamp--remap x '(("k" . select-text-in-quote))) (keyamp--set-map x '(select-text-in-quote)))

(with-sparse-keymap-x (keyamp--map-leaders x
  '((lambda () (interactive) (text-scale-adjust -1)) . (lambda () (interactive) (text-scale-adjust 1))))
  (keyamp--map x '(("TAB" . (lambda () (interactive) (text-scale-adjust 0)))
    ("<tab>" . (lambda () (interactive) (text-scale-adjust 0)))))
  (keyamp--set-map x '(text-scale-adjust)))


;; modes remap

(defun keyamp-insert-minibuffer ()
  "If minibuffer input not empty or default value then confirm
instead of insert mode activation."
  (interactive)
  (if (or (< 0 (length (buffer-substring (minibuffer-prompt-end) (point))))
          (< 0 (length minibuffer-default)))
      (exit-minibuffer) (keyamp-insert)))

(defun keyamp-escape-minibuffer ()
  "If minibuffer input not empty or default value then activate
command mode instead of quit minibuffer."
  (interactive)
  (if (or (< 0 (length (buffer-substring (minibuffer-prompt-end) (point))))
          (< 0 (length minibuffer-default)))
      (keyamp-escape) (abort-recursive-edit)))

(defun keyamp-minibuffer-n ()
  "Insert literally n to minibuffer."
  (interactive)
  (keyamp-insert-init) (execute-kbd-macro (kbd "n")))

(defun keyamp-minibuffer-y ()
  "Insert literally y to minibuffer."
  (interactive)
  (keyamp-insert-init) (execute-kbd-macro (kbd "y")))

(with-eval-after-load 'minibuffer
  (with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
    (keyamp--remap x '((end-of-line-or-block . keyamp-minibuffer-n)
        (backward-kill-word . keyamp-minibuffer-y)
        (keyamp-insert      . keyamp-insert-minibuffer)
        (keyamp-escape      . keyamp-escape-minibuffer)))
    (keyamp--set-map-hook x '(minibuffer-setup-hook) :command nil :repeat))
  (advice-add 'paste-or-paste-previous :after (lambda (&rest r)
    (when (minibufferp) (keyamp-insert))))
  (keyamp--remap y-or-n-p-map '(("i" . y-or-n-p-insert-n)
    ("d" . y-or-n-p-insert-n) ("k" . y-or-n-p-insert-y)))
  (keyamp--remap minibuffer-local-map
    '(("i" . previous-line-or-history-element) ("k" . next-line-or-history-element)
      (select-block . previous-line-or-history-element)))
  (keyamp--remap minibuffer-mode-map
    '(("i" . previous-line-or-history-element) ("k" . next-line-or-history-element)
      (select-block . previous-line-or-history-element))))

(with-eval-after-load 'icomplete (keyamp--map icomplete-minibuffer-map
    '(("RET"      . icomplete-exit-or-force-complete-and-exit)
      ("<return>" . icomplete-exit-or-force-complete-and-exit)))
  (keyamp--remap icomplete-minibuffer-map
    '(("i" . icomplete-backward-completions) ("k" . icomplete-forward-completions)
      (extend-selection . icomplete-forward-completions)))
  (with-sparse-keymap-x (keyamp--remap x '(("RET" . icomplete-exit-or-force-complete-and-exit)
      ("i" . icomplete-backward-completions) ("k" . icomplete-forward-completions)
      ("e" . icomplete-backward-completions) ("d" . icomplete-forward-completions)))
    (keyamp--map-leaders x '("i" . "k"))
    (keyamp--set-map x '(icomplete-backward-completions icomplete-forward-completions)))
  (with-sparse-keymap-x (keyamp--remap x
    '(("i" . previous-line-or-history-element) ("k" . next-line-or-history-element)
      ("e" . previous-line-or-history-element) ("d" . next-line-or-history-element)))
    (keyamp--set-map-hook x '(icomplete-minibuffer-setup-hook) nil nil :repeat))
  (with-sparse-keymap-x (keyamp--remap x '(("RET" . exit-minibuffer)
    ("i" . previous-line-or-history-element) ("k" . next-line-or-history-element)
    ("e" . previous-line-or-history-element) ("d" . next-line-or-history-element)))
    (keyamp--map-leaders x '("i" . "k"))
    (keyamp--set-map x '(previous-line-or-history-element next-line-or-history-element))))

(add-hook 'ido-setup-hook
  (lambda () (keyamp--remap ido-completion-map '(("RET" . ido-exit-minibuffer)
               ("i" . ido-prev-match) ("k" . ido-next-match)))
    (with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
      (keyamp--remap x '(("e" . ido-prev-match) ("d" . ido-next-match)))
      (keyamp--set-map x '(ido-prev-match ido-next-match)))))

(with-eval-after-load 'dired
  (keyamp--map dired-mode-map '(("C-h" . dired-do-delete) ("C-r" . open-in-external-app)
    ("<mouse-1>" . mouse-set-point) ("<double-mouse-1>" . dired-find-file)))
  (keyamp--remap dired-mode-map '(("RET" . dired-find-file) ("f" . dired-sort)
    ("m" . dired-mark)    ("." . dired-unmark)
    ("z" . revert-buffer) ("q" . dired-create-directory)
    (copy-to-register-1    . dired-do-copy)
    (paste-from-register-1 . dired-do-rename)
    (mark-whole-buffer     . dired-toggle-marks)))
  (with-sparse-keymap-x (keyamp--map-leaders x '(dired-unmark . dired-mark))
    (keyamp--set-map x '(dired-unmark dired-mark))))
(with-eval-after-load 'wdired
  (keyamp--map wdired-mode-map '(("C-h" . wdired-abort-changes) ("C-r" . wdired-finish-edit))))
(with-eval-after-load 'dired-util
  (keyamp--map dired-mode-map '(("TAB" . dired-leader-map) ("<tab>" . dired-leader-map)))
  (keyamp--map dired-leader-map '(("ESC" . ignore) ("<escape>" . ignore)
    ("TAB" . dired-hide-details-mode)        ("<tab>" . dired-hide-details-mode)
    ("q" . dired-image-remove-transparency)  ("e" . dired-optimize-png)
    ("u" . dired-2drawing)                   ("o" . dired-rotate-img-right)
    ("p" . dired-rotate-img-left)            ("a" . dired-image-autocrop)
    ("s" . dired-open-marked)                ("d" . dired-show-metadata)
    ("f" . dired-remove-all-metadata)        ("h" . dired-rotate-img-180)
    ("k" . dired-rename-space-to-underscore) ("l" . dired-2png)
    (";" . dired-scale-image)                ("\'" . dired-to-zip-encrypted)
    ("c" . dired-2jpg)                       ("/" . dired-to-zip))))

(with-eval-after-load 'rect (keyamp--remap rectangle-mark-mode-map
  '(("RET" . string-rectangle)     ("q" . open-rectangle)
    ("c" . copy-rectangle-as-kill) ("d" . kill-rectangle)
    ("v" . yank-rectangle)         ("8" . copy-rectangle-to-register)
    ("z" . rectangle-number-lines) ("x" . clear-rectangle)
    (clean-whitespace . delete-whitespace-rectangle))))

(with-eval-after-load 'ibuf-ext (keyamp--map ibuffer-mode-map
    '(("C-h" . ibuffer-do-delete) ("TAB" . news) ("<tab>" . news)
      ("<double-mouse-1>" . ibuffer-visit-buffer)))
  (keyamp--remap ibuffer-mode-map '(("RET" . ibuffer-visit-buffer)
    (";" . ibuffer-forward-filter-group) ("h" . ibuffer-backward-filter-group)
    ("q" . delete-frame)                 ("w" . sun-moon)
    ("e" . split-window-below)           ("r" . make-frame-command)
    ("t" . calculator)                   ("u" . bookmark-jump)
    ("o" . switch-to-buffer)             ("p" . view-echo-area-messages)
    ("a" . delete-window)                ("s" . prev-user-buffer)
    ("d" . delete-other-windows)         ("f" . next-user-buffer)
    ("g" . new-empty-buffer)             ("x" . works)
    ("c" . agenda)                       ("v" . tasks)
    ("m" . downloads)                    ("." . player)
    (select-block . prev-user-buffer)    (extend-selection . next-user-buffer)))
  (keyamp--map ibuffer-mode-filter-group-map
    '(("C-h" . help-command) ("<mouse-1>" . ibuffer-toggle-filter-group)))
  (keyamp--remap ibuffer-mode-filter-group-map '(("RET" . ibuffer-toggle-filter-group) ))
  (with-sparse-keymap-x (keyamp--remap x
    '(("i" . ibuffer-backward-filter-group) ("k" . ibuffer-forward-filter-group)
      ("e" . ibuffer-backward-filter-group) ("d" . ibuffer-forward-filter-group)
      ("h" . beg-of-line-or-buffer)         (";" . end-of-line-or-buffer)))
    (keyamp--set-map x '(ibuffer-backward-filter-group ibuffer-forward-filter-group ibuffer-toggle-filter-group))))
(with-eval-after-load 'ibuffer (keyamp--map ibuffer-name-map '(("<mouse-1>" . ibuffer-jump))))
(with-sparse-keymap-x (keyamp--remap x '(("d" . ibuffer-do-delete)))
  (keyamp--map-leaders x '("d" . "d")) (keyamp--set-map x '(ibuffer-do-delete)))

(with-eval-after-load 'company
  (with-sparse-keymap-x (keyamp--remap x '(("n" . company-search-candidates)
    (keyamp-escape . company-abort) (keyamp-insert . company-complete-selection)
    ("i" . company-select-previous) ("k" . company-select-next)
    ("j" . company-previous-page)   ("l" . company-next-page)
    ("e" . company-select-previous) ("d" . company-select-next)
    ("s" . company-previous-page)   ("f" . company-next-page)))
    (keyamp--map-leaders x '("i" . "k"))
    (keyamp--set-map x '(company-select-previous company-select-next company-previous-page
      company-next-page company-show-doc-buffer company-search-abort))
    (add-hook 'keyamp-command-hook (lambda () (when company-candidates (set-transient-map x)
               (setq this-command 'keyamp--repeat-dummy)))))
  (with-sparse-keymap-x (keyamp--set-map x '(company-search-abort) :command)
    (keyamp--set-map x '(company-abort company-complete-selection
      company-search-candidates) nil :insert))
  (keyamp--map company-search-map '(("<escape>" . company-search-abort)
    ("C-q" . company-search-repeat-backward) ("C-t" . company-search-repeat-forward))))

(with-eval-after-load 'transient
  (keyamp--map transient-base-map '(("<escape>" . transient-quit-one))))

(with-eval-after-load 'arc-mode (keyamp--remap archive-mode-map '(("RET" . archive-extract))))
(with-eval-after-load 'bookmark (keyamp--remap bookmark-bmenu-mode-map '(("RET" . bookmark-bmenu-this-window))))
(with-eval-after-load 'button (keyamp--remap button-map '(("RET" . push-button))))
(with-eval-after-load 'compile (keyamp--remap compilation-button-map '(("RET" . compile-goto-error))))
(with-eval-after-load 'flymake (keyamp--remap flymake-diagnostics-buffer-mode-map '(("RET" . flymake-goto-diagnostic))))
(with-eval-after-load 'gnus-art (keyamp--remap gnus-mime-button-map '(("RET" . gnus-article-press-button))))
(with-eval-after-load 'org-agenda (keyamp--remap org-agenda-mode-map '(("RET" . org-agenda-switch-to))))
(with-eval-after-load 'replace (keyamp--remap occur-mode-map '(("RET" . occur-mode-goto-occurrence))))
(with-eval-after-load 'shr (keyamp--remap shr-map '(("RET" . shr-browse-url))))
(with-eval-after-load 'simple (keyamp--remap completion-list-mode-map '(("RET" . choose-completion))))
(with-eval-after-load 'wid-edit (keyamp--remap widget-link-keymap '(("RET" . widget-button-press))))

(with-eval-after-load 'emms-playlist-mode (keyamp--remap emms-playlist-mode-map
  '(("RET" . emms-playlist-mode-play-smart)
    (extend-selection . emms-playlist-mode-play-smart))))

(with-eval-after-load 'doc-view (keyamp--remap doc-view-mode-map
    '(("i" . doc-view-previous-line-or-previous-page) ("k" . doc-view-next-line-or-next-page)
      ("j" . doc-view-previous-page)                  ("l" . doc-view-next-page)
      ("e" . doc-view-previous-line-or-previous-page) ("d" . doc-view-next-line-or-next-page)
      ("s" . doc-view-previous-page)                  ("f" . doc-view-next-page)
      ("u" . doc-view-shrink)                         ("o" . doc-view-enlarge)
      ("h" . doc-view-scroll-down-or-previous-page)   (";" . doc-view-scroll-up-or-next-page)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
    (keyamp--remap x
    '(("i" . doc-view-scroll-down-or-previous-page) ("k" . doc-view-scroll-up-or-next-page)
      ("e" . doc-view-scroll-down-or-previous-page) ("d" . doc-view-scroll-up-or-next-page)))
    (keyamp--set-map x '(doc-view-scroll-down-or-previous-page doc-view-scroll-up-or-next-page))))

(with-eval-after-load 'image-mode (keyamp--remap image-mode-map
    '(("j" . image-previous-file) ("l" . image-next-file)
      ("s" . image-previous-file) ("f" . image-next-file)
      ("i" . image-decrease-size) ("k" . image-increase-size)
      ("e" . image-dired)         ("d" . image-rotate)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("j" . "l"))
    (keyamp--set-map x '(image-previous-file image-next-file))))

(with-eval-after-load 'esh-mode
  (keyamp--map eshell-mode-map '(("C-h" . eshell-interrupt-process)))
  (keyamp--remap eshell-mode-map '(("x" . eshell-clear-input)
    (cut-all . eshell-clear) (select-block . eshell-previous-input)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
    (keyamp--remap x '(("i" . eshell-previous-input) ("k" . eshell-next-input)
      ("e" . eshell-previous-input) ("d" . eshell-next-input)
      (open-file-at-cursor . eshell-send-input)))
    (keyamp--set-map x '(eshell-send-input eshell-interrupt-process))
    (keyamp--set-map x '(eshell-previous-input eshell-next-input) :command)
    (keyamp--set-map-hook x '(eshell-mode-hook) nil :insert)))
(with-sparse-keymap-x (keyamp--set-map x '(save-close-current-buffer) :command))

(with-eval-after-load 'vterm
  (keyamp--map vterm-mode-map '(("C-h" . term-interrupt-subjob) ("C-q" . vterm-send-next-key)))
  (keyamp--remap vterm-mode-map '((select-block . vterm-send-up) (cut-all . vterm-clear)
    ("v" . vterm-yank) (paste-from-register-1 . vterm-yank-pop)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
    (keyamp--remap x '(("i" . vterm-send-up) ("k" . vterm-send-down)
      ("e" . vterm-send-up) ("d" . vterm-send-down)))
    (keyamp--set-map x '(vterm-send-return))
    (keyamp--set-map x '(vterm-send-up vterm-send-down) :command)
    (keyamp--set-map-hook x '(vterm-mode-hook) nil :insert)))

(with-eval-after-load 'info
  (keyamp--remap Info-mode-map '(("RET" . Info-follow-nearest-node)
    ("s" . Info-backward-node) ("f" . Info-forward-node)
    ("e" . Info-up)            ("d" . Info-next-reference)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
    (keyamp--set-map x '(Info-backward-node Info-forward-node))))

(with-eval-after-load 'help-mode (keyamp--remap help-mode-map
    '(("e" . backward-button) ("d" . forward-button)
      ("s" . help-go-back) ("f" . help-go-forward))))

(with-eval-after-load 'gnus-topic
  (keyamp--map gnus-topic-mode-map '(("TAB" . toggle-ibuffer) ("<tab>" . toggle-ibuffer)))
  (keyamp--remap gnus-topic-mode-map '(("RET" . gnus-topic-select-group)
    ("h" . gnus-topic-goto-prev-topic-line) (";" . gnus-topic-goto-next-topic-line)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("i" . "k"))
    (keyamp--remap x '(("i" . gnus-topic-goto-prev-topic-line) ("k" . gnus-topic-goto-next-topic-line)
      ("h" . gnus-beg-of-line-or-buffer)    (";" . gnus-end-of-line-or-buffer)))
    (keyamp--set-map x '(gnus-topic-goto-prev-topic-line
      gnus-topic-goto-next-topic-line gnus-beg-of-line-or-buffer
      gnus-end-of-line-or-buffer))))
(with-eval-after-load 'gnus-group (keyamp--remap gnus-group-mode-map
  '(("e" . gnus-group-enter-server-mode) ("d" . gnus-group-get-new-news))))
(with-eval-after-load 'gnus-sum (keyamp--map gnus-summary-mode-map
  '(("C-h" . gnus-summary-delete-article) ("C-r" . gnus-summary-save-parts)))
  (keyamp--remap gnus-summary-mode-map '(("RET" . gnus-summary-scroll-up)
    ("s" . gnus-summary-prev-group) ("f" . gnus-summary-next-group)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("s" . "f"))
    (keyamp--remap x '(("s" . gnus-summary-prev-group) ("f" . gnus-summary-next-group)))
    (keyamp--set-map x '(gnus-summary-prev-group gnus-summary-next-group))
    (keyamp--set-map-hook x '(gnus-summary-prepared-hook))))
(with-eval-after-load 'gnus-srvr (keyamp--remap gnus-server-mode-map
    '(("RET" . gnus-server-read-server) ("d" . gnus-server-exit)))
  (keyamp--remap gnus-browse-mode-map '(("RET" . gnus-browse-select-group))))

(with-eval-after-load 'snake (keyamp--remap snake-mode-map
    '(("RET" . snake-start-game) (keyamp-escape . snake-pause-game)
      ("d" . snake-move-up)      ("k" . snake-move-down)
      (delete-other-windows . snake-rotate-up)))
  (with-sparse-keymap-x (keyamp--map-leaders x '(snake-move-left . snake-move-right))
    (keyamp--set-map x '(snake-start-game snake-pause-game snake-move-left
      snake-move-right snake-move-down snake-move-up))
    (keyamp--set-map-hook x '(snake-mode-hook))))

(with-eval-after-load 'tetris (keyamp--remap tetris-mode-map
    '((keyamp-escape . tetris-pause-game)
      ("d" . tetris-rotate-prev) (delete-other-windows . tetris-rotate-prev)
      ("f" . tetris-rotate-next) (next-user-buffer     . tetris-rotate-next)
      ("k" . tetris-move-bottom) ("j" . tetris-move-down)))
  (with-sparse-keymap-x (keyamp--map-leaders x '(tetris-move-left . tetris-move-right))
    (keyamp--set-map x '(tetris-start-game tetris-pause-game tetris-move-left tetris-move-right
      tetris-rotate-prev tetris-rotate-next tetris-move-bottom tetris-move-down))))

(with-eval-after-load 'nov (keyamp--remap nov-mode-map
  '(("RET" . nov-browse-url)      ("d" . nov-goto-toc)
    ("s" . nov-previous-document) ("f" . nov-next-document))))

(with-eval-after-load 'find-replace (keyamp--map find-output-mode-map
  '(("TAB" . find-next-match) ("<tab>" . find-next-match)))
  (keyamp--remap find-output-mode-map '(("RET" . find--jump-to-place)))
  (with-sparse-keymap-x (keyamp--map-leaders x '("j" . "l"))
    (keyamp--remap x '(("i" . find-previous-file) ("j" . find-previous-match)
      ("k" . find-next-file)     ("l" . find-next-match)
      ("e" . find-previous-file) ("s" . find-previous-match)
      ("d" . find-next-file)     ("f" . find-next-match)))
   (keyamp--set-map x '(find-next-match find-previous-file
     find-previous-match find-next-file))))

(with-eval-after-load 'emacs-lisp-mode (keyamp--map emacs-lisp-mode-map
    '(("TAB" . emacs-lisp-leader-map) ("<tab>" . emacs-lisp-leader-map)
      ("S-<tab>" . ignore) ("<backtab>" . ignore)))
  (keyamp--map emacs-lisp-leader-map '(("ESC" . ignore) ("<escape>" . ignore)
     ("TAB" . emacs-lisp-complete-or-indent) ("<tab>" . emacs-lisp-complete-or-indent)
     ("d" . emacs-lisp-remove-paren-pair) ("k" . emacs-lisp-add-paren-around-symbol)
     ("f" . emacs-lisp-compact-parens))))

(with-sparse-keymap-x (keyamp--map-leaders x '(flymake-goto-prev-error . flymake-goto-next-error))
  (keyamp--set-map x '(flymake-goto-prev-error flymake-goto-next-error)))

(with-eval-after-load 'python-mode (keyamp--map python-mode-map
  '(("TAB" . python-indent-or-complete) ("<tab>"    . python-indent-or-complete)
    ("RET" . python-return-and-indent)  ("<return>" . python-return-and-indent)
    ("S-<tab>" . python-de-indent)      ("<backtab>" . python-de-indent)))
  (keyamp--remap python-mode-map '(("f" . python-return-and-indent)
    (reformat-lines . flymake-goto-next-error) (news . python-format-buffer))))

(with-eval-after-load 'go-mode (keyamp--map go-mode-map '(("TAB" . go-format-buffer)))
  (keyamp--remap go-mode-map '((describe-foo-at-point . xref-find-definitions)
    (describe-variable . xref-find-references) (reformat-lines . flymake-goto-next-error)))
  (with-sparse-keymap-x (keyamp--map-leaders x '(xref-go-back . xref-find-definitions))
    (keyamp--set-map x '(xref-go-back xref-find-definitions))))

(with-eval-after-load 'html-mode (keyamp--map html-mode-map
  '(("TAB" . html-leader-map)      ("<tab>" . html-leader-map)
    ("RET" . html-open-local-link) ("<return>" . html-open-local-link)
    ("C-r" . html-open-in-browser)))
  (keyamp--map html-leader-map
    '(("TAB" . html-insert-tag)                   ("<tab>" . html-insert-tag)
      ("RET" . html-insert-br-tag)                ("<return>" . html-insert-br-tag)
      ("<left>" . html-prev-opening-tag)          ("<right>" . html-next-opening-tag)
      ("<down>" . html-goto-matching-tag)         ("@" . html-encode-ampersand-entity)
      ("$" . html-percent-decode-url)             ("&" . html-decode-ampersand-entity)
      ("q" . html-make-citation)                  ("w" . nil)
      ("w ," . html-rename-source-file-path)
      ("w h" . html-resize-img)                   ("w q" . html-image-path-to-figure-tag)
      ("w j" . html-image-to-link)                ("w w" . html-image-to-img-tag)
      ("w c" . html-convert-to-jpg)               ("w o" . html-move-image-file)
      ("e" . html-remove-tag-pair)                ("r" . html-mark-unicode)
      ("y" . html-lines-to-table)                 ("u" . html-emacs-to-windows-kbd-notation)
      ("i" . html-all-urls-to-link)               ("o" . html-insert-pre-tag)
      ("[" . html-percent-encode-url)
      ("a <up>" . html-promote-header)            ("a <down>" . html-demote-header)
      ("a e" . html-remove-tags)                  ("a q" . html-compact-def-list)
      ("a ." . html-remove-list-tags)             ("a f" . html-remove-paragraph-tags)
      ("a ," . html-format-to-multi-lines)        ("a l" . html-disable-script-tag)
      ("a k" . html-markup-ruby)                  ("a a" . html-update-title-h1)
      ("a y" . html-remove-table-tags)            ("a h" . html-change-current-tag)
      ("s" . html-html-to-text)                   ("d" . html-select-element)
      ("f" . html-blocks-to-paragraph)            ("h" . html-lines-to-list)
      ("j" . html-any-to-link)                    ("k" . nil)
      ("k e" . html-dehtmlize-pre-tags)           ("k h" . html-bracket-to-markup)
      ("k j" . html-pre-tag-to-new-file)          ("k ;" . html-htmlize-region)
      ("k ," . html-rehtmlize-precode-buffer)     ("k k" . html-toggle-syntax-color-tags)
      ("l" . html-insert-date-section)            ("x" . html-lines-to-def-list)
      ("c" . html-join-tags)                      ("v" . html-keyboard-shortcut-markup)
      ("b" . html-make-link-defunct)
      ("m i" . html-ampersand-chars-to-unicode)   ("m h" . html-clone-file-in-link)
      ("m d" . html-url-to-dated-link)            ("m w" . html-url-to-iframe-link)
      ("m j" . html-local-links-to-relative-path) ("m f" . html-pdf-path-to-embed)
      ("m ," . html-named-entity-to-char)         ("m k" . html-local-links-to-fullpath)
      ("," . html-extract-url)                    ("." . html-word-to-anchor-tag)
      ("/ h" . html-open-in-chrome)               ("/ q" . html-open-in-firefox)
      ("/ ," . html-open-in-brave)                ("/ l" . html-open-in-safari))))

(with-eval-after-load 'js-mode (keyamp--map js-mode-map
  '(("TAB" . js-leader-map) ("<tab>" . js-leader-map)))
  (keyamp--map js-leader-map '(("h" . typescript-compile-file)
    ("TAB" . js-complete-or-indent) ("<tab>" . js-complete-or-indent)
    ("." . js-eval-region) ("," . js-eval-line)))
  (keyamp--remap js-mode-map '((news . js-format-buffer))))

(with-eval-after-load 'css-mode (keyamp--map css-mode-map
  '(("TAB" . css-leader-map) ("<tab>" . css-leader-map)))
   (keyamp--map css-leader-map '(("," . css-insert-random-color-hsl)
      ("TAB" . css-complete-or-indent) ("<tab>" . css-complete-or-indent)
      ("'" . css-hex-color-to-hsl)     ("a" . css-complete-symbol)
      ("h" . css-format-compact)       ("p" . css-format-compact-buffer)
      ("o" . css-format-expand-buffer) ("k" . css-format-expand)))
  (keyamp--remap css-mode-map '(("f" . css-smart-newline))))



(defconst keyamp-screen-commands-hash #s(hash-table test equal data
  (agenda                           t
   alternate-buffer                 t
   delete-other-windows             t
   dired-find-next-file             t
   dired-find-prev-file             t
   dired-jump                       t
   downloads                        t
   next-user-buffer                 t
   player                           t
   prev-user-buffer                 t
   save-close-current-buffer        t
   split-window-below               t
   sun-moon                         t
   tasks                            t
   view-echo-area-messages          t
   works                            t
   xref-find-definitions            t
   xref-go-back                     t)))

(defconst keyamp-edit-commands-hash #s(hash-table test equal data
  (delete-backward                  t
   delete-forward-char              t
   insert-space-before              t
   kill-region                      t
   shrink-whitespaces               t
   toggle-comment                   t
   undo                             t
   undo-redo                        t)))

(defconst keyamp-repeat-commands-hash #s(hash-table test equal data
  (backward-punct                   t
   back-word                        t
   beg-of-line-or-block             t
   beg-of-line-or-buffer            t
   backward-left-bracket            t
   company-select-previous          t
   company-select-next              t
   company-next-page                t
   company-previous-page            t
   copy-line-or-selection           t
   dired-mark                       t
   dired-unmark                     t
   down-line                        t
   end-of-line-or-block             t
   end-of-line-or-buffer            t
   eshell-next-input                t
   eshell-previous-input            t
   extend-selection                 t
   find-next-file                   t
   find-next-match                  t
   find-previous-file               t
   find-previous-match              t
   flymake-goto-next-error          t
   flymake-goto-prev-error          t
   forward-punct                    t
   forward-right-bracket            t
   forw-word                        t
   gnus-beg-of-line-or-buffer       t
   gnus-end-of-line-or-buffer       t
   gnus-topic-goto-next-topic-line  t
   gnus-topic-goto-prev-topic-line  t
   ibuffer-backward-filter-group    t
   ibuffer-forward-filter-group     t
   icomplete-backward-completions   t
   icomplete-forward-completions    t
   ido-next-match                   t
   ido-prev-match                   t
   isearch-repeat-backward          t
   isearch-repeat-forward           t
   isearch-ring-advance             t
   isearch-ring-retreat             t
   isearch-yank-kill                t
   keyamp--repeat-dummy             t
   next-line-or-history-element     t
   pop-local-mark-ring              t
   previous-line-or-history-element t
   recenter-top-bottom              t
   scroll-down-command              t
   scroll-up-command                t
   scroll-down-line                 t
   scroll-up-line                   t
   select-block                     t
   search-current-word              t
   select-line                      t
   select-text-in-quote             t
   up-line                          t
   vterm-send-down                  t
   vterm-send-up                    t)))



(defvar keyamp--deactivate-command-mode-func nil)
(defvar keyamp-insert-p t "Non-nil means insert is on.")
(defvar keyamp-repeat-p nil "Non-nil means repeat is on.")

(defun keyamp-command-init ()
  "Set command mode."
  (setq keyamp-insert-p nil)
  (if keyamp--deactivate-command-mode-func
      (funcall keyamp--deactivate-command-mode-func))
  (setq keyamp--deactivate-command-mode-func
        (set-transient-map keyamp-command-map (lambda () t))))

(defun keyamp-insert-init ()
  "Enter insert mode."
  (setq keyamp-insert-p t)
  (funcall keyamp--deactivate-command-mode-func))

(defun keyamp-set-var-karabiner (key val)
  "Set karabiner variable KEY to value VAL via shell command."
  (call-process keyamp-karabiner-cli nil 0 nil
                "--set-variables" (concat "{\"" key "\":" val "}")))

(when (file-exists-p keyamp-karabiner-cli)
  (add-hook 'keyamp-insert-hook
            (lambda () (keyamp-set-var-karabiner "insert mode activated" "1")))
  (add-hook 'keyamp-command-hook '
            (lambda () (keyamp-set-var-karabiner "insert mode activated" "0"))))

(defun keyamp-command ()
  "Activate command mode."
  (interactive)
  (keyamp-command-init)
  (run-hooks 'keyamp-command-hook))

(defun keyamp-insert ()
  "Activate insert mode."
  (interactive)
  (keyamp-insert-init)
  (run-hooks 'keyamp-insert-hook))

(defun keyamp-indicate ()
  "Indicate keyamp state. Run with `post-command-hook'."
  (cond
   ((gethash this-command keyamp-screen-commands-hash)
    (setq mode-line-front-space keyamp-command-indicator)
    (set-face-background 'cursor keyamp-command-cursor)
    (blink-cursor-mode 1))
   ((gethash this-command keyamp-repeat-commands-hash)
    (setq keyamp-repeat-p t)
    (setq mode-line-front-space keyamp-repeat-indicator)
    (set-face-background 'cursor keyamp-repeat-cursor)
    (blink-cursor-mode 0))
   ((or (gethash this-command keyamp-edit-commands-hash)
        (eq real-this-command 'repeat) keyamp-insert-p)
    (setq mode-line-front-space keyamp-insert-indicator)
    (set-face-background 'cursor keyamp-insert-cursor)
    (if keyamp-insert-p (blink-cursor-mode 1) (blink-cursor-mode 0)))
   (t (setq keyamp-repeat-p nil)
      (setq mode-line-front-space keyamp-command-indicator)
      (set-face-background 'cursor keyamp-command-cursor)
      (blink-cursor-mode 0))))

(defun keyamp-escape (&optional Keyamp-idle-p)
  "Return to command mode or escape everything.
If run by idle timer then emulate escape keyboard press."
  (interactive)
  (cond
   (Keyamp-idle-p     (execute-kbd-macro (kbd "<escape>")))
   (keyamp-insert-p   (keyamp-command))
   (keyamp-repeat-p   (keyamp-command))
   ((region-active-p) (deactivate-mark))
   ((minibufferp)     (abort-recursive-edit))
   (t                 (keyamp-command))))



;;;###autoload
(define-minor-mode keyamp
  "Key Amplifier."
  :global t
  :keymap keyamp-map
  (when keyamp
    (add-hook 'minibuffer-exit-hook  'keyamp-command)
    (add-hook 'isearch-mode-end-hook 'keyamp-command)
    (add-hook 'post-command-hook     'keyamp-indicate)
    (keyamp-catch-tty-ESC)
    (keyamp-define-input-source 'russian-computer)
    (keyamp-command)
    (setq keyamp-idle-timer
          (run-with-idle-timer keyamp-idle-timeout t 'keyamp-escape t))))

(provide 'keyamp)

;; Local Variables:
;; byte-compile-warnings: (not free-vars lexical)
;; End:
;;; keyamp.el ends here
