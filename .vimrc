" ==============================================================================
" 1. 兼容性初始化与全局引导 (最低兼容 Vim 8.0，即 Rocky/RHEL 8 自带的 8.0.1763；新特性均按版本探测)
" ==============================================================================
if &compatible
  set nocompatible
endif

let mapleader = ','
let g:netrw_home = expand('~/.cache/vim')
" 全大写的全局变量会随 viminfo ('!' 标志) 持久化，重启后 <Space>q 仍能看到上次关闭的文件
let g:RECENT_CLOSED = get(g:, 'RECENT_CLOSED', {})

" 自动初始化缓存与持久化 Undo 目录
let s:cache_dir = expand('~/.cache/vim')
for s:sub in ['undo', 'backup', 'swap']
  if !isdirectory(s:cache_dir . '/' . s:sub)
    silent! call mkdir(s:cache_dir . '/' . s:sub, 'p', 0700)
  endif
endfor

" ==============================================================================
" 2. 核心基础设置 (全版本向下兼容)
" ==============================================================================
filetype plugin indent on
syntax enable

set encoding=utf-8
" gb18030 几乎能解码任意字节序列，放在它之后的 GBK 系编码永远不会被尝试
set fileencodings=ucs-bom,utf-8,gb18030,latin1
silent! set helplang=cn

" 仅在确认终端支持 24 位色时开启 TrueColor (tmux 内总是安全的：外层不支持时 tmux 会自动降级到 256 色)
let s:truecolor = has('gui_running') || $COLORTERM =~# 'truecolor\|24bit' || exists('$TMUX')
      \ || $TERM_PROGRAM =~# 'iTerm\|WezTerm\|vscode\|ghostty\|WarpTerminal\|Hyper'
      \ || exists('$WT_SESSION') || exists('$KITTY_WINDOW_ID')
      \ || &term =~# 'kitty\|alacritty\|wezterm\|ghostty\|foot'
if exists('+termguicolors') && s:truecolor
  " 修复 Tmux / Screen 下的 TrueColor 序列识别
  if &term =~# '^screen\|^tmux\|^xterm'
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  endif
  set termguicolors
endif
if !has('gui_running') && (s:truecolor || &term =~# '256col\|^xterm\|^tmux\|^screen')
  set t_Co=256
endif
" macOS 自带 ncurses 缺少 tmux-256color，回退到 screen-256color 时没有斜体序列
if exists('$TMUX') && &t_ZH ==# ''
  let &t_ZH = "\<Esc>[3m"
  let &t_ZR = "\<Esc>[23m"
endif

set hidden autoread autowrite confirm
" swap 集中放在缓存目录 (// 表示用完整路径命名，避免同名文件冲突)，崩溃或 SSH 断线后可 :recover
let &directory = s:cache_dir . '/swap//'
let &backupdir = s:cache_dir . '/backup'
set swapfile nobackup writebackup updatetime=1000
if has('viminfo')
  set viminfo^=!
  " Vim 8.0.1716+：viminfo 挪进缓存目录 (首次自动迁移旧文件)；-i 指定过时不覆盖
  if exists('+viminfofile') && &viminfofile ==# ''
    let s:viminfo = s:cache_dir . '/viminfo'
    if !filereadable(s:viminfo) && filereadable(expand('~/.viminfo'))
      silent! call writefile(readfile(expand('~/.viminfo'), 'b'), s:viminfo, 'b')
    endif
    let &viminfofile = s:viminfo
  endif
endif
if has('persistent_undo')
  let &undodir = s:cache_dir . '/undo'
  set undofile
endif

set number cursorline laststatus=2 showtabline=2 ruler showcmd noshowmode
if exists('+signcolumn')
  set signcolumn=yes
endif

set cmdheight=1 textwidth=0 nowrap virtualedit=block,onemore synmaxcol=500
set whichwrap+=<,>,h,l ttimeout ttimeoutlen=10 timeoutlen=500 matchpairs+=<:>
" 只全局开 autoindent；C/C++/CUDA 由 indent 脚本自行启用 cindent (并沿用这里的 cinoptions)，
" 避免 markdown / conf 等无缩进脚本的文件被套用 C 缩进规则
set autoindent cinoptions=g0,:0,N-s,(0
set tabstop=4 shiftwidth=4 softtabstop=4 smarttab expandtab
set backspace=indent,eol,start sidescroll=1 sidescrolloff=4 scrolloff=4 nofoldenable
set splitbelow splitright
set list lcs=tab:¦\ ,trail:·,extends:»,precedes:«,nbsp:␣
set formatoptions+=j nrformats-=octal
silent! set breakindent
silent! set smoothscroll
silent! set diffopt+=algorithm:histogram,indent-heuristic

" 鼠标与剪贴板安全降级 (支持系统剪贴板时自动联通)
if has('unnamedplus')
  set clipboard^=unnamed,unnamedplus
else
  set clipboard^=unnamed
endif

" ==============================================================================
" 3. 搜索、跳转与补全增强 (原生 SuperTab & Ripgrep 集成)
" ==============================================================================
set wildmenu
silent! set wildmode=longest:full,full
silent! set wildoptions=pum
silent! set wildoptions+=fuzzy
set wildignore+=*.o,*.obj,*.so,*.a,*.pyc,__pycache__/*,.git/*,build/*,dist/*
" 不使用 path+=**：大仓库里 gf / :find 递归遍历会很慢，文件查找交给下方的 :F

set completeopt=menuone,preview
if v:version >= 704
  silent! set completeopt+=noselect
  silent! set shortmess+=c
endif
set omnifunc=syntaxcomplete#Complete cpt+=kspell
set hlsearch incsearch ignorecase smartcase

" 优先使用 ripgrep (rg) 作为内置 :grep 引擎 (glob 不加引号，兼容 Windows cmd.exe)
if executable('rg')
  set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ --glob=!.git
  set grepformat=%f:%l:%c:%m
endif

" {{{ 原生模糊文件查找 :F (替代 fzf / ctrlp)：文件列表来自 rg > git ls-files > find，同一条命令行内缓存
let s:files_cache = []
function! s:ListFiles() abort
  if !empty(s:files_cache)
    return s:files_cache
  endif
  if executable('rg')
    let s:files_cache = systemlist('rg --files --hidden --color=never --glob=!.git')
  endif
  if empty(s:files_cache) && executable('git')
    let l:out = systemlist('git ls-files -co --exclude-standard')
    let s:files_cache = v:shell_error ? [] : l:out
  endif
  if empty(s:files_cache) && executable('find')
    let s:files_cache = map(systemlist('find . -path ./.git -prune -o -type f -print'), 'v:val[2:]')
  endif
  return s:files_cache
endfunction

function! s:ByLen(a, b) abort
  return len(a:a) - len(a:b)
endfunction

" Vim 8.2.1665+ 用内置 matchfuzzy (按匹配质量排序)，旧版本退化为 "字符按序出现" 的正则匹配并按长度排序
function! s:FuzzyFilter(list, pat) abort
  if a:pat ==# ''
    return copy(a:list)
  endif
  if exists('*matchfuzzy')
    return matchfuzzy(a:list, a:pat)
  endif
  let l:re = '\V' . join(map(split(a:pat, '\zs'), 'escape(v:val, "\\")'), '\.\{-}')
  return sort(filter(copy(a:list), 'v:val =~? l:re'), 's:ByLen')
endfunction

function! s:FilesComplete(lead, ...) abort
  return s:FuzzyFilter(s:ListFiles(), a:lead)[:299]
endfunction

function! s:FilesEdit(arg) abort
  if filereadable(expand(a:arg))
    execute 'edit ' . fnameescape(expand(a:arg))
    return
  endif
  let l:hits = s:FuzzyFilter(s:ListFiles(), a:arg)
  if empty(l:hits)
    echohl ErrorMsg | echo 'No file matches: ' . a:arg | echohl None
  else
    execute 'edit ' . fnameescape(l:hits[0])
  endif
endfunction
command! -nargs=1 -complete=customlist,<SID>FilesComplete F call <SID>FilesEdit(<q-args>)

" Vim 9.1.0831+：:find 也复用同一套文件列表与模糊匹配
if exists('+findfunc')
  function! s:FindFunc(arg, cmdcomplete) abort
    if !a:cmdcomplete && filereadable(a:arg)
      return [a:arg]
    endif
    return s:FuzzyFilter(s:ListFiles(), a:arg)
  endfunction
  let &findfunc = expand('<SID>') . 'FindFunc'
endif
" }}}

" {{{ 插入模式与原生 Auto-Pairs / SuperTab
" 插入模式内统一使用 <C-G>U<Left>/<Right>，不打断撤销序列与 . 重复
function! s:Enter() abort
  if pumvisible()
    if exists('*complete_info') && complete_info(['selected']).selected == -1
      return "\<C-Y>\<CR>"
    endif
    return "\<C-Y>"
  endif
  let l:line = getline('.')
  let l:col = col('.') - 1
  let l:prev = strpart(l:line, l:col - 1, 1)
  let l:next = strpart(l:line, l:col, 1)
  if (l:prev ==# '{' && l:next ==# '}') || (l:prev ==# '[' && l:next ==# ']') || (l:prev ==# '(' && l:next ==# ')')
    return "\<CR>\<C-O>O"
  endif
  return "\<CR>"
endfunction

function! s:Backspace() abort
  let l:line = getline('.')
  let l:col = col('.') - 1
  let l:pair = strpart(l:line, l:col - 1, 2)
  if index(['()', '[]', '{}', '""', "''", '``'], l:pair) >= 0
    return "\<Del>\<BS>"
  endif
  return "\<BS>"
endfunction

function! s:SuperTab(dir) abort
  if pumvisible()
    return a:dir > 0 ? "\<C-N>" : "\<C-P>"
  endif
  let l:col = col('.') - 1
  if !l:col || getline('.')[l:col - 1] =~# '\s'
    return "\<Tab>"
  endif
  return a:dir > 0 ? "\<C-N>" : "\<C-P>"
endfunction

inoremap <silent> <expr> <CR> <SID>Enter()
inoremap <silent> <expr> <BS> <SID>Backspace()
inoremap <silent> <expr> <Tab> <SID>SuperTab(1)
inoremap <silent> <expr> <S-Tab> <SID>SuperTab(-1)

inoremap <C-E> <End>
inoremap <C-A> <C-O>^
inoremap <C-D> <Del>
vnoremap <C-D> <Del>
inoremap <C-F> <C-O>w

function! s:CtrlB() abort
  return pumvisible() ? "\<C-N>" : "\<C-O>b"
endfunction
inoremap <expr> <C-B> <SID>CtrlB()
snoremap <C-V> <Space><BS><C-O>"0P

" 命令行只在 : 命令中自动成对，/ ? 搜索里输入 \( 等正则时不干扰
function! s:CmdOpen(open, close) abort
  return getcmdtype() ==# ':' ? a:open . a:close . "\<Left>" : a:open
endfunction

inoremap ( ()<C-G>U<Left>
inoremap [ []<C-G>U<Left>
inoremap { {}<C-G>U<Left>
cnoremap <expr> ( <SID>CmdOpen('(', ')')
cnoremap <expr> [ <SID>CmdOpen('[', ']')
cnoremap <expr> { <SID>CmdOpen('{', '}')

function! s:Judge(ch, mode) abort
  if a:mode ==# 'c' && getcmdtype() !=# ':'
    return a:ch
  endif
  let l:line = a:mode ==# 'c' ? getcmdline() : getline('.')
  let l:pos  = a:mode ==# 'c' ? getcmdpos() - 1 : col('.') - 1
  let l:cur  = strpart(l:line, l:pos, 1)
  let l:prev = l:pos > 0 ? strpart(l:line, l:pos - 1, 1) : ''
  let l:left = a:mode ==# 'c' ? "\<Left>" : "\<C-G>U\<Left>"
  let l:right = a:mode ==# 'c' ? "\<Right>" : "\<C-G>U\<Right>"

  " 跳过已存在的闭合符号
  if l:cur ==# a:ch
    return l:right
  endif

  if index(['"', "'", '`'], a:ch) >= 0
    " 在 vim 配置文件中行首输入 " 视为注释，不自动成对
    if a:mode ==# 'i' && &filetype ==# 'vim' && a:ch ==# '"' && strpart(l:line, 0, l:pos) =~# '^\s*$'
      return a:ch
    endif
    " 紧跟在字母数字后的单引号(如 don't)或转义符后不自动成对
    if l:prev ==# '\' || (a:ch ==# "'" && l:prev =~# '\w')
      return a:ch
    endif
    return a:ch . a:ch . l:left
  endif
  return a:ch
endfunction

for s:pair in ['"', "'", '`', '>', ')', '}', ']']
  execute 'inoremap <expr> <silent> ' . s:pair . ' <SID>Judge(' . string(s:pair) . ', "i")'
  execute 'cnoremap <expr> ' . s:pair . ' <SID>Judge(' . string(s:pair) . ', "c")'
endfor
" }}}

" ==============================================================================
" 4. 原生插件级功能实现 (Commentary / Surround / OSC52 / MRU / Grep)
" ==============================================================================
" {{{ [原生插件 1] 代码注释切换 (gcc / gc{motion} / 可视 gc，支持计数与 . 重复，替代 vim-commentary)
function! s:ToggleComment(l1, l2) abort
  let l:cms = &commentstring
  if l:cms ==# '' || stridx(l:cms, '%s') < 0
    let l:cms = '# %s'
  endif
  let l:parts = split(l:cms, '%s', 1)
  let l:pre = substitute(l:parts[0], '\s\+$', '', '')
  let l:post = len(l:parts) > 1 ? substitute(l:parts[1], '^\s\+', '', '') : ''
  " \V 字面匹配，注释符后的空格可有可无 (兼容 //foo 这类写法)
  let l:pre_pat = '\V' . escape(l:pre, '\') . '\m'
  let l:post_pat = '\V' . escape(l:post, '\') . '\m'

  let l:uncomment = 1
  let l:min_indent = -1
  for l:lnum in range(a:l1, a:l2)
    let l:str = getline(l:lnum)
    if l:str =~# '\S'
      let l:ind = len(matchstr(l:str, '^\s*'))
      if l:min_indent < 0 || l:ind < l:min_indent | let l:min_indent = l:ind | endif
      if l:str !~# '^\s*' . l:pre_pat
        let l:uncomment = 0
      endif
    endif
  endfor
  if l:min_indent < 0 | return | endif

  for l:lnum in range(a:l1, a:l2)
    let l:str = getline(l:lnum)
    if l:str !~# '\S' | continue | endif
    if l:uncomment
      let l:str = substitute(l:str, '^\(\s*\)' . l:pre_pat . ' \?', '\1', '')
      if l:post !=# ''
        let l:str = substitute(l:str, ' \?' . l:post_pat . '\s*$', '', '')
      endif
    else
      let l:pad = strpart(l:str, 0, l:min_indent)
      let l:rest = strpart(l:str, l:min_indent)
      let l:str = l:pad . l:pre . ' ' . l:rest . (l:post !=# '' ? ' ' . l:post : '')
    endif
    call setline(l:lnum, l:str)
  endfor
endfunction

" operatorfunc 入口：无参数时设置 opfunc 并返回 g@，被 g@ 回调时执行注释切换
function! VimrcCommentOp(...) abort
  if !a:0
    set operatorfunc=VimrcCommentOp
    return 'g@'
  endif
  call s:ToggleComment(line("'["), line("']"))
  return ''
endfunction

nnoremap <silent> <expr> gc  VimrcCommentOp()
nnoremap <silent> <expr> gcc VimrcCommentOp() . '_'
xnoremap <silent> <expr> gc  VimrcCommentOp()
" }}}

" {{{ [原生插件 2] 轻量 Surround 操作 (ds / cs / 可视 S，替代 vim-surround)
" 全程关闭 clipboard 并恢复 "z / 无名寄存器，不污染系统剪贴板，也不触发 TextYankPost
let s:surround_alias = {'b': '(', ')': '(', 'r': '[', ']': '[', 'B': '{', '}': '{', 'a': '<', '>': '<'}
let s:surround_pairs = {'(': ['(', ')'], '[': ['[', ']'], '{': ['{', '}'], '<': ['<', '>']}
let s:surround_put = has('patch-8.2.4242') ? 'P' : 'p'

function! s:GetPair(ch) abort
  let l:key = get(s:surround_alias, a:ch, a:ch)
  return get(s:surround_pairs, l:key, [a:ch, a:ch])
endfunction

" 读取一个可打印字符，<Esc> 等特殊键返回空串
function! s:GetChar() abort
  let l:c = getchar()
  let l:c = type(l:c) == type(0) ? nr2char(l:c) : l:c
  return (l:c =~# '^\p$' && l:c !=# ' ') ? l:c : ''
endfunction

function! s:SaveRegs() abort
  let l:save = [getreg('z', 1), getregtype('z'), getreg('"', 1), getregtype('"'), &clipboard]
  set clipboard=
  return l:save
endfunction

function! s:RestoreRegs(save) abort
  call setreg('z', a:save[0], a:save[1])
  call setreg('"', a:save[2], a:save[3])
  let &clipboard = a:save[4]
endfunction

" 选中文本对象并返回其内容，未选中 (不在包围符内) 返回空串
function! s:SelectObj(obj) abort
  silent! execute "noautocmd normal! \<Esc>v" . a:obj . "\<Esc>"
  if getpos("'<") == getpos("'>")
    return ''
  endif
  noautocmd normal! gv"zy
  return getreg('z')
endfunction

" 将 old 包围符替换为 new 对应的符号 (new 为空串即删除)
function! s:ReplaceSurround(old, new) abort
  let l:save = s:SaveRegs()
  try
    let l:key = get(s:surround_alias, a:old, a:old)
    if l:key ==# 't'
      let l:inner = s:SelectObj('it')
      let l:outer = s:SelectObj('at')
      if l:outer ==# '' | return | endif
    else
      " 引号用 2i" 而不是 a"，避免把尾随空白一起删掉
      let l:outer = s:SelectObj((l:key =~# '^[''"`]$' ? '2i' : 'a') . l:key)
      let [l:open, l:close] = s:GetPair(l:key)
      if strchars(l:outer) < 2 || strcharpart(l:outer, 0, 1) !=# l:open
        return
      endif
      let l:inner = strcharpart(l:outer, 1, strchars(l:outer) - 2)
    endif
    let [l:open, l:close] = a:new ==# '' ? ['', ''] : s:GetPair(a:new)
    call setreg('z', l:open . l:inner . l:close, 'v')
    execute 'noautocmd normal! gv"z' . s:surround_put
  finally
    call s:RestoreRegs(l:save)
  endtry
endfunction

function! s:DeleteSurround() abort
  let l:ch = s:GetChar()
  if l:ch !=# ''
    call s:ReplaceSurround(l:ch, '')
  endif
endfunction

function! s:ChangeSurround() abort
  let l:old = s:GetChar()
  let l:new = l:old ==# '' ? '' : s:GetChar()
  if l:new !=# ''
    call s:ReplaceSurround(l:old, l:new)
  endif
endfunction

function! s:VisualSurround() abort
  let l:ch = s:GetChar()
  if l:ch ==# '' | return | endif
  let [l:open, l:close] = s:GetPair(l:ch)
  let l:mode = visualmode()
  let l:save = s:SaveRegs()
  try
    noautocmd normal! gv"zy
    if l:mode ==# 'V'
      call setreg('z', [l:open] + getreg('z', 1, 1) + [l:close], 'V')
    elseif l:mode ==# "\<C-V>"
      call setreg('z', map(getreg('z', 1, 1), 'l:open . v:val . l:close'), "\<C-V>")
    else
      call setreg('z', l:open . getreg('z') . l:close, 'v')
    endif
    execute 'noautocmd normal! gv"z' . s:surround_put
  finally
    call s:RestoreRegs(l:save)
  endtry
endfunction

nnoremap <silent> ds :<C-U>call <SID>DeleteSurround()<CR>
nnoremap <silent> cs :<C-U>call <SID>ChangeSurround()<CR>
xnoremap <silent> S  :<C-U>call <SID>VisualSurround()<CR>
" }}}

" {{{ [原生插件 3] OSC 52 远程剪贴板透传与复制高亮 (替代 vim-oscyank & highlightedyank)
" 在 tmux 内直接发送普通 OSC 52，由 tmux 的 set-clipboard on 接管并转发给外层终端
function! s:Osc52Yank(text) abort
  if exists('*base64_encode') && exists('*str2blob')
    let l:b64 = base64_encode(str2blob(split(a:text, "\n", 1)))
  elseif executable('base64')
    let l:b64 = substitute(system('base64', a:text), '[\r\n]', '', 'g')
  else
    return
  endif
  let l:seq = "\<Esc>]52;c;" . l:b64 . "\x07"
  if exists('*echoraw')
    call echoraw(l:seq)
  elseif filewritable('/dev/tty')
    silent! call writefile([l:seq], '/dev/tty', 'b')
  endif
endfunction

nnoremap <silent> <Leader>y :call <SID>Osc52Yank(@")<CR>:echohl ModeMsg \| echo "Yanked to system clipboard (OSC 52)" \| echohl None<CR>
xnoremap <silent> <Leader>y y:call <SID>Osc52Yank(@")<CR>:echohl ModeMsg \| echo "Yanked to system clipboard (OSC 52)" \| echohl None<CR>

" 仅在真正的 y 复制时触发 (x / dd / ciw 等删除不会覆盖系统剪贴板)
function! s:AutoOsc52() abort
  if v:event.operator !=# 'y' || index(['', '*', '+'], v:event.regname) < 0
    return
  endif
  call s:Osc52Yank(join(v:event.regcontents, "\n") . (v:event.regtype ==# 'V' ? "\n" : ''))
endfunction

function! s:FlashClear(ids, win, ...) abort
  for l:id in a:ids
    try
      call matchdelete(l:id, a:win)
    catch
      if win_getid() == a:win | silent! call matchdelete(l:id) | endif
    endtry
  endfor
endfunction

function! s:FlashYank() abort
  if !exists('*matchaddpos') || !exists('*timer_start') || get(v:event, 'operator', '') !=# 'y'
    return
  endif
  let [l:l1, l:c1] = [line("'["), col("'[")]
  let [l:l2, l:c2] = [line("']"), col("']")]
  " 包含末尾多字节字符的全部字节
  let l:c2 += max([len(matchstr(getline(l:l2), '\%' . l:c2 . 'c.')) - 1, 0])
  let l:type = v:event.regtype[0]
  let l:pos = []
  " 只高亮可见区域，避免大段复制时生成海量匹配
  for l:l in range(max([l:l1, line('w0')]), min([l:l2, line('w$')]))
    if l:type ==# 'V'
      call add(l:pos, l:l)
    elseif l:type ==# "\<C-V>"
      call add(l:pos, [l:l, min([l:c1, l:c2]), abs(l:c2 - l:c1) + 1])
    elseif l:l == l:l1 && l:l == l:l2
      call add(l:pos, [l:l, l:c1, l:c2 - l:c1 + 1])
    elseif l:l == l:l1
      call add(l:pos, [l:l, l:c1, col([l:l, '$']) - l:c1 + 1])
    elseif l:l == l:l2
      call add(l:pos, [l:l, 1, l:c2])
    else
      call add(l:pos, l:l)
    endif
  endfor
  " 旧版 matchaddpos 单次最多 8 个位置，分批添加
  let l:ids = []
  for l:i in range(0, len(l:pos) - 1, 8)
    call add(l:ids, matchaddpos('IncSearch', l:pos[l:i : l:i + 7]))
  endfor
  call timer_start(180, function('s:FlashClear', [l:ids, win_getid()]))
endfunction
" }}}

" {{{ [原生插件 4] 自动命令、CUDA/AscendC 支持与最近关闭/MRU 文件
function! s:CompareRecent(a, b) abort
  return a:a.time == a:b.time ? 0 : (a:a.time > a:b.time ? -1 : 1)
endfunction

function! s:GetRecentClose() abort
  let l:items = []
  for [l:file, l:value] in items(g:RECENT_CLOSED)
    if filereadable(l:file)
      let l:item = copy(l:value)
      let l:item.filename = l:file
      let l:item.text = 'Recent closed'
      call add(l:items, l:item)
    endif
  endfor
  call sort(l:items, 's:CompareRecent')
  " 补充 v:oldfiles 历史文件 (去重)
  if exists('v:oldfiles')
    let l:seen = copy(g:RECENT_CLOSED)
    for l:old in v:oldfiles[:30]
      let l:p = fnamemodify(expand(l:old), ':p')
      if !has_key(l:seen, l:p) && filereadable(l:p)
        let l:seen[l:p] = 1
        call add(l:items, {'filename': l:p, 'lnum': 1, 'col': 1, 'text': 'History MRU'})
      endif
    endfor
  endif
  call setqflist(l:items, 'r')
  copen
endfunction
nnoremap <silent> <nowait> <Space>q :call <SID>GetRecentClose()<CR>

" BufDelete 时当前 buffer 不一定是被删除的那个，必须通过 <abuf> 取信息
function! s:RememberClosed(buf) abort
  let l:name = bufname(a:buf)
  if l:name ==# '' || getbufvar(a:buf, '&buftype') !=# ''
    return
  endif
  if a:buf == bufnr('%')
    let [l:lnum, l:col] = [line('.'), col('.')]
  else
    let l:info = exists('*getbufinfo') ? get(getbufinfo(a:buf), 0, {}) : {}
    let [l:lnum, l:col] = [get(l:info, 'lnum', 1), 1]
  endif
  let g:RECENT_CLOSED[fnamemodify(l:name, ':p')] = {'lnum': l:lnum, 'col': l:col, 'time': localtime()}
endfunction

" 退出前只保留最近 100 条，避免 viminfo 无限膨胀
function! s:CompareItemTime(a, b) abort
  return s:CompareRecent(a:a[1], a:b[1])
endfunction

function! s:TrimRecent() abort
  if len(g:RECENT_CLOSED) <= 100
    return
  endif
  let l:keep = {}
  for [l:file, l:value] in sort(items(g:RECENT_CLOSED), 's:CompareItemTime')[:99]
    let l:keep[l:file] = l:value
  endfor
  let g:RECENT_CLOSED = l:keep
endfunction

" 带 shebang 的脚本保存后按 umask 风格补充可执行位 (有 r 的位置才加 x)
function! s:MakeExecutable(file) abort
  if !exists('*setfperm') || getline(1) !~# '^#!'
    return
  endif
  let l:perm = getfperm(a:file)
  if len(l:perm) != 9 || l:perm[2] ==# 'x'
    return
  endif
  let l:new = ''
  for l:i in range(9)
    let l:new .= (l:i % 3 == 2 && l:perm[l:i - 2] ==# 'r') ? 'x' : l:perm[l:i]
  endfor
  call setfperm(a:file, l:new)
endfunction

function! s:StripTrailing() abort
  let l:view = winsaveview()
  keeppatterns silent! %s/\s\+$//e
  call winrestview(l:view)
endfunction

function! s:GrepWord() abort
  let l:word = shellescape(expand('<cword>'), 1)
  " 整词 + 纯文本匹配；系统 grep 需要显式递归当前目录
  execute 'silent grep! ' . (executable('rg') ? '-w -F -- ' . l:word : '-rwF -- ' . l:word . ' .')
  redraw!
endfunction

" 可视模式 * / # 以字面方式搜索选中文本
function! s:VisualSearch(cmd) abort
  let l:save = s:SaveRegs()
  try
    noautocmd normal! gv"zy
    let @/ = '\V' . substitute(escape(getreg('z'), a:cmd . '\'), '\n', '\\n', 'g')
  finally
    call s:RestoreRegs(l:save)
  endtry
endfunction

function! s:ToggleQuickfix() abort
  for l:info in getwininfo()
    if l:info.quickfix && !get(l:info, 'loclist', 0)
      cclose
      return
    endif
  endfor
  copen
endfunction

" 关闭 buffer 但保留窗口布局：所有显示它的窗口先切到备用/上一个 buffer
function! s:BufClose() abort
  let l:cur = bufnr('%')
  if &modified
    let l:c = confirm('Save changes to "' . bufname(l:cur) . '"?', "&Yes\n&No\n&Cancel", 3)
    if l:c == 1
      write
    elseif l:c != 2
      return
    endif
  endif
  if &buftype !=# ''
    execute 'bdelete! ' . l:cur
    return
  endif
  let l:origin = win_getid()
  for l:win in win_findbuf(l:cur)
    call win_gotoid(l:win)
    let l:alt = bufnr('#')
    if l:alt > 0 && l:alt != l:cur && buflisted(l:alt)
      execute 'buffer ' . l:alt
    else
      bprevious
      if bufnr('%') == l:cur | enew | endif
    endif
  endfor
  call win_gotoid(l:origin)
  if bufexists(l:cur)
    execute 'bdelete! ' . l:cur
  endif
endfunction

" 以 sudo 写入当前文件 (忘记 sudo 打开时使用，也可在命令行输入 :w!! 触发)
function! s:SudoWrite() abort
  execute 'write !sudo tee ' . shellescape(expand('%:p'), 1) . ' >/dev/null'
  if !v:shell_error
    setlocal nomodified
  endif
endfunction
command! SudoWrite call <SID>SudoWrite()

" 与 tmux 共用 <C-h/j/k/l> 切换窗口：Vim 内已到边缘时交给 tmux 切换 pane (替代 vim-tmux-navigator)
function! s:Navigate(dir) abort
  let l:nr = winnr()
  execute 'wincmd ' . a:dir
  if winnr() == l:nr && exists('$TMUX')
    call system('tmux select-pane' . (exists('$TMUX_PANE') ? ' -t ' . shellescape($TMUX_PANE) : '')
          \ . ' -' . tr(a:dir, 'hjkl', 'LDUR'))
  endif
endfunction

" 快速文件查找、全局搜索与常用效率快捷键
nnoremap <Leader>f :F<Space>
nnoremap <Leader>b :ls<CR>:b<Space>
nnoremap <silent> <Leader>g :call <SID>GrepWord()<CR>
nnoremap <silent> <Leader><Space> :call <SID>StripTrailing()<CR>
nnoremap <silent> <Leader>q :call <SID>ToggleQuickfix()<CR>
nnoremap <silent> <Leader>x :call <SID>BufClose()<CR>
" <C-L> 已用于窗口切换，清除搜索高亮并重绘改为 <Leader>/
nnoremap <silent> <Leader>/ :nohlsearch<C-R>=has('diff') ? '<Bar>diffupdate' : ''<CR><CR><C-L>
for s:d in ['h', 'j', 'k', 'l']
  execute 'nnoremap <silent> <C-' . s:d . '> :<C-U>call <SID>Navigate(''' . s:d . ''')<CR>'
endfor
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [q :cprevious<CR>
nnoremap <silent> ]q :cnext<CR>

nnoremap Y y$
nnoremap n nzzzv
nnoremap N Nzzzv
xnoremap < <gv
xnoremap > >gv
xnoremap <silent> J :move '>+1<CR>gv=gv
xnoremap <silent> K :move '<-2<CR>gv=gv
xnoremap <silent> * :<C-U>call <SID>VisualSearch('/')<CR>/<C-R>=@/<CR><CR>
xnoremap <silent> # :<C-U>call <SID>VisualSearch('?')<CR>?<C-R>=@/<CR><CR>
if executable('sudo')
  cnoremap <expr> ! getcmdtype() ==# ':' && getcmdline() ==# 'w!' ? "\<C-U>SudoWrite" : '!'
endif
if exists(':tnoremap') == 2
  tnoremap <Esc><Esc> <C-\><C-N>
endif

" Vim 自带插件：% 支持 if/endif、HTML 标签等配对跳转；netrw 去掉横幅并使用树形视图
if has('packages')
  silent! packadd! matchit
endif
let g:netrw_banner = 0
let g:netrw_liststyle = 3

function! Time() abort
  return 'update by chenxuan ' . strftime('%Y-%m-%d %H:%M:%S')
endfunction

augroup VimrcCore
  autocmd!
  " 分支每个 buffer 只解析一次；改名后重新解析，切回 Vim / 执行外部命令 / 切换目录时强制刷新
  autocmd BufEnter * if !exists('b:status_git_branch') | call s:GitBranchUpdate(bufnr('%')) | endif
  autocmd BufFilePost * unlet! b:status_git_branch
  " 其他 pane/终端里 git checkout 后切回 Vim 时刷新所有可见窗口的分支
  autocmd FocusGained,ShellCmdPost * call s:GitBranchUpdateVisible()
  if exists('##DirChanged')
    autocmd DirChanged * call s:GitBranchUpdateVisible()
  endif
  " 终端下 autoread 需要主动 checktime：切 buffer 只检查当前 buffer，切回 Vim 时检查全部
  autocmd BufEnter * if &buftype ==# '' && getcmdwintype() ==# '' | silent! execute 'checktime ' . bufnr('%') | endif
  autocmd FocusGained * if getcmdwintype() ==# '' | silent! checktime | endif
  " 文件列表缓存：每次进入 : 命令行重新扫描一次 (旧版本没有 CmdlineEnter 时在写入/切回时失效)
  if exists('##CmdlineEnter')
    autocmd CmdlineEnter : let s:files_cache = []
  else
    autocmd BufWritePost,FocusGained,ShellCmdPost * let s:files_cache = []
  endif
  autocmd VimLeavePre * call s:TrimRecent()
  autocmd QuickFixCmdPost [^l]* cwindow
  autocmd QuickFixCmdPost l* lwindow
  autocmd FileType java,c,cpp,cuda,hip,glsl,objc,go,rust,javascript,typescript setlocal commentstring=//\ %s
  " .cu/.cuh 由内置检测识别为 cuda (语法已包含 cpp)，这里只补充内置不认识的扩展名
  autocmd BufNewFile,BufRead *.cce,*.hip setfiletype cpp
  autocmd BufNewFile,BufRead *.mlir,*.td setlocal commentstring=//\ %s
  if exists('##TerminalOpen')
    autocmd TerminalOpen * setlocal norelativenumber nonumber signcolumn=no
  endif
  if exists('##TextYankPost')
    autocmd TextYankPost * call s:FlashYank()
    " 若处于 SSH 或 Tmux 环境，复制时自动触发 OSC 52
    if exists('$SSH_TTY') || exists('$TMUX')
      autocmd TextYankPost * call s:AutoOsc52()
    endif
  endif
  autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line('$') && &ft !~# 'commit' | execute "normal! g'\"" | execute 'normal! zz' | endif
  autocmd BufDelete * call s:RememberClosed(str2nr(expand('<abuf>')))
  autocmd BufWritePost *.sh,*.py call s:MakeExecutable(expand('<afile>:p'))
  autocmd BufNewFile *.sh if line('$') == 1 && getline(1) ==# '' | call setline(1, '#!/bin/bash') | endif
  autocmd BufNewFile *.py if line('$') == 1 && getline(1) ==# '' | call setline(1, '#!/usr/bin/env python3') | endif
augroup END
" }}}

" ==============================================================================
" 5. 状态栏、原生顶部 Buffer 栏与零开销 Git 分支检测
" ==============================================================================
" {{{ 状态栏与 Tabline
let s:last_mode = ''

function! StatusModeName() abort
  let l:m = mode(1)
  if l:m =~# '^R' | return 'Replace '
  elseif l:m =~# '^[vV\x16sS]' | return 'Visual '
  elseif l:m =~# '^i' | return 'Insert '
  elseif l:m =~# '^t' | return 'Terminal '
  endif
  return 'Normal '
endfunction

function! StatusSetModeColor() abort
  let l:m = StatusModeName()
  if l:m ==# s:last_mode
    return ''
  endif
  let s:last_mode = l:m
  let l:color = (l:m ==# 'Insert ' || l:m ==# 'Terminal ') ? '#7AA2F7' : '#9ECE6A'
  let l:cterm = (l:m ==# 'Insert ' || l:m ==# 'Terminal ') ? '111' : '149'
  if l:m ==# 'Visual ' || l:m ==# 'Replace '
    let l:color = '#F7768E'
    let l:cterm = '204'
  endif
  execute 'highlight User3 guifg=#1a1b26 guibg=' . l:color . ' ctermfg=234 ctermbg=' . l:cterm . ' gui=bold cterm=bold'
  execute 'highlight User4 guifg=' . l:color . ' guibg=#232433 ctermfg=' . l:cterm . ' ctermbg=235'
  return ''
endfunction

" 仅在模式真正变化时才重绘状态栏
function! s:UpdateModeColor() abort
  let l:old = s:last_mode
  call StatusSetModeColor()
  if s:last_mode !=# l:old
    redrawstatus
  endif
endfunction

augroup VimrcMode
  autocmd!
  if exists('##ModeChanged')
    autocmd ModeChanged * call s:UpdateModeColor()
  else
    autocmd InsertEnter,InsertLeave,CursorMoved,CursorMovedI * call s:UpdateModeColor()
  endif
augroup END

" 纯 Vimscript 解析 .git/HEAD，0 子进程开销，兼容 Git Worktree / Submodule
function! s:GitBranch(dir) abort
  " 'path' 语法中空格与逗号需要转义；Windows 下统一为正斜杠
  let l:dir = escape(tr(a:dir, '\', '/'), ' ,')
  let l:git = finddir('.git', l:dir . ';')
  if l:git !=# ''
    let l:git = fnamemodify(l:git, ':p')
  else
    let l:gitfile = findfile('.git', l:dir . ';')
    if l:gitfile !=# '' && filereadable(l:gitfile)
      let l:lines = readfile(l:gitfile, '', 1)
      if !empty(l:lines) && l:lines[0] =~# '^gitdir:\s*'
        let l:git = substitute(l:lines[0], '^gitdir:\s*', '', '')
        if l:git !~# '^/\|^\a:[\\/]' | let l:git = fnamemodify(l:gitfile, ':p:h') . '/' . l:git | endif
      endif
    endif
  endif
  let l:head = l:git !=# '' ? substitute(l:git, '[\\/]$', '', '') . '/HEAD' : ''
  if l:head ==# '' || !filereadable(l:head)
    return ''
  endif
  let l:data = readfile(l:head, '', 1)
  if empty(l:data)
    return ''
  endif
  let l:branch = l:data[0] =~# '^ref:'
        \ ? substitute(l:data[0], '^ref: refs/\(heads/\|remotes/\|tags/\)\?', '', '')
        \ : strpart(l:data[0], 0, 7)
  return ' ' . l:branch . ' |'
endfunction

" 分支信息按 buffer 存储，分屏时每个窗口显示各自文件所在仓库的分支
function! s:GitBranchUpdate(buf) abort
  let l:name = bufname(a:buf)
  let l:dir = (l:name ==# '' || getbufvar(a:buf, '&buftype') !=# '') ? getcwd() : fnamemodify(l:name, ':p:h')
  call setbufvar(a:buf, 'status_git_branch', s:GitBranch(l:dir))
endfunction

function! s:GitBranchUpdateVisible() abort
  for l:b in tabpagebuflist()
    call s:GitBranchUpdate(l:b)
  endfor
  redrawstatus!
endfunction
call s:GitBranchUpdate(bufnr('%'))

" 原生顶部 Buffer 栏 (支持 <Leader>1..9 快速跳转)
function! s:ListedBuffers() abort
  if exists('*getbufinfo')
    return map(getbufinfo({'buflisted': 1}), 'v:val.bufnr')
  endif
  return filter(range(1, bufnr('$')), 'buflisted(v:val)')
endfunction

function! StatusTabLine() abort
  let l:s = ''
  let l:cur = bufnr('%')
  let l:idx = 1
  for l:b in s:ListedBuffers()
    let l:hl = (l:b == l:cur) ? '%#TabLineSel#' : '%#TabLine#'
    let l:name = fnamemodify(bufname(l:b), ':t')
    if l:name ==# '' | let l:name = '[No Name]' | endif
    let l:mod = getbufvar(l:b, '&modified') ? '+' : ''
    " 文件名中的 % 需转义，否则会被当作 tabline 格式符
    let l:s .= l:hl . ' ' . l:idx . ':' . substitute(l:name, '%', '%%', 'g') . l:mod . ' '
    let l:idx += 1
  endfor
  let l:s .= '%#TabLineFill#%T%=%#TabLine# Buffers '
  return l:s
endfunction
set tabline=%!StatusTabLine()

function! s:JumpBufferByIdx(idx) abort
  let l:bufs = s:ListedBuffers()
  if a:idx <= len(l:bufs)
    execute 'buffer ' . l:bufs[a:idx - 1]
  endif
endfunction
for s:i in range(1, 9)
  execute 'nnoremap <silent> <Leader>' . s:i . ' :call <SID>JumpBufferByIdx(' . s:i . ')<CR>'
endfor

" 有 ModeChanged 时由自动命令切换颜色；旧版本才在状态栏求值时检测，避免重绘中执行 :highlight
let &statusline = (exists('##ModeChanged') ? '' : '%{StatusSetModeColor()}') . '%3* %{StatusModeName()}'
set statusline+=%4*\ %{get(b:,'status_git_branch','')}\ %<%F\ \|%m%r%h%w%=
set statusline+=%3*\ %Y\ \|
set statusline+=%3*¦%{&fenc!=#''?&fenc:&enc}%{&bomb?'+':''}¦
set statusline+=%5*☰\ %l/%-L¦%3p%%¦@:%v\ ¦
" }}}

" ==============================================================================
" 6. TokyoNight 内置配色 (带 256 色精确终端降级映射)
" ==============================================================================
" {{{ TokyoNight Colorscheme
" 不设置 g:colors_name：并不存在对应的 colors/tokyonight.vim，设置后修改 'background' 会触发 E185
set background=dark
let g:tokyonight_style = get(g:, 'tokyonight_style', 'night')
let s:bg  = g:tokyonight_style ==# 'storm' ? '#24283b' : '#1a1b26'
let s:bg1 = g:tokyonight_style ==# 'storm' ? '#282d42' : '#232433'

" Hex 到 256-color 索引映射表，确保非 TrueColor 终端下配色依然准确
let s:c256 = {
      \ 'NONE': 'NONE', '#1a1b26': '234', '#232433': '235', '#24283b': '235',
      \ '#282d42': '236', '#2a2b3d': '236', '#32344a': '237', '#3b3d57': '238',
      \ '#444B6A': '60',  '#a9b1d6': '146', '#7AA2F7': '111', '#9ECE6A': '149',
      \ '#E0AF68': '179', '#F7768E': '204', '#FF9E64': '215', '#ad8ee6': '140',
      \ '#b9f27c': '156', '#ff7a93': '210'
      \ }

function! s:HL(group, fg, bg, ...) abort
  let l:cf = get(s:c256, a:fg, 'NONE')
  let l:cb = get(s:c256, a:bg, 'NONE')
  let l:attr = a:0 ? ' gui=' . a:1 . ' cterm=' . (a:1 ==# 'undercurl' ? 'underline' : a:1) : ' gui=NONE cterm=NONE'
  execute 'highlight ' . a:group . ' guifg=' . a:fg . ' guibg=' . a:bg . ' ctermfg=' . l:cf . ' ctermbg=' . l:cb . l:attr
endfunction

call s:HL('Normal',       '#a9b1d6', s:bg)
call s:HL('EndOfBuffer',  s:bg,      s:bg)
call s:HL('SignColumn',   '#a9b1d6', s:bg1)
call s:HL('FoldColumn',   '#444B6A', s:bg1)
call s:HL('Folded',       '#444B6A', s:bg1)
call s:HL('CursorLine',   'NONE',    s:bg1)
call s:HL('LineNr',       '#444B6A', 'NONE')
call s:HL('CursorLineNr', '#a9b1d6', s:bg1, 'bold')
call s:HL('Visual',       'NONE',    '#32344a')
call s:HL('Search',       '#1a1b26', '#b9f27c', 'bold')
call s:HL('IncSearch',    '#1a1b26', '#ff7a93', 'bold')
call s:HL('MatchParen',   '#FF9E64', '#3b3d57', 'bold')
call s:HL('Pmenu',        '#a9b1d6', '#2a2b3d')
call s:HL('PmenuSel',     '#1a1b26', '#b9f27c', 'bold')
call s:HL('StatusLine',   '#a9b1d6', '#32344a')
call s:HL('StatusLineNC', '#444B6A', s:bg1)
call s:HL('VertSplit',    '#32344a', s:bg)
call s:HL('TabLine',      '#a9b1d6', '#232433')
call s:HL('TabLineFill',  'NONE',    s:bg)
call s:HL('TabLineSel',   '#1a1b26', '#7AA2F7', 'bold')
call s:HL('SpecialKey',   '#444B6A', 'NONE')
call s:HL('NonText',      '#444B6A', 'NONE')
call s:HL('ErrorMsg',     '#F7768E', 'NONE', 'bold')
call s:HL('WarningMsg',   '#E0AF68', 'NONE', 'bold')
call s:HL('Comment',      '#444B6A', 'NONE', 'italic')
call s:HL('String',       '#E0AF68', 'NONE')
call s:HL('Constant',     '#FF9E64', 'NONE')
call s:HL('Number',       '#ad8ee6', 'NONE')
call s:HL('Identifier',   '#FF9E64', 'NONE')
call s:HL('Function',     '#9ECE6A', 'NONE')
call s:HL('Type',         '#7AA2F7', 'NONE', 'italic')
call s:HL('Statement',    '#F7768E', 'NONE')
call s:HL('PreProc',      '#F7768E', 'NONE')
call s:HL('Special',      '#ad8ee6', 'NONE')
call s:HL('Todo',         '#7AA2F7', 'NONE', 'italic')

highlight User1 guifg=#1a1b26 guibg=#9ECE6A ctermfg=234 ctermbg=149
highlight User2 guifg=#9ECE6A guibg=#232433 ctermfg=149 ctermbg=235
highlight User3 guifg=#1a1b26 guibg=#9ECE6A ctermfg=234 ctermbg=149 gui=bold cterm=bold
highlight User4 guifg=#9ECE6A guibg=#232433 ctermfg=149 ctermbg=235
highlight User5 guifg=#1a1b26 guibg=#7AA2F7 ctermfg=234 ctermbg=111 gui=bold cterm=bold
highlight User6 guifg=#7AA2F7 guibg=#232433 ctermfg=111 ctermbg=235
let s:last_mode = ''
call StatusSetModeColor()
" }}}

" vim: set ft=vim fdm=marker:
