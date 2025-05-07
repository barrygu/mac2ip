import System;
import System.IO;
import System.Text;
import System.Threading;
import System.Net.Sockets;

function findip(stdOut, mac)
{
	var line;
    var found=new Array();

	while(!stdOut.AtEndOfStream) {
		line = stdOut.ReadLine()
		if (!line) continue;
        var matched = line.match(/\b([\da-f]{2}-?){6}\b/)
		if (matched && matched[0].Contains(mac)) {
            matched = line.match(/(\d{1,3}\.?){4}\s+\S+/)
            if ( matched )
			    found.push(matched[0]);
		}
	}
    if (!found.length) return null;
	return found;
}

function getip(mac)
{
	var oShell = new ActiveXObject("WScript.Shell");
	var oExec = oShell.Exec("arp.exe -a");
	var Retry = 10;

	while (oExec.Status == 0 && Retry-- > 0) /*System.Threading.*/Thread.Sleep(100);

	return findip(oExec.StdOut, mac);
}

function arp_update_udp(lanAddr)
{
	var UDP_DISCARD_PORT = 9;
	var echoBytes = /*System.Text.*/Encoding.ASCII.GetBytes("echo string...");
	var udpc = new /*System.Net.Sockets.*/UdpClient(AddressFamily.InterNetwork);
    if (lanAddr.substr(-1) != '.')
        lanAddr = lanAddr + '.'
	for (var i = 1; i < 255; i++)
	{
		var newAddr = lanAddr + i;
		udpc.Send(echoBytes, echoBytes.Length, newAddr, UDP_DISCARD_PORT);
	}
	return;
}

function usage(appName)
{
    Console.WriteLine("")
    Console.WriteLine(String.Format("Usage:\n\t{0}: <MAC_Address> [xxx.xxx.xxx]", appName));
    Environment.Exit(1);
}

function Main(args)
{
	if (args.Length < 2)
        usage(args[0]);

	var macAddr = args[1];
    macAddr = macAddr.replace(/[.:]/g, '-').toLowerCase()

	var ipaddr = getip(macAddr);
	if (!ipaddr)
	{
        if (args.Length == 3) {
            var lanAddr = args[2];
            if ( ! lanAddr.match(/^(\d{1,3}\.?){3}$/) )
                usage(args[0]);
            arp_update_udp(lanAddr);
            ipaddr = getip(macAddr);
            if (!ipaddr) {
                Console.WriteLine("  !!! Can't find your mac address in your network.")
                Console.WriteLine("  !!! Please check your mac address and ip range.")
                Environment.Exit(2);
            }
        } else {
            Console.WriteLine("Warning:");
            Console.WriteLine("  !!Can't find your mac address in your arp cache.");
            Console.WriteLine("  !!Please try to specify a C-Class Lan IP to search it.");
            usage(args[0])
        }
	}

    Console.WriteLine(ipaddr.join("\r\n"))
}

////////////////////////////////////////////////////////
Main(Environment.GetCommandLineArgs())
