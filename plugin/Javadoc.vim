if exists("JavadocSourced")
	finish
endif 
let JavadocSourced = "true"

" Need some utilities from this script.
exe "so " . g:VIMMACROSPATH . "Functions.vim"
" Need some utilities from this script.
exe "so " . g:VIMMACROSPATH . "JavaMacros.vim"

" Do the clean up before existing vim. 
" Note: VimLeavePre event messes up the the last cursor mark.
au VimLeave *.java :call s:CleanCookie()

" Set the K to be the command that does easy lookups in command mode.
command! -nargs=1 -complete=command K call StandShot('Lookup', ('<a>'))

"   ,----------------------------------------------*\
"  /                                                |--sword--||
" (                      Map                        |---------||*
"  \                                                |--sword--||
"   `----------------------------------------------*/
   
" In normal press K on top off a java variable, then the javadoc
" for that variable's type should be fired up.
nnoremap K :echo StandShot("OpenJavadoc")<CR>

"   ,----------------------------------------------*\
"  /                                                |--sword--||
" (              User Defined Variables             |---------||*
"  \                                                |--sword--||
"   `----------------------------------------------*/

" The executable name for the browser.
let s:Browser = "start IEXPLORE.EXE"

" The top directories for all javadocs. The first entry will be the default
" directory.  When opening the default pages, this value is used.
"
" The path has to be separated and ended by ; Use / to separate the directories
" within the top directories.  Here's an exmaple to clear things up hopefully.
" Say we want to have two top level directories included, 'c:\xxx\api' and
" 'd:\yyy\javadoc\', then the value for s:Roots should be
" 'c:/xxx/api;d:/yyy/javadoc;' <-- Don't forget the last ';'
"
" This value can hard-code all the javadoc top level directories that users wish
" to use.  This scripts also supports dynamic lookup of top level directories
" such as based on the line 'package xxx.yyy;' in the java file that's being
" edited currently. Change the code in s:LookupDocDirs appropriately, to
" customise this dynamic lookup behaviour.
let s:Roots = "C:/java/jdk/current/docs/api/;C:/java/tomcat/current/webapps/tomcat-docs/servletapi/; C:/java/tomcat/current/webapps/tomcat-docs/jspapi/;C:/java/junit/current/javadoc/;C:/java/commons-fileupload/current/docs/apidocs/;"

" Does the brower support the use of frames? If yes, set it to 1; otherwise set
" it to 0.  When it's set to 1, this option also suggests the browser lives in a
" GUI environment and supports javascript.
let s:UseFrame = 1
" Maximise the browser window or not. 1 is true, 0 is false.
let s:MaxWin = 0
" If the browser window is not maximised and the s:UseFrame is 1, then set it to
" the following size.  The browser will be opened in the center of the screen.
let s:WinWidth = 800
let s:WinHeight = 700

" Reuse browser window.  When this option is set to 1 all the javadoc will be
" open in one browser.  If this option have the value 0, then a new instance of the
" browser will be created when OpenBrowser is called.
"
" For this option to work properly users also need to copy two files,
" JavadocApplet.html and JavadocHelper.jar, in the temp path directory which is the
" same as GetTempPath().  
"
" To force opening a new browser call RefreshSessionID.
let s:ReuseBrowser = 1

" If the href for the class pages is the same as the previous one, do we keep
" the view, i.e. no reloading of the current frames. 1 for keeping the view,
" otherwise set it to 0 to reloading the frames nevertheless.  If this value is
" used for the first time, its value is 2.
let s:KeepView = 0

"   ,----------------------------------------------*\
"  /                                                |--sword--||
" (                Script Variables                 |---------||*
"  \                                                |--sword--||
"   `----------------------------------------------*/

" The top level directories for the javadocs. It will have the value of s:Roots
" and the result of the dynamic lookup of other top level directories later.
let s:docDirs = ""

" Various javadoc pages(frames) in the browser window.
let s:overviewPage = ""
let s:packagePage = ""
let s:classPage = ""

" This is used to separate each entry. It's a read-only variable.
let s:separator = "#"
" We pair line number and javadoc path as one entry, and accumulate the entries
" into a big string separated by s:entrySeparator.
let s:entrySeparator = "@" " This is read-only
let s:entries = ""

" Message prifix, this is a read-only variable.
let s:messageHead = "Can't find the javadoc for "

" Use an auxiliary file to display the html.
let s:javadocFile = GetTempPath()."javadoc.tmp.html"

" This file will store how and when to update the frames in the opened browser.
" The actual contents in this file will be parsed by the applet periodically.
" The path for this file has to the same as "JavadocApplet.html",
" "JavadocHelper.java", and s:javadocFile.
let s:cookie = GetTempPath()."javadoc.cookie"

" This variable is only setup once.  It remains unchanged and shared by all the
" instances of vim that edit java code.  We can force to open a new browser by
" writing a different value for the sessionID in the cookie file.
let s:sessionID = ""

" The vars for managing how and when to open the default javadoc pages.  
let s:openDefaultNextTime = 0
let s:previousFileName = 0
let s:previousCursorPosition = 0

"   ,----------------------------------------------*\
"  /                                                |--sword--||
" (              Global Functions                   |---------||*
"  \                                                |--sword--||
"   `----------------------------------------------*/

" Function: This the main function for this script.  It opens a javadoc in
" browser for the variable that's under the cursor.
" Return: If the javadoc can't be opened then a non-empty string given the
" reason will be returned; otherwise it returns an empty string.
fun! OpenJavadoc()
	" Store the current cursor position, so we can open the default pages when is
	" appropriate.
	let pos = line2byte(line(".")) + col(".") - 1

	" Do a daynamic lookup of the javadoc based on the 'package xxx.yyy;' line in
	" this java source file.
	call s:LookupDocDirs()

	" The return value
	let retVal = ""
	" The cursor is on an import statement.
	if getline(".") =~# '^[[:space:]]*import[[:space:]]\+\([^;]\+\);.*$'
		let retVal = s:OpenImport(getline("."))

	" The cursor might be on an a java variable.
	else
		let className = s:FindClassName()
		if (strlen(className) > 0)
			let retVal = s:OpenClass(className, s:FindImports(), 1)
		else
			let retVal = s:messageHead . "the current word."
		endif
	endif

	" We found the javadoc, so it's the end of the story
	if (strlen(retVal) == 0)
		let s:openDefaultNextTime = 0
		return retVal
	endif

	" Can't find it, so go back to the same cursor position.
	exe "normal!" . pos . "go"
	" Open the default javadoc pages if the cursor is still at the same position.
	if (s:openDefaultNextTime == 1 && s:CursorChanged() == 0)
		let s:openDefaultNextTime = 0
		call s:OpenDefault()
		let retVal = "Javadoc not found and forced to open the default pages."
	else
		let retVal = s:PreOpenDefault(retVal)
	endif

	return retVal

endfun

" Function: returned the s:sessionID.  We need this function be global so
" that other vim peers can query the value of s:sessionID.  Therefore, we
" can avoid opening a new browser for each vim.
fun! GetSessionID()
	return s:sessionID
endfun

" Function: Refresh the s:sessionID so that we can open a new browser later.
fun! RefreshSessionID()
	" Sleep 1 sec to give the applet enough time to know that the cookie file has
	" been changed and then the browser will stop taking any requests for opening
	" javadocs.
	call s:Refresh(1)
endfun

" Function: Open the javadoc in browser for the class with className.
fun! Lookup(className)
	call s:LookupDocDirs()
	call s:OpenClass(a:className, s:FindImports(), 1)
endfun

" Functions: Lookup a javadoc for a class stealthily without opening or updating
" any browser.
" Parameter: class The class name.
" Return: The full path that points to the location of the javadoc
" for class.
fun! GetJavadoc(class)
	call s:LookupDocDirs()
	return s:OpenClass(a:class, s:FindImports(), 0)
endfun

" Function: Extract the class name from line lineNum.
" Parameter: lineNum The line indexed by this lineNum has got the class name
" Parameter: word This is the name for the variable in the java source file.
" Return: The class name, or an empty string when it's not found.
fun! ExtractClassName(lineNum, word)

	let line = getline(a:lineNum)

	" For matching statement that initialise an object.
	let pos = match(line, '\C\<'.a:word.'\>\s*=\s\+new\s\+\C\u\h\w*(')
	" This check is actually redundant, if this function is called from
	" s:FindClassName's backward searching loop.
	if (pos != -1) 
		if (IsInsideComment(pos, a:lineNum) != 1)
			return substitute(line, '.*=\s\+new\s\+\(\w\+\).*', '\1', '')
		endif
	endif

	" For matching a declaration statement
	let pos = match(line, '\C\u\h\w*\s\+\C\<'.a:word.'\>')
	if (pos != -1)
		if (IsInsideComment(pos, a:lineNum) != 1)
			" Match the type of the current variable
			let pattern = '.\{-}\(\w\+\)\s\+\C\<' . a:word . '\>.*'
			return substitute(line, pattern, '\1', '')
		endif
	endif

	return "" " className is inside a comment or not found.

endfun

"   ,----------------------------------------------*\
"  /                                                |--sword--||
" (              Script Functions                   |---------||*
"  \                                                |--sword--||
"   `----------------------------------------------*/

" Function: Lookup the top level javadoc directories.
fun! s:LookupDocDirs()
	" Use 'package xxx.yyy;' to set the current top level javadoc directory.
	" Find the javadoc path relative to src directory.
	let currentDocDir = FindSrcDirectory(FindPackageName()) . "../doc/javadoc/"
	if (isdirectory(currentDocDir))
		let currentDocDir = expand("%:p:h") . "/" . currentDocDir
	else
		let currentDocDir =""
	endif
	let s:docDirs = s:Roots . currentDocDir . ";"
endfun

" Function: Open the lines that have got import statement, 
" E.g. import java.io.File; or , import java.net.*;
" Parameter: line the line which will be looked for the import statements.
" Return: An empty string for successfully finding the javadoc; otherwise a
" message indicating what's not found is returned.
fun! s:OpenImport(line)
	" Open a temp file to do all the finding and parsing work.
	call EditTempFile()
	" Use bufnr but not bufName, because vim may not regconise long names.
	let bufNr = bufnr("%")

	let temp = substitute(a:line, '^[[:space:]]*import[[:space:]]\+\([^;]\+\);.*$', '\1', '')

	let found = -1
	let dir = ""
	let i = ItemCounts(s:docDirs, ';')
	while (i > 0)
		let i = i -1
		let javadocPath = GetItem(s:docDirs, ';', i)

		" This line imports a package.
		if (stridx(temp, '*') > 0)
			let dir = substitute(strpart(temp, 0, stridx(temp, '*')), '\.', '/', 'g')
			if (filereadable(javadocPath . dir . "package-frame.html"))
				let s:overviewPage = javadocPath . "overview-frame.html"
				let s:packagePage = javadocPath . dir . "package-frame.html"
				let s:classPage = javadocPath . dir . "package-summary.html"

				let found = 1
				break
			endif

		" This line imports a class.
		else
			let dir = substitute(temp, '\.', '/', 'g')
			if (filereadable(javadocPath . dir . ".html"))
				let s:overviewPage = javadocPath . "overview-frame.html"
				let package = strpart(dir, 0, strridx(dir, '/'))
				let s:packagePage = javadocPath . package . "/package-frame.html"
				let s:classPage = javadocPath . dir . ".html"

				let found = 1
				break
			endif
		endif
	endwhile

	" Found the javadoc
	if (found == 1)
		call s:OpenBrowser()
	endif

	call s:RestoreOptions(&ignorecase, bufNr)

	if (found == 1)
		return ""
	else
		return s:messageHead . dir
	endif

endfun

" Function: Open the javadoc for class.  The s:DocDirs variable needs to be set
" 				  before calling this function.
"
" Parameter: class the class that wants its javadoc to be opened.
" Parameter: packages implies one of its package contains the class.
"
" Parameter: command Set it to 1 to really open or update the browser for the
" 				   given class, or set it to 0 to return the found javadoc page for
" 				   the given class.
"
" Return: If the command is 1, then an empty string is returned for successfully
" 				finding the javadoc; otherwise a message indicating what's not found
" 				is returned.
" 				If the command is 0, then a file path with the ".html" extention is
" 				returned, otherwise an error message is returned.
fun! s:OpenClass(class, packages, command)
	" Use a special regex to match the class in the javadoc
	let class = '\<\C'.a:class.'\>[^.]'

	" Need this for matching the exact class name.
	let oldIgnoreCase = &ignorecase
	set noignorecase

	" Start working on a temp file now.
	call EditTempFile()

	let bufNr = bufnr("%")
	
	" Dump all the classes names into the tempFile and build up the 
	" s:entries string.
	call s:ReadClassesNames()

	let lineNum = -1
	" Find the line that's got the matched class name and package name
	let i = Count(class)
	if (i > 0)
		call search(class, 'w')

		if (i == 1)
			let lineNum = line(".")
		else
			"Go to the line that's got the closest match against the packages.
			let lineNum = s:MatchPackage(class, a:packages)
		endif
	endif

	"This shouldn't happen
	if (lineNum <= 0)
		call s:RestoreOptions(oldIgnoreCase, bufNr)
		return  s:messageHead . a:class 
	endif

	" Get the javadocPath
	let javadocPath = s:FindJavadocPath()

	if (strlen(javadocPath) != 0)
		let s:overviewPage = javadocPath . "overview-frame.html"
		let href = s:ParseHref("", 0)
		let package = strpart(href, 0, strridx(href, '/'))
		let s:packagePage = javadocPath . package . "/package-frame.html"
		let s:classPage = javadocPath . href

		if (a:command == 0)
			call s:RestoreOptions(oldIgnoreCase, bufNr)
			return s:classPage
		endif

		" If the javadoc is generated from Sun's toolkit, at least the class page
		" should exist.
		" echo filereadable(s:overviewPage)
		" echo filereadable(s:packagePage)
		" echo filereadable(s:classPage)
		
		" This java project has no packages.
		if (!filereadable(s:overviewPage))
			let s:overviewPage = javadocPath . "allclasses-frame.html"
			" Use the package frame to display what's in current javadoc's top
			" directory
			let s:packagePage = javadocPath
		endif

		call s:OpenBrowser()
	endif

	call s:RestoreOptions(oldIgnoreCase, bufNr)

	if (strlen(javadocPath) != 0)
		return ""
	else
		return s:messageHead . a:class
	endif

endfun

" Function: Open the default pages for the javadoc.
fun! s:OpenDefault()
	" Use the first entry as the default top level javadoc directory.
	let javadocPath = GetItem(s:docDirs, ';', 0)
	call EditTempFile()
	let bufnr = bufnr("%")

	" Get a clean slate to write on.
	%d

	" Get ready to parse current html file.
	exe "r " . javadocPath . "index.html"

	let s:overviewPage = javadocPath . s:ParseHref('name="packageListFrame">', 1)
	let s:packagePage = javadocPath . s:ParseHref('name="packageFrame">', 1)
	let s:classPage = javadocPath . s:ParseHref('name="classFrame">', 1)

	" Leave the temp file open so that s:OpenBrowser can have a scratch file to
	" work on.
	call s:OpenBrowser()

	" Call the same cleanup function as the others.
	call s:RestoreOptions(&ignorecase, bufnr)

endfun

" Functions: Find the imports from current file.
" Return: A string that has all the import lines separated by ';'.
fun! s:FindImports()

	let retVal = ""
	let pattern = '\(^\s*import\s\+[^;]*;\).*'
	" Go to the begining of file and then go the first import
	exe "normal! gg"
	let temp = search(pattern)

	if (temp != 0)
		let lineNum = line(".")
		while (getline(lineNum) =~# pattern) 
			let retVal = substitute(getline(lineNum), pattern, '\1', '') . retVal
			let lineNum = lineNum + 1
		endwhile
	endif

	return retVal
endfun

" Function: Set up the vars that are needed before opening the default javadoc
" pages.
fun! s:PreOpenDefault(msg)
	let s:openDefaultNextTime = 1
	let s:previousFileName = bufname("%")
	let s:previousCursorPosition = line2byte(line(".")) + col(".")
	return "Don't move the cursor, but press K again to see the default javadoc."
endfun

" Function: Parse a href from a line in a javadoc html file.  This function is
" javadoc dependent.
" Parameter: pattern The pattern that matches the href.
" Parameter: doSearch Pass 1 to this value if we need to do a search for the
" pattern; otherwise set it 0 if the current line already contains the href.
" Return: The href that matches the pattern, or "" if it's not found.
fun! s:ParseHref(pattern, doSearch)
	" Do a check for the parameter
	if (a:doSearch != 0 && a:doSearch != 1)
		echoerr "Invalid parameter value"
	endif

	" Seach not found
	if (a:doSearch == 1 )
		if (search(a:pattern, 'w') == 0)
			return ""
		endif
	endif

	let line = getline(".")
	if (ItemCounts(line, '"') == 7) 
		" This is the first class or interface
		let temp = GetItem(line, '"', 3)
		if (temp !~# '\s') " we got it, there's no space
			return temp
		endif
	endif

	return GetItem(line, '"', 1)

endfun

" Function: Test if the cursor has changed.
" Return:	Returns 1 for cursor has changed, otherwise 0
" Remark: b:changedtick can be used to determine the change as well.
fun! s:CursorChanged()
	return s:previousFileName !=# bufname("%") ||
		     \ s:previousCursorPosition != line2byte(line(".")) + col(".")
endfun

" Function: Find the class name for the word (should be a java variable, or a
" real java class name) under the cursor.  If the word is a class name, then
" that class name is returned. When the variable is initialised with the new
" keyword, then the class name will be the name of the exact class, but not its
" interface or super class.  If no other infomation is found from the source
" file, i.e. the variable is not initialised through the keyword - new, then the
" interface or super class name will be returned.  
" Ruturn: If the class name is found, then its name will be returned, otherwise
" an empty string "" is returned.
fun! s:FindClassName()

	" If we need to care about the method, then we can use "<cWORD>" to get the
	" whole string.
	let word = expand("<cword>")

	let lineNum = line(".")
	let line = getline(".")

	" word is actually a class.
	" e.g. String str;
	"       ^ (cursor is at this word)
	if (line =~# word.'\s\+\w\+')
		return word
	endif

	" word is actually a class.
	" e.g. new JPanel();
	"          ^ (cursor is at this word)
	if (line =~# 'new\s\+' . word . '(')
		return word
	endif

	" word is an exception class for
	" e.g. throws IOException
	"              ^ (cursor is at this word)
	if (line =~# 'throws\s\+\(\w\+,\s\+\)*' . word)
		return word
	endif

	" word is a super class
	" e.g. extends JPanel
	"              ^ (cursor is at this word)
	if (line =~# 'extends\s\+' . word)
		return word
	endif

	" word is an interface
	" e.g. implement ActionListener
	"              ^ (cursor is at this word)
	if (line =~# 'implements\s\+\(\w\+,\s\+\)*' . word)
		return word
	endif

	" word is a type
	" e.g. class ConcreteCommand
	"              ^ (cursor is at this word)
	" or interface Command
	"              ^ (cursor is at this word)
	if (line =~# '\(class\|interface\)\s\+' . word)
		return word
	endif

	" word may be a global
	" Note: The command 'gD' doesn't work very well
	" For example, it fails on the file
	" E:\Documents and Settings\Kid\Desktop\JBrowser\src\FileCommand.java
	" when the cursor is on "file"
	exe "normal! gD"

	" It is a global
	if (lineNum != line("."))
		" Get back to where the cursor was
		let lineNum = line(".")
		let pos = col(".")

		" Sometimes "gD" will jump to the import line, sometimes even a comment
		" line.  Anyway we'll fix it here.
		" 1. Fix the case when gD jumps to an import line.
		if getline(lineNum) =~# '^\s*import\s\+\([^;]\+\);.*$'
			let className = substitute(getline(lineNum), '.*\.\([^;]*\);.*', '\1', '')
			" The import line imports a class but not whole package, e.g. import java.awt.*;
			if (className !~# '^\*$')
				return className
			endif

		" 2. Fix the case when gD jumps to a comment line
		elseif IsInsideComment(pos, lineNum) == 1
			" We just don't return and let the current word to be parsed again 
			" after this if-else branches.
		
		" 3. Assume gD is on a truly global now.
		else
			" TODO lookup the initialisation statement that's got the keyword new.
			" e.g. inputStream = new FileInputStream(...)
				return ExtractClassName(lineNum, word)
		endif
	endif

	" Undo the effect of gD
	exe "normal! \<c-o>"

	let lineNum = line(".")
	" Searching backward for word's belonging class
	while (lineNum != 0)
		let line = getline(lineNum)

		" e.g. Object obj = new Object();
		"              ^ (curosor is at this word)
		if (line =~# '\<'.word.'\>\s*=\s\+new\s\+\w\+(')
			let className = ExtractClassName(lineNum, word)
			if (strlen(className) > 0)
				return className
			endif

		" e.g. private String str;
		"                     ^ (curosor is at this word)
		elseif (line =~# '\C\u\w*\s\+\<'.word.'\>')
			let className = ExtractClassName(lineNum, word)
			if (strlen(className) > 0)
				return className
			endif
		endif

		let lineNum = lineNum - 1
	endwhile

	" We assume if the current word begins with an upper case letter
	" then it's a class name.
	if (word =~# '^\C\u\w*')
		return word
	else 
		return "" "className not found
	endif

endfun

" Function: Restore the changed options and wipe out the unwanted buffer.
fun! s:RestoreOptions(ignoreCase, bufNr)
	if (a:ignoreCase == 1)
		set ignorecase
	else
		set noignorecase
	endif

	" Reset the entries string.
	let s:entries = ""

	exe "bwipe " . a:bufNr
endfun

" Function: This function can only be called if the current buffer is editing a
" temp file.  It read all the classes names into the current file.
" and build up the a:entries string.
fun! s:ReadClassesNames()
	" Get a clean slate to write on.
	%d

	let i = ItemCounts(s:docDirs, ";")
	" Dump all the classes into a file.
	while (i > 0)
		let i = i - 1
		" The current list for all the classes
		let javadocPath = GetItem(s:docDirs, ";", i)

		if (!filereadable(javadocPath."allclasses-frame.html"))
			" echoerr javadocPath . " is not a valid directory.  
			" \Please check s:Roots in Javadoc.vim"
			continue
		endif

		" Make the entry pair so that we know which class (line) belongs
		" to which javadoc top level directory later.
		let lineContent = line(".") + 1 . s:separator . javadocPath
		" Note the last entry will have the first linenumber and javadocpath pair
		let s:entries = lineContent . s:entrySeparator . s:entries

		" Put a line here to make sure the line that contains the matched class
		" can always fall into the range of two consecutive entries.  Actually,
		" the exact value for the lineContent doesn't really matter.
		put = lineContent
		" Dump the classes names for the current javadocpath.
		exe "silent r " . javadocPath . "allclasses-frame.html"
		" r creates an alternate file and we don't want it.
		bw #
		exe "normal! G"
	endwhile
endfun

" Function: Find the top level javadoc directory for the current line (in the
" classesnames file), which should have the href for the class.
" Return: Return the javadoc path. If the path is not found, then an empty
" string is returned.
fun! s:FindJavadocPath()

	" A simplified view of the current bufer (tempFile).
	" +--------------------------+
	" |current entry             |\ 
	" |                          | \ 
	" |                          |  \
	" |                          |   \
	" |lineNum (current is the   |    ) current classes list
	" |desired javadoc path      |   /
	" |because lineNum sits      |  /
	" |between current and next  | /
	" |entry)                    |/
	" +--------------------------+
	" |next entry                |\
	" |                          | \ 
	" |                          |  \ 
	" |                          |   \ 
	" |                          |    ) next classes list
	" |                          |   /
	" |                          |  /
	" |                          | /
	" |                          |/
	" +--------------------------+

	" We are on a line that's got the href for the needed class.
	let lineNum = line(".")

	" i is for the number of top level directories.
	let i = ItemCounts(s:entries, s:entrySeparator, 'exact')
	" Scanning forward to find the correct javadocpath
	while (i > 0)
		let i = i - 1
		let currentEntry = GetItem(s:entries, s:entrySeparator, i)
		let entryLineNum = GetItem(currentEntry, s:separator, 0)

		" If it's the last one so it's got to have the desired javadoc path.
		if (i == 0)
			return GetItem(currentEntry, s:separator, 1)
		endif

		" Go to see the next list
		let nextEntry = GetItem(s:entries, s:entrySeparator, i-1)
		let nextEntryLineNum = GetItem(nextEntry, s:separator, 0)

		" The lineNum sits between the first entryLineNum and the 
		" next one, so the current one is the desired javadoc path.
		if (entryLineNum < lineNum && lineNum < nextEntryLineNum)
			return GetItem(currentEntry, s:separator, 1)
		endif
	endwhile

	return ""

endfun

" Function: Go to the line that's got the closest match for the class.  This
" function is javadoc dependent.
" Parameter: class The name of the class.
" Parameter: packages Implies the class might be contained in one of them.
" Return: The line number that's got the match, otherwise -1.
fun! s:MatchPackage(class, packages)
	
	let oldLineNum = line(".")

	while (1 != 0)

		" We are already on a matched line, so get the href.
		let href = s:ParseHref("", 0)
		let package = substitute(strpart(href, 0, strridx(href, '/')), '/', '.', 'g')
		if (stridx(a:packages, package) != -1)
			return line(".")
		endif

		" Go on to the next matched line
		call search(a:class, 'w')

		" This is should not happen, if the java source code compiles.
		if oldLineNum == line(".")
			return -1
		endif
	endwhile

endfun

" Function: If there is no instance of vim that edits java source code
" then we should clean the cookie, so the browser won't do nonsense updates.
" 
" The incorrect updates can happen in the following senario. We're editing
" some java code again after quiting an previous edit session, which hasn't
" stopped the browser to accept update requests.  Later we open some javadoc by
" using this script again, then we'll have TWO browsers displaying the same
" javadoc, which can be quite annoying especially when the number of browsers
" goes up.
fun! s:CleanCookie()
	if (s:ReuseBrowser == 0)
		return
	endif

	call EditTempFile()
	let servers = substitute(serverlist(), '\W', ';', 'g')
	let shouldClean = 1

	let i = ItemCounts(servers, ';', 'exact')
	while (i > 0)
		let i = i - 1
		let server = GetItem(servers, ';', i)

		if (server =~# '\<' . v:servername . '\>')
			continue
		endif

		let reply = RemoteExecute(server, '&filetype')
		if (reply =~# '\<java\>')
			let shouldClean = 0
			break
		endif
	endwhile

	if (shouldClean == 1)
		call s:Refresh(0)
	endif

	" No need to cleanup the temp file, because we're
	" quiting vim anyway.

endfun

" Function: Changed the value of s:sessionID in the cookie file, but the real
" s:sessionID is unchanged, so that we can open a new browser later.  
" Parameter: interval this is the number of seconds that the refreshing should
" take.
fun! s:Refresh(interval)
	" We're not really changing the s:sessionID. We just put down an invalid
	" s:sessionID in the cookie file.
	"
	" Tell the applet don't update the frames.  The javascript in the Javadocapplet html
	" page will parse the put line to stop updating frames.  
	"
	" When this script sees an unmatched s:sessionID in the file it'll open a new
	" browser and reset the s:sessionID as well.

	put='@~stopupdate'
	exe "silent .w! " . s:cookie
	" w creates an alternate file and we don't want it.
	bw #

	if (a:interval > 0)
		exe "normal! u"
		echon "Refreshing..."
		exe a:interval."sleep"
		exe "normal! \<C-L>"
	endif

endfun

" Function: Get the s:sessionID from peers
" Return: A string for the s:sessionID, if it's not found then an empty string
" is returned.
fun! s:PeersSessionID()

	let servers = substitute(serverlist(), '\W', ';', 'g')

	let i = ItemCounts(servers, ';', 'exact')
	while (i > 0)
		let i = i - 1
		let server = GetItem(servers, ';', i)

		let reply = RemoteFunction(server, 'GetSessionID')
		if (strlen(reply) > 0)
			return reply
			break
		endif

	endwhile

	return ""

endfun

" Function: Test if the browser is running on behalf of this script.
" Return: 1 if the browser is running otherwise -1 for not running.
fun! s:IsBrowserRunning()

	" The cookie file doesn't exist, this probably the first time for the user to
	" use this script.
	if (!filereadable(s:cookie))
		return -1

	" Check if s:sessionID exists in other instances of vim.
	elseif (strlen(GetSessionID()) == 0)
		let s:sessionID = s:PeersSessionID()
			if (strlen(GetSessionID()) == 0)
			" This the first instance of vim that edits a java code,
			" so the browser can't be running already.
				return -1
			else
				return 1
			endif

	" Now the cookie file does exist and we want to check 
	" if the file has got a valid s:sessionID.
	else
		let temp = s:ExtractSessionID()
		" The current s:sessionID is fine.
		if (temp ==# s:sessionID)
			return 1

		" The browser has exited or s:Refresh(interval) is called.
		else
			return -1
		endif

	endif
endfun

fun! s:ExtractSessionID()
	" Get a clean slate to write on.
	%d
	exe "r " . s:cookie
	bw #
	let line = getline(".")
	return strpart(line, 0, stridx(line, '@'))
endfun

" Function: Open a standard javadoc window, with package list on the
" overview-frame (top-left frame), packages on the package-frame (bottom-left
" frame), and the current class on the class-frame (right frame).  
"
" The current buffer needs to be editing a temp file, so that it can write the
" needed html code onto it without messing up the contents in the java source
" file.
fun! s:OpenBrowser()

	if (s:UseFrame == 1)

		" Just show the javadoc in a new browser
		if (s:ReuseBrowser == 0) 
			call s:BuildWithFramePage()
			" Flush the page to the auxiliary file.  We are not using the temp file
			" directly, because that can cause vim throw 'E19 Mark has invalid line
			" number" error.
			exe "silent w!" . s:javadocFile
			" w creates an alternate file and we don't want it.
			bw #
			exe "silent ! " . s:Browser . " file://" . s:javadocFile

		" We want to reuse the browser, but the browser is not running yet.
		elseif (s:IsBrowserRunning() == -1)

			" Set the s:sessionID when it's empty.
			if (strlen(s:sessionID) == 0)
				let s:sessionID = localtime()
			endif

			let oldKeepView = s:KeepView
			" We're openning the browser the first time so don't change the view now.
			let s:KeepView = 2
			" Save the sessionID and other info in the cookie.
			call s:WriteCookie()
			let s:KeepView = oldKeepView

			call s:BuildWithFramePage()
			" Flush the page to the auxiliary file.  We are not using the temp file
			" directly, because that can cause vim throw 'E19 Mark has invalid line
			" number" error.
			exe "silent w!" . s:javadocFile
			bw #
			exe "silent ! " . s:Browser . " file://" . s:javadocFile

		" The browser is up and running so just let the applet to update the frames.
		else
			" Make sure all needed files are there
			if (!filereadable(GetTempPath()."JavadocHelper.jar"))
				echoerr "Please put JavadocHelper.jar in GetTempPath() directory"
			endif
			if (!filereadable(GetTempPath()."JavadocApplet.html"))
				echoerr "Please put JavadocApplet.html in GetTempPath() directory"
			endif

			call s:WriteCookie()
		endif

	" Running a text-mode browser, probably.
	else
		exe "silent ! " . s:Browser . " file://" . s:classPage
	endif

endfun

" Function: Build the javadoc page with frame sets.
fun! s:BuildWithFramePage()
	" Get a clean slate to write on.
	%d

	" Generate a html page to display the frame sets.
	0put='<HTML>'
	1put='<HEAD>'
	2put='<script>'

	" To maximise the window
	if (s:MaxWin == 1)
		3put='self.moveTo(0,0);self.resizeTo(screen.availWidth,screen.availHeight);'
	else
	" Place the browser window on the centre
		3put='var w =  ' . s:WinWidth .';' . 'var h = ' . s:WinHeight . '; if (screen.availWidth > w && screen.availHeight > h) {window.resizeTo(w, h); window.moveTo((screen.availWidth - w)/2, (screen.availHeight - h)/2);}'
	endif

	4put='</script>'
	5put='<TITLE>'
	6put='Java 2 Platform SE'
	7put='</TITLE>'
	8put='</HEAD>'
	9put='<FRAMESET cols=\"18%,82%\" onLoad=\"window.frames[3].focus();\">'
	10put='<FRAMESET rows=\"30%,70%\">'
	11put='<FRAMESET cols=\"0%, 100%\" frameborder=\"0\" framespacing=\"0\" border=\"0\">'

	if (s:ReuseBrowser == 1)
		12put='<FRAME src=\"JavadocApplet.html\" marginheight=\"0\" marginwidth=\"0\" scrolling=\"no\">'
	else
		12put='<FRAME marginheight=\"0\" marginwidth=\"0\" scrolling=\"no\">'
	endif

	13put='</FRAME>'
	14put='<FRAME name=\"packageListFrame\" src=\"' . s:overviewPage. '\">'
	15put='</FRAMESET>'
	16put='<FRAME name=\"packageFrame\" src=\"' . s:packagePage . '\">'
	17put='</FRAMESET>'
	18put='<FRAME name=\"classFrame\" src=\"' . s:classPage . '\">'
	19put='</FRAMESET>'
	20put='</HTML>'
endfun

" Function: write the change into the cookie file so the browser will display
" the new javadocs.
fun! s:WriteCookie()
	" Get a clean slate to write on.
	%d

	" The format for this line is documented at JavadocHelper#setUpdateID(String).
	" localtime() is used as the update ID which will trigger an automatic update
	" of the frames.
	0put=s:sessionID.'@'. localtime(). '~' . s:overviewPage . '~' . s:packagePage . '~' . s:classPage . '~' . s:KeepView
	exe "silent w!" . s:cookie
	" w creates an alternate file and we don't want it.
	bw #
endfun

