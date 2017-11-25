#Ver 6 - 2015-05-20
#1) Changed the command used by Invoke-Command to Get-Date
#2) Changed test conditions of Invoke-Command and PSExec to avoid false positives

#Ver 5 - 2015-05-19
#1) Added Logging_Subsystem logging to email snapshot (as of 6 AM) of non-connecting workstations to Alloy Navigator 

#Ver 4 - 2015-05-19
#1) Remote connection test set to execute at intervals of 15 minutes.

#Ver 3 - 2015-05-14
#1) Remote connection tests are executed in parallel as a workflow "Test-Connect". 

#Ver 2 - 2015-05-07
#1) if psexec or psinvoke returns error on the current iteration and computer, retry up to n times until first ok or nth error
#   if ok, then output to log "OK_#_Tries", else output to log "Error_#_Tries"

#Ver 1 - 2015-05-06
#Checks if (3)Remote Access Methods work
#There are 3 methods used:
#1) Ping
#3) Invoking system commands through Powershell (Invoke-Command)
#4) PSExec (sysinternals utility)
$DebugL1 = $true       #basic level of debugging
$DebugL2 = $true       #level 2 debugging (more info)

$ServerName = [System.Environment]::GetEnvironmentVariable("COMPUTERNAME")
#$BaseDir = "\\---\Scripts\"
#$BaseDir = "C:\Scripts\"
$BaseDir = "D:\Scripts\"
$ScriptDir = $BaseDir+"Check Remote Access Status\"
$CompList = Get-Content $ScriptDir"List.txt"
$LogonLogDir="D:\Logs\"

# $comp_prev_pass contains the following fields:
# comp_prev_pass[CompID, Date-Time, PingStat, PsInvokeStat, PsExecStat]
$comp_prev_pass = @()
#$idt = "YYYY-MM-DD  HH:MM"
$idt = Get-Date
$idtTxt = $idt.ToShortDateString().PadRight(12) + $idt.ToShortTimeString().PadRight(10)
$init = "Init"

# $StatusHashArr contains the following fields (#DEFINEs)
# StatusHashArr[PINGidx, PSIidx, PSEidx]
$StatusHashArr = @{}
$PINGidx = 0
$PSIidx = 1
$PSEidx = 2

#Connection tests and reporting/logging intervals
$WAIT_MINS = 15                           #interval (in minutes) between tests
#$WAIT_MINS = 10                           #interval (in minutes) between tests
$TIME_TO_EMAIL = " 6:00 AM"
#$TIME_TO_EMAIL = " 12:10 PM"
$next_check = [datetime]($((Get-Date).ToLongDateString()+$TIME_TO_EMAIL))

# Initialize the Media Logging Subsystem object
$retFilePath = $MyInvocation.MyCommand.Path
. $BaseDir"\Subsystem.ps1"

#initialization stage
foreach ($Comp in $CompList) {
    $comp_prev_pass+= ,@( $Comp, $idt, $init, $init, $init )
    $StatusHashArr.Add($Comp, @("Init","Init","Init"))
    if( (Test-Path $LogonLogDir) -eq $false ) {
        New-Item $LogonLogDir -type directory | Out-Null
    }
    if( (Test-Path $($LogonLogDir+$Comp+".log")) -eq $false ) {
        Add-Content $($LogonLogDir+$Comp+".log") $("Date".PadRight(22)+"Ping".PadRight(14)+"PsInvoke".PadRight(14)+"PsExec".PadRight(14))
        Add-Content $($LogonLogDir+$Comp+".log") $("-----------------------------------------------------------------------")
        Add-Content $($LogonLogDir+$Comp+".log") $($idtTxt+$init.PadRight(14)+$init.PadRight(14)+$init.PadRight(14))
    }
}

if($DebugL1){Write-Host $ServerName": *****Start script CheckRemoteAccessStatusParallelWithLogging.ps1*****" -ForegroundColor Red -BackgroundColor White}

#workflow for parallel execution
workflow Test-Connect {
    Param([parameter(Mandatory=$true)] [object[]] $computers,
          [parameter(Mandatory=$true)] [Hashtable] $hasharr)

    $samplesize = 3   #set sample size to test until ok or error
    ForEach -Parallel ($comp in $computers){
        $pingResult = InlineScript { & "ping" -4 $Using:comp}

        if( ($pingResult | Select-String -Pattern "(100% loss)") -or ($pingResult | Select-String -Pattern ("could not find host")) -or ($pingResult | Select-String -Pattern ("Destination host unreachable.")) ){ 
            $comp+"|Error|Error|Error_0_Tries" 
        }
        else{
            #$psiResult = InlineScript{ (Invoke-Command -ComputerName $Using:comp -ScriptBlock {Get-EventLog -LogName Application -Newest 1}).Message 2> $null }
            $psiResult = InlineScript{ (Invoke-Command -ComputerName $Using:comp -ScriptBlock {Get-Date -UFormat %Y}) 2> $null }
            if( ($psiResult -ne $null) -and ($psiResult.length -gt 1) -and ($psiResult[0] -eq '2') ) { $psiStatus = "OK" }
            else{ $psiStatus = "Error" }

            #$cmdargs = @("\\$comp", "ipconfig")
            $cmdargs = @("\\$comp", "cmd", "/C", "date", "/T")
            $pseStatus = ""
            $pseResult = ""
            for($i=1; $i -le $samplesize; $i++){
                $pseResult = InlineScript{ & "C:\Sysinternals\PsExec.exe" $Using:cmdargs 2> $null | foreach-Object { $resstr += $_ }; $resstr }
                if( ($pseResult -eq $null ) -and ($i -eq $samplesize) ) { $pseStatus = "Error_"+$i+"_Tries" }
                elseif( $pseResult -ne $null )                          { $pseStatus = "OK_"+$i+"_Tries"; $i=$samplesize+1 }
            }
            $comp+"|OK|"+$psiStatus+"|"+$pseStatus+"|"+$pseResult+"|"+$pseResult.length
        }
    }
}

$iter=1
while( 1 ){      
    $start_exec = Get-Date
if($DebugL1){Write-Host $(Get-Date) Iteration: $iter -ForegroundColor Green -BackgroundColor DarkRed; $iter++}
####################################1. Begin Ping check ############################################################
if($DebugL1){Write-Host *****1. Begin remote connection check of workstations***** -ForegroundColor Blue -BackgroundColor Gray}
    $StatusString = Test-Connect -computers $CompList -hasharr $StatusHashArr

if($DebugL1){Write-Host $ServerName": -----List of computers' statuses:" -ForegroundColor Yellow}
if($DebugL1){Write-Host $("Computer".PadRight(12)+"Ping".padRight(12)+"PSInvoke".PadRight(12)+"PSExec".PadRight(12)) -ForegroundColor Yellow}
if($DebugL1){ $StatusString }
if($DebugL1){Write-Host *****1. End remote connection check of workstations***** -ForegroundColor Blue -BackgroundColor Gray}

#Convert $StatusString and update hash array format
foreach( $line in $StatusString ){
    $linearr = $line.Split("|")
    $StatusHashArr.Set_Item($linearr[0].trim(), @($linearr[1].trim(),$linearr[2].trim(),$linearr[3].trim()))
}

if($DebugL1){Write-Host *****2. Begin Update and Log of changes to previous status of workstations***** -ForegroundColor Blue -BackgroundColor Gray}
    foreach ($CompStat in $comp_prev_pass) {
        $Dt = Get-Date
        $DtTxt = $Dt.ToShortDateString().PadRight(12) + $Dt.ToShortTimeString().PadRight(10)
        $UpdateStat = $false
if($DebugL2){Write-Host $("compstat-Previous Status-"+$CompStat[0]+", Ping:"+$CompStat[2]+", PsInvoke:"+$CompStat[3]+", PsExec:"+$CompStat[4])}
        $hashval = $StatusHashArr.Get_Item($CompStat[0])
        if( ($hashval[$PINGidx] -eq "OK") -and (($CompStat[2] -eq "OK") -or ($CompStat[2] -eq "Init")) ) {
            $CompStat[2] = "OK"
            #check psinvoke and psexec error arrays, compare status and (if required) update it in $comp_prev_pass
            if( $hashval[$PSIidx] -eq "Error" ) {   #ping=OK, but psinvoke=Error
                if(($CompStat[3] -eq "OK") -or ($CompStat[3] -eq "Init")) { 
                    $CompStat[3] = "Error" 
                    $UpdateStat = $true
                }   
            }
            else {                                    #ping=OK, psinvoke=OK
                if(($CompStat[3] -eq "Error") -or ($CompStat[3] -eq "Init")) { 
                    $CompStat[3] = "OK"
                    $UpdateStat = $true
                }
            }

            if( $hashval[$PSEidx] -match "Error") {      #ping=OK, but psexec=Error
                if(($CompStat[4] -match "OK") -or ($CompStat[4] -eq "Init")) { 
                    $CompStat[4] = $hashval[$PSEidx]
                    $UpdateStat = $true
                }
            }
            else {                                    #ping=OK, psexec=OK
                if(($CompStat[4] -match "Error") -or ($CompStat[4] -eq "Init")) { #psexec=OK for current, but psexec=Error for previous
                    $CompStat[4] = $hashval[$PSEidx]
                    $UpdateStat = $true
                }   
                elseif(($CompStat[4] -match "OK") -and ($CompStat[4].CompareTo($hashval[$PSEidx]) -ne 0)) {    #psexec=OK for current and previous, but diff #_tries
                        $CompStat[4] = $hashval[$PSEidx]
                        $UpdateStat = $true
                }
            }
            if( $UpdateStat ) {  #(if update is required) log results in $LogonLogDir+$CompStat[0]+".log" file
                $CompStat[1] = $DtTxt
                Add-content $($LogonLogDir+$CompStat[0]+".log") $($DtTxt+$CompStat[2].PadRight(14)+$CompStat[3].PadRight(14)+$CompStat[4].PadRight(14))
            }
        }

        elseif( ($hashval[$PINGidx] -eq "OK") -and ($CompStat[2] -eq "Error") ) {
            $CompStat[1] = $DtTxt
            $CompStat[2] = "OK" #update ping status in $comp_prev_pass to ok
            #check psinvoke and psexec error arrays and update status in $comp_prev_pass
            if( $hashval[$PSIidx] -eq "Error" ) {
                $CompStat[3] = "Error"
            }
            else {
                $CompStat[3] = "OK"
            }
            if( $hashval[$PSEidx] -match "Error" ) {
                $CompStat[4] = $hashval[$PSEidx]
            }
            else {
                $CompStat[4] = $hashval[$PSEidx]
            }
            #log results in $LogonLogDir+$CompStat[0]+".log" file
            Add-content $($LogonLogDir+$CompStat[0]+".log") $($DtTxt+$CompStat[2].PadRight(14)+$CompStat[3].PadRight(14)+$CompStat[4].PadRight(14))
        }

        elseif ( ($hashval[$PINGidx] -eq "Error") -and (($CompStat[2] -eq "OK") -or ($CompStat[2] -eq "Init")) ) {
            #update ping status in $comp_prev_pass to error
            $CompStat[1] = $DtTxt
            $CompStat[2] = "Error"
            $CompStat[3] = "Error"
            $CompStat[4] = $("Error_0_Tries")
            #log results in $LogonLogDir+$CompStat[0]+".log" file
            Add-content $($LogonLogDir+$CompStat[0]+".log") $($DtTxt+$CompStat[2].PadRight(14)+$CompStat[3].PadRight(14)+$CompStat[4].PadRight(14))
        }
if($DebugL2){Write-Host $("hashval -Current Status-"+$CompStat[0]+", Ping:"+$hashval[$PINGidx]+", PsInvoke:"+$hashval[$PSIidx]+", PsExec:"+$hashval[$PSEidx])}
if($DebugL2){Write-Host $("compstat-Current Status-"+$CompStat[0]+", Ping:"+$CompStat[2]+", PsInvoke:"+$CompStat[3]+", PsExec:"+$CompStat[4])}
    } #END of foreach ($CompStat in $comp_prev_pass) { ... }
if($DebugL1){Write-Host *****2. End Update and Log of changes to previous status of workstations***** -ForegroundColor Blue -BackgroundColor Gray}

if( $ruLog.LOG_FILELOGGING ){      #if File Logging initialization error, execution has to be aborted
    #Check if it is time to email Alloy Navigator
    if( ((Get-Date)-$next_check).totalMinutes -ge 0 ){    #if current date >= $next_check.date
        #perform emailing to Alloy Nav
        $ruLog.ExecStage( "Initializing Workstation Remote Access Check" )
        $MsgBody = ""
        $pingNOTOK            = @()
        $pingNOTOKMsgBody     = "`n`nList of workstations that do not respond to Ping`n"
        $psinvokeNOTOK        = @()
        $psinvokeNOTOKMsgBody = "`n`nList of workstations that do not respond to PSInvoke`n"
        $psexecNOTOK          = @()
        $psexecNOTOKMsgBody   = "`n`nList of workstations that do not respond to PSExec`n"
        foreach ($CompStat in $comp_prev_pass) {
            # $comp_prev_pass[CompID, Date-Time, PingStat, PsInvokeStat, PsExecStat]
            if(     $CompStat[2] -eq "Error"    ){ $pingNOTOK += $CompStat[0] }
            elseif( $CompStat[2] -eq "OK"){
                if( $CompStat[3] -eq "Error"    ){ $psinvokeNOTOK += $CompStat[0] }
                if( $CompStat[4] -match "Error" ){ $psexecNOTOK   += $CompStat[0] }
            }
        }
        if( $pingNOTOK.Length -ne 0     ){ $MsgBody += $pingNOTOKMsgBody+($pingNOTOK -join "`n") }
        if( $psinvokeNOTOK.Length -ne 0 ){ $MsgBody += $psinvokeNOTOKMsgBody+($psinvokeNOTOK -join "`n") }
        if( $psexecNOTOK.Length -ne 0   ){ $MsgBody += $psexecNOTOKMsgBody+($psexecNOTOK -join "`n") }
        if( $MsgBody.Length -ne 0       ){ $ruLog.Notify( $ServerName+": Non-responding workstations to Ping, PSInvoke and PSExec", $MsgBody) }
        $ruLog.ExecEnd(0, $ServerName+": Completed Workstation Remote Access Check" )

        $next_check = [datetime]($((Get-Date).AddDays(1).ToLongDateString()+$TIME_TO_EMAIL))
if($DebugL1){Write-Host "Email notification has been sent to ---" -ForegroundColor Red -BackgroundColor Yellow }
    }
} ###END if( $ruLog.LOG_FILELOGGING ){ 

    #Calculate the next poll time (inclusive) (after WAIT_MINS minutes)
    $next_exec = $start_exec.AddMinutes($WAIT_MINS)
if($DebugL1){Write-Host "Next check will be performed at $($next_exec.ToShortTimeString())... " -ForegroundColor Red -BackgroundColor Yellow -NoNewLine }
    while(($next_exec - (Get-Date)).totalMinutes -gt 0 ){ Start-Sleep -s 5 }

} #End while( 1 ){...}

if($DebugL1){Write-Host $ServerName": *****End script CheckRemoteAccessStatusParallelWithLogging.ps1*****" -ForegroundColor Red -BackgroundColor White}




