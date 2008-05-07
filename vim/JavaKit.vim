"Make sure this file is only sourced once
if exists("JavakitSourced")
	finish
endif
let JavakitSourced = "true"

" This value must be set to point to the directory where you store(unzip) the
" srcipt files.
let g:VIMMACROSPATH = ""

exe "so " . g:VIMMACROSPATH . "Javac.vim"
exe "so " . g:VIMMACROSPATH . "JavaDebug.vim"
exe "so " . g:VIMMACROSPATH . "Javadoc.vim"
exe "so " . g:VIMMACROSPATH . "JavaMacros.vim"
exe "so " . g:VIMMACROSPATH . "JavaSearch.vim"
exe "so " . g:VIMMACROSPATH . "JavaUtil.vim"
