" issue_from_comment.vim - Create GitHub issues from code comments
" Maintainer: OwlfaceGames
" Version: 0.1.0
" Repository: https://github.com/OwlfaceGames/issue-from-comment.nvim

" Prevent loading the plugin multiple times
if exists('g:loaded_issue_from_comment')
  finish
endif
let g:loaded_issue_from_comment = 1

" Set minimum Neovim version required
if !has('nvim-0.5.0')
  echohl ErrorMsg
  echom "issue-from-comment requires Neovim 0.5.0 or later"
  echohl None
  finish
endif

" Define the main command
command! -nargs=0 GHIssueFromComment lua require('issue_from_comment').create_issue_from_comment()

" Optional: Define default keymaps if you want to offer some defaults
" Commented out since most users will define their own keymaps
" nnoremap <silent> <Plug>(issue-from-comment) :GHIssueFromComment<CR>
" if !hasmapto('<Plug>(issue-from-comment)') && maparg('<Leader>gi', 'n') ==# ''
"   nmap <Leader>gi <Plug>(issue-from-comment)
" endif

" vim: set ts=2 sw=2 et:
