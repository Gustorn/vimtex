" LaTeX plugin for Vim
"
" Maintainer: Karl Yngve Lervåg
" Email:      karl.yngve@gmail.com
"

" vim-latex is not initialized until latex#init() has been run once
let s:initialized = 0

function! latex#init() " {{{1
  call s:init_options()
  call s:init_environment()

  call latex#toc#init(s:initialized)
  call latex#fold#init(s:initialized)
  call latex#view#init(s:initialized)
  call latex#motion#init(s:initialized)
  call latex#change#init(s:initialized)
  call latex#latexmk#init(s:initialized)
  call latex#complete#init(s:initialized)
  call latex#mappings#init(s:initialized)

  "
  " This variable is used to allow a distinction between global and buffer
  " initialization
  "
  let s:initialized = 1
endfunction

function! latex#info() " {{{1
  if !s:initialized
    echoerr "Error: vim-latex has not been initialized!"
    return
  endif

  " Print buffer data
  echo "b:latex"
  call s:print_dict(b:latex)

  " Print global data
  let n = 0
  for data in g:latex#data
    " Prepare for printing
    let d = deepcopy(data)
    for f in ['aux', 'out', 'log']
      silent execute 'let d.' . f . ' = data.' . f . '()'
    endfor

    " Print data blob title line
    echo "\n"
    echo "g:latex#data[" . n . "] : " . remove(d, 'name')
    call s:print_dict(d)
    let n += 1
  endfor
endfunction

function! latex#help() " {{{1
  if g:latex_mappings_enabled
    nmap <buffer>
    xmap <buffer>
    omap <buffer>
  else
    echo "Mappings not enabled"
  endif
endfunction

function! latex#reinit() " {{{1
  "
  " Stop latexmk processes (if running)
  "
  call latex#latexmk#stop_all()

  "
  " Reset global variables
  "
  let s:initialized = 0
  unlet g:latex#data

  "
  " Reset and reinitialize buffers
  "
  let n = bufnr('%')
  bufdo   if getbufvar('%', '&filetype') == 'tex' |
        \   unlet b:latex                         |
        \   call latex#init()                     |
        \ endif
  silent execute 'buffer ' . n
endfunction
" }}}1

function! s:init_environment() " {{{1
  " Initialize global and local data blobs
  call latex#util#set_default('g:latex#data', [])
  call latex#util#set_default('b:latex', {})

  " Set some file type specific vim options
  setlocal suffixesadd+=.tex
  setlocal commentstring=\%\ %s

  " Create new or link to existing blob
  let main = s:get_main()
  let id   = s:get_id(main)
  if id >= 0
    let b:latex.id = id
  else
    let data = {}
    let data.tex  = main
    let data.root = fnamemodify(data.tex, ':h')
    let data.base = fnamemodify(data.tex, ':t')
    let data.name = fnamemodify(data.tex, ':t:r')
    function data.aux() dict
      return s:get_main_ext(self, 'aux')
    endfunction
    function data.log() dict
      return s:get_main_ext(self, 'log')
    endfunction
    function data.out() dict
      return s:get_main_out(self)
    endfunction

    call add(g:latex#data, data)
    let b:latex.id = len(g:latex#data) - 1
  endif

  " Define commands
  command! -buffer VimLatexInfo         call latex#info()
  command! -buffer VimLatexHelp         call latex#help()
  command! -buffer VimLatexReinitialize call latex#reinit()

  " Define mappings
  nnoremap <buffer> <plug>(vl-info)   :call latex#info()<cr>
  nnoremap <buffer> <plug>(vl-help)   :call latex#help()<cr>
  nnoremap <buffer> <plug>(vl-reinit) :call latex#reinit()<cr>
endfunction

function! s:init_options() " {{{1
  call latex#util#set_default('g:latex_quickfix_ignore_all_warnings', 0)
  call latex#util#set_default('g:latex_quickfix_ignored_warnings', [])

  call latex#util#error_deprecated('g:latex_errorformat_ignore_warnings')
  call latex#util#error_deprecated('g:latex_errorformat_show_warnings')
endfunction
" }}}1

function! s:get_id(main) " {{{1
  if exists('g:latex#data') && !empty(g:latex#data)
    let id = 0
    while id < len(g:latex#data)
      if g:latex#data[id].tex == a:main
        return id
      endif
      let id += 1
    endwhile
  endif

  return -1
endfunction

function! s:get_main() " {{{1
  "
  " Search for main file specifier at the beginning of file.  This is similar
  " to the method used by several other plugins and editors, such as vim with
  " LaTeX-Box, TextMate, TexWorks, and texmaker.
  "
  for line in getline(1, 5)
    let candidate = matchstr(line,
          \ '^\s*%\s*!\s*[tT][eE][xX]\s\+root\s*=\s*\zs.*\ze\s*$')
    if len(candidate) > 0
      let main = fnamemodify(candidate, ':p')
      if filereadable(main)
        return main
      endif
    endif
  endfor

  "
  " Search for main file recursively through \input and \include specifiers
  "
  let main = s:get_main_recurse(expand('%:p'))
  if filereadable(main)
    return main
  endif

  "
  " If not found, use current file
  "
  return expand('%:p')
endfunction

function! s:get_main_recurse(file) " {{{1
  "
  " Check if file is readable
  "
  if !filereadable(a:file)
    return 0
  endif

  "
  " Check if current file is a main file
  "
  if len(filter(readfile(a:file),
        \ 'v:val =~ ''\C\\begin\_\s*{document}''')) > 0
    return fnamemodify(a:file, ':p')
  endif

  "
  " Gather candidate files
  "
  let l:path = expand('%:p:h')
  let l:dirs = l:path
  while l:path != fnamemodify(l:path, ':h')
    let l:path = fnamemodify(l:path, ':h')
    let l:dirs .= ',' . l:path
  endwhile
  let l:candidates = split(globpath(l:dirs, '*.tex'), '\n')

  "
  " Search through candidates for \include{current file}
  "
  for l:file in l:candidates
    if len(filter(readfile(l:file), 'v:val =~ ''\v\\(input|include)\{'
          \ . '\s*((.*)\/)?'
          \ . fnamemodify(a:file, ':t:r') . '(\.tex)?\s*''')) > 0
      return s:get_main_recurse(l:file)
    endif
  endfor

  "
  " If not found, return 0
  "
  return 0
endfunction

function! s:get_main_ext(texdata, ext) " {{{1
  " Create set of candidates
  let candidates = [
        \ a:texdata.name,
        \ g:latex_latexmk_build_dir . '/' . a:texdata.name,
        \ ]

  " Search through the candidates
  for f in map(candidates,
        \ 'a:texdata.root . ''/'' . v:val . ''.'' . a:ext')
    if filereadable(f)
      return fnamemodify(f, ':p')
    endif
  endfor

  " Return empty string if no entry is found
  return ''
endfunction

function! s:get_main_out(texdata) " {{{1
  " Create set of candidates
  let candidates = [
        \ a:texdata.name,
        \ g:latex_latexmk_build_dir . '/' . a:texdata.name,
        \ ]

  " Check for pdf files
  for f in map(candidates,
        \ 'a:texdata.root . ''/'' . v:val . ''.pdf''')
    if filereadable(f)
      return fnamemodify(f, ':p')
    endif
  endfor

  " Check for dvi files
  for f in map(candidates,
        \ 'a:texdata.root . ''/'' . v:val . ''.dvi''')
    if filereadable(f)
      return fnamemodify(f, ':p')
    endif
  endfor

  " Return empty string if no entry is found
  return ''
endfunction

" }}}1

function! s:print_dict(dict, ...) " {{{1
  let level = a:0 > 0 ? a:1 : 0

  for entry in sort(sort(items(a:dict),
        \ "s:print_dict_sort_2"),
        \ "s:print_dict_sort_1")
    let title = repeat(' ', 2 + 2*level) . entry[0] . ' : '
    if type(entry[1]) == type([])
      echo title
      for val in entry[1]
        echo repeat(' ', 4 + 2*level) . string(val)
      endfor
    elseif type(entry[1]) == type({})
      echo title
      call s:print_dict(entry[1], level + 1)
    else
      echo printf('%-s%-s', title, string(entry[1]))
    endif
  endfor
endfunction

" }}}1
function! s:print_dict_sort_1(i1, i2) " {{{1
  return type(a:i1[1]) - type(a:i2[1])
endfunction

" }}}1
function! s:print_dict_sort_2(i1, i2) " {{{1
  return string(a:i1[1]) == string(a:i2[1]) ? 0
        \ : string(a:i1[1]) > string(a:i2[1]) ? 1
        \ : -1
endfunction

" }}}1

" vim: fdm=marker sw=2
