1)	Unzip the JavaKit.zip file.
2)	In _vimrc set up a variable called "g:VIMMACROSPATH" which points to the
	directory where javakit was unzipped.  Source all the javakit *.vim files in
	_vimrc.
		au FileType java :exe "so " . g:VIMMACROSPATH . "Functions.vim"
						\|exe "so " . g:VIMMACROSPATH . "JavaMacros.vim"
						\|exe "so " . g:VIMMACROSPATH . "Javadoc.vim"
						\|exe "so " . g:VIMMACROSPATH . "Javac.vim"
						\|exe "so " . g:VIMMACROSPATH . "JavaSearch.vim"
3)	In the Javadoc.vim line 51 set up the "s:Roots" variable
4)	Having done the above settings, source "Functions.vim" and on the command
	line and then "echo GetTempPath()".  
	On the command line:

		:so Functions.vim
		:echo GetTempPath()

	Move JavadocApplet.html and JavadocHelper.jar to the GetTempPath()
	directory.  When the jar file is first run, the browser may ask you to accept
	a certificate, you can click "Yes" to accept the certificate.
