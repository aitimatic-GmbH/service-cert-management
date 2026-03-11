using namespace System.Net
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates

param($eventGridEvent, $TriggerMetadata)

$certificateName = $null
$keyVaultName    = $null

# Strukturiertes JSON-Logging für Application Insights
function Write-StructuredLog {
    param(
        [string]$Level,
        [string]$Message,
        [hashtable]$Properties = @{}
    )

    $logEntry = @{
        Timestamp = (Get-Date).ToUniversalTime().ToString("o")
        Level     = $Level
        Message   = $Message
        EventId   = $eventGridEvent.id
        EventType = $eventGridEvent.eventType
    }

    foreach ($key in $Properties.Keys) {
        $logEntry[$key] = $Properties[$key]
    }

    Write-Output ($logEntry | ConvertTo-Json -Compress)
}

# Event-Typ validieren und Zertifikat-Informationen extrahieren
# Gibt $null zurück wenn Event ignoriert werden soll, wirft bei fehlenden Feldern
function Resolve-EventData {
    if ($eventGridEvent.eventType -ne "Microsoft.KeyVault.CertificateNearExpiry") {
        Write-StructuredLog -Level "Warning" -Message "Unexpected event type received" -Properties @{
            ReceivedType = $eventGridEvent.eventType
        }
        return $null
    }

    $certName  = $eventGridEvent.data.ObjectName
    $vaultName = $eventGridEvent.data.VaultName

    if ([string]::IsNullOrEmpty($certName) -or [string]::IsNullOrEmpty($vaultName)) {
        throw "Missing required fields: ObjectName or VaultName"
    }

    return @{
        CertificateName = $certName
        KeyVaultName    = $vaultName
    }
}

# Mit Managed Identity authentifizieren
function Connect-ManagedIdentity {
    Write-StructuredLog -Level "Information" -Message "Authenticating with Managed Identity"
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-StructuredLog -Level "Information" -Message "Successfully authenticated"
}

# Vorhandenes Zertifikat in Key Vault prüfen und Ergebnis loggen
function Get-ExistingCertificate {
    param([string]$VaultName, [string]$CertName)

    $cert = Get-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -ErrorAction SilentlyContinue

    if ($null -eq $cert) {
        Write-StructuredLog -Level "Information" -Message "Certificate not found, will create it" -Properties @{
            CertificateName = $CertName
            KeyVaultName    = $VaultName
        }
    } else {
        Write-StructuredLog -Level "Information" -Message "Existing certificate found, will renew it" -Properties @{
            Version = $cert.Version
            Expires = $cert.Expires
        }
    }

    return $cert
}

# Self-signed Zertifikat generieren und als PFX in Temp-Datei exportieren
# Gibt @{ PfxPath; SecurePassword } zurück – Aufrufer ist für Cleanup verantwortlich
function New-SelfSignedPfx {
    param([string]$CertificateName, [int]$ValidityDays)

    Write-StructuredLog -Level "Information" -Message "Generating new self-signed certificate" -Properties @{
        ValidityDays = $ValidityDays
    }

    # Cross-platform .NET API – kein Windows-only New-SelfSignedCertificate
    $rsa     = [RSA]::Create(2048)
    $request = [CertificateRequest]::new(
        "CN=$CertificateName",
        $rsa,
        [HashAlgorithmName]::SHA256,
        [RSASignaturePadding]::Pkcs1
    )

    $request.CertificateExtensions.Add(
        [X509BasicConstraintsExtension]::new($false, $false, 0, $false)
    )
    $request.CertificateExtensions.Add(
        [X509KeyUsageExtension]::new(
            [X509KeyUsageFlags]::DigitalSignature -bor [X509KeyUsageFlags]::KeyEncipherment,
            $false
        )
    )

    $notBefore = [DateTimeOffset]::UtcNow
    $notAfter  = $notBefore.AddDays($ValidityDays)
    $cert      = $request.CreateSelfSigned($notBefore, $notAfter)

    Write-StructuredLog -Level "Information" -Message "Self-signed certificate generated" -Properties @{
        Thumbprint   = $cert.Thumbprint
        NotBefore    = $cert.NotBefore.ToUniversalTime().ToString("o")
        NotAfter     = $cert.NotAfter.ToUniversalTime().ToString("o")
        ValidityDays = $ValidityDays
    }

    # PFX in Temp-Datei exportieren (kein Windows-only Export-PfxCertificate)
    $pfxPasswordPlain = [Convert]::ToBase64String([RandomNumberGenerator]::GetBytes(32))
    $pfxBytes         = $cert.Export([X509ContentType]::Pfx, $pfxPasswordPlain)
    $pfxPath          = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).pfx")
    [System.IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

    return @{
        PfxPath        = $pfxPath
        SecurePassword = ConvertTo-SecureString -String $pfxPasswordPlain -Force -AsPlainText
    }
}

# PFX in Key Vault importieren und Ergebnis loggen
function Import-CertificateVersion {
    param(
        [string]$VaultName,
        [string]$CertName,
        [string]$PfxPath,
        [securestring]$Password,
        $ExistingCert
    )

    Write-StructuredLog -Level "Information" -Message "Importing certificate to Key Vault"

    $importedCert = Import-AzKeyVaultCertificate `
        -VaultName $VaultName `
        -Name $CertName `
        -FilePath $PfxPath `
        -Password $Password `
        -ErrorAction Stop

    $action = if ($null -ne $ExistingCert) { "renewed" } else { "created" }
    Write-StructuredLog -Level "Information" -Message "Certificate successfully $action" -Properties @{
        CertificateName = $importedCert.Name
        NewVersion      = $importedCert.Version
        OldVersion      = if ($null -ne $ExistingCert) { $ExistingCert.Version } else { 'N/A' }
        Thumbprint      = $importedCert.Thumbprint
        NotBefore       = $importedCert.Certificate.NotBefore.ToUniversalTime().ToString("o")
        NotAfter        = $importedCert.Certificate.NotAfter.ToUniversalTime().ToString("o")
    }
}

# Hauptlogik
try {
    Write-StructuredLog -Level "Information" -Message "Certificate renewal triggered" -Properties @{
        Subject   = $eventGridEvent.subject
        EventTime = $eventGridEvent.eventTime
    }

    $eventData = Resolve-EventData
    if ($null -eq $eventData) { return }

    $certificateName = $eventData.CertificateName
    $keyVaultName    = $eventData.KeyVaultName

    Write-StructuredLog -Level "Information" -Message "Certificate details extracted" -Properties @{
        CertificateName = $certificateName
        KeyVaultName    = $keyVaultName
    }

    Connect-ManagedIdentity

    $existingCert = Get-ExistingCertificate -VaultName $keyVaultName -CertName $certificateName
    $validityDays = if ($env:CERT_VALIDITY_DAYS) { [int]$env:CERT_VALIDITY_DAYS } else { 365 }

    $pfx = New-SelfSignedPfx -CertificateName $certificateName -ValidityDays $validityDays
    try {
        Import-CertificateVersion `
            -VaultName $keyVaultName `
            -CertName $certificateName `
            -PfxPath $pfx.PfxPath `
            -Password $pfx.SecurePassword `
            -ExistingCert $existingCert
    }
    finally {
        # Temp-Datei immer aufräumen
        if ($pfx.PfxPath -and (Test-Path $pfx.PfxPath)) {
            Remove-Item -Path $pfx.PfxPath -Force -ErrorAction SilentlyContinue
        }
    }

    $telemetry = @{
        name       = "CertRenewalSuccess"
        properties = @{
            CertificateName = $certificateName
            KeyVaultName    = $keyVaultName
            ValidityDays    = $validityDays
        }
    }
    Write-Output ($telemetry | ConvertTo-Json -Compress)
}
catch {
    Write-StructuredLog -Level "Error" -Message "Certificate renewal failed" -Properties @{
        ErrorMessage    = $_.Exception.Message
        ErrorType       = $_.Exception.GetType().FullName
        StackTrace      = $_.ScriptStackTrace
        CertificateName = if ($certificateName) { $certificateName } else { "unknown" }
        KeyVaultName    = if ($keyVaultName) { $keyVaultName } else { "unknown" }
    }

    $telemetry = @{
        name       = "CertRenewalFailed"
        properties = @{
            CertificateName = if ($certificateName) { $certificateName } else { "unknown" }
            KeyVaultName    = if ($keyVaultName) { $keyVaultName } else { "unknown" }
            ErrorMessage    = $_.Exception.Message
        }
    }
    Write-Output ($telemetry | ConvertTo-Json -Compress)

    throw
}
