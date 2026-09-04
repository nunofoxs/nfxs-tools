
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -Name Dpi -Namespace NFX -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
[DllImport("shcore.dll")]
public static extern int SetProcessDpiAwareness(int value);
[DllImport("user32.dll")]
public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")]
public static extern int GetDpiForSystem();
"@
try {
	[void][NFX.Dpi]::SetProcessDpiAwarenessContext((New-Object IntPtr(-4)))
} catch {
	try {
		[void][NFX.Dpi]::SetProcessDpiAwareness(2)
	} catch {
		try { [void][NFX.Dpi]::SetProcessDPIAware() } catch {}
	}
}

$Script:ReferenceWidth  = 1920
$Script:ReferenceHeight = 1080
$Script:MinFontPt       = 7.5

function Get-UIScale {
	try {
		$Dpi = [NFX.Dpi]::GetDpiForSystem()
	} catch {
		$Dpi = 96
	}
	if (-not $Dpi -or $Dpi -le 0) { $Dpi = 96 }
	$DpiFactor = $Dpi / 96.0
	$Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
	$LogicalWidth  = $Bounds.Width  / $DpiFactor
	$LogicalHeight = $Bounds.Height / $DpiFactor
	$ScaleX = $LogicalWidth  / $Script:ReferenceWidth
	$ScaleY = $LogicalHeight / $Script:ReferenceHeight
	return [Math]::Min([Math]::Min($ScaleX, $ScaleY), 1.0)
}
$Script:UIScale = Get-UIScale

function Scale-Point($X, $Y) {
	return New-Object System.Drawing.Point([int][Math]::Round($X * $Script:UIScale), [int][Math]::Round($Y * $Script:UIScale))
}
function Scale-Size($Width, $Height) {
	$ScaledWidth = [Math]::Max([int][Math]::Round($Width * $Script:UIScale), 24)
	$ScaledHeight = [Math]::Max([int][Math]::Round($Height * $Script:UIScale), 14)
	return New-Object System.Drawing.Size($ScaledWidth, $ScaledHeight)
}
function Scale-SizeMinWidth($Width, $Height, $MinWidth) {
	$Base = Scale-Size $Width $Height
	$Base.Width = [Math]::Max($Base.Width, $MinWidth)
	return $Base
}
function Scale-SizeMinHeight($Width, $Height, $MinHeight) {
	$Base = Scale-Size $Width $Height
	$Base.Height = [Math]::Max($Base.Height, $MinHeight)
	return $Base
}
function Scale-Val($V) {
	return [int][Math]::Round($V * $Script:UIScale)
}
function Scale-Font($SizePt, $Style) {
	$ScaledSize = [Math]::Max(($SizePt * $Script:UIScale), $Script:MinFontPt)
	if ($Style) {
		return New-Object System.Drawing.Font("Segoe UI", $ScaledSize, $Style)
	}
	return New-Object System.Drawing.Font("Segoe UI", $ScaledSize)
}

$AppVersion = "1.0"
$VersionCheckUrl = ""

$NewsCheckUrl = "https://gist.githubusercontent.com/nunofoxs/a699aaf4de1150110d447091ea32e080/raw/nunofoxs.txt"

function Get-RemoteText($Url) {
	if (-not $Url) {
		return $null
	}
	try {
		$Response = Invoke-RestMethod -Uri $Url -TimeoutSec 3 -ErrorAction Stop
		$Value = ([string]$Response -split "`n" | Select-Object -First 1).Trim()
		if ($Value) {
			return $Value
		}
	} catch {
	}
	return $null
}

function Get-RemoteNews($Url) {
	if (-not $Url) {
		return $null
	}
	try {
		$Response = Invoke-RestMethod -Uri $Url -TimeoutSec 3 -ErrorAction Stop
		$Lines = ([string]$Response -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
		if ($Lines.Count -ge 1) {
			return [PSCustomObject]@{
				Text = $Lines[0]
				Link = if ($Lines.Count -ge 2) { $Lines[1] } else { $null }
			}
		}
	} catch {
	}
	return $null
}

function Get-RemoteImage($Url) {
	if (-not $Url) { return $null }
	try {
		$Response = Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
		$Ms = New-Object System.IO.MemoryStream(, $Response.Content)
		return [System.Drawing.Image]::FromStream($Ms)
	} catch {
	}
	return $null
}

$LatestVersion = Get-RemoteText $VersionCheckUrl
$UpdateAvailable = $LatestVersion -and ($LatestVersion -ne $AppVersion)
$News = Get-RemoteNews $NewsCheckUrl
$NewsBannerImage = if ($News -and $News.Text) { Get-RemoteImage $News.Text } else { $null }

$DiscordUrl = "https://discord.gg/6aD5DqUmEz"

$CleanerBatPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS Cleaner\NFXS Cleaner.bat"

$CleanerDownloadCheckUrl = "https://gist.githubusercontent.com/nunofoxs/1421ad4d4db3c2edeed128e6cf69c6b2/raw/download.txt"
$CleanerDownloadUrl = Get-RemoteText $CleanerDownloadCheckUrl
if (-not $CleanerDownloadUrl) {
	$CleanerDownloadUrl = $DiscordUrl
}

Add-Type -Name Dwm -Namespace NFX -MemberDefinition @"
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@

$Games = @{
	"FiveM" = @{
		ProcessName    = "FiveM*"
		InstallRoot    = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app"
		AppDataPath    = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\data"
		ExePath        = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\FiveM.com"
		DownloadUrl    = "https://fivem.net/"
		BaseGameName   = "GTA V"
		CitizenFXIniPath = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\CitizenFX.ini"
	}
	"RedM" = @{
		ProcessName    = "RedM*"
		InstallRoot    = Join-Path $env:LOCALAPPDATA "RedM\RedM.app"
		AppDataPath    = Join-Path $env:LOCALAPPDATA "RedM\RedM.app\data"
		ExePath        = Join-Path $env:LOCALAPPDATA "RedM\RedM.app\CitiCon.com"
		DownloadUrl    = "https://redm.net/"
		BaseGameName   = "RDR2"
		CitizenFXIniPath = Join-Path $env:LOCALAPPDATA "RedM\RedM.app\CitizenFX.ini"
	}
}

function Format-Bytes($Bytes) {
	if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
	if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
	if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
	return "< 1 KB"
}

$CacheFolders = @("cache","server-cache","server-cache-priv","game-storage")

function Get-CacheTotalBytes($GameName) {
	$Game = $Games[$GameName]
	$Total = 0
	foreach ($Folder in $CacheFolders) {
		$Path = Join-Path $Game.AppDataPath $Folder
		if (Test-Path $Path) {
			$Size = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
			if ($Size) {
				$Total += $Size
			}
		}
	}
	return $Total
}

$CacheLevelThresholds = @{
	"FiveM" = @{ Elevated = 5GB;  Large = 10GB; Excessive = 20GB }
	"RedM"  = @{ Elevated = 7GB;  Large = 12GB; Excessive = 20GB }
}

function Get-CacheLevel($GameName, $TotalBytes) {
	$S = $Strings[$CurrentLang]
	$Limits = $CacheLevelThresholds[$GameName]
	$SizeText = Format-Bytes $TotalBytes

	if ($TotalBytes -ge $Limits.Excessive) {
		return [PSCustomObject]@{ Title = $S.CacheLevelExcessiveTitle; Description = $S.CacheLevelExcessiveDescFormat -f $SizeText; ColorKey = "Error" }
	} elseif ($TotalBytes -ge $Limits.Large) {
		return [PSCustomObject]@{ Title = $S.CacheLevelLargeTitle; Description = $S.CacheLevelLargeDescFormat -f $SizeText; ColorKey = "Alert" }
	} elseif ($TotalBytes -ge $Limits.Elevated) {
		return [PSCustomObject]@{ Title = $S.CacheLevelElevatedTitle; Description = $S.CacheLevelElevatedDescFormat -f $SizeText; ColorKey = "Warning" }
	} else {
		return [PSCustomObject]@{ Title = $S.CacheLevelNormalTitle; Description = $S.CacheLevelNormalDescFormat -f $SizeText; ColorKey = "Success" }
	}
}

$DiskFreeThresholds = @{ Warning = 15GB; Alert = 5GB; Critical = 2GB }

function Get-DiskLevel($FreeBytes, $DriveName) {
	$S = $Strings[$CurrentLang]
	$FreeText = Format-Bytes $FreeBytes

	if ($FreeBytes -lt $DiskFreeThresholds.Critical) {
		return [PSCustomObject]@{ Title = $S.DiskLevelCriticalTitle; Description = $S.DiskLevelCriticalDescFormat -f $FreeText, $DriveName; ColorKey = "Error" }
	} elseif ($FreeBytes -lt $DiskFreeThresholds.Alert) {
		return [PSCustomObject]@{ Title = $S.DiskLevelAlertTitle; Description = $S.DiskLevelAlertDescFormat -f $FreeText, $DriveName; ColorKey = "Alert" }
	} elseif ($FreeBytes -lt $DiskFreeThresholds.Warning) {
		return [PSCustomObject]@{ Title = $S.DiskLevelWarningTitle; Description = $S.DiskLevelWarningDescFormat -f $FreeText, $DriveName; ColorKey = "Warning" }
	} else {
		return [PSCustomObject]@{ Title = $S.DiskLevelNormalTitle; Description = $S.DiskLevelNormalDescFormat -f $FreeText, $DriveName; ColorKey = "Success" }
	}
}

function Test-WindowsCompatible {
	$Version = [System.Environment]::OSVersion.Version
	$Is64Bit = [System.Environment]::Is64BitOperatingSystem
	return ($Version.Major -ge 10) -and $Is64Bit
}

$VCRedistRegistryPath = "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64"
$VCRedistDirectDownloadUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$VCRedistInfoUrl = "https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist"

function Test-VCRedistInstalled {
	if (Test-Path $VCRedistRegistryPath) {
		$Value = (Get-ItemProperty -Path $VCRedistRegistryPath -ErrorAction SilentlyContinue).Installed
		return ($Value -eq 1)
	}
	return $false
}

function Get-UIDataStatus($GameName) {
	$Game = $Games[$GameName]
	$Path = Join-Path $Game.AppDataPath "nui-storage"
	if (-not (Test-Path $Path)) {
		return "NotFound"
	}
	$HasContent = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
	if ($HasContent.Count -eq 0) {
		return "Empty"
	}
	return "Found"
}

function Get-BaseGamePathFromIni($GameName) {
	$Game = $Games[$GameName]
	if (-not (Test-Path $Game.CitizenFXIniPath)) {
		return $null
	}
	$Line = Get-Content $Game.CitizenFXIniPath -ErrorAction SilentlyContinue | Where-Object { $_ -match '^IVPath=(.+)$' } | Select-Object -First 1
	if ($Line -and $Line -match '^IVPath=(.+)$') {
		return $Matches[1].Trim()
	}
	return $null
}

function Get-BaseGameStatus($GameName) {
	$Path = Get-BaseGamePathFromIni $GameName
	if (-not $Path) {
		return "Unknown"
	}
	if (Test-Path $Path) {
		return "Found"
	}
	return "NotFound"
}

$ModProxyFileNames = @("dxgi.dll","d3d11.dll","d3d9.dll","dinput8.dll","winmm.dll","ReShade.ini")

function Get-DetectedMods($GameName) {
	$Game = $Games[$GameName]
	if (-not (Test-Path $Game.InstallRoot)) {
		return @()
	}
	$Found = @()
	foreach ($FileName in $ModProxyFileNames) {
		$Path = Join-Path $Game.InstallRoot $FileName
		if (Test-Path $Path) {
			$Found += $FileName
		}
	}
	return $Found
}

$SettingsDir  = Join-Path $env:APPDATA "NFXS-GameCheck"
$SettingsFile = Join-Path $SettingsDir "theme.cfg"

function Get-SavedTheme {
	if (Test-Path $SettingsFile) {
		$Saved = (Get-Content $SettingsFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -eq "Light" -or $Saved -eq "Dark") {
			return $Saved
		}
	}
	return "Dark"
}

function Save-Theme($Name) {
	try {
		if (-not (Test-Path $SettingsDir)) {
			New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
		}
		Set-Content -Path $SettingsFile -Value $Name -ErrorAction SilentlyContinue
	} catch {
	}
}

$LangFile = Join-Path $SettingsDir "lang.cfg"

function Get-SavedLang {
	if (Test-Path $LangFile) {
		$Saved = (Get-Content $LangFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -in @("pt","en","es","de","fr")) {
			return $Saved
		}
	}
	return "pt"
}

function Save-Lang($Code) {
	try {
		if (-not (Test-Path $SettingsDir)) {
			New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
		}
		Set-Content -Path $LangFile -Value $Code -ErrorAction SilentlyContinue
	} catch {
	}
}

$LastGameFile = Join-Path $SettingsDir "lastgame.cfg"

function Get-SavedGame {
	if (Test-Path $LastGameFile) {
		$Saved = (Get-Content $LastGameFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -eq "FiveM" -or $Saved -eq "RedM") {
			return $Saved
		}
	}
	return "FiveM"
}

function Save-Game($Name) {
	try {
		if (-not (Test-Path $SettingsDir)) {
			New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
		}
		Set-Content -Path $LastGameFile -Value $Name -ErrorAction SilentlyContinue
	} catch {
	}
}

$SharedAccentFile = Join-Path $env:APPDATA "NFXS\accent.cfg"
$AccentPresets = @(
	[PSCustomObject]@{ Key = "Verde";   Light = [System.Drawing.Color]::FromArgb(78,159,85);   Dark = [System.Drawing.Color]::FromArgb(114,204,114) }
	[PSCustomObject]@{ Key = "Ciano";   Light = [System.Drawing.Color]::FromArgb(20,148,155);  Dark = [System.Drawing.Color]::FromArgb(100,220,225) }
	[PSCustomObject]@{ Key = "Azul";    Light = [System.Drawing.Color]::FromArgb(42,120,200);  Dark = [System.Drawing.Color]::FromArgb(120,175,235) }
	[PSCustomObject]@{ Key = "Indigo";  Light = [System.Drawing.Color]::FromArgb(88,90,196);   Dark = [System.Drawing.Color]::FromArgb(150,155,235) }
	[PSCustomObject]@{ Key = "Roxo";    Light = [System.Drawing.Color]::FromArgb(130,80,190);  Dark = [System.Drawing.Color]::FromArgb(190,145,235) }
	[PSCustomObject]@{ Key = "Rosa";    Light = [System.Drawing.Color]::FromArgb(199,74,140);  Dark = [System.Drawing.Color]::FromArgb(240,150,195) }
	[PSCustomObject]@{ Key = "Laranja"; Light = [System.Drawing.Color]::FromArgb(196,106,32);  Dark = [System.Drawing.Color]::FromArgb(240,165,90) }
)

function Get-SharedAccentColor($ThemeName) {
	$Key = "Verde"
	if (Test-Path $SharedAccentFile) {
		$Saved = (Get-Content $SharedAccentFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -in @($AccentPresets | ForEach-Object { $_.Key })) {
			$Key = $Saved
		}
	}
	$Preset = $AccentPresets | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
	if ($ThemeName -eq "Dark") { return $Preset.Dark }
	return $Preset.Light
}

$SharedThemeFile = Join-Path $env:APPDATA "NFXS\theme.cfg"
function Get-SharedTheme {
	if (Test-Path $SharedThemeFile) {
		$Saved = (Get-Content $SharedThemeFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -eq "Light" -or $Saved -eq "Dark") { return $Saved }
	}
	return "Dark"
}
$SharedLangFile = Join-Path $env:APPDATA "NFXS\lang.cfg"
function Get-SharedLang {
	if (Test-Path $SharedLangFile) {
		$Saved = (Get-Content $SharedLangFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -in @("pt","en","es","de","fr")) { return $Saved }
	}
	return "pt"
}

$Strings = @{
	"pt" = @{
		Description               = "Verifique se o FiveM ou RedM está funcionando corretamente."
		GameLabel                 = "Jogo"
		InstallLabel               = "Instalação"
		InstallDetected            = "Detectada"
		InstallNotDetected         = "Não detectada"
		BaseGameDetected           = "Detectado"
		BaseGameNotDetected        = "Não detectado"
		BaseGameUnknown            = "Não disponível"
		ModsLabel                  = "Mods gráficos"
		ModsNone                   = "Nenhum detectado"
		ModsDetectedFormat         = "Detectado: {0}"
		PathPlaceholder            = "Instalação não encontrada."
		DownloadLinkFormat         = "Baixe aqui o {0} (site oficial)."
		ProcessLabel               = "Jogo aberto"
		ProcessRunning             = "Em execução agora"
		ProcessClosed              = "Não está em execução"
		OSLabel                    = "Sistema"
		OSCompatible               = "Compatível"
		OSNotCompatible            = "Não compatível"
		RuntimeLabel               = "Runtime"
		RuntimeInstalled           = "Instalado."
		RuntimeNotFoundText        = "Não encontrado."
		RuntimeCta                 = "Baixe aqui o Visual C++ Redistributable."
		VCRedistDialogTitle        = "Visual C++ Redistributable"
		VCRedistDialogMessage      = "O FiveM/RedM precisa desse componente da Microsoft pra funcionar direito. Como prefere continuar?"
		VCRedistDialogDownload     = "Baixar automaticamente"
		VCRedistDialogOpenSite     = "Ver no site oficial da Microsoft"
		UIDataLabel                = "Dados de interface"
		UIDataFound                = "Encontrados"
		UIDataEmpty                = "Vazios"
		UIDataNotFound             = "Ainda não criados"
		CacheNotApplicableTitle    = "Cache não disponível"
		CacheNotApplicableDescFormat  = "Não foi possível medir o cache porque o {0} não foi detectado nesta máquina."
		CacheLevelNormalTitle      = "Cache normal"
		CacheLevelElevatedTitle    = "Cache elevado"
		CacheLevelLargeTitle       = "Cache muito grande"
		CacheLevelExcessiveTitle   = "Cache excessivo"
		CacheLevelNormalDescFormat    = "Seu cache está usando {0}. Está dentro do esperado."
		CacheLevelElevatedDescFormat  = "Seu cache está usando {0}. Considere limpar."
		CacheLevelLargeDescFormat     = "Seu cache está usando {0}. Recomendamos limpar em breve."
		CacheLevelExcessiveDescFormat = "Seu cache está usando {0}. Recomendamos limpar agora."
		CacheCtaDownload           = "Baixe aqui o NFXS Cleaner."
		CacheCtaOpen               = "Abra aqui o NFXS Cleaner."
		DiskLevelNormalTitle      = "Espaço em disco OK"
		DiskLevelWarningTitle     = "Espaço em disco baixo"
		DiskLevelAlertTitle       = "Espaço em disco muito baixo"
		DiskLevelCriticalTitle    = "Espaço em disco crítico"
		DiskLevelNormalDescFormat    = "{0} livres no disco {1}. Está dentro do esperado."
		DiskLevelWarningDescFormat   = "{0} livres no disco {1}. Fique de olho, pode faltar espaço em breve."
		DiskLevelAlertDescFormat     = "{0} livres no disco {1}. Considere liberar espaço."
		DiskLevelCriticalDescFormat  = "{0} livres no disco {1}. Isso pode impedir o jogo de atualizar ou baixar arquivos."
		ResultTitleOk              = "Tudo certo"
		ResultTitleAttention       = "Pontos de atenção"
		ResultTitleNotInstalled    = "Não detectado"
		ResultOkFormat             = "Seu {0} parece estar funcionando normalmente."
		ResultAttentionFormat      = "Seu {0} está funcionando, mas encontramos pontos de atenção acima."
		ResultNotInstalledFormat   = "Não detectamos o {0} instalado nesta máquina."
		RefreshButton              = "Verificar novamente"
		CloseButton                = "Fechar"
		ThemeButtonLight           = "Modo Claro"
		ThemeButtonDark            = "Modo Escuro"
		UpdateAvailableFormat      = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk                   = "Você está com a versão mais recente."
		NewsHeader                 = "Obrigado por usar nosso app, acesse:"
		FreeLabel                  = "Produto gratuito disponibilizado por NunoFoxs"
	}
	"en" = @{
		Description               = "Check if your FiveM or RedM is working correctly."
		GameLabel                 = "Game"
		InstallLabel               = "Installation"
		InstallDetected            = "Detected"
		InstallNotDetected         = "Not detected"
		BaseGameDetected           = "Detected"
		BaseGameNotDetected        = "Not detected"
		BaseGameUnknown            = "Not available"
		ModsLabel                  = "Graphics mods"
		ModsNone                   = "None detected"
		ModsDetectedFormat         = "Detected: {0}"
		PathPlaceholder            = "Installation not found."
		DownloadLinkFormat         = "Download {0} here (official site)."
		ProcessLabel               = "Game open"
		ProcessRunning             = "Currently running"
		ProcessClosed              = "Not running"
		OSLabel                    = "System"
		OSCompatible               = "Compatible"
		OSNotCompatible            = "Not compatible"
		RuntimeLabel               = "Runtime"
		RuntimeInstalled           = "Installed."
		RuntimeNotFoundText        = "Not found."
		RuntimeCta                 = "Download the Visual C++ Redistributable here."
		VCRedistDialogTitle        = "Visual C++ Redistributable"
		VCRedistDialogMessage      = "FiveM/RedM needs this Microsoft component to work properly. How would you like to continue?"
		VCRedistDialogDownload     = "Download automatically"
		VCRedistDialogOpenSite     = "View on the official Microsoft site"
		UIDataLabel                = "Interface data"
		UIDataFound                = "Found"
		UIDataEmpty                = "Empty"
		UIDataNotFound             = "Not created yet"
		CacheNotApplicableTitle    = "Cache not available"
		CacheNotApplicableDescFormat  = "We couldn't measure the cache because {0} wasn't detected on this machine."
		CacheLevelNormalTitle      = "Normal cache"
		CacheLevelElevatedTitle    = "Elevated cache"
		CacheLevelLargeTitle       = "Very large cache"
		CacheLevelExcessiveTitle   = "Excessive cache"
		CacheLevelNormalDescFormat    = "Your cache is using {0}. This is within the expected range."
		CacheLevelElevatedDescFormat  = "Your cache is using {0}. Consider cleaning it."
		CacheLevelLargeDescFormat     = "Your cache is using {0}. We recommend cleaning it soon."
		CacheLevelExcessiveDescFormat = "Your cache is using {0}. We recommend cleaning it now."
		CacheCtaDownload           = "Download NFXS Cleaner here."
		CacheCtaOpen               = "Open NFXS Cleaner here."
		DiskLevelNormalTitle      = "Disk space OK"
		DiskLevelWarningTitle     = "Low disk space"
		DiskLevelAlertTitle       = "Very low disk space"
		DiskLevelCriticalTitle    = "Critical disk space"
		DiskLevelNormalDescFormat    = "{0} free on drive {1}. This is within the expected range."
		DiskLevelWarningDescFormat   = "{0} free on drive {1}. Keep an eye on it, you might run low soon."
		DiskLevelAlertDescFormat     = "{0} free on drive {1}. Consider freeing up some space."
		DiskLevelCriticalDescFormat  = "{0} free on drive {1}. This may prevent the game from updating or downloading files."
		ResultTitleOk              = "All good"
		ResultTitleAttention       = "Points of attention"
		ResultTitleNotInstalled    = "Not detected"
		ResultOkFormat             = "Your {0} appears to be working normally."
		ResultAttentionFormat      = "Your {0} is working, but we found points of attention above."
		ResultNotInstalledFormat   = "We didn't detect {0} installed on this machine."
		RefreshButton              = "Check again"
		CloseButton                = "Close"
		ThemeButtonLight           = "Light Mode"
		ThemeButtonDark            = "Dark Mode"
		UpdateAvailableFormat      = "New version available (v{0}) - click here"
		UpdateOk                   = "You have the latest version."
		NewsHeader                 = "Thanks for using our app, check out:"
		FreeLabel                  = "Free product provided by NunoFoxs"
	}
	"es" = @{
		Description               = "Verifica si tu FiveM o RedM está funcionando correctamente."
		GameLabel                 = "Juego"
		InstallLabel               = "Instalación"
		InstallDetected            = "Detectada"
		InstallNotDetected         = "No detectada"
		BaseGameDetected           = "Detectado"
		BaseGameNotDetected        = "No detectado"
		BaseGameUnknown            = "No disponible"
		ModsLabel                  = "Mods gráficos"
		ModsNone                   = "Ninguno detectado"
		ModsDetectedFormat         = "Detectado: {0}"
		PathPlaceholder            = "Instalación no encontrada."
		DownloadLinkFormat         = "Descarga aquí el {0} (sitio oficial)."
		ProcessLabel               = "Juego abierto"
		ProcessRunning             = "En ejecución ahora"
		ProcessClosed              = "No está en ejecución"
		OSLabel                    = "Sistema"
		OSCompatible               = "Compatible"
		OSNotCompatible            = "No compatible"
		RuntimeLabel               = "Runtime"
		RuntimeInstalled           = "Instalado."
		RuntimeNotFoundText        = "No encontrado."
		RuntimeCta                 = "Descarga aquí el Visual C++ Redistributable."
		VCRedistDialogTitle        = "Visual C++ Redistributable"
		VCRedistDialogMessage      = "FiveM/RedM necesita este componente de Microsoft para funcionar bien. ¿Cómo prefieres continuar?"
		VCRedistDialogDownload     = "Descargar automáticamente"
		VCRedistDialogOpenSite     = "Ver en el sitio oficial de Microsoft"
		UIDataLabel                = "Datos de interfaz"
		UIDataFound                = "Encontrados"
		UIDataEmpty                = "Vacíos"
		UIDataNotFound             = "Aún no creados"
		CacheNotApplicableTitle    = "Caché no disponible"
		CacheNotApplicableDescFormat  = "No pudimos medir el caché porque no detectamos {0} en esta máquina."
		CacheLevelNormalTitle      = "Caché normal"
		CacheLevelElevatedTitle    = "Caché elevado"
		CacheLevelLargeTitle       = "Caché muy grande"
		CacheLevelExcessiveTitle   = "Caché excesivo"
		CacheLevelNormalDescFormat    = "Tu caché está usando {0}. Está dentro de lo esperado."
		CacheLevelElevatedDescFormat  = "Tu caché está usando {0}. Considera limpiarlo."
		CacheLevelLargeDescFormat     = "Tu caché está usando {0}. Te recomendamos limpiarlo pronto."
		CacheLevelExcessiveDescFormat = "Tu caché está usando {0}. Te recomendamos limpiarlo ahora."
		CacheCtaDownload           = "Descarga aquí el NFXS Cleaner."
		CacheCtaOpen               = "Abre aquí el NFXS Cleaner."
		DiskLevelNormalTitle      = "Espacio en disco OK"
		DiskLevelWarningTitle     = "Espacio en disco bajo"
		DiskLevelAlertTitle       = "Espacio en disco muy bajo"
		DiskLevelCriticalTitle    = "Espacio en disco crítico"
		DiskLevelNormalDescFormat    = "{0} libres en el disco {1}. Está dentro de lo esperado."
		DiskLevelWarningDescFormat   = "{0} libres en el disco {1}. Préstale atención, podría faltar espacio pronto."
		DiskLevelAlertDescFormat     = "{0} libres en el disco {1}. Considera liberar espacio."
		DiskLevelCriticalDescFormat  = "{0} libres en el disco {1}. Esto puede impedir que el juego se actualice o descargue archivos."
		ResultTitleOk              = "Todo en orden"
		ResultTitleAttention       = "Puntos de atención"
		ResultTitleNotInstalled    = "No detectado"
		ResultOkFormat             = "Tu {0} parece estar funcionando normalmente."
		ResultAttentionFormat      = "Tu {0} está funcionando, pero encontramos puntos de atención arriba."
		ResultNotInstalledFormat   = "No detectamos {0} instalado en esta máquina."
		RefreshButton              = "Verificar de nuevo"
		CloseButton                = "Cerrar"
		ThemeButtonLight           = "Modo Claro"
		ThemeButtonDark            = "Modo Oscuro"
		UpdateAvailableFormat      = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk                   = "Tienes la versión más reciente."
		NewsHeader                 = "Gracias por usar nuestra app, visita:"
		FreeLabel                  = "Producto gratuito ofrecido por NunoFoxs"
	}
	"de" = @{
		Description               = "Prüfe, ob dein FiveM oder RedM richtig funktioniert."
		GameLabel                 = "Spiel"
		InstallLabel               = "Installation"
		InstallDetected            = "Erkannt"
		InstallNotDetected         = "Nicht erkannt"
		BaseGameDetected           = "Erkannt"
		BaseGameNotDetected        = "Nicht erkannt"
		BaseGameUnknown            = "Nicht verfügbar"
		ModsLabel                  = "Grafik-Mods"
		ModsNone                   = "Keine erkannt"
		ModsDetectedFormat         = "Erkannt: {0}"
		PathPlaceholder            = "Installation nicht gefunden."
		DownloadLinkFormat         = "Hier herunterladen: {0} (offizielle Seite)."
		ProcessLabel               = "Spiel geöffnet"
		ProcessRunning             = "Wird gerade ausgeführt"
		ProcessClosed              = "Wird nicht ausgeführt"
		OSLabel                    = "System"
		OSCompatible               = "Kompatibel"
		OSNotCompatible            = "Nicht kompatibel"
		RuntimeLabel               = "Runtime"
		RuntimeInstalled           = "Installiert."
		RuntimeNotFoundText        = "Nicht gefunden."
		RuntimeCta                 = "Hier das Visual C++ Redistributable herunterladen."
		VCRedistDialogTitle        = "Visual C++ Redistributable"
		VCRedistDialogMessage      = "FiveM/RedM benötigt diese Microsoft-Komponente, um richtig zu funktionieren. Wie möchtest du fortfahren?"
		VCRedistDialogDownload     = "Automatisch herunterladen"
		VCRedistDialogOpenSite     = "Auf der offiziellen Microsoft-Seite ansehen"
		UIDataLabel                = "Oberflächendaten"
		UIDataFound                = "Gefunden"
		UIDataEmpty                = "Leer"
		UIDataNotFound             = "Noch nicht erstellt"
		CacheNotApplicableTitle    = "Cache nicht verfügbar"
		CacheNotApplicableDescFormat  = "Der Cache konnte nicht gemessen werden, da {0} auf diesem Computer nicht erkannt wurde."
		CacheLevelNormalTitle      = "Normaler Cache"
		CacheLevelElevatedTitle    = "Erhöhter Cache"
		CacheLevelLargeTitle       = "Sehr großer Cache"
		CacheLevelExcessiveTitle   = "Übermäßiger Cache"
		CacheLevelNormalDescFormat    = "Dein Cache belegt {0}. Das liegt im erwarteten Bereich."
		CacheLevelElevatedDescFormat  = "Dein Cache belegt {0}. Erwäge, ihn zu leeren."
		CacheLevelLargeDescFormat     = "Dein Cache belegt {0}. Wir empfehlen, ihn bald zu leeren."
		CacheLevelExcessiveDescFormat = "Dein Cache belegt {0}. Wir empfehlen, ihn jetzt zu leeren."
		CacheCtaDownload           = "Hier herunterladen: NFXS Cleaner."
		CacheCtaOpen               = "Hier öffnen: NFXS Cleaner."
		DiskLevelNormalTitle      = "Speicherplatz OK"
		DiskLevelWarningTitle     = "Wenig Speicherplatz"
		DiskLevelAlertTitle       = "Sehr wenig Speicherplatz"
		DiskLevelCriticalTitle    = "Kritischer Speicherplatz"
		DiskLevelNormalDescFormat    = "{0} frei auf Laufwerk {1}. Das liegt im erwarteten Bereich."
		DiskLevelWarningDescFormat   = "{0} frei auf Laufwerk {1}. Behalte es im Auge, es könnte bald knapp werden."
		DiskLevelAlertDescFormat     = "{0} frei auf Laufwerk {1}. Erwäge, Speicherplatz freizugeben."
		DiskLevelCriticalDescFormat  = "{0} frei auf Laufwerk {1}. Das kann verhindern, dass das Spiel aktualisiert oder Dateien herunterlädt."
		ResultTitleOk              = "Alles in Ordnung"
		ResultTitleAttention       = "Punkte, die Aufmerksamkeit brauchen"
		ResultTitleNotInstalled    = "Nicht erkannt"
		ResultOkFormat             = "Dein {0} scheint normal zu funktionieren."
		ResultAttentionFormat      = "Dein {0} funktioniert, aber wir haben oben Punkte gefunden, die Aufmerksamkeit brauchen."
		ResultNotInstalledFormat   = "Wir haben {0} auf diesem Computer nicht erkannt."
		RefreshButton              = "Erneut prüfen"
		CloseButton                = "Schließen"
		ThemeButtonLight           = "Heller Modus"
		ThemeButtonDark            = "Dunkler Modus"
		UpdateAvailableFormat      = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk                   = "Du hast die neueste Version."
		NewsHeader                 = "Danke, dass du unsere App nutzt, schau vorbei:"
		FreeLabel                  = "Kostenloses Produkt bereitgestellt von NunoFoxs"
	}
	"fr" = @{
		Description               = "Vérifiez si votre FiveM ou RedM fonctionne correctement."
		GameLabel                 = "Jeu"
		InstallLabel               = "Installation"
		InstallDetected            = "Détectée"
		InstallNotDetected         = "Non détectée"
		BaseGameDetected           = "Détecté"
		BaseGameNotDetected        = "Non détecté"
		BaseGameUnknown            = "Non disponible"
		ModsLabel                  = "Mods graphiques"
		ModsNone                   = "Aucun détecté"
		ModsDetectedFormat         = "Détecté : {0}"
		PathPlaceholder            = "Installation introuvable."
		DownloadLinkFormat         = "Télécharger {0} ici (site officiel)."
		ProcessLabel               = "Jeu ouvert"
		ProcessRunning             = "En cours d'exécution"
		ProcessClosed              = "N'est pas en cours d'exécution"
		OSLabel                    = "Système"
		OSCompatible               = "Compatible"
		OSNotCompatible            = "Non compatible"
		RuntimeLabel               = "Runtime"
		RuntimeInstalled           = "Installé."
		RuntimeNotFoundText        = "Introuvable."
		RuntimeCta                 = "Télécharger le Visual C++ Redistributable ici."
		VCRedistDialogTitle        = "Visual C++ Redistributable"
		VCRedistDialogMessage      = "FiveM/RedM a besoin de ce composant Microsoft pour bien fonctionner. Comment voulez-vous continuer ?"
		VCRedistDialogDownload     = "Télécharger automatiquement"
		VCRedistDialogOpenSite     = "Voir sur le site officiel de Microsoft"
		UIDataLabel                = "Données d'interface"
		UIDataFound                = "Trouvées"
		UIDataEmpty                = "Vides"
		UIDataNotFound             = "Pas encore créées"
		CacheNotApplicableTitle    = "Cache non disponible"
		CacheNotApplicableDescFormat  = "Nous n'avons pas pu mesurer le cache car {0} n'a pas été détecté sur cette machine."
		CacheLevelNormalTitle      = "Cache normal"
		CacheLevelElevatedTitle    = "Cache élevé"
		CacheLevelLargeTitle       = "Cache très volumineux"
		CacheLevelExcessiveTitle   = "Cache excessif"
		CacheLevelNormalDescFormat    = "Votre cache utilise {0}. C'est dans la plage attendue."
		CacheLevelElevatedDescFormat  = "Votre cache utilise {0}. Envisagez de le nettoyer."
		CacheLevelLargeDescFormat     = "Votre cache utilise {0}. Nous recommandons de le nettoyer bientôt."
		CacheLevelExcessiveDescFormat = "Votre cache utilise {0}. Nous recommandons de le nettoyer maintenant."
		CacheCtaDownload           = "Télécharger NFXS Cleaner ici."
		CacheCtaOpen               = "Ouvrir NFXS Cleaner ici."
		DiskLevelNormalTitle      = "Espace disque OK"
		DiskLevelWarningTitle     = "Espace disque faible"
		DiskLevelAlertTitle       = "Espace disque très faible"
		DiskLevelCriticalTitle    = "Espace disque critique"
		DiskLevelNormalDescFormat    = "{0} libres sur le disque {1}. C'est dans la plage attendue."
		DiskLevelWarningDescFormat   = "{0} libres sur le disque {1}. Surveillez-le, l'espace pourrait bientôt manquer."
		DiskLevelAlertDescFormat     = "{0} libres sur le disque {1}. Envisagez de libérer de l'espace."
		DiskLevelCriticalDescFormat  = "{0} libres sur le disque {1}. Cela peut empêcher le jeu de se mettre à jour ou de télécharger des fichiers."
		ResultTitleOk              = "Tout va bien"
		ResultTitleAttention       = "Points d'attention"
		ResultTitleNotInstalled    = "Non détecté"
		ResultOkFormat             = "Votre {0} semble fonctionner normalement."
		ResultAttentionFormat      = "Votre {0} fonctionne, mais nous avons trouvé des points d'attention ci-dessus."
		ResultNotInstalledFormat   = "Nous n'avons pas détecté {0} installé sur cette machine."
		RefreshButton              = "Vérifier à nouveau"
		CloseButton                = "Fermer"
		ThemeButtonLight           = "Mode Clair"
		ThemeButtonDark            = "Mode Sombre"
		UpdateAvailableFormat      = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk                   = "Vous avez la dernière version."
		NewsHeader                 = "Merci d'utiliser notre application, découvrez :"
		FreeLabel                  = "Produit gratuit proposé par NunoFoxs"
	}
}

$Themes = @{
	"Light" = @{
		FormBg       = [System.Drawing.Color]::FromArgb(244,245,243)
		HeaderBg     = [System.Drawing.Color]::FromArgb(11,13,12)
		HeaderTitle  = [System.Drawing.Color]::FromArgb(242,242,242)
		HeaderSub    = [System.Drawing.Color]::FromArgb(150,155,151)
		Text         = [System.Drawing.Color]::FromArgb(23,26,24)
		TextSoft     = [System.Drawing.Color]::FromArgb(98,104,98)
		FieldBg      = [System.Drawing.Color]::FromArgb(255,255,255)
		FieldFg      = [System.Drawing.Color]::FromArgb(23,26,24)
		Accent       = [System.Drawing.Color]::FromArgb(78,159,85)
		AccentTxt    = [System.Drawing.Color]::FromArgb(255,255,255)
		Btn2Bg       = [System.Drawing.Color]::FromArgb(250,251,250)
		Btn2Fg       = [System.Drawing.Color]::FromArgb(23,26,24)
		Btn2Border   = [System.Drawing.Color]::FromArgb(221,226,222)
		Success      = [System.Drawing.Color]::FromArgb(57,118,63)
		Warning      = [System.Drawing.Color]::FromArgb(184,150,10)
		Alert        = [System.Drawing.Color]::FromArgb(194,101,15)
		Error        = [System.Drawing.Color]::FromArgb(198,40,40)
		Credit       = [System.Drawing.Color]::FromArgb(168,172,168)
		ToggleBg     = [System.Drawing.Color]::FromArgb(78,159,85)
		ToggleFg     = [System.Drawing.Color]::FromArgb(255,255,255)
		RedMPrimary  = [System.Drawing.Color]::FromArgb(154,73,55)
		RedMDark     = [System.Drawing.Color]::FromArgb(122,56,43)
		Leather      = [System.Drawing.Color]::FromArgb(138,90,64)
		Gold         = [System.Drawing.Color]::FromArgb(167,123,62)
		DarkTitlebar = $true
	}
	"Dark" = @{
		FormBg       = [System.Drawing.Color]::FromArgb(11,13,12)
		HeaderBg     = [System.Drawing.Color]::FromArgb(18,22,20)
		HeaderTitle  = [System.Drawing.Color]::FromArgb(242,242,242)
		HeaderSub    = [System.Drawing.Color]::FromArgb(150,155,151)
		Text         = [System.Drawing.Color]::FromArgb(242,242,242)
		TextSoft     = [System.Drawing.Color]::FromArgb(150,155,151)
		FieldBg      = [System.Drawing.Color]::FromArgb(25,29,26)
		FieldFg      = [System.Drawing.Color]::FromArgb(242,242,242)
		Accent       = [System.Drawing.Color]::FromArgb(114,204,114)
		AccentTxt    = [System.Drawing.Color]::FromArgb(11,13,12)
		Btn2Bg       = [System.Drawing.Color]::FromArgb(25,29,26)
		Btn2Fg       = [System.Drawing.Color]::FromArgb(198,201,198)
		Btn2Border   = [System.Drawing.Color]::FromArgb(41,46,42)
		Success      = [System.Drawing.Color]::FromArgb(139,221,139)
		Warning      = [System.Drawing.Color]::FromArgb(232,212,77)
		Alert        = [System.Drawing.Color]::FromArgb(232,150,60)
		Error        = [System.Drawing.Color]::FromArgb(239,83,80)
		Credit       = [System.Drawing.Color]::FromArgb(90,95,91)
		ToggleBg     = [System.Drawing.Color]::FromArgb(114,204,114)
		ToggleFg     = [System.Drawing.Color]::FromArgb(11,13,12)
		RedMPrimary  = [System.Drawing.Color]::FromArgb(164,71,50)
		RedMLight    = [System.Drawing.Color]::FromArgb(200,106,82)
		RedMDark     = [System.Drawing.Color]::FromArgb(102,48,37)
		Leather      = [System.Drawing.Color]::FromArgb(139,90,60)
		Gold         = [System.Drawing.Color]::FromArgb(200,155,91)
		DarkTitlebar = $true
	}
}

$CurrentTheme = "Light"
$CurrentLang  = Get-SharedLang
$Script:CurrentGame = Get-SavedGame

$DefaultFont = Scale-Font 9

$IconPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS.ico"

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "NFXS - GameCheck"
$Form.AutoScaleMode = "Dpi"
$Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96,96)
$Form.Size = Scale-Size 400 880
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false
$Form.MinimizeBox = $true
$Form.Font = $DefaultFont
if (Test-Path $IconPath) { $Form.Icon = New-Object System.Drawing.Icon($IconPath) }

$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Dock = "Top"
$HeaderPanel.Height = Scale-Val 80
$Form.Controls.Add($HeaderPanel)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "NFXS | GAME CHECK"
$TitleLabel.Font = Scale-Font 12 ([System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = Scale-Point 18 13
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.Text = "FiveM & RedM Diagnostics v$AppVersion"
$SubtitleLabel.UseMnemonic = $false
$SubtitleLabel.Font = $DefaultFont
$SubtitleLabel.Location = Scale-Point 19 37
$SubtitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($SubtitleLabel)

$ContentPanel = New-Object System.Windows.Forms.Panel
$ContentPanel.Dock = "Fill"
$ContentPanel.AutoScroll = $true
$Form.Controls.Add($ContentPanel)
$ContentPanel.BringToFront()

$Y = Scale-Val 10
$DescriptionLabel = New-Object System.Windows.Forms.Label
$DescriptionLabel.Text = $Strings[$CurrentLang].Description
$DescriptionLabel.Font = Scale-Font 8
$DescriptionLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$DescriptionLabel.Size = Scale-SizeMinHeight 344 32 30
$ContentPanel.Controls.Add($DescriptionLabel)
$Y += (Scale-Val 36) + [Math]::Max(0, $DescriptionLabel.Size.Height - (Scale-Val 32))

$GameLabel = New-Object System.Windows.Forms.Label
$GameLabel.Text = $Strings[$CurrentLang].GameLabel
$GameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$GameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$GameLabel.AutoSize = $true
$ContentPanel.Controls.Add($GameLabel)
$Y += (Scale-Val 20)

$GameCombo = New-Object System.Windows.Forms.ComboBox
$GameCombo.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$GameCombo.Size = Scale-Size 344 26
$GameCombo.Font = $DefaultFont
$GameCombo.DropDownStyle = "DropDownList"
$GameCombo.Items.AddRange(@("FiveM","RedM"))
$GameCombo.SelectedItem = $Script:CurrentGame
$ContentPanel.Controls.Add($GameCombo)
$Y += (Scale-Val 38)

$InstallNameLabel = New-Object System.Windows.Forms.Label
$InstallNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$InstallNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$InstallNameLabel.Size = Scale-Size 120 18
$ContentPanel.Controls.Add($InstallNameLabel)

$InstallValueLabel = New-Object System.Windows.Forms.Label
$InstallValueLabel.Font = $DefaultFont
$InstallValueLabel.Location = New-Object System.Drawing.Point(($InstallNameLabel.Location.X + $InstallNameLabel.Size.Width + (Scale-Val 2)), $InstallNameLabel.Location.Y)
$InstallValueLabel.Size = New-Object System.Drawing.Size(([Math]::Max(((Scale-Val 362) - $InstallValueLabel.Location.X), 60)), (Scale-Val 18))
$InstallValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($InstallValueLabel)
$Y += (Scale-Val 22)

$PathBox = New-Object System.Windows.Forms.TextBox
$PathBox.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$PathBox.Size = Scale-Size 344 24
$PathBox.Font = Scale-Font 8
$PathBox.ReadOnly = $true
$ContentPanel.Controls.Add($PathBox)

$InstallLinkLabel = New-Object System.Windows.Forms.LinkLabel
$InstallLinkLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$InstallLinkLabel.Size = Scale-Size 344 24
$InstallLinkLabel.Font = Scale-Font 8
$InstallLinkLabel.TextAlign = "MiddleLeft"
$InstallLinkLabel.LinkBehavior = [System.Windows.Forms.LinkBehavior]::AlwaysUnderline
$InstallLinkLabel.Visible = $false
$InstallLinkLabel.Add_LinkClicked({ Start-Process $Script:DownloadUrl })
$ContentPanel.Controls.Add($InstallLinkLabel)
$Y += (Scale-Val 28)

$BaseGameNameLabel = New-Object System.Windows.Forms.Label
$BaseGameNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$BaseGameNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$BaseGameNameLabel.Size = Scale-Size 120 18
$ContentPanel.Controls.Add($BaseGameNameLabel)

$BaseGameValueLabel = New-Object System.Windows.Forms.Label
$BaseGameValueLabel.Font = $DefaultFont
$BaseGameValueLabel.Location = New-Object System.Drawing.Point(($BaseGameNameLabel.Location.X + $BaseGameNameLabel.Size.Width + (Scale-Val 2)), $BaseGameNameLabel.Location.Y)
$BaseGameValueLabel.Size = New-Object System.Drawing.Size(([Math]::Max(((Scale-Val 362) - $BaseGameValueLabel.Location.X), 60)), (Scale-Val 18))
$BaseGameValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($BaseGameValueLabel)
$Y += (Scale-Val 22)

$ModsNameLabel = New-Object System.Windows.Forms.Label
$ModsNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ModsNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$ModsNameLabel.Size = Scale-SizeMinWidth 120 18 100
$ContentPanel.Controls.Add($ModsNameLabel)

$ModsValueLabel = New-Object System.Windows.Forms.Label
$ModsValueLabel.Font = $DefaultFont
$ModsValueLabel.Location = New-Object System.Drawing.Point(($ModsNameLabel.Location.X + $ModsNameLabel.Size.Width + (Scale-Val 2)), $ModsNameLabel.Location.Y)
$ModsValueLabel.Size = New-Object System.Drawing.Size(([Math]::Max(((Scale-Val 362) - $ModsValueLabel.Location.X), 60)), (Scale-Val 18))
$ModsValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($ModsValueLabel)
$Y += (Scale-Val 26)

$ProcessNameLabel = New-Object System.Windows.Forms.Label
$ProcessNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ProcessNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$ProcessNameLabel.Size = Scale-Size 120 18
$ContentPanel.Controls.Add($ProcessNameLabel)

$ProcessValueLabel = New-Object System.Windows.Forms.Label
$ProcessValueLabel.Font = $DefaultFont
$ProcessValueLabel.Location = New-Object System.Drawing.Point(($ProcessNameLabel.Location.X + $ProcessNameLabel.Size.Width + (Scale-Val 2)), $ProcessNameLabel.Location.Y)
$ProcessValueLabel.Size = New-Object System.Drawing.Size(([Math]::Max(((Scale-Val 362) - $ProcessValueLabel.Location.X), 60)), (Scale-Val 18))
$ProcessValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($ProcessValueLabel)
$Y += (Scale-Val 24)

$OSNameLabel = New-Object System.Windows.Forms.Label
$OSNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$OSNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$OSNameLabel.Size = Scale-Size 120 18
$ContentPanel.Controls.Add($OSNameLabel)

$OSValueLabel = New-Object System.Windows.Forms.Label
$OSValueLabel.Font = $DefaultFont
$OSValueLabel.Location = New-Object System.Drawing.Point(($OSNameLabel.Location.X + $OSNameLabel.Size.Width + (Scale-Val 2)), $OSNameLabel.Location.Y)
$OSValueLabel.Size = New-Object System.Drawing.Size(([Math]::Max(((Scale-Val 362) - $OSValueLabel.Location.X), 60)), (Scale-Val 18))
$OSValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($OSValueLabel)
$Y += (Scale-Val 22)

$RuntimeDescLabel = New-Object System.Windows.Forms.LinkLabel
$RuntimeDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$RuntimeDescLabel.Size = Scale-SizeMinHeight 344 32 30
$RuntimeDescLabel.Font = Scale-Font 8
$RuntimeDescLabel.LinkBehavior = [System.Windows.Forms.LinkBehavior]::AlwaysUnderline
$RuntimeDescLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(0,0)
$RuntimeDescLabel.Add_LinkClicked({ Show-VCRedistChoice })
$ContentPanel.Controls.Add($RuntimeDescLabel)
$Y += (Scale-Val 38) + [Math]::Max(0, $RuntimeDescLabel.Size.Height - (Scale-Val 32))

$UIDataNameLabel = New-Object System.Windows.Forms.Label
$UIDataNameLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$UIDataNameLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$UIDataNameLabel.Size = Scale-SizeMinWidth 120 18 100
$ContentPanel.Controls.Add($UIDataNameLabel)

$UIDataValueLabel = New-Object System.Windows.Forms.Label
$UIDataValueLabel.Font = $DefaultFont
$UIDataValueLabel.Location = New-Object System.Drawing.Point(($UIDataNameLabel.Location.X + $UIDataNameLabel.Size.Width + (Scale-Val 2)), $UIDataNameLabel.Location.Y)
$UIDataValueLabel.Size = New-Object System.Drawing.Size(([Math]::Max(((Scale-Val 362) - $UIDataValueLabel.Location.X), 60)), (Scale-Val 18))
$UIDataValueLabel.TextAlign = "MiddleRight"
$ContentPanel.Controls.Add($UIDataValueLabel)
$Y += (Scale-Val 28)

$CacheTitleLabel = New-Object System.Windows.Forms.Label
$CacheTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$CacheTitleLabel.Size = Scale-Size 344 16
$CacheTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($CacheTitleLabel)
$Y += (Scale-Val 16)

$CacheDescLabel = New-Object System.Windows.Forms.LinkLabel
$CacheDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$CacheDescLabel.Size = Scale-SizeMinHeight 344 32 30
$CacheDescLabel.Font = Scale-Font 8
$CacheDescLabel.LinkBehavior = [System.Windows.Forms.LinkBehavior]::AlwaysUnderline
$CacheDescLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(0,0)
$CacheDescLabel.Add_LinkClicked({
	if (Test-Path $CleanerBatPath) {
		Start-Process $CleanerBatPath
	} else {
		Start-Process $CleanerDownloadUrl
	}
})
$ContentPanel.Controls.Add($CacheDescLabel)
$Y += (Scale-Val 40) + [Math]::Max(0, $CacheDescLabel.Size.Height - (Scale-Val 32))

$DiskTitleLabel = New-Object System.Windows.Forms.Label
$DiskTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$DiskTitleLabel.Size = Scale-Size 344 16
$DiskTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($DiskTitleLabel)
$Y += (Scale-Val 16)

$DiskDescLabel = New-Object System.Windows.Forms.Label
$DiskDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$DiskDescLabel.Size = Scale-SizeMinHeight 344 32 30
$DiskDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($DiskDescLabel)
$Y += (Scale-Val 44) + [Math]::Max(0, $DiskDescLabel.Size.Height - (Scale-Val 32))

$ResultTitleLabel = New-Object System.Windows.Forms.Label
$ResultTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$ResultTitleLabel.Size = Scale-Size 344 18
$ResultTitleLabel.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($ResultTitleLabel)
$Y += (Scale-Val 20)

$ResultDescLabel = New-Object System.Windows.Forms.Label
$ResultDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$ResultDescLabel.Size = Scale-SizeMinHeight 344 40 36
$ResultDescLabel.Font = $DefaultFont
$ContentPanel.Controls.Add($ResultDescLabel)
$Y += (Scale-Val 48) + [Math]::Max(0, $ResultDescLabel.Size.Height - (Scale-Val 40))

$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($Y + (Scale-Val 10)))

$BotoesPanel = New-Object System.Windows.Forms.Panel
$BotoesPanel.Dock = "Bottom"
$BotoesPanel.Height = Scale-Val 72

$RefreshButton = New-Object System.Windows.Forms.Button
$RefreshButton.Font = $DefaultFont
$RefreshButton.Location = Scale-Point 18 0
$RefreshButton.Size = Scale-Size 164 34
$RefreshButton.FlatStyle = "Flat"
$RefreshButton.FlatAppearance.BorderSize = 0
$RefreshButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$BotoesPanel.Controls.Add($RefreshButton)

$CloseButton = New-Object System.Windows.Forms.Button
$CloseButton.Font = $DefaultFont
$CloseButton.Location = Scale-Point 198 0
$CloseButton.Size = Scale-Size 164 34
$CloseButton.FlatStyle = "Flat"
$CloseButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$CloseButton.Add_Click({ $Form.Close() })
$BotoesPanel.Controls.Add($CloseButton)

$UpdateLabel = New-Object System.Windows.Forms.Label
$UpdateLabel.Location = Scale-Point 18 46
$UpdateLabel.Size = Scale-Size 344 18
if ($UpdateAvailable) {
	$UpdateLabel.Text = $Strings[$CurrentLang].UpdateAvailableFormat -f $LatestVersion
	$UpdateLabel.Font = Scale-Font 8 ([System.Drawing.FontStyle]::Underline)
	$UpdateLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
	$UpdateLabel.Add_Click({ Start-Process $DiscordUrl })
} else {
	$UpdateLabel.Text = $Strings[$CurrentLang].UpdateOk
	$UpdateLabel.Font = Scale-Font 8
	$UpdateLabel.Cursor = [System.Windows.Forms.Cursors]::Default
}
$BotoesPanel.Controls.Add($UpdateLabel)

$BannerPanel = New-Object System.Windows.Forms.Panel
$BannerPanel.Dock = "Bottom"
$BannerPanel.Height = Scale-Val 102

$NewsHeaderLabel = New-Object System.Windows.Forms.Label
$NewsHeaderLabel.Location = Scale-Point 18 0
$NewsHeaderLabel.Size = Scale-Size 344 16
$NewsHeaderLabel.TextAlign = "MiddleCenter"
$NewsHeaderLabel.Font = Scale-Font 7.5
if ($News) {
	$NewsHeaderLabel.Text = $Strings[$CurrentLang].NewsHeader
} else {
	$NewsHeaderLabel.Text = ""
}
$BannerPanel.Controls.Add($NewsHeaderLabel)

$NewsLabel = New-Object System.Windows.Forms.Label
$NewsLabel.Location = Scale-Point 18 18
$NewsLabel.Size = Scale-Size 344 18
$NewsLabel.TextAlign = "MiddleCenter"
$NewsLabel.Font = Scale-Font 8 ([System.Drawing.FontStyle]::Underline)
if ($News) {
	$NewsLabel.Text = $News.Text
	$NewsLabel.Cursor = [System.Windows.Forms.Cursors]::Hand
	$NewsLink = if ($News.Link -match '^https?://') { $News.Link } else { $DiscordUrl }
	$NewsLabel.Add_Click({ Start-Process $NewsLink }.GetNewClosure())
} else {
	$NewsLabel.Text = ""
}
$BannerPanel.Controls.Add($NewsLabel)

$NewsBanner = New-Object System.Windows.Forms.PictureBox
$NewsBanner.Size = Scale-Size 344 72
$NewsBanner.Location = Scale-Point 18 0
$NewsBanner.SizeMode = "Zoom"
$NewsBanner.Cursor = "Hand"
$NewsBanner.Visible = $false
$BannerPanel.Controls.Add($NewsBanner)
$NewsBanner.Add_Click({
	$Target = if ($News -and $News.Link) { $News.Link } else { $DiscordUrl }
	try { Start-Process $Target } catch {}
})
if ($NewsBannerImage) {
	$NewsHeaderLabel.Visible = $false
	$NewsLabel.Visible = $false
	$NewsBanner.Visible = $true
	$NewsBanner.Image = $NewsBannerImage
}

$DiscordPanel = New-Object System.Windows.Forms.Panel
$DiscordPanel.Dock = "Bottom"
$DiscordPanel.Height = Scale-Val 74

$DiscordButton = New-Object System.Windows.Forms.Button
$DiscordButton.Text = "Discord"
$DiscordButton.Font = Scale-Font 7.5 ([System.Drawing.FontStyle]::Bold)
$DiscordButton.Size = Scale-Size 72 24
$DiscordX = [int](($Form.ClientSize.Width - $DiscordButton.Width) / 2)
$DiscordButton.Location = New-Object System.Drawing.Point($DiscordX, 0)
$DiscordButton.BackColor = [System.Drawing.Color]::FromArgb(88,101,242)
$DiscordButton.ForeColor = [System.Drawing.Color]::White
$DiscordButton.FlatStyle = "Flat"
$DiscordButton.FlatAppearance.BorderSize = 0
$DiscordButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$DiscordButton.Add_Click({ Start-Process $DiscordUrl })
$DiscordPanel.Controls.Add($DiscordButton)

$FreeLabel = New-Object System.Windows.Forms.Label
$FreeLabel.Font = Scale-Font 7.5
$FreeLabel.TextAlign = "MiddleCenter"
$FreeLabel.Location = Scale-Point 18 38
$FreeLabel.Size = Scale-Size 344 16
$DiscordPanel.Controls.Add($FreeLabel)

$Form.Controls.Add($BotoesPanel)
$Form.Controls.Add($BannerPanel)
$Form.Controls.Add($DiscordPanel)

function Set-AutoEllipsisRecursive($Container) {
	foreach ($Ctrl in $Container.Controls) {
		if ($Ctrl -is [System.Windows.Forms.Label]) {
			$Ctrl.AutoEllipsis = $true
		}
		if ($Ctrl.Controls.Count -gt 0) {
			Set-AutoEllipsisRecursive $Ctrl
		}
	}
}
Set-AutoEllipsisRecursive $Form

function Get-GameAccentColor($GameName, $ThemeName) {
	$T = $Themes[$ThemeName]
	if ($GameName -eq "RedM") {
		if ($ThemeName -eq "Dark") { return $T.RedMLight }
		return $T.RedMPrimary
	}
	return $T.Accent
}

function Show-VCRedistChoice {
	$S = $Strings[$CurrentLang]
	$T = $Themes[$CurrentTheme]
	$GameAccent = $Script:GameAccent

	$Dlg = New-Object System.Windows.Forms.Form
	$Dlg.Text = $S.VCRedistDialogTitle
	$Dlg.Size = Scale-Size 320 224
	$Dlg.StartPosition = "CenterParent"
	$Dlg.FormBorderStyle = "FixedDialog"
	$Dlg.MaximizeBox = $false
	$Dlg.MinimizeBox = $false
	$Dlg.Font = $DefaultFont
	$Dlg.BackColor = $T.FormBg

	$MsgLabel = New-Object System.Windows.Forms.Label
	$MsgLabel.Text = $S.VCRedistDialogMessage
	$MsgLabel.ForeColor = $T.Text
	$MsgLabel.Location = Scale-Point 18 18
	$MsgLabel.Size = Scale-Size 268 70
	$Dlg.Controls.Add($MsgLabel)

	$DownloadBtn = New-Object System.Windows.Forms.Button
	$DownloadBtn.Text = $S.VCRedistDialogDownload
	$DownloadBtn.Font = $DefaultFont
	$DownloadBtn.Location = Scale-Point 18 96
	$DownloadBtn.Size = Scale-Size 268 34
	$DownloadBtn.FlatStyle = "Flat"
	$DownloadBtn.FlatAppearance.BorderSize = 0
	$DownloadBtn.BackColor = $GameAccent
	$DownloadBtn.ForeColor = $T.AccentTxt
	$DownloadBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
	$DownloadBtn.Add_Click({ Start-Process $VCRedistDirectDownloadUrl; $Dlg.Close() }.GetNewClosure())
	$Dlg.Controls.Add($DownloadBtn)

	$SiteBtn = New-Object System.Windows.Forms.Button
	$SiteBtn.Text = $S.VCRedistDialogOpenSite
	$SiteBtn.Font = $DefaultFont
	$SiteBtn.Location = Scale-Point 18 138
	$SiteBtn.Size = Scale-Size 268 34
	$SiteBtn.FlatStyle = "Flat"
	$SiteBtn.BackColor = $T.Btn2Bg
	$SiteBtn.ForeColor = $T.Btn2Fg
	$SiteBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$SiteBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
	$SiteBtn.Add_Click({ Start-Process $VCRedistInfoUrl; $Dlg.Close() }.GetNewClosure())
	$Dlg.Controls.Add($SiteBtn)

	$null = $Dlg.Handle
	$DarkModeValue = if ($T.DarkTitlebar) { 1 } else { 0 }
	[void][NFX.Dwm]::DwmSetWindowAttribute($Dlg.Handle,20,[ref]$DarkModeValue,4)

	$Dlg.ShowDialog($Form) | Out-Null
}

function Run-Checks {
	$S = $Strings[$CurrentLang]
	$T = $Themes[$CurrentTheme]
	$GameName = $Script:CurrentGame
	$Game = $Games[$GameName]

	$Installed = Test-Path $Game.ExePath
	if ($Installed) {
		$InstallValueLabel.Text = $S.InstallDetected
		$InstallValueLabel.ForeColor = $T.Success
		$PathBox.Text = $Game.InstallRoot
		$PathBox.Visible = $true
		$InstallLinkLabel.Visible = $false
	} else {
		$InstallValueLabel.Text = $S.InstallNotDetected
		$InstallValueLabel.ForeColor = $T.Error
		$Script:DownloadUrl = $Game.DownloadUrl

		$InstallBaseText = $S.PathPlaceholder
		$InstallCtaText = $S.DownloadLinkFormat -f $GameName
		$InstallLinkLabel.ForeColor = $T.TextSoft
		$InstallLinkLabel.LinkColor = $Script:GameAccent
		$InstallLinkLabel.ActiveLinkColor = $Script:GameAccent
		$InstallLinkLabel.VisitedLinkColor = $Script:GameAccent
		$InstallLinkLabel.Text = "$InstallBaseText $InstallCtaText"
		$InstallLinkLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(($InstallBaseText.Length + 1), $InstallCtaText.Length)

		$PathBox.Visible = $false
		$InstallLinkLabel.Visible = $true
	}

	$BaseGameNameLabel.Text = $Game.BaseGameName
	$BaseGameStatus = Get-BaseGameStatus $GameName
	switch ($BaseGameStatus) {
		"Found"    { $BaseGameValueLabel.Text = $S.BaseGameDetected;    $BaseGameValueLabel.ForeColor = $T.Success }
		"NotFound" { $BaseGameValueLabel.Text = $S.BaseGameNotDetected; $BaseGameValueLabel.ForeColor = $T.Error }
		"Unknown"  { $BaseGameValueLabel.Text = $S.BaseGameUnknown;     $BaseGameValueLabel.ForeColor = $T.TextSoft }
	}

	$DetectedMods = @(Get-DetectedMods $GameName)
	if ($DetectedMods.Count -gt 0) {
		$ModsValueLabel.Text = $S.ModsDetectedFormat -f ($DetectedMods -join ", ")
	} else {
		$ModsValueLabel.Text = $S.ModsNone
	}
	$ModsValueLabel.ForeColor = $T.TextSoft

	$Running = Get-Process -Name $Game.ProcessName -ErrorAction SilentlyContinue
	$ProcessValueLabel.Text = if ($Running) { $S.ProcessRunning } else { $S.ProcessClosed }
	$ProcessValueLabel.ForeColor = $T.TextSoft

	if (Test-WindowsCompatible) {
		$OSValueLabel.Text = $S.OSCompatible
		$OSValueLabel.ForeColor = $T.Success
	} else {
		$OSValueLabel.Text = $S.OSNotCompatible
		$OSValueLabel.ForeColor = $T.Error
	}

	$RuntimeDescLabel.ForeColor = $T.TextSoft
	$RuntimeDescLabel.LinkColor = $Script:GameAccent
	$RuntimeDescLabel.ActiveLinkColor = $Script:GameAccent
	$RuntimeDescLabel.VisitedLinkColor = $Script:GameAccent
	if (Test-VCRedistInstalled) {
		$RuntimeDescLabel.Text = "$($S.RuntimeLabel): $($S.RuntimeInstalled)"
		$RuntimeDescLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(0,0)
	} else {
		$RuntimeBaseText = "$($S.RuntimeLabel): $($S.RuntimeNotFoundText)"
		$RuntimeDescLabel.Text = "$RuntimeBaseText $($S.RuntimeCta)"
		$RuntimeDescLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(($RuntimeBaseText.Length + 1), $S.RuntimeCta.Length)
	}

	$UIDataStatus = Get-UIDataStatus $GameName
	$UIDataValueLabel.Text = switch ($UIDataStatus) {
		"Found"    { $S.UIDataFound }
		"Empty"    { $S.UIDataEmpty }
		"NotFound" { $S.UIDataNotFound }
	}
	$UIDataValueLabel.ForeColor = $T.TextSoft

	$CacheBytes = Get-CacheTotalBytes $GameName
	$CacheLevel = Get-CacheLevel $GameName $CacheBytes
	$CacheDescLabel.ForeColor = $T.TextSoft
	$CacheDescLabel.LinkColor = $Script:GameAccent
	$CacheDescLabel.ActiveLinkColor = $Script:GameAccent
	$CacheDescLabel.VisitedLinkColor = $Script:GameAccent

	if ($Installed) {
		$CacheTitleLabel.Text = $CacheLevel.Title
		$CacheTitleLabel.ForeColor = $T[$CacheLevel.ColorKey]

		$CtaText = if (Test-Path $CleanerBatPath) { $S.CacheCtaOpen } else { $S.CacheCtaDownload }
		$BaseText = $CacheLevel.Description
		$CacheDescLabel.Text = "$BaseText $CtaText"
		$CacheDescLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(($BaseText.Length + 1), $CtaText.Length)
	} else {
		$CacheTitleLabel.Text = $S.CacheNotApplicableTitle
		$CacheTitleLabel.ForeColor = $T.Error
		$CacheDescLabel.Text = $S.CacheNotApplicableDescFormat -f $GameName
		$CacheDescLabel.LinkArea = New-Object System.Windows.Forms.LinkArea(0,0)
	}

	$Root = [System.IO.Path]::GetPathRoot($Game.AppDataPath)
	$Drive = New-Object System.IO.DriveInfo($Root)
	$DiskLevel = Get-DiskLevel $Drive.AvailableFreeSpace $Drive.Name
	$DiskTitleLabel.Text = $DiskLevel.Title
	$DiskTitleLabel.ForeColor = $T[$DiskLevel.ColorKey]
	$DiskDescLabel.Text = $DiskLevel.Description
	$DiskDescLabel.ForeColor = $T.TextSoft

	if (-not $Installed) {
		$ResultTitleLabel.Text = $S.ResultTitleNotInstalled
		$ResultTitleLabel.ForeColor = $T.Error
		$ResultDescLabel.Text = $S.ResultNotInstalledFormat -f $GameName
	} else {
		$Rank = @{ Success = 0; Warning = 1; Alert = 2; Error = 3 }
		$WorstKey = if ($Rank[$CacheLevel.ColorKey] -ge $Rank[$DiskLevel.ColorKey]) { $CacheLevel.ColorKey } else { $DiskLevel.ColorKey }
		if ($WorstKey -eq "Success") {
			$ResultTitleLabel.Text = $S.ResultTitleOk
			$ResultTitleLabel.ForeColor = $T.Success
			$ResultDescLabel.Text = $S.ResultOkFormat -f $GameName
		} else {
			$ResultTitleLabel.Text = $S.ResultTitleAttention
			$ResultTitleLabel.ForeColor = $T[$WorstKey]
			$ResultDescLabel.Text = $S.ResultAttentionFormat -f $GameName
		}
	}
	$ResultDescLabel.ForeColor = $T.TextSoft
}

function Set-Theme($Name) {
	$T = $Themes[$Name]
	$Script:CurrentTheme = $Name
	$GameAccent = Get-SharedAccentColor $Name
	$Script:GameAccent = $GameAccent

	$Form.BackColor = $T.FormBg
	$HeaderPanel.BackColor = $T.HeaderBg
	$ContentPanel.BackColor = $T.FormBg
	$BotoesPanel.BackColor = $T.FormBg
	$BannerPanel.BackColor = $T.FormBg
	$DiscordPanel.BackColor = $T.FormBg
	$TitleLabel.ForeColor = $T.HeaderTitle
	$SubtitleLabel.ForeColor = $T.HeaderSub
	$UpdateLabel.ForeColor = if ($UpdateAvailable) { $T.Error } else { $T.Success }
	$DescriptionLabel.ForeColor = $T.TextSoft
	$GameLabel.ForeColor = $T.Text
	$GameCombo.BackColor = $T.FieldBg
	$GameCombo.ForeColor = $T.FieldFg
	$InstallNameLabel.ForeColor = $T.Text
	$BaseGameNameLabel.ForeColor = $T.Text
	$ModsNameLabel.ForeColor = $T.Text
	$PathBox.BackColor = $T.FieldBg
	$PathBox.ForeColor = $T.TextSoft
	$ProcessNameLabel.ForeColor = $T.Text
	$OSNameLabel.ForeColor = $T.Text
	$UIDataNameLabel.ForeColor = $T.Text
	$RefreshButton.BackColor = $GameAccent
	$RefreshButton.ForeColor = $T.AccentTxt
	$CloseButton.BackColor = $T.Btn2Bg
	$CloseButton.ForeColor = $T.Btn2Fg
	$CloseButton.FlatAppearance.BorderColor = $T.Btn2Border
	$NewsHeaderLabel.ForeColor = $T.TextSoft
	$NewsLabel.ForeColor = $GameAccent
	$FreeLabel.ForeColor = $T.Credit

	if ($Form.IsHandleCreated) {
		$DarkModeValue = if ($T.DarkTitlebar) { 1 } else { 0 }
		[void][NFX.Dwm]::DwmSetWindowAttribute($Form.Handle,20,[ref]$DarkModeValue,4)
		$Form.Refresh()
	}
}

function Apply-Language($Lang) {
	$Script:CurrentLang = $Lang
	$S = $Strings[$Lang]

	$DescriptionLabel.Text = $S.Description
	$GameLabel.Text = $S.GameLabel
	$InstallNameLabel.Text = $S.InstallLabel
	$ModsNameLabel.Text = $S.ModsLabel
	$ProcessNameLabel.Text = $S.ProcessLabel
	$OSNameLabel.Text = $S.OSLabel
	$UIDataNameLabel.Text = $S.UIDataLabel
	$RefreshButton.Text = $S.RefreshButton
	$CloseButton.Text = $S.CloseButton
	$FreeLabel.Text = $S.FreeLabel

	if ($UpdateAvailable) {
		$UpdateLabel.Text = $S.UpdateAvailableFormat -f $LatestVersion
	} else {
		$UpdateLabel.Text = $S.UpdateOk
	}
	if ($News) {
		$NewsHeaderLabel.Text = $S.NewsHeader
	}

	Run-Checks
}

$GameCombo.Add_SelectedIndexChanged({
	$Script:CurrentGame = $GameCombo.SelectedItem
	Save-Game $GameCombo.SelectedItem
	Set-Theme $CurrentTheme
	Run-Checks
})

$RefreshButton.Add_Click({
	$Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
	$RefreshButton.Enabled = $false
	$Form.Refresh()
	Run-Checks
	$RefreshButton.Enabled = $true
	$Form.Cursor = [System.Windows.Forms.Cursors]::Default
})

$Form.Add_Shown({
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	$ContentPanel.BeginInvoke([Action]{
		$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	})
})

[System.Windows.Forms.Application]::EnableVisualStyles()

$null = $Form.Handle
Set-Theme $CurrentTheme
Apply-Language $CurrentLang

$Form.ShowDialog() | Out-Null
