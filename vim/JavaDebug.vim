" Make sure this file is only sourced once
if exists("JavaDebugSourced")
	finish
endif
let JavaDebugSourced = "true"

exe "so " . g:VIMMACROSPATH . "Functions.vim"
exe "so " . g:VIMMACROSPATH . "JavaMacros.vim"
exe "so " . g:VIMMACROSPATH . "JavaUtil.vim"

" toggle the breakpoint
nnoremap <silent> et :echo <SID>ToggleBreakpoint()<cr>
" step into a method
nnoremap <silent> es :silent Jdb step<cr>
" execute the current line
nnoremap <silent> ei :silent Jdb stepi<cr>
" continue to the next breakpoint
nnoremap <silent> ec :silent Jdb cont<cr>
" run the next line 
nnoremap <silent> en :silent Jdb next<cr>
" step up a method return to the caller
nnoremap <silent> eu :silent Jdb step up<cr>

" navigate to the next breakpoint
nnoremap <silent> er :call <SID>Navigate(1)<cr>
" navigate to the previous breakpoint
nnoremap <silent> eb :call <SID>Navigate(-1)<cr>

" print the value for the current word
nnoremap <silent> ed :exe "Jdb dump " . expand("<cword>")<cr>
" print the result for the selected expression
vnoremap <silent> ed "zy:exe "Jdb dump " . @z<cr>

" print the fields for a class
nnoremap <silent> ef :exe "Jdb fields " . expand("<cword>")<cr>
" print the fields the selected class
vnoremap <silent> ef "zy:exe "Jdb fields " . @z<cr>

" print the methods for a class
nnoremap <silent> em :exe "Jdb methods " . expand("<cword>")<cr>
" print the methods the selected class
vnoremap <silent> em "zy:exe "Jdb methods " . @z<cr>

" watch the current word
nnoremap <silent> ew :exe "Jdb watch " . expand("<cword>")<cr>
" watch the hightlight expression
vnoremap <silent> ew "zy:exe "Jdb watch " . @z<cr>

" enable breakpoints
nnoremap <silent> ee :call <SID>UseBreakpoints(1)<cr>
" off(disable) breakpoints
nnoremap <silent> eo :call <SID>UseBreakpoints(0)<cr>

" start the jdb command prompt
nnoremap E :Jdb<space>

command! -nargs=+ Jdb :call DebugInterpret(<q-args>)
command! -nargs=* JdbAppend :call s:DebugOutputAppend(<q-args>)

hi LineNr    term=bold ctermfg=red ctermbg=white gui=bold guifg=red guibg=white 
hi SignColumn ctermbg=white guibg=white

hi JdbCurrentLine term=bold ctermfg=black ctermbg=grey gui=bold guifg=black guibg=white 
hi JdbBreakpoint  term=NONE cterm=NONE    gui=NONE
hi JdbSignText    term=bold ctermfg=black ctermbg=grey gui=bold guifg=black guibg=red

sign define JdbCurrentLine linehl=JdbCurrentLine
sign define JdbBreakpoint  linehl=JdbBreakpoint  texthl=JdbSignText text=<>
sign define JdbBoth        linehl=JdbCurrentLine texthl=JdbSignText text=<>

let s:JarFile = "C:\\java\\lib\\debug.jar"
let s:PackageHead = ""
let s:PathHead = ""
let s:DataInitialised = 0
let s:CanClean = 0
" This is the wrapper for taking jdb instructions.
fun! DebugInterpret(instruction)
	if (&filetype == 'java' && s:DataInitialised == 0)
		let className = expand("%:t:r")
		let packageName = FindPackageName('.')
		let s:PathHead = substitute(expand("%:p"), packageName . className . '.java$', '', '')
		let s:PackageHead = ExtractPackageHead(packageName)
		let s:DataInitialised = 1
	endif

	if (s:DataInitialised == 0)
		echoerr "Data not initialised"
		return
	endif

	if (a:instruction =~# "^step")
		let s:CanClean = 1
	elseif (a:instruction == "cont")
		let s:CanClean = 1
	elseif (a:instruction == "next")
		let s:CanClean = 1
	else
		let s:CanClean = 0
	endif

	let startClient = 1
	if (a:instruction =~# "^stop at ")
		let breakpoint = substitute(a:instruction, "^stop at ", '', '')
		let startClient = s:AddBreakpoint(breakpoint, "JdbBreakpoint")

	elseif (a:instruction =~# "^clear ")
		let breakpoint = substitute(a:instruction, "^clear ", '', '')
		let startClient = s:DeleteBreakpoint(breakpoint)
	endif

	if (startClient)
		call s:Execute(a:instruction)
	endif

endfun

fun! s:Execute(instruction)
	exe "silent !start javaw -jar " . s:JarFile . " -v " . v:servername . " " . a:instruction
endfun

" Toggle breakpoint for current line.
fun! s:ToggleBreakpoint()

	if (getline(".") !~ '^\s*\w')
		return "Can't set breakpoint at current line."
	endif

	let className = expand("%:t:r")
	let packageName = FindPackageName('.')
	let breakpoint = packageName . className . ":" . line(".")

	if (has_key(s:BreakpointList, breakpoint))
		call DebugInterpret("clear " . breakpoint)
	else
		call DebugInterpret("stop at " . breakpoint)
	endif

	return ""
endfun

let s:JdbSessionBuffer = -1
let s:JavaSourceBuffer = 1
let s:WindowSize = {}
let s:PotentialLine = ""
" Start outputing the message from jdb.  This is called by the java server.
fun! DebugOutputStart()
	let temp = &scrolloff
	let &scrolloff = 0
	let s:WindowSize = GetWinSize()

	let currentBuffer = bufnr('%')
	if (currentBuffer != s:JdbSessionBuffer)
		let s:JavaSourceBuffer = currentBuffer
	endif

	if (s:JdbSessionBuffer == -1)
		call EditTempFile()
		setlocal textwidth=1000
		" Create a scratch buffer.
		setlocal buftype=nofile
		setlocal bufhidden=hide
		setlocal noswapfile
		exe "f JDB Session" 
		let s:JdbSessionBuffer = bufnr('%')
	endif

	if (BufferInWindow(s:JdbSessionBuffer, 1) == 0)
		exe "sb "
		exe s:JdbSessionBuffer . "buffer"
	endif


	resize 8
	wincmd J

	call RestoreWinSize(s:WindowSize, s:JdbSessionBuffer)
	let &scrolloff = temp

	" move the window to the bottom
	exe "normal! G"

	if (s:IsConsecutive() == 0)
		let s:PotentialLine = ""
	endif
endfun

" Because the read from the jdb command output in the java server can block, and
" cause the output with the pattern '[digit]' to end prematurely.  To reduce
" complexity, we'll handle the broken output in our script, rather than the java
" server.
fun! s:IsConsecutive()
	return s:PotentialLine =~# '^Step completed: .*]$' || s:PotentialLine =~# '^Breakpoint hit: .*]$'
endfun

" Append a line to jdb session buffer
fun! s:DebugOutputAppend(text)
	let lineNumber = line("$")
	if (lineNumber == 1 && getline(".") == "")
		silent! call setline(1, a:text)
	elseif (s:IsConsecutive()) 
		silent! exe "normal! $a " . a:text
	else
		silent! call setline(lineNumber + 1, a:text)
	endif

	" Take care of the situation when s:PotentialLine is split over two cutive a:text.
	if (s:PotentialLine =~# '^Step completed: .*]$')
		let s:PotentialLine = s:PotentialLine . a:text

	elseif (s:PotentialLine =~# '^Breakpoint hit: .*]$')
		let s:PotentialLine = s:PotentialLine . a:text

	elseif (a:text =~# '^Step completed: .*]$')
		let s:PotentialLine = a:text

	elseif (a:text =~# '^Breakpoint hit: .*]$')
		let s:PotentialLine = a:text

	elseif (a:text =~# '^Step completed: ')
		let s:PotentialLine = a:text

	elseif (a:text =~# '^Breakpoint hit: ')
		let s:CanClean = 0
		let s:PotentialLine = a:text
	endif

	" move down one line
	exe "normal! j"
endfun

" After outputing the message from jdb, this function will be called by the java server.
fun! DebugOutputEnd()
	" The output has not finished.
	if (s:IsConsecutive())
		call BufferInWindow(s:JavaSourceBuffer, 1)
		return
	endif

	let deleteLater = ""
	if (s:CanClean == 1)
		let deleteLater = s:FetchJdbCurrentLine()
	endif

	if (strlen(s:PotentialLine) > 0)
		let breakpoint = s:ParseBreakpoint(s:PotentialLine)
		if (breakpoint != "")
			if (deleteLater == "")
				let deleteLater = s:FetchJdbCurrentLine()
			endif
			silent call s:AddBreakpoint(breakpoint, "JdbCurrentLine")
		endif
	endif

	" Do the clean up.
	" TODO use a better strategy for deciding the need to delete JdbCurrentLine.
	if (deleteLater != "" && deleteLater != s:PotentialLine)
		call s:DeleteBreakpoint(deleteLater)
	endif

	let s:CanClean = 0

	call BufferInWindow(s:JavaSourceBuffer, 1)
	if (foldlevel(line('.')) > 0)
		foldopen
	endif
endfun

" Parse a breakpoint from text.
fun! s:ParseBreakpoint(text)
	if (a:text !~ '", ' || a:text !~ 'line=')
 		return ""
	endif

	" Example: Step completed: "thread=http-443-2", baodian.persistence.PersistentObject.fetchServer(), line=390 bci=14 
	let temp = split(a:text, '", ')
	let temp = split(temp[1], ', ')

	let className = substitute(temp[0], '\.<\=\w\+>\=()*$', '', '')
	" trim the inner class name
	let className = substitute(className, '\$.*', '', '')

	let temp = split(temp[1], ' ')
	let lineNumber = substitute(temp[0], 'line=', '', '')
	return className . ':' . lineNumber
endfun

" Get the key that has 'JdbCurrentLine' as the sign name.
" If the no such key exists, then "" is returned.
fun! s:FetchJdbCurrentLine()
	let found = ""
	for key in keys(s:BreakpointList)
		if (s:IsValid(key) == 0)
			continue
		endif

		let signName = s:GetSignName(key)
		if (signName == "JdbCurrentLine" || signName == "JdbBoth")
			let found = key
			break
		endif
	endfor

	" This is a pure JdbCurrentLine not JdbBoth, so we can safely delete it.
	if (found != "" && s:SetSignName(found, "") == 1)
		return found
	endif

	return ""
endfun

" This is for debug purpose
fun! GetBreakpointList()
	return s:BreakpointList
endfun

" This is for debug purpose
fun! GetJdbCurrentLine()
	let found = ""
	for key in keys(s:BreakpointList)
		if (s:BreakpointList[key] == "")
			continue
		endif

		let signName = s:GetSignName(key)
		if (signName == "JdbCurrentLine" || signName == "JdbBoth")
			let found = key
			break
		endif
	endfor

	return found
endfun

" -------------------------------- BreakpointList Operation -----------------------------------

let s:BreakpointFile = "c:/vim/breakpoints.txt"
" save the breakpoints to a file
fun! SaveBreakpoints()
	exe "redir! > " . s:BreakpointFile
	silent echo string(s:BreakpointList)
	redir END
endfun

" load the breakpoints from a file
fun! LoadBreakpoints()
	call EditTempFile()
	exe "read " . s:BreakpointFile
	" The data is on the third line.
	let lines = getbufline(bufnr('%'), 3)[0]
	exe "let s:BreakpointList = " . lines
	bw %

	let s:UsingBreakpoints = 0
	" turn on the breakpoints
	call s:UseBreakpoints(1)
endfun

let s:UsingBreakpoints = 1
" Turn on or off the breakpoints.
fun! s:UseBreakpoints(flag)

	let enable = 0
	let disable = 0

	if (a:flag == 1 && s:UsingBreakpoints == 0)
		let enable = 1
		let s:UsingBreakpoints = 1
	elseif(a:flag == 0 && s:UsingBreakpoints == 1)
		let disable = 1
		let s:UsingBreakpoints = 0
	endif

	"wrong state
	if (enable == 0 && disable == 0)
		return
	endif

	let currentBuffer = bufnr('%')
	for key in sort(keys(s:BreakpointList))
		if (s:IsValid(key) == 0)
			continue
		endif

		if (s:HasPlaceSet(key) == 0)
			continue
		endif

		if (enable)
			call s:EnableBreakpoint(key)
		elseif(disable)
			call s:DisableBreakpoint(key)
		endif
	endfor

	if (BufferInWindow(currentBuffer, 1) == 0)
		if (BufferInWindow(s:JavaSourceBuffer, 1))
			exe currentBuffer . "buffer"
			let s:JavaSourceBuffer = bufnr('%')
		endif
	endif
endfun

" Disable a breakpoint.
fun! s:DisableBreakpoint(key)
	let currentFile = expand("%:p")
	let fileName = s:GetFileName(a:key)
	if (currentFile != fileName)
		call BufferInWindow(s:JavaSourceBuffer, 1)
		exe "e " . fileName
		let s:JavaSourceBuffer = bufnr('%')
	endif

	if (&number == 1)
		setlocal nonumber
	endif

	let placeNumber = s:GetPlaceNumber(a:key)
	let bufferNumber = s:GetBufferNumber(a:key)
	let lineNumber = s:GetNewLineNumber(bufferNumber, placeNumber)

	exe "sign unplace " . placeNumber . " file=" . fileName

	" Update the line line number if needed.
	if (lineNumber != s:GetLineNumber(a:key))
		let className = split(a:key, ':')[0]
		let newKey = className . ':' . lineNumber

		let value = bufferNumber . s:ObjectFieldSeparator .
				  \ s:GetSignName(a:key) . s:ObjectFieldSeparator .
				  \ s:GetFileName(a:key) . s:ObjectFieldSeparator .
				  \ placeNumber . s:ObjectFieldSeparator .
				  \ lineNumber . s:ObjectFieldSeparator .
				  \ s:HasPlaceSet(a:key)

		" delete the old value
		call filter(s:BreakpointList, 'v:key != "' . a:key . '"')
		let s:BreakpointList[newKey] = value
	endif

	call s:Execute("clear " . a:key)
endfun

fun! s:GetNewLineNumber(bufferNumber, placeNumber)

	redir => output
	silent exe "sign place buffer=" . a:bufferNumber
	redir END

	return substitute(output, '.*line=\(\w\+\)  id=\<'.a:placeNumber.'\>.*', '\1', '')
endfun

" Enable a breakpoint.
fun! s:EnableBreakpoint(key)
	let currentFile = expand("%:p")
	let fileName = s:GetFileName(a:key)
	if (currentFile != fileName)
		call BufferInWindow(s:JavaSourceBuffer, 1)
		exe "e " . fileName
		let s:JavaSourceBuffer = bufnr('%')
	endif

	if (&number == 0)
		setlocal number
		hi LineNr term=bold ctermfg=red ctermbg=white gui=bold guifg=red guibg=white 
		redraw
	endif

	" Use a new place number to avoid conflict with the existing signs.
	let placeNumber = s:PlaceNumber
	let s:PlaceNumber = s:PlaceNumber + 1

	exe "sign place " . placeNumber . " line=" . s:GetLineNumber(a:key) . 
				\ " name=" . s:GetSignName(a:key) . " file=" . fileName

	let placeSet = 1
	let value = bufnr('%') . s:ObjectFieldSeparator .
			 \  s:GetSignName(a:key) . s:ObjectFieldSeparator .
			 \  fileName . s:ObjectFieldSeparator .
			 \  placeNumber . s:ObjectFieldSeparator .
			 \  s:GetLineNumber(a:key) . s:ObjectFieldSeparator .
			 \  placeSet
	let s:BreakpointList[a:key] = value

	call s:Position(s:GetLineNumber(a:key))
	call s:Execute("stop at " . a:key)
endfun

let s:BreakpointList = {}
fun! s:AddBreakpoint(key, name)
	if (has_key(s:BreakpointList, a:key))
		" update the a:key
		call s:SetSignName(a:key, a:name)
		return 1
	endif

	let s:BreakpointList[a:key] = s:MakeBreakpointObject(a:key)
	call s:SetSignName(a:key, a:name)
	return 1
endfun

fun! s:DeleteBreakpoint(key)
	if (s:IsValid(a:key) == 0)
		call filter(s:BreakpointList, 'v:key != "' . a:key . '"')
		return 1
	endif

	let fileName = s:GetFileName(a:key)
	let bufferNumber = s:GetBufferNumber(a:key)
	exe "sign unplace " . s:GetPlaceNumber(a:key) . " file=" . fileName
	call filter(s:BreakpointList, 'v:key != "' . a:key . '"')

	let found = 0
	" See if the buffer still has signs.
	for key in keys(s:BreakpointList)
		if (s:IsValid(key) == 0)
			continue
		endif

		if (s:GetFileName(key) == fileName)
			let found = 1
			break
		endif
	endfor

	let current = bufnr('%')
	" Turn off the option 'number'
	if (found == 0)
		if (current == bufferNumber)
			setlocal nonumber
		elseif (BufferInWindow(bufferNumber, 1))
			setlocal nonumber
			call BufferInWindow(current, 1)
		else
			exe bufferNumber . "buffer"
			setlocal nonumber
			exe current . "buffer"
		endif
	endif

	return 1
endfun

let s:CurrentBreakpoint = 0

fun! s:Navigate(direction)
	let length = s:GetLength()
	if (length == 0)
		return
	endif

	let s:CurrentBreakpoint = s:CurrentBreakpoint + a:direction

	if (s:CurrentBreakpoint < 0)
		let s:CurrentBreakpoint = length - 1
	endif

	if (s:CurrentBreakpoint >= length)
		let s:CurrentBreakpoint = 0
	endif

	let counter = 0
	let found = ""
	for key in sort(keys(s:BreakpointList))
		if (s:IsValid(key) == 0)
			continue
		endif

		if (counter == s:CurrentBreakpoint)
			let found = key
			break
		endif

		let signName = s:GetSignName(key)
		if (signName == "JdbBreakpoint" || signName == "JdbBoth")
			let counter = counter + 1
		endif
	endfor

	let currentFile = expand("%:p")
	let fileName = s:GetFileName(found)
	if (currentFile != fileName)
		call BufferInWindow(s:JavaSourceBuffer, 1)
		exe "e " . fileName
		let s:JavaSourceBuffer = bufnr('%')
	endif

	call s:Position(s:GetLineNumber(found))
endfun

fun! s:GetLength()

	let counter = 0
	for key in keys(s:BreakpointList)
		if (s:IsValid(key) == 0)
			continue
		endif

		let signName = s:GetSignName(key)
		if (signName == "JdbBreakpoint" || signName == "JdbBoth")
			let counter = counter + 1
		endif
	endfor
	return counter

endfun

" ------------------------------ BreakpointObject Definition ----------------------------------
let s:PathSeparator = '\\'
let s:PlaceNumber = 1
let s:ObjectFieldSeparator = "@|@"
fun! s:MakeBreakpointObject(key)

	let temp = split(a:key, ':')
	let head = temp[0]
	let lineNumber = temp[1]

	let fileName = ""
	let packageHead = ExtractPackageHead(head)
	if (packageHead == s:PackageHead)
		let fileName = s:PathHead . substitute(head, '\.', s:PathSeparator, 'g') . '.java'
	endif

	if (fileName == "")
		return ""
	endif

	call BufferInWindow(s:JavaSourceBuffer, 1)
	let currentFile = expand("%:p")
	if (currentFile != fileName)
		exe "e " . fileName
	endif

	let placeSet = 0
	let bufferNumber = bufnr('%')
	let s:JavaSourceBuffer = bufferNumber
	let placeNumber = s:PlaceNumber
	let s:PlaceNumber = s:PlaceNumber + 1
	let signName = ""

	return bufferNumber . s:ObjectFieldSeparator .
		\  signName . s:ObjectFieldSeparator .
		\  fileName . s:ObjectFieldSeparator .
		\  placeNumber . s:ObjectFieldSeparator .
		\  lineNumber . s:ObjectFieldSeparator .
		\  placeSet
endfun

fun! s:GetBufferNumber(key)
	return split(s:BreakpointList[a:key], s:ObjectFieldSeparator)[0]
endfun

fun! s:GetSignName(key)
	return split(s:BreakpointList[a:key], s:ObjectFieldSeparator)[1]
endfun

fun! s:GetFileName(key)
	return split(s:BreakpointList[a:key], s:ObjectFieldSeparator)[2]
endfun

fun! s:GetPlaceNumber(key)
	return split(s:BreakpointList[a:key], s:ObjectFieldSeparator)[3]
endfun

fun! s:GetLineNumber(key)
	return split(s:BreakpointList[a:key], s:ObjectFieldSeparator)[4]
endfun

fun! s:HasPlaceSet(key)
	return split(s:BreakpointList[a:key], s:ObjectFieldSeparator)[5] == 1
endfun

fun! s:IsValid(key)
	if (has_key(s:BreakpointList, a:key) == 0 || s:BreakpointList[a:key] == "")
		return 0
	endif

	return 1
endfun

" Set sign name to name for a break point.
fun! s:SetSignName(key, name)

	" has no valid fields or not exist
	if (s:IsValid(a:key) == 0)
		return 0
	endif

	let currentFile = expand("%:p")
	let fileName = s:GetFileName(a:key)
	if (currentFile != fileName)
		call BufferInWindow(s:JavaSourceBuffer, 1)
		exe "e " . fileName
		let s:JavaSourceBuffer = bufnr('%')
	endif

	let signName = a:name
	if (s:HasPlaceSet(a:key))

		let previous = s:GetSignName(a:key)
		if (strlen(a:name) == 0)
			if (previous == "JdbBoth")
				let signName = "JdbBreakpoint"
			else
				return 1
			endif

		elseif (previous == "JdbBreakpoint" && a:name == "JdbCurrentLine")
			let signName = "JdbBoth"

		elseif (previous == "JdbCurrentLine" && a:name == "JdbBreakpoint")
			let signName = "JdbBoth"

		elseif (previous == a:name)
			if (a:name == "JdbCurrentLine")
				call s:Position(s:GetLineNumber(a:key))
			endif
			return 0
		endif

		exe "sign unplace " . s:GetPlaceNumber(a:key) . " file=" . fileName
	endif

	if (&number == 0)
		setlocal number
		hi LineNr term=bold ctermfg=red ctermbg=white gui=bold guifg=red guibg=white 
		redraw
	endif

	exe "sign place " . s:GetPlaceNumber(a:key) . " line=" . s:GetLineNumber(a:key) . 
				\ " name=" . signName . " file=" . fileName

	let placeSet = 1
	let value = s:GetBufferNumber(a:key) . s:ObjectFieldSeparator .
			 \  signName . s:ObjectFieldSeparator .
			 \  fileName . s:ObjectFieldSeparator .
			 \  s:GetPlaceNumber(a:key) . s:ObjectFieldSeparator .
			 \  s:GetLineNumber(a:key) . s:ObjectFieldSeparator .
			 \  placeSet
	let s:BreakpointList[a:key] = value

	if (a:name == "JdbCurrentLine")
		call s:Position(s:GetLineNumber(a:key))
	endif

	return 0

endfun

" Position the cursor to the given line
fun! s:Position(line)
	let line = str2nr(a:line)
	exe line
	if (foldlevel(line) > 0)
		foldopen
	endif
endfun
