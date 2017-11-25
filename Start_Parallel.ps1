#Method of operation: 
#This script executes the "DoIt.bat" file located in the same path as the script. 
#1) it reads the list of computer names in List.txt. 
#2) it runs the Start-Parallel workflow module. The module executes the tasks in the DoIt.bat file 
#   simultaneously for all the computers. 
#   To do this, it copies DoIt.bat to the target computer's C:\Temp drive. It then uses invoke-command 
#   to run an instance of cmd.exe in the target computer to execute the commands in DoIt.bat. After the 
#   job is completed, it deletes the DoIt.bat from the target's C:\Temp directory.
#4) The result is appended to the results.log file. 

#Ver 2 - 2015-06-01
# 1) Removed $commands parameter in workflow Start-Parallel - not needed
# 2) Added $debug flag to turn on/off debug output/messages. 

#Ver 1 - 2015-05-22
#Parallel version of Start.bat
#runs commands in DoIt.bat (or DoIt.ps) in parallel for a given list of workstations in PsExecFileList.txt

$debug      = $false      #set to true to turn debug messages on
$logresults = $true       #set to true if execution results are to be logged (appended) to the results log.

$comLineArgs = [System.Environment]::GetCommandLineArgs()
$ServerName  = [System.Environment]::GetEnvironmentVariable("COMPUTERNAME")

$scriptName     = $MyInvocation.MyCommand.Name                  #name of .ps1 file 
$fullScriptName = $MyInvocation.MyCommand.Path                  #full UNC pathname of .ps1 file 
$scriptDir      = $fullScriptName | Split-Path -Parent          #full UNC path of .ps1 file 
$CompList       = Get-Content $scriptDir"\List.txt"
$batchfile      = "DoIt.bat"
$comLineArgs    = [System.Environment]::GetCommandLineArgs()    #NOT Used

if($debug){ 
    Write-Host "scriptName is: "$scriptName
    Write-Host "scriptDir is: "$scriptDir
    Write-Host "fullScriptName is: "$fullScriptName
    Write-Host ">>> args are " + $comLineArgs
    Write-Host "CompList is: "$CompList
    Write-Host "batch file full path is: "$scriptDir"\"$batchfile
}


workflow Start-Parallel {
    Param([parameter(Mandatory=$true)] [object[]] $computers,
          [parameter(Mandatory=$true)] [String] $batFile,
          [parameter(Mandatory=$true)] [String] $scrDir)

    ForEach -Parallel ($comp in $computers){
        $pingResult = InlineScript { & "ping" -4 $Using:comp}

        if( ($pingResult | Select-String -Pattern "(100% loss)") -or ($pingResult | Select-String -Pattern ("could not find host")) -or ($pingResult | Select-String -Pattern ("Destination host unreachable.")) ){ 
            if    ($pingResult | Select-String -Pattern "(100% loss)")                    { $comp+"|Fail|Ping:100% loss" }
            elseif($pingResult | Select-String -Pattern ("could not find host"))          { $comp+"|Fail|Ping:Could not find host" }
            elseif($pingResult | Select-String -Pattern ("Destination host unreachable.")){ $comp+"|Fail|Ping:Destination host unreachable" }
        }
        else{
            $psiResult = InlineScript{ 
                $cmdcmd = "`"cmd.exe /c c:\Temp\$Using:batFile`""
                $sb = [Scriptblock]::Create("Invoke-Expression -Command $cmdcmd")
                $Error.Clear()
                if( (Test-Path -Path $("\\$Using:comp\c`$\Temp")) -eq $false ) {
                    New-Item -Path $("\\$Using:comp\c`$") -ItemType directory -Value Temp 
                }
                if( $Error.Count -eq 0){                                                                   #no Errors in creating remote folder C:\Temp
                    Copy-Item -Path "$Using:scrDir\$Using:batFile" -Destination "\\$Using:comp\c`$\Temp"   #copy .bat file from server to targetcomp/temp/folder
                    if( $Error.Count -eq 0){                                                               #no Errors in copying DoIt.bat to remote folder C:\Temp
                        $res = (Invoke-Command -ComputerName $Using:comp -ScriptBlock $Using:sb) #2> $null #invoke-command scriptblock executes the just copied .bat file "locally" (on the target comp)
                        Remove-Item -Path "\\$Using:comp\c`$\Temp\$Using:batFile"                          #delete .bat file from server to targetcomp/temp/folder
                        if( $Error.Count -ne 0){                                                           #no Errors in deleting DoIt.bat to remote folder C:\Temp
                            "|Fail|Remove-Item:Cannot delete DoIt.bat from folder `"C:\Temp`" in remote computer - "+$Error[0]
                            "`\n"+$Using:comp+"|Pass|  "
                        }
#                        "|Invoke-Command:|"+$res
                        "|Pass|  "
                    }
                    else{ "|Fail|Copy-Item:Cannot copy DoIt.bat to folder `"C:\Temp`" in remote computer - "+$Error[0] }
                }
                else{ "|Fail|New-Item:Cannot create folder `"C:\Temp`" in remote computer - "+$Error[0] }

            }
            $comp+$psiResult
        }
    }
}


$StatusString = Start-Parallel -computers $CompList -batFile $batchfile -scrDir $scriptDir
if($debug){
    Write-Host "StatusString is: "$StatusString
    Write-Host "StatusString length is: "$StatusString.Count
}

#helper function WriteToLog writes the sring
function WriteToLog {
    param([String]$dest, [String]$str1, [String]$str2, [String]$str3, [Int]$spacing)

    Add-Content $dest $(($str1.trim()).PadRight($spacing)+($str2.trim()).PadRight($spacing)+$str3.trim())
}

#Save the results in results.log file
if($logresults){

    #Convert $StatusString and update hash array format
    if( (Test-Path $($scriptDir+"\results.log")) -eq $false ) {
        New-Item $($scriptDir+"\results.log") -type file | Out-Null
        Add-Content $($scriptDir+"\results.log") $("--------------------------------------------------------------")
#        Add-Content $($scriptDir+"\results.log") $("Computer Name".PadRight(14)+"Ping".PadRight(14)+"PsInvoke".PadRight(14))
        WriteToLog -dest $scriptDir"\results.log" -str1 "Computer Name" -str2 "Status" -str3 "Description" -spacing 18
        Add-Content $($scriptDir+"\results.log") $("--------------------------------------------------------------")
    }

    $idt = Get-Date
    $idtTxt = $idt.ToShortDateString().PadRight(12) + $idt.ToShortTimeString().PadRight(10)
    Add-Content $($scriptDir+"\results.log") $("***** <"+$idtTxt+"> *****")
    Add-Content $($scriptDir+"\results.log") $("--------------------------------------------------------------")
    foreach( $line in $StatusString ){
        $linearr = $line.Split("|")
#        Add-Content $($scriptDir+"\results.log") $(($linearr[0].trim()).PadRight(14)+($linearr[1].trim()).PadRight(14)+$linearr[2].trim())
        WriteToLog -dest $scriptDir"\results.log" -str1 $linearr[0] -str2 $linearr[1] -str3 $linearr[2] -spacing 18
        if($linearr.Length -eq 6){
            WriteToLog -dest $scriptDir"\results.log" -str1 $linearr[3] -str2 $linearr[4] -str3 $linearr[5] -spacing 18
        }
    }
}


####################################################################################################




