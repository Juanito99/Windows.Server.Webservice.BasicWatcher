param($MonitorItem)
 $api = New-Object -comObject 'MOM.ScriptAPI'

$computerName        = $env:COMPUTERNAME
$testedAt            = "Tested on: $(Get-Date -Format u) / $(([TimeZoneInfo]::Local).DisplayName)"
$WindowsVersion      = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Caption

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


$api.LogScriptEvent('BasicWatcher.Collect.KPIs.ps1',250,4,"On computer $($computerName) with searching for $($MonitorItem)")	

if ($MonitorItem -eq 'svchost') {
	
	$api.LogScriptEvent('BasicWatcher.Collect.KPIs.ps1',251,2,"On computer $($computerName) with searching for $($MonitorItem) - SVCHOST ")	

	$allSvcHostProc = Get-Process | Where-Object {$_.Name -eq $MonitorItem}

	$allSvcHostProc | ForEach-Object {	
		if ($_ | Select-Object -ExpandProperty Modules | Where-Object {$_.ModuleName -contains 'ftpsvc.dll'}){
				$ftpPid = $($_ |Select-Object -ExpandProperty Id)
		}
	}

	$allPerfCounter = Get-Counter "\Process($MonitorItem*)\*"  | Select-Object -ExpandProperty CounterSamples
	$perfCounterTmp = $allPerfCounter | Where-Object {$_.Path -match 'id Proces'} | Where-Object {$_.CookedValue -eq $ftpPid}
	$perfCounterTmp = $perfCounterTmp | Select-Object -ExpandProperty Path
	$svcPattern     = [regex]::Match($perfCounterTmp,'\(svchost#?\d*\)') | Select-Object -ExpandProperty Value
	$allPerfCounter = $allPerfCounter | Where-Object {$_.Path -match $svcPattern}
	
} else {

	$allPerfCounter  = Get-Counter "\Process($MonitorItem*)\*" | Select-Object -ExpandProperty CounterSamples
	 
}
 
$perfCounterReg  = '% processor time|working set \- private|io data bytes\/sec|handle count'
$perfCounterList = New-Object -TypeName 'System.Collections.ArrayList'

$api.LogScriptEvent('BasicWatcher.Collect.KPIs.ps1',252,2,"On computer for $($MonitorItem) found No Counter: $($allPerCounter.count)")	

$allPerfCounter | ForEach-Object {
    if ($_.Path -match $perfCounterReg) {
        
		$newPath                = $_.Path -replace '(\\\\[\w]*\\process[()\w#]*\\)',''        
		[double]$newCookedValue = 1

		if($newPath -match '% processor time') {
			$newCookedValue = [Math]::Round($_.CookedValue)		
			$newPath        = 'PercentProcessorTime'
		} elseif ($newPath -match 'working set \- private') {
			$newPath = 'WorkingSetPrivateMB'			            
			if ($_.CookedValue) {
				$newCookedValue = [Math]::Round($_.CookedValue / 1MB) 				
			} else {
				$newCookedValue = 1
			}						
		} elseif ($newPath -match 'io data bytes\/sec') {
			$newPath = 'IODataMBPerSec'
			if ($_.CookedValue) {
				$newCookedValue = [Math]::Round($_.CookedValue / 1MB) 				
			} else {
				$newCookedValue = 1
			}
		} elseif ($newPath -match 'handle count') {
			$newPath = 'HandleCount'
			if ($_.CookedValue) {
				$newCookedValue = $_.CookedValue				
			} else {
				$newCookedValue = 1
			}			
		}
        		
		if ($newCookedValue -eq $null) {
			$newCookedValue = 1			
		} 		

		$newCookedValue = [double]::Parse($newCookedValue)

		$perfHash = @{'Location' = $newPath}
		$perfHash.Add('CookedValue',$newCookedValue)
		$perfObj  = New-Object -TypeName PSObject -Property $perfHash        
		$null     = $perfCounterList.Add($perfObj)
    }
}

$perfCounterSum = New-Object -TypeName 'System.Collections.ArrayList'

$perfCounterList | Group-Object -Property Location | ForEach-Object {
    $perfSumHash = @{'Location' = ($_.Name)}
    $perfSumHash.Add('CookedValue', (($_.Group | Measure-Object -Property CookedValue -Sum).Sum))
    $perfSumObj = New-Object -TypeName PSObject -Property $perfSumHash
    $null       = $perfCounterSum.Add($perfSumObj)
}


$availableRamRaw = (systeminfo | Select-String 'Total Physical Memory:').ToString().Split(':')[1].Trim()
$availableMBRam  = $availableRamRaw -replace('MB','') 
$availableMBRam  = $availableMBRam -replace(' ','') 
$availableMBRam  = $availableMBRam -replace(',','')
$availableMBRam  = $availableMBRam -replace('\.','')

$onePercentRam  = 100 / $availableMBRam 
$usedPercentRam = $onePercentRam * ($perfCounterSum.GetEnumerator() | Where-Object {$_.Location -eq 'WorkingSetPrivateMB'} | Select-Object -ExpandProperty CookedValue)
$usedPercentRam = [Math]::Round($usedPercentRam)

$perfSumHash = @{'Location' = 'PercentMemoryUsed'}
$perfSumHash.Add('CookedValue', $usedPercentRam)
$perfSumObj = New-Object -TypeName PSObject -Property $perfSumHash
$null       = $perfCounterSum.Add($perfSumObj)

$perfCounterSum | ForEach-Object {

	$sumi  = "ComputerName>$($ComputerName)< testedAt>$($testedAt)< WindowsVersion>$($WindowsVersion)< ComputerDescription>$($computerDescription)<"
	$sumi += "Location>$($_.Location)< CookedValue>$($_.CookedValue)< TypeOfCookedValue $($_.CookedValue.GetType())"
	
	if (($_.Location -ne $null -and ($_.Location.Gettype().Name -eq 'String' )) -and (($_.CookedValue -ne $null) -and ($_.CookedValue -match '\d'))) {		
		$api.LogScriptEvent('BasicWatcher.Collect.KPIs.ps1',253,2,"On computer $($computerName) sending Bag with searching for $($MonitorItem)`n Bag: $($sumi)")	
		$foo = 'bar'
	} else {
		$api.LogScriptEvent('BasicWatcher.Collect.KPIs.ps1',253,1,"On computer $($computerName) NOT SENDING Bag with searching for $($MonitorItem)`n Bag: $($sumi)")	
		continue 
	}	
			                   
	$objekt = $MonitorItem + '.' + 'Info'

	$bag = $api.CreatePropertybag()						                  
	$bag.AddValue("testedAt",$testedAt)	
	$bag.AddValue("WindowsVersion",$WindowsVersion)		               
	$bag.AddValue("ComputerDescription",$computerDescription)	
	$bag.AddValue('Counter',$_.Location)
	$bag.AddValue('Value',$_.CookedValue) 
	$bag.AddValue('Instance',$ComputerName)
	$bag.AddValue('Objekt',$objekt)
	$bag

}