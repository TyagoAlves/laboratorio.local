$logFile = "C:\OEM\setup.log"
$domain = "laboratorio.local"
$netbios = "LABORATORIO"
$safePass = "SenhaForte@2026"

function Log($msg) {
    "$(Get-Date -Format 'HH:mm:ss') $msg" | Out-File -Append $logFile
    Write-Host $msg
}

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

    # Install hMailServer
    Log "Installing hMailServer..."
    $hMailLocal = Get-ChildItem "C:\OEM\hMailServer-*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $hMailExe = $null
    if ($hMailLocal) {
        $hMailExe = $hMailLocal.FullName
        Log "Found local installer: $hMailExe"
    }
    else {
        $hMailUrl = "https://download.hmailserver.com/hMailServer-5.7.0-B2730.exe"
        $hMailExe = "C:\Windows\Temp\hMailServer.exe"
        Log "Downloading from $hMailUrl ..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $hMailUrl -OutFile $hMailExe -UseBasicParsing
            Log "Download complete."
        }
        catch {
            Log "Download failed: $_"
        }
    }
    if ($hMailExe -and (Test-Path $hMailExe)) {
        try {
            Start-Process -Wait -FilePath $hMailExe -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=`"C:\Program Files\hMailServer`""
            Log "hMailServer installed successfully."

            # Configure hMailServer basic settings
            $adminExe = "C:\Program Files\hMailServer\Bin\hMailServer.Administrator.exe"
            if (Test-Path $adminExe) {
                Log "hMailServer administrator found at $adminExe"
            }
        }
        catch { Log "hMailServer install error: $_" }
    }
    else {
        Log "hMailServer installer not found. Skipping email setup."
    }

    Log "=== SETUP COMPLETE ==="
    Log "RDP access: Administrator / $safePass"
    Log "Domain: $domain"
    Log "You can now connect via RDP on port 3389"
    Log "Guacamole will be available after configuring connections"
}
catch {
    Log "ERROR in phase 2: $_"
}
