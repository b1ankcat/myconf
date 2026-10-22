" ==============================================================================
" 1. 兼容性初始化与全局引导
" ==============================================================================
if v:version < 800 || has('compatible')
  set nocompatible
endif

let mapleader = ','
let g:netrw_home = expand('~/.cache/vim')
let g:status_git_branch = ''
let g:map_recent_close = {}

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
set fileencodings=utf-8,ucs-bom,gb18030,gbk,cp936,gb2312,latin1
silent! set helplang=cn

" 修复 Tmux / 远程终端下的 TrueColor 序列识别
if exists('+termguicolors')
  if &term =~# '^screen\|^tmux\|^xterm'
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  endif
  set termguicolors
endif
set t_Co=256

set hidden autoread autowrite confirm
set nobackup noswapfile
if has('persistent_undo')
  let &undodir = s:cache_dir . '/undo'
  set undofile
endif

set number cursorline laststatus=2 showtabline=2 ruler showcmd noshowmode
if exists('+signcolumn')
  set signcolumn=yes
endif

set cmdheight=1 textwidth=0 nowrap virtualedit=block,onemore
set whichwrap+=<,>,h,l ttimeout ttimeoutlen=10 timeoutlen=500 matchpairs+=<:>
set autoindent smartindent cindent cinoptions=g0,:0,N-s,(0
set tabstop=4 shiftwidth=4 softtabstop=4 smarttab expandtab
set backspace=indent,eol,start sidescroll=1 sidescrolloff=4 scrolloff=4 nofoldenable
set splitbelow splitright
set list lcs=tab:¦\ ,trail:·,extends:»,precedes:«

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
set wildignore+=*.o,*.obj,*.so,*.a,*.pyc,__pycache__/*,.git/*,build/*,dist/*
set path+=**

set completeopt=menuone,preview
if v:version >= 704
  silent! set completeopt+=noselect
  silent! set shortmess+=c
endif
set omnifunc=syntaxcomplete#Complete cpt+=kspell
set hlsearch incsearch ignorecase smartcase

" 优先使用 ripgrep (rg) 作为内置 :grep 引擎
if executable('rg')
  set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ -g\ '!.git'
  set grepformat=%f:%l:%c:%m
endif

" {{{ 插入模式与原生 Auto-Pairs / SuperTab
function! s:Enter() abort
  if pumvisible()
    return "\<C-Y>"
  endif
  let l:line = getline('.')
  let l:col = col('.') - 1
  let l:prev = strpart(l:line, l:col - 1, 1)
  let l:next = strpart(l:line, l:col, 1)
  if (l:prev ==# '{' && l:next ==# '}') || (l:prev ==# '[' && l:next ==# ']') || (l:prev ==# '(' && l:next ==# ')')
    return "\<CR>\<ESC>O"
  endif
  return "\<CR>"
endfunction

function! s:Backspace() abort
  let l:line = getline('.')
  let l:col = col('.') - 1
  let l:pair = strpart(l:line, l:col - 1, 2)
  if index(['()', '[]', '{}', '""', "''", '``'], l:pair) >= 0
    return "\<Right>\<BS>\<BS>"
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

inoremap ( ()<Left>
inoremap [ []<Left>
inoremap { {}<Left>
cnoremap ( ()<Left>
cnoremap [ []<Left>
cnoremap { {}<Left>

function! s:Judge(ch, mode) abort
  let l:line = a:mode ==# 'c' ? getcmdline() : getline('.')
  let l:pos  = a:mode ==# 'c' ? getcmdpos() - 1 : col('.') - 1
  let l:cur  = strpart(l:line, l:pos, 1)
  let l:prev = l:pos > 0 ? strpart(l:line, l:pos - 1, 1) : ''

  " 跳过已存在的闭合符号
  if l:cur ==# a:ch
    return "\<Right>"
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
    return a:ch . a:ch . "\<Left>"
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
" {{{ [原生插件 1] 代码注释切换 (gcc / gc，替代 vim-commentary)
function! s:ToggleComment(...) range abort
  let l:cms = get(b:, 'commentstring', &commentstring)
  if l:cms ==# '' || stridx(l:cms, '%s') < 0
    let l:cms = '# %s'
  endif
  let [l:l1, l:l2] = a:0 ? [line("'["), line("']")] : [a:firstline, a:lastline]
  let l:parts = split(l:cms, '%s', 1)
  let l:pre = substitute(l:parts[0], '\s\+$', '', '')
  let l:post = len(l:parts) > 1 ? l:parts[1] : ''
  let l:pre_esc = escape(l:pre, '\.^$*~[]')
  let l:post_esc = escape(l:post, '\.^$*~[]')

  let l:uncomment = 1
  let l:min_indent = 9999
  for l:lnum in range(l:l1, l:l2)
    let l:str = getline(l:lnum)
    if l:str =~# '\S'
      let l:ind = len(matchstr(l:str, '^\s*'))
      if l:ind < l:min_indent | let l:min_indent = l:ind | endif
      if l:str !~# '^\s*' . l:pre_esc . '\(\s\|$\)'
        let l:uncomment = 0
      endif
    endif
  endfor
  if l:min_indent == 9999 | let l:min_indent = 0 | endif

  for l:lnum in range(l:l1, l:l2)
    let l:str = getline(l:lnum)
    if l:str !~# '\S' | continue | endif
    if l:uncomment
      let l:str = substitute(l:str, '^\(\s*\)' . l:pre_esc . '\s\?', '\1', '')
      if l:post !=# ''
        let l:str = substitute(l:str, '\s\?' . l:post_esc . '\s*$', '', '')
      endif
    else
      let l:pad = strpart(l:str, 0, l:min_indent)
      let l:rest = strpart(l:str, l:min_indent)
      let l:str = l:pad . l:pre . ' ' . l:rest . (l:post !=# '' ? ' ' . l:post : '')
    endif
    call setline(l:lnum, l:str)
  endfor
endfunction

nnoremap <silent> gcc :call <SID>ToggleComment()<CR>
xnoremap <silent> gc  :call <SID>ToggleComment()<CR>
nnoremap <silent> gc  :set opfunc=<SID>ToggleComment<CR>g@
" }}}

" {{{ [原生插件 2] 轻量 Surround 操作 (ds / cs / 可视 S，替代 vim-surround)
function! s:GetPair(ch) abort
  let l:map = {'(': ['(', ')'], ')': ['(', ')'], 'b': ['(', ')'],
        \ '[': ['[', ']'], ']': ['[', ']'], 'r': ['[', ']'],
        \ '{': ['{', '}'], '}': ['{', '}'], 'B': ['{', '}'],
        \ '<': ['<', '>'], '>': ['<', '>'], 'a': ['<', '>']}
  return get(l:map, a:ch, [a:ch, a:ch])
endfunction

function! s:DeleteSurround() abort
  let l:ch = nr2char(getchar())
  if l:ch =~# '^\s*$' | return | endif
  let l:save = @z
  execute 'normal! "zyi' . l:ch . 'va' . l:ch . '"zp'
  let @z = l:save
endfunction

function! s:ChangeSurround() abort
  let l:old = nr2char(getchar())
  let l:new = nr2char(getchar())
  if l:old =~# '^\s*$' || l:new =~# '^\s*$' | return | endif
  let [l:open, l:close] = s:GetPair(l:new)
  let l:save = @z
  execute 'normal! "zyi' . l:old
  let @z = l:open . @z . l:close
  execute 'normal! va' . l:old . '"zp'
  let @z = l:save
endfunction

function! s:VisualSurround() range abort
  let l:ch = nr2char(getchar())
  let [l:open, l:close] = s:GetPair(l:ch)
  let l:save = @z
  normal! gv"zy
  let @z = l:open . @z . l:close
  normal! gv"zp
  let @z = l:save
endfunction

nnoremap <silent> ds :call <SID>DeleteSurround()<CR>
nnoremap <silent> cs :call <SID>ChangeSurround()<CR>
xnoremap <silent> S  :<C-U>call <SID>VisualSurround()<CR>
" }}}

" {{{ [原生插件 3] OSC 52 远程剪贴板透传与复制高亮 (替代 vim-oscyank & highlightedyank)
function! s:Osc52Yank(text) abort
  if !executable('base64') || !filewritable('/dev/tty') | return | endif
  let l:b64 = substitute(system('base64', a:text), '[\r\n]', '', 'g')
  let l:seq = "\e]52;c;" . l:b64 . "\x07"
  if exists('$TMUX')
    let l:seq = "\ePtmux;\e" . l:seq . "\e\\"
  endif
  silent! call writefile([l:seq], '/dev/tty', 'b')
endfunction

nnoremap <silent> <Leader>y :call <SID>Osc52Yank(@")<CR>:echohl ModeMsg \| echo "Yanked to system clipboard (OSC 52)" \| echohl None<CR>
xnoremap <silent> <Leader>y y:call <SID>Osc52Yank(@")<CR>:echohl ModeMsg \| echo "Yanked to system clipboard (OSC 52)" \| echohl None<CR>

function! s:FlashYank() abort
  if !exists('*matchaddpos') || !exists('*timer_start') || get(v:event, 'operator', '') !=# 'y'
    return
  endif
  let [l:l1, l:c1] = [line("'["), col("'[")]
  let [l:l2, l:c2] = [line("']"), col("']")]
  let l:pos = []
  for l:l in range(l:l1, l:l2)
    if l:l == l:l1 && l:l == l:l2
      call add(l:pos, [l:l, l:c1, l:c2 - l:c1 + 1])
    elseif l:l == l:l1
      call add(l:pos, [l:l, l:c1, col([l:l, '$']) - l:c1 + 1])
    elseif l:l == l:l2
      call add(l:pos, [l:l, 1, l:c2])
    else
      call add(l:pos, l:l)
    endif
  endfor
  let l:id = matchaddpos('IncSearch', l:pos[:7])
  call timer_start(180, {-> execute('silent! call matchdelete(' . l:id . ')')})
endfunction
" }}}

" {{{ [原生插件 4] 自动命令、CUDA/AscendC 支持与最近关闭/MRU 文件
function! s:CompareRecent(a, b) abort
  return a:a.time == a:b.time ? 0 : (a:a.time > a:b.time ? -1 : 1)
endfunction

function! s:GetRecentClose() abort
  let l:items = []
  for [l:file, l:value] in items(g:map_recent_close)
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
    for l:old in v:oldfiles[:30]
      let l:p = expand(l:old)
      if !has_key(g:map_recent_close, l:p) && filereadable(l:p)
        call add(l:items, {'filename': l:p, 'lnum': 1, 'col': 1, 'text': 'History MRU'})
      endif
    endfor
  endif
  call setqflist(l:items, 'r')
  copen
endfunction
nnoremap <silent> <nowait> <Space>q :call <SID>GetRecentClose()<CR>

" 快速文件查找、全局搜索与常用效率快捷键
nnoremap <Leader>f :find *
nnoremap <Leader>b :ls<CR>:b<Space>
nnoremap <silent> <Leader>g :execute 'silent grep! ' . shellescape(expand('<cword>'))<CR>:redraw!<CR>
nnoremap <silent> <Leader><Space> :let _s=@/<Bar>:%s/\s\+$//e<Bar>:let @/=_s<Bar>:nohlsearch<CR>
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [q :cprevious<CR>
nnoremap <silent> ]q :cnext<CR>

function! Time() abort
  return 'update by chenxuan ' . strftime('%Y-%m-%d %H:%M:%S')
endfunction

augroup VimrcCore
  autocmd!
  autocmd BufEnter * call GitBranchUpdate() | redrawstatus
  autocmd QuickFixCmdPost [^l]* cwindow
  autocmd QuickFixCmdPost l* lwindow
  autocmd FileType java,c,cpp,cuda,hip,glsl,objc,go,rust,javascript,typescript setlocal commentstring=//\ %s
  autocmd BufNewFile,BufRead *.cu,*.cuh,*.cce,*.hip setfiletype cpp
  autocmd BufNewFile,BufRead *.mlir,*.td setlocal commentstring=//\ %s
  if exists('##TerminalOpen')
    autocmd TerminalOpen * setlocal norelativenumber nonumber signcolumn=no
  endif
  if exists('##TextYankPost')
    autocmd TextYankPost * call <SID>FlashYank()
    " 若处于 SSH 或 Tmux 环境且无本地 X11 剪贴板，复制时自动触发 OSC 52
    autocmd TextYankPost * if (exists('$SSH_TTY') || exists('$TMUX')) && v:event.regname ==# '' | call <SID>Osc52Yank(@") | endif
  endif
  autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line('$') && &ft !~# 'commit' | execute "normal! g'\"" | execute 'normal! zz' | endif
  autocmd BufDelete * if expand('%:p') !=# '' && &buftype ==# '' | let g:map_recent_close[expand('%:p')] = {'lnum': line('.'), 'col': col('.'), 'time': localtime()} | endif
  autocmd BufWritePost *.sh,*.py if exists('*setfperm') && getline(1) =~# '^#!' | call setfperm(expand('%'), 'rwxrwxr-x') | endif
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

function! s:UpdateModeColor() abort
  call StatusSetModeColor()
  redrawstatus
endfunction

augroup VimrcMode
  autocmd!
  autocmd InsertEnter,InsertLeave,WinEnter,BufEnter * call <SID>UpdateModeColor()
  if exists('##ModeChanged')
    autocmd ModeChanged * call <SID>UpdateModeColor()
  else
    autocmd CursorMoved,CursorMovedI * call <SID>UpdateModeColor()
  endif
augroup END

" 纯 Vimscript 解析 .git/HEAD，0 子进程开销，兼容 Git Worktree / Submodule
function! GitBranchUpdate() abort
  let l:dir = expand('%:p:h')
  if l:dir ==# '' || &buftype !=# '' | let l:dir = getcwd() | endif
  let l:git = finddir('.git', fnameescape(l:dir) . ';')
  if l:git ==# ''
    let l:gitfile = findfile('.git', fnameescape(l:dir) . ';')
    if l:gitfile !=# '' && filereadable(l:gitfile)
      let l:lines = readfile(l:gitfile, '', 1)
      if !empty(l:lines) && l:lines[0] =~# '^gitdir:\s*'
        let l:git = substitute(l:lines[0], '^gitdir:\s*', '', '')
        if l:git !~# '^/' | let l:git = fnamemodify(l:gitfile, ':h') . '/' . l:git | endif
      endif
    endif
  endif
  let l:head = l:git !=# '' ? l:git . '/HEAD' : ''
  if l:head !=# '' && filereadable(l:head)
    let l:data = readfile(l:head, '', 1)
    if !empty(l:data)
      let l:branch = l:data[0] =~# '^ref:'
            \ ? substitute(l:data[0], '^ref: refs/\(heads/\|remotes/\|tags/\)\?', '', '')
            \ : strpart(l:data[0], 0, 7)
      let g:status_git_branch = ' ' . l:branch . ' |'
      return
    endif
  endif
  let g:status_git_branch = ''
endfunction
call GitBranchUpdate()

" 原生顶部 Buffer 栏 (支持 <Leader>1..9 快速跳转)
function! StatusTabLine() abort
  let l:s = ''
  let l:cur = bufnr('%')
  let l:idx = 1
  for l:b in range(1, bufnr('$'))
    if buflisted(l:b)
      let l:hl = (l:b == l:cur) ? '%#TabLineSel#' : '%#TabLine#'
      let l:name = fnamemodify(bufname(l:b), ':t')
      if l:name ==# '' | let l:name = '[No Name]' | endif
      let l:mod = getbufvar(l:b, '&modified') ? '+' : ''
      let l:s .= l:hl . ' ' . l:idx . ':' . l:name . l:mod . ' '
      let l:idx += 1
    endif
  endfor
  let l:s .= '%#TabLineFill#%T%=%#TabLine# Buffers '
  return l:s
endfunction
set tabline=%!StatusTabLine()

function! s:JumpBufferByIdx(idx) abort
  let l:cnt = 1
  for l:b in range(1, bufnr('$'))
    if buflisted(l:b)
      if l:cnt == a:idx | execute 'buffer ' . l:b | return | endif
      let l:cnt += 1
    endif
  endfor
endfunction
for s:i in range(1, 9)
  execute 'nnoremap <silent> <Leader>' . s:i . ' :call <SID>JumpBufferByIdx(' . s:i . ')<CR>'
endfor

set statusline=%{StatusSetModeColor()}%3*\ %{StatusModeName()}
set statusline+=%4*\ %{g:status_git_branch}\ %F\ \|%m%r%h%w%=
set statusline+=%3*\ %Y\ \|
set statusline+=%3*¦%{&enc.(&bomb?'+':'')}¦
set statusline+=%5*☰\ %l/%-L¦%3p%%¦@:%v\ ¦
" }}}

" ==============================================================================
" 6. TokyoNight 内置配色 (带 256 色精确终端降级映射)
" ==============================================================================
" {{{ TokyoNight Colorscheme
let g:tokyonight_style = get(g:, 'tokyonight_style', 'night')
let s:bg  = g:tokyonight_style ==# 'storm' ? '#24283b' : '#1a1b26'
let s:bg1 = g:tokyonight_style ==# 'storm' ? '#282d42' : '#232433'
let g:colors_name = 'tokyonight'

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