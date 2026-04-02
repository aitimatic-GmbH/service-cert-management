# Azure Functions Profil-Skript (wird bei jedem Cold Start ausgeführt)

if ($env:MSI_SECRET) {
    Disable-AzContextAutosave -Scope Process | Out-Null
}

# Strict Mode für bessere Fehlerbehandlung
Set-StrictMode -Version Latest

# Az-Modul Verhalten konfigurieren
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'