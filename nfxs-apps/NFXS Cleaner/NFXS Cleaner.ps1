
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
$VersionCheckUrl = "https://gist.githubusercontent.com/nunofoxs/ae0312b7929ea071d1e33bf61bb2df88/raw/versao.txt"

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

Add-Type -Name Dwm -Namespace NFX -MemberDefinition @"
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
"@

$Games = @{
	"FiveM" = @{
		ProcessName     = "FiveM*"
		AppDataPath     = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\data"
		ExePath         = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app\FiveM.com"
		Protocol        = "fivem://"
		ConnectPrefix   = "fivem://connect/"
		DefaultAddress  = "131.196.197.86:30120"
		RemoteConfigUrl = "https://gist.githubusercontent.com/nunofoxs/ce42b6a8fd2d67224bf3970c497e9cad/raw/fivem.txt"
	}
	"RedM" = @{
		ProcessName     = "RedM*"
		AppDataPath     = Join-Path $env:LOCALAPPDATA "RedM\RedM.app\data"
		ExePath         = Join-Path $env:LOCALAPPDATA "RedM\RedM.app\CitiCon.com"
		Protocol        = "redm://"
		ConnectPrefix   = "redm://connect/"
		DefaultAddress  = ""
		RemoteConfigUrl = "https://gist.githubusercontent.com/nunofoxs/08d7f3f1481c0d541b8000e7afe0cd0b/raw/redm.txt"
	}
}

function Format-Bytes($Bytes) {
	if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
	if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
	if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
	return "< 1 KB"
}

function Test-ValidAddress($Value) {
	if (-not $Value -or $Value.Length -gt 100 -or $Value -match '\s') {
		return $false
	}

	return ($Value -match ':\d{1,5}$') -or ($Value -match 'cfx\.re/join/')
}

function Get-RemoteAddress($Url) {
	if (-not $Url) {
		return $null
	}

	try {
		$Response = Invoke-RestMethod -Uri $Url -TimeoutSec 3 -ErrorAction Stop
		$Value = ([string]$Response -split "`n" | Select-Object -First 1).Trim()
		if (Test-ValidAddress $Value) {
			return $Value
		}
	} catch {
	}

	return $null
}

foreach ($GameKey in @($Games.Keys)) {
	$Remote = Get-RemoteAddress $Games[$GameKey].RemoteConfigUrl
	if ($Remote) {
		$Games[$GameKey].DefaultAddress = $Remote
	}
}

$CleanModes = @{
	"Cache" = @("cache","server-cache","server-cache-priv")
	"Tudo"  = @("cache","server-cache","server-cache-priv","game-storage")
}

function Get-CacheTotalBytes($GameName, $ModeName) {
	$Game = $Games[$GameName]
	$Total = 0
	foreach ($Folder in $CleanModes[$ModeName]) {
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
		return [PSCustomObject]@{
			Title       = $S.LevelExcessiveTitle
			Description = $S.LevelExcessiveDescFormat -f $SizeText
			ColorKey    = "Error"
		}
	} elseif ($TotalBytes -ge $Limits.Large) {
		return [PSCustomObject]@{
			Title       = $S.LevelLargeTitle
			Description = $S.LevelLargeDescFormat -f $SizeText
			ColorKey    = "Alert"
		}
	} elseif ($TotalBytes -ge $Limits.Elevated) {
		return [PSCustomObject]@{
			Title       = $S.LevelElevatedTitle
			Description = $S.LevelElevatedDescFormat -f $SizeText
			ColorKey    = "Warning"
		}
	} else {
		return [PSCustomObject]@{
			Title       = $S.LevelNormalTitle
			Description = $S.LevelNormalDescFormat -f $SizeText
			ColorKey    = "Success"
		}
	}
}

$SettingsDir  = Join-Path $env:APPDATA "NFXS-Cleaner"
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
		Description           = "Limpe o cache de forma segura e rápida."
		GameLabel              = "Jogo"
		AddressLabel           = "Endereço do servidor (opcional)"
		ModeGroupTitle         = "O que limpar"
		CacheRadio             = "Limpeza rápida (recomendado)"
		FullRadio              = "Limpeza completa"
		OpenCheck              = "Abrir o jogo após a limpeza"
		CleanButton            = "Limpar"
		CloseButton            = "Fechar"
		ThemeButtonLight       = "Modo Claro"
		ThemeButtonDark        = "Modo Escuro"
		UpdateAvailableFormat  = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk               = "Você está com a versão mais recente."
		NewsHeader             = "Obrigado por usar nosso app, acesse:"
		DiscordButton          = "Discord"
		FreeLabel              = "Produto gratuito disponibilizado por NunoFoxs"
		FullCleanWarningTitle  = "Limpeza completa"
		FullCleanWarningFormat = "Na limpeza completa, o {0} vai demorar mais pra carregar na próxima vez que você abrir ele. Isso é normal, ele só precisa baixar de novo algumas coisas que foram apagadas, tipo se fosse a primeira vez instalando. Não é erro nem problema.`n`nRecomendado: fazer isso pelo menos 1 vez por mês, ou mais vezes se você costuma entrar em vários servidores diferentes.`n`nQuer continuar?"
		Cancelled              = "Cancelado."
		GameOpenTitle          = "Jogo aberto"
		GameOpenWarningFormat  = "O {0} parece estar aberto. É necessário fechar o jogo antes de limpar (os arquivos ficam bloqueados enquanto o jogo está em execução).`n`nFechar agora?"
		CancelledCloseGameFormat = "Cancelado. Feche o {0} e tente de novo."
		VerifyingFormat        = "Verificando se o {0} está aberto..."
		CleaningNow            = "Limpando, aguarde..."
		FoundSizeFormat        = "Encontramos {0} de cache. Limpando..."
		CurrentCacheFormat     = "Cache atual: {0}"
		LevelNormalTitle       = "Cache normal"
		LevelElevatedTitle     = "Cache elevado"
		LevelLargeTitle        = "Cache muito grande"
		LevelExcessiveTitle    = "Cache excessivo"
		LevelNormalDescFormat    = "Seu cache está usando {0}. Está dentro do esperado."
		LevelElevatedDescFormat  = "Seu cache está usando {0}. Uma limpeza pode liberar espaço."
		LevelLargeDescFormat     = "Seu cache está usando {0}. Recomendamos limpar em breve."
		LevelExcessiveDescFormat = "Seu cache está usando {0}. Recomendamos limpar agora."
		ErrorCleanFormat       = "Não consegui limpar tudo. Feche o {0} (se estiver aberto) e tente de novo."
		SuccessCleanFormat     = "Pronto! Cache do {0} limpo com sucesso. Você liberou {1} de espaço."
		AlreadyCleanFormat     = "Seu cache do {0} já estava limpo."
		OpeningFormat          = "`nAbrindo {0}..."
		ErrorOpenFormat        = "`nErro ao abrir o {0}: {1}"
		NotInstalledFormat     = "`nNão consegui abrir o {0} automaticamente (não achei o jogo instalado nesse PC)."
		LastCleanNever         = "Nenhuma limpeza registrada ainda."
		LastCleanTodayFormat   = "Última limpeza ({0}): hoje."
		LastCleanYesterdayFormat = "Última limpeza ({0}): ontem."
		LastCleanDaysFormat    = "Última limpeza ({0}): há {1} dias."
		LastCleanReminderSuffix = " Recomendamos limpar novamente."
		ModeQuick              = "rápida"
		ModeFull               = "completa"
	}
	"en" = @{
		Description           = "Clean your cache safely and quickly."
		GameLabel              = "Game"
		AddressLabel           = "Server address (optional)"
		ModeGroupTitle         = "What to clean"
		CacheRadio             = "Quick clean (recommended)"
		FullRadio              = "Full clean"
		OpenCheck              = "Open the game after cleaning"
		CleanButton            = "Clean"
		CloseButton            = "Close"
		ThemeButtonLight       = "Light Mode"
		ThemeButtonDark        = "Dark Mode"
		UpdateAvailableFormat  = "New version available (v{0}) - click here"
		UpdateOk               = "You have the latest version."
		NewsHeader             = "Thanks for using our app, check out:"
		DiscordButton          = "Discord"
		FreeLabel              = "Free product provided by NunoFoxs"
		FullCleanWarningTitle  = "Full clean"
		FullCleanWarningFormat = "With a full clean, {0} will take longer to load the next time you open it. This is normal, it just needs to re-download some files that were deleted, like a first install. It is not an error or a problem.`n`nRecommended: do this at least once a month, or more often if you usually play on many different servers.`n`nDo you want to continue?"
		Cancelled              = "Cancelled."
		GameOpenTitle          = "Game is open"
		GameOpenWarningFormat  = "{0} seems to be open. It needs to be closed before cleaning (the files stay locked while the game is running).`n`nClose it now?"
		CancelledCloseGameFormat = "Cancelled. Close {0} and try again."
		VerifyingFormat        = "Checking if {0} is open..."
		CleaningNow            = "Cleaning, please wait..."
		FoundSizeFormat        = "Found {0} of cache. Cleaning..."
		CurrentCacheFormat     = "Current cache: {0}"
		LevelNormalTitle       = "Normal cache"
		LevelElevatedTitle     = "Elevated cache"
		LevelLargeTitle        = "Very large cache"
		LevelExcessiveTitle    = "Excessive cache"
		LevelNormalDescFormat    = "Your cache is using {0}. This is within the expected range."
		LevelElevatedDescFormat  = "Your cache is using {0}. A clean-up could free up space."
		LevelLargeDescFormat     = "Your cache is using {0}. We recommend cleaning soon."
		LevelExcessiveDescFormat = "Your cache is using {0}. We recommend cleaning now."
		ErrorCleanFormat       = "Could not clean everything. Close {0} (if it is open) and try again."
		SuccessCleanFormat     = "Done! {0} cache cleaned successfully. You freed up {1} of space!"
		AlreadyCleanFormat     = "Your {0} cache was already clean."
		OpeningFormat          = "`nOpening {0}..."
		ErrorOpenFormat        = "`nError opening {0}: {1}"
		NotInstalledFormat     = "`nCould not open {0} automatically (game not found installed on this PC)."
		LastCleanNever         = "No cleaning recorded yet."
		LastCleanTodayFormat   = "Last clean ({0}): today."
		LastCleanYesterdayFormat = "Last clean ({0}): yesterday."
		LastCleanDaysFormat    = "Last clean ({0}): {1} days ago."
		LastCleanReminderSuffix = " We recommend cleaning again."
		ModeQuick              = "quick"
		ModeFull               = "full"
	}
	"es" = @{
		Description           = "Limpia el caché de forma segura y rápida."
		GameLabel              = "Juego"
		AddressLabel           = "Dirección del servidor (opcional)"
		ModeGroupTitle         = "Qué limpiar"
		CacheRadio             = "Limpieza rápida (recomendado)"
		FullRadio              = "Limpieza completa"
		OpenCheck              = "Abrir el juego después de limpiar"
		CleanButton            = "Limpiar"
		CloseButton            = "Cerrar"
		ThemeButtonLight       = "Modo Claro"
		ThemeButtonDark        = "Modo Oscuro"
		UpdateAvailableFormat  = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk               = "Tienes la versión más reciente."
		NewsHeader             = "Gracias por usar nuestra app, visita:"
		DiscordButton          = "Discord"
		FreeLabel              = "Producto gratuito ofrecido por NunoFoxs"
		FullCleanWarningTitle  = "Limpieza completa"
		FullCleanWarningFormat = "Con la limpieza completa, {0} tardará más en cargar la próxima vez que lo abras. Esto es normal, solo necesita descargar de nuevo algunos archivos que fueron borrados, como si fuera la primera instalación. No es un error ni un problema.`n`nRecomendado: hacer esto al menos 1 vez al mes, o más seguido si sueles entrar en varios servidores diferentes.`n`n¿Quieres continuar?"
		Cancelled              = "Cancelado."
		GameOpenTitle          = "Juego abierto"
		GameOpenWarningFormat  = "{0} parece estar abierto. Es necesario cerrarlo antes de limpiar (los archivos quedan bloqueados mientras el juego está en ejecución).`n`n¿Cerrar ahora?"
		CancelledCloseGameFormat = "Cancelado. Cierra {0} e intenta de nuevo."
		VerifyingFormat        = "Verificando si {0} está abierto..."
		CleaningNow            = "Limpiando, espera..."
		FoundSizeFormat        = "Encontramos {0} de caché. Limpiando..."
		CurrentCacheFormat     = "Caché actual: {0}"
		LevelNormalTitle       = "Caché normal"
		LevelElevatedTitle     = "Caché elevado"
		LevelLargeTitle        = "Caché muy grande"
		LevelExcessiveTitle    = "Caché excesivo"
		LevelNormalDescFormat    = "Tu caché está usando {0}. Está dentro de lo esperado."
		LevelElevatedDescFormat  = "Tu caché está usando {0}. Una limpieza puede liberar espacio."
		LevelLargeDescFormat     = "Tu caché está usando {0}. Recomendamos limpiar pronto."
		LevelExcessiveDescFormat = "Tu caché está usando {0}. Recomendamos limpiar ahora."
		ErrorCleanFormat       = "No pude limpiar todo. Cierra {0} (si está abierto) e intenta de nuevo."
		SuccessCleanFormat     = "¡Listo! Caché de {0} limpiado con éxito. ¡Liberaste {1} de espacio!"
		AlreadyCleanFormat     = "Tu caché de {0} ya estaba limpio."
		OpeningFormat          = "`nAbriendo {0}..."
		ErrorOpenFormat        = "`nError al abrir {0}: {1}"
		NotInstalledFormat     = "`nNo pude abrir {0} automáticamente (no encontré el juego instalado en esta PC)."
		LastCleanNever         = "Todavía no hay ninguna limpieza registrada."
		LastCleanTodayFormat   = "Última limpieza ({0}): hoy."
		LastCleanYesterdayFormat = "Última limpieza ({0}): ayer."
		LastCleanDaysFormat    = "Última limpieza ({0}): hace {1} días."
		LastCleanReminderSuffix = " Recomendamos limpiar de nuevo."
		ModeQuick              = "rápida"
		ModeFull               = "completa"
	}
	"de" = @{
		Description           = "Reinigen Sie Ihren Cache sicher und schnell."
		GameLabel              = "Spiel"
		AddressLabel           = "Serveradresse (optional)"
		ModeGroupTitle         = "Was gereinigt wird"
		CacheRadio             = "Schnelle Reinigung (empfohlen)"
		FullRadio              = "Vollständige Reinigung"
		OpenCheck              = "Spiel nach der Reinigung öffnen"
		CleanButton            = "Reinigen"
		CloseButton            = "Schließen"
		ThemeButtonLight       = "Heller Modus"
		ThemeButtonDark        = "Dunkler Modus"
		UpdateAvailableFormat  = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk               = "Sie haben die neueste Version."
		NewsHeader             = "Danke, dass Sie unsere App nutzen, besuchen Sie:"
		DiscordButton          = "Discord"
		FreeLabel              = "Kostenloses Produkt bereitgestellt von NunoFoxs"
		FullCleanWarningTitle  = "Vollständige Reinigung"
		FullCleanWarningFormat = "Bei einer vollständigen Reinigung dauert es beim nächsten Öffnen länger, bis {0} lädt. Das ist normal, es müssen nur einige gelöschte Dateien neu heruntergeladen werden, ähnlich wie bei einer Erstinstallation. Das ist kein Fehler und kein Problem.`n`nEmpfohlen: mindestens einmal im Monat, oder öfter, wenn Sie häufig auf verschiedenen Servern spielen.`n`nMöchten Sie fortfahren?"
		Cancelled              = "Abgebrochen."
		GameOpenTitle          = "Spiel geöffnet"
		GameOpenWarningFormat  = "{0} scheint geöffnet zu sein. Das Spiel muss vor der Reinigung geschlossen werden (die Dateien bleiben gesperrt, während das Spiel läuft).`n`nJetzt schließen?"
		CancelledCloseGameFormat = "Abgebrochen. Schließen Sie {0} und versuchen Sie es erneut."
		VerifyingFormat        = "Wird geprüft, ob {0} geöffnet ist..."
		CleaningNow            = "Wird gereinigt, bitte warten..."
		FoundSizeFormat        = "{0} Cache gefunden. Wird gereinigt..."
		CurrentCacheFormat     = "Aktueller Cache: {0}"
		LevelNormalTitle       = "Normaler Cache"
		LevelElevatedTitle     = "Erhöhter Cache"
		LevelLargeTitle        = "Sehr großer Cache"
		LevelExcessiveTitle    = "Übermäßiger Cache"
		LevelNormalDescFormat    = "Ihr Cache belegt {0}. Das liegt im erwarteten Bereich."
		LevelElevatedDescFormat  = "Ihr Cache belegt {0}. Eine Reinigung könnte Speicherplatz freigeben."
		LevelLargeDescFormat     = "Ihr Cache belegt {0}. Wir empfehlen eine baldige Reinigung."
		LevelExcessiveDescFormat = "Ihr Cache belegt {0}. Wir empfehlen eine sofortige Reinigung."
		ErrorCleanFormat       = "Es konnte nicht alles gereinigt werden. Schließen Sie {0} (falls geöffnet) und versuchen Sie es erneut."
		SuccessCleanFormat     = "Fertig! {0}-Cache erfolgreich gereinigt. Sie haben {1} Speicherplatz freigegeben."
		AlreadyCleanFormat     = "Ihr {0}-Cache war bereits sauber."
		OpeningFormat          = "`n{0} wird geöffnet..."
		ErrorOpenFormat        = "`nFehler beim Öffnen von {0}: {1}"
		NotInstalledFormat     = "`n{0} konnte nicht automatisch geöffnet werden (Spiel auf diesem PC nicht gefunden)."
		LastCleanNever         = "Bisher keine Reinigung registriert."
		LastCleanTodayFormat   = "Letzte Reinigung ({0}): heute."
		LastCleanYesterdayFormat = "Letzte Reinigung ({0}): gestern."
		LastCleanDaysFormat    = "Letzte Reinigung ({0}): vor {1} Tagen."
		LastCleanReminderSuffix = " Wir empfehlen eine erneute Reinigung."
		ModeQuick              = "schnelle"
		ModeFull               = "vollständige"
	}
	"fr" = @{
		Description           = "Nettoyez votre cache en toute sécurité et rapidement."
		GameLabel              = "Jeu"
		AddressLabel           = "Adresse du serveur (optionnel)"
		ModeGroupTitle         = "Que nettoyer"
		CacheRadio             = "Nettoyage rapide (recommandé)"
		FullRadio              = "Nettoyage complet"
		OpenCheck              = "Ouvrir le jeu après le nettoyage"
		CleanButton            = "Nettoyer"
		CloseButton            = "Fermer"
		ThemeButtonLight       = "Mode Clair"
		ThemeButtonDark        = "Mode Sombre"
		UpdateAvailableFormat  = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk               = "Vous avez la dernière version."
		NewsHeader             = "Merci d'utiliser notre application, visitez :"
		DiscordButton          = "Discord"
		FreeLabel              = "Produit gratuit fourni par NunoFoxs"
		FullCleanWarningTitle  = "Nettoyage complet"
		FullCleanWarningFormat = "Avec un nettoyage complet, {0} mettra plus de temps à se charger la prochaine fois que vous l'ouvrirez. C'est normal, il doit simplement retélécharger certains fichiers supprimés, comme lors d'une première installation. Ce n'est ni une erreur ni un problème.`n`nRecommandé : faites-le au moins une fois par mois, ou plus souvent si vous jouez souvent sur plusieurs serveurs différents.`n`nVoulez-vous continuer ?"
		Cancelled              = "Annulé."
		GameOpenTitle          = "Jeu ouvert"
		GameOpenWarningFormat  = "{0} semble être ouvert. Il doit être fermé avant le nettoyage (les fichiers restent verrouillés pendant que le jeu est en cours d'exécution).`n`nFermer maintenant ?"
		CancelledCloseGameFormat = "Annulé. Fermez {0} et réessayez."
		VerifyingFormat        = "Vérification si {0} est ouvert..."
		CleaningNow            = "Nettoyage en cours, veuillez patienter..."
		FoundSizeFormat        = "{0} de cache trouvé. Nettoyage en cours..."
		CurrentCacheFormat     = "Cache actuel : {0}"
		LevelNormalTitle       = "Cache normal"
		LevelElevatedTitle     = "Cache élevé"
		LevelLargeTitle        = "Cache très volumineux"
		LevelExcessiveTitle    = "Cache excessif"
		LevelNormalDescFormat    = "Votre cache utilise {0}. Cela reste dans la plage attendue."
		LevelElevatedDescFormat  = "Votre cache utilise {0}. Un nettoyage pourrait libérer de l'espace."
		LevelLargeDescFormat     = "Votre cache utilise {0}. Nous recommandons de nettoyer bientôt."
		LevelExcessiveDescFormat = "Votre cache utilise {0}. Nous recommandons de nettoyer maintenant."
		ErrorCleanFormat       = "Impossible de tout nettoyer. Fermez {0} (s'il est ouvert) et réessayez."
		SuccessCleanFormat     = "Terminé ! Cache de {0} nettoyé avec succès. Vous avez libéré {1} d'espace."
		AlreadyCleanFormat     = "Votre cache {0} était déjà propre."
		OpeningFormat          = "`nOuverture de {0}..."
		ErrorOpenFormat        = "`nErreur lors de l'ouverture de {0} : {1}"
		NotInstalledFormat     = "`nImpossible d'ouvrir {0} automatiquement (jeu introuvable sur ce PC)."
		LastCleanNever         = "Aucun nettoyage enregistré pour le moment."
		LastCleanTodayFormat   = "Dernier nettoyage ({0}) : aujourd'hui."
		LastCleanYesterdayFormat = "Dernier nettoyage ({0}) : hier."
		LastCleanDaysFormat    = "Dernier nettoyage ({0}) : il y a {1} jours."
		LastCleanReminderSuffix = " Nous recommandons de nettoyer à nouveau."
		ModeQuick              = "rapide"
		ModeFull               = "complet"
	}
}

$CurrentLang = Get-SharedLang

function Get-LastCleanFile($GameName) {
	return Join-Path $SettingsDir "lastclean_$GameName.cfg"
}

function Get-LastCleanText($GameName) {
	$S = $Strings[$CurrentLang]
	$File = Get-LastCleanFile $GameName
	if (-not (Test-Path $File)) {
		return $S.LastCleanNever
	}

	try {
		$Lines = @(Get-Content $File -ErrorAction Stop)
		$LastDate = [DateTime]::Parse($Lines[0])
		$SavedMode = if ($Lines.Count -ge 2) { $Lines[1] } else { "Cache" }
		$ModeLabel = if ($SavedMode -eq "Tudo") { $S.ModeFull } else { $S.ModeQuick }
		$Days = [Math]::Floor(((Get-Date) - $LastDate).TotalDays)

		$Base = if ($Days -le 0) {
			$S.LastCleanTodayFormat -f $ModeLabel
		} elseif ($Days -eq 1) {
			$S.LastCleanYesterdayFormat -f $ModeLabel
		} else {
			$S.LastCleanDaysFormat -f $ModeLabel, $Days
		}

		if ($Days -ge 30) {
			return "$Base$($S.LastCleanReminderSuffix)"
		}
		return $Base
	} catch {
		return $S.LastCleanNever
	}
}

function Save-LastCleanDate($GameName, $ModeName) {
	try {
		if (-not (Test-Path $SettingsDir)) {
			New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
		}
		Set-Content -Path (Get-LastCleanFile $GameName) -Value @((Get-Date).ToString("o"), $ModeName) -ErrorAction SilentlyContinue
	} catch {
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

$DefaultFont = Scale-Font 9

$IconPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS.ico"

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "NFXS - Cache Cleaner"
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
$TitleLabel.Text = "NFXS | CACHE CLEANER"
$TitleLabel.Font = Scale-Font 12 ([System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = Scale-Point 18 13
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.Text = "FiveM & RedM Cache Cleaner v$AppVersion"
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
$GameCombo.SelectedItem = Get-SavedGame
$ContentPanel.Controls.Add($GameCombo)
$Y += (Scale-Val 34)

$AddressLabel = New-Object System.Windows.Forms.Label
$AddressLabel.Text = $Strings[$CurrentLang].AddressLabel
$AddressLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$AddressLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$AddressLabel.AutoSize = $true
$ContentPanel.Controls.Add($AddressLabel)
$Y += (Scale-Val 20)

$FiveMAddressBox = New-Object System.Windows.Forms.TextBox
$FiveMAddressBox.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$FiveMAddressBox.Size = Scale-Size 344 24
$FiveMAddressBox.Font = $DefaultFont
$FiveMAddressBox.Text = $Games["FiveM"].DefaultAddress
$FiveMAddressBox.Visible = $true
$ContentPanel.Controls.Add($FiveMAddressBox)

$RedMAddressBox = New-Object System.Windows.Forms.TextBox
$RedMAddressBox.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$RedMAddressBox.Size = Scale-Size 344 24
$RedMAddressBox.Font = $DefaultFont
$RedMAddressBox.Text = $Games["RedM"].DefaultAddress
$RedMAddressBox.Visible = $false
$ContentPanel.Controls.Add($RedMAddressBox)
$Y += (Scale-Val 32)

$GameCombo.Add_SelectedIndexChanged({
	$FiveMAddressBox.Visible = ($GameCombo.SelectedItem -eq "FiveM")
	$RedMAddressBox.Visible = ($GameCombo.SelectedItem -eq "RedM")
	$StatusLabel.ForeColor = $Themes[$CurrentTheme].TextSoft
	$StatusLabel.Text = Get-LastCleanText $GameCombo.SelectedItem
	Save-Game $GameCombo.SelectedItem
	Set-Theme $CurrentTheme
	Update-CurrentSizeLabel
})

$ModeGroup = New-Object System.Windows.Forms.GroupBox
$ModeGroup.Text = $Strings[$CurrentLang].ModeGroupTitle
$ModeGroup.Font = $DefaultFont
$ModeGroup.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$ModeGroup.Size = Scale-Size 344 64
$ContentPanel.Controls.Add($ModeGroup)

$CacheRadio = New-Object System.Windows.Forms.RadioButton
$CacheRadio.Text = $Strings[$CurrentLang].CacheRadio
$CacheRadio.Font = $DefaultFont
$CacheRadio.Location = Scale-Point 14 18
$CacheRadio.AutoSize = $true
$CacheRadio.Checked = $true
$ModeGroup.Controls.Add($CacheRadio)

$FullRadio = New-Object System.Windows.Forms.RadioButton
$FullRadio.Text = $Strings[$CurrentLang].FullRadio
$FullRadio.Font = $DefaultFont
$FullRadio.Location = Scale-Point 14 40
$FullRadio.AutoSize = $true
$ModeGroup.Controls.Add($FullRadio)
$Y += (Scale-Val 72)

$CacheLevelTitleLabel = New-Object System.Windows.Forms.Label
$CacheLevelTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$CacheLevelTitleLabel.Size = Scale-Size 344 16
$CacheLevelTitleLabel.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
$ContentPanel.Controls.Add($CacheLevelTitleLabel)
$Y += (Scale-Val 16)

$CacheLevelDescLabel = New-Object System.Windows.Forms.Label
$CacheLevelDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$CacheLevelDescLabel.Size = Scale-SizeMinHeight 344 32 30
$CacheLevelDescLabel.Font = Scale-Font 8
$ContentPanel.Controls.Add($CacheLevelDescLabel)
$Y += (Scale-Val 40) + [Math]::Max(0, $CacheLevelDescLabel.Size.Height - (Scale-Val 32))

function Update-CurrentSizeLabel {
	$ModeName = if ($FullRadio.Checked) { "Tudo" } else { "Cache" }
	$GameName = $GameCombo.SelectedItem
	$TotalBytes = Get-CacheTotalBytes $GameName $ModeName
	$Level = Get-CacheLevel $GameName $TotalBytes
	$CacheLevelTitleLabel.Text = $Level.Title
	$CacheLevelTitleLabel.ForeColor = $Themes[$CurrentTheme][$Level.ColorKey]
	$CacheLevelDescLabel.Text = $Level.Description
	$CacheLevelDescLabel.ForeColor = $Themes[$CurrentTheme].TextSoft
}

$CacheRadio.Add_CheckedChanged({ if ($CacheRadio.Checked) { Update-CurrentSizeLabel } })
$FullRadio.Add_CheckedChanged({ if ($FullRadio.Checked) { Update-CurrentSizeLabel } })

$OpenCheck = New-Object System.Windows.Forms.CheckBox
$OpenCheck.Text = $Strings[$CurrentLang].OpenCheck
$OpenCheck.Font = $DefaultFont
$OpenCheck.Location = New-Object System.Drawing.Point((Scale-Val 19), $Y)
$OpenCheck.AutoSize = $true
$OpenCheck.Checked = $true
$ContentPanel.Controls.Add($OpenCheck)
$Y += (Scale-Val 32)

$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($Y + (Scale-Val 10)))

$BotoesPanel = New-Object System.Windows.Forms.Panel
$BotoesPanel.Dock = "Bottom"
$BotoesPanel.Height = Scale-Val 152

$CleanButton = New-Object System.Windows.Forms.Button
$CleanButton.Text = $Strings[$CurrentLang].CleanButton
$CleanButton.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
$CleanButton.Location = Scale-Point 18 0
$CleanButton.Size = Scale-Size 164 34
$CleanButton.FlatStyle = "Flat"
$CleanButton.FlatAppearance.BorderSize = 0
$CleanButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$BotoesPanel.Controls.Add($CleanButton)

$CloseButton = New-Object System.Windows.Forms.Button
$CloseButton.Text = $Strings[$CurrentLang].CloseButton
$CloseButton.Font = $DefaultFont
$CloseButton.Location = Scale-Point 198 0
$CloseButton.Size = Scale-Size 164 34
$CloseButton.FlatStyle = "Flat"
$CloseButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$CloseButton.Add_Click({ $Form.Close() })
$BotoesPanel.Controls.Add($CloseButton)

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Location = Scale-Point 18 36
$ProgressBar.Size = Scale-Size 344 6
$ProgressBar.Style = "Marquee"
$ProgressBar.MarqueeAnimationSpeed = 30
$ProgressBar.Visible = $false
$BotoesPanel.Controls.Add($ProgressBar)

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

$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Text = Get-LastCleanText $GameCombo.SelectedItem
$StatusLabel.Font = $DefaultFont
$StatusLabel.Location = Scale-Point 18 70
$StatusLabel.Size = Scale-SizeMinHeight 344 72 60
$BotoesPanel.Controls.Add($StatusLabel)

$DiscordUrl = "https://discord.gg/6aD5DqUmEz"

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
$FreeLabel.Text = $Strings[$CurrentLang].FreeLabel
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

function Set-Theme($Name) {
	$T = $Themes[$Name]
	$Script:CurrentTheme = $Name
	$GameAccent = Get-SharedAccentColor $Name

	$Form.BackColor = $T.FormBg
	$HeaderPanel.BackColor = $T.HeaderBg
	$TitleLabel.ForeColor = $T.HeaderTitle
	$SubtitleLabel.ForeColor = $T.HeaderSub
	$UpdateLabel.ForeColor = if ($UpdateAvailable) { $T.Error } else { $T.Success }
	$DescriptionLabel.ForeColor = $T.TextSoft
	$GameLabel.ForeColor = $T.Text
	$GameCombo.BackColor = $T.FieldBg
	$GameCombo.ForeColor = $T.FieldFg
	$AddressLabel.ForeColor = $T.Text
	$FiveMAddressBox.BackColor = $T.FieldBg
	$FiveMAddressBox.ForeColor = $T.Accent
	$RedMAddressBox.BackColor = $T.FieldBg
	$RedMAddressBox.ForeColor = $T.RedMPrimary
	$ModeGroup.ForeColor = $T.TextSoft
	$ModeGroup.BackColor = $T.FormBg
	$CacheRadio.ForeColor = $T.Text
	$CacheRadio.BackColor = $T.FormBg
	$FullRadio.ForeColor = $T.Text
	$FullRadio.BackColor = $T.FormBg
	$OpenCheck.ForeColor = $T.Text
	$OpenCheck.BackColor = $T.FormBg
	$CleanButton.BackColor = $GameAccent
	$CleanButton.ForeColor = $T.AccentTxt
	$CloseButton.BackColor = $T.Btn2Bg
	$CloseButton.ForeColor = $T.Btn2Fg
	$CloseButton.FlatAppearance.BorderColor = $T.Btn2Border
	$StatusLabel.ForeColor = $T.TextSoft
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
	$AddressLabel.Text = $S.AddressLabel
	$ModeGroup.Text = $S.ModeGroupTitle
	$CacheRadio.Text = $S.CacheRadio
	$FullRadio.Text = $S.FullRadio
	$OpenCheck.Text = $S.OpenCheck
	$CleanButton.Text = $S.CleanButton
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

	$StatusLabel.Text = Get-LastCleanText $GameCombo.SelectedItem
	Update-CurrentSizeLabel
}

$CleanButton.Add_Click({
	$S = $Strings[$CurrentLang]
	$CleanButton.Enabled = $false
	$GameName = $GameCombo.SelectedItem
	$Game = $Games[$GameName]
	$ModeName = if ($FullRadio.Checked) { "Tudo" } else { "Cache" }
	$FoldersToClean = $CleanModes[$ModeName]

	if ($ModeName -eq "Tudo") {
		$Result = [System.Windows.Forms.MessageBox]::Show(
			($S.FullCleanWarningFormat -f $GameName),
			$S.FullCleanWarningTitle,
			[System.Windows.Forms.MessageBoxButtons]::YesNo,
			[System.Windows.Forms.MessageBoxIcon]::Information
		)

		if ($Result -ne [System.Windows.Forms.DialogResult]::Yes) {
			$StatusLabel.Text = $S.Cancelled
			$CleanButton.Enabled = $true
			return
		}
	}

	$ProgressBar.Visible = $true
	try {
		$StatusLabel.ForeColor = $Themes[$CurrentTheme].TextSoft
		$StatusLabel.Text = $S.VerifyingFormat -f $GameName
		$Form.Refresh()

		$Running = Get-Process -Name $Game.ProcessName -ErrorAction SilentlyContinue
		if ($Running) {
			$Result = [System.Windows.Forms.MessageBox]::Show(
				($S.GameOpenWarningFormat -f $GameName),
				$S.GameOpenTitle,
				[System.Windows.Forms.MessageBoxButtons]::YesNo,
				[System.Windows.Forms.MessageBoxIcon]::Warning
			)

			if ($Result -eq [System.Windows.Forms.DialogResult]::Yes) {
				$Running | Stop-Process -Force -ErrorAction SilentlyContinue
				Start-Sleep -Seconds 2
			} else {
				$StatusLabel.Text = $S.CancelledCloseGameFormat -f $GameName
				return
			}
		}

		$AnyFound = $false
		$TotalBytes = 0
		$ExistingPaths = @()

		foreach ($Folder in $FoldersToClean) {
			$Path = Join-Path $Game.AppDataPath $Folder
			if (Test-Path $Path) {
				$AnyFound = $true
				$ExistingPaths += $Path
				$FolderSize = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
				if ($FolderSize) {
					$TotalBytes += $FolderSize
				}
			}
		}

		if ($AnyFound) {
			$StatusLabel.Text = $S.FoundSizeFormat -f (Format-Bytes $TotalBytes)
			$Form.Refresh()
			Start-Sleep -Milliseconds 600
		} else {
			$StatusLabel.Text = $S.CleaningNow
			$Form.Refresh()
		}

		$ErrorFound = $false
		foreach ($Path in $ExistingPaths) {
			try {
				Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
			} catch {
				$ErrorFound = $true
			}
		}

		$ProgressBar.Style = "Continuous"
		$ProgressBar.Minimum = 0
		$ProgressBar.Maximum = 100
		for ($i = 0; $i -le 100; $i += 5) {
			$ProgressBar.Value = $i
			$Form.Refresh()
			Start-Sleep -Milliseconds 45
		}

		if ($ErrorFound) {
			$StatusLabel.ForeColor = $Themes[$CurrentTheme].Error
			$StatusLabel.Text = $S.ErrorCleanFormat -f $GameName
		} elseif ($AnyFound) {
			$StatusLabel.ForeColor = $Themes[$CurrentTheme].Success
			$StatusLabel.Text = $S.SuccessCleanFormat -f $GameName, (Format-Bytes $TotalBytes)
			Save-LastCleanDate $GameName $ModeName
		} else {
			$StatusLabel.ForeColor = $Themes[$CurrentTheme].Success
			$StatusLabel.Text = $S.AlreadyCleanFormat -f $GameName
			Save-LastCleanDate $GameName $ModeName
		}

		$Form.Refresh()

		if ($OpenCheck.Checked -and -not $ErrorFound) {
			if (Test-Path $Game.ExePath) {
				try {
					$AddressBox = if ($GameName -eq "FiveM") { $FiveMAddressBox } else { $RedMAddressBox }
					$TypedAddress = $AddressBox.Text.Trim()
					if (Test-ValidAddress $TypedAddress) {
						$LaunchTarget = $Game.ConnectPrefix + $TypedAddress
					} else {
						$LaunchTarget = $Game.Protocol
					}

					Start-Process -FilePath $LaunchTarget -ErrorAction Stop
					$StatusLabel.Text += $S.OpeningFormat -f $GameName
				} catch {
					$StatusLabel.ForeColor = $Themes[$CurrentTheme].Error
					$StatusLabel.Text += $S.ErrorOpenFormat -f $GameName, $_.Exception.Message
				}
			} else {
				$StatusLabel.ForeColor = $Themes[$CurrentTheme].Error
				$StatusLabel.Text += $S.NotInstalledFormat -f $GameName
			}
		}
	} finally {
		$ProgressBar.Visible = $false
		$ProgressBar.Style = "Marquee"
		$CleanButton.Enabled = $true
	}
})

[System.Windows.Forms.Application]::EnableVisualStyles()

$null = $Form.Handle
Set-Theme $CurrentTheme
Update-CurrentSizeLabel

$Form.ShowDialog() | Out-Null
