param (
  [string] $IP,
  [string] $Mac
)

function Show-Menu
{
  param (
    [string] $Title = 'Select index of below items:',
    [hashtable] $Items
  )
  Write-Host "================ $Title ================"

  $i = 1
  $ikey = @{}
  foreach ($k in $Items.Keys) {
    $ikey.Add($i.ToString(), $k)
  	Write-Host ([String]::Format('{0}: {1} ({2})', $i, $k, $Items[$k]))
  	$i++
  }

  $ikey.Add("q", "quit")
  Write-Host "Q: Press 'Q' to quit."
  Write-Host

  $s = Read-Host "Please make a selection"
  return $ikey[$s]
}

function Udp-Broadcast
{
  param (
    [string] $Net, # IP destination, should be xxx.xxx.xxx
    [int]    $Port = 9, # port destination, 9 is a udp discard port
    [string] $Message = "Test-UDP"
  )

  try {
    ## Create UDP client instance
    $UdpClient = New-Object Net.Sockets.UdpClient

    $Packet = [System.Text.Encoding]::ASCII.GetBytes($Message)
 	for ($Num = 2; $Num -lt 255; $Num++) {
      $IP = "$Net.$Num"
      $UdpClient.Send($Packet, $Packet.Length, $IP, $Port) | Out-Null
 	}
    $UdpClient.Close()
  } catch {
    $UdpClient.Dispose()
    $Error | Write-Error;
  }
}

$idx = @()
Get-NetIPInterface -AddressFamily IPv4 -ConnectionState Connected -Dhcp Enabled | 
  select-object -Property InterfaceIndex |
  foreach-object {$idx += $_.InterfaceIndex}

$ifs = @{}
$nics = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4
if ([string]::IsNullOrWhiteSpace($IP)) {
  $nics | foreach-object { $ifs.Add($_.InterfaceAlias, $_.IPAddress) }
  
  #$myip = "xxx.xxx.xxx.xxxx"
  if ($nics.count -gt 1) {
    $s = Show-Menu "Select Net interface" $ifs
    if ($s -ne "quit") {
      $myip = $ifs[$s]
      $s = Read-Host "Selected IP of Net interface is "$myip", using it? [y/n]"
      if ($s -eq "n") {
        Write-Host "End"
        Exit
      }
    } else {
      Write-Host "End"
      Exit
    }
  } else {
    if ([string]::IsNullOrWhiteSpace($nics.IPAddress)) {
      Write-Host "Not find valid NetIP Interface"
      Write-Host "End"
      Exit
    }
    $myip =$nics.IPAddress
    $s = Read-Host "Only one IP Address" $myip "detected, using it? [y/n]"
    if (-Not ($s -eq "y")) {
      Write-Host "End"
      Exit
    }
  }
} else {
  if ($IP -as [IPAddress] -as [Bool]) {
    $myip = $IP
  } else {
    Write-Host "Not valid parameter of NetIP"
    Exit
  }
}

if ([string]::IsNullOrWhiteSpace($Mac)) {
  $macs = @{}
  $conf="NetCards.json"
  (Get-Content $conf | ConvertFrom-Json).psobject.properties | foreach-object {$macs.Add($_.Name,$_.Value)}
  $sel = Show-Menu "Please select a MAC address" $macs
  
  if ($sel -ne "quit") {
    $mac = $macs[$sel]
    #Write-Host "Selected MAC address:" $mac
    #Write-Host
  } else {
    Write-Host "End"
    Exit
  }
}

$net = $myip.split('.')[0..2] -join '.'
Udp-Broadcast $net
$IP = (Get-NetNeighbor -AddressFamily IPv4 -IPAddress "$net.*" -LinkLayerAddress $mac).IPAddress

Write-Host
if (-Not [string]::IsNullOrWhiteSpace($IP)) {
  Write-Host $mac ": " $IP
} else {
  Write-Host "Not found IP of MAC " $mac
}

Write-Host
