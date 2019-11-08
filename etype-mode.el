;;; ETYPE-MODE --- drill typing skill for Chinese wubi input method
;;
;; Author: Wu Peng <paul.w86!foxmail.com>
;; Copyright © 2019, Wu Peng, all rights reserved.
;; Created:  8 November 2019
;;
;;; Commentary:
;;
;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at your
;; option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
;; details.
;;
;; You should have received a copy of the GNU Lesser General Public License along
;; with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Code:

(defvar-local etype-word-code nil
  "记录将要录入的字的五笔编码，通过 `pyim' 模块的。")

(defvar-local etype-total-words-number nil
  "记录整篇文章的总字数。")

(defvar-local etype-completed-words-number nil
  "记录已经完成的字数。用于计算完成的百分比，显示在窗口头行上。")

(defvar-local etype-error-points nil
  "记录打错的字的位置。")

(defvar-local etype-start-time  nil
  "打字练习开始时间，当你打第二个字的时候会被设置，窗口头行会显示
  已经使用的时间，但是是在你打一个字之后才刷新显示。")

(defvar-local etype-last-point  nil
  "上一次输入时光标所在的位置。")

(defvar-local etype-window-width nil
  "正在录入的这一行的宽度。")

(defvar-local etype-line-beg-point nil
  "正在录入这一行的行首的位置。")

(defvar-local etype-start-point nil
  "记录文章开始的位置，主要用于设置开始的时间。")

(defvar etype-mode-map nil
  "设置 etype 模式的按键映射，在打字的过程中不允许使用各种移动
  光标的按键，除了 `backspace'。因为 evil 模式为 `use-local-map'
  和 `use-global-map' 添加了 advice ，所以模式命令首先将其关闭。
  在打字的过程中还可能因为其他命令的副作用又将 evil 模式打开，所
  以在 `pre-command-hook' 中进行了检查，并及时清除
  `evil-mode-map-alist'。如果有其他全局模式像 evil 这样的话则需要
  对代码进行一些修改。")

(setq etype-mode-map
      ( let ((map (make-sparse-keymap)))
        (set-keymap-parent map text-mode-map)
        (define-key map "\C-f" 'etype-pass)
        (define-key map "\C-b" 'etype-pass)
        (define-key map "\M-f" 'etype-pass)
        (define-key map "\M-b" 'etype-pass)
        (define-key map "\C-a" 'etype-pass)
        (define-key map "\C-e" 'etype-pass)
        (define-key map "\M-a" 'etype-pass)
        (define-key map "\M-e" 'etype-pass)
        (define-key map "\C-p" 'etype-pass)
        (define-key map "\C-n" 'etype-pass)
        (define-key map "\C-v" 'etype-pass)
        (define-key map "\M-v" 'etype-pass)
        (define-key map "\M-<" 'etype-pass)
        (define-key map "\M->" 'etype-pass)
        (define-key map "\C-d" 'etype-pass)
        (define-key map "\M-d" 'etype-pass)
        (define-key map "\C-k" 'etype-pass)
        (define-key map "\C-o" 'etype-pass)
        (define-key map "\C-j" 'etype-pass)
        (define-key map "<RET>" 'etype-pass)
        (define-key map "\M-r" 'etype-pass)
        (define-key map "\M-s" 'etype-pass)
        (define-key map "\C-M-r" 'etype-pass)
        (define-key map "\C-M-s" 'etype-pass)
        (define-key map "\C-\\" 'toggle-input-method)
        (define-key map (kbd  "C-SPC") 'toggle-input-method)
        map
        ))

(defvar-local etype-original-text nil
  "用于存储原始文本，当要重来一次时或者切换到其他模式时，恢复原来
  的内容。 `etype-restore-buffer' 及 `change-major-mode-hook'
  中会用到。")

(defvar etype-ignore-commands nil
  "为了弥补 `etype-mode-map' 中可能存在的不足，即有可能使用其
  他按键调用一些改变 point 的命令。为了禁止这些命令起作用，加入到
  `etype-ignore-commands' 列表中的命令都将重定向到
  `etype-pass'，什么也不干。")

(setq etype-ignore-commands
      '(
        delete-char
        delete-forward-char
        kill-line
        kill-word
        backward-kill-word
        delete-blank-lines

        open-line
        newline
        newline-and-indent
        indent-for-tab-command

        pyim-convert-code-at-point
        pyim-convert-string-at-point
        ))

(defvar etype-work-commands nil
  "这个变量存储 `etype-check-input-hook' 要响应的命令，只有这
  些命令被调用后才执行输入的检查，并更新相关显示。")

(setq etype-work-commands
      '(self-insert-command
        delete-backward-char
        etype-pass
        ))

(define-derived-mode etype-mode text-mode "Type"
  "这是一个中文五笔打字练习模式，类似于金山打字通。

首先会保存缓冲中的文本，而后修改缓冲内容，设置成逐行对照的样式，
设置相关变量和钩子，做到可以显示下一个字的编码，使用的时间，打字
的速度等。在切换到其他模式时，或者采取手动运行
`etype-restore-buffer' 命令的方式可以恢复缓冲内容。

获取五笔编码的函数 `etype-get-code' 依赖于 `pyim'，主要使用了
其生成的 `pyim-dhashcache-word2code' 哈希表。当然，这个输入法现在
做到了非常值得安装。

为了练习打字，模式中默认会禁用掉基本上所有的移动命令的。主要采取
了使用 `etype-mode-map' 和 `pre-command-hook' 相结合的方式。

输入检查默认只会响应 `self-insert-command',
 `delete-backward-char' 和 `etype-pass'这几个命令，可以修改
 `etype-work-commands' 进行定制。

`evil-mode' 模式和 `company-mode' 不适合于打字练习，所以在模式中
被关闭了。因为 `evil-mode' 模式太过于邪恶，所以为防止其打开，在
`pre-command-hook' 还会检查是否被某些命令打开，如果打开了的话，会
立即将其关闭。

`etype-mode' 的工作逻辑非常简单，主要是跟踪输入命令和光标位置，
提示输入和检查输入，并显示相关信息。

使用 `C-SPC' 可以切换输入法，模拟大多数的普通输入法按键。
"

  :abbrev-table nil :syntax-table nil
  (setq etype-original-text  (buffer-string))
  ;; 关闭自动补全
  (when (boundp company-mode)
    (company-mode -1))
  ;; 关闭自动文本样式锁定
  (font-lock-mode -1)
  ;; 关闭打字缓冲区中的 evil 模式
  (when evil-local-mode
    (evil-local-mode -1))
  ;; 关闭自动中英文切换，模拟通常的输入法
  (setq-local pyim-english-input-switch-functions nil)

  ;; 清除空白字符并使用 `fill-paragraph' 折行后，每行插入一个空行
  (goto-char (point-min))
  (replace-string "\n" "")
  (setq etype-total-words-number (- (point-max) (point-min)))
  (fill-region (point-min) (point-max) 'full)
  (goto-char (point-min))
  (while (not  (eobp))
    (forward-line)
    (insert "\n")
    )
  (goto-char (point-max))
  (insert "\n")

  ;; 设置参照文本样式为带阴影的按钮样式
  (add-text-properties
   (point-min)
   (point-max)
   `(face custom-button))
  (goto-char (point-min))
  (while (search-forward "\n" nil t)
    (remove-text-properties
     (match-beginning 0)
     (+ (match-beginning 0) 1)
     `(face company-preview))
    )

  ;; 位置变量初始化
  (goto-char (point-min))
  (forward-line 1)
  (setq etype-line-beg-point (point))
  (setq etype-last-point (point))
  (forward-line -1) ;退一行
  (setq etype-window-width (-  etype-line-beg-point (point) 1))
  (setq etype-completed-words-number 0)
  ;; 高亮将要输入的文字
  (etype-highlight-tip)
  (forward-line 1)

  (setq etype-start-time (current-time))
  (setq etype-start-point (point))
  ;; 在窗口上产生一个头行显示相关信息
  (setq header-line-format '((:eval (propertize "编码：" 'face 'info-index-match))
                             etype-word-code
                             (:eval (propertize "  用时：" 'face 'info-index-match))
                             (:eval (etype-elapsed-time-string))
                             (:eval (propertize "  总计：" 'face 'info-index-match))
                             (:eval
                              (format "%5d字" etype-total-words-number))
                             (:eval (propertize "  完成：" 'face 'info-index-match))
                             (:eval  (format "%.2f%%%%" (/ (float (*  etype-completed-words-number 100)) etype-total-words-number)))
                             (:eval (propertize "  平均速度：" 'face 'info-index-match))
                             (:eval  (format "%.2f字每分钟" (/ (* etype-completed-words-number 60) (float-time  (time-subtract nil etype-start-time)))))
                             (:eval (propertize "  正确率：" 'face 'info-index-match))
                             (:eval (etype-correct-percent))

                             ))
  (force-mode-line-update)
  ;; 添加钩子函数
  (add-hook 'post-command-hook #'etype-check-input-hook nil t) ;用于检查输入并更新相关信息
  (add-hook 'pre-command-hook #'etype-jump-hook nil t) ;用于禁用一些改变
                                                          ;point的命令，只允许输
                                                          ;入和回退，回退不能超
                                                          ;过一行
  (add-hook 'change-major-mode-hook #'(lambda () (erase-buffer) (insert etype-original-text)) nil t)
  )

(defun etype-highlight-tip (&optional pos )
  (let (( pos (or pos (-  etype-last-point etype-window-width 1))))
    (add-text-properties
     (-  etype-line-beg-point etype-window-width 1)
     (-  etype-line-beg-point 1)
     `(face custom-button))
    (add-text-properties
     pos
     (+ pos 1)
     `(face custom-button-mouse))
    ))

(defun etype-restore-buffer ()
  "使用 `etype-original-text' 刷新缓冲区。"
  (interactive)
  (when etype-original-text
    (erase-buffer)
    (insert etype-original-text))
  )

(defun etype-type-again ()
  "用户命令重打一次。刷新缓冲，再一次进入 `etype-mode'。"
  (interactive)
  (etype-restore-buffer)
  (etype-mode)
  )

(defun etype-pass(&optional args)
  "保持光标不动。要确保这是一个命令（即要有 `interactive'），否则不能添加到按键映射表中。"
  (interactive)
  t
  )

(defun etype-jump-hook (&optional arg)
  "针对 `etype-ignore-commands' 变量中的命令，保持光标不动。"
  (when (eq major-mode 'etype-mode)
    ;; 如果 evil 模式被某个命令打开了则将其关闭，清除其键盘映射
    (when (and  evil-local-mode (string= (car (split-string (symbol-name this-command) "-")) "evil"))
      (evil-local-mode -1)
      (setq this-command 'etype-pass)
    )

    (if  (or (and (member this-command etype-ignore-commands)
                  (not (eq this-command 'delete-backward-char)))
             (and  (eq this-command 'delete-backward-char)
                   (= (point) etype-line-beg-point)))
        (setq this-command 'etype-pass))
    ))

(defun etype-correct-percent ()
  (if (= etype-completed-words-number 0)
      "100%%"
    (format "%.2f%%%%" (* 100 (/ (- etype-completed-words-number (length etype-error-points)) (float  etype-completed-words-number))))
    ))

(defun etype-elapsed-time-string()
  (let* ((sec (round  (float-time (time-subtract (current-time) etype-start-time)))))
    (format "%2d小时%2d分%2d秒" (floor (/ sec 3600)) (floor (/ (% sec 3600) 60 )) (% sec 60))
    ))

(defun etype-get-code (chr)
  "从 `pyim-dhashcache-word2code' 哈希表中获取 CHR 的五笔编码。"
  (require 'pyim)
  (let ((codes ( cl-copy-list (gethash chr pyim-dhashcache-word2code))))
    (when codes
      (let ((code (car (sort codes #'(lambda (x y)
                                       (if (or (not ( string= (substring y 0 1) "."))
                                               (string= (substring y 0 2) ".z")
                                               (> (length x) (length y))) t))))))
        (substring code 1)
        )
      )))

(defun etype-check-highlight-error ()
  "逐字检查输入的字符，如果错误的话标识为红色"
  (while (< etype-last-point (point))
    (let* ((input-char (buffer-substring-no-properties etype-last-point (+ etype-last-point 1)))
           (comp-point-beg (- etype-last-point etype-window-width 1) )
           (comp-char(buffer-substring-no-properties  comp-point-beg (+  comp-point-beg 1)))
           )

      (if (not (string= input-char comp-char ))
          (progn
            (add-to-list 'etype-error-points etype-last-point )
            ;; 字符不等，标为红色
            (add-text-properties
             etype-last-point
             (+ etype-last-point 1)
             `(face avy-lead-face)))
        ;; 新输入默认会使用其前一个字符的样式，输入正确要移除其上可能的红色标识
        (remove-text-properties
         etype-last-point
         (+ etype-last-point 1)
         `(face avy-lead-face))
        )
      )
    (setq etype-last-point (+ etype-last-point 1))
    )
  )

(defun etype-check-input-hook ()
  "检查输入正确与否的 `post-command-hook' 常规钩子函数。
`this-command' 是 `etype-work-commands' 的元素时，检查输入；否
则将光标设置到上次输入结束的位置。 "

  ;; 只有处于打字模式时才起作用
  (when (equal major-mode 'etype-mode)
    (cond
     ((member this-command etype-work-commands)
      (etype-set-completed-number)
      (if (<  (point) etype-last-point) ;delete-backward-char
          (setq etype-last-point (point))
        )
      (let (error-pos)
        ;; 将大于光标位置的错误点删除
        (while (and (length etype-error-points)
                    (setq  error-pos (pop  etype-error-points))
                    (>= error-pos etype-last-point)
                    )
          )
        (when error-pos (setq etype-error-points (cons error-pos etype-error-points)))
        )

      ;; 如果超过了行尾，则处理折行
      (if (>= (point) (+ etype-line-beg-point etype-window-width ))
          (let* ((line-end (+ etype-line-beg-point etype-window-width))
                 (s (buffer-substring-no-properties line-end (point))))
            (delete-region line-end (point))
                                        ;(etype-set-completed-number)
            (etype-check-highlight-error)
            ;; 将行尾提示样式清除
            (add-text-properties
             (-  etype-line-beg-point etype-window-width 1)
             (-  etype-line-beg-point 1)
             `(face custom-button))

            (goto-char etype-line-beg-point)
            (if (= (forward-line 2) 0)
                (progn
                  (setq etype-line-beg-point (point))
                  (setq etype-last-point (point))
                  (forward-line -1)
                  (setq etype-window-width (-  etype-line-beg-point (point) 1))
                  (forward-line 1)
                  (etype-highlight-tip)
                  (insert s)
                  (etype-check-input-hook))
              (when  (y-or-n-p  "本次练习完成，再来一次")
                (etype-type-again)
                )
              )
            )
        )
      ;; 如果光标处于第二个字则开始计时
      (if (= etype-start-point etype-last-point)
          (setq etype-start-time (current-time)))
      ;; etype-check-highlight-error 会移动 etype-last-point
      (etype-check-highlight-error)

      ;; 修改输入参照字符的显示样式
      (etype-highlight-tip)
      ;; 获取将要输入字符的五笔编码
      (let (( next-char (buffer-substring-no-properties
                         (-  etype-last-point etype-window-width 1)
                         (-  etype-last-point etype-window-width) )))
        (setq etype-word-code (format "%2s %5s" next-char (etype-get-code next-char))))

      (force-mode-line-update)
      )
     (t
      ;; 将被其他命令改过的值改回来，禁止中英文自动切换
      (if  (eq this-command 'toggle-input-method)
          (setq-local pyim-english-input-switch-functions nil))
      (goto-char etype-last-point)   ;将光标放到上次输入结束的位置
      )
     )
    ))

(defun etype-set-completed-number()
  (setq etype-completed-words-number (+ etype-completed-words-number (- (point) etype-last-point)))
  )

(provide 'etype-mode)

;;; etype-mode.el ends here
