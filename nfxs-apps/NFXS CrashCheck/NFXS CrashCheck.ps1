
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
	if (-not $Url) { return $null }
	try {
		$Response = Invoke-RestMethod -Uri $Url -TimeoutSec 3 -ErrorAction Stop
		$Value = ([string]$Response -split "`n" | Select-Object -First 1).Trim()
		if ($Value) { return $Value }
	} catch {
	}
	return $null
}

function Get-RemoteNews($Url) {
	if (-not $Url) { return $null }
	try {
		$Response = Invoke-RestMethod -Uri $Url -TimeoutSec 3 -ErrorAction Stop
		$Lines = ([string]$Response -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
		if ($Lines.Count -ge 1) {
			return [PSCustomObject]@{ Text = $Lines[0]; Link = if ($Lines.Count -ge 2) { $Lines[1] } else { $null } }
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

$KnownPatternsUrl = ""

function Get-RemoteKnownPatterns($Url) {
	if (-not $Url) { return @() }
	try {
		$Response = Invoke-RestMethod -Uri $Url -TimeoutSec 3 -ErrorAction Stop
		$Parsed = $Response | ConvertFrom-Json -ErrorAction Stop
		$Result = @()
		foreach ($P in $Parsed) {
			if ($P.Match -and $P.Label) {
				$Categoria = if ($P.Categoria) { [string]$P.Categoria } else { "Nao foi possivel identificar" }
				$Lado = if ($P.Lado) { [string]$P.Lado } else { "Indeterminado" }
				$Result += @{ Match = [string]$P.Match; Label = [string]$P.Label; Categoria = $Categoria; Lado = $Lado }
			}
		}
		return $Result
	} catch {
		return @()
	}
}

$LocalKnownPatterns = @(
	@{ Match = 'VK_ERROR_OUT_OF_DEVICE_MEMORY|Failed to allocate memory for Vulkan'; Label = "Falha de memoria de video (Vulkan/GPU) - indicio de VRAM insuficiente ou driver de video desatualizado, nao relacionado a script/recurso"; Categoria = "Problema de video / placa grafica"; Lado = "Cliente" }
	@{ Match = 'should be launched directly from the shell'; Label = "Nao e' um crash de gameplay - o executavel foi aberto de um jeito que o FiveM/RedM nao reconhece como inicializacao valida (ex: clique direto no .exe em vez do atalho oficial)"; Categoria = "Forma incorreta de abrir o jogo"; Lado = "Cliente" }
)
$KnownNativePatterns = @($LocalKnownPatterns) + @(Get-RemoteKnownPatterns $KnownPatternsUrl)

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
		RowBg        = [System.Drawing.Color]::FromArgb(255,255,255)
		RowBorder    = [System.Drawing.Color]::FromArgb(221,226,222)
		Success      = [System.Drawing.Color]::FromArgb(57,118,63)
		Warning      = [System.Drawing.Color]::FromArgb(184,150,10)
		Alert        = [System.Drawing.Color]::FromArgb(194,101,15)
		Error        = [System.Drawing.Color]::FromArgb(198,40,40)
		Credit       = [System.Drawing.Color]::FromArgb(168,172,168)
		ToggleFg     = [System.Drawing.Color]::FromArgb(255,255,255)
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
		RowBg        = [System.Drawing.Color]::FromArgb(18,22,20)
		RowBorder    = [System.Drawing.Color]::FromArgb(41,46,42)
		Success      = [System.Drawing.Color]::FromArgb(139,221,139)
		Warning      = [System.Drawing.Color]::FromArgb(232,212,77)
		Alert        = [System.Drawing.Color]::FromArgb(232,150,60)
		Error        = [System.Drawing.Color]::FromArgb(239,83,80)
		Credit       = [System.Drawing.Color]::FromArgb(90,95,91)
		ToggleFg     = [System.Drawing.Color]::FromArgb(11,13,12)
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
$SharedAccentFile = Join-Path $env:APPDATA "NFXS\accent.cfg"

function Get-SharedAccentColor($ThemeName) {
	$Key = "Verde"
	if (Test-Path $SharedAccentFile) {
		$Saved = (Get-Content $SharedAccentFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -in @($AccentPresets | ForEach-Object { $_.Key })) { $Key = $Saved }
	}
	$Preset = $AccentPresets | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
	if ($ThemeName -eq "Dark") { return $Preset.Dark }
	return $Preset.Light
}

$SettingsDir  = Join-Path $env:APPDATA "NFXS-CrashCheck"
$SettingsFile = Join-Path $SettingsDir "theme.cfg"

function Get-SavedTheme {
	if (Test-Path $SettingsFile) {
		$Saved = (Get-Content $SettingsFile -ErrorAction SilentlyContinue | Select-Object -First 1)
		if ($Saved -eq "Light" -or $Saved -eq "Dark") { return $Saved }
	}
	return "Dark"
}
function Save-Theme($Name) {
	try {
		if (-not (Test-Path $SettingsDir)) { New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null }
		Set-Content -Path $SettingsFile -Value $Name -ErrorAction SilentlyContinue
	} catch {
	}
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
		if ($Saved -in @("pt","en","es","de","fr")) { return $Saved }
	}
	return "pt"
}
function Save-Lang($Code) {
	try {
		if (-not (Test-Path $SettingsDir)) { New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null }
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

$CurrentTheme = "Light"
$CurrentLang  = Get-SharedLang
$DefaultFont = Scale-Font 9

$Strings = @{
	"pt" = @{
		Description        = "Encontra e analisa relatórios de crash do FiveM/RedM automaticamente - sem precisar procurar arquivo nenhum."
		ListHeader          = "Relatórios de crash encontrados"
		NoReportsTitle      = "Nenhum crash encontrado"
		NoReportsDesc       = "Não encontramos relatórios de crash em FiveM ou RedM nesta máquina."
		GroupToday          = "Hoje"
		GroupYesterday      = "Ontem"
		MostRecentBadge     = "Crash mais recente"
		MinutesAgoFormat    = "Há {0} minutos"
		MinuteAgoSingular   = "Há 1 minuto"
		HoursAgoFormat      = "Há {0} horas"
		HourAgoSingular     = "Há 1 hora"
		DaysAgoFormat       = "Há {0} dias"
		DayAgoSingular      = "Há 1 dia"
		CrashReportLabel    = "Crash report"
		BackButton          = "Voltar à lista"
		ResultTitleHigh     = "Possível causa identificada"
		ResultTitleMedium   = "Possível problema identificado"
		ResultTitleLow      = "Não foi possível determinar a causa"
		ResourceLabel       = "Recurso relacionado"
		ResourceNone        = "Não identificado"
		TypeLabel           = "Tipo"
		TypeAsset           = "Erro de recurso/asset"
		TypeRecognized      = "Categoria conhecida"
		TypeUnknown         = "Não determinado"
		ConfidenceLabel     = "Confiança"
		ConfidenceHigh      = "Alta"
		ConfidenceMedium    = "Média"
		ConfidenceLow       = "Não determinada"
		ProblemsFoundHeader = "Foram encontrados estes tipos de problema:"
		NoProblemsFound     = "Não foi possível identificar nenhum tipo de problema específico."
		CrashMomentHeader   = "O crash aconteceu neste momento:"
		PlayingFormat       = "jogando {0}"
		LadoCliente         = "Seu PC"
		LadoServidor        = "Servidor"
		LadoIndeterminado   = "Não determinado"
		EvidenceHeader      = "Evidências"
		DetailsButton       = "Ver detalhes técnicos"
		HideDetailsButton   = "Ocultar detalhes técnicos"
		CopyButton          = "Copiar relatório"
		CopiedFeedback      = "Copiado!"
		ExportButton        = "Exportar arquivos (.zip)"
		ExportSuccessTitle  = "Exportação concluída"
		ExportSuccessFormat = "Arquivo salvo em:`n{0}`n`nDeseja abrir a pasta onde foi salvo?"
		ExportErrorText     = "Não foi possível criar o arquivo .zip. Verifique se há espaço em disco e tente novamente."
		RefreshButton       = "Verificar novamente"
		CloseButton         = "Fechar"
		ThemeButtonLight    = "Modo Claro"
		ThemeButtonDark     = "Modo Escuro"
		AccentVerde         = "Verde"
		AccentRosa          = "Rosa"
		AccentRoxo          = "Roxo"
		AccentAzul          = "Azul"
		AccentCiano         = "Ciano"
		AccentIndigo        = "Índigo"
		AccentLaranja       = "Laranja"
		UpdateAvailableFormat = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk            = "Você está com a versão mais recente."
		NewsHeader          = "Obrigado por usar nosso app, acesse:"
		FreeLabel           = "Produto gratuito disponibilizado por NunoFoxs"
		ReportGame          = "Jogo"
		ReportDate          = "Data do crash"
		ReportResult        = "Resultado"
		ReportFile          = "Arquivo"
		ReportLine          = "Linha"
		ReportNote          = "Observação"
		ReportFooter        = "Relatório gerado pelo NFXS CrashCheck."
		ReportTitle         = "Relatório de diagnóstico"
		NoteHigh            = "A análise encontrou evidências associadas ao recurso indicado, mas isso não confirma isoladamente que ele seja a causa definitiva do crash."
		NoteMedium          = "A análise encontrou indícios, mas não uma confirmação direta - use essas informações como ponto de partida, não como veredito final."
		NoteLow             = "A análise não conseguiu identificar uma causa específica com segurança. Os dados técnicos brutos (stack trace, hash) estão disponíveis em Detalhes técnicos, caso um desenvolvedor queira investigar mais a fundo."
		TechFilePath        = "Arquivo de dump"
		TechSizeKB          = "Tamanho"
		TechLogPath         = "Log de sessão correlacionado"
		TechLogDelta        = "Diferença de horário"
		TechHash            = "Hash do crash"
		TechStackTrace      = "Stack trace bruto"
		TechScriptErrors    = "Erros de script próximos ao crash"
		TechNone            = "Não disponível"
	}
	"en" = @{
		Description        = "Automatically finds and analyzes FiveM/RedM crash reports - no need to hunt for any file."
		ListHeader          = "Crash reports found"
		NoReportsTitle      = "No crashes found"
		NoReportsDesc       = "We couldn't find any crash reports for FiveM or RedM on this machine."
		GroupToday          = "Today"
		GroupYesterday      = "Yesterday"
		MostRecentBadge     = "Most recent crash"
		MinutesAgoFormat    = "{0} minutes ago"
		MinuteAgoSingular   = "1 minute ago"
		HoursAgoFormat      = "{0} hours ago"
		HourAgoSingular     = "1 hour ago"
		DaysAgoFormat       = "{0} days ago"
		DayAgoSingular      = "1 day ago"
		CrashReportLabel    = "Crash report"
		BackButton          = "Back to list"
		ResultTitleHigh     = "Likely cause identified"
		ResultTitleMedium   = "Possible issue identified"
		ResultTitleLow      = "Couldn't determine the cause"
		ResourceLabel       = "Related resource"
		ResourceNone        = "Not identified"
		TypeLabel           = "Type"
		TypeAsset           = "Resource/asset error"
		TypeRecognized      = "Known category"
		TypeUnknown         = "Undetermined"
		ConfidenceLabel     = "Confidence"
		ConfidenceHigh      = "High"
		ConfidenceMedium    = "Medium"
		ConfidenceLow       = "Undetermined"
		ProblemsFoundHeader = "These types of problem were found:"
		NoProblemsFound     = "It wasn't possible to identify any specific type of problem."
		CrashMomentHeader   = "The crash happened at this moment:"
		PlayingFormat       = "playing {0}"
		LadoCliente         = "Your PC"
		LadoServidor        = "Server"
		LadoIndeterminado   = "Undetermined"
		EvidenceHeader      = "Evidence"
		DetailsButton       = "View technical details"
		HideDetailsButton   = "Hide technical details"
		CopyButton          = "Copy report"
		CopiedFeedback      = "Copied!"
		ExportButton        = "Export files (.zip)"
		ExportSuccessTitle  = "Export complete"
		ExportSuccessFormat = "File saved to:`n{0}`n`nDo you want to open the folder where it was saved?"
		ExportErrorText     = "Couldn't create the .zip file. Check your disk space and try again."
		RefreshButton       = "Check again"
		CloseButton         = "Close"
		ThemeButtonLight    = "Light Mode"
		ThemeButtonDark     = "Dark Mode"
		AccentVerde         = "Green"
		AccentRosa          = "Pink"
		AccentRoxo          = "Purple"
		AccentAzul          = "Blue"
		AccentCiano         = "Cyan"
		AccentIndigo        = "Indigo"
		AccentLaranja       = "Orange"
		UpdateAvailableFormat = "New version available (v{0}) - click here"
		UpdateOk            = "You have the latest version."
		NewsHeader          = "Thanks for using our app, check out:"
		FreeLabel           = "Free product provided by NunoFoxs"
		ReportGame          = "Game"
		ReportDate          = "Crash date"
		ReportResult        = "Result"
		ReportFile          = "File"
		ReportLine          = "Line"
		ReportNote          = "Note"
		ReportFooter        = "Report generated by NFXS CrashCheck."
		ReportTitle         = "Diagnostic report"
		NoteHigh            = "The analysis found evidence associated with the indicated resource, but this alone doesn't confirm it as the definitive cause of the crash."
		NoteMedium          = "The analysis found indications, but not a direct confirmation - use this as a starting point, not a final verdict."
		NoteLow             = "The analysis couldn't reliably identify a specific cause. Raw technical data (stack trace, hash) is available under Technical details in case a developer wants to dig deeper."
		TechFilePath        = "Dump file"
		TechSizeKB          = "Size"
		TechLogPath         = "Correlated session log"
		TechLogDelta        = "Time difference"
		TechHash            = "Crash hash"
		TechStackTrace      = "Raw stack trace"
		TechScriptErrors    = "Script errors near the crash"
		TechNone            = "Not available"
	}
	"es" = @{
		Description        = "Encuentra y analiza automáticamente reportes de crash de FiveM/RedM - sin buscar ningún archivo a mano."
		ListHeader          = "Reportes de crash encontrados"
		NoReportsTitle      = "No se encontraron crashes"
		NoReportsDesc       = "No encontramos reportes de crash de FiveM o RedM en esta máquina."
		GroupToday          = "Hoy"
		GroupYesterday      = "Ayer"
		MostRecentBadge     = "Crash más reciente"
		MinutesAgoFormat    = "Hace {0} minutos"
		MinuteAgoSingular   = "Hace 1 minuto"
		HoursAgoFormat      = "Hace {0} horas"
		HourAgoSingular     = "Hace 1 hora"
		DaysAgoFormat       = "Hace {0} días"
		DayAgoSingular      = "Hace 1 día"
		CrashReportLabel    = "Reporte de crash"
		BackButton          = "Volver a la lista"
		ResultTitleHigh     = "Posible causa identificada"
		ResultTitleMedium   = "Posible problema identificado"
		ResultTitleLow      = "No se pudo determinar la causa"
		ResourceLabel       = "Recurso relacionado"
		ResourceNone        = "No identificado"
		TypeLabel           = "Tipo"
		TypeAsset           = "Error de recurso/asset"
		TypeRecognized      = "Categoría conocida"
		TypeUnknown         = "No determinado"
		ConfidenceLabel     = "Confianza"
		ConfidenceHigh      = "Alta"
		ConfidenceMedium    = "Media"
		ConfidenceLow       = "No determinada"
		ProblemsFoundHeader = "Se encontraron estos tipos de problema:"
		NoProblemsFound     = "No fue posible identificar ningún tipo de problema específico."
		CrashMomentHeader   = "El crash ocurrió en este momento:"
		PlayingFormat       = "jugando {0}"
		LadoCliente         = "Tu PC"
		LadoServidor        = "Servidor"
		LadoIndeterminado   = "No determinado"
		EvidenceHeader      = "Evidencias"
		DetailsButton       = "Ver detalles técnicos"
		HideDetailsButton   = "Ocultar detalles técnicos"
		CopyButton          = "Copiar reporte"
		CopiedFeedback      = "¡Copiado!"
		ExportButton        = "Exportar archivos (.zip)"
		ExportSuccessTitle  = "Exportación completada"
		ExportSuccessFormat = "Archivo guardado en:`n{0}`n`n¿Quieres abrir la carpeta donde se guardó?"
		ExportErrorText     = "No fue posible crear el archivo .zip. Verifica el espacio en disco e intenta de nuevo."
		RefreshButton       = "Verificar de nuevo"
		CloseButton         = "Cerrar"
		ThemeButtonLight    = "Modo Claro"
		ThemeButtonDark     = "Modo Oscuro"
		AccentVerde         = "Verde"
		AccentRosa          = "Rosa"
		AccentRoxo          = "Morado"
		AccentAzul          = "Azul"
		AccentCiano         = "Cian"
		AccentIndigo        = "Índigo"
		AccentLaranja       = "Naranja"
		UpdateAvailableFormat = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk            = "Tienes la versión más reciente."
		NewsHeader          = "Gracias por usar nuestra app, visita:"
		FreeLabel           = "Producto gratuito ofrecido por NunoFoxs"
		ReportGame          = "Juego"
		ReportDate          = "Fecha del crash"
		ReportResult        = "Resultado"
		ReportFile          = "Archivo"
		ReportLine          = "Línea"
		ReportNote          = "Observación"
		ReportFooter        = "Reporte generado por NFXS CrashCheck."
		ReportTitle         = "Reporte de diagnóstico"
		NoteHigh            = "El análisis encontró evidencias asociadas al recurso indicado, pero esto no confirma por sí solo que sea la causa definitiva del crash."
		NoteMedium          = "El análisis encontró indicios, pero no una confirmación directa - úsalo como punto de partida, no como veredicto final."
		NoteLow             = "El análisis no pudo identificar una causa específica con seguridad. Los datos técnicos brutos (stack trace, hash) están disponibles en Detalles técnicos, por si un desarrollador quiere investigar más a fondo."
		TechFilePath        = "Archivo de dump"
		TechSizeKB          = "Tamaño"
		TechLogPath         = "Log de sesión correlacionado"
		TechLogDelta        = "Diferencia de horario"
		TechHash            = "Hash del crash"
		TechStackTrace      = "Stack trace bruto"
		TechScriptErrors    = "Errores de script cerca del crash"
		TechNone            = "No disponible"
	}
	"de" = @{
		Description        = "Findet und analysiert FiveM/RedM-Absturzberichte automatisch - ohne dass du selbst nach Dateien suchen musst."
		ListHeader          = "Gefundene Absturzberichte"
		NoReportsTitle      = "Keine Abstürze gefunden"
		NoReportsDesc       = "Wir konnten keine Absturzberichte für FiveM oder RedM auf diesem Computer finden."
		GroupToday          = "Heute"
		GroupYesterday      = "Gestern"
		MostRecentBadge     = "Neuester Absturz"
		MinutesAgoFormat    = "Vor {0} Minuten"
		MinuteAgoSingular   = "Vor 1 Minute"
		HoursAgoFormat      = "Vor {0} Stunden"
		HourAgoSingular     = "Vor 1 Stunde"
		DaysAgoFormat       = "Vor {0} Tagen"
		DayAgoSingular      = "Vor 1 Tag"
		CrashReportLabel    = "Absturzbericht"
		BackButton          = "Zurück zur Liste"
		ResultTitleHigh     = "Wahrscheinliche Ursache identifiziert"
		ResultTitleMedium   = "Mögliches Problem identifiziert"
		ResultTitleLow      = "Ursache konnte nicht bestimmt werden"
		ResourceLabel       = "Zugehörige Ressource"
		ResourceNone        = "Nicht identifiziert"
		TypeLabel           = "Typ"
		TypeAsset           = "Ressourcen-/Asset-Fehler"
		TypeRecognized      = "Bekannte Kategorie"
		TypeUnknown         = "Unbestimmt"
		ConfidenceLabel     = "Vertrauen"
		ConfidenceHigh      = "Hoch"
		ConfidenceMedium    = "Mittel"
		ConfidenceLow       = "Unbestimmt"
		ProblemsFoundHeader = "Folgende Problemarten wurden gefunden:"
		NoProblemsFound     = "Es konnte keine bestimmte Problemart identifiziert werden."
		CrashMomentHeader   = "Der Absturz ist in diesem Moment passiert:"
		PlayingFormat       = "beim Spielen von {0}"
		LadoCliente         = "Dein PC"
		LadoServidor        = "Server"
		LadoIndeterminado   = "Unbestimmt"
		EvidenceHeader      = "Hinweise"
		DetailsButton       = "Technische Details anzeigen"
		HideDetailsButton   = "Technische Details ausblenden"
		CopyButton          = "Bericht kopieren"
		CopiedFeedback      = "Kopiert!"
		ExportButton        = "Dateien exportieren (.zip)"
		ExportSuccessTitle  = "Export abgeschlossen"
		ExportSuccessFormat = "Datei gespeichert unter:`n{0}`n`nMöchtest du den Ordner öffnen, in dem sie gespeichert wurde?"
		ExportErrorText     = "Die .zip-Datei konnte nicht erstellt werden. Prüfe den Speicherplatz und versuche es erneut."
		RefreshButton       = "Erneut prüfen"
		CloseButton         = "Schließen"
		ThemeButtonLight    = "Heller Modus"
		ThemeButtonDark     = "Dunkler Modus"
		AccentVerde         = "Grün"
		AccentRosa          = "Pink"
		AccentRoxo          = "Lila"
		AccentAzul          = "Blau"
		AccentCiano         = "Türkis"
		AccentIndigo        = "Indigo"
		AccentLaranja       = "Orange"
		UpdateAvailableFormat = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk            = "Du hast die neueste Version."
		NewsHeader          = "Danke, dass du unsere App nutzt, schau vorbei:"
		FreeLabel           = "Kostenloses Produkt bereitgestellt von NunoFoxs"
		ReportGame          = "Spiel"
		ReportDate          = "Absturzdatum"
		ReportResult        = "Ergebnis"
		ReportFile          = "Datei"
		ReportLine          = "Zeile"
		ReportNote          = "Hinweis"
		ReportFooter        = "Bericht erstellt von NFXS CrashCheck."
		ReportTitle         = "Diagnosebericht"
		NoteHigh            = "Die Analyse fand Hinweise auf die angegebene Ressource, das bestätigt allein aber nicht, dass sie die endgültige Ursache des Absturzes ist."
		NoteMedium          = "Die Analyse fand Hinweise, aber keine direkte Bestätigung - nutze das als Ausgangspunkt, nicht als endgültiges Urteil."
		NoteLow             = "Die Analyse konnte keine spezifische Ursache mit Sicherheit feststellen. Die rohen technischen Daten (Stack Trace, Hash) sind unter Technische Details verfügbar, falls ein Entwickler tiefer nachforschen möchte."
		TechFilePath        = "Dump-Datei"
		TechSizeKB          = "Größe"
		TechLogPath         = "Zugeordnetes Sitzungsprotokoll"
		TechLogDelta        = "Zeitunterschied"
		TechHash            = "Absturz-Hash"
		TechStackTrace      = "Roher Stack Trace"
		TechScriptErrors    = "Skriptfehler nahe des Absturzes"
		TechNone            = "Nicht verfügbar"
	}
	"fr" = @{
		Description        = "Trouve et analyse automatiquement les rapports de crash FiveM/RedM - sans avoir à chercher le moindre fichier."
		ListHeader          = "Rapports de crash trouvés"
		NoReportsTitle      = "Aucun crash trouvé"
		NoReportsDesc       = "Nous n'avons trouvé aucun rapport de crash pour FiveM ou RedM sur cette machine."
		GroupToday          = "Aujourd'hui"
		GroupYesterday      = "Hier"
		MostRecentBadge     = "Crash le plus récent"
		MinutesAgoFormat    = "Il y a {0} minutes"
		MinuteAgoSingular   = "Il y a 1 minute"
		HoursAgoFormat      = "Il y a {0} heures"
		HourAgoSingular     = "Il y a 1 heure"
		DaysAgoFormat       = "Il y a {0} jours"
		DayAgoSingular      = "Il y a 1 jour"
		CrashReportLabel    = "Rapport de crash"
		BackButton          = "Retour à la liste"
		ResultTitleHigh     = "Cause probable identifiée"
		ResultTitleMedium   = "Problème possible identifié"
		ResultTitleLow      = "Impossible de déterminer la cause"
		ResourceLabel       = "Ressource associée"
		ResourceNone        = "Non identifiée"
		TypeLabel           = "Type"
		TypeAsset           = "Erreur de ressource/asset"
		TypeRecognized      = "Catégorie connue"
		TypeUnknown         = "Indéterminé"
		ConfidenceLabel     = "Confiance"
		ConfidenceHigh      = "Élevée"
		ConfidenceMedium    = "Moyenne"
		ConfidenceLow       = "Indéterminée"
		ProblemsFoundHeader = "Ces types de problème ont été trouvés :"
		NoProblemsFound     = "Il n'a pas été possible d'identifier un type de problème spécifique."
		CrashMomentHeader   = "Le crash s'est produit à ce moment :"
		PlayingFormat       = "en jouant à {0}"
		LadoCliente         = "Votre PC"
		LadoServidor        = "Serveur"
		LadoIndeterminado   = "Indéterminé"
		EvidenceHeader      = "Preuves"
		DetailsButton       = "Voir les détails techniques"
		HideDetailsButton   = "Masquer les détails techniques"
		CopyButton          = "Copier le rapport"
		CopiedFeedback      = "Copié !"
		ExportButton        = "Exporter les fichiers (.zip)"
		ExportSuccessTitle  = "Exportation terminée"
		ExportSuccessFormat = "Fichier enregistré dans :`n{0}`n`nVoulez-vous ouvrir le dossier où il a été enregistré ?"
		ExportErrorText     = "Impossible de créer le fichier .zip. Vérifiez l'espace disque et réessayez."
		RefreshButton       = "Vérifier à nouveau"
		CloseButton         = "Fermer"
		ThemeButtonLight    = "Mode Clair"
		ThemeButtonDark     = "Mode Sombre"
		AccentVerde         = "Vert"
		AccentRosa          = "Rose"
		AccentRoxo          = "Violet"
		AccentAzul          = "Bleu"
		AccentCiano         = "Cyan"
		AccentIndigo        = "Indigo"
		AccentLaranja       = "Orange"
		UpdateAvailableFormat = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk            = "Vous avez la dernière version."
		NewsHeader          = "Merci d'utiliser notre application, découvrez :"
		FreeLabel           = "Produit gratuit proposé par NunoFoxs"
		ReportGame          = "Jeu"
		ReportDate          = "Date du crash"
		ReportResult        = "Résultat"
		ReportFile          = "Fichier"
		ReportLine          = "Ligne"
		ReportNote          = "Remarque"
		ReportFooter        = "Rapport généré par NFXS CrashCheck."
		ReportTitle         = "Rapport de diagnostic"
		NoteHigh            = "L'analyse a trouvé des preuves associées à la ressource indiquée, mais cela ne confirme pas à lui seul qu'elle soit la cause définitive du crash."
		NoteMedium          = "L'analyse a trouvé des indices, mais pas de confirmation directe - utilisez ceci comme point de départ, pas comme verdict final."
		NoteLow             = "L'analyse n'a pas pu identifier une cause spécifique avec certitude. Les données techniques brutes (stack trace, hash) sont disponibles dans Détails techniques, si un développeur souhaite approfondir."
		TechFilePath        = "Fichier de dump"
		TechSizeKB          = "Taille"
		TechLogPath         = "Journal de session corrélé"
		TechLogDelta        = "Différence de temps"
		TechHash            = "Hash du crash"
		TechStackTrace      = "Stack trace brut"
		TechScriptErrors    = "Erreurs de script proches du crash"
		TechNone            = "Non disponible"
	}
}

function Find-CrashReports {
	$Games = @(
		@{ Name = "FiveM"; Root = Join-Path $env:LOCALAPPDATA "FiveM\FiveM.app" }
		@{ Name = "RedM";  Root = Join-Path $env:LOCALAPPDATA "RedM\RedM.app" }
	)
	$Results = @()
	foreach ($Game in $Games) {
		$CrashDir = Join-Path $Game.Root "crashes"
		if (-not (Test-Path $CrashDir)) { continue }
		$Dumps = Get-ChildItem -Path $CrashDir -Filter "*.dmp" -File -ErrorAction SilentlyContinue
		foreach ($Dump in $Dumps) {
			$Results += [PSCustomObject]@{
				Game      = $Game.Name
				GameRoot  = $Game.Root
				DumpPath  = $Dump.FullName
				Guid      = $Dump.BaseName
				Timestamp = $Dump.LastWriteTime
				SizeMB    = [Math]::Round($Dump.Length / 1MB, 1)
			}
		}
	}
	return @($Results | Sort-Object Timestamp -Descending)
}

function Get-CrashContext($Report) {
	$GameLogPath = "$($Report.DumpPath).gamelog"
	$GameLog = if (Test-Path $GameLogPath) { $GameLogPath } else { $null }

	$LogsDir = Join-Path $Report.GameRoot "logs"
	$SessionLog = $null
	if (Test-Path $LogsDir) {
		$Candidates = Get-ChildItem -Path $LogsDir -Filter "CitizenFX_log_*.log" -File -ErrorAction SilentlyContinue
		$SessionLog = $Candidates |
			Sort-Object { [Math]::Abs(($_.LastWriteTime - $Report.Timestamp).TotalSeconds) } |
			Select-Object -First 1
	}

	$Delta = if ($SessionLog) { [Math]::Round([Math]::Abs(($SessionLog.LastWriteTime - $Report.Timestamp).TotalSeconds), 1) } else { $null }
	$Reliable = $Delta -ne $null -and $Delta -le 120

	return [PSCustomObject]@{
		GameLogPath            = $GameLog
		SessionLogPath         = if ($Reliable) { $SessionLog.FullName } else { $null }
		SessionLogDeltaSeconds = $Delta
		CorrelationReliable    = $Reliable
	}
}

function Get-CrashEvidence($Context) {
	$Evidence = [PSCustomObject]@{
		DumpServerLines    = @()
		CrashReasonText    = $null
		CrashHash          = $null
		StackTrace         = @()
		NamedFileInReason  = $null
		RecentScriptErrors = @()
	}

	if ($Context.SessionLogPath -and (Test-Path $Context.SessionLogPath)) {
		$Lines = Get-Content $Context.SessionLogPath -ErrorAction SilentlyContinue

		$DumpLines = @()
		foreach ($Line in $Lines) {
			if ($Line -match '^\[\s*\d+\]\s*\[\s*DumpServer\]\s*\d+/\s?(.*)$') {
				$DumpLines += $Matches[1]
			}
		}
		$Evidence.DumpServerLines = $DumpLines

		if ($DumpLines.Count -gt 0) {
			$CaptureIndex = -1
			for ($i = 0; $i -lt $DumpLines.Count; $i++) {
				if ($DumpLines[$i] -match '^Process crash captured') { $CaptureIndex = $i }
			}
			if ($CaptureIndex -ge 0) {
				$ReasonLines = @()
				for ($i = $CaptureIndex + 1; $i -lt $DumpLines.Count; $i++) {
					$L = $DumpLines[$i]
					if ($L -match '^Stack trace:' -or $L.Trim() -eq '') { break }
					$ReasonLines += $L
				}
				if ($ReasonLines.Count -gt 0) {
					$Evidence.CrashReasonText = $ReasonLines[0]
				}

				$HashLine = $DumpLines[$CaptureIndex..($DumpLines.Count - 1)] | Where-Object { $_ -match 'Legacy crash hash:\s*(.+)' } | Select-Object -First 1
				if ($HashLine -match 'Legacy crash hash:\s*(.+)') {
					$Evidence.CrashHash = $Matches[1].Trim()
				}

				$InStack = $false
				for ($i = $CaptureIndex; $i -lt $DumpLines.Count; $i++) {
					$L = $DumpLines[$i]
					if ($L -match '^Stack trace:') { $InStack = $true; continue }
					if ($InStack) {
						if ($L -match '^\s*([\w\-]+\.(exe|dll))\+([0-9A-Fa-f]+)\s*$') {
							$Evidence.StackTrace += $L.Trim()
						} elseif ($L.Trim() -eq '') {
							break
						}
					}
				}
			}
			if ($Evidence.CrashReasonText -match '\(in\s+([\w\-]+)/([\w\-\./]+\.\w+)\)') {
				$Evidence.NamedFileInReason = [PSCustomObject]@{
					Resource = $Matches[1]
					File     = $Matches[2]
				}
			}
		}

		$Tail = $Lines | Select-Object -Last 200
		foreach ($Line in $Tail) {
			if ($Line -match '\^1SCRIPT ERROR:\s*@([\w\-]+)/([\w\-\./]+\.lua):(\d+):\s*(.+?)\^7') {
				$Evidence.RecentScriptErrors += [PSCustomObject]@{
					Resource = $Matches[1]
					File     = $Matches[2]
					Line     = $Matches[3]
					Message  = $Matches[4]
				}
			}
		}
	}

	return $Evidence
}

function Get-GamelogFacts($GamelogPath) {
	$Facts = [PSCustomObject]@{
		IsOutOfMemory        = $null
		PedMemoryUse         = $null
		PedMemoryBudget      = $null
		VehicleMemoryUse     = $null
		VehicleMemoryBudget  = $null
		NetworkOpen          = $null
		NetworkInTransition  = $null
		GameInProgress       = $null
		MemoryLoadPercent    = $null
		PhysicalFreeMB       = $null
		PhysicalTotalMB      = $null
	}
	if (-not $GamelogPath -or -not (Test-Path $GamelogPath)) { return $Facts }
	$Lines = Get-Content $GamelogPath -ErrorAction SilentlyContinue
	foreach ($Line in $Lines) {
		if ($Line -match 'Is Out of memory\s*:\s*(Yes|No)') { $Facts.IsOutOfMemory = ($Matches[1] -eq 'Yes') }
		elseif ($Line -match 'Ped Memory Use/Budget\s*:\s*(\d+)/(\d+)') { $Facts.PedMemoryUse = [int]$Matches[1]; $Facts.PedMemoryBudget = [int]$Matches[2] }
		elseif ($Line -match 'Vehicle Memory Use/Budget\s*:\s*(\d+)/(\d+)') { $Facts.VehicleMemoryUse = [int]$Matches[1]; $Facts.VehicleMemoryBudget = [int]$Matches[2] }
		elseif ($Line -match 'Network Open\s*:\s*(Yes|No)') { $Facts.NetworkOpen = ($Matches[1] -eq 'Yes') }
		elseif ($Line -match 'Network [Ss]ession in transition\s*:\s*(Yes|No)') { $Facts.NetworkInTransition = ($Matches[1] -eq 'Yes') }
		elseif ($Line -match 'Game In Progress\s*:\s*(Yes|No)') { $Facts.GameInProgress = ($Matches[1] -eq 'Yes') }
		elseif ($Line -match 'Memory Load\s*:\s*\(\s*(\d+)%\s*\)') { $Facts.MemoryLoadPercent = [int]$Matches[1] }
		elseif ($Line -match 'Physical Free\s*:\s*\(\s*(\d+)Mb\s*\)') { $Facts.PhysicalFreeMB = [int]$Matches[1] }
		elseif ($Line -match 'Physical Total\s*:\s*\(\s*(\d+)Mb\s*\)') { $Facts.PhysicalTotalMB = [int]$Matches[1] }
	}
	return $Facts
}

function Get-CrashDiagnosis($Report, $Context, $Evidence) {
	$Confirmado = New-Object System.Collections.Generic.List[string]
	$Possivel = New-Object System.Collections.Generic.List[string]
	$NaoDeterminado = New-Object System.Collections.Generic.List[string]
	$Evidencias = New-Object System.Collections.Generic.List[object]
	$Categorias = New-Object System.Collections.Generic.List[object]

	function Add-Evidence($Tipo, $Confianca, $Texto, $Recurso, $Arquivo, $Linha, $Valor) {
		$Evidencias.Add([PSCustomObject]@{
			Tipo      = $Tipo
			Confianca = $Confianca
			Texto     = $Texto
			Recurso   = $Recurso
			Arquivo   = $Arquivo
			Linha     = $Linha
			Valor     = $Valor
		})
		switch ($Confianca) {
			"Confirmado"     { $Confirmado.Add($Texto) }
			"Possivel"       { $Possivel.Add($Texto) }
			"NaoDeterminado" { $NaoDeterminado.Add($Texto) }
		}
	}

	function Add-Categoria($Nome, $Lado) {
		if (-not ($Categorias | Where-Object { $_.Nome -eq $Nome })) {
			$Categorias.Add([PSCustomObject]@{ Nome = $Nome; Lado = $Lado })
		}
	}

	Add-Evidence "Timestamp" "Confirmado" "Data/hora do crash: $($Report.Timestamp.ToString('dd/MM/yyyy HH:mm:ss'))" $null $null $null $Report.Timestamp
	Add-Evidence "Jogo" "Confirmado" "Jogo: $($Report.Game)" $null $null $null $Report.Game
	Add-Evidence "ArquivoDump" "Confirmado" "Arquivo de dump: $($Report.Guid).dmp ($($Report.SizeMB) MB)" $null $null $null $null

	if ($Context.SessionLogPath) {
		Add-Evidence "Correlacao" "Confirmado" "Log de sessao correlacionado (diferenca de $($Context.SessionLogDeltaSeconds)s)" $null $null $null $Context.SessionLogDeltaSeconds
	} elseif ($Context.SessionLogDeltaSeconds -ne $null) {
		Add-Evidence "Correlacao" "NaoDeterminado" "O log mais proximo esta a $([Math]::Round($Context.SessionLogDeltaSeconds/60,0)) minutos de distancia - distante demais pra correlacionar com confianca" $null $null $null $Context.SessionLogDeltaSeconds
	} else {
		Add-Evidence "Correlacao" "NaoDeterminado" "Nenhum log de sessao encontrado" $null $null $null $null
	}

	if ($Evidence.CrashHash) {
		Add-Evidence "Hash" "Confirmado" "Hash do crash: $($Evidence.CrashHash)" $null $null $null $Evidence.CrashHash
	}

	$MatchedPattern = $null
	if ($Evidence.CrashReasonText) {
		foreach ($Pattern in $KnownNativePatterns) {
			if ($Evidence.CrashReasonText -match $Pattern.Match) { $MatchedPattern = $Pattern; break }
		}
	}

	$ResourceName = $null
	$TypeKey = "Unknown"

	if ($Evidence.NamedFileInReason) {
		Add-Evidence "ArquivoCitado" "Confirmado" "Arquivo citado diretamente no motivo do crash: $($Evidence.NamedFileInReason.Resource)/$($Evidence.NamedFileInReason.File)" $Evidence.NamedFileInReason.Resource $Evidence.NamedFileInReason.File $null $null
		Add-Evidence "Recurso" "Possivel" "Recurso possivelmente relacionado: $($Evidence.NamedFileInReason.Resource)" $Evidence.NamedFileInReason.Resource $null $null $null
		Add-Categoria "Problema em um recurso do servidor" "Servidor"
		$ResourceName = $Evidence.NamedFileInReason.Resource
		$TypeKey = "Asset"
	} elseif ($MatchedPattern) {
		Add-Evidence "MotivoCrash" "Confirmado" "Motivo do crash (texto bruto): $($Evidence.CrashReasonText)" $null $null $null $Evidence.CrashReasonText
		Add-Evidence "TipoReconhecido" "Confirmado" "Tipo reconhecido: $($MatchedPattern.Label)" $null $null $null $MatchedPattern.Label
		Add-Categoria $MatchedPattern.Categoria $MatchedPattern.Lado
		$TypeKey = "Recognized"
	} elseif ($Evidence.CrashReasonText) {
		Add-Evidence "MotivoCrash" "Confirmado" "Motivo do crash (texto bruto): $($Evidence.CrashReasonText)" $null $null $null $Evidence.CrashReasonText
		Add-Evidence "MotivoCrash" "NaoDeterminado" "Nenhum recurso/arquivo especifico foi citado no motivo do crash - crash parece ser de engine/nativo" $null $null $null $null
	} else {
		Add-Evidence "MotivoCrash" "NaoDeterminado" "Nao foi possivel extrair o motivo do crash do log" $null $null $null $null
	}

	if ($Evidence.StackTrace.Count -gt 0) {
		Add-Evidence "StackTrace" "Confirmado" "Stack trace bruto disponivel ($($Evidence.StackTrace.Count) frames)" $null $null $null $Evidence.StackTrace.Count
	}

	$TopScriptResource = $null
	if ($Evidence.RecentScriptErrors.Count -gt 0) {
		$Grouped = $Evidence.RecentScriptErrors | Group-Object Resource | Sort-Object Count -Descending
		foreach ($G in $Grouped | Select-Object -First 3) {
			$FirstErr = $G.Group | Select-Object -First 1
			Add-Evidence "ScriptError" "Possivel" "Ha' evidencias associadas ao recurso '$($G.Name)' ($($G.Count) erro(s) de script pouco antes do crash, no mesmo log)" $G.Name $FirstErr.File $FirstErr.Line $FirstErr.Message
		}
		Add-Categoria "Problema em um recurso do servidor" "Servidor"
		if (-not $ResourceName) { $TopScriptResource = $Grouped[0].Name }
	}
	if (-not $ResourceName -and $TopScriptResource) { $ResourceName = $TopScriptResource }

	$GamelogFacts = Get-GamelogFacts $Context.GameLogPath
	$LimiarMemoriaAlta = 85
	if ($GamelogFacts.IsOutOfMemory -eq $true) {
		Add-Evidence "Memoria" "Confirmado" "O motor do jogo reportou memoria insuficiente no momento do crash (Is Out of memory: Sim)" $null $null $null $true
		Add-Categoria "Problema de memoria" "Cliente"
	}
	if ($GamelogFacts.MemoryLoadPercent -ne $null -and $GamelogFacts.MemoryLoadPercent -ge $LimiarMemoriaAlta) {
		Add-Evidence "Memoria" "Confirmado" "Memoria do sistema (nao so' do jogo) estava em $($GamelogFacts.MemoryLoadPercent)% de uso no momento do crash - $($GamelogFacts.PhysicalFreeMB) MB livres de $($GamelogFacts.PhysicalTotalMB) MB totais" $null $null $null $GamelogFacts.MemoryLoadPercent
		Add-Categoria "Problema de memoria" "Cliente"
	}
	if ($GamelogFacts.PedMemoryUse -ne $null -and $GamelogFacts.PedMemoryUse -gt $GamelogFacts.PedMemoryBudget) {
		Add-Evidence "Memoria" "Possivel" "Uso de memoria de pedestres acima do orcamento no momento do crash ($($GamelogFacts.PedMemoryUse)/$($GamelogFacts.PedMemoryBudget))" $null $null $null $null
		Add-Categoria "Problema de memoria" "Indeterminado"
	}
	if ($GamelogFacts.VehicleMemoryUse -ne $null -and $GamelogFacts.VehicleMemoryUse -gt $GamelogFacts.VehicleMemoryBudget) {
		Add-Evidence "Memoria" "Possivel" "Uso de memoria de veiculos acima do orcamento no momento do crash ($($GamelogFacts.VehicleMemoryUse)/$($GamelogFacts.VehicleMemoryBudget))" $null $null $null $null
		Add-Categoria "Problema de memoria" "Indeterminado"
	}
	if ($GamelogFacts.GameInProgress -eq $true -and $GamelogFacts.NetworkOpen -eq $false) {
		Add-Evidence "Rede" "Confirmado" "Estado de rede incomum no momento do crash: sessao de rede fechada com o jogo ainda em andamento" $null $null $null $null
		Add-Categoria "Problema de conexao/rede" "Indeterminado"
	}
	if ($GamelogFacts.NetworkInTransition -eq $true) {
		Add-Evidence "Rede" "Confirmado" "Estado de rede incomum no momento do crash: sessao de rede em transicao (reconectando/migrando host)" $null $null $null $null
		Add-Categoria "Problema de conexao/rede" "Indeterminado"
	}

	if ($Categorias.Count -eq 0) {
		Add-Categoria "Nao foi possivel identificar" "Indeterminado"
	}

	$ConfidenceTier = if ($Evidence.NamedFileInReason) { "High" }
		elseif ($MatchedPattern) { "Medium" }
		elseif ($Evidence.RecentScriptErrors.Count -gt 0) { "Medium" }
		else { "Low" }

	$Confidence = if ($Evidence.NamedFileInReason) { "Alta" }
		elseif ($MatchedPattern) { "Media (categoria reconhecida, sem recurso associado)" }
		elseif ($Evidence.RecentScriptErrors.Count -gt 0) { "Media (so indicios)" }
		else { "Nao determinada" }

	return [PSCustomObject]@{
		Confirmado     = $Confirmado.ToArray()
		Possivel       = $Possivel.ToArray()
		NaoDeterminado = $NaoDeterminado.ToArray()
		Evidencias     = $Evidencias.ToArray()
		Categorias     = $Categorias.ToArray()
		Confidence     = $Confidence
		ConfidenceTier = $ConfidenceTier
		ResourceName   = $ResourceName
		TypeKey        = $TypeKey
		PatternLabel   = if ($MatchedPattern) { $MatchedPattern.Label } else { $null }
	}
}

function Get-RelativeTimeText($Timestamp, $Lang) {
	$S = $Strings[$Lang]
	$Span = (Get-Date) - $Timestamp
	if ($Span.TotalMinutes -lt 60) {
		$N = [Math]::Max(1,[Math]::Round($Span.TotalMinutes))
		if ($N -eq 1) { return $S.MinuteAgoSingular }
		return ($S.MinutesAgoFormat -f $N)
	} elseif ($Span.TotalHours -lt 24) {
		$N = [Math]::Round($Span.TotalHours)
		if ($N -eq 1) { return $S.HourAgoSingular }
		return ($S.HoursAgoFormat -f $N)
	} else {
		$N = [Math]::Round($Span.TotalDays)
		if ($N -eq 1) { return $S.DayAgoSingular }
		return ($S.DaysAgoFormat -f $N)
	}
}

function Get-DateGroupLabel($Timestamp, $Lang) {
	$S = $Strings[$Lang]
	$Today = (Get-Date).Date
	$D = $Timestamp.Date
	if ($D -eq $Today) { return $S.GroupToday }
	if ($D -eq $Today.AddDays(-1)) { return $S.GroupYesterday }
	return $D.ToString("dd/MM/yyyy")
}

function Build-CrashReportText($Report, $Diagnosis, $Lang) {
	$S = $Strings[$Lang]

	$ResultTitle = switch ($Diagnosis.ConfidenceTier) {
		"High"   { $S.ResultTitleHigh }
		"Medium" { $S.ResultTitleMedium }
		default  { $S.ResultTitleLow }
	}
	$ConfidenceText = switch ($Diagnosis.ConfidenceTier) {
		"High"   { $S.ConfidenceHigh }
		"Medium" { $S.ConfidenceMedium }
		default  { $S.ConfidenceLow }
	}
	$NoteText = switch ($Diagnosis.ConfidenceTier) {
		"High"   { $S.NoteHigh }
		"Medium" { $S.NoteMedium }
		default  { $S.NoteLow }
	}

	$Lines = New-Object System.Collections.Generic.List[string]
	$Lines.Add("=== $($S.ReportTitle) - NFXS CrashCheck ===")
	$Lines.Add("$($S.ReportGame): $($Report.Game)")
	$Lines.Add("$($S.ReportDate): $($Report.Timestamp.ToString('dd/MM/yyyy HH:mm:ss'))")
	$Lines.Add("")
	$Lines.Add("$($S.ReportResult): $ResultTitle")
	$Lines.Add("")
	$Lines.Add($S.ProblemsFoundHeader)
	if ($Diagnosis.Categorias.Count -eq 0) {
		$Lines.Add("- $($S.NoProblemsFound)")
	} else {
		foreach ($Cat in $Diagnosis.Categorias) {
			$LadoText = switch ($Cat.Lado) {
				"Cliente"  { $S.LadoCliente }
				"Servidor" { $S.LadoServidor }
				default    { $S.LadoIndeterminado }
			}
			$Lines.Add("- $($Cat.Nome) ($LadoText)")
		}
	}
	if ($Diagnosis.ResourceName) {
		$Lines.Add("$($S.ResourceLabel): $($Diagnosis.ResourceName)")
	}
	$Lines.Add("")
	$Lines.Add($S.CrashMomentHeader)
	$Lines.Add("$($Report.Timestamp.ToString('dd/MM/yyyy HH:mm:ss')), $($S.PlayingFormat -f $Report.Game)")
	$Lines.Add("")
	$Lines.Add("$($S.ConfidenceLabel): $ConfidenceText")
	$Lines.Add("")
	$Lines.Add("$($S.EvidenceHeader):")
	$AllEvidence = @($Diagnosis.Confirmado) + @($Diagnosis.Possivel)
	foreach ($E in $AllEvidence) { $Lines.Add("- $E") }
	$Lines.Add("")
	$Lines.Add("$($S.ReportNote): $NoteText")
	$Lines.Add("")
	$Lines.Add($S.ReportFooter)

	return ($Lines -join "`r`n")
}

function Build-CrashZip($Report, $Context, $ReportText) {
	$Desktop = [Environment]::GetFolderPath("Desktop")
	$Stamp = $Report.Timestamp.ToString("yyyy-MM-dd_HHmmss")
	$BaseName = "NFXS_Crash_$($Report.Game)_$Stamp"
	$ZipPath = Join-Path $Desktop "$BaseName.zip"
	$Counter = 1
	while (Test-Path $ZipPath) {
		$ZipPath = Join-Path $Desktop "$BaseName ($Counter).zip"
		$Counter++
	}

	$TempDir = Join-Path $env:TEMP "NFXSCrashExport_$([Guid]::NewGuid().ToString('N'))"
	New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
	try {
		if (Test-Path $Report.DumpPath) {
			Copy-Item $Report.DumpPath -Destination $TempDir -ErrorAction SilentlyContinue
		}
		$GameLogPath = "$($Report.DumpPath).gamelog"
		if (Test-Path $GameLogPath) {
			Copy-Item $GameLogPath -Destination $TempDir -ErrorAction SilentlyContinue
		}
		if ($Context.SessionLogPath -and (Test-Path $Context.SessionLogPath)) {
			Copy-Item $Context.SessionLogPath -Destination $TempDir -ErrorAction SilentlyContinue
		}
		Set-Content -Path (Join-Path $TempDir "Relatorio.txt") -Value $ReportText -Encoding UTF8
		Compress-Archive -Path "$TempDir\*" -DestinationPath $ZipPath -Force
		return $ZipPath
	} finally {
		Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
	}
}

$Script:Reports = @(Find-CrashReports)
$Script:SelectedReport = $null
$Script:SelectedDiagnosis = $null
$Script:TechDetailsVisible = $false
$Script:MaxDisplayReports = 5

$IconPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS.ico"

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "NFXS CrashCheck"
$Form.AutoScaleMode = "Dpi"
$Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96,96)
$Form.Size = Scale-Size 400 880
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedSingle"
$Form.MaximizeBox = $false
$Form.Font = $DefaultFont
if (Test-Path $IconPath) { $Form.Icon = New-Object System.Drawing.Icon($IconPath) }

$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Dock = "Top"
$HeaderPanel.Height = Scale-Val 92
$Form.Controls.Add($HeaderPanel)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "NFXS | CRASH CHECK"
$TitleLabel.Font = Scale-Font 14 ([System.Drawing.FontStyle]::Bold)
$TitleLabel.AutoSize = $true
$TitleLabel.Location = Scale-Point 18 14
$HeaderPanel.Controls.Add($TitleLabel)

$SubtitleLabel = New-Object System.Windows.Forms.Label
$SubtitleLabel.UseMnemonic = $false
$SubtitleLabel.AutoSize = $false
$SubtitleLabel.Size = Scale-Size 344 44
$SubtitleLabel.Location = Scale-Point 18 42
$SubtitleLabel.Font = Scale-Font 8.25
$HeaderPanel.Controls.Add($SubtitleLabel)

$ContentPanel = New-Object System.Windows.Forms.Panel
$ContentPanel.Dock = "Fill"
$ContentPanel.AutoScroll = $true
$Form.Controls.Add($ContentPanel)
$ContentPanel.BringToFront()

$FooterPanel = New-Object System.Windows.Forms.Panel
$FooterPanel.Dock = "Bottom"
$FooterPanel.Height = Scale-Val 164
$Form.Controls.Add($FooterPanel)

$NewsLabel = New-Object System.Windows.Forms.LinkLabel
$NewsLabel.AutoSize = $false
$NewsLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$NewsLabel.Size = Scale-Size 344 32
$NewsLabel.Location = Scale-Point 18 28
$NewsLabel.Font = Scale-Font 7.5
$NewsLabel.LinkBehavior = "HoverUnderline"
$FooterPanel.Controls.Add($NewsLabel)
$NewsLabel.Add_LinkClicked({
	$Target = if ($News -and $News.Link) { $News.Link } elseif ($UpdateAvailable) { $DiscordUrl } else { $DiscordUrl }
	try { Start-Process $Target } catch {}
})

$NewsBanner = New-Object System.Windows.Forms.PictureBox
$NewsBanner.Size = Scale-Size 344 72
$NewsBanner.Location = Scale-Point 18 12
$NewsBanner.SizeMode = "Zoom"
$NewsBanner.Cursor = "Hand"
$NewsBanner.Visible = $false
$FooterPanel.Controls.Add($NewsBanner)
$NewsBanner.Add_Click({
	$Target = if ($News -and $News.Link) { $News.Link } else { $DiscordUrl }
	try { Start-Process $Target } catch {}
})

$DiscordButton = New-Object System.Windows.Forms.Button
$DiscordButton.Text = "Discord"
$DiscordButton.Font = Scale-Font 7.5 ([System.Drawing.FontStyle]::Bold)
$DiscordButton.Size = Scale-Size 72 24
$DiscordX = [int](($Form.ClientSize.Width - $DiscordButton.Width) / 2)
$DiscordButton.Location = New-Object System.Drawing.Point($DiscordX, (Scale-Val 96))
$DiscordButton.BackColor = [System.Drawing.Color]::FromArgb(88,101,242)
$DiscordButton.ForeColor = [System.Drawing.Color]::White
$DiscordButton.FlatStyle = "Flat"
$DiscordButton.FlatAppearance.BorderSize = 0
$DiscordButton.Cursor = "Hand"
$DiscordButton.Add_Click({ try { Start-Process $DiscordUrl } catch {} })
$FooterPanel.Controls.Add($DiscordButton)

$CreditLabel = New-Object System.Windows.Forms.Label
$CreditLabel.AutoSize = $false
$CreditLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$CreditLabel.Size = Scale-Size 344 16
$CreditLabel.Location = Scale-Point 18 134
$CreditLabel.Font = Scale-Font 7.5
$FooterPanel.Controls.Add($CreditLabel)

$ListView = New-Object System.Windows.Forms.Panel
$ListView.Location = New-Object System.Drawing.Point(0,0)
$ListView.Width = Scale-Val 338
$ListView.BackColor = [System.Drawing.Color]::Transparent
$ContentPanel.Controls.Add($ListView)

$ResultView = New-Object System.Windows.Forms.Panel
$ResultView.Location = New-Object System.Drawing.Point(0,0)
$ResultView.Width = Scale-Val 338
$ResultView.Visible = $false
$ContentPanel.Controls.Add($ResultView)

function Show-ListPane {
	$Script:SelectedReport = $null
	$ResultView.Visible = $false
	$ListView.Visible = $true
	Build-ListView
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
}

function Show-ResultPane($Report) {
	$Script:SelectedReport = $Report
	$Script:TechDetailsVisible = $false
	$Ctx = Get-CrashContext $Report
	$Ev = Get-CrashEvidence $Ctx
	$Diag = Get-CrashDiagnosis $Report $Ctx $Ev
	$Script:SelectedContext = $Ctx
	$Script:SelectedEvidence = $Ev
	$Script:SelectedDiagnosis = $Diag
	$ListView.Visible = $false
	$ResultView.Visible = $true
	Build-ResultView
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
}

function Build-ListView {
	$T = $Themes[$CurrentTheme]
	$S = $Strings[$CurrentLang]
	$Accent = Get-SharedAccentColor $CurrentTheme
	$ListView.Controls.Clear()
	$ListView.BackColor = $T.FormBg
	$Y = (Scale-Val 12)
	$Width = 320

	$HeaderLbl = New-Object System.Windows.Forms.Label
	$HeaderLbl.Text = $S.ListHeader
	$HeaderLbl.Font = Scale-Font 10 ([System.Drawing.FontStyle]::Bold)
	$HeaderLbl.ForeColor = $T.Text
	$HeaderLbl.AutoSize = $true
	$HeaderLbl.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ListView.Controls.Add($HeaderLbl)
	$Y += (Scale-Val 30)
	if ($Script:Reports.Count -eq 0) {
		$NoTitle = New-Object System.Windows.Forms.Label
		$NoTitle.Text = $S.NoReportsTitle
		$NoTitle.Font = Scale-Font 10 ([System.Drawing.FontStyle]::Bold)
		$NoTitle.ForeColor = $T.Text
		$NoTitle.AutoSize = $true
		$NoTitle.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
		$ListView.Controls.Add($NoTitle)
		$Y += (Scale-Val 26)
		$NoDesc = New-Object System.Windows.Forms.Label
		$NoDesc.Text = $S.NoReportsDesc
		$NoDesc.ForeColor = $T.TextSoft
		$NoDesc.AutoSize = $false
		$NoDesc.Size = Scale-Size $Width 40
		$NoDesc.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
		$ListView.Controls.Add($NoDesc)
		$Y += (Scale-Val 50)
	} else {
		$LastGroup = $null
		$First = $true
		foreach ($R in ($Script:Reports | Select-Object -First $Script:MaxDisplayReports)) {
			$Group = Get-DateGroupLabel $R.Timestamp $CurrentLang
			if ($Group -ne $LastGroup) {
				$GroupLbl = New-Object System.Windows.Forms.Label
				$GroupLbl.Text = $Group
				$GroupLbl.ForeColor = $T.TextSoft
				$GroupLbl.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
				$GroupLbl.AutoSize = $true
				$GroupLbl.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
				$ListView.Controls.Add($GroupLbl)
				$Y += (Scale-Val 24)
				$LastGroup = $Group
			}

			$Row = New-Object System.Windows.Forms.Panel
			$Row.Size = Scale-Size $Width 60
			$Row.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
			$Row.BackColor = $T.RowBg
			$Row.Cursor = "Hand"
			$Row.Tag = $R

			$Border = New-Object System.Windows.Forms.Panel
			$Border.Size = Scale-Size $Width 1
			$Border.Location = Scale-Point 0 59
			$Border.BackColor = $T.RowBorder
			$Row.Controls.Add($Border)

			$GameLbl = New-Object System.Windows.Forms.Label
			$GameLbl.Text = "$($R.Game) - $(Get-RelativeTimeText $R.Timestamp $CurrentLang)"
			$GameLbl.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
			$GameLbl.ForeColor = $T.Text
			$GameLbl.AutoSize = $true
			$GameLbl.Location = Scale-Point 4 8
			$Row.Controls.Add($GameLbl)

			$TimeLbl = New-Object System.Windows.Forms.Label
			$TimeLbl.Text = "$($S.CrashReportLabel) - $($R.Timestamp.ToString('dd/MM/yyyy HH:mm:ss'))"
			$TimeLbl.ForeColor = $T.TextSoft
			$TimeLbl.Font = Scale-Font 8
			$TimeLbl.AutoSize = $true
			$TimeLbl.Location = Scale-Point 4 30
			$Row.Controls.Add($TimeLbl)

			if ($First) {
				$Badge = New-Object System.Windows.Forms.Label
				$Badge.Text = $S.MostRecentBadge
				$Badge.ForeColor = Get-SharedAccentColor $CurrentTheme
				$Badge.Font = Scale-Font 7.5 ([System.Drawing.FontStyle]::Bold)
				$Badge.AutoSize = $true
				$Badge.Location = Scale-Point 4 46
				$Row.Controls.Add($Badge)
				$First = $false
			}

			$RowClick = { Show-ResultPane $this.Tag }.GetNewClosure()
			$Row.Add_Click($RowClick)
			foreach ($C in $Row.Controls) {
				if ($C -ne $Border) {
					$C.Add_Click({ Show-ResultPane $Row.Tag }.GetNewClosure())
					$C.Cursor = "Hand"
				}
			}

			$ListView.Controls.Add($Row)
			$Y += (Scale-Val 64)
		}
	}

	$Y += (Scale-Val 8)
	$RefreshBtn = New-Object System.Windows.Forms.Button
	$RefreshBtn.Text = $S.RefreshButton
	$RefreshBtn.Size = Scale-Size 152 34
	$RefreshBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$RefreshBtn.FlatStyle = "Flat"
	$RefreshBtn.FlatAppearance.BorderSize = 0
	$RefreshBtn.Cursor = "Hand"
	$RefreshBtn.BackColor = $Accent
	$RefreshBtn.ForeColor = $T.AccentTxt
	$RefreshBtn.Font = Scale-Font 9 ([System.Drawing.FontStyle]::Bold)
	$RefreshBtn.Add_Click({
		$Script:Reports = @(Find-CrashReports)
		Build-ListView
	})
	$ListView.Controls.Add($RefreshBtn)

	$CloseBtn = New-Object System.Windows.Forms.Button
	$CloseBtn.Text = $S.CloseButton
	$CloseBtn.Size = Scale-Size 152 34
	$CloseBtn.Location = New-Object System.Drawing.Point((Scale-Val 186), $Y)
	$CloseBtn.FlatStyle = "Flat"
	$CloseBtn.FlatAppearance.BorderSize = 1
	$CloseBtn.Cursor = "Hand"
	$CloseBtn.BackColor = $T.Btn2Bg
	$CloseBtn.ForeColor = $T.Btn2Fg
	$CloseBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$CloseBtn.Add_Click({ $Form.Close() })
	$ListView.Controls.Add($CloseBtn)
	$Y += (Scale-Val 34)

	$ListView.Height = $Y + (Scale-Val 10)
	$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, $ListView.Height)
}

function Build-ResultView {
	$T = $Themes[$CurrentTheme]
	$S = $Strings[$CurrentLang]
	$Accent = Get-SharedAccentColor $CurrentTheme
	$ResultView.Controls.Clear()
	$ResultView.BackColor = $T.FormBg
	$Report = $Script:SelectedReport
	$Diag = $Script:SelectedDiagnosis
	$Ev = $Script:SelectedEvidence
	$Ctx = $Script:SelectedContext
	$Width = 320
	$Y = (Scale-Val 12)
	$BackBtn = New-Object System.Windows.Forms.Button
	$BackBtn.Text = "< $($S.BackButton)"
	$BackBtn.Size = Scale-Size 150 28
	$BackBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$BackBtn.FlatStyle = "Flat"
	$BackBtn.FlatAppearance.BorderSize = 1
	$BackBtn.BackColor = $T.Btn2Bg
	$BackBtn.ForeColor = $T.Btn2Fg
	$BackBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$BackBtn.Cursor = "Hand"
	$BackBtn.Add_Click({ Show-ListPane })
	$ResultView.Controls.Add($BackBtn)
	$Y += (Scale-Val 40)
	$TitleColor = switch ($Diag.ConfidenceTier) {
		"High"   { $T.Success }
		"Medium" { $T.Warning }
		default  { $T.TextSoft }
	}
	$ResultTitleText = switch ($Diag.ConfidenceTier) {
		"High"   { $S.ResultTitleHigh }
		"Medium" { $S.ResultTitleMedium }
		default  { $S.ResultTitleLow }
	}
	$TitleLbl = New-Object System.Windows.Forms.Label
	$TitleLbl.Text = $ResultTitleText
	$TitleLbl.Font = Scale-Font 12 ([System.Drawing.FontStyle]::Bold)
	$TitleLbl.ForeColor = $TitleColor
	$TitleLbl.AutoSize = $false
	$TitleLbl.Size = Scale-Size $Width 26
	$TitleLbl.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ResultView.Controls.Add($TitleLbl)
	$Y += (Scale-Val 32)
	function Add-FieldRow($LabelText, $ValueText) {
		$L = New-Object System.Windows.Forms.Label
		$L.Text = "$($LabelText):"
		$L.ForeColor = $T.TextSoft
		$L.Font = Scale-Font 8.75 ([System.Drawing.FontStyle]::Bold)
		$L.AutoSize = $true
		$L.Location = New-Object System.Drawing.Point((Scale-Val 18), $Script:RY)
		$ResultView.Controls.Add($L)

		$ValueWidth = 180
		$VFont = Scale-Font 8.75
		$V = New-Object System.Windows.Forms.Label
		$V.Text = $ValueText
		$V.ForeColor = $T.Text
		$V.Font = $VFont
		$V.AutoSize = $false
		$Measured = [System.Windows.Forms.TextRenderer]::MeasureText($ValueText, $VFont, (Scale-Size $ValueWidth 0), [System.Windows.Forms.TextFormatFlags]::WordBreak)
		$RowHeight = [Math]::Max((Scale-Val 20), $Measured.Height + (Scale-Val 4))
		$V.Size = New-Object System.Drawing.Size((Scale-Val $ValueWidth), $RowHeight)
		$V.Location = New-Object System.Drawing.Point((Scale-Val 150), $Script:RY)
		$ResultView.Controls.Add($V)
		$Script:RY += $RowHeight + (Scale-Val 4)
	}

	function Add-WrappedLabel($Text, $Font, $Color, $YPos) {
		$L = New-Object System.Windows.Forms.Label
		$L.Text = $Text
		$L.ForeColor = $Color
		$L.Font = $Font
		$L.AutoSize = $false
		$Measured = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font, (Scale-Size $Width 0), [System.Windows.Forms.TextFormatFlags]::WordBreak)
		$L.Size = New-Object System.Drawing.Size((Scale-Val $Width), ($Measured.Height + (Scale-Val 6)))
		$L.Location = New-Object System.Drawing.Point((Scale-Val 18), $YPos)
		$ResultView.Controls.Add($L)
		return $YPos + $L.Height + (Scale-Val 4)
	}

	$ProblemsHeader = New-Object System.Windows.Forms.Label
	$ProblemsHeader.Text = $S.ProblemsFoundHeader
	$ProblemsHeader.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
	$ProblemsHeader.ForeColor = $T.Text
	$ProblemsHeader.AutoSize = $true
	$ProblemsHeader.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ResultView.Controls.Add($ProblemsHeader)
	$Y += (Scale-Val 24)
	$CategoryFont = Scale-Font 8.75
	if ($Diag.Categorias.Count -eq 0) {
		$Y = Add-WrappedLabel $S.NoProblemsFound $CategoryFont $T.TextSoft $Y
	} else {
		foreach ($Cat in $Diag.Categorias) {
			$LadoText = switch ($Cat.Lado) {
				"Cliente"   { $S.LadoCliente }
				"Servidor"  { $S.LadoServidor }
				default     { $S.LadoIndeterminado }
			}
			$Y = Add-WrappedLabel "-  $($Cat.Nome) ($LadoText)" $CategoryFont $T.Text $Y
		}
	}
	$Y += (Scale-Val 6)
	if ($Diag.ResourceName) {
		$Script:RY = $Y
		Add-FieldRow $S.ResourceLabel $Diag.ResourceName
		$Y = $Script:RY + (Scale-Val 4)
	}

	$MomentHeader = New-Object System.Windows.Forms.Label
	$MomentHeader.Text = $S.CrashMomentHeader
	$MomentHeader.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
	$MomentHeader.ForeColor = $T.Text
	$MomentHeader.AutoSize = $true
	$MomentHeader.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ResultView.Controls.Add($MomentHeader)
	$Y += (Scale-Val 24)
	$MomentText = "$($Report.Timestamp.ToString('dd/MM/yyyy HH:mm:ss')), $($S.PlayingFormat -f $Report.Game)"
	$Y = Add-WrappedLabel $MomentText (Scale-Font 8.75) $T.Text $Y
	$Y += (Scale-Val 6)
	$ConfidenceText = switch ($Diag.ConfidenceTier) {
		"High"   { $S.ConfidenceHigh }
		"Medium" { $S.ConfidenceMedium }
		default  { $S.ConfidenceLow }
	}
	$Script:RY = $Y
	Add-FieldRow $S.ConfidenceLabel $ConfidenceText
	$Y = $Script:RY + (Scale-Val 8)

	$EvHeader = New-Object System.Windows.Forms.Label
	$EvHeader.Text = $S.EvidenceHeader
	$EvHeader.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
	$EvHeader.ForeColor = $T.Text
	$EvHeader.AutoSize = $true
	$EvHeader.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ResultView.Controls.Add($EvHeader)
	$Y += (Scale-Val 26)
	$EvidenceFont = Scale-Font 8.5
	$AllEvidence = @($Diag.Confirmado) + @($Diag.Possivel)
	foreach ($E in $AllEvidence) {
		$Y = Add-WrappedLabel "-  $E" $EvidenceFont $T.Text $Y
	}
	if ($AllEvidence.Count -eq 0) {
		foreach ($E in $Diag.NaoDeterminado) {
			$Y = Add-WrappedLabel "-  $E" $EvidenceFont $T.TextSoft $Y
		}
	}
	$Y += (Scale-Val 8)
	$NoteText = switch ($Diag.ConfidenceTier) {
		"High"   { $S.NoteHigh }
		"Medium" { $S.NoteMedium }
		default  { $S.NoteLow }
	}
	$Y = Add-WrappedLabel $NoteText (Scale-Font 8 ([System.Drawing.FontStyle]::Italic)) $T.TextSoft $Y
	$Y += (Scale-Val 8)
	$DetailsBtn = New-Object System.Windows.Forms.Button
	$DetailsBtn.Text = if ($Script:TechDetailsVisible) { $S.HideDetailsButton } else { $S.DetailsButton }
	$DetailsBtn.Size = Scale-Size 320 30
	$DetailsBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$DetailsBtn.FlatStyle = "Flat"
	$DetailsBtn.FlatAppearance.BorderSize = 1
	$DetailsBtn.BackColor = $T.Btn2Bg
	$DetailsBtn.ForeColor = $T.Btn2Fg
	$DetailsBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$DetailsBtn.Cursor = "Hand"
	$DetailsBtn.Add_Click({
		$Script:TechDetailsVisible = -not $Script:TechDetailsVisible
		Build-ResultView
	})
	$ResultView.Controls.Add($DetailsBtn)
	$Y += (Scale-Val 40)
	if ($Script:TechDetailsVisible) {
		$Script:RY = $Y
		$LogPathValue = if ($Ctx.SessionLogPath) { [System.IO.Path]::GetFileName($Ctx.SessionLogPath) } else { $S.TechNone }
		$LogDeltaValue = if ($Ctx.SessionLogDeltaSeconds -ne $null) { "$($Ctx.SessionLogDeltaSeconds)s" } else { $S.TechNone }
		$HashValue = if ($Ev.CrashHash) { $Ev.CrashHash } else { $S.TechNone }
		Add-FieldRow $S.TechFilePath ([System.IO.Path]::GetFileName($Report.DumpPath))
		Add-FieldRow $S.TechSizeKB "$($Report.SizeMB) MB"
		Add-FieldRow $S.TechLogPath $LogPathValue
		Add-FieldRow $S.TechLogDelta $LogDeltaValue
		Add-FieldRow $S.TechHash $HashValue
		$Y = $Script:RY + (Scale-Val 4)

		$StackHeader = New-Object System.Windows.Forms.Label
		$StackHeader.Text = $S.TechStackTrace
		$StackHeader.ForeColor = $T.TextSoft
		$StackHeader.Font = Scale-Font 8.75 ([System.Drawing.FontStyle]::Bold)
		$StackHeader.AutoSize = $true
		$StackHeader.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
		$ResultView.Controls.Add($StackHeader)
		$Y += (Scale-Val 22)
		$StackBox = New-Object System.Windows.Forms.TextBox
		$StackBox.Multiline = $true
		$StackBox.ReadOnly = $true
		$StackBox.ScrollBars = "Vertical"
		$StackBox.BackColor = $T.FieldBg
		$StackBox.ForeColor = $T.FieldFg
		$StackBox.Font = New-Object System.Drawing.Font("Consolas", ([Math]::Max(8 * $Script:UIScale, $Script:MinFontPt)))
		$StackBox.Size = Scale-Size $Width 80
		$StackBox.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
		$StackBox.Text = if ($Ev.StackTrace.Count -gt 0) { $Ev.StackTrace -join "`r`n" } else { $S.TechNone }
		$ResultView.Controls.Add($StackBox)
		$Y += (Scale-Val 90)
		if ($Ev.RecentScriptErrors.Count -gt 0) {
			$SEHeader = New-Object System.Windows.Forms.Label
			$SEHeader.Text = $S.TechScriptErrors
			$SEHeader.ForeColor = $T.TextSoft
			$SEHeader.Font = Scale-Font 8.75 ([System.Drawing.FontStyle]::Bold)
			$SEHeader.AutoSize = $true
			$SEHeader.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
			$ResultView.Controls.Add($SEHeader)
			$Y += (Scale-Val 22)
			$SEBox = New-Object System.Windows.Forms.TextBox
			$SEBox.Multiline = $true
			$SEBox.ReadOnly = $true
			$SEBox.ScrollBars = "Vertical"
			$SEBox.BackColor = $T.FieldBg
			$SEBox.ForeColor = $T.FieldFg
			$SEBox.Font = New-Object System.Drawing.Font("Consolas", ([Math]::Max(8 * $Script:UIScale, $Script:MinFontPt)))
			$SEBox.Size = Scale-Size $Width 70
			$SEBox.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
			$SEBox.Text = ($Ev.RecentScriptErrors | ForEach-Object { "@$($_.Resource)/$($_.File):$($_.Line): $($_.Message)" }) -join "`r`n"
			$ResultView.Controls.Add($SEBox)
			$Y += (Scale-Val 80)
		}
		$Y += (Scale-Val 8)
	}

	$CopyBtn = New-Object System.Windows.Forms.Button
	$CopyBtn.Text = $S.CopyButton
	$CopyBtn.Size = Scale-Size 320 34
	$CopyBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$CopyBtn.FlatStyle = "Flat"
	$CopyBtn.FlatAppearance.BorderSize = 0
	$CopyBtn.BackColor = $Accent
	$CopyBtn.ForeColor = if ($CurrentTheme -eq "Dark") { $T.AccentTxt } else { $T.AccentTxt }
	$CopyBtn.Font = Scale-Font 9 ([System.Drawing.FontStyle]::Bold)
	$CopyBtn.Cursor = "Hand"
	$CopyBtn.Add_Click({
		$Text = Build-CrashReportText $Script:SelectedReport $Script:SelectedDiagnosis $CurrentLang
		[System.Windows.Forms.Clipboard]::SetText($Text)
		$CopyBtn.Text = $Strings[$CurrentLang].CopiedFeedback
		$CopyFeedbackTimer.Start()
	})
	$ResultView.Controls.Add($CopyBtn)
	$Y += (Scale-Val 40)
	$ExportBtn = New-Object System.Windows.Forms.Button
	$ExportBtn.Text = $S.ExportButton
	$ExportBtn.Size = Scale-Size 320 32
	$ExportBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ExportBtn.FlatStyle = "Flat"
	$ExportBtn.FlatAppearance.BorderSize = 1
	$ExportBtn.BackColor = $T.Btn2Bg
	$ExportBtn.ForeColor = $T.Btn2Fg
	$ExportBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$ExportBtn.Cursor = "Hand"
	$ExportBtn.Add_Click({
		$ReportText = Build-CrashReportText $Script:SelectedReport $Script:SelectedDiagnosis $CurrentLang
		try {
			$SavedPath = Build-CrashZip $Script:SelectedReport $Script:SelectedContext $ReportText
			$Msg = ($Strings[$CurrentLang].ExportSuccessFormat -f $SavedPath)
			$Choice = [System.Windows.Forms.MessageBox]::Show($Msg, $Strings[$CurrentLang].ExportSuccessTitle, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
			if ($Choice -eq [System.Windows.Forms.DialogResult]::Yes) {
				Start-Process "explorer.exe" -ArgumentList "/select,`"$SavedPath`""
			}
		} catch {
			[System.Windows.Forms.MessageBox]::Show($Strings[$CurrentLang].ExportErrorText, $Strings[$CurrentLang].ExportSuccessTitle, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
		}
	})
	$ResultView.Controls.Add($ExportBtn)
	$Y += (Scale-Val 42)

	$ResultView.Height = $Y + (Scale-Val 10)
	$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, $ResultView.Height)
}

$CopyFeedbackTimer = New-Object System.Windows.Forms.Timer
$CopyFeedbackTimer.Interval = 1400
$CopyFeedbackTimer.Add_Tick({
	$CopyFeedbackTimer.Stop()
	if ($Script:SelectedReport) { Build-ResultView }
})

function Set-Theme($Name) {
	$Script:CurrentTheme = $Name
	$T = $Themes[$Name]
	$Accent = Get-SharedAccentColor $Name

	$Form.BackColor = $T.FormBg
	$HeaderPanel.BackColor = $T.HeaderBg
	$ContentPanel.BackColor = $T.FormBg
	$TitleLabel.ForeColor = $T.HeaderTitle
	$SubtitleLabel.ForeColor = $T.HeaderSub
	$FooterPanel.BackColor = $T.FormBg
	$CreditLabel.ForeColor = $T.Credit
	$NewsLabel.LinkColor = $Accent
	$NewsLabel.ActiveLinkColor = $Accent
	$NewsLabel.VisitedLinkColor = $Accent

	if ($T.DarkTitlebar -and $Form.Handle) {
		$Val = 1
		[NFX.Dwm]::DwmSetWindowAttribute($Form.Handle, 20, [ref]$Val, 4) | Out-Null
	}

	if ($Script:SelectedReport) { Build-ResultView } else { Build-ListView }
}

function Apply-Language($Code) {
	$Script:CurrentLang = $Code
	$S = $Strings[$Code]
	$SubtitleLabel.Text = "$($S.Description) v$AppVersion"
	$CreditLabel.Text = $S.FreeLabel
	if ($UpdateAvailable) {
		$NewsLabel.Visible = $true
		$NewsBanner.Visible = $false
		$NewsLabel.Text = ($S.UpdateAvailableFormat -f $LatestVersion)
	} elseif ($NewsBannerImage) {
		$NewsLabel.Visible = $false
		$NewsBanner.Visible = $true
		$NewsBanner.Image = $NewsBannerImage
	} else {
		$NewsLabel.Visible = $true
		$NewsBanner.Visible = $false
		$NewsLabel.Text = $S.UpdateOk
	}
	if ($Script:SelectedReport) { Build-ResultView } else { Build-ListView }
}

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

Set-Theme $CurrentTheme
Apply-Language $CurrentLang
Show-ListPane
Set-AutoEllipsisRecursive $HeaderPanel
Set-AutoEllipsisRecursive $FooterPanel

$Form.Add_Shown({
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	$ContentPanel.BeginInvoke([Action]{
		$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	}) | Out-Null
})

[System.Windows.Forms.Application]::Run($Form)
