strServiceWildcard = WScript.Arguments(0)

On Error Resume Next

Set WshNetwork       = CreateObject("WScript.Network")
ComputerName         = WshNetwork.ComputerName

Set objADSysInfo     = CreateObject("ADSystemInfo")
strComputerName      = objADSysInfo.ComputerName

Set objComputer      = GetObject("LDAP://" & strComputerName)
strDistinguishedName = objComputer.DistinguishedName

Set objAPI         = CreateObject("MOM.ScriptAPI")
Set objBag         = objAPI.CreatePropertyBag()

strReplaceMentText = "CN=" & ComputerName &","
strOUName          = Replace(strDistinguishedName,strReplaceMentText,"")


strWQL       = "SELECT * FROM Win32_Service WHERE Name LIKE '%" &strServiceWildcard & "%'"
strComputer  = "."

Set objWMIService = GetObject("winmgmts:" _
    & "{impersonationLevel=impersonate}!\\" & strComputer & "\root\cimv2")

Set colRunningServices = objWMIService.ExecQuery(strWQL)

For Each objService In colRunningServices 
    strServiceState       = objService.State 
	strMsg                = "Service State: " & strServiceState  
    strServiceDescription = objService.Description 
    strStartupMode        = objService.StartMode
Next

If strStartupMode = "Disabled" Then
	strRslt = "DisabledOrManual"
	strMsg = strMsg & VbCrLf & " please clean configuration instead of disabling service. "
ElseIf strStartupMode = "Manual" Then
	strRslt = "DisabledOrManual"
	strMsg = strMsg & VbCrLf & " Startup Mode is Manual. Cannot judge service state. "
Else
	If strServiceState <> "Running" Then
		strRslt = "Stopped"
	Else 
		strRslt = "Running"
	End If
End If

'objAPI.LogScriptEvent "BasicWatcher.WebService.Monitor.vbs",402,4,"Monitor sends Result:" & strRslt & " for " & strServiceWildcard & " with msg: " & strMsg

strDescription = "Not Maintained"

Set colItems = objWMIService.ExecQuery("Select * from Win32_OperatingSystem",,48)
For Each objItem In colItems
    strDescription = objItem.Description
Next 

Call objBag.AddValue("Result", strRslt)
Call objBag.AddValue("Message", strMsg)
Call objBag.AddValue("ServiceDescription", strServiceDescription)
Call objBag.AddValue("Description", strDescription)
Call objBag.AddValue("OU", strOUName)

objAPI.AddItem(objBag)

objAPI.ReturnItems