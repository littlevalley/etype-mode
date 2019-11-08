# etype-mode

这是一个中文五笔打字练习模式，类似于金山打字通。

## 依赖

pyim

获取五笔编码的函数 'etype-get-code' 依赖于 'pyim'，主要使用了
其生成的 'pyim-dhashcache-word2code' 哈希表。当然，这个输入法现在
做到了非常值得安装。

## 安装

在 emacs 的配置文件中加入：
```
(require 'etype-mode)
```

## 使用

在 Emacs 中 "M-x etype-mode" 切换当前缓冲区到此主模式。而后可以像金山打字通一
  样练习五笔输入。

如果使用 Emacs 内部输入法，可以使用 "Ctrl + Space " 和 "Ctrl + \" 切换输入法。
  
可以使用"M-x etype-type-again" 刷新缓冲区，重置变量。

## 说明

### 按键绑定

为了练习打字，模式中采取了使用 'etype-mode-map' 和 'pre-command-hook' 相结合的方
式，模式中默认会禁用掉基本上所有的移动命令。除了 'self-insert-command' 和
'delete-backward-char' 。 

### 工作方式

'etype-mode' 的工作逻辑非常简单，主要是跟踪输入命令和光标位置，提示输入和检查输
入，并显示相关信息。模式首先会保存缓冲中的文本，而后修改缓冲内容，设置成逐行对照
的样式，设置相关变量和钩子，做到可以显示下一个字的编码、使用的时间、打字的速度等。
在切换到其他模式时，或者采取手动运行'etype-restore-buffer' 命令的方式可以恢复缓
冲内容。

### 变量

输入检查默认只会响应 'self-insert-command',
 'delete-backward-char' 和 'etype-pass'这几个命令，可以修改
 'etype-work-commands' 进行定制。
 
 另一个变量 'etype-ignore-commands' 中设置要忽略的命令，即这些命令在运行时都将重
 定向到 'etype-pass' 命令，啥也不做。

'evil-mode' 模式和 'company-mode' 不适合于打字练习，所以在模式中
被关闭了。因为 'evil-mode' 模式太过于邪恶，所以为防止其打开，在
'pre-command-hook' 还会检查是否被某些命令打开，如果打开了的话，会
立即将其关闭。
