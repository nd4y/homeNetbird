Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference='Stop'
$form=New-Object Windows.Forms.Form
$form.Text='homeNetbird - Aurora'; $form.ClientSize=New-Object Drawing.Size(540,410)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedDialog'; $form.MaximizeBox=$false
$form.BackColor=[Drawing.ColorTranslator]::FromHtml('#11151e'); $form.ForeColor=[Drawing.Color]::White
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$picture=New-Object Windows.Forms.PictureBox
$picture.Location=New-Object Drawing.Point(20,16);$picture.Size=New-Object Drawing.Size(500,160)
$picture.SizeMode='Zoom';$picture.Image=[Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'icons\home-preview.png'))
$form.Controls.Add($picture)
function Add-Label([string]$Text,[int]$Y){$l=New-Object Windows.Forms.Label;$l.Text=$Text;$l.Location=New-Object Drawing.Point(24,$Y);$l.Size=New-Object Drawing.Size(490,24);$form.Controls.Add($l)}
Add-Label 'Home management URL (cloud or your self-hosted server)' 180
$url=New-Object Windows.Forms.TextBox;$url.Text='https://api.netbird.io:443';$url.Location=New-Object Drawing.Point(24,207);$url.Size=New-Object Drawing.Size(490,26);$form.Controls.Add($url)
Add-Label 'Extra Home DNS domains, comma-separated (optional)' 241
$domains=New-Object Windows.Forms.TextBox;$domains.Location=New-Object Drawing.Point(24,269);$domains.Size=New-Object Drawing.Size(490,26);$form.Controls.Add($domains)
$status=New-Object Windows.Forms.Label;$status.Text='Installs a separate Home service, CLI and tray. Primary stays intact.';$status.Location=New-Object Drawing.Point(24,308);$status.Size=New-Object Drawing.Size(490,42);$form.Controls.Add($status)
$button=New-Object Windows.Forms.Button;$button.Text='Install & connect Home';$button.Location=New-Object Drawing.Point(24,355);$button.Size=New-Object Drawing.Size(490,38);$button.BackColor=[Drawing.ColorTranslator]::FromHtml('#4267db');$button.ForeColor=[Drawing.Color]::White;$button.FlatStyle='Flat';$form.Controls.Add($button)
$button.Add_Click({
    $button.Enabled=$false
    try {
        $uri=$null
        if(-not [Uri]::TryCreate($url.Text.Trim(),[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo){throw 'Enter an HTTPS management URL without embedded credentials.'}
        foreach($domain in @($domains.Text.Split(',')|ForEach-Object {$_.Trim()}|Where-Object {$_})) {
            if($domain -notmatch '^(?:\*\.)?(?:[a-zA-Z0-9_][a-zA-Z0-9_-]*\.)+[a-zA-Z0-9_][a-zA-Z0-9_-]*$'){throw 'Enter fully qualified DNS domains separated by commas.'}
        }
        if(-not (Test-Path (Join-Path $PSScriptRoot 'bin\netbird-home.exe'))){throw 'Use the release ZIP with the bundled daemon, or run Build.ps1 first.'}
        $status.Text='Installing the protected Windows service. Approve Windows UAC.'
        [Windows.Forms.Application]::DoEvents()
        $resultPath=Join-Path $env:TEMP ('homeNetbird-setup-'+[guid]::NewGuid()+'.json')
        $adminArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot 'Install-Service.ps1')+'"'),'-ResultPath',('"'+$resultPath+'"'))
        if($domains.Text.Trim()){$adminArgs+=@('-ExtraDomains',('"'+$domains.Text.Trim()+'"'))}
        $admin=Start-Process powershell.exe -ArgumentList $adminArgs -Verb RunAs -WindowStyle Hidden -PassThru
        while(-not $admin.HasExited){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 100}
        if(-not (Test-Path $resultPath)){throw 'Windows service setup did not return a result.'}
        $result=Get-Content $resultPath -Raw|ConvertFrom-Json
        Remove-Item -LiteralPath $resultPath
        if(-not $result.ok){throw $result.error}
        $status.Text='Service ready. Installing the Home indicator...';[Windows.Forms.Application]::DoEvents()
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-Tray.ps1') -NoLaunch
        if($LASTEXITCODE -ne 0){throw 'Home service installed, but tray installation failed.'}
        $destination=Join-Path $env:LOCALAPPDATA 'Programs\NetBirdHomeTray'
        $status.Text='Complete Home sign-in in the browser, then return to the tray.'
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $destination 'Connect-Home.ps1')+'"'),'-ManagementUrl',('"'+$uri.AbsoluteUri+'"')) -WindowStyle Normal
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+(Join-Path $destination 'Home-Tray.ps1')+'"')) -WindowStyle Hidden
        $button.Text='Installed - close this window';$button.Enabled=$false
    }catch{
        $status.Text=$_.Exception.Message;$button.Enabled=$true
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'homeNetbird',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null
    }
})
try{[Windows.Forms.Application]::Run($form)}finally{$picture.Image.Dispose();$form.Dispose()}
