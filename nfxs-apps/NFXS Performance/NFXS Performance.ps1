
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

Add-Type -Name Dwm -Namespace NFX -MemberDefinition @"
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@

$Games = @{
	"FiveM" = @{
		AppDataPath = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\data"
	}
	"RedM" = @{
		AppDataPath = Join-Path $env:LOCALAPPDATA "RedM\RedM.app\data"
	}
}

$Requirements = @{
	"FiveM" = @{
		RAMMinGB     = 4
		RAMRecGB     = 8
		StorageGB    = 125
		GPUVRAMMinGB = 1
		CPUMinRef = "Intel Core 2 Quad Q6600 @ 2.4GHz / AMD Phenom 9850 @ 2.5GHz"
		CPURecRef = "Intel Core i5 3470 @ 3.2GHz / AMD FX-8350 @ 4GHz"
		GPUMinRef = "NVIDIA 9800 GT 1GB / AMD HD 4870 1GB"
		GPURecRef = "NVIDIA GTX 660 2GB / AMD HD7870 2GB"
	}
	"RedM" = @{
		RAMMinGB     = 8
		RAMRecGB     = 12
		StorageGB    = 150
		GPUVRAMMinGB = 2
		CPUMinRef = "Intel Core i5-2500K / AMD FX-6300"
		CPURecRef = "Intel Core i7-4770K / AMD Ryzen 5 1500X"
		GPUMinRef = "NVIDIA GTX 770 2GB / AMD Radeon R9 280 3GB"
		GPURecRef = "NVIDIA GTX 1060 6GB / AMD Radeon RX 480 4GB"
	}
}

function Format-Bytes($Bytes) {
	if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
	if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
	if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
	return "< 1 KB"
}

function Test-OSCompatible {
	$Version = [System.Environment]::OSVersion.Version
	$Is64Bit = [System.Environment]::Is64BitOperatingSystem
	return ($Version.Major -ge 10) -and $Is64Bit
}

function Get-CPUName {
	try {
		$CPU = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
		if ($CPU -and $CPU.Name) {
			return $CPU.Name.Trim()
		}
	} catch {
	}
	return $null
}

function Get-GPUInfo {
	try {
		$Controllers = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -and $_.Name -notmatch "Basic Render|Remote Display" })
		if ($Controllers.Count -eq 0) {
			return $null
		}
		$Best = $Controllers | Sort-Object -Property AdapterRAM -Descending | Select-Object -First 1
		return [PSCustomObject]@{ Name = $Best.Name.Trim(); VRAMBytes = $Best.AdapterRAM }
	} catch {
	}
	return $null
}

function Get-RAMTotalBytes {
	try {
		return (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory
	} catch {
	}
	return $null
}

function Get-GameDiskFree($GameName) {
	$Game = $Games[$GameName]
	$Root = [System.IO.Path]::GetPathRoot($Game.AppDataPath)
	$Drive = New-Object System.IO.DriveInfo($Root)
	return [PSCustomObject]@{ Free = $Drive.AvailableFreeSpace; Name = $Drive.Name }
}

$SettingsDir  = Join-Path $env:APPDATA "NFXS-Performance"
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
		Description           = "Verifique se o seu PC atende aos requisitos do FiveM ou RedM."
		GameLabel              = "Jogo"
		OSLabel                = "Sistema"
		OSOk                   = "Compatível"
		OSNotOk                = "Não compatível"
		CPUNotDetected         = "Não foi possível detectar"
		ProcessorTitleFormat   = "Processador: {0}"
		CPUReqFormat           = "Requisito mínimo: {0}. Recomendado: {1}."
		RAMOkFormat            = "{0} de RAM"
		RAMReqFormat           = "Requisito mínimo: {0} GB. Recomendado: {1} GB."
		GPUNotDetected         = "Não foi possível detectar"
		VideoCardTitleFormat  = "Placa de vídeo: {0}"
		GPUReqFormat           = "Requisito mínimo: {0}. Recomendado: {1}."
		StorageFreeFormat      = "{0} livres no disco {1}"
		StorageReqFormat       = "Requisito: {0} GB de espaço livre pro jogo."
		ResultTitleOk          = "Atende aos requisitos"
		ResultTitleNotOk       = "Abaixo dos requisitos"
		ResultOkFormat         = "Seu PC atende aos requisitos mínimos pra rodar o {0}."
		ResultNotOkFormat      = "Seu PC está abaixo de algum requisito mínimo pro {0} - veja os itens acima em vermelho."
		RefreshButton          = "Verificar novamente"
		CloseButton            = "Fechar"
		ThemeButtonLight       = "Modo Claro"
		ThemeButtonDark        = "Modo Escuro"
		UpdateAvailableFormat  = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk               = "Você está com a versão mais recente."
		NewsHeader             = "Obrigado por usar nosso app, acesse:"
		FreeLabel              = "Produto gratuito disponibilizado por NunoFoxs"
	}
	"en" = @{
		Description           = "Check if your PC meets the requirements for FiveM or RedM."
		GameLabel              = "Game"
		OSLabel                = "System"
		OSOk                   = "Compatible"
		OSNotOk                = "Not compatible"
		CPUNotDetected         = "Could not be detected"
		ProcessorTitleFormat   = "Processor: {0}"
		CPUReqFormat           = "Minimum requirement: {0}. Recommended: {1}."
		RAMOkFormat            = "{0} of RAM"
		RAMReqFormat           = "Minimum requirement: {0} GB. Recommended: {1} GB."
		GPUNotDetected         = "Could not be detected"
		VideoCardTitleFormat  = "Video card: {0}"
		GPUReqFormat           = "Minimum requirement: {0}. Recommended: {1}."
		StorageFreeFormat      = "{0} free on drive {1}"
		StorageReqFormat       = "Requirement: {0} GB of free space for the game."
		ResultTitleOk          = "Meets requirements"
		ResultTitleNotOk       = "Below requirements"
		ResultOkFormat         = "Your PC meets the minimum requirements to run {0}."
		ResultNotOkFormat      = "Your PC is below a minimum requirement for {0} - check the items above in red."
		RefreshButton          = "Check again"
		CloseButton            = "Close"
		ThemeButtonLight       = "Light Mode"
		ThemeButtonDark        = "Dark Mode"
		UpdateAvailableFormat  = "New version available (v{0}) - click here"
		UpdateOk               = "You have the latest version."
		NewsHeader             = "Thanks for using our app, check out:"
		FreeLabel              = "Free product provided by NunoFoxs"
	}
	"es" = @{
		Description           = "Verifica si tu PC cumple los requisitos del FiveM o RedM."
		GameLabel              = "Juego"
		OSLabel                = "Sistema"
		OSOk                   = "Compatible"
		OSNotOk                = "No compatible"
		CPUNotDetected         = "No se pudo detectar"
		ProcessorTitleFormat   = "Procesador: {0}"
		CPUReqFormat           = "Requisito mínimo: {0}. Recomendado: {1}."
		RAMOkFormat            = "{0} de RAM"
		RAMReqFormat           = "Requisito mínimo: {0} GB. Recomendado: {1} GB."
		GPUNotDetected         = "No se pudo detectar"
		VideoCardTitleFormat  = "Tarjeta de video: {0}"
		GPUReqFormat           = "Requisito mínimo: {0}. Recomendado: {1}."
		StorageFreeFormat      = "{0} libres en el disco {1}"
		StorageReqFormat       = "Requisito: {0} GB de espacio libre para el juego."
		ResultTitleOk          = "Cumple los requisitos"
		ResultTitleNotOk       = "Por debajo de los requisitos"
		ResultOkFormat         = "Tu PC cumple los requisitos mínimos para ejecutar {0}."
		ResultNotOkFormat      = "Tu PC está por debajo de algún requisito mínimo para {0} - revisa los ítems de arriba en rojo."
		RefreshButton          = "Verificar de nuevo"
		CloseButton            = "Cerrar"
		ThemeButtonLight       = "Modo Claro"
		ThemeButtonDark        = "Modo Oscuro"
		UpdateAvailableFormat  = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk               = "Tienes la versión más reciente."
		NewsHeader             = "Gracias por usar nuestra app, visita:"
		FreeLabel              = "Producto gratuito ofrecido por NunoFoxs"
	}
	"de" = @{
		Description           = "Prüfe, ob dein PC die Anforderungen für FiveM oder RedM erfüllt."
		GameLabel              = "Spiel"
		OSLabel                = "System"
		OSOk                   = "Kompatibel"
		OSNotOk                = "Nicht kompatibel"
		CPUNotDetected         = "Konnte nicht erkannt werden"
		ProcessorTitleFormat   = "Prozessor: {0}"
		CPUReqFormat           = "Mindestanforderung: {0}. Empfohlen: {1}."
		RAMOkFormat            = "{0} RAM"
		RAMReqFormat           = "Mindestanforderung: {0} GB. Empfohlen: {1} GB."
		GPUNotDetected         = "Konnte nicht erkannt werden"
		VideoCardTitleFormat  = "Grafikkarte: {0}"
		GPUReqFormat           = "Mindestanforderung: {0}. Empfohlen: {1}."
		StorageFreeFormat      = "{0} frei auf Laufwerk {1}"
		StorageReqFormat       = "Anforderung: {0} GB freier Speicherplatz für das Spiel."
		ResultTitleOk          = "Erfüllt die Anforderungen"
		ResultTitleNotOk       = "Unter den Anforderungen"
		ResultOkFormat         = "Dein PC erfüllt die Mindestanforderungen für {0}."
		ResultNotOkFormat      = "Dein PC liegt unter einer Mindestanforderung für {0} - siehe die rot markierten Punkte oben."
		RefreshButton          = "Erneut prüfen"
		CloseButton            = "Schließen"
		ThemeButtonLight       = "Heller Modus"
		ThemeButtonDark        = "Dunkler Modus"
		UpdateAvailableFormat  = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk               = "Du hast die neueste Version."
		NewsHeader             = "Danke, dass du unsere App nutzt, schau vorbei:"
		FreeLabel              = "Kostenloses Produkt bereitgestellt von NunoFoxs"
	}
	"fr" = @{
		Description           = "Vérifiez si votre PC répond aux exigences du FiveM ou RedM."
		GameLabel              = "Jeu"
		OSLabel                = "Système"
		OSOk                   = "Compatible"
		OSNotOk                = "Non compatible"
		CPUNotDetected         = "Impossible à détecter"
		ProcessorTitleFormat   = "Processeur : {0}"
		CPUReqFormat           = "Exigence minimale : {0}. Recommandé : {1}."
		RAMOkFormat            = "{0} de RAM"
		RAMReqFormat           = "Exigence minimale : {0} GB. Recommandé : {1} GB."
		GPUNotDetected         = "Impossible à détecter"
		VideoCardTitleFormat  = "Carte graphique : {0}"
		GPUReqFormat           = "Exigence minimale : {0}. Recommandé : {1}."
		StorageFreeFormat      = "{0} libres sur le disque {1}"
		StorageReqFormat       = "Exigence : {0} GB d'espace libre pour le jeu."
		ResultTitleOk          = "Répond aux exigences"
		ResultTitleNotOk       = "En dessous des exigences"
		ResultOkFormat         = "Votre PC répond aux exigences minimales pour {0}."
		ResultNotOkFormat      = "Votre PC est en dessous d'une exigence minimale pour {0} - consultez les éléments en rouge ci-dessus."
		RefreshButton          = "Vérifier à nouveau"
		CloseButton            = "Fermer"
		ThemeButtonLight       = "Mode Clair"
		ThemeButtonDark        = "Mode Sombre"
		UpdateAvailableFormat  = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk               = "Vous avez la dernière version."
		NewsHeader             = "Merci d'utiliser notre application, découvrez :"
		FreeLabel              = "Produit gratuit proposé par NunoFoxs"
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
$Form.Text = "NFXS - Performance"
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
$TitleLabel.Text = "NFXS | PERFORMANCE"
$TitleLabel.Font = Scale-Font 12 ([System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = Scale-Point 18 13
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.Text = "FiveM & RedM Requirements v$AppVersion"
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
$Y += (Scale-Val 26)

$CPUTitleLabel = New-Object System.Windows.Forms.Label
$CPUTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$CPUTitleLabel.Size = Scale-Size 344 16
$CPUTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($CPUTitleLabel)
$Y += (Scale-Val 16)

$CPUDescLabel = New-Object System.Windows.Forms.Label
$CPUDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$CPUDescLabel.Size = Scale-SizeMinHeight 344 32 30
$CPUDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($CPUDescLabel)
$Y += (Scale-Val 40) + [Math]::Max(0, $CPUDescLabel.Size.Height - (Scale-Val 32))

$RAMTitleLabel = New-Object System.Windows.Forms.Label
$RAMTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$RAMTitleLabel.Size = Scale-Size 344 16
$RAMTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($RAMTitleLabel)
$Y += (Scale-Val 16)

$RAMDescLabel = New-Object System.Windows.Forms.Label
$RAMDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$RAMDescLabel.Size = Scale-SizeMinHeight 344 32 30
$RAMDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($RAMDescLabel)
$Y += (Scale-Val 40) + [Math]::Max(0, $RAMDescLabel.Size.Height - (Scale-Val 32))

$GPUTitleLabel = New-Object System.Windows.Forms.Label
$GPUTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$GPUTitleLabel.Size = Scale-Size 344 16
$GPUTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($GPUTitleLabel)
$Y += (Scale-Val 16)

$GPUDescLabel = New-Object System.Windows.Forms.Label
$GPUDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$GPUDescLabel.Size = Scale-SizeMinHeight 344 32 30
$GPUDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($GPUDescLabel)
$Y += (Scale-Val 40) + [Math]::Max(0, $GPUDescLabel.Size.Height - (Scale-Val 32))

$StorageTitleLabel = New-Object System.Windows.Forms.Label
$StorageTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$StorageTitleLabel.Size = Scale-Size 344 16
$StorageTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($StorageTitleLabel)
$Y += (Scale-Val 16)

$StorageDescLabel = New-Object System.Windows.Forms.Label
$StorageDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$StorageDescLabel.Size = Scale-SizeMinHeight 344 32 30
$StorageDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($StorageDescLabel)
$Y += (Scale-Val 42) + [Math]::Max(0, $StorageDescLabel.Size.Height - (Scale-Val 32))

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
$Y += (Scale-Val 50) + [Math]::Max(0, $ResultDescLabel.Size.Height - (Scale-Val 40))

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

function Run-Checks {
	$S = $Strings[$CurrentLang]
	$T = $Themes[$CurrentTheme]
	$GameName = $Script:CurrentGame
	$Req = $Requirements[$GameName]

	$OSOk = Test-OSCompatible
	if ($OSOk) {
		$OSValueLabel.Text = $S.OSOk
		$OSValueLabel.ForeColor = $T.Success
	} else {
		$OSValueLabel.Text = $S.OSNotOk
		$OSValueLabel.ForeColor = $T.Error
	}

	$CPUName = Get-CPUName
	$CPUTitleLabel.Text = $S.ProcessorTitleFormat -f ($(if ($CPUName) { $CPUName } else { $S.CPUNotDetected }))
	$CPUTitleLabel.ForeColor = $T.Text
	$CPUDescLabel.Text = $S.CPUReqFormat -f $Req.CPUMinRef, $Req.CPURecRef
	$CPUDescLabel.ForeColor = $T.TextSoft

	$RAMBytes = Get-RAMTotalBytes
	$RAMMinBytes = $Req.RAMMinGB * 1GB
	if ($null -eq $RAMBytes) {
		$RAMTitleLabel.Text = $S.CPUNotDetected
		$RAMTitleLabel.ForeColor = $T.TextSoft
	} elseif ($RAMBytes -ge $RAMMinBytes) {
		$RAMTitleLabel.Text = $S.RAMOkFormat -f (Format-Bytes $RAMBytes)
		$RAMTitleLabel.ForeColor = $T.Success
	} else {
		$RAMTitleLabel.Text = $S.RAMOkFormat -f (Format-Bytes $RAMBytes)
		$RAMTitleLabel.ForeColor = $T.Error
	}
	$RAMDescLabel.Text = $S.RAMReqFormat -f $Req.RAMMinGB, $Req.RAMRecGB
	$RAMDescLabel.ForeColor = $T.TextSoft

	$GPUInfo = Get-GPUInfo
	$GPUVRAMMinBytes = $Req.GPUVRAMMinGB * 1GB
	if (-not $GPUInfo) {
		$GPUTitleLabel.Text = $S.VideoCardTitleFormat -f $S.GPUNotDetected
		$GPUTitleLabel.ForeColor = $T.TextSoft
		$GPUOk = $null
	} else {
		$GPUTitleLabel.Text = $S.VideoCardTitleFormat -f $GPUInfo.Name
		if ($GPUInfo.VRAMBytes -and $GPUInfo.VRAMBytes -gt 0) {
			$GPUOk = $GPUInfo.VRAMBytes -ge $GPUVRAMMinBytes
			$GPUTitleLabel.ForeColor = if ($GPUOk) { $T.Success } else { $T.Error }
		} else {
			$GPUOk = $null
			$GPUTitleLabel.ForeColor = $T.Text
		}
	}
	$GPUDescLabel.Text = $S.GPUReqFormat -f $Req.GPUMinRef, $Req.GPURecRef
	$GPUDescLabel.ForeColor = $T.TextSoft

	$Disk = Get-GameDiskFree $GameName
	$StorageMinBytes = $Req.StorageGB * 1GB
	$StorageOk = $Disk.Free -ge $StorageMinBytes
	$StorageTitleLabel.Text = $S.StorageFreeFormat -f (Format-Bytes $Disk.Free), $Disk.Name
	$StorageTitleLabel.ForeColor = if ($StorageOk) { $T.Success } else { $T.Error }
	$StorageDescLabel.Text = $S.StorageReqFormat -f $Req.StorageGB
	$StorageDescLabel.ForeColor = $T.TextSoft

	$AllOk = $OSOk -and ($RAMBytes -ge $RAMMinBytes) -and $StorageOk -and ($GPUOk -ne $false)
	if ($AllOk) {
		$ResultTitleLabel.Text = $S.ResultTitleOk
		$ResultTitleLabel.ForeColor = $T.Success
		$ResultDescLabel.Text = $S.ResultOkFormat -f $GameName
	} else {
		$ResultTitleLabel.Text = $S.ResultTitleNotOk
		$ResultTitleLabel.ForeColor = $T.Error
		$ResultDescLabel.Text = $S.ResultNotOkFormat -f $GameName
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
	$OSNameLabel.ForeColor = $T.Text
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
	$OSNameLabel.Text = $S.OSLabel
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
