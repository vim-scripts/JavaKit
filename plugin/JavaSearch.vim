exe "so " . g:VIMMACROSPATH . "Javadoc.vim"
exe "so " . g:VIMMACROSPATH . "Functions.vim"

nmap <silent> gm :call SearchMethodHead(1)<cr>
nmap <silent> gc :call SearchClassHead(1)<cr>
nmap <silent> gd :call VariableDecl(1, 0, 1)<cr>
nmap <silent> gi :call VariableDecl(1, 1, 1)<cr>

" Set s:debug to 1 to debug all the main features,
" 2 to debug completion, or 3 to debug VariableDecl
let s:debug = 0
let s:DEBUG_ALL = 1
let s:COMPLETION = 2
let s:VARIABLE_DECL = 3

" ~~~~~~~~~~~~~~~~~~~~~~~~ Patterns ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" This is the pattern that excludes most of the C or C++ comments, 
" and being not trailed behind by a " (double quote)
let s:EXCLUDE = '\(\(^\s*\*\|/[/*]\|"\).*\)\@<!'

" Pattern for matching a method.
let s:METHOD_BEAR = '\(\<\(new\>\|else\>\|return\>\)\@!\&\h\w*\s\+\)' . 
							\'\@<=\h\w*\_s\{-}(\_[^)]*)\_s\{-}[{[:alpha:]]'
let s:METHOD = s:EXCLUDE . s:METHOD_BEAR

" Pattern for matching a constructor.
let s:CONSTRUCTOR = '\(^\s*\(public\|protected\|private\)\=\s*\)' . 
			\ '\@<=\C\u\h\w*\_s*(\_[^)]*)\_s*[{[:alpha:]]'

" Pattern for matching a normal class
let s:NORMAL_CLASS_BEAR = '\(\<\Cclass\>\_s\+\)\@<=\C\u\h\w*\_s\+\({\_s*}\)\@!'
let s:NORMAL_CLASS = s:EXCLUDE . s:NORMAL_CLASS_BEAR

" Pattern for matched an anonymous class
let s:ANONYMOUS_CLASS = s:EXCLUDE . 
											 \'\(\(\s*\|(\_[^)]*\)\C\<new\>\s\+\)\@<=\C\u\h\w*(\_[^)]*)\_s*{'
  
" ~~~~~~~~~~~~~~~~~~~~ End Patterns ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Function: Go to the declaration of current method or constructor.
"
" Return: The line number from where the method head was found, or -1 if the
" 				matched line is on the current line; return 0 if the current line is
" 				not inside a method block, or when the match can't be found.
"
" Bug: If the cursor is a class's field that without a scope modifier, then the
" 		 search will go to a random method.
"
fun! SearchMethodHead(restore)
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
" Bug: If the cursor is a class's field that without a scope modifier, then the
" 		 search will go to a random class head.
"
fun! SearchClassHead(restore)

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
	let methodLine = SearchMethodHead(0)
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
" 					currently.
"
" Paratmeter: smartCursor If this flag is set to 1 and the search is not found
" 												then the cursor will return to where the search
" 												started. If the search is found then the cursor will
" 												be on the matched pattern.  Set it 0 if we don't care
" 												about the cusor position.
"
" Paratmeter: init Set it to 1 to find the initialisation line instead of the
" 								 declaration line.  For exmaple when we don't want to find the
" 								 line "Object obj;" which declares "obj", but we want to find
" 								 in the line "obj = new  HashTable()".  If we can't find the
" 								 initialisation line, then a second attempt will be made to
" 								 find the declaration.
"
" Paratmeter: premitive Set this value to 1 to allow matching premitive data
" 											type declarations; set it to 0 to disallow such match.
"
" Parameter: ... This additional paratmeter is for search a word with the name,
" 							 so we're not checking '<cword>', but the cursor still needs to
" 							 be at the line where a:1 locates.
"
" Return: The line number for where the declaration or initialisation is found,
" 				otherwise 0 is returned.
"
fun! VariableDecl(smartCursor, init, premitive, ...)
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
		call SearchMethodHead(0)
		let result = s:InstanceVariableDecl(name, a:init)
	else
		let method = SearchMethodHead(0)
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
" Return: non-zero value for the line number that has the initialisation.
fun! s:MethodVariableDecl(lineNum, name, init)
	let anonymousIndent = cindent(s:SearchAnonymous(0))
	if (cindent(".") < anonymousIndent || anonymousIndent <= 0)
		let top = line(".")
	else
		let top = SearchMethodHead(0)
	endif

	let declaration = 0
	let initialisation = 0
	let lineNum = a:lineNum
	while (lineNum >= top)
		let line = getline(lineNum)

		let pattern = s:GetInit(a:name)
		if (line =~# pattern && IsInsideComment(match(line, pattern), lineNum) == -1)
				let initialisation = lineNum
				if (a:init == 1)
					break " Found it.
				endif
		endif

		let pattern = s:GetDecl(a:name)
		if (line =~# pattern && IsInsideComment(match(line, pattern), lineNum) == -1)
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
" Precondition: The cursor has to be on the current method head.
" Return: non-zero value for the line number that has the initialisation.
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

" Function: This is the loop that find a instance variable. It's a hand off from
" InstanceVariableDecl.
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
		if (cindent(lineNum) == a:instanceIndent && SearchMethodHead(0) != -1)
			if (IsInsideComment(match(getline(lineNum), a:pattern), lineNum) == -1)
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

" Function: Get the pattern that matches an initialisation for a variable.
fun! s:GetInit(name)
	return s:EXCLUDE . '\<' . a:name . '\>\s*=\s\+new\s\+' . s:UpperCase . '\h\w*\s*[[(]'
endfun

" Function: Get the pattern that matches a declaration for a variable.
fun! s:GetDecl(name)
	" Match 'String[] str', 'String str[]', 'String str', etc.
	return s:EXCLUDE . '\<\(return\>\|assert\>\)\@!\&\(\s*\[\s*\]\)\=' . s:UpperCase
				\ . '\h\w*\(\s*\[\s*\]\)\=\s\+\C\<' . a:name .'\>'
endfun

" Function: Search a pattorn backward, if the pattern is in a C or C++
" 					comments then it'll be skipped.
"
" Paratmeter: pattern The pattern to be searched for.
"
" Return: The line number where the pattern is matched, as a side effect
" 				the cursor will be placed on the matched pattern. 0 for not matching
" 				the pattern, and the cursor will remain at the same place.
fun! s:SearchBackward(pattern)
	let result = search(a:pattern, 'bW')

	if (result == 0)
		return result
	endif

	if (IsInsideComment(col("."), line(".")) == 1)
		return s:SearchBackward(a:pattern)
	endif

	return result
endfun

"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"~	  	 	 	   			 Start of Completion                 	       ~
"~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Set it to 1 to use vim built-in normal command to find the declaration for the
" current identifier; or set it 0 to use our own function to do the same chore.
let s:UseBuiltIn = 1

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
" We cache the members for all the classes we've looked up so far.
let s:cache = ""
" Need to this get rid of the previous completion.
let s:oldValue = ""
" The col(".") value for the cursor position before inserting completion.
let s:cursor = 0 

" Function: Get the completion for the current variable.
" Parameter: direction Specify for how to traverse the completion 
" 										 1 for forward, 0 for backward.
" Return: 1 for success, 0 for failure.
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
		if (Hashtable_exist(s:class, s:cache) && strlen(s:value) && s:MovePreviousFront)
			let memebers = Hashtable_get(s:class, s:cache)
			" The previous completion
			let previous = s:prefix . s:value
			" If the previous completion is not in the front of s:class.
			if (memebers !~# '^'.previous)
				let members = substitute(memebers, previous.'\(;\|$\)\@=', '', '')
				let s:members = previous . members
				let s:cache = Hashtable_put(s:class, s:members, s:cache)
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
		let temp = s:SetupCompletion()
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
	" delimeter for extracting the value.
	let s:value = substitute(GetItem(s:members, s:prefix, s:counter%s:total), '\([^;]*\);.*', '\1', '')

	return 1
endfun

" Function: Setup s:class, s:members, s:prefix, and s:total.
" Return: 1 for success, 0 for error.
fun! s:SetupCompletion()

	" Test the current cursor is behind a '.'
	let uptoCursor = strpart(getline("."), 0, col("."))
	let bigWord = GetLastItem(uptoCursor, '\s')

	let delimter = '\.'
	let counts = ItemCounts(bigWord, delimter)
	if (counts < 2)
		" We expect at least one '.'
		if (s:debug == s:COMPLETION || s:debug == s:DEBUG_ALL)
			echoerr "counts " . counts
		endif
		return 0
	endif

	let s:prefix = ';' . GetLastItem(bigWord, delimter)
	let name = GetItem(bigWord, delimter, counts - 2)
	let name = GetLastItem(name, '\W')

	if (name == "this")
		" Don't want to lookup 'this'.
		if (s:debug == s:COMPLETION || s:debug == s:DEBUG_ALL)
			echoerr "no completion for this"
		endif
		return 0
	endif

	" The declaration is on the current line.
	if (uptoCursor =~# '\C\u\w*\s\+'.name.'$')
		let lineNum = line(".")
	else

		if (s:UseBuiltIn == 0)
			let lineNum = VariableDecl(0, 0, 0, name)
		else
			" The gd command works good enough, but it doesn't always give
			" correct result.
			exe "normal?\\w\\.\<cr>"
			let saveIgnoreCase = &ignorecase
			let saveComments = &comments
			set noignorecase
			set comments=://,sr:/*,mb:*,ex:*/
			exe "normal!gd"
			let &ignorecase = saveIgnoreCase
			let &comments = saveComments
			let lineNum = line(".")
		endif
	endif

	if (s:UseBuiltIn == 0)
		" Name is a class name already.
		if (name =~# '^\C\u')
			let class = name
		else
			let class = ExtractClassName(lineNum, name)
			if (class ==# "")
				if (s:debug == s:COMPLETION || s:debug == s:DEBUG_ALL)
					echoerr "Class Name: " s:class . " Word: " . name . " LineNO: " . lineNum
				endif
				return 0
			endif
		endif

	else
		if (getline(".") !~# '\C\u\w*\s\+'.name)
			" If the lineNum is zero then we'll expand 'name' to be a class name rather
			" than a variable name which should have the upper case letter in its first
			" letter.
			if(name !~# '^\C\u')
				if (s:debug == s:COMPLETION || s:debug == s:DEBUG_ALL)
					echoerr bigWord
					echoerr s:class . " " . name . " " . lineNum
				endif
				return 0
			endif
		endif

	endif

	" Name is a class name already.
	if (name =~# '^\C\u')
		let class = name
	else
		let class = ExtractClassName(lineNum, name)
		if (class ==# "")
			if (s:debug == s:COMPLETION || s:debug == s:DEBUG_ALL)
				echoerr "s:class in SetupCompletion"
			endif
			return 0
		endif
	endif
	
	let s:class = class
	" Use the cache values if the class's javadoc has already been looked up.
	if (Hashtable_exist(class, s:cache))
		if (Hashtable_get(class, s:cache) ==# 'No Javadoc')
			return 0
		else
			let s:members = Hashtable_get(class, s:cache)
			let s:total = ItemCounts(s:members, s:prefix)
			return 1
		endif
	endif

	let javadoc = GetJavadoc(s:class)
	if (filereadable(javadoc))
		silent let s:members =  s:ConcateMembers(javadoc, s:class)
		" The javadoc exists so cache its members.
		let s:cache = Hashtable_put(class, s:members, s:cache)
		let s:total = ItemCounts(s:members, s:prefix)
		return 1

	else
		if (s:debug == s:COMPLETION || s:debug == s:DEBUG_ALL)
			echoerr "javadoc in SetupCompletion"
		endif

		" The javadoc doesn't exist, so we put a sentiment value
		" to indicate that it hasn't got a javadoc.
		let s:cache = Hashtable_put(class, 'No Javadoc', s:cache)
		return 0
	endif

endfun

" Function: ConcateMembers concatenate all the members for a class into a ';'
" separated string.  This function is javadoc dependent.
" Parameter: javadoc This is the full path to the file that contains the javadoc page.
" Parameter: class The name for the class.
fun! s:ConcateMembers(javadoc, class)
	silent call EditTempFile()
	exe "r " . a:javadoc
	" Don't want the alternate file.
	bw #

	" Norrow the search
	/<!-- =========== FIELD SUMMARY =========== -->/+1, /<!-- ============ FIELD DETAIL =========== -->/m0
	" Delete all the following lines.
	normal! dG
	" Don't want proctected members.  However, we can't deal with the protected
	" members inherited from the super classes.
	silent g/<CODE>protected &nbsp;/+1d
	" Norrow down to memebers
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
	let members = "" |
				\ g/^[^"]/let firstWord = expand("<cword>") |
				\ if (firstWord !=# a:class && match(members, '\<\C'.firstWord.'\>') == -1) |
				\ let members = members . ';' . firstWord |
				\ endif

	" Get rid of this temp file.
	bw %
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

" The following bechmark programs try to find out what is the quickest way to
" grab the first word of a line over the whole file.  The input file needs to be
" very large, i.e. > 10000 lines, to see the difference.
"
" The winner from my machine (AMD1.3GHZ VIM6.250 WinXP) is the g command.
"
" To run it
" :echo WhileLoop()
" But use a slightly different way to run GCommand()
" :let b:i = GCommand()
" :echo b:i
fun! WhileLoop()
	let start= localtime()
	let lineNum = 1
	let end = line("$")
	while (lineNum <= end)
		let word = substitute(getline(lineNum), '^\(\w\+\).*', '\1', '')
		let lineNum = lineNum + 1
	endwhile

	return localtime() - start
endfun

fun! GCommand()
	let start=localtime()
	g/^/let temp = expand("<cword>")
	return localtime() - start
endfun

" Check if line has the desired format for classes list.  If the javadocpath
" doesn't have the class list files in the desired format, error messages
" will be printed.
" Parameter: javadocpath should be the full path to a top level directory of the
" javadoc which contains the files, 'allclasses-frame.html' and
" 'allclasses-noframe.html'
" Return: 1 for compatible, -1 for non-compatible.
" call CheckJavadocCompatible('E:/Documents and Settings/Kid/Desktop/CMT3082/GoodChat/doc/javadoc/')
" call CheckJavadocCompatible('C:/java/j2sdk1.4.0_01/docs/api/') 
" notice the ending '/'
fun! CheckJavadocCompatible(javadocpath)
	let result = s:CheckOverviewPageCompatible(a:javadocpath.'overview-frame.html')
	if (result == -1)
		return result
	endif

	return s:CheckClassesListCompatible(a:javadocpath, a:javadocpath.'allclasses-frame.html')
	" return s:CheckClassesListCompatible(a:javadocpath, a:javadocpath.'allclasses-noframe.html')

endfun

" Hand-off from CheckClassesListCompatible
" Return: 1 for compatible, -1 for non-compatible.
fun! s:CheckClassesListCompatible(javadocpath, classesListFile, ...)
	if (!filereadable(a:classesListFile))
		echoerr a:classesListFile . " not found."
		return -1
	endif

	exe "edit " . a:classesListFile
	setlocal readonly
	setlocal buftype=nowrite
	setlocal noswapfile
	call search('<TD NOWRAP><FONT CLASS="', '')
	" Do the search again, but the cursor should be still at same the line, 
	" because there is only one match.
	let lineNum = search('<TD NOWRAP><FONT CLASS="', '')
	let line = getline(".") 
	if (ItemCounts(line, '"') != 7)
		echoerr a:classesListFile . " is not compatible"
		return -1
	endif
	let href = GetItem(line, '"', 3)
	" Check if the current line has got a html href.
	if (matchend(href, '.*\.html') == -1)
		echoerr href
		echoerr a:classesListFile . " is not compatible"
		return -1
	endif

	" If the package exist that check if the packageFrame is compatible 
	let package = strpart(href, 0, strridx(href, '/'))
	if (strlen(package) > 0)
		let result = s:CheckPackagePageCompatible(a:javadocpath.package.'/package-frame.html')
		if (result == -1)
			return -1
		endif
	endif

	let oldLineNum = getline(".")
	let lineNum = search('TARGET="classFrame">', '')
	let lineNum = search('TARGET="classFrame">', '')
	" Should be on a different line now.
	if (lineNum == oldLineNum)
		echoerr a:classesListFile . " is not compatible"
		return -1
	endif

	" ItemCounts should return 5
	let line = getline(".")
	if (ItemCounts(line, '"') != 5)
		echoerr a:classesListFile . " is not compatible"
		return -1
	endif

	" Check if the current line has got the href in the given position.
	let href = GetItem(line, '"', 1)
	if (matchend(href, '.*\.html') == -1)
		echoerr a:classesListFile . " is not compatible"
		return -1
	endif

	" If the package exist that check if the packageFrame is compatible 
	let package = strpart(href, 0, strridx(href, '/'))
	if (strlen(package) > 0)
		let result = s:CheckPackagePageCompatible(a:javadocpath.package.'/package-frame.html')
		if (result == -1)
			return -1
		endif
	endif

	bw %
	return 1

endfun

fun! s:CheckOverviewPageCompatible(overviewPage)
	if (!filereadable(a:overviewPage))
		echoerr a:overviewPage . " is not found"
		return -1
	endif

	exe "edit " . a:overviewPage

	if (search('TARGET="packageFrame"', '') == 0)
		echoerr a:overviewPage . "is not compatible"
		return -1
	endif

	bw %
	return 1
endfun

fun! s:CheckPackagePageCompatible(packagePage)
	if (!filereadable(a:packagePage))
		echoerr a:packagePage . " is not found"
		return -1
	endif

	exe "edit " . a:packagePage 
	" Should have hrefs that can be open on the classFrame.
	if (search('TARGET="classFrame"', '') == -1)
		echoerr a:packagePage . "is not compatible"
		return  -1
	endif

	bw %
	return 1
endfun

