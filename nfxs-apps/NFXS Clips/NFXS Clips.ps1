
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
Add-Type -Name Input -Namespace NFX -MemberDefinition @"
[DllImport("user32.dll")]
public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace NFXThumb {
	[StructLayout(LayoutKind.Sequential)]
	public struct SIZE { public int cx; public int cy; }

	[ComImport]
	[Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b")]
	[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
	public interface IShellItemImageFactory {
		void GetImage(SIZE size, int flags, out IntPtr phbm);
	}

	public static class ShellThumb {
		[DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
		static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid, out IShellItemImageFactory ppv);

		[DllImport("gdi32.dll")]
		static extern bool DeleteObject(IntPtr hObject);

		// SIIGBF_RESIZETOFIT (0) - encolhe preservando proporcao, nunca corta
		// nem distorce. O PictureBox.SizeMode=Zoom do lado PowerShell cuida
		// do encaixe final, entao nao precisa pedir um tamanho exato aqui.
		public static IntPtr GetHBitmap(string path, int maxDim) {
			Guid guid = typeof(IShellItemImageFactory).GUID;
			IShellItemImageFactory factory = null;
			IntPtr hbm = IntPtr.Zero;
			try {
				SHCreateItemFromParsingName(path, IntPtr.Zero, ref guid, out factory);
				SIZE size; size.cx = maxDim; size.cy = maxDim;
				factory.GetImage(size, 0, out hbm);
			} finally {
				if (factory != null) Marshal.ReleaseComObject(factory);
			}
			return hbm;
		}

		public static void FreeHBitmap(IntPtr hbm) {
			if (hbm != IntPtr.Zero) DeleteObject(hbm);
		}
	}
}
"@ -ErrorAction Stop

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
		Btn2Bg       = [System.Drawing.Color]::FromArgb(250,251,250)
		Btn2Fg       = [System.Drawing.Color]::FromArgb(23,26,24)
		Btn2Border   = [System.Drawing.Color]::FromArgb(221,226,222)
		RowBg        = [System.Drawing.Color]::FromArgb(255,255,255)
		RowBorder    = [System.Drawing.Color]::FromArgb(221,226,222)
		Success      = [System.Drawing.Color]::FromArgb(57,118,63)
		Warning      = [System.Drawing.Color]::FromArgb(184,150,10)
		Error        = [System.Drawing.Color]::FromArgb(198,40,40)
		Credit       = [System.Drawing.Color]::FromArgb(168,172,168)
		AccentTxt    = [System.Drawing.Color]::FromArgb(255,255,255)
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
		Btn2Bg       = [System.Drawing.Color]::FromArgb(25,29,26)
		Btn2Fg       = [System.Drawing.Color]::FromArgb(198,201,198)
		Btn2Border   = [System.Drawing.Color]::FromArgb(41,46,42)
		RowBg        = [System.Drawing.Color]::FromArgb(18,22,20)
		RowBorder    = [System.Drawing.Color]::FromArgb(41,46,42)
		Success      = [System.Drawing.Color]::FromArgb(139,221,139)
		Warning      = [System.Drawing.Color]::FromArgb(232,212,77)
		Error        = [System.Drawing.Color]::FromArgb(239,83,80)
		Credit       = [System.Drawing.Color]::FromArgb(90,95,91)
		AccentTxt    = [System.Drawing.Color]::FromArgb(11,13,12)
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

$CurrentTheme = "Light"
$CurrentLang  = Get-SharedLang
$DefaultFont = Scale-Font 9

function Get-CapturesFolder {
	return Join-Path ([Environment]::GetFolderPath("MyVideos")) "Captures"
}

function Find-Captures {
	$Folder = Get-CapturesFolder
	if (-not (Test-Path $Folder)) { return @() }
	$Files = Get-ChildItem -Path $Folder -File -ErrorAction SilentlyContinue | Where-Object {
		($_.Extension -eq ".mp4" -or $_.Extension -eq ".png") -and ($_.Name -match "FiveM|RedM")
	}
	$Results = @()
	foreach ($F in $Files) {
		$Results += [PSCustomObject]@{
			FullPath   = $F.FullName
			FileName   = $F.Name
			Extension  = $F.Extension.ToLower()
			SizeMB     = [Math]::Round($F.Length / 1MB, 1)
			SizeBytes  = $F.Length
			Timestamp  = $F.LastWriteTime
		}
	}
	return @($Results | Sort-Object Timestamp -Descending)
}

function Get-CapturesDiskInfo {
	$Folder = Get-CapturesFolder
	$Root = [System.IO.Path]::GetPathRoot($Folder)
	$Drive = New-Object System.IO.DriveInfo($Root)
	return [PSCustomObject]@{ Free = $Drive.AvailableFreeSpace; Name = $Drive.Name }
}

function Format-Bytes($Bytes) {
	if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
	if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
	if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
	return "< 1 KB"
}

$Script:ThumbCacheDir = Join-Path $env:APPDATA "NFXS-Clips\thumbs"
$Script:ThumbMaxDim = 160

function Get-ThumbnailCachePath($Capture) {
	if (-not (Test-Path $Script:ThumbCacheDir)) {
		New-Item -ItemType Directory -Path $Script:ThumbCacheDir -Force | Out-Null
	}
	$Key = "$($Capture.FullPath)|$($Capture.Timestamp.Ticks)"
	$Md5 = [System.Security.Cryptography.MD5]::Create()
	$HashBytes = $Md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Key))
	$Hash = [System.BitConverter]::ToString($HashBytes) -replace '-', ''
	return Join-Path $Script:ThumbCacheDir "$Hash.png"
}

function Read-ImageNoLock($Path) {
	$Bytes = [System.IO.File]::ReadAllBytes($Path)
	$Ms = New-Object System.IO.MemoryStream(, $Bytes)
	return [System.Drawing.Image]::FromStream($Ms)
}

function New-PhotoThumbnail($Path, $MaxDim) {
	$Orig = Read-ImageNoLock $Path
	try {
		$Scale = [Math]::Min([double]$MaxDim / $Orig.Width, [double]$MaxDim / $Orig.Height)
		if ($Scale -gt 1) { $Scale = 1 }
		$W = [Math]::Max(1, [int]([Math]::Round($Orig.Width * $Scale)))
		$H = [Math]::Max(1, [int]([Math]::Round($Orig.Height * $Scale)))
		$Thumb = New-Object System.Drawing.Bitmap($W, $H)
		$Gr = [System.Drawing.Graphics]::FromImage($Thumb)
		$Gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
		$Gr.DrawImage($Orig, 0, 0, $W, $H)
		$Gr.Dispose()
		return $Thumb
	} finally {
		$Orig.Dispose()
	}
}

function New-VideoThumbnail($Path, $MaxDim) {
	$Hbm = [NFXThumb.ShellThumb]::GetHBitmap($Path, $MaxDim)
	if ($Hbm -eq [IntPtr]::Zero) { return $null }
	try {
		return [System.Drawing.Bitmap]::FromHbitmap($Hbm)
	} finally {
		[NFXThumb.ShellThumb]::FreeHBitmap($Hbm)
	}
}

function Get-Thumbnail($Capture) {
	$CachePath = Get-ThumbnailCachePath $Capture
	if (Test-Path $CachePath) {
		try { return Read-ImageNoLock $CachePath } catch { }
	}
	$Thumb = $null
	try {
		if ($Capture.Extension -eq ".png") {
			$Thumb = New-PhotoThumbnail $Capture.FullPath $Script:ThumbMaxDim
		} else {
			$Thumb = New-VideoThumbnail $Capture.FullPath $Script:ThumbMaxDim
		}
	} catch {
	}
	if ($Thumb) {
		try { $Thumb.Save($CachePath, [System.Drawing.Imaging.ImageFormat]::Png) } catch { }
	}
	return $Thumb
}

function Get-CaptureContext($Capture) {
	$Title = $null
	$ParsedTimestamp = $null

	if ($Capture.Extension -eq ".mp4") {
		if ($Capture.FileName -match '^(.*) (\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2})\.mp4$') {
			$Title = $Matches[1]
			try { $ParsedTimestamp = [DateTime]::ParseExact($Matches[2], "yyyy-MM-dd HH-mm-ss", $null) } catch { }
		}
	} elseif ($Capture.Extension -eq ".png") {
		if ($Capture.FileName -match '^(.*) (\d{2}_\d{2}_\d{4} \d{2}_\d{2}_\d{2})\.png$') {
			$Title = $Matches[1]
			try { $ParsedTimestamp = [DateTime]::ParseExact($Matches[2], "dd_MM_yyyy HH_mm_ss", $null) } catch { }
		}
	}

	$ServerName = $null
	if ($Title -and $Title -match '^(?:FiveM|RedM)\S*\s+by\s+Cfx\.re\s*-\s*(.+)$') {
		$ServerName = $Matches[1].Trim()
	}

	return [PSCustomObject]@{
		Title           = $Title
		ServerName      = $ServerName
		DisplayTitle    = if ($ServerName) { $ServerName } elseif ($Title) { $Title } else { $Capture.FileName }
		Timestamp       = if ($ParsedTimestamp) { $ParsedTimestamp } else { $Capture.Timestamp }
		TimestampParsed = ($ParsedTimestamp -ne $null)
	}
}

function Get-GameDVRStatus {
	$DvrEnabled = $null
	$AppCaptureEnabled = $null
	try { $DvrEnabled = (Get-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -ErrorAction Stop).GameDVR_Enabled } catch { }
	try { $AppCaptureEnabled = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -ErrorAction Stop).AppCaptureEnabled } catch { }
	$Enabled = ($DvrEnabled -eq 1) -or ($AppCaptureEnabled -eq 1)
	return [PSCustomObject]@{ Enabled = $Enabled; Detected = ($DvrEnabled -ne $null -or $AppCaptureEnabled -ne $null) }
}

$Strings = @{
	"pt" = @{
		Description         = "Encontra seus prints e clipes de FiveM/RedM já salvos pelo Windows - sem precisar vasculhar pasta nenhuma."
		ListHeader          = "Prints e clipes encontrados"
		NoCapturesTitle     = "Nenhum print ou clipe encontrado"
		NoCapturesDesc      = "Não encontramos prints ou clipes de FiveM/RedM na pasta de Capturas do Windows."
		DVRDisabledTitle    = "Gravação do Windows está desativada"
		DVRDisabledDesc     = "Ative em Configurações > Jogos > Capturas, ou use Win+Alt+G a qualquer momento para tentar salvar os últimos 30 segundos."
		DVREnabledText      = "Gravação do Windows está ativada - Win+Alt+G salva os últimos 30s, Win+Alt+PrtScn tira um print."
		StorageFreeFormat   = "{0} livres no disco {1}"
		TotalSizeFormat     = "{0} ocupados por prints e clipes de FiveM/RedM"
		GroupToday          = "Hoje"
		GroupYesterday      = "Ontem"
		TypeVideo           = "Vídeo"
		TypePrint           = "Print"
		MinutesAgoFormat    = "Há {0} minutos"
		MinuteAgoSingular   = "Há 1 minuto"
		HoursAgoFormat      = "Há {0} horas"
		HourAgoSingular     = "Há 1 hora"
		DaysAgoFormat       = "Há {0} dias"
		DayAgoSingular      = "Há 1 dia"
		OpenFolderButton    = "Abrir pasta de capturas"
		RefreshButton       = "Verificar novamente"
		OpenGameBarButton   = "Abrir gravador do Windows (Win+G)"
		CloseButton         = "Fechar"
		OpenErrorText       = "Não foi possível abrir esse arquivo."
		UpdateAvailableFormat = "Nova versão disponível (v{0}) - clique aqui"
		UpdateOk            = "Você está com a versão mais recente."
		NewsHeader          = "Obrigado por usar nosso app, acesse:"
		FreeLabel           = "Produto gratuito disponibilizado por NunoFoxs"
	}
	"en" = @{
		Description         = "Finds your FiveM/RedM screenshots and clips already saved by Windows - no need to hunt through any folder."
		ListHeader          = "Screenshots and clips found"
		NoCapturesTitle     = "No screenshots or clips found"
		NoCapturesDesc      = "We couldn't find any FiveM/RedM screenshots or clips in the Windows Captures folder."
		DVRDisabledTitle    = "Windows recording is turned off"
		DVRDisabledDesc     = "Turn it on in Settings > Gaming > Captures, or use Win+Alt+G anytime to try saving the last 30 seconds."
		DVREnabledText      = "Windows recording is on - Win+Alt+G saves the last 30s, Win+Alt+PrtScn takes a screenshot."
		StorageFreeFormat   = "{0} free on drive {1}"
		TotalSizeFormat     = "{0} used by FiveM/RedM screenshots and clips"
		GroupToday          = "Today"
		GroupYesterday      = "Yesterday"
		TypeVideo           = "Video"
		TypePrint           = "Screenshot"
		MinutesAgoFormat    = "{0} minutes ago"
		MinuteAgoSingular   = "1 minute ago"
		HoursAgoFormat      = "{0} hours ago"
		HourAgoSingular     = "1 hour ago"
		DaysAgoFormat       = "{0} days ago"
		DayAgoSingular      = "1 day ago"
		OpenFolderButton    = "Open captures folder"
		RefreshButton       = "Check again"
		OpenGameBarButton   = "Open Windows Game Bar (Win+G)"
		CloseButton         = "Close"
		OpenErrorText       = "Couldn't open that file."
		UpdateAvailableFormat = "New version available (v{0}) - click here"
		UpdateOk            = "You have the latest version."
		NewsHeader          = "Thanks for using our app, check out:"
		FreeLabel           = "Free product provided by NunoFoxs"
	}
	"es" = @{
		Description         = "Encuentra tus prints y clips de FiveM/RedM ya guardados por Windows - sin buscar en ninguna carpeta."
		ListHeader          = "Prints y clips encontrados"
		NoCapturesTitle     = "No se encontraron prints ni clips"
		NoCapturesDesc      = "No encontramos prints ni clips de FiveM/RedM en la carpeta de Capturas de Windows."
		DVRDisabledTitle    = "La grabación de Windows está desactivada"
		DVRDisabledDesc     = "Actívala en Configuración > Juegos > Capturas, o usa Win+Alt+G en cualquier momento para intentar guardar los últimos 30 segundos."
		DVREnabledText      = "La grabación de Windows está activada - Win+Alt+G guarda los últimos 30s, Win+Alt+PrtScn toma un print."
		StorageFreeFormat   = "{0} libres en el disco {1}"
		TotalSizeFormat     = "{0} ocupados por prints y clips de FiveM/RedM"
		GroupToday          = "Hoy"
		GroupYesterday      = "Ayer"
		TypeVideo           = "Video"
		TypePrint           = "Print"
		MinutesAgoFormat    = "Hace {0} minutos"
		MinuteAgoSingular   = "Hace 1 minuto"
		HoursAgoFormat      = "Hace {0} horas"
		HourAgoSingular     = "Hace 1 hora"
		DaysAgoFormat       = "Hace {0} días"
		DayAgoSingular      = "Hace 1 día"
		OpenFolderButton    = "Abrir carpeta de capturas"
		RefreshButton       = "Verificar de nuevo"
		OpenGameBarButton   = "Abrir el grabador de Windows (Win+G)"
		CloseButton         = "Cerrar"
		OpenErrorText       = "No fue posible abrir ese archivo."
		UpdateAvailableFormat = "Nueva versión disponible (v{0}) - haz clic aquí"
		UpdateOk            = "Tienes la versión más reciente."
		NewsHeader          = "Gracias por usar nuestra app, visita:"
		FreeLabel           = "Producto gratuito ofrecido por NunoFoxs"
	}
	"de" = @{
		Description         = "Findet deine FiveM/RedM-Screenshots und -Clips, die Windows bereits gespeichert hat - kein Durchsuchen von Ordnern nötig."
		ListHeader          = "Gefundene Screenshots und Clips"
		NoCapturesTitle     = "Keine Screenshots oder Clips gefunden"
		NoCapturesDesc      = "Wir konnten keine FiveM/RedM-Screenshots oder -Clips im Windows-Aufnahmeordner finden."
		DVRDisabledTitle    = "Die Windows-Aufnahme ist deaktiviert"
		DVRDisabledDesc     = "Aktiviere sie unter Einstellungen > Spielen > Aufnahmen, oder nutze jederzeit Win+Alt+G, um die letzten 30 Sekunden zu speichern."
		DVREnabledText      = "Die Windows-Aufnahme ist aktiviert - Win+Alt+G speichert die letzten 30s, Win+Alt+PrtScn macht einen Screenshot."
		StorageFreeFormat   = "{0} frei auf Laufwerk {1}"
		TotalSizeFormat     = "{0} belegt durch FiveM/RedM-Screenshots und -Clips"
		GroupToday          = "Heute"
		GroupYesterday      = "Gestern"
		TypeVideo           = "Video"
		TypePrint           = "Screenshot"
		MinutesAgoFormat    = "Vor {0} Minuten"
		MinuteAgoSingular   = "Vor 1 Minute"
		HoursAgoFormat      = "Vor {0} Stunden"
		HourAgoSingular     = "Vor 1 Stunde"
		DaysAgoFormat       = "Vor {0} Tagen"
		DayAgoSingular      = "Vor 1 Tag"
		OpenFolderButton    = "Aufnahmeordner öffnen"
		RefreshButton       = "Erneut prüfen"
		OpenGameBarButton   = "Windows Game Bar öffnen (Win+G)"
		CloseButton         = "Schließen"
		OpenErrorText       = "Diese Datei konnte nicht geöffnet werden."
		UpdateAvailableFormat = "Neue Version verfügbar (v{0}) - hier klicken"
		UpdateOk            = "Du hast die neueste Version."
		NewsHeader          = "Danke, dass du unsere App nutzt, schau vorbei:"
		FreeLabel           = "Kostenloses Produkt bereitgestellt von NunoFoxs"
	}
	"fr" = @{
		Description         = "Trouve tes captures d'écran et clips FiveM/RedM déjà enregistrés par Windows - sans avoir à fouiller un dossier."
		ListHeader          = "Captures et clips trouvés"
		NoCapturesTitle     = "Aucune capture ni clip trouvé"
		NoCapturesDesc      = "Nous n'avons trouvé aucune capture ni clip FiveM/RedM dans le dossier Captures de Windows."
		DVRDisabledTitle    = "L'enregistrement Windows est désactivé"
		DVRDisabledDesc     = "Activez-le dans Paramètres > Jeux > Captures, ou utilisez Win+Alt+G à tout moment pour enregistrer les 30 dernières secondes."
		DVREnabledText      = "L'enregistrement Windows est activé - Win+Alt+G enregistre les 30 dernières secondes, Win+Alt+PrtScn prend une capture."
		StorageFreeFormat   = "{0} libres sur le disque {1}"
		TotalSizeFormat     = "{0} occupés par des captures et clips FiveM/RedM"
		GroupToday          = "Aujourd'hui"
		GroupYesterday      = "Hier"
		TypeVideo           = "Vidéo"
		TypePrint           = "Capture"
		MinutesAgoFormat    = "Il y a {0} minutes"
		MinuteAgoSingular   = "Il y a 1 minute"
		HoursAgoFormat      = "Il y a {0} heures"
		HourAgoSingular     = "Il y a 1 heure"
		DaysAgoFormat       = "Il y a {0} jours"
		DayAgoSingular      = "Il y a 1 jour"
		OpenFolderButton    = "Ouvrir le dossier des captures"
		RefreshButton       = "Vérifier à nouveau"
		OpenGameBarButton   = "Ouvrir la barre de jeu Windows (Win+G)"
		CloseButton         = "Fermer"
		OpenErrorText       = "Impossible d'ouvrir ce fichier."
		UpdateAvailableFormat = "Nouvelle version disponible (v{0}) - cliquez ici"
		UpdateOk            = "Vous avez la dernière version."
		NewsHeader          = "Merci d'utiliser notre application, découvrez :"
		FreeLabel           = "Produit gratuit proposé par NunoFoxs"
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

$Script:Captures = @(Find-Captures)
$Script:DVRStatus = Get-GameDVRStatus
$Script:MaxDisplayCaptures = 5

$Script:ThumbQueue = New-Object System.Collections.Generic.Queue[object]
$Script:ThumbTimer = New-Object System.Windows.Forms.Timer
$Script:ThumbTimer.Interval = 15
$Script:ThumbTimer.Add_Tick({
	if ($Script:ThumbQueue.Count -eq 0) { $Script:ThumbTimer.Stop(); return }
	$Item = $Script:ThumbQueue.Dequeue()
	if (-not $Item.PictureBox.IsDisposed) {
		$Thumb = Get-Thumbnail $Item.Capture
		if ($Thumb -and -not $Item.PictureBox.IsDisposed) {
			$Item.PictureBox.Image = $Thumb
		}
	}
})

$IconPath = Join-Path (Split-Path $PSScriptRoot -Parent) "NFXS.ico"

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "NFXS Clips"
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
$HeaderPanel.Height = Scale-Val 76
$Form.Controls.Add($HeaderPanel)

$TitleLabel = New-Object System.Windows.Forms.Label
$TitleLabel.Text = "NFXS | CLIPS"
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

function Build-ListView {
	$T = $Themes[$CurrentTheme]
	$S = $Strings[$CurrentLang]
	$Accent = Get-SharedAccentColor $CurrentTheme
	$Script:ThumbTimer.Stop()
	$Script:ThumbQueue.Clear()
	$ContentPanel.Controls.Clear()
	$ContentPanel.BackColor = $T.FormBg
	$Y = (Scale-Val 12)
	$Width = 320

	function Add-WrappedLabel($Text, $Font, $Color, $YPos) {
		$L = New-Object System.Windows.Forms.Label
		$L.Text = $Text
		$L.ForeColor = $Color
		$L.Font = $Font
		$L.AutoSize = $false
		$Measured = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font, (Scale-Size $Width 0), [System.Windows.Forms.TextFormatFlags]::WordBreak)
		$L.Size = New-Object System.Drawing.Size((Scale-Val $Width), ($Measured.Height + (Scale-Val 6)))
		$L.Location = New-Object System.Drawing.Point((Scale-Val 18), $YPos)
		$ContentPanel.Controls.Add($L)
		return $YPos + $L.Height + (Scale-Val 4)
	}

	$DVRFont = Scale-Font 8.5
	if ($Script:DVRStatus.Detected -and -not $Script:DVRStatus.Enabled) {
		$Y = Add-WrappedLabel $S.DVRDisabledTitle (Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)) $T.Warning $Y
		$Y = Add-WrappedLabel $S.DVRDisabledDesc $DVRFont $T.TextSoft $Y
	} else {
		$Y = Add-WrappedLabel $S.DVREnabledText $DVRFont $T.Success $Y
	}
	$Y += (Scale-Val 6)
	$Disk = Get-CapturesDiskInfo
	$TotalBytes = ($Script:Captures | Measure-Object -Property SizeBytes -Sum).Sum
	if (-not $TotalBytes) { $TotalBytes = 0 }
	$StorageFont = Scale-Font 8.5
	$Y = Add-WrappedLabel ($S.StorageFreeFormat -f (Format-Bytes $Disk.Free), $Disk.Name) $StorageFont $T.TextSoft $Y
	$Y = Add-WrappedLabel ($S.TotalSizeFormat -f (Format-Bytes $TotalBytes)) $StorageFont $T.TextSoft $Y
	$Y += (Scale-Val 10)
	$HeaderLbl = New-Object System.Windows.Forms.Label
	$HeaderLbl.Text = $S.ListHeader
	$HeaderLbl.Font = Scale-Font 10 ([System.Drawing.FontStyle]::Bold)
	$HeaderLbl.ForeColor = $T.Text
	$HeaderLbl.AutoSize = $true
	$HeaderLbl.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$ContentPanel.Controls.Add($HeaderLbl)
	$Y += (Scale-Val 30)
	if ($Script:Captures.Count -eq 0) {
		$NoTitle = New-Object System.Windows.Forms.Label
		$NoTitle.Text = $S.NoCapturesTitle
		$NoTitle.Font = Scale-Font 10 ([System.Drawing.FontStyle]::Bold)
		$NoTitle.ForeColor = $T.Text
		$NoTitle.AutoSize = $true
		$NoTitle.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
		$ContentPanel.Controls.Add($NoTitle)
		$Y += (Scale-Val 26)
		$Y = Add-WrappedLabel $S.NoCapturesDesc $DVRFont $T.TextSoft $Y
		$Y += (Scale-Val 10)
	} else {
		$LastGroup = $null
		foreach ($C in ($Script:Captures | Select-Object -First $Script:MaxDisplayCaptures)) {
			$Ctx = Get-CaptureContext $C
			$Group = Get-DateGroupLabel $C.Timestamp $CurrentLang
			if ($Group -ne $LastGroup) {
				$GroupLbl = New-Object System.Windows.Forms.Label
				$GroupLbl.Text = $Group
				$GroupLbl.ForeColor = $T.TextSoft
				$GroupLbl.Font = Scale-Font 8.5 ([System.Drawing.FontStyle]::Bold)
				$GroupLbl.AutoSize = $true
				$GroupLbl.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
				$ContentPanel.Controls.Add($GroupLbl)
				$Y += (Scale-Val 24)
				$LastGroup = $Group
			}

			$Row = New-Object System.Windows.Forms.Panel
			$Row.Size = Scale-Size $Width 72
			$Row.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
			$Row.BackColor = $T.RowBg
			$Row.Cursor = "Hand"
			$Row.Tag = $C.FullPath

			$Border = New-Object System.Windows.Forms.Panel
			$Border.Size = Scale-Size $Width 1
			$Border.Location = Scale-Point 0 71
			$Border.BackColor = $T.RowBorder
			$Row.Controls.Add($Border)

			$ThumbBox = New-Object System.Windows.Forms.PictureBox
			$ThumbBox.Size = Scale-Size 80 45
			$ThumbBox.Location = Scale-Point 4 14
			$ThumbBox.SizeMode = "Zoom"
			$ThumbBox.BackColor = $T.RowBg
			$Row.Controls.Add($ThumbBox)
			$CachePath = Get-ThumbnailCachePath $C
			if (Test-Path $CachePath) {
				try { $ThumbBox.Image = Read-ImageNoLock $CachePath } catch { }
			} else {
				$Script:ThumbQueue.Enqueue([PSCustomObject]@{ Capture = $C; PictureBox = $ThumbBox })
			}

			$TextX = 92
			$TypeText = if ($C.Extension -eq ".mp4") { $S.TypeVideo } else { $S.TypePrint }
			$TitleLbl2 = New-Object System.Windows.Forms.Label
			$TitleLbl2.Text = "$($Ctx.DisplayTitle)  ·  $TypeText"
			$TitleLbl2.Font = Scale-Font 9.5 ([System.Drawing.FontStyle]::Bold)
			$TitleLbl2.ForeColor = $Accent
			$TitleLbl2.AutoSize = $true
			$TitleLbl2.Location = Scale-Point $TextX 6
			$Row.Controls.Add($TitleLbl2)

			$InfoLbl = New-Object System.Windows.Forms.Label
			$InfoLbl.Text = "$(Get-RelativeTimeText $C.Timestamp $CurrentLang) - $($C.Timestamp.ToString('dd/MM/yyyy HH:mm:ss'))"
			$InfoLbl.ForeColor = $T.TextSoft
			$InfoLbl.Font = Scale-Font 8
			$InfoLbl.AutoSize = $true
			$InfoLbl.Location = Scale-Point $TextX 28
			$Row.Controls.Add($InfoLbl)

			$SizeLbl = New-Object System.Windows.Forms.Label
			$SizeLbl.Text = "$($C.SizeMB) MB"
			$SizeLbl.ForeColor = $T.TextSoft
			$SizeLbl.Font = Scale-Font 8
			$SizeLbl.AutoSize = $true
			$SizeLbl.Location = Scale-Point $TextX 48
			$Row.Controls.Add($SizeLbl)

			$OpenClick = {
				try { Start-Process $Row.Tag } catch {
					[System.Windows.Forms.MessageBox]::Show($Strings[$CurrentLang].OpenErrorText) | Out-Null
				}
			}.GetNewClosure()
			$Row.Add_Click($OpenClick)
			foreach ($Ctrl in $Row.Controls) {
				if ($Ctrl -ne $Border) {
					$Ctrl.Cursor = "Hand"
					$Ctrl.Add_Click({ Start-Process $Row.Tag }.GetNewClosure())
				}
			}

			$ContentPanel.Controls.Add($Row)
			$Y += (Scale-Val 76)
		}
	}

	$Y += (Scale-Val 8)
	$OpenFolderBtn = New-Object System.Windows.Forms.Button
	$OpenFolderBtn.Text = $S.OpenFolderButton
	$OpenFolderBtn.Size = Scale-Size 152 34
	$OpenFolderBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$OpenFolderBtn.FlatStyle = "Flat"
	$OpenFolderBtn.FlatAppearance.BorderSize = 0
	$OpenFolderBtn.Cursor = "Hand"
	$OpenFolderBtn.BackColor = $Accent
	$OpenFolderBtn.ForeColor = $T.AccentTxt
	$OpenFolderBtn.Font = Scale-Font 9 ([System.Drawing.FontStyle]::Bold)
	$OpenFolderBtn.Add_Click({
		$Folder = Get-CapturesFolder
		if (Test-Path $Folder) { Start-Process "explorer.exe" -ArgumentList "`"$Folder`"" }
	})
	$ContentPanel.Controls.Add($OpenFolderBtn)

	$RefreshBtn = New-Object System.Windows.Forms.Button
	$RefreshBtn.Text = $S.RefreshButton
	$RefreshBtn.Size = Scale-Size 152 34
	$RefreshBtn.Location = New-Object System.Drawing.Point((Scale-Val 186), $Y)
	$RefreshBtn.FlatStyle = "Flat"
	$RefreshBtn.FlatAppearance.BorderSize = 1
	$RefreshBtn.Cursor = "Hand"
	$RefreshBtn.BackColor = $T.Btn2Bg
	$RefreshBtn.ForeColor = $T.Btn2Fg
	$RefreshBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$RefreshBtn.Add_Click({
		$Script:Captures = @(Find-Captures)
		$Script:DVRStatus = Get-GameDVRStatus
		Build-ListView
	})
	$ContentPanel.Controls.Add($RefreshBtn)
	$Y += (Scale-Val 34)

	$Y += (Scale-Val 10)
	$GameBarBtn = New-Object System.Windows.Forms.Button
	$GameBarBtn.Text = $S.OpenGameBarButton
	$GameBarBtn.Size = Scale-Size 320 34
	$GameBarBtn.Location = New-Object System.Drawing.Point((Scale-Val 18), $Y)
	$GameBarBtn.FlatStyle = "Flat"
	$GameBarBtn.FlatAppearance.BorderSize = 1
	$GameBarBtn.Cursor = "Hand"
	$GameBarBtn.BackColor = $T.Btn2Bg
	$GameBarBtn.ForeColor = $T.Btn2Fg
	$GameBarBtn.FlatAppearance.BorderColor = $T.Btn2Border
	$GameBarBtn.Add_Click({
		$Form.WindowState = "Minimized"
		Get-Process | Where-Object { $_.Id -ne $PID -and $_.MainWindowTitle -like "NFXS*" -and $_.MainWindowHandle -ne [IntPtr]::Zero } | ForEach-Object {
			[NFX.Input]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
		}
		$Script:GameBarTimer = New-Object System.Windows.Forms.Timer
		$Script:GameBarTimer.Interval = 400
		$Script:GameBarTimer.Add_Tick({
			$Script:GameBarTimer.Stop()
			$VK_LWIN = 0x5B
			$VK_G = 0x47
			$KEYUP = 0x2
			[NFX.Input]::keybd_event($VK_LWIN, 0, 0, [UIntPtr]::Zero)
			[NFX.Input]::keybd_event($VK_G, 0, 0, [UIntPtr]::Zero)
			[NFX.Input]::keybd_event($VK_G, 0, $KEYUP, [UIntPtr]::Zero)
			[NFX.Input]::keybd_event($VK_LWIN, 0, $KEYUP, [UIntPtr]::Zero)
		})
		$Script:GameBarTimer.Start()
	})
	$ContentPanel.Controls.Add($GameBarBtn)
	$Y += (Scale-Val 34)

	$ContentPanel.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($Y + (Scale-Val 10)))

	if ($Script:ThumbQueue.Count -gt 0) { $Script:ThumbTimer.Start() }
}

function Set-Theme($Name) {
	$Script:CurrentTheme = $Name
	$T = $Themes[$Name]
	$Accent = Get-SharedAccentColor $Name

	$Form.BackColor = $T.FormBg
	$HeaderPanel.BackColor = $T.HeaderBg
	$TitleLabel.ForeColor = $T.HeaderTitle
	$SubtitleLabel.ForeColor = $T.HeaderSub
	$FooterPanel.BackColor = $T.FormBg
	$ContentPanel.BackColor = $T.FormBg
	$CreditLabel.ForeColor = $T.Credit
	$NewsLabel.LinkColor = $Accent
	$NewsLabel.ActiveLinkColor = $Accent
	$NewsLabel.VisitedLinkColor = $Accent

	if ($T.DarkTitlebar -and $Form.Handle) {
		$Val = 1
		[NFX.Dwm]::DwmSetWindowAttribute($Form.Handle, 20, [ref]$Val, 4) | Out-Null
	}
	Build-ListView
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
	Build-ListView
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
Set-AutoEllipsisRecursive $HeaderPanel
Set-AutoEllipsisRecursive $FooterPanel

$Form.Add_Shown({
	$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	$ContentPanel.BeginInvoke([Action]{
		$ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0,0)
	}) | Out-Null
})

[System.Windows.Forms.Application]::Run($Form)
