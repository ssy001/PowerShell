
### Part I: Ensure that drives are mapped in the desired order
# 1. Verify Boot (system) volume is mapped to drive C
# 2. Verify Rest of partition's volume is mapped to drive D
# 3. Verify DVD/CD is mapped to drive E (if DVD/CD drive exists)
# 4. If either 1,2,3 is not true, then
#    a. show information message to notify admin which drive is incorrectly assigned
#    b. after admin clicks ok, open Registry Editor and set key at HKLM\System\MountedDevices


# 1. Verify Boot (system) volume is mapped to drive C
# Soln: Check that C: is system drive, and Check that "Image.vhdx" exists in d:\folder
$envVar = Get-Item -Path Env:*
$envVarHT = @{}
#convert dictionary entry to hashtable
foreach ($item in $envVar){   #add entries to hashtable
    $envVarHT.Add($item.Name, $item.Value)
} 
$sysDrive = $envVarHT.SystemDrive

$global:isDriveChanged = $false
if( $sysDrive -ne "C:" ){
    # send message to notify admin that system drive is not C:
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $message = "System Drive is not set to `"C:`". Open Registry Editor?"
    $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 4)
    if ($response -eq "YES" ) 
    {
        $global:isDriveChanged = $True
        # after admin (user) clicks ok, open Registry at key "HKLM\System\MountedDevices"
        $progPath = $sysDrive + "\sys\sysinternals\regjump.exe"
        $regKey = "HKLM:\system\MountedDevices"
        & $progPath $regKey
    }
    else{ return }
}
else { "System Drive is set to C:" | Write-Host }

# 2. Verify Rest of partition's volume is mapped to drive D
$imagePath = "D:\"
$imageFilename = "PC_Image_Win81.VHDX"

if ( (Test-Path ($imagePath+$imageFilename)) -eq $false ){
    $message = "Main partition is not mapped to `"D:`". Open Registry Editor?"
    Add-Type -AssemblyName System.Windows.Forms
    $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 4)
    if ($response -eq "YES" ) 
    {
        $global:isDriveChanged = $True
        $progPath = $systemDrive + "\sys\SysinternalsSuite\regjump.exe"
        $regKey = "HKLM:\system\MountedDevices"
        & $progPath $regKey
    }
    else{ return }
}
else { "Main partition is mapped to D:" | Write-Host }

### Restart-computer if 1. system drive or 2. partiton volume as D: is changed
<#
if ($global:isDriveChanged) {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $message = "Drives assignments have been changed. Restart Computer?"
    $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 4)
    if ($response -eq "YES" ) 
    {
        $global:isDriveChanged = $false
        Restart-Computer 
    }
}
#>
if ($global:isDriveChanged) {
#    $message = "Drive assignments have been changed. Please restart the computer. Script will now exit."
#    $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 0)
    return
}

# Part II: Modify User Profile location to "D:\Users"
#    3.1. Verify (or create) that "Users" folder exists
#    3.2. Change HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\ProfilesDirectory value to "D:\Users"


#Set user profile folder to "D:\Users", create dir if necessary
$userProfileKeyLoc = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$userProfileDirNew = "D:\Users"
$userPropName = "ProfilesDirectory"

$userProfileDirOld = (Get-ItemProperty -Path $userProfileKeyLoc -name $userPropName).profilesdirectory
if( $userProfileDirOld -ne $userProfileDirNew ){
#    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
#    $message = "User profile is $userProfileDirOld, do you want to change it to `"D:\Users`"?"
#    $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 4)
#    if ($response -eq "YES" ) 
#    {
        if ( (Test-Path -PathType Container -Path $userProfileDirNew) -eq $false) {
            New-Item -ItemType Directory -Path $userProfileDirNew
        }
        Set-ItemProperty -Path $userProfileKeyLoc -name $userPropName -Value $userProfileDirNew
        [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
        $message = "User Profile Directory has been changed to `"$userProfileDirNew`"."
        $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 0)
#    }
}


### Part III: Assign computer name and join to domain
# 1. Check if computer is part of domain ---
# 2. if(1. is false) Show message requesting computer name, restart
# 3. if(1. is false) Show message to confirm to join domain, restart

$compName = $envVarHT.COMPUTERNAME
$domainName = "---.ryerson.ca"
$domainName = (gwmi win32_computersystem).Domain
$global:isCompNameChanged = $True

if ( $domainName -ne $domainName) {

    # Creates windows form to input computer name
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 
    $objForm = New-Object System.Windows.Forms.Form 
    $objForm.Text = "Message"
    $objForm.Size = New-Object System.Drawing.Size(480,210) 
    $objForm.StartPosition = "CenterScreen"
    $objForm.KeyPreview = $True
    $objForm.Add_KeyDown({if ($_.KeyCode -eq "Enter") {
        $newCompName=$objTextBox1.Text;$objForm.Close()
        #Renames computer with new name
#        Rename-Computer -ComputerName $compName -NewName $newCompName -LocalCredential $localCredential -Restart -WhatIf
#        Rename-Computer -ComputerName $compName -NewName $newCompName #-Restart
       Add-Computer -ComputerName $compName -NewName $newCompName -DomainName $domainName #-Restart
       $message = "Computer $newCompName will be joined to domain $domainName after restart. Script will now exit."
       $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 0)
       return
        }
    })
    $objForm.Add_KeyDown({if ($_.KeyCode -eq "Escape") {
#        Set-Variable -Name $isCompNameChanged -Value $false -Scope Global
        $global:isCompNameChanged = $false
        $objForm.Close()
        }
    })

    $OKButton = New-Object System.Windows.Forms.Button
    $OKButton.Location = New-Object System.Drawing.Size(155,120)
    $OKButton.Size = New-Object System.Drawing.Size(75,23)
    $OKButton.Text = "OK"
    $OKButton.Add_Click({
        $newCompName=$objTextBox1.Text;$objForm.Close()
        #Renames computer with new name
#        Rename-Computer -ComputerName $compName -NewName $newCompName -LocalCredential $localCredential -Restart -WhatIf
#        Rename-Computer -ComputerName $compName -NewName $newCompName #-Restart
       Add-Computer -ComputerName $compName -NewName $newCompName -DomainName $domainName #-Restart
       $message = "Computer $newCompName will be joined to domain $domainName after restart. Script will now exit."
       $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 0)
       return
    })
    $objForm.Controls.Add($OKButton)

    $CancelButton = New-Object System.Windows.Forms.Button
    $CancelButton.Location = New-Object System.Drawing.Size(230,120)
    $CancelButton.Size = New-Object System.Drawing.Size(75,23)
    $CancelButton.Text = "Cancel"
    $CancelButton.Add_Click({
#        Set-Variable -Name $isCompNameChanged -Value $false -Scope Global
        $global:isCompNameChanged = $false
        $objForm.Close()
    })
    $objForm.Controls.Add($CancelButton)

    $objLabel1 = New-Object System.Windows.Forms.Label
    $objLabel1.Location = New-Object System.Drawing.Size(10,20) 
    $objLabel1.Size = New-Object System.Drawing.Size(440,20) 
    $objLabel1.Text = "Computer name is $compName. Do you want to change the name?"
    $objForm.Controls.Add($objLabel1) 

    $objLabel2 = New-Object System.Windows.Forms.Label
    $objLabel2.Location = New-Object System.Drawing.Size(10,40) 
    $objLabel2.Size = New-Object System.Drawing.Size(440,20) 
    $objLabel2.Text = "Enter new computer name: "
    $objForm.Controls.Add($objLabel2) 

    $objTextBox1 = New-Object System.Windows.Forms.TextBox 
    $objTextBox1.Location = New-Object System.Drawing.Size(10,60) 
    $objTextBox1.Size = New-Object System.Drawing.Size(440,20) 
    $objForm.Controls.Add($objTextBox1) 

    $objLabel3 = New-Object System.Windows.Forms.Label
    $objLabel3.Location = New-Object System.Drawing.Size(10,80) 
    $objLabel3.Size = New-Object System.Drawing.Size(440,50) 
    $objLabel3.Text = "Click OK to apply changes."
    $objForm.Controls.Add($objLabel3) 

    $objForm.Topmost = $True
    $objForm.Add_Shown({$objForm.Activate()})
    [void] $objForm.ShowDialog()

#    "Press any key to continue ..." | Write-Host
#    $x = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

#    "Computer name change state is $iscompNameChanged" | Write-Host
    #If Computer Name has been previously changed, but computer not part of domain ---
    #Then join computer to domain 
<#
    if( $global:isCompNameChanged -eq $false ){

        $objForm2 = New-Object System.Windows.Forms.Form 
        $objForm2.Text = "Message"
        $objForm2.Size = New-Object System.Drawing.Size(320,155) 
        $objForm2.StartPosition = "CenterScreen"

        $objForm2.KeyPreview = $True
        $objForm2.Add_KeyDown({if ($_.KeyCode -eq "Enter") {
            $objForm2.Close()
            #Join Computer with new Name to domain
            Add-Computer -ComputerName $compName -DomainName $domainName #-Restart
        }})
        $objForm2.Add_KeyDown({if ($_.KeyCode -eq "Escape") {   
            $objForm2.Close()
            $message = "Computer is not joined to domain `"---`". Script will now exit."
            $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 0)
            }})

        $OKButton2 = New-Object System.Windows.Forms.Button
        $OKButton2.Location = New-Object System.Drawing.Size(75,80)
        $OKButton2.Size = New-Object System.Drawing.Size(75,23)
        $OKButton2.Text = "OK"
        $OKButton2.Add_Click({
            $objForm2.Close()
            #Join Computer with new Name to domain
            Add-Computer -ComputerName $compName -DomainName $domainName #-Restart
        })
        $objForm2.Controls.Add($OKButton2)

        $CancelButton2 = New-Object System.Windows.Forms.Button
        $CancelButton2.Location = New-Object System.Drawing.Size(150,80)
        $CancelButton2.Size = New-Object System.Drawing.Size(75,23)
        $CancelButton2.Text = "Cancel"
        $CancelButton2.Add_Click({
            $objForm2.Close()
            $message = "Computer is not joined to domain `"---`". Script will now exit."
            $response= [System.Windows.Forms.MessageBox]::Show($message, "Warning", 0)
            })
        $objForm2.Controls.Add($CancelButton2)

        $objLabel21 = New-Object System.Windows.Forms.Label
        $objLabel21.Location = New-Object System.Drawing.Size(10,20) 
        $objLabel21.Size = New-Object System.Drawing.Size(280,20) 
        $objLabel21.Text = "Computer name is $compName"
        $objForm2.Controls.Add($objLabel21) 

        $objLabel22 = New-Object System.Windows.Forms.Label
        $objLabel22.Location = New-Object System.Drawing.Size(10,40) 
        $objLabel22.Size = New-Object System.Drawing.Size(300,50) 
        $objLabel22.Text = "Do you want to join this computer to the domain `"---`"?" #`r NOTE: Computer will restart"
        $objForm2.Controls.Add($objLabel22) 

        $objForm2.Topmost = $True
        $objForm2.Add_Shown({$objForm2.Activate()})
        [void] $objForm2.ShowDialog()

    }
#>
}

#>
