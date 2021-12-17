function Udp-Broadcast
{
  param (
    [string] $Net, # IP destination
    [int]    $Port = 9, # port destination, 9 is a udp discard port
    [string] $Message = "Test-UDP"
  )

  try {
    $idx = @()
    Get-NetIPInterface -AddressFamily IPv4 -ConnectionState Connected -Dhcp Enabled | 
      Select-Object -Property InterfaceIndex |
      ForEach-Object {$idx += $_.InterfaceIndex}

    $myip = (Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 | 
      Where-Object -FilterScript {$_.IPAddress.StartsWith($Net)} | 
      Select-Object -Property IPAddress).IPAddress
	
    ## Create UDP client instance
    $UdpClient = New-Object Net.Sockets.UdpClient

    $Packet = [System.Text.Encoding]::ASCII.GetBytes($Message)
 	for ($Num = 1; $Num -lt 255; $Num++) {
      $IP = "$Net.$Num"
      #Write-Host $IP
      $UdpClient.Send($Packet, $Packet.Length, $IP, $Port) | Out-Null
 	}
    $UdpClient.Close()
  } catch {
    $UdpClient.Dispose()
    $Error | Write-Error;
  }
}

#$net = "xxx.xxx.xxx"
#$mac = "xx-xx-xx-xx-xx-xx"
$net = "192.168.1"
$mac = "AA-BB-CC-DD-EE-FF"

#param (
#  [string] $net,
#  [string] $mac
#)

Udp-Broadcast $net
Get-NetNeighbor -AddressFamily IPv4 -IPAddress "$net.*" -LinkLayerAddress $mac
