if exists("JavacSourced")
	finish
endif 
let JavacSourced = "true"

exe "so " . g:VIMMACROSPATH . "Functions.vim"

" The name for the error file.
let s:errorFile = ""
" The buffer number for the error file.
let s:buffNum = -1
" The current error number.
let s:errorNum = -1
" The total number of errors in each compilation.
let s:totalErrors = 0

let s:winSize = {}
" Function: Invoke the javac from Sun on the current file.
function! InvokeJavac(...)
	let counter = 1
	let commands = ""
	while counter <= a:0
		exe "let commands = commands . a:" . counter . ". \" \""
		let counter = counter + 1
	endwhile

	" echoerr commands

	" Create the error file if necessary.
	if (strlen(s:errorFile) == 0)
		let s:errorFile = tempname()
	endif

	let s:winSize = GetWinSize()
	" Save the current window so we can get back to it later.
	let oldWindow = winnr()

	" See if the error file exist in any of the open window.  If it does go to
	" that window; otherwise, open a new window for it.
	if (FileInWindow(s:errorFile, 1) ==  0)
		exe "silent sp "
		let oldWindow = winnr() + 1
	endif

	" close the previous error file
	" if (s:buffNum != -1)
		" exe 'bwipe ' . s:buffNum
	" endif

	" Open the errorFile so we can dump the output of javac into it later.
	exe "silent edit! " . s:errorFile

	" Keep the buffer number for the error file
	let s:buffNum = bufnr("%") 

	" Get a clean slate to write on.
	%d

	" Turn on same special buffer options for the error file.
	setlocal noswapfile
	setlocal nobuflisted
	setlocal autoread
	setlocal buftype=nowrite
	setlocal bufhidden=delete

	" Run the commands and dump its output in current file.
	exe "silent r !" . commands
	call s:DisplayErrors(oldWindow)

endfun

" Function: This is a handoff from the InvokeJavac function, displays the errors
" in the error file window.  If there is no error in the compilation, then close
" the error file's window.
fun! s:DisplayErrors(oldWindow)

	" The compilation went fine.
	if line(".") == line("$") && getline(".") =~ "^\s*$"
		exe 'bwipe ' . s:buffNum
		let s:totalErrors = 0
		" call GoToWindow(a:oldWindow-1)
		call RestoreWinSize(s:winSize, 0)
		" echoerr "hi"

	" javac displays some warning or error
	elseif getline(2) =~ '\.$'
		call SetViewport(2, line("$"))
		call GoToWindow(a:oldWindow)
	else

		" Comstom highlight for the errors.
		call s:HighlightJavacErrors()

		" Go to the end of the line to get the number for the total of errors
		let s:totalErrors = substitute(getline("$"), '\(^\d\+\).*$', '\1', '')

		" Get rid of all the return chars (windows)
		%s///e

		" Go back to where all this started.
		call GoToWindow(a:oldWindow)

		" Display the first error.
		call GoToError(0, 1)
	endif

endfun

" Go to next error
nnoremap ,n :call GoToError(2, 1)<CR>
" Go to previous error
nnoremap ,b :call GoToError(2, 0)<CR>
" Go to the first error
nnoremap ,f :call GoToError(0, 1)<CR>
" Go to the last error
nnoremap ,l :call GoToError(1, 0)<CR>

" Traverse to the error by following the strageties given in the parameters.
" direction - 0 backward, 1 forward
" startPoint - 0 start from the top, 1 start from bottom, 2 current
fun! GoToError(startPoint, direction)
	if (s:totalErrors == 0)
		echo "There is no compilation error :-)"
	endif

	" Save the winnr() for current window, so that we can get back to it later.
	let oldWindow = winnr()

	" Some vars for finding the matched lines.
	let line = 0
	let column = 0
	let pos = 0

	" Find the error file's window and go there.
	let errorWindow = BufferInWindow(s:buffNum, 1)

	if (errorWindow != 0)
		if (a:startPoint == 0)
			" Set the errorNum to be invalid so it will be reset again to point to
			" the FIRST error in the later if statements.
			let s:errorNum = -1
			exe "silent normal! gg"
		elseif (a:startPoint == 1)
			" Set the errorNum to be invalid so it will be reset again to point to
			" the LAST error in the later if statements.
			let s:errorNum = -1
			exe "silent normal! G"
		endif

		if (a:direction == 1)
			" Go dwon one line so that the search can go to the next error
			" otherwise it can stuck in the same line.
			let before = line(".")
			exe "silent normal! j"
			exe "silent normal! /:\\d\\+:\<CR>"
			let after = line(".")

			" The search is starting from the top.
			if (s:errorNum == -1)
				let s:errorNum = 1
			" The search has been wrapped around back to the top.
			elseif (before > after)
				let s:errorNum = 1
			else
				let s:errorNum = s:errorNum + 1
			endif
		else
			let before = line(".")
			" prevent stucking on the same line
			exe "silent normal! ?\\^\<CR>"
			exe "silent normal! ?:\\d\\+:\<CR>"
			let after = line(".")

			" The search is starting from the bottom
			if (s:errorNum == -1)
				let s:errorNum = s:totalErrors
			" The search has been wrapped around back to the bottom.
			elseif (before < after)
				let s:errorNum = s:totalErrors
			else
				let s:errorNum = s:errorNum - 1
			endif
		endif

		" Hit the low end, so srap around s:errorNum to 1
		if (s:errorNum == 0)
			let s:errorNum = 1
		endif

		" Hit the high end, so wrap around s:errorNum to s:totalErrors
		if (s:errorNum > s:totalErrors)
			let s:errorNum = s:totalErrors
		endif

		" Some vars for collecting the info about the java source file that's
		" causing the current error.
		let begin = line(".")
		let echoLine = getline(".")
		let line = s:GetLineNum(echoLine)
		let sourceFile = strpart(echoLine, 0, stridx(echoLine, ":"))

		exe "silent normal! /\\^\<CR>"
		let final = line(".")
		let tabs = 0 " How many tabs should be in current line
		" No tabs are in the current line yet.
		if (match(getline("."), '\t') == -1 && col(".") != 1)
			" Workout how many tabs are in the leading spaces.
			let lineContent = getline(final-1)
			let head = strpart(lineContent, 0, match(lineContent, '\S')+1)
			let tabs = ItemCounts(head, '\t', 'exact')
		endif
		" Get the actual column position for '^'
		let column = col(".") - 1 - (8*tabs) + tabs
		while (tabs > 0)
			" A tabstop in the output of javac has 8 spaces.
			s/        /\t/e
			let tabs = tabs - 1
		endwhile
		" Move one line up to avoid getting stuck at the same line.
		exe "normal!k"

		" Only show the current error
		call SetViewport(begin, final)

		let oldFileName = s:errorFile
		" We use the info that says something about the current error 
		" as the name of the error file.
		let s:errorFile = "Error " . s:errorNum . " of " . s:totalErrors
		" Delete the buffer that's got the old name.
		if (oldFileName != s:errorFile)
			exe "f " . s:errorFile
			" Delete the buffer that's got the old name.
			exe "bwipe " . bufnr("#")
		endif

	endif
	
	if (errorWindow != 0)
		call GoToWindow(oldWindow)
		" The java souce file that contains the current error is different from the
		" one just been compiled.
		if (bufname(winbufnr(oldWindow)) != sourceFile)
			exe "edit " . sourceFile
		endif

		" echoerr column
		let pos = line2byte(line) + column
		" Go to the code that correponds to the current error.
		exec "normal!" . pos . "go"
		redraw
		" If the error is in a fold, then open it.
		exe "normal! zx"
	endif

endfun

" Function: Get the line number in the source code that cause the compiler errors.
" line is part of Sun's JDK compiler output, which contains ':\d\+:' for the
" lineNum in the source code.
fun! s:GetLineNum(line)
	let begin = match(a:line, ':\d\+:', 0)
	let final = match(a:line, ': ', 0)
	return strpart(a:line, begin + 1, final - begin)
endfun

fun! s:HighlightJavacErrors()

	hi JavacError guifg=red gui=bold
	" **** Similar javac error message ****
	" Substituter.java:10: 'class' or 'interface' expected
	syn match javacQuotedWords "[^']*" contained
	syn match javacErrorquote "'[^']*'" contains=javacQuotedWords contained
	hi link javacQuotedWords JavacError

	" **** Similar javac error message ****
	" Substituter.java:24: cannot resolve symbol
	" symbol  : class Pattern  
	syn match javacWord "[_[:alnum:]]\+" contained
	syn match javacSymbolAndSpace "[_[:alnum:]]\+[[:space:]]*\((\|$\)" contains=javacWord contained
	syn match javacSymbolError "^symbol[[:space:]]*: .*$" contains=javacSymbolAndSpace
	hi link javacWord JavacError

	" **** Similar javac error message ****
	" Substituter.java:45: <identifier> expected
	syn match javacIdentifier "identifier" contained
	syn match javacIdentifierQuote "<identifier>" contains=javacIdentifier
	hi link javacIdentifier JavacError

	" **** Similar javac error message ****
	" Substituter.java:72: Substituter() is already defined in Substituter
	syn match javacLeftBracket "(" contained
	syn match javacRightBracket ")" contained
	syn match javacRedefine "[_[:alnum:]]\+(" contains=javacWord,javacLeftBracket contained
	syn match javacMsgHead "^.*:[[:digit:]]\+:" contained
	syn match javacMsg "^.*:[[:digit:]]\+:.*$" 
	\contains=javacRedefine,javacMsgHead,javacErrorQuote,javacLeftBracket,javacRightBracket
	hi javacMsgHead guibg=NONE guifg=NONE
	hi link javacMsg WarningMsg
	hi link javacLeftBracket javacMsg

	hi link javacErrorQuote Question
	hi link javacIdentifierQuote Question
	hi link javacLeftBracket Question
	hi link javacRightBracket Question

endfun
