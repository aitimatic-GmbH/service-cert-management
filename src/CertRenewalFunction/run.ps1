using namespace System.Net
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates

param($eventGridEvent, $TriggerMetadata)

# Variablen vorab initialisieren (für catch-Block Zugriff)
$certificateName = $null
$keyVaultName    = $null

# Hilfsfunktion: Strukturiertes JSON-Logging für Application Insights
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

# Hauptlogik
try {
    Write-StructuredLog -Level "Information" -Message "Certificate renewal triggered" -Properties @{
        Subject   = $eventGridEvent.subject
        EventTime = $eventGridEvent.eventTime
    }

    # Event-Typ validieren
    if ($eventGridEvent.eventType -ne "Microsoft.KeyVault.CertificateNearExpiry") {
        Write-StructuredLog -Level "Warning" -Message "Unexpected event type received" -Properties @{
            ReceivedType = $eventGridEvent.eventType
        }
        return
    }

    # Zertifikat-Informationen aus Event extrahieren
    $certificateName = $eventGridEvent.data.ObjectName
    $keyVaultName    = $eventGridEvent.data.VaultName

    if ([string]::IsNullOrEmpty($certificateName) -or [string]::IsNullOrEmpty($keyVaultName)) {
        throw "Missing required fields: ObjectName or VaultName"
    }

    Write-StructuredLog -Level "Information" -Message "Certificate details extracted" -Properties @{
        CertificateName = $certificateName
        KeyVaultName    = $keyVaultName
    }

    # Mit Managed Identity authentifizieren
    Write-StructuredLog -Level "Information" -Message "Authenticating with Managed Identity"
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-StructuredLog -Level "Information" -Message "Successfully authenticated"

    # Prüfen ob Zertifikat existiert (erstellen wenn neu, erneuern wenn vorhanden)
    $existingCert = Get-AzKeyVaultCertificate -VaultName $keyVaultName -Name $certificateName -ErrorAction SilentlyContinue

    if ($null -eq $existingCert) {
        Write-StructuredLog -Level "Information" -Message "Certificate not found, will create it" -Properties @{
            CertificateName = $certificateName
            KeyVaultName    = $keyVaultName
        }
    } else {
        Write-StructuredLog -Level "Information" -Message "Existing certificate found, will renew it" -Properties @{
            Version = $existingCert.Version
            Expires = $existingCert.Expires
        }
    }

    # Zertifikat-Gültigkeitsdauer aus App Setting (Bicep deployt CERT_VALIDITY_DAYS pro Umgebung)
    $validityDays = if ($env:CERT_VALIDITY_DAYS) { [int]$env:CERT_VALIDITY_DAYS } else { 365 }

    # Neues Self-signed Zertifikat generieren (cross-platform .NET API – kein Windows-only Cmdlet)
    Write-StructuredLog -Level "Information" -Message "Generating new self-signed certificate" -Properties @{
        ValidityDays = $validityDays
    }

    $pfxPath = $null
    try {
        $rsa     = [RSA]::Create(2048)
        $request = [CertificateRequest]::new(
            "CN=$certificateName",
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
        $notAfter  = $notBefore.AddDays($validityDays)
        $cert      = $request.CreateSelfSigned($notBefore, $notAfter)

        Write-StructuredLog -Level "Information" -Message "Self-signed certificate generated" -Properties @{
            Thumbprint   = $cert.Thumbprint
            NotBefore    = $cert.NotBefore.ToUniversalTime().ToString("o")
            NotAfter     = $cert.NotAfter.ToUniversalTime().ToString("o")
            ValidityDays = $validityDays
        }

        # PFX in Temp-Datei exportieren (kein Windows-only Export-PfxCertificate)
        $pfxPasswordPlain = [Convert]::ToBase64String([RandomNumberGenerator]::GetBytes(32))
        $pfxBytes         = $cert.Export([X509ContentType]::Pfx, $pfxPasswordPlain)
        $pfxPath          = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).pfx")
        [System.IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

        $securePassword = ConvertTo-SecureString -String $pfxPasswordPlain -Force -AsPlainText

        # In Key Vault importieren (neue Version des bestehenden Zertifikats)
        Write-StructuredLog -Level "Information" -Message "Importing certificate to Key Vault"

        $importedCert = Import-AzKeyVaultCertificate `
            -VaultName $keyVaultName `
            -Name $certificateName `
            -FilePath $pfxPath `
            -Password $securePassword `
            -ErrorAction Stop

        $action = if ($null -ne $existingCert) { "renewed" } else { "created" }
        Write-StructuredLog -Level "Information" -Message "Certificate successfully $action" -Properties @{
            CertificateName = $importedCert.Name
            NewVersion      = $importedCert.Version
            OldVersion      = if ($null -ne $existingCert) { $existingCert.Version } else { 'N/A' }
            Thumbprint      = $importedCert.Thumbprint
            NotBefore       = $importedCert.Certificate.NotBefore.ToUniversalTime().ToString("o")
            NotAfter        = $importedCert.Certificate.NotAfter.ToUniversalTime().ToString("o")
        }
    }
    finally {
        # Temp-Datei immer aufräumen
        if ($pfxPath -and (Test-Path $pfxPath)) {
            Remove-Item -Path $pfxPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Custom Event für Application Insights
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
