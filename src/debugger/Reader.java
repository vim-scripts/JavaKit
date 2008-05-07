/* File Name  : Reader.java
 * Author     : yiuwingyip@126.com
 * Created    : 2008-04-13 15:54:34
 * Copyright  : Copyright © 2008 Yiu Wing Yip. All rights reserved.
 *
 */

import java.io.*;
import java.util.concurrent.locks.ReentrantLock;

/** 
 * A Reader can perform asynchronous read for an InputStream.
 * 
 */
public class Reader extends Thread
{
	/** 
	 * The stream to read the input.
	 */
	private InputStream input;

	/** 
	 * The lock for protectding feedback.
	 */
	private ReentrantLock lock;

	/** 
	 * Notify when a feedback is ready.
	 */
	private Object notifier;

	/** 
	 * <code>true</code> if the feedback is ready, otherwise <code>false</code>.
	 */
	private boolean ready;

	/** 
	 * The vim server that we can send the output that's not directly from the
	 * response to a jdb instruction - it's contrary to feedback.
	 */
	private String vimServerName;

	/** 
	 * The path for vim executable.
	 */
	private String vimPath;

	/** 
	 * <code>true</code> if we're using squre bracket in the command prompt,
	 * otherwise <code>false</code>.
	 */
	private boolean usingSquareBracket = false;

	/** 
	 * Can we break the read when we encounter a square braket?
	 */
	private boolean canBreakBracket = false;

	/** 
	 * Construct an object that can perform non-blocking read from <code>is</code>.
	 * 
	 * @param is The source of the input.
	 */
	public Reader(InputStream is)
	{
		notifier = new Object();
		input = is;
		lock = new ReentrantLock();
		start();
	}

	/** 
	 * Retrieve the input from InputStream.
	 */
	public void run()
	{
		while (true)
		{
			try
			{
				if (read() == false)
					break;
			}
			catch (IOException e)
			{
				e.printStackTrace();
			}
		}
	}

	/** 
	 * Read the standard output or standard error streams from jdb.
	 * 
	 * @throws IOException If there's IO error.
	 */
	private boolean read()
		throws IOException
	{
		char current = 0;
		char previous = 0;
		StringBuffer buffer = new StringBuffer();

		while (true)
		{
			int temp = input.read();
			if (temp == -1)
				return false;

			current = (char)temp;
			// This is jdb specific behaviour.  Command line is followed after a new line and "> " prompt.
			if ( (previous == '\n' || previous == 0 ) && current == '>')
			{
				temp = input.read();
				if (temp == ' ' && input.available() == 0)
					break;

				buffer.append(current);
				previous = (char)temp;
				continue;
			}

			// This is when jdb enter a thread stack.
			// Break the read if encounter digit(s) in square bracket, e.g. "thread-xxx[1] ".
			//                                                                         ^^^
			else if (current == ']' && canBreakBracket)
			{
				temp = input.read();
				if (temp == ' ' && input.available() == 0)
				{
					buffer.append(previous);
					buffer.append(current);
					break;
				}
			}

			if (usingSquareBracket)
			{
				// this a "0" trailing behind "1-9"
				if (current == 48 && canBreakBracket)
					;
				// current is not "1-9"
				else if (current < 49 || current > 57)
				{
					usingSquareBracket = false;
					canBreakBracket = false;
				}

				canBreakBracket = true;
			}

			if (current == '[')
				usingSquareBracket = true;

			if (previous != 0)
				buffer.append(previous);
			previous = current;
		}

		handle(buffer);
		return true;
	}

	/** 
	 * Handle buffer properly after the read is finished.
	 */
	private void handle(StringBuffer buffer)
		throws IOException
	{
		// it can only be locked by the worker thread
		if (lock.isLocked())
		{
			synchronized(notifier)
			{
				ready = true;
				send(buffer);
				notifier.notifyAll();
			}
		}
		else
			send(buffer);
	}

	/** 
	 * Send the read message to vim server.
	 */
	private void send(StringBuffer buffer)
		throws IOException
	{
		if (vimServerName == null || vimPath == null)
		{
			System.out.print(buffer.toString());
			return;
		}

		// Take care of " and split temp into lines.
		String temp[] = buffer.toString().replaceAll("\"", "\\\\\"").split("\n");
		// true if has started the debug output in vim.
		boolean debugOutputStarted = false;
		for (String line : temp)
		{ 
			if (line.length() == 0)
				continue; // don't send empty line.

			if (line.charAt(0) == '\r' && line.length() == 1)
				continue; // don't output return.

			if (debugOutputStarted == false)
			{
				debugOutputStarted = true;
				executeVimCommand("call DebugOutputStart()");
			}

			executeVimCommand("JdbAppend " + line);
		}

		if (debugOutputStarted)
		{
			executeVimCommand(" call DebugOutputEnd()");
			// send a empty line to clear the command line
			executeVimCommand("");
		}
	}

	/** 
	 * Execute a vim command in vim server.
	 * 
	 * @param command The command
	 */
	private void executeVimCommand(String command)
		throws IOException
	{
		String cmd = vimPath + " --servername " + vimServerName + 
					 " -u NONE -U NONE --remote-send \"<C-\\><C-N>:" + command + "<CR>\"";
		Process process = Runtime.getRuntime().exec(cmd);

		try
		{
			process.waitFor();
		}
		catch (InterruptedException e)
		{
			e.printStackTrace();
		}
	}

	/** 
	 * Require the lock before doing the write in work thread, 
	 * because we need to wait for the feedback from this reader after the write.
	 */
	public void lock()
	{
		lock.lock();
	}

	/** 
	 * Wait for the read and send the feedback to vim server to finish.
	 * only be called the worker thread.
	 * 
	 * @param serverName The vim server's name.
	 * @param path The path for vim executable.
	 */
	public void waitFor(String serverName, String path)
	{
		vimServerName = serverName;
		vimPath = path;

		synchronized(notifier)
		{
			while (ready == false)
			{
				try
				{
					notifier.wait();
				}
				catch (InterruptedException e)
				{
					break; // interrupt by DebugSession#startJdb:121 worker.interrupt 
				}
			}

			ready = false;
		}
	}

	/** 
	 * Release the lock.
	 */
	public void unlock()
	{
		lock.unlock();
	}
}
