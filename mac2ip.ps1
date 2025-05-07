param (
  [string] $IP,
  [string] $Mac,
  [Alias('ca')]
  [string] $Card,
  [Alias('r')]
  [int]    $Retry = 10,
  [Alias('v')]
  [switch] $Verbose
)

function Show-Menu
{
  param (
    [string] $Title = 'Select index of below items:',
    #[hashtable] $Items
    [System.Collections.Specialized.IOrderedDictionary]$Items
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
      #if ($Verbose) {
        $i = "{0:N2}" -f (($Num-2) * 100.0 / 253) 
        Write-Progress -Id 1 -Activity "Updating ARP Table" `
          -Status "Progress: $i% completed" -PercentComplete $i
      #}
      $IP = "$Net.$Num"
      $UdpClient.Send($Packet, $Packet.Length, $IP, $Port) | Out-Null
      Start-Sleep -m 50
 	}
    $UdpClient.Close()
  } catch {
    $UdpClient.Dispose()
    $Error | Write-Error
  }
}

if ($Verbose) {
  $VerbosePreference = "continue"
}

if (-Not $IP) {
  $nics = Get-NetIPInterface -AddressFamily IPv4 -ConnectionState Connected -Dhcp Enabled
  if (-Not $nics) {
    Write-Verbose "No any connected net interface is found"
    Exit
  }

  $idx = @()
  foreach ($o in $nics) {
    $c = Get-NetConnectionProfile -InterfaceIndex $o.InterfaceIndex
  	if ($c.IPv4Connectivity -eq "Internet") {
  	  $idx += $o.InterfaceIndex
  	}
  }
  if (-Not $idx) {
    Write-Verbose "No valid connected net interface is found"
    Exit
  }

  $nics = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4
  if (-Not $nics) {
    Write-Verbose "No valid IPv4 address is found for any connected net interface"
    Exit
  }
  if ($nics.GetType().IsArray) {
    $ifs = @{}
    $nics | foreach-object { $ifs.Add($_.InterfaceAlias, $_.IPAddress) }
    $s = Show-Menu "Select Net interface" $ifs
    if ($s -ne "quit") { $myip = $ifs[$s] } else { Exit }
  } else {
    $myip =$nics.IPAddress
    if ($Verbose) {
      $s = Read-Host "Single IP Address" $myip "detected, using it? [y/n]"
      if (-Not ($s -eq "y")) { Exit }
    }
  }
} else {
  $c = ($IP.ToCharArray() -eq '.').count
  if (($c -ge 2) -and ($IP -as [IPAddress] -as [Bool])) {
    $myip = $IP
  } else {
    Write-Verbose "$IP is not a valid IP address"
    Exit
  }
  $net = $myip.split('.')[0..2] -join '.'
  # Check the specific IP has same net area with any interface
  Get-NetIPAddress -AddressFamily IPv4 -IPAddress "$net.*" -AddressState "Preferred" 2>&1 >$null
  if (-Not $?) {
    Write-Verbose "No net interface is located in same net area of IP address $IP"
    Exit
  }
}

$ConfigFile = "NetCards.json"
if (-Not $Mac) {
  $WDir = Split-Path $MyInvocation.MyCommand.Path -Parent
  $conf=Join-Path -Path $WDir -ChildPath $ConfigFile
  if (-Not (Test-Path -Path $conf -PathType Leaf)) {
    Write-Verbose "Please specify a MAC address or provide a config file named $ConfigFile"
    Exit
  }
  $macs = [ordered]@{}
  foreach ($o in (Get-Content $conf | ConvertFrom-Json).psobject.properties) {
    if (-not $Card -or ( $Card -eq $o.Name)) {
      $macs.Add($o.Name,$o.Value)
      #$macs[$o.Name] = $o.Value
    }
  }
  if ($macs.count -eq 0) {
    Write-Verbose "No valid 'Name':'Mac' pair is found in $ConfigFile"
    Exit
  }
  if ($macs.count -eq 1) {
    #$f = [System.IO.Path]::GetFileName($conf)
    Write-Verbose ("Single MAC address '{0}: {1}' is found in '{2}' , using it" `
      -f $macs.keys.Normalize(), $macs.values.Normalize(), $ConfigFile)
    $Mac = $macs.values | % tostring
  } else {
    $sel = Show-Menu "Please select a MAC address" $macs
    if ($sel -ne "quit") { $Mac = $macs[$sel] } else { Exit }
  }
}

if ( -not $Mac ) {
  Write-Verbose "No valid MAC address is specified."
  exit
}

$net = $myip.split('.')[0..2] -join '.'
Udp-Broadcast $net

for ($num = $Retry; $num; $num--) {
  Start-Sleep -s 1
  $net = Get-NetNeighbor -AddressFamily IPv4 -IPAddress "$net.*" -LinkLayerAddress $Mac -ea 0
  if ($net) {break}
  #if ($Verbose) { 
    $i = "{0:N2}" -f (($Retry - $num) * 100 / $Retry)
    Write-Progress -Id 2 -Activity "Waiting for ARP table is updated" `
      -Status "Progress: $i% completed" -PercentComplete $i
  #}
}

#$net = $net | where-object {$_.state -eq "stale" -or $_.state -eq "reachable"} 
if (-Not $net) {
  Write-Verbose "Timeout, No valid IPv4 Address is found for $Mac"
  Exit
}

foreach ($o in $net) { Write-Host ("{0}: {1}: {2}" -f $o.LinkLayerAddress, $o.IPAddress, $o.state) }
Write-Host
