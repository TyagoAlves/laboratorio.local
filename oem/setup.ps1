$logFile = "C:\OEM\setup.log"
$domain = "laboratorio.local"
$netbios = "LABORATORIO"
$safePass = "SenhaForte@2026"

function Log($msg) {
    "$(Get-Date -Format 'HH:mm:ss') $msg" | Out-File -Append $logFile
    Write-Host $msg
}

# ─── Disable Ctrl+Alt+Del and enable Auto-Logon ─────────────
Log "Configuring auto-logon and disabling Ctrl+Alt+Del..."
try {
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        /v DisableCAD /t REG_DWORD /d 1 /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        /v AutoAdminLogon /t REG_SZ /d "1" /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        /v DefaultUserName /t REG_SZ /d "Administrator" /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        /v DefaultPassword /t REG_SZ /d "$safePass" /f | Out-Null
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
        /v AutoLogonCount /t REG_DWORD /d 5 /f | Out-Null
    Log "Auto-logon configured."
}
catch { Log "Warning: could not set auto-logon: $_" }

# ─── PHASE 1: Install AD DS ─────────────────────────────────
$adService = Get-Service -Name NTDS -ErrorAction SilentlyContinue
if (-not $adService) {
    Log "=== PHASE 1: Installing AD DS ==="
    try {
        Log "Installing AD-Domain-Services feature..."
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
        Log "AD DS feature installed."

        Log "Creating forest $domain..."
        $securePass = ConvertTo-SecureString $safePass -AsPlainText -Force
        Install-ADDSForest -CreateDnsDelegation:$false `
            -DatabasePath "C:\Windows\NTDS" `
            -DomainMode "WinThreshold" `
            -DomainName $domain `
            -DomainNetbiosName $netbios `
            -ForestMode "WinThreshold" `
            -InstallDns:$true `
            -LogPath "C:\Windows\NTDS" `
            -SysvolPath "C:\Windows\SYSVOL" `
            -SafeModeAdministratorPassword $securePass `
            -Force:$true

        Log "Forest creation initiated. System will reboot."

        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        $cmd = "powershell -ExecutionPolicy Bypass -File C:\OEM\setup.ps1"
        Set-ItemProperty -Path $regPath -Name "OEMSetupPhase2" -Value $cmd
        Log "RunOnce registered for phase 2."
    }
    catch {
        Log "ERROR in phase 1: $_"
        exit 1
    }
    Log "=== PHASE 1 COMPLETE - REBOOTING ==="
    Restart-Computer -Force
    exit
}

# ─── PHASE 2: Post-reboot configuration ─────────────────────
Log "=== PHASE 2: Post-reboot configuration ==="
try {
    $domainObj = Get-ADDomain -Identity $domain -ErrorAction Stop
    Log "AD domain $domain is operational."

    # Create Organizational Units
    Log "Creating OUs..."
    $ous = @("Usuarios", "Grupos", "Servidores")
    foreach ($ou in $ous) {
        try {
            New-ADOrganizationalUnit -Name $ou -Path "DC=laboratorio,DC=local" -ErrorAction Stop
            Log "OU '$ou' created."
        }
        catch { Log "OU '$ou' may already exist: $_" }
    }

    # Create security groups
    Log "Creating security groups..."
    try {
        New-ADGroup -Name "G_Guacamole_Acesso" -GroupScope Global -GroupCategory Security `
            -Path "OU=Grupos,DC=laboratorio,DC=local" `
            -Description "Usuarios com acesso ao Apache Guacamole"
        Log "Group 'G_Guacamole_Acesso' created."
    }
    catch { Log "Group 'G_Guacamole_Acesso' error/skip: $_" }

    # Enable WinRM for remote management
    Log "Enabling WinRM..."
    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    New-NetFirewallRule -DisplayName "WinRM-HTTP" -Direction Inbound -Profile Any -Protocol TCP -LocalPort 5985 -Action Allow | Out-Null
    Log "WinRM enabled."

    # Create SMB share for internal network
    Log "Creating SMB share..."
    $sharePath = "C:\Compartilhado"
    New-Item -Path $sharePath -ItemType Directory -Force | Out-Null
    New-SmbShare -Name "Compartilhado" -Path $sharePath -FullAccess "$netbios\Domain Users" | Out-Null
    icacls $sharePath /grant "$netbios\Domain Users:(OI)(CI)(M)" /T | Out-Null
    Log "SMB share 'Compartilhado' created."

    # ─── Email: Windows SMTP Server (built-in) ────────────────
    Log "Installing Windows SMTP Server feature..."
    try {
        Install-WindowsFeature -Name SMTP-Server -IncludeManagementTools | Out-Null
        Log "Windows SMTP Server installed."

        # Configure relay for internal network
        $relayPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SMTP\Relay"
        if (-not (Test-Path $relayPath)) { New-Item -Path $relayPath -Force | Out-Null }
        Set-ItemProperty -Path $relayPath -Name "AllowRelay" -Value 1
        Set-ItemProperty -Path $relayPath -Name "RelayIpList" -Value "172.30.0.0/16"
        New-NetFirewallRule -DisplayName "SMTP-In" -Direction Inbound -Profile Any -Protocol TCP -LocalPort 25 -Action Allow | Out-Null
        Log "SMTP relay configured for 172.30.0.0/16."
    }
    catch { Log "Windows SMTP Server install error: $_" }

    # ─── Email: hMailServer (optional, local installer) ───────
    $hMailLocal = Get-ChildItem "C:\OEM\hMailServer-*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $hMailExe = $null
    $hMailInstalled = $false
    if ($hMailLocal) {
        $hMailExe = $hMailLocal.FullName
        Log "Found local hMailServer installer: $hMailExe"
    }
    else {
        Log "No local hMailServer installer found in C:\OEM\."
        Log "hMailServer download from internet is no longer available (site blocks automated access)."
        Log "Place hMailServer-5.7.0-B2730.exe manually in oem/ directory to enable."
    }
    if ($hMailExe -and (Test-Path $hMailExe)) {
        try {
            Log "Installing hMailServer..."
            Start-Process -Wait -FilePath $hMailExe -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"C:\Program Files\hMailServer`""
            Log "hMailServer installed successfully."

            # Stop Windows SMTP to avoid port 25 conflict
            Stop-Service -Name SMTPSvc -Force -ErrorAction SilentlyContinue
            Set-Service -Name SMTPSvc -StartupType Disabled -ErrorAction SilentlyContinue
            Log "Windows SMTP Server stopped (hMailServer will use port 25)."

            $adminExe = "C:\Program Files\hMailServer\Bin\hMailServer.Administrator.exe"
            if (Test-Path $adminExe) {
                Log "hMailServer administrator found at $adminExe"
            }
            $hMailInstalled = $true
        }
        catch { Log "hMailServer install error: $_" }
    }

    if (-not $hMailInstalled) {
        Log "Windows SMTP Server is active on port 25 (SMTP only)."
        Log "For POP3/IMAP support, add hMailServer installer to oem/ and recreate the container."
    }
    else {
        Log "hMailServer is active on port 25 (SMTP), 110 (POP3), 143 (IMAP)."
    }

    # Add Administrator to the Guacamole access group
    try {
        Add-ADGroupMember -Identity "CN=G_Guacamole_Acesso,OU=Grupos,DC=laboratorio,DC=local" `
            -Members "CN=Administrator,CN=Users,DC=laboratorio,DC=local"
        Log "Administrator added to G_Guacamole_Acesso."
    }
    catch { Log "Could not add Administrator to G_Guacamole_Acesso: $_" }

    Log "=== SETUP COMPLETE ==="
    Log "RDP access: Administrator / $safePass"
    Log "Domain: $domain"
    Log "You can now connect via RDP on port 3389"
    Log "Guacamole will be available after configuring connections"
}
catch {
    Log "ERROR in phase 2: $_"
}
