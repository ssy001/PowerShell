### ---------- ###
### NAME - FixItWizard.ps1
### VERSION - 1.0 
### DATE - 2015-07-07
### ---------- ###

#v14 changes:
#1 - add default entry in combo box "Select a topic from the list"
#v13 changes:
#1 - interface resized; logo changed
#v12 changes:
#1 - ".lnk" shorcuts that this script reads the are created manually with absolute paths
#2 - error handling (in function "ListBox_Click") for the case when shortcut targets are invalid
#3 - commented out the code segment (in function "ListBox_Click") which checks for arguments and absolute paths
#v11 changes:
#1 - folder contents stores shortcuts to actual troubleshooting script. Shortcuts' target is read and processed by the wizard form
#2 - category entries (problem issues) and paths are hard-coded into folder hashtables
#3 - made changes to event handler functions ListBox_Click, FixItComboBox_AddSubfolders, FixItComboBox_UpdateBoxContents
#v10 changes:
#1 - removed commented sections and unnecessary code
#2 - used relative paths for script resources' locations and absolute paths for log file location
#v9 changes:
#1 - Removed "FixIt" button. 
#2 - To handle fix it's pop-ups, if an item in the list box is selected, the pop-up will be shown asking whether user wants to fix the item.
#    If the item is clicked again, it is deselected.
#3 - Moved "Ryerson University" logo from bottom left to top right corner
#v8 changes:
#1 - "FixIt" button moved to column beside listbox
#v7 changes:
#1 - listbox choices are not initially highlighted/selected. This is true during startup and also when a category is changed.
#2 - "FixIt" button is enabled if a choice is selected
#v6 changes:
#1 - Changed background image to background color
#2 - added ryerson logo to bottom left of panel
#3 - fixed spacing between controls
#v4 changes:
#1 - resolved error "You cannot call a method on a null-valued expression." when changing ComboBox selections or clicking FixIt button
#v3 changes:
#1 - moved initialization procedures to InitializeForm()
#2 - moved table layout panel code to SetFixItPanel()
#v2 changes:
#1 - Added tablelayoutpanel to form


#read foldernames into array
#for each foldername, read filenames into foldername_array
function ListSubFolders { 
    param([parameter(Mandatory=$true)] [String] $path)

    $folderList = [System.IO.Directory]::EnumerateDirectories($path)
    return $folderList
}

function FixItComboBox_AddSubfolders {
    param([parameter(Mandatory=$true)] [System.Array] $folderList,
          [parameter(Mandatory=$true)] [System.Windows.Forms.ComboBox] $comboBox,
          [parameter(Mandatory=$true)] [System.Collections.Hashtable] $folderListHT)

    foreach ($fullpath in $folderList){
        $fileList = [System.IO.Directory]::GetFiles($fullpath)
        #if( ($fileList.Length -gt 0) -and (( @($fileList -like "*.txt").Count -gt 0) -or ( @($fileList -like "*.ps1").Count -gt 0) -or ( @($fileList -like "*.lnk").Count -gt 0)) ){
        #if( ($fileList.Length -gt 0) ){
        if( ($fileList.Length -gt 0) -and (( @($fileList -like "*.lnk").Count -gt 0)) ){
            $folder = $fullpath | Split-Path -leaf
            [void]$comboBox.Items.Add($folder)
            [void]$folderListHT.Add($folder,$fullpath)
        }
    }
}

<#
#function FindShortcuts - assigns a shortcut object to each entry in the listBox
function FindShortcuts {
    param([parameter(Mandatory=$true)] [System.String] $selectedItem,
          [parameter(Mandatory=$true)] [System.Collections.Hashtable] $folderListHT,
          [parameter(Mandatory=$true)] [System.Windows.Forms.ListBox] $listBox,
          [parameter(Mandatory=$true)] [System.Collections.Hashtable] $listBoxFilesHT,
          [parameter(Mandatory=$true)] [System.String] $probListFile)

    [void]$listBox.Items.Clear()
    [void]$listBoxFilesHT.Clear()
    $probListFilep = New-Object System.IO.StreamReader($probListFile)
    $problemLine = $probListFilep.ReadLine()
    while( $problemLine -ne $null ){
        #Write-Host problem Line is $problemLine
        if( $problemLine.Trim().Equals($selectedItem) ){
            $problemLine = $probListFilep.ReadLine()
            while( ($problemLine -ne $null) -and ([System.Text.RegularExpressions.Regex]::IsMatch($problemLine.Trim(),"^[0-9]")) ){
                $problemLineArr = $problemLine.Trim().Split("|")      #tokenize into strings with "|"" delimiter
                $teststr = $problemLineArr[1]
                Write-Host "problem Line Arr is $($problemLineArr[0]), $($problemLineArr[1]).lnk"
                $wsShellObj = New-Object -ComObject WScript.Shell
                $shortcutObj = $wsShellObj.CreateShortcut("$($PSScriptRoot)\$selectedItem\$($problemLineArr[1]).lnk")
                $targetPath = $shortcutObj.TargetPath
                foreach( $arg in $shortcutObj.Arguments){
                    $targetPath += "|$PSScriptRoot\$selectedItem\$arg"
                    Write-Host "arg --- $arg"
                }
                Write-Host "Shortcut has $shortcutObj.Arguments as args"
                Write-Host "Shortcut path is --- $($PSScriptRoot)\$selectedItem\$($problemLineArr[1]).lnk"
                [void]$listBox.Items.Add("$($problemLineArr[0])")
                [void]$listBoxFilesHT.Add("$($problemLineArr[0])",$targetPath)
                Write-Host "targetPath is $targetPath, shortcut file is $($problemLineArr[1].Trim()).lnk"
                Write-Host "problem Line Arr[0] length is $($problemLineArr[0].Length)"
                $problemLine = $probListFilep.ReadLine()
            }
            break
        }
        $problemLine = $probListFilep.ReadLine()
    }
    #fclose($probListFilep)
    [void]$probListFilep.Close()
}
#>

function FixItComboBox_UpdateBoxContents {
    param([parameter(Mandatory=$true)] [System.String] $selectedItem,
          [parameter(Mandatory=$true)] [System.Collections.Hashtable] $folderListHT,
          [parameter(Mandatory=$true)] [System.Windows.Forms.ListBox] $listBox,
          [parameter(Mandatory=$true)] [System.Collections.Hashtable] $listBoxFilesHT )

    $fileList = [System.IO.Directory]::EnumerateFiles($folderListHT[$selectedItem])
    [void]$listBox.Items.Clear()
    [void]$listBoxFilesHT.Clear()
    foreach ($fullpath in $fileList){    #show the filename's comment type in comboBox
        #Write-Host fullpath is $fullpath
        if( [System.IO.Path]::GetExtension($fullpath) -eq ".lnk" ){
            $filename = $fullpath | Split-Path -leaf
            $entryname = [System.IO.Path]::GetFileNameWithoutExtension($filename)
            #Write-Host "entry name is $entryname, path is $fullpath"
            [void]$listBox.Items.Add($entryname)
            [void]$listBoxFilesHT.Add($entryname,$fullpath)
        }
<#
        $filep = New-Object System.IO.StreamReader($fullpath)
        $comment = $filep.ReadLine()
        if( ($comment -ne $null) -and $comment.Contains("#") ){
            $comment = $comment.Split("#")[1].Trim()
            [void]$listBox.Items.Add($comment)
            [void]$listBoxFilesHT.Add($comment,$fullpath)
        }
        [void]$filep.Close()
#>
    }

    $graphics1 = $listBox.CreateGraphics()    #ensure that last character of listBox entries is visible
    $maxHorSize = 0
    foreach ( $item in $listBox.Items){ 
        $horSize = [Int]$graphics1.MeasureString($item.ToString(), $listBox.Font).Width
        if( $horSize -ge $maxHorSize ){ 
            $maxHorSize = $horSize 
        }
    }
    $listBox.HorizontalExtent = $maxHorSize + 10
    [void]$listBox.ClearSelected()
    $global:fixItListBoxSelectedItem = ""
}

function ListBox_Click{
    param([parameter(Mandatory=$true)] [System.Windows.Forms.TableLayoutPanel] $middleLayoutPanel,
          [parameter(Mandatory=$true)] [System.Collections.Hashtable] $listBoxFilesHT )

    #Write-Host listbox Files HT is $listBoxFilesHT
    if($middleLayoutPanel.GetControlFromPosition(0,1).SelectedItem -eq $null){   #check if listBox has no selected item
        [System.Windows.Forms.MessageBox]::Show($wizardForm, "You must select an item from the table first", "Information")
    }
    else{    
        $selectedItem = $middleLayoutPanel.GetControlFromPosition(0,1).SelectedItem.ToString()
        #Write-Host selectedItem is $selectedItem
        #if user deselects the current selected item
        if( $selectedItem.equals($global:fixItListBoxSelectedItem) ){
            $middleLayoutPanel.GetControlFromPosition(0,1).SelectedIndex = -1
            $global:fixItListBoxSelectedItem = ""
        }
        #if user selects a new item, then call the fix it procedure
        else{ 
            Clear-Variable fixItListBoxSelectedItem -Scope Global
            Set-Variable fixItListBoxSelectedItem -Scope Global -Value $selectedItem -Force 
            if ($selectedItem.Equals("") ){
                [System.Windows.Forms.MessageBox]::Show($wizardForm, "You must select an item from the table first", "Error")
            }
            else{
                $result = [System.Windows.Forms.MessageBox]::Show($wizardForm, "Do you want to run `"$selectedItem`" wizard`?", 'Information', 'YesNo')
                if( $result -eq 'Yes'){
                    #this section assumes that 
                    #(i) all values in $listBoxFilesHT are .lnk files, 
                    #(ii) all target in .lnk files are .ps1 files
                    #Write-Host "listbox files HT selected item is --- $($listBoxFilesHT[$selectedItem])"
                    $wsShellObj = New-Object -ComObject WScript.Shell
                    $shortcutObj = $wsShellObj.CreateShortcut("$($listBoxFilesHT[$selectedItem])")
                    $shortcutTarget = $shortcutObj.TargetPath
                    #Write-Host "shortcut target is $shortcutTarget"
                    try{
                        #$procObj = new System.diagnostics.ProcessStartInfo(
                        $psProcess = [System.Diagnostics.Process]::Start("powershell.exe", "-NoLogo -NoProfile -WindowStyle Hidden -File `"$shortcutTarget`"") 
                    }
                    catch{
                        $ErrorMessage = $_.Exception.Message
                        $FailedItem = $_.Exception.ItemName
                        #Write-Host "Unable to process shortcut target $FailedItem`: $ErrorMessage"
                        break
                    }

<#
                    ########## This section below is reserved for future implementations of relative paths
                    Write-Host entry file is $listBoxFilesHT[$selectedItem] 
                    $entries = $($listBoxFilesHT[$selectedItem]).Split("|")
                    $fileExt = $listBoxFilesHT[$selectedItem] | Split-Path -leaf
                    if( [System.IO.Path]::GetExtension($fileExt) -eq ".lnk" ){
                        $shortcutObj = New-Object -COM WScript.Shell
                        $shortcutTarget = $shortcutObj.CreateShortcut($listBoxFilesHT[$selectedItem]).TargetPath
                        [System.Diagnostics.Process]::Start("powershell.exe", $shortcutTarget)
                    }
                    elseif( [System.IO.Path]::GetExtension($fileExt) -eq ".ps1" ){
                        if($entries.count -gt 1){
                           [System.Diagnostics.Process]::Start("powershell.exe", $entries[1])
                        }
                        else{
                           [System.Diagnostics.Process]::Start("powershell.exe", $listBoxFilesHT[$selectedItem])
                        }
                    }
                    else{
                        if($entries.count -gt 1){
                            [System.Diagnostics.Process]::Start($entries[0],$entries[1])
                        }
                        else{
                            [System.Diagnostics.Process]::Start($entries[0])
                        }
                    }
#>
                }
                else{   #display a message balloon in the notification area
                    <#
                    $notifyIcon1 = New-Object System.Windows.Forms.NotifyIcon
                    $notifyIcon1.Icon = New-Object System.Drawing.Icon($PSScriptRoot+"\NotifyIcon.ico")
                    $notifyIcon1.BalloonTipText = "ARCH Fix It Wizard: `n$selectedItem `nwas cancelled by user"
                    $notifyIcon1.BalloonTipTitle = "Information"
                    $notifyIcon1.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
                    $notifyIcon1.Visible = $true
                    $notifyIcon1.ShowBalloonTip(3500)
                    $notifyIcon1.Add_BalloonTipClosed({ NotifyIcon_Close -notifyIcon $notifyIcon1 })
                    #>
                }
            }
        }
    }
}

function NotifyIcon_Close{ 
    param( [System.Windows.Forms.NotifyIcon] $notifyIcon )

    $notifyIcon.Dispose()

}

function InitializeLog{
    param( [Parameter(Mandatory=$true)] [System.String] $logFolder,
           [Parameter(Mandatory=$true)] [System.String] $logFile)

    if( (Test-Path -PathType Container -Path $logFolder) -eq $false){
        $newDir = New-Item -ItemType Directory -Path $logFolder
        if( $newDir -eq $null ){       #if log folder cannot be created
            $logEnable = $false 
            return
        }
    }
    if( (Test-Path -Path $($logFolder+"\"+$logFile)) -eq $false){
        $newFile = New-Item $($logFolder+"\"+$logFile) -Type file
        if( $newFile -eq $null){       #if log file cannot be created
            $logEnable = $false 
            return
        }
        else{ 
            Add-Content $($logFolder+"\"+$logFile) $("---") 
        }
    }
}

function AddLogEntry{
    param( [Parameter(Mandatory=$true)] [System.String] $logFolder,
           [Parameter(Mandatory=$true)] [System.String] $logFile,
           [Parameter(Mandatory=$true)] [System.String] $logEntry )

    Add-Content $($logFolder+"\"+$logFile) $logEntry
}

function InitializeWizardForm(){
    $wizardForm.Name = "wizardForm"
    $wizardForm.Text = "Arch IT Fix It Wizard"
    $wizardForm.Width = 800
    $wizardForm.Height = 622
    $wizardForm.BackColor = "#FFFFFFF0"
    #$wizardForm.BackColor = "#FF303030"
    $wizardForm.WindowState = "Normal"     # Maximized, Minimized, Normal
    $wizardForm.SizeGripStyle = "Hide"     # Auto, Hide, Show
    $wizardForm.ShowInTaskbar = $True
    $wizardForm.Opacity = 0.97             # 1.0 is fully opaque; 0.0 is invisible
    $wizardForm.StartPosition = "CenterScreen" # CenterScreen, Manual, WindowsDefaultLocation, WindowsDefaultBounds, CenterParent

    $wizardForm.add_FormClosing({ WizardForm_ClosingTerminate })
    #$wizardForm.add_FormClosed({ WizardForm_Terminate })
}

function WizardForm_ClosingTerminate(){
    Test-Path variable:wizardForm
    Test-Path Variable:fixItTableLayoutPanel
    Test-Path Variable:fixItComboBoxFolderListHT
    Test-Path variable:fixItListBoxFilesHT
    Test-Path variable:global:fixItListBoxSelectedItem
}

function WizardForm_Terminate(){

<#    if(Test-Path variable:wizardForm){ 
        try{ Remove-Variable $wizardForm } 
        catch{ 
            Write-Host cannot remove wizardForm 
            AddLogEntry -logFolder $logFolder -logFile $logFile -logEntry "cannot remove wizardForm"
            } }
    if(Test-Path Variable:fixItTableLayoutPanel){ 
        try{ Remove-Variable $fixItTableLayoutPanel } 
        catch{ 
            Write-Host cannot remove fixItTableLayoutPanel 
            AddLogEntry -logFolder $logFolder -logFile $logFile -logEntry "cannot remove fixItTableLayoutPanel "
            } }
    if(Test-Path Variable:fixItComboBoxFolderListHT){ 
        try{ Remove-Variable $fixItComboBoxFolderListHT } 
        catch{ 
            Write-Host cannot remove fixItComboBoxFolderListHT
            AddLogEntry -logFolder $logFolder -logFile $logFile -logEntry "cannot remove fixItComboBoxFolderListHT"
        } }
    if(Test-Path variable:fixItListBoxFilesHT){ 
        try{ Remove-Variable $fixItListBoxFilesHT } 
        catch{ 
            Write-Host cannot remove fixItListBoxFilesHT 
            AddLogEntry -logFolder $logFolder -logFile $logFile -logEntry "cannot remove fixItListBoxFilesHT "
        } }
    if(Test-Path variable:global:fixItListBoxSelectedItem){ 
        try{ Remove-Variable $global:fixItListBoxSelectedItem } 
        catch{ 
            Write-Host cannot remove global:fixItListBoxSelectedItem
            AddLogEntry -logFolder $logFolder -logFile $logFile -logEntry "cannot remove global:fixItListBoxSelectedItem"
        } }
#>
}

function CreateFixItTableLayoutPanel(){
    $fixItTableLayoutPanel.Name = "fixItTableLayoutPanel"
    $fixItTableLayoutPanel.ColumnCount = 1
    $fixItTableLayoutPanel.RowCount = 2
    $rowStyleAutoSize0 = New-Object System.Windows.Forms.RowStyle( [System.Windows.Forms.SizeType]::AutoSize )
    $rowStylePercent1 = New-Object System.Windows.Forms.RowStyle( [System.Windows.Forms.SizeType]::Percent,100 )
    [void]$fixItTableLayoutPanel.RowStyles.Add( $rowStyleAutoSize0 )
    [void]$fixItTableLayoutPanel.RowStyles.Add( $rowStylePercent1 )
    $fixItTableLayoutPanel.AutoScroll = $True
    $fixItTableLayoutPanel.AutoSize = $True
    $fixItTableLayoutPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    #$fixItTableLayoutPanel.BackColor = [System.Drawing.Color]::AliceBlue
    $fixItTableLayoutPanel.BackColor = "#FF1A7BA5"
    $fixItTableLayoutPanel.Padding = New-Object System.Windows.Forms.Padding(3)

    $fixItTopTableLayoutPanel = CreateFixItTopTableLayoutPanel
    [void]$fixItTableLayoutPanel.Controls.Add($fixItTopTableLayoutPanel,0,0)

    $fixItMiddleTableLayoutPanel = CreateFixItMiddleTableLayoutPanel
    [void]$fixItTableLayoutPanel.Controls.Add($fixItMiddleTableLayoutPanel,0,1)

    #NOTE: ComboBox and ListBox Event Handlers must be created here because only global variable is $fixItTableLayoutPanel 
    #      and $fixItMiddleTableLayoutPanel needs to be created first
    #Add ComboBox Event Handlers
    [void]$fixItTableLayoutPanel.GetControlFromPosition(0,1).GetControlFromPosition(0,0).Add_SelectedIndexChanged({FixItComboBox_UpdateBoxContents `
        -selectedItem $fixItTableLayoutPanel.GetControlFromPosition(0,1).GetControlFromPosition(0,0).SelectedItem.ToString() `
        -folderListHT $fixItComboBoxFolderListHT `
        -listBox $fixItTableLayoutPanel.GetControlFromPosition(0,1).GetControlFromPosition(0,1) `
        -listBoxFilesHT $fixItListBoxFilesHT })

    #register ListBox Click Event
    [void]$fixItTableLayoutPanel.GetControlFromPosition(0,1).GetControlFromPosition(0,1).Add_Click({ListBox_Click `
        -middleLayoutPanel $fixItTableLayoutPanel.GetControlFromPosition(0,1) `
        -listBoxFilesHT $fixItListBoxFilesHT })

    #Add controls to TableLayoutPanel
    [void]$fixItTableLayoutPanel.Update()
    $fixItTableLayoutPanel.Enabled = $True
    #$fixItTableLayoutPanelControls = $fixItTableLayoutPanel.Controls
}

function CreateFixItTopTableLayoutPanel{
    $fixItTopTableLayoutPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $fixItTopTableLayoutPanel.Name = "fixItTopTableLayoutPanel"
    $fixItTopTableLayoutPanel.ColumnCount = 2
    $fixItTopTableLayoutPanel.RowCount = 1
    $fixItTopTableLayoutPanel.AutoScroll = $True
    $fixItTopTableLayoutPanel.AutoSize = $True
    $fixItTopTableLayoutPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    #$fixItTopTableLayoutPanel.BackColor = [System.Drawing.Color]::Black
    $fixItTopTableLayoutPanel.Margin = New-Object System.Windows.Forms.Padding(0,3,0,0)

    $fixItLabel = CreateFixItLabel
    [void]$fixItTopTableLayoutPanel.Controls.Add($fixItLabel,0,0)
    $fixItLabelLogo = CreateFixItLabelLogo
    [void]$fixItTopTableLayoutPanel.Controls.Add($fixItLabelLogo,1,0)

    $labelWidth = $fixItLabel.Size.Width
    $logoWidth = $fixItLabelLogo.Size.Width
    #$columnStyleAbsolute0 = New-Object System.Windows.Forms.ColumnStyle ( [System.Windows.Forms.SizeType]::Absolute,$labelWidth)
    #$columnStylePercent1 = New-Object System.Windows.Forms.ColumnStyle( [System.Windows.Forms.SizeType]::Percent,100 )
    #[void]$fixItTopTableLayoutPanel.ColumnStyles.Add( $columnStyleAbsolute0 )
    #[void]$fixItTopTableLayoutPanel.ColumnStyles.Add( $columnStylePercent1 )
    $columnStylePercent0 = New-Object System.Windows.Forms.ColumnStyle( [System.Windows.Forms.SizeType]::Percent,100 )
    $columnStyleAbsolute1 = New-Object System.Windows.Forms.ColumnStyle ( [System.Windows.Forms.SizeType]::Absolute,$logoWidth)
    [void]$fixItTopTableLayoutPanel.ColumnStyles.Add( $columnStylePercent0 )
    [void]$fixItTopTableLayoutPanel.ColumnStyles.Add( $columnStyleAbsolute1 )
    $fixItTopTableLayoutPanelColumnStyle = $fixItTopTableLayoutPanel.ColumnStyles

    return $fixItTopTableLayoutPanel
}

function CreateFixItLabel{
    $fixItLabel = New-Object System.Windows.Forms.Label
    $fixItLabel.Name = "fixItLabel"
    $fixItLabel.AutoSize = $true
    #$fixItLabel.Size = New-Object System.Drawing.Size 383,25 
    $fixItLabel.Font = New-Object System.Drawing.Font("Courier",14,[System.Drawing.FontStyle]::Bold)
    $fixItLabel.ForeColor = [System.Drawing.Color]::White
    $fixItLabel.BackColor = [System.Drawing.Color]::Black
    $fixItLabel.text = "Select a Category from the drop down list"
    $fixItLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $fixItLabel.Margin = New-Object System.Windows.Forms.Padding(3,0,0,0)
    $fixItLabel.Padding = New-Object System.Windows.Forms.Padding(9,0,0,0)
    $fixItLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
    return $fixItLabel
}

function CreateFixItLabelLogo{
    $fixItLabelLogo = New-Object System.Windows.Forms.Label
    $fixItLabelLogo.Name = "fixItLabelLogo"
    #$labelImage = [System.Drawing.Image]::FromFile("D:\logo2.png")
    $labelImage = [System.Drawing.Image]::FromFile($PSScriptRoot+"\logo(horizontal2).png")
    $fixItLabelLogo.Image = $labelImage
    $fixItLabelLogo.Size = New-Object System.Drawing.Size($labelImage.Width, $labelImage.Height)
    $fixItLabelLogo.Margin = New-Object System.Windows.Forms.Padding(0,0,3,0)
    $fixItLabelLogo.Dock = [System.Windows.Forms.DockStyle]::Right
    $fixItLabelLogo.ImageAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    return $fixItLabelLogo
}

function CreateFixItMiddleTableLayoutPanel{
    $fixItMiddleTableLayoutPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $fixItMiddleTableLayoutPanel.Name = "fixItMiddleTableLayoutPanel"
    $fixItMiddleTableLayoutPanel.ColumnCount = 1
    $fixItMiddleTableLayoutPanel.RowCount = 2
    $fixItMiddleTableLayoutPanel.AutoScroll = $True
    $fixItMiddleTableLayoutPanel.AutoSize = $True
    $fixItMiddleTableLayoutPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $fixItMiddleTableLayoutPanel.Margin = New-Object System.Windows.Forms.Padding(0,10,0,0)
    $fixItMiddleTableLayoutPanel.Padding = New-Object System.Windows.Forms.Padding(0,0,0,0)
    #$fixItMiddleTableLayoutPanel.BackColor = [System.Drawing.Color]::AliceBlue

    $fixItComboBox = CreateFixItComboBox -ht $fixItComboBoxFolderListHT
    [void]$fixItMiddleTableLayoutPanel.Controls.Add($fixItComboBox,0,0)

    $comboBoxHeight = $fixItComboBox.Height

    $fixItListBox = CreateFixItListBox
    [void]$fixItMiddleTableLayoutPanel.Controls.Add($fixItListBox,0,1)

    $rowStyleAbsolute0 = New-Object System.Windows.Forms.RowStyle( [System.Windows.Forms.SizeType]::Absolute,$comboBoxHeight )
    $rowStylePercent1 = New-Object System.Windows.Forms.RowStyle ( [System.Windows.Forms.SizeType]::Percent,100 )
    [void]$fixItMiddleTableLayoutPanel.RowStyles.Add( $rowStyleAbsolute0 )
    [void]$fixItMiddleTableLayoutPanel.RowStyles.Add( $rowStylePercent1 )

    return $fixItMiddleTableLayoutPanel
}

function CreateFixItComboBox{
    param( [System.Collections.Hashtable] $ht)

    $fixItComboBox = New-Object System.Windows.Forms.ComboBox
    $fixItComboBox.Name = "fixItComboBox"
    $fixItComboBox.Size = New-Object System.Drawing.Size 400,15
    $fixItComboBox.Font = New-Object System.Drawing.Font("Arial",14,[System.Drawing.FontStyle]::Regular)
    #$folderList1 = ListSubFolders("D:\Temp")
    $folderList1 = ListSubFolders($PSScriptRoot)
    FixItComboBox_AddSubfolders -folderList $folderList1 -comboBox $fixItComboBox -folderListHT $ht
    $fixItComboBox.SelectedIndex = 0
    $fixItComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    #$fixItComboBox.Margin = New-Object System.Windows.Forms.Padding(0,15,0,15)
    $fixItComboBox.Padding = New-Object System.Windows.Forms.Padding(0,0,0,0)
    $fixItComboBox.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom
    #$fixItComboBox.Dock = [System.Windows.Forms.DockStyle]::Fill
    return $fixItComboBox
}

function CreateFixItListBox{
    $fixItListBox = New-Object System.Windows.Forms.ListBox
    $fixItListBox.Name = "fixItListBox"
    $fixItListBox.Size = New-Object System.Drawing.Size 360,60
    $fixItListBox.Font = New-Object System.Drawing.Font("Arial",14,[System.Drawing.FontStyle]::Regular)
    $fixItListBox.SelectionMode = [System.Windows.Forms.SelectionMode]::One
    $fixItListBox.HorizontalScrollbar = $True
    $fixItListBox.Margin = New-Object System.Windows.Forms.Padding(2,15,2,0)
    $fixItListBox.Padding = New-Object System.Windows.Forms.Padding(5,0,0,0)
    $fixItListBox.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom
    return $fixItListBox
}


function InitializeScript(){
    if( $logEnable ){
        InitializeLog -logFolder $logFolder -logFile $logFile
    }
    InitializeWizardForm
    CreateFixItTableLayoutPanel
    [void]$wizardForm.Controls.Add($fixItTableLayoutPanel)
    [void]$wizardForm.ShowDialog()

}

# Initialize the Media Logging Subsystem object
. ".\Scripts\LoggingSubsystem.ps1"

$logFolder = "C:\Temp"                #location of log file
$logFile = "FixItWizard.log"          #name of log file
$logEnable = $true
$problemListFile = "ProblemList.txt"
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.IO | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
Add-Type -AssemblyName System.Text.RegularExpressions | Out-Null
$wizardForm = New-Object System.Windows.Forms.Form
$fixItTableLayoutPanel = New-Object System.Windows.Forms.TableLayoutPanel
$fixItComboBoxFolderListHT = New-Object System.Collections.Hashtable
$fixItListBoxFilesHT = New-Object System.Collections.Hashtable
$global:fixItListBoxSelectedItem = ""
InitializeScript


