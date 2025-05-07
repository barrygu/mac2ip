using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Net.Sockets;
using System.Net.NetworkInformation;
using System.Text.RegularExpressions;

class ConsoleCommand
{
	public ConsoleCommand(bool bRedirectOutput = true, bool bRedirectError = false)
	{
		m_bRedirectOutput = bRedirectOutput;
		m_bRedirectError = bRedirectError;

		if (bRedirectOutput) {
			m_OutputData = new StringBuilder();
			m_OutputEvent = new AutoResetEvent(false);
		}

		if (bRedirectError) {
			m_ErrorData = new StringBuilder();
			m_ErrorEvent = new AutoResetEvent(false);
		}
	}

	public void Execute(string fileName, string arguments, int timeout = 10000)
	{
		Execute(fileName, arguments, timeout, null);
	}

	public void Execute(string fileName, string arguments, int timeout, string strInputData)
	{
		try {
			using (Process process = new Process())
			{
				process.StartInfo.FileName = fileName;
				process.StartInfo.Arguments = arguments;
				process.StartInfo.UseShellExecute = false;
				process.StartInfo.CreateNoWindow = true;

				if (strInputData != null)
					process.StartInfo.RedirectStandardInput = true;

				if (m_bRedirectOutput) {
					process.StartInfo.RedirectStandardOutput = true;
					process.OutputDataReceived += new DataReceivedEventHandler(OutputHandler);
				}

				if (m_bRedirectError) {
					process.StartInfo.RedirectStandardError = true;
					process.ErrorDataReceived += new DataReceivedEventHandler(ErrorHandler);
				}

				process.Start();

				if (m_bRedirectOutput)
					process.BeginOutputReadLine();
				if (m_bRedirectError)
					process.BeginErrorReadLine();

				if (strInputData != null)
				{
					process.StandardInput.Write(strInputData);
					process.StandardInput.Close();
				}

				if (!process.WaitForExit(timeout))
					throw new Exception("Process execution timeout.");

				m_ExitCode = process.ExitCode;
			}
		}

		finally
		{
			if (m_bRedirectOutput)
				m_OutputEvent.WaitOne(timeout);
			if (m_bRedirectError)
				m_ErrorEvent.WaitOne(timeout);
		}
	}

	public int ExitCode { get { return m_ExitCode; } }

	public string OutputData { get { return m_bRedirectOutput ? m_OutputData.ToString() : null; } }
	public string ErrorData { get { return m_bRedirectError ? m_ErrorData.ToString() : null; } }

	public bool RedirectOutput {
		get { return m_bRedirectOutput; }
		set { m_bRedirectOutput = value; }
	}

	public bool RedirectError {
		get { return m_bRedirectError; }
		set { m_bRedirectError = value; }
	}

	private void OutputHandler(object process, DataReceivedEventArgs e)
	{
		if (m_bRedirectOutput) {
			if (e.Data == null)
				m_OutputEvent.Set();
			else
				m_OutputData.AppendLine(e.Data);
		}
	}

	private void ErrorHandler(object process, DataReceivedEventArgs e)
	{
		if (m_bRedirectError) {
			if (e.Data == null)
				m_ErrorEvent.Set();
			else
				m_ErrorData.AppendLine(e.Data);
		}
	}

	private int m_ExitCode;
	private StringBuilder m_OutputData = null;
	private StringBuilder m_ErrorData = null;
	private AutoResetEvent m_OutputEvent = null;
	private AutoResetEvent m_ErrorEvent = null;
	private bool m_bRedirectOutput;
	private bool m_bRedirectError;
}

class Mac2IP
{
	protected string localip_from_name(string strName)
	{
		NetworkInterface[] nics = NetworkInterface.GetAllNetworkInterfaces();
		if (nics == null || nics.Length < 1)
		{
			Console.WriteLine("  No network interfaces found.");
			return null;
		}

		foreach (NetworkInterface adapter in nics)
		{
			if (adapter.OperationalStatus != OperationalStatus.Up)
				continue;

			if (adapter.NetworkInterfaceType != NetworkInterfaceType.Ethernet)
				continue;

			if (!adapter.Supports(NetworkInterfaceComponent.IPv4))
				continue;

			if (!adapter.Name.Equals(strName/*"Local Area Connection"*/))
				continue;

			//if (!adapter.GetPhysicalAddress().Equals(PhysicalAddress.Parse(host_mac)))
			//	continue;

			IPInterfaceProperties properties = adapter.GetIPProperties();
			UnicastIPAddressInformationCollection ipInfo = properties.UnicastAddresses;
			foreach (UnicastIPAddressInformation item in ipInfo)
			{
				if (item.Address.AddressFamily == /*System.Net.Sockets.*/AddressFamily.InterNetwork
						&& !IPAddress.IsLoopback(item.Address))
					return item.Address.ToString();
			}
		}

		return null;
	}

	private string findip(StreamReader stmReader, string mac)
	{
		string line, result = "";
		Regex regex = new Regex(@"(\d{1,3}\.){3}\d{1,3}\s+\S+");
		while(!stmReader.EndOfStream) {
			line = stmReader.ReadLine();
			if (string.IsNullOrEmpty(line)) {
				continue;
			}

			if (line.Contains(mac)) {
				result += regex.Match(line).Value + "\n";
			}
		}

		return result;
	}

	protected string getip(string mac)
	{
		ConsoleCommand arp = new ConsoleCommand();
		arp.Execute("arp.exe", "-a");

		MemoryStream memStm = new MemoryStream(Encoding.UTF8.GetBytes(arp.OutputData));
		StreamReader stmReader = new StreamReader(memStm);
		string ip = findip(stmReader, mac);
		return ip;
	}

	protected void arp_update_udp(string lanAddr)
	{
		int UDP_DISCARD_PORT = 9;
		byte[] echoBytes = /*System.Text.*/Encoding.ASCII.GetBytes("echo string...");
		UdpClient udpc = new /*System.Net.Sockets.*/UdpClient(AddressFamily.InterNetwork);

		for (int i = 1; i < 255; i++)
		{
			string newAddr = lanAddr + i;
			udpc.Send(echoBytes, echoBytes.Length, newAddr, UDP_DISCARD_PORT);
		}
		/*System.Threading.*/Thread.Sleep(1000);
	}

	public static void Main(string[] args)
	{
		if (args != null && args.Length < 1)
		{
			Console.WriteLine("Usage:");
			Console.WriteLine("    {0}: <MAC_Address> [xxx.xxx.xxx]", Environment.GetCommandLineArgs()[0]);
			Environment.Exit(1);
		}

		// TODO:
		//   Force flush arp cache table

		string macAddr = args[0];
		macAddr = Regex.Replace(macAddr.ToLower(), @"[.:]", "-");
		if (!macAddr.Contains("-")) {
			macAddr = Regex.Replace(macAddr, @"[\da-f]{2}\B", "$0-");
		}
		Mac2IP m2ip = new Mac2IP();
		// Don't search in cache first before update
		string ipAddr = ""; // = m2ip.getip(macAddr.ToLower());

		if (string.IsNullOrEmpty(ipAddr)) {
			string lanAddr = "";
			Regex regex = new Regex(@"(\d{1,3}\.){3}");
			if (args.Length == 2) {
				lanAddr = args[1];
				if (!lanAddr.EndsWith(".")) {
					lanAddr += ".";
				}
				lanAddr = regex.Match(lanAddr).Value;
				if (string.IsNullOrEmpty(lanAddr)) {
					Console.WriteLine("Invalid LAN address \"{0}\"", args[1]);
					Environment.Exit(1);
				}
			} else {
				string adapter_name = "Local Area Connection";
				Console.WriteLine("Trying to find IPv4 on your Ethernet adapter \"{0}\"", adapter_name);

				string ipLan = m2ip.localip_from_name(adapter_name);
				if (string.IsNullOrEmpty(ipLan)) {
					Console.WriteLine("Cannot find IP for \"{0}\"", adapter_name);
					Console.WriteLine("Please specify a LAN address on command line.");
					Environment.Exit(2);
				}
				lanAddr = regex.Match(ipLan).Value;
				if (string.IsNullOrEmpty(lanAddr)) {
					Console.WriteLine("Invalid LAN address \"{0}\" format from \"{1}\"", ipLan, adapter_name);
					Environment.Exit(3);
				}
			}

			Console.WriteLine(string.Format("Updating ARP Cache, trying {0}1 through {0}254", lanAddr));
			m2ip.arp_update_udp(lanAddr);
			ipAddr = m2ip.getip(macAddr);

			if (string.IsNullOrEmpty(ipAddr)) {
				Console.WriteLine("Cannot find IP for MAC {0}", macAddr);
				Environment.Exit(4);
			}
		}
		Console.WriteLine(ipAddr);
		Environment.Exit(0);
	}
}
