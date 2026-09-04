
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

$Themes = @{
	"Light" = @{
		FormBg       = [System.Drawing.Color]::FromArgb(244,245,243)
		HeaderBg     = [System.Drawing.Color]::FromArgb(11,13,12)
		HeaderTitle  = [System.Drawing.Color]::FromArgb(242,242,242)
		HeaderSub    = [System.Drawing.Color]::FromArgb(150,155,151)
		Text         = [System.Drawing.Color]::FromArgb(23,26,24)
		TextSoft     = [System.Drawing.Color]::FromArgb(98,104,98)
		Accent       = [System.Drawing.Color]::FromArgb(78,159,85)
		AccentTxt    = [System.Drawing.Color]::FromArgb(255,255,255)
		Btn2Bg       = [System.Drawing.Color]::FromArgb(250,251,250)
		Btn2Fg       = [System.Drawing.Color]::FromArgb(23,26,24)
		Btn2Border   = [System.Drawing.Color]::FromArgb(221,226,222)
		Credit       = [System.Drawing.Color]::FromArgb(168,172,168)
		ToggleBg     = [System.Drawing.Color]::FromArgb(78,159,85)
		ToggleFg     = [System.Drawing.Color]::FromArgb(255,255,255)
		Error        = [System.Drawing.Color]::FromArgb(198,40,40)
		DarkTitlebar = $true
	}
	"Dark" = @{
		FormBg       = [System.Drawing.Color]::FromArgb(11,13,12)
		HeaderBg     = [System.Drawing.Color]::FromArgb(18,22,20)
		HeaderTitle  = [System.Drawing.Color]::FromArgb(242,242,242)
		HeaderSub    = [System.Drawing.Color]::FromArgb(150,155,151)
		Text         = [System.Drawing.Color]::FromArgb(242,242,242)
		TextSoft     = [System.Drawing.Color]::FromArgb(150,155,151)
		Accent       = [System.Drawing.Color]::FromArgb(114,204,114)
		AccentTxt    = [System.Drawing.Color]::FromArgb(11,13,12)
		Btn2Bg       = [System.Drawing.Color]::FromArgb(25,29,26)
		Btn2Fg       = [System.Drawing.Color]::FromArgb(198,201,198)
		Btn2Border   = [System.Drawing.Color]::FromArgb(41,46,42)
		Credit       = [System.Drawing.Color]::FromArgb(90,95,91)
		ToggleBg     = [System.Drawing.Color]::FromArgb(114,204,114)
		ToggleFg     = [System.Drawing.Color]::FromArgb(11,13,12)
		Error        = [System.Drawing.Color]::FromArgb(239,83,80)
		DarkTitlebar = $true
	}
}

$AccentPresets = @(
	[PSCustomObject]@{ Key = "Verde";   Light = [System.Drawing.Color]::FromArgb(78,159,85);   Dark = [System.Drawing.Color]::FromArgb(114,204,114) }
	[PSCustomObject]@{ Key = "Ciano";   Light = [System.Drawing.Color]::FromArgb(20,148,155);  Dark = [System.Drawing.Color]::FromArgb(100,220,225) }
	[PSCustomObject]@{ Key = "Azul";    Light = [System.Drawing.Color]::FromArgb(42,120,200);  Dark = [System.Drawing.Color]::FromArgb(120,175,235) }
	[PSCustomObject]@{ Key = "Indigo";  Light = [System.Drawing.Color]::FromArgb(88,90,196);   Dark = [System.Drawing.Color]::FromArgb(150,155,235) }
	[PSCustomObject]@{ Key = "Roxo";    Light = [System.Drawing.Color]::FromArgb(130,80,190);  Dark = [System.Drawing.Color]::FromArgb(190,145,235) }
	[PSCustomObject]@{ Key = "Rosa";    Light = [System.Drawing.Color]::FromArgb(199,74,140);  Dark = [System.Drawing.Color]::FromArgb(240,150,195) }
	[PSCustomObject]@{ Key = "Laranja"; Light = [System.Drawing.Color]::FromArgb(196,106,32);  Dark = [System.Drawing.Color]::FromArgb(240,165,90) }
)

$Strings = @{
	"pt" = @{
		Subtitle         = "Central de apps NFXS"
		Description      = "Abra qualquer app NFXS instalado a partir daqui."
		NoAppsFoundTitle = "Nenhum app encontrado"
		NoAppsFoundDesc  = "Não encontramos nenhum app NFXS na pasta App ao lado do Hub."
		ThemeButtonLight = "Modo Claro"
		ThemeButtonDark  = "Modo Escuro"
		AccentVerde      = "Verde"
		AccentRosa       = "Rosa"
		AccentRoxo       = "Roxo"
		AccentAzul       = "Azul"
		AccentCiano      = "Ciano"
		AccentIndigo     = "Índigo"
		AccentLaranja    = "Laranja"
		UpdateAvailableFormat = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk         = "Você está com a versão mais recente."
		NewsHeader       = "Obrigado por usar nosso app, acesse:"
		FreeLabel        = "Produto gratuito disponibilizado por NunoFoxs"
	}
	"en" = @{
		Subtitle         = "NFXS App Center"
		Description      = "Open any installed NFXS app from here."
		NoAppsFoundTitle = "No apps found"
		NoAppsFoundDesc  = "We couldn't find any NFXS app in the App folder next to the Hub."
		ThemeButtonLight = "Light Mode"
		ThemeButtonDark  = "Dark Mode"
		AccentVerde      = "Green"
		AccentRosa       = "Pink"
		AccentRoxo       = "Purple"
		AccentAzul       = "Blue"
		AccentCiano      = "Cyan"
		AccentIndigo     = "Indigo"
		AccentLaranja    = "Orange"
		UpdateAvailableFormat = "New version available (v{0}) - click here"
		UpdateOk         = "You have the latest version."
		NewsHeader       = "Thanks for using our app, check out:"
		FreeLabel        = "Free product provided by NunoFoxs"
	}
	"es" = @{
		Subtitle         = "Centro de apps NFXS"
		Description      = "Abre cualquier app NFXS instalada desde aquí."
		NoAppsFoundTitle = "No se encontraron apps"
		NoAppsFoundDesc  = "No encontramos ninguna app NFXS en la carpeta App junto al Hub."
		ThemeButtonLight = "Modo Claro"
		ThemeButtonDark  = "Modo Oscuro"
		AccentVerde      = "Verde"
		AccentRosa       = "Rosa"
		AccentRoxo       = "Morado"
		AccentAzul       = "Azul"
		AccentCiano      = "Cian"
		AccentIndigo     = "Índigo"
		AccentLaranja    = "Naranja"
		UpdateAvailableFormat = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk         = "Tienes la versión más reciente."
		NewsHeader       = "Gracias por usar nuestra app, visita:"
		FreeLabel        = "Producto gratuito ofrecido por NunoFoxs"
	}
	"de" = @{
		Subtitle         = "NFXS App-Zentrale"
		Description      = "Öffne von hier aus jede installierte NFXS-App."
		NoAppsFoundTitle = "Keine Apps gefunden"
		NoAppsFoundDesc  = "Wir konnten keine NFXS-App im App-Ordner neben dem Hub finden."
		ThemeButtonLight = "Heller Modus"
		ThemeButtonDark  = "Dunkler Modus"
		AccentVerde      = "Grün"
		AccentRosa       = "Pink"
		AccentRoxo       = "Lila"
		AccentAzul       = "Blau"
		AccentCiano      = "Türkis"
		AccentIndigo     = "Indigo"
		AccentLaranja    = "Orange"
		UpdateAvailableFormat = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk         = "Du hast die neueste Version."
		NewsHeader       = "Danke, dass du unsere App nutzt, schau vorbei:"
		FreeLabel        = "Kostenloses Produkt bereitgestellt von NunoFoxs"
	}
	"fr" = @{
		Subtitle         = "Centre d'applications NFXS"
		Description      = "Ouvrez ici n'importe quelle application NFXS installée."
		NoAppsFoundTitle = "Aucune application trouvée"
		NoAppsFoundDesc  = "Nous n'avons trouvé aucune application NFXS dans le dossier App à côté du Hub."
		ThemeButtonLight = "Mode Clair"
		ThemeButtonDark  = "Mode Sombre"
		AccentVerde      = "Vert"
		AccentRosa       = "Rose"
		AccentRoxo       = "Violet"
		AccentAzul       = "Bleu"
		AccentCiano      = "Cyan"
		AccentIndigo     = "Indigo"
		AccentLaranja    = "Orange"
		UpdateAvailableFormat = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk         = "Vous avez la dernière version."
		NewsHeader       = "Merci d'utiliser notre application, découvrez :"
		FreeLabel        = "Produit gratuit proposé par NunoFoxs"
	}
}

$SettingsDir  = Join-Path $env:APPDATA "NFXS-Hub"
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

$SharedThemeFile = Join-Path (Join-Path $env:APPDATA "NFXS") "theme.cfg"

function Save-SharedTheme($Name) {
	try {
		$SharedDir = Split-Path $SharedThemeFile -Parent
		if (-not (Test-Path $SharedDir)) {
			New-Item -ItemType Directory -Path $SharedDir -Force | Out-Null
		}
		Set-Content -Path $SharedThemeFile -Value $Name -ErrorAction SilentlyContinue
	} catch {
	}
}

function Get-SharedTheme {
	if (Test-Path $SharedThemeFile) {
		$Saved = (Get-Content $SharedThemeFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -eq "Light" -or $Saved -eq "Dark") {
			return $Saved
		}
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

$SharedSettingsDir = Join-Path $env:APPDATA "NFXS"
$AccentFile = Join-Path $SharedSettingsDir "accent.cfg"
$AccentKeys = @($AccentPresets | ForEach-Object { $_.Key })

function Get-SavedAccentKey {
	if (Test-Path $AccentFile) {
		$Saved = (Get-Content $AccentFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -in $AccentKeys) {
			return $Saved
		}
	}
	return $AccentKeys[0]
}

function Save-AccentKey($Key) {
	try {
		if (-not (Test-Path $SharedSettingsDir)) {
			New-Item -ItemType Directory -Path $SharedSettingsDir -Force | Out-Null
		}
		Set-Content -Path $AccentFile -Value $Key -ErrorAction SilentlyContinue
	} catch {
	}
}

$SharedLangFile = Join-Path $SharedSettingsDir "lang.cfg"

function Save-SharedLang($Code) {
	try {
		if (-not (Test-Path $SharedSettingsDir)) {
			New-Item -ItemType Directory -Path $SharedSettingsDir -Force | Out-Null
		}
		Set-Content -Path $SharedLangFile -Value $Code -ErrorAction SilentlyContinue
	} catch {
	}
}

function Get-SharedLang {
	if (Test-Path $SharedLangFile) {
		$Saved = (Get-Content $SharedLangFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -in @("pt","en","es","de","fr")) {
			return $Saved
		}
	}
	return "pt"
}

$CurrentTheme = "Light"
$CurrentLang  = Get-SharedLang
$CurrentAccentKey = Get-SavedAccentKey
$DefaultFont = Scale-Font 9

function Get-CurrentAccentColor {
	$Preset = $AccentPresets | Where-Object { $_.Key -eq $CurrentAccentKey } | Select-Object -First 1
	if (-not $Preset) { $Preset = $AccentPresets[0] }
	if ($CurrentTheme -eq "Dark") { return $Preset.Dark }
	return $Preset.Light
}

$AppsRootFolder = Split-Path -Parent $PSScriptRoot
$SelfFolderName = Split-Path -Leaf $PSScriptRoot

$AppFiles = @(
	Get-ChildItem -Path $AppsRootFolder -Directory -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -ne $SelfFolderName } |
		ForEach-Object { Get-ChildItem -Path $_.FullName -Filter "NFXS *.bat" -File -ErrorAction SilentlyContinue } |
		Sort-Object BaseName
)

$IconPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS.ico"

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "NFXS - Hub"
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
$HeaderPanel.Height = Scale-Val 96
$Form.Controls.Add($HeaderPanel)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "NFXS | HUB"
$TitleLabel.Font = Scale-Font 12 ([System.Drawing.FontStyle]::Bold)
$TitleLabel.Location = Scale-Point 18 13
$TitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.Text = "$($Strings[$CurrentLang].Subtitle) v$AppVersion"
$SubtitleLabel.UseMnemonic = $false
$SubtitleLabel.Font = $DefaultFont
$SubtitleLabel.Location = Scale-Point 19 37
$SubtitleLabel.AutoSize = $true
$HeaderPanel.Controls.Add($SubtitleLabel)

$LangCodes = @("pt","en","es","de","fr")
$LangNativeNames = @{
	pt = "Português"
	en = "English"
	es = "Español"
	de = "Deutsch"
	fr = "Français"
}
$LangButton = New-Object System.Windows.Forms.Button
$LangButton.Size = Scale-Size 164 24
$LangButton.Location = Scale-Point 18 60
$LangButton.Font = Scale-Font 7.5
$LangButton.Text = $LangNativeNames[$CurrentLang]
$LangButton.FlatStyle = "Flat"
$LangButton.FlatAppearance.BorderSize = 0
$LangButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$HeaderPanel.Controls.Add($LangButton)

$AccentButton = New-Object System.Windows.Forms.Button
$AccentButton.Size = Scale-Size 164 24
$AccentButton.Location = Scale-Point 198 60
$AccentButton.Font = Scale-Font 7.5
$AccentButton.FlatStyle = "Flat"
$AccentButton.FlatAppearance.BorderSize = 0
$AccentButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$HeaderPanel.Controls.Add($AccentButton)

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
$Y += (Scale-Val 40) + [Math]::Max(0, $DescriptionLabel.Size.Height - (Scale-Val 32))

$RunningProcesses = @{}
$ButtonsByName = @{}

function Set-ButtonRunningState($Btn, $IsRunning) {
	$T = $Themes[$CurrentTheme]
	if ($IsRunning) {
		$AccentColor = Get-CurrentAccentColor
		$Btn.BackColor = $AccentColor
		$Btn.ForeColor = $T.AccentTxt
		$Btn.FlatAppearance.BorderColor = $AccentColor
	} else {
		$Btn.BackColor = $T.Btn2Bg
		$Btn.ForeColor = $T.Btn2Fg
		$Btn.FlatAppearance.BorderColor = $T.Btn2Border
	}
}

$NoAppsTitleLabel = New-Object System.Windows.Forms.Label
$NoAppsTitleLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
$NoAppsTitleLabel.Size = Scale-Size 344 18
$NoAppsTitleLabel.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
$NoAppsTitleLabel.Visible = ($AppFiles.Count -eq 0)
$ContentPanel.Controls.Add($NoAppsTitleLabel)

$NoAppsDescLabel = New-Object System.Windows.Forms.Label
$NoAppsDescLabel.Location = New-Object System.Drawing.Point((Scale-Val 18), ($Y + (Scale-Val 20)))
$NoAppsDescLabel.Size = Scale-SizeMinHeight 344 40 36
$NoAppsDescLabel.Font = $DefaultFont
$NoAppsDescLabel.Visible = ($AppFiles.Count -eq 0)
$ContentPanel.Controls.Add($NoAppsDescLabel)

foreach ($App in $AppFiles) {
	$Name = $App.BaseName -replace '^NFXS\s+', ''
	$PsPath = $App.FullName -replace '\.bat$', '.ps1'
	$Btn = New-Object System.Windows.Forms.Button
	$Btn.Text = $Name
	$Btn.Size = Scale-Size 344 38
	$Btn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$Btn.FlatStyle = "Flat"
	$Btn.FlatAppearance.BorderSize = 1
	$Btn.Font = Scale-Font 9.5
	$Btn.TextAlign = "MiddleLeft"
	$Btn.Padding = New-Object System.Windows.Forms.Padding(14,0,0,0)
	$Btn.Cursor = [System.Windows.Forms.Cursors]::Hand
	$ContentPanel.Controls.Add($Btn)
	$ButtonsByName[$Name] = $Btn

	$Btn.Add_Click({
		$Key = $Name
		$Existing = $RunningProcesses[$Key]
		if ($Existing -and -not $Existing.HasExited) {
			try { $Existing.CloseMainWindow() | Out-Null } catch {}
		} else {
			$Psi = New-Object System.Diagnostics.ProcessStartInfo
			$Psi.FileName = "powershell.exe"
			$Psi.Arguments = "-WindowStyle Minimized -NoProfile -ExecutionPolicy Bypass -File `"$PsPath`""
			$Psi.WorkingDirectory = Split-Path $PsPath
			$Proc = [System.Diagnostics.Process]::Start($Psi)
			$RunningProcesses[$Key] = $Proc
			Set-ButtonRunningState $Btn $true
		}
	}.GetNewClosure())

	$Y += Scale-Val 46
}

if ($AppFiles.Count -eq 0) {
	$Y += Scale-Val 76
}

$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($Y + (Scale-Val 10)))

$PollTimer = New-Object System.Windows.Forms.Timer
$PollTimer.Interval = 700
$PollTimer.Add_Tick({
	foreach ($Key in @($RunningProcesses.Keys)) {
		$Proc = $RunningProcesses[$Key]
		if ($Proc.HasExited) {
			Set-ButtonRunningState $ButtonsByName[$Key] $false
			$RunningProcesses.Remove($Key)
		}
	}
})
$PollTimer.Start()

$InfoPanel = New-Object System.Windows.Forms.Panel
$InfoPanel.Dock = "Bottom"
$InfoPanel.Height = Scale-Val 40

$UpdateLabel = New-Object System.Windows.Forms.Label
$UpdateLabel.Location = Scale-Point 18 10
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
$InfoPanel.Controls.Add($UpdateLabel)

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

$Form.Controls.Add($InfoPanel)
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

function Set-Theme($Name) {
	$T = $Themes[$Name]
	$Script:CurrentTheme = $Name
	$AccentColor = Get-CurrentAccentColor

	$Form.BackColor = $T.FormBg
	$HeaderPanel.BackColor = $T.HeaderBg
	$ContentPanel.BackColor = $T.FormBg
	$InfoPanel.BackColor = $T.FormBg
	$BannerPanel.BackColor = $T.FormBg
	$DiscordPanel.BackColor = $T.FormBg
	$TitleLabel.ForeColor = $T.HeaderTitle
	$SubtitleLabel.ForeColor = $T.HeaderSub
	$UpdateLabel.ForeColor = if ($UpdateAvailable) { $T.Error } else { $AccentColor }
	$DescriptionLabel.ForeColor = $T.TextSoft
	$NoAppsTitleLabel.ForeColor = $T.TextSoft
	$NoAppsDescLabel.ForeColor = $T.TextSoft
	$NewsHeaderLabel.ForeColor = $T.TextSoft
	$NewsLabel.ForeColor = $AccentColor
	$FreeLabel.ForeColor = $T.Credit

	foreach ($Key in $ButtonsByName.Keys) {
		$IsRunning = $RunningProcesses.ContainsKey($Key) -and -not $RunningProcesses[$Key].HasExited
		Set-ButtonRunningState $ButtonsByName[$Key] $IsRunning
	}

	$LangButton.BackColor = $AccentColor
	$LangButton.ForeColor = $T.ToggleFg
	$AccentButton.BackColor = $AccentColor
	$AccentButton.ForeColor = $T.ToggleFg

	if ($Form.IsHandleCreated) {
		$DarkModeValue = if ($T.DarkTitlebar) { 1 } else { 0 }
		[void][NFX.Dwm]::DwmSetWindowAttribute($Form.Handle,20,[ref]$DarkModeValue,4)
		$Form.Refresh()
	}
}

function Apply-Language($Lang) {
	$Script:CurrentLang = $Lang
	$S = $Strings[$Lang]

	$LangButton.Text = $LangNativeNames[$Lang]
	$AccentButton.Text = $S.("Accent" + $CurrentAccentKey)
	$SubtitleLabel.Text = "$($S.Subtitle) v$AppVersion"
	$DescriptionLabel.Text = $S.Description
	$NoAppsTitleLabel.Text = $S.NoAppsFoundTitle
	$NoAppsDescLabel.Text = $S.NoAppsFoundDesc
	$FreeLabel.Text = $S.FreeLabel

	if ($UpdateAvailable) {
		$UpdateLabel.Text = $S.UpdateAvailableFormat -f $LatestVersion
	} else {
		$UpdateLabel.Text = $S.UpdateOk
	}
	if ($News) {
		$NewsHeaderLabel.Text = $S.NewsHeader
	}

}

$AccentButton.Add_Click({
	$CurrentIndex = $AccentKeys.IndexOf($CurrentAccentKey)
	$Script:CurrentAccentKey = $AccentKeys[($CurrentIndex + 1) % $AccentKeys.Count]
	Save-AccentKey $CurrentAccentKey
	$AccentButton.Text = $Strings[$CurrentLang].("Accent" + $CurrentAccentKey)
	Set-Theme $CurrentTheme
})

$LangButton.Add_Click({
	$CurrentIndex = $LangCodes.IndexOf($CurrentLang)
	$NextLang = $LangCodes[($CurrentIndex + 1) % $LangCodes.Count]
	Apply-Language $NextLang
	Save-SharedLang $NextLang
})

[System.Windows.Forms.Application]::EnableVisualStyles()

$null = $Form.Handle
Set-Theme $CurrentTheme
Apply-Language $CurrentLang

$Form.Add_Shown({
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	$ContentPanel.BeginInvoke([Action]{
		$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	}) | Out-Null
})

$Form.ShowDialog() | Out-Null
