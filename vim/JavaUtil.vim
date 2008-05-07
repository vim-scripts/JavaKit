if exists("JavaUtilSourced")
	finish
endif 
let JavaUtilSourced = "true"

" Function: Extract the class name from line lineNum.
"
" Param: 	lineNum The line indexed by this lineNum has got the class name
" Param: 	word This is the name for the variable in the java source file.
"
" Return: 	The class name, or an empty string when it's not found.
fun! ExtractClassName(lineNum, word)

	let line = getline(a:lineNum)

	" For matching statement that initialise an object.
	let pos = match(line, '\C\<'.a:word.'\>\s*=\s\+new\s\+\C\u\i*\s*\(<[^)]*\)\=(')

	" This check is actually redundant, if this function is called from
	" s:FindClassName's backward searching loop.
	if (pos != -1) 
		if (IsStatement(pos, a:lineNum))
			return substitute(line, '.*=\s\+new\s\+\(\i\+\).*', '\1', '')
		endif
	endif

	" For matching a declaration statement
	let pos = match(line, '\C\u\i*\(<[^;(]*\)\=\s\+\C\<'.a:word.'\>')
	if (pos != -1)
		if (IsStatement(pos, a:lineNum))
			" Match the type of the current variable
			let pattern = '.\{-}\(\i\+\)\(<[^;(]*\)\=\s\+\C\<' . a:word . '\>.*'
			return substitute(line, pattern, '\1', '')
		endif
	endif

	return "" " className is inside a comment or not found.

endfun

" Function: Extract the generic types from the given line.
"
" Param:	lineNum The line number where the generic types might appear.
"
" Param:	word The variable name.
"
" Return:	The generic types list, or an empty list if the current line doesn't
" 			contain any generic type declaration.
fun! ExtractGenerics(lineNum, word)
	let line = getline(a:lineNum)
	let pos = match(line, '>\s\+\C\<'.a:word.'\>')
	if (pos == -1)
		return {}
	endif

	" Get the generic types
	let temp = substitute(line, '.\{-}<\(.*\)>.*\s\+\C\<'.a:word.'\>.*', '\1', '')
	let temp = substitute(temp, '\i\+,\s\+', '', 'g')
	return split(substitute(temp, '>', '', 'g'), '\(,\s*\|<\)')
endfun

" Function: Extract the package head, i.e. the first component in the package name.
fun! ExtractPackageHead(packageName)
	let retVal = a:packageName
	if (stridx(a:packageName, '.') > 0)
		let retVal = split(a:packageName, '\.')[0]
	endi
	return retVal
endfun

" Function:	Extract the inheritance class for the current class.
fun! ExtractInheritance()
	let lineNum = 1
	let end = line('$')
	let pattern = '.*extends\s\+'


	while (lineNum <= end)
		let line = getline(lineNum)

		if (line =~# ' \(class\|interface\) ')
			let column = match(line, pattern)
			if (IsStatement(column, line) == 0)
				let lineNum = lineNum + 1
				continue
			endif

			if (column >= 0)
				return substitute(line, pattern, '', '')
			else
				return ""
			endif
		endif

		let lineNum = lineNum + 1
	endwhile

	return ""
endfun

" Function: Get the imports for the current java source code.
fun! ExtractImports()
	let retVal = []
	call add(retVal, "java.lang.*")

	" let pattern = '^\s*import\s\+\(static\s\+\)\=\([^;]*;\).*'
	let pattern = '^\s*import\s\+\([^;]*\);.*'

	let lineNum = 1
	let end = line('$')
	while (lineNum <= end)
		let line = getline(lineNum)
		if (line =~# pattern)
			call add(retVal, substitute(line, pattern, '\1', ''))
		elseif (line =~# '\s\(class\|interface\)\s')
			break
		endif

		let lineNum = lineNum + 1
	endwhile

	" make explicit imports have higher priority
	call sort(retVal, "ImportCompare")
	return retVal
endfun

" Function: Sort the import list so that explicit imports can get higher
" 			priority than wildcard imports.
fun! ImportCompare(left, right)
	if (stridx(a:left, '.*') > 0)
		return 1
	else 
		return -1
	endif
endfun

" Function: Find the package name for the current file.  The return value
" represents the directory structure for the package.  For exmaple, package
" foo.bar, will return foo/bar/ If the current file is not included in a
" package, then an empty string is returned.
fun! FindPackageName(separator)
	let lastLine = line("$")
	let currentLine = 1

	while currentLine <= lastLine
		let ln = getline(currentLine)
		if ln =~# '^\s*package'
			let offset = matchend(ln, '^\s*package\s*')
			let lastChar = match(ln, '\s*;')
			let packageName = strpart(ln, offset, lastChar - offset)
			let packageName = substitute(packageName, '\.', a:separator, 'g')
			return packageName . a:separator
		endif

		let currentLine = currentLine + 1
	endwhile

	return ''
endfun

" Function: Find the src directory, it's ended with a /
fun! FindSrcDirectory(packageName)
	" Find how deep the current directroy is nested in the source code directory tree
	let depth = ItemCounts(a:packageName, '/', 'exact')

	" The test directory is nested one level shallower.
	if (a:packageName =~# '^test')
		let depth = depth - s:Shallow
		if (depth == 0)
			return ''
		elseif (depth < 0)
			" TODO climb up the directory
		endif
	endif

	let src = ""
	while depth > 0
		let src = "../" . src
		let depth = depth - 1
	endwhile

	return src
endfun

" Function: Test the position at line lineNum is part of a C, C++, or java comment.
" 			This function has no side effects.  The cursor remains unchanged
" 			after its invokation.
" Return: 	1 if the given position in line lineNum is a statement, otherwise 0.
fun! IsStatement(position, lineNum)
	let name = synIDattr(synID(a:lineNum, a:position, 0), "name")
	if (name =~? "string" || name =~? "comment")
		return 0
	else
		return 1
	endif
endfun
