### AccessCredentials reads and writes to various device credentials file 
### Structure of Credentials file
### CredName: <Name1>
### |---> LoginName: <loginName1>
### |---> Password: <password1>
### CredName: <Name2>
### |---> LoginName: <loginName2>
### |---> Password: <password2>

$ACDebugMode = $false

$ruCred = New-Object System.Object
$Res = $ruCred | Add-Member -MemberType NoteProperty -name CR_CREDNAME -value ""
$Res = $ruCred | Add-Member -MemberType NoteProperty -name CR_LOGINNAME -value ""
### ????? Can I save a securestring type to an object's NoteProperty Parameter ????? 
$Res = $ruCred | Add-Member -MemberType NoteProperty -name CR_PASSWORD -value ""
### ????? Maybe can store $CredFilePath and $NameToSearch as NoteProperties

#################################################
### method: ReadCredentials 
### - reads the userID and decodes the password from the credentials file path parameter
### - It searches for the record with the credential name from the CR_CREDNAME NoteProperty
### parameters: 
### - [string] CredFilePath - path of the credentials file
### Return values: [int]
### 0 - credentials read succesfully
### 1 - credentials record not found
### 2 - file access error: unable to read $CredFilePath
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruCred -Name ReadCredentials -Value `
{
    param( [string]$CredFilePath )
    
    try{ $credArray = Get-Content -Path $CredFilePath }
    catch{ return 2 } #file access error: unable to read $CredFilePath
    $index=0
    $found = $false
    while( ($index -lt $credArray.Length) ){
        if( $credArray[$index] -match "^CredName" ){
            $CredName= ($credArray[$index] -split " ")[1]
            $LoginName= ($credArray[$index+1] -split " ")[1]
            $encryptedPassword= ($credArray[$index+2] -split " ")[1]
            
            $securePassword = $encryptedPassword | ConvertTo-SecureString
            $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $LoginName, $securePassword
            $plainPassword = $Credentials.GetNetworkCredential().Password
            #NOTE: The record name to search is contained in $this.CR_CREDNAME
            if( $ACDebugMode ) { "CredName is " + $CredName + ", Index is " + $index | Write-Host }
            if( $CredName -eq $this.CR_CREDNAME ){
                $found = $true
                break
            }
            $index+=3
        }
        else{ $index++ }
    }    
    
if( $ACDebugMode ) { "Found is $found" | Write-Host }    
    if( $found ){
        ### store these in the object NoteProperty parameters
        $this.CR_LOGINNAME = $LoginName
        $this.CR_PASSWORD = $plainPassword
        #"In function ReadCredentials, " + $LoginName + " - " + $Password | Write-Host
        return 0
    }
    else{ return 1 }    #credentials record not found
    
}

#################################################
### method: WriteCredentials 
### - appends the new credentials to the credentials file
### parameters: 
### - [string] CredFilePath - path of the credentials file
### Return values: [int]
### 0 - credentials appended succesfully
### 1 - credentials record found (i.e. already in file)
### 2 - file access error: unable to read $CredFilePath
#################################################
Add-Member -MemberType ScriptMethod -InputObject $ruCred -Name WriteCredentials -Value `
{
    param( [string]$CredFilePath )

    ### Before writing credentials to file, Check to make sure that it is not in file. 
    try{ $credArray = Get-Content -Path $CredFilePath }
    catch{ return 2 }
    $index=0
    $found = $false
    while( $index -lt $credArray.Length ){
        if( $credArray[$index] -match "^CredName" ){
            $CredName= ($credArray[$index] -split " ")[1]
            #NOTE: The record name to search is contained in $this.CR_CREDNAME
            "In function WriteCredential, CredName is " + $CredName | Write-Host
            if( $CredName -eq $this.CR_CREDNAME ){
                $found = $true
                break
            }
        }
        $index++
    }    
    if( $found ){ return 1 }
    else{    #append new record to file
        $writeStr = "CredName: " + $this.CR_CREDNAME + "`n" 
        $writeStr += "LoginName: " + $this.CR_LOGINNAME + "`n"
        
        $securePassword = $this.CR_PASSWORD | ConvertTo-SecureString -Force -AsPlainText
        $encryptedPassword = $securePassword | ConvertFrom-SecureString
        $writeStr += "Password: " + $encryptedPassword 
        $writeStr | Add-Content -Path $CredFilePath
        return 0
    }    

}


### WARNING: Testing Area !!! ###
#$path = "\\scripts\Credentials.txt"

<#
### Test Read Credentials
$ruCred.CR_CREDNAME = "BBB"
if ( !($ruCred.ReadCredentials( $path )) ){
    "Record Found !!!" | Write-Host
    "CredName: " + $ruCred.CR_CREDNAME | Write-Host
    "LoginName: " + $ruCred.CR_LOGINNAME | Write-Host
    "Password: " + $ruCred.CR_PASSWORD | Write-Host
}
else{
    "Record NOT Found !!!" | Write-Host
}
#>

<#
### Test Write Credentials
$ruCred.CR_CREDNAME = "BBB"
$ruCred.CR_LOGINNAME = "apc"
$ruCred.CR_PASSWORD = "mJ6xE2J"

if ( !($ruCred.WriteCredentials( $path )) ){
    "Record successfully written to file." | Write-Host
}
else{
    "Record with same name already exists in file." | Write-Host
}
#>
