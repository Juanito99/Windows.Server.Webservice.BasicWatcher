param($MonitorItem)

$api = New-Object -comObject 'MOM.ScriptAPI'

$computerName   = $env:COMPUTERNAME
$testedAt       = "Tested on: $(Get-Date -Format u) / $(([TimeZoneInfo]::Local).DisplayName)"
$WindowsVersion = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Caption
$regIPPat       = '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'

try {
	$computerDescription = Get-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\services\LanmanServer\Parameters | Select-Object -ExpandProperty srvcomment -ErrorAction Stop
} catch {
	$computerDescription = 'Not maintained.'
}

$localComputerDomain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name
$computerName        = $computerName + '.' + $localComputerDomain

if (([string]::IsNullOrEmpty($computerDescription))) {
	$computerDescription = 'Not-Maintained'
} else {
	$noActionRequiredSo  = 'Keep description'
}

$netStatIpFile = [System.IO.Path]::GetTempFileName()

#$api.LogScriptEvent('BasicWatcher.Collect.IPConnections.ps1',350,4,"On computer $($computerName) with searching for $($MonitorItem)")	

Function Format-NetstatData {

	param(
		[object]$netstatInPut,		
		[ref]$nestatIPData
	)

	$allProcesses    = Get-Process | Select-Object -Property Name, Path, StartTime, id
	$netStatConnects = New-Object -TypeName System.Collections.Generic.List[object]
	$netStatArr      =  $netstatInPut -split "`r`n"

	$localComputerName   = $env:COMPUTERNAME
	$localComputerDomain = ([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain()).Name
	$localIPAddresses    = ([System.Net.Dns]::GetHostAddresses($localComputerName)) | Where-Object {$_.AddressFamily -eq 'interNetwork'} | Select-Object -ExpandProperty IPAddressToString

	$netStatArr | ForEach-Object {

		$netStatItm = $_

		if ($netStatItm -match "\d") {       

			$netStatItmParts = [Regex]::Split($netStatItm,"\s{2,}")
			$proto        = $netStatItmParts[1]
			$localIP      = ($netStatItmParts[2] -split ':')[0]
			$localPort    = ($netStatItmParts[2] -split ':')[1]
			$remoteIP     = ($netStatItmParts[3] -split ':')[0]
			$remotePort   = ($netStatItmParts[3] -split ':')[1]
			$connectState = $netStatItmParts[4]
			$procId       = $netStatItmParts[5]

			$procInfo      = $allProcesses | Where-Object { $_.id -eq $procId }
			$procName      = $procInfo.Name
			$procPath      = $procInfo.Path
			$procStartTime = $procInfo.StartTime

			if(-not $procPath) {
				$procPath = 'Path not exposed to API'    
			}		

			if ($localIPAddresses -contains $localIP) {
				$localName = $localComputerName
			}			

			if (($localIp -match $regIpPat -and $remoteIp -match $regIpPat) -and ($remoteIP -notmatch '0.0.0.0|127.0.0.1') ) {
				$myNetHsh = @{'proto' = $proto}
				$myNetHsh.Add('localIP', $localIP)
				$myNetHsh.Add('localName', $localName)
				$myNetHsh.Add('localPort', $localPort)
				$myNetHsh.Add('remoteIP', $remoteIP)
				$myNetHsh.Add('remotePort', $remotePort)
				$myNetHsh.Add('connectState', $connectState)
				$myNetHsh.Add('procId', $procId)
				$myNetHsh.Add('procName', $procName)
				$myNetHsh.Add('procPath', $procPath)
				$myNetHsh.Add('procStartTime', $procStartTime)

				$myNetObj = New-Object -TypeName PSObject -Property $myNetHsh
				$null     = $netStatConnects.Add($myNetObj)    
			}

		}#END if ($netStatItm -match "\d") 

	} #END $netStatIpArr | ForEach-Object {} 

	If ($netStatConnects.count -gt 0) {
		$rtn = $true
		$nestatIPData.Value = $netStatConnects
	} else {
		$rtn = $false	
	}

	$rtn

} #END Funciton Get-NetstatIPData



Invoke-Expression "C:\Windows\System32\netstat.exe -ano" | Out-File -FilePath $netStatIpFile
$netStatIp = Get-Content -Path $netStatIpFile | Out-String


$netStatIPConnects = New-Object -TypeName System.Collections.Generic.List[object]
Format-NetstatData -netstatInPut $netStatIp -nestatIPData ([ref]$netStatIPConnects)

$ipConnections = ''

#if svchost - check for port, otherwise use name to find the right process
if ($MonitorItem -ieq 'svchost') {
	$ipConnections = $netStatIPConnects | Where-Object {$_.localPort -eq "21"}
} else {
	$ipConnections = $netStatIPConnects | Where-Object {$_.procPath -match "(?i)[\\]$MonitorItem" -or $_.procName  -match "(?i)$MonitorItem"}
}


if ($ipConnections -ne '') {	
	#$api.LogScriptEvent('BasicWatcher.Collect.IPConnections.ps1',351,4,"Searching for $($MonitorItem) found no: $($ipConnections.Count) IPConnections")	
	$foo = 'bar'
} else {
	$api.LogScriptEvent('BasicWatcher.Collect.IPConnections.ps1',351,1,"Searching for $($MonitorItem) found no IPConnections. Ending now.")	
	Exit
}


$ipConnectionsCount = $ipConnections | Group-Object -Property remoteIP | Measure-Object  | Select-Object -ExpandProperty Count

#$api.LogScriptEvent('BasicWatcher.Collect.IPConnections.ps1',352,4,"Searching for $($MonitorItem) found individual no $($ipConnectionsCount) IPConnections")	

$objekt = $MonitorItem + '.' + 'Info'

$bag = $api.CreatePropertybag()						                  
$bag.AddValue("testedAt",$testedAt)	
$bag.AddValue("WindowsVersion",$WindowsVersion)		               
$bag.AddValue("ComputerDescription",$computerDescription)	
$bag.AddValue('Counter','ipConnections')
$bag.AddValue('Value',$ipConnectionsCount)
$bag.AddValue('Instance',$ComputerName)
$bag.AddValue('Objekt',$objekt)
$bag