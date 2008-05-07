if exists("JavaSearchSourced")
	finish
endif 
let JavaSearchSourced = "true"

exe "so " . g:VIMMACROSPATH . "Javadoc.vim"
exe "so " . g:VIMMACROSPATH . "Functions.vim"
exe "so " . g:VIMMACROSPATH . "JavaUtil.vim"

nmap <silent> gm :call <SID>SearchMethodHead(1)<cr>
nmap <silent> gc :call <SID>SearchClassHead(1)<cr>
nmap <silent> gd :call <SID>VariableDecl(1, 0, 1)<cr>
nmap <silent> gi :call <SID>VariableDecl(1, 1, 1)<cr>

" Set s:debug to 1 to debug all the main features,
" 2 to debug completion, or 3 to debug s:VariableDecl
let s:debug = 0
let s:DEBUG_ALL = 1
let s:COMPLETION = 2
let s:VARIABLE_DECL = 3

" ~~~~~~~~~~~~~~~~~~~~~~~~ Patterns ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" This is the pattern that excludes most of the C or C++ comments, 
" and being not trailed behind by a " (double quote)
let s:EXCLUDE = '\(\(^\s*\*\|/[/*]\|"\).*\)\@<!'

" Pattern for matching a method.
let s:METHOD_BEAR = '\(\<\(new\>\|else\>\|return\>\)\@!\&\h\i*\s\+\)' . 
					\ '\@<=\h\i*\_s\{-}(\_[^)]*)\_s\{-}[{[:alpha:]]'
let s:METHOD = s:EXCLUDE . s:METHOD_BEAR

" Pattern for matching a constructor.
let s:CONSTRUCTOR = '\(^\s*\(public\|protected\|private\)\=\s*\)' . 
					\ '\@<=\C\u\h\i*\_s*(\_[^)]*)\_s*[{[:alpha:]]'

" Pattern for matching a normal class
let s:NORMAL_CLASS_BEAR = '\(\<\Cclass\>\_s\+\)\@<=\C\u\h\i*\_s\+\({\_s*}\)\@!'
let s:NORMAL_CLASS = s:EXCLUDE . s:NORMAL_CLASS_BEAR

" Pattern for matched an anonymous class
let s:ANONYMOUS_CLASS = s:EXCLUDE . '\(\(\s*\|(\_[^)]*\)\C\<new\>\s\+\)\@<=\C\u\h\i*(\_[^)]*)\_s*{'
  
" ~~~~~~~~~~~~~~~~~~~~ End Patterns ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Function: Go to the declaration of current method or constructor.
"
" Return: 	The line number from where the method head was found, or -1 if the
" 			matched line is on the current line; return 0 if the current line is
" 			not inside a method block, or when the match can't be found.
"
" Bug: 		If the cursor is a class's field that without a scope modifier, then the
" 		 	search will go to a random method.
fun! s:SearchMethodHead(restore)
	" This line is for a class.
	let lineContent = getline(".")
	if (lineContent =~ s:NORMAL_CLASS)
		return 0
	endif

	" This is probably a field
	if (lineContent =~ '\(^\s*\(public\|protected\|private\)\s*\).*;\s*$')
			return 0 
	endif

	if (a:restore == 1)
		exe "normal!m`"
	endif
	let pos = line2byte(line(".")) + col(".") - 1

	let before = line(".")
	let indentation = cindent(".")

	" Concatenating the lines together so that we can test if the match is on the
	" current line
	let lineNum = before
	let line = ""
	while (lineNum <= line("$"))
		let current = getline(lineNum)

		" Don't let these keywords get in the way.
		if (current =~ s:EXCLUDE . '\<\(if\|for\|while\|do\)\>')
			break
		endif

		let line = line . current
		" Take the lines up to before the current statement breaks. 
		if (current =~# s:EXCLUDE . '[;{}]')
			break
		endif	 
		let lineNum = lineNum + 1
	endwhile
	" The match is on the current line
	if (line =~# s:CONSTRUCTOR || line =~# s:METHOD)
		return -1
	endif

	let constructor =  s:SearchBackward(s:CONSTRUCTOR)
	" Go back to where we started.  Don't use 'exe "normal!" . pos . "go"',
	" because that would cause a mark to be set.
	exe before

	" The extra indentaion that expected from the method head.
	let extra = &tabstop
	" Don't ask for more indetation if the current line is ended 
	" with either a { or }
	if (line =~ s:EXCLUDE . '[{}]\s*$')
		let extra = 0
	endif

	" Find out the location for the above class.
	let normalClass = s:SearchBackward(s:NORMAL_CLASS)
	exe before

	let method = 1
	while (method != 0 )
		let method = s:SearchBackward(s:METHOD)
		" Found the method head
		if (indentation >= cindent(".") + extra)
			break
		endif
	endwhile

	" Not inside a method block.
	if (normalClass >= method)
		if (a:restore == 1)
			exe "normal!" . pos . "go"
		else
			exe before
		endif
		return 0
	endif

	" Not inside a method block.
	if (a:restore == 1 && (indentation < cindent(".") + extra))
		exe "normal!" . pos . "go"
		return 0
	endif

	" Choose the nearest constructor or method.
	if (method != 0 && method > constructor)
		return method
	elseif (constructor > 0)
		exe before
		call s:SearchBackward(s:CONSTRUCTOR)
		return constructor
	else
		" not found
		if (a:restore == 1)
			exe "normal!" . pos . "go"
		endif
		return 0
	endif

endfun

" Function: Go to the declaration of current class.
"
" Bug: 		If the cursor is a class's field that without a scope modifier, then the
" 		 	search will go to a random class head.
fun! s:SearchClassHead(restore)

	if (a:restore == 1)
		exe "normal!m`"
	endif
	let pos = line2byte(line(".")) + col(".") - 1

	let first = cindent('.')

	" Search for the nearest anonymous class
	let pos1 = 0
	let line1 = line(".")
	" Have the initial line only upto where the cursor stops.
	let uptoCursor = strpart(getline("."), 0, col("."))
	let lines = uptoCursor
	let anonymousLine = 0
	let searchPair = 0
	if (s:SearchAnonymous(0))
		let line2 = line(".")
		let temp = line1

		if (temp >= line2)

			let temp = line1 - 1
			" concatenate the inbetween lines together
			while (temp >= line2)
				let lines = getline(temp) . lines
				let temp = temp - 1
			endwhile

			let klass = matchend(lines, s:NORMAL_CLASS_BEAR)
			let method = 0
			" Get the index in lines for the last method
			let counts = ItemCounts(lines, s:METHOD_BEAR, '')
			let lastMethod = ""
			if (counts > 0)
				let lastMethod = GetItem(lines, s:METHOD_BEAR, counts - 1)
				let method = strridx(lines, lastMethod)
			endif

			" The cursor is on the first { of method
			if (klass != -1 || lines =~ s:METHOD_BEAR . '\s*$')
				" if (method > klass || lines =~ '\Cclass\s\+\(\(\w\+\|,\)\_s\+\)\+{\s*$')
				if (method > klass)
					let searchPair = 1
				endif

			elseif(lines =~ '.\{-})\s*{\(\s*$\|{\(.\{-}};\)\@!\)')
				return line(".")

			elseif (uptoCursor =~ '{\s*$')
				let searchPair = 1
			endif

		endif
	endif
	" go back to the place before searching anonymous class
	exe line1

	" Have to go to the method head for the next line to work correctly.
	let methodLine = s:SearchMethodHead(0)
	let before = cindent('.')

	" This line will let us go to the '{' for the class declaration.
	" Note: If any of the in between comment string contains 
	" a dangling { or } can cause this seach to fail.
	if (uptoCursor !~ '{\s*$' || searchPair == 1)
		call searchpair('{', '', '}', 'bW')
	endif
	let curlyBrace = line(".")

	" Test if we're in an anonymous class.
	call s:SearchAnonymous(0)
	let after = cindent('.')
	if (before == after + &tabstop && getline(".") =~# 'new' &&
				\ after < first)
		return line(".")
	endif

	" Failed the anonymous class so go back to the curly brace.
	exe curlyBrace

	" Failed to match a anonymous class, no match a normal class
	let result = s:SearchBackward(s:NORMAL_CLASS)
	if (result == 0 && a:restore == 1)
		exe "normal!" . pos . "go"
	endif

	return result
endfun

" Function: Go to the declaration of current anonymous class.
fun! s:SearchAnonymous(restore)
	if (a:restore == 1)
		exe "normal!m`"
	endif
	let pos = line2byte(line(".")) + col(".") - 1

	let result = s:SearchBackward(s:ANONYMOUS_CLASS)
	if (result == 0 && a:restore == 1)
		exe "normal!" . pos . "go"
	endif

	return result
endfun

" Function: Find the declaration for the variable that's under the cursor
" 			currently.
"
" Param: 	smartCursor If this flag is set to 1 and the search is not found
" 			then the cursor will return to where the search started. If the
" 			search is found then the cursor will be on the matched pattern.  Set
" 			it 0 if we don't care about the cusor position.
"
" Param: 	init Set it to 1 to find the initialisation line instead of the
" 		   	declaration line.  For exmaple when we don't want to find the line
" 		   	"Object obj;" which declares "obj", but we want to find in the line
" 		   	"obj = new HashTable()".  If we can't find the initialisation line,
" 		   	then a second attempt will be made to find the declaration.
"
" Param: 	premitive Set this value to 1 to allow matching premitive data
" 			type declarations; set it to 0 to disallow such match.
"
" Param: 	... This additional paratmeter is for search a word with the name,
" 			so we're not checking '<cword>', but the cursor still needs to be at
" 			the line where a:1 locates.
"
" Return: 	The line number for where the declaration or initialisation is found,
" 			otherwise 0 is returned.
fun! s:VariableDecl(smartCursor, init, premitive, ...)
	" Store current cusor position so we can get back to it later.
	if (a:smartCursor == 1)
		exe "normal!m'"
		let pos = line2byte(line(".")) + col(".") - 1
	endif

	" Check if the user wants to match premitive data types.  s:UpperCase is only
	" used in s:GetInit and s:GetDecl but not directly in this function.
	if (a:premitive == 1)
		let s:UpperCase = ''
	else
		let s:UpperCase = '\C\u'
	endif

	if (a:0 > 0)
		let name = a:1
	else
		let name = expand("<cword>")
	endif

	" Don't continue if the current word begins only with an uppercase,
	" or its trailed by a (, or it's being referring to as a member
	" for some objects such as when the current current word is on
	" the 'out' of 'System.out'
	let line = getline(".")
	if (name[0] =~# '\u'  && name !~# '^\(\u\|_\)\+$'
			\ || line =~# '\<'.name.'\>\s*(' 
			\ || line =~# '\(this\)\@<!\.\<'.name.'\>')

		if (s:debug == s:DEBUG_ALL || s:debug == s:VARIABLE_DECL)
			echoerr "Unsatisfied word: " . name
		endif

		return 0
	endif

	" The lower bound of the search range in which the declaration of a
	" java variable will be found.
	let bottom = line(".")
	" Use indent level to determine the upper bound.
	let currentIndent = cindent(bottom)

	" The cursor is on an instance variable which has the name as 'this.xxxx'
	if (match(getline("."), 'this\.\<\C' . name . '\>') < col(".")
				\ && col(".") < matchend(getline("."), 'this\.\<\C' . name . '\>'))
		call s:SearchMethodHead(0)
		let result = s:InstanceVariableDecl(name, a:init)
	else
		let method = s:SearchMethodHead(0)
		let methodIndent = cindent(method)

		" 1. The cursor is on a method head.
		if (method == -1)
			" let result = s:MethodVariableDecl(bottom, name, a:init)
			" echoerr line(".")
			let result = line(".")

		" 2. The cusor is on an instance variable 
		" and it's outside the method definition.
		elseif (method == 0 || currentIndent <= methodIndent)
			let result =  s:InstanceVariableDecl(name, a:init)

		" 3. The cursor is inside the method definition.  It can
		" be on a method variable or an instance variable.
		else
			let result = s:MethodVariableDecl(bottom, name, a:init)
			if (s:debug == s:DEBUG_ALL || s:debug == s:VARIABLE_DECL)
				echoerr 's:MethodVariableDecl return value: ' . result
			endif

			if (result == 0)
				let result =  s:InstanceVariableDecl(name, a:init)
				if (s:debug == s:DEBUG_ALL || s:debug == s:VARIABLE_DECL)
					echoerr 's:InstanceVariableDecl return value: ' . result
				endif

			endif

		endif

	endif

	if (a:smartCursor == 1)
		if (result == 0)
			exe "normal!" . pos . "go"
		elseif (result != line("."))
			exe result
		endif

		" Go to the current position
		if (expand("<cword>") !~# name)
			call search('\C\<'.name.'\>', '')
		endif
	endif

	return result

endfun

" Function: Try to find the declaration for name inside a method block.
"
" Return: 	Non-zero value for the line number that has the initialisation.
fun! s:MethodVariableDecl(lineNum, name, init)
	let anonymousIndent = cindent(s:SearchAnonymous(0))
	if (cindent(".") < anonymousIndent || anonymousIndent <= 0)
		let top = line(".")
	else
		let top = s:SearchMethodHead(0)
	endif

	let declaration = 0
	let initialisation = 0
	let lineNum = a:lineNum
	while (lineNum >= top)
		let line = getline(lineNum)

		let pattern = s:GetInit(a:name)
		if (line =~# pattern && IsStatement(match(line, pattern), lineNum))
			let initialisation = lineNum
			if (a:init == 1)
				break " Found it.
			endif
		endif

		let pattern = s:GetDecl(a:name)
		if (line =~# pattern && IsStatement(match(line, pattern), lineNum))
			let declaration = lineNum
			break " Found it.
		endif

		let lineNum = lineNum - 1
	endwhile

	if (initialisation == 0 || a:init == 0)
		return declaration
	else
		return initialisation
	endif

endfun

" Function: Find the instance variable with name.
"
" Precon: 	The cursor has to be on the current method head.
"
" Return: 	Non-zero value for the line number that has the initialisation.
fun! s:InstanceVariableDecl(name, init)
	let beforeSearch = line(".")

	while (1)
		" This will jump to the '{' just after the class declaration.
		" start's indentation level = (instance variable indentation) - &tabstop
		" Note: If any of the in between comment string contains 
		" a dangling { or } can cause this seach to fail.
		let start = searchpair('{', '', '}', 'bW')
		if (beforeSearch == line("."))
			if (s:debug == s:VARIABLE_DECL || s:debug == s:DEBUG_ALL)
				echoerr 'Search ended in s:InstanceVariableDecl ' .
							\ 'start: ' . start . ' beforeSearch: ' . beforeSearch
			endif
			return 0 " We've already checked the out-most class level.
		endif

		let beforeSearch = line(".")
		" Note: If any of the in between comment string contains 
		" a dangling { or } can cause this seach to fail.
		" let end = searchpair('{', '', '}', 'nW', 'getline(".") =~ "//.*}"')
		let end = searchpair('{', '', '}', 'nW')
		let instanceIndent = cindent(start) + &tabstop

		" The maximum indent level before giving up the search.
		let max = 1
		if (a:init == 1)
			let pattern =  s:GetInit(a:name)
			let max = 5 " Initialisation sometimes have a deeper indent level
		else
			let pattern = s:GetDecl(a:name)
		endif

		" Do a search for the instance identifier's initialisation or declaration.
		let counter = 0
		let result = 0
		while (result == 0 && counter < max)
			" Increase the indent level each time when look for the initialisation or
			" declaration.
			let result = s:Loop(start, end, pattern, instanceIndent + &tabstop*counter)
			" Get back to the same start position for the next search.
			exe start
			let counter = counter + 1
		endwhile

		" If the initialisation is not found, then try to find the declaration.
		if (result == 0 && a:init == 1)
			let result = s:Loop(start, end, s:GetDecl(a:name), instanceIndent)
			if (result > 0)
				return result
			endif
		elseif (result > 0)
			return result
		endif

		exe beforeSearch
	endwhile

endfun

" Function: This is the loop that find a instance variable.  It's a hand off from InstanceVariableDecl.
fun! s:Loop(start, end, pattern, instanceIndent)
	while (1)
		let lineNum = search(a:pattern, 'W')
		if (lineNum > a:end || lineNum == 0)
			if (s:debug == s:VARIABLE_DECL || s:debug == s:DEBUG_ALL)
				echoerr 'Pattern ' . a:pattern . ' not found in s:Loop. ' . 
							\ 'Start:' . a:start . ' End:' . a:end
			endif

			return 0 " Not found.
		endif

		" Check if pattern is at the same indent level and also make sure it's not a
		" method parameter.
		if (cindent(lineNum) == a:instanceIndent && s:SearchMethodHead(0) != -1)
			if (IsStatement(match(getline(lineNum), a:pattern), lineNum))
				return lineNum

			else
				if (s:debug == s:VARIABLE_DECL || s:debug == s:DEBUG_ALL)
					echoerr 'Pattern ' . a:pattern . ' found inside comment string'
				endif

			endif
		endif

		if (line(".") == a:start)
			if (s:debug == s:VARIABLE_DECL || s:debug == s:DEBUG_ALL)
				echoerr 'Pattern ' . a:pattern . ' not found in s:Loop'
			endif

			return 0 " Not found
		endif
	endwhile

endfun

" Function: Get the pattern that matches the initialisation for a variable.
fun! s:GetInit(name)
	return s:EXCLUDE . '\<' . a:name . '\>\s*=\s\+new\s\+'
				\ . s:UpperCase . '\h\i*\s*\(<\s*\i\+\s*\(,.*\)*>\)\=\s*[[(]'
endfun

" Function: Get the pattern that matches the declaration for a variable.
fun! s:GetDecl(name)
	" Match 'String[] str', 'String str[]', 'String str', 'List<String> strings' etc.
	return s:EXCLUDE . '\<\(return\>\|assert\>\)\@!\&\(\s*\[\s*\]\)\=' . s:UpperCase
				\ . '\h\i*\(\s*\[\s*\]\)\=\(<\s*\i\+\s*\(,.*\)*>\)\=\s\+\C\<' . a:name .'\>'
endfun

" Function: Search a pattorn backward, if the pattern is in a C or C++
" 			comments then it'll be skipped.
"
" Parame: 	pattern The pattern to be searched for.
"
" Return: 	The line number where the pattern is matched, as a side effect
" 			the cursor will be placed on the matched pattern. 0 for not matching
" 			the pattern, and the cursor will remain at the same place.
fun! s:SearchBackward(pattern)
	let result = search(a:pattern, 'bW')

	if (result == 0)
		return result
	endif

	if (IsStatement(col("."), line(".")) == 0)
		return s:SearchBackward(a:pattern)
	endif

	return result
endfun

"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"~	  	     	 	   			 Start of Completion                                ~
"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Set it to 1 to use vim built-in normal command to find the declaration for the
" current identifier; or set it 0 to use our own function to do the same chore.
let s:UseBuiltIn = 0

" Move the previous completion to the front, so the previous completion will
" be the first one to be looked up when the next search begins.
" 1 to enable this feature, 0 to disable it.
let s:MovePreviousFront = 1

" Use <c-r>= in the keymap to avoid redrawing the screen 
" while doing all the hard work.
" Go to next completion.
inoremap <silent> <c-n> <c-r>=<SID>Z(1)<cr>
" Go to previous completion.
inoremap <silent> <c-l> <c-r>=<SID>Z(0)<cr>

" A short name can help achieve minimum redraw on the command line.
fun! s:Z(direction)
	let uptoCursor = strpart(getline("."), 0, col(".")-1)
	let bigWord = GetLastItem(uptoCursor, '\.')
	let w = matchend(bigWord, '\W')

	" Can't find the '.' or the cursor is behind some special chars, e.g.
	" '( ', 
	"   ^ (cursor is at this exact point)
	" so just do normal completion.
	if (w != -1)
		if (a:direction == 1)
			return "\<c-n>"
		else
			return "\<c-p>"
		endif
	endif

	" Find the completion and we don't want to ignore cases.
	let oldIgoreCase = &ignorecase
	set noignorecase
	let result = StandShot('InvokeCompletion', a:direction)
	let &ignorecase = oldIgoreCase

	" The lookup has failed.
	if (result == 0)
		" TODO avoid adding an extra space to get the correct completion.
		if (col(".") == s:cursor - 1)
			exe "normal!a "
		endif
		if (a:direction == 1)
			return "\<c-n>"
		else
			return "\<c-p>"
		endif
	endif

	" From this line onward we'll handle the completion for members.

	let dc = strlen(s:oldValue)
	" Delete the previous completion if it exists.
	if (dc > 0)
		exe "normal!" . s:start . "go"
		exe "normal!d" . dc . "l"
	endif

	" Save the value so that we can delete it next time
	" when inserting the next completion
	let s:oldValue = s:value

	" Now we're in normal mode, and the cursor position is one character less than
	" before that means the cursor was placed at the end of line in insert mode
	" (before <c-r>= was called), so we need to move one step to right before
	" inserting the completion.
	if (col(".") == s:cursor - 1)
		return "\<right>" . s:value
	else
		return s:value
	endif
endfun

" This var is not used currently, it was meant to be used to detect if the use
" exists from insert mode, e.g., by pressing <esc>, etc.  Nevertheless, I think
" the current behaviour is satisfactory - if the cursor is back on the same
" location then we can do the completion again based on the previous prefix.
" However, this behaviour is not compatible with vim.
let s:valid = 0

" The index that points to the current completion in the s:members array.
let s:counter = 0 
" The name of the class.
let s:class = ""
" Members in the class, each of them is separated by a ';'
let s:members = ""
" Prefix for the completion.
let s:prefix = ""
" The number of matched members.
let s:total = 0
" Start point of the completion
let s:start = 0
" The current completion.
let s:value = ""
" Cache the members for all the classes been looked up so far, use fqn for the key.
let s:cache = {}
" Need this to get rid of the previous completion.
let s:oldValue = ""
" The col(".") value for the cursor position before inserting completion.
let s:cursor = 0 
" The fully qualified name for class
let s:fqn = ""
" This is an fqn and javadoc/javasource path map.
let s:path = {}

" Function: Get the completion for the current variable.
"
" Param: 	direction Specify for how to traverse the completion 1 for forward, 0 for backward.
"
" Return: 	1 for success, 0 for failure.
fun! InvokeCompletion(direction)
	let position = line2byte(line(".")) + col(".") - 1

	" Make sure the existing text is the same as the
	" previous completion.
	let uptoCursor = strpart(getline("."), 0, col(".")-1)
	let bigWord = GetLastItem(uptoCursor, '\.')
	let existing = ';' . bigWord
	let word = s:prefix . s:value

	" To test if the cursor has not been moved and the existing text is the same
	" as before.
	if (s:start != position - strlen(s:value) || existing !=# word )

		" Move the previous completion (s:value) for s:class to the front.
		if (has_key(s:cache, s:fqn) && strlen(s:value) && s:MovePreviousFront)
			let members = s:cache[s:fqn]
			" The previous completion
			let previous = s:prefix . s:value
			" If the previous completion is not in the front of s:class.
			if (members !~# '^'.previous)
				let members = substitute(members, previous.'\(;\|$\)\@=', '', '')
				let s:members = previous . members
				let s:cache[s:fqn] = s:members
			endif
		endif

		let s:start = position
		let s:valid = 1
		let s:counter = 0
		let s:cursor = col(".")
		let s:value = ""
		let s:oldValue = ""
		
		" Because we're in the insert mode (<c-r>=) so the cursor needs to be moved
		" one step backward so that it can always point to a [:alnum:].
		normal! h
		let temp = s:InitialiseVars()
		normal! l

		if (temp == 0)
			" let s:valid = 0
			let s:total = 0
			return 0
		endif
	endif

	if (a:direction == 1)
		" Go forward
		let s:counter = s:counter + 1
	else
		" Go backward
		let s:counter = s:counter - 1
	endif

	" wrap around
	if (s:counter < 0)
		let s:counter = s:total - 1
	endif

	" We always have substitution(GetItem(s:members, s:prefix, 0), ...) to be an
	" empty string, because the array s:members is separated by s:prefix and the
	" substitution only takes the char up to a ';', the number of chars taken
	" can be zero as well in which case we have an empty string. If the match is
	" a proper one then GetItem(s:members, s:prefix, number) will return a string
	" that's not preceded by the s:prefix, because we're using s:prefix as the
	" delimiter for extracting the value.
	let s:value = substitute(GetItem(s:members, s:prefix, s:counter%s:total), '\([^;]*\);.*', '\1', '')

	return 1
endfun

" Function: Initialise the script vars for the completion operation.
"
" Return:	1 for success, otherwise 0.
fun! s:InitialiseVars()
	let delimiter = '\.'
	let line = getline(line('.'))

	let pattern = '\(switch\s*(\|while\s*(\|if\s*(\|return\|for\s*(\)\=.\{-}\(\i[^;]*\%' . (col('.') + 1). 'c\).*'
	let uptoCursor = substitute(line, pattern, '\2', '')

	let chunk = s:BuildExpression(uptoCursor)
	let tokens = split(chunk, delimiter)
	let s:prefix = ';' . GetLastItem(chunk, delimiter)

	" Note the length can be greater than len(tokens), 
	" Even an input like 'xx.' for ItemCounts is returned 2.
	" For details see the comments for ItemCounts.
	let length = ItemCounts(chunk, delimiter)
	" must have at least a delimiter
	if (length < 2)
		return 0
	endif

	" TODO support completion for 'this' keyword
	if (tokens[0] == 'this')
		return 0
	endif

	" The declaration is on the current line.
	if (uptoCursor =~# '\C\u\w*\s\+'.tokens[0].'$')
		let lineNum = line(".")
	else
		let lineNum = s:VariableDecl(0, 0, 0, tokens[0])
	endif

	let class = ""
	" Name is a class name already.
	if (tokens[0] =~# '^\C\u')
		let class = tokens[0]
	else
		let class = ExtractClassName(lineNum, tokens[0])
	endif

	" can't find the type
	if (class == "")
		return 0
	endif

	let generics = ExtractGenerics(lineNum, tokens[0])

	" walk through the expression tokens
	return s:WalkExpression(class, tokens, length, generics)

endfun

" Function: Build the expression statement for input.
"
" Param:	input A serie of sequential strings taken from a java source code.
"
" Return:	A '.' separated expression with the method parameters stripped.
"			e.g. 'retVal.subString.equalsIgnoreCase'
fun! s:BuildExpression(input)
	let i = 0
	let stack = []
	let token = ""
	let retVal = ""
	let canAdd = 1
	" use empty value to avoid index not found error
	let values = ["", "", "", "", ""]

	while(i < strlen(a:input))
		if (a:input[i] == '(')
			" push the stack
			call insert(stack, token, len(stack))
			let token = ""

		elseif (a:input[i] == ')')
			if (len(stack) - 1 >= 0)
				let index = len(stack)

				" pop the stack
				let item = remove(stack, len(stack) - 1)
				let values[index] = values[index] . item
			endif

			let token = ""

		else
			let token = token . a:input[i]
		endif

		let i = i + 1
	endwhile

	let index = len(stack) + 1
	let values[index] = values[index] . token

	" remove the string before ','
	return substitute(values[index], '.*,\s*', '', '')
endfun


" Function: Walk though the tokens in an expression. If the function is
" 			successful, then the values for s:class, s:fqn, s:members,
" 			s:prefix, and s:total will be reset to new ones.
"
" Return:	1 for success, otherwise 0. 
fun! s:WalkExpression(class, tokens, length, generics)
	let class = a:class
	let success = 0
	let members = ""
	let total = 0
	let fqn = ""
	let size = len(a:generics)

	let i = 0
	" the last item in token is used for s:prefix
	let length = a:length - 1
	while (i < length)
		let i = i + 1
		let success = 0

		if (strlen(members) > 0)
			let memberName = a:tokens[i - 1]
			let file = s:path[fqn]

			if (file =~# '\.html$')
				let class = s:GetMemberTypeFromJavadoc(memberName, file)
			elseif (file =~# '\.java$')
				let class = s:GetMemberTypeFromJavaSource(memberName, file, class)
			else
				echoerr "Wrong return value: " . javadoc . " from GetJavadoc."
				break
			endif
		endif

		if (class == "")
			" check if the current type is of generic type
			if ((size > i - 2) && i >= 2)
				let class = a:generics[i - 2]
			else
				break
			endif
		endif

		let docInfo = GetJavadoc(class, 1, expand("%:t:r"), expand("%:p"))
		if (len(docInfo) == 0)
			break
		endif

		let fqn = docInfo['fqn']
		" Use the cache values if the class's javadoc has already been looked up.
		if (has_key(s:cache, fqn))
			let members = s:cache[fqn]
			let total = ItemCounts(members, s:prefix)
			let success = 1
			continue
		endif

		let javadoc = docInfo['path']
		if (filereadable(javadoc))
			if (javadoc =~# '\.html$')
				silent let members = s:Join(s:ConcateMembersFromJavadoc(javadoc, class))
			elseif (javadoc =~# '\.java$')
				silent let members = s:Join(s:ConcateMembersFromSource(javadoc, class))
			else
				echoerr "Wrong return value: " . javadoc . " from GetJavadoc."
				break
			endif

			let s:cache[fqn] = members
			let s:path[fqn] = javadoc
			let success = 1
			let total = ItemCounts(members, s:prefix)
			continue
		else
			break
		endif
	endwhile

	" reset some script-wide vars
	if (success)
		let s:class = class
		let s:members = members
		let s:total = total
		let s:fqn = fqn

		return 1
	else
		return 0
	endif
endfun

" Function: Get the type for name from a javadoc file.
"
" Param:	name The name of the public member.
"
" Param:	file The file javadoc file.
"
" Return:	The data type for name, or an empty string if not found.
fun! s:GetMemberTypeFromJavadoc(name, file)
	silent call EditTempFile()
	exe "silent r " . a:file
	" Don't want the alternate file.
	bw #

	let lineNum = search('^<TD><CODE><B><A.*#'.a:name, 'n')
	if (lineNum <= 0)
		let lineNum = search('#'.a:name, 'n')
	endif

	let type = ""
	if (lineNum > 0)
		let line = getline(lineNum - 1)

		" Get the fully qualified class name from the same javadoc.
		if (line =~# 'title="\(class\|interface\)\s\+in')
			let type = substitute(line, '.*title="\(class\|interface\)\s\+in\s\+\([^<]*\)<.*', '\2', '')
			let type = substitute(type, '">', '.', '')

		" This is of a generic value.
		elseif (line =~# 'title="type parameter in ')
			" do nothing

		" The type is actually a fully qualified name.
		elseif (line =~# '<CODE>&nbsp;\([^<]*\)<.*')
			let type = substitute(line, '<CODE>&nbsp;\([^<]*\)<.*', '\1', '')

		" This is an inherited member, so open its super class.
		else
			let line = getline(lineNum - 3)
			let file = substitute(line, '.*HREF="\([^"]*\)".*', '\1', '')
			let file = substitute(a:file, '\w\+\.html', '', '') . file

			if (filereadable(file))
				bw %
				return s:GetMemberTypeFromJavadoc(a:name, file)
			endif
		endif
	endif

	" no longer needed the temp file
	bw %

	return type
endfun

" Function: Get the data type for name.
"
" Param:	name The name of the public member.
"
" Param:	file The file, maybe javadoc/javasource, that's containing the
" 			definition or the javadoc for name.
"
" Param:	class The class name for the file.
"
" Return:	The data type for name, or an empty string if not found.
fun! s:GetMemberTypeFromJavaSource(name, file, class)
	silent call EditTempFile()
	exe "silent r " . a:file
	" Don't want the alternate file.
	bw #

	let lineNum = search('\s*public.*'.a:name)
	let type = ""
	if (lineNum <= 0)
		let inheritance = ExtractInheritance()
		if (inheritance == "")
			let type= ""
		else
			let docInfo = GetJavadoc(inheritance, 1, a:class, a:file)
			if (len(docInfo) == 0)
				let type = ""
			endif

			let path = docInfo['path']
			if (filereadable(path))
				bw %
				if (path =~# '\.html$')
					return s:GetMemberTypeFromJavadoc(a:name, path)
				elseif (path =~# '\.java$')
					return s:GetMemberTypeFromJavaSource(a:name, path, inheritance)
				endif
			endif
		endif
	endif

	let line = getline(line('.'))
	let pattern = '.\{-}\(\i\+\)\s\+\<'.a:name.'\>.*'
	if (match(line, pattern) != -1)
		let type = substitute(line, pattern, '\1', '')
	endif

	" don't want the temp file
	bw %
	return type
endfun

" Function: concatenate the members from java source.
fun! s:ConcateMembersFromSource(sourceFile, currentClass)
	silent call EditTempFile()
	exe "silent r " . a:sourceFile
	" Don't want the alternate file.
	bw #

	let end = line('$')
	let lineNum = 1
	let members = []

	let static = '^\tpublic.\{-}\(\i\+\)\s*=.*$'
	let method = '^\tpublic\(\s\+\i\+\)\{-1,}\s\+\(\i\+\)\s*(.*$'
	let enum   = '^\tpublic\s\+enum\s\+\(\i\+\)\s*.*$'
	while (lineNum <= end)
		let line = getline(lineNum)
		if (line =~# static)
			call add(members, substitute(line, static, '\1', ''))
		elseif (line =~# method)
			call add(members, substitute(line, method, '\2', ''))
		elseif (line =~# enum)
			call add(members, substitute(line, enum, '\1', ''))
		endif
		let lineNum = lineNum + 1
	endwhile

	let inheritance = ExtractInheritance()

	if (strlen(inheritance) > 0)
		call extend(members, s:ExtractMembers(inheritance, a:currentClass, a:sourceFile))
	else
		" All the java.lang.Object public methods.
		call add(members, "clone")
		call add(members, "equals")
		call add(members, "finalize")
		call add(members, "getClass")
		call add(members, "hashCode")
		call add(members, "notify")
		call add(members, "notifyAll")
		call add(members, "toString")
		call add(members, "wait")
	endif

	" Sometimes maybe the current buffer is editing a java source code file.
	" '_' is the temp file's name.
	if (expand("%:t:r") == "_")
		" no longer needed the temp file
		bw %
	endif

	return members
endfun

" Function: Extract the public members for class.
"
" Param:	class The class of which we're looking for its members.
"
" Param:	currentClass The class name for the opened java source code.
"
" Param:	path The full path to the opened java source code.
"
" Return:	All the public members for class.
fun! s:ExtractMembers(class, currentClass, path)

	let docInfo = GetJavadoc(a:class, 1, a:currentClass, a:path)
	if (len(docInfo) == 0)
		return []
	endif

	let fqn = docInfo['fqn']
	" Use the cache values if the class's javadoc has already been looked up.
	if (has_key(s:cache, fqn))
		return split(s:cache[fqn], ';')
	endif

	let javadoc = docInfo['path']
	if (filereadable(javadoc))
		if (javadoc =~# '\.html$')
			silent let members = s:ConcateMembersFromJavadoc(javadoc, a:class)
			let s:cache[fqn] = s:Join(members)
			return members
		elseif (javadoc =~# '\.java$')
			silent let members = s:ConcateMembersFromSource(javadoc, a:class)
			let s:cache[fqn] = s:Join(members)
			return members
		else
			echoerr "Wrong return value: " . javadoc . " from GetJavadoc."
			return []
		endif
	endif

	return []

endfun

" Function: Join the members into a ';' separated string.  The user can
" 			manipulate this function to get customised completion behaviour,
" 			e.g. filter out unwanted members.
"
" Return:	A ';' separated string representation of members and duplicates are removed.
fun! s:Join(members)
	call sort(a:members)
	let previous = ""
	let retVal = ""
	" remove duplicates
	for item in a:members
		if (item != previous)
			let retVal = retVal . ';' . item
		endif
		let previous = item
	endfor

	return retVal
endfun

" Function: Concatenate all the members for a class into a ';'
" 			separated string.  This function is javadoc dependent.
"
" Param: 	javadoc This is the full path to the file that contains the javadoc page.
"
" Param: 	class The name for the class.
"
" Precon:	The current buffer is displaying the java source code.
"
" Return:	All the public fields and methods for class.
fun! s:ConcateMembersFromJavadoc(javadoc, class)
	silent call EditTempFile()
	exe "r " . a:javadoc
	" Don't want the alternate file.
	bw #

	let members = []
	" java 4 and java (5|6) have different javadoc output
	if (search('(Java .* [56])', 'n'))
		let members = s:UserJavadoc15()
	else
		let members = s:UseJavadoc14(a:class)
	endif

	" Get rid of this temp file.
	bw %
	return members
endfun

" Function:	Parse the public members from javadoc 15
"
" Precon:	The current buffer is displaying the javadoc.
"
" Return:	All the public fields and methods for a class.
fun! s:UserJavadoc15()

	let members = []
	while (1 != 0)
		let [lnum, col] = searchpos('<TH ALIGN="left"><B>Methods ', 'W')
		if (lnum == 0)
			break
		endif
		call extend(members, split(substitute(getline(lnum + 3), '<.\{-}>', '', 'g'), ', '))
	endwhile

	if (search('<META NAME="keywords" CONTENT="', 'n'))
		v/<META NAME="keywords" CONTENT="/d
		%s/<META NAME="keywords" CONTENT="//

		" this may fail for exceptions
		%s/()">//e
		g/ /d
		g/^[^"]/call add(members, expand("<cword>"))
	endif

	return members

endfun

" Function: Parse the public members from javadoc 14
"
" Precon:	The current buffer is displaying the javadoc.
"
" Param:	class The class name.
"
" Return:	All the public fields and methods for class.
fun! s:UseJavadoc14(class)

	let members = []
	while (1 != 0)
		let [lnum, col] = searchpos('<TD><B>Methods inherited from ', 'W')
		if (lnum == 0)
			break
		endif
		let methods = substitute(getline(lnum + 3), '<.\{-}>', '', 'g')
		call extend(members, split(substitute(methods, '$', '', ''), ', '))
	endwhile

	" Norrow the search
	/<!-- =========== FIELD SUMMARY =========== -->/+1, /<!-- ============ FIELD DETAIL =========== -->/m0
	" Delete all the following lines.
	normal! dG

	" Don't want proctected members.  However, we can't deal with the protected
	" members inherited from the super classes.
	silent g/<CODE>protected &nbsp;/+1d
	" Norrow down to members
	v/.*html#/d
	silent g/^ href=/d
	" Make the members from the super classes to occupy a line each.
	%s/.\{-}\.html#\(\w\+\(([^)]*)\)\=\)/\1/g
	" silent g/"/d
	" silent %s/\w\+\.//g
	" Some commands are not silent, which means they have to find
	" a match in the file, otherwise the regex needs to be deviced again.

	" Grab the members from the first words on each line.
	" In this case the g command allows us to optimise the search better then a while loop.
	g/^[^"]/let firstWord = expand("<cword>") |
			\ if (firstWord !=# a:class && match(members, '\<\C'.firstWord.'\>') == -1) |
			\ call add(members, firstWord) |
			\ endif

	return members
endfun

" These functions are for debugging purposes.
fun! GetMembers()
	return s:members
endfun

fun! GetValue()
	return s:value
endfun

fun! GetClass()
	return s:class
endfun

fun! GetPrefix()
	return s:prefix
endfun

fun! GetCounter()
	return s:counter
endfun

fun! GetStart()
	return s:start
endfun

fun! GetBuiltIn()
	return s:UseBuiltIn
endfun

fun! GetTotal()
	return s:total
endfun

fun! GetCache()
	return s:cache
endfun
