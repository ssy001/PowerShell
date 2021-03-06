### v10 changes from v9
### - CHANGES:
### - 1) removed all "if( $DCDebugMode ){ ... status messages 
### IMPROVEMENTS:
### more status reports (via ruLog methods) can be added to some functions for ease of debugging


#Device Indexes
New-Variable UPS1_ -Value 0 -Option Readonly -Force 
New-Variable UPS2_ -Value 1 -Option Readonly -Force
New-Variable ATS_  -Value 2 -Option Readonly -Force

#File Indexes
New-Variable CONFIG_ -Value 0 -Option Readonly -Force
New-Variable EVENT_  -Value 1 -Option Readonly -Force
New-Variable DATA_   -Value 2 -Option Readonly -Force
New-Variable OLDCONFIG_ -Value 3 -Option Readonly -Force

#Device Status Code
New-Variable OK_ -Value $true -Option Readonly -Force
New-Variable NOTOK_ -Value $false -Option Readonly -Force

$DeviceStatus=$OK_,$OK_,$OK_

#array of device names to process
$DeviceList="UPS1","UPS2","UPS3"
### hash table for device to IP
#NOTE: can also use an array to implement with device constants (see above) as indexes
$DeviceNameIP_HT = @{
    "UPS1"="-.-.-.-";
    "UPS2"="-.-.-.-";
    "ATS"="-.-.-.-"
}

#hash table of device to file locations
#NOTE: can also use an array to implement with device constants (see above) as indexes
$filePath_HT=@{
    "UPS1"="c:\UPS1\";
    "UPS2"="c:\UPS2\"
    "ATS"="c:\UPS3\"
}

$credentialsPath="c:\Credentials.txt"

#files to process
$FileList = "config.ini","event.txt","data.txt"    

#allowed IPs
$allowedIPs = @("-.-.-.-",  
                "-.-.-.-",
                "-.-.-.-", 
                "-.-.-.-" 
                )

$ScriptName=$MyInvocation.MyCommand.Name

$RegScriptName = "UPSDeviceMonitoring"
$RegKeyPath = "HKLM:\Software\$RegScriptName"

$APC="---"
$NetMC="---"
$NetMCVer="---"
$SmartUPS="---"
$SmartUPSVer="---"
$NetMCATS="---"

$TimeToCheck = $null    #Get-Date    #Set TimeToCheck initial value to now

#New-Object System.Collections.Hashtable
$newHT = $null
$oldHT = $null
$oldCodeHT = $null

#File array of arrays, grouped according to file type. Its indexes are based on the devices' constant variables above
#For example, $fileArray index [$UPS1_][$CONFIG_] is UPS1's config.ini file array, etc.
#Currently, it is a 3 device x 4 files/device array all initialized to null string
$global:fileArray=@( 
    @("", "", "", ""), 
    @("", "", "", ""), 
    @("", "", "", "")
)

$Global:fakeCommandLine = @("C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe", "-NoExit", "-File", "C:\UPSDeviceCheck.ps1")

#################################################
### method: CheckLastExecution
### - checks whether the last execution time for the script exists
### parameters:
### - [string] RegistryPath - registry path of the last execution key
### return codes:
### - 0 - no errors, registry key exists
### - 1 - registry access error or registry path is invalid
### - 2 - Last Execution Time exists, but variable TimeToCheck cannot be set
### - 3 - Last Execution Time does not exist, but variable TimeToCheck cannot be set
#################################################
#store registry key into variable
function CheckLastExecution{
    param( [string]$RegistryPath )
    
    try { 
    $var = Get-ItemProperty -path $RegistryPath -Name LE_LASTRUNTIME }
    catch { return 1 }    #registry path is invalid or returns error or LE_EXISTS property does not exist. 

#if LASTRUNTIME is a valid date, then last execution data is available, then process data from last execution time minus 2 minutes
    $LastExecTime = 0
    if( [DateTime]::TryParse($var.LE_LASTRUNTIME, [ref]$LastExecTime) ){
        try{
        Set-Variable -Name TimeToCheck -Scope global -Value ($LastExecTime.AddMinutes(-2)) }
        catch { 
            $ruLog.ExecError( "CheckLastExecution: variable TimeToCheck cannot be set", $TimeToCheck )
            return 2 
        }
    }
    else {
        try { 
        Set-Variable -Name TimeToCheck -Scope global -Value ((Get-Date).AddHours(-24)) }    #set time to process = 24 hours ago
        catch { 
            $ruLog.ExecError( "CheckLastExecution: variable TimeToCheck cannot be set", $TimeToCheck )
            return 3 
        }
        $ruLog.ExecError( "CheckLastExecution: Last Execution Time does not exist, time to check is: $TimeToCheck", $ruLastExecution )
    }
    return 0
}

#################################################
### method: DownloadFiles
### - Downloads 3 files (Config.ini, Event.txt, Data.txt) into the corresponding arrays
### - It also accesses credentials file to obtain the username and password for each device
### parameters:
### - None
### return codes:
### - None
#################################################
function DownloadFiles {
    param( )
    
    #for loop goes through each device in $DeviceList[] array.  
    for( $i=0; $i -lt $DeviceList.Length; $i++){   

        $DeviceName=$DeviceList[$i]
        $DeviceIP=$DeviceNameIP_HT.Item($DeviceName)
        $FilePath=$filePath_HT.Item($DeviceName)

        #retrieves the loginID and password for each device
        $ruCred.CR_CREDNAME = $DeviceName
        $returnValue = $ruCred.ReadCredentials($credentialsPath)
        if( $returnValue -eq 2 ){ 
            $ruLog.ExecCritError( "DownloadFiles: Credentials file $credentialsPath cannot be read. Script aborted" )
            break    #break from processing of whole script
        }
        elseif( $returnValue -eq 1){
            $ruLog.ExecError( "DownloadFiles: Credentials record $credentialsPath not found. $DeviceName device processing skipped" )
            continue    #skip processing of this device $i
        }

        #construct ftp command from $DeviceIP
        $FTPLoc = "ftp://" + $ruCred.CR_LOGINNAME + ":" + $ruCred.CR_PASSWORD + "@" + $DeviceIP + "/"

        for( $j=0; $j -lt $FileList.Length; $j++ ){
            if( $j -eq $CONFIG_ ){    #download process for config.ini here
                # Get-Content of original config file of device
                try{ 
                    $global:fileArray[$i][$OLDCONFIG_] = Get-Content -Path ($FilePath+$FileList[$CONFIG_]) -ErrorAction Stop 
                    if( $DeviceName -eq "ATS"){ $gIdx = 2 }
                    else{ $gIdx = 4 }
                    $subOldConfigArray = $fileArray[$i][$OLDCONFIG_][0..($gIdx-1)]+$fileArray[$i][$OLDCONFIG_][($gIdx+1)..(($fileArray[$i][$OLDCONFIG_]).length-1)]
                }
                catch{ $ruLog.ExecError( "DownloadFiles: Get-Content failed: unable to access $DeviceName original config.ini file" ) }

                #3) Download new config file of device and save as "tempconfig.ini"
                TryDownloadFile ($FtpLoc+$FileList[$CONFIG_]) ($FilePath+"tempconfig.ini")

                #4) Get-Content of new config file of device
                if( Test-Path -Path ($FilePath+"tempconfig.ini") ){
                    try{ 
                        $global:fileArray[$i][$CONFIG_] = Get-Content -Path ($FilePath+"tempconfig.ini") -ErrorAction Stop 
                        if( $DeviceName -eq "ATS"){ $gIdx = 2 }
                        else{ $gIdx = 4 }
                        $subConfigArray = $fileArray[$i][$CONFIG_][0..($gIdx-1)]+$fileArray[$i][$CONFIG_][($gIdx+1)..(($fileArray[$i][$CONFIG_]).length-1)]
                        $outObj = Compare-Object $subConfigArray $subOldConfigArray -SyncWindow 0
                    }
                    catch{ $ruLog.ExecError( "DownloadFiles: Get-Content failed: unable to access $DeviceName new config.ini file" ) }
                }

                if( $outObj ){ #if new config is different from original config, 
                    CreateBackup $FilePath ($FileList[$CONFIG_])     #Backup original config file of device
                    #save file array of tempconfig.ini to config.ini
                    try{ Set-Content -Path ($FilePath+$FileList[$CONFIG_]) -Value ($global:fileArray[$i][$CONFIG_]) }
                    catch{ $ruLog.ExecError( "DownloadFiles: Set-Content failed: unable to save $DeviceName new config.ini file" ) }
                }

                #delete the tempconfig.ini
                try{ Remove-Item ($FilePath+"tempconfig.ini") -ErrorAction Stop }
                catch{ $ruLog.ExecError( "DownloadFiles: Remove-Item failed: unable to delete $DeviceName tempconfig.ini file" ) }

            } #end if( $j -eq ... clause
            else{    #download process for event.txt, data.txt here
                #1) Backup original event|data file of device
                CreateBackup $FilePath ($FileList[$j])

                #2) Download new event|data file of device
                TryDownloadFile ($FtpLoc+$FileList[$j]) ($FilePath+$FileList[$j]) 
 
                #3) Get-Content of new event|data file of device
                if( Test-Path -Path ($FilePath+$FileList[$j]) ){
                    try{ $global:fileArray[$i][$j] = Get-Content -Path ($FilePath+$FileList[$j]) -ErrorAction Stop }
                    catch{ $ruLog.ExecError( "DownloadFiles: Get-Content failed: unable to access $DeviceName $($FileList[$j]) file" ) }
                }
            } #end else{ ... clause
        } #end for( $j=0; ... loop
    } #end for( $i=0; ... loop
}

#################################################
### method: TryDownloadFile
### - Tries to download a file via FTP n times
### parameters:
### - [string] fSource - path of source file
### - [string] fDest - path of destination folder
### return codes:
### - None
#################################################
function TryDownloadFile {
    param( [string]$fSource, [string]$fDest )

    $n = 10
    $wc = New-Object System.Net.WebClient

    for( $i=0; $i -lt $n; $i++ ){
        try{ $wc.DownloadFile( $fSource, $fDest ) }    #config.ini
        catch{ $ruLog.Debug( 2, "TryDownloadFile: Attempt $($i+1) of $n`: Can not download $fSource", $wc ) }
        if( Test-Path -Path $fDest ){ break }    #break out of for loop if download successful
        else{ Start-Sleep -s 5 }
    }
}

#################################################
### method: CreateBackup
### - creates a backup of the existing file with last modified date suffix appended to it
### parameters:
### - [string] fpath - path of file to be backed up
### - [string] fname - name of file to be backed up
### return codes:
### - None
#################################################
function CreateBackup {
    param( [string]$fpath, [string]$fname )
        
        $fileExists = $true
        try{ 
            $lastModified = (Get-Item -Path ($fpath+$fname) -ErrorAction Stop ).LastWriteTime
            $lastModifiedStr = $lastModified.ToString("_yyyy-MM-dd_HH-mm-ss")
        }
        catch{ 
            $fileExists = $false
            $ruLog.ExecError( "CreateBackup: Unable to access $fpath$fname" )
        }
        $fileNameParts = ($fname) -split "\."
        if( $fileNameParts.length -lt 2 ){ $fileNameBase = $fileNameParts }
        else{ 
            $fileNameBase = ""
            for($i=0; $i -lt $fileNameParts.length-1; $i++ ){
                $fileNameBase += $fileNameParts[$i] + "."
            }
            $fileNameBase = $filenameBase.substring(0, $fileNameBase.length-1)
        }
        if( $fileExists ){
            try{ 
                Copy-Item -Path ($fpath+$fname) -Destination (($fpath+$fileNameBase)+$lastModifiedStr+"."+$fileNameParts[-1])
            }
            catch{
                $ruLog.ExecError( "CreateBackup: Unable to backup $fpath$fname" )
            }
        }
}

#################################################
### method: ProcessATSEventTxt
### - checks ATS device's event.txt file header info, then examines the events list for any unusual events up to the time in variable TimeToCheck
### parameters:
### - None
### return codes:
### - 0 - No errors
### - 3 - ATS event.txt software version changed
#################################################
function ProcessATSEventTxt {
    param(  )

### Check first two lines for version and name data
    if ( $fileArray[$ATS_][$EVENT_][0] -ne $NetMCATS ) { $ruLog.Notify( "ATS event.txt software version changed", "ProcessATSEvent: ATS event.txt Software version changed to $($fileArray[$ATS_][$EVENT_][0]) from $NetMCATS" ); return 3 }

#### Check Name, Contact, Location, & System IP data
    $LineIndex=2
    #check for datetime at beginning of line 5 index[4], parse each line [string] into 4 tokens with whitespace delimiter, 
    #filter based on event, and then code
    New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CNAME_ -Value 2 -Option Readonly
    New-Variable CCONTACT_ -Value 3 -Option Readonly
    New-Variable CLOCATION_ -Value 4 -Option Readonly
    New-Variable CSYSTEMIP_ -Value 5 -Option Readonly

    $FileAccessedInfo=$fileArray[$ATS_][$EVENT_][$LineIndex].split("`t")

    #Identification L2 array indexes are the same as that of the column headers, only shifted by -2
    $Identification=@(
        @("UPS1 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("UPS2 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("---", "---", "---", "-.-.-.-")
    )
    
    if ( $FileAccessedInfo[$CNAME_] -ne $Identification[$ATS_][$CNAME_-2] ){ $ruLog.Notify( "ATS event.txt name different", "ProcessATSEventTxt: ATS event.txt Name is different. Name is $($FileAccessedInfo[$CNAME_])" ) }
    if ( $FileAccessedInfo[$CCONTACT_] -ne $Identification[$ATS_][$CCONTACT_-2] ) { $ruLog.Notify( "ATS event.txt contact different", "ProcessATSEventTxt: ATS event.txt Contact is different. Contact is $($FileAccessedInfo[$CCONTACT_])" ) }
    if ( $FileAccessedInfo[$CLOCATION_] -ne $Identification[$ATS_][$CLOCATION_-2] ) { $ruLog.Notify( "ATS event.txt location different", "ProcessATSEventTxt: ATS event.txt Location is different. Location is $($FileAccessedInfo[$CLOCATION_])" ) }
    if ( $FileAccessedInfo[$CSYSTEMIP_] -ne $Identification[$ATS_][$CSYSTEMIP_-2] ){ $ruLog.Notify( "ATS event.txt system IP different", "ProcessATSEventTxt: ATS event.txt System IP is different. System IP is $($FileAccessedInfo[$CSYSTEMIP_])" ) }

###--- Event Analysis ---###
    #Skip device check, "Set Date or Time" events
    #Filter only events up to $TimeToCheck
    #New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    #New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CEVENT_ -Value 2 -Option Readonly
    New-Variable CCODE_  -Value 3 -Option Readonly
    $authorizedUsers=@(
        "`'apc`'",
        "`'device`'",
        "`'readonly`'"
    )
    
    $LineIndex=5 #First entry of $eventFileArray is on line 5
    $line=$fileArray[$ATS_][$EVENT_][$LineIndex] 
    do {
        $lineSplit = $line.split("`t")    #tab delimited fields
        try{ $lineDT = [datetime]($lineSplit[$CDATE_]+" "+$lineSplit[$CTIME_]) }
        catch{ "Invalid conversion to System.DateTime" | Write-Host }
        if ($lineDT -ge $TimeToCheck) { 

            switch( $lineSplit[$CCODE_] ){
                { @("0x0014","0x001E","0x0016","0x0020","0x0015","0x001F") -contains $_ } { 
                    $ret= CheckEventForIPs $lineSplit[$CEVENT_]
                    switch( $ret ){
                        1 { $ruLog.Notify( "ATS event.txt Unauthorized IPs detected", "ProcessATSEventTxt Unauthorized IPs detected: $line" ) }
                        2 { $ruLog.ExecError( "ATS ProcessATSEventTxt: Parsing error: unknown string error encountered. Line is $line" ) }
                        3 { $ruLog.ExecError( "ATS ProcessATSEventTxt: Parsing error: null object encountered" ) }
                    }
                } 
                #Console user logged in
                #Console user logged out
                #FTP user logged in
                #FTP user logged out
                #Web user logged in
                #Web user logged out

                { @("0x0004","0x0005","0x0006","0x0045") -contains $_ } { 
                    $ret= CheckEventForIPs $DeviceName $lineSplit[$CEVENT_] 
                    switch( $ret ){
                        1 { $ruLog.Notify( "ATS event.txt Unauthorized IPs detected", "ProcessATSEventTxt Unauthorized IPs detected: $line" ) }
                        2 { $ruLog.ExecError( "ATS ProcessATSEventTxt: Parsing error: unknown string error encountered. Line is $line" ) }
                        3 { $ruLog.ExecError( "ATS CheckEventForIPs: Parsing error: null object encountered" ) }
                    }   
                } 
                #Detected an unauthorized user attempting to access the SNMP interface
                #Detected an unauthorized user attempting to access the Console Control interface
                #Detected an unauthorized user attempting to access the Web interface
                #Detected an unauthorized user attempting to access the FTP interface

                "0x000F" { $ruLog.Notify("ATS event.txt file transfer failed", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #File transfer failed

                "0x0C01" { $ruLog.Notify("ATS event.txt ATS has switched source", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #ATS has switched source
                "0x0C02" { $ruLog.Notify("ATS event.txt ATS has lost redundancy", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])") } #ATS has lost redundancy
                "0x0C03" { $ruLog.Notify("ATS event.txt Redundancy has been restored", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #Redundancy has been restored
                "0x0C04" { $ruLog.Notify("ATS event.txt A configuration change has been made", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #A configuration change has been made
                "0x0C07" { $ruLog.Notify("ATS event.txt Output current has exceeded threshold", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #Output current has exceeded threshold
                "0x0C08" { $ruLog.Notify("ATS event.txt Output current is within tolerance", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #Output current is within tolerance
                "0x0C09" { $ruLog.Notify("ATS event.txt Power supply failure", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #Power supply failure
                "0x0C0A" { $ruLog.Notify("ATS event.txt Power supply failure has cleared", "ProcessATSEventTxt: $($lineSplit[$CEVENT_])" ) } #Power supply failure has cleared
                default  {}

            } #END switch( ...

        } #END if( $lineDT ...
        else{ break }

        #skips empty lines in event.txt file
        $LineIndex++
        while( $LineIndex -lt $fileArray[$ATS_][$EVENT_].length ){
            if( $fileArray[$ATS_][$EVENT_][$LineIndex] -eq "" ){ $LineIndex++ } #if current line is "", go to next line
            else{ $line=$fileArray[$ATS_][$EVENT_][$LineIndex]; break }
        }

    }while( ($LineIndex -lt $fileArray[$ATS_][$EVENT_].length) ) 
    
    return 0 
} ### END of ProcessATSEventTxt function ###


#################################################
### method: ProcessUPSEventTxt
### - checks UPS1 or UPS2 device's event.txt file header info, then examines the events list for any unusual events up to the time in variable TimeToCheck
### parameters:
### - None
### return codes:
### - 0 - No errors
### - 2 - if device's event.txt Smart-UPS or NMC name changed
### - 3 - if device's event.txt Smart-UPS or NMC software version changed
#################################################
function ProcessUPSEventTxt {
    param( [string]$DeviceName )

    switch( $DeviceName ) {
        "UPS1" { $deviceNo = $UPS1_; break }
        "UPS2" { $deviceNo = $UPS2_; break }
        default { return 1 }    #unknown device name. return code 1
    }

### Check first two lines for version and name data
    if ( !($fileArray[$deviceNo][$EVENT_][0] -match $NetMC ) ) { $ruLog.Notify("$DeviceName event.txt NMC name does not match", "ProcessUPSEventTxt: $DeviceName event.txt line 0: $($fileArray[$deviceNo][$EVENT_][0]) does not match $NetMC " ); return 2 }
    if ( !($fileArray[$deviceNo][$EVENT_][1] -match $SmartUPS ) ) { $ruLog.Notify("$DeviceName event.txt Smart-UPS name does not match", "ProcessUPSEventTxt: $DeviceName event.txt line 1: $($fileArray[$deviceNo][$EVENT_][1]) does not match $SmartUPS" ); return 2 }
    
    $fileLine1Split = $fileArray[$deviceNo][$EVENT_][0].split()
    $fileLine2Split = $fileArray[$deviceNo][$EVENT_][1].split()
    if ( $fileLine1Split[-1] -ne $NetMCVer ) { $ruLog.Notify("$DeviceName event.txt NMC version changed", "ProcessUPSEventTxt: $DeviceName event.txt line 0: Network Management Card software version changed to $($fileLine1Split[-1]) from $NetMCVer" ); return 3 }
    if ( $fileLine2Split[-1] -ne $SmartUPSVer ) { $ruLog.Notify("$DeviceName event.txt Smart-UPS version changed", "ProcessUPSEventTxt: $DeviceName event.txt line 1: Smart-UPS software version changed to $($fileLine2Split[-1]) from $SmartUPSVer" ); return 3 }

#### Check Name, Contact, Location, & System IP data
    $LineIndex=4     #array index for first header row
    #check for datetime at beginning of line 5 index[4], parse each line [string] into 4 tokens with whitespace delimiter, 
    #filter based on event, and then code
    New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CNAME_ -Value 2 -Option Readonly
    New-Variable CCONTACT_ -Value 3 -Option Readonly
    New-Variable CLOCATION_ -Value 4 -Option Readonly
    New-Variable CSYSTEMIP_ -Value 5 -Option Readonly

    $FileAccessedInfo=$fileArray[$deviceNo][$EVENT_][$LineIndex].split("`t")
    #Identification L2 array indexes are the same as that of the column headers, only shifted by -2
    $Identification=@(
        @("UPS1 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("UPS2 APC SmartUPS 5000", "---", "--", "-.-.-.-"),
        @("---", "ATS", "---", "-.-.-.-")
    )
    
    if ( $FileAccessedInfo[$CNAME_] -ne $Identification[$deviceNo][$CNAME_-2] ){ $ruLog.Notify("$DeviceName event.txt device name changed", "ProcessUPSEventTxt: $DeviceName event.txt Name is different. Name is $($FileAccessedInfo[$CNAME_])" ) }
    if ( $FileAccessedInfo[$CCONTACT_] -ne $Identification[$deviceNo][$CCONTACT_-2] ) { $ruLog.Notify("$DeviceName event.txt contact changed", "ProcessUPSEventTxt: $DeviceName event.txt Contact is different. Contact is $($FileAccessedInfo[$CCONTACT_])" ) }
    if ( $FileAccessedInfo[$CLOCATION_] -ne $Identification[$deviceNo][$CLOCATION_-2] ) { $ruLog.Notify("$DeviceName event.txt location changed", "ProcessUPSEventTxt: $DeviceName event.txt Location is different. Location is $($FileAccessedInfo[$CLOCATION_])" ) }
    if ( $FileAccessedInfo[$CSYSTEMIP_] -ne $Identification[$deviceNo][$CSYSTEMIP_-2] ){ $ruLog.Notify("$DeviceName event.txt System IP changed", "ProcessUPSEventTxt: $DeviceName event.txt System IP is different. System IP is $($FileAccessedInfo[$CSYSTEMIP_])" ) }

###--- Event Analysis ---###
    #Skip device check, "Set Date or Time" events
    #Filter only events up to $TimeToCheck
    #New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    #New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CEVENT_ -Value 2 -Option Readonly
    New-Variable CCODE_  -Value 3 -Option Readonly
    $authorizedUsers=@(
        "`'apc`'",
        "`'device`'",
        "`'readonly`'"
    )
    
    $LineIndex=7   #First entry of $eventFileArray is on line 7
    $line=$fileArray[$deviceNo][$EVENT_][$LineIndex] 
    do {
        $lineSplit = $line.split("`t")    #tab delimited fields
        try{ $lineDT = [datetime]($lineSplit[$CDATE_]+" "+$lineSplit[$CTIME_]) }
        catch{ "Invalid conversion to System.DateTime" | Write-Host }
        if ($lineDT -ge $TimeToCheck) { 

            switch( $lineSplit[$CCODE_] ){
                { @("0x0014","0x001E","0x0016","0x0020","0x0015","0x001F") -contains $_ } { 
                    $ret= CheckEventForIPs $lineSplit[$CEVENT_]
                    switch( $ret ){
                        1 { $ruLog.Notify( "$DeviceName event.txt Unauthorized IPs detected", "ProcessUPSEventTxt Unauthorized IPs detected: $line" ) }
                        2 { $ruLog.ExecError( "$DeviceName ProcessUPSEventTxt: Parsing error: unknown string error encountered. Line is $line" ) }
                        3 { $ruLog.ExecError( "$DeviceName CheckEventForIPs: Parsing error: null object encountered" ) }
                    }
                } 
                #Console user logged in
                #Console user logged out
                #FTP user logged in
                #FTP user logged out
                #Web user logged in
                #Web user logged out

                { @("0x0004","0x0005","0x0006","0x0045") -contains $_ } { 
                    $ret= CheckEventForIPs $lineSplit[$CEVENT_] 
                    switch( $ret ){
                        1 { $ruLog.Notify( "$DeviceName event.txt Unauthorized IPs detected", "ProcessUPSEventTxt Unauthorized IPs detected: $line" ) }
                        2 { $ruLog.ExecError( "$DeviceName ProcessUPSEventTxt: Parsing error: unknown string error encountered. Line is $line" ) }
                        3 { $ruLog.ExecError( "$DeviceName CheckEventForIPs: Parsing error: null object encountered" ) }
                    }   
                } 
                #Detected an unauthorized user attempting to access the SNMP interface
                #Detected an unauthorized user attempting to access the Console Control interface
                #Detected an unauthorized user attempting to access the Web interface
                #Detected an unauthorized user attempting to access the FTP interface

                "0x000F" { $ruLog.Notify("$DeviceName event.txt file transfer failed", "ProcessUPSEventTxt: $($lineSplit[$CEVENT_])" ) } #File transfer failed

                "0x0103" { $ruLog.Notify("$DeviceName event.txt The load exceeds 100% of rated capacity", "ProcessUPSEventTxt: $($lineSplit[$CEVENT_])" ) } #The load exceeds 100% of rated capacity
                "0x0104" { $ruLog.Notify("$DeviceName event.txt The load no longer exceeds 100% of rated capacity", "ProcessUPSEventTxt: $($lineSplit[$CEVENT_])" ) } #The load no longer exceeds 100% of rated capacity
                "0x0107" { $ruLog.Notify("$DeviceName event.txt The battery is too low to support the load; if power fails, the UPS will be shut down immediately", "ProcessUPSEventTxt: $($lineSplit[$CEVENT_])" ) } #The battery is too low to support the load; if power fails, the UPS will be shut down immediately
                "0x0108" { $ruLog.Notify("$DeviceName event.txt A discharged battery condition no longer exists", "ProcessUPSEventTxt: $($lineSplit[$CEVENT_])" ) } #A discharged battery condition no longer exists

                default  {}

            } #END switch( ...

        } #END if( $lineDT ...
        else{ break }

        #skips empty lines in event.txt file
        $LineIndex++
        while( $LineIndex -lt $fileArray[$deviceNo][$EVENT_].length ){
            if( $fileArray[$deviceNo][$EVENT_][$LineIndex] -eq "" ){ $LineIndex++ } #if current line is "", go to next line
            else{ $line=$fileArray[$deviceNo][$EVENT_][$LineIndex]; break }
        }

    }while( ($LineIndex -lt $fileArray[$deviceNo][$EVENT_].length) ) 
    
    return 0 
} ### END of ProcessUPSEventTxt function ###

#################################################
### method: CheckEventForIPs
### - checks event for unauthorized IPs and reports them via ruLog's methods
### parameters:
### - [string] eventLine - line containing event and IP address to be checked
### return codes: 
### - 0 - IP address is in allowed IP list
### - 1 - IP address is not in allowed IP list
### - 2 - eventLine does not contain spaces as delimiter
### - 3 - eventLine is null object
#################################################
function CheckEventForIPs {
    param( [string]$eventLine )

    if( $eventLine -eq $null ){ return 3 }
    try{ $eventSplit = $eventLine.split(" ") }
    catch{ return 2 }
    foreach( $word in $eventSplit ) {
        if( $word -match "^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\.$" ){
            $IP = $word.Substring(0, $word.Length-1)
            if( $allowedIPs -contains $IP ){ return 0 }
            else{ return 1 }
        }
    } #end foreach( $word ...
}

#################################################
### method: ProcessATSDataTxt
### - checks ATS device's data.txt file header info, then examines the data readings for any unusual values up to the time in variable TimeToCheck
### parameters:
### - None
### return codes:
### - 0 - No errors
### - 3 - ATS data.txt software version changed
#################################################
function ProcessATSDataTxt {
    param(  )

### Check first two lines for version and name data
    if ( $fileArray[$ATS_][$DATA_][0] -ne $NetMCATS ) { $ruLog.Notify( "ATS data.txt software version changed", "ProcessATSDataTxt: ATS data.txt Software version changed to $($fileArray[$ATS_][$DATA_][0]) from $NetMCATS" ); return 3 }

    $LineIndex=2

#### Check Name, Contact, Location, & System IP data
    #check for datetime at beginning of line 5 index[4], parse each line [string] into 4 tokens with whitespace delimiter, 
    #filter based on event, and then code
    New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CNAME_ -Value 2 -Option Readonly
    New-Variable CCONTACT_ -Value 3 -Option Readonly
    New-Variable CLOCATION_ -Value 4 -Option Readonly
    New-Variable CSYSTEMIP_ -Value 5 -Option Readonly

    $FileAccessedInfo=$fileArray[$ATS_][$DATA_][$LineIndex].split("`t")
    #Identification L2 array indexes are the same as that of the column headers, only shifted by -2
    $Identification=@(
        @("UPS1 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("UPS2 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("ATS", "---", "---", "-.-.-.-")
    )
    if ( $FileAccessedInfo[$CNAME_] -ne $Identification[$ATS_][$CNAME_-2] ){ $ruLog.Notify( "ATS data.txt device name changed", "ProcessATSDataTxt: ATS data.txt Name field changed to $($FileAccessedInfo[$CNAME_]) from $($Identification[$ATS_][$CNAME_-2])" ) }
    if ( $FileAccessedInfo[$CCONTACT_] -ne $Identification[$ATS_][$CCONTACT_-2] ) { $ruLog.Notify( "ATS data.txt contact changed", "ProcessATSDataTxt: ATS data.txt Contact field changed to $($FileAccessedInfo[$CCONTACT_]) from $($Identification[$ATS_][$CCONTACT_-2])" ) }
    if ( $FileAccessedInfo[$CLOCATION_] -ne $Identification[$ATS_][$CLOCATION_-2] ) { $ruLog.Notify( "ATS data.txt location changed", "ProcessATSDataTxt: ATS data.txt Location field changed to $($FileAccessedInfo[$CLOCATION_]) from $($Identification[$ATS_][$CLOCATION_-2])" ) }
    if ( $FileAccessedInfo[$CSYSTEMIP_] -ne $Identification[$ATS_][$CSYSTEMIP_-2] ){ $ruLog.Notify( "ATS data.txt System IP changed", "ProcessATSDataTxt: ATS data.txt System IP field changed to $($FileAccessedInfo[$CSYSSTEMIP_]) from $($Identification[$ATS_][$CSYSTEMIP_-2])" ) }

###--- Data Analysis ---####
    #Filter only events up to $TimeToCheck
    #New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    #New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CFREQA_  -Value 2 -Option Readonly
    New-Variable CFREQB_  -Value 3 -Option Readonly
    New-Variable CVINA_  -Value 4 -Option Readonly
    New-Variable CVINB_  -Value 5 -Option Readonly
    New-Variable CIOUT_  -Value 6 -Option Readonly

    $LineIndex+=3
    $HeaderLine=$fileArray[$ATS_][$DATA_][$LineIndex]    #column headers
    $LineIndex++    #First entry of $dataFileArray is on line 9
    $line=$fileArray[$ATS_][$DATA_][$LineIndex] 
    
    do {
        $lineSplit = $line.split("`t")    #tab delimited fields
        $lineDT = [datetime]($lineSplit[$CDATE_]+" "+$lineSplit[$CTIME_])
        if ($lineDT -ge $TimeToCheck) { 
            #check FreqA, FreqB, VinA, VinB, Iout if they are within ranges. If not, report.
            if( [math]::abs( [int]($lineSplit[$CFREQA_]) - 60 ) -gt 5 )  { $ruLog.Notify( "ATS data.txt frequency A outside of range", "ProcessATSDataTxt: ATS Frequency A variance greater than 5 HZ `n" + $line ) }
            if( [math]::abs( [int]($lineSplit[$CFREQB_]) - 60 ) -gt 5 )  { $ruLog.Notify( "ATS data.txt frequency B outside of range", "ProcessATSDataTxt: ATS Frequency B variance greater than 5 HZ  `n" + $line ) }
            if( [math]::abs( [int]($lineSplit[$CVINA_]) - 120 ) -gt 10 )  { $ruLog.Notify( "ATS data.txt input A voltage outside of range", "ProcessATSDataTxt: ATS Voltage at Input A variance greater than 10 V `n" + $line ) }
            if( [math]::abs( [int]($lineSplit[$CVINB_]) - 120 ) -gt 10 )  { $ruLog.Notify( "ATS data.txt input B voltage outside of range", "ProcessATSDataTxt: ATS Voltage at Input B variance greater than 10 V `n" + $line ) }
            if( ([double]($lineSplit[$CIOUT_]) -gt 12.0) ) { $ruLog.Notify( "ATS data.txt output current exceeds maximum", "ProcessATSDataTxt: ATS Output current greater than 12.0 Amps `n" + $line ) }
        }
        else{ break }

        #skips empty lines in data.txt file
        $LineIndex++
        while( $LineIndex -lt $fileArray[$ATS_][$DATA_].length ){
            if( $fileArray[$ATS_][$DATA_][$LineIndex] -eq "" ){ $LineIndex++ } #if current line is "", go to next line
            else{ $line=$fileArray[$ATS_][$DATA_][$LineIndex]; break }
        }

    }while( ($LineIndex -lt $fileArray[$ATS_][$DATA_].length) ) 

    return 0
} ### END of ProcessATSDataTxt function ###

#################################################
### method: ProcessUPSDataTxt 
### - checks UPS1 or UPS2 device's data.txt file header info, then examines the data readings for any unusual values up to the time in variable TimeToCheck
### parameters:
### - [string] Devicename - name of the device to be checked
### return codes:
### - 0 - No errors
### - 2 - if device's data.txt Smart-UPS or NMC name changed
### - 3 - if device's data.txt Smart-UPS or NMC software version changed
#################################################
function ProcessUPSDataTxt {
    param( [string]$DeviceName )

    switch( $DeviceName ) {
        "UPS1" { $deviceNo = $UPS1_; break }
        "UPS2" { $deviceNo = $UPS2_; break }
        default { return 1 }    #unknown device name. return code 1
    }

### Check first two lines for version and name data
    if ( $fileArray[$deviceNo][$DATA_][0] -notmatch $NetMC ) { $ruLog.Notify( "$DeviceName data.txt NMC name does not match", "ProcessUPSDataTxt: $DeviceName data.txt line 0: $($fileArray[$deviceNo][$DATA_][0]) does not match $NetMC " ); return 2 }
    if ( $fileArray[$deviceNo][$DATA_][1] -notmatch $SmartUPS ) { $ruLog.Notify( "$DeviceName data.txt SmartUPS name does not match", "ProcessUPSDataTxt: $DeviceName data.txt line 1: $($fileArray[$deviceNo][$DATA_][1]) does not match $SmartUPS " ); return 2 }
    
    $fileLine1Split = $fileArray[$deviceNo][$DATA_][0].split()
    $fileLine2Split = $fileArray[$deviceNo][$DATA_][1].split()
    if ( $fileLine1Split[-1] -ne $NetMCVer ) { $ruLog.Notify( "$DeviceName data.txt NMC version changed", "ProcessUPSDataTxt: $DeviceName data.txt line 0: Network Management Card software version changed to $($fileLine1Split[-1]) from $NetMCVer" ); return 3 }
    if ( $fileLine2Split[-1] -ne $SmartUPSVer ) { $ruLog.Notify( "$DeviceName data.txt Smart-UPS version changed", "ProcessUPSDataTxt: $DeviceName data.txt line 1: Smart-UPS software version changed to $($fileLine2Split[-1]) from $SmartUPSVer" ); return 3 }
    $LineIndex=4

#### Check Name, Contact, Location, & System IP data
    #check for datetime at beginning of line 5 index[4], parse each line [string] into 4 tokens with whitespace delimiter, 
    #filter based on event, and then code
    New-Variable CDATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    New-Variable CTIME_ -Value 1 -Option Readonly
    New-Variable CNAME_ -Value 2 -Option Readonly
    New-Variable CCONTACT_ -Value 3 -Option Readonly
    New-Variable CLOCATION_ -Value 4 -Option Readonly
    New-Variable CSYSTEMIP_ -Value 5 -Option Readonly

    $FileAccessedInfo=$fileArray[$deviceNo][$DATA_][$LineIndex].split("`t")
    #Identification L2 array indexes are the same as that of the column headers, only shifted by -2
    $Identification=@(
        @("UPS1 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("UPS2 APC SmartUPS 5000", "---", "---", "-.-.-.-"),
        @("ATS", "---", "---", "-.-.-.-")
    )
    
    if ( $FileAccessedInfo[$CNAME_] -ne $Identification[$deviceNo][$CNAME_-2] ){ $ruLog.Notify( "$DeviceName data.txt device name changed", "ProcessUPSDataTxt: $DeviceName data.txt Name is different. Name is $($FileAccessedInfo[$CNAME_])" ) }
    if ( $FileAccessedInfo[$CCONTACT_] -ne $Identification[$deviceNo][$CCONTACT_-2] ) { $ruLog.Notify( "$DeviceName data.txt contact changed", "ProcessUPSDataTxt: $DeviceName data.txt Contact is different. Contact is $($FileAccessedInfo[$CCONTACT_])" ) }
    if ( $FileAccessedInfo[$CLOCATION_] -ne $Identification[$deviceNo][$CLOCATION_-2] ) { $ruLog.Notify( "$DeviceName data.txt location changed", "ProcessUPSDataTxt: $DeviceName data.txt Location is different. Location is $($FileAccessedInfo[$CLOCATION_])" ) }
    if ( $FileAccessedInfo[$CSYSTEMIP_] -ne $Identification[$deviceNo][$CSYSTEMIP_-2] ){ $ruLog.Notify( "$DeviceName data.txt System IP changed", "ProcessUPSDataTxt: $DeviceName data.txt System IP is different. System IP is $($FileAccessedInfo[$CSYSTEMIP_])" ) }

###--- Data Analysis ---####
    #Filter only events up to $TimeToCheck
    #New-Variable DATE_ -Value 0 -Option Readonly    #create some constants from column headers for array indexes
    #New-Variable TIME_ -Value 1 -Option Readonly
    New-Variable CVMIN_ -Value 2 -Option Readonly
    New-Variable CVMAX_  -Value 3 -Option Readonly
    New-Variable CVOUT_  -Value 4 -Option Readonly

if( $DeviceName -eq "UPS1" ){    #Different column positions for UPS1 and UPS2
    New-Variable CWOUT_  -Value 5 -Option Readonly
    New-Variable CFREQ_  -Value 6 -Option Readonly
    New-Variable CCAP_  -Value 7 -Option Readonly
    New-Variable CVBAT_  -Value 8 -Option Readonly
    New-Variable CTUPSC_  -Value 9 -Option Readonly
}
elseif ( $DeviceName -eq "UPS2" ){
    New-Variable CIOUT_  -Value 5 -Option Readonly
    New-Variable CWOUT_  -Value 6 -Option Readonly
    New-Variable CFREQ_  -Value 7 -Option Readonly
    New-Variable CCAP_  -Value 8 -Option Readonly
    New-Variable CVBAT_  -Value 9 -Option Readonly
    New-Variable CTUPSC_  -Value 10 -Option Readonly
    New-Variable CVAOUT_  -Value 11 -Option Readonly
}

    $LineIndex+=3
    $HeaderLine=$fileArray[$deviceNo][$DATA_][$LineIndex]    #column headers
    $LineIndex++    #First entry of $dataFileArray is on line 9
    $line=$fileArray[$deviceNo][$DATA_][$LineIndex] 
    
    do {
        $lineSplit = $line.split("`t")    #tab delimited fields
        $lineDT = [datetime]($lineSplit[$CDATE_]+" "+$lineSplit[$CTIME_])
        if ($lineDT -ge $TimeToCheck) { 
            #check %Cap, Vmin, Vmax, TupsC fields if they are within ranges. If not, report.
            if( [int]($lineSplit[$CVMIN_]) -lt 177 )  { $ruLog.Notify( "$DeviceName data.txt Voltage lower than minimum", "ProcessUPSDataTxt: $DeviceName Minimum line voltage less than 177 VAC `n" + $line ) }
            if( [int]($lineSplit[$CVMAX_]) -gt 229 )  { $ruLog.Notify( "$DeviceName data.txt Voltage greater than maximum", "ProcessUPSDataTxt: $DeviceName Maximum line voltage greater than 229 VAC `n" + $line ) }
            if( ([int]($lineSplit[$CFREQ_]) -lt 57) -or ([int]($lineSplit[$CFREQ_]) -gt 63) )  
                { $ruLog.Notify( "$DeviceName data.txt Frequency beyond tolerance range", "ProcessUPSDataTxt: Frequency beyond tolerance range of 57-63 Hz `n" + $line ) }
            if( [double]($lineSplit[$CCAP_]) -gt 100.0 )  { $ruLog.Notify( "$DeviceName data.txt Capacity exceeds 100%", "ProcessUPSDataTxt: $DeviceName Capacity exceeds 100% `n" + $line ) }
            if( ([double]($lineSplit[$CTUPSC_]) -lt 0.0) -or ([double]($lineSplit[$CTUPSC_]) -gt 40.0) )  
                { $ruLog.Notify( "$DeviceName data.txt Temperature beyond tolerance range", "ProcessUPSDataTxt: $DeviceName Temperature beyond tolerance range of 0-40 C `n" + $line ) }

            if( $DeviceName -eq "UPS2" ){    #Additional column checks for UPS2
                if( ([double]($lineSplit[$CIOUT_]) -lt 0.0) -or ([double]($lineSplit[$CIOUT_]) -gt 12.0) )  
                    { $ruLog.Notify( "$DeviceName data.txt Output current beyond operating range", "ProcessUPSDataTxt: $DeviceName Output current beyond operating range of 0.0A - 12.0A `n" + $line ) }
                if( [double]($lineSplit[$CVAOUT_]) -gt 99.9 )  
                    { $ruLog.Notify( "$DeviceName data.txt Output power greater than 100%", "ProcessUPSDataTxt: $DeviceName Output power greater than 100% `n" + $line ) }
            }
        }
        else{ break }

        #skips empty lines in data.txt file
        $LineIndex++
        while( $LineIndex -lt $fileArray[$deviceNo][$DATA_].length ){
            if( $fileArray[$deviceNo][$DATA_][$LineIndex] -eq "" ){ $LineIndex++ } #if current line is "", go to next line
            else{ $line=$fileArray[$deviceNo][$DATA_][$LineIndex]; break }
        }

    }while( ($LineIndex -lt $fileArray[$deviceNo][$DATA_].length) ) 

    return 0
} ### END of ProcessUPSDataTxt function ###


#################################################
### method: ProcessATSConfigIni
### - calls a series of functions to process the ATS configuration codes, store them in hash arrays, then compares them for any differences
### parameters:
### - None
### return codes:
### - 0 - no errors
#################################################
function ProcessATSConfigIni {
    param(  )

    $retVal = ATSStoreToHashArray $true    #Process the new ATS config.ini file
    if( $retVal ){ return $retVal }
    $retVal = ATSStoreToHashArray $false
    if( $retVal ){ return $retVal }    #Process the old ATS config.ini file

    CompareHashArray $newHT $oldHT 
    CompareHashArray $oldHT $newHT 
    return 0
}

#################################################
### method: ATSStoreToHashArray
### - parse the ATS' configuration codes from the config.ini file, and stores them to hash array
### parameters: 
### - [boolean] isNewFile - true if new config.ini file is being processed, false otherwise. Saves the results to the new (true) or old (false) hash table. 
### return codes:
### - 0 - No errors
### - 1 - if device's config.ini APC name changed
#################################################
function ATSStoreToHashArray {
    param( [boolean]$isNewFile )

    # if processing new config file, let fileArray point to the new configFileArray    
    if( $isNewFile ){ $configFileArray = $fileArray[$ATS_][$CONFIG_] }
    else{ $configFileArray = $fileArray[$ATS_][$OLDCONFIG_] }    

    $fileLine=0
    #check first line of file for version and name changes
    if ( $configFileArray[$fileLine] -notmatch $APC ) { $ruLog.Notify( "ATS config.ini APC name does not match", "ATSStoreToHashArray: ATS DeviceName config.ini line 0: $($configFileArray[$fileLine]) does not match $APC " ); return 1 }

    $fileLine+=2
    #check for datetime at beginning of line 5 index[4], parse each line [string] into 4 tokens with whitespace delimiter, 
    #filter based on event, and then code
    $FileAccessedInfo=$configFileArray[$fileLine].split(" ")

    if( $FileAccessedInfo[-1] -ne "apc" ) { $ruLog.Notify( "ATS config.ini file generated by unauthorized user", "ATSStoreToHashArray: ATS Unauthorized user $($FileAccessedInfo[-1]) detected. " ) }
    
    $fileLine=6  
    
    $hashL1Table = New-Object System.Collections.Hashtable
    $hashL2Table=@{}        #declare hashL2Table variable for scope for if statement after while($ $fileLine -lt $configFileArray.Length )... loop
    $fileLinePrevState="I"
    [boolean]$hasSection=$false
    [boolean]$isEventActionConfig=$false
    $oldCodeHashTable=@{}
    while( ++$fileLine -lt $configFileArray.Length ) {
        if( $configFileArray[$fileLine] -match "^\[[a-zA-Z/]*\]$" ) {    #if section headers, store line as hashL1Key, create empty hashL2Table
            #if this is not the first section, then attach the previous section hashtable (hashL2Table) to main hashtable (hashL1Table) 
            if( $hasSection ) {    #if hashL2Table exists, i.e not first section
                $hashL1Table.add("$hashL1Key", $hashL2Table)
            }
            #add entries to hash array
            $hashL1Key=$configFileArray[$fileLine]
            $hashL2Table = @{}                                    #create empty hash level 2 tables
            $hasSection=$true
            
        }
        elseif( ($configFileArray[$fileLine] -match "^;") -or ($configFileArray[$fileLine] -eq "") ) { $fileLinePrevState="N" }    #skip comments and empty/null strings
        elseif( $configFileArray[$fileLine] -match "^[a-zA-Z]" ) {    #process key-value strings - starts with a letter
            #parse key, value pair from line
            $keyValue=$configFileArray[$fileLine] -split "="
            $hashL2Key=$keyValue[0]
            $hashL2Value=$keyValue[1]
            #must check for existence of key-value pair before every add. 
            if( $hashL2Table.ContainsKey("$hashL2Key")) {        #if this key exists, then create a sub-hashtable to contain the keys (with value="")
                #check for the type of object in value. 
                #if value is a hashtable, then add the new value to the hashtable
                if( $hashL2Table.Item("$hashL2Key") -is "hashtable") {    #the new value is always added first - at the beginning of the newHashL3Table
                    $newHashL3Table=@{"$hashL2Value"=""}
                    $newHashL3Table+=$hashL2Table.Item("$hashL2Key")
                    $hashL2Table.Set_Item("$hashL2Key", $newHashL3Table)
                }
                #else if value is a string, then create a new hashtable and store it along with the new 
                elseif( $hashL2Table.Item("$hashL2Key") -is "string") {
                    $newHashL3Table=@{"$hashL2Value"="";$hashL2Table.Item("$hashL2Key")=""}
                    $hashL2Table.Set_Item("$hashL2Key", $newHashL3Table)
                }
            }
            else { $hashL2Table.add("$hashL2Key", "$hashL2Value") } 
            $fileLinePrevState="K"    #set previous state to "K"
        }
        else{ $ruLog.Notify( "ATS config.ini parse error", "ATSStoreToHashArray: Error: unknown line format. Line is $($configFileArray[$fileLine])" ) }  
        
        # for the old config file, process the event codes and stores them in a hashtable 
        if( !$isNewFile ){
            if( ($configFileArray[$fileLine] -match "^\[EventActionConfig\]$") -or $isEventActionConfig ) {
                $isEventActionConfig = $true
                if( $configFileArray[$fileLine] -match "^;" ){    #save code description
                    $codeDescription = $configFileArray[$fileLine]
                }
                if( $configFileArray[$fileLine] -match "^E" ){    #process code and enter into hashtable
                    $oldCodeHashTable.add($configFileArray[$fileLine], $codeDescription)
                }
            }
            # if start of a different section, then $isEventActionConfig flag is false - i.e. turned off
            if( ($configFileArray[$fileLine] -notmatch "^\[EventActionConfig\]$") -and ($configFileArray[$fileLine] -match "^\[[a-zA-Z/]*\]$")){
                $isEventActionConfig = $false
            }
        }
    }   #END of WHILE loop
    
    #append the last section to hashL1Table
    if( $hasSection ) {    #if hashL2Table exists, i.e not first section
        $hashL1Table.add("$hashL1Key", $hashL2Table)
        $hasSection=$false
    }

    if( $isNewFile ){ Set-Variable -Name newHT -Scope global -Value $hashL1Table }
    else{ 
        Set-Variable -Name oldHT -Scope global -Value $hashL1Table
        Set-Variable -Name oldCodeHT -Scope global -Value $oldCodeHashTable
    }
    return 0
}    ### End of function ATSStoreToHashArray ###


#################################################
### method: ProcessUPSConfigIni
### - calls a series of functions to process the UPS (1 or 2) configuration codes, store them in hash arrays, then compares them for any differences
### parameters:
### - [string] DeviceName - name of the device (UPS1 or UPS2) config.ini file to be processed
### return codes:
### - 0 - no errors
#################################################
function ProcessUPSConfigIni {
    param( [string]$DeviceName  )

    $retVal = UPSStoreToHashArray $true $DeviceName
    if( $retVal ){ return $retVal }
    $retVal = UPSStoreToHashArray $false $DeviceName
    if( $retVal ){ return $retVal }

    CompareHashArray $newHT $oldHT 
    CompareHashArray $oldHT $newHT 
    return 0
}

#################################################
### method: UPSStoreToHashArray
### - parse the UPS1 or UPS2 configuration codes from the config.ini file, and stores them to hash array
### parameters: 
### - [boolean] isNewFile - true if new file is being processed, false otherwise. Saves the results to the new (true) or old (false) hash table. 
### - [string] DeviceName - name of the device (UPS1 or UPS2) config.ini file to be processed
### return codes: 
### - 0 - No errors
### - 1 - if device's config.ini APC name changed
### - 2 - if device's config.ini Smart-UPS or NMC name changed
### - 3 - if device's config.ini Smart-UPS or NMC software version changed
#################################################
function UPSStoreToHashArray {
    param( [boolean]$isNewFile, [string]$DeviceName )

    switch( $DeviceName ) {
        "UPS1" { $deviceNo = $UPS1_; break }
        "UPS2" { $deviceNo = $UPS2_; break }
        default { return 1 }    #unknown device name. return code 1
    }

    $fileLine=0
    # if processing new config file, let fileArray point to the new configFileArray    
    if( $isNewFile ){ $configFileArray = $fileArray[$deviceNo][$CONFIG_] }
    else{ $configFileArray = $fileArray[$deviceNo][$OLDCONFIG_] }
    
    #check first 3 lines of file for version and name changes
    if ( $configFileArray[$fileLine] -notmatch $APC ) { $ruLog.Notify( "$DeviceName config.ini APC name does not match", "UPSStoreToHashArray: $DeviceName config.ini line 0: $($configFileArray[$fileLine]) does not match $APC " ); return 1 }
    if ( $configFileArray[++$fileLine] -notmatch $NetMC ) { $ruLog.Notify( "$DeviceName config.ini NMC name does not match", "UPSStoreToHashArray: $DeviceName config.ini line 1: $($configFileArray[$fileLine]) does not match $NetMC " ); return 2 }
    if ( $configFileArray[++$fileLine] -notmatch $SmartUPS ) { $ruLog.Notify( "$DeviceName config.ini SmartUPS name does not match", "UPSStoreToHashArray: $DeviceName config.ini line 2: $($configFileArray[$fileLine]) does not match $SmartUPS " ); return 2 }
    
    $fileLine1Split = $configFileArray[$fileLine-1].split()
    $fileLine2Split = $configFileArray[$fileLine].split()
    if ( $fileLine1Split[-1] -ne $NetMCVer ) { $ruLog.Notify( "$DeviceName config.ini NMC version does not match", "UPSStoreToHashArray: $DeviceName config.ini line 1: Network Management Card software version changed to $($fileLine1Split[-1]) from $NetMCVer" ); return 3 }
    if ( $fileLine2Split[-1] -ne $SmartUPSVer ) { $ruLog.Notify( "$DeviceName config.ini Smart-UPS version does not match", "UPSStoreToHashArray: $DeviceName config.ini line 2: Smart-UPS software version changed to $($fileLine2Split[-1]) from $SmartUPSVer" ); return 3 }

    $fileLine+=2
    #check for datetime at beginning of line 5 index[4], parse each line [string] into 4 tokens with whitespace delimiter, 
    #filter based on event, and then code
    $FileAccessedInfo=$configFileArray[$fileLine].split(" ")

    if( $FileAccessedInfo[-1] -ne "apc" ) { $ruLog.Notify( "$DeviceName config.ini file generated by unauthorized user", "UPSStoreToHashArray: UPS Unauthorized user $($FileAccessedInfo[-1]) detected." ) }
    
    $fileLine=6 #350 
    
    $hashL1Table = New-Object System.Collections.Hashtable
    $hashL2Table=@{}        #declare hashL2Table variable for scope for if statement after while($ $fileLine -lt $configFileArray.Length )... loop
    $fileLinePrevState="I"
    [boolean]$hasSection=$false
    [boolean]$isEventActionConfig=$false
    $oldCodeHashTable=@{}
    while( ++$fileLine -lt $configFileArray.Length ) {
        if( $configFileArray[$fileLine] -match "^\[[a-zA-Z/]*\]$" ) {    #if section headers, store line as hashL1Key, create empty hashL2Table
            #if this is not the first section, then attach the previous section hashtable (hashL2Table) to main hashtable (hashL1Table) 
            if( $hasSection ) {    #if hashL2Table exists, i.e not first section
                $hashL1Table.add("$hashL1Key", $hashL2Table)
            }
            #add entries to hash array
            $hashL1Key=$configFileArray[$fileLine]
            $hashL2Table = @{}                                    #create empty hash level 2 tables
            $hasSection=$true
            #$fileLinePrevState="H"    #set previous state to "H"
            
        }
        elseif( ($configFileArray[$fileLine] -match "^;") -or ($configFileArray[$fileLine] -eq "") ) { $fileLinePrevState="N" }    #skip comments and empty/null strings
        elseif( $configFileArray[$fileLine] -match "^[a-zA-Z]" ) {    #process key-value strings - starts with a letter
            #parse key, value pair from line
            $keyValue=$configFileArray[$fileLine] -split "="
            $hashL2Key=$keyValue[0]
            $hashL2Value=$keyValue[1]
            #must check for existence of key-value pair before every add. 
            if( $hashL2Table.ContainsKey("$hashL2Key")) {        #if this key exists, then create a sub-hashtable to contain the keys (with value="")
                #check for the type of object in value. 
                #if value is a hashtable, then add the new value to the hashtable
                if( $hashL2Table.Item("$hashL2Key") -is "hashtable") {    #the new value is always added first - at the beginning of the newHashL3Table
                    $newHashL3Table=@{"$hashL2Value"=""}
                    $newHashL3Table+=$hashL2Table.Item("$hashL2Key")
                    $hashL2Table.Set_Item("$hashL2Key", $newHashL3Table)
                }
                #else if value is a string, then create a new hashtable and store it along with the new 
                elseif( $hashL2Table.Item("$hashL2Key") -is "string") {
                    $newHashL3Table=@{"$hashL2Value"="";$hashL2Table.Item("$hashL2Key")=""}
                    $hashL2Table.Set_Item("$hashL2Key", $newHashL3Table)
                }
            }
            else { $hashL2Table.add("$hashL2Key", "$hashL2Value") } 
            $fileLinePrevState="K"    #set previous state to "K"
        }
        else{ $ruLog.Notify( "$DeviceName config.ini parse error", "UPSStoreToHashArray: Error: unknown line format. Line is $($configFileArray[$fileLine])" ) }  
        
        # for the old config file, process the event codes and stores them in a hashtable 
        if( !$isNewFile ){
            if( ($configFileArray[$fileLine] -match "^\[EventActionConfig\]$") -or $isEventActionConfig ) {
                $isEventActionConfig = $true
                if( $configFileArray[$fileLine] -match "^;" ){    #save code description
                    $codeDescription = $configFileArray[$fileLine]
                }
                if( $configFileArray[$fileLine] -match "^E" ){    #process code and enter into hashtable
                    $oldCodeHashTable.add($configFileArray[$fileLine], $codeDescription)
                }
            }
            # if start of a different section, then $isEventActionConfig flag is false - i.e. turned off
            if( ($configFileArray[$fileLine] -notmatch "^\[EventActionConfig\]$") -and ($configFileArray[$fileLine] -match "^\[[a-zA-Z/]*\]$")){
                $isEventActionConfig = $false
            }
        }
    }   #END of WHILE loop
    
    #append the last section to hashL1Table
    if( $hasSection ) {    #if hashL2Table exists, i.e not first section
        $hashL1Table.add("$hashL1Key", $hashL2Table)
        $hasSection=$false
    }

    if( $isNewFile ){ Set-Variable -Name newHT -Scope global -Value $hashL1Table }
    else{ 
        Set-Variable -Name oldHT -Scope global -Value $hashL1Table
        Set-Variable -Name oldCodeHT -Scope global -Value $oldCodeHashTable
    }
    return 0
}    ### End of function StoreToHashArray ###
   

#################################################
### method: CompareHashArray
### - checks if HT2 contains all the key-value pairs in HT1
### parameters:
### - [hashtable] HT1 - reference hashtable
### - [hashtable] HT2 - hashtable to be compared
### return codes:
### - None
#################################################
function CompareHashArray {
    param( [hashtable]$HT1, [hashtable]$HT2 )

#########################################################################################################################################    
### --- This takes the two hash arrays and compares them section by section twice, 1) orig vs bak, then 2) bak vs orig. --- ###    
### parameters are: $hashKey, $hashValue, $hashKeyBak, $hashValueBak
<#
for each section, 
    compare section headers
    if section header not found, report
    else
        for each key in section,
        compare keys
        if value is not a string, search hashtable keys for value
            if value not found, set flag(not found) = $true
        if key not found, set flag(not found) = $true
        if value not found, set flag(not found) = $true
    if flag(not found) = $true
        report whole section
        reset flag(not found) = $false
    
#>    
    [boolean]$notfound=$false
    $HT1.GetEnumerator() | ForEach-Object { 
        if( $_.key -match "^\[[a-zA-Z/]*\]$" ) {
            $sectionName=$_.key     #store section name
            if( !$HT2.ContainsKey("$sectionName") ) {    #if this section is missing from hashtablebak
                $ruLog.Notify( "UPS config.ini is missing a section", "CompareHashArray: Section $sectionName is missing in second file." )
            }
            else {    #retrieve the key-value pairs for each section
                $_.value.getEnumerator() | ForEach-Object {
                    $hashKey = $_.key
                    $hashValue = $_.value
                    if( $hashValue -is "hashtable" ) {    #if value is a hashtable, then foreach key in that hashtable, check if this is missing from hashtablebak
                        $hashValue.getEnumerator() | ForEach-Object {
                            $hashValueKey=$_.key
                            if( !($HT2.Item("$sectionName").Item("$hashKey").ContainsKey("$hashValueKey")) ) {
                                $notfound=$true
                            }
                        }
                    }
                    elseif( !($HT2.Item("$sectionName").ContainsKey("$hashKey")) ) {    #if key is missing from hashtablebak
                        $notfound=$true
                    }
                    elseif( !($HT2.Item("$sectionName").ContainsValue("$hashValue")) ) {    
                        $notfound=$true
                    }
                }    #end of ForEach-Object
            }    #end of else stmt
            if( $notfound ) {
                $notfound=$false
                $ruLog.Notify( "$DeviceName config.ini has missing parameters", "CompareHashArray: Section $sectionName is has different/missing parameters in second file." )
            }
        }    #end of if stmt
    }    #end of ForEach-Object  

} ### END of ProcessConfigIni function ###


#######################################
##### Top Level of Script #####
##### - initializes the following objects: 1-ruLog, 2-ruCred, 3-ruLastExecution, and 4-ruNetworkTest
##### - checks network connections
##### - downloads and processes the status files from each of the devices
##### - updates the last script runtime if script executed without errors
#######################################

$totalReturnValue=0

# Initialize the Media Logging Subsystem object
$retFilePath = $MyInvocation.MyCommand.Path
. "c:\Sys\Scripts\Libs\LoggingSubsystem.ps1"

if( $ruLog.LOG_FILELOGGING ){      #if File Logging initialization error, execution has to be aborted

# Initialize Password file object for password retrieval
. "c:\Credentials.ps1"

# Initialize Device Monitoring object (last run time, network test)
. "c:\UPSDeviceMonitoring.ps1"

#Ping (3) Devices that require ftp access
for( $index=0; $index -lt $DeviceList.Length; $index++){
    if( !$ruNetworkTest.DevicePing( $DeviceNameIP_HT.Item($DeviceList[$index]) ) ){ 
        $ruLog.ExecError( "Top Level: $($DeviceList[$index]) not reachable, processing for this device is aborted" )
        $DeviceStatus[$index] = $NOTOK_
    }
}

# Checks to see if Last Execution date is available.
$returnValue = CheckLastExecution $RegKeyPath
$totalReturnValue += $returnValue

DownloadFiles

$isAllDownloadOK = $true
for($i=0; $i -lt $DeviceList.Length; $i++ ){
    if( $DeviceStatus[$i] ){    #if DevicePing connection is ok for this device, then process it
        for($j=0; $j -lt $FileList.Length; $j++ ){
            if( $fileArray[$i][$j].Length -eq 0 ){ 
                $isAllDownloadOK = $false }    #set flag to false if any file download unsuccessful and do not process it
            elseif( ($j -eq $CONFIG_) -and ($fileArray[$i][$OLDCONFIG_].Length -eq 0) ){
                $isAllDownloadOk = $false }    #don't process the config file if the old config file wasn't read successfully
            else{
                switch( $i ){
                    0 { switch( $j ) {
                        0 { $res = ProcessUPSConfigIni "UPS1"; break }
                        1 { $res = ProcessUPSEventTxt  "UPS1"; break }
                        2 { $res = ProcessUPSDataTxt   "UPS1"; break }
                        default { "Switch L2: Unrecognized index $j" | Write-Host }
                        }
                        break
                    }
                    1 { switch( $j ) {
                        0 { $res = ProcessUPSConfigIni "UPS2"; break }
                        1 { $res = ProcessUPSEventTxt  "UPS2"; break }
                        2 { $res = ProcessUPSDataTxt   "UPS2"; break }
                        default { "Switch L2: Unrecognized index $j" | Write-Host }
                        }
                        break
                    }
                    2 { switch( $j ) {
                        0 { $res = ProcessATSConfigIni; break }
                        1 { $res = ProcessATSEventTxt;  break }
                        2 { $res = ProcessATSDataTxt;   break }
                        default { "Switch L2: Unrecognized index $j" | Write-Host }
                        }
                        break
                    }
                    default { "Switch L1: Unrecognized index $i" | Write-Host }
                } #end switch( $i ...
            } #end else{ ...
        } #end inner for($j=0; ...
    } #end if( $DeviceStatus[$i] ...
} #end outer for($i=0; ...

#if $totalReturnValue = 0 and $isAllDownloadOk = $true, then set LastExecution time to now
if( !$totalReturnValue -and $isAllDownloadOK ){ 
    $ruLastExecution.Save()
}

} #END of if( $ruLog.FILE_LOGGING ){ ...

#$ruLog.ExecEnd( $returnValue, $returnStr )

