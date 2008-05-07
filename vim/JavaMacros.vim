"Make sure this file is only sourced once
if exists("JavaMacrosSourced")
	finish
endif
let JavaMacrosSourced = "true"

" The function CompileJavaFile calls functions in this script.
exe "so " . g:VIMMACROSPATH. "Javac.vim"
" Need some utilities from this script.
exe "so " . g:VIMMACROSPATH. "Functions.vim"
" Need some utilities from this script.
exe "so " . g:VIMMACROSPATH. "JavaUtil.vim"

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~                    Key bindings and commands                         ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
nnoremap <silent> ;c :silent call <SID>CompileJavaFile()<CR><Left><Right>
nnoremap <silent> ;v :silent call <SID>RunAppletViewer()<CR>
nnoremap <silent> ;r :silent call <SID>RunJava()<CR>
nnoremap <silent> ;t :silent call <SID>EditSourceOrTest()<CR>
command! Html silent call <SID>AppletHtmlFile()

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~                   Short Cut for Often Used Words                     ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ca mr     silent\ !java %:t:r
ia Sop    System.out.println
ia echo   System.out.println
ia cnull  <code>null</code>
ia ctrue  <code>true</code>
ia cfalse <code>false</code>

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~                          User Defined Vars                           ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" The relative path for the build directory with repect to src directory.
let s:Build = '../build/class'
" The path for the test directory with respect to the src directory.
" Test cases have to be in the package - 'test'
let s:Test = "../build"

" The directory name that contains all the java source code.
let s:MainSrc = "src"
" The directory name that contains all the source code for test cases.
let s:TestSrc = "test"

" This value says how many levels shallower is the source code for the test case
" package than the those for the main package.  This value can be 0, if
" they are at the same level. Negative integer says how many level the main
" package is nested deeper than the test cases, or positive if the test case
" package is shallower than main package.
let s:Shallow = 1

" Do we use J2SE 1.4 or not?
let s:UseLastestJdk = "true"

" Setup some vars for 1.4
if (s:UseLastestJdk =~# "true")
	" Enable the assert keyword
	let s:JavaSource = " -source 1.6 "
	let s:EnableAssertion = " -ea "
else
	let s:JavaSource = ""
	let s:EnableAssertion = ""
endif

" The argument to run junit in gui
let s:junitGui = "--gui"

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~                              Script Vars                             ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
let s:classPath = $CLASSPATH

let g:JavacUseLint = 0

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~             Directory Tree for A Sample Project                      ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" The reason why src and test is in the same directory level, insteading of 
" test being included in src, is because this provides a better parallel 
" view of the source code diretory tree.  So the packages in src can be 
" directly mapped to the packages in test.  For exmaple, if there a package
" called "sprite" in src, then the directory structure for this package is
" "src/sprite", and the test package will be "test/sprite", but not
" "src/test/sprite".
"
"  project-+
"          |- src  [ package org.xxx.yyy.zzz ]
"		   |
"          |- test [ package test.org.xxx.yyy.zzz ] 
"          |       (Test case package is nested one level shallower than main package)
"		   |
"          |- build +         
"					|- classes +
"					|          |(directory for package1)
"					|          |- .
"					|          |
"					|          |-(top level class files)
"                   | 
"                   |- test+
"                          |( test class files )
"					       |
"					       |- (directory for test.package1 
"					       | 
"					       |- . 

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~                    			Global Functions                             ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" Function: Compile the current java source file.  
" If the compilation is OK, then the class file will go to the build directory
fun! s:CompileJavaFile()
	let classPath = s:classPath
	let build = ""

	silent w
	" Change the current directory to where the source file lies in
	silent cd %:p:h

	let packageName = FindPackageName('/')
	" Find the build directory based on the package.
	let build = s:FindBuild(packageName)
	if strlen(packageName) > 1
		" Once we've found the correct directory for build, 
		" the package directory tree will be built up 
		" for the compiler based no the build's directory.
	  " An example directory tree for build is shown above.
		let test = s:FindTest(packageName)
	endif

	" Find the desired directory to put all the class files
	" 1. The current file is a test file and it's in a java project, 
	"		 i.e. has been imported to CVS.  
	"    An example directory tree for such probject is shown below.
	if (packageName =~# '^test' && isdirectory(test))
		let class = test
		" Normally, test files import the core classes that are being tested.
		" so include the build.
		let classPath = classPath . ';' . build . ';' . test . ';'

	" 2. The current file is a source file and it's in a java project, 
	"    i.e. it's been imported in CVS repositry.
	"    An example directory tree for such probject is shown below.
	elseif isdirectory(build)
		let class = build
		let classPath = classPath . ';' . build . ';'

	" 3. This is a non-project file, 
	"    so put the class file in the current directory
	else
		let class = '.'
	endif

	if isdirectory(build . '/../lib')
		let dirs = substitute(glob(build . "/../lib/*.jar"), '\n', ';', 'g')
		let classPath = classPath . ';' . dirs
	endif

	let lint = ''
	if (g:JavacUseLint)
		let lint = '-Xlint'
	endif

	" '-g' is for generating all debugging information
	silent call InvokeJavac('javac', s:JavaSource, '-g:lines,vars,source', 
				\ '-deprecation', '-classpath', classPath, '-encoding utf8', 
				\ '-d ' . class, '-extdirs', g:MYJAVALIB, lint, expand('%'))
endfun

let g:JavaMain=""
" Function: Run the java application. This assumes the class 
" in the current source code has the main method.
fun! s:RunJava()
	let classPath = s:classPath

	silent cd %:p:h

	let className = expand("%:t:r")
	let packageName = FindPackageName('/')
	let build = s:FindBuild(packageName)
	let test = s:FindTest(packageName)

	let target = className

	" This source code is within a package
	if strlen(packageName) > 1
		let build = s:FindBuild(packageName)
		let target = packageName . className
	endif

	if packageName =~# '^test' && isdirectory(test)
		" include the class files for the main classes
		let classPath = classPath . ';' . build . ';' . test . ';'
		let target = target . " " . s:junitGui
	elseif isdirectory(build)
		let classPath = classPath . ";" . build . ";"
		" Pass the class name as the argument. 
		" So we can use refelction to access the class.
		let target = substitute(target . " " . target, '/', '.', 'g')
	endif

	if strlen(packageName) == 0 && className =~# 'Test$'
		let target = target . " " . s:junitGui
	endif

	if isdirectory(build . '/../lib')
		let dirs = substitute(glob(build . "/../lib/*.jar"), '\n', ';', 'g')
		let classPath = classPath . ';' . dirs
		" echoerr classPath
	endif

	if (strlen(g:JavaMain) > 0)
		let target = g:JavaMain
	endif

	silent exe "!start java -Xmx200m -Djava.ext.dirs=".g:MYJAVALIB . " -cp ".classPath . " " 
	\. s:EnableAssertion . target
endfun

" Function: Run the appletviewer for the current java source file or the html
" file
fun! s:RunAppletViewer()
	silent cd %:p:h

	let packageName = FindPackageName('/')
	let build = s:FindBuild(packageName)
	let filenameRoot = expand("%:r")
	let htmlFile = filenameRoot . ".html"

	if isdirectory(build)
		let htmlFile = build . '/' . htmlFile
		let filenameRoot =  build . '/'. filenameRoot
	endif

	if &filetype == "html"
		exe "silent !start appletviewer " . htmlFile
		return
	endif

	if &filetype == "java" && filereadable(htmlFile)
		exe "silent !start appletviewer " . filenameRoot .".html"
	endif

endfun

" Function: Create an html file template for applet
fun! s:AppletHtmlFile()
	let filenameRoot = expand("%:r")
	let htmlFile = filenameRoot . ".html"
	if filewritable(htmlFile) == 1
		echo "File " . htmlFile " exists"
		exe "e " . htmlFile
	else
		exe "e " . htmlFile
		exe "normal! a<applet code=" . filenameRoot .".class width=500 height=500>\<CR>\<Esc>"
		exe "normal! a</applet>"
		exe "w"
	endif

endfun

" Function: Generate a class template with the file name as the class name
fun! PutClassName()

	let filename = expand("%:r")
	" Test file is handled differently
	if filename =~# '.\+Test$'
		return
	endif

	call JCommentWriter()
  	exe "normal! a\<CR>\<Esc>"

	let packageName = ""
	let path = expand("%:p")
	if (path =~? '.*src')
		let temp = substitute(substitute(path, '.*src\\', '', ''), '\\', '.', 'g')
		let temp = substitute(substitute(temp, '.*src/', '', ''), '/', '.', 'g')
		let packageName = substitute(temp, "." . expand("%:t"), '', '')
	endif

	if (strlen(packageName) > 0)
		exe "normal! apackage " . packageName . "; \<CR>\<Esc>"
		exe "normal! a\<CR>\<Esc>"
	endif

	exe "normal! apublic class " . filename . "\<CR>\<Esc>"
	exe "normal! a{\<CR>\<Esc>"

endfun

" Function: Switch between test file and source file.  The test case file has to
" have the extentions as "Test.java", for exmaple "SimpleTest.java"
fun! s:EditSourceOrTest()
	let fileName = expand("%")

	let packageName = FindPackageName('/')
	if (fileName =~# 'Test\.java$')
		call s:EditSourceFile(packageName)
	elseif (packageName !~# '^test' && fileName =~# '\.java$')
		call s:EditTestFile(packageName)
	endif

endfun

" Because invoking javah is a bit slow, so we cache all the templates.
let s:templateCache = ""
" Function: Insert a template for the given interface.
" Parameter: interfaceName This has to be fully qualified interface name.
"
" Exmaple: Suppose the we're editing the following java code.
" 		private static class MyListener implements MouseListener
" 		{
" 		}
" 		^
"     place the cursor at this point and then on the command line
"     :silent call InsertJavaTemplate("java.awt.event.MouseListener")
"     then you should see the template for the MouseListener being inserted. 
"	  Insert a wrapper class 
"	  :silent call InsertJavaTemplate("javax.mail.internet.MimeMessage", 'message', 'Communication')
"                                                                           ^              ^
"                                                                       inner field     class name
fun! s:InsertJavaTemplate(interfaceName, ...)

	let template = ""
	if (!Hashtable_exist(a:interfaceName, s:templateCache))

		if (a:0 > 0)
			let template = s:GenerateTemplate(a:interfaceName, a:1, a:2)
		else
			let template = s:GenerateTemplate(a:interfaceName)
		endif

		let s:templateCache = Hashtable_put(a:interfaceName, template, s:templateCache)
	else
		let template = Hashtable_get(a:interfaceName, s:templateCache)
	endif

	" Some ugly fiddling to paste and format the template.
	let oldZ = @z
	let @z = template
	exe 'normal! "z[p'
	let @z = oldZ
	exe 'normal! mz'
	call search('{', 'b')
	silent exe 'normal! =%'
	exe "normal 'z"
	call search('{', '')

endfun

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~                     Script functions                                 ~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 
" Edit the test file for the current class, i.e. the one's source code being
" edited at the moment if the directory path for test file doesn't exist, then
" it'll be created.
fun! s:EditTestFile(packageName)
	let filenameRoot = s:GetFileRoot()
	let sourceDirectory = expand("%:p:h")

	let test = "."
	if (strlen(a:packageName) > 0)
		if (has("win32"))
			let test = substitute(sourceDirectory, '\\'.s:MainSrc.'\>\\\=', '\\'.s:TestSrc.'\\', '')
		else
			let test = substitute(sourceDirectory, '/'.s:MainSrc.'/>/\=', '/'.s:TestSrc.'/', '')
		endif
	endif

	" Create the test directory if we really are in a java project.
	if (!isdirectory(test) && test != sourceDirectory)
		if (!Mkdir(test, '/'))
			echoerr "Can't create the test directory: " . test
			let testFile = filenameRoot . "Test.java"
		else
			" echo "Test Directory " . test . " has been created"
			let testFile = test . "/" . filenameRoot . "Test.java"
		endif
	else
		let testFile = test . "/" . filenameRoot . "Test.java"
	endif

	exe "e " . testFile
	" The testFile has nothing written on it.
	if (line2byte(line("$")) == -1)
		call s:StartNewTestFile(a:packageName, filenameRoot . 'Test')
	endif

endfun

fun! s:StartNewTestFile(packageName, className)
	let i = 1
	if (strlen(a:packageName) > 1)
		let pkgName = strpart(a:packageName, 0, strlen(a:packageName)-1)
		let pkgName = substitute(pkgName, '/', '.', 'g')
		0put = 'package test.' . pkgName . ';'
		" The number '2' is a workaround for Vim's misbehaviour of jumping to the next line
		" when putting the method contents, such as super(name), etc.
		2put = 'import ' . pkgName . '.*;'
		let i  = 3
	endif

	exe i + 0"put =  'import junit.framework.*;'"
	exe i + 1"put =  ''"
	exe i + 2"put =  'public class ' . a:className . ' extends TestCase'"
	exe i + 3"put =  '{'"
	exe i + 4"put =  '	public ' . a:className . '(String name)'"
	exe i + 5"put =  '	{'"
	exe i + 6"put =  '		super(name);'"
	exe i + 7"put =  '	}'"
	exe i + 8"put =  ''"
	exe i + 9"put =  '	public static Test suite()'"
	exe i + 10"put =  '	{'"
	exe i + 11"put =  '		return new TestSuite('. a:className. '.class);'"
	exe i + 12"put =  '	}'"
	exe i + 13"put =  ''"
	exe i + 14"put =  '	public static void main(String args[])'"
	exe i + 15"put =  '	{'"
	exe i + 16"put = '		if (args != null && args[0].equals(\\\"' . s:junitGui . '\\\"))'"
	exe i + 17"put =  '			junit.swingui.TestRunner.run(' . a:className . '.class);'"
	exe i + 18"put =  '		else'"
	exe i + 19"put =  '			junit.textui.TestRunner.run(suite());'"
	exe i + 20"put =  '	}'"
	exe i + 21"put =  '}'"

	" Line 12 seems to be a good place to start writing test code.
	12
endfun

" Edit the source file for the given test file
fun! s:EditSourceFile(packageName)
	let testFile = expand("%:p")

	let sourceFile = testFile
	if (strlen(a:packageName) > 0)
		if (has("win32"))
			" substitute the last pattern
			let sourceFile = substitute(testFile, '\(.*\)\\'.s:TestSrc.'\>\\\=', '\1\\'.s:MainSrc.'\\', '')
		else
			" substitute the last pattern
			let sourceFile = substitute(testFile, '\(.*\)/'.s:TestSrc.'/>/\=', '\1/'.s:MainSrc.'/', '')
		endif
	endif

	let sourceFile = substitute(sourceFile, 'Test\.java', '.java', '')
	exe "e " . sourceFile
endfun

" Get the file root. Note: expand("%:r") doesn't work if the file is the in
" current path, i.e. the output of the command pwd is different from the current
" file's path
fun! s:GetFileRoot()
	let fileRoot = expand("%:r")

	if (has("Win32"))
			return GetLastItem(fileRoot, '\\')
	else
			return GetLastItem(fileRoot, '/')
	endif

	return fileRoot " the current file is in the same path as the output of pwd
endfun

" Find the build directory for the currrent source file.
" packageName is the return value of FindPackageName
fun! s:FindBuild(packageName)
	let srcDir = FindSrcDirectory(a:packageName)
	if (isdirectory(srcDir.'../build/WEB-INF/classes'))
		return srcDir.'../build/WEB-INF/classes'
	elseif (isdirectory(srcDir.'../build/class'))
		return srcDir.'../build/class'
	elseif ( isdirectory(srcDir.'../build') && a:packageName !=# "^test")
		return srcDir.'../build/' " This is for backward-compability.
	elseif ( isdirectory(srcDir.'/build') && a:packageName =~# "^test")
		return srcDir.'/build/' " This is for backward-compability.
	elseif (exists("s:Build"))
		return FindSrcDirectory(a:packageName) . s:Build
	else
		return '' "Assume the classes are at the same level of the source.
	endif
endfun

" Find the test directory fo the current source file.
" packageName is the return value of FindPackageName
fun! s:FindTest(packageName)
	return FindSrcDirectory(a:packageName) . s:Test
endfun
	
" Function: Find the template the for the given interfaceName.
fun! s:GenerateTemplate(interfaceName, ...)
	let classPath = s:classPath
	let packageName = FindPackageName('/')
	let build = s:FindBuild(packageName)
	let test = s:FindTest(packageName)
	let classPath = classPath . ';' . build . ';' . test . ';'
	if isdirectory(build . '/../lib')
		let dirs = substitute(glob(build . "/../lib/*.jar"), '\n', ';', 'g')
		let classPath = classPath . ';' . dirs
		" echoerr classPath
	endif

	call EditTempFile()
	exe "r! javap -extdirs " . g:MYJAVALIB . " -classpath " . classPath . 
				\ " " . a:interfaceName

	" All the interface methods end with a ";"
	v/;/d

	" Delete the leading space, the "abstract" keyword and the package names
	%s/^\s\+\|abstract \|\w\+\.//eg

	" Insert the name of the parameter for premitive types
	let i = 0
	let pattern = '\<\l\h\+\>\%(,\|)\)\@='
	g/./call search(pattern) | exe 's/' . pattern .'/\=submatch(0) . " " . submatch(0). i /e' | let i = i + 1

	" Insert the name of the paramter for Object types 
	let pattern = '\(throws.*\)\@<!\u\w\+\%(,\|)\|\[\]\()\|,\)\)\@='
	g/./call search(pattern) | exe 's/' . pattern .'/\=submatch(0) . " ". tolower(strpart(submatch(0), strlen(submatch(0)) - strlen(GetItem(submatch(0), "\\u", ItemCounts(submatch(0), "\\u")-1)) - 1 )). i /e' | let i = i + 1 

	" Only the public methods are wanted
	%v/\<public\>/d

	" $ points to a inner class object
	%s/\$/\./eg

	" static methods are not wanted
	silent g/\<static\>/d

	" get rid of the synchronized key word
	silent g/\<synchronized\>/d

	" Replace ; with a pair of curly braces
	if (a:0 == 0)
		g/./if line(".") != line("$") | s/;/{}/ | else | s/;/{}/ | endif
	else

		" delete all the ;
		%s/;//g

		exe "normal! gg"
		while line(".") <= line("$")
			let content = getline(".")
			" get the method name
			let method = GetItem(GetItem(content, '(', 0), ' ' , ItemCounts(GetItem(content, '(', 0), ' ', 'exact'))
			let params = s:GetParamters(GetItem(GetItem(content, '(', 1), 'throws', 0))

			" This is a method that return no value.
			if (content =~# 'public void')
				exe "normal! o{\<CR>\<Tab>" . a:1 . "." . method . "(" .params. ";\<CR>}\<CR>\<Esc>"
			" This is a constructor.
			elseif(content =~# 'public \u\w\+(')
				if (strlen(params) == 0)
					let params = ")"
				endif
				exe 's/\u\w\+(\@=/' . a:2 .'/e'
				exe "normal! o{\<CR>\<Tab>super(" . params .";\<CR>}\<CR>\<Esc>"
			" A normal method that returns a value.
			else
				exe "normal! o{\<CR>\<Tab>return " . a:1 . "." . method . "(" . params . ";\<CR>}\<CR>\<Esc>"
			endif

			if (line(".") == line("$"))
				break
			endif

			" go to next line
			exe "normal! j"
		endwhile

		exe "normal! ggOprivate " . a:1 . ";\<Esc>"
	endif

	" move the throw statement next line
	" silent %s/throw/&/

	" delete the white space at the end
	" silent %s/)\s\+$/)/

	" store the content of this file in a register temporarily
	let oldZ = @z
	exe 'normal! G"zygg'
	bw %
	let retVal = @z
	let @z = oldZ
	return retVal
endfun

fun! s:GetParamters(input)
	return substitute(substitute(substitute(a:input, '\w\+\(\.\w\+\)* ', '', 'g'), '\[\|\]', '', 'g'), '\s\+$', '', '')
endfun
