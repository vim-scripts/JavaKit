

							--------------------
						============================
					^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
				Thank you for your time of using my scripts!
		Any comment or question please send to yiuwingyipAT126DOTcom
  I use WinXP, haven't got the chance to test my scripts on other platforms.


************************************ Installation *******************************
1)	Unzip the JavaKit.zip file.

2)	In JavaKit.vim set up a variable called "g:VIMMACROSPATH" which points to the
	directory where javakit was unzipped.

3)	In the Javadoc.vim line 54 set up the "s:Roots" variable.

4)	Source "Functions.vim" and on the command line and then "echo GetTempPath()",
	On the command line:

		:so Functions.vim
		:echo GetTempPath()

	Move src/javadoc/JavadocApplet.html and src/javadoc/JavadocHelper.jar to the
	GetTempPath() directory.  When the jar file is first run, the browser may
	ask you to accept a certificate, you can click "Yes" to accept the
	certificate.

5)	Source javakit.vim in _vimrc
		au FileType java :so [yourpath]/javakit.vim"


********************************** jdb session *********************************
1)	Compile the source file with '-g' flag,
		javac -g Main.java

2)	Start the java program with debugging enabled,
		java -Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=n Main
	Note the socket port is 8000 and this program should be still running after
	you set breakpoints in step 5.

3)	Put src/debugger/debugg.jar in your class path.

4)	Double click an debugg.jar to start the server.

5)	Open the source file for the debug-enabled java program, to toggle a break
	point, on normal node type "et".  For key maps and user defined commands see
	vim/JavaDebug.vim.

6)	If you're not using Windows platform or want to change the listening port,
	change the command line to start jdb at src/debugger/DebugSession.java line
	23, set an appropriate value for JDB_COMMAND.  For more details, refer to
	the source code.


******************************** compile & run ********************************
1)	Open a java file, in normal mode type ";c" to compile a file.

2)	Use ';n' or ';b' to navigate forth and back the compile errors. 

3)	If the current file has a main method, in normal mode type ";r" to run it.

4)	For other key maps see vim/JavaMacros.vim.


***************************** search & completion ******************************
1)	When you're editing a java source file, after a method starts like,
		xxx.zz
			  ^
			 (cursor at here)
	and press the key map for completion, a closest match of public members
	will be available.

2)	The completion works for generic types as well.

3)	When the cursor is on an indentifier, type 'gd' to go to its definition. 
	For other key maps see vim/JavaSearch.vim.

4)	I developed my script before vim omni feature was implemented, and the
	legacy lives on, so there is no 'omni' popups etc.


********************************** javadoc ************************************
1)	When the cursor is on an indentifier, type 'K' to go to its javadoc.

2)	If the javadoc is not found press 'K' again to open the default javadoc.

3)	There is a subtle problem with jdk 6 javadoc official's release, read
	src/javadoc/build.xml to see if your javadoc html needs to be modified.
