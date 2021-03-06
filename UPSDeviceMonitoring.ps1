### v2 changes from v1
### - removed several registry key entries and their values to simplify registry key
### - only need LE_LASTRUNTIME AND LE_FULLSCRIPTNAME
### - used a different datetime format for registry key entry LE_LASTRUNTIME

$DMFDebugMode = $false

$le_ScriptName = $MyInvocation.MyCommand.Name
$le_FullScriptName = $MyInvocation.MyCommand.Path

$le_RegKeyPath = "HKLM:\Software\$le_ScriptName"    #registry key path for ru object
$le_RegKeyPath = $le_RegKeyPath.substring(0, $le_RegKeyPath.Length-4)    #omit the ".ps1" suffix

<#
if( $DMFDebugMode ){    #only for debugging, valid date format is i.e. June-27-2013 11:07:06 AM
    $le_LastRunTime="" 
}    
else{    #use today's date for lastruntime
    $le_LastRunTime=Get-Date -format ((Get-Culture).DateTimeFormat.FullDateTimePattern)
}
#>

##### Global Object - ruLastExecution #####
### NOTE: LE_LASTRUNTIME is recorded when all 3 devices are successfully ran. 
$ruLastExecution = New-Object System.Object
$Res = $ruLastExecution | Add-Member -MemberType NoteProperty -name LE_LASTRUNTIME -value $le_LastRunTime
$Res = $ruLastExecution | Add-Member -MemberType NoteProperty -name LE_FULLSCRIPTNAME -value $le_FullScriptName

#################################################
### method: CreateRegistryKey
### - creates the registry key with associated entries from ruLastExecution object's NoteProperties
### parameters:
### - None
### return codes:
### - None
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruLastExecution -Name CreateRegistryKey -Value `
{
#    param( )

    $RegKey = New-Item -Path $le_RegKeyPath -Force
    $this | get-member | where-object { $_.MemberType -eq "NoteProperty" } | ForEach-Object `
    {
        $parts = ($_.Definition -split "=")
        $val = $parts[1]
        $res = $parts[0] -split " "
        $fulltype = $res[0]
        
        if( $DMFDebugMode ){ "fulltype is $fulltype" | Write-Host }
        switch( $fulltype ) {
            "System.String"   { $typename="String"; break } #used for names and paths and date&time strings
            "System.Boolean"  { $typename="String"; break } #if( $_ -eq $true ){ $val="true" } else{ $val="false" }; break }
            default    { $typename="Unknown" ; "CreateRegistryKey: output error" | Write-Host }
        }
        if( $DMFDebugMode ){ "typename is $typename" | Write-Host }
        $RegEntry = New-ItemProperty -Path $le_RegKeyPath -Name $_.Name -Type $typename -Value $val
    }
}

#################################################
### method: Save
### - saves current Date & Time to ruLastExecution's LE_LASTRUNTIME
### parameters:
### - None
### return codes:
### - None
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruLastExecution -Name Save -Value `
{ 
#    param( )

    #update registry entry Date&Time to value (current date and time)
    
    #NOTE: We are using this format EN-CA.FullDateTimePattern
    $le_DateTime= Get-Date -format ((Get-Culture).DateTimeFormat.FullDateTimePattern) 
    if( $DMFDebugMode ){ "le_DateTime is $le_DateTime" | Write-Host }
    
    $RegEntry = Set-ItemProperty -path $le_RegKeyPath -Name "LE_LASTRUNTIME" -Value $le_DateTime
}


##### Global Object - ruNetworkTest #####
$ruNetworkTest = New-Object System.Object

#################################################
### method: LocalConnection
### - ping to Domain Controllers. 
### - if at least one responds and it is not a local IP address – connected.
### parameters:
### - None
### return codes:
### - [boolean] - true if at least one dc's connected; false otherwise
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruNetworkTest -name LocalConnection -Value `
{
    $dc = "-.-.-.-","-.-.-.-"
    $myIP = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter IPEnabled=true -ComputerName .).IPAddress[0]
    if( $dc[0] -eq $myIP ) { return (Test-Connection -ComputerName $dc[1] -Count 1 -ea 0 -quiet) }
    elseif( $dc[1] -eq $myIP ) { return (Test-Connection -ComputerName $dc[0] -Count 1 -ea 0 -quiet) }
    return( (Test-Connection -ComputerName $dc[0] -Count 1 -ea 0 -quiet) -or (Test-Connection -ComputerName $dc[1] -Count 1 -ea 0 -quiet) )
}

#################################################
### method: InternetConnection
### - pings Google DNS (8.8.8.8, 8.8.4.4). If at least one responds then connected.
### parameters:
### - None
### return codes:
### - [boolean] - true if at least one server's connected; false otherwise
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruNetworkTest -name InternetConnection -Value `
{
    $googleIP = "8.8.8.8","8.8.4.4"
    return( (Test-Connection -ComputerName $googleIP[0] -Count 1 -ea 0 -quiet) -or (Test-Connection -ComputerName $googleIP[1] -Count 1 -ea 0 -quiet) )
}

#################################################
### method: LocalDNS
### - Clears DNS cache and ping Domain Controllers by names (DC1, DC2). If at least one responds then connected.
### parameters:
### - None
### return codes:
### - [boolean] - true if at least one dc's connected; false otherwise
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruNetworkTest -name LocalDNS -Value `
{
    ipconfig /flushdns | Out-Null
    $dcNames = "D1","D2"
    return( (Test-Connection -ComputerName $dcNames[0] -Count 1 -ea 0 -quiet) -or (Test-Connection -ComputerName $dcNames[1] -Count 1 -ea 0 -quiet) )
}

#################################################
### method: InternetDNS
### - pings Google.com and www.cisco.com. If at least one responds then connected.
### parameters:
### - None
### return codes:
### - [boolean] - true if at least one site's connected; false otherwise
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruNetworkTest -name InternetDNS -Value `
{
    $iDNS = "www.google.com","www.cisco.com"
    return( (Test-Connection -ComputerName $iDNS[0] -Count 1 -ea 0 -quiet) -or (Test-Connection -ComputerName $iDNS[1] -Count 1 -ea 0 -quiet) )
}

#################################################
### method: DevicePing
### - pings device IP address as parameter. If device responds, then connected.
### parameters:
### - None
### return codes:
### - [boolean] - true if device responds; false otherwise
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruNetworkTest -name DevicePing -Value `
{
    param( [string]$deviceIP )
    return (Test-Connection -ComputerName $deviceIP -Count 1 -ea 0 -quiet)
}



##### CODE TESTING SECTION #####

<# ### Testing ruNetworkTest ###
"---ruLastExecution---" | Write-Host
$ruLastExecution | Get-Member | Write-Host
"`n---ruNetworkTest---" | Write-Host
$ruNetworkTest | Get-Member | Write-Host

$devIP="-.-.-.-" 
"`n---Testing connections...---" | Write-Host
"Local Connection Test: " + $ruNetworkTest.LocalConnection()
"Internet Connection Test: " + $ruNetworkTest.InternetConnection()
"Local DNS Test: " + $ruNetworkTest.LocalDNS()
"Internet DNS Test: " + $ruNetworkTest.InternetDNS()
"Device $deviceIP Ping Test: " + $ruNetworkTest.DevicePing($devIP)
#>

### Testing ruLastExecution ###
#$ruLastExecution.CreateRegistryKey()
#$ruLastExecution.Save()






