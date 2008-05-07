/* File Name  : DebugSession.java
 * Author     : yiuwingyip@126.com
 * Created    : 2008-04-12 08:06:40
 * Copyright  : Copyright © 2008 Yiu Wing Yip. All rights reserved.
 *
 */

import java.io.*;
import java.net.*;

/** 
 * This class represends a jdb session.  Make this app into an executable jar on
 * the command line:
 *
 *		D:\project\debugger>jar cvfm debug.jar META-INF/MANIFEST.MF *.class 
 *
 */
public class DebugSession
{
	/** 
	 * The command line string to start jdb.
	 */
	private static final String JDB_COMMAND = "jdb -connect com.sun.jdi.SocketAttach:port=8000";

	/** 
	 * The listening port for incomming connection.
	 */
	private static final int LISTENING_PORT = 8833;

	/** 
	 * The standard output reader for jdb process.
	 */
	private Reader reader;

	/** 
	 * The standard output for jdb process.
	 */
	private OutputStream output;

	/** 
	 * The notifier for new message.
	 */
	private final Object notifier;

	/** 
	 * <code>true</code> the execution of the new jdb instrution and the
	 * feedback was sent to vim sever have finished, otherwise
	 * <code>false</code>.
	 */
	private boolean finished = false;

	/** 
	 * <code>true</code> the client has sent new message to the server, otherwise <code>false</code>.
	 */
	private boolean newMessage = false;

	/** 
	 * The new message from the client.
	 */
	private String message;

	/** 
	 * The delimiter for message.
	 */
	private static final String DELIMITER = "@@@";

	/** 
	 * Construct a jdb server.
	 */
	private DebugSession()
	{
		notifier = new Object();

		try
		{
			initialiseServer();
			startJdb();
		}
		catch (IOException ioe)
		{
			ioe.printStackTrace();
		}
		catch (InterruptedException ie)
		{
			ie.printStackTrace();
		}
	}

	/** 
	 * Start the jdb process.
	 * 
	 * @throws IOException 
	 * @throws InterruptedException 
	 */
	private void startJdb()
		throws IOException, InterruptedException
	{
		// start a new jdb process.
		final Process process = Runtime.getRuntime().exec(JDB_COMMAND);
		Thread worker = new Thread()
		{
			public void run()
			{
				try
				{
					reader = new Reader(process.getInputStream());
					// Eat up the error stream, otherwise the standar output will be blocked..
					new Reader(process.getErrorStream());
					output = process.getOutputStream();
					processMessage();
				}
				catch (IOException e)
				{
					e.printStackTrace();
				}
			}
		};
		worker.start();
		process.waitFor();

		worker.interrupt();
		// Exit the program if jdb ends.
		System.exit(0);
	}

	/** 
	 * Process the new message sent by the client.
	 */
	private void processMessage()
		throws IOException
	{
		while (true)
		{
			synchronized (notifier)
			{
				// Wait for the new message.
				while (newMessage == false)
				{
					try
					{
						notifier.wait();
					}
					catch (InterruptedException e)
					{
						e.printStackTrace();
					}
				}

				String temp[] = message.split(DELIMITER);
				if (temp.length != 3)
				{
					System.out.println("Wrong input: " + message);
					finished = true;
					newMessage = false;
					notifier.notifyAll();
					continue;
				}

				String vimServerName = temp[0];
				String vimPath = temp[1];
				String instruction = temp[2];
				reader.lock();
				write(instruction);
				reader.waitFor(vimServerName, vimPath);
				reader.unlock();

				finished = true;
				newMessage = false;
				notifier.notifyAll();
			}
		}
	}

	/** 
	 * Write a instruction to jdb.
	 * 
	 * @param instruction A jdb instruction or statement.
	 * @throws IOException If there's IO error.
	 */
	private void write(String instruction)
		throws IOException
	{
		// '\r' is the ascii for enter or cartriage return.
		instruction += '\r';
		byte buffer[] = instruction.getBytes();
		output.write(buffer);
		output.flush();
	}

	/** 
	 * Start the server.
	 */
	private void initialiseServer()
		throws IOException
	{
		ServerSocket server = new ServerSocket(LISTENING_PORT);
		listen(server);
	}

	/** 
	 * Listen to client connection and retrieve the new message.
	 * 
	 * @param server The server.
	 */
	private void listen(final ServerSocket server)
	{
		new Thread()
		{
			public void run()
			{

				while (true)
				{
					try
					{
						Socket socket = server.accept();
						BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream()));
						String temp = reader.readLine();

						synchronized(notifier)
						{
							message = temp;
							newMessage = true;
							notifier.notifyAll();
						}

						synchronized(notifier)
						{
							// wait for jdb command output, ie feedback
							while (finished == false)
							{
								try
								{
									notifier.wait();
								}
								catch (InterruptedException e)
								{
									e.printStackTrace();
								}
							}

							finished = false;
						}

						OutputStream output = socket.getOutputStream();
						output.close(); // send EOF(-1).
						reader.close();
						socket.close();
					}
					catch (IOException e)
					{
						e.printStackTrace();
					}
				}
			}
		}.start();
	}

	/** 
	 * Work as a client and send the message to the server.
	 * The response from the server is printed out on the screen.
	 * 
	 * @param message The message to the server.
	 */
	private static void client(String args[])
	{
		String message = getOptionts(args);
		try
		{
			Socket socket = new Socket("localhost", LISTENING_PORT);
			PrintWriter writer = new PrintWriter(new OutputStreamWriter(socket.getOutputStream()));
			writer.println(message);
			writer.flush();

			InputStream input = socket.getInputStream();
			// If the worker thread has finished processing new message, 
			// then EOF (-1) will be read from the input.
			while (input.read() >= 0)
				;

			writer.close();
			input.close();
			socket.close();
		}
		catch (IOException e)
		{
			e.printStackTrace();
		}
	}

	/** 
	 * Compress the options into one string.
	 * 
	 * @param args -v [optional] is for vimServerName 
	 * 			   -p [optional] is for vim executable path, 
	 * 			   the remaining is for jdb instruction.
	 *
	 * @return A delimited string.
	 */
	private static String getOptionts(String args[])
	{
		String vimServerName = null;
		String vimPath = null;
		StringBuffer buffer = new StringBuffer();

		for (int i = 0; i < args.length; i++)
		{
			String temp = args[i];
			if (temp.equals("-v"))
			{
				i++;
				if (i < args.length)
					vimServerName = args[i];
				else
					break;

				continue;
			}

			if (temp.equals("-p"))
			{
				i++;
				if (i < args.length)
					vimPath = args[i];
				else
					break;

				continue;
			}

			buffer.append(temp + " ");
		}

		if (vimServerName == null)
			vimServerName = "GVIM";
		if (vimPath == null)
			vimPath = "C:\\vim\\vim71\\vim.exe";

		return vimServerName + DELIMITER + vimPath + DELIMITER + buffer;
	}

	/** 
	 * This program can work as a client or server depending on the given args.
	 * 
	 * @param args Leave this option blank if we want to start a server,
	 * 			   otherwise this program will work as a client which sends the
	 * 			   first option as the message to the server.
	 */
	public static final void main(String args[])
	{
		if (args.length > 0)
			client(args);
		else
			new DebugSession();
	}
}
