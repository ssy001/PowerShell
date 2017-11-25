### This script copies registry key values (and recursively copies subkey values) from one registry location to another
### Precondition(s): 
### 1) destination registry key must exist - keys (and subkeys) must have the same structure and values as source key

### Function: CopyKey
### Description: copies registry key values from srcpath to dstpath. 
### Param(s):
### 1) srcpath - source registry path
### 2) dstpath - destination registry path
### Return value(s): None

function CopyKey ($srcpath, $dstpath ) {

    ### copies all values (including default value if used) in current key
    $regKey = Get-Item -Path $srcpath 
    ForEach ($prop in $regKey.Property ) {
        if( $prop -eq "(default)") { 
            $defaultProp = Get-ItemProperty -Path $srcpath -Name '(Default)'
            Set-ItemProperty -Path $dstpath -Name '(default)' -Value $defaultProp.'(default)'
        }
        else { Set-ItemProperty -Path $dstpath -name $prop -Value $regKey.getValue($prop) }
    }

    ### parse source path for each subkey and recursive calls CopyKey
    Get-ChildItem $srcpath -Recurse | ForEach-Object { Get-ItemProperty $_.pspath } | 
    % { 
        $origprefix = $srcpath -replace '\\', '\\' 
        $newprefix = $dstpath
        $origStr = $_.pspath
        $newStr = $origStr -replace $origprefix, $newprefix
        CopyKey $origStr $newStr
    }
} ### END of function CopyKey() ...


### preset location variables
$autoLogonKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$passKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SECURITY\Policy\Secrets\DefaultPassword'
$winLogonKey = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' #same path as $autoLogonKeyLoc
$lastUser = $winLogonKey.DefaultUserName
$currentUser = (Get-WmiObject win32_computersystem).username  
if($currentUser.contains("\")){   ### parse current username
    $currentUser = $currentUser | Split-Path -leaf
}
$localHostName = $env:COMPUTERNAME

### updates registry keys to current user's login & pass keys
#if ($currentUser.ToLower() -ne $lastUser.ToLower()){   
    if ($currentUser.ToLower() -eq "kiosk" ){ 
        $currentUserKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\---'
        $currentUserpassKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\---'
#        CopyKey $currentUserKeyLoc $autoLogonKeyLoc
        CopyKey $currentUserpassKeyLoc $passKeyLoc
    }
    elseif ($currentUser.ToLower() -eq "presenter" ){ 
        $currentUserKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\---'
        $currentUserpassKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\---'
        CopyKey $currentUserKeyLoc $autoLogonKeyLoc
        CopyKey $currentUserpassKeyLoc $passKeyLoc
    }
#}


