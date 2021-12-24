param (
  [string] $IP,
  [string] $Mac,
  [Bool] $Verbose = $false
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
    $UdpClient = new-object Net.Sockets.UdpClient
    $Packet = [System.Text.Encoding]::ASCII.GetBytes($Message)
 	for ($Num = 2; $Num -lt 255; $Num++) {
      $IP = "$Net.$Num"
      $UdpClient.Send($Packet, $Packet.Length, $IP, $Port) | Out-Null
 	}
    $UdpClient.Close()
  } catch {
    $UdpClient.Dispose()
    $Error | Write-Error
  }
}

if (-Not $IP) {
  $nics = Get-NetIPInterface -AddressFamily IPv4 -ConnectionState Connected -Dhcp Enabled
  if (-Not $nics) {
    if (-Not $Verbose) {
      Write-Host "No any connected net interface is found"
    }
    Exit
  }

  $idx = @()
  foreach ($o in $nics) { $idx += $o.InterfaceIndex }

  $ifs = @{}
  $nics = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4
  if (-Not $nics) {
    if ($Verbose) { 
      Write-Host "No valid IPv4 address is found for any connected net interface"
    }
    Exit
  }
  if ($nics.GetType().IsArray) {
    $nics | foreach-object { $ifs.Add($_.InterfaceAlias, $_.IPAddress) }
    $s = Show-Menu "Select Net interface" $ifs
    if ($s -ne "quit") { $myip = $ifs[$s] } else { Exit }
  } else {
    $myip =$nics.IPAddress
    $s = Read-Host "Only one IP Address" $myip "detected, using it? [y/n]"
    if (-Not ($s -eq "y")) { Exit }
  }
} else {
  if ($IP -as [IPAddress] -as [Bool]) {
    $myip = $IP
  } else {
    if ($Verbose) { 
      Write-Host $IP "is not a valid IP address"
    }
    Exit
  }
  $net = $myip.split('.')[0..2] -join '.'
  # Check the specific IP has same net area with any interface
  Get-NetIPAddress -AddressFamily IPv4 -IPAddress "$net.*" -AddressState "Preferred" 2>&1 >$null
  if (-Not $?) {
    if ($Verbose) { 
      Write-Host "No net interface is located in same net area of IP address" $IP
    }
    Exit
  }
}

if (-Not $Mac) {
  $conf="NetCards.json"
  if (-Not (Test-Path -Path $conf -PathType Leaf)) {
    if ($Verbose) {
      Write-Host "Please specify a MAC address or provide a config file named" $conf
    }
    Exit
  }
  $macs = @{}
  foreach ($o in (Get-Content $conf | ConvertFrom-Json).psobject.properties) {$macs.Add($o.Name,$o.Value)}
  if (-Not $macs) {
    if ($Verbose) {
      Write-Host "No valid 'Name':'Mac' pair is found in" $conf
    }
    Exit
  }
  if ($macs.count -eq 1) {
    if ($Verbose) {
      Write-Host "Only one MAC address is found in" $conf ", using it"
    }
    $Mac = $a.values | % tostring
  } else {
    $sel = Show-Menu "Please select a MAC address" $macs
    if ($sel -ne "quit") { $Mac = $macs[$sel] } else { Exit }
  }
}

$net = $myip.split('.')[0..2] -join '.'
Udp-Broadcast $net

$retry = 10
do {
  Start-Sleep -s 1
  $net = Get-NetNeighbor -AddressFamily IPv4 -IPAddress "$net.*" -LinkLayerAddress $Mac 2> $null
  if ($net) {break}
  $retry--
} while ($retry)

$net = $net | where-object {$_.state -eq "stale" -or $_.state -eq "reachable"} 
if (-Not $net) {
  if ($Verbose) {
    Write-Host "No valid IPv4 Address is found for" $Mac
  }
  Exit
}

foreach ($o in $net) { Write-Host $o.LinkLayerAddress ":" $o.IPAddress }
Write-Host
