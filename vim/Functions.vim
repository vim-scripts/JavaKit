if exists("FunctionsSourced")
	finish
endif 
let FunctionsSourced = "true"

"============== File Utilites ============== 
fun! GetTempPath()
	let tempFile = tempname()

	if (has("win32"))
		let tempPath = substitute(tempFile, '\(.*\\\)\(.*\)', '\1', '')
	else
		let tempPath = substitute(tempFile, '\(.*/\)\(.*\)', '\1', '')
	endif

	return tempPath
endfun

" Function: Split edit the tempFile and set the needed options
fun! EditTempFile()
	" Split open a window to edit the tempFile.
	" The file name is '_' which can avoid redrawing too much title string.
	exe "silent split _"
    setlocal noswapfile
	setlocal nobuflisted
	setlocal autoread
	" setlocal autowrite
	setlocal buftype=nowrite
	setlocal bufhidden=delete
endfun

"============== Search Utilites ============== 

" Find out how many pats are in the current file
fun! Count(pat)
	" mark where the curson is at the moment
	let cur = line(".")
	let pos = line2byte(cur) + col(".")

	" find the matches
	let num = 0
	silent execute 'g/' . a:pat . '/let num = num + 1'

	"get back excatly where the cursor was
	let pos = pos - 1
	exec "normal!" . pos . "go"

  return num
endfun

" command -nargs=+ -complete=command Count let ct = Count(<q-args>) | echo ct

" Find out how many items are there in string, add one more paratmeter to get
" the exact counts of item in string.  The actual value passed to the third
" paratemter is not important.  When we want to traverse through an delimter
" separated array, we might want to use two paratemters only so that we always
" can get the remaining bit in the string. 
" Example: When the third parameter is given, 
"          ItemCounts('this.parent.', '\.') returns 3,
"          ItemCounts('this.parent.something', '\.') returns 3 as well,
"          but ItemCounts('this.parent.something', '\.', '') returns 2 only
"          because there are only two '.' in the given string.
"          If the item is not found at all then it'll awalys return 0, whether
"          it's given two or three parameters.
"          ItemCounts('this.parent.', 'xx') returns 0,
"          ItemCounts('this.parent.', 'xx', '') returns 0, too.
fun! ItemCounts(string, item, ...)
	let temp = a:string
	let counter = 0

	" We can break out from the loop in its body
	while 1 != 0
		let i = matchend(temp, a:item)

		if (i == -1)
			break
		else
			let temp = strpart(temp, i, strlen(temp) - i)
			let counter = counter + 1
		endif

	endwhile

	" Add the counting to one more if only two parameters are given.
	if (matchend(a:string, a:item) && a:0 == 0)
		return counter + 1
	else
		return counter
	endif

endfun

" Get the last item in string, which is separated by delimter.
" If the delimter is not in the string then the whole string is returned.
" For example, GetLastItem('hello/world', '/') will return 'world'
fun! GetLastItem(string, delimiter)
	let temp = a:string

	" We can break out from the endless loop in its body
	while 1 != 0
		let i = matchend(temp, a:delimiter)

		if i == -1
			return temp " The last item is found
		else
			let temp = strpart(temp, i, strlen(temp) - i)
		endif
	endwhile
endfun

" Get the item in the string, which is delimited by the delimiter, index is the
" index for the item - starting from 0.  If the index or delimiter don't exist,
" then an empty string "" will be returned.
fun! GetItem(string, delimiter, index)
	if (a:index < 0)
		return 0
	endif

	let temp = a:string
	let counter = 0
	let delimiterExists = 0

	while counter <= a:index
		let i = match(temp, a:delimiter)

		" Delimiter doesn't exist now
		if (i == -1)
			" This for the last item which is not followed by a delimiter
			if (delimiterExists == 1 && counter == a:index)
				return temp
			else
				return ""
			endif
		endif

		" i is > -1, so the delimiter exists in the string
		let delimiterExists = 1

		" Found it.
		if (a:index == counter)
			return strpart(temp, 0, i)
		endif

		let counter = counter + 1
		" Trim off the previous value and the delimiter for temp.
		let temp = strpart(temp, i + strlen(matchstr(temp, a:delimiter)))
	endwhile

endfun

" Function: Search a pattern starting from the given line.
" Paratmeter: start The start point for the search.
" Paratmeter: pattern The pattern to look for in the search.
" Paratmeter: direction The direction of the search, forward or backward.
fun! s:Search(start, pattern, direction)
	let lineNum = a:start
	if (a:direction == "forward")
		let end = line("$")
		while (lineNum <= end)
			if (match(getline(lineNum), a:pattern) != -1)
				return lineNum
			endif
			let lineNum = lineNum + 1
		endwhile

	else
		while (lineNum >= 1)
			if (match(getline(lineNum), a:pattern) != -1)
				return lineNum
			endif	 
			let lineNum = lineNum - 1
		endwhile

	endif

endfun

" Function: Put the value associated with the key into the store, if the key
" is already exist then the new value will replace the old one.
" Return: The new value for the store.
fun! Hashtable_put(key, value, store)
	if (Hashtable_exist(a:key, a:store))
		" Assign the new value to key.
		return substitute(a:store, 
					\ '\(.*'.a:key.'\)[^]*\(.*\)\=',
					\ '\1' . a:value . '\2', '')
	endif

	return '' . a:key . '' . a:value . a:store
endfun

" Test if the key exists in store. 1 if the key exists
" or 0 if the key doesn't exist.
fun! Hashtable_exist(key, store)
	return ItemCounts(a:store, ''.a:key.'', 'exact') > 0
endfun

" Before calling this function, the caller can check
" if the key exists or not by calling Hashtable_exist
" Get the value associated with key in store.
fun! Hashtable_get(key, store)
	if (Hashtable_exist(a:key, a:store) == 0)
		echoerr "key " . a:key . " doesn't exist in store " . a:store
	endif

	let temp = GetItem(a:store, ''.a:key, 1)
	" Trim off the words behind 
	if (ItemCounts(temp, '', 'exact') > 0)
		let temp = GetItem(temp, '', 0)
	endif

	return GetItem(temp, '', 1)
endfun

" ================ Window Utilities ===================

" Function: Go to the window specify by the windowNum
" if the windowNum is not present, then stay in the original window 
fun! GoToWindow(windowNum)
	let start = winnr()
	while (winnr() != a:windowNum )
		wincmd w

		if (winnr() == start)
			break
		endif
	endwhile
endfun

" Show the window from the begin line to the final line inclusively.
" If the final line is earlier than the begin line, 
" then keep the current window as it is
fun! SetViewport(begin, final)
	
	" Scroll off can changed the number of lines that have been scrolled.
	let scrolloff = &scrolloff
	set scrolloff=0

	if (a:final > a:begin )

		let lines = a:final - a:begin + 1
		
		" Test the the wrap option which might wrap the physical line that's longer
		" than the textwidth into multiple screen lines
		if (&wrap == 1)
			let i = 0
			let winHeight = 0
			let winWidth = winwidth(0)
			" In case the line is longer that the window width, so compute the number of
			" screen lines there should be.
			while (i < lines)
				let winHeight = strlen(getline(a:begin + i)) / winWidth + 1 + winHeight
				let i = i + 1
			endwhile
		
		else
			let winHeight = lines
		endif

		if (winheight(0) != winHeight)
			exe "silent  resize " . winHeight
		endif

	else
		exe "set scrolloff=" . scrolloff
		return
	endif

	" go to the begin line first
	exe a:begin
	let numScrollDowns = winline() - 1
	if (numScrollDowns != 0)
		exe "normal! L"
		exe "normal! " . numScrollDowns . "j"
	endif

	" Go to the last line of the scrollable line only when the current line is
	" greater than the scrolloff boundry,
	" but this is a hack
	if (winheight(0) - winline() + 1 == &scrolloff)
		exe "normal! 2j"
		exe "normal! 2k"
	endif

	exe "set scrolloff=" . scrolloff
endfun

" Function: Test if the file with the fileName is in one of the open window.
" Parameter: fileName the name of the file.
" Parameter: jump 1 for , if possible, going to the window where the fileName
" exists, otherwise site it 0 for remaing at the same window.
" Return: return 0 if the file is not in the window
" or the winnr for the file is turned
fun! FileInWindow(fileName, jump)

  let start = winnr()
	" Do an early check.
	if (bufname(winbufnr(start)) ==# a:fileName)
		return start
	endif

	wincmd w
  let current = winnr()

	" There's only one open window and it can't match a:fileName, because early
	" check has already done that.
	if (current == start)
			return 0
	endif

	while (current != start )
		if (strlen(a:fileName) != 0)
			if (bufname(winbufnr(current)) ==# a:fileName)
				if (a:jump == 0)
					call GoToWindow(start)
				endif
				return current " Found.
			endif
		endif

		wincmd w
		let current = winnr()
	endwhile

	call GoToWindow(start)
	return 0 " Not found.
endfun

" Function: Test if the buffer with buffer number buffNum is in one of the open
" windows.
" Parameter: buffNum the buffer number, can be obtained with bufnr()
" Parameter: jump 1 for , if possible, going to the window where the fileName
" exists, otherwise site it 0 for remaing at the same window.
" Return: winnr for the buffer, or 0 when buffNum doesn't exist in the open
" windows.
fun! BufferInWindow(buffNum, jump)
	" Buffer numbers have value smaller than 0.
	if (a:buffNum < 0)
		return 0
	endif

	let start = winnr()
	" Do an early check
	if (winbufnr("%") == a:buffNum)
		return start
	endif

	wincmd w
	let current = winnr()

	" There's only one open window and it can't match a:fileName, 
	" because early check has already done that.
	if (current == start)
		return 0
	endif

	while (current != start)
		if (winbufnr("%") == a:buffNum)
			if (a:jump == 0)
				call GoToWindow(start)
			endif
			return current " Found.
		endif
		
		wincmd w
		let current = winnr()
	endwhile

	call GoToWindow(start)
	return 0 " Not found.

endfun

" Function: Execute a function (typically it has side-effects such as changing
" the cursor position, size of the window, etc.) in a way that the cursor position
" will remain the same.
" Parameter: fnt the name of the function
" Parameter: ... the parameters for the function, the caller may not supply it.
" Return: the return value of fnt.
" Note: This is only restores the current window, the view port for other
" windows maybe effeceted by the execution of a:fnt, but their settings are not
" restored.
fun! StandShot(fnt, ...)

	let counter = 1
	let arguments = ""
	while counter <= a:0
		if (counter < a:0)
			exe "let arguments = arguments . \"'\" . a:" . counter . ". \"',\" . \" \""
		else " Drop the comma
			exe "let arguments = arguments . \"'\" . a:" . counter . ". \"'\" . \" \""
		endif
		let counter = counter + 1
	endwhile

	" Mark where the curson is at the moment
	let cur = line(".")
	let pos = line2byte(cur) + col(".")

	" Get the line numbers on the screen.
	let screenLine = winline()

	" Save the current winnr(), so that we can go back to it.
	let winNum = winnr()
	let width = winwidth(0)
	let height = winheight(0)
	let winSize = GetWinSize()

	let retVal = ""
	exe "let retVal = " . a:fnt. "(" . arguments .")"

	call RestoreWindow(winNum, width, height)
	" call RestoreWinSize(winSize, winNum)

	" Restore cursor position
	let pos = pos - 1
	exe "normal!" . pos . "go"

	" Restore screen line positoin
	let oldScroll = &scroll
	set scroll=0

	let offSet = winline() - screenLine
	" Should move up
	if (offSet > 0)
		exe "normal!" . offSet . "\<C-E>"
	elseif (offSet < 0)
		let offSet = offSet * -1
		exe "normal!" . offSet . "\<C-Y>"
	endif

	exe "set scroll=".oldScroll

	return retVal

endfun

" Function: Go to the winNum, and set its size to 
" the corresponding width and height.
fun! RestoreWindow(winNum, width, height)

	call GoToWindow(a:winNum)
	" Restore the old window's size.
	" However, this might affect the sizes of other windows.
	exe "vertical resize " . a:width
	exe "resize " . a:height

endfun

" Function: Get the windows size.
fun! GetWinSize()
	let winSize = {}
	let oldWindow = winnr()
	let winSize[oldWindow] = ''

	while (1 != 0)
		wincmd w
		let current = winnr()

		if (current == oldWindow)
			break
		endif

		let winSize[current] = winheight(current) . " " . winwidth(current)
	endwhile

	return winSize
endfun

" Function: Restore the windows size accoding to winSize.
" Parameter: bufJump pass 0 to jump to the starting window, or a number for the buffer window.
fun! RestoreWinSize(winSize, bufJump)
	if (len(a:winSize) == 1)
		return
	endif

	let biggest = 0
	let start = 0
	for key in keys(a:winSize)
		if (key > biggest)
			let biggest = key
		endif

		if (a:winSize[key] == '')
			let start = key
		endif
	endfor

	" no window was open
	let offSet = 0
	if (winbufnr(biggest) == -1)
		let offSet = -1
	else
		while (winbufnr(biggest + offSet + 1) != -1)
			let offSet = offSet + 1
		endwhile
	endif

	for [key, value] in items(a:winSize)
		if (value != '')
			let winNum = key
			if (winNum > start)
				let winNum = winNum + offSet
			endif

			call GoToWindow(winNum)
			let size = split(value, ' ')
			exe "resize " . size[0]
			exe "vertical resize " . size[1]
		endif
	endfor

	if (a:bufJump == 0)
		call GoToWindow(start + offSet)
	else
		call BufferInWindow(a:bufJump, 1)
	endif

endfun

" ***************** Client&Server *********************
" Function: Ask a server to execute an expression. This is different from
" remote_expr in that this function can take function calls in the expression.
" Parameter: serever the name of the server, can be obtained through
" serverlist().
" Parameter: exp the exp to be excecuted. Or it can be anything that the
" ":echo " command can take.  However, if the expression isn't valid then the
" call to this function can be blocked.  A good way to test if fnt will work is
" do a ":echo exp"
" Return: The output of expression.
" Example: :echo RemoteExecute("GVIM2", "tempname()")
fun! RemoteExecute(server, exp)
	" If the server is local vim then execute on there.
	if (a:server =~# '^'.v:servername.'$')
		let temp = ""
		exe "let temp = " . a:exp
		return temp
	endif

	return remote_send(a:server, 
									\"<esc>:call histdel(':', -1)|silent echo ".
									\'server2client(expand("<client>"), ' . a:exp . ')<CR><C-L>',
									\"serverid").remote_read(serverid)
endfun

" Function: Invoke a function on a sever.
" Parameter: sever the name of the server.
" Parameter: fnt the function to be executed remotely.
" Parameter: ... the argument that fnt takes, and it may be ommitted.
" Return: Whatever the function fnt returns.
fun! RemoteFunction(server, fnt, ...)
	if (RemoteExecute(a:server, 'exists("*'.a:fnt.'")') != 0)
		let counter = 1
		let arguments = ""
		while counter <= a:0
			if (counter < a:0)
				exe "let arguments = arguments . \"'\" . a:" . counter . ". \"',\" . \" \""
			else " Drop the comma
				exe "let arguments = arguments . \"'\" . a:" . counter . ". \"'\" . \" \""
			endif
			let counter = counter + 1
		endwhile

		return RemoteExecute(a:server, a:fnt.'('.arguments.')')
	else
		return "" "Maybe we should echo some error message here.
	endif
endfun

" =================System Utils===================
" Function: Make a new directory for the given name.
" Parameter: name The name for the directory.  It can be have vaules such as
" temp/test, if temp doesn't exist it'll be created as well.
" Parameter: pathSeparator The char to separate the path.
" Return: The value of isdirectory(name).
fun! Mkdir(name, pathSeparator)

	if (has("win32"))
		let path = substitute(a:name, a:pathSeparator, '\\', 'g')
		call system('mkdir ' . '"' . path . '"')
	else
		"TODO check if this valid in bash.
		let path = substitute(a:name, a:pathSeparator, '/', 'g')
		call system('mkdir ' . path)
	endif

	return isdirectory(path)
endfun

" ============== Cool Stuff ============== 
fun! GenerateAlphabet()
	let i = 0
	while i < 26
		s/$/\=nr2char(97 + i)/
		let i = i + 1
	endwhile
endfun

fun! ReverseLine(str)
   if strlen(a:str) <= 1
      return a:str
   else
      let l:len = strlen(a:str)-1
      return a:str[l:len] . ReverseLine(strpart(a:str, 0, l:len))
   endif
endfunction

command! RevLine call setline(line("."), ReverseLine(getline(".")))

let s:smartindent = ""
let s:cindent     = ""
let s:autoindent  = ""
let s:indentexpr  = ""
let s:textwidth   = ""
function! SetUpInsertion()
	let s:smartindent = &smartindent
	let s:cindent     = &cindent
	let s:autoindent  = &autoindent
	let s:indentexpr  = &indentexpr
	let s:textwidth   = &textwidth

	let &smartindent = 0
	let &cindent     = 0
	let &autoindent  = 0
	let &indentexpr  = ""
	let &textwidth   = 1000
endfunction

function! TearDownInsertion()
	let &smartindent = s:smartindent
	let &cindent     = s:cindent
	let &autoindent  = s:autoindent
	let &indentexpr  = s:indentexpr
	let &textwidth   = s:textwidth
endfunction
