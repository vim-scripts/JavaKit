import java.io.*;
import java.net.*;
import java.applet.Applet;

/** 
 * This class helps to display the javadoc page in the browser.
 * 
 */
public class JavadocHelper extends Applet
{
	/** 
	 * This string is used to determined whether we need to update the browser.
	 * It can be changed in the javadoc.cookie file.
	 */
	private String updateID;

	/** 
	 * The file name for the cookie.
	 */
	private static final String COOKIE = "javadoc.cookie";

	/** 
	 * A asynchronous method for reading the content of the file.
	 * 
	 * @return the content of the file, or an empty string when there's nothing
	 * in the file.
	 */
	public String getFileContent()
	{
		InputStream stream = getClass().getResourceAsStream(COOKIE);
		// The cookie file doesn't exist
		if (stream == null)
			return "";

		BufferedReader reader = new BufferedReader(new InputStreamReader(stream));

		String line = null;
		try
		{
			// only one line is needed
			line = reader.readLine();
			reader.close();
		}
		catch (IOException e)
		{
			return "";
		}

		// Line can't continue to be processed.
		if (line == null)
			return "";

		// hasn't got an updateID yet.
		if (updateID == null)
		{
			setUpdateID(line);
			return line;
		}
		else
		{
			// The updateID hasn't been updated yet.
			if (updateID.equals(extractUpdateID(line)))
				return "";
			// There is a new updateID in the file, so update it.
			else
			{
				setUpdateID(line);
				return line;
			}

		}
	}

	/** 
	 *  Put some info on the cookie which says the brower was exited.  This need
	 *  the security permission to allow write access.
	 */
	public void exitBrowser()
	{
		try
		{
			// %20 means a space in URL syntax.
			String path = getCodeBase().getPath().replaceAll("%20", " ");
			File cookie = new File(new URI("file", null, path + COOKIE, null));
			PrintWriter writer = new PrintWriter(new FileWriter(cookie), true);

			// This only puts a blank line in IE6, but that's good enough.  When
			// the javadoc.vim scripts sees an unmatched sessionID, it'll fire
			// up a new browser.  The actual value passed to println is not
			// important as long as the sessionID is different from the current
			// one.
			writer.println("@~existedBrowser");
			writer.flush();
			writer.close();
		}
		catch (IOException e)
		{
			System.out.println(e);
		}
		catch (URISyntaxException e)
		{
			System.out.println(e);
		}
	}

	/** 
	 * Set the updateID.
	 * 
	 * @param line contains the whole line about how to update the browser
	 * window.  The format for the line is like:
	 * <br>
	 * sessionID@updateID~overviewUrl~packageUrl~classUrl~keepView.
	 * <br>
	 * sessionID is used in the vim script to see if we need to open a new
	 * browser window, whereas updateID is for displaying the javadoc pages by
	 * updating each visible frame's href in the current opened browser.
	 */
	private void setUpdateID(String line)
	{
		updateID = extractUpdateID(line);
	}

	/** 
	 * Extract the updateID from line.
	 * 
	 * @param line the input line.
	 * @see #setUpdateID(String l)
	 */
	private static String extractUpdateID(String line)
	{
		String temp = line.substring(0, line.indexOf("~"));
		return temp.substring(temp.indexOf("@") + 1);
	}

	/* C:\vim\javakit\src\javakit\javadoc>keytool -genkey -alias yiuwing -keyalg RSA -validity 40000 */
	/* C:\vim\javakit\src\javakit\javadoc>jar cvf JavadocHelper.jar JavadocHelper.class */
	/* C:\vim\javakit\src\javakit\javadoc>jarsigner JavadocHelper.jar yiuwing */
}

