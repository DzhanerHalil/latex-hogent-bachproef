# Script om Fira Code fonts te installeren
$fonts = @(
    ".\fonts\FiraCode\FiraCode-Regular.otf",
    ".\fonts\FiraCode\FiraCode-Bold.otf"
)

$FONTS = 0x14
$objShell = New-Object -ComObject Shell.Application
$objFolder = $objShell.Namespace($FONTS)

foreach ($font in $fonts) {
    $fontPath = (Resolve-Path $font).Path
    $fontName = Split-Path $fontPath -Leaf
    
    Write-Host "Installeren van $fontName..."
    
    # Kopieer naar lokale fonts folder (geen admin rechten nodig)
    $localFonts = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (-not (Test-Path $localFonts)) {
        New-Item -ItemType Directory -Path $localFonts -Force | Out-Null
    }
    
    Copy-Item -Path $fontPath -Destination $localFonts -Force
    
    # Registreer in registry voor huidige gebruiker
    $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    $fontFileName = Split-Path $fontPath -Leaf
    
    # Verkrijg font naam
    if ($fontFileName -match "Regular") {
        $regName = "Fira Code (TrueType)"
    } elseif ($fontFileName -match "Bold") {
        $regName = "Fira Code Bold (TrueType)"
    }
    
    New-ItemProperty -Path $regPath -Name $regName -Value "$localFonts\$fontFileName" -PropertyType String -Force | Out-Null
    
    Write-Host "✓ $fontName geïnstalleerd" -ForegroundColor Green
}

Write-Host "`nFonts succesvol geïnstalleerd! Start Visual Studio Code opnieuw op." -ForegroundColor Green
